--!strict
--- Slayer arial - rowa1's DOWNSLAM (Main `typ == 4 or 5`, Anims.Arial).
--- !! the declared windup lies again: Attacking.Time says 0.5, the real waits
--- are 0.3 + 0.3. Slayer lies in TWO of its four attacks (this and the heavy's
--- 1.4-vs-1.0), so do not trust that field anywhere in this weapon.
--- THE KNOCKBACK IS THE MOVE: (0,-20,0) drives the victim into the floor, which
--- is what makes it a slam rather than a jumping swing. It needs the atkCB hook,
--- which `arial` did not have -- added rather than dropping the knockback.
--- NOT PORTED: rowa1 dashes further on typ 4 than 5; rowa2 has one variant, so
--- this takes the typ 5 number.
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepTyp&any): wepType.atkResult
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox
	local hold = this._model and this._model:FindFirstChild("Hold")

	local function indicator()
		this:indicateAtk()
		local s = hold and hold:FindFirstChild("heavySwung")
		if s and s:IsA("Sound") then s:Play() end

		task.delay(this:scaledTime(0.3), function()
			if this._humObj == nil or this._humObj:inStun() then return end
			local sw = hold and hold:FindFirstChild("Swing1")
			if sw and sw:IsA("Sound") then
				sw.Pitch = 1.2
				sw:Play()
			end
		end)
	end

	--- rowa1 Knockback (0,-20,0) + look*2 -> S7 rule 9, K * 0.6.
	local function slamDown(attack)
		attack.knockback = this:knockback(
			Vector3.new(0, -12, 0) + hurtbox.CFrame.LookVector*1.2, 0.3)
	end

	return this.basicAtks.arial(
		this,
		script.arial, -- anim
		dmgConfig.downSlam, -- dmgtbl
		0.58, -- windup BASE (real waits 0.3 + 0.3, NOT the declared 0.5)
		12, -- force. rowa1 MiniDash 30 flat; rowa2 bodyForce decays.
		0.6, -- force duration
		CFrame.new(0, -2, -5), -- hitboxoffset
		--- +2 per axis over the rowa1 translation (was 7,7,7.5). See m1.
		Vector3.new(9, 9, 9.5), -- hitbox sz
		indicator,
		0.08, -- fadetime
		1,    -- weight
		1,    -- speed
		slamDown
	)
end
