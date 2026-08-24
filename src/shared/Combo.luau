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
	if now - state.LastAt > (window or Combo.Window) then
		return 0
	end
	return state.Chain
end

-- Kolik sekund do pádu řetězu (0 = už spadl).
function Combo.remaining(state: State?, now: number, window: number?): number
	if Combo.value(state, now, window) <= 0 then
		return 0
	end
	return math.max((window or Combo.Window) - (now - (state :: State).LastAt), 0)
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
