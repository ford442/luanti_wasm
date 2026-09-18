<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Routines: the stage director

[Dance mode](dance.md) is the visitor pressing keys. This is the other half —
the cast that is already dancing when they walk in.

A **routine** is choreography as data: who is in it and what they do, on a
clock. A **stage** says where that happens. A **director** owns the clock,
puts the cast on the stage, and plays the routine's steps on them through the
same move catalog the visitor's number keys use. That sharing is the whole
design: a visitor and a chorus line are running the same `groove`, out of the
same table, at the same phase if the director says so.

## Trying it

| | |
|---|---|
| Theater | Walk to the stage in front of the screen and punch the violet **Stage Director** to the right of it. Three dancers take the marks and run `chorus_line_v1`. |
| Halloween lane | Punch the director at the back of the porch: a scarecrow and two ghosts, slow. |
| Fruit garden | Punch the director on the path by the melon bowl: a melon mascot stomping, and a berry that rides a raft down the juice channel. |

Or from chat:

```
/routine list                       what exists, and what is running
/routine start chorus_line_v1       start it on its own stage
/routine start chorus_line_v1 here  start it where you stand, facing you
/routine stop [<id>]                stop one, or all of them
/routine seek <id> <seconds>        jump the clock
/routine bpm <id> <n>               change the speed
/routine status [<id>]              where the clock is
/routine join [<id>]                dance along with it
/routine leave                      stop dancing along
```

Stopping a routine despawns its cast. Nothing is saved: a routine is something
that is *running*, and a world reloaded next week should come back to an empty
stage rather than to three dancers frozen mid-bow with no clock behind them.

## Joining in

**The director never drives a player.** It does not move you, turn you, or
take a key from you. `/routine join` is an opt-in that says "hand me the same
step you hand the cast": you stay in ordinary dance mode, every key still
works, and the first move key you press takes you back off the routine without
a word about it.

If you are standing on a marker node when you join, you get that dancer's
part — stand on `lw_dance:mark_lead` in the theater and you are dancing the
lead's steps next to the lead. Otherwise you follow the steps aimed at the
whole cast (`role = "*"`).

## Writing a routine

Routine files live in **`games/luanti_web/routines/`** — in the game, not in
the mod, so a map can ship its dance next to the schematic it was
choreographed for. Each file returns a table (or a list of them) and is loaded
at startup. See `routines/README.md` for the field list; the short version:

```lua
return {
	id = "chorus_line_v1",
	loop = true,
	bpm = 120,
	length_beats = 32,
	dancers = {
		{role = "lead",  model = "person"},
		{role = "left",  model = "person"},
		{role = "right", model = "person"},
	},
	formation = {kind = "line", spacing = 2},
	steps = {
		{beat = 0,  role = "*",    move = "groove", facing = "audience"},
		{beat = 8,  role = "lead", move = "spin"},
		{beat = 16, role = "left", move = "wave"},
		{beat = 24, role = "*",    move = "bow"},
	},
}
```

### Time

Seconds (`t`) are the timebase that always works. A routine that names a `bpm`
may write `beat` instead, and then **both** are kept: the beat count is what
playback reads, which is what makes `/routine bpm` a real speed control rather
than a relabelling. A routine with no `bpm` still runs; it just cannot be
sped up.

`length` (or `length_beats`) is one pass. Without it the length is the last
step plus a bar, because a looping routine that snapped back the instant its
last step fired would never be seen finishing.

### Where dancers stand

In order of preference:

1. **Marker nodes.** `lw_dance:mark_lead` goes to the lead; `lw_dance:mark_1`
   … `lw_dance:mark_8` are handed to the rest of the cast in number order. The
   director scans 12 nodes around itself every time a routine starts, so marks
   moved in game take effect without a restart. A dancer's feet land on the
   bottom face of the mark's node.
2. **The routine's `formation`**, for whatever the marks do not cover:
   `line`, `wedge` or `circle`, with a `spacing`. Offsets are in the stage's
   own frame — along the front of the stage and away from the audience — so a
   formation never has to know which way north is.

Marks are nodes rather than coordinates in a Lua file on purpose: `/lw_schem
save` keeps node names and param2, so the choreography travels with the map.

### Facing

`facing` on a step is `"audience"` (the direction the stage points),
`"away"`, `"partner"` (the nearest other dancer), `"director"`, or a yaw in
degrees. A routine written for the theater says "face the seats" and plays
unchanged on a porch where the seats are east.

### Riding something

A dancer with `ride = "<entity name>"` is attached to a carrier that moves on
its own and is never positioned by the director again. It keeps playing its
clip the whole way: the carrier owns where the dancer is, the routine owns
what it is doing, and neither has to know about the other. `lw_dance:float` is
the raft the fruit garden's berry rides, with a `path` given relative to the
stage.

## Stages

A stage is registered next to the build it belongs to — `lw_world` registers
the theater's the same way it registers the theater screen:

```lua
lw_dance.register_stage({
	routine = "chorus_line_v1",
	pos = {x = 0, y = FLOOR, z = 57},     -- middle of the formation
	node = {x = 6, y = FLOOR, z = 58},    -- the director node that toggles it
	facing = {x = 0, y = 0, z = -1},      -- which way the audience is
})
```

`pos` and `node` are separate because nobody wants a lectern in the middle of
a chorus line. `/routine start <id> here` makes a throwaway stage where the
visitor is standing, facing back at them.

## Rigs

`model` on a dancer names a rig registered with `lw_dance.register_model`:

| Rig | What it is |
|---|---|
| `person` | The visitor's own mesh, skeleton and frame ranges |
| `ghost` | The same rig, tinted and part-transparent, with a glow |
| `scarecrow` | The same rig, straw-coloured and a little bigger |
| `berry` | The same rig, small and magenta; the one that rides |
| `mascot_melon` | A cube of garden wool, with **no skeleton at all** |

Recolouring one texture rather than shipping four meshes is a content-budget
decision (see `docs/` on the web pack): a ghost is a silhouette and a colour.

### Failing soft

The mascot is the interesting one. It has no bones, so the poses in
`moves.lua` cannot be put on it — and it dances anyway, because the director
reduces each pose to the body's own turn and bounce and applies that to the
whole entity. A rig with nothing to pose still keeps the beat and keeps its
place in the formation, which is what makes a routine readable rather than
half-empty. The same applies to a missing frame range: no `stand` range is not
an error, it just means the pose is doing all the work.

## Cost

The cap is **eight dancers** per routine (`lw_dance.MAX_DANCERS`). A bigger
cast still runs — the extras stay off stage and a warning is logged — because
a short-handed dance beats a stalled browser tab.

What keeps eight affordable:

* Poses go out ten times a second with `interpolation` set to one step, not
  once per server step, and the client draws the motion in between.
* Every bone key that would repeat the last value sent is dropped.
* Each dancer's keys are staggered across the interval, so eight of them never
  land on the same server step.
* With no player within 48 nodes the clock keeps running but nothing is sent
  at all, so an empty theater is free — and a visitor who walks back in finds
  the routine where it should be rather than restarted.

## Not done here

* **The snow mountain has no routine.** The cast would be recoloured people on
  an overlook, which is a worse demo than an empty overlook. It waits for a
  penguin mesh.
* No improvised choreography, no motion capture from the Tier B videos, and no
  judged contests. A routine is authored, and the file is the whole of it.
