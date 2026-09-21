// Classic is selected in the local Solo lobby; a stale selection cannot affect Private Match.
enabled()
{
    return awz_issolo() && getdvarint( "ui_awz_classic" ) == 1;
}

main()
{
    if ( !enabled() )
        return;

    level.awz_round_start_seconds = awz_classicmusic( 0 ) / 1000.0;
    level.awz_round_end_seconds = awz_classicmusic( 1 ) / 1000.0;
    level.awz_dog_round_end_seconds = awz_classicmusic( 3 ) / 1000.0;
    replacefunc( maps\mp\zombies\_zombies_music::changezombiemusic, ::changezombiemusic );
    replacefunc( maps\mp\gametypes\zombies::runroundend, ::runroundend );
    replacefunc( maps\mp\gametypes\zombies::getroundintermissionduration, ::getroundintermissionduration );
    replacefunc( maps\mp\gametypes\zombies::onspawnfinished, ::onspawnfinished );
    replacefunc( maps\mp\zombies\_zombies_laststand::zombieslaststandweapon, ::zombieslaststandweapon );
    replacefunc( maps\mp\zombies\_zombies_laststand::zombieperkbleed, ::remove_downed_perks );
    replacefunc( maps\mp\gametypes\zombies::calculateroundtype, ::calculateroundtype );
    replacefunc( maps\mp\zombies\zombies_spawn_manager::getenemytypetospawn, ::getenemytypetospawn );
    replacefunc( maps\mp\zombies\_terminals::getitemrequiresexo, ::getitemrequiresexo );
    replacefunc( maps\mp\zombies\_terminals::itemhasuses, ::itemhasuses );
    replacefunc( maps\mp\zombies\_terminals::perkterminaltriggerthink, ::perkterminaltriggerthink );
    replacefunc( maps\mp\zombies\_terminals::perkterminalsetexohealth, ::perkterminalsetexohealth );
    replacefunc( maps\mp\zombies\_terminals::perkterminalsetexostabilizer, ::perkterminalsetexostabilizer );
    replacefunc( maps\mp\zombies\_terminals::perkterminalsetexofastreload, ::perkterminalsetexofastreload );
    replacefunc( maps\mp\zombies\_terminals::perkterminalsetexotacticalarmor, ::perkterminalsetexotacticalarmor );
    replacefunc( maps\mp\zombies\_zombies_sidequests::sidequest_start, ::sidequest_start );
    // Both scheduled supply pods and Descent's armor pods honor this flag.
    level.disablecarepackagedrops = 1;
    replacefunc( maps\mp\zombies\killstreaks\_zombie_killstreaks::dropcarepackage, ::disabled );
    replacefunc( maps\mp\zombies\zombie_generic::zombie_generic_think, ::zombie_generic_think );
    println( "[Classic] Enabled: no suit/Slam, suit-free perks, regular zombies/dogs, Mk5/Mk10=5000 each, quests disabled" );
    println( "[Classic] Downing removes perks with stock HUD effects; orbital drops disabled; sprint=70%; team route spreading and idle wandering disabled" );
}

// Use the stock removal listeners so perk effects, saved ammo and HUD order all
// clear together while downed. Medic must remain until stock useexostim starts
// self-revival; that routine consumes Medic and plays its removal effect too.
remove_downed_perks()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    perks = self.zm_perks;
    foreach ( perk in perks )
    {
        if ( perk != "exo_revive" )
            self notify( "take_" + perk );
    }

    // Let the stock removal listeners and Medic consumption finish this frame.
    waitframe();
    println( "[Classic] Downed perk cleanup: before=" + perks.size + "; remaining=" + self.zm_perks.size + "; laststand=" + self.inlaststand + "; max health=" + self.maxhealth );
}

