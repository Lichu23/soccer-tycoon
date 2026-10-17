# soccer-tycoon: design plan

Status: steps 1 to 3 agreed (step 3 numbers are a draft to be playtested). Items marked *provisional* use defaults and can change. Steps 4 to 8 are still to do.

## Step 1: core loop

### Match (the income engine)
- Every ~10 s an automatic mini-match plays on the player's pitch. It is PvE in name only: there is no opponent strength.
- The match is always a win. The opponent is cosmetic (dummies in a rival kit). Goals on the scoreboard are derived from the payout.
- The server computes the payout and adds the cash. The client only plays the animation.
- **Loading bar:** while a match plays, a progress bar fills in the HUD next to the money label. When the match ends, a large "VICTORY" text appears on screen and "+$N" lands on the money label as the counter ticks up. There is no extra goal celebration. The amount is shown only at the end.

```
payout = base x sum(field player income) x upgrades x momentum x daily boost x (hat-trick 2x if rolled)
```

- **Hat-trick:** small random chance (about 10%) of a 2x match. The same text reads "HAT-TRICK x2" in a different colour, and "+$N" is the doubled amount. A Store upgrade can raise the chance later.
- **Momentum:** session-only bonus for matches played in a row (for example +1% per match, capped). Never saved. Resets to 0 on join.
- **Offline earnings:** capped at 4 hours of income. The offline rate starts at 10% of normal income and an upgrade raises it up to 35% (see Step 3).

### Stadium: 4 floors of capsules
Players are physical displays in the world (glass capsules on pedestals, like a tycoon). There is no inventory menu and no picker.

| Floor | Players | Rarity | Role |
|---|---|---|---|
| 1 | 10 | Common + Rare (placeholder split 4 + 6) | First hour, the tutorial floor |
| 2 | 10 | Rare + Very Rare | Early mid game |
| 3 | 10 | Very Rare + Epic | Late mid game, the last cash floor |
| 4 | 5 | Legend | Long-term goal (the Legends hall) |

- 35 players in total. Rarity tiers: Common, Rare, Very Rare, Epic, Legend.
- Each capsule is one specific named player with a fixed price and income.
- **Purchase pad:** each capsule has a pad on the floor in front of it showing the name and price. The player buys by standing on the pad for **1 second** while a **circular loading ring** fills (it is not an instant buy, which avoids accidental purchases). The ring is drawn clockwise around the price on the pad, large enough to read on mobile, so the player understands they are paying. When it completes it flashes and plays a short pop sound, then the player appears. Stepping off cancels it, the ring drains back, and nothing is charged. If the player cannot afford it, the ring is red, shows the missing amount and does not fill. Level-up pads use the same 1-second ring, and repeat level-ups while still standing use 0.5 seconds. The stadium upgrade pad uses 2 seconds. The hold times are single values in `Config` so they can be tuned in playtests. If they cannot afford it, the pad shows the missing amount. The server decides the purchase and checks proximity.
- **A floor opens when the previous floor is complete** (all its players owned). Players won from cases count as owned for completion. Nobody is ever replaced or removed.
- A player won from a case on a floor the player has not reached is owned. Their capsule is shown lit behind a glass barrier on the locked floor (a teaser). The rest of that floor stays dark and cannot be bought until the floor opens.
- Capsule order and the guide arrow lead the player through the buying order.

### Field and lineup
- Only the players on the field earn. The field is **always filled automatically with the owned players with the highest income** (top N, N set by the stadium tier). There is no manual swapping, no lineup board and no capsule prompts.
- Owned players beyond the capacity wait on the bench in their capsules and are never removed.
- **The first player is added with a button in the stadium** (pitch), which starts the match loop. After that, new players go to the field automatically when they rank in the top N.
- Positions or set bonuses can be added later if the economy needs more depth (step 3).

