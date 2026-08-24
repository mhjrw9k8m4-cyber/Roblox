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

local CameraFX = require(script:WaitForChild("CameraFX"))
local CharacterFX = require(script:WaitForChild("CharacterFX"))
local CosmeticFX = require(script:WaitForChild("CosmeticFX"))
local Effects = require(script:WaitForChild("Effects"))
local Onboarding = require(script:WaitForChild("Onboarding"))
local Pets = require(script:WaitForChild("Pets"))
local SoundKit = require(script:WaitForChild("SoundKit"))
local Textures = require(script:WaitForChild("Textures"))
local TrackView = require(script:WaitForChild("TrackView"))

local UI = script:WaitForChild("UI")
local HUD = require(UI.HUD)
local Layout = require(UI.Layout)
local Preview = require(UI.Preview)
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

-- Rozvržení se musí spočítat dřív, než UI vznikne
Layout.start()

local hud = HUD.new(screen)
local panels = Panels.new(screen)
local toasts = Notifications.new(screen)
local track = TrackView.new()

-- Stav -------------------------------------------------------------------------

local profile = nil
local shownWorld = 0
local settings = { Music = true, Sfx = true, HideUi = false, LowGraphics = false }
-- Rozdíl mezi serverovým a lokálním časem, aby odpočty tikaly správně
local timeOffset = 0

local applyWorldAtmosphere

--[[
	Nastavení se aplikuje lokálně hned a na server jde jen k uložení.
	Čekat na potvrzení by u přepínače působilo rozbitě.
]]
local function applySettings(incoming, send: boolean)
	for key, value in incoming do
		if typeof(value) == "boolean" then
			settings[key] = value
		end
	end

	SoundKit.setEnabled(settings.Sfx)
	Effects.setLowGraphics(settings.LowGraphics)
	Pets.setLowGraphics(settings.LowGraphics, profile and profile.EquippedPets or {})
	CosmeticFX.setLowGraphics(settings.LowGraphics)
	hud:setHidden(settings.HideUi)

	if send then
		Remotes.SaveSettings:FireServer(settings)
	end
end

local function applyProfile(incoming)
	if not incoming then
		return
	end

	profile = incoming
	timeOffset = (incoming.ServerTime or os.time()) - os.time()

	hud:setProfile(profile)
	panels:setProfile(profile)
	track:setProfile(profile)

	if incoming.Settings then
		applySettings(incoming.Settings, false)
	end
	Pets.setEquipped(incoming.EquippedPets or {})
	Onboarding.update(profile)

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

	-- Zvuk se přebarví spolu se světem: stejné vzorky, jiný dozvuk a ekvalizér
	SoundKit.setWorld(world.Id)
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

-- Kus se posílá jako "druh:id" v jednom řetězci, protože `row` umí předat
-- jen jednu hodnotu. Rozbalí se hned tady, server dostane tabulku.
panels.Callbacks.EquipCosmetic = function(value: string)
	local kind, id = string.match(value, "^(%w+):(.+)$")
	if not kind or not id then
		return
	end

	task.spawn(function()
		local ok = pcall(function()
			return Remotes.EquipCosmetic:InvokeServer({ Kind = kind, Id = id })
		end)

		if ok then
			SoundKit.playNamed("Click")
		end
	end)
end
panels.Callbacks.DoRebirth = invoke("DoRebirth")

panels.Callbacks.ClaimDaily = invoke("ClaimDaily")
panels.Callbacks.ClaimQuest = invoke("ClaimQuest")
panels.Callbacks.RedeemCode = invoke("RedeemCode")
panels.Callbacks.BuyEgg = invoke("BuyEgg")
panels.Callbacks.EquipPet = invoke("EquipPet")
panels.Callbacks.MergePet = invoke("MergePet")

-- Obchod jede po jednosměrných událostech: server na každou změnu stejně
-- pošle celý nový stav, takže na odpověď není co čekat.
panels.Callbacks.TradeRequest = function(userId: string)
	local id = tonumber(userId)
	if id then
		Remotes.TradeRequest:FireServer(id)
	end
