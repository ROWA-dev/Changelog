--!strict
-- Shield - the off-hand that has no action. Arm while a weapon is out, back when not.
-- Was ROWA/Cards/Shield; the card is now only the grant.
local baseClass = require(script.Parent:WaitForChild("SideWepBase"))

export type myself = baseClass.myself & {
	_modKey: string,
	_blockTrack: AnimationTrack?,
}

local MAX_POSTURE = 40

local module = {
	Name = "Shield",
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

--- the two welds live in the model; only one is ever enabled.
local function pose(self: any, weapon: any?)
	local model = self._model
	local humObj = self._humObj
	local char = humObj and humObj.Hum and humObj.Hum.Parent
	if model == nil or char == nil then return end

	local handle = model:FindFirstChild("Handle")
	if handle == nil then return end
	local armWeld = handle:FindFirstChild("ArmWeld")
	local backWeld = handle:FindFirstChild("BackWeld")
	if not (armWeld and armWeld:IsA("Weld") and backWeld and backWeld:IsA("Weld")) then return end

	armWeld.Enabled = false
	backWeld.Enabled = false
	if weapon then
		local arm = self:armPart()
		if arm then
			armWeld.Part0 = handle :: BasePart
			armWeld.Part1 = arm
			armWeld.Enabled = true
		end
	else
		local torso = char:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			backWeld.Part0 = handle :: BasePart
			backWeld.Part1 = torso
			backWeld.Enabled = true
		end
	end
end

function module.new(humObj): myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self: myself = setmetatable(abstract, module) :: any
	self._modKey = "shield:" .. tostring(humObj.entityId)

	humObj.maxPosture:SetMod(self._modKey, MAX_POSTURE)
	humObj.posture.Value = math.min(humObj.posture.Value + MAX_POSTURE, humObj.maxPosture.Value)

	local track = humObj:LoadAnimation(script:WaitForChild("ShieldHold") :: Animation)
	track.Priority = Enum.AnimationPriority.Action3
	self._blockTrack = track
	humObj:setBlockAnimOverride(track)

	self._model = script:WaitForChild("Model"):Clone()
	;(self._model :: any).Name = "TalentShield"
	return self
end

--- overrides the base Motor6D weld: this one has two welds and picks by wield state.
function module.attach(self: any)
	local model = self._model
	local humObj = self._humObj
	local char = humObj and humObj.Hum and humObj.Hum.Parent
	if model == nil or char == nil then return end
	model.Parent = char
	pose(self, humObj.wielding_weapon)
end

--- HumObj forwards this on every wield change.
function module.onWieldChanged(self: any, weapon: any?)
	pose(self, weapon)
end

function module.destroy(self: any)
	local humObj = self._humObj
	if humObj then
		humObj:setBlockAnimOverride(nil)
		humObj.maxPosture:RemoveMod(self._modKey)
		humObj.posture.Value = math.min(humObj.posture.Value, humObj.maxPosture.Value)
	end
	if self._blockTrack then self._blockTrack:Destroy() end
	baseClass.destroy(self)
end

return table.freeze(module)