### Cases and stars
- A case result that is a player you do not own unlocks that capsule for free. A duplicate adds a **star** to that player: income +X% per star, capped (placeholder 5 stars, modest bonus per star).
- **Case pool includes players from higher floors, but with minimum chances** (the better the player, the lower the odds). The field capacity limits how much a lucky case can earn. Exact odds are set in step 3 and shown before purchase.
- **Free daily case:** cash or temporary boosts only, never players, never large amounts. No login streak.
- **Player case (Robux):** CS-style case-opening animation. The server decides the result first, then the animation shows it. The strip must reflect the real odds (no fake near-misses). Odds are shown before purchase, including the chance of a duplicate. Roblox treats this as a paid random item: odds disclosure is required, pity systems and luck boosts count as paid random items too, and a `PolicyService` restriction may apply to some users. Before building, check current policy and offer the documented alternatives (direct purchase, earnable reward, a known non-random sequence) for affected users.
- Cap the total star bonus and let the free paths also produce duplicates, so paying is not the only way to get stronger.

### Legends (floor 4)
Two routes: free route reachable in roughly 2 to 4 weeks of casual play, or a much more expensive cash route, or a direct Robux purchase at a clearly shown price. A Legend bought with Robux can only be bought inside the building once floor 4 has been reached, so the rule is the same for everyone. Legends stay across New Seasons, and so does anything bought with Robux.

### Training ground
- One training ground where standing earns **training points (TP)**, spent on levelling any owned player (more income) (*provisional*: no position stations, since rosters are fixed).
- **Spending TP on a specific player:** every owned player's capsule has a **level-up pad** in front of it (the same spot as the purchase pad, which becomes the training pad once the player is owned). The pad shows the player's level ("Level 3/10"), the TP cost of the next level, and the income bonus it gives. Standing on it for 1 second (the circular ring fills, like a purchase) spends TP and raises that player's level. At the level cap it reads "MAX". If the player is **on the bench** (not among the top N earning on the field), the pad also shows "On the bench: not earning yet" so TP are not wasted by accident. No menu. The HUD shows the TP balance once the training ground is unlocked.
- A **stamina bar** is the cap: it drains while training and refills while away. TP are earned only while present, never offline, never sold for Robux.
- Level caps by rarity (Common 5, Rare 10, Very Rare 15, Epic 20, Legend 25, placeholders).

### Daily penalties
- 3 kicks a day. Goals give a x1.5 income boost: 3 goals = 10 min, 2 = 5 min, 1 = 3 min, 0 = nothing.
- The server judges each kick (the client only sends the aim) and decides the reset time. No day-streak, no penalty for skipping.

### Store
- **Cash upgrades:** cash per match (from the start), match speed (after stadium tier 2), hat-trick chance and offline earnings (after floor 1 is complete). No daily limit: rising prices are the gate. Every upgrade is reachable with cash. Levels and prices are in Step 3.
- **Robux match boost:** "next 30 matches x2" (developer product, price about 25 to 49 Robux, size and price on the button). Boosted matches are banked up to a **maximum of 60**, shown by a counter ("Boosted matches left: 27"). It can be bought again once the bank has room. Stacking with other boosts is capped (total boost never above x4).
- Purchases are granted by the server and must be safe if the purchase message arrives twice (`roblox-monetization`).
- The offer lives in the Store only: no purchase popups after matches, nothing in the first 5 minutes.

### Plot: building and pitch
- Each plot has two areas: **the building** (capsule floors, where you farm and own players) and **the pitch outside** (the "stadium", where matches are shown). The building has an open or glass front so matches can be watched from the pads (*provisional* layout: pitch in front, building behind).
- The match scene is a short scripted animation. The server has already decided the result and payout. Opponents are cosmetic dummies.

| Stadium tier | Pitch | Players on the field | Price |
|---|---|---|---|
| 1 (start) | Street futsal court: walled, painted lines, centre circle, flags and murals (blocky) | 4 | free |
| 2 | Walled court with proper lines and a small bench | 5 | $250 |
| 3 | Local ground: fences and a small stand | 6 | $25K |
| 4 | Club stadium: floodlights, bigger stand | 8 | $750K |
| 5 | Pro stadium: roof, crowd, scoreboard, fireworks | 11 | $45M |

