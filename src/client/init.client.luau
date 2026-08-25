--!strict
--[[
	Klient — vstupní bod.

	Drží lokální kopii profilu, staví UI a trať, posílá serveru, co sebral
	a co chce prorazit, a přehrává efekty, které přijdou zpátky.

	Power se po sebrání přičítá jen podle serveru (PowerChanged) — plovoucí
	"+N" u pickupu je jen optický odhad, aby odezva byla okamžitá. Kdyby se
	počítadlo řídilo klientem, rozešlo by se s realitou při každém zahozeném
	paketu.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Combo = require(Shared.Combo)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Track = require(Shared.Track)
local Zones = require(Shared.Zones)

local CameraFX = require(script:WaitForChild("CameraFX"))
local CharacterFX = require(script:WaitForChild("CharacterFX"))
local CosmeticFX = require(script:WaitForChild("CosmeticFX"))
local Effects = require(script:WaitForChild("Effects"))
local Milestone = require(script:WaitForChild("Milestone"))
local Onboarding = require(script:WaitForChild("Onboarding"))
local Pads = require(script:WaitForChild("Pads"))
local Held = require(script:WaitForChild("Held"))
local SoundKit = require(script:WaitForChild("SoundKit"))
local Squish = require(script:WaitForChild("Squish"))
local Textures = require(script:WaitForChild("Textures"))
local TrackView = require(script:WaitForChild("TrackView"))

local UI = script:WaitForChild("UI")
local HUD = require(UI.HUD)
local Layout = require(UI.Layout)
local Preview = require(UI.Preview)
local Notifications = require(UI.Notifications)
local Panels = require(UI.Panels)
local Welcome = require(UI.Welcome)

local player = Players.LocalPlayer

-- Rozhraní --------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "PowerSmash"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

-- Rozvržení se musí spočítat dřív, než UI vznikne
Layout.start()

local hud = HUD.new(screen)
local panels = Panels.new(screen)
local toasts = Notifications.new(screen)
local milestones = Milestone.new(screen)
local track = TrackView.new()

-- Stav -------------------------------------------------------------------------

local profile = nil
local shownWorld = 0
-- Poslední stupeň comba; slouží k tomu, aby zvuk hrál jen při přeskočení
local comboTier = 1
-- Kdy vyprší nálet. Klient si ho hlídá sám, aby po jeho konci
-- nepočítal s vyšší rychlostí, než jakou server dovolí.
local surgeEndsAt = 0
local settings = { Music = true, Sfx = true, HideUi = false, LowGraphics = false }
-- Rozdíl mezi serverovým a lokálním časem, aby odpočty tikaly správně
local timeOffset = 0

local applyWorldAtmosphere

--[[
	Nastavení se aplikuje lokálně hned a na server jde jen k uložení.
	Čekat na potvrzení by u přepínače působilo rozbitě.
]]
local function applySettings(incoming, send: boolean)
	for key, value in incoming do
		if typeof(value) == "boolean" then
			settings[key] = value
		end
	end

	SoundKit.setEnabled(settings.Sfx)
	SoundKit.setMusic(settings.Music)
	Effects.setLowGraphics(settings.LowGraphics)
	Held.setLowGraphics(settings.LowGraphics)
	CosmeticFX.setLowGraphics(settings.LowGraphics)
	Textures.setLowGraphics(settings.LowGraphics)
	Squish.setEnabled(not settings.LowGraphics)
	hud:setHidden(settings.HideUi)

	if send then
		Remotes.SaveSettings:FireServer(settings)
	end
end

local function applyProfile(incoming)
	if not incoming then
		return
	end

	profile = incoming
	timeOffset = (incoming.ServerTime or os.time()) - os.time()

	hud:setProfile(profile)
	panels:setProfile(profile)
	track:setProfile(profile)
	Pads.setProfile(profile)

	if incoming.Settings then
		applySettings(incoming.Settings, false)
	end
	Held.setHeld(incoming.Held or {})
	Onboarding.update(profile)

	if incoming.WorldIndex ~= shownWorld then
		shownWorld = incoming.WorldIndex
		applyWorldAtmosphere(incoming.WorldIndex)

		local world = Config.Worlds[incoming.WorldIndex]
		if world then
			CharacterFX.setWorldColor(world.Accent)
		end
	end
end

local function serverNow(): number
	return os.time() + timeOffset
end

-- Atmosféra podle světa ----------------------------------------------------------
-- Světy stojí vedle sebe v jednom místě, takže mlhu nejde nastavit
-- serverem pro každý zvlášť — musí ji přepínat klient.

--[[
	Přebarvení scény podle světa.

	Jede se to tweenem, ne skokem. Přechod mezi světy je jediná chvíle,
	kdy se hráči změní celý obraz naráz — skokové přebarvení působí jako
	záseknutí, půlvteřinový přeliv jako přechod někam jinam.

	Barva oblohy se odvozuje z mlhy, ne z barvy světa: obloha je za mlhou
	a musí do ní zapadnout, jinak je na horizontu vidět ostrý šev.
]]
local ATMOSPHERE_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function applyWorldAtmosphere(worldIndex: number)
	local world = Config.Worlds[worldIndex]
	if not world then
		return
	end

	--[[
		Mlha až daleko. Dřív končila na 320 studech, což je uprostřed
		trati — hráč viděl do šedi a zeď na konci se ztrácela. Populární
		hry v žánru mlhu skoro nemají: chodba má být vidět celá.
	]]
	TweenService:Create(Lighting, ATMOSPHERE_TWEEN, {
		FogColor = world.Fog,
		FogStart = 220,
		FogEnd = 1100,
	}):Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, ATMOSPHERE_TWEEN, {
			Color = world.Color:Lerp(Color3.new(1, 1, 1), 0.35),
			Decay = world.Fog,
		}):Play()
	end

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		-- Sky nejde tweenovat plynule přes barvy hvězd, ale skok je tady
		-- neviditelný: hvězdy jsou za mlhou, mění se jen jejich odstín.
		sky.StarCount = if settings.LowGraphics then 0 else 3000
	end

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Enabled = not settings.LowGraphics
	end

	-- Zvuk se přebarví spolu se světem: stejné vzorky, jiný dozvuk a ekvalizér
	SoundKit.setWorld(world.Id)
end

-- Akce z UI ------------------------------------------------------------------------

local function invoke(remoteName: string)
	return function(value: string)
		local ok, result = pcall(function()
			return (Remotes :: any)[remoteName]:InvokeServer(value)
		end)

		if not ok then
			toasts:push("Server did not respond, try again.", "error")
			return
		end

		if result and result.Ok == false and result.Message then
			toasts:push(result.Message, "warn")
		elseif result and result.Ok then
			SoundKit.playNamed("Purchase")
		end
	end
end

panels.Callbacks.BuyUpgrade = invoke("BuyUpgrade")
panels.Callbacks.BuyWorld = invoke("BuyWorld")
panels.Callbacks.EquipTitle = invoke("EquipTitle")

-- Kus se posílá jako "druh:id" v jednom řetězci, protože `row` umí předat
-- jen jednu hodnotu. Rozbalí se hned tady, server dostane tabulku.
panels.Callbacks.EquipCosmetic = function(value: string)
	local kind, id = string.match(value, "^(%w+):(.+)$")
	if not kind or not id then
		return
	end

	task.spawn(function()
		local ok = pcall(function()
			return Remotes.EquipCosmetic:InvokeServer({ Kind = kind, Id = id })
		end)

		if ok then
			SoundKit.playNamed("Click")
		end
	end)
end
panels.Callbacks.DoRebirth = invoke("DoRebirth")
panels.Callbacks.BuyPerk = invoke("BuyPerk")
panels.Callbacks.ExchangeGems = invoke("ExchangeGems")
panels.Callbacks.BuyBoost = invoke("BuyBoost")

panels.Callbacks.ClaimDaily = invoke("ClaimDaily")
panels.Callbacks.ClaimQuest = invoke("ClaimQuest")
panels.Callbacks.RedeemCode = invoke("RedeemCode")
panels.Callbacks.BuySquishy = invoke("BuySquishy")
panels.Callbacks.HoldSquishy = invoke("HoldSquishy")

-- Obchod jede po jednosměrných událostech: server na každou změnu stejně
-- pošle celý nový stav, takže na odpověď není co čekat.
panels.Callbacks.TradeRequest = function(userId: string)
	local id = tonumber(userId)
	if id then
		Remotes.TradeRequest:FireServer(id)
	end
end

panels.Callbacks.TradeRespond = function(answer: string)
	Remotes.TradeRespond:FireServer(answer == "yes")
end

panels.Callbacks.TradeAdd = function(petId: string)
	Remotes.TradeOffer:FireServer(petId, true)
end

panels.Callbacks.TradeRemove = function(petId: string)
	Remotes.TradeOffer:FireServer(petId, false)
end

panels.Callbacks.TradeConfirm = function()
	Remotes.TradeConfirm:FireServer()
end

panels.Callbacks.TradeCancel = function()
	Remotes.TradeCancel:FireServer()
end

panels.Callbacks.PromptPass = function(id: string)
	Remotes.PromptPass:FireServer(id)
end

panels.Callbacks.PromptProduct = function(id: string)
	Remotes.PromptProduct:FireServer(id)
end

panels.Callbacks.ToggleSetting = function(key: string)
	applySettings({ [key] = not settings[key] }, true)

	if profile then
		profile.Settings = table.clone(settings)
		panels:setProfile(profile)
	end
end

panels.Callbacks.EnterWorld = function(value: string)
	local index = tonumber(value)
	if not index then
		return
	end

	local ok, result = pcall(function()
		return Remotes.EnterWorld:InvokeServer(index)
	end)

	if ok and result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	end
end

--[[
	Seznam hráčů se natahuje až při otevření záložky. Posílat ho průběžně
	by znamenalo provoz kvůli obrazovce, kterou většina hráčů neotevře.
]]
local function refreshTradeCandidates()
	task.spawn(function()
		local ok, list = pcall(function()
			return Remotes.TradeCandidates:InvokeServer()
		end)
		if ok and list then
			panels:setCandidates(list)
		end
	end)
end

hud.OnAction = function(kind: string)
	SoundKit.playNamed("Click")

	if kind == "trade" then
		refreshTradeCandidates()
	end

	if kind == "chest" then
		local ok, result = pcall(function()
			return Remotes.ClaimChest:InvokeServer()
		end)
		if ok and result and result.Ok == false and result.Message then
			toasts:push(result.Message, "warn")
		end
		return
	end

	--[[
		Pozvánka není panel, ale systémové okno Robloxu. Musí se spustit
		z klienta a jen z gesta hráče — server ho vyvolat nemůže.

		`CanSendGameInviteAsync` se ptá, jestli to hráč vůbec smí
		(rodičovské nastavení, věk, platforma). Bez toho by se části
		hráčů tlačítko tvářilo jako rozbité: klepnou a nestane se nic.
	]]
	if kind == "invite" then
		task.spawn(function()
			local allowed, canInvite = pcall(function()
				return SocialService:CanSendGameInviteAsync(player)
			end)

			if not allowed or not canInvite then
				toasts:push("Invites are not available on this account.", "warn")
				return
			end

			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end)
		return
	end

	panels:open(kind)
end

--[[
	Nákup vylepšení. Volá to tlačítko v HUD i deska na trati, takže
	odpověď musí vypadat stejně z obou stran — hráč nemá poznat, kudy
	nákup šel.
]]
local function buyUpgrade(id: string)

	local ok, result = pcall(function()
		return Remotes.BuyUpgrade:InvokeServer(id)
	end)

	if not ok then
		toasts:push("Server did not respond, try again.", "error")
	elseif result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	else
		SoundKit.playNamed("Purchase")
	end
end

hud.OnQuickBuy = function(id: string)
	SoundKit.playNamed("Click")
	buyUpgrade(id)
end

Pads.setBuy(buyUpgrade)

--[[
	Portál na konci trati: nevlastněný svět koupí, vlastněný do sebe
	pustí. Obojí potvrzuje server — klient jen ví, co se má zeptat.
]]
Pads.setWorld(function(id: string, owned: boolean)
	--[[
		`BuyWorld` chce id, `EnterWorld` index. Není to hezké, ale je to
		to, co server opravdu čeká — a poslat mu druhý tvar znamená
		odmítnutí, které by hráč viděl jako nefunkční bránu.
	]]
	local ok, result = pcall(function()
		if owned then
			return Remotes.EnterWorld:InvokeServer(Config.worldIndex(id))
		end
		return Remotes.BuyWorld:InvokeServer(id)
	end)

	if not ok then
		toasts:push("Server did not respond, try again.", "error")
	elseif result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	else
		SoundKit.playNamed(if owned then "Ready" else "Purchase")
	end
end)

hud.OnBuyBoost = function(id: string)
	local ok, result = pcall(function()
		return Remotes.BuyBoost:InvokeServer(id)
	end)

	if ok and result and result.Ok == false and result.Message then
		toasts:push(result.Message, "warn")
	elseif ok and result and result.Ok then
		SoundKit.playNamed("Purchase")
	end
end

-- Klávesové zkratky -----------------------------------------------------------------

local SHORTCUTS = {
	[Enum.KeyCode.One] = "upgrades",
	[Enum.KeyCode.Two] = "worlds",
	[Enum.KeyCode.Three] = "titles",
	[Enum.KeyCode.Four] = "rebirth",
	[Enum.KeyCode.Five] = "squishies",
}

--[[
	Čím se mačká.

	Klik, dotyk i klávesa naráz, protože hra běží na počítači i na
	telefonu a mačkání musí jít všude stejně snadno. `E` je tam pro ty,
	kdo chtějí mačkat a zároveň se rozhlížet myší.
]]
local SQUEEZE = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if SQUEEZE[input.UserInputType] or input.KeyCode == Enum.KeyCode.E then
		Held.squeeze()
		return
	end

	local target = SHORTCUTS[input.KeyCode]
	if target then
		panels:open(target)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		panels:close()
	end
end)

