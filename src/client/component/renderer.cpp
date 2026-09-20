#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "game/dvars.hpp"
#include "console.hpp"
#include "renderer.hpp"
#include "scheduler.hpp"

#include <utils/hook.hpp>
#include <utils/flags.hpp>
#include <d3d11sdklayers.h>

namespace renderer
{
	namespace
	{
		utils::hook::detour r_init_draw_method_hook;
		utils::hook::detour r_update_front_end_dvar_options_hook;
		utils::hook::detour preload_init_hook;
		utils::hook::detour preload_shutdown_hook;
		utils::hook::detour add_cell_surfaces_hook;
		game::dvar_t* r_batch_cell_workers;
		decltype(&D3D11CreateDevice) create_device_original;
		CComPtr<ID3D11InfoQueue> debug_queue;

		HRESULT WINAPI create_device_stub(IDXGIAdapter* adapter, D3D_DRIVER_TYPE type, HMODULE software,
			UINT flags, const D3D_FEATURE_LEVEL* levels, UINT level_count, UINT sdk,
			ID3D11Device** device, D3D_FEATURE_LEVEL* selected_level, ID3D11DeviceContext** context)
		{
			auto result = create_device_original(adapter, type, software, flags | D3D11_CREATE_DEVICE_DEBUG,
				levels, level_count, sdk, device, selected_level, context);
			if (result == DXGI_ERROR_SDK_COMPONENT_MISSING)
			{
				result = create_device_original(adapter, type, software, flags, levels, level_count, sdk,
					device, selected_level, context);
			}
			if (SUCCEEDED(result) && device && *device)
			{
				debug_queue.Release();
				(*device)->QueryInterface(__uuidof(ID3D11InfoQueue), reinterpret_cast<void**>(&debug_queue.p));
				if (debug_queue)
				{
					D3D11_MESSAGE_SEVERITY severities[] = {D3D11_MESSAGE_SEVERITY_CORRUPTION, D3D11_MESSAGE_SEVERITY_ERROR};
					D3D11_INFO_QUEUE_FILTER filter{};
					filter.AllowList.NumSeverities = static_cast<UINT>(std::size(severities));
					filter.AllowList.pSeverityList = severities;
					debug_queue->AddStorageFilterEntries(&filter);
					debug_queue->SetMessageCountLimit(256);
				}
				console::info("[Renderer] Diagnostic DirectX validation layer: %s\n", debug_queue ? "enabled" : "unavailable");
			}
			return result;
		}

		struct cell_worker_batch_state
		{
			unsigned int depth = 0;
			bool pending = false, bypass = false;
			uint64_t cells = 0, requests = 0, signals = 0, full_queues = 0;
		};
		thread_local cell_worker_batch_state cell_workers;

		void flush_cell_worker_wake()
		{
			if (!cell_workers.pending) return;
			cell_workers.pending = false;
			++cell_workers.signals;
			utils::hook::invoke<void>(0x1403E1B10);
		}

		class cell_worker_batch
		{
		public:
			cell_worker_batch()
			{
				if (cell_workers.depth++ == 0)
				{
					++cell_workers.cells;
					cell_workers.bypass = !r_batch_cell_workers->current.enabled;
				}
			}

			~cell_worker_batch()
			{
				if (--cell_workers.depth == 0)
				{
					flush_cell_worker_wake();
					cell_workers.bypass = false;
				}
			}
		};

		void add_cell_surfaces_stub(int view_index, int cell_index, const void* planes,
			int plane_count, int frustum_plane_count)
		{
			// Native code copies up to five visibility commands for this cell, waking
			// the same manual-reset worker event after each copy. Publish the small
			// group before waking workers; every command still uses the native queue.
			const cell_worker_batch batch;
			add_cell_surfaces_hook.invoke<void>(view_index, cell_index, planes, plane_count, frustum_plane_count);
		}

		void enqueue_worker_wake_stub()
		{
			if (cell_workers.depth)
			{
				++cell_workers.requests;
				if (!cell_workers.bypass)
				{
					cell_workers.pending = true;
					return;
				}
				++cell_workers.signals;
			}
			utils::hook::invoke<void>(0x1403E1B10);
		}

