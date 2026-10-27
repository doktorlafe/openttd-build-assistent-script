# Lafe Build Assistant – Game Script for OpenTTD

**Tired of laying every piece of track by hand?** Pick two towns, press a button, and the script plans the route,
shows you the price, builds it and buys the vehicles. Everything is controlled from one page in the Story Book.

<div align="center">

![LIVE](https://img.shields.io/badge/🔴%20LIVE-SERVER%20ONLINE-red?style=for-the-badge)
![OpenTTD](https://img.shields.io/badge/OpenTTD-16%20Beta-orange?style=for-the-badge)
![Game Script](https://img.shields.io/badge/Game%20Script-ACTIVE-brightgreen?style=for-the-badge)

</div>

> [!CAUTION]
> # 🚂 PLAY IT LIVE NOW!
> ### This script runs on my **public OpenTTD server!**
>
> | | |
> |---|---|
> | 🎮 **Server name** | `OpenTTD 16 Beta` |
> | 🌐 **IP address** | `62.238.53.187:3979` |
> | ⚠️ **Required version** | **Latest OpenTTD 16 test build** |
>
> 👉 **Multiplayer → search `OpenTTD 16 Beta` → JOIN!**


**Quick start:**
1. In the main menu open **Game Script Settings**, choose **Lafe Build Assistant** and start a game.
2. Open the **Story Book** and go to the **Build assistant** page.
3. Choose **Road** or **Rail**, click **A** and **B** on two towns, then **Plan**.
4. Check the preview on the map and press **Build**. Done: the line is built and vehicles are running.

See the pictures below for the basics. The detailed manual follows after them.

A Game Script for **OpenTTD 15.x** (API 15) that builds transport connections for your company and buys
vehicles for them. It is controlled entirely from the **Story Book**, where each company has its own page.

## What's new in version 5

- **Better route search.** Long routes (hundreds of tiles) are found quickly: the search no longer gets stuck in front
  of a station, and a search that cannot get closer to its goal stops early instead of running for months of game time.
  On the benchmark map the whole test set went from 46,438 to 2,141 ticks.
- **Terrain handled like the best AIs do it.** The land under the track is **never levelled** any more. The route only
  uses sloped tiles where the track fits the land as it is (on a foundation) and goes around steep slopes or bridges
  them, as AIs built on the Pathfinder.Rail library do. Levelling single tiles used to tilt their neighbours and left
  holes in the line. A station is only placed without levelling where its whole layout (platforms, switches, exits and
  depot) is flat at one height; otherwise the whole area is levelled at once. Any hole that still appears gets a
  **HOLE** sign on the map with the reason.
- **Suggestions page.** Press **Suggest**: the script scans the industries and lists the 5 best cargo railways with the
  income, running costs, build cost, cargo days and payback time. **Plan #N** plans the route in one click.
- **Autopilot.** Switch it on and it builds route after route on its own until you switch it off (see section 2b).
- **Ships from oil rigs.** **Ship: plan / Ship: build** connects an oil rig to a refinery: dock, depot and tankers.
- The default **max_distance** is now 2000 tiles.

**Features:**
- **roads** between two towns (buses) or for cargo from industry to industry or town (trucks),
- **railways**: single track (2 trains can pass in the stations thanks to path signals), or double track with signals,
- **a list of up to 10 towns** connected as one through line that a single train runs from A to Z,
- **bridges, tunnels, level crossings** and perpendicular crossing of your own track,
- **terrain levelling** under stations and **extending an existing station** with more platforms,
- **route preview** with signs and a cost estimate before building,
- **automatic vehicle purchase** including orders,
- **town bus loop** (stops close together, a depot near the centre and a bus),
- **suggestions** of the best cargo routes with an income estimate, and an **autopilot** that builds them,
- **ship lines** from oil rigs to refineries,
- **progress in percent** and a **Log** with the reasons of problems (no money, no station place, no route ...) right in the Story Book.

> Only one Game Script can run in a game, so this script cannot run together with HardEconomy.

---
Defining connection A - B
<img width="802" height="597" alt="image" src="https://github.com/user-attachments/assets/88ac1bbd-603d-42e5-9315-df961da1b190" />
Shows a plan
<img width="2162" height="910" alt="image" src="https://github.com/user-attachments/assets/24339df8-fd27-4e53-9e45-52aff42f4032" />
After build
<img width="2322" height="918" alt="image" src="https://github.com/user-attachments/assets/96e95685-f25a-4c7e-a123-a01ec0c6e380" />
Also creates a vehicle to run (optional)
<img width="1412" height="898" alt="image" src="https://github.com/user-attachments/assets/3a1a3c9b-217b-4ce1-bcf4-d8db9a96c6f0" />
Want to grow your city quickly? Just click on the city to create bus stations and also a bus is created.
<img width="2341" height="878" alt="image" src="https://github.com/user-attachments/assets/f2c07044-fd02-48af-9226-7297e7897657" />


## 1. Installation and startup

The project lives in `C:\Users\lafe\openttd-projects\lafe-script`. The game reads it through a directory junction
`C:\Users\lafe\Documents\OpenTTD\game\lafe-script`, so files are edited only in the project.

1. Start OpenTTD, open **Game Script Settings** in the main menu and select **Lafe Build Assistant**.
2. Check the settings (chapter 7) and start a new game, or load a saved one.
3. In the game, open the **Story Book**. The **"Build assistant"** page is created automatically for each company.

**What to restart when:**
| What changed | What to do |
|---|---|
| script code (`*.nut` except `info.nut`) | just reload the game (a savegame or a new game) |
| script settings (`info.nut`) | restart OpenTTD entirely, because the settings list is read only at program start |

---

## 2. The Story Book page

Page elements from top to bottom:

| Section | Elements | Purpose |
|---|---|---|
| Main buttons | **A**, **B**, **Plan**, **Build**, **Cancel** | right after each other at the top, the ones used all the time. A/B: click on the map: within 4 tiles of an industry = industry, otherwise the nearest town |
| Selection | *Selection* line | type, ends or list, which cargo will be carried and from where |
| State | *Progress* and *Status* lines | what is happening now, progress in percent, `>>> READY TO BUILD <<<` when the plan is done |
| | **Resume** | continue after running out of money |
| Build type | **Road**, **Rail**, **Double**, **My tracks** | what will be built; *My tracks* switches reuse of your existing railway on/off (chapter 3) |
| List | **+ List**, **List from signs**, **Clear** | several towns in a row (chapter 4) |
| Log | 6 lines, newest first | diagnostics: `[!]` = problem (no money, no station place, search limit, failed pieces, ...), `[i]` = info |
| Bus loop | **Bus loop in a town** + result | chapter 6 |
| History | *Last builds* (5 lines) | the last five builds including errors |
| Help | one line at the bottom | short how-to |

The Story Book can only stack elements below each other, so buttons cannot be put side by side.

A page **Build assistant - help** explains every button (the Story Book has no tooltips).

A second page, **Build assistant - debug**, shows the technical side without opening the script debug window:
the script settings that matter for the search (including OpenTTD's opcode limit), the inner state of the running job
(search part, tiles examined / limit, how long without progress, retries, build step, bank) and the last 20 lines
of the technical log. Switch pages with the page selector at the top of the Story Book.

The percentage is also shown in the **page title**, e.g. "Build assistant [45%]", so it is visible even when the page is scrolled.
A page from a savegame of an older version is rebuilt into the new layout automatically and the history is kept.

---

## 2b. Suggestions and autopilot

The page **Build assistant - suggestions** has its own controls:

- **Suggest** scans every industry that produced cargo last month and is not fully served, and looks for an industry
  that accepts its cargo 30-150 tiles away. Each of the 5 best routes shows two lines: the profit per year and the
  payback time, and the breakdown (income = amount x the game's payment for that cargo, distance and days on the way;
  running costs; build cost = track + stations + trains). Travel time counts with 3/4 of the top speed of your fastest
  engine plus half of the full-load waiting time. Industries on water are left out (rail cannot reach them).
- **Plan #N** puts the two industries into A and B, plans the route and opens the build page with the exact cost.
- **Autopilot** (orange button, OFF -> BUILD -> PLAN ONLY):
  - **BUILD**: it runs Suggest, takes the best suggestion whose estimate fits the budget (*ap_budget_percent* of the
    bank balance, default 50%), plans it and builds it with the trains. Then it starts again at once, route after
    route, until you switch it off. A plan that fails, costs more than the budget or more than 1.5x the estimate is
    skipped and the next suggestion is planned. A source it has already connected is not taken again.
  - **PLAN ONLY**: the same, but it only writes what it would build ("WOULD BUILD ...") and spends nothing.
  - When nothing can be built (no money, no paying route) it waits *ap_interval* months (default 1) and tries again.
  - It never touches a job you started yourself; while one runs it waits. The mode is saved with the game.
  - On a server the setting *ap_allowed* switches the autopilot off for every company.
  - Every decision goes to the history lines under the button, the Log and the script debug window (lines `AP`).

## 3. Building a single connection (A → B)

1. Choose the build type (**Road / Rail / Double**).
2. **A** and **B**: click on a town or near an industry.
3. **Plan**: the script finds station locations and searches for a route. The game does not freeze meanwhile.
4. The route is shown on the map with signs (*route*, *bridge*, *tunnel*) and *Status* shows the length, number of bridges
   and tunnels, and the cost estimate.
5. **Build** starts building, **Cancel** cancels it. If money runs out, building pauses and continues with **Resume**.
6. After building, the script buys vehicles (chapter 5) and writes the result to the history.

### What gets built
| Type | Stations | Route | Depot | Vehicles |
|---|---|---|---|---|
| Road, 2 towns | bus stops near the centres (if not already there) | road, reuses existing roads, stops and bridges | near the centre of the first town | buses (default 2) |
| Road, cargo | drive-through truck stops with a turnaround | road | next to the loading stop | trucks, full load at the source |
| Rail | station length × 1–2 platforms with switches | single track, two-way path signals at the station entries | past the end of the platform, in the same axis | up to 2 trains (with 2 platforms) |
| Double rail | station length × 2, both tracks linked | two tracks side by side (the second follows the first as closely as it can), one-way path signals on the line and at the station entries | past the end of the platform | trains as configured |

### Cargo
- **Two towns:** passengers.
- **Industry and anything:** the script picks a cargo that one end produces and the other accepts. It decides the direction itself,
  so it does not matter which end is A and which is B. If no such cargo exists, it says so already in *Selection*.

### Stations: where and how
A station location is searched in this order:
0. **Joining a big station of yours:** the script remembers the stations it built. If one near the end still has free platforms
   (without a line in front), the new line ends there: it gets its own entry and is linked to the switches of the others,
   so all trains share one big station. Only the switches and the track are built, no new station.
   If that station does not cover the industry or town, the script uses the **Ctrl trick (distant join)**: one station tile
   right next to it, joined to the big station. The industry then delivers to (or takes from) the big station. It works
   as far as the game setting *station spread* allows (the whole station must fit in spread × spread tiles, default 12)
   and only when *distant join* is on in the game settings.
1. **Extending your station:** new platforms are placed alongside an existing station, with the same orientation
   and aligned with its end, and connected to it. A 2×7 thus becomes one 4×7 station with shared passengers.
   The switches of the old and new platforms are linked both ways, so it is **one big station**: trains of every line
   can use every platform, come in through one throat and leave straight on their own line.
2. **Flat free land** within 20 tiles of the town centre (or around the industry). The station must cover houses or the industry.
   At an industry the station goes **as far from it as the coverage allows** (and a bit toward the other end), so the land
   around the industry stays free. Of the first places that fit (up to 6), the **best** one is taken: free straight land in
   front of the exit (the line can leave without a sharp bend), facing the other end and, in towns, covering more houses.
3. **A slope that gets levelled** (if *allow_terraform* is on). The levelling cost is included in the estimate.

The station exit must be free and the space for the depot behind the platform is kept free.
The script does not demolish houses, because that would hurt your town rating.

### Route rules
- **Road:** uses existing roads, goes straight through drive-through stops and also uses existing bridges and tunnels.
  It crosses rail only perpendicularly and only over a single straight track.
- **Rail, following your lines:** a tile right beside one of your tracks is cheaper (*follow_lines*), so a new line runs
  alongside your existing ones, copies their line and takes the same way around hills, water and towns: tidy corridors
  instead of new tracks across open land.
- **Rail, slopes:** the land under the track is never levelled. The route only uses sloped tiles where the track piece fits
  as the land is (on a foundation), and goes around steep slopes or over them with a bridge or tunnel. (Levelling single
  tiles along the track moved the corners of their neighbours and left holes in the line; other AIs such as those using the
  Pathfinder.Rail library work the same way.)
- **Rail:** crossing roads or tracks is possible on the level, but a **bridge over them** (flyover) is always considered too
  and usually wins over crossing your own track on the level. Must not turn on a slope, on a level crossing, or right after a bridge. Two turns in the same direction in a row
  (a 90° turn) are forbidden. Diagonal track is cheaper per tile than straight track, because a diagonal is the shorter way for a train
  (idea from the ChooChoo AI); entering and leaving a diagonal costs a little, so the route has long straight and long
  diagonal runs instead of zigzags. A tile right next to houses, water or an industry costs a little more, so the line keeps
  some room beside it. A sharp bend (straight, one curve piece, straight) is expensive, so bends are smooth where there is room. It may cross your own straight unsignalled track perpendicularly. It does not cross other companies' tracks, but can bridge over them.
- **Long routes** are searched in parts: a waypoint is placed every *segment_length* tiles on the straight line between the ends
  and the route is searched part by part. A waypoint in water or in a town is moved to free land, and an unreachable waypoint is skipped.

- **Test run before building:** the whole plan is built once in test mode. If a track piece fails there , the route is planned once more around that tile, so the line has no hole.

### My tracks: using your existing railway
Press **My tracks** to switch it on (the *Selection* line then says *uses your tracks*). The route search may then run
on your existing tracks and join them where it helps, instead of building a new line next to them:
- only **your company's** tracks are used (players in the same company share them); other companies' tracks stay obstacles,
- the rail type must suit the new trains, stations, depots, bridges and tunnels of the old line are not used,
- it never runs against a one-way signal, so on a double track it keeps to the right track,
- where a switch is needed on the old line it is added, and the new track gets a signal before the junction,
- running on your track is much cheaper for the search than new track, so it takes a small detour to use it.
  Lines to the same place (for example several mines to one power station) then share one corridor:
  less land taken, less money spent, and more room left for the other players,
- the plan summary says on how many tiles new track is built and how much was saved.

The old line is shared by more trains then, so check that it has enough signals. Off by default.

### Transfer: feed a line you already have
Press **Transfer** to switch it on (the *Selection* line says *transfer on*). When you then plan A → B, the script looks at
your trains: if one of them already carries a cargo of A (passengers for a town) to a station that accepts it at B, the
script builds only a short **feeder** from A to the station of that line nearest to A (the *hub*, within *max_distance*
of A; it is used even when B itself is closer):
- the new platforms become part of the hub station (beside it, or with the Ctrl trick within the *station spread*),
- the feeder trains load at A (full load for cargo) and at the hub **transfer and leave empty**,
- your trains already running from the hub take the cargo on to B and the money is paid on delivery,
- B may then be further away than *max_distance*, only the feeder has to fit the limit,
- the Log says how many of your trains load at the hub; with fewer than 2 it warns you, because waiting cargo slowly
  disappears when it is not picked up often enough.

If no such train exists, the script says so and plans the whole way to B. Built for games without cargodist (the default).

### When no route is found
If the search ran out of its limit, the script first tries once more with twice the limit. Then it discards the station locations, finds others and tries again, up to 3 attempts in total.
A typical cause is a station surrounded by older track or roads. For a road between two town centres nothing can be retried.

---

## 4. Town list (up to 10) – one through line

1. Choose **Rail** (or **Road**).
2. Faster: take the game's **sign tool**, click the towns one after another (it stays active) and press **List from signs**. The signs become the list in the order you placed them and are removed. Or use **+ List** to click towns in the order you want to connect them. *Selection* shows
   the list (`Aton > Bury > Cefield`). The list takes priority over A/B, **Clear** clears it. **Cancel** with no job running throws away the list and A/B.
3. **Plan**: sections 1→2, 2→3, … are built one after another **without confirmation**. Each section must pass the cost limit.

### Railway (towns only, Rail type)
1. **Stations in all towns are planned first** (Progress: `1/3 stations 2/5: Bury`).
   - the first and last stations are terminals facing the neighbouring town,
   - stations in between are **through stations**: they have switches at both ends, one end facing the previous
     and the other facing the next town,
   - if no location is found in some town, the list does not start at all.
2. **The first section builds all stations at once** (including switches and the depot behind the first station), so nobody
   can take their places.
3. Later sections only lay track between finished stations. A train enters a through station at one end and leaves at the other.
4. After the last section the script buys **one train** with orders A → B → … → Z → … → B (there and back).

### Road
Sections are built as separate roads. After the last section the script buys buses with orders through the stops of all towns there and back.

### When a through line is not created
- with **Double rail**, because through stations are so far supported only for single track,
- when the list contains an **industry**.

In both cases the sections are built separately and a single train will not run all of them.

### When a section fails
The whole list **stops**, because the remaining sections would not connect to the broken line. The history records which section
it was and how many sections remain. Enter the rest as a new list starting with that town. **Cancel** cancels the section in progress
and all remaining ones.

---

## 5. Vehicles

### Automatic purchase
After a build finishes, the script buys vehicles, gives them orders and starts them from the depot:
- **buses and trucks:** the best available vehicle for the cargo (capacity × speed), refitted if needed,
- **train:** the fastest locomotive for the rail type, between towns also mail wagon(s) (*rail_mail*), and wagons as long as the train fits the platform. The script measures the length
  **on the purchased train** and sells whatever sticks out, so it works with NewGRF vehicles too,
- **bus loop:** bus(es) with orders Loop 1 → … → Loop N.

Rules:
- additional vehicles are copies of the first with **shared orders**,
- for cargo from an industry the first order is **full load**,
- **single track gets at most 2 trains**: with 2 platforms and *station_signals* on, the stations work as passing places. Otherwise 1 train. A town list always gets 1 train,
- if there is no money or no suitable vehicle, the script says so and the route stays built.

Counts are set in *Vehicles: …*; 0 means don't buy vehicles.

---

## 6. Town bus loop

Click **Bus loop in a town** and then a town. The script:
1. walks the roads connected to the centre (so all stops will be on one connected network),
2. builds *loop_stops* drive-through stops as close to the centre and to each other as possible, but at least *loop_gap* tiles apart.
   It avoids stops that already exist,
3. computes the shortest loop and names the stops in that order *Town Loop 1 … Loop N*,
4. builds a **depot as close to the centre as possible**: within 12 tiles, by a road connected to the loop, flat land first, then a gentle slope.
   If you already have a depot within 5 tiles of the centre, it uses that,
5. buys *veh_loop* buses with orders around the loop.

---

## 7. Script settings

Found in the main menu under **Game Script Settings**, or in game in the AI/Game Script window under **Configure**.
They can be changed while the game is running and apply to all companies. In multiplayer only the server can change them.

### Route search
| Setting (name in `info.nut`) | Default | Range | What it does |
|---|---|---|---|
| Maximum distance between the two ends (`max_distance`) | 2000 | 10–2000 | Maximum distance of the ends (and of neighbouring towns in a list) in tiles. |
| Route search limit (`search_limit`) | 500 | 10–5000 | How many thousand tiles the search may examine before giving up. A section to a waypoint gets a quarter, at least 20 thousand. |
| Route search: tiles examined per step (`search_per_tick`) | 2000 | 100–20000 | Cap of one search batch. The script searches in batches of at most 300 tiles anyway so progress updates often, so the setting only matters below 300. |
| Long routes: search in parts of N tiles (`segment_length`) | 40 | 0–200 | Waypoint spacing for long routes. 0 = search the whole route at once (very slow for long routes). |
| Allow bridges (`allow_bridges`) | yes | | Bridges over water, roads and rails. |
| Allow tunnels (`allow_tunnels`) | yes | | Tunnels through hills. |
| Maximum bridge length (`max_bridge_length`) | 60 | 2–100 | Longest bridge in tiles. The game also has its own limit (*max bridge length*, default 64). |
| Maximum tunnel length (`max_tunnel_length`) | 20 | 2–100 | Longest tunnel in tiles. |
| Route search quality (`route_quality`) | 1 | 0–2 | 0 = fastest search, 1 = balanced, 2 = straighter and cheaper routes but a slower search. Level 2 can be many times slower on long routes. The search also avoids level crossings where it can. |

### Building
| Setting | Default | Range | What it does |
|---|---|---|---|
| Building: pieces built per step (`build_per_tick`) | 20 | 1–200 | How many pieces are built in one step. Higher builds faster. |
| Road between towns: build a bus stop in both towns (`build_stops`) | yes | | Bus stops near the centres of both towns. |
| Build a depot (`build_depot`) | yes | | A depot for each new route. |
| One build may cost at most this % of the bank balance (`cost_limit_percent`) | 100 | 1–100 | Safeguard: a more expensive build won't start. The loan is not counted and the estimate excludes the depot and vehicles. |

### Railway
| Setting | Default | Range | What it does |
|---|---|---|---|
| Landscaping (`allow_terraform`) | yes | | Level land under stations when no flat place is found. The levelling is in the cost estimate. The land under the track is never levelled. |
| Rail station length (`rail_station_length`) | 4 | 2–10 | Platform length in tiles; determines train length. |
| Double rail: loop station (`loop_station`) | on | | The destination gets a through station: trains enter at the front, use any platform, leave at the back and the return track turns around the station and runs right beside the incoming track (one-way traffic, no reversing). The source gets a small 2-platform station. Where there is no room, a normal end station is built. A later double line to the same destination becomes a branch: only the small station at its source is built, its track joins your inbound track and its return track leaves your return track. |
| Double rail station platforms (`rail_platforms`) | 4 | 2–8 | Big stations for double track: rows 0 and 1 get the line, the other platforms are linked to them and wait for later lines to join. Single track uses at most 2 platforms (enough for two trains to pass). If the big station fits nowhere, a smaller one is built. Through stations of a town list have 2. |
| New lines alongside your tracks (`follow_lines`) | yes | | Running right beside your existing tracks is cheaper for the route search, so lines form tidy corridors. |
| Trains between towns also carry mail (`rail_mail`) | yes | | Passenger trains get mail wagons right behind the engine (1 per 4 platform tiles, at least 1); the rest are passenger wagons. |
| Path signals at station entries (`station_signals`) | yes | | Double track: one-way signal before each station. Single track with 2 platforms: two-way signals, so 2 trains can pass in the stations. |
| Double rail: signal every N tiles (`signal_spacing`) | 5 | 2–20 | Signal spacing on double track (also on diagonal stretches; crossings and bridge heads are skipped). |

### Vehicles
| Setting | Default | Range | What it does |
|---|---|---|---|
| Vehicles: buses/trucks… (`veh_road`) | 2 | 0–20 | Buses or trucks for a new road. |
| Vehicles: trains… (`veh_rail`) | 1 | 0–10 | Trains for a new line (at most 2 on single track, see chapter 5). |
| Vehicles: buses for a town bus loop (`veh_loop`) | 1 | 0–10 | Buses for a town loop. |

### Bus loop
| Setting | Default | Range | What it does |
|---|---|---|---|
| Town bus loop: number of bus stops (`loop_stops`) | 5 | 2–8 | Number of stops. |
| Town bus loop: minimum distance… (`loop_gap`) | 4 | 2–10 | Minimum stop spacing. Smaller = closer together, but more coverage overlap. |

### Controls
| Setting | Default | What it does |
|---|---|---|
| Show the route search live (`search_preview`) | yes | While searching, *search* signs follow the path that got closest to the goal so far and move as the search goes on (every ~15 000 tiles examined); *search >* marks the tip. You can watch where it tries and where it gets stuck. All players see them; they disappear when the search ends. |
| Show the planned route with signs (`preview_signs`) | yes | Route preview signs. All players can see them; they disappear after confirming or cancelling. |
| Build right away without asking (`auto_confirm`) | no | Build immediately after planning without the Build button. A town list is always built without confirmation. |

---

## Benchmark (comparing script versions)

1. Make one test map: generate a game with a fixed *random seed* (World generation window), save it, e.g. `benchmark.sav`.
2. Switch on the setting **benchmark** and load that savegame.
3. The script plans a fixed set of test routes one after another and **builds nothing**, so the map stays the same:
   the 6 biggest towns each to their nearest town 20+ tiles away (the first one as double rail) and the first 4 industries
   (by id) to the nearest industry that accepts their cargo. On the same map it is always the same set.
4. For every route: found or not, ticks, tiles examined, retries, length, bridges, tunnels and cost. The summary
   (`Benchmark done: 9/10 routes found, … ticks, …k tiles examined`) goes to the Log and the history, failures to the Log,
   all lines to the debug page and the script debug window (lines starting with `BENCH`, easy to copy).
5. Load the same savegame with another version or other settings and compare the numbers.

---

## 8. Progress and messages

The **Progress** line (and the percentage in the page title):
| Text | Meaning |
|---|---|
| `1/3 station place at …` / `1/3 truck stop at …` | searching for station locations |
| `1/3 stations 2/5: …` | planning stations for a town list |
| `2/3 route search, part 3/8 (limit used 12%)` | route search. The bar = how close to the goal the search got, *part* = section between waypoints, *limit used* = portion of the limit used (at 100 % the script gives up) |
| `2/3 second track` | second track of double rail |
| `>>> READY TO BUILD <<< cost …, money after …` | route planned, press **Build** (the page title shows *[READY - press Build]* and a news message appears) |
| `3/3 building` | building |
| `paused, out of money` | waiting for **Resume** |

The result of every build is written to the **history**. "FAILED …" means the job failed, with the reason.
"NO MONEY …" means the build was over the cost limit.
"… piece(s) failed" means some pieces were not built and **the route may be broken**. The first failures with their
reason are in the **Log**, all of them in the script debug window (AI/Game Script Debug, GS tab).

---

## 9. Troubleshooting

| Problem | What to try |
|---|---|
| Search takes long | In OpenTTD's computer player settings raise **"Max number of opcodes before scripts are suspended"** (default 10,000, max 250,000). Fast-forward (Tab) also helps. |
| Something failed, but why? | Look at the **Log** on the Story Book page. |
| "No route found" | Shorten the distance, raise *search_limit*, allow longer bridges and tunnels. The script tries other station locations itself. |
| "No place for a … station" | Lower *rail_station_length*, use 1 platform for single track, enable *allow_terraform*, or pick another town. |
| Train doesn't run the whole route | Check the history for "piece(s) failed", "FAILED" or "Town list stopped". The line may be broken. |
| "Too expensive" | Higher *cost_limit_percent*, more money in the bank, or a shorter route. |
| Nothing happens, Status is stuck | The script may have crashed. Open the script debug window and look for red lines. |

---

## 10. Limitations

- **Check after building:** every planned track piece is checked; missing ones are built again. What still cannot be built
  is reported in the Log with its tile (X,Y) and the news message points there.
- Single track carries at most 2 trains (they pass in the stations). A town list on single track runs 1 train.
- The locomotive is chosen by speed, not by train weight. A weak locomotive with heavy cargo will be slow.
- Each line is a separate route; the script can't branch into an existing network.
- Double rail fails if the two tracks would have to cross.
- A route **search** in progress is not saved in the savegame; after loading, press Plan again.
  The preview and a build in progress are saved.
- The script does not demolish houses.
- The script has no automated tests yet; everything is verified manually in game.

---

## 11. For developers: code structure

| File | Contents |
|---|---|
| `info.nut` | metadata and all settings |
| `main.nut` | main loop, Story Book events, town list queue, save and load |
| `ui.nut` | page layout (versioned, `UI_VERSION`), status, progress, history |
| `jobs.nut` | jobs: PREP → SEARCH (→ SEARCH2) → CONFIRM → BUILD (→ PAUSED), town list station planning, retries, vehicles |
| `targets.nut` | towns and industries, cargo selection, station coverage |
| `astar.nut` | generic A* running in steps |
| `path_road.nut`, `path_rail.nut` | route rules for road and rail, tile cache |
| `build_road.nut` | bus stops, truck stops, depots |
| `build_rail.nut` | station layout (terminal and through), location search, station extension, switches, depot |
| `actions.nut` | build steps: execution, cost estimate in test mode |
| `vehicles.nut` | vehicle purchase, train composition, orders |
| `bench.nut` | benchmark mode: fixed test routes, results |
| `suggest.nut` | suggestions page: industry scan, income and cost estimate, Plan #N |
| `autopilot.nut` | autopilot: rounds of suggest, plan and build within a budget |
| `ship.nut` | ship lines from oil rigs: dock place, search over water, depot, ships |
| `advice.nut` | locomotive and wagon choice for bought trains |
| `loop.nut` | town bus loop |
| `preview.nut` | preview signs |
| `util.nut` | directions, neighbouring tiles, progress bar, bridge and tunnel helpers |

**Principles:**
- **Everything runs in small steps:** route search (A* in batches) and building (`build_per_tick` actions per step), so the game doesn't freeze and the script stays responsive to buttons.
- **A build = a list of actions** (tables `{ op = "rail", … }`). The same list is used in test mode for the cost estimate
  and is stored in the savegame.
- **Search state lives in the job** (`job`). Tile caches (`cc`, `xc`, `bc`, `tc`) save game API calls.
- **Company:** everything that builds or buys runs in `GSCompanyMode(company)`.
