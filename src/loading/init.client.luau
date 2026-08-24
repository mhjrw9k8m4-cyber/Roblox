--!strict
--[[
	Loading screen — první tři sekundy rozhodují.

	Běží z ReplicatedFirst, protože jen odtud se dá zachytit okamžik, kdy
	hráč vidí obrazovku poprvé, a schovat výchozí Roblox načítání dřív,
	než probliknout stihne.

	Roblox 2026 řadí hry podle toho, jestli se hráč vrátí. Sezení, které
	začne šedivým "Loading…", má proti sobě první dojem hned od začátku.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Paleta se sem opisuje schválně: ReplicatedFirst běží dřív, než je
-- ReplicatedStorage.Shared zaručeně k dispozici, a čekat na něj by
-- znamenalo mít chvíli černou obrazovku.
local INK = Color3.fromRGB(18, 13, 38)
local GROUND = Color3.fromRGB(14, 10, 28)
local POWER = Color3.fromRGB(118, 220, 255)
local VIOLET = Color3.fromRGB(150, 86, 255)
local TEXT = Color3.fromRGB(255, 255, 255)
local DIM = Color3.fromRGB(202, 186, 240)

local TIPS = {
	"Run into a wall once you have enough power.",
	"Hold a squishy and mash it. Every squeeze is free power.",
	"Log in every day — the day 7 reward is worth it.",
	"Entering a new world resets your power to zero.",
	"Finish all three daily quests to keep your streak.",
	"Codes give free coins and gems. Check the Codes tab.",
}

local screen = Instance.new("ScreenGui")
screen.Name = "Loading"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 100
screen.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = GROUND
backdrop.BorderSizePixel = 0
backdrop.Parent = screen

local glow = Instance.new("Frame")
glow.Size = UDim2.fromScale(1, 1)
glow.BackgroundColor3 = VIOLET
glow.BackgroundTransparency = 0.85
glow.BorderSizePixel = 0
glow.Parent = backdrop

local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(1, 1),
})
gradient.Parent = glow

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 110)
title.Position = UDim2.new(0, 20, 0.5, -150)
title.BackgroundTransparency = 1
title.Font = Enum.Font.LuckiestGuy
title.Text = "POWER SMASH"
title.TextColor3 = TEXT
title.TextScaled = true
title.Parent = backdrop

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = INK
titleStroke.Thickness = 6
titleStroke.Parent = title

-- Lišta postupu: hráč musí vidět, že se něco děje
local track = Instance.new("Frame")
track.Size = UDim2.new(0, 420, 0, 26)
track.Position = UDim2.new(0.5, 0, 0.5, -10)
track.AnchorPoint = Vector2.new(0.5, 0)
track.BackgroundColor3 = INK
track.BorderSizePixel = 0
track.Parent = backdrop

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 13)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = POWER
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 13)
fillCorner.Parent = fill

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -40, 0, 30)
status.Position = UDim2.new(0, 20, 0.5, 26)
status.BackgroundTransparency = 1
status.Font = Enum.Font.FredokaOne
status.Text = "Building the world…"
status.TextColor3 = DIM
status.TextSize = 20
status.Parent = backdrop

local tip = Instance.new("TextLabel")
tip.Size = UDim2.new(1, -40, 0, 30)
tip.Position = UDim2.new(0, 20, 1, -70)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.FredokaOne
tip.Text = "TIP:  " .. TIPS[math.random(1, #TIPS)]
tip.TextColor3 = POWER
tip.TextSize = 19
tip.Parent = backdrop

--[[
	Předinačtení. Bez něj hráč prvních pár sekund kouká na šedé díly,
	než se dotáhnou materiály — a to je přesně ten okamžik, kdy část
	lidí odchází.
]]
task.spawn(function()
	local deadline = os.clock() + 12
	local progress = 0

	-- Lišta jede plynule i tehdy, když předinačtení nehlásí mezikroky
	local running = true
	task.spawn(function()
		while running do
			progress = math.min(progress + 0.012, 0.94)
			fill.Size = UDim2.fromScale(progress, 1)
			task.wait(0.05)
		end
	end)

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	status.Text = "Loading sounds and textures…"

	local assets = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(assets, descendant)
		end
		if #assets >= 400 then
			break
		end
	end

	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)

	-- Minimální doba, ať se obrazovka nemihne na zlomek sekundy
	while os.clock() < deadline and progress < 0.94 do
		RunService.Heartbeat:Wait()
	end

	running = false
	status.Text = "Ready!"

	TweenService:Create(fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(1, 1) }):Play()
	task.wait(0.35)

	local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
	for _, object in { backdrop, glow, title, status, tip } do
		if object:IsA("Frame") then
			TweenService:Create(object, fade, { BackgroundTransparency = 1 }):Play()
		else
			TweenService:Create(object, fade, { TextTransparency = 1 }):Play()
		end
	end
	TweenService:Create(titleStroke, fade, { Transparency = 1 }):Play()
	TweenService:Create(track, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(fill, fade, { BackgroundTransparency = 1 }):Play()

	task.wait(0.6)
	screen:Destroy()
end)
