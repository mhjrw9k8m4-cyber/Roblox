--!strict
--[[
	Kosmetika — odemykání se nikde neukládá, počítá se ze statistik.
	Testuje se proto hlavně to, že se počítá ze SPRÁVNÉ statistiky
	a že se nikde nedá dostat k něčemu, na co hráč nemá.
]]

return function(t)
	local Cosmetics = t.require("Cosmetics")

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
		t.equal(Cosmetics.owned(fresh, "trail"), 1, "stopy")
		t.equal(Cosmetics.owned(fresh, "aura"), 1, "aury")
	end)

	t.test("každé id je jedinečné a 'none' je první", function()
		for _, kind in { "trail", "aura" } do
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
		for _, kind in { "trail", "aura" } do
			for _, item in Cosmetics.list(kind) do
				local look = if kind == "aura" then item.Aura else item.Trail

				if item.Id == "none" then
					t.assert(look == nil, "none nesmí mít vzhled")
				else
					t.assert(look ~= nil, `{item.Id} nemá vzhled`)
					t.assert(#look.Colors >= 1, `{item.Id} nemá barvy`)
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
		for _, kind in { "trail", "aura" } do
			for _, item in Cosmetics.list(kind) do
				t.assert(Cosmetics.requirement(item) ~= "", `{item.Id} nemá popis`)
			end
		end
	end)

	t.test("podmínky rostou, takže seznam jde odshora dolů", function()
		-- Kdyby pátý kus byl levnější než druhý, hráč by odemykal
		-- v jiném pořadí, než v jakém jsou v panelu vypsané.
		for _, kind in { "trail", "aura" } do
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
end
