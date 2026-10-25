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
  return e.kind == "town" ? GSTown.IsValidTown(e.id) : GSIndustry.IsValidIndustry(e.id);
}

function Tg_Name(e)
{
  if (!Tg_Valid(e)) return "?";
  return e.kind == "town" ? GSTown.GetName(e.id) : GSIndustry.GetName(e.id);
}

function Tg_Center(e)
{
  if (e.kind == "town") return GSTown.GetLocation(e.id);
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
  if (e.kind == "industry" && role == "from") return GSTile.GetCargoProduction(tile, cargo, w, h, radius) > 0;
  return GSTile.GetCargoAcceptance(tile, cargo, w, h, radius) >= 8;
}

/* Candidate tiles for a station, best first. */
function Tg_Candidates(e, role, radius, other)
{
  local list;
  if (e.kind == "industry") {
    list = (role == "from") ? GSTileList_IndustryProducing(e.id, radius) : GSTileList_IndustryAccepting(e.id, radius);
    list.Valuate(GSMap.DistanceManhattan, other);
    list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
  } else {
    // towns: up to 16 tiles out, so a station can sit at the edge of a dense centre
    list = U_TilesAround(Tg_Center(e), 16);
  }
  return list;
}
