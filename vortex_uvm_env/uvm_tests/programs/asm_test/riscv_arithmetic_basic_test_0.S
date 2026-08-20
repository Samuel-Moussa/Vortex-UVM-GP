.include "user_define.h"
.globl _start
.section .text
_start:           
                  .include "user_init.s"
                  csrr x5, 0xf14
                  li x6, 0
                  beq x5, x6, 0f

0: la x2, h0_start
jalr x0, x2, 0
h0_start:
                  li x12, 0x40001104
                  csrw 0x301, x12
kernel_sp:        
                  la x28, kernel_stack_end

trap_vec_init:    
                  la x12, mtvec_handler
                  ori x12, x12, 0
                  csrw 0x305, x12 # MTVEC

mepc_setup:       
                  la x12, init
                  csrw 0x341, x12

custom_csr_setup: 
                  nop

init_machine_mode:
                  li x12, 0x1800
                  csrw 0x300, x12 # MSTATUS
                  li x12, 0x0
                  csrw 0x304, x12 # MIE
                  mret
init:             
                  li x0, 0x3
                  li x1, 0xf1724a48
                  li x2, 0xa417d9e
                  li x3, 0xcd3363e1
                  li x4, 0x80000000
                  li x5, 0xb
                  li x6, 0x1
                  li x7, 0x80000000
                  li x8, 0x9790452d
                  li x9, 0x0
                  li x10, 0xff90682b
                  li x11, 0xf99d0ac3
                  li x12, 0xf7389d37
                  li x13, 0xc19d7907
                  li x14, 0x80000000
                  li x15, 0x0
                  li x16, 0x80000000
                  li x17, 0x0
                  li x18, 0x7
                  li x19, 0x1
                  li x21, 0x0
                  li x22, 0x80000000
                  li x23, 0xc
                  li x24, 0x0
                  li x25, 0x80000000
                  li x26, 0xf438255f
                  li x27, 0x0
                  li x29, 0xf
                  li x30, 0x9
                  li x31, 0xb
                  la x20, user_stack_end
