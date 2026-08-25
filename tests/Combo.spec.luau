--!strict
--[[
	Combo — čistá logika řetězu. Server podle ní počítá odměnu, klient
	podle ní kreslí HUD, takže se musí chovat stejně v obou.
]]

return function(t)
	local Combo = t.require("Combo")

	t.test("nový řetěz je prázdný", function()
		local state = Combo.new()
		t.equal(Combo.value(state, 100), 0, "chain")
		t.equal(Combo.multiplier(0), 1, "násobič")
	end)

	t.test("článek se přidá a drží", function()
		local state = Combo.new()

		t.equal(Combo.step(state, 1, 100), 1, "první článek")
		t.equal(Combo.step(state, 1, 101), 2, "druhý článek")
		t.equal(Combo.value(state, 102), 2, "těsně v okně")
	end)

	t.test("po vypršení okna padá na nulu", function()
		local state = Combo.new()
		Combo.step(state, 10, 100)

		t.equal(Combo.value(state, 100 + Combo.Window - 0.01), 10, "těsně před")
		t.equal(Combo.value(state, 100 + Combo.Window + 0.01), 0, "těsně po")
	end)

	--[[
		Nejzrádnější případ: hráč se vrátí po prodlevě. Nesmí navázat
		tam, kde skončil — jinak by stačilo sbírat jeden pickup za dvě
		vteřiny a řetěz by rostl donekonečna.
	]]
	t.test("po prodlevě se začíná od jedné, ne od starého čísla", function()
		local state = Combo.new()
		Combo.step(state, 50, 100)

		t.equal(Combo.step(state, 1, 200), 1, "navázal na starý řetěz")
	end)

	t.test("řetěz nepřeroste strop", function()
		local state = Combo.new()
		t.equal(Combo.step(state, 10000, 100), Combo.Max, "strop se nedodržel")
		t.equal(Combo.step(state, 1, 100.1), Combo.Max, "strop se dá přeskočit dalším článkem")
	end)

	t.test("násobič roste lineárně a má strop", function()
		t.equal(Combo.multiplier(0), 1, "nula")
		t.equal(Combo.multiplier(Combo.Max), Combo.maxMultiplier(), "strop")
		t.assert(Combo.multiplier(Combo.Max + 500) == Combo.maxMultiplier(), "nad stropem roste dál")
		t.assert(Combo.multiplier(50) > Combo.multiplier(49), "neroste")
	end)

	t.test("strop násobiče je přesně dvojnásobek", function()
		-- Číslo se musí dát říct hráči jednou větou. Když se změní,
		-- musí se změnit i text v README a v HUD.
		t.equal(Combo.maxMultiplier(), 2, "×2 na stropu")
	end)

	t.test("reset vynuluje řetěz i čas", function()
		local state = Combo.new()
		Combo.step(state, 40, 100)
		Combo.reset(state)

		t.equal(Combo.value(state, 100), 0, "chain")
		t.equal(Combo.step(state, 1, 100), 1, "po resetu se nenavazuje")
	end)

	t.test("zbývající čas ubývá a nejde pod nulu", function()
		local state = Combo.new()
		Combo.step(state, 1, 100)

		t.equal(Combo.remaining(state, 100), Combo.Window, "hned po článku")
		t.assert(Combo.remaining(state, 100 + Combo.Window / 2) < Combo.Window, "neubývá")
		t.equal(Combo.remaining(state, 500), 0, "po vypršení")
	end)

	t.test("stupně jsou seřazené a začínají na nule", function()
		t.equal(Combo.Tiers[1].At, 0, "první stupeň není od nuly")

		for index = 2, #Combo.Tiers do
			t.assert(
				Combo.Tiers[index].At > Combo.Tiers[index - 1].At,
				`stupeň {index} nemá vyšší práh`
			)
		end

		-- Poslední stupeň musí jít dosáhnout, jinak je v seznamu zbytečně
		t.assert(Combo.Tiers[#Combo.Tiers].At <= Combo.Max, "poslední stupeň je nad stropem")
	end)

	t.test("stupeň sedí na řetěz", function()
		t.equal(Combo.tierIndex(0), 1, "nula")
		t.equal(Combo.tier(0).Name, "", "nultý stupeň má jméno")
		t.equal(Combo.tierIndex(Combo.Max), #Combo.Tiers, "strop nedá poslední stupeň")

		-- Práh je včetně: přesně na hodnotě už stupeň platí
		local second = Combo.Tiers[2]
		t.equal(Combo.tierIndex(second.At), 2, "práh se nezapočítal")
		t.equal(Combo.tierIndex(second.At - 1), 1, "práh se započítal moc brzo")
	end)

	t.test("nil stav se chová jako prázdný", function()
		-- Server čte řetěz i pro hráče, který ještě nic nesebral
		t.equal(Combo.value(nil, 100), 0, "value")
		t.equal(Combo.remaining(nil, 100), 0, "remaining")
	end)

	--[[
		Mačkání hračky drží řetěz naživu, ale nestaví ho.

		Kdyby článek přidávalo, byla by nejlepší strategie stát na místě
		a mačkat — jenže řetěz je odměna za sbírání v pohybu a to musí
		zůstat. Testuje se proto obojí: že se čas obnoví a že se počet
		nezmění.
	]]
	t.test("držení obnoví čas, ale nepřidá článek", function()
		local state = Combo.new()
		Combo.step(state, 5, 0)

		local late = Combo.Window - 0.1
		t.equal(Combo.hold(state, late), 5, "držení změnilo počet článků")

		-- Po obnovení musí řetěz přežít další skoro celé okno
		t.equal(Combo.value(state, late + Combo.Window - 0.1), 5, "řetěz spadl, i když ho drželo mačkání")
	end)

	t.test("držení neoživí spadlý řetěz", function()
		local state = Combo.new()
		Combo.step(state, 7, 0)

		local dead = Combo.Window + 1
		t.equal(Combo.hold(state, dead), 0, "mačkání oživilo řetěz, který už spadl")
		t.equal(Combo.value(state, dead), 0, "spadlý řetěz se po držení vrátil")
	end)

	t.test("držení nezaloží řetěz z ničeho", function()
		local state = Combo.new()
		t.equal(Combo.hold(state, 0), 0, "mačkání založilo combo bez jediného pickupu")
		t.equal(Combo.value(state, 0), 0, "prázdný řetěz se po držení naplnil")
	end)

end