-- Události ze serveru -------------------------------------------------------------------

Remotes.ProfileChanged.OnClientEvent:Connect(applyProfile)

Remotes.PowerChanged.OnClientEvent:Connect(function(payload)
	if profile then
		profile.Power = payload.Power
	end

	hud:setPower(payload.Power)
	track:setPower(payload.Power)

	if payload.Source == "collect" then
		hud:pulsePower()
	elseif payload.Source == "squeeze" then
		--[[
			Záblesk u hračky se pouští až podle serveru, ne rovnou při
			stisku. Klient nemá jak vědět, jestli se zmáčknutí vešlo do
			limitu — a odměna u stisku, který se zahodil, je lež.
		]]
		Held.reward(payload.Gained or 0)
		hud:pulsePower()
	end

	if payload.Goldens and payload.Goldens > 0 then
		toasts:push(`GOLDEN ×{Config.Track.GoldenValue}!  +{Format.short(payload.Gained)} power`, "success")
		CameraFX.flash(0.5, Config.Theme.Gold)
	elseif payload.Crits and payload.Crits > 0 then
		toasts:push(`LUCKY ×5!  +{Format.short(payload.Gained)} power`, "success")
	end

	--[[
		Řetěz posílá server, klient si ho nedopočítává. Kdyby si ho počítal
		sám, ukazoval by po zahozeném pickupu vyšší násobič, než jaký se
		opravdu započítá — a hráč by měl pocit, že ho hra okrádá.
	]]
	if payload.Combo ~= nil then
		track:setChain(payload.Combo)
		local tier = hud:setCombo(payload.Combo, os.clock(), payload.Window)

		-- Zvuk i kamera reagují na PŘESKOČENÍ stupně, ne na každý článek.
		-- Hudba se nabudí podle řetězu: rozjeté combo je pak slyšet
		-- i v podkladu, ne jen v jednorázových zvucích.
		SoundKit.setMusicSwell(payload.Combo / Combo.Max)

		if tier ~= comboTier then
			-- Širší záběr při vyšším stupni: rychlost je pak vidět, ne jen slyšet.
			CameraFX.setFovBonus((tier - 1) * 1.8)
			-- A celá trať se rozjede s tebou: pruhy tečou rychleji a zjasní se.
			Textures.setIntensity(1 + (tier - 1) * 0.4)

			if tier > comboTier and payload.Combo > 0 then
				SoundKit.playNamed("Unlock", { Pitch = 0.9 + tier * 0.12 })
				CameraFX.kick(0.35 + tier * 0.12, 0)
			end

			comboTier = tier
		end
	end
end)

