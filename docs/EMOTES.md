# EMOTES - the emote subsystem
(index: parent ServerStorage/README.md)

Emotes are the one player-facing system with no combat in it, so the traps are
different: teardown paths, client-owned UI, and a saved loadout.

## 1. THE PIECES
  ServerStorage/ROWA/Emotes.luau              id -> class registry, playEmote
  ROWA/Emotes/EmoteBase                       base class, weapon put-away
  ROWA/Emotes/EmoteTemplate                   copy this to author one
  ROWA/Emotes/StayInPlace                     abstract tier: pins you, cancels
                                              itself on dash and slide
  ROWA/Modules/liveEmote                      plr -> live instance, leaf module
  ROWA/Class/HumObj `StopEmote`               THE teardown, all three callers
  StarterGui/EmoteUi/EmotesGui                the wheel + the replace picker
  ROWA/Emotes/Phone/rowaPhone/Apps            phone app id -> module registry
  ROWA/Modules/phoneSpeak                     Speak's server half: filter,
                                              budget, the voice everyone hears
  ReplicatedStorage/Modules/pianoConfig       piano audio id + grid, both sides
  ReplicatedStorage/VFXQuiver/pianoNote       plays one note, every listener
  ReplicatedStorage/VFXQuiver/pianoIK         poses the hands off that same call
  ServerStorage/ROWA/VFXQuiver/bindLock       drops/restores every keybind

## 2. THE CLASS TREE
    EmoteBase
      |- StayInPlace (abstract, no BaseAnim)
      |    |- Flex, Fraud, Sherbet
      |- Camera (Selfie), Phone, Piano
  Leaves under StayInPlace `require(script.Parent)`, so MOVING one changes what
  it inherits. The others name EmoteBase explicitly and can sit anywhere.

  `selfEnd = true` is the declarative "end when the animation ends". Do NOT
  hand-roll `track.Ended`: EmoteBase.Play owns it and carries the re-entrancy
  guard, because Ended ALSO fires when destroy() stops the track, and a second
  destroy on a table.clear'd self throws.

  BaseAnim INHERITS through __index, exactly like `req` on weapons. An emote
  with no Animation child silently plays EmoteBase's placeholder. Piano's is a
  LOOPED single-keyframe sit, which is also why it cannot use selfEnd: a looped
  track never fires Ended.

## 3. LIFECYCLE
  Emotes.playEmote(id, hum)
    validates the id (they come from a client), refuses while stunned or
    attacking, `humObj:StopEmote()`, builds, REGISTERS, then Plays.
  Registration happens BEFORE Play on purpose: an emote that ends inside Play
  has to find itself on the humObj to deregister.

  Teardown, every path:
    stun / attacking / blocking   HumObj connections -> StopEmote
    dash / slide                  StayInPlace only, its own connections
    animation finished            selfEnd
    another emote                 playEmote's StopEmote
    death, leaving                HumObj:destroy -> StopEmote
  EmoteBase.destroy DEREGISTERS ITSELF off humObj._emoteInstance, so a
  self-ending emote cannot leave a cleared table behind. StopEmote still nils
  it, which is the only cover for a leftover that never called destroy.

  `_humObj` is resolved ONCE in EmoteBase.new. Never look it up during
  teardown: Entities.Get lazily REGISTERS a miss, so a destroy-time lookup can
  build a whole new HumObj (loadChar does Unregister -> Get on every respawn).

  The weapon is put away in .new and given back in .destroy as one unit, so
  every path above restores it for free. A HELD weapon comes back with
  holdOut, not wield -- wield would make emote a requirement bypass.

## 4. THE LOADOUT
  Per ACCOUNT, saved: `PlrData.emoteData`, an id per wheel slot. #it IS the
  slot count the wheel draws. Client-writable through C2S.SaveEmotes ->
  verifyEmotes; deepMerge pins it to the default's LENGTH, so a client can
  reorder slots but never add one. See DATASTORE 7 and 9.

  The wheel builds on FIRST OPEN, not at init -- a viewport rig per slot is
  real memory and most players never open it. Hold a slot to get the replace
  picker; rows are text only, because a rig per row would cost more than the
  wheel does.

  !! NOTHING ON THE WIRE IS KEYED BY EMOTE ID. listEmotes replies
  index-parallel to its request and emoteCatalogue is an array of {id, name}.
  A numeric-keyed table that does not start at 1 does not survive a remote
  intact -- it reindexes, and the wheel then draws one emote while holding
  another's id. That shipped once; do not reintroduce it.

