--!strict
--[[
	ToolService — čepel v ruce postavy.

	Nůž je čistě vizuál (poškození počítá ASMRService), ale je to
	nejviditelnější odměna za grind: každý tier vypadá jinak
	a od Neonové výš za sebou táhne svítící stopu.

	Zároveň drží leaderstats, aby byl postup vidět i v seznamu hráčů.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local DataService = require(script.Parent.DataService)

local ToolService = {}

local function buildBlade(definition): Model
	local model = Instance.new("Model")
	model.Name = "Čepel"

	local handle = Build.part({
		Name = "Rukojeť",
		Size = Vector3.new(0.35, 1.4, 0.35),
		Color = Color3.fromRGB(48, 42, 60),
		Material = Enum.Material.WoodPlanks,
		Anchored = false,
		CanCollide = false,
		Parent = model,
	})

	local blade = Build.part({
		Name = "Ostří",
		Size = Vector3.new(0.12, 3.2, 0.7),
		Color = definition.Color,
		Material = definition.Material,
		Anchored = false,
		CanCollide = false,
		Parent = model,
	})

	blade.CFrame = handle.CFrame * CFrame.new(0, 2.2, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = blade

	-- Vyšší tiery svítí a nechávají za sebou stopu
	if definition.Material == Enum.Material.Neon then
		Build.pointLight(blade, definition.Color, 2.5, 14)

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 1.6, 0)
		top.Parent = blade

		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -1.6, 0)
		bottom.Parent = blade

		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(definition.Color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = 0.28
		trail.LightEmission = 1
		trail.Parent = blade
	end

	model.PrimaryPart = handle
	return model
end

function ToolService.giveTool(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	-- Starý nůž pryč (z ruky i z batohu)
	for _, container in { backpack, character } do
		local old = container:FindFirstChild("Nůž")
		if old then
			old:Destroy()
		end
	end

	local definition = Config.tool(profile.EquippedTool) or Config.Tools[1]

	local tool = Instance.new("Tool")
	tool.Name = "Nůž"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = definition.Name

	local model = buildBlade(definition)
	local handle = model.PrimaryPart :: BasePart
	handle.Name = "Handle"

	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()

	tool.Grip = CFrame.new(0, -0.4, 0) * CFrame.Angles(math.rad(-100), 0, 0)
	tool.Parent = backpack

	-- Automaticky vzít do ruky, ať hráč nemusí nic hledat
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

-- Leaderstats: vidět postup i v seznamu hráčů (Tab)
local function setupLeaderstats(player: Player, profile)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("StringValue")
	coins.Name = "💰 Peníze"
	coins.Value = Format.short(profile.Coins)
	coins.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "⭐ Rebirthy"
	rebirths.Value = profile.Rebirths
	rebirths.Parent = leaderstats

	leaderstats.Parent = player
end

function ToolService.refreshStats(player: Player)
	local profile = DataService.get(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("💰 Peníze") :: StringValue?
	if coins then
		coins.Value = Format.short(profile.Coins)
	end

	local rebirths = leaderstats:FindFirstChild("⭐ Rebirthy") :: IntValue?
	if rebirths then
		rebirths.Value = profile.Rebirths
	end
end

function ToolService.setup(player: Player, profile)
	setupLeaderstats(player, profile)
end

function ToolService.start()
	-- Leaderstats se aktualizují jednou za sekundu; častěji nemá smysl,
	-- čísla v seznamu hráčů nikdo nečte po jednotlivých ranách.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				ToolService.refreshStats(player)
			end
		end
	end)
end

return ToolService
