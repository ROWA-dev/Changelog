--!strict
--- Oblitar m1 - a 4 hit cycle, the last of which is the flourish. The flourish
--- uses `fsM2`, the shared punch, not oblM1, and carries the chain's only knockback.
--- !! WINDUPS ARE THE REAL WAITS, not `Attacking.Time` -- rowa1 lies in both
--- directions (S5 7g). m1's claim agrees at 0.5; the flourish's 0.45 does NOT,
--- and its real waits are also 0.5.
--- Both are BASE numbers: atkRate 1.05 is applied by scaledTime, so 0.5 lands on
--- rowa1's real 0.525. Do not pre-multiply or it is applied twice.
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

--[[ rowa1's audio telegraph, and it was missing entirely. The m1 plays
	Swing1 (pitched down to 0.7, started 0.2s in) plus afterswing at 0.3 into
	the 0.5 windup -- i.e. 0.2s BEFORE the hit. That cue is most of how the
	swing reads as heavy; with no sound at all the wind-up has nothing to
	announce it, which is the other half of "the windup is too fast".
	Scheduled rather than played up front so it keeps rowa1's offset, and
	guarded so a feint does not leave a swing sound with no swing. ]]
local function telegraph(this:wepBase.myself&any)
	local hold = this._model and this._model:FindFirstChild("Hold")
	if hold == nil then return end

	local sharp = this._model:FindFirstChild("sharp", true)
	if sharp and sharp:IsA("ParticleEmitter") then sharp:Emit(1) end

	task.delay(this:scaledTime(0.3), function()
		if this._humObj == nil or this._humObj:inStun() then return end
		local swing = hold:FindFirstChild("Swing1")
		if swing and swing:IsA("Sound") then
			swing.Pitch = 0.7
			swing.TimePosition = 0.2
			swing:Play()
		end
		local after = hold:FindFirstChild("afterswing")
		if after and after:IsA("Sound") then after:Play() end
	end)
end

local function flourish(this:wepBase.myself&any)
	-- reset m1 cycle if took too long
	this.lastAttacked = tick()

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox

	--[[ speed 1, which PlayAnim divides by atkRate to 0.952 -- rowa1's
		`AtkAnim:AdjustSpeed(1/AtkRate)` on the Flourish. This was 0.95
		before atkRate was wired up, which would now compound to 0.905. ]]
	local track = this:PlayAnim(script.swing4, 0, 1, 1)
	track.Priority = Enum.AnimationPriority.Action2

	this.m1cycle = (this.m1cycle+1)%4
	if this.m1cycle == 0 and this.flourishHook then
		if this:flourishHook() == true then return end
	end

	humObj.limbTrails:indicatorRightLeg()

	--[[ rowa1 plays arrowwoosh (from 0.2s in) at the START of the flourish,
		not partway through like the normal m1. ]]
	local hold = this._model and this._model:FindFirstChild("Hold")
	local woosh = hold and hold:FindFirstChild("arrowwoosh")
	if woosh and woosh:IsA("Sound") then
		woosh.TimePosition = 0.2
		woosh:Play()
	end
	local sharp = this._model and this._model:FindFirstChild("sharp", true)
	if sharp and sharp:IsA("ParticleEmitter") then sharp:Emit(1) end

	-- the REAL waits, 0.2 + 0.3. NOT the declared 0.45. See the header.
	if this:feintWait(0.42) then return end

	local hitbox, hits = this:hitbox(
		CFrame.new(0, 0, -3),
		Vector3.new(5, 5, 5.5)
	)

	local hitLanded = false
	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.punch,
			enemy,
			hurtbox.CFrame.LookVector
		)

		attack.hitbox = hitbox

		--[[ rowa1: Knockback(Hum, EnemyHum, LookVector*30) on the flourish
			only. S7 rule 9 -- a rowa1 knockback vector K is a rowa2 force of
			K * 0.6, so 30 -> 18. Sits right where Claymore's flourish lands
			(it computes 16 plus a distance term). ]]
		attack.knockback = this:knockback(hurtbox.CFrame.LookVector*18, 0.3)

		this:executeAttack(attack)

		if attack:isParried() then
			this:stopLastAnim()
		elseif attack:isHit() then
			hitLanded = true
		end
	end

	if this.m1cycle == 0 then -- flourish endlag
		this.m1last = tick() + 0.6
	end

	return hitLanded
end

return function(this:wepBase.myself&any): wepBase.atkResult
	local function indicator()
		this:indicateAtk()
		telegraph(this)
	end

	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 3 then
		return flourish(this)
	end

	return this.basicAtks.m1(
		this,
		script, -- animsParent, expects swing1..swing4
		4, -- m1CycleCount
		dmgConfig.m1,
		--[[ 0.6 BASE -> 0.63 after atkRate. rowa1's real windup was 0.5 base
			/ 0.525 scaled; this is a deliberate +0.1 on top of it, asked for
			in playtest because the axe should commit harder than the sword it
			was first modelled on. It is NOT a translation of a rowa1 number,
			so do not "correct" it back to 0.5 by reading Main. ]]
		0.52, -- windup BASE
		CFrame.new(0,0,-3.5), -- hitboxoffset
		Vector3.new(6,6.5,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1,   -- speed. atkRate divides this -> 0.952, rowa1's AdjustSpeed
		--[[ ENDLAG, and it was missing here too -- same latent bug Slayer
			shipped with. attackHelpers/m1 only sets `m1last`, the gate on
			the next m1, inside `elseif endlag then`; pass nil and the links
			have no cooldown between them at all. Executer passes 0.08.
			rowa1's equivalent is Oblitar's `lastatk = tick() + 0.2*AtkRate`,
			which is half Slayer's -- this is the faster axe of the two. ]]
		0.08 -- endlag
	)
end
