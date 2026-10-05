main()
{
    replacefunc( maps\mp\zombies\_zombies_sidequests::fake_use, ::fake_use );
    replacefunc( maps\mp\mp_zombie_lab_sq::stage4_run_incinerator, ::stage4_run_incinerator );
    replacefunc( maps\mp\mp_zombie_lab_sq::badgepickup, ::badgepickup );
    replacefunc( maps\mp\mp_zombie_lab_sq::badgeshowtoplayers, ::badgeshowtoplayers );
    replacefunc( maps\mp\mp_zombie_lab_sq::removebadge, ::removebadge );
    replacefunc( maps\mp\mp_zombie_lab_sq::setupweaponstationblocker, ::setupweaponstationblocker );
    replacefunc( maps\mp\mp_zombie_lab_sq::stage10_end, ::stage10_end );
    level.awz_outbreak_station_unlocked = 0;
    println( "[Outbreak Quest] Computer: 96-unit horizontal/vertical reach, 60-degree facing tolerance, input checked every frame; incinerator glint=red; dropped badges=red glow/first-four pickup sound" );
    println( "[Outbreak Quest] Mk 25 station: saved main quest completion restores unlock; purchase and hint cost=3000 credits" );
}

init()
{
    if ( scripts\zm\classic::enabled() )
        return;
    level thread restore_station_unlock();
}

fake_use( event, validate, argument, stop_event, radius, facing_3d )
{
    if ( isdefined( stop_event ) )
        level endon( stop_event );

    level endon( "game_ended" );
    waittillframeend;

    if ( !isdefined( radius ) )
        radius = 64;
    if ( !isdefined( facing_3d ) )
        facing_3d = 0;

    // All computer stages and reminder dialogue share this exact use struct.
    // Other quest objects retain the stock radius, facing checks and polling.
    computer = self == common_scripts\utility::getstruct( "blackbox2Use", "targetname" );
    range_squared = radius * radius;

    for (;;)
    {
        if ( !isdefined( self ) )
            return;

        foreach ( player in level.players )
        {
            if ( computer )
            {
                if ( !isalive( player ) || maps\mp\zombies\_util::isplayerinlaststand( player ) || !player usebuttonpressed() || !player can_use_computer( self ) )
                    continue;
            }
            else
            {
                if ( distancesquared( self.origin, player.origin ) >= range_squared )
                    continue;
                if ( !facing_3d && !player maps\mp\zombies\_zombies_sidequests::is_facing( self ) || facing_3d && !player maps\mp\zombies\_zombies_sidequests::is_facing_3d( self ) )
                    continue;
                if ( !player usebuttonpressed() )
                    continue;
            }

            allowed = 1;
            if ( isdefined( validate ) && isdefined( argument ) )
                allowed = player [[ validate ]]( argument );
            else if ( isdefined( validate ) )
                allowed = player [[ validate ]]();

            if ( allowed )
            {
                if ( computer )
                    println( "[Outbreak Quest] Computer used: player=" + player getentitynumber() + "; stage=" + stop_event + "; distance=" + distance2d( self.origin, player.origin ) );
                self notify( event, player );
                return player;
            }
        }

        if ( computer )
            waitframe();
        else
            wait 0.1;
    }
}

can_use_computer( computer )
{
    // A sphere measured from the player's feet loses most of its reach when
    // the use point is on a raised console. Measure horizontal/vertical reach
    // separately, and allow aiming at the screen rather than a tiny point.
    if ( distance2d( self.origin, computer.origin ) >= 96 || abs( self.origin[2] - computer.origin[2] ) >= 96 )
        return 0;

    // This client's compiler names stock player-view builtin 0x833B getangles.
    forward = anglestoforward( self getangles() );
    forward = vectornormalize( ( forward[0], forward[1], 0 ) );
    direction = computer.origin - self.origin;
    direction = vectornormalize( ( direction[0], direction[1], 0 ) );
    return vectordot( forward, direction ) > 0.5;
}

stage4_run_incinerator()
{
    duration = 30;
    level.incinerator_active = 1;
    level notify( "incinerator_start" );
    level thread maps\mp\mp_zombie_lab_sq::stage4_incinerator_ground();
    level thread incinerator_hint();
    wait 3;
    level thread maps\mp\mp_zombie_lab_sq::stage4_incinerator_pusher( duration );
    wait( duration );
    maps\mp\mp_zombie_lab_sq::stage4_activate_all_teleporters();
    wait 1;
    maps\mp\mp_zombie_lab_sq::stage4_double_check_players_out();
    level.incinerator_active = 0;
    level notify( "incinerator_end" );
}

