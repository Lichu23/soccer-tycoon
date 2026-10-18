--!strict
-- The rules for loading a player's profile (docs/PLAN.md, Step 6), kept pure so they are tested.

local LoadPolicy = {}

-- Stop retrying when the player left or the retry time ran out. The lock held by another server
-- is never stolen: after the timeout the player is kicked and can rejoin.
function LoadPolicy.shouldCancel(
	elapsedSeconds: number,
	timeoutSeconds: number,
	playerInGame: boolean
): boolean
	return not playerInGame or elapsedSeconds > timeoutSeconds
end

-- What happens when no profile could be loaded. A player is never let in on a blank profile,
-- because a new save could overwrite the real one.
function LoadPolicy.outcome(loaded: boolean, playerInGame: boolean): string
	if loaded then
		return "play"
	end
	return if playerInGame then "kick" else "ignore"
end

return LoadPolicy
