--!strict
--[[
	LeaderboardService — globální žebříček přes OrderedDataStore
	a fyzická tabule ve světě.

	Tabule stojí u spawnu schválně: hráč ji vidí hned, jak se připojí,
	a je to nejlevnější sociální motivace, jakou hra může mít.

	Zápis běží jen jednou za dvě minuty a jen když se číslo změnilo —
	OrderedDataStore má tvrdé limity a psát do něj po každém průrazu
	by hru zablokovalo.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Track = require(Shared.Track)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local store = DataStoreService:GetOrderedDataStore(Config.GameName .. "_Smashes_v1")

local TOP_COUNT = 10
local WRITE_INTERVAL = 120
local READ_INTERVAL = 60

local lastWritten: { [Player]: number } = {}
local board: { { Name: string, Value: number, UserId: number } } = {}
local rows: { Frame } = {}

-- Fyzická tabule --------------------------------------------------------------

--[[
	Barva podle pořadí. Zlato, stříbro, bronz — a pak už jednotná bílá.

	Není to ozdoba: v žánru je tabule to první, na co hráč u spawnu
	kouká, a když jsou všechny řádky stejné, nepozná z ní nic. Takhle
	uvidí špičku dřív, než začne číst.
]]
local RANK_COLORS = {
	Color3.fromRGB(255, 196, 60),
	Color3.fromRGB(214, 226, 246),
	Color3.fromRGB(226, 148, 84),
}

local function rankColor(index: number): Color3
	return RANK_COLORS[index] or Config.Theme.Text
end

local function buildBoard()
	local existing = Workspace:FindFirstChild("Leaderboard")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Leaderboard"
	folder.Parent = Workspace

	--[[
		U spawnu prvního světa, čelem k hráči — a na terase, která je
		o kus níž než dráha. Bez toho posunu tabule i její sloup visely
		přesně o výšku terasy nad zemí.
	]]
	local origin = Track.origin(1) + Vector3.new(-40, -Config.Track.DeckDrop, -26)
	local facing = CFrame.Angles(0, math.rad(35), 0)

	Build.part({
		Name = "Sloup",
		Size = Vector3.new(3, 16, 3),
		Position = origin + Vector3.new(0, 8, 0),
		Color = Config.Theme.PanelDeep,
		Material = Enum.Material.Plastic,
		Surface = Enum.SurfaceType.Studs,
		Parent = folder,
	})

	--[[
		Tabule je záměrně velká. V referenčních hrách zabírá u spawnu
		půlku obrazovky a je to hlavní důvod, proč se tam hráči zdržují;
		malá cedule stranou funguje jako výzdoba, ne jako cíl.
	]]
	local WIDTH, HEIGHT = 34, 26

	-- Zářivý rám kolem, aby tabule svítila i proti světlé stěně
	local frame = Build.part({
		Name = "Rám tabule",
		Size = Vector3.new(WIDTH + 2.4, HEIGHT + 2.4, 0.6),
		CFrame = CFrame.new(origin + Vector3.new(0, 26, 0.4)) * facing,
		Color = Config.Theme.Violet,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = folder,
	})
	Build.light(frame, Config.Theme.Violet, 2.4, 40)

	local panel = Build.part({
		Name = "Tabule",
		Size = Vector3.new(WIDTH, HEIGHT, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 26, 0)) * facing,
		Color = Config.Theme.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(680, 520)
	surface.LightInfluence = 0
	surface.Adornee = panel
	surface.Parent = panel

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Config.Theme.PanelDeep
	background.BorderSizePixel = 0
	background.Parent = surface

	-- Hlavička jako pruh, ne jen text: dá tabuli tvar i na dálku
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 76)
	header.BackgroundColor3 = Config.Theme.Panel
	header.BorderSizePixel = 0
	header.Parent = background

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.Text = "TOP SMASHERS"
	title.TextColor3 = Config.Theme.Gold
	title.TextScaled = true
	title.Parent = header

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.Outline
	stroke.Thickness = 4
	stroke.Parent = title

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -24, 1, -92)
	list.Position = UDim2.fromOffset(12, 84)
	list.BackgroundTransparency = 1
	list.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index = 1, TOP_COUNT do
		local row = Instance.new("Frame")
		row.Name = `Row{index}`
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = if index % 2 == 0 then Config.Theme.Panel else Config.Theme.PanelLight
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row

		--[[
			Portrét hráče. `rbxthumb://` je vestavěná adresa — Roblox si
			hlavu dokreslí sám, takže tabule vypadá jako v referenčních
			hrách a přitom se nic nenahrává.
		]]
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.Size = UDim2.fromOffset(32, 32)
		avatar.Position = UDim2.fromOffset(4, 3)
		avatar.BackgroundColor3 = Config.Theme.PanelDeep
		avatar.BorderSizePixel = 0
		avatar.Image = ""
		avatar.Parent = row

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = avatar

		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.Size = UDim2.fromOffset(34, 38)
		rank.Position = UDim2.fromOffset(40, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.LuckiestGuy
		rank.Text = `{index}`
		rank.TextColor3 = rankColor(index)
		rank.TextScaled = true
		rank.Parent = row

		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.Size = UDim2.new(0.55, -78, 1, 0)
		name.Position = UDim2.fromOffset(78, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.Text = "—"
		name.TextColor3 = Config.Theme.TextDim
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = row

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.Size = UDim2.new(0.45, -12, 1, 0)
		value.Position = UDim2.new(0.55, 0, 0, 0)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.LuckiestGuy
		value.Text = ""
		value.TextColor3 = Config.Theme.Acid
		value.TextScaled = true
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Parent = row

		rows[index] = row
	end
end

local function paintBoard()
	for index, row in rows do
		local entry = board[index]

		local avatar = row:FindFirstChild("Avatar") :: ImageLabel
		local name = row:FindFirstChild("PlayerName") :: TextLabel
		local value = row:FindFirstChild("Value") :: TextLabel

		if entry then
			avatar.Image = `rbxthumb://type=AvatarHeadShot&id={entry.UserId}&w=150&h=150`
			name.Text = entry.Name
			name.TextColor3 = rankColor(index)
			value.Text = `{Format.short(entry.Value)} SMASHES`
		else
			--[[
				Prázdné místo se nechává vidět. Skrýt ho by znamenalo,
				že tabule na novém serveru vypadá jako by měla jen tři
				řádky a chyběl jí zbytek.
			]]
			avatar.Image = ""
			name.Text = "—"
			name.TextColor3 = Config.Theme.TextDim
			value.Text = ""
		end
	end
end

-- Čtení a zápis ------------------------------------------------------------------

local function refresh()
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_COUNT)
	end)

	if not ok then
		warn(`[LeaderboardService] Nepodařilo se načíst žebříček: {pages}`)
		return
	end

	local page = (pages :: any):GetCurrentPage()
	local fresh = {}

	for _, entry in page do
		local userId = tonumber(entry.key)
		if not userId then
			continue
		end

		-- Jméno se dotahuje zvlášť a může selhat; UserId je pak lepší
		-- než prázdný řádek.
		local nameOk, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)

		table.insert(fresh, {
			Name = if nameOk then name else `User {userId}`,
			Value = entry.value,
			UserId = userId,
		})
	end

	board = fresh
	paintBoard()
end

local function write(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local value = math.floor(profile.Smashes)
	if value <= 0 or lastWritten[player] == value then
		return
	end
	lastWritten[player] = value

	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), value)
	end)

	if not ok then
		warn(`[LeaderboardService] Zápis pro {player.Name} selhal: {err}`)
		lastWritten[player] = nil
	end
end

function LeaderboardService.start()
	buildBoard()

	task.spawn(function()
		while true do
			refresh()
			task.wait(READ_INTERVAL)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(WRITE_INTERVAL)
			for _, player in Players:GetPlayers() do
				write(player)
			end
		end
	end)

	-- Poslední zápis při odchodu, ať se poslední sezení neztratí
	Players.PlayerRemoving:Connect(function(player)
		write(player)
		lastWritten[player] = nil
	end)
end

return LeaderboardService
