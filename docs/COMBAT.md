# COMBAT - how a pro fight plays, and every number that shapes it
(index: parent ServerStorage/README.md)

Assumes BOTH players are skilled: they know the matchup and take the
correct defensive option whenever one exists. Skill decides WHICH option
you take; latency decides whether it was available at all (4.16).

Covers the FIGHT, not the code. API and authoring live in WEAPONS /
ABILITIES / GOTCHAS. No per weapon damage tables, they rot within
a patch. Every number here is a FEEL number; changing one is a balance
call. Harness: require(game.ServerScriptService.Tests.CombatTests.Harness).run()

## 1. THE SHAPE OF A FIGHT
Two health bars, two posture bars, one mana bar each.

Attack, and you commit to a windup you can cancel (feint) at a price.
Defend, and you pick one of three answers, checked in that order: parry,
dodge, block.

Health regen 0.5/s and posture 2/s are both too slow to matter inside a
fight, so treat them as budgets, not resources. Mana only comes from
hitting people. Standing off regenerates nothing you care about.

Weapons come in three weight classes. Heavy hits hardest, swings slowest,
and is the only class with a rule attached to the class itself (5.6).
Light swings fastest and wins the parry punish. Medium is in between and
is currently missing one of its defensive perks (9).

## 2. THE ATTACK BUTTON IS FIVE MOVES
What your attack becomes is read fresh every frame off your movement
state:
    airborne (jumped within 0.1s)   aerial
    slide key held                  uppercut
    sprinting                       sprint attack
    otherwise                       m1

Attack inputs REPEAT while held. You do not tap out a combo, you hold and
the gates decide your rhythm.

M1 STRINGS. Each weapon cycles 3 to 5 swings. The last is the FLOURISH:
bigger knockback, and the closer you are the harder it hits (force scales
as 16 + (4 - distance) * 0.8). Flourish costs 0.6s of endlag instead of
the usual 0.1 or less.

The string RESETS if you pause longer than about twice your swing time,
so backing off loses your finisher. Re-entering starts you at swing 1.

## 3. THE THREE ANSWERS
Checked in this order, first match wins: PARRY, DODGE, BLOCK, else HIT.

PARRY. 0.2s from raising guard, -0.08 in stun, -0.06 from behind, plus
the attack's parryH. Cooldown 1.2s, RESET on success, so parry CHAINS;
miss one and you wait 1.2s, and that gap is the whole risk. Block still
works for 0.2s after the window closes. Landing one stuns the attacker
(0.3s heavy, 0.4s otherwise), locks their attack 0.4-0.5s, wipes your own
stun and lockout, unragdolls you, and trades posture. What the window is
worth against human latency is 4.16.

DODGE. 0.3s of i-frames granted by dashing, not a separate button, cut to
0.16s after a dashcancel. Dashing cancels a pending parry, so you cannot
hold both options. Gated 0.1s after stun ends (0.3s if you attacked in
the last second), 0.1s after your last dash, 0.1s after a feint. Cooldown
1.5s, RESET every time you land a hit.

BLOCK. Costs posture equal to damage * posMult, plus force^0.8 if the hit
carries knockback. From behind it fails. Hit 0 posture and you
GUARD BREAK: 1.6s true stun, 1.9s stun, and the breaking attack still
lands. Roughly two seconds of being a target.

3.1 DASHING DISABLES GUARD FOR 0.3s
Parry is not a button, it is the first 0.2s of BLOCK, so anything gating
block gates parry with it. Dashing gates block for 0.3s.

So a dash costs you BOTH defensive answers for 0.3s, and it outlasts the
0.3s of i-frames it bought: dodge covers exactly the window in which you
have nothing else. Dash COMMITS you to the i-frames as your whole defence
for that beat. This decides 5.9.

Separate from the OTHER dash rule, that dashing wipes a parry already
raised. One kills the current window, this one blocks the next press.
Both fire on the same dash.

The gate QUEUES rather than rejects: guard pressed during the 0.3s fires
when it expires. But the parry branch re-checks its conditions on waking,
so a press queued as a parry commonly arrives as a plain block, with no
feedback that it downgraded. Mashing guard out of a dash gets the block.

## 4. THE HIDDEN RULES
Each is two numbers meeting.

4.1 PARRYING A COMMITTED HEAVY GUTS THEIR GUARD
The parry posture trade is asymmetric on purpose: parrier gains
transfer/2, attacker loses transfer/1.5, both clamped 0 to 80. Transfer
is the attack's posture damage (damage * posMult) minus the weapon's
postureGain.

