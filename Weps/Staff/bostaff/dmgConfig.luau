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
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 10,
		stun     = 0.68,
		posMult  = 1,
		onHit    = require(script.hit)
	},
	multiple = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 2,
		stun     = 0.2,
		posMult  = 1,
		onHit    = require(script.hit),
		stunMeOnParried = 0
		--parryH   = 0.4
	},
	heavy = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 9,
		stun     = 0.66,
		posMult  = 3.5,
		onHit    = require(script.hit)
	},
	heavySecond = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 9,
		stun     = 0.66,
		posMult  = 1.5,
		onHit    = require(script.hit)
	},
	heavyPunch = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 5,
		stun     = 0.66,
		posMult  = 1.5,
		onHit    = require(script.hit)
	},
	heavyFlourish = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 9,
		stun     = 0.66,
		posMult  = 1.5,
		onHit    = require(script.hit)
	},
}

deepFreeze(config)
return config