main:             li           a6, 0xffffffff #start riscv_int_numeric_corner_stream_21
                  li           s2, 0x89cad33b
                  li           s8, 0x0
                  li           s7, 0x0
                  li           a7, 0x80000000
                  li           t4, 0x535e10a
                  li           t0, 0x80000000
                  li           gp, 0x0
                  li           s1, 0x80000000
                  li           s10, 0xcbe7cebf
                  div          s7, s7, t0
                  addi         gp, s7, 2029
                  sub          s8, s2, s7
                  mulhu        s1, s7, gp
                  mulh         s8, s10, a6
                  divu         s10, a7, s2
                  mulh         s8, s10, a6
                  add          a6, s10, gp
                  remu         a7, s8, t4
                  divu         s10, a7, s2
                  div          s7, s7, t0
                  nop
                  mul          a7, s10, s10
                  auipc        a6, 400075
                  rem          t0, s1, t0
                  remu         a7, s8, t4
                  mulh         s8, s10, a6
                  mulhu        s1, s7, gp
                  rem          t0, s1, t0
                  remu         a7, s8, t4
                  remu         a7, s8, t4
                  auipc        a6, 400075 #end riscv_int_numeric_corner_stream_21
                  li           ra, 0xc3ec2446 #start riscv_int_numeric_corner_stream_0
                  li           a3, 0xffffffff
                  li           s0, 0x0
                  li           s11, 0xffffffff
                  li           tp, 0xd7568c63
                  li           s2, 0x80000000
                  li           t2, 0x0
                  li           gp, 0x7075ddf8
                  li           a7, 0xffffffff
                  li           a6, 0xacf07b09
                  divu         s2, s0, a3
                  mulhu        tp, a6, ra
                  mulh         a7, s2, t2
                  sub          a7, a3, a6
                  mulhu        tp, a6, ra
                  remu         s0, a7, s11
                  auipc        t2, 400075
                  auipc        t2, 400075
                  addi         ra, a6, 2029
                  rem          gp, tp, gp
                  nop
                  auipc        t2, 400075
                  mulhu        tp, a6, ra
                  sub          a7, a3, a6
                  mul          s0, s2, s2
                  div          a6, a6, gp
                  auipc        t2, 400075
                  rem          gp, tp, gp
                  auipc        t2, 400075
                  mul          s0, s2, s2
                  mulh         a7, s2, t2
                  sub          a7, a3, a6
                  lui          a7, 955933
                  mulh         a7, s2, t2
                  mulhsu       s2, s0, tp #end riscv_int_numeric_corner_stream_0
                  li           t6, 0x80000000 #start riscv_int_numeric_corner_stream_23
                  li           s0, 0x0
                  li           s1, 0x80000000
                  li           s11, 0x80000000
                  li           t4, 0x0
                  li           s8, 0xffffffff
                  li           s2, 0x80000000
                  li           s9, 0x8a4d3452
                  li           t2, 0xffffffff
                  li           s5, 0xffffffff
                  mulh         s11, t4, s2
                  add          s2, t4, t2
                  divu         t4, s5, s8
                  mulh         s11, t4, s2
                  remu         s5, s11, t6
                  nop
                  mul          s5, t4, t4
                  mulhsu       t4, s5, s1
                  sub          s11, s8, s9
                  lui          s11, 955933
                  nop
                  lui          s11, 955933
                  sub          s11, s8, s9
                  remu         s5, s11, t6
                  rem          s0, s1, s0
                  auipc        s2, 400075
                  mulh         s11, t4, s2
                  rem          s0, s1, s0
                  mul          s5, t4, t4
                  sub          s11, s8, s9
                  divu         t4, s5, s8
                  add          s2, t4, t2
                  rem          s0, s1, s0
                  divu         t4, s5, s8
                  remu         s5, s11, t6
                  remu         s5, s11, t6
                  div          s9, s9, s0
                  addi         t2, s9, 2029
                  mul          s5, t4, t4 #end riscv_int_numeric_corner_stream_23
                  li           s10, 0x0 #start riscv_int_numeric_corner_stream_29
                  li           a0, 0xffffffff
                  li           a1, 0xd2289012
                  li           s6, 0x80000000
                  li           s0, 0x80000000
                  li           s11, 0x80000000
                  li           a4, 0xffffffff
                  li           a2, 0x9d5d93fe
                  li           a5, 0xffffffff
                  li           tp, 0xffffffff
                  mulh         s6, s10, a1
                  mulh         s6, s10, a1
                  mulh         s6, s10, a1
                  nop
                  remu         a2, s6, s11
                  lui          s6, 955933
                  divu         s10, a2, a4
                  mulh         s6, s10, a1
                  div          a5, a5, s0
                  nop
                  mulhsu       s10, a2, a0
                  nop
                  mulhsu       s10, a2, a0
                  mulh         s6, s10, a1
                  div          a5, a5, s0
                  remu         a2, s6, s11
                  remu         a2, s6, s11
                  addi         tp, a5, 2029 #end riscv_int_numeric_corner_stream_29
                  li           t2, 0xa570c050 #start riscv_int_numeric_corner_stream_33
                  li           t4, 0x80000000
                  li           a4, 0x80000000
                  li           gp, 0x80000000
                  li           t1, 0x80000000
                  li           tp, 0x80000000
                  li           s8, 0x0
                  li           a5, 0x80000000
                  li           ra, 0x1605c04a
                  li           a3, 0x80000000
                  auipc        t1, 400075
                  div          a4, a4, gp
                  rem          gp, tp, gp
                  remu         t2, a5, t4
                  auipc        t1, 400075
                  lui          a5, 955933
                  div          a4, a4, gp
                  nop
                  mulhu        tp, a4, ra
                  mulhu        tp, a4, ra
                  add          t1, s8, ra
                  div          a4, a4, gp
                  mulh         a5, s8, t1
                  remu         t2, a5, t4
                  mulhsu       s8, t2, tp
                  addi         ra, a4, 2029
                  mul          t2, s8, s8
                  divu         s8, t2, a3
                  mulhsu       s8, t2, tp
                  mulhu        tp, a4, ra
                  lui          a5, 955933
                  auipc        t1, 400075
                  mul          t2, s8, s8
                  rem          gp, tp, gp
                  nop
                  mulh         a5, s8, t1
                  nop
                  lui          a5, 955933
                  auipc        t1, 400075
                  addi         ra, a4, 2029 #end riscv_int_numeric_corner_stream_33
                  li           tp, 0x0 #start riscv_int_numeric_corner_stream_18
                  li           a7, 0x0
                  li           a0, 0xc4a82f00
                  li           t6, 0xffffffff
                  li           a2, 0x0
                  li           s1, 0xffffffff
                  li           a1, 0x80000000
                  li           t1, 0xb8adddaa
                  li           s5, 0x80000000
                  li           a6, 0x0
                  auipc        a0, 400075
                  sub          a7, a2, a6
                  lui          a7, 955933
                  auipc        a0, 400075
                  mul          a1, s5, s5
                  rem          t1, s1, t1
                  addi         tp, a6, 2029
                  mulh         a7, s5, a0
                  mulhu        s1, a6, tp
                  div          a6, a6, t1
                  remu         a1, a7, t6
                  rem          t1, s1, t1
                  rem          t1, s1, t1
                  remu         a1, a7, t6
                  mul          a1, s5, s5
                  sub          a7, a2, a6
                  sub          a7, a2, a6
                  mulhsu       s5, a1, s1
                  nop
                  mulh         a7, s5, a0
                  auipc        a0, 400075
                  mulhsu       s5, a1, s1
                  nop
                  mulhu        s1, a6, tp
                  add          a0, s5, tp
                  rem          t1, s1, t1
                  lui          a7, 955933
                  mulhu        s1, a6, tp
                  mulhu        s1, a6, tp
                  mulh         a7, s5, a0 #end riscv_int_numeric_corner_stream_18
                  li           a3, 0x68352933 #start riscv_int_numeric_corner_stream_24
                  li           s9, 0x80000000
                  li           s2, 0x0
                  li           a6, 0x0
                  li           a4, 0x39b5ed3f
                  li           s11, 0xc1466d9e
                  li           t0, 0x0
                  li           tp, 0xaa3efb80
                  li           gp, 0xffffffff
                  li           a5, 0x80000000
                  add          a3, s9, gp
                  lui          s2, 955933
                  mulh         s2, s9, a3
                  remu         a4, s2, s11
                  sub          s2, a5, a6
                  add          a3, s9, gp
                  remu         a4, s2, s11
                  rem          tp, t0, tp
                  addi         gp, a6, 2029
                  addi         gp, a6, 2029
                  sub          s2, a5, a6
                  divu         s9, a4, a5
                  remu         a4, s2, s11
                  sub          s2, a5, a6
                  mulhsu       s9, a4, t0
                  lui          s2, 955933
                  addi         gp, a6, 2029
                  mulh         s2, s9, a3
                  mul          a4, s9, s9
                  addi         gp, a6, 2029
                  mulh         s2, s9, a3
                  mulhu        t0, a6, gp #end riscv_int_numeric_corner_stream_24
                  li           gp, 0x0 #start riscv_int_numeric_corner_stream_31
                  li           t2, 0x0
                  li           tp, 0x80000000
                  li           t4, 0x69ab0455
                  li           t5, 0x0
                  li           s8, 0x80000000
                  li           a7, 0xffffffff
                  li           s6, 0xffffffff
                  li           s10, 0xffffffff
                  li           t6, 0x172e4259
                  add          a7, t5, gp
                  mulhsu       t5, s6, t2
                  mulh         t4, t5, a7
                  mulh         t4, t5, a7
                  div          s10, s10, tp
                  add          a7, t5, gp
                  mulhsu       t5, s6, t2
                  mul          s6, t5, t5
                  addi         gp, s10, 2029
                  mulh         t4, t5, a7
                  mulh         t4, t5, a7
                  mulh         t4, t5, a7
                  mulh         t4, t5, a7
                  mulhu        t2, s10, gp
                  addi         gp, s10, 2029
                  mulh         t4, t5, a7
                  divu         t5, s6, s8
                  addi         gp, s10, 2029
                  div          s10, s10, tp
                  auipc        a7, 400075
                  sub          t4, s8, s10
                  div          s10, s10, tp
                  mulh         t4, t5, a7 #end riscv_int_numeric_corner_stream_31
                  li           a6, 0xffffffff #start riscv_int_numeric_corner_stream_35
                  li           t0, 0x91745576
                  li           a0, 0x35c906ff
                  li           s9, 0x80000000
                  li           s8, 0xffffffff
                  li           gp, 0xff007350
                  li           t4, 0x0
                  li           a7, 0xa8b98302
                  li           s11, 0x0
                  li           s5, 0xa998ee52
                  auipc        a6, 400075
                  nop
                  mulhsu       s11, a7, a0
                  div          s8, s8, t0
                  lui          s9, 955933
                  addi         gp, s8, 2029
                  remu         a7, s9, t4
                  sub          s9, s5, s8
                  sub          s9, s5, s8
                  remu         a7, s9, t4
                  auipc        a6, 400075
                  lui          s9, 955933
                  mulh         s9, s11, a6
                  add          a6, s11, gp
                  mulhu        a0, s8, gp
                  mulhu        a0, s8, gp
                  nop
                  mulhu        a0, s8, gp
                  auipc        a6, 400075
                  sub          s9, s5, s8
                  mul          a7, s11, s11 #end riscv_int_numeric_corner_stream_35
                  li           s9, 0xceab5516 #start riscv_int_numeric_corner_stream_15
                  li           s8, 0xffffffff
                  li           s5, 0x80000000
                  li           s6, 0xfc9c6d2c
                  li           s10, 0x8872c92d
                  li           tp, 0xb7955586
                  li           s2, 0xffffffff
                  li           a2, 0x0
                  li           s0, 0x80000000
                  li           gp, 0xffffffff
                  mulh         s8, s9, a2
                  divu         s9, s2, s5
                  add          a2, s9, gp
                  auipc        a2, 400075
                  addi         gp, s6, 2029
                  add          a2, s9, gp
                  lui          s8, 955933
                  mulhsu       s9, s2, s0
                  mulhu        s0, s6, gp
                  div          s6, s6, tp
                  sub          s8, s5, s6
                  mulhsu       s9, s2, s0
                  addi         gp, s6, 2029
                  div          s6, s6, tp
                  auipc        a2, 400075
                  add          a2, s9, gp
                  rem          tp, s0, tp
                  add          a2, s9, gp
                  div          s6, s6, tp #end riscv_int_numeric_corner_stream_15
                  li           t5, 0x0 #start riscv_int_numeric_corner_stream_14
                  li           s10, 0xffffffff
                  li           s7, 0x1af21917
                  li           s9, 0xffffffff
                  li           a0, 0xffffffff
                  li           s2, 0x64e5cacc
                  li           gp, 0x0
                  li           s8, 0xffffffff
                  li           t2, 0xade15c2
                  li           s0, 0x80000000
                  div          s8, s8, t2
                  add          a0, s10, gp
                  sub          s9, s7, s8
                  mul          s2, s10, s10
                  mulhu        s0, s8, gp
                  mulhsu       s10, s2, s0
                  auipc        a0, 400075
                  sub          s9, s7, s8
                  lui          s9, 955933
                  sub          s9, s7, s8
                  nop
                  mul          s2, s10, s10
                  remu         s2, s9, t5
                  divu         s10, s2, s7
                  auipc        a0, 400075
                  mulh         s9, s10, a0
                  auipc        a0, 400075
                  div          s8, s8, t2 #end riscv_int_numeric_corner_stream_14
                  li           s6, 0x0 #start riscv_int_numeric_corner_stream_9
                  li           a3, 0x0
                  li           t4, 0x0
                  li           t6, 0x80000000
                  li           gp, 0xffffffff
                  li           ra, 0x10a96dd5
                  li           a4, 0xe6f61fd6
                  li           s11, 0xffffffff
                  li           a6, 0x0
                  li           s3, 0x39fc112d
                  mul          a6, t4, t4
                  sub          s11, s3, s6
                  mul          a6, t4, t4
                  mul          a6, t4, t4
                  sub          s11, s3, s6
                  mul          a6, t4, t4
                  div          s6, s6, gp
                  mulh         s11, t4, a4
                  divu         t4, a6, s3
                  rem          gp, a3, gp
                  div          s6, s6, gp
                  mulh         s11, t4, a4
                  rem          gp, a3, gp
                  mul          a6, t4, t4
                  div          s6, s6, gp
                  mulh         s11, t4, a4
                  remu         a6, s11, t6
                  rem          gp, a3, gp
                  sub          s11, s3, s6
                  auipc        a4, 400075
                  lui          s11, 955933
                  addi         ra, s6, 2029 #end riscv_int_numeric_corner_stream_9
                  li           tp, 0xce75cb92 #start riscv_int_numeric_corner_stream_16
                  li           a1, 0xffffffff
                  li           s6, 0x8864e323
                  li           t4, 0x80000000
                  li           a0, 0x0
                  li           s3, 0x2c18e1fe
                  li           s1, 0x80000000
                  li           t0, 0x80000000
                  li           a2, 0xd6f5e574
                  li           a5, 0x0
                  mulhsu       s6, a1, s1
                  mulhsu       s6, a1, s1
                  rem          t0, s1, t0
                  mul          a1, s6, s6
                  rem          t0, s1, t0
                  mulhsu       s6, a1, s1
                  mulh         s3, s6, a0
                  rem          t0, s1, t0
                  mulh         s3, s6, a0
                  addi         tp, a5, 2029
                  divu         s6, a1, a2
                  auipc        a0, 400075
                  lui          s3, 955933
                  addi         tp, a5, 2029
                  remu         a1, s3, t4
                  add          a0, s6, tp
                  rem          t0, s1, t0
                  mulhu        s1, a5, tp
                  mul          a1, s6, s6 #end riscv_int_numeric_corner_stream_16
                  li           t4, 0x287875e8 #start riscv_int_numeric_corner_stream_3
                  li           a2, 0x0
                  li           t6, 0xffffffff
                  li           tp, 0x80000000
                  li           a6, 0x0
                  li           s5, 0x1e50b863
                  li           s1, 0x741ddcb0
                  li           t5, 0x0
                  li           s7, 0xffffffff
                  li           s9, 0x80000000
                  addi         tp, s9, 2029
                  sub          t4, s7, s9
                  mul          s5, t5, t5
                  addi         tp, s9, 2029
                  mul          s5, t5, t5
                  auipc        a6, 400075
                  mulhsu       t5, s5, a2
                  auipc        a6, 400075
                  divu         t5, s5, s7
                  div          s9, s9, s1
                  add          a6, t5, tp
                  auipc        a6, 400075
                  mulh         t4, t5, a6
                  mulhu        a2, s9, tp
                  mulh         t4, t5, a6
                  lui          t4, 955933 #end riscv_int_numeric_corner_stream_3
                  li           s0, 0xc443e035 #start riscv_int_numeric_corner_stream_22
                  li           a5, 0x0
                  li           s6, 0x58ea13a5
                  li           t1, 0xffffffff
                  li           a1, 0x0
                  li           t4, 0x37bbcb4d
                  li           t2, 0x80000000
                  li           s5, 0x80000000
                  li           a0, 0xffffffff
                  li           ra, 0xffffffff
                  add          s0, s6, ra
                  mulhsu       s6, a0, t2
                  auipc        s0, 400075
                  mulhu        t2, a5, ra
                  lui          s5, 955933
                  sub          s5, a1, a5
                  sub          s5, a1, a5
                  addi         ra, a5, 2029
                  mul          a0, s6, s6
                  addi         ra, a5, 2029
                  divu         s6, a0, a1
                  mul          a0, s6, s6
                  mulh         s5, s6, s0
                  remu         a0, s5, t4
                  mul          a0, s6, s6
                  divu         s6, a0, a1
                  sub          s5, a1, a5
                  mulh         s5, s6, s0
                  mulh         s5, s6, s0
                  auipc        s0, 400075
                  mulhsu       s6, a0, t2 #end riscv_int_numeric_corner_stream_22
                  slti         s8, ra, -2031
                  c.and        a3, s0
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  c.add        s7, s6
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  c.mv         s8, t5
                  c.xor        a5, s0
                  c.or         a3, s1
                  xor          t5, s1, a7
                  divu         s1, s4, a4
                  nop
                  c.add        s7, s6
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  c.lui        s0, 15
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  c.nop
                  c.li         t6, 20
                  andi         s5, tp, -69
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  c.or         a3, s1
                  c.and        a3, s0
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  c.srai       a3, 9
                  auipc        tp, 400075
                  c.srli       a0, 18
                  c.sub        s0, a4
                  c.slli       s8, 9
                  nop
                  auipc        tp, 400075
                  srli         a3, s8, 11
                  c.slli       s8, 9
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.nop
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  c.add        s7, s6
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  c.nop
                  xor          t5, s1, a7
                  c.nop
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  c.slli       s8, 9
                  xori         t5, s5, -792
                  addi         zero, t6, 2029
                  c.add        s7, s6
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  c.addi       s2, 16
                  c.srai       a3, 9
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  c.nop
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  remu         t0, s7, s1
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  c.xor        a5, s0
                  add          s5, s8, a6
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  c.slli       s8, 9
                  c.lui        s0, 15
                  or           t4, a3, a3
                  c.addi       s2, 16
                  sra          a3, s6, t4
                  c.add        s7, s6
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  slti         s8, ra, -2031
                  mul          s6, a0, s0
                  nop
                  c.mv         s8, t5
                  auipc        tp, 400075
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  sub          s9, s5, s6
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  c.sub        s0, a4
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  c.xor        a5, s0
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  mulh         s9, s8, gp
                  c.lui        s0, 15
                  c.slli       s8, 9
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  c.xor        a5, s0
                  div          a2, t1, a7
                  mul          s6, a0, s0
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  mulhu        a1, t1, t5
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  nop
                  c.srli       a0, 18
                  c.addi       s2, 16
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  c.and        a3, s0
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  auipc        tp, 400075
                  auipc        tp, 400075
                  or           t4, a3, a3
                  srai         s6, s3, 24
                  c.xor        a5, s0
                  mulh         s9, s8, gp
                  auipc        tp, 400075
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  add          s5, s8, a6
                  c.mv         s8, t5
                  or           t4, a3, a3
                  c.slli       s8, 9
                  c.and        a3, s0
                  nop
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  c.andi       a5, 16
                  c.nop
                  slt          t6, a0, sp
                  c.or         a3, s1
                  c.or         a3, s1
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  and          s6, gp, s0
                  lui          s0, 955933
                  lui          s0, 955933
                  c.srli       a0, 18
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  c.li         t6, 20
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  c.srai       a3, 9
                  c.sub        s0, a4
                  and          s6, gp, s0
                  c.li         t6, 20
                  c.and        a3, s0
                  xori         t5, s5, -792
                  c.or         a3, s1
                  add          s5, s8, a6
                  or           t4, a3, a3
                  slti         s8, ra, -2031
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  mulhsu       s1, s4, sp
                  c.nop
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  c.nop
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  c.and        a3, s0
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  srai         s6, s3, 24
                  mulhsu       s1, s4, sp
                  c.xor        a5, s0
                  c.mv         s8, t5
                  c.add        s7, s6
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  mul          s6, a0, s0
                  rem          a4, s2, a7
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  c.li         t6, 20
                  sltu         s10, s9, s8
                  lui          s0, 955933
                  c.sub        s0, a4
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  addi         zero, t6, 2029
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  c.slli       s8, 9
                  xori         t5, s5, -792
                  divu         s1, s4, a4
                  sltu         s10, s9, s8
                  mulh         s9, s8, gp
                  lui          s0, 955933
                  c.srai       a3, 9
                  and          s6, gp, s0
                  c.and        a3, s0
                  c.add        s7, s6
                  c.lui        s0, 15
                  c.and        a3, s0
                  mul          s6, a0, s0
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  auipc        tp, 400075
                  auipc        tp, 400075
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  addi         zero, t6, 2029
                  srli         a3, s8, 11
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  sltu         s10, s9, s8
                  li           s6, 0x1d556651 #start riscv_int_numeric_corner_stream_19
                  li           tp, 0xffffffff
                  li           t0, 0x4c9d587e
                  li           s11, 0xb01ae01
                  li           s9, 0x375b03a8
                  li           a7, 0x0
                  li           t4, 0x767ba9bd
                  li           t2, 0x235dd0eb
                  li           t1, 0xffffffff
                  li           a2, 0xffffffff
                  lui          s9, 955933
                  nop
                  sub          s9, a7, s6
                  auipc        t2, 400075
                  div          s6, s6, t0
                  auipc        t2, 400075
                  auipc        t2, 400075
                  nop
                  nop
                  divu         s11, a2, a7
                  mulh         s9, s11, t2
                  mulhsu       s11, a2, t1
                  mulh         s9, s11, t2
                  remu         a2, s9, t4
                  remu         a2, s9, t4
                  mulhsu       s11, a2, t1
                  add          t2, s11, tp
                  div          s6, s6, t0
                  remu         a2, s9, t4
                  lui          s9, 955933
                  add          t2, s11, tp
                  rem          t0, t1, t0
                  remu         a2, s9, t4 #end riscv_int_numeric_corner_stream_19
                  c.or         a3, s1
                  c.or         a3, s1
                  c.slli       s8, 9
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  div          a2, t1, a7
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  ori          a2, a1, -1711
                  c.add        s7, s6
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  slt          t6, a0, sp
                  c.lui        s0, 15
                  xori         t5, s5, -792
                  c.add        s7, s6
                  srl          s2, s1, sp
                  c.nop
                  addi         zero, t6, 2029
                  srli         a3, s8, 11
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  c.nop
                  divu         s1, s4, a4
                  c.li         t6, 20
                  c.nop
                  divu         s1, s4, a4
                  c.nop
                  c.xor        a5, s0
                  c.add        s7, s6
                  xor          t5, s1, a7
                  c.or         a3, s1
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  slli         t4, t3, 27
                  srai         s6, s3, 24
                  c.add        s7, s6
                  add          s5, s8, a6
                  c.srai       a3, 9
                  c.xor        a5, s0
                  slt          t6, a0, sp
                  c.nop
                  c.nop
                  c.add        s7, s6
                  sub          s9, s5, s6
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  c.add        s7, s6
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  mulhu        a1, t1, t5
                  sra          a3, s6, t4
                  c.slli       s8, 9
                  c.li         t6, 20
                  or           t4, a3, a3
                  lui          s0, 955933
                  c.and        a3, s0
                  c.sub        s0, a4
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  c.or         a3, s1
                  c.add        s7, s6
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  mulhsu       s1, s4, sp
                  divu         s1, s4, a4
                  slt          t6, a0, sp
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  add          s5, s8, a6
                  c.sub        s0, a4
                  auipc        tp, 400075
                  srli         a3, s8, 11
                  sub          s9, s5, s6
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  lui          s0, 955933
                  c.nop
                  mulhsu       s1, s4, sp
                  mul          s6, a0, s0
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  and          s6, gp, s0
                  c.mv         s8, t5
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  srli         a3, s8, 11
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  slt          t6, a0, sp
                  c.slli       s8, 9
                  slt          t6, a0, sp
                  auipc        tp, 400075
                  c.sub        s0, a4
                  slt          t6, a0, sp
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  divu         s1, s4, a4
                  remu         t0, s7, s1
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  c.slli       s8, 9
                  c.addi       s2, 16
                  slli         t4, t3, 27
                  add          s5, s8, a6
                  c.addi       s2, 16
                  c.nop
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  remu         t0, s7, s1
                  c.and        a3, s0
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  c.and        a3, s0
                  c.and        a3, s0
                  xor          t5, s1, a7
                  divu         s1, s4, a4
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  nop
                  c.mv         s8, t5
                  c.nop
                  c.slli       s8, 9
                  c.mv         s8, t5
                  c.and        a3, s0
                  xori         t5, s5, -792
                  mulh         s9, s8, gp
                  mulhsu       s1, s4, sp
                  andi         s5, tp, -69
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  nop
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  mulh         s9, s8, gp
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  or           t4, a3, a3
                  c.or         a3, s1
                  c.li         t6, 20
                  c.andi       a5, 16
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  c.nop
                  sub          s9, s5, s6
                  mulh         s9, s8, gp
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  c.li         t6, 20
                  c.srai       a3, 9
                  c.srai       a3, 9
                  c.or         a3, s1
                  slt          t6, a0, sp
                  mulhu        a1, t1, t5
                  andi         s5, tp, -69
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  divu         s1, s4, a4
                  c.slli       s8, 9
                  c.nop
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  c.xor        a5, s0
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  c.addi       s2, 16
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  c.xor        a5, s0
                  ori          a2, a1, -1711
                  slti         s8, ra, -2031
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  c.nop
                  c.addi       s2, 16
                  add          s5, s8, a6
                  auipc        tp, 400075
                  c.and        a3, s0
                  divu         s1, s4, a4
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  c.xor        a5, s0
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  c.add        s7, s6
                  div          a2, t1, a7
                  auipc        tp, 400075
                  c.mv         s8, t5
                  or           t4, a3, a3
                  c.lui        s0, 15
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  c.srli       a0, 18
                  c.li         t6, 20
                  c.andi       a5, 16
                  c.li         t6, 20
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  mulhsu       s1, s4, sp
                  srl          s2, s1, sp
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  nop
                  mulh         s9, s8, gp
                  mulh         s9, s8, gp
                  c.mv         s8, t5
                  slti         s8, ra, -2031
                  c.nop
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  c.li         t6, 20
                  div          a2, t1, a7
                  c.nop
                  c.mv         s8, t5
                  andi         s5, tp, -69
                  c.srai       a3, 9
                  c.slli       s8, 9
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  c.andi       a5, 16
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  c.nop
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  c.andi       a5, 16
                  c.sub        s0, a4
                  c.nop
                  li           a6, 0xffffffff #start riscv_int_numeric_corner_stream_27
                  li           t0, 0xffffffff
                  li           ra, 0x0
                  li           tp, 0x0
                  li           a1, 0x534fbe99
                  li           gp, 0x6253567f
                  li           a4, 0x9f7f2969
                  li           s6, 0xffffffff
                  li           t5, 0xffffffff
                  li           s11, 0x76aaa05a
                  lui          s6, 955933
                  mulhsu       s11, a1, tp
                  mul          a1, s11, s11
                  add          t0, s11, ra
                  nop
                  mulhu        tp, a6, ra
                  mulhsu       s11, a1, tp
                  div          a6, a6, gp
                  mulh         s6, s11, t0
                  div          a6, a6, gp
                  div          a6, a6, gp
                  addi         ra, a6, 2029
                  lui          s6, 955933
                  add          t0, s11, ra
                  mulhsu       s11, a1, tp
                  remu         a1, s6, t5
                  div          a6, a6, gp
                  add          t0, s11, ra
                  divu         s11, a1, a4
                  addi         ra, a6, 2029
                  sub          s6, a4, a6
                  remu         a1, s6, t5
                  lui          s6, 955933
                  mul          a1, s11, s11
                  sub          s6, a4, a6
                  divu         s11, a1, a4
                  sub          s6, a4, a6
                  div          a6, a6, gp
                  divu         s11, a1, a4 #end riscv_int_numeric_corner_stream_27
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  c.addi       s2, 16
                  c.li         t6, 20
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  lui          s0, 955933
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  divu         s1, s4, a4
                  c.slli       s8, 9
                  c.andi       a5, 16
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  c.andi       a5, 16
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  mulh         s9, s8, gp
                  c.xor        a5, s0
                  auipc        tp, 400075
                  c.li         t6, 20
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  mulhu        a1, t1, t5
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.li         t6, 20
                  sub          s9, s5, s6
                  mulh         s9, s8, gp
                  c.srai       a3, 9
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  nop
                  mul          s6, a0, s0
                  ori          a2, a1, -1711
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  c.add        s7, s6
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  c.slli       s8, 9
                  c.add        s7, s6
                  mulhsu       s1, s4, sp
                  c.add        s7, s6
                  mulh         s9, s8, gp
                  srl          s2, s1, sp
                  xor          t5, s1, a7
                  mulhu        a1, t1, t5
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  auipc        tp, 400075
                  mul          s6, a0, s0
                  slt          t6, a0, sp
                  div          a2, t1, a7
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  nop
                  slli         t4, t3, 27
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  addi         zero, t6, 2029
                  c.add        s7, s6
                  auipc        tp, 400075
                  lui          s0, 955933
                  sll          a5, s3, s8
                  addi         zero, t6, 2029
                  or           t4, a3, a3
                  c.andi       a5, 16
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  c.xor        a5, s0
                  c.slli       s8, 9
                  lui          s0, 955933
                  divu         s1, s4, a4
                  addi         zero, t6, 2029
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  c.add        s7, s6
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  c.nop
                  c.and        a3, s0
                  c.srai       a3, 9
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  c.add        s7, s6
                  c.li         t6, 20
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  c.slli       s8, 9
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  lui          s0, 955933
                  remu         t0, s7, s1
                  sltiu        zero, gp, -198
                  lui          s0, 955933
                  c.sub        s0, a4
                  lui          s0, 955933
                  nop
                  and          s6, gp, s0
                  c.lui        s0, 15
                  lui          s0, 955933
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  sltu         s10, s9, s8
                  c.slli       s8, 9
                  c.xor        a5, s0
                  c.and        a3, s0
                  mul          s6, a0, s0
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  auipc        tp, 400075
                  c.and        a3, s0
                  mulh         s9, s8, gp
                  c.srli       a0, 18
                  c.andi       a5, 16
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  or           t4, a3, a3
                  and          s6, gp, s0
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  c.nop
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  divu         s1, s4, a4
                  sll          a5, s3, s8
                  srl          s2, s1, sp
                  c.slli       s8, 9
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  c.and        a3, s0
                  c.add        s7, s6
                  xori         t5, s5, -792
                  c.nop
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  c.addi       s2, 16
                  sltu         s10, s9, s8
                  remu         t0, s7, s1
                  c.srli       a0, 18
                  c.srai       a3, 9
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  mulhsu       s1, s4, sp
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  or           t4, a3, a3
                  or           t4, a3, a3
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  or           t4, a3, a3
                  mulhsu       s1, s4, sp
                  sltiu        zero, gp, -198
                  nop
                  c.xor        a5, s0
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  c.mv         s8, t5
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  sltu         s10, s9, s8
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  sltu         s10, s9, s8
                  c.srai       a3, 9
                  c.srli       a0, 18
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  c.srli       a0, 18
                  divu         s1, s4, a4
                  c.mv         s8, t5
                  c.add        s7, s6
                  divu         s1, s4, a4
                  c.mv         s8, t5
                  andi         s5, tp, -69
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  c.nop
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  and          s6, gp, s0
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  srai         s6, s3, 24
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  c.sub        s0, a4
                  srl          s2, s1, sp
                  c.and        a3, s0
                  c.addi       s2, 16
                  lui          s0, 955933
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  remu         t0, s7, s1
                  c.addi       s2, 16
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  mulhsu       s1, s4, sp
                  srl          s2, s1, sp
                  c.slli       s8, 9
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  c.li         t6, 20
                  mulhsu       s1, s4, sp
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  c.nop
                  c.or         a3, s1
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  srli         a3, s8, 11
                  c.andi       a5, 16
                  ori          a2, a1, -1711
                  srl          s2, s1, sp
                  c.and        a3, s0
                  xori         t5, s5, -792
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  addi         zero, t6, 2029
                  c.sub        s0, a4
                  c.mv         s8, t5
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  c.li         t6, 20
                  c.nop
                  remu         t0, s7, s1
                  lui          s0, 955933
                  c.xor        a5, s0
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  c.andi       a5, 16
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  nop
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  or           t4, a3, a3
                  c.srai       a3, 9
                  or           t4, a3, a3
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  auipc        tp, 400075
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  nop
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  lui          s0, 955933
                  srai         s6, s3, 24
                  c.and        a3, s0
                  nop
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  xor          t5, s1, a7
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  and          s6, gp, s0
                  c.add        s7, s6
                  c.addi       s2, 16
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  add          s5, s8, a6
                  c.srli       a0, 18
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  c.slli       s8, 9
                  c.or         a3, s1
                  auipc        tp, 400075
                  sub          s9, s5, s6
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  c.slli       s8, 9
                  ori          a2, a1, -1711
                  c.nop
                  ori          a2, a1, -1711
                  ori          a2, a1, -1711
                  srl          s2, s1, sp
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  c.srli       a0, 18
                  c.andi       a5, 16
                  c.andi       a5, 16
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  divu         s1, s4, a4
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  nop
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  sltiu        zero, gp, -198
                  c.li         t6, 20
                  c.lui        s0, 15
                  c.and        a3, s0
                  auipc        tp, 400075
                  c.and        a3, s0
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  c.slli       s8, 9
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  rem          a4, s2, a7
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  lui          s0, 955933
                  sub          s9, s5, s6
                  c.srai       a3, 9
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  c.sub        s0, a4
                  nop
                  nop
                  auipc        tp, 400075
                  c.or         a3, s1
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  c.add        s7, s6
                  srai         s6, s3, 24
                  lui          s0, 955933
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  c.nop
                  div          a2, t1, a7
                  sltu         s10, s9, s8
                  nop
                  sll          a5, s3, s8
                  and          s6, gp, s0
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  c.and        a3, s0
                  or           t4, a3, a3
                  c.xor        a5, s0
                  c.or         a3, s1
                  c.add        s7, s6
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  c.srai       a3, 9
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  c.and        a3, s0
                  or           t4, a3, a3
                  c.slli       s8, 9
                  auipc        tp, 400075
                  c.add        s7, s6
                  c.add        s7, s6
                  slli         t4, t3, 27
                  c.mv         s8, t5
                  and          s6, gp, s0
                  c.srli       a0, 18
                  mul          s6, a0, s0
                  c.slli       s8, 9
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  rem          a4, s2, a7
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  c.or         a3, s1
                  c.li         t6, 20
                  c.addi       s2, 16
                  c.slli       s8, 9
                  mul          s6, a0, s0
                  lui          s0, 955933
                  lui          s0, 955933
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  sll          a5, s3, s8
                  srl          s2, s1, sp
                  slti         s8, ra, -2031
                  andi         s5, tp, -69
                  c.slli       s8, 9
                  sltiu        zero, gp, -198
                  c.addi       s2, 16
                  c.add        s7, s6
                  c.add        s7, s6
                  divu         s1, s4, a4
                  c.addi       s2, 16
                  sltiu        zero, gp, -198
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  div          a2, t1, a7
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  slt          t6, a0, sp
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  c.nop
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  mulhsu       s1, s4, sp
                  andi         s5, tp, -69
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  c.mv         s8, t5
                  or           t4, a3, a3
                  c.xor        a5, s0
                  c.slli       s8, 9
                  c.li         t6, 20
                  c.addi       s2, 16
                  c.srai       a3, 9
                  mulhsu       s1, s4, sp
                  c.li         t6, 20
                  nop
                  srai         s6, s3, 24
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  srai         s6, s3, 24
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  or           t4, a3, a3
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  c.sub        s0, a4
                  c.add        s7, s6
                  auipc        tp, 400075
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  c.srli       a0, 18
                  mul          s6, a0, s0
                  c.add        s7, s6
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  c.li         t6, 20
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  c.or         a3, s1
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  ori          a2, a1, -1711
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  c.slli       s8, 9
                  andi         s5, tp, -69
                  c.or         a3, s1
                  remu         t0, s7, s1
                  c.andi       a5, 16
                  c.sub        s0, a4
                  c.xor        a5, s0
                  c.sub        s0, a4
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  add          s5, s8, a6
                  divu         s1, s4, a4
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  c.li         t6, 20
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  andi         s5, tp, -69
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  c.add        s7, s6
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  li           gp, 0xffffffff #start riscv_int_numeric_corner_stream_1
                  li           s3, 0xffffffff
                  li           t0, 0x9a1d3c05
                  li           s6, 0x80000000
                  li           s0, 0x15d566c9
                  li           s11, 0x65bde094
                  li           t5, 0x80000000
                  li           s7, 0xba2eef48
                  li           t6, 0x0
                  li           s10, 0x0
                  add          s3, t5, gp
                  rem          t0, s0, t0
                  addi         gp, s10, 2029
                  divu         t5, s6, s7
                  add          s3, t5, gp
                  mul          s6, t5, t5
                  lui          s11, 955933
                  mulh         s11, t5, s3
                  sub          s11, s7, s10
                  div          s10, s10, t0
                  divu         t5, s6, s7
                  addi         gp, s10, 2029
                  div          s10, s10, t0
                  mulhu        s0, s10, gp
                  rem          t0, s0, t0 #end riscv_int_numeric_corner_stream_1
                  c.slli       s8, 9
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  srai         s6, s3, 24
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  xor          t5, s1, a7
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  add          s5, s8, a6
                  c.nop
                  c.li         t6, 20
                  c.mv         s8, t5
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.or         a3, s1
                  c.and        a3, s0
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  c.nop
                  and          s6, gp, s0
                  lui          s0, 955933
                  xori         t5, s5, -792
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  sltu         s10, s9, s8
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  nop
                  sub          s9, s5, s6
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  nop
                  xor          t5, s1, a7
                  c.and        a3, s0
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  srai         s6, s3, 24
                  add          s5, s8, a6
                  lui          s0, 955933
                  c.srai       a3, 9
                  xor          t5, s1, a7
                  divu         s1, s4, a4
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  andi         s5, tp, -69
                  c.mv         s8, t5
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  c.xor        a5, s0
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  div          a2, t1, a7
                  divu         s1, s4, a4
                  sll          a5, s3, s8
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  c.or         a3, s1
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  sltu         s10, s9, s8
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  nop
                  c.slli       s8, 9
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  slt          t6, a0, sp
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  div          a2, t1, a7
                  nop
                  mulhsu       s1, s4, sp
                  c.lui        s0, 15
                  slti         s8, ra, -2031
                  sll          a5, s3, s8
                  divu         s1, s4, a4
                  nop
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  li           t5, 0xffffffff #start riscv_int_numeric_corner_stream_37
                  li           t6, 0x0
                  li           a7, 0xffffffff
                  li           s5, 0xffffffff
                  li           s2, 0x80000000
                  li           s6, 0xffffffff
                  li           a6, 0x1de1be2f
                  li           ra, 0xffffffff
                  li           a0, 0xe9db060e
                  li           t2, 0xffffffff
                  mulhsu       t5, a7, a0
                  mul          a7, t5, t5
                  remu         a7, s6, t6
                  remu         a7, s6, t6
                  rem          t2, a0, t2
                  mulhsu       t5, a7, a0
                  remu         a7, s6, t6
                  lui          s6, 955933
                  add          a6, t5, ra
                  mulhsu       t5, a7, a0
                  mul          a7, t5, t5
                  nop
                  mulh         s6, t5, a6
                  remu         a7, s6, t6
                  lui          s6, 955933
                  remu         a7, s6, t6
                  rem          t2, a0, t2
                  rem          t2, a0, t2
                  add          a6, t5, ra
                  addi         ra, s5, 2029
                  mulh         s6, t5, a6
                  divu         t5, a7, s2
                  mulh         s6, t5, a6
                  lui          s6, 955933
                  remu         a7, s6, t6
                  nop
                  mulh         s6, t5, a6
                  remu         a7, s6, t6 #end riscv_int_numeric_corner_stream_37
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  nop
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  divu         s1, s4, a4
                  c.addi       s2, 16
                  add          s5, s8, a6
                  auipc        tp, 400075
                  c.srli       a0, 18
                  nop
                  lui          s0, 955933
                  sra          a3, s6, t4
                  c.slli       s8, 9
                  nop
                  c.or         a3, s1
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  c.nop
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  c.nop
                  c.srli       a0, 18
                  c.add        s7, s6
                  or           t4, a3, a3
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  c.addi       s2, 16
                  sra          a3, s6, t4
                  lui          s0, 955933
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  srai         s6, s3, 24
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  add          s5, s8, a6
                  c.slli       s8, 9
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  mulhu        a1, t1, t5
                  mul          s6, a0, s0
                  c.or         a3, s1
                  sltiu        zero, gp, -198
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  sll          a5, s3, s8
                  c.nop
                  lui          s0, 955933
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  add          s5, s8, a6
                  andi         s5, tp, -69
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  c.slli       s8, 9
                  slli         t4, t3, 27
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  c.addi       s2, 16
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  c.srli       a0, 18
                  c.li         t6, 20
                  and          s6, gp, s0
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  srai         s6, s3, 24
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  slt          t6, a0, sp
                  c.add        s7, s6
                  xori         t5, s5, -792
                  div          a2, t1, a7
                  lui          s0, 955933
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  lui          s0, 955933
                  xor          t5, s1, a7
                  divu         s1, s4, a4
                  auipc        tp, 400075
                  c.add        s7, s6
                  c.nop
                  add          s5, s8, a6
                  auipc        tp, 400075
                  nop
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  c.or         a3, s1
                  c.slli       s8, 9
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  mulhsu       s1, s4, sp
                  andi         s5, tp, -69
                  nop
                  c.and        a3, s0
                  andi         s5, tp, -69
                  c.or         a3, s1
                  c.lui        s0, 15
                  nop
                  or           t4, a3, a3
                  c.slli       s8, 9
                  sltiu        zero, gp, -198
                  lui          s0, 955933
                  c.add        s7, s6
                  nop
                  divu         s1, s4, a4
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  div          a2, t1, a7
                  andi         s5, tp, -69
                  nop
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  nop
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  sltu         s10, s9, s8
                  auipc        tp, 400075
                  xor          t5, s1, a7
                  c.add        s7, s6
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  div          a2, t1, a7
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  nop
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  sra          a3, s6, t4
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.li         t6, 20
                  lui          s0, 955933
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  c.li         t6, 20
                  c.li         t6, 20
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  and          s6, gp, s0
                  or           t4, a3, a3
                  c.and        a3, s0
                  c.and        a3, s0
                  mul          s6, a0, s0
                  xor          t5, s1, a7
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  sra          a3, s6, t4
                  div          a2, t1, a7
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  mulhsu       s1, s4, sp
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  slli         t4, t3, 27
                  div          a2, t1, a7
                  srli         a3, s8, 11
                  addi         zero, t6, 2029
                  mulhu        a1, t1, t5
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  or           t4, a3, a3
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  c.slli       s8, 9
                  div          a2, t1, a7
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  andi         s5, tp, -69
                  sltu         s10, s9, s8
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  c.or         a3, s1
                  mulh         s9, s8, gp
                  c.xor        a5, s0
                  c.xor        a5, s0
                  auipc        tp, 400075
                  and          s6, gp, s0
                  c.lui        s0, 15
                  auipc        tp, 400075
                  auipc        tp, 400075
                  c.srai       a3, 9
                  c.srai       a3, 9
                  c.lui        s0, 15
                  divu         s1, s4, a4
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  c.or         a3, s1
                  c.and        a3, s0
                  c.xor        a5, s0
                  c.slli       s8, 9
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  c.slli       s8, 9
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  or           t4, a3, a3
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  c.and        a3, s0
                  mul          s6, a0, s0
                  xori         t5, s5, -792
                  c.li         t6, 20
                  nop
                  c.add        s7, s6
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  c.andi       a5, 16
                  auipc        tp, 400075
                  c.lui        s0, 15
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  c.slli       s8, 9
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  c.xor        a5, s0
                  c.srli       a0, 18
                  c.nop
                  c.or         a3, s1
                  or           t4, a3, a3
                  c.lui        s0, 15
                  c.li         t6, 20
                  xor          t5, s1, a7
                  c.li         t6, 20
                  div          a2, t1, a7
                  c.andi       a5, 16
                  andi         s5, tp, -69
                  slt          t6, a0, sp
                  c.nop
                  add          s5, s8, a6
                  c.addi       s2, 16
                  c.or         a3, s1
                  slli         t4, t3, 27
                  srai         s6, s3, 24
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  c.and        a3, s0
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  c.lui        s0, 15
                  div          a2, t1, a7
                  mulhsu       s1, s4, sp
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  nop
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  auipc        tp, 400075
                  lui          s0, 955933
                  srl          s2, s1, sp
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  slt          t6, a0, sp
                  c.slli       s8, 9
                  rem          a4, s2, a7
                  c.li         t6, 20
                  slli         t4, t3, 27
                  c.li         t6, 20
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  c.andi       a5, 16
                  remu         t0, s7, s1
                  nop
                  c.andi       a5, 16
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  slli         t4, t3, 27
                  slti         s8, ra, -2031
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  lui          s0, 955933
                  auipc        tp, 400075
                  slli         t4, t3, 27
                  c.add        s7, s6
                  c.or         a3, s1
                  c.lui        s0, 15
                  c.and        a3, s0
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  c.or         a3, s1
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  c.sub        s0, a4
                  sub          s9, s5, s6
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  c.or         a3, s1
                  slt          t6, a0, sp
                  slli         t4, t3, 27
                  add          s5, s8, a6
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  mul          s6, a0, s0
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  srai         s6, s3, 24
                  mulhsu       s1, s4, sp
                  c.li         t6, 20
                  c.sub        s0, a4
                  c.srai       a3, 9
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  rem          a4, s2, a7
                  mulhsu       s1, s4, sp
                  mulhsu       s1, s4, sp
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.andi       a5, 16
                  c.andi       a5, 16
                  c.sub        s0, a4
                  srl          s2, s1, sp
                  c.sub        s0, a4
                  c.mv         s8, t5
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  srl          s2, s1, sp
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  c.add        s7, s6
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  c.nop
                  addi         zero, t6, 2029
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  divu         s1, s4, a4
                  and          s6, gp, s0
                  and          s6, gp, s0
                  srli         a3, s8, 11
                  c.nop
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  lui          s0, 955933
                  c.or         a3, s1
                  andi         s5, tp, -69
                  c.nop
                  c.srli       a0, 18
                  c.addi       s2, 16
                  c.slli       s8, 9
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  div          a2, t1, a7
                  mul          s6, a0, s0
                  c.or         a3, s1
                  sub          s9, s5, s6
                  c.li         t6, 20
                  mulhsu       s1, s4, sp
                  c.xor        a5, s0
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  c.li         t6, 20
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  c.srai       a3, 9
                  c.nop
                  c.lui        s0, 15
                  c.lui        s0, 15
                  slti         s8, ra, -2031
                  c.slli       s8, 9
                  c.sub        s0, a4
                  c.add        s7, s6
                  slti         s8, ra, -2031
                  c.sub        s0, a4
                  lui          s0, 955933
                  c.lui        s0, 15
                  lui          s0, 955933
                  sltiu        zero, gp, -198
                  sltu         s10, s9, s8
                  rem          a4, s2, a7
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  slli         t4, t3, 27
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  c.nop
                  c.nop
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  or           t4, a3, a3
                  c.srai       a3, 9
                  and          s6, gp, s0
                  add          s5, s8, a6
                  nop
                  slti         s8, ra, -2031
                  c.li         t6, 20
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  sub          s9, s5, s6
                  sltiu        zero, gp, -198
                  mulhu        a1, t1, t5
                  c.xor        a5, s0
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  sra          a3, s6, t4
                  sltu         s10, s9, s8
                  mul          s6, a0, s0
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  div          a2, t1, a7
                  c.lui        s0, 15
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  slli         t4, t3, 27
                  c.and        a3, s0
                  xor          t5, s1, a7
                  c.and        a3, s0
                  srli         a3, s8, 11
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  c.li         t6, 20
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  c.sub        s0, a4
                  srl          s2, s1, sp
                  slti         s8, ra, -2031
                  c.or         a3, s1
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  c.and        a3, s0
                  mul          s6, a0, s0
                  auipc        tp, 400075
                  lui          s0, 955933
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  c.nop
                  c.sub        s0, a4
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  or           t4, a3, a3
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  srl          s2, s1, sp
                  c.nop
                  c.nop
                  xor          t5, s1, a7
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  c.and        a3, s0
                  c.nop
                  auipc        tp, 400075
                  ori          a2, a1, -1711
                  c.xor        a5, s0
                  c.xor        a5, s0
                  c.sub        s0, a4
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  c.nop
                  c.lui        s0, 15
                  lui          s0, 955933
                  andi         s5, tp, -69
                  c.or         a3, s1
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  c.and        a3, s0
                  or           t4, a3, a3
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  c.add        s7, s6
                  c.add        s7, s6
                  mulh         s9, s8, gp
                  sltu         s10, s9, s8
                  mulh         s9, s8, gp
                  c.srai       a3, 9
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  c.srai       a3, 9
                  c.add        s7, s6
                  xori         t5, s5, -792
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  c.nop
                  c.nop
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  c.sub        s0, a4
                  c.li         t6, 20
                  slti         s8, ra, -2031
                  and          s6, gp, s0
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  c.add        s7, s6
                  c.addi       s2, 16
                  ori          a2, a1, -1711
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  c.slli       s8, 9
                  xori         t5, s5, -792
                  divu         s1, s4, a4
                  lui          s0, 955933
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  c.slli       s8, 9
                  c.add        s7, s6
                  and          s6, gp, s0
                  c.slli       s8, 9
                  c.li         t6, 20
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  srli         a3, s8, 11
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  c.srai       a3, 9
                  c.nop
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  srl          s2, s1, sp
                  nop
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  and          s6, gp, s0
                  srai         s6, s3, 24
                  mulhu        a1, t1, t5
                  c.nop
                  divu         s1, s4, a4
                  c.add        s7, s6
                  slti         s8, ra, -2031
                  c.nop
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  c.add        s7, s6
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  and          s6, gp, s0
                  or           t4, a3, a3
                  sltiu        zero, gp, -198
                  ori          a2, a1, -1711
                  or           t4, a3, a3
                  and          s6, gp, s0
                  c.srai       a3, 9
                  lui          s0, 955933
                  xor          t5, s1, a7
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  sltu         s10, s9, s8
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  nop
                  addi         zero, t6, 2029
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  c.addi       s2, 16
                  xori         t5, s5, -792
                  c.srai       a3, 9
                  c.and        a3, s0
                  xor          t5, s1, a7
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  mulhsu       s1, s4, sp
                  auipc        tp, 400075
                  add          s5, s8, a6
                  auipc        tp, 400075
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  sltu         s10, s9, s8
                  and          s6, gp, s0
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  srai         s6, s3, 24
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  c.add        s7, s6
                  c.mv         s8, t5
                  nop
                  c.mv         s8, t5
                  c.xor        a5, s0
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  nop
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  c.srai       a3, 9
                  srai         s6, s3, 24
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  c.sub        s0, a4
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  c.nop
                  c.or         a3, s1
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  auipc        tp, 400075
                  sra          a3, s6, t4
                  sltu         s10, s9, s8
                  c.addi       s2, 16
                  c.slli       s8, 9
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  c.add        s7, s6
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  mulhsu       s1, s4, sp
                  mulhu        a1, t1, t5
                  sltu         s10, s9, s8
                  add          s5, s8, a6
                  or           t4, a3, a3
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  sub          s9, s5, s6
                  mulhsu       s1, s4, sp
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  div          a2, t1, a7
                  lui          s0, 955933
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  c.or         a3, s1
                  c.xor        a5, s0
                  c.sub        s0, a4
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  c.slli       s8, 9
                  div          a2, t1, a7
                  lui          s0, 955933
                  mul          s6, a0, s0
                  sll          a5, s3, s8
                  slti         s8, ra, -2031
                  c.nop
                  c.and        a3, s0
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  c.add        s7, s6
                  c.lui        s0, 15
                  rem          a4, s2, a7
                  c.nop
                  mul          s6, a0, s0
                  srl          s2, s1, sp
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  c.slli       s8, 9
                  remu         t0, s7, s1
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  c.add        s7, s6
                  c.or         a3, s1
                  c.andi       a5, 16
                  div          a2, t1, a7
                  c.srai       a3, 9
                  c.mv         s8, t5
                  and          s6, gp, s0
                  c.lui        s0, 15
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.slli       s8, 9
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  c.li         t6, 20
                  c.mv         s8, t5
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  andi         s5, tp, -69
                  c.nop
                  rem          a4, s2, a7
                  or           t4, a3, a3
                  c.nop
                  c.li         t6, 20
                  srai         s6, s3, 24
                  slli         t4, t3, 27
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  add          s5, s8, a6
                  and          s6, gp, s0
                  add          s5, s8, a6
                  c.and        a3, s0
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  div          a2, t1, a7
                  or           t4, a3, a3
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  lui          s0, 955933
                  c.mv         s8, t5
                  c.lui        s0, 15
                  rem          a4, s2, a7
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  c.slli       s8, 9
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  c.xor        a5, s0
                  c.xor        a5, s0
                  auipc        tp, 400075
                  nop
                  srai         s6, s3, 24
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  c.slli       s8, 9
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  sll          a5, s3, s8
                  nop
                  c.srai       a3, 9
                  divu         s1, s4, a4
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  lui          s0, 955933
                  div          a2, t1, a7
                  c.andi       a5, 16
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  c.slli       s8, 9
                  c.srli       a0, 18
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  remu         t0, s7, s1
                  c.and        a3, s0
                  c.srai       a3, 9
                  add          s5, s8, a6
                  and          s6, gp, s0
                  li           s1, 0xffffffff #start riscv_int_numeric_corner_stream_12
                  li           t1, 0xffffffff
                  li           s5, 0x45164878
                  li           s8, 0xffffffff
                  li           a4, 0x0
                  li           t5, 0x39b0204
                  li           s9, 0x0
                  li           s0, 0x969ee236
                  li           ra, 0x80000000
                  li           s2, 0x0
                  mulhsu       s9, a4, s0
                  mulh         s8, s9, s1
                  add          s1, s9, ra
                  mul          a4, s9, s9
                  nop
                  addi         ra, s5, 2029
                  mulh         s8, s9, s1
                  remu         a4, s8, t5
                  sub          s8, s2, s5
                  mulhu        s0, s5, ra
                  sub          s8, s2, s5
                  mulh         s8, s9, s1
                  nop
                  mulh         s8, s9, s1
                  divu         s9, a4, s2
                  add          s1, s9, ra
                  remu         a4, s8, t5
                  remu         a4, s8, t5
                  auipc        s1, 400075
                  mul          a4, s9, s9 #end riscv_int_numeric_corner_stream_12
                  lui          s0, 955933
                  c.nop
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  mul          s6, a0, s0
                  c.lui        s0, 15
                  mulh         s9, s8, gp
                  srl          s2, s1, sp
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  nop
                  add          s5, s8, a6
                  and          s6, gp, s0
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  xori         t5, s5, -792
                  nop
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  sll          a5, s3, s8
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  srl          s2, s1, sp
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  c.add        s7, s6
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  c.nop
                  c.srai       a3, 9
                  c.li         t6, 20
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  c.add        s7, s6
                  auipc        tp, 400075
                  nop
                  mulh         s9, s8, gp
                  lui          s0, 955933
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  c.nop
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  c.srli       a0, 18
                  c.li         t6, 20
                  xor          t5, s1, a7
                  andi         s5, tp, -69
                  c.nop
                  sub          s9, s5, s6
                  remu         t0, s7, s1
                  addi         zero, t6, 2029
                  mulhu        a1, t1, t5
                  nop
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  c.add        s7, s6
                  c.or         a3, s1
                  xor          t5, s1, a7
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  div          a2, t1, a7
                  c.srli       a0, 18
                  c.add        s7, s6
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  c.nop
                  slli         t4, t3, 27
                  lui          s0, 955933
                  auipc        tp, 400075
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  nop
                  c.li         t6, 20
                  srli         a3, s8, 11
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  or           t4, a3, a3
                  c.sub        s0, a4
                  add          s5, s8, a6
                  srai         s6, s3, 24
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  lui          s0, 955933
                  or           t4, a3, a3
                  c.addi       s2, 16
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  rem          a4, s2, a7
                  c.srli       a0, 18
                  or           t4, a3, a3
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.or         a3, s1
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  c.sub        s0, a4
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  div          a2, t1, a7
                  add          s5, s8, a6
                  c.lui        s0, 15
                  c.and        a3, s0
                  c.add        s7, s6
                  c.add        s7, s6
                  or           t4, a3, a3
                  auipc        tp, 400075
                  auipc        tp, 400075
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  c.slli       s8, 9
                  c.and        a3, s0
                  slti         s8, ra, -2031
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  add          s5, s8, a6
                  addi         zero, t6, 2029
                  sra          a3, s6, t4
                  slt          t6, a0, sp
                  c.or         a3, s1
                  slt          t6, a0, sp
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  nop
                  c.add        s7, s6
                  xori         t5, s5, -792
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  mulhu        a1, t1, t5
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  c.nop
                  mulhu        a1, t1, t5
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  c.lui        s0, 15
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  c.add        s7, s6
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  c.add        s7, s6
                  divu         s1, s4, a4
                  c.nop
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  c.nop
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  nop
                  div          a2, t1, a7
                  srai         s6, s3, 24
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  mul          s6, a0, s0
                  c.mv         s8, t5
                  andi         s5, tp, -69
                  and          s6, gp, s0
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  slt          t6, a0, sp
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  c.lui        s0, 15
                  auipc        tp, 400075
                  c.li         t6, 20
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  c.nop
                  xor          t5, s1, a7
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  c.add        s7, s6
                  c.and        a3, s0
                  c.add        s7, s6
                  c.xor        a5, s0
                  c.and        a3, s0
                  remu         t0, s7, s1
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  ori          a2, a1, -1711
                  divu         s1, s4, a4
                  c.nop
                  c.mv         s8, t5
                  c.andi       a5, 16
                  remu         t0, s7, s1
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  c.andi       a5, 16
                  or           t4, a3, a3
                  mulhsu       s1, s4, sp
                  mul          s6, a0, s0
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.add        s7, s6
                  c.andi       a5, 16
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  c.srli       a0, 18
                  c.sub        s0, a4
                  c.and        a3, s0
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  c.nop
                  c.nop
                  lui          s0, 955933
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  divu         s1, s4, a4
                  c.li         t6, 20
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  nop
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  div          a2, t1, a7
                  c.sub        s0, a4
                  c.nop
                  nop
                  c.nop
                  c.xor        a5, s0
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  xor          t5, s1, a7
                  c.srai       a3, 9
                  srai         s6, s3, 24
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  or           t4, a3, a3
                  or           t4, a3, a3
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  c.lui        s0, 15
                  add          s5, s8, a6
                  sltiu        zero, gp, -198
                  nop
                  c.sub        s0, a4
                  and          s6, gp, s0
                  c.andi       a5, 16
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  c.sub        s0, a4
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  xor          t5, s1, a7
                  lui          s0, 955933
                  div          a2, t1, a7
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  c.sub        s0, a4
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  lui          s0, 955933
                  c.xor        a5, s0
                  c.add        s7, s6
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  nop
                  sltiu        zero, gp, -198
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  c.nop
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  c.add        s7, s6
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  mulhsu       s1, s4, sp
                  c.and        a3, s0
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  c.and        a3, s0
                  auipc        tp, 400075
                  c.sub        s0, a4
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  c.andi       a5, 16
                  add          s5, s8, a6
                  andi         s5, tp, -69
                  nop
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  lui          s0, 955933
                  add          s5, s8, a6
                  c.slli       s8, 9
                  c.andi       a5, 16
                  nop
                  sub          s9, s5, s6
                  sra          a3, s6, t4
                  div          a2, t1, a7
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  or           t4, a3, a3
                  xor          t5, s1, a7
                  slti         s8, ra, -2031
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  c.or         a3, s1
                  nop
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  auipc        tp, 400075
                  lui          s0, 955933
                  lui          s0, 955933
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  c.and        a3, s0
                  c.srli       a0, 18
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  add          s5, s8, a6
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  or           t4, a3, a3
                  and          s6, gp, s0
                  c.add        s7, s6
                  and          s6, gp, s0
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  nop
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  c.andi       a5, 16
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  c.and        a3, s0
                  ori          a2, a1, -1711
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  mulh         s9, s8, gp
                  nop
                  div          a2, t1, a7
                  c.addi       s2, 16
                  auipc        tp, 400075
                  mulh         s9, s8, gp
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  c.mv         s8, t5
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  c.and        a3, s0
                  srl          s2, s1, sp
                  mulhsu       s1, s4, sp
                  srl          s2, s1, sp
                  xor          t5, s1, a7
                  slti         s8, ra, -2031
                  c.nop
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  lui          s0, 955933
                  sltu         s10, s9, s8
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  c.sub        s0, a4
                  nop
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  ori          a2, a1, -1711
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  c.slli       s8, 9
                  mulhsu       s1, s4, sp
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  nop
                  slti         s8, ra, -2031
                  c.and        a3, s0
                  slli         t4, t3, 27
                  nop
                  sltu         s10, s9, s8
                  srl          s2, s1, sp
                  mulhu        a1, t1, t5
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  slli         t4, t3, 27
                  nop
                  c.mv         s8, t5
                  auipc        tp, 400075
                  c.add        s7, s6
                  xori         t5, s5, -792
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  xori         t5, s5, -792
                  c.li         t6, 20
                  remu         t0, s7, s1
                  div          a2, t1, a7
                  c.or         a3, s1
                  c.sub        s0, a4
                  c.nop
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  or           t4, a3, a3
                  c.sub        s0, a4
                  c.srai       a3, 9
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  div          a2, t1, a7
                  nop
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  c.or         a3, s1
                  c.add        s7, s6
                  c.srli       a0, 18
                  slt          t6, a0, sp
                  mulhsu       s1, s4, sp
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  slt          t6, a0, sp
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  mulh         s9, s8, gp
                  c.slli       s8, 9
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  nop
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  mul          s6, a0, s0
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  c.li         t6, 20
                  srai         s6, s3, 24
                  mulh         s9, s8, gp
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  c.sub        s0, a4
                  c.sub        s0, a4
                  c.sub        s0, a4
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  remu         t0, s7, s1
                  remu         t0, s7, s1
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  auipc        tp, 400075
                  c.srai       a3, 9
                  c.srli       a0, 18
                  c.nop
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  or           t4, a3, a3
                  c.addi       s2, 16
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  nop
                  c.and        a3, s0
                  c.add        s7, s6
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  c.nop
                  c.nop
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  c.and        a3, s0
                  c.sub        s0, a4
                  divu         s1, s4, a4
                  lui          s0, 955933
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  c.andi       a5, 16
                  c.nop
                  srai         s6, s3, 24
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  sra          a3, s6, t4
                  ori          a2, a1, -1711
                  c.addi       s2, 16
                  c.srli       a0, 18
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  nop
                  add          s5, s8, a6
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  c.lui        s0, 15
                  c.and        a3, s0
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  c.andi       a5, 16
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  mulh         s9, s8, gp
                  rem          a4, s2, a7
                  slli         t4, t3, 27
                  slt          t6, a0, sp
                  mulhsu       s1, s4, sp
                  mul          s6, a0, s0
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  c.or         a3, s1
                  srli         a3, s8, 11
                  c.addi       s2, 16
                  c.srai       a3, 9
                  lui          s0, 955933
                  and          s6, gp, s0
                  c.sub        s0, a4
                  c.sub        s0, a4
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  c.and        a3, s0
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  c.lui        s0, 15
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  rem          a4, s2, a7
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  auipc        tp, 400075
                  c.li         t6, 20
                  div          a2, t1, a7
                  c.add        s7, s6
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  nop
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  add          s5, s8, a6
                  c.srai       a3, 9
                  sra          a3, s6, t4
                  sll          a5, s3, s8
                  divu         s1, s4, a4
                  c.andi       a5, 16
                  c.mv         s8, t5
                  addi         zero, t6, 2029
                  slti         s8, ra, -2031
                  auipc        tp, 400075
                  lui          s0, 955933
                  auipc        tp, 400075
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  or           t4, a3, a3
                  c.nop
                  c.nop
                  slti         s8, ra, -2031
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  c.xor        a5, s0
                  lui          s0, 955933
                  sll          a5, s3, s8
                  c.nop
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  remu         t0, s7, s1
                  c.add        s7, s6
                  c.li         t6, 20
                  c.and        a3, s0
                  rem          a4, s2, a7
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  nop
                  srai         s6, s3, 24
                  c.and        a3, s0
                  nop
                  c.srai       a3, 9
                  c.xor        a5, s0
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  srl          s2, s1, sp
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  lui          s0, 955933
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  c.or         a3, s1
                  auipc        tp, 400075
                  c.add        s7, s6
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  c.srai       a3, 9
                  and          s6, gp, s0
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  c.addi       s2, 16
                  lui          s0, 955933
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  sltiu        zero, gp, -198
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  c.or         a3, s1
                  slli         t4, t3, 27
                  slt          t6, a0, sp
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  c.and        a3, s0
                  c.srli       a0, 18
                  c.lui        s0, 15
                  sub          s9, s5, s6
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  c.add        s7, s6
                  sltu         s10, s9, s8
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  c.srai       a3, 9
                  c.add        s7, s6
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  c.add        s7, s6
                  c.or         a3, s1
                  c.li         t6, 20
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  c.nop
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  div          a2, t1, a7
                  c.li         t6, 20
                  xor          t5, s1, a7
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  c.and        a3, s0
                  c.addi       s2, 16
                  c.andi       a5, 16
                  c.slli       s8, 9
                  c.lui        s0, 15
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  c.nop
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  srai         s6, s3, 24
                  add          s5, s8, a6
                  add          s5, s8, a6
                  c.srli       a0, 18
                  xori         t5, s5, -792
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  and          s6, gp, s0
                  c.sub        s0, a4
                  c.add        s7, s6
                  srli         a3, s8, 11
                  nop
                  c.slli       s8, 9
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  c.srli       a0, 18
                  c.lui        s0, 15
                  c.or         a3, s1
                  c.lui        s0, 15
                  c.srli       a0, 18
                  c.slli       s8, 9
                  c.addi       s2, 16
                  and          s6, gp, s0
                  c.nop
                  c.sub        s0, a4
                  sra          a3, s6, t4
                  c.slli       s8, 9
                  c.srli       a0, 18
                  c.mv         s8, t5
                  sltiu        zero, gp, -198
                  divu         s1, s4, a4
                  c.sub        s0, a4
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  c.add        s7, s6
                  c.mv         s8, t5
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  or           t4, a3, a3
                  c.add        s7, s6
                  c.li         t6, 20
                  srai         s6, s3, 24
                  nop
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  slt          t6, a0, sp
                  c.mv         s8, t5
                  c.sub        s0, a4
                  c.lui        s0, 15
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  auipc        tp, 400075
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  c.lui        s0, 15
                  div          a2, t1, a7
                  c.mv         s8, t5
                  c.addi       s2, 16
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  rem          a4, s2, a7
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  remu         t0, s7, s1
                  c.nop
                  c.or         a3, s1
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  mulh         s9, s8, gp
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  c.and        a3, s0
                  c.andi       a5, 16
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  mul          s6, a0, s0
                  c.sub        s0, a4
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  c.add        s7, s6
                  srli         a3, s8, 11
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  sltu         s10, s9, s8
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  c.lui        s0, 15
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  nop
                  c.addi       s2, 16
                  div          a2, t1, a7
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  div          a2, t1, a7
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  divu         s1, s4, a4
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  auipc        tp, 400075
                  div          a2, t1, a7
                  xor          t5, s1, a7
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  c.li         t6, 20
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  ori          a2, a1, -1711
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  nop
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  mul          s6, a0, s0
                  and          s6, gp, s0
                  c.or         a3, s1
                  xor          t5, s1, a7
                  c.li         t6, 20
                  c.nop
                  auipc        tp, 400075
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  mulh         s9, s8, gp
                  nop
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  sub          s9, s5, s6
                  srl          s2, s1, sp
                  c.andi       a5, 16
                  or           t4, a3, a3
                  sltu         s10, s9, s8
                  and          s6, gp, s0
                  div          a2, t1, a7
                  and          s6, gp, s0
                  remu         t0, s7, s1
                  c.or         a3, s1
                  remu         t0, s7, s1
                  c.srli       a0, 18
                  and          s6, gp, s0
                  c.nop
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.and        a3, s0
                  sltu         s10, s9, s8
                  nop
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  and          s6, gp, s0
                  c.add        s7, s6
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  c.nop
                  c.add        s7, s6
                  add          s5, s8, a6
                  c.add        s7, s6
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  nop
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  mulhu        a1, t1, t5
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  mulh         s9, s8, gp
                  li           s7, 0x0 #start riscv_int_numeric_corner_stream_4
                  li           a0, 0xffffffff
                  li           s11, 0x1f1d6216
                  li           s5, 0x80000000
                  li           s8, 0xffffffff
                  li           ra, 0x0
                  li           a2, 0xffffffff
                  li           s0, 0x0
                  li           s2, 0x80000000
                  li           a5, 0x0
                  remu         a5, s7, s11
                  add          a2, s8, ra
                  rem          s0, a0, s0
                  sub          s7, s2, s5
                  remu         a5, s7, s11
                  rem          s0, a0, s0
                  div          s5, s5, s0
                  rem          s0, a0, s0
                  nop
                  remu         a5, s7, s11
                  remu         a5, s7, s11
                  mul          a5, s8, s8
                  nop
                  nop
                  nop
                  remu         a5, s7, s11
                  addi         ra, s5, 2029
                  mul          a5, s8, s8
                  sub          s7, s2, s5
                  nop #end riscv_int_numeric_corner_stream_4
                  srl          s2, s1, sp
                  mulhu        a1, t1, t5
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  c.and        a3, s0
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  c.li         t6, 20
                  c.add        s7, s6
                  xor          t5, s1, a7
                  c.add        s7, s6
                  div          a2, t1, a7
                  c.li         t6, 20
                  c.li         t6, 20
                  lui          s0, 955933
                  c.add        s7, s6
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  c.nop
                  slti         s8, ra, -2031
                  c.mv         s8, t5
                  c.li         t6, 20
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  c.add        s7, s6
                  lui          s0, 955933
                  srli         a3, s8, 11
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  sub          s9, s5, s6
                  c.li         t6, 20
                  slli         t4, t3, 27
                  remu         t0, s7, s1
                  c.andi       a5, 16
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  auipc        tp, 400075
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  and          s6, gp, s0
                  nop
                  mul          s6, a0, s0
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  addi         zero, t6, 2029
                  c.add        s7, s6
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  mulhsu       s1, s4, sp
                  divu         s1, s4, a4
                  srli         a3, s8, 11
                  c.mv         s8, t5
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  srl          s2, s1, sp
                  sub          s9, s5, s6
                  srli         a3, s8, 11
                  slli         t4, t3, 27
                  c.srai       a3, 9
                  auipc        tp, 400075
                  c.srai       a3, 9
                  mul          s6, a0, s0
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  c.nop
                  auipc        tp, 400075
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  ori          a2, a1, -1711
                  c.li         t6, 20
                  or           t4, a3, a3
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  mul          s6, a0, s0
                  c.andi       a5, 16
                  c.add        s7, s6
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  c.and        a3, s0
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  c.and        a3, s0
                  or           t4, a3, a3
                  srai         s6, s3, 24
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  div          a2, t1, a7
                  c.andi       a5, 16
                  sub          s9, s5, s6
                  div          a2, t1, a7
                  c.mv         s8, t5
                  c.or         a3, s1
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  or           t4, a3, a3
                  c.nop
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  c.add        s7, s6
                  or           t4, a3, a3
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  c.slli       s8, 9
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  mulh         s9, s8, gp
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  li           s11, 0xffffffff #start riscv_int_numeric_corner_stream_30
                  li           s7, 0x5c8134ff
                  li           gp, 0x80000000
                  li           a3, 0x0
                  li           a0, 0xd1d2960f
                  li           s0, 0xf26d065e
                  li           a2, 0xffffffff
                  li           t2, 0x80000000
                  li           s2, 0x7b3e0c79
                  li           a6, 0xffffffff
                  remu         a2, s2, s11
                  mulh         s2, s7, a0
                  nop
                  auipc        a0, 400075
                  mulhu        s0, a6, gp
                  mulhsu       s7, a2, s0
                  div          a6, a6, t2
                  mul          a2, s7, s7
                  mulhsu       s7, a2, s0
                  mul          a2, s7, s7
                  remu         a2, s2, s11
                  divu         s7, a2, a3
                  addi         gp, a6, 2029
                  mul          a2, s7, s7
                  mulhu        s0, a6, gp
                  mulhu        s0, a6, gp
                  divu         s7, a2, a3
                  rem          t2, s0, t2 #end riscv_int_numeric_corner_stream_30
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  andi         s5, tp, -69
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  nop
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  divu         s1, s4, a4
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  slti         s8, ra, -2031
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  div          a2, t1, a7
                  c.srli       a0, 18
                  and          s6, gp, s0
                  c.li         t6, 20
                  c.li         t6, 20
                  nop
                  ori          a2, a1, -1711
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.add        s7, s6
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  c.slli       s8, 9
                  c.nop
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  c.nop
                  c.or         a3, s1
                  slt          t6, a0, sp
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  sub          s9, s5, s6
                  mulhsu       s1, s4, sp
                  c.addi       s2, 16
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  sub          s9, s5, s6
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  c.and        a3, s0
                  c.or         a3, s1
                  c.sub        s0, a4
                  slti         s8, ra, -2031
                  remu         t0, s7, s1
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  c.and        a3, s0
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  c.nop
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  c.xor        a5, s0
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  li           a3, 0x255c451b #start riscv_int_numeric_corner_stream_17
                  li           s7, 0x745e5eda
                  li           s9, 0x80000000
                  li           t4, 0x78693875
                  li           s1, 0xffffffff
                  li           tp, 0xd84ac08b
                  li           s2, 0x80000000
                  li           a6, 0xe4860cac
                  li           t1, 0x965eb10c
                  li           t0, 0x0
                  auipc        s1, 400075
                  lui          s7, 955933
                  mul          a3, s9, s9
                  div          s2, s2, t0
                  mulh         s7, s9, s1
                  sub          s7, a6, s2
                  mulh         s7, s9, s1
                  rem          t0, t1, t0
                  lui          s7, 955933
                  divu         s9, a3, a6
                  add          s1, s9, tp
                  sub          s7, a6, s2
                  mul          a3, s9, s9
                  remu         a3, s7, t4
                  div          s2, s2, t0
                  mulhu        t1, s2, tp
                  addi         tp, s2, 2029
                  lui          s7, 955933
                  remu         a3, s7, t4
                  divu         s9, a3, a6
                  div          s2, s2, t0
                  sub          s7, a6, s2
                  rem          t0, t1, t0
                  mul          a3, s9, s9 #end riscv_int_numeric_corner_stream_17
                  c.or         a3, s1
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  slti         s8, ra, -2031
                  c.nop
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  nop
                  c.sub        s0, a4
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  mulhu        a1, t1, t5
                  div          a2, t1, a7
                  slt          t6, a0, sp
                  c.li         t6, 20
                  c.addi       s2, 16
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  c.mv         s8, t5
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  c.and        a3, s0
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  mulh         s9, s8, gp
                  div          a2, t1, a7
                  add          s5, s8, a6
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  div          a2, t1, a7
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  c.li         t6, 20
                  c.nop
                  mulh         s9, s8, gp
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  or           t4, a3, a3
                  lui          s0, 955933
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  lui          s0, 955933
                  divu         s1, s4, a4
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  auipc        tp, 400075
                  lui          s0, 955933
                  c.li         t6, 20
                  c.li         t6, 20
                  nop
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  or           t4, a3, a3
                  lui          s0, 955933
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  and          s6, gp, s0
                  c.li         t6, 20
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  srai         s6, s3, 24
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  nop
                  c.li         t6, 20
                  lui          s0, 955933
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  c.srai       a3, 9
                  lui          s0, 955933
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  div          a2, t1, a7
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  nop
                  slli         t4, t3, 27
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  div          a2, t1, a7
                  c.srli       a0, 18
                  and          s6, gp, s0
                  c.sub        s0, a4
                  auipc        tp, 400075
                  mulhsu       s1, s4, sp
                  div          a2, t1, a7
                  mulh         s9, s8, gp
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  c.lui        s0, 15
                  and          s6, gp, s0
                  c.and        a3, s0
                  xor          t5, s1, a7
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  c.slli       s8, 9
                  c.nop
                  nop
                  c.lui        s0, 15
                  c.srli       a0, 18
                  c.sub        s0, a4
                  slti         s8, ra, -2031
                  c.and        a3, s0
                  srli         a3, s8, 11
                  c.nop
                  mul          s6, a0, s0
                  slli         t4, t3, 27
                  or           t4, a3, a3
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  sltu         s10, s9, s8
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  sltiu        zero, gp, -198
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  lui          s0, 955933
                  add          s5, s8, a6
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  xor          t5, s1, a7
                  lui          s0, 955933
                  c.and        a3, s0
                  c.srli       a0, 18
                  mulhsu       s1, s4, sp
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  auipc        tp, 400075
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  c.nop
                  c.and        a3, s0
                  c.lui        s0, 15
                  and          s6, gp, s0
                  div          a2, t1, a7
                  c.and        a3, s0
                  c.li         t6, 20
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  xori         t5, s5, -792
                  mul          s6, a0, s0
                  nop
                  divu         s1, s4, a4
                  and          s6, gp, s0
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  c.sub        s0, a4
                  auipc        tp, 400075
                  rem          a4, s2, a7
                  nop
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  c.andi       a5, 16
                  andi         s5, tp, -69
                  c.mv         s8, t5
                  nop
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  c.srli       a0, 18
                  c.sub        s0, a4
                  c.li         t6, 20
                  srli         a3, s8, 11
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  lui          s0, 955933
                  c.srai       a3, 9
                  divu         s1, s4, a4
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  c.or         a3, s1
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  slt          t6, a0, sp
                  mulhu        a1, t1, t5
                  c.srli       a0, 18
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  c.slli       s8, 9
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  c.and        a3, s0
                  c.add        s7, s6
                  c.sub        s0, a4
                  c.or         a3, s1
                  srl          s2, s1, sp
                  c.li         t6, 20
                  lui          s0, 955933
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  mulhsu       s1, s4, sp
                  c.add        s7, s6
                  c.slli       s8, 9
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  c.nop
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  c.srai       a3, 9
                  c.add        s7, s6
                  srl          s2, s1, sp
                  nop
                  mul          s6, a0, s0
                  srl          s2, s1, sp
                  c.li         t6, 20
                  sra          a3, s6, t4
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  c.or         a3, s1
                  div          a2, t1, a7
                  rem          a4, s2, a7
                  c.lui        s0, 15
                  c.srli       a0, 18
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  lui          s0, 955933
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  srl          s2, s1, sp
                  c.or         a3, s1
                  sltiu        zero, gp, -198
                  srli         a3, s8, 11
                  c.nop
                  auipc        tp, 400075
                  c.lui        s0, 15
                  lui          s0, 955933
                  c.sub        s0, a4
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  srl          s2, s1, sp
                  c.sub        s0, a4
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  nop
                  ori          a2, a1, -1711
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  c.and        a3, s0
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  lui          s0, 955933
                  srli         a3, s8, 11
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  lui          s0, 955933
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  c.andi       a5, 16
                  c.xor        a5, s0
                  c.mv         s8, t5
                  c.nop
                  nop
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  c.sub        s0, a4
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  c.sub        s0, a4
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  li           t6, 0x0 #start riscv_int_numeric_corner_stream_39
                  li           s6, 0x0
                  li           a3, 0xef43544
                  li           t5, 0xffffffff
                  li           s8, 0xffffffff
                  li           a1, 0x0
                  li           a2, 0x80000000
                  li           s1, 0xffffffff
                  li           t4, 0x0
                  li           t0, 0x0
                  add          a2, t5, t0
                  mulh         t4, t5, a2
                  sub          t4, s6, s8
                  nop
                  div          s8, s8, s1
                  rem          s1, a1, s1
                  rem          s1, a1, s1
                  mulhsu       t5, a3, a1
                  div          s8, s8, s1
                  add          a2, t5, t0
                  addi         t0, s8, 2029
                  mulhsu       t5, a3, a1
                  lui          t4, 955933
                  mulhsu       t5, a3, a1
                  sub          t4, s6, s8 #end riscv_int_numeric_corner_stream_39
                  c.and        a3, s0
                  xor          t5, s1, a7
                  remu         t0, s7, s1
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  c.li         t6, 20
                  c.and        a3, s0
                  c.srli       a0, 18
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  c.sub        s0, a4
                  mul          s6, a0, s0
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  c.addi       s2, 16
                  nop
                  sltu         s10, s9, s8
                  andi         s5, tp, -69
                  divu         s1, s4, a4
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  c.and        a3, s0
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  lui          s0, 955933
                  slt          t6, a0, sp
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.add        s7, s6
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  auipc        tp, 400075
                  c.addi       s2, 16
                  c.srli       a0, 18
                  c.add        s7, s6
                  c.nop
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  c.li         t6, 20
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  c.and        a3, s0
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  sltu         s10, s9, s8
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  add          s5, s8, a6
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  xor          t5, s1, a7
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  divu         s1, s4, a4
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  c.or         a3, s1
                  c.lui        s0, 15
                  sltu         s10, s9, s8
                  c.nop
                  nop
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  c.sub        s0, a4
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  c.li         t6, 20
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  srl          s2, s1, sp
                  c.andi       a5, 16
                  c.slli       s8, 9
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  c.xor        a5, s0
                  c.and        a3, s0
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  c.and        a3, s0
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  slt          t6, a0, sp
                  c.nop
                  c.lui        s0, 15
                  c.andi       a5, 16
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  c.add        s7, s6
                  remu         t0, s7, s1
                  c.add        s7, s6
                  sltu         s10, s9, s8
                  mul          s6, a0, s0
                  c.slli       s8, 9
                  c.and        a3, s0
                  sll          a5, s3, s8
                  srli         a3, s8, 11
                  c.or         a3, s1
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  nop
                  add          s5, s8, a6
                  lui          s0, 955933
                  c.slli       s8, 9
                  slt          t6, a0, sp
                  c.add        s7, s6
                  c.add        s7, s6
                  c.nop
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  c.andi       a5, 16
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  srl          s2, s1, sp
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  c.mv         s8, t5
                  c.mv         s8, t5
                  slt          t6, a0, sp
                  nop
                  c.srai       a3, 9
                  nop
                  divu         s1, s4, a4
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  lui          s0, 955933
                  c.mv         s8, t5
                  ori          a2, a1, -1711
                  divu         s1, s4, a4
                  lui          s0, 955933
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  lui          s0, 955933
                  add          s5, s8, a6
                  auipc        tp, 400075
                  slli         t4, t3, 27
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  c.nop
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  c.xor        a5, s0
                  and          s6, gp, s0
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  nop
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  c.or         a3, s1
                  c.xor        a5, s0
                  c.slli       s8, 9
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  andi         s5, tp, -69
                  nop
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  sltu         s10, s9, s8
                  srl          s2, s1, sp
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  sll          a5, s3, s8
                  c.srli       a0, 18
                  c.and        a3, s0
                  mul          s6, a0, s0
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  xor          t5, s1, a7
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  divu         s1, s4, a4
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  c.and        a3, s0
                  slti         s8, ra, -2031
                  c.slli       s8, 9
                  div          a2, t1, a7
                  nop
                  divu         s1, s4, a4
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  xori         t5, s5, -792
                  div          a2, t1, a7
                  nop
                  c.srli       a0, 18
                  or           t4, a3, a3
                  nop
                  c.addi       s2, 16
                  slli         t4, t3, 27
                  mulhu        a1, t1, t5
                  auipc        tp, 400075
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  auipc        tp, 400075
                  div          a2, t1, a7
                  c.lui        s0, 15
                  c.mv         s8, t5
                  or           t4, a3, a3
                  ori          a2, a1, -1711
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  c.nop
                  or           t4, a3, a3
                  c.srli       a0, 18
                  c.nop
                  c.addi       s2, 16
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  slt          t6, a0, sp
                  c.or         a3, s1
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  mul          s6, a0, s0
                  c.mv         s8, t5
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  c.add        s7, s6
                  c.lui        s0, 15
                  mulh         s9, s8, gp
                  mul          s6, a0, s0
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  c.or         a3, s1
                  rem          a4, s2, a7
                  c.or         a3, s1
                  srai         s6, s3, 24
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  c.add        s7, s6
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  c.addi       s2, 16
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  add          s5, s8, a6
                  c.slli       s8, 9
                  sub          s9, s5, s6
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  c.andi       a5, 16
                  nop
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  c.add        s7, s6
                  c.sub        s0, a4
                  c.nop
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  mulh         s9, s8, gp
                  c.mv         s8, t5
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  sll          a5, s3, s8
                  nop
                  sll          a5, s3, s8
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  c.add        s7, s6
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  nop
                  c.andi       a5, 16
                  lui          s0, 955933
                  c.lui        s0, 15
                  and          s6, gp, s0
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  c.lui        s0, 15
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  lui          s0, 955933
                  mulhsu       s1, s4, sp
                  lui          s0, 955933
                  srai         s6, s3, 24
                  c.sub        s0, a4
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  c.or         a3, s1
                  slli         t4, t3, 27
                  c.add        s7, s6
                  sra          a3, s6, t4
                  and          s6, gp, s0
                  sub          s9, s5, s6
                  c.slli       s8, 9
                  slti         s8, ra, -2031
                  c.andi       a5, 16
                  lui          s0, 955933
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  remu         t0, s7, s1
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  and          s6, gp, s0
                  c.nop
                  c.mv         s8, t5
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  and          s6, gp, s0
                  rem          a4, s2, a7
                  c.lui        s0, 15
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  mulhu        a1, t1, t5
                  c.sub        s0, a4
                  c.addi       s2, 16
                  c.add        s7, s6
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  c.and        a3, s0
                  c.sub        s0, a4
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  c.nop
                  mulhu        a1, t1, t5
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  mul          s6, a0, s0
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  c.li         t6, 20
                  c.lui        s0, 15
                  c.lui        s0, 15
                  c.sub        s0, a4
                  andi         s5, tp, -69
                  c.li         t6, 20
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  c.or         a3, s1
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  c.slli       s8, 9
                  div          a2, t1, a7
                  c.xor        a5, s0
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  lui          s0, 955933
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  c.sub        s0, a4
                  nop
                  mulhu        a1, t1, t5
                  srai         s6, s3, 24
                  andi         s5, tp, -69
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  mul          s6, a0, s0
                  c.or         a3, s1
                  c.li         t6, 20
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  nop
                  c.li         t6, 20
                  li           a5, 0x0 #start riscv_int_numeric_corner_stream_13
                  li           gp, 0x0
                  li           s5, 0x7d582c88
                  li           s2, 0x0
                  li           a4, 0xffffffff
                  li           a7, 0x900001c6
                  li           t5, 0x0
                  li           t1, 0xffffffff
                  li           ra, 0x0
                  li           s3, 0x80000000
                  remu         a5, s3, t5
                  div          s2, s2, gp
                  add          a4, s5, ra
                  div          s2, s2, gp
                  mulhu        t1, s2, ra
                  lui          s3, 955933
                  divu         s5, a5, a7
                  remu         a5, s3, t5
                  mulhsu       s5, a5, t1
                  mulh         s3, s5, a4
                  remu         a5, s3, t5
                  mulh         s3, s5, a4
                  sub          s3, a7, s2
                  nop
                  nop
                  mulhu        t1, s2, ra
                  lui          s3, 955933
                  auipc        a4, 400075
                  rem          gp, t1, gp
                  lui          s3, 955933
                  lui          s3, 955933
                  nop
                  auipc        a4, 400075
                  divu         s5, a5, a7
                  mulhu        t1, s2, ra
                  remu         a5, s3, t5
                  mul          a5, s5, s5
                  mulh         s3, s5, a4
                  addi         ra, s2, 2029 #end riscv_int_numeric_corner_stream_13
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  rem          a4, s2, a7
                  c.addi       s2, 16
                  c.xor        a5, s0
                  c.andi       a5, 16
                  c.andi       a5, 16
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  c.nop
                  c.addi       s2, 16
                  slti         s8, ra, -2031
                  c.sub        s0, a4
                  c.and        a3, s0
                  c.mv         s8, t5
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  c.add        s7, s6
                  remu         t0, s7, s1
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  divu         s1, s4, a4
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  c.sub        s0, a4
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  c.srai       a3, 9
                  c.nop
                  mulhsu       s1, s4, sp
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  srli         a3, s8, 11
                  div          a2, t1, a7
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  mulhu        a1, t1, t5
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  lui          s0, 955933
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  srl          s2, s1, sp
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  c.or         a3, s1
                  c.li         t6, 20
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  c.srli       a0, 18
                  lui          s0, 955933
                  nop
                  li           a5, 0x0 #start riscv_int_numeric_corner_stream_2
                  li           s6, 0xffffffff
                  li           s11, 0x80000000
                  li           s0, 0x80000000
                  li           s2, 0x0
                  li           s10, 0x0
                  li           a1, 0x0
                  li           a4, 0xffffffff
                  li           s1, 0x32d2a86f
                  li           ra, 0xffffffff
                  div          s2, s2, s0
                  add          a1, s10, ra
                  divu         s10, a4, a5
                  nop
                  mulh         s6, s10, a1
                  mulh         s6, s10, a1
                  rem          s0, s1, s0
                  nop
                  sub          s6, a5, s2
                  remu         a4, s6, s11
                  add          a1, s10, ra
                  div          s2, s2, s0
                  remu         a4, s6, s11
                  nop
                  mulhu        s1, s2, ra
                  auipc        a1, 400075
                  mulhu        s1, s2, ra
                  remu         a4, s6, s11
                  mulhsu       s10, a4, s1
                  divu         s10, a4, a5
                  rem          s0, s1, s0
                  auipc        a1, 400075
                  sub          s6, a5, s2
                  auipc        a1, 400075
                  rem          s0, s1, s0
                  rem          s0, s1, s0
                  mulh         s6, s10, a1
                  sub          s6, a5, s2
                  div          s2, s2, s0
                  remu         a4, s6, s11 #end riscv_int_numeric_corner_stream_2
                  or           t4, a3, a3
                  nop
                  c.srai       a3, 9
                  auipc        tp, 400075
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  c.srai       a3, 9
                  xor          t5, s1, a7
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  nop
                  c.srli       a0, 18
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  srli         a3, s8, 11
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  c.lui        s0, 15
                  c.slli       s8, 9
                  mul          s6, a0, s0
                  sll          a5, s3, s8
                  nop
                  xori         t5, s5, -792
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  c.sub        s0, a4
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  c.li         t6, 20
                  c.srai       a3, 9
                  c.srli       a0, 18
                  lui          s0, 955933
                  div          a2, t1, a7
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  c.slli       s8, 9
                  c.andi       a5, 16
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  srl          s2, s1, sp
                  addi         zero, t6, 2029
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  c.and        a3, s0
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  srai         s6, s3, 24
                  auipc        tp, 400075
                  nop
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  c.or         a3, s1
                  slt          t6, a0, sp
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  nop
                  mulhsu       s1, s4, sp
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  c.addi       s2, 16
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.andi       a5, 16
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  c.or         a3, s1
                  nop
                  rem          a4, s2, a7
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  c.and        a3, s0
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  nop
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  c.and        a3, s0
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  mul          s6, a0, s0
                  c.xor        a5, s0
                  rem          a4, s2, a7
                  c.and        a3, s0
                  mul          s6, a0, s0
                  c.mv         s8, t5
                  auipc        tp, 400075
                  c.slli       s8, 9
                  sra          a3, s6, t4
                  sltiu        zero, gp, -198
                  sltu         s10, s9, s8
                  nop
                  mulh         s9, s8, gp
                  c.and        a3, s0
                  c.addi       s2, 16
                  andi         s5, tp, -69
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  addi         zero, t6, 2029
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  c.add        s7, s6
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  c.mv         s8, t5
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  xor          t5, s1, a7
                  c.nop
                  xori         t5, s5, -792
                  c.andi       a5, 16
                  c.andi       a5, 16
                  srli         a3, s8, 11
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  add          s5, s8, a6
                  mulhsu       s1, s4, sp
                  slli         t4, t3, 27
                  c.add        s7, s6
                  sra          a3, s6, t4
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  sub          s9, s5, s6
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  srl          s2, s1, sp
                  nop
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  c.xor        a5, s0
                  c.add        s7, s6
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  lui          s0, 955933
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  c.mv         s8, t5
                  and          s6, gp, s0
                  c.or         a3, s1
                  c.andi       a5, 16
                  mulh         s9, s8, gp
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  c.slli       s8, 9
                  nop
                  c.add        s7, s6
                  c.nop
                  c.add        s7, s6
                  xori         t5, s5, -792
                  c.nop
                  or           t4, a3, a3
                  nop
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  mul          s6, a0, s0
                  c.nop
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  div          a2, t1, a7
                  add          s5, s8, a6
                  lui          s0, 955933
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  c.li         t6, 20
                  c.lui        s0, 15
                  c.slli       s8, 9
                  c.xor        a5, s0
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  c.slli       s8, 9
                  c.and        a3, s0
                  srl          s2, s1, sp
                  c.slli       s8, 9
                  c.add        s7, s6
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  c.xor        a5, s0
                  srl          s2, s1, sp
                  rem          a4, s2, a7
                  mulhsu       s1, s4, sp
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  lui          s0, 955933
                  c.xor        a5, s0
                  c.add        s7, s6
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  c.slli       s8, 9
                  lui          s0, 955933
                  c.srai       a3, 9
                  c.add        s7, s6
                  nop
                  mul          s6, a0, s0
                  and          s6, gp, s0
                  srli         a3, s8, 11
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  div          a2, t1, a7
                  lui          s0, 955933
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  srl          s2, s1, sp
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  c.andi       a5, 16
                  remu         t0, s7, s1
                  c.li         t6, 20
                  c.addi       s2, 16
                  srai         s6, s3, 24
                  ori          a2, a1, -1711
                  c.nop
                  c.andi       a5, 16
                  c.andi       a5, 16
                  c.or         a3, s1
                  c.and        a3, s0
                  xori         t5, s5, -792
                  srl          s2, s1, sp
                  and          s6, gp, s0
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  c.nop
                  div          a2, t1, a7
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.sub        s0, a4
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  lui          s0, 955933
                  c.nop
                  c.nop
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  c.xor        a5, s0
                  div          a2, t1, a7
                  nop
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  c.nop
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  mul          s6, a0, s0
                  c.lui        s0, 15
                  slli         t4, t3, 27
                  mulhu        a1, t1, t5
                  sll          a5, s3, s8
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  or           t4, a3, a3
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  srl          s2, s1, sp
                  c.and        a3, s0
                  mulh         s9, s8, gp
                  add          s5, s8, a6
                  add          s5, s8, a6
                  c.mv         s8, t5
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  lui          s0, 955933
                  div          a2, t1, a7
                  sltiu        zero, gp, -198
                  remu         t0, s7, s1
                  c.nop
                  c.srai       a3, 9
                  div          a2, t1, a7
                  c.sub        s0, a4
                  c.slli       s8, 9
                  mulh         s9, s8, gp
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  or           t4, a3, a3
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  c.add        s7, s6
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  c.or         a3, s1
                  div          a2, t1, a7
                  li           s11, 0x80000000 #start riscv_int_numeric_corner_stream_7
                  li           a0, 0x80000000
                  li           a6, 0xd73100a7
                  li           s0, 0xffffffff
                  li           tp, 0x405e8dff
                  li           ra, 0xffffffff
                  li           s6, 0xffffffff
                  li           s9, 0xffffffff
                  li           s1, 0x0
                  li           a1, 0xffffffff
                  mul          a0, s9, s9
                  lui          s6, 955933
                  remu         a0, s6, s11
                  sub          s6, a1, a6
                  addi         ra, a6, 2029
                  sub          s6, a1, a6
                  rem          tp, s0, tp
                  divu         s9, a0, a1
                  addi         ra, a6, 2029
                  mul          a0, s9, s9
                  mulhu        s0, a6, ra
                  mul          a0, s9, s9
                  sub          s6, a1, a6
                  divu         s9, a0, a1
                  div          a6, a6, tp
                  div          a6, a6, tp
                  sub          s6, a1, a6 #end riscv_int_numeric_corner_stream_7
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  mulh         s9, s8, gp
                  lui          s0, 955933
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  c.srai       a3, 9
                  c.xor        a5, s0
                  c.lui        s0, 15
                  or           t4, a3, a3
                  and          s6, gp, s0
                  c.addi       s2, 16
                  c.srai       a3, 9
                  c.li         t6, 20
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  add          s5, s8, a6
                  c.slli       s8, 9
                  c.add        s7, s6
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  mulhsu       s1, s4, sp
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  c.nop
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  c.srai       a3, 9
                  divu         s1, s4, a4
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  xor          t5, s1, a7
                  auipc        tp, 400075
                  lui          s0, 955933
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  and          s6, gp, s0
                  c.sub        s0, a4
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  c.add        s7, s6
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  div          a2, t1, a7
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  c.add        s7, s6
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  lui          s0, 955933
                  add          s5, s8, a6
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  ori          a2, a1, -1711
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  mulhsu       s1, s4, sp
                  mulhu        a1, t1, t5
                  sll          a5, s3, s8
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  c.nop
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  c.add        s7, s6
                  sltu         s10, s9, s8
                  divu         s1, s4, a4
                  lui          s0, 955933
                  c.or         a3, s1
                  nop
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  sll          a5, s3, s8
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  c.addi       s2, 16
                  add          s5, s8, a6
                  ori          a2, a1, -1711
                  c.xor        a5, s0
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  ori          a2, a1, -1711
                  remu         t0, s7, s1
                  c.add        s7, s6
                  c.add        s7, s6
                  srl          s2, s1, sp
                  sltiu        zero, gp, -198
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  c.nop
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  srli         a3, s8, 11
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  c.li         t6, 20
                  xori         t5, s5, -792
                  mulh         s9, s8, gp
                  c.srli       a0, 18
                  mul          s6, a0, s0
                  c.sub        s0, a4
                  remu         t0, s7, s1
                  c.nop
                  lui          s0, 955933
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  div          a2, t1, a7
                  c.nop
                  c.sub        s0, a4
                  c.add        s7, s6
                  c.xor        a5, s0
                  c.nop
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  nop
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  c.slli       s8, 9
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  c.addi       s2, 16
                  c.srli       a0, 18
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  xor          t5, s1, a7
                  c.nop
                  c.add        s7, s6
                  mul          s6, a0, s0
                  mulhsu       s1, s4, sp
                  c.and        a3, s0
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  c.slli       s8, 9
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  sltiu        zero, gp, -198
                  divu         s1, s4, a4
                  c.add        s7, s6
                  srl          s2, s1, sp
                  rem          a4, s2, a7
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  c.srai       a3, 9
                  c.addi       s2, 16
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  div          a2, t1, a7
                  rem          a4, s2, a7
                  c.and        a3, s0
                  c.or         a3, s1
                  mul          s6, a0, s0
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  nop
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  c.slli       s8, 9
                  srl          s2, s1, sp
                  c.or         a3, s1
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  c.and        a3, s0
                  c.nop
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  or           t4, a3, a3
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  ori          a2, a1, -1711
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  lui          s0, 955933
                  slt          t6, a0, sp
                  c.nop
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  auipc        tp, 400075
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  c.and        a3, s0
                  sub          s9, s5, s6
                  lui          s0, 955933
                  and          s6, gp, s0
                  sra          a3, s6, t4
                  lui          s0, 955933
                  slli         t4, t3, 27
                  c.and        a3, s0
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  c.li         t6, 20
                  c.sub        s0, a4
                  c.addi       s2, 16
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  sll          a5, s3, s8
                  c.li         t6, 20
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  divu         s1, s4, a4
                  c.mv         s8, t5
                  or           t4, a3, a3
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  c.nop
                  c.mv         s8, t5
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  xor          t5, s1, a7
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  c.add        s7, s6
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  c.and        a3, s0
                  c.xor        a5, s0
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  mul          s6, a0, s0
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  c.nop
                  mul          s6, a0, s0
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  add          s5, s8, a6
                  and          s6, gp, s0
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  sll          a5, s3, s8
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  div          a2, t1, a7
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  srli         a3, s8, 11
                  c.and        a3, s0
                  and          s6, gp, s0
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  and          s6, gp, s0
                  div          a2, t1, a7
                  mulhsu       s1, s4, sp
                  mulhsu       s1, s4, sp
                  c.andi       a5, 16
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  sub          s9, s5, s6
                  lui          s0, 955933
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  rem          a4, s2, a7
                  c.srli       a0, 18
                  mulh         s9, s8, gp
                  mul          s6, a0, s0
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  c.or         a3, s1
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  srli         a3, s8, 11
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  and          s6, gp, s0
                  c.srai       a3, 9
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  c.nop
                  xor          t5, s1, a7
                  rem          a4, s2, a7
                  c.addi       s2, 16
                  nop
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  c.addi       s2, 16
                  c.or         a3, s1
                  c.mv         s8, t5
                  div          a2, t1, a7
                  li           gp, 0x0 #start riscv_int_numeric_corner_stream_6
                  li           s10, 0x0
                  li           a4, 0xfe744c04
                  li           t6, 0xffffffff
                  li           s0, 0x80000000
                  li           s11, 0xffffffff
                  li           a6, 0x0
                  li           s7, 0xffffffff
                  li           a7, 0xffffffff
                  li           s6, 0x61aac75e
                  add          a6, s11, gp
                  rem          s0, a4, s0
                  add          a6, s11, gp
                  mul          a7, s11, s11
                  mulh         s10, s11, a6
                  mulhsu       s11, a7, a4
                  sub          s10, s6, s7
                  mulhsu       s11, a7, a4
                  addi         gp, s7, 2029
                  mulh         s10, s11, a6
                  nop
                  mulh         s10, s11, a6
                  mulhu        a4, s7, gp
                  div          s7, s7, s0
                  remu         a7, s10, t6
                  mul          a7, s11, s11
                  lui          s10, 955933
                  rem          s0, a4, s0
                  sub          s10, s6, s7 #end riscv_int_numeric_corner_stream_6
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  c.nop
                  c.nop
                  c.mv         s8, t5
                  c.xor        a5, s0
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  c.nop
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  c.add        s7, s6
                  slt          t6, a0, sp
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  c.nop
                  sra          a3, s6, t4
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  nop
                  c.add        s7, s6
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  mul          s6, a0, s0
                  ori          a2, a1, -1711
                  c.lui        s0, 15
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  c.or         a3, s1
                  c.xor        a5, s0
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  c.or         a3, s1
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  c.nop
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  srli         a3, s8, 11
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  c.or         a3, s1
                  c.mv         s8, t5
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  c.nop
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  slti         s8, ra, -2031
                  andi         s5, tp, -69
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  div          a2, t1, a7
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  c.nop
                  srl          s2, s1, sp
                  slli         t4, t3, 27
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  ori          a2, a1, -1711
                  nop
                  remu         t0, s7, s1
                  addi         zero, t6, 2029
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  sra          a3, s6, t4
                  sra          a3, s6, t4
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  c.xor        a5, s0
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  div          a2, t1, a7
                  divu         s1, s4, a4
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  c.sub        s0, a4
                  remu         t0, s7, s1
                  c.srai       a3, 9
                  c.li         t6, 20
                  c.addi       s2, 16
                  mulhu        a1, t1, t5
                  sltu         s10, s9, s8
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  or           t4, a3, a3
                  and          s6, gp, s0
                  nop
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  divu         s1, s4, a4
                  c.mv         s8, t5
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  mulh         s9, s8, gp
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  add          s5, s8, a6
                  c.slli       s8, 9
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  sltiu        zero, gp, -198
                  c.nop
                  mulhsu       s1, s4, sp
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  and          s6, gp, s0
                  nop
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  lui          s0, 955933
                  c.lui        s0, 15
                  c.xor        a5, s0
                  lui          s0, 955933
                  c.sub        s0, a4
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  lui          s0, 955933
                  mulhsu       s1, s4, sp
                  mulh         s9, s8, gp
                  c.li         t6, 20
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  slt          t6, a0, sp
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  c.li         t6, 20
                  xori         t5, s5, -792
                  c.and        a3, s0
                  div          a2, t1, a7
                  or           t4, a3, a3
                  sltiu        zero, gp, -198
                  sll          a5, s3, s8
                  mul          s6, a0, s0
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  div          a2, t1, a7
                  c.mv         s8, t5
                  mulhsu       s1, s4, sp
                  auipc        tp, 400075
                  sra          a3, s6, t4
                  slli         t4, t3, 27
                  remu         t0, s7, s1
                  c.or         a3, s1
                  c.sub        s0, a4
                  c.slli       s8, 9
                  c.srai       a3, 9
                  c.srai       a3, 9
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  slti         s8, ra, -2031
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  c.or         a3, s1
                  add          s5, s8, a6
                  lui          s0, 955933
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  addi         zero, t6, 2029
                  li           a1, 0xffffffff #start riscv_int_numeric_corner_stream_26
                  li           t0, 0x0
                  li           tp, 0x80000000
                  li           s2, 0x80000000
                  li           a2, 0x80000000
                  li           s7, 0xffffffff
                  li           a0, 0xfb0b68f0
                  li           a6, 0x0
                  li           a4, 0x0
                  li           t6, 0xffffffff
                  add          a1, s7, tp
                  auipc        a1, 400075
                  mul          a2, s7, s7
                  rem          t0, a0, t0
                  div          a6, a6, t0
                  rem          t0, a0, t0
                  divu         s7, a2, a4
                  mulhsu       s7, a2, a0
                  auipc        a1, 400075
                  addi         tp, a6, 2029
                  addi         tp, a6, 2029
                  mulhu        a0, a6, tp
                  lui          s2, 955933
                  mul          a2, s7, s7
                  addi         tp, a6, 2029
                  lui          s2, 955933
                  rem          t0, a0, t0
                  mulhsu       s7, a2, a0
                  div          a6, a6, t0
                  mulh         s2, s7, a1
                  mul          a2, s7, s7
                  mulh         s2, s7, a1
                  mulhsu       s7, a2, a0
                  lui          s2, 955933
                  mul          a2, s7, s7
                  add          a1, s7, tp
                  addi         tp, a6, 2029 #end riscv_int_numeric_corner_stream_26
                  sltu         s10, s9, s8
                  c.xor        a5, s0
                  srl          s2, s1, sp
                  li           s0, 0x80000000 #start riscv_int_numeric_corner_stream_25
                  li           t6, 0x0
                  li           s1, 0x2b3ddd39
                  li           s6, 0xffffffff
                  li           t2, 0xffffffff
                  li           s8, 0xffffffff
                  li           s10, 0x80000000
                  li           gp, 0x80000000
                  li           ra, 0x80000000
                  li           s5, 0x9ceb17eb
                  lui          s8, 955933
                  add          s0, s10, ra
                  sub          s8, s5, s6
                  nop
                  sub          s8, s5, s6
                  mulh         s8, s10, s0
                  lui          s8, 955933
                  add          s0, s10, ra
                  addi         ra, s6, 2029
                  nop
                  auipc        s0, 400075
                  divu         s10, s1, s5
                  sub          s8, s5, s6
                  add          s0, s10, ra
                  mulhu        t2, s6, ra
                  lui          s8, 955933
                  addi         ra, s6, 2029
                  lui          s8, 955933
                  lui          s8, 955933
                  mulh         s8, s10, s0
                  auipc        s0, 400075
                  mulhu        t2, s6, ra
                  mulhu        t2, s6, ra
                  mul          s1, s10, s10
                  mul          s1, s10, s10
                  mulhu        t2, s6, ra
                  rem          gp, t2, gp
                  mul          s1, s10, s10
                  div          s6, s6, gp
                  add          s0, s10, ra #end riscv_int_numeric_corner_stream_25
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.add        s7, s6
                  auipc        tp, 400075
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  c.nop
                  c.slli       s8, 9
                  divu         s1, s4, a4
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  sll          a5, s3, s8
                  nop
                  add          s5, s8, a6
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  c.srai       a3, 9
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  c.andi       a5, 16
                  div          a2, t1, a7
                  c.and        a3, s0
                  c.add        s7, s6
                  c.li         t6, 20
                  sub          s9, s5, s6
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  sll          a5, s3, s8
                  c.li         t6, 20
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  c.srli       a0, 18
                  mul          s6, a0, s0
                  c.nop
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  c.srai       a3, 9
                  c.and        a3, s0
                  srli         a3, s8, 11
                  mulhsu       s1, s4, sp
                  c.xor        a5, s0
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  sll          a5, s3, s8
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  c.li         t6, 20
                  c.add        s7, s6
                  or           t4, a3, a3
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  sub          s9, s5, s6
                  nop
                  c.addi       s2, 16
                  sltu         s10, s9, s8
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  c.nop
                  c.xor        a5, s0
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  mul          s6, a0, s0
                  c.or         a3, s1
                  nop
                  sra          a3, s6, t4
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  sll          a5, s3, s8
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  nop
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  add          s5, s8, a6
                  c.lui        s0, 15
                  add          s5, s8, a6
                  ori          a2, a1, -1711
                  remu         t0, s7, s1
                  or           t4, a3, a3
                  c.srli       a0, 18
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  andi         s5, tp, -69
                  srli         a3, s8, 11
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  c.mv         s8, t5
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  rem          a4, s2, a7
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  and          s6, gp, s0
                  lui          s0, 955933
                  c.or         a3, s1
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  c.mv         s8, t5
                  c.add        s7, s6
                  xori         t5, s5, -792
                  nop
                  c.srai       a3, 9
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  c.or         a3, s1
                  srl          s2, s1, sp
                  nop
                  sll          a5, s3, s8
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  c.add        s7, s6
                  or           t4, a3, a3
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  c.andi       a5, 16
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  auipc        tp, 400075
                  c.and        a3, s0
                  divu         s1, s4, a4
                  nop
                  c.srai       a3, 9
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  c.and        a3, s0
                  srl          s2, s1, sp
                  c.or         a3, s1
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  div          a2, t1, a7
                  c.and        a3, s0
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  lui          s0, 955933
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  c.add        s7, s6
                  c.xor        a5, s0
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  c.and        a3, s0
                  ori          a2, a1, -1711
                  c.sub        s0, a4
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  mulhu        a1, t1, t5
                  div          a2, t1, a7
                  c.or         a3, s1
                  c.andi       a5, 16
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  c.add        s7, s6
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  auipc        tp, 400075
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  c.slli       s8, 9
                  lui          s0, 955933
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  sra          a3, s6, t4
                  c.add        s7, s6
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  andi         s5, tp, -69
                  mul          s6, a0, s0
                  sra          a3, s6, t4
                  nop
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  c.or         a3, s1
                  srai         s6, s3, 24
                  remu         t0, s7, s1
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  sra          a3, s6, t4
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  nop
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  c.nop
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  c.mv         s8, t5
                  c.li         t6, 20
                  nop
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  c.xor        a5, s0
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  srai         s6, s3, 24
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  mulhu        a1, t1, t5
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  c.nop
                  add          s5, s8, a6
                  c.srai       a3, 9
                  c.addi       s2, 16
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  c.srli       a0, 18
                  c.li         t6, 20
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  c.sub        s0, a4
                  c.sub        s0, a4
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  mulh         s9, s8, gp
                  c.and        a3, s0
                  c.xor        a5, s0
                  srl          s2, s1, sp
                  slt          t6, a0, sp
                  mulhsu       s1, s4, sp
                  rem          a4, s2, a7
                  c.add        s7, s6
                  xor          t5, s1, a7
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  c.add        s7, s6
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  andi         s5, tp, -69
                  srl          s2, s1, sp
                  c.slli       s8, 9
                  sub          s9, s5, s6
                  slt          t6, a0, sp
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  lui          s0, 955933
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  srli         a3, s8, 11
                  c.srai       a3, 9
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  lui          s0, 955933
                  sub          s9, s5, s6
                  c.slli       s8, 9
                  c.nop
                  c.li         t6, 20
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  or           t4, a3, a3
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  c.srai       a3, 9
                  c.srli       a0, 18
                  lui          s0, 955933
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  c.and        a3, s0
                  addi         zero, t6, 2029
                  mulhsu       s1, s4, sp
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  c.add        s7, s6
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  c.lui        s0, 15
                  lui          s0, 955933
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  c.xor        a5, s0
                  c.or         a3, s1
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  srai         s6, s3, 24
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  c.sub        s0, a4
                  c.li         t6, 20
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  xori         t5, s5, -792
                  nop
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  lui          s0, 955933
                  auipc        tp, 400075
                  or           t4, a3, a3
                  lui          s0, 955933
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  srli         a3, s8, 11
                  c.mv         s8, t5
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  slli         t4, t3, 27
                  or           t4, a3, a3
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  nop
                  c.mv         s8, t5
                  srl          s2, s1, sp
                  sub          s9, s5, s6
                  lui          s0, 955933
                  slli         t4, t3, 27
                  or           t4, a3, a3
                  and          s6, gp, s0
                  c.srai       a3, 9
                  slti         s8, ra, -2031
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  sltiu        zero, gp, -198
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  c.add        s7, s6
                  andi         s5, tp, -69
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  remu         t0, s7, s1
                  div          a2, t1, a7
                  slli         t4, t3, 27
                  div          a2, t1, a7
                  c.nop
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  c.and        a3, s0
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  mulhsu       s1, s4, sp
                  c.srli       a0, 18
                  auipc        tp, 400075
                  c.addi       s2, 16
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  or           t4, a3, a3
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  and          s6, gp, s0
                  c.nop
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  lui          s0, 955933
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  nop
                  srl          s2, s1, sp
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  srl          s2, s1, sp
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  sra          a3, s6, t4
                  lui          s0, 955933
                  divu         s1, s4, a4
                  c.nop
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  c.andi       a5, 16
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  c.mv         s8, t5
                  srl          s2, s1, sp
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  c.or         a3, s1
                  lui          s0, 955933
                  c.or         a3, s1
                  remu         t0, s7, s1
                  c.or         a3, s1
                  add          s5, s8, a6
                  c.srai       a3, 9
                  c.or         a3, s1
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  sltiu        zero, gp, -198
                  srai         s6, s3, 24
                  and          s6, gp, s0
                  sll          a5, s3, s8
                  xor          t5, s1, a7
                  c.andi       a5, 16
                  c.srli       a0, 18
                  c.andi       a5, 16
                  c.li         t6, 20
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  c.slli       s8, 9
                  sra          a3, s6, t4
                  nop
                  c.add        s7, s6
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  c.xor        a5, s0
                  slt          t6, a0, sp
                  c.nop
                  c.xor        a5, s0
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  c.srli       a0, 18
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  c.andi       a5, 16
                  divu         s1, s4, a4
                  c.mv         s8, t5
                  c.mv         s8, t5
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  slt          t6, a0, sp
                  mulhu        a1, t1, t5
                  divu         s1, s4, a4
                  c.li         t6, 20
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  c.and        a3, s0
                  c.or         a3, s1
                  srli         a3, s8, 11
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  c.addi       s2, 16
                  c.addi       s2, 16
                  c.srli       a0, 18
                  c.nop
                  or           t4, a3, a3
                  c.nop
                  add          s5, s8, a6
                  c.nop
                  c.srai       a3, 9
                  nop
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  c.sub        s0, a4
                  c.lui        s0, 15
                  c.slli       s8, 9
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  c.li         t6, 20
                  slli         t4, t3, 27
                  c.mv         s8, t5
                  auipc        tp, 400075
                  c.or         a3, s1
                  c.slli       s8, 9
                  lui          s0, 955933
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  auipc        tp, 400075
                  mulh         s9, s8, gp
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  c.and        a3, s0
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  c.lui        s0, 15
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  c.nop
                  ori          a2, a1, -1711
                  slti         s8, ra, -2031
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  c.slli       s8, 9
                  mulhsu       s1, s4, sp
                  slti         s8, ra, -2031
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  srli         a3, s8, 11
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  lui          s0, 955933
                  c.sub        s0, a4
                  c.li         t6, 20
                  c.nop
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  c.and        a3, s0
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  c.nop
                  c.nop
                  nop
                  c.andi       a5, 16
                  and          s6, gp, s0
                  div          a2, t1, a7
                  andi         s5, tp, -69
                  mul          s6, a0, s0
                  srl          s2, s1, sp
                  slti         s8, ra, -2031
                  c.nop
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  and          s6, gp, s0
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  c.slli       s8, 9
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  addi         zero, t6, 2029
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  sltiu        zero, gp, -198
                  c.slli       s8, 9
                  c.lui        s0, 15
                  and          s6, gp, s0
                  c.sub        s0, a4
                  c.srai       a3, 9
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  c.lui        s0, 15
                  c.sub        s0, a4
                  nop
                  lui          s0, 955933
                  c.or         a3, s1
                  or           t4, a3, a3
                  c.lui        s0, 15
                  add          s5, s8, a6
                  lui          s0, 955933
                  lui          s0, 955933
                  c.srli       a0, 18
                  c.addi       s2, 16
                  auipc        tp, 400075
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  c.nop
                  mulh         s9, s8, gp
                  c.srai       a3, 9
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  c.li         t6, 20
                  c.or         a3, s1
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  c.add        s7, s6
                  c.or         a3, s1
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  addi         zero, t6, 2029
                  c.or         a3, s1
                  auipc        tp, 400075
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  auipc        tp, 400075
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  c.slli       s8, 9
                  ori          a2, a1, -1711
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  div          a2, t1, a7
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  sll          a5, s3, s8
                  c.nop
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  andi         s5, tp, -69
                  c.andi       a5, 16
                  c.and        a3, s0
                  srl          s2, s1, sp
                  divu         s1, s4, a4
                  c.li         t6, 20
                  mulh         s9, s8, gp
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  mulhsu       s1, s4, sp
                  sub          s9, s5, s6
                  c.srli       a0, 18
                  auipc        tp, 400075
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  srai         s6, s3, 24
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  c.andi       a5, 16
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  c.and        a3, s0
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  c.mv         s8, t5
                  li           s8, 0xf8411132 #start riscv_int_numeric_corner_stream_11
                  li           a1, 0xffffffff
                  li           s6, 0x0
                  li           s11, 0xffffffff
                  li           a0, 0x0
                  li           a7, 0xffffffff
                  li           s1, 0x80000000
                  li           s9, 0x3564b15c
                  li           s0, 0xffffffff
                  li           t5, 0x80000000
                  add          a1, s11, s0
                  addi         s0, s8, 2029
                  sub          s9, s6, s8
                  divu         s11, a7, s6
                  sub          s9, s6, s8
                  add          a1, s11, s0
                  mulhu        a0, s8, s0
                  mulh         s9, s11, a1
                  auipc        a1, 400075
                  mulh         s9, s11, a1
                  addi         s0, s8, 2029
                  addi         s0, s8, 2029
                  mul          a7, s11, s11
                  auipc        a1, 400075
                  divu         s11, a7, s6
                  rem          s1, a0, s1
                  add          a1, s11, s0
                  mulhsu       s11, a7, a0
                  mulh         s9, s11, a1
                  mulhu        a0, s8, s0 #end riscv_int_numeric_corner_stream_11
                  c.or         a3, s1
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  div          a2, t1, a7
                  c.li         t6, 20
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  lui          s0, 955933
                  lui          s0, 955933
                  rem          a4, s2, a7
                  c.addi       s2, 16
                  c.xor        a5, s0
                  lui          s0, 955933
                  c.nop
                  sltiu        zero, gp, -198
                  sltiu        zero, gp, -198
                  c.sub        s0, a4
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  c.nop
                  mulhsu       s1, s4, sp
                  mul          s6, a0, s0
                  sltu         s10, s9, s8
                  slti         s8, ra, -2031
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  xori         t5, s5, -792
                  lui          s0, 955933
                  lui          s0, 955933
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  c.nop
                  c.sub        s0, a4
                  lui          s0, 955933
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  c.or         a3, s1
                  mulhu        a1, t1, t5
                  lui          s0, 955933
                  c.lui        s0, 15
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  c.srli       a0, 18
                  mulhsu       s1, s4, sp
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  auipc        tp, 400075
                  div          a2, t1, a7
                  c.or         a3, s1
                  sltiu        zero, gp, -198
                  c.add        s7, s6
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  remu         t0, s7, s1
                  sltu         s10, s9, s8
                  sll          a5, s3, s8
                  and          s6, gp, s0
                  and          s6, gp, s0
                  lui          s0, 955933
                  c.or         a3, s1
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  addi         zero, t6, 2029
                  c.li         t6, 20
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  andi         s5, tp, -69
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  xori         t5, s5, -792
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  c.or         a3, s1
                  c.andi       a5, 16
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.nop
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  c.sub        s0, a4
                  c.xor        a5, s0
                  sra          a3, s6, t4
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  c.srli       a0, 18
                  c.mv         s8, t5
                  c.and        a3, s0
                  c.li         t6, 20
                  nop
                  li           t1, 0xffffffff #start riscv_int_numeric_corner_stream_36
                  li           t4, 0x0
                  li           tp, 0xffffffff
                  li           s5, 0x80000000
                  li           s11, 0x4be52e18
                  li           a7, 0x80000000
                  li           s3, 0xceb68d30
                  li           s10, 0x0
                  li           ra, 0x0
                  li           s9, 0xffffffff
                  rem          tp, t1, tp
                  mulh         s10, s11, a7
                  lui          s10, 955933
                  auipc        a7, 400075
                  sub          s10, s5, s9
                  mulhsu       s11, s3, t1
                  mulhu        t1, s9, ra
                  sub          s10, s5, s9
                  mulhu        t1, s9, ra
                  sub          s10, s5, s9
                  lui          s10, 955933
                  remu         s3, s10, t4
                  lui          s10, 955933
                  remu         s3, s10, t4
                  nop
                  lui          s10, 955933
                  rem          tp, t1, tp
                  mulhsu       s11, s3, t1
                  mulh         s10, s11, a7
                  nop
                  mulhsu       s11, s3, t1 #end riscv_int_numeric_corner_stream_36
                  sltu         s10, s9, s8
                  c.srai       a3, 9
                  c.or         a3, s1
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  ori          a2, a1, -1711
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  c.or         a3, s1
                  c.srli       a0, 18
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  c.srli       a0, 18
                  xori         t5, s5, -792
                  c.srli       a0, 18
                  add          s5, s8, a6
                  c.nop
                  mul          s6, a0, s0
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  c.li         t6, 20
                  add          s5, s8, a6
                  andi         s5, tp, -69
                  sll          a5, s3, s8
                  c.or         a3, s1
                  mulhu        a1, t1, t5
                  c.addi       s2, 16
                  and          s6, gp, s0
                  c.slli       s8, 9
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  c.addi       s2, 16
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  c.li         t6, 20
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  c.xor        a5, s0
                  remu         t0, s7, s1
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  c.and        a3, s0
                  c.srai       a3, 9
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  nop
                  and          s6, gp, s0
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  c.sub        s0, a4
                  c.nop
                  c.li         t6, 20
                  c.sub        s0, a4
                  c.sub        s0, a4
                  c.li         t6, 20
                  mulhu        a1, t1, t5
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  sub          s9, s5, s6
                  and          s6, gp, s0
                  c.srai       a3, 9
                  c.srai       a3, 9
                  slt          t6, a0, sp
                  xor          t5, s1, a7
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  c.lui        s0, 15
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  c.xor        a5, s0
                  c.xor        a5, s0
                  divu         s1, s4, a4
                  rem          a4, s2, a7
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  nop
                  c.nop
                  slti         s8, ra, -2031
                  slt          t6, a0, sp
                  nop
                  mulh         s9, s8, gp
                  slti         s8, ra, -2031
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.slli       s8, 9
                  c.srli       a0, 18
                  c.addi       s2, 16
                  c.mv         s8, t5
                  lui          s0, 955933
                  add          s5, s8, a6
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  c.and        a3, s0
                  c.srli       a0, 18
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  rem          a4, s2, a7
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  c.srai       a3, 9
                  and          s6, gp, s0
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  slti         s8, ra, -2031
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  c.mv         s8, t5
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  c.nop
                  sll          a5, s3, s8
                  c.and        a3, s0
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  c.or         a3, s1
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  auipc        tp, 400075
                  slti         s8, ra, -2031
                  c.nop
                  slli         t4, t3, 27
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  c.slli       s8, 9
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  mulhu        a1, t1, t5
                  mulh         s9, s8, gp
                  mulhsu       s1, s4, sp
                  c.nop
                  auipc        tp, 400075
                  c.nop
                  remu         t0, s7, s1
                  mulhsu       s1, s4, sp
                  add          s5, s8, a6
                  or           t4, a3, a3
                  mul          s6, a0, s0
                  c.li         t6, 20
                  sra          a3, s6, t4
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  rem          a4, s2, a7
                  slli         t4, t3, 27
                  mulh         s9, s8, gp
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  c.li         t6, 20
                  c.nop
                  lui          s0, 955933
                  lui          s0, 955933
                  remu         t0, s7, s1
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  c.srli       a0, 18
                  c.lui        s0, 15
                  rem          a4, s2, a7
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  c.lui        s0, 15
                  add          s5, s8, a6
                  srai         s6, s3, 24
                  slli         t4, t3, 27
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  c.andi       a5, 16
                  c.srli       a0, 18
                  c.and        a3, s0
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  lui          s0, 955933
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  mulhu        a1, t1, t5
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  auipc        tp, 400075
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  c.andi       a5, 16
                  srli         a3, s8, 11
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  c.andi       a5, 16
                  c.srai       a3, 9
                  c.srai       a3, 9
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  c.lui        s0, 15
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  c.slli       s8, 9
                  rem          a4, s2, a7
                  or           t4, a3, a3
                  divu         s1, s4, a4
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  slt          t6, a0, sp
                  c.sub        s0, a4
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  sltiu        zero, gp, -198
                  nop
                  auipc        tp, 400075
                  c.nop
                  c.andi       a5, 16
                  nop
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  slt          t6, a0, sp
                  lui          s0, 955933
                  or           t4, a3, a3
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  divu         s1, s4, a4
                  mulhsu       s1, s4, sp
                  add          s5, s8, a6
                  c.xor        a5, s0
                  auipc        tp, 400075
                  andi         s5, tp, -69
                  slt          t6, a0, sp
                  mulhsu       s1, s4, sp
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  lui          s0, 955933
                  c.lui        s0, 15
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  lui          s0, 955933
                  mul          s6, a0, s0
                  c.add        s7, s6
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  c.or         a3, s1
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  rem          a4, s2, a7
                  c.andi       a5, 16
                  srl          s2, s1, sp
                  andi         s5, tp, -69
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  addi         zero, t6, 2029
                  srl          s2, s1, sp
                  divu         s1, s4, a4
                  srl          s2, s1, sp
                  c.lui        s0, 15
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  xori         t5, s5, -792
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  div          a2, t1, a7
                  c.srai       a3, 9
                  c.lui        s0, 15
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.and        a3, s0
                  c.lui        s0, 15
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  sltu         s10, s9, s8
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  c.addi       s2, 16
                  c.li         t6, 20
                  andi         s5, tp, -69
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  mulhsu       s1, s4, sp
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  rem          a4, s2, a7
                  c.and        a3, s0
                  auipc        tp, 400075
                  nop
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  sltiu        zero, gp, -198
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  c.srli       a0, 18
                  c.and        a3, s0
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  c.slli       s8, 9
                  or           t4, a3, a3
                  mulhsu       s1, s4, sp
                  c.xor        a5, s0
                  c.sub        s0, a4
                  c.slli       s8, 9
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  or           t4, a3, a3
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  c.srai       a3, 9
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  c.andi       a5, 16
                  c.srai       a3, 9
                  and          s6, gp, s0
                  c.nop
                  xori         t5, s5, -792
                  c.add        s7, s6
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  c.and        a3, s0
                  c.li         t6, 20
                  c.nop
                  mulhu        a1, t1, t5
                  div          a2, t1, a7
                  sltiu        zero, gp, -198
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.slli       s8, 9
                  rem          a4, s2, a7
                  c.srai       a3, 9
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  c.andi       a5, 16
                  c.srai       a3, 9
                  srl          s2, s1, sp
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  divu         s1, s4, a4
                  c.addi       s2, 16
                  auipc        tp, 400075
                  c.or         a3, s1
                  c.lui        s0, 15
                  sll          a5, s3, s8
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  c.addi       s2, 16
                  c.slli       s8, 9
                  or           t4, a3, a3
                  or           t4, a3, a3
                  c.add        s7, s6
                  add          s5, s8, a6
                  c.and        a3, s0
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  c.mv         s8, t5
                  auipc        tp, 400075
                  c.li         t6, 20
                  c.addi       s2, 16
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  ori          a2, a1, -1711
                  c.and        a3, s0
                  sltu         s10, s9, s8
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  c.or         a3, s1
                  c.andi       a5, 16
                  nop
                  c.addi       s2, 16
                  slt          t6, a0, sp
                  divu         s1, s4, a4
                  c.or         a3, s1
                  mul          s6, a0, s0
                  c.sub        s0, a4
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  c.addi       s2, 16
                  and          s6, gp, s0
                  lui          s0, 955933
                  mul          s6, a0, s0
                  slli         t4, t3, 27
                  mulhsu       s1, s4, sp
                  remu         t0, s7, s1
                  c.li         t6, 20
                  sll          a5, s3, s8
                  c.add        s7, s6
                  divu         s1, s4, a4
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  c.or         a3, s1
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  nop
                  div          a2, t1, a7
                  c.sub        s0, a4
                  c.nop
                  addi         zero, t6, 2029
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  c.addi       s2, 16
                  auipc        tp, 400075
                  c.andi       a5, 16
                  c.andi       a5, 16
                  lui          s0, 955933
                  slli         t4, t3, 27
                  nop
                  c.addi       s2, 16
                  c.srli       a0, 18
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  auipc        tp, 400075
                  c.and        a3, s0
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  c.add        s7, s6
                  c.slli       s8, 9
                  c.nop
                  c.or         a3, s1
                  c.add        s7, s6
                  c.addi       s2, 16
                  lui          s0, 955933
                  c.srai       a3, 9
                  slt          t6, a0, sp
                  c.or         a3, s1
                  mulh         s9, s8, gp
                  srli         a3, s8, 11
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  xor          t5, s1, a7
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  c.nop
                  c.and        a3, s0
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  slti         s8, ra, -2031
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  c.addi       s2, 16
                  mulhu        a1, t1, t5
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  c.or         a3, s1
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  c.sub        s0, a4
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  nop
                  or           t4, a3, a3
                  srl          s2, s1, sp
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  c.or         a3, s1
                  c.sub        s0, a4
                  c.nop
                  c.or         a3, s1
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  c.nop
                  xori         t5, s5, -792
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  slti         s8, ra, -2031
                  nop
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  addi         zero, t6, 2029
                  srli         a3, s8, 11
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  mulh         s9, s8, gp
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  c.srli       a0, 18
                  mulhsu       s1, s4, sp
                  c.sub        s0, a4
                  slti         s8, ra, -2031
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  c.srli       a0, 18
                  nop
                  c.andi       a5, 16
                  c.and        a3, s0
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  c.sub        s0, a4
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  xori         t5, s5, -792
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  div          a2, t1, a7
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  c.and        a3, s0
                  slt          t6, a0, sp
                  c.xor        a5, s0
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  and          s6, gp, s0
                  c.li         t6, 20
                  mul          s6, a0, s0
                  c.andi       a5, 16
                  add          s5, s8, a6
                  c.andi       a5, 16
                  c.mv         s8, t5
                  c.slli       s8, 9
                  or           t4, a3, a3
                  rem          a4, s2, a7
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  c.and        a3, s0
                  slli         t4, t3, 27
                  c.and        a3, s0
                  c.and        a3, s0
                  srl          s2, s1, sp
                  c.li         t6, 20
                  mulh         s9, s8, gp
                  c.xor        a5, s0
                  c.mv         s8, t5
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  c.add        s7, s6
                  add          s5, s8, a6
                  srai         s6, s3, 24
                  mulh         s9, s8, gp
                  auipc        tp, 400075
                  c.add        s7, s6
                  srl          s2, s1, sp
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  c.sub        s0, a4
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  slli         t4, t3, 27
                  and          s6, gp, s0
                  c.srai       a3, 9
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  add          s5, s8, a6
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  sltiu        zero, gp, -198
                  div          a2, t1, a7
                  c.slli       s8, 9
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  c.addi       s2, 16
                  divu         s1, s4, a4
                  nop
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  c.sub        s0, a4
                  addi         zero, t6, 2029
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  auipc        tp, 400075
                  xor          t5, s1, a7
                  lui          s0, 955933
                  c.or         a3, s1
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  sub          s9, s5, s6
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  xori         t5, s5, -792
                  mulhu        a1, t1, t5
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  c.srai       a3, 9
                  addi         zero, t6, 2029
                  c.or         a3, s1
                  lui          s0, 955933
                  rem          a4, s2, a7
                  mulhu        a1, t1, t5
                  c.add        s7, s6
                  mulhu        a1, t1, t5
                  slt          t6, a0, sp
                  srl          s2, s1, sp
                  mulh         s9, s8, gp
                  c.slli       s8, 9
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  c.xor        a5, s0
                  c.or         a3, s1
                  c.lui        s0, 15
                  remu         t0, s7, s1
                  div          a2, t1, a7
                  or           t4, a3, a3
                  and          s6, gp, s0
                  or           t4, a3, a3
                  xori         t5, s5, -792
                  sltiu        zero, gp, -198
                  remu         t0, s7, s1
                  c.addi       s2, 16
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  divu         s1, s4, a4
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  c.srli       a0, 18
                  slt          t6, a0, sp
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  lui          s0, 955933
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  sll          a5, s3, s8
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  c.add        s7, s6
                  lui          s0, 955933
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  rem          a4, s2, a7
                  c.add        s7, s6
                  srl          s2, s1, sp
                  c.nop
                  sltiu        zero, gp, -198
                  remu         t0, s7, s1
                  sltu         s10, s9, s8
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  lui          s0, 955933
                  srli         a3, s8, 11
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  sltiu        zero, gp, -198
                  c.li         t6, 20
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  c.li         t6, 20
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  lui          s0, 955933
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  sll          a5, s3, s8
                  c.li         t6, 20
                  c.and        a3, s0
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  sll          a5, s3, s8
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  c.and        a3, s0
                  remu         t0, s7, s1
                  c.addi       s2, 16
                  lui          s0, 955933
                  c.mv         s8, t5
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  c.srli       a0, 18
                  c.andi       a5, 16
                  ori          a2, a1, -1711
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  c.and        a3, s0
                  c.sub        s0, a4
                  c.sub        s0, a4
                  c.xor        a5, s0
                  c.srai       a3, 9
                  c.add        s7, s6
                  remu         t0, s7, s1
                  mulhsu       s1, s4, sp
                  c.addi       s2, 16
                  c.xor        a5, s0
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  lui          s0, 955933
                  auipc        tp, 400075
                  and          s6, gp, s0
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  c.slli       s8, 9
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  c.or         a3, s1
                  srli         a3, s8, 11
                  c.add        s7, s6
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  sra          a3, s6, t4
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  c.sub        s0, a4
                  sub          s9, s5, s6
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  c.slli       s8, 9
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  c.addi       s2, 16
                  c.or         a3, s1
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  c.nop
                  c.li         t6, 20
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  and          s6, gp, s0
                  srai         s6, s3, 24
                  c.add        s7, s6
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.xor        a5, s0
                  slti         s8, ra, -2031
                  lui          s0, 955933
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  nop
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  divu         s1, s4, a4
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  sll          a5, s3, s8
                  c.and        a3, s0
                  slt          t6, a0, sp
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  c.nop
                  sub          s9, s5, s6
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  addi         zero, t6, 2029
                  c.mv         s8, t5
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  srli         a3, s8, 11
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  remu         t0, s7, s1
                  srl          s2, s1, sp
                  mulhu        a1, t1, t5
                  c.or         a3, s1
                  auipc        tp, 400075
                  srai         s6, s3, 24
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  c.slli       s8, 9
                  rem          a4, s2, a7
                  div          a2, t1, a7
                  add          s5, s8, a6
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  c.li         t6, 20
                  c.li         t6, 20
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  li           t2, 0x80000000 #start riscv_int_numeric_corner_stream_5
                  li           a7, 0x80000000
                  li           t5, 0xfae8291e
                  li           tp, 0xffffffff
                  li           a0, 0xffffffff
                  li           t1, 0x32ff448e
                  li           t6, 0xf4a80f7a
                  li           s11, 0xffffffff
                  li           s9, 0xffffffff
                  li           t4, 0xffffffff
                  mulhsu       t5, a7, t2
                  auipc        a0, 400075
                  remu         a7, t4, t6
                  auipc        a0, 400075
                  nop
                  auipc        a0, 400075
                  addi         tp, s11, 2029
                  mulh         t4, t5, a0
                  nop
                  nop
                  mulhsu       t5, a7, t2
                  addi         tp, s11, 2029
                  divu         t5, a7, s9
                  nop
                  auipc        a0, 400075
                  mul          a7, t5, t5 #end riscv_int_numeric_corner_stream_5
                  addi         zero, t6, 2029
                  c.nop
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  remu         t0, s7, s1
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  addi         zero, t6, 2029
                  nop
                  mulh         s9, s8, gp
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  lui          s0, 955933
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  c.add        s7, s6
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  remu         t0, s7, s1
                  c.srai       a3, 9
                  c.mv         s8, t5
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  divu         s1, s4, a4
                  mulh         s9, s8, gp
                  sltiu        zero, gp, -198
                  sll          a5, s3, s8
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  srai         s6, s3, 24
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  lui          s0, 955933
                  add          s5, s8, a6
                  c.nop
                  sll          a5, s3, s8
                  or           t4, a3, a3
                  lui          s0, 955933
                  sra          a3, s6, t4
                  c.andi       a5, 16
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  c.andi       a5, 16
                  divu         s1, s4, a4
                  slli         t4, t3, 27
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  sltiu        zero, gp, -198
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  c.nop
                  c.nop
                  sll          a5, s3, s8
                  c.slli       s8, 9
                  c.srai       a3, 9
                  c.li         t6, 20
                  c.andi       a5, 16
                  c.add        s7, s6
                  rem          a4, s2, a7
                  c.add        s7, s6
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  c.add        s7, s6
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  auipc        tp, 400075
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  lui          s0, 955933
                  c.add        s7, s6
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  remu         t0, s7, s1
                  c.and        a3, s0
                  remu         t0, s7, s1
                  c.nop
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  rem          a4, s2, a7
                  c.addi       s2, 16
                  srai         s6, s3, 24
                  mulhsu       s1, s4, sp
                  srli         a3, s8, 11
                  mul          s6, a0, s0
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  c.nop
                  c.nop
                  c.lui        s0, 15
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  addi         zero, t6, 2029
                  c.nop
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  c.addi       s2, 16
                  sltu         s10, s9, s8
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  add          s5, s8, a6
                  c.or         a3, s1
                  or           t4, a3, a3
                  c.addi       s2, 16
                  div          a2, t1, a7
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  c.srai       a3, 9
                  c.mv         s8, t5
                  c.lui        s0, 15
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  c.xor        a5, s0
                  div          a2, t1, a7
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  c.li         t6, 20
                  c.andi       a5, 16
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  c.add        s7, s6
                  nop
                  mul          s6, a0, s0
                  mulhsu       s1, s4, sp
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  xori         t5, s5, -792
                  mulhsu       s1, s4, sp
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  sra          a3, s6, t4
                  sra          a3, s6, t4
                  div          a2, t1, a7
                  c.andi       a5, 16
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  slti         s8, ra, -2031
                  srl          s2, s1, sp
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  mul          s6, a0, s0
                  c.li         t6, 20
                  c.nop
                  nop
                  sub          s9, s5, s6
                  andi         s5, tp, -69
                  c.li         t6, 20
                  c.xor        a5, s0
                  c.mv         s8, t5
                  slt          t6, a0, sp
                  c.and        a3, s0
                  nop
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  c.nop
                  div          a2, t1, a7
                  c.or         a3, s1
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  nop
                  c.add        s7, s6
                  auipc        tp, 400075
                  div          a2, t1, a7
                  c.add        s7, s6
                  c.addi       s2, 16
                  mulhu        a1, t1, t5
                  c.li         t6, 20
                  sltiu        zero, gp, -198
                  mul          s6, a0, s0
                  div          a2, t1, a7
                  srli         a3, s8, 11
                  or           t4, a3, a3
                  sll          a5, s3, s8
                  c.xor        a5, s0
                  srai         s6, s3, 24
                  add          s5, s8, a6
                  addi         zero, t6, 2029
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  rem          a4, s2, a7
                  lui          s0, 955933
                  c.srai       a3, 9
                  c.xor        a5, s0
                  c.add        s7, s6
                  c.addi       s2, 16
                  xor          t5, s1, a7
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  remu         t0, s7, s1
                  slti         s8, ra, -2031
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  c.andi       a5, 16
                  c.and        a3, s0
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  mulh         s9, s8, gp
                  c.or         a3, s1
                  rem          a4, s2, a7
                  sltiu        zero, gp, -198
                  lui          s0, 955933
                  c.nop
                  c.and        a3, s0
                  remu         t0, s7, s1
                  slt          t6, a0, sp
                  c.or         a3, s1
                  c.srli       a0, 18
                  divu         s1, s4, a4
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  or           t4, a3, a3
                  c.li         t6, 20
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  c.add        s7, s6
                  add          s5, s8, a6
                  nop
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  slli         t4, t3, 27
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  c.lui        s0, 15
                  nop
                  lui          s0, 955933
                  c.andi       a5, 16
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  sra          a3, s6, t4
                  c.and        a3, s0
                  mul          s6, a0, s0
                  c.and        a3, s0
                  xor          t5, s1, a7
                  lui          s0, 955933
                  xor          t5, s1, a7
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  c.li         t6, 20
                  andi         s5, tp, -69
                  and          s6, gp, s0
                  srai         s6, s3, 24
                  sub          s9, s5, s6
                  nop
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  mulhsu       s1, s4, sp
                  add          s5, s8, a6
                  c.xor        a5, s0
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  c.and        a3, s0
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  c.srai       a3, 9
                  c.add        s7, s6
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  and          s6, gp, s0
                  add          s5, s8, a6
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  mulhsu       s1, s4, sp
                  remu         t0, s7, s1
                  c.xor        a5, s0
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  c.and        a3, s0
                  xori         t5, s5, -792
                  sra          a3, s6, t4
                  div          a2, t1, a7
                  c.addi       s2, 16
                  c.li         t6, 20
                  div          a2, t1, a7
                  mulhsu       s1, s4, sp
                  c.add        s7, s6
                  c.and        a3, s0
                  c.srli       a0, 18
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  c.nop
                  c.srli       a0, 18
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  srai         s6, s3, 24
                  c.sub        s0, a4
                  lui          s0, 955933
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  nop
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  c.nop
                  rem          a4, s2, a7
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  c.xor        a5, s0
                  c.sub        s0, a4
                  auipc        tp, 400075
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  c.lui        s0, 15
                  c.andi       a5, 16
                  srl          s2, s1, sp
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  nop
                  mul          s6, a0, s0
                  mulhu        a1, t1, t5
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  slt          t6, a0, sp
                  auipc        tp, 400075
                  mulhsu       s1, s4, sp
                  c.slli       s8, 9
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  mulhu        a1, t1, t5
                  srai         s6, s3, 24
                  sltu         s10, s9, s8
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  c.srai       a3, 9
                  or           t4, a3, a3
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  mulhu        a1, t1, t5
                  xori         t5, s5, -792
                  div          a2, t1, a7
                  slt          t6, a0, sp
                  add          s5, s8, a6
                  auipc        tp, 400075
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  c.xor        a5, s0
                  c.andi       a5, 16
                  srl          s2, s1, sp
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  divu         s1, s4, a4
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  sltiu        zero, gp, -198
                  and          s6, gp, s0
                  lui          s0, 955933
                  lui          s0, 955933
                  xor          t5, s1, a7
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  ori          a2, a1, -1711
                  sra          a3, s6, t4
                  c.add        s7, s6
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  srl          s2, s1, sp
                  nop
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  sll          a5, s3, s8
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  div          a2, t1, a7
                  auipc        tp, 400075
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  c.or         a3, s1
                  srai         s6, s3, 24
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  srl          s2, s1, sp
                  c.srai       a3, 9
                  nop
                  remu         t0, s7, s1
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  div          a2, t1, a7
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  div          a2, t1, a7
                  mulhu        a1, t1, t5
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  xori         t5, s5, -792
                  srai         s6, s3, 24
                  c.nop
                  add          s5, s8, a6
                  c.andi       a5, 16
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  c.nop
                  c.andi       a5, 16
                  c.and        a3, s0
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  c.srli       a0, 18
                  mul          s6, a0, s0
                  nop
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  add          s5, s8, a6
                  and          s6, gp, s0
                  mul          s6, a0, s0
                  c.and        a3, s0
                  slti         s8, ra, -2031
                  c.andi       a5, 16
                  or           t4, a3, a3
                  c.slli       s8, 9
                  lui          s0, 955933
                  sltu         s10, s9, s8
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  c.and        a3, s0
                  slt          t6, a0, sp
                  c.or         a3, s1
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  c.addi       s2, 16
                  mulh         s9, s8, gp
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  c.and        a3, s0
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  xor          t5, s1, a7
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  c.slli       s8, 9
                  div          a2, t1, a7
                  sltiu        zero, gp, -198
                  nop
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  c.andi       a5, 16
                  srli         a3, s8, 11
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  c.or         a3, s1
                  xori         t5, s5, -792
                  sll          a5, s3, s8
                  lui          s0, 955933
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  c.srai       a3, 9
                  c.xor        a5, s0
                  auipc        tp, 400075
                  c.xor        a5, s0
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  or           t4, a3, a3
                  xor          t5, s1, a7
                  c.xor        a5, s0
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  c.srli       a0, 18
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  lui          s0, 955933
                  c.add        s7, s6
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  xor          t5, s1, a7
                  add          s5, s8, a6
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.add        s7, s6
                  auipc        tp, 400075
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  slti         s8, ra, -2031
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  slt          t6, a0, sp
                  mulh         s9, s8, gp
                  srai         s6, s3, 24
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  mulh         s9, s8, gp
                  c.srai       a3, 9
                  c.add        s7, s6
                  c.lui        s0, 15
                  li           s3, 0x2bdd462c #start riscv_int_numeric_corner_stream_8
                  li           a7, 0xffffffff
                  li           a5, 0x9d2cd840
                  li           s10, 0x80000000
                  li           t2, 0xc138b2c0
                  li           s7, 0x0
                  li           s0, 0xf211621b
                  li           s8, 0x9ce3fcc6
                  li           ra, 0x0
                  li           a3, 0x83363f1f
                  nop
                  mulhsu       s8, a5, s0
                  auipc        a3, 400075
                  remu         a5, s7, s10
                  rem          t2, s0, t2
                  mulh         s7, s8, a3
                  auipc        a3, 400075
                  mulhu        s0, s3, ra
                  div          s3, s3, t2
                  auipc        a3, 400075
                  mulhu        s0, s3, ra
                  rem          t2, s0, t2
                  nop
                  nop
                  lui          s7, 955933
                  mulhsu       s8, a5, s0
                  mul          a5, s8, s8
                  mulh         s7, s8, a3 #end riscv_int_numeric_corner_stream_8
                  xori         t5, s5, -792
                  c.and        a3, s0
                  slli         t4, t3, 27
                  c.or         a3, s1
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  lui          s0, 955933
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  c.slli       s8, 9
                  or           t4, a3, a3
                  mulh         s9, s8, gp
                  mul          s6, a0, s0
                  add          s5, s8, a6
                  auipc        tp, 400075
                  sub          s9, s5, s6
                  c.add        s7, s6
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.andi       a5, 16
                  c.li         t6, 20
                  c.srai       a3, 9
                  c.sub        s0, a4
                  or           t4, a3, a3
                  c.li         t6, 20
                  sub          s9, s5, s6
                  div          a2, t1, a7
                  c.mv         s8, t5
                  sub          s9, s5, s6
                  c.sub        s0, a4
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  rem          a4, s2, a7
                  c.li         t6, 20
                  mulhsu       s1, s4, sp
                  c.srai       a3, 9
                  rem          a4, s2, a7
                  c.sub        s0, a4
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  c.mv         s8, t5
                  c.lui        s0, 15
                  lui          s0, 955933
                  c.or         a3, s1
                  ori          a2, a1, -1711
                  c.nop
                  and          s6, gp, s0
                  sll          a5, s3, s8
                  auipc        tp, 400075
                  and          s6, gp, s0
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  sltiu        zero, gp, -198
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  slt          t6, a0, sp
                  c.addi       s2, 16
                  ori          a2, a1, -1711
                  c.or         a3, s1
                  lui          s0, 955933
                  slli         t4, t3, 27
                  and          s6, gp, s0
                  mulh         s9, s8, gp
                  c.sub        s0, a4
                  lui          s0, 955933
                  slti         s8, ra, -2031
                  mulhu        a1, t1, t5
                  mulhsu       s1, s4, sp
                  c.and        a3, s0
                  slti         s8, ra, -2031
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  sltiu        zero, gp, -198
                  auipc        tp, 400075
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  c.sub        s0, a4
                  addi         zero, t6, 2029
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  add          s5, s8, a6
                  srli         a3, s8, 11
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  c.li         t6, 20
                  srli         a3, s8, 11
                  auipc        tp, 400075
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  lui          s0, 955933
                  add          s5, s8, a6
                  sltiu        zero, gp, -198
                  nop
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  c.srai       a3, 9
                  div          a2, t1, a7
                  c.li         t6, 20
                  slti         s8, ra, -2031
                  c.nop
                  c.srai       a3, 9
                  xori         t5, s5, -792
                  c.sub        s0, a4
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  c.sub        s0, a4
                  slt          t6, a0, sp
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  c.and        a3, s0
                  lui          s0, 955933
                  c.xor        a5, s0
                  c.li         t6, 20
                  sra          a3, s6, t4
                  mulhu        a1, t1, t5
                  c.or         a3, s1
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  c.addi       s2, 16
                  c.add        s7, s6
                  c.srai       a3, 9
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  srl          s2, s1, sp
                  rem          a4, s2, a7
                  c.srli       a0, 18
                  add          s5, s8, a6
                  c.andi       a5, 16
                  c.li         t6, 20
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  c.or         a3, s1
                  c.srai       a3, 9
                  lui          s0, 955933
                  c.andi       a5, 16
                  c.lui        s0, 15
                  xori         t5, s5, -792
                  c.xor        a5, s0
                  div          a2, t1, a7
                  li           t6, 0x80000000 #start riscv_int_numeric_corner_stream_28
                  li           s0, 0x80000000
                  li           a4, 0x0
                  li           a3, 0xa123a255
                  li           a5, 0xffffffff
                  li           t0, 0xffffffff
                  li           a0, 0x0
                  li           s8, 0x80000000
                  li           t2, 0x80000000
                  li           s10, 0x80000000
                  add          a0, s10, t0
                  mulhsu       s10, a3, s0
                  mulhu        s0, a5, t0
                  auipc        a0, 400075
                  add          a0, s10, t0
                  divu         s10, a3, a4
                  mulhsu       s10, a3, s0
                  sub          s8, a4, a5
                  divu         s10, a3, a4
                  divu         s10, a3, a4
                  mulh         s8, s10, a0
                  add          a0, s10, t0
                  mulhsu       s10, a3, s0
                  lui          s8, 955933
                  addi         t0, a5, 2029
                  mulhu        s0, a5, t0 #end riscv_int_numeric_corner_stream_28
                  div          a2, t1, a7
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  slti         s8, ra, -2031
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  andi         s5, tp, -69
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  c.mv         s8, t5
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  c.nop
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  sub          s9, s5, s6
                  rem          a4, s2, a7
                  c.xor        a5, s0
                  auipc        tp, 400075
                  c.li         t6, 20
                  nop
                  andi         s5, tp, -69
                  c.or         a3, s1
                  c.and        a3, s0
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  c.srai       a3, 9
                  remu         t0, s7, s1
                  lui          s0, 955933
                  xori         t5, s5, -792
                  sra          a3, s6, t4
                  c.or         a3, s1
                  c.lui        s0, 15
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  srl          s2, s1, sp
                  c.sub        s0, a4
                  c.srli       a0, 18
                  c.srai       a3, 9
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  mulhu        a1, t1, t5
                  c.sub        s0, a4
                  lui          s0, 955933
                  mulhsu       s1, s4, sp
                  c.add        s7, s6
                  rem          a4, s2, a7
                  add          s5, s8, a6
                  c.xor        a5, s0
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  c.nop
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  nop
                  c.andi       a5, 16
                  c.add        s7, s6
                  mulhsu       s1, s4, sp
                  sll          a5, s3, s8
                  sub          s9, s5, s6
                  rem          a4, s2, a7
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  mulhsu       s1, s4, sp
                  div          a2, t1, a7
                  xor          t5, s1, a7
                  c.add        s7, s6
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  c.and        a3, s0
                  divu         s1, s4, a4
                  c.slli       s8, 9
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  c.slli       s8, 9
                  c.nop
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  c.xor        a5, s0
                  c.nop
                  auipc        tp, 400075
                  rem          a4, s2, a7
                  nop
                  c.sub        s0, a4
                  and          s6, gp, s0
                  c.and        a3, s0
                  c.slli       s8, 9
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  c.and        a3, s0
                  srl          s2, s1, sp
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  c.slli       s8, 9
                  c.srai       a3, 9
                  c.li         t6, 20
                  c.li         t6, 20
                  andi         s5, tp, -69
                  nop
                  c.or         a3, s1
                  addi         zero, t6, 2029
                  xori         t5, s5, -792
                  slli         t4, t3, 27
                  and          s6, gp, s0
                  or           t4, a3, a3
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  sll          a5, s3, s8
                  xori         t5, s5, -792
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  divu         s1, s4, a4
                  xor          t5, s1, a7
                  c.li         t6, 20
                  nop
                  c.or         a3, s1
                  remu         t0, s7, s1
                  c.li         t6, 20
                  c.mv         s8, t5
                  li           s5, 0xbeeddb06 #start riscv_int_numeric_corner_stream_20
                  li           t6, 0x18492fc0
                  li           a7, 0xffffffff
                  li           a3, 0xffffffff
                  li           s10, 0x0
                  li           a0, 0x80000000
                  li           s3, 0x4aff312e
                  li           a6, 0x80000000
                  li           s1, 0xffffffff
                  li           gp, 0xffffffff
                  mulh         s5, s10, a3
                  remu         a6, s5, t6
                  mulhsu       s10, a6, a0
                  mulh         s5, s10, a3
                  div          s3, s3, s1
                  div          s3, s3, s1
                  mulhu        a0, s3, gp
                  mulh         s5, s10, a3
                  sub          s5, a7, s3
                  add          a3, s10, gp
                  divu         s10, a6, a7
                  auipc        a3, 400075
                  mulhu        a0, s3, gp
                  auipc        a3, 400075
                  auipc        a3, 400075
                  sub          s5, a7, s3
                  addi         gp, s3, 2029
                  lui          s5, 955933
                  add          a3, s10, gp
                  sub          s5, a7, s3
                  divu         s10, a6, a7
                  addi         gp, s3, 2029
                  lui          s5, 955933
                  divu         s10, a6, a7
                  rem          s1, a0, s1
                  addi         gp, s3, 2029 #end riscv_int_numeric_corner_stream_20
                  xori         t5, s5, -792
                  nop
                  c.sub        s0, a4
                  auipc        tp, 400075
                  nop
                  srai         s6, s3, 24
                  c.srli       a0, 18
                  and          s6, gp, s0
                  mulh         s9, s8, gp
                  c.sub        s0, a4
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  srai         s6, s3, 24
                  lui          s0, 955933
                  remu         t0, s7, s1
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  div          a2, t1, a7
                  c.li         t6, 20
                  add          s5, s8, a6
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  c.srai       a3, 9
                  nop
                  c.srai       a3, 9
                  c.add        s7, s6
                  c.sub        s0, a4
                  mul          s6, a0, s0
                  rem          a4, s2, a7
                  and          s6, gp, s0
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  and          s6, gp, s0
                  c.li         t6, 20
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  c.add        s7, s6
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  andi         s5, tp, -69
                  lui          s0, 955933
                  rem          a4, s2, a7
                  remu         t0, s7, s1
                  addi         zero, t6, 2029
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  c.mv         s8, t5
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  nop
                  c.addi       s2, 16
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  c.nop
                  sub          s9, s5, s6
                  lui          s0, 955933
                  mulh         s9, s8, gp
                  c.sub        s0, a4
                  and          s6, gp, s0
                  nop
                  lui          s0, 955933
                  andi         s5, tp, -69
                  lui          s0, 955933
                  xori         t5, s5, -792
                  srai         s6, s3, 24
                  c.li         t6, 20
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  ori          a2, a1, -1711
                  auipc        tp, 400075
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  c.addi       s2, 16
                  c.addi       s2, 16
                  c.or         a3, s1
                  nop
                  div          a2, t1, a7
                  auipc        tp, 400075
                  c.or         a3, s1
                  c.sub        s0, a4
                  div          a2, t1, a7
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  and          s6, gp, s0
                  slt          t6, a0, sp
                  nop
                  c.nop
                  auipc        tp, 400075
                  mulhsu       s1, s4, sp
                  c.mv         s8, t5
                  remu         t0, s7, s1
                  c.and        a3, s0
                  lui          s0, 955933
                  c.add        s7, s6
                  c.sub        s0, a4
                  c.lui        s0, 15
                  c.li         t6, 20
                  xori         t5, s5, -792
                  andi         s5, tp, -69
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  c.lui        s0, 15
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.srli       a0, 18
                  mulhsu       s1, s4, sp
                  c.or         a3, s1
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  lui          s0, 955933
                  nop
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  c.li         t6, 20
                  and          s6, gp, s0
                  divu         s1, s4, a4
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  or           t4, a3, a3
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  c.li         t6, 20
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  sltu         s10, s9, s8
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  sll          a5, s3, s8
                  c.li         t6, 20
                  xor          t5, s1, a7
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  auipc        tp, 400075
                  mul          s6, a0, s0
                  divu         s1, s4, a4
                  or           t4, a3, a3
                  c.andi       a5, 16
                  slt          t6, a0, sp
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  c.and        a3, s0
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  c.or         a3, s1
                  mulh         s9, s8, gp
                  xori         t5, s5, -792
                  srli         a3, s8, 11
                  remu         t0, s7, s1
                  auipc        tp, 400075
                  c.andi       a5, 16
                  rem          a4, s2, a7
                  c.slli       s8, 9
                  sltu         s10, s9, s8
                  c.srli       a0, 18
                  lui          s0, 955933
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  div          a2, t1, a7
                  c.xor        a5, s0
                  slli         t4, t3, 27
                  remu         t0, s7, s1
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  c.and        a3, s0
                  c.and        a3, s0
                  c.lui        s0, 15
                  c.sub        s0, a4
                  c.srli       a0, 18
                  addi         zero, t6, 2029
                  mul          s6, a0, s0
                  c.xor        a5, s0
                  c.mv         s8, t5
                  srli         a3, s8, 11
                  c.nop
                  srli         a3, s8, 11
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  c.add        s7, s6
                  c.mv         s8, t5
                  c.nop
                  srai         s6, s3, 24
                  c.nop
                  c.and        a3, s0
                  xor          t5, s1, a7
                  slli         t4, t3, 27
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  slt          t6, a0, sp
                  mulhu        a1, t1, t5
                  mul          s6, a0, s0
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  or           t4, a3, a3
                  srli         a3, s8, 11
                  srli         a3, s8, 11
                  c.slli       s8, 9
                  c.nop
                  andi         s5, tp, -69
                  addi         zero, t6, 2029
                  rem          a4, s2, a7
                  c.slli       s8, 9
                  sra          a3, s6, t4
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  c.sub        s0, a4
                  mulhsu       s1, s4, sp
                  add          s5, s8, a6
                  div          a2, t1, a7
                  c.li         t6, 20
                  add          s5, s8, a6
                  c.andi       a5, 16
                  c.li         t6, 20
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  c.mv         s8, t5
                  lui          s0, 955933
                  divu         s1, s4, a4
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  auipc        tp, 400075
                  or           t4, a3, a3
                  nop
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  c.srli       a0, 18
                  c.add        s7, s6
                  slt          t6, a0, sp
                  c.slli       s8, 9
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  slt          t6, a0, sp
                  c.or         a3, s1
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  ori          a2, a1, -1711
                  sub          s9, s5, s6
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  mul          s6, a0, s0
                  mul          s6, a0, s0
                  sltiu        zero, gp, -198
                  c.nop
                  andi         s5, tp, -69
                  xori         t5, s5, -792
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  slli         t4, t3, 27
                  sltiu        zero, gp, -198
                  c.slli       s8, 9
                  c.addi       s2, 16
                  addi         zero, t6, 2029
                  c.lui        s0, 15
                  mulhsu       s1, s4, sp
                  srli         a3, s8, 11
                  c.and        a3, s0
                  sub          s9, s5, s6
                  srl          s2, s1, sp
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  mulhsu       s1, s4, sp
                  sltu         s10, s9, s8
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  c.sub        s0, a4
                  c.slli       s8, 9
                  c.srli       a0, 18
                  remu         t0, s7, s1
                  c.srai       a3, 9
                  sltu         s10, s9, s8
                  divu         s1, s4, a4
                  c.srli       a0, 18
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  slt          t6, a0, sp
                  c.li         t6, 20
                  srai         s6, s3, 24
                  andi         s5, tp, -69
                  nop
                  sub          s9, s5, s6
                  c.or         a3, s1
                  c.nop
                  addi         zero, t6, 2029
                  ori          a2, a1, -1711
                  c.slli       s8, 9
                  mulhsu       s1, s4, sp
                  rem          a4, s2, a7
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  and          s6, gp, s0
                  c.andi       a5, 16
                  srl          s2, s1, sp
                  or           t4, a3, a3
                  c.or         a3, s1
                  c.addi       s2, 16
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  c.slli       s8, 9
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  c.xor        a5, s0
                  c.srai       a3, 9
                  c.srai       a3, 9
                  or           t4, a3, a3
                  ori          a2, a1, -1711
                  sltiu        zero, gp, -198
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  and          s6, gp, s0
                  addi         zero, t6, 2029
                  c.xor        a5, s0
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  lui          s0, 955933
                  andi         s5, tp, -69
                  lui          s0, 955933
                  ori          a2, a1, -1711
                  c.mv         s8, t5
                  c.li         t6, 20
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  mulh         s9, s8, gp
                  mulhu        a1, t1, t5
                  c.srai       a3, 9
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  sra          a3, s6, t4
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  divu         s1, s4, a4
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  srai         s6, s3, 24
                  c.li         t6, 20
                  or           t4, a3, a3
                  and          s6, gp, s0
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  c.xor        a5, s0
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  c.slli       s8, 9
                  add          s5, s8, a6
                  mul          s6, a0, s0
                  c.add        s7, s6
                  xori         t5, s5, -792
                  c.add        s7, s6
                  nop
                  c.srai       a3, 9
                  c.add        s7, s6
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  remu         t0, s7, s1
                  c.add        s7, s6
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  mulhu        a1, t1, t5
                  srli         a3, s8, 11
                  slti         s8, ra, -2031
                  c.lui        s0, 15
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  c.andi       a5, 16
                  c.add        s7, s6
                  nop
                  remu         t0, s7, s1
                  add          s5, s8, a6
                  srl          s2, s1, sp
                  c.lui        s0, 15
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  sltu         s10, s9, s8
                  mulhsu       s1, s4, sp
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  c.li         t6, 20
                  c.srli       a0, 18
                  c.lui        s0, 15
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  sub          s9, s5, s6
                  slti         s8, ra, -2031
                  slli         t4, t3, 27
                  mul          s6, a0, s0
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  c.slli       s8, 9
                  c.mv         s8, t5
                  slli         t4, t3, 27
                  lui          s0, 955933
                  add          s5, s8, a6
                  div          a2, t1, a7
                  nop
                  c.nop
                  lui          s0, 955933
                  sub          s9, s5, s6
                  rem          a4, s2, a7
                  c.slli       s8, 9
                  c.nop
                  c.mv         s8, t5
                  c.lui        s0, 15
                  c.or         a3, s1
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  c.sub        s0, a4
                  c.addi       s2, 16
                  c.mv         s8, t5
                  c.lui        s0, 15
                  c.sub        s0, a4
                  sub          s9, s5, s6
                  c.and        a3, s0
                  mul          s6, a0, s0
                  lui          s0, 955933
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  c.srai       a3, 9
                  c.srli       a0, 18
                  sltiu        zero, gp, -198
                  c.lui        s0, 15
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  srai         s6, s3, 24
                  c.slli       s8, 9
                  c.nop
                  c.nop
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  and          s6, gp, s0
                  c.lui        s0, 15
                  c.xor        a5, s0
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  divu         s1, s4, a4
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  lui          s0, 955933
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  slli         t4, t3, 27
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  srli         a3, s8, 11
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  mulhsu       s1, s4, sp
                  divu         s1, s4, a4
                  srli         a3, s8, 11
                  c.or         a3, s1
                  nop
                  c.slli       s8, 9
                  c.srai       a3, 9
                  slli         t4, t3, 27
                  c.addi       s2, 16
                  mul          s6, a0, s0
                  c.nop
                  c.mv         s8, t5
                  mulhu        a1, t1, t5
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  c.lui        s0, 15
                  slt          t6, a0, sp
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  c.add        s7, s6
                  c.nop
                  nop
                  c.nop
                  divu         s1, s4, a4
                  mulh         s9, s8, gp
                  sll          a5, s3, s8
                  sra          a3, s6, t4
                  srli         a3, s8, 11
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  slli         t4, t3, 27
                  c.srli       a0, 18
                  slt          t6, a0, sp
                  sll          a5, s3, s8
                  nop
                  srai         s6, s3, 24
                  slt          t6, a0, sp
                  c.slli       s8, 9
                  andi         s5, tp, -69
                  c.lui        s0, 15
                  sltu         s10, s9, s8
                  srli         a3, s8, 11
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  sltu         s10, s9, s8
                  c.or         a3, s1
                  rem          a4, s2, a7
                  xor          t5, s1, a7
                  rem          a4, s2, a7
                  c.li         t6, 20
                  srai         s6, s3, 24
                  rem          a4, s2, a7
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  c.nop
                  c.xor        a5, s0
                  ori          a2, a1, -1711
                  divu         s1, s4, a4
                  mul          s6, a0, s0
                  andi         s5, tp, -69
                  nop
                  lui          s0, 955933
                  sub          s9, s5, s6
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  c.sub        s0, a4
                  rem          a4, s2, a7
                  srli         a3, s8, 11
                  nop
                  add          s5, s8, a6
                  li           s8, 0x80000000 #start riscv_int_numeric_corner_stream_32
                  li           s3, 0x0
                  li           s2, 0x60384d1a
                  li           a4, 0x0
                  li           a5, 0x0
                  li           s11, 0xffffffff
                  li           s10, 0x80000000
                  li           a7, 0x80000000
                  li           a1, 0x80000000
                  li           a6, 0x80000000
                  sub          s8, s2, s3
                  rem          a4, a5, a4
                  auipc        a6, 400075
                  mulhsu       s10, a7, a5
                  mulhu        a5, s3, a1
                  auipc        a6, 400075
                  mulhsu       s10, a7, a5
                  addi         a1, s3, 2029
                  sub          s8, s2, s3
                  rem          a4, a5, a4
                  rem          a4, a5, a4
                  divu         s10, a7, s2
                  rem          a4, a5, a4
                  nop
                  nop
                  addi         a1, s3, 2029 #end riscv_int_numeric_corner_stream_32
                  ori          a2, a1, -1711
                  rem          a4, s2, a7
                  c.or         a3, s1
                  sltiu        zero, gp, -198
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  c.slli       s8, 9
                  c.lui        s0, 15
                  auipc        tp, 400075
                  sltu         s10, s9, s8
                  mulhsu       s1, s4, sp
                  nop
                  auipc        tp, 400075
                  c.lui        s0, 15
                  lui          s0, 955933
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  c.and        a3, s0
                  c.lui        s0, 15
                  xor          t5, s1, a7
                  slti         s8, ra, -2031
                  add          s5, s8, a6
                  sub          s9, s5, s6
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  divu         s1, s4, a4
                  mulhu        a1, t1, t5
                  sll          a5, s3, s8
                  c.srli       a0, 18
                  andi         s5, tp, -69
                  slli         t4, t3, 27
                  c.and        a3, s0
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  srai         s6, s3, 24
                  srli         a3, s8, 11
                  c.li         t6, 20
                  add          s5, s8, a6
                  nop
                  mulhsu       s1, s4, sp
                  mulh         s9, s8, gp
                  c.slli       s8, 9
                  slli         t4, t3, 27
                  auipc        tp, 400075
                  c.and        a3, s0
                  slt          t6, a0, sp
                  or           t4, a3, a3
                  xor          t5, s1, a7
                  lui          s0, 955933
                  nop
                  c.and        a3, s0
                  c.addi       s2, 16
                  c.addi       s2, 16
                  c.add        s7, s6
                  c.li         t6, 20
                  auipc        tp, 400075
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  xori         t5, s5, -792
                  lui          s0, 955933
                  c.and        a3, s0
                  mul          s6, a0, s0
                  c.srai       a3, 9
                  c.lui        s0, 15
                  addi         zero, t6, 2029
                  sltiu        zero, gp, -198
                  c.nop
                  srl          s2, s1, sp
                  ori          a2, a1, -1711
                  srli         a3, s8, 11
                  add          s5, s8, a6
                  c.add        s7, s6
                  c.add        s7, s6
                  or           t4, a3, a3
                  c.lui        s0, 15
                  lui          s0, 955933
                  sub          s9, s5, s6
                  c.mv         s8, t5
                  c.nop
                  nop
                  sub          s9, s5, s6
                  xori         t5, s5, -792
                  c.and        a3, s0
                  c.andi       a5, 16
                  c.mv         s8, t5
                  c.mv         s8, t5
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  c.srai       a3, 9
                  slti         s8, ra, -2031
                  c.lui        s0, 15
                  and          s6, gp, s0
                  sltu         s10, s9, s8
                  c.srai       a3, 9
                  srai         s6, s3, 24
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  divu         s1, s4, a4
                  c.lui        s0, 15
                  c.add        s7, s6
                  divu         s1, s4, a4
                  c.sub        s0, a4
                  c.andi       a5, 16
                  c.srli       a0, 18
                  c.or         a3, s1
                  srli         a3, s8, 11
                  lui          s0, 955933
                  sll          a5, s3, s8
                  ori          a2, a1, -1711
                  addi         zero, t6, 2029
                  srai         s6, s3, 24
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  xor          t5, s1, a7
                  c.add        s7, s6
                  sub          s9, s5, s6
                  slti         s8, ra, -2031
                  c.slli       s8, 9
                  c.addi       s2, 16
                  slli         t4, t3, 27
                  or           t4, a3, a3
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  slt          t6, a0, sp
                  divu         s1, s4, a4
                  divu         s1, s4, a4
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  c.add        s7, s6
                  c.slli       s8, 9
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  mul          s6, a0, s0
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  sub          s9, s5, s6
                  mulhu        a1, t1, t5
                  li           t2, 0x80000000 #start riscv_int_numeric_corner_stream_10
                  li           s5, 0xffffffff
                  li           t6, 0x0
                  li           a3, 0x1483bcdf
                  li           t1, 0x80000000
                  li           ra, 0x0
                  li           a0, 0xffffffff
                  li           t4, 0xffffffff
                  li           a7, 0x0
                  li           s8, 0xc237bcf6
                  rem          t1, t2, t1
                  auipc        a0, 400075
                  remu         a3, s8, t6
                  remu         a3, s8, t6
                  mulhu        t2, s5, ra
                  lui          s8, 955933
                  mul          a3, t4, t4
                  mul          a3, t4, t4
                  nop
                  mulhu        t2, s5, ra
                  mulhu        t2, s5, ra
                  add          a0, t4, ra
                  add          a0, t4, ra
                  divu         t4, a3, a7
                  addi         ra, s5, 2029
                  sub          s8, a7, s5 #end riscv_int_numeric_corner_stream_10
                  c.or         a3, s1
                  div          a2, t1, a7
                  srl          s2, s1, sp
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  and          s6, gp, s0
                  c.add        s7, s6
                  lui          s0, 955933
                  divu         s1, s4, a4
                  andi         s5, tp, -69
                  c.lui        s0, 15
                  c.lui        s0, 15
                  ori          a2, a1, -1711
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  c.add        s7, s6
                  andi         s5, tp, -69
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  c.li         t6, 20
                  remu         t0, s7, s1
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  c.nop
                  c.li         t6, 20
                  lui          s0, 955933
                  c.or         a3, s1
                  srai         s6, s3, 24
                  auipc        tp, 400075
                  lui          s0, 955933
                  mul          s6, a0, s0
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  mulh         s9, s8, gp
                  xor          t5, s1, a7
                  nop
                  sra          a3, s6, t4
                  c.xor        a5, s0
                  c.srai       a3, 9
                  lui          s0, 955933
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  c.srai       a3, 9
                  sltiu        zero, gp, -198
                  c.nop
                  c.mv         s8, t5
                  c.li         t6, 20
                  xori         t5, s5, -792
                  ori          a2, a1, -1711
                  auipc        tp, 400075
                  c.li         t6, 20
                  lui          s0, 955933
                  srai         s6, s3, 24
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  c.or         a3, s1
                  c.or         a3, s1
                  c.srli       a0, 18
                  and          s6, gp, s0
                  div          a2, t1, a7
                  div          a2, t1, a7
                  c.srli       a0, 18
                  srl          s2, s1, sp
                  addi         zero, t6, 2029
                  mulh         s9, s8, gp
                  c.or         a3, s1
                  andi         s5, tp, -69
                  c.nop
                  c.add        s7, s6
                  and          s6, gp, s0
                  auipc        tp, 400075
                  c.xor        a5, s0
                  sub          s9, s5, s6
                  c.and        a3, s0
                  c.xor        a5, s0
                  xori         t5, s5, -792
                  mul          s6, a0, s0
                  c.addi       s2, 16
                  c.xor        a5, s0
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  c.nop
                  div          a2, t1, a7
                  srai         s6, s3, 24
                  and          s6, gp, s0
                  c.li         t6, 20
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  addi         zero, t6, 2029
                  c.and        a3, s0
                  rem          a4, s2, a7
                  mul          s6, a0, s0
                  mulhu        a1, t1, t5
                  mulhu        a1, t1, t5
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  mulh         s9, s8, gp
                  auipc        tp, 400075
                  andi         s5, tp, -69
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  c.xor        a5, s0
                  auipc        tp, 400075
                  auipc        tp, 400075
                  and          s6, gp, s0
                  or           t4, a3, a3
                  mulh         s9, s8, gp
                  and          s6, gp, s0
                  auipc        tp, 400075
                  sll          a5, s3, s8
                  c.and        a3, s0
                  mulhu        a1, t1, t5
                  c.add        s7, s6
                  c.or         a3, s1
                  mulhsu       s1, s4, sp
                  lui          s0, 955933
                  rem          a4, s2, a7
                  auipc        tp, 400075
                  rem          a4, s2, a7
                  srli         a3, s8, 11
                  slt          t6, a0, sp
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  andi         s5, tp, -69
                  add          s5, s8, a6
                  xori         t5, s5, -792
                  srai         s6, s3, 24
                  c.mv         s8, t5
                  c.srai       a3, 9
                  mulhsu       s1, s4, sp
                  sra          a3, s6, t4
                  addi         zero, t6, 2029
                  c.xor        a5, s0
                  srli         a3, s8, 11
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  divu         s1, s4, a4
                  c.andi       a5, 16
                  c.and        a3, s0
                  and          s6, gp, s0
                  mulhsu       s1, s4, sp
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  c.addi       s2, 16
                  sltiu        zero, gp, -198
                  mul          s6, a0, s0
                  slli         t4, t3, 27
                  sltu         s10, s9, s8
                  or           t4, a3, a3
                  divu         s1, s4, a4
                  sll          a5, s3, s8
                  c.nop
                  xor          t5, s1, a7
                  c.addi       s2, 16
                  remu         t0, s7, s1
                  c.mv         s8, t5
                  sll          a5, s3, s8
                  c.andi       a5, 16
                  sltu         s10, s9, s8
                  nop
                  mulhu        a1, t1, t5
                  c.srli       a0, 18
                  sub          s9, s5, s6
                  c.li         t6, 20
                  andi         s5, tp, -69
                  and          s6, gp, s0
                  lui          s0, 955933
                  div          a2, t1, a7
                  divu         s1, s4, a4
                  sltiu        zero, gp, -198
                  c.and        a3, s0
                  c.and        a3, s0
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  auipc        tp, 400075
                  c.slli       s8, 9
                  c.sub        s0, a4
                  c.slli       s8, 9
                  c.and        a3, s0
                  c.li         t6, 20
                  c.sub        s0, a4
                  c.add        s7, s6
                  mulh         s9, s8, gp
                  c.add        s7, s6
                  c.lui        s0, 15
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  sll          a5, s3, s8
                  c.nop
                  c.addi       s2, 16
                  c.or         a3, s1
                  lui          s0, 955933
                  addi         zero, t6, 2029
                  c.andi       a5, 16
                  c.li         t6, 20
                  sltu         s10, s9, s8
                  auipc        tp, 400075
                  mul          s6, a0, s0
                  slt          t6, a0, sp
                  sra          a3, s6, t4
                  ori          a2, a1, -1711
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  c.addi       s2, 16
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  auipc        tp, 400075
                  srl          s2, s1, sp
                  c.xor        a5, s0
                  c.li         t6, 20
                  c.srai       a3, 9
                  xor          t5, s1, a7
                  c.sub        s0, a4
                  xori         t5, s5, -792
                  remu         t0, s7, s1
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  xori         t5, s5, -792
                  and          s6, gp, s0
                  srl          s2, s1, sp
                  and          s6, gp, s0
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  slli         t4, t3, 27
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  srli         a3, s8, 11
                  li           t0, 0xffffffff #start riscv_int_numeric_corner_stream_38
                  li           t2, 0x0
                  li           s8, 0x80000000
                  li           a4, 0xffffffff
                  li           a0, 0x80000000
                  li           a5, 0x80000000
                  li           gp, 0x29a2019b
                  li           s6, 0x80000000
                  li           ra, 0x80000000
                  li           s0, 0xb06f927b
                  div          a4, a4, gp
                  nop
                  remu         s0, a5, s8
                  nop
                  nop
                  sub          a5, a0, a4
                  div          a4, a4, gp
                  auipc        t2, 400075
                  mul          s0, s6, s6
                  auipc        t2, 400075
                  rem          gp, t0, gp
                  sub          a5, a0, a4
                  div          a4, a4, gp
                  addi         ra, a4, 2029
                  div          a4, a4, gp
                  rem          gp, t0, gp
                  add          t2, s6, ra
                  mulhu        t0, a4, ra
                  div          a4, a4, gp
                  addi         ra, a4, 2029
                  rem          gp, t0, gp
                  auipc        t2, 400075
                  mulhu        t0, a4, ra
                  mulh         a5, s6, t2
                  lui          a5, 955933 #end riscv_int_numeric_corner_stream_38
                  or           t4, a3, a3
                  add          s5, s8, a6
                  or           t4, a3, a3
                  nop
                  slli         t4, t3, 27
                  c.and        a3, s0
                  c.and        a3, s0
                  div          a2, t1, a7
                  divu         s1, s4, a4
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  auipc        tp, 400075
                  c.xor        a5, s0
                  mulhu        a1, t1, t5
                  xor          t5, s1, a7
                  div          a2, t1, a7
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  auipc        tp, 400075
                  mul          s6, a0, s0
                  auipc        tp, 400075
                  slti         s8, ra, -2031
                  nop
                  c.and        a3, s0
                  div          a2, t1, a7
                  c.add        s7, s6
                  sub          s9, s5, s6
                  auipc        tp, 400075
                  c.addi       s2, 16
                  auipc        tp, 400075
                  divu         s1, s4, a4
                  slt          t6, a0, sp
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  sra          a3, s6, t4
                  mulhsu       s1, s4, sp
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  c.andi       a5, 16
                  lui          s0, 955933
                  srli         a3, s8, 11
                  andi         s5, tp, -69
                  andi         s5, tp, -69
                  sra          a3, s6, t4
                  auipc        tp, 400075
                  c.and        a3, s0
                  div          a2, t1, a7
                  c.mv         s8, t5
                  xori         t5, s5, -792
                  c.srli       a0, 18
                  c.srli       a0, 18
                  add          s5, s8, a6
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  slti         s8, ra, -2031
                  rem          a4, s2, a7
                  srl          s2, s1, sp
                  slt          t6, a0, sp
                  rem          a4, s2, a7
                  slti         s8, ra, -2031
                  xor          t5, s1, a7
                  sll          a5, s3, s8
                  mulh         s9, s8, gp
                  sltu         s10, s9, s8
                  sub          s9, s5, s6
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  remu         t0, s7, s1
                  sll          a5, s3, s8
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  sltiu        zero, gp, -198
                  c.srli       a0, 18
                  mulhu        a1, t1, t5
                  srl          s2, s1, sp
                  mulhu        a1, t1, t5
                  add          s5, s8, a6
                  srai         s6, s3, 24
                  slti         s8, ra, -2031
                  slti         s8, ra, -2031
                  mulhsu       s1, s4, sp
                  divu         s1, s4, a4
                  c.add        s7, s6
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  c.srli       a0, 18
                  xor          t5, s1, a7
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.li         t6, 20
                  c.add        s7, s6
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  c.addi       s2, 16
                  sub          s9, s5, s6
                  divu         s1, s4, a4
                  c.sub        s0, a4
                  slli         t4, t3, 27
                  c.lui        s0, 15
                  c.srai       a3, 9
                  c.slli       s8, 9
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  rem          a4, s2, a7
                  auipc        tp, 400075
                  c.addi       s2, 16
                  c.srli       a0, 18
                  c.mv         s8, t5
                  c.addi       s2, 16
                  lui          s0, 955933
                  slt          t6, a0, sp
                  slti         s8, ra, -2031
                  lui          s0, 955933
                  c.lui        s0, 15
                  c.nop
                  c.add        s7, s6
                  addi         zero, t6, 2029
                  sub          s9, s5, s6
                  sub          s9, s5, s6
                  ori          a2, a1, -1711
                  sltu         s10, s9, s8
                  divu         s1, s4, a4
                  lui          s0, 955933
                  c.sub        s0, a4
                  sll          a5, s3, s8
                  remu         t0, s7, s1
                  c.sub        s0, a4
                  mulhu        a1, t1, t5
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  c.andi       a5, 16
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  and          s6, gp, s0
                  sltiu        zero, gp, -198
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  sltiu        zero, gp, -198
                  mulh         s9, s8, gp
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  ori          a2, a1, -1711
                  sll          a5, s3, s8
                  srai         s6, s3, 24
                  div          a2, t1, a7
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  mulhsu       s1, s4, sp
                  remu         t0, s7, s1
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  c.sub        s0, a4
                  c.andi       a5, 16
                  xor          t5, s1, a7
                  c.slli       s8, 9
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  srl          s2, s1, sp
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  nop
                  add          s5, s8, a6
                  c.sub        s0, a4
                  xori         t5, s5, -792
                  sub          s9, s5, s6
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  xori         t5, s5, -792
                  xori         t5, s5, -792
                  slt          t6, a0, sp
                  remu         t0, s7, s1
                  mul          s6, a0, s0
                  sltu         s10, s9, s8
                  c.add        s7, s6
                  srai         s6, s3, 24
                  and          s6, gp, s0
                  xor          t5, s1, a7
                  ori          a2, a1, -1711
                  c.lui        s0, 15
                  mulh         s9, s8, gp
                  or           t4, a3, a3
                  sra          a3, s6, t4
                  divu         s1, s4, a4
                  divu         s1, s4, a4
                  divu         s1, s4, a4
                  c.addi       s2, 16
                  mulhsu       s1, s4, sp
                  sra          a3, s6, t4
                  xori         t5, s5, -792
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  c.add        s7, s6
                  c.mv         s8, t5
                  sltu         s10, s9, s8
                  sll          a5, s3, s8
                  div          a2, t1, a7
                  sub          s9, s5, s6
                  mulh         s9, s8, gp
                  remu         t0, s7, s1
                  slti         s8, ra, -2031
                  or           t4, a3, a3
                  lui          s0, 955933
                  sra          a3, s6, t4
                  c.andi       a5, 16
                  sra          a3, s6, t4
                  nop
                  c.and        a3, s0
                  or           t4, a3, a3
                  add          s5, s8, a6
                  and          s6, gp, s0
                  c.sub        s0, a4
                  c.mv         s8, t5
                  div          a2, t1, a7
                  sltiu        zero, gp, -198
                  rem          a4, s2, a7
                  c.li         t6, 20
                  andi         s5, tp, -69
                  and          s6, gp, s0
                  and          s6, gp, s0
                  remu         t0, s7, s1
                  mulhu        a1, t1, t5
                  c.and        a3, s0
                  xori         t5, s5, -792
                  c.slli       s8, 9
                  mulh         s9, s8, gp
                  addi         zero, t6, 2029
                  c.addi       s2, 16
                  ori          a2, a1, -1711
                  c.nop
                  and          s6, gp, s0
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  andi         s5, tp, -69
                  c.or         a3, s1
                  ori          a2, a1, -1711
                  andi         s5, tp, -69
                  sub          s9, s5, s6
                  lui          s0, 955933
                  andi         s5, tp, -69
                  rem          a4, s2, a7
                  sltu         s10, s9, s8
                  nop
                  sra          a3, s6, t4
                  xor          t5, s1, a7
                  c.mv         s8, t5
                  slti         s8, ra, -2031
                  sll          a5, s3, s8
                  c.or         a3, s1
                  srai         s6, s3, 24
                  c.add        s7, s6
                  or           t4, a3, a3
                  andi         s5, tp, -69
                  c.srai       a3, 9
                  c.mv         s8, t5
                  add          s5, s8, a6
                  slt          t6, a0, sp
                  and          s6, gp, s0
                  c.li         t6, 20
                  slli         t4, t3, 27
                  sltiu        zero, gp, -198
                  c.li         t6, 20
                  c.addi       s2, 16
                  or           t4, a3, a3
                  c.xor        a5, s0
                  sltu         s10, s9, s8
                  sub          s9, s5, s6
                  mulhsu       s1, s4, sp
                  nop
                  c.srai       a3, 9
                  ori          a2, a1, -1711
                  c.nop
                  sub          s9, s5, s6
                  c.lui        s0, 15
                  c.srli       a0, 18
                  li           t2, 0x3cfa6ce8 #start riscv_int_numeric_corner_stream_34
                  li           a4, 0x26a9dc09
                  li           s8, 0x0
                  li           gp, 0xffffffff
                  li           t0, 0xffffffff
                  li           s10, 0xffffffff
                  li           s11, 0x0
                  li           ra, 0xffffffff
                  li           t1, 0xffffffff
                  li           a7, 0x0
                  add          t1, s10, ra
                  auipc        t1, 400075
                  mulh         s8, s10, t1
                  nop
                  addi         ra, a7, 2029
                  lui          s8, 955933
                  lui          s8, 955933
                  sub          s8, a4, a7
                  add          t1, s10, ra
                  lui          s8, 955933
                  lui          s8, 955933
                  nop
                  auipc        t1, 400075
                  mulh         s8, s10, t1
                  nop
                  divu         s10, t2, a4
                  lui          s8, 955933
                  nop
                  mulhu        t0, a7, ra
                  addi         ra, a7, 2029
                  mul          t2, s10, s10
                  mulhsu       s10, t2, t0
                  sub          s8, a4, a7
                  auipc        t1, 400075
                  mul          t2, s10, s10
                  mulhsu       s10, t2, t0
                  divu         s10, t2, a4
                  divu         s10, t2, a4
                  rem          gp, t0, gp
                  mul          t2, s10, s10 #end riscv_int_numeric_corner_stream_34
                  c.mv         s8, t5
                  lui          s0, 955933
                  c.mv         s8, t5
                  mul          s6, a0, s0
                  srai         s6, s3, 24
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  slli         t4, t3, 27
                  srai         s6, s3, 24
                  ori          a2, a1, -1711
                  mulhu        a1, t1, t5
                  c.lui        s0, 15
                  sra          a3, s6, t4
                  c.nop
                  c.srli       a0, 18
                  sltu         s10, s9, s8
                  xori         t5, s5, -792
                  c.lui        s0, 15
                  srl          s2, s1, sp
                  c.lui        s0, 15
                  add          s5, s8, a6
                  div          a2, t1, a7
                  slli         t4, t3, 27
                  c.sub        s0, a4
                  div          a2, t1, a7
                  sltu         s10, s9, s8
                  c.xor        a5, s0
                  c.mv         s8, t5
                  c.andi       a5, 16
                  srai         s6, s3, 24
                  c.lui        s0, 15
                  c.srli       a0, 18
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  mulhsu       s1, s4, sp
                  srl          s2, s1, sp
                  c.nop
                  xori         t5, s5, -792
                  rem          a4, s2, a7
                  ori          a2, a1, -1711
                  c.andi       a5, 16
                  or           t4, a3, a3
                  slli         t4, t3, 27
                  andi         s5, tp, -69
                  sltu         s10, s9, s8
                  divu         s1, s4, a4
                  and          s6, gp, s0
                  c.or         a3, s1
                  c.andi       a5, 16
                  mulhu        a1, t1, t5
                  or           t4, a3, a3
                  remu         t0, s7, s1
                  c.li         t6, 20
                  auipc        tp, 400075
                  and          s6, gp, s0
                  c.li         t6, 20
                  c.slli       s8, 9
                  c.or         a3, s1
                  c.li         t6, 20
                  c.mv         s8, t5
                  mulh         s9, s8, gp
                  c.andi       a5, 16
                  sub          s9, s5, s6
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  mulhu        a1, t1, t5
                  sub          s9, s5, s6
                  sra          a3, s6, t4
                  remu         t0, s7, s1
                  auipc        tp, 400075
                  addi         zero, t6, 2029
                  c.srai       a3, 9
                  andi         s5, tp, -69
                  c.nop
                  sltiu        zero, gp, -198
                  c.or         a3, s1
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  c.srli       a0, 18
                  sll          a5, s3, s8
                  c.and        a3, s0
                  div          a2, t1, a7
                  slti         s8, ra, -2031
                  lui          s0, 955933
                  c.srai       a3, 9
                  auipc        tp, 400075
                  xori         t5, s5, -792
                  c.addi       s2, 16
                  c.or         a3, s1
                  c.nop
                  c.xor        a5, s0
                  mul          s6, a0, s0
                  slti         s8, ra, -2031
                  addi         zero, t6, 2029
                  and          s6, gp, s0
                  xori         t5, s5, -792
                  sltu         s10, s9, s8
                  c.and        a3, s0
                  nop
                  lui          s0, 955933
                  c.addi       s2, 16
                  c.srai       a3, 9
                  mulhsu       s1, s4, sp
                  c.sub        s0, a4
                  c.addi       s2, 16
                  c.nop
                  divu         s1, s4, a4
                  sra          a3, s6, t4
                  c.srai       a3, 9
                  c.xor        a5, s0
                  srl          s2, s1, sp
                  c.mv         s8, t5
                  srai         s6, s3, 24
                  c.and        a3, s0
                  sll          a5, s3, s8
                  c.xor        a5, s0
                  c.andi       a5, 16
                  c.andi       a5, 16
                  c.nop
                  c.sub        s0, a4
                  srli         a3, s8, 11
                  c.nop
                  c.nop
                  and          s6, gp, s0
                  c.addi       s2, 16
                  c.nop
                  srli         a3, s8, 11
                  xor          t5, s1, a7
                  nop
                  rem          a4, s2, a7
                  sra          a3, s6, t4
                  c.srli       a0, 18
                  c.mv         s8, t5
                  slti         s8, ra, -2031
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  div          a2, t1, a7
                  or           t4, a3, a3
                  slt          t6, a0, sp
                  sltiu        zero, gp, -198
                  sll          a5, s3, s8
                  slli         t4, t3, 27
                  sub          s9, s5, s6
                  slli         t4, t3, 27
                  xori         t5, s5, -792
                  xor          t5, s1, a7
                  c.mv         s8, t5
                  c.sub        s0, a4
                  mulh         s9, s8, gp
                  div          a2, t1, a7
                  remu         t0, s7, s1
                  c.lui        s0, 15
                  c.mv         s8, t5
                  c.or         a3, s1
                  sub          s9, s5, s6
                  c.srai       a3, 9
                  mulhu        a1, t1, t5
                  srai         s6, s3, 24
                  c.andi       a5, 16
                  c.lui        s0, 15
                  andi         s5, tp, -69
                  mulhsu       s1, s4, sp
                  c.and        a3, s0
                  sra          a3, s6, t4
                  srl          s2, s1, sp
                  sltu         s10, s9, s8
                  sltu         s10, s9, s8
                  c.xor        a5, s0
                  nop
                  and          s6, gp, s0
                  slti         s8, ra, -2031
                  sltu         s10, s9, s8
                  and          s6, gp, s0
                  c.and        a3, s0
                  sra          a3, s6, t4
                  mul          s6, a0, s0
                  xor          t5, s1, a7
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  c.and        a3, s0
                  c.or         a3, s1
                  c.add        s7, s6
                  auipc        tp, 400075
                  c.lui        s0, 15
                  nop
                  xori         t5, s5, -792
                  c.nop
                  c.sub        s0, a4
                  add          s5, s8, a6
                  ori          a2, a1, -1711
                  c.srai       a3, 9
                  sltu         s10, s9, s8
                  c.lui        s0, 15
                  c.srai       a3, 9
                  c.slli       s8, 9
                  add          s5, s8, a6
                  slli         t4, t3, 27
                  c.nop
                  slti         s8, ra, -2031
                  c.add        s7, s6
                  c.srli       a0, 18
                  add          s5, s8, a6
                  sltu         s10, s9, s8
                  sltiu        zero, gp, -198
                  c.mv         s8, t5
                  div          a2, t1, a7
                  sra          a3, s6, t4
                  c.and        a3, s0
                  add          s5, s8, a6
                  lui          s0, 955933
                  sll          a5, s3, s8
                  c.srai       a3, 9
                  srli         a3, s8, 11
                  c.or         a3, s1
                  andi         s5, tp, -69
                  c.srli       a0, 18
                  sra          a3, s6, t4
                  mulh         s9, s8, gp
                  ori          a2, a1, -1711
                  srai         s6, s3, 24
                  addi         zero, t6, 2029
                  remu         t0, s7, s1
                  nop
                  slti         s8, ra, -2031
                  add          s5, s8, a6
                  div          a2, t1, a7
                  c.andi       a5, 16
                  remu         t0, s7, s1
                  c.addi       s2, 16
                  rem          a4, s2, a7
                  sll          a5, s3, s8
                  nop
                  or           t4, a3, a3
                  c.add        s7, s6
                  c.add        s7, s6
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  div          a2, t1, a7
                  srli         a3, s8, 11
                  rem          a4, s2, a7
                  c.srai       a3, 9
                  sltu         s10, s9, s8
                  slti         s8, ra, -2031
                  divu         s1, s4, a4
                  c.and        a3, s0
                  c.mv         s8, t5
                  or           t4, a3, a3
                  xori         t5, s5, -792
                  slti         s8, ra, -2031
                  c.mv         s8, t5
                  c.nop
                  c.nop
                  sltu         s10, s9, s8
                  nop
                  c.lui        s0, 15
                  nop
                  slti         s8, ra, -2031
                  c.xor        a5, s0
                  c.li         t6, 20
                  mulhsu       s1, s4, sp
                  c.addi       s2, 16
                  srai         s6, s3, 24
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  divu         s1, s4, a4
                  slti         s8, ra, -2031
                  c.sub        s0, a4
                  xor          t5, s1, a7
                  xori         t5, s5, -792
                  sra          a3, s6, t4
                  add          s5, s8, a6
                  c.lui        s0, 15
                  xor          t5, s1, a7
                  mulhsu       s1, s4, sp
                  div          a2, t1, a7
                  xori         t5, s5, -792
                  mulhu        a1, t1, t5
                  nop
                  or           t4, a3, a3
                  sub          s9, s5, s6
                  addi         zero, t6, 2029
                  sll          a5, s3, s8
                  lui          s0, 955933
                  add          s5, s8, a6
                  sltiu        zero, gp, -198
                  c.xor        a5, s0
                  addi         zero, t6, 2029
                  sltu         s10, s9, s8
                  sra          a3, s6, t4
                  srai         s6, s3, 24
                  mul          s6, a0, s0
                  la x2, test_done
                  jalr x0, x2, 0
