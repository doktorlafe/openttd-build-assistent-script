/* Build jobs. One job per company, run in small steps:
 *   PREP     find stations, start the route search
 *   SEARCH   route search (track 1)
 *   SEARCH2  route search for the second track (double rail)
 *   CONFIRM  preview shown, waiting for Confirm / Cancel
 *   BUILD    running the build actions
 *   PAUSED   out of money, waiting for Resume
 * self = the controller (for the Story Book helpers). */

const MODE_ROAD = 0;
const MODE_RAIL = 1;
const MODE_DOUBLE = 2;

function Job_ModeName(mode)
{
  return ["Road", "Rail", "Double rail"][mode];
}

function Job_New(company, mode, a, b)
{
  return { company = company, mode = mode, a = a, b = b, state = "PREP",
           names = Tg_Name(a) + " - " + Tg_Name(b), actions = [], idx = 0, failed = 0,
           signs = [], cost = 0, rt = -1, rail = -1, ticks = 0, cargo = -1, plat_len = 0,
           depot_tile = -1, veh_text = "" };
}

function Job_IsActive(job)
{
  return job.state == "PREP" || job.state == "SEARCH" || job.state == "SEARCH2" || job.state == "BUILD";
}

function Job_SearchSetup(job)
{
  // tiles of station places that already failed stay off limits on a retry
  job.blocked <- {};
  if (!job.rawin("avoid")) job.avoid <- {};
  foreach (t, _ in job.avoid) job.blocked.rawset(t, true);
  job.allow_br <- GSController.GetSetting("allow_bridges") != 0;
  job.allow_tu <- GSController.GetSetting("allow_tunnels") != 0;
  job.max_br <- GSController.GetSetting("max_bridge_length");
  job.max_tu <- GSController.GetSetting("max_tunnel_length");
  job.goal_tile <- -1;
  job.goal_dir <- 4;
  Job_ResetCache(job);
}

/* Tile caches of the route search (see path_rail.nut). */
function Job_ResetCache(job)
{
  job.cc <- {};
  job.xc <- {};
  job.bc <- {};
  job.tc <- {};
}

/* Long routes are searched in parts: waypoints on the straight line from
 * start to goal, one every segment_length tiles. Each part only has to get
 * near its waypoint, so every search stays small and fast. A waypoint that
 * cannot be reached is skipped. */
function Job_BeginSearch(job, start_key)
{
  local start = K_Tile(start_key), goal = job.goal_tile;
  local seg = GSController.GetSetting("segment_length");
  job.wps <- [];
  local d = GSMap.DistanceManhattan(start, goal);
  if (seg > 0 && d > seg * 3 / 2) {
    local n = d / seg;
    local sx = GSMap.GetTileX(start), sy = GSMap.GetTileY(start);
    local gx = GSMap.GetTileX(goal), gy = GSMap.GetTileY(goal);
    for (local s = 1; s < n; s++) {
      local wp = GSMap.GetTileIndex(sx + (gx - sx) * s / n, sy + (gy - sy) * s / n);
      job.wps.append(Job_GoodWaypoint(job, wp, seg / 3));
    }
  }
  job.wp_i <- 0;
  job.wp <- job.wps.len() > 0 ? job.wps[0] : -1;
  job.wp_tol <- max(3, seg / 6);
  job.acc <- { tiles = [], kinds = [] };
  job.seg_start <- start_key;
  Job_NewAStar(job, start_key);
}

/* Moves a waypoint that lies in water or a town to the nearest free land. */
function Job_GoodWaypoint(job, wp, radius)
{
  if (GSTile.IsBuildable(wp) && !job.blocked.rawin(wp)) return wp;
  local tiles = U_TilesAround(wp, radius);
  for (local t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
    if (GSTile.IsBuildable(t) && !job.blocked.rawin(t)) return t;
  }
  return wp;
}

function Job_NewAStar(job, key)
{
  // a part towards a waypoint gives up sooner, so a bad waypoint costs little
  local limit = job.wp >= 0 ? max(20000, Job_Limit() / 4) : Job_Limit();
  if (job.mode == MODE_ROAD)
    job.astar <- AStar(job, [key], PathRoad_Nb, PathRoad_Goal, PathRoad_H, limit);
  else
    job.astar <- AStar(job, [key], PathRail_Nb, PathRail_Goal, PathRail_H, limit);
}

