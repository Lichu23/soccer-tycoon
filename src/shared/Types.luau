--!strict
-- Shapes shared by the server and the client. Shared code only sees this subset of a profile;
-- the server's full Profile (ProfileSchema) is structurally compatible with it.

export type OwnedPlayer = { level: number, stars: number }

export type StoreLevels = {
	matchSpeed: number,
	hatTrick: number,
	gymRate: number,
}

-- What the progress rules (roster, store, stadium, goals) need to know.
export type ProgressData = {
	cash: number,
	tp: number, -- training points
	stadiumTier: number,
	storeLevels: StoreLevels,
	fieldStarted: boolean,
	players: { [string]: OwnedPlayer },
	-- Legend Trial goals reached so far, by Legend and goal id. Never unset (a New Season keeps them).
	trials: { [string]: { [string]: boolean } }?,
	-- Owned premium styles and the chosen style of each slot (see Cosmetics).
	cosmetics: { owned: { [string]: boolean }, chosen: { [string]: string } },
}

return {}
