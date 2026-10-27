/* Suggestions (own Story Book page "Build assistant - suggestions").
 * The Suggest button scans the industries and lists the best cargo railways:
 * a producing industry that is not served much yet -> an industry that
 * accepts the cargo, 30..150 tiles away. Each route gets a rough estimate:
 *   income  = cargo carried per year x the game's payment for that cargo,
 *             distance and travel time (GSCargo.GetCargoIncome)
 *   cost    = track + 2 stations + the trains needed to carry it
 *   payback = cost / (income - running costs)
 * The list is sorted by payback. The exact price comes from Plan on the
 * build page. Everything here is an estimate for ranking, nothing is built. */

const SUG_LINES = 5;
const SUG_MIN_DIST = 30;
const SUG_MAX_DIST = 150;

/* Elements of the suggestions page: [name, type, reference, text]. */
function Sug_Items()
{
  local items = [
    ["s_head", GSStoryPage.SPET_TEXT, 0, "Find the best cargo railways for your company. Press Suggest: the map is scanned and the 5 best routes are listed with a rough cost, profit and payback time. Plan #N fills in A and B and plans that route on the Build assistant page."],
    ["s_go", GSStoryPage.SPET_BUTTON_PUSH, GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_NONE), "Suggest"],
    ["s_status", GSStoryPage.SPET_TEXT, 0, "Not scanned yet."]
  ];
  local plan = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_NONE);
  for (local i = 0; i < SUG_LINES; i++) {
    items.append(["s" + i, GSStoryPage.SPET_TEXT, 0, " "]);
    items.append(["sd" + i, GSStoryPage.SPET_TEXT, 0, " "]);
    items.append(["sp" + i, GSStoryPage.SPET_BUTTON_PUSH, plan, "Plan #" + (i + 1)]);
  }
  return items;
}

/* Rough figures for one route, or null if it cannot pay. */
function Sug_Estimate(t, src, dst, cargo, avail)
{
  local dist = GSMap.DistanceManhattan(GSIndustry.GetLocation(src), GSIndustry.GetLocation(dst));
  if (dist < SUG_MIN_DIST || dist > t.max_dist) return null;
  local route = dist * 12 / 10;   // the track is longer than the straight line
  // a train at v km/h runs about v * 24 / 686 tiles a day; on average it runs
  // at about 3/4 of its top speed (starting, curves, hills, signals)
  local one_way = route * 686 / (t.speed * 3 / 4 * 24) + 2;
  local round = 2 * one_way + 4;   // + loading and unloading
  local month = avail * 7 / 10;   // a good station rating gets about 70%
  if (month <= 0) return null;
  // full load: the train waits until the industry has made a train load;
  // cargo ages in the train meanwhile, on average for half of that time
  local fill = min(90, t.cap * 30 / max(1, month));
  local days = one_way + fill / 2;
  local per_unit = GSCargo.GetCargoIncome(cargo, dist, days);
  if (per_unit <= 0) return null;
  // trains needed: one train moves cap units every round trip
  local per_train = t.cap * 30 / max(1, round);
  if (per_train <= 0) return null;
  local trains = (month + per_train - 1) / per_train;
  if (trains > 5) { trains = 5; month = per_train * 5; }
  local income = month * 12 * per_unit;
  local profit = income - trains * t.run_cost;
  if (profit <= 0) return null;
  local cost = route * t.track_cost + t.station_cost + trains * t.train_price;
  cost = cost * 12 / 10;   // levelling, clearing, depot, signals
  return { src = src, dst = dst, cargo = cargo, dist = dist, month = month, trains = trains, days = days, fill = fill,
           income = income, profit = profit, cost = cost, payback = cost * 12 / profit,
           per_unit = per_unit, one_way = one_way, run = trains * t.run_cost,
           c_track = route * t.track_cost * 12 / 10, c_st = t.station_cost * 12 / 10, c_train = trains * t.train_price * 12 / 10 };
}

