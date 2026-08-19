--!strict
-- Settings > Slot. Shows what the inventory charInfoUI does NOT: kills, elo,
-- lives, credits, cards, flags, and the account-wide combat counters.
--
-- Numbers arrive by PULL (plrObj:requestSlotInfo -> S2C.SlotInfo). plrStats ticks
-- on every single hit, so there is deliberately no live push for any of this; the
-- page asks once per open and the server rate-gates the ask.
local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local plrObj = clientData.plrObj

local frame = script.Parent
local list  = frame:WaitForChild("ScrollingFrame")

local rowTemplate    = script:WaitForChild("row")
local headerTemplate = script:WaitForChild("header")
local chartTemplate  = script:WaitForChild("chart")
local segTemplate    = script:WaitForChild("seg")
local keyTemplate    = script:WaitForChild("keyitem")

-- parried / blocked / dodged / damage, in the order the server sends each group.
-- Saturated so parry gold and damage red read as themselves rather than pastel.
local STAT_COLORS = {
	Color3.fromHex("dcab3c"),
	Color3.fromHex("5697e6"),
	Color3.fromHex("52c47d"),
	Color3.fromHex("de4f4f"),
}

local isOpen = false
local order = 0

local function clear()
	order = 0
	for _, v in pairs(list:GetChildren()) do
		-- UIListLayout / UIPadding are not GuiObjects, so they survive this
		if v:IsA("GuiObject") then game.Debris:AddItem(v, 0) end
	end
end

local function comma(v: any): string
	local n = math.floor(tonumber(v) or 0)
	local s = tostring(math.abs(n))
	local k
	repeat
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return (if n < 0 then "-" else "") .. s
end

local function duration(v: any): string
	local s = math.floor(tonumber(v) or 0)
	if s <= 0 then return "0m" end
	-- sub-minute used to floor to "0m", which reads as broken on a live session
	if s < 60 then return s .. "s" end
	local d = s // 86400
	local h = (s % 86400) // 3600
	local m = (s % 3600) // 60
	if d > 0 then return d .. "d " .. h .. "h" end
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

local function dateOf(v: any): string
	local n = tonumber(v)
	if n == nil or n <= 0 then return "-" end
	return os.date("!%d %b %Y", n) :: string
end

local function ratio(a: any, b: any): string
	local kills  = tonumber(a) or 0
	local deaths = tonumber(b) or 0
	if deaths <= 0 then return string.format("%.2f", kills) end
	return string.format("%.2f", kills / deaths)
end

local function addHeader(text: string)
	local h = headerTemplate:Clone()
	h.title.Text = text
	h.LayoutOrder = order
	order += 1
	h.Visible = true
	h.Parent = list
end

local function addRow(key: string, val: string)
	local r = rowTemplate:Clone()
	r.key.Text = key
	r.val.Text = val
	r.LayoutOrder = order
	order += 1
	r.Visible = true
	r.Parent = list
end

local function sumDmg(rows: {any}?): number
	local t = 0
	for _, r in ipairs(rows or {}) do t += (tonumber(r[3]) or 0) end
	return t
end

