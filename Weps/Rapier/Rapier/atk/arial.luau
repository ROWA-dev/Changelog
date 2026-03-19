--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)

local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

-- must follow {[string]: dmgUtils.dmgType}
type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 9,
		stun     = 0.55,
		posMult  = 0.8,
		onHit    = require(script.slash)
	},
	punch = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 9,
		stun     = 0.6,
		posMult  = 1,
		onHit    = require(script.punch)
	},
	firstHeavy = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 4,
		stun     = 0.55,
		posMult  = 0.8,
		onHit    = require(script.slash),
		stunMeOnParried = 0,
		dodgeH   = -0.1,
		parryH   = -0.05,
	},
	lastHeavy = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 5,
		stun     = 0.55,
		posMult  = 0.8,
		onHit    = require(script.slash),
		dodgeH   = -0.1,
		parryH   = 0.3--0.12
	},
	heavy = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 5,
		stun     = 0.55,
		posMult  = 0.8,
		onHit    = require(script.slash),
		stunMeOnParried = 0,
		dodgeH   = -0.1,
		parryH   = 0.3--0.12
	},
}

deepFreeze(config)
return config