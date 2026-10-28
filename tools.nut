/* Light mode (setting "light_mode"): the player builds the tracks, the script
 * only takes the clicking out of buying trains. One page "Build assistant -
 * tools", element names start with t_. Kept apart from the planner on purpose
 * (needs only vehicles.nut, advice.nut, targets.nut Tg_Mail and util.nut), so
 * it can become a script of its own later.
 *   Train on a route  depot + 2 stations -> engine, wagons for the platform, orders
 *   Copies            pick a train -> N clones with shared orders
 *   Fill wagons       pick a train -> to the depot, wagons up to the platform length
 * self.tools[company] = { depot, st1, st2, count, wait = [ { v, len, t0 } ] }, not saved. */

const TOOLS_LOG_LINES = 6;
TOOLS_COUNTS <- [1, 2, 3, 5];

function Tools_IsLight()
{
  return GSController.GetSetting("light_mode") != 0;
}

function Tools_Items()
{
  local go = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_NONE);
  local push = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_NONE);
  local stop = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, GSStoryPage.SPBF_NONE);
  local pick = GSStoryPage.MakeTileButtonReference(GSStoryPage.SPBC_YELLOW, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE);
  local veh = GSStoryPage.MakeVehicleButtonReference(GSStoryPage.SPBC_ORANGE, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE, GSVehicle.VT_RAIL);
  local items = [
    ["t_title1", GSStoryPage.SPET_TEXT, 0, "--- Train on a route: click your depot and two of your stations ---"],
    ["t_depot", GSStoryPage.SPET_BUTTON_TILE, pick, "Depot"],
    ["t_detect", GSStoryPage.SPET_BUTTON_PUSH, push, "Find stations from the depot"],
    ["t_st1", GSStoryPage.SPET_BUTTON_TILE, pick, "Station 1 (loads)"],
    ["t_st2", GSStoryPage.SPET_BUTTON_TILE, pick, "Station 2 (unloads)"],
    ["t_count", GSStoryPage.SPET_BUTTON_PUSH, push, "How many: 1 / 2 / 3 / 5"],
    ["t_buy", GSStoryPage.SPET_BUTTON_PUSH, go, "Buy trains"],
    ["t_sel", GSStoryPage.SPET_TEXT, 0, "Depot: - | Station 1: - | Station 2: - | how many: 1"],
    ["t_title2", GSStoryPage.SPET_TEXT, 0, "--- Your trains: click the button, then a train ---"],
    ["t_clone", GSStoryPage.SPET_BUTTON_VEHICLE, veh, "Copies of a train (how many above)"],
    ["t_fill", GSStoryPage.SPET_BUTTON_VEHICLE, veh, "Fill wagons to the platform length"],
    ["t_title3", GSStoryPage.SPET_TEXT, 0, "--- Connect two track ends: click the last tile of each track ---"],
    ["t_end1", GSStoryPage.SPET_BUTTON_TILE, pick, "End 1"],
    ["t_end2", GSStoryPage.SPET_BUTTON_TILE, pick, "End 2"],
    ["t_conn", GSStoryPage.SPET_BUTTON_PUSH, push, "Find the way"],
    ["t_cbuild", GSStoryPage.SPET_BUTTON_PUSH, go, "Build connection"],
    ["t_ccancel", GSStoryPage.SPET_BUTTON_PUSH, stop, "Cancel"],
    ["t_csel", GSStoryPage.SPET_TEXT, 0, "End 1: - | End 2: -"],
    ["t_title4", GSStoryPage.SPET_TEXT, 0, "--- Town bus loop ---"],
    ["t_loop", GSStoryPage.SPET_BUTTON_TILE, pick, "Bus loop in a town"],
    ["t_status", GSStoryPage.SPET_TEXT, 0, "Status: ready."],
    ["t_logt", GSStoryPage.SPET_TEXT, 0, "--- Log (newest first) ---"]
  ];
  for (local i = 0; i < TOOLS_LOG_LINES; i++) items.append(["t_log" + i, GSStoryPage.SPET_TEXT, 0, "-"]);
  return items;
}

