--!strict
--[[
	Rekvizity světů.

	Modul je jen data, takže se testuje to, co se v datech snadno pokazí
	a ve hře se pozná až po postavení: neznámý tvar nebo materiál, díl
	zapuštěný do trati, nebo svět, na který se zapomnělo.
]]

return function(t)
	local Props = t.require("Props")
	local Config = t.require("Config")

	local TRACK = Config.Track

	t.test("každý svět má rekvizity", function()
		for _, world in Config.Worlds do
			local props = Props.forWorld(world.Id)
			t.assert(#props > 0, `svět {world.Id} nemá ani jednu rekvizitu — bude to holá chodba`)
		end
	end)

	t.test("neznámý svět nespadne, jen nic nevrátí", function()
		t.equal(#Props.forWorld("vymysleny"), 0, "vymyšlený svět něco vrátil")
	end)

	t.test("každý tvar a materiál v Robloxu existuje", function()
		local shapes = { Block = true, Ball = true, Cylinder = true, Wedge = true }

		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				for index, piece in prop.Pieces do
					t.assert(shapes[piece.Shape], `{world.Id}/{prop.Id}[{index}]: neznámý tvar {piece.Shape}`)
					t.assert(
						(Enum.Material :: any)[piece.Material] ~= nil,
						`{world.Id}/{prop.Id}[{index}]: neznámý materiál {piece.Material}`
					)
				end
			end
		end
	end)

	t.test("barvy se uvádějí rolí, ne hexem", function()
		local roles = { World = true, Accent = true, Dark = true, Light = true }

		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				for index, piece in prop.Pieces do
					t.assert(roles[piece.Color], `{world.Id}/{prop.Id}[{index}]: neznámá role barvy {piece.Color}`)
				end
			end
		end
	end)

	--[[
		Nejzrádnější vada: rekvizita v cestě.

		Nestačí ale hlídat vzdálenost od osy. Rekvizita smí v chodbě
		být — pokud visí dost vysoko, aby pod ní hráč prošel. Právě
		takové jsou kapky ze stropu a potrubí nad tratí, a bez téhle
		výjimky by šly zahodit dvě z nejhezčích věcí ve světě.

		Počítá se proto **skutečná spodní hrana** ze všech dílů, ne
		jen poloha rekvizity.
	]]
	local HEADROOM = 12

	--[[
		Svislý dosah otočeného kvádru.

		První verze brala prostě nejdelší stranu — a shodila potrubí nad
		tratí, které je sedmdesát studů dlouhé, ale VODOROVNĚ. Sedmdesát
		se tedy nesmí započítat do výšky.

		Počítá se proto řádek rotační matice, který mapuje lokální osy na
		světové Y. Rotace je `CFrame.Angles(x, y, z)`, tedy Rx·Ry·Rz;
		jeho Y řádek vyjde takhle:

		    ( sx·sy·cz + cx·sz ,  cx·cz − sx·sy·sz ,  −sx·cy )

		Svislá půlka je pak součet absolutních hodnot těch tří členů
		vynásobených půlkami rozměrů.
	]]
	local function verticalHalf(size: Vector3, rotation: Vector3?): number
		local r = rotation or Vector3.zero
		local rx, ry, rz = math.rad(r.X), math.rad(r.Y), math.rad(r.Z)

		local sx, cx = math.sin(rx), math.cos(rx)
		local sy, cy = math.sin(ry), math.cos(ry)
		local sz, cz = math.sin(rz), math.cos(rz)

		local toX = sx * sy * cz + cx * sz
		local toY = cx * cz - sx * sy * sz
		local toZ = -sx * cy

		return math.abs(toX) * size.X / 2
			+ math.abs(toY) * size.Y / 2
			+ math.abs(toZ) * size.Z / 2
	end

	local function lowestPoint(prop): number
		local lowest = math.huge

		for _, piece in prop.Pieces do
			lowest = math.min(lowest, piece.Offset.Y - verticalHalf(piece.Size, piece.Rotation))
		end

		return prop.Height + lowest
	end

	t.test("nic nestojí hráči v cestě", function()
		local half = TRACK.Width / 2

		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				local outside = prop.Side ~= "center" and prop.Distance > half
				if outside then
					continue
				end

				local lowest = lowestPoint(prop)
				t.assert(
					lowest >= HEADROOM,
					`{world.Id}/{prop.Id}: zasahuje do chodby a spodní hrana je ve výšce `
						.. `{string.format("%.1f", lowest)}, potřeba aspoň {HEADROOM}`
				)
			end
		end
	end)

	t.test("strany se určují správně", function()
		local both = Props.sides({ Side = "both" } :: any)
		t.equal(#both, 2, "oboustranná rekvizita nestojí na dvou stranách")

		t.equal(Props.sides({ Side = "left" } :: any)[1], -1, "levá")
		t.equal(Props.sides({ Side = "right" } :: any)[1], 1, "pravá")
		t.equal(Props.sides({ Side = "center" } :: any)[1], 0, "středová")
	end)

	t.test("rozestupy dávají smysl", function()
		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				t.assert(
					prop.Every >= 1 and prop.Every == math.floor(prop.Every),
					`{world.Id}/{prop.Id}: rozestup {prop.Every} není celé kladné číslo`
				)
				t.assert(
					prop.Every <= TRACK.BarrierCount,
					`{world.Id}/{prop.Id}: rozestup {prop.Every} je delší než celá trať`
				)
				t.assert(#prop.Pieces > 0, `{world.Id}/{prop.Id}: rekvizita bez dílů`)
			end
		end
	end)

	--[[
		Rekvizity se staví pro každý svět a stojí paměť i vykreslování.
		Když jich někdo přidá příliš, pozná se to až na slabém telefonu.
	]]
	t.test("počet dílů na svět zůstává rozumný", function()
		for _, world in Config.Worlds do
			local total = 0

			for _, prop in Props.forWorld(world.Id) do
				local spots = 0
				for segment = 0, TRACK.BarrierCount do
					if segment % prop.Every == 0 then
						spots += #Props.sides(prop)
					end
				end
				total += spots * #prop.Pieces
			end

			t.assert(total > 20, `svět {world.Id} má jen {total} dílů rekvizit — bude vypadat prázdně`)
			t.assert(total < 900, `svět {world.Id} má {total} dílů rekvizit — moc na slabé zařízení`)
		end
	end)

	t.test("vznášející se rekvizity mají kladnou rychlost", function()
		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				if prop.Float then
					t.assert(prop.Float > 0, `{world.Id}/{prop.Id}: nulová rychlost vznášení`)
					t.assert(prop.Float < 3, `{world.Id}/{prop.Id}: vznášení {prop.Float} je tak rychlé, že to bude vibrovat`)
				end
			end
		end
	end)

	--[[
		Poznatelné cukrovinky.

		Zbytek rekvizit jsou tvary — krystal, střep, monolit. Fungují
		jako výplň, ale svět, ve kterém stojí jen ony, vypadá jako
		kulisa. Každý svět proto musí mít aspoň dvě věci, které člověk
		pozná bez vysvětlení.
	]]
	t.test("každý svět má poznatelné cukrovinky", function()
		local CANDY = {
			["Cukrová hůl"] = true,
			["Sušenka"] = true,
			["Jahoda"] = true,
			["Koktejl"] = true,
			["Kornout"] = true,
		}

		for _, world in Config.Worlds do
			local found = 0
			for _, prop in Props.forWorld(world.Id) do
				if CANDY[prop.Id] then
					found += 1
				end
			end

			t.assert(found >= 2, `{world.Name} má jen {found} poznatelných rekvizit`)
		end
	end)

	--[[
		Rekvizity musí stát v hale, ne za její stěnou. Je to ta samá
		past, do které spadly obří hračky i plovoucí kry — jen se
		nejdřív musela postavit hala, aby bylo co překročit.
	]]
	t.test("rekvizity stojí uvnitř haly", function()
		local half = Config.Track.HallWidth / 2

		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				if prop.Side == "center" then
					continue
				end

				t.assert(
					prop.Distance < half - 6,
					`{world.Name}/{prop.Id}: stojí {prop.Distance} od osy, stěna haly je na {half}`
				)
			end
		end
	end)

	--[[
		Silueta se pozná podle počtu kusů. Cukrovinka ze dvou dílů je
		zase jen tvar; hůl potřebuje hák, koktejl brčko a třešničku.
	]]
	t.test("cukrovinky mají dost kusů na siluetu", function()
		local CANDY = {
			["Cukrová hůl"] = true,
			["Sušenka"] = true,
			["Jahoda"] = true,
			["Koktejl"] = true,
			["Kornout"] = true,
		}

		for _, world in Config.Worlds do
			for _, prop in Props.forWorld(world.Id) do
				if CANDY[prop.Id] then
					t.assert(
						#prop.Pieces >= 5,
						`{prop.Id} má jen {#prop.Pieces} kusů — silueta se ztratí`
					)
				end
			end
		end
	end)

end