zombie_generic_think()
{
    self endon( "death" );
    level endon( "game_ended" );
    self endon( "owner_disconnect" );
    maps\mp\agents\humanoid\_humanoid::setuphumanoidstate();
    // Stock spawn_humanoid enables route spreading before starting this thread.
    self scragentsetpathteamspread( 0 );
    thread maps\mp\zombies\_zombies::zombieaimonitorthreads();
    thread maps\mp\zombies\_util::waitforbadpath();
    thread maps\mp\zombies\zombie_generic::zombie_generic_moan();
    thread maps\mp\zombies\zombie_generic::zombie_audio_monitor();
    thread maps\mp\zombies\_zombies::updatebuffs();
    thread maps\mp\zombies\_zombies::updatepainsensor();

    if ( level.nextgen )
        interval = 0.05;
    else
        interval = 0.2;

    for (;;)
    {
        if ( maps\mp\zombies\_behavior::humanoid_begin_melee() )
        {
            wait( interval );
            continue;
        }
        if ( maps\mp\zombies\_behavior::humanoid_seek_enemy_melee() )
        {
            wait( interval );
            continue;
        }
        if ( maps\mp\zombies\_behavior::humanoid_seek_enemies_all_known() )
        {
            wait( interval );
            continue;
        }

        // No eligible target (for example during revive grace): stop instead of
        // choosing a random path node. Normal targeting resumes on the next tick.
        self scragentsetgoalpos( self.origin );
        self.bhasnopath = 1;
        wait( interval );
    }
}

// The stock selector only recognizes stock Zombies pistols and falls back to the
// Atlas 45. Use the 1911's upgrade state for both downing and revival cleanup.
zombieslaststandweapon()
{
    weapon = maps\mp\zombies\_wall_buys::getupgradeweaponname( self, "iw5_dlcgun13_mp" );
    println( "[Classic] Last-stand weapon=" + weapon );
    return weapon;
}

onspawnfinished()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );
    self waittill( "applyLoadout" );
    maps\mp\killstreaks\_killstreaks::clearkillstreaks();
    if ( !maps\mp\zombies\_util::isonhumanteam( self ) )
        return;

    starter = "iw5_dlcgun13_mp"; // Base multiplayer 1911; verified against vm_m1911_base.
    maps\mp\gametypes\zombies::createzombieweaponstate( self, starter );
    weapon = maps\mp\zombies\_wall_buys::getupgradeweaponname( self, starter );
    if ( isplayer( self ) )
    {
        if ( isdefined( self.characterindex ) )
            setomnvar( "ui_zm_character_" + self.characterindex + "_alive", 1 );
        self setlethalweapon( "frag_grenade_throw_zombies_mp" );
        self giveweapon( "frag_grenade_throw_zombies_mp" );
        self setweaponammoclip( "frag_grenade_throw_zombies_mp", 4 );
        maps\mp\_utility::giveperk( "specialty_pistoldeath", 0 );
        maps\mp\_utility::giveperk( "specialty_wildcard_duallethals", 0 );
        maps\mp\_utility::giveperk( "specialty_coldblooded", 0 );
        if ( level.wavecounter <= 1 && !isdefined( self.joinedround1 ) )
            self.joinedround1 = 1;
        self.hideondeath = undefined;
        if ( isdefined( self.body ) )
            self.body delete();

        if ( ( !isdefined( self.playedspawnweaponflourish ) || !self.playedspawnweaponflourish ) && ( !isdefined( level.zombieinitialcountdownover ) || !level.zombieinitialcountdownover ) )
        {
            playintroweaponflourish( weapon );
            self.playedspawnweaponflourish = 1;
        }
        else
        {
            maps\mp\gametypes\zombies::waittoloadweapons( [ weapon ] );
            self giveweapon( weapon );
            self setspawnweapon( weapon );
        }
    }
    self givemaxammo( weapon );
    println( "[Classic] Spawn weapon=" + weapon + "; multiplayer 1911 with Zombies upgrade state" );
}

