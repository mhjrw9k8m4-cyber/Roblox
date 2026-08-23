--!strict
--[[
	Economy — všechny výpočty progrese na jednom místě.

	Sdílené záměrně: server podle toho počítá skutečné odměny,
	klient podle toho ukazuje v obchodě, co ti vylepšení přinese.
	Jeden vzorec = UI nikdy nelže.
]]

local Config = require(script.Parent.Config)

local Economy = {}

export type Stats = {
	Damage: number,
	Cooldown: number,
	EarnMultiplier: number,
	ComboMax: number,
	AutoRate: number,
	RebirthMultiplier: number,
}

local function upgradeLevel(profile: any, id: string): number
	return (profile.Upgrades and profile.Upgrades[id]) or 0
end

function Economy.damage(profile: any): number
	local tool = Config.tool(profile.EquippedTool) or Config.Tools[1]
	local sharpness = Config.upgrade("Sharpness")
	return tool.Damage * (1 + upgradeLevel(profile, "Sharpness") * sharpness.PerLevel)
end

function Economy.cooldown(profile: any): number
	local tool = Config.tool(profile.EquippedTool) or Config.Tools[1]
	local speed = Config.upgrade("Speed")
	local reduction = 1 - upgradeLevel(profile, "Speed") * speed.PerLevel
	return math.max(tool.Cooldown * reduction, 0.05)
end

function Economy.rebirthMultiplier(profile: any): number
	return 1 + profile.Rebirths * Config.Rebirth.BonusPerRebirth
end

function Economy.earnMultiplier(profile: any): number
	local fortune = Config.upgrade("Fortune")
	local fromUpgrade = 1 + upgradeLevel(profile, "Fortune") * fortune.PerLevel
	return fromUpgrade * Economy.rebirthMultiplier(profile)
end

function Economy.comboMax(profile: any): number
	local combo = Config.upgrade("Combo")
	return Config.Core.ComboBaseMax + upgradeLevel(profile, "Combo") * combo.PerLevel
end

function Economy.autoRate(profile: any): number
	local auto = Config.upgrade("Auto")
	return upgradeLevel(profile, "Auto") * auto.PerLevel
end

function Economy.stats(profile: any): Stats
	return {
		Damage = Economy.damage(profile),
		Cooldown = Economy.cooldown(profile),
		EarnMultiplier = Economy.earnMultiplier(profile),
		ComboMax = Economy.comboMax(profile),
		AutoRate = Economy.autoRate(profile),
		RebirthMultiplier = Economy.rebirthMultiplier(profile),
	}
end

--[[
	Peníze za jednu ránu.
	Platí se poměrem ubrané integrity, takže tvrdší materiál nese víc,
	ale trvá dýl — a silnější nůž zrychluje celý cyklus.
]]
function Economy.strikeReward(profile: any, objectId: string, dealt: number, comboMultiplier: number): number
	local object = Config.object(objectId) or Config.Objects[1]
	local share = dealt / object.Integrity
	return math.max(math.floor(object.Value * share * comboMultiplier * Economy.earnMultiplier(profile)), 1)
end

function Economy.destroyBonus(profile: any, objectId: string): number
	local object = Config.object(objectId) or Config.Objects[1]
	return math.floor(object.Value * Config.Core.DestroyBonus * Economy.earnMultiplier(profile))
end

-- Kolik peněz za sekundu hráč zhruba udělá (pro UI a porovnání upgradů)
function Economy.coinsPerSecond(profile: any): number
	local object = Config.object(profile.EquippedObject) or Config.Objects[1]
	local damage = Economy.damage(profile)
	local cooldown = Economy.cooldown(profile)
	local strikesPerObject = math.max(object.Integrity / damage, 1)
	local secondsPerObject = strikesPerObject * cooldown
	local perObject = object.Value * (1 + Config.Core.DestroyBonus) * Economy.earnMultiplier(profile)
	return perObject / math.max(secondsPerObject, 0.01)
end

--[[
	Přidá XP a vrátí, kolik úrovní hráč získal.
	Přebytek XP se přelévá do další úrovně, takže velký zisk může
	skočit o víc levelů najednou.
]]
function Economy.addXp(profile: any, amount: number): number
	profile.Xp += amount
	local gained = 0

	while profile.Level < Config.Level.MaxLevel do
		local needed = Config.xpForLevel(profile.Level)
		if profile.Xp < needed then
			break
		end
		profile.Xp -= needed
		profile.Level += 1
		gained += 1
	end

	if profile.Level >= Config.Level.MaxLevel then
		profile.Xp = 0
	end

	return gained
end

-- Postup v aktuální úrovni jako 0..1 (pro XP lištu)
function Economy.levelProgress(profile: any): (number, number)
	if profile.Level >= Config.Level.MaxLevel then
		return 1, 0
	end
	local needed = Config.xpForLevel(profile.Level)
	return math.clamp(profile.Xp / needed, 0, 1), needed
end

-- Může si hráč koupit / nasadit danou věc?
function Economy.canUnlockTool(profile: any, id: string): (boolean, string?)
	local tool = Config.tool(id)
	if not tool then
		return false, "Neznámý nůž."
	end
	if profile.Tools[id] then
		return false, "Už ho vlastníš."
	end
	if profile.Level < tool.Level then
		return false, `Potřebuješ úroveň {tool.Level}.`
	end
	if profile.Coins < tool.Price then
		return false, "Nemáš dost peněz."
	end
	return true, nil
end

function Economy.canUnlockObject(profile: any, id: string): (boolean, string?)
	local object = Config.object(id)
	if not object then
		return false, "Neznámý materiál."
	end
	if profile.Objects[id] then
		return false, "Už ho vlastníš."
	end
	if profile.Level < object.Level then
		return false, `Potřebuješ úroveň {object.Level}.`
	end
	if profile.Coins < object.Price then
		return false, "Nemáš dost peněz."
	end
	return true, nil
end

function Economy.canBuyUpgrade(profile: any, id: string): (boolean, string?)
	local upgrade = Config.upgrade(id)
	if not upgrade then
		return false, "Neznámé vylepšení."
	end
	local level = upgradeLevel(profile, id)
	local price = Config.upgradePrice(id, level)
	if not price then
		return false, "Maximální úroveň."
	end
	if profile.Coins < price then
		return false, "Nemáš dost peněz."
	end
	return true, nil
end

function Economy.canRebirth(profile: any): (boolean, string?)
	local cost = Config.rebirthCost(profile.Rebirths)
	if profile.Coins < cost then
		return false, "Nemáš dost peněz na rebirth."
	end
	return true, nil
end

return Economy
