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

function Preview_Count(path, kind)
{
  local n = 0;
  foreach (k in path.kinds) if (k == kind) n++;
  return n;
}
