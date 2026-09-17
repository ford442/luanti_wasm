<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Dance mode

`lw_dance` gives the visitor a body and six things to do with it. It is a
**mode**, not a set of always-live emote keys: until you opt in, nothing in
this mod reads a key, so building the plaza never sets off a dance.

## The binds

Toggle dance mode by **holding sneak and zoom together** (default `Shift`+`Z`)
for about a third of a second, or with `/dance`. While dance mode is on, the
number keys are the moves:

| Key | Move | Chat |
|-----|------|------|
| `1` | Groove — the idle bounce | `/dance groove` |
| `2` | Spin — body turns, arms out | `/dance spin` |
| `3` | Wave — both arms up, hands swaying | `/dance wave` |
| `4` | Stomp — alternating kicks | `/dance stomp` |
| `5` | The Robot — held poses, stepwise | `/dance robot` |
| `6` | Bow — a flourish, then back to the groove | `/dance bow` |
| `7` | Random move from the pool | `/dance random` |
| `8` | Leave dance mode | `/dance stop` |

`/dance help` prints the same list in game. `/dance pad` opens a tap-friendly
pad with the same eight buttons.

Nothing here steals a bind: chat, `i`, `Esc`, `F7` and the whole tool set
behave exactly as they do outside dance mode.

### Why number keys and not `B`, `R` and `0`

Luanti has no server-side "this key went down" event — a mod can read
`get_player_control()`, which covers movement, jump, sneak, aux1, dig, place
and zoom, and nothing else. The letter and digit keys the issue proposed
(`B` to toggle, `1`–`6` for moves, `R` for random, `0` to exit) never reach
the server as keys.

What *does* reach the server is **hotbar selection**, and the number keys are
how a hotbar slot gets selected. So in dance mode slots 1–8 are the dance
keys. This costs the visitor nothing: entering dance mode remembers the slot
you were on and the exact item you were wielding, and gives both back the
moment you leave. The highlighted slot is always the move that is playing,
which is also why entering dance mode starts slot 1's move rather than an
empty stance — with slot 1 already highlighted, pressing `1` would be a dead
key.

`sneak`+`zoom` is the toggle gesture for the same reason: they are two of the
keys a mod can actually see, and the pair is not a combination the showcase
uses for anything else. It fires once per hold and needs both keys released
before it toggles back, so leaning on them does not flicker.

In the browser this matters twice over: both the gesture and the number keys
are ordinary key events the canvas already owns, so the toggle never drops
pointer lock. Only `/dance pad` does, because a formspec must be clickable —
touch clients, which have no number keys, are given the pad automatically
when they enter dance mode.

## Walking, jumping and sitting

Walking **layers**. The legs take the walk cycle and the move keeps running on
the upper body, so you can groove across the plaza. Jumping and flying change
nothing. Sitting down in the theater ends dance mode, because `lw_theater`
drives the same skeleton into its sit pose and two owners of one skeleton
would fight.

One-shot moves — anything with a `duration` — hand back to whatever their
`next` field names when they run out. The bow is the one in the shipped set:
it runs for two seconds, refuses to be cut short, and returns to the groove.

## Watching yourself

The dance is on your *character*, and in first person you are inside it.
Press `F7` for third person to watch the moves, or watch someone else dance:
every move is server-side, so observers see the same dance the dancer does.
There is no browser-only path here.

## The stage hint

Standing on any node in the **`lw_dance_stage`** group suggests dance mode in
chat, at most once every 90 seconds. `lw_dance:stage` — a violet dance floor
in the palette — is in that group. The hook is the group, not a node name, so
a theater stage node can join it with one line and light up here.

## How the moves are built

The character the showcase ships (`lw_dance_character.b3d`, the classic
Minetest Sam skeleton) has five animation ranges: stand, sit, lay, walk and
mine. None of them is a dance. So each move is a **base frame range for the
legs plus a procedural pose on the skeleton**, which is the fallback path the
issue asked for — and it turned out to be the better v1:

* Bone overrides are server-side, so a move replicates to every observer with
  no extra work.
* A pose sits *on top of* whatever the legs are doing, which is what makes
  walking layer instead of cancel.
* No new art. Six moves, zero new textures, one model copied from devtest.

Poses are sent as sparse keyframes — ten a second, each with
`interpolation` set to exactly one step — so the client draws the smooth
motion and the server stays quiet. Keys that would repeat a bone's last value
are dropped, which is why the Robot, which holds each pose for three ticks,
costs about eight messages a second.

### Adding a move

```lua
lw_dance.register_move("shimmy", {
	label = "Shimmy",
	description = "Shimmy — shoulders only",
	anim = "stand",          -- frame-range key in the model's `animations`
	loop = true,
	duration = nil,          -- seconds; nil means "until told otherwise"
	next = nil,              -- move to fall into when `duration` runs out
	interruptible = true,
	snap = false,            -- true sends keys with no interpolation
	pose = function(t)       -- degrees and model units; called every 0.1s
		return {
			Body = {rot = {y = math.sin(t * 6) * 18}},
			Arm_Right = {rot = {z = -30}},
			Arm_Left = {rot = {z = 30}},
		}
	end,
})

lw_dance.bind_slot(3, "shimmy")   -- optional: put it on a number key
```

Bones available on the shipped character: `Head`, `Body`, `Arm_Left`,
`Arm_Right`, `Leg_Left`, `Leg_Right`.

Overrides are relative, so they compose with each bone's rest rotation and
act in the bone's own frame. On this skeleton the limbs and the body carry a
180-degree rest rotation, which flips two of their three axes against model
space: a move that reads as leaning back where it should lean forward just
needs that one axis negated. The rest transforms are listed at the top of
`moves.lua`. Paired limbs are always given equal and opposite angles, which
stays symmetric whichever way the axis points.

### Named glTF tracks (5.17+)

A move may also name a real animation track:

```lua
lw_dance.register_move("groove", {..., track = "dance_groove", priority = 1})
```

The `track` field is used **only** when the registered model declares
`tracks`, because `.b3d` and `.x` meshes have a single unnamed track. Give a
multi-track glTF character a model entry with

```lua
tracks = {idle = "idle", walk = "walk", dance_groove = "dance_groove", ...},
```

and the same moves play as authored clips through `play_animation`, with the
legs keeping their own track underneath at a lower priority — the arms wave
while the legs walk. The `pose` functions stay as the fallback for meshes
without those tracks. Every move in the shipped set already carries its
`track` name, so a future character is a model-table entry and nothing else.

## The player mesh

This mod is also where the showcase player *gets* a mesh. The engine default
for a player is an upright sprite, which has no skeleton and no animation
tracks, so `set_animation` and `set_bone_override` are silent no-ops on it.
`lw_theater` was already driving the `character.b3d` frame ranges (stand
`0..79`, sit `81..160`) on the assumption that a mesh was there, so shipping
one fixes the theater seats as well as enabling the dances.

Eye height is deliberately left at the engine default: the character is 1.77
nodes tall, the default 1.625 already lands in the head, and the theater's
seated camera offsets are calibrated against that number.

The model and its texture are byte-identical copies of
`games/devtest/mods/testentities/models/testentities_sam.{b3d,png}`, CC BY-SA
3.0; see `mods/lw_dance/models/LICENSE.txt`.
