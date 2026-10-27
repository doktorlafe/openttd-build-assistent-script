require("util.nut");
require("astar.nut");
require("targets.nut");
require("path_road.nut");
require("path_rail.nut");
require("build_road.nut");
require("build_rail.nut");
require("preview.nut");
require("actions.nut");
require("jobs.nut");
require("advice.nut");
require("loop.nut");
require("vehicles.nut");
require("ui.nut");
require("bench.nut");

class LafeBuildAssistant extends GSController {
  pages = null;   // company -> { page, el }
  picks = null;   // company -> { mode, a, b }
  jobs = null;    // company -> job
  hist = null;    // company -> [texts]
  logs = null;    // company -> [diagnostic lines]
  dlogs = null;   // company -> [technical log lines] (debug page, not saved)
  titles = null;  // company -> current page title
  queue = null;   // company -> legs still to build from a town list
  chains = null;  // company -> { list, spots, depot } of the town list being built
  bigst = null;   // company -> [stations built by the script, for later lines to join]
  loops = null;   // company -> [loop lines: station + inbound and return track tiles, for branches]
  bench = null;   // benchmark run (setting "benchmark"), not saved
  bench_wait = false;   // benchmark waits for the first company
  bench_on = false;     // last seen value of the "benchmark" setting
  turn = 0;       // round robin over the companies

  constructor() {
    this.pages = {};
    this.picks = {};
    this.jobs = {};
    this.hist = {};
    this.logs = {};
    this.dlogs = {};
    this.titles = {};
    this.queue = {};
    this.chains = {};
    this.bigst = {};
    this.loops = {};
  }

  function Start();
  function Save();
  function Load(version, data);
  function HandleEvent(ev);
  function OnButton(company, name);
  function PlanList(company, p);
  function ListFromSigns(company, p);
  function RunJobs();
}

function LafeBuildAssistant::Save()
{
  local jobs = {};
  foreach (c, job in this.jobs) {
    local d = Job_SaveData(job);
    if (d != null) jobs.rawset(c, d);
  }
  // texts are cut to the 255 byte limit of the savegame; the actions and the
  // tile lists hold no long texts and are big, so they are saved as they are
  foreach (c, d in jobs) {
    foreach (k, x in d) if (typeof x == "string" || (typeof x == "array" && k != "actions")) d.rawset(k, U_SaveSafe(x));
  }
  return { pages = U_SaveSafe(this.pages), picks = U_SaveSafe(this.picks), hist = U_SaveSafe(this.hist), logs = U_SaveSafe(this.logs),
           jobs = jobs, queue = U_SaveSafe(this.queue), chains = U_SaveSafe(this.chains), bigst = this.bigst, loops = this.loops };
}

function LafeBuildAssistant::Load(version, data)
{
  if (data.rawin("pages")) this.pages = data.rawget("pages");
  if (data.rawin("picks")) this.picks = data.rawget("picks");
  if (data.rawin("hist")) this.hist = data.rawget("hist");
  if (data.rawin("logs")) this.logs = data.rawget("logs");
  if (data.rawin("queue")) this.queue = data.rawget("queue");
  if (data.rawin("chains")) this.chains = data.rawget("chains");
  if (data.rawin("bigst")) this.bigst = data.rawget("bigst");
  if (data.rawin("loops")) this.loops = data.rawget("loops");
  if (data.rawin("jobs")) {
    foreach (c, d in data.rawget("jobs")) this.jobs.rawset(c, Job_LoadData(d));
  }
}

