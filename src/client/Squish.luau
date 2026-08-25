--!strict
--[[
	Squish — mačkání s pomalým návratem.

	Celý půvab squishy hraček stojí na jedné věci: **zmáčkneš je a ony se
	vrátí pomalu**. Ne odpruží — pomalu se zvednou. Důlek po prstu zůstane
	vidět ještě vteřinu poté, co jsi ruku dal pryč, a to je přesně to, co
	je na tom uspokojivé.

	Ve hře to do teď nebylo. Pickup zmizel, zeď se buď prorazila, nebo
	nestalo nic. Nic nereagovalo na dotek a nic si dotek nepamatovalo.

	Tenhle modul je ta chybějící vrstva. Umí jediné: promáčknout díl
	a nechat ho pomalu vrátit.

	Křivka je schválně `t^2.2`, ne lineární ani `ease-out`:

	    lineární   — vypadá jako výtah, mechanicky
	    ease-out   — vystřelí zpátky, to je guma, ne squishy
	    t^2.2      — chvíli zůstane dole a teprve pak se zvedne

	Právě to zdržení na dně je ten "slow rise", kvůli kterému lidi ta
	videa sledují.

	Všechno běží z jedné Heartbeat smyčky nad seznamem aktivních důlků —
	desítky vlastních spojení by se při přestavbě světa musely uklízet.
]]

local RunService = game:GetService("RunService")

local Squish = {}

