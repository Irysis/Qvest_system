# RAMP R1 Gate Review — 잔차-직교 sleeve 스태킹 (§6 프론티어 측정)

- **일자**: 2026-07-05
- **모드**: RAMP (Axiom 엔진 v2 카드-수렴 리서치)
- **L-code**: L-RAMP-20260705_184828 (grade B, canonical_screen, sweep)
- **판정**: **REWORK / screen-tier** (Promote 아님 — 자본 졸업 HARD 게이트 미달, frontier 열림)
- **자본 영향**: 없음 (governor 정지, book_state 무변경. 현 PG2 = STR_1715_on_M4_R05_noLayer4_PG2 불변)

## 1. Observe (Axiom 엔진 v2 카드 주입)
주입 distilled 카드 3건(status=distilled)이 프론티어를 수렴:
- **DIST-RAMP-006** (CLEAN): "envelope 안 천장-초과 유일 레버 = overlay-on-tuned-base. **잔차-직교 sleeve 스태킹·DPL은 미검증**"
- **DIST-RAMP-005** (REVISED): "직교조합+회전제어 도구 재적용 / calmar 0.37 개선 = regime overlay MDD 번역"
- **DIST-RAMP-003** (CLEAN): data-driven soft 국면가중 타이밍 알파 실재하나 oos<0.7·calmar<0.64 미달

`ramp_observe` failure-ledger 회피선: naive-regime-tilt FAIL · Shu-Mulvey-25종 전이 FAIL · dispersion-conditional 동적 sleeve배분 FAIL → **select-then-stack**은 이 셋과 전부 차별 (INV-7 충족).

## 2. 구성 (INV-7 차별)
06-18 graduation은 11군 *블렌드 composite*만 측정(cap-w 2.37). R1 = **개별 sleeve → PORT_t 선택 → 스택 → soft-regime overlay**.
프레임: canonical top-25 EW long-only · 15bps one-way · cap-w active vs KOSPI200 · 2005-2026 256m · 24m OOS 꼬리. 실측-only(`canonical_screen_bt`).

## 3. 측정 결과 (실측, cap-w authoritative)
| 구성 | port_t_capwt | oos_retention | calmar | post2017 SR |
|---|---|---|---|---|
| 개별 best (Consensus) | +2.07 | −0.19 | 0.38 | −0.15 |
| 개별 2nd (Value) | +1.43 | −0.48 | 0.28 | −0.23 |
| stack_EW | **+2.54** | −0.31 | 0.39 | −0.26 |
| stack_InvVol | +2.46 | −0.31 | 0.39 | −0.30 |
| stack_EW_softRegimeOverlay | +1.77 | — | 0.30 | −0.53 |

- **개별 11 sleeve 전부 cap-w PORT_t < 2.95**. oos_retention·post2017 SR **11/11 음수** (cohort-wide 2017+ decay). calmar 최대 0.39.
- **survivors (cap-w PORT_t≥2.95) = 0** → §6 절차게이트: book-margin 부여 안 됨 → book-marginal ΔIR 산출 대상 부재 (N/A).

## 4. 적대검증 (4렌즈, task wqj2nlawr — AX-008 verification)
| 렌즈 | verdict | 핵심 |
|---|---|---|
| look-ahead/PIT | CONFIRMS | overlay pt 하락(2.54→1.77)이 shift(t-1) 작동 증명; 음성은 look-ahead로 부풀 수 없음 |
| 벤치 정렬 | CONFIRMS | cap-w = K200∪KQ150 fresh 재계산(rawdata.BM_Ret 미사용) 256:256 0-NA; flip에 ~43% boost 필요 |
| oos·통계 | CONFIRMS | NW·oos_retention v2 산식 정확(cap-w act_bm); post2017 decay 11/11 실재 |
| firewall·해석 | **OVERTURNS (framing)** | 측정 불변, 단 verdict 프레이밍이 INV-7 위반 → 재작성 강제 |

**측정 확정 3/4 CONFIRM (AX-008 2/3 충족). framing만 firewall이 교정.**

## 5. 재작성된 verdict (INV-7 준수, firewall 반영)
- **이는 "직교 ≠ 수익" 구조적·최종 판결이 아니다.** sleeve는 β≈0.92·active-corr 0.53로 **불완전-직교**(47% BM 노출). 실패는 **이 측정프레임의 크기·안정성 부족**(config-scoped).
- **두 실패모드 구분**: ① active-return 크기 부족(stack 2.54 < 2.95, −11%) ② **oos_retention −0.31**(게이트 0.7에서 −144%, **더 심각** = 2017+ cohort-wide regime instability).
- **절차게이트 결과**(§6): survivors=0 → book 자본 기여 후보 부재. 이는 과학적 판결이 아니라 운영 규칙.
- **frontier 열림** (미탐색 envelope-안 인접 경로): (a) soft-membership ML 앙상블 국면가중 (b) cost-optimized top-N sweep(10-20bps 민감도) (c) holdout time-series CV rolling (d) 비-return 원천으로 2017+ decay 상쇄.
- **live_trigger**: 2017+ cohort decay 회복 국면(unified_regime) 또는 비-return 데이터원(DART 등) 등재 시 재측정.

## 6. CCS(프로세스) 정성 평가
실측-only ✓ · PIT C1~C15 ✓(4렌즈 검증) · 방화벽 통과 ✓ · 역할분업(forge 측정 + 4렌즈 적대검증 + Q-Lead 종합) ✓ · 문서화 ✓ · Axiom 엔진 emit ✓. hard violation = 0.

## 7. 산출
- 측정: `02_Infrastructure/ramp/run_ramp_r1_sleeve_stack.R`
- 결과: `outputs/ramp/{r1_summary_20260705.json, r1_per_sleeve_gates.parquet, r1_stack_gates.parquet}`, `.cache/_ramp_r1_20260705.{rds,txt}`
- 검증: workflow task wqj2nlawr (4렌즈)
- L-code: `stage_artifacts/l_code/ramp/l_code_RAMP_R1_SLEEVE_STACK_20260705.json`
