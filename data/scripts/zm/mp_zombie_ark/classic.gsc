main()
{
    if ( !scripts\zm\classic::enabled() )
        return;
    // Keep zone/bomb initialization for stock references; never start the event
    // that spawns human soldiers and converts them into infected enemies.
    replacefunc( maps\mp\zombies\_area_invalidation::run_breach_logic, scripts\zm\classic::disabled );
    replacefunc( maps\mp\mp_zombie_ark_sq::runozextras, scripts\zm\classic::disabled );
    println( "[Classic] Carrier: soldier/bomb events and Oz quest interactions disabled" );
}
