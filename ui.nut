/* Story Book: one page per company with the controls, status and history.
 * self = the controller: self.pages[company] = { page, el = { name -> element id }, ver } */

/* Bump when the page layout changes: older pages are then built again. */
const UI_VERSION = 4;

function UI_Items()
{
  local push = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_NONE);
  local go = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_NONE);
  local stop = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, GSStoryPage.SPBF_NONE);
  local pick = GSStoryPage.MakeTileButtonReference(GSStoryPage.SPBC_YELLOW, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE);
  local pick2 = GSStoryPage.MakeTileButtonReference(GSStoryPage.SPBC_ORANGE, GSStoryPage.SPBF_NONE, GSStoryPage.SPBC_MOUSE);
  local items = [
    ["intro", GSStoryPage.SPET_TEXT, 0,
      "1. Choose what to build. 2. Pick end A and end B (a town, or click within 4 tiles of an industry), " +
      "or add up to 10 towns to the list to connect them one after another."],
    ["intro2", GSStoryPage.SPET_TEXT, 0,
      "3. Plan route shows the route with signs and the price. 4. Confirm build. Vehicles are bought as set in the script settings."],
    ["mode_road", GSStoryPage.SPET_BUTTON_PUSH, push, "Road"],
    ["mode_rail", GSStoryPage.SPET_BUTTON_PUSH, push, "Rail"],
    ["mode_double", GSStoryPage.SPET_BUTTON_PUSH, push, "Double rail"],
    ["pick_a", GSStoryPage.SPET_BUTTON_TILE, pick, "Pick end A"],
    ["pick_b", GSStoryPage.SPET_BUTTON_TILE, pick, "Pick end B"],
    ["list_add", GSStoryPage.SPET_BUTTON_TILE, pick2, "Add to list (many towns)"],
    ["list_clear", GSStoryPage.SPET_BUTTON_PUSH, stop, "Clear list"],
    ["sel", GSStoryPage.SPET_TEXT, 0, "Selection: -"],
    ["plan", GSStoryPage.SPET_BUTTON_PUSH, go, "Plan route"],
    ["confirm", GSStoryPage.SPET_BUTTON_PUSH, go, "Confirm build"],
    ["cancel", GSStoryPage.SPET_BUTTON_PUSH, stop, "Cancel"],
    ["resume", GSStoryPage.SPET_BUTTON_PUSH, push, "Resume"],
    ["status", GSStoryPage.SPET_TEXT, 0, "Status: ready."],
    ["progress", GSStoryPage.SPET_TEXT, 0, "Progress: -"],
    ["adv_title", GSStoryPage.SPET_TEXT, 0, "Train advice: appears after a railway is built, or click a rail station or depot."],
    ["adv1", GSStoryPage.SPET_TEXT, 0, "-"],
    ["adv2", GSStoryPage.SPET_TEXT, 0, "-"],
    ["adv_pick", GSStoryPage.SPET_BUTTON_TILE, pick, "Train advice for a station"],
    ["loop_title", GSStoryPage.SPET_TEXT, 0, "Town bus loop: click a town to get bus stops close together, ready for one bus line."],
    ["loop_pick", GSStoryPage.SPET_BUTTON_TILE, pick2, "Bus loop in a town"],
    ["loop_result", GSStoryPage.SPET_TEXT, 0, "-"],
    ["hist_title", GSStoryPage.SPET_TEXT, 0, "Last builds:"]
  ];
  for (local i = 0; i < 5; i++) items.append(["h" + i, GSStoryPage.SPET_TEXT, 0, "-"]);
  return items;
}

function UI_Ensure(self, company)
{
  if (self.pages.rawin(company)) {
    local p = self.pages.rawget(company);
    if (GSStoryPage.IsValidStoryPage(p.page)) {
      if (p.rawin("ver") && p.ver == UI_VERSION) return true;
      // a page from an older version: build it again in the current layout
      GSStoryPage.Remove(p.page);
    }
    self.pages.rawdelete(company);
  }
  local page = GSStoryPage.New(company, "Build assistant");
  if (page == GSStoryPage.STORY_PAGE_INVALID) {
    GSLog.Error("Could not create the Story Book page for company " + company);
    return false;
  }
  local p = { page = page, el = {}, ver = UI_VERSION };
  self.pages.rawset(company, p);
  if (self.titles.rawin(company)) self.titles.rawdelete(company);
  foreach (it in UI_Items()) {
    local id = GSStoryPage.NewElement(page, it[1], it[2], U_Clip(it[3]));
    if (id != GSStoryPage.STORY_PAGE_ELEMENT_INVALID) p.el.rawset(it[0], id);
  }
  UI_Selection(self, company);
  if (self.hist.rawin(company)) {
    local h = self.hist.rawget(company);
    for (local i = 0; i < h.len() && i < 5; i++) UI_SetText(self, company, "h" + i, h[i]);
  }
  try {
    GSNews.Create(GSNews.NT_GENERAL, "Build assistant is ready: open the Story Book.", company, GSNews.NR_NONE, 0);
  } catch (e) {}
  return true;
}

