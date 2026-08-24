--!strict
--[[
	Zápis postupu v úkolech.

	Dvě různá pravidla: `progress` sečítá (prorazil jsi další zeď),
	`reach` bere maximum (dosáhl jsi řetězu N). Splést je znamená, že
	úkol jde splnit něčím jiným, než co má učit — proto vlastní testy.
]]

return function(t)
	local Live = t.require("Live")

	--[[
		Testuje se čistá logika obou pravidel proti stejné tabulce úkolů,
		jakou drží profil. Server ji používá přesně takhle.
	]]
	local function quests(): any
		return {
			{ Id = "Smash", Progress = 0, Target = 10, Claimed = false },
			{ Id = "Combo", Progress = 0, Target = 40, Claimed = false },
		}
	end

	local function add(list: any, questType: string, amount: number)
		for _, quest in list do
			local definition = Live.quest(quest.Id)
			if definition and definition.Type == questType and not quest.Claimed then
				if quest.Progress < quest.Target then
					quest.Progress = math.min(quest.Progress + amount, quest.Target)
				end
			end
		end
	end

	local function reach(list: any, questType: string, value: number)
		for _, quest in list do
			local definition = Live.quest(quest.Id)
			if definition and definition.Type == questType and not quest.Claimed then
				local capped = math.min(value, quest.Target)
				if capped > quest.Progress then
					quest.Progress = capped
				end
			end
		end
	end

	t.test("úkol na combo v Live existuje a je typu combo", function()
		local quest = Live.quest("Combo")
		t.assert(quest ~= nil, "úkol Combo chybí")
		t.equal((quest :: any).Type, "combo", "špatný typ")
	end)

	t.test("sečítací úkol se sečítá", function()
		local list = quests()
		add(list, "smash", 3)
		add(list, "smash", 4)
		t.equal(list[1].Progress, 7, "nesečetlo se")
	end)

	--[[
		Tohle je ten rozdíl, kvůli kterému `reach` vzniklo: kdyby se
		řetězy sečítaly, splnil by úkol i ten, komu řetěz pořád padá —
		a úkol má učit pravý opak.
	]]
	t.test("úkol na řetěz se NEsečítá", function()
		local list = quests()

		for _ = 1, 20 do
			reach(list, "combo", 5)
		end

		t.equal(list[2].Progress, 5, "dvacet krátkých řetězů úkol splnilo")
	end)

	t.test("úkol na řetěz bere nejvyšší dosažený", function()
		local list = quests()

		reach(list, "combo", 12)
		reach(list, "combo", 30)
		-- Pád řetězu nesmí postup sebrat
		reach(list, "combo", 2)

		t.equal(list[2].Progress, 30, "maximum se neudrželo")
	end)

	t.test("žádné pravidlo nepřeleze cíl", function()
		local list = quests()

		add(list, "smash", 9999)
		reach(list, "combo", 9999)

		t.equal(list[1].Progress, list[1].Target, "součet přelezl cíl")
		t.equal(list[2].Progress, list[2].Target, "maximum přelezlo cíl")
	end)

	t.test("splněný úkol se už nemění", function()
		local list = quests()
		list[2].Claimed = true

		reach(list, "combo", 40)
		t.equal(list[2].Progress, 0, "zapsalo se do vyzvednutého úkolu")
	end)

	--[[
		Cíl úkolu roste se světem. U comba by ale přerostl strop řetězu
		a hráč by celý den koukal na úkol, který nejde dodělat.
	]]
	t.test("cíl každého úkolu je dosažitelný ve všech světech", function()
		local Combo = t.require("Combo")
		local Config = t.require("Config")

		for _, quest in Live.Quests do
			for world = 1, #Config.Worlds do
				local scale = 1 + (world - 1) * quest.Scale
				local target = math.max(math.floor(quest.Base * scale), 1)

				--[[
					Testuje se SUROVÉ číslo z Live, ne oříznuté. Server cíl
					sice zastropuje, ale kdyby test kontroloval až výsledek
					ořezu, nemohl by nikdy selhat — a nesmyslné číslo v Live
					by prošlo bez povšimnutí.
				]]
				if quest.Type == "combo" then
					t.assert(
						target <= Combo.Max,
						`{quest.Id} ve světě {world}: cíl {target} je nad stropem řetězu {Combo.Max}`
					)
				end

				t.assert(target >= 1, `{quest.Id} ve světě {world}: nulový cíl`)
			end
		end
	end)

	t.test("každý typ úkolu má někde svůj zápis", function()
		-- Úkol, který nikdo nikdy nezapíše, se nedá splnit. Seznam
		-- odpovídá volání progress()/reach() na serveru.
		local written = {
			smash = true, collect = true, clear = true,
			spend = true, hatch = true, upgrade = true, combo = true,
		}

		for _, quest in Live.Quests do
			t.assert(written[quest.Type], `typ {quest.Type} nikdo nezapisuje — úkol nejde splnit`)
		end
	end)
end
