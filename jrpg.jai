Character :: struct {
    name: string;
    health: struct {
        current: int;
        maximum: int;
    }
    attack: int;
    initiative: int;
    stunned_turns_remaining: int;
}

ENEMY_KOBOLD :: Character.{
    name="kobold",
    health.maximum=5,
    attack=1,
    initiative=1
};

ENEMY_GOBLIN :: Character.{
    name="goblin",
    health.maximum=10,
    attack=2,
    initiative=1
};

game: struct {
    state: struct {
        party: [..] Character;
        encounter: struct {
            party: [..] Character;
            initiative_order: [..] *Character;
            current_turn_haver: *Character;
        }
    }
}

begin_encounter_against :: (enemies: ..Character) {
    // list enemies
    {
        enemy_list: String_Builder;
        for enemies {
            if enemies.count > 1 && it_index > 0 {
                remaining := enemies.count - it_index;
                if remaining >  1 then append(*enemy_list, ", ");
                if remaining == 1 then append(*enemy_list, " and ");
            }
            append(*enemy_list, it.name);
        }
        append(*enemy_list, " appears!");
        log(builder_to_string(*enemy_list));
    }

    // add enemies
    { using game.state.encounter;
        array_reset(*party);
        array_add(*party, ..enemies);
        for * party it.health.current = it.health.maximum;
    }

    // roll for initiative (disclaimer: no actual rolling occurs for now)
    { using game.state;
        array_reset(*encounter.initiative_order);
        for * party array_add(*encounter.initiative_order, it);
        for * encounter.party array_add(*encounter.initiative_order, it);
        assert(encounter.initiative_order.count > 0);
        quick_sort(encounter.initiative_order, x => -x.initiative);
        encounter.current_turn_haver = encounter.initiative_order[0];
    }

    // encounter loop
    encounter_status := get_encounter_status();
    while encounter_status == .ONGOING {
        // do turn
        { using game.state;
            if !can_take_turn(encounter.current_turn_haver) then return;
            
            target := choose_target();
            attack(encounter.current_turn_haver, target);

            choose_target :: () -> *Character {
                using game.state;
                current_turn_haver_is_player := false;
                for * party if it == encounter.current_turn_haver { current_turn_haver_is_player = true; break; }
                possible_targets: [..] *Character; possible_targets.allocator = temp;
                if current_turn_haver_is_player
                    then { for * encounter.party if it.health.current > 0 then array_add(*possible_targets, it); }
                    else { for * party           if it.health.current > 0 then array_add(*possible_targets, it); }
                assert(possible_targets.count > 0);
                random_index := cast(s32)(random_get() % cast(u64)possible_targets.count);
                return possible_targets[random_index];
            }

            can_take_turn :: (using character: *Character) -> bool {
                if health.current == 0 then return false;
                if stunned_turns_remaining > 0 {
                    stunned_turns_remaining -= 1;
                    if stunned_turns_remaining > 0 {
                        log("% is stunned!", name);
                        return false;
                    }
                    else log("% is no longer stunned!", name);
                }
                return true;
            }
        }
        
        // end of turn
        { using game.state.encounter;
            found, index := array_find(initiative_order, current_turn_haver);
            assert(found);
            index += 1;
            if index >= initiative_order.count then index -= initiative_order.count;
            current_turn_haver = initiative_order[index];
        }
        encounter_status = get_encounter_status();
        reset_temporary_storage();
    }

    // end of encounter cleanup/results
    { using game.state.encounter;
        array_free(party);
        array_free(initiative_order);
    }
    game.state.encounter = .{};
    if encounter_status == {
        case .VICTORY; log("Victory!");
        case .DEFEAT;  log("Defeat!");
    }

    get_encounter_status :: () -> enum { ONGOING; VICTORY; DEFEAT; } {
        using game.state;
        is_any_player_character_alive := false;
        for party if it.health.current > 0 { is_any_player_character_alive = true; break; }
        is_any_enemy_character_alive := false;
        for encounter.party if it.health.current > 0 { is_any_enemy_character_alive = true; break; }
        if is_any_player_character_alive then if is_any_enemy_character_alive then return .ONGOING; else return .VICTORY;
        return .DEFEAT;
    }
}

attack :: (attacker: *Character, target: *Character) {
    damage := attacker.attack;
    target_health_previous := target.health.current;
    target.health.current = max(target.health.current-damage, 0);
    //damage_inflicted := target_health_previous - target.health.current;
    log("% attacks % for % damage%", attacker.name, target.name, damage, ifx target.health.current == 0 then tprint(", killing %!", target.name) else "!");
}

// unused, but works
stun :: (using target: *Character, turns: int=2) { stunned_turns_remaining = max(stunned_turns_remaining, turns); }

// unused for now, but could be used to allow basic user input
read_input :: (prompt := "") -> string {
    write_string(prompt);

    buffer: []u8;
    buffer.count = 128;
    buffer.data = talloc(buffer.count);
    #if OS == .WINDOWS {
        #import "Windows";
        bytes_read: u32;
        success := ReadFile(GetStdHandle(STD_INPUT_HANDLE), buffer.data, xx buffer.count, *bytes_read, null);
        assert(success == .TRUE);
    }
    else #if OS == .LINUX || OS == .MACOS {
        #import "POSIX";
        bytes_read := read(STDIN_FILENO, buffer.data, xx buffer.count);
        assert(bytes_read >= 0);
    }
    if bytes_read {
        result: string;
        result.data  = buffer.data;
        result.count = bytes_read;
        if result[result.count-1] == #char "\n" result.count -= 1;
        if result[result.count-1] == #char "\r" result.count -= 1;
        return result;
    }
    return "";
}

// entry point
main :: () {
    array_add(*game.state.party, Character.{
        name="Hero",
        health.current=10,
        health.maximum=10,
        attack=4,
        initiative=2
    });

    begin_encounter_against(
        ENEMY_KOBOLD
    );

    begin_encounter_against(
        ENEMY_KOBOLD,
        ENEMY_GOBLIN,
        ENEMY_KOBOLD
    );
}

#import "Basic";
#import "Sort";
#import "Random";
