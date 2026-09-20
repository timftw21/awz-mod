// Focused overrides of the stock GSC routines documented in docs/gameplay-balance.md.
// Transaction, map-specific mutation, and quest behavior otherwise stays in stock scripts.
main()
{
    replacefunc( maps\mp\zombies\zombie_host::hostroundnumenemies, ::hostroundnumenemies );
    replacefunc( maps\mp\zombies\_zombies_laststand::laststandselfrevive, ::laststandselfrevive );
    replacefunc( maps\mp\zombies\zombie_dog::dogroundnumenemies, ::dogroundnumenemies );
    replacefunc( maps\mp\zombies\_terminals::zombiegroundslamcommon, ::zombiegroundslamcommon );
    replacefunc( maps\mp\zombies\_terminals::getitemcost, ::getitemcost );
    replacefunc( maps\mp\_utility::_giveweapon, ::_giveweapon );
    replacefunc( maps\mp\zombies\_zombies_laststand::respawnplayerzombies, ::respawnplayerzombies );
    replacefunc( maps\mp\zombies\_mutators::mutator_apply, ::mutator_apply );
    replacefunc( maps\mp\zombies\_wall_buys::weaponlevelboxisplayerweaponmaxed, ::weaponlevelboxisplayerweaponmaxed );
    replacefunc( maps\mp\zombies\_wall_buys::weaponlevelboxupdatehintstrings, ::weaponlevelboxupdatehintstrings );
    replacefunc( maps\mp\zombies\_wall_buys::cg_levelboxtriggermonitor, ::cg_levelboxtriggermonitor );
    replacefunc( maps\mp\zombies\_wall_buys::weaponlevelboxthink, ::weaponlevelboxthink );
    replacefunc( maps\mp\zombies\_wall_buys::giveweaponlevelachievement, ::giveweaponlevelachievement );
    replacefunc( maps\mp\zombies\_wall_buys::displayrequiredlevelmessage, ::displayrequiredlevelmessage );
    replacefunc( maps\mp\zombies\_wall_buys::diaplaymaxlevelmessage, ::diaplaymaxlevelmessage );
    replacefunc( maps\mp\zombies\_wall_buys::setweaponlevel, ::setweaponlevel );
    replacefunc( maps\mp\zombies\_wall_buys::getupgradeweaponname, ::getupgradeweaponname );
    replacefunc( maps\mp\zombies\_wall_buys::initcamolevels, ::initcamolevels );
    replacefunc( maps\mp\zombies\_wall_buys::getmagicboxcost, ::getmagicboxcost );
    replacefunc( maps\mp\zombies\_wall_buys::getmagicboxhintstringcost, ::getmagicboxhintstringcost );
    replacefunc( maps\mp\gametypes\zombies::givepointsforevent, ::givepointsforevent );
    replacefunc( maps\mp\gametypes\zombies::createzombieweaponstate, ::createzombieweaponstate );
    replacefunc( maps\mp\gametypes\zombies::getem1maxammo, ::getem1maxammo );
    replacefunc( maps\mp\zombies\killstreaks\_zombie_killstreaks::getnextmoneyamount, ::getnextmoneyamount );
    replacefunc( maps\mp\zombies\zombies_spawn_manager::applyzombiemutator, ::applyzombiemutator );
    replacefunc( maps\mp\zombies\_zombies::calulatezombiemovemode, ::calulatezombiemovemode );
    replacefunc( maps\mp\zombies\_zombies::calculatezombiemoveratescale, ::calculatezombiemoveratescale );
    replacefunc( maps\mp\zombies\zombie_host::hostcaculatemovemode, ::hostcaculatemovemode );
    replacefunc( maps\mp\zombies\zombie_host::hostcaculatemoveratescale, ::hostcaculatemoveratescale );
    replacefunc( maps\mp\agents\humanoid\_humanoid_move::setmoveanim, ::setmoveanim );
    replacefunc( maps\mp\agents\humanoid\_humanoid::setuphumanoidstate, ::setuphumanoidstate );
    replacefunc( maps\mp\agents\_scripted_agent_anim_util::playanimnatrateuntilnotetrack, ::playanimnatrateuntilnotetrack );
    replacefunc( maps\mp\zombies\_mutators::mutatoremz_applyemp, ::mutatoremz_applyemp );
    replacefunc( maps\mp\zombies\_zombies_audio::playerweaponupgrade, ::playerweaponupgrade );
    level.awz_spawn_rolls = 0;
    level.awz_emp_blocked = 0;
    level.awz_mutations_skipped = 0;
    level.awz_exo_spawned = 0;
    level.awz_emp_spawned = 0;
    level.awz_movement_logged = [];
    level thread log_rounds();
    println( "[Zombies Balance] Prices: Reload=3000, Soldier=2500, decontamination=500; Slam=6s/2.5x damage; infection enemies=80%; self-revive=6s; dogs=8/10 per player" );
    println( "[Zombies Balance] Installed: Mk 10 gold/4.55x damage, EMP cap=1, Solo revive grace=2s, power=200, fabricator=950 stock format, sprint=" + zombie_sprint_scale() * 100 + "%, infected sprint=90%, reboot=4s/3s" );
    println( "[Zombies Movement] Round-based pacing through round 14; run ceiling follows reduced sprint speed; locomotion cadence separated from travel speed" );
}

// Map nine upgrades onto the full original attachment progression.
stock_weapon_level( mark )
{
    if ( mark == 25 )
        return 25;
    if ( mark <= 1 )
        return mark;
    return 1 + int( ( min( mark, 10 ) - 1 ) * 19.0 / 9.0 );
}

damage_increment( mark )
{
    if ( mark == 25 )
        return 0.30; // Quest weapon: 8.2x base, above Mk 10's 4.55x.
    if ( mark == 10 )
        return ( 9 * 0.2 + 1.75 ) / 9; // +175% base damage completion bonus.
    return 0.2;
}