Remotes.SmashEffect.OnClientEvent:Connect(function(payload)
	local isLocal = payload.UserId == player.UserId

	if isLocal then
		--[[
			Nálet vyhlásil server. Klient si jen zapíše, kdy skončí, aby
			uměl dopočítat rychlost (viz setWalkSpeedSource) a rozsvítit
			ukazatel — hodnotu samotnou si nevymýšlí.
		]]
		if payload.Surge then
			surgeEndsAt = serverNow() + Config.Track.SurgeSeconds
			hud:setSurge(surgeEndsAt, Config.Track.SurgeSeconds)
			CameraFX.kick(0.6, 0)
			SoundKit.playNamed("Ready", { Pitch = 1.5 })
		end

		track:breakBarrier(payload.Barrier, payload)
		return
	end

	-- Průraz jiného hráče: efekt na správném místě, ale tišší
	if profile and payload.WorldIndex == profile.WorldIndex then
		local world = Config.Worlds[payload.WorldIndex]
		local position = Track.barrierPosition(payload.WorldIndex, payload.Barrier) + Vector3.new(0, 8, 0)
		-- Otřes projde i hračkou v ruce; nehybná by při průrazu vypadala
		-- jako přilepený kus plastu
		Held.nudge(0.55)

		Effects.smash({
			CFrame = CFrame.new(position),
			Size = Vector3.new(Config.Track.Width, 28, 3.2),
			World = world,
			Payload = payload,
			IsLocal = false,
			Zone = Zones.at(payload.Barrier).Sound,
		})
	end
end)

