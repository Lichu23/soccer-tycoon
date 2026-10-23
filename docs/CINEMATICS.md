# How to build a cinematic mini-game (like the 1v1 Breakaway)

This is the recipe the 1v1 Breakaway (`shared/Freekick`, `client/BreakawayScene`, `client/FreekickUi`)
was built with. Follow it for any new "the player does a few inputs, then a short film plays" feature:
a penalty shoot-out, a bicycle kick, a trophy lift, a celebration.

---

## 1. Split it into four pieces

| Piece | Where | Job |
|---|---|---|
| **Rules** | `src/shared/<Name>.luau` | Pure functions: phases, timings, judging, pay. No Instances, no services. Unit tested with Lune. |
| **Server actions** | `src/server/TrainingActions.luau` (or a new `<Name>Actions`) | Keeps the state per player, receives the remotes, calls the rules, pays, publishes attributes. |
| **Scene** | `src/client/<Name>Scene.luau` | Builds the 3D set and plays the film. Display only: `frame(view)` draws one moment. |
| **Screen** | `src/client/<Name>Ui.luau` | Opens and closes the scene, handles inputs, draws the HUD, plays sounds at the right moment. |

**Rule of thumb:** the server decides *what happened* (goal, save, tackle) the moment the last input
arrives. The film only *shows* it afterwards, so the outcome is never decided on the client.

---

## 2. Run everything on the server clock

Never send a message per frame. The state has a `phase` and a `stageAt` (the server time the phase
started). Everything that moves is a function of `now - stageAt`:

```lua
-- shared rules: the reticle at any time, identical on server and client
function Freekick.aimAt(state, at)
	local t = at - state.stageAt
	return range * (2 * sweep(t + across / 2, across) - 1), ...
end
```

- **Phases:** waiting for inputs (`dribble`, `aim`, `power`), then `shot` (the film), then `over`.
- **`normalize(state, now)`** advances what time alone changes: a timeout, the film ending, the next
  round. It is called on every tick and before every input. Bound its loop (`for _ = 1, 16`).
- **Inputs carry a timestamp** (`Workspace:GetServerTimeNow()` on the client). The server clamps it:
  never in the future, never more than `GraceSeconds` (0.2 s) in the past, never before the phase began.
