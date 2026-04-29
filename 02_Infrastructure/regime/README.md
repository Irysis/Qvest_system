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
| **fred_robust** | `fred_robust.R` | 22 series fetch + retry + wide-format 저장. 개별 fail graceful. |
| **ktri_v3_builder** | `ktri_v3_builder.R` | Market breadth + volatility → KTRI/VEA full schema signal |
| **msm_daily_refit** | `msm_daily_refit.R` | benchmark daily → 2-state HMM fit → msm_daily_latest 갱신 |
| **regime_signal** | `regime_signal.R` | 3-layer merge (MSM + FRED + KTRI) + gap handling + Category 산출 |
| **regime_briefing** | (telegram_notify.R `tg_regime_briefing`) | Telegram 발송. partial mode (Layer 부분 실패 시 degrade). |

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
# 매일 아침 pipeline (※ 실제 crontab 등록은 사용자 승인 필요 — 문서만)
30 7  * * 1-5     mrs_daily_briefing.sh    # 평일 MRS 브리핑 발송 (Claude agent 기반)
```

> Note (2026-04-29): `regime_data_refresh.sh` + `regime_healthcheck` 등 실운영용 모니터링/문제감지 인프라는 Qvest(리서치 시스템) 정의에 부합하지 않아 제거. regime cache는 daily_refresh.sh에서 갱신.

---

## Test Strategy (`08_Tests/regime/`)

### Test files (5 units)
- `test_ktri_v3_builder.R`: synthetic benchmark + RAWDATA → `build_ktri_v3()` 실행, KTRI/VEA 범위 + schema + VEA NA ≤10% 검증
- `test_fred_robust.R`: mock long+wide parquet, `fred_robust_wide_load()` 1차 / fallback / backup path 패턴 검증 (실 API fetch 없음)
- `test_msm_daily_refit.R`: 합성 2-regime daily returns → `.hmm_em()` 수렴, μ/σ 유한, γ ∈ [0,1], stress state 식별
- `test_regime_signal_merge.R`: 3-layer 합성 fixture → `build_regime_signal_table_daily()` 전체 / L3 missing / L1-only 케이스별 `Active_Layers` + partial 동작
- `test_briefing_partial.R`: `tg_format_table()` `<pre>` 블록 + 정렬, `tg_html_escape()` `<>&` 치환, `tg_send()` `emoji_min` warn 경로 (실 Telegram 발송 없음)

### 실행 방법
```bash
# 전체 단위 테스트 (run_all.R 순차 실행 + summary)
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
Rscript 08_Tests/regime/run_all.R

# 개별 테스트
Rscript 08_Tests/regime/test_ktri_v3_builder.R
Rscript 08_Tests/regime/test_fred_robust.R
Rscript 08_Tests/regime/test_msm_daily_refit.R
Rscript 08_Tests/regime/test_regime_signal_merge.R
Rscript 08_Tests/regime/test_briefing_partial.R
```

5 파일 모두 합성 데이터 기반 — 실 cache / 실 API / 실 Telegram 무의존.

---

## Troubleshooting

| 증상 | 원인 | 조치 |
|------|------|------|
| `fred_robust_health` 에서 월간 series STALE 다수 | 자연스러운 release lag (UNRATE/CPI 등) | monthly threshold 45d 유지. staleness 45d 이하면 OK. |
| KTRI VEA NA 최근 며칠 | rolling 252 window 미충족 (benchmark.parquet BM_Close NA) | Step 2 fallback (min 20d window + LOCF) 이미 적용. BM_Close 원본 확인. |
| Briefing 발송 실패 / HTML parse error | `tg_send()` `emoji_min` warn 또는 `<>&` escape 누락 | `tg_html_escape()` 로 escape 후 `tg_send_rich()`. 이모지 최소 1개 포함. |
| MSM refit 오래 걸림 | `refit_freq_days = 30` 기본 → 많은 HMM fit | `refit_freq_days = 60` 으로 늘리면 빠름 (정확도 trade-off). |

---

## Public API 요약

| Module | Function | 용도 |
|--------|----------|------|
| fred_robust | `fred_robust_fetch_all()` | 22 FRED series fetch + long/wide 저장 |
| fred_robust | `fred_robust_wide_load()` | wide parquet 로드 (fallback: long → dcast) |
| fred_robust | `fred_robust_health()` | cache staleness + schema 진단 |
| msm_daily_refit | `refit_msm_daily()` | benchmark → 2-state HMM daily Crisis_Prob |
| ktri_v3_builder | `build_ktri_v3()` | breadth + volatility → KTRI/VEA 신호 |
| ktri_v3_builder | `build_ktri_v3_safe()` | error-safe wrapper |
| regime_signal | `build_regime_signal_table(daily = TRUE)` | 3-layer daily merge + Active_Layers + Regime_Score |
| regime_signal | `build_regime_signal_table(daily = FALSE)` | monthly cascade (기존 호환) |
| regime_signal | `load_daily_regime_signal()` | daily cache 로드 (없으면 rebuild) |

---

## Build 단계

1. **[현재 Step 1]** 설계 문서 (본 파일) ✅
2. **[Step 2]** ktri_v3_builder full schema + VEA NA fix
3. **[Step 3]** msm_daily_refit
4. **[Step 4]** fred_robust ✅ (2026-04-24 — `fred_robust.R` 22 series retry/graceful + long+wide 병행 저장. `load_fred_signal()` wide 우선 호환 갱신)
5. **[Step 5]** regime_signal v2 strong ✅ (2026-04-24 — `build_regime_signal_table(daily = TRUE)` + `load_daily_regime_signal()` 추가. 일간 3-layer merge + MSM/FRED/KTRI LOCF + Regime_Score_smooth(EWMA hl=5) + Active_Layers + Is_Month_End + last_updated. `.cache/unified_regime_signal_daily.parquet` 10,159행 (1990-01-05 ~ 2026-04-24). Backward compat: `daily = FALSE` default 유지)
6. **[Step 6]** Briefing graceful fallback
7. ~~**[Step 7]** Healthcheck + alert~~ — **REMOVED 2026-04-29** (실운영 모니터링 인프라는 Qvest 리서치 시스템 정의 외)
8. ~~**[Step 8]** Test + orchestration~~ — **regime_data_refresh.sh REMOVED 2026-04-29** (실운영 cron). 단위 테스트 5건은 유지 (`08_Tests/regime/`).

---

## Backward Compatibility

기존 소비자 (briefing 함수 등)가 계속 동작하도록:
- `ktri_v3_signals.csv` 컬럼은 순서 유지 + 신규 추가
- `unified_regime_signal.parquet` 기존 스키마 유지 + 추가 컬럼 옵션
- `.cache/msm_daily_latest.parquet` 기존 schema 유지

## 변경 log

- 2026-04-24 v1.0: 초안 설계 (사용자 "지속 사용 가능 인프라" 지시 반영)
- 2026-04-24 v1.1 (Step 8): 단위 테스트 5건 + `run_all.R` + `regime_data_refresh.sh` orchestrator. README Orchestration/Test/Troubleshooting/Public API 섹션 추가.
