# ADMIN - the ROWA admin command system
(index: parent ServerStorage/README.md)

Slash-command admin, all in ServerStorage. Only admins get anything: one cloned ScreenGui.

## WHERE THINGS LIVE
  ROWA/Modules/loadRowaAdmin          loader: the RF, the GUI clone, the manifest, the hooks
  loadRowaAdmin/commands              THE command table + binder + executor
  loadRowaAdmin/commands/types        arg types (parse/complete)
  loadRowaAdmin/commands/<name>       one module per command, `function(ctx, args)`
  loadRowaAdmin/commands/syntaxFuncs  the selector; players/plr build on it in types
  loadRowaAdmin/PERMS                 the bitfield, the userId table, BRIDGE_USERS
  loadRowaAdmin/rowaAdmin             the cloned ScreenGui: Cmdr's console UI, baked as instances
  loadRowaAdmin/rowaAdmin/shared      the ONLY server+client shared code (cmdParse, fuzzySearch)
  loadRowaAdmin/entityInspect         one serializer for /data AND the entity panel

Started by ServerScriptService/Core. The Discord bridge (Init/SERVERS) also calls `loadCommand`.

## AUTHORING A COMMAND
    {
      names = {"kill"},
      desc  = "kill things",
      args  = { { type = "selector", name = "targets", desc = "who", default = "@s" } },
      perms = PERMS.MOD,
      module = script.health, -- kill/heal/damage share it via ctx.commandName
    }

Args are NAMED: `args.targets`, never `params[1]`.
`default` is a SOURCE STRING, parsed like typed input: `"@s"` means me.
`optional = true` without a default may arrive nil. Prefer a default.
`greedy = true` on the LAST arg takes the raw rest of the line, quotes and spacing intact.
`min`/`max`/`integer` on a number arg are checked before the module runs.
`listOnEmpty = "<argName>"`: the bare command lists what that arg accepts (its own `complete`).

## SUBCOMMANDS
`subs` INSTEAD of `args` when branches differ in arity (`effect give` 4 args, `effect clear` 2).
Token 2 picks the branch, matched EXACTLY since give/clear are opposites. Perms inherit unless set.

## THE MODULE CONTRACT
  return a string        -> success, printed to the console log
  return nil / true      -> silent success, the console closes
  return false, "why"    -> soft failure, painted red
  raise                  -> caught by loadCommand's pcall, logged
`ctx` is {executor, userId, name, perms, source, character, commandName}.
`executor`/`character` may be nil, or a VIRTUAL table from the bridge. Never assume a real Player.

## BINDING (checked at load)
The binder walks the SPEC: tokens spare beyond the required args fill optionals left to right,
so a LEADING optional works (`/size 2` = me, `/size bob 2` = bob).
Adjacent optionals must share a type, else `[targets] [reason]` would make it guess.
Bad definitions fail at server start.

## ARG TYPES
    parse(ctx, raw, spec) -> ok: boolean, value | errMsg    input errors RETURN false, never raise
    complete(ctx, spec)   -> { string }                     optional
    static                -> boolean                        the list never changes at runtime

One-value types return the value, not a list. `plr` rejects several matches.
Static lists ship IN the manifest (zero round trips); only selector/players/plr ask the server.
A new "list of things" type is a `resource({ label, enumerate })`.

## PERMS
2^n bitfield, never change the values. Read via `PERMS.of(userId)`; `test` passes on ANY shared bit.
Gated three times, keep all: the RF (BOTH ids, autocomplete enumerates players and assets),
loadCommand (the effective sub perms), entityEditRF (calls ANY method on ANY entity).

## WIRE
Manifest: a JSON StringValue in the GUI template, so it arrives WITH the gui. No handshake.
adminRF: id 1 = completion list for one type, id 2 = run a RAW line (the server tokenises).

## FOOTGUNS
  Trailing whitespace emits an EMPTY token, load-bearing for hints; loadCommand trims first.
  Popup and log text is RichText: write it through Markdown or one `<` shows raw source.
  Selectors return MODELS, not entities; `commands/targets` has the resolve-and-report loop.
  Fuzzy floors are deliberate: without one, `banana` ran `ban`.
