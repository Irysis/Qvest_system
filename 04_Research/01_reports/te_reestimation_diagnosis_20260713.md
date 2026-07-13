# 라이브 북 TE 과소추정 진단 (task #47)

**작성**: risk-research agent · 2026-07-13 · **READ-ONLY 진단 (book_state/배포 파라미터/weight 무수정, 무제안)**
**대상 북**: `STR_1715_on_M4_R05_noLayer4_PG2` (book_state v2.5, 100%, incumbent IR 1.416 net_active_recon_v1)
**트리거**: monitoring 202607 — 실현 TE 0.3324/yr vs 예측 0.1898/yr = **비율 1.751** (> 1.5 임계) → Risk 재추정 플래그
**데이터**: `bt_result_C_noL4_CLEAN_ann12.rds` (계약-authoritative recon, 269월 2004-02~2026-06) + panel `period_returns_layer5_faith.csv`(ret_orig/exposure) + KOSPI200 벤치(계약)
**산출**: `stage_artifacts/te_diag_202607/` (te_decompose.R · merged_series.csv · decomp_sel_vs_overlay.csv · regime_conditional_te.csv · walkforward_estimator_eval.csv · te_forecast_scenarios.csv · te_diag_summary.json · chart1/2.png)

---

## 0. 핵심 결론 (1문단)

이 경보는 **모델 버그가 아니라 "상수 예측"의 구조적 한계**다. "예측 TE 0.1898"은 배포 당시 위험모델이 산출한 ex-ante 예측이 아니라 **contract full-sample 실현 TE 상수**(book_state `incumbent_ir_basis` = 07_benchmark_compare Tracking_Error 0.18984)다. STR_1715는 forge retrofit로 배포돼 별도 ex-ante Σ 기반 TE 예측이 없다. monitoring은 이 상수를 분모로 trailing-21m 실현 TE(0.3324)와 비교했고, 실제로 **최근 active 변동성이 전기간 대비 분산으로 3.07배** 뛰었다. 원인은 (1) 2025-26 초대형주 반도체 melt-up으로 **벤치 자체 변동성이 2배**(0.225→0.414)로 폭발한 위에 (2) 방어 오버레이(β 0.70·현금 스위칭)가 얹혀, base가 melt-up BM을 못 따라가는 selection 격차와 오버레이 de-risk가 **최근 양(+)의 공분산으로 동조 증폭**된 것이다. 상수 예측은 이런 국면-가변 TE를 표현할 수 없어 재발이 예정돼 있다. **단 이는 진단 재료이며, 전략/자본은 무변경 — 실제 라이브는 trailing SR 3.25로 PASS_PLUS다.**

---

## 1. 갭 분해 (task 1) — trailing-21m active 분산 = full 대비 3.07배

TE 재현 (rds-authoritative, monitoring 정합 ✓): full **0.1898** → trail36 0.2737 → trail21 **0.3324** (ratio 1.751) → trail12 0.3350.

### 1-A. 구조축 분해 (분산 가법·정확 — chart2)
`active = selection + overlay + cost`, 여기서 selection = (fully-invested base) − BM, overlay = (exposure−1)·ret_orig. 항등식 오차 2.8e-17 (정확).

| window | TE(recon) | var_share_sel | var_share_ovl(자체) | var_share_2cov | corr(sel,ovl) |
|---|---|---|---|---|---|
| full(269) | 0.1908 | **0.960** | 0.111 | −0.072 | −0.11 |
| trail36 | 0.2787 | 0.736 | 0.061 | +0.199 | +0.47 |
| **trail21** | **0.3394** | **0.701** | 0.057 | **+0.240** | **+0.60** |
| trail12 | 0.3460 | 0.598 | 0.083 | +0.316 | +0.71 |

**핵심**: 오버레이의 *자체* 분산 기여는 작다(5.7%). 그러나 전기간 −0.11이던 **selection↔overlay 상관이 최근 +0.60로 반전** → 2cov 항이 −7%→+24%로 급등. 즉 오버레이는 base가 BM에 뒤질 때(selection 음) *동시에* de-risk(overlay 음)해 **손실을 정확히 그 순간에 증폭**한다. 오버레이 계열(자체+2cov) = trailing21 분산의 **약 30%**. 오버레이를 끄면(fully-invested) trail21 TE 0.339→0.284 (분산 −30%).

