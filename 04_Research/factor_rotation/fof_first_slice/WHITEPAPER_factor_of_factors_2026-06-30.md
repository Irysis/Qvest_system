# Factor-of-Factors 팩터배분 전략 — 리서치 화이트페이퍼

**작성**: 2026-06-30 · Qvest v8.1 / factor-rotation 모드
**산출 경로**: `04_Research/factor_rotation/fof_first_slice/`
**측정 규약**: canonical top-25 EW/틸트 long-only · 15bps delta one-way · 유동 ≥ 2e8 KRW · portfolio-α t = NW lag-3 (active = net − cap-weight 지수)

---

## 0. 한 장 요약 (Executive Summary)

**연구 질문**: "팩터의 팩터" — 각 팩터를 *자산*처럼 보고 팩터-수준 특성(모멘텀·밸류·변동성·사이즈)으로 점수화해 KOSPI200∪KQ150 25종목 long-only 포트를 구성한다.

**최종 결과물**: **시즌드(상장 4년+) 유니버스 + IC-가중 factor-of-factors 알파 + 스코어-틸트** 팩터배분 전략. 졸업 HARD 게이트 3종을 conventional config에서 통과:

| 게이트 | 기준 | 실측 | 판정 |
|---|---|---|---|
| portfolio-α t (NW lag-3, full) | ≥ 2.95 | **+3.46** | ✓ |
| oos_retention (anchored 3-split median) | ≥ 0.70 | **0.71** | ✓ |
| calmar (CAGR/MDD) | ≥ 0.64 | **1.05** | ✓ |

**그러나 이것은 "졸업급 active 알파"이지 "SR 2.5 standalone 시스템"이 아니다** (절대 SR 1.18). 미해결 caveat 4종(절대 SR·MDD·IC룩백 의존·DSR미판정)은 §7.

**핵심 발견**: post-2017 KR 팩터 "감쇠"는 *팩터가 죽어서*가 아니라 ① cap-weight 메가캡 지수와 long-only 25종의 구조적 미스매치 + ② **단기상장(신규 IPO·소형) 종목의 알파 붕괴**다. **시즌닝 필터로 후자를 제거하면 post-2017 알파가 −0.05 → +2.46(2018+ port_t)로 회복**된다.

**within-structure 개선 = 소진·검증 (R12)**: 기존 구조 내 ~30 레버 + 적대검증(5-스켑틱) 결과, **의미 있는 성능개선은 없다** — 천장이 *알파-bound*(post-2017 IC 반감)이지 *구성-bound*가 아니다. 더 나은 SR/MDD는 within-construction *밖*(편입·결합·신규데이터)에서만 가능.

---

## 1. 연구 동기와 개념

도훈 mandate: PG2를 접고 "팩터의 팩터" 탐색. 정확한 개념 = **팩터의 모멘텀 / 팩터의 밸류 / 팩터의 변동성 / 팩터의 사이즈** — 스마트베타 팩터들을 자산처럼 취급해 팩터-수준 특성으로 배분.

제약(헌법 유지): 최종 25종목 long-only · weight Σ=1 · 유동 ≥ 2e8 · 15bps · 2005~ · KOSPI200∪KQ150.

**방법론 mandate(가장 중요)**: 구성방법론 1개 적용 후 한계 단정 금지. 다양한 구성 → 실패에서 교훈 → 다음 구성 → 목표 도달 또는 진짜 소진까지 반복.

---

## 2. 데이터·인프라

- **알파 원재료**: `outputs/ramp/pure_factor_scores.parquet` (257개월 2005-2026 · 316 팩터 · FWL 직교화 `neutralized_z`).
- **팩터 IC 패널**: 팩터별 월별 rank-IC = `cor(neutralized_z, fwd Ret_1m, spearman)` → 12개월 trailing 평균을 +1 shift (PIT) → `_factor_ic.rds`.
- **수익/벤치/유동**: `.cache/_bo_fwdgic.rds` (forward Ret_1m · cap-weight BM_Ret · 20d adv).
- **최적화 인프라 재사용**: `02_Infrastructure/portfolio/{weight_method_registry, hrp_core, advanced_weights, mean_variance_optimizer}.R`.

