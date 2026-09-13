--!strict
local abilityBase = require(script.AbilityBase)
export type anyAbility = abilityBase.myself & {id:number} & any
--export type serialAbility = {id:number} & any
type list = {
	[number]: ModuleScript
}

local manifold = script
local abilityList:list = {
	[1] = manifold.StrongLeft,
	[2] = manifold.Blaze,
	[3] = manifold.Clap,
	[4] = manifold.ToshiCounter,
	[5] = manifold.Barrage,
	[6] = manifold.FireStab,
	[7] = manifold.Fulminate,
	-- rowa1 port, wave 1 (no prerequisites), plan in rowa1OldPlanToPort PORT_00_INDEX.
	-- IDS ARE PERSISTED: append only, never renumber, never reuse.
	[8]  = manifold.PowerStrike,
	[9]  = manifold.IceBash,
	[10] = manifold.BoltPunch,
	[11] = manifold.PiercingStab,
	[12] = manifold.Rend,
	[13] = manifold.Blight,
	[14] = manifold.StrongerLeft,
	[15] = manifold.IceBeam,
	[16] = manifold.Zoltraak,
	[17] = manifold.JoltKick,
	[18] = manifold.FlameDance,
	[19] = manifold.StormUp,
	[20] = manifold.Cero,
	[21] = manifold.Huozai,
	[22] = manifold.Lightning,
	[23] = manifold.Tendrils,
	[24] = manifold.IceSlash,
	[25] = manifold.RPG,
	[26] = manifold.PaperBomb,
	[27] = manifold.StoneBall,
	[28] = manifold.IceShards,
	[29] = manifold.bloodChain,
	[30] = manifold.LionFall,
	[31] = manifold.DropKick,
	[32] = manifold.Divide,
	[33] = manifold.Smash,
	[34] = manifold.Burst,
	[35] = manifold.Bastar,
	[36] = manifold.Streak,
	[37] = manifold.Prediction,
	[38] = manifold.Freeze,
	[39] = manifold.Armor,
	[40] = manifold.InverseRed,
	[41] = manifold.FullBlue,
	--- unblocked by Destruction.Grab, which Armor [39] added. See its header.
	[42] = manifold.BoulderKick,
	--- TEST RIG, not a move. Registered only because the admin `ability`
	--- command drops anything moduleToID cannot resolve. See its header.
	[43] = manifold.ProjTest,
	--- rowa1 EmptyPurple, renamed after its own assets. See its header and
	--- PORT_00_INDEX; the ledger still files it under the old tool name.
	[44] = manifold.HollowPurple,
}
table.freeze(abilityList)

-- registered ids, ascending. Built off the KEYS, so asking what exists requires nothing.
-- Enumerate with this, never by probing getAbilityClass (that loads all 44 modules).
local idList:{number} = {}
for id in abilityList do
	table.insert(idList, id)
end
table.sort(idList)
table.freeze(idList)

-- draft metadata, KEYED BY MODULE so the id is written once and a misspelt key dies at load.
-- No entry == not draftable (keeps ProjTest out). Out of the classes, so filtering requires none.
local Requirements = require(game.ReplicatedStorage.Modules.Requirements)
local DraftTiers = require(game.ReplicatedStorage.Modules.DraftTiers) -- might remove this - air
export type meta = {
	desc: string,
	req: Requirements.req,          -- Modules/Requirements, {} is FREE and nil inherits
	tier: string?,                  -- Modules/DraftTiers, nil is the default colour
	replaces: number?,              -- claiming DROPS this id. Pair with req.ability or it drafts without the base
	reoffersBase: boolean?,         -- ...and then it returns to the pool, so both can be held
	excludes: {number}?,            -- PICK ONE. Made symmetric at load, so declare one side
	notWepClass: ModuleScript?,     -- weapon FAMILY you may not wield. Draft AND AbilityBase.use
}

-- weapon FAMILY, not an id: the instance path, so this gains no require on Weps.
local FISTS = game.ServerStorage.ROWA.Weps.Light.Fists