Committed heavies run posMult 3 to 10 and the heaviest attacks clear 400
posture, so the loss is routinely most of an 80 bar. Zeroing it outright
needs transfer >= 120. A 36 damage heavy at posMult 3 is 108 posture,
minus heavy class gain 16, so the attacker loses 61 and sits at 19: one
chip hit from a break.

That is the real answer to heavy weapons, and why parry chains matter:
parry the heavy, then any light poke ends the fight.

4.2 THE PARRY REWARD IS USUALLY WASTED
Same clamp, other side. You parry at near full posture, so your gain does
nothing. A punish, not a heal. It only matters when you parry late in a
long block string.

4.3 postureGain IS DAMAGE CONTROL FOR BEING PARRIED
Subtracted from the transfer, so it softens your punishment for being
parried. Heavy class 16, greatswords 8, some individual weapons 4,
light 0. Medium is commented out, so mediums fall through to 0 and eat
parry punishment exactly as hard as lights while swinging the biggest
heavies in the game (9).

4.4 MANA IS NOT A REGENERATING RESOURCE
Regen is 4 * (1 - fill)^3, which collapses as it fills: 0 to 10 takes 3s,
0 to 25 takes 10s, 0 to 50 takes 38s. Abilities cost 10, and hitting
people pays damage/4, so roughly 4 light hits per ability or one heavy.

Abilities are earned by landing weapon hits, not by waiting. Banked mana
earns nothing: sitting full wastes the fast part of the curve. Passive
play locks you out of your own kit.

4.5 LANDING A HIT MAKES YOU FASTER AND REFILLS YOUR DASH
Every landed or BLOCKED hit gives walkspeed +5+stun*2 for 0.8+stun*2
seconds, and resets both dash cooldowns, so you can dash freely after
every hit that connects. Aggression funds itself, which is why a fight
that starts going one way accelerates. Blocking still feeds the attacker,
so blocking is not a way to slow someone down.

4.6 WHIFFING IS THE ONLY THING THAT SLOWS YOU
A swing that hits nothing makes your NEXT swing 0.1 slower for 0.4s.
Combined with 4.5, spacing is the entire skill floor: hit and speed up,
miss and bog down. Abilities are exempt.

4.7 FEINTING EARLY COSTS MORE THAN FEINTING LATE
Cancel lockout is 0.4s minus how long you held it, floored around 0.1s:
    feint immediately     0.40s lockout
    feint at 0.2s         0.20s lockout
    feint at 0.3s or more 0.10s lockout
Twitch cancelling is punished, committing then reading is not. Weapon
feints also cost a 0.15 attack rate penalty for 0.2s and block dashing
for 0.1s. Ability feints cost neither, so abilities are the cheap bait.
What this costs you in the actual mixup is 5.7.

Feints under 0.18s do not show the feint effect, so the fastest cancel is
invisible to your opponent and costs you the most.

4.8 FLANKING BEATS BLOCK COMPLETELY, PARRY BARELY
Block from behind fails outright. Parry from behind only loses 0.06s.
So circling a turtling opponent wins, but circling someone actively
parrying does almost nothing.

4.9 STUN MAKES RETREATING WORSE THAN ADVANCING
Backpedalling costs 3 walkspeed normally, 6 for two seconds after being
stunned. Movement returns smoothly over the last part of a stun rather
than snapping, so the recovery is readable.

4.10 NEITHER FIGHTER GETS TO WATCH THE OTHER BE STUNNED
If a trade stuns BOTH, both stuns are cut to 0.1s so the fight restarts
immediately. Neither side is rewarded for the coin flip, which makes
trading the cheapest escape at low posture: it costs health, not guard.
The exception is 4.15.

4.11 AIR COMBOS ARE DELIBERATELY GENEROUS
Both fighters float, each pulled toward the other. Weapon hitboxes grow
by 1.5 in every direction while airborne. Every landed hit re-extends
the float by 0.2 + stun. Uppercut also makes you immune to aerials during
your own launcher, so you cannot be knocked out of your own combo.
Abilities do NOT get the bigger hitbox.

4.12 GUARD IS A TIMER WHOSE LENGTH IS SET BY THE ATTACKER
80 posture, 2/s regen. Posture damage per hit runs from about 2 (fast
multi hit strings) to 500 (the heaviest heavy), so a guard bar is roughly
12 blocked hits against fast lights, 6 to 8 against normal m1s, 2 to 4
against heavy m1s and 1 or 2 against committed heavies. Blocking buys
time against fast weapons and nothing at all against slow ones. That is
why both exist.

4.13 KNOCKBACK IS SECRETLY POSTURE DAMAGE
Any attack carrying knockback adds force^0.8 posture on top. Authored
force is multiplied by 5 internally, so modest looking numbers are large:
an authored 6 is +15 posture, an authored 20 is +40. The m1 flourish
carries knockback, so combo enders pressure guard far harder than their
damage suggests: at authored 16 to 19 it is 33 to 38 posture from the
knockback alone, before any damage.

