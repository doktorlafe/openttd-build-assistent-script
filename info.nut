class LafeBuildAssistant extends GSInfo {
  function GetAuthor()      { return "lafe"; }
  function GetName()        { return "Lafe Build Assistant"; }
  function GetDescription() { return "Builds roads and railways for your company between towns and industries: bridges, tunnels, stations, depots, signals and vehicles. Control it from the Story Book."; }
  function GetVersion()     { return 6; }
  function MinVersionToLoad() { return 1; }   // older savegames (and the benchmark map) load with newer versions
  function GetDate()        { return "2026-10-28"; }
  function CreateInstance() { return "LafeBuildAssistant"; }
  function GetShortName()   { return "LBAS"; }
  function GetAPIVersion()  { return "15"; }
  function GetURL()         { return "https://github.com/doktorlafe/openttd-build-assistent-script"; }

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
    Flag("light_mode", "Light mode: only the train tools page (you build the tracks, the assistant buys trains, copies and wagons)", 0);
    Flag("distance_tool", "Distance calculator in the Story Book (Manhattan distance between two clicked tiles)", 0);
    Flag("auto_connect_full", "Classic mode: connect two of your track ends that point at each other by itself (like Auto in light mode)", 1);
    Num("auto_range", "Light mode Auto: connect two track ends that point at each other up to N tiles apart", 1000, 10, 2000);
    Num("auto_wait", "Light mode Auto: days a track end or depot must stay unchanged before the assistant acts", 1, 0, 30);
    Num("max_distance", "Maximum distance between the two ends (tiles)", 2000, 10, 2000);
    Num("search_limit", "Route search limit (thousands of tiles examined)", 500, 10, 5000);
    Num("search_per_tick", "Route search: tiles examined per step (higher = faster, more lag)", 2000, 100, 20000);
    Num("segment_length", "Long routes: search in parts of N tiles (0 = one search)", 40, 0, 200);
    Num("build_per_tick", "Building: pieces built per step", 20, 1, 200);
    Flag("allow_bridges", "Allow bridges", 1);
    Flag("allow_tunnels", "Allow tunnels", 1);
    Num("max_bridge_length", "Maximum bridge length (tiles)", 60, 2, 100);
    Num("max_tunnel_length", "Maximum tunnel length (tiles)", 20, 2, 100);
    Flag("build_stops", "Road between towns: build a bus stop in both towns", 1);
    Flag("build_depot", "Build a depot", 1);
    Num("veh_road", "Vehicles: buses/trucks bought for a new road route (0 = none)", 2, 0, 20);
    Num("veh_rail", "Vehicles: trains bought for a new railway (0 = none)", 1, 0, 10);
    Num("veh_loop", "Vehicles: buses bought for a town bus loop (0 = none)", 1, 0, 10);
    Num("loop_stops", "Town bus loop: number of bus stops", 5, 2, 8);
    Num("loop_gap", "Town bus loop: minimum distance between the stops (tiles)", 4, 2, 10);
    Flag("allow_terraform", "Landscaping: level the land under stations (the land under the track is never levelled)", 1);
    Num("rail_station_length", "Rail station length (tiles)", 4, 2, 10);
    Num("rail_platforms", "Double rail station platforms (big station: later lines join the free platforms; single track uses at most 2)", 4, 2, 8);
    Flag("loop_station", "Double rail: loop at the destination (trains run through the station and turn back onto the return track, no reversing); a normal end station where there is no room", 1);
    Flag("follow_lines", "Rail: new lines run alongside your existing tracks where they can (tidy corridors)", 1);
    Flag("rail_mail", "Rail between towns: trains also carry mail (mail wagon behind the engine)", 1);
    Flag("station_signals", "Rail: path signals at the station entries (lets 2 trains share a single track)", 1);
    Num("signal_spacing", "Double rail: signal every N tiles", 5, 2, 20);
    Flag("preview_signs", "Show the planned route with signs", 1);
    Flag("search_preview", "Show the route search live on the map with moving signs", 1);
    Num("route_quality", "Route search: 0 = fastest, 1 = balanced, 2 = straightest/cheapest (slower)", 1, 0, 2);
    Flag("benchmark", "Benchmark: on loading, plan a fixed set of test routes (nothing is built) and report the results", 0);
    Flag("auto_confirm", "Build right away without asking for confirmation", 0);
    Flag("ap_allowed", "Autopilot: companies may switch it on (suggestions page)", 1);
    Num("ap_budget_percent", "Autopilot: one route may cost at most this % of the bank balance", 50, 5, 100);
    Num("ap_interval", "Autopilot: months to wait when nothing could be built (no money, no paying route)", 1, 1, 24);
    Num("ap_plan_timeout", "Autopilot: real seconds a plan may take before it tries the next suggestion (0 = no limit)", 50, 0, 600);
    Num("ap_watchdog", "Autopilot: real minutes without anything new before it moves on by itself (0 = never)", 30, 0, 240);
    Num("cost_limit_percent", "One build may cost at most this % of the bank balance", 100, 1, 100);
  }
}

RegisterGS(LafeBuildAssistant());