ammo_scale( mark )
{
    if ( !isdefined( mark ) || mark <= 1 )
        return 1.0;
    if ( mark == 25 )
        return 2.25;
    return 1.5 + ( min( mark, 10 ) - 2 ) / 16.0;
}

log_rounds()
{
    level endon( "game_ended" );
    for (;;)
    {
        level waittill( "zombie_wave_started" );
        println( "[Zombies Balance] Starting round=" + level.wavecounter + "; previous round: natural spawns=" + level.awz_spawn_rolls + " kept plain=" + level.awz_mutations_skipped + " exo=" + level.awz_exo_spawned + " EMP=" + level.awz_emp_spawned + " EMP blocked=" + level.awz_emp_blocked );
        level.awz_spawn_rolls = 0;
        level.awz_emp_blocked = 0;
        level.awz_mutations_skipped = 0;
        level.awz_exo_spawned = 0;
        level.awz_emp_spawned = 0;
    }
}


weaponlevelboxisplayerweaponmaxed( var_0, var_1 )
{
    return !maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) && var_0.weaponstate[var_1]["level"] >= 10 || maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) && var_0.weaponstate[var_1]["level"] >= 25;
}

weapon_upgrade_cost( player, base_weapon )
{
    if ( scripts\zm\classic::enabled() )
        return 5000;
    if ( !maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) && maps\mp\zombies\_util::haszombieweaponstate( player, base_weapon ) && player.weaponstate[base_weapon]["level"] == 9 )
        return 3000;
    return 1500;
}

weapon_upgrade_level( mark )
{
    if ( scripts\zm\classic::enabled() )
    {
        if ( mark < 5 )
            return 5;
        return 10;
    }
    return min( mark + 1, 10 );
}

weaponlevelboxupdatehintstrings( var_0 )
{
    var_0 endon( "disconnect" );
    for (;;)
    {
        var_2 = var_0 maps\mp\zombies\_util::waittill_any_return_parms_no_endon_death( "weapon_change", "no_upgrades" );
        var_3 = undefined;

        if ( var_2[0] == "no_upgrades" && self.allowupgrade )
            continue;

        switch ( var_2[0] )
        {
            case "weapon_change":
                var_3 = var_2[1];
                break;
            case "no_upgrades":
                self sethintstring( "" );
                self setsecondaryhintstring( "" );
                maps\mp\zombies\_util::tokenhintstring( 0 );
                var_0 waittill( "allow_upgrades" );
                var_3 = maps\mp\zombies\_util::getplayerweaponzombies( var_0 );
                break;
        }

        var_4 = getweaponbasename( var_3 );
        self setcursorhint( "HINT_NOICON" );

        if ( !maps\mp\zombies\_util::haszombieweaponstate( var_0, var_4 ) || !maps\mp\zombies\_wall_buys::weaponlevelboxisplayerweaponmaxed( var_0, var_4 ) )
        {
            self sethintstring( &"ZOMBIES_WEAPON_LEVEL_BOX" );
            cost = weapon_upgrade_cost( var_0, var_4 );
            self setsecondaryhintstring( maps\mp\zombies\_util::getcoststring( cost ) );
            maps\mp\zombies\_util::settokencost( maps\mp\zombies\_util::creditstotokens( cost ) );
            maps\mp\zombies\_util::tokenhintstring( 1 );
            continue;
        }

        self sethintstring( &"ZOMBIES_WEAPON_LEVEL_MAX" );
        self setsecondaryhintstring( "" );
        maps\mp\zombies\_util::tokenhintstring( 0 );
    }
}

cg_levelboxtriggermonitor( var_0 )
{
    var_0 endon( "disconnect" );
    for (;;)
    {
        while ( !var_0 istouching( self ) )
            wait 0.1;
        while ( var_0 istouching( self ) )
        {
            if ( !maps\mp\zombies\_util::haszombieweaponstate( var_0, var_0.baseweapon ) || !maps\mp\zombies\_wall_buys::weaponlevelboxisplayerweaponmaxed( var_0, var_0.baseweapon ) )
            {
                var_0.storedescription settext( &"ZOMBIES_WEAPON_LEVEL_BOX" );
                cost = weapon_upgrade_cost( var_0, var_0.baseweapon );
                var_0.storecost settext( maps\mp\zombies\_util::getcoststring( cost ) );
            }
            else
            {
                var_0.storedescription settext( &"ZOMBIES_WEAPON_LEVEL_MAX" );
                var_0.storecost settext( "" );
            }
            wait 0.1;
        }
        var_0.storedescription settext( "" );
        var_0.storecost settext( "" );
    }
}

