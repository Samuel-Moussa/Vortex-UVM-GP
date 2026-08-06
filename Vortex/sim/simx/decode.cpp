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
#include <string>
#include <sstream>
#include <stdlib.h>
#include <string.h>
#include <iomanip>
#include <cstdio>
#include <vector>
#include <unordered_map>
#include <util.h>
#include "debug.h"
#include "types.h"
#include "emulator.h"
#include "arch.h"
#include "instr.h"
#include "golden_halt.h"

#ifdef EXT_TCU_ENABLE
#include "tensor_cfg.h"
#endif

using namespace vortex;

// ── golden-halt record definition (shared with execute.cpp via golden_halt.h) ─
namespace vortex {

golden_halt_t& golden_halt_record() {
  static golden_halt_t rec{};
  return rec;
}

void golden_halt_clear() {
  golden_halt_record() = golden_halt_t{};
}

void golden_halt_set(const char* where, const char* detail, int line,
                     uint64_t pc, uint32_t code, uint32_t wid) {
  auto& r = golden_halt_record();
  if (r.valid)
    return;                       // keep the FIRST refusal: it stopped the run
  r.valid = 1;
  r.pc    = pc;
  r.code  = code;
  r.wid   = wid;
  r.line  = line;
  std::snprintf(r.where,  sizeof(r.where),  "%s", where  ? where  : "?");
  std::snprintf(r.detail, sizeof(r.detail), "%s", detail ? detail : "?");
}

bool golden_halt_force_pending() {
  static long threshold = -2;   // -2 = env not read yet, -1 = disabled
  static long decoded   = 0;
  if (threshold == -2) {
    const char* e = std::getenv("SIMX_FORCE_HALT");
    threshold = (e && *e) ? std::atol(e) : -1;
    if (threshold >= 0)
      std::cerr << "[SimX-GOLDEN-HALT] injection ARMED: will refuse at decoded "
                << "instruction #" << threshold << " (SIMX_FORCE_HALT)" << std::endl;
  }
  if (threshold < 0)
    return false;               // default path: no counter, no behaviour change
  return (++decoded >= threshold);
}

} // namespace vortex

// ── Decode-failure diagnostic ────────────────────────────────────────────────
// SimX's decoder aborts (default: std::abort()) on any instruction word it does
// not model. Previously that abort was silent — the DPI crash-guard masked it to
// a bare sentinel (-3 / UNVERIFIABLE) with no reason. This macro prints the exact
// faulting instruction word + PC + warp + decode.cpp line BEFORE aborting, so an
// UNVERIFIABLE-by-decode-abort case is self-documenting (garbage from a computed
// jump vs a genuinely-unimplemented RISC-V instruction). Used ONLY inside
// Emulator::decode() where `code`/`wid` and `warps_` are in scope; the abort is
// intentionally NOT silenced (a golden model must refuse, not fabricate, a result).
//
// A3: it now also RECORDS the refusal (golden_halt.h) before aborting, so the DPI
// can return -4 (GOLDEN_HALT, known point) instead of -3 (CRASH, unknown) and the
// scoreboard can keep the instructions verified before this one.
#define DECODE_ABORT() do {                                                     \
    vortex::golden_halt_set("decode", "unrecognized instruction encoding",      \
                            __LINE__, warps_.at(wid).PC, (code), (wid));        \
    std::cerr << "[SimX-DECODE-ABORT] cannot decode instr=0x" << std::hex       \
              << std::setw(8) << std::setfill('0') << (code)                    \
              << " at PC=0x" << warps_.at(wid).PC << std::dec                   \
              << " (wid=" << (wid) << ", decode.cpp:" << __LINE__ << ")"        \
              << std::endl;                                                     \
    std::abort();                                                               \
  } while (0)

// ── A3 / OBS-020: the DISASSEMBLER must never abort ──────────────────────────
// op_string() below is pure formatting: it is `static`, its only consumer is
// operator<<(ostream&, const Instr&) at the bottom of this file, and it runs on
// an instruction that has ALREADY decoded and executed correctly. Its `default:`
// labels are sub-field cases (funct3/rounding-mode/enum) it cannot NAME.
// Aborting there killed the process, the DPI crash-guard mapped SIGABRT to the
// -3 sentinel, and an otherwise fully-verified run was thrown away because the
// golden could not spell an instruction. There is no verification value in that:
// a mnemonic is never compared against anything. So every such case now yields a
// printable placeholder naming the sub-field and its value, and the run survives.
// (This is NOT the same as fabricating a RESULT — see Emulator::decode(), where
// refusing is correct and the abort is deliberately kept.)
static inline op_string_t unknown_op(const char *sub, long long v) {
  std::ostringstream ss;
  ss << "UNKNOWN(" << sub << "=" << v << ")";
  return {ss.str(), ""};
}

