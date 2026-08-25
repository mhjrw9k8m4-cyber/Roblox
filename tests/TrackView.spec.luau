--!strict
--[[
	Trať, kterou staví klient.

	Server postaví halu, podlahu a architekturu; VŠECHNO, po čem hráč
	běhá a co sbírá — dlaždice, panely stěn, žebra stropu, bariéry
	a pickupy — staví klient. Doteď se ten modul jenom načetl a nikdy
	nepostavil, takže právě ta část hry, kterou hráč vidí nejvíc, byla
	bez jediné kontroly.

	Postaví se tady celá trať proti náhradě Roblox prostředí a měří se
	na ní to samé, co na serverové části: že se opravdu postavila, že
	sedí na podlaze a že z haly nic netrčí.
]]

return function(t)
	local TrackView = t.require("TrackView")
	local Config = t.require("Config")
	local Track = t.require("Track")
	local Economy = t.require("Economy")

	local TRACK = Config.Track

	local function profile()
		return {
			Coins = 0,
			Gems = 0,
			Power = 0,
			WorldIndex = 1,
			Barrier = 1,
			Worlds = { [Config.Worlds[1].Id] = true },
			Upgrades = {},
			Boosts = {},
			Passes = {},
			Perks = {},
			Laps = {},
			Rebirths = 0,
			Smashes = 0,
			Squishies = {},
			Held = {},
		}
	end

	--[[
		Jedna postavená trať pro všechny testy. Stavba je drahá (přes
		tisíc dílů) a všechny kontroly čtou totéž, takže stavět ji
		v každém testu znovu by běh testů jen zpomalilo.
	]]
	local view = TrackView.new()
	view:setProfile(profile())

	--[[
		Dlaždice, panely stěn a žebra stropu se nestaví při `build()`,
		ale až v první smyčce — staví se totiž jen pro úsek, ve kterém
		hráč zrovna je. Test proto musí jednu smyčku prohnat, jinak by
		měřil trať bez toho, po čem se chodí.
	]]
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Track.origin(1) + Vector3.new(0, 3, 10)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, -40)
	root.Parent = workspace

	view:update(0, 0, root)

	local function parts(): { any }
		local list = {}
		local folder = view.Folder
		if not folder then
			return list
		end
		for _, part in folder:GetDescendants() do
			if part.ClassName == "Part" and part.Position and part.Size then
				table.insert(list, part)
			end
		end
		return list
	end

	t.test("trať se opravdu postaví", function()
		t.assert(view.Folder ~= nil, "klient nepostavil vlastní složku trati")

		local built = 0
		for _ in parts() do
			built += 1
		end
		t.assert(built > 300, `klient postavil jen {built} dílů — trať je prázdná`)
	end)

	--[[
		Bariéra na každý level. Kdyby jich bylo míň, hráč by narazil na
		zeď, kterou server zná a klient nezobrazuje — tedy na nic.
	]]
	t.test("bariéra stojí u každého levelu", function()
		for index = 1, TRACK.BarrierCount do
			local barrier = view.Barriers[index]
			t.assert(barrier ~= nil, `chybí bariéra {index}`)
			t.assert(barrier.Part ~= nil, `bariéra {index} nemá díl`)

			local expected = Track.barrierPosition(1, index)
			local actual = barrier.Part.Position
			t.assert(
				math.abs(actual.Z - expected.Z) < 1,
				`bariéra {index} stojí jinde, než ji hlídá server`
			)
		end
	end)

	--[[
		Požadavek na ceduli musí sedět s tím, co pustí server. Kdyby se
		rozešly, hráč by nasbíral přesně to, co cedule chce, vrazil do
		zdi a nic by se nestalo.
	]]
	t.test("cedule slibuje totéž, co server vyžaduje", function()
		local p = profile()
		for index = 1, TRACK.BarrierCount do
			t.equal(
				view.Barriers[index].Required,
				Economy.barrierPower(p, index),
				`bariéra {index}: cedule a server se neshodnou`
			)
		end
	end)

	--[[
		Povrch, po kterém se chodí, musí sedět na `Config.floorTop()`.

		Z toho jednoho čísla se odvozuje výška nákupních desek, cedulí
		i rekvizit na serveru. Kdyby si klient dlaždice postavil o kus
		výš nebo níž, stály by desky zapuštěné v podlaze nebo by se
		vznášely — a poznalo by se to až tím, že si toho někdo všimne
		ve Studiu.
	]]
	t.test("dlaždice končí přesně na chodicí ploše", function()
		local origin = Track.origin(1)
		local expected = origin.Y + Config.floorTop()

		local checked = 0
		for _, part in parts() do
			if part.Name ~= "Dlaždice" then
				continue
			end

			checked += 1
			local top = part.Position.Y + part.Size.Y / 2
			t.assert(
				math.abs(top - expected) < 0.01,
				`dlaždice má povrch v {top}, čekáno {expected}`
			)
		end

		t.assert(checked > 100, `zkontrolovalo se jen {checked} dlaždic`)
	end)

	--[[
		Rozpočet dílů klienta. Server má svůj vlastní; tenhle je o to
		důležitější, že klientské díly se přestavují za běhu, takže se
		jejich přírůstek pozná až jako škubnutí při přechodu mezi levely.
	]]
	t.test("klient se vejde do rozpočtu dílů", function()
		local BUDGET = 700

		local built = 0
		for _ in parts() do
			built += 1
		end

		t.assert(
			built <= BUDGET,
			`klient staví {built} dílů, rozpočet je {BUDGET} — buď to prořež, `
				.. `nebo rozpočet vědomě zvedni`
		)
	end)

	--[[
		Obří hračka u trati se otřese s proraženou zdí.

		Level je ušitý podle jedné hračky a ta hračka vedle trati stojí
		jako obří rekvizita. Když se prorazí máslová zeď a obří máslo
		vedle se ani nehne, je to kulisa, která se dívá — a přesně tím
		se levné hry v žánru poznají.

		Test jde přes atributy, které nasadil server. Kdyby je přestal
		nasazovat nebo je klient přestal sbírat, spadne to tady, ne až
		ve Studiu.
	]]
	t.test("obří hračka levelu se při průrazu promáčkne", function()
		local Squish = t.require("Squish")

		local giants = view.Giants[1]
		t.assert(giants ~= nil and #giants > 0, "klient nenašel obří hračku prvního levelu")

		local piece = giants[1]
		t.assert(not Squish.isPressed(piece), "rekvizita je promáčklá ještě před průrazem")

		view:breakBarrier(1, { Coins = 10, Overkill = 1, Barrier = 1 })

		t.assert(Squish.isPressed(piece), "obří hračka se při průrazu ani nehnula")
	end)

	--[[
		Každý level má svou rekvizitu, takže se každá zeď musí mít
		s čím otřást. Kdyby některá chyběla, prošel by ten level
		potichu — a zrovna to je ta chvíle, kdy má hra vypadat draze.
	]]
	t.test("rekvizitu má každý level", function()
		for index = 1, TRACK.BarrierCount do
			local giants = view.Giants[index]
			t.assert(
				giants ~= nil and #giants > 0,
				`level {index} nemá u trati žádnou obří hračku`
			)
		end
	end)

	--[[
		Ta samá pojistka jako u serverové části: díl mimo halu je díl,
		který hráč neuvidí. U klienta to platí dvojnásob — dlaždice
		a panely se přepočítávají za běhu, takže se chyba v souřadnicích
		neprojeví hned, ale až když hráč doběhne dost daleko.
	]]
	t.test("žádný díl klienta netrčí z haly ven", function()
		local origin = Track.origin(1)
		local sideLimit = TRACK.HallWidth / 2 + 8
		local topLimit = TRACK.HallHeight + 8
		local bottomLimit = -TRACK.DeckDrop - 8

		local outside = 0
		local example = ""

		for _, part in parts() do
			local across = math.abs(part.Position.X - origin.X)
			local height = part.Position.Y - origin.Y

			if across > sideLimit or height > topLimit or height < bottomLimit then
				outside += 1
				example = `{part.Name} ({math.floor(across)} do stran, {math.floor(height)} nahoru)`
			end
		end

		t.equal(outside, 0, `{outside} dílů klienta je mimo halu (třeba {example})`)
	end)
end
