/* Ship lines (step 1): from an industry on water (oil rig) to an industry
 * that accepts its cargo near the coast.
 *   source      the oil rig's own dock (built into the rig)
 *   destination a new dock that reaches the accepting industry
 *   check       a search over water tiles: both docks on the same water
 *   then        a ship depot in the water near the new dock, ships, orders
 * Ships find their own way on water, so nothing is built between the ends.
 * "Ship: plan" shows the result and the cost, "Ship: build" builds it.
 * Must run inside a GSCompanyMode. */

/* Water tiles a ship can stand on next to tile t (up to 2 tiles away). */
function Ship_WaterAround(t)
{
  local out = [];
  local list = U_TilesAround(t, 2);
  for (local x = list.Begin(); !list.IsEnd(); x = list.Next()) {
    if (GSTile.IsWaterTile(x) && !GSMarine.IsDockTile(x) && !GSMarine.IsWaterDepotTile(x)) out.append(x);
  }
  return out;
}

/* Can a dock be built on tile t? (test mode: nothing is built) */
function Ship_DockOk(t)
{
  local tm = GSTestMode();
  return GSMarine.BuildDock(t, GSStation.STATION_NEW);
}

/* Dock places that reach industry ind (accepting), nearest to tile `toward`
 * first. Returns up to `max` tiles. */
function Ship_DockPlaces(ind, toward, max)
{
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_DOCK);
  local list = GSTileList_IndustryAccepting(ind, radius);
  list.Valuate(GSMap.DistanceManhattan, toward);
  list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
  local out = [];
  for (local t = list.Begin(); !list.IsEnd() && out.len() < max; t = list.Next()) {
    if (GSTile.GetSlope(t) == GSTile.SLOPE_FLAT) continue;   // a dock stands on a coast slope
    if (Ship_DockOk(t)) out.append(t);
  }
  return out;
}

/* Search over water from the tiles in `from` to any tile in `to` (a table).
 * Returns the number of tiles examined when found, or -1. */
function Ship_WaterSearch(from, to, goal_tile)
{
  local ctx = { to = to, goal = goal_tile };
  local nb = function(ctx, t, kind) {
    local out = [];
    foreach (n in U_Neighbours(t)) {
      if (ctx.to.rawin(n) || (GSTile.IsWaterTile(n) && !GSMarine.IsWaterDepotTile(n))) out.append([n, 1, 0]);
    }
    return out;
  };
  local goal = function(ctx, t, kind) { return ctx.to.rawin(t); };
  local h = function(ctx, t) { return GSMap.DistanceManhattan(t, ctx.goal); };
  local a = AStar(ctx, from, nb, goal, h, 300000);
  while (true) {
    local r = a.Step(5000);
    if (r == 1) return a.examined;
    if (r < 0) return -1;
  }
}

/* Best ship for the cargo: most capacity x speed. Returns -1 if none. */
function Ship_Engine(cargo)
{
  local best = -1, best_v = -1;
  local list = GSEngineList(GSVehicle.VT_WATER);
  for (local e = list.Begin(); !list.IsEnd(); e = list.Next()) {
    if (!GSEngine.IsBuildable(e)) continue;
    if (GSEngine.GetCargoType(e) != cargo && !GSEngine.CanRefitCargo(e, cargo)) continue;
    local v = GSEngine.GetCapacity(e) * GSEngine.GetMaxSpeed(e);
    if (v > best_v) { best = e; best_v = v; }
  }
  return best;
}

