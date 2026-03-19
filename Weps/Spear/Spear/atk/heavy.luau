--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local hitboxClass = require(game.ServerStorage.ROWA.Class.HitboxClass)

local atkTypeEnums = require(game.ServerStorage.ROWA.Weps.Utils.atkTypeEnums)

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	this:triggerCD("heavy")
	this.m1cycle = 0
	local spearState = this.spearState
	if spearState == 1 then
		this.spearState = 2
		this._model.mtr.Enabled = false
		this._model.Hold.CanCollide = true
	else
		this.spearState = 1
		this._model.mtr.Enabled = true
		this._model.Hold.CanCollide = false
	end
	print("RAH heavy", this.spearState)
	return
end