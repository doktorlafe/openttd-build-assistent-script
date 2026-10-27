/* Story Book: one page per company with the controls, status and history.
 * self = the controller: self.pages[company] = { page, el = { name -> element id }, ver } */

/* Bump when the page layout changes: older pages are then built again. */
const UI_VERSION = 16;

/* Lines kept in the "Log" part of the page. */
const UI_LOG_LINES = 6;

/* Lines of the technical log on the debug page. */
const UI_DBG_LINES = 20;

/* Help page: what every button does (the Story Book has no tooltips). */
function UI_HelpLines()
{
  return [
    "What the buttons do (the Story Book has no tooltips, so they are explained here).",
    "A / B: click on the map. Within 4 tiles of an industry = that industry, otherwise the nearest town. These are the two ends.",
    "Plan: finds station places and the route, shows it with signs and the price. Nothing is built yet.",
    "Build: builds the planned route and buys vehicles (see the script settings). Shown as READY TO BUILD when the plan is done.",
    "Cancel: stops planning or building (built parts stay). With nothing running it clears A, B and the list.",
    "Resume: continues a build that stopped because the money ran out.",
    "Road / Rail / Double: what to build. Double = two tracks side by side with signals, several trains.",
    "My tracks: on = the new railway may run on your existing tracks and join them with switches. Off = always all new.",
    "Transfer: on = if one of your trains already carries the cargo of A to B, only a short feeder to its nearest station is built; the cargo is dropped there and goes on with that train. Also lets you reach a B beyond the distance limit.",
    "+ List: adds one town (or industry) to a list of up to 10. A list wins over A/B and is built as one line A > B > C ...",
    "List from signs: place signs on towns with the sign tool (click, Enter, click ...), then press this. The signs become the list in that order and are removed.",
    "Clear: empties the list.",
    "Bus loop in a town: click a town, it gets bus stops close together, a depot and a bus.",
    "Log: reasons of problems, [!] = problem (no money, no station place, no route ...). Debug page: technical details."
  ];
}

/* Elements of the debug page (a second page of the Story Book). */
function UI_DebugItems()
{
  local items = [
    ["x_info", GSStoryPage.SPET_TEXT, 0, "Technical log of the build assistant for your company, newest first. The same lines are in the AI/Game Script Debug window."],
    ["x_set", GSStoryPage.SPET_TEXT, 0, "Settings: -"],
    ["x_job", GSStoryPage.SPET_TEXT, 0, "Job: none"],
    ["x_title", GSStoryPage.SPET_TEXT, 0, "--- Technical log ---"]
  ];
  for (local i = 0; i < UI_DBG_LINES; i++) items.append(["x" + i, GSStoryPage.SPET_TEXT, 0, "-"]);
  return items;
}

function UI_Items()
{
  local push = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_NONE);
  local go = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_NONE);
  local stop = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, GSStoryPage.SPBF_NONE);
  local pick = GSStoryPage.MakeTileButtonReference(GSStoryPage.SPBC_YELLOW, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE);
  local pick2 = GSStoryPage.MakeTileButtonReference(GSStoryPage.SPBC_ORANGE, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE);
  // the buttons used all the time come first, one right after another:
  // A, B, Plan, Build, Cancel; the selection and state lines follow
  local items = [
    ["pick_a", GSStoryPage.SPET_BUTTON_TILE, pick, "A"],
    ["pick_b", GSStoryPage.SPET_BUTTON_TILE, pick, "B"],
    ["plan", GSStoryPage.SPET_BUTTON_PUSH, go, "Plan"],
    ["confirm", GSStoryPage.SPET_BUTTON_PUSH, go, "Build"],
    ["cancel", GSStoryPage.SPET_BUTTON_PUSH, stop, "Cancel"],
    ["sel", GSStoryPage.SPET_TEXT, 0, "Selection: -"],
    ["progress", GSStoryPage.SPET_TEXT, 0, "Progress: -"],
    ["status", GSStoryPage.SPET_TEXT, 0, "Status: ready."],
    ["resume", GSStoryPage.SPET_BUTTON_PUSH, push, "Resume"],
    ["mode_road", GSStoryPage.SPET_BUTTON_PUSH, push, "Road"],
    ["mode_rail", GSStoryPage.SPET_BUTTON_PUSH, push, "Rail"],
    ["mode_double", GSStoryPage.SPET_BUTTON_PUSH, push, "Double"],
    ["reuse", GSStoryPage.SPET_BUTTON_PUSH, push, "My tracks: use / don't use"],
    ["transfer", GSStoryPage.SPET_BUTTON_PUSH, push, "Transfer: use / don't use"],
    ["list_add", GSStoryPage.SPET_BUTTON_TILE, pick2, "+ List"],
    ["list_signs", GSStoryPage.SPET_BUTTON_PUSH, push, "List from signs"],
    ["list_clear", GSStoryPage.SPET_BUTTON_PUSH, stop, "Clear"],
    ["ship_plan", GSStoryPage.SPET_BUTTON_PUSH, push, "Ship: plan (A = oil rig, B = refinery)"],
    ["ship_build", GSStoryPage.SPET_BUTTON_PUSH, go, "Ship: build"],
    ["log_title", GSStoryPage.SPET_TEXT, 0, "--- Log (newest first) ---"]
  ];
  for (local i = 0; i < UI_LOG_LINES; i++) items.append(["d" + i, GSStoryPage.SPET_TEXT, 0, "-"]);
  items.append(["loop_pick", GSStoryPage.SPET_BUTTON_TILE, pick2, "Bus loop in a town"]);
  items.append(["loop_result", GSStoryPage.SPET_TEXT, 0, "-"]);
  items.append(["hist_title", GSStoryPage.SPET_TEXT, 0, "--- Last builds ---"]);
  for (local i = 0; i < 5; i++) items.append(["h" + i, GSStoryPage.SPET_TEXT, 0, "-"]);
  items.append(["intro", GSStoryPage.SPET_TEXT, 0,
    "Help: A and B > Plan > Build. What every button does: page Build assistant - help."]);
  return items;
}

