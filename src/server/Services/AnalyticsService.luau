--!strict
--[[
	Analytics — kde hráči odcházejí.

	Roblox řadí hry podle retence. Zlepšit se nedá to, co se neměří:
	bez tohohle víš, že ti lidi odcházejí, ale ne jestli v prvních třiceti
	sekundách (nepochopili ovládání), po první zdi (nudné tempo), nebo
	po první hodině (došel obsah). Každá z těch tří odpovědí znamená
	úplně jinou opravu.

	Onboarding funnel je proto rozepsaný na kroky, které jdou po sobě
	v první minutě hraní. Kde se čísla mezi dvěma kroky propadnou,
	tam je problém.

	Poznámky k API:
	  * události jde posílat jen ze serveru a jen v publikované hře —
	    ve Studiu tiše nic nedělají, proto je všechno v pcall,
	  * každý krok se posílá jednou za hráče; opakované volání by
	    zkreslilo poměry mezi kroky.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = require(script.Parent.DataService)

local Analytics = {}

--[[
	Kroky první minuty. Pořadí je to, v jakém je hráč musí projít —
	funnel má smysl jen tehdy, když kroky opravdu jdou po sobě.
]]
local ONBOARDING = {
	Joined = { Step = 1, Name = "joined" },
	FirstPickup = { Step = 2, Name = "collected_first_power" },
	FirstSmash = { Step = 3, Name = "smashed_first_wall" },
	FirstUpgrade = { Step = 4, Name = "bought_first_upgrade" },
	FirstSqueeze = { Step = 5, Name = "squeezed_first_squishy" },
	SecondWorld = { Step = 6, Name = "unlocked_second_world" },
}

-- Co už bylo pro daného hráče odesláno; jinak by se poměry rozbily
local sent: { [Player]: { [string]: boolean } } = {}
-- Do onboarding funnelu patří jen hráči, kteří opravdu začínají
local isNew: { [Player]: boolean } = {}
-- Které volání už jednou selhalo; hlásí se jednou, ne každou vteřinu
local warned: { [string]: boolean } = {}

--[[
	Obal na volání analytiky.

	Samotný `pcall` by schoval i chybu v podpisu volání a hra by tiše
	neposílala nic — což je horší než neměřit vůbec, protože to vypadá,
	že se měří. Proto se první selhání každého druhu vypíše do konzole.
]]
local function track(label: string, call: () -> ())
	local ok, err = pcall(call)
	if ok or warned[label] then
		return
	end

	warned[label] = true
	warn(`[Analytics] {label} selhalo: {err}`)
end

local function once(player: Player, key: string): boolean
	local marks = sent[player]
	if not marks then
		marks = {}
		sent[player] = marks
	end

	if marks[key] then
		return false
	end

	marks[key] = true
	return true
end

--[[
	Krok onboardingu. Posílá se jen hráčům, kteří jsou v první minutě —
	veterán, který si dnes koupil první upgrade, by jinak vypadal jako
	nováček a zkreslil čísla.
]]
function Analytics.onboarding(player: Player, key: string)
	local step = ONBOARDING[key]
	if not step then
		return
	end

	--[[
		Veterán do onboarding funnelu nepatří ani prvním krokem. Kdyby se
		mu počítalo "joined", vypadal by poměr kroku 1 → 2 mnohem hůř,
		než jaký ve skutečnosti je u nováčků.
	]]
	if not isNew[player] then
		return
	end

	if not once(player, `onboarding_{key}`) then
		return
	end

	track("onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step.Step, step.Name)
	end)
end

--[[
	Označí hráče jako nováčka. Volá se jednou při vstupu — kdo už má
	za sebou průraz, do onboarding funnelu nepatří.
]]
function Analytics.markNew(player: Player)
	local profile = DataService.get(player)
	isNew[player] = profile ~= nil and profile.Smashes == 0
end

--[[
	Pohyb měny. `flow` je "Source" (přibylo) nebo "Sink" (ubylo).

	Sledovat obojí je důležité: hra, kde hráči peníze jen přibývají,
	nemá co kupovat, a hra, kde jen ubývají, je frustrující.
]]
function Analytics.economy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	item: string?
)
	if amount <= 0 then
		return
	end

	track("economy", function()
		local flowType = if flow == "Source"
			then Enum.AnalyticsEconomyFlowType.Source
			else Enum.AnalyticsEconomyFlowType.Sink

		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currency,
			amount,
			math.floor(balance),
			transaction,
			item
		)
	end)
end

--[[
	Postup světem. Roblox z toho staví přehled, ve kterém světě se hráči
	zasekávají — to je přesně to místo, kde se ladí tempo.
]]
function Analytics.world(player: Player, worldIndex: number, completed: boolean)
	local world = Config.Worlds[worldIndex]
	if not world then
		return
	end

	local key = `world_{world.Id}_{if completed then "done" else "start"}`
	if not once(player, key) then
		return
	end

	track("progression", function()
		AnalyticsService:LogProgressionEvent(
			player,
			"worlds",
			if completed
				then Enum.AnalyticsProgressionType.Complete
				else Enum.AnalyticsProgressionType.Start,
			{ world = world.Id },
			world.Name,
			worldIndex
		)
	end)
end

-- Vlastní událost pro věci, které nikam jinam nepatří
function Analytics.custom(player: Player, name: string, value: number?, fields: { [string]: any }?)
	track("custom", function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
end

function Analytics.start()
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
		isNew[player] = nil
	end)
end

return Analytics
