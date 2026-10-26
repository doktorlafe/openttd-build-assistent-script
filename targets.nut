/* Endpoints of a route: a town or an industry.
 * An endpoint is a table { kind = "town" | "industry", id = ... }. */

/* Industry within 4 tiles of the click, otherwise the nearest town. */
function Tg_FromTile(tile)
{
  local list = GSIndustryList();
  if (!list.IsEmpty()) {
    list.Valuate(GSIndustry.GetDistanceManhattanToTile, tile);
    list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
    local ind = list.Begin();
    if (list.GetValue(ind) <= 4) return { kind = "industry", id = ind };
  }
  local town = GSTile.GetClosestTown(tile);
  if (GSTown.IsValidTown(town)) return { kind = "town", id = town };
  return null;
}

function Tg_Valid(e)
{
  if (e == null) return false;
  if (e.kind == "station") return GSStation.IsValidStation(e.id);
  return e.kind == "town" ? GSTown.IsValidTown(e.id) : GSIndustry.IsValidIndustry(e.id);
}

function Tg_Name(e)
{
  if (!Tg_Valid(e)) return "?";
  if (e.kind == "station") return GSStation.GetName(e.id);
  return e.kind == "town" ? GSTown.GetName(e.id) : GSIndustry.GetName(e.id);
}

function Tg_Center(e)
{
  if (e.kind == "town") return GSTown.GetLocation(e.id);
  if (e.kind == "station") return GSStation.GetLocation(e.id);
  local t = GSIndustry.GetLocation(e.id);
  return GSMap.GetTileIndex(GSMap.GetTileX(t) + 1, GSMap.GetTileY(t) + 1);
}

function Tg_Passengers()
{
  local list = GSCargoList();
  for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
    if (GSCargo.HasCargoClass(c, GSCargo.CC_PASSENGERS)) return c;
  }
  return -1;
}

function Tg_Mail()
{
  local list = GSCargoList();
  for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
    if (GSCargo.HasCargoClass(c, GSCargo.CC_MAIL)) return c;
  }
  return -1;
}

function Tg_Accepts(e, c)
{
  if (e.kind == "industry") return GSCargoList_IndustryAccepting(e.id).HasItem(c);
  return GSTile.GetCargoAcceptance(Tg_Center(e), c, 1, 1, 6) >= 8;
}

/* What goes where. Returns { from, to, cargo, pax } or null.
 * Two towns = passengers. Otherwise a cargo that one end produces and the other accepts. */
function Tg_Link(a, b)
{
  if (a.kind == "town" && b.kind == "town") {
    local p = Tg_Passengers();
    return p < 0 ? null : { from = a, to = b, cargo = p, pax = true };
  }
  if (a.kind == "industry") {
    local list = GSCargoList_IndustryProducing(a.id);
    for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
      if (Tg_Accepts(b, c)) return { from = a, to = b, cargo = c, pax = false };
    }
  }
  if (b.kind == "industry") {
    local list = GSCargoList_IndustryProducing(b.id);
    for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
      if (Tg_Accepts(a, c)) return { from = b, to = a, cargo = c, pax = false };
    }
  }
  return null;
}

/* Does a station rectangle at tile serve this endpoint in its role? */
function Tg_SpotOk(e, role, cargo, tile, w, h, radius)
{
  // a transfer hub: the place must be part of that station
  if (e.kind == "station") return GSRail.IsRailStationTile(tile) && GSStation.GetStationID(tile) == e.id;
  if (e.kind == "industry" && role == "from") return GSTile.GetCargoProduction(tile, cargo, w, h, radius) > 0;
  return GSTile.GetCargoAcceptance(tile, cargo, w, h, radius) >= 8;
}

/* Transfer hub for cargo from a to b (Transfer on): the own station nearest
 * to a from which an own train already carries a cargo of a to a station
 * that accepts it at b. Cargo dropped there travels on with that train.
 * Returns { hub, cargo, pax, trains, dest } or null. Needs a GSCompanyMode. */