function LafeBuildAssistant::Start()
{
  U_MapInit();   // before anything that steps over tiles
  U_Log("i", "Lafe Build Assistant v3 (fast search, 2026-10-26) started, opcodes per tick: " + GSGameSettings.GetValue("script.script_max_opcode_till_suspend"));
  this.Sleep(1);
  try { Preview_CleanLeftovers(); } catch (e) {}
  for (local i = 0; i < 15; i++) {
    local c = GSCompany.ResolveCompanyID(i);
    if (c != GSCompany.COMPANY_INVALID) UI_Ensure(this, c);
  }
  while (true) {
    // the benchmark starts when the setting is switched on (at load or in-game)
    local on = GSController.GetSetting("benchmark") != 0;
    if (on && !this.bench_on && this.bench == null && !this.bench_wait) Bench_Start(this);
    this.bench_on = on;
    while (GSEventController.IsEventWaiting()) {
      local ev = GSEventController.GetNextEvent();
      try {
        this.HandleEvent(ev);
      } catch (e) {
        U_Log("e", U_Clip("Event failed: " + e));
      }
    }
    local busy = false;
    try {
      busy = this.RunJobs();
    } catch (e) {
      U_Log("e", U_Clip("Job failed: " + e));
      // drop the job that crashed so it does not crash again
      foreach (c, job in this.jobs) {
        if (Job_IsActive(job)) {
          UI_Status(this, c, "Internal error, job cancelled: " + e);
          Job_Drop(this, job);
          break;
        }
      }
    }
    // while working, do not sleep: the game pauses the script by itself
    // when its operations for the tick are used up
    if (!busy) this.Sleep(5);
  }
}

/* Runs one step of the next active job. Returns true if any job is active. */
function LafeBuildAssistant::RunJobs()
{
  // start the next leg of a town list when the company has no job
  foreach (c, legs in this.queue) {
    if (legs.len() == 0 || this.jobs.rawin(c)) continue;
    local leg = legs[0];
    legs.remove(0);
    local job = Job_New(c, leg.mode, leg.a, leg.b);
    job.auto <- true;
    job.reuse <- leg.rawin("reuse") && leg.reuse;
    if (leg.rawin("k") && this.chains.rawin(c)) {
      job.chain <- this.chains.rawget(c);
      job.chain_k <- leg.k;
    }
    job.names = "(" + leg.n + "/" + leg.total + ") " + job.names;
    this.jobs.rawset(c, job);
    UI_Status(this, c, "Town list: planning " + job.names + " ...");
  }
  if (this.bench != null) Bench_Tick(this);
  local active = [];
  foreach (c, job in this.jobs) if (Job_IsActive(job)) active.append(c);
  if (active.len() == 0) return false;
  this.turn = (this.turn + 1) % active.len();
  local company = active[this.turn];
  local job = this.jobs.rawget(company);
  if (GSCompany.ResolveCompanyID(company) == GSCompany.COMPANY_INVALID) {
    Job_Drop(this, job);
    return true;
  }
  local mode = GSCompanyMode(company);
  ::g_ctx = { self = this, company = company };
  try {
    Job_Step(this, job);
  } catch (e) {
    ::g_ctx = null;
    UI_Diag(this, company, "!", "Internal error in " + job.names + ": " + e);
    throw e;
  }
  ::g_ctx = null;
  return true;
}

