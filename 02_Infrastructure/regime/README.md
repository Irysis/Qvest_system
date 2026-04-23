# Regime Infra — 지속 사용 가능 아키텍처

**v1.0 — 2026-04-24 신규 설계 / Session 70**

## 설계 원칙

1. **Resilience**: 파일 이동, 데이터 누락, 일부 layer 실패에도 브리핑 발송 지속
2. **Idempotent**: 재실행 안전, 상태 기반 (stale 감지 → self-heal)
3. **Graceful Degrade**: Layer 1/2/3 독립. 하나 실패해도 나머지로 briefing
4. **Testable**: 각 모듈 단위 테스트 가능 (`08_Tests/regime/`)
5. **Observable**: staleness / schema 위반 감지 → Telegram alert

---

## Module Responsibility

| 모듈 | 파일 | 책임 |
|------|------|------|
| **regime_data_refresh** | `regime_data_refresh.R` | FRED + KTRI + MSM 일간 일괄 refresh orchestrator. cron이 호출. |
| **fred_robust** | `fred_robust.R` | 22 series fetch + retry + wide-format 저장. 개별 fail graceful. |
| **ktri_v3_builder** | `ktri_v3_builder.R` | Market breadth + volatility → KTRI/VEA full schema signal |
| **msm_daily_refit** | `msm_daily_refit.R` | benchmark daily → 2-state HMM fit → msm_daily_latest 갱신 |
| **regime_signal** | `regime_signal.R` | 3-layer merge (MSM + FRED + KTRI) + gap handling + Category 산출 |
| **regime_briefing** | (telegram_notify.R `tg_regime_briefing`) | Telegram 발송. partial mode (Layer 부분 실패 시 degrade). |
| **regime_healthcheck** | `regime_healthcheck.R` | 매 refresh 후 staleness/schema 체크 + Telegram alert |

---

## Data Flow

```
┌─ Raw Sources ─────────────────────────────────┐
│ RAWDATA.parquet (KOSPI 일간 전종목)           │
│ benchmark.parquet (KOSPI index)               │
│ FRED API (22 macro series)                    │
│ KRX API (ktri_indices — 최근만)               │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─ Layer 1~3 Builders ─────────────────────────┐
│ ktri_v3_builder → ktri_v3_signals.csv         │
│   (DATE, KTRI, VEA, IKS200,                   │
│    Delta_KTRI, Action_v3, K_num, V_num,       │
│    above_MA200, adv_dec_ratio, vol20, disp)   │
│                                               │
│ msm_daily_refit → msm_daily_latest.parquet    │
│   (Date, Price, Vol_Est, Crisis_Prob)         │
│                                               │
│ fred_robust → fred_macro.parquet              │
│   (wide-format: Date × {VIXCLS, BAMLH0A0...}) │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─ regime_signal merge ────────────────────────┐
│ unified_regime_signal.parquet                 │
│   (Date, YM, MSM_Crisis_Prob, FRED_MRS,       │
│    KTRI_Score, VEA_Score, Regime_Score,       │
│    Category, ...)                             │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─ Briefing ───────────────────────────────────┐
│ tg_regime_briefing()                          │
│ - Layer X 실패 감지 시 partial mode           │
│ - "L1 MSM / L2 FRED / L3 KTRI" 개별 상태 표시 │
│ - fallback: disabled layer 명시 + 발송 지속   │
└───────────────────────────────────────────────┘
                │
                ▼
┌─ Healthcheck (매 refresh 후) ────────────────┐
│ - 각 cache staleness check                   │
│ - Schema validation                          │
│ - Alert: Telegram + log                      │
└──────────────────────────────────────────────┘
```

---

## KTRI v3 Full Schema (ktri_v3_signals.csv)

tg_regime_briefing이 요구하는 컬럼 전수 포함:

| Column | Type | Description | 기대 source |
|--------|------|-------------|-------------|
| DATE | Date | 거래일 | 필수 |
| KTRI | numeric [0,100] | Market breadth + trend composite | breadth/trend 계산 |
| VEA | numeric [0,100] | Volatility / exposure / activity | vol20 z + disp z |
| IKS200 | numeric | KOSPI index close | benchmark.parquet |
| Delta_KTRI | numeric | 5-day KTRI change | shift(KTRI, 5) |
| Action_v3 | string | Zone label (Strong Add / Neutral / Defensive Bias / Strong Hedge 등) | 9-grid bin |
| above_MA200_pct | numeric [0,1] | 200일 MA 초과 종목 % | breadth |
| adv_dec_ratio | numeric [0,1] | 상승/(상승+하락) | breadth |
| vol20 | numeric | KOSPI 20-day rolling sd | volatility |
| disp_z | numeric | Cross-sectional dispersion z | dispersion |