- **Each stadium upgrade gives a free x2 income boost for 5 minutes.** The timer counts only while the player is online (it waits if they leave), and a HUD badge shows the time left ("x2 · 4:32"). A new upgrade resets the timer, it does not add up. It stacks with other boosts inside the total x4 cap. It is free, never a Robux item, and repeats each New Season when the tiers are bought again.
- The stadium tier costs cash only. Floors and stadium tier are two separate tracks (floors by completion, tier by cash). The price is taken from the player's cash, and the server charges and applies the upgrade in one step.
- **"Next goal" HUD row:** a small row under the money label shows one goal at a time ("Next goal: Stadium upgrade", progress bar, "$120 / $200"). It follows the buying path (first player, start the game, first upgrade, next players, stadium upgrade). It is not a list of every upgrade.
- When the goal becomes affordable, the row **glows brightly** and reads "Stadium upgrade available!", and the guide arrow points to the pad. The glow pulses a few times and then stays steady. No sound and no nagging.
- **Upgrades can be bought from the HUD row** with a button (stadium tiers and Store upgrades), as well as by standing on the pad in the world. Because it is a big spend, the HUD button asks for a second tap to confirm. Players are still bought only on the capsule pads.
- **Upgrade animation:** the server confirms the purchase, that player's controls are locked and the camera moves to a cinematic view for about 5 to 8 s while the pitch transforms, then the new capacity shows and controls unlock. Beats (about 6 s): pay and lock, camera to the court, shake and dust while field players step aside, fences and stand rise and floodlights switch on one by one, "STADIUM UPGRADED", "Field 4 to 5" and "x2 for 5 minutes" text, the next-best bench players run onto the new spots, controls unlock and the HUD goal switches. It works wherever the player bought it (the camera goes to the court). The first upgrade cannot be skipped; from the second upgrade a tap skips to the end. Later tiers get bigger versions (tier 2 to 3: fences and a small stand; tier 3 to 4: floodlights and a bigger stand; tier 4 to 5: roof, crowd, scoreboard, fireworks). No fast flashes, mobile friendly. It has a time limit (so nobody gets stuck), affects only that player, and the server finishes the upgrade even if the player leaves.

### World and plots
- Shared world: players spawn in a shared area outside, with free plots in front. Visitors can see claimed plots, buildings and pitches.
- **Plot claiming:** the player walks onto a free plot's "Claim" ring. The server assigns it (so two players cannot claim the same one) and the building appears with a build animation. Plots equal max players per server (*provisional*: 8).
- When a player leaves, the plot is freed. Their saved data rebuilds their building on rejoin on any free plot.
- Idle players: the arrow points to the nearest free plot, and after about 20 s the server assigns one (*provisional*).
- Blocky cartoon style. Mobile first.

### New Season (rebirth) (*provisional*)
- Called "New Season", not leagues: the 35 players stay the same.
- Unlocked after floor 3 (the last cash floor) is complete and a cash threshold is met. Target first New Season about 2 to 3 hours of play in (day 2 for an efficient player, around day 4 for a casual one). It does not require owning Legends.
- **Resets:** cash, floors 1 to 3 back to floor 1, players from floors 1 to 3, Store upgrade levels, TP levels.
- **Stays:** Legends, anything bought with Robux, trophies, the permanent income multiplier (diminishing returns), stars, the collection record.
- Confirm screen shows exactly what is lost and gained. Optional, no timers, no guilt.
- **Season badge in the HUD** next to the money label ("Season 2 · x1.5": season number and permanent multiplier). Tapping it shows progress (floors complete, cash threshold, what the next season gives). When New Season becomes available the badge glows and reads "New Season available" (no nagging, no timer), and the "Next goal" row switches to "Start New Season".
- Legends and anything bought with Robux are kept across seasons (*provisional*: this replaces the idea of resetting every cash-bought player).
- Trophies perk shop: later, not in the first release.

