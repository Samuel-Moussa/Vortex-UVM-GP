# Handover لستيفن — تعديلات Samuel في lane الـ SimX / DPI

الغرض: أشرحلك بالظبط اللي عملته في ملفاتك (SimX/DPI/بناء SimX) عشان تراجعه وتعمل sign-off.
كله اتعمل تحت توجيه Samuel لأنه كان بيكسر co-sim لكل الأنواع، لكن الملفات دي lane بتاعك.

الكوميتات المعنية: `55661d7`, `1ce1e9f`, `f59efa9`, `600395d`, `2c8d008`.

---

## 1) `uvm_env/ref_model/simx_dpi.cpp` (`55661d7`) — إصلاح co-sim جوهري

ده الـ DPI-C bridge اللي بيشغّل SimX (الـ golden reference). فيه 3 إصلاحات مترابطة:

### 1.1 السبب الأصلي: reset في المكان الغلط (أهم إصلاح)
الكود القديم قبل الـ step loop:
```cpp
g_processor->step(0);   // المفروض one-shot device reset
```
- `ProcessorImpl::step()` **مش بيعمل reset** (سطر الـ reset جواه متعلّق عليه كومنت).
- `step(0)` = "اخطُ صفر cycle" = **no-op تمامًا**.
- النتيجة: الـ cores بتبدأ من حالة un-reset، الـ PC مش على startup address → بتقرأ garbage وتفكّه كـ instruction → `abort()` عند cycle 0. ده اللي كان بيكسر DUT-vs-SimX لكل الأنواع.

الإصلاح:
```cpp
SimPlatform::instance().reset();   // زي ما ProcessorImpl::run() بيعمل بالظبط
```
بيعمل `do_reset()` لكل core/cache → الـ PC يبدأ من DCR startup address الصح. **مهم:** الـ `g_ram` منفصل ومابيتمسحش، فلسه بيعملوا replay للـ staged writes بعده دفاعيًا.

**عايز منك تأكيد:** إن `SimPlatform::instance().reset()` هو السلوك الصح للـ configs كلها (مش بس 1CL/1C).

### 1.2 استنتاج الـ startup address من منطقة الكود بس
كان:
```cpp
if (addr >= 0x80000000ULL) g_startup_addr = addr;
```
المشكلة: الـ regression harness بيحطّ `kernel_arg_t` + I/O buffers في منطقة DATA (`≥ 0x9000_0000`). أي write منهم كان بيحرّك `g_startup_addr` غلط → SimX يبدأ التنفيذ من الـ data → decode abort عند cycle 0.

الإصلاح:
```cpp
if (addr >= 0x80000000ULL && addr < 0x90000000ULL) g_startup_addr = addr;
```

### 1.3 Crash guard عشان كراش SimX مايوقّعش vsim كله
SimX ممكن يعمل `abort()`/segfault جوه `Emulator::decode` على تعليمات مش بيعرف يمثّلها. الـ `abort()` **مش بيتمسك بـ try/catch** وكان هيوقّع vsim كله.

الإصلاح — `SIGABRT`/`SIGSEGV` handlers حوالين الـ step loop مع `sigsetjmp`/`siglongjmp`:
```cpp
g_simx_crashed = 0;
struct sigaction sa, old_abrt, old_segv;
sa.sa_handler = simx_crash_handler;
sigemptyset(&sa.sa_mask); sa.sa_flags = 0;
sigaction(SIGABRT, &sa, &old_abrt);
sigaction(SIGSEGV, &sa, &old_segv);

if (sigsetjmp(g_simx_jmp, 1) == 0) {
    while (!g_processor->is_done() && cycles_run < MAX_CYCLES) {
        g_processor->step(STEP_CHUNK);
        cycles_run += STEP_CHUNK;
    }
}
// crash path falls through with g_simx_crashed == 1
sigaction(SIGABRT, &old_abrt, nullptr);
sigaction(SIGSEGV, &old_segv, nullptr);

if (g_simx_crashed) {
    run_status = -3; g_done = false; g_exitcode = run_status;
    return g_exitcode;   // scoreboard يترجم -3 => UNVERIFIABLE
}
```
لو SimX وقع، `siglongjmp` يرجّع لبرّه، يرجّع stdout، ويطلّع sentinel **`-3`** = UNVERIFIABLE (مش فشل DUT).

**عايز منك تأكيد:** إن الـ `-3` sentinel متوافق مع أي exit-code polishing بتعمله، وإن مفيش قيمة exit حقيقية من SimX بتساوي `-3`.

---

## 2) `scripts/prepare.sh` (`1ce1e9f`) — بناء SimX per-config
- الـ `Core::issue` loop مربوط compile-time بـ `PER_ISSUE_WARPS`، بس الـ `ibuffers_` متحجّم runtime → default-NUM_WARPS objects كانت بتكراش (`vector::_M_range_check`) عند warps/threads<4.
- الإصلاح: إعادة بناء SimX core objects لكل config (`CONFIGS=$ARCH_FLAGS`) في الـ DPI build.
- **ده مكانش bug في Ramulator ولا SimX-core.** بعده: 2C/4W/4T→140cmp PASS، 2CL/2C/4W/4T→252cmp PASS، 4C/2W→PASS.

**عايز منك sign-off:** إن الـ per-config rebuild صح ومش بيكسر أي assumption في بناء SimX عندك.

---

## 3) `scripts/prepare.sh` — riscv-dv flow (`f59efa9`, `600395d`, `2c8d008`)
- `f59efa9`: arithmetic tests بقت self-checking عبر GPR-dump + `vx_tmc 0` exit.
- `600395d`: إصلاح epilogue injection (يحافظ على sub-programs).
- `2c8d008`: إصلاح bug الـ gawk `\b` اللي كان بيمسح ذيل الـ assembly.

**ملاحظة FP لك:** الـ scoreboard دلوقتي فيه FP-compare tolerance (≤2 ULP / denormal-flush للكِرنلات اللي path فيها "fpu") — محتاج تأكيدك إنها متوافقة مع softfloat في SimX (fpu_test بيّن divergence 1-ULP).

---

## المطلوب منك (checklist)
- [ ] sign-off على `SimPlatform::instance().reset()` لكل الـ configs.
- [ ] تأكيد إن sentinel `-3` مايتعارضش مع exit-code polishing.
- [ ] sign-off على per-config SimX rebuild في `prepare.sh`.
- [ ] تأكيد FP tolerance متوافقة مع softfloat.
