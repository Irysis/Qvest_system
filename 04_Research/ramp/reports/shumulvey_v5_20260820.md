# Shu-Mulvey KR v5 — 보정 회계 재기준선 + 일별 온라인 필터 + 피처 완전화 + 인과 re-tune (FQ-239)

**2026-08-20 · 도훈 mandate "자본졸업을 목표로 지속 강화" · prereg `outputs/ramp/smv_v5_prereg_20260820.json` (결과 산출 전 기록) · pin tag `smv_r2_20260820`**

> 상태: P0~P1b 확정, P1c(roll)·게이트 배터리 진행 중 — 완료 시 §6~§8 확정.

## 1. P0-1 동결입력 재현 — PASS
기존 parquet + `run_ramp_shumulvey.R` 재실행 → 6월 보고서 §2 표와 전 수치 소수점 둘째 자리 일치(Δ=0.00 ≤ 허용 |Δpt|0.1). 코드 결정성 확인.

## 2. P0-2 ★동월 적용 결함 확정 (shift A/B) — 6월 헤드라인 전면 재기준선화
`bt()` :179-199가 월말-결정 비중을 같은 달 수익에 적용(전 변형 공유). 동일 상태·뷰·c 재사용, 타이밍만 교체(147mo 공통윈도, 5bps):

| TE | pt 동월(구) | **pt 익월(보정)** | IR_vsEW 동월 | **보정** | paired NW-t |
|---|---|---|---|---|---|
| 1% | 2.12 | 0.73 | 1.15 | 0.17 | +5.71 |
| 2% | 2.71 | 0.82 | 1.20 | 0.20 | +5.75 |
| 3% | 3.46 | 0.98 | 1.24 | 0.24 | +5.47 |
| 4% | 3.86 | 1.13 | 1.21 | 0.28 | +5.07 |

placebo/분해/oos 전부 이 결함을 못 잡았고(placebo도 동월 프레임 공유) shift A/B만 판별 — BearProb 실사고 3번째 재입증. 원장 정정 적재: `ramp_registry.json::RAMP_SHUMULVEY_BL_20260619.correction_20260820` + 6월 보고서 §7 + L-code `RAMP_SHUMULVEY_P02_TIMING_CORRECTION_20260820`.

## 3. P0-3/P0-4 지수 재빌드 + vintage 드리프트
- 빌더 rebal 캡 파라미터화(`SMV_REBAL_END`, 기본값 구 동작 보존). 확장 빌드 `shumulvey_index_returns_202608.parquet` (rebal ~2026-07-31 완결월, 일별 ~2026-08-20). 동일창 빌드는 등가 논증으로 생략(확장 빌드의 구간 ≤2026-06-17은 governing rebal ≤05-31이라 동일창 빌드와 정확히 동일).
- 겹침 5,043일 비교(`smv_p03_overlap_20260820.csv`): Market/Size/Mom/Quality/LowVol cor ≥0.999(사실상 동일) · **Value cor 0.936(연율 +4.5pp) · Growth 0.978(−3.2pp) 드리프트**. 국소화: Growth = 2016~2024 완전 동일(ndiff 0) + 2026 극단 구간 대폭 수정(구 vintage 연율 613.9 → 171.7 — R44 ret_sanity/R47 KRX backfill의 물리 불가능 수익 제거 효과) · Value = 전 기간 매일 상이 + 2017 구조 단절(cor 0.43) = V12 팩터 스코어 역사 재산출 흔적. **신규 빌드(현행 정본 factor DB + 수리된 rawdata)가 이후 판정 기준.** 2025~26 수익이 전 기간 통계를 지배할 수 있어 시대분해 병기 의무 재확인.

## 4. P1 케이던스 A/B (f15, 신규 parquet, 2014-04~2026-07 ~149mo) — ★일별 온라인 필터는 열위
16셀 전수(`smv_v5_results_f15.csv`). 헤드라인 발췌:

