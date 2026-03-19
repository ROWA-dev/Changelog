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
		dmg      = 10,
		stun     = 0.66,
		posMult  = 1,
		onHit    = require(script.slash)
	},
	heavy = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 16,
		stun     = 0.66,
		posMult  = 1,
		onHit    = require(script.heavy),
		parryH   = 0.1
	},
	multiple = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 3,
		stun     = 0.2,
		posMult  = 0.7,
		onHit    = require(script.multiple),
		stunMeOnParried = 0,
		parryH   = 0.3
	}
}

deepFreeze(config)
return config