### 1-B. 시간축 국소화 (같은 분산의 다른 렌즈)
- 상위 3개월이 trailing21 분산의 **69.9%**, 단일 최악월 **2026-06(5월 홀딩) 하나가 39.2%**: BM +33.4% vs 북 +7.2% = active **−26.1%** (selection −18.7%p + overlay −8.7%p; melt-up을 base가 못 따라간 게 68%, 오버레이 de-risk가 32%).
- melt-up 월(2025+ & BM>10%, 8개월) 제거 시 TE **0.3324→0.2318** → melt-up 월이 분산의 **51.4%**.

### 1-C. 4개 지목 성분 귀속 (task 명시 4성분)
| # | 성분 | 실측 기여 | 성격 |
|---|---|---|---|
| ① | **Megacap melt-up 횡단분산 폭발** | melt-up 8월 = trail21 분산 **51%**. BM 자체 vol 0.225→**0.414**(2배). | **일시적**(국면) |
| ② | **공분산 추정 창/방법 구조적 과소** | melt-up 제거 후에도 TE 0.232 > 상수 0.190 (분산 **1.49배**). 상수 예측이 국면-가변 TE를 못 담음. | **항상**(방법) |
| ③ | **오버레이 현금스위칭 TE 기여(모델 미반영)** | trail21 분산의 **30%**(자체 5.7% + 2cov 24%). corr(sel,ovl) +0.60로 동조증폭. | **모델 미반영** |
| ④ | **벤치 구성변화(삼성·하이닉스 집중)** | BM vol 2배가 근인 — ①의 원천이자 selection 격차(70%)의 배경. **구성비 미보유로 ①과 분리 식별 불가(데이터 한계, 정직 보고)**. | 외생 |

성분은 두 축(구조·시간)의 중첩이라 단순 합산 100% 아님. **정확한 가법 분해는 구조축(1-A)**: selection 70% + 오버레이 계열 30%. 시간축(1-B)은 그중 melt-up 월이 51%를 담는다는 별개 렌즈.

### 1-D. 국면조건부 TE (regime_conditional_te.csv)
CAUTION 0.277 > CRISIS 0.199 > NORMAL 0.190 > BULL 0.169. **경고**: 2025-26 melt-up 대형월(2025-03/05 등)이 *NORMAL*로 라벨돼 있어, **과거-NORMAL sd로 만든 조건부 예측은 현 NORMAL TE를 심하게 과소**(0.121)한다 → 순진한 국면조건부는 오히려 최악(§2 참조).

---

## 2. 재추정 (task 2) — 워크포워드 예측기 평가 + 갱신 예측·CI

**추정기 선택 근거(selection_objective = stress_robust)**: holdings-level Σ=BΩB'+D 대신 **active-수익 시계열 변동성 모델** 채택. 이유 — 지배 원인(오버레이 타이밍 + selection×overlay 공분산, §1-A/C)은 *시계열 국면* 현상이라 정적 holdings Σ가 원리적으로 담지 못한다. 현 holdings + BM 구성비도 미보유. 정적 Σ를 만들어 "backtested TE"로 보고하면 지배 성분을 놓친 오도 수치가 된다(정직 라벨). method_shopping: 5 추정기(상한 5 이내).

### 2-A. 워크포워드 평가 (PIT past-only, 각 시점 과거로만 예측 → 실현 대조, n_eval 257)
| 추정기 | 실현/예측 분산비 (≈1 이상적) | 1.5x 오경보율 | 현 vintage 예측 TE |
|---|---|---|---|
| expand_const (≈현행) | 1.197 | 6.1% | 0.180 |
| roll36 | 1.215 | 9.4% | 0.222 |
| **ewma94** | 1.108 | 4.5% | 0.239 |
| **ewma97** | **1.103** | **3.3%** | 0.221 |
| regime_cond(순진) | 1.291 (최악) | 10.6% (최악) | 0.121 |

**판독**: (i) *모든* 추정기가 실현/예측 > 1 — 국면전환+두꺼운 꼬리로 어떤 과거기반 모델도 active vol을 다소 과소(10~29%)한다(구조적, 완전제거 불가). (ii) **EWMA(λ0.97)가 최선** — 분산비 1.10(상수 1.20보다 1에 근접) + 1.5x 오경보율을 상수 6.1%의 **절반(3.3%)**로. (iii) **순진한 국면조건부는 최악** — melt-up이 NORMAL로 라벨돼 조건부 예측이 되레 과소·오경보 증가.

