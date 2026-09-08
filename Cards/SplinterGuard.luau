--!strict
-- parrying a "strong (>= 40 posturedmg)" sprays the blow outward

local baseClass = require(script.Parent:WaitForChild("cardBase"))
local HitBox = require(game.ServerScriptService.HitBox)
local AttackClass = require(game.ServerStorage.ROWA.Class.AttackClass)
local DMGS = require(game.ServerStorage.ROWA.Class.DMGS)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

export type myself = baseClass.myself

local RADIUS = 14
local BOX = Vector3.new(RADIUS * 2, 10, RADIUS * 2)

local CD_ID, COOLDOWN = "splinterGuard", 3
local DMG = DMGS.new(DMGS.weighEnum.Medium, DMGS.dmgFlag.slash, 15, 0.3, 1.5)

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	humObj.cooldowns:setCooldown(CD_ID, COOLDOWN)

	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isParried() then return end
		local postureDmg = attack:CalculatePostureDmg()
		if postureDmg < 40 then return end
		
		local cooldowns = humObj.cooldowns
		if not cooldowns:canTrigger(CD_ID) then return end
		cooldowns:trigger(CD_ID)

		local root = humObj.HRootPart
		if root == nil then return end

		local fx:ParticleEmitter = root:FindFirstChild("spliterguard") or script.spliterguard:Clone()
		fx.Parent = root
		fx:Emit(postureDmg)
		
		-- ignore me
		local attacker = attack.myEntity
		
		for _, victim in ipairs(HitBox.hitbox(CFrame.new(root.Position), BOX, nil, humObj.Hum)) do
			if victim ~= attacker and victim.HRootPart then
				local dir = victim.HRootPart.Position - root.Position
				if dir.Magnitude <= 0 then dir = root.CFrame.LookVector end
				AttackClass.new(DMG, humObj, victim, dir):Execute()
			end
		end
		
		print("SPLINTER RAH")
	end), "splinterGuard")

	return self
end

function module.destroy(self:myself)
	self:remConnection("splinterGuard")
	baseClass.destroy(self)
end

return table.freeze(module)
