#include "svdpi.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <stdint.h>
#include <cstring>
#include <sstream>

// Vortex includes
#include "processor.h"
#include "arch.h"
#include "mem.h"
#include <VX_config.h>
#include <VX_types.h>

using namespace vortex;

// Global state
static Processor* g_processor   = nullptr;
static RAM*       g_ram         = nullptr;
static Arch*      g_arch        = nullptr;
static bool       g_initialized = false;
static bool       g_ram_attached= false;
static uint64_t   g_current_cycle = 0;
static uint64_t   g_startup_addr  = 0x80000000;

// Execution completion state (used by simx_is_done / simx_get_exitcode)
static bool       g_done        = false;
static int        g_exitcode    = 0;
static bool       g_step_initialized = false;  // tracks first step() call

extern "C" {

// ============================================================================
// CLEANUP
// ============================================================================

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
    g_ram_attached = false;
    g_current_cycle = 0;
    g_startup_addr = 0;
    g_done          = false;   
    g_exitcode      = 0;       
    g_step_initialized  = false;

    std::cout << "[SimX-DPI] Cleanup complete" << std::endl;
    std::cout << "[SimX-DPI] ========================================" << std::endl;
}

// ============================================================================
// INITIALIZATION FUNCTIONS
// ============================================================================

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
        
        // Create architecture configuration (CORRECT ORDER!)
        // Arch(num_threads, num_warps, num_cores)
        g_arch = new Arch(num_threads, num_warps, num_cores);
        if (!g_arch) {
            std::cerr << "[SimX-DPI] Error: Failed to create Arch" << std::endl;
            return -1;
        }
        std::cout << "[SimX-DPI] Architecture created successfully" << std::endl;
        
        // Create RAM with proper page size (CRITICAL FIX #1)
        uint64_t capacity = 0x100000000ULL;  // 4GB capacity
        uint32_t page_size = 4096;            // 4KB pages (not 4GB!)
        
        std::cout << "[SimX-DPI] Creating RAM: capacity=0x" << std::hex << capacity 
                  << ", page_size=0x" << page_size << std::dec << std::endl;
        
        g_ram = new RAM(capacity, page_size);
        if (!g_ram) {
            std::cerr << "[SimX-DPI] Error: Failed to create RAM" << std::endl;
            delete g_arch;
            return -1;
        }
        std::cout << "[SimX-DPI] RAM created successfully" << std::endl;

        // Create processor
        g_processor = new Processor(*g_arch);
        if (!g_processor) {
            std::cerr << "[SimX-DPI] Error: Failed to create Processor" << std::endl;
            delete g_ram;
            delete g_arch;
            return -1;
        }
        
        // Attach RAM to processor
        std::cout << "[SimX-DPI] Attaching RAM to processor..." << std::endl;
        g_processor->attach_ram(g_ram);
        g_ram_attached = true;
        std::cout << "[SimX-DPI] RAM attached successfully" << std::endl;
        
        // Verify RAM works
        std::cout << "[SimX-DPI] Verifying RAM..." << std::endl;
        uint8_t test_data[4] = {0xDE, 0xAD, 0xBE, 0xEF};
        uint8_t read_data[4] = {0};
        uint64_t test_addr = 0x80000000ULL;
        
        g_ram->write(test_data, test_addr, 4);
        g_ram->read(read_data, test_addr, 4);
        
        bool ram_ok = true;
        for (int i = 0; i < 4; i++) {
            if (read_data[i] != test_data[i]) {
                std::cerr << "[SimX-DPI] RAM verification failed at byte " << i << std::endl;
                ram_ok = false;
            }
        }
        
        if (ram_ok) {
            std::cout << "[SimX-DPI] RAM verification PASSED" << std::endl;
            // Clear test data
            uint8_t zeros[4] = {0};
            g_ram->write(zeros, test_addr, 4);
        } else {
            std::cerr << "[SimX-DPI] RAM verification FAILED!" << std::endl;
            return -1;
        }
        
        g_initialized = true;
        g_current_cycle = 0;
        
        std::cout << "[SimX-DPI] Initialization successful" << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        return 0; 
        
    } catch (const std::exception& e) { 
        std::cerr << "[SimX-DPI] Init Exception: " << e.what() << std::endl;
        g_initialized = false;
        g_ram_attached = false;
        return -1; 
    } catch (...) {
        std::cerr << "[SimX-DPI] Init Error: Unknown exception" << std::endl;
        g_initialized = false;
        g_ram_attached = false;
        return -1;
    }
}

