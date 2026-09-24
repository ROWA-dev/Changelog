--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local hitboxClass = require(game.ServerStorage.ROWA.Class.HitboxClass)
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local weighEnum = dmgUtils.weighEnum
local dmgFlag = dmgUtils.dmgFlags

return function(this:wepTyp): wepType.atkResult
	--[[if this:canTriggerCD("heavy") == false then return end
	this:indicateAtk()
	local humObj = this._humObj]]
end