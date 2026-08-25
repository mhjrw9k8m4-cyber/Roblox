--!strict
--[[
	Fracture — rozlámání bariéry na kusy, které se chovají jako kusy.

	Původní verze sypala náhodné střepy náhodnými směry. Vypadá to jako
	konfety, ne jako rozbitá tabule. Tenhle modul dělá dvě věci jinak:

	1. TABULE SE LÁME PODLE MŘÍŽKY. Buňky se rozmístí do sítě s náhodným
	   posunem, takže drží tvar původní desky — a když odletí, je poznat,
	   odkud který kus byl.

	2. IMPULS SE POČÍTÁ Z MÍSTA NÁRAZU. Každý kus dostane směr od bodu,
	   kde do desky hráč vrazil, sílu podle vzdálenosti od něj a k tomu
	   část hráčovy vlastní rychlosti. Rychlý běh tak kusy odhodí dál —
	   a to je rozdíl mezi "efekt" a "náraz".

	Střepy padají na zem, dokutálí se a teprve pak zmizí. Kolizní skupina
	`Debris` je drží stranou od hráče, aby ho vlastní destrukce neházela
	po chodbě.

	Díly se recyklují. Při plném serveru by desítky nových dílů na každý
	průraz byly znát.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fracture = {}

local random = Random.new()

-- Zeď je přes celou chodbu, takže se dělí na víc kusů — při 5×4 by
-- z ní odletěly čtyři obří desky a vypadalo by to jako rozložené lego.
local COLUMNS = 6
local ROWS = 5
local POOL_LIMIT = 90
local SETTLE_SECONDS = 1.6

local pool: { BasePart } = {}

--[[
	Střepy, které jsou zrovna ve světě. Bez seznamu se nedají uklidit
	naráz: každý si sám o sobě mizí až po vlastním časovači, a při
	přechodu do jiného světa by tak zůstaly viset u trati, kterou hráč
	právě opustil.
]]
local active: { BasePart } = {}
local live = 0

local function acquire(): BasePart
	local part = table.remove(pool)
	if part then
		return part
	end

	local created = Instance.new("Part")
	created.Name = "Shard"
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.CastShadow = false
	created.CanQuery = false
	created.CanTouch = false
	return created
end

-- Skupinu registruje server. Nastavuje se při každém vydání z poolu, ne
-- jen při vytvoření — jinak by díl vyrobený dřív, než skupina dorazila,
-- zůstal mimo ni napořád a mlátil by do hráče.
local function assignGroup(part: BasePart)
	if part.CollisionGroup ~= "Debris" then
		pcall(function()
			part.CollisionGroup = "Debris"
		end)
	end
end

local function release(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.Parent = nil
	live -= 1

	local at = table.find(active, part)
	if at then
		table.remove(active, at)
	end

	if #pool < POOL_LIMIT then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

--[[
	Rozláme desku a rozhodí kusy.

	`impact` je bod, kde do desky hráč vrazil — od něj se odvíjí směr
	i síla každého kusu. `momentum` je rychlost hráče v okamžiku nárazu.
]]
function Fracture.shatter(options: {
	CFrame: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Impact: Vector3,
	Momentum: Vector3,
	Power: number,
	Detail: number?,
})
	local detail = options.Detail or 1
	local columns = math.max(math.floor(COLUMNS * detail), 2)
	local rows = math.max(math.floor(ROWS * detail), 2)

	local cellWidth = options.Size.X / columns
	local cellHeight = options.Size.Y / rows
	local force = 42 * options.Power

	for column = 0, columns - 1 do
		-- Strop na počet živých dílů; radši méně kusů než trhaná hra.
		-- Kontrola musí být i tady, jinak by `break` uvnitř přerušil jen
		-- jeden sloupec a vnější smyčka by pokračovala dál.
		if live >= POOL_LIMIT then
			break
		end

		for row = 0, rows - 1 do
			if live >= POOL_LIMIT then
				break
			end

			local part = acquire()
			assignGroup(part)

			-- Posun uvnitř buňky rozbije pravidelnost mřížky
			local jitterX = random:NextNumber(-0.18, 0.18) * cellWidth
			local jitterY = random:NextNumber(-0.18, 0.18) * cellHeight

			local localX = -options.Size.X / 2 + cellWidth * (column + 0.5) + jitterX
			local localY = -options.Size.Y / 2 + cellHeight * (row + 0.5) + jitterY

			part.Size = Vector3.new(
				cellWidth * random:NextNumber(0.7, 1.05),
				cellHeight * random:NextNumber(0.7, 1.05),
				options.Size.Z * random:NextNumber(0.6, 1)
			)
			part.Color = options.Color
			part.Material = options.Material
			part.Transparency = 0
			part.Anchored = false
			part.CanCollide = true
			part.CFrame = options.CFrame * CFrame.new(localX, localY, 0)
			part.Parent = Workspace
			live += 1
			table.insert(active, part)

			-- Směr od místa nárazu; blízké kusy dostanou víc
			local away = part.Position - options.Impact
			local distance = away.Magnitude
			local direction = if distance > 0.01 then away.Unit else Vector3.yAxis
			local falloff = 1 / (1 + distance * 0.12)

			part.AssemblyLinearVelocity = direction * force * falloff
				+ options.CFrame.LookVector * force * 0.35
				+ Vector3.new(0, force * 0.3 * falloff, 0)
				+ options.Momentum * 0.45

			part.AssemblyAngularVelocity = Vector3.new(
				random:NextNumber(-18, 18),
				random:NextNumber(-18, 18),
				random:NextNumber(-18, 18)
			)

			-- Kolize se vypne dřív, než díl zmizí: dokutálí se, ustálí
			-- a teprve pak vybledne, místo aby propadl podlahou.
			task.delay(SETTLE_SECONDS, function()
				if part.Parent then
					part.CanCollide = false
					TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Linear), {
						Transparency = 1,
					}):Play()
				end
			end)

			task.delay(SETTLE_SECONDS + 0.7, function()
				if part.Parent then
					release(part)
				end
			end)
		end
	end
end

--[[
	Rázová vlna, která opravdu tlačí. Projde okolní neukotvené díly
	(včetně střepů z předchozích průrazů) a přidá jim rychlost —
	destrukce tím dostane dosah za hranice jedné desky.
]]
function Fracture.shockwave(origin: Vector3, radius: number, strength: number)
	local region = Workspace:GetPartBoundsInRadius(origin, radius)

	for _, part in region do
		-- Ukotvené díly se nehýbou; pety a trať jsou ukotvené, takže
		-- tahle jedna podmínka stačí a nic dalšího filtrovat netřeba.
		if part.Anchored or not part:IsA("BasePart") then
			continue
		end

		local away = part.Position - origin
		local distance = away.Magnitude
		if distance < 0.01 then
			continue
		end

		local falloff = 1 - math.clamp(distance / radius, 0, 1)
		part.AssemblyLinearVelocity += away.Unit * strength * falloff
			+ Vector3.new(0, strength * 0.3 * falloff, 0)
	end
end

--[[
	Rozhrnutí střepů během.

	Střepy po průrazu do teď zůstaly ležet a hráč jimi procházel skrz —
	fyzicky tam byly, ale nic se s nimi nedělo. Kolizní skupina `Debris`
	je totiž schválně neprostupná jen mezi sebou, ne vůči postavě: kdyby
	do nich hráč narážel, zasekl by se v hromadě vlastní destrukce.

	Místo kolize se proto rozhrnují **impulzem**. Střep, kolem kterého
	hráč proběhne, dostane strk do strany a trochu vzhůru — cesta za
	ním se rozevře, jako by se v tom brodil.

	Síla se násobí hráčovou rychlostí: v plném běhu je odmete, při chůzi
	je jen odsune. To je ta část, kvůli které to působí fyzikálně,
	a ne jako naskriptovaný efekt.
]]
function Fracture.wade(position: Vector3, velocity: Vector3, radius: number)
	local speed = velocity.Magnitude
	if speed < 4 then
		return
	end

	local region = Workspace:GetPartBoundsInRadius(position, radius)

	for _, part in region do
		if part.Anchored or not part:IsA("BasePart") then
			continue
		end

		local away = (part.Position - position) * Vector3.new(1, 0, 1)
		local distance = away.Magnitude
		if distance < 0.05 then
			continue
		end

		local falloff = 1 - math.clamp(distance / radius, 0, 1)
		--[[
			Vodorovně od hráče a lehce nahoru. Bez té svislé složky by se
			střepy jen posunuly po zemi; s ní vyskočí a je to vidět.
		]]
		part.AssemblyLinearVelocity += away.Unit * speed * 0.55 * falloff
			+ Vector3.new(0, speed * 0.2 * falloff, 0)
	end
end

--[[
	Kolik střepů je zrovna ve světě, a kolik jich nejvíc smí být.

	Ven kvůli testu: strop je pojistka proti trhané hře na slabém
	zařízení a pojistka, kterou nikdo neměří, je jen komentář. Číslo
	se ven dává schválně místo toho, aby si ho test opsal — opsaný
	strop by po jeho změně tiše přestal měřit to, co se doopravdy děje.
]]
function Fracture.liveCount(): number
	return live
end

Fracture.PoolLimit = POOL_LIMIT

--[[
	Uklidí všechny střepy naráz.

	Volá se při přestavbě trati — tedy při přechodu do jiného světa
	nebo do dalšího kola. Střepy z předchozí zdi zůstávaly viset
	u trati, kterou hráč právě opustil: nekotvené díly, které nikdo
	neuvidí a které se přesto počítají do fyziky.
]]
function Fracture.clear()
	for _, part in table.clone(active) do
		release(part)
	end
end

return Fracture
