// // Copyright © 2019-2023
// //
// // Licensed under the Apache License, Version 2.0 (the "License");
// // you may not use this file except in compliance with the License.
// // You may obtain a copy of the License at
// // http://www.apache.org/licenses/LICENSE-2.0
// //
// // Unless required by applicable law or agreed to in writing, software
// // distributed under the License is distributed on an "AS IS" BASIS,
// // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// // See the License for the specific language governing permissions and
// // limitations under the License.

// #include <iostream>
// #include <iomanip>
// #include <string>
// #include <sstream>
// #include <fstream>
// #include <stdlib.h>
// #include <unistd.h>
// #include <sys/stat.h>
// #include "processor.h"
// #include "mem.h"
// #include "constants.h"
// #include <util.h>
// #include "core.h"
// #include "VX_types.h"

// using namespace vortex;

// static void show_usage() {
//    std::cout << "Usage: [-c <cores>] [-w <warps>] [-t <threads>] [-v: vector-test] [-s: stats] [-h: help] <program>" << std::endl;
// }

// uint32_t num_threads = NUM_THREADS;
// uint32_t num_warps = NUM_WARPS;
// uint32_t num_cores = NUM_CORES;
// bool showStats = false;
// bool vector_test = false;
// const char* program = nullptr;

// static void parse_args(int argc, char **argv) {
//   	int c;
//   	while ((c = getopt(argc, argv, "t:w:c:vsh")) != -1) {
//     	switch (c) {
//       case 't':
//         num_threads = atoi(optarg);
//         break;
//       case 'w':
//         num_warps = atoi(optarg);
//         break;
// 		  case 'c':
//         num_cores = atoi(optarg);
//         break;
//       case 'v':
//         vector_test = true;
//         break;
//       case 's':
//         showStats = true;
//         break;
//     	case 'h':
//       	show_usage();
//       	exit(0);
//     		break;
//     	default:
//       	show_usage();
//       	exit(-1);
//     	}
// 	}

// 	if (optind < argc) {
// 		program = argv[optind];
//     std::cout << "Running " << program << "..." << std::endl;
// 	} else {
// 		show_usage();
//     exit(-1);
// 	}
// }

// int main(int argc, char **argv) {
//   int exitcode = 0;

//   parse_args(argc, argv);

//   {
//     // create processor configuation
//     Arch arch(num_threads, num_warps, num_cores);

//     // create memory module
//     RAM ram(0, MEM_PAGE_SIZE);

//     // create processor
//     Processor processor(arch);

//     // attach memory module
//     processor.attach_ram(&ram);

// 	  // setup base DCRs
//     const uint64_t startup_addr(STARTUP_ADDR);
//     processor.dcr_write(VX_DCR_BASE_STARTUP_ADDR0, startup_addr & 0xffffffff);
//   #if (XLEN == 64)
//     processor.dcr_write(VX_DCR_BASE_STARTUP_ADDR1, startup_addr >> 32);
//   #endif
// 	  processor.dcr_write(VX_DCR_BASE_MPM_CLASS, 0);

//     // load program
//     {
//       std::string program_ext(fileExtension(program));
//       if (program_ext == "bin") {
//         ram.loadBinImage(program, startup_addr);
//       } else if (program_ext == "hex") {
//         ram.loadHexImage(program);
//       } else {
//         std::cerr << "Error: only *.bin or *.hex images supported." << std::endl;
//         return -1;
//       }
//     }
//   #ifndef NDEBUG
//     std::cout << "[VXDRV] START: program=" << program << std::endl;
//   #endif
//     // run simulation
//   #ifdef EXT_V_ENABLE
//     // vector test exitcode is a special case
//     if (vector_test) return (processor.run() != 1);
//   #endif
//     // else continue as normal
//     processor.run();

//     // read exitcode from @MPM.1
//     ram.read(&exitcode, (IO_MPM_ADDR + 8), 4);
//   }

  
// #ifdef MEM_DUMP_ENABLE
//     std::string file_path = "dump_mem_0.bin";
//     std::cout << "[Vortex-UVM-GP] SIMX: Writing memory dump to " << file_path << std::endl;

//     std::ofstream ofs(file_path, std::ios::binary);
//     if (!ofs) {
//         std::cerr << "Error: could not open " << file_path << " for writing." << std::endl;
//     } else {
//         // The RAM object is a std::vector, so we can use.data() and.size()
//         ofs.write(reinterpret_cast<const char*>(ram.data()), ram.size());
//         ofs.close();
//     }
// #endif



//   return exitcode;
// }

