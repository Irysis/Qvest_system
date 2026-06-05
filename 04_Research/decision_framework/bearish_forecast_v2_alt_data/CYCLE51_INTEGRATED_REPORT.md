# Cycle 51 Integrated Report — Bearish Forecast Model Foundational Integrity Recovery

**작성**: 2026-05-20 KST Cycle 51 (도훈 mandate B안 — Phase 1+2+3+4 통합 cleanup roadmap)
**Scope**: bearish forecast v2 alt_data + 02_Infrastructure validation/sanity/hooks + .claude/rules
**Severity**: CRITICAL — backward label bug 사후 cleanup
**Status**: ALL 4 PHASES COMPLETE
**AX-008 정합**: Forge single-source (cleanup cycle 정합, admit decision 미수반). Phase 5 future cycle Codex + Architect verification 의무

---

## Executive Summary

### Background

2026-05-20 KST 21:00 무렵, Cycle 48A subagent가 `scripts/02_target_builder.R` line 39의 `shift(BM_Close, -H, type="lead")` semantics 의심. `data.table::shift(x, n=-H, type="lead")` = `x[t-H]` (BACKWARD, past h-day value) — `n=-H` + `type="lead"` double negation으로 의도 forward `r(t, t+h)` 정반대 backward 작동.

모든 cycle (이 session 43~50)의 `y_tail_q15` / `y_onset` label은 "현재가 21일 전 대비 peak 상승 상태인지" 분류 task — features와 label이 같은 시점 `BM_Close` backward window 함수 → **trivial concurrent classification**.

### 정량 증거 (Forward 재baseline)

