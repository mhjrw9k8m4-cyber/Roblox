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
local board: { { Name: string, Value: number } } = {}
local rows: { TextLabel } = {}

-- Fyzická tabule --------------------------------------------------------------

local function buildBoard()
	local existing = Workspace:FindFirstChild("Leaderboard")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Leaderboard"
	folder.Parent = Workspace

	-- U spawnu prvního světa, čelem k hráči
	local origin = Track.origin(1) + Vector3.new(-26, 0, -26)

	Build.part({
		Name = "Sloup",
		Size = Vector3.new(2, 16, 2),
		Position = origin + Vector3.new(0, 8, 0),
		Color = Config.Theme.PanelDeep,
		Material = Enum.Material.Metal,
		Parent = folder,
	})

	local panel = Build.part({
		Name = "Tabule",
		Size = Vector3.new(20, 22, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 24, 0)) * CFrame.Angles(0, math.rad(35), 0),
		Color = Config.Theme.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	Build.light(panel, Config.Theme.Violet, 2, 30)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(500, 560)
	surface.LightInfluence = 0
	surface.Adornee = panel
	surface.Parent = panel

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Config.Theme.PanelDeep
	background.BorderSizePixel = 0
	background.Parent = surface

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 70)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.Text = "TOP SMASHERS"
	title.TextColor3 = Config.Theme.Gold
	title.TextScaled = true
	title.Parent = background

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -24, 1, -84)
	list.Position = UDim2.fromOffset(12, 76)
	list.BackgroundTransparency = 1
	list.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index = 1, TOP_COUNT do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 42)
		row.BackgroundColor3 = if index % 2 == 0 then Config.Theme.Panel else Config.Theme.PanelLight
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Font = Enum.Font.FredokaOne
		row.Text = `{index}.  —`
		row.TextColor3 = Config.Theme.Text
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = index
		row.Parent = list

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = row

		rows[index] = row
	end
end

local function paintBoard()
	for index, row in rows do
		local entry = board[index]
		if entry then
			row.Text = `{index}.  {entry.Name}`
			row.TextColor3 = if index == 1 then Config.Theme.Gold else Config.Theme.Text

			-- Hodnota vpravo jako druhý popisek, ať se s jménem nepere
			local value = row:FindFirstChild("Value") :: TextLabel?
			if not value then
				value = Instance.new("TextLabel")
				value.Name = "Value"
				value.Size = UDim2.new(0.35, 0, 1, 0)
				value.Position = UDim2.new(0.65, 0, 0, 0)
				value.BackgroundTransparency = 1
				value.Font = Enum.Font.FredokaOne
				value.TextColor3 = Config.Theme.Acid
				value.TextScaled = true
				value.TextXAlignment = Enum.TextXAlignment.Right
				value.Parent = row
			end
			;(value :: TextLabel).Text = Format.short(entry.Value)
		else
			row.Text = `{index}.  —`
			row.TextColor3 = Config.Theme.TextDim
			local value = row:FindFirstChild("Value")
			if value then
				value:Destroy()
			end
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

function LeaderboardService.top()
	return board
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
