# soccer-tycoon: design plan

Status: steps 1 and 2 agreed (items marked *provisional* use defaults and can change). Steps 3 to 8 are still to do.

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
- **Offline earnings:** capped. Matches pay offline.

### Stadium: 3 floors of capsules
Players are physical displays in the world (glass capsules on pedestals, like a tycoon). There is no inventory menu and no picker.

| Floor | Players | Rarity |
|---|---|---|
| 1 | 10 | Common + Rare (placeholder split 6 + 4) |
| 2 | 10 | Very Rare + Epic (placeholder split 5 + 5) |
| 3 | 5 | Legend |

- 25 players in total. Rarity tiers: Common, Rare, Very Rare, Epic, Legend.
- Each capsule is one specific named player with a fixed price and income.
- **Purchase pad:** each capsule has a pad on the floor in front of it showing the name and price. The player buys by standing on the pad (a short ring fills for about half a second to avoid accidental buys). If they cannot afford it, the pad shows the missing amount. The server decides the purchase and checks proximity.
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

### Legends (floor 3)
Two routes: free route reachable in roughly 2 to 4 weeks of casual play, or a much more expensive cash route, or a direct Robux purchase at a clearly shown price. A Legend bought with Robux can only be bought inside the building once floor 3 has been reached, so the rule is the same for everyone. Never reset anything bought with Robux.

### Training ground
- One training ground where standing earns **training points (TP)**, spent on levelling any owned player (more income) (*provisional*: no position stations, since rosters are fixed).
- A **stamina bar** is the cap: it drains while training and refills while away. TP are earned only while present, never offline, never sold for Robux.
- Level caps by rarity (Common 5, Rare 10, Very Rare 15, Epic 20, Legend 25, placeholders).

### Daily penalties
- 3 kicks a day. Goals give a x1.5 income boost: 3 goals = 10 min, 2 = 5 min, 1 = 3 min, 0 = nothing.
- The server judges each kick (the client only sends the aim) and decides the reset time. No day-streak, no penalty for skipping.

### Store
- **Cash upgrades:** match speed, cash per match, hat-trick chance (later), offline earnings. No daily limit: rising prices are the gate. Every upgrade is reachable with cash.
- **Robux match boost:** "next 5 matches x2" (developer product, price and size on the button). Boosted matches are banked up to a **maximum of 10**, shown by a counter ("Boosted matches left: 7"). It can be bought again once the bank has room. Stacking with other boosts is capped (placeholder: total boost never above x4).
- Purchases are granted by the server and must be safe if the purchase message arrives twice (`roblox-monetization`).
- The offer lives in the Store only: no purchase popups after matches, nothing in the first 5 minutes.

### Plot: building and pitch
- Each plot has two areas: **the building** (capsule floors, where you farm and own players) and **the pitch outside** (the "stadium", where matches are shown). The building has an open or glass front so matches can be watched from the pads (*provisional* layout: pitch in front, building behind).
- The match scene is a short scripted animation. The server has already decided the result and payout. Opponents are cosmetic dummies.

| Stadium tier | Pitch | Players on the field (placeholder) |
|---|---|---|
| 1 (start) | Street futsal court: walled, painted lines, centre circle, flags and murals (blocky) | up to 4 |
| 2 | Local ground: fences, small stand | up to 7 |
| 3 | Club stadium: floodlights, bigger stand | up to 9 |
| 4 | Pro stadium: roof, crowd, scoreboard | 11 |

- The stadium tier costs cash only. Floors and stadium tier are two separate tracks (floors by completion, tier by cash). The price is taken from the player's cash, and the server charges and applies the upgrade in one step.
- **"Next goal" HUD row:** a small row under the money label shows one goal at a time ("Next goal: Stadium upgrade", progress bar, "$120 / $200"). It follows the buying path (first player, start the game, first upgrade, next players, stadium upgrade). It is not a list of every upgrade.
- When the goal becomes affordable, the row **glows brightly** and reads "Stadium upgrade available!", and the guide arrow points to the pad. The glow pulses a few times and then stays steady. No sound and no nagging.
- **Upgrades can be bought from the HUD row** with a button (stadium tiers and Store upgrades), as well as by standing on the pad in the world. Because it is a big spend, the HUD button asks for a second tap to confirm. Players are still bought only on the capsule pads.
- **Upgrade animation:** the server confirms the purchase, that player's controls are locked and the camera moves to a cinematic view for about 5 to 8 s while the pitch transforms, then the new capacity shows and controls unlock. It has a time limit (so nobody gets stuck), affects only that player, and the server finishes the upgrade even if the player leaves.

