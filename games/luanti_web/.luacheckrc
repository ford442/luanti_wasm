unused_args = false
allow_defined_top = true
max_line_length = false

ignore = {
	"131", -- Unused global variable
	"211", -- Unused local variable
	"212", -- Unused argument
	"431", -- Shadowing an upvalue
	"432", -- Shadowing an upvalue argument
}

read_globals = {
	"ItemStack",
	"DIR_DELIM",
	"dump", "dump2",
	"vector",
	"VoxelArea",
	"VoxelManip",
	"PseudoRandom",
	"PcgRandom",

	string = {fields = {"split", "trim"}},
	table  = {fields = {"copy", "indexof", "insert_all", "key_value_swap"}},
	math   = {fields = {"round"}},
}

globals = {
	"core",
	-- One global table per mod, the usual Luanti convention.
	"lw_core",
	"lw_dance",
	"lw_maps",
	"lw_nodes",
	"lw_theater",
	"lw_tools",
	"lw_world",
}
