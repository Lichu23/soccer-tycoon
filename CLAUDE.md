# soccer-tycoon (Roblox, Rojo)

## Setup
- Scripts live in `src/` and sync to Studio with Rojo (`rojo serve`, then Connect in Studio).
  `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts, `src/shared` → ReplicatedStorage.
- Rojo is at `C:\Users\lisan\.rojo\bin\rojo.exe`. Map and parts are edited through the Studio MCP and saved in `Place3.rbxl`.

## Skills (load before the matching work)
- Planning / balancing / economy → `roblox-game-design`
- Writing or reviewing Luau → `luau-best-practices` (+ `luau-type-expert` for types)
- Code layout, client/server boundaries → `roblox-architecture`
- Anything touching remotes, cash, purchases → `roblox-security`
- Saving player progress → `roblox-data`
- Building the map → `roblox-building`; lighting → `roblox-lighting`; menus/HUD → `roblox-gui`
- Working through Studio (playtests, screenshots) → `roblox-studio-mcp`
- Rojo problems → `rojo-pro`
- Before publishing → `roblox-publish-checklist`; later → `roblox-monetization`, `roblox-growth-design`

## Rules
- The server owns all game state. Clients never decide cash, purchases or progress.
- Scripts in `src/` are the source of truth. Don't paste scripts into Studio only.