### World and plots
- Shared world: players spawn in a shared area outside, with free plots in front. Visitors can see claimed plots, buildings and pitches.
- **Plot claiming:** the player walks onto a free plot's "Claim" ring. The server assigns it (so two players cannot claim the same one) and the building appears with a build animation. Plots equal max players per server (*provisional*: 8).
- When a player leaves, the plot is freed. Their saved data rebuilds their building on rejoin on any free plot.
- Idle players: the arrow points to the nearest free plot, and after about 20 s the server assigns one (*provisional*).
- Blocky cartoon style. Mobile first.

### New Season (rebirth) (*provisional*)
- Called "New Season", not leagues: the 25 players stay the same.
- Unlocked after floor 3 is reached and a cash threshold is met (target first rebirth about 45 to 60 minutes in).
- **Resets:** cash, floors back to floor 1, cash-bought players, Store upgrade levels, TP levels.
- **Stays:** anything bought with Robux, trophies, the permanent income multiplier (diminishing returns), stars, the collection record.
- Confirm screen shows exactly what is lost and gained. Optional, no timers, no guilt.
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
| 3:30 | The first Rare player is bought with a small reveal animation. | Small peak |
| 4:00 to 4:30 | First hat-trick, scripted once (afterwards real odds apply). The text reads "HAT-TRICK x2". | Surprise before the main peak |
| 4:30 | They buy the 4th player. The court shows "Field 4/4" and the stadium upgrade pad glows with its price and a progress bar fed by match income. | Creates the next goal |
| 5:00 | **Peak:** once they can afford the upgrade, a short message says "Stadium upgrade available!" and the arrow points to the pad (it never fires on its own and never nags). They pay by standing on the pad or by pressing the glowing HUD button. Controls lock, the camera moves, the court transforms into the local ground, and the new capacity shows ("Field 4 to 7"). | Main peak and transition |
| After 5:00 | The daily penalty pad appears with a short clear prompt. More Store options appear gradually. | Loop established |

Not in the first 5 minutes: training ground, cases, Robux shop, notifications, leaderboard, New Season. They open later, one at a time.

Provisional defaults: start with $15, scripted first hat-trick (not tied to a purchase), daily penalties introduced right after the first peak. Whether the stadium upgrade is affordable by minute 5 depends on prices (step 3).

### Verify (after build)
Time to first purchase under about 30 s; share reaching the first stadium upgrade by minute 5 (below about 60% means pacing is too slow); where players drop; day-1 return.

### Ethics check
Pass: no fake timers, no scarcity, no guilt, nothing for sale in the first 5 minutes.

## Decisions log
| Topic | Decision |
|---|---|
| Opponent | Cosmetic only, always a win |
| Match feedback | Loading bar in HUD, then "VICTORY" (or "HAT-TRICK x2") text and "+$N" on the money label |
| Store | Cash upgrades with no daily limit. Robux boost: next 5 matches x2, banked up to 10 |
| Streak | Momentum, session only |
| Stadium | 3 floors of capsules, 10 + 10 + 5 players |
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
| Rebirth | New Season, same roster (provisional) |
| Names | Real names, names kept in Config, risk acknowledged |

## Steps still to do
3. Economy: prices, income, stars, TP and level costs, case odds, first rebirth timing
4. Retention and ethics review
5. Architecture and security (roblox-architecture, roblox-security)
6. Saving (roblox-data)
7. Build and polish (roblox-building, roblox-gui, roblox-lighting)
8. Launch (roblox-publish-checklist, roblox-monetization, roblox-growth-design)
