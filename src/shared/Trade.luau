--!strict
--[[
	Trade — logika obchodu, oddělená od sítě i od hráčů.

	Obchodování je v každé hře nejčastější díra na duplikaci itemů. Klasické
	způsoby, jak z něj vytáhnout věci zadarmo:

	  * nabídnout hračku, kterou mezitím vyměníš nebo dáš pryč,
	  * nabídnout desetkrát tu samou hračku, kterou máš jednou,
	  * potvrdit, počkat, až potvrdí druhý, a na poslední chvíli nabídku
	    vyměnit za bezcennou,
	  * odejít v půlce a doufat, že se výměna provede jen na jedné straně.

	Proto je celý výpočet tady, v čistých funkcích nad obyčejnými
	tabulkami. Nedá se tím poslat zpráva ani sáhnout na hráče — a hlavně
	se to dá otestovat, což u kódu, kde chyba znamená zničenou ekonomiku,
	není luxus.

	Klíčová vlastnost, kterou testy hlídají: výměna **nesmí změnit celkový
	počet kusů**. Co zmizí jednomu, musí přibýt druhému.
]]

local Trade = {}

-- Kolik různých hraček smí být v jedné nabídce
Trade.MaxItems = 6
-- Po téhle době nečinnosti obchod sám spadne
Trade.TimeoutSeconds = 120

export type Offer = { [string]: number }
export type Inventory = { [string]: number }

--[[
	Kolik kusů dané hračky smí hráč ještě přidat do nabídky.
	Počítá se z toho, co vlastní, minus co už nabídl.
]]
function Trade.available(inventory: Inventory, offer: Offer, itemId: string): number
	return math.max((inventory[itemId] or 0) - (offer[itemId] or 0), 0)
end

--[[
	Smí hráč přidat tenhle kus do nabídky?

	Vrací i důvod, aby ho šlo hráči rovnou ukázat — "nelze" bez vysvětlení
	vypadá jako chyba hry.
]]
function Trade.canAdd(inventory: Inventory, offer: Offer, itemId: string): (boolean, string?)
	if (inventory[itemId] or 0) <= 0 then
		return false, "You don't own that squishy."
	end
	if Trade.available(inventory, offer, itemId) <= 0 then
		return false, "All of those are already in the offer."
	end

	-- Počet různých druhů, ne kusů: šest řádků se ještě dá přečíst
	local kinds = 0
	for _ in offer do
		kinds += 1
	end
	if offer[itemId] == nil and kinds >= Trade.MaxItems then
		return false, `Up to {Trade.MaxItems} different squishies per trade.`
	end

	return true, nil
end

function Trade.add(offer: Offer, itemId: string): Offer
	local next: Offer = table.clone(offer)
	next[itemId] = (next[itemId] or 0) + 1
	return next
end

function Trade.remove(offer: Offer, itemId: string): Offer
	local next: Offer = table.clone(offer)
	local count = (next[itemId] or 0) - 1

	if count <= 0 then
		next[itemId] = nil
	else
		next[itemId] = count
	end

	return next
end

--[[
	Je nabídka pořád platná vůči skutečnému inventáři?

	Tohle se musí volat **znovu v okamžiku výměny**, ne jen při vkládání.
	Mezi nabídnutím a potvrzením může hráč hračku vyměnit nebo dostat
	něco jiného — a přesně na tom stojí většina duplikačních exploitů.
]]
function Trade.validate(inventory: Inventory, offer: Offer): (boolean, string?)
	local empty = true

	for itemId, count in offer do
		empty = false

		if count <= 0 then
			return false, "Invalid offer."
		end
		if (inventory[itemId] or 0) < count then
			return false, "Someone no longer owns what they offered."
		end
	end

	if empty then
		return false, "Both sides must offer something."
	end

	return true, nil
end

--[[
	Provede výměnu nad dvěma inventáři a vrátí nové.

	Nemění vstupy — volající si tak může výsledek nejdřív zkontrolovat
	a teprve pak ho zapsat. Prázdné položky se z tabulky mažou, aby
	inventář nezaplevelily nuly.
]]
function Trade.apply(
	inventoryA: Inventory,
	offerA: Offer,
	inventoryB: Inventory,
	offerB: Offer
): (Inventory, Inventory)
	local nextA: Inventory = table.clone(inventoryA)
	local nextB: Inventory = table.clone(inventoryB)

	local function move(from: Inventory, to: Inventory, offer: Offer)
		for itemId, count in offer do
			local left = (from[itemId] or 0) - count
			if left <= 0 then
				from[itemId] = nil
			else
				from[itemId] = left
			end

			to[itemId] = (to[itemId] or 0) + count
		end
	end

	move(nextA, nextB, offerA)
	move(nextB, nextA, offerB)

	return nextA, nextB
end

--[[
	Vyhodí z ruky hračky, které hráč po výměně už nevlastní.

	Bez tohohle by mu zůstal v ruce odkaz na hračku, kterou dal pryč,
	a jeho bonus by se dál počítal — tichá varianta duplikace.
]]
function Trade.pruneEquipped(inventory: Inventory, equipped: { string }): { string }
	local kept = {}

	for _, itemId in equipped do
		if (inventory[itemId] or 0) > 0 then
			table.insert(kept, itemId)
		end
	end

	return kept
end

--[[
	Změna nabídky musí zrušit obě potvrzení.

	Klasický podvod: obě strany potvrdí, podvodník na poslední chvíli
	vymění cennou hračku za bezcennou a druhý to nestihne zaregistrovat.
	Když jakákoliv změna shodí potvrzení, útok přestane fungovat.
]]
function Trade.resetConfirmations(session: any)
	session.ConfirmA = false
	session.ConfirmB = false
end

function Trade.bothConfirmed(session: any): boolean
	return session.ConfirmA == true and session.ConfirmB == true
end

-- Celkový počet kusů v inventáři; testy si tím hlídají zachování množství
function Trade.totalItems(inventory: Inventory): number
	local total = 0
	for _, count in inventory do
		total += count
	end
	return total
end

return Trade
