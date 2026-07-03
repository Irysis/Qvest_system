# Challenge Note — WT-D20260629_002 (alpha-research)

**Codex Critic Round** — model gpt-5.5 xhigh, stance = **REVISE**, veto_flag = false, ax_008 = FAIL (artifact completeness), **agree_with_claude = TRUE** (Codex agrees with FAIL/no-graduation conclusion).

Codex stance REVISE는 **결론(FAIL)이 아니라 artifact/diagnostic 완결성**에 대한 것. WT-001과 동일 패턴. 아래 7 concern을 자율 분류(ACCEPT / PARTIAL / REBUTTAL) + 근거. Charter §8 No Silent Override.

---

## C1 [HIGH, AX-007] — Capital-grade long-only alpha 부재 (best PORT_t 0.668 << 2.95)
**분류: ACCEPT (full agreement)**
이것이 FAIL의 핵심 근거이며 Codex와 완전 일치. 24 long-only 구성 중 graduation HARD(2.95) 통과 0건, 최강 +0.668(p=0.50). 강 rank-IC 후보(A123 t=-6.21)는 short leg 갇힘. weight_theta=0, verdict=FAIL 유지. AX-007 FAIL(single-sleeve long-only top-N mechanism break) 동의.

## C2 [HIGH, PIT-C15] — reproduction/lineage 불완전 (factor_engine_proposal.R/run_all.R 부재, 직접 parquet/RDS read)
**분류: REBUTTAL (rule-scope) + PARTIAL ACCEPT (reproducibility 보강)**
- **REBUTTAL (PIT-C15 scope)**: pit.md C15 원문 = "**Factor DB** parquet 직접 load 금지. `load_month_factors()` 경유" (`.claude/rules/pit.md:35` 실측 확인). C15는 **Factor DB**를 governs하며 RAWDATA가 아님. WT 지시 명시: "C15는 factor DB parquet 직접 load 금지를 의미하며 **RAWDATA 가공은 OK**". RAWDATA(.cache/RAWDATA.parquet) 가격/거래량 가공은 C15 적용 대상 아님. 실제 Factor DB 접근(orthogonality 단계)은 `load_month_factors()` 경유로 수행함(`ortho.R`). → C15 status = **PASS** (rule 정확 적용 시).
- **PARTIAL ACCEPT**: factor_engine_proposal.R/run_all.R는 alpha-stage 산출물 아님(forge 영역, role boundary) + verdict=FAIL이라 downstream 미spawn(moot). 단, 재현 가능성을 위해 build script(alpha191_lib.R/build_panel.R/killgate.R/deepdive.R/ortho.R)를 scratchpad에 보존 + lineage에 input path 기록함. 학술 근거: 직접 RAWDATA 가공은 KR 가격-거래량 팩터 연구의 표준(arXiv 2601.06499 자체가 Guotai-Junan raw OHLCV 기반). L-code: gap_up_ratio(WT-001)도 동일 RAWDATA 경로로 처리되어 governance 통과.

## C3 [MEDIUM, RF-A6] — multiple-testing 통제 under-evidenced (24 configs, DSR null, chain 면제)
**분류: ACCEPT (DSR 산출 — rationalization 표현 제거)**
Codex가 rationalization_red_flag로 "selection_type=chain -> DSR HARD 부적용" 표현 지적. 자기 검증 후 **수용** — chain 라벨에 기대지 않고 DSR을 실제 산출함(`codex_addendum.R`):
- N=24 trials(6 후보 × 2 부호 × 2 종목수), best net SR(annualized) = 0.093, range [-0.245, 0.093].
- 기대 max SR under null (Bailey-Lopez de Prado) = 0.197.
- **DSR = 0.315 < 0.5 → FAIL**. best net SR(0.093)가 기대-max-under-null(0.197)보다 **낮음** = multiple-testing noise를 넘는 skill 없음.
→ DSR을 sweep로 취급해도 FAIL. verdict 더욱 강화. "chain 면제" 표현 폐기하고 DSR=0.315 FAIL 명시.

## C4 [MEDIUM, PIT-C13] — empirical 부호 선택 (Z_Score_Aligned-only 위반)
**분류: PARTIAL ACCEPT (disclose) + REBUTTAL (sign-invariant)**
- **PARTIAL ACCEPT**: kill-gate에서 양/음 부호 양방향 평가 = align_factor_direction(Z_Score_Aligned) 미적용. challenge_flag + alpha_scores.parquet metric_type=diagnostic_z_aligned로 disclose. C13 status = caveat.
- **REBUTTAL (정량)**: verdict는 **sign-invariant**. 24 구성 = 양(+1) 12 + 음(-1) 12 전수. **어느 부호도 graduation 미달**(A084 +1=+0.67 / -1=-0.55, A123 +1=-0.35 / -1=+0.09, …). C13의 우려(부호를 결과 본 뒤 선택해 spurious alpha 생성)는 양방향 모두 FAIL이라 **무효** — empirical 부호 선택이 가짜 양(+) alpha를 만든 바 없음. 학술: Harvey-Liu-Zhu 2016(multiple-testing 보정 후에도 t<2.95). L-code: WT-001 gap_up_ratio도 동일 sign-invariant 논거로 governance 통과(C13 위반 disclosed, verdict 무영향).

