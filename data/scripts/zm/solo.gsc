// Choose the stock character before model, voice and HUD assignment, including
// Carrier's map-specific assignment/spawn-zone path. Private Match stays stock.
main()
{
    if ( !awz_issolo() )
        return;

    level.awz_solo_character = getdvarint( "ui_awz_solo_character" );
    if ( level.awz_solo_character < 0 || level.awz_solo_character > 3 )
        level.awz_solo_character = 0;

    replacefunc( maps\mp\gametypes\zombies::onplayerconnectzombies, ::onplayerconnectzombies );
    println( "[Solo] Stock character assignment override installed; index=" + level.awz_solo_character );
}

onplayerconnectzombies()
{
    for (;;)
    {
        level waittill( "connected", var_0 );
        var_0 thread maps\mp\zombies\_zombies_audio::init_audio_functions();
        var_0 thread maps\mp\gametypes\zombies::playermonitorweapon();
        var_0 thread maps\mp\gametypes\zombies::playermonitorboostevents();
        var_0 thread maps\mp\gametypes\zombies::playermonitortokenuse();
        var_0 thread maps\mp\gametypes\zombies::playermonitorlastgroundpos();
        level thread maps\mp\gametypes\zombies::createplayervariables( var_0 );
        var_1 = level.awz_solo_character;

        if ( isdefined( level.givecustomcharacters ) )
            var_0 [[ level.givecustomcharacters ]]( var_1 );
        else
            var_0 maps\mp\zombies\_util::givecustomcharactersdefault( var_1 );

        println( "[Solo] Spawn character assigned; requested=" + var_1 + "; actual=" + var_0.characterindex );
        if ( isbot( var_0 ) )
            continue;
    }
}