weaponlevelboxthink()
{
    level endon( "game_ended" );
    self.modelent = getent( self.target, "targetname" );
    self.allowupgrade = 1;

    if ( maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) )
    {
        maps\mp\zombies\_wall_buys::weaponlevelboxsetupspecialbox();
        maps\mp\zombies\_wall_buys::weaponlevelboxturnofflight();
        common_scripts\utility::trigger_off();
        level waittill( "special_weapon_box_unlocked" );

        if ( level.currentgen )
            common_scripts\utility::trigger_on();

        maps\mp\zombies\_wall_buys::weaponlevelboxturnonlight();
    }

    var_0 = self.modelent gettagangles( "tag_origin" );
    self.modelent playloopsound( "interact_weapon_upgrade_attract" );

    if ( maps\mp\zombies\_util::isusetriggerprimary( self ) )
        maps\mp\zombies\_util::playfxontagnetwork( common_scripts\utility::getfx( "station_upgrade_weapon_pwr_on" ), self.modelent, "tag_origin" );

    if ( level.nextgen )
        maps\mp\zombies\_util::setupusetriggerforclient( self, maps\mp\zombies\_wall_buys::weaponlevelboxupdatehintstrings );
    else
    {
        foreach ( var_2 in level.players )
            thread maps\mp\zombies\_wall_buys::cg_weaponlevelboxupdatehintstrings( var_2 );

        thread maps\mp\zombies\_wall_buys::cg__onplayerconnectedweaponlevelboxupdatehintstrings( self );
    }

    for (;;)
    {
        [var_2, var_8] = maps\mp\zombies\_util::waittilltriggerortokenuse();
        var_9 = var_2 getcurrentprimaryweapon();

        if ( maps\mp\zombies\_util::isrippedturretweapon( var_9 ) || maps\mp\zombies\_util::iszombiekillstreakweapon( var_9 ) || maps\mp\zombies\_util::arewallbuysdisabled() )
            continue;

        var_10 = maps\mp\zombies\_util::getplayerweaponzombies( var_2 );
        var_11 = getweaponbasename( var_10 );

        if ( !maps\mp\zombies\_util::haszombieweaponstate( var_2, var_11 ) )
            continue;

        if ( maps\mp\zombies\_wall_buys::weaponlevelboxisplayerweaponmaxed( var_2, var_11 ) )
        {
            maps\mp\zombies\_wall_buys::diaplaymaxlevelmessage( var_2 );
            continue;
        }

        if ( maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) && var_2.weaponstate[var_11]["level"] != 10 )
        {
            maps\mp\zombies\_wall_buys::displayrequiredlevelmessage( var_2 );
            continue;
        }

        var_4 = weapon_upgrade_cost( var_2, var_11 );
        if ( var_8 == "token" )
            var_2 maps\mp\gametypes\zombies::spendtoken( maps\mp\zombies\_util::creditstotokens( var_4 ) );
        else if ( !var_2 maps\mp\gametypes\zombies::attempttobuy( var_4 ) )
        {
            var_2 thread maps\mp\zombies\_zombies_audio::playerweaponbuy( "wpn_no_cash" );
            continue;
        }

        println( "[Zombies Balance] Upgrade purchase from Mk=" + var_2.weaponstate[var_11]["level"] + " credits=" + var_4 + " payment=" + var_8 );
        self.allowupgrade = 0;

        foreach ( var_13 in level.players )
            var_13 notify( "no_upgrades" );

        var_15 = undefined;

        if ( level.nextgen )
        {
            var_16 = maps\mp\zombies\_wall_buys::findholomodel( var_11 );
            var_15 = spawn( "script_model", self.origin );
            var_15.angles = var_0 - ( 0, 90, 0 );
            var_15 setmodel( var_16 );
            var_17 = [ 15, 0, -6 ];

            if ( var_11 == "iw5_exocrossbowzm_mp" )
            {
                var_17 = [ 13, 0, -13 ];
                var_15.angles = var_15.angles + ( 0, 0, -90 );
            }

            level thread maps\mp\zombies\_wall_buys::centerweaponforwallbuy( self.modelent, var_15, var_17 );
        }

        maps\mp\zombies\_util::playfxontagnetwork( common_scripts\utility::getfx( "station_upgrade_weapon" ), self.modelent, "tag_origin", 1 );
        self.modelent playsound( "interact_weapon_upgrade" );

        if ( maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) )
            maps\mp\zombies\_wall_buys::setweaponlevel( var_2, var_10, 25 );
        else
            maps\mp\zombies\_wall_buys::setweaponlevel( var_2, var_10, weapon_upgrade_level( var_2.weaponstate[var_11]["level"] ) );

        var_2 thread maps\mp\zombies\_zombies_audio::playerweaponupgrade( maps\mp\zombies\_wall_buys::isspecialweaponbox( self ), var_2.weaponstate[var_11]["level"] );
        var_2.numupgrades++;
        wait 1.2;

        if ( isdefined( var_2 ) )
        {
            if ( var_2.weaponstate[var_11]["level"] >= 10 )
            {
                maps\mp\zombies\_util::playfxontagnetwork( common_scripts\utility::getfx( "weapon_level_20" ), self.modelent, "tag_origin", 1 );
                self.modelent playsound( "interact_weapon_upgrade_fwks" );
            }
        }

        wait 0.75;

        if ( isdefined( var_15 ) )
            var_15 delete();

        self.allowupgrade = 1;

        foreach ( var_13 in level.players )
            var_13 notify( "allow_upgrades" );
    }
}

giveweaponlevelachievement( var_0 )
{
    var_1 = var_0 getweaponslistprimaries();

    if ( var_1.size < 2 )
        return;

    foreach ( var_3 in var_1 )
    {
        var_4 = getweaponbasename( var_3 );

        if ( var_0.weaponstate[var_4]["level"] < 10 )
            return;
    }

    var_0 maps\mp\gametypes\zombies::givezombieachievement( "DLC1_ZOMBIE_2020" );
}

displayrequiredlevelmessage( var_0 )
{
    var_0 playsoundtoplayer( "ui_button_error", var_0 );
    var_0 iprintlnbold( awz_localizednumber( "ZOMBIES_REQUIRES_LEVEL_20", "20", "10" ) );
}

diaplaymaxlevelmessage( var_0 )
{
    var_0 playsoundtoplayer( "ui_button_error", var_0 );

    if ( !maps\mp\zombies\_wall_buys::isspecialweaponbox( self ) )
        var_0 iprintlnbold( awz_localizednumber( "ZOMBIES_MAX_LEVEL_20", "20", "10" ) );
    else
        var_0 iprintlnbold( &"ZOMBIES_MAX_LEVEL_25" );
}

