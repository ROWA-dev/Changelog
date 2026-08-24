--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)

local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

-- must follow {[string]: dmgUtils.dmgType}
type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 12,
		stun     = 0.7,
		posMult  = 1,
		onHit    = require(script.slash)
	},
	punch = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 10,
		stun     = 0.6,
		posMult  = 1.2,
		onHit    = require(script:WaitForChild("punch"))
	},
	--[[ THE THROWN SPEAR. rowa1 `spH`: Medium, slash+weaponHeavy, 28 dmg,
		truestun 0.4 + stun 0.9 (collapsed to one, README S4.2), posMult 2.
		Damage down to 20: this pierces, ragdolls and cannot be blocked out of
		existence. NO parryH/dodgeH and NO knockback -- rowa1 carries neither,
		the parry reward is already large, and it PINS on a clean hit.
		Do not add either without a playtest. ]]
	throw = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 20,
		stun     = 0.8,
		posMult  = 2,
		onHit    = require(script.throw)
	},
	--[[ UNUSED. The heavy is a throw, so nothing reads this row. Kept
		because it is the only home the decap onHit has; wire it up only if
		the spear ever grows a melee heavy again. ]]
	heavy = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 36,
		stun     = 0.8,
		posMult  = 3,
		parryH   = -0.1,
		dodgeH   = -0.1,
		onHit    = require(script.heavy)
	}
}

deepFreeze(config)
return config