// Keep the stock character animation, timing and control gates; only its final
// weapon changes. The pilot on Carrier/Descent also has a separate idle prop.
playintroweaponflourish( weapon )
{
    self endon( "disconnect" );
    intro = maps\mp\gametypes\zombies::getcharacterintroweaponname();
    weapons = [ weapon, intro ];
    pilot = maps\mp\zombies\_util::getzombieslevelnum() >= 3 && self.characterindex == 3;
    idle = "";
    if ( pilot )
    {
        idle = maps\mp\gametypes\zombies::getcharacterintroidleweapon();
        weapons[2] = idle;
        self hasloadedcustomizationplayerview( self, weapons );
        self giveweapon( idle );
        self switchtoweaponimmediate( idle );
        self disableweaponswitch();
        maps\mp\zombies\_util::playerallowfire( 0, "flourish" );
        maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause( 0.2 );
    }
    else
        maps\mp\gametypes\zombies::waittoloadweapons( weapons );

    thread maps\mp\gametypes\zombies::freezecontrolsduringcharacterintroflourish();
    if ( pilot )
        wait 1;
    else
        maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause( 1 );
    self giveweapon( intro );
    self switchtoweaponimmediate( intro );
    common_scripts\utility::_disableweaponswitch();
    maps\mp\zombies\_util::playerallowfire( 0, "flourish" );
    maps\mp\gametypes\_hostmigration::waitlongdurationwithhostmigrationpause( 3.6 );
    if ( pilot )
        maps\mp\gametypes\zombies::waittoloadweapons( weapons );
    common_scripts\utility::_enableweaponswitch();
    maps\mp\zombies\_util::playerallowfire( 1, "flourish" );
    if ( pilot )
        self takeweapon( idle );
    self takeweapon( intro );
    self giveweapon( weapon );
    self switchtoweaponimmediate( weapon );
    println( "[Classic] Character intro=" + intro + "; finished with " + weapon );
}

// Retain stock music state selection, including map-specific mixing and game-over priority.
changezombiemusic( name, player )
{
    if ( !level.zmb_music_states_active || name == "round_intermission" )
        return;
    state = level.zmb_music_states[name];
    if ( !isdefined( state ) )
        return;
    if ( isdefined( level.old_music_state ) && ( level.old_music_state == state || level.old_music_state == level.zmb_music_states["game_over"] ) )
        return;
    if ( maps\mp\zombies\_util::getzombieslevelnum() == 4 )
        thread maps\mp\zombies\_zombies_music::dimmallmusic( name, player );
    if ( name == "round_start" || name == "round_end" )
    {
        index = 0;
        if ( name == "round_end" )
            index = 1;
        if ( level.roundtype == "zombie_dog" )
            index += 2;
        seconds = awz_classicmusic( index ) / 1000.0;
        if ( name == "round_start" )
        {
            level.awz_round_start_seconds = seconds;
            level.awz_round_music_started = gettime();
        }
        println( "[Classic Audio] " + name + "; type=" + level.roundtype + "; duration=" + seconds + "s" );
    }
    thread playroundmusic( state, player );
    level.old_music_state = state;
}

playroundmusic( state, player )
{
    level endon( "game_ended" );
    if ( state.is_looping )
    {
        level endon( "zombie_wave_ended" );
        if ( isdefined( level.awz_round_music_started ) )
        {
            // The new sting extends into the round. Let it finish before the stock loop starts.
            remaining = level.awz_round_start_seconds + 0.5 - ( gettime() - level.awz_round_music_started ) / 1000.0 - state.start_wait;
            if ( remaining > 0 )
                wait remaining;
        }
    }
    maps\mp\zombies\_zombies_music::_playmusic( state, player );
}

getroundintermissionduration()
{
    // Stock round-end audio has a half-second lead-in.
    if ( level.roundtype == "zombie_dog" )
        return level.awz_dog_round_end_seconds + 0.5;
    return level.awz_round_end_seconds + 0.5;
}