function LafeBuildAssistant::HandleEvent(ev)
{
  local type = ev.GetEventType();
  if (type == GSEvent.ET_COMPANY_NEW) {
    UI_Ensure(this, GSEventCompanyNew.Convert(ev).GetCompanyID());
    if (this.bench_wait) Bench_Start(this);
  } else if (type == GSEvent.ET_COMPANY_BANKRUPT) {
    local c = GSEventCompanyBankrupt.Convert(ev).GetCompanyID();
    if (this.jobs.rawin(c)) this.jobs.rawdelete(c);
    if (this.queue.rawin(c)) this.queue.rawdelete(c);
    if (this.pages.rawin(c)) this.pages.rawdelete(c);
  } else if (type == GSEvent.ET_STORYPAGE_TILE_SELECT) {
    local e = GSEventStoryPageTileSelect.Convert(ev);
    local company = e.GetCompanyID();
    local name = UI_ElementName(this, company, e.GetElementID());
    if (name == "loop_pick") {
      local town = GSTile.GetClosestTown(e.GetTile());
      if (!GSTown.IsValidTown(town)) {
        UI_Status(this, company, "No town there.");
        return;
      }
      UI_Status(this, company, "Building bus loop in " + GSTown.GetName(town) + " ...");
      local mode = GSCompanyMode(company);
      local text = Loop_Build(town, GSController.GetSetting("loop_stops"), GSController.GetSetting("loop_gap"),
                              GSController.GetSetting("veh_loop"));
      UI_SetText(this, company, "loop_result", text);
      UI_Diag(this, company, "i", text);
      UI_Status(this, company, text);
      UI_History(this, company, text);
      return;
    }
    if (name != "pick_a" && name != "pick_b" && name != "list_add") return;
    local target = Tg_FromTile(e.GetTile());
    if (target == null) {
      UI_Status(this, company, "Nothing there to connect.");
      return;
    }
    local p = UI_Pick(this, company);
    if (name == "list_add") {
      if (p.list.len() >= 10) {
        UI_Status(this, company, "The list is full (10). Press Clear to start again.");
        return;
      }
      local last = p.list.len() > 0 ? p.list[p.list.len() - 1] : null;
      if (last != null && last.kind == target.kind && last.id == target.id) {
        UI_Status(this, company, Tg_Name(target) + " is already the last one in the list.");
        return;
      }
      p.list.append(target);
    } else if (name == "pick_a") {
      p.a = target;
    } else {
      p.b = target;
    }
    UI_Selection(this, company);
  } else if (type == GSEvent.ET_STORYPAGE_BUTTON_CLICK) {
    local e = GSEventStoryPageButtonClick.Convert(ev);
    local company = e.GetCompanyID();
    local name = UI_ElementName(this, company, e.GetElementID());
    if (name != null) {
      UI_Dbg(this, company, "button " + name);
      ::g_ctx = { self = this, company = company };
      try {
        this.OnButton(company, name);
      } catch (ex) {
        ::g_ctx = null;
        throw ex;
      }
      ::g_ctx = null;
    }
  }
}

/* Adds the company's signs to the list, in the order they were placed
 * (sign ids grow), and removes them. The sign tool stays active in the game,
 * so many towns can be marked click after click. */
function LafeBuildAssistant::ListFromSigns(company, p)
{
  local mode = GSCompanyMode(company);
  local ids = GSSignList();
  ids.Sort(GSList.SORT_BY_ITEM, GSList.SORT_ASCENDING);
  local added = 0, skipped = 0, found = 0;
  for (local s = ids.Begin(); !ids.IsEnd(); s = ids.Next()) {
    local owner = GSCompany.COMPANY_INVALID;
    try { owner = GSSign.GetOwner(s); } catch (e) {}
    if (owner != company) continue;
    if (Preview_IsOwnSign(GSSign.GetName(s))) continue;   // route preview / live search signs
    found++;
    local target = Tg_FromTile(GSSign.GetLocation(s));
    local last = p.list.len() > 0 ? p.list[p.list.len() - 1] : null;
    if (target == null || p.list.len() >= 10 || (last != null && last.kind == target.kind && last.id == target.id)) {
      skipped++;
    } else {
      p.list.append(target);
      added++;
    }
    GSSign.RemoveSign(s);
  }
  UI_Selection(this, company);
  if (found == 0) {
    UI_Status(this, company, "No signs of your company. Use the sign tool and click the towns one after another, then press List from signs.");
    return;
  }
  UI_Status(this, company, "Added " + added + " from signs" + (skipped > 0 ? ", " + skipped + " skipped (same as the one before, nothing there, or the list is full)" : "") +
    ". Press Plan, or Cancel to throw the list away.");
}

/* Town list: one leg per neighbour pair, built one after another without
 * asking for confirmation (each leg still has to fit the cost limit). */
