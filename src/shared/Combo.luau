--!strict
--[[
	Combo — řetěz sebraných "+1" za sebou.

	Proč vůbec: bez něj je sbírání pasivní. Hráč běží tratí a hodnota
	pickupu je pořád stejná, ať se snaží nebo ne. Combo dá základní
	smyčce jedinou věc, kterou dosud neměla — důvod hrát ji dobře.

	Pravidla schválně jednoduchá, ať jdou přečíst z HUD:
	  * každý uznaný pickup přidá jeden článek,
	  * po `Window` sekundách bez pickupu řetěz spadne na nulu,
	  * násobič roste lineárně do stropu, takže ×2 znamená přesně
	    "sbíral jsem sto pickupů bez zaváhání".

	Průraz bariéry řetěz NEBOURÁ. Hráč u ní stejně chvíli stojí a bylo
	by trestání za to, že hraje hru.

	Modul je čistý (žádné Roblox API), aby ho server mohl počítat
	autoritativně a klient podle stejných čísel kreslit HUD.
]]

local Combo = {}

-- Kolik sekund od posledního pickupu řetěz vydrží.
-- Respawn pickupu je 2.5 s, takže tohle je zhruba "nesmíš se zastavit".
Combo.Window = 2.5

-- Strop řetězu a přírůstek násobiče na článek.
-- 100 × 0,01 = ×2 na stropu: čitelné číslo, které jde říct jednou větou.
Combo.Max = 100
Combo.PerStep = 0.01

--[[
	Čím delší řetěz, tím kratší okno.

	Combo bylo do teď jen "nezastav se": okno drželo pořád stejné dvě
	a půl vteřiny, takže sto článků nebylo o nic těžší udržet než deset.
	Odměna rostla a napětí ne — a to je přesně ten druh mechaniky, který
	po pěti minutách přestane hráče zajímat.

	Na stropu zbyde 55 % okna. Za běhu se sbírá několikrát za vteřinu,
	takže to nevadí; bije to přesně tam, kde má — když se hráč
	s dlouhým řetězem zastaví nebo zaváhá u zdi. Nejvyšší násobič tím
	přestane být něco, co si člověk vyběhá, a stane se z něj něco, co
	si musí uhlídat.
]]
Combo.Tighten = 0.55

function Combo.windowAt(chain: number, window: number?): number
	local base = window or Combo.Window
	local share = math.clamp(chain, 0, Combo.Max) / Combo.Max
	return base * (1 - (1 - Combo.Tighten) * share)
end

export type State = {
	Chain: number,
	LastAt: number,
}

--[[
	Stupně jsou jen pojmenování rozsahu — hráč nepočítá články, ale vidí,
	že se něco změnilo. Barvy sedí na paletu hry (Config.Theme).
]]
Combo.Tiers = {
	{ At = 0, Name = "", Color = Color3.fromRGB(214, 174, 118) },
	{ At = 8, Name = "NICE", Color = Color3.fromRGB(96, 226, 255) },
	{ At = 25, Name = "HOT", Color = Color3.fromRGB(168, 255, 88) },
	{ At = 50, Name = "BLAZING", Color = Color3.fromRGB(255, 196, 60) },
	{ At = 80, Name = "UNREAL", Color = Color3.fromRGB(255, 86, 178) },
	{ At = 100, Name = "SMASHER", Color = Color3.fromRGB(150, 86, 255) },
}

function Combo.new(): State
	return { Chain = 0, LastAt = 0 }
end

--[[
	Kolik článků řetěz opravdu má.

	Nepočítá se to při vypršení, ale při čtení — stav tak nemusí nikdo
	uklízet a odhlášený hráč po sobě nenechá tikající smyčku.
]]
--[[
	`window` je nepovinné: bez něj platí základní `Combo.Window`. Perk
	"Flow State" ho prodlužuje, takže ho server i klient předávají —
	kdyby ho jeden z nich zapomněl, ukazoval by lištu jinak dlouhou,
	než jak řetěz doopravdy padá.
]]
function Combo.value(state: State?, now: number, window: number?): number
	if not state or state.Chain <= 0 then
		return 0
	end
	if now - state.LastAt > Combo.windowAt(state.Chain, window) then
		return 0
	end
	return state.Chain
end

-- Kolik sekund do pádu řetězu (0 = už spadl).
function Combo.remaining(state: State?, now: number, window: number?): number
	if Combo.value(state, now, window) <= 0 then
		return 0
	end
	local state = state :: State
	return math.max(Combo.windowAt(state.Chain, window) - (now - state.LastAt), 0)
end

--[[
	Přidá `count` článků a vrátí nový počet.

	Stav se mění na místě, protože ho server drží per hráč a kopírovat
	tabulku při každém pickupu by bylo zbytečné.
]]
function Combo.step(state: State, count: number, now: number, window: number?): number
	local current = Combo.value(state, now, window)

	state.Chain = math.min(current + math.max(count, 0), Combo.Max)
	state.LastAt = now

	return state.Chain
end

--[[
	Podrží řetěz, ale nepřidá článek.

	Mačkání hračky drží combo naživu, aniž by ho stavělo. Kdyby článek
	přidávalo, byla by nejlepší strategie stát na místě a mačkat —
	řetěz je odměna za sbírání v pohybu a to musí zůstat.

	Prázdný řetěz se schválně neoživí: kdo nic nenasbíral, nemá co
	držet, a mačkání by jinak zakládalo combo z ničeho.
]]
function Combo.hold(state: State?, now: number, window: number?): number
	local current = Combo.value(state, now, window)
	if current <= 0 then
		return 0
	end

	;(state :: State).LastAt = now
	return current
end

function Combo.reset(state: State)
	state.Chain = 0
	state.LastAt = 0
end

function Combo.multiplier(chain: number): number
	return 1 + math.clamp(chain, 0, Combo.Max) * Combo.PerStep
end

function Combo.maxMultiplier(): number
	return Combo.multiplier(Combo.Max)
end

--[[
	Stupeň pro daný řetěz. Vrací vždycky něco — nultý stupeň je prázdný,
	aby volající nemusel řešit nil.
]]
function Combo.tier(chain: number): { At: number, Name: string, Color: Color3 }
	local best = Combo.Tiers[1]

	for _, tier in Combo.Tiers do
		if chain >= tier.At then
			best = tier
		end
	end

	return best
end

-- Index stupně (1..n) — klient podle něj pozná, že se stupeň změnil.
function Combo.tierIndex(chain: number): number
	local best = 1

	for index, tier in Combo.Tiers do
		if chain >= tier.At then
			best = index
		end
	end

	return best
end

return Combo