		void worker_queue_full_stub(int warning, const char* queue_name)
		{
			if (cell_workers.depth)
			{
				// The full-queue path can wait on dependencies or execute a command
				// inline. Wake pending work first, and keep immediate wakes enabled
				// through any nested commands until this cell has finished.
				++cell_workers.full_queues;
				cell_workers.bypass = true;
				flush_cell_worker_wake();
			}
			utils::hook::invoke<void>(0x1405E4050, warning, queue_name);
		}

		// These are prefixes of the native material/technique/pass structures.
		struct named_asset { const char* name; };
		struct preload_pass
		{
			const named_asset* vertex;
			const void* declaration;
			const named_asset* hull;
			const named_asset* domain;
			const named_asset* pixel;
		};
		struct preload_breadcrumb
		{
			ULONGLONG tick;
			unsigned int technique_index, pass_index;
			char material[192], technique[192], vertex[192], hull[192], domain[192], pixel[192];
		};
		std::mutex preload_mutex;
		std::array<preload_breadcrumb, 8> preload_history{};
		size_t preload_sequence = 0;
		struct preload_statistics
		{
			bool active = false;
			ULONGLONG started = 0;
			size_t batches = 0, materials = 0, cache_hits = 0, draws = 0, pending_queries = 0;
		};
		preload_statistics preload_stats;

		void log_preload_statistics(const char* outcome)
		{
			if (!preload_stats.active) return;
			console::info("[Shader preload] %s: %llu ms elapsed, %zu batches, %zu materials completed, "
				"%zu technique-set cache hits, %zu draws, %zu pending query polls\n", outcome,
				GetTickCount64() - preload_stats.started, preload_stats.batches, preload_stats.materials,
				preload_stats.cache_hits, preload_stats.draws, preload_stats.pending_queries);
			preload_stats.active = false;
		}

		void preload_init_stub()
		{
			// Native cancellation clears the material queue but leaves this cursor
			// behind. A new queue must start at the first technique of its first material.
			*reinterpret_cast<unsigned int*>(0x15004D6D8) = 0;
			{
				std::lock_guard lock(preload_mutex);
				preload_sequence = 0;
			}
			preload_init_hook.invoke<void>();
		}

		void preload_shutdown_stub()
		{
			log_preload_statistics("Stopped before completion");
			preload_shutdown_hook.invoke<void>();
			*reinterpret_cast<unsigned int*>(0x15004D6D8) = 0;
		}

		bool preload_material_stub(const void* material, int batch_start)
		{
			const auto* cache_enabled = *reinterpret_cast<game::dvar_t**>(0x14D850278);
			const auto* technique_set = *reinterpret_cast<const unsigned char* const*>(
				static_cast<const unsigned char*>(material) + 0xF0);
			// Use the engine's existing cache predicate before its two render-target
			// setup calls. A cache hit needs neither state changes nor GPU work.
			if (cache_enabled->current.enabled && (technique_set[8] & 1))
			{
				++preload_stats.cache_hits;
				++preload_stats.materials;
				return true;
			}

			const auto completed = utils::hook::invoke<bool>(0x14060F320, material, batch_start);
			if (completed) ++preload_stats.materials;
			return completed;
		}

		void preload_batch_stub()
		{
			if (!preload_stats.active)
			{
				preload_stats = {};
				preload_stats.active = true;
				preload_stats.started = GetTickCount64();
				console::info("[Shader preload] Starting at material %u/%u\n",
					*reinterpret_cast<unsigned int*>(0x15004D6D0), *reinterpret_cast<unsigned int*>(0x15004D6D4));
			}
			++preload_stats.batches;
			utils::hook::invoke<void>(0x14060EE50);
			if (*reinterpret_cast<unsigned int*>(0x15004D6D0) >= *reinterpret_cast<unsigned int*>(0x15004D6D4))
			{
				log_preload_statistics("Completed");
			}
		}

