# Handover لأحمد — تعديلات Samuel في lane الـ coverage / scoreboard

الغرض: أشرحلك بالظبط اللي لمسته في ملفاتك (coverage collector + scoreboard + status agent)
عشان تراجعه وتعمل sign-off. كله اتعمل تحت توجيه Samuel، لكن الملفات دي lane بتاعك.

الكوميتات: `148ff78`, `55ac424`, `3fdf359`, `0cfec34` (collector) ·
`55661d7`, `bc96979`, `4b7c55c` (scoreboard) · `a3ce838`, `1dfab0c` (status / probe).

---

## أ) `uvm_env/vortex_coverage_collector.sv` — 4 تعديلات (كلها `ignore_bins`)

1. **`148ff78`** — AXI ignores مبنية على دليل + خريطة reachability في الكومنت:
   - `cp_size` (awsize=CLOG2(DATA_SIZE) → native فقط) 12.5→100.
   - `cp_burst`/`cp_len` (FIXED/single) 100.
   - `cp_bresp`/`cp_rresp0` (الـ TB دايمًا OKAY، مافيش error-inject test) 25→100.
   - `cross_type_burst_size` 12.5→100.

2. **`55ac424`** — config-aware: `cp_num_*` بقى فيها `ignore_bins ... with (item != CFG_*)`
   مربوطة بـ `` `NUM_* `` → كل build يعدّ الـ reachable bins بتاعته بس → auto-adapt لأي config.

3. **`3fdf359`** — structural ignores على `cp_id_route` (route≥32 + even≥16) و
   `cross_type_route` (READ×[17:31], WRITE×even). route field = `id[ROUTE_W-1:0]`, ROUTE_W=6.

4. **`0cfec34`** — waiver مبني على دليل للـ residual:
   - `route_emergent_read = {4,6,8,10,12,14}` (read-only MSHR slot idx).
   - `route_high_write_tag = {23,27,31}` (write src/counter id).
   - `cross_type_route: rd_emergent = read × {1,5,9,13}`.
   - **الإثبات (3 نقاط) في الكومنت inline:** structure = الـ read route = tbuf_waddr = MSHR
     free-list slot من الـ lowest-free priority encoder (بكينج داخلي مش DUT-visible) ·
     not-controllable = الـ slot بيتحدد بترتيب release بتاع Ramulator، مفيش instruction بيختاره ·
     empirical = 29-run suite + 4 directed `axi_stress` runs وصلوا read depth slot 15 وماطلّعوش الـ evens.

**TRIP-WIRE (محتاج تراجعه):** كل ده معمول لـ `ROUTE_W==6` (1CL/1C/4W/4T). أي config أوسع
بيكبّر `VX_MEM_TAG_WIDTH` والـ slot space → لازم re-derive. الأفضل تخلّي الـ collector يشتق
الـ route ignores أوتوماتيك من `TAG_BUFFER_SIZE`/`ROUTE_W` (بدل الأرقام الـ hardcoded).

**نتيجة الـ re-merge (session 4):** covergroup functional bins 72.70% ·
`cp_id_route` + `cross_type_route` = **100%** (الـ waiver اتحقق في merge حقيقي).

---

## ب) `uvm_env/vortex_scoreboard.sv` — 3 تعديلات

### ب.1 `55661d7` — نافذة المقارنة + استقبال crash + قفل vacuous
- **compare window fallback:** لو مافيش result window (kernel_launch/riscv-dv) → قارن المنطقة
  كلها `[RAM_BASE, DATA_LIMIT)` بدل ما `in_result=0` يسكِّت المقارنة. الـ stack/local/MMIO مستثنيين.
- **sentinel `-3`:** لو `simx_run()` رجّع `-3` → `simx_crashed=1` + `return` (يسكِب المقارنة) = UNVERIFIABLE.
- **قفل VACUOUS RUN:** window مُعلَن باسم صفر مقارنات = لسه FAIL. run بدون window + ebreak + simx_ran = PASS على liveness.

### ب.2 `bc96979` — مقارنة أمينة للـ fpu/barrier (استثناءان مبدئيان)
- `is_got_reloc()`: DUT=0 بينما SimX=pointer في program-region → `.got`/relocation entry
  (مش output محسوب — barrier_lite addr 0x80001e98).
- `f32_close()`/`fp_lanes_close()`: مقارنة FP بتسامح ≤`FP_ULP_TOL`(=2) ULP أو denormal-flush per
  f32 lane — **بس** للكِرنلات اللي `program_path` فيه "fpu". NaN/Inf لازم يتطابقوا بالظبط.
- **مهم:** أي injected fault (negative test) بيتعامل كـ `is_injected` **قبل** أي استثناء →
  مستحيل يتغطّى بالـ GOT/FP exceptions.

### ب.3 `4b7c55c` — byte-valid mask
- `shadow_valid [bit[31:0]]` per-byte: sub-word stores (`sb`/`sh`) في preinit `.data`
  مابقتش تعمل false-mismatch (الـ sparse shadow كان بيسيب الـ lanes التانية 0 بينما SimX بيرجّع
  merge). لـ full 8-byte write الـ mask = `0xFF` = **no-op** → الـ NEG لسه بيمسك.

**عايز منك sign-off:** إن الاستثناءات دي (GOT/FP/byte-mask) صح مبدئيًا، وإن NEG لسه أحمر عند الحقن.

---

## ج) status agent + probe — تغذية الـ coverage

### ج.1 `a3ce838` — fetch/memory stalls
- `tb/vortex_status_if.sv`: ضفت `fetch_stall`/`memory_stall` كـ wires + في الـ clocking/modports.
- `status_monitor.sv`: بيسمبلهم في الـ transaction (sample + ebreak paths).
- `status_transaction.sv`: `uvm_field_int` للحقلين.
- النتيجة: `cp_fetch/memory_stall` 50→100%.

### ج.2 `1dfab0c` — `tb/vx_instr_probe.sv`
- TCU covergroup guard.

**المطلوب منك:** تعلّق الـ covergroups على `fetch_stall`/`memory_stall`، وتصلّح cadence الـ
`cp_active_warps` sampling (16% = اتسمبل مرة واحدة، بيفوّت الـ ramp/drain).

---

## المطلوب منك (checklist)
- [ ] sign-off على route waiver + الـ trip-wire (ROUTE_W==6)، ويفضّل تخليه config-derived.
- [ ] sign-off على scoreboard: GOT/FP tolerance/byte-mask، وتأكيد NEG catches.
- [ ] تعليق covergroups على fetch/memory stalls + إصلاح `cp_active_warps` sampling cadence.
- [ ] `cp_num_clusters` (CFG_CLUSTERS declared-but-unused) + span `cp_active_warps` على NUM_WARPS.
