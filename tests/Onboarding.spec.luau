--!strict
--[[
	Nápověda pro nové hráče.

	Chyba v ní se pozná jediným způsobem: hráč krok nikdy neuvidí — a to
	nikdo nenahlásí. Přesně to se v projektu už jednou stalo, když
	nápověda končila po prvním průrazu a poslední krok nešel zobrazit.

	Testují se proto dvě věci z opačných konců: na začátku nesmí být
	splněný ani jeden krok, na konci musí být splněné všechny.
]]

return function(t)
	local Onboarding = t.require("Onboarding")
	local Config = t.require("Config")
	local Combo = t.require("Combo")

	local STEPS = Onboarding.Steps

	t.test("kroky mají jedinečné id a text", function()
		t.assert(#STEPS > 0, "nápověda nemá jediný krok")

		local seen = {}
		for index, step in STEPS do
			t.assert(not seen[step.Id], `dvakrát krok {step.Id}`)
			seen[step.Id] = true

			t.assert(#step.Text > 0, `krok {index} nemá text`)
			t.assert(typeof(step.Done) == "function", `krok {step.Id} nemá podmínku`)
		end
	end)

	--[[
		Nováček nesmí mít splněný ani jeden krok. Kdyby měl, nápověda by
		ten krok přeskočila hned na startu a mechanika, kterou učí, by
		zůstala neobjevená.
	]]
	t.test("nováčkovi se neodškrtne žádný krok předem", function()
		local fresh = {
			Power = 0,
			Coins = 0,
			Barrier = 1,
			WorldIndex = 1,
			Rebirths = 0,
			Smashes = 0,
			Squeezes = 0,
			Upgrades = {},
			Boosts = {},
			Perks = {},
			Laps = {},
			Passes = {},
			Held = { "Blob" },
			Worlds = { [Config.Worlds[1].Id] = true },
		}

		for _, step in STEPS do
			t.assert(not step.Done(fresh), `krok {step.Id} je splněný hned na startu`)
		end
	end)

	--[[
		A z druhé strany: zkušený hráč musí mít splněné všechno, jinak
		mu nápověda visí na obrazovce navždy.
	]]
	t.test("zkušený hráč má splněné všechny kroky", function()
		local veteran = {
			Power = 1e12,
			Coins = 1e12,
			Barrier = 1,
			WorldIndex = 1,
			Rebirths = 4,
			Smashes = 500,
			Squeezes = 900,
			Chain = Combo.Max,
			Upgrades = { Power = 12 },
			Boosts = {},
			Perks = {},
			Laps = {},
			Passes = {},
			Held = { "Blob" },
			Worlds = { [Config.Worlds[1].Id] = true },
		}

		for _, step in STEPS do
			t.assert(step.Done(veteran), `krok {step.Id} nejde splnit ani po pěti stech průrazech`)
		end
	end)

	--[[
		Krok o mačkání se nesmí zaseknout hráči, který si hračku odložil.
		Bez téhle úlevy by mu nápověda zůstala viset u pokynu, který
		nemá jak splnit.
	]]
	t.test("bez hračky v ruce se mačkání neblokuje", function()
		local empty = {
			Power = 0,
			Smashes = 1,
			Squeezes = 0,
			Held = {},
			Upgrades = {},
			Barrier = 1,
			WorldIndex = 1,
			Rebirths = 0,
			Boosts = {},
			Perks = {},
			Laps = {},
			Passes = {},
			Worlds = { [Config.Worlds[1].Id] = true },
		}

		for _, step in STEPS do
			if step.Id == "squeeze" then
				t.assert(step.Done(empty), "nápověda na mačkání se zasekne bez hračky")
			end
		end
	end)
end
