////////////////////////////////////////////////////////////////////////////////
// File: simx_dpi.cpp
// Description: DPI-C Bridge between SystemVerilog UVM and SimX C++ Model
//
// Provides C-callable functions for:
//   - SimX initialization and cleanup
//   - Memory read/write operations
//   - DCR (Device Configuration Register) access
//   - Processor execution control
//   - State inspection and debugging
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

#include "svdpi.h"
#include <iostream>
#include <fstream>
#include <cstring>
#include <cstdint>
#include <exception>
#include <vector>

// SimX includes (adjust paths based on your Vortex installation)
#include "processor.h"
#include "arch.h"
#include "mem.h"

using namespace vortex;

//==============================================================================
// Global State
//==============================================================================
static Processor* g_processor = nullptr;
static RAM* g_ram = nullptr;
static bool g_initialized = false;

//==============================================================================
// Helper Functions
//==============================================================================

static void log_info(const char* msg) {
    std::cout << "[SimX-DPI INFO] " << msg << std::endl;
}

static void log_error(const char* msg) {
    std::cerr << "[SimX-DPI ERROR] " << msg << std::endl;
}

//==============================================================================
// DPI-C Exported Functions
//==============================================================================

extern "C" {

/**
 * Initialize SimX processor with specified architecture
 * Returns: 0 on success, -1 on failure
 */
int simx_init(int num_cores, int num_warps, int num_threads) {
    try {
        if (g_initialized) {
            log_error("SimX already initialized! Call simx_cleanup() first.");
            return -1;
        }

        std::cout << "[SimX-DPI] Initializing with " 
                  << num_cores << " cores, "
                  << num_warps << " warps, "
                  << num_threads << " threads" << std::endl;

        // Create architecture configuration
        Arch arch(num_cores, num_warps, num_threads);

        // Create 4GB RAM to cover full 32-bit address space
        g_ram = new RAM(0xFFFFFFFF);
        
        // Create processor and attach RAM
        g_processor = new Processor(arch);
        g_processor->attach_ram(g_ram);

        g_initialized = true;
        log_info("Initialization successful");
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Init Error: " << e.what() << std::endl;
        return -1;
    }
}

/**
 * Load program from file into SimX memory
 * Returns: 0 on success, -1 on failure
 */
int simx_load_program(const char* filename, uint64_t load_addr) {
    if (!g_initialized || !g_ram) {
        log_error("SimX not initialized");
        return -1;
    }

    try {
        std::ifstream file(filename, std::ios::binary | std::ios::ate);
        if (!file.is_open()) {
            std::cerr << "[SimX-DPI] Failed to open file: " << filename << std::endl;
            return -1;
        }

        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);

        std::vector<uint8_t> buffer(size);
        if (!file.read((char*)buffer.data(), size)) {
            log_error("Failed to read program file");
            return -1;
        }

        g_ram->write(buffer.data(), load_addr, size);

        std::cout << "[SimX-DPI] Loaded " << size << " bytes from " 
                  << filename << " to 0x" << std::hex << load_addr << std::dec << std::endl;
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Load Error: " << e.what() << std::endl;
        return -1;
    }
}

/**
 * Write memory from SystemVerilog byte array
 */
void simx_write_mem(uint64_t addr, int size, const svOpenArrayHandle data) {
    if (!g_initialized || !g_ram) {
        log_error("SimX not initialized");
        return;
    }

    try {
        uint8_t* src = (uint8_t*)svGetArrayPtr(data);
        if (src) {
            g_ram->write(src, addr, size);
            std::cout << "[SimX-DPI] Wrote " << size << " bytes to addr 0x" 
                      << std::hex << addr << std::dec << std::endl;
        } else {
            log_error("Invalid data pointer");
        }
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Write Error: " << e.what() << std::endl;
    }
}

/**
 * Read memory into SystemVerilog byte array
 */
