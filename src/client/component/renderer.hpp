#pragma once

#include <d3d11.h>

namespace renderer
{
	void log_device_failure(ID3D11Device* device, const char* operation, HRESULT result);
	void log_debug_messages();
}