### Naming
- **Decision (made by the project owner):** use real player names. Known risk: names, and any faces, club badges or logos, are covered by image, publicity and trademark rights, and a rights holder can request a takedown or take legal action. Faces, club badges and logos have not been checked against Roblox policy.
- Safeguard: every player's name, nationality, number and description live in one `Config` table (not in code or models), so names can be swapped in minutes if a notice arrives or the decision changes.
- Keep real names away from paid features where possible.

## Step 2: first 5 minutes

Principles: value in the first 30 s, teach by doing (no popups), one new idea per minute, never an empty wait, finish the section on a peak.

| Time | What happens | Purpose |
|---|---|---|
| 0:00 | The player spawns in the shared area outside. An arrow points to the nearest free plot. | One obvious action |
| 0:10 | They step on a free plot's Claim ring. The plot is theirs and the building appears with a build animation. They hold $15. | Ownership moment |
| 0:20 | The arrow points at the first capsule's pad. They stand on it and buy the first Common player for $10. | First purchase in about 20 s |
| 0:25 | A new arrow guides them to the stadium (the street court). They click the button on the pitch: the player runs onto the court and the match loop starts. | Teaches that the field is where the game plays |
| 0:30 | First match with the loading bar (about 5 s for this one). "VICTORY" appears, then "+$N" lands on the money label. | First reward, loop understood |
| 0:40 to 1:00 | A match every ~10 s keeps paying. The Store pad glows when an upgrade is affordable and the arrow points to it. | Guide without a menu |
| 1:00 | First upgrade (Cash per match, about $20). Next matches pay visibly more. | Spending makes numbers go up |
| 1:30 to 3:00 | The next capsule lights up with the arrow. They buy the 2nd and 3rd players, who join the field automatically (the court shows 2, then 3 players). | The buying order is the tutorial, and each purchase visibly changes the court |
| 3:30 | The 3rd player is bought with a small reveal animation (name, number, nationality). | Small peak |
| 4:00 to 4:30 | First hat-trick, scripted once (afterwards real odds apply). The text reads "HAT-TRICK x2". | Surprise before the main peak |
| 4:30 | They buy the 4th player. The court shows "Field 4/4" and the stadium upgrade pad shows its price ($250) and a progress bar fed by match income. | Creates the next goal |
| 5:00 | **Peak:** once they can afford the upgrade, a short message says "Stadium upgrade available!" and the arrow points to the pad (it never fires on its own and never nags). They pay by standing on the pad or by pressing the glowing HUD button. Controls lock, the camera moves, the street court becomes a walled court with proper lines, the new capacity shows ("Field 4 to 5") and a x2 income boost starts for 5 minutes. | Main peak and transition |
| After 5:00 | The daily penalty pad appears with a short clear prompt. More Store options appear gradually. | Loop established |

Not in the first 5 minutes: training ground, cases, Robux shop, notifications, leaderboard, New Season. They open later, one at a time.

Provisional defaults: start with $15, scripted first hat-trick (not tied to a purchase), daily penalties introduced right after the first peak. Whether the stadium upgrade is affordable by minute 5 depends on prices (step 3).

### Verify (after build)
Time to first purchase under about 30 s; share reaching the first stadium upgrade by minute 5 (below about 60% means pacing is too slow); where players drop; day-1 return.

### Ethics check
Pass: no fake timers, no scarcity, no guilt, nothing for sale in the first 5 minutes.

## Step 3: economy (draft, to be playtested)

Method: a small simulation of a player who buys the cheapest next item as soon as they can, with matches every 10 s and the average effect of hat-tricks. Back tests ran five player types (free efficient, free casual, light, regular and heavy spenders). They ignore training points, momentum, daily penalties, the New Season multiplier and real player behaviour, treat star bonuses roughly, and use placeholder Robux prices. All numbers are placeholders for `Config`. The HUD shows large numbers with K, M, B, T abbreviations.