// ============================================================================
// NEW FUNCTION: Initialize Exit Code Register (x3)
// ============================================================================

void simx_init_exit_code_register() {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: Cannot init registers - SimX not initialized" << std::endl;
        return;
    }
    
    std::cout << "[SimX-DPI] ========================================" << std::endl;
    std::cout << "[SimX-DPI] Installing Exit Code Bootstrap" << std::endl;
    
    // Save original startup address
    uint64_t original_startup = g_startup_addr;
    
    // Place bootstrap code 16 bytes BEFORE the main program
    uint64_t bootstrap_addr = original_startup - 16;
    
    std::cout << "[SimX-DPI] Bootstrap address: 0x" << std::hex << bootstrap_addr << std::dec << std::endl;
    std::cout << "[SimX-DPI] Main program at:   0x" << std::hex << original_startup << std::dec << std::endl;
    
    // Bootstrap program:
    // 1. Set x3 = 0 (exit code register)
    // 2. Jump to main program
    // uint8_t bootstrap[16] = {
    //     // Instruction 1: addi x3, x0, 0  (set x3 = 0)
    //     // Encoding: 0x00000193
    //     0x93, 0x01, 0x00, 0x00,
        
    //     // Instruction 2: auipc x1, 0  (get current PC into x1)
    //     // Encoding: 0x00000097
    //     0x97, 0x00, 0x00, 0x00,
        
    //     // Instruction 3: jalr x0, x1, 16  (jump to x1 + 16)
    //     // Encoding: 0x01008067
    //     0x67, 0x80, 0x00, 0x01,
        
    //     // Instruction 4: nop (padding)
    //     0x13, 0x00, 0x00, 0x00
    // };
        uint8_t bootstrap[16] = {
        // Instruction 1: addi x3, x0, 0  (set x3 = 0)
        // Encoding: 0x00000193  [imm=0, rs1=x0, rd=x3, opcode=OP-IMM]
        0x93, 0x01, 0x00, 0x00,

        // Instruction 2: auipc x1, 0  (x1 = PC of THIS instruction = bootstrap_addr+4)
        // Encoding: 0x00000097  [imm=0, rd=x1, opcode=AUIPC]
        0x97, 0x00, 0x00, 0x00,

        // Instruction 3: jalr x0, x1, 12  (jump to x1+12 = bootstrap_addr+4+12 = original_startup)
        // FIXED: imm must be 12 (not 16).  Encoding: 0x00C08067
        // Old WRONG encoding was 0x01008067 (imm=16) → skipped first instruction of user program
        0x67, 0x80, 0xC0, 0x00,

        // Instruction 4: nop (padding, never reached)
        0x13, 0x00, 0x00, 0x00
    };
    try {
        // Write bootstrap to memory
        g_ram->write(bootstrap, bootstrap_addr, 16);
        std::cout << "[SimX-DPI] Bootstrap code written to memory" << std::endl;
        
        // Update startup address to point to bootstrap
        g_startup_addr = bootstrap_addr;
        
        // Configure DCRs to start at bootstrap address
        g_processor->dcr_write(VX_DCR_BASE_STARTUP_ADDR0, bootstrap_addr & 0xFFFFFFFF);
        
        #if (XLEN == 64)
        if ((bootstrap_addr >> 32) != 0) {
            g_processor->dcr_write(VX_DCR_BASE_STARTUP_ADDR1, bootstrap_addr >> 32);
        }
        #endif
        
        std::cout << "[SimX-DPI] DCRs updated to start at bootstrap" << std::endl;
        std::cout << "[SimX-DPI] Bootstrap will:" << std::endl;
        std::cout << "[SimX-DPI]   1. Set x3 = 0 (exit code)" << std::endl;
        std::cout << "[SimX-DPI]   2. Jump to 0x" << std::hex << original_startup << " (auipc+jalr x1+12)" << std::dec << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error installing bootstrap: " << e.what() << std::endl;
        // Restore original startup address
        g_startup_addr = original_startup;
    }
}

