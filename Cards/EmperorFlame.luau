--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local AttackClass = require(game.ServerStorage.ROWA.Class.AttackClass)
local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local fireTint = require(game.ReplicatedStorage.Modules.fireTint)

export type myself = baseClass.myself & { _crown: BasePart? }

local KNOCK_THRESHOLD = 9.6
local PROC_RANGE = 15
local MANA_DRAIN = 8
local MANA_REQ = 10
local BURN_TIME, BURN_DAMAGE = 10, 2

local EXPLOSION = table.freeze({
	weight = dmgUtils.weighEnum.Heavy,
	type = dmgUtils.dmgFlags.fire,
	dmg = 6,
	stun = 0.2,
	posMult = 1,
	onHit = function(attack: any)
		local owner = attack.myEntity
		local victim = attack.enemyEntity
		owner.statusEffects:apply(owner.statusEffects.Burn, BURN_TIME, BURN_DAMAGE, owner)
		victim.statusEffects:apply(owner.statusEffects.Burn, BURN_TIME, BURN_DAMAGE, owner)
		fireVFX("emperorFlame", victim.HRootPart.Position, attack.atkDir, owner.Model)
	end,
})

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

-- rebuilt rather than repainted, since fireTint only maps one way and losing the hue must restore it
local function wearCrown(self: myself)
	if self._crown then
		self._crown:Destroy()
		self._crown = nil
	end
	local char = self._humObj.Model
	local head = char and char:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local crown = script.emperor:Clone()
	local weld = crown:FindFirstChild("Weld")
	if not (weld and weld:IsA("Weld")) then
		crown:Destroy()
		return
	end
	weld.Part1 = head
	fireTint(crown, char)
	crown.Parent = char
	self._crown = crown
end

function module.new(humObj): myself
	local self: myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(
		humObj.beforeAttack:Connect(function(attack: any)
			if attack.myEntity ~= humObj or attack.knockback == nil or attack.dmgTbl.stunMeOnParried == 0 then
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
		end)
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
			if victim == nil or victim.isActive ~= true or humObj:manaNow() < MANA_REQ then
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
		end)
	)

	wearCrown(self)
	-- cards load in pick order, so AzureFlames can set the hue after this
	local char = humObj.Model
	if char then
		self:addConnection(char:GetAttributeChangedSignal("fireHue"):Connect(function()
			wearCrown(self)
		end))
	end

	return self
end

function module.destroy(self: myself)
	if self._crown then
		self._crown:Destroy()
	end
	baseClass.destroy(self)
end

return table.freeze(module)