Remotes.WorldChanged.OnClientEvent:Connect(function(worldIndex)
	applyWorldAtmosphere(worldIndex)
	local world = Config.Worlds[worldIndex]
	if world then
		toasts:push(`Entered {world.Name} — power reset to 0.`, "info")
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(payload)
	toasts:push(payload.Text, payload.Kind)

	if payload.Sound then
		SoundKit.playNamed(payload.Sound)
	end
end)

Remotes.RetentionChanged.OnClientEvent:Connect(function(snapshot)
	panels:setRetention(snapshot)

	-- Odznaky: co čeká na vyzvednutí
	local questReady = false
	for _, quest in snapshot.Quests or {} do
		if not quest.Claimed and quest.Progress >= quest.Target then
			questReady = true
			break
		end
	end

	hud:setBadges({
		daily = (snapshot.Daily and not snapshot.Daily.Claimed) or questReady,
	})
end)

--[[
	Velké okamžiky celého serveru. Vlastní dostane obřad, cizí proužek
	ve výpisu — v tomhle žánru je postup ostatních hlavní důvod, proč
	hráč pokračuje.
]]
Remotes.Milestone.OnClientEvent:Connect(function(payload)
	milestones:play(payload)
end)

Remotes.TradeChanged.OnClientEvent:Connect(function(state)
	panels:setTrade(state)
end)

