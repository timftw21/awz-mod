#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "scheduler.hpp"
#include "fps.hpp"
#include "console.hpp"
#include "localized_strings.hpp"
#include "renderer.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include <array>
#include <algorithm>

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace fps
{
	namespace
	{
		const game::dvar_t* cg_drawFPS;
		const game::dvar_t* cg_drawPing;
		const game::dvar_t* com_preciseFramePacing;
		const game::dvar_t* com_framePacingStats;
		const game::dvar_t* com_frameSpikeStats;
		using frame_clock = std::chrono::steady_clock;
		enum class frame_stage { callbacks, limiter, events, server, client, submit, render_wait, screen, cgame, ui, begin_render, end_render, worker_wait, config, count };
		struct frame_measurement
		{
			frame_clock::time_point start{};
			std::array<double, static_cast<size_t>(frame_stage::count)> ms{};
			double wake_late_ms = 0;
			ULONG64 cgame_cycles = 0;
			bool active = false;
		};
		thread_local frame_measurement frame{};
		std::atomic_int effective_cap{0};
		utils::hook::detour render_wait_hook;
		utils::hook::detour present_frame_hook;
		utils::hook::detour worker_wait_hook;
		thread_local frame_clock::time_point present_frame_start{};
		std::atomic_bool diagnostics_enabled{false};

		double elapsed_ms(const frame_clock::time_point start, const frame_clock::time_point end)
		{
			return std::chrono::duration<double, std::milli>(end - start).count();
		}

		class stage_timer
		{
		public:
			explicit stage_timer(const frame_stage stage) : stage_(stage), enabled_(frame.active)
			{
				if (enabled_) start_ = frame_clock::now();
			}
			~stage_timer()
			{
				if (enabled_) frame.ms[static_cast<size_t>(stage_)] += elapsed_ms(start_, frame_clock::now());
			}
		private:
			frame_stage stage_;
			bool enabled_;
			frame_clock::time_point start_{};
		};

		template<frame_stage Stage, size_t Address, typename... Args>
		void measured_call(Args... args)
		{
			const stage_timer timer(Stage);
			utils::hook::invoke<void>(Address, args...);
		}

		void render_wait_stub(void* callback)
		{
			const stage_timer timer(frame_stage::render_wait);
			render_wait_hook.invoke<void>(callback);
		}

		int worker_wait_stub(void* predicate, int process_commands)
		{
			const stage_timer timer(frame_stage::worker_wait);
			return worker_wait_hook.invoke<int>(predicate, process_commands);
		}

		int cgame_draw_stub(int client, int server_time, int stereo, int demo, int cubemap, int active, int draw_type)
		{
			const stage_timer timer(frame_stage::cgame);
			ULONG64 before = 0, after = 0;
			if (frame.active) QueryThreadCycleTime(GetCurrentThread(), &before);
			const auto result = utils::hook::invoke<int>(0x1401D4710, client, server_time, stereo, demo, cubemap, active, draw_type);
			if (frame.active && QueryThreadCycleTime(GetCurrentThread(), &after)) frame.cgame_cycles += after - before;
			return result;
		}

		void present_frame_stub()
		{
			present_frame_start = frame_clock::now();
			present_frame_hook.invoke<void>();
		}

		HRESULT present_stub(IDXGISwapChain* chain, UINT sync_interval, UINT flags)
		{
			const auto start = frame_clock::now();
			const auto result = chain->Present(sync_interval, flags);
			const auto end = frame_clock::now();
			renderer::log_debug_messages();
			if (FAILED(result))
			{
				CComPtr<ID3D11Device> device;
				chain->GetDevice(__uuidof(ID3D11Device), reinterpret_cast<void**>(&device.p));
				renderer::log_device_failure(device, "IDXGISwapChain::Present", result);
			}
			static thread_local frame_clock::time_point previous_start{}, last_spike{};
			const auto interval = previous_start == frame_clock::time_point{} ? 0.0 : elapsed_ms(previous_start, start);
			previous_start = start;
			const auto cap = effective_cap.load(std::memory_order_relaxed);
			const auto threshold = std::max(10.0, cap > 0 ? 1500.0 / cap : 10.0);
			const auto duration = elapsed_ms(start, end);
			if (diagnostics_enabled.load(std::memory_order_relaxed) &&
				(interval >= threshold || duration >= threshold) && end - last_spike >= 250ms)
			{
				last_spike = end;
				const auto before = elapsed_ms(present_frame_start, start);
				const auto stamp = GetTickCount64();
				scheduler::once([stamp, interval, duration, before, sync_interval, flags, result]
				{
					console::info("[Present spike] tick=%llu interval=%.3f api=%.3f pre_present=%.3f ms sync=%u flags=%u result=0x%08lx\n",
						stamp, interval, duration, before, sync_interval, flags, result);
				}, scheduler::pipeline::async);
			}
			return result;
		}

		class frame_pacer
		{
		public:
			frame_pacer()
			{
				if (!timer_) console::warn("[FPS] High-resolution timer unavailable (%lu); using legacy pacing\n", GetLastError());
			}

			~frame_pacer()
			{
				if (timer_) CloseHandle(timer_);
			}

			bool available() const { return timer_ != nullptr; }

			void reset()
			{
				previous_ = {};
				previous_fps_ = 0;
			}

			bool wait(const int max_fps)
			{
				if (!timer_) return false;
				auto now = frame_clock::now();
				if (previous_ != frame_clock::time_point{} && previous_fps_ == max_fps)
				{
					const auto deadline = previous_ + std::chrono::nanoseconds(1000000000LL / max_fps);
					const auto waited = now < deadline;
					while (now < deadline)
					{
						const auto remaining = deadline - now;
						if (remaining > 500us)
						{
							LARGE_INTEGER due{};
							due.QuadPart = -std::chrono::duration_cast<std::chrono::nanoseconds>(remaining - 500us).count() / 100;
							if (!SetWaitableTimer(timer_, &due, 0, nullptr, nullptr, FALSE) ||
								WaitForSingleObject(timer_, INFINITE) != WAIT_OBJECT_0)
							{
								console::warn("[FPS] High-resolution timer failed (%lu); restoring legacy pacing\n", GetLastError());
								CloseHandle(timer_);
								timer_ = nullptr;
								reset();
								return false;
							}
						}
						else
						{
							YieldProcessor();
						}
						now = frame_clock::now();
					}
					if (frame.active && waited) frame.wake_late_ms = elapsed_ms(deadline, now);
				}
				// Start from the actual release time: a slow frame must not cause a
				// burst of short catch-up frames. A changed cap takes effect immediately.
				previous_ = now;
				previous_fps_ = max_fps;
				return true;
			}

		private:
			HANDLE timer_ = CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
				TIMER_MODIFY_STATE | SYNCHRONIZE);
			frame_clock::time_point previous_{};
			int previous_fps_ = 0;
		};

		int frame_milliseconds(const int max_fps)
		{
			const stage_timer timer(frame_stage::limiter);
			effective_cap.store(max_fps, std::memory_order_relaxed);
			static frame_pacer pacer;
			static int previous_fps = 0;
			static bool previous_precise = false;
			static int remainder = 0;
			const auto precise = com_preciseFramePacing->current.enabled && pacer.available();
			if (max_fps != previous_fps || precise != previous_precise)
			{
				previous_fps = max_fps;
				previous_precise = precise;
				remainder = 0;
				pacer.reset();
				if (com_framePacingStats->current.enabled)
				{
					console::info("[FPS] Frame pacing: %s, effective cap=%d, interval=%.6f ms\n",
						precise ? "high-resolution" : "legacy fractional", max_fps, 1000.0 / max_fps);
				}
			}
			if (precise && pacer.wait(max_fps))
			{
				// Time has already elapsed before Com_Frame samples its clock. Use its
				// normal 1 ms minimum so it measures real simulation time rather than
				// scheduling a second, rounded wait. GPU synchronization stays intact.
				return 1;
			}

			// Com_Frame uses whole milliseconds for both pacing and simulation.
			// Carry the fraction instead of losing it: 144 FPS needs a mixture of
			// 6 and 7 ms frames totalling 1000 ms, rather than 144 * 6 = 864 ms.
			remainder += 1000 % max_fps;
			const auto milliseconds = 1000 / max_fps + remainder / max_fps;
			remainder %= max_fps;
			return milliseconds;
		}

		float fps_color_good[4] = {0.6f, 1.0f, 0.0f, 1.0f};
		float fps_color_ok[4] = {1.0f, 0.7f, 0.3f, 1.0f};
		float fps_color_bad[4] = {1.0f, 0.3f, 0.3f, 1.0f};

		//float origin_color[4] = { 1.0f, 0.67f, 0.13f, 1.0f };
		float ping_color[4] = {1.0f, 1.0f, 1.0f, 0.65f};

		struct frame_samples
		{
			frame_clock::time_point previous{};
			std::array<double, 32> history{};
			size_t index = 0;
			size_t count = 0;
			double total_ms = 0;
		};

		frame_samples cg_perf;
		std::atomic_int published_fps{0};

		void record_frame_time(const double milliseconds)
		{
			if (milliseconds <= 0) return;
			cg_perf.total_ms -= cg_perf.history[cg_perf.index];
			cg_perf.history[cg_perf.index] = milliseconds;
			cg_perf.total_ms += milliseconds;
			cg_perf.index = (cg_perf.index + 1) % cg_perf.history.size();
			cg_perf.count = std::min(cg_perf.count + 1, cg_perf.history.size());
			published_fps.store(static_cast<int>(1000.0 * cg_perf.count / cg_perf.total_ms + 0.5), std::memory_order_relaxed);
		}

		void record_diagnostics(const double milliseconds, const frame_clock::time_point now)
		{
			static std::array<double, 1024> samples{};
			static size_t count = 0;
			static auto last_report = now;
			if (!com_framePacingStats->current.enabled)
			{
				count = 0;
				last_report = now;
				return;
			}
			samples[count++] = milliseconds;
			if (count < samples.size() && now - last_report < 10s) return;
			last_report = now;
			// Sorting and disk logging run off the game thread. This is a bounded
			// batch. Flush when full so frames between reports are never discarded.
			scheduler::once([values = std::vector<double>(samples.begin(), samples.begin() + count)]() mutable
			{
				double total = 0;
				for (const auto value : values) total += value;
				std::sort(values.begin(), values.end());
				const auto size = values.size();
				const auto p99 = (99 * size + 99) / 100 - 1;
				console::info("[Performance] %zu consecutive frames: avg=%.3f ms, median=%.3f ms, p99=%.3f ms, max=%.3f ms\n",
					size, total / size, values[size / 2], values[p99], values.back());
			}, scheduler::pipeline::async);
			count = 0;
		}

		void perf_update()
		{
			const auto now = frame_clock::now();
			if (cg_perf.previous != frame_clock::time_point{})
			{
				const auto milliseconds = std::chrono::duration<double, std::milli>(now - cg_perf.previous).count();
				record_frame_time(milliseconds);
				record_diagnostics(milliseconds, now);
			}
			cg_perf.previous = now;
			utils::hook::invoke<void>(SELECT_VALUE(0x1404F6A90, 0x14062C540));
		}

		void cg_draw_fps()
		{
			if (cg_drawFPS && cg_drawFPS->current.integer > 0)
			{
				const auto fps = get_fps();

				auto* font = game::R_RegisterFont("fonts/consolefont");
				if (!font) return;

				const auto* const fps_string = utils::string::va("%i", fps);

				const auto scale = 1.0f;

				const auto x = (game::ScrPlace_GetViewPlacement()->realViewportSize[0] - 10.0f) - game::R_TextWidth(
					fps_string, std::numeric_limits<int>::max(), font) * scale;

				const auto y = font->pixelHeight * 1.2f;

				const auto fps_color = fps >= 60 ? fps_color_good : (fps >= 30 ? fps_color_ok : fps_color_bad);
				game::R_AddCmdDrawText(fps_string, std::numeric_limits<int>::max(), font, x, y, scale, scale, 0.0f, fps_color, 6);
			}
		}

		void cg_draw_ping()
		{
			if (cg_drawPing->current.integer > 0 && game::CL_IsCgameInitialized())
			{
				auto* font = game::R_RegisterFont("fonts/consolefont");
				if (!font) return;

				auto* const ping_string = utils::string::va("Ping: %i", *game::mp::ping);

				const auto scale = 1.0f;

				const auto x = (game::ScrPlace_GetViewPlacement()->realViewportSize[0] - 375.0f) - game::R_TextWidth(
					ping_string, std::numeric_limits<int>::max(), font) * scale;

				const auto y = font->pixelHeight * 1.2f;

				game::R_AddCmdDrawText(ping_string, std::numeric_limits<int>::max(), font, x, y, scale, scale, 0.0f, ping_color, 6);
			}
		}

		const game::dvar_t* cg_draw_fps_register_stub(const char* dvar_name, const char** value_list, const int default_index, unsigned int /*flags*/)
		{
			cg_drawFPS = game::Dvar_RegisterEnum(dvar_name, value_list, default_index, game::DVAR_FLAG_SAVED);
			return cg_drawFPS;
		}
	}

	int get_fps()
	{
		return published_fps.load(std::memory_order_relaxed);
	}

	void begin_frame()
	{
		frame = {};
		frame.active = game::environment::is_mp() && com_frameSpikeStats && com_frameSpikeStats->current.enabled;
		diagnostics_enabled.store(frame.active, std::memory_order_relaxed);
		effective_cap.store(0, std::memory_order_relaxed);
		if (frame.active) frame.start = frame_clock::now();
	}

	void end_main_callbacks()
	{
		if (frame.active) frame.ms[static_cast<size_t>(frame_stage::callbacks)] = elapsed_ms(frame.start, frame_clock::now());
	}

	void end_frame()
	{
		static frame_clock::time_point previous_end{};
		static frame_clock::time_point last_spike{};
		if (!frame.active) { previous_end = {}; return; }
		const auto now = frame_clock::now();
		const auto total = elapsed_ms(frame.start, now);
		const auto gap = previous_end == frame_clock::time_point{} ? 0.0 : elapsed_ms(previous_end, frame.start);
		previous_end = now;
		frame.active = false;
		const auto cap = effective_cap.load(std::memory_order_relaxed);
		const auto threshold = std::max(10.0, cap > 0 ? 1500.0 / cap : 10.0);
		if (total + gap < threshold || now - last_spike < 250ms) return;
		last_spike = now;
		const auto sample = frame;
		const auto in_game = game::CL_IsCgameInitialized();
		const auto stamp = GetTickCount64();
		scheduler::once([sample, total, gap, cap, in_game, stamp]
		{
			const auto& t = sample.ms;
			console::info("[Frame spike] tick=%llu game=%d cap=%d total=%.3f gap=%.3f callbacks=%.3f limiter=%.3f wake_late=%.3f events=%.3f server=%.3f client=%.3f submit=%.3f render_wait=%.3f screen=%.3f cgame=%.3f ui=%.3f begin_render=%.3f end_render=%.3f worker_wait=%.3f config=%.3f ms cgame_Mcycles=%.3f (nested stages overlap)\n",
				stamp, in_game, cap, total, gap, t[0], t[1], sample.wake_late_ms, t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12], t[13], sample.cgame_cycles / 1000000.0);
		}, scheduler::pipeline::async);
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			// fps setup
			com_framePacingStats = game::Dvar_RegisterBool("com_framePacingStats", false, game::DVAR_FLAG_NONE);
			com_frameSpikeStats = game::Dvar_RegisterBool("com_frameSpikeStats", true, game::DVAR_FLAG_NONE);
			utils::hook::call(SELECT_VALUE(0x140144D41, 0x140213B27), &perf_update);

			// change cg_drawfps flags to saved
			utils::hook::call(SELECT_VALUE(0x1400EF951, 0x1401A4B8E), &cg_draw_fps_register_stub);

			// fix ping value
			utils::hook::nop(0x140213031, 2);

			scheduler::loop(cg_draw_fps, scheduler::pipeline::renderer);
			if (game::environment::is_mp())
			{
				console::info("[Performance] Installing frame-stage diagnostics\n");
				// Verified Com_Frame call sites; preserve stock arguments and all work.
				utils::hook::call(0x1403CF012, measured_call<frame_stage::events, 0x1403CEBC0>);
				utils::hook::call(0x1403CF299, measured_call<frame_stage::events, 0x1403CEBC0>);
				utils::hook::call(0x1403CF26E, measured_call<frame_stage::server, 0x1404425B0, int>);
				utils::hook::call(0x1403CF28D, measured_call<frame_stage::client, 0x14020DA20, int, float>);
				utils::hook::call(0x140213B62, measured_call<frame_stage::submit, 0x1405C2D80>);
				utils::hook::call(0x1403CF308, measured_call<frame_stage::screen, 0x140213C20>);
				utils::hook::call(0x140213771, cgame_draw_stub);
				utils::hook::call(0x140213B3C, measured_call<frame_stage::ui, 0x1402138D0, int, int>);
				utils::hook::call(0x140213B14, measured_call<frame_stage::begin_render, 0x1405C24A0>);
				utils::hook::call(0x140213B5D, measured_call<frame_stage::end_render, 0x1405C25B0>);
				utils::hook::call(0x1403CEF7C, measured_call<frame_stage::config, 0x1403D2490>);
				render_wait_hook.create(0x1405A7630, render_wait_stub);
				worker_wait_hook.create(0x1405E6330, worker_wait_stub);
				// Stock swap-chain Present: RCX=chain, EDI=sync interval, flags=0.
				// Replace the complete argument-setup/call sequence; retain HRESULT.
				console::info("[Performance] Installing presentation diagnostics\n");
				present_frame_hook.create(0x1405F3940, present_frame_stub);
				// Omitting the unused vtable load leaves room for a direct call to
				// our image. A JIT stub is not guaranteed to lie within rel32 range.
				constexpr unsigned char present_args[] = {0x45, 0x33, 0xC0, 0x8B, 0xD7};
				utils::hook::copy(0x1405F3A43, present_args, sizeof(present_args));
				utils::hook::call(0x1405F3A48, present_stub);
				utils::hook::nop(0x1405F3A4D, 1);
				console::info("[Performance] Slow-frame diagnostics enabled; routine pacing statistics off (com_frameSpikeStats / com_framePacingStats)\n");
				// Pace before Com_Frame samples elapsed simulation time.
				// Keep its effective-cap selection, unlimited path and GPU waits.
				com_preciseFramePacing = game::Dvar_RegisterBool("com_preciseFramePacing", true, game::DVAR_FLAG_SAVED);
				utils::hook::nop(0x1403CEFDB, 8);
				utils::hook::call(0x1403CEFDB, frame_milliseconds);
				console::info("[FPS] High-resolution frame pacing installed; com_preciseFramePacing 0 selects legacy pacing\n");

				cg_drawPing = game::Dvar_RegisterInt("cg_drawPing", 0, 0, 1, game::DVAR_FLAG_SAVED);
				scheduler::loop(cg_draw_ping, scheduler::pipeline::renderer);
			}

			game::Dvar_RegisterBool("cg_infobar_ping", false, game::DVAR_FLAG_SAVED);
			game::Dvar_RegisterBool("cg_infobar_fps", false, game::DVAR_FLAG_SAVED);
		}
	};
}

REGISTER_COMPONENT(fps::component)