- **Random but agreed:** anything random (the keeper's side, which move is asked) comes from a
  hash of `seed` and `kick` (`Freekick.setup`), so both sides compute the same thing without sending it.
- **Publish as player attributes** (`publishKick`); the client mirrors them in `readServerState`.
- **Film length lives in the rules** (`Freekick.filmSeconds(outcome)`), so the server knows when the
  film ends and the next round starts.

Add every new remote to `shared/RemoteSpec.luau` with types, ranges and a rate limit, and update
`tests/validate.spec.luau`. Pay through the existing capped path (`Training.gamePay`).

---

## 3. Build the set far from the map, on the client only

```lua
local ORIGIN = Vector3.new(6000, 400, 6000) -- nothing else is near here
local folder = Instance.new("Folder")      -- built on the client: nobody else sees it
```

- Build everything relative to `ORIGIN` with a small `at(x, y, z)` helper. **Every position in the
  film code is pitch-local**; convert world positions back with `pos - ORIGIN` before mixing them
  (the aim camera once added a world X and flew 2,400 studs away).
- Parts: anchored, `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false` for set dressing.
- Follow the CLAUDE.md look: `SmoothPlastic`, flat bright colours, navy (`Style.ui.panel`) for dark
  bits, never black. Crowds are coloured blocks on grey tiers.
- Surround the camera: build a stand behind every direction a camera looks, or the sky shows through.
- Build in `new()`, destroy everything in `destroy()`. Build it when the screen opens, not at startup.

---

## 4. Put people in it

### The player's own avatar (`client/AvatarActor`)
`AvatarActor.new(folder)` clones the avatar (or falls back to a mannequin) and returns `place`, `run`,
`pose` and `hipX`. The breakaway, the penalties and the keepie-uppies (`client/KeepieScene`) all use it;
the shared screen bits (takeover, reticle, power meter, the red X's `walkOff`) are in `client/CinemaScreen`.
What it does:
1. Read the run and idle animation ids from `character.Animate` **before** cloning.
2. Set `character.Archivable = true`, `Clone()`, then restore the old value.
3. Remove scripts, sounds and force fields. Make every part non-colliding and `Massless`.
4. Anchor `HumanoidRootPart`, set `EvaluateStateMachine = false` and hide the name
   (`DisplayDistanceType = None`).
5. Parent it **before** `Animator:LoadAnimation` (it must be in the DataModel).
6. Place it with the root's height over the feet: R15 `HipHeight + root.Size.Y / 2`, R6 `root.Size.Y / 2 + 2`.

### Posing joints by hand (kicks, skill moves)
- Collect joints that are **`Motor6D` or `AnimationConstraint`** (newer avatars use the second one;
  both have `.Transform`).
- Set `joint.Transform` in **`RunService.Stepped`**, which runs after the animations, so the pose wins.
- R15 axes: `CFrame.Angles(+x, 0, 0)` on a hip swings the leg forward; a negative angle on a knee bends
  it back; `CFrame.Angles(0, 0, +z)` on `RightShoulder` lifts the right arm out (mirror it for the left).
- Write a pose as a function of a 0-to-1 share (`strikeJoints(g)`): back-swing, strike, follow-through,
  each eased with `smooth`.
- Drive the pose from the server's times, not from the local tap: the keepie-uppies raise the foot
  before each beat and flick it from the beat the server confirmed (`legLifts`), so the foot always
  meets the ball on screen.
- A leg swinging forward hardly shows from straight in front; film it three-quarters on.

### NPCs (defender, keeper)
Use `shared/Mannequin`: anchored parts with no joints. Pose them by moving the whole model
(`PivotTo`) and then each limb around its joint (`poseFigure`). The front of a mannequin is −Z.

---

## 5. Write the film as a pure function of time

This is the most important rule. **`frame(view)` must draw any moment from scratch**: never "move a
bit since last frame". Then the film can be paused, skipped, scrubbed and screenshotted.

```lua
local CUT_STRIKE, CUT_RESULT = 2, 3.6           -- where each cut starts
if t < CUT_STRIKE then filmDribble(state, t)
elseif t < CUT_RESULT then filmStrike(state, t)
else filmResult(state, t) end
```

- Each cut function places **everyone** (attacker, defender, keeper, ball) and the camera.
- Use `smooth(u)` (smoothstep) and `lerp` with `u = (t - start) / duration`, clamped.
- **Slow motion** = spend more real time on less action: the strike cut is 1.6 s of screen time for a
  half-second kick, and the ball covers only 12% of its flight per second during it.
- **Moments** worth a sound or a word are named constants (`CONTACT_AT`, `ARRIVE_AT`, `TACKLE_AT`)
  exported from the scene so the screen can use them.
- The outcome changes the film, not the timing: the ball flies to the same arrival time whether it is
  a goal, a save or a miss, and only what happens after `ARRIVE_AT` differs.
- During `over`, draw the film's last frame (`t = filmSeconds(outcome)`).

---

## 6. Camera

```lua
local function look(position, target, fov)
	camera.CFrame = CFrame.lookAt(position, target)
	camera.FieldOfView = fov
end
```

- Set `CameraType = Scriptable` **every frame** while the screen is open: the default camera scripts
  can switch it back to `Custom`. On close, restore the saved type and FOV, and set `CameraSubject`
  back to the humanoid.
- Shot types that worked well:
  - **Tracking:** fixed offset from the subject (`feet + Vector3.new(17, 3.8, -1.5)`), FOV ~50.
  - **Close-up:** 10 to 12 studs away, slightly in front and to the side, FOV ~45, a slow dolly in
    (`camera0:Lerp(target, 0.15 * g)`). Avatars are big: too close cuts off the head.
  - **Swivel:** high behind the goal (`y 12`, 15 studs back), the look target sliding from the shooter
    to the ball (`start:Lerp(ball, follow * 0.65)`). Don't follow the ball fully or the camera turns
    sideways.
- Input phases get calm cameras (behind the player); the film gets the dramatic ones.

---

## 7. Effects and sounds

- `BlurEffect` and `ColorCorrectionEffect` **parented to the camera** affect only this client. Use
  light values (blur 3 for speed, saturation −0.35 for "bullet time").
- Speed lines, letterbox bars, the reticle: a separate `ScreenGui` with `IgnoreGuiInset = true`;
  convert world points with `camera:WorldToViewportPoint`.
- Respect `GuiService.ReducedMotionEnabled`: no blur, no speed lines, no pulses.
- Sounds and words fire when the frame **crosses** a moment (`lastFilm < at and t >= at`), and reset
  when a new film starts (`stageAt` changed). **One effect per event** (a goal plays only the goal sound).

---

## 8. The screen around it

- **Open:** build the scene, save the camera, disable controls through
  `PlayerModule:GetControls():Disable()` (this also stops the thumbstick and jump), and hide the other
  screens by name (`Hud`, `Shop`, `Locker`, `Reminders`, `Daily`, `Season`, `FloorSwitcher`,
  `Objective`, `PadHint`), remembering their state.
- **Close:** the reverse, in `close()`, called whenever the server says the player is no longer there.
- **Way out:** the red X (232, 64, 96) walks the character off the spot (`Humanoid:MoveTo`) and sets
  a `dismissed` flag until the player leaves the spot, so it does not reopen at once.
- **Inputs on every device:** keys (arrows and WASD letters), gamepad (D-pad, A, R2) and on-screen
  buttons. Taps go on a full-screen `TextButton`; watch releases with `UserInputService.InputEnded`,
  because the finger can lift anywhere.
- **Show input at once:** the screen shows what the player did (`pressedMove`, `lockedX`,
  `releasedPower`) until the server's attributes arrive, then clears it on the phase change.
- **Layout:** check every element pair that can show together. Elements that must fit between others
  get a `UIScale` computed from `gui.AbsoluteSize` (the move prompt shrinks on phones).
- **Tutorial:** one short line per step until the first success ever, sitting above the buttons.

---

## 9. Testing in Studio

1. `lune run tests/run`: rules tests first (timings, judging, timeouts, grace window, NaN stamps).
2. Start Rojo (`rojo serve`), start play, fire the `quickStart` dev command, teleport onto the spot
   from the **Server** context.
3. **Scrub the film with a harness:** in the **Client** context, require the scene module, build it
   with a fake state and bind a render step that draws `stageAt + _G.fk.t`. Change `_G.fk.t` and take
   a screenshot per moment (dribble 0.5 / 1.15, strike 2.75, result 4.4 / 5.1). Fix the cameras from
   these stills.
4. Then play it once for real with keys and mouse.

**Gotchas with the Studio MCP tools:**
- `execute_luau` has its **own module cache**: changing `Config` from it does not reach the game.
  Change the file, then restart play. Scripts in a running playtest never hot-reload.
- `user_mouse_input` coordinates are **viewport pixels**; screenshots are about 1.5× larger. Click
  buttons with `instance_path` instead.
- Each tool call takes seconds, so you cannot hit a 1 s input window from a tool. Widen the window on
  disk for one test run and put it back.
- Run `stylua` on files, not folders, and `selene` before committing.

---

## 10. Checklist

- [ ] Rules module is pure, timed from `stageAt`, bounded `normalize`, tests pass
- [ ] Server judges and pays when the last input arrives; stamps clamped; remotes in RemoteSpec with rate limits
- [ ] Scene built at `ORIGIN` on the client, all positions pitch-local, destroyed on close
- [ ] Avatar clone poses `Motor6D` **and** `AnimationConstraint` joints in `Stepped`
- [ ] `frame()` draws any `t` from scratch; moments are named constants
- [ ] Camera forced to Scriptable each frame and restored on close; controls and other screens restored
- [ ] Keys, gamepad and on-screen buttons; releases watched globally
- [ ] Reduced motion respected; one sound per event
- [ ] Stills of every cut checked with the harness, then one real playthrough; console clean
