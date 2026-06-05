# New Cycle Entry Checklist (Bearish Forecast v2 alt_data 영역)

**작성**: 2026-05-20 Cycle 51 Phase 4 (도훈 mandate B안)
**적용**: Cycle 52 이후 모든 신규 cycle 진입 시 의무

---

## 본 checklist 운영 원칙

1. **MUST 항목 (체크 안 됨 → cycle 진입 차단)**: bear_date_audit + label semantics + AX-008 (admit cycle 한정)
2. **SHOULD 항목 (체크 안 됨 → 위험 표시 + 도훈 sign-off 의무)**: sanity range + spot check
3. **MAY 항목 (체크 권장)**: cross-cycle ranking + 도훈 audit checkpoint

---

## MUST — 절대 의무 (모든 cycle)

### M1. 라벨 직진 sanity check

- [ ] `02_Infrastructure/sanity_checks/bear_date_audit.R` **4/4 PASS** (Lehman 2008-09-15 / Euro 2011-08-08 / COVID 2020-02-19 / Stagflation 2022-09-26)
  - core checks: `forward_match=YES` + `backward_mismatch=YES` (sign-flip detection)
  - COVID strong assertion: forward ret_h ≤ -0.30 + backward ret_h ≥ 0
  - Log: `qepm/observability/sanity_checks/bear_date_audit_latest.json`

### M2. Label semantics 자동 검증

- [ ] `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()` **≥ 95% 일치율 PASS** (PIT v2)
  - expected_direction="forward" + horizon=21L + n_sample=100L
  - COVID assertion: `covid_assertion$fwd_pass=TRUE`

### M3. PIT C1~C15 의무 (PIT 헌법)

- [ ] **C1**: full-sample 통계 금지 (rolling/expanding window only)
- [ ] **C2**: same-day circular reference 금지
- [ ] **C5**: overlay signal t-1 기준
- [ ] **C9**: VT/DD lag (`shift(., 1, type="lag")`)
- [ ] **C11**: 데이터 시간축 검증 (FRED 시차 등)
- [ ] **C13**: Z_Score_Aligned only (NEGATE/FLIP_SIGN 금지)

### M4. data.table::shift convention 의무

- [ ] **shift convention rule 정합** (`.claude/rules/data_table_shift_convention.md`):
  - **금지 패턴 사용 X**: `shift(x, n=-H, type="lead")` / `shift(x, n=-H, type="lag")`
  - **권장 패턴 사용**: `shift(x, n=H, type="lead")` (forward) / `shift(x, n=H, type="lag")` (backward)

### M5. AX-008 multi-source (Admit cycle 한정)

- [ ] **Forge + Codex + Architect 3-source 중 2/3 PASS** 필수 (admit/promote 결정 시만)
  - 단순 EDA / exploration cycle은 면제
  - paradigm shift / book_state mutation / production deployment 결정 cycle은 의무

### M6. Phantom-0 contamination assertion (Cycle 54D 신규)

- [ ] **q126 / q63 / q15 evaluation 사용 시 의무**: `targets_long_horizon_observable.parquet` 사용 (NaN propagation 적용본)
- [ ] **assertion 자동 실행** (cycle 시작 시):
  ```r
  obs <- as.data.table(arrow::read_parquet("outputs/02_targets/targets_long_horizon_observable.parquet"))
  for (h in c("q15", "q63", "q126")) {
    ret_col <- sprintf("ret_%s", h); y_col <- sprintf("y_tail_%s", h)
    n_phantom <- sum(is.na(obs[[ret_col]]) & !is.na(obs[[y_col]]))
    stopifnot(n_phantom == 0L)
  }
  ```
