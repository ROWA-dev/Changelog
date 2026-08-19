--!strict
local baseClass = require(script.Parent:WaitForChild("EntityBase"))

local repliStore = game:GetService("ReplicatedStorage")
local Classes    = repliStore:WaitForChild("Class")
local Packages   = repliStore:WaitForChild("Packages")

local Signal        = require(Packages.Signal)
local Debug         = require(repliStore.Modules.Debug)
local AdditiveValue = require(Packages.AdditiveValue)

local valueBase = Packages.valueBase
local objValue  = require(valueBase)
local numVal    = require(valueBase.numberValue)
local boolVal   = require(valueBase.boolValue)

local cooldownsClass = require(Classes.cooldowns)
local limbTrails     = require(script.setupLimbTrails)
local charAnims      = require(script:WaitForChild("CharAnims"))

export type myself = baseClass.entity & {
	parryWindow: numVal.NumberValue,

	stun:     numVal.NumberValue,
	trueStun: numVal.NumberValue,
	floating: numVal.NumberValue, -- if value > 0 then FLOATTTT!
	targetFloatY: objValue.myself,

	timeScale:   AdditiveValue.myself,
	walkSpeed:   AdditiveValue.myself,
	slideSpeed:  AdditiveValue.myself,
	sprintSpeed: AdditiveValue.myself,
	maxPosture:  AdditiveValue.myself,
	maxMana:     AdditiveValue.myself,
	dashPower:   AdditiveValue.myself,
	postureHeal: AdditiveValue.myself,
	charSize:    AdditiveValue.myself,


	attacking: boolVal.BoolValue, -- maybe a state manager currated just for humobj....
	blocking:  boolVal.BoolValue,
	sliding:   boolVal.BoolValue,
	sprinting: boolVal.BoolValue,

	cooldowns: cooldownsClass.myself,

	--

	posture: numVal.NumberValue,
	mana:    numVal.NumberValue,


	timeStunned:	 number,
	_hyperUntil:     number,
	_lastAttack:     number,
	_numClimb:       number,
	_dashForce:		 LinearVelocity,
	_lastDashed: 	 number,
	_lastDashCancel: number,
	_lastJumped: 	 number,
	_lastBlocked:    number,
	_lastDoubleDash: number,
	_wantSlide: 	 boolean,
	_slideForce: 	 LinearVelocity?,
	_slideHipDrop:   number,

	charAnims:  charAnims.myself,
	limbTrails: limbTrails.myself,

	-- Methods
	setupController: (self:myself) -> (),
	stopDash: (self: myself, onlyStopAnims:boolean?) -> (),

	Stun:       (self: myself, stunTime: number, bypassArmour: boolean?) -> (),
	inStun:     (self: myself, timeOffset:number?) -> boolean,
	TrueStun:   (self: myself, trueStunTime: number) -> (),
	inTrueStun: (self: myself) -> boolean,
	inHyperArmour: (self: myself) -> boolean,
	isSwimming: (self: myself) -> boolean,
	
	Dash:       (self: myself, dir:Vector3, fromServer: boolean?) -> boolean,
	DashCancel: (self: myself, dir:Vector3, fromServer: boolean?) -> boolean,
	canDash:    (self: myself, offset:number?) -> boolean,

	ChangeSliding:   (self: myself, setTo:boolean) -> boolean,
	ChangeSprinting: (self: myself, setTo:boolean) -> boolean,
	
	PlayAnim: (self:myself, anim:Animation, fadeT:number?, weight:number?, speed:number?) -> AnimationTrack,
	PlayTrack: (self:myself, track:AnimationTrack, fadeT:number?, weight:number?, speed:number?)->(),
	initReplicateClient: (self: myself, remoteEvent:RemoteEvent) -> (),

	onDash: Signal.Signal<Vector3>,
	onDashCancel: Signal.Signal<Vector3>,
}