incinerator_hint()
{
    level endon( "game_ended" );
    key = level.incinerator_key;
    if ( !isdefined( key ) || !key.hidden )
        return;

    // Use the map's precached small light, positioned at the actual random
    // hiding spot. A separate FX entity stays visible while the badge is hidden.
    hint = spawnfx( level.chopper_fx["light"]["warbird"], key.origin + ( 0, 0, 3 ) );
    triggerfx( hint );
    println( "[Outbreak Quest] Red incinerator badge glint started at " + key.origin );

    while ( level.incinerator_active && isdefined( key ) && key.hidden )
        waitframe();

    hint delete();
    println( "[Outbreak Quest] Incinerator badge glint removed after reveal, pickup or room exit" );
}

badgepickup()
{
    self endon( "deleted" );
    for (;;)
    {
        self.trigger waittill( "trigger", player );
        if ( isplayer( player ) && !player maps\mp\mp_zombie_lab_sq::playerisbadgeupgradedstage7() )
        {
            player maps\mp\mp_zombie_lab_sq::playerincrementbadge();
            player playlocalsound( "ee_badge_collected" );
            println( "[Outbreak Quest] Zombie badge collected: player=" + player getentitynumber() + "; badge count=" + player maps\mp\mp_zombie_lab_sq::playergetbadgecount() + "; sound=ee_badge_collected" );
            level.pickedupbadges = 1;
            thread removebadge( self );
            return;
        }
    }
}

badgeshowtoplayers()
{
    self hide();
    self.trigger hide();
    self.awz_glows = [];
    foreach ( player in level.players )
    {
        if ( !player maps\mp\mp_zombie_lab_sq::playerisbadgeupgradedstage7() )
        {
            self showtoplayer( player );
            // A small red light uses the same visibility as the collectible.
            glow = spawnfxforclient( level.chopper_fx["light"]["warbird"], self.origin + ( 0, 0, 3 ), player );
            triggerfx( glow );
            self.awz_glows[self.awz_glows.size] = glow;
        }
    }
    println( "[Outbreak Quest] Dropped badge red glow at " + self.origin + "; eligible players=" + self.awz_glows.size );
}

removebadge( badge, stage_ended )
{
    // The last pickup and stage completion can both remove the same badge.
    if ( !isdefined( badge ) || maps\mp\zombies\_util::is_true( badge.awz_removing ) )
        return;
    badge.awz_removing = 1;
    badge notify( "deleted" );
    if ( isdefined( badge.awz_glows ) )
    {
        foreach ( glow in badge.awz_glows )
        {
            if ( isdefined( glow ) )
                glow delete();
        }
    }
    waitframe();
    if ( isdefined( badge.trigger ) )
        badge.trigger delete();
    badge delete();
    if ( !maps\mp\zombies\_util::is_true( stage_ended ) && isdefined( level.sq_droppedbadges ) )
        level.sq_droppedbadges = common_scripts\utility::array_removeundefined( level.sq_droppedbadges );
}

restore_station_unlock()
{
    level endon( "game_ended" );
    level endon( "special_weapon_box_unlocked" );
    for (;;)
    {
        if ( isdefined( level.players ) )
        {
            foreach ( player in level.players )
            {
                // Co-op data is loaded by the stock connection/spawn flow.
                if ( !isalive( player ) || isbot( player ) )
                    continue;
                flags = player getcoopplayerdatareservedint( "eggData" );
                if ( flags & 1 )
                {
                    println( "[Outbreak Quest] Restoring saved completion: player=" + player getentitynumber() + "; eggData=" + flags );
                    // Run separately: this monitor ends on the unlock notify.
                    level thread unlock_station();
                    return;
                }
            }
        }
        wait 0.25;
    }
}

setupweaponstationblocker()
{
    blocker = getent( "weapon_upgrade_blocker_model", "targetname" );
    if ( !isdefined( blocker ) )
        return;
    if ( isdefined( blocker.target ) )
    {
        collision = getent( blocker.target, "targetname" );
        if ( isdefined( collision ) )
            collision linktosynchronizedparent( blocker );
    }
    waitframe();
    blocker.offsetmove = 76;
    if ( !level.awz_outbreak_station_unlocked )
        blocker.origin = blocker.origin + ( 0, 0, -blocker.offsetmove );
    println( "[Outbreak Quest] Mk 25 station blocker initialized; unlocked=" + level.awz_outbreak_station_unlocked );
}

unlock_station()
{
    if ( level.awz_outbreak_station_unlocked )
        return;
    level.awz_outbreak_station_unlocked = 1;
    blocker = getent( "weapon_upgrade_blocker_model", "targetname" );
    if ( isdefined( blocker ) && isdefined( blocker.offsetmove ) )
        blocker moveto( blocker.origin + ( 0, 0, blocker.offsetmove ), 2, 0.5, 0.5 );
    level notify( "special_weapon_box_unlocked" );
    println( "[Outbreak Quest] Mk 25 station unlocked; credits=3000" );
}

stage10_end( completed )
{
    unlock_station();
    foreach ( player in level.players )
        player.usedexoterminalsq = undefined;
    maps\mp\zombies\_zombies_sidequests::sidequest_iprintlnbold( "Super weapon upgrade station unlocked." );
}