setweaponlevel( var_0, var_1, var_2 )
{
    // Mk 25 remains the quest reward; ordinary upgrades stop at Mk 10.
    if ( var_2 != 25 )
        var_2 = int( clamp( var_2, 1, 10 ) );

    var_0 takeweapon( var_1 );
    var_3 = getweaponbasename( var_1 );
    var_0.weaponstate[var_3]["level"] = var_2;
    var_0.weaponstate[var_3]["weapon_level_increase"] = damage_increment( var_2 );
    println( "[Zombies Balance] Weapon " + var_3 + " upgraded to Mk " + var_2 );
    var_4 = maps\mp\zombies\_wall_buys::getupgradeweaponname( var_0, var_3 );
    if ( scripts\zm\classic::enabled() && var_3 == "iw5_dlcgun13_mp" && var_2 >= 5 )
        println( "[Classic] 1911 Mk " + var_2 + ": dual pistols with impact-explosive projectiles; weapon=" + var_4 );
    maps\mp\zombies\_wall_buys::givezombieweapon( var_0, var_4, 0 );

    if ( issubstr( var_4, "iw5_em1zm_mp" ) )
        var_0 maps\mp\gametypes\zombies::playersetem1maxammo();

    if ( isdefined( level.setweaponlevelfunc ) )
        var_0 [[ level.setweaponlevelfunc ]]( var_1, stock_weapon_level( var_2 ) );

    var_0 playsoundtoplayer( "mp_s1_earn_medal", var_0 );
}

getupgradeweaponname( var_0, var_1 )
{
    var_2 = var_1;
    var_3 = getweaponbasename( var_1 );

    if ( maps\mp\zombies\_util::haszombieweaponstate( var_0, var_3 ) && var_0.weaponstate[var_3]["level"] > 0 )
    {
        var_4 = var_0.weaponstate[var_3]["level"];
        stock_level = stock_weapon_level( var_4 );

        if ( var_4 > 25 )
            var_4 = 25;

        var_5 = maps\mp\zombies\_wall_buys::getcamoforweaponlevel( var_3, var_4 );
        var_6 = maps\mp\zombies\_wall_buys::getattachment1forweaponlevel( var_3, stock_level );
        var_7 = maps\mp\zombies\_wall_buys::getattachment2forweaponlevel( var_3, stock_level );
        var_8 = maps\mp\zombies\_wall_buys::getattachment3forweaponlevel( var_3, stock_level );
        if ( scripts\zm\classic::enabled() && var_3 == "iw5_dlcgun13_mp" && var_4 >= 5 )
        {
            // Keep the original base name so upgrades, ammo and last stand share
            // the same weapon state. Akimbo retains the native two-hand behavior.
            var_6 = "akimbo";
            var_7 = "explosive1911";
            var_8 = "none";
        }
        var_9 = maps\mp\_utility::strip_suffix( var_3, "_mp" );
        var_2 = maps\mp\gametypes\_class::buildweaponname( var_9, var_6, var_7, var_8, var_5, 0 );
    }

    return var_2;
}

initcamolevels()
{
    awz_resetammoscales();
    level.camolevel = [];
    for ( mark = 0; mark <= 25; mark++ )
    {
        // The native weapon display name also reads this camo's table row.
        // Keep it at the real Mk; only attachments use the compressed stock tier.
        camo = int( tablelookup( "mp/zmWeaponLevels.csv", 0, mark, 1 ) );
        level.camolevel[mark] = camo;
        if ( ( mark >= 2 && mark <= 10 ) || mark == 25 )
            awz_setammoscale( camo, ammo_scale( mark ) );
    }
    if ( scripts\zm\classic::enabled() )
        println( "[Classic] Upgrades: Mk1 -> Mk5 -> Mk10; cost=5000 each; Mk5=1.8x damage/1.6875x ammo; Mk10=4.55x damage/2x ammo/gold" );
    else
        println( "[Zombies Balance] Mk 1-10; upgrades=1500 (Mk10=3000); damage=+20% base per upgrade, Mk10=4.55x with completion bonus; ammo=1.5x-2x" );
}

getmagicboxcost( base_cost )
{
    if ( maps\mp\_utility::gameflag( "fire_sale" ) )
        return 10;
    return 950;
}

getmagicboxhintstringcost( inactive )
{
    self.cost = getmagicboxcost();
    if ( isdefined( inactive ) && inactive )
    {
        self.cost = 0;
        return &"ZOMBIES_EMPTY_STRING";
    }
    if ( self.cost == 10 )
        return &"ZOMBIES_COST_10";
    // Preserve the stock language, punctuation, and number color.
    return awz_localizednumber( "ZOMBIES_COST_900", "900", "950" );
}

givepointsforevent( var_0, var_1, var_2 )
{
    if ( isdefined( level.disablescoring ) && level.disablescoring )
        return;

    var_3 = level.pointevents[var_0];

    if ( isdefined( var_1 ) )
        var_3 = var_1;

    if ( var_0 == "atm" )
        var_3 = 150;
    else if ( var_0 == "power_on" )
        var_3 = 200;

    if ( var_0 == "atm" || var_0 == "power_on" || var_0 == "crate" )
        println( "[Zombies Balance] Credit event=" + var_0 + " base=" + var_3 );

    if ( !var_3 )
        return;

    if ( maps\mp\_utility::gameflag( "double_points" ) )
        var_3 = int( var_3 * 2 );

    if ( isdefined( var_2 ) && var_2 )
    {
        var_4 = common_scripts\utility::tostring( var_3 );
        var_4 = strinsertnumericdelimiters( var_4 );
        self iprintlnbold( &"ZOMBIES_PLUS_CREDITS", var_4 );
    }

    maps\mp\gametypes\zombies::givemoney( var_3 );
}

createzombieweaponstate( var_0, var_1 )
{
    var_2 = getweaponbasename( var_1 );

    if ( maps\mp\zombies\_util::haszombieweaponstate( var_0, var_2 ) )
        return;

    var_0.weaponstate[var_2]["level"] = 1;
    var_0.weaponstate[var_2]["weapon_level_increase"] = damage_increment( 1 );
}

getem1maxammo( var_0 )
{
    if ( !isdefined( var_0 ) )
        var_0 = 0;

    var_1 = 1.0;

    if ( !var_0 && self hasperk( "specialty_stockpile", 1 ) )
        var_1 = var_1 * 1.2;

    return 1800.0 * var_1 * ammo_scale( maps\mp\zombies\_util::getzombieweaponlevel( self, "iw5_em1zm_mp" ) );
}

