# soccer-tycoon: design plan

Status: steps 1 to 6 agreed (step 3 numbers are a draft to be playtested). Items marked *provisional* use defaults and can change. Steps 7 and 8 are still to do.

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
- **Purchase pad:** each capsule has a pad on the floor in front of it showing the name and price. The player buys by standing on the pad for **1 second** while a **circular loading ring** fills (it is not an instant buy, which avoids accidental purchases). The ring is drawn clockwise around the price on the pad, large enough to read on mobile, so the player understands they are paying. When it completes it flashes and plays a short pop sound, then the player appears. Stepping off cancels it, the ring drains back, and nothing is charged. If the player cannot afford it, the ring is red, shows the missing amount and does not fill. Every pad uses the same 1-second ring: player purchases, level-ups (including repeats while still standing) and the stadium upgrade pad. The hold time is one value in `Config` so it can be tuned in playtests. If they cannot afford it, the pad shows the missing amount. The server decides the purchase and checks proximity.
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
- **Decision: stars are for paying players.** They come only from case duplicates (Robux) and no free path produces them. The star bonus is capped (+10% per star, 5 stars, +50% per player), and no free goal, including the Legend Trials, depends on stars. Free players still reach every floor, tier and Legend through cash, training and the trials.

### Legends (floor 4)
Two routes:
- **Legend Trials (free):** each Legend has a short checklist of goals plus the cash price. The goals use only training, owned players and stadium tiers, never stars (stars are paid-only, see Cases and stars). First Legend (*provisional*, to be tuned in the step 3 simulation): own all players of floors 1 to 3, train three players to level 5, and reach stadium tier 4. Later Legends ask for more (more players trained, higher levels, stadium tier 5). Reachable in roughly 2 to 4 weeks of casual play. The checklist is shown on each Legend capsule's panel in the Legends hall (no HUD row). The hall is visible through glass from floor 2, so the panel can be read early, with goals greyed out until floor 4 is reached. Progress is recorded permanently, so a New Season does not undo a completed goal. No streak, no daily cap, no expiry.
- **Direct Robux purchase** at a clearly shown price, which skips the trials and the cash price.

There is no separate expensive cash route: everyone pays the cash price and completes the trials, or buys with Robux. A Legend bought with Robux can only be bought inside the building once floor 4 has been reached, so the rule is the same for everyone. Legends stay across New Seasons, and so does anything bought with Robux.

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
- **Plot claiming:** the player walks onto a free plot's "Claim" ring. The server assigns it (so two players cannot claim the same one) and the building appears with a build animation. Plots equal max players per server: 8 (decided).
- When a player leaves, the plot is freed. Their saved data rebuilds their building on rejoin on any free plot.
- Idle players: the arrow points to the nearest free plot, and after about 20 s the server assigns one (*provisional*).
- Blocky cartoon style. Mobile first.

