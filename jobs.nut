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
           depot_tile = -1, veh_text = "", live = [], live_at = -15000 };
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
  job.twin <- -1;
  job.hw <- [8, 7, 6][GSController.GetSetting("route_quality")];
  if (!job.rawin("reuse")) job.reuse <- false;
  job.terra <- GSController.GetSetting("allow_terraform") != 0;
  job.follow <- GSController.GetSetting("follow_lines") != 0;
  if (!job.rawin("boost")) job.boost <- 1;
  Job_ResetCache(job);
}

/* Tile caches of the route search (see path_rail.nut). */
function Job_ResetCache(job)
{
  job.cc <- {};
  job.xc <- {};
  job.bc <- {};
  job.tc <- {};
  job.sc <- {};   // curves on slopes
  job.lc <- {};   // can this tile be levelled
  job.uc <- {};   // may run on this own track tile (My tracks)
  job.rc <- {};   // existing track piece checks (My tracks)
  job.ic <- {};   // is this a rail tile
  // My tracks counters for the debug page: usable tiles seen, moves along the
  // old track, possible switches, refused by a one-way signal / by the test build
  job.rs <- { tiles = 0, along = 0, join = 0, oneway = 0, refused = 0, last = "" };
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
  job.t0 <- GSController.GetTick();   // for the time estimate in the Story Book
  job.exam0 <- Job_Examined(job);     // for the search speed in the status line
  job.goal_dead <- false;             // set by Job_StartSecondTrack
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

/* Tiles examined by all searches of this job so far. */
function Job_Examined(job)
{
  local n = job.rawin("exam_sum") ? job.exam_sum : 0;
  if (job.rawin("astar") && job.astar != null) n += job.astar.examined;
  return n;
}

function Job_NewAStar(job, key)
{
  // keep the count of the search that is replaced (benchmark, debug)
  if (job.rawin("astar") && job.astar != null) job.exam_sum <- Job_Examined(job);
  // a part towards a waypoint gives up sooner, so a bad waypoint costs little
  local limit = (job.wp >= 0 ? max(20000, Job_Limit() / 4) : Job_Limit()) * job.boost;
  // where the estimate points: this part's waypoint, or the goal
  job.htile <- job.wp >= 0 ? job.wp : job.goal_tile;
  if (job.mode == MODE_ROAD)
    job.astar <- AStar(job, [key], PathRoad_Nb, PathRoad_Goal, PathRoad_H, limit);
  else
    job.astar <- AStar(job, [key], PathRail_Nb, PathRail_Goal, PathRail_H, limit);
  // no step closer to the goal for a long time: it is boxed in, stop early
  job.astar.stall = max(30000, limit / 3);
  // the second track runs right beside the first one: when it gets no closer
  // for a while, it is boxed in
  if (job.rawin("near") && job.near.len() > 0) job.astar.stall = min(job.astar.stall, 40000);
  // a few tiles from the goal and no closer for a long time: the way in is
  // shut (the search would otherwise examine the whole area around the goal)
  job.astar.near_h = 3 * Job_HW(job);
  job.astar.near_stall = 20000;
  if (job.rawin("live_at")) job.live_at = -15000;
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
      job.uc.rawset(t, false);
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
  U_Diag("i", job.names + ": waypoint " + (job.wp_i + 1) + "/" + job.wps.len() + " not reachable (" + Job_Why(job) + "), skipping it.");
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
  // My tracks found no way: plan again with all-new track
  if (job.reuse && job.mode != MODE_ROAD) {
    local rs = job.rs;
    UI_Diag(self, job.company, "!", job.names + ": no route along your tracks (" + why + "; own track tiles seen " + rs.tiles +
            ", switches possible " + rs.join + ", refused: one-way signal " + rs.oneway + ", test build " + rs.refused +
            (rs.last != "" ? " - " + rs.last : "") + "). Trying again with all-new track.");
    UI_Status(self, job.company, job.names + ": no route along your tracks, trying again with all-new track ...");
    job.reuse = false;
    job.reuse_failed <- true;
    job.state = "PREP";
    return true;
  }
  // the search ran out of room: try once more with a doubled limit
  if (job.astar.examined > job.astar.limit && !job.astar.stalled && job.boost == 1) {
    job.boost = 2;
    UI_Diag(self, job.company, "!", job.names + ": search limit reached, trying again with twice the limit.");
    UI_Status(self, job.company, job.names + ": route search ran out of room, trying again with a bigger limit ...");
    job.state = "PREP";
    return true;
  }
  if (!job.rawin("retries")) job.retries <- 0;
  if (job.retries >= 2) return false;
  if (job.rawin("chain")) {
    if (job.chain_k > 0) return false;   // stations of the list are built already
    job.chain.plan <- null;              // plan them again, avoiding these places
  }
  local tiles = [], which = "both stations";
  if (job.rawin("spA")) {
    // change only the station where the search got stuck, keep the other one
    local a = job.astar;
    local closest = a.best_h < 0 ? -1 : a.best_h / max(1, Job_HW(job));
    local at_b = why == "station entry blocked" || (job.wp < 0 && closest >= 0 && closest <= 12);
    local at_a = !at_b && job.wp_i == 0 && a.examined > 0 && a.Closeness() < 10;
    if (!at_b) foreach (t in job.spA.tiles) tiles.append(t);
    if (!at_a) foreach (t in job.spB.tiles) tiles.append(t);
    which = at_b ? "the station at " + Tg_Name(job.link.to) : (at_a ? "the station at " + Tg_Name(job.link.from) : "both stations");
  } else if (job.rawin("stations")) {
    foreach (a in job.stations) if (a.op == "truck_stop") { tiles.append(a.s); tiles.append(a.f); }
  }
  if (tiles.len() == 0) return false;   // town to town road: nothing to move
  job.retries++;
  foreach (t in tiles) job.avoid.rawset(t, true);
  UI_Diag(self, job.company, "!", job.names + ": no route (" + why + "), retry " + job.retries + "/2: new place for " + which + ".");
  UI_Status(self, job.company, job.names + ": no route from these station places, trying other places (" + (job.retries + 1) + "/3) ...");
  job.state = "PREP";
  return true;
}

/* Rough time left from the progress so far, in game days (74 ticks each).
 * Only a guess: a detour around a lake or hills makes it jump. */
function Job_Eta(job, pct)
{
  local spent = GSController.GetTick() - job.t0;
  if (pct < 3 || spent < 74) return "estimating time";
  local days = spent * (100 - pct) / pct / 74;
  return "about " + max(1, days) + " game day(s) left";
}

/* Live view on the map: every ~15000 tiles examined the signs move along
 * the path that got closest to the goal (finished parts + current part). */
function Job_LiveView(job)
{
  if (!GSController.GetSetting("search_preview")) return;
  local a = job.astar;
  if (a.examined - job.live_at < 15000) return;
  job.live_at = a.examined;
  local tiles = [];
  foreach (t in job.acc.tiles) tiles.append(t);
  foreach (t in a.PathFrom(a.best_node).tiles) tiles.append(t);
  job.live = Preview_Live(job.live, tiles);
}

function Job_LiveClear(job)
{
  if (!job.rawin("live")) return;
  Preview_Clear(job.live);
  job.live = [];
  job.live_at = -15000;
}

/* Why the current search part failed, in words. */
function Job_Why(job)
{
  local a = job.astar;
  if (job.rawin("goal_dead") && job.goal_dead) return "the way into the station is taken";
  if (a.stalled) return "stuck, no way closer than " + (a.best_h / max(1, Job_HW(job))) + " tiles to the goal";
  if (a.examined > a.limit) return "search limit reached";
  return "no way through";
}

/* Tiles examined per game day (74 ticks) since this search began. */
function Job_Speed(job)
{
  local ticks = max(1, GSController.GetTick() - job.t0);
  return (Job_Examined(job) - job.exam0) * 74 / ticks;
}

function Job_HW(job)
{
  return job.mode == MODE_ROAD ? 3 : job.hw;
}

function Job_Limit()
{
  return GSController.GetSetting("search_limit") * 1000;
}

/* Returns an error text, or null when the search was started. */
function Job_Prep(self, job)
{
  ::g_nocash = 0;
  if (!Tg_Valid(job.a) || !Tg_Valid(job.b)) return "Town or industry no longer exists.";
  local link = job.rawin("forced_link") ? job.forced_link : Tg_Link(job.a, job.b);
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
    // single track: 2 platforms are enough (trains pass each other there);
    // big stations only for double track, where several lines meet
    local plat = GSController.GetSetting("rail_platforms");
    if (job.mode == MODE_DOUBLE) plat = max(2, plat);
    else plat = min(plat, 2);
    local min_plat = job.mode == MODE_DOUBLE ? 2 : 1;
    local nrows = job.mode == MODE_DOUBLE ? 2 : 1;
    local memo = self.bigst.rawin(job.company) ? self.bigst.rawget(job.company) : null;
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
      U_Log("i", "Rail: type " + job.rail + ", station " + len + "x" + plat + ", looking at " + Tg_Name(link.from));
      ::g_report = { self = self, company = job.company, label = "1/3 station place at " + Tg_Name(link.from), base = 0 };
      sa = BuildRail_UseStation(memo, link.from, "from", link.cargo, nrows, job.rail, job.me, job.blocked);
      // with a loop at B the source only needs a small 2-platform station
      local plat_a = (job.mode == MODE_DOUBLE && link.to.kind != "station" && !job.rawin("transfer_to") &&
                      GSController.GetSetting("loop_station") != 0) ? min_plat : plat;
      if (sa == null) sa = BuildRail_FindSpotAny(link.from, "from", link.cargo, c_to, plat_a, min_plat, len, job.blocked, false);
      ::g_report = null;
      if (sa == null) return "No place for a " + len + "x" + plat + " station at " + Tg_Name(link.from) + ".";
      foreach (t in sa.tiles) job.blocked.rawset(t, true);
      if (sa.rawin("dep") && sa.dep >= 0) job.blocked.rawset(sa.dep, true);   // keep the depot place free
      UI_Progress(self, job.company, "1/3 station place at " + Tg_Name(link.to), 50);
      ::g_report = { self = self, company = job.company, label = "1/3 station place at " + Tg_Name(link.to), base = 50 };
      // loop station: a through station at B, the return track starts at its back end
      job.loop <- job.mode == MODE_DOUBLE && link.to.kind != "station" && !job.rawin("transfer_to") &&
                  GSController.GetSetting("loop_station") != 0;
      sb = null;
      // a loop line to this destination exists: the new line becomes a branch of it
      local br = job.loop && !job.rawin("reuse_failed") ? Job_FindLoop(self, job.company, link.to) : null;
      if (br != null) {
        job.branch <- br;
        job.reuse = true;
        sb = Job_LoopSpot(br);
        // the first track may only use the inbound track, the second only the return track
        foreach (t in br.out) job.blocked.rawset(t, true);
      } else if (job.rawin("branch")) delete job.branch;
      if (job.loop && sb == null) {
        // rows on the side where the return track is at the source (mirrored layout if needed)
        ::g_want_rel = -1;
        for (local i = 0; i < 4; i++) if (sa.plat >= 2 && U_Step(sa.G[0], i) == sa.G[1]) ::g_want_rel = (i - sa.d + 4) % 4;
        sb = BuildRail_FindSpotAny(link.to, "to", link.cargo, c_from, plat, min_plat, len, job.blocked, true);
        ::g_want_rel = -1;
        if (sb == null) {
          job.loop = false;
          UI_Diag(self, job.company, "i", "No room for a loop station at " + Tg_Name(link.to) + ", a normal end station is used.");
        }
      }
      if (sb == null) sb = BuildRail_UseStation(memo, link.to, "to", link.cargo, nrows, job.rail, job.me, job.blocked);
      if (sb == null) sb = BuildRail_FindSpotAny(link.to, "to", link.cargo, c_from, link.to.kind == "station" ? min_plat : plat, min_plat, len, job.blocked, false);
      ::g_report = null;
      if (sb == null) return "No place for a " + len + "x" + plat + " station at " + Tg_Name(link.to) + ".";
      foreach (t in sb.tiles) job.blocked.rawset(t, true);
    }
    if (ch == null) {
      // say what was chosen at each end, so the choice is clear in the Log
      foreach (pair in [[sa, link.from], [sb, link.to]]) {
        local sp = pair[0], how;
        if (sp.rawin("branch")) how = "branch onto your loop line to " + sp.station_name + " (joins your inbound track, leaves your return track)";
        else if (sp.rawin("existing")) how = "free platform row " + sp.rows + " of your station " + sp.station_name;
        else if (sp.rawin("join")) how = sp.plat + " new platform(s) beside your station " + GSStation.GetName(sp.join);
        else if (sp.rawin("join_sid")) how = sp.plat + " new platform(s) joined to " + GSStation.GetName(sp.join_sid);
        else how = "new station, " + sp.plat + " platform(s)" + (sp.level ? ", land levelled" : "");
        if (sp == sb && job.rawin("loop") && job.loop) how += ", loop (trains run through and turn back)";
        UI_Diag(self, job.company, "i", "Station at " + Tg_Name(pair[1]) + ": " + how + ".");
      }
    }
    job.spA <- sa;
    job.spB <- sb;
    // which platform row at B the first track ends on, so the two tracks do not cross
    local r1 = 0;
    if (job.mode == MODE_DOUBLE && !(job.rawin("loop") && job.loop)) {
      local same = U_Cross(sa.d, sa.s) == U_Cross((sb.d + 2) % 4, sb.s);
      r1 = same ? 0 : 1;
    }
    job.r1 <- r1;
    // side of the second track as seen from a train on the first one:
    // 1 = right, 3 = left (from the row order at A)
    job.twin <- -1;
    if (job.mode == MODE_DOUBLE && sa.plat >= 2) {
      for (local i = 0; i < 4; i++) if (U_Step(sa.G[0], i) == sa.G[1]) job.twin = (i - sa.d + 4) % 4;
      if (job.twin != 1 && job.twin != 3) job.twin = -1;
    }
    job.approach <- [];
    job.lane <- [];
    // double track: keep the tiles in front of the second track's platform free
    // during the first search, so the first track cannot turn across them and
    // shut the second one out (freed again in Job_StartSecondTrack)
    if (job.mode == MODE_DOUBLE) {
      if (sa.plat >= 2) Job_KeepEntry(job, sa.G[1], sa.d);
      local loop_b = job.rawin("loop") && job.loop && !job.rawin("branch");
      if (last && !loop_b && sb.plat >= 2) Job_KeepEntry(job, sb.G[1 - r1], sb.d);
    }
    if (last) {
      job.goal_tile = sb.G[r1];
      job.goal_dir = (sb.d + 2) % 4;
      job.goal_front <- sb.F[r1];
      if (job.rawin("loop") && job.loop && !job.rawin("branch")) Job_LoopApproach(job, sb);
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

/* Blocks tile t and the 2 tiles straight out from it (direction d) and puts
 * them in job.lane, which is freed when the second track is searched. */
function Job_KeepEntry(job, t, d)
{
  for (local i = 0; i < 3 && t >= 0; i++) {
    if (!job.blocked.rawin(t)) {
      job.blocked.rawset(t, true);
      job.lane.append(t);
    }
    t = U_Step(t, d);
  }
}

/* Loop station: the first track ends with a straight run in front of the
 * station, and the lane beside it (outside row 0) stays free during the first
 * search. The return track comes around the station and lies in that lane,
 * so both tracks leave the station side by side (a tight loop). */
function Job_LoopApproach(job, sb)
{
  local want = max(4, sb.plat + 2), run = [];
  local t = sb.G[0];
  for (local i = 0; i < want; i++) {
    t = U_Step(t, sb.d);
    if (t < 0 || job.blocked.rawin(t) || !GSTile.IsBuildable(t)) break;
    run.append(t);
  }
  if (run.len() < 2) return;
  // the search ends at the far end of the run, the rest is laid straight
  job.goal_tile = run[run.len() - 1];
  for (local i = run.len() - 2; i >= 0; i--) {
    job.approach.append(run[i]);
    job.blocked.rawset(run[i], true);
  }
  job.approach.append(sb.G[0]);
  // side of row 0 away from the other platforms
  if (sb.plat < 2) return;
  local side = -1;
  for (local i = 0; i < 4; i++) if (U_Step(sb.G[1], i) == sb.G[0]) side = i;
  if (side < 0) return;
  local lane = [U_Step(sb.F[0], side), U_Step(sb.G[0], side)];
  foreach (x in run) lane.append(U_Step(x, side));
  // a few tiles past the run too, so the first track cannot turn across the
  // lane there and shut the return track in
  local past = run[run.len() - 1];
  for (local i = 0; i < 3 && past >= 0; i++) {
    past = U_Step(past, sb.d);
    if (past >= 0) lane.append(U_Step(past, side));
  }
  foreach (x in lane) {
    if (x < 0 || job.blocked.rawin(x)) continue;
    job.blocked.rawset(x, true);
    job.lane.append(x);
  }
}

function Job_StartSecondTrack(job)
{
  local sa = job.spA, sb = job.spB;
  job.near <- {};
  Job_ResetCache(job);
  // the lane kept free beside the loop approach is for this track
  if (job.rawin("lane")) foreach (x in job.lane) if (job.blocked.rawin(x)) job.blocked.rawdelete(x);
  // branch: now the return track of the loop line may be used, the inbound one not
  if (job.rawin("branch")) {
    foreach (x in job.branch.out) if (job.blocked.rawin(x)) job.blocked.rawdelete(x);
    foreach (x in job.branch.inn) job.blocked.rawset(x, true);
  }
  foreach (t in job.path1.tiles) {
    job.blocked.rawset(t, true);
    foreach (n in U_Neighbours(t)) job.near.rawset(n, true);
  }
  local loop = job.rawin("loop") && job.loop;
  if (loop) {
    // loop: from the back end of B around the station and back to A
    job.goal_tile = sa.G[1];
    job.goal_dir = (sa.d + 2) % 4;
    Job_BeginSearch(job, K_Make(sb.Gb[0], (sb.d + 2) % 4, 0));
  } else {
    job.goal_tile = sb.G[1 - job.r1];
    job.goal_dir = (sb.d + 2) % 4;
    Job_BeginSearch(job, K_Make(sa.G[1], sa.d, 0));
  }
  // the waypoints of the second track lie on the first track (not on the
  // straight line between the towns), so it follows the first one closely
  local p1 = job.path1.tiles;
  if (job.wps.len() > 0 && p1.len() > 2) {
    local n = job.wps.len() + 1;
    job.wps = [];
    for (local s = 1; s < n; s++) job.wps.append(p1[loop ? p1.len() - 1 - s * p1.len() / n : s * p1.len() / n]);
    job.wp_i = 0;
    job.wp = job.wps[0];
    Job_NewAStar(job, job.seg_start);
  }
  // nothing can reach the end of the second track (the tile in front of it
  // is taken): fail at once instead of searching the whole area around it
  job.goal_dead = !PathRail_GoalReachable(job);
  job.state = "SEARCH2";
}

/* Route found: build the action list, estimate the cost and show the preview. */
function Job_Plan(self, job)
{
  Job_LiveClear(job);
  local acts = [], specials = [], pieces = [], extra = [], levels = [];
  local paths = [job.path1];
  if (job.mode == MODE_ROAD) {
    foreach (a in job.stations) acts.append(a);
    PathRoad_Actions(job.path1, specials, pieces);
    if (GSController.GetSetting("build_depot")) extra.append({ op = "road_depot", center = job.depot_center });
  } else {
    local sa = job.spA, sb = job.spB, dbl = job.mode == MODE_DOUBLE;
    local loop = dbl && job.rawin("loop") && job.loop;
    // second track ends: normally A row 1 <- B row (1 - r1); loop: B back end -> A row 1
    // (single track: a free row of an old station has only one platform, so no F[1])
    local p2a = -1, p2b = -1;
    if (dbl) {
      p2a = loop ? sb.Fb[0] : sa.F[1];
      p2b = loop ? sa.F[1] : sb.F[1 - job.r1];
    }
    // stations: both ends, or for a town list every station at once in leg 0
    local build = [];
    if (job.build_all) foreach (sp in job.chain.plan) build.append(sp);
    else if (!job.rawin("chain")) build = [sa, sb];
    foreach (sp in build) {
      if (sp.rawin("branch")) continue;   // the loop station of the line is built already
      if (sp.rawin("existing")) {
        // a free row of an own station: only the switches and the link to its switch column
        BuildRail_FanActions(sp, dbl, pieces);
        foreach (a in sp.links) pieces.append(a);
        if (sp.rawin("helper")) {
          acts.append({ op = "rail_station_join", tile = sp.helper, station = sp.sid, critical = true });
          UI_Diag(self, job.company, "i", "Ctrl trick: one tile of " + sp.station_name + " is built next to the " +
                  (sp == job.spA ? Tg_Name(job.link.from) : Tg_Name(job.link.to)) + ", joined to the station (distant join).");
        }
        continue;
      }
      if (sp.level) acts.append({ op = "level", a = sp.la, b = sp.lb, critical = true });
      acts.append({ op = "rail_station", tile = sp.anchor, axis = sp.axis, plat = sp.plat, len = sp.len, critical = true,
                    station = sp.rawin("join_sid") ? sp.join_sid : -1 });
      local lp = loop && sp == sb;   // loop station: all platforms from one entry to one exit
      BuildRail_FanActions(sp, dbl && !lp, pieces);
      BuildRail_FanMore(sp, dbl && !lp, pieces);
      if (lp) BuildRail_FanBackMore(sp, pieces);
      local x = BuildRail_JoinCrossover(sp, dbl, pieces);
      if (x > 0) UI_Diag(self, job.company, "i", "Station " + GSStation.GetName(sp.join) + " gets " + sp.plat +
                         " more platform(s), linked " + (x == 2 ? "both ways" : "one way") + " with the old ones: one big station.");
    }
    // landscaping first, then bridges/tunnels, then the track
    local nl = PathRail_LevelActions(job.path1, sa.F[0], job.goal_front, levels);
    if (dbl) nl += PathRail_LevelActions(job.path2, p2a, p2b, levels);
    if (nl > 0) UI_Diag(self, job.company, "i", job.names + ": " + nl + " tile(s) of the route will be levelled (landscaping).");
    foreach (a in levels) acts.append(a);
    PathRail_Actions(job.path1, sa.F[0], job.goal_front, specials, pieces);
    if (dbl) {
      paths.append(job.path2);
      PathRail_Actions(job.path2, p2a, p2b, specials, pieces);
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
      PathRail_Signals(job.path2, sp, loop, extra);
    }
    if (job.reuse) {
      // protect the junctions with the existing tracks
      PathRail_JoinSignals(job.path1, job.me, dbl, true, extra);
      if (dbl) PathRail_JoinSignals(job.path2, job.me, true, loop, extra);
    }
    if (GSController.GetSetting("station_signals")) {
      // station entries: path signals so trains wait for a free platform / free line
      if (dbl) {
        PathRail_StationSignals(sa, 1, extra);        // track 2 arrives at A on row 1
        if (!sb.rawin("branch")) PathRail_StationSignals(sb, job.r1, extra);    // track 1 arrives at B on row r1
        // loop station: an exit signal behind every platform, so each platform
        // is a safe place to stop and one train does not hold up the others
        if (loop && !sb.rawin("branch") && sb.rawin("Pe"))
          for (local r = 0; r < sb.plat; r++) extra.append({ op = "signal", t = sb.Pb[r], f = sb.Fb[r], kind = "oneway" });
      } else if (sa.plat >= 2 || sa.rawin("existing") || sb.rawin("existing")) {
        // only the ends this leg connects (a through station's other end may have no track yet)
        extra.append({ op = "signal", t = sa.G[0], f = sa.F[0], kind = "twoway" });
        if (job.goal_tile == sb.G[0]) extra.append({ op = "signal", t = sb.G[0], f = sb.F[0], kind = "twoway" });
        else extra.append({ op = "signal", t = sb.Gb[0], f = sb.Fb[0], kind = "twoway" });
      }
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
  // track pieces that fail the test run would leave a hole in the line:
  // plan the route once more around them
  if (job.mode != MODE_ROAD && !job.rawin("replanned")) {
    local bad = Job_BadTiles(job, levels);
    if (bad.len() > 0) {
      job.replanned <- true;
      foreach (t in bad) job.avoid.rawset(t, true);
      UI_Diag(self, job.company, "i", job.names + ": " + bad.len() + " track piece(s) failed the test run (first at tile " +
              GSMap.GetTileX(bad[0]) + "," + GSMap.GetTileY(bad[0]) + "), planning the route again around them.");
      job.astar = null;
      job.state = "PREP";
      return;
    }
  }
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
  if (job.rawin("branch")) summary += ", branch onto your loop line to " + Tg_Name(job.link.to);
  else if (job.rawin("loop") && job.loop) summary += ", loop station at " + Tg_Name(job.link.to);
  if (job.rawin("reuse_failed")) summary += " (My tracks found no way, all-new track)";
  if (job.mode != MODE_ROAD && job.reuse) {
    local used = 0, all = 0;
    foreach (p in paths) foreach (t in p.tiles) { all++; if (PathRail_IsExisting(t, job.me)) used++; }
    summary += ", new track only on " + (all - used) + " tile(s), " + used + " on your existing tracks (" + (used * 100 / max(1, all)) + "% saved)";
  }
  job.summary <- summary;
  job.news_tile <- job.mode == MODE_ROAD ? Tg_Center(job.link.from) : job.spA.anchor;
  if (job.rawin("bench")) {
    // benchmark: record and stop, nothing is built
    Bench_Record(self, job, true, tiles + " tiles, " + bridges + " bridge(s), " + tunnels + " tunnel(s), cost about " + job.cost);
    job.astar = null;
    Job_Drop(self, job);
    return;
  }
  // free the search memory, it is not needed any more
  job.astar = null;
  job.blocked = {};
  if (job.rawin("near")) job.near = {};
  Job_ResetCache(job);

  UI_Diag(self, job.company, "i", "Planned " + summary + ".");
  if (job.est_nocash > 0)
    UI_Diag(self, job.company, "!", "NOT ENOUGH MONEY: " + job.names + ": " + job.est_nocash + " piece(s) could not even be priced (" + U_MoneyText(job.company) + "). The real cost is higher, building will pause when the money runs out.");
  if (job.est_fail > 0)
    UI_Diag(self, job.company, "i", job.names + ": " + job.est_fail + " piece(s) failed the test run, they may fail when building.");
  if (job.cost > limit) {
    local why = "costs about " + job.cost + ", you can spend " + limit + " (bank " + bank + ", setting cost_limit_percent)";
    UI_Diag(self, job.company, "!", job.names + ": not built, " + why + ".");
    UI_History(self, job.company, "NO MONEY " + Job_ModeName(job.mode) + " " + job.names + ": " + why + ".");
    UI_Status(self, job.company, "NOT ENOUGH MONEY: " + summary + ". " + why + ". " + U_MoneyText(job.company) + ".");
    try {
      GSNews.Create(GSNews.NT_GENERAL, U_Clip("Build assistant: not enough money for " + job.names + " (costs about " + job.cost + ")."), job.company, GSNews.NR_NONE, 0);
    } catch (e) {}
    Job_StopChain(self, job);
    Job_Drop(self, job);
    return;
  }
  if (GSController.GetSetting("preview_signs")) job.signs = Preview_Place(paths);
  if (GSController.GetSetting("auto_confirm") || job.rawin("auto")) {
    Job_Confirm(self, job);
  } else {
    job.state = "CONFIRM";
    local left = bank - job.cost;
    UI_Ready(self, job.company, "cost about " + job.cost + ", money after about " + left +
      (job.est_nocash > 0 ? " (NOT ENOUGH MONEY!)" : "") + ". Press Build or Cancel.");
    UI_Diag(self, job.company, "i", "Plan ready: " + job.names + ", press Build.");
    try {
      GSNews.Create(GSNews.NT_GENERAL, U_Clip("Build assistant: route " + job.names + " is planned. Press Build in the Story Book."),
                    job.company, GSNews.NR_TILE, job.news_tile);
    } catch (e) {}
    UI_Status(self, job.company, summary + ". Money after building about " + left +
      (job.est_nocash > 0 ? " (NOT ENOUGH MONEY for all pieces!)" : "") + ". Press Build or Cancel.");
  }
}

/* Tiles of track pieces that failed the test run where the failure is real:
 * not on or next to a tile that is levelled first (levelling happens only
 * when building, so the test run still sees the old slope) and not at a
 * station (its tiles do not exist yet in the test run either). */
function Job_BadTiles(job, levels)
{
  local skip = {}, out = [];
  local around = [];
  foreach (a in levels) around.append(a.a);
  foreach (sp in [job.spA, job.spB]) if (sp.rawin("tiles")) foreach (t in sp.tiles) around.append(t);
  foreach (t in around) {
    skip.rawset(t, true);
    for (local i = 0; i < 4; i++) {
      local n = U_Step(t, i);
      if (n >= 0) skip.rawset(n, true);
    }
  }
  foreach (t in job.est_bad) if (!skip.rawin(t)) out.append(t);
  return out;
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
    local sp = BuildRail_FindSpot(e, i == 0 ? "from" : "to", job.cargo, other, min(plat, 2), len, blocked, through, null, false);
    ::g_report = null;
    if (sp == null) return "No place for a " + len + "x" + plat + (through ? " through" : "") + " station at " + Tg_Name(e) + ". The list was not started.";
    foreach (t in sp.tiles) blocked.rawset(t, true);
    if (sp.rawin("dep") && sp.dep >= 0) blocked.rawset(sp.dep, true);
    plan.append(sp);
    U_Log("i", "Town list: station " + (i + 1) + "/" + n + " at " + Tg_Name(e) + (through ? " (through)" : ""));
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
  // single track: with signals at 2-platform stations the stations are passing
  // places and 2 trains fit; otherwise a second train would block the line
  if (!road && job.mode != MODE_DOUBLE) {
    local passing = GSController.GetSetting("station_signals") && job.spA.plat >= 2 && ch == null;
    count = min(count, passing ? 2 : 1);
  }
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
  local a = { op = "vehicles", kind = road ? "road" : "rail", stops = stops, resolve = resolve,
              cargo = job.cargo, full = !job.link.pax, count = count,
              depot = ch != null ? ch.depot : -1, rail = job.rail, plat_len = job.plat_len };
  if (job.rawin("transfer_to")) {
    // feeder: load at the source, at the hub transfer and leave empty
    a.flags <- [job.link.pax ? GSOrder.OF_NONE : GSOrder.OF_FULL_LOAD_ANY, GSOrder.OF_TRANSFER | GSOrder.OF_NO_LOAD];
  }
  return a;
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
  Job_LiveClear(job);
  UI_SetText(self, job.company, "x_job", "Job: none (last: " + job.names + ", ended in state " + job.state + ")");
  Preview_Clear(job.signs);
  UI_Progress(self, job.company, "-", -1);
  if (self.jobs.rawin(job.company)) self.jobs.rawdelete(job.company);
}

function Job_Fail(self, job, text)
{
  if (job.rawin("bench")) Bench_Record(self, job, false, text);
  if (::g_nocash > 0) {
    text = "NOT ENOUGH MONEY (" + U_MoneyText(job.company) + "). " + ::g_nocash +
           " test build(s) failed for lack of money, so this may be the real reason: " + text;
    ::g_nocash = 0;
  }
  Job_StopChain(self, job);
  UI_Status(self, job.company, job.names + ": " + text);
  UI_Diag(self, job.company, "!", "FAILED " + job.names + ": " + text);
  UI_History(self, job.company, "FAILED " + Job_ModeName(job.mode) + " " + job.names + ": " + text);
  Job_Drop(self, job);
}

/* Check after building: every track piece of the plan must really connect
 * its neighbours. A missing one (a hole in the track, a switch that was not
 * built at a station) is built again; what still fails is reported. */
function Job_Verify(self, job)
{
  if (job.mode == MODE_ROAD) return;
  local missing = 0, fixed = 0, where = -1;
  foreach (a in job.actions) {
    if (a.op != "rail") continue;
    if (GSRail.AreTilesConnected(a.p, a.t, a.n)) continue;
    missing++;
    if (Act_Rail(a) && GSRail.AreTilesConnected(a.p, a.t, a.n)) fixed++;
    else if (where < 0) where = a.t;
  }
  if (missing == 0) {
    U_Log("i", job.names + ": check after building: all track pieces connected.");
    return;
  }
  job.failed = max(0, job.failed - fixed);
  if (missing == fixed) {
    UI_Diag(self, job.company, "i", job.names + ": check after building: " + missing + " missing track piece(s) found and built.");
  } else {
    UI_Diag(self, job.company, "!", job.names + ": check after building: " + (missing - fixed) + " track piece(s) still missing (" +
            GSError.GetLastErrorString() + "), first at tile " + GSMap.GetTileX(where) + "," + GSMap.GetTileY(where) +
            ". Trains may not reach every platform there.");
    job.news_tile = where;   // the news message points at the hole
  }
}

/* Loop lines: remembered after building, so a later line to the same
 * destination becomes a branch (joins the inbound track, leaves the return
 * track) instead of building a second station there. */
function Job_FindLoop(self, company, e)
{
  if (!self.loops.rawin(company)) return null;
  foreach (r in self.loops.rawget(company)) {
    if (r.kind != e.kind || r.id != e.id) continue;
    // still there: the station and the track in front of it
    if (!GSRail.IsRailStationTile(r.P[0]) || GSTile.GetOwner(r.P[0]) != company) continue;
    if (!GSRail.IsRailTile(r.G[0]) || !GSRail.IsRailTile(r.Gb[0])) continue;
    return r;
  }
  return null;
}

/* Station spot of a remembered loop line (nothing is built there). */
function Job_LoopSpot(r)
{
  return { branch = true, existing = true, d = r.d, s = r.s, plat = r.plat, len = r.len, anchor = r.anchor,
           P = r.P, F = r.F, G = r.G, Pb = r.Pb, Fb = r.Fb, Gb = r.Gb, tiles = [], level = false,
           station_name = GSStation.GetName(GSStation.GetStationID(r.P[0])) };
}

function Job_RememberLoop(self, job)
{
  if (!job.rawin("path1") || !job.rawin("path2")) return;   // loaded from a save: the paths are gone
  if (!self.loops.rawin(job.company)) self.loops.rawset(job.company, []);
  local list = self.loops.rawget(job.company);
  local r;
  if (job.rawin("branch")) {
    r = job.branch;
  } else {
    local sb = job.spB;
    r = { kind = job.link.to.kind, id = job.link.to.id, d = sb.d, s = sb.s, plat = sb.plat, len = sb.len, anchor = sb.anchor,
          P = clone sb.P, F = clone sb.F, G = clone sb.G, Pb = clone sb.Pb, Fb = clone sb.Fb, Gb = clone sb.Gb, inn = [], out = [] };
    list.append(r);
    while (list.len() > 12) list.remove(0);
  }
  // the new tracks join the line, so later branches can join them too
  foreach (pair in [[r.inn, job.path1.tiles], [r.out, job.path2.tiles]]) {
    local have = {};
    foreach (t in pair[0]) have.rawset(t, true);
    foreach (t in pair[1]) if (!have.rawin(t)) { pair[0].append(t); have.rawset(t, true); }
  }
}

function Job_Finish(self, job)
{
  local text = Job_ModeName(job.mode) + " " + job.names + " built";
  if (job.failed > 0) text += ", " + job.failed + " piece(s) failed (see Log)";
  if (job.rawin("chain")) {
    // remember the stations and depot for the next legs of the town list
    if (job.chain.depot < 0) job.chain.depot = job.depot_tile;
  } else if (job.mode != MODE_ROAD && job.rawin("spA") && job.rawin("spB")) {
    // big stations: later lines may join their free platforms
    if (!self.bigst.rawin(job.company)) self.bigst.rawset(job.company, []);
    local memo = self.bigst.rawget(job.company);
    foreach (sp in [job.spA, job.spB]) {
      if (sp.rawin("existing") || sp.plat < 2) continue;
      if (sp == job.spB && job.rawin("loop") && job.loop) continue;   // every row of a loop station is used
      memo.append(BuildRail_Memo(sp));
    }
    while (memo.len() > 60) memo.remove(0);
    if (job.rawin("loop") && job.loop) Job_RememberLoop(self, job);
  }
  if (job.rawin("transfer_to")) text += ". Transfer: the cargo goes on to " + job.transfer_name + " with your trains from the hub";
  if (job.veh_text != "") text += "." + job.veh_text;
  else if (job.rawin("chain") && job.chain_k + 2 < job.chain.list.len()) text += ". The next leg follows.";
  else text += ". Now buy the vehicles.";
  UI_Status(self, job.company, text);
  UI_History(self, job.company, text);
  UI_Diag(self, job.company, "i", text);
  local where = job.news_tile;
  try {
    GSNews.Create(GSNews.NT_GENERAL, U_Clip(text), job.company, GSNews.NR_TILE, where);
  } catch (e) {
    U_Log("w", "Could not send news: " + e);
  }
  Job_Drop(self, job);
}

/* One unit of work. Must run inside GSCompanyMode(job.company). */
function Job_Step(self, job)
{
  if (job.rt >= 0) GSRoad.SetCurrentRoadType(job.rt);
  if (job.rail >= 0) GSRail.SetCurrentRailType(job.rail);
  job.ticks++;

  if (job.ticks % 10 == 1) UI_DbgJob(self, job);
  if (!job.rawin("last_state") || job.last_state != job.state) {
    UI_DbgJob(self, job);
    UI_DbgSettings(self, job.company);
    U_Log("i", U_Clip("[" + job.company + "] job " + job.names + ": state " + job.state + " (step " + job.ticks + ")"));
    job.last_state <- job.state;
  }

  if (job.state == "PREP") {
    Job_LiveClear(job);   // a retry starts over
    UI_Status(self, job.company, "Looking for station places for " + job.names + " ...");
    local err = Job_Prep(self, job);
    U_Log("i", U_Clip("[" + job.company + "] prep done: " + (err == null ? "ok, searching route" : err)));
    if (err != null) {
      Job_Fail(self, job, err);
      return;
    }
    if (job.mode != MODE_ROAD && !PathRail_GoalReachable(job)) {
      // nothing can reach the station entry: do not search at all
      UI_Diag(self, job.company, "!", job.names + ": the entry of the station at " + Tg_Name(job.link.to) + " is blocked.");
      if (Job_Retry(self, job, "station entry blocked")) return;
      Job_Fail(self, job, "The station entry is blocked and no other station place works. Try other ends.");
      return;
    }
    UI_Diag(self, job.company, "i", "Searching " + job.names + ": " +
            GSMap.DistanceManhattan(K_Tile(job.seg_start), job.goal_tile) + " tiles, " + (job.wps.len() + 1) + " part(s).");
    return;
  }

  if (job.state == "SEARCH" || job.state == "SEARCH2") {
    // small chunks, so the progress in the Story Book moves often
    local r = job.goal_dead ? -1 : job.astar.Step(GSController.GetSetting("search_per_tick"));
    local segs = job.wps.len() + 1;
    if (r == 0) {
      if (true) {
        local a = job.astar;
        local pct = (job.wp_i * 100 + a.Closeness()) / segs;
        UI_Progress(self, job.company, (job.state == "SEARCH2" ? "2/3 second track" : "2/3 route search") +
          ", part " + (job.wp_i + 1) + "/" + segs + " (limit used " + (a.examined * 100 / a.limit) + "%)", pct);
      }
      Job_LiveView(job);
      // about every 6000 tiles examined, whatever the step size
      local every = max(1, 6000 / max(1, GSController.GetSetting("search_per_tick")));
      if (job.ticks % every == 0) {
        local a = job.astar;
        local pct = max(0, min(99, (job.wp_i * 100 + a.Closeness()) / segs));
        UI_Status(self, job.company, "Searching " + job.names + (job.state == "SEARCH2" ? " (second track)" : "") +
          ": " + pct + "%, " + Job_Eta(job, pct) + ", part " + (job.wp_i + 1) + "/" + segs + ", " + a.examined / 1000 +
          "k tiles examined (" + Job_Speed(job) + " per game day), closest " + (a.best_h < 0 ? "?" : (a.best_h / max(1, Job_HW(job))).tostring()) + " tiles from the goal");
      }
      return;
    }
    if (r < 0) {
      if (!job.goal_dead && Job_SegFailed(job)) return;   // waypoint skipped, trying again
      if (job.state == "SEARCH2" && job.rawin("loop") && job.loop) {
        job.loop = false;
        UI_Diag(self, job.company, "i", job.names + ": no room for the loop at " + Tg_Name(job.link.to) + " (" + Job_Why(job) + "), the return track starts at the station front instead.");
        Job_StartSecondTrack(job);
        return;
      }
      local why = Job_Why(job);
      if (Job_Retry(self, job, why)) return;
      Job_Fail(self, job, "No route found (" + why + ", " + job.astar.examined + " tiles examined). Try other ends, allow longer bridges or raise search_limit.");
      return;
    }
    if (!Job_SegDone(job)) return;      // next part of the route
    if (job.state == "SEARCH") {
      job.path1 <- job.acc;
      // loop station: the straight approach in front of it
      if (job.rawin("approach")) foreach (x in job.approach) {
        job.path1.tiles.append(x);
        job.path1.kinds.append(0);
      }
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
          UI_Diag(self, job.company, "!", "NOT ENOUGH MONEY: " + job.names + " paused at " + Act_Describe(a) + " (" + U_MoneyText(job.company) + "). Press Resume when you have money.");
          UI_Status(self, job.company, "NOT ENOUGH MONEY: " + job.names + " paused at step " + job.idx + "/" + job.actions.len() + " (" + U_MoneyText(job.company) + "). Press Resume when you have money.");
          UI_History(self, job.company, "PAUSED, NO MONEY " + Job_ModeName(job.mode) + " " + job.names + " at step " + job.idx + "/" + job.actions.len() + ".");
          try {
            GSNews.Create(GSNews.NT_GENERAL, U_Clip("Build assistant: not enough money for " + job.names + ". Building paused, press Resume in the Story Book."), job.company, GSNews.NR_NONE, 0);
          } catch (e) {}
          return;
        }
        local msg = Act_Describe(a) + " failed: " + GSError.GetLastErrorString();
        // only the first few failures go to the page, all go to the script log
        if (job.failed < 3 || a.rawin("critical")) UI_Diag(self, job.company, "!", job.names + ": " + msg);
        else U_Log("w", U_Clip(job.names + ": " + msg));
        if (a.rawin("critical")) {
          Job_Fail(self, job, "Could not build " + a.op + ": " + GSError.GetLastErrorString());
          return;
        }
        job.failed++;
      }
      job.idx++;
    }
    if (job.idx >= job.actions.len()) {
      Job_Verify(self, job);
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
