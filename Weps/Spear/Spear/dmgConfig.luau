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
	-- the thrown spear: no parryH/dodgeH and no knockback, since it pierces, ragdolls and PINS on a clean hit. Do not add either without a playtest.
	throw = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 20,
		stun     = 0.8,
		posMult  = 2,
		onHit    = require(script.throw)
	},
}

deepFreeze(config)
return config