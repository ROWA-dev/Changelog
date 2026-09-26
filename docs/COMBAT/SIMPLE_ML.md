# SIMPLE_ML - ML_SIMPLE, the parry model
(index: parent ServerStorage/README.md/COMBAT.md)

SCOPE. ML_SIMPLE stands still, faces its target, and presses guard.
It does not move, attack, dodge, or choose block-over-parry. One
decision, one button.

DESIGN ONLY. No code exists yet.

## 0. THE ENDGOAL
Read this before changing anything below it. Every decision in this
document is downstream of this section, and several of them look
wrong until you have read it.

THE GOAL IS A BELIEVABLE OPPONENT WITH ONE DIFFICULTY DIAL, NOT A
PARRY MAXIMISER.

0.1 WHAT REPLACES WHAT
CombatAi today is configured by eleven hand-tuned chances -- feint_chance,
uppercut_chance, early_parry_chance, miss_parry_chance and so on --
and botSummonsSetup fills them with math.random per bot. Difficulty is
therefore RANDOM NOISE, not a setting, and the numbers have drifted
from their own comments (early_parry_chance is 4 next to a comment
saying 0.3).

ML_SIMPLE's endgoal is to delete early_parry_chance and
miss_parry_chance entirely and have both behaviours FALL OUT of one
number: R. A bot is not "70% likely to parry", it is SLOW or FAST, and
what it can and cannot answer follows from 4.16 rather than from a
dial someone guessed.

0.2 MODULE ONE OF A DEFENSIVE LAYER, NOT A ONE-OFF
Parry is first because 5.7 says it is CORRECT PLAY: the only answer
that stops the hit and takes the turn back. Dodge and block come
later.

This is why 5 keeps the decision rule out of the network. "When is the
next hit" is the SAME question for parry, dodge and block, so:

    ONE world model  +  N decision rules  =  the whole defensive layer

Module two is a new rule reading the same hazard, not a new model. Had
we learned the press directly, every module would need its own
training run.

0.3 THE TENSION THAT DEFINES SUCCESS -- READ THIS ONE TWICE
R is supposed to be the difficulty dial. BUT PREDICTION BYPASSES R
COMPLETELY: a model that knows the rhythm does not need to see
anything at all, so it parries just as well at R 0.5 as at R 0.1.

TAKEN TO ITS LIMIT, SUCCEEDING AT 1's SECOND ROW BREAKS THE DIAL. A
perfect predictor is a uniformly superhuman bot whose difficulty knob
does nothing. Stage 1 is precisely the case that produces one, because
a scripted attacker is perfectly regular.

SO: 100% PARRY RATE IS A FAILING RESULT, NOT A WINNING ONE.

The resolution is not to cripple the model. Humans DO learn rhythm and
DO parry sub-reaction-time attacks by prediction -- that is real skill
and it should be modelled. What humans do not have is zero execution
variance. So:

    the MODEL predicts as accurately as it can          (honest)
    the RULE presses with a motor-noise floor (5)       (human)

Target is a BAND, not a maximum (7). Note this partly self-corrects in
deployment: a real player holding m1 is not frame-perfect, so the
rhythm is genuinely noisy and the model's own sigma stays wide. It
does NOT self-correct against a scripted attacker, which is why the
band is enforced in the metric.

0.4 IT MUST LOSE TO THE RIGHT THINGS
Acceptance is behavioural, not just numeric. ML_SIMPLE must still lose
to everything a human loses to:

    flanking (4.8)          circling beats a turtle
    guard break (5.3)       posture pressure still wins
    LATE FEINTS (5.7)       a feint thrown after the commitment point
                            CANNOT be answered. Falling for it is
                            CORRECT, not a bug. A bot that never eats
                            a late feint is reading something it
                            should not be able to see.

5.7 says the feint needs a guaranteed customer. ML_SIMPLE is meant to
BE that customer.

0.5 INFERRED, CORRECT ME IF WRONG
Taken from "ONLY START WITH reaction time parrying" and from R being
synthetic (3.2), not stated outright:
  * the bot is for PLAYERS to fight, so fun and fairness outrank win
    rate.
  * it eventually runs on live servers, so learning is online, cheap,
    and must degrade safely.
  * per-opponent adaptation is probably wanted later (CombatAiV2's
    feintMap already learns per target and clears on target change),
    but it is OUT OF SCOPE here.

## 1. THE CORE CONCEPT: REACT, OR PREDICT
The first section to read after 0. Everything else is downstream.

