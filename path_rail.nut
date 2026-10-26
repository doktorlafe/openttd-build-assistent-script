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
    // costs stay below the search estimate (7 per tile, see PathRail_H): if a
    // tile cost more than that, the search would stop heading for the goal and
    // spread out in hilly land
    if (U_IsFlat(t)) c = 5;
    else if (!U_IsSteep(t)) c = 6;
    else if (job.terra && PathRail_CanLevel(job, t)) c = 7;   // levelled before the track is laid
    else c = -1;
    // follow what is built: right beside an own track is cheaper, so a new line
    // runs alongside the old ones, copies their line and takes their way
    // around hills, water and towns
    if (c >= 0 && job.follow && PathRail_NextToOwn(job, t)) c = max(2, c - 2);
    // second track: right next to the first is very cheap, anywhere else expensive,
    // so the two tracks run side by side and take as little land as possible
    if (job.rawin("near") && job.near.len() > 0) c = job.near.rawin(t) ? 1 : c + 6;
  }
  job.cc.rawset(t, c);
  return c;
}

/* Permission: may this company's trains run on the track on tile t?
 * The one place that decides it. In OpenTTD 15/16 that means: the company's
 * own plain track (no station, depot, bridge or tunnel) of a rail type the new
 * trains can run on with power. Players in the same company share it. Cached. */
function PathRail_Usable(job, t)
{
  if (job.uc.rawin(t)) return job.uc.rawget(t);
  local ok = false;
  if (!job.blocked.rawin(t) && GSRail.IsRailTile(t) && !GSRail.IsRailStationTile(t) && !GSRail.IsRailDepotTile(t) &&
      !U_IsSpecial(t) && GSTile.GetOwner(t) == job.me) {
    local rt = GSRail.GetRailType(t);
    ok = GSRail.TrainCanRunOnRail(job.rail, rt) && GSRail.TrainHasPowerOnRail(job.rail, rt);
  }
  job.uc.rawset(t, ok);
  if (ok) job.rs.tiles++;
  return ok;
}

/* Running over an existing track tile from prev to next: -1 = not possible,
 * 0 = the track piece is there, 1 = a switch has to be added (a junction).
 * A one-way signal against the direction blocks it. Cached. */
function PathRail_ReusePiece(job, prev, tile, next, dir, i)
{
  local key = (tile * 4 + dir) * 4 + i;
  if (job.rc.rawin(key)) return job.rc.rawget(key);
  local r = -1;
  if (prev >= 0 && next >= 0) {
    local s = GSRail.GetSignalType(tile, prev);   // a signal for trains going the other way
    local oneway = s == GSRail.SIGNALTYPE_NORMAL || s == GSRail.SIGNALTYPE_ENTRY || s == GSRail.SIGNALTYPE_EXIT ||
                   s == GSRail.SIGNALTYPE_COMBO || s == GSRail.SIGNALTYPE_PBS_ONEWAY;
    if (oneway) {
      job.rs.oneway++;
    } else {
      local tm = GSTestMode();
      if (GSRail.BuildRail(prev, tile, next)) { r = 1; job.rs.join++; }
      else if (GSError.GetLastError() == GSError.ERR_ALREADY_BUILT) { r = 0; job.rs.along++; }
      else { job.rs.refused++; job.rs.last <- GSError.GetLastErrorString(); U_NoCash(); }
    }
  }
  job.rc.rawset(key, r);
  return r;
}

/* Existing own track at plan time (for the summary and junction signals). */
function PathRail_IsExisting(t, me)
{
  return GSRail.IsRailTile(t) && !GSRoad.IsRoadTile(t) && GSTile.GetOwner(t) == me;
}

/* Can tile t be levelled? One test per tile (it is expensive). Cached. */
function PathRail_CanLevel(job, t)
{
  if (job.lc.rawin(t)) return job.lc.rawget(t);
  local ok = U_CanLevel(t);
  job.lc.rawset(t, ok);
  return ok;
}

/* A curve on a sloped tile from prev to next: extra cost, or -1. Foundation
 * first (1), levelling the tile when landscaping is allowed (2). Kept small,
 * so hills do not slow the search down. Cached. */
function PathRail_SlopeCurve(job, prev, tile, next, dir, i)
{
  local key = (tile * 4 + dir) * 4 + i;
  if (job.sc.rawin(key)) return job.sc.rawget(key);
  local r = -1;
  if (prev >= 0 && next >= 0 && !U_IsSteep(tile)) {
    local tm = GSTestMode();
    if (GSRail.BuildRail(prev, tile, next)) r = 1;
  }
  if (r < 0 && job.terra && PathRail_CanLevel(job, tile)) r = 2;
  job.sc.rawset(key, r);
  return r;
}

/* Landscaping before the track: every sloped tile of the path where its track
 * piece cannot be built as it is (steep slope, curve without foundation) is
 * levelled first. first/last = the tiles before and after the path. */