-- these descriptions and reqs are ai generated TODO human write them?
-- THESE REQS ARE LOW (reason: not enough content) will scale them accordingly in the future - air
local abilityMeta: {[ModuleScript]: meta} = {
	[manifold.StrongLeft] = {
		desc = "A charged left hook. Long windup, heavy launch.",
		req = { strength = 1 },
	},
	-- Blaze [2] is WIP
	[manifold.Clap] = {
		desc = "Clap shut on the nearest target within 40 studs.",
		req = { strength = 5 },
	},
	[manifold.ToshiCounter] = {
		desc = "A counter stance answering with a two-hit reply.",
		req = { dexterity = 4 },
		-- both are dexterity counters; a build picks its answer, not both.
		excludes = { 30 }, -- LionFall
	},
	[manifold.Barrage] = {
		desc = "A rapid flurry of punches.",
		req = { strength = 1 },
	},
	[manifold.FireStab] = {
		desc = "A flaming stab. Costs mana.",
		req = { flame = 3 },
	},
	[manifold.Fulminate] = {
		desc = "A close-range lightning discharge.",
		req = { lightning = 3 },
	},
	[manifold.PowerStrike] = {
		desc = "Two-stage weapon flourish; the second slash launches.",
		req = {
			Or = {
				{med = 2}, {lht = 2}
			} :: {Requirements.req}
		},
	},
	[manifold.IceBash] = {
		desc = "A committed overhead ice smash. Long reach.",
		req = { ice = 4 },
	},
	[manifold.BoltPunch] = {
		desc = "A lunging lightning straight; the dash leads the windup.",
		req = { lightning = 2 },
	},
	[manifold.PiercingStab] = {
		desc = "A rooted 0.65s telegraph. The slowest single hit.",
		req = {
			Or = {
				{med = 4}, {lht = 2}
			} :: {Requirements.req}
		},
		notWepClass = FISTS, -- nothing to stab with
	},
	[manifold.Rend] = {
		desc = "Two ground slams, the second higher than the first.",
		req = { hvy = 4 },
	},
	[manifold.Blight] = {
		desc = "A blinding orb that detonates in a 20-stud sphere.",
		req = { creation = 2, flame = 1 },
	},
	[manifold.StrongerLeft] = {
		desc = "Three shockwave rings and terrain destruction.",
		req = { strength = 6, ability = 1 }, -- StrongLeft
		replaces = 1, -- same id as req.ability above, or it drafts without the base
		-- a PAIR, not a ladder: the quick hook still earns a slot next to the committed one.
		reoffersBase = true,
		tier = DraftTiers.RARE,
	},
	[manifold.IceBeam] = {
		desc = "A sustained freezing beam. Freezes rather than stuns.",
		req = { ice = 3 },
	},
	[manifold.Zoltraak] = {
		desc = "A lock-on bolt; a connect follows with a 10-shot volley.",
		req = { mind = 7 },
	},
	[manifold.JoltKick] = {
		desc = "A lightning roundhouse that chains a second jolt.",
		req = { lightning = 4 },
	},
	[manifold.FlameDance] = {
		desc = "A 2s spinning fire aura that ignites its outer band.",
		req = { flame = 6 },
	},
	[manifold.StormUp] = {
		desc = "A rising spin that launches you both. Air-combo opener.",
		req = { lightning = 8 },
	},
	[manifold.Cero] = {
		desc = "A wide beam cannon that carves a tunnel.",
		req = { mind = 6 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.Huozai] = {
		desc = "A 3s flamethrower in six nested bands.",
		req = { flame = 10 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.Lightning] = {
		desc = "Call a bolt down on a target's position.",
		req = { lightning = 6 },
		tier = DraftTiers.RARE,
	},
	[manifold.Tendrils] = {
		desc = "Blood tendrils grab, hoist and break a target.",
		req = { blood = 4 },
	},
	[manifold.IceSlash] = {
		desc = "Two ice crescents that cut through and deflect.",
		req = { ice = 4 },
	},
	[manifold.RPG] = {
		desc = "One homing rocket. A parry redirects it to someone else.",
		req = { creation = 4 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.PaperBomb] = {
		desc = "Four explosive kunai that stick and burn a fuse.",
		req = { creation = 1, flame = 2 },
	},
	[manifold.StoneBall] = {
		desc = "Roll forward inside a giant stone ball.",
		req = { earth = 2 },
	},
	[manifold.IceShards] = {
		desc = "Rain twenty ice shards in five waves.",
		req = { ice = 3 },
	},
	[manifold.bloodChain] = {
		desc = "A chain that yanks both parties to the midpoint.",
		req = { blood = 3 },
	},
	[manifold.LionFall] = {
		desc = "Cancel an incoming attack, answer with one huge punch.",
		req = { dexterity = 5 },
	},
	[manifold.DropKick] = {
		desc = "Hop up, then dive at the ground on a diagonal.",
		req = { dexterity = 4, strength = 2 },
	},
	[manifold.Divide] = {
		desc = "Uppercut, drag them in, two committed strikes.",
		req = { strength = 2, mind = 2 },
	},
	[manifold.Smash] = {
		desc = "Uppercut, flash-step up, drive them back down.",
		req = { strength = 8 },
	},
	[manifold.Burst] = {
		desc = "Charge with a fireball; anyone caught is dragged along.",
		req = { flame = 4 },
	},
	[manifold.Bastar] = {
		desc = "Pin them on the blade, then hurl it down the lane.",
		req = { hvy = 5 },
		tier = DraftTiers.RARE,
	},
	[manifold.Streak] = {
		desc = "Blink-slash a 40-stud lane, dragging everyone to its end.",
		req = { med = 4 },
		notWepClass = FISTS, -- a blink-SLASH needs a blade
	},
	[manifold.Prediction] = {
		desc = "Attacks are turned back on whoever threw them.",
		req = { mind = 5 },
		tier = DraftTiers.RARE,
	},
	[manifold.Freeze] = {
		desc = "A line of ice. Fills the Freeze meter in one hit.",
		req = { ice = 6 },
		tier = DraftTiers.RARE,
	},
	[manifold.Armor] = {
		desc = "Wear the ground. How much you rip is how much you get.",
		req = { earth = 8 },
		tier = DraftTiers.RARE,
	},
	[manifold.InverseRed] = {
		desc = "A red orb fired flat. All the damage is in the blast.",
		-- CARD id raw, like loadChar's, so Abilities gains no require on Cards. NOT ability 13.
		req = { card = 13 }, -- Six Eyes
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.FullBlue] = {
		desc = "A gravity well that drags everything into orbit.",
		req = { card = 13 }, -- Six Eyes card
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.BoulderKick] = {
		desc = "Rip a chunk of the map out and punt it.",
		req = { earth = 4 },
	},
	[manifold.HollowPurple] = {
		desc = "A 4.25s charge, then a beam that ignores geometry.",
		req = { card = 13, mind = 10 }, -- Six Eyes card
		tier = DraftTiers.ULTIMATE,
	},
}
table.freeze(abilityMeta)

local module = {}

function module.getIds(): {number}
	return idList
end

function module.getAbilityClass(id:number)
	local sreq:any = require
	local ability = abilityList[id]

	if ability == nil then
		error("ability_id["..tostring(id).."] does not exist")
	end

	return sreq(ability)
end

function module.getMeta(id:number): meta?
	local mod = abilityList[id]
	return if mod then abilityMeta[mod] else nil
end

-- reverse of meta.replaces, built once from the metadata. Requires NOTHING, same as idList.
local supersededBy: {[number]: number} = {}
-- exclusions, made SYMMETRIC here so a pair is declared once and neither side can drift.
local conflicts: {[number]: {number}} = {}
local function addConflict(a: number, b: number)
	local list = conflicts[a]
	if list == nil then list = {} conflicts[a] = list end
	if not table.find(list, b) then table.insert(list, b) end
end
for id, mod in abilityList do
	local m = abilityMeta[mod]
	if m == nil then continue end
	if m.replaces then supersededBy[m.replaces] = id end
	for _, other in ipairs(m.excludes or {}) do
		addConflict(id, other)
		addConflict(other, id)
	end
end
table.freeze(supersededBy)
table.freeze(conflicts)

-- which upgrade eats this ability, if any. The draft hides the base behind it, unless
-- that upgrade sets reoffersBase.
function module.supersededBy(id:number): number?
	return supersededBy[id]
end

-- ids that CANNOT be owned alongside this one. Symmetric, so asking either side works.
function module.conflictsOf(id:number): {number}?
	return conflicts[id]
end

-- display name without an instance: one require, and callers cache. ablityItem.getName routes here.
function module.nameOf(id:number): string
	local ok, class = pcall(module.getAbilityClass, id)
	return (ok and class and class.Name) or ("ability_"..tostring(id))
end

-- nil for a module on disk but not in abilityList (EarthShot, HitSelf, StrongKick,
-- StrongShove). NOT a fault, so it warns rather than errors: callers must handle nil.
function module.moduleToID(module:ModuleScript): number?
	for i, v in abilityList do
		if v == module then
			return i
		end
	end
	warn("module_to_id: "..tostring(module and module:GetFullName()).." is not registered in abilityList")
	return nil
end

function module.newAbility(id:number, ...): anyAbility
	local abilityClass = module.getAbilityClass(id)
	local itmInst = abilityClass.new(...)
	-- carry the wielded-weapon gate onto the instance, so AbilityBase.use needs no id
	-- and no require back into this registry.
	local meta = module.getMeta(id)
	itmInst.notWepClass = meta and meta.notWepClass
	return itmInst
end

-- ModuleScript name, NOT nameOf: nameOf reads class.Name, so naming a whole catalogue
-- through it would require all 44 modules. They agree, every class is Name = script.Name.
local function listName(id: number): string
	local mod = abilityList[id]
	return if mod then mod.Name else "ability_" .. tostring(id)
end

-- ARRAY, never KEYED by id: ids gap here too. Cards.catalogue's COLUMNS exactly, because
-- the codex draws one page for both.
local catalogue: {{any}}
function module.catalogue(): {{any}}
	if catalogue == nil then
		local built = {}
		for _, id in ipairs(idList) do
			local meta = abilityMeta[abilityList[id]]
			if meta == nil then continue end
			-- replaces/excludes are NOT part of `req`, so describe never mentions them; the draft does.
			local drops = if meta.replaces then listName(meta.replaces) else ""
			local picks = {}
			for _, other in ipairs(conflicts[id] or {}) do
				table.insert(picks, listName(other))
			end
			-- DENSE: "" and {} never nil -- a nil gaps the row, and a nil req means INHERIT.
			table.insert(built, {id, listName(id), meta.desc or "", Requirements.describe(meta.req),
				meta.req or {}, drops, table.concat(picks, ", ")})
		end
		catalogue = table.freeze(built)
	end
	return catalogue
end

-- `req = { ability = id }` prints a name instead of a number. Costs one ability
-- require, and only when a gate is actually described.
Requirements.setNamer("ability", module.nameOf)

return module