-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 The Luanti Contributors

-- The cabaret club's songs: the slot. lw_amps/init.lua loads this file, so
-- adding a song is a pair of files in this folder and one line below. See
-- README.md in this folder for how to cut the pair and measure its length.
--
-- Every song added here is:
--
-- * played by the cabaret's cabs (lw_maps' `cabaret` map plays the first one
--   when someone walks in, and punching either cab plays it too);
-- * danced to by Rubella and Lillith (routines/cabaret_revue.lua reads this
--   playlist, so it needs no edit);
-- * not join-time media: the pair lives here, not in ../sounds/, and is sent
--   only to visitors who come within earshot of the cabaret's stage.
--
-- The files for song <name> are, in this folder:
--
--   lw_amps_<name>_l.ogg   the original left channel  -> audience-left cab
--   lw_amps_<name>_r.ogg   the original right channel -> audience-right cab
--
-- A line whose files are not both here is skipped with a warning in the log,
-- so the stage stays quiet rather than playing silence.

local function cabaret(name, def)
	def.media_dir = "cabaret"
	def.playlist = "cabaret"
	def.artist = def.artist or "Lace Waterfall"
	return lw_amps.register_song(name, def)
end

-- Add one line per song, in the order the cabaret should play them. `length`
-- is the duration of the files in seconds, measured with ffprobe (both files
-- of a pair must be the same length); `bpm` is the song's tempo.
--
-- cabaret("cabaret_example", {title = "Example", length = 180.0, bpm = 120})