local module = {
	Name = "HumObj_Client",

	-- hyper armour. absolute tick() stamp like stun. class-table default so
	-- unarmoured entities cost nothing. owned by StatusEffects/HyperArmour.
	_hyperUntil = 0,

	--[[ Studs of HipHeight the current slide still owes back, 0 when upright.
		Class-level default so `stopSlideState` can never read nil on an entity
		that skipped `module.new`'s init (inert/Combatant defaults path). ]]
	_slideHipDrop = 0,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

-- Combatant contract. Behaviour-preserving and meant to be boring: HumObj
-- overrides every one of these for real, so it changes nothing there. It only
-- bites on a client-side HumObjClient, which never had ragdoll/statusEffects/
-- dmgRecord/cards and would previously have errored on them.
-- Must run before this file's table.freeze.
require(Classes:WaitForChild("Combatant")).applyInertDefaults(module, "HumObj_Client")

local setupChar = require(script:WaitForChild("setupCharacter"))
function module.new(hum: Humanoid):myself
	local abstract = baseClass.new(hum) :: baseClass.entity
	local self:myself = setmetatable(abstract, module) :: any
	
	self.attacking   = boolVal.new(false)
	self.blocking    = boolVal.new(false)
	self.sliding     = boolVal.new(false)
	self.sprinting   = boolVal.new(false)

	self.timeScale   = AdditiveValue.new(1)
	self.parryWindow = numVal.new(0.2)
	self.stun        = numVal.new(0)
	self.trueStun    = numVal.new(0)
	self.floating    = numVal.new(0)
	self.targetFloatY = objValue.new()
	self.posture     = numVal.new(80)
	self.mana        = numVal.new(0)

	self.slideSpeed  = AdditiveValue.new(28)
	self.sprintSpeed = AdditiveValue.new(14)
	self.maxPosture  = AdditiveValue.new(80)
	self.maxMana     = AdditiveValue.new(100)
	self.walkSpeed   = AdditiveValue.new(13)
	self.dashPower   = AdditiveValue.new(50)
	self.postureHeal = AdditiveValue.new(2)
	self.charSize    = AdditiveValue.new(1)

	self.timeStunned = 0
	self.cooldowns   = cooldownsClass.new()

	self.onDash       = Signal.new()
	self.onDashCancel = Signal.new()

	self._lastAttack = 0
	self._numClimb = 0
	self._lastDashed = 0
	self._lastJumped = 0
	self._lastBlocked = 0
	self._lastDoubleDash = 0
	self._wantSlide = false
--[[ How many studs of HipHeight the slide currently owes back. NEVER do
		`HipHeight -= 1.5` / `+= 1.5` in a pair -- a missed or doubled call
		leaks the offset forever (permanent crouched/floating character). Only
		`_enterSlideHip`/`_exitSlideHip` touch this. ]]
	self._slideHipDrop = 0
	
	--
	
	self.cooldowns:setCooldown("dashCancel", 1.5)
	self.cooldowns:setCooldown("dash", 1.5)
	self.cooldowns:setCooldown("slide", 2)
	
	--
	
	local character:any = hum.Parent
	self.limbTrails = limbTrails.new(character, self)
	self.charAnims = charAnims.new(self)

	local rootpart = self.HRootPart
	setupChar(hum, rootpart)

	self:AddConnection(
		self.Hum.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType) 
			if new == Enum.HumanoidStateType.Jumping then
				self._lastJumped = tick()
			end
		end),
		"stateChange"
	)

	self:AddConnection(self.attacking.Changed:Connect(function(boolean: boolean) 
		if boolean == true then
			self._lastAttack = tick()
			self:stopDash(true)
		end
	end), "attacking_stopDash")
	
	return self
end

function module.destroy(self:myself)
	self.isActive = false
	self.cooldowns:Destroy()
	self.parryWindow:destroy()
	self.walkSpeed:destroy()
	self.slideSpeed:destroy()
	self.dashPower:destroy()
	self.timeScale:destroy()
	self.stun:destroy()
	self.posture:destroy()
	self.mana:destroy()
	self.postureHeal:destroy()
	self.maxMana:destroy()
	self.maxPosture:destroy()
	self.trueStun:destroy()
	self.floating:destroy()
	self.targetFloatY:destroy()
	self.charAnims:destroy()
	self.charSize:destroy()
	baseClass.destroy(self)
end


----


local controller = require(script:WaitForChild("CharController"))
function module.setupController(self:myself)
	controller(self)
end

local function canSlide(self:myself): boolean
	if self.cooldowns == nil then return false end
	return (
		self.cooldowns:canTrigger("slide")
			and self.attacking.Value == false
			and tick() > self.stun.Value + 0.1 -- can only dash 0.1s after stun ends
			and self:inStun() == false
	)
end

function module.ChangeSprinting(self:myself, setTo:boolean): boolean
	if self.sprinting.Value ~= setTo then
		--print("set sprint:", setTo)
		self.sprinting.Value = setTo
		local SprintAnim = self.charAnims.Sprint
		if setTo == true then -- start sprint ing
			--print("play sprint")
			SprintAnim.Priority = Enum.AnimationPriority.Action
			self:PlayTrack(SprintAnim,0.2)
			self.walkSpeed:SetMod("sprint", 5) -- starts at 5?
		elseif setTo == false then -- stopped sprint ing
			--print("STOP sprint")
			SprintAnim.Priority = Enum.AnimationPriority.Movement
			SprintAnim:Stop(0.3)
			self.walkSpeed:RemoveMod("sprint")
		end
	end
	return true
end

local slidefx = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("slideFx"))
local repliUtils = game.ReplicatedStorage:WaitForChild("Utils")
local bodyMover = require(repliUtils:WaitForChild("bodymover"))
local SLIDE_HIP_DROP = 1.5