function UI_Ensure(self, company)
{
  if (self.pages.rawin(company)) {
    local p = self.pages.rawget(company);
    if (GSStoryPage.IsValidStoryPage(p.page)) {
      if (p.rawin("ver") && p.ver == UI_VERSION) return true;
      // a page from an older version: build it again in the current layout
      GSStoryPage.Remove(p.page);
    }
    if (p.rawin("spage") && GSStoryPage.IsValidStoryPage(p.spage)) GSStoryPage.Remove(p.spage);
    if (p.rawin("dpage") && GSStoryPage.IsValidStoryPage(p.dpage)) GSStoryPage.Remove(p.dpage);
    if (p.rawin("hpage") && GSStoryPage.IsValidStoryPage(p.hpage)) GSStoryPage.Remove(p.hpage);
    self.pages.rawdelete(company);
  }
  local page = GSStoryPage.New(company, "Build assistant");
  if (page == GSStoryPage.STORY_PAGE_INVALID) {
    GSLog.Error("Could not create the Story Book page for company " + company);
    return false;
  }
  local p = { page = page, el = {}, ver = UI_VERSION };
  self.pages.rawset(company, p);
  if (self.titles.rawin(company)) self.titles.rawdelete(company);
  foreach (it in UI_Items()) {
    local id = GSStoryPage.NewElement(page, it[1], it[2], U_Clip(it[3]));
    if (id != GSStoryPage.STORY_PAGE_ELEMENT_INVALID) p.el.rawset(it[0], id);
  }
  // suggestions page: its element names start with s, so they share the el table
  local spage = GSStoryPage.New(company, "Build assistant - suggestions");
  if (spage != GSStoryPage.STORY_PAGE_INVALID) {
    p.spage <- spage;
    local all = Sug_Items();
    foreach (it in Ap_Items()) all.append(it);
    foreach (it in all) {
      local id = GSStoryPage.NewElement(spage, it[1], it[2], U_Clip(it[3]));
      if (id != GSStoryPage.STORY_PAGE_ELEMENT_INVALID) p.el.rawset(it[0], id);
    }
  }
  // debug page: its element names start with x, so they share the el table
  local dpage = GSStoryPage.New(company, "Build assistant - debug");
  if (dpage != GSStoryPage.STORY_PAGE_INVALID) {
    p.dpage <- dpage;
    foreach (it in UI_DebugItems()) {
      local id = GSStoryPage.NewElement(dpage, it[1], it[2], U_Clip(it[3]));
      if (id != GSStoryPage.STORY_PAGE_ELEMENT_INVALID) p.el.rawset(it[0], id);
    }
  }
  local hpage = GSStoryPage.New(company, "Build assistant - help");
  if (hpage != GSStoryPage.STORY_PAGE_INVALID) {
    p.hpage <- hpage;
    foreach (line in UI_HelpLines()) GSStoryPage.NewElement(hpage, GSStoryPage.SPET_TEXT, 0, U_Clip(line));
  }
  UI_DbgSettings(self, company);
  if (self.dlogs.rawin(company)) {
    local d = self.dlogs.rawget(company);
    for (local i = 0; i < d.len() && i < UI_DBG_LINES; i++) UI_SetText(self, company, "x" + i, d[i]);
  }
  UI_Selection(self, company);
  if (self.hist.rawin(company)) {
    local h = self.hist.rawget(company);
    for (local i = 0; i < h.len() && i < 5; i++) UI_SetText(self, company, "h" + i, h[i]);
  }
  if (self.logs.rawin(company)) {
    local d = self.logs.rawget(company);
    for (local i = 0; i < d.len() && i < UI_LOG_LINES; i++) UI_SetText(self, company, "d" + i, d[i]);
  }
  try {
    GSNews.Create(GSNews.NT_GENERAL, "Build assistant is ready: open the Story Book.", company, GSNews.NR_NONE, 0);
  } catch (e) {}
  return true;
}

