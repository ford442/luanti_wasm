# Routines

Choreography, as data. Every `.lua` file here returns one routine table (or a
list of them) and `lw_dance` loads the lot at startup — adding a dance is
dropping in a file, with no Lua to edit anywhere else.

A routine says *what* is danced and by whom. It never says where: a **stage**
(registered by `lw_world` next to the build it belongs to, see
`lw_dance.register_stage`) says where the director stands and which way the
audience is, and `lw_dance:mark_lead` / `lw_dance:mark_1`… nodes in the map say
where each dancer stands. So the same routine plays on a theater stage, on a
porch, or wherever a visitor points it with `/routine start <id> here`.

```lua
return {
	id = "chorus_line_v1",   -- also the /routine argument
	title = "Chorus line",
	loop = true,
	bpm = 120,               -- optional: steps may then use `beat` instead of `t`
	length = 16.0,           -- optional: one pass, in seconds
	dancers = {
		{role = "lead", model = "person"},
	},
	formation = {kind = "line", spacing = 2},   -- used where marks run out
	steps = {
		{t = 0.0, role = "*", move = "groove", facing = "audience"},
	},
}
```

* `t` is seconds; `beat` is beats and needs a `bpm`. Both are kept, which is
  what makes `/routine bpm <id> <n>` change the speed rather than the labels.
* `role` picks a dancer, `"*"` means the whole cast.
* `move` is any move in the shared catalog (`games/luanti_web/mods/lw_dance/moves.lua`)
  — the same names a visitor's number keys play.
* `facing` is `"audience"`, `"away"`, `"partner"`, `"director"`, or a yaw in
  degrees.
* `model` is a rig registered with `lw_dance.register_model`: `person`,
  `ghost`, `scarecrow`, `berry`, `mascot_melon`.
* `ride` attaches the dancer to an entity that moves on its own; `path` gives
  that carrier a from/to, relative to the stage.

The cap is eight dancers per routine (`lw_dance.MAX_DANCERS`); the rest stay
off stage rather than stalling the browser worker.
