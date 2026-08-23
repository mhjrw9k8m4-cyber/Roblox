--!strict
--[[
	Klient — vstupní bod.

	Drží lokální kopii profilu, staví UI, posílá seky na server
	a přehrává efekty, které přijdou zpátky.

	Peníze se po ráně přičítají lokálně, aby čísla naskakovala okamžitě;
	server je každých pár sekund srovná svou verzí, takže se lokální
	odhad nemůže rozejít nadlouho.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local Effects = require(script:WaitForChild("Effects"))
local UI = script:WaitForChild("UI")
local HUD = require(UI.HUD)
local Notifications = require(UI.Notifications)
local Panel = require(UI.Panel)

local player = Players.LocalPlayer

-- Rozhraní ------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "ASMRStudio"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

local hud = HUD.new(screen)
local panel = Panel.new(screen)
local notifications = Notifications.new(screen)

-- Stav ----------------------------------------------------------------------

local profile = nil
local lastStrikeAt = 0

local function applyProfile(newProfile)
	if not newProfile then
		return
	end
	profile = newProfile
	hud:setProfile(profile)
	panel:setProfile(profile)
end

-- Sekání ---------------------------------------------------------------------

local function canStrike(): boolean
	if not profile then
		return false
	end

	-- Klientská prodleva jen šetří provoz; skutečné slovo má server.
	local cooldown = Economy.cooldown(profile)
	if os.clock() - lastStrikeAt < cooldown then
		return false
	end

	return true
end

local function strike()
	if not canStrike() then
		return
	end

	lastStrikeAt = os.clock()
	Remotes.Strike:FireServer()
end

hud.OnStrike = strike

hud.OnAction = function(kind: string)
	panel:open(kind)
end

-- Vstup: myš, dotyk i klávesnice ------------------------------------------
-- Držení tlačítka opakuje seky, aby se dalo grindovat bez rozbití myši.

local holding = false

local function setHolding(state: boolean)
	if holding == state then
		return
	end
	holding = state

	if not holding then
		return
	end

	task.spawn(function()
		while holding do
			strike()
			task.wait(0.03)
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		setHolding(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		setHolding(false)
	end
end)

-- Mezerník jako alternativa pro klávesnici
ContextActionService:BindAction("Seknout", function(_, state)
	if state == Enum.UserInputState.Begin then
		setHolding(true)
	elseif state == Enum.UserInputState.End then
		setHolding(false)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Space, Enum.KeyCode.E)

-- Zkratky do panelů
local SHORTCUTS = {
	[Enum.KeyCode.One] = "tools",
	[Enum.KeyCode.Two] = "objects",
	[Enum.KeyCode.Three] = "upgrades",
	[Enum.KeyCode.Four] = "rewards",
	[Enum.KeyCode.Five] = "rebirth",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	local target = SHORTCUTS[input.KeyCode]
	if target then
		panel:open(target)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		panel:close()
	end
end)

-- Akce z panelu -> server ----------------------------------------------------

local function invoke(remoteName: string)
	return function(value)
		local ok, result = pcall(function()
			return (Remotes :: any)[remoteName]:InvokeServer(value)
		end)

		if not ok then
			notifications:push("Server neodpověděl, zkus to znovu.", "error")
			return
		end

		if result and result.Ok == false and result.Message then
			notifications:push(result.Message, "warn")
		end
	end
end

panel.Callbacks.BuyTool = invoke("BuyTool")
panel.Callbacks.EquipTool = invoke("EquipTool")
panel.Callbacks.BuyObject = invoke("BuyObject")
panel.Callbacks.EquipObject = invoke("EquipObject")
panel.Callbacks.BuyUpgrade = invoke("BuyUpgrade")
panel.Callbacks.DoRebirth = invoke("DoRebirth")

panel.Callbacks.ClaimReward = function(minutes)
	Remotes.ClaimReward:FireServer(minutes)
end

-- Události ze serveru ---------------------------------------------------------

Remotes.ProfileChanged.OnClientEvent:Connect(applyProfile)

Remotes.StrikeEffect.OnClientEvent:Connect(function(payload)
	local isLocal = payload.UserId == player.UserId

	Effects.strike(payload, isLocal)

	if isLocal then
		if profile then
			profile.Coins += payload.Coins
			hud:setCoins(profile.Coins)
		end
		hud:setIntegrity(payload.Ratio)

		if not payload.Auto then
			hud:setCombo(payload.Combo, payload.Multiplier)
		end
	end
end)

Remotes.ObjectDestroyed.OnClientEvent:Connect(function(payload)
	local isLocal = payload.UserId == player.UserId

	Effects.destroy(payload, isLocal)

	if isLocal then
		if profile then
			profile.Coins += payload.Bonus
			hud:setCoins(profile.Coins)
		end
		hud:setIntegrity(0)
	end
end)

Remotes.ObjectSpawned.OnClientEvent:Connect(function(payload)
	hud:setIntegrity(1)

	if profile then
		profile.Integrity = payload.Integrity
		profile.MaxIntegrity = payload.MaxIntegrity
		profile.EquippedObject = payload.ObjectId
		hud:setProfile(profile)
	end
end)

Remotes.LevelUp.OnClientEvent:Connect(function(level)
	Effects.levelUp(level)
	notifications:push(`Postoupil jsi na úroveň {level}!`, "success")
end)

Remotes.Notify.OnClientEvent:Connect(function(payload)
	notifications:push(payload.Text, payload.Kind)
end)

Remotes.RewardReady.OnClientEvent:Connect(function(rewards)
	panel:setRewards(rewards)

	local pending = false
	for _, reward in rewards do
		if reward.Ready and not reward.Claimed then
			pending = true
			break
		end
	end

	hud:setRewardBadge(pending)
end)

-- Start ----------------------------------------------------------------------

task.spawn(function()
	-- Profil může dorazit i pushem ze serveru; tohle je pojistka,
	-- kdyby se klient načetl dřív, než server stihl push poslat.
	local ok, result = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)

	if ok and result and not profile then
		applyProfile(result)
	end
end)

-- Combo padá i vizuálně, když hráč přestane sekat
task.spawn(function()
	while true do
		task.wait(0.25)
		if os.clock() - lastStrikeAt > Config.Core.ComboWindow then
			hud:setCombo(0, 1)
		end
	end
end)

notifications:push("Vítej v ASMR Studiu! Klikni na materiál a začni krájet.", "info")