		HRESULT preload_create_query_stub(ID3D11Device* device, const D3D11_QUERY_DESC* description,
			ID3D11Query** query)
		{
			const auto result = device->CreateQuery(description, query);
			if (FAILED(result))
			{
				log_device_failure(device, "shader preload CreateQuery", result);
				game::Com_Error(game::ERR_FATAL, "Could not create the shader preload query (0x%08lx). See the client log for GPU details.", result);
			}

			D3D11_FEATURE_DATA_SHADER_CACHE cache{};
			const auto support = device->CheckFeatureSupport(D3D11_FEATURE_SHADER_CACHE, &cache, sizeof(cache));
			if (SUCCEEDED(support))
			{
				console::info("[Shader cache] Driver automatic caching: memory=%s, disk=%s (flags=0x%x)\n",
					(cache.SupportFlags & D3D11_SHADER_CACHE_SUPPORT_AUTOMATIC_INPROC_CACHE) ? "supported" : "not reported",
					(cache.SupportFlags & D3D11_SHADER_CACHE_SUPPORT_AUTOMATIC_DISK_CACHE) ? "supported" : "not reported",
					cache.SupportFlags);
			}
			else
			{
				console::info("[Shader cache] Driver cache capability query unavailable (0x%08lx)\n", support);
			}
			return result;
		}

		template<size_t Size>
		void copy_asset_name(char (&destination)[Size], const named_asset* asset)
		{
			strncpy_s(destination, asset && asset->name ? asset->name : "<none>", _TRUNCATE);
		}

		void preload_draw_stub(void* state, const void* arguments)
		{
			++preload_stats.draws;
			// Copy names while the assets are in use, rather than dereferencing them
			// later during device loss or after a map has been unloaded.
			{
				std::lock_guard lock(preload_mutex);
				auto& entry = preload_history[preload_sequence++ % preload_history.size()];
				entry.tick = GetTickCount64();
				entry.technique_index = *reinterpret_cast<unsigned int*>(0x1500362F0);
				entry.pass_index = *reinterpret_cast<unsigned int*>(0x150036308);
				copy_asset_name(entry.material, *reinterpret_cast<const named_asset**>(0x1500362E8));
				copy_asset_name(entry.technique, *reinterpret_cast<const named_asset**>(0x1500362F8));
				const auto* pass = *reinterpret_cast<const preload_pass**>(0x150036300);
				copy_asset_name(entry.vertex, pass ? pass->vertex : nullptr);
				copy_asset_name(entry.hull, pass ? pass->hull : nullptr);
				copy_asset_name(entry.domain, pass ? pass->domain : nullptr);
				copy_asset_name(entry.pixel, pass ? pass->pixel : nullptr);
			}
			utils::hook::invoke<void>(0x1405D9CB0, state, arguments);
		}

		HRESULT preload_get_data_stub(ID3D11DeviceContext* context, ID3D11Asynchronous* query,
			void* data, UINT size, UINT flags)
		{
			const auto result = context->GetData(query, data, size, flags);
			if (result == S_FALSE) ++preload_stats.pending_queries;
			if (FAILED(result))
			{
				CComPtr<ID3D11Device> device;
				context->GetDevice(&device);
				log_device_failure(device, "shader preload GetData", result);
				// The stock loops treat every nonzero result as pending. A failed
				// query cannot complete: do not spin forever or advance to more draws.
				game::Com_Error(game::ERR_FATAL, "DirectX failed during shader preload (0x%08lx). See the client log for the GPU error and shader details.", result);
			}
			return result;
		}

		const char* device_result_name(HRESULT result)
		{
			switch (result)
			{
			case S_OK: return "S_OK";
			case DXGI_ERROR_DEVICE_REMOVED: return "DXGI_ERROR_DEVICE_REMOVED";
			case DXGI_ERROR_DEVICE_HUNG: return "DXGI_ERROR_DEVICE_HUNG";
			case DXGI_ERROR_DEVICE_RESET: return "DXGI_ERROR_DEVICE_RESET";
			case DXGI_ERROR_DRIVER_INTERNAL_ERROR: return "DXGI_ERROR_DRIVER_INTERNAL_ERROR";
			case DXGI_ERROR_INVALID_CALL: return "DXGI_ERROR_INVALID_CALL";
			default: return "other HRESULT";
			}
		}

