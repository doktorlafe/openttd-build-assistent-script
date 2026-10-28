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
    ["t_auto", GSStoryPage.SPET_BUTTON_PUSH, push, "Auto: on / off (watches your depots and track ends)"],
    ["t_ashow", GSStoryPage.SPET_BUTTON_PUSH, push, "Show what Auto sees (signs on the map): on / off"],
    ["t_asel", GSStoryPage.SPET_TEXT, 0, "Auto: ON | signs: OFF | waiting for the first look."],
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
    ["t_dbl", GSStoryPage.SPET_BUTTON_TILE, pick, "Double track: click a tile of a single track"],
    ["t_title5", GSStoryPage.SPET_TEXT, 0, "--- Buses / trucks: A and B (town or industry), road, stops, depot, vehicles ---"],
    ["t_ra", GSStoryPage.SPET_BUTTON_TILE, pick, "A"],
    ["t_rb", GSStoryPage.SPET_BUTTON_TILE, pick, "B"],
    ["t_rplan", GSStoryPage.SPET_BUTTON_PUSH, push, "Plan road"],
    ["t_rbuild", GSStoryPage.SPET_BUTTON_PUSH, go, "Build road"],
    ["t_rcancel", GSStoryPage.SPET_BUTTON_PUSH, stop, "Cancel"],
    ["t_rsel", GSStoryPage.SPET_TEXT, 0, "A: - | B: -"],
    ["t_title6", GSStoryPage.SPET_TEXT, 0, "--- Fleet care: once a month, lines with waiting cargo or a queue ---"],
    ["t_fleet", GSStoryPage.SPET_BUTTON_PUSH, push, "Fleet care: off / report / do it"],
    ["t_fsel", GSStoryPage.SPET_TEXT, 0, "Fleet care: on (buys and sells by itself)"],
    ["t_title4", GSStoryPage.SPET_TEXT, 0, "--- Town bus loop ---"],
    ["t_loop", GSStoryPage.SPET_BUTTON_TILE, pick, "Bus loop in a town"],
    ["t_title7", GSStoryPage.SPET_TEXT, 0, "--- Distance: click two tiles ---"],
    ["t_ma", GSStoryPage.SPET_BUTTON_TILE, pick, "Point A"],
    ["t_mb", GSStoryPage.SPET_BUTTON_TILE, pick, "Point B"],
    ["t_msel", GSStoryPage.SPET_TEXT, 0, "A: - | B: -"],
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
    "Buses / trucks: A and B = a town or an industry (within 4 tiles of it). Plan road finds the road, Build road builds it with stops, a depot and vehicles (setting veh_road).",
    "Show what Auto sees: signs \"auto: end\" on every track end it found and, at every depot, why it did or did not buy trains. The Auto line shows the counts of the last look.",
    "Double track: click the button, then any plain tile of a single track. The track is followed both ways up to a switch, a station, a depot or its end, and a second track is built right beside it (curves, bridges and tunnels too), on the side where it fits. Its ends stay open: connect them to your stations yourself (or Auto connects ends that point at each other).",
    "Distance: click Point A and Point B, then a tile each. It shows the Manhattan distance (the one the game pays cargo by), dx / dy and the straight line.",
    "Fleet care: off / report (only writes what it would do) / do it. Once a month a line with more than 2 loads waiting at its first station gets a vehicle; a line with 2+ vehicles stuck in a queue and little cargo sells one. Lines older than 3 months that make money, at most 8 trains / 15 road vehicles.",
    "Auto (on at start): the assistant watches your map. Two track ends that point at each other (setting auto_range, 1000 tiles) and did not change for auto_wait days get connected (a double track as a pair). A new depot whose track reaches 2+ stations without trains gets trains (How many). A depot click buys at once, found ways are built without asking. Off: only your buttons.",
    "Build connection: builds it (again after running out of money: it goes on where it stopped). Cancel: stops and removes the signs."
  ];
}

/* A human player? GSCompany.IsHuman when the game has it, else: the company
 * clicked something on the tools page (an AI never does). */
function Tools_IsHuman(company, s)
{
  if (s.rawin("human") && s.human) return true;
  if ("IsHuman" in GSCompany) return GSCompany.IsHuman(company);
  return false;
}

/* Per company state. */
function Tools_State(self, company)
{
  if (!self.tools.rawin(company))
    self.tools.rawset(company, { depot = -1, st1 = -1, st2 = -1, route = null, count = 0, wait = [], end1 = -1, end2 = -1, conn = null,
                                 fleet = Tools_IsLight() ? 2 : 0, fleet_next = 0, manual = false,
                                 watch_next = 0, ends = {}, failed = {},
                                 depots_done = {}, depot_seen = {}, depot_retry = {},
                                 show = false, asigns = [], depot_why = {} });
  return self.tools.rawget(company);
}