function Tools_HelpLines()
{
  return [
    "Light mode: you build the tracks and stations, the assistant buys the trains.",
    "Depot / Station 1 / Station 2: click the button, then the tile on the map. Station 1 is where the train loads (it waits for a full load), station 2 where it unloads.",
    "Find stations from the depot: follows your track from the picked depot and lists every station it reaches, in travel order (a loop of towns too). Buy trains then runs the trains over all of them. Station 1 / 2 replace the list.",
    "How many: switches 1, 2, 3, 5 trains (also used by Copies).",
    "Buy trains: the best engine for the rail type of the depot, as many wagons as fit the shorter platform, the cargo station 1 gets and station 2 takes, and the orders.",
    "Copies of a train: click the button, then a train. It gets copies with shared orders, bought in its depot or the nearest one.",
    "Fill wagons: click the button, then a train. It goes to a depot, gets wagons of its last wagon's type (or loses some) to fit the shortest platform of its orders, and leaves again.",
    "End 1 / End 2: click the last tile of a track that stops there (a dead end). Double track: click one track of each pair, the one beside it is found and connected too. Find the way searches a route between them (bridges, tunnels, hills like the full assistant) and shows it with signs and the price.",
    "Bus loop in a town: click a town, it gets bus stops close together (setting loop_stops, 5), a depot and buses (setting veh_loop, 1).",
    "Build connection: builds it (again after running out of money: it goes on where it stopped). Cancel: stops and removes the signs."
  ];
}

/* Per company state. */
function Tools_State(self, company)
{
  if (!self.tools.rawin(company))
    self.tools.rawset(company, { depot = -1, st1 = -1, st2 = -1, route = null, count = 0, wait = [], end1 = -1, end2 = -1, conn = null });
  return self.tools.rawget(company);
}

/* Builds the light pages for a company into p (p.page = the tools page). */
function Tools_Pages(self, company, p)
{
  local page = GSStoryPage.New(company, "Build assistant - tools");
  if (page == GSStoryPage.STORY_PAGE_INVALID) return false;
  p.page = page;
  foreach (it in Tools_Items()) {
    local id = GSStoryPage.NewElement(page, it[1], it[2], U_Clip(it[3]));
    if (id != GSStoryPage.STORY_PAGE_ELEMENT_INVALID) p.el.rawset(it[0], id);
  }
  local hpage = GSStoryPage.New(company, "Build assistant - help");
  if (hpage != GSStoryPage.STORY_PAGE_INVALID) {
    p.hpage <- hpage;
    foreach (line in Tools_HelpLines()) GSStoryPage.NewElement(hpage, GSStoryPage.SPET_TEXT, 0, U_Clip(line));
  }
  return true;
}

function Tools_Status(self, company, text)
{
  GSLog.Info(U_Clip("[" + company + "] tools: " + text));
  UI_SetText(self, company, "t_status", "Status: " + text);
}

/* A line for the log of the tools page. */
function Tools_Log(self, company, text)
{
  Tools_Status(self, company, text);
  local s = Tools_State(self, company);
  if (!s.rawin("log")) s.log <- [];
  s.log.insert(0, U_Clip(GSDate.GetYear(GSDate.GetCurrentDate()) + "-" + GSDate.GetMonth(GSDate.GetCurrentDate()) + " " + text));
  while (s.log.len() > TOOLS_LOG_LINES) s.log.pop();
  for (local i = 0; i < TOOLS_LOG_LINES; i++) UI_SetText(self, company, "t_log" + i, i < s.log.len() ? s.log[i] : "-");
}

function Tools_TileName(t)
{
  if (t < 0) return "-";
  if (GSRail.IsRailStationTile(t)) return GSStation.GetName(GSStation.GetStationID(t));
  return GSMap.GetTileX(t) + "," + GSMap.GetTileY(t);
}

function Tools_Selection(self, company)
{
  local s = Tools_State(self, company);
  local st = "Station 1: " + Tools_TileName(s.st1) + " | Station 2: " + Tools_TileName(s.st2);
  if (s.route != null) {
    st = "Stations:";
    for (local i = 0; i < s.route.len(); i++) st += (i > 0 ? " >" : "") + " " + Tools_TileName(s.route[i]);
  }
  UI_SetText(self, company, "t_sel", "Depot: " + Tools_TileName(s.depot) + " | " + st + " | how many: " + TOOLS_COUNTS[s.count]);
}

/* Own rail stations reachable over the track from the depot, in travel order:
 * the one reached first along the track, then always the nearest one not yet
 * in the list (a loop of towns comes out in its order). Returns platform tiles. */