4.14 HARD KNOCKBACK TURNS WALLS INTO A SECOND ATTACK
Above 60 real force the victim is tracked for up to 4s. Hitting geometry
destroys it and fires a free follow up (damage scaled to impact size,
0.6 stun, posMult 4, hard to parry) plus a ragdoll. The m1 flourish
clears 60 at any range, so every string ender is a free wall check.
Fighting near walls is a real risk and knockback abilities are map
dependent.

4.15 SLOW WEAPONS BUY THE RIGHT TO FINISH THE SWING
Any m1 with a windup over 0.55s gets hyper armour for
(windup - 0.55) * 3.5, capped at 0.5s. Today only the slowest families
qualify at all, and the very slowest is capped.

Armour stops the STUN and the interrupt only. Damage, knockback, posture
damage, ragdoll and grabs all still land, and being parried still locks
your attack. But 4.10 only caps both stuns when BOTH land, so armouring
through a trade turns a mutual 0.1s reset into a one sided full stun:
a tempo swing, not a damage race.

TRUE STUN PIERCES IT. Guard break, the counter ability and the grab
heavies are the intended answers to someone walking through your pokes.

4.16 PARRY DIFFICULTY IS WINDUP, NOT parryH
parryH is added to the defender's window, negative meaning harder. Fast
multi hit finishers run as high as +0.3, committed heavies -0.1. The
intent was that fast strings would be unbeatable otherwise.

What the numbers produce is different, because a parry must be STARTED
before the hit lands, and starting costs human latency: roughly 0.25s to
see and press, plus ping. Guard raised at t covers [t, t+window] and the
hit lands at the windup, so valid presses are [windup - window, windup].
Latency deletes everything below 0.25 + ping:

    slice = min(window, windup - 0.25 - ping)

REACTING NEEDS WINDUP, NOT WINDOW. At 0.25 latency and 0.08 ping a 0.36
windup leaves almost nothing while a 0.82 leaves the whole window and
slack. A WIDER WINDOW ONLY PAYS PREDICTION: window extends the EARLIEST
press, and latency already removed the early end.

So fast weapons are parried by PREDICTION and heavy weapons by REACTION,
and parryH only forgives the guess. Fast finishers at +0.3 are not
"readable", they are guessable with a wide margin; heavies at -0.1 are
reactable with no slack. In stun it is prediction only.

This also makes the 0.18s feint visibility floor (5.8) redundant, and
makes PingCompensation and HeavensEqualizer (8.9) latency subsidies
rather than balance knobs.

4.17 YOU DO NOT DIE, YOU GET KNOCKED DOWN
A hit that would leave you at 5 health or less does not kill. You clamp to
1 and hit the floor, pinned in a ragdoll, and everything is off until you
get up: no attacking, no blocking, parrying or dodging, and no movement
tech either -- dash, dash cancel, slide, crouch and sprint all refuse.
Finishing you off is a second job: while down you have a separate 40 point
pool, so chip damage counts but one more poke is not enough.
You get up when health regen carries you back over 5, eight seconds at the
default rate. So a knockdown is a tempo loss and a free window for
everyone else, not a death.
THE EXCEPTION: the decapitation heavies (Katana, Executer, Oblitar, Axe)
ignore the pool entirely and kill outright. Being down in front of one of
those is death, which is the point of carrying one.
You also stay execute-able until health passes 10, so the moment you stand
up is still the most dangerous one.
Mechanism and the reasons it is where it is: CLASSES 3.5.

## 5. READS AND PUNISHES
What one player can infer about another. Most of the mindgame is
reading habits, not reading state: there is no stamina bar to watch and
no cooldown UI on the opponent.

TRUE STUN ALSO TAKES YOUR FACING. Under shiftlock the ENGINE turns you to
face the camera (UserGameSettings.RotationType = CameraRelative, set by
BaseCamera:UpdateMouseBehavior), so a stunlocked player could still re-aim
for free. ClientClass calls shiftLock.freezeCharacter("trueStun", ...) off
trueStun.Changed, which holds RotationType at MovementRelative for the
duration. The lock itself stays ON -- only the steering stops.

This needed a WIRE CHANGE to work at all: client `trueStun` was
permanently 0, so nothing client-side could tell a guard break from a jab.
See GOTCHAS, "CLIENT trueStun USED TO BE PERMANENTLY 0" -- it also
woke up CharController's hard movement zero, which is a real feel change
on every true stun in this file (guard break, the three grabs, Freeze).

5.1 THE BACKDASH TELL
The only place the game leaks a cooldown through the animation, and the
one read available on sight rather than by habit.