getnextmoneyamount()
{
    return 500 + 50 * randomint( 11 );
}

applyzombiemutator( var_0 )
{
    if ( scripts\zm\classic::enabled() )
    {
        level.awz_spawn_rolls++;
        level.awz_mutations_skipped++;
        return;
    }
    if ( !isscriptedagent( var_0 ) )
        return;

    // Half the ordinary spawn slots remain unmutated. Preserve the stock
    // map-specific selection and the exo dependency of special mutations.
    level.awz_spawn_rolls++;
    if ( randomfloat( 1.0 ) < 0.5 )
    {
        level.awz_mutations_skipped++;
        return;
    }

    var_1 = var_0 maps\mp\zombies\zombies_spawn_manager::specialmutatorshouldapply( level.wavecounter );
    var_2 = [];
    var_3 = var_0 maps\mp\zombies\zombies_spawn_manager::exomutatorshouldapply( level.wavecounter ) || var_1;

    if ( var_3 )
    {
        level.awz_exo_spawned++;
        var_0 thread maps\mp\zombies\_mutators::mutator_apply( "exo" );
    }

    if ( var_1 )
    {
        var_7 = [];
        var_8 = 0.0;

        foreach ( var_12, var_5 in level.special_mutators )
        {
            var_10 = var_5[0];
            var_11 = var_5[1];

            if ( isdefined( level.mutators_disabled[var_0.agent_type] ) )
            {
                if ( isdefined( level.mutators_disabled[var_0.agent_type][var_12] ) && level.mutators_disabled[var_0.agent_type][var_12] )
                    continue;
            }

            if ( var_0 [[ var_10 ]]( level.wavecounter ) )
            {
                var_7[var_7.size] = var_12;
                var_8 = var_8 + var_11;
            }
        }

        var_13 = randomfloat( var_8 );
        var_14 = 0.0;

        foreach ( var_12 in var_7 )
        {
            var_11 = level.special_mutators[var_12][1];

            if ( var_13 > var_14 && var_13 <= var_14 + var_11 )
            {
                var_0 thread maps\mp\zombies\_mutators::mutator_apply( var_12 );
                break;
            }

            var_14 = var_14 + var_11;
        }
    }
}

calulatezombiemovemode( var_0 )
{
    // Gate the whole progression, not just the gait: mutation offsets otherwise
    // advance the rate by up to six rounds and wrap it inside the capped run gait.
    if ( level.wavecounter < 15 )
    {
        if ( level.wavecounter <= var_0 )
            return "walk";
        return "run";
    }
    var_1 = maps\mp\zombies\_zombies::calculatezombieroundindex( var_0 );
    var_2 = int( var_1 / var_0 );
    return level.zombie_move_modes[int( clamp( var_2, 0, level.zombie_move_modes.size - 1 ) )];
}

hostcaculatemovemode()
{
    if ( level.wavecounter < 15 )
        return "run";
    return "sprint";
}

playerweaponupgrade( var_0, var_1 )
{
    if ( var_1 == 10 )
        thread maps\mp\zombies\_zombies_audio::create_and_play_dialog_delay( "perk", "weapon_upgrade_max", undefined, undefined, undefined, 1 );
    else if ( !isdefined( self.weaponupgradevodebounce ) || self.weaponupgradevodebounce < gettime() )
    {
        thread maps\mp\zombies\_zombies_audio::create_and_play_dialog_delay( "perk", "weapon_upgrade", undefined, undefined, undefined, 1 );
        self.weaponupgradevodebounce = gettime() + 20000;
    }
}


zombie_sprint_scale()
{
    if ( scripts\zm\classic::enabled() )
        return 0.7;
    return 0.8;
}

calculatezombiemoveratescale( var_0, var_1, var_2 )
{
    if ( level.wavecounter < 15 )
    {
        if ( self.movemode == "run" )
            return early_run_rate( var_0, var_1, var_2, level.moveratescalemod["sprint"][0] * zombie_sprint_scale() ) * maps\mp\zombies\_zombies::getbuffspeedmultiplier();
        progress = clamp( float( level.wavecounter - 1 ) / float( var_0 - 1 ), 0, 1 );
        return maps\mp\zombies\_util::lerp( progress, var_1, var_2 ) * maps\mp\zombies\_zombies::getbuffspeedmultiplier();
    }
    var_3 = maps\mp\zombies\_zombies::calculatezombieroundindex( var_0 );
    var_4 = var_3 % var_0;
    var_5 = float( var_4 ) / float( var_0 - 1 );
    var_6 = maps\mp\zombies\_util::lerp( var_5, var_1, var_2 );

    if ( level.wavecounter > 24 )
        var_6 = var_6 + 0.05;

    if ( level.wavecounter > 29 )
        var_6 = var_6 + 0.05;

    var_6 = var_6 * maps\mp\zombies\_zombies::getbuffspeedmultiplier();
    if ( self.movemode == "sprint" )
        var_6 *= zombie_sprint_scale();
    return var_6;
}

hostcaculatemoveratescale()
{
    // Stock infected playback is 0.9; retain 90% of its travel speed.
    scale = 0.9 * 0.9;
    if ( self.movemode != "sprint" )
    {
        cycle = 7;
        if ( isdefined( level.wavecycleoverride ) )
            cycle = level.wavecycleoverride;
        scale = early_run_rate( cycle, level.moveratescalemod["run"][0], level.moveratescalemod["run"][1], scale );
    }
    return scale * maps\mp\zombies\_zombies::getbuffspeedmultiplier();
}

move_anim_speed( mode, index )
{
    movement_anim = self getanimentry( mode, index );
    duration = getanimlength( movement_anim );
    if ( duration <= 0 )
        return 0;
    return length2d( getmovedelta( movement_anim ) ) / duration;
}

