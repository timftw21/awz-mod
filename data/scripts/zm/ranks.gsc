main()
{
    // Keep multiplayer's challenge entry point, targets and tier states, but
    // use the co-op profile and Zombies events instead of ranked-match rules.
    replacefunc( maps\mp\gametypes\_missions::processchallenge, ::processchallenge );
    replacefunc( maps\mp\zombies\_util::enemykilled, ::enemy_killed );
}

init()
{
    if ( !awz_progressionavailable() )
    {
        println( "[Zombies Ranks] Disabled: unsupported co-op profile layout" );
        return;
    }

    // Custom init can run before callback_startgametype starts _persistence.
    while ( !isdefined( level.ranktable ) || !isdefined( level.challengeinfo ) ) waitframe();
    level.awz_gate_table = "mp/awzGateChallenges.csv";
    level.awz_gate_refs = [];
    for ( row = 1; row <= 15; row++ )
    {
        ref = tablelookupbyrow( level.awz_gate_table, row, 0 );
        target = int( tablelookupbyrow( level.awz_gate_table, row, 9 ) );
        if ( ref == "" || target <= 0 )
        {
            println( "[Zombies Ranks] Disabled: invalid Gate Challenge at row " + row );
            return;
        }
        level.awz_gate_refs[row - 1] = ref;
        // These are single-tier challenges. Build the multiplayer challenge
        // record directly from its CSV row, including the required tier target.
        level.challengeinfo[ref] = [];
        level.challengeinfo[ref]["index"] = row;
        level.challengeinfo[ref]["type"] = 2;
        level.challengeinfo[ref]["targetval"][1] = target;
        level.challengeinfo[ref]["reward"][1] = 0;
        level.challengeinfo[ref]["parent_challenge"] = "";
        level.challengeinfo[ref]["awz_index"] = row - 1;
        level.challengeinfo[ref]["awz_level"] = int( tablelookupbyrow( level.awz_gate_table, row, 6 ) );
        level.challengeinfo[ref]["awz_event"] = tablelookupbyrow( level.awz_gate_table, row, 44 );
        println( "[Zombies Ranks] Challenge loaded: " + ref + " target=" + target );
    }
    level thread on_connect();
    level thread watch_rounds();
    foreach ( player in level.players )
        player thread initialize_player();
    println( "[Zombies Ranks] MP rank curve and 30 prestiges; three challenges per gate; XP banks at 10/20/30/40/50" );
}

// Bytes 0..255 remain stock. Native profile extension owns bytes 256..303.
// 256: magic; 257: version; 258: prestige; 260..263: XP;
// 264..293: fifteen little-endian challenge counters. States are derived.
// 294..297: banked XP, persisted across matches in the existing extension.
read_value( offset, bytes )
{
    value = 0;
    multiplier = 1;
    for ( i = 0; i < bytes; i++ )
    {
        value += self getcoopplayerdata( "reserved", offset + i ) * multiplier;
        multiplier *= 256;
    }
    return value;
}

write_value( offset, bytes, value )
{
    value = int( value );
    for ( i = 0; i < bytes; i++ )
    {
        self setcoopplayerdata( "reserved", offset + i, value % 256 );
        value = int( value / 256 );
    }
}

on_connect()
{
    for (;;)
    {
        level waittill( "connected", player );
        player thread initialize_player();
    }
}

