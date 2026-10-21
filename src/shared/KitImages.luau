--!strict
-- The uploaded images of the player figures (shared/Mannequin): a classic Shirt and Pants template per
-- team of shared/Kits, the plain kit that a colour tints, and the face decals. Drawn by tools/kits/make
-- (run it after changing a kit, upload the PNGs and paste the new ids here). A missing id leaves that
-- piece off: the figure still shows, in plain colours.

local KitImages = {}

KitImages.shirts = {
	alIttihad = "rbxassetid://77592249374895",
	alNassr = "rbxassetid://88924620538883",
	argentina = "rbxassetid://84229468714013",
	arsenal = "rbxassetid://103768286958909",
	atletico = "rbxassetid://110457907270327",
	barcelona = "rbxassetid://103031284240498",
	bayern = "rbxassetid://85159673131556",
	brazil = "rbxassetid://81496767952946",
	chelsea = "rbxassetid://72186250025994",
	everton = "rbxassetid://110909082524019",
	france = "rbxassetid://71686434785337",
	inter = "rbxassetid://101458095500373",
	interMiami = "rbxassetid://132219019595882",
	lafc = "rbxassetid://73283458638130",
	liverpool = "rbxassetid://136680690777326",
	manCity = "rbxassetid://105944797777906",
	milan = "rbxassetid://92719881521471",
	napoli = "rbxassetid://104238523676315",
	realMadrid = "rbxassetid://121399505614572",
	santos = "rbxassetid://111044895623637",
} :: { [string]: string }

KitImages.pants = {
	alIttihad = "rbxassetid://110450372436335",
	alNassr = "rbxassetid://127955204771662",
	argentina = "rbxassetid://85655062643542",
	arsenal = "rbxassetid://90545623734753",
	atletico = "rbxassetid://107035624767865",
	barcelona = "rbxassetid://115210570151027",
	bayern = "rbxassetid://99941477778905",
	brazil = "rbxassetid://108433241242375",
	chelsea = "rbxassetid://88251760601038",
	everton = "rbxassetid://136979298057891",
	france = "rbxassetid://138712379173335",
	inter = "rbxassetid://77530986295065",
	interMiami = "rbxassetid://98089911356669",
	lafc = "rbxassetid://107187950590123",
	liverpool = "rbxassetid://73935681521421",
	manCity = "rbxassetid://111859026928370",
	milan = "rbxassetid://83779334785815",
	napoli = "rbxassetid://121224404020429",
	realMadrid = "rbxassetid://88563436707316",
	santos = "rbxassetid://72231967625630",
} :: { [string]: string }

-- The plain kit: a white shirt that the given colour tints, and dark shorts with white socks.
KitImages.plainShirt = "rbxassetid://127385825376988"
KitImages.plainPants = "rbxassetid://119415380815260"

-- The eyes and mouth (Look.face) and the brows (Look.brows, tinted with the hair colour).
KitImages.faces = {
	smile = "rbxassetid://80874693846924",
	grin = "rbxassetid://85422304773234",
	focus = "rbxassetid://112981797351052",
	smirk = "rbxassetid://130355139035609",
} :: { [string]: string }

-- A buzz cut painted on the head (tinted with the hair colour): the top, the sides and back, the front.
KitImages.buzz = {
	top = "rbxassetid://125631609272068",
	side = "rbxassetid://128569145891097",
	front = "rbxassetid://117862765187151",
}

KitImages.brows = {
	flat = "rbxassetid://90485149805243",
	raised = "rbxassetid://109887108321110",
} :: { [string]: string }

return KitImages
