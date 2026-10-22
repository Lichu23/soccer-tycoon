# Fair price analysis

2026-10-22 · commit `d67d9c4` on `phase-4-expansion`

## Summary

Every price now follows one rate: about **3 to 4 Robux per minute of play saved**. Before this change, several products cost far more than they were worth. A free player who trained only on the idle stations also needed over 3 years to finish the game.

- **Worst value before:**
  - Fixed cash packs: $1M for 349 Robux saved 0 minutes after minute 17.
  - Elite Case: 149 Robux for 1 to 6 minutes saved.
  - 30-match boost: about 3 to 5 minutes for 39 Robux.
  - 10-minute x2 TP: it only pays while stamina lasts.
- **Price fixes:**
  - Cash packs are now minutes of the player's own income.
  - The Elite Case only rolls players you don't own, for 79 Robux.
  - The match boost is removed.
  - x2 TP lasts 20 minutes.
  - Buying a Legend with Robux still needs his trials done.
- **Balance fixes:**
  - Pelé's trial was three quarters of the game; it dropped from about 144K TP to 75K.
  - Idle training doubled to 20 TP per minute.
  - The season bonus slows after season 10.
  - Stadium tier 5 now pays x7.3.
- **Result:**
  - A 30-minute-a-day player who juggles finishes on day 164 instead of 253.
  - An idle trainer finishes on day 384 instead of 1,172.
  - The first Legend still comes around day 15 to 19.

## Method

Two simulations ran the game's real economy code (`Actions`, `MatchLogic`, `Boosts`, `Cases`, `Legends`, `NewSeason`) in Lune.

1. **Minutes of play saved.** A free player buys the cheapest next thing as soon as they can afford it, until floor 3 is complete (155 minutes). Each product is given at five stages (floor 1 done, floor 2 done, owning player 23, 26 and 28), then the climb is run again. "Minutes saved" is how much sooner floor 3 is complete.
2. **Finish line.** The same player continues to own all five Legends. This run adds New Seasons, the training stamina cycle, levelling for the Legend Trials and for income, the daily penalties and free case, and 25% offline income each night. It tests four player types and several New Season strategies.

Limits:

- Juggling is assumed to average 50 TP per minute while stamina lasts. The daily penalties are assumed to score 2 goals of 3.
- No Robux purchases are made in the finish run.
- Real players are slower than a bot that always buys the cheapest next thing. Income per minute at a given stage is the same either way, because it depends on what the player owns, not how fast they got there.

The simulation scripts are not in the repo. They have to sit in `tests/` to run.

## Exchange rate

The 10-minute x2 Cash boost costs 39 Robux and saves 10 to 15 minutes of play. That sets the rate at **about 3 to 4 Robux per minute saved**, and every other product is priced against it.

TP is valued separately. Juggling earns about 25 TP per minute of play once stamina is counted (50 TP a minute while stamina lasts, about half the time). Training runs alongside matches, so a minute of play earns cash and TP together, and TP is priced at about half the time rate: **roughly 0.07 to 0.1 Robux per TP**.

## Robux prices

| Product | Before | What it was worth | Now |
|---|---|---|---|
| x2 Cash | 10 min, 39 | saves 10 to 15 min | 10 min, 39 (unchanged) |
| x2 TP | 10 min, 39 | pays only while stamina lasts: about +250 TP juggling, +50 idle | **20 min, 39** |
| x2 Cash + TP | 69 | the two above | 69 (cash 10 min, TP 20 min) |
| Match boost | 30 matches, 39 | 2.5 min once matches take 5 s; saved 2.75 to 5.6 min | **removed** |
| Cash packs | $10K / $100K / $1M for 25 / 99 / 349 | 0.3 / 1.3 / 3 min when floor 1 is done; 0 after minute 17 | **15 min / 1 h / 4 h of income for 39 / 129 / 399** |
| TP packs | 500 / 2,500 / 10,000 for 25 / 99 / 349 | cheap for the main bottleneck | **39 / 149 / 499** |
| Standard Case | 49 | 5 to 12 min of cash plus about 6 min of TP; about 70% of the cash value is the x2 cash boost slots | 49 (unchanged) |
| Elite Case | 149 | 6.4 min when it unlocks, 1.1 min late in floor 3; 65% to 97% of pulls were duplicates | **79, only players not owned yet** |
| Legends | 799 to 3,499 | the cheapest route to a Legend (the Elite Case averaged about 7,450 Robux per Legend) | same prices, **trials still required** |
| Robux cosmetics | 79 to 199 | no gameplay value | unchanged |

