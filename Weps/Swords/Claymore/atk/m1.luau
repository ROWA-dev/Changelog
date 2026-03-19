--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

function flourish(this:wepBase.myself&any)
	-- reset m1 cycle if took too long
	this.lastAttacked = tick()

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox


	local anim = script.swing4
	local track = this:PlayAnim(anim,0,1,0.9)
	track.Priority = Enum.AnimationPriority.Action2

	this.m1cycle = (this.m1cycle+1)%4
	if this.m1cycle == 0 and this.flourishHook then
		if this:flourishHook() == true then return end
	end

	humObj.limbTrails:indicatorRightLeg()

	if this:feintWait(0.5) then return end

	local hitbox, hits = this:hitbox(
		CFrame.new(0, 0, -3), 
		Vector3.new(6.5,6.5,6.5)
	)

	local hitLanded = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.punch,
			enemhum,
			hurtbox.CFrame.LookVector
		)

		attack.hitbox = hitbox

		local enemyRoot:any = enemhum.RootPart

		local offset = enemyRoot.Position - hurtbox.Position
		local forward = hurtbox.CFrame.LookVector
		local signedDist = offset:Dot(forward)

		local newkb = this:knockback(forward*(16 + (4-signedDist)*0.8), 0.3)
		attack.knockback = newkb

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
	local humObj = this._humObj
	local function indicator()
		this:indicateAtk()
	end

	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 3 then 
		return flourish(this)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		4, -- m1CycleCount
		dmgConfig.m1,
		0.52, -- windup
		CFrame.new(0,0,-3), -- hitboxoffset
		Vector3.new(6,6,6), -- hitbox sz
		indicator,
		-- anim stuff
		0.1, -- fadetime
		1,   -- weight
		1    -- speed
	   -- 0.08  -- endlag
	)
end