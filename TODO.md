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
- [ ] **Loop station** (double rail, setting loop_station): through station at the destination, all platforms from one entry to one exit, return track starts at the back end and turns back; straight approach in front, the return track lies right beside it (tight loop); source gets 2 platforms; falls back to a normal end station when there is no room

## Known issues

- [ ] Signals at the transfer hub were messy once (fixed by hand: an added track at the hub, see screenshot 2026-10-26 013629) – the bridge rule and the check after building should cover it, verify
- [ ] Through stations of a town list: only 2 platforms, their back end is not linked to new platforms

## Next

- [ ] Commit and push as version 4 (raise the version in `info.nut` to 4 first)
- [ ] Junctions on an existing own line: a proper branch on a straight stretch without signals, flyover over the other track of a double line
- [ ] Survey of nearby industries and ranked suggestions with build buttons
- [ ] Autopilot with a budget, later cargo chains
- [ ] Cargodist support for transfers (if the server uses it)
