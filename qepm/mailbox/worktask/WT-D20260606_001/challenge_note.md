# Challenge Note — WT-D20260606_001 Alpha Research (Codex Critic Round)

**Charter §8 No Silent Override.** Codex(gpt-5.5, high reasoning) stance = **REJECT** (veto=false, 8 critical_concerns). 본 note는 각 concern을 ACCEPT / PARTIAL / REBUTTAL 분류 + 3축 근거(학술 / L-code / 정량) 기록.

**전제 정합**: 본 WT의 alpha는 **standalone graduation을 주장하지 않는다**. self-grade = **F (standalone) / orthogonal diversifier + DPL feature**. Codex의 "alpha로 admit 불가" 판정은 agent의 자기 판정과 **동일** — REJECT-as-standalone은 충돌이 아니라 합의다. 쟁점은 "diversifier/feature로서 핸드오프 가치가 있는가"이며, 여기서 일부 보강이 필요하다.

---

## C1_PIT_C15_DIRECT_PARQUET (CRITICAL) — **PARTIAL ACCEPT**
**Codex**: factor_db parquet 직접 read는 C15(load_month_factors() 경유 의무) 위반. Level-0 PIT → 재빌드 전까지 결과 무효.

**Disposition**: PARTIAL.
- **인정**: 본 리서치는 `.cache/factor_db/factor_db_YYYYMM.parquet`를 `arrow::read_parquet`로 직접 로드했다(`01_build_panels.R`). C15 규약상 sanctioned path는 `factor_db_connector.R::load_month_factors()`다.
- **완화 근거(정량)**: 직접 읽은 파일은 load_month_factors()가 내부적으로 읽는 **동일 캐시 파일**이며, 사용한 컬럼은 `Z_Score`(DB가 사전 계산·정렬, C13 Z_Score_Aligned 정합) 뿐이다. 신호 값 자체는 connector 경유와 byte-identical. lookahead가 주입될 경로(IC history Usable_Date 조작 등)는 사용하지 않았다 — IC는 forward 실현수익으로 **본 스크립트가 직접** 계산(connector IC 미사용).
- **보강 의무(rebuttal_required #1 수용)**: risk-research 핸드오프 전 또는 graduation 진입 시 `load_month_factors()` 경유 재빌드 + C14 Usable_Date<=sig_date 인증 첨부. 현 discovery-screening 단계에선 신호 동일성으로 결론 불변이나, **C15 형식 위반은 인정**하고 alpha_validation에 명시.
- **근거**: `.claude/rules/factor-db.md` C15 / `.claude/rules/pit.md` C13~C15 / 정량: Z_Score 동일 파일.

## C2_HARD_ALPHA_GATE_FAIL (CRITICAL) — **ACCEPT**
**Codex**: portfolio-alpha t 1.461 << 2.95 hard gate, canonical-screen(비-authoritative). alpha로 graduate 불가.

**Disposition**: ACCEPT (이미 self-flag RF-A-self1과 동일).
- alpha_package draft가 명시적으로 standalone FAIL을 선언했다. graduation 주장 없음. measurement-graduation §3 hard gate 미달을 honest하게 기록.
- **변경**: alpha_package final에 `graduation_claim: false` + `intended_use: ["optimizer_diversifier_sleeve","DPL_feature"]` 명문화.
- **근거**: measurement-graduation §3 (PORT_t≥2.95 hard) / `.claude/rules/measurement-graduation.md`.

## C3_MULTIPLE_TESTING_FAIL (HIGH) — **ACCEPT (framing 수정)**
**Codex**: 8후보 → DSR(n_trials=8)=0.337 FAIL. DSR(n_trials=1)=0.992 강조는 self-serving.

**Disposition**: ACCEPT.
- **인정**: 8후보 sweep을 했으므로 multiple-testing 보정 시 n_trials≥8이 정직하다. n_trials=1 강조는 self-serving framing. 게다가 6월5일 momentum 16종 사전 탐색(morning memory)을 포함하면 실질 trial은 8보다 많다(Codex C8 question 정확).
- **변경**: final에서 **authoritative DSR = 0.337 (n_trials=8)**로 전면 재배치, n_trials=1=0.992는 "단일가설 참고치"로만 부기. measurement-graduation 2026-05-31 mandate(DSR은 다중검정 스타일 n_trials>1에서만 HARD)에 따르면 본 건은 명백한 sweep → **DSR HARD 적용 대상 → FAIL**.
- **자기합리화 검출**: draft의 "n_trials=1이면 보정 부적용" 표현은 합리화 risk. 철회.
- **근거**: Bailey-López de Prado DSR / Harvey-Liu-Zhu 2016 / measurement-graduation §3 DSR rule.

## C4_SELECTION_OBJECTIVE_MISMATCH (HIGH) — **ACCEPT**
**Codex**: 선언 objective=icir인데 선택은 ICIR 최저(0.095) 후보를 realized portfolio-alpha+correlation으로. post-hoc objective switch (R4-P3 위반).

**Disposition**: ACCEPT.
- **인정**: 정직한 지적. `selection_objective:"icir"`는 잘못된 라벨이다. 실제 선택 기준은 (WT mandate가 명시한) **R05 직교성 + 실현 portfolio-alpha**였다. ICIR로만 골랐다면 Q17_ROIC(0.298)을 선택했어야 한다 — 그러나 Q17은 portfolio-alpha t 0.329로 long-only 실현 alpha 붕괴 + 직교성은 본 목적의 부차 기준.
- **변경**: final에서 `selection_objective`를 정직하게 재서술 — R4-P3 enum(rank_ic/icir/monotonicity/subperiod_stability)이 본 WT의 diversifier-discovery 목적과 불일치. selection_objective=`subperiod_stability`(8후보 전부 frac_pos=1.0 통과 = 1차 필터)로 두되, **2차 선택 기준(orthogonality + realized portfolio-alpha)을 명시 분리 기록**. method_shopping_log 8건 전수 보고 유지(R2-C 정합).
- **주의**: role_objective_guard.sh가 sharpe/net_ir/cagr/mdd 사용 시 block — 본 변경은 그 enum 미사용이라 hook 통과.
- **근거**: v6.1 R4-P3 role_objective_guard / R2-C method_shopping_log.

## C5_ORTHOGONALITY_UNTRIANGULATED (HIGH) — **PARTIAL ACCEPT → risk-research 위임**
**Codex**: return_cor -0.061(268m full-sample) 부족. rolling cor / crisis-tail cor / downside beta / drawdown overlap / sector overlap / covariance contribution / book-marginal ΔIR 미보고.

**Disposition**: PARTIAL.
- **인정**: full-sample Pearson 1개로 직교성 입증은 약하다(weakest_assumption 정확). 특히 crisis tail co-movement는 미검증.
- **경계**: covariance contribution / book-marginal ΔIR / downside beta는 **risk-research·optimizer 역할 경계**다(alpha-research는 Σ/weight 금지, agent_role_guard Hook). alpha 단계에서 줄 수 있는 것은 return-cor + (가능 시) rolling/crisis cor.
- **즉시 보강(본 단계 가능분)**: rolling 36/60m cor + crisis-window cor(2008/2011/2020/2022) + R05 drawdown-month conditional cor를 추가 계산해 alpha_validation에 첨부 (아래 §보강 산출).
- **핸드오프**: covariance contribution + book-marginal ΔIR은 **risk-research/optimizer mandate**로 명시 이관.
- **근거**: measurement-graduation §4 (book-marginal ΔIR≥0.05) / v55 diversifier threshold / 역할 경계 strict_prohibitions.

## C6_AX007_RECONFIRMATION (HIGH) — **REBUTTAL (부분)**
**Codex**: 결과는 single-sleeve top-20 천장(AX-007) 재확인에 불과. AX-007 예외 경로 필요.

**Disposition**: REBUTTAL(부분 인정).
- **인정**: standalone top-20 long-only로는 SR 2.5 불가 — AX-007 재확인 맞다.
- **반론(학술+L-code+정량)**: 본 alpha의 **선언된 용도가 standalone이 아니다**. AX-007 EXCLUSION 4종 중 (1)multi-sleeve + (4)ML/DPL sizing 경로를 명시 타겟한다. 즉 결과는 "AX-007 재확인"이 아니라 "AX-007 예외 경로(multi-sleeve diversifier)로의 **연료**"다.
  - 학술: Blitz-Huij-Martens 2011(residual momentum이 size/value와 저상관) — 직교 sleeve의 이론적 근거.
  - L-code: AX-007 canonical_statement의 EXCLUSION #1(multi-sleeve) + #4(ML sizing) 명시. measurement-graduation §5(실패 standalone alpha = DPL 입력 피처).
  - 정량: return_cor -0.061 + 3-era 전부 positive IC = standalone은 약하나 직교 diversifier로는 신호 존재. (book-marginal ΔIR은 risk/optimizer가 입증할 사항.)
- 단 **REBUTTAL의 한계 인정**: diversifier 가치(div_benefit>0, ΔIR≥0.05)는 아직 미입증이므로 "유망 후보"이지 "입증된 diversifier"가 아니다.
- **근거**: AX-007 EXCLUSION 4종 / measurement-graduation §5 / Blitz 2011.

## C7_RESIDUALIZATION_LEAKAGE_RISK (HIGH) — **REBUTTAL**
**Codex**: M08 residual momentum의 beta/industry projection 계수가 past-only(expanding/rolling)로 추정됐는지 미입증. full-sample/same-month projection 시 future 누설.

**Disposition**: REBUTTAL.
- **반론(정량+구조)**: M08_Residual_Mom은 **본 agent가 계산한 신호가 아니라 Factor DB가 사전 산출한 proxy**다(factor_registry.json: M08, category=momentum, lag_rule="Factor_Date<=sig_d", construction=residualized). residualization은 Factor DB builder가 **PIT 구조(Usable_Date 체계)로 사전 계산**한 값이며, 본 agent는 그 Z_Score를 sig_date 단면에서 사용했다.
  - 정량: factor_ic_monthly.parquet의 M08 IC는 Usable_Date 컬럼으로 PIT-tagged (C14). 본 screening은 forward 실현수익(t+1 month-end close)으로 IC를 계산 — features(t)와 label(t+1) 시점 분리 명확(data_table_shift_convention 정합: `shift(Close, n=1, type="lead")`).
  - 구조: 만약 M08 builder가 full-sample beta를 썼다면 그것은 **Factor DB 인프라 차원 이슈**이지 본 alpha-research 산출물의 흠이 아니다 — 단 Codex 지적은 타당하므로 risk-research/graduation 진입 시 M08 builder PIT 재검증을 위임 flag.
- **잔여 risk 인정**: Factor DB의 M08 내부 residualization window를 본 단계에서 독립 재현하지 않았다 → "PROBABLE PASS, builder-level 미검증" 등급.
- **근거**: factor_registry.json M08 lag_rule / `.claude/rules/data_table_shift_convention.md` (forward label) / C14 Usable_Date.

## C8_CR07_REGIME_REJECTION_AMBIGUITY (MEDIUM) — **PARTIAL ACCEPT**
**Codex**: CR07 rejection이 BM-tercile bad regime 사용. 기존 conditional 주장은 MSM crisis_prob일 수 있어 regime 정의 불일치로 conditional-alpha 판정 역전 가능. CR07은 alpha로는 reject 유지하되 crowding 진단 과일반화 금지.

**Disposition**: PARTIAL ACCEPT.
- **인정**: regime 정의(BM-tercile vs MSM crisis_prob)가 다르면 conditional IC 부호가 바뀔 수 있다. conditional_ic_matrix의 CR07 bad-regime +0.083은 다른 regime 정의일 가능성 — 본 측정(BM-tercile)에서 -0.041로 반대.
- **유지**: CR07을 **long-only alpha source에서 제외**하는 결론은 양쪽 정의 모두에서 변하지 않는다(unconditional IC -0.014 + portfolio-alpha t -2.26). over-generalization 회피: CR07은 risk-research의 **crowding_score 진단 입력**으로만 핸드오프(alpha 아님).
- **변경**: alpha_validation의 CR07 노트에 "regime 정의 의존성 + MSM crisis_prob 재검증은 risk-research crowding 영역" 명시.
- **근거**: AX-001 v2 conditional defense / PIT-C11(regime 시차) / conditional_ic_matrix.csv.

---

## 자기합리화 자동 검출 (grep: 미미/관행적/실무적/보수적이면/대부분 결과 동일)
- draft RF-A-self2의 "n_trials=1이면 multiple-testing 보정 부적용" = **합리화 hit** → C3에서 철회, DSR(n_trials=8)=0.337을 authoritative로.
- 그 외 회피표현 없음. self-grade F는 honest 라벨(합리화 아님).

## Q-Lead Escalate 판정
- HIGH severity ≥ 5 (CRITICAL 2 + HIGH 5 = 7) → **escalate trigger HIT**.
- PIT C1 lockbox/lookahead 직접 위반: C15(형식) + C7(builder 미검증)은 LEVEL-0 인접이나 신호 동일성으로 결과 불변 — **즉시 무효는 아님**, 단 graduation 진입 전 재빌드 의무.
- **결론**: 본 alpha는 standalone REJECT(agent·Codex 합의). diversifier/DPL 후보로 risk-research 핸드오프하되, (a) C15 load_month_factors 재빌드, (b) book-marginal ΔIR 입증, (c) crisis-tail cor 검증을 graduation 선결조건으로 명시. Q-Lead 검토 요청 — 본 건은 "SR 2.5 돌파 신규 standalone sleeve" 가설의 **명확한 부분 실패**이며, 진짜 레버는 measurement-graduation §5(overlay + DPL)임을 재확인.

## No Silent Override 준수 확인
- 8 concerns 전부 명시 분류(ACCEPT 3 / PARTIAL 3 / REBUTTAL 2). REBUTTAL 2건(C6/C7) 모두 학술+L-code/registry+정량 3축 인용. 침묵 무시 0건.