function UI_SetText(self, company, name, text)
{
  if (!self.pages.rawin(company)) return;
  local p = self.pages.rawget(company);
  if (!p.el.rawin(name)) return;
  local id = p.el.rawget(name);
  // every update is a game command: skip it when the text did not change
  // (the progress line is set after every search step)
  text = U_Clip(text);
  if (::g_shown.rawin(id) && ::g_shown.rawget(id) == text) return;
  if (!GSStoryPage.IsValidStoryPageElement(id)) return;
  ::g_shown.rawset(id, text);
  GSStoryPage.UpdateElement(id, 0, text);
}

/* Text last shown in each Story Book element (not saved). */
g_shown <- {};

function UI_Status(self, company, text)
{
  GSLog.Info(U_Clip("[" + company + "] " + text));
  UI_Dbg(self, company, "status: " + text);
  UI_SetText(self, company, "status", "Status: " + text);
}

/* Progress line: phase name and a bar (pct < 0 = no bar). */
function UI_Progress(self, company, phase, pct)
{
  UI_SetText(self, company, "progress", "Progress: " + phase + (pct >= 0 ? " " + U_Bar(pct) : ""));
  // the page title is always visible, even when the progress line is scrolled away
  if (!self.pages.rawin(company)) return;
  local page = self.pages.rawget(company).page;
  if (!GSStoryPage.IsValidStoryPage(page)) return;
  local title = "Build assistant";
  if (pct >= 0) title += " [" + max(0, min(100, pct)) + "%]";
  if (self.titles.rawin(company) && self.titles.rawget(company) == title) return;
  self.titles.rawset(company, title);
  GSStoryPage.SetTitle(page, title);
}

/* Plan finished: a clear "ready" line instead of the progress bar, and the
 * page title says so too (it is visible even when the page is scrolled). */
function UI_Ready(self, company, text)
{
  UI_SetText(self, company, "progress", "Progress: >>> READY TO BUILD <<< " + text);
  if (!self.pages.rawin(company)) return;
  local page = self.pages.rawget(company).page;
  if (!GSStoryPage.IsValidStoryPage(page)) return;
  local title = "Build assistant [READY - press Build]";
  if (self.titles.rawin(company) && self.titles.rawget(company) == title) return;
  self.titles.rawset(company, title);
  GSStoryPage.SetTitle(page, title);
}

function UI_Pick(self, company)
{
  if (!self.picks.rawin(company)) self.picks.rawset(company, { mode = MODE_ROAD, a = null, b = null, list = [] });
  local p = self.picks.rawget(company);
  if (!p.rawin("list")) p.list <- [];   // picks from older saves
  if (!p.rawin("reuse")) p.reuse <- false;
  if (!p.rawin("transfer")) p.transfer <- false;
  return p;
}

function UI_Selection(self, company)
{
  local p = UI_Pick(self, company);
  local text;
  if (p.list.len() > 0) {
    // the list wins over A/B
    text = "Selection: " + Job_ModeName(p.mode) + (p.mode != MODE_ROAD && p.reuse ? " (uses your tracks)" : "") +
         (p.mode != MODE_ROAD && p.transfer ? " (transfer on)" : "") +
           " | list of " + p.list.len() + ": ";
    for (local i = 0; i < p.list.len(); i++) text += (i > 0 ? " > " : "") + Tg_Name(p.list[i]);
    if (p.list.len() < 2) text += " (add at least one more)";
    UI_SetText(self, company, "sel", text);
    return;
  }
  text = "Selection: " + Job_ModeName(p.mode) + (p.mode != MODE_ROAD && p.reuse ? " (uses your tracks)" : "") +
         (p.mode != MODE_ROAD && p.transfer ? " (transfer on)" : "") +
         " | A: " + Tg_Name(p.a) + " | B: " + Tg_Name(p.b);
  if (p.a != null && p.b != null && Tg_Valid(p.a) && Tg_Valid(p.b)) {
    local link = Tg_Link(p.a, p.b);
    if (link == null) text += " | no cargo between them";
    else text += " | carries " + GSCargo.GetCargoLabel(link.cargo) + " from " + Tg_Name(link.from);
  }
  UI_SetText(self, company, "sel", text);
}

