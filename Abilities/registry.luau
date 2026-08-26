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
	-- rowa1 port, wave 1 (no prerequisites). See
	-- ServerStorage/rowa1OldPlanToPort/README.md/PORT_00_INDEX for the plan.
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

-- registered ids, ascending. Built once from the keys, so reading it requires
-- NOTHING: no ability module is loaded to ask "what exists". Anything wanting
-- to enumerate abilities (random grants, admin listings) uses this instead of
-- probing getAbilityClass in a loop, which would require all 44 modules.
local idList:{number} = {}
for id in abilityList do
	table.insert(idList, id)
end
table.sort(idList)
table.freeze(idList)

-- draft metadata. KEYED BY MODULE so the id is written once (in abilityList) and every line names itself;
-- a misspelt key is a nil index that dies at load. No entry == not draftable, which is what keeps ProjTest out.
-- OUT of the classes so filtering never requires them (see idList). name is class.Name, via nameOf.
-- req: Modules/Requirements ({} is free). tier: Modules/DraftTiers (nil == default).
local Requirements = require(game.ReplicatedStorage.Modules.Requirements)
local DraftTiers = require(game.ReplicatedStorage.Modules.DraftTiers) -- might remove this - air
export type meta = { desc: string, req: Requirements.req, tier: string? }

