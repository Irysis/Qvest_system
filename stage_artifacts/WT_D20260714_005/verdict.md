# R29 (FQ-044) Verdict — Z6 PIT-clean 재측정 + 저장 268m 패널 vintage seam 확정

**판정 요약 (2건):**

**판정 1 (Q1 — seam 확정, judge-grade CONFIRMED):** 저장 `alpha_scores_str1715_268m.parquet` 268m 패널 = **전 기간 균일 same-month(off+1) factor vintage** = ~1개월 look-ahead. production forward 경로(`_recompute_alpha_asof.R`, off=0, T-1)는 **PIT-clean**. value 성분(V14/V07)은 이미 T-1 clean(seam 무관). R28 발견을 독립 재현으로 확정.

**판정 2 (Q2 — Z6 clean 재판정, 핵심): CONFIG_SCOPED_NEGATIVE (cap-w PIT-clean 기준).** R27 Z6 paired 3.807은 **상당분이 look-ahead-base 아티팩트**. PIT-clean base에서 paired NW-t = **1.02~1.72 < 2.0** (전 clean cell 미달). AND-게이트(paired≥2.0 ∧ ΔIR≥0.05) 불충족 → **자본 기여 미검증**. book_state 무변경. **단 value 신호 자체는 진짜·clean**(dIR+, variant PORT_t 상승, EW-uni 강함) — "value dead" 아님, cap-w top-25 국소화 벽. **dossier 재발사 = NO-GO (clean 기준).**

---

## 1. Q1 — 저장 268m 패널 vintage seam 확정 (judge-grade)

### 1.1 어느 구간이 어느 vintage인가
저장 268m 패널은 **부분-clean/부분-dirty seam이 아니라 전 기간 균일 same-month(off+1) vintage**다. 근거: R28 parity(median cross-sectional cor vs recon)가 전 기간 안정적으로 off+1(0.913) >> off0(0.612). 시대 경계(era boundary)가 존재하지 않음. seam은 패널 *내부*가 아니라 **{historical 저장 패널 = same-month} 와 {forward recompute = T-1} 사이의 live-경계 1개월 vintage 불연속**이다.

### 1.2 증거 체인 (R28 승계 + R29 독립 재현)
| 축 | 값 | 출처 |
|---|---|---|
| parity: recon off+1(same-month) vs 저장 score_eff | median cor **0.913** | R28 |
| parity: recon off0(T-1) vs 저장 | 0.612 (다른 vintage, 정상) | R28 |
| 저장 패널 직접 screen PORT_t | **5.241** (R29 독립 재현 = R28 5.241 정확 일치) | R29 verify(A) |
| controlled inflation: off0(T-1)→off+1(same-month) cap-w PORT_t | **2.08×** (stored-theta 3.058→6.376; ic-theta 3.247→6.922) | R29 grid |
| factor_db 내부 Date | M-end (예 2015-06-30); `load_month_factors` same-month 매핑 | R28 |

**기전**: 저장 패널은 core Consensus(C01/C02/C04/C06)·momentum(M08) 팩터를 factor_db_{M+1}(=M+1 수익과 동월)로 계산 → top-25 cap-w tail의 momentum 순환성으로 PORT_t ~2.08× 부풀림. production `_recompute`는 factor_db_{M}(T-1)를 써서 clean.

### 1.3 value 성분 vintage — clean 확정 (Q2 sub-question)
`pure_factor_scores.parquet`(R27 value source)의 V14/V07 z는 **완전히 T-1 clean**:
- median cor(vz_pfs, factor_db **off0[T-1]**) = **1.0000** (n=257)
- median cor(vz_pfs, factor_db off+1[same-month]) = 0.985
- value 자체 vintage self-seam(off0 vs off1) = 0.985 (value = EBIT/EV·EV/EBITDA 저속 fundamental → 1개월 shift에 거의 불변)

