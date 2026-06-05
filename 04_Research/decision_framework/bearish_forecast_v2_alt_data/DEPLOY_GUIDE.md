# Deploy Guide — 약세예측 모델 + Hybrid Triple-Layer System

> 26-cycle 자가발전 무한리서치 deploy-ready 산출물
> 작성: 2026-05-20 / 도훈님 결정 대기

## 1. Triple-Layer 구조

```
Layer 1 (always active): STR_1715_AR_on_M4_R05_overlay_PG2 admit baseline
                         → 매월 1일 정기 운용 (책)
                         
Layer 2 (monthly trigger): KOSPI_DD_Hybrid_V1aV3_2M_5PCT
                          → 전월 KOSPI200 ret ≤ -5% 시 trig_run≤2 활성
                          → STR_1715 → 70% KOSPI long (dynamic by DD)
                          → admit pre-Codex 후보
                          
Layer 3 (daily monitor): 약세예측 v1.3 5-way M2 Regime
                        → daily p_bear → top 30/10/5% threshold
                        → NORMAL / WARNING / ALERT / CRITICAL
                        → Telegram alert (early warning)
```

## 2. Deploy-Ready Scripts

| Script | Mode | Trigger |
|---|---|---|
| `scripts/live_monitor_v1av3.R` | Monthly | 매월 1일 (V1aV3 Hybrid state check) |
| `scripts/daily_bearish_monitor.R` | Daily | 매일 장마감 후 (모델 alert) |
| `02_Infrastructure/ops/triple_monitor.sh` | Wrapper | cron 통합 (daily / monthly / both) |

## 3. Crontab Registration (수동)

```bash
# Edit crontab
crontab -e

# Add lines:
# Daily 약세예측 monitor (07:15, Mon-Fri)
15 7 * * 1-5  cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot" && 02_Infrastructure/ops/triple_monitor.sh daily

# Monthly V1aV3 Hybrid monitor (월초 1일 09:00, Mon-Fri만)
0 9 1 * 1-5  cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot" && 02_Infrastructure/ops/triple_monitor.sh monthly
```

## 4. Manual Test (verify before cron)

```bash
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

# Daily monitor 테스트 (with Telegram alert)
02_Infrastructure/ops/triple_monitor.sh daily

# Monthly monitor 테스트
02_Infrastructure/ops/triple_monitor.sh monthly

# Both
02_Infrastructure/ops/triple_monitor.sh both
```

Logs: `qepm/observability/triple_monitor_YYYYMMDD.log`
States: `04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/05_live/`

## 5. Stale Detection

Model predictions (`predictions_dynamic_y_tail_q15.parquet`) refresh 주기:
- **Current**: 20 days stale (2026-04-30 latest)
- **Required**: Monthly model re-train (또는 daily feature refresh + predict)
- **Stale threshold**: 7 days → 자동 알람

Daily monitor R script가 stale 시 WARNING 출력.

## 6. Model Refresh Pipeline (필요 시)

```bash
# Monthly model re-train (after 매 월말):
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data"

# 1. Refresh alt data
Rscript scripts/A3_us_sector_flow_builder.R
Rscript scripts/A6_bbva_macro_builder.R
Rscript scripts/A5_options_higher_moments.R

# 2. Rebuild feature panel
Rscript scripts/01_feature_assembler_alt.R
Rscript scripts/11_feature_engineering_enhanced.R

# 3. Re-train + predict (4-6 hours GPU recommended)
Rscript scripts/04_model_runner.R
Rscript scripts/12_multi_algorithm_ensemble.R
# (LSTM/TFT Python)
# (Dynamic ensemble)
Rscript scripts/19_dynamic_ensemble_5way.R
```

## 7. Strategy Performance Snapshot (267m, all validated)

| Metric | STR_1715 baseline | Hybrid V1aV3 | Forward P50 |
|---|---|---|---|
| SR | 1.83 | **2.696** | 2.58 |
| MDD | -23.3% | **-15.56%** | -10.4% |
| CAGR | 38.2% | **51.16%** | 47% |
| Harvey-t | +2.68 | **+4.779** STRICT_HARVEY | — |
| P(개선 > 0) | — | — | **99.3%** |

## 8. Risk-Averse Alternative (Cycle 24 발견)

Hybrid V1aV3에서 **active 시 KOSPI 대신 Gold (132030 KODEX)** 사용:
- SR 2.55 (KOSPI 2.62 대비 -0.07만)
- MDD -8.82% (KOSPI -15.56% 대비 +6.7pp 개선)
- SR/MDD efficiency 28.88 (KOSPI 16.83 대비 1.7x)

도훈 risk preference 시 변경 후보.

## 9. 도훈 Final Decision Matrix

| Option | Action | Outcome |
|---|---|---|
| **(A)** | Codex Round + AX-008 + WT 생성 | V1aV3 formal admit (governor approval) |
| **(B)** | Crontab 등록 + paper trading 1-3개월 | Triple-layer live + 실증 |
| **(C)** | 결과 정리 + 종료 | research finding 보존 |

## 10. References

- L-332: 14-cycle 자가발전 initial discovery
- L-333: cycles 16-18 PRIMARY refinement (2m/-5%%)
- L-334: cycles 20-26 deep maturity validation
- Spec: `outputs/06_reports/kospi_dd_hybrid_v1av3_2m5pct_PRIMARY_spec.json`
- Scripts: `scripts/25_~50_` 약 25개 reproducible
- Evaluations: `outputs/04_evaluation/` 약 15개 JSON
- Charts: `outputs/06_reports/charts/09_~32_` 약 24개 PNG