function LafeBuildAssistant::PlanList(company, p)
{
  local list = [];
  foreach (t in p.list) if (Tg_Valid(t)) list.append(t);
  if (list.len() < 2) {
    UI_Status(this, company, "Add at least two towns to the list.");
    return;
  }
  local max_dist = GSController.GetSetting("max_distance");
  local legs = [];
  for (local i = 0; i + 1 < list.len(); i++) {
    local a = list[i], b = list[i + 1];
    local dist = GSMap.DistanceManhattan(Tg_Center(a), Tg_Center(b));
    if (dist > max_dist) {
      UI_Status(this, company, Tg_Name(a) + " - " + Tg_Name(b) + " is " + dist + " tiles, the limit is " + max_dist + ". Change the list.");
      UI_Diag(this, company, "!", "List refused: " + Tg_Name(a) + " - " + Tg_Name(b) + " is " + dist + " tiles (limit " + max_dist + ", setting max_distance).");
      return;
    }
    legs.append({ mode = p.mode, reuse = p.reuse, a = { kind = a.kind, id = a.id }, b = { kind = b.kind, id = b.id }, n = i + 1, total = list.len() - 1 });
  }
  // a list of towns becomes one line: shared through stations, vehicles run A..Z
  local towns = true;
  foreach (t in list) if (t.kind != "town") towns = false;
  if (towns && p.mode != MODE_DOUBLE) {
    local spots = [];
    foreach (t in list) spots.append(null);
    local saved = [];
    foreach (t in list) saved.append({ kind = t.kind, id = t.id });
    this.chains.rawset(company, { list = saved, spots = spots, plan = null, depot = -1 });
    for (local i = 0; i < legs.len(); i++) legs[i].k <- i;
  }
  this.queue.rawset(company, legs);
  UI_Status(this, company, "Town list: " + legs.len() + " leg(s) queued, they are built one after another" +
    (legs[0].rawin("k") ? " as one line through all towns." : "."));
}