/* A part was found. Returns true when the whole route is done. */
function Job_SegDone(job)
{
  local p = job.astar.Path();
  local first = job.acc.tiles.len() > 0 ? 1 : 0;   // the first tile repeats the last one
  for (local i = first; i < p.tiles.len(); i++) {
    job.acc.tiles.append(p.tiles[i]);
    job.acc.kinds.append(p.kinds[i]);
  }
  if (job.wp < 0) return true;
  if (job.mode != MODE_ROAD) {
    // a railway must not cross itself: later parts may not use these tiles
    foreach (t in p.tiles) {
      job.blocked.rawset(t, true);
      job.cc.rawset(t, -1);
      job.xc.rawset(t * 2, false);
      job.xc.rawset(t * 2 + 1, false);
    }
  }
  job.seg_start = job.astar.found;
  job.wp_i++;
  job.wp = job.wp_i < job.wps.len() ? job.wps[job.wp_i] : -1;
  Job_NewAStar(job, job.seg_start);
  return false;
}

/* A part failed. Skips its waypoint and returns true, or false if it was the last part. */
function Job_SegFailed(job)
{
  if (job.wp < 0) return false;
  GSLog.Info("Route: waypoint " + (job.wp_i + 1) + " not reachable, skipping it");
  job.wp_i++;
  job.wp = job.wp_i < job.wps.len() ? job.wps[job.wp_i] : -1;
  Job_NewAStar(job, job.seg_start);
  return true;
}

/* No route: often a station place is boxed in by older tracks or roads.
 * Mark the station places as off limits and plan again, up to 2 times.
 * Returns true when a retry was started. */
function Job_Retry(self, job, why)
{
  if (!job.rawin("retries")) job.retries <- 0;
  if (job.retries >= 2) return false;
  if (job.rawin("chain")) {
    if (job.chain_k > 0) return false;   // stations of the list are built already
    job.chain.plan <- null;              // plan them again, avoiding these places
  }
  local tiles = [];
  if (job.rawin("spA")) {
    foreach (t in job.spA.tiles) tiles.append(t);
    foreach (t in job.spB.tiles) tiles.append(t);
  } else if (job.rawin("stations")) {
    foreach (a in job.stations) if (a.op == "truck_stop") { tiles.append(a.s); tiles.append(a.f); }
  }
  if (tiles.len() == 0) return false;   // town to town road: nothing to move
  job.retries++;
  foreach (t in tiles) job.avoid.rawset(t, true);
  GSLog.Info(U_Clip(job.names + ": no route (" + why + "), retry " + job.retries + " with other station places"));
  UI_Status(self, job.company, job.names + ": no route from these station places, trying other places (" + (job.retries + 1) + "/3) ...");
  job.state = "PREP";
  return true;
}

function Job_Limit()
{
  return GSController.GetSetting("search_limit") * 1000;
}

