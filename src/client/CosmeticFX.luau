--!strict
--[[
	CosmeticFX — vykreslení stop a aur na VŠECH hráčích.

	Proč zvlášť od `CharacterFX`: ten řeší jen tvoji postavu (pózy, náklon,
	kamera). Kosmetika má smysl hlavně na ostatních — ukazuje se jí, co má
	kdo odehrané, takže ji musí vidět celý server.

	Nasazený kus se čte z atributu na `Player`. Atribut doteče sám i k tomu,
	kdo se připojil až potom, takže se nikde neřeší dohánění stavu.

	Pohyb textur (co jsi chtěl): u stop s `Cycle` se za běhu posouvá barevný
	přechod po pásu, takže barvy po stopě putují místo aby stály. U aur
	s `Orbit` obíhá samotný emitor kolem těla, takže částice nevznikají
	pořád na stejném místě.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)

local CosmeticFX = {}

type Live = {
	Skinned: { [BasePart]: { Color: Color3, Material: Enum.Material, Reflectance: number, Transparency: number } }?,
	Outline: Highlight?,
	Trail: Trail?,
	Cycle: number?,
	Colors: { Color3 }?,
	Emitter: ParticleEmitter?,
	Orbit: number?,
	Radius: number?,
	Pivot: Attachment?,
}

local live: { [Player]: Live } = {}
local lowGraphics = false
local elapsed = 0

local function stateFor(player: Player): Live
	local existing = live[player]
	if existing then
		return existing
	end

	local fresh: Live = {}
	live[player] = fresh
	return fresh
end

local function clearFor(player: Player)
	local state = live[player]
	if not state then
		return
	end

	if state.Trail then
		state.Trail:Destroy()
	end
	if state.Emitter then
		state.Emitter:Destroy()
	end
	if state.Pivot then
		state.Pivot:Destroy()
	end
	if state.Outline then
		state.Outline:Destroy()
	end

	-- Skin se maže vrácením původních hodnot, ne zničením instance:
	-- části postavy patří Robloxu, my jsme si je jen půjčili.
	restoreSkin(state)

	live[player] = nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--[[
	Barvy rozprostřené po pásu. `offset` posune celý přechod dokola,
	čímž vzniká putování barev.
]]
local function sequence(colors: { Color3 }, offset: number): ColorSequence
	local count = #colors
	if count == 1 then
		return ColorSequence.new(colors[1])
	end

	local keypoints = {}
	-- ColorSequence musí mít krajní body přesně na 0 a 1, a mezi nimi
	-- ostře rostoucí čas — proto se posun počítá do indexu barvy,
	-- ne do pozice klíčového bodu.
	local shift = math.floor(offset * count)

	for index = 1, count do
		local position = (index - 1) / (count - 1)
		local pick = ((index - 1 + shift) % count) + 1
		table.insert(keypoints, ColorSequenceKeypoint.new(position, colors[pick]))
	end

	return ColorSequence.new(keypoints)
end

-- Stopa ----------------------------------------------------------------------

local function buildTrail(player: Player, look: Cosmetics.TrailLook)
	local root = rootOf(player)
	if not root then
		return
	end

	local state = stateFor(player)

	local top = Instance.new("Attachment")
	top.Name = "CosTrailTop"
	top.Position = Vector3.new(0, look.Width, 0.5)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = "CosTrailBottom"
	bottom.Position = Vector3.new(0, -look.Width, 0.5)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "CosTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = sequence(look.Colors, 0)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, look.Alpha),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = look.Lifetime
	trail.LightEmission = look.Light
	trail.MinLength = 0.15
	trail.FaceCamera = true
	trail.Parent = root

	state.Trail = trail
	state.Cycle = look.Cycle
	state.Colors = look.Colors
end

-- Aura -----------------------------------------------------------------------

local function buildAura(player: Player, look: Cosmetics.AuraLook)
	local root = rootOf(player)
	if not root then
		return
	end

	local state = stateFor(player)

	local pivot = Instance.new("Attachment")
	pivot.Name = "CosAura"
	pivot.Position = Vector3.new(look.Radius, 0, 0)
	pivot.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CosAuraEmitter"
	emitter.Color = sequence(look.Colors, 0)
	emitter.LightEmission = 0.85
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, look.Size[1]),
		NumberSequenceKeypoint.new(0.5, (look.Size[1] + look.Size[2]) / 2),
		NumberSequenceKeypoint.new(1, look.Size[2]),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.7, 1.6)
	emitter.Speed = NumberRange.new(look.Speed[1], look.Speed[2])
	emitter.SpreadAngle = Vector2.new(look.Spread, look.Spread)
	emitter.Acceleration = Vector3.new(0, look.Rise, 0)
	emitter.Drag = look.Drag
	emitter.RotSpeed = NumberRange.new(-look.Spin, look.Spin)
	emitter.Rate = look.Rate
	emitter.Parent = pivot

	if look.Glow then
		local light = Instance.new("PointLight")
		light.Name = "CosGlow"
		light.Color = look.Colors[1]
		light.Brightness = look.Glow
		light.Range = 10 + look.Glow * 3
		light.Shadows = false
		light.Parent = pivot
	end

	state.Emitter = emitter
	state.Pivot = pivot
	state.Orbit = look.Orbit
	state.Radius = look.Radius
