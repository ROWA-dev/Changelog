# DESTRUCTION - carving the map, what falls, what comes back
(index: parent ServerStorage/README.md)

## Files
    ROWA/Destruction_Stable/
      Destruction         public API: Sphere, Sphere_Fast, Cylinder, Ellipsoid, OBB, Grab.
                          `plr` is ignored everywhere; kept so ~40 callers didn't change
        Carve             THE carve engine + the four shapes
        FloodFill         what a carve left unsupported
        DestroyedHandler  regen records, falling islands ("stars"), regen, re-gluing loose assemblies
      DestUtils           hitbox (anchored, plus opted-in loose parts for carves), subdivide, greedy mesher, visualize
      RuntimeStorage      carved originals wait here until regen

## One call, start to finish
1. Carve returns ONLY parts that lost something: kept + removed cuboids per part.
2. The removed cuboids go to every client as `dbri`. Rubble is client-only; the server never owns it.
3. Each carved part moves to RuntimeStorage and fragment parts replace it, under one regen record.
   A re-hit fragment folds into the SAME record, so re-carving never stacks records.
4. FloodFill seeds from the new fragments, plus the neighbours of any part swallowed whole.
   Anything that cannot reach ground is welded into one star and dropped.
   A LOOSE part that was carved skips the flood fill: its assembly, snapshotted before the cut, is re-glued
   by what still touches (`reglue`), so pieces cut off fall on their own and keep the old velocity.
5. After ~120s the record regens: its stars go home, the original comes back, fragments are destroyed.

## Adding a shape
A shape is `(cf, query box size, default minSz, sd)` in Carve. `sd(p)` is the signed distance from `p`,
in the shape's own frame, to its surface; negative inside. It may UNDERestimate, never over: an
overestimate classifies blocks as fully in/out when they straddle, and holes come out wrong.
No exact distance? Scale a cheap one down until it is a bound (see ellipsoid).
The query box must contain the shape: only its footprint on each part is split, the rest stays whole.

## minSz is the caller's accuracy knob
Blocks under minSz are decided by their centre, so misclassified volume scales with minSz
(r8 sphere: 22% at 4, 3% at 0.5). Lower = rounder holes and more fragment parts.

## Memory (measured with Stats + gcinfo)
- What a carve holds until regen is INSTANCES: every fragment is a Part (~1.3 KB of server physics
  memory, more on every client in range once rendered) plus the original parked in RuntimeStorage.
  The record's Luau bookkeeping is ~3 KB for a 40-fragment hit, ~5% of that. Fewer fragments is
  the lever, which is why Carve windows (heavy hit 191 -> 40).
- A carve allocates ~40 KB of Luau garbage and keeps none of it.
- Regen always comes, so everything held is released: the wait for an occupant has a 60s ceiling;
  star members wait for their star, whose owner has a finite clock.
- `reglue` clears its shared OverlapParams after use (GOTCHAS, HITBOX TRAPS: params hold strong refs).
- Client: dbri keeps a pool of up to ~200 debris parts (each with a dust emitter), reused oldest
  first and never destroyed. That cap is destruction's steady-state cost per client.

## Gotchas
- `velo` is studs per SECOND, not a direction. See the header of Destruction.
- Unanchored parts are carvable only if tagged `breakable` (the part or its direct parent). Stars tag
  theirs while down. The flood fill never sees loose parts, so a fallen thing never holds anything up.
  DestHitbox also skips characters and `nodestroy`, so a `nodestroy` part never holds anything up either.
- Welds this system makes are named `DestWeld` and are the only ones it ever breaks. Authored joints are
  never touched, so a welded table stays one piece when it falls. An authored weld to anchored geometry
  the flood fill cannot see (CanQuery off) PINS the island: it is left in place, no fling, no owner call
  (SetNetworkOwner throws on it), and still goes home at regen.
- A star member carved while down gets a record that waits for its star: the tree comes back whole.
  Loose and in no star (a boat) = permanent damage, no record.
- A breakable BOAT needs its own welds swapped for DestWelds at spawn, or reglue cannot split it (not
  built yet). Its parts must be CanQuery: re-gluing finds contacts with a spatial query.
- Ground is world Y <= -4 (FloodFill GROUND_Y). Anything higher must chain down to it through
  destructible anchored parts. The map does (RockGate, IslandTerrain).
- A star goes home with its root fragment's record, or the swallowed part's. Parts that fell into
  the void are gone for good.
- Regen waits while a character stands inside the carved part's box.
- Re-hit fragments are destroyed immediately, never via Debris: a deferred removal leaves the old
  piece bridging the gap while the flood fill runs.
- Fragments are parented straight into the world. StreamingEnabled is on, so a ReplicatedStorage hop
  would send every piece to every client.
