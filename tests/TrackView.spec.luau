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
	--[[
		Tahle sada potřebuje běžící služby, takže si server nastartuje
		sama. Spoléhat na jinou sadu znamená testy, které procházejí jen
		v jednom pořadí souborů.
	]]
	t.boot()

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
		Stěna se propadá VEN z chodby, ne dovnitř.

		Kdyby se osa spletla, panely by se hráči vydouvaly do cesty
		místo aby mu uhýbaly — a protože nemají kolizi, poznalo by se
		to jen tím, že chodba vypadá, jako by se svírala.

		Osa se drží v tabulce, ne v atributu dílu: atribut se četl
		v každém snímku pro každý ze šedesáti panelů, tedy šedesát
		cest přes hranici do enginu za snímek za číslo, které se od
		postavení dílu nezmění. Test proto sahá na tu tabulku.
	]]
	t.test("panely stěny se propadají ven z chodby", function()
		local origin = Track.origin(1)
		local checked = 0

		for index, panel in view.Panels do
			local axis = view.PanelAxis[index]
			t.assert(axis ~= nil, `panel {index} nemá osu propadu`)

			local side = panel.Position.X - origin.X
			checked += 1
			t.assert(
				(side < 0 and axis.X < 0) or (side > 0 and axis.X > 0),
				`panel na straně {side} se propadá do {axis.X} — tedy dovnitř chodby`
			)
		end

		t.assert(checked > 20, `zkontrolovalo se jen {checked} panelů`)
	end)

	--[[
		Na kostce svítí to, co za ni hráč opravdu dostane.

		Do teď tam bylo "+1" napořád — i když hráč po vylepšeních bral
		padesát tisíc. Přitom je to jediné místo, kde je vidět, co
		obchod udělal: hráč koupí Power a musí se každá kostka na trati
		změnit. Bez toho je vylepšení jen číslo, které se někde schovalo.
	]]
	t.test("hodnota na kostce roste s vylepšeními", function()
		local Format = t.require("Format")

		local before = view.Pickups[1].Label.Text
		t.assert(string.find(before, "+1", 1, true) ~= nil, `nováček nevidí +1, ale {before}`)

		local rich = profile()
		rich.PickupValue = 4200
		view:setProfile(rich)

		local after = view.Pickups[1].Label.Text
		t.assert(
			string.find(after, Format.short(4200), 1, true) ~= nil,
			`po vylepšení je na kostce pořád {after}`
		)

		--[[
			Zlatá kostka dává násobek, takže musí ukazovat víc než
			obyčejná. Kdyby ukazovala to samé, není na ní co objevovat.
		]]
		local golden
		for _, pickup in view.Pickups do
			if pickup.Golden then
				golden = pickup
				break
			end
		end
		t.assert(golden ~= nil, "na trati není ani jedna zlatá kostka")
		t.assert(
			golden.Label.Text ~= after,
			"zlatá kostka slibuje totéž co obyčejná"
		)

		-- Zpátky na výchozí stav, ať na tom nestojí pořadí testů
		view:setProfile(profile())
	end)

	--[[
		Na zdi je vidět, kolik za ni hráč dostane.

		Dřív tam svítil holý násobek přeplácnutí s dovětkem "COINS" —
		"27.1 COINS" ve chvíli, kdy hráči přibyly přes dva miliony.
		Číslo, které se tváří jako částka a částka není, je horší než
		žádné: hráč z něj usoudí, že se přebírat Power nevyplatí,
		protože to podle cedule nese pár mincí.
	]]
	t.test("zeď ukazuje mince, ne holý násobek", function()
		local Format = t.require("Format")

		local rich = profile()
		local required = Economy.barrierPower(rich, 1)
		rich.Power = required * 8
		view:setProfile(rich)
		view:setPower(rich.Power)

		local text = view.Barriers[1].Label.Text
		local reward = Economy.smashReward(rich, 1, os.time(), rich.Power)

		t.assert(reward > 0, "za zeď se nedávají žádné mince")
		t.assert(
			string.find(text, Format.short(reward), 1, true) ~= nil,
			`na zdi svítí "{text}", ale odměna je {Format.short(reward)}`
		)

		--[[
			Násobek smí zůstat, ale musí být poznat, že je to násobek.
			Bez křížku ho oko přečte jako počet mincí.
		]]
		local bonus = Economy.overkill(rich.Power, required, rich)
		t.assert(bonus > 1.5, "přeplácnutí je moc malé, test by neměřil, co tvrdí")
		t.assert(
			string.find(text, Format.multiplier(bonus), 1, true) ~= nil,
			`na zdi chybí násobek {Format.multiplier(bonus)}: "{text}"`
		)

		-- Zpátky na nováčka, ať na tom nestojí pořadí testů
		view:setProfile(profile())
	end)

	--[[
		Rekvizita, která dorazí až za běhu, se taky musí chytit.

		Se zapnutým streamingem dorazí vzdálenější polovina trati
		k hráči až ve chvíli, kdy k ní dojde. Dokud si klient rekvizity
		sbíral jedním průchodem stromu při stavbě světa, našel jen ty,
		které byly zrovna načtené — tedy sotva první třetinu trati.
		Zbytek se při průrazu nehnul a poznat to šlo jedině okem.

		Test proto přidá rekvizitu AŽ POTOM, co je svět postavený,
		což je přesně to pořadí, ve kterém to streaming dělá.
	]]
	t.test("rekvizita, která dorazí později, se chytí taky", function()
		local CollectionService = t.stub().service("CollectionService")
		local Config = t.require("Config")

		local before = #(view.Giants[3] or {})

		local late = Instance.new("Part")
		late.Name = "Obří pozdní 1"
		late.Position = Track.origin(1) + Vector3.new(40, 6, 200)
		late:SetAttribute("Giant", 3)
		late:SetAttribute("Squish", 0.9)
		late:SetAttribute("WorldId", Config.Worlds[1].Id)
		late.Parent = workspace

		CollectionService:AddTag(late, "GiantToy")

		t.equal(#(view.Giants[3] or {}), before + 1, "pozdě příchozí rekvizitu klient nezaznamenal")

		--[[
			A když se zase uvolní (hráč odešel z dosahu), musí ze
			seznamu zmizet. Jinak by se mačkaly díly, které už ve
			světě nejsou.
		]]
		CollectionService:RemoveTag(late, "GiantToy")
		t.equal(#(view.Giants[3] or {}), before, "uvolněná rekvizita zůstala v seznamu")

		late:Destroy()
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
