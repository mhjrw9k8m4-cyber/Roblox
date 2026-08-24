--!strict
--[[
	Procedurální hudba — data, ze kterých se skládá.

	Nota se přehrává jako `PENTATONIC[stupeň]`. Stupeň mimo rozsah by
	tedy indexoval nil a spadl by až za běhu, u hráče — a jen občas,
	až by se smyčka dostala k tomu jednomu špatnému kroku ve vzoru.
]]

return function(t)
	local Assets = t.require("Assets")
	local Config = t.require("Config")

	-- Musí sedět s PENTATONIC v SoundKit
	local DEGREES = 6

	t.test("vzory nejsou prázdné a jsou stejně dlouhé", function()
		local music = Assets.Music

		t.assert(#music.Pattern > 0, "melodie je prázdná")
		t.equal(#music.BassPattern, #music.Pattern, "spodek a melodie mají jinou délku")
	end)

	t.test("každý stupeň ve vzoru existuje v pentatonice", function()
		for _, name in { "Pattern", "BassPattern" } do
			for index, degree in Assets.Music[name] do
				t.assert(
					degree == math.floor(degree),
					`{name}[{index}] = {degree} není celé číslo`
				)
				t.assert(
					degree >= 0 and degree <= DEGREES,
					`{name}[{index}] = {degree} je mimo pentatoniku (0..{DEGREES})`
				)
			end
		end
	end)

	--[[
		Pomlky jsou důležitější než noty: bez nich je z toho drnčení.
		Zároveň nesmí být samá pomlka, to už by nebyla hudba.
	]]
	t.test("melodie dýchá — má noty i pomlky", function()
		local notes, rests = 0, 0
		for _, degree in Assets.Music.Pattern do
			if degree == 0 then
				rests += 1
			else
				notes += 1
			end
		end

		t.assert(notes >= 4, `jen {notes} not — málo`)
		t.assert(rests >= 4, `jen {rests} pomlk — z toho bude drnčení`)
	end)

	t.test("spodek je řidší než melodie", function()
		local function count(pattern): number
			local total = 0
			for _, degree in pattern do
				if degree > 0 then
					total += 1
				end
			end
			return total
		end

		t.assert(
			count(Assets.Music.BassPattern) < count(Assets.Music.Pattern),
			"spodek hraje stejně hustě jako melodie — poperou se"
		)
	end)

	t.test("obě vrstvy mají zvuk a rozumnou hlasitost", function()
		for _, name in { "Bass", "Melody" } do
			local layer = Assets.Music[name]
			t.assert(layer.Id ~= nil and layer.Id ~= "", `{name} nemá zvuk`)
			t.assert(layer.Volume > 0 and layer.Volume < 0.5, `{name}: hlasitost mimo rozsah`)
			t.assert(layer.Pitch > 0, `{name}: nulová výška`)
		end
	end)

	t.test("každý svět má tempo a je v rozumném rozsahu", function()
		for _, world in Config.Worlds do
			local tempo = Assets.tempo(world.Id)
			t.assert(tempo > 0.1, `{world.Id}: tempo {tempo} je tak rychlé, že to bude drnčet`)
			t.assert(tempo < 1, `{world.Id}: tempo {tempo} je tak pomalé, že to nedrží rytmus`)
		end
	end)

	t.test("neznámý svět dostane výchozí tempo, ne nil", function()
		t.assert(Assets.tempo("neexistuje") > 0, "vrátilo se nic")
	end)
end
