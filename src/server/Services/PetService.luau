--!strict
--[[
	PetService — vejce, líhnutí a nasazení petů.

	Pet je v tomhle žánru hlavní dlouhodobý cíl: hráč negrinduje na další
	upgrade, ale na vejce. Vzácnost se losuje váženě, takže mythic je
	reálně vzácný, ale ne nedosažitelný — a `Lucky` gamepass ty váhy
	posune, aniž by garantoval cokoliv.

	Losování běží na serveru. Kdyby ho dělal klient, byl by to nejlevnější
	exploit ve hře.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Live = require(Shared.Live)
local Perks = require(Shared.Perks)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Guard = require(script.Parent.GuardService)
local GameService = require(script.Parent.GameService)

local PetService = {}

type Result = { Ok: boolean, Message: string? }

local random = Random.new()

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function succeed(message: string?): Result
	return { Ok = true, Message = message }
end

-- Kolik petů smí mít hráč nasazených
function PetService.slots(profile: any): number
	local base = if profile.Passes and profile.Passes.Vip
		then Live.MaxEquippedPetsVip
		else Live.MaxEquippedPets

	-- Perk "Pack Leader" se přičítá i k VIP: kdo si ho koupil, má ho mít.
	return base + Perks.value(profile, "Slot")
end

--[[
	Vážené losování z poolu vejce.

	`Lucky` nenavyšuje šanci přímo, ale zmenšuje převahu běžných petů —
	tím se vzácné zvednou realisticky a nevznikne z toho garantovaný drop.
]]
function PetService.roll(eggId: string, lucky: boolean)
	local pool = Live.eggPool(eggId)
	if #pool == 0 then
		return nil
	end

	local total = 0
	local weights = table.create(#pool)

	for index, pet in pool do
		local weight = Live.rarity(pet.Rarity).Weight
		if lucky and weight < 100 then
			weight *= Live.PassBonus.LuckyWeight
		end
		weights[index] = weight
		total += weight
	end

	local roll = random:NextNumber(0, total)
	local running = 0

	for index, pet in pool do
		running += weights[index]
		if roll <= running then
			return pet
		end
	end

	return pool[#pool]
end

-- Přidá pet do inventáře bez placení (denní odměna, milník)
function PetService.grantFromEgg(player: Player, eggId: string)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end

	local pet = PetService.roll(eggId, profile.Passes and profile.Passes.Lucky == true)
	if not pet then
		return nil
	end

	profile.Pets[pet.Id] = (profile.Pets[pet.Id] or 0) + 1
	profile.Hatched += 1
	DataService.markDirty(player)

	-- První pety se nasadí samy, ať hráč nemusí nic hledat
	if #profile.EquippedPets < PetService.slots(profile) then
		table.insert(profile.EquippedPets, pet.Id)
	end

	return pet
end

function PetService.buyEgg(player: Player, eggId: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(eggId) ~= "string" then
		return fail("Profile not ready.")
	end

	local egg = Live.egg(eggId)
	if not egg then
		return fail("Unknown egg.")
	end
	if profile.Coins < egg.Price then
		return fail("Not enough coins.")
	end

	profile.Coins -= egg.Price
	profile.Spent += egg.Price

	local pet = PetService.grantFromEgg(player, eggId)
	if not pet then
		-- Peníze se nesmí ztratit, když se z jakéhokoliv důvodu nic nevylíhne
		profile.Coins += egg.Price
		profile.Spent -= egg.Price
		return fail("Egg is empty, try again.")
	end

	DataService.markDirty(player)
	DataService.save(player)

	local RetentionService = require(script.Parent.RetentionService)
	RetentionService.progress(player, "hatch", 1)
	RetentionService.progress(player, "spend", egg.Price)

	local Analytics = require(script.Parent.AnalyticsService)
	Analytics.onboarding(player, "FirstEgg")
	Analytics.economy(player, "Sink", "Coins", egg.Price, profile.Coins, "egg", eggId)
	Analytics.custom(player, "pet_hatched", 1, { rarity = pet.Rarity, egg = eggId })

	local rarity = Live.rarity(pet.Rarity)
	Remotes.EggHatched:FireClient(player, {
		PetId = pet.Id,
		Name = pet.Name,
		Rarity = pet.Rarity,
		Color = rarity.Color,
		Power = pet.Power,
		Shape = pet.Shape,
		EggId = eggId,
	})

	--[[
		Vzácný úlovek jde do výpisu okamžiků, ne do toastu. Toast si každý
		odklikne a zapomene; proužek ve výpisu chvíli visí a je vidět, že
		to potkalo někoho jiného — o to tu jde.
	]]
	require(script.Parent.MilestoneService).pet(player, pet, rarity)

	GameService.pushProfile(player)
	return succeed()
end

function PetService.equip(player: Player, petId: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(petId) ~= "string" then
		return fail("Profile not ready.")
	end
	if (profile.Pets[petId] or 0) <= 0 then
		return fail("You don't own that pet.")
	end

	-- Kliknutí na nasazeného peta ho sundá
	for index, equipped in profile.EquippedPets do
		if equipped == petId then
			table.remove(profile.EquippedPets, index)
			DataService.markDirty(player)
			GameService.pushProfile(player)
			return succeed()
		end
	end

	if #profile.EquippedPets >= PetService.slots(profile) then
		return fail(`Only {PetService.slots(profile)} pet slots. Unequip one first.`)
	end

	table.insert(profile.EquippedPets, petId)
	DataService.markDirty(player)
	GameService.pushProfile(player)

	return succeed()
end

--[[
	Kolik pety přidávají k Poweru. Bonusy nasazených se sčítají a k tomu
	se přičte VIP. Vrací násobič, tedy 1 = žádný bonus.
]]
function PetService.multiplier(profile: any): number
	local total = 1

	for _, petId in profile.EquippedPets or {} do
		local pet = Live.pet(petId)
		if pet then
			total += pet.Power
		end
	end

	if profile.Passes and profile.Passes.Vip then
		total *= Live.PassBonus.Vip
	end

	return total
end

-- Seznam petů pro UI, seřazený od nejsilnějšího
function PetService.snapshot(profile: any)
	local list = {}

	for petId, count in profile.Pets do
		local pet = Live.pet(petId)
		if pet and count > 0 then
			local _, tier = Live.petTier(petId)
			table.insert(list, {
				Id = pet.Id,
				Name = pet.Name,
				Rarity = pet.Rarity,
				Power = pet.Power,
				Shape = pet.Shape,
				Count = count,
				Tier = tier,
				Equipped = table.find(profile.EquippedPets, petId) ~= nil,
				CanMerge = count >= Live.Merge.Cost and Live.mergedId(petId) ~= nil,
			})
		end
	end

	table.sort(list, function(a, b)
		return a.Power > b.Power
	end)

	return list
end

--[[
	Sloučení. Spotřebuje `Live.Merge.Cost` kusů stejného petu a vrátí
	jeden o úroveň výš.

	Nasazený pet se při slučování sundá — jinak by hráči zůstal v nasazení
	odkaz na kus, který už nevlastní, a bonus by se počítal z ničeho.
]]
function PetService.merge(player: Player, petId: string): Result
	local profile = DataService.get(player)
	if not profile or typeof(petId) ~= "string" then
		return fail("Profile not ready.")
	end

	local count = profile.Pets[petId] or 0
	if count < Live.Merge.Cost then
		return fail(`Needs {Live.Merge.Cost}× the same pet.`)
	end

	local upgraded = Live.mergedId(petId)
	if not upgraded then
		return fail("Already at the highest tier.")
	end

	profile.Pets[petId] = count - Live.Merge.Cost
	if profile.Pets[petId] <= 0 then
		profile.Pets[petId] = nil
	end

	profile.Pets[upgraded] = (profile.Pets[upgraded] or 0) + 1

	-- Nasazení se musí přepočítat: hráč mohl přijít o poslední kus
	local equipped = {}
	for _, equippedId in profile.EquippedPets do
		if (profile.Pets[equippedId] or 0) > 0 then
			table.insert(equipped, equippedId)
		end
	end
	profile.EquippedPets = equipped

	-- Nový, silnější pet se rovnou nasadí, pokud je místo
	if #profile.EquippedPets < PetService.slots(profile) then
		table.insert(profile.EquippedPets, upgraded)
	end

	DataService.markDirty(player)
	DataService.save(player)

	local pet = Live.pet(upgraded)
	Remotes.EggHatched:FireClient(player, {
		PetId = upgraded,
		Name = pet.Name,
		Rarity = pet.Rarity,
		Color = Live.rarity(pet.Rarity).Color,
		Power = pet.Power,
		Shape = pet.Shape,
		EggId = "Merge",
	})

	GameService.pushProfile(player)
	return succeed()
end

function PetService.start()
	Guard.wrapFunction("BuyEgg", "Write", PetService.buyEgg)
	Guard.wrapFunction("EquipPet", "Cheap", PetService.equip)
	Guard.wrapFunction("MergePet", "Write", PetService.merge)
end

return PetService