function LafeBuildAssistant::OnButton(company, name)
{
  local p = UI_Pick(this, company);
  local job = this.jobs.rawin(company) ? this.jobs.rawget(company) : null;

  if (name == "mode_road" || name == "mode_rail" || name == "mode_double") {
    p.mode = name == "mode_road" ? MODE_ROAD : (name == "mode_rail" ? MODE_RAIL : MODE_DOUBLE);
    UI_Selection(this, company);
  } else if (name == "transfer") {
    p.transfer = !p.transfer;
    UI_Selection(this, company);
    UI_Status(this, company, p.transfer
      ? "Transfer: ON. If your trains already carry the cargo to B, only a feeder to their nearest station is built."
      : "Transfer: OFF. Railways go all the way from A to B.");
  } else if (name == "reuse") {
    p.reuse = !p.reuse;
    UI_Selection(this, company);
    UI_Status(this, company, p.reuse
      ? "My tracks: ON. New railways may run on your existing tracks and join them with switches and signals."
      : "My tracks: OFF. New railways are built completely new, next to your old ones.");
  } else if (name == "list_signs") {
    this.ListFromSigns(company, p);
  } else if (name == "list_clear") {
    p.list = [];
    UI_Selection(this, company);
    UI_Status(this, company, "List cleared.");
  } else if (name == "plan") {
    if (job != null || (this.queue.rawin(company) && this.queue.rawget(company).len() > 0)) {
      UI_Status(this, company, "A job is already running" + (job != null ? " (" + job.names + ")" : "") + ". Press Cancel first.");
      return;
    }
    if (p.list.len() > 0) {
      this.PlanList(company, p);
      return;
    }
    if (!Tg_Valid(p.a) || !Tg_Valid(p.b)) {
      UI_Status(this, company, "Pick A and B first.");
      return;
    }
    if (p.a.kind == p.b.kind && p.a.id == p.b.id) {
      UI_Status(this, company, "End A and end B are the same.");
      return;
    }
    local dist = GSMap.DistanceManhattan(Tg_Center(p.a), Tg_Center(p.b));
    local max_dist = GSController.GetSetting("max_distance");
    // Transfer: a short feeder to the nearest station your trains carry the cargo from
    local hub = null;
    if (p.transfer && p.mode != MODE_ROAD) {
      local cm = GSCompanyMode(company);
      hub = Tg_FindHub(p.a, p.b, max_dist);
      if (hub == null) {
        local hi = ::g_hubinfo;
        local why = hi == null ? "" : " Checked: " + hi.carry + " train(s) can carry a cargo of " + Tg_Name(p.a) + ", " +
          hi.to_b + " of them go to a station near " + Tg_Name(p.b) + " that accepts it, " + hi.hubs +
          " station(s) where they load, none within " + max_dist + " tiles of " + Tg_Name(p.a) + ".";
        UI_Diag(this, company, "!", "Transfer: no station to feed." + why + " Planning the whole way instead.");
      }
    }
    if (hub != null) {
      local h = { kind = "station", id = hub.hub };
      local nj = Job_New(company, p.mode, { kind = p.a.kind, id = p.a.id }, h);
      nj.reuse <- p.reuse;
      nj.forced_link <- { from = nj.a, to = h, cargo = hub.cargo, pax = hub.pax };
      nj.transfer_to <- { kind = p.b.kind, id = p.b.id };
      nj.transfer_name <- Tg_Name(p.b);
      nj.names = Tg_Name(p.a) + " - " + Tg_Name(h) + " (transfer to " + Tg_Name(p.b) + ")";
      this.jobs.rawset(company, nj);
      UI_Diag(this, company, "i", "Transfer: " + GSCargo.GetName(hub.cargo) + " of " + Tg_Name(p.a) + " goes to your station " +
              Tg_Name(h) + " (" + GSMap.DistanceManhattan(Tg_Center(p.a), Tg_Center(h)) + " tiles instead of " + dist + "), " +
              hub.trains + " of your train(s) take it on to " + Tg_Name(p.b) + ".");
      if (hub.trains < 2) UI_Diag(this, company, "!", "Transfer: only " + hub.trains + " train loads at " + Tg_Name(h) +
              ". If the cargo piles up there, add trains to that line, waiting cargo slowly disappears.");
      UI_Status(this, company, "Planning " + nj.names + " ...");
      return;
    }
    if (dist > max_dist) {
      UI_Status(this, company, "The ends are " + dist + " tiles apart, the limit is " + max_dist + "." +
        (p.mode != MODE_ROAD && !p.transfer ? " Tip: switch Transfer on to feed one of your lines that already goes there." : ""));
      UI_Diag(this, company, "!", "Plan refused: ends " + dist + " tiles apart (limit " + max_dist + ", setting max_distance).");
      return;
    }
    if (GSCompany.GetBankBalance(company) <= 0) {
      UI_Diag(this, company, "!", "NOT ENOUGH MONEY: your bank balance is " + GSCompany.GetBankBalance(company) +
              ". Planning goes on, but station places, bridges and tunnels need money even to be tested. " + U_MoneyText(company) + ".");
    }
    U_Log("i", "[" + company + "] new job, mode " + p.mode);
    local nj = Job_New(company, p.mode, { kind = p.a.kind, id = p.a.id }, { kind = p.b.kind, id = p.b.id });
    nj.reuse <- p.reuse;
    this.jobs.rawset(company, nj);
    UI_Status(this, company, "Planning " + Job_ModeName(p.mode) + " " + Tg_Name(p.a) + " - " + Tg_Name(p.b) + " ...");
  } else if (name == "confirm") {
    if (job == null || job.state != "CONFIRM") {
      UI_Status(this, company, "Nothing to build. Press Plan first.");
      return;
    }
    local mode = GSCompanyMode(company);
    Job_Confirm(this, job);
  } else if (name == "cancel") {
    if (job == null) {
      // nothing running: Cancel throws away the selection instead
      if (p.list.len() > 0 || p.a != null || p.b != null) {
        p.list = [];
        p.a = null;
        p.b = null;
        UI_Selection(this, company);
        UI_Status(this, company, "Selection cleared.");
      } else {
        UI_Status(this, company, "Nothing to cancel.");
      }
      return;
    }
    local mode = GSCompanyMode(company);
    local done = job.state == "BUILD" || job.state == "PAUSED" ? " (already built parts stay)" : "";
    local legs = this.queue.rawin(company) ? this.queue.rawget(company).len() : 0;
    if (legs > 0) this.queue.rawset(company, []);
    Job_Drop(this, job);
    UI_Status(this, company, "Cancelled " + job.names + done + (legs > 0 ? ", and " + legs + " more leg(s) of the list" : "") + ".");
  } else if (name == "resume") {
    if (job == null || job.state != "PAUSED") {
      UI_Status(this, company, "Nothing to resume.");
      return;
    }
    job.state = "BUILD";
    UI_Status(this, company, "Resuming " + job.names + " ...");
  }
}
