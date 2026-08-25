--!strict
-- Smash - uppercut into the air, flash-step up after them, drive them back into the ground.
-- ONE authored track carries all four segments and the move SEEKS between them rather than swapping clips; MARK below is the spec.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Smash"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local pinTo    = require(game.ServerStorage.ROWA.Modules.pinTo)

-- shared with Divide.
local UCUT = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	-- 0.8s FLAT ragdoll (no ground check) so they flop through the launch; the hang is topped up at the pin, see HOLD.
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * -40)
	end,
}

-- kept low deliberately: this lands off ONE confirmed uppercut.
local SSMASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 20,
	stun     = 0.6,
	posMult  = 3,
	parryH   = -0.04,
	-- sounds: HeavyHit, wet_punch2
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyHit", "wet_punch2")
	end,
}

local SLOW_KEY = "smash"

-- the throw AND the angle of its fx: one pair with two users, so the pillar and the victim cannot drift apart.
local LAUNCH_FWD, LAUNCH_UP = 15, 21

-- roll about the pillar's own axis: decides where the two rings sit around the column, not the lean.
local FX_ROLL = CFrame.Angles(math.rad(-180), math.rad(75), 0)

-- marks along the one track, in seconds. THE ANIMATION IS THE SPEC: re-export the clip and only these move.
local MARK = table.freeze({
	UPPERCUT   = 0.70,
	FREEZE_END = 0.80,
	PREP_END   = 1.45,
	MISS_IN    = 1.85,
	MISS_OUT   = 2.13,
	TELE_IN    = 2.60,
	SLAM       = 3.28,
	TRACK_END  = 3.87,
})

-- the pin captures a FIXED world point, so it must be taken at the top; grab earlier and they hang low.
local APEX = MARK.FREEZE_END + 0.38

-- how long the victim hangs pinned: derived from the marks, never typed as its own number.
local HOLD = (MARK.PREP_END - APEX) + (MARK.SLAM - MARK.TELE_IN)

-- !! this hold must WIN against the launch it just ate: pinTo's default arm loses to the live knockback mover, so passing `axes` is required.
local FREEZE_HOLD = table.freeze({
	axes = Vector3.one,
	responsiveness = 200,
	maxTime = 0.35,
})

-- where the caster is hauled for the flash-step, relative to the pinned victim: up and slightly short, or the step ends INSIDE them.
local CASTER_OVER = Vector3.new(0, 7, 0)
local CASTER_BACK = 2

-- !! the air-combo float and this move cannot both own the victim's height; it arms from blockedOrHit AFTER dmgTbl.onHit, so this must run after executeAttack.
local function killFloat(entity:any)
	if entity == nil then return end
	if entity.floating then entity.floating.Value = 0 end
	if entity.targetFloatY then entity.targetFloatY.Value = nil end
end

-- jump the single track to a mark; a second :PlayAnim would stop this track and load another.
local function seek(track:AnimationTrack?, to:number)
	if track == nil then return end
	track.TimePosition = to
end