The AI has a REACTION TIME R that can be set per bot. It observes the
world as it was at now - R; its press is instant. Every attack in the
game then falls on one side of a line, and R is what moves the line:

    windup >= R    it is SEEN in time. REACT.
    windup <  R    it lands before it is even visible. PREDICT.

The same attack is reactable for a fast bot and unreactable for a slow
one. THAT IS THE DIFFICULTY DIAL (0.1), and it is why the split is not
a property of the weapon.

1.1 THE REACTIVE HALF IS ARITHMETIC
`onAttackWindup:Fire(t)` hands over the windup AT onset, and
sharedFeintWait sets `attackAt = onset + t` on the same line.
So the moment an onset becomes visible you know the impact time
EXACTLY. Subtract the window, press. No model, no estimate.

1.2 THE PREDICTIVE HALF CANNOT SEE THE ATTACK IT IS PARRYING
This is the part that is easy to underestimate. Below the line the AI
is not reacting late, it is pressing BEFORE the attack it is
defending against has become visible AT ALL. Nothing about the current
attack is available. Only the history is. So one question:

    WHEN IS THE NEXT ATTACK, AND HOW LONG IS ITS WINDUP?

1.3 THE THREE THINGS IT HAS TO GET RIGHT
These are the design. Every input in 3 exists for one of them.

A. TEMPO OF AN UNREADABLE ATTACK.
   Someone holds m1 with a fast weapon. No individual swing can be
   seen in time. But the swings arrive on a rhythm, so the AI learns
   the TEMPO and fires on the beat rather than on the swing. It is
   parrying a schedule, not an attack.

B. WINDUP PATTERN -- "SLOW, SLOW, FAST".
   Windups vary across a string and across attack types. If the AI has
   seen slow, slow, it should expect the next to be FAST -- that is,
   to fall BELOW its own line -- and PRE-FIRE it, while it would have
   reacted normally to another slow one.

   THE AI MUST PREDICT WHICH SIDE OF THE LINE THE NEXT ATTACK LANDS
   ON, not just when it arrives. That is why windup history is an
   input (3) and why the output is time-to-IMPACT, which already
   bundles onset time and windup together.

C. ITS OWN PARRIES CHANGE THE TEMPO. THIS IS THE HARD ONE.
   A successful parry stuns the attacker 0.3-0.4s and locks their
   attack 0.4-0.5s (3, 8.2). So THE BEAT SHIFTS BY ROUGHLY HALF A
   SECOND THE INSTANT THE AI SUCCEEDS. A model that learned the free
   rhythm is now wrong, and wrong in the moment that matters most,
   because parry cooldown RESETS on success (3) and the chain is the
   whole reward.

   This is the parry-trade instinct a human builds: after your attack
   is parried you press parry again, on a rhythm you learned from
   BEING PARRIED, not from neutral. Both fighters are on the shifted
   beat.

   IT IS NOT AN EDGE CASE, IT IS THE MAIN LOOP of a bot whose only
   move is parrying, and the better the bot gets the more of its life
   is spent in post-parry tempo.

1.4 THE AI IS PART OF THE SYSTEM IT IS PREDICTING
C generalises. The AI's own actions perturb the thing it forecasts:
parry shifts the beat (3), a whiff makes their next swing 0.1 slower
for 0.4s (4.6), a block adds 0.4s of attack lockout (8.2).

So the target is NOT a fixed opponent rhythm. It is a rhythm that
jumps at events the AI causes. The model must be told what just
happened (3), or it will average the free tempo and the post-parry
tempo into one wrong number -- the same failure as averaging the
flourish gap, one level up.

1.5 R IS NOT SOMETHING THE MODEL ADAPTS TO. THE SITUATION ADAPTS.
Worth being precise, because it looks backwards.

The world model answers "when is the next impact". THAT ANSWER DOES
NOT DEPEND ON R -- the opponent swings when they swing. What R changes
is whether the onset is VISIBLE yet, which selects a branch of the
decision rule (5): visible -> arithmetic, not visible -> predict.

So the react/predict switch is AUTOMATIC, not learned. Raise R and the
same model starts pre-firing more attacks because fewer onsets arrive
in time. This is the property that makes R a real dial: CHANGING
DIFFICULTY REQUIRES NO RETRAINING (3.1).

## 2. NO ATTACK IDENTIFIER. AT ALL.
Considered and rejected: tag attacks by windup value, by animation
name, by weapon. All unnecessary, for a reason that is not about
availability:

    PARRY IS ATTACK-AGNOSTIC. You press guard and it parries whatever
    arrives. There is no branch where knowing WHICH attack is coming
    changes WHAT YOU DO.