static op_string_t op_string(const Instr &instr) {
  auto op_type = instr.getOpType();
  auto instrArgs = instr.getArgs();
  return visit_var(op_type,
    [&](AluType alu_type)-> op_string_t {
      auto aluArgs = std::get<IntrAluArgs>(instrArgs);
      switch (alu_type) {
      case AluType::LUI:   return {"LUI", to_hex_str(aluArgs.imm)};
      case AluType::AUIPC: return {"AUIPC", to_hex_str(aluArgs.imm)};
      case AluType::ADD: {
        if (aluArgs.is_imm) {
          return {aluArgs.is_w ? "ADDIW":"ADDI", to_hex_str(aluArgs.imm)};
        } else {
          return {aluArgs.is_w ? "ADDW":"ADD", ""};
        }
      }
      case AluType::SUB: {
        if (aluArgs.is_imm) {
          return {aluArgs.is_w ? "SUBW":"SUB", to_hex_str(aluArgs.imm)};
        } else {
          return {aluArgs.is_w ? "SUBW":"SUB", ""};
        }
      }
      case AluType::SLL: {
        if (aluArgs.is_imm) {
          return {aluArgs.is_w ? "SLLIW":"SLLI", to_hex_str(aluArgs.imm)};
        } else {
          return {aluArgs.is_w ? "SLLW":"SLL", ""};
        }
      }
      case AluType::SRL: {
        if (aluArgs.is_imm) {
          return {aluArgs.is_w ? "SRLIW":"SRLI", to_hex_str(aluArgs.imm)};
        } else {
          return {aluArgs.is_w ? "SRLW":"SRL", ""};
        }
      }
      case AluType::SRA: {
        if (aluArgs.is_imm) {
          return {aluArgs.is_w ? "SRAIW":"SRAI", to_hex_str(aluArgs.imm)};
        } else {
          return {aluArgs.is_w ? "SRAW":"SRA", ""};
        }
      }
      case AluType::SLT: {
        if (aluArgs.is_imm) {
          return {"SLTI", to_hex_str(aluArgs.imm)};
        } else {
          return {"SLT", ""};
        }
      }
      case AluType::SLTU: {
        if (aluArgs.is_imm) {
          return {"SLTIU", to_hex_str(aluArgs.imm)};
        } else {
          return {"SLTU", ""};
        }
      }
      case AluType::AND: {
        if (aluArgs.is_imm) {
          return {"ANDI", to_hex_str(aluArgs.imm)};
        } else {
          return {"AND", ""};
        }
      }
      case AluType::OR: {
        if (aluArgs.is_imm) {
          return {"ORI", to_hex_str(aluArgs.imm)};
        } else {
          return {"OR", ""};
        }
      }
      case AluType::XOR: {
        if (aluArgs.is_imm) {
          return {"XORI", to_hex_str(aluArgs.imm)};
        } else {
          return {"XOR", ""};
        }
      }
      case AluType::CZERO: return {aluArgs.imm ? "CZERO.NEZ":"CZERO.EQZ", ""};
      default:
        return unknown_op("alu_type", (long long)(alu_type));
      }
    },
    [&](VoteType vote_type)-> op_string_t {
      switch (vote_type) {
      case VoteType::ALL: return {"VOTE.ALL", ""};
      case VoteType::ANY: return {"VOTE.ANY", ""};
      case VoteType::UNI: return {"VOTE.UNI", ""};
      case VoteType::BAL: return {"VOTE.BAL", ""};
      default:
        return unknown_op("vote_type", (long long)(vote_type));
      }
    },
    [&](ShflType shfl_type)-> op_string_t {
      switch (shfl_type) {
      case ShflType::UP:   return {"SHFL.UP", ""};
      case ShflType::DOWN: return {"SHFL.DOWN", ""};
      case ShflType::BFLY: return {"SHFL.BFLY", ""};
      case ShflType::IDX:  return {"SHFL.IDX", ""};
      default:
        return unknown_op("shfl_type", (long long)(shfl_type));
      }
    },
    [&](BrType br_type)-> op_string_t {
      auto brArgs = std::get<IntrBrArgs>(instrArgs);
      switch (br_type) {
      case BrType::BR: {
        switch (brArgs.cmp) {
        case 0: return {"BEQ",  to_hex_str(brArgs.offset)};
        case 1: return {"BNE",  to_hex_str(brArgs.offset)};
        case 4: return {"BLT",  to_hex_str(brArgs.offset)};
        case 5: return {"BGE",  to_hex_str(brArgs.offset)};
        case 6: return {"BLTU", to_hex_str(brArgs.offset)};
        case 7: return {"BGEU", to_hex_str(brArgs.offset)};
        default:
          return unknown_op("brArgs.cmp", (long long)(brArgs.cmp));
        }
      }
      case BrType::JAL:  return {"JAL", to_hex_str(brArgs.offset)};
      case BrType::JALR: return {"JALR", to_hex_str(brArgs.offset)};
      case BrType::SYS:
        switch (brArgs.offset) {
        case 0x000: return {"ECALL", ""};
        case 0x001: return {"EBREAK", ""};
        case 0x002: return {"URET", ""};
        case 0x102: return {"SRET", ""};
        case 0x302: return {"MRET", ""};
        default:
          return unknown_op("brArgs.offset", (long long)(brArgs.offset));
        }
      default:
        return unknown_op("br_type", (long long)(br_type));
      }
    },
    [&](MdvType mdv_type)-> op_string_t {
      auto mdvArgs = std::get<IntrMdvArgs>(instrArgs);
      switch (mdv_type) {
      case MdvType::MUL:    return {mdvArgs.is_w ? "MULW":"MUL", ""};
      case MdvType::MULHU:  return {"MULHU", ""};
      case MdvType::MULH:   return {"MULH", ""};
      case MdvType::MULHSU: return {"MULHSU", ""};
      case MdvType::DIV:    return {mdvArgs.is_w ? "DIVW":"DIV", ""};
      case MdvType::DIVU:   return {mdvArgs.is_w ? "DIVUW":"DIVU", ""};
      case MdvType::REM:    return {mdvArgs.is_w ? "REMW":"REM", ""};
      case MdvType::REMU:   return {mdvArgs.is_w ? "REMUW":"REMU", ""};
      default:
        return unknown_op("mdv_type", (long long)(mdv_type));
      }
    },
    [&](FpuType fpu_type)-> op_string_t {
      auto fpuArgs = std::get<IntrFpuArgs>(instrArgs);
      switch (fpu_type) {
      case FpuType::FADD:   return {fpuArgs.is_f64 ? "FADD.D":"FADD.S", ""};
      case FpuType::FSUB:   return {fpuArgs.is_f64 ? "FSUB.D":"FSUB.S", ""};
      case FpuType::FMUL:   return {fpuArgs.is_f64 ? "FMUL.D":"FMUL.S", ""};
      case FpuType::FDIV:   return {fpuArgs.is_f64 ? "FDIV.D":"FDIV.S", ""};
      case FpuType::FSQRT:  return {fpuArgs.is_f64 ? "FSQRT.D":"FSQRT.S", ""};
      case FpuType::FMADD:  return {fpuArgs.is_f64 ? "FMADD.D":"FMADD.S", ""};
      case FpuType::FMSUB:  return {fpuArgs.is_f64 ? "FMSUB.D":"FMSUB.S", ""};
      case FpuType::FNMADD: return {fpuArgs.is_f64 ? "FNMADD.D":"FNMADD.S", ""};
      case FpuType::FNMSUB: return {fpuArgs.is_f64 ? "FNMSUB.D":"FNMSUB.S", ""};
      case FpuType::F2I: {
        switch (fpuArgs.cvt) {
        case 0: return {fpuArgs.is_f64 ? "FCVT.W.D":"FCVT.W.S", ""};
        case 1: return {fpuArgs.is_f64 ? "FCVT.WU.D":"FCVT.WU.S", ""};
        case 2: return {fpuArgs.is_f64 ? "FCVT.L.D":"FCVT.L.S", ""};
        case 3: return {fpuArgs.is_f64 ? "FCVT.LU.D":"FCVT.LU.S", ""};
        default:
          return unknown_op("fpuArgs.cvt", (long long)(fpuArgs.cvt));
        }
      }
      case FpuType::I2F: {
        switch (fpuArgs.cvt) {
        case 0: return {fpuArgs.is_f64 ? "FCVT.D.W":"FCVT.S.W", ""};
        case 1: return {fpuArgs.is_f64 ? "FCVT.D.WU":"FCVT.S.WU", ""};
        case 2: return {fpuArgs.is_f64 ? "FCVT.D.L":"FCVT.S.L", ""};
        case 3: return {fpuArgs.is_f64 ? "FCVT.D.LU":"FCVT.S.LU", ""};
        default:
          return unknown_op("fpuArgs.cvt", (long long)(fpuArgs.cvt));
        }
      }
      case FpuType::F2F: return {fpuArgs.is_f64 ? "FCVT.D.S":"FCVT.S.D", ""};
      case FpuType::FCMP: {
        switch (fpuArgs.frm) {
        case 0: return {fpuArgs.is_f64 ? "FLE.D":"FLE.S", ""};
        case 1: return {fpuArgs.is_f64 ? "FLT.D":"FLT.S", ""};
        case 2: return {fpuArgs.is_f64 ? "FEQ.D":"FEQ.S", ""};
        default:
          return unknown_op("fpuArgs.frm", (long long)(fpuArgs.frm));
        }
      }
      case FpuType::FSGNJ: {
        switch (fpuArgs.frm) {
        case 0: return {fpuArgs.is_f64 ? "FSGNJ.D":"FSGNJ.S", ""};
        case 1: return {fpuArgs.is_f64 ? "FSGNJN.D":"FSGNJN.S", ""};
        case 2: return {fpuArgs.is_f64 ? "FSGNJX.D":"FSGNJX.S", ""};
        default:
          return unknown_op("fpuArgs.frm", (long long)(fpuArgs.frm));
        }
      }
      case FpuType::FCLASS: return {fpuArgs.is_f64 ? "FCLASS.D":"FCLASS.S", ""};
      case FpuType::FMVXW:  return {fpuArgs.is_f64 ? "FMV.X.D":"FMV.X.S", ""};
      case FpuType::FMVWX:  return {fpuArgs.is_f64 ? "FMV.D.X":"FMV.S.X", ""};
      case FpuType::FMINMAX: {
        switch (fpuArgs.frm) {
        case 0: return {fpuArgs.is_f64 ? "FMIN.D":"FMIN.S", ""};
        case 1: return {fpuArgs.is_f64 ? "FMAX.D":"FMAX.S", ""};
        default:
          return unknown_op("fpuArgs.frm", (long long)(fpuArgs.frm));
        }
      }
      default:
        return unknown_op("fpu_type", (long long)(fpu_type));
      }
    },
    [&](LsuType lsu_type)-> op_string_t {
      switch (lsu_type) {
      case LsuType::LOAD: {
        auto lsuArgs = std::get<IntrLsuArgs>(instrArgs);
        if (lsuArgs.is_float) {
          switch (lsuArgs.width) {
          case 2: return {"FLW", to_hex_str(lsuArgs.offset)};
          case 3: return {"FLD", to_hex_str(lsuArgs.offset)};
          default:
            return unknown_op("lsuArgs.width", (long long)(lsuArgs.width));
          }
        } else {
          switch (lsuArgs.width) {
          case 0: return {"LB",  to_hex_str(lsuArgs.offset)};
          case 1: return {"LH",  to_hex_str(lsuArgs.offset)};
          case 2: return {"LW",  to_hex_str(lsuArgs.offset)};
          case 3: return {"LD",  to_hex_str(lsuArgs.offset)};
          case 4: return {"LBU", to_hex_str(lsuArgs.offset)};
          case 5: return {"LHU", to_hex_str(lsuArgs.offset)};
          case 6: return {"LWU", to_hex_str(lsuArgs.offset)};
          default:
            return unknown_op("lsuArgs.width", (long long)(lsuArgs.width));
          }
        }
      }
      case LsuType::STORE: {
        auto lsuArgs = std::get<IntrLsuArgs>(instrArgs);
        if (lsuArgs.is_float) {
          switch (lsuArgs.width) {
          case 2: return {"FSW", to_hex_str(lsuArgs.offset)};
          case 3: return {"FSD", to_hex_str(lsuArgs.offset)};
          default:
            return unknown_op("lsuArgs.width", (long long)(lsuArgs.width));
          }
        } else {
          switch (lsuArgs.width) {
          case 0: return {"SB", to_hex_str(lsuArgs.offset)};
          case 1: return {"SH", to_hex_str(lsuArgs.offset)};
          case 2: return {"SW", to_hex_str(lsuArgs.offset)};
          case 3: return {"SD", to_hex_str(lsuArgs.offset)};
          default:
            return unknown_op("lsuArgs.width", (long long)(lsuArgs.width));
          }
        }
      }
      case LsuType::FENCE: return {"FENCE", ""};
      default:
        return unknown_op("lsu_type", (long long)(lsu_type));
      }
    },
    [&](AmoType amo_type)-> op_string_t {
      auto amoArgs = std::get<IntrAmoArgs>(instrArgs);
      switch (amoArgs.width) {
      case 2: {
        switch (amo_type) {
        case AmoType::LR:      return {"LR.W", ""};
        case AmoType::SC:      return {"SC.W", ""};
        case AmoType::AMOADD:  return {"AMOADD.W", ""};
        case AmoType::AMOSWAP: return {"AMOSWAP.W", ""};
        case AmoType::AMOAND:  return {"AMOAND.W", ""};
        case AmoType::AMOOR:   return {"AMOOR.W", ""};
        case AmoType::AMOXOR:  return {"AMOXOR.W", ""};
        case AmoType::AMOMIN:  return {"AMOMIN.W", ""};
        case AmoType::AMOMAX:  return {"AMOMAX.W", ""};
        case AmoType::AMOMINU: return {"AMOMINU.W", ""};
        case AmoType::AMOMAXU: return {"AMOMAXU.W", ""};
        default:
          return unknown_op("amo_type", (long long)(amo_type));
        }
      }
      case 3: {
        switch (amo_type) {
        case AmoType::LR:      return {"LR.D", ""};
        case AmoType::SC:      return {"SC.D", ""};
        case AmoType::AMOADD:  return {"AMOADD.D", ""};
        case AmoType::AMOSWAP: return {"AMOSWAP.D", ""};
        case AmoType::AMOAND:  return {"AMOAND.D", ""};
        case AmoType::AMOOR:   return {"AMOOR.D", ""};
        case AmoType::AMOXOR:  return {"AMOXOR.D", ""};
        case AmoType::AMOMIN:  return {"AMOMIN.D", ""};
        case AmoType::AMOMAX:  return {"AMOMAX.D", ""};
        case AmoType::AMOMINU: return {"AMOMINU.D", ""};
        case AmoType::AMOMAXU: return {"AMOMAXU.D", ""};
        default:
          return unknown_op("amo_type", (long long)(amo_type));
        }
      }
      default:
        return unknown_op("amoArgs.width", (long long)(amoArgs.width));
      }
    },
    [&](CsrType csr_type)-> op_string_t {
      auto csrArgs = std::get<IntrCsrArgs>(instrArgs);
      if (csrArgs.is_imm) {
        switch (csr_type) {
        case CsrType::CSRRW: return {"CSRRWI", to_hex_str(csrArgs.imm) + ", " + to_hex_str(csrArgs.csr)};
        case CsrType::CSRRS: return {"CSRRSI", to_hex_str(csrArgs.imm) + ", " + to_hex_str(csrArgs.csr)};
        case CsrType::CSRRC: return {"CSRRCI", to_hex_str(csrArgs.imm) + ", " + to_hex_str(csrArgs.csr)};
        default:
          return unknown_op("csr_type", (long long)(csr_type));
        }
      } else {
        switch (csr_type) {
        case CsrType::CSRRW: return {"CSRRW", to_hex_str(csrArgs.csr)};
        case CsrType::CSRRS: return {"CSRRS", to_hex_str(csrArgs.csr)};
        case CsrType::CSRRC: return {"CSRRC", to_hex_str(csrArgs.csr)};
        default:
          return unknown_op("csr_type", (long long)(csr_type));
        }
      }
    },
    [&](WctlType wctl_type)-> op_string_t {
      auto wctlArgs = std::get<IntrWctlArgs>(instrArgs);
      switch (wctl_type) {
      case WctlType::TMC:    return {"TMC", ""};
      case WctlType::WSPAWN: return {"WSPAWN", ""};
      case WctlType::SPLIT:  return {wctlArgs.is_neg ? "SPLIT.N":"SPLIT", ""};
      case WctlType::JOIN:   return {"JOIN", ""};
      case WctlType::BAR:    return {"BAR", ""};
      case WctlType::PRED:   return {wctlArgs.is_neg ? "PRED.N":"PRED", ""};
      default:
        return unknown_op("wctl_type", (long long)(wctl_type));
      }
    }
  #ifdef EXT_V_ENABLE
    ,[&](VsetType vset_type)-> op_string_t {
      auto vsetArgs = std::get<IntrVsetArgs>(instrArgs);
      switch (vset_type) {
      case VsetType::VSETVLI:  return {"VSETVLI", vsetArgs.to_string(vset_type)};
      case VsetType::VSETIVLI: return {"VSETIVLI", vsetArgs.to_string(vset_type)};
      case VsetType::VSETVL:   return {"VSETVL", vsetArgs.to_string(vset_type)};
      default:
        return unknown_op("vset_type", (long long)(vset_type));
      }
    },
    [&](VlsType vls_type)-> op_string_t {
      auto vlsArgs = std::get<IntrVlsArgs>(instrArgs);
      switch (vls_type) {
      case VlsType::VL: {
        switch (vlsArgs.width) {
        case 0: return {"VL8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VL16", vlsArgs.to_string(vls_type)};
        case 2: return {"VL32", vlsArgs.to_string(vls_type)};
        case 3: return {"VL64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }
      case VlsType::VLS: {
        switch (vlsArgs.width) {
        case 0: return {"VLS8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VLS16", vlsArgs.to_string(vls_type)};
        case 2: return {"VLS32", vlsArgs.to_string(vls_type)};
        case 3: return {"VLS64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }
      case VlsType::VLX: {
        switch (vlsArgs.width) {
        case 0: return {"VLX8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VLX16", vlsArgs.to_string(vls_type)};
        case 2: return {"VLX32", vlsArgs.to_string(vls_type)};
        case 3: return {"VLX64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }
      case VlsType::VS: {
        switch (vlsArgs.width) {
        case 0: return {"VS8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VS16", vlsArgs.to_string(vls_type)};
        case 2: return {"VS32", vlsArgs.to_string(vls_type)};
        case 3: return {"VS64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }

      case VlsType::VSS: {
        switch (vlsArgs.width) {
        case 0: return {"VSS8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VSS16", vlsArgs.to_string(vls_type)};
        case 2: return {"VSS32", vlsArgs.to_string(vls_type)};
        case 3: return {"VSS64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }

      case VlsType::VSX: {
        switch (vlsArgs.width) {
        case 0: return {"VSX8",  vlsArgs.to_string(vls_type)};
        case 1: return {"VSX16", vlsArgs.to_string(vls_type)};
        case 2: return {"VSX32", vlsArgs.to_string(vls_type)};
        case 3: return {"VSX64", vlsArgs.to_string(vls_type)};
        default:
          return unknown_op("vlsArgs.width", (long long)(vlsArgs.width));
        }
      }
      default:
        return unknown_op("vls_type", (long long)(vls_type));
      }
    },
    [&](VopType vop_type)-> op_string_t {
      auto vopArgs = std::get<IntrVopArgs>(instrArgs);
      switch (vop_type) {
      case VopType::OPIVV: return {"OPIVV", vopArgs.to_string(vop_type)};
      case VopType::OPFVV: return {"OPFVV", vopArgs.to_string(vop_type)};
      case VopType::OPMVV: return {"OPMVV", vopArgs.to_string(vop_type)};
      case VopType::OPIVI: return {"OPIVI", vopArgs.to_string(vop_type)};
      case VopType::OPIVX: return {"OPIVX", vopArgs.to_string(vop_type)};
      case VopType::OPFVF: return {"OPFVF", vopArgs.to_string(vop_type)};
      case VopType::OPMVX: return {"OPMVX", vopArgs.to_string(vop_type)};
      default:
        return unknown_op("vop_type", (long long)(vop_type));
      }
    }
  #endif // EXT_V_ENABLE
  #ifdef EXT_TCU_ENABLE
    ,[&](TcuType tcu_type)-> op_string_t {
      auto tpuArgs = std::get<IntrTcuArgs>(instrArgs);
      return op_string(tcu_type, tpuArgs);
    }
  #endif // EXT_TCU_ENABLE
 );
 return {"", ""};
}

namespace vortex {
std::ostream &operator<<(std::ostream &os, const Instr &instr) {
  auto sintr = ::op_string(instr);
  int sep = 0;
  os << sintr.op;
  auto rd = instr.getDestReg();
  if (rd.type != RegType::None) {
    if (sep++ != 0) { os << ", "; } else { os << " "; }
    os << rd;
  }
  for (uint32_t i = 0; i < Instr::MAX_REG_SOURCES; ++i) {
    auto rs = instr.getSrcReg(i);
    if (rs.type != RegType::None) {
      if (sep++ != 0) { os << ", "; } else { os << " "; }
      os << rs;
    }
  }
  if (sintr.arg != "") {
    if (sep++ != 0) { os << ", "; } else { os << " "; }
    os << sintr.arg;
  }
  return os;
}
}

void Emulator::decode(uint32_t code, uint32_t wid, uint64_t uuid) {
  // A3 non-vacuity injection — default OFF (see golden_halt.h). Placed at the
  // decoder entry because that is where a genuinely unknown encoding would be
  // met, so the injected halt exercises the SAME path a real one would.
  if (vortex::golden_halt_force_pending())
    DECODE_ABORT();

  // get instruction buffer
  auto& ibuffer = warps_.at(wid).ibuffer;

  auto op = Opcode((code >> shift_opcode) & mask_opcode);
  auto funct2 = (code >> shift_funct2) & mask_funct2;
  auto funct3 = (code >> shift_funct3) & mask_funct3;
  auto funct5 = (code >> shift_funct5) & mask_funct5;
  auto funct6 = (code >> shift_funct6) & mask_funct6;
  auto funct7 = (code >> shift_funct7) & mask_funct7;
  __unused(funct6);

  auto rd  = (code >> shift_rd)  & mask_reg;
  auto rs1 = (code >> shift_rs1) & mask_reg;
  auto rs2 = (code >> shift_rs2) & mask_reg;
  auto rs3 = (code >> shift_rs3) & mask_reg;

  switch (op) {
  case Opcode::LUI:
  case Opcode::AUIPC: { // RV32I: LUI / AUIPC
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
    auto imm20 = (code >> shift_funct3) << shift_funct3;
    instr->setOpType((op == Opcode::LUI) ? AluType::LUI : AluType::AUIPC);
    instr->setArgs(IntrAluArgs{1, 0, imm20});
    instr->setDestReg(rd, RegType::Integer);
    ibuffer.push_back(instr);
    break;
  }
#ifdef XLEN_64
  case Opcode::R_W:
  case Opcode::I_W:
#endif
  case Opcode::R:
  case Opcode::I: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
    bool is_w = (op == Opcode::R_W) || (op == Opcode::I_W);
    bool is_imm = (op == Opcode::I) || (op == Opcode::I_W);
    if (op == Opcode::R && funct7 == 0x7) {
      uint32_t imm;
      if (funct3 == 0x5) { // CZERO.EQZ
        imm = 0;
      } else
      if (funct3 == 0x7) { // CZERO.NEZ
        imm = 1;
      } else {
        DECODE_ABORT();
      }
      instr->setOpType(AluType::CZERO);
      instr->setArgs(IntrAluArgs{0, 0, imm});
    } else
    if ((op == Opcode::R || op == Opcode::R_W) && (funct7 & 0x1)) {
      switch (funct3) {
      case 0: { // RV32M: MUL
        instr->setOpType(MdvType::MUL);
        break;
      }
      case 1: { // RV32M: MULH
        instr->setOpType(MdvType::MULH);
        break;
      }
      case 2: { // RV32M: MULHSU
        instr->setOpType(MdvType::MULHSU);
        break;
      }
      case 3: { // RV32M: MULHU
        instr->setOpType(MdvType::MULHU);
        break;
      }
      case 4: { // RV32M: DIV
        instr->setOpType(MdvType::DIV);
        break;
      }
      case 5: { // RV32M: DIVU
        instr->setOpType(MdvType::DIVU);
        break;
      }
      case 6: { // RV32M: REM
        instr->setOpType(MdvType::REM);
        break;
      }
      case 7: { // RV32M: REMU
        instr->setOpType(MdvType::REMU);
        break;
      }
      default:
        DECODE_ABORT();
      }
      instr->setArgs(IntrMdvArgs{is_w});
    } else {
      uint32_t imm = 0;
      if (funct3 == 0x1 || funct3 == 0x5) {
        // Shift instructions
        imm = rs2; // uint5
      #ifdef XLEN_64
        imm |= ((funct7 & 0x1) << 5);
      #endif
      } else {
        auto imm12 = code >> shift_rs2;
        imm = sext(imm12, width_i_imm);
      }
      switch (funct3) {
      case 0: { // RV32I: SUB/ADD
        instr->setOpType((!is_imm && funct7 == 0x20) ? AluType::SUB : AluType::ADD);
        break;
      }
      case 1: { // RV32I: SLL
        instr->setOpType(AluType::SLL);
        break;
      }
      case 2: { // RV32I: SLT
        instr->setOpType(AluType::SLT);
        break;
      }
      case 3: { // RV32I: SLTU
        instr->setOpType(AluType::SLTU);
        break;
      }
      case 4: { // RV32I: XOR
        instr->setOpType(AluType::XOR);
        break;
      }
      case 5: { // RV32I: SRA/SRL
        instr->setOpType((funct7 == 0x20) ? AluType::SRA : AluType::SRL);
        break;
      }
      case 6: { // RV32I: OR
        instr->setOpType(AluType::OR);
        break;
      }
      case 7: { // RV32I: AND
        instr->setOpType(AluType::AND);
        break;
      }
      default:
        DECODE_ABORT();
      }
      instr->setArgs(IntrAluArgs{is_imm, is_w, imm});
    }
    instr->setDestReg(rd, RegType::Integer);
    instr->setSrcReg(0, rs1, RegType::Integer);
    if (!is_imm) {
      instr->setSrcReg(1, rs2, RegType::Integer);
    }
    ibuffer.push_back(instr);
  } break;
  case Opcode::B: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
    auto bit_11   = rd & 0x1;
    auto bits_4_1 = rd >> 1;
    auto bit_10_5 = funct7 & 0x3f;
    auto bit_12   = funct7 >> 6;
    auto imm12 = (bits_4_1 << 1) | (bit_10_5 << 5) | (bit_11 << 11) | (bit_12 << 12);
    auto addr = sext(imm12, width_i_imm+1);
    instr->setOpType(BrType::BR);
    instr->setArgs(IntrBrArgs{funct3, addr});
    instr->setSrcReg(0, rs1, RegType::Integer);
    instr->setSrcReg(1, rs2, RegType::Integer);
    ibuffer.push_back(instr);
  } break;
  case Opcode::JAL: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
    auto unordered  = code >> shift_funct3;
    auto bits_19_12 = unordered & 0xff;
    auto bit_11     = (unordered >> 8) & 0x1;
    auto bits_10_1  = (unordered >> 9) & 0x3ff;
    auto bit_20     = (unordered >> 19) & 0x1;
    auto imm20 = (bits_10_1 << 1) | (bit_11 << 11) | (bits_19_12 << 12) | (bit_20 << 20);
    auto addr = sext(imm20, width_j_imm+1);
    instr->setOpType(BrType::JAL);
    instr->setArgs(IntrBrArgs{0, addr});
    instr->setDestReg(rd, RegType::Integer);
    ibuffer.push_back(instr);
  } break;
  case Opcode::JALR: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
    auto imm12 = code >> shift_rs2;
    auto addr = sext(imm12, width_i_imm);
    instr->setOpType(BrType::JALR);
    instr->setArgs(IntrBrArgs{0, addr});
    instr->setDestReg(rd, RegType::Integer);
    instr->setSrcReg(0, rs1, RegType::Integer);
    ibuffer.push_back(instr);
  } break;
  case Opcode::L:
  case Opcode::FL:
  case Opcode::S:
  case Opcode::FS: {
    bool is_float = (op == Opcode::FL || op == Opcode::FS);
    bool is_load = (op == Opcode::L || op == Opcode::FL);
  #ifdef EXT_V_ENABLE
    if (is_float && funct3 != 0x2 && funct3 != 0x3) {
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::LSU);
      IntrVlsArgs instArgs{};
      instArgs.mew = (code >> shift_vmew) & mask_vmew;
      instArgs.vm = (code >> shift_vm) & mask_vm;
      instArgs.nf = (code >> shift_vnf) & mask_vnf;
      switch (funct3) {
      case 0: instArgs.width = 0; break;
      case 5: instArgs.width = 1; break;
      case 6: instArgs.width = 2; break;
      case 7: instArgs.width = 3; break;
      default:
        DECODE_ABORT();
      }
      instr->setSrcReg(0, rs1, RegType::Integer);
      auto mop = (code >> shift_vmop) & mask_vmop;
      switch (mop) {
      case 0b00:
        instr->setOpType(is_load ? VlsType::VL : VlsType::VS);
        instArgs.umop = rs2;
        break;
      case 0b10:
        instr->setOpType(is_load ? VlsType::VLS : VlsType::VSS);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 0b01:
      case 0b11:
        instr->setOpType(is_load ? VlsType::VLX : VlsType::VSX);
        instr->setSrcReg(1, rs2, RegType::Vector);
        break;
      }
      if (is_load) {
        instr->setDestReg(rd, RegType::Vector);
      } else {
        instr->setSrcReg(2, rd, RegType::Vector);
      }
      instr->setArgs(instArgs);
      ibuffer.push_back(instr);
    } else
  #endif // EXT_V_ENABLE
    {
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::LSU);
      instr->setSrcReg(0, rs1, RegType::Integer);
      uint32_t imm12 = 0;
      if (is_load) {
        imm12 = code >> shift_rs2;
        instr->setDestReg(rd, is_float ? RegType::Float : RegType::Integer);
      } else {
        imm12 = (funct7 << width_reg) | rd;
        instr->setSrcReg(1, rs2, is_float ? RegType::Float : RegType::Integer);
      }
      auto offset = sext(imm12, width_i_imm);
      instr->setOpType(is_load ? LsuType::LOAD : LsuType::STORE);
      instr->setArgs(IntrLsuArgs{funct3, is_float, offset});
      ibuffer.push_back(instr);
    }
  } break;
  case Opcode::FENCE: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::LSU);
    instr->setOpType(LsuType::FENCE);
    instr->setArgs(IntrLsuArgs{0, 0, 0});
    ibuffer.push_back(instr);
  } break;
  case Opcode::AMO: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::LSU);
    uint32_t aq = (code >> shift_aq) & mask_aq;
    uint32_t rl = (code >> shift_rl) & mask_rl;
    switch (funct5) {
    case 0x00: instr->setOpType(AmoType::AMOADD); break;
    case 0x01: instr->setOpType(AmoType::AMOSWAP); break;
    case 0x02: instr->setOpType(AmoType::LR); break;
    case 0x03: instr->setOpType(AmoType::SC); break;
    case 0x04: instr->setOpType(AmoType::AMOXOR); break;
    case 0x08: instr->setOpType(AmoType::AMOOR); break;
    case 0x0c: instr->setOpType(AmoType::AMOAND); break;
    case 0x10: instr->setOpType(AmoType::AMOMIN); break;
    case 0x14: instr->setOpType(AmoType::AMOMAX); break;
    case 0x18: instr->setOpType(AmoType::AMOMINU); break;
    case 0x1c: instr->setOpType(AmoType::AMOMAXU); break;
    default:
      DECODE_ABORT();
    }
    instr->setArgs(IntrAmoArgs{funct3, aq, rl});
    instr->setDestReg(rd, RegType::Integer);
    instr->setSrcReg(0, rs1, RegType::Integer);
    instr->setSrcReg(1, rs2, RegType::Integer);
    ibuffer.push_back(instr);
  } break;
  case Opcode::SYS: {
    if (funct3 != 0) { // CSRRW/CSRRS/CSRRC
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::SFU);
      instr->setDestReg(rd, RegType::Integer);
      switch (funct3) {
      case 1: case 5: instr->setOpType(CsrType::CSRRW); break;
      case 2: case 6: instr->setOpType(CsrType::CSRRS); break;
      case 3: case 7: instr->setOpType(CsrType::CSRRC); break;
      default:
        DECODE_ABORT();
      }
      auto imm12 = code >> shift_rs2;
      if (funct3 < 5) {
        instr->setSrcReg(0, rs1, RegType::Integer);
        instr->setArgs(IntrCsrArgs{0, 0, imm12});
      } else { // zimm
        instr->setArgs(IntrCsrArgs{1, rs1, imm12});
      }
      ibuffer.push_back(instr);
    } else { // ECALL/EBREACK/URET/SRET/MRET
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
      auto imm12 = code >> shift_rs2;
      instr->setOpType(BrType::SYS);
      instr->setArgs(IntrBrArgs{0, imm12});
      ibuffer.push_back(instr);
    }
  } break;
  case Opcode::FCI: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::FPU);
    instr->setArgs(IntrFpuArgs{funct3, rs2, (funct7 & 0x1)});
    switch (funct7) {
    case 0x00: // RV32F: FADD.S
    case 0x01: // RV32D: FADD.D
      instr->setOpType(FpuType::FADD);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x04: // RV32F: FSUB.S
    case 0x05: // RV32D: FSUB.D
      instr->setOpType(FpuType::FSUB);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x08: // RV32F: FMUL.S
    case 0x09: // RV32D: FMUL.D
      instr->setOpType(FpuType::FMUL);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x10: // RV32F: FSGNJ.S, FSGNJN.S, FSGNJX.S
    case 0x11: // RV32D: FSGNJ.D, FSGNJN.D, FSGNJX.D
      instr->setOpType(FpuType::FSGNJ);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x14: // RV32F: FMIN.S, FMAX.S
    case 0x15: // RV32D: FMIN.D, FMAX.D
      instr->setOpType(FpuType::FMINMAX);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x0c: // RV32F: FDIV.S
    case 0x0d: // RV32D: FDIV.D
      instr->setOpType(FpuType::FDIV);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x20: // FCVT.S.D
    case 0x21: // FCVT.D.S
      instr->setOpType(FpuType::F2F);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      break;
    case 0x2c: // FSQRT.S
    case 0x2d: // FSQRT.D
      instr->setOpType(FpuType::FSQRT);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Float);
      break;
    case 0x50: // FLE.S, FLT.S, FEQ.S
    case 0x51: // FLE.D, FLT.D, FEQ.D
      instr->setOpType(FpuType::FCMP);
      instr->setDestReg(rd, RegType::Integer);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Float);
      break;
    case 0x60: // FCVT.W.D, FCVT.WU.D, FCVT.L.D, FCVT.LU.D
    case 0x61: // FCVT.W.S, FCVT.WU.S, FCVT.L.S, FCVT.LU.S
      instr->setOpType(FpuType::F2I);
      instr->setDestReg(rd, RegType::Integer);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::None);
      break;
    case 0x68: // FCVT.S.W, FCVT.S.WU, FCVT.S.L, FCVT.S.LU
    case 0x69: // FCVT.D.W, FCVT.D.WU, FCVT.D.L, FCVT.D.LU
      instr->setOpType(FpuType::I2F);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Integer);
      instr->setSrcReg(1, rs2, RegType::None);
      break;
    case 0x70: // FCLASS.S, FMV.X.S
    case 0x71: // FCLASS.D, FMV.X.D
      instr->setOpType((funct3 != 0) ? FpuType::FCLASS : FpuType::FMVXW);
      instr->setDestReg(rd, RegType::Integer);
      instr->setSrcReg(0, rs1, RegType::Float);
      break;
    case 0x78: // FMV.S.X
    case 0x79: // FMV.D.X
      instr->setOpType(FpuType::FMVWX);
      instr->setDestReg(rd, RegType::Float);
      instr->setSrcReg(0, rs1, RegType::Integer);
      break;
    default:
      DECODE_ABORT();
    }
    ibuffer.push_back(instr);
  } break;
  case Opcode::FMADD:
  case Opcode::FMSUB:
  case Opcode::FNMADD:
  case Opcode::FNMSUB: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::FPU);
    instr->setOpType((op == Opcode::FMADD) ? FpuType::FMADD :
                     (op == Opcode::FMSUB) ? FpuType::FMSUB :
                     (op == Opcode::FNMADD) ? FpuType::FNMADD : FpuType::FNMSUB);
    instr->setArgs(IntrFpuArgs{funct3, funct2, (funct7 & 0x1)});
    instr->setDestReg(rd, RegType::Float);
    instr->setSrcReg(0, rs1, RegType::Float);
    instr->setSrcReg(1, rs2, RegType::Float);
    instr->setSrcReg(2, rs3, RegType::Float);
    ibuffer.push_back(instr);
  } break;
