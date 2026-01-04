// #include <stdio.h>
// #include <stdlib.h>
// #include <assert.h>
// #include <math.h>
// #include <CL/opencl.h>
// #include <unistd.h>
// #include <string.h>
// #include <chrono>
// #include <vector>
// #include "common.h"
// #include <fstream>


// #define KERNEL_NAME "vecadd"

// #define FLOAT_ULP 6

// #define CL_CHECK(_expr)                                                \
//    do {                                                                \
//      cl_int _err = _expr;                                              \
//      if (_err == CL_SUCCESS)                                           \
//        break;                                                          \
//      printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);   \
// 	 cleanup();			                                                     \
//      exit(-1);                                                         \
//    } while (0)

// #define CL_CHECK2(_expr)                                               \
//    ({                                                                  \
//      cl_int _err = CL_INVALID_VALUE;                                   \
//      decltype(_expr) _ret = _expr;                                     \
//      if (_err != CL_SUCCESS) {                                         \
//        printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
// 	   cleanup();			                                                   \
//        exit(-1);                                                       \
//      }                                                                 \
//      _ret;                                                             \
//    })

// static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
//   if (nullptr == filename || nullptr == data || 0 == size)
//     return -1;

//   FILE* fp = fopen(filename, "r");
//   if (NULL == fp) {
//     fprintf(stderr, "Failed to load kernel.");
//     return -1;
//   }
//   fseek(fp , 0 , SEEK_END);
//   long fsize = ftell(fp);
//   rewind(fp);

//   *data = (uint8_t*)malloc(fsize);
//   *size = fread(*data, 1, fsize, fp);

//   fclose(fp);

//   return 0;
// }

// template <typename Type>
// class Comparator {};

// template <>
// class Comparator<int> {
// public:
//   static const char* type_str() {
//     return "integer";
//   }
//   static int generate() {
//     return rand();
//   }
//   static bool compare(int a, int b, int index, int errors) {
//     if (a != b) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%d, actual=%d\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// template <>
// class Comparator<float> {
// public:
//   static const char* type_str() {
//     return "float";
//   }
//   static int generate() {
//     return static_cast<float>(rand()) / RAND_MAX;
//   }
//   static bool compare(float a, float b, int index, int errors) {
//     union fi_t { float f; int32_t i; };
//     fi_t fa, fb;
//     fa.f = a;
//     fb.f = b;
//     auto d = std::abs(fa.i - fb.i);
//     if (d > FLOAT_ULP) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%f, actual=%f\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// static void vecadd_cpu(TYPE *C, const TYPE* A, const TYPE *B, int N) {
//   for (int i = 0; i < N; ++i) {
//     C[i] = A[i] + B[i];
//   }
// }

// cl_device_id device_id = NULL;
// cl_context context = NULL;
// cl_command_queue commandQueue = NULL;
// cl_program program = NULL;
// cl_kernel kernel = NULL;
// cl_mem a_memobj = NULL;
// cl_mem b_memobj = NULL;
// cl_mem c_memobj = NULL;
// uint8_t *kernel_bin = NULL;

// static void cleanup() {
//   if (commandQueue) clReleaseCommandQueue(commandQueue);
//   if (kernel) clReleaseKernel(kernel);
//   if (program) clReleaseProgram(program);
//   if (a_memobj) clReleaseMemObject(a_memobj);
//   if (b_memobj) clReleaseMemObject(b_memobj);
//   if (c_memobj) clReleaseMemObject(c_memobj);
//   if (context) clReleaseContext(context);
//   if (device_id) clReleaseDevice(device_id);

//   if (kernel_bin) free(kernel_bin);
// }

// uint32_t size = 64;

// static void show_usage() {
//   printf("Usage: [-n size] [-h: help]\n");
// }

// static void parse_args(int argc, char **argv) {
//   int c;
//   while ((c = getopt(argc, argv, "n:h")) != -1) {
//     switch (c) {
//     case 'n':
//       size = atoi(optarg);
//       break;
//     case 'h':
//       show_usage();
//       exit(0);
//       break;
//     default:
//       show_usage();
//       exit(-1);
//     }
//   }

//   printf("Workload size=%d\n", size);
// }

// int main (int argc, char **argv) {
//   // parse command arguments
//   parse_args(argc, argv);

//   cl_platform_id platform_id;
//   size_t kernel_size;

//   // Getting platform and device information
//   CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
//   CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

