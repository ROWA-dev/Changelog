--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any)
	this:stopLastAnim()
	this.lastAttacked = tick()

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox

	local anim = script.anim
	local track = this:PlayAnim(anim, 0, 1, 1.4)
	if track then
		track.Priority = Enum.AnimationPriority.Action2
	end
	
	if this.flourishHook and this:flourishHook() == true then return end

	this:indicateAtk()
	if this:feintWait(0.65) then return end

	local hitboxOffset = CFrame.new(0,0,-3.5)
	local hitboxSize   = Vector3.new(5,5,5)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local breakOut = false
	for i = 1,10 do
		if humObj and humObj:inStun() == true then
			breakOut = true
			break
		end
		hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemhum in pairs(hits) do
			local attack = this:makeAtk(
				dmgConfig.multiple,
				enemhum,
				hurtbox.CFrame.LookVector
			)
			attack.hitbox = hitbox
			task.spawn(function()
				this:executeAttack(attack)

				if attack:isParried() then
					breakOut = true
					this:stopLastAnim()
				end
			end)
		end
		task.wait(0.1)
		if breakOut then
			break
		end
	end
	
	task.wait(0.1)
	
	local hitLanded = false
	
	if breakOut == false and humObj:inStun() == false then
		hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemhum in pairs(hits) do
			local attack = this:makeAtk(
				dmgConfig.heavy,
				enemhum,
				hurtbox.CFrame.LookVector
			)
			attack.hitbox = hitbox
			local newkb = this:knockback(hurtbox.CFrame.LookVector*16, 0.3)
			attack.knockback = newkb

			this:executeAttack(attack)

			if attack:isParried() then
				this:stopLastAnim()
			elseif attack:isHit() then
				hitLanded = true
			end
		end
	elseif track then
		track:Stop()
	end

	this.m1last = tick() + 0.6
	if hitLanded == false then
		task.wait(0.2)
	end
	return hitLanded
end