/* Benchmark mode (setting "benchmark"): after loading a game the script plans
 * a fixed set of test routes one after another and builds nothing, so the map
 * stays the same and runs of different script versions can be compared.
 * The routes are picked from the map in a fixed way (biggest towns, industries
 * by id), so the same savegame always gives the same set.
 * Results: Log (summary, failures), debug page and the script debug window
 * (lines starting with BENCH). */

/* Test routes: { mode, a, b, label }. */
function Bench_Routes(max_dist)
{
  local out = [];
  // towns: the 6 biggest, each paired with the nearest town 20..max_dist away
  local towns = GSTownList();
  towns.Valuate(GSTown.GetPopulation);
  towns.Sort(GSList.SORT_BY_VALUE, GSList.SORT_DESCENDING);
  local n = 0;
  for (local t = towns.Begin(); !towns.IsEnd() && n < 6; t = towns.Next()) {
    local loc = GSTown.GetLocation(t), best = -1, best_d = max_dist + 1;
    local all = GSTownList();
    for (local o = all.Begin(); !all.IsEnd(); o = all.Next()) {
      if (o == t) continue;
      local d = GSMap.DistanceManhattan(loc, GSTown.GetLocation(o));
      if (d >= 20 && d < best_d) { best = o; best_d = d; }
    }
    if (best < 0) continue;
    out.append({ mode = n == 0 ? MODE_DOUBLE : MODE_RAIL, a = { kind = "town", id = t }, b = { kind = "town", id = best }, label = "town" });
    n++;
  }
  // industries: the first 4 (by id) that produce a cargo another industry
  // 20..max_dist away accepts
  local inds = GSIndustryList();
  inds.Sort(GSList.SORT_BY_ITEM, GSList.SORT_ASCENDING);
  n = 0;
  for (local i = inds.Begin(); !inds.IsEnd() && n < 4; i = inds.Next()) {
    local prod = GSCargoList_IndustryProducing(i);
    local found = false;
    for (local c = prod.Begin(); !prod.IsEnd() && !found; c = prod.Next()) {
      local acc = GSIndustryList_CargoAccepting(c);
      acc.Valuate(GSIndustry.GetDistanceManhattanToTile, GSIndustry.GetLocation(i));
      acc.KeepBetweenValue(19, max_dist + 1);
      acc.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
      if (acc.IsEmpty()) continue;
      out.append({ mode = MODE_RAIL, a = { kind = "industry", id = i }, b = { kind = "industry", id = acc.Begin() }, label = "cargo" });
      found = true;
      n++;
    }
  }
  return out;
}

function Bench_Start(self)
{
  local company = -1;
  for (local i = 0; i < 15 && company < 0; i++) {
    local c = GSCompany.ResolveCompanyID(i);
    if (c != GSCompany.COMPANY_INVALID) company = c;
  }
  if (company < 0) {
    // a fresh map without players: start when the first company appears
    self.bench_wait = true;
    U_Log("i", "BENCH: no company yet, the benchmark starts when one is founded");
    return;
  }
  self.bench_wait = false;
  local list = Bench_Routes(GSController.GetSetting("max_distance"));
  self.bench = { company = company, list = list, i = 0, ok = 0, ticks = 0, exam = 0, t0 = GSController.GetTick() };
  UI_Diag(self, company, "i", "Benchmark: planning " + list.len() + " test routes, nothing is built. Results in the Log, the debug page and the script debug window (BENCH).");
  U_Log("i", "BENCH start: " + list.len() + " routes, settings: search_limit " + GSController.GetSetting("search_limit") +
        "k, segment_length " + GSController.GetSetting("segment_length") + ", route_quality " + GSController.GetSetting("route_quality") +
        ", follow_lines " + GSController.GetSetting("follow_lines") + ", allow_terraform " + GSController.GetSetting("allow_terraform"));
}

/* Starts the next test route when the company has no job. */
function Bench_Tick(self)
{
  local b = self.bench;
  if (self.jobs.rawin(b.company)) return;
  if (b.i >= b.list.len()) {
    local text = "Benchmark done: " + b.ok + "/" + b.list.len() + " routes found, " + b.ticks + " ticks, " +
                 (b.exam / 1000) + "k tiles examined (" + (GSController.GetTick() - b.t0) + " ticks in all).";
    UI_Diag(self, b.company, "i", text);
    UI_History(self, b.company, text);
    U_Log("i", "BENCH " + text);
    self.bench = null;
    return;
  }
  local r = b.list[b.i];
  b.i++;
  if (!Tg_Valid(r.a) || !Tg_Valid(r.b)) return;
  local job = Job_New(b.company, r.mode, r.a, r.b);
  job.auto <- true;
  job.bench <- b.i;
  job.bench_t0 <- GSController.GetTick();
  job.names = "[bench " + b.i + "/" + b.list.len() + "] " + job.names;
  self.jobs.rawset(b.company, job);
}

/* One test route finished (found = route planned). */
function Bench_Record(self, job, found, info)
{
  local b = self.bench;
  if (b == null) return;
  local ticks = GSController.GetTick() - job.bench_t0;
  local exam = Job_Examined(job);
  b.ticks += ticks;
  b.exam += exam;
  if (found) b.ok++;
  local line = job.names + " " + Job_ModeName(job.mode) + ": " + (found ? "OK" : "FAIL") + ", " + ticks + " ticks, " +
               (exam / 1000) + "k tiles examined" + (job.rawin("retries") ? ", retries " + job.retries : "") + ", " + info;
  U_Log("i", "BENCH " + line);
  if (!found) UI_Diag(self, job.company, "!", line);
}
