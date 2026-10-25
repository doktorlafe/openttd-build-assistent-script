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
3. Choose **Road** or **Rail**, click **Pick end A** and **Pick end B** on two towns, then **Plan route**.
4. Check the preview on the map and press **Confirm build**. Done: the line is built and vehicles are running



See the pictures below for the basics. The detailed manual follows after them.

A Game Script for **OpenTTD 15.x** (API 15) that builds transport connections for your company and buys
vehicles for them. It is controlled entirely from the **Story Book**, where each company has its own page.

**Features:**
- **roads** between two towns (buses) or for cargo from industry to industry or town (trucks),
- **railways**: single track, or double track with signals,
- **a list of up to 10 towns** connected as one through line that a single train runs from A to Z,
- **bridges, tunnels, level crossings** and perpendicular crossing of your own track,
- **terrain levelling** under stations and **extending an existing station** with more platforms,
- **route preview** with signs and a cost estimate before building,
- **automatic vehicle purchase** including orders,
- **train advice** (locomotive and number of wagons based on platform length),
- **town bus loop** (stops close together, a depot near the centre and a bus),
- **progress in percent** right in the Story Book.

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
| Build type | **Road**, **Rail**, **Double rail** | what will be built |
| Ends | **Pick end A**, **Pick end B** | click on the map: within 4 tiles of an industry = industry, otherwise the nearest town |
| List | **Add to list (many towns)**, **Clear list** | several towns in a row (chapter 4) |
| Selection | *Selection* line | type, ends or list, which cargo will be carried and from where |
| Controls | **Plan route**, **Confirm build**, **Cancel**, **Resume** | plan, confirm, cancel, continue after running out of money |
| State | *Status* and *Progress* lines | what is happening now and progress in percent |
| Train advice | 2 lines + **Train advice for a station** | chapter 5 |
| Bus loop | **Bus loop in a town** + result | chapter 6 |
| History | *Last builds* (5 lines) | the last five builds including errors |

The percentage is also shown in the **page title**, e.g. "Build assistant [45%]", so it is visible even when the page is scrolled.
A page from a savegame of an older version is rebuilt into the new layout automatically and the history is kept.

---

## 3. Building a single connection (A → B)

1. Choose the build type (**Road / Rail / Double rail**).
2. **Pick end A** and **Pick end B**: click on a town or near an industry.
3. **Plan route**: the script finds station locations and searches for a route. The game does not freeze meanwhile.
4. The route is shown on the map with signs (*route*, *bridge*, *tunnel*) and *Status* shows the length, number of bridges
   and tunnels, and the cost estimate.
5. **Confirm build** starts building, **Cancel** cancels it. If money runs out, building pauses and continues with **Resume**.
6. After building, the script buys vehicles (chapter 5) and writes the result to the history.

### What gets built
| Type | Stations | Route | Depot | Vehicles |
|---|---|---|---|---|
| Road, 2 towns | bus stops near the centres (if not already there) | road, reuses existing roads, stops and bridges | near the centre of the first town | buses (default 2) |
| Road, cargo | drive-through truck stops with a turnaround | road | next to the loading stop | trucks, full load at the source |
| Rail | station length × 1–2 platforms with switches | single track | past the end of the platform, in the same axis | 1 train |
| Double rail | station length × 2, both tracks linked | two parallel tracks, one-way path signals | past the end of the platform | trains as configured |

### Cargo
- **Two towns:** passengers.
- **Industry and anything:** the script picks a cargo that one end produces and the other accepts. It decides the direction itself,
  so it does not matter which end is A and which is B. If no such cargo exists, it says so already in *Selection*.

### Stations: where and how
A station location is searched in this order:
1. **Extending your station:** new platforms are placed alongside an existing station, with the same orientation
   and aligned with its end, and connected to it. A 2×7 thus becomes one 4×7 station with shared passengers.
2. **Flat free land** within 16 tiles of the town centre (or around the industry). The station must cover houses or the industry.
3. **A slope that gets levelled** (if *allow_terraform* is on). The levelling cost is included in the estimate.

The station exit must be free and the space for the depot behind the platform is kept free.
The script does not demolish houses, because that would hurt your town rating.