#ifdef EXT_V_ENABLE
  case Opcode::VSET: {
    auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::VPU);
    uint32_t vm = (code >> shift_vm) & mask_vm;
    switch (funct3) {
    case 0: { // OPIVV
      instr->setOpType(VopType::OPIVV);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Vector);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 1: { // OPFVV
      instr->setOpType(VopType::OPFVV);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, (funct6 == 16) ? RegType::Float : RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Vector);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 2: { // OPMVV
      instr->setOpType(VopType::OPMVV);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, (funct6 == 16) ? RegType::Integer : RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Vector);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 3: { // OPIVI
      instr->setOpType(VopType::OPIVI);
      instr->setArgs(IntrVopArgs{vm, funct6, rs1});
      instr->setDestReg(rd, RegType::Vector);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 4: { // OPIVX
      instr->setOpType(VopType::OPIVX);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Integer);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 5: { // OPFVF
      instr->setOpType(VopType::OPFVF);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Float);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 6: { // OPMVX
      instr->setOpType(VopType::OPMVX);
      instr->setArgs(IntrVopArgs{vm, funct6, 0});
      instr->setDestReg(rd, (funct6 == 16) ? RegType::Integer : RegType::Vector);
      instr->setSrcReg(0, rs1, RegType::Integer);
      instr->setSrcReg(1, rs2, RegType::Vector);
    } break;
    case 7: {
      instr->setDestReg(rd, RegType::Integer);
      if ((code >> 30) == 0b10) { // vsetvl
        instr->setOpType(VsetType::VSETVL);
        instr->setArgs(IntrVsetArgs{0, 0});
        instr->setSrcReg(0, rs1, RegType::Integer);
        instr->setSrcReg(1, rs2, RegType::Integer);
      } else {
        auto zimm = (code >> shift_vzimm) & mask_vzimm;
        if ((code >> 30) == 0b11) { // vsetivli
          instr->setOpType(VsetType::VSETIVLI);
          instr->setArgs(IntrVsetArgs{zimm, rs1});
        } else { // vsetvli
          instr->setOpType(VsetType::VSETVLI);
          instr->setArgs(IntrVsetArgs{zimm, 0});
          instr->setSrcReg(0, rs1, RegType::Integer);
        }
      }
    } break;
    default:
      DECODE_ABORT();
    }
    ibuffer.push_back(instr);
  } break;
