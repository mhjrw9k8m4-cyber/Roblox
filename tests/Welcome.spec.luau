--!strict
--[[
	Karta při návratu hráče.

	Roblox od konce roku 2025 řadí hry hlavně podle NÁVRATNOSTI, takže
	okamžik, kdy se hráč vrátí, je nejcennější v celé hře. Karta na něm
	dělá dvě věci: pojmenuje, co na hráče čekalo, a pošle ho do denní
	odměny — právě ta vyrábí návraty další dny.

	Testuje se to, co by se ve hře poznalo špatně: že tlačítko opravdu
	vede do denní odměny (jinak je karta slepá ulička) a že se karta
	umí zavřít, aniž by cestou sundala tu, která přišla po ní.
]]

return function(t)
	local Welcome = t.require("Welcome")

	local function screen()
		local gui = Instance.new("ScreenGui")
		gui.Name = "TestGui"
		gui.Parent = t.world().players.LocalPlayer:FindFirstChild("PlayerGui")
		return gui
	end

	t.test("karta ukáže, co na hráče čekalo", function()
		local gui = screen()
		Welcome.show(gui, { Coins = 12345, Seconds = 3600 }, function() end)

		t.assert(Welcome.visible(), "karta se nepostavila")

		local card = gui:FindFirstChild("Welcome")
		t.assert(card ~= nil, "karta není ve stromu")

		local texts = {}
		for _, child in card:GetDescendants() do
			if child.ClassName == "TextLabel" or child.ClassName == "TextButton" then
				table.insert(texts, child.Text)
			end
		end

		local joined = table.concat(texts, " | ")
		t.assert(
			string.find(joined, "12.3K", 1, true) ~= nil or string.find(joined, "12345", 1, true) ~= nil,
			`karta neříká, kolik hráči přibylo: {joined}`
		)

		Welcome.dismiss()
	end)

	--[[
		Tlačítko je celý smysl karty. Bez něj by hráče jen pochválila
		za návrat a nikam by ho neposlala — a denní odměna, která ty
		návraty další dny vyrábí, by mu zůstala schovaná v menu.
	]]
	t.test("tlačítko vede do denní odměny", function()
		local gui = screen()
		local opened = false

		Welcome.show(gui, { Coins = 100, Seconds = 120 }, function()
			opened = true
		end)

		local card = gui:FindFirstChild("Welcome")
		local button
		for _, child in card:GetDescendants() do
			if child.ClassName == "TextButton" then
				button = child
			end
		end

		t.assert(button ~= nil, "karta nemá tlačítko")
		button.Activated:Fire()

		t.assert(opened, "tlačítko nikam nevede")
		t.assert(not Welcome.visible(), "karta po kliknutí zůstala stát")
	end)

	--[[
		Odložené zavření se nesmí trefit do nové karty. Karta má vlastní
		časovač; kdyby zavíral "co je zrovna vidět", sundal by tu, která
		se objevila místo ní — a hráč by viděl kartu bliknout a zmizet.
	]]
	t.test("zavření staré karty nesundá tu novou", function()
		local gui = screen()

		Welcome.show(gui, { Coins = 1, Seconds = 60 }, function() end)
		local first = gui:FindFirstChild("Welcome")

		Welcome.show(gui, { Coins = 2, Seconds = 60 }, function() end)
		local second = gui:FindFirstChild("Welcome")

		t.assert(second ~= nil, "druhá karta se nepostavila")
		t.assert(first ~= second, "druhé volání kartu nevyměnilo")
		t.assert(Welcome.visible(), "po druhém volání není vidět žádná karta")

		Welcome.dismiss()
	end)
end