### Route rules
- **Road:** uses existing roads, goes straight through drive-through stops and also uses existing bridges and tunnels.
  It crosses rail only perpendicularly and only over a single straight track.
- **Rail:** must not turn on a slope, on a level crossing, or right after a bridge. Two turns in the same direction in a row
  (a 90° turn) are forbidden. It may cross your own straight unsignalled track perpendicularly. It does not cross other companies' tracks, but can bridge over them.
- **Long routes** are searched in parts: a waypoint is placed every *segment_length* tiles on the straight line between the ends
  and the route is searched part by part. A waypoint in water or in a town is moved to free land, and an unreachable waypoint is skipped.

### When no route is found
The script discards the station locations, finds others and tries again, up to 3 attempts in total.
A typical cause is a station surrounded by older track or roads. For a road between two town centres nothing can be retried.

---

## 4. Town list (up to 10) – one through line

1. Choose **Rail** (or **Road**).
2. Use **Add to list (many towns)** to click towns in the order you want to connect them. *Selection* shows
   the list (`Aton > Bury > Cefield`). The list takes priority over A/B, **Clear list** clears it.
3. **Plan route**: sections 1→2, 2→3, … are built one after another **without confirmation**. Each section must pass the cost limit.

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

## 5. Vehicles and train advice

### Automatic purchase
After a build finishes, the script buys vehicles, gives them orders and starts them from the depot:
- **buses and trucks:** the best available vehicle for the cargo (capacity × speed), refitted if needed,
- **train:** the locomotive from the advice (*Fast*) and wagons as long as the train fits the platform. The script measures the length
  **on the purchased train** and sells whatever sticks out, so it works with NewGRF vehicles too,
- **bus loop:** bus(es) with orders Loop 1 → … → Loop N.

Rules:
- additional vehicles are copies of the first with **shared orders**,
- for cargo from an industry the first order is **full load**,
- **single track always has only 1 train**, because without signals two trains would crash,
- if there is no money or no suitable vehicle, the script says so and the route stays built.

Counts are set in *Vehicles: …*; 0 means don't buy vehicles.

### Train advice
After a railway is built, **two trains** are listed below *Progress*:
- **Fast:** the fastest locomotive the company can buy that is powered on the given rail type,
- **Strong:** the locomotive with the highest tractive effort. **Cheap** is the cheapest locomotive, offered when the strongest is also the fastest.