void simx_read_mem(uint64_t addr, int size, const svOpenArrayHandle data) {
    if (!g_initialized || !g_ram) {
        log_error("SimX not initialized");
        return;
    }

    try {
        uint8_t* dst = (uint8_t*)svGetArrayPtr(data);
        if (dst) {
            g_ram->read(dst, addr, size);
            std::cout << "[SimX-DPI] Read " << size << " bytes from addr 0x" 
                      << std::hex << addr << std::dec << std::endl;
        } else {
            log_error("Invalid data pointer");
        }
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Read Error: " << e.what() << std::endl;
    }
}

/**
 * Write to Device Configuration Register (DCR)
 * Returns: 0 on success, -1 on failure
 */
int simx_dcr_write(uint32_t addr, uint32_t data) {
    if (!g_initialized || !g_processor) {
        log_error("SimX not initialized");
        return -1;
    }

    try {
        g_processor->dcr_write(addr, data);
        std::cout << "[SimX-DPI] DCR Write: addr=0x" << std::hex << addr 
                  << " data=0x" << data << std::dec << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] DCR Write Error: " << e.what() << std::endl;
        return -1;
    }
}

/**
 * Read from Device Configuration Register (DCR)
 * Returns: DCR value
 */
uint32_t simx_dcr_read(uint32_t addr) {
    if (!g_initialized || !g_processor) {
        log_error("SimX not initialized");
        return 0xDEADBEEF;
    }

    try {
        uint32_t value = g_processor->dcr_read(addr);
        std::cout << "[SimX-DPI] DCR Read: addr=0x" << std::hex << addr 
                  << " data=0x" << value << std::dec << std::endl;
        return value;
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] DCR Read Error: " << e.what() << std::endl;
        return 0xDEADBEEF;
    }
}

/**
 * Run SimX for specified number of cycles
 * Returns: 0 if still running, 1 if completed, -1 on error
 */
int simx_run(int max_cycles) {
    if (!g_initialized || !g_processor) {
        log_error("SimX not initialized");
        return -1;
    }

    try {
        int cycles = 0;
        while (cycles < max_cycles) {
            if (g_processor->running()) {
                g_processor->step();
                cycles++;
            } else {
                std::cout << "[SimX-DPI] Execution completed after " 
                          << cycles << " cycles" << std::endl;
                return 1; // Completed
            }
        }
        return 0; // Still running
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Run Error: " << e.what() << std::endl;
        return -1;
    }
}

/**
 * Single-step SimX execution
 * Returns: 1 if still running, 0 if completed, -1 on error
 */
int simx_step() {
    if (!g_initialized || !g_processor) {
        log_error("SimX not initialized");
        return -1;
    }

    try {
        if (g_processor->running()) {
            g_processor->step();
            return 1;
        }
        return 0; // Completed
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Step Error: " << e.what() << std::endl;
        return -1;
    }
}

/**
 * Check if processor is busy/running
 * Returns: 1 if busy, 0 if idle
 */
int simx_is_busy() {
    if (!g_initialized || !g_processor) {
        return 0;
    }
    return g_processor->running() ? 1 : 0;
}

/**
 * Get performance counters
 */
void simx_get_perf_counters(
    uint64_t* cycles,
    uint64_t* instructions
) {
    if (!g_initialized || !g_processor) {
        *cycles = 0;
        *instructions = 0;
        return;
    }

    // Get performance stats from processor
    // (Adjust based on actual SimX API)
    *cycles = g_processor->get_cycle_count();
    *instructions = g_processor->get_instr_count();
}

/**
 * Dump processor state for debugging
 */
void simx_dump_state() {
    if (!g_initialized || !g_processor) {
        log_error("SimX not initialized");
        return;
    }

    try {
        log_info("Dumping processor state:");
        // Call SimX internal debug dump
        g_processor->dump_state(std::cout);
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Dump Error: " << e.what() << std::endl;
    }
}

/**
 * Cleanup SimX resources
 */
void simx_cleanup() {
    if (!g_initialized) {
        return;
    }

    log_info("Cleaning up SimX");

    if (g_processor) {
        delete g_processor;
        g_processor = nullptr;
    }

    if (g_ram) {
        delete g_ram;
        g_ram = nullptr;
    }

    g_initialized = false;
    log_info("Cleanup complete");
}

} // extern "C"
