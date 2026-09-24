main()
{
    replacefunc( maps\mp\zombies\_util::clearzombiestats, ::clearzombiestats );
    println( "[Zombies Career] Preserving cumulative revives, kills, headshots and credits across matches" );
}

// Stock writezombieplayerstats already adds each completed match to these
// fields. Keep the four career counters instead of clearing them on connection.
// Other counters retain their stock per-match reset behavior.
clearzombiestats( player )
{
    if ( isdefined( level.dlcleaderboardnumber ) && level.dlcleaderboardnumber >= 2 && level.dlcleaderboardnumber <= 4 )
    {
        prefix = "dlc" + level.dlcleaderboardnumber;
        player setcoopplayerdatareservedint( prefix + "Rounds", 0 );
        player setcoopplayerdatareservedint( prefix + "TimePlayed", 0 );
        player setcoopplayerdatareservedint( prefix + "MeleeKills", 0 );

        if ( level.dlcleaderboardnumber == 2 )
            player setcoopplayerdatareservedint( prefix + "Civilians", 0 );
        if ( level.dlcleaderboardnumber == 3 )
            player setcoopplayerdatareservedint( prefix + "Bombs", 0 );
    }
    else
    {
        player setcoopplayerdata( "totalRounds", 0 );
        player setcoopplayerdata( "totalMoneySpent", 0 );
        player setcoopplayerdata( "totalMagicBox", 0 );
        player setcoopplayerdata( "totalTraps", 0 );
        player setcoopplayerdata( "totalMeleeKills", 0 );
        player setcoopplayerdatareservedint( "totalTimePlayed", 0 );
    }
    println( "[Zombies Career] Retained career totals on " + getdvar( "mapname" ) + " for player " + player getentitynumber() );
}
