#include "svdpi.h"
#include <iostream>
#include <vector>
#include <stdint.h>
#include "processor.h"
#include "arch.h"
#include "mem.h"

using namespace vortex;

static Processor* g_processor = nullptr;
static RAM* g_ram = nullptr;

extern "C" {

// Simplified Init: Just sets up the objects
// Inside simx_init in simx_dpi.cpp
int simx_init(int num_cores, int num_warps, int num_threads) {
    try {
        std::cout << "[SimX-DPI] Initializing with " << num_cores << " cores..." << std::endl;
        
        Arch arch(num_cores, num_warps, num_threads);
        
        // FIX: Increase memory size to cover the 0x80000000 range.
        // 0xFFFFFFFF (4GB) ensures any 32-bit address is valid.
        // SimX uses sparse memory or allocation on demand usually, 
        // but let's give it a large enough range:
        g_ram = new RAM(0xFFFFFFFF); 

        g_processor = new Processor(arch);
        g_processor->attach_ram(g_ram);
        
        return 0; 
    } catch (const std::exception& e) { 
        std::cerr << "Init Error: " << e.what() << std::endl;
        return -1; 
    }
}

// Write memory directly from SystemVerilog bytes
void simx_write_mem(uint64_t addr, int size, const svOpenArrayHandle data) {
    if (!g_ram) return;
    
    // Get pointer to the SystemVerilog array data
    uint8_t* src = (uint8_t*)svGetArrayPtr(data);
    if (src) {
        g_ram->write(src, addr, size);
        std::cout << "[SimX-DPI] Wrote " << size << " bytes to addr 0x" << std::hex << addr << std::dec << std::endl;
    }
}

void simx_cleanup() {
    delete g_processor;
    delete g_ram;
    g_processor = nullptr;
    g_ram = nullptr;
}

}