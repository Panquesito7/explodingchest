exploding_chest = {}

minetest.register_on_mods_loaded(function()
	if not tnt.boom then
		error("Could not find tnt.boom function.")
	elseif (explodingchest_config.blast_type == "entity" or explodingchest_config.trap_blast_type == "entity") 
		and not tnt.create_entity then
		error("Could not find tnt.create_entity function. Make sure tnt_revamped is enabled, or change one of the blast types from being set to entity.")
	end
	for k, v in pairs(minetest.registered_nodes) do
		if v.groups.volatile then
			local old_on_rightclick = v.on_rightclick
			minetest.override_item(k, {
				on_blast = function(pos)
					return exploding_chest.drop_and_blowup(pos, false, false, nil, explodingchest_config.blast_type)
				end,
				on_blast_break = function(pos)
					return exploding_chest.drop_and_blowup(pos, false, false, nil, explodingchest_config.blast_type)
				end,
				on_ignite = function(pos)
					exploding_chest.drop_and_blowup(pos, true, true, nil, explodingchest_config.blast_type)
				end,
				mesecons = {effector =
					{action_on =
						function(pos)
							exploding_chest.drop_and_blowup(pos, true, true, nil, explodingchest_config.blast_type)
						end
					}
				},
				on_burn = function(pos)
					exploding_chest.drop_and_blowup(pos, false, true, nil, explodingchest_config.blast_type)
				end,
				on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
					local meta = minetest.get_meta(pos)
					local inv = meta:get_inventory()
					
					for q, r in pairs(inv:get_lists()) do
						for i = 1, inv:get_size(q) do
							local stack = inv:get_stack(q, i)
							if stack:get_count() > 0 and stack:get_name() == "explodingchest:trap" then
								if exploding_chest.drop_and_blowup(pos, true, true, meta, explodingchest_config.trap_blast_type) then
									return
								elseif old_on_rightclick then
									return old_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
								end
							end
						end
					end

					if old_on_rightclick then
						return old_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
					end
				end,
			})
		end
	end
end)

--
-- Optimized helper to put all items in an inventory into a drops list
--

local function get_inventory_drops(inv, inventory, drops)
	local n = #drops
	for i = 1, inv:get_size(inventory) do
		local stack = inv:get_stack(inventory, i)
		if stack:get_count() > 0 then
			drops[n+1] = stack:to_table()
			n = n + 1
		end
	end
end

local function eject_drops(drops, pos)
	local drop_pos = vector.new(pos)
	for _, item in pairs(drops) do
		local count = item.count or 1
		local dropitem = ItemStack(item.name)
		dropitem:set_count(count)
		local obj = minetest.add_item(drop_pos, dropitem)
		if obj then
			obj:get_luaentity().collect = true
			obj:set_acceleration({x = 0, y = -10, z = 0})
			obj:set_velocity({x = math.random(-3, 3),
					y = math.random(0, 10),
					z = math.random(-3, 3)})
		end
	end
end

local function process(pos, removeifvolatile, meta)
	local node = minetest.get_node_or_nil(pos)

	if not node then
		return
	end

	if not meta then
		meta = minetest.get_meta(pos)
	end

	local inv = meta:get_inventory()
	
	if not inv then
		return
	end

	local olddrops = {}
	local drops = {}
	local explodesize = 0
	local strength = 0
	local blowup = false
	local riv = false

	if not removeifvolatile then
		riv = true
	end

	local ref_items = minetest.registered_items
	local max = explodingchest_config.explosion_max
	local radius_comput = explodingchest_config.radius_comput
	local reduce = explodingchest_config.reduce

	for q, r in pairs(inv:get_lists()) do
		get_inventory_drops(inv, q, olddrops)
	end

	if radius_comput == "reduce" then
		local index
		local trap = false
		-- init explosion size
		for k, v in pairs(olddrops) do
			local item = ref_items[v.name]

			if item and item.groups.explosive then
				if explodesize < item.groups.explosive then
					explodesize = item.groups.explosive
					index = k
				end
			end
			if item and item.groups.strength then
				if strength < item.groups.strength then
					strength = item.groups.strength
					index = k
				end
			end
			if v.name == "explodingchest:trap" and not trap then
				olddrops[k].count = 0
				trap = true
			end
		end
		if index then
			olddrops[index].count = olddrops[index].count - 1
		end
	end
	
	for k, v in pairs(olddrops) do

		if explodesize >= max then
			break
		end

		local item = ref_items[v.name]

		if item and item.groups.explosive then
			if radius_comput == "multiply" then
				for i = 1, v.count do
					explodesize = explodesize + item.groups.explosive
					if item.groups.strength then
						strength = strength + item.groups.strength
					end
					if explodesize >= max then
						v.count = v.count - i
						explodesize = max
						break
					end
				end

				if explodesize < max then
					v.count = 0
				end
			else
				for i = 1, v.count do
					explodesize = explodesize + item.groups.explosive / reduce
					if item.groups.strength then
						strength = strength + item.groups.strength / reduce
					end
					if explodesize >= max then
						v.count = v.count - i
						explodesize = max
						break
					end
				end

				if explodesize < max then
					v.count = 0
				end
			end
		end

		if v.count >= 1 then
			drops[#drops + 1] = v
		end
	end

	if explodesize >= 1.0 then
		blowup = true
		riv = true
	end

	drops[#drops + 1] = node.name
	return node, olddrops, drops, explodesize, strength, blowup, riv
end

-- functions
function exploding_chest.drop_and_blowup(pos, removeifvolatile, eject, meta, blast_type, instant)
	if blast_type == "instant" or instant then
		local node, olddrops, drops, explodesize, strength, blowup, riv = process(pos, removeifvolatile, meta)
		if blowup == true then
			minetest.remove_node(pos)
			tnt.boom(pos, {radius = explodesize, damage_radius = explodesize * 2})
		elseif riv == true then
			minetest.remove_node(pos)
		end

		if eject and (blowup or riv) then
			eject_drops(drops, pos)
			return {}
		elseif not blowup and not riv then
			return
		end

		return drops
	elseif blast_type == "timer" then
		local timer = explodingchest_config.timer
		if timer < 1 then
			local node, olddrops, drops, explodesize, strength, blowup, riv = process(pos, removeifvolatile, meta)
			timer = explodesize
		end
		minetest.after(timer, exploding_chest.drop_and_blowup, pos, removeifvolatile, true, nil, "instant", true)
	elseif blast_type == "entity" then
		local node, olddrops, drops, explodesize, strength, blowup, riv = process(pos, removeifvolatile, meta)
		
		if blowup == true then
			local timer = explodingchest_config.timer
			if timer < 1 then
				timer = explodesize
			end
			local def = {radius = explodesize,
				time = timer,
				jump = 3,
				strength = strength}
			local obj = tnt.create_entity(pos, nil, nil, 3, def)
			obj:set_properties({textures = {node.name}})
			
			local ent = obj:get_luaentity()
			ent.time = timer
			ent.drops = drops
			drops = {}
		elseif riv then
			minetest.remove_node(pos)
		end

		return drops
	end
end