/* Returns an error text, or null when the search was started. */
function Job_Prep(self, job)
{
  if (!Tg_Valid(job.a) || !Tg_Valid(job.b)) return "Town or industry no longer exists.";
  local link = Tg_Link(job.a, job.b);
  if (link == null) return "Nothing to carry between " + job.names + ": pick an industry that produces a cargo the other end accepts.";
  job.link <- link;
  job.cargo_name <- GSCargo.GetCargoLabel(link.cargo);
  job.cargo = link.cargo;
  Job_SearchSetup(job);
  local c_from = Tg_Center(link.from), c_to = Tg_Center(link.to);

  if (job.mode == MODE_ROAD) {
    job.rt = BuildRoad_SelectType();
    if (job.rt < 0) return "No road type available yet.";
    job.stations <- [];
    local start, goal;
    if (link.pax) {
      start = c_from;
      goal = c_to;
      if (GSController.GetSetting("build_stops")) {
        job.stations.append({ op = "bus_stop", town = link.from.id });
        job.stations.append({ op = "bus_stop", town = link.to.id });
      }
      job.depot_center <- c_from;
    } else {
      UI_Progress(self, job.company, "1/3 truck stop at " + Tg_Name(link.from), 0);
      ::g_report = { self = self, company = job.company, label = "1/3 truck stop at " + Tg_Name(link.from), base = 0 };
      local sf = BuildRoad_FindTruckSpot(link.from, "from", link.cargo, c_to, job.blocked);
      ::g_report = null;
      if (sf == null) return "No place for a truck stop at " + Tg_Name(link.from) + ".";
      job.blocked.rawset(sf.s, true);
      if (sf.e >= 0) job.blocked.rawset(sf.e, true);
      UI_Progress(self, job.company, "1/3 truck stop at " + Tg_Name(link.to), 50);
      ::g_report = { self = self, company = job.company, label = "1/3 truck stop at " + Tg_Name(link.to), base = 50 };
      local st = BuildRoad_FindTruckSpot(link.to, "to", link.cargo, c_from, job.blocked);
      ::g_report = null;
      if (st == null) return "No place for a truck stop at " + Tg_Name(link.to) + ".";
      job.blocked.rawset(st.s, true);
      if (st.e >= 0) job.blocked.rawset(st.e, true);
      job.stations.append({ op = "truck_stop", s = sf.s, f = sf.f, e = sf.e, critical = true });
      job.stations.append({ op = "truck_stop", s = st.s, f = st.f, e = st.e, critical = true });
      start = sf.f;
      goal = st.f;
      job.depot_center <- sf.f;
    }
    if (start == goal) return "Both ends are on the same tile.";
    job.goal_tile = goal;
    Job_BeginSearch(job, K_Make(start, 4, 0));
  } else {
    job.rail = BuildRail_SelectType();
    job.me <- GSCompany.ResolveCompanyID(GSCompany.COMPANY_SELF);
    if (job.rail < 0) return "No rail type available yet.";
    local plat = job.mode == MODE_DOUBLE ? 2 : GSController.GetSetting("rail_platforms");
    local len = GSController.GetSetting("rail_station_length");
    job.plat_len = len;
    // town list (chain): all stations are planned first (see Job_PlanChainStations),
    // then each leg only lays the track between two of them
    local ch = job.rawin("chain") ? job.chain : null;
    local k = ch != null ? job.chain_k : 0;
    local last = ch == null || k + 2 >= ch.list.len();
    local sa, sb;
    if (ch != null) {
      if (!ch.rawin("plan") || ch.plan == null) {
        local err = Job_PlanChainStations(self, job, ch, plat, len);
        if (err != null) return err;
      }
      sa = ch.plan[k];
      sb = ch.plan[k + 1];
      job.build_a <- false;   // leg 0 builds every station of the list
      job.build_all <- k == 0;
      foreach (sp in ch.plan) {
        foreach (t in sp.tiles) job.blocked.rawset(t, true);
        if (sp.rawin("dep") && sp.dep >= 0) job.blocked.rawset(sp.dep, true);
      }
    } else {
      job.build_a <- true;
      job.build_all <- false;
      UI_Progress(self, job.company, "1/3 station place at " + Tg_Name(link.from), 0);
      GSLog.Info("Rail: type " + job.rail + ", station " + len + "x" + plat + ", looking at " + Tg_Name(link.from));
      ::g_report = { self = self, company = job.company, label = "1/3 station place at " + Tg_Name(link.from), base = 0 };
      sa = BuildRail_FindSpot(link.from, "from", link.cargo, c_to, plat, len, job.blocked, false);
      ::g_report = null;
      if (sa == null) return "No place for a " + len + "x" + plat + " station at " + Tg_Name(link.from) + ".";
      foreach (t in sa.tiles) job.blocked.rawset(t, true);
      if (sa.rawin("dep") && sa.dep >= 0) job.blocked.rawset(sa.dep, true);   // keep the depot place free
      UI_Progress(self, job.company, "1/3 station place at " + Tg_Name(link.to), 50);
      ::g_report = { self = self, company = job.company, label = "1/3 station place at " + Tg_Name(link.to), base = 50 };
      sb = BuildRail_FindSpot(link.to, "to", link.cargo, c_from, plat, len, job.blocked, false);
      ::g_report = null;
      if (sb == null) return "No place for a " + len + "x" + plat + " station at " + Tg_Name(link.to) + ".";
      foreach (t in sb.tiles) job.blocked.rawset(t, true);
    }
    job.spA <- sa;
    job.spB <- sb;
    // which platform row at B the first track ends on, so the two tracks do not cross
    local r1 = 0;
    if (job.mode == MODE_DOUBLE) {
      local same = U_Cross(sa.d, sa.s) == U_Cross((sb.d + 2) % 4, sb.s);
      r1 = same ? 0 : 1;
    }
    job.r1 <- r1;
    if (last) {
      job.goal_tile = sb.G[r1];
      job.goal_dir = (sb.d + 2) % 4;
      job.goal_front <- sb.F[r1];
    } else {
      // enter the through station at its back end, moving towards its front
      job.goal_tile = sb.Gb[0];
      job.goal_dir = sb.d;
      job.goal_front <- sb.Fb[0];
    }
    Job_BeginSearch(job, K_Make(sa.G[0], sa.d, 0));
  }
  job.state = "SEARCH";
  return null;
}