| arm | TE | 5bps: IR_vsEW / pt | 15bps: IR_vsEW / pt | TO/yr | absMDD |
|---|---|---|---|---|---|
| **M0**(월간 보정) | 1% | +0.10 / 0.97 | −0.06 / 0.77 | 2.8 | −0.32 |
| **M0** | 2% | +0.10 / 1.01 | −0.06 / 0.72 | 4.2 | −0.32 |
| **M0** | 3% | +0.05 / 0.79 | −0.11 / 0.47 | 5.5 | −0.33 |
| D1(일별 T+2, λm1) | 3% | −0.24 / 0.08 | −0.46 / −0.36 | 9.8 | −0.47 |
| D1(λm2) | 3% | −0.20 / 0.14 | −0.48 / −0.39 | 11.8 | −0.47 |

**판정: D1은 prereg 채택 규칙(15bps IR 비열등) 명백 미달 — 전 16셀 IR_vsEW 음수, 턴오버 2배+, MDD 악화.** 기전: 온라인 상태 flip 노이즈(논문도 실시간 shift ~2× 경고)가 KR active 노이즈 위에서 신선도 이득을 압도. λm=2(점프 페널티↑)가 λm=1보다 일관 우위 = flip 노이즈 귀속 방증. **케이던스 레버는 config-scoped negative** (일별-일괄이 아니라, 주간/이벤트-트리거 케이던스는 미측정 — next_probe).

## 5. P1b 피처 완전화 (f17) — 금리 2종 무기여~소폭 역기여
ECOS 3Y·10Y−3Y diff ewm21 추가(17종 완성, 논문 대조 달성): M0 pt 0.97→0.90 (TE1), 0.79→0.64 (TE3) 등 전반 소폭 하락, D1 불변~소폭 악화. 논문의 US 실측(해당 피처 가중 ≈0)과 정합. **작업 피처셋 = f15 유지, f17은 충실도 대조 기록.** (f17_usvix 변형은 미소비 — f17 자체가 역기여라 우선순위 하향, 프론티어 표기)

## 6. P1c 인과 rolling re-tune — 월간 소폭 개선, 일별 구제 불가, ★계약 측정 HARD 3종 전패 확정
v3 프로토콜 이식 + 검증 L/S를 T+1 적용+5bps로 상향(v3 same-day 결함 수리). grid {20,50,100}×{6,9.5,14}, 6mo/6y 인과.
- M0-roll(5bps): TE2 IR_vsEW +0.20/pt 1.23 (fixed +0.10/1.01 대비 개선) · TE3 +0.14/1.03. D1-roll: 전 셀 IR_vsEW 음수(−0.16~−0.54) — **일별 축은 re-tune으로도 음수**.
- **계약 측정 (`run_ramp_shumulvey_v5_measure.R`: build_bt_result(월간)→audit→essence_score(v2, chain, n_trials=16)) — 헤드라인 M0-roll TE3**:

| 항목 | 5bps | 15bps | HARD |
|---|---|---|---|
| portfolio_alpha_t_nw_lag3 | **1.033** | 0.631 | ≥2.95 FAIL |
| oos_retention (v2 3분할 중앙값) | **0.163** (0.163/0.057/0.50) | 0.031 | ≥0.7 FAIL (<0.5 무조건) |
| calmar | 0.394 | 0.364 | ≥0.64 FAIL |
| net_SR / net_IR / DSR / MDD | 0.65 / 0.28 / 0.20 / 0.32 | 0.62 / 0.17 / 0.11 / 0.33 | — |

**판정: 자본 tier 3종 전패 (계약 경유 확정). DIST-RAMP-014 live_trigger (b)(인과 re-tune oos ≥0.5) 미발화 — 실측 0.163.** 6월 "HARD 2/3 통과"는 회계 결함 산물로 최종 철회. prereg 분기 = oos<0.5 → **레버 교체 재라운드 (config-scoped, 종결 아님)**.

