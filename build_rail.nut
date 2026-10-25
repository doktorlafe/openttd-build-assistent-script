/* Rail building helpers. All of them must run inside a GSCompanyMode.
 *
 * Station layout (seen from the line, d = outward direction, s = side):
 *
 *   platform row 0:  P0 [L tiles] F0  G0  -> line (track 1)
 *   platform row 1:  P1 [L tiles] F1  G1  -> line (track 2, double only)
 *
 * F0/F1 hold the switches that let trains reach both platforms. */

/* Fastest rail type the company can use, or -1. */
function BuildRail_SelectType()
{
  local list = GSRailTypeList();
  local best = -1, best_speed = -1;
  for (local rt = list.Begin(); !list.IsEnd(); rt = list.Next()) {
    if (!GSRail.IsRailTypeAvailable(rt)) continue;
    local sp = GSRail.GetMaxSpeed(rt);
    if (sp == 0) sp = 100000;
    if (sp > best_speed) { best = rt; best_speed = sp; }
  }
  if (best >= 0) GSRail.SetCurrentRailType(best);
  return best;
}

function BuildRail_Offset(tile, d, s, k, r)
{
  local v = U_Vec(d), w = U_Vec(s);
  local x = GSMap.GetTileX(tile) + v[0] * k + w[0] * r;
  local y = GSMap.GetTileY(tile) + v[1] * k + w[1] * r;
  if (x < 1 || y < 1 || x >= GSMap.GetMapSizeX() - 1 || y >= GSMap.GetMapSizeY() - 1) return -1;
  return GSMap.GetTileIndex(x, y);
}

/* Lays out a station whose platform row 0 ends at e0, facing direction d.
 * through = also switch tiles at the back end (Pb/Fb/Gb), so trains can
 * enter at one end and leave at the other (station in the middle of a line).
 * Returns the spot table or null if a tile is off the map. */
function BuildRail_Layout(e0, d, plat, len, through)
{
  local s = (d % 2 == 0) ? 1 : 0;
  local sp = { d = d, s = s, plat = plat, len = len, P = [], F = [], G = [], tiles = [] };
  local minx = 100000, miny = 100000;
  for (local r = 0; r < plat; r++) {
    for (local k = 0; k < len; k++) {
      local t = BuildRail_Offset(e0, d, s, -k, r);
      if (t < 0) return null;
      sp.tiles.append(t);
      minx = min(minx, GSMap.GetTileX(t));
      miny = min(miny, GSMap.GetTileY(t));
      if (k == 0) sp.P.append(t);
    }
    local f = BuildRail_Offset(e0, d, s, 1, r), g = BuildRail_Offset(e0, d, s, 2, r);
    if (f < 0 || g < 0) return null;
    sp.F.append(f);
    sp.G.append(g);
    sp.tiles.append(f);
    sp.tiles.append(g);
  }
  if (!through) {
    // depot straight behind platform row 0: trains leave it without any curve
    sp.dep <- BuildRail_Offset(e0, d, s, -len, 0);
    sp.dep_front <- BuildRail_Offset(e0, d, s, -(len - 1), 0);
  }
  if (through) {
    sp.Pb <- [];
    sp.Fb <- [];
    sp.Gb <- [];
    for (local r = 0; r < plat; r++) {
      local pb = BuildRail_Offset(e0, d, s, -(len - 1), r);
      local fb = BuildRail_Offset(e0, d, s, -len, r), gb = BuildRail_Offset(e0, d, s, -len - 1, r);
      if (fb < 0 || gb < 0) return null;
      sp.Pb.append(pb);
      sp.Fb.append(fb);
      sp.Gb.append(gb);
      sp.tiles.append(fb);
      sp.tiles.append(gb);
    }
  }
  sp.anchor <- GSMap.GetTileIndex(minx, miny);
  sp.axis <- (d % 2 == 0) ? GSRail.RAILTRACK_NE_SW : GSRail.RAILTRACK_NW_SE;
  sp.w <- (d % 2 == 0) ? len : plat;
  sp.h <- (d % 2 == 0) ? plat : len;
  return sp;
}

/* Finds a free place for a station serving endpoint e. Returns the spot or null. */
/* Candidate platform-end tiles: first around the company's own rail stations
 * near the endpoint (new platforms there join that station = shared station),
 * then the usual tiles around the town or industry. */
function BuildRail_Candidates(e, role, radius, other, len)
{
  local out = [], seen = {};
  local center = Tg_Center(e);
  local own = GSStationList(GSStation.STATION_TRAIN);
  for (local st = own.Begin(); !own.IsEnd(); st = own.Next()) {
    local loc = GSStation.GetLocation(st);
    if (GSMap.DistanceManhattan(loc, center) > 30) continue;
    local around = U_TilesAround(loc, len + 4);
    for (local t = around.Begin(); !around.IsEnd(); t = around.Next()) {
      if (!seen.rawin(t)) { seen.rawset(t, true); out.append(t); }
    }
  }
  local tiles = Tg_Candidates(e, role, radius, other);
  for (local t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
    if (!seen.rawin(t)) { seen.rawset(t, true); out.append(t); }
  }
  return out;
}