function Job_StartSecondTrack(job)
{
  local sa = job.spA, sb = job.spB;
  job.near <- {};
  Job_ResetCache(job);
  foreach (t in job.path1.tiles) {
    job.blocked.rawset(t, true);
    foreach (n in U_Neighbours(t)) job.near.rawset(n, true);
  }
  job.goal_tile = sb.G[1 - job.r1];
  job.goal_dir = (sb.d + 2) % 4;
  Job_BeginSearch(job, K_Make(sa.G[1], sa.d, 0));
  job.state = "SEARCH2";
}

/* Route found: build the action list, estimate the cost and show the preview. */
function Job_Plan(self, job)
{
  local acts = [], specials = [], pieces = [], extra = [];
  local paths = [job.path1];
  if (job.mode == MODE_ROAD) {
    foreach (a in job.stations) acts.append(a);
    PathRoad_Actions(job.path1, specials, pieces);
    if (GSController.GetSetting("build_depot")) extra.append({ op = "road_depot", center = job.depot_center });
  } else {
    local sa = job.spA, sb = job.spB, dbl = job.mode == MODE_DOUBLE;
    // stations: both ends, or for a town list every station at once in leg 0
    local build = [];
    if (job.build_all) foreach (sp in job.chain.plan) build.append(sp);
    else if (!job.rawin("chain")) build = [sa, sb];
    foreach (sp in build) {
      if (sp.level) acts.append({ op = "level", a = sp.la, b = sp.lb, critical = true });
      acts.append({ op = "rail_station", tile = sp.anchor, axis = sp.axis, plat = sp.plat, len = sp.len, critical = true });
      BuildRail_FanActions(sp, dbl, pieces);
    }
    PathRail_Actions(job.path1, sa.F[0], job.goal_front, specials, pieces);
    if (dbl) {
      paths.append(job.path2);
      PathRail_Actions(job.path2, sa.F[1], sb.F[1 - job.r1], specials, pieces);
    }
    if (GSController.GetSetting("build_depot")) {
      local t = job.path1.tiles, slice = [];
      for (local j = 1; j < t.len() - 1 && j < 30; j++) slice.append(t[j]);
      if ((job.build_a || job.build_all) && sa.rawin("dep"))
        extra.append({ op = "rail_depot_end", tile = sa.dep, front = sa.dep_front, tiles = slice });
      else if (job.build_a || job.build_all)
        extra.append({ op = "rail_depot", tiles = slice });
    }
    if (dbl) {
      local sp = GSController.GetSetting("signal_spacing");
      PathRail_Signals(job.path1, sp, true, extra);
      PathRail_Signals(job.path2, sp, false, extra);
    }
  }
  foreach (a in specials) acts.append(a);
  foreach (a in pieces) acts.append(a);
  foreach (a in extra) acts.append(a);
  local veh = Job_VehicleAction(job);
  if (veh != null) acts.append(veh);
  job.actions = acts;
  job.idx = 0;

  job.cost = Act_Estimate(job, acts);
  local bank = GSCompany.GetBankBalance(job.company);
  local limit = bank / 100 * GSController.GetSetting("cost_limit_percent");
  local bridges = 0, tunnels = 0, tiles = 0;
  foreach (p in paths) {
    bridges += Preview_Count(p, 1);
    tunnels += Preview_Count(p, 2);
    tiles += p.tiles.len();
  }
  local summary = Job_ModeName(job.mode) + " " + job.names + " (" + job.cargo_name + "): " + tiles + " tiles, " +
    bridges + " bridge(s), " + tunnels + " tunnel(s), cost about " + job.cost;
  job.summary <- summary;
  job.news_tile <- job.mode == MODE_ROAD ? Tg_Center(job.link.from) : job.spA.anchor;
  // free the search memory, it is not needed any more
  job.astar = null;
  job.blocked = {};
  if (job.rawin("near")) job.near = {};
  Job_ResetCache(job);

  if (job.cost > limit) {
    UI_Status(self, job.company, summary + ". Too expensive: you can spend " + limit + " (bank " + bank + ").");
    Job_StopChain(self, job);
    Job_Drop(self, job);
    return;
  }
  if (GSController.GetSetting("preview_signs")) job.signs = Preview_Place(paths);
  if (GSController.GetSetting("auto_confirm") || job.rawin("auto")) {
    Job_Confirm(self, job);
  } else {
    job.state = "CONFIRM";
    UI_Progress(self, job.company, "route ready, waiting for Confirm build", 100);
    UI_Status(self, job.company, summary + ". Press Confirm build or Cancel.");
  }
}