type Entry = {
	Part: BasePart,
	-- Původní stav, do kterého se díl vrací
	BaseCFrame: CFrame,
	BaseSize: Vector3,
	-- Jak hluboko se promáčkl a jak moc se roztáhl do stran
	Depth: number,
	Spread: number,
	--[[
		Směr mačkání v lokálních osách dílu, VČETNĚ znaménka.

		Znaménko říká, která strana zůstane na místě. Pickup se mačká
		dolů (`-Y`), takže mu zůstane stát spodek a promáčkne se vršek —
		kdyby se mačkal nahoru, propadl by se do země.
	]]
	Axis: Vector3,
	Rise: number,
	Elapsed: number,
	--[[
		Lepivé přidržení: jak dlouho zůstane díl úplně stlačený, než
		se vůbec začne vracet. Skutečná squishy hračka se od prstu
		neodlepí hned — a je to slyšet i v těch videích ("slightly
		sticky"). Bez toho vypadá i pomalý návrat jako pružina.
	]]
	Hold: number,
	--[[
		Díly přivařené k ruce se nedají posouvat přes CFrame — svar to
		každý krok fyziky přepíše zpátky. Posun proto jde do svaru.
	]]
	Weld: Weld?,
	BaseC0: CFrame,
}

local active: { Entry } = {}
-- Díl smí mít v jednu chvíli jen jeden důlek; druhý by si s prvním
-- přepisoval původní stav a díl by se "propadl" natrvalo.
local byPart: { [BasePart]: Entry } = {}

local enabled = true

--[[
	Zmáčkne díl.

	`depth` je podíl rozměru, o který se propadne (0.6 = na 40 % tloušťky).
	`axis` je lokální osa mačkání; když se neuvede, mačká se do hloubky (Z).
	`rise` je doba návratu v sekundách.
]]
function Squish.press(part: BasePart, depth: number, rise: number, axis: Vector3?, hold: number?)
	if not enabled or not part.Parent then
		return
	end

	local existing = byPart[part]
	if existing then
		--[[
			Další zmáčknutí důlek prohloubí a čas návratu spustí znovu.
			Původní stav se NEPŘEPISUJE — ten drží první zmáčknutí,
			jinak by se díl s každým dotykem trvale zmenšoval.
		]]
		existing.Depth = math.clamp(math.max(existing.Depth, depth), 0, 0.9)
		existing.Rise = rise
		existing.Hold = hold or 0
		existing.Elapsed = 0
		return
	end

	--[[
		Svar se hledá na dílu i na jeho rodiči: hračka v ruce je
		poskládaná z několika kusů a svar drží každý z nich zvlášť.
	]]
	local weld = part:FindFirstChildWhichIsA("Weld")
	if weld and weld.Part1 ~= part then
		weld = nil
	end

	local entry: Entry = {
		Part = part,
		Weld = weld,
		BaseC0 = if weld then weld.C0 else CFrame.identity,
		BaseCFrame = part.CFrame,
		BaseSize = part.Size,
		Depth = math.clamp(depth, 0, 0.9),
		-- Hmota se nikam neztratí: co ubude v hloubce, přibude do stran.
		-- Bez toho vypadá zmáčknutí jako zmenšení, ne jako stlačení.
		Spread = math.clamp(depth, 0, 0.9) * 0.42,
		-- Bez určení se mačká dolů: to je zdaleka nejčastější případ
		Axis = axis or -Vector3.yAxis,
		Rise = math.max(rise, 0.05),
		Hold = math.max(hold or 0, 0),
		Elapsed = 0,
	}

	byPart[part] = entry
	table.insert(active, entry)
end

-- Vrátí díl okamžitě do původního stavu (třeba než se schová).
function Squish.release(part: BasePart)
	local entry = byPart[part]
	if not entry then
		return
	end

	if part.Parent then
		part.Size = entry.BaseSize
		if entry.Weld then
			entry.Weld.C0 = entry.BaseC0
		else
			part.CFrame = entry.BaseCFrame
		end
	end

	byPart[part] = nil
	for index, other in active do
		if other == entry then
			table.remove(active, index)
			break
		end
	end
end

--[[
	Přepíše původní stav, do kterého se díl vrací.

	Volá se, když se dílem legitimně pohne odjinud (pickup se po sebrání
	posune, zeď se přestaví). Bez toho by ho návrat vrátil tam, kde byl
	před tím posunem.
]]
function Squish.rebase(part: BasePart)
	local entry = byPart[part]
	if entry then
		entry.BaseCFrame = part.CFrame
		entry.BaseSize = part.Size
		if entry.Weld then
			entry.BaseC0 = entry.Weld.C0
		end
	end
end

--[[
	Má díl zrovna rozdělaný důlek?

	Ptá se na to všechno, co dílu samo přepisuje velikost — třeba
	dýchání hračky v ruce. Dvě věci, které si na jeden díl sahají naráz,
	ho nechají natrvalo zmenšený, protože návrat se vrací k rozměru,
	který mezitím někdo přepsal.
]]
function Squish.isPressed(part: BasePart): boolean
	return byPart[part] ~= nil
end

function Squish.setEnabled(value: boolean)
	enabled = value

	if not value then
		for index = #active, 1, -1 do
			Squish.release(active[index].Part)
		end
	end
end

function Squish.start()
	RunService.Heartbeat:Connect(function(deltaTime)
		for index = #active, 1, -1 do
			local entry = active[index]
			local part = entry.Part

			if not part.Parent then
				byPart[part] = nil
				table.remove(active, index)
				continue
			end

			entry.Elapsed += deltaTime

			--[[
				Nejdřív lepivé přidržení, teprve pak návrat. Během
				přidržení je promáčknutí plné, takže se díl ani
				nehne — a právě to nehnutí čte oko jako lepivost.
			]]
			local afterHold = entry.Elapsed - entry.Hold
			local t = if afterHold <= 0 then 0 else afterHold / entry.Rise

			if t >= 1 then
				part.Size = entry.BaseSize
				if entry.Weld then
					entry.Weld.C0 = entry.BaseC0
				else
					part.CFrame = entry.BaseCFrame
				end
				byPart[part] = nil
				table.remove(active, index)
				continue
			end

			-- Zbývající promáčknutí. Mocnina drží důlek chvíli dole
			-- a teprve pak ho pustí nahoru — to je ten pomalý návrat.
			local remaining = 1 - t ^ 2.2

			local squeeze = entry.Depth * remaining
			local bulge = entry.Spread * remaining
			local axis = entry.Axis

			--[[
				Osa mačkání se zmenší, zbylé dvě se roztáhnou. Počítá se
				to složkově, protože `Vector3` nemá "všechno kromě téhle
				osy" — a `1 - axis` je přesně to.
			]]
			--[[
				Rozměr se počítá ze SMĚRU BEZ ZNAMÉNKA: zmenšit se má osa
				mačkání, ať se mačká z které strany chce. Znaménko se
				uplatní až u posunu níž.
			]]
			local along = Vector3.new(math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z))
			local shrink = Vector3.one - along * squeeze
			local grow = Vector3.one + (Vector3.one - along) * bulge

			part.Size = entry.BaseSize * shrink * grow

			--[[
				Díl se musí propadnout, ne zmenšit kolem středu. Střed se
				proto posune o polovinu toho, co ubylo, VE SMĚRU mačkání —
				protilehlá strana tím zůstane přesně tam, kde byla.
			]]
			local lost = (entry.BaseSize * along * squeeze).Magnitude
			local shift = CFrame.new(axis * (lost / 2))

			if entry.Weld then
				-- C1 necháváme jednotkové, takže pravostranné násobení
				-- C0 posune díl v jeho vlastní ose, stejně jako CFrame
				entry.Weld.C0 = entry.BaseC0 * shift
			else
				part.CFrame = entry.BaseCFrame * shift
			end
		end
	end)
end

return Squish