test_done:        
                  li gp, 1
                  ecall
write_tohost:     
                  sw gp, tohost, t5

_exit:            
                  j write_tohost

instr_end:        
                  nop

.section .data
.align 6; .global tohost; tohost: .dword 0;
.align 6; .global fromhost; fromhost: .dword 0;
.section .user_stack,"aw",@progbits;
.align 2
user_stack_start:
.rept 4999
.4byte 0x0
.endr
user_stack_end:
.4byte 0x0
.align 2
kernel_instr_start:
.text
.align           2
mtvec_handler:    
                  addi x28, x28, -4
                  sw  x20, (x28)
                  add x20, x28, zero
                  addi x20, x20, -128
                  sw  x1, 4(x20)
                  sw  x2, 8(x20)
                  sw  x3, 12(x20)
                  sw  x4, 16(x20)
                  sw  x5, 20(x20)
                  sw  x6, 24(x20)
                  sw  x7, 28(x20)
                  sw  x8, 32(x20)
                  sw  x9, 36(x20)
                  sw  x10, 40(x20)
                  sw  x11, 44(x20)
                  sw  x12, 48(x20)
                  sw  x13, 52(x20)
                  sw  x14, 56(x20)
                  sw  x15, 60(x20)
                  sw  x16, 64(x20)
                  sw  x17, 68(x20)
                  sw  x18, 72(x20)
                  sw  x19, 76(x20)
                  sw  x20, 80(x20)
                  sw  x21, 84(x20)
                  sw  x22, 88(x20)
                  sw  x23, 92(x20)
                  sw  x24, 96(x20)
                  sw  x25, 100(x20)
                  sw  x26, 104(x20)
                  sw  x27, 108(x20)
                  sw  x28, 112(x20)
                  sw  x29, 116(x20)
                  sw  x30, 120(x20)
                  sw  x31, 124(x20)
                  add x28, x20, zero
                  csrr x12, 0x300 # MSTATUS
                  csrr x12, 0x342 # MCAUSE
                  srli x12, x12, 31
                  bne x12, x0, mmode_intr_handler

