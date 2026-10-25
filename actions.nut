/* Build actions: small tables that can be run, tested (cost estimate)
 * and saved with the game. Each returns true on success. */

function Act_Run(job, a)
{
  local op = a.op;
  if (op == "road") {
    if (GSRoad.AreRoadTilesConnected(a.a, a.b)) return true;
    return GSRoad.BuildRoad(a.a, a.b) || GSError.GetLastError() == GSError.ERR_ALREADY_BUILT;
  }
  if (op == "road_bridge") return a.id >= 0 && GSBridge.BuildBridge(GSVehicle.VT_ROAD, a.id, a.a, a.b);
  if (op == "road_tunnel") return GSTunnel.BuildTunnel(GSVehicle.VT_ROAD, a.a);
  if (op == "bus_stop") return BuildRoad_BusStop(a.town) != "failed";
  if (op == "truck_stop") {
    if (!GSRoad.BuildDriveThroughRoadStation(a.s, a.f, GSRoad.ROADVEHTYPE_TRUCK, GSStation.STATION_NEW)) return false;
    GSRoad.BuildRoad(a.f, a.s);
    if (a.e >= 0) GSRoad.BuildRoad(a.s, a.e);
    return true;
  }
  if (op == "road_depot") {
    local d = BuildRoad_DepotClosest(a.center, null, 8);
    if (d >= 0) job.depot_tile = d;
    return d >= 0;
  }
  if (op == "rail") return GSRail.BuildRail(a.p, a.t, a.n) || GSError.GetLastError() == GSError.ERR_ALREADY_BUILT;
  if (op == "rail_bridge") return a.id >= 0 && GSBridge.BuildBridge(GSVehicle.VT_RAIL, a.id, a.a, a.b);
  if (op == "rail_tunnel") return GSTunnel.BuildTunnel(GSVehicle.VT_RAIL, a.a);
  if (op == "rail_station") return GSRail.BuildRailStation(a.tile, a.axis, a.plat, a.len, GSStation.STATION_JOIN_ADJACENT);
  if (op == "level") return GSTile.LevelTiles(a.a, a.b) || GSError.GetLastError() == GSError.ERR_ALREADY_BUILT;
  if (op == "rail_depot_end") {
    // behind the station, in line with platform 0; if that tile is taken, beside the line
    local d = -1;
    if (a.tile >= 0 && GSRail.BuildRailDepot(a.tile, a.front)) d = a.tile;
    if (d < 0) d = BuildRail_DepotOnLine(a.tiles);
    if (d >= 0) job.depot_tile = d;
    return d >= 0;
  }
  if (op == "rail_depot") {
    local d = BuildRail_DepotOnLine(a.tiles);
    if (d >= 0) job.depot_tile = d;
    return d >= 0;
  }
  if (op == "vehicles") {
    if (a.resolve) {
      // town centres -> own bus stops there
      local stops = [];
      foreach (p in a.stops) {
        local s = Veh_StopNear(p, GSStation.STATION_BUS_STOP, 8);
        if (s >= 0) stops.append(s);
      }
      a.stops = stops;
      a.resolve = false;
      if (stops.len() < 2) { job.veh_text = " Vehicles: bus stops not found."; return true; }
    }
    // depot: built by this job, given by an earlier leg, or the nearest own one
    local depot = a.depot >= 0 ? a.depot : job.depot_tile;
    if (depot < 0) depot = Veh_FindDepot(a.stops[0], a.kind == "rail" ? a.rail : -1, 30);
    job.veh_text = Veh_Buy(a, depot);
    return true;
  }
  if (op == "signal") {
    local type = (a.rawin("kind") && a.kind == "twoway") ? GSRail.SIGNALTYPE_PBS : GSRail.SIGNALTYPE_PBS_ONEWAY;
    if (GSRail.GetSignalType(a.t, a.f) == type) return true;
    return GSRail.BuildSignal(a.t, a.f, type);
  }
  U_Log("w", "Unknown action " + op);
  return false;
}

/* Cost of all actions in test mode. Depots and signals depend on track that
 * does not exist yet, so they are left out of the estimate. */
function Act_Estimate(job, actions)
{
  local tm = GSTestMode();
  local acc = GSAccounting();
  job.est_nocash <- 0;
  job.est_fail <- 0;
  foreach (a in actions) {
    if (a.op == "rail_depot" || a.op == "rail_depot_end" || a.op == "road_depot" || a.op == "signal" || a.op == "vehicles") continue;
    if (!Act_Run(job, a)) {
      // the test run also checks money: such pieces are missing from the sum
      if (GSError.GetLastError() == GSError.ERR_NOT_ENOUGH_CASH) job.est_nocash++;
      else job.est_fail++;
    }
  }
  return acc.GetCosts();
}

function Act_Describe(a)
{
  if (a.rawin("t")) return a.op + " at " + a.t;
  if (a.rawin("a")) return a.op + " at " + a.a;
  if (a.rawin("s")) return a.op + " at " + a.s;
  if (a.rawin("tile")) return a.op + " at " + a.tile;
  return a.op;
}
