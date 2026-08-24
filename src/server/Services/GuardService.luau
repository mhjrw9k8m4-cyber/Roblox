--!strict
--[[
	Guard — omezovač volání nasazený na remote handlery.

	Bez něj může klient volat `RemoteFunction` tak rychle, jak stihne.
	Několik handlerů přitom zapisuje do DataStore (nákup hračky, denní
	odměna, rebirth, obchod), takže jeden hráč držící tlačítko vyčerpá
	kvótu zápisů pro celý server a ostatním se přestane ukládat.

	Limity jsou schválně velkorysé vůči člověku a přísné vůči skriptu:
	nikdo neklikne desetkrát za vteřinu, ale skript ano.

	Samotné počítání je v `Shared.Throttle` jako čisté funkce, aby šlo
	otestovat. Tady se řeší jen napojení na hráče a remoty.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Throttle = require(Shared.Throttle)

local Guard = {}

--[[
	Skupiny podle toho, co volání stojí.

	`Write` je nejpřísnější: každé takové volání může skončit zápisem
	do DataStore. `Cheap` jen čte paměť. `Social` posílá zprávy jiným
	hráčům, takže se hlídá kvůli obtěžování, ne kvůli výkonu.
]]
local LIMITS = {
	Write = Throttle.limit(12, 10),
	Cheap = Throttle.limit(40, 10),
	Social = Throttle.limit(8, 10),
	--[[
		`Burst` je na mačkání hračky: hráč ho pouští ručně a rychle, takže
		strop musí být vysoko nad tím, co stihne prst, a přitom pod tím,
		co by poslalo makro. Ekonomiku hlídá `Live.SqueezeRate` zvlášť —
		tenhle limit chrání server, ne příjem.
	]]
	Burst = Throttle.limit(120, 10),
}

local buckets: { [Player]: { [string]: Throttle.Bucket } } = {}

local function bucketsFor(player: Player)
	local existing = buckets[player]
	if existing then
		return existing
	end

	local fresh = {}
	buckets[player] = fresh
	return fresh
end

--[[
	Smí hráč zavolat `key`?

	Překročení se hlásí jen jednou za okno — hlásit každý pokus by při
	skriptu zaplavilo konzoli i hráči chat.
]]
function Guard.allow(player: Player, key: string, group: string): boolean
	local limit = LIMITS[group] or LIMITS.Cheap
	local mine = bucketsFor(player)

	if Throttle.allow(mine, key, limit, os.clock()) then
		return true
	end

	if Throttle.allow(mine, `warn_{key}`, Throttle.limit(1, limit.Window), os.clock()) then
		Remotes.Notify:FireClient(player, {
			Text = "Slow down a little.",
			Kind = "warn",
		})
	end

	return false
end

--[[
	Obalí `OnServerInvoke`. Zablokované volání vrací stejný tvar odpovědi
	jako odmítnutý nákup, aby to klient nemusel řešit zvlášť.
]]
function Guard.wrapFunction(remoteName: string, group: string, handler: (Player, ...any) -> any)
	Remotes[remoteName].OnServerInvoke = function(player: Player, ...)
		if not Guard.allow(player, remoteName, group) then
			return { Ok = false, Message = "Too many requests." }
		end
		return handler(player, ...)
	end
end

-- Obalí `OnServerEvent`. Zablokované volání se tiše zahodí.
function Guard.wrapEvent(remoteName: string, group: string, handler: (Player, ...any) -> ())
	Remotes[remoteName].OnServerEvent:Connect(function(player: Player, ...)
		if not Guard.allow(player, remoteName, group) then
			return
		end
		handler(player, ...)
	end)
end

function Guard.start()
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	-- Úklid pro dlouho běžící server: klíčů přibývá, okna zastarávají
	task.spawn(function()
		while true do
			task.wait(60)
			local now = os.clock()
			for _, mine in buckets do
				Throttle.prune(mine, LIMITS.Cheap, now)
			end
		end
	end)
end

return Guard