## 7. 게이트 배터리
①assert_overlay_pit — **PASS** (D1 T+2 전수 + M0 익월 전수, 구조 검사). ②③④(shift 사다리·placebo 30-seed M0/D1) — 3차 실행 진행 중 (1·2차는 하네스 자기결함 2건을 검거하며 무효: ⓐ`run_engine` shQuote가 Windows 자식에 리터럴 따옴표 전달 → 전 하위실행 즉사에도 "done" 출력(상태 미검사) ⓑ`SMV_TE` 필터의 부동소수점 `0.03*100≠3` → TE_T 빈 벡터 붕괴. 둘 다 수리 + 자식 성공 검사 추가. **"통과처럼 보이는 침묵"을 잡은 것은 요약 부재를 눈으로 확인한 것** — verify-both-directions 계열 교훈).

## 8. 졸업 게이트 갭 표 (계약 측정 확정 — essence_score v2)

| 게이트 | 문턱 | 실측 (M0-roll TE3, 보정 회계·신규 vintage) | 갭 귀속 |
|---|---|---|---|
| PORT_t (cap-w NW3) | ≥2.95 | **1.03** (5bps) / 0.63 (15bps) — best셀 TE2 1.23 | **1차 병목** — 동월 결함 제거로 구속이 oos에서 PORT_t로 이동. 신호 자체의 크기 부족 |
| oos_retention | ≥0.7 (밴드 0.5) | **0.163** / 0.031 | 2차 병목 — 재판정 트리거(0.5) 미발화 |
| calmar | ≥0.64 | 0.394 / 0.364 | 미달 (MDD 0.32 — 완전투자 구조 한계, 논문도 동일 지적) |
| 배포 형태 | 25종 조건-안 | 미착수 | PORT_t 벽이 선결 — 단독 자본 경로는 후순위, **소비면(overlay/조건변수)이 현행 레버** |

**정직 서술**: 보정 회계·계약 채점에서 KR Shu-Mulvey 팩터-국면 타이밍은 자본 게이트 3종 전패. 5bps 월간에서 약양성(IR_vsEW +0.10~0.20)이나 15bps에선 소멸. 논문 US(IR_vsEW 0.40~0.49, 문헌값) 대비 한 급 이하. 6월 "논문 능가"는 회계 결함의 산물. **남는 실질 가치**: ①위기월 조건부 반응성(D1이 위기월에만 우위 +0.57 vs +0.18 %/mo — 상시 배분이 아니라 조건부 소비가 맞는 그릇) ②팩터별 국면 연속 신호 자산(export 완료) ③프로토콜 자산(shift A/B·인과 re-tune 표준·게이트 하네스).

## 9. P2 착수 — 소비면 전개 (도훈 2순위, 레버 교체 후속)
- **export 완료**: `export_smv_factor_regime.R` → `outputs/ramp/smv_factor_regime_daily.parquet` (30,522행 = 6팩터 × 5,087일, 2006~2026-08-20. bear_prob = 상대근접도 c_bull/(c_bear+c_bull) — 자유도 0 연속변수. 결측 40.3%는 첫 refit(2014-04) 이전 구간 — 커버 구간은 전일). 소비 규약 헤더 명문(T+2·컷오프 2거래일 전·진행월 금지).
- 다음: ⓐ book overlay A/B (method_registry exposure adapter — `breadth=mean(bear_prob)`, `exposure=1−0.30·breadth` 사전등록) ⓑ Lane D(FQ-236) 조건변수 스펙 핸드오프.

## 산출물
- 코드: `run_ramp_shumulvey_p02_shift_ab.R` · `ramp_shumulvey_features.R` · `run_ramp_shumulvey_v5_daily.R` · `run_ramp_shumulvey_v5_verify.R` · `ramp_shumulvey_indices.R`(캡 파라미터화)
- 데이터: `shumulvey_index_returns_202608.parquet` · `smv_p02_shift_ab_20260820.csv` · `smv_p03_overlap_20260820.csv` · `smv_v5_results_{f15,f17}.csv` · prereg JSON
- 원장: FQ-239 등재(owner claim) · ramp_registry 정정 · L-code 1건(+마감 시 추가)
