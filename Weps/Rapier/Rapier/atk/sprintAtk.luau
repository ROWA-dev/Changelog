--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp&any): wepType.atkResult	
	local humObj = this._humObj
	local function indicator()
		humObj.limbTrails:indicatorLeft()
	end
	
	return this.basicAtks.sprint(
		this,
		script.sprintAtk, -- anim
		dmgConfig.m1, -- dmgtbl
		0.5, -- windup
		12, -- force
		0.4, -- force duration
		CFrame.new(0, 0, -4), -- hitboxoffset
		Vector3.new(5, 5, 5), -- hitbox sz
		indicator,
		-- anim stuff
		0.08, -- fadetime
		1,   -- weight
		1 -- speed
		-- endlag
	)
end