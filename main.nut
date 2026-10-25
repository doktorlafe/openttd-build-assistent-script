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

class LafeBuildAssistant extends GSController {
  pages = null;   // company -> { page, el }
  picks = null;   // company -> { mode, a, b }
  jobs = null;    // company -> job
  hist = null;    // company -> [texts]
  titles = null;  // company -> current page title
  queue = null;   // company -> legs still to build from a town list
  chains = null;  // company -> { list, spots, depot } of the town list being built
  turn = 0;       // round robin over the companies

  constructor() {
    this.pages = {};
    this.picks = {};
    this.jobs = {};
    this.hist = {};
    this.titles = {};
    this.queue = {};
    this.chains = {};
  }

  function Start();
  function Save();
  function Load(version, data);
  function HandleEvent(ev);
  function OnButton(company, name);
  function OnAdvicePick(company, tile);
  function PlanList(company, p);
  function RunJobs();
}

function LafeBuildAssistant::Save()
{
  local jobs = {};
  foreach (c, job in this.jobs) {
    local d = Job_SaveData(job);
    if (d != null) jobs.rawset(c, d);
  }
  return { pages = this.pages, picks = this.picks, hist = this.hist, jobs = jobs, queue = this.queue, chains = this.chains };
}

function LafeBuildAssistant::Load(version, data)
{
  if (data.rawin("pages")) this.pages = data.rawget("pages");
  if (data.rawin("picks")) this.picks = data.rawget("picks");
  if (data.rawin("hist")) this.hist = data.rawget("hist");
  if (data.rawin("queue")) this.queue = data.rawget("queue");
  if (data.rawin("chains")) this.chains = data.rawget("chains");
  if (data.rawin("jobs")) {
    foreach (c, d in data.rawget("jobs")) this.jobs.rawset(c, Job_LoadData(d));
  }
}

function LafeBuildAssistant::Start()
{
  GSLog.Info("Lafe Build Assistant v2 started");
  this.Sleep(1);
  for (local i = 0; i < 15; i++) {
    local c = GSCompany.ResolveCompanyID(i);
    if (c != GSCompany.COMPANY_INVALID) UI_Ensure(this, c);
  }

  while (true) {
    while (GSEventController.IsEventWaiting()) {
      local ev = GSEventController.GetNextEvent();
      try {
        this.HandleEvent(ev);
      } catch (e) {
        GSLog.Error(U_Clip("Event failed: " + e));
      }
    }
    local busy = false;
    try {
      busy = this.RunJobs();
    } catch (e) {
      GSLog.Error(U_Clip("Job failed: " + e));
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
    if (leg.rawin("k") && this.chains.rawin(c)) {
      job.chain <- this.chains.rawget(c);
      job.chain_k <- leg.k;
    }
    job.names = "(" + leg.n + "/" + leg.total + ") " + job.names;
    this.jobs.rawset(c, job);
    UI_Status(this, c, "Town list: planning " + job.names + " ...");
  }
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
  Job_Step(this, job);
  return true;
}

function LafeBuildAssistant::HandleEvent(ev)
{
  local type = ev.GetEventType();
  if (type == GSEvent.ET_COMPANY_NEW) {
    UI_Ensure(this, GSEventCompanyNew.Convert(ev).GetCompanyID());
  } else if (type == GSEvent.ET_COMPANY_BANKRUPT) {
    local c = GSEventCompanyBankrupt.Convert(ev).GetCompanyID();
    if (this.jobs.rawin(c)) this.jobs.rawdelete(c);
    if (this.queue.rawin(c)) this.queue.rawdelete(c);
    if (this.pages.rawin(c)) this.pages.rawdelete(c);
  } else if (type == GSEvent.ET_STORYPAGE_TILE_SELECT) {
    local e = GSEventStoryPageTileSelect.Convert(ev);
    local company = e.GetCompanyID();
    local name = UI_ElementName(this, company, e.GetElementID());
    if (name == "adv_pick") {
      this.OnAdvicePick(company, e.GetTile());
      return;
    }
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
        UI_Status(this, company, "The list is full (10). Press Clear list to start again.");
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
    if (name != null) this.OnButton(company, name);
  }
}

/* Train advice for a clicked rail station (its platform length and cargo)
 * or a depot / track (default station length, passengers). */
function LafeBuildAssistant::OnAdvicePick(company, tile)
{
  if (!GSRail.IsRailTile(tile) && !GSRail.IsRailStationTile(tile) && !GSRail.IsRailDepotTile(tile)) {
    UI_Status(this, company, "Click a rail station, depot or track for train advice.");
    return;
  }
  local mode = GSCompanyMode(company);
  local rail = GSRail.GetRailType(tile);
  local len = Adv_PlatformLength(tile);
  if (len < 0) len = GSController.GetSetting("rail_station_length");
  local cargo = GSRail.IsRailStationTile(tile) ? Adv_StationCargo(tile) : Tg_Passengers();
  UI_Advice(this, company, cargo, rail, len);
  UI_Status(this, company, "Train advice updated.");
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
      return;
    }
    legs.append({ mode = p.mode, a = { kind = a.kind, id = a.id }, b = { kind = b.kind, id = b.id }, n = i + 1, total = list.len() - 1 });
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
      UI_Status(this, company, "Pick end A and end B first.");
      return;
    }
    if (p.a.kind == p.b.kind && p.a.id == p.b.id) {
      UI_Status(this, company, "End A and end B are the same.");
      return;
    }
    local dist = GSMap.DistanceManhattan(Tg_Center(p.a), Tg_Center(p.b));
    local max_dist = GSController.GetSetting("max_distance");
    if (dist > max_dist) {
      UI_Status(this, company, "The ends are " + dist + " tiles apart, the limit is " + max_dist + ".");
      return;
    }
    GSLog.Info("[" + company + "] new job, mode " + p.mode);
    this.jobs.rawset(company, Job_New(company, p.mode, { kind = p.a.kind, id = p.a.id }, { kind = p.b.kind, id = p.b.id }));
    UI_Status(this, company, "Planning " + Job_ModeName(p.mode) + " " + Tg_Name(p.a) + " - " + Tg_Name(p.b) + " ...");
  } else if (name == "confirm") {
    if (job == null || job.state != "CONFIRM") {
      UI_Status(this, company, "Nothing to confirm. Press Plan route first.");
      return;
    }
    local mode = GSCompanyMode(company);
    Job_Confirm(this, job);
  } else if (name == "cancel") {
    if (job == null) {
      UI_Status(this, company, "Nothing to cancel.");
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
