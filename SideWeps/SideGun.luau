--!strict
local baseClass = require(script.Parent:WaitForChild("SideGunBase"))
local DMGS = require(game.ServerStorage.ROWA.Class.DMGS)

export type myself = baseClass.myself

local module = {
	Name = "SideGun",

	Draw   = script:WaitForChild("Draw"),
	Draw2  = script:WaitForChild("Draw2"),
	Reload = script:WaitForChild("Reload"),

	MAX_SHOTS   = 3,
	WINDUP      = 0.4,
	RELOAD_TIME = 0.9,
	HITBOX_SIZE = Vector3.new(3, 3, 6),
	HITBOX_OFFSET = CFrame.new(0,0,-4),
	MAX_TARGETS = 3,
	PELLETS     = 1,
	SPREAD      = 0,

	DMG = DMGS.new(DMGS.weighEnum.Light, DMGS.dmgFlag.blunt, 11, 0.4, 1),
	PROJ = table.freeze({
		speed       = 300,
		lifetime    = 1,
		maxDistance = 300,
		size        = Vector3.new(1, 1, 2),
		stopOnWorld = true,
		fxId        = "sgunProj",
		dmgTbl      = DMGS.new(DMGS.weighEnum.Light, DMGS.dmgFlag.blunt, 9, 0.2, 1),
		onHit       = baseClass.onBulletHit,
	}),
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj): myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self: myself = setmetatable(abstract, module) :: any
	self._model = script:WaitForChild("Model"):Clone()
	return self
end

return module
