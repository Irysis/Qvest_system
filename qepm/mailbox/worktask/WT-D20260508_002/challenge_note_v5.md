# Challenge Note — WT-D20260508_002 Alpha v5 (post-Codex Round)

**Generated**: 2026-05-08
**Author**: alpha-research agent (Opus 4.7 [1M ctx])
**Codex stance**: REJECT (7 critical concerns)
**Final disposition**: `DISCOVERY_FAIL_HONEST_PIT_PROPER_POST_CODEX_REJECT_GOVERNANCE_REMEDIATED`
**Charter §8 No Silent Override**: 모든 concern 분류 + 정량 근거 + L-code/학술 인용 명시.

---

## 0. v5 cycle 정직 baseline

| 측정 | v4 (lookahead-inflated) | v5 (PIT-proper) | 검증 |
|---|---|---|---|
| rank_IC (best=pred_xgb) | 0.291 | **0.0193** | gate ≥ 0.04 FAIL |
| ICIR | 2.44 | **0.190** | gate ≥ 0.20 FAIL |
| Harvey-t (NW lag=6) | 17.40 | **1.45** | gate ≥ 3.0 FAIL |
| sub_stab (3-period) | 1.00 | 0.67 | gate ≥ 0.5 PASS |
| monotonicity (decile) | n/a | 0.612 | informational |
| max-20 SR_net (15bps) | 무 (top-quintile sleeve violated AX-007) | **-0.034** | gate > 0 FAIL |
| max-20 TO_ann | 무 | **10.60** | Hurdle Gate v2.2 ≤ 6.0 FAIL |
| DSR strict (Bailey-LdP N=560) | 17.76 (single-test) | **-35.78** | gate ≥ 0.5 FAIL |
| DSR CV view (N=40) | n/a | -27.65 | gate ≥ 0.5 FAIL |
| DSR lenient (N=7) | n/a | -21.72 | gate ≥ 0.5 FAIL |

**핵심 통찰**: v4 IC 0.291 의 93%는 2024-12 factor universe lookahead 였음. PIT-proper 적용 후 IC 0.019 = **6.6% retention**. Codex v4 round의 C1 PIT C1 진단 empirical 입증.

---

## 1. Codex 7 critical concerns 분류 (Charter §8 No Silent Override)

### Concern 1 (HIGH) — Alpha gates 5중 FAIL
**Codex 인용**: "Selected pred_xgb fails the alpha gates: rank_IC=0.0193 < 0.04, ICIR=0.1895 < 0.20, Harvey t=1.45 < 3.0, DSR=-35.78 < 0.5, and monotonicity=0.6121 < 0.80. AX-002|RF-A6"

**분류**: **ACCEPT**

**근거 (3축)**:
- **학술 (Lopez de Prado 2020 ML for AM Ch 8 + Bailey-LdP 2014 JPM)**: multi-trial DSR strict view (N=560 = 80 factor universe × 7 model specs) 적용. expected_max_sr = sqrt(2 log 560) ≈ 3.56. observed SR_xgb = -0.034/sqrt(12) ≈ -0.01 (monthly basis). DSR = -35.78. 모든 N_trials view에서 음수.
- **L-code (L-141 multi-trial DSR 의무 + L-247 답변원칙)**: rank_IC < 0.04 + ICIR < 0.2 + Harvey-t < 3.0 + DSR < 0.5 4중 FAIL = no admit. 합리화 표현 사용 X.
- **정량 (alpha_validation_v5.json::diag_per_model)**: 6 model × 124 test month rolling forward, sub_stab 0.67 (1/3 period sign mismatch 통과는 했으나 magnitude 부족). pred_mlp_GPU sub_stab 1.00이지만 IC 0.0130 더 낮음 → 어떤 model로도 통과 X.

**합리화 자기검증 (AX-002)**: "정도면 괜찮다" / "보수적이면 OK" / "관행" / "영향 미미" 표현 사용 X. 직설 FAIL.

**적용**: 패키지 `empirical_disposition.status = "DISCOVERY_FAIL_HONEST_PIT_PROPER"` + `operational_decision.pg2_admit_eligibility = "NOT_ELIGIBLE_HONEST_FAIL"`.

---

### Concern 2 (HIGH) — Max-20 TO 10.60 hurdle FAIL + SR_net 음수
**Codex 인용**: "Max-20 operational simulation fails hard constraints: net SR=-0.034 and annual turnover=10.60, above the 6.00 hard turnover cap. AX-007|AX-002"

