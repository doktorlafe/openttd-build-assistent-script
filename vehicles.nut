/* Buying vehicles and giving them orders. Must run inside a GSCompanyMode.
 * The first vehicle gets the orders, the others are clones that share them. */

/* Nearest own depot for road (rail = -1) or for the rail type, or -1. */
function Veh_FindDepot(near, rail, dist)
{
  local list = GSDepotList(rail >= 0 ? GSTile.TRANSPORT_RAIL : GSTile.TRANSPORT_ROAD);
  local best = -1, best_d = dist + 1;
  for (local d = list.Begin(); !list.IsEnd(); d = list.Next()) {
    if (rail >= 0 && GSRail.GetRailType(d) != rail) continue;
    local dd = GSMap.DistanceManhattan(d, near);
    if (dd < best_d) { best = d; best_d = dd; }
  }
  return best;
}

/* Own station of a type near a tile: a tile of it, or -1. */
function Veh_StopNear(center, type, dist)
{
  local list = GSStationList(type);
  local best = -1, best_d = dist + 1;
  for (local s = list.Begin(); !list.IsEnd(); s = list.Next()) {
    local loc = GSStation.GetLocation(s);
    local dd = GSMap.DistanceManhattan(loc, center);
    if (dd < best_d) { best = loc; best_d = dd; }
  }
  return best;
}

/* Builds an engine, refitted to cargo when it cannot carry it as it is. */
function Veh_Build(depot, engine, cargo)
{
  if (cargo >= 0 && GSEngine.GetCargoType(engine) != cargo && GSEngine.CanRefitCargo(engine, cargo))
    return GSVehicle.BuildVehicleWithRefit(depot, engine, cargo);
  return GSVehicle.BuildVehicle(depot, engine);
}

/* Best road vehicle for cargo on the current road type: capacity x speed. */
function Veh_RoadEngine(cargo)
{
  local rt = GSRoad.GetCurrentRoadType();
  local best = -1, best_v = -1;
  local list = GSEngineList(GSVehicle.VT_ROAD);
  for (local e = list.Begin(); !list.IsEnd(); e = list.Next()) {
    if (!GSEngine.IsBuildable(e) || !GSEngine.HasPowerOnRoad(e, rt)) continue;
    if (!Adv_Carries(e, cargo)) continue;
    local v = max(1, GSEngine.GetCapacity(e)) * max(1, GSEngine.GetMaxSpeed(e));
    if (v > best_v) { best = e; best_v = v; }
  }
  return best;
}

/* A train: the first advised engine and as many wagons as fit the platform.
 * The real length is checked after building (works with NewGRF vehicles too). */
function Veh_Train(depot, rail, cargo, plat_len)
{
  local locos = Adv_Locos(rail);
  if (locos.len() == 0) return [-1, "no locomotive for this rail type"];
  local loco = locos[0].loco;
  local wagon = Adv_Wagon(cargo, rail, GSEngine.GetMaxSpeed(loco));
  if (wagon < 0) return [-1, "no wagon for " + GSCargo.GetName(cargo)];
  local v = GSVehicle.BuildVehicle(depot, loco);
  if (!GSVehicle.IsValidVehicle(v)) return [-1, GSError.GetLastErrorString()];
  local max_len = plat_len * 16;   // vehicle length is in 1/16 of a tile
  for (local i = 0; i < plat_len * 2; i++) {
    local w = Veh_Build(depot, wagon, cargo);
    if (!GSVehicle.IsValidVehicle(w)) break;
    if (!GSVehicle.MoveWagon(w, 0, v, GSVehicle.GetNumWagons(v) - 1)) {
      GSVehicle.SellVehicle(w);
      break;
    }
    if (GSVehicle.GetLength(v) > max_len) {
      GSVehicle.SellWagon(v, GSVehicle.GetNumWagons(v) - 1);
      break;
    }
  }
  return [v, ""];
}

/* Orders: stops in the given order, full load at the first one if asked. */
function Veh_Orders(v, stops, full_first)
{
  for (local i = 0; i < stops.len(); i++) {
    local flags = (i == 0 && full_first) ? GSOrder.OF_FULL_LOAD_ANY : GSOrder.OF_NONE;
    if (!GSOrder.AppendOrder(v, stops[i], flags)) {
      GSLog.Warning("Order to " + stops[i] + " failed: " + GSError.GetLastErrorString());
      return false;
    }
  }
  return true;
}

/* Buys `count` vehicles. a = { kind = "rail" | "road", stops, cargo, full,
 * count, depot, rail, plat_len }. Returns a short text for the Story Book. */
function Veh_Buy(a, depot)
{
  if (a.count <= 0) return "";
  if (depot < 0) return " Vehicles: no depot found.";
  if (a.stops.len() < 2) return " Vehicles: stations not found.";
  local first = -1, why = "";
  if (a.kind == "rail") {
    local r = Veh_Train(depot, a.rail, a.cargo, a.plat_len);
    first = r[0];
    why = r[1];
  } else {
    local e = Veh_RoadEngine(a.cargo);
    if (e < 0) return " Vehicles: no road vehicle for " + GSCargo.GetName(a.cargo) + ".";
    first = Veh_Build(depot, e, a.cargo);
    if (!GSVehicle.IsValidVehicle(first)) why = GSError.GetLastErrorString();
  }
  if (!GSVehicle.IsValidVehicle(first)) return " Vehicles: could not buy (" + why + ").";
  if (!Veh_Orders(first, a.stops, a.full)) {
    GSVehicle.SellVehicle(first);
    return " Vehicles: orders failed.";
  }
  GSVehicle.StartStopVehicle(first);
  local n = 1;
  for (local i = 1; i < a.count; i++) {
    local c = GSVehicle.CloneVehicle(depot, first, true);
    if (!GSVehicle.IsValidVehicle(c)) break;
    GSVehicle.StartStopVehicle(c);
    n++;
  }
  local text = " Bought " + n + "x " + GSEngine.GetName(GSVehicle.GetEngineType(first));
  if (a.kind == "rail") text += " with " + (GSVehicle.GetNumWagons(first) - 1) + " wagons";
  return text + ".";
}