### 2-B. 갱신 TE 예측 + 90% CI (χ² 분산 CI, 시나리오 병기)
| 시나리오 | TE 예측 | 90% CI |
|---|---|---|
| 현행(구 예측 = full-sample 상수) | 0.1898 | [0.177, 0.204] |
| **정상화(trail36 blended)** | **0.2737** | [0.230, 0.342] |
| **melt-up 지속(trail21)** | **0.3324** | [0.265, 0.451] |
| melt-up 지속-보수(trail12) | 0.3350 | [0.250, 0.519] |
| EWMA(λ0.97) 현 vintage | 0.2211 | — |
| EWMA(λ0.94) 현 vintage | 0.2389 | — |

현 상수 0.190은 **정상화 시나리오 CI 하단(0.230)에도 못 미침** → 어떤 시나리오에서도 재-baseline 필요. 국면 지속 여부에 무관한 robust 중앙값 ≈ **0.22~0.27**.

---

## 3. 판정 재료 (task 3) — 3안 전제·비용·리스크

| 안 | 전제 | 비용 | 리스크 | 실측 근거 |
|---|---|---|---|---|
| **ⓐ 예측치만 갱신(모델 불변)** | 상수 baseline을 0.190 → 현 vintage(예: trail36 0.274 또는 EWMA 0.221)로 재-baseline | 최저 (monitoring 상수 1개 교체) | 상수인 한 **다음 국면전환에서 또 lag** — 재발 지연일 뿐 해소 아님 | 상수의 1.5x 오경보율 6.1% |
| **ⓑ 추정기 교체 (상수 → EWMA λ0.97)** | monitoring TE baseline을 EWMA(λ0.97) 롤링 예측으로 | 낮음 (monitoring 산식만; book/weight 무변경) | ①스파이크에 반응 후 하강 느림 ②잔여 과소 ~10%(분산비 1.10) 여전 | 워크포워드 오경보율 **6.1%→3.3%**(절반), 분산비 1.20→1.10 |
| **ⓒ 국면조건부 예측 도입** | TE를 국면별로 예측 | 중~고 (개발) | **순진판(과거 동일국면 sd)은 최악**(분산비 1.29·오경보 10.6%) — melt-up이 NORMAL로 라벨돼 과소. BM-vol 조건부 등 재설계 필요 | regime_cond 실측 열위 |

**권고 (1줄, 실행은 도훈)**: **ⓑ 채택 — monitoring 예측 TE baseline을 full-sample 상수(0.190)에서 EWMA(λ0.97, 현 0.221)로 교체(또는 최소 ⓐ로 trail36 0.274 재-baseline).** 워크포워드가 1.5x 오경보율 절반 감소를 직접 입증하며, book/weight 무변경의 monitoring-side 변경이라 자본게이트 무관. 순진한 ⓒ는 실측 열위로 기각.

**중요 정합**: 이 경보는 실질적 false-positive가 아니다 — active TE는 실제로 3배 뛰었다(실존하는 melt-up × 방어 오버레이 상호작용). "수정"의 목적은 **알려진 구조적 특성(방어북이 초집중 BM 대비 TE 상승)에 대한 반복 오경보를 줄이면서, 진짜 새 위험은 계속 포착**하는 국면-인지 baseline이다. 전략은 정상 작동 중(trailing SR 3.25 PASS_PLUS).

---

## 4. 데이터 품질 caveat (비차단)
- **2026-06 recon 불일치**: rds ret_net 0.0724 vs panel 재구성 0.0582 (Δ0.0142, monitoring 기문서화). 분해는 recon-basis(가법정확), authoritative TE는 rds-basis 사용 — 최대 기여월이라 `live_book_series` 재생성·정합 권고.
- `.cache/regime_current.json` 부재 → gap_vector로 대체(monitoring과 동일). 표준 입력 복원 권고.
- 현 라이브 국면 NEUTRAL(≈NORMAL); recon 마지막 CAUTION → 국면전이 관측(진단; optimizer 재계산은 Q-Lead/도훈 판단, 본 진단 범위 밖).

## 5. 경계 준수
alpha/weight 무수정·무제안 (role firewall). Σ 재추정은 진단 예측치 산출에 국한(exposure bound 등 optimizer scope 미침범). book_state/recon/holdout 무수정. R: .R 파일 source·단일스레드·arrow io(2). 표준 추정기(EWMA/sd/χ²)만, 자체합성 없음. insider 백필 프로세스 미간섭(RAM 63% 여유, 이름 kill 없음).