A backdash plays one of two animations. With dashcancel available you get
the short one. Without it you get a different animation, the dash takes
1.0s instead of 0.4s, and dashcancel goes on a 2s cooldown. So a long,
committed looking backdash means their escape is spent and they are slow
for a full second. Every backdash is also 10 power shorter than other
dashes, so it covers less ground than it looks like it should.

5.2 PARRY PUNISH DEPENDS ON YOUR WEAPON SPEED
A parry stuns the attacker 0.4s (0.3s heavy) and locks their attack
0.5s (0.4s heavy). Your swing lands at its windup, so whether you get a
free hit is decided by your windup:

    windup 0.36 to 0.40   lands inside the stun, guaranteed hit
    windup 0.44 and up    they recover first

So light weapons get a guaranteed hit off a parry. Heavy weapons get
position and a posture win, not damage. Parrying with a slow weapon and
then winding up a swing loses the exchange. The real heavy reward is 4.1:
their guard is at zero, so the follow up needs to be blockable into a
break, not fast.

5.3 GUARD BREAK IS THE ONLY GUARANTEED COMBO
1.6s of true stun, during which they cannot block, parry or dodge, plus
0.3s of ordinary stun after: 3 swings for a fast weapon, 2 for a medium,
1 for the slowest. Spending it on an uppercut instead buys more, since
4.11 re-extends the float on every hit and outlives the stun.

The largest reward in the game, and why posture pressure is worth playing
for even when your damage is bad.

5.4 WHIFFS ARE READABLE AND PUNISHABLE
A missed swing slows the next one by 0.1 for 0.4s, so a whiffing opponent
is slower for their recovery AND their follow up. Against a whiffed heavy
that is often a free parry, and by 4.16 the extra 0.1 of windup is real
reaction time rather than a wider guess.

5.5 PANIC OPTIONS
Dashing while attacking, and dashing out of a block, both burn dashcancel
for nothing. Skilled players do neither, so this only surfaces as the 5.1
tell after a scramble.

5.6 BLOCKING A HEAVY IS NOT SAFE
Heavy class weapons stun the BLOCKER 0.1s and add 0.1s of attack lockout
on a successful block. The only rule attached to a weight class rather
than to a specific attack. Holding guard against a heavy means you never
get your turn back by blocking alone. You have to parry, dodge or move.

5.7 THE FEINT TRIANGLE
The real mixup at any windup. Three options, each beats exactly one:

    feint     beats parry    their window burns, then 1.2s of cooldown
    commit    beats feint    they swing through your cancel and hit you
    parry     beats commit   4.1: not a hit, a gutted guard

The payoffs are NOT symmetric. Eating a hit during a feint costs one hit.
Being parried costs stun, 0.4-0.5 lockout, most of a guard bar, and a
break on the next blocked hit. Commit is the only option with unbounded
downside, which is why holding the attack button feels strong: it never
loses more than tempo.

How much that costs depends on YOUR weapon, because the loss is
transfer/1.5 (4.1). A light m1 parried is about 5 posture; a heavy is 60
to 80. So lights can commit and only heavies need the feint, which is why
the heavy's two stage windup is built to cancel late.

LATENCY MAKES THE FEINT BEAT PARRY OUTRIGHT. A press landing at t was
committed at t - 0.25 (4.16), so a feint thrown after their commitment
point cannot be answered. Feint LATE: cheapest (4.7) and most reliable.

It also does not decay the way bait options usually do, because against a
skilled defender the parry is CORRECT PLAY, not a habit. If your windup
clears the latency floor they can react, and a defender who can react
will parry: it is the only answer that stops the hit and takes their turn
back (3). Dropping the option means eating every reactable attack you
own, so the feint has a guaranteed customer.

So the trigger is not your weapon but one question per attack: WILL THIS
SWING BE PARRIED. Windup answers it (4.16). Feint the attacks that clear
the reaction floor, commit the ones that do not. Weight class matters
only because it tracks windup.

Never a speed option. A weapon feint costs its lockout PLUS 0.15 rate for
0.2s, about 0.69s to the next hit in the cheapest light case, slower than
an uninterrupted string. Ability feints skip both penalties (8.8).

The free answer to a held attack button is the string itself: it arrives
at the flourish on a fixed schedule, and 4.16 makes that finisher the
most parryable hit in the game while 4.13 makes it the one carrying the
largest posture transfer. Blocking into a finisher parry is a timer, not
a read.

5.8 WHAT YOU CANNOT READ
Hyper armour is invisible by default: it flashes only when it eats a hit,
so "did that swing have armour" is answered after the fact. Posture and
mana are not shown on the opponent. A feint under 0.18s shows no effect,
though per 4.16 that floor is redundant against a reacting player.

