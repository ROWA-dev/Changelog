# ADMIN - the ROWA admin command system
(index: parent ServerStorage/README.md)

Slash-command admin. Lives entirely in ServerStorage; the only thing that
reaches a client is one cloned ScreenGui.

## WHERE THINGS LIVE
  ROWA/Modules/loadRowaAdmin        loader: owns the RF, the GUI clone, the manifest
  loadRowaAdmin/commands            THE command table + binder + executor
  loadRowaAdmin/commands/types      arg type registry (parse/complete)
  loadRowaAdmin/commands/<name>     one module per command, `function(ctx, args)`
  loadRowaAdmin/commands/syntaxFuncs  selector/players/plr transformers only
  loadRowaAdmin/PERMS               the bitfield + the userId table
  loadRowaAdmin/rowaAdmin           the ScreenGui that gets cloned (adminClient)
  loadRowaAdmin/rowaAdmin/shared    the ONLY server+client shared code channel
  loadRowaAdmin/entityInspect       one serializer for /data AND the entity panel

Kicked off by ServerScriptService/Core. A second entry point exists:
ServerScriptService/Init/SERVERS.luau calls `commands.loadCommand` with a
VIRTUAL player table for the Discord bridge, so no command may assume
`ctx.executor` is a real Player.

## AUTHORING A COMMAND

    {
      names = {"kill"},
      desc  = "kill things",
      args  = {
        { type = "selector", name = "targets", desc = "who", default = "@s" },
      },
      perms = PERMS.MOD,
      module = script.kill,
    }

    -- kill.luau
    return function(ctx, args)
        for _, char in args.targets do ... end
    end

ARGS ARE NAMED, NOT POSITIONAL. `args.targets`, never `params[1]`.

`default` IS A SOURCE STRING, NOT A VALUE. It runs through the same parse as
typed input, so `default = "@s"` means "me" for free and there is one code
path for typed and defaulted args.

`optional = true` with no default means the arg may be nil and the module
must handle it. Prefer a default.

`greedy = true` on the LAST arg swallows the rest of the line, so
`/kick bob spamming in chat` works.

ARG SPECS CARRY TYPE OPTIONS. `min`/`max`/`integer` on a number, `choices`
on a literal. Read at parse time, so bad input is rejected before the
module runs.

`listOnEmpty = "<argName>"` makes the BARE command print everything that arg
accepts instead of a missing-arg error. The list is the arg type's own
`complete`, so it cannot drift from autocomplete.

## SUBCOMMANDS
A command may declare `subs` INSTEAD of `args`. Token 2 selects the branch;
each branch has its own args, perms and module, and inherits the parent's
perms unless it sets its own. Use this when branches have DIFFERENT ARITY
(`effect give` takes 4 args, `effect clear` takes 2) - a flat signature
cannot express that without the module re-validating itself.

Subcommand names are matched EXACTLY, never fuzzily: branches do opposite
things, so resolving a typo to the wrong one is a destructive guess.

## THE MODULE CONTRACT
  return a string        -> success, printed to the response pane
  return false, "why"    -> SOFT FAILURE, painted red
  raise                  -> caught by loadCommand's pcall, logged
`ctx` is {executor, userId, name, perms, source, character, commandName}.
`ctx.executor` and `ctx.character` may be nil (bridge/system callers).

## THE AMBIGUITY RULE (enforced at load)
Adjacent optionals are LEGAL when they share a type, ILLEGAL when they do
not. `[seconds] [amplifier]` both numbers -> filling left to right is the
only reading. `[targets] [reason]` -> "60" is a valid player name AND a
valid reason, so the binder would have to guess. Malformed command
definitions fail at server start, loudly, not at 2am.

## ARITY-AWARE BINDING
The binder walks the SPEC, not the input, so omitting a middle optional
cannot shift later args left. It counts tokens spare beyond the required
args and spends that budget on optionals left to right, which is what lets
a LEADING optional precede a required arg:
    /size 2      -> scale me
    /size bob 2  -> scale bob

## ARG TYPES
Registry is commands/types.luau. Interface:

    parse(ctx, raw, spec) -> ok: boolean, value | errMsg
    complete(ctx, spec)   -> { string }        optional
    multiplicity          -> "one" | "many"
    static                -> boolean           optional, default false

PARSE IS FALLIBLE, NOT RAISING. Input errors are `return false, msg`. A
parse that RAISES is a bug in the TYPE. Keep it that way - the binder does
not pcall it.

MULTIPLICITY IS DECLARED, so the binder unwraps and modules never write
`args.weapon[1]`.

`static` MEANS THE LIST NEVER CHANGES AT RUNTIME (fixed asset trees:
weapon/tool/ability/summon/effect/number/literal/message). Static lists
ship INSIDE the manifest and complete clientside with ZERO round trips.
Only selector/players/plr still ask the server, because only those depend
on who is online and where they are standing.

Adding a "list of things" type needs no new module: use the `resource`
combinator and give it an `enumerate`.

## PERMS
Bitfield in PERMS.luau, 2^n, values are serialized-ish - never change them.
DEFAULT_PLAYERS IS KEYED BY STRING userId; `tostring(plr.UserId)`.
`test(userPerms, cmdPerms)` is a band ~= 0, so ANY overlapping bit passes.

Gated in three places, all of which must stay:
  1. loadRowaAdmin's RF handler - BOTH ids. Autocomplete was ungated once
     and leaked every player, weapon, tool and summon to anyone who found
     the RemoteFunction.
  2. loadCommand, per command, against the effective (sub) perms.
  3. entityEditRF, separately - it can call ANY method on ANY live entity,
     so it is more dangerous than the command that opened the window.
The GUI is only cloned for players with a non-zero perms entry.

## WIRE SHAPE
The command manifest is a StringValue of JSON parented INTO the GUI clone
before it reaches PlayerGui, so it arrives atomically WITH the gui - no
round trip, no OnClientInvoke handshake, no ordering question. A running
game CANNOT write `Source`, so this cannot be a generated ModuleScript.

adminRF: id 1 = autocomplete for one type, id 2 = run a command.

## FOOTGUNS
  Tokenising is `rowaAdmin/shared/cmdParse` for BOTH sides. A line ending in
  whitespace emits a trailing EMPTY token - that is load-bearing for
  autocomplete, not a bug to tidy.

  A THIRD copy of that tokeniser still lives in Init/SERVERS.luau for the
  Discord bridge and has already drifted. Point it here next time that file
  is open.

  Every write to the client's `signature` / `response` labels goes through
  Markdown. Both are RichText and both print `<targets>`, which is not a tag
  - one of those and the engine draws the raw source.

  Selectors return MODELS, not entities. `commands/targets.luau` has the
  resolve-and-report loop; use it rather than re-rolling one.

  Fuzzy thresholds are deliberate floors, not tuning knobs. Without one,
  `/weapon notarealweapon` silently equipped magicStaff and `banana`
  resolved to `ban`.
