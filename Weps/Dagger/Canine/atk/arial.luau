--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp&any): wepType.atkResult	
	local humObj = this._humObj
	local function indicator()
		humObj.limbTrails:indicatorRightLeg()
	end

	return this.basicAtks.arial(
		this,
		script.arial, -- anim
		dmgConfig.punch, -- dmgtbl
		0.5, -- windup
		10, -- force
		0.4, -- force duration
		CFrame.new(0, -2, -4), -- hitboxoffset
		Vector3.new(6, 6, 6), -- hitbox sz
		indicator
	)
end