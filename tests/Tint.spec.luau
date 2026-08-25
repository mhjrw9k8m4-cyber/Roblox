--!strict
--[[
	Obarvení levelu podle světa.

	Levely se ve všech světech vykreslovaly úplně stejně: svět měnil
	halu, oblohu, mlhu a rekvizity, ale podlaha — to, po čem hráč běhá
	a na co se dívá nejvíc — byla v posledním světě na chlup stejná
	jako v prvním. Deset světů tím pádem vypadalo jako deset pozadí
	kolem jedné a té samé trati.

	Kontroluje se obojí: že se barva opravdu mění (jinak je celá věc
	k ničemu) a že se level nerozpustí (jinak by z dvanácti levelů
	zbyl jeden přebarvený).
]]

return function(t)
	local Zones = t.require("Zones")
	local Config = t.require("Config")

	local function distance(a: Color3, b: Color3): number
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
	end

	--[[
		První svět je referenční: levely z něj vycházejí, takže se v něm
		nesmí obarvit. Kdyby byl obarvený taky, neměl by se odstín
		v druhém světě od čeho odrazit.
	]]
	t.test("první svět nechává levely tak, jak jsou", function()
		for _, zone in Zones.List do
			local palette = Zones.palette(zone, Config.Worlds[1])
			t.equal(palette.Floor, zone.Floor, `{zone.Id}: podlaha se v prvním světě obarvila`)
			t.equal(palette.Edge, zone.Edge, `{zone.Id}: lem se v prvním světě obarvil`)
		end
	end)

	t.test("každý další svět levely znatelně přebarví", function()
		for index = 2, #Config.Worlds do
			local world = Config.Worlds[index]

			--[[
				Infinity Garden je krémový a máslo taky, takže zrovna
				u téhle dvojice vyjde posun malý — a je to v pořádku.
				Měří se proto přes VŠECHNY levely: svět, který nepohne
				ani jedním, neobarvuje nic.
			]]
			local moved = 0
			for _, zone in Zones.List do
				if distance(Zones.palette(zone, world).Floor, zone.Floor) > 0.03 then
					moved += 1
				end
			end

			t.assert(moved >= 8, `{world.Name} pohnul jen {moved} levely z {#Zones.List}`)
		end
	end)

	--[[
		A druhá strana: level musí zůstat poznat. Kdyby se přebarvil
		celý, byla by ze všech dvanácti jedna barevná chodba a rozdíl
		mezi máslem a chromem by zmizel.
	]]
	t.test("levely se v jednom světě nerozpustí do jedné barvy", function()
		for index = 2, #Config.Worlds do
			local world = Config.Worlds[index]

			local butter = Zones.palette(Zones.List[3], world).Floor
			local chrome = Zones.palette(Zones.List[11], world).Floor

			t.assert(
				distance(butter, chrome) > 0.25,
				`{world.Name}: máslo a chrom mají skoro stejnou podlahu`
			)
		end
	end)
end