→ **R27의 value 병합은 seam을 도입하지 않았다.** look-ahead는 전적으로 base 패널(core+momentum)에 있었다. R27의 ym-정렬 정정(R26 exact-Date 92월 누락 → ym 255/255)은 별개 사안으로 유효.

## 2. Q2 — Z6 PIT-clean 재판정 (핵심)

### 2.1 파이프라인 검증 (challenge #1 — recon parity 의존 리스크)
R27 exact 재현(STORED 패널 base + pure_factor_scores value, non-recon):
- paired_full **3.738** (R27 3.807) · IS 3.107 (3.171) · HO 4.357 (4.300) · dIR 0.458 (0.481) · var_pt 7.398 (7.60).

→ **R27 노이즈 내 정확 재현.** 파이프라인 유효. clean 재구축은 이 검증된 파이프라인에서 base vintage만 교체.

### 2.2 controlled vintage swap (동일 value=vz_pfs, 동일 recon 파이프라인, base 월만 교체)
| base | vintage | base PORT_t | Z6 var_pt | **paired** | IS | HO | dIR |
|---|---|---|---|---|---|---|---|
| 1_stored_S7 | off+1 (LA) | 6.38 | 8.50 | **2.226** | 1.785 | 2.222 | 0.345 |
| **0_stored_S7** | **off0 (CLEAN)** | **3.06** | **3.75** | **1.023** | 0.668 | 1.075 | 0.127 |
| 1_ic_S7 | off+1 (LA prod) | 6.92 | 9.19 | **2.593** | 2.627 | 0.606 | 0.433 |
| **0_ic_S7** | **off0 (CLEAN prod)** | **3.25** | **4.16** | **1.328** | 1.324 | 0.360 | 0.197 |

**vintage swap 단독 효과**: LA→clean base로 paired 2.23→1.02(stored), 2.59→1.33(ic) = 게이트 하향 관통.

### 2.3 primary clean cell (factor_db T-1 clean value, 완전 vintage-일치)
| cell | var_pt | base_pt | **paired** | IS | HO | dIR | lag1 | post2017 | EW-uni pt | EW-uni oos |
|---|---|---|---|---|---|---|---|---|---|---|
| **PRIMARY (0_stored_S7 + clean val)** | 3.85 | 3.06 | **1.243** | 0.918 | 1.075 | +0.153 | 1.530 | 1.03 | 6.39 | 0.52 |
| prod-ic (0_ic_S7 + clean val) | 4.35 | 3.25 | **1.721** | 1.611 | 0.628 | +0.244 | 0.881 | 0.86 | 7.23 | 0.54 |
| clean base + pfs val (R27 exact value) | 3.75 | 3.06 | **1.023** | 0.668 | 1.075 | +0.127 | 1.230 | 1.05 | 6.42 | 0.52 |

**판정: paired 1.02~1.72 < 2.0 전 clean cell 미달 → AND-게이트 FAIL.** dIR은 통과(+0.13~+0.24)하나 paired 단독 허위통과 방지 AND-게이트에서 탈락.

### 2.4 기전 정합성 (challenge #2 — clean에서 죽는데 R27 placebo/lag는 어떻게 통과했나)
**완전 정합.** R27의 placebo(p=0.000)와 lag1(2.982)은 **VALUE 신호 무결성**만 시험 — value shuffle이 paired를 음수로 붕괴시킴(=value 실재), value 1개월 shift에도 생존(=value PIT-safe). **그 두 결론은 R29에서 유지**(vz_pfs=T-1 clean cor 1.0). R27이 시험하지 **않은** 것 = **BASE 패널 vintage**. R28이 base=same-month 검거, R29가 clean base에서 value 한계기여를 재측정. 즉 **value는 진짜·clean인데, 그 한계 paired 기여가 LA base 위에서 ~2배 부풀려 측정됐다**(dIR 0.153 clean vs 0.345 LA — look-ahead base가 value 오버레이 한계이득을 대략 2배 증폭). 모순 없음.

