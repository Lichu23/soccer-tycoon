--!strict
-- The bench press of the Training Gym: its invisible seat (a Seat tagged "BenchSeat" in the bench
-- model, placed where the root lies) lays the plot's owner on their back along the bench, head
-- under the barbell. Anyone else is
-- put straight back on their feet. Getting up is the Seat's own jump. Lying on the bench is standing
-- on the training pad, so TrainingActions pays the TP; client/BenchPress animates the press.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TAG = "BenchSeat"
local LIE_HEIGHT = 0.6 -- studs from the top of the seat to the middle of the root (the back on the pad)

-- The root's turn on the seat: its front faces up, its head points to the seat's -Z.
local LYING = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1))

local BenchSeats = {}

-- The plot's owner, from the OwnerUserId attribute of the plot the seat is in.
local function ownerOf(seat: Instance): number?
	local node: Instance? = seat
	while node do
		local id = node:GetAttribute("OwnerUserId")
		if type(id) == "number" then
			return id
		end
		node = node.Parent
	end
	return nil
end

local function watch(seat: Instance)
	if not seat:IsA("Seat") then
		return
	end
	local function lieDown(weld: Instance)
		if weld.Name ~= "SeatWeld" or not weld:IsA("Weld") then
			return
		end
		local humanoid = seat.Occupant
		local player = if humanoid then Players:GetPlayerFromCharacter(humanoid.Parent) else nil
		if humanoid == nil or player == nil or player.UserId ~= ownerOf(seat) then
			-- Not this plot's bench: back on their feet.
			weld:Destroy()
			if humanoid then
				humanoid.Sit = false
			end
			return
		end
		weld.C0 = CFrame.new(0, seat.Size.Y / 2 + LIE_HEIGHT, 0) * LYING
		weld.C1 = CFrame.identity
	end
	seat.ChildAdded:Connect(lieDown)
	for _, child in seat:GetChildren() do
		lieDown(child)
	end
end

function BenchSeats.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
	for _, seat in CollectionService:GetTagged(TAG) do
		watch(seat)
	end
end

return BenchSeats
