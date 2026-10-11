--!strict
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local deepFreeze = require(game.ServerScriptService.Utils.deepfreeze)
local weighEnum, dmgFlag = dmgUtils.weighEnum, dmgUtils.dmgFlags
local slash = require(script.Parent.Parent.Katana.dmgConfig.slash)
local M1 = bit32.bor(dmgFlag.slash, dmgFlag.weaponM1)

type configs = {[string]: dmgUtils.dmgType}
local config:configs = {
	m1         = { weight = weighEnum.Medium, type = M1, dmg = 10,   stun = 0.66, posMult = 1,   onHit = slash },
	airM1      = { weight = weighEnum.Medium, type = M1, dmg = 9,    stun = 0.7,  posMult = 1,   onHit = slash },
	upperSlash = { weight = weighEnum.Medium, type = M1, dmg = 10.5, stun = 0.7,  posMult = 5.5, onHit = slash },
	spin       = { weight = weighEnum.Medium, type = M1, dmg = 3.5,  stun = 0.25, posMult = 3,   onHit = slash },
	slam       = { weight = weighEnum.Medium, type = M1, dmg = 10.5, stun = 0.7,  posMult = 5.5, onHit = require(game.ServerStorage.ROWA.Weps.WepBase.dmgConfig.dslam) },
}

deepFreeze(config)
return config
