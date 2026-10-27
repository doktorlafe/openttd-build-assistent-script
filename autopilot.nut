/* Autopilot (on the suggestions page). Per company: OFF, BUILD, PLAN ONLY.
 * BUILD keeps building route after route until it is switched off: right
 * after a route is built the next round starts. When nothing fits (money,
 * no paying route) it checks again every ap_interval months.
 * A round:
 *   1. Suggest: scan the industries (suggest.nut)
 *   2. take the best suggestion whose estimate fits the budget
 *      (ap_budget_percent of the bank balance)
 *   3. Plan it. A plan that fails, costs more than the budget or more than
 *      1.5x the estimate is skipped and the next suggestion is planned
 *   4. BUILD: build it with the trains. PLAN ONLY: only report what it
 *      would build, nothing is spent
 *   5. BUILD: next round at once; PLAN ONLY: wait ap_interval months
 * A source it has built from is not suggested to it again.
 * One job at a time; a job the player started is never touched.
 * Plan time limit: a plan of its own not ready within ap_plan_timeout real
 * seconds (default 50) is given up and the next suggestion is planned.
 * Watchdog: when nothing new happens for ap_watchdog real minutes (default
 * 30), it moves on by itself: its own job that is stuck is cancelled (one
 * paused for money is resumed first), and a wait for the next round ends. */

const AP_OFF = 0;
const AP_PLAN = 1;
const AP_BUILD = 2;
const AP_HIST = 3;

/* Real time in seconds (the server's clock). Falls back to game ticks
 * (27 ms each at normal speed) where the clock is not available. */
function Ap_Now()
{
  try {
    return GSDate.GetSystemTime();
  } catch (e) {
    return GSController.GetTick() * 27 / 1000;
  }
}

function Ap_Items()
{
  local push = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_ORANGE, GSStoryPage.SPBF_NONE);
  local items = [
    ["a_title", GSStoryPage.SPET_TEXT, 0, "--- Autopilot ---  Every few months it picks the best suggestion that fits the budget, plans it and builds it. PLAN ONLY just reports what it would build."],
    ["a_mode", GSStoryPage.SPET_BUTTON_PUSH, push, "Autopilot: OFF / BUILD / PLAN ONLY"],
    ["a_state", GSStoryPage.SPET_TEXT, 0, "Autopilot: OFF."]
  ];
  for (local i = 0; i < AP_HIST; i++) items.append(["a_h" + i, GSStoryPage.SPET_TEXT, 0, " "]);
  return items;
}

function Ap_ModeName(m)
{
  return m == AP_BUILD ? "BUILD" : (m == AP_PLAN ? "PLAN ONLY" : "OFF");
}

function Ap_State(self, company)
{
  if (self.ap == null) self.ap = {};
  if (!self.ap.rawin(company)) self.ap.rawset(company, { mode = AP_OFF, next = 0, cands = [], i = 0, budget = 0, hist = [], done = {}, seen = Ap_Now(), mark = "" });
  return self.ap.rawget(company);
}

function Ap_Date(d)
{
  return GSDate.GetDayOfMonth(d) + "." + GSDate.GetMonth(d) + "." + GSDate.GetYear(d);
}

/* State line on the page and in the debug window. */
function Ap_Say(self, company, text)
{
  local st = Ap_State(self, company);
  st.seen = Ap_Now();   // something new: the watchdog starts again
  UI_SetText(self, company, "a_state", U_Clip("Autopilot " + Ap_ModeName(st.mode) + ": " + text));
  U_Log("i", U_Clip("AP [" + company + "] " + text));
}

/* A decision for the history lines (newest first) and the Log. */
function Ap_Note(self, company, text)
{
  local st = Ap_State(self, company);
  local line = U_Clip(Ap_Date(GSDate.GetCurrentDate()) + " " + text);
  st.hist.insert(0, line);
  while (st.hist.len() > AP_HIST) st.hist.pop();
  for (local i = 0; i < st.hist.len(); i++) UI_SetText(self, company, "a_h" + i, st.hist[i]);
  UI_Diag(self, company, "i", "Autopilot: " + text);
}

