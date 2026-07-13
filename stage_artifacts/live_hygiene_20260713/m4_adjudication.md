# 판별 보고: ① 2026-06 recon m4 (1.0 vs 0.8064) + ② regime 표시 불일치 (task #49, 2026-07-13)

**성격**: read-only 판별 재료 — recon rds·book_state·live_book_series·m4_extended.csv **무수정**. 신규 산출물만 본 디렉토리에 기록.
**선행**: `repair_log.md` (task #48) Item 1·2의 미해결 판별 2건.
**재현**: `m4_recompute_check.R` / `regime_display_diag.R` (본 디렉토리, 단일스레드·arrow io 2).

---

## ① 판정: 2026-06 recon 적용 m4 = **1.0 — rds가 맞다** (0.8064는 오염-vintage 아티팩트)

repair_log가 우려한 방향("rds 1.0이 NA-fill 아티팩트, 진짜는 0.8064")의 **역**이 실측으로 확정됐다.

### 1. PIT 재계산 (본 판별의 1차 근거 — 실측)

`WT-D20260430_001/stage_artifacts/factor_engine.R`의 `run_engine()`을 sandbox env에서 재실행
(main() 스킵 → 파일 무기록, PG2_AS_OF=2026-07-01로 07-02 grid 동일. 입력 = 현행(07-13) 수리 완료 데이터):

| m4 row | 07-02 07:31 CSV (현행 파일) | **PIT 재계산 (07-13, 수리 데이터)** | 분기 입력 Cash_Pct_lag |
|---|---|---|---|
| 2026-05-04 | 0.8064 | **1.0000** | 0.1936 → **0.0000** |
| 2026-06-01 | 0.8064 | **1.0000** | 0.1936 → **0.0000** |
| 2026-07-01 | 0.8260 | **1.0000** | 0.1740 → **0.0000** |

recon 컨벤션(`run_layer5_rerun_extended.R` L116/L128: ym join + `shift(weight_str1715,1)`)상
realized_ym 2026-06 적용 m4 = **row 2026-05-04의 weight = 1.0**.
검산: 0.5(β_R05) × 1.0 × 0.146303900075010(ret_orig) − 0.00075 = **0.072401950037505 = rds 실측값 exact**.

### 2. 분기 메커니즘: regime Layer 3 단일-alert +8.00 (산식 분해로 유일 특정)

m4의 해당 행은 전부 Case A(기존 MRS overlay defer): `weight = 1 − Cash_Pct(전월 regime)`. 유일 입력 = `.cache/unified_regime_signal.parquet`의 월간 Regime_Score → `get_cash_allocation()` (score<45 → cash 0; score≥45 → 0.15+0.20×(s−45)/25).

07-02 vintage(alpha_scores.parquet에 보존) vs 현행(07-13) 월간 score:

| regime YM | 07-02 vintage | 현행 | Δ | 분해 (compute_regime_score, `regime_signal.R` L244-268) |
|---|---|---|---|---|
| 2026-04 | 50.45 | 42.45 | **−8.00** | layer1(MSM 포화)=40 + layer2(FRED 7)=2.45 + **layer3 8→0** |
| 2026-05 | 50.45 | 42.45 | **−8.00** | 상동 |
| 2026-06 | 48.00 | 40.00 | **−8.00** | layer1=40 + layer2(FRED 0)=0 + **layer3 8→0** |

layer3 ∈ {0, 8, 15} 양자화(단일 alert = KTRI≤35 **또는** VEA≥70일 때 정확히 +8, L261-262)이므로 정확 −8.00 3연속 = **Layer3 단일-alert 플립 외 다른 조합 불가능**. MSM(양측 포화 40)·FRED(동일) 무관 — 07-02 IKS200 벤치 수리와도 무관.

### 3. Layer 3의 데이터 의존 = rawdata → 4월 소실 사고 창과 정확 일치

- KTRI/VEA는 `ktri_v3_builder.R`이 **`.cache/RAWDATA.parquet` 전 종목 daily**로 산출 (L130-139; VEA = 0.7·z(vol20)+0.3·z(dispersion), L186-187; KTRI = breadth composite).
- **07-02 리빌드가 4월 rawdata ~72k행을 삭제**(QW 이음매 구멍), 07-11 KRX 백필로 복구 — memory `project-rawdata-april-gap-incident-20260711`.
- 0.8064를 산출한 **유일한 vintage(07-02 03:20 / 07:31 재생성)가 정확히 이 오염 창 안**에서 생성됨 (`.cache/pg2_fwd_logs/m4.log` mtime 07-02 03:20 + CSV mtime 07-02 07:31).

### 4. 오염 창 양측의 독립 clean-vintage 증인 2건 (둘 다 m4 = 1.0)

| 증인 | 시점 (rawdata 상태) | 기록 | 성격 |
|---|---|---|---|
| `production_weights/20260501_PG2_generation_manifest.json` | 06-17 (구멍 前, QW 원본) | "M4 outer: weight_str1715=**1.0** … May 디리스크 없음" | 당시 스케줄 실행(行) 값 |
| `production_weights/20260601_R05_AR_manifest.json` | 06-24 (구멍 前) | m4_scalar = **1** @ 2026-06-01 | `forward_weights_R05_AR.R` L47이 **실제 최신행 ≤AS_OF를 read**한 값 (default 아님 — default는 스케줄 전무 시에만) |
| PIT 재계산 (§1) | 07-13 (KRX 백필 복구 後) | row 2026-05/06/07 전부 **1.0** | 본 판별 실측 |

pre-hole·post-repair 두 clean vintage가 일치(1.0)하고, 오염 창 내 vintage만 0.8064 — 샌드위치 완결.

### 5. repair_log (a)/(b) 판별 해소

- **(b)-역방향으로 확정**: 구 매핑의 2026-05-04 행은 **정당하게 1.0**이었고(증인 2건), **07-02 재생성이 오염 입력(hole-distorted KTRI/VEA)으로 0.8064로 flip**시킨 것. rds의 1.0은 (faith 패널이 구 vintage의 실제 행을 읽었든, ym-06 부재 NA-fill이었든) **정답과 일치** — sub-메커니즘은 결론에 비영향.
- rds의 2026-05 행(ret 0.205937 = 1.0×0.7784×0.265528−0.00074)이 m4 0.7784(row 2026-04-01)를 정확 반영 = 구 vintage 매핑 join이 정상 작동했다는 방증 (전면 NA-fill 아님).

### 6. recon 영향량 + 정정 필요 여부 (도훈 결정 재료)

- **Δ = 0. recon 정정 별도 WT 불필요.** 계약 rds 2026-06 행(0.072402)이 정답이고, 07-13 위생 수리(live_book_series = rds passthrough)가 이미 정답을 복원한 상태. SR_geo 1.8977 / CAGR 0.4526 / MDD 0.2329 불변 (`m4_recon_delta.json`).
- 반대로 **0.8064 채택 금지**: 채택 시 2026-06 ret_net 0.058240 (−1.416%p) — 오염-vintage 수치의 소급 주입이 됨. live_book_series의 진단 컬럼 `ret_recompute_panel`(0.058240)도 동일 오염 산물 — 승격 금지.

### 7. 파급 (수리 실행은 범위 밖 — 재료만)

1. **현행 `stage_artifacts/WT-D20260430_001_m4_extended.csv`(07-02 07:31)는 오염 3행 잔존** (2026-05-04/06-01 = 0.8064, 2026-07-01 = 0.826; 정답 전부 1.0). 다음 월간 run(`run_nolayer4_monthly.sh`, 8월 초)이 신선 재계산으로 자가치유 예정이나, 그 전까지 이 파일을 읽는 소비자는 오염 상속.
2. **7월 배포 비중이 오염 m4를 이미 소비**: `20260701_R05_AR_weights_cap_0p20.csv`(07-03 09:00) invested 0.0991 = **0.826**×β_AR 0.4×β_R05 0.3. 정답 m4 1.0 기준 invested 0.12 — **7월 노출 약 2.09%p 과소투자** 상태. 실주문 도훈 수동이므로 7월 비중 재생성 여부는 도훈 결정.
3. 부수 관찰 (비긴급): 오늘 재계산 vs 07-02 CSV에서 역사 3행(2008-02, 2011-12, 2012-01)도 1.0↔0.845/0.848 flip — score≈45 경계월의 입력-vintage 민감성([[project-cache-vintage-pinning]] 계열). recon은 rds 앵커(§2b 패치)라 비영향이나, m4 스케줄 소비처가 늘면 pin 대상 후보.

---

## ② regime 표시 불일치: 엔진 CRISIS vs gap_vector NEUTRAL

### ⓐ 소스 추적 — **하드코딩 fallback 확정 (경로 버그, 엔진 소비 아님)**

`portfolio_governor.R` `.pg_get_regime()` (L177-194):
- L179: `rs_path <- file.path(.pg_root, "regime_signal.R")` — `.pg_root` = `02_Infrastructure/portfolio/` (L30-39). **그 디렉토리에 regime_signal.R이 존재한 적 없음** (실물은 `02_Infrastructure/regime/regime_signal.R`).
- → `file.exists` FALSE → `get_regime_at_date` 미정의 → **L192 fallback `data.table(Category="NEUTRAL", Regime_Score=0)` 무경고 반환**. 구조상 이 경로로는 엔진값을 한 번도 읽을 수 없음 — gap_vector의 NEUTRAL/0은 상시 fallback이다 (date 필드는 `Sys.Date()-1` 문자열일 뿐).
- 자가모순 방증: 같은 `.cache/portfolio_gap_vector.json` 안에서 `book_context.live_exposure.regime = "CRISIS"`(배포 manifest 유래)와 이미 충돌.
- 동종 스테일 경로 1건 더: `telegram_commands.R` L106 (`02_Infrastructure/regime_signal.R`).
- 수리 시 함께 정렬할 것: `.PG_REGIME_ADJ`(L56-61)에 CRISIS 키 부재 — 엔진 vocab(RISK_ON/NEUTRAL/CAUTION/RISK_OFF/CRISIS) 대비 lookup 누락.

### ⓑ MSM≈1.0 연속 발화 — **정상 발화 판정 (데이터/산출 이상 아님)**

`regime_display_diag.R` 실측 (`regime_msm_recent.csv`):
- 연속성: trailing **60거래일 연속** MSM_Crisis_Prob ≥ 0.9 (최종 2026-07-10; repair_log의 "8일"은 07-02 이후 단면). 역사 baseline: ≥0.9 에피소드 149회, median 3d, p90 35d, **max 160d** — 60d는 상위권이나 전례 범위 내.
- 입력 sanity (MSM 입력 = `.cache/benchmark.parquet` 일간, `msm_daily_refit.R`): 최근 60거래일 NA 0 · dup 0 · date-gap ≤4일 · 스케일 연속. 일간 log-ret min −11.1% / max +8.6%, |ret|>3% 23일·>5% 17일, **20d 실현 vol(ann) 77.5% vs 최근 1y median 34.9%·p90 78.9%** — 진짜 극단 변동성 국면(멜트업 whipsaw, memory `reference-kr-2025-megacap-semi-regime` 정합).
- 해석: 2-state 분산-스위칭 HMM은 방향 무관 고변동 상태를 crisis state로 분류 → 이 vol에서 posterior ≈1.0 포화는 산식대로. Category는 display-only(MSM≥0.9 단락 escalation, `regime_signal.R` L280-286)이고 production 결정축 Score 43.79 / Cash_Pct 0은 별개로 정상.

### ⓒ 정합 수리안 (1줄, 실행 안 함)

`.pg_get_regime()`의 rs_path를 `file.path(dirname(.pg_root), "regime", "regime_signal.R")`로 교정(또는 07-13 상시 배선된 `.cache/regime_current.json` 소비로 교체)하고, fallback 시 조용한 NEUTRAL 대신 warn + `regime_state$source="fallback"` 라벨을 남긴다.

---

## 산출물

| 파일 | 내용 |
|---|---|
| `m4_adjudication.md` | 본 보고 |
| `m4_recompute_check.R` | ① PIT 재계산 스크립트 (sandbox, 무기록 재현) |
| `m4_recompute_vs_csv.csv` / `m4_recompute_recent.csv` | 재계산 vs 현행 CSV 전행/근접행 대조 |
| `m4_inputs_snapshot.csv` | 월간 regime 2025-08~2026-07 슬라이스 (현행 vintage) |
| `m4_recon_delta.json` | 정답 m4·recon Δ·시리즈 영향 수치 |
| `regime_display_diag.R` / `regime_msm_recent.csv` | ② MSM·벤치 입력 sanity 실측 |

metric_type: diagnostic (판별 재료 — 자본/recon 무변경). 텔레그램 불요 (지시).
