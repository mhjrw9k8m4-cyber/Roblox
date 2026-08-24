--!strict
--[[
	Mačkání s pomalým návratem.

	Modul sám sahá na Roblox API, takže se tady testuje jeho **křivka** —
	to jediné, na čem celý pocit stojí. Squishy hračka se nevrací lineárně
	ani odpružením: chvíli zůstane dole a teprve pak se zvedne.
]]

return function(t)
	-- Stejná mocnina jako v Squish.luau
	local function remaining(progress: number): number
		return 1 - progress ^ 2.2
	end

	t.test("na začátku je promáčknutí plné, na konci žádné", function()
		t.equal(remaining(0), 1, "start")
		t.equal(remaining(1), 0, "konec")
	end)

	t.test("návrat je jednosměrný — důlek se nikdy neprohloubí sám", function()
		local previous = remaining(0)
		for step = 1, 40 do
			local value = remaining(step / 40)
			t.assert(value <= previous + 1e-9, `v {step / 40} se důlek prohloubil`)
			previous = value
		end
	end)

	--[[
		Tohle je ten "slow rise". V polovině času musí být důlek pořád
		z větší části dole; lineární návrat by v půlce byl na 50 %
		a vypadal by jako výtah.
	]]
	t.test("v polovině času je důlek pořád z větší části dole", function()
		local half = remaining(0.5)
		t.assert(half > 0.6, `v půlce zbývá jen {half}, to je moc rychlý návrat`)
		t.assert(half < 0.95, `v půlce zbývá {half}, to se skoro nehne`)
	end)

	t.test("většina návratu se odehraje v poslední třetině", function()
		local atTwoThirds = remaining(2 / 3)
		t.assert(
			atTwoThirds > 0.35,
			`ve dvou třetinách zbývá {atTwoThirds} — návrat je rozprostřený, ne pomalý`
		)
	end)

	t.test("křivka nikdy nevyjede mimo rozsah", function()
		for step = 0, 50 do
			local value = remaining(step / 50)
			t.assert(value >= 0 and value <= 1, `v {step / 50} je hodnota {value} mimo 0..1`)
		end
	end)

	--[[
		Zóny mají mít měkkost sladěnou se zvukem: co zní jako stlačení,
		se musí i promáčknout. Jinak by hráč slyšel jedno a viděl druhé.
	]]
	t.test("nejměkčí zóna se opravdu mačká nejvíc", function()
		local Zones = t.require("Zones")
		local Assets = t.require("Assets")

		local softest = Zones.List[1]
		t.assert(softest.Squish > 0.5, "první zóna se skoro nemačká")

		local bends = 0
		for _, layer in Assets.terrain(softest.Sound, "Step") do
			if layer.Bend then
				bends += 1
			end
		end
		t.assert(bends > 0, "nejměkčí zóna nemá ohyb výšky — bude vidět, ale ne slyšet")
	end)
end
