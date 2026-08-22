"""alpha_validation.json — 판정 근거·검증 삼각측량·정직 라벨 집성."""
import json

R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/"
ST = R + "stage_artifacts/WT-D20260821_002/"
MB = R + "qepm/mailbox/worktask/WT-D20260821_002/"


def rd(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


G, L, V = rd(ST + "gate_result.json"), rd(ST + "gate_lock.json"), rd(ST + "verdict_result.json")
P, IV, A2 = rd(ST + "step0_provenance.json"), rd(ST + "independent_verify.json"), rd(ST + "axis2_probe.json")
IC, TP, LP = rd(ST + "ic_stats.json"), rd(ST + "transition_probe.json"), rd(ST + "leg_probe.json")
PA, AS = rd(ST + "pit_align_tight.json"), rd(ST + "alpha_scores_manifest.json")

gate_rows = {}
for r in G["gate_table"]:
    gate_rows.setdefault(r["frame"], {})[r["pair"]] = {
        "diff_sd_monthly": r["diff_sd_monthly"],
        "nw_inflation_measured": r["nw_inflation"],
        "nw_inflation_source": r["nw_inflation_source"],
        "mde_annual_pct": round(100 * r["mde_annual"], 4),
        "sd_reduction_pct_vs_F0": round(r["sd_reduction_pct"], 2),
        "gate_pass": r["gate_pass"]}

val = {
 "wt_id": "WT-D20260821_002", "round_id": "FQ233_FRAME_20260821",
 "validated_by": "alpha-research", "validated_at": "2026-08-22",
 "verdict": {
   "binding_frame": "F3L",
   "labels": {"c_vs_a": "POWERED_NULL_BREADTH_SCOPED", "b_vs_a": "POWERED_NULL_BREADTH_SCOPED"},
   "scope": ("F3L 전 브레드스 랭크가중 프레임에서 표적 형태 효과 연 3%p 이상 부재. "
             "top-25 국소 효과는 미결 잔존 — 랭크-기울기가 소비 구간에서 오히려 음(-) 방향."),
   "not_claimed": ["자본 자격", "graduation HARD 3종", "브레드스 프레임 운용 성과",
                   "top-25 에서의 무효과", "EW 대비 초과의 알파 해석"]},

 "order_enforcement": {
   "rule": "PREREG §3 — sd/MDE 관문 먼저, paired t 나중. t 를 보고 프레임 선택 시 sweep + DSR HARD.",
   "evidence_chain": [
     {"step": "gate.R (mean-blind)", "finished_at": G["finished_at"],
      "source_audit": ("소스 실검 — sd(d) · nw_inflation_measured(d) · required_effect(series=d) 만 존재. "
                       "mean/t 연산 부재, arm 성과량은 metrics=FALSE 로 우회.")},
     {"step": "gate_lock.json", "locked_at": L["locked_at"],
      "binding_frame": L["binding_frame"], "rule": L["binding_rule_applied"]},
     {"step": "verdict.R (paired t)", "started_at": V["started_at"], "finished_at": V["finished_at"]}],
   "verified_by_this_session": ("타임스탬프 단조성 확인: 관문 종료 < 잠금 < 판정 시작. "
                                "선택 규칙이 성과 무관 사전 고정 사다리라 chain 유지."),
   "deviation": {
     "what": "본 세션이 탈락 프레임 F1·F2 의 paired 평균·t 를 산출(independent_verify.R)",
     "prereg_clause": "§3 — 탈락 프레임의 평균·t 를 산출하지 않는다",
     "classification": "postlock_deviation_diagnostic",
     "contamination_possible": False,
     "why": ("잠금·판정이 모두 선행 세션(2026-08-21)에 완료·불변 기록됐고 본 산출은 2026-08-22 다. "
             "프레임을 고를 수 있는 시점이 아니었고 어떤 라벨도 바뀌지 않는다(전부 |t| < 2)."),
     "sweep_reclassification": False,
     "disclosed_in": "challenge_note.md C1"}},

 "power_gate": {"mde_bar_annual_pct": 3.0, "ladder_prefixed": ["F1", "F2", "F3L"],
                "by_frame": gate_rows,
                "binding_selection": "F1·F2 는 co-primary 양쪽 MDE > 3%p 로 FRAME_REJECTED_UNDERPOWERED"},

 "coprimary": V["coprimary"],

 "independent_verification": {
   "method": "NW lag-3 t 를 3구현으로 교차 산출",
   "implementations": ["자체 Bartlett 커널(independent_verify.R)", "sandwich::NeweyWest", "verdict.R::nw_t"],
   "F3L_c_vs_a": {"verdict_r": V["coprimary"]["c_vs_a"]["nw3_t"],
                  "independent": IV["F3L|c_vs_a"]["t_nw3_indep"],
                  "sandwich": IV["F3L|c_vs_a"]["t_nw3_sandwich"], "agree": True},
   "F3L_b_vs_a": {"verdict_r": V["coprimary"]["b_vs_a"]["nw3_t"],
                  "independent": IV["F3L|b_vs_a"]["t_nw3_indep"],
                  "sandwich": IV["F3L|b_vs_a"]["t_nw3_sandwich"], "agree": True},
   "scale_invariance_check": {
     "note": ("절대 %p 문턱은 스케일 의존적이므로 스케일 불변량(t)으로 교차 확인. "
              "사다리 전 구간에서 |t| < 2 — 무차이 결론이 프레임 선택과 무관하게 성립."),
     "t_across_ladder": {k: IV[k]["t_nw3_indep"] for k in IV},
     "effect_vs_noise_deflation": {
       "c_vs_a": {"sd_ratio_F3L_over_F0": 0.167496, "mean_ratio_F3L_over_F0": 1.5185,
                  "reading": "효과가 오히려 커져 t 개선(0.088 → 0.820)"},
       "b_vs_a": {"sd_ratio_F3L_over_F0": 0.150098, "mean_ratio_F3L_over_F0": 0.1073,
                  "reading": ("효과가 잡음보다 더 축소 → t 악화(−1.247 → −1.059). "
                              "이 쌍에서 관문 통과는 판별력 향상이 아니다 — challenge_note C2.")}}}},

 "falsification_axes": {
   "axis1_detection": {"rule": "diff sd 가 F0 의 50% 이하로 감소", "measured_reduction_pct": [83.25, 84.99],
                       "verdict": "AXIS1_NOT_REJECTED", "frame_path_invalid_fired": False},
   "axis2_alpha_mechanism": {
     "design_prediction": "왜도 양(+) 연속 구간이 holds_in — 효과가 왜도와 함께 커져야 함",
     "measured_slope_sign": "negative (예측과 반대)",
     "detail": A2,
     "monthly_vs_daily_skew_cor": A2["cor_skew_m_d"],
     "verdict": "AXIS2_INCONCLUSIVE_AND_SIGN_CONTRARY",
     "reject_clause_fired": False,
     "reject_clause_reason": "절이 '평균 diff 유의' 를 요구하는데 co-primary 평균이 비유의 — 사후 완화 금지",
     "redesign_requested": True}},

 "advisory_metrics": {
   "severity": "ADVISORY (measurement-graduation §3)",
   "rank_ic": IC["rank_ic"], "cross_arm_rank_cor": IC["cross_arm_rank_cor_median"],
   "transition_probe": TP, "leg_decomposition": LP,
   "critical_finding": ("rank-IC Harvey-t 가 armC 3.85 · armB 3.35 로 문헌 문턱 2.95 를 넘지만, "
                        "이는 지표 기저 아티팩트다 — Spearman 은 순위 함수라 순위-표적을 편든다. "
                        "Pearson 으로 재면 armA 가 armB 를 앞선다(2.14 vs 1.83). "
                        "rank-IC 를 판정에 쓰면 거짓 SUPPORTED — challenge_note C9."),
   "binding_on_verdict": False},

 "pit_validation": {
   "c5_signal_timing": {"gap_days_min": 29, "gap_days_median": 32, "gap_days_max": 32,
                        "n_nonpositive": 0, "n_months": 199, "pass": True,
                        "note": "신호가 홀딩월 시작보다 항상 앞선다 — 동월 아니라 1개월 여유 버퍼"},
   "alignment_independent": {"method": "종목-월 짝 단위 shift 스캔 vs RAWDATA 독립 재구성",
                             "scan": PA, "pass": True,
                             "note": "shift 0 에서 cor 0.9728, ±1 에서 0.003/0.031"},
   "ast_static": {"tool": "02_Infrastructure/ast/ast_verify.py", "verdict": "WARN_RESTATEMENT",
                  "violations": 0, "contract_failures": 0,
                  "warn_reason": ("STORED_SCORE 가 field_map 미등재 → 보수적 restatement 표시. "
                                  "확인 불가를 확인 완료로 취급하지 않기 위해 vintage_available 을 "
                                  "선언하지 않았다(의도된 플래그).")},
   "ast_spec_gate": {"result": "hard 게이트 통과 (advisory only)", "blocked": False},
   "stored_panel_lookahead_rebuttal": (
     "저장 패널 동월 vintage 선례에 대한 반박은 가정이 아니라 실측이다 — C5 간격 실측 + 정렬 "
     "독립 검증 + embedded_data_through ≤ decision_ts−1 기계 확인. 또한 본 라운드는 incumbent "
     "비교를 하지 않으며 production_parity_verified=false 로 §7b 경로를 스스로 차단했다.")},

 "provenance": {"stored_scores": P["stored_scores"],
                "keyset_identical_across_arms": P["keyset_identical_across_arms"],
                "retrain_count": 0,
                "armA_reproduction_drift": {
                  "max_abs_reldiff": P["armA_reproduction"]["max_abs_reldiff"],
                  "resolved": True,
                  "attribution": ("ret_net 은 198/198 bit-parity(max abs diff 0). 차이는 벤치 1개월"
                                  "(2026-08-01) 개정에만 기인하며, co-primary diff 는 벤치가 소거되므로 "
                                  "판정량에 구조적으로 도달 불가 — challenge_note C7.")},
                "alpha_scores_emitted": AS},

 "selection_type": {"value": "chain",
   "basis": ("저장 스코어 소비 · 재학습 0회 · HPO 없음 · 프레임 선택은 mean-blind 관문 + 사전 고정 "
             "사다리 · co-primary 2건 고정(argmax 없음)"),
   "dsr_hard_applicable": False,
   "dsr_diagnostic_n_trials_1": V["dsr_diag_n_trials_1"]},

 "constraint_compliance": {
   "weights_computed": False, "covariance_computed": False,
   "max_names_25_respected": ("판정 대상 아님 — F3L 은 검출 장치이며 운용 후보를 산출하지 않는다. "
                              "25종 상한은 고정 축(INV-7)이고 브레드스 확대를 완화 레버로 제시하지 않는다."),
   "long_only": True, "cost_bps_oneway": 15, "longshort_used_in_verdict": False,
   "ax001_defense_scope": {"applicable": False,
     "reason": "detected_family 가 defense 아님 — 표적 형태(measurement_form) 축. 조건부 평가 요건 미해당."}},

 "triangulation_AX008": {
   "self_adversarial": {"status": "PASS", "concerns": 11,
                        "breakdown": {"ACCEPT": 5, "PARTIAL": 4, "REBUTTAL": 2},
                        "artifact": "qepm/mailbox/worktask/WT-D20260821_002/challenge_note.md"},
   "independent_recomputation": {"status": "PASS", "detail": "NW3 t 3구현 일치"},
   "machine_gate": {"status": "PASS", "detail": "ast_verify violations 0 / ast_spec_gate 비차단"},
   "forge": {"status": "NOT_INVOKED", "reason": "자본 판정 없음 — forge-authoritative 지표 미주장"},
   "result": "3-source 중 3 PASS (2/3 요건 충족)"},

 "escalation": {"auto_trigger_fired": False,
   "high_severity_count": 4, "axiom_hard_fail": 0, "pit_c1_violation": False,
   "manual_report_items": [
     "alpha-hypothesis 재설계 요청 2건 (축2 부호 반대 · 다리 비대칭) — 설계 미수정, 요청만",
     "PREREG 이탈 1건 (탈락 프레임 t 산출, 선택 오염 불가)",
     "C9 파급 — rank-IC 기반 과거 선별에 소급 감사 필요(NP2), FQ-237 서열 인용 의무와 직결"]},

 "ledger_update_required": {
   "note": "★본 에이전트는 큐·원장을 수정하지 않았다(mandate: 큐·원장 수정 금지). 아래는 Q-Lead 실행 항목.",
   "items": [
     {"target": "06_Registry/alpha_frontier_queue.json FQ-233",
      "action": ("status 를 armABC_done__lane_underpowered_labeled → "
                 "breadth_frame_powered_null__top25_local_open 으로 갱신. next_action ① "
                 "(해상도 개선 설계)은 본 라운드로 소비 완료 — NP1(top-25 국소 재판정)으로 대체.")},
     {"target": "FQ-237", "action": "5-arm 서열 근거 갱신 + C9(rank-IC 기저 아티팩트) 반영 — 서열이 rank-IC 기반이면 재산정 대상"},
     {"target": "hypothesis_index / L-code",
      "action": "본 라운드 L-code 발행 후 corpus 수확 + `Rscript 02_Infrastructure/tools/hypothesis_index.R build` (build 인자 필수)"},
     {"target": "06_Registry/layer_bottleneck_map.md",
      "action": "alpha 계층 행 갱신 — 병목이 '검출 해상도'가 아니라 'IC→PORT 전이(표적-지표 함수 불일치)'로 국소화됨"}]},

 "next_probe_count": 4,
 "artifacts": {
   "alpha_package": "qepm/mailbox/worktask/WT-D20260821_002/alpha_package.json",
   "challenge_note": "qepm/mailbox/worktask/WT-D20260821_002/challenge_note.md",
   "alpha_scores": "stage_artifacts/WT-D20260821_002/alpha_scores.parquet",
   "gate": "stage_artifacts/WT-D20260821_002/gate_result.json",
   "gate_lock": "stage_artifacts/WT-D20260821_002/gate_lock.json",
   "verdict": "stage_artifacts/WT-D20260821_002/verdict_result.json",
   "independent_verify": "stage_artifacts/WT-D20260821_002/independent_verify.json",
   "pit_align": "stage_artifacts/WT-D20260821_002/pit_align_tight.json",
   "ic_stats": "stage_artifacts/WT-D20260821_002/ic_stats.json",
   "transition_probe": "stage_artifacts/WT-D20260821_002/transition_probe.json",
   "leg_probe": "stage_artifacts/WT-D20260821_002/leg_probe.json",
   "axis2_probe": "stage_artifacts/WT-D20260821_002/axis2_probe.json"}}

with open(ST + "alpha_validation.json", "w", encoding="utf-8") as f:
    json.dump(val, f, ensure_ascii=False, indent=2)
print("written:", ST + "alpha_validation.json")
