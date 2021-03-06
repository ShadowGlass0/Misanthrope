require 'stdlib/event/event'

Harpa = {}
Harpa.Logger = Logger.new("Misanthrope", "harpa", DEBUG_MODE)

function Harpa.migrate(old_global)
    for _, field_name in pairs({"harpa_list", "idle_harpa_list", "unpowered_harpa_list", "biter_ignore_list", "harpa_overlays"}) do
        global[field_name] = old_global[field_name]
    end
end

function Harpa.setup()
    for _, field_name in pairs({"harpa_list", "idle_harpa_list", "unpowered_harpa_list", "biter_ignore_list", "harpa_overlays", "micro_harpa_players", "idle_micro_harpa_players"}) do
        if not global[field_name] then
            global[field_name] = {}
        end
    end
end

Event.register(defines.events.on_tick, function(event)
    Event.remove(defines.events.on_tick, event._handler)
    Harpa.setup()
end)

function Harpa.register(entity, player_idx)
    if Harpa.is_powered(entity, nil) then
        if player_idx then
            Harpa.create_overlay(entity, player_idx)
        end
        table.insert(global.harpa_list, entity)
    else
        table.insert(global.unpowered_harpa_list, entity)
    end
end

function Harpa.update_power_grid(position, range, ignore_entity)
    local range_squared = range * range

    -- check inactive emitters to see if they gained power
    for i = #global.unpowered_harpa_list, 1, -1 do
        local harpa = global.unpowered_harpa_list[i]
        if harpa.valid then
            local harpa_pos = harpa.position
            local dist_squared = (position.x - harpa_pos.x) * (position.x - harpa_pos.x) + (position.y - harpa_pos.y) * (position.y - harpa_pos.y)
            if range_squared > dist_squared then
                if Harpa.is_powered(harpa, ignore_entity) then
                    table.remove(global.unpowered_harpa_list, i)
                    table.insert(global.harpa_list, harpa)
                end
            end
        else
            table.remove(global.unpowered_harpa_list, i)
        end
    end

    -- check active emitters to verify they still have power
    for i = #global.harpa_list, 1, -1 do
        local harpa = global.harpa_list[i]
        if harpa.valid then
            local harpa_pos = harpa.position
            local dist_squared = (position.x - harpa_pos.x) * (position.x - harpa_pos.x) + (position.y - harpa_pos.y) * (position.y - harpa_pos.y)
            if range_squared > dist_squared then
                if not Harpa.is_powered(harpa, ignore_entity) then
                    table.remove(global.harpa_list, i)
                    table.insert(global.unpowered_harpa_list, harpa)
                    Harpa.disable_overlay(harpa)
                end
            end
        else
            table.remove(global.harpa_list, i)
        end
    end
end

function Harpa.disable_overlay(entity)
    for i = #global.harpa_overlays, 1, -1 do
        local overlay = global.harpa_overlays[i]
        if overlay.harpa == entity then
            overlay.ticks_remaining = -1
        end
    end
end

function Harpa.create_overlay(entity, player_idx)
    -- only allow 1 active overlay per player (to prevent lag)
    for i = #global.harpa_overlays, 1, -1 do
        local overlay = global.harpa_overlays[i]
        if overlay.player_idx == player_idx then
            overlay.ticks_remaining = -1
        end
    end
    local overlay_entity = entity.surface.create_entity({name = "80_red_overlay", force = game.forces.neutral, position = entity.position })
    local overlay = { player_idx = player_idx, harpa = entity, entity_list = {}, radius = 0, ticks_remaining = 15 * 30 + 12 * 60 }
    table.insert(overlay.entity_list, overlay_entity)
    table.insert(global.harpa_overlays, overlay)
end

