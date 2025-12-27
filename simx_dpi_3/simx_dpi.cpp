#include "svdpi.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <stdint.h>
#include <cstring>

// Vortex includes
#include "processor.h"
#include "arch.h"
#include "mem.h"
#include <VX_config.h>
#include <VX_types.h>

// Define DCR address ranges if not defined in headers
#ifndef VX_DCR_BASE_STATE_BEGIN
#define VX_DCR_BASE_STATE_BEGIN 0x001
#endif

#ifndef VX_DCR_BASE_STATE_END
#define VX_DCR_BASE_STATE_END   0x041
#endif

// Startup address DCR offset (from VX_types.h)
#ifndef VX_DCR_BASE_STARTUP_ADDR0
#define VX_DCR_BASE_STARTUP_ADDR0 0x800
#endif

#ifndef VX_DCR_BASE_STARTUP_ADDR1  
#define VX_DCR_BASE_STARTUP_ADDR1 0x801
#endif

using namespace vortex;

// Global state
static Processor* g_processor = nullptr;
static RAM* g_ram = nullptr;
static Arch* g_arch = nullptr;
static bool g_initialized = false;
static uint64_t g_current_cycle = 0;

extern "C" {

void simx_cleanup() {
    std::cout << "[SimX-DPI] ========================================" << std::endl;
    std::cout << "[SimX-DPI] Cleaning up SimX..." << std::endl;
    
    if (g_processor) {
        delete g_processor;
        g_processor = nullptr;
        std::cout << "[SimX-DPI] Processor deleted" << std::endl;
    }
    
    if (g_ram) {
        delete g_ram;
        g_ram = nullptr;
        std::cout << "[SimX-DPI] RAM deleted" << std::endl;
    }
    
    if (g_arch) {
        delete g_arch;
        g_arch = nullptr;
        std::cout << "[SimX-DPI] Arch deleted" << std::endl;
    }
    
    g_initialized = false;
    g_current_cycle = 0;
    
    std::cout << "[SimX-DPI] Cleanup complete" << std::endl;
    std::cout << "[SimX-DPI] ========================================" << std::endl;
}

// Initialize SimX processor
int simx_init(int num_cores, int num_warps, int num_threads) {
    try {
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        std::cout << "[SimX-DPI] Initializing SimX Golden Model" << std::endl;
        std::cout << "[SimX-DPI] Cores=" << num_cores 
                  << ", Warps=" << num_warps 
                  << ", Threads=" << num_threads << std::endl;
        
        // Cleanup any previous instance
        if (g_initialized) {
            std::cout << "[SimX-DPI] Cleaning up previous instance..." << std::endl;
            simx_cleanup();
        }
        
        // Create architecture configuration
        g_arch = new Arch(num_cores, num_warps, num_threads);
        if (!g_arch) {
            std::cerr << "[SimX-DPI] Error: Failed to create Arch" << std::endl;
            return -1;
        }
        std::cout << "[SimX-DPI] Architecture created successfully" << std::endl;
        
        // Create RAM (4GB address space for 32-bit systems)
        // Use 0x100000000 for full 32-bit range
        g_ram = new RAM(0x100000000ULL);
        if (!g_ram) {
            std::cerr << "[SimX-DPI] Error: Failed to create RAM" << std::endl;
            delete g_arch;
            return -1;
        }
        std::cout << "[SimX-DPI] RAM created (4GB address space)" << std::endl;

        // Create processor
        g_processor = new Processor(*g_arch);
        if (!g_processor) {
            std::cerr << "[SimX-DPI] Error: Failed to create Processor" << std::endl;
            delete g_ram;
            delete g_arch;
            return -1;
        }
        
        // Attach RAM to processor
        g_processor->attach_ram(g_ram);
        std::cout << "[SimX-DPI] Processor created and RAM attached" << std::endl;
        
        g_initialized = true;
        g_current_cycle = 0;
        
        std::cout << "[SimX-DPI] Initialization successful" << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        return 0; 
        
    } catch (const std::exception& e) { 
        std::cerr << "[SimX-DPI] Init Exception: " << e.what() << std::endl;
        g_initialized = false;
        return -1; 
    } catch (...) {
        std::cerr << "[SimX-DPI] Init Error: Unknown exception" << std::endl;
        g_initialized = false;
        return -1;
    }
}

// Load kernel binary file to memory
int simx_load_bin(const char* filepath, uint64_t load_addr) {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }

    std::ifstream file(filepath, std::ios::binary | std::ios::ate);
    if (!file) {
        std::cerr << "[SimX-DPI] Error: Could not open file: " << filepath << std::endl;
        return -1;
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (!file.read((char*)buffer.data(), size)) {
        std::cerr << "[SimX-DPI] Error: Could not read file" << std::endl;
        return -1;
    }

    try {
        g_ram->write(buffer.data(), load_addr, size);
        std::cout << "[SimX-DPI] Loaded '" << filepath 
                  << "' (" << size << " bytes) at 0x" 
                  << std::hex << load_addr << std::dec << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error writing to RAM: " << e.what() << std::endl;
        return -1;
    }
}

// Write memory from SystemVerilog byte array
void simx_write_mem(uint64_t addr, int size, const svOpenArrayHandle data) {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return;
    }
    
    if (size <= 0) {
        std::cerr << "[SimX-DPI] Error: Invalid size " << size << std::endl;
        return;
    }
    
    uint8_t* src = (uint8_t*)svGetArrayPtr(data);
    if (!src) {
        std::cerr << "[SimX-DPI] Error: Invalid data pointer" << std::endl;
        return;
    }
    
    try {
        g_ram->write(src, addr, size);
        std::cout << "[SimX-DPI] Wrote " << size << " bytes to 0x" 
                  << std::hex << addr << std::dec << std::endl;
                  
        // Debug: print first few bytes
        std::cout << "[SimX-DPI] First bytes: ";
        for (int i = 0; i < std::min(16, size); i++) {
            printf("%02x ", src[i]);
        }
        std::cout << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in write_mem: " << e.what() << std::endl;
    }
}

