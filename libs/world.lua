require 'stdlib/event/event'
require 'stdlib/log/logger'
require 'stdlib/entity/entity'
require 'stdlib/surface'
require 'libs/biter/base'

World = {}
World.version = 70
World.Logger = Logger.new("Misanthrope", "world", DEBUG_MODE)
local Log = function(str, ...) World.Logger.log(string.format(str, ...)) end

function World.setup()
    if not global.mod_version then
        -- goodbye fair world
        local old_global = global
        global = {}
        global.mod_version = 0

        Harpa.migrate(old_global)
        World.recalculate_chunk_values()
    end
    if World.version ~= global.mod_version then
        World.migrate(global.mod_version, World.version)
        global.mod_version = World.version
    end
end

function World.migrate(old_version, new_version)
    Log("Migrating world data from {%s} to {%s}...", old_version, new_version)
    if old_version < 60 then
        local old_global = global
        global = {}
        global.mod_version = 60

        Harpa.migrate(old_global)
        World.recalculate_chunk_values()
        global.bases = {}
        for _, spawner in pairs(Surface.find_all_entities({ type = 'unit-spawner', surface = 'nauvis' })) do
            -- may already be dead if it was discovered and killed
            if spawner.valid then
                local data = Entity.get_data(spawner)
                if not data or not data.base then
                    BiterBase.discover(spawner)
                end
            end
        end
    end
    if old_version < 67 then
        global.mod_version = 67
        global.tick_schedule = {}
        global.bases = table.each(table.filter(global.bases, Game.VALID_FILTER), function(base)
            if base.next_tick < game.tick then
                base.next_tick = game.tick + 60
            end
            if not global.tick_schedule[base.next_tick] then
                global.tick_schedule[base.next_tick] = {}
            end
            table.insert(global.tick_schedule[base.next_tick], base)
        end)
    end
    if old_version < 69 then
        global.mod_version = 69
        global._chunk_indexes = nil
        global._chunk_data = nil
    end
    if old_version < 70 then
        global.mod_version = 70
        if global.overmind then
            global.overmind.last_evo_boost = 0
        end
        global.bases = table.each(table.filter(global.bases, Game.VALID_FILTER), function(base)
            if base.targets then
                local max_candidates = math.min(20, #base.targets.candidates)
                local base_candidates = {}
                for i = 1, max_candidates do
                    base_candidates[i] = base.targets.candidates[i].chunk_pos
                end
                base.targets.candidates = base_candidates
            end
        end)
    end
end

function World.all_characters(surface)
    local characters = {}
    for idx, player in pairs(game.players) do
        if player.valid and player.connected then
            local character = player.character
            if character and character.valid and (surface == nil or character.surface == surface) then
                characters[idx] = character
            end
        end
    end
    return characters
end

function World.closest_player_character(surface, pos, dist)
    local closest_char = nil
    local closest = dist * dist
    for _, character in pairs(World.all_characters(surface)) do
        local dist_squared = Position.distance_squared(pos, character.position)
        if dist_squared < closest then
            closest_char = character
            closest = dist_squared
        end
    end
    return closest_char
end

function World.get_base_at(surface, chunk)
    local area = Chunk.to_area(chunk)
    if not global.bases then return nil end
    for _, base in pairs(global.bases) do
        if base.valid and base.queen.valid and base.queen.surface == surface then
            if Area.inside(area, base.queen.position) then
                return base
            end
        end
    end
    return nil
end

Event.register({Event.core_events.init, Event.core_events.configuration_changed}, function(event)
    Log("Setting up world...")
    World.setup()
    Log("World setup complete.")
end)
