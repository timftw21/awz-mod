main()
{
    replacefunc( maps\mp\zombies\weapons\_zombie_microwave_gun::getmicrowavemaxammo, ::getmicrowavemaxammo );
    replacefunc( maps\mp\zombies\weapons\_zombie_microwave_gun::setmicrowaveweaponlevel, ::setmicrowaveweaponlevel );
    replacefunc( maps\mp\zombies\_zombies_rewards::reward_weaponupgradethink, ::reward_weaponupgradethink );
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

    if ( self.weaponstate[var_1]["level"] < 10 )
        maps\mp\zombies\_wall_buys::setweaponlevel( self, var_0, self.weaponstate[var_1]["level"] + 1 );
    else if ( self.weaponstate[var_1]["level"] == 10 )
        maps\mp\zombies\_wall_buys::setweaponlevel( self, var_0, 25 );
    else
        return;

    thread maps\mp\zombies\_zombies_audio::playerweaponupgrade( 0, self.weaponstate[var_1]["level"] );
    self.numupgrades++;
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
