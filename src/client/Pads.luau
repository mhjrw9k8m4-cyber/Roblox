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

function Pads.setProfile(incoming)
	profile = incoming
	Pads.refresh()
end

function Pads.setBuy(callback: (string) -> ())
	onBuy = callback
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

	for _, pad in CollectionService:GetTagged("BuyPad") do
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
	Deska, na které hráč stojí. Bere se nejbližší, ne první nalezená —
	dvě desky vedle sebe by jinak kupovaly obě naráz.
]]
local function padUnder(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = REACH

	for _, pad in CollectionService:GetTagged("BuyPad") do
		if not pad:IsA("BasePart") then
			continue
		end

		local flat = (pad.Position - position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < bestDistance then
			best = pad
			bestDistance = flat.Magnitude
		end
	end

	return best
end

function Pads.start()
	RunService.Heartbeat:Connect(function()
		if not profile or not onBuy then
			return
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

		local pad = padUnder(root.Position)
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