function Tools_FindStations(depot, company)
{
  local seen = {}, found = [], ids = {};
  local queue = [[depot, GSRail.GetRailDepotFrontTile(depot)]];
  local qi = 0;
  while (qi < queue.len() && qi < 60000) {
    local prev = queue[qi][0], t = queue[qi][1];
    qi++;
    if (t < 0 || !GSRail.IsRailTile(t) || GSTile.GetOwner(t) != company || GSRail.IsRailDepotTile(t)) continue;
    local far = GSMap.DistanceManhattan(prev, t) > 1;   // came over a bridge or through a tunnel
    local dir = U_DirOf(prev, t);
    local key = t * 4 + dir;
    if (seen.rawin(key)) continue;
    seen.rawset(key, true);
    if (GSRail.IsRailStationTile(t)) {
      local sid = GSStation.GetStationID(t);
      if (!ids.rawin(sid)) { ids.rawset(sid, true); found.append(t); }
    }
    local other = -1;
    if (GSBridge.IsBridgeTile(t)) other = GSBridge.GetOtherBridgeEnd(t);
    else if (GSTunnel.IsTunnelTile(t)) other = GSTunnel.GetOtherTunnelEnd(t);
    if (other >= 0) {
      // on a head: into the bridge / tunnel, or out of it onto the land
      if (!far && U_DirOf(t, other) == dir) queue.append([t, other]);
      else queue.append([t, U_Step(t, dir)]);
      continue;
    }
    for (local i = 0; i < 4; i++) {
      local n = U_Step(t, i);
      if (n < 0 || n == prev) continue;
      if (GSRail.AreTilesConnected(prev, t, n)) queue.append([t, n]);
    }
  }
  if (found.len() < 3) return found;
  local order = [found[0]];
  found.remove(0);
  while (found.len() > 0) {
    local last = order[order.len() - 1], bi = 0;
    for (local i = 1; i < found.len(); i++)
      if (GSMap.DistanceManhattan(last, found[i]) < GSMap.DistanceManhattan(last, found[bi])) bi = i;
    order.append(found[bi]);
    found.remove(bi);
  }
  return order;
}

/* Cargo for a train over the stations: passengers when it is a line of 3+
 * stations and at least 2 of them take passengers, else as for 2 stations. */
function Tools_CargoRoute(tiles)
{
  if (tiles.len() > 2) {
    local list = GSCargoList();
    for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
      if (!GSCargo.HasCargoClass(c, GSCargo.CC_PASSENGERS)) continue;
      local n = 0;
      foreach (t in tiles) if (GSCargoList_StationAccepting(GSStation.GetStationID(t)).HasItem(c)) n++;
      if (n >= 2) return c;
    }
  }
  return Tools_Cargo(tiles[0], tiles[1]);
}

/* Length of the platform tile t is on (tiles in a row of the same station). */
function Tools_PlatLen(t)
{
  if (!GSRail.IsRailStationTile(t)) return 0;
  local sid = GSStation.GetStationID(t);
  local dir = GSRail.GetRailStationDirection(t);
  local step = dir == GSRail.RAILTRACK_NE_SW ? GSMap.GetTileIndex(1, 0) : GSMap.GetTileIndex(0, 1);
  local n = 1;
  foreach (d in [step, -step]) {
    local x = t + d;
    while (GSMap.IsValidTile(x) && GSRail.IsRailStationTile(x) && GSStation.GetStationID(x) == sid &&
           GSRail.GetRailStationDirection(x) == dir) {
      n++;
      x += d;
    }
  }
  return n;
}

/* Cargo for a train from station tile t1 to station tile t2: the one with the
 * most waiting at station 1 that station 2 takes; else one produced around
 * station 1 that station 2 takes (a new station has no rating yet). -1 = none. */
function Tools_Cargo(t1, t2)
{
  local s1 = GSStation.GetStationID(t1), s2 = GSStation.GetStationID(t2);
  local acc = GSCargoList_StationAccepting(s2);
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  local best = -1, best_v = -1;
  for (local c = acc.Begin(); !acc.IsEnd(); c = acc.Next()) {
    local v = -1;
    if (GSStation.HasCargoRating(s1, c)) v = 1000000 + GSStation.GetCargoWaiting(s1, c);
    else if (GSTile.GetCargoProduction(t1, c, 1, 1, radius) > 0) v = GSTile.GetCargoProduction(t1, c, 1, 1, radius);
    if (v > best_v) { best = c; best_v = v; }
  }
  return best;
}

/* Own rail station tile? */
function Tools_OwnStation(t, company)
{
  return GSRail.IsRailStationTile(t) && GSTile.GetOwner(t) == company;
}

