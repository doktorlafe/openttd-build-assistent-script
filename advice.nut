/* Train advice: which locomotive and wagons to buy for a line.
 * Reads what the company can buy for the rail type and cargo and picks two
 * trains: the fastest and the strongest (or the cheapest if that is the same
 * engine). The train length fits the platform: standard vehicles are half a
 * tile long, so a platform of L tiles holds 2*L vehicles including the engine.
 * Must run inside a GSCompanyMode. */

function Adv_IsLoco(e, rail)
{
  return !GSEngine.IsWagon(e) && GSEngine.IsBuildable(e) &&
         GSEngine.CanRunOnRail(e, rail) && GSEngine.HasPowerOnRail(e, rail);
}

function Adv_Carries(e, cargo)
{
  return GSEngine.GetCargoType(e) == cargo || GSEngine.CanRefitCargo(e, cargo);
}

/* Wagon with the most capacity. Prefers wagons that are not slower than speed. */
function Adv_Wagon(cargo, rail, speed)
{
  local best = -1, best_cap = -1, any = -1, any_cap = -1;
  local list = GSEngineList(GSVehicle.VT_RAIL);
  for (local e = list.Begin(); !list.IsEnd(); e = list.Next()) {
    if (!GSEngine.IsWagon(e) || !GSEngine.IsBuildable(e) || !GSEngine.CanRunOnRail(e, rail)) continue;
    if (!Adv_Carries(e, cargo)) continue;
    local cap = GSEngine.GetCapacity(e);
    local limit = GSEngine.GetMaxSpeed(e);
    if (cap > any_cap) { any = e; any_cap = cap; }
    if ((limit == 0 || limit >= speed) && cap > best_cap) { best = e; best_cap = cap; }
  }
  return best >= 0 ? best : any;
}

/* Up to two { kind, loco } choices. */
function Adv_Locos(rail)
{
  local fast = -1, strong = -1, cheap = -1;
  local list = GSEngineList(GSVehicle.VT_RAIL);
  local locos = [];
  for (local e = list.Begin(); !list.IsEnd(); e = list.Next()) {
    if (Adv_IsLoco(e, rail)) locos.append(e);
  }
  foreach (e in locos) {
    if (fast < 0 || GSEngine.GetMaxSpeed(e) > GSEngine.GetMaxSpeed(fast) ||
        (GSEngine.GetMaxSpeed(e) == GSEngine.GetMaxSpeed(fast) && GSEngine.GetPower(e) > GSEngine.GetPower(fast))) fast = e;
  }
  foreach (e in locos) {
    if (e == fast) continue;
    if (strong < 0 || GSEngine.GetMaxTractiveEffort(e) > GSEngine.GetMaxTractiveEffort(strong)) strong = e;
    if (cheap < 0 || GSEngine.GetPrice(e) < GSEngine.GetPrice(cheap)) cheap = e;
  }
  local out = [];
  if (fast >= 0) out.append({ kind = "Fast", loco = fast });
  if (strong >= 0 && GSEngine.GetMaxTractiveEffort(strong) > GSEngine.GetMaxTractiveEffort(fast)) {
    out.append({ kind = "Strong", loco = strong });
  } else if (cheap >= 0) {
    out.append({ kind = "Cheap", loco = cheap });
  }
  return out;
}

/* Lines of text for the Story Book: [title, option 1, option 2]. */
function Adv_Text(cargo, rail, plat_len)
{
  local cname = GSCargo.GetName(cargo);
  local title = "Train advice: " + cname + " on " + GSRail.GetName(rail) + ", platform " + plat_len +
                " tiles = engine + " + (plat_len * 2 - 1) + " wagons (standard length vehicles).";
  local lines = [title];
  local locos = Adv_Locos(rail);
  if (locos.len() == 0) {
    lines.append("No locomotive for this rail type is available.");
    lines.append("-");
    return lines;
  }
  foreach (o in locos) {
    local e = o.loco;
    local speed = GSEngine.GetMaxSpeed(e);
    local own = GSEngine.GetCapacity(e) > 0 && Adv_Carries(e, cargo) ? GSEngine.GetCapacity(e) : 0;
    local w = Adv_Wagon(cargo, rail, speed);
    local n = plat_len * 2 - 1;
    local text = o.kind + ": 1x " + GSEngine.GetName(e) + " (" + speed + " km/h, " + GSEngine.GetPower(e) + " hp, " +
                 GSEngine.GetMaxTractiveEffort(e) + " kN)";
    if (w < 0) {
      text += " - no wagon for " + cname + " on this rail type";
    } else {
      local cap = GSEngine.GetCapacity(w);
      text += " + " + n + "x " + GSEngine.GetName(w) + " (" + cap + " each). Train carries " + (cap * n + own) + " " + cname;
      local limit = GSEngine.GetMaxSpeed(w);
      if (limit > 0 && limit < speed) text += ", wagons limit it to " + limit + " km/h";
      text += ". Price about " + (GSEngine.GetPrice(e) + GSEngine.GetPrice(w) * n) + ".";
    }
    lines.append(text);
  }
  if (lines.len() < 3) lines.append("-");
  return lines;
}

/* Platform length of the rail station at tile, or -1. */
function Adv_PlatformLength(tile)
{
  if (!GSRail.IsRailStationTile(tile)) return -1;
  local st = GSStation.GetStationID(tile);
  local axis = GSRail.GetRailStationDirection(tile);
  local dirs = axis == GSRail.RAILTRACK_NE_SW ? [0, 2] : [1, 3];
  local n = 1;
  foreach (d in dirs) {
    local t = U_Step(tile, d);
    while (t >= 0 && GSRail.IsRailStationTile(t) && GSStation.GetStationID(t) == st &&
           GSRail.GetRailStationDirection(t) == axis) {
      n++;
      t = U_Step(t, d);
    }
  }
  return n;
}

/* Cargo a station handles: rated cargo with most waiting, else what is
 * produced around it, else passengers. */
function Adv_StationCargo(tile)
{
  local st = GSStation.GetStationID(tile);
  local best = -1, best_v = -1;
  local list = GSCargoList();
  if (GSStation.IsValidStation(st)) {
    for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
      if (!GSStation.HasCargoRating(st, c)) continue;
      local v = GSStation.GetCargoWaiting(st, c);
      if (v > best_v) { best = c; best_v = v; }
    }
    if (best >= 0) return best;
  }
  local radius = GSStation.GetCoverageRadius(GSStation.STATION_TRAIN);
  for (local c = list.Begin(); !list.IsEnd(); c = list.Next()) {
    local v = GSTile.GetCargoProduction(tile, c, 1, 1, radius);
    if (v > best_v) { best = c; best_v = v; }
  }
  if (best >= 0 && best_v > 0) return best;
  return Tg_Passengers();
}
