# Factor-of-Factors — Book-Marginal 기여 검증 + 등록 자격 판정

**작성**: 2026-07-01 · Qvest v8.1 / factor-rotation 모드 (fof 세션 계승)
**임무**: fof 졸업급 *active* alpha(port_t +3.46)가 배포북(STR_1715)에 **직교적으로 기여**하는가 — book-marginal ΔIR≥0.05 게이트 + caveat 4종 정밀 + 등록 준비.
**측정 규약**: 실측-only · metric_type 라벨 · PIT C1~C15 · paired-NW-t(SR 비율비교 금지) · R 단일스레드.
**산출 스크립트**: `run_fof_book_marginal.R` · `run_fof_bmarg_significance.R` · `run_fof_caveat_dsr.R`

---

## 0. 결론 (Executive Summary)

**fof 최종전략(FoF_Seasoned_ICtilt)은 배포북에 *직교적*(active cor −0.018)이지만, book-marginal *기여는 통계적으로 미입증*이다. → 자본 등록 부적격. screen-tier(FR/overlay 입력) 라벨.**

| 판정축 | 실측 | 게이트 | 판정 |
|---|---|---|---|
| active 상관 (fof_act ↔ book_act) | **−0.018** | 낮을수록 직교 | ✓ 직교 |
| ΔIR (PIT 점진 λ) — 표면 | **+0.476** | ≥0.05 | (표면)PASS |
| **ΔIR diversification 아티팩트 검정** | 노이즈 baseline median **0.454**, 관측 0.464 = 노이즈 **58.6 백분위** | 노이즈 95%CI 초과 | ❌ **아티팩트** |
| **paired-NW-t (결합−incumbent active)** | **+0.71** | >2 | ❌ 비유의 |
| fof⊥book 잔차 standalone IR (PIT) | **−0.020** | >0 | ❌ 직교성분 무알파 |

**핵심**: ΔIR=+0.48은 "fof가 book이 못 가진 알파를 더한 것"이 아니라 **두 양수-IR 무상관 시리즈를 평균낼 때 발생하는 √2형 산술 효과**다. 동일-IR 순수노이즈 sleeve도 동일 ΔIR(median 0.454, 95%CI [0.373, 0.554])을 생성하며, 관측 fof ΔIR(0.464)은 그 노이즈 분포 한가운데 위치한다. measurement-graduation §6("직교 ≠ 수익", "PORT_t 통과분만 book 실질 기여") + [[project-pg2-orthogonal-alpha-search]]("SR차=paired-NW-t 유의검정 필수, 비율비교=noise")의 정확한 재현.

이 세션의 일관된 교훈 확정: **earnings(pt1.75, ΔIR<0) · flow(직교지만 pt0.31 약함) · fof(pt3.46, 직교지만 paired-t 0.71 비유의)** — 세 후보 모두 *standalone 졸업/강도 ≠ book 기여*. fof는 셋 중 가장 강한 standalone(pt3.46)·가장 깨끗한 직교(cor −0.018)이지만 그래도 **book IR 1.575를 유의하게 못 밀어올린다**.

---

## 1. fof 최종전략 net 시리즈 복원 (임무 ①)

- **authoritative 산출물**: `run_fof_optsweep2.R` → `_optsweep2_series.rds`의 **`Tilt`** 메서드.
  - whitepaper §4 스펙(FoF_Seasoned_ICtilt, no-overlay λ2)과 성과 **정확 일치**: absSR **1.18** · MDD **36.6%** · pt_full **+3.46** · pt_18p **+2.46** · CAGR +38.6%.
  - ⚠ `_improve{2,3}` 시리즈는 **아님** — R12 within-structure 개선 라운드로, 5-스켑틱 적대검증에서 "base와 cor 0.956 near-clone + paired-t 1.94<2"로 반박된 산출물. whitepaper §3 R12·§7이 명시.
- **시리즈 구조**: `data.table(date=결정월말, net=[t,t+1m] 실현 net active)`. n=189, 2010-01~2026-04 (시즌닝 48m이 2005-2009 소비).
- active = net − BM (cap-weight 지수, fof `bench_dt$BM_Ret`).