Identity had exactly one job -- conditioning the interval between
attacks -- and the recent intervals already carry that implicitly. A
dagger's intervals do not look like a hammer's. Adding an id would be
adding a feature to predict something the features already predict.

Corollary: parryH is invisible and stays invisible (4.16, 8.5). The
model cannot know its own exact window. It does not need to; the
decision rule (5) uses the conservative window and eats the rest as
noise.

## 3. INPUTS: EIGHT FEATURES, ELEVEN NUMBERS
Only onsets that have become visible (>= R old) may be used. Grouped
by which part of 1.3 they serve.

TEMPO -- when does the next one arrive (1.3 A)
    1  dt          NOW minus the last visible onset's TIMESTAMP
    2  gap[-1]     interval between the last two onsets
    3  gap[-2]     the one before
    4  gap[-3]     the one before that

SHAPE -- how long will its windup be (1.3 B)
    5  windup[-1]  windup of the last visible onset
    6  windup[-2]  the one before

PERTURBATION -- did I just move the beat myself (1.3 C, 1.4)
    7  oppStun     opponent stun remaining, 0 if none
    8  outcome     one-hot(4) of the last resolved attack:
                   parried / blocked / hit / whiffed

dt IS MEASURED TO NOW, NOT TO THE DELAYED VIEW. THIS IS THE WHOLE
TRAP. You learn about an onset late, but you learn its TIMESTAMP, so
dt starts at R the moment the onset becomes visible and then counts in
real time. Computing dt as (now - R) - onset instead makes every
prediction R seconds early and silently breaks 4. One line, total
failure, no error message.

WHY BOTH 7 AND 8. They are not redundant. oppStun is the CONTINUOUS
countdown -- it says how much longer the pause lasts and it covers
guard break too. outcome is the CATEGORY, and each category has a
different tempo consequence with no stun attached: a whiff slows their
next swing 0.1 for 0.4s (4.6), a block adds 0.4s of lockout (8.2), a
landed hit adds none. Attack lockout is the quantity that actually
gates their next swing and it is NOT stun, so stun alone would miss
it.

ALL EIGHT ARE THINGS A PLAYER CAN SEE: swing timings, how long a
windup looked, a stagger, and whether their own attack got parried,
blocked, whiffed or landed.

WHY 5 AND 6 ARE NOT AN ATTACK ID. They are the "slow, slow, ..."
of 1.3 B: the model uses them to guess how long the NEXT windup will
be, which is how it knows whether the next attack falls above or below
its own line. Together with dt they also say whether the attack
already seen is still in the air -- impact was at onset + windup.
Used as a clock and as a pattern, never as a name (2).

THREE GAPS, NOT AN AVERAGE. A held m1 string is not a metronome. From
attackHelpers/m1:

    if this.m1cycle == 0 then this.m1last = tick() + 0.6  -- flourish
    elseif endlag then this.m1last = tick() + endlag end

The flourish takes 0.6s of endlag against the usual 0.1 or less (2),
so a 5-swing string runs fast-fast-fast-fast-LONG. AVERAGING THE
INTERVAL IS THE ONE MISTAKE THAT GUARANTEES FAILURE, and it fails at
the flourish -- the most parryable and highest-posture hit in the
game (4.13, 5.7). Three raw gaps let the model see the pattern; one
EMA would erase it.

NOT INPUTS. Own posture, own cooldowns, own stun: the decision rule
handles those. Distance: handled in the rule too (5). Anything the
server knows but does not render.

3.1 R IS NOT AN INPUT, AND THAT IS STRUCTURAL
Not "R is unnecessary", but: THE TARGET DOES NOT DEPEND ON R.

    P(time until next impact | dt, gaps)  is a fact about the OPPONENT.
    R                                     is a fact about ME.

R does not move the opponent's next swing. It only decides WHICH dt
values I am able to ask about. Feeding it in would add a variable the
answer does not depend on: a spurious feature to overfit, and it would
destroy the transfer property below.

This works ONLY because dt is measured to now (3). Written that way, R
is fully absorbed into dt and never needs to appear anywhere in the
model again.

CONSEQUENCE, TRAIN AT LOW R AND DEPLOY AT ANY R. The learned function
is R-invariant, so:
  * at R = 0 the model observes the whole range of dt.
  * at high R it never observes dt < R, so a model trained high is
    UNTRAINED exactly where a faster model would query. Transfer runs
    one way only: low -> high.