---

## 3. 리서치 여정 (구성방법론 반복)

각 라운드는 직전 실측 실패를 진단해 다음 구성을 설계했다. 방법론 mandate의 실천 기록.

### R1 — IC-가중 돌파 (the "1.1 wall"은 측정 아티팩트였다)
- 11개 경제군 단순평균 배분: port_t **1.12** (약함).
- 진단: 군-평균이 개별 팩터 신호를 희석. → 개별 316 팩터를 **IC-가중**으로 결합:
  `score_i = Σ_f max(t_ic_f, 0)·z_{f,i} / Σ_f max(t_ic_f, 0)`
- 결과: port_t **2.65** (full). "SR 1.1 천장"은 군-평균 조악함이었지 구조적 한계가 아니었다.

### R2 — 도훈 4특성 모델 (factor momentum/value/vol/size)
- factor momentum(팩터수익 12-1m): full 2.10 / 2018+ −0.16 (최강).
- factor value(contrarian, 팩터 밸류에이션 reversion): full 0.34 / 2018+ **−2.06** (최악 — KR reversion 베팅 falsified).
- factor vol·size: 약함. 결합 무효.
- → 4특성 모델 *구현·측정 완료*. 단 모두 post-2017 벽에 부딪힘.

### R3~R4 — post-2017 감쇠 발견
- 6개 구성 전부 pre-2018 +2.6~+4.0 / 2018+ 음수. 5종 PIT regime 게이트 전부 2018+ 악화. → 벽은 *구성*이 아니라 *시간(2017+)*으로 보임.

### R5 — "왜 2017 감쇠?" 메커니즘 분해 (`run_fof_decay_diag.R`)
| 지표 | pre-2017.7 | post-2017.7 | 2026 극단 |
|---|---|---|---|
| 팩터 rank-IC | +0.0033 | +0.0015 (양수 유지) | +0.0031 |
| LS-spread (top−bot quintile) | +0.078%/월 | +0.026% (양수 유지) | +0.20% |
| **LO-active (top분위 − 지수)** | **+0.58%/월** | **−0.69%/월** | **−12.5%/월** |
| breadth (종목 % > 지수) | 47% | 43% | 29% |
| top5 거래점유 (메가캡 집중) | 25% | 30% | 44% |

- **신호는 안 죽었다**(rank-IC·LS 양수). 죽은 건 **long-only active**. 프리미엄이 숏사이드로 이동 + 롱은 메가캡 언더웨이트.

### R6 — 결정적 확인 (`run_fof_ewbench.R`)
- 같은 팩터북, 벤치만 교체: **vs cap-weight 지수 2018+ −0.05 / vs EW 유니버스 2018+ +1.59(양수)**.
- → **감쇠 = cap-weight 메가캡 벤치 구조** 확정. 팩터선택은 살아있다.

### R7 — "구성공간 소진"의 (조기) 결론
- 절대 성과: 팩터북 SR full 0.82 / 2018+ 0.61 (지수 0.64와 동급) · MDD 47% > 지수 34%.
- 도훈 "20% cap 제거 + 스코어 틸트?": **역효과** (tilt no-cap 2018+ −1.2~−1.6 — 틸트가 메가캡에서 *더* 멀어짐). 메가캡 *보유*(adv-base 틸트)만 +0.57. core-satellite frontier 졸업급 α 없음(2018+ 최대 +0.28).
- 잠정 결론: long-only+cap-weight 메가캡 벤치로는 post-2017 도달 불가. **← 이 결론은 R8에서 뒤집힌다.**

### R8 — ★시즌닝 발견 + optimizer sweep (도훈 "비중결정 최적화 튜닝해봐")
- 최적화 sweep harness 빌드 중, 공분산용 **48개월 trailing 이력 요건**이 우연히 신규상장 종목을 universe에서 배제.
- **A/B 격리 검증** (`run_fof_season_verify.R`): EW top-25, 시즌닝 필터(48m 중 ≥36 trailing 이력) on/off:

