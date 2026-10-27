# To-do

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

## Known issues

- [ ] Signals at the transfer hub were messy once (fixed by hand: an added track at the hub, see screenshot 2026-10-26 013629) – the bridge rule and the check after building should cover it, verify
- [ ] Through stations of a town list: only 2 platforms, their back end is not linked to new platforms

## Next

- [ ] Commit and push as version 4 (raise the version in `info.nut` to 4 first)
- [ ] Junctions on an existing own line: a proper branch on a straight stretch without signals, flyover over the other track of a double line
- [ ] Survey of nearby industries and ranked suggestions with build buttons
- [ ] Autopilot with a budget, later cargo chains
- [ ] Cargodist support for transfers (if the server uses it)
