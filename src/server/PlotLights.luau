--!strict
-- Ceiling lights for the four floors of a plot, so the pad labels and the players can be read
-- inside the building. Built in code when the plot is placed (the template has none), so they are
-- part of the source and are removed with the plot. Positions are in the template's own space.

local PlotLights = {}

-- The underside of each floor's ceiling in the template (the next slab, or the roof for floor 4).
local CEILING_Y = { 15.2, 31.2, 47.2, 63.2 }
-- The light fixtures as {x, z}: a grid of three by three over the middle of the main slab, then a few
-- more towards the side walls and the front part of the building, where the grid did not reach (the
-- capsules and the pads along those walls were dark). The same spots on every floor.
local SPOTS: { { number } } = {
	{ 56, 50 },
	{ 90, 50 },
	{ 124, 50 },
	{ 56, 77 },
	{ 90, 77 },
	{ 124, 77 },
	{ 56, 104 },
	{ 90, 104 },
	{ 124, 104 },
	-- Towards the wall at z 22.
	{ 60, 30 },
	{ 90, 30 },
	{ 120, 30 },
	-- Towards the end of the main slab (z 132) and the front part that ends at z 158.
	{ 60, 126 },
	{ 90, 126 },
	{ 120, 126 },
	{ 66, 146 },
	{ 96, 146 },
}
local WARM = Color3.fromRGB(255, 244, 225)

-- Adds the lights to `plot`. `templatePivot` is the pivot the template had before it was moved, so a
-- template position becomes the matching position on the placed plot.
function PlotLights.build(plot: Model, templatePivot: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Lights"
	local plotPivot = plot:GetPivot()
	for _, y in CEILING_Y do
		for _, spot in SPOTS do
			local x, z = spot[1], spot[2]
			local fixture = Instance.new("Part")
			fixture.Name = "Light"
			fixture.Size = Vector3.new(12, 0.4, 1.5)
			fixture.Material = Enum.Material.Neon
			fixture.Color = WARM
			fixture.Anchored = true
			fixture.CanCollide = false
			fixture.CanQuery = false
			fixture.CanTouch = false
			fixture.CastShadow = false
			fixture.CFrame = plotPivot * templatePivot:ToObjectSpace(CFrame.new(x, y, z))

			local light = Instance.new("PointLight")
			light.Color = WARM
			light.Range = 36
			light.Brightness = 0.22
			light.Shadows = false
			light.Parent = fixture
			fixture.Parent = folder
		end
	end
	folder.Parent = plot
end

return PlotLights
