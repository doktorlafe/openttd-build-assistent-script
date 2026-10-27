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
 * through = also tiles at the back end, so trains can enter at one end and
 * leave at the other: Pe = last platform tile, Pb = one plain track tile for
 * the exit signal of that platform (a signal cannot stand on a station tile or
 * a switch), Fb = switches, Gb = where the line leaves.
 * Returns the spot table or null if a tile is off the map. */
function BuildRail_Layout(e0, d, plat, len, through)
{
  local s = (d % 2 == 0) ? 1 : 0;
  if (through && ::g_want_rel >= 0) s = (::g_want_rel + d) % 4;
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
    sp.Pe <- [];
    sp.Pb <- [];
    sp.Fb <- [];
    sp.Gb <- [];
    for (local r = 0; r < plat; r++) {
      local pe = BuildRail_Offset(e0, d, s, -(len - 1), r), pb = BuildRail_Offset(e0, d, s, -len, r);
      local fb = BuildRail_Offset(e0, d, s, -len - 1, r), gb = BuildRail_Offset(e0, d, s, -len - 2, r);
      if (pb < 0 || fb < 0 || gb < 0) return null;
      sp.Pe.append(pe);
      sp.Pb.append(pb);
      sp.Fb.append(fb);
      sp.Gb.append(gb);
      sp.tiles.append(pb);
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

/* Tiles of a station layout that must lie flat at one height: platforms,
 * switch tiles (F, Fb), the tiles where the line leaves (G, Gb) and the depot
 * behind platform 0 (if that tile is free). A switch or a depot cannot stand
 * on a slope, and a tile at another height leaves a step: the track does not
 * connect. */
function BuildRail_FlatTiles(sp)
{
  local out = clone sp.tiles;
  if (sp.rawin("dep") && sp.dep >= 0 && GSTile.IsBuildable(sp.dep)) out.append(sp.dep);
  return out;
}

function BuildRail_AllFlat(sp)
{
  local h = -1;
  foreach (t in BuildRail_FlatTiles(sp)) {
    if (GSTile.GetSlope(t) != GSTile.SLOPE_FLAT) return false;
    local th = GSTile.GetMinHeight(t);
    if (h < 0) h = th;
    else if (th != h) return false;
  }
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
  if (e.kind == "station") {
    // transfer hub: the new platforms must become part of that station,
    // beside it or (Ctrl trick) within the station spread
    local ok = sp.rawin("join") && sp.join == e.id;
    if (!ok) {
      local spread = U_DistantJoinSpread();
      ok = spread > 0 && GSMap.DistanceMax(sp.anchor, GSStation.GetLocation(e.id)) + max(sp.w, sp.h) <= spread;
    }
    if (!ok) return false;
    sp.join_sid <- e.id;
  } else if (!Tg_SpotOk(e, role, cargo, sp.anchor, sp.w, sp.h, radius)) return false;
  local tm = GSTestMode();
  local fits = GSRail.BuildRailStation(sp.anchor, sp.axis, sp.plat, sp.len, GSStation.STATION_JOIN_ADJACENT);
  if (!fits) U_NoCash();
  // without levelling only on land that is flat at one height under the whole
  // layout (the station alone may fit on a slope, its switches and depot not)
  local flat = fits && BuildRail_AllFlat(sp);
  if (!level) {
    if (!flat) return false;
    sp.level <- false;
    return true;
  }
  if (flat) return false;   // would have been found without levelling
  // level the whole area at once: platforms, switch tiles, exits and depot
  local minx = 100000, miny = 100000, maxx = 0, maxy = 0;
  foreach (t in BuildRail_FlatTiles(sp)) {
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
        // the new row next to the old station, and the direction to the old one
        sp.ra <- side > 0 ? 0 : plat - 1;
        sp.old_dir <- along_x ? (side > 0 ? 3 : 1) : (side > 0 ? 2 : 0);
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
/* mode: null = flat land first, then levelled land; false = flat land only;
 * true = levelled land only (fewer places, each test is expensive).
 * quiet = no "no place" line in the Log (the caller reports). */
function BuildRail_FindSpot(e, role, cargo, other, plat, len, blocked, through, mode, quiet)
{
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  local terra = GSController.GetSetting("allow_terraform") != 0;
  local passes = mode == null ? (terra ? [false, true] : [false]) : (mode && !terra ? [] : [mode]);
  if (passes.len() == 0) return null;

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
    local cap = level ? 500 : 2000;   // a levelling test is expensive
    // flat land: not the first place that fits, but the best of the first few
    // (room for the line in front, facing the other end, what it covers);
    // levelled land: the first one, each test there is expensive
    local best = null, best_s = 0, found = 0, first_at = -1;
    foreach (e0 in cands) {
      if (++tried > cap) break;
      if (first_at >= 0 && (found >= 6 || tried - first_at > 80)) break;
      if (++done % 40 == 0) U_Report(done * 100 / max(1, total));
      if (blocked.rawin(e0) || !GSTile.IsBuildable(e0)) continue;
      foreach (d in U_DirsToward(e0, other)) {
        if (U_Toward(d, e0, other) < 0) continue;
        local sp = BuildRail_Layout(e0, d, plat, len, through);
        if (sp == null) continue;
        if (!BuildRail_Check(e, role, cargo, sp, blocked, radius, level)) continue;
        if (level) {
          U_Log("i", "Rail: station place found after " + tried + " tiles, the land will be levelled");
          return sp;
        }
        if (first_at < 0) first_at = tried;
        // later candidates lie further from the preferred spot
        local sc = BuildRail_SpotScore(e, cargo, sp, other, radius, blocked) - (tried - first_at) / 2;
        if (best == null || sc > best_s) { best = sp; best_s = sc; }
        found++;
        break;   // one layout per tile: the best direction that fits
      }
    }
    if (best != null) {
      U_Log("i", "Rail: station place found after " + tried + " tiles, best of " + found + " (score " + best_s + ")");
      return best;
    }
  }
  if (!quiet) U_Diag("!", "No free " + len + "x" + plat + " station place at " + Tg_Name(e) + " (" + cands.len() + " tiles checked" + (terra ? "" : ", land levelling is off") + ").");
  return null;
}

/* How good a station place is (higher = better):
 * - room in front: free straight tiles ahead of the rows that get a line, so
 *   the line can leave straight instead of turning sharply at the switches
 *   (fewer failed searches, faster trains),
 * - facing the other end of the route,
 * - for towns: how many houses it covers (passengers accepted). */
function BuildRail_SpotScore(e, cargo, sp, other, radius, blocked)
{
  local score = 0;
  local rows = min(2, sp.plat);
  for (local r = 0; r < rows; r++) {
    local t = sp.G[r];
    for (local k = 0; k < 6; k++) {
      t = U_Step(t, sp.d);
      if (t < 0 || blocked.rawin(t) || !GSTile.IsBuildable(t)) break;
      score += 3;
    }
  }
  if (sp.rawin("Gb")) {
    local back = (sp.d + 2) % 4, t = sp.Gb[0];
    for (local k = 0; k < 6; k++) {
      t = U_Step(t, back);
      if (t < 0 || blocked.rawin(t) || !GSTile.IsBuildable(t)) break;
      score += 3;
    }
  }
  local dist = max(1, U_Dist(sp.anchor, other));
  score += 20 * U_Toward(sp.d, sp.anchor, other) / dist;
  if (e.kind == "town") score += min(160, GSTile.GetCargoAcceptance(sp.anchor, cargo, sp.w, sp.h, radius)) / 4;
  return score;
}

/* One big station: when new platforms are added beside an own station, the
 * switch tiles of the neighbouring rows are linked both ways. Trains of every
 * line can then use every platform, enter through one station throat and
 * leave straight on their own line. Old line pieces are only added when the
 * old row really has a line in front of it. */
function BuildRail_JoinCrossover(sp, dbl, out)
{
  if (!sp.rawin("join") || !sp.rawin("old_dir")) return 0;
  local ra = sp.ra, od = sp.old_dir;
  local pb = sp.P[ra], fb = sp.F[ra], gb = sp.G[ra];
  local pa = U_Step(pb, od), fa = U_Step(fb, od), ga = U_Step(gb, od);
  if (pa < 0 || fa < 0 || ga < 0) return 0;
  if (!GSRail.IsRailStationTile(pa) || GSStation.GetStationID(pa) != sp.join) return 0;
  local n = 0;
  // old platforms -> new line, only if this new row has its own exit
  // (single track: only row 0 leads out)
  if (dbl || ra == 0) {
    out.append({ op = "rail", p = pa, t = fa, n = fb });
    out.append({ op = "rail", p = fa, t = fb, n = gb });
    n++;
  }
  // new platforms -> old line, only if there is an old line in front of that row
  if (GSRail.IsRailTile(ga)) {
    out.append({ op = "rail", p = pb, t = fb, n = fa });
    out.append({ op = "rail", p = fb, t = fa, n = ga });
    n++;
  }
  return n;
}

/* Switch tracks on the F tiles. double = both rows lead out to the line. */
function BuildRail_FanActions(sp, double, out)
{
  // back end of a station in the middle of a line (single track)
  if (sp.rawin("Fb")) {
    out.append({ op = "rail", p = sp.Pe[0], t = sp.Pb[0], n = sp.Fb[0] });
    out.append({ op = "rail", p = sp.Pb[0], t = sp.Fb[0], n = sp.Gb[0] });
    if (sp.plat >= 2) {
      out.append({ op = "rail", p = sp.Pe[1], t = sp.Pb[1], n = sp.Fb[1] });
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

/* Big station, rows 2 and up: a track along the switch tiles (the F column)
 * leads every platform to the exits of rows 0 (and 1 on double track).
 * The G tiles of these rows stay free for lines that join later. */
function BuildRail_FanMore(sp, double, out)
{
  if (sp.plat <= 2) return;
  for (local r = 2; r < sp.plat; r++) {
    out.append({ op = "rail", p = sp.P[r], t = sp.F[r], n = sp.F[r - 1] });
    if (r + 1 < sp.plat) out.append({ op = "rail", p = sp.F[r + 1], t = sp.F[r], n = sp.F[r - 1] });
  }
  out.append({ op = "rail", p = sp.F[2], t = sp.F[1], n = sp.F[0] });
  if (double) out.append({ op = "rail", p = sp.F[2], t = sp.F[1], n = sp.G[1] });
}

/* Loop station, rows 2 and up at the back end: a track along the back switch
 * tiles (the Fb column) leads every platform to the exit of row 0. */
function BuildRail_FanBackMore(sp, out)
{
  if (sp.plat <= 2 || !sp.rawin("Fb")) return;
  for (local r = 2; r < sp.plat; r++) {
    out.append({ op = "rail", p = sp.Pe[r], t = sp.Pb[r], n = sp.Fb[r] });
    out.append({ op = "rail", p = sp.Pb[r], t = sp.Fb[r], n = sp.Fb[r - 1] });
    if (r + 1 < sp.plat) out.append({ op = "rail", p = sp.Fb[r + 1], t = sp.Fb[r], n = sp.Fb[r - 1] });
  }
  out.append({ op = "rail", p = sp.Fb[2], t = sp.Fb[1], n = sp.Fb[0] });
}

/* Station place with plat platforms, or fewer (down to min_plat) when the big
 * one does not fit anywhere. */
function BuildRail_FindSpotAny(e, role, cargo, other, plat, min_plat, len, blocked, through)
{
  // cheap first: flat land for the big and the small size, only then levelled land
  local sizes = plat > min_plat ? [plat, min_plat] : [plat];
  foreach (mode in [false, true]) {
    foreach (p in sizes) {
      local sp = BuildRail_FindSpot(e, role, cargo, other, p, len, blocked, through, mode, true);
      if (sp == null) continue;
      if (p < plat) U_Diag("i", "Station at " + Tg_Name(e) + ": only " + p + " platform(s) fit instead of " + plat + ".");
      return sp;
    }
  }
  U_Diag("!", "No free " + len + "x" + plat + " station place at " + Tg_Name(e) + " (not even " + min_plat + " platform(s)" +
         (GSController.GetSetting("allow_terraform") ? "" : ", land levelling is off") + ").");
  return null;
}

/* A station the script built before, near endpoint e, that still has free
 * platform rows (rows without a line in front). Returns a spot that uses
 * nrows of them (1 single, 2 double track) or null. The new line then joins
 * this station instead of building another one. */
function BuildRail_UseStation(list, e, role, cargo, nrows, rail, me, blocked)
{
  if (list == null) return null;
  local center = Tg_Center(e);
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  foreach (st in list) {
    local p0 = st.P[0];
    if (!GSRail.IsRailStationTile(p0) || GSTile.GetOwner(p0) != me) continue;
    if (GSMap.DistanceManhattan(st.anchor, center) > 30) continue;
    local rt = GSRail.GetRailType(p0);
    if (!GSRail.TrainCanRunOnRail(rail, rt) || !GSRail.TrainHasPowerOnRail(rail, rt)) continue;
    // does not cover the endpoint: the Ctrl trick (one joined tile near it) may help
    local helper = -1;
    if (!Tg_SpotOk(e, role, cargo, st.anchor, st.w, st.h, radius)) {
      helper = BuildRail_HelperTile(e, role, cargo, st, GSStation.GetStationID(p0), radius, U_DistantJoinSpread(), blocked);
      if (helper < 0) continue;
    }
    local free = {};
    for (local r = 1; r < st.plat; r++) {
      local g = st.G[r];
      if (!GSRail.IsRailStationTile(st.P[r])) continue;
      if (blocked.rawin(g) || GSRail.IsRailTile(g) || !GSTile.IsBuildable(g)) continue;
      if (!BuildRail_ExitOk(U_Step(g, st.d), st.d, blocked)) continue;
      free.rawset(r, true);
    }
    local first = -1;
    for (local r = 1; r < st.plat && first < 0; r++) {
      if (nrows == 1 && free.rawin(r)) first = r;
      if (nrows == 2 && free.rawin(r) && free.rawin(r + 1)) first = r;
    }
    if (first < 0) continue;
    local v = { d = st.d, s = st.s, plat = nrows, len = st.len, P = [], F = [], G = [], tiles = [],
                anchor = st.anchor, w = st.w, h = st.h, level = false, existing = true, links = [] };
    for (local r = first; r < first + nrows; r++) {
      v.P.append(st.P[r]);
      v.F.append(st.F[r]);
      v.G.append(st.G[r]);
      v.tiles.append(st.F[r]);
      v.tiles.append(st.G[r]);
    }
    // the switch column of the station leads into the new exit, so trains of
    // this line can use the other platforms too
    v.links.append({ op = "rail", p = st.F[first - 1], t = st.F[first], n = st.G[first] });
    v.station_name <- GSStation.GetName(GSStation.GetStationID(p0));
    if (helper >= 0) {
      v.helper <- helper;
      v.sid <- GSStation.GetStationID(p0);
      v.tiles.append(helper);
    }
    v.rows <- first.tostring() + (nrows == 2 ? "+" + (first + 1) : "");
    return v;
  }
  return null;
}

/* The Ctrl trick: one station tile next to endpoint e, joined to the station
 * st (distant join), so e delivers to / takes from that station although the
 * station itself is too far away. Returns the tile or -1. */
function BuildRail_HelperTile(e, role, cargo, st, sid, radius, spread, blocked)
{
  if (spread <= 0) return -1;
  local x0 = GSMap.GetTileX(st.anchor), y0 = GSMap.GetTileY(st.anchor);
  local x1 = x0 + st.w - 1, y1 = y0 + st.h - 1;
  local cands = Tg_Candidates(e, role, radius, st.anchor);
  if (e.kind == "industry") {
    // closest to the station first, the spread is the limit
    cands.Valuate(GSMap.DistanceManhattan, st.anchor);
    cands.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
  }
  local tried = 0;
  for (local t = cands.Begin(); !cands.IsEnd() && tried < 400; t = cands.Next()) {
    tried++;
    if (blocked.rawin(t) || !GSTile.IsBuildable(t) || !U_IsFlat(t)) continue;
    local x = GSMap.GetTileX(t), y = GSMap.GetTileY(t);
    if (max(x1, x) - min(x0, x) + 1 > spread || max(y1, y) - min(y0, y) + 1 > spread) continue;
    if (!Tg_SpotOk(e, role, cargo, t, 1, 1, radius)) continue;
    local tm = GSTestMode();
    if (!GSRail.BuildRailStation(t, GSRail.RAILTRACK_NE_SW, 1, 1, sid)) { U_NoCash(); continue; }
    return t;
  }
  return -1;
}

/* What to remember of a station for later lines (saved with the game). */
function BuildRail_Memo(sp)
{
  return { anchor = sp.anchor, d = sp.d, s = sp.s, plat = sp.plat, len = sp.len,
           P = clone sp.P, F = clone sp.F, G = clone sp.G, w = sp.w, h = sp.h };
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