//   printf("Create context\n");
//   context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));

//   printf("Allocate device buffers\n");
//   size_t nbytes = size * sizeof(TYPE);
//   a_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   b_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   c_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, nbytes, NULL, &_err));

//   printf("Create program from kernel source\n");
//   if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
//     return -1;
//   program = CL_CHECK2(clCreateProgramWithSource(
//     context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

//   // Build program
//   CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

//   // Create kernel
//   kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

//   // Set kernel arguments
//   CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&a_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&b_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&c_memobj));

//     // Allocate memories for input arrays and output arrays.
//   std::vector<TYPE> h_a(size);
//   std::vector<TYPE> h_b(size);
//   std::vector<TYPE> h_c(size);

//   // Generate input values
//   for (uint32_t i = 0; i < size; ++i) {
//     h_a[i] = Comparator<TYPE>::generate();
//     h_b[i] = Comparator<TYPE>::generate();
//   }

//   // Creating command queue
//   commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

// 	printf("Upload source buffers\n");
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, a_memobj, CL_TRUE, 0, nbytes, h_a.data(), 0, NULL, NULL));
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, b_memobj, CL_TRUE, 0, nbytes, h_b.data(), 0, NULL, NULL));

//   printf("Execute the kernel\n");
//   size_t global_work_size[1] = {size};
//   size_t local_work_size[1] = {1};
//   auto time_start = std::chrono::high_resolution_clock::now();
//   CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
//   CL_CHECK(clFinish(commandQueue));
//   auto time_end = std::chrono::high_resolution_clock::now();
//   double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
//   printf("Elapsed time: %lg ms\n", elapsed);

//   printf("Download destination buffer\n");
//   CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));

//   printf("Verify result\n");
//   std::vector<TYPE> h_ref(size);
//   vecadd_cpu(h_ref.data(), h_a.data(), h_b.data(), size);
//   int errors = 0;
//   for (uint32_t i = 0; i < size; ++i) {
//     if (!Comparator<TYPE>::compare(h_c[i], h_ref[i], i, errors)) {
//       ++errors;
//     }
//   }
//   if (0 == errors) {
//     printf("PASSED!\n");
//   } else {
//     printf("FAILED! - %d errors\n", errors);
//   }

// #ifdef MEM_DUMP_ENABLE
// {
//     /* Dump device output buffer to deterministic file so runner can locate it */
//     const char *dump_path = "logs/vecadd_output_dump.bin";
//     /* Ensure logs directory exists (CI runner expects logs/) */
//     system("mkdir -p logs");
//     FILE *f = fopen(dump_path, "wb");
//     if (f) {
//         size_t written = fwrite(h_c.data(), sizeof(TYPE), (size_t)size, f);
//         fclose(f);
//         printf("[DMEM_DUMP] wrote %zu elements to %s\n", written, dump_path);
//     } else {
//         printf("[DMEM_DUMP] failed to create %s\n", dump_path);
//     }
// }
// #endif

// // // <<< CORRECTED DUMP CODE IS HERE >>>
// //  {
// //     std::ofstream ofs("vecadd_output.bin", std::ios::binary);
// //     if (ofs) {
// //         printf("[Vortex-UVM-GP] Dumping result buffer to vecadd_output.bin\n");
// //         ofs.write(reinterpret_cast<const char*>(h_c.data()), h_c.size() * sizeof(TYPE));
// //         ofs.close();
// //     }
// //  }

//   // Clean up
//   cleanup();

//   return errors;
// }



// #include <stdio.h>
// #include <stdlib.h>
// #include <assert.h>
// #include <math.h>
// #include <CL/opencl.h>
// #include <unistd.h>
// #include <string.h>
// #include <chrono>
// #include <vector>
// #include "common.h"
// #include <fstream>

// #define KERNEL_NAME "vecadd"
// #define FLOAT_ULP 6

// #define CL_CHECK(_expr)                                                \
//    do {                                                                \
//      cl_int _err = _expr;                                              \
//      if (_err == CL_SUCCESS)                                           \
//        break;                                                          \
//      printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);   \
//      cleanup();                                                        \
//      exit(-1);                                                         \
//    } while (0)

// #define CL_CHECK2(_expr)                                               \
//    ({                                                                  \
//      cl_int _err = CL_INVALID_VALUE;                                   \
//      decltype(_expr) _ret = _expr;                                     \
//      if (_err != CL_SUCCESS) {                                         \
//        printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
//        cleanup();                                                      \
//        exit(-1);                                                       \
//      }                                                                 \
//      _ret;                                                             \
//    })

