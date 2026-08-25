--!strict
--[[
	Rozlámání bariéry.

	Střepy jsou nejrychlejší cesta, jak z hry udělat prezentaci. Průraz
	sype desítky nekotvených dílů a při plném serveru se prorazí několik
	zdí ve stejnou vteřinu — bez stropu by se toho na slabším telefonu
	sešlo tolik, že by fyzika spadla na pár snímků.

	Strop v modulu byl, ale nikdo ho neměřil. Pojistka, kterou nikdo
	neměří, je jen komentář.

	Každý test po sobě uklízí. Střepy končí přímo ve `workspace`
	a jiný test tam počítá prolnuté díly — nechat je viset by znamenalo,
	že tenhle test shodí jiný, a to na pořadí, které nikdo neurčuje.
]]

return function(t)
	local Fracture = t.require("Fracture")

	local function shatter()
		Fracture.shatter({
			CFrame = CFrame.new(0, 10, 0),
			Size = Vector3.new(44, 14, 2),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
			Impact = Vector3.new(0, 8, 0),
			Momentum = Vector3.new(0, 0, -60),
			Power = 1,
		})
	end

	t.test("jedna zeď se opravdu rozláme", function()
		Fracture.clear()
		shatter()
		t.assert(Fracture.liveCount() > 0, "z proražené zdi neodletěl jediný kus")
		Fracture.clear()
	end)

	--[[
		Dvacet zdí za sebou bez jediného snímku mezi tím — nic se nestihne
		uklidit, takže se strop musí projevit. Kdyby se neprojevil, bylo by
		tam přes šest set dílů.
	]]
	t.test("dvacet průrazů za sebou nepřeleze strop", function()
		Fracture.clear()

		for _ = 1, 20 do
			shatter()
		end

		local count = Fracture.liveCount()
		Fracture.clear()

		t.assert(count > 0, "dvacet průrazů nevyrobilo ani jeden střep")
		t.assert(
			count <= Fracture.PoolLimit,
			`ve světě je {count} střepů, strop je {Fracture.PoolLimit}`
		)
	end)

	--[[
		Úklid při přestavbě trati. Střepy si samy mizí až po vlastním
		časovači, takže při přechodu do jiného světa zůstávaly viset
		u trati, kterou hráč právě opustil — nekotvené díly, které
		nikdo neuvidí a přesto se počítají do fyziky.
	]]
	t.test("úklid sebere všechny střepy", function()
		shatter()
		t.assert(Fracture.liveCount() > 0, "není co uklízet")

		Fracture.clear()
		t.equal(Fracture.liveCount(), 0, "po úklidu zůstaly střepy ve světě")

		-- A ještě jednou naprázdno: úklid bez střepů nesmí spadnout
		Fracture.clear()
		t.equal(Fracture.liveCount(), 0, "druhý úklid počet rozhodil")
	end)
end
