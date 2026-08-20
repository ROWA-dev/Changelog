--!strict
--[[ Slayer damage. rowa1 rows translated per README S4 (truestun + stun
	collapse to ONE stun; flags by NAME, never by number).

	rowa1                                                    -> rowa2
	  slM1  Heavy slash+weaponM1     24 ts0.3 st0.75 pm1.8      m1
	  slM2  Heavy slash+weaponM1     20 ts1.4 st2.0  pm6        heavyCatch
	  slM3  Heavy slash+weaponM1      8 ts0   st0.7  pm8        heavyBreak
	  slM5  Heavy slash+weaponM1      2 ts0   st0    pm1        heavyGrind
	  slM4  Heavy slash+weaponM1     20 ts0.3 st0.7  pm2        heavyLaunch
	  gsM2  Heavy slash+weaponHeavy  20 ts0.4 st0.8  pm4        downSlam
	  fsM2  the shared unarmed punch                      -> WepBase/dmgConfig

	SOUNDS, per row, read off DMGS rather than guessed (they were guessed on
	first ship and every one of them was wrong):
	  slM1  BladeStab2, HitSound          -> slash
	  slM2  Slayer, BladeStab3, HitSound  -> catch   (`Slayer` is unique to
	                                         this row: the blade going in)
	  slM3  BladeStab3, HitSound          -> breakHit
	  slM4  BladeStab2, HitSound          -> launch. AND `ragdtillground`,
	                                         the ONLY onHit on any Slayer row
	                                         -- see launch.luau
	  slM5  {} -- genuinely EMPTY         -> grind, plays nothing
	  gsM2  BladeStab, HitSound           -> downSlamHit

	!! THE FIVE slM ROWS ARE NOT AN m1 CHAIN. slM2/3/5/4 are the four beats
	of the grab-and-drag heavy, in that order. All three m1 links share slM1.
	PORTW_Slayer says otherwise; see the header of Slayer.luau.

	RETUNED AGAINST EXECUTER, the shipped weapon in this family, per PORTW_00
	("compare against the nearest SHIPPED rowa2 weapon, not against rowa1").
	Executer is m1 14 / heavy 18 / kick 10.
	  m1        24 -> 15. Just above Executer's 14: same family, three-link
	            chain, Heavy weight.
	  downSlam  20 -> 18, i.e. Executer's heavy exactly. Both are gsM2-class
	            overhead finishers and there is no reason for them to differ.
	  the heavy  74 -> 49 across four beats (14 + 6 + 13x1 + 16). rowa1's
	            total is enormous, but it IS a committed 1s windup on an 8s
	            gate that has to CATCH first, so it is meant to be a lot.
	            Cut by a third rather than to Executer's per-hit rate.

	POSTURE IS THE PART TO WATCH. rowa1 runs pm6 then pm8 back to back --
	14x against maxPosture 80 -- which guard-breaks almost anything. That
	made sense in rowa1 where posture was 100 and the grab could still be
	blocked out of. Here the victim is ALREADY WELDED TO THE BLADE by then,
	so posture pressure is redundant: they are not blocking, they are being
	carried. Dropped to 3 and 4. README Q3, treat as a starting point. ]]
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
		posMult  = 1.5,
		onHit    = require(script.slash)
	},

	--- rowa1 fsM2, now shared. PORTW_00's one gotcha.
	punch = sharedCfg.punch,

	--[[ THE CATCH. Its 2.0 stun is the GRAB HOLD, not a combo extender --
		the victim is welded to the blade for the rest of the move. Kept
		long deliberately: if this expires early they fall off mid-drag. ]]
	heavyCatch = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 14,
		stun     = 2,
		posMult  = 3,
		parryH   = -0.06,
		onHit    = require(script.catch)
	},

	--- the guard-break beat, once they are on the blade.
	heavyBreak = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 6,
		stun     = 0.7,
		posMult  = 4,
		onHit    = require(script.breakHit)
	},

	--[[ THE GRIND. x13 at 0.05s while you drag them. 2 damage and ZERO stun
		in rowa1 -- the zero is load-bearing: this fires thirteen times and
		anything non-zero would re-stun-lock on its own rather than leaving
		the catch's hold to do it. Do not round it up. ]]
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
		dmg      = 16,
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
		dmg      = 18,
		stun     = 0.8,
		posMult  = 4,
		parryH   = -0.04,
		onHit    = require(script.downSlamHit)
	}
}

deepFreeze(config)
return config