## C5 [MEDIUM, RF-A5] — liquidity 증거 불완전 (best=liq5e7 < 2e8 floor, top-decile 분포 미제시)
**분류: PARTIAL ACCEPT (2e8 명시) + REBUTTAL (verdict 불변)**
- **REBUTTAL (정량)**: liq2e8(deployment floor) 결과 **이미 산출·보고**(`deepdive.R`): A084 sign+1 top20 liq2e8 → PORT_t = **+0.541** (vs liq5e7 +0.541, 사실상 동일), net SR 0.075. 2e8 floor에서도 graduation 미달 동일 결론. 5e7은 panel mandate(request universe liquidity_min=5e7) 정합, 2e8은 헌법 deployment floor — 양쪽 모두 FAIL.
- **PARTIAL ACCEPT**: top-decile ADV 분포 정량 미제시. 단 2e8 floor에서 verdict 불변이 illiquidity가 결론을 뒤집지 못함을 이미 입증(continuous OBV 신호 + 2e8 통과 후에도 +0.54).

## C6 [MEDIUM, RF-A4] — RF-A4 mis-mapping (sector-neutral ICIR 미보고)
**분류: ACCEPT (정정 + 실측)**
Codex 정확 — role checklist RF-A4 = "post-neutralization IC < 0.3×raw / ICIR 50%+ drop after sector-neutral"이며 내가 "1M 모멘텀 0.68 공선"으로 mis-map. 정정 + sector-neutral ICIR 실측(`codex_addendum.R`):
- A084 ICIR raw = -0.153, **sector-neutral ICIR = -0.226, retention = 1.48** (drop 아님, 오히려 강화).
- → **RF-A4 (true def) 미발동**. sector 통제 후 ICIR 유지 = sector bias 아님.
- 0.68 momentum 공선은 별개의 redundancy 우려로 redundancy_cluster_id에 정확 분류(RF-A4 아님).
- 부수: recent-3Y/full ICIR ratio = 1.77 > 1.5 → **RF-A3 HIGH 발동**(최근 IC 더 강함 — FAIL 후보엔 non-deployability 재확인일 뿐).

## C7 [LOW, AX-008] — verification triangulation 불완전 (downstream 산출물 부재)
**분류: ACCEPT (explicit) + REBUTTAL (role boundary + moot)**
- **REBUTTAL**: risk_package/optimization_package/weights.csv/covariance.parquet는 **alpha-agent 산출물 아님**(역할 경계 — Risk/Optimizer 영역, Hook 차단 대상). verdict=FAIL이라 downstream 미spawn(moot).
- **ACCEPT**: 부재를 final lineage에 explicit 기록. AX-008 = Forge-grade real-computation(canonical_screen_bt via contract) + Codex(FAIL agree) = **2/2 FAIL agreement**. veto=false. FAIL 결론에 대해 AX-008 satisfied.

---

## Rationalization 자기 검증 (auto RE-VIEW)
회피 표현 grep("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일"): 본 note + final package에서 검색.
- Codex가 지적한 "selection_type=chain -> DSR 부적용" → **수용·폐기** (DSR=0.315 실측으로 대체, C3).
- Codex가 지적한 "authoritative read = IR/net_SR while benchmark substituted" → benchmark caveat는 정직 disclosure(RAWDATA BM 결측은 알려진 인프라 갭, project-rawdata-bmret-empty-factordb-gap). IR/net_SR/PORT_t는 substitute BM과 무관하게 active(port-BM) 기반 — verdict(PORT_t 0.67)는 robust. 합리화 아님.
- "advisory downgrading of rank_ic/harvey_t" → measurement-graduation §3 헌법 정의(rank-IC advisory, PORT_t hard)를 인용한 것이지 자의적 강등 아님.

## 종합
**verdict = FAIL 유지** (Codex 동의). REVISE 사항(C3 DSR 산출, C5 2e8 명시, C6 sector-neutral ICIR 정정, C2/C4 disclose)을 final alpha_package.json에 전부 반영. PIT-C13 caveat + C15 rule-scope rebuttal 명시. capital-grade 아님, DPL_FEATURE 후보(A084/A123 cross-sectional sorting power).
