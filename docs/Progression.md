# PROGRESSION
(index: parent ServerStorage/README.md)

## CURRENT CONTRACT
Cap 15. Every level owns 2 points, including lvl 1: 30 total.
allocPts is unspent; prog is successful mixed-hand claims, not level.

  earnedProg  = lvl - ceil(allocPts / 2)
  pendingProg = max(0, earnedProg - prog)

earnedProg/pendingProg are derived, never saved. Unspent points bank; pending
drafts may stack. Allocation stays available while a draft is pending.

## UX
pointsToNextProg > 0 -> spend CTA + stat coach.
pendingProg > 0      -> draft button; coaching disappears.
An empty offer pool hides the button: draftOffer.hasAny rides the patch stream as
`draftable` (absent == unchanged, client defaults true), so a pending draft with
nothing eligible waits silently until stats open something.
The starter pair opens stats once. Later CTAs are click-to-open so combat is
not interrupted. Draft-ready sound/burst fires only on button hidden -> visible;
raw level-up feedback is a separate future effect.

## INVARIANTS
Allocation is immediate and permanent: no confirm, undo or respec.
Stats currently gate content; they do not directly scale combat values.
Draft eligibility is rebuilt from the invested build; offers are not saved.
A reward is granted before prog increments, so failed claims spend nothing.
A rebalance is retroactive: draftOffer.audit revokes picks whose req tightened
and refunds their prog, so the level is re-drafted rather than eaten.
An unclaimable pending draft is never consumed or skipped; it banks like a point.

## TWO-HAND TARGET — NOT IMPLEMENTED
Every invested level, including the free lvl 1, owes TWO independent hands:
one Card hand and one Ability hand. The player claims exactly one from each.
At cap that is 15 Cards + 15 Abilities. Neither hand may replace or consume
the other; separate claim counters/pending counts replace the mixed prog queue.

## OWNERS
slotSS grants/caps; client slot derives; inventory/charInfo coach;
draftUI shows; draftOffer rolls/claims.
XP payout: COMBAT section 10. Save/migration: DATASTORE section 6.