/* Town list: finds a station place in every town before any track is laid.
 * The first and last are terminus stations facing their neighbour, the ones in
 * between are through stations facing the next town. Each place is kept free
 * for the others. Returns an error text or null. */
function Job_PlanChainStations(self, job, ch, plat, len)
{
  local n = ch.list.len();
  local blocked = {};
  foreach (t, _ in job.avoid) blocked.rawset(t, true);
  local plan = [];
  for (local i = 0; i < n; i++) {
    local e = ch.list[i];
    if (!Tg_Valid(e)) return "A town of the list no longer exists.";
    local other = (i == n - 1) ? Tg_Center(ch.list[i - 1]) : Tg_Center(ch.list[i + 1]);
    local through = i > 0 && i < n - 1;
    local label = "1/3 stations " + (i + 1) + "/" + n + ": " + Tg_Name(e);
    UI_Progress(self, job.company, label, i * 100 / n);
    ::g_report = { self = self, company = job.company, label = label, base = i * 100 / n };
    local sp = BuildRail_FindSpot(e, i == 0 ? "from" : "to", job.cargo, other, plat, len, blocked, through);
    ::g_report = null;
    if (sp == null) return "No place for a " + len + "x" + plat + (through ? " through" : "") + " station at " + Tg_Name(e) + ". The list was not started.";
    foreach (t in sp.tiles) blocked.rawset(t, true);
    if (sp.rawin("dep") && sp.dep >= 0) blocked.rawset(sp.dep, true);
    plan.append(sp);
    GSLog.Info("Town list: station " + (i + 1) + "/" + n + " at " + Tg_Name(e) + (through ? " (through)" : ""));
  }
  ch.plan = plan;
  return null;
}

/* The "buy vehicles" action for the end of a job, or null.
 * Single route: shuttle between the two stations. Town list: only the last
 * leg buys, one line through all towns there and back (A B C ... Z ... B). */