// static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
//   if (nullptr == filename || nullptr == data || 0 == size)
//     return -1;

//   FILE* fp = fopen(filename, "r");
//   if (NULL == fp) {
//     fprintf(stderr, "Failed to load kernel.");
//     return -1;
//   }
//   fseek(fp , 0 , SEEK_END);
//   long fsize = ftell(fp);
//   rewind(fp);

//   *data = (uint8_t*)malloc(fsize);
//   *size = fread(*data, 1, fsize, fp);

//   fclose(fp);
//   return 0;
// }

// template <typename Type>
// class Comparator {};

// template <>
// class Comparator<int> {
// public:
//   static const char* type_str() { return "integer"; }
//   static int generate() { return rand(); }
//   static bool compare(int a, int b, int index, int errors) {
//     if (a != b) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%d, actual=%d\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// template <>
// class Comparator<float> {
// public:
//   static const char* type_str() { return "float"; }
//   static int generate() { return static_cast<float>(rand()) / RAND_MAX; }
//   static bool compare(float a, float b, int index, int errors) {
//     union fi_t { float f; int32_t i; };
//     fi_t fa, fb;
//     fa.f = a; fb.f = b;
//     auto d = std::abs(fa.i - fb.i);
//     if (d > FLOAT_ULP) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%f, actual=%f\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// static void vecadd_cpu(TYPE *C, const TYPE* A, const TYPE *B, int N) {
//   for (int i = 0; i < N; ++i) {
//     C[i] = A[i] + B[i];
//   }
// }

// cl_device_id device_id = NULL;
// cl_context context = NULL;
// cl_command_queue commandQueue = NULL;
// cl_program program = NULL;
// cl_kernel kernel = NULL;
// cl_mem a_memobj = NULL;
// cl_mem b_memobj = NULL;
// cl_mem c_memobj = NULL;
// uint8_t *kernel_bin = NULL;

// static void cleanup() {
//   if (commandQueue) clReleaseCommandQueue(commandQueue);
//   if (kernel) clReleaseKernel(kernel);
//   if (program) clReleaseProgram(program);
//   if (a_memobj) clReleaseMemObject(a_memobj);
//   if (b_memobj) clReleaseMemObject(b_memobj);
//   if (c_memobj) clReleaseMemObject(c_memobj);
//   if (context) clReleaseContext(context);
//   if (device_id) clReleaseDevice(device_id);
//   if (kernel_bin) free(kernel_bin);
// }

// uint32_t size = 64;

// static void show_usage() {
//   printf("Usage: [-n size] [-h: help]\n");
// }

// static void parse_args(int argc, char **argv) {
//   int c;
//   while ((c = getopt(argc, argv, "n:h")) != -1) {
//     switch (c) {
//     case 'n': size = atoi(optarg); break;
//     case 'h': show_usage(); exit(0);
//     default:  show_usage(); exit(-1);
//     }
//   }
//   printf("Workload size=%d\n", size);
// }

// int main (int argc, char **argv) {
//   parse_args(argc, argv);

//   cl_platform_id platform_id;
//   size_t kernel_size;

//   CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
//   CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

//   printf("Create context\n");
//   context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));

//   printf("Allocate device buffers\n");
//   size_t nbytes = size * sizeof(TYPE);
//   a_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   b_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   c_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, nbytes, NULL, &_err));

//   printf("Create program from kernel source\n");
//   if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
//     return -1;
//   program = CL_CHECK2(clCreateProgramWithSource(context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

//   CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));
//   kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

//   CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&a_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&b_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&c_memobj));

//   std::vector<TYPE> h_a(size);
//   std::vector<TYPE> h_b(size);
//   std::vector<TYPE> h_c(size);

//   for (uint32_t i = 0; i < size; ++i) {
//     h_a[i] = Comparator<TYPE>::generate();
//     h_b[i] = Comparator<TYPE>::generate();
//   }

//   commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

//   printf("Upload source buffers\n");
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, a_memobj, CL_TRUE, 0, nbytes, h_a.data(), 0, NULL, NULL));
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, b_memobj, CL_TRUE, 0, nbytes, h_b.data(), 0, NULL, NULL));

