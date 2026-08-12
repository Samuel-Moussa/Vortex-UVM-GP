#include "svdpi.h"
#include <iostream>
#include <vector>
#include <fstream>
#include <stdint.h>
#include <cstring>
#include <sstream>
#include <iomanip>
#include <map>
#include <csetjmp>
#include <csignal>
#include <cstdlib>       // getenv/strtoull — SIMX_MAX_CYCLES override

// Vortex includes
#include "processor.h"
#include "arch.h"
#include "mem.h"
#include "simobject.h"   // SimPlatform — needed to reset the platform before stepping
#include <VX_config.h>
#include <VX_types.h>
#include "simx_cosim_record.h"
#include "cosim_loadfeed.h"
#include "golden_halt.h"

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

static std::string g_console;   // captured program stdout from simx_run()

// ── Crash guard ─────────────────────────────────────────────────────────────
// SimX can abort()/segfault inside Emulator::decode on instructions/memory it
// cannot model (decode SIGABRT). A raw abort() is NOT catchable by try/catch and
// would take down the whole vsim process. We install SIGABRT/SIGSEGV handlers
// around the step loop and siglongjmp back out so the model failure is converted
// to a sentinel return (-3) — the scoreboard maps that to UNVERIFIABLE.
static sigjmp_buf            g_simx_jmp;
static volatile sig_atomic_t g_simx_crashed = 0;
static void simx_crash_handler(int sig) {
    g_simx_crashed = 1;
    siglongjmp(g_simx_jmp, sig);
}

// ── Post-reset memory re-staging ────────────────────────────────────────────
// The one-shot device reset inside ProcessorImpl::step() drops SimX's lazily-
// allocated RAM pages back to poison (0xbaadf00d). Anything written to g_ram
// BEFORE that reset (program hex, bootstrap, kernel arg struct + buffers) is
// lost by the time the kernel executes. We cache every staged write here and
// replay it in simx_run() AFTER the reset, before stepping.
static std::map<uint64_t, std::vector<uint8_t>> g_staged_mem;

static void ram_write_cached(const uint8_t* src, uint64_t addr, uint32_t size) {
    g_ram->write(src, addr, size);
    g_staged_mem[addr] = std::vector<uint8_t>(src, src + size);
}

