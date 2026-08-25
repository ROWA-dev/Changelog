--!strict
--- Slayer damage. rowa1 rows per README S4 (truestun + stun collapse to one).
---   slM1 -> m1 (all three links share it)   gsM2 -> downSlam
---   slM2/slM3/slM5/slM4 -> heavyCatch / heavyBreak / heavyGrind / heavyLaunch,
---   the four beats of the grab-and-drag heavy IN THAT ORDER -- not an m1
---   chain, whatever PORTW_Slayer says. See Slayer.luau's header.
--- Sounds are read off DMGS per row, not guessed. slM4 carries `ragdtillground`,
--- the only onHit on any Slayer row -- see launch.luau.
--- Retuned against EXECUTER, not rowa1 (PORTW_00): m1 24 -> 15, downSlam 20 -> 18
--- (Executer's heavy exactly), the heavy 74 -> 49 across its four beats.
--- !! POSTURE IS THE PART TO WATCH: rowa1's pm6 then pm8 is 14x against a
--- maxPosture of 80. Redundant here -- the victim is already WELDED to the
--- blade and is not blocking. Dropped to 3 and 4, README Q3, a starting point.
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local sharedCfg = require(game.ServerStorage.ROWA.Weps.WepBase.dmgConfig)

local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 15,
		stun     = 0.75,
		posMult  = 1,
		onHit    = require(script.slash),
		
		parryH   = -0.03
	},

	--- rowa1 fsM2, now shared. PORTW_00's one gotcha.
	punch = sharedCfg.punch,

	--[[ THE CATCH. Its 2.0 stun is the GRAB HOLD, not a combo extender --
		the victim is welded to the blade for the rest of the move. Kept
		long deliberately: if this expires early they fall off mid-drag. ]]
	heavyCatch = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 10,
		stun     = 2,
		posMult  = 3,
		--parryH   = -0.06,
		onHit    = require(script.catch)
	},

	--- the guard-break beat, once they are on the blade.
	heavyBreak = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 6,
		stun     = 1,
		posMult  = 6,
		onHit    = require(script.breakHit)
	},

	--[[ THE GRIND. x10 at 0.065s while you drag them.]]
	heavyGrind = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 1,
		stun     = 0,
		posMult  = 0.3,
		stunMeOnParried = 0,
		onHit    = require(script.grind)
	},

	--- the launch that ends the drag.
	heavyLaunch = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 10,
		stun     = 0.7,
		posMult  = 2,
		--[[ carries rowa1's `ragdtillground`. This is the only Slayer row
			with an onHit of its own and it is what makes the throw a THROW
			rather than a shove. ]]
		onHit    = require(script.launch)
	},

	--- gsM2, the downslam. Executer's heavy numbers.
	downSlam = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 14,
		stun     = 0.8,
		posMult  = 4,
		onHit    = require(script.downSlamHit)
	}
}

deepFreeze(config)
return config
