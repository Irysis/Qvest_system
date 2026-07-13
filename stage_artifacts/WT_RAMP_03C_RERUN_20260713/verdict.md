# RAMP_03C 재실행 판정 — FQ-020 / 태스크 #65

**판정: DEMOTED (재현 실패 — 자본 졸업 불가).** config-scoped negative.
**as_of_date**: 2026-07-13 · **source_version**: qvest_v8.3 · **security_id**: Ticker(RAWDATA K200∪KQ150)
**config_hash(md5)**: `d9ca5fbdf98234fe16531d6afc83133e` · **pin_tag**: `ramp03c_rerun_20260713_205545`
**원 L-code**: `L-RAMP-20260620_184815` (RAMP_03C_BOOKMOM_CAPW). ⚠ 태스크 cite `161507`은 RAMP_03 MOMCONS(별개) — 2.98/1.19/0.89 일치 항목은 184815(prereg §0).

---

## 1. HARD 3종 판정 (원 기록 대비)

| basis | window | n | **PORT_t** | **oos_ret v2** | **calmar** | SR | CAGR | MDD | grade | HARD |
|---|---|---|---|---|---|---|---|---|---|---|
| **원 기록**(버그기·소실164mo) | 164 | — | **2.98** | **1.19** | **0.89** | 0.99 | — | — | A(proxy라벨) | 3/3(명목) |
| 재현 RAMP-native proxy | full 255 | 255 | **2.98** | **0.38** | **0.42** | 0.81 | 0.21 | −0.51 | B | **1/3** |
| 재현 RAMP-native proxy | t164 | 164 | 2.69 | 0.36 | 0.60 | 0.85 | 0.23 | −0.38 | B | 0/3 |
| **재현 교정 IKS200**(authoritative) | full 255 | 255 | **2.65** | **0.22** | **0.42** | 0.81 | 0.21 | −0.51 | B | **0/3** |
| 재현 교정 IKS200 | t164 | 164 | 2.28 | 0.22 | 0.60 | 0.85 | 0.23 | −0.38 | B | 0/3 |
| 민감도 ALT(mom6 재-z) proxy | full 255 | 255 | 3.03 | 0.41 | 0.43 | 0.82 | — | — | B | 1/3 |

**게이트 문턱**: PORT_t≥2.95 · oos_retention v2≥0.7(band[0.5,0.7)=보강증거 2/3) · calmar≥0.64.

**결론**: 모든 window×benchmark 조합에서 HARD 3/3 재현 실패.
- 원 유일 통과였던 **PORT_t 2.98은 RAMP-native proxy·full-window에서 우연히 정확 재현**되나, **교정 IKS200(authoritative)에선 2.65로 미달**(경계값 +0.03의 취약성 실증).
- **oos_retention은 1.19 → 0.22~0.41로 붕괴**(어느 창·벤치서도 재현 안 됨). 원 "cap-w OOS레버(0.01→1.19)" 주장 = 재현 불가 아티팩트.
- **calmar은 0.89 → 0.42~0.60로 붕괴**(원 소실 164mo가 2008 GFC를 제외한 최근창이라 MDD 과소평가 → calmar 과대. full 255mo MDD −0.51 → calmar 0.42).
- oos_retention 하한 0.5 미만(band escalation 자격 없음). ⇒ **자본 졸업 불가, screen-tier/B(블렌드 문맥에서만 가치).**

## 2. 핵심 발견 — cap-weight OOS레버 기전 **반전**

동일 top-25 selection의 3가중 PORT_t(proxy, full 255mo):

| 가중 | 원 기록 | 재현 |
|---|---|---|
| EW | 2.65 | **4.25** |
| score-tilt | 2.72 | **4.26** |
| **cap-weight** | **2.98 (최고)** | **2.98 (최악)** |

