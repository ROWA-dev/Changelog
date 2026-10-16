--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

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
	heavy = {
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 12,
		stun     = 0.8,
		posMult  = 1,
		dodgeH   = -0.1,
		onHit    = function(attack) fireVFX("scimHvy", 2, attack.enemyEntity.HRootPart) end
	},
	heavy2 = { -- the uppercut follow-up, stun of the house launcher. its lift is in attack/heavy (blocked lifts too)
		weight   = weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 12,
		stun     = 1,
		posMult  = 1,
		dodgeH   = -0.1,
		onHit    = function(attack) fireVFX("scimHvy", 2, attack.enemyEntity.HRootPart) end
	},
	punch = {
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.weaponM1),
		dmg      = 12,
		stun     = 0.6,
		posMult  = 1.2,
		onHit    = require(script:WaitForChild("punch"))
	}
}

deepFreeze(config)
return config