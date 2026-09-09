--!strict
--[[
	A side weapon is worn on the LEFT ARM, is not in the wielded set, and owns
	ONE action fired by the `sideWep` bind. Shield is one with no action.

	Binds at construction like an ability, NOT like a weapon

	NOT feintable, and that costs no code: humObj:feint() only reaches
	wielding_weapon and using_ability
]]
local additiveVal = require(game.ReplicatedStorage.Packages.AdditiveValue)
local dmgUtils    = require(game.ServerScriptService.Utils.DmgUtils)
local humObjClass = require(game.ServerStorage.ROWA.Class.HumObj)

export type humObj = humObjClass.myself
export type useFunc = ((any) -> any)?
type atkTyp = dmgUtils.atkTyp

export type myself = {
	Name: string,
	_humObj: humObj,
	_model: Instance?,
	_track: AnimationTrack?,
	_animCon: any,

	-- AdditiveValues, matching WepBase and AbilityBase, so a card can target these too.
	atkRate: additiveVal.myself,
	atkRateOffset: additiveVal.myself,
	knockbackMult: additiveVal.myself,
	range: additiveVal.myself,
	isFeinted: boolean,

	use:     (self: myself, useFunc: useFunc) -> boolean,
	attach:  (self: myself) -> (),
	detach:  (self: myself) -> (),
	armPart: (self: myself) -> BasePart?,
	onWieldChanged: (self: myself, weapon: any?) -> (),

	PlayAnim: (self: myself, anim: Animation, speed: number?) -> AnimationTrack?,
	StopAnim: (self: myself) -> (),

	new: (humObj: humObj) -> myself,
	destroy: (self: myself) -> (),
}

local module = {
	Name = "SideWepBase",
}
module.__index = module
module.__tostring = function(self)
	return "SideWep(" .. tostring(self.Name) .. ")"
end

local CombatAction = require(game.ServerStorage.ROWA.Class.CombatAction)
setmetatable(module, { __index = CombatAction })

-- subclass constants
-- TODO these might be redundant
module.FEINT_CD_ID = "feint2"          -- shares the ability id: does NOT gate dashing
module.KNOCKBACK_USES_CHARSIZE = false -- like an ability, not a weapon

function module.new(humObj: humObj): myself
	local self = setmetatable({
		atkRateOffset = additiveVal.new(0),
		atkRate       = additiveVal.new(1),
		knockbackMult = additiveVal.new(1),
		range         = additiveVal.new(0),
		_humObj = humObj,
		isFeinted = false,
	}, module) :: any & myself

	-- a swing or a cast takes over the body, so the sidearm pose goes with it. Rising edge only, the same hook and shape emotes use to cancel themselves.
	-- our OWN use() takes the lock before its useFunc plays anything, so this never eats the anim it is about to draw.
	self._animCon = humObj.attacking.Changed:Connect(function(attacking: boolean)
		if attacking == true then self:StopAnim() end
	end)

	return self
end

function module.destroy(self: any)
	--- first, so the StopAnim below cannot be re-entered by an edge landing mid-teardown
	if self._animCon then
		self._animCon:Disconnect()
		self._animCon = nil
	end
	self:StopAnim()
	self:detach()
	if self.atkRate then self.atkRate:destroy() end
	if self.atkRateOffset then self.atkRateOffset:destroy() end
	if self.knockbackMult then self.knockbackMult:destroy() end
	if self.range then self.range:destroy() end
	self._humObj = nil
	table.clear(self)
	setmetatable(self, nil)
end

-- the arm everything hangs off. R6, same assumption as Shield and Haki.
function module.armPart(self: any): BasePart?
	local humObj = self._humObj
	local char = humObj and humObj.Hum and humObj.Hum.Parent
	local arm = char and char:FindFirstChild("Left Arm")
	return if arm and arm:IsA("BasePart") then arm :: BasePart else nil
end

--- default weld: the model carries its own Motor6D and a `Hold` part, which is the
--- rowa1 sidearm shape. Anything else (Shield's two welds) overrides this.
function module.attach(self: any)
	local model = self._model
	local arm = self:armPart()
	local humObj = self._humObj
	local char = humObj and humObj.Hum and humObj.Hum.Parent
	if model == nil or arm == nil or char == nil then return end

	local motor = model:FindFirstChild("Motor6D")
	local hold = model:FindFirstChild("Hold")
	if motor and motor:IsA("Motor6D") and hold and hold:IsA("BasePart") then
		motor.Part0 = arm
		motor.Part1 = hold
	end
	model.Parent = char
end

function module.detach(self: any)
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
end

--- only Shield cares; the base is inert so nothing else has to implement it.
function module.onWieldChanged(self: any, weapon: any?) end

--- THE action, same guards as AbilityBase.use minus mana. Subclasses pass their body in.
function module.use(self: any, useFunc: useFunc): boolean
	local humObj = self._humObj
	if humObj == nil then return false end
	local attacking = humObj.attacking
	if attacking.Value == true or humObj:canAttack() == false then
		return false
	end

	attacking.Value = true
	humObj:ChangeBlocking(false)

	local ok, err
	if useFunc then
		ok, err = pcall(useFunc, self)
	end
	if ok == false then
		warn("sideWep use err:", err)
	end

	if humObj.attacking then
		attacking.Value = false
	end
	return true
end

--- own track, own stop: ability anim state must not reach in and kill a sidearm draw.
function module.PlayAnim(self: any, anim: Animation, speed: number?): AnimationTrack?
	self:StopAnim()
	local humObj = self._humObj
	if humObj == nil or humObj.LoadAnimation == nil then return nil end
	local track = humObj:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	self._track = track
	humObj:PlayTrack(track, nil, nil,
		((speed or 1) - self.atkRateOffset.Value) / self.atkRate.Value)
	return track
end

function module.StopAnim(self: any)
	local track = self._track
	if track then
		track:Stop()
		self._track = nil
	end
end

module._feintWait = require(game.ServerStorage.ROWA.Abilities.AbilityBase.feintwait)

local HitboxQuery = require(game.ServerStorage.ROWA.Class.HitboxQuery)

local SIDEWEP_HITBOX_OPTS = table.freeze({
	rangeOf = function(sideWep)
		return sideWep.range.Value
	end,
	scaleByCharSize = false,
	floatBonus      = nil,
	retryOnMiss     = false,
	trackPrevHits   = false,
})

-- returns (hitboxObj, hits), same as WepBase and AbilityBase.
function module.hitbox(self: any, cf: CFrame, sz: Vector3, op: OverlapParams?, isRelativeToWorldSpace: boolean?)
	return HitboxQuery.query(self, cf, sz, SIDEWEP_HITBOX_OPTS, op, isRelativeToWorldSpace)
end

-- makeAtk / executeAttack / knockback / bodyForce / projectile / cooldowns: CombatAction.

return table.freeze(module)