end

panels.Callbacks.TradeRespond = function(answer: string)
	Remotes.TradeRespond:FireServer(answer == "yes")
end

panels.Callbacks.TradeAdd = function(petId: string)
	Remotes.TradeOffer:FireServer(petId, true)
end

panels.Callbacks.TradeRemove = function(petId: string)
	Remotes.TradeOffer:FireServer(petId, false)
end

panels.Callbacks.TradeConfirm = function()
	Remotes.TradeConfirm:FireServer()
end

panels.Callbacks.TradeCancel = function()
	Remotes.TradeCancel:FireServer()
end

panels.Callbacks.PromptPass = function(id: string)
	Remotes.PromptPass:FireServer(id)
end

panels.Callbacks.PromptProduct = function(id: string)
	Remotes.PromptProduct:FireServer(id)
end

panels.Callbacks.ToggleSetting = function(key: string)
	applySettings({ [key] = not settings[key] }, true)

	if profile then
		profile.Settings = table.clone(settings)
		panels:setProfile(profile)
	end
end

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

--[[
	Seznam hráčů se natahuje až při otevření záložky. Posílat ho průběžně
	by znamenalo provoz kvůli obrazovce, kterou většina hráčů neotevře.
]]
local function refreshTradeCandidates()
	task.spawn(function()
		local ok, list = pcall(function()
			return Remotes.TradeCandidates:InvokeServer()
		end)
		if ok and list then
			panels:setCandidates(list)
		end
	end)
end

hud.OnAction = function(kind: string)
	SoundKit.playNamed("Click")

	if kind == "trade" then
		refreshTradeCandidates()
	end

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
		Effects.smash({
			CFrame = CFrame.new(position),
			Size = Vector3.new(Config.Track.Width - 4, 20, 2.4),
			World = world,
			Payload = payload,
			IsLocal = false,
		})
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

Remotes.RetentionChanged.OnClientEvent:Connect(function(snapshot)
	panels:setRetention(snapshot)

	-- Odznaky: co čeká na vyzvednutí
	local questReady = false
	for _, quest in snapshot.Quests or {} do
		if not quest.Claimed and quest.Progress >= quest.Target then
			questReady = true
			break
		end
	end

	hud:setBadges({
		daily = (snapshot.Daily and not snapshot.Daily.Claimed) or questReady,
	})
end)

Remotes.EggHatched.OnClientEvent:Connect(function(payload)
	Pets.playHatch(payload)
	SoundKit.playNamed(if payload.Rarity == "Mythic" or payload.Rarity == "Legendary" then "Rebirth" else "Purchase")
	toasts:push(`Hatched {payload.Rarity} {payload.Name}!  +{math.floor(payload.Power * 100)}% power`, "success")
end)

Remotes.TradeChanged.OnClientEvent:Connect(function(state)
	panels:setTrade(state)
end)

Remotes.TradeInvite.OnClientEvent:Connect(function(invite)
	panels:setInvite(invite)
	SoundKit.playNamed("Ready")
	toasts:push(`{invite.Name} wants to trade — open the Trade tab.`, "info")
end)

Remotes.GiantWall.OnClientEvent:Connect(function(state)
	hud:setEvent(state)
end)

Remotes.PassesChanged.OnClientEvent:Connect(function(payload)
	if payload.Offers then
		panels:setOffers(payload.Offers)
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
CosmeticFX.start()
CameraFX.start()
Pets.start()
Preview.start()

task.spawn(function()
	-- Pojistka, kdyby se klient načetl dřív, než server stihl push poslat
	local ok, result = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)

	if ok and result and not profile then
		applyProfile(result)
	end

	-- Nápověda jen pro úplně nového hráče; existujícího by jen otravovala
	if profile then
		Onboarding.start(screen, profile)
		Onboarding.update(profile)
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