## 2. ★날짜정렬 실증 (retraction 교훈 — 외부 시계열 머지 전 offset 검증 필수)

[[project-ramp-book-misalignment-retraction]] mandate("외부 시계열 머지 전 cor offset −3..+3 검증")를 준수. **strategy-vs-strategy raw 상관은 정렬 핀으로 부적합**(fof Tilt는 틸트 팩터포트, book V5는 β-managed 오버레이북 → 진짜 정렬에서도 상관 낮음). 대신 **ground-truth 월간 KR 시장(`/.cache/benchmark.parquet` yfinance ^KS11 daily→monthly 복리)에 두 시리즈의 BM을 핀**:

| 시리즈 | vs ground-truth 시장 최대상관 | offset |
|---|---|---|
| fof `BM_Ret`@label | **+0.9974** (BM=시장 그 자체) | 동일(label=실현월+1) |
| book `ret_orig`@realized_ym | **+0.7164** (팩터슬리브) | **동일 offset** |

→ **두 시리즈 동일 라벨규약**(label = 실현월+1). 따라서 fof `date`-label ↔ book `realized_ym` **offset 0 직접 매칭 = 동일 실현월**. (초기 PIT-가정 +1은 오류였음 — ground-truth 핀이 0 확정. strategy gross cor가 +2에서 0.40 뜨는 것은 우연/시장사이클 aliasing이지 정렬 아님.)

## 3. book-marginal ΔIR (임무 ②) — 표면 PASS, 실질 아티팩트

- **상관(active basis)**: gross −0.120 / **active −0.018** (직교). full-sample 회귀 β(fof~book)=−0.015 ≈ 0.
- **active IR(전기간 공통창)**: incumbent book(V5) **+0.838** · fof standalone **+1.008**.
- **PIT 확장윈도 잔차화**(36m 워밍업, 각 t에서 [first,t-1] OLS β로 t 잔차): fof⊥book IR = **−0.020** (직교성분에 standalone 알파 없음).
- **ΔIR**: λ=0.5 +0.464 / λ-opt(0.60, 진단상한) +0.484 / **PIT 점진 λ +0.476**.
- **★아티팩트 판별(결정적)**: 동일 mean/sd(=동일 standalone IR) **무상관 순수노이즈** sleeve를 fof 자리에 넣고 B=2000 재계산 → ΔIR median **0.454**, 95%CI **[0.373, 0.554]**. 관측 fof ΔIR(0.464)은 노이즈 분포의 **58.6 백분위 = CI 한가운데**. **노이즈와 구별 불가 → ΔIR은 diversification 산술, 직교알파 기여 아님.**
- **paired-NW-t**(PIT결합 active − incumbent active, lag3): mean +0.266%/월, **t=+0.71 (<2, 비유의)**.

> ΔIR≥0.05 게이트는 *형식상* 통과하나, 그 통과가 **임의의 동일-IR 직교노이즈로도 동일하게 달성**되므로 게이트 의미 없음. measurement-graduation §4의 정신(book이 *못 가진* 기여)을 paired-t와 노이즈-baseline이 반증.

## 4. caveat 4종 정밀 (임무 ③)

| caveat | 정밀 결과 | 상태 |
|---|---|---|
| ① 절대 SR 1.18 | net SR 1.178, calmar 1.05. active-알파 게이트는 통과하나 **standalone 2.5 시스템 아님**(본질적 한계) | 미해소(본질) |
| ② MDD 36.6% | >25% 제약 위반. 단 KR 2005+ BM 자체 MDD 54.5% → structural-drawdown 규약상 **hard-fail 아님(tail_review)**. 오버레이 무력(R10: post-2017=랠리지 크래시 아님) | tail_review |
| ③ IC-lookback 12m 의존 | sensitivity 실측: **12m만 통과**(BASE oos 0.71). ic6 oos **0.17**·ic24 oos **−0.52** 둘 다 FAIL. PIT청정(STALE 양수, look-ahead 아님)이나 **단일 lookback fragile** | 미해소(fragile) |
| ④ DSR / chain·sweep | **sweep 분류 확정**: optimizer 10종(argmax absSR=Tilt) + sensitivity 9격자(argmax-pass=BASE) = 열거 argmax-pick. **chain 면제 불가**(§3 요건② IS-only 위반 — 변형선택이 2018+ port_t·oos_retention OOS 반복조회 기반). DSR 산정값은 N=10~100 전부 ~1.000 **PASS이나 uninformative**: sweep trial들이 동일 알파의 미세변형(near-clone, Var(SR_trials)=0.00166 극소) → deflation baseline 약해 trivially 통과. **실질 과적합 가드 = oos_retention(0.71 borderline) + IC-fragility이지 DSR 아님** | DSR 형식통과(약함)·과적합 주가드는 borderline |