/* The a_mode button: OFF -> BUILD -> PLAN ONLY -> OFF. */
function Ap_Toggle(self, company)
{
  local st = Ap_State(self, company);
  if (!GSController.GetSetting("ap_allowed")) {
    st.mode = AP_OFF;
    Ap_Say(self, company, "switched off on this server (setting ap_allowed).");
    return;
  }
  st.mode = st.mode == AP_OFF ? AP_BUILD : (st.mode == AP_BUILD ? AP_PLAN : AP_OFF);
  st.cands = [];
  st.i = 0;
  st.next = GSDate.GetCurrentDate();   // first round right away
  st.seen = Ap_Now();
  Ap_Say(self, company, st.mode == AP_OFF ? "off." : (st.mode == AP_BUILD ? "on, builds route after route until you switch it off." : "on, only reports what it would build."));
}

/* Called from the main loop: starts rounds and the next plan. */
function Ap_Tick(self)
{
  if (self.ap == null) return;
  local allowed = GSController.GetSetting("ap_allowed") != 0;
  foreach (company, st in self.ap) {
    if (st.mode == AP_OFF) continue;
    if (!allowed) {
      st.mode = AP_OFF;
      Ap_Say(self, company, "switched off on this server (setting ap_allowed).");
      continue;
    }
    if (GSCompany.ResolveCompanyID(company) == GSCompany.COMPANY_INVALID) continue;
    if (Ap_Watchdog(self, company, st)) continue;
    // busy: a job (own or the player's) or a town list is running
    if (self.jobs.rawin(company)) continue;
    if (self.queue.rawin(company) && self.queue.rawget(company).len() > 0) continue;
    if (st.i < st.cands.len()) {
      Ap_PlanNext(self, company, st);
      continue;
    }
    local now = GSDate.GetCurrentDate();
    if (now < st.next) continue;
    Ap_Round(self, company, st, now);
  }
}

/* Plan time limit and watchdog. Returns true when it acted. */
function Ap_Watchdog(self, company, st)
{
  local job = self.jobs.rawin(company) ? self.jobs.rawget(company) : null;
  local own = job != null && job.rawin("ap");
  // a plan of its own that takes too long: give it up, plan the next one
  local secs = GSController.GetSetting("ap_plan_timeout");
  if (own && secs > 0 && (job.state == "PREP" || job.state == "SEARCH" || job.state == "SEARCH2") &&
      Ap_Now() - job.ap.t0 > secs) {
    Ap_Note(self, company, "skipped " + job.names + ": no plan within " + secs + " s, trying the next one.");
    Job_Drop(self, job);
    if (st.i >= st.cands.len()) Ap_Say(self, company, "nothing could be planned in time this round. Next check " + Ap_Date(st.next) + ".");
    return true;
  }
  // progress of its own job counts as something new
  if (own) {
    local mark = job.state + ":" + job.idx + ":" + Job_Examined(job);
    if (mark != st.mark) { st.mark = mark; st.seen = Ap_Now(); }
  }
  local mins = GSController.GetSetting("ap_watchdog");
  if (mins <= 0 || Ap_Now() - st.seen < mins * 60) return false;
  if (job != null) {
    if (!own) { st.seen = Ap_Now(); return false; }   // the player's job: wait, never touch it
    if (job.state == "PAUSED") {
      Ap_Note(self, company, "nothing new for " + mins + " min, resuming " + job.names + ".");
      job.state = "BUILD";
    } else {
      Ap_Note(self, company, "nothing new for " + mins + " min, " + job.names + " is stuck in " + job.state + ": cancelled, going on.");
      Job_Drop(self, job);
    }
    st.seen = Ap_Now();
    return true;
  }
  // only waiting for the next round: start it now
  if (st.i >= st.cands.len() && GSDate.GetCurrentDate() < st.next) {
    Ap_Note(self, company, "nothing new for " + mins + " min, checking again now instead of " + Ap_Date(st.next) + ".");
    st.next = GSDate.GetCurrentDate();
  }
  st.seen = Ap_Now();
  return false;
}

/* A new round: suggestions within the budget, best first. */
function Ap_Round(self, company, st, now)
{
  local months = GSController.GetSetting("ap_interval");
  st.next = now + months * 30;
  local bank = GSCompany.GetBankBalance(company);
  st.budget = bank / 100 * GSController.GetSetting("ap_budget_percent");
  if (st.budget <= 0) {
    Ap_Say(self, company, "waiting for money (bank " + bank + "). Next check " + Ap_Date(st.next) + ".");
    return;
  }
  Sug_Run(self, company);
  st.cands = [];
  st.i = 0;
  if (self.sugs != null && self.sugs.rawin(company)) {
    foreach (s in self.sugs.rawget(company)) {
      // a source already connected by the autopilot (its share carried shows
      // only after a month, so the suggester would offer it again)
      if (st.done.rawin(s.src)) continue;
      if (s.cost <= st.budget) st.cands.append(s);
    }
  }
  if (st.cands.len() == 0) {
    Ap_Say(self, company, "no suggestion fits the budget of " + Sug_Money(st.budget) + " (" +
           GSController.GetSetting("ap_budget_percent") + "% of the bank). Next check " + Ap_Date(st.next) + ".");
    return;
  }
  Ap_Say(self, company, st.cands.len() + " suggestion(s) fit the budget of " + Sug_Money(st.budget) + ", planning the best one ...");
}

