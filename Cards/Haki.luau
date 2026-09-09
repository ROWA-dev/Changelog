--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_modKey: string,
	_healthApplied: boolean,
	_hardened: {[Instance]: {any}},
}

local WEAPON_DAMAGE = 0.1
local WEAPON_POSTURE = 0.1
local MAX_POSTURE = 20
local MAX_HEALTH = 10

local HAKI_COLOR = Color3.new(0, 0, 0)
local HAKI_TRAIL = ColorSequence.new(Color3.new(0.662745, 0.364706, 1))
local ARMS = { "Left Arm", "Right Arm" }

-- every instance we recolour is remembered, so destroy restores exactly what we changed
-- and one is never hardened (or saved) twice. Trails keep their own shape: colour, no material.
local function harden(self:myself, inst:Instance?)
	if inst == nil or self._hardened[inst] then return end
	if inst:IsA("BasePart") then
		self._hardened[inst] = { inst.Color, inst.Material }
		inst.Color = HAKI_COLOR
		inst.Material = Enum.Material.Glass
	elseif inst:IsA("Trail") then
		self._hardened[inst] = { inst.Color }
		inst.Color = HAKI_TRAIL
	end
end

-- weapon models are per-instance clones (script.Model:Clone()), never the template.
local function hardenWeapon(self:myself, weapon:any?)
	local model = weapon and weapon._model
	if model == nil then return end
	harden(self, model)
	for _, d in ipairs(model:GetDescendants()) do harden(self, d) end
end

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._modKey = "haki:" .. tostring(self.randID)
	self._healthApplied = false
	self._hardened = {}

	humObj.wepDmgMult:SetMod(self._modKey, WEAPON_DAMAGE)
	humObj.maxPosture:SetMod(self._modKey, MAX_POSTURE)
	humObj.posture.Value = math.min(humObj.posture.Value + MAX_POSTURE, humObj.maxPosture.Value)

	local hum:Humanoid? = humObj.Hum
	if hum and hum.Parent then
		hum.MaxHealth += MAX_HEALTH
		hum.Health = math.min(hum.Health + MAX_HEALTH, hum.MaxHealth)
		self._healthApplied = true

		local char = hum.Parent
		for _, name in ipairs(ARMS) do harden(self, char:FindFirstChild(name)) end
	end

	-- weapon attacks only, same scope as the damage mod above. Fists are a weapon
	-- (Weps id 1), so the hardened arms are covered and abilities are not.
	self:addConnection(humObj.beforeAttack:Connect(function(attack)
		if attack:isWep() then attack.postureMult += WEAPON_POSTURE end
	end), "hakiPosture")

	-- whatever is already on the body, then anything wielded later.
	for _, w in ipairs(humObj.equippedWeapons) do hardenWeapon(self, w) end
	hardenWeapon(self, humObj.heldWeapon)
	self:addConnection(humObj:wieldChanged():Connect(function(weapon)
		hardenWeapon(self, weapon)
	end), "hakiWield")

	return self
end

function module.destroy(self:myself)
	self:remConnection("hakiWield")
	self:remConnection("hakiPosture")
	for inst, was in pairs(self._hardened) do
		local target = inst :: any -- BasePart or Trail, both restore off .Color
		target.Color = was[1]
		if was[2] then target.Material = was[2] end
	end
	table.clear(self._hardened)

	local humObj = self._humObj
	if humObj then
		humObj.wepDmgMult:RemoveMod(self._modKey)
		humObj.maxPosture:RemoveMod(self._modKey)
		humObj.posture.Value = math.min(humObj.posture.Value, humObj.maxPosture.Value)

		local hum:Humanoid? = humObj.Hum
		if self._healthApplied and hum and hum.Parent then
			hum.MaxHealth = math.max(1, hum.MaxHealth - MAX_HEALTH)
			hum.Health = math.min(hum.Health, hum.MaxHealth)
		end
	end
	baseClass.destroy(self)
end

return table.freeze(module)