/* Can the line leave a station over tile t in direction d? Free land, or a
 * road the track can cross at a right angle (not one running along the line). */
function BuildRail_ExitOk(t, d, blocked)
{
  if (t < 0 || blocked.rawin(t)) return false;
  if (GSTile.IsBuildable(t)) return true;
  if (!GSRoad.IsRoadTile(t) || GSRoad.IsRoadStationTile(t) || GSRoad.IsRoadDepotTile(t)) return false;
  if (!U_IsFlat(t) || U_IsSpecial(t)) return false;
  local a = U_Step(t, d), b = U_Step(t, (d + 2) % 4);
  if (a >= 0 && GSRoad.AreRoadTilesConnected(t, a)) return false;
  if (b >= 0 && GSRoad.AreRoadTilesConnected(t, b)) return false;
  return true;
}

/* Checks one station layout. level = may level the land first.
 * Sets sp.level (and sp.la / sp.lb) and returns true when it can be built. */
function BuildRail_Check(e, role, cargo, sp, blocked, radius, level)
{
  foreach (t in sp.tiles) {
    if (blocked.rawin(t) || !GSTile.IsBuildable(t)) return false;
  }
  // the line must be able to leave the station: the tile after G has to be free land or a road
  foreach (g in sp.G) {
    if (!BuildRail_ExitOk(U_Step(g, sp.d), sp.d, blocked)) return false;
  }
  if (sp.rawin("Gb")) {
    local back = (sp.d + 2) % 4;
    if (!BuildRail_ExitOk(U_Step(sp.Gb[0], back), back, blocked)) return false;
  }
  if (!Tg_SpotOk(e, role, cargo, sp.anchor, sp.w, sp.h, radius)) return false;
  local tm = GSTestMode();
  local fits = GSRail.BuildRailStation(sp.anchor, sp.axis, sp.plat, sp.len, GSStation.STATION_JOIN_ADJACENT);
  if (!fits) U_NoCash();
  if (!level) {
    if (!fits) return false;
    sp.level <- false;
    return true;
  }
  if (fits) return false;   // would have been found without levelling
  // level the whole station area including the switch tiles
  local minx = 100000, miny = 100000, maxx = 0, maxy = 0;
  foreach (t in sp.tiles) {
    minx = min(minx, GSMap.GetTileX(t)); maxx = max(maxx, GSMap.GetTileX(t));
    miny = min(miny, GSMap.GetTileY(t)); maxy = max(maxy, GSMap.GetTileY(t));
  }
  sp.la <- GSMap.GetTileIndex(minx, miny);
  sp.lb <- GSMap.GetTileIndex(maxx + 1, maxy + 1);
  if (!GSTile.LevelTiles(sp.la, sp.lb)) {
    U_NoCash();
    return false;
  }
  sp.level <- true;
  return true;
}

/* Layouts that put the new platforms right beside an own rail station near
 * the endpoint: same direction, ends lined up, on either side. The new
 * platforms join that station, so a 2x7 station becomes a 4x7 one.
 * Returns an array of spots, the ones facing the other end first. */
function BuildRail_ExtendLayouts(e, other, plat, len, through)
{
  local out = [], later = [];
  local center = Tg_Center(e);
  local own = GSStationList(GSStation.STATION_TRAIN);
  for (local st = own.Begin(); !own.IsEnd(); st = own.Next()) {
    if (GSMap.DistanceManhattan(GSStation.GetLocation(st), center) > 30) continue;
    local tiles = GSTileList_StationType(st, GSStation.STATION_TRAIN);
    if (tiles.IsEmpty()) continue;
    local minx = 100000, miny = 100000, maxx = 0, maxy = 0;
    for (local t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
      minx = min(minx, GSMap.GetTileX(t)); maxx = max(maxx, GSMap.GetTileX(t));
      miny = min(miny, GSMap.GetTileY(t)); maxy = max(maxy, GSMap.GetTileY(t));
    }
    local along_x = GSRail.GetRailStationDirection(tiles.Begin()) == GSRail.RAILTRACK_NE_SW;
    local ends = along_x ? [0, 2] : [1, 3];
    foreach (d in ends) {
      foreach (side in [1, -1]) {
        // e0 = end tile of the new platform row 0, flush with the old station's end
        local ex, ey;
        if (along_x) {
          ex = (d == 0) ? maxx : minx;
          ey = (side > 0) ? maxy + 1 : miny - plat;
        } else {
          ey = (d == 1) ? maxy : miny;
          ex = (side > 0) ? maxx + 1 : minx - plat;
        }
        if (ex < 1 || ey < 1 || ex >= GSMap.GetMapSizeX() - 1 || ey >= GSMap.GetMapSizeY() - 1) continue;
        local sp = BuildRail_Layout(GSMap.GetTileIndex(ex, ey), d, plat, len, through);
        if (sp == null) continue;
        sp.join <- st;
        if (U_Toward(d, sp.anchor, other) >= 0) out.append(sp); else later.append(sp);
      }
    }
  }
  foreach (sp in later) out.append(sp);
  return out;
}

