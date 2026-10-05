main()
{
    replacefunc( maps\mp\zombies\zombie_melee_goliath::meleegoliathcalculatemoveratescale, scripts\zm\balance::goliath_movement_rate );
    replacefunc( maps\mp\zombies\zombie_melee_goliath::meleegoliathcalculatetraverseratescale, scripts\zm\balance::goliath_traversal_rate );
    println( "[Zombies Balance] Carrier: Goliath movement/traversal=85%; attack timing retained" );
}
