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
		stun     = 0.5,
		posMult  = 0.8,
		onHit    = require(script.slash)
	},
	punch = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 9,
		stun     = 0.6,
		posMult  = 1.2,
		onHit    = require(script:WaitForChild("punch"))
	},
	heavy = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 4.5,
		stun     = 0.5,
		posMult  = 1,
		onHit    = require(script.slash),

		parryH   = -0.05
	},
}

deepFreeze(config)
return config