extern "C" {

// ============================================================================
// CLEANUP
// ============================================================================

void simx_cleanup() {
    std::cout << "[SimX-DPI] ========================================" << std::endl;
    std::cout << "[SimX-DPI] Cleaning up SimX..." << std::endl;
    
    if (g_processor) {
        g_processor->cosim_clear();  // M1: drop any unread retire records
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
        // Validate requested configuration against the SimX compile-time
        // constants. SimX is built with fixed values for some topology
        // parameters (NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS).
        // If the runtime request doesn't match the compiled model, fail
        // early with a clear diagnostic instead of throwing an exception
        // deep in the simulator internals.
#if defined(NUM_CORES) && defined(NUM_WARPS) && defined(NUM_THREADS)
        if (num_cores != NUM_CORES || num_warps != NUM_WARPS || num_threads != NUM_THREADS) {
            std::cerr << "[SimX-DPI] Configuration mismatch: simx_model.so was built for "
                      << "NUM_CORES=" << NUM_CORES << ", NUM_WARPS=" << NUM_WARPS
                      << ", NUM_THREADS=" << NUM_THREADS << " but simx_init() was called with "
                      << "num_cores=" << num_cores << ", num_warps=" << num_warps
                      << ", num_threads=" << num_threads << std::endl;
            std::cerr << "[SimX-DPI] Rebuild simx_model.so with matching -DNUM_* flags or "
                      << "use matching --cores/--warps/--threads in the run script." << std::endl;
            return -1;
        }
#endif
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
        
        // Keep RAM address space aligned with ISA width.
        #if (XLEN == 32)
            uint64_t capacity = 0x100000000ULL;         // 4GB flat space for RV32
        #else
            uint64_t capacity = 0;                      // Sparse/unbounded for RV64
        #endif
            uint32_t page_size = 4096;                  // 4KB pages
        
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
        ram_write_cached(bootstrap, bootstrap_addr, 16);
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
        ram_write_cached(buffer.data(), load_addr, size);
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
    static constexpr uint64_t BASE_ADDR_OFFSET = 0x80000000ULL;

    while (std::getline(file, line)) {
        // Strip CR/LF
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n'))
            line.pop_back();
        if (line.empty() || line[0] == '/' || line[0] == '#') continue;

        if (line[0] == '@') {
            // Address marker.
            // ALWAYS use BASE_ADDR_OFFSET for relative files (@0) so we don't accidentally
            // apply the bootstrap address (0x7FFFFFF0) to the main program offset.
            uint64_t raw_addr = std::stoull(line.substr(1), nullptr, 16);
            current_addr = (raw_addr == 0) ? BASE_ADDR_OFFSET : raw_addr;
            
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
                ram_write_cached(&b, current_addr++, 1);
                bytes_loaded++;
            } else {
                uint32_t w = std::stoul(token, nullptr, 16);
                uint8_t bytes[4] = {
                    (uint8_t)(w),
                    (uint8_t)(w >> 8),
                    (uint8_t)(w >> 16),
                    (uint8_t)(w >> 24)
                };
                ram_write_cached(bytes, current_addr, 4);
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
// Load hex file with base_addr offset applied to @addresses ONLY IF they are relative.
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
            // Address marker: apply base_addr ONLY if the address is relative (e.g., @00000000)
            uint64_t raw_addr = std::stoull(line.substr(1), nullptr, 16);
            
            if (raw_addr >= 0x80000000ULL) {
                // Address is already absolute (e.g., @80000000)
                current_addr = raw_addr;
            } else {
                // Address is relative (e.g., @00000000), add the base offset
                current_addr = raw_addr + base_addr;
            }
            continue;
        }

        // Parse space-separated tokens (byte or word format)
        std::istringstream iss(line);
        std::string tok;
        while (iss >> tok) {
            if (tok.size() <= 2) {
                // Byte format (--verilog-data-width=1)
                uint8_t b = (uint8_t)std::stoul(tok, nullptr, 16);
                ram_write_cached(&b, current_addr++, 1);
                bytes_loaded++;
            } else {
                // 32-bit word format (little-endian)
                uint32_t w = (uint32_t)std::stoul(tok, nullptr, 16);
                uint8_t bytes[4] = {
                    (uint8_t)(w),       (uint8_t)(w >> 8),
                    (uint8_t)(w >> 16), (uint8_t)(w >> 24)
                };
                ram_write_cached(bytes, current_addr, 4);
                current_addr += 4;
                bytes_loaded += 4;
            }
        }
    }

    std::cout << "[SimX-DPI] Loaded " << bytes_loaded
              << " bytes from '" << filepath
              << "' mapped to absolute memory" << std::endl;
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
    // Validate inputs first — independent of init state.
    if (size <= 0) {
        std::cerr << "[SimX-DPI] Error: Invalid size " << size << std::endl;
        return;
    }
    uint8_t* src = (uint8_t*)svGetArrayPtr(data);
    if (!src) {
        std::cerr << "[SimX-DPI] Error: Invalid data pointer" << std::endl;
        return;
    }

    // ALWAYS cache. This map is replayed into RAM by simx_run() AFTER the
    // device reset wipes pages to poison. Writes that arrive before
    // simx_init() (the test staging kernel args at time 0) MUST land here,
    // or they are lost and SimX reads 0xbaadf00d.
    g_staged_mem[addr] = std::vector<uint8_t>(src, src + size);

    // Only touch live RAM if SimX is up; otherwise the cached copy above is
    // applied by simx_run()'s re-stage loop.
    if (g_initialized && g_ram) {
        try {
            g_ram->write(src, addr, size);
        } catch (const std::exception& e) {
            std::cerr << "[SimX-DPI] Error in write_mem: " << e.what() << std::endl;
            return;
        }
    }

    // Infer the program startup address ONLY from writes in the program code
    // region (0x8xxx_xxxx). The regression harness stages kernel_arg_t + I/O
    // buffers in the DATA region (>= 0x9000_0000); those writes must NOT move
    // g_startup_addr, or the exit-code bootstrap is built on top of the arg
    // struct and SimX starts by executing data → decode abort at cycle 0.
    if (addr >= 0x80000000ULL && addr < 0x90000000ULL) g_startup_addr = addr;
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

        //  was: int run_status = g_processor->run();
        const uint64_t STEP_CHUNK = 100;        // cycles per step call

        // Hard cap on golden-model cycles. MUST be overridable: this is not a
        // safety net, it is a CORRECTNESS input. When SimX hits the cap it stops
        // with the memory it has written SO FAR, and every location the DUT wrote
        // afterwards then compares against 0 — turning "the golden model did not
        // finish" into thousands of fake MEM MISMATCH errors that look exactly
        // like a DUT bug. Measured 2026-08-12: wide_stress at 2CL/2C blew the old
        // hardcoded 2,000,000 and produced 4,115 such false mismatches (SimX=0x0
        // on every one) while the DUT completed 577,569 instructions correctly.
        //
        // The old comment ("basic needs ~1800; huge margin") sized this for small
        // kernels only; big programs and higher core counts are both far more
        // expensive, so a fixed number cannot be right for every config.
        // DEFAULT RAISED 2,000,000 -> 20,000,000 on 2026-08-12, from MEASUREMENT:
        // wide_stress at 2CL/2C needs 2,584,300 SimX cycles (DUT: 1,420,203 cycles /
        // 577,569 instructions). The old 2,000,000 was short by 584,300 (~23%) and
        // that shortfall alone produced 4,115 phantom MEM MISMATCH errors. Note SimX
        // cycles are NOT DUT cycles — here the ratio was ~1.82x — so sizing this from
        // a DUT +TIMEOUT is wrong; measure the golden model itself.
        // 20,000,000 is ~7.7x the heaviest measured program, which still bounds a
        // genuine runaway while leaving real programs room at higher core counts.
        uint64_t MAX_CYCLES = 20000000;
        if (const char* e = std::getenv("SIMX_MAX_CYCLES")) {
            uint64_t v = std::strtoull(e, nullptr, 0);
            if (v > 0) {
                MAX_CYCLES = v;
                std::cout << "[SimX-DPI] SIMX_MAX_CYCLES override: " << MAX_CYCLES
                          << " (default 2000000)" << std::endl;
            }
        }
        uint64_t cycles_run = 0;
        int run_status;

        // (1) Reset the sim platform BEFORE stepping, exactly as
        //     ProcessorImpl::run() does (it calls SimPlatform::instance().reset()
        //     then ticks). ProcessorImpl::step() does NOT reset — its reset line
        //     is commented out — and the old `step(0)` here was a no-op (cycles=0
        //     runs zero iterations), so the cores were ticked from an un-reset
        //     state and decoded garbage → abort at cycle 0. This do_reset()s every
        //     core/cache so PC starts at the DCR startup address. RAM (g_ram) is
        //     separate and is NOT cleared by this.
        SimPlatform::instance().reset();

        // (2) Replay every staged write (program, bootstrap, arg struct, buffers)
        //     so SimX's RAM matches what the harness staged (defensive; the reset
        //     above does not wipe RAM, but keeps parity with pre-init staging).
        for (auto& kv : g_staged_mem) {
            g_ram->write(kv.second.data(), kv.first, (uint32_t)kv.second.size());
        }
        std::cout << "[SimX-DPI] Re-staged " << g_staged_mem.size()
                  << " memory regions after reset" << std::endl;

        // RVVI load-bus (Phase A1(e)): reset per-warp LOAD cursors so ordinal
        // counting restarts for this run. Overrides pushed by the scoreboard
        // (pass 2) persist; a no-op when the feed is disabled/empty.
        vortex::loadfeed_rewind();
        vortex::compfeed_rewind();   // OBS-014 sqrt-writeback feed cursors

        // (3) Verify the arg struct is now real (not poison).
        {
            uint8_t dbg[24];
            g_ram->read(dbg, 0x90000000, 24);
            fprintf(stderr, "[SimX-ARGS] count=%08x src=%08x%08x dst=%08x%08x\n",
                    *(uint32_t*)(dbg+0),
                    *(uint32_t*)(dbg+12), *(uint32_t*)(dbg+8),
                    *(uint32_t*)(dbg+20), *(uint32_t*)(dbg+16));
        }

        // tee program output ONLY around the actual run
        std::ostringstream _cap;
        std::streambuf* _old = std::cout.rdbuf(_cap.rdbuf()); // tee ON

        // (4) Run to completion (bounded), guarded against a SimX abort()/segfault
        //     so a model decode failure CANNOT take down vsim. On crash we
        //     siglongjmp back here, restore stdout, and return sentinel -3.
        g_simx_crashed = 0;
        // A3: clear any record from a previous run, so a stale halt can never
        // relabel a fresh CRASH (-3) as a tidy GOLDEN_HALT (-4).
        vortex::golden_halt_clear();
        struct sigaction sa, old_abrt, old_segv;
        sa.sa_handler = simx_crash_handler;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = 0;
        sigaction(SIGABRT, &sa, &old_abrt);
        sigaction(SIGSEGV, &sa, &old_segv);

        if (sigsetjmp(g_simx_jmp, 1) == 0) {
            while (!g_processor->is_done() && cycles_run < MAX_CYCLES) {
                g_processor->step(STEP_CHUNK);
                cycles_run += STEP_CHUNK;
            }
        }
        // (crash path falls through here with g_simx_crashed == 1)

        sigaction(SIGABRT, &old_abrt, nullptr);
        sigaction(SIGSEGV, &old_segv, nullptr);

        std::cout.rdbuf(_old);                                  // tee OFF
        g_console += _cap.str();
        std::cout << _cap.str();                                // echo program output

        if (g_simx_crashed) {
            // SimX model aborted mid-run. Do NOT touch the processor again (its
            // state is undefined). Return a sentinel; either way the END-STATE
            // memory compare must be skipped, because SimX never reached a valid
            // final image.
            //
            // A3 splits what used to be one bucket:
            //   -4 GOLDEN_HALT — the model REFUSED at a recorded instruction
            //                    (golden_halt.h). We know the PC, the encoding and
            //                    the sub-field, so the gap is nameable and every
            //                    instruction lockstep-verified BEFORE it still
            //                    counts as real verification.
            //   -3 CRASH       — nothing recorded: SIGSEGV, or an abort site not
            //                    yet converted. Genuinely unknown, stays fully
            //                    UNVERIFIABLE. Keeping -3 distinct is what stops
            //                    an unconverted site from masquerading as a clean
            //                    halt.
            const vortex::golden_halt_t& gh = vortex::golden_halt_record();
            run_status = gh.valid ? -4 : -3;
            g_done     = false;
            g_exitcode = run_status;
            if (gh.valid) {
                std::cerr << "[SimX-DPI] GOLDEN_HALT after " << cycles_run
                          << " cycles: " << gh.where << " refused '" << gh.detail
                          << "' at PC=0x" << std::hex << gh.pc;
                if (gh.code)
                    std::cerr << " instr=0x" << std::setw(8) << std::setfill('0') << gh.code;
                std::cerr << std::dec << " (wid=" << gh.wid << ", " << gh.where
                          << ".cpp:" << gh.line << "). Instructions verified BEFORE this "
                          << "point remain valid; the end-state compare is skipped."
                          << std::endl;
            } else {
                std::cerr << "[SimX-DPI] WARNING: SimX crashed after " << cycles_run
                          << " cycles with NO recorded halt reason (segfault, or an abort "
                          << "site not yet converted). Caught so vsim survives; "
                          << "this run is UNVERIFIABLE." << std::endl;
            }
            std::cout << "[SimX-DPI] ========================================" << std::endl;
            return g_exitcode;
        }

        if (g_processor->is_done()) {
            run_status = g_processor->get_exitcode();
            std::cout << "[SimX-DPI] Clean exit after " << cycles_run
                    << " cycles, exitcode=" << run_status << std::endl;
        } else {
            // Hit the cap without the kernel signaling done — this is the
            // spawn-kernel / no-clean-EBREAK case. Stop GRACEFULLY instead of
            // letting an unbounded run() walk into unmapped memory and crash vsim.
            run_status = -2;   // distinct sentinel: "capped, not crashed"
            std::cerr << "[SimX-DPI] WARNING: hit cycle cap (" << MAX_CYCLES
                    << ") without clean exit — kernel likely lacks EBREAK termination. "
                    << "Stopping SimX gracefully so the scoreboard can still compare memory."
                    << std::endl;
        }

        // Processor::run() already returns the final exit code.
        g_done     = true;
        g_exitcode = run_status;
        
        std::cout << "[SimX-DPI] Execution finished" << std::endl;
        std::cout << "[SimX-DPI] Run status: " << run_status << std::endl;
        std::cout << "[SimX-DPI] Exit code: " << g_exitcode << std::endl;
        std::cout << "[SimX-DPI] ========================================" << std::endl;
        
        return g_exitcode;
        
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

    // This SimX backend only exposes run-to-completion.
    // Keep the DPI contract by treating the first step call as a full run.
    if (!g_step_initialized) {
        std::cout << "[SimX-DPI] simx_step: backend is run-to-completion; running once" << std::endl;
        g_step_initialized = true;
    }

    try {
        int exitcode = simx_run();
        if (exitcode < 0) {
            return -1;
        }

        g_current_cycle += cycles;
        std::cout << "[SimX-DPI] Program completed via simx_step at cycle "
                  << g_current_cycle << " (exitcode=" << g_exitcode << ")" << std::endl;
        return 1;

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

// Returns captured program console output (valid after simx_run)
const char* simx_get_console() {
    return g_console.c_str();
}

// ============================================================================
// M1 COSIM RETIRE-RECORD INTERFACE (Option β)
// ============================================================================
// SimX cores push one record per writeback-bearing Emulator::step() into a
// queue owned by Processor. SV-side scoreboard polls simx_cosim_pop() in a
// drain loop to match against DUT VX_commit_if events.

// Pop one record into scalar output args (DPI-portable; no struct alignment
// dependency between C and SV). The result[] open array must be sized to
// at least num_threads on the SV side; we write exactly that many entries.
// Returns: 1 on success, 0 if queue is empty, -1 on error.
int simx_cosim_pop(
    uint64_t* uuid,
    unsigned* cid,
    unsigned* wid,
    uint64_t* pc,
    unsigned* tmask,
    unsigned char* wb,
    unsigned char* is_fp,
    unsigned char* rd,
    unsigned char* sop,
    unsigned char* eop,
    unsigned char* fu_type,
    unsigned char* is_volatile,
    unsigned char* is_fsqrt,
    const svOpenArrayHandle result,
    const svOpenArrayHandle mem_addr
) {
    if (!g_processor) {
        std::cerr << "[SimX-DPI] simx_cosim_pop: processor not initialized" << std::endl;
        return -1;
    }
    vortex::simx_retire_t rec{};
    if (!g_processor->cosim_drain_retire(rec)) return 0;

    *uuid  = rec.uuid;
    *cid   = rec.cid;
    *wid   = rec.wid;
    *pc    = rec.pc;
    *tmask = rec.tmask;
    *wb    = rec.wb;
    *is_fp = rec.is_fp;
    *rd    = rec.rd;
    *sop   = rec.sop;
    *eop   = rec.eop;
    *fu_type = rec.fu_type;
    *is_volatile = rec.is_volatile;
    *is_fsqrt = rec.is_fsqrt;

    const int lo = svLow(result, 1);
    const int hi = svHigh(result, 1);
    const int n  = hi - lo + 1;
    for (int i = 0; i < n && i < SIMX_COSIM_MAX_THREADS; ++i) {
        uint64_t* slot = static_cast<uint64_t*>(svGetArrElemPtr1(result, lo + i));
        if (slot) *slot = rec.result[i];
    }
    // Per-thread effective LOAD address (OBS-002), same open-array convention.
    const int alo = svLow(mem_addr, 1);
    const int ahi = svHigh(mem_addr, 1);
    const int an  = ahi - alo + 1;
    for (int i = 0; i < an && i < SIMX_COSIM_MAX_THREADS; ++i) {
        uint64_t* slot = static_cast<uint64_t*>(svGetArrElemPtr1(mem_addr, alo + i));
        if (slot) *slot = rec.mem_addr[i];
    }
    return 1;
}

// Number of retire records currently queued.
unsigned simx_cosim_pending() {
    if (!g_processor) return 0;
    return g_processor->cosim_pending();
}

// Drop all queued records without consuming them.
void simx_cosim_clear() {
    if (g_processor) g_processor->cosim_clear();
}

// ============================================================================
// RVVI LOAD-BUS FEED (Phase A1(e)) — DUT-observed load values into SimX
// ============================================================================
// The SV lockstep scoreboard identifies provably-racy shared loads in pass 1,
// then (pass 2) pushes the DUT's captured per-lane writeback values here and
// re-runs SimX with the feed armed so SimX follows the DUT's memory ordering on
// exactly those loads. Keyed by (cid,wid,uuid); default OFF ⇒ no substitution.

void simx_cosim_load_feed_reset() {
    vortex::loadfeed_reset();
}

void simx_cosim_load_feed_enable(int en) {
    vortex::loadfeed_enable(en != 0);
}

// Push one DUT load override for the `occurrence`-th (0-based) execution of the
// LOAD at `pc` on warp (cid,wid). data[] is an SV open array sized to num_threads;
// feed_mask bit l set => override lane l with data[l].
void simx_cosim_load_feed_push(
    unsigned cid,
    unsigned wid,
    uint64_t pc,
    unsigned occurrence,
    unsigned feed_mask,
    const svOpenArrayHandle data
) {
    const int lo = svLow(data, 1);
    const int hi = svHigh(data, 1);
    const int n  = hi - lo + 1;
    uint64_t buf[SIMX_COSIM_MAX_THREADS] = {0};
    for (int i = 0; i < n && i < SIMX_COSIM_MAX_THREADS; ++i) {
        uint64_t* slot = static_cast<uint64_t*>(svGetArrElemPtr1(data, lo + i));
        if (slot) buf[i] = *slot;
    }
    vortex::loadfeed_push(cid, wid, pc, occurrence, feed_mask, buf,
                          (n < SIMX_COSIM_MAX_THREADS) ? (unsigned)n : SIMX_COSIM_MAX_THREADS);
}

// Diagnostics: pushed = records handed to SimX; consumed = records SimX actually
// matched at a load retirement. consumed==pushed ⇒ DUT and SimX uuids aligned.
unsigned simx_cosim_load_feed_pushed()   { return vortex::loadfeed_pushed(); }
unsigned simx_cosim_load_feed_consumed() { return vortex::loadfeed_consumed(); }

// --- A3 GOLDEN_HALT accessors -----------------------------------------------
// Valid only after simx_run() returned -4. They let the scoreboard NAME the
// instruction that stopped the golden instead of reporting a bare sentinel.
int      simx_golden_halt_valid()  { return vortex::golden_halt_record().valid; }
uint64_t simx_golden_halt_pc()     { return vortex::golden_halt_record().pc;    }
unsigned simx_golden_halt_code()   { return vortex::golden_halt_record().code;  }
unsigned simx_golden_halt_wid()    { return vortex::golden_halt_record().wid;   }
int      simx_golden_halt_line()   { return vortex::golden_halt_record().line;  }
const char* simx_golden_halt_where()  { return vortex::golden_halt_record().where;  }
const char* simx_golden_halt_detail() { return vortex::golden_halt_record().detail; }

// --- COMPUTE-writeback feed (OBS-014 sqrt reconvergence) — same contract as the
// load feed, applied at the FSQRT writeback (execute.cpp FPU lambda).
void simx_cosim_comp_feed_reset()      { vortex::compfeed_reset(); }
void simx_cosim_comp_feed_enable(int en){ vortex::compfeed_enable(en != 0); }
void simx_cosim_comp_feed_push(
    unsigned cid,
    unsigned wid,
    uint64_t pc,
    unsigned occurrence,
    unsigned feed_mask,
    const svOpenArrayHandle data
) {
    const int lo = svLow(data, 1);
    const int hi = svHigh(data, 1);
    const int n  = hi - lo + 1;
    uint64_t buf[SIMX_COSIM_MAX_THREADS] = {0};
    for (int i = 0; i < n && i < SIMX_COSIM_MAX_THREADS; ++i) {
        uint64_t* slot = static_cast<uint64_t*>(svGetArrElemPtr1(data, lo + i));
        if (slot) buf[i] = *slot;
    }
    vortex::compfeed_push(cid, wid, pc, occurrence, feed_mask, buf,
                          (n < SIMX_COSIM_MAX_THREADS) ? (unsigned)n : SIMX_COSIM_MAX_THREADS);
}
unsigned simx_cosim_comp_feed_pushed()   { return vortex::compfeed_pushed(); }
unsigned simx_cosim_comp_feed_consumed() { return vortex::compfeed_consumed(); }

} // extern "C"