--[[ Every bit of state a slide turns ON lives here and gets turned OFF here,
	as ONE unit. It is idempotent and cheap when there is nothing to undo, so
	it doubles as the reaper for orphaned slide state: the controller pings
	`ChangeSliding(false)` every frame while not sliding, which lands here.

	DO NOT re-gate any of this behind `if slideModif then` again.
	That was the old shape and it meant "the walkSpeed mod is still present"
	decided whether HipHeight / the Slide track / torso collision came back.
	Any path that dropped the mod first (the standing-still crouch fast-path
	did exactly that) orphaned the rest of it PERMANENTLY -- character stuck
	crouched with the slide anim looping. `slideModif` only decides whether a
	slide JUMP is owed, nothing else. ]]
local function stopSlideState(self:myself&any, allowSlideJump:boolean)
	local Hum = self.Hum
	local SlideAnim = self.charAnims.Slide
	local slideModif:number? = self.walkSpeed:GetMod("slide")

	if slideModif == nil
		and self._slideHipDrop == 0
		and SlideAnim.IsPlaying == false
	then
		return -- nothing to undo, don't churn signals every frame
	end

	self.walkSpeed:RemoveMod("slide")

	local root = self.HRootPart
	if allowSlideJump and slideModif and root then
		local floor = workspace:FindPartOnRayWithIgnoreList(
			Ray.new(root.Position, Vector3.new(0,-root.Size.Y*3,0)),
			{root}
		)
		if Hum.Jump and floor ~= nil then
			local timeScale = self.timeScale.Value
			local slideJumpPower = math.max(slideModif, self.slideSpeed.Value)
			if self._slideForce then
				self._slideForce:Destroy()
			end

			local dir = (root.CFrame.LookVector*Vector3.new(1,0,1)).Unit
			local rDir = root.CFrame:VectorToObjectSpace(dir)
			task.spawn(slidefx, root, rDir)
			Debug.dprint("slide jump")
			self._slideForce = bodyMover(
				dir*slideJumpPower*1*timeScale,
				root,
				0.4/timeScale
			)
		end
	end

	-- absolute, not `+= 1.5`: pays back exactly what was taken, once
	local owedHip = self._slideHipDrop
	if owedHip ~= 0 then
		self._slideHipDrop = 0
		Hum.HipHeight += owedHip
	end

	SlideAnim.Priority = Enum.AnimationPriority.Action
	SlideAnim:Stop(0.3)

	local chr:any = Hum.Parent
	local torso:BasePart? = if chr then chr:FindFirstChild("Torso") else nil
	if torso then
		torso.CanCollide = true
		torso.CollisionGroup = "Default"
	end

	if root then
		local RootJoint:Motor6D = root:FindFirstChild("RootJoint")::any
		if RootJoint then
			RootJoint.C1 = RootJoint.C0
		end
	end