/* Short money text: 48k, 1.2M. */
function Sug_Money(m)
{
  if (m >= 1000000) return (m / 1000000) + "." + (m / 100000 % 10) + "M";
  if (m >= 1000) return (m / 1000) + "k";
  return m.tostring();
}

/* The Suggest button. Errors are shown on the page and in the debug window. */
function Sug_Run(self, company)
{
  local t0 = GSController.GetTick();
  U_Log("i", "SUG [" + company + "] start, map " + GSMap.GetMapSizeX() + "x" + GSMap.GetMapSizeY() +
        ", " + GSIndustryList().Count() + " industries");
  try {
    Sug_Scan(self, company);
  } catch (e) {
    U_Log("e", U_Clip("SUG failed: " + e));
    UI_SetText(self, company, "s_status", U_Clip("Suggest failed: " + e + " (details in the Game Script debug window, lines SUG)"));
  }
  U_Log("i", "SUG done in " + (GSController.GetTick() - t0) + " ticks");
}

/* Scans the map and fills the list. */
function Sug_Scan(self, company)
{
  UI_SetText(self, company, "s_status", "Scanning the industries ...");
  local mode = GSCompanyMode(company);
  local rail = BuildRail_SelectType();
  if (rail < 0) {
    UI_SetText(self, company, "s_status", "No railway type is available yet.");
    return;
  }
  local locos = Adv_Locos(rail);
  if (locos.len() == 0) {
    UI_SetText(self, company, "s_status", "No locomotive can be bought yet.");
    return;
  }
  local loco = locos[0].loco;
  U_Log("i", U_Clip("SUG rail type " + GSRail.GetName(rail) + ", engine " + GSEngine.GetName(loco) +
        " (" + GSEngine.GetMaxSpeed(loco) + " km/h, " + GSEngine.GetPrice(loco) + ", running " + GSEngine.GetRunningCost(loco) + "/year)"));
  local speed = max(20, GSEngine.GetMaxSpeed(loco));
  local slen = GSController.GetSetting("rail_station_length");
  local t = {
    speed = speed,
    max_dist = min(SUG_MAX_DIST, GSController.GetSetting("max_distance")),
    track_cost = GSRail.GetBuildCost(rail, GSRail.BT_TRACK),
    station_cost = GSRail.GetBuildCost(rail, GSRail.BT_STATION) * slen * 2 * 2,
    run_cost = GSEngine.GetRunningCost(loco),
    cap = 0, train_price = 0
  };

  U_Log("i", "SUG costs: track " + t.track_cost + "/tile, 2 stations " + t.station_cost + ", max distance " + t.max_dist);
  local best = [];
  local n_ind = 0, n_low = 0, n_nowagon = 0, n_nodst = 0;
  local acc_cache = {}, wagon_cache = {};
  local inds = GSIndustryList();
  local scanned = 0;
  for (local src = inds.Begin(); !inds.IsEnd(); src = inds.Next()) {
    n_ind++;
    if (n_ind % 20 == 0) UI_SetText(self, company, "s_status", "Scanning the industries ... " + n_ind + " done, " + best.len() + " routes found so far.");
    // oil rigs and other industries on water: no railway can reach them
    if (GSIndustry.IsBuiltOnWater(src)) {
      U_Log("i", U_Clip("SUG skip " + GSIndustry.GetName(src) + ": built on water, rail cannot reach it"));
      continue;
    }
    local prod = GSCargoList_IndustryProducing(src);
    for (local c = prod.Begin(); !prod.IsEnd(); c = prod.Next()) {
      local made = GSIndustry.GetLastMonthProduction(src, c);
      local pct = GSIndustry.GetLastMonthTransportedPercentage(src, c);
      // what others (and we) carry already is not free for a new line
      local avail = made * (100 - pct) / 100;
      if (made < 10 || avail < 10) {
        n_low++;
        U_Log("i", U_Clip("SUG skip " + GSIndustry.GetName(src) + " " + GSCargo.GetName(c) + ": made " + made + ", carried " + pct + "%"));
        continue;
      }
      scanned++;
      // train for this cargo: the fast engine and wagons to fill the platform
      if (!wagon_cache.rawin(c)) wagon_cache.rawset(c, Adv_Wagon(c, rail, speed));
      local wagon = wagon_cache.rawget(c);
      if (wagon < 0) {
        n_nowagon++;
        U_Log("i", U_Clip("SUG skip " + GSIndustry.GetName(src) + " " + GSCargo.GetName(c) + ": no wagon for this cargo"));
        continue;
      }
      local nw = max(1, slen * 2 - 1);
      t.cap = nw * GSEngine.GetCapacity(wagon);
      t.train_price = GSEngine.GetPrice(loco) + nw * GSEngine.GetPrice(wagon);
      if (!acc_cache.rawin(c)) {
        local l = [];
        local acc = GSIndustryList_CargoAccepting(c);
        for (local a = acc.Begin(); !acc.IsEnd(); a = acc.Next()) l.append(a);
        acc_cache.rawset(c, l);
      }
      // the best destination for this source and cargo
      local top = null;
      foreach (dst in acc_cache.rawget(c)) {
        if (dst == src || GSIndustry.IsBuiltOnWater(dst)) continue;
        local e = Sug_Estimate(t, src, dst, c, avail);
        if (e != null && (top == null || e.payback < top.payback)) top = e;
      }
      if (top != null) {
        best.append(top);
        U_Log("i", U_Clip("SUG " + GSIndustry.GetName(src) + " " + GSCargo.GetName(c) + " " + avail + "/month free -> " +
              GSIndustry.GetName(top.dst) + " " + top.dist + " tiles (of " + acc_cache.rawget(c).len() + " acceptors), " +
              top.trains + " train(s), " + top.days + " days (fill " + top.fill + "), cost " + top.cost + ", income " + top.income + ", profit " + top.profit + "/year, payback " + top.payback + " months"));
      } else {
        n_nodst++;
        U_Log("i", U_Clip("SUG skip " + GSIndustry.GetName(src) + " " + GSCargo.GetName(c) + " " + avail + "/month: no paying destination " +
              SUG_MIN_DIST + ".." + t.max_dist + " tiles away (of " + acc_cache.rawget(c).len() + " acceptors)"));
      }
    }
  }
  U_Log("i", "SUG summary: " + n_ind + " industries, " + scanned + " sources used, skipped: " + n_low + " too little cargo, " +
        n_nowagon + " no wagon, " + n_nodst + " no paying destination; " + best.len() + " routes");
  best.sort(function(a, b) { return a.payback < b.payback ? -1 : (a.payback > b.payback ? 1 : 0); });

  // remembered for the Plan buttons (not saved: after loading press Suggest again)
  if (self.sugs == null) self.sugs = {};
  local keep = [];
  for (local i = 0; i < SUG_LINES && i < best.len(); i++) keep.append({ src = best[i].src, dst = best[i].dst, text = "Estimate: profit ~" + Sug_Money(best[i].profit) +
    "/year (income ~" + Sug_Money(best[i].income) + ", running ~" + Sug_Money(best[i].run) + "), build ~" + Sug_Money(best[i].cost) +
    ", pays back in " + best[i].payback + " months." });
  self.sugs.rawset(company, keep);
  local bank = GSCompany.GetBankBalance(company);
  for (local i = 0; i < SUG_LINES; i++) {
    if (i >= best.len()) {
      UI_SetText(self, company, "s" + i, " ");
      UI_SetText(self, company, "sd" + i, " ");
      continue;
    }
    local e = best[i];
    local years = e.payback / 12, months = e.payback % 12;
    // line 1: what and where, line 2: the money (two lines: one is cut at 250 bytes)
    local text = (i + 1) + ". " + GSCargo.GetName(e.cargo) + ": " + GSIndustry.GetName(e.src) + " -> " + GSIndustry.GetName(e.dst) +
                 ", " + e.dist + " tiles. Profit ~" + Sug_Money(e.profit) + "/year, pays back in " +
                 (years > 0 ? years + "y " : "") + months + "m" + (e.cost > bank ? " (too expensive now)" : "") + ".";
    local det = "Income ~" + Sug_Money(e.income) + "/year (" + e.month + "/month x " + e.per_unit + " per unit), running costs ~" +
                Sug_Money(e.run) + "/year. Build ~" + Sug_Money(e.cost) + " = track " + Sug_Money(e.c_track) + " + stations " +
                Sug_Money(e.c_st) + " + " + e.trains + " train(s) " + Sug_Money(e.c_train) + ". ~" + e.days + " days on the way (" +
                e.one_way + " travel + " + (e.fill / 2) + " loading).";
    UI_SetText(self, company, "sd" + i, det);
    UI_SetText(self, company, "s" + i, text);
  }
  local when = GSDate.GetCurrentDate();
  local status = "Scanned " + scanned + " cargo sources, " + best.len() + " routes can pay. " +
                 "Date " + GSDate.GetDayOfMonth(when) + "." + GSDate.GetMonth(when) + "." + GSDate.GetYear(when) +
                 ". Rough estimate with " + GSEngine.GetName(loco) + "; press Suggest again for fresh numbers.";
  if (best.len() == 0) status = "Scanned " + scanned + " cargo sources: no route " + SUG_MIN_DIST + ".." + t.max_dist + " tiles away can pay right now.";
  UI_SetText(self, company, "s_status", status);
  U_Log("i", U_Clip("[" + company + "] suggestions: " + best.len() + " routes, best payback " + (best.len() > 0 ? best[0].payback + " months" : "-")));
}