/* Builds the light pages for a company into p (p.page = the tools page). */
function Tools_Pages(self, company, p)
{
  local page = GSStoryPage.New(company, "Build assistant - tools");
  if (page == GSStoryPage.STORY_PAGE_INVALID) return false;
  p.page = page;
  foreach (it in Tools_DistFilter(Tools_Items())) {
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
  if (!Tools_IsLight()) UI_SetText(self, company, "status", "Status: " + text);   // classic page
  Tools_State(self, company).last_status <- text;
}

function Tools_StatusText(self, company)
{
  local s = Tools_State(self, company);
  return s.rawin("last_status") ? s.last_status : "?";
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
  if (!Tools_IsLight()) UI_Diag(self, company, "i", text);   // classic page: its own log
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
  local found = Tools_Walk([[depot, GSRail.GetRailDepotFrontTile(depot)]], company, null);
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

/* Follows the company's track from the queue entries [from, tile]. Returns
 * the station tiles reached (one per station, in the order reached); when
 * ends is a table, every dead end of the track goes into it (tile -> direction). */
function Tools_Walk(queue, company, ends)
{
  local seen = {}, found = [], ids = {};
  local qi = 0;
  while (qi < queue.len() && qi < 200000) {
    local prev = queue[qi][0], t = queue[qi][1];
    qi++;
    if (t < 0 || !Tools_HasRail(t) || GSTile.GetOwner(t) != company || GSRail.IsRailDepotTile(t)) continue;
    local far = GSMap.DistanceManhattan(prev, t) > 1;   // came over a bridge or through a tunnel
    local dir = U_DirOf(prev, t);
    local key = t * 4 + dir;
    if (seen.rawin(key)) continue;
    seen.rawset(key, true);
    if (GSRail.IsRailStationTile(t)) {
      local sid = GSStation.GetStationID(t);
      if (!ids.rawin(sid)) { ids.rawset(sid, true); found.append(t); }
    } else if (ends != null && !ends.rawin(t)) {
      local d = Tools_EndDir(t);
      if (d >= 0) ends.rawset(t, d);
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
  return found;
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
  s.human <- true;
  if (name == "t_ra" || name == "t_rb") {
    local target = Tg_FromTile(t);
    if (target == null) { Tools_Status(self, company, "Nothing there to connect."); return; }
    local p = UI_Pick(self, company);
    if (name == "t_ra") p.a = target; else p.b = target;
    UI_SetText(self, company, "t_rsel", "A: " + Tg_Name(p.a) + " | B: " + Tg_Name(p.b));
    Tools_Status(self, company, p.a != null && p.b != null ? "Press Plan road." : "Pick the other end.");
    return;
  }
  if (name == "t_loop") {
    local town = GSTile.GetClosestTown(t);
    if (!GSTown.IsValidTown(town)) { Tools_Status(self, company, "No town there."); return; }
    Tools_Status(self, company, "Building bus loop in " + GSTown.GetName(town) + " ...");
    local mode = GSCompanyMode(company);
    Tools_Log(self, company, Loop_Build(town, GSController.GetSetting("loop_stops"), GSController.GetSetting("loop_gap"),
                                        GSController.GetSetting("veh_loop")));
    return;
  }
  if (name == "t_ma" || name == "t_mb") {
    if (name == "t_ma") s.ma <- t; else s.mb <- t;
    UI_SetText(self, company, "t_msel", Tools_DistText(s));
    return;
  }
  if (name == "t_dbl") {
    local mode = GSCompanyMode(company);
    Tools_DoubleStart(self, company, s, t);
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
    if (!s.manual) {
      // auto: stations from the depot and the trains in one click
      local r = Tools_FindStations(t, company);
      if (r.len() < 2) { Tools_Selection(self, company); Tools_Status(self, company, "From this depot the track reaches " + r.len() + " station(s), at least 2 are needed."); return; }
      while (r.len() > 10) r.pop();
      s.route = r;
      Tools_Selection(self, company);
      local mode = GSCompanyMode(company);
      Tools_Buy(self, company, s);
      return;
    }
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
  s.human <- true;
  if (name == "t_count") {
    s.count = (s.count + 1) % TOOLS_COUNTS.len();
    Tools_Selection(self, company);
  } else if (name == "t_auto") {
    s.manual = !s.manual;
    Tools_Status(self, company, s.manual ? "Auto off: you confirm the plans and press Buy trains." : "Auto on: a depot click buys trains, found ways are built at once.");
    if (s.manual) { Preview_Clear(s.asigns); s.asigns = []; }
    s.watch_next = 0;
    Tools_AutoLine(self, company, s);
  } else if (name == "t_ashow") {
    s.show = !s.show;
    if (!s.show) { Preview_Clear(s.asigns); s.asigns = []; }
    s.watch_next = 0;   // look again now
    Tools_AutoLine(self, company, s);
    Tools_Status(self, company, s.show ? "Auto signs on: \"auto: end\" = a track end it sees, at depots the reason. They update once a day." : "Auto signs off.");
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
  } else if (name == "t_rplan") {
    // the road planner of the full assistant
    local p = UI_Pick(self, company);
    p.mode = MODE_ROAD;
    p.list = [];
    p.transfer = false;
    self.OnButton(company, "plan");
    // auto: the road gets built as soon as it is planned
    if (!s.manual && self.jobs.rawin(company)) self.jobs.rawget(company).auto <- true;
  } else if (name == "t_rbuild") {
    self.OnButton(company, "confirm");
  } else if (name == "t_rcancel") {
    self.OnButton(company, "cancel");
  } else if (name == "t_fleet") {
    s.fleet = (s.fleet + 1) % 3;
    s.fleet_next = 0;
    Tools_FleetText(self, company, s);
  } else if (name == "t_ccancel") {
    Tools_ConnStop(s);
    Tools_Status(self, company, "Connection cancelled.");
  }
}

/* Rail on tile t, also a rail bridge head, tunnel entrance or depot
 * (GSRail.IsRailTile is false for those). */
function Tools_HasRail(t)
{
  if (GSRail.IsRailTile(t) || GSRail.IsRailDepotTile(t)) return true;
  return (GSBridge.IsBridgeTile(t) || GSTunnel.IsTunnelTile(t)) && GSRail.GetRailType(t) != GSRail.RAILTYPE_INVALID;
}

/* Direction (0..3) in which the track on tile e stops, or -1: a track piece
 * on e leads to a neighbour that has no track. */
function Tools_EndDir(e)
{
  if (!GSRail.IsRailTile(e) || GSRail.IsRailStationTile(e) || GSRail.IsRailDepotTile(e) || U_IsSpecial(e)) return -1;
  for (local i = 0; i < 4; i++) {
    local n = U_Step(e, i);
    if (n < 0 || Tools_HasRail(n)) continue;
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

/* The second track as an exact parallel copy of path p1 on side job.twin:
 * straight = the tile beside it, a bend away from the twin side = the outer
 * arc (one corner tile more), a bend towards it = the inner arc (one less),
 * a bridge or tunnel = one beside it. tr1/tr2 = the two tracks' ends.
 * Returns the path, or null when it does not fit (then it is searched). */
function Tools_Parallel(job, p1, tr1, tr2)
{
  local tw = job.twin;
  if (tw < 0) return null;
  local t = p1.tiles, k = p1.kinds, n = t.len();
  local out = [], kinds = [];
  local dins = [], douts = [], own = {};
  for (local j = 0; j < n; j++) {
    dins.append(j == 0 ? tr1.da : U_DirOf(t[j - 1], t[j]));
    douts.append(j == n - 1 ? (tr1.db + 2) % 4 : U_DirOf(t[j], t[j + 1]));
    own.rawset(t[j], true);
  }
  for (local j = 0; j < n; j++) {
    local din = dins[j], dout = douts[j];
    local s1 = U_Step(t[j], (din + tw) % 4);
    if (s1 < 0) return null;
    if (j > 0 && k[j] != 0) {   // the far head of a bridge / tunnel
      out.append(s1);
      kinds.append(k[j]);
      continue;
    }
    local add = [];
    if (din == dout) add = [s1];
    else if ((din + tw) % 4 == dout) {
      // inner side of a bend: the tile diagonally inside it (the same tile the
      // straight before / after ends on; in a diagonal it is the next step)
      local d = U_Step(U_Step(t[j], (din + 2) % 4), dout);
      if (d < 0) return null;
      add = [d];
    }
    else if ((din + 2) % 4 == dout) return null;
    else if ((j > 0 && dins[j - 1] != douts[j - 1]) || (j + 1 < n && dins[j + 1] != douts[j + 1])) {
      // outer side of a bend inside a diagonal: the second track takes the
      // other half of this very tile (diagonal double track touching)
      local s2 = U_Step(t[j], (dout + tw) % 4);
      if (s2 < 0) return null;
      add = [s1, t[j], s2];
    }
    else {                                              // outer arc of a single bend: corner tile
      local corner = U_Step(s1, (dout + tw) % 4);
      local s2 = U_Step(t[j], (dout + tw) % 4);
      if (corner < 0 || s2 < 0) return null;
      add = [s1, corner, s2];
    }
    foreach (x in add) {
      if (out.len() > 0 && out[out.len() - 1] == x) continue;
      out.append(x);
      kinds.append(0);
    }
  }
  if (out.len() == 0) return null;
  if (tr2 != null && (out[0] != U_Step(tr2.a, tr2.da) || out[out.len() - 1] != U_Step(tr2.b, tr2.db))) return null;
  // every tile free, every piece fits the land (test mode: nothing is built)
  local full = [tr2 != null ? tr2.a : U_Step(out[0], (tr1.da + 2) % 4)];
  foreach (x in out) full.append(x);
  full.append(tr2 != null ? tr2.b : U_Step(out[out.len() - 1], (tr1.db + 2) % 4));
  if (full[0] < 0 || full[full.len() - 1] < 0) return null;
  local tm = GSTestMode();
  for (local i = 0; i < out.len(); i++) {
    local prev = full[i], x = out[i], next = full[i + 2];
    if (kinds[i] == 1) {
      if (!U_TestBridge(GSVehicle.VT_RAIL, prev, x)) return null;
      continue;
    }
    if (kinds[i] == 2) {
      if (GSTunnel.GetOtherTunnelEnd(prev) != x) return null;
      continue;
    }
    if (GSMap.DistanceManhattan(prev, x) != 1) return null;
    if (!own.rawin(x) && PathRail_Cost(job, x) < 0 && !PathRail_CanCross(job, x, U_DirOf(prev, x))) return null;
    if (i + 1 < out.len() && kinds[i + 1] != 0) continue;   // a bridge / tunnel head: no piece
    if (!GSRail.BuildRail(prev, x, next) && GSError.GetLastError() != GSError.ERR_ALREADY_BUILT &&
        GSError.GetLastError() != GSError.ERR_NOT_ENOUGH_CASH) return null;
  }
  return { tiles = out, kinds = kinds, first = full[0], last = full[full.len() - 1] };
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
  job.twin_pen <- 6;    // the first track keeps room beside it, so the second one can be a copy
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
    // first try: an exact parallel copy of the first track (no search at all)
    if (!c.rawin("copy_tried")) {
      c.copy_tried <- true;
      job.near <- {};
      job.tight <- false;
      local p2 = Tools_Parallel(job, c.paths[0], c.tracks[0], c.tracks[1]);
      if (p2 != null) {
        c.paths.append(p2);
        Tools_ConnNext(self, company, s);
        return;
      }
      U_Log("i", "Connect: track 2 cannot run right beside track 1 everywhere, searching it");
      Job_ResetCache(job);
    }
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
  if (!s.manual) {
    c.state = "BUILD";
    Tools_Status(self, company, "Way found (" + c.paths[0].tiles.len() + " tiles, about " + cost + "), building ...");
    return;
  }
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
        if (c.rawin("auto_key")) s.failed.rawset(c.auto_key, [c.ea, c.eb]);
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
  if (c.state == "CASH" && GSDate.GetCurrentDate() >= c.retry) c.state = "BUILD";
  if (c.state != "BUILD") return false;
  GSRail.SetCurrentRailType(job.rail);
  local n = GSController.GetSetting("build_per_tick");
  for (local i = 0; i < n && c.idx < c.actions.len(); i++) {
    if (!Act_Run(job, c.actions[c.idx])) {
      if (GSError.GetLastError() == GSError.ERR_NOT_ENOUGH_CASH) {
        c.state = "CONFIRM";
        if (!s.manual) {
          // auto: goes on by itself in a week
          c.state = "CASH";
          c.retry <- GSDate.GetCurrentDate() + 7;
          Tools_Status(self, company, "Out of money at piece " + c.idx + "/" + c.actions.len() + ", trying again in a week.");
          return false;
        }
        Tools_Status(self, company, "Out of money at piece " + c.idx + "/" + c.actions.len() + ". Press Build connection to go on.");
        return false;
      }
      c.failed++;
    }
    c.idx++;
  }
  if (c.idx < c.actions.len()) return true;
  local fails = c.failed > 0 ? ", " + c.failed + " piece(s) failed (see the script log)" : "";
  if (c.rawin("label")) {   // double track: the picked ends stay
    Tools_ConnStop(s);
    Tools_Log(self, company, c.label + fails + ".");
    return false;
  }
  local done = "Connected " + Tools_TileName(c.ea) + " and " + Tools_TileName(c.eb) + fails + ".";
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
    return "bad";
  }
  local bad = !GSRail.IsRailDepotTile(s.depot);
  foreach (t in stops) if (!Tools_OwnStation(t, company)) bad = true;
  if (bad) { Tools_Status(self, company, "The depot or a station is gone. Pick them again."); return "bad"; }
  if (stops.len() == 2 && GSStation.GetStationID(stops[0]) == GSStation.GetStationID(stops[1])) {
    Tools_Status(self, company, "Station 1 and 2 are the same station.");
    return "none";
  }
  local rail = GSRail.GetRailType(s.depot);
  local plat = 0;
  foreach (t in stops) { local l = Tools_PlatLen(t); if (plat == 0 || l < plat) plat = l; }
  local cargo = Tools_CargoRoute(stops);
  if (cargo < 0) {
    Tools_Status(self, company, "Station 2 takes nothing that station 1 gets or has around it. Check the station catchment.");
    return "none";
  }
  // money: the engine and the most wagons that could fit, for every train
  local locos = Adv_Locos(rail);
  if (locos.len() == 0) { Tools_Status(self, company, "No engine for the rail type of this depot."); return "none"; }
  local wagon = Adv_Wagon(cargo, rail, GSEngine.GetMaxSpeed(locos[0].loco));
  local n = TOOLS_COUNTS[s.count];
  local cost = n * (GSEngine.GetPrice(locos[0].loco) + (wagon >= 0 ? plat * 2 * GSEngine.GetPrice(wagon) : 0));
  local bank = GSCompany.GetBankBalance(GSCompany.COMPANY_SELF);
  if (cost > bank) { Tools_Status(self, company, "Not enough money: up to " + cost + " needed, you have " + bank + "."); return "cash"; }
  // 2 stations: full load at the first; a line of more stations just stops at each
  local text = Veh_Buy({ kind = "rail", stops = stops, cargo = cargo, full = stops.len() == 2, count = n, rail = rail, plat_len = plat }, s.depot);
  Tools_Log(self, company, GSCargo.GetName(cargo) + " " + Tools_TileName(stops[0]) + " > ... (" + stops.len() + " stations), platform " + plat + ":" + text);
  return "ok";
}

/* A train of the company picked with a vehicle button. */
function Tools_OnVehicle(self, company, name, v)
{
  Tools_State(self, company).human <- true;
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
    // nothing by itself for an AI company: only after a click on the tools page
    if (!Tools_IsHuman(company, s)) continue;
    if (s.fleet > 0 && GSDate.GetCurrentDate() >= s.fleet_next) {
      s.fleet_next = GSDate.GetCurrentDate() + 30;
      if (GSCompany.ResolveCompanyID(company) != GSCompany.COMPANY_INVALID) {
        local fm = GSCompanyMode(company);
        Tools_Fleet(self, company, s);
      }
    }
    // classic mode: only the track end connection, and not while a planned route is being built
    local watch = Tools_IsLight() ? !s.manual :
                  GSController.GetSetting("auto_connect_full") != 0 && !(self.jobs.rawin(company) && Job_IsActive(self.jobs.rawget(company)));
    if (watch && s.conn == null && GSCompany.ResolveCompanyID(company) != GSCompany.COMPANY_INVALID) {
      local wm = GSCompanyMode(company);
      ::g_ctx = { self = self, company = company };
      try {
        Tools_Watch(self, company, s);
      } catch (e) {
        ::g_ctx = null;
        Tools_Log(self, company, "Internal error in Auto: " + e);
        throw e;
      }
      ::g_ctx = null;
    }
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
        if (w.rawin("sell")) {
          local vn = GSVehicle.GetName(w.v);
          if (GSVehicle.SellVehicle(w.v)) Tools_Log(self, company, "Fleet care: " + vn + " sold.");
        } else {
          Tools_Fill(self, company, w.v, w.len);
        }
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

/* Fleet care ---------------------------------------------------------------- */

function Tools_FleetText(self, company, s)
{
  local t = ["off", "report only (writes what it would do)", "on (buys and sells by itself)"][s.fleet];
  UI_SetText(self, company, "t_fsel", "Fleet care: " + t);
  Tools_Status(self, company, "Fleet care: " + t + ".");
}

/* Saved with the game: the fleet care mode per company. */
function Tools_SaveData(self)
{
  local out = {};
  foreach (c, s in self.tools) out.rawset(c, { fleet = s.fleet, human = s.rawin("human") && s.human });
  return out;
}

function Tools_LoadData(self, d)
{
  foreach (c, m in d) {
    local s = Tools_State(self, c);
    if (typeof m == "table") {
      s.fleet = m.fleet;
      if (m.human) s.human <- true;
    } else {
      s.fleet = m;
    }
  }
}

/* One look at every line (vehicles sharing their orders) of the company. */
function Tools_Fleet(self, company, s)
{
  local act = s.fleet == 2;
  local seen = {};
  local all = GSVehicleList();
  for (local v = all.Begin(); !all.IsEnd(); v = all.Next()) {
    if (seen.rawin(v)) continue;
    local type = GSVehicle.GetVehicleType(v);
    if (type != GSVehicle.VT_RAIL && type != GSVehicle.VT_ROAD) continue;
    local group = GSVehicleList_SharedOrders(v);
    if (group.IsEmpty()) group.AddItem(v, 0);
    for (local g = group.Begin(); !group.IsEnd(); g = group.Next()) seen.rawset(g, true);
    if (GSOrder.GetOrderCount(v) < 2) continue;
    local first = -1;
    for (local i = 0; i < GSOrder.GetOrderCount(v) && first < 0; i++)
      if (GSOrder.IsGotoStationOrder(v, i)) first = GSStation.GetStationID(GSOrder.GetOrderDestination(v, i));
    if (!GSStation.IsValidStation(first)) continue;
    local cargo = Tools_TrainCargo(v);
    if (cargo < 0) continue;
    // a young line or one that loses money is left alone
    local n = 0, young = false, profit = 0, stuck = -1, nstuck = 0;
    for (local g = group.Begin(); !group.IsEnd(); g = group.Next()) {
      n++;
      if (GSVehicle.GetAge(g) < 90) young = true;
      profit += GSVehicle.GetProfitLastYear(g);
      // standing on the line (a signal or a queue), not loading at a station
      if (GSVehicle.GetState(g) == GSVehicle.VS_RUNNING && GSVehicle.GetCurrentSpeed(g) == 0) { nstuck++; stuck = g; }
    }
    if (young || profit < 0) continue;
    local cap = max(1, GSVehicle.GetCapacity(v, cargo));
    local waiting = GSStation.GetCargoWaiting(first, cargo);
    local limit = type == GSVehicle.VT_RAIL ? 8 : 15;
    local line = GSVehicle.GetName(v) + " (" + GSStation.GetName(first) + ", " + n + " vehicles)";
    if (waiting > 2 * cap && n < limit) {
      if (!act) { Tools_Log(self, company, "Fleet care would add a vehicle to " + line + ": " + waiting + " " + GSCargo.GetName(cargo) + " waiting."); continue; }
      local rail = type == GSVehicle.VT_RAIL ? GSEngine.GetRailType(GSVehicle.GetEngineType(v)) : -1;
      local depot = Veh_FindDepot(GSStation.GetLocation(first), rail, 40);
      if (depot < 0) { Tools_Log(self, company, "Fleet care: no depot near " + GSStation.GetName(first) + " for " + line + "."); continue; }
      local c = GSVehicle.CloneVehicle(depot, v, true);
      if (!GSVehicle.IsValidVehicle(c)) { Tools_Log(self, company, "Fleet care: could not add to " + line + ": " + GSError.GetLastErrorString()); continue; }
      GSVehicle.StartStopVehicle(c);
      Tools_Log(self, company, "Fleet care: +1 vehicle for " + line + ", " + waiting + " " + GSCargo.GetName(cargo) + " were waiting.");
    } else if (nstuck >= 2 && n > 1 && waiting < cap) {
      if (!act) { Tools_Log(self, company, "Fleet care would sell a vehicle of " + line + ": " + nstuck + " stand in a queue, little cargo."); continue; }
      local busy = false;
      foreach (w in s.wait) if (w.v == stuck) busy = true;
      if (busy || !GSVehicle.SendVehicleToDepot(stuck)) continue;
      s.wait.append({ v = stuck, len = 0, t0 = GSDate.GetCurrentDate(), sell = true });
      Tools_Log(self, company, "Fleet care: " + GSVehicle.GetName(stuck) + " of " + line + " goes to the depot to be sold (" + nstuck + " in a queue).");
    }
  }
}

/* Auto ---------------------------------------------------------------------- */

/* The watch, once a day: follows your track from all your rail stations and
 * depots, then connects track ends and buys trains for new depots. */
function Tools_Watch(self, company, s)
{
  local now = GSDate.GetCurrentDate();
  if (now < s.watch_next) return;
  s.watch_next = now + 1;
  local queue = [];
  local sl = GSStationList(GSStation.STATION_TRAIN);
  for (local sid = sl.Begin(); !sl.IsEnd(); sid = sl.Next()) {
    local tl = GSTileList_StationType(sid, GSStation.STATION_TRAIN);
    for (local t = tl.Begin(); !tl.IsEnd(); t = tl.Next()) {
      local step = GSRail.GetRailStationDirection(t) == GSRail.RAILTRACK_NE_SW ? [0, 2] : [1, 3];
      foreach (i in step) {
        local n = U_Step(t, i);
        if (n >= 0 && !(GSRail.IsRailStationTile(n) && GSStation.GetStationID(n) == sid)) queue.append([t, n]);
      }
    }
  }
  local dl = GSDepotList(GSTile.TRANSPORT_RAIL);
  for (local t = dl.Begin(); !dl.IsEnd(); t = dl.Next()) queue.append([t, GSRail.GetRailDepotFrontTile(t)]);
  local found = {};
  Tools_Walk(queue, company, found);
  // the day an end was first seen stays while it does not change
  local ends = {};
  foreach (t, d in found) {
    local seen = s.ends.rawin(t) && s.ends.rawget(t).d == d ? s.ends.rawget(t).seen : now;
    ends.rawset(t, { d = d, seen = seen });
  }
  s.ends = ends;
  if (!Tools_PairEnds(self, company, s) && Tools_IsLight()) Tools_WatchDepots(self, company, s);
  Tools_AutoReport(self, company, s, sl.Count(), dl.Count());
}

/* The Auto line: on / off, signs on / off and the last look. */
function Tools_AutoLine(self, company, s)
{
  UI_SetText(self, company, "t_asel", "Auto: " + (s.manual ? "OFF" : "ON") + " | signs: " + (s.show ? "ON" : "OFF") +
    (s.manual ? "" : " | " + (s.rawin("auto_report") ? s.auto_report : "waiting for the first look.")));
}

/* The Auto line on the tools page and, when switched on, signs on the map. */
function Tools_AutoReport(self, company, s, n_st, n_dep)
{
  local now = GSDate.GetCurrentDate(), wait = GSController.GetSetting("auto_wait");
  local old = 0;
  foreach (t, e in s.ends) if (now - e.seen >= wait) old++;
  local busy = s.conn != null ? ", connecting " + Tools_TileName(s.conn.ea) + " - " + Tools_TileName(s.conn.eb) : "";
  s.auto_report <- "last look " + GSDate.GetMonth(now) + "/" + GSDate.GetDayOfMonth(now) + ": " + n_st + " stations, " +
    n_dep + " depots, " + s.ends.len() + " track ends (" + old + " ready), " + s.failed.len() + " pair(s) failed" + busy + ".";
  Tools_AutoLine(self, company, s);
  Preview_Clear(s.asigns);
  s.asigns = [];
  if (!s.show) return;
  foreach (t, e in s.ends) {
    if (s.asigns.len() >= 60) break;
    local id = GSSign.BuildSign(t, "auto: end " + ["+x", "+y", "-x", "-y"][e.d] + (now - e.seen < wait ? " (new)" : ""));
    if (GSSign.IsValidSign(id)) s.asigns.append(id);
  }
  foreach (t, why in s.depot_why) {
    if (s.asigns.len() >= 90) break;
    if (!GSRail.IsRailDepotTile(t)) continue;
    local id = GSSign.BuildSign(t, U_Clip("auto: " + why));
    if (GSSign.IsValidSign(id)) s.asigns.append(id);
  }
}

/* Does tile f lie ahead of the end on tile t that stops in direction d? */
function Tools_Ahead(t, d, f)
{
  local dx = GSMap.GetTileX(f) - GSMap.GetTileX(t), dy = GSMap.GetTileY(f) - GSMap.GetTileY(t);
  local fwd = [dx, dy, -dx, -dy][d];
  local side = (d % 2 == 0) ? dy : dx;
  if (side < 0) side = -side;
  return fwd > 0 && fwd * 3 >= side;
}

/* Starts the connection of the nearest pair of old enough ends that point at
 * each other. Returns true when one was started. */
function Tools_PairEnds(self, company, s)
{
  local now = GSDate.GetCurrentDate(), wait = GSController.GetSetting("auto_wait");
  local range = GSController.GetSetting("auto_range");
  local cand = [];
  foreach (t, e in s.ends) if (now - e.seen >= wait) cand.append([t, e.d]);
  // forget the failed pairs whose ends are gone
  local failed = {};
  foreach (k, v in s.failed) {
    if (s.ends.rawin(v[0]) && s.ends.rawin(v[1])) failed.rawset(k, v);
  }
  s.failed = failed;
  local best = null, best_d = range + 1;
  for (local i = 0; i < cand.len(); i++) {
    local twin = Tools_Twin(cand[i][0], cand[i][1], company);
    for (local j = i + 1; j < cand.len(); j++) {
      local a = cand[i][0], b = cand[j][0];
      local dist = GSMap.DistanceManhattan(a, b);
      if (dist >= best_d || dist < 2) continue;
      if (twin != null && twin[0] == b) continue;
      if (!Tools_Ahead(a, cand[i][1], b) || !Tools_Ahead(b, cand[j][1], a)) continue;
      local key = a < b ? "" + a + "_" + b : "" + b + "_" + a;
      if (s.failed.rawin(key)) continue;
      best = [a, b, key];
      best_d = dist;
    }
  }
  if (best == null) return false;
  // a double track: Tools_ConnStart finds the twin ends and connects both
  s.end1 = best[0];
  s.end2 = best[1];
  UI_SetText(self, company, "t_csel", "End 1: " + Tools_TileName(s.end1) + " | End 2: " + Tools_TileName(s.end2));
  Tools_Log(self, company, "Auto: connecting " + Tools_TileName(best[0]) + " and " + Tools_TileName(best[1]) + " (" + best_d + " tiles).");
  Tools_ConnStart(self, company, s);
  if (s.conn == null) { s.failed.rawset(best[2], [best[0], best[1]]); return false; }
  s.conn.auto_key <- best[2];
  return true;
}

/* A depot whose track reaches 2+ stations, at least one of them without a
 * train, gets trains over all of them. A depot is looked at again when the
 * stations its track reaches change (a new station on the line). */
function Tools_WatchDepots(self, company, s)
{
  local now = GSDate.GetCurrentDate(), wait = GSController.GetSetting("auto_wait");
  local list = GSDepotList(GSTile.TRANSPORT_RAIL);
  for (local t = list.Begin(); !list.IsEnd(); t = list.Next()) {
    if (GSTile.GetOwner(t) != company) continue;
    if (!s.depot_seen.rawin(t)) s.depot_seen.rawset(t, now);
    if (now - s.depot_seen.rawget(t) < wait) { s.depot_why.rawset(t, "new depot, waiting"); continue; }
    if (s.depot_retry.rawin(t) && now < s.depot_retry.rawget(t)) { s.depot_why.rawset(t, "no money, retry soon"); continue; }
    local r = Tools_FindStations(t, company);
    // the stations this depot reaches, as a text: when it changes, look again
    local sig = "";
    foreach (st in r) sig += GSStation.GetStationID(st) + ",";
    if (s.depots_done.rawin(t) && s.depots_done.rawget(t) == sig) continue;
    s.depots_done.rawset(t, sig);
    if (r.len() < 2) {
      s.depot_why.rawset(t, r.len() == 1 ? "only " + Tools_TileName(r[0]) + " reached" : "no station reached");
      if (r.len() == 1) Tools_Log(self, company, "Auto: depot at " + Tools_TileName(t) + " reaches only " + Tools_TileName(r[0]) + ", waiting for a 2nd station.");
      continue;
    }
    local empty = 0;
    foreach (st in r) {
      local vl = GSVehicleList_Station(GSStation.GetStationID(st));
      vl.Valuate(GSVehicle.GetVehicleType);
      vl.KeepValue(GSVehicle.VT_RAIL);
      if (vl.Count() == 0) empty++;
    }
    if (empty == 0) { s.depot_why.rawset(t, r.len() + " stations, all have trains"); continue; }
    while (r.len() > 10) r.pop();
    s.depot = t;
    s.route = r;
    Tools_Selection(self, company);
    Tools_Log(self, company, "Auto: depot at " + Tools_TileName(t) + " reaches " + r.len() + " stations (" + empty + " without trains), buying trains.");
    local res = Tools_Buy(self, company, s);
    if (res == "cash") { s.depots_done.rawdelete(t); s.depot_retry.rawset(t, now + 7); s.depot_why.rawset(t, "no money, retry soon"); return; }
    s.depot_why.rawset(t, res == "ok" ? "trains bought" : res == "cash" ? "no money, retry soon" : "no trains: see log");
    if (res != "ok") Tools_Log(self, company, "Auto: no trains bought: " + Tools_StatusText(self, company));
    return;   // one depot per pass
  }
}

/* Double track ---------------------------------------------------------------- */

/* One plain track piece on tile t (no switch, crossing, station or depot)? */
function Tools_Single(t, company)
{
  if (t < 0 || GSTile.GetOwner(t) != company) return false;
  if (GSBridge.IsBridgeTile(t) || GSTunnel.IsTunnelTile(t)) return GSRail.GetRailType(t) != GSRail.RAILTYPE_INVALID;
  if (!GSRail.IsRailTile(t)) return false;
  if (GSRail.IsRailStationTile(t) || GSRail.IsRailDepotTile(t) || GSRail.IsLevelCrossingTile(t)) return false;
  local b = GSRail.GetRailTracks(t);
  return b != GSRail.RAILTRACK_INVALID && b != 0 && (b & (b - 1)) == 0;
}

/* Follows the single track from tile `cur` (entered from `prev`) until a
 * switch, station, depot or its end. Returns { tiles, stop }: the tiles
 * passed and the tile it stopped in front of (-1 = a dead end). */
function Tools_FollowLine(prev, cur, company, seen)
{
  local tiles = [];
  for (local i = 0; i < 5000; i++) {
    if (cur < 0 || seen.rawin(cur) || !Tools_Single(cur, company)) {
      return { tiles = tiles, stop = (cur >= 0 && Tools_HasRail(cur)) ? cur : -1 };
    }
    local dir = U_DirOf(prev, cur);
    local far = GSMap.DistanceManhattan(prev, cur) > 1;
    seen.rawset(cur, true);
    tiles.append(cur);
    local other = -1;
    if (GSBridge.IsBridgeTile(cur)) other = GSBridge.GetOtherBridgeEnd(cur);
    else if (GSTunnel.IsTunnelTile(cur)) other = GSTunnel.GetOtherTunnelEnd(cur);
    if (other >= 0) {
      if (!far && U_DirOf(cur, other) == dir) { prev = cur; cur = other; }
      else { prev = cur; cur = U_Step(cur, dir); }
      continue;
    }
    local next = -1;
    for (local d = 0; d < 4; d++) {
      local n = U_Step(cur, d);
      if (n >= 0 && n != prev && GSRail.AreTilesConnected(prev, cur, n)) next = n;
    }
    if (next < 0) return { tiles = tiles, stop = -1 };   // the track ends here
    prev = cur;
    cur = next;
  }
  return { tiles = tiles, stop = -1 };
}

/* Builds a second track beside the single track through tile t. */
function Tools_DoubleStart(self, company, s, t)
{
  if (s.conn != null) { Tools_Status(self, company, "Busy with a connection, try again when it is built."); return; }
  if (!Tools_Single(t, company) || GSBridge.IsBridgeTile(t) || GSTunnel.IsTunnelTile(t)) {
    Tools_Status(self, company, "Click a plain tile of your single track (not a switch, bridge, station or depot).");
    return;
  }
  // the two neighbours the track piece on t joins
  local ends = [];
  for (local d = 0; d < 4; d++) {
    local n = U_Step(t, d);
    if (n < 0) continue;
    for (local e = d + 1; e < 4; e++) {
      local m = U_Step(t, e);
      if (m >= 0 && GSRail.AreTilesConnected(n, t, m)) ends = [n, m];
    }
  }
  if (ends.len() == 0) { Tools_Status(self, company, "No track piece found on that tile."); return; }
  local seen = {};
  seen.rawset(t, true);
  local fw = Tools_FollowLine(t, ends[1], company, seen);
  local bw = Tools_FollowLine(t, ends[0], company, seen);
  local tiles = [];
  for (local i = bw.tiles.len() - 1; i >= 0; i--) tiles.append(bw.tiles[i]);
  tiles.append(t);
  foreach (x in fw.tiles) tiles.append(x);
  if (tiles.len() < 2) { Tools_Status(self, company, "That track is too short to double."); return; }
  local kinds = [0];
  for (local j = 1; j < tiles.len(); j++)
    kinds.append(GSMap.DistanceManhattan(tiles[j - 1], tiles[j]) > 1 ? (GSBridge.IsBridgeTile(tiles[j]) ? 1 : 2) : 0);
  local n = tiles.len();
  local p1 = { tiles = tiles, kinds = kinds };
  // directions: into the first tile, and back out of the last one
  local da = bw.stop >= 0 ? U_DirOf(bw.stop, tiles[0]) : U_DirOf(tiles[0], tiles[1]);
  local dout = fw.stop >= 0 ? U_DirOf(tiles[n - 1], fw.stop) : U_DirOf(tiles[n - 2], tiles[n - 1]);
  local tr1 = { da = da, db = (dout + 2) % 4 };
  local job = { mode = MODE_RAIL, company = company, names = "double track", live = [], live_at = -15000,
                rail = GSRail.GetRailType(t), me = company };
  GSRail.SetCurrentRailType(job.rail);
  Job_SearchSetup(job);
  job.lane <- [];
  local p2 = null;
  foreach (tw in [1, 3]) {
    job.twin = tw;
    p2 = Tools_Parallel(job, p1, tr1, null);
    if (p2 != null) break;
  }
  if (p2 == null) {
    Tools_Log(self, company, "Double track: no room for a second track along all " + n + " tiles on either side (houses, water, other track, slopes).");
    return;
  }
  local specials = [], pieces = [], actions = [];
  PathRail_Actions(p2, p2.first, p2.last, specials, pieces);
  foreach (a in specials) actions.append(a);
  foreach (a in pieces) actions.append(a);
  local cost = Act_Estimate(job, actions);
  s.conn = { state = "BUILD", job = job, tracks = [], k = 0, paths = [p2], actions = actions, idx = 0, failed = 0,
             ea = tiles[0], eb = tiles[n - 1], tight = true,
             label = "Double track: second track built along " + n + " tiles (about " + cost + ")" };
  if (s.manual) {
    s.conn.state = "CONFIRM";
    Job_LiveClear(job);
    job.live = Preview_Live([], p2.tiles);
    Tools_Status(self, company, "Second track planned along " + n + " tiles, about " + cost + ". Press Build connection.");
    return;
  }
  Tools_Status(self, company, "Building a second track along " + n + " tiles, about " + cost + " ...");
}

/* Distance calculator on the pages? (setting distance_tool) */
function Tools_DistOn()
{
  return GSController.GetSetting("distance_tool") != 0;
}

/* Page items without the distance calculator when it is switched off. */
function Tools_DistFilter(items)
{
  if (Tools_DistOn()) return items;
  local out = [];
  foreach (it in items) {
    if (it[0] == "t_title7" || it[0] == "t_ma" || it[0] == "t_mb" || it[0] == "t_msel") continue;
    out.append(it);
  }
  return out;
}

/* Distance calculator line. */
function Tools_DistText(s)
{
  local a = s.rawin("ma") ? s.ma : -1, b = s.rawin("mb") ? s.mb : -1;
  local text = "A: " + (a >= 0 ? GSMap.GetTileX(a) + "," + GSMap.GetTileY(a) : "-") +
               " | B: " + (b >= 0 ? GSMap.GetTileX(b) + "," + GSMap.GetTileY(b) : "-");
  if (a < 0 || b < 0) return text;
  local dx = GSMap.GetTileX(b) - GSMap.GetTileX(a), dy = GSMap.GetTileY(b) - GSMap.GetTileY(a);
  if (dx < 0) dx = -dx;
  if (dy < 0) dy = -dy;
  // straight line: integer square root (no math library needed)
  local sq = dx * dx + dy * dy, line = 0;
  while ((line + 1) * (line + 1) <= sq) line++;
  if (sq - line * line > line) line++;   // round
  return text + " | Manhattan " + (dx + dy) + " (dx " + dx + ", dy " + dy + ") | straight line " + line;
}
