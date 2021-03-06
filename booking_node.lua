--[[

	Hyperloop Mod
	=============

	Copyright (C) 2017-2019 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	Booking/ticket machine
]]--

-- for lazy programmers
local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P = minetest.string_to_pos
local M = minetest.get_meta

-- Load support for intllib.
local MP = minetest.get_modpath("hyperloop")
local I, NS = dofile(MP.."/intllib.lua")

-- Used to store the Station list for each booking machine: 
--    tStationList[S(pos)] = {pos1, pos2, ...}
local tStationList = {}

local Stations = hyperloop.Stations


-- Form spec for the station list
local function generate_string(sortedList)
	local tRes = {"size[12,10]"..
	default.gui_bg..
	default.gui_bg_img..
	default.gui_slots..
	"label[4,0; "..I("Select your destination").."]"}
	tRes[2] = "label[1,0.6;"..I("Destination").."]label[5,0.6;"..
			I("Distance").."]label[7,0.6;"..I("Local Info").."]"
	for idx,tDest in ipairs(sortedList) do
		if idx >= 12 then
			break
		end
		local ypos = 0.5 + idx*0.8
		local ypos2 = ypos - 0.2
		local name = tDest.name or "<unknown>"
		local distance = tDest.distance or 0
		local info = tDest.booking_info or ""
		
		tRes[#tRes+1] = "button_exit[0,"..ypos2..";1,1;button;"..idx.."]"
		tRes[#tRes+1] = "label[1,"..ypos..";"..string.sub(name,1,28).."]"
		tRes[#tRes+1] = "label[5,"..ypos..";"..distance.." m]"
		tRes[#tRes+1] = "label[6.6,"..ypos..";"..info.."]"
	end
	if #sortedList == 0 then
		tRes[#tRes+1] = "button_exit[4,4;3,1;button;Update]"
	end
	return table.concat(tRes)
end

local function store_station_list(pos, sortedList)
	local tbl = {}
	for idx,item in ipairs(sortedList) do
		tbl[#tbl+1] = item.pos
	end
	tStationList[S(pos)] = tbl
end

local function remove_junctions(sortedList)
	local tbl = {}
	for idx,item in ipairs(sortedList) do
		if not item.junction and item.booking_pos then
			tbl[#tbl+1] = item
		end
	end
	return tbl
end

local function station_list_as_string(pos)
	-- Generate a distance sorted list of all connected stations
	local sortedList = Stations:station_list(pos, pos, "dist")
	-- Delete the own station from list
	table.remove(sortedList, 1)
	-- remove all junctions from the list
	sortedList = remove_junctions(sortedList)
	-- store the list for later use
	store_station_list(pos, sortedList)
	-- Generate the formspec string
	return generate_string(sortedList)
end


local function naming_formspec(pos)
	local meta = minetest.get_meta(pos)
	local formspec = "size[6,4]"..
	default.gui_bg..
	default.gui_bg_img..
	default.gui_slots..
	"label[0,0;"..I("Please enter the station name to\nwhich this booking machine belongs.").."]" ..
	"field[0.5,1.5;5,1;name;"..I("Station name")..";MyTown]" ..
	"field[0.5,2.7;5,1;info;"..I("Additional station information")..";]" ..
	"button_exit[2,3.6;2,1;exit;Save]"
	meta:set_string("formspec", formspec)
	meta:set_int("change_counter", 0)
end


local function booking_machine_update(pos)
	local meta = M(pos)
	local sStationPos = meta:get_string("sStationPos")
	if sStationPos ~= "" then
		local station_pos = P(sStationPos)
		local counter = meta:get_int("change_counter") or 0
		local changed, newcounter = Stations:changed(counter)
		if changed then
			meta:set_string("formspec", station_list_as_string(station_pos))
			meta:set_int("change_counter", newcounter)
		end
		if not tStationList[sStationPos] then
			local sortedList = Stations:station_list(station_pos, station_pos, "dist")
			-- Delete the own station from list
			table.remove(sortedList, 1)
			-- remove all junctions from the list
			sortedList = remove_junctions(sortedList)
			-- store the list for later use
			store_station_list(station_pos, sortedList)
		end
	end
end


local function on_receive_fields(pos, formname, fields, player)
	booking_machine_update(pos)
	-- station name entered?
	if fields.name ~= nil then
		local station_name = string.trim(fields.name)
		if station_name == "" then
			return
		end
		local stationPos = Stations:get_next_station(pos)
		if stationPos then
			if Stations:get(stationPos).booking_pos then
				hyperloop.chat(player, I("Station has already a booking machine!"))
				return
			end
			-- store meta and generate station formspec
			Stations:update(stationPos, {
					name = station_name,
					booking_pos = pos,
					booking_info = string.trim(fields.info),
			})
			
			local meta = M(pos)
			meta:set_string("sStationPos", S(stationPos))
			meta:set_string("infotext", "Station: "..station_name)
			meta:set_string("formspec", station_list_as_string(stationPos))
		else
			hyperloop.chat(player, I("Invalid station name!"))
		end
	elseif fields.button ~= nil then -- destination selected?
		local idx = tonumber(fields.button)
		if idx then
			local tStation, src_pos = hyperloop.get_base_station(pos)
			local dest_pos = tStationList[S(src_pos)] and tStationList[S(src_pos)][idx]
			if dest_pos and tStation then
				-- place booking if not already blocked
				if hyperloop.reserve(src_pos, dest_pos, player) then
					hyperloop.set_arrival(src_pos, dest_pos)
					-- open the pod door
					hyperloop.open_pod_door(tStation)
				end
			else
				-- data is corrupt, try an update
				M(pos):set_int("change_counter", 0)
			end
		end
	end
end
	
local function on_destruct(pos)
	local sStationPos = M(pos):get_string("sStationPos")
	if sStationPos ~= "" then
		Stations:update(P(sStationPos), {
			booking_pos = "nil",
			booking_info = "nil",
			name = "Station",
		})
	end
end

-- wap from wall to ground 
local function swap_node(pos, placer)
	pos.y = pos.y - 1
	if minetest.get_node_or_nil(pos).name ~= "air" then
		local node = minetest.get_node(pos)
		node.name = "hyperloop:booking_ground"
		node.param2 = hyperloop.get_facedir(placer)
		pos.y = pos.y + 1
		minetest.swap_node(pos, node)
	else
		pos.y = pos.y + 1
	end
end

-- wall mounted booking machine
minetest.register_node("hyperloop:booking", {
	description = I("Hyperloop Booking Machine"),
	tiles = {
		-- up, down, right, left, back, front
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking_front.png",
	},
	
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{ -8/16, -8/16, 2/16,  8/16,  8/16, 8/16},
		},
	},
	
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		naming_formspec(pos)
		swap_node(pos, placer)
	end,

	on_rotate = screwdriver.disallow,	
	on_receive_fields = on_receive_fields,
	on_destruct = on_destruct,

	paramtype = 'light',
	light_source = 2,
	paramtype2 = "facedir",
	groups = {cracky=2},
	is_ground_content = false,
})

-- ground mounted booking machine
minetest.register_node("hyperloop:booking_ground", {
	description = I("Hyperloop Booking Machine"),
	tiles = {
		-- up, down, right, left, back, front
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking.png",
		"hyperloop_booking_front.png",
	},
	
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{ -8/16, -8/16, -3/16,  8/16,  8/16, 3/16},
		},
	},
	
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		naming_formspec(pos)
	end,

	on_receive_fields = on_receive_fields,
	on_destruct = on_destruct,
	
	on_rotate = screwdriver.disallow,	
	drop = "hyperloop:booking",
	light_source = 2,
	paramtype = 'light',
	paramtype2 = "facedir",
	groups = {cracky=2, not_in_creative_inventory=1},
	is_ground_content = false,
})


minetest.register_lbm({
	label = "[Hyperloop] Booking machine update",
	name = "hyperloop:update",
	nodenames = {"hyperloop:booking", "hyperloop:booking_ground"},
	run_at_every_load = true,
	action = booking_machine_update
})