// ============================================================================
// MEMORY OPERATIONS
// ============================================================================

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
        
        g_startup_addr = load_addr;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error writing to RAM: " << e.what() << std::endl;
        return -1;
    }
}

// REPLACE the entire simx_load_hex function with this:
int simx_load_hex(const char* filepath) {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: not initialized" << std::endl;
        return -1;
    }

    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "[SimX-DPI] Cannot open hex file: " << filepath << std::endl;
        return -1;
    }

    std::string line;
    uint64_t current_addr = 0;
    int bytes_loaded = 0;
    bool format_detected = false;
    bool is_byte_format  = true;   // objcopy --verilog-data-width=1
    //to_solve Samual_fatials 
    static constexpr uint64_t BASE_ADDR_OFFSET = 0x80000000ULL;

    while (std::getline(file, line)) {
        // Strip CR/LF
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n'))
            line.pop_back();
        if (line.empty() || line[0] == '/' || line[0] == '#') continue;

        if (line[0] == '@') {
            // Address marker
            current_addr = std::stoull(line.substr(1), nullptr, 16);
                // Add base offset
                current_addr += BASE_ADDR_OFFSET;
            if (bytes_loaded == 0) g_startup_addr = current_addr;
            format_detected = false;   // re-detect on next data line
            continue;
        }

        // Tokenise on whitespace
        std::istringstream iss(line);
        std::string token;
        bool first_token = true;

        while (iss >> token) {
            if (first_token && !format_detected) {
                is_byte_format  = (token.size() <= 2);
                format_detected = true;
            }
            first_token = false;

            if (is_byte_format) {
                uint8_t b = (uint8_t)std::stoul(token, nullptr, 16);
                g_ram->write(&b, current_addr++, 1);
                bytes_loaded++;
            } else {
                uint32_t w = std::stoul(token, nullptr, 16);
                uint8_t bytes[4] = {
                    (uint8_t)(w),
                    (uint8_t)(w >> 8),
                    (uint8_t)(w >> 16),
                    (uint8_t)(w >> 24)
                };
                g_ram->write(bytes, current_addr, 4);
                current_addr  += 4;
                bytes_loaded  += 4;
            }
        }
    }

    std::cout << "[SimX-DPI] Loaded " << bytes_loaded
              << " bytes from hex '" << filepath
              << "' startup=0x" << std::hex << g_startup_addr << std::dec << std::endl;

    // Apply startup address to DCR
    g_processor->dcr_write(VX_DCR_BASE_STARTUP_ADDR0, g_startup_addr & 0xFFFFFFFF);
    return (bytes_loaded > 0) ? 0 : -1;
}

