--!strict
--[[
	Cosmetics — stopy a aury, které se odemykají hraním.

	Dvě rozhodnutí, na kterých tenhle modul stojí:

	  1. Odemčení se NIKDE neukládá. Počítá se pokaždé znovu ze statistik,
	     které profil stejně vede (průrazy, rebirthy, světy, vylíhlá vejce,
	     odehraný čas). Není tak co duplikovat, co ztratit při rollbacku
	     ani co podvrhnout — hráč "vlastní" přesně to, co si odehrál.
	     V profilu leží jen dvě id: co má nasazené.

	  2. Vzhled je popsaný čísly, ne assety. Žádné `rbxassetid://`, které
	     by v cizí hře nemuselo projít právy — rozdíl mezi stopami dělá
	     barevný přechod, šířka, doba dohasínání a svit. Aury jsou pak
	     jen jinak nastavené emitory.

	Klient si podle `Look` postaví Trail / ParticleEmitter, server řeší
	pouze to, jestli na daný kus hráč vůbec dosáhl.
]]

local Cosmetics = {}

export type Requirement = {
	Kind: string, -- "free" | "smashes" | "rebirths" | "worlds" | "hatched" | "playtime"
	Value: number,
}

export type TrailLook = {
	Colors: { Color3 },
	Width: number, -- půlka výšky pásu ve studech
	Lifetime: number,
	Light: number, -- LightEmission 0..1
	Alpha: number, -- průhlednost na začátku pásu
	Cycle: number?, -- když je vyplněné, barvy po pásu putují (sekundy na obrátku)
}

export type AuraLook = {
	Colors: { Color3 },
	Rate: number,
	Size: { number }, -- {od, do}
	Speed: { number },
	Spread: number,
	Rise: number, -- svislé zrychlení: kladné stoupá, záporné padá
	Drag: number,
	Spin: number, -- otáčení částic za sekundu
	Orbit: number?, -- když je vyplněné, emitor krouží kolem hráče (otáčky/s)
	Radius: number, -- vzdálenost emitoru od těla
	Glow: number?, -- jas PointLightu, nil = žádné světlo
}