- 원 기록: cap-w가 **최고**(메가캡 모멘텀=OOS레버 주장). 재현: cap-w가 **최악**(EW/score 4.25/4.26 ≫ cap-w 2.98).
- cap-weight는 시총 상위(mega-cap)에 비중을 실어 **cap-w 벤치와 유사해지는 closet-indexing** → active PORT_t 희석. [[project-captier-alpha-localization-20260706]] "mega-cap signal-dead" + cap-w 트랩과 정합.
- **바인딩 벽은 가중이 아니라 oos_retention**: 3가중 전부 oos 0.38~0.42(전부 <0.7). 즉 RAMP_03C family는 어떤 가중이든 oos 게이트 미달.

## 3. 2017+ decay 노출 (challenge #3)

cap-w active 시계열 pre/post-2017 분해:

| basis | pt(pre-2017, 144mo) | pt(post-2017, 111mo) | actSR pre | actSR post |
|---|---|---|---|---|
| proxy | 2.96 | **1.11** | 0.92 | **0.37** |
| iks200 | 2.84 | **0.76** | 0.89 | **0.25** |

- 알파는 **pre-2017에 집중**(PORT_t ~2.9), post-2017 붕괴(0.76~1.11). 이것이 oos_retention 붕괴의 직접 기전 = cohort-wide 2017+ 감쇠(decay-pattern, overfit 아님).

## 4. 164mo 창 정의 (모호점 #2 결과)