function Tools_OnTile(self, company, name, t)
{
  local s = Tools_State(self, company);
  if (name == "t_loop") {
    local town = GSTile.GetClosestTown(t);
    if (!GSTown.IsValidTown(town)) { Tools_Status(self, company, "No town there."); return; }
    Tools_Status(self, company, "Building bus loop in " + GSTown.GetName(town) + " ...");
    local mode = GSCompanyMode(company);
    Tools_Log(self, company, Loop_Build(town, GSController.GetSetting("loop_stops"), GSController.GetSetting("loop_gap"),
                                        GSController.GetSetting("veh_loop")));
    return;
  }
  if (name == "t_end1" || name == "t_end2") {
    if (GSTile.GetOwner(t) != company || Tools_EndDir(t) < 0) {
      Tools_Status(self, company, "That is not the last tile of your track: click the tile where the track stops.");
      return;
    }
    if (name == "t_end1") s.end1 = t; else s.end2 = t;
    UI_SetText(self, company, "t_csel", "End 1: " + Tools_TileName(s.end1) + " | End 2: " + Tools_TileName(s.end2));
    Tools_Status(self, company, s.end1 >= 0 && s.end2 >= 0 ? "Press Find the way." : "Pick the other end.");
    return;
  }
  if (name == "t_depot") {
    if (!GSRail.IsRailDepotTile(t) || GSTile.GetOwner(t) != company) { Tools_Status(self, company, "That is not your rail depot."); return; }
    s.depot = t;
  } else {
    if (!Tools_OwnStation(t, company)) { Tools_Status(self, company, "That is not a platform of your rail station."); return; }
    if (name == "t_st1") s.st1 = t; else s.st2 = t;
    s.route = null;
  }
  Tools_Selection(self, company);
  Tools_Status(self, company, s.depot >= 0 && s.st1 >= 0 && s.st2 >= 0 ? "Press Buy trains." : "Pick the rest.");
}

function Tools_OnButton(self, company, name)
{
  local s = Tools_State(self, company);
  if (name == "t_count") {
    s.count = (s.count + 1) % TOOLS_COUNTS.len();
    Tools_Selection(self, company);
  } else if (name == "t_detect") {
    if (s.depot < 0 || !GSRail.IsRailDepotTile(s.depot)) { Tools_Status(self, company, "Pick the depot first."); return; }
    local r = Tools_FindStations(s.depot, company);
    if (r.len() < 2) { Tools_Status(self, company, "From this depot the track reaches " + r.len() + " station(s), at least 2 are needed."); return; }
    while (r.len() > 10) r.pop();
    s.route = r;
    Tools_Selection(self, company);
    Tools_Status(self, company, "Found " + r.len() + " stations. Press Buy trains.");
  } else if (name == "t_buy") {
    local mode = GSCompanyMode(company);
    Tools_Buy(self, company, s);
  } else if (name == "t_conn") {
    local mode = GSCompanyMode(company);
    Tools_ConnStop(s);
    Tools_ConnStart(self, company, s);
  } else if (name == "t_cbuild") {
    if (s.conn == null || s.conn.state != "CONFIRM") { Tools_Status(self, company, "Nothing found yet: pick both ends and press Find the way."); return; }
    s.conn.state = "BUILD";
    Tools_Status(self, company, "Building the connection ...");
  } else if (name == "t_ccancel") {
    Tools_ConnStop(s);
    Tools_Status(self, company, "Connection cancelled.");
  }
}

/* Direction (0..3) in which the track on tile e stops, or -1: a track piece
 * on e leads to a neighbour that has no track. */
function Tools_EndDir(e)
{
  if (!GSRail.IsRailTile(e) || GSRail.IsRailStationTile(e) || GSRail.IsRailDepotTile(e) || U_IsSpecial(e)) return -1;
  for (local i = 0; i < 4; i++) {
    local n = U_Step(e, i);
    if (n < 0 || GSRail.IsRailTile(n)) continue;
    for (local j = 0; j < 4; j++) {
      if (j == i) continue;
      local p = U_Step(e, j);
      if (p >= 0 && GSRail.AreTilesConnected(p, e, n)) return i;
    }
  }
  return -1;
}

/* Removes the signs of a connection and forgets it. */
function Tools_ConnStop(s)
{
  if (s.conn != null) Job_LiveClear(s.conn.job);
  s.conn = null;
}

/* The end beside track end e that stops in the same direction d (the other
 * track of a double track): [tile, side direction] or null. */
function Tools_Twin(e, d, company)
{
  foreach (sd in [(d + 1) % 4, (d + 3) % 4]) {
    local t = U_Step(e, sd);
    if (t >= 0 && GSTile.GetOwner(t) == company && Tools_EndDir(t) == d) return [t, sd];
  }
  return null;
}

/* Tiles right beside a path on side `twin` (1 = right, 3 = left of the
 * direction of travel): the lane of the second track. */