/* Plan #N button: puts the suggestion into A and B (rail) and plans it. */
function Sug_Plan(self, company, i)
{
  if (self.sugs == null || !self.sugs.rawin(company) || i >= self.sugs.rawget(company).len()) {
    UI_SetText(self, company, "s_status", "No suggestion #" + (i + 1) + " yet: press Suggest first.");
    return;
  }
  local sg = self.sugs.rawget(company)[i];
  if (!GSIndustry.IsValidIndustry(sg.src) || !GSIndustry.IsValidIndustry(sg.dst)) {
    UI_SetText(self, company, "s_status", "Suggestion #" + (i + 1) + " is gone (an industry closed). Press Suggest again.");
    return;
  }
  local p = UI_Pick(self, company);
  p.a = { kind = "industry", id = sg.src };
  p.b = { kind = "industry", id = sg.dst };
  p.mode = MODE_RAIL;
  p.list = [];
  UI_Selection(self, company);
  U_Log("i", U_Clip("SUG [" + company + "] Plan #" + (i + 1) + ": " + GSIndustry.GetName(sg.src) + " -> " + GSIndustry.GetName(sg.dst)));
  UI_SetText(self, company, "s_status", U_Clip("Planning #" + (i + 1) + " " + GSIndustry.GetName(sg.src) + " -> " +
             GSIndustry.GetName(sg.dst) + ": see the Build assistant page (exact cost, preview, Build)."));
  self.OnButton(company, "plan");
  UI_Diag(self, company, "i", U_Clip("Suggestion #" + (i + 1) + " " + GSIndustry.GetName(sg.src) + " -> " + GSIndustry.GetName(sg.dst) + ". " + sg.text));
  // show the build page, where the plan and the Build button are
  try {
    local page = self.pages.rawget(company).page;
    if (GSStoryPage.IsValidStoryPage(page)) GSStoryPage.Show(page);
  } catch (e) {}
}