mmode_exception_handler:
                  csrr x12, 0x341 # MEPC
                  csrr x12, 0x342 # MCAUSE
                  li x18, 0x3 # BREAKPOINT
                  beq x12, x18, ebreak_handler
                  li x18, 0x8 # ECALL_UMODE
                  beq x12, x18, ecall_handler
                  li x18, 0x9 # ECALL_SMODE
                  beq x12, x18, ecall_handler
                  li x18, 0xb # ECALL_MMODE
                  beq x12, x18, ecall_handler
                  li x18, 0x1
                  beq x12, x18, instr_fault_handler
                  li x18, 0x5
                  beq x12, x18, load_fault_handler
                  li x18, 0x7
                  beq x12, x18, store_fault_handler
                  li x18, 0xc
                  beq x12, x18, pt_fault_handler
                  li x18, 0xd
                  beq x12, x18, pt_fault_handler
                  li x18, 0xf
                  beq x12, x18, pt_fault_handler
                  li x18, 0x2 # ILLEGAL_INSTRUCTION
                  beq x12, x18, illegal_instr_handler
                  csrr x18, 0x343 # MTVAL
                  1: la x2, test_done
                  jalr x1, x2, 0

ecall_handler:    
                  la x12, _start
                  sw x0, 0(x12)
                  sw x1, 4(x12)
                  sw x2, 8(x12)
                  sw x3, 12(x12)
                  sw x4, 16(x12)
                  sw x5, 20(x12)
                  sw x6, 24(x12)
                  sw x7, 28(x12)
                  sw x8, 32(x12)
                  sw x9, 36(x12)
                  sw x10, 40(x12)
                  sw x11, 44(x12)
                  sw x12, 48(x12)
                  sw x13, 52(x12)
                  sw x14, 56(x12)
                  sw x15, 60(x12)
                  sw x16, 64(x12)
                  sw x17, 68(x12)
                  sw x18, 72(x12)
                  sw x19, 76(x12)
                  sw x20, 80(x12)
                  sw x21, 84(x12)
                  sw x22, 88(x12)
                  sw x23, 92(x12)
                  sw x24, 96(x12)
                  sw x25, 100(x12)
                  sw x26, 104(x12)
                  sw x27, 108(x12)
                  sw x28, 112(x12)
                  sw x29, 116(x12)
                  sw x30, 120(x12)
                  sw x31, 124(x12)
                  la x2, write_tohost
                  jalr x0, x2, 0

