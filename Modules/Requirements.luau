--!strict
--[[
	Requirements - one gate shape for weapons, cards, anything gated on a slot.
	Server enforces, client renders the same table; no second wire format.

	NAMESPACED, NOT FLAT: `light` is both a weaponStat AND an element.
	  w = weaponStats  b = baseStats  e = elements (ElementRegistry)
	Every entry is a minimum (>=); entries in one table are AND.
	And / Or nest, matching the names ROWA/Cards.luau already declares.

	    req = { w = {heavy = 2} }
	    req = { Or = { {w={heavy=2}}, {b={strength=6}} } }
	    req = {}    -- FREE. `nil` is NOT free: class statics inherit through
	                -- __index, so nil picks up the family's req.
	                
	MIGHT CHANGE THIS FORMAT - air
]]

local ElementRegistry = require(game.ReplicatedStorage.Modules.ElementRegistry)

export type req = {
	w: {[string]: number}?,
	b: {[string]: number}?,
	e: {[string]: number}?,
	minLevel: number?,
	maxLevel: number?,
	And: {req}?,
	Or:  {req}?,
}

local module = {}

local NS = {"w", "b", "e"}
local NS_LABEL = {w = "", b = "", e = " element"}

--- fn(ns, name, amount) over this level's stat leaves; truthy fn stops and returns it.
local function eachLeaf(req: req, fn: (string, string, number) -> any): any
	for _, ns in ipairs(NS) do
		local want = (req :: any)[ns]
		if want then
			for name, amount in pairs(want) do
				local hit = fn(ns, name, amount)
				if hit then return hit end
			end
		end
	end
	return nil
end

--- what `slot` owns of one stat. nil slot = nothing.
local function statOf(slot: any, ns: string, name: string): number
	if slot == nil then return 0 end
	if ns == "e" then
		local elems = slot.elements
		return (elems and elems:Get(name)) or 0
	end
	local tbl = if ns == "w" then slot.weaponStats else slot.baseStats
	local v = tbl and (tbl :: any)[name]
	return if typeof(v) == "number" then v else 0
end

local function label(ns: string, name: string, amount: number): string
	return amount .. " " .. name .. NS_LABEL[ns]
end

--- true if `slot` satisfies `req`. nil req is free.
function module.check(slot: any, req: req?): boolean
	if req == nil then return true end

	if eachLeaf(req, function(ns, name, amount)
		return statOf(slot, ns, name) < amount
	end) then return false end

	local lvl = (slot and slot.lvl) or 0
	if req.minLevel and lvl < req.minLevel then return false end
	if req.maxLevel and lvl > req.maxLevel then return false end

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

	eachLeaf(req, function(ns, name, amount)
		table.insert(parts, label(ns, name, amount))
	end)

	if req.minLevel then table.insert(parts, "lvl " .. req.minLevel .. "+") end
	if req.maxLevel then table.insert(parts, "lvl " .. req.maxLevel .. "-") end

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

--- every unmet leaf as "heavy 0 -> 2", have vs need. nil when the req is met.
function module.missing(slot: any, req: req?): string?
	if req == nil or module.check(slot, req) then return nil end
	local parts = {}

	eachLeaf(req, function(ns, name, amount)
		local have = statOf(slot, ns, name)
		if have < amount then
			table.insert(parts, name .. NS_LABEL[ns] .. " " .. have .. " -> " .. amount)
		end
	end)

	local lvl = (slot and slot.lvl) or 0
	if req.minLevel and lvl < req.minLevel then
		table.insert(parts, "lvl " .. lvl .. " -> " .. req.minLevel)
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

--- authoring guard: a typo'd stat name is a req that can never pass, silently.
--  Call it from a test after adding reqs; nothing in prod calls it.
function module.validate(req: req?, label: string?): boolean
	if req == nil then return true end
	-- DERIVED, never re-listed: adding a stat to baseStats/weaponStats teaches this for
	-- free, the way e has always read ElementRegistry. Required in here, not at the top,
	-- because validate is test-only and Requirements loads on every HumObj.
	local sreq: any = require
	local slotDir = game.ReplicatedStorage.Class.plrObjClient.slot
	local known: {[string]: {[string]: boolean}} = { w = {}, b = {}, e = {} }
	for name in pairs(sreq(slotDir.weaponStats).new()) do known.w[name] = true end
	for name in pairs(sreq(slotDir.baseStats).new()) do known.b[name] = true end
	for _, name in ipairs(ElementRegistry) do known.e[name] = true end

	local ok = true
	eachLeaf(req, function(ns, name)
		if not known[ns][name] then
			warn("[Requirements] unknown " .. ns .. " stat '" .. name .. "' in " .. tostring(label))
			ok = false
		end
	end)
	for _, key in ipairs({"And", "Or"}) do
		for _, sub in ipairs((req :: any)[key] or {}) do
			if not module.validate(sub, label) then ok = false end
		end
	end
	return ok
end

return table.freeze(module)