Both include the wagon with the largest capacity for the carried cargo (preferably one that doesn't slow the train), the number of wagons
(platform length × 2 − 1 with standard vehicle length), train capacity and approximate price.

Click **Train advice for a station** and then a station: the script detects the rail type, the actual platform length
and the cargo (what is waiting at the station, or what is produced nearby). It also works for lines you built yourself.

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
| Maximum distance between the two ends (`max_distance`) | 150 | 10–1000 | Maximum distance of the ends (and of neighbouring towns in a list) in tiles. |
| Route search limit (`search_limit`) | 200 | 10–2000 | How many thousand tiles the search may examine before giving up. A section to a waypoint gets a quarter, at least 20 thousand. |
| Route search: tiles examined per step (`search_per_tick`) | 2000 | 100–20000 | Cap of one search batch. The script searches in batches of at most 300 tiles anyway so progress updates often, so the setting only matters below 300. |
| Long routes: search in parts of N tiles (`segment_length`) | 40 | 0–200 | Waypoint spacing for long routes. 0 = search the whole route at once (very slow for long routes). |
| Allow bridges (`allow_bridges`) | yes | | Bridges over water, roads and rails. |
| Allow tunnels (`allow_tunnels`) | yes | | Tunnels through hills. |
| Maximum bridge length (`max_bridge_length`) | 10 | 2–50 | Longest bridge in tiles. |
| Maximum tunnel length (`max_tunnel_length`) | 12 | 2–50 | Longest tunnel in tiles. |

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
| Rail stations: level sloped land… (`allow_terraform`) | yes | | Level a slope when no flat land is found. |
| Rail station length (`rail_station_length`) | 4 | 2–10 | Platform length in tiles; determines train length. |
| Rail station platforms on single track (`rail_platforms`) | 2 | 1–2 | Platforms for single track. Double track always has 2. |
| Double rail: signal every N tiles (`signal_spacing`) | 5 | 2–20 | Signal spacing on double track. |

### Vehicles
| Setting | Default | Range | What it does |
|---|---|---|---|
| Vehicles: buses/trucks… (`veh_road`) | 2 | 0–20 | Buses or trucks for a new road. |
| Vehicles: trains… (`veh_rail`) | 1 | 0–10 | Trains for a new line (at most 1 on single track). |
| Vehicles: buses for a town bus loop (`veh_loop`) | 1 | 0–10 | Buses for a town loop. |

### Bus loop
| Setting | Default | Range | What it does |
|---|---|---|---|
| Town bus loop: number of bus stops (`loop_stops`) | 5 | 2–8 | Number of stops. |
| Town bus loop: minimum distance… (`loop_gap`) | 4 | 2–10 | Minimum stop spacing. Smaller = closer together, but more coverage overlap. |

### Controls
| Setting | Default | What it does |
|---|---|---|
| Show the planned route with signs (`preview_signs`) | yes | Route preview signs. All players can see them; they disappear after confirming or cancelling. |
| Build right away without asking (`auto_confirm`) | no | Build immediately after planning without the Confirm build button. A town list is always built without confirmation. |

---

## 8. Progress and messages

The **Progress** line (and the percentage in the page title):
| Text | Meaning |
|---|---|
| `1/3 station place at …` / `1/3 truck stop at …` | searching for station locations |
| `1/3 stations 2/5: …` | planning stations for a town list |
| `2/3 route search, part 3/8 (limit used 12%)` | route search. The bar = how close to the goal the search got, *part* = section between waypoints, *limit used* = portion of the limit used (at 100 % the script gives up) |
| `2/3 second track` | second track of double rail |
| `route ready, waiting for Confirm build` | route planned |
| `3/3 building` | building |
| `paused, out of money` | waiting for **Resume** |

The result of every build is written to the **history**. "FAILED …" means the job failed, with the reason.
"… piece(s) failed" means some pieces were not built and **the route may be broken**. Details are
in the script debug window (AI/Game Script Debug, GS tab).

---

## 9. Troubleshooting

| Problem | What to try |
|---|---|
| Search takes long | In OpenTTD's computer player settings raise **"Max number of opcodes before scripts are suspended"** (default 10,000, max 250,000). Fast-forward (Tab) also helps. |
| "No route found" | Shorten the distance, raise *search_limit*, allow longer bridges and tunnels. The script tries other station locations itself. |
| "No place for a … station" | Lower *rail_station_length*, use 1 platform for single track, enable *allow_terraform*, or pick another town. |
| Train doesn't run the whole route | Check the history for "piece(s) failed", "FAILED" or "Town list stopped". The line may be broken. |
| "Too expensive" | Higher *cost_limit_percent*, more money in the bank, or a shorter route. |
| Nothing happens, Status is stuck | The script may have crashed. Open the script debug window and look for red lines. |

---

## 10. Limitations

- **No post-build check yet:** when a piece of track fails to build, the script only reports it as "piece(s) failed" and doesn't fix it.
- Only one train runs on **single track**. Through stations don't have signals yet, so trains can't pass each other in them.
- The locomotive is chosen by speed, not by train weight. A weak locomotive with heavy cargo will be slow.
- Each line is a separate route; the script can't branch into an existing network.
- Double rail fails if the two tracks would have to cross.
- A route **search** in progress is not saved in the savegame; after loading, press Plan route again.
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
| `advice.nut` | train advice, platform length, station cargo |
| `loop.nut` | town bus loop |
| `preview.nut` | preview signs |
| `util.nut` | directions, neighbouring tiles, progress bar, bridge and tunnel helpers |

**Principles:**
- **Everything runs in small steps:** route search (A* in batches) and building (`build_per_tick` actions per step), so the game doesn't freeze and the script stays responsive to buttons.
- **A build = a list of actions** (tables `{ op = "rail", … }`). The same list is used in test mode for the cost estimate
  and is stored in the savegame.
- **Search state lives in the job** (`job`). Tile caches (`cc`, `xc`, `bc`, `tc`) save game API calls.
- **Company:** everything that builds or buys runs in `GSCompanyMode(company)`.
