--!strict
--[[
	Klient — vstupní bod.

	Drží lokální kopii profilu, staví UI a trať, posílá serveru, co sebral
	a co chce prorazit, a přehrává efekty, které přijdou zpátky.

	Power se po sebrání přičítá jen podle serveru (PowerChanged) — plovoucí
	"+N" u pickupu je jen optický odhad, aby odezva byla okamžitá. Kdyby se
	počítadlo řídilo klientem, rozešlo by se s realitou při každém zahozeném
	paketu.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)

local CharacterFX = require(script:WaitForChild("CharacterFX"))
local Effects = require(script:WaitForChild("Effects"))
local SoundKit = require(script:WaitForChild("SoundKit"))
local Textures = require(script:WaitForChild("Textures"))
local TrackView = require(script:WaitForChild("TrackView"))

local UI = script:WaitForChild("UI")
local HUD = require(UI.HUD)
local Notifications = require(UI.Notifications)
local Panels = require(UI.Panels)

local player = Players.LocalPlayer

-- Rozhraní --------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "PowerSmash"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

local hud = HUD.new(screen)
local panels = Panels.new(screen)
local toasts = Notifications.new(screen)
local track = TrackView.new()

-- Stav -------------------------------------------------------------------------

local profile = nil
local shownWorld = 0
-- Rozdíl mezi serverovým a lokálním časem, aby odpočty tikaly správně
local timeOffset = 0

local applyWorldAtmosphere

local function applyProfile(incoming)
	if not incoming then
		return
	end

	profile = incoming
	timeOffset = (incoming.ServerTime or os.time()) - os.time()

	hud:setProfile(profile)
	panels:setProfile(profile)
	track:setProfile(profile)

	if incoming.WorldIndex ~= shownWorld then
		shownWorld = incoming.WorldIndex
		applyWorldAtmosphere(incoming.WorldIndex)

		local world = Config.Worlds[incoming.WorldIndex]
		if world then
			CharacterFX.setWorldColor(world.Accent)
		end
	end
end

local function serverNow(): number
	return os.time() + timeOffset
end

-- Atmosféra podle světa ----------------------------------------------------------
-- Světy stojí vedle sebe v jednom místě, takže mlhu nejde nastavit
-- serverem pro každý zvlášť — musí ji přepínat klient.

function applyWorldAtmosphere(worldIndex: number)
	local world = Config.Worlds[worldIndex]
	if not world then
		return
	end

	Lighting.FogColor = world.Fog
	Lighting.FogStart = 40
	Lighting.FogEnd = 320

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = world.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		atmosphere.Decay = world.Fog
	end
end

-- Akce z UI ------------------------------------------------------------------------

local function invoke(remoteName: string)
	return function(value: string)
		local ok, result = pcall(function()
			return (Remotes :: any)[remoteName]:InvokeServer(value)
		end)

		if not ok then
			toasts:push("Server did not respond, try again.", "error")
			return
		end

		if result and result.Ok == false and result.Message then
			toasts:push(result.Message, "warn")
		elseif result and result.Ok then
			SoundKit.playNamed("Purchase")
		end
	end
end

panels.Callbacks.BuyUpgrade = invoke("BuyUpgrade")
panels.Callbacks.BuyWorld = invoke("BuyWorld")
panels.Callbacks.EquipTitle = invoke("EquipTitle")
panels.Callbacks.DoRebirth = invoke("DoRebirth")

panels.Callbacks.EnterWorld = function(value: string)
	local index = tonumber(value)
	if not index then
		return
	end

	local ok, result = pcall(function()
		return Remotes.EnterWorld:InvokeServer(index)
	end)

	if ok and result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	end
end

hud.OnAction = function(kind: string)
	SoundKit.playNamed("Click")

	if kind == "chest" then
		local ok, result = pcall(function()
			return Remotes.ClaimChest:InvokeServer()
		end)
		if ok and result and result.Ok == false and result.Message then
			toasts:push(result.Message, "warn")
		end
		return
	end

	panels:open(kind)
end

hud.OnQuickBuy = function(id: string)
	SoundKit.playNamed("Click")

	local ok, result = pcall(function()
		return Remotes.BuyUpgrade:InvokeServer(id)
	end)

	if not ok then
		toasts:push("Server did not respond, try again.", "error")
	elseif result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	else
		SoundKit.playNamed("Purchase")
	end
end

hud.OnBuyBoost = function(id: string)
	local ok, result = pcall(function()
		return Remotes.BuyBoost:InvokeServer(id)
	end)

	if ok and result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	elseif ok and result and result.Ok then
		SoundKit.playNamed("Purchase")
	end
end

-- Klávesové zkratky -----------------------------------------------------------------

local SHORTCUTS = {
	[Enum.KeyCode.One] = "upgrades",
	[Enum.KeyCode.Two] = "worlds",
	[Enum.KeyCode.Three] = "titles",
	[Enum.KeyCode.Four] = "rebirth",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	local target = SHORTCUTS[input.KeyCode]
	if target then
		panels:open(target)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		panels:close()
	end
end)

-- Události ze serveru -------------------------------------------------------------------

Remotes.ProfileChanged.OnClientEvent:Connect(applyProfile)

Remotes.PowerChanged.OnClientEvent:Connect(function(payload)
	if profile then
		profile.Power = payload.Power
	end

	hud:setPower(payload.Power)
	track:setPower(payload.Power)

	if payload.Source == "collect" then
		hud:pulsePower()
	end

	if payload.Crits and payload.Crits > 0 then
		toasts:push(`LUCKY ×5!  +{Format.short(payload.Gained)} power`, "success")
	end
end)

Remotes.SmashEffect.OnClientEvent:Connect(function(payload)
	local isLocal = payload.UserId == player.UserId

	if isLocal then
		track:breakBarrier(payload.Barrier, payload)
		return
	end

	-- Průraz jiného hráče: efekt na správném místě, ale tišší
	if profile and payload.WorldIndex == profile.WorldIndex then
		local world = Config.Worlds[payload.WorldIndex]
		local position = Track.barrierPosition(payload.WorldIndex, payload.Barrier) + Vector3.new(0, 4, 0)
		Effects.smash(position, Vector3.new(Config.Track.Width - 4, 20, 2.4), world, payload, false)
	end
end)

Remotes.WorldChanged.OnClientEvent:Connect(function(worldIndex)
	applyWorldAtmosphere(worldIndex)
	local world = Config.Worlds[worldIndex]
	if world then
		toasts:push(`Entered {world.Name} — power reset to 0.`, "info")
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(payload)
	toasts:push(payload.Text, payload.Kind)

	if payload.Sound then
		SoundKit.playNamed(payload.Sound)
	end
end)

Remotes.OfflineReward.OnClientEvent:Connect(function(payload)
	toasts:push(
		`Welcome back! You earned {Format.short(payload.Coins)} 💰 while away ({Format.time(payload.Seconds)}).`,
		"success"
	)
end)

-- Postava -------------------------------------------------------------------------------

local function bindCharacter(model: Model)
	local world = Config.Worlds[shownWorld] or Config.Worlds[1]
	CharacterFX.bind(model, world.Accent)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- Start -----------------------------------------------------------------------------

track:start()
Textures.start()
CharacterFX.start()

task.spawn(function()
	-- Pojistka, kdyby se klient načetl dřív, než server stihl push poslat
	local ok, result = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)

	if ok and result and not profile then
		applyProfile(result)
	end
end)

-- Odpočty boostů a truhly tikají lokálně
task.spawn(function()
	while true do
		task.wait(1)
		if profile then
			hud:refreshTimers(serverNow())
		end
	end
end)

toasts:push("Collect +1 pickups, then run into the wall to smash it!", "info")