function Tools_Lane(path, twin)
{
  local lane = {}, t = path.tiles;
  for (local j = 0; j < t.len(); j++) {
    if (j + 1 < t.len() && GSMap.DistanceManhattan(t[j], t[j + 1]) == 1) {
      local x = U_Step(t[j], (U_DirOf(t[j], t[j + 1]) + twin) % 4);
      if (x >= 0) lane.rawset(x, true);
    }
    if (j > 0 && GSMap.DistanceManhattan(t[j - 1], t[j]) == 1) {
      local x = U_Step(t[j], (U_DirOf(t[j - 1], t[j]) + twin) % 4);
      if (x >= 0) lane.rawset(x, true);
    }
  }
  return lane;
}

/* Starts the route search between the two picked track ends. Uses the route
 * search of the full assistant (jobs.nut, path_rail.nut). When both ends have
 * a twin beside them (double track), both tracks are connected: the second
 * one is searched right beside the first. */
function Tools_ConnStart(self, company, s)
{
  if (s.end1 < 0 || s.end2 < 0) { Tools_Status(self, company, "Pick End 1 and End 2 first."); return; }
  local ea = s.end1, eb = s.end2;
  local da = Tools_EndDir(ea), db = Tools_EndDir(eb);
  if (da < 0 || db < 0) { Tools_Status(self, company, "An end is no longer a dead end of a track. Pick it again."); return; }
  if (ea == eb) { Tools_Status(self, company, "End 1 and End 2 are the same tile."); return; }
  local tracks = [{ a = ea, da = da, b = eb, db = db }];
  local twin = -1;
  local ta = Tools_Twin(ea, da, company), tb = Tools_Twin(eb, db, company);
  if (ta != null && tb != null && ta[0] != eb && tb[0] != ea) {
    // side of the second track as seen from a train on the first one (1 = right,
    // 3 = left); at B the train arrives in direction db + 2, so the end on the
    // same side there belongs to the same track
    twin = (ta[1] - da + 4) % 4;
    local side_b = (tb[1] - (db + 2) % 4 + 4) % 4;
    if (side_b == twin) tracks = [{ a = ea, da = da, b = eb, db = db }, { a = ta[0], da = da, b = tb[0], db = db }];
    else tracks = [{ a = ea, da = da, b = tb[0], db = db }, { a = ta[0], da = da, b = eb, db = db }];
  }
  local job = { mode = MODE_RAIL, company = company, names = "connection", live = [], live_at = -15000,
                rail = GSRail.GetRailType(ea), me = company };
  GSRail.SetCurrentRailType(job.rail);
  Job_SearchSetup(job);
  job.twin = twin;
  job.lane <- [];
  // the tiles in front of the second track's ends stay free while the first
  // one is searched, so it cannot shut them in
  if (tracks.len() == 2) {
    Job_KeepEntry(job, U_Step(tracks[1].a, da), da);
    Job_KeepEntry(job, U_Step(tracks[1].b, db), db);
  }
  s.conn = { state = "SEARCH", job = job, tracks = tracks, k = -1, paths = [], actions = [], idx = 0, failed = 0,
             ea = ea, eb = eb, tight = true };
  Tools_ConnNext(self, company, s);
}

/* Starts the search of the next track, or plans the build when all are found. */
function Tools_ConnNext(self, company, s)
{
  local c = s.conn, job = c.job;
  c.k++;
  if (c.k >= c.tracks.len()) { Tools_ConnPlanned(self, company, s); return; }
  local tr = c.tracks[c.k];
  local na = U_Step(tr.a, tr.da), nb = U_Step(tr.b, tr.db);
  if (c.k > 0) {
    // second track: the lane is free again, the first track is off limits and
    // right beside it is cheap
    Job_ResetCache(job);
    foreach (x in job.lane) if (job.blocked.rawin(x)) job.blocked.rawdelete(x);
    foreach (t in c.paths[0].tiles) job.blocked.rawset(t, true);
    // tight: only the tiles right beside the first track on the twin side, so
    // the two run with no gap; if that finds no way, any tile near it
    job.tight <- c.tight;
    job.near <- {};
    if (c.tight) job.near = Tools_Lane(c.paths[0], job.twin);
    else foreach (t in c.paths[0].tiles) foreach (n in U_Neighbours(t)) job.near.rawset(n, true);
  }
  if (na == nb) {
    // the ends are 2 tiles apart: one piece between them
    c.paths.append({ tiles = [na], kinds = [0] });
    Tools_ConnNext(self, company, s);
    return;
  }
  job.goal_tile = nb;
  job.goal_dir = (tr.db + 2) % 4;
  if ((PathRail_Cost(job, na) < 0 || PathRail_Cost(job, nb) < 0) && c.k > 0 && c.tight) {
    // an end of track 2 is not right beside track 1: search with more room
    c.tight = false;
    c.k--;
    Tools_ConnNext(self, company, s);
    return;
  }
  if (PathRail_Cost(job, na) < 0 || PathRail_Cost(job, nb) < 0) {
    Tools_ConnStop(s);
    Tools_Status(self, company, "The tile in front of an end is not free (or too steep). Clear it or pick another end.");
    return;
  }
  Job_BeginSearch(job, K_Make(na, tr.da, 0));
  if (c.k > 0) {
    // the waypoints of the second track lie on the first one, so it follows it
    local p1 = c.paths[0].tiles;
    if (job.wps.len() > 0 && p1.len() > 2) {
      local n = job.wps.len() + 1;
      job.wps = [];
      for (local i = 1; i < n; i++) job.wps.append(p1[i * p1.len() / n]);
      job.wp_i = 0;
      job.wp = job.wps[0];
      Job_NewAStar(job, job.seg_start);
    }
  }
  Tools_Status(self, company, "Searching track " + (c.k + 1) + "/" + c.tracks.len() + ", " + GSMap.DistanceManhattan(tr.a, tr.b) + " tiles apart ...");
}