### New Season (rebirth) (*provisional*)
- Called "New Season", not leagues: the 35 players stay the same.
- Unlocked after floor 3 (the last cash floor) is complete and a cash threshold is met. Target first New Season about 2 to 3 hours of play in (day 2 for an efficient player, around day 4 for a casual one). It does not require owning Legends.
- **Resets:** cash, floors 1 to 3 back to floor 1, players from floors 1 to 3, Store upgrade levels, TP levels.
- **Head start (replaces "start from scratch"):** a new season starts with earlier floors already owned. Season 2 starts with floor 1 owned, season 3 and later with floors 1 and 2 owned. **Floor 3 is never granted**, because completing it opens floor 4 and the next New Season, so it must be played every season. Floor 4 and Legends are never granted by a season. Head-start players start at level 0 and 0 stars (stars from earlier seasons are kept, see below). The confirm screen shows exactly which floors are kept. Pacing is checked in the step 3 simulation (provisional).
- **Stays:** Legends, anything bought with Robux, trophies, the permanent income multiplier (diminishing returns), stars, the collection record.
- **Preview from floor 3:** as soon as floor 3 opens (reached, not yet complete), the New Season button appears in the HUD in a locked state. Tapping it explains how it works: a permanent x1.5 income that grows each season, you start again from floor 1 with no cash, what resets, what stays (the floor head start, Legends, Robux purchases, stars, trophies), and how much of floor 3 is left to unlock it. It does not glow or nag while locked. The reset itself is available only when floor 3 is complete.
- Confirm screen shows exactly what is lost and gained, plus an estimate of the re-climb ("floor 3 again in about 1.8 h at x1.5"). Optional, no timers, no guilt.
- **Season badge in the HUD** next to the money label ("Season 2 · x1.5": season number and permanent multiplier). Tapping it shows progress (floors complete, cash threshold, what the next season gives). When New Season becomes available the badge glows and reads "New Season available" (no nagging, no timer), and the "Next goal" row switches to "Start New Season".
- Legends and anything bought with Robux are kept across seasons (*provisional*: this replaces the idea of resetting every cash-bought player).
- **Season trophies:** starting a New Season awards the trophy for the season just finished, with a short reveal in the style of the rarity reveal (a small celebration after the reset). Trophies use generic names to avoid trademarked competitions (*provisional*: Street Cup, City Cup, National Cup, Continental Cup, World Cup, then World Cup with a number), kept in `Config` so they are easy to swap. They stand on a shelf in the building's entrance hall, visible to visitors. Purely cosmetic, permanent, kept across seasons.
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
- **Legends (floor 4):** $400B, $1T, $2.5T, $6T, $15T. Everyone pays the cash price and completes the Legend Trials, or buys with Robux. The first Legend should take about 3 weeks of casual free play, but the cash price on top of the trials may now be the real bottleneck, so check it in the simulation. Re-check these after the first playtests.
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

## Step 4: retention and ethics review (agreed)

Method: the retention stack (core loop, hour-to-hour meta-game, day-to-day progression) plus the Fogg model (motivation, ability, prompt) for each return trigger, then the Regret Test and Black Mirror Test on every persuasive feature. Nothing here is measured yet: all targets come from playtests and the Creator Dashboard after launch.

### Why a player comes back
| Window | Reason to return | Where it comes from |
|---|---|---|
| Same session | The next player or upgrade is always one or two minutes away | Step 3 pacing, "Next goal" row |
| Day 1 | Offline earnings waiting, free daily case, daily penalty kicks, floor 2 in progress (about 40 min) | Offline cap 4 h, no streak |
| Days 2 to 4 | Floor 3 complete, first New Season (a visible fresh start with x1.5) | Step 1 New Season |
| Weeks 1 to 3 | Climb floor 3, TP levelling, stars from duplicates, first Legend (about 3 weeks) | Legends route, collection |
| Month 1+ | Collection record, more seasons, seeing other players' plots | Shared world |

Return triggers are all **pull, not push**: a reason that is true (cash is waiting), never a made-up deadline.

### Pit and peak map (first sessions)
- **Peaks:** first purchase (0:23), first hat-trick (about 4:15), first stadium upgrade (about 5:16, the main one), floor 1 complete (about 11 min), floor 2 complete (about 40 min).
- **Pits to watch:** minutes 5 to 11 (after the big peak, before floor 1 is done), the long wait for items 10 to 12 on each floor, and the first New Season reset.
- **Fix for the post-peak dip:** open one new thing right after the first upgrade (daily penalty pad), and open the next one when floor 1 completes (hat-trick and offline upgrades, training ground). One new idea at a time, never a menu dump.
- **End on a high:** when a player leaves, the HUD shows what is banked ("Offline earnings ready: up to 4 h") so the last thing they see is progress, not a treadmill.
- **Welcome back:** a single non-blocking line ("+$N while you were away", the cap is shown). It is the Day 1 hook, so it must always load correctly (see Step 6).

