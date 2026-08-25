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
	Kind: string, -- "free" | "smashes" | "rebirths" | "worlds" | "squeezes" | "playtime"
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

export type SkinLook = {
	Body: Color3,
	Limbs: Color3,
	Material: string, -- jméno z Enum.Material, ne samotný enum (sdílený modul)
	Reflectance: number,
	Transparency: number,
	Glow: number?, -- jas obrysu; nil = bez obrysu
}

export type Item = {
	Id: string,
	Name: string,
	Rarity: string,
	Req: Requirement,
	Trail: TrailLook?,
	Aura: AuraLook?,
	Skin: SkinLook?,
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
		Req = { Kind = "squeezes", Value = 1000 },
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
		--[[
			Stopa za dosažení Nebula Drift. Nové světy musí dávat i něco,
			co je vidět — samotné vyšší číslo v peněžence nikomu nepoznají
			ostatní hráči a právě to je na kosmetice cenné.
		]]
		Id = "stardust",
		Name = "Stardust",
		Rarity = "Epic",
		Req = { Kind = "worlds", Value = 7 },
		Trail = {
			Colors = {
				rgb(186, 130, 255),
				rgb(255, 120, 220),
				rgb(96, 226, 255),
			},
			Width = 1.9,
			Lifetime = 2.4,
			Light = 0.85,
			Alpha = 0.12,
			Cycle = 1.6,
		},
	},
	{
		--[[
			Solar Forge. Úzká, krátká a jasná — po měkkém prachu
			mlhoviny musí být na první pohled znát, že je to něco
			jiného, ne jen jiná barva téhož.
		]]
		Id = "ember",
		Name = "Ember Trail",
		Rarity = "Epic",
		Req = { Kind = "worlds", Value = 8 },
		Trail = {
			Colors = {
				rgb(255, 210, 96),
				rgb(255, 96, 40),
				rgb(178, 32, 12),
			},
			Width = 1.2,
			Lifetime = 1,
			Light = 1,
			Alpha = 0.02,
			Cycle = 0.35,
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
		Req = { Kind = "squeezes", Value = 2400 },
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
		--[[
			Quantum Bloom. Málo částic, ale rychle obíhají po těsném
			kruhu — má to vypadat jako přístroj, ne jako kouzlo.
		]]
		Id = "orbit",
		Name = "Orbit",
		Rarity = "Epic",
		Req = { Kind = "worlds", Value = 9 },
		Aura = {
			Colors = {
				rgb(140, 255, 226),
				rgb(60, 226, 255),
			},
			Rate = 26,
			Size = { 0.22, 0.6 },
			Speed = { 0.2, 0.6 },
			Spread = 20,
			Rise = 0.4,
			Drag = 4,
			Spin = 220,
			Orbit = 1,
			Radius = 2.2,
			Glow = 2.4,
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

-- Skiny ----------------------------------------------------------------------
--[[
	Skin přebarví a přemateriálí postavu. Žádné modely ani balíčky —
	jen `BodyColors`, `Material`, odrazivost a průhlednost na částech,
	které tam už jsou. Funguje to na R6 i R15 a nepotřebuje to práva
	k žádnému nahranému assetu.

	Materiál se drží jako jméno, ne jako `Enum.Material`: tenhle modul
	čte i server, kde by konkrétní enum nikomu k ničemu nebyl, a klient
	si ho přeloží až při nasazení.
]]
Cosmetics.Skins = {
	{
		Id = "none",
		Name = "Default",
		Rarity = "Common",
		Req = { Kind = "free", Value = 0 },
	},
	{
		Id = "glass",
		Name = "Glass",
		Rarity = "Common",
		Req = { Kind = "smashes", Value = 100 },
		Skin = {
			Body = rgb(180, 232, 255),
			Limbs = rgb(140, 210, 250),
			Material = "Glass",
			Reflectance = 0.35,
			Transparency = 0.25,
		},
	},
	{
		Id = "jelly",
		Name = "Jelly",
		Rarity = "Common",
		Req = { Kind = "worlds", Value = 2 },
		Skin = {
			Body = rgb(255, 106, 178),
			Limbs = rgb(255, 158, 214),
			Material = "Glass",
			Reflectance = 0.1,
			Transparency = 0.15,
			Glow = 0.4,
		},
	},
	{
		Id = "chrome",
		Name = "Chrome",
		Rarity = "Rare",
		Req = { Kind = "smashes", Value = 5000 },
		Skin = {
			Body = rgb(226, 232, 240),
			Limbs = rgb(170, 180, 196),
			Material = "Metal",
			Reflectance = 0.9,
			Transparency = 0,
		},
	},
	{
		Id = "cocoa",
		Name = "Cocoa",
		Rarity = "Rare",
		Req = { Kind = "squeezes", Value = 1600 },
		Skin = {
			Body = rgb(112, 62, 32),
			Limbs = rgb(168, 104, 58),
			Material = "Slate",
			Reflectance = 0.05,
			Transparency = 0,
		},
	},
	{
		Id = "neon",
		Name = "Neon",
		Rarity = "Epic",
		Req = { Kind = "rebirths", Value = 2 },
		Skin = {
			Body = rgb(168, 255, 88),
			Limbs = rgb(96, 226, 255),
			Material = "Neon",
			Reflectance = 0,
			Transparency = 0,
			Glow = 1,
		},
	},
	{
		Id = "obsidian",
		Name = "Obsidian",
		Rarity = "Epic",
		Req = { Kind = "playtime", Value = 36000 },
		Skin = {
			Body = rgb(24, 20, 38),
			Limbs = rgb(44, 34, 66),
			Material = "Glass",
			Reflectance = 0.6,
			Transparency = 0,
			Glow = 0.5,
		},
	},
	{
		Id = "void",
		Name = "Void",
		Rarity = "Legendary",
		Req = { Kind = "rebirths", Value = 8 },
		Skin = {
			-- Skoro průhledné tělo se svítícím obrysem: postava vypadá
			-- jako díra v prostoru, ne jako obarvená figurka.
			Body = rgb(12, 8, 24),
			Limbs = rgb(150, 86, 255),
			Material = "ForceField",
			Reflectance = 0,
			Transparency = 0.45,
			Glow = 1.6,
		},
	},
	{
		--[[
			Infinity Garden, poslední svět. Skin je z celé kosmetiky ten
			nejvíc vidět — nese ho celá postava — takže patří na konec
			řady, ne doprostřed.
		]]
		Id = "bloom",
		Name = "Bloom",
		Rarity = "Legendary",
		Req = { Kind = "worlds", Value = 10 },
		Skin = {
			Body = rgb(255, 246, 214),
			Limbs = rgb(255, 210, 96),
			Material = "Marble",
			Reflectance = 0.2,
			Transparency = 0,
			Glow = 1.2,
		},
	},
	{
		Id = "gold",
		Name = "Solid Gold",
		Rarity = "Mythic",
		Req = { Kind = "rebirths", Value = 30 },
		Skin = {
			Body = rgb(255, 196, 60),
			Limbs = rgb(212, 148, 30),
			Material = "Metal",
			Reflectance = 1,
			Transparency = 0,
			Glow = 0.8,
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
	elseif kind == "squeezes" then
		return profile.Squeezes or 0, item.Req.Value
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
	elseif kind == "squeezes" then
		return `{value} squeezes`
	elseif kind == "playtime" then
		return `{math.floor(value / 3600)}h played`
	end

	return ""
end

-- Seznam podle druhu: "trail", "aura" nebo "skin".
function Cosmetics.list(kind: string): { Item }
	if kind == "aura" then
		return Cosmetics.Auras
	elseif kind == "skin" then
		return Cosmetics.Skins
	end
	return Cosmetics.Trails
end

-- Druhy v pořadí, v jakém je ukazuje panel. Server podle toho ověřuje,
-- že klient neposlal vymyšlený druh.
--[[
	Barvy vzácností. Dřív se braly z tabulky u petů — jenže ta patřila
	petům, ne kosmetice, a odešla s nimi. Vzácnost kusu je vlastnost
	kosmetiky, takže její barva patří sem.
]]
Cosmetics.Rarities = {
	Common = Color3.fromRGB(186, 196, 214),
	Rare = Color3.fromRGB(96, 226, 255),
	Epic = Color3.fromRGB(150, 86, 255),
	Legendary = Color3.fromRGB(255, 196, 60),
	Mythic = Color3.fromRGB(255, 86, 178),
}

function Cosmetics.rarityColor(name: string): Color3
	return Cosmetics.Rarities[name] or Cosmetics.Rarities.Common
end

Cosmetics.Kinds = { "trail", "aura", "skin" }

function Cosmetics.isKind(kind: string): boolean
	return table.find(Cosmetics.Kinds, kind) ~= nil
end

-- Vzhled daného kusu, ať je to kterýkoliv druh.
function Cosmetics.look(kind: string, item: Item): any
	if kind == "aura" then
		return item.Aura
	elseif kind == "skin" then
		return item.Skin
	end
	return item.Trail
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
