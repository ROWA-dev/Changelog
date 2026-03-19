--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)

local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

-- must follow {[string]: dmgUtils.dmgType}
type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1 = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1),
		dmg      = 14,
		stun     = 0.72,
		posMult  = 1,
		onHit    = require(script.gswordHit),
		
		parryH   = -0.01
	},
	kick = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 10,
		stun     = 0.64,
		posMult  = 1.2,
		onHit    = require(script.kick)
	},
	heavy = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 18,
		stun     = 1,
		posMult  = 3,
		onHit    = require(script.hvy),
		
		parryH   = -0.01
	}
}

deepFreeze(config)
return config