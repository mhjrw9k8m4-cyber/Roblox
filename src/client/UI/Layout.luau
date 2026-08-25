--!strict
--[[
	Layout — rozvržení pro obrazovky, které nejsou monitor.

	Většina hráčů tohohle žánru sedí na telefonu. Pevné pixelové rozměry
	na monitoru vypadají dobře a na mobilu se rozsypou: sloupce se překryjí,
	okno přeteče přes obrazovku a tlačítka jsou moc malá na prst.

	Modul řeší dvě věci naráz, protože každá potřebuje něco jiného:

	  ŠKÁLOVÁNÍ — na malé obrazovce se UI zmenší, ale jen po hranici, pod
	  kterou by se přestalo dát trefit prstem. Proto se neškáluje lineárně
	  s výškou, ale s omezením zdola.

	  BREAKPOINT — pod určitou šířkou se rozvržení nemění velikostí, ale
	  tvarem: dva sloupce ikon se složí do jednoho, promo sloupec se schová.
	  Zmenšit dvousloupcovou mřížku na polovinu nepomůže, když na ni pak
	  nejde kliknout.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Layout = {}

-- Pod touhle šířkou se rozvržení skládá, ne zmenšuje
local NARROW_WIDTH = 900
-- Referenční výška, ke které se poměřuje škála
local BASE_HEIGHT = 900
-- Pod 0.72 už jsou tlačítka menší, než se dá pohodlně trefit prstem
local MIN_SCALE = 0.72
local MAX_SCALE = 1.15

local listeners: { (Layout.State) -> () } = {}

export type State = {
	Viewport: Vector2,
	Scale: number,
	Narrow: boolean,
	Touch: boolean,
}

local state: State = {
	Viewport = Vector2.new(1280, 720),
	Scale = 1,
	Narrow = false,
	Touch = false,
}

local function compute(): State
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)

	return {
		Viewport = viewport,
		Scale = math.clamp(viewport.Y / BASE_HEIGHT, MIN_SCALE, MAX_SCALE),
		Narrow = viewport.X < NARROW_WIDTH,
		Touch = UserInputService.TouchEnabled,
	}
end

--[[
	Registruje reakci na změnu rozvržení a hned ji jednou zavolá —
	volající tak nemusí řešit počáteční stav zvlášť.
]]
function Layout.onChange(callback: (State) -> ())
	table.insert(listeners, callback)
	callback(state)
end

--[[
	Škálovací obal. `UIScale` se aplikuje na kontejner, ne na jednotlivé
	prvky — tím se zachovají všechny vnitřní poměry a stačí měnit jedno číslo.
]]
function Layout.applyScale(container: GuiObject): UIScale
	local uiScale = container:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = container
	end

	;(uiScale :: UIScale).Scale = state.Scale
	return uiScale :: UIScale
end

--[[
	Omezení maxima. Prvek dostane relativní velikost (aby se vešel na
	malou obrazovku) a k tomu strop v pixelech, aby se na velkém monitoru
	neroztáhl do nesmyslu.
]]
function Layout.constrain(gui: GuiObject, maxSize: Vector2, minSize: Vector2?): UISizeConstraint
	local constraint = gui:FindFirstChildOfClass("UISizeConstraint")
	if not constraint then
		constraint = Instance.new("UISizeConstraint")
		constraint.Parent = gui
	end

	;(constraint :: UISizeConstraint).MaxSize = maxSize
	;(constraint :: UISizeConstraint).MinSize = minSize or Vector2.new(0, 0)
	return constraint :: UISizeConstraint
end

function Layout.start()
	state = compute()

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	--[[
		Přepočet se pouští jen když se rozměr opravdu změní. Na mobilu
		se ViewportSize hlásí i při otočení klávesnice nebo notifikace,
		takže bez téhle podmínky by se rozvržení přestavovalo zbytečně.
	]]
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local fresh = compute()
		if fresh.Viewport == state.Viewport then
			return
		end

		state = fresh
		for _, callback in listeners do
			task.spawn(callback, state)
		end
	end)
end

return Layout
