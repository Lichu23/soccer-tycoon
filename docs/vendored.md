# Vendored code

## ProfileStore

- **What:** player data saving with session locking (docs/PLAN.md, Step 6).
- **Source:** https://github.com/MadStudioRoblox/ProfileStore (MAD STUDIO, by loleris)
- **Pinned commit:** `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31)
- **License:** Apache-2.0. The license text is in `src/server/vendor/LICENSE`, next to the file.
- **Location:** `src/server/vendor/ProfileStore.luau`, copied unchanged. It is excluded from the formatter, linter and type check (see `.styluaignore`, `selene.toml`, `tools/check.sh`).
- **Updating:** do not auto-update. Read the new version's documentation first, copy the file, update the commit above, run `tools/check.sh` and a Studio playtest.