runroundend()
{
    while ( maps\mp\zombies\_util::iszombiegamepaused() )
        waitframe();
    thread maps\mp\zombies\_zombies_music::changezombiemusic( "round_end" );
    level thread maps\mp\gametypes\zombies::revivedownedplayers();
    if ( isdefined( level.roundendfunc[level.roundtype] ) )
        [[ level.roundendfunc[level.roundtype] ]]();
    maps\mp\zombies\weapons\_zombie_weapons::givegrenadesafterrounds();
    level maps\mp\zombies\_util::recordmatchdataforroundend( level.wavecounter - 1 );
    duration = getroundintermissionduration();
    println( "[Classic Audio] Round intermission=" + duration + "s; stock rewards/respawns retained" );
    wait duration;
}

calculateroundtype()
{
    type = "normal";
    if ( maps\mp\zombies\_util::isspecialround() )
        type = "zombie_dog";
    println( "[Classic] Round=" + level.wavecounter + "; type=" + type );
    return type;
}

getenemytypetospawn( index, count )
{
    if ( level.roundtype == "zombie_dog" )
        return "zombie_dog";
    return "zombie_generic";
}

getitemrequiresexo( item )
{
    return 0;
}

itemhasuses( item )
{
    if ( item == "exo_suit" || item == "exo_slam" )
        return 0;
    limit = maps\mp\zombies\_terminals::getitemmaxbuys( item );
    return limit < 0 || limit > maps\mp\zombies\_terminals::getitemnumbuys( item );
}

perkterminaltriggerthink()
{
    if ( self.itemtype == "exo_suit" || self.itemtype == "exo_slam" )
    {
        // Keep map-owned entities intact; stock hints honor terminaldisabled and
        // stock lighting honors itemhasuses. The transaction check also rejects gifts/tokens.
        self.terminaldisabled = 1;
        self sethintstring( "" );
        self setsecondaryhintstring( "" );
        println( "[Classic] Terminal disabled: " + self.itemtype );
    }
    else
    {
        thread maps\mp\zombies\_terminals::perkterminalupdate();
        thread maps\mp\zombies\_terminals::perkterminalusethink();
    }
    waitframe();
    if ( !maps\mp\zombies\_util::isusetriggerprimary( self ) )
        return;
    thread maps\mp\zombies\_terminals::perkterminalplayercountwatch();
    thread maps\mp\zombies\_terminals::perkterminalpowerwatch();
    thread maps\mp\zombies\_terminals::perkterminalupdatefx();
}

// Grant/register the perk immediately; the cosmetic animation runs separately
// so downing during playback still removes the newly bought perk.
perkterminalsetexohealth( item, buyer )
{
    self.maxhealth = 200;
    self.health = 200;
    thread scripts\zm\balance::perk_flourish( item );
}

perkterminalsetexostabilizer( item, buyer )
{
    maps\mp\_utility::giveperk( "specialty_bulletaccuracy", 0 );
    maps\mp\_utility::giveperk( "specialty_sprintfire", 0 );
    maps\mp\_utility::giveperk( "specialty_quickswap", 0 );
    maps\mp\_utility::giveperk( "specialty_fastoffhand", 0 );
    thread scripts\zm\balance::perk_flourish( item );
}

perkterminalsetexofastreload( item, buyer )
{
    maps\mp\_utility::giveperk( "specialty_fastreload", 0 );
    maps\mp\_utility::giveperk( "specialty_sprintreload", 0 );
    thread scripts\zm\balance::perk_flourish( item );
}

perkterminalsetexotacticalarmor( item, buyer )
{
    maps\mp\_utility::giveperk( "specialty_stockpile", 0 );
    maps\mp\_utility::giveperk( "specialty_extralethal", 0 );
    maps\mp\_utility::giveperk( "specialty_extratactical", 0 );
    thread scripts\zm\balance::perk_flourish( item );
}

sidequest_start( name )
{
    // Preserve initial map state (e.g. Burger Town's hidden quest objects/locked
    // rooms), but do not build interactive quest assets or start quest logic.
    quest = level._zombie_sidequests[name];
    if ( isdefined( quest.init_func ) )
        quest [[ quest.init_func ]]();
    println( "[Classic] Quest disabled: " + name );
}

disabled()
{
}
