# Track F — O3_MIDBAND_FLOOR forge-authoritative 확정 측정 + 교체 권고문

- **일자**: 2026-06-12 (Composition Search Cycle 2, 도훈 confirm 2026-06-12)
- **대상**: Cycle 1 Track O 선택후보 `O3_MIDBAND_FLOOR` (prereg 동결 공식: `g = g_inc if g_inc < 0.25 else max(g_inc, 0.5)` + INV-O1 deep-guard) vs incumbent combine (`g_inc = beta_AR_lag x m4_weight_lag` 곱)
- **metric_type**: `backtested` (build_bt_result 10-component + audit_bt_result 경유, critical FAIL 0/16 x 8빌드)
- **권위 경로**: upstream 원천(base PR + M4 weights + AR beta_t_mapping) 재구축 full 재실행 — 재구축 vs production 저장 경로 최대 오차 5.6e-17 (ret_orig/beta/m4 0.0e+00, ret_L5_V2 재구성 5.1e-16) → production 엔진 완전 재현 확인. R05 레그는 INV-O2대로 AS STORED.
- **데이터 경계**: 2026-04-30 절단 (패널 native 종료 2026-04 — 절단으로 제거된 행 없음. BM 캐시도 2026-04-30 절단)
- **비용**: uniform v2.4-delta (15bps x |Δg| + stored R05 레그, prereg 규약 — incumbent 동일 재과금)
- **selection_type**: sweep, n_trials_cumulative=5 (Cycle 1 Track O 5후보 계상)

## (a) Incumbent vs O3 정식 비교표 (forge-authoritative, backtested)

contract Sharpe = Charter §12 mean(ER)/sd(ER)·√12. `SR_ta` = table.AnnualizedReturns(기하 연환산, Cycle 1 동일 방법).

| window | arm | SR(contract) | SR_ta | CAGR(contract) | MDD | Calmar | PORT_t(NW3) | IR | 연 overlay 비용 |
|---|---|---|---|---|---|---|---|---|---|
| FULL 267m | INC | 1.7081 | 1.8849 | 0.4030 | -0.2481 | 1.6247 | 5.255 | 0.8376 | 0.00182 |
| FULL 267m | **O3** | **1.7372** | **1.9271** | **0.4176** | -0.2481 | **1.6834** | **5.679** | **0.8748** | **0.00174** |
| IS 2005-2018 | INC | 1.7159 | 1.8961 | 0.4116 | -0.2481 | 1.6594 | 4.925 | 1.0734 | 0.00117 |
| IS 2005-2018 | **O3** | 1.7321 | 1.9209 | 0.4231 | -0.2481 | 1.7057 | 5.247 | 1.1057 | 0.00110 |
| OOS 2019-2026 | INC | 1.8046 | 2.0142 | 0.4216 | -0.1437 | 2.9333 | 2.106 | 0.5122 | 0.00323 |
| OOS 2019-2026 | **O3** | 1.8626 | 2.0971 | 0.4443 | -0.1437 | 3.0914 | 2.393 | 0.5605 | 0.00310 |
| SUB 2017-2026 | INC | 1.7429 | 1.9220 | 0.3768 | -0.1437 | 2.6215 | 2.770 | 0.5913 | 0.00270 |
| SUB 2017-2026 | **O3** | 1.7888 | 1.9862 | 0.3940 | -0.1437 | 2.7415 | 3.064 | 0.6319 | 0.00260 |

O3 − incumbent 델타: FULL dSR +0.0291(contract)/+0.0422(ta), dCAGR +1.46pp, dMDD 0.00pp, dPORT_t +0.424, 비용 −0.8bp/yr · IS +0.0162/+0.0248 · OOS +0.0580/+0.0829 · SUB2017 +0.0459/+0.0642. **전 윈도우에서 O3가 비열등+개선, MDD 전 윈도우 동일**(INV-O1 deep-guard 6개월 베타 차이 0 — 위기방어 보존 실측).

incumbent STORED-convention(production 비용규약) 참고행 FULL: SR_ta 1.8861 / CAGR 0.4037 / MDD -0.2481 / 비용 0.00162 — repriced와 차이 미미(재과금 영향 SR 0.0012).

## (b) Estimated(Cycle 1) 대비 괴리

like-for-like 방법(table.AnnualizedReturns + maxDrawdown, 동일 비용규약)으로 4윈도우 x 2암 전부 **dSR=0.0000, dCAGR=0.0000, dMDD=0.0000, dCost=0.00000** — Cycle 1 realized-path 재합성이 forge full 재실행과 기계 정밀도로 일치. 재합성 신뢰도 검증 완료(v24_book_remeasure 선례 재확인). estimated→backtested 전환에서 수치 괴리 0; 새로 추가된 정보는 contract 지표(PORT_t/IR/TE/Calmar/oos_retention/DSR)와 audit 게이트.

## (c) Graduation HARD 게이트 — 상대 판정 (FULL, essence_score sweep n=5)

