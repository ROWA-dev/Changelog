--!strict
local baseClass = require(script.Parent:WaitForChild("SideGunBase"))
local DMGS = require(game.ServerStorage.ROWA.Class.DMGS)

export type myself = baseClass.myself

local module = {
	Name = "SideShotgun",

	Draw   = script:WaitForChild("Draw"),
	Draw2  = script:WaitForChild("Draw2"),
	Reload = script:WaitForChild("Reload"),

	MAX_SHOTS   = 3,
	WINDUP      = 0.5,
	RELOAD_TIME = 0.7,
	END_LAG     = 0.1,  -- 
	HITBOX_SIZE = Vector3.new(4, 4, 5),
	HITBOX_OFFSET = CFrame.new(0,0,-4),
	MAX_TARGETS = 6,
	PELLETS     = 5,
	SPREAD      = math.rad(8),
	MELEE_KB    = 10,

	DMG = DMGS.new(DMGS.weighEnum.Medium, DMGS.dmgFlag.blunt, 16, 0.6, 2),
	PROJ = table.freeze({
		speed       = 300,
		lifetime    = 0.2,
		maxDistance = 90,
		size        = Vector3.new(1, 1, 2),
		stopOnWorld = true,
		fxId        = "sgunProj",
		dmgTbl      = DMGS.new(DMGS.weighEnum.Medium, DMGS.dmgFlag.blunt, 3, 0.1, 1),
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
