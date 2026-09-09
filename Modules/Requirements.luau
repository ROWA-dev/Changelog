--!strict
--[[
	Requirements - one gate shape for weapons, cards, anything gated on a slot.
	Server-only today; lives here so the client needs no second shape.

	FLAT: stat names are unique across weaponStats / baseStats / elements. The
	registry warns at load if that ever stops being true, so a collision is a
	startup failure, never a silent mis-gate.
	Every entry is a minimum (>=); entries in one table are AND.

	    req = { hvy = 2 }
	    req = { Or = { {hvy = 2}, {strength = 6} } }
	    req = { card = 13 }     -- owns that CARD
	    req = { ability = 1 }   -- owns that ABILITY, i.e. an upgrade's base move
	                            -- Both OWNERSHIP gates read the slot's own
	                            -- containers, so they are server-side only.
	    req = { sum = { weaponStats = 4 } }
	                            -- TOTAL invested across a whole track, for gates
	                            -- that want spread rather than one deep stat.
	                            -- Tracks: baseStats, weaponStats, elements.
	    req = {}    -- FREE. `nil` is NOT free: class statics inherit through
	                -- __index, so nil picks up the family's req.

	An unknown stat name is UNSATISFIABLE, never skipped: a typo locks the gate
	rather than opening it.
]]

local ElementRegistry = require(game.ReplicatedStorage.Modules.ElementRegistry)

export type req = {
	[string]: number,
	minLevel: number?,
	maxLevel: number?,
	card: number?,
	ability: number?,
	sum: {[string]: number}?,
	-- Luau types an array literal from its FIRST element, so a mixed
	-- {{hvy=2},{med=2}} needs `:: {Requirements.req}` at the authoring site.
	And: {req}?,
	Or:  {req}?,
}

local module = {}

-- registry values: string = which track owns it, false = operator key, nil = unknown.
local OPS = {minLevel = false, maxLevel = false, And = false, Or = false, card = false, ability = false, sum = false}
local TRACK: {[string]: any}? = nil

--- id -> display name, PUSHED by each registry at load: Requirements is shared code
--- and both registries are ServerStorage, so nothing here requires them.
local namers: {[string]: (number) -> string} = {}
function module.setNamer(kind: string, fn: (number) -> string)
	namers[kind] = fn
end

local function nameOf(kind: string, id: number): string
	local fn = namers[kind]
	if fn == nil then return kind .. " #" .. tostring(id) end
	local ok, name = pcall(fn, id)
	return if ok and typeof(name) == "string" then name else kind .. " #" .. tostring(id)
end

--- OWNERSHIP gates. Cards are a SparseBitSet on the slot, abilities are items in its
--- containers; a client slot has neither, which is what makes these server-side only.
local function ownsCard(slot: any, id: number): boolean
	local cards = slot and slot.cards
	return cards ~= nil and cards:getIndex(id) == true
end

local function ownsAbility(slot: any, id: number): boolean
	return slot ~= nil and slot.hasAbility ~= nil and slot:hasAbility(id) == true
end

--- name -> track, DERIVED from the stat classes so a new stat teaches this for free.
--  Built on FIRST USE, not at load: Requirements loads on every HumObj.
local function tracks(): {[string]: any}
	if TRACK then return TRACK end
	local t: {[string]: any} = {}
	local sreq: any = require
	local slotDir = game.ReplicatedStorage.Class.plrObjClient.slot
	local function add(name: string, track: string)
		if t[name] ~= nil then
			warn("[Requirements] stat '" .. name .. "' is declared by two tracks ("
				.. tostring(t[name]) .. ", " .. track .. "); flat reqs need unique names")
		end
		t[name] = track
	end
	for name in pairs(sreq(slotDir.weaponStats).new()) do add(name, "weaponStats") end
	for name in pairs(sreq(slotDir.baseStats).new()) do add(name, "baseStats") end
	for _, name in ipairs(ElementRegistry) do add(name, "elements") end
	for k, v in pairs(OPS) do t[k] = v end
	TRACK = t
	return t
end

--- fn(name, amount, track, ctx) over this level's stat leaves; truthy fn stops and returns it.
--  track is nil for an unknown name, so every caller decides how to fail.
local function eachLeaf(req: req, fn: (string, any, any, any) -> any, ctx: any?): any
	local T = tracks()
	for name, amount in pairs(req) do
		local track = T[name]
		if track ~= false then
			local hit = fn(name, amount, track, ctx)
			if hit then return hit end
		end
	end
	return nil
end