### 2.5 어느 성분이 seam 의존인가 (fail branch 기전 분해)
- **base 패널**: seam의 전부. off+1→off0로 base PORT_t 6.38→3.06 (2.08×), paired 2.23→1.02.
- **value 성분**: seam 무관(cor 1.0 clean). value 기여 자체는 clean에서도 양(+): variant PORT_t 3.06→3.85, dIR +0.153, EW-uni pt 6.39.
- 결론: R27 3.807 = (base look-ahead 증폭) × (진짜 clean value 신호). clean base에서 value 신호는 살아있으나 cap-w top-25 paired NW-t가 2.0 문턱 미달.

## 3. Q3 — true admission 수치 (재산출 재료, 판정 없음)
| 항목 | cap-w PORT_t (screening) | 비고 |
|---|---|---|
| clean base (0_stored_S7, stored theta) | **3.058** | R28 3.058 재현 |
| clean base (0_ic_S7, production ic theta) | **3.247** | production forward 경로 |
| Z6 clean variant (0_stored_S7 + clean val) | **3.85** | value 오버레이 후 |
| Z6 clean variant (0_ic_S7 + clean val) | **4.35** | production 경로 오버레이 |
| (참고) 저장 LA base | 5.24 | R28/R29 = same-month 부풀림 |
| (참고) 현직 book pinned | 6.130 | **재해석 범위 밖 — 별도 judge 라운드** (오버레이 포함·LA-basis) |

**주의**: 위 전부 `metric_type=canonical_screen`(weighted_screen_bt cap-w) — admission 권위 아님(forge build_bt_result authoritative). 현직 book 6.130 vs clean base 3.06~3.25 병기만; live NAV corroborate + FQ-044 후속 재베이스에서 판정.

## 4. dual-basis (M2) — cap-tier 국소화 프론티어
clean primary: cap-w PORT_t 3.85 vs **EW-uni PORT_t 6.39** (oos_approx 0.52). value 오버레이의 신호는 EW-유니버스에서 훨씬 강함 → **cap-w top-25(mega-편중)가 value 한계기여를 희석**하는 cap-tier 국소화 패턴([[project-captier-alpha-localization-20260706]]). cap-w FAIL이나 EW-대비 생존 → screen_route 재분류 후보(overlay/EW).

## 5. governance / prior 정합
- book_state·05_Production 무변경. n_trials=1(Z6 단일 구성 재측정, argmax 없음) → DSR sweep 게이트 부적용.
- honest prior 정합: KR value 24/24 standalone 감쇠 + 06-24 직교327 t>2=0 — 본건 clean paired 미달이 정합 방향. **단 AX-000: R27 negative-reversal은 측정 정정이었고, R29는 그 정정의 base-측 잔여 look-ahead를 재검거** — value 신호 자체는 dead 아님(clean dIR+·EW-uni 강함).
- pin: R28_current_20260714 승계 (RAWDATA md5 c5242397..., benchmark md5 d0b5549...).

## 6. next_probe (>=2, 종결 어휘 미사용 — config-scoped negative + 프론티어)
1. **P1 (cap-tier 국소화 소비)**: clean base + value의 EW-uni pt 6.39 vs cap-w 3.85 gap → value 오버레이를 **cap-tier-conditional**(MID/OTHER 슬리브) 또는 **EW-tilt**로 재소비. cap-w top-25 희석을 우회하는 소비형태 프론티어(FQ 신설 후보). IS-only.
2. **P2 (base seam 후속 — FQ-044 본류)**: 저장 268m 패널 전량 **clean(T-1) convention 재빌드** → book 전반 재베이스 + 현직 pinned 6.130의 clean-basis 재산출(별도 judge 라운드). QEPM 파이프라인 factor_db 매핑을 off0로 통일(재발방지).
3. **P3 (value weight/정의 정밀화, 조건부)**: clean base에서 w sweep(0.20~0.40) + regime-conditional theta는 P1(cap-tier)에서 신호 보이면의 후속 — clean cap-w에서 w=0.30 paired 1.24로 미달이므로 단독 w-tuning EV는 낮음(IS-only, DSR 회계).
