--!strict
--[[
	Remotes — jeden zdroj pravdy pro síťovou komunikaci.
	Server remoty vytvoří při prvním requiru, klient si na ně počká.

	Použití: `Remotes.ProfileChanged:FireClient(player, profile)`
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFINITIONS: { [string]: string } = {
	-- Server -> klient
	ProfileChanged = "RemoteEvent", -- celý profil (peníze, level, vlastnictví…)
	StrikeEffect = "RemoteEvent", -- rána: pozice, combo, výdělek, barvy, zvuk
	ObjectDestroyed = "RemoteEvent", -- objekt rozbit: velký efekt + bonus
	ObjectSpawned = "RemoteEvent", -- nový objekt na stanici
	Notify = "RemoteEvent", -- toast zpráva
	LevelUp = "RemoteEvent", -- nová úroveň
	RewardReady = "RemoteEvent", -- odměna za odehraný čas čeká

	-- Klient -> server
	Strike = "RemoteEvent", -- hráč sekl
	ClaimReward = "RemoteEvent", -- vyzvednutí odměny za čas

	-- Dotaz s odpovědí
	BuyTool = "RemoteFunction",
	EquipTool = "RemoteFunction",
	BuyObject = "RemoteFunction",
	EquipObject = "RemoteFunction",
	BuyUpgrade = "RemoteFunction",
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
