/* Road route search callbacks for AStar.
 * Existing road is cheap, new road costs more, slopes and turns a bit more.
 * Water, rails and roads in the way can be bridged, hills tunnelled.
 * Level crossings are allowed over a single straight rail track. */

function PathRoad_Cost(job, t)
{
  if (job.blocked.rawin(t)) return -1;
  if (U_IsSpecial(t)) return -1;
  if (GSRoad.IsRoadStationTile(t) || GSRoad.IsRoadDepotTile(t)) return -1;
  if (GSRoad.IsRoadTile(t)) return 1;
  if (GSTile.IsBuildable(t)) return U_IsFlat(t) ? 4 : 7;
  return -1;
}

/* Road crossing a rail tile in direction i. */
function PathRoad_CanCross(t, i)
{
  if (!GSRail.IsRailTile(t) || !U_IsFlat(t) || U_IsSpecial(t)) return false;
  if (GSRail.IsRailStationTile(t) || GSRail.IsRailDepotTile(t)) return false;
  local need = (i % 2 == 0) ? GSRail.RAILTRACK_NW_SE : GSRail.RAILTRACK_NE_SW;
  return GSRail.GetRailTracks(t) == need;
}

function PathRoad_Nb(job, cur, kind)
{
  local tile = K_Tile(cur), dir = K_Dir(cur);
  local out = [];
  local on_road = GSRoad.IsRoadTile(tile);
  // after a bridge/tunnel, on a slope or on a level crossing: go straight on
  local straight = kind != 0 || GSRail.IsRailTile(tile) || GSRoad.IsRoadStationTile(tile) ||
                   (dir != 4 && !on_road && !U_IsFlat(tile));

  for (local i = 0; i < 4; i++) {
    if (dir != 4 && i == (dir + 2) % 4) continue;
    if (straight && dir != 4 && i != dir) continue;
    local n = U_Step(tile, i);
    if (n < 0) continue;
    local turn = (dir != 4 && i != dir) ? 1 : 0;
    if (n == job.goal_tile) {
      out.append([K_Make(n, i, 0), 1 + turn, 0]);
      continue;
    }
    local c = PathRoad_Cost(job, n);
    if (c < 0 && PathRoad_CanCross(n, i)) c = 8;
    // straight through a drive-through stop that lies along our direction
    if (c < 0 && turn == 0 && !job.blocked.rawin(n) && GSRoad.IsDriveThroughRoadStationTile(n) &&
        (U_DirOf(n, GSRoad.GetRoadStationFrontTile(n)) % 2) == (i % 2)) c = 3;
    if (c >= 0) {
      out.append([K_Make(n, i, 0), c + turn, 0]);
      continue;
    }
    // an existing road bridge or tunnel starting right here: drive over / through it
    if (turn == 0 && U_IsSpecial(n) && GSTile.HasTransportType(n, GSTile.TRANSPORT_ROAD)) {
      local other = GSBridge.IsBridgeTile(n) ? GSBridge.GetOtherBridgeEnd(n) : GSTunnel.GetOtherTunnelEnd(n);
      if (GSMap.IsValidTile(other) && other != n && U_SameAxis(n, other) && U_DirOf(n, other) == i && !job.blocked.rawin(other)) {
        out.append([K_Make(other, i, 0), 2 + GSMap.DistanceManhattan(n, other), 3]);
        continue;
      }
    }
    // blocked: try a bridge with its head on this tile
    if (job.allow_br && kind == 0 && (dir == 4 || dir == i) && !on_road && GSTile.IsBuildable(tile) && !job.blocked.rawin(tile)) {
      for (local len = 2; len <= job.max_br; len++) {
        local e = U_StepN(tile, i, len);
        if (e < 0) break;
        if (job.blocked.rawin(e) || !GSTile.IsBuildable(e)) continue;
        if (U_TestBridge(GSVehicle.VT_ROAD, tile, e)) out.append([K_Make(e, i, 0), 10 + len * 6, 1]);
        break;
      }
    }
  }

  // tunnel from this tile
  if (job.allow_tu && kind == 0 && !on_road && U_IsInclined(tile) && GSTile.IsBuildable(tile)) {
    local other = GSTunnel.GetOtherTunnelEnd(tile);
    if (GSMap.IsValidTile(other) && other != tile && U_SameAxis(tile, other)) {
      local i2 = U_DirOf(tile, other);
      local len = GSMap.DistanceManhattan(tile, other);
      if (len >= 2 && len <= job.max_tu && (dir == 4 || dir == i2) && !job.blocked.rawin(other) &&
          U_TestTunnel(GSVehicle.VT_ROAD, tile))
        out.append([K_Make(other, i2, 0), 10 + len * 8, 2]);
    }
  }
  return out;
}

function PathRoad_Goal(job, k, kind)
{
  if (job.wp >= 0) return kind == 0 && GSMap.DistanceManhattan(K_Tile(k), job.wp) <= job.wp_tol;
  return K_Tile(k) == job.goal_tile;
}

function PathRoad_H(job, k)
{
  return 3 * GSMap.DistanceManhattan(K_Tile(k), job.wp >= 0 ? job.wp : job.goal_tile);
}

/* Turns a found path into build actions: bridges and tunnels first,
 * then the road pieces (so the road can attach to the bridge heads). */
function PathRoad_Actions(path, specials, pieces)
{
  local t = path.tiles, k = path.kinds;
  for (local j = 1; j < t.len(); j++) {
    if (k[j] == 1) {
      specials.append({ op = "road_bridge", a = t[j - 1], b = t[j], id = U_PickBridge(GSMap.DistanceManhattan(t[j - 1], t[j]) + 1) });
    } else if (k[j] == 3) {
      // existing bridge/tunnel: only connect the road to its entrance
      local entry = U_Step(t[j - 1], U_DirOf(t[j - 1], t[j]));
      if (entry >= 0) pieces.append({ op = "road", a = t[j - 1], b = entry });
    } else if (k[j] == 2) {
      specials.append({ op = "road_tunnel", a = t[j - 1] });
    } else {
      pieces.append({ op = "road", a = t[j - 1], b = t[j] });
    }
  }
}