--- what `slot` owns of one stat. nil slot = nothing.
local function statOf(slot: any, track: string, name: string): number
	if slot == nil then return 0 end
	if track == "elements" then
		local elems = slot.elements
		return (elems and elems:Get(name)) or 0
	end
	local tbl = slot[track]
	local v = tbl and (tbl :: any)[name]
	return if typeof(v) == "number" then v else 0
end

local function suffix(track: any): string
	return if track == "elements" then " element" else ""
end

--- TRACK TOTALS for the `sum` op. An unknown track name sums to nothing and the gate
--- never opens, same rule as an unknown stat name.
local TRACK_LABEL = {baseStats = "base stats", weaponStats = "weapon stats", elements = "elements"}

--- sums the track's REGISTERED stats through statOf, rather than reading the slot a
--- second way: one place knows how a track is stored, and a stat class that grows a
--- non-stat number cannot silently inflate a gate.
local function trackSum(slot: any, track: string): number
	if slot == nil or TRACK_LABEL[track] == nil then return 0 end
	local total = 0
	for name, owner in pairs(tracks()) do
		if owner == track then total += statOf(slot, track, name) end
	end
	return total
end

local function sumUnmet(slot: any, sums: {[string]: number}): boolean
	for track, amount in pairs(sums) do
		if trackSum(slot, track) < amount then return true end
	end
	return false
end

--- hoisted eachLeaf bodies, so check allocates no closure per call.
local function unmet(name: string, amount: number, track: any, slot: any): boolean
	if track == nil then return true end
	return statOf(slot, track, name) < amount
end
local function pushWant(name: string, amount: number, track: any, parts: {string})
	table.insert(parts, amount .. " " .. name .. suffix(track))
end

--- true if `slot` satisfies `req`. nil req is free.
function module.check(slot: any, req: req?): boolean
	if req == nil then return true end

	if eachLeaf(req, unmet, slot) then return false end

	local lvl = (slot and slot.lvl) or 0
	if req.minLevel and lvl < req.minLevel then return false end
	if req.maxLevel and lvl > req.maxLevel then return false end
	if req.card and not ownsCard(slot, req.card) then return false end
	if req.ability and not ownsAbility(slot, req.ability) then return false end
	if req.sum and sumUnmet(slot, req.sum) then return false end

	if req.And then
		for _, sub in ipairs(req.And) do
			if not module.check(slot, sub) then return false end
		end
	end
	if req.Or then
		local hit = false
		for _, sub in ipairs(req.Or) do
			if module.check(slot, sub) then hit = true break end
		end
		if not hit then return false end
	end
	return true
end

--- human string for tooltips. "" when the req is free, so callers can test it.
function module.describe(req: req?): string
	if req == nil then return "" end
	local parts = {}

	eachLeaf(req, pushWant, parts)

	if req.minLevel then table.insert(parts, "lvl " .. req.minLevel .. "+") end
	if req.maxLevel then table.insert(parts, "lvl " .. req.maxLevel .. "-") end
	if req.card then table.insert(parts, nameOf("card", req.card)) end
	if req.ability then table.insert(parts, nameOf("ability", req.ability)) end
	if req.sum then
		for track, amount in pairs(req.sum) do
			table.insert(parts, amount .. " across " .. (TRACK_LABEL[track] or track))
		end
	end

	if req.And then
		for _, sub in ipairs(req.And) do
			local s = module.describe(sub)
			if s ~= "" then table.insert(parts, s) end
		end
	end
	if req.Or then
		local any = {}
		for _, sub in ipairs(req.Or) do
			local s = module.describe(sub)
			if s ~= "" then table.insert(any, s) end
		end
		if #any > 0 then table.insert(parts, "(" .. table.concat(any, " or ") .. ")") end
	end
	return table.concat(parts, ", ")
end