end

function module.ChangeSliding(self:myself, setTo:boolean): boolean
	local crouchAnim = self.charAnims.Crouch
	--self._wantSlide = setTo

--[[ Standing still -> the slide key crouches instead of sliding.
		This fast-path must NEVER write `sliding.Value` for setTo==false
		and then fall through. <<< It used to, and the `sliding.Value ~= setTo`
		guard further down then read false and skipped the ENTIRE teardown,
		leaving walkSpeed's +slideSpeed mod on with sliding.Value==false --
		nothing decays it (the decay lives in the controller's sliding==true
		branch) so you keep the anim and fly around steerable at ~41 WS.
		That is the "stuck fast slide" bug. Both branches return. ]]
	if setTo == true and self.Hum.MoveDirection == Vector3.zero and self.sliding.Value ~= true then
		stopSlideState(self, false) -- reap residue before crouching over it
		self.sliding.Value = true
		self:PlayTrack(crouchAnim, 0.1)
		return true
	end

	if setTo == false and crouchAnim.IsPlaying then
		crouchAnim:Stop(0.1)
		self.sliding.Value = false
		stopSlideState(self, false)
		return true
	end

	if setTo == false and self.sliding.Value == false then
		stopSlideState(self, false) -- orphan reaper, no-ops when clean
		return false
	end

	if setTo == true then
		while canSlide(self) == false and self._wantSlide do
			--print("waiting can slide")
			task.wait()
		end
		--print(canSlide(self), self._wantSlide)
		if canSlide(self) == false then
			return false
		end
	end

	if self.sliding.Value ~= setTo then
		local Hum = self.Hum
		local chr:any = Hum.Parent
		local torso:BasePart = chr:FindFirstChild("Torso")
		local root = self.HRootPart

	--[[ Only ENTERING needs the torso (collision swap). Bailing out of the
			stop path on a missing torso would strand the speed mod + HipHeight,
			which is the same permanent-fast-slide failure this function exists
			to prevent -- stopSlideState handles a nil torso itself. ]]
		if torso == nil and setTo == true then
			return false
		end

		self.sliding.Value = setTo
		
		local timeScale = self.timeScale.Value
		local iTimeScale = 1/timeScale

		local SlideAnim = self.charAnims.Slide
		if setTo == true and canSlide(self) == true then -- start slide ing
			self.cooldowns:trigger("slide")
			self:stopDash()
			torso.CanCollide = false
			torso.CollisionGroup = "no"

			self.walkSpeed:SetMod("slide", self.slideSpeed.Value)
			-- book the drop instead of assuming a matching `+= 1.5` later.
			-- guarded so a double-enter can't stack two drops on one payback.
			if self._slideHipDrop == 0 then
				self._slideHipDrop = SLIDE_HIP_DROP
				Hum.HipHeight -= SLIDE_HIP_DROP
			end
			SlideAnim.Priority = Enum.AnimationPriority.Action2
			self:PlayTrack(SlideAnim, 0.1)

			local dir = root.CFrame.LookVector
			local rDir = root.CFrame:VectorToObjectSpace(dir)
			task.spawn(slidefx, root, rDir)
			self._slideForce = bodyMover(
				dir*self.slideSpeed.Value*1.6*timeScale,
				root,
				0.1*iTimeScale,
				false,
				-1
			)
		elseif setTo == false then				  -- stopped slide ing
			stopSlideState(self, true)
		end
	end
	return false