end

-- Skin -----------------------------------------------------------------------

--[[
	Části, které se přebarvují. Hlava a torzo dostanou hlavní barvu,
	končetiny doplňkovou — jinak by postava byla jednolitá skvrna.

	Nesahá se na příslušenství ani na obličej: ty patří hráči, ne hře.
]]
local function isBody(part: BasePart): boolean
	if part:FindFirstAncestorOfClass("Accessory") then
		return false
	end
	return part.Name ~= "HumanoidRootPart"
end

local function isTorso(part: BasePart): boolean
	local name = part.Name
	return name == "Head" or name == "Torso" or name == "UpperTorso" or name == "LowerTorso"
end

local function buildSkin(player: Player, look: Cosmetics.SkinLook)
	local character = player.Character
	if not character then
		return
	end

	local state = stateFor(player)
	local previous = {}

	--[[
		Materiál je v datech jméno, ne enum — sdílený modul čte i server.
		Neznámé jméno se tiše přeskočí místo pádu: rozbitý zápis v datech
		nesmí shodit vykreslování celé postavy.
	]]
	local material = (Enum.Material :: any)[look.Material]

	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") or not isBody(part) then
			continue
		end

		previous[part] = {
			Color = part.Color,
			Material = part.Material,
			Reflectance = part.Reflectance,
			Transparency = part.Transparency,
		}

		part.Color = if isTorso(part) then look.Body else look.Limbs
		part.Reflectance = look.Reflectance
		part.Transparency = look.Transparency
		if material then
			part.Material = material
		end
	end

	state.Skinned = previous

	if look.Glow then
		--[[
			Highlight, ne SurfaceLight: obrys je vidět i skrz zeď a nestojí
			nic navíc na výkonu. U skoro průhledného těla je to jediné,
			podle čeho postavu poznáš.
		]]
		local outline = Instance.new("Highlight")
		outline.Name = "CosSkinGlow"
		outline.FillTransparency = 1
		outline.OutlineColor = look.Limbs
		outline.OutlineTransparency = math.clamp(1 - look.Glow, 0, 0.9)
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Adornee = character
		outline.Parent = character

		state.Outline = outline
	end
end

local function restoreSkin(state: Live)
	for part, saved in state.Skinned or {} do
		if part.Parent then
			part.Color = saved.Color
			part.Material = saved.Material
			part.Reflectance = saved.Reflectance
			part.Transparency = saved.Transparency
		end
	end
	state.Skinned = nil
end

-- Nasazení -------------------------------------------------------------------

local function refresh(player: Player)
	clearFor(player)

	if not rootOf(player) then
		return
	end

	--[[
		Skin se kreslí i v nízké grafice. Nestojí nic — jen přebarví
		části, které na obrazovce stejně jsou. Vypínají se stopy a aury,
		tedy emitory a světla, protože tam jde výkon doopravdy.
	]]
	local skinId = player:GetAttribute("CosmeticSkin")
	if typeof(skinId) == "string" then
		local item = Cosmetics.get("skin", skinId)
		if item and item.Skin then
			buildSkin(player, item.Skin)
		end
	end

	if lowGraphics then
		return
	end

	local trailId = player:GetAttribute("CosmeticTrail")
	if typeof(trailId) == "string" then
		local item = Cosmetics.get("trail", trailId)
		if item and item.Trail then
			buildTrail(player, item.Trail)
		end
	end

	local auraId = player:GetAttribute("CosmeticAura")
	if typeof(auraId) == "string" then
		local item = Cosmetics.get("aura", auraId)
		if item and item.Aura then
			buildAura(player, item.Aura)
		end
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("CosmeticTrail"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("CosmeticAura"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("CosmeticSkin"):Connect(function()
		refresh(player)
	end)

	player.CharacterAdded:Connect(function(character)
		-- Efekty visí na HumanoidRootPart, který u čerstvé postavy
		-- ještě nemusí existovat.
		character:WaitForChild("HumanoidRootPart", 10)
		refresh(player)
	end)

	player.CharacterRemoving:Connect(function()
		clearFor(player)
	end)

	if player.Character then
		refresh(player)
	end
end

--[[
	Nízká grafika kosmetiku vypne úplně: na slabém telefonu je deset
	emitorů kolem deseti hráčů to první, co sundá snímkovou frekvenci.
]]
function CosmeticFX.setLowGraphics(enabled: boolean)
	if lowGraphics == enabled then
		return
	end

	lowGraphics = enabled

	for _, player in Players:GetPlayers() do
		refresh(player)
	end
end

function CosmeticFX.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearFor)

	RunService.RenderStepped:Connect(function(delta)
		elapsed += delta

		for player, state in live do
			local trail = state.Trail
			if trail and state.Cycle and state.Colors then
				trail.Color = sequence(state.Colors, (elapsed / state.Cycle) % 1)
			end

			local pivot = state.Pivot
			if pivot and state.Orbit and state.Radius then
				local angle = elapsed * state.Orbit * math.pi * 2
				pivot.Position = Vector3.new(
					math.cos(angle) * state.Radius,
					math.sin(angle * 0.5) * 0.8,
					math.sin(angle) * state.Radius
				)
			end
		end
	end)
end

return CosmeticFX