//   printf("Execute the kernel\n");
//   size_t global_work_size[1] = {size};
//   size_t local_work_size[1] = {1};
//   auto time_start = std::chrono::high_resolution_clock::now();
//   CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
//   CL_CHECK(clFinish(commandQueue));
//   auto time_end = std::chrono::high_resolution_clock::now();
//   double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
//   printf("Elapsed time: %lg ms\n", elapsed);

//   printf("Download destination buffer\n");
//   CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));

//   printf("Verify result\n");
//   std::vector<TYPE> h_ref(size);
//   vecadd_cpu(h_ref.data(), h_a.data(), h_b.data(), size);
//   int errors = 0;
//   for (uint32_t i = 0; i < size; ++i) {
//     if (!Comparator<TYPE>::compare(h_c[i], h_ref[i], i, errors)) {
//       ++errors;
//     }
//   }
//   if (0 == errors) {
//     printf("PASSED!\n");
//   } else {
//     printf("FAILED! - %d errors\n", errors);
//   }





// // Ensure kernel execution is finished and results are copied back to host
// CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));
// CL_CHECK(clFinish(commandQueue));

// // Print a small sample of input/output vectors for debugging
// for (int i = 0; i < std::min<int>(10, size); ++i) {
//   if constexpr (std::is_same<TYPE,int>::value) {
//     printf("A[%d]=%d B[%d]=%d C[%d]=%d\n", i, (int)h_a[i], i, (int)h_b[i], i, (int)h_c[i]);
//   } else {
//     printf("A[%d]=%f B[%d]=%f C[%d]=%f\n", i, (double)h_a[i], i, (double)h_b[i], i, (double)h_c[i]);
//   }
// }

// // Dump the result buffer to a binary file for later comparison
// const char* dump_env = std::getenv("VORTEX_DUMP_NAME");
// std::string dump_name = dump_env ? dump_env : "vecadd_output.bin";

// // Create logs directory if needed
// if (dump_name.rfind("logs/", 0) == 0) {
//   system("mkdir -p logs");
// }

// std::ofstream ofs(dump_name, std::ios::binary);
// if (!ofs) {
//   fprintf(stderr, "[Dump] Failed to open %s\n", dump_name.c_str());
// } else {
//   ofs.write(reinterpret_cast<const char*>(h_c.data()), h_c.size() * sizeof(TYPE));
//   ofs.close();
//   printf("[Dump] Wrote %zu bytes to %s\n", h_c.size() * sizeof(TYPE), dump_name.c_str());
// }



//     // --- Dump results to file for SIMX/RTLSIM comparison ---
//   {
//     const char* dump_env = std::getenv("VORTEX_DUMP_NAME");
//     std::string dump_name = dump_env ? dump_env : "vecadd_output.bin";

//     if (dump_name.rfind("logs/", 0) == 0) {
//       system("mkdir -p logs");
//     }

//     std::ofstream ofs(dump_name, std::ios::binary);
//     if (ofs) {
//       ofs.write(reinterpret_cast<const char*>(h_c.data()), h_c.size() * sizeof(TYPE));
//       ofs.close();
//       std::printf("[Vortex-UVM-GP] Dumped %zu elements to %s\n", h_c.size(), dump_name.c_str());
//     } else {
//       std::fprintf(stderr, "[Vortex-UVM-GP] Failed to write dump file: %s\n", dump_name.c_str());
//     }
//   }

//   // Clean up
//   cleanup();

//   return errors;
// }


// #include <stdio.h>
// #include <stdlib.h>
// #include <assert.h>
// #include <math.h>
// #include <CL/opencl.h>
// #include <unistd.h>
// #include <string.h>
// #include <chrono>
// #include <vector>
// #include <fstream>
// #include <algorithm>
// #include <type_traits>
// #include "common.h"

// #define KERNEL_NAME "vecadd"
// #define FLOAT_ULP 6

// #define CL_CHECK(_expr)                                                \
//    do {                                                                \
//      cl_int _err = _expr;                                              \
//      if (_err == CL_SUCCESS)                                           \
//        break;                                                          \
//      printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);   \
//      cleanup();                                                        \
//      exit(-1);                                                         \
//    } while (0)

// #define CL_CHECK2(_expr)                                               \
//    ({                                                                  \
//      cl_int _err = CL_INVALID_VALUE;                                   \
//      decltype(_expr) _ret = _expr;                                     \
//      if (_err != CL_SUCCESS) {                                         \
//        printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
//        cleanup();                                                      \
//        exit(-1);                                                       \
//      }                                                                 \
//      _ret;                                                             \
//    })