/* Shows train advice for cargo on a rail type with a platform length. */
function UI_Advice(self, company, cargo, rail, plat_len)
{
  local lines;
  try {
    lines = Adv_Text(cargo, rail, plat_len);
  } catch (e) {
    GSLog.Error("Train advice failed: " + e);
    lines = ["Train advice: could not be worked out (" + e + ").", "-", "-"];
  }
  UI_SetText(self, company, "adv_title", lines[0]);
  UI_SetText(self, company, "adv1", lines[1]);
  UI_SetText(self, company, "adv2", lines[2]);
  foreach (l in lines) GSLog.Info(U_Clip("[" + company + "] " + l));
}

function UI_SetText(self, company, name, text)
{
  if (!self.pages.rawin(company)) return;
  local p = self.pages.rawget(company);
  if (!p.el.rawin(name)) return;
  local id = p.el.rawget(name);
  if (GSStoryPage.IsValidStoryPageElement(id)) GSStoryPage.UpdateElement(id, 0, U_Clip(text));
}

function UI_Status(self, company, text)
{
  GSLog.Info(U_Clip("[" + company + "] " + text));
  UI_SetText(self, company, "status", "Status: " + text);
}

/* Progress line: phase name and a bar (pct < 0 = no bar). */
function UI_Progress(self, company, phase, pct)
{
  UI_SetText(self, company, "progress", "Progress: " + phase + (pct >= 0 ? " " + U_Bar(pct) : ""));
  // the page title is always visible, even when the progress line is scrolled away
  if (!self.pages.rawin(company)) return;
  local page = self.pages.rawget(company).page;
  if (!GSStoryPage.IsValidStoryPage(page)) return;
  local title = "Build assistant";
  if (pct >= 0) title += " [" + max(0, min(100, pct)) + "%]";
  if (self.titles.rawin(company) && self.titles.rawget(company) == title) return;
  self.titles.rawset(company, title);
  GSStoryPage.SetTitle(page, title);
}

function UI_Pick(self, company)
{
  if (!self.picks.rawin(company)) self.picks.rawset(company, { mode = MODE_ROAD, a = null, b = null, list = [] });
  local p = self.picks.rawget(company);
  if (!p.rawin("list")) p.list <- [];   // picks from older saves
  return p;
}

function UI_Selection(self, company)
{
  local p = UI_Pick(self, company);
  local text;
  if (p.list.len() > 0) {
    // the list wins over A/B
    text = "Selection: " + Job_ModeName(p.mode) + " | list of " + p.list.len() + ": ";
    for (local i = 0; i < p.list.len(); i++) text += (i > 0 ? " > " : "") + Tg_Name(p.list[i]);
    if (p.list.len() < 2) text += " (add at least one more)";
    UI_SetText(self, company, "sel", text);
    return;
  }
  text = "Selection: " + Job_ModeName(p.mode) + " | A: " + Tg_Name(p.a) + " | B: " + Tg_Name(p.b);
  if (p.a != null && p.b != null && Tg_Valid(p.a) && Tg_Valid(p.b)) {
    local link = Tg_Link(p.a, p.b);
    if (link == null) text += " | no cargo between them";
    else text += " | carries " + GSCargo.GetCargoLabel(link.cargo) + " from " + Tg_Name(link.from);
  }
  UI_SetText(self, company, "sel", text);
}

function UI_History(self, company, text)
{
  if (!self.hist.rawin(company)) self.hist.rawset(company, []);
  local h = self.hist.rawget(company);
  h.insert(0, text);
  while (h.len() > 5) h.pop();
  for (local i = 0; i < 5; i++) UI_SetText(self, company, "h" + i, i < h.len() ? h[i] : "-");
}

/* Which button of the company's page an element id is, or null. */
function UI_ElementName(self, company, id)
{
  if (!self.pages.rawin(company)) return null;
  foreach (name, el in self.pages.rawget(company).el) {
    if (el == id) return name;
  }
  return null;
}
