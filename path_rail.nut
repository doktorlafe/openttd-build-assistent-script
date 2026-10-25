/* Rail route search callbacks for AStar.
 * A node is (tile, arrival direction, last turn). Two turns the same way in a
 * row are forbidden, because the track pieces would not connect. Diagonals
 * (left, right, left ...) are cheap. A sharp bend - straight, one curve piece,
 * straight again - costs extra, because trains slow down a lot there; the
 * search prefers a smooth bend through a short diagonal instead.
 *
 * One tile is visited in up to 12 states, so everything we learn about a tile
 * is cached in the job (job.cc, job.xc, job.bc, job.tc). */

/* Base cost to lay track on a tile, or -1. Cached. */
function PathRail_Cost(job, t)
{
  if (job.cc.rawin(t)) return job.cc.rawget(t);
  local c = -1;
  if (!job.blocked.rawin(t) && !U_IsSpecial(t) && GSTile.IsBuildable(t)) {
    c = U_IsFlat(t) ? 5 : 8;
    // second track: right next to the first is very cheap, anywhere else expensive,
    // so the two tracks run side by side and take as little land as possible
    if (job.rawin("near") && job.near.len() > 0) c = job.near.rawin(t) ? 1 : c + 6;
  }
  job.cc.rawset(t, c);
  return c;
}

function PathRail_Flat(job, t)
{
  local k = -1 - t;   // negative keys in the same cache
  if (job.cc.rawin(k)) return job.cc.rawget(k);
  local f = U_IsFlat(t);
  job.cc.rawset(k, f);
  return f;
}

/* Rail crossing a road tile in direction i (level crossing). Cached per axis. */
function PathRail_CanCross(job, t, i)
{
  local key = t * 2 + (i % 2);
  if (job.xc.rawin(key)) return job.xc.rawget(key);
  local ok = false;
  if (!job.blocked.rawin(t) && U_IsFlat(t) && !U_IsSpecial(t)) {
    if (GSRoad.IsRoadTile(t) && !GSRoad.IsRoadStationTile(t) && !GSRoad.IsRoadDepotTile(t)) {
      // level crossing: the road must not run along our direction
      ok = true;
      local a = U_Step(t, i), b = U_Step(t, (i + 2) % 4);
      if (a >= 0 && GSRoad.AreRoadTilesConnected(t, a)) ok = false;
      if (b >= 0 && GSRoad.AreRoadTilesConnected(t, b)) ok = false;
    } else if (GSRail.IsRailTile(t) && !GSRail.IsRailStationTile(t) && !GSRail.IsRailDepotTile(t) &&
               GSTile.GetOwner(t) == job.me && GSRail.GetRailType(t) == job.rail) {
      // diamond crossing over our own straight track at a right angle, without signals
      local need = (i % 2 == 0) ? GSRail.RAILTRACK_NW_SE : GSRail.RAILTRACK_NE_SW;
      if (GSRail.GetRailTracks(t) == need) {
        local s1 = U_Step(t, (i + 1) % 4), s2 = U_Step(t, (i + 3) % 4);
        ok = s1 >= 0 && s2 >= 0 &&
             GSRail.GetSignalType(t, s1) == GSRail.SIGNALTYPE_NONE &&
             GSRail.GetSignalType(t, s2) == GSRail.SIGNALTYPE_NONE;
      }
    }
  }
  job.xc.rawset(key, ok);
  return ok;
}

function PathRail_IsRoad(job, t)
{
  local k = -1 - t;
  if (job.xc.rawin(k)) return job.xc.rawget(k);
  local r = GSRoad.IsRoadTile(t);
  job.xc.rawset(k, r);
  return r;
}

/* Bridge from tile in direction i: [end, len] or null. Cached. */
function PathRail_Bridge(job, tile, i)
{
  local key = tile * 4 + i;
  if (job.bc.rawin(key)) return job.bc.rawget(key);
  local res = null;
  if (GSTile.IsBuildable(tile) && !job.blocked.rawin(tile)) {
    for (local len = 2; len <= job.max_br; len++) {
      local e = U_StepN(tile, i, len);
      if (e < 0) break;
      if (job.blocked.rawin(e) || !GSTile.IsBuildable(e)) continue;
      if (U_TestBridge(GSVehicle.VT_RAIL, tile, e)) res = [e, len];
      break;
    }
  }
  job.bc.rawset(key, res);
  return res;
}

/* Tunnel from tile: [other end, direction, len] or null. Cached. */
function PathRail_Tunnel(job, tile)
{
  if (job.tc.rawin(tile)) return job.tc.rawget(tile);
  local res = null;
  if (U_IsInclined(tile) && GSTile.IsBuildable(tile)) {
    local other = GSTunnel.GetOtherTunnelEnd(tile);
    if (GSMap.IsValidTile(other) && other != tile && U_SameAxis(tile, other)) {
      local len = GSMap.DistanceManhattan(tile, other);
      if (len >= 2 && len <= job.max_tu && !job.blocked.rawin(other) && U_TestTunnel(GSVehicle.VT_RAIL, tile))
        res = [other, U_DirOf(tile, other), len];
    }
  }
  job.tc.rawset(tile, res);
  return res;
}

