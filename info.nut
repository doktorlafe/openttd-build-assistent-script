class LafeBuildAssistant extends GSInfo {
  function GetAuthor()      { return "lafe"; }
  function GetName()        { return "Lafe Build Assistant"; }
  function GetDescription() { return "Builds roads and railways for your company between towns and industries: bridges, tunnels, stations, depots, signals and vehicles. Control it from the Story Book."; }
  function GetVersion()     { return 2; }
  function GetDate()        { return "2026-10-24"; }
  function CreateInstance() { return "LafeBuildAssistant"; }
  function GetShortName()   { return "LBAS"; }
  function GetAPIVersion()  { return "15"; }
  function GetURL()         { return ""; }

  function Num(name, desc, value, lo, hi) {
    AddSetting({name = name, description = desc,
      easy_value = value, medium_value = value, hard_value = value, custom_value = value,
      flags = CONFIG_INGAME, min_value = lo, max_value = hi});
  }

  function Flag(name, desc, value) {
    AddSetting({name = name, description = desc,
      easy_value = value, medium_value = value, hard_value = value, custom_value = value,
      flags = CONFIG_BOOLEAN | CONFIG_INGAME, min_value = 0, max_value = 1});
  }

  function GetSettings() {
    Num("max_distance", "Maximum distance between the two ends (tiles)", 150, 10, 1000);
    Num("search_limit", "Route search limit (thousands of tiles examined)", 200, 10, 2000);
    Num("search_per_tick", "Route search: tiles examined per step (higher = faster, more lag)", 2000, 100, 20000);
    Num("segment_length", "Long routes: search in parts of N tiles (0 = one search)", 40, 0, 200);
    Num("build_per_tick", "Building: pieces built per step", 20, 1, 200);
    Flag("allow_bridges", "Allow bridges", 1);
    Flag("allow_tunnels", "Allow tunnels", 1);
    Num("max_bridge_length", "Maximum bridge length (tiles)", 10, 2, 50);
    Num("max_tunnel_length", "Maximum tunnel length (tiles)", 12, 2, 50);
    Flag("build_stops", "Road between towns: build a bus stop in both towns", 1);
    Flag("build_depot", "Build a depot", 1);
    Num("veh_road", "Vehicles: buses/trucks bought for a new road route (0 = none)", 2, 0, 20);
    Num("veh_rail", "Vehicles: trains bought for a new railway (0 = none)", 1, 0, 10);
    Num("veh_loop", "Vehicles: buses bought for a town bus loop (0 = none)", 1, 0, 10);
    Num("loop_stops", "Town bus loop: number of bus stops", 5, 2, 8);
    Num("loop_gap", "Town bus loop: minimum distance between the stops (tiles)", 4, 2, 10);
    Flag("allow_terraform", "Rail stations: level sloped land when there is no flat place", 1);
    Num("rail_station_length", "Rail station length (tiles)", 4, 2, 10);
    Num("rail_platforms", "Rail station platforms on single track (1-2)", 2, 1, 2);
    Num("signal_spacing", "Double rail: signal every N tiles", 5, 2, 20);
    Flag("preview_signs", "Show the planned route with signs", 1);
    Flag("auto_confirm", "Build right away without asking for confirmation", 0);
    Num("cost_limit_percent", "One build may cost at most this % of the bank balance", 100, 1, 100);
  }
}

RegisterGS(LafeBuildAssistant());
