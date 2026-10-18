--!strict
-- Shapes shared by the server and the client. Shared code only sees this subset of a profile;
-- the server's full Profile (ProfileSchema) is structurally compatible with it.

export type OwnedPlayer = { level: number, stars: number }

export type StoreLevels = {
	cashPerMatch: number,
	matchSpeed: number,
	hatTrick: number,
	offline: number,
}

-- What the progress rules (roster, store, stadium, goals) need to know.
export type ProgressData = {
	cash: number,
	tp: number, -- training points
	stadiumTier: number,
	storeLevels: StoreLevels,
	fieldStarted: boolean,
	players: { [string]: OwnedPlayer },
}

return {}
