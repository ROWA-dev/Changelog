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
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 9.5,
		stun     = 0.65,
		posMult  = 1.2,
		onHit    = require(script:WaitForChild("punch"))
	},
	heavy = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 3,
		stun     = 0.6,
		posMult  = 6,
		onHit    = require(script:WaitForChild("punch"))
	},
	smash = {
		weight   = weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponHeavy),
		dmg      = 24,
		stun     = 0.6,
		posMult  = 6,
		onHit    = require(script:WaitForChild("punch"))
	}
}

deepFreeze(config)
return config