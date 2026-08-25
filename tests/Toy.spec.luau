--!strict
--[[
	Recepty hraček.

	Hračka je poskládaná z několika kusů a recept je čistá data, takže
	se dá kontrolovat bez Robloxu. Kontroluje se hlavně to, co by ve
	Studiu vypadalo jako chyba vykreslení: kus mimo hračku, nulový
	rozměr, neznámý tvar nebo role.
]]

return function(t)
	local Toy = t.require("Toy")
	local Live = t.require("Live")

	local function known(list: { string }, value: string): boolean
		return table.find(list, value) ~= nil
	end

	t.test("každá hračka z Live se dá postavit", function()
		for _, squishy in Live.Squishies do
			local pieces = Toy.pieces(squishy)
			t.assert(#pieces > 0, `{squishy.Name} nemá jediný kus`)
		end
	end)

	t.test("kusy mají známý tvar, roli a nenulový rozměr", function()
		for _, squishy in Live.Squishies do
			for index, piece in Toy.pieces(squishy) do
				local where = `{squishy.Name} #{index}`

				t.assert(known(Toy.Kinds, piece.Kind), `{where}: neznámý tvar {piece.Kind}`)
				t.assert(known(Toy.Roles, piece.Role), `{where}: neznámá role {piece.Role}`)

				t.assert(piece.Size.X > 0, `{where}: nulová šířka`)
				t.assert(piece.Size.Y > 0, `{where}: nulová výška`)
				t.assert(piece.Size.Z > 0, `{where}: nulová hloubka`)
			end
		end
	end)

	--[[
		Kus, který kouká mimo hračku, se v ruce prosekne rukávem a při
		zmáčknutí od hračky odletí. Hranice je 0,9 od středu, tedy o kus
		dál než půlka — díry v sýru mají z hračky koukat ven.
	]]
	t.test("žádný kus netrčí mimo hračku", function()
		for _, squishy in Live.Squishies do
			for index, piece in Toy.pieces(squishy) do
				local reach = piece.Offset.Magnitude + piece.Size.Magnitude / 2
				t.assert(
					reach <= 1.3,
					`{squishy.Name} #{index}: kus sahá {math.floor(reach * 100) / 100} od středu`
				)
			end
		end
	end)

	--[[
		Barvy detailů se počítají z barvy hračky. Kdyby role vracely
		tu samou barvu jako tělo, díry v sýru zmizí a zůstane žlutá
		kostka — což je přesně to, od čeho recepty pomohly.
	]]
	t.test("odstíny se od těla opravdu liší", function()
		local base = Color3.fromRGB(250, 232, 150)

		local body = Toy.colorFor("Body", base)
		local shade = Toy.colorFor("Shade", base)
		local light = Toy.colorFor("Light", base)

		local function distance(a: Color3, b: Color3): number
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
		end

		t.assert(distance(body, shade) > 0.15, "tmavší odstín se od těla neliší")
		t.assert(distance(body, light) > 0.1, "světlejší odstín se od těla neliší")
		t.assert(distance(shade, light) > 0.25, "tmavší a světlejší odstín splývají")
	end)

	t.test("vlastní barva v receptu přebije roli", function()
		local green = Color3.fromRGB(126, 208, 96)
		t.equal(Toy.colorFor("Body", Color3.new(1, 0, 0), green), green, "vlastní barva se ignoruje")
	end)

	--[[
		Obě hračky z referencí musí mít skutečný recept, ne náhradní
		primitivum: máslo obal s nápisem, sýr díry.
	]]
	t.test("máslo má obal s nápisem", function()
		local butter = Live.squishy("Butter")
		t.assert(butter ~= nil, "máslo v katalogu chybí")
		t.assert(Toy.hasRecipe("Butter"), "máslo nemá recept, je z něj holá kostka")

		local labels = 0
		local wraps = 0
		for _, piece in Toy.pieces(butter) do
			if piece.Label then
				labels += 1
				t.assert(#piece.Label.Text > 0, "nápis na obalu je prázdný")
			end
			if piece.Role == "Wrap" then
				wraps += 1
			end
		end

		t.equal(wraps, 1, "máslo nemá právě jeden obal")
		t.equal(labels, 1, "máslo nemá právě jeden nápis")
	end)

	t.test("sýr má díry", function()
		local cheese = Live.squishy("Cheese")
		t.assert(cheese ~= nil, "sýr v katalogu chybí")

		local holes = 0
		for _, piece in Toy.pieces(cheese) do
			if piece.Role == "Shade" then
				holes += 1
			end
		end

		t.assert(holes >= 4, `sýr má jen {holes} díry — z dálky to bude kostka`)
	end)

	--[[
		Kobliha musí mít uprostřed skutečnou díru. Prstenec z koulí ji
		má jen tehdy, když jsou koule dost daleko od středu; jinak se
		uprostřed slijí a je z toho koule.
	]]
	t.test("kobliha má díru uprostřed", function()
		local donut = Live.squishy("Donut")
		local pieces = Toy.pieces(donut)

		t.assert(#pieces >= 8, "kobliha není z prstence")

		for index, piece in pieces do
			local radius = Vector2.new(piece.Offset.X, piece.Offset.Z).Magnitude
			local width = math.max(piece.Size.X, piece.Size.Z) / 2
			t.assert(
				radius - width > -0.02,
				`kobliha #{index}: kus zasahuje do díry uprostřed`
			)
		end
	end)

	--[[
		Počet kusů má strop. Hráč jich může držet šest naráz a každý kus
		je díl navíc na scéně — hezký recept, který sebere výkon, se
		na telefonu neprojeví jako detail, ale jako sekání.
	]]
	t.test("žádná hračka není přeplácaná", function()
		for _, squishy in Live.Squishies do
			local count = #Toy.pieces(squishy)
			t.assert(count <= 18, `{squishy.Name} má {count} kusů, strop je 18`)
		end
	end)
end
