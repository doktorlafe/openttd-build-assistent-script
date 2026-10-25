/* Small helpers shared by all modules.
 * Directions are indexes 0..3: 0 = +x, 1 = +y, 2 = -x, 3 = -y. 4 = none. */

function U_Vec(i)
{
  return [[1, 0], [0, 1], [-1, 0], [0, -1]][i];
}

/* Neighbour tile in direction i, or -1 at the map edge. */
function U_Step(tile, i)
{
  local v = U_Vec(i);
  local x = GSMap.GetTileX(tile) + v[0], y = GSMap.GetTileY(tile) + v[1];
  if (x < 1 || y < 1 || x >= GSMap.GetMapSizeX() - 1 || y >= GSMap.GetMapSizeY() - 1) return -1;
  return GSMap.GetTileIndex(x, y);
}

/* Tile moved by n steps in direction i, or -1. */
function U_StepN(tile, i, n)
{
  local v = U_Vec(i);
  local x = GSMap.GetTileX(tile) + v[0] * n, y = GSMap.GetTileY(tile) + v[1] * n;
  if (x < 1 || y < 1 || x >= GSMap.GetMapSizeX() - 1 || y >= GSMap.GetMapSizeY() - 1) return -1;
  return GSMap.GetTileIndex(x, y);
}

/* Direction from a to b (they should share an axis). */
function U_DirOf(a, b)
{
  local dx = GSMap.GetTileX(b) - GSMap.GetTileX(a);
  local dy = GSMap.GetTileY(b) - GSMap.GetTileY(a);
  if (dx > 0) return 0;
  if (dx < 0) return 2;
  if (dy > 0) return 1;
  return 3;
}

function U_SameAxis(a, b)
{
  return GSMap.GetTileX(a) == GSMap.GetTileX(b) || GSMap.GetTileY(a) == GSMap.GetTileY(b);
}

function U_Cross(i, j)
{
  local a = U_Vec(i), b = U_Vec(j);
  return a[0] * b[1] - a[1] * b[0];
}

/* Dot product of direction i with the vector from tile a to tile b. */
function U_Toward(i, a, b)
{
  local v = U_Vec(i);
  return v[0] * (GSMap.GetTileX(b) - GSMap.GetTileX(a)) + v[1] * (GSMap.GetTileY(b) - GSMap.GetTileY(a));
}

/* The four directions ordered by how much they point from a toward b. */
function U_DirsToward(a, b)
{
  local dirs = [0, 1, 2, 3];
  for (local i = 0; i < 4; i++) {
    for (local j = i + 1; j < 4; j++) {
      if (U_Toward(dirs[j], a, b) > U_Toward(dirs[i], a, b)) {
        local x = dirs[i]; dirs[i] = dirs[j]; dirs[j] = x;
      }
    }
  }
  return dirs;
}

function U_IsFlat(t)
{
  return GSTile.GetSlope(t) == GSTile.SLOPE_FLAT;
}

function U_IsInclined(t)
{
  local s = GSTile.GetSlope(t);
  return s == GSTile.SLOPE_NE || s == GSTile.SLOPE_SE || s == GSTile.SLOPE_SW || s == GSTile.SLOPE_NW;
}

function U_Neighbours(tile)
{
  local out = [];
  for (local i = 0; i < 4; i++) {
    local n = U_Step(tile, i);
    if (n >= 0) out.append(n);
  }
  return out;
}

/* Tiles in a square around center, nearest first. */
function U_TilesAround(center, radius)
{
  local x = GSMap.GetTileX(center), y = GSMap.GetTileY(center);
  local list = GSTileList();
  list.AddRectangle(GSMap.GetTileIndex(max(1, x - radius), max(1, y - radius)),
                    GSMap.GetTileIndex(min(GSMap.GetMapSizeX() - 2, x + radius), min(GSMap.GetMapSizeY() - 2, y + radius)));
  list.Valuate(GSMap.DistanceManhattan, center);
  list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);
  return list;
}

/* Text progress bar, e.g. [######--------------] 30% */
function U_Bar(pct)
{
  pct = max(0, min(100, pct));
  local n = pct / 5, s = "[";
  for (local i = 0; i < 20; i++) s += i < n ? "#" : "-";
  return s + "] " + pct + "%";
}

/* OpenTTD refuses texts longer than 254 bytes (Story Book, news, titles).
 * Cuts the text to fit, without splitting a UTF-8 character. */
const U_MAX_TEXT = 250;
function U_Clip(s)
{
  if (s == null) return "";
  if (typeof s != "string") s = s.tostring();
  if (s.len() <= U_MAX_TEXT) return s;
  local n = U_MAX_TEXT - 3;
  while (n > 0 && (s[n] & 0xC0) == 0x80) n--;   // UTF-8 continuation byte
  return s.slice(0, n) + "...";
}

/* Progress reporting for long one-shot searches (station places).
 * Jobs set g_report = { self, company, label, base } before the search;
 * U_Report(pct) shows base + pct/2 in the Story Book. */
g_report <- null;

function U_Report(pct)
{
  if (g_report == null) return;
  UI_Progress(g_report.self, g_report.company, g_report.label, g_report.base + pct / 2);
}

/* Operations left before the script is suspended for this tick. */
function U_OpsLeft()
{
  return GSController.GetOpsTillSuspend();
}

function U_IsSpecial(t)
{
  return GSBridge.IsBridgeTile(t) || GSTunnel.IsTunnelTile(t);
}

/* Fastest bridge for a given length (head to head, inclusive), or -1. */
function U_PickBridge(length)
{
  local list = GSBridgeList_Length(length);
  if (list.IsEmpty()) return -1;
  list.Valuate(GSBridge.GetMaxSpeed);
  list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_DESCENDING);
  return list.Begin();
}

function U_TestBridge(vt, a, b)
{
  local id = U_PickBridge(GSMap.DistanceManhattan(a, b) + 1);
  if (id < 0) return false;
  local tm = GSTestMode();
  return GSBridge.BuildBridge(vt, id, a, b);
}

function U_TestTunnel(vt, a)
{
  local tm = GSTestMode();
  return GSTunnel.BuildTunnel(vt, a);
}

/* State keys for the route search: tile, arrival direction, last turn. */
function K_Make(tile, dir, turn) { return tile * 16 + dir * 3 + turn; }
function K_Tile(k) { return k >> 4; }
function K_Dir(k)  { return (k & 15) / 3; }
function K_Turn(k) { return (k & 15) % 3; }