early_run_rate( cycle, low, high, sprint_rate )
{
    // Capture the intact class at spawn, before damage can swap its animations.
    // Losing an arm must not change the round's movement budget.
    if ( isdefined( level.awz_move_speeds ) )
        high = min( high, level.awz_move_speeds["sprint"].low * sprint_rate / level.awz_move_speeds["run"].high );
    low = min( low, high );
    // Infection's six-round cycle needs eight running rounds before the same
    // round-15 sprint gate; modulo arithmetic used to restart it on round 13.
    progress = clamp( float( level.wavecounter - cycle - 1 ) / float( 13 - cycle ), 0, 1 );
    return maps\mp\zombies\_util::lerp( progress, low, high );
}

uses_balanced_locomotion()
{
    if ( self.agent_type == "zombie_host" )
        return 1;
    // Descent's scripted challenge has its own movement callbacks.
    return self.agent_type == "zombie_generic" && !isdefined( level.moveratescalefunc[self.agent_type] );
}

setuphumanoidstate()
{
    // Stock initialization; capture locomotion references synchronously at spawn.
    self.attackoffset = 26 + self.radius;
    self.meleesectortype = "normal";
    self.meleesectorupdatetime = 50;
    self.attackzheight = 54;
    self.attackzheightdown = -64;
    self.damagedradiussq = 2250000;
    self.ignoreclosefoliage = 1;
    self.moveratescale = 1.0;
    self.nonmoveratescale = 1.0;
    self.traverseratescale = 1.0;
    self.generalspeedratescale = 1.0;
    self.bhasbadpath = 0;
    self.bhasnopath = 1;
    self.timeoflastdamage = 0;
    self.allowcrouch = 1;
    self.meleecheckheight = 40;
    self.meleeradiusbase = 60;
    self.meleeradiusbasesq = squared( self.meleeradiusbase );
    maps\mp\zombies\_util::setmeleeradius( self.meleeradiusbase );
    self.defaultgoalradius = self.radius + 1;
    self scragentsetgoalradius( self.defaultgoalradius );
    self.meleedot = 0.5;

    if ( !uses_balanced_locomotion() || isdefined( level.awz_move_speeds ) )
        return;
    level.awz_move_speeds = [];
    foreach ( mode in [ "run", "sprint" ] )
    {
        limits = spawnstruct();
        limits.low = move_anim_speed( mode, 0 );
        limits.high = limits.low;
        for ( i = 1; i < self getanimentrycount( mode ); i++ )
        {
            speed = move_anim_speed( mode, i );
            limits.low = min( limits.low, speed );
            limits.high = max( limits.high, speed );
        }
        level.awz_move_speeds[mode] = limits;
        println( "[Zombies Movement] Intact " + mode + " animation speed range=" + limits.low + ".." + limits.high );
    }
}

setmoveanim( mode )
{
    self notify( "humanoidmove_endwait_setmoveanim" );
    self endon( "humanoidmove_endwait_setmoveanim" );
    self endon( "killanimscript" );
    self.inpainmoving = 0;
    self.inturnanim = 0;
    index = randomint( self getanimentrycount( mode ) );
    rate = self.moveratescale;
    self.awz_stride_scaled = 0;
    self scragentsetanimscale( 1, 1 );

    if ( !uses_balanced_locomotion() || maps\mp\agents\humanoid\_humanoid_util::iscrawling() || mode == "walk" )
    {
        maps\mp\agents\_scripted_agent_anim_util::set_anim_state( mode, index, rate );
        return;
    }

    base_speed = move_anim_speed( mode, index );
    limits = level.awz_move_speeds[mode];
    speed = clamp( base_speed, limits.low, limits.high ) * rate;
    if ( base_speed > 0 )
        rate = speed / base_speed;
    // A reduced sprint often matches a natural run. Keep the requested travel
    // speed when choosing that clip, instead of playing a sprint in slow motion.
    if ( ( mode == "sprint" || base_speed > limits.high ) && rate > 0 )
    {
        for ( run_index = 0; run_index < self getanimentrycount( "run" ); run_index++ )
        {
            run_speed = move_anim_speed( "run", run_index );
            if ( run_speed > 0 && abs( speed / run_speed - 1 ) < abs( rate - 1 ) )
            {
                mode = "run";
                index = run_index;
                rate = speed / run_speed;
            }
        }
    }

    // Root displacement and playback are separate engine controls. Preserve
    // speed exactly while avoiding slow running cycles; weapon/trap slows still
    // slow the animation too. Zero-speed debuffs must not divide by zero.
    cadence = max( rate, 0.9 * min( 1, maps\mp\zombies\_zombies::getbuffspeedmultiplier() ) );
    stride = 1;
    if ( cadence > 0 )
        stride = rate / cadence;
    self scragentsetanimscale( stride, 1 );
    self.awz_stride_scaled = 1;
    maps\mp\agents\_scripted_agent_anim_util::set_anim_state( mode, index, cadence );

    key = self.agent_type + "_" + self.movemode;
    if ( !isdefined( level.awz_movement_logged[key] ) || level.awz_movement_logged[key] != level.wavecounter )
    {
        level.awz_movement_logged[key] = level.wavecounter;
        println( "[Zombies Movement] round=" + level.wavecounter + " type=" + self.agent_type + " gait=" + self.movemode + " clip=" + mode + " speed=" + speed + " playback=" + cadence + " stride=" + stride );
    }
}

playanimnatrateuntilnotetrack( state, index, rate, note, endnote, callback )
{
    // Turns are the one move interruption that does not set its own root scale.
    // Stops, pain, dodges, leaps, traversal and leaving move already reset it.
    if ( note == "turn" && isdefined( self.awz_stride_scaled ) && self.awz_stride_scaled )
    {
        self scragentsetanimscale( 1, 1 );
        self.awz_stride_scaled = 0;
    }
    maps\mp\agents\_scripted_agent_anim_util::set_anim_state( state, index, rate );
    if ( !isdefined( endnote ) )
        endnote = "end";
    maps\mp\agents\_scripted_agent_anim_util::waituntilnotetrack( note, endnote, state, index, callback );
}

