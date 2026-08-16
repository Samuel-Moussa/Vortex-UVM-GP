// storm_big — force ICACHE and DCACHE responses to arrive TOGETHER.
//
// TARGET: the last large cluster of missing condition terms that unit_storm cannot
// reach — `g_mem_bus_if[0]/g_i0/mem_arb/g_rsp_select/rsp_switch/g_out_buf[0..1]/out_buf`
// (2 terms at 1CL, more at 2CL) plus `dcache/.../bank/core_rsp_queue`.
//
// WHY unit_storm CANNOT DO IT: mem_arb multiplexes the icache and dcache memory
// streams. Its response switch only back-pressures when BOTH streams have a response
// ready at once and one must wait. unit_storm's loop is small and stays resident in
// the 16 KB icache (VX_config.vh:557), so it generates essentially zero instruction
// fetch traffic — there is never a second stream to contend with.
//
// MECHANISM: ~19 KB of hot .text (96 noinline functions, each ~200 B) called in a
// runtime-indexed order that defeats prefetch, INTERLEAVED with the same independent
// local-memory + global-load traffic unit_storm uses. Instruction fetch misses and
// data misses are then outstanding simultaneously.
//
// ⚠ DATA TABLE IS 4 KB AND MUST STAY THAT WAY — MEASURED TWICE.
// The obvious "improvement" is to enlarge it so the DATA stream also misses to memory
// and contends with the instruction stream at the socket-level mem_arb. It was tried:
//   storm_big  4 KB table -> +4 condition terms at 2CL (dcache core_arb rsp_switch)
//   storm_big 64 KB table -> +0 terms. Strictly worse.
// This is the SECOND independent confirmation of the unit_storm v3 result (which lost
// 2 terms the same way). Past a point, memory pressure does not add congestion — it
// REMOVES it, because every warp ends up stalled on memory and nothing is ever issued
// densely enough for two streams to collide in the same cycle.
// ⇒ Contention is created by ISSUE DENSITY, not by miss volume. Do not enlarge this.
//
// DETERMINISM / SAFETY: every thread writes ONLY out_buf[i]; vx_spawn distributes
// CONTIGUOUSLY (vx_spawn.c:299) so no barrier is needed and no core touches another
// core's slice; local memory is per-core; the global table is CONST (.rodata), so
// multi-core is race-free with no initialisation (OBS-026); all arithmetic is integer
// and exact.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define ITERS      48
#define LM_SLOTS   8
#define TAB_WORDS  1024
#define MAX_TOTAL  256
#define NFUNCS     96

static const int g_tab[TAB_WORDS] = {
#define R1(i)  ((i) * 2654435761u) >> 16
#define R8(i)  R1(i), R1(i+1), R1(i+2), R1(i+3), R1(i+4), R1(i+5), R1(i+6), R1(i+7)
#define R64(i) R8(i), R8(i+8), R8(i+16), R8(i+24), R8(i+32), R8(i+40), R8(i+48), R8(i+56)
#define R512(i) R64(i), R64(i+64), R64(i+128), R64(i+192), R64(i+256), R64(i+320), R64(i+384), R64(i+448)
	R512(0), R512(512)
};

typedef struct { int *out; } sb_args_t;
volatile int out_buf[MAX_TOTAL];
static inline int tab_ref(int i) { return (int)(((unsigned)i * 2654435761u) >> 16); }