5.9 WHAT A BURNED PARRY BUYS
The feint's value is not the cancel, it is the 1.2s after it. Parry
cooldown is 1.2s and only RESETS on success (3), so a baited parry is a
full 1.2s with the defender's best option gone. Both remaining answers
are worse than the parry they spent.

DASH AWAY. 0.3s of i-frames and real distance, but committal. Dash cd is
1.5s, LONGER than the 1.2s parry it replaced, so they downgrade their own
rotation to answer a 0.4s cancel. A dash also locks out GUARD ENTIRELY
for 0.3s (3.1), so for those 0.3s they have no parry AND no block, only
the i-frames. Land after the i-frames expire and there is no defence left
to beat. Backdash leaks the 5.1 tell. Whiffing into their dash costs you
tempo only, and landing anything resets YOUR dash (4.5), so you keep
initiative on both branches.

BLOCK. The safe answer, and what skilled players default to: it cannot
whiff and it cannot be baited twice. It is also why the loop ends in
posture, not damage. You stop trying to hit them and start spending their
80 (4.12). Against real posMult that is 1 to 4 blocked hits, and a
blocked heavy still stuns the blocker (5.6). Guard break closes it (5.3).

So the move is not the cancel: the feint CONVERTS a parry mixup into a
posture race, and the posture race favours the attacker. The rate limit
is what stops it being the whole game: feint cd 2s (8.2) against a 1.2s
parry, so you choose which swing carries it.

## 6. THE MOVE ARCHETYPES
Every weapon draws from the same six moves. Damage numbers live in each
weapon's dmgConfig.

M1
    The string. 3 to 5 swings, last one is the flourish.
    Windups run 0.44 to 0.90, and that single number also decides hyper
    armour (8.6) and how long you can pause before the string resets.

HEAVY
    Usually the most bespoke move on any given weapon.
    Two stage windup, 0.53 then 0.13, so it can be feinted late.
    Roots you completely while charging (walkspeed -100).
    Scans the ground ahead for 0.3s looking for something to smash.
    Connecting early is rewarded: a delta from 0.2 to 1.0 multiplies the
    knockback, and connecting late downgrades the hit to an m1.
    Endlag 0.4 on whiff, 0.2 on hit. Weapon set cooldown, usually 6s.

UPPERCUT (slide key plus attack)
    The launcher and the entry to the air game. 0.5s windup, 2s cooldown.
    Moves you forward 6, or 10 if you dashed within the last 0.4s, so it
    doubles as a gap closer out of a dash.
    Aerial immune for its duration: you cannot be knocked out of your own
    launcher. Tries the hitbox 3 times 0.04s apart, so it is forgiving.
    Endlag 0.3 on whiff, none on hit.

AERIAL (attack while airborne)
    0.5s windup, 1s cooldown, pushes you forward 10 for 0.4s.
    Shrinks your own hurtbox by 0.5 during the windup, the only move that
    evades as it attacks. Blocked until 0.2s after stun ends.
    Retries the hitbox once after 0.05s. Endlag 0.3 whiff, 0.05 hit.

SPRINT ATTACK
    0.52s windup, 1s cooldown, pushes you forward 12 for 0.4s.
    Blocked until 0.3s after stun ends, the strictest of the three.
    Same retry and endlag as aerial. No hurtbox shrink, so it is the
    committed version of the same idea: more range, no evasion.

DOWNSLAM (flourish while airborne)
    The air combo ender. 0.5s windup, 2s cooldown. Drives the victim down
    and away, then ragdolls. Replaces the flourish automatically.

SHARED GATE
    Aerial, sprint and uppercut all refuse if you are within 0.1s of
    your last attack landing, unless you are mid flourish. That is what
    stops you cancelling a string into a movement special.

## 7. THE MOVEMENT LAYER
Your attack type is chosen by your movement state, and dashing IS your
dodge.

7.1 SPEED IS A STACK OF MODIFIERS
Base 13. Everything adds or subtracts, and several stack at once:
    sprint      ramps up to +14 over time, not instant
    slide       up to +28, decays with terrain
    landing hit +5 or more for about a second
    parry card  +5 for 1s
    blocking    -6            attacking    -2
    backpedal   -3, doubled to -6 for 2s after being stunned
    crouch      -7            swimming     -4
    shock       -6            rooted moves -100
    true stun   0

7.2 SPRINT IS A COMMITMENT
Sprint ramps rather than toggling, so it is slow to reach top speed and
instantly lost. It drops the moment you turn away from your movement
direction, and is cancelled by attacking, blocking, sliding or being
stunned. You cannot sprint defensively.