Training is passive observation of the opponent, so it does not care
what R the AI is playing at, or even whether it pressed anything.

SAME REASON, FREE DATA. One recorded event log can be replayed and
queried at ANY dt, not just the dt values the live R happened to
produce. Every event pair yields many training examples instead of
one. This is worth more than any architecture change in 6.

3.2 REACTION TIME AND INPUT LAG ARE NOT THE SAME THING
They are equivalent HERE, and it is worth knowing why in case that
stops being true.

    observation delay   see the world as it was at now - R, press
                        instantly.
    input lag           see the present, press lands L later.

Different mechanisms, identical consequence: the press landing at time
X was committed on information from X - delta. They diverge only when
an action can be CANCELLED after being committed. ML_SIMPLE presses
one uncancellable button, so they collapse into one number.

R IS SYNTHETIC. This AI runs on the server and has no real latency.
R is a fairness handicap chosen to match 4.16's ~0.25s see-and-press,
not a network property being measured.

## 4. OUTPUT: TWO NUMBERS
    mu, logSigma   -> log-normal distribution over TIME UNTIL THE
                      NEXT IMPACT

Not a press/do-not-press bit. Rejected: a bit gives the net no reason
to prefer any moment inside the valid window, so it fires at the
earliest one, which is exactly the press a late feint beats (5.7).
Rejected also: binning time into 16 buckets, which quantises the
answer against a 0.2s window and needs a junk bin for feints.

LOG-NORMAL BECAUSE:
  * two outputs. it is the smallest thing that carries "when" AND
    "how sure".
  * positive support, right-skewed. That is what an interval between
    events looks like.
  * closed-form CDF and survival function, so 5 and 6 are both a
    couple of lines with no integration.

## 5. THE DECISION RULE IS NOT LEARNED
The model predicts the world. The game rules decide. No payoff, cost
or risk appetite goes into the network.

Each tick, w = own parry window (conservative, assume parryH 0):

    if a KNOWN impact is pending (from an observed onset):
        press at impactTime - w + margin        -- arithmetic, 1
    else:
        P_press = CDF(w) - CDF(0)               -- lands in my window
        P_late  = 1 - CDF(w)                    -- lands after it
        press if P_press * REWARD > P_late * COST

then, on the press itself:

    press at (chosen time + jitter),  jitter ~ N(0, ~0.03s)

MOTOR NOISE IS NOT A HANDICAP HACK, IT IS THE SECOND HALF OF 0.3. R
models what you can SEE in time; jitter models that a hand cannot hit
an exact millisecond even when the brain knows it. Without it a
converged model presses perfectly and the difficulty dial stops
working. It lives HERE and not in the model because the model's job is
to be right and the rule's job is to be human.

It is also the only knob besides R, and both are per-bot.

COST is 5.9: a burned parry is 1.2s with the best option gone. REWARD
is 3 and 4.1. BOTH ARE READ OUT OF THIS DOCUMENT, so rebalancing
combat rebalances the AI and nobody has to remember a magic number.

The rule presses LATE by construction: waiting stays cheap while mass
sits beyond the window. That is 5.7's advice, with no feint logic
written anywhere.

Gates, all in the rule and none in the model: parry off cooldown, not
attacking, target within range.

## 6. ARCHITECTURE
    MLP  11 -> 16 -> 16 -> 2      tanh hidden, linear out
    ~500 parameters

Loss = negative log-likelihood of the log-normal.

    impact observed at T, predicted from time s   -> logpdf(T - s)
    windup started and FEINTED, no impact         -> log survival

THE FEINT LINE IS WHY THE OUTPUT IS A DISTRIBUTION. A feint (4.7) is
not a wrong answer and not a negative example -- it is a censored
observation, "no impact yet, at least this long". Survival handles it
in one term. A classifier would need a special case.

ONLINE. One gradient step per event, ~5 events/sec. No offline
training run, no dataset, no epochs. It can learn on a live server.

NO RNN. 500 params of MLP over explicit gaps and windups is smaller
and simpler than a GRU, and those features ARE the history. Revisit
only if 8 fails.

6.1 NON-STATIONARITY IS EXPECTED, NOT A BUG
By 1.4 the AI perturbs its own target, so as it improves, more of its
data is post-parry tempo. Two consequences to plan for:
  * early on it sees almost NO post-parry events, because it is not
    parrying yet. The 1.3 C regime is learned LAST and is the last
    thing to converge.
  * a constant learning rate is correct here rather than a decayed
    one. The distribution genuinely keeps moving; annealing would
    freeze the model in the pre-competence regime.

