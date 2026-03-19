--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself&any): wepBase.atkResult
	local humObj = this._humObj
	local function indicator()
		local m1cycle = this.m1cycle
		if m1cycle == 1 then
			humObj.limbTrails:indicatorRight()
		elseif m1cycle == 2 then
			humObj.limbTrails:indicatorLeft()
		elseif m1cycle == 3 then
			humObj.limbTrails:indicatorRight()
		elseif m1cycle == 4 then
			humObj.limbTrails:indicatorLeft()
		elseif m1cycle == 5 then
			humObj.limbTrails:indicatorRight()
		elseif m1cycle == 0 then
			humObj.limbTrails:indicatorRightLeg()
		end
	end

	return this.basicAtks.m1(
		this,
		script, -- animsParent
		6, -- m1CycleCount
		dmgConfig.m1,
		0.4, -- windup
		CFrame.new(0, 0, -2), -- hitboxoffset
		Vector3.new(5.5,6,5.5), -- hitbox sz
		indicator
	)
end