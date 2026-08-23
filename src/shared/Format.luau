--!strict
--[[
	Format — čísla v grind hře rostou do miliard, musí se zkracovat
	čitelně: 12 400 -> "12.4K", 3 100 000 -> "3.1M".

	Zkratky jsou schválně anglické (K/M/B/T) — takhle to hráči z žánru
	znají a v UI to sedí k "+1 Power" stylu.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.short(value: number): string
	if value < 0 then
		return "-" .. Format.short(-value)
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local tier = math.clamp(math.floor(math.log(value, 1000)), 1, #SUFFIXES - 1)
	local scaled = value / 1000 ^ tier
	local text = if scaled >= 100 then string.format("%.0f", scaled) else string.format("%.1f", scaled)

	-- "12.0K" vypadá hůř než "12K"
	text = text:gsub("%.0$", "")

	return text .. SUFFIXES[tier + 1]
end

-- Přesné číslo s mezerami po tisících: 1234567 -> "1 234 567"
function Format.full(value: number): string
	local digits = tostring(math.floor(math.abs(value)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1\u{202F}"):reverse()
	grouped = grouped:gsub("^\u{202F}", "")
	return (if value < 0 then "-" else "") .. grouped
end

-- Sekundy -> "1:23:45" nebo "23:45"
function Format.time(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

function Format.multiplier(value: number): string
	local text = string.format("%.2f", value):gsub("0$", ""):gsub("%.$", "")
	return "×" .. text
end

return Format
