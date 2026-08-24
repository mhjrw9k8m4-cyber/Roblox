--!strict
--[[
	Remotes — jeden zdroj pravdy pro síťovou komunikaci.
	Server remoty vytvoří při prvním requiru, klient si na ně počká.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[
	`UnreliableRemoteEvent` pro zprávy, které chodí několikrát za sekundu
	a stačí u nich poslední hodnota.

	Není rychlejší ani menší než běžný remote — je NEPRIORITNÍ. Když se síť
	zahltí, zahodí se ona místo toho, aby zdržela nákup nebo uložení profilu.
	Přesně to chceme u Poweru: zahozený tik se za desetinu sekundy nahradí
	novějším, kdežto zahozený nákup by hráče naštval.

	Pozor na dvě věci: limit je zhruba 500 zpráv za sekundu na klienta
	(sdílený mezi všemi remoty stejného typu) a zpráva nad 1000 bajtů
	se zahodí celá.
]]
local DEFINITIONS: { [string]: string } = {
	-- Server -> klient
	ProfileChanged = "RemoteEvent", -- celý profil
	PowerChanged = "UnreliableRemoteEvent", -- chodí několikrát za sekundu
	SmashEffect = "UnreliableRemoteEvent", -- efekt; zahozený nikomu nechybí
	WorldChanged = "RemoteEvent", -- hráč se přesunul do jiného světa
	Notify = "RemoteEvent", -- toast zpráva
	OfflineReward = "RemoteEvent", -- co vydělal, než se přihlásil
	RetentionChanged = "RemoteEvent", -- denní odměna + stav úkolů
	EggHatched = "RemoteEvent", -- co se vylíhlo (spustí animaci)
	LeaderboardChanged = "RemoteEvent", -- nový žebříček
	PassesChanged = "RemoteEvent", -- vlastnictví gamepassů
	TradeChanged = "RemoteEvent", -- stav obchodu (oběma stranám)
	TradeInvite = "RemoteEvent", -- přišla žádost o obchod
	GiantWall = "UnreliableRemoteEvent", -- tiká každé dvě sekundy

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
	ClaimDaily = "RemoteFunction",
	ClaimQuest = "RemoteFunction",
	RedeemCode = "RemoteFunction",
	BuyEgg = "RemoteFunction",
	EquipPet = "RemoteFunction",
	MergePet = "RemoteFunction",
	TradeCandidates = "RemoteFunction",
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
