main()
{
    if ( !scripts\zm\classic::enabled() )
        return;
    // Burger Town modifies spawn types a second time and has its own spawn loop.
    // Use the common wave loop so no civilian scheduling or special packs survive.
    replacefunc( maps\mp\zombies\_zombies_burgertown_spawning::spawnzombies, maps\mp\zombies\zombies_spawn_manager::spawnzombies );
    // DLC2 schedules the pilot's rescue briefings independently of survivor spawns.
    replacefunc( maps\mp\zombies\_zombies_audio_dlc2::zmbaudiomidroundwavelogic, scripts\zm\classic::disabled );
    replacefunc( maps\mp\zombies\_zombies_audio_dlc2::zmbwaveintermissionvo, ::zmbwaveintermissionvo );
    // Prevent the round controller, gas effects, infection triggers and warnings
    // from starting. The toxic-zone state is used only by this event system.
    replacefunc( maps\mp\mp_zombie_brg::inittoxiczones, scripts\zm\classic::disabled );
    replacefunc( maps\mp\mp_zombie_brg_sq::toilet_interact, scripts\zm\classic::disabled );
    // The gator trap can create this quest pickup outside the stage controller.
    replacefunc( maps\mp\mp_zombie_brg_sq::stage13_spawn_arm, scripts\zm\classic::disabled );
    println( "[Classic] Infection: standard wave spawning; toxic zones, civilian/Goliath rounds and quest interactions disabled" );
    println( "[Classic Audio] Infection: survivor rescue briefings, reminders and responses disabled" );
}

zmbwaveintermissionvo( played )
{
    // Preserve the caller's result so ordinary intermission chatter can still run.
    return played;
}