end

function module.stopDash(self:myself, onlyStopAnims:boolean?)
	if onlyStopAnims ~= true then
		game.Debris:AddItem(self._dashForce, 0)
	end
	self.charAnims:stopDashAnims()
end

-- bypassArmour pierces hyper armour. only TrueStun passes it.
function module:Stun(stunTime:number, bypassArmour:boolean?)
	if not bypassArmour and tick() < self._hyperUntil then return end

	if stunTime > 0 then
		self:stopDash()
	end
	self.timeStunned = stunTime
	self.stun.Value = math.max(
		self.stun.Value,
		tick() + stunTime
	)
end

function module:TrueStun(trueStunTime:number)
	self.trueStun.Value = math.max(
		self.stun.Value,
		tick() + trueStunTime
	)
	-- must pass the flag. without it the gate eats this silently: trueStun.Value
	-- is already set so inStun() looks right, but stun.Value never changes and
	-- the stun.Changed replication never fires -> client thinks it is free.
	self:Stun(trueStunTime, true)
end

function module:inTrueStun(): boolean
	return tick() < self.trueStun.Value
end

--- Armoured right now? Ask this, never `tick() < self._hyperUntil` by hand --
--- anything that INTERRUPTS a victim has to check it, not just :Stun.
function module:inHyperArmour(): boolean
	return tick() < self._hyperUntil
end

function module:inStun(timeOffset:number?): boolean
	local now = tick() + (timeOffset or 0)
	return now < self.stun.Value or now < self.trueStun.Value
end

function module:isSwimming(): boolean
	local WATER_Y = -3.5 + 1
	return self.HRootPart.Position.Y <= WATER_Y
end

function module.canDash(self:myself, offset:number?): boolean
	local now = tick() + (offset or 0)
	local isLastAtk = (now - self._lastAttack) < 1
	return 
		self.cooldowns:canTrigger("dash", offset) == true
		and self:inStun(offset) ~= true
		and now > self.stun.Value + (if isLastAtk then 0.3 else 0.1) -- can only dash 0.1s after stun ends
		and now > self._lastDashed + 0.1
		and now > self.cooldowns:lastUsedAt("feint") + 0.1 -- can only dash 0.1s after a feint
		and self.attacking.Value == false
end


