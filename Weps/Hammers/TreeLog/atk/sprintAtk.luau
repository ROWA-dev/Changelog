--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp): wepType.atkResult	
	local humObj = this._humObj
	local function indicator()
		humObj.limbTrails:indicatorLeft()
	end
	
	local atkCB = function(atk:any)
		local lookVec = atk.myEntity.HRootPart.CFrame.LookVector
		atk.knockback = this:knockback(lookVec*24, 0.2)
	end


	return this.basicAtks.sprint(
		this,
		script.Thrust, -- anim
		dmgConfig.m1, -- dmgtbl
		0.9, -- windup
		10, -- force
		0.8, -- force duration
		CFrame.new(0, 0, -7), -- hitboxoffset
		Vector3.new(8, 5, 10), -- hitbox sz
		indicator,
		-- anim stuff
		0.08, -- fadetime
		1,   -- weight
		0.6, -- speed
		atkCB
	)
end