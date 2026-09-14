--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local AttackClass = require(game.ServerStorage.ROWA.Class.AttackClass)
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

export type myself = baseClass.myself & { _crown: BasePart? }

local KNOCK_THRESHOLD = 9.6
local PROC_RANGE = 15
local MANA_DRAIN = 8
local BURN_TIME, BURN_DAMAGE = 10, 3

local EXPLOSION = table.freeze({
	weight = dmgUtils.weighEnum.Heavy,
	type = dmgUtils.dmgFlags.fire,
	dmg = 6,
	stun = 0.2,
	posMult = 1,
	onHit = function(attack: any)
		local owner = attack.myEntity
		local victim = attack.enemyEntity
		owner.statusEffects:apply(owner.statusEffects.Burn, BURN_TIME, BURN_DAMAGE)
		victim.statusEffects:apply(owner.statusEffects.Burn, BURN_TIME, BURN_DAMAGE)
		fireVFX("emperorFlame", victim.HRootPart.Position, attack.atkDir)
	end,
})

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj): myself
	local self: myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(
		humObj.beforeAttack:Connect(function(attack: any)
			if attack.myEntity ~= humObj or attack.knockback == nil then
				return
			end
			local victim = attack.enemyEntity
			local aroot = humObj.HRootPart
			local vroot = victim and victim.HRootPart
			if aroot == nil or vroot == nil then
				return
			end
			local force = attack.knockback.force
			if force.Magnitude > KNOCK_THRESHOLD and (vroot.Position - aroot.Position).Magnitude < PROC_RANGE then
				attack.emperorFlameForce = force
			end
		end),
		"emperorMark"
	)

	self:addConnection(
		humObj.onAttack:Connect(function(attack: any)
			local force = attack.emperorFlameForce
			if humObj.isActive ~= true or force == nil or attack.myEntity ~= humObj then
				return
			end
			if not (attack:isHit() or attack:isBlocked()) then
				return
			end

			local victim = attack.enemyEntity
			if victim == nil or victim.isActive ~= true then
				return
			end
			humObj:setMana(humObj:manaNow() - MANA_DRAIN)

			local dir = if force.Magnitude > 0 then force.Unit else attack.atkDir
			local blast = AttackClass.new(EXPLOSION, humObj, victim, dir)
			blast:Execute()
			if not blast:isHit() then
				return
			end

			local root = humObj.HRootPart
			if root == nil then
				return
			end
			local flat = Vector3.new(force.X, 0, force.Z)
			local recoilDir = if flat.Magnitude > 0 then -flat.Unit else -root.CFrame.LookVector
			humObj:bodyForce(recoilDir * 10.8 + Vector3.new(0, 1.2, 0), 0.1, false, -1)
		end),
		"emperorProc"
	)

	local char = humObj.Model
	local head = char and char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local crown = script.emperor:Clone()
		local weld = crown:FindFirstChild("Weld")
		if weld and weld:IsA("Weld") then
			weld.Part1 = head
			crown.Parent = char
			self._crown = crown
		else
			crown:Destroy()
		end
	end

	return self
end

function module.destroy(self: myself)
	self:remConnection("emperorMark")
	self:remConnection("emperorProc")
	if self._crown then
		self._crown:Destroy()
	end
	baseClass.destroy(self)
end

return table.freeze(module)