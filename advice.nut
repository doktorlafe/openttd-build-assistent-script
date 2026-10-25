/* Engine and wagon choice for the trains bought with a railway.
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
