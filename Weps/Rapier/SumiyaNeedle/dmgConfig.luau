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
	lunge = { -- hooks on a hit or block
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 9,
		stun     = 0.8,
		posMult  = 0.8,
		dodgeH   = -0.08,
		onHit    = require(script.slash)
	},
	reel = { -- the slash they are reeled into: light, its stun is what sets up the follow-up
		weight   = weighEnum.Light,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.weaponHeavy),
		dmg      = 5,
		stun     = 0.8,
		posMult  = 1,
		dodgeH   = -0.08,
		onHit    = require(script.slash)
	},
}

deepFreeze(config)
return config