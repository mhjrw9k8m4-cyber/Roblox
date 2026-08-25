--!strict
--[[
	Účtenky za vývojářské produkty.

	Roblox stejnou účtenku doručí i víckrát — proto v ní vůbec je
	`PurchaseId`. Server tedy MUSÍ poznat, že tuhle už jednou vyřídil,
	a odměnu podruhé nepřipsat.

	Do teď to bylo napsané jen v komentáři: nikde se nic nezapisovalo,
	takže hráč za jeden nákup dostal gemy tolikrát, kolikrát Roblox
	doručení zopakoval. Poznalo by se to až na číslech, která nesedí
	s tržbami — tedy pozdě a špatně.
]]

return function(t)
	local Live = t.require("Live")
	local DataService = t.require("DataService")
	local MarketplaceService = t.stub().service("MarketplaceService")

	-- Aby se služba navěsila na ProcessReceipt
	t.require("MonetizationService").start()

	local product = Live.Products[1]
	t.assert(product ~= nil, "v konfiguraci není žádný produkt")

	--[[
		Produkty mají v konfiguraci nulu, dokud je někdo nezaloží
		v Creator Dashboardu. Test si proto na chvíli nastaví vlastní
		id — a zároveň tím ověřuje, že se na skutečné id vůbec trefí.
	]]
	local PRODUCT_ID = 909090
	local originalId = product.ProductId
	product.ProductId = PRODUCT_ID

	local function receipt(purchaseId: string, userId: number)
		return {
			PurchaseId = purchaseId,
			PlayerId = userId,
			ProductId = PRODUCT_ID,
			CurrencySpent = 100,
		}
	end

	t.test("stejná účtenka nepřipíše odměnu dvakrát", function()
		local players = t.world().players
		local player = players:_add("Kupujici", 31337)
		local profile = DataService.get(player)
		t.assert(profile ~= nil, "profil se nenačetl")

		profile.Gems = 0

		local first = MarketplaceService.ProcessReceipt(receipt("ucet-1", player.UserId))
		t.equal(first, Enum.ProductPurchaseDecision.PurchaseGranted, "první doručení neprošlo")
		t.equal(profile.Gems, product.Gems, "za první doručení nepřišly správné gemy")

		--[[
			Druhé doručení té samé účtenky. Potvrdit se MUSÍ — Roblox se
			ptá právě proto, že mu první odpověď nedorazila — ale gemy
			přibýt nesmí.
		]]
		local again = MarketplaceService.ProcessReceipt(receipt("ucet-1", player.UserId))
		t.equal(again, Enum.ProductPurchaseDecision.PurchaseGranted, "opakované doručení se nepotvrdilo")
		t.equal(profile.Gems, product.Gems, "opakované doručení připsalo gemy znovu")

		-- A jiná účtenka odměnu dostat MUSÍ, jinak by stačilo blokovat všechno
		local second = MarketplaceService.ProcessReceipt(receipt("ucet-2", player.UserId))
		t.equal(second, Enum.ProductPurchaseDecision.PurchaseGranted, "druhý nákup neprošel")
		t.equal(profile.Gems, product.Gems * 2, "za druhý nákup nepřišly gemy")
	end)

	--[[
		Seznam účtenek má strop. Neomezený by profil nafukoval do konce
		života účtu a při každém uložení se posílal po síti celý.
	]]
	t.test("seznam účtenek nepřeteče", function()
		local players = t.world().players
		local player = players:_add("Utratny", 31338)
		local profile = DataService.get(player)

		for index = 1, 80 do
			MarketplaceService.ProcessReceipt(receipt(`davka-{index}`, player.UserId))
		end

		t.assert(#profile.Receipts > 0, "účtenky se nezapisují vůbec")
		t.assert(
			#profile.Receipts <= 32,
			`profil si pamatuje {#profile.Receipts} účtenek — seznam nemá strop`
		)

		--[[
			Nejnovější účtenka musí v seznamu zůstat. Kdyby se ořezával
			opačný konec, pamatoval by si profil ty nejstarší a opakované
			doručení té poslední — tedy přesně toho, co se opakuje —
			by prošlo.
		]]
		t.assert(
			table.find(profile.Receipts, "davka-80") ~= nil,
			"poslední účtenka ze seznamu vypadla"
		)
	end)

	product.ProductId = originalId
end
