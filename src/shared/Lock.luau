--!strict
--[[
	Lock — logika zámku profilu, oddělená od DataStore.

	Proč vlastní modul: tohle je nejchoulostivější kód v projektu. Chyba
	tady znamená ztracený postup hráče, a přitom se to nedá vyzkoušet
	klikáním — museli by se sejít dva servery ve správný okamžik.

	Oddělené jsou proto čisté funkce bez jediného síťového volání: berou
	záznam a čas, vracejí rozhodnutí. Takové se dají otestovat mimo Roblox
	(viz `tools/test.py`), a to je jediná cesta, jak si být jistý, že
	sedí i hraniční případy.
]]

local Lock = {}

-- Zámek starší než tohle se považuje za mrtvý (server spadl)
Lock.StaleSeconds = 150
-- Jak často se obnovuje; musí být pohodlně míň než StaleSeconds
Lock.RefreshSeconds = 45

export type Stamp = {
	JobId: string,
	At: number,
}

export type Record = {
	Data: any,
	Lock: Stamp?,
}

--[[
	Sjednotí starý i nový tvar záznamu.

	Profily uložené před zavedením zámku mají data přímo na nejvyšší
	úrovni. Poznají se podle toho, že nemají `Data` ani `Lock` — bez
	tohohle převodu by všichni stávající hráči přišli o postup.
]]
function Lock.toRecord(raw: any): Record
	if typeof(raw) ~= "table" then
		return { Data = nil, Lock = nil }
	end
	if raw.Data == nil and raw.Lock == nil then
		return { Data = raw, Lock = nil }
	end
	return { Data = raw.Data, Lock = raw.Lock }
end

--[[
	Drží zámek někdo jiný?

	Vlastní zámek nikdy neblokuje — server, který se znovu připojuje ke
	svému profilu (třeba po chybě sítě), nesmí sám sebe vyhodit.
]]
function Lock.heldByOther(record: Record, jobId: string, now: number): boolean
	local stamp = record.Lock
	if not stamp then
		return false
	end
	if stamp.JobId == jobId then
		return false
	end
	return now - stamp.At < Lock.StaleSeconds
end

-- Je zámek natolik starý, že ho má smysl obnovit?
function Lock.needsRefresh(lastAt: number?, now: number): boolean
	if not lastAt then
		return true
	end
	return now - lastAt >= Lock.RefreshSeconds
end

function Lock.stamp(jobId: string, now: number): Stamp
	return { JobId = jobId, At = now }
end

--[[
	Identita serveru. Ve Studiu je `JobId` prázdný, takže by dvě spuštění
	vypadala jako jeden server a zámek by nikdy nic nechytil.
]]
function Lock.jobId(realJobId: string, fallbackSeed: number): string
	if realJobId ~= "" then
		return realJobId
	end
	return `studio-{math.floor(fallbackSeed * 1000)}`
end

return Lock