function Harpa.update_overlays()
    for i = #global.harpa_overlays, 1, -1 do
        local overlay = global.harpa_overlays[i]
        if overlay.radius < 30 and overlay.harpa.valid and overlay.ticks_remaining % 15 == 0 then
            overlay.radius = overlay.radius + 1
            if (overlay.radius % 5 == 0) then
                local surface = overlay.harpa.surface
                local opacity = 80 - overlay.radius * 2
                local position = overlay.harpa.position
                for dx = -(overlay.radius), overlay.radius do
                    Harpa.create_overlay_entity(surface, opacity, {position.x + dx, position.y + overlay.radius}, overlay.entity_list)
                    Harpa.create_overlay_entity(surface, opacity, {position.x + dx, position.y - overlay.radius}, overlay.entity_list)
                end
                for dy = -(overlay.radius - 1), overlay.radius - 1 do
                    Harpa.create_overlay_entity(surface, opacity, {position.x + overlay.radius, position.y + dy}, overlay.entity_list)
                    Harpa.create_overlay_entity(surface, opacity, {position.x - overlay.radius, position.y - dy}, overlay.entity_list)
                end
            end
        end
        overlay.ticks_remaining = overlay.ticks_remaining - 1
        if overlay.ticks_remaining <= 0 or not overlay.harpa.valid then
            table.remove(global.harpa_overlays, i)
            for _, entity in ipairs(overlay.entity_list) do
                if entity.valid then
                    entity.destroy()
                end
            end
        end
    end
end

function Harpa.create_overlay_entity(surface, opacity, position, list)
    local overlay_entity = surface.create_entity({name = opacity .. "_red_overlay", force = game.forces.neutral, position = position})
    overlay_entity.minable = false
    overlay_entity.destructible = false
    overlay_entity.operable = false
    table.insert(list, overlay_entity)
end

function Harpa.check_power(entity, ignore_entity)
    if entity.prototype.type == "electric-pole" then
        Harpa.update_power_grid(entity.position, 10, ignore_entity)
    end
end

Event.register(defines.events.on_built_entity, function(event)
    if event.created_entity.name == "biter-emitter" then
        event.created_entity.backer_name = ""
        Harpa.register(event.created_entity, event.player_index)
    end
    Harpa.check_power(event.created_entity, nil)
end)

Event.register(defines.events.on_robot_built_entity, function(event)
    if event.created_entity.name == "biter-emitter" then
        event.created_entity.backer_name = ""
        Harpa.register(event.created_entity, nil)
    end
    Harpa.check_power(event.created_entity, nil)
end)

Event.register(defines.events.on_entity_died, function(event)
    local entity = event.entity
    Harpa.check_power(entity, entity)
end)

Event.register(defines.events.on_player_mined_item, function(event)
    if event and event.item_stack and event.item_stack.name and game.entity_prototypes[event.item_stack.name] then
        if game.entity_prototypes[event.item_stack.name].type == "electric-pole" then
            if game.players[event.player_index].character then
                Harpa.update_power_grid(game.players[event.player_index].character.position, 10, nil)
            else
                Harpa.update_power_grid(game.players[event.player_index].position, 10, nil)
            end
        end
    end
end)

Event.register(defines.events.on_tick, function(event)
    Harpa.update_overlays()

    -- check idle emitters less often
    if event.tick % 150 == 0 then
        for i = #global.idle_harpa_list, 1, -1 do
            local harpa = global.idle_harpa_list[i]
            if not harpa.valid then
                table.remove(global.idle_harpa_list, i)
            else
                -- validate that emitter is still idle
                if not Harpa.is_idle(harpa, 32) then
                    table.remove(global.idle_harpa_list, i)
                    table.insert(global.harpa_list, harpa)
                end
            end
        end
    end

    for i = #global.harpa_list, 1, -1 do
        local harpa = global.harpa_list[i]
        if not harpa.valid then
            table.remove(global.harpa_list, i)
        else
            -- check to see if emitter is idle, and we can update it less often
            if event.tick % 150 == 0 then
                if Harpa.is_idle(harpa, 32) then
                    table.remove(global.harpa_list, i)
                    table.insert(global.idle_harpa_list, harpa)
                end
            end

            Harpa.tick_emitter(harpa, 30)
        end
    end
    Harpa.update_power_armor()
end)

Event.register({defines.events.on_player_placed_equipment, defines.events.on_player_removed_equipment}, function(event)
    local player_index = event.player_index

    -- examine harpa status on the next tick
    Event.register(defines.events.on_tick, function(event)
        Event.remove(defines.events.on_tick, event._handler)

        local player = game.players[player_index]
        if Harpa.has_micro_emitter(player) then
            Harpa.track_micro_emitter(player)
        end
    end)
end)