Income is cash per match for a player on the field. Prices rise faster than income, so each purchase takes longer to pay back. Floor 1 grows by 2.05x per player, floor 2 by 1.9x and floor 3 by 2.0x (income grows 1.6x, 1.5x and 1.45x).

| # | Floor | Price | Income | | # | Floor | Price | Income | | # | Floor | Price | Income |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | $10 | $3 | | 11 | 2 | $21.2K | $403 | | 21 | 3 | $13.7M | $22.4K |
| 2 | 1 | $30 | $5 | | 12 | 2 | $40.2K | $604 | | 22 | 3 | $27.3M | $32.5K |
| 3 | 1 | $70 | $9 | | 13 | 2 | $76.4K | $906 | | 23 | 3 | $54.6M | $47.2K |
| 4 | 1 | $150 | $16 | | 14 | 2 | $145K | $1.4K | | 24 | 3 | $109M | $68.4K |
| 5 | 1 | $308 | $26 | | 15 | 2 | $276K | $2K | | 25 | 3 | $218M | $99.2K |
| 6 | 1 | $630 | $41 | | 16 | 2 | $524K | $3.1K | | 26 | 3 | $437M | $144K |
| 7 | 1 | $1.3K | $66 | | 17 | 2 | $995K | $4.6K | | 27 | 3 | $874M | $209K |
| 8 | 1 | $2.7K | $105 | | 18 | 2 | $1.9M | $6.9K | | 28 | 3 | $1.75B | $302K |
| 9 | 1 | $5.4K | $168 | | 19 | 2 | $3.6M | $10.3K | | 29 | 3 | $3.49B | $439K |
| 10 | 1 | $11.1K | $268 | | 20 | 2 | $6.8M | $15.5K | | 30 | 3 | $6.99B | $636K |

- **Starting cash:** $15.
- **Legends (floor 4):** $400B, $1T, $2.5T, $6T, $15T. The first Legend should take about 3 weeks of casual free play. The cash route is very expensive and a direct Robux purchase is also available. Re-check these after the first playtests.
- **Stadium tiers (cash):** tier 2 $250 (field 5), tier 3 $25K (field 6), tier 4 $750K (field 8), tier 5 $45M (field 11). The final back test (with all boosts, momentum and stars) has a player buying them at about 4 min, 7 min, 10 min and 28 min. Raising tiers 3 to 5 about 3 times spread them out from about 4, 6, 9 and 20 minutes. A bigger field adds only about +5% to +27% income in total (the best players do most of the earning), so tiers are mostly milestones. Each one gives a free x2 boost for 5 minutes (counts only while online, resets if a new one starts, inside the x4 cap).
- **"Cash per match" upgrade, 8 levels:** $15, $60, $240, $960, $3.8K, $15K, $61K, $246K, giving multipliers x1.5, x2.1, x2.7, x3.5, x4.3, x5.1, x5.9, x6.7.
- **Match speed (unlocks after stadium tier 2, minimum 5 s so the bar, "VICTORY" text and counter stay readable):** $120 (9 s), $2K (8 s), $30K (7 s), $500K (6 s), $8M (5 s).
- **Hat-trick chance (unlocks after floor 1):** base 10%, then $300 (12%), $5K (14%), $80K (17%), $1.5M (21%), $25M (25%). It is a cash upgrade, not a Robux luck boost.
- **Offline earnings (unlocks after floor 1):** cap 4 hours of income. Rate starts at 10% and rises with $500 (15%), $10K (20%), $200K (25%), $4M (30%), $80M (35%). At 100% it out-earned active play, so it is deliberately low.
- **Stars:** +10% income per star, maximum 5 stars (+50%).
- **Training points (TP):** stamina session of 5 minutes, refilling in about 5 minutes away. Placeholder rate 10 TP per minute (50 TP per session). Each level adds **+3% income**. Level caps: Common 5, Rare 10, Very Rare 15, Epic 20, Legend 25. Cost of level L = 40 x L x rarity factor (Common 1, Rare 2, Very Rare 3, Epic 4, Legend 5). A Common player reaches level 5 in about 1 hour of training (600 TP, about 12 sessions). A Legend at level 25 is a very long-term goal (about 65,000 TP).
- **Momentum:** +1% per match in a row this session, maximum +25%. Resets on join.
- **Daily penalties:** x1.5 income for up to 10 minutes.
- **Case (Robux):** 49 Robux. Pool: 70% players from floors you have reached, 25% from the next floor, 5% from further floors. A Legend has a 0.5% chance (inside the 5%). Duplicates add a star. All odds, including the chance of a duplicate, are shown before purchase.
- **Free daily case:** a mixed prize, either cash worth about 5 minutes of the player's income or a x2 boost for 5 minutes. Never players, never large amounts.
- **Robux boost:** next 30 matches x2, banked up to 60, about 25 to 49 Robux. A 5-match pack was too small to feel worth buying (a 30-minute session has about 180 matches). Total boost never above x4.
- **New Season:** the button appears when floor 3 is complete (no extra cash threshold). Each season adds +50% to the permanent multiplier (season 2 = x1.5, season 3 = x2.0, season 4 = x2.5).