// static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
//   if (nullptr == filename || nullptr == data || 0 == size)
//     return -1;

//   FILE* fp = fopen(filename, "r");
//   if (NULL == fp) {
//     fprintf(stderr, "Failed to load kernel.");
//     return -1;
//   }
//   fseek(fp , 0 , SEEK_END);
//   long fsize = ftell(fp);
//   rewind(fp);

//   *data = (uint8_t*)malloc(fsize);
//   *size = fread(*data, 1, fsize, fp);

//   fclose(fp);
//   return 0;
// }

// template <typename Type>
// class Comparator {};

// template <>
// class Comparator<int> {
// public:
//   static const char* type_str() { return "integer"; }
//   static int generate() { return rand(); }
//   static bool compare(int a, int b, int index, int errors) {
//     if (a != b) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%d, actual=%d\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// template <>
// class Comparator<float> {
// public:
//   static const char* type_str() { return "float"; }
//   static int generate() { return static_cast<float>(rand()) / RAND_MAX; }
//   static bool compare(float a, float b, int index, int errors) {
//     union fi_t { float f; int32_t i; };
//     fi_t fa, fb;
//     fa.f = a; fb.f = b;
//     auto d = std::abs(fa.i - fb.i);
//     if (d > FLOAT_ULP) {
//       if (errors < 100) {
//         printf("*** error: [%d] expected=%f, actual=%f\n", index, a, b);
//       }
//       return false;
//     }
//     return true;
//   }
// };

// static void vecadd_cpu(TYPE *C, const TYPE* A, const TYPE *B, int N) {
//   for (int i = 0; i < N; ++i) {
//     C[i] = A[i] + B[i];
//   }
// }

// cl_device_id device_id = NULL;
// cl_context context = NULL;
// cl_command_queue commandQueue = NULL;
// cl_program program = NULL;
// cl_kernel kernel = NULL;
// cl_mem a_memobj = NULL;
// cl_mem b_memobj = NULL;
// cl_mem c_memobj = NULL;
// uint8_t *kernel_bin = NULL;

// static void cleanup() {
//   if (commandQueue) clReleaseCommandQueue(commandQueue);
//   if (kernel) clReleaseKernel(kernel);
//   if (program) clReleaseProgram(program);
//   if (a_memobj) clReleaseMemObject(a_memobj);
//   if (b_memobj) clReleaseMemObject(b_memobj);
//   if (c_memobj) clReleaseMemObject(c_memobj);
//   if (context) clReleaseContext(context);
//   if (device_id) clReleaseDevice(device_id);
//   if (kernel_bin) free(kernel_bin);
// }

// uint32_t size = 64;

// static void show_usage() {
//   printf("Usage: [-n size] [-h: help]\n");
// }

// static void parse_args(int argc, char **argv) {
//   int c;
//   while ((c = getopt(argc, argv, "n:h")) != -1) {
//     switch (c) {
//     case 'n': size = atoi(optarg); break;
//     case 'h': show_usage(); exit(0);
//     default:  show_usage(); exit(-1);
//     }
//   }
//   printf("Workload size=%d\n", size);
// }

// int main (int argc, char **argv) {
//   parse_args(argc, argv);

//   cl_platform_id platform_id;
//   size_t kernel_size;

//   CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
//   CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

//   printf("Create context\n");
//   context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));

//   printf("Allocate device buffers\n");
//   size_t nbytes = size * sizeof(TYPE);
//   a_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   b_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
//   c_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, nbytes, NULL, &_err));

//   printf("Create program from kernel source\n");
//   if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
//     return -1;
//   program = CL_CHECK2(clCreateProgramWithSource(context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

//   CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));
//   kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

//   CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&a_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&b_memobj));
//   CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&c_memobj));

//   std::vector<TYPE> h_a(size);
//   std::vector<TYPE> h_b(size);
//   std::vector<TYPE> h_c(size);

//   for (uint32_t i = 0; i < size; ++i) {
//     h_a[i] = Comparator<TYPE>::generate();
//     h_b[i] = Comparator<TYPE>::generate();
//   }

//   commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

//   printf("Upload source buffers\n");
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, a_memobj, CL_TRUE, 0, nbytes, h_a.data(), 0, NULL, NULL));
//   CL_CHECK(clEnqueueWriteBuffer(commandQueue, b_memobj, CL_TRUE, 0, nbytes, h_b.data(), 0, NULL, NULL));

