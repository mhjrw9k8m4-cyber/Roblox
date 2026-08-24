--!strict
--[[
	Textury vyrobené vzorem.

	Modul je čistá funkce ze souřadnic na barvu, takže se dá otestovat
	celý. Testuje se hlavně to, co jde snadno pokazit a v mřížce kostek
	se to nepozná dřív než ve hře: vzor, který obarví skoro všechno nebo
	skoro nic, není vzor — je to jednolitá plocha.
]]

return function(t)
	local Patterns = t.require("Patterns")
	local Zones = t.require("Zones")

	local PALETTE = {
		Base = Color3.fromRGB(255, 176, 206),
		Accent = Color3.fromRGB(255, 224, 236),
		Extra = Color3.fromRGB(150, 86, 255),
	}

	t.test("stejné souřadnice dají vždy stejnou barvu", function()
		for _, kind in Patterns.Kinds do
			for column = 0, 12 do
				for row = 0, 12 do
					t.assert(
						Patterns.tile(kind, column, row, PALETTE)
							== Patterns.tile(kind, column, row, PALETTE),
						`{kind}: {column},{row} vrátilo pokaždé něco jiného`
					)
				end
			end
		end
	end)

	--[[
		Nejdůležitější test souboru. Vzor musí obarvit rozumnou část
		plochy: pod 4 % se v mřížce ztratí, nad 70 % už není vzor,
		ale jiná základní barva.
	]]
	t.test("každý vzor je opravdu vidět", function()
		for _, kind in Patterns.Kinds do
			local coverage = Patterns.coverage(kind, PALETTE)

			t.assert(coverage > 0.04, `{kind}: obarví jen {math.floor(coverage * 100)} % — ztratí se`)
			t.assert(coverage < 0.7, `{kind}: obarví {math.floor(coverage * 100)} % — to už není vzor`)
		end
	end)

	t.test("vzor používá jen barvy z palety", function()
		for _, kind in Patterns.Kinds do
			for column = 0, 20 do
				for row = 0, 20 do
					local color = Patterns.tile(kind, column, row, PALETTE)
					t.assert(
						color == PALETTE.Base or color == PALETTE.Accent or color == PALETTE.Extra,
						`{kind}: {column},{row} vrátilo barvu mimo paletu`
					)
				end
			end
		end
	end)

	t.test("bez třetí barvy se vzor obejde", function()
		local two = { Base = PALETTE.Base, Accent = PALETTE.Accent }

		for _, kind in Patterns.Kinds do
			for column = 0, 14 do
				for row = 0, 14 do
					local color = Patterns.tile(kind, column, row, two)
					t.assert(
						color == two.Base or color == two.Accent,
						`{kind}: bez Extra vrátil něco třetího`
					)
				end
			end
		end
	end)

	t.test("neznámý vzor vrátí základní barvu, ne nic", function()
		t.equal(Patterns.tile("vymysleny", 3, 4, PALETTE), PALETTE.Base, "spadlo mimo paletu")
		t.assert(not Patterns.has("vymysleny"), "vymyšlený vzor se tváří jako známý")
	end)

	--[[
		Vzory se od sebe musí lišit. Dva stejné by znamenaly, že dvě zóny
		vypadají stejně, i když mají v konfiguraci jiné jméno.
	]]
	t.test("žádné dva vzory nekreslí totéž", function()
		local function fingerprint(kind: string): string
			local marks = {}
			for column = 0, 15 do
				for row = 0, 15 do
					local color = Patterns.tile(kind, column, row, PALETTE)
					table.insert(marks, if color == PALETTE.Base then "0" else "1")
				end
			end
			return table.concat(marks)
		end

		local seen = {}
		for _, kind in Patterns.Kinds do
			local print_ = fingerprint(kind)
			t.assert(not seen[print_], `{kind} kreslí totéž co {seen[print_]}`)
			seen[print_] = kind
		end
	end)

	t.test("každá zóna má vzor, který modul zná", function()
		local used = {}

		for _, zone in Zones.List do
			t.assert(Patterns.has(zone.Pattern), `zóna {zone.Id}: neznámý vzor {zone.Pattern}`)
			t.assert(not used[zone.Pattern], `vzor {zone.Pattern} má i zóna {used[zone.Pattern]}`)
			used[zone.Pattern] = zone.Id
		end
	end)

	--[[
		Posypka je jediný vzor, který se nesmí opakovat v rastru — právě
		tím se liší od teček. Kdyby byla pravidelná, byla by to mřížka.
	]]
	t.test("posypka je rozházená, ne v rastru", function()
		local gaps = {}
		local previous = nil

		for column = 0, 60 do
			if Patterns.tile("sprinkles", column, 0, PALETTE) ~= PALETTE.Base then
				if previous then
					gaps[column - previous] = true
				end
				previous = column
			end
		end

		local distinct = 0
		for _ in gaps do
			distinct += 1
		end

		t.assert(distinct > 1, "posypka má pořád stejné rozestupy — je to rastr, ne posypka")
	end)
end