// Read memory to SystemVerilog byte array
void simx_read_mem(uint64_t addr, int size, const svOpenArrayHandle data) {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return;
    }
    
    if (size <= 0) {
        std::cerr << "[SimX-DPI] Error: Invalid size " << size << std::endl;
        return;
    }
    
    uint8_t* dest = (uint8_t*)svGetArrayPtr(data);
    if (!dest) {
        std::cerr << "[SimX-DPI] Error: Invalid data pointer" << std::endl;
        return;
    }
    
    try {
        g_ram->read(dest, addr, size);
        std::cout << "[SimX-DPI] Read " << size << " bytes from 0x" 
                  << std::hex << addr << std::dec << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in read_mem: " << e.what() << std::endl;
    }
}

// Write DCR (Device Configuration Register)
void simx_dcr_write(uint32_t addr, uint32_t value) {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return;
    }
    
    std::cout << "[SimX-DPI] DCR Write: addr=0x" << std::hex << addr 
              << ", value=0x" << value << std::dec << std::endl;
    
    try {
        // Validate DCR address range
        if (addr >= VX_DCR_BASE_STATE_BEGIN && addr < VX_DCR_BASE_STATE_END) {
            g_processor->dcr_write(addr, value);
            std::cout << "[SimX-DPI] DCR write successful" << std::endl;
        } else {
            std::cerr << "[SimX-DPI] Warning: DCR address 0x" << std::hex 
                      << addr << std::dec << " outside valid range [0x" 
                      << std::hex << VX_DCR_BASE_STATE_BEGIN << " - 0x" 
                      << VX_DCR_BASE_STATE_END << ")" << std::dec << std::endl;
            // Still attempt the write - processor will validate
            g_processor->dcr_write(addr, value);
        }
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in dcr_write: " << e.what() << std::endl;
    }
}

// Run SimX to completion (Post-Mortem mode)
int simx_run() {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }
    
    try {
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        std::cout << "[SimX-DPI] Running processor to completion..." << std::endl;
        
        int exitcode = g_processor->run();
        
        std::cout << "[SimX-DPI] Execution finished" << std::endl;
        std::cout << "[SimX-DPI] Exit code: " << exitcode << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        
        return exitcode;
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in run: " << e.what() << std::endl;
        return -1;
    }
}

// Step SimX N cycles (On-the-Fly mode)
int simx_step(int cycles) {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }
    
    if (cycles <= 0) {
        std::cerr << "[SimX-DPI] Error: Invalid cycle count " << cycles << std::endl;
        return -1;
    }
    
    try {
        g_processor->step(cycles);
        g_current_cycle += cycles;
        
        // Periodic status (every 10000 cycles)
        if (g_current_cycle % 10000 == 0) {
            std::cout << "[SimX-DPI] Stepped to cycle " << g_current_cycle << std::endl;
        }
        
        // Check if processor is done (you need to implement is_done() in processor.cpp)
        // For now, return 0 to continue execution
        // Return non-zero when execution completes
        return 0;
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in step: " << e.what() << std::endl;
        return -1;
    }
}

// Get current simulation cycle
uint64_t simx_get_cycle() {
    return g_current_cycle;
}

// Cleanup

} // extern "C"