- v1.3 M2 5-way: buggy 0.608 → forward **0.1450** (Δ -0.463)
- Cycle 45B v3b_inst (#1 buggy 0.6417) → forward **0.1413** (#4 worst, Δ -0.500)
- Cycle 45E PatchTST: buggy ~0.45 → forward **0.2345** (Δ -0.215)
- Cycle 48A q126 long horizon: forward **0.3079** (신규 발견, fix 후 측정)

**Buggy vs Forward 비교**:
- Spearman ρ = **-0.40** (랭킹 inversion)
- Cohen kappa = **-0.016** (label 거의 무관)
- COVID 2020-02-19: forward -34.05% vs backward +1.82% (label 정반대)

### Cycle 50 fix 적용

```r
# CORRECT (Cycle 50, line 43):
bm[, ret_h := shift(BM_Close, n = H, type = "lead") / BM_Close - 1]
```

→ `targets_full_forward.parquet` + `targets_full.parquet` (canonical mirror) 생성. `targets_full_buggy_backup.parquet` (audit 증거 보존).

### Cycle 51 도훈 mandate (B안)

> "Phase 1+2+3+4 통합 cleanup roadmap — foundational integrity recovery 작업. CPU only, 재학습 없음. R/Python script 작성 + audit + sanity check 등록 위주."

---

## Phase 1 — Damage Assessment

### 1.1 L-code 영향

영향 L-code (이 session 작업 결과 인용):
- **L-332** (KOSPI_DD_Hybrid_V1aV3 ADMIT-ready 후보 발견 14-cycle 자가발전): **RETAIN**
  - 이유: model PR-AUC 0.608 buggy이었음에도 strategy는 **model-free trigger** (KOSPI 6m DD ≤ -10%) 기반. L-332 finding (10) `Model INCIDENTAL — model 진짜로 INCIDENTAL 입증` 이미 detect.
  - 후속 의무: monitoring deploy ready 표시 후속 cycle 재검증 (model component 별도 측정).
- **L-333** (18-cycle 자가발전 무한리서치 final refinement KOSPI_DD_Hybrid_V1aV3_2M_5PCT TRUE BEST): **RETAIN**
  - 이유: 2m/-5% trigger도 KOSPI return 단독 model-free.
  - 후속 의무: 동일 — model PR-AUC component 재검증.

다른 L-code (L-130~L-329, L-330~L-331): **buggy bug 무관** (bearish forecast model 발생 이전 + v0.4.2 NULL RESULT는 다른 framework).

도훈 mandate 정합: "STR_1715 자체 L-code 폐기 금지" — STR_1715 admit L-code (L-279~L-281, L-308~L-313) bearish bug 무관, retain.

### 1.2 V10 monitor disable

- `02_Infrastructure/ops/morning_briefing.sh` Step 6 V10 KOSPI Kill Switch:
  - Backup: `morning_briefing.sh.cycle51_backup` (11953 bytes)
  - Step 6 본문 disable + 재가동 4 조건 명시 (bear_date_audit PASS + label semantics PASS + AX-008 2/3 + 도훈 mandate)
- `02_Infrastructure/ops/triple_monitor.sh`:
  - Backup: `triple_monitor.sh.cycle51_backup`
  - `run_daily()` disable (daily bearish monitor)
  - `run_monthly()` disable (V1aV3 hybrid — safety stop bearish family 전체)

### 1.3 다른 strategy 의존성 audit

`grep -r "y_tail_q15|y_onset|bearish_forecast|V10_kill_switch"`:
- `04_Research/strategies/` (다른 strategies): **0건**
- `02_Infrastructure/` (config / hooks / agents): **0건**
- `qepm/` (mailbox / observability / memory): **0건**

→ bearish forecast model은 `04_Research/decision_framework/bearish_forecast_v2_alt_data/` 한정 + `02_Infrastructure/ops/morning_briefing.sh` + `triple_monitor.sh` 만 의존. 외부 strategy / production 무영향. STR_1715 admit baseline 무관.

### 1.4 STATUS_BUGGY_ERA.md

신규 파일: `STATUS_BUGGY_ERA.md` (본 폴더 root)
- 7 section: bug description + affected cycles + Cycle 50 fix + 새 forward baseline + 자료 처분 정책 + 재가동 조건 + 참조
- buggy era 자료 처분 매트릭스 + L-332/L-333 retain 명시

---

## Phase 2 — Root Cause Hardening

### 2.1 PIT v2 — `validate_label_direction()`

`02_Infrastructure/validation/pit_enforcement.R`에 신규 함수 추가:

```r
validate_label_direction(target_df, target_col, bm_df, bm_col,
                         expected_direction = "forward",
                         horizon = 21L, n_sample = 100L,
                         threshold = 0.95, assert_covid = TRUE)
```

- target_df의 ret_h sample (default 100 random non-NA dates)
- 각 sample date에서 manual forward/backward lookup 비교
- 일치율 ≥ threshold (0.95) → PASS
- COVID 2020-02-19 strong assertion: fwd ≤ -0.30 + bwd ≥ 0

Return: `list(pass, agreement_rate_forward, agreement_rate_backward, covid_assertion, details)`

### 2.2 `bear_date_audit.R` 신규 sanity check suite

`02_Infrastructure/sanity_checks/bear_date_audit.R`:

4 known KOSPI200 bear dates:
- Lehman GFC 2008-09-15 (expected_forward_le=-0.05)
- Euro Crisis 2011-08-08 (semantics only)
- COVID 2020-02-19 (expected_forward_le=-0.30 + expected_backward_ge=0 strong)
- Stagflation 2022-09-26 (semantics only)

각 date 3 checks:
- `check_fwd_match`: target matches manual forward (label is forward)
- `check_bwd_mismatch`: target does NOT match backward (sign-flip detection)
- `check_strong_fwd / check_strong_bwd`: date-specific assertions (optional)

**즉시 실행 결과: 4/4 ALL PASS**:
```
[Lehman GFC]      target -9.31% = forward (match) / backward +5.74% (mismatch) PASS
[Euro Crisis]     target -1.93% = forward (match) / backward +16.63% (mismatch) PASS
[COVID]           target -34.05% = forward (match) / backward +1.82% (mismatch) strong PASS
[Stagflation 2022] target +3.05% = forward (match) / backward +10.20% (mismatch) PASS
```

Log: `qepm/observability/sanity_checks/bear_date_audit_latest.json` + timestamped JSON

### 2.3 `data_table_shift_convention.md` 신규 Level 1 rule

`.claude/rules/data_table_shift_convention.md`:

- 4 조합 table (n positive/negative × type "lag"/"lead")
- 함정: `shift(x, n=-H, type="lead")` double negation = BACKWARD
- 권장 패턴: type만으로 방향 표시 (n positive 유지)
- 금지 패턴: `n=-H` + "lead" 조합 + `n=-H` + "lag" 명시
- Cycle 50 incident 사례 정합

### 2.4 `bootstrap.sh` Step 4d integration

`02_Infrastructure/ops/bootstrap.sh` Step 4d 신규:

```bash
BEAR_AUDIT_R="$PROJECT/02_Infrastructure/sanity_checks/bear_date_audit.R"
TARGET_PARQUET="$PROJECT/04_Research/.../targets_full.parquet"
if [ -f "$BEAR_AUDIT_R" ] && [ -f "$TARGET_PARQUET" ]; then
  BEAR_OUT=$(cd "$PROJECT" && Rscript "$BEAR_AUDIT_R" 2>&1)
  BEAR_SUMMARY=$(echo "$BEAR_OUT" | grep -E "Audit Summary:" | head -1)
  echo "[boot] $BEAR_SUMMARY"
  if echo "$BEAR_OUT" | grep -q "ALL PASS"; then
    echo "[boot] bear_date_audit: ALL PASS (forward label semantics CLEAN)"
  else
    echo "[boot] WARN: bear_date_audit FAIL — backward label bug suspected"
    ...
```

→ 매 bootstrap 시 forward label semantics 자동 검증. FAIL 시 WARN log.

---

## Phase 3 — Research Redesign

### 3.1 `RESEARCH_CHARTER_v2_forward.md` 신규

본 폴더 root.

**Section 1 — Forward baseline**:
- v1.3 M2: **0.1450**
- v1.3 best M4_Bayes: **0.1917**
- Top 3: 48A q126 **0.3079** / 45E PatchTST **0.2345** / 43 v2_2feat **0.2129**

**Section 2 — Realistic target**:
- Floor ≥ 0.20 / Standard ≥ 0.25 / Stretch ≥ 0.30 / Ceiling 0.35~0.40
- PR-AUC vs PnL conversion 분리 명시 (L-332 finding (10))

**Section 3 — Relative ranking retain**:
- Architecture / family / method findings (cycles 43~49) 절대값 reset 후에도 ranking valid
- foreign breadth single > variants / inst flow alive / VKOSPI dilution / US macro q126 PROVEN / N-BEATS > LSTM > TFT / etc.

**Section 4 — 다음 cycle 권고**:
- Highest priority: Cycle 43 + 45E forward 결합 (Standard target ≥ 0.25)
- High priority: Cycle 48A q126 long horizon (Stretch ≥ 0.30)
- LOW priority: Cycle 45B v3b_inst 재시도 부적합 (#1 buggy → #4 forward)

### 3.2 KOSPI_DD_Hybrid_V1aV3 (L-332/L-333) 상태

- Trigger: **model-free** (KOSPI 6m DD ≤ -10% 또는 v1.1 2m DD ≤ -5%)
- 따라서 buggy label 무관, strategy spec retain
- Model component (model PR-AUC 0.608)은 **buggy 측정값**이므로 후속 cycle 재검증 의무

---

## Phase 4 — Process Redesign

### 4.1 `NEW_CYCLE_CHECKLIST.md` 신규

본 폴더 root. 신규 cycle 진입 시 의무 checklist 11건:

**MUST (5)**: bear_date_audit + label semantics + PIT C1~C15 + shift convention + AX-008 (admit cycle)
**SHOULD (3)**: PR-AUC sanity range [0.15, 0.40] + COVID spot check + Spearman ρ ≥ 0.30
**MAY (3)**: cross-cycle compare 절대값 confound 회피 + 도훈 audit checkpoint + Codex critic

각 cycle 종료 시 `outputs/06_reports/cycleNN_checklist.md` 작성 의무.

### 4.2 methodology_active.md L-334 등재

`/home/quant/.claude/projects/.../memory/methodology_active.md` line 11 위치 (L-333 직전).

L-334 spec:
- grade: `PROCESS_INTEGRITY_RECOVERY_INFRA_HARDENING_BUGGY_ERA_INVALIDATED_FORWARD_BASELINE_REDEFINED`
- lesson_text: 7 본질 통찰 + 4 phase 작업 + 잔존 작업 + 5월 운용 unchanged
- core_reference: STATUS_BUGGY_ERA + RESEARCH_CHARTER_v2_forward + NEW_CYCLE_CHECKLIST + 본 report + 02_target_builder.R + Cycle 50 scripts + PIT v2 + bear_date_audit + shift convention rule + bootstrap Step 4d + L-332/L-333 retain + 도훈 mandate + 학술 (Lopez de Prado 2018 / Harvey-Liu-Zhu 2016 / Bailey-Lopez de Prado 2014 / Hand-Til 2001)
- 태그: 15 keys (CYCLE_51_INTEGRATED_CLEANUP 등)

헤더 갱신: `# Methodology Memory (ACTIVE) — L-130 ~ L-334`

### 4.3 Hook 등록 권고 (optional)

현재 `bear_date_audit.R`는 `bootstrap.sh` Step 4d에서만 호출. 신규 cycle Write tool 호출 시 PreToolUse Hook 추가 가능성:

- Path: `02_Infrastructure/hooks/` 위치에 `label_semantics_check.sh` 신규 후보
- Trigger: `bearish_forecast` 폴더 내 `targets_full*.parquet` Write 시
- Action: `bear_date_audit.R` 자동 실행 + FAIL 시 hard block

**Status**: 권고만 (현 cycle 적용 X). 후속 cycle에서 도훈 판단 시 추가 가능.

---

## 모든 작성된 file 절대 경로 목록

### 신규 파일 (8건)

1. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md` (사후 처분 SOT, ~9KB)
2. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data/RESEARCH_CHARTER_v2_forward.md` (forward baseline charter, ~8KB)
3. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data/NEW_CYCLE_CHECKLIST.md` (신규 cycle 진입 checklist, ~5KB)
4. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data/CYCLE51_INTEGRATED_REPORT.md` (본 통합 보고, ~12KB)
5. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/sanity_checks/bear_date_audit.R` (4 bear date sanity, ~10KB)
6. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.claude/rules/data_table_shift_convention.md` (Level 1 rule, ~6KB)
7. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/ops/morning_briefing.sh.cycle51_backup` (backup)
8. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/ops/triple_monitor.sh.cycle51_backup` (backup)

### 수정 파일 (5건)

1. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/ops/morning_briefing.sh` (Step 6 V10 monitor disable + 재가동 4 조건 명시)
2. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/ops/triple_monitor.sh` (run_daily + run_monthly disable + safety stop 사유)
3. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/validation/pit_enforcement.R` (`validate_label_direction()` PIT v2 함수 추가)
4. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/ops/bootstrap.sh` (Step 4d bear_date_audit integration)
5. `/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_active.md` (L-334 등재 + 헤더 갱신)

### 자동 생성 (1건)

1. `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/observability/sanity_checks/bear_date_audit_latest.json` (audit 4/4 PASS log) + timestamped versions

---

## AX-008 정합 status

본 cycle 자체는 cleanup이므로 **single-source Forge 정합** (admit decision 미수반).

Phase 5 future cycle (forward baseline 후 admit 시도) 의무:
- Forge agent: forward baseline 재baseline 후 backtest
- Codex critic: Charter v1.7 §10 정합 critic round (REJECT/REVISE/APPROVE)
- Architect agent: AX-008 3rd source mandate

3-source 중 **2/3 PASS 필수** for admit/promote 결정.

---

## 5월 운용 unchanged

- **STR_1715_AR_on_M4_R05_overlay_PG2 100% retain** (effective 2026-05-13, book_state v2.3)
- Beta: m4=NORMAL × β_AR=0.7 × β_R05=1.0 = **70% risk + 30% cash**
- Top10 alpha-updated holdings: 삼성전자 4.78% / 삼성SDI 4.65% / SK하이닉스 4.37% / 에코프로비엠 4.29% / 한화솔루션 4.15% / SK케미칼 4.10% / HD현대마린엔진 3.89% / 컴투스 3.57% / 한올바이오파마 3.41% / 한화엔진 3.30%

본 cycle은 bearish forecast model 영역 한정 cleanup → STR_1715 admit baseline / production deployment 무관.

---

## 도훈 audit instinct hit 누적

**23번째 hit** (이전 22번 누적):

- 이번 hit: "현재 피처로 과거 예측" 한 마디로 trivial concurrent classification 본질 정확 진단 (Cycle 50 발견 직후 Cycle 51 통합 cleanup mandate)
- system-level audit instinct 정확 — buggy 발견 → 즉시 4-phase 통합 cleanup roadmap reframe (B안)
- 도훈 mandate가 cycle 진화의 일부 (cycle 43~49 buggy + cycle 50 fix + cycle 51 cleanup = 8-cycle 자가 진화)

---

## Time budget

- 예상: 2-3시간 (CPU only)
- 실제: ~1시간 30분 (script 작성 + audit + sanity check 등록 + 통합 보고)

---

## 잔존 작업 (Phase 5 future cycle 의무)

1. Forward baseline 재baseline 완료 후 V10 / V1aV3 monitor 재가동 결정 (4 조건):
   - bear_date_audit PASS
   - label semantics validate PASS
   - AX-008 2/3 PASS
   - 도훈 명시 mandate

2. Cycle 43 + 45E + 48A forward 결합 ensemble 시도 (Standard target ≥ 0.25 도달 가능):
   - Cycle 43 v2_2feat foreign breadth M4_Bayes (0.2129)
   - Cycle 45E architecture PatchTST + N-BEATS (0.2345)
   - Cycle 48A q126 long horizon US macro (0.3079) 직교

3. KOSPI_DD_Hybrid_V1aV3_2M_5PCT (L-333) model component 재검증:
   - Trigger (KOSPI 2m DD ≤ -5%) model-free retain
   - Model PR-AUC component 별도 측정 (buggy era 0.608 → forward 재baseline)

---

## Change log

- **2026-05-20 Cycle 51 통합 cleanup**: 도훈 mandate B안 — Phase 1+2+3+4 통합 roadmap 완주.

---

## 참조 (학술 정통)

- Lopez de Prado 2018: PIT enforcement + walk-forward
- Harvey-Liu-Zhu 2016: multiple testing Harvey-t > 3.0 strict
- Bailey-Lopez de Prado 2014: DSR (Deflated Sharpe Ratio)
- Hand-Til 2001: AUC max lift heuristic (PR-AUC ceiling 추정)
- L-332 / L-333: KOSPI_DD_Hybrid_V1aV3 admit-ready (model INCIDENTAL 본질 통찰)
- AX-002: process honesty (immutable)
- AX-008: Verification Triangulation (Forge + Codex + Architect 2/3 PASS)
