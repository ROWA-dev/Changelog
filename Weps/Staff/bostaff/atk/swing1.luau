--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any)
	this:stopLastAnim()
	this.lastAttacked = tick()

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox

	local anim = script.anim
	local track = this:PlayAnim(anim, 0, 1, 1)
	if track then
		track.Priority = Enum.AnimationPriority.Action2
	end

	this:indicateAtk()
	if this:feintWait(0.5) then return end

	local hitboxOffset = CFrame.new(0,0,-4)
	local hitboxSize   = Vector3.new(6,6,6)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local hitLanded = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.m1,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		attack.hitbox = hitbox
		this:executeAttack(attack)

		if attack:isParried() then
			this:stopLastAnim()
		elseif attack:isHit() then
			hitLanded = true
		end
	end

	this.m1last = tick() + 0.05
	return hitLanded
end