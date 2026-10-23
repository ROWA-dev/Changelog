--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local WINDUP = 0.44 -- the anim's own hit time, so it plays at speed 1
local SLASH_CF, SLASH_SIZE = CFrame.Angles(0, math.rad(-115), 0), Vector3.new(20, 5, 20) -- BigSlash face up, clockwise
local BOX_CF, BOX_SIZE = CFrame.new(0, 0, -3), Vector3.new(7, 6, 7)
local ACTIVE = table.freeze({ window = 0.1 })

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox

	this:PlayAnim(script.heavy, 0.08, 1, 1)
	this:indicateAtk()
	fireVFX("hshock", humObj.HRootPart)

	if this:feintWait(WINDUP) then this:stopLastAnim(true) return end
	this:triggerCD("heavy")
	fireVFX("BigSlash", hurtbox.CFrame * SLASH_CF, hurtbox, SLASH_SIZE)
	--local step = this:bodyForce(Vector3.new(0,0,-4), 0.3, true, 0.3)

	local hitbox, hits = this:sweep(BOX_CF, BOX_SIZE, ACTIVE)
	if humObj:inStun() then --[[step:destroy()]] this:stopLastAnim(true) return end

	local look = hurtbox.CFrame.LookVector
	local hitLanded = false
	for _, enemy in hits do
		local attack = this:makeAtk(dmgConfig.heavy, enemy, look)
		attack.hitbox = hitbox
		attack.knockback = this:knockback(look * 4, 0.2)
		this:executeAttack(attack)
		if attack:isHit() then hitLanded = true end
		--elseif attack:isParried() then step:destroy() end
	end

	this:endLag(if hitLanded then 0.1 else 0.3)
	return hitLanded
end
