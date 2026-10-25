/* Route preview: signs along the planned route. */

function Preview_Place(paths)
{
  local ids = [];
  foreach (path in paths) {
    local t = path.tiles, k = path.kinds;
    for (local j = 0; j < t.len() && ids.len() < 80; j++) {
      local mark = j == 0 || j == t.len() - 1 || j % 6 == 0;
      local label = "route";
      if (k[j] == 1) { mark = true; label = "bridge"; }
      if (k[j] == 2) { mark = true; label = "tunnel"; }
      if (!mark) continue;
      local id = GSSign.BuildSign(t[j], label);
      if (GSSign.IsValidSign(id)) ids.append(id);
    }
  }
  return ids;
}

function Preview_Clear(ids)
{
  foreach (id in ids) {
    if (GSSign.IsValidSign(id)) GSSign.RemoveSign(id);
  }
}

/* Sign texts the script uses; List from signs leaves these alone. */
function Preview_IsOwnSign(name)
{
  return name == "route" || name == "bridge" || name == "tunnel" || name == "search" || name == "search >";
}

/* Live view of the route search: signs along the most promising path so
 * far (up to 30), the last one marks the tip. Returns the new sign ids. */
function Preview_Live(old, tiles)
{
  Preview_Clear(old);
  local ids = [];
  local n = tiles.len();
  if (n == 0) return ids;
  local step = max(3, n / 30);
  for (local j = 0; j < n; j += step) {
    local id = GSSign.BuildSign(tiles[j], "search");
    if (GSSign.IsValidSign(id)) ids.append(id);
  }
  local id = GSSign.BuildSign(tiles[n - 1], "search >");
  if (GSSign.IsValidSign(id)) ids.append(id);
  return ids;
}

/* Signs left from a search that was running when the game was saved. */
function Preview_CleanLeftovers()
{
  local list = GSSignList();
  for (local s = list.Begin(); !list.IsEnd(); s = list.Next()) {
    local name = GSSign.GetName(s);
    if (name == "search" || name == "search >") GSSign.RemoveSign(s);
  }
}

function Preview_Count(path, kind)
{
  local n = 0;
  foreach (k in path.kinds) if (k == kind) n++;
  return n;
}