-- these descriptions and reqs are ai generated TODO human write them?
-- THESE REQS ARE LOW (reason: not enough content) will scale them accordingly in the future - air
local abilityMeta: {[ModuleScript]: meta} = {
	[manifold.StrongLeft] = {
		desc = "A charged left hook. Long windup, heavy launch.",
		req = {},
	},
	[manifold.Blaze] = {
		desc = "A burst of flame that shoves you back as it erupts.",
		req = { flame = 1 },
	},
	[manifold.Clap] = {
		desc = "Clap shut on the nearest target within 40 studs.",
		req = { strength = 2 },
	},
	[manifold.ToshiCounter] = {
		desc = "A counter stance answering with a two-hit reply.",
		req = { dexterity = 2 },
	},
	[manifold.Barrage] = {
		desc = "A rapid flurry of punches.",
		req = { strength = 1 },
	},
	[manifold.FireStab] = {
		desc = "A flaming stab. Costs mana.",
		req = { flame = 2 },
	},
	[manifold.Fulminate] = {
		desc = "A close-range lightning discharge.",
		req = { wind = 2 },
	},
	[manifold.PowerStrike] = {
		desc = "Two-stage weapon flourish; the second slash launches.",
		req = { med = 2 },
	},
	[manifold.IceBash] = {
		desc = "A committed overhead ice smash. Long reach.",
		req = { ice = 1 },
	},
	[manifold.BoltPunch] = {
		desc = "A lunging lightning straight; the dash leads the windup.",
		req = { wind = 1 },
	},
	[manifold.PiercingStab] = {
		desc = "A rooted 0.65s telegraph. The slowest single hit.",
		req = { med = 2 },
	},
	[manifold.Rend] = {
		desc = "Two ground slams, the second higher than the first.",
		req = { strength = 3 },
	},
	[manifold.Blight] = {
		desc = "A blinding orb that detonates in a 20-stud sphere.",
		req = { dark = 2 },
	},
	[manifold.StrongerLeft] = {
		desc = "Three shockwave rings and terrain destruction.",
		req = { strength = 6 },
		tier = DraftTiers.RARE,
	},
	[manifold.IceBeam] = {
		desc = "A sustained freezing beam. Freezes rather than stuns.",
		req = { ice = 3 },
	},
	[manifold.Zoltraak] = {
		desc = "A lock-on bolt; a connect follows with a 10-shot volley.",
		req = { mind = 3 },
	},
	[manifold.JoltKick] = {
		desc = "A lightning roundhouse that chains a second jolt.",
		req = { wind = 3 },
	},
	[manifold.FlameDance] = {
		desc = "A 2s spinning fire aura that ignites its outer band.",
		req = { flame = 3 },
	},
	[manifold.StormUp] = {
		desc = "A rising spin that launches you both. Air-combo opener.",
		req = { wind = 3 },
	},
	[manifold.Cero] = {
		desc = "A wide beam cannon that carves a tunnel.",
		req = { mind = 5 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.Huozai] = {
		desc = "A 3s flamethrower in six nested bands.",
		req = { flame = 6 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.Lightning] = {
		desc = "Call a bolt down on a target's position.",
		req = { wind = 4 },
		tier = DraftTiers.RARE,
	},
	[manifold.Tendrils] = {
		desc = "Blood tendrils grab, hoist and break a target.",
		req = { blood = 3 },
	},
	[manifold.IceSlash] = {
		desc = "Two ice crescents that cut through and deflect.",
		req = { ice = 2 },
	},
	[manifold.RPG] = {
		desc = "One homing rocket. A parry re-acquires someone else.",
		req = { creation = 4 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.PaperBomb] = {
		desc = "Four explosive kunai that stick and burn a fuse.",
		req = { dexterity = 3 },
	},
	[manifold.StoneBall] = {
		desc = "Roll forward inside a giant stone ball at 90 studs/s.",
		req = { earth = 2 },
	},
	[manifold.IceShards] = {
		desc = "Rain twenty ice shards in five waves.",
		req = { ice = 4 },
	},
	[manifold.bloodChain] = {
		desc = "A chain that yanks both parties to the midpoint.",
		req = { blood = 4 },
	},
	[manifold.LionFall] = {
		desc = "Cancel an incoming attack, answer with one huge punch.",
		req = { dexterity = 4 },
	},
	[manifold.DropKick] = {
		desc = "Hop up, then dive at the ground on a diagonal.",
		req = { dexterity = 2 },
	},
	[manifold.Divide] = {
		desc = "Uppercut, drag them in, two committed strikes.",
		req = { strength = 4 },
	},
	[manifold.Smash] = {
		desc = "Uppercut, flash-step up, drive them back down.",
		req = { strength = 4 },
	},
	[manifold.Burst] = {
		desc = "Charge with a fireball; anyone caught is dragged along.",
		req = { flame = 3 },
	},
	[manifold.Bastar] = {
		desc = "Pin them on the blade, then hurl it down the lane.",
		req = { hvy = 4 },
		tier = DraftTiers.RARE,
	},
	[manifold.Streak] = {
		desc = "Blink-slash a 40-stud lane, dragging everyone to its end.",
		req = { lht = 3 },
	},
	[manifold.Prediction] = {
		desc = "Attacks are turned back on whoever threw them.",
		req = { dexterity = 5 },
		tier = DraftTiers.RARE,
	},
	[manifold.Freeze] = {
		desc = "A line of ice. Fills the Freeze meter in one hit.",
		req = { ice = 5 },
		tier = DraftTiers.RARE,
	},
	[manifold.Armor] = {
		desc = "Wear the ground. How much you rip is how much you get.",
		req = { earth = 5 },
		tier = DraftTiers.RARE,
	},
	[manifold.InverseRed] = {
		desc = "A red orb fired flat. All the damage is in the blast.",
		req = { mind = 5 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.FullBlue] = {
		desc = "A gravity well that drags everything into orbit.",
		req = { mind = 5 },
		tier = DraftTiers.ULTIMATE,
	},
	[manifold.BoulderKick] = {
		desc = "Rip a chunk of the map out and punt it.",
		req = { earth = 3 },
	},
	[manifold.HollowPurple] = {
		desc = "A 4.25s charge, then a beam that ignores geometry.",
		req = { mind = 7 },
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

-- display name without an instance: one require, and callers cache. ablityItem.getName routes here.
function module.nameOf(id:number): string
	local ok, class = pcall(module.getAbilityClass, id)
	return (ok and class and class.Name) or ("ability_"..tostring(id))
end

-- returns nil for abilities that exist on disk but are not in abilityList
-- (scratch abilities: EarthShot, HitSelf, StrongKick, StrongShove).
-- PowerStrike used to be on that list and is NOT any more -- it shipped as id 8.
-- That is NOT a fault, so it warns and returns instead of erroring — callers
-- must handle nil.
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
	return itmInst
end

return module