initialize_player()
{
    self endon( "disconnect" );
    if ( isbot( self ) || isdefined( self.awz_initializing_rank ) ) return;
    self.awz_initializing_rank = 1;
    // The stock connection threads load the profile and initialize pers first.
    if ( !isdefined( self.headshotkills ) || !isalive( self ) ) self waittill( "spawned_player" );
    waittillframeend;
    if ( self getcoopplayerdata( "reserved", 256 ) != 167 )
    {
        for ( i = 256; i < 304; i++ ) self setcoopplayerdata( "reserved", i, 0 );
        self setcoopplayerdata( "reserved", 257, 1 );
        self setcoopplayerdata( "reserved", 256, 167 );
        println( "[Zombies Ranks] Created co-op rank profile for player " + self getentitynumber() );
    }
    if ( self getcoopplayerdata( "reserved", 257 ) != 1 )
    {
        println( "[Zombies Ranks] Unsupported profile version; preserved data for player " + self getentitynumber() );
        return;
    }
    self.awz_xp = int( max( 0, read_value( 260, 4 ) ) );
    self.awz_banked_xp = int( max( 0, read_value( 294, 4 ) ) );
    self.awz_prestige = int( min( self getcoopplayerdata( "reserved", 258 ), int( tablelookup( "mp/rankIconTable.csv", 0, "maxprestige", 1 ) ) ) );
    self.awz_progress = [];
    for ( i = 0; i < 15; i++ )
    {
        ref = level.awz_gate_refs[i];
        self.awz_progress[ref] = int( min( read_value( 264 + i * 2, 2 ), level.challengeinfo[ref]["targetval"][1] ) );
        self.challengedata[ref] = 1 + ( self.awz_progress[ref] == level.challengeinfo[ref]["targetval"][1] );
    }
    limit = xp_limit();
    self.awz_banked_xp += int( max( 0, self.awz_xp - limit ) );
    self.awz_xp = int( min( self.awz_xp, limit ) );
    write_value( 294, 4, self.awz_banked_xp );
    write_value( 260, 4, self.awz_xp );
    self.awz_rank = maps\mp\gametypes\_rank::getrankforxp( self.awz_xp );
    sync_rank();
    if ( isdefined( self.clientid ) && self.clientid < level.maxlogclients )
        setmatchdata( "players", self.clientid, "rankAtStart", self.awz_rank );
    println( "[Zombies Ranks] Loaded player=" + self getentitynumber() + " level=" + ( self.awz_rank + 1 ) + " prestige=" + self.awz_prestige + " xp=" + self.awz_xp + " banked=" + self.awz_banked_xp + " gate=" + active_gate() );
}

gate_complete( gate )
{
    first = ( int( gate / 10 ) - 1 ) * 3;
    for ( i = first; i < first + 3; i++ )
    {
        ref = level.awz_gate_refs[i];
        if ( self.awz_progress[ref] < level.challengeinfo[ref]["targetval"][1] ) return 0;
    }
    return 1;
}

xp_limit()
{
    for ( gate = 10; gate <= 50; gate += 10 )
        if ( !gate_complete( gate ) ) return maps\mp\gametypes\_rank::getrankinfominxp( gate - 1 );
    return maps\mp\gametypes\_rank::getrankinfomaxxp( level.maxrank );
}

active_gate()
{
    for ( gate = 10; gate <= 50; gate += 10 )
        if ( !gate_complete( gate ) )
        {
            if ( self.awz_xp >= maps\mp\gametypes\_rank::getrankinfominxp( gate - 1 ) ) return gate;
            return 0;
        }
    return 0;
}

sync_rank()
{
    self.pers["rank"] = self.awz_rank;
    self.pers["rankxp"] = self.awz_xp;
    self.pers["prestige"] = self.awz_prestige;
    self setrank( self.awz_rank, self.awz_prestige );
    if ( isdefined( self.clientid ) && self.clientid < level.maxlogclients )
    {
        setmatchdata( "players", self.clientid, "rankAtEnd", self.awz_rank );
        setmatchdata( "players", self.clientid, "Prestige", self.awz_prestige );
    }
    publish_match_ranks();
}

publish_match_ranks()
{
    // Zombies client match-data rows use entity numbers. Its stock schema has
    // no rank/prestige fields, so retain this authoritative snapshot for AAR.
    snapshot = "";
    foreach ( player in level.players )
        if ( isdefined( player.awz_rank ) )
            snapshot += ( player getentitynumber() ) + ":" + player.awz_rank + ":" + player.awz_prestige + ",";
    foreach ( viewer in level.players )
    {
        if ( isbot( viewer ) || isdefined( viewer.awz_match_rank_snapshot ) && viewer.awz_match_rank_snapshot == snapshot ) continue;
        viewer setclientdvar( "ui_awz_match_ranks", snapshot );
        viewer.awz_match_rank_snapshot = snapshot;
    }
    if ( !isdefined( level.awz_match_rank_snapshot ) || level.awz_match_rank_snapshot != snapshot )
    {
        level.awz_match_rank_snapshot = snapshot;
        println( "[Zombies Ranks] Match rank snapshot: " + snapshot );
    }
}

