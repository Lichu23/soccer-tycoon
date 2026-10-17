# soccer-tycoon: design plan

Status: step 1 (core loop) agreed. Steps 2 to 8 are still to do.

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

### Squad and stadium
- Players have an income value (no "strength"). Each stadium level unlocks more squad slots.
- The stadium upgrade costs cash only. The UI shows a slot counter such as "Squad 1/3", with empty slots drawn as outlines.
- Slot counts per stadium level are decided in step 3 (placeholder: 1, 3, 5, 8, 11).
- Positions arrive in a fixed order (striker first, goalkeeper and the rest later) so the formation fills like a real team.
- Every player ever signed stays in the **trophy room** (display shelf) with a small collection bonus. Only players in squad slots earn.
- Rarity: Common, Rare, Epic, Legend. Use invented names, not licensed real players.

### Training ground
- A place on the map where standing earns **training points (TP)**, spent on levelling players (more income).
- A **stamina bar** is the cap: it drains while training and refills while away.
- **Stations by position** (striker goal, midfield cones, defence wall, keeper gloves). A station unlocks with its position.
- TP are earned only while present. Level caps by rarity (Common 5, Rare 10, Epic 15, Legend 20, placeholders).
- TP are never sold for Robux.

### Daily penalties
- 3 kicks a day. Goals give a x1.5 income boost: 3 goals = 10 min, 2 = 5 min, 1 = 3 min, 0 = nothing.
- The server judges each kick (the client only sends the aim) and decides the reset time. No day-streak, no penalty for skipping.

### Store (cash)
Match speed, cash per match, hat-trick chance (later), offline earnings. The stadium level replaces a separate "capacity" upgrade.

### Cases and legends
- **Free daily case:** cash or temporary boosts only, never players, never large amounts. No login streak.
- **Player case (Robux):** CS-style case-opening animation. The server decides the result first, then the animation shows it. Odds shown before purchase. Roblox treats this as a paid random item: odds disclosure is required, pity systems and luck boosts count as paid random items too, and a `PolicyService` restriction may apply to some users. Before building, check current policy and offer the documented alternatives (direct purchase, earnable reward, a known non-random sequence) for affected users.
- **Legends:** two routes. Free route reachable in roughly 2 to 4 weeks of casual play. Cash route is much more expensive than the early game. Robux route is a direct purchase at a clearly shown price. Legends are trophy and cosmetic heavy, with a bonus only in their own position.

### World
- Shared world, personal stadium: players share one map and see each other. Each owns a plot with their own stadium. Visitors can see trophies.
- Blocky cartoon style. Mobile first.

### Decisions log
| Topic | Decision |
|---|---|
| Opponent | Cosmetic only, always a win |
| Streak | Momentum, session only |
| Training | TP from a training ground with a stamina cap |
| Stadium cost | Cash only |
| Trading | Out of version 1 |
| Roulette | Replaced by cases (free daily, Robux player case) |
| Legends | Free grind or cash or Robux |
| World | Shared world, personal stadium |

## Steps still to do
2. First 5 minutes (roblox-game-design + product-psychology)
3. Economy: prices, income, slot counts, first prestige timing
4. Retention and ethics review
5. Architecture and security (roblox-architecture, roblox-security)
6. Saving (roblox-data)
7. Build and polish (roblox-building, roblox-gui, roblox-lighting)
8. Launch (roblox-publish-checklist, roblox-monetization, roblox-growth-design)
