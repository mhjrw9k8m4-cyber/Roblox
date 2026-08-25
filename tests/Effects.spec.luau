--!strict
--[[
	Nastavení pro slabá zařízení.

	Přepínač "Low graphics" zhasíná světla ve světě — na telefonu je
	dvacet svítících bodů v jedné chodbě to první, co sundá snímkovou
	frekvenci.

	Chyba, kterou to má hlídat: přepínač platil jen na to, co bylo
	v okamžiku přepnutí načtené. Se zapnutým streamingem je to okolí
	hráče, takže se zbytek trati rozsvítil, jakmile k němu hráč
	doběhl — nastavení kvůli výkonu a výkon se stejně po chvíli
	propadl.
]]

return function(t)
	local Effects = t.require("Effects")
	local Config = t.require("Config")

	--[[
		Svět staví `Boot.spec` a pořadí testů nikdo neurčuje. Když tenhle
		soubor běží dřív, postaví se tady — `WorldService.build()` si
		složku vyrobí sám a Boot ji později najde postavenou, takže se
		nic nerozbije ani v opačném pořadí.
	]]
	local function worldFolder()
		local workspaceService = t.stub().service("Workspace")
		if not workspaceService:FindFirstChild("Worlds") then
			t.require("WorldService").build()
		end

		local worlds = workspaceService:FindFirstChild("Worlds")
		return worlds and worlds:FindFirstChild(Config.Worlds[1].Id)
	end

	local function newLight(name: string)
		local holder = Instance.new("Part")
		holder.Name = name
		holder.Parent = worldFolder()

		local light = Instance.new("PointLight")
		light.Enabled = true
		light.Parent = holder

		return light
	end

	t.test("zhasnutí platí i na světlo, které dorazí později", function()
		t.assert(worldFolder() ~= nil, "svět se nepostavil")

		local before = newLight("Světlo předem")
		Effects.setLowGraphics(true)
		t.equal(before.Enabled, false, "světlo, které tam bylo, zůstalo svítit")

		--[[
			A teď to hlavní: díl dorazí AŽ POTOM, co hráč přepnul.
			Přesně tohle dělá streaming, když hráč doběhne dál.
		]]
		local later = newLight("Světlo pozdě")
		t.equal(later.Enabled, false, "pozdě příchozí světlo se rozsvítilo navzdory nastavení")
	end)

	t.test("vypnutí nastavení světla zase rozsvítí", function()
		t.assert(worldFolder() ~= nil, "svět se nepostavil")
		Effects.setLowGraphics(false)

		local later = newLight("Světlo po vypnutí")
		t.equal(later.Enabled, true, "světlo zůstalo zhasnuté, i když se nastavení vyplo")
	end)
end
