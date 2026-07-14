# R32 Verdict — 밸류 추가가 실제 PG2 북(M4xR05 오버레이 적용)의 최종 배포 성과를 강화하는가 (FQ-048)

**부모 체인**: R30(FQ-045) B2 screening 관통 → FQ-046 dossier judge REJECT → **R32(FQ-048, 오버레이 적용 배포 북 위험축 실측)**.
**역할**: forge (integration + measurement, pure function). 3-package/production READ-ONLY.
**base 권위 (§7b)**: clean recon N20 λ1.5 tilt on `0_ic_S7`(production `_recompute_alpha_asof.R` score와 spearman 1.000 exact). production 역사 `ret_orig` NAV는 vintage 부풀림 잔존(Challenge 1) → 미사용.
**pin**: R32_frozen_panels_20260714 (recon/value/screen_inputs 07-14 off0 clean + prod overlay scalars m4/beta_R05). prereg sha256: 27996a9b…
**metric authority**: build_metrics/build_benchmark_compare (contract, PerformanceAnalytics, ann=12, monthly).

---

## 판정 요약 — CONFIG-SCOPED POSITIVE (전기간 위험축) + RECENCY-DECAYED (자본 NO-GO)

> **전기간(269m, clean recon basis)**: 밸류 추가는 오버레이 배포 북의 위험조정 성과를 **강화** — Calmar 0.724→**1.14**(B2)/1.12(Z6) · MDD 0.349→**0.278** · SR_geo 1.089→**1.37** · PORT_t 3.455→**4.53** · book-marginal dIR **+0.269**(B2, paired-t 3.08).
> **★그러나 강화의 지배분 = 2024+ 역전된 pre-2024 알파**: value marginal paired-t **pre-2024 +4.24 → post-2024 -1.26**(B2). post-2024 book active baseline +85bps → B2 +14bps → Z6 **-22bps**. OOS retention v2 **0.24/0.20/0.14** (3 arm 전부 ≪0.7 HARD fail, 밸류가 retention 악화).
> **자본 판정**: **NO-GO** — FQ-046 judge REJECT 재확인·심화(오버레이 적용 실측으로). 밸류는 위험축 full-period 강화하나 최근 소진 + graduation OOS 게이트 미달.

---

## 1. 3-arm 성과표 (overlay applied = primary, clean recon basis)

| arm | SR_geo | CAGR | MDD | Calmar | AnnVol | PORT_t(NW3) | IR | β |
|---|---|---|---|---|---|---|---|---|
| arm0 baseline | 1.089 | 0.253 | 0.349 | 0.724 | 0.235 | 3.455 | 0.740 | 0.767 |
| **arm1 +B2 value** | **1.369** | 0.317 | **0.278** | **1.141** | 0.234 | **4.533** | **1.009** | 0.747 |
| arm2 +Z6 value | 1.367 | 0.314 | 0.279 | 1.124 | 0.232 | 4.361 | 0.972 | 0.724 |

(pre-overlay context: arm0 SR 0.922/Calmar 0.543/PORT_t 3.455/β 0.94 → 오버레이가 β 0.94→0.77·Calmar 0.54→0.72 개선. 오버레이 3 arm 동일 적용 = 밸류 차이만 격리.)

book-marginal (overlay active, window-matched 269m): dIR B2 **+0.269** / Z6 +0.232 · paired active-diff NW-t B2 **3.079** / Z6 2.727 · active-corr vs arm0 B2 0.893 / Z6 0.888.

## 2. ★핵심 = 위험축 시간 분해 (전기간 강화의 recency 소진)

| arm | full active t | pre-2024 t | pre-2024 bps/mo | **post-2024 t** | **post-2024 bps/mo** | OOS_v2 |
|---|---|---|---|---|---|---|
| baseline | 3.46 | 3.70 | +108.7 | 0.56 | +85.3 | 0.244 |
| +B2 | 4.53 | 5.51 | +164.3 | 0.08 | +13.7 | 0.195 |
| +Z6 | 4.36 | 5.55 | +166.0 | -0.12 | -22.4 | 0.142 |

value marginal (arm-arm0): pre-2024 paired-t **+4.24**(B2)/+4.31(Z6) → post-2024 **-1.26**/-1.64. dbps pre +56 → post **-72/-108**.
→ 밸류의 book 기여는 pre-2024 강력·2024+ 완전 역전 = value 아크 lockbox OOS -1.191(value-vs-mega 스타일 역전) 정면 재현.

