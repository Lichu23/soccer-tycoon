# Icons for soccer-tycoon: list, prompts and workflow

The HUD already reads its pictures from `src/client/Icons.luau`. An empty id shows the text label, so the
game works without art. Fill an id and that tile or badge shows the picture.

## 1. Shared style (paste this into every prompt)

> Mobile game UI icon, cartoon style, one single object centred, thick dark navy outline, bold saturated
> flat colours with a soft glossy highlight on top, simple shapes, clean edges, no text, no letters, no
> numbers, no watermark, transparent background, square 1:1.

Rules that keep the set consistent:
- Same style paragraph for every icon. Change only the subject line.
- Generate the first icon, pick the best one, then use it as the **style reference / image prompt** for
  the rest (most tools have this). Keep the same seed or "style" setting when the tool offers one.
- No logos, club badges, real player faces or names, no brand marks (the plan's naming-risk rule).
- Add the accent colour of the tile so it matches its outline in the game (below).

## 2. What to make, in this order

### Priority 1: the HUD (8 icons, 256 x 256 PNG)
| Name in `Icons.luau` | Subject line | Accent colour |
|---|---|---|
| `case` | a closed treasure-style prize crate with a gold lock and a small star | orange |
| `kick` | a soccer ball just kicked into a goal net corner | green |
| `shop` | a small market stall with a striped awning | gold |
| `locker` | a team locker with a jersey hanging inside | blue |
| `alerts` | a bell with a small sound wave | purple |
| `cash` | a stack of green banknotes with a coin | green |
| `tp` | a lightning bolt on a small dumbbell | blue |

### Priority 2: inside the screens (about 12 icons)
| Use | Subject line |
|---|---|
| Season button | a golden trophy cup |
| Boost badge | a green arrow up with x2 shape (no letters: two small arrows) |
| Standard Case | a plain wooden crate with a silver band |
| Elite Case | a golden crate with a glowing keyhole |
| Store: cash per match | a coin with a small plus |
| Store: match speed | a stopwatch with a fast streak |
| Store: hat-trick | three soccer balls in a row |
| Store: offline | a moon with a small coin |
| Locker slots: kit / crest / banners / floodlights / scoreboard | a jersey / a shield / a pennant flag / a stadium floodlight / a scoreboard panel (5 icons) |

### Priority 3: the store page (Step 8, 5.7)
- Game icon, 512 x 512, one bold subject (a soccer ball and a trophy on a stadium glow).
- Thumbnails, 1920 x 1080, 3 of them: the claim, the pitch with a goal, the Locker room. These are best
  made from real in-game screenshots with a title added, not from AI.

## 3. Per-icon prompt (copy, replace the bracket)

> Mobile game UI icon, cartoon style, [SUBJECT LINE], [ACCENT COLOUR] accent colour, thick dark navy
> outline, bold saturated flat colours with a soft glossy highlight on top, simple shapes, clean edges,
> centred single object, no text, no letters, no numbers, no watermark, transparent background, square.

Negative prompt (where the tool has the field): `text, letters, watermark, realistic photo, busy
background, blurry, multiple objects, cropped`.

## 4. Free or trial tools (check the terms yourself; they change)

Always check three things on the tool's own pricing and terms page: (1) the free plan allows
**commercial use**, (2) no watermark, (3) **transparent PNG** is included. If a tool gives a solid
background, remove it afterwards (Photopea, or Canva's "Remove background", or remove.bg).

- free.ai icon maker: https://free.ai/icon/ (says no sign-up, no watermark, commercial use, transparent PNG)
- insMind AI icon generator: https://www.insmind.com/ai-icon-generator/ (a transparent background switch)
- MiriCanvas AI icon: https://www.miricanvas.com/en/features/ai-icon (commercial use stated, remove background option)
- Also worth a look: the free credits of general image tools (Bing Image Creator, Ideogram, Leonardo,
  Adobe Firefly, Canva). Free limits and licences differ and change, so verify before relying on one.
- Edit and clean up for free: Photopea (photopea.com), Krita, or Canva.

Keep every generated file and note the tool, date and plan you used, in case the terms are asked later.

## 5. From image to game

1. Clean the picture: transparent background, crop to a square with about 10% empty margin, export
   **256 x 256 PNG** (512 for the game icon). Name it like the table: `case.png`, `kick.png`, ...
2. In Roblox Studio, open **Window > Asset Manager** (or the Home tab), click the import button at the
   top of the panel and pick all the PNGs. Use the account that owns the game. Wait for the
   moderation to pass (usually minutes).
3. In the Asset Manager, right-click each image > **Copy Asset ID**.
4. Send me the list `case = 123..., kick = 456...`. I put `rbxassetid://<id>` in `src/client/Icons.luau`
   and the tiles show the pictures. A picture that fails to load falls back to the text label.
5. Check on the phone preset that every icon is readable at 46 px (simple shapes read best).

## 6. Status (2026-10-19)
The first set is imported and wired in `src/client/Icons.luau`: tiles for case (the gift box), kick, shop,
locker and alerts; tiles for cash and tp (new versions, a square tile at the left of the money and TP boxes instead of the round badge); the trophy tile replaces the drawn cup on the New Season badge (the badge keeps its shape, place and rules). The
source files are in `OneDrive/Imágenes/Roblox Soccer Tycoon/icon_set_v2` (tiles, icons and the SVGs).
A closed button shows its tile greyed with the padlock at the bottom-right corner.