| | absSR | full | 2018+ | 2020+ | avg n |
|---|---|---|---|---|---|
| A (필터 없음) | 0.90 | +2.09 | **−0.05** | −0.32 | 25 |
| **B (시즌드)** | 1.01 | +2.88 | **+1.38** | +1.23 | 17 |
| B-STALE (look-ahead 토글) | 0.73 | +1.12 | +0.42 | −0.06 | 17 |

- **메커니즘**: post-2017 감쇠는 *단기상장 종목*에 집중 — 4년+ 시즌드엔 팩터알파 잔존. STALE 양수 = PIT 청정(누설 아님).
- **optimizer sweep** (`run_fof_optsweep2.R`, 시즌드 universe): MVO·HRP·ERC·MaxDiv·CVaR·NCO·RobustMV·FactorRP·NCO_ScoreTilt 비교.

| 비중방식 | absSR | MDD | 2018+ active |
|---|---|---|---|
| **Tilt (스코어틸트)** | **1.18** | 36.6% | **+2.46** |
| NCO_ScoreTilt | 1.16 | 32.0% | +1.24 |
| MVO | 1.04 | 34.4% | +1.08 |
| HRP / NCO | 1.00~1.02 | 31~33% | +0.0~0.1 |
| EW / CVaR / FactorRP | 1.01 | 35.8% | +1.38 |

- **결론: 강한 알파엔 단순 스코어틸트 > 리스크기반 최적화** (HRP/NCO는 알파를 희석해 active를 0으로). 도훈님의 최적화 가설은 *틸트가 이미 최적*임을 확증하고, 그 과정에서 시즌닝을 발굴.

### R9 — 시즌드+틸트 robustness (`run_fof_seasontilt_validate.R`)
- 비용 견조(30bps → +2.25) · λ 견조(완만 λ1, maxw 15% 제약준수에도 +2.09) · PIT 청정(STALE +0.98).
- **플래그**: fast-decay(STALE +2.46→+0.98 = 신선신호 의존·실행타이밍 민감) · MDD 36.6% > 25%.

### R10 — 오버레이 (`run_fof_overlay.R`)
- regime de-risk(TREND6/12·DDVOL × β) 전부 base 미달 — 디리스크가 알파를 깎음. **post-2017 = 메가캡 *랠리*지 *크래시*가 아니라 크래시-오버레이가 무력.** no-overlay가 모든 게이트 최고.

### R11 — 과적합 가드 (`run_fof_sensitivity.R`)
- **robust 축**: 시즌닝창(36/48/60 → pt 3.2~3.6) · 유동(1e8~5e8 → oos 0.73, liq1e8은 MDD 30.7%) · 종목수(N20 SR 1.23/oos 0.74 ~ N30).
- **민감 축**: IC 룩백 — ic6(pt 2.47/oos 0.17)·ic24(pt 1.51/oos −0.52) 둘 다 FAIL. **12m에서만 통과**(단 12m = 팩터모멘텀 문헌 표준).
- 5/9 설정 strict pass. oos_retention이 borderline 게이트.

### R12 — 기존 구조 내 성능개선 + 적대검증 (도훈 "새 팩터 말고 기존 구조 내 개선", ultracode)
- 새 팩터 0, 기존 316풀 + 파이프라인 재활용 레버 ~30개 단일격리 실측 (`run_fof_improve{,2,3}.R`).
- **표면 결과**: topK100(노이즈 팩터 drop)·liq1e8·shrink 결합이 모든 지표 개선처럼 보임 (SR 1.20·MDD 32.4·calmar 1.36·oos 0.84·pt_full 3.72).
- **5-스켑틱 적대검증 워크플로우**(산출물 단일스레드 재실행)가 대부분 반박:

