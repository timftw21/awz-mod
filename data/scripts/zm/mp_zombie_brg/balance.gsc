main()
{
    replacefunc( maps\mp\zombies\weapons\_zombie_microwave_gun::getmicrowavemaxammo, ::getmicrowavemaxammo );
    replacefunc( maps\mp\zombies\weapons\_zombie_microwave_gun::setmicrowaveweaponlevel, ::setmicrowaveweaponlevel );
    replacefunc( maps\mp\zombies\_zombies_rewards::reward_weaponupgradethink, ::reward_weaponupgradethink );
    replacefunc( maps\mp\zombies\_zombies_rewards::civrescuefail, ::civrescuefail );
    replacefunc( maps\mp\zombies\_civilians::civilianmovementrate, ::civilianmovementrate );
    replacefunc( maps\mp\zombies\_zombies_burgertown_spawning::initializespecialai, ::initializespecialai );
    replacefunc( maps\mp\zombies\_zombies_burgertown_spawning::setspecialspawntype, ::setspecialspawntype );
    replacefunc( maps\mp\zombies\zombie_melee_goliath::meleegoliathcalculatemoveratescale, scripts\zm\balance::goliath_movement_rate );
    replacefunc( maps\mp\zombies\zombie_melee_goliath::meleegoliathcalculatetraverseratescale, scripts\zm\balance::goliath_traversal_rate );
    println( "[Zombies Balance] Infection: survivor movement=125%; normal/escort dog cap=5; normal dogs start at round 20; rescue=3 upgrades; failure power penalty disabled; Goliath movement=85%" );
}

civrescuefail()
{
    level.civfailedescorts++;
    println( "[Zombies Balance] Survivor rescue failed; failures=" + level.civfailedescorts + "; power shutdown and EMP penalty suppressed" );
}

civilianmovementrate()
{
    self.moveratescale = 1.2 * 1.25;
    self.nonmoveratescale = 1.2;
    self.traverseratescale = 1.2 * 1.25;
    println( "[Zombies Balance] Survivor=" + self getentitynumber() + " movement/traversal scale=" + self.moveratescale );
}

initializespecialai()
{
    for ( i = 0; i < level.spawninfo.specialspawnsinfo.size; i++ )
    {
        if ( level.spawninfo.specialspawnsinfo[i]["type"] == "zombie_dog" )
        {
            // Both first-appearance and random-pack selection read these limits.
            if ( !isdefined( level.spawninfo.specialspawnsinfo[i]["awzStockTotalAllowed"] ) )
            {
                level.spawninfo.specialspawnsinfo[i]["awzStockStartingRound"] = level.spawninfo.specialspawnsinfo[i]["startingRound"];
                level.spawninfo.specialspawnsinfo[i]["awzStockTotalAllowed"] = level.spawninfo.specialspawnsinfo[i]["startingTotalAllowed"];
            }

            if ( level.roundtype == "normal" )
            {
                level.spawninfo.specialspawnsinfo[i]["startingRound"] = 20;
                level.spawninfo.specialspawnsinfo[i]["startingTotalAllowed"] = 5;
                println( "[Zombies Balance] Infection round=" + level.wavecounter + " regular-round dogs: first round=20; pack budget=5" );
            }
            else
            {
                level.spawninfo.specialspawnsinfo[i]["startingRound"] = level.spawninfo.specialspawnsinfo[i]["awzStockStartingRound"];
                level.spawninfo.specialspawnsinfo[i]["startingTotalAllowed"] = level.spawninfo.specialspawnsinfo[i]["awzStockTotalAllowed"];
                if ( level.roundtype == "civilian" )
                {
                    level.spawninfo.specialspawnsinfo[i]["startingTotalAllowed"] = 5;
                    println( "[Zombies Balance] Infection round=" + level.wavecounter + " survivor escort dog budget=5" );
                }
            }
        }

        if ( level.spawninfo.specialspawnsinfo[i]["spawned"] )
        {
            level.spawninfo.specialspawnsinfo[i]["currentProbability"] = 0;
            level.spawninfo.specialspawnsinfo[i]["currentRemainingCooldown"] = level.spawninfo.specialspawnsinfo[i]["roundCooldown"];
        }
        else
        {
            level.spawninfo.specialspawnsinfo[i]["currentRemainingCooldown"]--;

            if ( level.spawninfo.specialspawnsinfo[i]["currentRemainingCooldown"] < 0 )
                level.spawninfo.specialspawnsinfo[i]["currentRemainingCooldown"] = 0;
        }

        if ( level.spawninfo.specialspawnsinfo[i]["startingRound"] > level.wavecounter )
            probability = 0;
        else
            probability = int( min( 100, level.spawninfo.specialspawnsinfo[i]["currentProbability"] + level.spawninfo.specialspawnsinfo[i]["probabilityIncrease"] ) );

        level.spawninfo.specialspawnsinfo[i]["currentProbability"] = probability;
        level.spawninfo.specialspawnsinfo[i]["totalSpawned"] = 0;
        level.spawninfo.specialspawnsinfo[i]["spawned"] = 0;
        level.spawninfo.packremaining = 0;
    }
}

