--!strict
--[[
	Throttle — omezovač počtu volání, jako čisté funkce.

	Proč to hra potřebuje: `RemoteFunction` může klient volat tak rychle,
	jak stihne. Několik handlerů přitom zapisuje do DataStore — nákup
	hračky, vyzvednutí denní odměny, rebirth. Hráč, který drží tlačítko
	(nebo si napíše skript), tím vyčerpá kvótu zápisů pro celý server
	a ostatním se přestane ukládat.

	Rate limiting u střílečky bývá o podvádění. Tady je hlavně o tom,
	aby jeden hráč nepoložil ukládání všem.

	Použitý model je "sliding window" zjednodušený na počítadlo s pevným
	oknem: počítá se, kolik volání přišlo v aktuálním okně, a po jeho
	vypršení se začíná od nuly. Přesnější klouzavé okno by muselo držet
	časy jednotlivých volání — na tohle je to zbytečné.
]]

local Throttle = {}

export type Bucket = {
	Count: number,
	Since: number,
}

export type Limit = {
	Max: number,
	Window: number,
}

--[[
	Vytvoří pravidlo: nejvýš `max` volání za `window` sekund.
]]
function Throttle.limit(max: number, window: number): Limit
	return { Max = max, Window = window }
end

--[[
	Smí volání projít?

	`buckets` je tabulka, kterou si drží volající (typicky na hráče).
	Funkce ji mění, ale nic jiného nedělá — žádné síťování ani čas
	zevnitř, aby šla otestovat.
]]
function Throttle.allow(buckets: { [string]: Bucket }, key: string, limit: Limit, now: number): boolean
	local bucket = buckets[key]

	if not bucket or now - bucket.Since >= limit.Window then
		buckets[key] = { Count = 1, Since = now }
		return true
	end

	bucket.Count += 1
	return bucket.Count <= limit.Max
end

--[[
	Kolik volání ještě zbývá. Slouží hlavně testům a ladění — hra sama
	se ptá jen `allow`.
]]
function Throttle.remaining(buckets: { [string]: Bucket }, key: string, limit: Limit, now: number): number
	local bucket = buckets[key]
	if not bucket or now - bucket.Since >= limit.Window then
		return limit.Max
	end
	return math.max(limit.Max - bucket.Count, 0)
end

--[[
	Zapomene stará okna.

	Bez úklidu by tabulka rostla s každým klíčem, který kdy někdo použil.
	U hráče, který se odpojí, se maže celá jeho tabulka; tohle je pro
	dlouho běžící server, kde přibývají klíče.
]]
function Throttle.prune(buckets: { [string]: Bucket }, limit: Limit, now: number)
	for key, bucket in buckets do
		if now - bucket.Since >= limit.Window * 2 then
			buckets[key] = nil
		end
	end
end

return Throttle
