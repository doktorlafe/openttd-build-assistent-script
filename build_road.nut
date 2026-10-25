/* Road building helpers. All of them must run inside a GSCompanyMode. */

/* Picks a road type the company can use. Returns the type or -1. */
function BuildRoad_SelectType()
{
  local list = GSRoadTypeList(GSRoad.ROADTRAMTYPES_ROAD);
  for (local rt = list.Begin(); !list.IsEnd(); rt = list.Next()) {
    if (GSRoad.IsRoadTypeAvailable(rt)) {
      GSRoad.SetCurrentRoadType(rt);
      return rt;
    }
  }
  return -1;
}

function BuildRoad_HasBusStopNear(center, dist)
{
  local list = GSStationList(GSStation.STATION_BUS_STOP);
  for (local s = list.Begin(); !list.IsEnd(); s = list.Next()) {
    if (GSMap.DistanceManhattan(GSStation.GetLocation(s), center) <= dist) return true;
  }
  return false;
}

/* Drive-through bus stop on a straight piece of road near the town centre.
 * Returns "built", "exists" or "failed". */
function BuildRoad_BusStop(town)
{
  local center = GSTown.GetLocation(town);
  if (BuildRoad_HasBusStopNear(center, 6)) return "exists";
  local tiles = U_TilesAround(center, 6);
  for (local t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
    if (!GSRoad.IsRoadTile(t) || GSRoad.IsRoadStationTile(t) || U_IsSpecial(t) || !U_IsFlat(t)) continue;
    local c = [];
    for (local i = 0; i < 4; i++) {
      local n = U_Step(t, i);
      c.append(n >= 0 && GSRoad.AreRoadTilesConnected(t, n));
    }
    local front = -1;
    if (c[0] && c[2] && !c[1] && !c[3]) front = U_Step(t, 0);
    else if (c[1] && c[3] && !c[0] && !c[2]) front = U_Step(t, 1);
    if (front == -1) continue;
    if (GSRoad.BuildDriveThroughRoadStation(t, front, GSRoad.ROADVEHTYPE_BUS, GSStation.STATION_NEW)) return "built";
  }
  return "failed";
}

/* Road depot next to a road near center. Returns true on success. */
function BuildRoad_DepotNear(center)
{
  return BuildRoad_DepotClosest(center, null, 8) >= 0;
}

/* Own road depot within dist of center, or -1. */
function BuildRoad_OwnDepotNear(center, dist)
{
  local list = GSDepotList(GSTile.TRANSPORT_ROAD);
  for (local d = list.Begin(); !list.IsEnd(); d = list.Next()) {
    if (GSMap.DistanceManhattan(d, center) <= dist) return d;
  }
  return -1;
}

/* Depot as close to center as possible, next to a road tile.
 * reach (optional) = road tiles it must connect to. Flat land first, then
 * gentle slopes. Returns the depot tile or -1. */
function BuildRoad_DepotClosest(center, reach, radius)
{
  local tiles = U_TilesAround(center, radius);
  foreach (flat_only in [true, false]) {
    for (local t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
      if (!GSRoad.IsRoadTile(t) || GSRoad.IsRoadStationTile(t) || GSRoad.IsRoadDepotTile(t) || U_IsSpecial(t)) continue;
      if (reach != null && !reach.rawin(t)) continue;
      foreach (d in U_Neighbours(t)) {
        if (!GSTile.IsBuildable(d)) continue;
        if (flat_only && !U_IsFlat(d)) continue;
        if (GSRoad.BuildRoadDepot(d, t)) {
          GSRoad.BuildRoad(d, t);
          return d;
        }
      }
    }
  }
  return -1;
}

/* Place for a truck stop: stop tile s, front tile f (where the road comes in)
 * and an optional tile e behind it where trucks can turn around.
 * Returns { s, f, e } or null. */
function BuildRoad_FindTruckSpot(e, role, cargo, other, blocked)
{
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRUCK_STOP);
  local tiles = Tg_Candidates(e, role, radius, other);
  local tried = 0;
  for (local s = tiles.Begin(); !tiles.IsEnd() && tried < 400; s = tiles.Next()) {
    tried++;
    if (tried % 40 == 0) U_Report(tried * 100 / 400);
    if (blocked.rawin(s) || !GSTile.IsBuildable(s) || !U_IsFlat(s)) continue;
    if (!Tg_SpotOk(e, role, cargo, s, 1, 1, radius)) continue;
    // try the side facing the other end first
    foreach (i in U_DirsToward(s, other)) {
      local f = U_Step(s, i);
      if (f < 0 || blocked.rawin(f)) continue;
      local road_ok = GSRoad.IsRoadTile(f) && !GSRoad.IsRoadStationTile(f) && !U_IsSpecial(f);
      if (!road_ok && !(GSTile.IsBuildable(f) && U_IsFlat(f))) continue;
      local back = U_Step(s, (i + 2) % 4);
      local back_ok = back >= 0 && !blocked.rawin(back) && GSTile.IsBuildable(back) && U_IsFlat(back);
      local tm = GSTestMode();
      if (!GSRoad.BuildDriveThroughRoadStation(s, f, GSRoad.ROADVEHTYPE_TRUCK, GSStation.STATION_NEW)) {
        U_NoCash();
        continue;
      }
      return { s = s, f = f, e = back_ok ? back : -1 };
    }
  }
  return null;
}