- [ ] **DEPRECATED**: `targets_long_horizon.parquet` (buggy, retain as `.cycle54d_backup` for historical analysis only)
- [ ] **Cycle 48A target generation script 수정 필요** (`scripts/103_compute_long_horizon_targets.R` 라인 78-79 — NaN propagation 패치 또는 source-of-truth migration)
- [ ] **새 cycle**: prediction 파일을 observable targets로 merge 후 PR/IC 계산 (phantom-0 rows 자동 제외)
- [ ] **Cycle 54D 실측 결과**: phantom-0 mask는 PR-AUC를 평균 +0.0037 (median +0.0005)만큼 변동시킴 → 영향 작지만 정확성 위해 의무
  - 단, T2/T3 같은 Stage 2 OOF coverage restriction과 결합 시 누적 효과 큼 (T1 0.4012 → T3 0.2887)
  - 56-2stage 같은 multi-stage pipeline에선 두 효과 (phantom-0 + coverage restriction) 분리 필수

### M7. Data source publication lag assertion (Cycle 55B 신규)

**도훈 mandate trigger** (2026-05-21): Cycle 55B PIT deep audit ("PIT 이슈 없다고 자신있게 말할 수 있어?" trigger). FRED CFNAI / ICSA / Init_Claims 모두 reference-period dated → release-date convention 위반 발견. Codex 외부 검증 confirmed 4/4 (Q1a/Q1b/Q1c/Q1d/Q2) + ECOS 보수적 lag 확인.

- [ ] **신규 외부 data source 사용 시 의무**: 각 series의 `reference_date` vs `release_date` 차이 명시 + `publication_lag_days` 적용
- [ ] **FRED series publication-lag reference table** (cycle entry 시 reference):
  ```r
  # Confirmed by Cycle 55B Q-Lead+Codex audit:
  fred_pub_lag <- list(
    T10Y2Y = 0L,         # daily, US close ET → KR next open OK (shift(1L) sufficient)
    STLFSI4 = 0L,        # Fri ~12:00 ET → Sat 01:00 KST, shift(1L) absorbs
    DGS10 = 0L, DGS2 = 0L, VIXCLS = 0L,  # all daily
    DCOILWTICO = 0L,     # daily
    BBB_Spread = 0L, HY_Spread = 0L,  # daily corporate spreads
    ICSA = 5L,           # ⚠️ Saturday-dated, released Thu following week 08:30 ET
    UNRATE = 35L,        # monthly unemployment, released 1st Friday next month + buffer
    CPIAUCSL = 35L,      # monthly CPI, released ~10-15d after month-end
    INDPRO = 25L,        # monthly Industrial Production, released ~17d
    M2SL = 35L,          # monthly M2, released ~3-4 weeks
    PERMIT = 35L,        # monthly housing permits
    UMCSENT = 25L,       # monthly UMich, released mid-month for prior
    CFNAI = 55L,         # ⚠️ Cycle 57A correction (+25L → +55L): FRED dates CFNAI at MM-START of reference month (NOT month-end). Release ~25d after month-END = ~53-55d after MM-01 dating. Empirical: cfnai_raw[2020-03-01]=-4.37 = March 2020 reading (released 2020-04-23). Verified Q-Lead pre-Codex 2026-05-21.
    DRTSCILM = 45L       # quarterly SLOOS, released ~1-2 months after quarter-end
  )
  # ECOS BOK (이미 134_ecos_fetch_kr_macro.R에 명시):
  ecos_pub_lag <- list(
    KR_M2 = 35L, KR_CPI = 35L, KR_IndProd = 50L,
    KRW_USD = 1L, KR_Call1D = 1L
  )
  # KRX (already daily-publish at 18:10 same trade day):
  krx_pub_lag <- list(Investor_Act = 0L, krx_options = 0L)  # shift(1L) at panel build absorbs
  ```
- [ ] **금지 패턴 (Cycle 55B audit-confirmed)**:
  - ❌ `nafill(raw, type="locf") + shift(1L)` for monthly/weekly series with non-trivial release lag (96_5way_retrain_v3f_us_macro.R:72-84 pattern that produces CFNAI/ICSA leaks)
  - ❌ FRED raw fetch direct shift(1L) without considering reference-period vs release-date convention
  - ✅ 대안: `series[, Date := Date + pub_lag_days]` + rolling join (134_ecos_fetch_kr_macro.R:234-256 pattern)