### Simulated pacing
- First 5 minutes: first purchase 0:23, first upgrade 1:06, player 2 at 2:06, player 3 at 3:36, player 4 at 4:16, stadium tier 2 at 5:16. This matches the Step 2 script.
- Floor 1 complete at about 11 min, floor 2 at about 40 min, floor 3 in about 2.7 hours of play (day 2 for an efficient player, around day 4 for a 30-minute-a-day player). First Legend after about 3 weeks of casual free play.
- Spenders save time but not a lot. Boosts roughly equal playing twice as long, and a free player can catch up with time. **Cases are the strongest shortcut** (a regular spender skipped much of floor 3), so watch the 70 / 25 / 5 case pool in playtests and lower it (for example to 90 / 9 / 1) if players skip floors.

### Still to test in playtests
Real pacing of floors 2 and 3 with stars, TP, momentum and daily boosts, the Legend prices, the case pool, the hat-trick chance, the offline rate and whether the 30-match boost feels worth its price.

## Decisions log
| Topic | Decision |
|---|---|
| Opponent | Cosmetic only, always a win |
| Match feedback | Loading bar in HUD, then "VICTORY" (or "HAT-TRICK x2") text and "+$N" on the money label |
| Store | Cash upgrades with no daily limit. Robux boost: next 30 matches x2, banked up to 60, total boost cap x4 |
| Stadium | 5 tiers (field 4, 5, 6, 8, 11), each upgrade gives a free x2 boost for 5 minutes |
| Streak | Momentum, session only |
| Stadium | 4 floors of capsules, 10 + 10 + 10 + 5 players (35) |
| Buying | Stand on the pad in front of the capsule |
| Duplicates | Add a star (income bonus, capped) |
| Field | Auto-filled with top-N income players, no swapping, first player added by a stadium button |
| Training | One training ground, stamina bar cap (provisional) |
| Stadium tier cost | Cash only, taken on purchase |
| Goal guidance | HUD "Next goal" row, glows when affordable, buy from HUD (with confirm) or the pad |
| Floors | Open when the previous floor is complete |
| Cases and floors | Cases can give higher-floor players, at minimum chances |
| Trading | Out of version 1 |
| Roulette | Replaced by cases (free daily, Robux player case) |
| Legends | Free grind or cash or Robux |
| World | Shared world, claimable plots, personal building and pitch |
| Rebirth | New Season after floor 3 is complete, Legends and Robux purchases kept (provisional) |
| Names | Real names, names kept in Config, risk acknowledged |

## Steps still to do
3. Economy: drafted and tested with a simulation (needs real playtests)
4. Retention and ethics review
5. Architecture and security (roblox-architecture, roblox-security)
6. Saving (roblox-data)
7. Build and polish (roblox-building, roblox-gui, roblox-lighting)
8. Launch (roblox-publish-checklist, roblox-monetization, roblox-growth-design)