//   printf("Execute the kernel\n");
//   size_t global_work_size[1] = {size};
//   size_t local_work_size[1] = {1};
//   auto time_start = std::chrono::high_resolution_clock::now();
//   CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
//   CL_CHECK(clFinish(commandQueue));
//   auto time_end = std::chrono::high_resolution_clock::now();
//   double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
//   printf("Elapsed time: %lg ms\n", elapsed);

//   printf("Download destination buffer\n");
//   CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));

//   printf("Verify result\n");
//   std::vector<TYPE> h_ref(size);
//   vecadd_cpu(h_ref.data(), h_a.data(), h_b.data(), size);
//   int errors = 0;
//   for (uint32_t i = 0; i < size; ++i) {
//     if (!Comparator<TYPE>::compare(h_c[i], h_ref[i], i, errors)) {
//       ++errors;
//     }
//   }
//   if (0 == errors) {
//     printf("PASSED!\n");
//   } else {
//     printf("FAILED! - %d errors\n", errors);
//   }

//    // Print a small sample of input/output vectors for debugging
//   for (int i = 0; i < std::min<int>(10, size); ++i) {
//     if constexpr (std::is_same<TYPE,int>::value) {
//       printf("A[%d]=%d B[%d]=%d C[%d]=%d\n", i, (int)h_a[i], i, (int)h_b[i], i, (int)h_c[i]);
//     } else {
//       printf("A[%d]=%f B[%d]=%f C[%d]=%f\n", i, (double)h_a[i], i, (double)h_b[i], i, (double)h_c[i]);
//     }
//   }


// // Dump the result buffer to a binary file for later comparison
// const char* dump_env = std::getenv("VORTEX_DUMP_NAME");
// std::string dump_name = dump_env ? dump_env : "vecadd_output.bin";

// // Create logs directory if needed
// if (dump_name.rfind("logs/", 0) == 0) {
//   system("mkdir -p logs");
// }

// std::ofstream ofs(dump_name, std::ios::binary);
// if (!ofs) {
//   fprintf(stderr, "[Dump] Failed to open %s\n", dump_name.c_str());
// } else {
//   ofs.write(reinterpret_cast<const char*>(h_c.data()), h_c.size() * sizeof(TYPE));
//   ofs.close();
//   printf("[Dump] Wrote %zu bytes to %s\n", h_c.size() * sizeof(TYPE), dump_name.c_str());
// }

//   // Clean up
//   //cleanup();

//   return errors;
// }


// Modified vecadd main.cpp - with reliable DMEM dump
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

// main.cpp (full, explicit, compatible with your original style)
// - uses common.h to define TYPE (default float)
// - reads kernel.cl from cwd
// - writes multiple dumps and prints debug info
// - declares _err used by CL_CHECK2 macro

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include <fstream>
#include <algorithm>
#include <type_traits>
#include "common.h"

#define KERNEL_NAME "vecadd"
#define FLOAT_ULP 6

// declare an _err variable used by CL_CHECK2
static cl_int _err = CL_SUCCESS;

#define CL_CHECK(_expr)                                                \
   do {                                                                \
     cl_int _err_loc = (_expr);                                        \
     if (_err_loc == CL_SUCCESS)                                       \
       break;                                                          \
     printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err_loc); \
     cleanup();                                                        \
     exit(-1);                                                         \
   } while (0)

#define CL_CHECK2(_expr)                                               \
   ({                                                                  \
     _err = CL_INVALID_VALUE;                                          \
     decltype(_expr) _ret = _expr;                                     \
     if (_err != CL_SUCCESS) {                                         \
       printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
       cleanup();                                                      \
       exit(-1);                                                       \
     }                                                                 \
     _ret;                                                             \
   })

static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
    return -1;

  FILE* fp = fopen(filename, "r");
  if (NULL == fp) {
    fprintf(stderr, "Failed to load kernel: %s\n", filename);
    return -1;
  }
  fseek(fp , 0 , SEEK_END);
  long fsize = ftell(fp);
  rewind(fp);

  if (fsize <= 0) {
    fclose(fp);
    fprintf(stderr, "Kernel file empty or error: %s\n", filename);
    return -1;
  }

  *data = (uint8_t*)malloc(fsize + 1);
  *size = fread(*data, 1, fsize, fp);
  (*data)[*size] = '\0'; // NUL terminate for safety with clCreateProgramWithSource
  fclose(fp);
  return 0;
}

