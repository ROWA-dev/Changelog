--!strict
--- Oblitar damage. rowa1 oblM1/oblH/oblH2 -> m1/heavy/heavy2, per README S4
--- (truestun + stun collapse to one; flags by NAME, they moved between games).
--- fsM2, the shared unarmed punch, lives in WepBase/dmgConfig.
--- THE NUMBERS ARE NOT ROWA1'S: m1 damage is comparable across the games but
--- HEAVIES ARE NOT, so each is scaled against the nearest SHIPPED rowa2 weapon.
---   m1       19 -> 16, landing just above Claymore's 13
---   heavies  20+20 -> 18+22, equal to rowa1's TOTAL rather than scaled to
---            Claymore's per-hit rate. The second beat takes the larger share
---            because it is the committed one and the one that executes.
---   posMult  4+4 -> 2+3. Two beats at 4 was 8 posture-mult on one input.
--- SINCE PLAYTEST, tuning calls and not translations -- do not "correct" these
--- back off the rowa1 rows: m1.stun 0.8 -> 0.7, and m1/sprintAtk both carry a
--- deliberate +0.1 windup. README Q3: a starting point, not an answer.
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local sharedCfg = require(game.ServerStorage.ROWA.Weps.WepBase.dmgConfig)

local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

-- must follow {[string]: dmgUtils.dmgType}
type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 14,
		stun     = 0.7,
		posMult  = 1,
		onHit    = require(script.slash)
	},

	--[[ the flourish, and the thrust's whiff-punish partner. rowa1 used
		`fsM2` here; that now lives once on WepBase rather than being copied
		into every weapon that falls back to a punch. PORTW_00. ]]
	punch = sharedCfg.punch,

	heavy = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 16,
		stun     = 0.8,
		posMult  = 2,
		parryH   = -0.05,
		onHit    = require(script.heavy)
	},

	--[[ THE SECOND BEAT. Identical to `heavy` in rowa1 except for stun --
		PORTW_Oblitar's WATCH points out that without the execute the two
		tables are the same thing twice and the two-stage heavy has no
		reason to exist. The execute IS the second stage's reason to exist,
		and it lives in this row's onHit. ]]
	heavy2 = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 18,
		stun     = 0.8,
		posMult  = 3,
		parryH   = -0.05,
		onHit    = require(script.heavy2)
	}
}

deepFreeze(config)
return config