## 7. MEASUREMENT
Three references, and the model has to beat the third, not the first.

    REACTIVE   press R after seeing the onset. lower bound.
    ORACLE     reads attackAt directly. upper bound, AND the harness
               check: if the oracle is not near perfect, the harness
               is lying, stop and fix it.
    CONSTANT   assume the next impact comes one mean-interval after
               the last. no learning. THIS IS THE REAL BASELINE.

Beating REACTIVE proves nothing (row 2 of 1 makes it trivial to beat
by guessing). BEATING CONSTANT IS THE ONLY RESULT THAT MATTERS,
because CONSTANT is what a metronome does and 3 says the flourish
breaks metronomes.

Reported split by t >= R, always. Blending the two rows hides
the only interesting one. Two raw numbers underneath:

    parries landed / attacks faced
    cooldown-seconds burned per minute      (misses * 1.2)

7.1 THE TARGET IS A BAND (0.3)
Parry rate is scored against a BAND, not maximised. Outside it in
EITHER direction is a failure:

    far below   the model has not learned
    at ~100%    the dial is broken and the bot is superhuman

Band per R, set by playtest, not by this document.

7.2 THE DIAL TEST, WHICH OUTRANKS EVERY OTHER NUMBER
Sweep R on ONE trained model and plot parry rate.

    MUST fall as R rises.  A FLAT LINE MEANS THE PROJECT FAILED,
    however high the line sits, because R has stopped being difficulty
    (0.3).

This doubles as the falsification test for 3.1's invariance claim.

7.3 BEHAVIOURAL ACCEPTANCE (0.4)
Pass/fail, not scored: it gets flanked, it gets guard-broken, and IT
EATS LATE FEINTS. If it never eats a late feint, look for a leak
before celebrating.

## 8. STAGES
Per 3.1 the model TRAINS AT R = 0 throughout; R is set only for
evaluation. R appears below as a test condition, never as a training
condition.

    1  windup 0.90 heavy, eval R 0.25.  reactable. arithmetic only. if
       this is not ~100% the plumbing is broken, not the model.
    2  held dagger m1 (0.44), eval R 0.50. unreactable, 1.3 A. CONSTANT
       should already do well and the flourish is where it should not.
    3  PARRY CHAIN, 1.3 C. Attacker resumes immediately after being
       parried. Measures whether the second parry in a chain lands.
       A model ignoring inputs 7-8 should visibly fail HERE and only
       here, which makes this stage the test of 1.4.
    4  windup pattern, 1.3 B. Attacker alternates slow, slow, fast with
       the fast one below R. Score the FAST swing alone: it can only
       be parried by pre-firing off the pattern.
    5  add string resets and pauses (2), then mixed weapons. Sweep eval
       R on ONE trained model -- if 3.1 is right, no retraining is
       needed to change difficulty.

Stages 3 and 4 are the deliverables. 1 and 2 are plumbing checks.

Do NOT train against CombatAi. Its attacks roll on per-second
chances, so its timing is genuinely unpredictable and stage 1 would
teach the model that timing cannot be learned. It is a final
evaluation opponent, not a teacher.

## 9. KNOWN LIMITS
  * WHIFFED SWINGS COUNT AS IMPACTS. The model predicts every attack
    the opponent throws, including ones far out of range. Fine for a
    fixed-distance spar; put distance in the rule (5), not the model,
    and revisit only if training moves.
  * FIXED R IS NOT HUMAN. Real latency jitters. By 3.1 this is a
    smaller problem than it looks -- jitter changes which dt is
    queried, not what the model believes -- so test with jitter and do
    not train with it.
  * NO OPPONENT-STUN INPUT was listed here as an acceptable omission
    in an earlier draft. THAT WAS WRONG -- 1.3 C makes it the main
    loop, and it is now inputs 7-8.
  * IT ONLY PRESSES. It loses to flanking (4.8) and guard break
    (5.3). Not a model failure. Do not bolt on movement.

## 10. BUILD ORDER
    1  event tap: onset (with windup) and impact, exact timestamps.
       R-delayed VISIBILITY queue -- it gates WHEN an onset may be
       used, it does NOT rewrite its timestamp (3).
    2  harness: scripted attacker, event log.
    3  ORACLE and CONSTANT. No model yet. If the oracle is not near
       perfect, stop.
    4  the decision rule (5) with arithmetic only. Stage 0 should
       pass here with no network at all.
    5  the MLP. Stage 1. Report CONSTANT -> MODEL.