instr_fault_handler:
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret

load_fault_handler:
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret

store_fault_handler:
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret

ebreak_handler:   
                  csrr  x12, 0x341
                  addi  x12, x12, 4
                  csrw  0x341, x12
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret

illegal_instr_handler:
                  csrr  x12, 0x341
                  addi  x12, x12, 4
                  csrw  0x341, x12
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret

pt_fault_handler: 
                  nop

.align 2
mmode_intr_handler:
                  csrr  x12, 0x300 # MSTATUS;
                  csrr  x12, 0x304 # MIE;
                  csrr  x12, 0x344 # MIP;
                  csrrc x12, 0x344, x12 # MIP;
                  add x20, x28, zero
                  lw  x1, 4(x20)
                  lw  x2, 8(x20)
                  lw  x3, 12(x20)
                  lw  x4, 16(x20)
                  lw  x5, 20(x20)
                  lw  x6, 24(x20)
                  lw  x7, 28(x20)
                  lw  x8, 32(x20)
                  lw  x9, 36(x20)
                  lw  x10, 40(x20)
                  lw  x11, 44(x20)
                  lw  x12, 48(x20)
                  lw  x13, 52(x20)
                  lw  x14, 56(x20)
                  lw  x15, 60(x20)
                  lw  x16, 64(x20)
                  lw  x17, 68(x20)
                  lw  x18, 72(x20)
                  lw  x19, 76(x20)
                  lw  x20, 80(x20)
                  lw  x21, 84(x20)
                  lw  x22, 88(x20)
                  lw  x23, 92(x20)
                  lw  x24, 96(x20)
                  lw  x25, 100(x20)
                  lw  x26, 104(x20)
                  lw  x27, 108(x20)
                  lw  x28, 112(x20)
                  lw  x29, 116(x20)
                  lw  x30, 120(x20)
                  lw  x31, 124(x20)
                  addi x20, x20, 128
                  add x28, x20, zero
                  lw  x20, (x28)
                  addi x28, x28, 4
                  mret;

kernel_instr_end: nop
.section .kernel_stack,"aw",@progbits;
.align 2
kernel_stack_start:
.rept 3999
.4byte 0x0
.endr
kernel_stack_end:
.4byte 0x0