book carrier PORT_t 재측정: full 257mo proxy **6.18** / t164 **5.12** / iks200 full 5.71 / t164 4.53. **어느 것도 원 book 2.64 재현 안 됨** → 원 164mo의 정확한 월-집합은 소실된 `_bo_fwdgic.rds`에서 유래, 생존 입력으로 복원 불가(prereg §2 #2 확정). full + trailing-164 병기로 대체 — **판정은 양 창 모두 FAIL이라 창 불확실성이 결론을 바꾸지 않음.**

## 5. 판정 & 자본

- **DEMOTED — 재현 실패.** 원 2.98/1.19/0.89 = 벤치버그기 + 소실 164mo 창 아티팩트. FQ-018 감사의 보수적 prior(재베이스 하락) + 본 prereg 하락 예상치 부합.
- **자본 편입 = governor 정지(도훈 수동).** 본 재현은 편입 근거 아님(FAIL). RAMP_03C `grade:"A"` 원장 라벨은 스크리닝/버그기 라벨로 확정 — 자본 문맥 인용 금지.
- **construction 복원 충실도 = high**(PORT_t 2.98 exact match). 벤치 basis 주의: 원 RAMP는 IKS 미사용(cap-w rawdata proxy) — "IKS001→IKS200 벤치버그"는 RAMP 비직접적용, RAMP 벤치버그=RAWDATA April-gap(말단 1mo, 영향 미미). authoritative는 태스크 지정 교정 IKS200 채택(보수적, 0/3).

## 6. next_probe (W9 게이트)
1. **cap-tier 국소화 후속(FQ-006~008 정합)**: RAMP_03C의 pre-2017 PORT_t 2.9는 실재 — MID(11-30위) tier 국한 여부 실측(cap-w가 MEGA에 비중을 실어 죽인 신호가 MID에 살아있나). cap-tier LS 분해.
2. **2017+ decay가 book-marginal에 미치는 영향**: EW/score-tilt(PORT_t 4.25/4.26, oos 0.42)가 cap-w보다 우월 — 이 EW variant를 현 pinned book(6.13)과 book-marginal ΔIR로 재평가(oos 0.42<0.7이라 standalone 졸업 불가하나 blend 기여 가능성). → **§7에서 소비 완료 (태스크 #66, 2026-07-13): config-scoped negative.**

---

## 7. [태스크 #66 addendum 2026-07-13] EW/score-tilt book-marginal ΔIR 진단 — next_probe #2 소비

**판정(진단): blend 기여 없음 — config-scoped negative.** 산출 `deltair_diag/deltair_grid_results.json` · 엔진 `portfolio_governor.R::.pg_book_ir_recon`(net_active_recon_v1, Return.portfolio 월리밸 + build_benchmark_compare ann=12, book_optimize QP는 incumbent 3-package 부재로 불가 — §4 recon 어댑터가 canonical). pin 동일(`ramp03c_rerun_20260713_205545`). 재생성 충실도 pt EW 4.2527/score 4.2650 (기록 4.25/4.26 일치). **book_state 쓰기·admission 없음 — 도훈 결정 재료.**

| variant | w | new_book_ir | ΔIR(vs stored 1.416) | ΔIR(window-matched) | cor_gross | cor_active |
|---|---|---|---|---|---|---|
| EW | 0 (control) | 1.4834 | +0.0674 | 0 | 0.791 | 0.606 |
| EW | 0.05 | 1.4835 | +0.0675 | **+0.0001** | 0.791 | 0.606 |
| EW | 0.10 | 1.4812 | +0.0652 | −0.0022 | 0.791 | 0.606 |
| EW | 0.15 | 1.4763 | +0.0603 | −0.0071 | 0.791 | 0.606 |
| EW | 0.20 | 1.4685 | +0.0525 | −0.0149 | 0.791 | 0.606 |
| SCORETILT | 0 (control) | 1.4834 | +0.0674 | 0 | 0.787 | 0.615 |
| SCORETILT | 0.05 | 1.4839 | +0.0679 | **+0.0005** | 0.787 | 0.615 |
| SCORETILT | 0.10 | 1.4812 | +0.0652 | −0.0022 | 0.787 | 0.615 |
| SCORETILT | 0.15 | 1.4752 | +0.0592 | −0.0082 | 0.787 | 0.615 |
| SCORETILT | 0.20 | 1.4657 | +0.0497 | −0.0178 | 0.787 | 0.615 |

(공통창 2005-02~2026-04, 255mo. w-그리드 = 진단 전수보고·선택 없음 → DSR sweep 게이트 비적용. variant 단독 net-active IR: EW 0.923 / score 0.947.)

- **ΔIR≥0.05 도달 없음(실질)**: "vs stored" 열의 +0.05~0.07은 **w=0 control이 이미 +0.0674**임이 증명하는 창(255m vs 269m)+BM basis(calendar canonical vs anchor-window embedded) 아티팩트 — variant 기여 아님. 깨끗한 귀속 = window-matched: 최대 **+0.0005**(score w=0.05), w≥0.10은 전부 음수(희석). blend PORT_t도 w 증가에 단조 하락(6.81→6.43).
- **기전 = 구조적 중복**: RAMP_03C 신호의 절반이 book 자신의 score_eff(0.5*zc(book_score_eff)) — active(−BM) cor 0.61(≫0.30 참고문턱), gross 0.79 (basis 라벨 병기, §6 규약). 남는 절반(mom6)도 book carrier 보유 모멘텀축과 중첩.
- **정렬 사고 1건 적발·정정**: 1차 그리드는 incumbent bt(WT-D20260702_002 CLEAN) date 라벨이 eval-anchor월(+1)임을 정렬검증 3a가 적발(embedded↔canonical BM cor 0.136·S0 0.848≠1.416)해 **무효·supersede** — offset-scan k*=−1 실증(bm_cor 0.946·ret β 0.655) 후 return_ym 정정 재산출. [[reference-book-benchmark-alignment-realized-ym]] 규약 재확인. 1차 로그(deltair_diag.log 1차분)의 그리드 인용 금지.
- **거버넌스 발견(basis 주의)**: stored incumbent 1.416은 anchor-window embedded BM 산출 — 동일 book을 canonical calendar BM으로 recon하면 **1.327**(Δ−0.089, 269m). §4 게이트가 "stored baseline vs canonical-BM recon 후보"를 그대로 빼면 창/basis 혼합으로 ΔIR이 systematically ~+0.07 인플레 — **window-matched control(w=0 행) 병기 의무** 권고.

**next_probe(#66)**: ① book-성분 제거 variant — mom6-only(bz 가중 0) 또는 variant active를 book active에 직교화한 잔차의 한계기여 재측정(중복 기전 분리 — 4.25의 신규 정보량 격리). ② §4 게이트 배관 — pg1 book-context에 window-matched incumbent 재계산(basis/창 동일화) control 병기 검토(stored-vs-recon basis 혼합 인플레 방지). ③ (유지) §6 #1 cap-tier LS 분해.