| 게이트 | INC | O3 | 비고 |
|---|---|---|---|
| PORT_t ≥ 2.95 | PASS (5.255) | PASS (5.679) | O3 우위 |
| oos_retention ≥ 0.7 | **FAIL (0.559)** | **FAIL (0.558)** | 양쪽 동일 band [0.5,0.7) band_fail — 아래 주석 |
| calmar ≥ 0.64 | PASS (1.625) | PASS (1.683) | O3 우위 |
| DSR ≥ 0.5 (sweep) | PASS (0.997) | PASS (0.998) | 동등 |
| essence grade | B | B | 동일 |

**해석 (주 판정 = 상대 비교)**: 이것은 신규 알파가 아니라 **현 book의 overlay 변형**입니다. oos_retention band_fail은 STR_1715+overlay book 자체의 속성으로 양 암에 사실상 동일하게(0.559 vs 0.558) 걸리며, O3 채택으로 악화되지 않습니다. O3는 4개 게이트 전부에서 incumbent 대비 비열등이고 PORT_t/calmar에서 개선 → **교체 후보 성립**. (band escalation 보강증거는 본 측정 범위에서 ① trailing PORT_t>0 1건만 확보(SUB2017 INC 2.77/O3 3.06) — 2/3 미충족이라 band_fail 유지. 단 incumbent는 이미 admit/live 상태이므로 이 게이트가 교체 판단을 차단하지 않음.)

## (d) Caveat 잔존 사항

1. **설계 오염 (이월, 최중요)**: O3 밴드 상수(0.25/0.5)는 B2 진단(full-sample 267m) 유래 — 상수 자체가 전 기간을 보고 설계됨. IS(2005-2018, 선택 전용)/OOS(2019+, 확인 전용) 분리 보고로 완화하되 제거 불가. OOS 개선폭(+0.058 contract SR)이 IS(+0.016)보다 크다는 점은 우호적이나, 이 역시 사후 관찰임. 라이브 트래킹으로만 최종 해소 가능.
2. **R05 레그 AS STORED**: INV-O2 규약 + upstream admit-lineage parquet(stage_artifacts/WT_D20260425_010) 현 머신 부재로 R05 신호 독립 재계산 불가. beta_R05_V2/db_R05_V2/regime은 production 저장값 소비.
3. **BM 캐시 드리프트**: 현 BM(naver patch 후) full-window CAGR 0.0966/Vol 0.2105 vs production 당시 참조 0.0972/0.2138 (MDD 0.4852 동일) — PORT_t/IR 절대값에 미세 영향 가능, 양 암 동일 BM이므로 상대 비교 무영향.
4. **holdings 미모델링**: overlay는 cash-control 스칼라(종목 보유 불변 by design) — bt_result holdings 공란, turnover audit WARN 3건(critical 아님). 종목레벨 검증은 base STR_1715 production 선례에 위임.
5. **Sharpe 규약 병기**: contract Sharpe(산술 mean/sd)와 table.AnnualizedReturns(기하)가 0.17~0.19 차이 — 본 보고서 양쪽 병기, 게이트는 contract 값 기준.
6. **oos_retention band_fail**: 위 (c) — book 공통 속성, 교체 판단 비차단. 단 이 book의 신규 자본 graduation 주장에는 여전히 구속.

## (e) 교체 권고

**권고: O3_MIDBAND_FLOOR로 combine 교체 (조건부 — governor + 도훈 수동 confirm 대상)**

- 근거: forge-authoritative 전 윈도우 비열등+개선 (SR/CAGR/PORT_t/calmar/비용 개선, MDD·위기방어 완전 보존, OOS confirm rule 기 통과), estimated→backtested 괴리 0.
- 본 측정은 **book_state/admission을 일절 건드리지 않았음** (`book_state_written: false`). 교체 실행은 ① governor 수동 + 도훈 confirm ② production 코드(`run_layer5_R05_overlay.R` 후속판) combine 치환 ③ live holdout 등록(06_Registry/live_track STR_1715_AR_on_M4_R05 [0.39, 3.16]) 처분 결정(전략 변경 시 mark_consumed/재봉인 — holdout_falsification 규약) 3건이 선행되어야 합니다.
- 권고 조건: 교체 후 첫 분기 월간 monitoring에서 mid-band 월(0.25 ≤ g_inc < 0.5)의 실현 기여를 별도 라벨로 추적 (설계 오염 caveat 1의 라이브 검증 경로).

## 산출물

- `bt_result_incumbent_FULL.rds` / `bt_result_O3_FULL.rds` (10-component, audit 포함)
- `trackF_comparison.json` (전체 수치 + 게이트 + 괴리표 + caveat)
- `trackF_forge_comparison.csv` (8행 윈도우 비교표)
- `inputs/period_returns_layer5_prod_copy.csv` (production READ-ONLY 사본)
- 재실행: `cd 04_Research/composition_search/cycle2_trackF && Rscript -e 'source("run_trackF_forge.R", encoding="UTF-8")'`
