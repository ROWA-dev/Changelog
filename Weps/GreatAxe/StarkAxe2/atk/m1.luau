--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

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

	local track = this:PlayAnim(script.swing4, 0, 1, 1)
	track.Priority = Enum.AnimationPriority.Action2

	this.m1cycle = (this.m1cycle+1)%4
	if this.m1cycle == 0 and this.flourishHook then
		if this:flourishHook() == true then return end
	end

	humObj.limbTrails:indicatorLeftLeg()

	local hold = this._model and this._model:FindFirstChild("Hold")
	local woosh = hold and hold:FindFirstChild("arrowwoosh")
	if woosh and woosh:IsA("Sound") then
		woosh.TimePosition = 0.2
		woosh:Play()
	end
	local sharp = this._model and this._model:FindFirstChild("sharp", true)
	if sharp and sharp:IsA("ParticleEmitter") then sharp:Emit(1) end

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
		0.52, -- windup BASE
		CFrame.new(0,0,-3.5), -- hitboxoffset
		Vector3.new(6,6.5,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1,   -- speed. atkRate divides this -> 0.952, rowa1's AdjustSpeed
		0.08 -- endlag
	)
end
