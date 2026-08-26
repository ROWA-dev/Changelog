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
	-- Luau types an array literal from its FIRST element, so a mixed
	-- {{hvy=2},{med=2}} needs `:: {Requirements.req}` at the authoring site.
	And: {req}?,
	Or:  {req}?,
}

local module = {}

-- registry values: string = which track owns it, false = operator key, nil = unknown.
local OPS = {minLevel = false, maxLevel = false, And = false, Or = false}
local TRACK: {[string]: any}? = nil

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
	local ok = true
	eachLeaf(req, function(name, _amount, track)
		if track == nil then
			warn("[Requirements] unknown stat '" .. name .. "' in " .. tostring(label))
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
