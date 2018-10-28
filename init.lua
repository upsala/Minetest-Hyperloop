--[[

	Hyperloop Mod
	=============

	v2.00 by JoSt

	Copyright (C) 2017,2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	History:
	2017-06-18  v0.01  First version
	2017-07-06  v0.02  Version on GitHub
	2017-07-07  v0.03  Recipes added, settingstypes added
	2017-07-08  v0.04  Door removal issue fixed
	2017-07-16  v0.05  Doors can be opened manually
	2017-07-24  v0.06  Tubes with limited slope, elevator and deco blocks added
	2017-07-28  v0.07  Slope removed, Station auto-builder added
	2017-07-30  v0.08  Signs added, tube robot added, crowbar added
	2017-07-31  v0.09  Some bug fixes on the Bocking Machine
	2017-08-01  v0.10  Elevator now with sound and travel animation plus minor bug fixes
	2017-08-06  v0.11  Crowbar now allows repairing of illegally detroyed tubes
	2018-03-27  v0.12  Some minor improvements with player position, arrival time,
	                   Wifi node improvements, Podshell cheating bugfix,
	                   forceload_block removed.
	2018-04-13  v0.13  Potential "Never Store ObjectRefs" bug fixed
	2018-10-27  v1.00  Release
	2018-10-27  v2.00  Switched to lubelib2 for shafts and tubes

]]--


hyperloop = {
	data = {
		version = 2,            -- compatibility version
		tAllStations = {},      -- tube networks
		tAllElevators = {},     -- elevators
		booking = {},           -- open booking nodes
		change_counter = 0,     -- used for booking machine updates
	}
}

-- Configuration settings
hyperloop.wifi_enabled = minetest.setting_get("hyperloop_wifi_enabled") or false
hyperloop.free_tube_placement_enabled = minetest.setting_get("hyperloop_free_tube_placement_enabled") or false

dofile(minetest.get_modpath("hyperloop") .. "/utils.lua")
dofile(minetest.get_modpath("hyperloop") .. "/tube.lua")
dofile(minetest.get_modpath("hyperloop") .. "/booking.lua")
dofile(minetest.get_modpath("hyperloop") .. "/junction.lua")
dofile(minetest.get_modpath("hyperloop") .. "/station.lua")
dofile(minetest.get_modpath("hyperloop") .. "/elevator.lua")
if hyperloop.wifi_enabled then
	dofile(minetest.get_modpath("hyperloop") .. "/wifi.lua")
end
dofile(minetest.get_modpath("hyperloop") .. "/map.lua")
dofile(minetest.get_modpath("hyperloop") .. "/door.lua")
dofile(minetest.get_modpath("hyperloop") .. "/seat.lua")
dofile(minetest.get_modpath("hyperloop") .. "/robot.lua")
dofile(minetest.get_modpath("hyperloop") .. "/lcd.lua")
dofile(minetest.get_modpath("hyperloop") .. "/waypoint.lua")
dofile(minetest.get_modpath("hyperloop") .. "/deco.lua")
dofile(minetest.get_modpath("hyperloop") .. "/tubecrowbar.lua")
dofile(minetest.get_modpath("hyperloop") .. "/recipes.lua")

-- Migration from v1 to v2
--dofile(minetest.get_modpath("hyperloop") .. "/migrate.lua")

--
-- Data base storage
--
local storage = minetest.get_mod_storage()
hyperloop.data = minetest.deserialize(storage:get_string("data")) or hyperloop.data

local function update_mod_storage()
	minetest.log("action", "[Hyperloop] Store data...")
	storage:set_string("data", minetest.serialize(hyperloop.data))
	-- store data each hour
	minetest.after(60*60, update_mod_storage)
	minetest.log("action", "[Hyperloop] Data stored")
end

minetest.register_on_shutdown(function()
	update_mod_storage()
end)

-- store data after one hour
minetest.after(60*60, update_mod_storage)

print ("[MOD] Hyperloop loaded")