--- every unmet leaf as "hvy 0 -> 2", have vs need. nil EXACTLY when check passes.
function module.missing(slot: any, req: req?): string?
	if req == nil or module.check(slot, req) then return nil end
	local parts = {}

	eachLeaf(req, function(name, amount, track)
		if track == nil then
			table.insert(parts, "unknown stat '" .. name .. "'")
			return
		end
		local have = statOf(slot, track, name)
		if have < amount then
			table.insert(parts, name .. suffix(track) .. " " .. have .. " -> " .. amount)
		end
	end)

	local lvl = (slot and slot.lvl) or 0
	if req.minLevel and lvl < req.minLevel then
		table.insert(parts, "lvl " .. lvl .. " -> " .. req.minLevel)
	end
	-- maxLevel was checked by `check` but never REPORTED here, so an over-levelled
	-- gate fell through to quoting itself. Same shape as the line above.
	if req.maxLevel and lvl > req.maxLevel then
		table.insert(parts, "lvl " .. lvl .. " -> " .. req.maxLevel .. " max")
	end
	if req.card and not ownsCard(slot, req.card) then
		table.insert(parts, "the " .. nameOf("card", req.card) .. " card")
	end
	if req.ability and not ownsAbility(slot, req.ability) then
		table.insert(parts, "the " .. nameOf("ability", req.ability) .. " ability")
	end
	if req.sum then
		for track, amount in pairs(req.sum) do
			local have = trackSum(slot, track)
			if have < amount then
				table.insert(parts, (TRACK_LABEL[track] or track) .. " " .. have .. " -> " .. amount)
			end
		end
	end
	if req.And then
		for _, sub in ipairs(req.And) do
			local s = module.missing(slot, sub)
			if s then table.insert(parts, s) end
		end
	end

	-- an Or has no single gap to point at, so quote the whole gate instead
	if #parts == 0 then return module.describe(req) end
	return table.concat(parts, ", ")
end

--- STRUCTURED `missing`, for a UI that draws bars instead of a sentence.
--- One row per leaf. `stat` is the name to colour by, nil on rows that are not a stat.
--- `have` is nil EXACTLY when the caller cannot evaluate the row: ownership reads the
--- slot's own containers, which a client slot does not have, so a client must render
--- those neutrally rather than as unmet.
export type gateRow = {
	label: string,
	stat: string?,
	have: number?,
	need: number,
	met: boolean,
}

local function pushGate(name: string, amount: number, track: any, ctx: any)
	-- unknown stat is unsatisfiable, same rule as check
	local have = if track == nil then 0 else statOf(ctx.slot, track, name)
	table.insert(ctx.out, {
		label = name .. suffix(track),
		stat = if track == nil then nil else name,
		have = have,
		need = amount,
		met = have >= amount,
	})
end

function module.breakdown(slot: any, req: req?): {gateRow}
	local out: {gateRow} = {}
	if req == nil then return out end

	eachLeaf(req, pushGate, { slot = slot, out = out })

	local lvl = (slot and slot.lvl) or 0
	if req.minLevel then
		table.insert(out, {label = "level", have = lvl, need = req.minLevel, met = lvl >= req.minLevel})
	end
	if req.maxLevel then
		table.insert(out, {label = "level at most", have = lvl, need = req.maxLevel, met = lvl <= req.maxLevel})
	end
	-- have stays nil: ownership is server-side only
	if req.card then
		table.insert(out, {label = nameOf("card", req.card), need = 1, met = ownsCard(slot, req.card)})
	end
	if req.ability then
		table.insert(out, {label = nameOf("ability", req.ability), need = 1, met = ownsAbility(slot, req.ability)})
	end
	if req.sum then
		for track, amount in pairs(req.sum) do
			local have = trackSum(slot, track)
			table.insert(out, {
				label = "across " .. (TRACK_LABEL[track] or track),
				have = have, need = amount, met = have >= amount,
			})
		end
	end
	if req.And then
		for _, sub in ipairs(req.And) do
			for _, row in ipairs(module.breakdown(slot, sub)) do table.insert(out, row) end
		end
	end
	-- an Or has no single leaf to point a bar at, so it stays ONE row quoting itself,
	-- same call describe makes. It IS evaluable though, so it carries a have: leaving
	-- that nil reads as an ownership row and renders as "cannot check here".
	if req.Or then
		local hit = false
		for _, sub in ipairs(req.Or) do
			if module.check(slot, sub) then hit = true break end
		end
		table.insert(out, {label = module.describe({Or = req.Or} :: any), have = if hit then 1 else 0, need = 1, met = hit})
	end

	return out
end

--- authoring guard: a typo'd stat name is a req that can never pass, silently.
--  Call it from a test after adding reqs; nothing in prod calls it.
function module.validate(req: req?, label: string?): boolean
	if req == nil then return true end
	local ok = true
	eachLeaf(req, function(name, _amount, track)
		if track == nil then
			warn("[Requirements] unknown stat '" .. name .. "' in " .. tostring(label))
			ok = false
		end
	end)
	for track in pairs(req.sum or {}) do
		if TRACK_LABEL[track] == nil then
			warn("[Requirements] unknown track '" .. track .. "' in " .. tostring(label))
			ok = false
		end
	end
	for _, key in ipairs({"And", "Or"}) do
		for _, sub in ipairs((req :: any)[key] or {}) do
			if not module.validate(sub, label) then ok = false end
		end
	end
	return ok
end

return table.freeze(module)