/* All tracks found: build actions, price, signs; waits for Build connection. */
function Tools_ConnPlanned(self, company, s)
{
  local c = s.conn, job = c.job;
  local specials = [], pieces = [], tiles = [];
  for (local k = 0; k < c.paths.len(); k++) {
    PathRail_Actions(c.paths[k], c.tracks[k].a, c.tracks[k].b, specials, pieces);
    foreach (t in c.paths[k].tiles) tiles.append(t);
  }
  foreach (a in specials) c.actions.append(a);
  foreach (a in pieces) c.actions.append(a);
  local cost = Act_Estimate(job, c.actions);
  Job_LiveClear(job);
  job.live = Preview_Live([], tiles);
  c.state = "CONFIRM";
  Tools_Status(self, company, "Way found (" + (c.tracks.len() == 2 ? "double track" : "single track") + "): " + c.paths[0].tiles.len() +
    " tiles, about " + cost + ". Press Build connection." + (job.est_fail > 0 ? " Warning: " + job.est_fail + " piece(s) failed the test." : ""));
}

/* One step of the connection of a company. Returns true while it works. */
function Tools_ConnTick(self, company, s)
{
  local c = s.conn;
  if (c == null) return false;
  local job = c.job;
  if (c.state == "SEARCH") {
    local r = job.astar.Step(GSController.GetSetting("search_per_tick"));
    Job_LiveView(job);
    if (r == 1) {
      if (Job_SegDone(job)) {
        local p = { tiles = [], kinds = [] };
        foreach (t in job.acc.tiles) p.tiles.append(t);
        foreach (x in job.acc.kinds) p.kinds.append(x);
        c.paths.append(p);
        Tools_ConnNext(self, company, s);
      }
    } else if (r < 0) {
      if (!Job_SegFailed(job)) {
        if (c.k > 0 && c.tight) {
          // no way right beside the first track: once more with room to move away
          c.tight = false;
          c.k--;
          Tools_Status(self, company, "Track 2 does not fit right beside track 1 everywhere, searching with more room ...");
          Tools_ConnNext(self, company, s);
          return true;
        }
        local why = Job_Why(job);
        local which = c.tracks.len() == 2 ? " (track " + (c.k + 1) + "/2)" : "";
        Tools_ConnStop(s);
        Tools_Log(self, company, "No way between the two ends" + which + ": " + why + ".");
      }
    } else {
      Tools_Status(self, company, "Searching track " + (c.k + 1) + "/" + c.tracks.len() + " ... " + U_Bar(job.astar.Closeness()));
    }
    return s.conn != null && s.conn.state == "SEARCH";
  }
  if (c.state != "BUILD") return false;
  GSRail.SetCurrentRailType(job.rail);
  local n = GSController.GetSetting("build_per_tick");
  for (local i = 0; i < n && c.idx < c.actions.len(); i++) {
    if (!Act_Run(job, c.actions[c.idx])) {
      if (GSError.GetLastError() == GSError.ERR_NOT_ENOUGH_CASH) {
        c.state = "CONFIRM";
        Tools_Status(self, company, "Out of money at piece " + c.idx + "/" + c.actions.len() + ". Press Build connection to go on.");
        return false;
      }
      c.failed++;
    }
    c.idx++;
  }
  if (c.idx < c.actions.len()) return true;
  local done = "Connected " + Tools_TileName(c.ea) + " and " + Tools_TileName(c.eb) +
               (c.failed > 0 ? ", " + c.failed + " piece(s) failed (see the script log)" : "") + ".";
  Tools_ConnStop(s);
  s.end1 = -1;
  s.end2 = -1;
  UI_SetText(self, company, "t_csel", "End 1: - | End 2: -");
  Tools_Log(self, company, done);
  return false;
}

