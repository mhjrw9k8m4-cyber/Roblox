--!strict
--[[
	Held — squishy hračka v ruce.

	Tohle je ta věc, kterou hráč vidí celou dobu uprostřed obrazu.
	Hračka je v ruce a dá se s ní mačkat, takže je součástí hraní,
	ne řádkem ve statistice.

	Modul dělá tři věci:

	  1. **Drží** hračku v pravé ruce (a další na pásku) svarem, takže
	     jede s animací postavy, ne vedle ní.
	  2. **Mačká** ji — pomalý návrat přes `Squish`, k tomu zvuk a
	     zmenšení postavy o kousek, aby to vypadalo jako pohyb celého
	     těla a ne jen dílu.
	  3. **Dýchá** — i když se nic neděje, hračka se sotva znatelně
	     nafukuje. Nehybný díl v ruce vypadá jako chyba vykreslování.

	Vlastní hodnotu zmáčknutí modul nepočítá. Klient jen řekne serveru
	"zmáčkl jsem" a Power přijde zpátky — cokoliv jiného by byl
	nejlevnější exploit ve hře.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(Shared.Build)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)

local Squish = require(script.Parent.Squish)
local SoundKit = require(script.Parent.SoundKit)

local player = Players.LocalPlayer

local Held = {}

local parts: { BasePart } = {}
local heldIds: { string } = {}
local elapsed = 0
local lowGraphics = false
local lastSqueezeAt = 0
local squeezeCount = 0

--[[
	Nejrychlejší tempo, které klient pustí dál. Server má vlastní strop
	(`Live.SqueezeRate`); tenhle je o kousek volnější schválně — hráč
	nemá vidět, že mu hra zahazuje stisky, jen že rychlejší mačkání už
	nic nepřidá.
]]
local MIN_GAP = 1 / (Live.SqueezeRate + 2)

local function shapeOf(shape: string): Enum.PartType
	if shape == "Ball" then
		return Enum.PartType.Ball
	elseif shape == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return Enum.PartType.Block
end

--[[
	Kam který kus patří.

	Slot 1 je ruka. Zbytek visí u pasu po stranách — hráč tak vidí, že
	má u sebe víc věcí, ale pořád je jasné, se kterou se dá mačkat.
]]
local function mountFor(character: Model, slot: number): (BasePart?, CFrame)
	if slot == 1 then
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if hand then
			return hand :: BasePart, CFrame.new(0, -1.1, -0.2)
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, CFrame.identity
	end

	-- Sudé doprava, liché doleva, každé další o kousek dozadu
	local side = if slot % 2 == 0 then 1 else -1
	local depth = math.floor((slot - 2) / 2) * 0.5
	return root :: BasePart, CFrame.new(side * 1.4, -0.6, 0.5 + depth)
end

local function clear()
	for _, part in parts do
		part:Destroy()
	end
	table.clear(parts)
end

function Held.clear()
	clear()
	table.clear(heldIds)
end

--[[
	Postaví hračky na postavě. Volá se při každé změně držení i po
	respawnu — porovnávat, co přesně se změnilo, by se u tří dílů
	nevyplatilo.
]]
function Held.rebuild()
	clear()

	if lowGraphics then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	for slot, id in heldIds do
		local squishy = Live.squishy(id)
		if not squishy then
			continue
		end

		local mount, offset = mountFor(character, slot)
		if not mount then
			continue
		end

		local size = if slot == 1 then 1.5 else 0.9
		local part = Build.part({
			Name = `Squishy{slot}`,
			Shape = shapeOf(squishy.Shape),
			Size = Vector3.new(size, size, size),
			Position = mount.Position,
			Color = squishy.Color,
			--[[
				Plast, ne Neon. Squishy hračka je matná guma; Neon by
				z ní udělal svítící kouli a celý ten měkký dojem, kvůli
				kterému tu je, by byl pryč.
			]]
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.08,
			CanCollide = false,
			CastShadow = false,
			Anchored = false,
			Parent = character,
		})

		local weld = Instance.new("Weld")
		weld.Part0 = mount
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part

		table.insert(parts, part)
	end
end

function Held.setHeld(ids: { string })
	heldIds = table.clone(ids)
	Held.rebuild()
end

function Held.setLowGraphics(enabled: boolean)
	lowGraphics = enabled
	if enabled then
		clear()
	else
		Held.rebuild()
	end
end

--[[
	Zmáčknutí.

	Hloubka i doba návratu jdou z `Softness` hračky: měkká se propadne
	skoro celá a vrací se dlouho, tvrdá jen cvakne. Právě ten pomalý
	návrat je to, co dělá squishy hračku squishy — ne zvuk.
]]
function Held.squeeze()
	local now = os.clock()
	if now - lastSqueezeAt < MIN_GAP then
		return
	end
	lastSqueezeAt = now

	local part = parts[1]
	local id = heldIds[1]
	local squishy = if id then Live.squishy(id) else nil
	if not part or not squishy then
		return
	end

	squeezeCount += 1

	Squish.rebase(part)
	Squish.press(part, 0.35 + squishy.Softness * 0.5, 0.25 + squishy.Softness * 0.55)

	--[[
		Výška tónu stoupá se sérií a po pauze spadne zpátky. Stejný trik
		jako u sbírání: mozek to slyší jako postup, i když je to pořád
		ten samý vzorek.
	]]
	local step = math.min(squeezeCount, 12)
	SoundKit.playNamed("Pickup", {
		Position = part.Position,
		Pitch = 0.8 + step * 0.045 + (1 - squishy.Softness) * 0.4,
		Volume = 0.5,
	})

	Remotes.Squeeze:FireServer()
end

--[[
	Zmáčkne hračku "zvenčí" — nárazem, dopadem, průrazem zdi.

	Hračka v ruce, která reaguje jen na klikání, působí jako přilepený
	kus. Když se zmáčkne i při dopadu na zem a při proražení zdi, čte to
	oko jako měkkou hmotu, která tam opravdu je. Serveru se nic neposílá:
	tohle je čistě to, jak to vypadá, ne příjem.
]]
function Held.nudge(strength: number)
	local part = parts[1]
	local id = heldIds[1]
	local squishy = if id then Live.squishy(id) else nil
	if not part or not squishy then
		return
	end

	Squish.rebase(part)
	Squish.press(part, math.clamp(strength, 0.1, 0.7) * squishy.Softness, 0.3 + squishy.Softness * 0.4)
end

--[[
	Krátký záblesk u hračky, když zmáčknutí něco přineslo. Server
	potvrzuje Power zvlášť, takže se tohle pouští až podle něj — jinak
	by hráč viděl odměnu i u stisků, které se zahodily.
]]
function Held.reward(amount: number)
	local part = parts[1]
	if not part or lowGraphics or amount <= 0 then
		return
	end

	local spark = Instance.new("Attachment")
	spark.Parent = part

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(part.Color)
	burst.LightEmission = 0.6
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.2, 0.45)
	burst.Speed = NumberRange.new(4, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Parent = spark
	burst:Emit(6)

	Debris:AddItem(spark, 0.6)
end

--[[
	Dýchání. Rozsah je schválně na hranici viditelnosti — jakmile je
	nafukování vidět jako animace, přestane to působit jako hmota
	a začne to působit jako efekt.

	Nesahá se na díl, který zrovna drží `Squish`: ten si velikost
	přepisuje sám a dvě věci najednou by ho nechaly natrvalo zmenšený.
]]
function Held.start()
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		-- Série se po pauze rozpadne, aby tón začínal zase dole
		if os.clock() - lastSqueezeAt > 1.2 then
			squeezeCount = 0
		end

		if #parts == 0 or lowGraphics then
			return
		end

		for index, part in parts do
			if not part.Parent or Squish.isPressed(part) then
				continue
			end

			local breath = 1 + math.sin(elapsed * 1.8 + index) * 0.03
			local base = if index == 1 then 1.5 else 0.9
			part.Size = Vector3.new(base * breath, base / breath, base * breath)
		end
	end)

	--[[
		Respawn: postava je nová, svary staré. Bez tohohle by hráč po
		smrti chodil s prázdnou rukou až do další změny držení.
	]]
	player.CharacterAdded:Connect(function()
		task.wait(0.4)
		Held.rebuild()
	end)
end

return Held