7.3 SLIDE IS TERRAIN DEPENDENT
Entry costs 1.5 studs of height and a burst of 1.6x slide speed. Downhill
ACCELERATES you, uphill kills the slide. Cooldown 2s. Jumping out of a
slide converts the speed into a leap, so slide jumping is a real
traversal option. Standing still turns the slide key into a crouch.

7.4 PARKOUR
Vault, climb and wallslide hang off the jump input. Vault reach 5,
sprinting vaults harder, closer obstacles throw you higher. Climb is 2
per airtime, refunded on landing, ladders free. Both 0.4s cooldown.
Wallslide is automatic and bleeds horizontal speed. They are the only
ways to gain height without jumping, and height feeds aerials.

7.5 SWIMMING DISABLES THE AIR GAME
Below the water plane you swim: speed -4, and the air combo handoff
refuses to start.

7.6 DASH IS THE CENTRE OF EVERYTHING
Power 50, lasts 0.4s, cooldown 1.5s but RESET on every landed hit.
    backward                power -10, and see 5.1 for the tell
    airborne                shorter (0.2s) but stronger (+10), and costs
                            0.4s extra cooldown plus your dashcancel
    no dashcancel left      dash cooldown +0.7
Dashcancel is a second, shorter dash (power 30) usable within 1s of
dashing, which resets your dash outright. The two together are the
mobility economy, and 5.5 is how you lose it.

## 8. NUMBER REFERENCE
8.1 BODY
    health 0.5/s (1s ticks)     posture 80, regen 2/s
    mana 0/100, 4*(1-fill)^3    walkspeed 13, sprint 14, slide 28
    dash power 50               jump power 36
    parry window 0.2            dodge window 0.3
    water plane Y -2.5          weapon slots 2, oldest dropped
    human latency ~0.25s + ping, see 4.16

8.2 GATES AND LOCKOUTS
    parry cd 1.2, reset on success     feint cd 2
    dash cd 1.5, reset on landed hit   dashcancel 1.5, slide 2
    vault cd 0.4, climb cd 0.4, climbs per airtime 2
    block raises attack lockout 0.4    parried: attacker locked 0.4-0.5
    ability parried: attacker locked 0.2
    dash blocked 0.1s post stun, 0.3s if you attacked within 1s
    dash blocked 0.1s after a feint and 0.1s after the last dash
    block AND parry blocked 0.3s after a dash (3.1), input queues
    dash also zeroes any parry window already raised
    aerial blocked until 0.2s past stun, sprint until 0.3s, both cd 1s
    movement specials blocked within 0.1s of your last hit landing

8.3 PENALTIES
    whiff              next swing 0.1 slower for 0.4s
    weapon feint       0.15 slower for 0.2s, no dash 0.1s
    early feint        up to 0.4s lockout, less the longer you hold
    parry in stun      -0.08 window        from behind -0.06
    heavy blocked      blocker stunned 0.1 and locked 0.1

8.4 REWARDS
    landed or blocked hit  +5+stun*2 speed for 0.8+stun*2s, dashes reset
    weapon hit             mana +damage/4
    parry                  stun and lockout wiped, unragdoll, posture trade
    guard break            1.6s true stun, 1.9s stun, breaking hit lands

8.5 DAMAGE TABLE SHAPE
Every attack is weight, damage, stun, posMult, plus optional parryH,
dodgeH and stunMeOnParried. Ranges currently in use:
    damage    2 to 50         stun    0.2 to 1.0
    posMult   0.7 to 30       parryH  -0.1 to +0.3
    weight    Heavy, Medium, Light. Heavy is the only one with a class
              wide side effect (5.6).
posMult is the guard pressure knob and has the widest range in the game;
high posMult with low damage is the shield breaker shape. parryH negative
means harder. stunMeOnParried 0 means the move is safe on parry.
dodgeH negative means harder to dodge, and it is LIVE as of the isDodge
fix -- it was inert for its whole life. Authored range -10 to +0.15:
    weapons          -0.1     Rapier x3, Claymore, magicStaff, Spear
    Fulminate        -0.2
    lock-on / AoE    +0.1 to +0.15   Zoltraak, Lightning, Tendrils, RPG
    HollowPurple     -10      not a difficulty, a STATEMENT: i-frames do
                              not answer this. rowa1's `bypassiframes`.
Against a 0.3 dodge window, -0.1 is a third of it and +0.15 is half again,
so these are not small. They took effect all at once; if dodging suddenly
feels different, this is why.

posMult IS NOT OPTIONAL. CalculatePostureDmg defaults it to 1 now, but it
used to read `dmg * posMult` raw -- and since that is the first line of
HandleAttack, a nil posMult threw into AbilityBase.use's pcall, which only
warns. The ability then plays in full and damages nobody. Lightning
shipped that way. See the port bible S4.2.

