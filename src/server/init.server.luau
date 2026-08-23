--!strict
--[[
	Server — startovní bod.

	Pořadí je záměrné: nejdřív se postaví svět, pak se nastartují služby
	a teprve potom se pouští hráči dovnitř. Kdo se připojil dřív, než
	server doběhl, se dopracuje přes smyčku na konci.
]]

local Players = game:GetService("Players")

local Services = script:WaitForChild("Services")

local ASMRService = require(Services.ASMRService)
local DataService = require(Services.DataService)
local PlaytimeService = require(Services.PlaytimeService)
local ShopService = require(Services.ShopService)
local StationService = require(Services.StationService)
local ToolService = require(Services.ToolService)

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Humanoid")
	-- Jeden frame, ať se postava stihne poskládat, než s ní hneme
	task.wait(0.1)

	StationService.teleport(player)
	ToolService.giveTool(player)
end

local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)

	ToolService.setup(player, profile)
	StationService.assign(player)
	ASMRService.refreshAutoLoop(player)
	ASMRService.pushProfile(player)
	PlaytimeService.push(player)

	if not profile._canSave then
		require(game:GetService("ReplicatedStorage").Shared.Remotes).Notify:FireClient(player, {
			Text = "Ukládání je vypnuté (DataStore není dostupný). Postup se neuloží.",
			Kind = "warn",
		})
	end

	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacterAdded, player, character)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	ASMRService.stopAutoLoop(player)
	StationService.release(player)
	-- DataService.release se volá vlastním připojením v DataService.start
end

-- Start -------------------------------------------------------------------

StationService.build()

DataService.start()
StationService.start()
ASMRService.start()
ShopService.start()
PlaytimeService.start()
ToolService.start()

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)

Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Hráči, kteří se připojili během startu serveru
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print(`[ASMR Studio] Server běží — {#StationService.all()} stanic připraveno.`)