function Harpa.track_micro_emitter(player)
    -- prevent duplicate entries
    for i = #global.micro_harpa_players, 1, -1 do
        if (player == global.micro_harpa_players[i]) then
            return
        end
    end
    for i = #global.idle_micro_harpa_players, 1, -1 do
        if (player == global.idle_micro_harpa_players[i]) then
            return
        end
    end
    table.insert(global.micro_harpa_players, player)
end

function Harpa.has_micro_emitter(player)
    if player and player.valid and player.connected then
        --local armor = player.get_inventory(defines.inventory.player_armor)[1]
        local armor = Harpa.get_player_armor(player)
        local equipment_grid = Harpa.get_equipment_grid(armor)
        if equipment_grid then
            for _, equipment in pairs(equipment_grid.equipment) do
                if equipment.name == "micro-biter-emitter" then
                    return true
                end
            end
        end
    end
    return false
end

function Harpa.get_equipment_grid(item)
    if not item then
        return nil
    end
    if not item.valid_for_read then
        return nil
    end
    local status, value = pcall(function() return item.grid end)
    if status then
        return value
    end
    return nil
end

function Harpa.get_player_armor(player)
    local status, inventory = pcall(player.get_inventory, defines.inventory.player_armor)
    if status and inventory then
        return inventory[1]
    end
    return nil
end

function Harpa.update_power_armor()
    local idle_check = game.tick % 120 == 0

    -- check all idle micro emitters, and return active emitters to service
    if game.tick % 150 == 0 then
        for i = #global.idle_micro_harpa_players, 1, -1 do
            local player = global.idle_micro_harpa_players[i]
            if Harpa.has_micro_emitter(player) then
                if Harpa.is_idle(player, 20) then
                    -- do nothing, still idle
                else
                    -- return to active status
                    table.remove(global.idle_micro_harpa_players, i)
                    table.insert(global.micro_harpa_players, player)
                end
            else
                table.remove(global.idle_micro_harpa_players, i)
            end
        end
    end
    -- update all active micro emitters
    for i = #global.micro_harpa_players, 1, -1 do
        local player = global.micro_harpa_players[i]
        if Harpa.has_micro_emitter(player) then
            -- only test if HARPA is idle every 120 ticks, it is expensive
            if idle_check and Harpa.is_idle(player, 20) then
                table.insert(global.idle_micro_harpa_players, player)
                table.remove(global.micro_harpa_players, i)
            else
                Harpa.tick_emitter(player, 16)
            end
        else
            table.remove(global.micro_harpa_players, i)
        end
    end
end

-- only a best guess based on nearby electric poles
function Harpa.is_powered(entity, ignore_entity)
    local surface = entity.surface
    local position = entity.position
    local ranges_squared = {}; ranges_squared["small-electric-pole"] = 2.5; ranges_squared["medium-electric-pole"] = 3.5; ranges_squared["big-electric-pole"] = 2; ranges_squared["substation"] = 7
    local electric_poles = surface.find_entities_filtered({area = Harpa.area_around(position, 10), type = "electric-pole", force = "player"})
    for i = 1, #electric_poles do
        local electric_pole = electric_poles[i]
        if electric_pole ~= ignore_entity then
            local range = ranges_squared[electric_pole.prototype.name]

            local pole_pos = electric_pole.position
            if range ~= nil and Harpa.is_inside_area(Harpa.area_around(pole_pos, range), position) then
                return true
            end
        end
    end
    return false
end

function Harpa.is_inside_area(area, position)
    return position.x > area.left_top.x and position.y > area.left_top.y and
            position.x < area.right_bottom.x and position.y < area.right_bottom.y
end

function Harpa.area_around(position, distance)
    return {left_top = {x = position.x - distance, y = position.y - distance},
            right_bottom = {x = position.x + distance, y = position.y + distance}}
end

function Harpa.is_idle(entity, radius)
    return entity.surface.find_nearest_enemy({position = entity.position, max_distance = radius, force = entity.force}) == nil
end

