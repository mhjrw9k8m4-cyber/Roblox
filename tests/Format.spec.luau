--!strict
--[[
	Formátování čísel.

	Čísla ve hře přeskakují mezi jednotkami a desítkami bilionů, takže
	pravidlo "kolik desetin ukázat" nemůže být pro celý rozsah jedno.
	Testuje se hlavně to, že se nikde neztratí ta část, která něco říká.
]]

return function(t)
	local Format = t.require("Format")

	t.test("malý násobek si nechá desetinu, velký ne", function()
		t.equal(Format.gain(2.7), "×2.7", "u malého čísla zmizela desetina")
		t.equal(Format.gain(1.5), "×1.5", "u malého čísla zmizela desetina")
		t.equal(Format.gain(28.46), "×28", "velký násobek zůstal nečitelný")
		t.equal(Format.gain(812.3), "×812", "velký násobek zůstal nečitelný")
	end)

	--[[
		Hranice se zkouší z obou stran. Kdyby bylo porovnání obrácené,
		projde půlka případů dál a rozdíl by šlo přehlédnout.
	]]
	t.test("hranice deseti platí přesně", function()
		t.equal(Format.gain(9.99), "×9.99", "pod hranicí se má ukázat desetina")
		t.equal(Format.gain(10), "×10", "na hranici se má ukázat celé číslo")
	end)

	t.test("celé číslo nemá zbytečnou nulu", function()
		t.equal(Format.gain(2), "×2", "u dvojky přebývá desetina")
		t.equal(Format.multiplier(1), "×1", "u jedničky přebývá desetina")
	end)

	t.test("krátký zápis drží řády", function()
		t.equal(Format.short(999), "999", "pod tisícem se nemá zkracovat")
		t.equal(Format.short(1000), "1K", "tisíc se má zkrátit")
		t.equal(Format.short(1500), "1.5K", "ztratila se desetina")
		t.equal(Format.short(1000000), "1M", "milion se má zkrátit")
	end)
end