⚠ DSR caveat 부기: 이 코드베이스 DSR이 과거 PSR t-stat로 오표기된 전례([[project-ramp-fullcycle-graduation]])가 있어, DSR "PASS"를 graduation 근거로 인용 금지. 여기선 sweep 형식요건 충족 여부 기록 목적.

## 5. 등록 자격 판정 (임무 ④)

**판정: 자본 등록 부적격 → screen-tier(FR/overlay 입력 피처) 라벨.**

- book-marginal ΔIR 게이트: **형식 PASS(+0.476)이나 diversification 아티팩트로 무효**(노이즈 58.6 백분위) + **paired-NW-t +0.71 비유의** → measurement-graduation §4 admission 정신 미충족.
- `register_module` 계약 floor(contract_pass+backtested+frozen+hash/build/cost) **진행 불가**: 등록 전제인 "book 실질 기여"가 미입증. 게다가 현 산출은 canonical_screen(metric_type) 실측이지 **forge-authoritative backtested 아님** — §2 권위수치(forge build_bt_result + portfolio_alpha_t_nw_lag3) 미생성. 계약 floor의 `backtested` 요건 자체도 미충족.
- **book_state 쓰기·admit 미실행**(governor 정지 준수, 도훈 수동 confirm 영역) — 애초 게이트 미통과로 해당 없음.

**screen-tier 권장 경로**(measurement-graduation §3 screen_route): fof는 직교(cor −0.018) + 강한 cross-sectional 신호(IC-weighted, pt_full 3.46)를 보유하므로 **DPL_FEATURE**(§5 DPL 입력 피처) 또는 **FR_RCMA**(국면조건부 모듈 후보) 입력으로 보존 가치 있음. 단 standalone/book-sleeve 자본 배분은 부적격.

---

## 6. 미해결 / 후속 (도훈 결정 영역)

- (B) **DSR/sweep + holdout 봉인**: sweep 확정했으나 holdout 사전등록 예측구간(holdout_falsification.R) 미생성. 단 book-marginal 미통과로 graduation 자체가 무의미해진 상황.
- (C) **SR 2.5 향한 결합**: fof를 코어로 직교 sleeve·DPL 결합 — 단 본 검증이 시사하듯 **fof 직교성분의 standalone IR이 −0.02**라 결합 PORT_t 통과 전망 낮음(measurement-graduation §6 "PORT_t 통과분만 실질"). 추가 sleeve 사냥보다 **DPL 직접 SR 최적화 피처 투입**이 유망.
- whitepaper §7의 (A) book-marginal 편입 = **본 세션이 검증 완료 → 부적격 확정**.

---

## 부록 — 산출 파일

| 파일 | 내용 |
|---|---|
| `run_fof_book_marginal.R` · `_fof_book_marginal.txt/.rds` | 시리즈 복원 + 정렬실증 + 상관 + PIT 잔차화 + ΔIR + paired-t |
| `book_marginal_panel.csv` | 공통 realized 패널(realized_ym, fof_net/act, book_net/act) n=189 |
| `run_fof_bmarg_significance.R` · `_fof_bmarg_sig.txt/.rds` | ★ΔIR block-bootstrap CI + 노이즈 diversification baseline(아티팩트 판별) |
| `run_fof_caveat_dsr.R` · `_fof_caveat_dsr.txt/.rds` | caveat 4종 + DSR(sweep) 산정 |

**충돌 회피 준수**: smartbeta_allstock/·discovery/·WT-D20260701_001/ 미접촉.