- [ ] **검증 의무**:
  - Each external feature가 ECOS-style explicit lag 적용 여부 확인
  - **FRED 4 features (us_t10y2y_spread_lag1 / us_initial_claims_4w_avg_lag1 / us_cfnai_lag1 / us_stlfsi_lag1)** — Cycle 55B 진단:
    - us_t10y2y_spread_lag1: GREEN (daily, shift(1L) safe)
    - us_initial_claims_4w_avg_lag1: **RED (~4-5d lookahead via ICSA Sat dating + 4w MA inherits)**
    - us_cfnai_lag1: **RED (~22d lookahead via month-end dating)**
    - us_stlfsi_lag1: GREEN (Friday release, KR next-open OK)
- [ ] **재현 가능한 sanity check (Cycle 55B audit precedent)**:
  ```r
  # CFNAI lookahead sanity check
  df <- arrow::read_parquet("outputs/01_data/feature_panel_v3f_us_macro.parquet")
  v <- df[as.Date(df$Date) == "2020-04-02", "us_cfnai_lag1"]
  # Currently: v == -18.28 (March 2020 reading, released ~2020-04-23) → BUG
  # After fix: v == -4.37 (February 2020 reading, released ~2020-03-23) until 2020-04-24
  ```
- [ ] **신규 monthly/quarterly source 추가 시 즉시 publication_lag_days 명시 의무**
- [ ] **BBVA Markets channel 주의**: bbva_market_z / bbva_macro_composite는 Init_Claims component 통해 ICSA bug 상속 (Cycle 55B Q2 confirmed) → A6_bbva_macro_builder.R 패치 필요 시 동시 fix

---

## SHOULD — 강력 권장 (위험 표시 + 도훈 sign-off 의무)

### S1. PR-AUC absolute value sanity range

- [ ] 새 cycle PR-AUC ∈ [0.15, 0.40] range
  - 0.15 미만 = base rate 13% × 1.15x 미달 → 모델 무가치
  - **0.40 초과 = 의심 신호** (base rate × 3x 이상 → buggy bug 회귀 가능성 + lookahead bias detect 의무)
  - 0.40+ 발견 시 **즉시 cycle 중단 + sanity check 반복**

### S2. COVID 2020-02-19 spot check (수동)

- [ ] `targets_full.parquet` 에서 Date == 2020-02-19 row의 ret_h 값 직접 확인
- [ ] **-34.05% 근사** (forward 21d 정합) — 만약 +1.82% 근사 시 backward bug 회귀
- [ ] R/Python interactive 또는 dedicated audit script

### S3. Spearman ρ cross-cycle ranking consistency

- [ ] 새 cycle ranking vs 이전 forward baseline ranking Spearman ρ ≥ 0.30
- [ ] ρ < 0.30 시: 새 cycle의 ranking 정합성 의심 → 도훈 sign-off 필요
- [ ] ρ < 0 (역전) 시: **즉시 cycle 중단 + bug detect 의무** (Cycle 50 사건 재발 risk)

---

## MAY — 권장 (좋은 practice)

### A1. Cross-cycle relative comparison 절대값 confound 회피

- [ ] 새 cycle PR-AUC를 기존 cycle과 비교 시 **같은 forward label dataset** 사용 확인
- [ ] buggy era 결과와 비교 금지 (relative ranking만 인정)

### A2. 도훈 audit checkpoint

- [ ] **큰 verdict / paradigm shift 결정 전** 도훈 audit instinct 활용
- [ ] **도훈 audit hit 누적**: Session 80 기준 11~21+ hit (system-level audit instinct 정확)
- [ ] 도훈 직감 ("음 모델 PR-AUC 너무 높은데?" / "현재 피처로 과거 예측 아냐?") 즉시 sanity check 반복

### A3. Codex critic 외부 평가