## 3. 위험축 귀속 (Calmar/MDD 개선 = 방어인가 알파인가)
- down-market(bench<-3%, n=53) capture: baseline 0.693 → B2 0.645 → Z6 0.640 (밸류가 down-capture 소폭 개선 = genuine defense, 오버레이와 보완).
- 단 CAGR 상승(0.253→0.317)·MDD date 분산(arm2 2007 vs arm0 2023)·COVID dd 유사 → **개선 지배분은 방어 아닌 pre-2024 알파**(2024+ 역전). 단일 에피소드 특이 아님(공간 분산)이나 시간-특이(pre-2024 집중).

## 4. §7b parity 판정 (Challenge 1) — ★도훈 결정 재료
production 역사 `ret_orig` NAV = same-month vintage 부풀림 **~2.08×**(noL4 pinned PORT_t 6.214/SR 1.898 ÷ clean recon 3.455/1.089). clean recon PORT_t(base 3.06~3.25)는 R28/R29 judge-급 clean 진실과 정확 정합. `0_ic_S7`=production score spearman 1.0. → **clean recon이 §7b-correct base**. 현직 book pinned 6.130/6.214는 clean-basis 재산출 필요(FQ-044 P2 기확인) — **본 R32가 그 재산출을 3-arm(baseline+value)으로 확장 실증**. 별도 judge 라운드·도훈 결정.

## 5. 신규 지식 (value 아크 심화)
1. **construction 의존성**: 밸류 book 기여는 construction에 크게 의존 — cap-w top-25(closet-index, 값 희석) PORT_t 2.74(FQ-046 REJECT) vs **N20 λ1.5 tilt(production 실construction) PORT_t 4.53**. FQ-046이 cap-w에서 판정한 밸류 기여는 production 실북(N20 tilt)에선 더 크다 — 단 자본 게이트(OOS 0.7)는 여전히 미달.
2. **오버레이×밸류 = 보완**: 오버레이 현금분과 밸류 종목-저β 방어분은 별개 채널(상쇄 아님, down-capture 0.69→0.64 추가 개선).
3. **recency 벽 불변**: construction/오버레이 어느 것도 2024+ value-vs-mega 역전을 구제 못함(스타일 감쇠 ≠ β 타이밍).

## 6. governance / prior 정합
- book_state·05_Production·outputs 무변경. stage_artifacts만 write. DART API 미접촉. governor 정지. 02:00 insider crawl/R9 자동발사 무접촉(잔류 R 프로세스 taskkill 회피 — 타 agent 활성작업 보호, single-thread+arrow io+file-based 세그폴트 방지로 대체, challenge_note 기록).
- n_trials: value family 누적 ~9(R26~R32, chain — iteration별 mechanism 진단 기록·IS-only 변형선택). DSR 진단 산출 대상이나 게이트는 OSS retention(3 arm 전부 미달).
- honest prior 정합: prereg "알파 상쇄로 큰 개선 기대 낮음" → **부분 반증**(전기간 위험축은 강화, construction 의존). 단 prereg "위험축 상호작용 미측정" 해소 = full-period 강화·2024+ 소진 양면 확정.
- AX-000: FQ-046 REJECT를 dead-end로 접지 않고 오버레이-적용 배포 북 위험축(미측정 면)을 소비 → construction 의존성·오버레이 보완 채널 신규 획득.

## 7. next_probe (≥2, 종결 어휘 미사용 — config-scoped positive(전기간) + recency 프론티어)
1. **P1 (book pinned clean-basis 재산출, 도훈 결정 대기 승격)**: 본 R32가 clean recon 3-arm으로 현직 book pinned 6.130/6.214의 vintage 부풀림 2×를 배포-북 레벨로 재확인 → production noL4 book의 clean-basis 공식 재산출을 judge 라운드로 승격(FQ-044 P2 + R32 통합). governor·도훈 confirm. book_state SR/Calmar/PORT_t 재기재 필요 여부 판정.
2. **P2 (value recency tripwire + 스타일 로테이션 반전 감시)**: value marginal post-2024 음전환(-1.3)·value_quality_spread 0.175(압축) → monitoring이 trailing-12m value-marginal paired-t + 스프레드 백분위 월간 추적. 반전 발화(스프레드 재확대·mega 레짐 붕괴) 시 B2/Z6 재판정(하네스 전부 보존). 늦은-사이클 규율.
3. **P3 (construction 의존성 일반화)**: N20 tilt에서 밸류 기여가 cap-w top-25보다 큼(2.74→4.53) → 타 screen-tier 재료(R9 insider 소비면·overlay 큐)를 cap-w 아닌 production N20 tilt basis로 재측정 시 screening→graduation 관통 여부. FQ 등재 후보(측정 basis가 graduation 판정을 바꾸는지 계통 검증).