#endif // EXT_V_ENABLE
  case Opcode::EXT1: {
    switch (funct7) {
    case 0: {
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::SFU);
      IntrWctlArgs wctlArgs{};
      switch (funct3) {
      case 0: // TMC
        instr->setOpType(WctlType::TMC);
        instr->setSrcReg(0, rs1, RegType::Integer);
        break;
      case 1: // WSPAWN
        instr->setOpType(WctlType::WSPAWN);
        instr->setSrcReg(0, rs1, RegType::Integer);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 2: // SPLIT
        instr->setOpType(WctlType::SPLIT);
        instr->setDestReg(rd, RegType::Integer);
        instr->setSrcReg(0, rs1, RegType::Integer);
        wctlArgs.is_neg = (rs2 != 0);
        break;
      case 3: // JOIN
        instr->setOpType(WctlType::JOIN);
        instr->setSrcReg(0, rs1, RegType::Integer);
        break;
      case 4: // BAR
        instr->setOpType(WctlType::BAR);
        instr->setSrcReg(0, rs1, RegType::Integer);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 5: // PRED
        instr->setOpType(WctlType::PRED);
        instr->setSrcReg(0, rs1, RegType::Integer);
        instr->setSrcReg(1, rs2, RegType::Integer);
        wctlArgs.is_neg = (rd != 0);
        break;
      default:
        DECODE_ABORT();
      }
      instr->setArgs(wctlArgs);
      ibuffer.push_back(instr);
    } break;
    case 1: { // VOTE
      auto instr = std::allocate_shared<Instr>(instr_pool_, uuid, FUType::ALU);
      instr->setDestReg(rd, RegType::Integer);
      instr->setSrcReg(0, rs1, RegType::Integer);
      switch (funct3) {
      case 0:
        instr->setOpType(VoteType::ALL);
        break;
      case 1:
        instr->setOpType(VoteType::ANY);
        break;
      case 2:
        instr->setOpType(VoteType::UNI);
        break;
      case 3:
        instr->setOpType(VoteType::BAL);
        break;
      case 4:
        instr->setOpType(ShflType::UP);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 5:
        instr->setOpType(ShflType::DOWN);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 6:
        instr->setOpType(ShflType::BFLY);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      case 7:
        instr->setOpType(ShflType::IDX);
        instr->setSrcReg(1, rs2, RegType::Integer);
        break;
      default:
        DECODE_ABORT();
      }
      ibuffer.push_back(instr);
    } break;
  #ifdef EXT_TCU_ENABLE
    case 2: {
      switch (funct3) {
      case 0: { // WMMA
        namespace vt = vortex::tensor;
        using cfg = vt::wmma_config_t<NUM_THREADS>;
        uint32_t ra_base = 0;
        uint32_t rb_base = (cfg::NRB == 4) ? 28 : 10;
        uint32_t rc_base = (cfg::NRB == 4) ? 10 : 24;
        uint32_t fmt_d = rd;
        uint32_t fmt_s = rs1;
        uint32_t steps = 0;
        uint32_t steps_count = cfg::m_steps * cfg::n_steps * cfg::k_steps;
        uint32_t steps_shift = 32 - log2ceil(steps_count);
        uint32_t uuid_hi = (uuid >> 32) & 0xffffffff;
        uint32_t uuid_lo = uuid & 0xffffffff;
        for (uint32_t k = 0; k < cfg::k_steps; ++k) {
          for (uint32_t m = 0; m < cfg::m_steps; ++m) {
            for (uint32_t n = 0; n < cfg::n_steps; ++n) {
              uint32_t rs1 = ra_base + (m / cfg::a_sub_blocks) * cfg::k_steps + k;
              uint32_t rs2 = rb_base + (k * cfg::n_steps + n) / cfg::b_sub_blocks;
              uint32_t rs3 = rc_base + m * cfg::n_steps + n;
              uint32_t uuid_lo_x = (steps << steps_shift) | uuid_lo;
              uint64_t uuid_x = (static_cast<uint64_t>(uuid_hi) << 32) | uuid_lo_x;
              ++steps;
              auto instr = std::allocate_shared<Instr>(instr_pool_, uuid_x, FUType::TCU);
              instr->setOpType(TcuType::WMMA);
              instr->setArgs(IntrTcuArgs{fmt_s, fmt_d, m, n});
              instr->setDestReg(rs3, RegType::Float);
              instr->setSrcReg(0, rs1, RegType::Float);
              instr->setSrcReg(1, rs2, RegType::Float);
              instr->setSrcReg(2, rs3, RegType::Float);
              ibuffer.push_back(instr);
            }
          }
        }
      } break;
      default:
        DECODE_ABORT();
      }
    } break;
  #endif
    default:
      DECODE_ABORT();
    }
  } break;
  default:
    DECODE_ABORT();
  }
}
