#pragma once

#include <string>
#include <string_view>

namespace loading_tips
{
	inline int index(const std::string_view reference)
	{
		constexpr std::string_view prefix = "DIDYOUKNOWZM_MSG";
		if (!reference.starts_with(prefix)) return 0;
		const auto suffix = reference.substr(prefix.size());
		if (suffix.empty() || suffix.size() > 2 || suffix.front() == '0') return 0;
		int value = 0;
		for (const auto c : suffix)
		{
			if (c < '0' || c > '9') return 0;
			value = value * 10 + c - '0';
		}
		return value <= 85 ? value : 0;
	}

	inline const char* replacement(const int tip, const bool classic)
	{
		if (classic)
		{
			switch (tip)
			{
			case 1: return "You can purchase ^3perks^7 without an Exo Suit in ^3Classic^7 mode.";
			case 3: return "Upgrade weapons to ^3Mk 5^7, then ^3Mk 10^7 at the Weapon Upgrade Station. Each upgrade costs ^35,000 credits^7.";
			case 4: return "^3Classic^7 disables Exo Suits and Exo Slam. Other perks remain available.";
			case 8: return "^3Classic^7 uses regular zombies and dogs, without special zombie mutations.";
			case 10: return "Turning on a ^3Power Station^7 awards ^3200 credits^7 before any Double Points bonus.";
			case 11: return "Regular zombies cannot sprint before ^3round 15^7. In Classic, their sprint speed is ^330% below stock^7.";
			case 12: return "Use ^3Traps^7 to thin out large groups of zombies, but keep clear of their damage.";
			case 14: return "In ^3Classic^7, self-reviving removes all remaining perks. Buy your perks again after recovering.";
			case 17: return "^3Orbital Drops^7 are disabled in Classic mode.";
			case 22: return "After a Solo revive, zombies ignore you for ^3two seconds^7. Use that time to get clear.";
			case 27: return "^3Classic^7 skips Survivor escort rounds on Infection.";
			case 28: return "Infection's ^3Toxic Gas Zones^7 remain active in Classic. Leave contaminated areas promptly.";
			case 29: return "The ^3Magnetron^7 can slow groups of zombies and help you make room to escape.";
			case 30: return "Weapon upgrades increase ^3damage^7 and ^3reserve ammo capacity^7 as well as refilling ammunition.";
			case 31: return "Perk lockers still need ^3power^7 in Classic, even though you do not need an Exo Suit.";
			case 32: return "Use the break between rounds to reload, buy perks, and plan your next route.";
			case 39: return "^3Exo Health^7 raises your maximum health to ^3200^7.";
			case 40: return "^3Exo Reload^7 costs ^33,000 credits^7 and lets you reload faster.";
			case 41: return "^3Exo Soldier^7 costs ^32,500 credits^7 and improves hip fire, weapon swapping, and firing on the move.";
			case 42: return "^3Exo Stockpile^7 increases your ammo and grenade reserves without requiring a suit in Classic.";
			case 43: return "^3Decontamination^7 costs ^3500 credits^7. Keep enough credits available when toxic gas is active.";
			case 44: return "^3Mk 10^7 is the highest normal weapon upgrade and gives your weapon ^3gold camo^7.";
			case 56: return "^3Classic^7 disables Carrier's bomb and contamination events.";
			case 63: return "^3Atlas Saboteurs^7 do not board the ship in Classic mode.";
			case 64: return "^3Classic^7 zombies pursue targets without spreading their routes or wandering when no target is available.";
			case 65: return "Aim for heads and leave yourself room to retreat when fighting large groups.";
			case 66: return "Special rounds in ^3Classic^7 feature ^3dogs^7 instead of special zombie encounters.";
			case 67: return "^3Exo Medic^7 provides a self-revive in Classic, but you lose your other perks when you recover.";
			case 70: return "Use map ^3Traps^7 to help control the horde. Classic disables orbital supply drops.";
			case 71: return "In ^3Classic^7, the ^31911^7 is your starting pistol and your pistol while downed.";
			case 76: return "^3Goliath-class Armor^7 drops are disabled in Classic mode.";
			case 77: return "Keep an escape route open: ^3Classic^7 has no Exo Suit or Goliath armor drops.";
			case 78: return "^3Classic^7 removes special enemy mutations, but regular zombies become more dangerous as rounds progress.";
			case 80: return "^3Classic^7 skips Oz's boss rounds on Descent.";
			}
		}
		switch (tip)
		{
		case 1: return "Most ^3Exo Upgrades^7 require an ^3Exo Suit^7. In Solo, ^3Exo Medic^7 can be purchased without one.";
		case 3: return "Upgrade weapons from ^3Mk 1^7 to ^3Mk 10^7 at the Weapon Upgrade Station. Upgrades cost ^31,500 credits^7, or ^33,000^7 for the final upgrade.";
		case 6: return "In Solo, ^3Exo Medic^7 grants one self-revive per purchase. You can buy it ^3three times^7 per match.";
		case 10: return "^3EMZs^7 will disable your ^3EXO Suit^7 if they hit you or if you attempt to boost away from them.";
		case 41: return "^3Meatbags^7 wear tactical armor, making them resistant to body and headshots.";
		case 43: return "^3Goliaths^7 sport automated anti-air rockets that fire from their shoulder-mounted cannons.";
		case 70: return "The ^3Advanced Repulsion Turret^7 slows, damages, and EMPs zombies.";
		default: return nullptr;
		}
	}

	inline std::string text(const int tip, const std::string_view stock, const bool classic, const bool english)
	{
		const auto* updated = english ? replacement(tip, classic) : nullptr;
		const std::string_view source = updated ? std::string_view(updated) : stock;
		std::string result;
		result.reserve(source.size());
		for (const auto c : source)
		{
			// Only collapse repeated ordinary spaces; retain colors and other markup.
			if (c != ' ' || result.empty() || result.back() != ' ') result += c;
		}
		return result;
	}
}
