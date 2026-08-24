--!strict
--[[
	MonetizationService — gamepassy, vývojářské produkty a badge.

	Roblox od konce roku 2025 měří útratu jako samostatný signál
	v doporučování, takže nabídka musí ve hře být — ale musí být poctivá:
	žádná z nabídek tady neblokuje postup, jen ho zrychluje.

	ID jsou v `Live` nastavená na nulu. Dokud je nedoplníš z Creator
	Dashboardu, nabídky se hráči vůbec nezobrazí — hra tak nikdy neukazuje
	tlačítko, které nejde zmáčknout.
]]

local BadgeService = game:GetService("BadgeService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Live = require(Shared.Live)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

local Monetization = {}

-- Gamepassy -------------------------------------------------------------------

--[[
	Vlastnictví se zjišťuje jednou při vstupu a pak už jen při nákupu.
	`UserOwnsGamePassAsync` je síťové volání; ptát se na něj v herní
	smyčce by hru zadrhávalo.
]]
function Monetization.refreshPasses(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local changed = false

	for _, pass in Live.Passes do
		if pass.GamepassId == 0 then
			continue
		end

		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.GamepassId)
		end)

		if ok and profile.Passes[pass.Id] ~= owns then
			profile.Passes[pass.Id] = owns
			changed = true
		end
	end

	if changed then
		DataService.markDirty(player)
		GameService.pushProfile(player)
	end

	Monetization.pushOffers(player)
end

-- Klient potřebuje vlastnictví i seznam nabídek naráz; dvě zprávy by
-- se mohly rozejít a UI by chvíli ukazovalo koupené jako nekoupené.
function Monetization.pushOffers(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	Remotes.PassesChanged:FireClient(player, {
		Passes = profile.Passes,
		Offers = Monetization.offers(player),
	})
end

local function onPassPurchased(player: Player, gamepassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	for _, pass in Live.Passes do
		if pass.GamepassId == gamepassId then
			profile.Passes[pass.Id] = true
			DataService.markDirty(player)
			DataService.save(player)

			GameService.pushProfile(player)
			Monetization.pushOffers(player)
			Remotes.Notify:FireClient(player, {
				Text = `{pass.Name} unlocked!`,
				Kind = "success",
				Sound = "Rebirth",
			})
			return
		end
	end
end

-- Vývojářské produkty ------------------------------------------------------------

--[[
	ProcessReceipt musí být idempotentní: Roblox může stejnou účtenku
	poslat víckrát a než vrátíme `PurchaseGranted`, musí být odměna
	bezpečně uložená. Proto se po připsání rovnou ukládá profil —
	kdyby server spadl mezi tím, hráč by zaplatil a nic nedostal.
]]
local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Hráč odešel; ať to Roblox zkusí znovu, až se vrátí
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product
	for _, entry in Live.Products do
		if entry.ProductId == receipt.ProductId then
			product = entry
			break
		end
	end

	if not product then
		-- Neznámý produkt nikdy nepotvrzuj jako vyřízený
		warn(`[Monetization] Neznámý produkt {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if product.Gems then
		profile.Gems += product.Gems
	end
	if product.CoinSeconds then
		profile.Coins += math.floor(Economy.coinsPerSecond(profile, os.time()) * product.CoinSeconds)
	end

	DataService.markDirty(player)
	if not DataService.save(player) then
		-- Neuložilo se: raději nic nepotvrdit, než připsat a ztratit
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	GameService.pushProfile(player)
	Remotes.Notify:FireClient(player, {
		Text = `{product.Name} added. Thanks!`,
		Kind = "success",
		Sound = "Purchase",
	})

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Badge ----------------------------------------------------------------------------

--[[
	Badge jsou levná forma uznání a Roblox je ukazuje na profilu hry,
	takže fungují i jako sociální důkaz. Udělují se jednou.
]]
function Monetization.checkBadges(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local worlds = 0
	for _, unlocked in profile.Worlds do
		if unlocked then
			worlds += 1
		end
	end

	for _, badge in Live.Badges do
		if badge.BadgeId == 0 or profile.Badges[badge.Id] then
			continue
		end

		local earned = (badge.Smashes and profile.Smashes >= badge.Smashes)
			or (badge.Rebirths and profile.Rebirths >= badge.Rebirths)
			or (badge.Worlds and worlds >= badge.Worlds)

		if not earned then
			continue
		end

		profile.Badges[badge.Id] = true
		DataService.markDirty(player)

		task.spawn(function()
			local ok, err = pcall(function()
				BadgeService:AwardBadge(player.UserId, badge.BadgeId)
			end)
			if not ok then
				warn(`[Monetization] Badge {badge.Name} se nepodařilo udělit: {err}`)
			end
		end)
	end
end

-- Nabídky pro klienta ----------------------------------------------------------------

--[[
	Klient dostane jen ty nabídky, které mají skutečné ID. Nabídka bez ID
	by byla tlačítko, po kterém se nic nestane.
]]
function Monetization.offers(player: Player)
	local profile = DataService.get(player)

	local passes = {}
	for _, pass in Live.Passes do
		if pass.GamepassId ~= 0 then
			table.insert(passes, {
				Id = pass.Id,
				Name = pass.Name,
				Desc = pass.Desc,
				Icon = pass.Icon,
				GamepassId = pass.GamepassId,
				Owned = profile and profile.Passes[pass.Id] == true,
			})
		end
	end

	local products = {}
	for _, product in Live.Products do
		if product.ProductId ~= 0 then
			table.insert(products, {
				Id = product.Id,
				Name = product.Name,
				Icon = product.Icon,
				ProductId = product.ProductId,
			})
		end
	end

	return { Passes = passes, Products = products }
end

function Monetization.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)

	Remotes.PromptPass.OnServerEvent:Connect(function(player, passId)
		local pass = Live.pass(passId)
		if pass and pass.GamepassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.GamepassId)
		end
	end)

	Remotes.PromptProduct.OnServerEvent:Connect(function(player, productId)
		local product = Live.product(productId)
		if product and product.ProductId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		end
	end)

	-- Milníky se kontrolují průběžně, ne po každé ráně
	task.spawn(function()
		while true do
			task.wait(20)
			for _, player in Players:GetPlayers() do
				Monetization.checkBadges(player)
			end
		end
	end)
end

return Monetization
