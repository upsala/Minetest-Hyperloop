--[[

	Hyperloop Mod
	=============

	Copyright (C) 2017 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	History:
	see init.lua

]]--

-- Tube chain arrangement:
--   [0] = tube0 (single node)
--   [1] = tube1 (head node)
--   [2] = tube2 (link node)
--   [J] = junction
--
--   [0]  [1]-[1]  [1]-[2]-[1]  [J]-[1]-[2]-...-[2]-[1]-[J]


-- Scan all 8 neighbor positions for tube nodes.
-- Return:
--  0, nodes    - no node available
--  1, nodes    - one head/single node available
--  3, nodes    - two head nodes available
--  4, nodes    - one link node available
--  5, nodes    - invalid position
function hyperloop.scan_neighbours(pos)
	local nodes = {}
	local node, npos, idx
	local res = 0
	for _,dir in ipairs(hyperloop.NeighborPos) do
		npos = vector.add(pos, dir)
		node = minetest.get_node(npos)
		if string.find(node.name, "hyperloop:tube") then
			node.pos = npos
			table.insert(nodes, node)
			idx = string.byte(node.name, -1) - 48
			if idx == 0 then        -- single node?
				idx = 1
			elseif idx == 2 then    -- link node?
				return 4, nodes
			end
			res = res * 2 + idx
		end
	end
	if res > 3 then
		res = 5
	end
	return res, nodes
end

local function get_slope_counter(pos)
	if pos ~= nil then
		local slope_cnt = minetest.get_meta(pos):get_int("slope_cnt")
		if slope_cnt ~= nil then
			return slope_cnt
		end
	end
	return 1
end


-- update head tube meta data
-- param pos: position as string
-- param peer_pos: position as string
function hyperloop.update_head_node(pos, peer_pos)
	if hyperloop.debugging then
		print("update head node(pos="..pos.." peer_pos="..peer_pos..")")
	end
	pos = minetest.string_to_pos(pos)
	if pos ~= nil then
		local meta = minetest.get_meta(pos)
		meta:set_string("peer", peer_pos)
		hyperloop.update_junction(pos)
	end
end


-- Degrade one node.
-- Needed when a new node is placed nearby.
function hyperloop.degrade_tupe_node(node)
	if node.name == "hyperloop:tube0" then
		node.name = "hyperloop:tube1"
	elseif node.name == "hyperloop:tube1" then
		node.name = "hyperloop:tube2"
		node.diggable = false
		minetest.get_meta(node.pos):from_table(nil)
	else
		return
	end
	minetest.swap_node(node.pos, node)
end

-- Remove the given node
function hyperloop.remove_node(pos, node)
	-- can't call "remove_node(pos)" because subsequently "on_destruct" will be called
	node.name = "air"
	node.diggable = true
	minetest.swap_node(pos, node)
end


-- Upgrade one node.
-- Needed when a tube node is digged.
function hyperloop.upgrade_node(digged_node_pos)
	local res, nodes = hyperloop.scan_neighbours(digged_node_pos)
	if res == 1 or res == 4 then
		local new_head_node = nodes[1]
		-- copy peer pos first
		local peer_pos = minetest.get_meta(digged_node_pos):get_string("peer")
		local slope_cnt = get_slope_counter(digged_node_pos)
		local pos = minetest.pos_to_string(new_head_node.pos)
		hyperloop.update_head_node(pos, peer_pos)
		hyperloop.update_head_node(peer_pos, pos)
		-- upgrade
		new_head_node.diggable = true
		if new_head_node.name == "hyperloop:tube2" then          -- 2 connections?
			new_head_node.name = "hyperloop:tube1"
		elseif new_head_node.name == "hyperloop:tube1" then      -- 1 connection?
			new_head_node.name = "hyperloop:tube0"
		end
		-- slope counter correction
		if digged_node_pos.y ~= new_head_node.pos.y then
			slope_cnt = 0
		else
			slope_cnt = math.min(slope_cnt + 1, hyperloop.min_slope_counter)
		end
		minetest.get_meta(new_head_node.pos):set_int("slope_cnt", slope_cnt)
		minetest.get_meta(new_head_node.pos):set_string("infotext", pos.." : "..slope_cnt)
		minetest.swap_node(new_head_node.pos, new_head_node)
	end
end

-- Place a node without neighbours
local function single_node(node)
	local meta = minetest.get_meta(node.pos)
	local str_pos = minetest.pos_to_string(node.pos)
	meta:set_string("peer", str_pos)
	meta:set_int("slope_cnt", hyperloop.min_slope_counter)
	minetest.get_meta(node.pos):set_string("infotext", str_pos.." : "..hyperloop.min_slope_counter)
	-- upgrade self to single node
	node.name = "hyperloop:tube0"
	minetest.swap_node(node.pos, node)
	return true