////////////////////////////////////////////////////////////////////////////////
// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>
#include <fstream>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <vector>
#include "processor.h"
#include "mem.h"
#include "constants.h"
#include <util.h>
#include "core.h"
#include "VX_types.h"

using namespace vortex;

static void show_usage() {
    std::cout << "Usage: [-c <cores>][-w <warps>][-t <threads>][-v: vector-test][-s: stats][-h: help] <program>" << std::endl;
}

uint32_t num_threads = NUM_THREADS;
uint32_t num_warps = NUM_WARPS;
uint32_t num_cores = NUM_CORES;
bool showStats = false;
bool vector_test = false;
const char* program = nullptr;

static void parse_args(int argc, char **argv) {
    int c;
    while ((c = getopt(argc, argv, "t:w:c:vsh")) != -1) {
        switch (c) {
        case 't':
            num_threads = atoi(optarg);
            break;
        case 'w':
            num_warps = atoi(optarg);
            break;
        case 'c':
            num_cores = atoi(optarg);
            break;
        case 'v':
            vector_test = true;
            break;
        case 's':
            showStats = true;
            break;
        case 'h':
            show_usage();
            exit(0);
            break;
        default:
            show_usage();
            exit(-1);
        }
    }

    if (optind < argc) {
        program = argv[optind];
        std::cout << "Running " << program << "..." << std::endl;
    } else {
        show_usage();
        exit(-1);
    }
}

int main(int argc, char **argv) {
    int exitcode = 0;

    parse_args(argc, argv);

    {
        // ============================
        // 🔹 Create Processor & Memory
        // ============================
        Arch arch(num_threads, num_warps, num_cores);
        RAM ram(0, MEM_PAGE_SIZE);
        Processor processor(arch);
        processor.attach_ram(&ram);

        // Setup base DCRs
        const uint64_t startup_addr(STARTUP_ADDR);
        processor.dcr_write(VX_DCR_BASE_STARTUP_ADDR0, startup_addr & 0xffffffff);
    #if (XLEN == 64)
        processor.dcr_write(VX_DCR_BASE_STARTUP_ADDR1, startup_addr >> 32);
    #endif
        processor.dcr_write(VX_DCR_BASE_MPM_CLASS, 0);

        // ============================
        // 🔹 Load program image
        // ============================
        {
            std::string program_ext(fileExtension(program));
            if (program_ext == "bin") {
                ram.loadBinImage(program, startup_addr);
            } else if (program_ext == "hex") {
                ram.loadHexImage(program);
            } else {
                std::cerr << "Error: only *.bin or *.hex images supported." << std::endl;
                return -1;
            }
        }

    #ifndef NDEBUG
        std::cout << " START: program=" << program << std::endl;
    #endif

        // ============================
        // 🔹 Run simulation
        // ============================
    #ifdef EXT_V_ENABLE
        if (vector_test)
            return (processor.run() != 1);
    #endif

        processor.run();

        // Read exitcode from @MPM.1
        ram.read(&exitcode, (IO_MPM_ADDR + 8), 4);

        // ============================
        // 🔹 Memory Dump for SIMX logs
        // ============================
        std::string dir_path = "logs";
        std::string file_path = dir_path + "/dump_mem_0_simx.bin";

        // Ensure logs directory exists
        mkdir(dir_path.c_str(), 0777);

        std::cout << "[Vortex-UVM-GP] SIMX: Writing memory dump to " << file_path << std::endl;

        std::ofstream ofs(file_path, std::ios::binary);
        if (!ofs) {
            std::cerr << "[DMEM_DUMP] Failed to open " << file_path << std::endl;
        } else {
            std::vector<uint8_t> buffer(ram.size());
            ram.read(buffer.data(), 0, ram.size());
            ofs.write(reinterpret_cast<const char*>(buffer.data()), buffer.size());
            ofs.close();
        }
    }


            // ==============================
        // 🔹 Memory Dump for SIMX output
        // ==============================
    //     if (true) {
    //         std::string file_path = "dump_mem_0_simx.bin";
    //         std::cout << "[Vortex-UVM-GP] SIMX: Writing memory dump to " << file_path << std::endl;

    //         std::ofstream ofs(file_path, std::ios::binary);
    //         if (!ofs) {
    //             std::cerr << "Error: could not open " << file_path << " for writing." << std::endl;
    //         } else {
    //             std::vector<uint8_t> buffer(ram.size()); // allocate memory for full dump
    //             ram.read(buffer.data(), 0, ram.size());  // ✅ correct order: (data, addr, size)
    //             ofs.write(reinterpret_cast<const char*>(buffer.data()), buffer.size());
    //             ofs.close();
    //         }
    //     }
    // }


    return exitcode;
}