- [ ] cycle 종료 전 Codex critic round (Charter v1.7 §10 정합)
- [ ] Codex stance: APPROVE / REVISE / REJECT veto 확인
- [ ] 자기 합리화 자동 detect ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적")

---

## 운영 checklist 적용

### 신규 cycle 진입 (예: Cycle 52)

1. **MUST 7건 + SHOULD 3건 + MAY 3건 = 총 13건 의무 체크** (Cycle 55B M7 추가)
2. 모든 MUST PASS 후 cycle 진입 허가
3. SHOULD 1건 이상 FAIL 시 도훈 sign-off 의무
4. MAY 항목은 sign-off 불요 (권장)

### 보고 format

각 cycle 종료 시 `outputs/06_reports/cycleNN_checklist.md` 작성:

```markdown
# Cycle NN Entry Checklist

## MUST (5/5 PASS)
- [x] M1. bear_date_audit 4/4 PASS — log: qepm/observability/sanity_checks/bear_date_audit_2026MMDD.json
- [x] M2. validate_label_direction 100% PASS — n_sample=100, agreement_rate=1.0
...

## SHOULD (3/3 PASS)
- [x] S1. PR-AUC 0.2129 ∈ [0.15, 0.40] PASS
...

## Sign-off
- 도훈 audit instinct: PASS (이상 신호 없음)
- Codex critic: APPROVE / REVISE / REJECT
```

---

## 참조

- **Cycle 51 incident 사건**: `STATUS_BUGGY_ERA.md`
- **Forward baseline**: `RESEARCH_CHARTER_v2_forward.md`
- **PIT v2**: `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()`
- **bear_date_audit**: `02_Infrastructure/sanity_checks/bear_date_audit.R`
- **shift convention rule**: `.claude/rules/data_table_shift_convention.md`
- **PIT 헌법**: `.claude/rules/pit.md`
- **AX-008**: `qepm/memory/axioms/active/AX-008.json` (Forge + Codex + Architect 2/3 PASS)

---

## Change log

- **2026-05-20 Cycle 51 Phase 4**: 작성 (도훈 mandate B안 — 신규 cycle 의무 checklist 11건 / MUST 5 + SHOULD 3 + MAY 3).
- **2026-05-21 Cycle 54D Phase 4**: M6 Phantom-0 contamination assertion 추가 (총 12건 / MUST 6 + SHOULD 3 + MAY 3). 의무 사용본: `targets_long_horizon_observable.parquet`. buggy 원본 `targets_long_horizon.parquet.cycle54d_backup` retain.
- **2026-05-21 Cycle 55B PIT Deep Audit**: M7 Data source publication lag assertion 추가 (총 13건 / MUST 7 + SHOULD 3 + MAY 3). 도훈 mandate "PIT 이슈 없다고 자신있게 말할 수 있어?" trigger. CFNAI (~22d) + ICSA (~5d) FRED leaks 발견 + Codex 2/2 confirm + ECOS pattern 권장. 패치 필요: `96_5way_retrain_v3f_us_macro.R:72-84` (us_cfnai_lag1 / us_initial_claims_4w_avg_lag1) + `A6_bbva_macro_builder.R:71-90` (bbva_market_z via Init_Claims).
- **2026-05-21 Cycle 57A Phase 1+2 fix**: CFNAI publication lag corrected from `+25L` (55B initial assumption of MM-END dating) to `+55L` (Q-Lead pre-Codex empirical verification: FRED dates at MM-START of reference month, release ~25d post month-END). Applied to direct us_* FRED features in v5e_FIXED + v5f_FIXED panels (Phase 2). 53H BUGGY 0.2480 → FIXED 0.2337 (-0.0143 PR-AUC) confirms lookahead was inflating signal. 53I BUGGY 0.2356 → FIXED 0.2382 (+0.0026). New q15 leader: 53I_v5f_FIXED. **BBVA-indirect contamination remains** (Codex Q3a/Q3b — fred_macro_wide.parquet Init_Claims feeds A6_bbva_macro_builder.R same bug). Deferred to Cycle 57A_followup.