end

-- Place a node with one neighbor
local function head_node(node, old_head)
	-- determine peer pos
	local peer_pos = minetest.get_meta(old_head.pos):get_string("peer")
	local slope_cnt = get_slope_counter(old_head.pos)
	-- both nodes on the same level OR slope OK?
	if node.pos.y == old_head.pos.y or slope_cnt == 0 then
		-- update self
		local str_pos = minetest.pos_to_string(node.pos)
		hyperloop.update_head_node(str_pos, peer_pos)
		-- update peer
		hyperloop.update_head_node(peer_pos, str_pos)
		-- slope correction
		if node.pos.y ~= old_head.pos.y then
			slope_cnt = hyperloop.min_slope_counter
		else
			slope_cnt = math.max(slope_cnt - 1, 0)
		end
		-- upgrade self
		minetest.get_meta(node.pos):set_int("slope_cnt", slope_cnt)
		minetest.get_meta(node.pos):set_string("infotext", str_pos.." : "..slope_cnt)
		node.name = "hyperloop:tube1"
		minetest.swap_node(node.pos, node)
		-- degrade old head
		hyperloop.degrade_tupe_node(old_head)
		return true
	end
	return false
end

local function link_node(node, node1, node2)
	-- both nodes on the same level?
	if node1.pos.y == node2.pos.y then
		-- determine the meta data from both head nodes
		local pos1 = minetest.get_meta(node1.pos):get_string("peer")
		local pos2 = minetest.get_meta(node2.pos):get_string("peer")
		-- exchange position data
		hyperloop.update_head_node(pos1, pos2)
		hyperloop.update_head_node(pos2, pos1)
		-- set to tube2
		node.name = "hyperloop:tube2"
		node.diggable = true
		minetest.swap_node(node.pos, node)
		-- degrade both nodes
		hyperloop.degrade_tupe_node(node1)
		hyperloop.degrade_tupe_node(node2)
		return true
	end
	return false
end

-- called when a new node is placed
local function node_placed(pos, itemstack)
	local res, nodes = hyperloop.scan_neighbours(pos)
	local node = minetest.get_node(pos)
	local placed = false
	node.pos = pos
	if res == 0 then            -- no neighbor available?
		placed = single_node(node)
	elseif res == 1 then        -- one neighbor available?
		placed = head_node(node, nodes[1])
	elseif res == 3 then        -- two neighbours available?
		placed = link_node(node, nodes[1], nodes[2])
	end
	if not placed then
		hyperloop.remove_node(pos, node)
		return itemstack
	end
	hyperloop.update_junction(pos)
end

-- simple tube without logic or "memory"
minetest.register_node("hyperloop:tube2", {
	description = "Hyperloop Tube",
	tiles = {
		-- up, down, right, left, back, front
		"hyperloop_tube_locked.png^[transformR90]",
		"hyperloop_tube_locked.png^[transformR90]",
		"hyperloop_tube_locked.png",
		"hyperloop_tube_locked.png",
		"hyperloop_tube_locked.png",
		"hyperloop_tube_locked.png",
	},

	diggable = false,
	paramtype2 = "facedir",
	groups = {cracky=1, not_in_creative_inventory=1},
	is_ground_content = false,
	sounds = default.node_sound_metal_defaults(),
})

-- single-node and head-node with meta data about the peer head node position
for idx = 0,1 do
	minetest.register_node("hyperloop:tube"..idx, {
		description = "Hyperloop Tube",
		inventory_image = "hyperloop_tube_inventory.png",
		drawtype = "nodebox",
		tiles = {
			-- up, down, right, left, back, front
			"hyperloop_tube_locked.png^[transformR90]",
			"hyperloop_tube_locked.png^[transformR90]",
			'hyperloop_tube_closed.png',
			'hyperloop_tube_closed.png',
			'hyperloop_tube_open.png',
			'hyperloop_tube_open.png',
		},

		after_place_node = function(pos, placer, itemstack, pointed_thing)
			return node_placed(pos, itemstack)
		end,

		on_destruct = function(pos)
			hyperloop.upgrade_node(pos)
			hyperloop.update_junction(pos)
		end,

		paramtype2 = "facedir",
		groups = {cracky=2, not_in_creative_inventory=idx},
		is_ground_content = false,
		drop = "hyperloop:tube0",
		sounds = default.node_sound_metal_defaults(),
	})
end


