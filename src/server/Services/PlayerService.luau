--!strict
--[[
	PlayerService — všechno kolem hráče samotného: cedulka s titulem nad
	hlavou, leaderstats a offline výdělky při návratu do hry.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local PlayerService = {}

-- Cedulka nad hlavou ---------------------------------------------------------

function PlayerService.refreshNameplate(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local existing = head:FindFirstChild("Nameplate")
	if existing then
		existing:Destroy()
	end

	local title = Config.titleFor(profile.Smashes)
	for _, entry in Config.Titles do
		if entry.Id == profile.Title and profile.Smashes >= entry.Smashes then
			title = entry
			break
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromScale(9, 2.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.LightInfluence = 0
	billboard.Adornee = head

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(1, 0.45)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = `[{title.Name}]`
	titleLabel.TextColor3 = title.Color
	titleLabel.TextScaled = true
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = billboard

	local nameLabel = titleLabel:Clone()
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.Text = player.DisplayName
	nameLabel.TextColor3 = Config.Theme.Text
	nameLabel.LayoutOrder = 2
	nameLabel.Parent = billboard

	for _, label in { titleLabel, nameLabel } do
		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.Theme.Outline
		stroke.Thickness = 3
		stroke.Parent = label
	end

	billboard.Parent = head
end

-- Leaderstats ------------------------------------------------------------------

function PlayerService.setupStats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("StringValue")
	coins.Name = "💰 Coins"
	coins.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "⭐ Rebirths"
	rebirths.Parent = leaderstats

	local smashes = Instance.new("IntValue")
	smashes.Name = "💥 Smashes"
	smashes.Parent = leaderstats

	leaderstats.Parent = player
	PlayerService.refreshStats(player)
end

function PlayerService.refreshStats(player: Player)
	local profile = DataService.get(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("💰 Coins") :: StringValue?
	if coins then
		coins.Value = Format.short(profile.Coins)
	end

	local rebirths = leaderstats:FindFirstChild("⭐ Rebirths") :: IntValue?
	if rebirths then
		rebirths.Value = profile.Rebirths
	end

	local smashes = leaderstats:FindFirstChild("💥 Smashes") :: IntValue?
	if smashes then
		smashes.Value = profile.Smashes
	end
end

-- Offline výdělky -----------------------------------------------------------------

--[[
	Když se hráč vrátí, dostane zlomek toho, co by za tu dobu vydělal.
	Sazba je schválně jen 35 % a strop 8 hodin: má to být důvod se vrátit,
	ne náhrada za hraní.
]]
function PlayerService.grantOffline(player: Player)
	local profile = DataService.get(player)
	if not profile or profile.LeftAt <= 0 then
		return
	end

	local now = os.time()
	local elapsed = math.clamp(now - profile.LeftAt, 0, Config.Rewards.OfflineCapHours * 3600)
	if elapsed < 60 then
		return
	end

	local reward = math.floor(
		Economy.coinsPerSecond(profile, now) * elapsed * Config.Rewards.OfflineRate
	)
	if reward <= 0 then
		return
	end

	profile.Coins += reward
	DataService.markDirty(player)

	Remotes.OfflineReward:FireClient(player, {
		Coins = reward,
		Seconds = elapsed,
	})
end

function PlayerService.start()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				PlayerService.refreshStats(player)
			end
		end
	end)
end

return PlayerService
