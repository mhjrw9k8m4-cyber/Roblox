--!strict
--[[
	Testy zámku profilu.

	Tohle je jediný kód v projektu, který se nedá ověřit hraním: aby se
	chyba projevila, musely by se dva servery sejít ve správný okamžik.
	Proto je logika oddělená do čistých funkcí a testuje se tady.
]]

return function(t)
	local Lock = t.require("src/shared/Lock.luau")

	local NOW = 1000000
	local ME = "server-a"
	local OTHER = "server-b"

	-- Převod starého tvaru ------------------------------------------------

	t.test("starý profil bez zámku se načte jako data", function()
		local record = Lock.toRecord({ Coins = 500, Gems = 3 })
		t.equal(record.Data.Coins, 500, "data zůstala")
		t.equal(record.Lock, nil, "zámek chybí")
	end)

	t.test("nový tvar se rozloží správně", function()
		local record = Lock.toRecord({
			Data = { Coins = 700 },
			Lock = { JobId = OTHER, At = NOW },
		})
		t.equal(record.Data.Coins, 700, "data")
		t.equal(record.Lock.JobId, OTHER, "zámek")
	end)

	t.test("prázdný klíč nespadne", function()
		local record = Lock.toRecord(nil)
		t.equal(record.Data, nil, "žádná data")
		t.equal(record.Lock, nil, "žádný zámek")
	end)

	--[[
		Hraniční případ, kvůli kterému to celé existuje: profil uložený
		PŘED zavedením zámku má pole `Data` roven nil. Kdyby se rozpoznával
		podle přítomnosti `Data`, tenhle by se načetl jako prázdný a hráč
		by přišel o postup.
	]]
	t.test("starý profil s polem jménem Lock se nesplete s novým", function()
		local record = Lock.toRecord({ Coins = 12, Lock = { JobId = ME, At = NOW } })
		t.equal(record.Data, nil, "tvar s Lock se bere jako nový")
	end)

	-- Rozhodnutí o zámku ---------------------------------------------------

	t.test("volný profil se dá vzít", function()
		local record = { Data = {}, Lock = nil }
		t.equal(Lock.heldByOther(record, ME, NOW), false, "nic nedrží")
	end)

	t.test("živý cizí zámek blokuje", function()
		local record = { Data = {}, Lock = { JobId = OTHER, At = NOW - 10 } }
		t.equal(Lock.heldByOther(record, ME, NOW), true, "blokováno")
	end)

	t.test("vlastní zámek neblokuje sám sebe", function()
		-- Server, který se po výpadku sítě vrací ke svému profilu,
		-- se nesmí vyhodit vlastním zámkem.
		local record = { Data = {}, Lock = { JobId = ME, At = NOW - 10 } }
		t.equal(Lock.heldByOther(record, ME, NOW), false, "vlastní projde")
	end)

	t.test("mrtvý zámek jde převzít", function()
		local record = { Data = {}, Lock = { JobId = OTHER, At = NOW - Lock.StaleSeconds - 1 } }
		t.equal(Lock.heldByOther(record, ME, NOW), false, "starý zámek nedrží")
	end)

	t.test("zámek přesně na hranici ještě drží", function()
		local record = { Data = {}, Lock = { JobId = OTHER, At = NOW - Lock.StaleSeconds + 1 } }
		t.equal(Lock.heldByOther(record, ME, NOW), true, "těsně pod limitem drží")
	end)

	-- Obnovování ------------------------------------------------------------

	t.test("obnovení je potřeba, když se ještě neukládalo", function()
		t.equal(Lock.needsRefresh(nil, NOW), true, "bez značky vždycky")
	end)

	t.test("čerstvý zámek se neobnovuje", function()
		t.equal(Lock.needsRefresh(NOW - 1, NOW), false, "před chvílí")
	end)

	t.test("zámek se obnoví dřív, než stihne zestárnout", function()
		-- Tohle je ta podmínka, na které celý zámek stojí: interval
		-- obnovování musí být pohodlně menší než doba zestárnutí,
		-- jinak si server nechá vypršet vlastní zámek.
		t.assert(Lock.RefreshSeconds * 2 < Lock.StaleSeconds,
			"mezi obnovami se musí vejít aspoň dva pokusy")
	end)

	-- Identita serveru --------------------------------------------------------

	t.test("skutečné JobId se použije beze změny", function()
		t.equal(Lock.jobId("abc-123", 5), "abc-123", "beze změny")
	end)

	t.test("ve Studiu se vyrobí náhradní identita", function()
		local first = Lock.jobId("", 1.5)
		local second = Lock.jobId("", 2.5)
		t.assert(first ~= second, "dvě spuštění musí být rozlišitelná")
	end)
end