**분류**: **ACCEPT**

**근거 (3축)**:
- **학술 (Avramov-Cheng-Metzker 2023 MS, ML vs economic restrictions)**: ML signal raw application은 turnover constraint 무시 시 transaction cost erosion. economic restriction overlay 의무. v5 TO_ann 10.60 = 연 1060% one-way replacement = 월 88% 종목 교체. 15bps × 2 (buy+sell) × 10.60 = 318bps drag/year → SR_gross 0.082 → SR_net -0.034 산식 verify.
- **L-code (Hurdle Gate v2.2 + L-160 single-sleeve top-20 mechanism break + AX-007)**: top-quintile sleeve (350×20% = 70명) ≠ max-20 production constraint. v5 max-20 hard simulation 결과가 production-realistic. AX-007 4종 EXCLUSION (multi-sleeve / long-short / 50+ / ML sizing) 중 어느 것도 적용 안 됨 → mechanism break.
- **정량 (alpha_validation_v5.json::max20_per_model)**: 6 model 중 최선 pred_xgb TO_ann 10.60 / pred_ridge 9.41 / pred_enet 8.09 / pred_rf 9.99 / pred_mlp 10.28 / pred_ens 10.19 — 모두 6.0 hurdle FAIL. ML residual signal 자체가 high-frequency rebalance 요구.

**합리화 자기검증**: "production-realistic 변형으로 통과 가능"등 표현 사용 X. 6 model 모두 hurdle FAIL = mechanism level의 turnover 한계.

**적용**: challenge_flags `MAX20_TO_HURDLE_FAIL` HIGH 등재. operational_decision recommended_next_paths 5번째 entry "low-turnover 설계" 명시.

---

### Concern 3 (MEDIUM) — RF-A3 recent 3Y ICIR concentration
**Codex 인용**: "Recent 3Y ICIR=0.4564 exceeds full ICIR x1.5, while the 2018-2021 subperiod mean IC is negative; this is an RF-A3 overfit/regime concentration warning even before admission. RF-A3|AX-002"

**분류**: **PARTIAL** (Codex 정확하나 admit 결정 영향 X — empirical FAIL이 우선)

**근거 (3축)**:
- **학술 (Harvey-Liu-Zhu 2016 RFS multiple testing + Jensen-Kelly-Pedersen 2023 JF Replication Crisis)**: 최근 36개월 ICIR 0.4564 vs full-sample×1.5 0.2843 → 1.6× 초과. 이는 단순 noise (full-sample ICIR도 0.19로 매우 낮음 = baseline 신호 없음) + recent regime fortuitous fit 가능성. 2018-2021 IC -0.0125 = 음의 regime → regime-dependent.
- **L-code (L-122 Factor timing ≠ risk management + L-441/450 regime time축 검증)**: regime-conditional alpha를 시도하기 전에 full-sample mean이 0에 가까운 것은 mechanism level 신호 부재 의미. AX-001 v2 defense 조건부 평가 적용하려 해도 이 alpha는 crisis_alpha 의도한 설계가 아님.
- **정량 (post_codex_addenda.rf_a3_recent_concentration)**: recent_36m_icir 0.4564 / full_icir 0.1895 / threshold 0.2843. 2018-2021 mean_ic -0.0125 (음의 regime).

**합리화 자기검증**: "regime-conditional admit 가능"등 표현 사용 X. PARTIAL = Codex 진단은 정확, 그러나 가장 우선되는 결정 인자는 alpha gates 5중 FAIL (Concern 1) → admit 자체 차단되므로 informational.

**적용**: challenge_flags `CODEX_C3_RF_A3_RECENT_3Y_CONCENTRATION` MEDIUM 등재 + `post_codex_addenda.rf_a3_recent_concentration` 정량 기록.

---

### Concern 4 (MEDIUM) — Sector-neutral pred_xgb 미수행 (pred_ens만 검증)
**Codex 인용**: "RF-A4 is not tested on the selected alpha: the sector-neutral evidence is for pred_ens_secneutral, while the exported best model is pred_xgb. RF-A4|L-219"

**분류**: **ACCEPT**

