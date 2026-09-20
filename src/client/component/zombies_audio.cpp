#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "gsc/script_extension.hpp"
#include "console.hpp"
#include "filesystem.hpp"
#include "scripting.hpp"
#include "solo.hpp"

namespace zombies_audio
{
	namespace
	{
		struct round_sound
		{
			const char* path;
			std::string pcm;
			game::LoadedSound loaded{};
			game::SoundFile file{};
		};

		struct round_alias
		{
			const char* name;
			game::snd_alias_t* target{};
			game::SoundFile* original{};
			unsigned original_flags{};
		};

		// Owned for the process lifetime: active voices may outlive script shutdown.
		round_sound sounds[] = {
			{"sound/awz/classic_round_start.wav"},
			{"sound/awz/classic_round_end.wav"},
			{"sound/awz/classic_dog_round_start.wav"},
			{"sound/awz/classic_dog_round_end.wav"},
		};
		round_alias aliases[] = {
			{"zmb_mus_roundcount"},
			{"zmb_mus_roundfinish"},
		};

		void load(round_sound& sound)
		{
			if (!sound.pcm.empty()) return;
			const auto wav = filesystem::read_file(sound.path);
			if (wav.size() < 12 || wav.size() > 8 * 1024 * 1024 ||
				wav.compare(0, 4, "RIFF") || wav.compare(8, 4, "WAVE"))
				throw std::runtime_error(std::format("Missing/invalid Classic audio: {}", sound.path));
			bool format_ok = false;
			std::string pcm;
			for (size_t pos = 12; pos + 8 <= wav.size();)
			{
				uint32_t size;
				std::memcpy(&size, wav.data() + pos + 4, 4);
				if (size > wav.size() - pos - 8) throw std::runtime_error("Truncated Classic WAV chunk");
				const auto* data = wav.data() + pos + 8;
				if (!wav.compare(pos, 4, "fmt ") && size >= 16)
				{
					// Our converted assets use the same PCM layout as AW's loaded sounds.
					constexpr unsigned char expected[] = {1, 0, 2, 0, 0x80, 0xBB, 0, 0,
						0, 0xEE, 2, 0, 4, 0, 16, 0};
					format_ok = std::memcmp(data, expected, sizeof(expected)) == 0;
				}
				else if (!wav.compare(pos, 4, "data")) pcm.assign(data, size);
				pos += 8 + size + (size & 1);
			}
			if (!format_ok || pcm.empty() || pcm.size() % 4)
				throw std::runtime_error("Classic audio must be 48 kHz stereo 16-bit PCM");
			sound.pcm = std::move(pcm);
			sound.loaded.name = sound.path;
			sound.loaded.info = {sound.pcm.data(), 48000, static_cast<unsigned>(sound.pcm.size()),
				static_cast<unsigned>(sound.pcm.size() / 4), 2, 16, 4, 1, static_cast<int>(sound.pcm.size())};
			sound.file.type = 1;
			sound.file.exists = 1;
			sound.file.u.loadSnd = &sound.loaded;
		}

		void prepare()
		{
			const auto index = game::Scr_GetInt(0);
			if (index < 0 || index >= static_cast<int>(std::size(sounds)))
			{
				gsc::scr_error("Invalid Classic music index");
				return;
			}
			const auto* mode = game::Dvar_FindVar("ui_awz_classic");
			if (!solo::active() || !mode || mode->current.integer != 1 ||
				game::Com_GetCurrentCoDPlayMode() != game::CODPLAYMODE_ZOMBIES)
			{
				gsc::scr_error("Classic music requested outside a Classic Solo match");
				return;
			}
			try
			{
				// Validate every recording and both shared aliases before changing playback.
				for (auto& sound : sounds) load(sound);
				std::array<game::snd_alias_t*, std::size(aliases)> targets{};
				for (size_t i = 0; i < std::size(aliases); ++i)
				{
					auto& alias = aliases[i];
					const auto* list = static_cast<game::snd_alias_list_t*>(
						game::DB_FindXAssetHeader(game::ASSET_TYPE_SOUND, alias.name, false).data);
					if (!list || list->count != 1 || !list->head || !list->head->soundFile)
						throw std::runtime_error(std::format("Unexpected Classic sound alias: {}", alias.name));
					targets[i] = list->head;
				}
				for (size_t i = 0; i < std::size(aliases); ++i)
				{
					auto& alias = aliases[i];
					auto& sound = sounds[(index / 2) * 2 + i];
					if (!alias.target)
					{
						alias.target = targets[i];
						alias.original = alias.target->soundFile;
						alias.original_flags = alias.target->flags;
					}
					if (alias.target->soundFile == &sound.file) continue;
					// The alias also carries the file type in bits 16..18.
					alias.target->flags = (alias.original_flags & ~(7u << 16)) | (1u << 16);
					alias.target->soundFile = &sound.file;
					console::info("[Classic Audio] %s -> %s: %.3fs PCM; stock music routing/volume retained\n",
						alias.name, sound.path, sound.loaded.info.numSamples / 48000.0);
				}
				game::Scr_AddInt((sounds[index].loaded.info.numSamples + 47) / 48);
			}
			catch (const std::exception& e)
			{
				console::error("[Classic Audio] %s\n", e.what());
				gsc::scr_error(e.what());
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_mp()) return;
			gsc::add_function("awz_classicmusic", &prepare);
			scripting::on_shutdown([](int)
			{
				// G_ShutdownGame runs while the old map's assets are still valid.
				for (auto& alias : aliases)
				{
					if (!alias.target) continue;
					alias.target->soundFile = alias.original;
					alias.target->flags = alias.original_flags;
					alias.target = nullptr;
					alias.original = nullptr;
				}
			});
		}
	};
}

REGISTER_COMPONENT(zombies_audio::component)