__attribute__((noinline)) static int sb_0(int x){
  x = x*3 + 1; x ^= (x << 1) + 3; x = (x >> 1) + 5; x += x*5;
  x = x*3 + 7; x ^= (x << 1) + 9; x = (x >> 1) + 11; x += x*1;
  x = x*3 + 13; x ^= (x << 1) + 15; x = (x >> 1) + 17; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_1(int x){
  x = x*3 + 8; x ^= (x << 1) + 14; x = (x >> 1) + 18; x += x*5;
  x = x*3 + 24; x ^= (x << 1) + 28; x = (x >> 1) + 34; x += x*1;
  x = x*3 + 42; x ^= (x << 1) + 46; x = (x >> 1) + 54; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_2(int x){
  x = x*3 + 15; x ^= (x << 1) + 25; x = (x >> 1) + 31; x += x*5;
  x = x*3 + 41; x ^= (x << 1) + 47; x = (x >> 1) + 57; x += x*1;
  x = x*3 + 71; x ^= (x << 1) + 77; x = (x >> 1) + 91; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_3(int x){
  x = x*3 + 22; x ^= (x << 1) + 36; x = (x >> 1) + 44; x += x*5;
  x = x*3 + 58; x ^= (x << 1) + 66; x = (x >> 1) + 80; x += x*1;
  x = x*3 + 100; x ^= (x << 1) + 108; x = (x >> 1) + 128; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_4(int x){
  x = x*3 + 29; x ^= (x << 1) + 47; x = (x >> 1) + 57; x += x*5;
  x = x*3 + 75; x ^= (x << 1) + 85; x = (x >> 1) + 103; x += x*1;
  x = x*3 + 129; x ^= (x << 1) + 139; x = (x >> 1) + 165; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_5(int x){
  x = x*3 + 36; x ^= (x << 1) + 58; x = (x >> 1) + 70; x += x*5;
  x = x*3 + 92; x ^= (x << 1) + 104; x = (x >> 1) + 126; x += x*1;
  x = x*3 + 158; x ^= (x << 1) + 170; x = (x >> 1) + 202; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_6(int x){
  x = x*3 + 43; x ^= (x << 1) + 69; x = (x >> 1) + 83; x += x*5;
  x = x*3 + 109; x ^= (x << 1) + 123; x = (x >> 1) + 149; x += x*1;
  x = x*3 + 187; x ^= (x << 1) + 201; x = (x >> 1) + 239; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_7(int x){
  x = x*3 + 50; x ^= (x << 1) + 80; x = (x >> 1) + 96; x += x*5;
  x = x*3 + 126; x ^= (x << 1) + 142; x = (x >> 1) + 172; x += x*1;
  x = x*3 + 216; x ^= (x << 1) + 232; x = (x >> 1) + 276; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_8(int x){
  x = x*3 + 57; x ^= (x << 1) + 91; x = (x >> 1) + 109; x += x*5;
  x = x*3 + 143; x ^= (x << 1) + 161; x = (x >> 1) + 195; x += x*1;
  x = x*3 + 245; x ^= (x << 1) + 263; x = (x >> 1) + 313; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_9(int x){
  x = x*3 + 64; x ^= (x << 1) + 102; x = (x >> 1) + 122; x += x*5;
  x = x*3 + 160; x ^= (x << 1) + 180; x = (x >> 1) + 218; x += x*1;
  x = x*3 + 274; x ^= (x << 1) + 294; x = (x >> 1) + 350; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_10(int x){
  x = x*3 + 71; x ^= (x << 1) + 113; x = (x >> 1) + 135; x += x*5;
  x = x*3 + 177; x ^= (x << 1) + 199; x = (x >> 1) + 241; x += x*1;
  x = x*3 + 303; x ^= (x << 1) + 325; x = (x >> 1) + 387; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_11(int x){
  x = x*3 + 78; x ^= (x << 1) + 124; x = (x >> 1) + 148; x += x*5;
  x = x*3 + 194; x ^= (x << 1) + 218; x = (x >> 1) + 264; x += x*1;
  x = x*3 + 332; x ^= (x << 1) + 356; x = (x >> 1) + 424; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_12(int x){
  x = x*3 + 85; x ^= (x << 1) + 135; x = (x >> 1) + 161; x += x*5;
  x = x*3 + 211; x ^= (x << 1) + 237; x = (x >> 1) + 287; x += x*1;
  x = x*3 + 361; x ^= (x << 1) + 387; x = (x >> 1) + 461; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_13(int x){
  x = x*3 + 92; x ^= (x << 1) + 146; x = (x >> 1) + 174; x += x*5;
  x = x*3 + 228; x ^= (x << 1) + 256; x = (x >> 1) + 310; x += x*1;
  x = x*3 + 390; x ^= (x << 1) + 418; x = (x >> 1) + 498; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_14(int x){
  x = x*3 + 99; x ^= (x << 1) + 157; x = (x >> 1) + 187; x += x*5;
  x = x*3 + 245; x ^= (x << 1) + 275; x = (x >> 1) + 333; x += x*1;
  x = x*3 + 419; x ^= (x << 1) + 449; x = (x >> 1) + 535; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_15(int x){
  x = x*3 + 106; x ^= (x << 1) + 168; x = (x >> 1) + 200; x += x*5;
  x = x*3 + 262; x ^= (x << 1) + 294; x = (x >> 1) + 356; x += x*1;
  x = x*3 + 448; x ^= (x << 1) + 480; x = (x >> 1) + 572; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_16(int x){
  x = x*3 + 113; x ^= (x << 1) + 179; x = (x >> 1) + 213; x += x*5;
  x = x*3 + 279; x ^= (x << 1) + 313; x = (x >> 1) + 379; x += x*1;
  x = x*3 + 477; x ^= (x << 1) + 511; x = (x >> 1) + 609; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_17(int x){
  x = x*3 + 120; x ^= (x << 1) + 190; x = (x >> 1) + 226; x += x*5;
  x = x*3 + 296; x ^= (x << 1) + 332; x = (x >> 1) + 402; x += x*1;
  x = x*3 + 506; x ^= (x << 1) + 542; x = (x >> 1) + 646; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_18(int x){
  x = x*3 + 127; x ^= (x << 1) + 201; x = (x >> 1) + 239; x += x*5;
  x = x*3 + 313; x ^= (x << 1) + 351; x = (x >> 1) + 425; x += x*1;
  x = x*3 + 535; x ^= (x << 1) + 573; x = (x >> 1) + 683; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_19(int x){
  x = x*3 + 134; x ^= (x << 1) + 212; x = (x >> 1) + 252; x += x*5;
  x = x*3 + 330; x ^= (x << 1) + 370; x = (x >> 1) + 448; x += x*1;
  x = x*3 + 564; x ^= (x << 1) + 604; x = (x >> 1) + 720; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_20(int x){
  x = x*3 + 141; x ^= (x << 1) + 223; x = (x >> 1) + 265; x += x*5;
  x = x*3 + 347; x ^= (x << 1) + 389; x = (x >> 1) + 471; x += x*1;
  x = x*3 + 593; x ^= (x << 1) + 635; x = (x >> 1) + 757; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_21(int x){
  x = x*3 + 148; x ^= (x << 1) + 234; x = (x >> 1) + 278; x += x*5;
  x = x*3 + 364; x ^= (x << 1) + 408; x = (x >> 1) + 494; x += x*1;
  x = x*3 + 622; x ^= (x << 1) + 666; x = (x >> 1) + 794; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_22(int x){
  x = x*3 + 155; x ^= (x << 1) + 245; x = (x >> 1) + 291; x += x*5;
  x = x*3 + 381; x ^= (x << 1) + 427; x = (x >> 1) + 517; x += x*1;
  x = x*3 + 651; x ^= (x << 1) + 697; x = (x >> 1) + 831; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_23(int x){
  x = x*3 + 162; x ^= (x << 1) + 256; x = (x >> 1) + 304; x += x*5;
  x = x*3 + 398; x ^= (x << 1) + 446; x = (x >> 1) + 540; x += x*1;
  x = x*3 + 680; x ^= (x << 1) + 728; x = (x >> 1) + 868; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_24(int x){
  x = x*3 + 169; x ^= (x << 1) + 267; x = (x >> 1) + 317; x += x*5;
  x = x*3 + 415; x ^= (x << 1) + 465; x = (x >> 1) + 563; x += x*1;
  x = x*3 + 709; x ^= (x << 1) + 759; x = (x >> 1) + 905; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_25(int x){
  x = x*3 + 176; x ^= (x << 1) + 278; x = (x >> 1) + 330; x += x*5;
  x = x*3 + 432; x ^= (x << 1) + 484; x = (x >> 1) + 586; x += x*1;
  x = x*3 + 738; x ^= (x << 1) + 790; x = (x >> 1) + 942; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_26(int x){
  x = x*3 + 183; x ^= (x << 1) + 289; x = (x >> 1) + 343; x += x*5;
  x = x*3 + 449; x ^= (x << 1) + 503; x = (x >> 1) + 609; x += x*1;
  x = x*3 + 767; x ^= (x << 1) + 821; x = (x >> 1) + 979; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_27(int x){
  x = x*3 + 190; x ^= (x << 1) + 300; x = (x >> 1) + 356; x += x*5;
  x = x*3 + 466; x ^= (x << 1) + 522; x = (x >> 1) + 632; x += x*1;
  x = x*3 + 796; x ^= (x << 1) + 852; x = (x >> 1) + 1016; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_28(int x){
  x = x*3 + 197; x ^= (x << 1) + 311; x = (x >> 1) + 369; x += x*5;
  x = x*3 + 483; x ^= (x << 1) + 541; x = (x >> 1) + 655; x += x*1;
  x = x*3 + 825; x ^= (x << 1) + 883; x = (x >> 1) + 1053; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_29(int x){
  x = x*3 + 204; x ^= (x << 1) + 322; x = (x >> 1) + 382; x += x*5;
  x = x*3 + 500; x ^= (x << 1) + 560; x = (x >> 1) + 678; x += x*1;
  x = x*3 + 854; x ^= (x << 1) + 914; x = (x >> 1) + 1090; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_30(int x){
  x = x*3 + 211; x ^= (x << 1) + 333; x = (x >> 1) + 395; x += x*5;
  x = x*3 + 517; x ^= (x << 1) + 579; x = (x >> 1) + 701; x += x*1;
  x = x*3 + 883; x ^= (x << 1) + 945; x = (x >> 1) + 1127; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_31(int x){
  x = x*3 + 218; x ^= (x << 1) + 344; x = (x >> 1) + 408; x += x*5;
  x = x*3 + 534; x ^= (x << 1) + 598; x = (x >> 1) + 724; x += x*1;
  x = x*3 + 912; x ^= (x << 1) + 976; x = (x >> 1) + 1164; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_32(int x){
  x = x*3 + 225; x ^= (x << 1) + 355; x = (x >> 1) + 421; x += x*5;
  x = x*3 + 551; x ^= (x << 1) + 617; x = (x >> 1) + 747; x += x*1;
  x = x*3 + 941; x ^= (x << 1) + 1007; x = (x >> 1) + 1201; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_33(int x){
  x = x*3 + 232; x ^= (x << 1) + 366; x = (x >> 1) + 434; x += x*5;
  x = x*3 + 568; x ^= (x << 1) + 636; x = (x >> 1) + 770; x += x*1;
  x = x*3 + 970; x ^= (x << 1) + 1038; x = (x >> 1) + 1238; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_34(int x){
  x = x*3 + 239; x ^= (x << 1) + 377; x = (x >> 1) + 447; x += x*5;
  x = x*3 + 585; x ^= (x << 1) + 655; x = (x >> 1) + 793; x += x*1;
  x = x*3 + 999; x ^= (x << 1) + 1069; x = (x >> 1) + 1275; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_35(int x){
  x = x*3 + 246; x ^= (x << 1) + 388; x = (x >> 1) + 460; x += x*5;
  x = x*3 + 602; x ^= (x << 1) + 674; x = (x >> 1) + 816; x += x*1;
  x = x*3 + 1028; x ^= (x << 1) + 1100; x = (x >> 1) + 1312; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_36(int x){
  x = x*3 + 253; x ^= (x << 1) + 399; x = (x >> 1) + 473; x += x*5;
  x = x*3 + 619; x ^= (x << 1) + 693; x = (x >> 1) + 839; x += x*1;
  x = x*3 + 1057; x ^= (x << 1) + 1131; x = (x >> 1) + 1349; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_37(int x){
  x = x*3 + 260; x ^= (x << 1) + 410; x = (x >> 1) + 486; x += x*5;
  x = x*3 + 636; x ^= (x << 1) + 712; x = (x >> 1) + 862; x += x*1;
  x = x*3 + 1086; x ^= (x << 1) + 1162; x = (x >> 1) + 1386; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_38(int x){
  x = x*3 + 267; x ^= (x << 1) + 421; x = (x >> 1) + 499; x += x*5;
  x = x*3 + 653; x ^= (x << 1) + 731; x = (x >> 1) + 885; x += x*1;
  x = x*3 + 1115; x ^= (x << 1) + 1193; x = (x >> 1) + 1423; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_39(int x){
  x = x*3 + 274; x ^= (x << 1) + 432; x = (x >> 1) + 512; x += x*5;
  x = x*3 + 670; x ^= (x << 1) + 750; x = (x >> 1) + 908; x += x*1;
  x = x*3 + 1144; x ^= (x << 1) + 1224; x = (x >> 1) + 1460; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_40(int x){
  x = x*3 + 281; x ^= (x << 1) + 443; x = (x >> 1) + 525; x += x*5;
  x = x*3 + 687; x ^= (x << 1) + 769; x = (x >> 1) + 931; x += x*1;
  x = x*3 + 1173; x ^= (x << 1) + 1255; x = (x >> 1) + 1497; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_41(int x){
  x = x*3 + 288; x ^= (x << 1) + 454; x = (x >> 1) + 538; x += x*5;
  x = x*3 + 704; x ^= (x << 1) + 788; x = (x >> 1) + 954; x += x*1;
  x = x*3 + 1202; x ^= (x << 1) + 1286; x = (x >> 1) + 1534; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_42(int x){
  x = x*3 + 295; x ^= (x << 1) + 465; x = (x >> 1) + 551; x += x*5;
  x = x*3 + 721; x ^= (x << 1) + 807; x = (x >> 1) + 977; x += x*1;
  x = x*3 + 1231; x ^= (x << 1) + 1317; x = (x >> 1) + 1571; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_43(int x){
  x = x*3 + 302; x ^= (x << 1) + 476; x = (x >> 1) + 564; x += x*5;
  x = x*3 + 738; x ^= (x << 1) + 826; x = (x >> 1) + 1000; x += x*1;
  x = x*3 + 1260; x ^= (x << 1) + 1348; x = (x >> 1) + 1608; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_44(int x){
  x = x*3 + 309; x ^= (x << 1) + 487; x = (x >> 1) + 577; x += x*5;
  x = x*3 + 755; x ^= (x << 1) + 845; x = (x >> 1) + 1023; x += x*1;
  x = x*3 + 1289; x ^= (x << 1) + 1379; x = (x >> 1) + 1645; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_45(int x){
  x = x*3 + 316; x ^= (x << 1) + 498; x = (x >> 1) + 590; x += x*5;
  x = x*3 + 772; x ^= (x << 1) + 864; x = (x >> 1) + 1046; x += x*1;
  x = x*3 + 1318; x ^= (x << 1) + 1410; x = (x >> 1) + 1682; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_46(int x){
  x = x*3 + 323; x ^= (x << 1) + 509; x = (x >> 1) + 603; x += x*5;
  x = x*3 + 789; x ^= (x << 1) + 883; x = (x >> 1) + 1069; x += x*1;
  x = x*3 + 1347; x ^= (x << 1) + 1441; x = (x >> 1) + 1719; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_47(int x){
  x = x*3 + 330; x ^= (x << 1) + 520; x = (x >> 1) + 616; x += x*5;
  x = x*3 + 806; x ^= (x << 1) + 902; x = (x >> 1) + 1092; x += x*1;
  x = x*3 + 1376; x ^= (x << 1) + 1472; x = (x >> 1) + 1756; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_48(int x){
  x = x*3 + 337; x ^= (x << 1) + 531; x = (x >> 1) + 629; x += x*5;
  x = x*3 + 823; x ^= (x << 1) + 921; x = (x >> 1) + 1115; x += x*1;
  x = x*3 + 1405; x ^= (x << 1) + 1503; x = (x >> 1) + 1793; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_49(int x){
  x = x*3 + 344; x ^= (x << 1) + 542; x = (x >> 1) + 642; x += x*5;
  x = x*3 + 840; x ^= (x << 1) + 940; x = (x >> 1) + 1138; x += x*1;
  x = x*3 + 1434; x ^= (x << 1) + 1534; x = (x >> 1) + 1830; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_50(int x){
  x = x*3 + 351; x ^= (x << 1) + 553; x = (x >> 1) + 655; x += x*5;
  x = x*3 + 857; x ^= (x << 1) + 959; x = (x >> 1) + 1161; x += x*1;
  x = x*3 + 1463; x ^= (x << 1) + 1565; x = (x >> 1) + 1867; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_51(int x){
  x = x*3 + 358; x ^= (x << 1) + 564; x = (x >> 1) + 668; x += x*5;
  x = x*3 + 874; x ^= (x << 1) + 978; x = (x >> 1) + 1184; x += x*1;
  x = x*3 + 1492; x ^= (x << 1) + 1596; x = (x >> 1) + 1904; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_52(int x){
  x = x*3 + 365; x ^= (x << 1) + 575; x = (x >> 1) + 681; x += x*5;
  x = x*3 + 891; x ^= (x << 1) + 997; x = (x >> 1) + 1207; x += x*1;
  x = x*3 + 1521; x ^= (x << 1) + 1627; x = (x >> 1) + 1941; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_53(int x){
  x = x*3 + 372; x ^= (x << 1) + 586; x = (x >> 1) + 694; x += x*5;
  x = x*3 + 908; x ^= (x << 1) + 1016; x = (x >> 1) + 1230; x += x*1;
  x = x*3 + 1550; x ^= (x << 1) + 1658; x = (x >> 1) + 1978; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_54(int x){
  x = x*3 + 379; x ^= (x << 1) + 597; x = (x >> 1) + 707; x += x*5;
  x = x*3 + 925; x ^= (x << 1) + 1035; x = (x >> 1) + 1253; x += x*1;
  x = x*3 + 1579; x ^= (x << 1) + 1689; x = (x >> 1) + 2015; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_55(int x){
  x = x*3 + 386; x ^= (x << 1) + 608; x = (x >> 1) + 720; x += x*5;
  x = x*3 + 942; x ^= (x << 1) + 1054; x = (x >> 1) + 1276; x += x*1;
  x = x*3 + 1608; x ^= (x << 1) + 1720; x = (x >> 1) + 2052; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_56(int x){
  x = x*3 + 393; x ^= (x << 1) + 619; x = (x >> 1) + 733; x += x*5;
  x = x*3 + 959; x ^= (x << 1) + 1073; x = (x >> 1) + 1299; x += x*1;
  x = x*3 + 1637; x ^= (x << 1) + 1751; x = (x >> 1) + 2089; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_57(int x){
  x = x*3 + 400; x ^= (x << 1) + 630; x = (x >> 1) + 746; x += x*5;
  x = x*3 + 976; x ^= (x << 1) + 1092; x = (x >> 1) + 1322; x += x*1;
  x = x*3 + 1666; x ^= (x << 1) + 1782; x = (x >> 1) + 2126; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_58(int x){
  x = x*3 + 407; x ^= (x << 1) + 641; x = (x >> 1) + 759; x += x*5;
  x = x*3 + 993; x ^= (x << 1) + 1111; x = (x >> 1) + 1345; x += x*1;
  x = x*3 + 1695; x ^= (x << 1) + 1813; x = (x >> 1) + 2163; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_59(int x){
  x = x*3 + 414; x ^= (x << 1) + 652; x = (x >> 1) + 772; x += x*5;
  x = x*3 + 1010; x ^= (x << 1) + 1130; x = (x >> 1) + 1368; x += x*1;
  x = x*3 + 1724; x ^= (x << 1) + 1844; x = (x >> 1) + 2200; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_60(int x){
  x = x*3 + 421; x ^= (x << 1) + 663; x = (x >> 1) + 785; x += x*5;
  x = x*3 + 1027; x ^= (x << 1) + 1149; x = (x >> 1) + 1391; x += x*1;
  x = x*3 + 1753; x ^= (x << 1) + 1875; x = (x >> 1) + 2237; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_61(int x){
  x = x*3 + 428; x ^= (x << 1) + 674; x = (x >> 1) + 798; x += x*5;
  x = x*3 + 1044; x ^= (x << 1) + 1168; x = (x >> 1) + 1414; x += x*1;
  x = x*3 + 1782; x ^= (x << 1) + 1906; x = (x >> 1) + 2274; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_62(int x){
  x = x*3 + 435; x ^= (x << 1) + 685; x = (x >> 1) + 811; x += x*5;
  x = x*3 + 1061; x ^= (x << 1) + 1187; x = (x >> 1) + 1437; x += x*1;
  x = x*3 + 1811; x ^= (x << 1) + 1937; x = (x >> 1) + 2311; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_63(int x){
  x = x*3 + 442; x ^= (x << 1) + 696; x = (x >> 1) + 824; x += x*5;
  x = x*3 + 1078; x ^= (x << 1) + 1206; x = (x >> 1) + 1460; x += x*1;
  x = x*3 + 1840; x ^= (x << 1) + 1968; x = (x >> 1) + 2348; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_64(int x){
  x = x*3 + 449; x ^= (x << 1) + 707; x = (x >> 1) + 837; x += x*5;
  x = x*3 + 1095; x ^= (x << 1) + 1225; x = (x >> 1) + 1483; x += x*1;
  x = x*3 + 1869; x ^= (x << 1) + 1999; x = (x >> 1) + 2385; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_65(int x){
  x = x*3 + 456; x ^= (x << 1) + 718; x = (x >> 1) + 850; x += x*5;
  x = x*3 + 1112; x ^= (x << 1) + 1244; x = (x >> 1) + 1506; x += x*1;
  x = x*3 + 1898; x ^= (x << 1) + 2030; x = (x >> 1) + 2422; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_66(int x){
  x = x*3 + 463; x ^= (x << 1) + 729; x = (x >> 1) + 863; x += x*5;
  x = x*3 + 1129; x ^= (x << 1) + 1263; x = (x >> 1) + 1529; x += x*1;
  x = x*3 + 1927; x ^= (x << 1) + 2061; x = (x >> 1) + 2459; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_67(int x){
  x = x*3 + 470; x ^= (x << 1) + 740; x = (x >> 1) + 876; x += x*5;
  x = x*3 + 1146; x ^= (x << 1) + 1282; x = (x >> 1) + 1552; x += x*1;
  x = x*3 + 1956; x ^= (x << 1) + 2092; x = (x >> 1) + 2496; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_68(int x){
  x = x*3 + 477; x ^= (x << 1) + 751; x = (x >> 1) + 889; x += x*5;
  x = x*3 + 1163; x ^= (x << 1) + 1301; x = (x >> 1) + 1575; x += x*1;
  x = x*3 + 1985; x ^= (x << 1) + 2123; x = (x >> 1) + 2533; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_69(int x){
  x = x*3 + 484; x ^= (x << 1) + 762; x = (x >> 1) + 902; x += x*5;
  x = x*3 + 1180; x ^= (x << 1) + 1320; x = (x >> 1) + 1598; x += x*1;
  x = x*3 + 2014; x ^= (x << 1) + 2154; x = (x >> 1) + 2570; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_70(int x){
  x = x*3 + 491; x ^= (x << 1) + 773; x = (x >> 1) + 915; x += x*5;
  x = x*3 + 1197; x ^= (x << 1) + 1339; x = (x >> 1) + 1621; x += x*1;
  x = x*3 + 2043; x ^= (x << 1) + 2185; x = (x >> 1) + 2607; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_71(int x){
  x = x*3 + 498; x ^= (x << 1) + 784; x = (x >> 1) + 928; x += x*5;
  x = x*3 + 1214; x ^= (x << 1) + 1358; x = (x >> 1) + 1644; x += x*1;
  x = x*3 + 2072; x ^= (x << 1) + 2216; x = (x >> 1) + 2644; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_72(int x){
  x = x*3 + 505; x ^= (x << 1) + 795; x = (x >> 1) + 941; x += x*5;
  x = x*3 + 1231; x ^= (x << 1) + 1377; x = (x >> 1) + 1667; x += x*1;
  x = x*3 + 2101; x ^= (x << 1) + 2247; x = (x >> 1) + 2681; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_73(int x){
  x = x*3 + 512; x ^= (x << 1) + 806; x = (x >> 1) + 954; x += x*5;
  x = x*3 + 1248; x ^= (x << 1) + 1396; x = (x >> 1) + 1690; x += x*1;
  x = x*3 + 2130; x ^= (x << 1) + 2278; x = (x >> 1) + 2718; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_74(int x){
  x = x*3 + 519; x ^= (x << 1) + 817; x = (x >> 1) + 967; x += x*5;
  x = x*3 + 1265; x ^= (x << 1) + 1415; x = (x >> 1) + 1713; x += x*1;
  x = x*3 + 2159; x ^= (x << 1) + 2309; x = (x >> 1) + 2755; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_75(int x){
  x = x*3 + 526; x ^= (x << 1) + 828; x = (x >> 1) + 980; x += x*5;
  x = x*3 + 1282; x ^= (x << 1) + 1434; x = (x >> 1) + 1736; x += x*1;
  x = x*3 + 2188; x ^= (x << 1) + 2340; x = (x >> 1) + 2792; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_76(int x){
  x = x*3 + 533; x ^= (x << 1) + 839; x = (x >> 1) + 993; x += x*5;
  x = x*3 + 1299; x ^= (x << 1) + 1453; x = (x >> 1) + 1759; x += x*1;
  x = x*3 + 2217; x ^= (x << 1) + 2371; x = (x >> 1) + 2829; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_77(int x){
  x = x*3 + 540; x ^= (x << 1) + 850; x = (x >> 1) + 1006; x += x*5;
  x = x*3 + 1316; x ^= (x << 1) + 1472; x = (x >> 1) + 1782; x += x*1;
  x = x*3 + 2246; x ^= (x << 1) + 2402; x = (x >> 1) + 2866; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_78(int x){
  x = x*3 + 547; x ^= (x << 1) + 861; x = (x >> 1) + 1019; x += x*5;
  x = x*3 + 1333; x ^= (x << 1) + 1491; x = (x >> 1) + 1805; x += x*1;
  x = x*3 + 2275; x ^= (x << 1) + 2433; x = (x >> 1) + 2903; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_79(int x){
  x = x*3 + 554; x ^= (x << 1) + 872; x = (x >> 1) + 1032; x += x*5;
  x = x*3 + 1350; x ^= (x << 1) + 1510; x = (x >> 1) + 1828; x += x*1;
  x = x*3 + 2304; x ^= (x << 1) + 2464; x = (x >> 1) + 2940; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_80(int x){
  x = x*3 + 561; x ^= (x << 1) + 883; x = (x >> 1) + 1045; x += x*5;
  x = x*3 + 1367; x ^= (x << 1) + 1529; x = (x >> 1) + 1851; x += x*1;
  x = x*3 + 2333; x ^= (x << 1) + 2495; x = (x >> 1) + 2977; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_81(int x){
  x = x*3 + 568; x ^= (x << 1) + 894; x = (x >> 1) + 1058; x += x*5;
  x = x*3 + 1384; x ^= (x << 1) + 1548; x = (x >> 1) + 1874; x += x*1;
  x = x*3 + 2362; x ^= (x << 1) + 2526; x = (x >> 1) + 3014; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_82(int x){
  x = x*3 + 575; x ^= (x << 1) + 905; x = (x >> 1) + 1071; x += x*5;
  x = x*3 + 1401; x ^= (x << 1) + 1567; x = (x >> 1) + 1897; x += x*1;
  x = x*3 + 2391; x ^= (x << 1) + 2557; x = (x >> 1) + 3051; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_83(int x){
  x = x*3 + 582; x ^= (x << 1) + 916; x = (x >> 1) + 1084; x += x*5;
  x = x*3 + 1418; x ^= (x << 1) + 1586; x = (x >> 1) + 1920; x += x*1;
  x = x*3 + 2420; x ^= (x << 1) + 2588; x = (x >> 1) + 3088; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_84(int x){
  x = x*3 + 589; x ^= (x << 1) + 927; x = (x >> 1) + 1097; x += x*5;
  x = x*3 + 1435; x ^= (x << 1) + 1605; x = (x >> 1) + 1943; x += x*1;
  x = x*3 + 2449; x ^= (x << 1) + 2619; x = (x >> 1) + 3125; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_85(int x){
  x = x*3 + 596; x ^= (x << 1) + 938; x = (x >> 1) + 1110; x += x*5;
  x = x*3 + 1452; x ^= (x << 1) + 1624; x = (x >> 1) + 1966; x += x*1;
  x = x*3 + 2478; x ^= (x << 1) + 2650; x = (x >> 1) + 3162; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_86(int x){
  x = x*3 + 603; x ^= (x << 1) + 949; x = (x >> 1) + 1123; x += x*5;
  x = x*3 + 1469; x ^= (x << 1) + 1643; x = (x >> 1) + 1989; x += x*1;
  x = x*3 + 2507; x ^= (x << 1) + 2681; x = (x >> 1) + 3199; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_87(int x){
  x = x*3 + 610; x ^= (x << 1) + 960; x = (x >> 1) + 1136; x += x*5;
  x = x*3 + 1486; x ^= (x << 1) + 1662; x = (x >> 1) + 2012; x += x*1;
  x = x*3 + 2536; x ^= (x << 1) + 2712; x = (x >> 1) + 3236; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_88(int x){
  x = x*3 + 617; x ^= (x << 1) + 971; x = (x >> 1) + 1149; x += x*5;
  x = x*3 + 1503; x ^= (x << 1) + 1681; x = (x >> 1) + 2035; x += x*1;
  x = x*3 + 2565; x ^= (x << 1) + 2743; x = (x >> 1) + 3273; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_89(int x){
  x = x*3 + 624; x ^= (x << 1) + 982; x = (x >> 1) + 1162; x += x*5;
  x = x*3 + 1520; x ^= (x << 1) + 1700; x = (x >> 1) + 2058; x += x*1;
  x = x*3 + 2594; x ^= (x << 1) + 2774; x = (x >> 1) + 3310; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_90(int x){
  x = x*3 + 631; x ^= (x << 1) + 993; x = (x >> 1) + 1175; x += x*5;
  x = x*3 + 1537; x ^= (x << 1) + 1719; x = (x >> 1) + 2081; x += x*1;
  x = x*3 + 2623; x ^= (x << 1) + 2805; x = (x >> 1) + 3347; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_91(int x){
  x = x*3 + 638; x ^= (x << 1) + 1004; x = (x >> 1) + 1188; x += x*5;
  x = x*3 + 1554; x ^= (x << 1) + 1738; x = (x >> 1) + 2104; x += x*1;
  x = x*3 + 2652; x ^= (x << 1) + 2836; x = (x >> 1) + 3384; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_92(int x){
  x = x*3 + 645; x ^= (x << 1) + 1015; x = (x >> 1) + 1201; x += x*5;
  x = x*3 + 1571; x ^= (x << 1) + 1757; x = (x >> 1) + 2127; x += x*1;
  x = x*3 + 2681; x ^= (x << 1) + 2867; x = (x >> 1) + 3421; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_93(int x){
  x = x*3 + 652; x ^= (x << 1) + 1026; x = (x >> 1) + 1214; x += x*5;
  x = x*3 + 1588; x ^= (x << 1) + 1776; x = (x >> 1) + 2150; x += x*1;
  x = x*3 + 2710; x ^= (x << 1) + 2898; x = (x >> 1) + 3458; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_94(int x){
  x = x*3 + 659; x ^= (x << 1) + 1037; x = (x >> 1) + 1227; x += x*5;
  x = x*3 + 1605; x ^= (x << 1) + 1795; x = (x >> 1) + 2173; x += x*1;
  x = x*3 + 2739; x ^= (x << 1) + 2929; x = (x >> 1) + 3495; x += x*3;
  return x;
}
__attribute__((noinline)) static int sb_95(int x){
  x = x*3 + 666; x ^= (x << 1) + 1048; x = (x >> 1) + 1240; x += x*5;
  x = x*3 + 1622; x ^= (x << 1) + 1814; x = (x >> 1) + 2196; x += x*1;
  x = x*3 + 2768; x ^= (x << 1) + 2960; x = (x >> 1) + 3532; x += x*3;
  return x;
}

static int sb_call(int idx, int x){
  switch (idx & (NFUNCS-1)) {
    case 0: return sb_0(x);
    case 1: return sb_1(x);
    case 2: return sb_2(x);
    case 3: return sb_3(x);
    case 4: return sb_4(x);
    case 5: return sb_5(x);
    case 6: return sb_6(x);
    case 7: return sb_7(x);
    case 8: return sb_8(x);
    case 9: return sb_9(x);
    case 10: return sb_10(x);
    case 11: return sb_11(x);
    case 12: return sb_12(x);
    case 13: return sb_13(x);
    case 14: return sb_14(x);
    case 15: return sb_15(x);
    case 16: return sb_16(x);
    case 17: return sb_17(x);
    case 18: return sb_18(x);
    case 19: return sb_19(x);
    case 20: return sb_20(x);
    case 21: return sb_21(x);
    case 22: return sb_22(x);
    case 23: return sb_23(x);
    case 24: return sb_24(x);
    case 25: return sb_25(x);
    case 26: return sb_26(x);
    case 27: return sb_27(x);
    case 28: return sb_28(x);
    case 29: return sb_29(x);
    case 30: return sb_30(x);
    case 31: return sb_31(x);
    case 32: return sb_32(x);
    case 33: return sb_33(x);
    case 34: return sb_34(x);
    case 35: return sb_35(x);
    case 36: return sb_36(x);
    case 37: return sb_37(x);
    case 38: return sb_38(x);
    case 39: return sb_39(x);
    case 40: return sb_40(x);
    case 41: return sb_41(x);
    case 42: return sb_42(x);
    case 43: return sb_43(x);
    case 44: return sb_44(x);
    case 45: return sb_45(x);
    case 46: return sb_46(x);
    case 47: return sb_47(x);
    case 48: return sb_48(x);
    case 49: return sb_49(x);
    case 50: return sb_50(x);
    case 51: return sb_51(x);
    case 52: return sb_52(x);
    case 53: return sb_53(x);
    case 54: return sb_54(x);
    case 55: return sb_55(x);
    case 56: return sb_56(x);
    case 57: return sb_57(x);
    case 58: return sb_58(x);
    case 59: return sb_59(x);
    case 60: return sb_60(x);
    case 61: return sb_61(x);
    case 62: return sb_62(x);
    case 63: return sb_63(x);
    case 64: return sb_64(x);
    case 65: return sb_65(x);
    case 66: return sb_66(x);
    case 67: return sb_67(x);
    case 68: return sb_68(x);
    case 69: return sb_69(x);
    case 70: return sb_70(x);
    case 71: return sb_71(x);
    case 72: return sb_72(x);
    case 73: return sb_73(x);
    case 74: return sb_74(x);
    case 75: return sb_75(x);
    case 76: return sb_76(x);
    case 77: return sb_77(x);
    case 78: return sb_78(x);
    case 79: return sb_79(x);
    case 80: return sb_80(x);
    case 81: return sb_81(x);
    case 82: return sb_82(x);
    case 83: return sb_83(x);
    case 84: return sb_84(x);
    case 85: return sb_85(x);
    case 86: return sb_86(x);
    case 87: return sb_87(x);
    case 88: return sb_88(x);
    case 89: return sb_89(x);
    case 90: return sb_90(x);
    case 91: return sb_91(x);
    case 92: return sb_92(x);
    case 93: return sb_93(x);
    case 94: return sb_94(x);
    case 95: return sb_95(x);
  }
  return x;
}

void sb_kernel(sb_args_t *__UNIFORM__ args) {
	int i = blockIdx.x;

	volatile int *lm = (volatile int *)csr_read(VX_CSR_LOCAL_MEM_BASE);
	int base = ((vx_warp_id() * vx_num_threads()) + vx_thread_id()) * LM_SLOTS;
	for (int s = 0; s < LM_SLOTS; s++) lm[base + s] = s + 1;

	int acc = 0;
	for (int k = 0; k < ITERS; k++) {
		// DATA side — identical to unit_storm: 4 independent local-memory loads
		// spanning 4 banks, plus 2 resident global loads. Kept small on purpose.
		int l0 = lm[base + 0];
		int l1 = lm[base + 1];
		int l2 = lm[base + 2];
		int l3 = lm[base + 3];
		int g0 = g_tab[(i * 7 + k * 17) & (TAB_WORDS - 1)];
		int g1 = g_tab[(i * 13 + k * 101 + 512) & (TAB_WORDS - 1)];

		// INSTRUCTION side — a runtime-indexed jump into ~19 KB of hot text.
		// The stride is coprime with NFUNCS so successive iterations land far apart
		// and sequential prefetch cannot hide the miss. This is what creates the
		// SECOND memory stream that mem_arb/rsp_switch has to arbitrate against the
		// data stream.
		int fidx = (i * 37 + k * 53) & (NFUNCS - 1);
		int fv = sb_call(fidx, k + i);

		acc += (l0 + l1 + l2 + l3) ^ (g0 + g1) ^ fv;
		lm[base + (k & (LM_SLOTS - 1))] = acc + k;
	}
	args->out[i] = acc;
}

// Host reference — same recurrence, same functions, no device state.
static int sb_ref(int i) {
	int lmv[LM_SLOTS];
	for (int s = 0; s < LM_SLOTS; s++) lmv[s] = s + 1;
	int acc = 0;
	for (int k = 0; k < ITERS; k++) {
		int l0 = lmv[0], l1 = lmv[1], l2 = lmv[2], l3 = lmv[3];
		int g0 = tab_ref((i * 7 + k * 17) & (TAB_WORDS - 1));
		int g1 = tab_ref((i * 13 + k * 101 + 512) & (TAB_WORDS - 1));
		int fv = sb_call((i * 37 + k * 53) & (NFUNCS - 1), k + i);
		acc += (l0 + l1 + l2 + l3) ^ (g0 + g1) ^ fv;
		lmv[k & (LM_SLOTS - 1)] = acc + k;
	}
	return acc;
}

int main() {
	sb_args_t args; args.out = (int *)out_buf;
	uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * (uint32_t)vx_num_threads();
	if (total > MAX_TOTAL) total = MAX_TOTAL;
	vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)sb_kernel, &args);

	uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
	uint32_t per = total / nc, lo = cid * per, hi = lo + per;
	int errors = 0;
	for (uint32_t i = lo; i < hi; i++) if (out_buf[i] != sb_ref((int)i)) errors++;
	return errors;
}