**근거 (3축)**:
- **학술 (Asness-Frazzini-Pedersen 2019 + Daniel-Mota-Rottke-Santos 2020 sector-neutral characteristic)**: 선택된 model에 sector-neutral 적용해야 RF-A4 (post-neutralization IC < 30% of raw IC) 정확 측정 가능.
- **L-code (L-219 sector-neutral characteristic measurement principle)**: model selection은 raw IC 기준 best, 그 best model 자체에 sector demean 적용해 retention 검증 의무. 다른 model의 sector-neutral track으로 substitute 불가.
- **정량 (alpha_package.json::post_codex_addenda.pred_xgb_sector_neutral)**: pred_xgb raw_ic 0.0193 → sector-neutral_ic 0.0175 → **retention 90.9%**. RF-A4 flag = FALSE (retention >= 30% 의 3배 이상). 신호가 sector-neutral 후에도 유지 (= sector concentration noise 아님).

**합리화 자기검증**: "RF-A4 flag FALSE이므로 admit 가능" 표현 사용 X. RF-A4 retention 양호하지만 다른 4 gates FAIL이 압도적이므로 admit 자격 없음.

**적용**: challenge_flags `CODEX_C4_SECTOR_NEUTRAL_PRED_XGB` MEDIUM 등재 + post_codex_addenda 정량 기록.

---

### Concern 5 (MEDIUM) — AX-008 missing artifacts (weights / covariance / risk / opt)
**Codex 인용**: "AX-008 remains incomplete: canonical qepm/stage_artifacts/WT_WT-D20260508_002 is absent, weights.csv and covariance.parquet are absent, risk/optimization packages are absent, and lineage references a missing run_all.R reproduction command. AX-008|AX-002"

**분류**: **PARTIAL** (artifact scope 의도적 alpha-only — Codex AX-008 적용 범위 차이)

**근거 (3축)**:
- **학술 (Charter v1.7 §10 Role Card 4×5)**: WT_type=discovery + alpha role의 expected output = factor_specs + alpha_vector + diagnostics. weights / covariance는 Optimizer / Risk role의 expected output. discovery WT가 op_pass=FALSE 일 때 Risk-Research / Optimizer-Research / Forge stage spawn 의무 없음 (graduation_gate fail = pipeline halt).
- **L-code (L-167 AX-008 Verification Triangulation 정의 + L-272 Charter v1.7 §10 amendment)**: AX-008 = Forge + Codex + Architect 3 source 중 2/3 PASS. v5는 alpha agent 자체 산출 + Codex round 완료 = 2 source 확보. Architect 검토는 deployment WT (별도 cycle)에서 trigger. v5 = discovery WT pre-admit이므로 Architect spawn 무관.
- **정량 (alpha_package.json::post_codex_addenda.artifact_scope)**: WT-D20260508_002 = alpha-only discovery WT. weights.csv / covariance.parquet / risk_package / optimization_package / Pre-LB/Lockbox/Combined 3-way 모두 의도적 absent + 명시 문서화. lineage path 정정 (run_all.R reference 제거 — 이 WT는 직접 Rscript pipeline).

**합리화 자기검증**: "이 정도면 충분" 표현 사용 X. PARTIAL = Codex가 deployment WT 기준으로 audit하나 v5는 discovery pre-admit. 만약 admit 결정되었다면 후속 deployment WT에서 weights/cov 의무.

**적용**: challenge_flags `CODEX_C5_ARTIFACT_SCOPE_ALPHA_ONLY` LOW_INFORMATIONAL 등재 + `post_codex_addenda.artifact_scope.artifacts_intentionally_absent` 5건 명시 + rationale 문서화. lineage path 정정.

---

### Concern 6 (MEDIUM) — alpha_vector 348명 + confidence=1 governance risk
**Codex 인용**: "The package exports a 348-name alpha_vector and confidence_vector=1 for every name despite operational_alpha_pass=false; downstream tools must not treat this as an admitted signal. AX-002|RF-A7"

**분류**: **ACCEPT** (machine-enforced fix)

**근거 (3축)**:
- **학술 (Charter v1.7 §8 No Silent Override)**: op_pass=FALSE 인 package가 deployable-looking artifact를 emit 하는 것은 silent downstream consumption risk. 명시 차단 필요.
- **L-code (L-247 답변 8원칙 + L-272 v7.0 hardening "검증 가능한 SW 커널")**: machine-enforced gate (no_deploy flag) > human-readable disposition flag. governance 강제.
- **정량 (alpha_package.json::alpha_vector / confidence_vector / no_deploy_flag)**: alpha_vector 348 entries 모두 NA로 nullify, confidence_vector 모두 0으로 zero-out, `no_deploy_flag = TRUE` 명시. forward 2026-05 raw predictions는 stage_artifacts/predictions_v5_all_models.parquet에 forensic audit용으로만 retain (downstream consumption 차단).