Remotes.TradeInvite.OnClientEvent:Connect(function(invite)
	panels:setInvite(invite)
	SoundKit.playNamed("Ready")
	toasts:push(`{invite.Name} wants to trade — open the Trade tab.`, "info")
end)

Remotes.GiantWall.OnClientEvent:Connect(function(state)
	hud:setEvent(state)
end)

Remotes.PassesChanged.OnClientEvent:Connect(function(payload)
	if payload.Offers then
		panels:setOffers(payload.Offers)
	end
end)

--[[
	Návrat hráče je nejcennější okamžik v celé hře — Roblox od konce
	roku 2025 řadí hry hlavně podle něj. Do teď na něj připadal jeden
	toast v rohu, který zmizel dřív, než ho hráč dočetl.

	Karta místo něj pojmenuje, co na hráče čekalo, a pošle ho rovnou
	do denní odměny: právě ta vyrábí návraty další dny a hráč, který ji
	po přihlášení nevidí, si ji nevybere.
]]
Remotes.OfflineReward.OnClientEvent:Connect(function(payload)
	Welcome.show(screen, payload, function()
		panels:open("daily")
	end)
end)

-- Postava -------------------------------------------------------------------------------

local function bindCharacter(model: Model)
	local world = Config.Worlds[shownWorld] or Config.Worlds[1]
	CharacterFX.bind(model, world.Accent)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- Start -----------------------------------------------------------------------------