template <typename Type>
class Comparator {};

template <>
class Comparator<int> {
public:
  static const char* type_str() { return "integer"; }
  static int generate() { return rand(); }
  static bool compare(int a, int b, int index, int errors) {
    if (a != b) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%d, actual=%d\n", index, a, b);
      }
      return false;
    }
    return true;
  }
};

template <>
class Comparator<float> {
public:
  static const char* type_str() { return "float"; }
  static float generate() { return static_cast<float>(rand()) / RAND_MAX; }
  static bool compare(float a, float b, int index, int errors) {
    union fi_t { float f; int32_t i; };
    fi_t fa, fb;
    fa.f = a; fb.f = b;
    auto d = std::abs((int64_t)fa.i - (int64_t)fb.i);
    if (d > FLOAT_ULP) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%f, actual=%f\n", index, a, b);
      }
      return false;
    }
    return true;
  }
};

static void vecadd_cpu(TYPE *C, const TYPE* A, const TYPE *B, int N) {
  for (int i = 0; i < N; ++i) {
    C[i] = A[i] + B[i];
  }
}

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem a_memobj = NULL;
cl_mem b_memobj = NULL;
cl_mem c_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) { clFinish(commandQueue); clReleaseCommandQueue(commandQueue); commandQueue = NULL; }
  if (kernel) { clReleaseKernel(kernel); kernel = NULL; }
  if (program) { clReleaseProgram(program); program = NULL; }
  if (a_memobj) { clReleaseMemObject(a_memobj); a_memobj = NULL; }
  if (b_memobj) { clReleaseMemObject(b_memobj); b_memobj = NULL; }
  if (c_memobj) { clReleaseMemObject(c_memobj); c_memobj = NULL; }
  if (context) { clReleaseContext(context); context = NULL; }
  if (device_id) { /* do not release device in many CL installs, but include guard */ device_id = NULL; }
  if (kernel_bin) { free(kernel_bin); kernel_bin = NULL; }
}

uint32_t size = 64;

static void show_usage() {
  printf("Usage: [-n size] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:h")) != -1) {
    switch (c) {
    case 'n': size = atoi(optarg); break;
    case 'h': show_usage(); exit(0);
    default:  show_usage(); exit(-1);
    }
  }
  printf("Workload size=%d\n", size);
}

int main (int argc, char **argv) {
  parse_args(argc, argv);

  cl_platform_id platform_id;
  size_t kernel_size;

  // pick platform + device
  CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
  CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

  printf("Create context\n");
  context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));

  printf("Allocate device buffers\n");
  size_t nbytes = (size_t)size * sizeof(TYPE);
  a_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
  b_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
  c_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, nbytes, NULL, &_err));

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size)) {
    fprintf(stderr, "Falling back to inline kernel source\n");
    // optional fallback: inline kernel (if file not found)
    const char *inline_src =
      "__kernel void vecadd(__global const float* A, __global const float* B, __global float* C) { int i = get_global_id(0); C[i] = A[i] + B[i]; }";
    kernel_bin = (uint8_t*)strdup(inline_src);
    kernel_size = strlen(inline_src);
  }
  program = CL_CHECK2(clCreateProgramWithSource(context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

  // build program with TYPE macro substituted if needed
  // In your original flow kernel.cl probably uses TYPE; if so, pass -DTYPE=float to clBuildProgram.
  CL_CHECK(clBuildProgram(program, 1, &device_id, "-DTYPE=float", NULL, NULL));
  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&a_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&b_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&c_memobj));

  std::vector<TYPE> h_a(size);
  std::vector<TYPE> h_b(size);
  std::vector<TYPE> h_c(size);

  // initial data
  srand(123456);
  for (uint32_t i = 0; i < size; ++i) {
    h_a[i] = Comparator<TYPE>::generate();
    h_b[i] = Comparator<TYPE>::generate();
  }

  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, a_memobj, CL_TRUE, 0, nbytes, h_a.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, b_memobj, CL_TRUE, 0, nbytes, h_b.data(), 0, NULL, NULL));

  printf("Execute the kernel\n");
  size_t global_work_size[1] = { (size_t)size };
  size_t local_work_size[1] = { 1 };
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));

  printf("Verify result\n");
  std::vector<TYPE> h_ref(size);
  vecadd_cpu(h_ref.data(), h_a.data(), h_b.data(), size);
  int errors = 0;
  for (uint32_t i = 0; i < size; ++i) {
    if (!Comparator<TYPE>::compare(h_c[i], h_ref[i], i, errors)) {
      ++errors;
    }
  }
  if (0 == errors) {
    printf("PASSED!\n");
  } else {
    printf("FAILED! - %d errors\n", errors);
  }

  // Print a small sample of input/output vectors for debugging
  for (int i = 0; i < std::min<int>(10, size); ++i) {
    if constexpr (std::is_same<TYPE,int>::value) {
      printf("A[%d]=%d B[%d]=%d C[%d]=%d\n", i, (int)h_a[i], i, (int)h_b[i], i, (int)h_c[i]);
    } else {
      printf("A[%d]=%f B[%d]=%f C[%d]=%f\n", i, (double)h_a[i], i, (double)h_b[i], i, (double)h_c[i]);
    }
  }