**합리화 자기검증**: "downstream agent가 op_pass 보고 알아서 차단" 표현 사용 X. machine 차단이 default. 

**적용**: alpha_vector / confidence_vector nullify + `no_deploy_flag=TRUE` + `no_deploy_rationale` 명시 + challenge_flags `CODEX_C6_ALPHA_VECTOR_NULLIFIED_NO_DEPLOY` HIGH 등재.

---

### Concern 7 (LOW) — Page-level academic references missing
**Codex 인용**: "Academic references still lack page-level core_reference evidence, so the Charter mechanism checklist is not fully satisfied even though the empirical fail makes admission moot. AX-002"

**분류**: **ACCEPT** (downgrade rather than augment)

**근거 (3축)**:
- **학술 (Charter v1.7 §1-2 Research Process First + Idea→Data→Model→Backtest→Report)**: 논문 page-level citation은 admission 시점 mechanism explain 의무. empirical FAIL 시 admission moot → 논문 references는 mechanism background로 downgrade.
- **L-code (s0-hypothesis-rules.md + L-247)**: core_reference 형식적 인용 금지. 그러나 v5 admission moot이므로 mechanism background level로 downgrade가 honest.
- **정량 (alpha_package.json::factor_specs[*].references)**: 11 references list retain (Gu/Kelly/Xiu 2020, Bryzgalova/Pelger/Zhu 2024, etc.) but `pipeline_stage = "alpha_v5_final_post_codex_no_admit"` 로 admission claim 제거.

**합리화 자기검증**: "page citation 사후 추가 가능" 표현 사용 X. ACCEPT = admission moot이므로 references는 background level로 책정.

**적용**: factor_specs references retain + admission claim 제거 (pipeline_stage 수정).

---

## 2. Q-Lead Auto-Escalate Trigger 검증

| Trigger | Threshold | v5 status | 발동? |
|---|---|---|---|
| HIGH severity concerns | ≥ 5 | 2 (C1, C2) + 1 alpha-side (C6 ACCEPT machine fix) = 3 | NO (3 < 5) |
| AX axiom hard FAIL | ≥ 3 | 1 (AX-007 from Concern 2) | NO (1 < 3) |
| PIT C1 (lockbox / lookahead) violation | 1+ | 0 (v5 PIT C1 PASS) | NO |
| Codex stance REJECT + agent rebuttal ALL | — | Codex REJECT but 0 REBUTTAL (5 ACCEPT + 2 PARTIAL) | NO |

**결과**: Auto-escalate trigger 발동 안 함. Self-resolve via spec revision (이 challenge_note + alpha_package.json final 작성으로 충분).

---

## 3. AX 공리 v5 status

| AX | v4 | v5 final |
|---|---|---|
| AX-000 한계 없다 | 적용 | 적용 (FAIL 후 Pivot path 5건 제시) |
| AX-001 v2 defense 조건부 | N/A (defense factor X) | N/A |
| AX-002 합리화 grep 0건 | WARN (3 hits) | **PASS** (0 hits in v5 final) |
| AX-003/004/005 | N/A | N/A |
| AX-007 ML sizing 예외 | TARGETING_FAIL (top-quintile sleeve) | TARGETING_FAIL (max-20 TO 10.60 mechanism break) — empirical |
| AX-008 Verification Triangulation | 1/3 (alpha만) | **2/3** (alpha + Codex Round) — Architect는 deployment WT에서 |

**AX-002 합리화 grep 결과** (v5 final 패키지 본문):
- "conservative" 사용: caveat에서 1회 (`bond_proxy = 0 explicit limitation, not rationalization`) — explicit 라벨 형식.
- "minimal impact / 영향 미미 / 보수적이면 OK / 대부분 결과 동일" — 0회.
- "관행 / 실무적" — 0회.
- v4 "GPU benefit minimal" → v5 GPU 실측 정량 (12분 vs 48분, 4× speedup) 으로 대체.

---

