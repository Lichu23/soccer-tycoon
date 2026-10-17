# soccer-tycoon: design plan

Status: steps 1 and 2 agreed (items marked *provisional* use defaults and can change). Steps 3 to 8 are still to do.

## Step 1: core loop

### Match (the income engine)
- Every ~10 s an automatic mini-match plays on the player's pitch. It is PvE in name only: there is no opponent strength.
- The match is always a win. The opponent is cosmetic (name and kit colour). Goals on the scoreboard are derived from the payout.
- The server computes the payout and adds the cash. The client only plays the animation.

```
payout = base x sum(player income) x upgrades x momentum x daily boost x (hat-trick 2x if rolled)
```

- **Hat-trick:** small random chance (about 10%) of a 2x match. A Store upgrade can raise the chance later.
- **Momentum:** session-only bonus for matches played in a row (for example +1% per match, capped). Never saved. Resets to 0 on join.
- **Offline earnings:** capped. Matches pay offline.

### Stadium: 3 floors of capsules
Players are physical displays in the world (glass capsules on pedestals, like a tycoon). There is no inventory menu and no picker. Buying a player is placing it. A capsule is both the squad slot and the trophy.

| Floor | Players | Rarity |
|---|---|---|
| 1 | 10 | Common + Rare (placeholder split 6 + 4) |
| 2 | 10 | Very Rare + Epic (placeholder split 5 + 5) |
| 3 | 5 | Legend |

- 25 players in total. Rarity tiers: Common, Rare, Very Rare, Epic, Legend.
- Each capsule is one specific named player with a fixed price and income. Dark capsules show a price pad in front.
- **A floor opens when the previous floor is complete** (all its players owned). Players won from cases count as owned for completion. Nobody is ever replaced or removed.
- A player won from a case on a floor the player has not reached is owned. Their capsule is shown lit behind a glass barrier on the locked floor (a teaser). The rest of that floor stays dark and cannot be bought until the floor opens.
- Capsule order and the guide arrow lead the player through the buying order.
- **Only the players on the field earn** (see Plot below). Owned players beyond the field capacity wait on the bench in their capsules. Counters are shown as "x/N" per floor.

### Cases and stars
- A case result that is a player you do not own unlocks that capsule for free. A duplicate adds a **star** to that player: income +X% per star, capped (placeholder 5 stars, modest bonus per star).
- **Case pool includes players from higher floors, but with minimum chances** (the better the player, the lower the odds). Higher-floor players are much rarer than players from reached floors, and the field capacity limits how much a lucky case can earn. Exact odds are set in step 3 and shown before purchase.
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

### Store (cash)
Match speed, cash per match, hat-trick chance (later), offline earnings.

### Plot: building and pitch
- Each plot has two areas: **the building** (capsule floors, where you farm and own players) and **the pitch outside** (where matches are shown).
- The match scene is a short scripted animation. The server has already decided the result and payout. Opponents are cosmetic dummies in a rival kit.
- **Field capacity:** only the top N owned players by income are on the field and earn, with N set by the stadium tier. Benched players are not removed.

| Stadium tier | Pitch | Players on the field (placeholder) |
|---|---|---|
| 1 (start) | Street futsal court: walled, painted lines, centre circle, flags and murals (blocky) | up to 4 |
| 2 | Local ground: fences, small stand | up to 7 |
| 3 | Club stadium: floodlights, bigger stand | up to 9 |
| 4 | Pro stadium: roof, crowd, scoreboard | 11 |

- The stadium tier costs cash only. Floors and stadium tier are two separate tracks (floors by completion, tier by cash).
- **Upgrade animation:** the server confirms the purchase, that player's controls are locked and the camera moves to a cinematic view for about 5 to 8 s while the pitch transforms, then the new capacity shows and controls unlock. It has a time limit (so nobody gets stuck), affects only that player, and the server finishes the upgrade even if the player leaves.

### World
- Shared world, personal stadium: players share one map and see each other. Each owns a plot with their own stadium. Visitors can see trophies.
- Blocky cartoon style. Mobile first.

