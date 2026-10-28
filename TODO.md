# To-do

## Test (version 6, light mode)

- [ ] light_mode on: only the pages tools + help; switching it off brings the full pages back
- [ ] Buy trains: coal mine > power plant gives a coal train as long as the platform, full load at station 1
- [ ] Buy trains with How many = 3: three trains with shared orders
- [ ] Copies of a train: N copies, also when the train is out on the line (nearest depot)
- [ ] Fill wagons: a short train goes to a depot, gets wagons, leaves; a too long one loses wagons
- [ ] Connect two ends: straight ends, a curve end, ends 2 tiles apart, a long way over a hill/river (bridge)
- [ ] Connect double track: 2 clicks connect both tracks, side by side with no gap, ends on the right sides
- [ ] Find stations from the depot: a loop of 4 towns comes out in travel order, Buy trains runs over all of them
- [ ] Light: Plan road / Build road between two towns and between two industries (trucks)
- [ ] Fleet care report: lines with waiting cargo and queues appear in the log, nothing bought
- [ ] Fleet care on: a vehicle is added to a full line, a queued one is sold; mode kept after save/load
- [ ] Connect: out of money in the middle, Build connection goes on; Cancel removes the signs

## Test (new since version 3, not committed yet)

- [ ] **My tracks** (experimental): new railway runs on your own tracks and joins them; falls back to all-new track when it finds no way
- [ ] **Thrifty My tracks**: lines to the same place share one corridor, plan summary shows "% saved"
- [ ] **Help page** in the Story Book (what every button does)
- [ ] **Big stations**: 4 platforms by default, only rows 0/1 get a line, the others are linked and wait
- [ ] **Joining a big station**: a later line to the same place uses a free platform row ("Station at …: free platform row …" in the Log)
- [ ] **One big station**: new platforms beside an own station are linked both ways with the old ones
- [ ] **Ctrl trick (distant join)**: one joined station tile next to an industry the big station does not cover
- [ ] **Coverage**: industry stations as far from the industry as the coverage allows
- [ ] **Bridges**: max 60 tiles, bridges over own tracks (flyovers), no bridge landing right in front of a station entry
- [ ] **Landscaping**: curves on slopes (foundation, else levelling), steep slopes levelled, "N tile(s) … levelled" in the Log
- [ ] **Faster station search**: big flat, small flat, then levelled land (max 500 places)
- [ ] **Hills**: route goes straight over hills instead of hesitating
- [ ] **Transfer**: feeder to the nearest station your trains carry the cargo from (Log says what was checked when it finds none)
- [ ] **Follow lines**: new lines run alongside your existing tracks
- [ ] **Check after building**: missing track pieces found and built again, the rest reported with tile X,Y
- [ ] **Station choice**: Log says what was chosen at each end; a retry changes only the station where the search got stuck
- [ ] **Benchmark**: setting "benchmark" + fixed savegame, BENCH lines and the summary
- [ ] **Branch onto a loop line** (double rail): a second line to the same destination builds only the small station at the source; its tracks join the inbound track and leave the return track of the first line (bridge over the other track where needed)
- [ ] **Loop station** (double rail, setting loop_station): through station at the destination, all platforms from one entry to one exit, an exit signal behind every platform, return track starts at the back end and turns back; straight approach in front, the return track lies right beside it (tight loop); source gets 2 platforms; falls back to a normal end station when there is no room
- [ ] **Faster route search**: neighbour tiles and the estimate by plain arithmetic (no GSMap calls), rail tile cache; compare the benchmark with the old version (BENCH summary: ticks, tiles examined)
- [ ] **Diagonals** (idea from ChooChoo): diagonal track costs 4 per tile instead of 5 (shorter for trains), entering/leaving a diagonal costs 2 - routes should show long straight and long diagonal runs, no zigzags
- [ ] **Room beside the line**: tiles next to houses, water or industries cost 1 more, the line keeps a little distance
- [ ] **Second track on steep slopes**: a steep tile that cannot be levelled is no longer taken as "next to the first track" (it was a bug)
- [ ] **Best station place**: of the first 6 places that fit (flat land), the one with free straight tiles in front, facing the other end and (towns) covering more houses ("best of N (score S)" in the script log)
- [ ] **Test run check**: track pieces that fail the test run make the route plan once more around them ("failed the test run ... planning the route again" in the Log)
- [ ] **Story Book**: the same text is not sent again (fewer game commands while searching)
- [ ] **Second track can get in**: double track keeps the 3 tiles in front of the second platform free during the first search (start station, and the end station without a loop) - benchmark route 10 (Úval - Zadní Vyševník) must no longer stall "1 tile from the goal"
- [ ] **Fail fast**: second track whose station entry is taken fails at once ("the way into the station is taken"); a search that gets within 3 tiles of the goal and no closer for 20k tiles stops; second track stops after 40k tiles without getting closer
- [ ] **Suggestions page** (step 1): own Story Book page "Build assistant - suggestions", Suggest button lists the 5 best cargo railways (30..150 tiles, sources carried < 100%) with cost, profit/year, trains and payback; check on BENCHMARK-LAFE.scn that the top routes make sense and the Plan cost is close to the estimate
- [ ] **Suggestions step 2**: travel time at 3/4 top speed + half the full-load wait counts as cargo days ("~N days on the way" on each line, "days (fill F)" in SUG lines); Plan #N button fills A/B (rail), plans and opens the build page
- [ ] **Ship line step 1** (oil rig -> refinery): A = oil rig, B = refinery, "Ship: plan" finds a dock place within reach of B that the water from the rig reaches (SHIP lines in the debug window), "Ship: build" builds dock + water depot + 1..3 ships with orders (full load at the rig)
- [ ] **No levelling under track**: rail routes only use sloped tiles where the piece fits as the land is (foundation), steep slopes are avoided or bridged; levelling only under stations. Check: a long route over hills has no holes, no "HOLE" signs
- [ ] **Autopilot**: button on the suggestions page OFF -> BUILD -> PLAN ONLY; BUILD builds route after route until switched off (next round right after a build, sources already connected are not taken again, up to 20 candidates); when nothing fits it waits ap_interval months; Suggest, plan the best suggestion within ap_budget_percent of the bank, skip a failed plan or one dearer than budget / 1.5x the estimate and plan the next; PLAN ONLY reports "WOULD BUILD", BUILD builds; never touches a player's job; mode saved; setting ap_allowed switches it off for everyone (AP lines in the debug window)
- [ ] **Benchmark switch**: switching "benchmark" on in-game starts it; 4 long routes (~250 tiles) added

## Known issues

- [ ] Signals at the transfer hub were messy once (fixed by hand: an added track at the hub, see screenshot 2026-10-26 013629) – the bridge rule and the check after building should cover it, verify
- [ ] Through stations of a town list: only 2 platforms, their back end is not linked to new platforms

## Next

- [ ] Commit and push as version 4 (raise the version in `info.nut` to 4 first)
- [ ] Junctions on an existing own line: a proper branch on a straight stretch without signals, flyover over the other track of a double line
- [ ] Survey of nearby industries and ranked suggestions with build buttons
- [ ] Autopilot with a budget, later cargo chains
- [ ] Cargodist support for transfers (if the server uses it)
- [ ] Auto: double track from station A and from station B, not joined; within a few days it gets connected beside itself.
- [ ] Auto: a depot on the A-B line gets trains after the connection; a second depot on the same line does not.
- [ ] Auto: a track end pointing nowhere near another end stays as it is; Auto off = nothing happens by itself.