## 5. CLIENT INPUT
  An emote that needs input owns a channel and a method:
    Phone   RemoteEvents.Phone -> Tap / Speak / StopSpeak, ids in its `enums`
    Piano   RemoteEvents.Piano -> ready / play / abort
  Both resolve the sender with `ROWA/Modules/liveEmote`, then check the
  instance is theirs before acting (Piano compares the metatable).

  The phone is an OS: `Apps` is the registry, buttons are GENERATED from it, and
  an app class is required on the tap that opens it and never sooner. Contract is
  `.new(phone, parentFrame)` + `:destroy()`, one live app at a time.
  Apps live INSIDE the ScreenGui because it is cloned into PlayerGui -- a module
  in ServerStorage is unreachable from there. `fullscreen = true` parents to the
  ScreenGui instead of the handset's appFrame; Draw, Encyclopedia and ImgBoard do.
  The Encyclopedia is THREE TABS OVER ONE ROW LIST: cards, abilities, and a dev
  coverage grid. A tab is half the search predicate, not a second list -- the two
  catalogues share a column order so the page is never written twice, and each is
  fetched on the first tap of its own tab.
  An app's Janitor holds RenderStepped/Mouse connections that are NOT children of
  the gui, so `Destroying` has to close it or they outlive the emote.
  !! AN APP OTHERS SEE OR HEAR BUILDS IT ON THE SERVER. Speak's TTS chain was
  client-built and so replicated to nobody; it lives in phoneSpeak now, on an
  emitter on your rootpart, behind filterText and a cooldown + window budget
  because the TTS quota is per EXPERIENCE (1 + 6 * CCU a minute).

  bindLock (server quiver, lazy) drops EVERY game keybind and restores from
  plrData. It exists because initInputReader reads raw UIS and only skips
  gameProcessed, so ContextActionService cannot sink over it. It also
  re-binds on CharacterAdded, because a release that never lands must not
  cost someone their controls for the session.