local dashfx = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("dashFx"))
function module.Dash(self:myself, dir:any, fromServer:boolean?): boolean
	if self:canDash() == false then return false end
	Debug.dprint((tick() - self._lastAttack))
	
	local hum = self.Hum
	local rootpart = self.HRootPart
	if rootpart == nil then
		warn("rootpart not found")
		return false
	end
	if dir == nil or dir == Vector3.zero then
		dir = rootpart.CFrame.LookVector
	end

	local cooldowns = self.cooldowns
	local dashCD = cooldowns:get("dash")
	

	local timeScale = self.timeScale.Value
	local iTimeScale = 1/timeScale


	local dashPower = self.dashPower.Value * self.charSize.Value * timeScale

	local dashTime = 0.4*iTimeScale
	local dashFadeT = 0.6*iTimeScale

	self._lastDashed = tick()
	if fromServer ~= true then
		if self.sliding.Value == true then -- stop sliding when dash while sliding
			self:ChangeSliding(false)
		end

		local anims = self.charAnims
		local localDir = rootpart.CFrame:VectorToObjectSpace(dir)
		self:stopDash()
		if localDir.Z > 0.6 then      -- backwards
			local canCancel = cooldowns:canTrigger("dashCancel")
			dashPower -= 10
			if canCancel == true then
				self:PlayTrack(anims.dashB, 0)
			else
				dashTime = 1*iTimeScale
				dashFadeT = 1*iTimeScale
				self:PlayTrack(anims.dashB2, 0.1)
				cooldowns:trigger("dashCancel", 2)
			end
		elseif localDir.Z < -0.6 then -- forward
			local canCancel = cooldowns:canTrigger("dashCancel")
			if canCancel == true then
				self:PlayTrack(anims.dashF,0.1)
			else
				self:PlayTrack(anims.dashF2,0.1)
			end
		elseif localDir.X > 0 then    -- right
			self:PlayTrack(anims.dashR,0.1)
		else					      -- left
			self:PlayTrack(anims.dashL,0.1)
		end
	end

	local dashCooldown = dashCD.Value * iTimeScale -- default
	local rDir = rootpart.CFrame:VectorToObjectSpace(dir)
	if hum.FloorMaterial == Enum.Material.Air and self:isSwimming() == false then
		dashTime = 0.2 * iTimeScale
		dashPower += 10
		dashCD:Trigger(dashCooldown + 0.4)
		cooldowns:trigger("dashCancel")
	end

	local canCancel = cooldowns:canTrigger("dashCancel")
	if canCancel == false then
		dashCooldown += 0.7
	end

	dashCD:Trigger(dashCooldown)

	if fromServer == true and game["Run Service"]:IsServer() then
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("dash", rootpart, rDir)
	else
		self._dashForce = bodyMover(rDir*dashPower, rootpart, dashTime, true, dashFadeT)
		task.spawn(dashfx, rootpart, rDir)
	end

	task.spawn(function()
		self.limbTrails:enable(true)
		task.wait(0.6 * iTimeScale)
		self.limbTrails:enable(false)
	end)

	self.onDash:Fire(dir)

	return true
end

local function canDashCancel(self:myself): boolean
	local cooldowns = self.cooldowns
	return (
		cooldowns:canTrigger("dashCancel") == true
			and cooldowns:canTrigger("dash") == false -- if cant dash then dashcancel duh
			and self.attacking.Value == false
			and self:inStun() == false
			and tick() <= self._lastDashed + 1/self.timeScale.Value-- can dash cancel 1s after dashing
	)
end

function module.DashCancel(self:myself, dir:Vector3, fromServer:boolean?): boolean
	if canDashCancel(self) == false then
		return false
	end

	self:stopDash()
	self._lastDashCancel = tick()

	if dir ~= Vector3.zero then
		local timeScale = self.timeScale.Value
		local iTimeScale = 1/timeScale
		
		local dcPower = 30 * timeScale
		local dcTime = 0.2 * iTimeScale
		local dcDecay = 0.4 * iTimeScale

		
		local rootpart = self.HRootPart
		local rDir = rootpart.CFrame:VectorToObjectSpace(dir) * Vector3.new(1,0,1)
		local mover = bodyMover(rDir*dcPower, rootpart, dcTime, true, dcDecay)
		self._dashForce = mover

		local anims = self.charAnims
		local localDir = rootpart.CFrame:VectorToObjectSpace(dir)
		if localDir.X > 0 then    -- right
			self:PlayTrack(anims.dashRT, 0.1)
		else					   -- left
			self:PlayTrack(anims.dashLT, 0.1)
		end
	end

	local cooldowns = self.cooldowns
	cooldowns:trigger("dashCancel")
	cooldowns:Reset("dash")
	cooldowns:get("dash").lastUsed = 0
	self.onDashCancel:Fire(dir)

	return true
end

function module.PlayTrack(self:myself, track:AnimationTrack, fadeT:number?, weight:number?, speed:number?)
	local timeScale = self.timeScale.Value
	if speed == nil then
		speed = timeScale
	else
		speed *= timeScale
	end
	if fadeT == nil then
		fadeT = 0.1/timeScale
	else
		fadeT /= timeScale
	end
	return track:Play(fadeT, weight, speed)
end

