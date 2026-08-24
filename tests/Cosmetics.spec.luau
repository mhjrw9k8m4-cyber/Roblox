--!strict
--[[
	Kosmetika — odemykání se nikde neukládá, počítá se ze statistik.
	Testuje se proto hlavně to, že se počítá ze SPRÁVNÉ statistiky
	a že se nikde nedá dostat k něčemu, na co hráč nemá.
]]

return function(t)
	local Cosmetics = t.require("Cosmetics")
	local Live = t.require("Live")

	local function profile(fields: any?): any
		local base = {
			Smashes = 0,
			Rebirths = 0,
			Hatched = 0,
			Playtime = 0,
			Worlds = { glass = true },
		}
		for key, value in fields or {} do
			base[key] = value
		end
		return base
	end

	t.test("prázdný profil má jen 'none'", function()
		local fresh = profile()
		for _, kind in Cosmetics.Kinds do
			t.equal(Cosmetics.owned(fresh, kind), 1, kind)
		end
	end)

	t.test("každé id je jedinečné a 'none' je první", function()
		for _, kind in Cosmetics.Kinds do
			local seen = {}
			local list = Cosmetics.list(kind)

			t.equal(list[1].Id, "none", `{kind}: první není none`)

			for _, item in list do
				t.assert(not seen[item.Id], `{kind}: dvakrát id {item.Id}`)
				seen[item.Id] = true
			end
		end
	end)

	t.test("'none' nemá žádný vzhled, ostatní ho mají", function()
		for _, kind in Cosmetics.Kinds do
			for _, item in Cosmetics.list(kind) do
				local look = Cosmetics.look(kind, item)

				if item.Id == "none" then
					t.assert(look == nil, "none nesmí mít vzhled")
				else
					t.assert(look ~= nil, `{item.Id} nemá vzhled`)
					if kind == "skin" then
						t.assert(look.Material ~= nil, `{item.Id} nemá materiál`)
					else
						t.assert(#look.Colors >= 1, `{item.Id} nemá barvy`)
					end
				end
			end
		end
	end)

	t.test("odemyká se z té statistiky, kterou kus vyžaduje", function()
		local spark = Cosmetics.get("trail", "spark") :: any
		t.equal(spark.Req.Kind, "smashes", "spark není na průrazy")

		t.assert(not Cosmetics.unlocked(profile({ Smashes = 24 }), spark), "24 průrazů stačilo")
		t.assert(Cosmetics.unlocked(profile({ Smashes = 25 }), spark), "25 průrazů nestačilo")

		-- Jiná statistika na spark vliv mít nesmí
		t.assert(not Cosmetics.unlocked(profile({ Rebirths = 99 }), spark), "rebirthy odemkly spark")
	end)

	t.test("počet světů se bere z tabulky vlastnictví", function()
		local frost = Cosmetics.get("trail", "frost") :: any
		t.equal(frost.Req.Value, 3, "frost změnil podmínku")

		local two = profile({ Worlds = { glass = true, jelly = true } })
		local three = profile({ Worlds = { glass = true, jelly = true, ice = true } })
		-- Odemčený-ale-neaktivní svět se počítat nesmí
		local faked = profile({ Worlds = { glass = true, jelly = true, ice = false } })

		t.assert(not Cosmetics.unlocked(two, frost), "dva světy stačily")
		t.assert(Cosmetics.unlocked(three, frost), "tři světy nestačily")
		t.assert(not Cosmetics.unlocked(faked, frost), "false se počítá jako vlastněný")
	end)

	t.test("odehraný čas jde předat zvlášť", function()
		local dust = Cosmetics.get("aura", "dust") :: any
		local fresh = profile()

		t.assert(not Cosmetics.unlocked(fresh, dust), "nula hodin stačila")
		t.assert(Cosmetics.unlocked(fresh, dust, dust.Req.Value), "předaný čas se ignoroval")
	end)

	--[[
		Materiál se v datech drží jako jméno, ne jako enum, protože modul
		čte i server. Překlep by se jinak projevil až na klientovi.
	]]
	t.test("každý skin má materiál, který v Robloxu existuje", function()
		for _, item in Cosmetics.Skins do
			if item.Skin then
				t.assert(
					(Enum.Material :: any)[item.Skin.Material] ~= nil,
					`skin {item.Id}: neznámý materiál {item.Skin.Material}`
				)
				t.assert(item.Skin.Transparency < 1, `skin {item.Id} je úplně neviditelný`)
			end
		end
	end)

	t.test("druhy kosmetiky se poznají a vymyšlený neprojde", function()
		for _, kind in Cosmetics.Kinds do
			t.assert(Cosmetics.isKind(kind), `{kind} neprošel`)
			t.assert(#Cosmetics.list(kind) > 1, `{kind} má prázdný seznam`)
		end

		t.assert(not Cosmetics.isKind("hlava"), "vymyšlený druh prošel")
	end)

	t.test("neznámé id nic nevrátí", function()
		t.assert(Cosmetics.get("trail", "neexistuje") == nil, "vymyšlené id prošlo")
		t.assert(Cosmetics.get("aura", "spark") == nil, "stopa prošla jako aura")
	end)

	t.test("progress vrací kolik mám a kolik potřebuju", function()
		local void = Cosmetics.get("trail", "void") :: any
		local have, need = Cosmetics.progress(profile({ Rebirths = 2 }), void)

		t.equal(have, 2, "have")
		t.equal(need, void.Req.Value, "need")
	end)

	t.test("každý kus má popis podmínky", function()
		for _, kind in Cosmetics.Kinds do
			for _, item in Cosmetics.list(kind) do
				t.assert(Cosmetics.requirement(item) ~= "", `{item.Id} nemá popis`)
			end
		end
	end)

	t.test("podmínky rostou, takže seznam jde odshora dolů", function()
		-- Kdyby pátý kus byl levnější než druhý, hráč by odemykal
		-- v jiném pořadí, než v jakém jsou v panelu vypsané.
		for _, kind in Cosmetics.Kinds do
			local list = Cosmetics.list(kind)
			local ranks = {}

			for index, item in list do
				-- Porovnáváme jen kusy na stejné statistice
				local bucket = ranks[item.Req.Kind]
				if bucket then
					t.assert(
						item.Req.Value > bucket.Value,
						`{kind}: {item.Id} (#{index}) nemá vyšší podmínku než {bucket.Id}`
					)
				end
				ranks[item.Req.Kind] = { Id = item.Id, Value = item.Req.Value }
			end
		end
	end)

	--[[
		Podmínky na mačkání se nesmí dát splnit za pár vteřin.

		Tahle čísla sem přišla z líhnutí vajec, kterých hráč udělal za
		celou hru pár desítek. Mačkání jde pětkrát za sekundu, takže
		stejné číslo znamená odemčeno dřív, než si toho kdokoli všimne —
		a odměna, které si nikdo nevšimne, je vyhozená práce.
	]]
	t.test("odměna za mačkání není na pár vteřin", function()
		local perSecond = Live.SqueezeRate
		local minimum = perSecond * 60 * 2 -- dvě minuty nepřetržitého mačkání

		for _, kind in Cosmetics.Kinds do
			for _, item in Cosmetics.list(kind) do
				if item.Req and item.Req.Kind == "squeezes" then
					t.assert(
						item.Req.Value >= minimum,
						`{item.Name}: {item.Req.Value} zmáčknutí je pod dvě minuty mačkání`
					)
				end
			end
		end
	end)

end
