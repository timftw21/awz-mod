#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console.hpp"

#include <utils/nt.hpp>
#include <utils/string.hpp>

namespace menu_audio
{
	namespace
	{
		constexpr unsigned int bink_file_handle = 0x00800000;
		constexpr unsigned int bink_from_memory = 0x04000000;

		using bink_open_t = void* (__stdcall*)(const char*, unsigned int);
		using bink_set_volume_t = void (__stdcall*)(void*, unsigned int, int);
		bink_open_t bink_open{};
		bink_set_volume_t bink_set_volume{};

		std::string video_name(const char* name, const unsigned int flags)
		{
			// Bink also accepts memory buffers and file handles in its name argument.
			if (!name || (flags & bink_from_memory)) return {};

			std::string path;
			if (flags & bink_file_handle)
			{
				const auto handle = reinterpret_cast<HANDLE>(const_cast<char*>(name));
				const auto size = GetFinalPathNameByHandleA(handle, nullptr, 0, FILE_NAME_NORMALIZED);
				if (!size) return {};
				path.resize(size + 1);
				const auto length = GetFinalPathNameByHandleA(handle, path.data(), size + 1, FILE_NAME_NORMALIZED);
				if (!length || length > size) return {};
				path.resize(length);
			}
			else
			{
				path = name;
			}

			const auto separator = path.find_last_of("/\\");
			if (separator != std::string::npos) path.erase(0, separator + 1);
			path = utils::string::to_lower(path);
			if (path.ends_with(".bik")) path.resize(path.size() - 4);
			return path;
		}

		bool is_zombies_background(const std::string& name)
		{
			return name == "zombies_bg_main" || name == "zombies_bg_lobby"
				|| name == "zombies_bg_main_dlc2" || name == "zombies_bg_lobby_dlc2"
				|| name == "zombies_bg_main_dlc3" || name == "zombies_bg_lobby_dlc3"
				|| name == "zombies_bg_main_dlc4" || name == "zombies_bg_lobby_dlc4";
		}

		void* __stdcall bink_open_stub(const char* name, const unsigned int flags)
		{
			const auto video = video_name(name, flags);
			auto* const movie = bink_open(name, flags);
			if (movie && is_zombies_background(video))
			{
				// Keep the audio clock running: BinkSetSoundOnOff stalls BinkWait after
				// the first frame in this DLL. These backgrounds have track 0 or no audio.
				// Track volume is independent of the game's speaker-volume updates.
				bink_set_volume(movie, 0, 0);
				console::info("[Menu audio] Muted background video audio (playback clock active): %s\n", video.data());
			}
			return movie;
		}
	}

	class component final : public component_interface
	{
	public:
		void* load_import(const std::string& library, const std::string& function) override
		{
			if (!game::environment::is_mp() || library != "bink2w64.dll" || function != "BinkOpen")
			{
				return nullptr;
			}

			const auto bink = utils::nt::library::load(library);
			bink_open = bink.get_proc<bink_open_t>("BinkOpen");
			bink_set_volume = bink.get_proc<bink_set_volume_t>("BinkSetVolume");
			if (!bink_open || !bink_set_volume)
			{
				throw std::runtime_error("Failed to resolve Bink menu audio functions");
			}
			console::info("[Menu audio] Background video volume hook installed\n");
			return bink_open_stub;
		}
	};
}

REGISTER_COMPONENT(menu_audio::component)