mutatoremz_applyemp()
{
    self notify( "applyEmp" );
    self endon( "applyEmp" );
    self endon( "death" );
    self endon( "disconnect" );
    wait 0.05;
    self.empduration = 5;

    if ( isdefined( self.isexotacticalarmoractive ) && self.isexotacticalarmoractive )
        self.empduration = self.empduration - 1.25;

    // A 25% faster reboot takes 1 / 1.25 of the original duration.
    self.empduration /= 1.25;
    println( "[Zombies Balance] EMP reboot duration=" + self.empduration + "s" );

    var_0 = 1;
    maps\mp\_utility::playerallowhighjump( 0, "empgrenade" );
    maps\mp\_utility::playerallowhighjumpdrop( 0, "empgrenade" );
    maps\mp\_utility::playerallowboostjump( 0, "empgrenade" );
    maps\mp\_utility::playerallowpowerslide( 0, "empgrenade" );
    maps\mp\_utility::playerallowdodge( 0, "empgrenade" );
    self playsoundtoplayer( "emp_big_activate", self );
    self.empgrenaded = 1;
    self.empendtime = gettime() + int( self.empduration * 1000 );
    var_1 = maps\mp\gametypes\_scrambler::playersethudempscrambled( self.empendtime, var_0, "emp" );

    if ( !maps\mp\zombies\_util::iszombieshardmode() )
        thread maps\mp\zombies\_mutators::mutatoremz_digitaldistort( self.empduration, var_1 );

    thread maps\mp\zombies\_mutators::mutatoremz_rumbleloop( 0.75 );
    self setempjammed( 1 );
    thread maps\mp\zombies\_zombies_audio::player_emp();
    thread maps\mp\zombies\_mutators::mutatoremz_deathwaiter( var_1 );
    wait( self.empduration );
    self notify( "emzTimedOut" );
    maps\mp\zombies\_mutators::mutatoremz_clearemp( var_1 );
}


mutator_apply( var_0 )
{
    // All mutation entry points, including scripted conversions and dog variants.
    if ( scripts\zm\classic::enabled() )
        return;
    if ( !isdefined( level.activemutators[var_0] ) )
        level.activemutators[var_0] = 0;

    if ( !isdefined( self.activemutators ) )
        self.activemutators = [];

    if ( isdefined( self.activemutators[var_0] ) )
        return;

    if ( isdefined( level.mutators_disabled[self.agent_type] ) )
    {
        if ( isdefined( level.mutators_disabled[self.agent_type][var_0] ) && level.mutators_disabled[self.agent_type][var_0] )
            return;
    }

    if ( var_0 == "emz" )
    {
        if ( isdefined( level.awz_emp_zombie ) && level.awz_emp_zombie.health > 0 )
        {
            level.awz_emp_blocked++;
            return;
        }
        // Reserve before the stock mutation can wait/yield.
        level.awz_emp_zombie = self;
        level.awz_emp_spawned++;
        println( "[Zombies Balance] EMP slot occupied by " + self.agent_type );
    }

    level.activemutators[var_0]++;
    self.activemutators[var_0] = 1;
    self [[ level.mutators[var_0][0] ]]();

    if ( isdefined( self.activemutators ) )
        self.activemutators[var_0] = undefined;

    level.activemutators[var_0]--;
    if ( var_0 == "emz" && isdefined( level.awz_emp_zombie ) && level.awz_emp_zombie == self )
    {
        level.awz_emp_zombie = undefined;
        println( "[Zombies Balance] EMP slot released" );
    }
}

respawnplayerzombies( var_0 )
{
    self notify( "revive" );
    if ( scripts\zm\classic::enabled() && isdefined( self.selfreviveactive ) && self.selfreviveactive )
        scripts\zm\classic::remove_self_revive_perks();
    self.laststand = undefined;
    self.inlaststand = 0;
    self.headicon = "";
    self.health = self.maxhealth;
    self.ignoreme = 0;
    self.ignoremecount = undefined;
    self.zombiesignoreme = 0;
    self.zombiesignoremecount = undefined;
    self.beingrevived = 0;
    self.lastrevivetime = gettime();
    solo_grace = awz_issolo();
    if ( solo_grace )
        maps\mp\zombies\_util::setallignoreme( 1 );

    if ( maps\mp\_utility::_hasperk( "specialty_lightweight" ) )
        self.movespeedscaler = maps\mp\_utility::lightweightscalar();

    self hudoutlinedisable();
    self laststandrevive();
    self setstance( "crouch" );

    if ( var_0 )
        maps\mp\zombies\_zombies_laststand::givebackweaponsfromlaststand();

    if ( var_0 )
        common_scripts\utility::_enableweaponswitch();
    else
        self enableweaponswitch();

    thread maps\mp\zombies\_util::zombieallowallboost( 1, "laststand" );
    self enableweapons();
    common_scripts\utility::_enableusability();
    self enableoffhandweapons();
    maps\mp\gametypes\_weapons::updatemovespeedscale();
    maps\mp\_utility::clearlowermessage( "last_stand" );
    maps\mp\_utility::giveperk( "specialty_pistoldeath", 0 );
    self allowsprint( 1 );

    if ( !canspawn( self.origin ) )
        maps\mp\_movers::unresolved_collision_nearest_node( self, 0 );
    if ( solo_grace )
        thread solo_revive_grace();
}

