# Shu & Mulvey (2024) "Dynamic Factor Allocation Leveraging Regime-Switching Signals" — KR 충실 재현

**arXiv 2410.14841 · 2026-06-19 · 도훈 mandate "논문 충실 구현, 모든 제약 해지"**

## 1. 구현 (논문 그대로)

| 논문 요소 | 구현 |
|---|---|
| 유니버스 | 7 롱온리 인덱스 = Market + 6 스타일팩터 (value/size/momentum/quality/lowvol/growth) |
| 팩터 소싱 | **KR raw + FactorDB composite** (V12_Composite_Value·S01_Size·M09_Composite_Mom·Q08_Composite_Quality·D03_RealVol·GR07_Composite_Growth, `load_month_factors` PIT C13/14/15). 도훈 mandate "FactorDB 구현된 거 가져와 써도 돼" |
| 인덱스 구성 | 월리밸 cap-weighted top-tercile tilt (MSCI smart-beta 방식), 일별 VW(Size_lag), active = factor − market |
| 국면모델 | 팩터별 2-state **Sparse Jump Model** (~15피처: EWMA수익 8/21/63·RSI·%K·MACD·logDD·activeβ·시장ret·VIX-proxy / 희소 피처가중 ℓ1 bound κ²=9.5 + jump penalty λ=50 DP). 확장윈도 min8y/max12y, 월refit |
| 뷰 | regime → 동일국면 과거평균 active수익(연율, **±5% cap**) |
| 배분 | **Black-Litterman**: EW prior(1/7), P 6×7(+factor/−market), Σ=EWMA 126d half-life, δ=2.5, Ω/τ = c·diag(PΣP') (c는 목표 TE 1~4% 캘리브) → posterior μ → **long-only Σw=1 MVO** |
| 비용 | 5bps one-way (논문값) |

**이탈(정직)**: ① 국면추론은 offline smoother 마지막상태(window≤t, 미래無 → PIT valid). 논문은 online filter(실시간 shift ~2×). ② 시장환경 피처서 2Y/10Y 국채금리 제외(논문서 가중≈0). ③ 펀더멘털은 바닥부터 대신 FactorDB composite(도훈 승인).

## 2. 결과 (2014–2026, 148개월 walk-forward)

| model | IR_vsMkt | IR_vsEW | pt_capwt | absSR | absCAGR | absMDD | calmar | TO/yr |
|---|---|---|---|---|---|---|---|---|
| EW (정적 7팩터) | 0.33 | −0.13 | 1.50 | 0.62 | 0.112 | −0.415 | 0.27 | 0.23 |
| BL TE1% | 0.63 | 1.30 | 2.16 | 0.78 | 0.159 | −0.313 | 0.51 | 2.40 |
| BL TE2% | 0.80 | 1.30 | 2.75 | 0.82 | 0.169 | −0.298 | 0.57 | 3.19 |
| **BL TE3%** | 0.99 | **1.30** | **3.50** | 0.88 | 0.184 | −0.276 | **0.67** | 4.33 |
| **BL TE4%** | 1.07 | 1.26 | **3.90** | 0.92 | 0.198 | −0.271 | **0.73** | 5.24 |

논문 헤드라인(US 2007–2024): IR_vsEW 0.40~0.49 / absSR 0.52→0.65 / actMDD −10%→−6%. **KR 재현이 이를 능가** (IR_vsEW 1.30, absSR 0.62→0.92).

## 3. 적대 검증 (graduation 주장 전 의무)

- **PLACEBO** (regime view 시간 셔플, 30 seeds): real IR_vsEW 1.30 vs placebo mean −0.31 (sd 0.21), **p(placebo≥real)=0.000**. → 국면 타이밍이 실재 알파 (정적틸트 아티팩트 아님).
- **분해**: 정적 7팩터 EW틸트는 테스트구간 pt 0.46(약함), BL 순수 타이밍 pt(BL−EW) 5.71 → **엔진은 틸트가 아니라 타이밍**.
- **oos_retention** (anchored 3-split median): TE3 0.31 / TE4 0.42 → **0.7 게이트 FAIL** (게다가 <0.5 무조건 FAIL). 전 구간 워크포워드 OOS임에도 전반(2014-21) 대비 후반(2021-26) 엣지 ~1/3 축소 = **2017+ cohort-wide 팩터 decay**(헌법 §3 decay-pattern, 전략 고유 아님).

## 4. 판정

**RAMP 역대 최강 결과 — HARD 3종 중 2종(pt_capwt 2.95·calmar 0.64) 최초 동시통과 + 타이밍 placebo 검증(p<0.001).** 그러나 oos_retention이 KR decay에 막혀 **자본 tier 졸업 불가 → screen-tier(2/3)**. 자본 게이트는 governor 정지·도훈 수동(불변).

**정정**: 이전 결론 "팩터 최근성과 타이밍 = decay 추종 실패"는 과한 일반화였음. 다피처 SJM + BL 결합의 팩터-국면 타이밍은 **실재 알파를 더한다**(placebo 검증). 단 KR 2017+ decay가 그 엣지를 시간축으로 깎아 *졸업만* 차단한다(알파 부재가 아니라 알파 축소).

## 5. 산출
- 코드: `02_Infrastructure/ramp/ramp_shumulvey_indices.R`(인덱스) · `run_ramp_shumulvey.R`(SJM+BL) · `run_ramp_shumulvey_verify.R`(검증)
- 데이터: `outputs/ramp/shumulvey_index_returns.parquet` (7 인덱스 일별, 2006-2026)
- L-code: `RAMP_SHUMULVEY_20260619` (backtested)

## 6. 옵션1+2 (기간확장 + 튜닝) 및 ★sweep-부풀림 정정 (도훈 "1,2 실행" + "더 튜닝할 여지?")

**옵션1 인덱스 2003~확장(2008 GFC 테스트포함, `_ext.parquet`) + 옵션2 per-factor λ/κ CV튜닝.** online filter는 월간 last-state서 smoother와 수학적 동일(no-op). 전체 8셀 ablation{ext/orig×MINY5/8×fixed/cv, 계약 PORT_t}.

**1차 (argmax-CV) 결과 — 매력적이나 부풀려짐:** 최강 ext_m5_cv(2009-2026 208mo) PORT_t 7.65·calmar 0.92·oos 0.52, placebo p=0.000, 첫36m(GFC)제거해도 pt 7.29. → 한때 "조건부졸업 밴드(2/3)"로 보였음.

**2차 de-bias (`run_ramp_shumulvey_v3.R`: rolling re-tune + grid-ensemble) — 정정:**

| 방법 | PORT_t | oos | 성격 |
|---|---|---|---|
| argmax-CV (단일/rolling) | 7.2–7.7 | 0.39–0.54 | sweep-부풀림 |
| **고정 λ50/κ²9.5 (논문)** | **3.5–4.8** | 0.23–0.31 | 비-sweep |
| **grid-ENSEMBLE (argmax제거)** | **3.0** | 0.11–0.23 | de-bias |

- **rolling re-tune(논문 본래 적응메커니즘)으로도 oos 불변**(0.39/0.54) → oos는 decay 상한, **합법 튜닝여지 없음**.
- **argmax 제거(ensemble)시 pt 7.7→3.0 붕괴** → "조건부졸업"은 9그리드argmax+8셀선택 **sweep 다중검정 부풀림(~2.4배)**.

**★최종 정정 판정**: Shu-Mulvey는 **RAMP 최강 regime 접근**(비-sweep pt 3.5–4.8가 Cascade 2.85·full-cycle 2.37 능가, placebo 실재타이밍)이나 **oos~0.25 decay-cap = screen-tier, 졸업 아님.** 더 튜닝 = p-hacking(§1.3/AX-002). **교훈: 화려한 CV/튜닝 수치는 grid-ensemble(argmax제거)로 de-bias 검증 필수.** L-code `RAMP_SHUMULVEY_V2_20260619`·`RAMP_SHUMULVEY_V3_DEBIAS_20260619`.

## 7. ★★정정 (2026-08-20, FQ-239 P0-2) — 동월 적용 look-ahead 확정, 본 보고서 수치 전면 재기준선화

**결함**: `bt()`(:179-199)가 월말 mi 종가 데이터로 산출한 비중 `W[m]`을 **같은 달 수익 `ret[m]`**에 곱한다(동월 적용 = ~1개월 look-ahead). `_verify/_v2/_v3/_v4/_contract`의 `port()` 전 계열 동일. 같은 파일 Stage 2B L/S 진단(:127-128)은 `(ei+1):nx` 익월 적용 — 파일 내 불일치로 의도가 아닌 버그. 부수: `calib_c`(:172-176) 전기간 평균 TE 캘리브 = 2차 look-ahead.

**shift A/B 실측** (`run_ramp_shumulvey_p02_shift_ab.R`, 동일 상태·뷰·c 재사용, 공통윈도 2014-04~ 147mo, 5bps):

| TE | pt_capwt 동월(§2) | **pt_capwt 익월(보정)** | IR_vsEW 동월 | **보정** | paired NW-t |
|---|---|---|---|---|---|
| 1% | 2.12 | **0.73** | 1.15 | **0.17** | +5.71 |
| 2% | 2.71 | **0.82** | 1.20 | **0.20** | +5.75 |
| 3% | 3.46 | **0.98** | 1.24 | **0.24** | +5.47 |
| 4% | 3.86 | **1.13** | 1.21 | **0.28** | +5.07 |

**판정**: §2·§3·§6의 헤드라인(TE3 pt 3.50·IR_vsEW 1.30, v3 7.2~7.7, oos 0.31~0.54)은 전부 동월 회계 위 수치 — **무효/재기준선화**. §3 placebo p=0.000·정적틸트/타이밍 분해도 결함-공유 프레임(placebo도 동월 적용으로 측정)이라 보정 프레임 재검증 대상. §4 "HARD 2/3 최초 통과" 철회. 기존 검증 4종(placebo/분해/oos/subperiod)이 이 결함류를 판별하지 못함을 재확인 — **shift/lag A/B만 판별**(BearProb 실사고 동형, `overlay_pit_guard.R` 규약 재입증).

**계속 (config-scoped, 종결 아님)**: 보정 월간(M0)은 신호를 한 달 묵혀 쓰는 회계이고 논문 원 프로토콜은 일별 T+2 적용 — 동월(불법 신선도)↔익월(1개월 낡음) 갭이 일별 적용(합법 신선도)이 회수할 공간의 상계. next_probe = ①v5 일별 온라인 필터 + T+2 (FQ-239 P1) ②피처 완전화 f17 ③완전 인과 rolling re-tune으로 oos 재산출(DIST-RAMP-014 live_trigger b). 원장 정정: `ramp_registry.json::RAMP_SHUMULVEY_BL_20260619.correction_20260820`. L-code `RAMP_SHUMULVEY_P02_TIMING_CORRECTION_20260820`.
