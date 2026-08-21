--!strict
--[[ Oblitar damage. rowa1 rows, translated per README S4.

	rowa1                                            -> rowa2
	  oblM1  Medium slash+weaponM1  19 ts0.32 st0.8 pm1   m1
	  oblH   Medium slash+weaponHeavy 20 ts0.2  st0.8 pm4 heavy
	  oblH2  Medium slash+weaponHeavy 20 ts0.6  st1.0 pm4 heavy2
	  fsM2   the shared unarmed punch                     -> WepBase/dmgConfig

	truestun + stun collapse to ONE `stun` (S4.2), flags are written by NAME
	because fire/magic and wind/blood moved between the games (S4.1).

	THE NUMBERS ARE NOT ROWA1'S, and PORTW_00 is explicit about why: m1 dmg
	is broadly comparable across the games but HEAVIES ARE NOT (rowa1 swH 28
	-> rowa2 Claymore heavy 36), so each is scaled against the nearest
	SHIPPED rowa2 weapon instead of by one factor.
	  m1      19 -> 16. rowa1 oblM1 19 against rowa1 swM1 15.5, applied to
	          Claymore's shipped 13. Lands between Claymore (13) and nothing
	          else in the family, which is right for a bigger blade.
	  heavies 20+20 -> 18+22 = 40 TOTAL, deliberately equal to rowa1's own
	          total rather than scaled up to Claymore's 36-per-hit rate. A
	          proportional scale would have put this at ~52 across two beats
	          on a 5s gate, against Claymore's 36 on a 10s one. The second
	          beat carries the larger share because it is the committed one
	          and the one that executes.
	  posMult 4+4 -> 2+3. PORTW_Oblitar's own WATCH flags posMult 4 as high
	          for Medium weight and says to compare against Claymore's heavy
	          (3) first. Two beats at 4 was 8 posture-mult on one input.

	SINCE PLAYTEST, and these are TUNING CALLS, not translations. Do not
	"correct" them back by reading the rowa1 rows:
	  m1.stun  0.8 -> 0.7   (rowa1 oblM1 is 0.8)
	  windups  m1 and the running attack both carry a deliberate +0.1 over
	           rowa1; those live in attack/m1 and attack/sprintAtk.

	Treat all of it as a starting point, not an answer -- README Q3. ]]
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
