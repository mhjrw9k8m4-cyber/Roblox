--!strict
--[[
	Remotes — jeden zdroj pravdy pro síťovou komunikaci.
	Server remoty vytvoří při prvním requiru, klient si na ně počká.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFINITIONS: { [string]: string } = {
	-- Server -> klient
	ProfileChanged = "RemoteEvent", -- celý profil
	PowerChanged = "RemoteEvent", -- jen Power (chodí často, drží se malý)
	SmashEffect = "RemoteEvent", -- bariéra praskla (vidí všichni)
	WorldChanged = "RemoteEvent", -- hráč se přesunul do jiného světa
	Notify = "RemoteEvent", -- toast zpráva
	OfflineReward = "RemoteEvent", -- co vydělal, než se přihlásil

	-- Klient -> server
	Collect = "RemoteEvent", -- sebral pickup(y)
	Smash = "RemoteEvent", -- zkusil prorazit bariéru

	-- Dotaz s odpovědí
	BuyUpgrade = "RemoteFunction",
	BuyWorld = "RemoteFunction",
	EnterWorld = "RemoteFunction",
	BuyBoost = "RemoteFunction",
	EquipTitle = "RemoteFunction",
	ClaimChest = "RemoteFunction",
	DoRebirth = "RemoteFunction",
	GetProfile = "RemoteFunction",
}

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

return setmetatable({}, {
	__index = function(_, key: string)
		assert(DEFINITIONS[key], `Remotes: neznámý remote "{key}"`)
		return folder:WaitForChild(key)
	end,
}) :: any