function Job_VehicleAction(job)
{
  local ch = job.rawin("chain") ? job.chain : null;
  if (ch != null && job.chain_k + 2 < ch.list.len()) return null;   // not the last leg
  local road = job.mode == MODE_ROAD;
  local count = GSController.GetSetting(road ? "veh_road" : "veh_rail");
  if (count <= 0) return null;
  // a single track has no signals: two trains on it would crash into each other
  if (!road && job.mode != MODE_DOUBLE) count = 1;
  local points = [], resolve = false;
  if (road) {
    if (job.link.pax) {
      resolve = true;   // bus stops are found when the vehicles are bought
      if (ch != null) foreach (t in ch.list) points.append(Tg_Center(t));
      else points = [Tg_Center(job.link.from), Tg_Center(job.link.to)];
    } else {
      points = [job.stations[0].s, job.stations[1].s];
    }
  } else {
    if (ch != null) {
      foreach (sp in ch.plan) points.append(sp.anchor);
    } else {
      points = [job.spA.anchor, job.spB.anchor];
    }
  }
  // there and back again through the stops in between
  local stops = [];
  foreach (p in points) stops.append(p);
  for (local i = points.len() - 2; i >= 1; i--) stops.append(points[i]);
  return { op = "vehicles", kind = road ? "road" : "rail", stops = stops, resolve = resolve,
           cargo = job.cargo, full = !job.link.pax, count = count,
           depot = ch != null ? ch.depot : -1, rail = job.rail, plat_len = job.plat_len };
}

function Job_Confirm(self, job)
{
  Preview_Clear(job.signs);
  job.signs = [];
  job.state = "BUILD";
  UI_Status(self, job.company, "Building " + job.names + " ...");
}

/* A leg of a town line failed: the rest would not connect to it, so stop the list. */
function Job_StopChain(self, job)
{
  if (!job.rawin("chain")) return;
  local left = self.queue.rawin(job.company) ? self.queue.rawget(job.company).len() : 0;
  self.queue.rawset(job.company, []);
  if (left > 0) UI_History(self, job.company, "Town list stopped at " + job.names + ", " + left + " leg(s) not built. Fix the problem and add the rest as a new list starting with this town.");
}

function Job_Drop(self, job)
{
  Preview_Clear(job.signs);
  UI_Progress(self, job.company, "-", -1);
  if (self.jobs.rawin(job.company)) self.jobs.rawdelete(job.company);
}

function Job_Fail(self, job, text)
{
  Job_StopChain(self, job);
  UI_Status(self, job.company, job.names + ": " + text);
  UI_History(self, job.company, "FAILED " + Job_ModeName(job.mode) + " " + job.names + ": " + text);
  Job_Drop(self, job);
}

function Job_Finish(self, job)
{
  local text = Job_ModeName(job.mode) + " " + job.names + " built";
  if (job.failed > 0) text += ", " + job.failed + " piece(s) failed (see the script debug log)";
  if (job.rawin("chain")) {
    // remember the stations and depot for the next legs of the town list
    if (job.chain.depot < 0) job.chain.depot = job.depot_tile;
  }
  if (job.veh_text != "") text += "." + job.veh_text;
  else if (job.rawin("chain") && job.chain_k + 2 < job.chain.list.len()) text += ". The next leg follows.";
  else text += ". Now buy the vehicles.";
  UI_Status(self, job.company, text);
  UI_History(self, job.company, text);
  if (job.mode != MODE_ROAD && job.rail >= 0 && job.cargo >= 0) UI_Advice(self, job.company, job.cargo, job.rail, job.plat_len);
  local where = job.news_tile;
  try {
    GSNews.Create(GSNews.NT_GENERAL, U_Clip(text), job.company, GSNews.NR_TILE, where);
  } catch (e) {
    GSLog.Warning("Could not send news: " + e);
  }
  Job_Drop(self, job);
}

