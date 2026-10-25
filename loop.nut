/* Town bus loop: several drive-through bus stops close together in one town,
 * all on the same connected road network, ordered as the shortest round trip.
 * Must run inside a GSCompanyMode. */

/* Road tiles connected to the town centre, up to `radius` tiles away. */
function Loop_Reachable(center, radius)
{
  local start = -1;
  local near = U_TilesAround(center, 6);
  for (local t = near.Begin(); !near.IsEnd(); t = near.Next()) {
    if (GSRoad.IsRoadTile(t)) { start = t; break; }
  }
  local seen = {};
  if (start < 0) return seen;
  local queue = [start];
  seen.rawset(start, true);
  for (local qi = 0; qi < queue.len() && queue.len() < 3000; qi++) {
    local t = queue[qi];
    foreach (n in U_Neighbours(t)) {
      if (seen.rawin(n) || GSMap.DistanceManhattan(n, center) > radius) continue;
      if (!GSRoad.AreRoadTilesConnected(t, n)) continue;
      seen.rawset(n, true);
      queue.append(n);
    }
  }
  return seen;
}

/* Front tile for a drive-through stop on a straight road piece, or -1. */
function Loop_StopFront(t)
{
  if (!GSRoad.IsRoadTile(t) || GSRoad.IsRoadStationTile(t) || GSRoad.IsRoadDepotTile(t) || U_IsSpecial(t) || !U_IsFlat(t)) return -1;
  local c = [];
  for (local i = 0; i < 4; i++) {
    local n = U_Step(t, i);
    c.append(n >= 0 && GSRoad.AreRoadTilesConnected(t, n));
  }
  if (c[0] && c[2] && !c[1] && !c[3]) return U_Step(t, 0);
  if (c[1] && c[3] && !c[0] && !c[2]) return U_Step(t, 1);
  return -1;
}

/* Shortest round trip through the stops (tries every order, fine for <= 8). */
function Loop_Order(tiles)
{
  local n = tiles.len();
  if (n <= 3) return tiles;
  local best = null, best_len = 1 << 30;
  local perm = [];
  for (local i = 1; i < n; i++) perm.append(i);
  // Heap's algorithm over stops 1..n-1, stop 0 stays first
  local c = [];
  for (local i = 0; i < perm.len(); i++) c.append(0);
  local check = function(perm, tiles) {
    local len = GSMap.DistanceManhattan(tiles[0], tiles[perm[0]]);
    for (local i = 0; i + 1 < perm.len(); i++) len += GSMap.DistanceManhattan(tiles[perm[i]], tiles[perm[i + 1]]);
    return len + GSMap.DistanceManhattan(tiles[perm[perm.len() - 1]], tiles[0]);
  };
  local l = check(perm, tiles);
  best = clone perm; best_len = l;
  local i = 0;
  while (i < perm.len()) {
    if (c[i] < i) {
      local a = (i % 2 == 0) ? 0 : c[i];
      local x = perm[a]; perm[a] = perm[i]; perm[i] = x;
      l = check(perm, tiles);
      if (l < best_len) { best_len = l; best = clone perm; }
      c[i]++;
      i = 0;
    } else {
      c[i] = 0;
      i++;
    }
  }
  local out = [tiles[0]];
  foreach (p in best) out.append(tiles[p]);
  return out;
}

/* Builds the loop. Returns a text for the Story Book. */
function Loop_Build(town, count, gap, veh)
{
  local name = GSTown.GetName(town);
  if (BuildRoad_SelectType() < 0) return "No road type available yet.";
  local center = GSTown.GetLocation(town);
  local radius = 6 + count * gap;
  local reach = Loop_Reachable(center, radius);
  if (reach.len() == 0) return name + ": no roads near the centre.";

  // candidates sorted by distance to the centre
  local list = GSTileList();
  foreach (t, _ in reach) {
    if (Loop_StopFront(t) >= 0) list.AddTile(t);
  }
  list.Valuate(GSMap.DistanceManhattan, center);
  list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);

  // keep away from bus stops that are already there
  local taken = [];
  local stops = GSStationList(GSStation.STATION_BUS_STOP);
  for (local s = stops.Begin(); !stops.IsEnd(); s = stops.Next()) {
    if (GSMap.DistanceManhattan(GSStation.GetLocation(s), center) <= radius) taken.append(GSStation.GetLocation(s));
  }

  // nearest to the centre first, each new stop at least `gap` tiles from the others
  local built = [];
  for (local t = list.Begin(); !list.IsEnd() && built.len() < count; t = list.Next()) {
    local ok = true;
    foreach (o in taken) if (GSMap.DistanceManhattan(o, t) < gap) { ok = false; break; }
    if (!ok) continue;
    local front = Loop_StopFront(t);
    if (front < 0) continue;
    if (!GSRoad.BuildDriveThroughRoadStation(t, front, GSRoad.ROADVEHTYPE_BUS, GSStation.STATION_NEW)) continue;
    built.append(t);
    taken.append(t);
  }
  if (built.len() < 2) return name + ": could build only " + built.len() + " bus stop(s), the town roads are too short or busy.";

  local order = Loop_Order(built);
  local names = [];
  for (local i = 0; i < order.len(); i++) {
    local st = GSStation.GetStationID(order[i]);
    local sname = name + " Loop " + (i + 1);
    if (!GSStation.SetName(st, sname)) sname = GSStation.GetName(st);
    names.append(sname);
  }
  local depot = "", depot_tile = -1;
  if (GSController.GetSetting("build_depot") || veh > 0) {
    local own = BuildRoad_OwnDepotNear(center, 5);
    if (own >= 0) {
      depot_tile = own;
      depot = " Your depot " + GSMap.DistanceManhattan(own, center) + " tiles from the centre is used.";
    } else {
      depot_tile = BuildRoad_DepotClosest(center, reach, 12);
      depot = depot_tile >= 0 ? " Depot built " + GSMap.DistanceManhattan(depot_tile, center) + " tiles from the centre." : " No place for a depot near the centre.";
    }
  }
  local text = name + " bus loop (" + order.len() + " stops): ";
  foreach (n in names) text += n + " > ";
  text += names[0] + "." + depot;
  if (veh > 0) {
    local a = { kind = "road", stops = order, cargo = Tg_Passengers(), full = false, count = veh };
    text += Veh_Buy(a, depot_tile);
  } else {
    text += " Give the bus orders in this order.";
  }
  return text;
}
