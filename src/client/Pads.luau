--!strict
--[[
	Pads — nákupní desky na trati.

	Vylepšení jde koupit i z menu, ale ve velkých hrách žánru se kupuje
	hlavně tak, že si na desku **stoupneš a stojíš**. Rozdíl není
	v pohodlí: hráč tím dostane důvod se v chodbě zastavovat a chodba
	dostane obsah. Prázdný tunel vypadá levně, i když je barevný.

	Kupuje se opakovaně, dokud hráč stojí. Jedno kliknutí na úroveň by
	u šedesáti úrovní znamenalo šedesát kliknutí, takže by to nikdo
	nedělal a deska by byla jen ozdoba.

	Cenu ani úroveň si klient nepočítá pro sebe — ukazuje je jen na
	ceduli. Nákup vždycky potvrzuje server.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local player = Players.LocalPlayer

local Pads = {}

-- Jak daleko od středu desky se ještě kupuje
local REACH = 6
-- Pauza mezi nákupy; kratší by ze stání udělalo nekontrolovaný výprodej
local INTERVAL = 0.4

local profile: any = nil
local lastBuyAt = 0
local onBuy: ((string) -> ())? = nil

--[[
	Vlastní seznam desek místo `GetTagged` v každém snímku.

	`GetTagged` vrací pokaždé **novou tabulku** — na trati je desek přes
	sto a při šedesáti snímcích za sekundu z toho byla tabulka se sto
	padesáti položkami šedesátkrát za vteřinu, kterou hned zahodil
	sběrač paměti. Sto padesát porovnání vzdálenosti není nic, ta
	alokace je všechno.
]]
local pads: { BasePart } = {}

--[[
	Portály do dalších světů. Chovají se stejně jako desky — proximita,
	pauza, potvrzení serverem — takže jedou v té samé smyčce. Druhá
	kopie by se s ní dřív nebo později rozešla v pauze nebo v dosahu.
]]
local portals: { BasePart } = {}
local onWorld: ((string, boolean) -> ())? = nil

--[[
	Cedule nově příchozí desky se musí přepsat.

	Se zapnutým streamingem k hráči desky doputují až ve chvíli, kdy
	k nim dojde — ne při startu. Do teď se cedule přepisovaly jen při
	změně profilu, takže deska, která doputovala, když hráč zrovna
	stál, na sobě nesla text ze serveru: bez úrovně, bez ceny, bez
	červené, když na ni hráč nemá.

	Nepřekresluje se rovnou při každém příchodu: naráz jich dorazí
	klidně padesát a padesát průchodů celým seznamem v jednom snímku
	je přesně ten zásek, kterému se celý tenhle modul vyhýbá.
	Nastaví se příznak a překreslí se jednou v nejbližším snímku.
]]
local stale = false

local function tracker(list: { BasePart })
	local function add(instance: Instance)
		if instance:IsA("BasePart") and not table.find(list, instance) then
			table.insert(list, instance)
			stale = true
		end
	end

	local function remove(instance: Instance)
		local at = table.find(list, instance :: any)
		if at then
			table.remove(list, at)
		end
	end

	return add, remove
end

function Pads.setProfile(incoming)
	profile = incoming
	Pads.refresh()
end

function Pads.setBuy(callback: (string) -> ())
	onBuy = callback
end

--[[
	Co udělat s portálem. Druhý parametr říká, jestli hráč svět už
	vlastní: nevlastněný se kupuje, vlastněný se do něj vstupuje.
]]
function Pads.setWorld(callback: (string, boolean) -> ())
	onWorld = callback
end

--[[
	Přepíše cedule podle profilu.

	Ukazuje se úroveň, účinek a cena — a když na ni hráč nemá, cena
	zčervená. Bez toho by hráč stál na desce a nechápal, proč se nic
	neděje.
]]
function Pads.refresh()
	if not profile then
		return
	end

	Pads.refreshPortals()

	for _, pad in pads do
		local id = pad:GetAttribute("Upgrade")
		local upgrade = if typeof(id) == "string" then Config.upgrade(id) else nil
		if not upgrade then
			continue
		end

		local billboard = pad:FindFirstChild("Info")
		local label = billboard and billboard:FindFirstChild("PadText") :: TextLabel?
		if not label then
			continue
		end

		local level = (profile.Upgrades and profile.Upgrades[id]) or 0
		local price = Config.upgradePrice(id, level)

		if not price then
			label.Text = `<b>{upgrade.Icon} {string.upper(upgrade.Name)}</b>\nLVL {level}  ·  MAX`
			label.TextColor3 = Config.Theme.Success
			continue
		end

		local affordable = profile.Coins >= price
		label.Text = `<b>{upgrade.Icon} {string.upper(upgrade.Name)}</b>\n`
			.. `LVL {level}  ·  💰 {Format.short(price)}`
		label.TextColor3 = if affordable then Config.Theme.Text else Config.Theme.Danger

		pad.Color = if affordable then Config.Theme.Acid else Config.Theme.PanelDeep
	end
end

--[[
	Cedule nad portálem. Cena je pro všechny stejná, ale to, jestli si
	ji hráč může dovolit a jestli svět už vlastní, se liší člověk od
	člověka — proto to skládá klient, ne server.
]]
function Pads.refreshPortals()
	if not profile then
		return
	end

	for _, portal in portals do
		local id = portal:GetAttribute("World")
		local world = if typeof(id) == "string" then Config.world(id) else nil
		if not world then
			continue
		end

		local billboard = portal.Parent and portal.Parent:FindFirstChild("Blána brány")
		local info = billboard and billboard:FindFirstChild("Info")
		local label = info and info:FindFirstChild("PortalText") :: TextLabel?
		if not label then
			continue
		end

		local owned = (profile.Worlds or {})[id] == true

		if owned then
			label.Text = `<b>{string.upper(world.Name)}</b>\nENTER`
			label.TextColor3 = Config.Theme.Success
			continue
		end

		--[[
			Zamčená brána musí říct dvě věci, ne jen cenu: **jak daleko**
			hráč je a **co za to** dostane.

			Samotná cena je u zamčené brány osmiciferné číslo, které nic
			neznamená — hráč u ní stojí, nemá na ni a nemá jak poznat,
			jestli je to na pět minut nebo na hodinu. Kolik už má a kolik
			pickup v tom světě sype, jsou obojí čísla, která zná.
		]]
		local current = Config.Worlds[profile.WorldIndex]
		local times = if current and current.Pickup > 0
			then world.Pickup / current.Pickup
			else 1
		local percent = math.floor(math.min(profile.Coins / math.max(world.Price, 1), 1) * 100)

		if profile.Coins >= world.Price then
			label.Text = `<b>{string.upper(world.Name)}</b>\n💰 {Format.short(world.Price)}  ·  READY\n`
				.. `PICKUPS {Format.multiplier(times)}`
			label.TextColor3 = Config.Theme.Gold
		else
			label.Text = `<b>{string.upper(world.Name)}</b>\n`
				.. `💰 {Format.short(profile.Coins)} / {Format.short(world.Price)}  ·  {percent}%\n`
				.. `PICKUPS {Format.multiplier(times)}`
			label.TextColor3 = Config.Theme.Danger
		end
	end
end

--[[
	Deska, na které hráč stojí. Bere se nejbližší, ne první nalezená —
	dvě desky vedle sebe by jinak kupovaly obě naráz.
]]
local function nearest(list: { BasePart }, position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = REACH

	for _, part in list do
		local flat = (part.Position - position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < bestDistance then
			best = part
			bestDistance = flat.Magnitude
		end
	end

	return best
end

function Pads.start()
	--[[
		Desky staví server, takže na klienta dorazí se zpožděním a po
		přepnutí světa přibývají dál. Seznam se proto plní z obou
		stran: co už je, i co teprve přijde.
	]]
	for _, entry in { { "BuyPad", pads }, { "WorldPortal", portals } } do
		local tag = entry[1] :: string
		local list = entry[2] :: { BasePart }
		local add, remove = tracker(list)

		for _, part in CollectionService:GetTagged(tag) do
			add(part)
		end

		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	end

	RunService.Heartbeat:Connect(function()
		if not profile or not onBuy then
			return
		end

		if stale then
			stale = false
			Pads.refresh()
		end

		local now = os.clock()
		if now - lastBuyAt < INTERVAL then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		--[[
			Portál má přednost před deskou. Kdyby se braly v opačném
			pořadí, deska u brány by hráči snědla stisk a do světa by
			se nedostal, dokud by neodstoupil stranou.
		]]
		local portal = nearest(portals, root.Position)
		if portal and onWorld then
			local id = portal:GetAttribute("World")
			if typeof(id) == "string" then
				local world = Config.world(id)
				local owned = (profile.Worlds or {})[id] == true

				if world and (owned or profile.Coins >= world.Price) then
					lastBuyAt = now
					onWorld(id, owned)
					return
				end
			end
			return
		end

		local pad = nearest(pads, root.Position)
		if not pad then
			return
		end

		local id = pad:GetAttribute("Upgrade")
		if typeof(id) ~= "string" then
			return
		end

		--[[
			Na co hráč nemá, se nezkouší kupovat. Server by to odmítl,
			ale posílal by se dotaz dvakrát za vteřinu po celou dobu,
			co hráč na desce stojí.
		]]
		local level = (profile.Upgrades and profile.Upgrades[id]) or 0
		local price = Config.upgradePrice(id, level)
		if not price or profile.Coins < price then
			return
		end

		lastBuyAt = now
		onBuy(id)
	end)
end

return Pads