### New Season (rebirth) (*provisional*)
- Called "New Season", not leagues: the 25 players stay the same.
- Unlocked after floor 3 is reached and a cash threshold is met (target first rebirth about 45 to 60 minutes in).
- **Resets:** cash, floors back to floor 1, cash-bought players, Store upgrade levels, TP levels.
- **Stays:** anything bought with Robux, trophies, the permanent income multiplier (diminishing returns), stars, the collection record.
- Confirm screen shows exactly what is lost and gained. Optional, no timers, no guilt.
- Trophies perk shop: later, not in the first release.

### Naming
- **Decision (made by the project owner):** use real player names. Known risk: names, and any faces, club badges or logos, are covered by image, publicity and trademark rights, and a rights holder can request a takedown or take legal action. Real names, faces and club badges are outside what has been checked against Roblox policy.
- Safeguard: every player's name, nationality, number and description live in one `Config` table (not in code or models), so names can be swapped in minutes if a notice arrives or the decision changes.
- Keep real names away from paid features where possible.

## Step 2: first 5 minutes (all on floor 1)

Principles: value in the first 10 s, teach by doing (no popups), one new idea per minute, never an empty wait, finish the section on a peak.

| Time | What happens | Purpose |
|---|---|---|
| 0:00 | Player spawns at their plot holding $15. A guide arrow points at a glowing pad on the first capsule: "Sign player $10". | One obvious action |
| 0:10 | They step on the pad, the first Common player appears in the capsule, kick-off. | First purchase in about 10 s |
| 0:15 | First match (about 5 s). Goal celebration, "+$" pop-up, cash ticks up. | First reward, loop understood |
| 0:30 to 1:00 | Matches keep paying. The Store pad glows when affordable, the arrow points to it. | Guide without a menu |
| 1:00 | First upgrade (Cash per match, about $20). Next matches pay visibly more. | Spending makes numbers go up |
| 1:30 | A locked silhouette of the floor 2 entrance appears with a price and a progress bar that fills from match income. | A goal that fills the wait |
| 2:30 | Next capsules light up in order, the arrow points at each. They buy two more players. | Buying order is the tutorial |
| 3:30 | A player is the first Rare on the floor: a small reveal animation. | First small peak |
| 4:00 to 4:30 | First hat-trick (scripted once, afterwards real odds apply). Bigger celebration. | Surprise before the main peak |
| 5:00 | **Peak:** the player buys a standout Rare capsule with a spotlight and crowd reaction. Locked silhouettes of floor 2 players appear behind it. | Main peak and end of the section |
| After 5:00 | The daily penalty pad appears with a short clear prompt. More Store options appear gradually. | Loop established |

Not in the first 5 minutes: training ground, cases, Robux shop, notifications, leaderboard, rebirth. They open later, one at a time.

Provisional defaults: start with $15, scripted first hat-trick (not tied to a purchase), daily penalties introduced right after the first peak.

### Verify (after build)
Time to first purchase under 15 s; share reaching the end of floor 1 or the floor 2 silhouette by minute 5 (below about 60% means pacing is too slow); where players drop; day-1 return.

### Ethics check
Pass: no fake timers, no scarcity, no guilt, nothing for sale in the first 5 minutes.

## Decisions log
| Topic | Decision |
|---|---|
| Opponent | Cosmetic only, always a win |
| Streak | Momentum, session only |
| Stadium | 3 floors of capsules, 10 + 10 + 5 players |
| Placement | Buying places the player, no inventory menu |
| Duplicates | Add a star (income bonus, capped) |
| Training | One training ground, stamina bar cap (provisional) |
| Stadium tier cost | Cash only |
| Floors | Open when the previous floor is complete |
| Field capacity | Only the top N players earn, N by stadium tier, others on the bench |
| Cases and floors | Cases can give higher-floor players, at minimum chances |
| Trading | Out of version 1 |
| Roulette | Replaced by cases (free daily, Robux player case) |
| Legends | Free grind or cash or Robux |
| World | Shared world, personal stadium |
| Rebirth | New Season, same roster (provisional) |
| Names | Real names, names kept in Config, risk acknowledged |

## Steps still to do
3. Economy: prices, income, stars, TP and level costs, first rebirth timing
4. Retention and ethics review
5. Architecture and security (roblox-architecture, roblox-security)
6. Saving (roblox-data)
7. Build and polish (roblox-building, roblox-gui, roblox-lighting)
8. Launch (roblox-publish-checklist, roblox-monetization, roblox-growth-design)