award_xp( amount )
{
    if ( !isdefined( self.awz_xp ) || level.gameended ) return;
    amount = int( max( 0, amount ) );
    previous = self.awz_xp;
    self.awz_xp = int( min( previous + amount, xp_limit() ) );
    excess = previous + amount - self.awz_xp;
    if ( excess > 0 && active_gate() )
    {
        // Never bank more than the remaining XP in this prestige.
        capacity = maps\mp\gametypes\_rank::getrankinfomaxxp( level.maxrank ) - self.awz_xp;
        self.awz_banked_xp = int( min( self.awz_banked_xp + excess, capacity ) );
        write_value( 294, 4, self.awz_banked_xp );
        println( "[Zombies Ranks] XP banked; player=" + self getentitynumber() + " gate=" + active_gate() + " earned=" + excess + " banked=" + self.awz_banked_xp );
    }
    if ( previous == self.awz_xp ) return;
    write_value( 260, 4, self.awz_xp );
    rank = maps\mp\gametypes\_rank::getrankforxp( self.awz_xp );
    if ( rank != self.awz_rank )
    {
        self.awz_rank = rank;
        self thread maps\mp\gametypes\_hud_message::rankupsplashnotify( "ranked_up", rank, self.awz_prestige );
        println( "[Zombies Ranks] Promotion player=" + self getentitynumber() + " level=" + ( rank + 1 ) + " prestige=" + self.awz_prestige + " xp=" + self.awz_xp );
        gate = active_gate();
        if ( gate )
        {
            println( "[Zombies Ranks] XP banking; player=" + self getentitynumber() + " gate=" + gate );
        }
    }
    sync_rank();
}

release_banked_xp()
{
    amount = int( min( self.awz_banked_xp, xp_limit() - self.awz_xp ) );
    if ( amount <= 0 ) return;
    self.awz_banked_xp -= amount;
    write_value( 294, 4, self.awz_banked_xp );
    award_xp( amount );
    // The same multiplayer challenge queue handles the amount and its sound.
    splash = spawnstruct();
    splash.name = "ch_awz_banked_xp";
    splash.type = "challenge_splash";
    // Both challenge payload omnvars are 16-bit. Preserve larger payouts.
    splash.challengetier = int( amount / 65536 ) + 1;
    splash.optionalnumber = amount % 65536;
    splash.sound = "mp_s1_challenge_complete";
    splash.slot = 0;
    self thread maps\mp\gametypes\_hud_message::actionnotify( splash );
    println( "[Zombies Ranks] Banked XP awarded; player=" + self getentitynumber() + " awarded=" + amount + " remaining=" + self.awz_banked_xp + " gate=" + active_gate() );
}

// Adapted from _missions::processchallenge: a counter advances the current
// target tier once. Only active Zombies gates write to the co-op profile.
processchallenge( ref, amount, set_value )
{
    if ( !isdefined( self.awz_xp ) || level.gameended || !isdefined( level.challengeinfo[ref] ) || !isdefined( level.challengeinfo[ref]["awz_index"] ) ) return;
    info = level.challengeinfo[ref];
    if ( active_gate() != info["awz_level"] ) return;
    target = info["targetval"][1];
    previous = self.awz_progress[ref];
    if ( previous >= target ) return;
    if ( !isdefined( amount ) ) amount = 1;
    value = previous + max( 0, amount );
    if ( isdefined( set_value ) && set_value ) value = max( previous, amount );
    value = int( min( value, target ) );
    if ( previous == value ) return;
    self.awz_progress[ref] = value;
    write_value( 264 + info["awz_index"] * 2, 2, value );
    self.challengedata[ref] = 1;
    if ( value == target )
    {
        self.challengedata[ref] = 2;
        self thread maps\mp\gametypes\_hud_message::challengesplashnotify( ref, 1, 2 );
        println( "[Zombies Ranks] Challenge complete; player=" + self getentitynumber() + " ref=" + ref + " target=" + target );
        if ( gate_complete( info["awz_level"] ) )
        {
            println( "[Zombies Ranks] Gate cleared; player=" + self getentitynumber() + " level=" + info["awz_level"] );
            release_banked_xp();
        }
    }
}