/* Finds a place for a station serving endpoint e. Returns the spot or null.
 * 1. right beside an own station (extends it),
 * 2. free land nearby as it is,
 * 3. (if allowed) sloped land that gets levelled first. */
function BuildRail_FindSpot(e, role, cargo, other, plat, len, blocked, through)
{
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  local passes = GSController.GetSetting("allow_terraform") ? [false, true] : [false];

  foreach (level in passes) {
    foreach (sp in BuildRail_ExtendLayouts(e, other, plat, len, through)) {
      if (BuildRail_Check(e, role, cargo, sp, blocked, radius, level)) {
        U_Log("i", "Rail: extending station " + GSStation.GetName(sp.join) + (level ? " (land levelled)" : ""));
        return sp;
      }
    }
  }

  local cands = BuildRail_Candidates(e, role, radius + len, other, len);
  local total = passes.len() * min(cands.len(), 2000), done = 0;
  foreach (level in passes) {
    local tried = 0;
    foreach (e0 in cands) {
      if (++tried > 2000) break;
      if (++done % 40 == 0) U_Report(done * 100 / max(1, total));
      if (blocked.rawin(e0) || !GSTile.IsBuildable(e0)) continue;
      foreach (d in U_DirsToward(e0, other)) {
        if (U_Toward(d, e0, other) < 0) continue;
        local sp = BuildRail_Layout(e0, d, plat, len, through);
        if (sp == null) continue;
        if (!BuildRail_Check(e, role, cargo, sp, blocked, radius, level)) continue;
        U_Log("i", "Rail: station place found after " + tried + " tiles" + (level ? ", the land will be levelled" : ""));
        return sp;
      }
    }
  }
  U_Diag("!", "No free " + len + "x" + plat + " station place at " + Tg_Name(e) + " (" + cands.len() + " tiles checked" + (passes.len() < 2 ? ", land levelling is off" : "") + ").");
  return null;
}

/* Switch tracks on the F tiles. double = both rows lead out to the line. */
function BuildRail_FanActions(sp, double, out)
{
  // back end of a station in the middle of a line (single track)
  if (sp.rawin("Fb")) {
    out.append({ op = "rail", p = sp.Pb[0], t = sp.Fb[0], n = sp.Gb[0] });
    if (sp.plat >= 2) {
      out.append({ op = "rail", p = sp.Pb[1], t = sp.Fb[1], n = sp.Fb[0] });
      out.append({ op = "rail", p = sp.Fb[1], t = sp.Fb[0], n = sp.Gb[0] });
    }
  }
  out.append({ op = "rail", p = sp.P[0], t = sp.F[0], n = sp.G[0] });
  if (sp.plat < 2) return;
  out.append({ op = "rail", p = sp.P[1], t = sp.F[1], n = sp.F[0] });
  out.append({ op = "rail", p = sp.F[1], t = sp.F[0], n = sp.G[0] });
  if (!double) return;
  out.append({ op = "rail", p = sp.P[1], t = sp.F[1], n = sp.G[1] });
  out.append({ op = "rail", p = sp.P[0], t = sp.F[0], n = sp.F[1] });
  out.append({ op = "rail", p = sp.F[0], t = sp.F[1], n = sp.G[1] });
}

/* Depot beside a straight piece of track. tiles = part of the line in order.
 * Returns the depot tile or -1. */
function BuildRail_DepotOnLine(tiles)
{
  for (local j = 1; j + 1 < tiles.len(); j++) {
    local p = tiles[j - 1], t = tiles[j], n = tiles[j + 1];
    if (GSMap.DistanceManhattan(p, t) != 1 || GSMap.DistanceManhattan(t, n) != 1) continue;
    local dir = U_DirOf(p, t);
    if (U_DirOf(t, n) != dir) continue;
    if (!GSRail.IsRailTile(t) || U_IsSpecial(t) || GSRoad.IsRoadTile(t) || !U_IsFlat(t)) continue;
    foreach (side in [(dir + 1) % 4, (dir + 3) % 4]) {
      local dp = U_Step(t, side);
      if (dp < 0 || !GSTile.IsBuildable(dp) || !U_IsFlat(dp)) continue;
      if (GSRail.BuildRailDepot(dp, t)) {
        GSRail.BuildRail(dp, t, n);
        GSRail.BuildRail(dp, t, p);
        return dp;
      }
    }
  }
  return -1;
}