8.6 HYPER ARMOUR
    cutoff 0.55, scale 3.5, cap 0.5, applied to m1 windups only.
    grant = min((windup - 0.55) * 3.5, 0.5)
    All three constants interact: raising the cutoff SHRINKS every grant
    above it. Never move one alone, print the whole table after.

8.7 KNOCKBACK
    authored force is multiplied by 5 internally
    adds force^0.8 posture damage on top of the hit
    above 60 real force, walls are hunted for 4s and produce a free
    follow up plus a ragdoll
    weapons scale knockback by character size, abilities do not

8.8 ABILITIES
    all cost 10 mana, though most never spend it.
    cooldowns run 6 to 20s.
    abilities skip the whiff penalty and never grow hitboxes in the air.
    ability feints are cheaper than weapon feints by design.

8.9 CARDS AND STATUS
    Underdog          -15% damage taken when below the attacker's health
                      (the card text says 20%, see 9)
    SpeedOnParry      +5 speed for 1s on parry
    Counterweight     +25% on the parrier's half of the posture trade,
                      via the lazy parryPostureMult knob in resolveParry
    PingCompensation  delays resolution up to 90% of your ping, aborting
                      the moment you parry, dodge or attack
    HeavensEqualizer  up to +0.04 parry window, scaled down as wins
                      approach 30, plus a flat 0.04s grace under 2 wins
    Burn              damage every 0.4s, HALVED if you cannot dash,
                      cancelled outright by dodging
    Shock             -6 speed, 0.1 damage per 0.02s, capped at 4 total
    RendingBlow       guard breaking applies Bleed, off attack.guardBroke
    Bloodletting      weapon heavy on a bleeding enemy eats the bleed, heals
                      what it had left. PICK ONE with Deep Wound
    DeepWound         same trigger, +4s on the bleed instead, on a 4s cd so a
                      multi-hit heavy cannot stack it per hit
    FirstInstinct     the hit that would start your fight is dodged, and
                      registers a 0-dmg entry so it fires once. PICK ONE
                      with Adrenaline
    Adrenaline        +5 speed for 10s on the hit that starts your fight
    PiercingChill     +5% damage from YOU to anything holding a live Freeze
    Dispel            weapon heavy HIT puts the victim's last_ability on a
                      240s cd. Skips ids never triggered this life
    Purity            debuffMult 0.5: DEBUFFS on you get half the duration
                      and amp. Shock's amp is hardcoded, so duration only
    SecondWind        under half posture, postureHeal x2 as a MOD (so the
                      client's own step follows). PICK ONE with Composure
    Composure         postureHeal +25%, flat
    Bleed             1 damage a second for 10s, flat and unconditional
    Hemorrhage        +2% damage taken per stack, up to 10 stacks (20%),
                      stacks share one duration, no per-stack decay
PingCompensation and HeavensEqualizer are latency subsidies (4.16), not
balance knobs.

## 9. THINGS THAT LOOK LIKE BUGS
Listed so nobody "fixes" one without deciding it is a balance change.

  * FIXED, was: "dodgeH does nothing." It genuinely did nothing --
    HandleAttack called :isDodge() with no attack while its parry and
    block siblings both passed one, so per-weapon dodge difficulty, the
    directional bonus and HollowPurple's i-frame pierce were all inert.
    It passes the attack now. TWO consequences, both live:
      - every authored dodgeH took effect at once (8.5 lists them).
      - the directional bonus is real: moving INTO a blow widens your
        window by up to 0.1, running with it narrows it by the same.
        VELOCITY_NUDGE / NUDGE_MIN_SPEED in HumObj, one place to tune.
    AND isDodge no longer WRITES to dodgeThreshold. It used to, which
    meant the three cards that poll it (PingCompensation every Heartbeat
    for the length of a ping, Nick_Amplifier, HeavensEqualizer) moved the
    defender's real dodge window every time they asked a question.
  * Medium weapons have no postureGain, so they are punished on parry
    like light weapons despite swinging the biggest heavies (4.3).
  * One ability has no cooldown at all.
  * Underdog's text says 20%, its code does 15%.
  * Two heavy weapons are numerically identical, and three medium
    weapons share one heavy attack.
  * The grab heavies try to clear stun on release with a lowercase field
    name, so that half of the release does nothing.

## 10. WHAT A KILL PAYS OUT
One question ("who actually did the work?"), asked once, paid three ways.

  HumObj/onDeath -> ProcessDmgRecord builds ONE `enemyLog` from the
  victim's dmgRecord (Class/HumObj/damageRecord, entries live 60s and are
  keyed weakly). Everything below reads that same log:
    heal      the killers, by `myDmgToEnemy` (health pack, inline)
    death msg topRecent / topDmg / topFair killer, FireAllClients
    xp        onDeath/processXp   <- per contributor
    elo+W/L   onDeath/processElo  <- needs BOTH sides to hold a slot

  Order matters: processXp runs BEFORE the
  `myPlrObj == nil or loadedSlot == nil -> return` guard, because killing
  a slotless NPC should still level you. processElo is after it on
  purpose -- elo is a rating between two saved accounts.

  ### WHO DECIDES THE AMOUNT (the rowa1 lesson)
  THE DYING THING ANSWERS, ONE SITE DIVIDES.
    `victim:xpWorth()` -> total pot   (Combatant contract, inert 0)
    processXp          -> splits it by damage share, and knows NOTHING
                          else: not slots, not levels, not plrObj
  rowa1 put this rule in SEVEN places -- six AiCores each with their own
  multiplier and clamp (*1/*2/*3, clamp 400 vs 1000) plus a separate
  player path in rewardKillers -- because every death site decided the
  amount itself. Adding a boss/crate/entity class here needs no edit to
  the payout: it either inherits inert 0 or defines its own xpWorth.
  DO NOT put a `what kind of thing died` branch back into processXp.

  HumObj.xpWorth is the ONE place that asks "am I player-backed?":
  player -> its slot's lvl, anything else -> `.xpLevel`, a plain number a
  summon sets in one line next to its cards. Unset == 0 == worth nothing.

  ### THE XP INVARIANT
  A kill is a pot worth KILL_LEVELS (2) levels of xp AT THE VICTIM'S
  LEVEL (HumObj.xpWorth). You are paid your damage share of that pot. So
  an even 1v1 -- you dealt half the damage that killed them -- is EXACTLY
  ONE LEVEL, at every level, because both sides ride the same curve.
    lvl1 kills lvl1 @50% -> 160 xp, nextLevelXp(1) == 160 -> lvl 2.
  Three-way where you did a third of the work pays a third of a level.

  Victim's level, NOT yours. Scaling by the KILLER's level cancels the
  curve exactly (kills-per-level becomes 1/(2*share) at every level), so
  farming the weakest thing alive would pay the same as beating the best
  player on the server. It also cannot be expressed as xpWorth -- the
  corpse does not know who killed it -- so it would force the branch back
  into the payout. Victim-level is the only one that survives the design.

  YOUR OWN LEVEL IS NOT IN THE FORMULA, deliberately. Punching far above
  your weight can pay several levels in one death (a lvl 1 soloing a
  lvl 30 banks 8000 -> lvl 10) and that is intended, not a bug to clamp.
  giveExp rolls over as many times as the exp covers. Farming DOWN needs
  no guard either -- the pot IS the victim's level, so it decays by
  itself: a lvl 30 killing a lvl 2 gets 640, a rounding error up there.

  The curve is NOT duplicated. processXp calls
  plrObjClient/slot.nextLevelXp with a `{lvl=n}` stub, so retuning
  `math.clamp(lvl * 160, 10, 4000)` there retunes kill xp for free.

  Two knobs, now in the two places that own them:
    KILL_LEVELS 2     the pot, in levels        (HumObj, by xpWorth)
    MIN_SHARE   0.05  below this you did nothing (processXp). Also saves
                      a packet, since giveExp applyPatches.

  Self-damage (RPG blast, HitSelf) is excluded from the pot exactly like
  the heal loop excludes it: nobody earns off someone else's suicide. An
  already-dead killer still gets paid; a killer with no slot loaded is
  skipped, not errored.

  processXp only decides who gets how much; Progression.md owns everything
  after the payout.

  NPCs have no slot, so they are worth 0 until given `.xpLevel`. That is
  the boss-bounty hook, one line: `humObj.xpLevel = 12`.

  `/s xpdummy` is that hook's test rig: `dummy` plus `humObj.xpLevel = 1`,
  so killing it pays exactly what killing a lvl 1 player pays. Solo == 2
  levels, split == 1 each. Bump the number for a higher bracket.

  Do NOT "simplify" this by faking a plrObj on the dummy. plrObj is the
  is-a-player DISCRIMINATOR, not just a data bag: ChangeState branches
  `if self.plrObj then FireClient(plrObj.Plr) else Hum:ChangeState()`,
  so a fake without a real .Plr takes the player branch and the state
  change goes nowhere, silently. FireVFXClient and two cards read it the
  same way, and processElo would index .Data on the fake and throw
  mid-onDeath, before isActive=false -- a stuck corpse. xpWorth cannot
  lie about being a player; a fake plrObj can.

