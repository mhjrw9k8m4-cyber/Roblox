--!strict
--[[
	CameraFX — kamera na pružinách a záblesky obrazu.

	Lineární doběh (odečti kousek každý snímek) vypadá mechanicky. Skutečná
	kamera má hmotnost: vychýlí se, přestřelí zpátky a dohoupe se. Proto
	tady všechno běží na tlumené pružině — jedna rovnice, která tohle
	chování dá zadarmo:

	    zrychlení = -tuhost * výchylka - tlumení * rychlost

	Tuhost říká, jak rychle se to vrací; tlumení, jestli to přestřelí
	(nízké) nebo dosedne bez kmitu (vysoké). Otřes má nízké tlumení,
	protože chceme, aby se rozdrnčel. Zorné pole vysoké, protože kmitající
	FOV je nepříjemný.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraFX = {}

local random = Random.new()

type Spring = {
	Value: number,
	Velocity: number,
	Stiffness: number,
	Damping: number,
}

local function spring(stiffness: number, damping: number): Spring
	return { Value = 0, Velocity = 0, Stiffness = stiffness, Damping = damping }
end

local function step(self: Spring, deltaTime: number)
	local acceleration = -self.Stiffness * self.Value - self.Damping * self.Velocity
	self.Velocity += acceleration * deltaTime
	self.Value += self.Velocity * deltaTime
end

-- Otřes se má rozdrnčet, proto nízké tlumení
local shake = spring(210, 9)
-- Náklon dosedne trochu měkčeji
local roll = spring(120, 11)
-- Zorné pole nesmí kmitat, jinak je z toho nevolno
local fov = spring(90, 16)

local baseFov = 70
-- Trvalé přičtení k zornému poli (combo). Drží se zvlášť od pružiny,
-- aby ho krátký impuls z průrazu nepřepsal.
local fovBonus = 0
local lowGraphics = false

-- Post-processing ------------------------------------------------------------------

local colorCorrection: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil

local function ensureEffects()
	if not colorCorrection then
		colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	end
	if not bloom then
		bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	end
end

--[[
	Záblesk obrazu. Nejde o bílé překrytí — zvedne se jas a bloom, takže
	se rozzáří to, co už na obrazovce svítí. Vypadá to jako výbuch světla,
	ne jako přilepený obdélník.
]]
function CameraFX.flash(strength: number, tint: Color3?)
	if lowGraphics then
		return
	end

	ensureEffects()

	local correction = colorCorrection
	if correction then
		correction.Brightness = 0.12 * strength
		correction.Contrast = 0.15 + 0.2 * strength
		if tint then
			correction.TintColor = tint:Lerp(Color3.new(1, 1, 1), 0.7)
		end

		TweenService:Create(correction, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
			Brightness = 0,
			Contrast = 0.15,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
	end

	local glow = bloom
	if glow then
		glow.Intensity = 1.1 + 1.6 * strength
		TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Intensity = 1.1 }):Play()
	end
end

-- Vybuzení pružin ------------------------------------------------------------------

function CameraFX.shake(strength: number)
	shake.Velocity += strength * 26
end

--[[
	Kop do kamery. `direction` rozhoduje, na kterou stranu se nakloní —
	náraz zprava má naklonit vlevo, jinak to není cítit jako náraz.
]]
function CameraFX.kick(strength: number, direction: number)
	shake.Velocity += strength * 30
	roll.Velocity += strength * direction * 14
	fov.Velocity += strength * 90
end

function CameraFX.setLowGraphics(enabled: boolean)
	lowGraphics = enabled
end

--[[
	Přičtení k zornému poli, které drží, dokud ho někdo nezmění — na rozdíl
	od `kick`, který doznívá. Používá se na combo: čím vyšší stupeň, tím
	širší záběr, takže rychlost je vidět, ne jen slyšet.

	Volající tak nemusí znát výchozí hodnotu; kdyby si ji držel sám,
	rozešla by se s tou, kterou má hráč nastavenou.
]]
function CameraFX.setFovBonus(amount: number)
	fovBonus = math.clamp(amount, -20, 20)
end

--[[
	Aplikace běží až za kamerou (Camera + 1), jinak by si engine výsledek
	hned přepsal vlastním výpočtem.
]]
function CameraFX.start()
	-- Výchozí zorné pole se vezme z kamery, ne z konstanty — jinak by
	-- se hráči, který si ho změnil, po prvním snímku přepsalo.
	local camera = Workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
	end

	RunService:BindToRenderStep("CameraFX", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local clamped = math.min(deltaTime, 1 / 30)
		step(shake, clamped)
		step(roll, clamped)
		step(fov, clamped)

		if math.abs(shake.Value) > 0.0005 then
			local offset = Vector3.new(
				random:NextNumber(-1, 1),
				random:NextNumber(-1, 1),
				random:NextNumber(-0.4, 0.4)
			) * shake.Value * 0.5

			camera.CFrame = camera.CFrame * CFrame.new(offset)
		end

		if math.abs(roll.Value) > 0.0005 then
			camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(roll.Value))
		end

		camera.FieldOfView = baseFov + fovBonus + math.clamp(fov.Value, -12, 18)
	end)
end

return CameraFX
