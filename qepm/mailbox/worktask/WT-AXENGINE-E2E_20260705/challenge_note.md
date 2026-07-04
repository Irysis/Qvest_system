# Self-Adversarial Challenge — WT-AXENGINE-E2E_20260705 (alpha-research)

Opus 4.8 native adversarial pass (v8.2 — Codex Round 대체). finalize 직전, 본 리서치의 약점을 스스로 적대적으로 제기 → 분류(ACCEPT/PARTIAL/REBUTTAL) → 근거 기록. Charter §8 No Silent Override.

## Concern 1 — regime signal PIT/lookahead 취약 (HIGH)
**제기**: `unified_regime_signal.parquet`의 `Category`를 sig_date t의 값으로 사용했으나, 이 regime 산출물이 in-sample으로 fit된 분류기(MSM/FRED/KTRI/VEA 합성)일 수 있다. 만약 Category가 full-sample 통계로 라벨링됐다면 C1(full-sample) 위반이며, "CRISIS/CAUTION"의 정의 자체에 forward 정보가 샐 수 있다.
**분류: PARTIAL (ACCEPT lookahead-risk, 그러나 verdict 무변)**.
- 근거: 본 리서치의 **결론이 negative**다. Lookahead가 있었다면 regime-conditional 성과를 *낙관* 편향시킬 것인데, 실측이 오히려 negative(PORT_t −2.61)이므로 lookahead가 결론을 뒤집지 못한다. AX-000 정직보고: negative 결론은 optimistic-bias 오염에 robust.
- 그러나 향후 이 regime 신호를 *positive* frontier에 쓰려면 반드시 asof-toggle test(prod vs full-sample-IC)로 look-ahead 정량화 필요 — 06-18 RAMP graduation 감사 선례(prod 3.66 vs full 4.38 = 코드가 0.72t 제거). 본 태스크는 candidate가 FAIL이라 미실행. 라벨: `regime_lookahead=untested_but_verdict_robust`.

## Concern 2 — conditional_ic_matrix(ic_bad>ic_good) → 잘못된 mechanism 착수 (HIGH)
**제기**: 착수의 근거로 삼은 conditional_ic_matrix의 `ic_bad > ic_good`(quality가 bad regime서 rank-IC 강함)는 **rank-IC 지표이지 long-only 실현 alpha가 아니다**. 이 rank-IC를 realized alpha로 오독하여 "CRISIS서 quality 활성화" frontier를 착수 — 이는 measurement-graduation §2/§6("직교≠수익", rank-IC t≠portfolio-alpha t)를 착수 단계에서 위반한 셈.
**분류: ACCEPT (착수 논리 결함 인정)**.
- 실측이 정확히 이를 드러냄: quality standalone active by regime = CRISIS **−78%/yr(t−1.76)**, RISK_ON −8.8%(t−2.16), CAUTION만 +7.1%(t0.30, n13 무의미). ic_bad(rank)와 realized long-only active의 부호가 CRISIS에서 정반대. 
- 교훈(다음 frontier에 반영): regime-conditional 착수 근거는 rank-IC가 아니라 **regime별 realized long-only active(canonical_screen_bt period_returns 분해)**여야 한다. conditional_ic_matrix는 지도용일 뿐 mechanism 증거가 아님. → alpha_validation에 `mechanism_evidence_must_be_realized=true` 기록.

## Concern 3 — 벤치마크 basis가 결과를 지배 (MEDIUM, 해석 위험)
**제기**: 모든 변형이 PORT_t 음수인데, 이는 신호 실패가 아니라 **cap-weighted KOSPI200 vs EW top-25의 basis mismatch**일 수 있다. 실제로 universe EW 자체가 BM 대비 −1.5%/yr, top-25 quality는 universe EW 대비 **+3.3%/yr gross**(신호 selection power 실재). 즉 신호는 살아있고 벤치가 이긴 것.
**분류: PARTIAL**.
- ACCEPT: 신호의 cross-sectional selection power는 실재(rank-IC +0.036, top25 vs uni-EW +3.3% gross). "완전 무신호"라 결론하면 과장.
- REBUTTAL(verdict 유지): 그러나 헌법상 authoritative benchmark = cap-weighted KOSPI200(canonical_screen_bt `benchmark_id=KOSPI200_total_return`, §2 forge-authoritative 정합). 배포 envelope(25종 long-only)에서 자본 자격은 cap-w PORT_t로 판정 — RAMP 06-18 선례와 동일(EW-uni 낙관 라벨 기각). basis 완화를 레버로 제시하는 것은 AX-000 따름정리(제약=고정축) 위반. 따라서 "신호 있음 ∧ 자본자격 없음" 동시 성립 = §6 "직교≠수익" 재확증. 라벨: `metric_type=canonical_screen(cap-w authoritative)`.

## Escalation 판정
- HIGH severity ≥ 5? → 아니오 (HIGH 2건). 
- AX axiom hard FAIL ≥ 3? → 아니오.
- PIT C1(lockbox/lookahead) 위반? → 아니오 (Concern 1 = untested-risk, verdict-robust, 미확정 위반 아님).
- **→ Q-Lead auto-escalate 미발동.** 단, Concern 2(mechanism 착수 논리 결함)는 다음 frontier 설계에 must-carry (alpha_validation next_frontier에 기록).

## AX-008 Verification Triangulation
- self-adversarial: 본 노트 (완료).
- forge: 미실행(candidate FAIL — full pipeline 진행 부적격). 
- architect: 미실행.
- → candidate가 FAIL이므로 3-source 2/3 요건은 적용 대상 아님(admission 후보 아님). 본 태스크는 *지식 소비 E2E 검증*이 1차 목적이며 그 목적은 PASS(아래 alpha_validation).
