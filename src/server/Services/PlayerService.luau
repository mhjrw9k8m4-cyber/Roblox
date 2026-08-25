--!strict
--[[
	PlayerService — všechno kolem hráče samotného: cedulka s titulem nad
	hlavou, leaderstats a offline výdělky při návratu do hry.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Perks = require(Shared.Perks)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local PlayerService = {}

--[[
	Kolizní skupiny.

	Střepy z rozbité bariéry vznikají na klientovi a mají zapnuté kolize,
	aby se dokutálely po zemi. Bez oddělené skupiny by ale mlátily do
	hráče a odhazovaly ho — vlastní destrukce by se stala překážkou.

	Skupiny se registrují na serveru a replikují se; klient si pak jen
	nastaví `part.CollisionGroup = "Debris"`.
]]
local function setupCollisionGroups()
	for _, name in { "Debris", "Character" } do
		-- Opakovaná registrace vyhodí chybu, ale nastat může (rychlý restart)
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end

	pcall(function()
		-- se zemí ano, s hráčem ne, mezi sebou ne (šetří výpočty)
		PhysicsService:CollisionGroupSetCollidable("Debris", "Character", false)
		PhysicsService:CollisionGroupSetCollidable("Debris", "Debris", false)
	end)
end

function PlayerService.applyCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Character"
		end
	end
end

-- Cedulka nad hlavou ---------------------------------------------------------

--[[
	Co stojí na jmenovce nad hlavou.

	Oddělené od stavby GUI schválně: text je jediná část, která se dá
	splést, a takhle se dá zkontrolovat bez postavy, hlavy a billboardu.

	Rebirthy se lepí k titulu jako hvězdička. Samostatný řádek by
	jmenovku protáhl na čtyři patra a z dálky by se z toho stal shluk.
]]
function PlayerService.nameplate(profile: any, displayName: string)
	local title = Config.titleFor(profile.Smashes)
	for _, entry in Config.Titles do
		if entry.Id == profile.Title and profile.Smashes >= entry.Smashes then
			title = entry
			break
		end
	end

	local rebirths = profile.Rebirths or 0
	local mark = if rebirths > 0 then `⭐{rebirths} ` else ""

	return title, {
		Title = `{mark}[{title.Name}]`,
		Name = displayName,
		Stat = `💥 {Format.short(profile.Smashes or 0)}`,
	}
end

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

	local title, lines = PlayerService.nameplate(profile, player.DisplayName)

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
	titleLabel.Size = UDim2.fromScale(1, 0.34)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = lines.Title
	titleLabel.TextColor3 = title.Color
	titleLabel.TextScaled = true
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = billboard

	local nameLabel = titleLabel:Clone()
	nameLabel.Size = UDim2.fromScale(1, 0.38)
	nameLabel.Text = lines.Name
	nameLabel.TextColor3 = Config.Theme.Text
	nameLabel.LayoutOrder = 2
	nameLabel.Parent = billboard

	--[[
		Třetí řádek s počtem průrazů.

		Ve velkých hrách žánru je nad hlavou vidět, jak na tom kdo je —
		hráč tím při míjení pozná, koho dohání. Bez toho je jmenovka jen
		popiska a postup ostatních nejde vidět nikde než v tabulce
		u spawnu, kam se nikdo nevrací.
	]]
	local statLabel = titleLabel:Clone()
	statLabel.Size = UDim2.fromScale(1, 0.28)
	statLabel.Text = lines.Stat
	statLabel.TextColor3 = Config.Theme.Acid
	statLabel.LayoutOrder = 3
	statLabel.Parent = billboard

	for _, label in { titleLabel, nameLabel, statLabel } do
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

	-- Perk "Night Shift" zvedá právě tuhle sazbu, nic jiného.
	local rate = Config.Rewards.OfflineRate * (1 + Perks.value(profile, "Offline"))
	local reward = math.floor(Economy.coinsPerSecond(profile, now) * elapsed * rate)
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
	setupCollisionGroups()

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
