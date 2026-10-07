--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local sharedCfg = require(game.ServerStorage.ROWA.Weps.WepBase.dmgConfig)

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

	punch = sharedCfg.punch,
}

deepFreeze(config)
return config
