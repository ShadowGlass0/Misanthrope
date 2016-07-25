require 'stdlib/event/event'
require 'stdlib/area/position'
require 'stdlib/area/chunk'
require 'stdlib/area/tile'
require 'libs/biter_targets'

local Log = function(str, ...) World.Logger.log(string.format(str, ...)) end

Event.register({defines.events.on_entity_built, defines.events.on_robot_built_entity}, function(event)
    local value, adj_value = World.entity_value(event.entity)

    if value ~= 0 then
        local chunk = Chunk.from_position(event.entity.position)
        World.change_chunk_value(event.entity.surface, chunk, value, adj_value)
    end
end)

Event.register({defines.events.on_entity_died, defines.events.on_preplayer_mined_item, defines.events.on_robot_pre_mined}, function(event)
    local value, adj_value = World.entity_value(event.entity)

    if value ~= 0 then
        local chunk = Chunk.from_position(event.entity.position)
        World.change_chunk_value(event.entity.surface, chunk, value * -1, adj_value * -1)
    end
end)

function World.entity_value(entity)
    if not entity or not entity.valid then
        return 0
    end
    local entity_name = entity.name
    local value = 0
    local adj_value = 0
    local biter_value = Biters.entity_value(entity)
    if entity.type:contains('turret') then
        value = -1 * game.entity_prototypes[entity_name].max_health
        adj_value = value / 2
    elseif biter_value > 0 then
        value = biter_value
    elseif entity.type:contains('container') then
        value = game.entity_prototypes[entity_name].max_health / 3
    end
    if value ~= 0 then
        Log("Entity %s value is %d", entity.name, value)
    end
    return math.floor(value), math.floor(adj_value)
end

function World.recalculate_chunk_values(reset)
    if reset then
        local nauvis = game.surfaces.nauvis
        for chunk in nauvis.get_chunks() do
            local chunk_data = Chunk.get_data(nauvis, chunk)
            if chunk_data then
                chunk_data.player_value = nil
            end
        end
    end
    local all_entities = Surface.find_all_entities({force = game.forces.player})
    Log("Total number of player entities: %d", #all_entities)
    local entity_prototypes = game.entity_prototypes
    for _, entity in pairs(all_entities) do
        local value, adj_value = World.entity_value(entity)
        if value ~= 0 then
            local chunk = Chunk.from_position(entity.position)
            World.change_chunk_value(entity.surface, chunk, value, adj_value)
        end
    end
end

function World.change_chunk_value(surface, chunk, value, adj_value)
    local chunk_data = Chunk.get_data(surface, chunk, {})
    if chunk_data.player_value then
        chunk_data.player_value = math.floor(chunk_data.player_value + value)
    else
        chunk_data.player_value = math.floor(value)
    end
    if adj_value ~= 0 then
        for x, y in Area.iterate(Position.expand_to_area(chunk, 1)) do
            if x ~= chunk.x and y ~= chunk.y then
                World.change_chunk_value(surface, {x = x, y = y}, adj_value, 0)
            end
        end
    end
end