local function useFunc(this:myself)
	local cooldownID = "smash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	-- the WHOLE move. Nothing below may call :PlayAnim again.
	local anim = this:PlayAnim(script.Smash, 0, 1, 1)

	fireVFX("hideTool", char)
	-- LEFT arm: the clip throws the uppercut with the left, so the gather must be on the hand that connects.
	fireVFX("smashCharge", char:FindFirstChild("Left Arm"), 1.2)

	-- plays on the root for the whole gather
	local chargeSnd = script["magic attack sound"]:Clone()
	chargeSnd.Parent = humObj.HRootPart
	chargeSnd:Play()
	chargeSnd.TimePosition = 0.1
	game.Debris:AddItem(chargeSnd, 6)

	-- set at the apex, nil until then; declared above bail() because bail has to see it.
	local release:(()->())? = nil

	-- EVERY exit path owes the arms, the tool and the charge, or players end up armless.
	local function restore()
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		fireVFX("smashCharge", nil, 0)
		fireVFX("showArms", char)
		game.Debris:AddItem(chargeSnd, 0)
	end

	-- cancelled: kill the track, drop the pin, put the player back together. A stranded pin drags the victim around forever.
	local function bail()
		if release then
			release()
			release = nil
		end
		if anim then anim:Stop(0.1) end
		restore()
	end

	-- 0.00 -> 0.70: the punch comes out on the frame the clip punches on.
	if this:feintWait(MARK.UPPERCUT) then
		bail()
		return
	end
	
	-- the slow starts at the PUNCH, not the windup, so you keep your feet while gathering.
	humObj.walkSpeed:SetMod(SLOW_KEY, -8)


	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(7, 7, 7))

	-- ONE victim goes up, but a PARRY IS NOT A CONNECT and must not end the scan; resolveParry stuns the attacker so the next feintWait bails anyway.
	local caught = nil
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(UCUT, enemy, forward)
		-- !! NO DECAY: a decaying vertical mover fights gravity down its own ramp and stops launching at all.
		attack.knockback = this:knockback(
			forward * LAUNCH_FWD + Vector3.new(0, LAUNCH_UP, 0), 0.25, false, -1)
		this:executeAttack(attack)

		-- parried, dodged or aborted: someone behind them may still eat it, so keep scanning.
		if not (attack:isHit() or attack:isBlocked()) then continue end

		-- ~the punch -> slam gap, so the launch carries the whole ride; a BLOCK does not get this but still counts as a catch.
		if attack:isHit() and enemy.TrueStun then
			enemy:TrueStun(1.6)
		end

		caught = enemy
		break
	end

	if caught == nil or caught.HRootPart == nil then
		-- MISS: the whiff is parked mid-clip, so seek straight to it past the freeze frame and the jump prep.
		seek(anim, MARK.MISS_IN)
		restore()
		this:endLag(MARK.MISS_OUT - MARK.MISS_IN)
		-- MUST stop, or the clip runs on into the flash-step and plays a full slam at nobody.
		if anim then anim:Stop(0.15) end
		return
	end

	-- 0.70 -> 0.80, the freeze frame: the track holds itself, this only stops the VICTIM leaving. atkWait, since the punch has landed.
	local contact = caught.HRootPart.Position
	local unfreeze = pinTo(caught.HRootPart, function() return contact end,
		FREEZE_HOLD)

	this:atkWait(MARK.FREEZE_END - MARK.UPPERCUT)

	unfreeze()

	-- both of these, before anything tries to hold anyone. See killFloat.
	killFloat(caught)
	killFloat(humObj)

	fireVFX("camShake", hurtbox.Position, 200, 2, 0.1)

	-- !! the pillar LEANS along the launch: sending a bare position lands it on an identity rotation. Derived from LAUNCH so the two cannot drift.
	local fxAt  = hurtbox.Position + Vector3.new(0, 6, 0)
	local fxAim = forward * LAUNCH_UP - Vector3.new(0, LAUNCH_FWD, 0)
	fireVFX("smashUppercut", CFrame.lookAt(fxAt, fxAt + fxAim) * FX_ROLL)
	
	-- 0.80 -> 1.18, the first half of the prep: let the launch happen.
	if this:feintWait(APEX - MARK.FREEZE_END) then
		bail()
		return
	end

	-- hold them at the apex while you close; maxTime is the hang plus a margin, so a thrown error cannot strand the pin.
	local apex = caught.HRootPart.Position + forward * 4
	release = pinTo(caught.HRootPart, function() return apex end,
		{ maxTime = HOLD + 0.35 })

	-- the hang outlasts UCUT's ragdoll, so without this they STAND BACK UP mid-air while pinned; ragdoll() max()es, so this extends rather than restarts.
	caught.ragdoll:ragdoll(HOLD, false)

	-- TrueStun, not :Stun: only TrueStun passes bypassArmour, so under hyper armour the pin is otherwise free. Guarded, it is not in Combatant.
	if caught.TrueStun then
		caught:TrueStun(HOLD)
	end

	-- 1.18 -> 1.45, the rest of the prep.
	if this:feintWait(MARK.PREP_END - APEX) then
		bail()
		return
	end

	-- 1.45 -> 2.60: seek over the whiff, which sits in the middle of the clip.
	seek(anim, MARK.TELE_IN)
	fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	fireVFX("fstep", char, 0.4)
	-- hauls the CASTER up client-side for most of the window, so the last stretch is a real fall into the slam. NOT to `apex`, see CASTER_OVER.
	fireVFX("smashDown", humObj.HRootPart,
		apex + CASTER_OVER - forward * CASTER_BACK)

	-- 2.60 -> 3.28, up and back down. The slam lands on the last frame.
	if this:feintWait(MARK.SLAM - MARK.TELE_IN) then
		bail()
		return
	end

	if release then
		release()
		release = nil
	end

	if caught.isActive == true and caught.HRootPart then
		local eroot = caught.HRootPart
		fireVFX("camShake", eroot.Position, 400, 4, 0.2)

		forward = hurtbox.CFrame.LookVector
		local attack = this:makeAtk(SSMASH, caught, forward)
		attack.knockback = this:knockback(
			forward * 6 + Vector3.new(0, -36, 0), 0.25, false, -1)
		this:executeAttack(attack)

		-- again, and this is the one that matters: both fighters are airborne, so the float arms anti-gravity as we drive them down.
		killFloat(caught)
		killFloat(humObj)

		if attack:isHit() then
			-- flat 0.8s: stopOnGround would end it on the first frame, since they are driven INTO the ground.
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, Vector3.new(0, -10, 0))
			fireVFX("smashLand", eroot.Position)
			fireVFX("pauseF", char, eroot.Parent)
		end
	end

	restore()
	-- 3.28 -> 3.87, the landing. The clip ends by itself on the last frame.
	this:endLag(MARK.TRACK_END - MARK.SLAM)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