-- Whole percents that always add to exactly 100 (largest remainder). Rounding each
-- share on its own overshoots -- four values at 12.5/12.5/37.5/37.5 print 102 --
-- and just deriving the last one from the rest dumps the whole error onto it, so
-- equal values come out as different percents. This spreads it by remainder.
local function sharePercents(rows: {any}, total: number): {number}
	local out, floors, rem = {}, 0, {}
	for i, r in ipairs(rows) do
		local exact = (tonumber(r[3]) or 0) / total * 100
		out[i] = math.floor(exact)
		floors += out[i]
		rem[i] = { i = i, frac = exact - out[i] }
	end
	table.sort(rem, function(a, b)
		if a.frac == b.frac then return a.i < b.i end
		return a.frac > b.frac
	end)
	for k = 1, math.min(#rem, 100 - floors) do
		out[rem[k].i] += 1
	end
	return out
end

-- One 100%-stacked bar. Share-of-total, not raw damage, so the two bars are always
-- the same length and the eye compares shape instead of scale.
local function addChart(titleText: string, rows: {any}?, total: number)
	if total <= 0 then return end

	local c = chartTemplate:Clone()
	c.title.Text = titleText
	c.total.Text = comma(total) .. " dmg"
	c.LayoutOrder = order
	order += 1

	local pcts = sharePercents(rows or {}, total)
	for i, r in ipairs(rows or {}) do
		local v = tonumber(r[3]) or 0

		-- exact fraction for the width, so the segments always fill the bar
		local sg = segTemplate:Clone()
		sg.BackgroundColor3 = STAT_COLORS[i] or Color3.new(1, 1, 1)
		sg.Size = UDim2.new(v / total, 0, 1, 0)
		sg.LayoutOrder = i
		sg.Visible = true
		sg.Parent = c.bar

		local pct = pcts[i]

		local k = keyTemplate:Clone()
		k.dot.BackgroundColor3 = sg.BackgroundColor3
		k.label.Text = tostring(r[1]) .. "  " .. pct .. "%"
		k.LayoutOrder = i
		k.Visible = true
		k.Parent = c.key
	end

	c.Visible = true
	c.Parent = list
end

local function render(info: any)
	clear()
	if info == nil then
		addHeader("loading...")
		return
	end

	local live = info.live or {}
	local acct = info.acct or {}
	local data = plrObj.Data
	local slotData = if data then data.slots[plrObj.loadedSlotId] else nil

	addHeader("CHARACTER")
	if slotData then addRow("Name", tostring(slotData.name)) end
	-- slot.wins IS the kill counter: processElo credits it to the top-damage killer
	addRow("Kills",    comma(live.kills))
	addRow("Deaths",   comma(live.loss))
	addRow("K/D",      ratio(live.kills, live.loss))
	addRow("Elo",      comma(live.elo))
	addRow("Lives",    comma(live.lives))
	addRow("Credits",  comma(live.credits))
	addRow("Progress", comma(live.prog))
	addRow("Created",  dateOf(live.first))
	addRow("Seed",     tostring(live.seed or "-"))

	-- PlrData.plrStats is account level, not per slot. Say so rather than letting
	-- it read as this character's record. Whole section hides until there's a
	-- fight to describe, same as the site does.
	local takenTotal = sumDmg(info.taken)
	local dealtTotal = sumDmg(info.dealt)
	if takenTotal > 0 or dealtTotal > 0 then
		addHeader("COMBAT  -  account, all characters")
		addChart("What happened to you", info.taken, takenTotal)
		addChart("What you did to them", info.dealt, dealtTotal)
		addRow("Feints",         comma(info.feints))
		addRow("Ability Feints", comma(info.feint2s))
	end

	addHeader("ACCOUNT")
	addRow("Elo",          comma(acct.elo))
	addRow("Wins",         comma(acct.wins))
	addRow("Losses",       comma(acct.loss))
	addRow("Playtime",     duration(acct.playtime))
	addRow("First Joined", dateOf(acct.first))

	-- cards live in the inventory info panel now, not here

	addHeader("FLAGS")
	for _, f in ipairs(info.flags or {}) do
		addRow(f[1], if f[2] then "yes" else "no")
	end
end

-- ONE persistent connection, made at require time. Connecting inside open() is
-- what makes a page stack a listener per open.
plrObj.slotInfoRecieved:Connect(function(info)
	if isOpen then render(info) end
end)

return {
	order = 0,        -- leftmost
	default = true,   -- and what the window focuses when opened with nothing up
	available = false, -- no tab until a slot is actually loaded

	-- The "Slot tab follows the loaded slot" rule lives HERE, so the terminal and
	-- the bootstrap stay ignorant of slots entirely.
	init = function(ctx)
		plrObj.slotLoaded:Connect(function() ctx.setAvailable(true) end)
		-- server re-sends PlrData on every CharacterAdded, which zeroes
		-- loadedSlotId and drops the player back to the menu
		plrObj.slotUnloaded:Connect(function() ctx.setAvailable(false) end)
		if plrObj:IsSlotLoaded() then ctx.setAvailable(true) end
	end,

	open = function()
		isOpen = true
		render(plrObj.slotInfo)
		plrObj:requestSlotInfo()
	end,

	close = function()
		isOpen = false
		clear() -- don't hold ~40 frames alive while the page is shut
	end,
}