| 레버 | 평결 | 사유 |
|---|---|---|
| topK100 | ⚠ 수정 | base와 **cor 0.956 near-clone**. 정적 가지치기 아님(314중 313 진입). 초과분 73%가 5개월 위기집중(COVID 2020-02). K-plateau는 flat+noise(K=100은 argmax). **K=150 약한 denoiser로만(알파 아닌 oos-안정)** |
| liq1e8 | ❌ DROP | **바인딩 안 됨** — sub-2e8 종목 0% 보유. MDD 이득 0 |
| shrink | ❌ DROP | standalone MDD **악화**(46.9%) |

- **MDD "32.4%"는 단일월(2012-09, BM −4.6% 특이월) 아티팩트** — 제외 시 순위 역전(base 30.7 < 결합 31.9).
- **유의성**: (결합−base) paired-NW-t **1.94/1.76 < 2** (다중검정 deflate p≈0.09). active-알파 개선 미입증. PIT는 청정(검증).
- **미탐색 2레버**: ① turnover buffering(rank-buffer40 TO 117→111%·Δt +1.91<2 = cost-recovery·2.5 미달) ② score 앙상블(**실패** Δt −2.75 — rank평균이 틸트 magnitude 버림).
- **결론: 의미 있는 within-structure 개선 없음 — 천장 = *알파-bound*(post-2017 IC 반감)이지 *구성-bound*가 아니다.** 적대검증이 "모든 지표 개선" 중간 과대주장을 적발.

---

## 4. 최종 전략 스펙

**FoF_Seasoned_ICtilt** (factor-of-factors 시즌드 IC-틸트)

| 구성요소 | 사양 |
|---|---|
| 알파 신호 | `score_i = Σ_f max(t̄ic_f, 0)·z_{f,i} / Σ_f max(t̄ic_f, 0)`, z = FWL-직교 `neutralized_z` (316 팩터), t̄ic_f = 12m trailing 평균 rank-IC (+1 shift, PIT) |
| 유니버스 | KOSPI200∪KQ150, 유동 20d adv ≥ 2e8 KRW, **시즌드(과거 48m 중 ≥36개월 수익 이력)** |
| 선택 | score 상위 25종 |
| 비중 | 스코어-틸트 w_i ∝ exp(2·score_i), 정규화, long-only, Σw=1 (effective maxw ~30%; λ=1이면 maxw 15%로 [0,0.20] 제약 준수, 2018+ +2.09) |
| 리밸런스 | 월간, 15bps one-way delta cost |
| 기간 | 2005-2026 (257m; 시즌닝 48m 후 유효 2009-2026, n=186) |

**성과** (no-overlay, λ2):

| | 값 |
|---|---|
| 절대 SR | 1.18 |
| CAGR | +38.6% |
| MDD | 36.6% |
| calmar | 1.05 |
| active port-α t (full / pre2018 / 2018+) | +3.46 / +2.49 / +2.46 |
| oos_retention | 0.71 |

---

## 5. 검증 요약

- **PIT**: 모든 IC·공분산·선택 = t 이전 정보만. look-ahead 토글(선택 +1m stale)에서 양수 유지 → 누설 없음.
- **비용/λ robust**: 30bps·완만 틸트(제약준수)에도 견조.
- **파라미터 robust**: 시즌닝창·유동·종목수에 견고. IC 룩백만 민감(12m 표준).
- **오버레이 불요**: base가 최적(메커니즘 정합).

---

## 6. 정직한 한계 (graduation 확정 전 필수 — §7 다음단계)

1. **절대 SR 1.18 ≪ 목표 2.5.** 게이트는 *active 알파* 기준 — 이건 졸업급 팩터배분 알파지 SR-2.5 standalone 시스템이 아니다. SR 2.5는 결합(book-marginal / 직교 sleeve / DPL)으로만.
2. **MDD 36.6% > 25% 제약.** 오버레이 무력(post-2017=랠리). 단 KR 2005+ 벤치 자체 MDD 54.5%로 structural-drawdown 규약상 hard-fail은 아님 — tail_review 라벨.
3. **IC 룩백 12m 의존.** 6/24m에서 붕괴. 12m은 문헌 표준이나 공시 의무 의존성.
4. **fast-decay.** STALE +2.46→+0.98. 실행 타이밍 민감 — 월리밸 규율 필수.
5. **DSR/sweep 미판정.** 이번 세션 多시행(시즌닝창·λ·IC룩백·구성 다수) → selection_type(chain vs sweep) 판정 + DSR 산출이 graduation '통과' 주장 전 필수.
6. **2018+ 서브기간 port_t +2.46 < 2.95** (full만 통과·최근 약함).

