main()
{
    if ( !scripts\zm\classic::enabled() )
        return;
    // Keep jump-quest geometry initialization, but never start its interaction loop.
    replacefunc( maps\mp\mp_zombie_h2o_sq::jumpquest_run, scripts\zm\classic::disabled );
    replacefunc( maps\mp\mp_zombie_h2o_sq::setuphardmode, scripts\zm\classic::disabled );
    // The round-4 arena preview runs independently of the boss-round selector.
    replacefunc( maps\mp\zombies\zombie_boss_oz::roundstartupdate, scripts\zm\classic::disabled );
    replacefunc( maps\mp\zombies\killstreaks\_zombie_goliath_suit::tryuseheavyexosuit, ::tryuseheavyexosuit );
    println( "[Classic] Descent: boss rounds, jump quest, hard-mode switch and Goliath armor drops disabled" );
}

tryuseheavyexosuit( var_0, var_1 )
{
    return 0;
}