/* Plans a ship line from a to b. Returns { ok, text, ... }. */
function Ship_Plan(a, b)
{
  if (a == null || b == null || a.kind != "industry" || b.kind != "industry")
    return { ok = false, text = "Ship: pick A = an oil rig (or another industry on water) and B = the industry that takes its cargo." };
  local src = a.id, dst = b.id;
  if (!GSIndustry.IsBuiltOnWater(src) && GSIndustry.IsBuiltOnWater(dst)) { local x = src; src = dst; dst = x; }
  if (!GSIndustry.HasDock(src))
    return { ok = false, text = "Ship: " + GSIndustry.GetName(src) + " has no dock of its own. For now ships run only from oil rigs." };
  // the cargo: something the rig makes and the other end takes
  local cargo = -1;
  local prod = GSCargoList_IndustryProducing(src);
  local acc = GSCargoList_IndustryAccepting(dst);
  for (local c = prod.Begin(); !prod.IsEnd(); c = prod.Next()) if (acc.HasItem(c)) { cargo = c; break; }
  if (cargo < 0)
    return { ok = false, text = "Ship: " + GSIndustry.GetName(dst) + " does not take what " + GSIndustry.GetName(src) + " produces." };
  local rig = GSIndustry.GetDockLocation(src);
  local start = Ship_WaterAround(rig);
  if (start.len() == 0) return { ok = false, text = "Ship: no open water next to the dock of " + GSIndustry.GetName(src) + "." };

  local places = Ship_DockPlaces(dst, rig, 8);
  U_Log("i", "SHIP " + GSIndustry.GetName(src) + " -> " + GSIndustry.GetName(dst) + ": " + places.len() + " dock place(s) near the destination");
  if (places.len() == 0)
    return { ok = false, text = "Ship: no place for a dock near " + GSIndustry.GetName(dst) + " (a dock needs a straight coast slope within reach of the industry)." };
  // the first dock place that the water from the rig reaches
  foreach (d in places) {
    local to = {};
    foreach (w in Ship_WaterAround(d)) to.rawset(w, true);
    if (to.len() == 0) continue;
    local n = Ship_WaterSearch(start, to, d);
    U_Log("i", "SHIP dock place " + GSMap.GetTileX(d) + "," + GSMap.GetTileY(d) + ": " + (n < 0 ? "not reachable by water" : "reachable, " + n + " water tiles examined"));
    if (n < 0) continue;
    local engine = Ship_Engine(cargo);
    if (engine < 0) return { ok = false, text = "Ship: no ship can carry " + GSCargo.GetName(cargo) + " yet." };
    // ships: one per ~a month of production, 1..3
    local made = GSIndustry.GetLastMonthProduction(src, cargo);
    local count = max(1, min(3, (made * 7 / 10 + GSEngine.GetCapacity(engine) - 1) / max(1, GSEngine.GetCapacity(engine))));
    local cost = GSMarine.GetBuildCost(GSMarine.BT_DOCK) + GSMarine.GetBuildCost(GSMarine.BT_DEPOT) + count * GSEngine.GetPrice(engine);
    local text = "Ship: " + GSIndustry.GetName(src) + " -> " + GSIndustry.GetName(dst) + ", " + GSCargo.GetName(cargo) + " " + made +
                 "/month, " + GSMap.DistanceManhattan(rig, d) + " tiles by water. New dock + depot, " + count + "x " + GSEngine.GetName(engine) +
                 ". Cost about " + cost + ". Press Ship: build.";
    return { ok = true, text = text, src = src, dst = dst, cargo = cargo, rig = rig, dock = d, engine = engine, count = count, cost = cost };
  }
  return { ok = false, text = "Ship: no dock place near " + GSIndustry.GetName(dst) + " is on the same water as " + GSIndustry.GetName(src) + "." };
}

/* Ship depot in open water near tile t. Returns the depot tile or -1. */
function Ship_Depot(t)
{
  local list = U_TilesAround(t, 6);
  list.Valuate(GSMap.DistanceManhattan, t);
  list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
  for (local x = list.Begin(); !list.IsEnd(); x = list.Next()) {
    if (GSMap.DistanceManhattan(x, t) < 3 || !GSTile.IsWaterTile(x)) continue;
    foreach (f in U_Neighbours(x)) {
      if (!GSTile.IsWaterTile(f)) continue;
      if (GSMarine.BuildWaterDepot(x, f)) return x;
    }
  }
  return -1;
}

/* Builds a planned ship line. Returns a text for the Story Book. */
function Ship_Build(plan)
{
  local bank = GSCompany.GetBankBalance(GSCompany.COMPANY_SELF);
  if (plan.cost > bank) return "Ship: not enough money (about " + plan.cost + " needed, you have " + bank + ").";
  if (!GSIndustry.IsValidIndustry(plan.src) || !GSIndustry.IsValidIndustry(plan.dst)) return "Ship: an industry of the plan is gone. Plan again.";
  if (!GSMarine.IsDockTile(plan.dock) && !GSMarine.BuildDock(plan.dock, GSStation.STATION_NEW))
    return "Ship: could not build the dock (" + GSError.GetLastErrorString() + "). Plan again.";
  local depot = Ship_Depot(plan.dock);
  if (depot < 0) return "Ship: dock built, but no place for a ship depot near it.";
  local bought = 0, why = "";
  for (local i = 0; i < plan.count; i++) {
    local v = GSVehicle.BuildVehicle(depot, plan.engine);
    if (!GSVehicle.IsValidVehicle(v)) { why = GSError.GetLastErrorString(); break; }
    if (GSEngine.GetCargoType(plan.engine) != plan.cargo) GSVehicle.RefitVehicle(v, plan.cargo);
    GSOrder.AppendOrder(v, plan.rig, GSOrder.OF_FULL_LOAD_ANY);
    GSOrder.AppendOrder(v, plan.dock, GSOrder.OF_NONE);
    GSVehicle.StartStopVehicle(v);
    bought++;
  }
  local text = "Ship line " + GSIndustry.GetName(plan.src) + " -> " + GSIndustry.GetName(plan.dst) + " built: dock, depot, " +
               bought + "x " + GSEngine.GetName(plan.engine) + (bought < plan.count ? " (could not buy more: " + why + ")" : "") + ".";
  U_Log("i", U_Clip("SHIP " + text));
  return text;
}
