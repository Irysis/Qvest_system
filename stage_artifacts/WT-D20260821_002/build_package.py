"""alpha_package.json 빌더 — 가설층 자구 승계 + AST v1.1 3층 구조."""
import json

R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/"
MB = R + "qepm/mailbox/worktask/WT-D20260821_002/"
ST = R + "stage_artifacts/WT-D20260821_002/"


def rd(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


H = rd(MB + "alpha_hypothesis.json")
S = H["selected"]
G = rd(ST + "gate_result.json")
V = rd(ST + "verdict_result.json")
P = rd(ST + "step0_provenance.json")
IV = rd(ST + "independent_verify.json")
A2 = rd(ST + "axis2_probe.json")
AS = rd(ST + "alpha_scores_manifest.json")
PA = rd(ST + "pit_align_tight.json")

GEN = {a: "stage_artifacts/fq233_probe0_20260813/%s_score.py" % a
       for a in ("armA", "armB", "armC")}
COL = {"armA": "score", "armB": "q50", "armC": "score"}


def factor(arm):
    pv = P["stored_scores"][arm]
    return {
        "factor_id": "FQ233_%s_rank" % arm,
        "arm": arm,
        "economic_rationale": S["mechanism"]["path"],
        "redundancy_cluster_id": "FQ233_LANE_A_TARGET_FORM",
        "redundancy_note": (
            "3-arm 은 의도적 동일-클러스터다 — 표적 형태만 다르고 패널·피처·학습창·비용이 "
            "동일한 대조군 설계(paired 비교의 전제). 신규 팩터 추가가 아니라 기존 3-arm 의 "
            "소비 형태 재판정이다(Factor Zoo 축소 원칙 ①: validation > discovery)."),
        "ast": {"op": "CS_RANK", "children": [{
            "leaf": "STORED_SCORE",
            "id": "%s_scores" % arm,
            "column": COL[arm],
            "provenance": {
                "store_build_hash": pv["sha256_file"],
                "generator_code_path": GEN[arm],
                "generated_at": pv["mtime"]},
            "production_parity_verified": False,
            "production_parity_note": (
                "정직 false — 본 3-arm 은 production 대응물이 없는 리서치 패널이다"
                "(§7b 는 incumbent base 비교 요건이며 본 라운드는 incumbent 비교를 하지 않는다). "
                "이 패널로 book-marginal/incumbent 대조 금지."),
            "vintage_note": (
                "field_map 미등재 → 보수적 restatement 표시 수용. 저장 아티팩트 자체는 "
                "sha256 고정·재생성 0회이나, 빌드 시점 피처 패널의 vintage 정합은 선행 "
                "PREREG(armA/armB/armC)에서 승계한 성질이며 본 라운드가 재증명하지 않는다 — "
                "확인 불가를 확인 완료로 취급하지 않는다."),
            "embedded_data_through": "2026-07-31"}]}}


pkg = {
    "spec_version": "ast_v1.1",
    "strategy_id": "FQ233_FRAME_WT-D20260821_002",
    "wt_id": "WT-D20260821_002",
    "round_id": "FQ233_FRAME_20260821",
    "produced_by": "alpha-research",
    "produced_at": "2026-08-22",
    "prereg": "qepm/mailbox/worktask/WT-D20260821_002/PREREG_WT002_20260821.md",
    "pit": {
        "sig_date": "2026-07-31",
        "decision_ts": "2026-09-01",
        "note": ("sig_date = 최종 신호 형성일. decision_ts = 그 신호가 소비되는 홀딩월 시작일. "
                 "실측 간격 min 29 / median 32 / max 32 일, 음수·0 건수 0 (C5 충족, 1개월 여유 버퍼)."),
        "alignment_evidence": {
            "method": "종목-월 짝 단위로 frd$Ret_1m 을 RAWDATA 독립 재구성 월수익과 shift 스캔 대조",
            "shift_scan": PA,
            "verdict": "shift=0 에서 cor 0.9728 (중앙 절대차 1.19%p), shift ±1 에서 0.003/0.031 "
                       "— Date 라벨 = 수익 실현월 확정. sig_date 는 그 월 시작보다 29~32일 앞선다."}},
    "hypothesis": {
        "inherited_from": ("qepm/mailbox/worktask/WT-D20260821_002/alpha_hypothesis.json "
                           "(alpha-hypothesis, model_tier=fable, verdict=designed)"),
        "inheritance_rule": (
            "Charter 원칙 8 No Silent Override — mechanism/falsification/regime_scope 는 자구 그대로 "
            "승계. 본 패키지는 재작성하지 않았다. falsification 은 게이트 스키마(list + field_ref)로 "
            "형식만 재포장하고 원문을 falsification_inherited_verbatim 에 보존한다."),
        "hypothesis_title": S["hypothesis_title"],
        "hypothesis_description": S["hypothesis_description"],
        "mechanism": S["mechanism"],
        "regime_scope": S["regime_scope"],
        "falsification_inherited_verbatim": S["falsification"],
        "prereg_stance": S["prereg_stance"]},
    "mechanism": S["mechanism"],
    "regime_scope": S["regime_scope"],
    "falsification": [
        {"axis": "axis1_detection_mechanism",
         "field": "A1_RAWDATA_OHLCVS_daily",
         "observable": ("브레드스·랭크가중 프레임의 paired diff 월 sd 가 top-25 이산 프레임 "
                        "실측 0.043381 의 50% 이하로 감소하는가"),
         "reject_if": "sd 감소율 < 50% → 검출-기전 기각 + 프레임 경로 무효(FRAME_PATH_INVALID)",
         "measured": {"min_sd_ratio_c_vs_a": 0.167496,
                      "min_sd_ratio_b_vs_a": 0.150098,
                      "verdict": "AXIS1_NOT_REJECTED",
                      "note": "sd 83.3~85.0% 감소 — 기각 미발화"}},
        {"axis": "axis2_alpha_mechanism",
         "field": "A1_RAWDATA_OHLCVS_daily",
         "observable": "월내 횡단면 왜도 × diff 연속 상호작용 기울기 (이분 라벨 금지)",
         "reject_if": "|t_b| < 2.0 ∧ 평균 diff 유의 → 알파-기전 기각(효과는 있으나 비대칭 기원 아님)",
         "measured": {
             "c_vs_a": {"monthly_cs_t": -1.9716, "daily_cs_t": -4.2493,
                        "monthly_t_ctrl_dispersion": -1.1134,
                        "joint_monthly_t": A2["c_vs_a"]["joint_monthly_t"],
                        "joint_daily_t": A2["c_vs_a"]["joint_daily_t"]},
             "b_vs_a": {"monthly_cs_t": -4.1683, "daily_cs_t": 0.2234,
                        "monthly_t_ctrl_dispersion": -2.3759,
                        "joint_monthly_t": A2["b_vs_a"]["joint_monthly_t"],
                        "joint_daily_t": A2["b_vs_a"]["joint_daily_t"]},
             "cor_monthly_vs_daily_skew": A2["cor_skew_m_d"],
             "clause_fired": False,
             "verdict": "AXIS2_INCONCLUSIVE_AND_SIGN_CONTRARY",
             "note": (
                 "사전등록 기각절은 '평균 diff 유의' 를 요구하는데 co-primary 평균이 비유의라 "
                 "절이 발화하지 않는다. 그러나 상호작용 자체는 유의하며 부호가 설계 예측과 "
                 "반대다 — 설계는 왜도 양(+) 연속 구간을 holds_in 으로 예측했으나 실측 기울기는 "
                 "음수(왜도 높은 달에 분포-표적이 상대적으로 더 나쁨). 또한 두 왜도 추정기가 "
                 "사실상 무상관(cor -0.011)이라 동일량의 두 추정치가 아니다 — 월간 횡단면 왜도는 "
                 "분산과 0.494 상관이나 일간 파생은 0.096 으로, 서로 다른 양이다.")}},
        {"axis": "axis3_benchmark_invariance",
         "field": "A4_benchmark_kospi200",
         "observable": "co-primary diff 가 arm 간 ret_net 차이라 벤치가 상쇄되는가",
         "reject_if": "벤치 vintage 변동이 diff 로 전이되면 판정이 벤치 개정에 오염",
         "measured": {"bench_drift_detected": "2026-08-01 BM_Ret 0.005474 변동 (step0b)",
                      "transmission_to_diff": 0.0,
                      "note": ("d = ret_net(arm) − ret_net(armA) 는 포트 순수익의 차이므로 벤치가 "
                               "식에 들어가지 않는다 — 벤치 드리프트는 co-primary 판정에 구조적으로 "
                               "전이 불가. PORT_t·active_IR 등 active 기반 병기 지표에만 영향.")}}],
    "factors": [factor("armA"), factor("armB"), factor("armC")],
    "ast": factor("armC")["ast"],
    "measurement_frame": {
        "note": ("★프레임 가중은 검출 장치(canonical_screen_bt 스크리닝 가중)이지 target_weights "
                 "제안이 아니다. 본 패키지는 어떤 weight/공분산도 산출·제안하지 않는다(역할 경계). "
                 "운용 종목수 ≤25 는 Production Constraints 고정 축(INV-7)이며 브레드스 확대는 "
                 "제약 완화 레버가 아니다."),
        "binding_frame": "F3L",
        "ladder_prefixed": ["F1", "F2", "F3L"],
        "weight_rule": "w_i ∝ (N − rank_i), Σw=1, long-only",
        "longshort_excluded": (
            "설계 원안 F3(센터드랭크 Σ|w|=1)는 롱숏 — 도훈 mandate 2026-06-11 에 따라 판정 바인딩 "
            "금지, long-only 사상판 F3L 로 대체. F3 의 paired t 는 산출하지 않았다.")},
    "selection_type": "chain",
    "selection_type_basis": (
        "저장 스코어 소비·재학습 0회·HPO 없음·프레임 선택은 mean-blind MDE 관문 + 사전 고정 사다리·"
        "co-primary 2건 고정(argmax 없음) ⇒ DSR HARD 부적용. DSR 진단치는 병기."),
    "metric_type": "canonical_screen_frame",
    "metric_type_note": (
        "canonical_screen_bt fork(가중 규칙만 교체). forge-authoritative 아님 — graduation HARD "
        "판정 근거로 쓸 수 없다."),
    "results": {
        "binding_frame": "F3L",
        "n_months": 198,
        "coprimary": V["coprimary"],
        "gate_table_mde_annual_pct": dict(
            ("%s|%s" % (r["frame"], r["pair"]), round(100 * r["mde_annual"], 4))
            for r in G["gate_table"]),
        "independent_verification": IV,
        "scale_diagnostic": G["scale_diagnostic"],
        "secondary_rank_slope": V["secondary_rank_slope"],
        "frame_metrics_binding": V["frame_metrics_binding"],
        "frame_metrics_F0": V["frame_metrics_F0"],
        "dsr_diagnostic_n_trials_1": V["dsr_diag_n_trials_1"]},
    "labels": {
        "c_vs_a": "POWERED_NULL_BREADTH_SCOPED",
        "b_vs_a": "POWERED_NULL_BREADTH_SCOPED",
        "scope_statement": (
            "F3L(전 브레드스 랭크가중) 프레임에서 표적 형태 효과 연 3%p 이상 부재. "
            "★top-25 국소 효과는 미결로 잔존하며 본 라운드는 그것을 배제하지 않는다 — "
            "랭크-기울기 진단이 오히려 소비 구간(rank 1~25)에서 분포-표적이 음(-)임을 보인다."),
        "not_claimed": ["자본 자격", "graduation HARD 3종 판정",
                        "브레드스 프레임의 운용 성과", "top-25 에서의 무효과"]},
    "alpha_scores": AS,
    "role_boundary": {"weights_computed": False, "covariance_computed": False,
                      "note": "α̂ 및 그 검출 해상도만. Σ/weight/사전최적화 없음."}}

# ── alpha-style 출력 의무 + 전이 벽 국소화 (post-lock 진단, 판정 비바인딩) ──────
IC = rd(ST + "ic_stats.json")
TP = rd(ST + "transition_probe.json")
LP = rd(ST + "leg_probe.json")

pkg["advisory_rank_ic"] = {
    "severity": "ADVISORY",
    "severity_basis": (
        "measurement-graduation §3 — rank_ic/icir/harvey_t(rank-IC) 는 advisory. "
        "graduation 구속 지표는 forge-authoritative portfolio-alpha t 이며 본 라운드는 그것을 주장하지 않는다."),
    "per_arm": IC["rank_ic"],
    "cross_arm_rank_cor_median": IC["cross_arm_rank_cor_median"],
    "top25_overlap_median": IC["top25_overlap_median"],
    "redundancy_check": (
        "arm 간 월내 스코어 순위상관 중앙값 A~B 0.525 / A~C 0.298 / B~C 0.331, "
        "top-25 편입 중첩 중앙값 0.20 — 전부 0.95 미만이므로 중복 팩터가 아니다. "
        "단 이는 의도된 동일-클러스터 대조군이며 신규 팩터 추가 주장이 아니다."),
    "critical_caveat": (
        "★rank-IC 만 보면 분포-표적이 압도한다(Harvey-t armC 3.85 · armB 3.35 vs armA 0.83 — "
        "앞 둘은 문헌 문턱 2.95 초과). 그러나 이는 **지표 기저 아티팩트**다: rank-IC 는 순위 "
        "함수(Spearman)이고 포트 수익은 평균(선형) 함수라, 순위-표적 학습기를 구조적으로 편든다. "
        "실제로 Pearson IC 로 재면 순서가 뒤집힌다(아래 transition_wall). rank-IC 로 "
        "SUPPORTED 를 선언했다면 거짓 통과였을 것 — Cycle 2 교훈(IC t ≠ portfolio-alpha t)의 재현.")}

pkg["transition_wall_localization"] = {
    "question": "분포-표적의 순위 우위가 raw-return(포트가 실제로 버는 함수) 우위로 전이되는가",
    "measured": TP,
    "finding": (
        "전이되지 않으며, 그 이유가 측정된다. armA(평균 표적): Spearman IC 0.0074 (t 0.83) 인데 "
        "Pearson IC 0.0214 (t 2.14) — 정보가 **순위가 아니라 크기**에 있다. armB(q50 중앙값 표적): "
        "Spearman 0.0299 (t 3.35) 인데 Pearson 0.0154 (t 1.83) — **순서는 잘 매기나 크기를 못 맞춘다**. "
        "armC 는 양쪽 다 강하다(0.0331 t 3.85 / 0.0240 t 2.80). 상하위 10% 스프레드도 같은 방향: "
        "armB 는 중앙값차 t 2.85 인데 평균차 t 1.05 로, **중앙값 표적이 중앙값 스프레드만 벌었다**. "
        "포트 수익은 평균 함수이므로 armB 의 우위는 구성상 회수되지 않는다."),
    "implication": (
        "co-primary null 은 '세 표적이 같은 정보를 담는다' 가 아니라 "
        "'표적마다 다른 함수를 최적화했고, 포트 수익이 쓰는 함수에서는 차이가 연 3%p 미만' 이다. "
        "이것이 표적 형태 라운드에서 **평가 지표를 표적과 같은 함수로 고르면 안 되는** 이유다.")}

pkg["leg_decomposition"] = {
    "basis": "EW-유니버스 평균 대비 초과 (n=198, 플레이스홀더 월 2026-09-01 배제)",
    "dual_basis_caveat": (
        "★이 수치는 **EW-유니버스 기준**이며 cap-w 벤치(KOSPI200) 기준이 아니다. v8.3 dual-basis 규약상 "
        "HARD 판정 권위는 cap-w 이고, 같은 arm 의 cap-w PORT_t 는 F0 에서 armC 0.854 · armA 0.625 로 "
        "문턱(2.95)에 한참 못 미친다. EW 대비 +9~10%p 를 알파 주장으로 읽으면 안 된다 — "
        "EW-유니버스 초과에는 소형주·EW 프리미엄이 섞여 있다."),
    "measured": LP,
    "finding": (
        "armC−armA 격차는 LONG(회수 가능) +0.91%p vs SHORT(공매도 필요, 회수 불가) +1.53%p 로 "
        "**회수 불가능한 다리에 더 크게 실려 있다**. armB 는 전 다리에서 열등(LONG −5.30 · SHORT −2.65). "
        "mechanism.friction 이 알파의 원천으로 지목한 KR 공매도 제약이, 그 알파의 **회수 경로도 동시에 "
        "막는다** — 분포-표적이 하방을 더 잘 식별할수록 long-only 는 그 우위를 덜 가져간다."),
    "caveat": (
        "단 armC 의 LONG/SHORT 격차(+0.91 / +1.53%p)는 **차이 수준에서 유의하지 않다** — "
        "co-primary paired 검정이 그것을 정면으로 시험해 |t| < 2 를 냈다. 방향 표시이지 주장이 아니다.")}

pkg["next_probe"] = [
    {"id": "NP1", "probe": (
        "소비 구간 국소 재판정 — 랭크-기울기가 rank 1~25 에서 분포-표적 음(-)(armC −0.71%p t −1.69 · "
        "armB −0.90%p t −1.87), 26~50 에서 armB |t| 2.20 을 보였다. 브레드스 프레임이 구조적으로 "
        "덮지 못하는 구간이므로, top-25 국소 diff sd 를 낮추는 **다른** 검출 설계(짝지은 대칭차 "
        "per-swap 추정 등)로 별도 라운드."),
     "why": "본 라운드의 powered null 이 명시적으로 배제하지 못한 유일한 구간"},
    {"id": "NP2", "probe": (
        "표적-지표 정합 감사 — Spearman/Pearson 이 arm 서열을 뒤집는다는 실측을 기존 판정들에 소급. "
        "rank-IC 로 선별·기각된 후보 중 평균 함수 기준으로 재평가하면 서열이 바뀌는 건수를 센다."),
     "why": "지표 기저 아티팩트가 과거 선별을 오염시켰을 수 있음 — FQ-237 5-arm 서열 갱신 의무와 직결"},
    {"id": "NP3", "probe": (
        "armC 의 크기-정보 결합 — armC 는 Spearman·Pearson 양쪽에서 armA 이상이다(유일). "
        "armA 대비 격차가 유의하지 않은 것은 검정력이 아니라 **격차 자체가 작기 때문**임을 "
        "co-primary 가 이미 보였으므로, armC 단독의 절대 성과가 아니라 armA 와의 **결합**(직교 성분)에 "
        "잔여가 있는지 별도 축으로."),
     "why": "본 라운드는 대체(A vs C)만 시험했고 결합은 시험하지 않았다"},
    {"id": "NP4", "probe": (
        "플레이스홀더 월 위생 — frd 의 2026-09-01 은 Ret_1m 이 347종목 전부 정확히 0 이며 NA 가 아니다. "
        "`!is.na` 만 거르는 소비자는 이 월을 실데이터로 흡수한다(본 라운드에서 실제로 내 진단 1건이 "
        "그렇게 오염됐고 수리했다). 패널 생산 지점에서 NA 로 바꾸거나 소비자 계약에 sd==0 차단 추가."),
     "why": "결손을 정상값으로 내려앉히는 형태 — 침묵 오염 경로"}]

pkg["labels"]["mechanism_note"] = (
    "설계 mechanism 은 유지하되(재작성 금지) 실측 2건이 그것과 **어긋난다**: ①반증 축 2 의 왜도 "
    "상호작용 부호가 예측과 반대(음) ②격차가 공매도 불가 다리에 더 실림. 두 건 모두 "
    "alpha-hypothesis 재설계 요청 사유로 challenge_note 에 기록했다.")

with open(ST + "alpha_package_draft.json", "w", encoding="utf-8") as f:
    json.dump(pkg, f, ensure_ascii=False, indent=2)
print("draft written:", ST + "alpha_package_draft.json")