_giveweapon( var_0, var_1, var_2 )
{
    if ( !isdefined( var_1 ) )
        var_1 = -1;

    var_3 = 0;
    // Stock defaults to magnified (0). Start new hybrid optics zoomed out,
    // but keep the player's saved toggle choice on re-grant.
    attachments = getweaponattachments( var_0 );
    if ( isdefined( attachments ) )
    {
        foreach ( attachment in attachments )
        {
            if ( attachment == "variablereddot" )
                var_3 = 1;
        }
    }

    if ( isdefined( self.pers["toggleScopeStates"] ) && isdefined( self.pers["toggleScopeStates"][var_0] ) )
        var_3 = self.pers["toggleScopeStates"][var_0];

    if ( issubstr( var_0, "variablereddot" ) )
        println( "[Zombies Balance] Hybrid optic grant=" + var_0 + " state=" + var_3 );

    if ( issubstr( var_0, "_akimbo" ) || isdefined( var_2 ) && var_2 == 1 )
    {
        if ( isagent( self ) )
            self giveweapon( var_0, var_1, 1, -1, 0 );
        else
            self giveweapon( var_0, var_1, 1, -1, 0, self, var_3 );
    }
    else if ( isagent( self ) )
        self giveweapon( var_0, var_1, 0, -1, 0 );
    else
        self giveweapon( var_0, var_1, 0, -1, 0, self, var_3 );
}

solo_revive_grace()
{
    self endon( "disconnect" );
    self endon( "death" );
    self endon( "revive" );
    level endon( "game_ended" );
    println( "[Zombies Balance] Solo revive: targeting paused for 2 seconds" );
    wait 2;
    maps\mp\zombies\_util::setallignoreme( 0 );
    println( "[Zombies Balance] Solo revive: targeting grace ended" );
}


getitemcost( var_0 )
{
    if ( var_0 == "specialty_fastreload" )
        return 3000;
    if ( var_0 == "exo_stabilizer" )
        return 2500;
    if ( var_0 == "host_cure" )
        return 500;

    if ( isdefined( level.terminalitems[var_0].costsolo ) && level.players.size == 1 )
        return maps\mp\zombies\_terminals::getitemcostsolo( var_0 );

    var_1 = level.terminalitems[var_0].cost;

    if ( isdefined( level.penaltycostincrease ) )
    {
        for ( var_2 = 0; var_2 < level.penaltycostincrease; var_2++ )
        {
            var_3 = maps\mp\zombies\_util::getincreasedcost( var_1 );
            var_1 = var_3;
        }
    }

    return var_1;
}

zombiegroundslamcommon( var_0, var_1 )
{
    if ( maps\mp\zombies\_terminals::perkterminalhasexoslam() && maps\mp\zombies\_terminals::zombiegroundslamready() )
    {
        var_2 = 100.0;
        var_3 = 250.0;
        var_4 = 0.25;
        var_5 = 1.25;
        var_6 = 100.0;
        var_7 = 300.0;
        var_8 = 6.0;

        if ( isdefined( var_1 ) && !var_1 maps\mp\zombies\_util::instakillimmune() )
        {
            var_1 dodamage( var_1.health, self.origin, self, self, "MOD_TRIGGER_HURT", "boost_slam_mp" );
            playfx( common_scripts\utility::getfx( "gib_full_body" ), var_1.origin, ( 1, 0, 0 ) );
        }

        if ( !isdefined( var_0 ) )
            var_0 = var_2;

        if ( var_0 < var_2 )
            return;

        thread maps\mp\zombies\_terminals::groudslamcooldown( var_8 );
        self.exoslamnextusetime = gettime() + int( var_8 * 1000 );
        println( "[Zombies Balance] Exo Slam cooldown=6s; area damage=2.5x stock" );
        self setclientomnvar( "ui_zm_exo_slam_next_time", self.exoslamnextusetime );
        var_9 = ( var_0 - var_2 ) / ( var_3 - var_2 );
        var_9 = clamp( var_9, 0.0, 1.0 );
        var_10 = ( var_7 - var_6 ) * var_9 + var_6;
        var_11 = level.agentclasses["zombie_generic"].roundhealth;
        self radiusdamage( self.origin, var_10, var_5 * var_11, var_4 * var_11, self, "MOD_EXPLOSIVE", "boost_slam_mp" );
        physicsexplosionsphere( self.origin, var_10, 20, 1 );
        playfx( common_scripts\utility::getfx( "zombie_exo_slam" ), self.origin );
    }
}

dogroundnumenemies( var_0 )
{
    var_1 = maps\mp\zombies\_util::getnumplayers();
    var_2 = var_1 * 8;

    if ( level.specialroundcounter > 3 )
        var_2 = var_1 * 10;

    println( "[Zombies Balance] Dog round=" + level.specialroundcounter + " players=" + var_1 + " dogs=" + var_2 );
    return var_2;
}


laststandselfrevive()
{
    self endon( "disconnect" );
    self setclientomnvar( "ui_use_bar_text", 3 );
    self setclientomnvar( "ui_use_bar_start_time", int( gettime() ) );
    self.curprogress = 0;
    self.userate = 1;
    self.usetime = 6000;
    println( "[Zombies Balance] Self-revive duration=6s" );
    self.selfreviveactive = 1;
    var_0 = -1;

    while ( maps\mp\_utility::isreallyalive( self ) && isdefined( self.laststand ) && !level.gameended )
    {
        if ( var_0 != self.userate )
        {
            if ( self.curprogress > self.usetime )
                self.curprogress = self.usetime;

            if ( self.userate > 0 )
            {
                var_1 = gettime();
                var_2 = self.curprogress / self.usetime;
                var_3 = var_1 + ( 1 - var_2 ) * ( self.usetime / self.userate );
                self setclientomnvar( "ui_use_bar_end_time", int( var_3 ) );
            }

            var_0 = self.userate;
        }

        wait 0.05;
    }

    self.selfreviveactive = 0;
    self setclientomnvar( "ui_use_bar_end_time", 0 );
}

hostroundnumenemies( var_0 )
{
    stock_count = min( 52, var_0 );
    count = int( ceil( stock_count * 0.8 ) );
    println( "[Zombies Balance] Infection round enemies=" + count + " stock=" + stock_count );
    return count;
}
