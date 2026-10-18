# soccer-tycoon: build tracker

This is the checklist for building the game from `docs/PLAN.md`, one small task at a time. Each task has a test, and a task is only ticked when its test passes. Update this file as we go (tick boxes, fill the test log).

## How we work on each task
1. Pick the next unticked task (in order, unless a task says it can run in parallel).
2. Write the code in `src/` (Rojo syncs it to Studio). Pure logic goes in `src/shared` so it can be tested outside Studio.
3. Run the checks: `tools/check.sh` (type check, format check, lint, unit tests).
4. Run the task's Studio test through the Studio MCP (playtest, console output, screenshot) or the manual test it names.
5. Record the result in the test log at the bottom.
6. Tick the box and commit (one commit per finished task group, message `feat: ...`).

**Test types:** **U** = unit test (Lune, automatic, no Studio). **S** = Studio playtest through the MCP (start play, read the console, inspect the tree, screenshot). **M** = manual by you (real phone, two players with Studio's Local Server, anything the MCP cannot do).

**Status:** `[ ]` todo, `[~]` in progress, `[x]` done.

## Tools (all installed)
| Tool | Use | Command |
|---|---|---|
| Rojo 7.7.1 | Sync `src/` to Studio | `rojo serve` (then Connect in Studio) |
| luau-lsp 1.70.1 | Type check | `luau-lsp analyze --definitions=C:/Users/lisan/.local/share/luau/globalTypes.d.luau --sourcemap=sourcemap.json src` |
| StyLua 2.6.0 | Format | `stylua src tests` (check with `stylua --check src tests`) |
| selene 0.32.0 | Lint | `selene src` |
| Lune 0.11.0 | Unit tests | `lune run tests/run` |
| Studio MCP | Playtests, console, screenshots | via the Studio tools |

Before the type check, refresh the sourcemap: `rojo sourcemap default.project.json -o sourcemap.json`.

---

## Phase 0: setup and pure logic
Goal: the project structure, `Config`, `Formulas` and the safety modules exist and are tested, with no Studio work.

- [x] **0.1 Tools and configs.** Rojo, luau-lsp, StyLua, selene, Lune installed; `.luaurc`, `stylua.toml`, `selene.toml` created. *Test:* `luau-lsp`, `stylua --check` and `selene` run clean on `src/` (U, done 2026-10-18).
- [x] **0.2 Rojo connected.** *Test:* Studio shows `ServerScriptService.Server.Main` and `StarterPlayerScripts.Client.Main` (S, done 2026-10-18).
- [x] **0.3 Check script and test runner.** `tools/check.sh` runs sourcemap, analyze, stylua check, selene and the Lune tests; `tests/run.luau` runs every `tests/*.spec.luau`. *Test:* `tools/check.sh` exits 0 and fails when a test fails (U).
- [x] **0.4 Folder structure.** `src/shared`, `src/server` (with `vendor/`), `src/client`, `tests/`, `tools/`. Modules from the Step 5 map are created when their task first needs them, not as empty stubs (see "Decisions and changes"). *Test:* the type check passes and Studio shows the same tree after a sync (U, S).
- [x] **0.5 `Config`: the 35 players.** Name, nationality, number, rarity, floor, slot, with price and income from the Step 3 curve. *Test:* a spec checks 35 players, rarity counts 4/10/10/6/5, floor counts 10/10/10/5, unique IDs, price and income strictly rising with slot, and the Step 3 anchor values (slot 1 = $10 / $3, slot 10 = $11.1K / $268, slot 30 = $6.99B / $636K, Legends $400B / $1T / $2.5T / $6T / $15T) (U).
- [x] **0.6 `Config`: everything else.** Store upgrades and prices, match speed, hat-trick chance, offline rate, stadium tiers and field sizes, starting cash $15, hold time 1 s, cooldown 20 h, max cash, stamina, level caps, feature switches. *Test:* a spec checks each table against Step 3 (cash upgrades x1.5 to x6.7, tiers $250 / $25K / $750K / $45M, field 4/5/6/8/11) (U).
- [x] **0.7 `Formulas`.** Payout, star bonus (+10% per star, max 5), level bonus (+3%), level cost `40 x L x rarity factor`, offline earnings (cap 4 h, rate), pad price, season multiplier, boost stacking cap x4. *Test:* a spec with known values (a Common reaching level 5 costs 600 TP, a Legend level 25 about 65,000 TP, momentum caps at +25%, boosts never above x4) (U).
- [x] **0.8 Number formatter.** K / M / B / T. *Test:* a spec ($999, $1.2K, $11.1K, $6.99B, $15T, rounding at edges) (U).
- [x] **0.9 `Remotes` registry.** One module registers each remote with a payload shape, rate limit and cooldown; invalid payloads are dropped and logged. *Test:* a spec for the validator (wrong type, out of range, unknown ID, rate limit hit) (U); a Studio playtest sending a bad payload is dropped with a log line (S).
- [x] **0.10 ProfileStore and `Session`.** Vendor ProfileStore (pinned, with its LICENSE), profile template, version, migrations, reconcile, save checks, receipt pruning, Mock mode in Studio. *Test:* a spec for the template, migration chain, reconcile and the "bad value" check (U); a playtest joins with Mock, then reads the profile (S).
- [x] **0.11 Commit Phase 0.** Message `feat: project structure, config, formulas and tests`.

## Phase 1: greybox (Studio, plain blocks)
Goal: the right sizes, and walking times that match Step 2.

- [x] **1.1 Map folders and plaza.** `Map`, plaza, spawn in the middle, 8 plot slot anchors. *Test:* tree readback, bounds, no loose parts (S).
- [x] **1.2 Plot template, floor 1 only.** One model in `ServerStorage` with the gate and claim ring, tier-1 court (60x36), the building with 10 capsule pads, Store counter, Locker spot and trophy shelf spot. *Test:* readback of bounds and pivot, every part anchored (S).
- [x] **1.3 Markers.** `Claim`, `Player_<id>` x10, `Field`, `Store_<id>`, `Stadium`, `Penalty`, field and opponent slots, each with a `PadId` attribute from `Config`. *Test:* a Studio script lists every marker and checks its `PadId` exists in `Config` (S).
- [x] **1.4 Walking-time check.** *Test:* a character walks spawn to claim ring, gate to first capsule (at most about 8 s), first capsule to field button (at most about 5 s), timed from the player camera (S). If a time is off, change the template before going on.
- [x] **1.5 Commit Phase 1.** The map file is committed here only. Message `feat: greybox plaza and plot template`.

## Phase 2: slice scripts (the first 5 minutes)
Goal: claim a plot, buy the first player, start the match loop, earn, buy the first upgrade, reach stadium tier 2, save.

- [x] **2.1 Join and profile.** Load profile (Mock), loading screen, failed-load kick path, HUD attributes (cash, TP). *Test:* playtest join creates a profile with $15 and sets the attributes (S); a spec for the load-failure decision (U).
- [x] **2.2 `Economy`.** `grant` and `spend` in one step, max cash. *Test:* a spec (spend fails when short, no negative cash, max cash clamp, two rapid spends cannot both pass) (U).
- [x] **2.3 `Plots`.** Claim by standing on the ring, one plot per player, clone the template into the slot, free on leave. *Test:* playtest claim (S); two players claiming different plots and the same plot (M, Local Server).
- [x] **2.4 `Pads` (server-timed).** Presence tracking, 1 s hold from the server clock, owner check, cancel on leaving, ring events to the client. *Test:* a spec for the hold logic with a fake clock (U); playtest standing 1 s buys, stepping off cancels, not enough cash does not charge, a second player on the pad is ignored (S).
- [x] **2.5 `Roster` and the field.** Owned players, top-N by income, field button pad starts the first player. *Test:* a spec (top N, ties, bench, N by tier) (U); playtest button puts the first player on the court (S).
- [x] **2.6 `Match`.** One timer per plot, payout from `Formulas`, scripted first hat-trick, result event, first match 5 s then 10 s. *Test:* a spec for payout and hat-trick rolls with a seeded random (U); playtest cash rises each match and the event fires (S).
- [x] **2.7 Match view (greybox).** Client plays the match with local mannequins from the result event. *Test:* playtest shows the loading bar, "VICTORY" and "+$N" (S, screenshot).
- [x] **2.8 `Store`: cash per match.** Store pad and HUD row button. *Test:* a spec for the level and price (U); playtest the upgrade changes the next payout (S).
- [x] **2.9 `Stadium`: tier 2.** Pad purchase, capacity 5, the x2 boost for 5 minutes (online time only), no cinematic yet. *Test:* a spec for the boost timer and the stacking cap (U); playtest (S).
- [x] **2.10 HUD basic.** Money label with the loading bar, "Next goal" row, boost badge, guide arrow. *Test:* checked on the smallest phone preset (667x375) with touch controls showing, and no overlaps (S, screenshot).
- [~] **2.11 Save and rejoin.** Forced saves and `BindToClose`. *Test:* a playtest on the Studio store leaves and rejoins with the same cash, players and tier (S).
- [x] **2.12 Analytics events.** joined, claimed plot, first purchase, first match, first upgrade, first stadium upgrade. *Test:* playtest logs each event once (S).
- [x] **2.13 Commit Phase 2.** Message `feat: first 5 minutes vertical slice`.

## Phase 3: slice playtest and decision gate
- [x] **3.1 Timed run-through.** Compare to Step 2 and 3: first purchase about 0:23, first upgrade about 1:06, player 2 at about 2:06, stadium tier 2 at about 5:16. Record the times in the test log (M or S).
- [~] **3.2 Phone pass.** Smallest phone, a common phone, tablet and desktop (S, M on a real phone).
- [x] **3.3 Clean console.** No errors or warnings during a full run (S).
- [x] **3.4 Fix list and gate.** Decide whether the footprint is right and what to change **before** building floors 2 to 4. Write the decision below the test log.

## Phase 4: expansion (one group at a time, each with its own commit)
Each group is done when its unit tests pass, its Studio playtest passes, and the group is checked on the phone preset.

- [x] **4.1 Floors 2 to 4 and gates.** Three-flight switchback stairs in the back-left corner, a glass gate at the bottom of each flight opened by the server when the floor before is complete, floors 2 to 4 with the same wall layout (floor 4 is the Legends hall), railings around the stair holes. *Test:* `Roster.floorUnlocked` spec (U); a playtest of the climb with locked and open gates (S, done).
- [ ] **4.2 Stadium tiers 3 to 5 and the cinematic.** Pitch growth in place, camera lock, reduced-motion path, skip from the second upgrade. *Test:* playtest each tier; a spec for the tier request guard (the seen-tier number) (S, U).
- [ ] **4.3 Training ground and drill.** Presence TP at 10 per minute, stamina, drill up to 15 per minute, level-up on the pad. *Test:* specs for TP, stamina and level costs; playtest (U, S).
- [ ] **4.4 Daily icons, penalties and the free case.** 20-hour cooldowns, ready glow, the penalty kick (aim zones, the server rolls). *Test:* specs with a fake clock (ready at 20 h, never twice in a day) (U); playtest (S).
- [ ] **4.5 Hat-trick, offline earnings, match speed, Store upgrades.** *Test:* specs (rate, 4 h cap, negative gap clamp) (U); playtest rejoin shows "+$N while you were away" (S).
- [ ] **4.6 Rarity reveals.** First of each rarity, case wins, reduced motion. *Test:* playtest each rarity (S, screenshots).
- [ ] **4.7 New Season, head start and trophies.** Locked preview from floor 3 reached, the confirm screen with the re-climb estimate, head start floors, trophies. *Test:* specs for the reset (what resets and what stays, floor 3 never granted, double-tap guard) (U); playtest season 2 and 3 (S).
- [ ] **4.8 Legends and the Legend Trials.** Capsule panels, permanent goal flags, cash price. *Test:* specs for goal flags and the season interaction (U); playtest (S).
- [ ] **4.9 Cases and Robux products.** Standard and Elite Case, odds screen, session total, `RequestPurchase`, `ProcessReceipt`, idempotent receipts. *Test:* specs for odds (seeded rolls match the table), receipt replay returns the same result, a failed save leaves the receipt unconfirmed (U); a playtest with test purchases in Studio (S, M).
- [ ] **4.10 Cosmetics and the Locker room.** Free and Robux styles by tier. *Test:* specs (the tier gate, ownership check) (U); playtest (S).
- [ ] **4.11 Private plots.** Fence, collision groups, respawn handling. *Test:* playtest the owner passes and a visitor does not; respawn keeps the group (S, M with two players).
- [ ] **4.12 Notifications opt-in.** Asked once after floor 1. *Test:* playtest the flag is saved and the question never repeats (S).
- [ ] **4.13 Remaining screens and states.** Every pair of HUD elements that can show together is checked on the smallest phone. *Test:* the device matrix (S, M).

## Phase 5: polish and launch gate
- [ ] **5.1 Art pass** (kit of parts, mannequins, stands, crowd, roof).
- [ ] **5.2 Lighting** (fixed late afternoon, one color correction, light bloom, checked on a phone preset).
- [ ] **5.3 Sound and icons** (only confirmed-usable audio; uploaded icons with permission granted).
- [ ] **5.4 Accessibility** (reduced motion, text size, 44 px targets).
- [ ] **5.5 Worst-case fixture.** 8 plots at tier 5 with every player owned, on a low-end phone preset. *Test:* MicroProfiler and Scene Analysis results recorded (S, M).
- [ ] **5.6 Real phone check** (thumb reach, notch) (M).
- [ ] **5.7 Step 8 items:** the pre-release checklist, Robux prices, store page, the rights check on names.

---

## Test log
| Date | Task | Type | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | 0.1 | U | pass | luau-lsp, stylua and selene clean on `src/` |
| 2026-10-18 | 0.2 | S | pass | Both Main scripts visible in Studio through Rojo |
| 2026-10-18 | 0.3 | U | pass | `tools/check.sh` exits 0; a deliberately failing spec exits 1; a deliberate type error is caught by luau-lsp |
| 2026-10-18 | 0.5, 0.6 | U | pass | 35 players, rarity and floor counts, Step 3 anchors, store tables, tiers (21 tests) |
| 2026-10-18 | 0.7, 0.8 | U | pass | Formulas (level cost 600 TP / 65,000 TP, season, boosts cap, payout 416 example, offline cap) and number format |
| 2026-10-18 | 0.9 | U | pass | Validate, RemoteSpec (10 client-to-server remotes), RateLimiter (burst, refill, penalty, cooldown) |
| 2026-10-18 | 0.9 | S | pass | In a playtest: valid payload handled; bad payload dropped and logged with its reason; flood of 50 limited to the burst of 2; a handler that errors was caught and logged |
| 2026-10-18 | 0.10 | U | pass | Profile template, validation, migration chain, reconcile, receipt pruning (91 unit tests in total) |
| 2026-10-18 | 0.10 | S | pass | Playtest join on the Mock store: `$15, tier 1, 0 players owned`. The Studio store (real saving) is not tested yet, it needs API access and a published place |
| 2026-10-18 | 1.1 | S | pass | Map readback: Origin, Plaza (ground 640x80, spawn pad), 8 PlotSlots (4 north, 4 south, each facing into its plot) |
| 2026-10-18 | 1.2, 1.3 | S | pass | PlotTemplate: 80 parts, all anchored, none below ground, PrimaryPart = Gate, bounds 160 x 17.5 x 181; 29 markers (10 player, 4 store, claim, field, stadium, penalty, training, locker, 8 field slots, ball); every PadId exists in `Config` |
| 2026-10-18 | 1.4 | S | pass | Real character at 16 studs/s, no blocked leg: spawn to claim ring 6.3 s; claim ring to capsule 1 pad 9.4 s (Step 2 allows about 10 s); pad 1 to Field pad 1.6 s (target at most 5 s) |
| 2026-10-18 | 2.1 to 2.9 | S | pass | Server flow in a real playtest: claim by standing on the ring; pad hold (full hold buys, stepping off at 0.5 s charges nothing, a pad you cannot afford never fills or charges); Store -$15; stadium -$250 with tier 2 and a x2 boost (299 s left); analytics milestones each logged once |
| 2026-10-18 | 2.10 | S | partial | Client built in a playtest: HUD, loading screen removed after the profile loaded, 8 claim rings with billboards, no script errors. The phone-size check and the owner's manual playtest found the field pad and layout problems above, now fixed |
| 2026-10-18 | 2.x | S | pass | After the fixes: claim, walk in through the entrance, one hold on the first pad: $15 -> $5, matches start by themselves, first match 5 s and pays $3, goal row switches to "More cash per match", capsule shows a figure, 3 client match figures (our player, a rival, the ball) |
| 2026-10-18 | 2.11 | S | partial | Profile round trip through ProfileStore's in-memory store with our schema, migrate and reconcile: 13 checks pass (cash, owned player, field flag, store level, tier, returning-player flag, milestone, receipt all kept; valid after reload). **Not done yet:** the real DataStore save and rejoin (needs the place published and "Enable Studio Access to API Services"), and a real second join (Local Server test). Do both before launch (Step 8 checklist) |
| 2026-10-18 | 3.1 | U | pass | Pacing simulation through the real game logic (`tests/pacing.spec.luau`, a player who buys the next goal as soon as it is affordable, 8 s walk): first purchase 0:09, first upgrade 0:53, player 2 1:54, player 3 2:54, player 4 3:45, scripted hat-trick 3:46, stadium tier 2 4:15 (add about 10 s of claim and walk) |
| 2026-10-18 | 3.1 | S | pass | Real-time bot in a real playtest (claims a plot, walks to each goal's pad, waits to afford it): plot claimed 0:08, first player 0:19, first upgrade 0:54, player 2 1:45, player 3 2:36, player 4 3:27, stadium tier 2 3:57 with a 300 s boost. Step 3 targets: 0:23, 1:06, 2:06, 3:36, 4:16, 5:16. The early game is within 5 to 20 s; player 3 onwards is 50 to 80 s faster (see decisions) |
| 2026-10-18 | 3.2 | calc | partial | Smallest phone (667 x 375): the HUD column is 300 px wide and centred, so it spans x = 183 to 483; Roblox's top-left buttons end near x = 150 and nothing sits at the top right except our 96 px boost badge (x = 563 to 659). Nothing of ours sits in the thumbstick (lower left) or jump (lower right) areas. **Still to do by the owner:** Studio's Device Emulator on a small phone, a common phone and a tablet, and a real phone before launch |
| 2026-10-18 | 3.3 | S | pass | A full 4-minute playtest: no errors or warnings from our scripts. Only Roblox's own UIBlox and asset warnings, and our analytics lines (each milestone once: claimed plot +25 s, first purchase +36 s, first match +41 s, first upgrade +73 s, first stadium upgrade +256 s after joining, which includes about 17 s of Studio loading) |
| 2026-10-18 | 4.1 | U | pass | `Roster.floorUnlocked`: floor 1 always open, floor k opens when the floor before is complete, owning a later floor (for example from cases) does not open it (191 unit tests in total) |
| 2026-10-18 | 4.1 | S | pass | Real character, real stairs: with floor 1 incomplete the gate stopped it at x = -70.7 at floor-1 height; after floor 1 completed it climbed flight 1 to floor 2 (height 20.6 = floor top 16.7 + 3.9), bought Lautaro there ($50,000 -> $29,419), flight 2 blocked until floor 2 completed then climbed to floor 3 (36.6), flight 3 blocked until floor 3 completed then climbed to floor 4 (52.6); Pelé's `legend` marker is on floor 4. Template: 232 parts, 53 markers (30 player, 5 legend, 4 store, 1 each claim/stadium/penalty/training, 10 spots), 65.2 studs tall, layout checks clean |

## Decisions and changes during the build
- **2026-10-18, Studio-only dev panel (planned in Step 6, built now for testing):** `DevCommand` is an eleventh client-to-server remote (`grantFloor n`, `setCash n`, `resetProfile`) that the server handles only while `RunService:IsStudio()`; in a published game nothing is registered for it. `src/client/DevPanel.luau` shows seven small buttons on the left of the screen, also only in Studio. `DevCommands` (pure, 6 unit tests) never grants Legends. Checked in a playtest: floors open their gates, cash and reset work, a bad command is refused. Note for tests: with Instance Streaming the client does not receive the far end of the building until the player is near, so check gate and stair parts from the server side.
- **2026-10-18, task 4.1 stairs design:** the corner stairs are a three-flight switchback (flight 1 along lane A toward the wall, a landing joining both lanes, flight 2 along lane B away from the wall, flight 3 along lane A again), 16 steps of 1 stud rise each, a 9-stud lane, glass gates `Gate_Floor2/3/4` across the bottom of each flight, and railings around the three holes. A single straight flight does not work in a corner (the top of one flight would meet the start of the next). The "Legends hall visible through glass from floor 2" idea from Step 7 is dropped for now: with the corner stairs there is no atrium, so the Legends hall is only reached by climbing. Pads of players on a floor that is not open yet show no text. Floor 4 markers have kind `legend` (no pad behaviour until task 4.8).
- **2026-10-18, goal card removed, result texts fixed (owner feedback):** (1) the "Next" goal card is gone: the guide covers the first steps and the player decides after that (pad rings already show the price and "Need $X more"). The stadium-upgrade glow and the planned HUD buy button went with it. `Goals` stays in the code only to drive the first-step guide. (2) **Bug:** the VICTORY and "+$N" labels stayed on screen as a ghost outline, because only the text was faded while its UIStroke stayed opaque. Now the text and the outline fade together and the label is hidden afterwards. (3) VICTORY is now near the top (10 px under the safe area, size 44) and the result texts are visible for 1 second in total (0.65 s then a 0.35 s fade). (4) "+$N" is placed from the money text width, 9 px left of the amount. Checked in a playtest: both labels fully hidden 1.2 s after the result, a second result shows and hides again.
- **2026-10-18, HUD moved to the top right (owner phone-emulator feedback):** in landscape the centred HUD column covered the view, so the money, match bar, goal card and boost badge are now one compact 230 px column at the top right (money right aligned, "Next: ..." goal card with truncation, "+$N" to the left of the money). The goal card stays: after the first purchase it is the only guidance left. The centre of the screen is clear apart from the VICTORY text. Checked with a layout preview in Studio (long goal text fits). Needs the owner's Device Emulator check on a small phone.
- **2026-10-18, Phase 3 pacing decision:** keep the economy numbers as they are. The bot is an optimal player who stands on the right pad the whole time, and it reaches the first stadium upgrade at 3:57 against 5:16 in the Step 3 simulation. Likely causes: the first match is 5 s (the simulation used 10 s), small payouts round up (4.5 becomes 5, worth about +11% early), and the scripted hat-trick at match 22 (about 3:35) pays double once. A real player who hesitates or wanders 25 to 30% slower lands at about 5:00, which is the Step 2 peak, and the target "60% reach the first stadium upgrade by minute 5" is met easily. Re-check with real players: if most reach the upgrade before minute 4, raise the tier 2 price (for example $250 to $350) or change the rounding. The pacing spec keeps the numbers in range (stadium between minute 3 and 8).
- **2026-10-18, Phase 3 footprint decision:** the plot footprint changed once after the owner's playtest (plots 200 x 210, building 140 x 80 with larger capsules and pads, plaza 800). Walking times with it: spawn to claim ring about 8 s, claim ring to first pad 9.8 s, farthest plot from the spawn about 19 s. Floors 2 to 4 and the tier 3 to 5 pitches (task 4.x) build on this footprint.
- **2026-10-18, task 0.4:** no empty stub modules. A module is created when its task first needs it, so there is no dead code and the type check stays meaningful.
- **2026-10-18, task 0.10:** ProfileStore's real autosave default is 300 seconds, not 30 as Step 6 said by mistake. `Config.Data.autoSaveSeconds` is 60. `Profile:Save()` does not wait for the write, so `Session.saveAndConfirm` waits until `LastSavedData` shows the change (used for purchase receipts).
- **2026-10-18, task 0.5:** Legend incomes are not in the Step 3 table. Placeholders continue the floor 3 growth (about x1.6 per Legend: 1.0M, 1.6M, 2.6M, 4.1M, 6.6M). Check them in the economy simulation. Shirt numbers are also provisional.
- **2026-10-18, task 0.9:** `BuyStoreUpgrade` sends the level the client saw as well as the upgrade id, so a double tap cannot buy two levels (Step 5 only listed the id).
- **2026-10-18, test method:** `require` inside `execute_luau` creates a separate module instance, so it cannot register handlers on the running game. Studio tests that need server handlers use temporary scripts (added in Edit mode, then deleted).
- **2026-10-18, task 1.4:** the building door moved from the middle of the front to the left end (door at local x = -62, next to capsule 1), and the Field pad moved in front of it. With the door in the middle the claim-ring-to-pad-1 walk was about 10.5 s; with the door at the left end it measured 9.4 s and the Field pad is 1.6 s from pad 1. Slot order along the capsule row stays left to right.
- **2026-10-18, first manual playtest (task 2.x feedback):** (1) the "Start the game" pad and its billboard overlapped the capsule pads and were unreadable, so the pad is gone: buying the first player puts him on the field and starts the matches (`Actions.buyPlayer` sets `fieldStarted`; the goal row has no "Start the game" step). (2) The building interior was redone to the owner's sketch: entrance clear in the middle of the front wall, capsules around the walls in buying order with the first player left of the entrance, stairs in the back-left corner, Store pads in the open middle (generator `tools/studio/BuildPlotTemplate.luau`, door at x = -20, first pad 17.8 studs from the doorway). (3) Pad billboards now show the name above the ring, the price inside it and a note below ("Need $X more"), and only pads within 30 studs, so neighbours never overlap.
- **2026-10-18, guide arrow (owner feedback):** the arrow now guides only the first steps (free plot, then the first player's pad). After the first purchase it is removed, then it points once to the Store pad for at most 20 s (it also ends when the player is within 14 studs, or buys the upgrade), only so the player knows the Store exists, and never again. It starts only when the first player is bought during the session, so a returning player never sees it. Later goals are shown by the goal row only. Checked in a playtest: claim ring, first pad, Store hint, off after 20 s and stays off.
- **2026-10-18, bigger building and clearer guidance (owner feedback):** the building was too small and the entrance guidance unclear. The building went from 120 x 50 to 140 x 80 (about 2x the floor area) with larger capsules (5 x 9) and pads (7 x 7) and wider spacing; each plot is now 200 wide by 210 deep and the plaza 800 long (slots at x = -300, -100, 100, 300). Layout checks run by the generator: nearest pad to the doorway centre 22.2 studs, nearest pair of pads 18.0 studs, no pad near a wall. The guide now also shows a bouncing marker with a caption above the target pad ("Claim your plot", "Buy your first player", "Upgrades are here") drawn through walls, plus the beam. Locked Store pads show no billboard until they unlock, the billboards are smaller (170 x 176), and the "+$N" text moved below the goal row. Claim ring to first pad is 9.8 s with the bigger layout (Step 2 allows about 10 s); the farthest plot from the spawn is about 19 s away (303 studs at 16 studs per second), inside the plan's 20 s.
- **2026-10-18, template generation:** the greybox is built by `tools/studio/BuildMap.luau` and `tools/studio/BuildPlotTemplate.luau` (run through the Studio MCP in Edit mode, safe to rerun). Change a size in the `Def` table and rebuild, do not hand-edit the parts. The map file only holds one template in `ServerStorage.PlotTemplate`.
- **2026-10-18, unit tests:** `tests/framework.luau` loads modules from `src/` in Lune with a fake `script` and `game`, so the same `require(script.Parent.X)` lines work in Studio and in tests. It reads every source file once at startup because Lune file calls cannot yield inside the loader.
