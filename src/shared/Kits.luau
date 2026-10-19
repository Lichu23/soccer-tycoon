--!strict
-- The colours of each player's shirt and shorts: the colours of the team he plays for, nothing else (no
-- crest, logo, sponsor or exact kit design). Written as plain {r, g, b} numbers, so it is unit tested.
-- The teams are the ones known in mid 2026; players move, so change the `teamOf` line of a player here
-- when he does. The retired Legends wear their national team's colours. The shirt keeps the player's
-- surname and number on the back and the number on the chest; the pattern is only how the second colour
-- is used (stripes at the sides, a band at the hem, or none).

export type Kit = {
	shirt: { number },
	trim: { number }, -- the second colour of the shirt (stripes or hem)
	shorts: { number },
	socks: { number },
	pattern: string, -- "stripes", "hem" or "plain"
}

local function kit(
	shirt: { number },
	trim: { number },
	shorts: { number },
	socks: { number },
	pattern: string
): Kit
	return { shirt = shirt, trim = trim, shorts = shorts, socks = socks, pattern = pattern }
end

local WHITE = { 248, 248, 248 }
local BLACK = { 22, 22, 26 }

-- The teams (colours only).
local TEAMS: { [string]: Kit } = {
	barcelona = kit({ 165, 25, 75 }, { 0, 80, 155 }, { 20, 45, 115 }, { 20, 45, 115 }, "stripes"),
	realMadrid = kit(WHITE, WHITE, WHITE, WHITE, "plain"),
	manCity = kit({ 108, 171, 221 }, { 108, 171, 221 }, WHITE, { 108, 171, 221 }, "plain"),
	liverpool = kit({ 200, 16, 46 }, { 200, 16, 46 }, { 200, 16, 46 }, { 200, 16, 46 }, "plain"),
	bayern = kit({ 220, 0, 30 }, { 220, 0, 30 }, WHITE, { 220, 0, 30 }, "plain"),
	arsenal = kit({ 220, 20, 30 }, WHITE, WHITE, { 220, 20, 30 }, "plain"),
	atletico = kit({ 210, 30, 45 }, WHITE, { 20, 45, 115 }, { 20, 45, 115 }, "stripes"),
	inter = kit(BLACK, { 0, 75, 155 }, BLACK, BLACK, "stripes"),
	milan = kit({ 220, 20, 35 }, BLACK, BLACK, { 220, 20, 35 }, "stripes"),
	alNassr = kit({ 255, 205, 0 }, { 255, 205, 0 }, { 0, 70, 150 }, { 255, 205, 0 }, "plain"),
	alIttihad = kit({ 255, 215, 0 }, BLACK, BLACK, { 255, 215, 0 }, "stripes"),
	napoli = kit({ 0, 140, 220 }, { 0, 140, 220 }, WHITE, { 0, 140, 220 }, "plain"),
	lafc = kit(BLACK, { 200, 170, 90 }, BLACK, BLACK, "hem"),
	interMiami = kit({ 245, 150, 180 }, { 245, 150, 180 }, BLACK, { 245, 150, 180 }, "plain"),
	santos = kit(WHITE, BLACK, WHITE, WHITE, "hem"),
	everton = kit({ 0, 60, 160 }, { 0, 60, 160 }, WHITE, { 0, 60, 160 }, "plain"),
	chelsea = kit({ 5, 70, 160 }, { 5, 70, 160 }, { 5, 70, 160 }, WHITE, "plain"),
	-- National teams, for the retired Legends.
	brazil = kit({ 255, 222, 0 }, { 0, 150, 60 }, { 0, 70, 160 }, WHITE, "hem"),
	argentina = kit({ 116, 172, 223 }, WHITE, BLACK, WHITE, "stripes"),
	france = kit({ 20, 50, 120 }, { 20, 50, 120 }, WHITE, { 200, 30, 45 }, "plain"),
}

local teamOf: { [string]: string } = {
	rashford = "barcelona",
	grealish = "everton",
	sterling = "chelsea",
	joao_felix = "alNassr",
	son = "lafc",
	saka = "arsenal",
	griezmann = "atletico",
	pedri = "barcelona",
	trent = "realMadrid",
	gavi = "barcelona",
	lautaro = "inter",
	leao = "milan",
	wirtz = "liverpool",
	musiala = "bayern",
	lewandowski = "barcelona",
	benzema = "alIttihad",
	modric = "milan",
	kane = "bayern",
	de_bruyne = "napoli",
	rodri = "manCity",
	foden = "manCity",
	vinicius = "realMadrid",
	bellingham = "realMadrid",
	yamal = "barcelona",
	salah = "liverpool",
	neymar = "santos",
	haaland = "manCity",
	mbappe = "realMadrid",
	cristiano = "alNassr",
	messi = "interMiami",
	ronaldinho = "brazil",
	zidane = "france",
	ronaldo_nazario = "brazil",
	maradona = "argentina",
	pele = "brazil",
}

local Kits = {}

Kits.teamOf = teamOf

-- The kit of a player, or nil when he has none (the figure then falls back to the rarity colour).
function Kits.of(playerId: string): Kit?
	local team = teamOf[playerId]
	return if team then TEAMS[team] else nil
end

return Kits
