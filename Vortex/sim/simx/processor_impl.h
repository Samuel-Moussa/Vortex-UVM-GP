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

#pragma once

#include <deque>
#include "mem_sim.h"
#include "cache_sim.h"
#include "constants.h"
#include "dcrs.h"
#include "cluster.h"
#include "simx_cosim_record.h"

namespace vortex {

class ProcessorImpl {
public:
  struct PerfStats {
    CacheSim::PerfStats l3cache;
    MemSim::PerfStats memsim;
    uint64_t mem_reads;
    uint64_t mem_writes;
    uint64_t mem_latency;
  };

  ProcessorImpl(const Arch& arch);
  ~ProcessorImpl();

  void attach_ram(RAM* mem);

  int run();
  void step(uint64_t cycles); // <--- ADD THIS
  bool is_done() const;       // <--- ADD THIS to check status
  int  get_exitcode() const;   // returns exit code after is_done() == true
  
  void dcr_write(uint32_t addr, uint32_t value);

  // M1 cosim retire-record queue (Option β)
  void     cosim_push_retire(const simx_retire_t& rec) { cosim_log_.push_back(rec); }
  bool     cosim_drain_retire(simx_retire_t& out) {
    if (cosim_log_.empty()) return false;
    out = cosim_log_.front();
    cosim_log_.pop_front();
    return true;
  }
  uint32_t cosim_pending() const { return static_cast<uint32_t>(cosim_log_.size()); }
  void     cosim_clear() { cosim_log_.clear(); }

#ifdef VM_ENABLE
  void set_satp(uint64_t satp);
#endif

  PerfStats perf_stats() const;

private:

  void reset();

  const Arch& arch_;
  std::vector<std::shared_ptr<Cluster>> clusters_;
  DCRS dcrs_;
  MemSim::Ptr memsim_;
  CacheSim::Ptr l3cache_;
  uint64_t perf_mem_reads_;
  uint64_t perf_mem_writes_;
  uint64_t perf_mem_latency_;
  uint64_t perf_mem_pending_reads_;
  int      exitcode_;    // ADD: stores exit code when step() or run() finishes
  std::deque<simx_retire_t> cosim_log_;  // M1: unbounded retire-record queue
};

}