function PathRail_Nb(job, cur, kind)
{
  local tile = K_Tile(cur), dir = K_Dir(cur), last = K_Turn(cur);
  local out = [];
  // no turning on slopes, crossings or after a bridge/tunnel
  local straight = kind != 0 || !PathRail_Flat(job, tile) || PathRail_IsRoad(job, tile) || GSRail.IsRailTile(tile);

  for (local i = 0; i < 4; i++) {
    if (i == (dir + 2) % 4) continue;
    local turn = 0;
    if (i == (dir + 1) % 4) turn = 1;
    else if (i == (dir + 3) % 4) turn = 2;
    if (straight && turn != 0) continue;
    local side = K_Side(last);
    if (turn != 0 && turn == side) continue;
    // extra cost: start of a bend 2, diagonal continues 1, straight right after a single curve piece 6
    local extra = 0, state = turn;
    if (turn != 0) {
      if (side != 0) { state = turn + 2; extra = 1; } else extra = 2;
    } else if (last == 1 || last == 2) {
      extra = 6;
    }
    local n = U_Step(tile, i);
    if (n < 0) continue;
    if (n == job.goal_tile) {
      if (i == job.goal_dir && turn == 0) out.append([K_Make(n, i, 0), 1 + extra, 0]);
      continue;
    }
    local c = PathRail_Cost(job, n);
    if (c < 0 && turn == 0 && PathRail_CanCross(job, n, i)) c = 20;   // level crossings slow trains and cause crashes
    if (c >= 0) {
      out.append([K_Make(n, i, state), c + extra, 0]);
      continue;
    }
    // blocked straight ahead: bridge with its head on this tile
    if (job.allow_br && kind == 0 && turn == 0) {
      local b = PathRail_Bridge(job, tile, i);
      if (b != null) out.append([K_Make(b[0], i, 0), 12 + b[1] * 8, 1]);
    }
  }

  if (job.allow_tu && kind == 0) {
    local tu = PathRail_Tunnel(job, tile);
    if (tu != null && tu[1] == dir) out.append([K_Make(tu[0], tu[1], 0), 12 + tu[2] * 10, 2]);
  }
  return out;
}

/* Can the search reach the goal tile at all? The last step must come
 * straight from the tile in front of it. */
function PathRail_GoalReachable(job)
{
  local back = (job.goal_dir + 2) % 4;
  local t = U_Step(job.goal_tile, back);
  if (t < 0) return false;
  return PathRail_Cost(job, t) >= 0 || PathRail_CanCross(job, t, job.goal_dir);
}

/* Goal: the station entry, or (for a part of a long route) any tile near the
 * waypoint that was not reached over a bridge or tunnel. */
function PathRail_Goal(job, k, kind)
{
  if (job.wp >= 0) return kind == 0 && GSMap.DistanceManhattan(K_Tile(k), job.wp) <= job.wp_tol;
  return K_Tile(k) == job.goal_tile && K_Dir(k) == job.goal_dir;
}

/* More than the real minimum (5 per tile): the search goes straight for the
 * target and examines far fewer tiles. job.hw comes from the route_quality
 * setting: 8 = fast, 7 = balanced, 6 = closer to the cheapest route. */
function PathRail_H(job, k)
{
  return job.hw * GSMap.DistanceManhattan(K_Tile(k), job.wp >= 0 ? job.wp : job.goal_tile);
}

/* Build actions for one track. first/last are the station front tiles
 * before and after the path. Heads of bridges and tunnels get no track piece. */
function PathRail_Actions(path, first, last, specials, pieces)
{
  local t = path.tiles, k = path.kinds;
  local heads = {};
  for (local j = 1; j < t.len(); j++) {
    if (k[j] == 1) {
      specials.append({ op = "rail_bridge", a = t[j - 1], b = t[j], id = U_PickBridge(GSMap.DistanceManhattan(t[j - 1], t[j]) + 1) });
    } else if (k[j] == 2) {
      specials.append({ op = "rail_tunnel", a = t[j - 1] });
    }
    if (k[j] != 0) {
      heads.rawset(t[j - 1], true);
      heads.rawset(t[j], true);
    }
  }
  local full = [first];
  foreach (x in t) full.append(x);
  full.append(last);
  for (local j = 1; j + 1 < full.len(); j++) {
    if (heads.rawin(full[j])) continue;
    pieces.append({ op = "rail", p = full[j - 1], t = full[j], n = full[j + 1] });
  }
}

/* Can a signal go on path tile j? Plain track only (straight or one curve
 * piece, so diagonal stretches get signals too): no bridge or tunnel heads,
 * no level or diamond crossings. */
function PathRail_SignalOk(t, k, j)
{
  if (k[j] != 0 || k[j + 1] != 0 || k[j - 1] != 0) return false;
  if (GSMap.DistanceManhattan(t[j - 1], t[j]) != 1 || GSMap.DistanceManhattan(t[j], t[j + 1]) != 1) return false;
  if (GSRoad.IsRoadTile(t[j]) || GSRail.IsRailTile(t[j])) return false;   // crossings (checked before building)
  return true;
}

/* One-way path signals about every `spacing` tiles. forward = trains run
 * along the path. A tile that cannot hold a signal moves it further on. */
function PathRail_Signals(path, spacing, forward, out)
{
  local t = path.tiles, k = path.kinds;
  local j = 2;
  while (j + 2 < t.len()) {
    if (!PathRail_SignalOk(t, k, j)) { j++; continue; }
    local front = forward ? t[j + 1] : t[j - 1];
    out.append({ op = "signal", t = t[j], f = front, kind = "oneway" });
    j += spacing;
  }
}

/* Entry signal for double track: one-way on the incoming row, facing the
 * switches, so arriving trains reserve a free platform before the switches. */
function PathRail_StationSignals(sp, in_row, out)
{
  out.append({ op = "signal", t = sp.G[in_row], f = sp.F[in_row], kind = "oneway" });
}