### Unlock order (one new idea at a time)
| Moment | Opens |
|---|---|
| Start | Claim plot, capsule pads, the field button |
| About 1 min | Store: cash per match |
| About 5 min | Daily penalties, free daily case, their two HUD icons, stadium tier 2 |
| Floor 1 complete (about 11 min) | Hat-trick and offline upgrades, training ground, the notification opt-in (below) |
| Stadium tier 2 | Match speed |
| Floor 2 started | The Robux player case, in the Store (not before, so the first 30 minutes are about the loop). The Legends hall becomes visible through glass |
| Floor 3 reached | New Season button appears locked, with the explainer |
| Floor 3 complete | New Season can be started |
| Floor 4 reached | Legends hall and the direct Robux Legend |

### Active play during the waits
The game stays idle by design. Two small additions, no chores:
- **Training drill:** at the training ground, standing still earns the base 10 TP per minute. A timing drill (same aim-only input and server judging as the daily penalties, so one mechanic built once) raises the rate for as long as the player keeps hitting it, up to about 15 TP per minute (*provisional*). The stamina bar stays the cap. Pacing and the Legend Trials are always tuned on the idle rate, so nobody falls behind.
- **Team customization** (below).
- Not in version 1: world collectibles, tap-to-boost during matches, daily quests.

### Team customization by stadium tier
Each stadium tier unlocks a new thing to customise, so a tier is more than a bigger field. Choices apply to the match scene, the plot outside and what visitors see, through a "Locker room" button on the pitch. Defaults look good, so nobody has to use it, and a new unlock shows a small note on the HUD that never blocks.

| Tier | Free styles | Robux styles |
|---|---|---|
| 1 | Kit colours (home and away), team name from a preset list | Premium kit designs |
| 2 | Crest from a small preset set, bench style | Premium crests |
| 3 | Fence banners, stand colours | Premium stand and banner sets |
| 4 | Floodlight colour, flags | Premium floodlight and flag sets |
| 5 | Scoreboard style, crowd chant style, fireworks colour | Premium stadium themes |

- **Each tier has several free styles and a few premium ones** (counts are *provisional*). Premium styles are purely cosmetic: no income, no capacity, no advantage.
- A premium style is shown only for tiers the player has reached, with a preview before buying. It is a direct purchase of a visible style: no random cosmetic crates. Offers live only in the Locker room, with no popups and nothing in the first 30 minutes. Prices are placeholders (set in Step 8).
- Bought styles are kept across New Seasons, like anything bought with Robux. Free choices are also kept and re-apply as the player reaches each tier again.
- The client sends only an option ID from `Config` and the server checks it against what the tier unlocks and what the player owns. No free-text names in version 1 (presets avoid filtering). Purchases follow the Step 1 rule of being safe if a message arrives twice (`roblox-monetization`).
- Art cost: kit colours and banners are cheap, crowd chants and fireworks are the most expensive. Tier 5 is the first thing to cut if time is short.

### Daily return: HUD icons and cooldown
- After the first 5 minutes (when penalties unlock), two icons sit next to the money label: the **free daily case** and the **daily penalties**. When one is ready it shows a small dot or soft glow, with no sound and no red counter, and the glow stops pulsing after a few seconds. When not ready the icon is dimmed and a tap shows the time left ("Ready in 3 h 20 min").
- The icon opens the **free** case only (cash or a boost, never players). The Robux case lives in the Store from floor 2 and never shows a "ready" glow, because nothing free is pending there.
- **Cooldown: 20 hours from claiming**, for the case and for the penalties (the 3 kicks refill together 20 hours after the first kick of a batch). A player who claims at 6 pm finds it ready again at 2 pm the next day, so a daily player never meets "not ready yet". It cannot be claimed twice in a day, and the ready time drifts earlier, so a changing schedule loses nothing. A fixed midnight reset was rejected: someone could claim at 11:59 pm and again at 12:01 am, and it feels unfair across timezones. Judged by the server clock.
- No streak, nothing lost by skipping, and the icons never block anything.
- HUD layout (*to check in the GUI pass, `roblox-gui`*): icons at least 44 px, inside the safe area, not overlapping the money label, the season badge or the "Next goal" row. This is the busiest part of the HUD.
- The free case opens at minute 5 as a small cash prize (about 5 minutes of income), so the Step 3 cash numbers for the first session need a quick recheck.

