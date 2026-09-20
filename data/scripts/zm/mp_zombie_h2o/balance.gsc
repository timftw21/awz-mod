main()
{
    replacefunc( maps\mp\mp_zombie_h2o_sq::playerrewardweaponupgrade, ::playerrewardweaponupgrade );
    replacefunc( maps\mp\mp_zombie_h2o_sq::setweaponlevelallowthird, ::setweaponlevelallowthird );
}

playerrewardweaponupgrade()
{
    self endon( "death" );
    self endon( "disconnect" );
    level endon( "game_ended" );

    while ( maps\mp\zombies\_util::is_true( self.sqawardingweaponupgrade ) )
        wait 0.1;

    self.sqawardingweaponupgrade = 1;
    var_0 = maps\mp\gametypes\_hud_util::createprimaryprogressbartext( 0, 185 );
    var_0 settext( &"ZOMBIE_H2O_SQ_WPN_UPGRADE" );
    var_0.fontscale = 0.65;
    var_1 = maps\mp\gametypes\_hud_util::createprimaryprogressbartext( 0, 205 );
    var_1 thread maps\mp\mp_zombie_h2o_sq::update_countdown( self );
    var_1.fontscale = 1;
    common_scripts\utility::waittill_any( "timer_countdown_complete" );
    var_1 maps\mp\gametypes\_hud_util::destroyelem();
    var_0 maps\mp\gametypes\_hud_util::destroyelem();

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

    var_2 = maps\mp\zombies\_util::getplayerweaponzombies( self );
    var_3 = getweaponbasename( var_2 );

    if ( !maps\mp\zombies\_util::haszombieweaponstate( self, var_3 ) )
    {
        self.sqawardingweaponupgrade = undefined;
        return;
    }

    if ( self.weaponstate[var_3]["level"] < 10 )
        maps\mp\zombies\_wall_buys::setweaponlevel( self, var_2, self.weaponstate[var_3]["level"] + 1 );
    else if ( self.weaponstate[var_3]["level"] == 10 )
        maps\mp\zombies\_wall_buys::setweaponlevel( self, var_2, 25 );
    else
    {
        self.sqawardingweaponupgrade = undefined;
        return;
    }

    thread maps\mp\zombies\_zombies_audio::playerweaponupgrade( 0, self.weaponstate[var_3]["level"] );
    self.sqawardingweaponupgrade = undefined;
}

setweaponlevelallowthird( var_0, var_1, var_2 )
{
    var_0 takeweapon( var_1 );
    var_3 = getweaponbasename( var_1 );
    var_0.weaponstate[var_3]["level"] = var_2;
    var_0.weaponstate[var_3]["weapon_level_increase"] = scripts\zm\balance::damage_increment( var_2 );
    var_4 = maps\mp\zombies\_wall_buys::getupgradeweaponname( var_0, var_3 );
    maps\mp\mp_zombie_h2o_sq::givezombieweaponallowthird( var_0, var_4 );

    if ( issubstr( var_4, "iw5_em1zm_mp" ) )
        var_0 maps\mp\gametypes\zombies::playersetem1maxammo();

    if ( isdefined( level.setweaponlevelfunc ) )
        var_0 [[ level.setweaponlevelfunc ]]( var_1, scripts\zm\balance::stock_weapon_level( var_2 ) );
}