// Load hex file with base_addr offset applied to @addresses.
// Handles both byte format (--verilog-data-width=1) and word format.
// Does NOT change g_startup_addr — caller controls that via bootstrap.
int simx_load_hex_at(const char* filepath, uint64_t base_addr) {
    if (!g_initialized || !g_ram) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }

    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "[SimX-DPI] Cannot open hex file: " << filepath << std::endl;
        return -1;
    }

    std::string line;
    uint64_t current_addr = base_addr;
    int bytes_loaded = 0;

    while (std::getline(file, line)) {
        // Strip CR/LF
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n'))
            line.pop_back();
        if (line.empty() || line[0] == '/' || line[0] == '#') continue;

        if (line[0] == '@') {
            // Address marker: apply base_addr offset
            uint64_t rel = std::stoull(line.substr(1), nullptr, 16);
            current_addr = rel + base_addr;
            std::cout << "[SimX-DPI] hex_at: @" << std::hex << rel
                      << " → absolute 0x" << current_addr << std::dec << std::endl;
            continue;
        }

        // Parse space-separated tokens (byte or word format)
        std::istringstream iss(line);
        std::string tok;
        while (iss >> tok) {
            if (tok.size() <= 2) {
                // Byte format (--verilog-data-width=1)
                uint8_t b = (uint8_t)std::stoul(tok, nullptr, 16);
                g_ram->write(&b, current_addr++, 1);
                bytes_loaded++;
            } else {
                // 32-bit word format (little-endian)
                uint32_t w = (uint32_t)std::stoul(tok, nullptr, 16);
                uint8_t bytes[4] = {
                    (uint8_t)(w),       (uint8_t)(w >> 8),
                    (uint8_t)(w >> 16), (uint8_t)(w >> 24)
                };
                g_ram->write(bytes, current_addr, 4);
                current_addr += 4;
                bytes_loaded += 4;
            }
        }
    }

    std::cout << "[SimX-DPI] Loaded " << bytes_loaded
              << " bytes from '" << filepath
              << "' at base=0x" << std::hex << base_addr << std::dec << std::endl;
    return 0;
}

// Load .hex file 
// int simx_load_hex(const char* filepath) {
//     if (!g_initialized || !g_ram) {
//         std::cerr << "[SimX-DPI] Error: not initialized" << std::endl;
//         return -1;
//     }

//     std::ifstream file(filepath);
//     if (!file.is_open()) {
//         std::cerr << "[SimX-DPI] Cannot open hex file: " << filepath << std::endl;
//         return -1;
//     }

//     std::string line;
//     uint64_t current_addr = 0;
//     int words_loaded = 0;

//     while (std::getline(file, line)) {
//         // Trim whitespace
//         while (!line.empty() && isspace(line.front())) line.erase(line.begin());
//         while (!line.empty() && isspace(line.back()))  line.pop_back();
//         if (line.empty()) continue;

//         if (line[0] == '@') {
//             // Address line: @80000000
//             current_addr = std::stoull(line.substr(1), nullptr, 16);
//             g_startup_addr = current_addr;
//             std::cout << "[SimX-DPI] Hex load address: 0x" 
//                       << std::hex << current_addr << std::dec << std::endl;
//         } else {
//             // Data word (little-endian 32-bit stored as big-endian hex text)
//             uint32_t word = std::stoul(line, nullptr, 16);
//             // Write as little-endian bytes into RAM
//             uint8_t bytes[4];
//             bytes[0] = (word)       & 0xFF;
//             bytes[1] = (word >> 8)  & 0xFF;
//             bytes[2] = (word >> 16) & 0xFF;
//             bytes[3] = (word >> 24) & 0xFF;
//             g_ram->write(bytes, current_addr, 4);
//             current_addr += 4;
//             words_loaded++;
//         }
//     }

//     std::cout << "[SimX-DPI] Loaded " << words_loaded 
//               << " words from hex file" << std::endl;
    
//     // Set DCR startup address
//     g_processor->dcr_write(VX_DCR_BASE_STARTUP_ADDR0, 
//                             g_startup_addr & 0xFFFFFFFF);
//     return 0;
// }

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
        
        if (addr >= 0x80000000ULL) {
            g_startup_addr = addr;
        }
        
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

// ============================================================================
// DCR (Device Configuration Register) OPERATIONS
// ============================================================================

// Write DCR
void simx_dcr_write(uint32_t addr, uint32_t value) {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return;
    }
    
    std::cout << "[SimX-DPI] DCR Write: addr=0x" << std::hex << addr 
              << ", value=0x" << value << std::dec << std::endl;
    
    try {
        g_processor->dcr_write(addr, value);
        std::cout << "[SimX-DPI] DCR write successful" << std::endl;
        
        if (addr == VX_DCR_BASE_STARTUP_ADDR0) {
            g_startup_addr = (g_startup_addr & 0xFFFFFFFF00000000ULL) | value;
        } else if (addr == VX_DCR_BASE_STARTUP_ADDR1) {
            g_startup_addr = (g_startup_addr & 0x00000000FFFFFFFFULL) | (((uint64_t)value) << 32);
        }
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in dcr_write: " << e.what() << std::endl;
    }
}