function PathRail_LevelActions(path, first, last, out)
{
  local t = path.tiles, k = path.kinds;
  local full = [first];
  foreach (x in t) full.append(x);
  full.append(last);
  local n = 0;
  for (local j = 1; j + 1 < full.len(); j++) {
    local x = full[j];
    if (j - 1 < k.len() && k[j - 1] != 0) continue;              // bridge / tunnel end
    if (j < k.len() && k[j] != 0) continue;                      // bridge / tunnel start
    if (U_IsFlat(x) || GSRail.IsRailTile(x) || GSRoad.IsRoadTile(x)) continue;
    local ok = false;
    if (!U_IsSteep(x)) {
      local tm = GSTestMode();
      ok = GSRail.BuildRail(full[j - 1], x, full[j + 1]) || GSError.GetLastError() == GSError.ERR_ALREADY_BUILT;
    }
    if (ok) continue;
    out.append({ op = "level", a = x, b = U_Corner(x) });
    n++;
  }
  return n;
}

/* Is an own plain track right next to tile t (not a station or depot)? */
function PathRail_NextToOwn(job, t)
{
  foreach (n in U_Neighbours(t)) {
    if (GSRail.IsRailTile(n) && !GSRail.IsRailStationTile(n) && !GSRail.IsRailDepotTile(n) && GSTile.GetOwner(n) == job.me) return true;
  }
  return false;
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
  // on an existing own track (My tracks on) the track pieces decide where it may go
  local reuse = job.reuse && kind == 0 && PathRail_Usable(job, tile);
  local prev = reuse ? U_Step(tile, (dir + 2) % 4) : -1;
  // no turning on crossings or after a bridge/tunnel; on slopes only when a
  // curve fits there (foundation) or the tile can be levelled (landscaping)
  local straight = !reuse && (kind != 0 || PathRail_IsRoad(job, tile) || GSRail.IsRailTile(tile));
  local sloped = !reuse && !straight && !PathRail_Flat(job, tile);
  local back = U_Step(tile, (dir + 2) % 4);

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
    if (sloped && turn != 0) {
      local sc = PathRail_SlopeCurve(job, back, tile, n, dir, i);
      if (sc < 0) continue;
      extra += sc;
    }
    if (reuse) {
      local r = PathRail_ReusePiece(job, prev, tile, n, dir, i);
      if (r < 0) continue;
      if (r == 1) extra += 3;   // a new switch on the existing line: cheap, joining is wanted
    }
    if (n == job.goal_tile) {
      if (i == job.goal_dir && turn == 0) out.append([K_Make(n, i, 0), 1 + extra, 0]);
      continue;
    }
    local c = PathRail_Cost(job, n);
    // run on the existing own track: much cheaper than new track (5), so lines to
    // the same place share one corridor and take little new land
    if (c < 0 && job.reuse && PathRail_Usable(job, n)) c = 1;
    else if (c < 0 && turn == 0 && PathRail_CanCross(job, n, i)) {
      // level crossings slow trains and cause crashes; crossing our own track
      // on the level costs even more, a bridge over it is usually better
      c = PathRail_IsRoad(job, n) ? 20 : 30;
    }
    if (c >= 0) {
      out.append([K_Make(n, i, state), c + extra, 0]);
      // a track or road ahead: also offer a bridge over it (flyover)
      if (!GSRail.IsRailTile(n) && !PathRail_IsRoad(job, n)) continue;
    }
    // blocked (or a track / road) straight ahead: bridge with its head on this tile
    if (job.allow_br && kind == 0 && turn == 0) {
      local b = PathRail_Bridge(job, tile, i);
      // a bridge must not land right in front of the station entry: there is
      // no room left to turn and join the station switches (except when it
      // lands on the entry itself, in line with the platforms)
      if (b != null && b[0] != job.goal_tile && GSMap.DistanceManhattan(b[0], job.goal_tile) <= 3) b = null;
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

/* Signals where the new track joins an existing own track, on the last new
 * tile before the junction. Double track: one-way, only where trains run from
 * the new track onto the old one (forward = trains run along the path).
 * Single track: two-way at every join. */
function PathRail_JoinSignals(path, me, dbl, forward, out)
{
  local t = path.tiles, k = path.kinds;
  for (local j = 1; j < t.len(); j++) {
    if (k[j] != 0 || k[j - 1] != 0) continue;
    local e0 = PathRail_IsExisting(t[j - 1], me), e1 = PathRail_IsExisting(t[j], me);
    if (e0 == e1) continue;
    local nw = e0 ? t[j] : t[j - 1], old = e0 ? t[j - 1] : t[j];
    if (GSRoad.IsRoadTile(nw)) continue;
    if (dbl) {
      // trains go new -> old when the old tile comes later in their direction
      local into_old = forward ? e1 : e0;
      if (into_old) out.append({ op = "signal", t = nw, f = old, kind = "oneway" });
    } else {
      out.append({ op = "signal", t = nw, f = old, kind = "twoway" });
    }
  }
}

/* Entry signal for double track: one-way on the incoming row, facing the
 * switches, so arriving trains reserve a free platform before the switches. */
function PathRail_StationSignals(sp, in_row, out)
{
  out.append({ op = "signal", t = sp.G[in_row], f = sp.F[in_row], kind = "oneway" });
}