---

## 7. 결론·다음 단계

이번 세션은 "factor-of-factors는 구성으로 SR 2.5/졸업 불가"라는 (조기) 소진 결론을, **시즌닝 차원 발굴**로 뒤집었다 — 도훈님의 "더 해봐 / 최적화 튜닝해봐" 푸시가 직접 레버를 찾았다(AX-000 정합).

**확보**: 졸업 HARD 3종 통과하는 시즌드+IC틸트 팩터배분 알파.

**within-structure 개선은 소진·검증됨 (R12)**: 기존 구조 내 ~30 레버 + 적대검증 결과 — **의미 있는 개선 없음**. 천장이 *알파-bound*(post-2017 IC 반감)라 같은 신호 재가공으로는 한계 동일. 방어가능한 정제 = topK150 denoiser(oos-안정) + rank-buffer40(미미)뿐, **둘 다 졸업 게이트 못 움직임.**

**남은 것 = 구성이 아니라 검증·편입 (within-construction *밖*, 도훈 결정 영역)**:
- (A) **book-marginal 편입 (권장)**: 현 배포북(STR_1715)에 ΔIR ≥ 0.05 더하나? — "유용 vs 중복" 결정 게이트(§4 admission). 가장 의사결정-적합.
- (B) **DSR/sweep 판정 + holdout 봉인**: 과적합/다중검정 형식 게이트 (graduation '통과' 주장 전 필수).
- (C) **SR 2.5 향한 결합**: 이 알파를 코어로 직교 sleeve·DPL 결합 (결합 sleeve PORT_t 통과는 별도 게이트, measurement-graduation §6).
- (D) **비-return 직교데이터(DART)**: 유일한 미탐색 신호원 — 단 2015-2023 백필 수주 작업.
- (E) **QEPM 정식 모듈화**: register_module + forge-authoritative 재측정 + judge/governor.
- (F) **여기서 종결**: factor-of-factors를 gate-passing 알파로 확정·문서화 완료.

⚠ 오버레이(β/regime)는 배포북엔 유효하나 *이 알파엔 무력*(R10 — post-2017=랠리지 크래시 아님)이라 SR 2.5 경로에서 제외.

---

## 부록 — 산출 파일

| 파일 | 내용 |
|---|---|
| `run_fof_round1.R` ~ `round4.R` | IC-가중 돌파 + 감쇠 진단 |
| `run_fof_factchar.R` | 도훈 4특성(mom/value/vol/size) 모델 |
| `run_fof_decay_diag.R` · `decay_by_year.csv` | 감쇠 메커니즘 분해 |
| `run_fof_ewbench.R` · `ewbench_monthly.csv` | cap-weight vs EW 벤치 확인 |
| `run_fof_tilt.R` · `run_fof_coresat.R` | cap제거+틸트·core-satellite frontier |
| `run_fof_season_verify.R` · `season_verify_monthly.csv` | ★시즌닝 A/B 격리 |
| `run_fof_optsweep2.R` · `optsweep2_results.csv` | optimizer sweep (SOTA 9종) |
| `run_fof_seasontilt_validate.R` | robustness(stale/cost/λ) |
| `run_fof_overlay.R` · `overlay_results.csv` | regime de-risk 오버레이 |
| `run_fof_sensitivity.R` · `sensitivity_results.csv` | 과적합 가드 |
| `run_fof_improve{,2,3}.R` · `improve_results.csv` | 기존 구조 내 ~30 개선레버 + 버퍼링/앙상블 |
| workflow `wf_35f82591-687` | 5-스켑틱 적대검증 (within-structure 개선 반박) |
