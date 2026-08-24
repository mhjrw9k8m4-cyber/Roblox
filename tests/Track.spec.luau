--!strict
--[[
	Zlaté pickupy — server i klient je určují ze stejného vzorce, aniž
	by si cokoliv posílali. Testuje se proto hlavně to, že vzorec je
	deterministický a že jich je opravdu tak málo, jak má být.
]]

return function(t)
	local Track = t.require("Track")
	local Config = t.require("Config")

	local TRACK = Config.Track

	--[[
		Nejdůležitější vlastnost: obě strany musí pro stejný vstup dojít
		ke stejné odpovědi. Kdyby se rozešly, klient by ukazoval zlatý
		pickup, který server neuzná — nebo naopak.
	]]
	t.test("odpověď závisí jen na vstupu", function()
		for index = 1, 200 do
			t.equal(
				Track.isGolden(2, 3, index),
				Track.isGolden(2, 3, index),
				`index {index} vrátil pokaždé něco jiného`
			)
		end
	end)

	t.test("vzácnost sedí na nastavení", function()
		local golden = 0
		local total = 0

		for world = 1, #Config.Worlds do
			for lap = 0, 4 do
				for index = 1, Track.PickupCount do
					total += 1
					if Track.isGolden(world, lap, index) then
						golden += 1
					end
				end
			end
		end

		local perMille = golden / total * 1000
		-- Hash není generátor náhody, takže se povoluje odchylka;
		-- jde o to, aby to nebylo o řád vedle.
		t.assert(
			perMille > TRACK.GoldenPerMille * 0.5 and perMille < TRACK.GoldenPerMille * 1.8,
			`{math.floor(perMille)} z tisíce, čekáno kolem {TRACK.GoldenPerMille}`
		)
	end)

	t.test("v každém světě a kole se nějaké najdou", function()
		for world = 1, #Config.Worlds do
			for lap = 0, 3 do
				local found = 0
				for index = 1, Track.PickupCount do
					if Track.isGolden(world, lap, index) then
						found += 1
					end
				end
				t.assert(found > 0, `svět {world}, kolo {lap}: ani jeden zlatý pickup`)
			end
		end
	end)

	--[[
		Kdyby zlaté pickupy seděly ve vzoru (třeba každý dvacátý), hráč
		by se je naučil a přestaly by být nálezem. Kontroluje se proto,
		že se rozestupy mezi nimi liší.
	]]
	t.test("nesedí v pravidelném vzoru", function()
		local positions = {}
		for index = 1, Track.PickupCount do
			if Track.isGolden(1, 0, index) then
				table.insert(positions, index)
			end
		end

		t.assert(#positions >= 3, "moc málo zlatých na to, aby šel vzor posoudit")

		local gaps = {}
		for i = 2, #positions do
			gaps[positions[i] - positions[i - 1]] = true
		end

		local distinct = 0
		for _ in gaps do
			distinct += 1
		end

		t.assert(distinct > 1, "rozestupy jsou pořád stejné — vzor jde odhadnout")
	end)

	t.test("kolo a svět mění, které pickupy jsou zlaté", function()
		local function fingerprint(world: number, lap: number): string
			local marks = {}
			for index = 1, 120 do
				table.insert(marks, if Track.isGolden(world, lap, index) then "1" else "0")
			end
			return table.concat(marks)
		end

		t.assert(fingerprint(1, 0) ~= fingerprint(1, 1), "další kolo má stejné zlaté pickupy")
		t.assert(fingerprint(1, 0) ~= fingerprint(2, 0), "jiný svět má stejné zlaté pickupy")
	end)

	t.test("hodnota se vyplatí, ale nerozbije ekonomiku", function()
		t.assert(TRACK.GoldenValue >= 5, "zlatý pickup je tak levný, že si ho nikdo nevšimne")
		t.assert(TRACK.GoldenValue <= 100, "zlatý pickup přebíjí celý zbytek sbírání")
	end)
end
