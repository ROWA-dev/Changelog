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
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 16,
		stun     = 0.76,
		posMult  = 1.4,
		onHit    = require(script.hammer),
		
		parryH   = -0.03
	},
	heavy = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 24,
		stun     = 1,
		posMult  = 2,
		onHit    = require(script.hvy),
		
		--parryH   = -0.03
	}
}

deepFreeze(config)
return config