setspecialspawntype( index )
{
    info = level.spawninfo.specialspawnsinfo[index];
    if ( info["minPackSize"] < info["maxPackSize"] )
        count = randomintrange( info["minPackSize"], info["maxPackSize"] );
    else
        count = info["minPackSize"];

    if ( ( level.roundtype == "normal" || level.roundtype == "civilian" ) && info["type"] == "zombie_dog" )
    {
        // Stock never advances totalSpawned. Reserve the entire pack so queued
        // dogs cannot exceed the round budget or be replenished after a kill.
        count = int( min( count, info["startingTotalAllowed"] - info["totalSpawned"] ) );
        level.spawninfo.specialspawnsinfo[index]["totalSpawned"] += count;
        println( "[Zombies Balance] Infection round=" + level.wavecounter + " dog pack=" + count + " reserved=" + level.spawninfo.specialspawnsinfo[index]["totalSpawned"] + "/5" );
    }

    level.spawninfo.specialspawnsinfo[index]["spawned"] = 1;
    level.spawninfo.packtype = info["type"];
    level.spawninfo.packremaining = count - 1;
    level.spawninfo.specialspawnsinfo[index]["currentProbability"] = level.spawninfo.specialspawnsinfo[index]["currentProbability"] - 10;

    if ( level.roundtype == "normal" )
        level.spawninfo.nextpossiblespecialaipack = level.spawninfo.numberspawned + count + 10;
    else
        level.spawninfo.nextpossiblespecialaipack = level.spawninfo.numberspawned + count + randomintrange( level.spawninfo.specialairange["min"], level.spawninfo.specialairange["max"] );
}

getmicrowavemaxammo()
{
    return 900.0 * scripts\zm\balance::ammo_scale( maps\mp\zombies\_util::getzombieweaponlevel( self, "iw5_microwavezm_mp" ) );
}
reward_weaponupgradethink()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    if ( isdefined( self.inlaststand ) && self.inlaststand == 1 )
    {
        while ( self.inlaststand == 1 )
            wait 0.1;
    }

    if ( isdefined( self.iscarrying ) && self.iscarrying == 1 )
    {
        while ( self.iscarrying == 1 )
            wait 0.1;
    }

    if ( isdefined( self.hasbomb ) && self.hasbomb == 1 )
    {
        while ( self.hasbomb == 1 )
            wait 0.1;
    }

    var_0 = maps\mp\zombies\_util::getplayerweaponzombies( self );
    var_1 = getweaponbasename( var_0 );

    if ( !maps\mp\zombies\_util::haszombieweaponstate( self, var_1 ) )
        return;

    previous_level = self.weaponstate[var_1]["level"];
    reward_level = previous_level;
    upgrades = 0;
    // Apply three steps, retaining the existing Mk 10 -> Mk 25 rescue bonus.
    while ( upgrades < 3 && reward_level <= 10 )
    {
        if ( reward_level < 10 )
            reward_level++;
        else
            reward_level = 25;
        upgrades++;
    }
    if ( !upgrades )
        return;

    maps\mp\zombies\_wall_buys::setweaponlevel( self, var_0, reward_level );
    thread maps\mp\zombies\_zombies_audio::playerweaponupgrade( 0, self.weaponstate[var_1]["level"] );
    self.numupgrades += upgrades;
    println( "[Zombies Balance] Survivor reward player=" + self getentitynumber() + " weapon=" + var_1 + " Mk=" + previous_level + " -> " + reward_level + " upgrades=" + upgrades );
}

setmicrowaveweaponlevel( var_0 )
{
    self.weaponstate["iw5_microwavezm_mp"]["weapon_level_increase"] = scripts\zm\balance::damage_increment( maps\mp\zombies\_util::getzombieweaponlevel( self, "iw5_microwavezm_mp" ) );
    var_0 = clamp( var_0, 1, 20 );

    if ( !isdefined( self.microwavegundata ) )
        return;

    var_1 = clamp( ( var_0 - 1 ) / 19.0, 0, 1 );
    self.microwavegundata.bufflifespan = maps\mp\zombies\_util::lerp( var_1, 3.0, 10.0 );
    self.microwavegundata.fullyslowed = maps\mp\zombies\_util::lerp( var_1, 0.6, 0.4 );
    self.microwavegundata.beamwidth = 25;
}
