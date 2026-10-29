--!strict
-- The equipment of each gym tier (the Gym upgrade, Config.Store.gymRate). The plot template holds it
-- in Gym.GymTiers (built by tools/studio/BuildGymTiers.luau): one model a level, with a GymLevel
-- attribute. A model shows once the owner's Gym upgrade reaches its level; until then it waits in
-- ServerStorage, so it is never streamed. Derived from the saved level, never stored itself.

local ServerStorage = game:GetService("ServerStorage")

local GymTiers = {}

local stashes: { [Model]: Folder } = {} -- a plot's hidden equipment

local function stashFor(plot: Model): Folder
	local stash = stashes[plot]
	if stash == nil then
		local made = Instance.new("Folder")
		made.Name = "GymTiers_" .. plot.Name
		made.Parent = ServerStorage
		stash = made
		stashes[plot] = made
		plot.Destroying:Connect(function()
			stashes[plot] = nil
			made:Destroy()
		end)
	end
	return stash :: Folder
end

-- Shows the equipment of every gym tier up to `level` (the Gym upgrade level) on `plot`.
function GymTiers.update(plot: Model, level: number)
	local gym = plot:FindFirstChild("Gym")
	local shown = gym and gym:FindFirstChild("GymTiers")
	if shown == nil then
		return
	end
	local stash = stashFor(plot)
	local models: { Instance } = shown:GetChildren()
	for _, model in stash:GetChildren() do
		table.insert(models, model)
	end
	for _, model in models do
		local needed = model:GetAttribute("GymLevel")
		if type(needed) == "number" then
			local parent = if level >= needed then shown else stash
			if model.Parent ~= parent then
				model.Parent = parent
			end
		end
	end
end

return GymTiers