challenge_event( event, gate )
{
    if ( !gate ) return;
    first = ( int( gate / 10 ) - 1 ) * 3;
    for ( i = first; i < first + 3; i++ )
    {
        ref = level.awz_gate_refs[i];
        if ( level.challengeinfo[ref]["awz_event"] == event )
            maps\mp\gametypes\_missions::processchallenge( ref, 1 );
    }
}

enemy_killed( inflictor, attacker, damage, mod, weapon, direction, hitloc, offset, extra )
{
    // Preserve _util::enemykilled, including the map's replaceable quest callback.
    // Outbreak and Descent install/remove that callback during quests, so it
    // cannot own persistent rank tracking.
    level.lastenemydeathpos = self.origin;
    level thread maps\mp\gametypes\zombies::chancetospawnpickup( attacker, self, mod, weapon );
    if ( isdefined( attacker ) && isplayer( attacker ) )
    {
        attacker thread maps\mp\zombies\_zombies_audio::player_kill_zombie( hitloc, mod, weapon, self );
        if ( !level.gameended )
        {
            attacker maps\mp\_utility::incplayerstat( "kills", 1 );
            attacker maps\mp\_utility::incpersstat( "kills", 1 );
            attacker.kills = attacker maps\mp\_utility::getpersstat( "kills" );
            attacker maps\mp\gametypes\_persistence::statsetchild( "round", "kills", attacker.kills );
        }
    }
    if ( isdefined( attacker ) ) attacker notify( "killed_enemy" );
    if ( isdefined( level.processenemykilledfunc ) )
        self thread [[ level.processenemykilledfunc ]]( inflictor, attacker, damage, mod, weapon, direction, hitloc, offset, extra );

    if ( !isdefined( attacker ) || !isplayer( attacker ) || !isdefined( attacker.awz_xp ) || level.gameended || isdefined( self.awz_rank_credited ) ) return;
    self.awz_rank_credited = 1;
    gate = attacker active_gate();
    attacker challenge_event( "kills", gate );
    xp = 50;
    if ( maps\mp\_utility::isheadshot( weapon, hitloc, mod, attacker ) )
    {
        attacker challenge_event( "headshots", gate );
        xp += 25;
    }
    if ( ( maps\mp\_utility::ismeleemod( mod ) || mod == "MOD_IMPACT" ) && !maps\mp\zombies\_util::istrapweapon( weapon ) )
    {
        attacker challenge_event( "melee", gate );
        xp += 25;
    }
    attacker award_xp( xp );
}

watch_rounds()
{
    level endon( "game_ended" );
    for (;;)
    {
        level waittill( "zombie_wave_started" );
        foreach ( player in level.players )
        {
            player.awz_wave_gate = 0;
            player.awz_wave_eligible = isdefined( player.awz_xp ) && isalive( player ) && !maps\mp\zombies\_util::isplayerinlaststand( player );
            if ( player.awz_wave_eligible )
            {
                player.awz_wave_gate = player active_gate();
                player.awz_wave_downs = player.numberofdowns;
                player.awz_wave_bleedouts = player.numberofbleedouts;
            }
        }
        level waittill( "zombie_wave_ended" );
        foreach ( player in level.players )
        {
            if ( !isdefined( player.awz_wave_eligible ) || !player.awz_wave_eligible || !isalive( player ) || player.numberofbleedouts != player.awz_wave_bleedouts || maps\mp\zombies\_util::isplayerinlaststand( player ) ) continue;
            player challenge_event( "rounds", player.awz_wave_gate );
            if ( player.numberofdowns == player.awz_wave_downs )
                player challenge_event( "flawless", player.awz_wave_gate );
            player award_xp( 250 );
            println( "[Zombies Ranks] Round=" + level.wavecounter + " player=" + player getentitynumber() + " xp=" + player.awz_xp + " gate=" + player active_gate() );
        }
    }
}