// ============================================================================
// EXECUTION FUNCTIONS
// ============================================================================

// Run SimX to completion (Post-Mortem mode)
int simx_run() {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }
    
    try {
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        std::cout << "[SimX-DPI] Running processor to completion..." << std::endl;
        std::cout << "[SimX-DPI] Startup address: 0x" << std::hex << g_startup_addr << std::dec << std::endl;
        
        int exitcode = g_processor->run();
        // Mark execution as complete so simx_is_done() returns 1
        g_done     = true;
        g_exitcode = exitcode;
        
        std::cout << "[SimX-DPI] Execution finished" << std::endl;
        std::cout << "[SimX-DPI] Exit code: " << exitcode << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        
        return exitcode;
        
    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in run: " << e.what() << std::endl;
        return -1;
    }
}

// ============================================================================
// EXECUTION FUNCTIONS - On-the-Fly mode
// ============================================================================

// Step SimX N cycles.
// Returns:  0  = still running (call step again)
//           1  = execution completed normally
//          -1  = error
int simx_step(int cycles) {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] Error: SimX not initialized" << std::endl;
        return -1;
    }

    if (cycles <= 0) {
        std::cerr << "[SimX-DPI] Error: Invalid cycle count " << cycles << std::endl;
        return -1;
    }

    // Already finished — don't step further
    if (g_done) {
        std::cout << "[SimX-DPI] simx_step: already done (exitcode=" << g_exitcode << ")" << std::endl;
        return 1;
    }

        // First step call: initialize SimPlatform (run() does this itself internally)
    if (!g_step_initialized) {
        std::cout << "[SimX-DPI] simx_step: first call — initializing SimPlatform" << std::endl;
        SimPlatform::instance().reset();
        g_step_initialized = true;
    }

    try {
        // Processor::step() takes uint64_t — safe cast since we checked cycles > 0
        g_processor->step(static_cast<uint64_t>(cycles));
        g_current_cycle += cycles;

        if (g_current_cycle % 10000 == 0) {
            std::cout << "[SimX-DPI] Stepped to cycle " << g_current_cycle << std::endl;
        }

        // --- Pattern A: use Processor::is_done() directly ---
        if (g_processor->is_done()) {
            g_done     = true;
            g_exitcode = g_processor->get_exitcode();  // requires Bug 2 fix above
            std::cout << "[SimX-DPI] Program completed at cycle " << g_current_cycle
                      << " (exitcode=" << g_exitcode << ")" << std::endl;
            return 1;  // signal completion to SystemVerilog
        }

        return 0;  // still running

    } catch (const std::exception& e) {
        std::cerr << "[SimX-DPI] Error in simx_step: " << e.what() << std::endl;
        return -1;
    }
}

// ============================================================================
// STATUS QUERY FUNCTIONS
// ============================================================================

// Returns 1 when program has finished, 0 if still running, -1 if not init
int simx_is_done() {
    if (!g_initialized || !g_processor) {
        std::cerr << "[SimX-DPI] simx_is_done: not initialized" << std::endl;
        return -1;
    }
    // Sync the global flag with the processor's actual state
    if (!g_done && g_processor->is_done()) {
        g_done     = true;
        g_exitcode = g_processor->get_exitcode();
    }
    return g_done ? 1 : 0;
}

// Returns exit code. Valid only after simx_is_done() == 1
int simx_get_exitcode() {
    if (!g_done) {
        std::cerr << "[SimX-DPI] simx_get_exitcode: program not finished yet" << std::endl;
        return -1;
    }
    return g_exitcode;
}

} // extern "C"