		int get_fullbright_technique()
		{
			switch (dvars::r_fullbright->current.integer)
			{
			case 3:
				return 13;
			case 2:
				return 25;
			default:
				return game::TECHNIQUE_UNLIT;
			}
		}

		void gfxdrawmethod()
		{
			game::gfxDrawMethod->drawScene = game::GFX_DRAW_SCENE_STANDARD;
			game::gfxDrawMethod->baseTechType = dvars::r_fullbright->current.enabled ? get_fullbright_technique() : game::TECHNIQUE_LIT;
			game::gfxDrawMethod->emissiveTechType = dvars::r_fullbright->current.enabled ? get_fullbright_technique() : game::TECHNIQUE_EMISSIVE;
			game::gfxDrawMethod->forceTechType = dvars::r_fullbright->current.enabled ? get_fullbright_technique() : 182;
		}

		void r_init_draw_method_stub()
		{
			gfxdrawmethod();
		}

		bool r_update_front_end_dvar_options_stub()
		{
			if (dvars::r_fullbright->modified)
			{
				game::Dvar_ClearModified(dvars::r_fullbright);
				game::R_SyncRenderThread();
				
				gfxdrawmethod();
			}

			return r_update_front_end_dvar_options_hook.invoke<bool>();
		}
	}

	void log_device_failure(ID3D11Device* device, const char* operation, HRESULT result)
	{
		const auto reason = device ? device->GetDeviceRemovedReason() : E_POINTER;
		// Flush through the console immediately; a fatal error may stop scheduler jobs.
		console::error("[GPU failure] %s: %s (0x%08lx); device reason: %s (0x%08lx)\n",
			operation, device_result_name(result), result, device_result_name(reason), reason);
		log_debug_messages();
		if (!game::environment::is_mp()) return;
		console::error("[GPU failure] Shader preload: initialized=%u, material=%u/%u, technique=%u\n",
			*reinterpret_cast<unsigned char*>(0x15004D6DC), *reinterpret_cast<unsigned int*>(0x15004D6D0),
			*reinterpret_cast<unsigned int*>(0x15004D6D4), *reinterpret_cast<unsigned int*>(0x15004D6D8));
		std::lock_guard lock(preload_mutex);
		const auto first = preload_sequence > preload_history.size() ? preload_sequence - preload_history.size() : 0;
		for (auto i = first; i < preload_sequence; ++i)
		{
			const auto& entry = preload_history[i % preload_history.size()];
			console::error("[GPU failure] Recent preload draw tick=%llu material=%s technique=%s (%u) pass=%u VS=%s HS=%s DS=%s PS=%s\n",
				entry.tick, entry.material, entry.technique, entry.technique_index, entry.pass_index,
				entry.vertex, entry.hull, entry.domain, entry.pixel);
		}
	}

	void log_debug_messages()
	{
		if (!debug_queue) return;
		const auto count = debug_queue->GetNumStoredMessagesAllowedByRetrievalFilter();
		for (UINT64 i = 0; i < count; ++i)
		{
			SIZE_T size = 0;
			if (FAILED(debug_queue->GetMessage(i, nullptr, &size)) || !size || size > 65536) continue;
			std::vector<unsigned char> buffer(size);
			auto* message = reinterpret_cast<D3D11_MESSAGE*>(buffer.data());
			if (SUCCEEDED(debug_queue->GetMessage(i, message, &size)))
				console::error("[D3D11 validation] id=%u severity=%u: %s\n", message->ID, message->Severity, message->pDescription);
		}
		if (count) debug_queue->ClearStoredMessages();
	}

	class component final : public component_interface
	{
	public:
		void* load_import(const std::string& library, const std::string& function) override
		{
			if (!utils::flags::has_flag("gpu-debug") || !game::environment::is_mp() || game::environment::is_dedi() ||
				_stricmp(library.c_str(), "d3d11.dll") || function != "D3D11CreateDevice") return nullptr;
			create_device_original = utils::nt::library::load(library).get_proc<decltype(create_device_original)>(function);
			if (!create_device_original) throw std::runtime_error("Failed to resolve D3D11CreateDevice");
			console::info("[Renderer] Diagnostic DirectX device creation hook installed\n");
			return create_device_stub;
		}

		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			dvars::r_fullbright = game::Dvar_RegisterInt("r_fullbright", 0, 0, 3, game::DVAR_FLAG_SAVED);