function Tools_Buy(self, company, s)
{
  local stops = s.route != null ? s.route : [s.st1, s.st2];
  if (s.depot < 0 || (s.route == null && (s.st1 < 0 || s.st2 < 0))) {
    Tools_Status(self, company, "Pick the depot and both stations (or Find stations from the depot) first.");
    return;
  }
  local bad = !GSRail.IsRailDepotTile(s.depot);
  foreach (t in stops) if (!Tools_OwnStation(t, company)) bad = true;
  if (bad) { Tools_Status(self, company, "The depot or a station is gone. Pick them again."); return; }
  if (stops.len() == 2 && GSStation.GetStationID(stops[0]) == GSStation.GetStationID(stops[1])) {
    Tools_Status(self, company, "Station 1 and 2 are the same station.");
    return;
  }
  local rail = GSRail.GetRailType(s.depot);
  local plat = 0;
  foreach (t in stops) { local l = Tools_PlatLen(t); if (plat == 0 || l < plat) plat = l; }
  local cargo = Tools_CargoRoute(stops);
  if (cargo < 0) {
    Tools_Status(self, company, "Station 2 takes nothing that station 1 gets or has around it. Check the station catchment.");
    return;
  }
  // money: the engine and the most wagons that could fit, for every train
  local locos = Adv_Locos(rail);
  if (locos.len() == 0) { Tools_Status(self, company, "No engine for the rail type of this depot."); return; }
  local wagon = Adv_Wagon(cargo, rail, GSEngine.GetMaxSpeed(locos[0].loco));
  local n = TOOLS_COUNTS[s.count];
  local cost = n * (GSEngine.GetPrice(locos[0].loco) + (wagon >= 0 ? plat * 2 * GSEngine.GetPrice(wagon) : 0));
  local bank = GSCompany.GetBankBalance(GSCompany.COMPANY_SELF);
  if (cost > bank) { Tools_Status(self, company, "Not enough money: up to " + cost + " needed, you have " + bank + "."); return; }
  // 2 stations: full load at the first; a line of more stations just stops at each
  local text = Veh_Buy({ kind = "rail", stops = stops, cargo = cargo, full = stops.len() == 2, count = n, rail = rail, plat_len = plat }, s.depot);
  Tools_Log(self, company, GSCargo.GetName(cargo) + " " + Tools_TileName(stops[0]) + " > ... (" + stops.len() + " stations), platform " + plat + ":" + text);
}

/* A train of the company picked with a vehicle button. */
function Tools_OnVehicle(self, company, name, v)
{
  local mode = GSCompanyMode(company);
  if (!GSVehicle.IsValidVehicle(v) || GSVehicle.GetOwner(v) != company || GSVehicle.GetVehicleType(v) != GSVehicle.VT_RAIL) {
    Tools_Status(self, company, "Pick one of your trains.");
    return;
  }
  if (name == "t_clone") Tools_Clone(self, company, v);
  else if (name == "t_fill") Tools_FillStart(self, company, v);
}

function Tools_Clone(self, company, v)
{
  local rail = GSEngine.GetRailType(GSVehicle.GetEngineType(v));
  local depot = GSVehicle.IsInDepot(v) ? GSVehicle.GetLocation(v) : Veh_FindDepot(GSVehicle.GetLocation(v), rail, 100);
  if (depot < 0) { Tools_Status(self, company, "No depot of this rail type within 100 tiles of the train."); return; }
  local n = TOOLS_COUNTS[Tools_State(self, company).count];
  local made = 0, why = "";
  for (local i = 0; i < n; i++) {
    local c = GSVehicle.CloneVehicle(depot, v, true);
    if (!GSVehicle.IsValidVehicle(c)) { why = GSError.GetLastErrorString(); break; }
    GSVehicle.StartStopVehicle(c);
    made++;
  }
  Tools_Log(self, company, GSVehicle.GetName(v) + ": " + made + " cop" + (made == 1 ? "y" : "ies") + " bought" + (made < n ? " (" + why + ")" : "") + ".");
}

/* Shortest platform among the stations in the train's orders, 0 = none. */
function Tools_OrderPlatLen(v)
{
  local best = 0;
  for (local i = 0; i < GSOrder.GetOrderCount(v); i++) {
    if (!GSOrder.IsGotoStationOrder(v, i)) continue;
    local len = Tools_PlatLen(GSOrder.GetOrderDestination(v, i));
    if (len > 0 && (best == 0 || len < best)) best = len;
  }
  return best;
}