function module.PlayAnim(self:myself&any, anim:Animation, fadeT:number?, weight:number?, speed:number?): AnimationTrack
	local prev = self._prevAnim
	if prev then
		prev:Stop()
		prev = nil
	end
	
	local track = self:LoadAnimation(anim)
	self:PlayTrack(track, fadeT, weight, speed)
	
	self._prevAnim = track
	return track
end


----

local getDashDir = require(repliStore:WaitForChild("Utils"):WaitForChild("getDashDir"))
function module.initReplicateClient(self:myself, remoteEvent:RemoteEvent)
	self.maxPosture:initReplicateClient(5, remoteEvent)
	self.walkSpeed:initReplicateClient(6, remoteEvent)
	self.sprintSpeed:initReplicateClient(15, remoteEvent)
	self.dashPower:initReplicateClient(16, remoteEvent)
	self.postureHeal:initReplicateClient(17, remoteEvent)
	self.slideSpeed:initReplicateClient(18, remoteEvent)
	self.charSize:initReplicateClient(19, remoteEvent)
	self.timeScale:initReplicateClient(21, remoteEvent)
	self.maxMana:initReplicateClient(22, remoteEvent)

	
	local rcon = remoteEvent.OnClientEvent:Connect(function(id:number, value:any, ...) 
		--print("from HUMOBJCLI", id, value)
		if id == 1 then
			--self.stun.Value = value
			if value == 0 then
				self.timeStunned = 0
				self.stun.Value = 0
			end
			self:Stun(value)
		elseif id == 2 then
			self.attacking.Value = value
		elseif id == 3 then
			self.blocking.Value = value
		elseif id == 4 then
			self.posture.Value = value
		elseif id == 7 then
			self.parryWindow.Value = value
		elseif id == 8 then
			self:Dash(getDashDir(self), true)
		elseif id == 9 then
			self:DashCancel(getDashDir(self), true)
		elseif id == 10 then
			local newCd = ...
			self.cooldowns:setCooldown(value, newCd)
		elseif id == 11 then
			local cooldownName = value
			local newCd = ...
			if newCd and self.cooldowns:get(cooldownName) == nil then
				self.cooldowns:setCooldown(cooldownName, newCd)
			end
			if newCd == 0 then
				self.cooldowns:Reset(cooldownName)
				return
			end
			if cooldownName == "dash" or cooldownName == "dashCancel" then
				local timeDiff = (tick() - self.cooldowns:lastUsedAt(cooldownName))
				if timeDiff > 0.4 then -- or if somehow 400 ping :skull:
					self.cooldowns:trigger(cooldownName, newCd)
				else
					self.cooldowns:quietTrigger(cooldownName, newCd)
				end
			else
				self.cooldowns:trigger(cooldownName, newCd)
			end
		elseif id == 12 then
			self.floating.Value = value
			-- 13 is taken by _lastJumped stateChange
		elseif id == 14 then
			-- duration on the wire, absolute timestamp locally. 0 = clear.
			-- Written straight to the field: :TrueStun would re-route through
			-- :Stun and double up the stun that id 1 has already delivered.
			self.trueStun.Value = if value > 0 then tick() + value else 0
		elseif id == 20 then
			self.targetFloatY.Value = value
			-- 21 is taken by timescale
		elseif id == 23 then
			self.mana.Value = value
		end
	end)
	self:AddConnection(rcon, "repliClient")

	self:AddConnection(
		self.Hum.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType) 
			if new == Enum.HumanoidStateType.Jumping then
				remoteEvent:FireServer(13)
				self._lastJumped = tick()
			end
		end),
		"stateChange" -- override default
	)

	self:AddConnection(self.sprinting.Changed:Connect(function(boolean: boolean)
		remoteEvent:FireServer(1, boolean)
	end), "repl_c2s_1_sprinting")
	self:AddConnection(self.sliding.Changed:Connect(function(boolean: boolean) 
		remoteEvent:FireServer(14, boolean)
	end), "repl_c2s_14_sliding")
end

return table.freeze(module)