function Tg_FindHub(a, b, max_dist)
{
  local cargos = [];
  if (a.kind == "industry") {
    local l = GSCargoList_IndustryProducing(a.id);
    for (local c = l.Begin(); !l.IsEnd(); c = l.Next()) cargos.append(c);
  } else if (a.kind == "town") {
    local p = Tg_Passengers();
    if (p >= 0) cargos.append(p);
  }
  if (cargos.len() == 0) return null;
  local ca = Tg_Center(a), cb = Tg_Center(b);
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  // the nearest hub wins, even when it is not closer than b itself (you asked
  // for a transfer); only the feeder has to fit max_dist
  local best = null, best_d = max_dist + 1;
  ::g_hubinfo = { carry = 0, to_b = 0, hubs = 0 };   // what was checked, for the Log
  local vl = GSVehicleList();
  for (local v = vl.Begin(); !vl.IsEnd(); v = vl.Next()) {
    if (GSVehicle.GetVehicleType(v) != GSVehicle.VT_RAIL) continue;
    foreach (c in cargos) {
      if (GSVehicle.GetCapacity(v, c) <= 0) continue;
      ::g_hubinfo.carry++;
      // the stations of its orders
      local st = [];
      for (local i = 0; i < GSOrder.GetOrderCount(v); i++) {
        if (!GSOrder.IsGotoStationOrder(v, i)) continue;
        local tile = GSOrder.GetOrderDestination(v, i);
        st.append({ sid = GSStation.GetStationID(tile), tile = tile, flags = GSOrder.GetOrderFlags(v, i) });
      }
      // does it go to a station near b that accepts the cargo (whole station)?
      local dest = -1;
      foreach (o in st) {
        if (GSMap.DistanceManhattan(GSStation.GetLocation(o.sid), cb) <= 30 &&
            GSCargoList_StationAccepting(o.sid).HasItem(c)) { dest = o.sid; break; }
      }
      if (dest < 0) continue;
      ::g_hubinfo.to_b++;
      foreach (o in st) {
        if (o.sid == dest || (o.flags & GSOrder.OF_NO_LOAD) != 0) continue;
        if (!GSStation.HasStationType(o.sid, GSStation.STATION_TRAIN)) continue;
        ::g_hubinfo.hubs++;
        local d = GSMap.DistanceManhattan(ca, GSStation.GetLocation(o.sid));
        if (d >= best_d) continue;
        best_d = d;
        best = { hub = o.sid, cargo = c, pax = GSCargo.HasCargoClass(c, GSCargo.CC_PASSENGERS), trains = 0, dest = dest };
      }
    }
  }
  if (best == null) return null;
  // how many own trains load this cargo at the hub (for the Log)
  for (local v = vl.Begin(); !vl.IsEnd(); v = vl.Next()) {
    if (GSVehicle.GetVehicleType(v) != GSVehicle.VT_RAIL || GSVehicle.GetCapacity(v, best.cargo) <= 0) continue;
    for (local i = 0; i < GSOrder.GetOrderCount(v); i++) {
      if (GSOrder.IsGotoStationOrder(v, i) && GSStation.GetStationID(GSOrder.GetOrderDestination(v, i)) == best.hub) { best.trains++; break; }
    }
  }
  return best;
}

/* Industry station places: far from the industry (keeps the land around it
 * free), and a bit toward the other end. The coverage check comes later. */
function Tg_FarScore(t, ind, other)
{
  return 3 * GSMap.DistanceManhattan(t, ind) + GSMap.DistanceManhattan(ind, other) - GSMap.DistanceManhattan(t, other);
}

/* Candidate tiles for a station, best first. */
function Tg_Candidates(e, role, radius, other)
{
  local list;
  if (e.kind == "industry") {
    list = (role == "from") ? GSTileList_IndustryProducing(e.id, radius) : GSTileList_IndustryAccepting(e.id, radius);
    list.Valuate(Tg_FarScore, Tg_Center(e), other);
    list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_DESCENDING);
  } else {
    // towns: up to 20 tiles out, so a station can sit at the edge of a dense centre
    list = U_TilesAround(Tg_Center(e), 20);
  }
  return list;
}
