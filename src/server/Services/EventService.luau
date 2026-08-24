--!strict
--[[
	EventService — Obří zeď.

	Serverová událost: uprostřed hubu stojí zeď se společným životem.
	Každý průraz běžné bariéry do ní zároveň bouchne, takže se hráči
	nemusí nikam přesouvat ani přepínat režim — přispívají tím, co dělají.

	Odměna se dělí podle podílu na poškození, ale kus dostane každý, kdo
	přispěl aspoň něčím. Čistý podíl by odřízl nováčky, čistě rovný díl
	by odměnil přihlížení.

	Život zdi se odvíjí od nejsilnějšího hráče na serveru. Pevné číslo by
	na serveru samotných začátečníků bylo nedosažitelné a na serveru
	veteránů by padlo za pár vteřin.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

local EventService = {}

local SETTINGS = Live.GiantWall

type Round = {
	Health: number,
	MaxHealth: number,
	EndsAt: number,
	Contributions: { [Player]: number },
	Active: boolean,
}

local round: Round = {
	Health = 0,
	MaxHealth = 0,
	EndsAt = 0,
	Contributions = {},
	Active = false,
}

local wall: BasePart? = nil
local label: TextLabel? = nil

-- Stavba ------------------------------------------------------------------------

local function buildWall()
	local existing = Workspace:FindFirstChild("GiantWall")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "GiantWall"
	folder.Parent = Workspace

	-- Vedle spawnu prvního světa, aby ji hráč viděl hned po připojení
	local origin = Track.origin(1) + Vector3.new(30, 0, -26)

	local part = Build.part({
		Name = "Wall",
		Size = Vector3.new(26, 30, 4),
		CFrame = CFrame.new(origin + Vector3.new(0, 15, 0)) * CFrame.Angles(0, math.rad(-35), 0),
		Color = Config.Theme.Violet,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = folder,
	})
	Build.light(part, Config.Theme.Violet, 4, 60)

	local sign = Build.part({
		Name = "Sign",
		Size = Vector3.new(28, 7, 1),
		CFrame = part.CFrame * CFrame.new(0, 19, 0),
		Color = Config.Theme.PanelDeep,
		CanCollide = false,
		Parent = folder,
	})

	local _, text = Build.billboard({
		Adornee = sign,
		Text = "<b>GIANT WALL</b>",
		Size = UDim2.fromScale(28, 7),
		Color = Config.Theme.Gold,
		MaxDistance = 500,
	})

	wall = part
	label = text
end

local function paintWall()
	local part = wall
	if not part then
		return
	end

	local ratio = if round.MaxHealth > 0 then round.Health / round.MaxHealth else 0

	-- Zeď viditelně slábne: mění barvu a ztenčuje se
	part.Color = Config.Theme.Danger:Lerp(Config.Theme.Violet, ratio)
	part.Size = Vector3.new(26, 30, math.max(4 * ratio, 0.6))
	part.Transparency = 0.15 + (1 - ratio) * 0.4

	if label then
		label.Text = if round.Active
			then `<b>GIANT WALL</b>\n{Format.short(round.Health)} / {Format.short(round.MaxHealth)}`
			else "<b>GIANT WALL</b>\nrebuilding…"
	end
end

-- Kolo --------------------------------------------------------------------------

--[[
	Život se počítá z nejsilnějšího hráče na serveru, ne z pevného čísla.
	Server samých začátečníků by na pevnou hodnotu nedosáhl, server
	veteránů by ji smetl za pár vteřin.
]]
local function computeHealth(): number
	local strongest = 0

	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			strongest = math.max(strongest, Economy.coinsPerSecond(profile, os.time()))
		end
	end

	local players = math.max(#Players:GetPlayers(), 1)
	return math.max(strongest * SETTINGS.HealthPerPlayer * math.sqrt(players), SETTINGS.MinHealth)
end

function EventService.snapshot()
	return {
		Active = round.Active,
		Health = round.Health,
		MaxHealth = round.MaxHealth,
		SecondsLeft = math.max(round.EndsAt - os.time(), 0),
	}
end

local function push()
	Remotes.GiantWall:FireAllClients(EventService.snapshot())
end

local function startRound()
	round.Health = computeHealth()
	round.MaxHealth = round.Health
	round.EndsAt = os.time() + SETTINGS.RoundSeconds
	round.Contributions = {}
	round.Active = true

	paintWall()
	push()

	Remotes.Notify:FireAllClients({
		Text = "GIANT WALL appeared! Smash anything to damage it.",
		Kind = "info",
		Sound = "Ready",
	})
end

--[[
	Rozdělení odměny. Každý, kdo přispěl, dostane základ; zbytek se dělí
	podle podílu na poškození. Kdo nepřispěl, nedostane nic — jinak by
	se vyplatilo jen stát.
]]
local function payOut()
	local total = 0
	for _, amount in round.Contributions do
		total += amount
	end

	if total <= 0 then
		return
	end

	local expires = os.time() + SETTINGS.BoostSeconds
	-- Hláška bere násobek z boostu, který se opravdu uděluje
	local granted = Config.boost("Power2")
	local best: Player? = nil
	local bestAmount = 0

	for player, amount in round.Contributions do
		local profile = DataService.get(player)
		if not profile then
			continue
		end

		local share = SETTINGS.BaseShare + (1 - SETTINGS.BaseShare) * (amount / total)
		local reward = math.floor(round.MaxHealth * share * 0.4)

		profile.Coins += reward
		profile.Gems += SETTINGS.GemsForAll

		-- Boost pro celý server: prodlouží běžící, nezahodí ho
		for _, field in { "Power2", "Coins2" } do
			profile.Boosts[field] = math.max(profile.Boosts[field] or 0, expires)
		end

		DataService.markDirty(player)
		GameService.pushProfile(player)

		Remotes.Notify:FireClient(player, {
			Text = `Giant Wall down! +{Format.short(reward)} 💰  +{SETTINGS.GemsForAll} 💎  `
				.. `×{granted.Value} boost`,
			Kind = "success",
			Sound = "WorldClear",
		})

		if amount > bestAmount then
			best, bestAmount = player, amount
		end
	end

	if best then
		local profile = DataService.get(best)
		if profile then
			profile.Gems += SETTINGS.GemsForTop
			DataService.markDirty(best)
			GameService.pushProfile(best)
		end

		Remotes.Notify:FireAllClients({
			Text = `{best.DisplayName} dealt the most damage! +{SETTINGS.GemsForTop} 💎`,
			Kind = "success",
		})
	end
end

local function endRound(broken: boolean)
	round.Active = false
	round.Health = 0
	paintWall()
	push()

	if broken then
		payOut()
	else
		Remotes.Notify:FireAllClients({
			Text = "Giant Wall held. It rebuilds in two minutes.",
			Kind = "warn",
		})
	end

	round.Contributions = {}
end

--[[
	Přispění. Volá se z běžného průrazu, takže hráč nemusí nikam chodit
	ani nic přepínat — přispívá tím, co stejně dělá.
]]
function EventService.contribute(player: Player, amount: number)
	if not round.Active or amount <= 0 then
		return
	end

	round.Contributions[player] = (round.Contributions[player] or 0) + amount
	round.Health = math.max(round.Health - amount, 0)

	paintWall()

	if round.Health <= 0 then
		endRound(true)
	end
end

function EventService.start()
	buildWall()

	task.spawn(function()
		while true do
			task.wait(SETTINGS.BreakSeconds)

			-- Na prázdném serveru nemá smysl kolo pouštět
			if #Players:GetPlayers() == 0 then
				continue
			end

			startRound()

			while round.Active and os.time() < round.EndsAt do
				task.wait(2)
				push()
			end

			if round.Active then
				endRound(false)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		round.Contributions[player] = nil
	end)
end

return EventService