/* Plans the next candidate of the round. */
function Ap_PlanNext(self, company, st)
{
  local s = st.cands[st.i];
  st.i++;
  if (!GSIndustry.IsValidIndustry(s.src) || !GSIndustry.IsValidIndustry(s.dst)) return;
  local job = Job_New(company, MODE_RAIL, { kind = "industry", id = s.src }, { kind = "industry", id = s.dst });
  job.reuse <- false;
  job.ap <- { est = s.cost, budget = st.budget, n = st.i, of = st.cands.len(), t0 = Ap_Now() };
  job.names = "[autopilot] " + job.names;
  self.jobs.rawset(company, job);
  Ap_Say(self, company, "planning " + st.i + "/" + st.cands.len() + ": " + GSIndustry.GetName(s.src) + " -> " +
         GSIndustry.GetName(s.dst) + " (estimate " + Sug_Money(s.cost) + ") ...");
}

/* Job_Plan: an autopilot route is planned. Build it, report it or skip it. */
function Ap_Planned(self, job)
{
  local st = Ap_State(self, job.company);
  local ap = job.ap;
  local why = null;
  if (job.cost > ap.budget) why = "costs " + Sug_Money(job.cost) + ", more than the budget of " + Sug_Money(ap.budget);
  else if (job.cost > ap.est * 3 / 2) why = "costs " + Sug_Money(job.cost) + ", much more than the estimate of " + Sug_Money(ap.est);
  if (why != null) {
    Ap_Note(self, job.company, "skipped " + job.names + ": " + why + ".");
    Job_Drop(self, job);
    if (st.i >= st.cands.len()) Ap_Say(self, job.company, "nothing fitted this round. Next check " + Ap_Date(st.next) + ".");
    return;
  }
  // this round is decided
  st.cands = [];
  st.i = 0;
  if (st.mode != AP_BUILD) {
    Ap_Note(self, job.company, "WOULD BUILD " + job.summary + " (estimate " + Sug_Money(ap.est) + "). Switch to BUILD to let it build.");
    Ap_Say(self, job.company, "plan only, nothing built. Next check " + Ap_Date(st.next) + ".");
    Job_Drop(self, job);
    return;
  }
  st.done.rawset(job.a.id, true);
  Ap_Note(self, job.company, "building " + job.summary + ".");
  Ap_Say(self, job.company, "building " + job.names + " ...");
  Job_Confirm(self, job);
}

/* Job_Fail: the plan of an autopilot route failed; the next one follows. */
function Ap_Failed(self, job, text)
{
  local st = Ap_State(self, job.company);
  Ap_Note(self, job.company, "skipped " + job.names + ": " + text);
  if (st.i >= st.cands.len()) Ap_Say(self, job.company, "nothing could be planned this round. Next check " + Ap_Date(st.next) + ".");
}

/* Job_Finish: an autopilot route is built. */
function Ap_Built(self, job, text)
{
  local st = Ap_State(self, job.company);
  Ap_Note(self, job.company, text);
  // BUILD goes on at once with the next route
  st.next = GSDate.GetCurrentDate();
  Ap_Say(self, job.company, "built " + job.names + ", looking for the next route ...");
}

/* Saved: the mode and the sources already connected, per company. */
function Ap_SaveData(self)
{
  local out = {};
  if (self.ap != null) foreach (c, st in self.ap) {
    local done = [];
    foreach (src, _ in st.done) done.append(src);
    out.rawset(c, { mode = st.mode, done = done });
  }
  return out;
}

function Ap_LoadData(self, data)
{
  foreach (c, d in data) {
    local st = Ap_State(self, c);
    st.mode = d.mode;
    st.next = 0;
    foreach (src in d.done) st.done.rawset(src, true);
  }
}