-- called every tick... keep it optimized
function Harpa.tick_emitter(entity, radius)
    -- using x and y and tick for modulus assures emitters next to each other will scan separate rows
    local diameter = radius * 2
    local pos = entity.position
    local surface = entity.surface
    local force = entity.force
    local row = ((math.floor(pos.y) + math.floor(pos.x) + game.tick) % diameter) - radius
    local area = {left_top = {pos.x - radius, pos.y - row}, right_bottom = {pos.x + radius, pos.y - row + 1}}
    local biters = surface.find_entities_filtered({area = area, type = "unit", force = "enemy"})

    local emitter_area = {left_top = {pos.x - diameter, pos.y - diameter}, right_bottom = {pos.x + diameter, pos.y + diameter}}
    for _, biter in ipairs(biters) do
        local roll = math.random(0, 100)
        local biter_pos = biter.position
        -- random chance to 1-shot kill a biter (as long as it is not a behemoth)
        if (roll >= 99) and biter.prototype.max_health < 2500 then
            biter.damage(biter.prototype.max_health, force)
        else
            distance = math.sqrt((biter_pos.x - pos.x) * (biter_pos.x - pos.x) + (biter_pos.y - pos.y) * (biter_pos.y - pos.y))
            biter.damage(math.min(100, biter.prototype.max_health / (1 + distance)), force)
        end

        -- check if biter is valid (damage may have killed it)
        if biter.valid and not Harpa.ignore_biter(biter) then
            local command = {}
            local ignore_time = 60 * 5

            -- emitter only works on non-behemoth biters
            if biter.prototype.max_health < 2500 then
                local destination = Harpa.nearest_corner(biter_pos, emitter_area, math.random(1, 10), math.random(1, 10))
                destination = surface.find_non_colliding_position(biter.name, destination, 20, 0.3)
                command = {type = defines.command.compound, structure_type = defines.compound_command.logical_and, commands = {
                    {type = defines.command.go_to_location, distraction = defines.distraction.by_damage, destination = destination},
                    {type = defines.command.wander}
                }}
            else
                -- emitter angers behemoth biters into attacking immediately
                command = {type = defines.command.attack, target = entity, distraction = defines.distraction.none}
                ignore_time = 60 * 60
            end
             local status, err = pcall(biter.set_command, command)
             if not status then
                Harpa.Logger.log("Error (" .. string.line(err) .. ") executing biter command command: " .. string.block(command))
            end
            table.insert(global.biter_ignore_list, {biter = biter, until_tick = game.tick + ignore_time})
        end
    end

    local spawners = surface.find_entities_filtered({area = area, type = "unit-spawner", force = "enemy"})
    for _, spawner in ipairs(spawners) do
        spawner.damage(spawner.prototype.max_health / 250, force)
    end
    local worms = surface.find_entities_filtered({area = area, type = "turret", force = "enemy"})
    for _, worm in ipairs(worms) do
        worm.damage(worm.prototype.max_health / 100, force)
    end
end

function Harpa.ignore_biter(entity)
    for i = #global.biter_ignore_list, 1, -1 do
        local biter_data = global.biter_ignore_list[i]
        if not biter_data.biter.valid or game.tick > biter_data.until_tick then
            table.remove(global.biter_ignore_list, i)
        elseif biter_data.biter == entity then
            return true
        end
    end
    return false
end

function Harpa.nearest_corner(pos, area, rand_x, rand_y)
    local dist_left_top = (pos.x - area.left_top[1]) * (pos.x - area.left_top[1]) + (pos.y - area.left_top[2]) * (pos.y - area.left_top[2])
    local dist_right_bottom = (pos.x - area.right_bottom[1]) * (pos.x - area.right_bottom[1]) + (pos.y - area.right_bottom[2]) * (pos.y - area.right_bottom[2])
    if (dist_left_top < dist_right_bottom) then
        local dist_right_top = (pos.x - area.right_bottom[1]) * (pos.x - area.right_bottom[1]) + (pos.y - area.left_top[2]) * (pos.y - area.left_top[2])
        if (dist_left_top < dist_right_top) then
            return {area.left_top[1] - rand_x, area.left_top[2] - rand_y}
        else
            return {area.right_bottom[1] + rand_x, area.left_top[2] - rand_y}
        end
    else
        local dist_left_bottom = (pos.x - area.left_top[1]) * (pos.x - area.left_top[1]) + (pos.y - area.right_bottom[2]) * (pos.y - area.right_bottom[2])
        if (dist_right_bottom < dist_left_bottom) then
            return {area.right_bottom[1] + rand_x, area.right_bottom[2] + rand_y}
        else
            return {area.left_top[1] - rand_x, area.right_bottom[2] + rand_y}
        end
    end
end

return Harpa