/* One unit of work. Must run inside GSCompanyMode(job.company). */
function Job_Step(self, job)
{
  if (job.rt >= 0) GSRoad.SetCurrentRoadType(job.rt);
  if (job.rail >= 0) GSRail.SetCurrentRailType(job.rail);
  job.ticks++;

  if (!job.rawin("last_state") || job.last_state != job.state) {
    GSLog.Info(U_Clip("[" + job.company + "] job " + job.names + ": state " + job.state + " (step " + job.ticks + ")"));
    job.last_state <- job.state;
  }

  if (job.state == "PREP") {
    UI_Status(self, job.company, "Looking for station places for " + job.names + " ...");
    local err = Job_Prep(self, job);
    GSLog.Info(U_Clip("[" + job.company + "] prep done: " + (err == null ? "ok, searching route" : err)));
    if (err != null) Job_Fail(self, job, err);
    return;
  }

  if (job.state == "SEARCH" || job.state == "SEARCH2") {
    // small chunks, so the progress in the Story Book moves often
    local r = job.astar.Step(min(300, GSController.GetSetting("search_per_tick")));
    local segs = job.wps.len() + 1;
    if (r == 0) {
      if (true) {
        local a = job.astar;
        local pct = (job.wp_i * 100 + a.Closeness()) / segs;
        UI_Progress(self, job.company, (job.state == "SEARCH2" ? "2/3 second track" : "2/3 route search") +
          ", part " + (job.wp_i + 1) + "/" + segs + " (limit used " + (a.examined * 100 / a.limit) + "%)", pct);
      }
      if (job.ticks % 20 == 1)
        UI_Status(self, job.company, "Searching route " + job.names + (job.state == "SEARCH2" ? " (second track)" : "") +
          ", part " + (job.wp_i + 1) + " of " + segs + " ...");
      return;
    }
    if (r < 0) {
      if (Job_SegFailed(job)) return;   // waypoint skipped, trying again
      local why = job.astar.examined > job.astar.limit ? "search limit reached" : "no way through";
      if (Job_Retry(self, job, why)) return;
      Job_Fail(self, job, "No route found (" + why + "). Try other ends, allow longer bridges or raise the search limit.");
      return;
    }
    if (!Job_SegDone(job)) return;      // next part of the route
    if (job.state == "SEARCH") {
      job.path1 <- job.acc;
      if (job.mode == MODE_DOUBLE) {
        Job_StartSecondTrack(job);
        return;
      }
    } else {
      job.path2 <- job.acc;
    }
    Job_Plan(self, job);
    return;
  }

  if (job.state == "BUILD") {
    local n = GSController.GetSetting("build_per_tick");
    for (local i = 0; i < n && job.idx < job.actions.len(); i++) {
      local a = job.actions[job.idx];
      if (!Act_Run(job, a)) {
        local err = GSError.GetLastError();
        if (err == GSError.ERR_NOT_ENOUGH_CASH) {
          job.state = "PAUSED";
          UI_Progress(self, job.company, "paused, out of money", job.idx * 100 / job.actions.len());
          UI_Status(self, job.company, job.names + ": out of money at step " + job.idx + "/" + job.actions.len() + ". Press Resume when you have money.");
          return;
        }
        GSLog.Warning(U_Clip(job.names + ": " + Act_Describe(a) + " failed: " + GSError.GetLastErrorString()));
        if (a.rawin("critical")) {
          Job_Fail(self, job, "Could not build " + a.op + ": " + GSError.GetLastErrorString());
          return;
        }
        job.failed++;
      }
      job.idx++;
    }
    if (job.idx >= job.actions.len()) {
      Job_Finish(self, job);
    } else if (job.ticks % 2 == 0) {
      UI_Progress(self, job.company, "3/3 building", job.idx * 100 / job.actions.len());
    }
    if (job.state == "BUILD" && job.idx < job.actions.len() && job.ticks % 5 == 0) {
      UI_Status(self, job.company, "Building " + job.names + ": " + job.idx + "/" + job.actions.len() + " ...");
    }
  }
}

/* Only these fields survive a save; searches are not saved. */
function Job_SaveData(job)
{
  if (job.state != "CONFIRM" && job.state != "BUILD" && job.state != "PAUSED") return null;
  local d = { company = job.company, mode = job.mode, a = job.a, b = job.b, state = job.state,
              names = job.names, actions = job.actions, idx = job.idx, failed = job.failed,
              signs = job.signs, cost = job.cost, rt = job.rt, rail = job.rail, cargo = job.cargo, plat_len = job.plat_len,
              depot_tile = job.depot_tile, veh_text = job.veh_text,
              summary = job.rawin("summary") ? job.summary : "" };
  d.news_tile <- job.news_tile;
  return d;
}

function Job_LoadData(d)
{
  local job = Job_New(d.company, d.mode, d.a, d.b);
  foreach (k in ["state", "names", "actions", "idx", "failed", "signs", "cost", "rt", "rail", "cargo", "plat_len", "depot_tile", "veh_text"]) if (d.rawin(k)) job.rawset(k, d.rawget(k));
  job.summary <- d.summary;
  job.news_tile <- d.news_tile;
  return job;
}