/* Diagnostic line for the Log part of the page (and the script log).
 * level: "!" = problem, "i" = info. */
function UI_Diag(self, company, level, text)
{
  local line = (level == "!" ? "[!] " : "[i] ") + GSDate.GetYear(GSDate.GetCurrentDate()) + "-" +
               GSDate.GetMonth(GSDate.GetCurrentDate()) + "-" + GSDate.GetDayOfMonth(GSDate.GetCurrentDate()) + " " + text;
  if (level == "!") GSLog.Warning(U_Clip("[" + company + "] " + text)); else GSLog.Info(U_Clip("[" + company + "] " + text));
  UI_Dbg(self, company, (level == "!" ? "WARN " : "") + text);
  if (!self.logs.rawin(company)) self.logs.rawset(company, []);
  local d = self.logs.rawget(company);
  if (d.len() > 0 && d[0] == line) return;
  d.insert(0, U_Clip(line));
  while (d.len() > UI_LOG_LINES) d.pop();
  for (local i = 0; i < UI_LOG_LINES; i++) UI_SetText(self, company, "d" + i, i < d.len() ? d[i] : "-");
}

/* One line of the technical log on the debug page. Not saved with the game. */
function UI_Dbg(self, company, text)
{
  if (!self.dlogs.rawin(company)) self.dlogs.rawset(company, []);
  local d = self.dlogs.rawget(company);
  local line = U_Clip("t" + GSController.GetTick() + " " + text);
  if (d.len() > 0 && d[0] == line) return;
  d.insert(0, line);
  while (d.len() > UI_DBG_LINES) d.pop();
  for (local i = 0; i < UI_DBG_LINES; i++) UI_SetText(self, company, "x" + i, i < d.len() ? d[i] : "-");
}

/* Settings that matter for the route search, in one line. */
function UI_DbgSettings(self, company)
{
  local ops = "?";
  try {
    if (GSGameSettings.IsValid("script.script_max_opcode_till_suspend"))
      ops = GSGameSettings.GetValue("script.script_max_opcode_till_suspend").tostring();
  } catch (e) {}
  UI_SetText(self, company, "x_set", "Settings: max_distance " + GSController.GetSetting("max_distance") +
    ", search_limit " + GSController.GetSetting("search_limit") + "k, search_per_tick " + GSController.GetSetting("search_per_tick") +
    ", segment_length " + GSController.GetSetting("segment_length") + ", route_quality " + GSController.GetSetting("route_quality") +
    ", bridge " + GSController.GetSetting("max_bridge_length") + ", tunnel " + GSController.GetSetting("max_tunnel_length") +
    ", station_signals " + GSController.GetSetting("station_signals") + ", script opcodes/tick " + ops);
}

/* The job's inner state in one line (debug page). */
function UI_DbgJob(self, job)
{
  local t = "Job: " + Job_ModeName(job.mode) + " " + job.names + " | state " + job.state + " | step " + job.ticks;
  if (job.rawin("astar") && job.astar != null && (job.state == "SEARCH" || job.state == "SEARCH2")) {
    local a = job.astar;
    t += " | part " + (job.wp_i + 1) + "/" + (job.wps.len() + 1) + " | examined " + a.examined + "/" + a.limit +
         " | no progress for " + (a.examined - a.last_imp) + "/" + a.stall + " | closeness " + a.Closeness() + "%";
    if (job.rawin("boost")) t += " | boost x" + job.boost;
    if (job.rawin("retries")) t += " | retries " + job.retries;
    t += " | heuristic " + Job_HW(job);
    if (job.rawin("reuse") && job.reuse && job.rawin("rs")) {
      local rs = job.rs;
      t += " | My tracks: tiles " + rs.tiles + ", along " + rs.along + ", switches " + rs.join +
           ", refused one-way " + rs.oneway + " / test " + rs.refused;
    }
  } else if (job.state == "BUILD" || job.state == "PAUSED") {
    t += " | action " + job.idx + "/" + job.actions.len() + " | failed " + job.failed + " | bank " + GSCompany.GetBankBalance(job.company);
  }
  UI_SetText(self, job.company, "x_job", t);
}

function UI_History(self, company, text)
{
  if (!self.hist.rawin(company)) self.hist.rawset(company, []);
  local h = self.hist.rawget(company);
  h.insert(0, text);
  while (h.len() > 5) h.pop();
  for (local i = 0; i < 5; i++) UI_SetText(self, company, "h" + i, i < h.len() ? h[i] : "-");
}

/* Which button of the company's page an element id is, or null. */
function UI_ElementName(self, company, id)
{
  if (!self.pages.rawin(company)) return null;
  foreach (name, el in self.pages.rawget(company).el) {
    if (el == id) return name;
  }
  return null;
}