--[[
	Hitstop musí umět rychlost obnovit na tu, kterou povolil server —
	ne na tu, kterou si zapamatoval. Kdyby si ji pamatoval sám, po koupi
	Speed upgradu během zaseknutí by hráče zpomalil zpátky.
]]
Effects.setWalkSpeedSource(function(): number
	if not profile then
		return 16
	end
	-- Počítá se ze stejného vzorce jako na serveru, ne z posledního
	-- poslaného čísla: to by po doběhu náletu zůstalo o třetinu vyšší.
	return Economy.walkSpeed(profile, surgeEndsAt, serverNow())
end)

track:start()
Squish.start()
SoundKit.startMusic()
Textures.start()
CharacterFX.start()
CosmeticFX.start()
CameraFX.start()
Held.start()
Pads.start()
Preview.start()

task.spawn(function()
	-- Pojistka, kdyby se klient načetl dřív, než server stihl push poslat
	local ok, result = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)

	if ok and result and not profile then
		applyProfile(result)
	end

	-- Nápověda jen pro úplně nového hráče; existujícího by jen otravovala
	if profile then
		Onboarding.start(screen, profile)
		Onboarding.update(profile)
	end
end)

-- Lišta comba ubývá plynule, takže musí tikat každý snímek, ne po sekundě
RunService.RenderStepped:Connect(function()
	hud:tickSurge(serverNow())

	if hud:tickCombo(os.clock()) then
		-- Řetěz spadl: záběr zpátky na normál, žádný zvuk (nic se nestalo,
		-- hráč jen přestal sbírat — trestat ho fanfárou nemá smysl).
		comboTier = 1
		CameraFX.setFovBonus(0)
		Textures.setIntensity(1)
		SoundKit.setMusicSwell(0)
	end
end)

-- Odpočty boostů a truhly tikají lokálně
task.spawn(function()
	while true do
		task.wait(1)
		if profile then
			hud:refreshTimers(serverNow())
		end
	end
end)

toasts:push("Collect +1 pickups, then run into the wall to smash it!", "info")
