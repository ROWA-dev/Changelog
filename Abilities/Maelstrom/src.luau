--!strict
-- Maelstrom - WindSlash's upgrade: same swing, no boomerang, a wider cut that lands twice.
local baseClass = require(script.Parent.WindSlash)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags

local module = {
	Name = "Maelstrom",
	cdId = "maelstrom",
	cd = 12,
	manaUse = 15,
	fx = "maelstrom",
	boxCf = CFrame.new(0, 0, -2), -- wraps you: 14 ahead, 10 behind, 12 a side
	boxSize = Vector3.new(28, 12, 28),
	gust = false,
	swings = table.freeze({
		{
			weight  = dmgUtils.weighEnum.Medium,
			type    = bit32.bor(dmgFlag.wind, dmgFlag.slash),
			dmg     = 12,
			stun    = 0.6, -- outlasts HIT_GAP so the second cut lands
			dodgeH   = -0.1,
			onHit   = baseClass.onHit,
		},
		{
			weight  = dmgUtils.weighEnum.Heavy,
			type    = bit32.bor(dmgFlag.wind, dmgFlag.slash),
			dmg     = 14,
			stun    = 0.7,
			dodgeH   = -0.1,
			onHit   = baseClass.onHit,
		},
	}),
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

return table.freeze(module)