#ifdef MEM_DUMP_ENABLE
// ========== RELIABLE OUTPUT DUMP (writes 3 places + prints markers) ==========
{
    // 1) Ensure logs directory exists (runner expects logs/)
    system("mkdir -p logs");

    // 2) Determine CWD absolute path for robust placement
    char cwd[1024] = {0};
    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        strncpy(cwd, ".", sizeof(cwd)-1);
    }

    // 3) Compose file paths
    const char *name1 = "vecadd_output.bin";                // simple local file
    const char *name2 = "logs/vecadd_output_dump.bin";      // runner-friendly path
    std::string abs_path = std::string(cwd) + "/" + name1;  // absolute path copy

    // 4) Write to local file
    FILE *f = fopen(name1, "wb");
    if (f) {
        size_t w = fwrite(h_c.data(), sizeof(TYPE), h_c.size(), f);
        fclose(f);
        printf("[DMEM_DUMP] WROTE %zu elems -> %s\n", w, name1);
    } else {
        printf("[DMEM_DUMP] FAILED_WRITE -> %s\n", name1);
    }

    // 5) Write to logs/vecadd_output_dump.bin (this is the path CI scripts often look for)
    FILE *f2 = fopen(name2, "wb");
    if (f2) {
        size_t w2 = fwrite(h_c.data(), sizeof(TYPE), h_c.size(), f2);
        fclose(f2);
        printf("[DMEM_DUMP] WROTE %zu elems -> %s\n", w2, name2);
    } else {
        printf("[DMEM_DUMP] FAILED_WRITE -> %s\n", name2);
    }

    // 6) Also emit absolute path (some wrappers run from build root and will mv/grep)
    FILE *f3 = fopen(abs_path.c_str(), "wb");
    if (f3) {
        size_t w3 = fwrite(h_c.data(), sizeof(TYPE), h_c.size(), f3);
        fclose(f3);
        printf("[DMEM_DUMP] WROTE %zu elems -> %s\n", w3, abs_path.c_str());
    } else {
        printf("[DMEM_DUMP] FAILED_WRITE -> %s\n", abs_path.c_str());
    }

    // 7) Flush file system buffers to increase chance file is visible to other processes immediately
    fflush(NULL);
    sync();
    printf("[DMEM_DUMP] DONE (cwd=%s)\n", cwd);
}
#endif
// ========== END RELIABLE OUTPUT DUMP ==========

// === Dump output buffer (h_c) to binary file depending on driver env var ===
{
    const char* driver = getenv("VORTEX_DRIVER");
    std::string driver_name = driver ? driver : "unknown";

    printf("[INFO] Detected driver: %s\n", driver_name.c_str());

    std::string filename;
    if (driver_name == "rtlsim")
        filename = "vecadd_output_rtlsim.bin";
    else if (driver_name == "simx")
        filename = "vecadd_output_simx.bin";
    else
        filename = "vecadd_output_unknown.bin";

    FILE* fout = fopen(filename.c_str(), "wb");
    if (fout) {
        size_t w = fwrite(h_c.data(), sizeof(TYPE), h_c.size(), fout);
        fclose(fout);
        printf("[INFO] Dumped %zu elements -> %s\n", w, filename.c_str());
    } else {
        perror("[ERROR] Failed to open output file");
    }
}

  // Clean up (release OpenCL objects and local buffers)
 // cleanup();

  return errors;
}