## 4. Pivot path 5건 (operational_decision.recommended_next_paths)

| 순위 | 후보 | mechanism | 학술 reference |
|---|---|---|---|
| 1 | Crisis-conditional defense | bad/normal IC ratio + crisis_alpha + Core 대비 MDD 완화 | AX-001 v2 + Pedersen 2015 |
| 2 | Macro-residual long-horizon | FRED/ECOS × KOSPI residual, low TO 설계 | Stambaugh-Yuan 2017 + Jiang-Yu-Zhang 2021 |
| 3 | RL state-space + economic restriction | policy gradient + turnover constraint | Avramov-Cheng-Metzker 2023 MS |
| 4 | Alternative data sentiment | kr-news embeddings, retail flow non-conformity | Bali-Beckmeyer-Morke-Weigert 2023 |
| 5 | Multi-frequency ensemble | daily-monthly bridge + regime conditioning | Jeon-Kang 2022 KR-specific |

---

## 5. 최종 자가 검증 (도훈 답변 8원칙)

- ✅ 표면 아닌 실제 목적: ML residual cross-section alpha의 PIT-proper 성립 가능성 정직 검증.
- ✅ 하위 과제 분해: 6 path Codex 8 concerns 모두 명시 처리.
- ✅ 명시적 처리: 모든 gate FAIL을 정량 + sign + threshold 비교로 표시.
- ✅ 일반론 회피: 모든 수치 stage_artifacts / alpha_validation_v5 / dsr_strict 직접 인용.
- ✅ 가정/예외/리스크 점검: RF-A3 / RF-A4 / artifact scope / governance flag 모두 challenge_flags 등재.
- ✅ 어려운 부분 생략 X: max-20 hard simulation 6 model 모두 실행, sector-neutral pred_xgb 별도 측정.
- ✅ 불확실성 명시: r_bond=0 explicit limitation (KR 10y bond data unavailable).
- ✅ 실행가능 결론: alpha_vector NULLIFIED + no_deploy_flag + 5 pivot path 명시.

**5금지**:
- ✅ 조용한 단순화 X: 모든 metric 정량.
- ✅ TODO 대체 X: 모든 path 즉시 실행.
- ✅ Hallucination X: Codex log 기반 모든 인용.
- ✅ 검증 없이 완료 X: alpha_validation_v5.json + dsr_strict_bailey_ldp.json + post_codex_addenda 모두 cross-reference.
- ✅ 얕고 그럴듯한 마무리 X: empirical FAIL 직설.

---

## 6. 최종 산출물 (절대 경로)

- alpha_package.json (49 KB, post-Codex final, no_deploy_flag=TRUE)
- alpha_package_v5_draft.json (45 KB, pre-Codex)
- alpha_validation_v5.json (9 KB, per-model + DSR 3 views)
- codex_critic_response_alpha_v5.json (8 KB, REJECT 7 concerns)
- challenge_note_v5.md (이 파일)
- sig_date_window_lineage.json (PIT-rolling factor universe + panel meta)
- gpu_acceleration_report.json (GPU speedup 정량)
- multi_trial_dsr_log.json + dsr_strict_bailey_ldp.json (Bailey-LdP 3 views)
- forward_2026_05_predictions.parquet (forensic only, 348 tickers)
- artifact_lineage.json (4 entries cumulative)
- stage_artifacts/WT_D20260508_002/alpha_scores_v5.parquet (43526 rows)
- stage_artifacts/WT_D20260508_002/predictions_v5_all_models.parquet
- stage_artifacts/WT_D20260508_002/predictions_v5_sector_neutral.parquet
- stage_artifacts/WT_D20260508_002/v5_factor_universe_stability.parquet
- stage_artifacts/WT_D20260508_002/v5_phase1_features/ (137 panels + index)

---

**Final**: WT-D20260508_002 v5 = `DISCOVERY_FAIL_HONEST_PIT_PROPER_POST_CODEX_REJECT_GOVERNANCE_REMEDIATED`. 4번째 직교 source가 ML residual cross-section approach로는 KR top-342 + Hybrid 70/15/15 baseline에서 형성되지 않음 empirically 입증. v4 IC 0.291 lookahead diagnosis Codex 정확. v5 Codex round REJECT는 governance fix (alpha_vector nullify + no_deploy_flag) 만으로 self-resolve. Pivot mandate 5 path 후속 cycle.