export type Item = {
	Id: string,
	Name: string,
	Rarity: string,
	Req: Requirement,
	Trail: TrailLook?,
	Aura: AuraLook?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Stopy ----------------------------------------------------------------------

Cosmetics.Trails = {
	{
		Id = "none",
		Name = "No Trail",
		Rarity = "Common",
		Req = { Kind = "free", Value = 0 },
	},
	{
		Id = "spark",
		Name = "Spark",
		Rarity = "Common",
		Req = { Kind = "smashes", Value = 25 },
		Trail = {
			Colors = { rgb(255, 236, 168), rgb(255, 196, 60) },
			Width = 1.1,
			Lifetime = 0.45,
			Light = 0.9,
			Alpha = 0.3,
		},
	},
	{
		Id = "bubble",
		Name = "Bubblegum",
		Rarity = "Common",
		Req = { Kind = "smashes", Value = 250 },
		Trail = {
			Colors = { rgb(255, 158, 214), rgb(255, 86, 178), rgb(150, 86, 255) },
			Width = 1.5,
			Lifetime = 0.7,
			Light = 0.4,
			Alpha = 0.25,
		},
	},
	{
		Id = "frost",
		Name = "Frostline",
		Rarity = "Rare",
		Req = { Kind = "worlds", Value = 3 },
		Trail = {
			Colors = { rgb(226, 250, 255), rgb(96, 226, 255), rgb(90, 150, 255) },
			Width = 1.2,
			Lifetime = 0.9,
			Light = 1,
			Alpha = 0.4,
		},
	},
	{
		Id = "cocoa",
		Name = "Molten Cocoa",
		Rarity = "Rare",
		Req = { Kind = "hatched", Value = 25 },
		Trail = {
			Colors = { rgb(255, 208, 140), rgb(140, 78, 40), rgb(70, 36, 18) },
			Width = 1.8,
			Lifetime = 1.1,
			Light = 0.15,
			Alpha = 0.1,
		},
	},
	{
		Id = "neon",
		Name = "Neon Cut",
		Rarity = "Epic",
		-- Průrazů přibývá rychle (~3 000/h), takže tenhle stupeň musí být
		-- řádově výš než předchozí — jinak by celá řada padla v první hodině.
		Req = { Kind = "smashes", Value = 25000 },
		Trail = {
			Colors = { rgb(168, 255, 88), rgb(96, 226, 255) },
			Width = 0.8,
			Lifetime = 1.4,
			Light = 1,
			Alpha = 0.15,
			Cycle = 1.2,
		},
	},
	{
		Id = "plasma",
		Name = "Plasma",
		Rarity = "Epic",
		Req = { Kind = "rebirths", Value = 1 },
		Trail = {
			Colors = { rgb(255, 255, 255), rgb(150, 86, 255), rgb(60, 20, 120) },
			Width = 2.1,
			Lifetime = 0.8,
			Light = 1,
			Alpha = 0.2,
			Cycle = 0.6,
		},
	},
	{
		Id = "void",
		Name = "Voidsplit",
		Rarity = "Legendary",
		Req = { Kind = "rebirths", Value = 6 },
		Trail = {
			Colors = { rgb(18, 13, 38), rgb(150, 86, 255), rgb(18, 13, 38) },
			Width = 2.6,
			Lifetime = 1.6,
			Light = 0.6,
			Alpha = 0,
			Cycle = 2.4,
		},
	},
	{
		Id = "prism",
		Name = "Prism",
		Rarity = "Mythic",
		Req = { Kind = "rebirths", Value = 25 },
		Trail = {
			Colors = {
				rgb(255, 86, 178),
				rgb(255, 196, 60),
				rgb(168, 255, 88),
				rgb(96, 226, 255),
				rgb(150, 86, 255),
			},
			Width = 2.2,
			Lifetime = 1.8,
			Light = 1,
			Alpha = 0.05,
			Cycle = 0.9,
		},
	},
} :: { Item }

-- Aury -----------------------------------------------------------------------

Cosmetics.Auras = {
	{
		Id = "none",
		Name = "No Aura",
		Rarity = "Common",
		Req = { Kind = "free", Value = 0 },
	},
	{
		Id = "dust",
		Name = "Dust Motes",
		Rarity = "Common",
		Req = { Kind = "playtime", Value = 1800 },
		Aura = {
			Colors = { rgb(255, 236, 168) },
			Rate = 9,
			Size = { 0.12, 0.3 },
			Speed = { 0.4, 1.2 },
			Spread = 180,
			Rise = 1.4,
			Drag = 2,
			Spin = 30,
			Radius = 2.4,
		},
	},
	{
		Id = "embers",
		Name = "Embers",
		Rarity = "Common",
		Req = { Kind = "smashes", Value = 500 },
		Aura = {
			Colors = { rgb(255, 208, 120), rgb(255, 120, 40) },
			Rate = 22,
			Size = { 0.15, 0.5 },
			Speed = { 1, 3 },
			Spread = 40,
			Rise = 6,
			Drag = 1,
			Spin = 90,
			Radius = 1.6,
			Glow = 1.2,
		},
	},
	{
		Id = "flurry",
		Name = "Flurry",
		Rarity = "Rare",
		Req = { Kind = "worlds", Value = 4 },
		Aura = {
			Colors = { rgb(255, 255, 255), rgb(180, 232, 255) },
			Rate = 28,
			Size = { 0.18, 0.42 },
			Speed = { 0.5, 1.5 },
			Spread = 180,
			Rise = -3.5,
			Drag = 3,
			Spin = 140,
			Radius = 3.2,
		},
	},
	{
		Id = "fizz",
		Name = "Fizz",
		Rarity = "Rare",
		Req = { Kind = "hatched", Value = 60 },
		Aura = {
			Colors = { rgb(255, 158, 214), rgb(96, 226, 255) },
			Rate = 34,
			Size = { 0.2, 0.7 },
			Speed = { 1.5, 3.5 },
			Spread = 25,
			Rise = 9,
			Drag = 4,
			Spin = 20,
			Orbit = 0.5,
			Radius = 2.2,
		},
	},
	{
		Id = "halo",
		Name = "Halo",
		Rarity = "Epic",
		Req = { Kind = "playtime", Value = 14400 },
		Aura = {
			Colors = { rgb(255, 224, 120), rgb(255, 196, 60) },
			Rate = 46,
			Size = { 0.1, 0.34 },
			Speed = { 0.1, 0.4 },
			Spread = 6,
			Rise = 0,
			Drag = 6,
			Spin = 0,
			Orbit = 1.1,
			Radius = 3,
			Glow = 1.6,
		},
	},
	{
		Id = "storm",
		Name = "Storm",
		Rarity = "Epic",
		Req = { Kind = "rebirths", Value = 3 },
		Aura = {
			Colors = { rgb(255, 255, 255), rgb(120, 190, 255), rgb(60, 90, 255) },
			Rate = 52,
			Size = { 0.08, 0.9 },
			Speed = { 4, 11 },
			Spread = 60,
			Rise = -2,
			Drag = 0.5,
			Spin = 240,
			Orbit = 2.2,
			Radius = 2.8,
			Glow = 2.2,
		},
	},
	{
		Id = "singularity",
		Name = "Singularity",
		Rarity = "Legendary",
		Req = { Kind = "rebirths", Value = 12 },
		Aura = {
			-- Záporná rychlost = částice se sbíhají dovnitř místo ven.
			Colors = { rgb(150, 86, 255), rgb(18, 13, 38) },
			Rate = 60,
			Size = { 0.5, 0.05 },
			Speed = { -7, -3 },
			Spread = 180,
			Rise = 0,
			Drag = 1.5,
			Spin = 300,
			Orbit = 3,
			Radius = 5,
			Glow = 2.6,
		},
	},
	{
		Id = "aurora",
		Name = "Aurora",
		Rarity = "Mythic",
		Req = { Kind = "rebirths", Value = 40 },
		Aura = {
			Colors = {
				rgb(168, 255, 88),
				rgb(96, 226, 255),
				rgb(150, 86, 255),
				rgb(255, 86, 178),
			},
			Rate = 70,
			Size = { 0.3, 1.4 },
			Speed = { 0.5, 2 },
			Spread = 180,
			Rise = 3.5,
			Drag = 2.5,
			Spin = 60,
			Orbit = 0.35,
			Radius = 3.6,
			Glow = 3,
		},
	},
} :: { Item }

-- Odemykání ------------------------------------------------------------------

local function countWorlds(profile: any): number
	local total = 0
	for _, owned in profile.Worlds or {} do
		if owned then
			total += 1
		end
	end
	return total
end

--[[
	Kolik hráč má z toho, co daný kus vyžaduje. `playtime` se předává
	zvlášť: v profilu je jen čas z minulých sezení, ten aktuální drží
	DataService.
]]
function Cosmetics.progress(profile: any, item: Item, playtime: number?): (number, number)
	local kind = item.Req.Kind

	if kind == "free" then
		return 1, 1
	elseif kind == "smashes" then
		return profile.Smashes or 0, item.Req.Value
	elseif kind == "rebirths" then
		return profile.Rebirths or 0, item.Req.Value
	elseif kind == "worlds" then
		return countWorlds(profile), item.Req.Value
	elseif kind == "hatched" then
		return profile.Hatched or 0, item.Req.Value
	elseif kind == "playtime" then
		return playtime or profile.Playtime or 0, item.Req.Value
	end

	return 0, item.Req.Value
end

function Cosmetics.unlocked(profile: any, item: Item, playtime: number?): boolean
	local have, need = Cosmetics.progress(profile, item, playtime)
	return have >= need
end

-- Krátký popis podmínky do panelu.
function Cosmetics.requirement(item: Item): string
	local kind = item.Req.Kind
	local value = item.Req.Value

	if kind == "free" then
		return "Always yours"
	elseif kind == "smashes" then
		return `{value} walls smashed`
	elseif kind == "rebirths" then
		return `{value} rebirth{if value == 1 then "" else "s"}`
	elseif kind == "worlds" then
		return `{value} worlds unlocked`
	elseif kind == "hatched" then
		return `{value} eggs hatched`
	elseif kind == "playtime" then
		return `{math.floor(value / 3600)}h played`
	end

	return ""
end

-- Seznam podle druhu; "trail" nebo "aura".
function Cosmetics.list(kind: string): { Item }
	return if kind == "aura" then Cosmetics.Auras else Cosmetics.Trails
end

function Cosmetics.get(kind: string, id: string): Item?
	for _, item in Cosmetics.list(kind) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

--[[
	Kolik kusů má hráč odemčených — do podtitulku panelu a do HUD.
]]
function Cosmetics.owned(profile: any, kind: string, playtime: number?): number
	local total = 0
	for _, item in Cosmetics.list(kind) do
		if Cosmetics.unlocked(profile, item, playtime) then
			total += 1
		end
	end
	return total
end

return Cosmetics
