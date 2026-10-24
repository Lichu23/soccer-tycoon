--!strict
-- Robux purchases (docs/PLAN.md, Steps 3 and 5; roblox-monetization): the cases, the match boost and
-- the direct Legend. The client only asks; the server decides whether to show the prompt, grants in
-- one step, records every receipt by its PurchaseId and confirms it to Roblox only after the save.
-- `apply` and `canOffer` are pure on the profile, so they are unit tested.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Actions = require(script.Parent.Actions)
local Analytics = require(script.Parent.Analytics)
local Config = require(ReplicatedStorage.Shared.Config)
local Grants = require(script.Parent.Grants)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local ShopRules = require(script.Parent.ShopRules)
local Sync = require(script.Parent.Sync)

local rng = Random.new()
local notified: { [string]: boolean } = {} -- receipts already shown to the player in this server
local started = false

local Purchases = {}

-- Processing ----------------------------------------------------------------------------------

local productKeyById: { [number]: string } = {}
for key, product in Config.Products do
	if product.productId > 0 then
		productKeyById[product.productId] = key
	end
end

-- What a stored purchase shows: the session total, the reveal and the new state.
local function announce(
	session: Session.Session,
	product: Config.ProductDef,
	result: { [string]: any }
)
	local runtime = session.runtime
	runtime.sessionRobux += product.robux
	if product.kind == "case" then
		runtime.sessionCases += 1
	end
	Analytics.event(session, "robux_" .. product.kind)
	-- The notice goes first: for a case it opens the roulette, which holds the reveal sent next
	-- until the strip has landed (remotes to one client arrive in order).
	Remotes.fireClient("Notice", session.player, { kind = "purchaseDone", result = result })
	local playerId = result.playerId
	if type(playerId) == "string" then
		Actions.onChange(session, "case", playerId)
	elseif product.kind == "cosmetic" then
		Actions.onChange(session, "cosmetic", result.cosmeticId) -- the plot shows the new kit
	else
		Sync.all(session)
	end
end

-- Grants and saves one purchase. Returns true once the grant is stored, so the receipt may be
-- confirmed. A retry after a failed save finds the receipt and only tries to save again.
local function grantAndStore(
	session: Session.Session,
	product: Config.ProductDef,
	purchaseId: string,
	robuxSpent: number?
): boolean
	local result = Grants.process(
		session.data,
		product,
		purchaseId,
		os.time(),
		rng:NextNumber(),
		function()
			return Session.saveAndConfirm(session.player, function(saved)
				return saved.receipts ~= nil and saved.receipts[purchaseId] ~= nil
			end)
		end,
		robuxSpent
	)
	if result == nil then
		return false
	end
	if not notified[purchaseId] then
		notified[purchaseId] = true
		announce(session, product, result)
	end
	return true
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = if player then Session.get(player) else nil
	if session == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox asks again when they are back
	end
	local key = productKeyById[info.ProductId]
	local product = if key then Config.Products[key] else nil
	if product == nil then
		warn("[Purchases] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local spent = if type(info.CurrencySpent) == "number" then info.CurrencySpent else nil
	if grantAndStore(session, product, tostring(info.PurchaseId), spent) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Whether Roblox restricts paid random items for this player (cases are then not offered).
local function randomItemsRestricted(player: Player): boolean
	local ok, policy = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok then
		return not RunService:IsStudio() -- unknown: assume restricted, except while testing
	end
	return policy.ArePaidRandomItemsRestricted == true
end

local function refuse(player: Player, reason: string)
	Remotes.fireClient("Notice", player, { kind = "purchaseRefused", reason = reason })
end

-- Asks for a purchase for this player (the shop button and the Robux pads both come here).
local function request(player: Player, key: string)
	local session = Session.get(player)
	local product = Config.Products[key]
	if session == nil or product == nil then
		return
	end
	local ok, reason = ShopRules.canOffer(session.data, key)
	if not ok then
		refuse(player, reason or "unavailable")
		return
	end
	if product.kind == "case" and randomItemsRestricted(player) then
		refuse(player, "restricted")
		return
	end
	-- Studio simulates when the product has no id yet, or when the place file is not linked to the
	-- experience (GameId 0), where a real prompt fails: both run the same grant and save path.
	local simulate = RunService:IsStudio() and (product.productId <= 0 or game.GameId == 0)
	if simulate then
		grantAndStore(session, product, "studio-" .. HttpService:GenerateGUID(false))
	elseif product.productId > 0 then
		MarketplaceService:PromptProductPurchase(player, product.productId)
	else
		refuse(player, "unavailable")
	end
end

function Purchases.request(player: Player, key: string)
	request(player, key)
end

-- Registers the receipt handler and the request remote. Call once, after Remotes.init.
function Purchases.start()
	assert(not started, "Purchases.start called twice")
	started = true
	MarketplaceService.ProcessReceipt = processReceipt
	if not RunService:IsStudio() then
		-- A product without its id is refused live, so say which ones still need creating.
		local missing = {}
		for key, product in Config.Products do
			if product.productId <= 0 then
				table.insert(missing, key)
			end
		end
		if #missing > 0 then
			table.sort(missing)
			warn("[Purchases] no Developer Product id yet for: " .. table.concat(missing, ", "))
		end
	end
	Remotes.on("RequestPurchase", function(player: Player, ...: any)
		local key = select(1, ...)
		if type(key) == "string" then
			request(player, key)
		end
	end)
	Session.onLoaded(function(session)
		-- Cases are hidden for a player Roblox restricts; the server checks again at every request.
		session.player:SetAttribute("casesRestricted", randomItemsRestricted(session.player))
	end)
end

return Purchases