Why the Elite Case lost so much value: a duplicate adds a star, but stars only count for players on the field. Most duplicates landed on cheap players on the bench, where a star adds nothing.

## Cash prices

Income per minute depends on what the player owns, not how fast they got there:

| Stadium tier | Cash per minute |
|---|---|
| 1 | $30 to $325 |
| 2 | $0.7K to $28K |
| 3 | $55K to $640K |
| 4 | $0.9M to $12M |
| 5 | $12.6M to $83M |
| 6 | $99M to $302M |

The plan said a cash cosmetic should cost 10 to 20 minutes of income at its tier. Most were 10 to 40 times cheaper than that. The two cash prices in each slot are now about 10 and 25 minutes of income near the end of the slot's tier:

| Slot (tier) | Before | Now |
|---|---|---|
| Kit (1) | 2K / 6K | 3K / 8K |
| Crest (2) | 15K / 40K | 300K / 700K |
| Banners (3) | 300K / 800K | 6M / 15M |
| Floodlights (3) | 1M / 2.5M | 8M / 20M |
| Light colour (4) | 3M / 8M | 120M / 300M |
| Scoreboard (5) | 60M / 150M | 800M / 2B |
| Stadium colour (6) | 300M / 800M | 3B / 7.5B |
| Stadium name (6) | 100M | 1.5B |

Floodlights sit just above banners because a test requires each slot's cheapest cash price to be higher than the slot before.

Store upgrades did not change. Match speed level 5 pays for itself in about 8 minutes, and hat-trick level 3 in about 28.

## Economy changes

| Change | Before | Now | Why |
|---|---|---|---|
| Pelé trial | 10 players at level 15 (~144K TP) | 8 players at level 12 (~75K TP) | it was about 75% of the whole game |
| Idle training | 10 TP/min | 20 TP/min | idle players were 4.5x slower than jugglers; the plan says the trials are tuned on the idle rate |
| Season bonus | +0.5 every season, no limit | +0.5 up to season 10 (x5.5), then +0.1 | a bot that reset at once went through 3,631 seasons |
| Stadium tier 5 | x6.7 | x7.3 | it added only +3% income and took about 2 h to pay for itself |

## Finish line: time to own all five Legends

These results use the best New Season strategy: start a new season unless the next Legend is within about 4 hours of income.

| Player | Before | After |
|---|---|---|
| Plays nonstop, juggles | 136 h | 95 h |
| 2 h a day, juggles | day 67 (134 h) | day 45 (88 h) |
| 30 min a day, juggles | day 253 (126 h) | day 164 (82 h) |
| 30 min a day, idle trainer | day 1,172 (586 h) | day 384 (192 h) |
| Plays nonstop, idle trainer | 617 h | 201 h |

- The first Legend comes on day 15 to 19 for a 30-minute player. That matches the plan's target of about 3 weeks.
- Training is still the last wall. Pelé's trial takes about 50 h of juggling after Maradona is owned.
- Idle players are still about 2.3x slower than jugglers.
- New Seasons help with cash, not training. TP and levels reset each season, so a training goal must be finished within one season.

## Ethics check

- **Fixed cash packs failed the Regret test.** A floor-3 player paid 349 Robux for a few seconds of income. Packs sized by income fix this.
- **Robux Legends skipping the trials** let a payer finish in about 3 hours against about 130 for a free player. That left the payer nothing to aim for, which hurts retention. A Robux Legend now skips only the cash price.
- **Cases** still show their odds before purchase, have no pity system and no luck boosts, and are hidden for players that `PolicyService` restricts.

## Status

- **Committed** in `d67d9c4`.
- **Tests:** 434 pass, and format and lint are clean.
- **Type check:** 3 type errors remain in code this change did not touch: `Config.luau` (the case boosts list), `AvatarActor.luau` and `CaseModal.luau`.
- **Studio playtest, buying through the real server:**
  - A cash pack before the first player is refused.
  - With floors 1 and 2 owned, a 15-minute pack paid +$4.2M, which matches the field's income.
  - x2 TP runs 20 minutes.
  - Three Elite Cases gave three floor-3 players the player didn't own.
  - A Legend without his trials is refused.
  - The pads and the Shop show the new labels and prices.
- **Before launch:** the Robux prices go on the Creator Dashboard, since every product still has `productId = 0`.
