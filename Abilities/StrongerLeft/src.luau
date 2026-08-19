--!strict
--[[ StrongerLeft - rowa1 Items/Ability/StrongerLeft.
	Notes: README.md/PORT_StrongerLeft.

	StrongLeft's big brother: longer charge, three expanding shockwave rings,
	a screen shake, terrain destruction, and the heaviest single hit in the
	non-ultimate set.

	STRUCTURALLY THIS IS StrongLeft.luau WITH DIFFERENT NUMBERS, on purpose --
	the Folder-of-numbered-emitters trick, the LeftGripAttachment lookup, the
	feintWait charge loop and the -1 decayT knockback are all decisions that
	were already made there and should not be re-litigated per ability. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StrongerLeft"
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
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--[[ rowa1 "strP2": Heavy, blunt, 50 dmg, truestun 1.4 / stun 1.6, posMult 6.
	Scaled by the same ~0.65 the shipped ports used, so it keeps its ratio to
	StrongLeft (20).

	!! posMult 6 is joint-highest in rowa1's whole table and was tuned against
	a 100 posture pool; rowa2's maxPosture is 80, so 6 would guard-break in
	two connects from full. Pulled to 4 -- still the hardest guard pressure of
	any non-ultimate, but not a two-hit break.

	!! rowa1 set NO parryH here, making the 50-damage version EASIER to parry
	than StrongLeft's -0.04. That is an omission, not a design: matched to
	StrongLeft. ]]
local STR_P2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 33,
	stun     = 1.6,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack, _source)
		local eroot = attack.enemyEntity.HRootPart
		fireVFX("strpunch", eroot)
		hitSfx(eroot, "HardPunchHit", "GoreyHit")
	end,
}

local function useFunc(this:myself)
	local cooldownID = "strongerLeft"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent

	--[[ nil-degrade the arm lookup. StrongLeft chains
		FindFirstChild("Left Arm"):FindFirstChild(...) and throws on any rig
		without one -- and because use() pcalls, that silently eats the whole
		ability. Worth fixing there too. ]]
	local leftArm = char:FindFirstChild("Left Arm")
	local grip = leftArm and leftArm:FindFirstChild("LeftGripAttachment")

	local anim = this:PlayAnim(script.Punch, 0, 1, 0.8)

	local startSnd = script.start:Clone()
	startSnd.Parent = hurtbox
	startSnd:Play()
	game.Debris:AddItem(startSnd, 4)

	local sparks, circle
	if grip then
		sparks = script.handsparks:Clone()
		sparks.Parent = grip
		game.Debris:AddItem(sparks, 4)

		circle = script.circle:Clone()
		circle.Parent = grip
		game.Debris:AddItem(circle, 4)
	end

	--[[ rowa1 charged for 15 iterations of Rwait(0.05): Emit(8) sparks each
		one, and a ring every second one. 15 emits total, ~120 particles.

		!! THE CALLBACK RUNS EVERY FRAME, NOT EVERY 0.05s. Emitting straight
		out of it ran at ~60Hz instead of 20Hz -- three times the particles
		rowa1 produced, which is why the windup looked like a firework. The
		accumulator restores rowa1's cadence and makes the emit rate
		independent of framerate. ]]
	local sinceEmit, ticks = 0, 0
	local feinted = this:feintWait(0.8, function(dt: number)
		sinceEmit += dt
		if sinceEmit < 0.05 then return end
		sinceEmit -= 0.05
		ticks += 1
		if sparks then sparks:Emit(8) end
		if circle and ticks % 2 == 0 then circle:Emit(1) end
	end)

	if feinted then
		if anim then anim:Stop() end
		game.Debris:AddItem(startSnd, 0)
		if sparks then game.Debris:AddItem(sparks, 0) end
		if circle then game.Debris:AddItem(circle, 0) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 9, true)
	-- rowa1 MiniDash power 40; bodyForce scales by 5 internally, so 40/5 = 8.
	this:bodyForce(Vector3.new(0, 0, -8), 0.2, true)

	if anim then anim:AdjustSpeed(1.1) end

	local loud = script.lowLoud:Clone()
	loud.Parent = hurtbox
	loud:Play()
	game.Debris:AddItem(loud, 4)

	local forward = hurtbox.CFrame.LookVector
	local origin  = hurtbox.Position

	--[[ the slam body and the three rings are ONE client effect now.
		rowa1 cloned a server Part into workspace.Effects and relied on a
		global `Effects.ChildAdded` listener in FxHandler to notice the name
		and animate it. rowa2 has no such listener and should not grow one --
		see VFXQuiver/strongerSlam for the full argument. ]]
	fireVFX("strongerSlam", hurtbox)

	-- rowa1 Destruction:BigBreak2, CUTTER_SIZE 16^3 -> Sphere r 8.
	--[[ rowa1 BigBreak2 cut with a 16^3 CUBE. rowa2 has a real sphere, so
		this is r8 (the inscribed sphere of that cube -- the circumscribed one
		would carve ~40% wider than the original). ]]
	Destruction.Sphere(nil, origin + Vector3.new(0, 8, 0) + forward * 9, 8, 4.8, forward)

	--- rowa1 fired its own CamShake RemoteEvent with exactly these args;
	--- rowa2's camShake quiver id takes the same (pos, range, intensity, dur).
	fireVFX("camShake", origin, 400, 2, 0.3)

	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(7, 7, 7))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(STR_P2, enemy, forward)
		--[[ rowa1 look*50 + (0,8,0). Its Knockback set Velocity = knock*3;
			rowa2's scales by 5. So a rowa1 vector K converts at K * 0.6 --
			which is exactly what shipped StrongLeft did (rowa1 16 -> 9). ]]
		attack.knockback = this:knockback(
			attack.atkDir * 30 + Vector3.new(0, 5, 0), 0.15, false, -1)

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 12)
		end
	end

	-- the trailing hand smoke outlives the move, exactly as in rowa1.
	if grip then
		local smoke = script.smoke:Clone()
		smoke.Parent = grip
		game.Debris:AddItem(smoke, 4)
		task.spawn(function()
			for _ = 1, 16 do
				if smoke.Parent == nil then return end
				smoke:Emit(1)
				task.wait(0.08)
			end
		end)
	end

	humObj.canAtkThreshold = tick() + 0.3
	this:endLag(0.15)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