### Notifications (opt-in only)
- Ask once, after floor 1 is complete, never in the first 5 minutes, and with a plain "Notify me when my offline earnings are full" text.
- Send only when it is true and useful: offline bank full (4 h), a free daily case waiting. At most 1 a day. If the player ignores several in a row, stop sending. No guilt wording, no countdown language.

### Ethics gate: feature by feature
| Feature | Regret Test | Black Mirror Test | Verdict and rule |
|---|---|---|---|
| Hold-to-buy ring | Player knows what they pay and can step off | None | Pass |
| Glowing "available" row | It is true information; the glow stops pulsing | None | Pass. Keep it silent and short |
| Hat-trick | Positive-only luck, cash only, odds visible in the upgrade | Chance upgrades could look like gambling | Pass. The scripted first hat-trick is a tutorial moment; show the real chance in the upgrade text and do not call it "lucky" |
| Momentum | It only adds income, never removes it | Rewards staying online, reaching the cap in about 4 min | Pass. Capped at +25% so it does not trap players in long sessions |
| Stadium x2 timer | Pauses while offline, so nothing is lost | A countdown on a HUD badge | Pass. Keep the badge calm, no red or flashing |
| Offline earnings | Low rate, no punishment for being away | None | Pass |
| Stamina and TP | Free, never sold | Could be a chore | Pass. Never sell stamina refills |
| Daily penalties and free case | No streak, no penalty for skipping | None | Pass |
| Robux match boost | Bank never expires, cap 60, price on the button | Stacking cap x4 | Pass |
| **Robux player case** | **Main risk: a paid random item, likely young players** | Repeat buying for duplicates | **Pass only with the rules below** |
| New Season reset | Player loses progress for a bonus | Feels forced if cash Legends become unreachable without it | Pass with a clear confirm and a re-climb estimate. Verify in playtests that it stays optional |

### Rarity reveal (fills the minute 5 to 11 dip)
- The **first time a player owns a player of a rarity** (first Common, first Rare, first Very Rare, first Epic, first Legend), a short reveal plays: a background colour for that rarity, the player's name and number, and the player doing a ball trick (juggle, flick, or a celebration).
- Rarity colours (*provisional*): Common grey or white, Rare blue, Very Rare purple, Epic gold, Legend a rainbow or red-gold. The rarity name is always written as text too, so the colour is not the only signal.
- About 3 s, a tap skips it, no fast flashes, readable on mobile. It plays for purchases, case wins and free unlocks alike. Later players of a known rarity get only the small reveal from Step 2 (name, number, nationality).
- **The first Common reveal is the first purchase (about 0:23)**, so it is shorter (about 2 s) and does not lock movement: the guide arrow to the stadium shows as soon as it ends or is skipped, to keep the 30 s first-match target of Step 2.
- **Every player won from a case gets a reveal**, whether or not the rarity is new. A duplicate shows the same reveal plus the star it adds ("+1 star, 3/5"). It plays after the result is final, and it never replaces the odds strip or hints at a better result than the one won.
- The first Rare player arrives early in floor 1, so the player gets the second reveal in the first 10 minutes.

### Cases are in version 1
Decision: the Robux player case ships in version 1 with the rules below, because it is optional and nothing in the progression depends on it. Re-check the 70 / 25 / 5 pool in the first playtests (see Step 3).

### Rules for the Robux player case
- Odds, the chance of a duplicate and the star effect are shown before purchase and on the button screen.
- The server decides first and the strip shows the true odds (no fake near-misses). No pity counter and no luck boost.
- One purchase per confirmation. No "open again" button that skips the confirm, no bundle discounts that push quantity, no limited-time banners, no popups after matches.
- No case offers in the first 30 minutes. Never the only way to progress: every player, cases included, can be earned with cash.
- Duplicates beyond 5 stars turn into cash (about 5 minutes of income) so a pull is never dead.
- Check `PolicyService` before showing it and offer the direct-purchase alternative where it is restricted (see Step 1 and `roblox-monetization`).
- Keep real player names away from the case flow (already in the naming safeguard).
- The confirm screen shows the session total ("This session: 4 cases, 196 Robux"). Information only: no limits and no lockouts.