## 6. THE PIANO (vendored)
  NickPatella's bundle, kept mostly intact. Case + Keys are welded to the
  player and the emote roots them; its Bench, Stand and Main are DELETED
  because Main only ever activates off a Seat.

  Dependencies:
    RemoteEvents.Piano     was the bundle's Workspace GlobalPianoConnector,
                           moved and renamed to sit with every other remote
    Emotes/Piano/PianoGui  cloned into PlayerGui while playing only

  The gui pings "ready" when its own script is live and the server activates
  off that. Do not go back to activating on spawn: the clone's script has not
  connected yet and the activate lands on nothing. That is the same race that
  broke the first seat-based version.

  !! I and O are NOTES here and also roblox's camera zoom, and UIS.InputBegan
  cannot be trusted for them. A CAS action at High takes them while playing and
  plays the note itself; RbxCameraKeypress sits at Medium, so sinking the press
  also stops the camera yanking. The UIS listener skips I/O so nothing doubles.
  bindLock is no help here, it only clears OUR binds.
  !! IN STUDIO THOSE TWO KEYS ARE DEAD AND THAT IS NOT THIS CODE. Measured:
  InputBegan never fires, CAS never gets Begin, IsKeyDown never goes true, and
  one InputEnded per session is the only thing that leaks. Live is fine. Test
  the piano IN GAME, and do not spend a day re-deriving this in studio.

  Notes: the pianist hears their own locally on the keypress; the server fires
  VFXQuiver/pianoNote at everyone ELSE, and skips anyone beyond RANGE so being
  out of earshot costs no packet. That module ships rather than lazy loading,
  because fetching on the first note you hear is a round trip of silence.
  Your OWN note takes that same RollOff and the listener is the CAMERA, so a
  camera further than RANGE from your character hears nothing.
  Payload is (pianist, note) only -- ids and range are static and client-side,
  position comes off the already-replicated character, and the falloff is the
  engine's because the Sound parents to a part. The bundle solved volume by
  hand only because it parented sounds to a gui folder, making them 2D.

  Sheets: one character is one step (an eighth at the BPM box), [..] is a chord
  inside one step, {..} is a RUN splitting one step between its notes, and - is
  a rest, as is | (virtualpiano.net's rules: "as|df - Pause for |"). Spaces and
  any other stray character cost no time. Tempo is re-read every step, so the
  box retimes a song while it plays.
  !! WE ARE ONE DIALECT OF TWO. VP itself has no - or {}: it reads RUNS of
  letters as fast, spaces as the rhythm, and [a s d f] as a fast sequence
  rather than a chord. Ours is a uniform grid where every character is a step.
  Sheets from either dialect play, but a VP-native one comes out slower and
  flatter than written. Decide before "fixing" a sheet that sounds wrong.

  Vendored edits are marked inline through PianoGui/Main, including its
  client-only auto sheet player. Re-importing the bundle loses:
  the exit firing Abort (Deactivate alone is local, so the server never learns
  and a welded piano never goes away), the "ready" ping, note playback
  delegating to VFXQuiver/pianoNote, the I/O key grab, the remote being
  RemoteEvents.Piano rather than a loose Workspace object, and the auto
  player's live tempo and {} run timing.
  !! A fresh import also arrives with Sandboxed = true, because Studio marks
  scripts from community models. A sandboxed thread CANNOT require a
  non-sandboxed module, and everything in this place is non-sandboxed, so it
  cannot reach pianoNote or pianoConfig until you clear that flag.

  Audio is ONE asset, 107672995343601, holding all 61 notes C2..C7 on a fixed
  5.0s grid; note n is played by seeking TimePosition = 5.0 * (n - 1). Levels
  are baked in the render, so there is no per-octave gain. Rendered from
  Salamander Grand Piano V3; every pitch is shifted offline, never with
  PlaybackSpeed. Being over 6s it is PRIVATE, so it must stay granted to this
  experience -- a lapsed grant silences the whole piano, not one note.
  Nothing sends a note-off, and the samples were rendered UNDAMPED (the
  library's release layers never fire for a note that is never released), so
  pianoNote damps them itself: ring for HOLD, then fall over FADE. Without
  that a tap rings the full 4.6s and dense passages turn to mud.

  Hands: pianoNote calls pianoIK, so the pose costs no wire and every peer
  runs it for itself (Motor6D.C0 does not replicate -- same deal as dragIK).
  It lives and dies with char.Keyboard. 7 studs of keyboard against a 2 stud R6
  arm, with the keyboard TANGENT to reach, so the hand only sits ON the key
  because R6IK's `stretch` lets the arm leave the shoulder for it -- 0.24 of
  gap at middle C, 0.67 at the outer key, measured. Deliberate, and the file's
  header says why. Read it before touching SPREAD or the emote's FRONT.
  A hand with no note for RELEASE lifts off the keys; IDLE seconds of silence
  drops the whole pose so the authored sit animation comes back.

## 7. GOTCHAS
  * ids are PERSISTED in emoteData. Only APPEND, same rule as weapons.
  * getEmoteClass errors on an unknown id; isValidId is the soft check, and
    every client-facing path uses it.
  * An emote with no Animation child inherits EmoteBase's placeholder, and the
    wheel's viewport preview shows it too (listEmotes reads BaseAnim).
  * !! Do NOT give one an Animation child with an EMPTY AnimationId to mean "no
    pose". LoadAnimation rejects it, and EmotesGui's requestAnims tests
    `if animID then` -- "" is TRUTHY in Lua, so it throws mid-loop and blanks
    every later wheel slot. Override Play and return nil instead. Nothing does
    that yet, so there is no exemplar to copy -- every emote holds a real pose.
  * The OS sweeps every `.jpg` key in the phone table into the ImgBoard gallery
    store in ONE SetAsync, and cleanGallery caps the TOTAL. So an oversized
    entry does not fail alone -- it refuses the whole save and takes the
    player's drawings with it. Photos mirrors GALLERY_CAP client-side and
    refuses the photo instead; anything else writing that table must too.
  * The gallery format is RUN-LENGTH. Measured: a flat 320x320 drawing is 84
    BYTES, the same frame as a photo is 300-455KB. That is why Photos samples
    at 80 and upscales by 4 -- integer, so every pixel gets a run -- landing at
    ~26KB worst case. Re-measure before touching either number.
  * walkSpeed mod key is "emote" everywhere. Safe only because ONE emote is
    ever live; do not reuse that key elsewhere.
  * Camera (Selfie) builds a PROP, never a Tool. A Tool parented to a
    character is equipped, and the moment it is unequipped plrObj's Backpack
    watcher mints a real inventory item that outlives the emote.

## 8. AUTHORING ONE (checklist)
  1. Copy EmoteTemplate. Under StayInPlace if it should pin the player.
  2. Give it an Animation child, or override Play.
  3. `selfEnd = true` if it ends with its animation.
  4. Clean up in destroy, and call baseClass.destroy LAST.
  5. APPEND it to emoteList in Emotes.luau.
  6. Needs client input? Reuse liveEmote, do not re-derive the lookup.
  7. Needs a UI? Clone it in on demand like Phone and Piano. Not StarterGui.