			if (game::environment::is_mp())
			{
				r_batch_cell_workers = game::Dvar_RegisterBool("r_batchCellWorkers", true, 0);
				add_cell_surfaces_hook.create(0x14057B1A0, add_cell_surfaces_stub);
				utils::hook::call(0x1405E5269, enqueue_worker_wake_stub);
				utils::hook::call(0x1405E51A8, worker_queue_full_stub);
				console::info("[Renderer] Cell visibility worker wake batching enabled (r_batchCellWorkers), with immediate wakes on queue overflow\n");
				scheduler::loop([]
				{
					if (!cell_workers.cells) return;
					console::info("[Visibility workers] main thread: %llu cells, %llu requested wakes, %llu event signals, %llu full queues; batching=%d\n",
						cell_workers.cells, cell_workers.requests, cell_workers.signals, cell_workers.full_queues,
						r_batch_cell_workers->current.enabled);
					cell_workers.cells = cell_workers.requests = cell_workers.signals = cell_workers.full_queues = 0;
				}, scheduler::pipeline::main, 10s);

				// The stock tessellation loop writes all 16 control points to vertex 1.
				// Start one stride before the buffer and advance before EVERY iteration,
				// including the loop back-edge, so vertices 0 through 15 are initialized.
				utils::hook::set<uint8_t>(0x14060FB54, 0xE0); // lea rdi, [rax - 0x20]
				utils::hook::nop(0x14060FB77, 9);
				utils::hook::copy(0x14060FB77, "\x48\x83\xC7\x20", 4); // add rdi, 0x20 (in native NOP space)
				utils::hook::inject(0x14060FC01, reinterpret_cast<void*>(0x14060FB77));

				// Preserve the terminal cursor (180) when the final technique exhausts
				// the batch budget. Modulo 180 restarts the same material instead.
				utils::hook::nop(0x14060F826, 5);
				utils::hook::nop(0x14060F82D, 0x15);

				preload_init_hook.create(0x14060FA80, preload_init_stub);
				preload_shutdown_hook.create(0x140610000, preload_shutdown_stub);
				utils::hook::call(0x14060F9AA, preload_batch_stub);
				utils::hook::call(0x14060EF37, preload_material_stub);
				utils::hook::call(0x14060FDB3, preload_create_query_stub);
				utils::hook::nop(0x14060FDB8, 1);
				utils::hook::call(0x14060F6EA, preload_draw_stub);
				for (const auto address : {0x14060EEA7, 0x14060EED8, 0x14060F767, 0x14060F7AB})
				{
					// Replace the six-byte COM call with a five-byte call plus padding;
					// all five COM arguments, including flags on the stack, stay intact.
					utils::hook::call(address, preload_get_data_stub);
					utils::hook::nop(address + 5, 1);
				}
				console::info("[Renderer] Shader preload vertex/cursor fixes, early cache hits, query failure handling and statistics enabled\n");
			}
		
			r_init_draw_method_hook.create(SELECT_VALUE(0x14046C150, 0x140588B00), &r_init_draw_method_stub);
			r_update_front_end_dvar_options_hook.create(SELECT_VALUE(0x1404A5330, 0x1405C3AE0), &r_update_front_end_dvar_options_stub);

			// use "saved" flags for "r_normalMap"
			utils::hook::set<uint8_t>(SELECT_VALUE(0x14047E0B8, 0x14059AD71), game::DVAR_FLAG_SAVED);

			// use "saved" flags for "r_specularMap"
			utils::hook::set<uint8_t>(SELECT_VALUE(0x14047E0DA, 0x14059AD99), game::DVAR_FLAG_SAVED);

			// use "saved" flags for "r_specOccMap"
			utils::hook::set<uint8_t>(SELECT_VALUE(0x14047E0FC, 0x14059ADC1), game::DVAR_FLAG_SAVED);
		}
	};
}

REGISTER_COMPONENT(renderer::component)