### VEA NA 최근 13일 issue (Step 2에서 해결)
- 원인 후보: rolling 252 window 내 vol20/disp 누락, frollapply NA 전파
- 해결: fallback — 최소 20-day window 충족 시 z 계산, 충족 못 하면 neutral (50)

---

## MSM Schema

### Monthly (기존)
`02_Infrastructure/msm_signals.parquet` — month_end, Avg_Prob (Crisis_Prob)

### Daily (신규 msm_daily_refit)
`.cache/msm_daily_latest.parquet` — Date, Price, Vol_Est, Crisis_Prob

### regime_signal 소비
- MSM_Crisis_Prob: daily priority → monthly fallback
- 월말 집계 시 last day of month 사용

---

## FRED Schema

### Wide format (목표)
`.cache/fred_macro.parquet` columns:
```
date, VIXCLS, BAMLH0A0HYM2, DGS10, DGS2, DCOILWTICO, DEXKOUS, ...
```

### 현 long format (broken)
66 rows / date × series × value — long. briefing 함수는 wide 기대. **변환 필요**.

---

## 차트 Set (Step 6에서 확장)

### 현재 3개 차트 (월간 중심)
1. `regime_score_24m.png` — Regime Score + Cash 24M **월간**
2. `regime_3layer_24m.png` — MSM / FRED MRS / KTRI 3-layer **월간**
3. `ktri_9quad.png` — KTRI 9-Quadrant **일간 252d**

### 추가 예정 (Step 6)
4. `regime_score_daily_6m.png` — **일간 Regime Score** 6개월 (MSM_daily + FRED_daily + KTRI_daily 일간 merge 기반)
5. `mrs_daily_standalone.png` — **FRED MRS 전용 일간 차트** (22 series composite + subscore)
6. `ktri_breadth_daily.png` — KTRI breadth metrics 일간 (above_MA200 / adv_dec ratio)

### 일간 Regime Score 조건
Step 3 (MSM daily refit) + Step 4 (FRED robust wide) + Step 5 (regime_signal v2 일간 mode) 완료 후 가능.

---

## Briefing Partial Mode

```r
tg_regime_briefing(
  allow_partial = TRUE,  # 신규 옵션
  layers_required = c()  # 빈 list = 최소 1 layer만 있으면 발송
)
```

각 layer 상태:
| Layer | 상태 코드 | 조치 |
|-------|----------|------|
| L1 MSM | OK / STALE / MISSING | STALE: 최근값 사용 / MISSING: skip |
| L2 FRED | OK / STALE / BROKEN | BROKEN: neutral 50 대입 |
| L3 KTRI | OK / PARTIAL / MISSING | PARTIAL: last known value / MISSING: skip chart 3 |

Briefing 텍스트에 "ℹ️ Active layers: L1/L3 (L2 FRED stale 6d)" 명시.

---

## Orchestration (cron)

```
30 6  * * *      regime_data_refresh.sh   # 데이터 일괄 갱신 (FRED + KTRI + MSM)
30 7  * * 1-5    mrs_daily_briefing.sh     # MRS 브리핑 발송 (Claude agent 기반)
35 7  * * *      regime_healthcheck.sh     # 상태 체크 + alert
```

---

## Test Strategy (`08_Tests/regime/`)

- `test_ktri_v3_builder.R`: synthetic breadth → KTRI/VEA 계산 검증
- `test_fred_robust.R`: mock fetch + schema 검증
- `test_msm_daily_refit.R`: HMM convergence 테스트
- `test_regime_signal_merge.R`: 3-layer gap handling 테스트
- `test_briefing_partial.R`: Layer 일부 missing 시 발송 검증

---

## Build 단계

1. **[현재 Step 1]** 설계 문서 (본 파일) ✅
2. **[Step 2]** ktri_v3_builder full schema + VEA NA fix
3. **[Step 3]** msm_daily_refit
4. **[Step 4]** fred_robust ✅ (2026-04-24 — `fred_robust.R` 22 series retry/graceful + long+wide 병행 저장. `load_fred_signal()` wide 우선 호환 갱신)
5. **[Step 5]** regime_signal v2 strong
6. **[Step 6]** Briefing graceful fallback
7. **[Step 7]** Healthcheck + alert
8. **[Step 8]** Test + orchestration 문서화

---

## Backward Compatibility

기존 소비자 (briefing 함수 등)가 계속 동작하도록:
- `ktri_v3_signals.csv` 컬럼은 순서 유지 + 신규 추가
- `unified_regime_signal.parquet` 기존 스키마 유지 + 추가 컬럼 옵션
- `.cache/msm_daily_latest.parquet` 기존 schema 유지

## 변경 log

- 2026-04-24 v1.0: 초안 설계 (사용자 "지속 사용 가능 인프라" 지시 반영)