function Tools_FillStart(self, company, v)
{
  if (GSVehicle.GetNumWagons(v) < 2) { Tools_Status(self, company, GSVehicle.GetName(v) + " has no wagon to copy."); return; }
  local len = Tools_OrderPlatLen(v);
  if (len == 0) { Tools_Status(self, company, GSVehicle.GetName(v) + " has no orders to a rail station."); return; }
  if (GSVehicle.IsStoppedInDepot(v)) { Tools_Fill(self, company, v, len); return; }
  if (!GSVehicle.SendVehicleToDepot(v)) { Tools_Status(self, company, "Cannot send " + GSVehicle.GetName(v) + " to a depot: " + GSError.GetLastErrorString()); return; }
  Tools_State(self, company).wait.append({ v = v, len = len, t0 = GSDate.GetCurrentDate() });
  Tools_Status(self, company, GSVehicle.GetName(v) + " is going to a depot, the wagons follow there.");
}

/* Cargo the train carries most of. */
function Tools_TrainCargo(v)
{
  local best = -1, best_c = 0;
  local list = GSCargoList();
  for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
    local cap = GSVehicle.GetCapacity(v, c);
    if (cap > best_c) { best = c; best_c = cap; }
  }
  return best;
}

/* Train v stopped in a depot: wagons up to plat platform tiles, then go. */
function Tools_Fill(self, company, v, plat)
{
  local depot = GSVehicle.GetLocation(v);
  local max_len = plat * 16;   // vehicle length is in 1/16 of a tile
  local before = GSVehicle.GetNumWagons(v);
  local wagon = GSVehicle.GetWagonEngineType(v, before - 1);
  local cargo = Tools_TrainCargo(v);
  local why = "";
  // too long: drop wagons from the end (keep at least one)
  while (GSVehicle.GetLength(v) > max_len && GSVehicle.GetNumWagons(v) > 2) {
    if (!GSVehicle.SellWagon(v, GSVehicle.GetNumWagons(v) - 1)) break;
  }
  // too short: add wagons while they fit
  for (local i = 0; i < 40 && GSVehicle.GetLength(v) < max_len; i++) {
    local w = Veh_Build(depot, wagon, cargo);
    if (!GSVehicle.IsValidVehicle(w)) { why = GSError.GetLastErrorString(); break; }
    if (!GSVehicle.MoveWagon(w, 0, v, GSVehicle.GetNumWagons(v) - 1)) {
      why = GSError.GetLastErrorString();
      GSVehicle.SellVehicle(w);
      break;
    }
    if (GSVehicle.GetLength(v) > max_len) {
      GSVehicle.SellWagon(v, GSVehicle.GetNumWagons(v) - 1);
      break;
    }
  }
  GSVehicle.StartStopVehicle(v);
  local d = GSVehicle.GetNumWagons(v) - before;
  Tools_Log(self, company, GSVehicle.GetName(v) + ": " + (d >= 0 ? "+" : "") + d + " wagons, now " + (GSVehicle.GetNumWagons(v) - 1) +
    " for platform " + plat + (why != "" ? " (" + why + ")" : "") + ".");
}

/* Trains on their way to a depot for Fill wagons, track connections.
 * Called every loop. Returns true while a connection is searched or built. */
function Tools_Tick(self)
{
  local busy = false;
  foreach (company, s in self.tools) {
    if (s.wait.len() == 0 && s.conn == null) continue;
    if (GSCompany.ResolveCompanyID(company) == GSCompany.COMPANY_INVALID) { s.wait = []; s.conn = null; continue; }
    local mode = GSCompanyMode(company);
    if (s.conn != null) {
      ::g_ctx = { self = self, company = company };
      try {
        if (Tools_ConnTick(self, company, s)) busy = true;
      } catch (e) {
        ::g_ctx = null;
        Tools_ConnStop(s);
        Tools_Log(self, company, "Internal error, connection cancelled: " + e);
        throw e;
      }
      ::g_ctx = null;
    }
    local keep = [];
    foreach (w in s.wait) {
      if (!GSVehicle.IsValidVehicle(w.v)) continue;
      if (GSVehicle.IsStoppedInDepot(w.v)) {
        Tools_Fill(self, company, w.v, w.len);
      } else if (GSDate.GetCurrentDate() - w.t0 > 60) {
        Tools_Log(self, company, GSVehicle.GetName(w.v) + " did not reach a depot in 2 months, wagons not changed.");
      } else {
        keep.append(w);
      }
    }
    s.wait = keep;
  }
  return busy;
}