### What disappears if this succeeds (Black Mirror)
- The game is mostly automatic, so a player can leave it running without doing anything. That is fine for income, but engagement then lives in the buying decisions, so keep those fresh (new items, short upgrade animations) and avoid "stay online or lose out" mechanics.
- The collection record and plot visiting are the only social hooks. If growth needs more, add them later (cheering a visitor's plot, a trophy shelf), never leaderboards ranked by time played.

### How to verify
- Metrics: day 1, day 7 and day 30 return, average session length, share reaching the first stadium upgrade by minute 5 (target at least 60%), share reaching floor 1, floor 2 and floor 3, share who press New Season, share who regret it (rejoin and quit within a day), case purchases per paying player.
- Check for harm: how many players buy cases repeatedly in one session, and refund requests. If a small group spends a lot, add a confirm showing a session total.
- Questions to ask testers: "What made you stop?", "What did you want to do next?", "Was anything you bought not what you expected?"

## Step 5: architecture and security (agreed)

Principle: the server owns every game fact and the client only draws. No framework, event bus or ECS: direct module calls, one owner per piece of state. Every client message is a remote with a type check, bounds, an ID taken only from `Config`, a server cooldown and a rate limit. The module map is the structure to build; the items below were each discussed and agreed.

### Module map
- **Shared** (pure, no secrets): `Config` (players, prices, rarities, store levels, trophies, cosmetics, hold time, cooldowns) and `Formulas` (payout, star bonus, pad price, offline earnings), so the number on a pad is the number the server charges.
- **Server:** `Session` (one in-memory record per player), `Economy` (the only place cash changes), `Plots`, `Match`, `Roster`, `Pads`, `Stadium`, `Store`, `Training`, `Daily`, `Cases`, `Season`, `Legends`, `Cosmetics`, `Purchases`. A small `Main.server.luau` starts them in an explicit order and fails visibly.
- **Client:** `HUD`, `PadRing`, `MatchView`, `Reveal`, `StadiumCinematic`, `LockerRoom`, `CaseView`. None of them decides anything.

### Decisions
- **Pads are server-timed, not `ProximityPrompt`.** The player just stands on the pad. The server tracks who is on which pad and times the hold with its own clock (`Config` hold time, 1 second). The client draws the ring (it starts it right away and the server confirms). Only the plot owner can buy on their pads, and a visitor standing on a pad is ignored. Written and tested first, because every buy, level-up and stadium upgrade uses it. Edge cases to cover: respawn, two players on one pad, leaving mid-hold.

- **HUD numbers travel as player attributes.** Single values (cash, TP, stamina, season number, boost multiplier and end time, boosted matches left, ready times for the daily case and penalties) are set by the server and replicate automatically, with no remote. Lists (owned players, levels, stars, cosmetics, trial progress) go once as a snapshot on join and then as small changes through one remote, since only the Locker room and Legend panels need them. The plot itself (capsules, pads, pitch) is built and changed by the server and replicates as parts. One server-to-client remote carries events (match result, reveal, upgrade cinematic). The HUD counter animation is separate from the real number, which is set at payout. Attributes are exact up to about 9 quadrillion, so `Config` has a maximum cash value as a safety net for many seasons. A client changing its own copy changes nothing, because the server never reads these values back.

- **Ten client-to-server remotes. Actions in the world are pads, so they need no remote** (claim plot, buy and level a player, start the first player on the field, Store pads, stadium pad, training presence).

| Remote | The client sends | The server checks |
|---|---|---|
| `ClientReady` | nothing | Sends the join snapshot, so it is never sent before the client listens |
| `UpgradeStadium` | the tier the client saw | It is the next tier, affordable, nothing in progress |
| `BuyStoreUpgrade` | an upgrade ID | The ID exists, unlocked, the next level, affordable |
| `ClaimDaily` | which one (case) | 20 hours since the last claim |
| `PenaltyKick` | an aim zone (small enum) | Kicks left, cooldown, the server rolls the result |
| `SetCosmetic` | an option ID | Tier reached and the style is free or owned |
| `StartNewSeason` | the season number the client saw | Floor 3 complete, number matches, then reset |
| `TrainingDrillHit` | the press only | Drill active, 15 TP per minute cap, stamina |
| `RequestPurchase` | a product key from `Config` | The server decides whether to show the Robux prompt (boost bank has room, case policy, floor 4 reached for a Legend) |
| `AckReveal` (optional) | nothing | Marks a reveal as seen so it is not replayed after rejoin |

- **Rules for every remote:** one shared module registers each remote with its payload shape. A wrong type, an out-of-range value or an unknown ID is dropped and logged. Rate limit per player per remote plus a server cooldown where the action has one. The client never sends cash, prices, quantities or player IDs it chose, only IDs from `Config`. Handlers never yield between "check" and "change", so two fast requests cannot both pass the check.

- **Double-tap safety on big actions.** `StartNewSeason` and `UpgradeStadium` carry the season or tier number the client saw, and the server drops a request whose number is old (the first request already changed it). The check and the change happen in one step with no waiting in between, so two requests with the right number cannot both pass. A refused duplicate is silent. A real refusal (not enough cash) shows a short calm HUD message. Store upgrades use the same idea through the "next level" check. No server lock during the stadium cinematic: the server applies the upgrade at once and the cinematic is only presentation, so the client simply ignores buttons while the camera is locked.

- **Robux purchases are started by the server and are idempotent** (`roblox-monetization`):
  1. The client asks `RequestPurchase`; the server decides whether to show the prompt (boost bank has room, case policy, floor 4 reached for a Legend).
  2. Every receipt is recorded by its `PurchaseId`. A resent receipt grants nothing a second time and, for a case, returns the saved result.
  3. Cases: roll, save, then animate. The result is saved with the `PurchaseId` before the client plays the animation, so a disconnect mid-animation still leaves the player in the collection and the reveal shows on the next join.
  4. The receipt is confirmed to Roblox only after the item is saved. If the save fails it stays unconfirmed so Roblox retries and nobody loses Robux.
  5. The match boost is granted in full even if the bank is over 60 by the time the receipt arrives.
  6. Cosmetics and Legends are ownership flags in the save and are never reset by New Season.
  The receipt record must be part of the saved profile (Step 6).

- **The training drill is bounded, not strictly validated.** The server never gives more than 15 TP per minute and the stamina cap ends the session, so the best a cheater gets equals a perfect honest player. The marker position depends on the server's time since the drill started, and a press is accepted with a small latency tolerance, so poor connections are not punished. Presses faster than a human could (many in one frame) are ignored and logged. Legend Trials stay tuned on the idle rate (10 TP per minute).

- **All times come from the server.** Real-world times (the 20-hour cooldowns and offline earnings) use `os.time()` on the server, saved as timestamps in the profile, so changing the device date does nothing. Online-only timers (the 5-minute stadium boost, the stamina bar) count connected seconds and are saved as time left, pausing while offline. Offline earnings are computed at join: time since the last save, clamped to 4 hours, times the offline rate, and negative or very large gaps are clamped. HUD countdowns follow a server timestamp attribute, not the device clock. Small differences between servers (a few seconds) are accepted, no time-sync system.

- **Cheaters: log and ignore, no automatic bans in version 1.** A bad request is dropped with no effect, and logged with the player ID, the remote and the reason. A player sending many bad requests in a short time gets that remote refused for a while. No kicks or bans from code (false positives, such as a laggy double tap, are likely, and bans are a product decision with appeals). Revisit after launch if the logs show a real pattern, starting with manual bans from a dashboard. A feature switch in `Config` (for example to turn off cases) lets us disable something after launch without a full republish.

### Who may change what
| State | Only changed by | Triggered by |
|---|---|---|
| Cash, TP | `Economy` | Match payout, pad buys, store, daily claim, receipts |
| Owned players, levels, stars | `Roster` | Pad buys, training pad, case receipts |
| Field lineup | `Roster` (top N by income) | Automatic after any roster change |
| Stadium tier | `Stadium` | Stadium pad or `UpgradeStadium` |
| Store levels | `Store` | Store pad or `BuyStoreUpgrade` |
| Season, trophies, head start | `Season` | `StartNewSeason` |
| Legend trial progress | `Legends` | Recomputed by the server from state |
| Cooldowns, kicks | `Daily` | `ClaimDaily`, `PenaltyKick` |
| Cosmetics owned and chosen | `Cosmetics` | `SetCosmetic`, receipts |
| Plot ownership | `Plots` | Claim ring, join, leave |
| Receipts | `Purchases` | `ProcessReceipt` |

### Threats covered (summary)
Forged price or ID (IDs only from `Config`), double tap or resent message (numbers seen, one-step check and change), double receipt (`PurchaseId` record), clock change (server clock), remote flooding (rate limits and cooldowns), standing on someone else's pad (owner check), teleport to a pad (all other rules still apply), training drill bots (rate and stamina cap), client-side value edits (server never reads them back).

## Step 6: saving (agreed)

Principle: one small profile per player, saved safely, and a failed load never lets someone play on a blank profile. Each item below was discussed and agreed.

### Decisions
- **ProfileStore for saving**, not hand-written DataStore code. It gives session locking (one server holds a profile at a time, which stops duplicated progress when a player hops servers), retries and throttling, a Mock mode for Studio, and template reconcile. It is free: Apache-2.0 license (checked on the official repo page, not the full text). Copy a pinned version into `src/server/` with its LICENSE and copyright notice beside it, read its current documentation before using it, and do not auto-update.
- **Profile shape: small and flat, only what cannot be recomputed.** Key `Player_<UserId>`.

```
version        1
cash, tp
staminaLeft            seconds left in the current session
lastSeen               server time, for offline earnings
stadiumTier
storeLevels            { cashPerMatch, matchSpeed, hatTrick, offline }
fieldStarted           true once the first player is on the field
players                { [playerId] = { level, stars } }   owned only, Legends included
season                 { number }
trials                 { [legendId] = { [goalId] = true } }   goals are never unset
cosmetics              { owned = { [id] = true }, chosen = { kit, crest, ... } }
daily                  { caseClaimedAt, penaltyBatchAt, kicksUsed }
boosts                 { bankedMatches, stadiumBoostLeft }
receipts               { [purchaseId] = { at, result } }
pendingReveals         results the player has not seen yet
seenRarities           { Common = true, ... }
flags                  { firstHatTrickDone, notificationAsked, ... }
```

  - **Derived values are not stored:** the field lineup, the permanent multiplier, head-start floors, the trophy shelf and floor completion come from `players` and `season.number`.
  - **New Season is one step** that rebuilds the progress fields from the template and the head-start rule, and keeps `trials`, `cosmetics`, Legends, `receipts` and `season.number + 1`. A crash before saving loses the reset, never progress.
  - IDs in the profile (players, products, cosmetics) come from `Config`, never names.
  - **Versioning:** a `version` number and ordered migration functions run on load, then ProfileStore reconcile fills new fields from the template. Reconcile handles added fields, migrations handle changed meaning. No field is renamed or repurposed without a migration.
  - **Checks before saving:** numbers finite and within the `Config` maximum cash, and `players` keys must be known IDs, because one bad value fails the whole write.
- **When we save.** ProfileStore's autosave (about every 30 seconds) is the baseline, so a server crash loses at most about 30 seconds of normal play. On top of that there are **forced saves** at moments that matter: right after any Robux purchase (the receipt is confirmed to Roblox only after the save succeeds), at New Season (the reset and trophy are written together), at a stadium upgrade, at buying a Legend and at finishing a Legend Trial goal. Leaving ends the session and saves, and `BindToClose` waits for every profile to finish. Cash, TP and ordinary pad buys are not saved one by one (rate limits, and autosave covers them). Saves run in the background and never block the game, except that a purchase reveal waits for its own save. If a forced save fails it is retried a few times, and a purchase is left unconfirmed so Roblox retries it later and nobody is charged without receiving the item.
- **When loading fails, nobody plays on a blank profile.** The server retries quietly for a short time (a few attempts over about 10 to 20 seconds, which also covers a lock left by a quick server hop) while the player sees a loading screen ("Loading your stadium…") and no plot is claimed yet. The lock is never stolen, because that could erase progress from the other server. If it still fails the player is kicked with a clear message ("Couldn't load your save. Please rejoin in a minute. Your progress is safe."). A blank profile could be saved over the real one, which is the worst failure in the game. A failed save during play does not kick anyone: the profile in memory is correct and the save is retried. If another server takes the profile mid-session (ProfileStore signals this), that player is kicked at once so two servers never change one profile. Load and save failures are logged so a DataStore outage is noticed early.
- **Receipts and purchases.** `receipts` stores each purchase as `{ at, result }` keyed by `PurchaseId`. `ProcessReceipt` looks the ID up first: if it is there the item is not granted again, and for a case the saved result is returned. If the profile is not loaded (just joining, or the player already left) the answer is "not processed yet" and Roblox retries later. Receipts are kept for 30 days or the last 100, whichever is more, and pruned on load. Order: the grant and the receipt entry are written together, then the forced save, then the receipt is confirmed to Roblox, then the case animation is sent to the client. A failure before the confirm loses nothing. `pendingReveals` holds case results the player has not watched, so a disconnect mid-animation shows the reveal on the next join. Support disputes use `receipts` plus the Roblox Creator Dashboard purchase records. No separate ledger in version 1.
- **Testing without touching real data.** Studio uses ProfileStore Mock mode by default (data only in memory, so every playtest starts fresh). Tests that need real saving use a differently named store (for example `PlayerData_Studio`), and the live game uses `PlayerData` only, chosen from one switch in `Config` so they never mix. A reset command and a few ready-made profiles (floor 2 complete, floor 3 complete with Legends ready, season 3) exist only in Studio, not in a published server, and the check cannot be turned on from the client. Before launch, one full save, rejoin and migration test on the Studio store is a Step 8 checklist item. No automated unit tests for the save code: the shared formulas are checked in Studio with the MCP tools and the save path is mostly ProfileStore's own tested code.

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
| Legends | Legend Trials (training, owned players, stadium tiers) plus the cash price, or a direct Robux purchase. No stars in the trials, no separate expensive cash route |
| Stars | Paid-only (case duplicates), capped at +50% per player, never required by a free goal |
| World | Shared world, claimable plots, personal building and pitch |
| Robux player case | Ships in version 1 with the Step 4 rules (odds shown, no pity or luck boost, none in the first 30 minutes, one purchase per confirm) |
| Rarity reveal | First player of each rarity (Common included) gets a 3 s reveal (2 s for the first purchase): rarity colour background, name and number, ball trick, skippable. Every case win gets a reveal, duplicates show the star gained |
| Waits | Idle by design. Training drill raises TP up to about 15 per minute while played, idle rate stays the baseline. No quests or tap-to-boost in version 1 |
| Customization | Each stadium tier unlocks free styles to choose and a few Robux cosmetic styles. Purely cosmetic, kept across seasons, direct purchase only |
| Daily return | HUD icons for the free daily case and the penalties from minute 5, 20-hour cooldown from claiming, no streak |
| Plots | 8 per server (decided) |
| Trophies | One generic-named trophy per finished season, shown on a shelf in the entrance hall, cosmetic |
| Rebirth head start | Season 2 keeps floor 1, season 3+ keeps floors 1 and 2. Floor 3 is never granted (it opens floor 4 and the next season) |
| Rebirth | New Season stays optional. Button and explainer visible from floor 3 reached (locked), startable when floor 3 is complete. Legends and Robux purchases kept (provisional) |
| Names | Real names, names kept in Config, risk acknowledged |

## Steps still to do
3. Economy: drafted and tested with a simulation (needs real playtests)
4. Retention and ethics review: agreed (needs playtest data)
5. Architecture and security: agreed (roblox-architecture, roblox-security)
6. Saving: agreed (roblox-data)
7. Build and polish (roblox-building, roblox-gui, roblox-lighting)
8. Launch (roblox-publish-checklist, roblox-monetization, roblox-growth-design)
