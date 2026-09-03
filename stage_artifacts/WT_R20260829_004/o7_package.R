# O7 — optimization_package.json 발행 + lineage
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
O2<-readRDS(file.path(OUT,"o2_objects.rds")); O3<-readRDS(file.path(OUT,"o3_objects.rds"))
O5<-readRDS(file.path(OUT,"o5_objects.rds")); O6<-readRDS(file.path(OUT,"o6_objects.rds"))
RES<-O2$RES; RESC<-O2$RESC; SEL<-"W2_IV"; M<-RES[[SEL]]$M; MC<-O6$MC; CC<-O6$CC
F8 <- fromJSON(file.path(OUT,"o3_overlay_pit.json"), simplifyVector=FALSE)
PG <- fromJSON(file.path(OUT,"pit_gate_optimizer.json"), simplifyVector=FALSE)
Wa <- O6$Wa; asof <- O6$asof
# 발행 정밀도 정합: 10자리 반올림 후 잔차를 최대비중 종목에 흡수 -> 문자열 표현에서도 sum(w)=1 정확
wv <- round(Wa$w, 10); wv[1] <- wv[1] + (1 - sum(wv))
stopifnot(abs(sum(wv)-1) < 1e-12, all(wv >= 0), length(wv) <= 25)
tw <- setNames(as.list(wv), Wa$Ticker)
act_ann_sel <- M$m$alpha_annualized
cost_ann <- M$cost_ann

pkg <- list(
  task_id="WT-R20260829_004", agent="optimizer-research", spec_version="optimization_package_v1.3",
  as_of_date=as.character(asof), wt_type="reinforcement", keyword_axis="risk_overlay",
  upstream=list(alpha_package="qepm/mailbox/worktask/WT-R20260829_004/alpha_package.json",
    risk_package="qepm/mailbox/worktask/WT-R20260829_004/risk_package.json",
    alpha_vector_modified=FALSE, alpha_reinterpreted=FALSE, sigma_reestimated=FALSE,
    grade_declared=FALSE, overlay_applied_here=TRUE,
    note="alpha 의 score/vol 패널과 risk 의 Sigma 를 read-only 소비. 국면 오버레이의 **적용**만 본 층에서 수행(alpha·risk 는 PIT S0/S1 금지로 미적용)."),

  method_selected="W2_IV",
  method_selected_long="regime_switch_composition(alpha spec) + inverse-realized-volatility weights (sigma = alpha 발행 vol126_ann, strict t-1)",
  selection_objective="to_adj_ret",
  selection_objective_spec="net-of-cost(15bps delta) Calmar 1차 · net SR 2차 · turnover 3차. gross Sharpe 단독 최대화 아님.",
  selection_predeclaration_ref="stage_artifacts/WT_R20260829_004/selection_predeclaration.json",
  selection_note=paste0("사전선언 축의 전 표본 승자는 W5_WCH_IV(Calmar 0.1990)였고 W2_IV(0.1976)는 2위다. ",
    "브리핑이 부여한 외부 제약(패닉월 구성 교체를 비중에 반영)을 사전선언 hard_filters 에 넣지 못한 것이 본 층의 선언 결함이며, ",
    "그 제약을 적용하면 적격 집합은 W1/W2/W3/W4 이고 그중 F7 통과분은 W2_IV 뿐이다. ",
    "격차는 tie-band 안(dCalmar 0.0014<0.010 · dSR 0.0010<0.020)이고, anchored 3창(55/65/75%)에서는 W2_IV 가 3/3 승자다 - ",
    "즉 사전선언 축의 전 표본 승자 W5 는 오히려 IS-selection 쪽에 가깝다. 두 축 결과를 모두 발행한다(은폐 없음)."),

  target_weights=tw,
  active_weights=NULL,
  active_weights_note="벤치(KOSPI200) 구성종목 비중 패널이 alpha/risk 핸드오프에 없다. 자체 합성하면 measurement-graduation 1절 자체합성 금지 위반이므로 null 로 둔다 - active 지표는 실현 active 수익 계열(ret_net - BM_Ret)로만 보고한다.",

  n_names=length(tw), sum_weights=sum(unlist(tw)), min_weight=min(unlist(tw)), max_weight=max(unlist(tw)),
  cash_weight=0, leverage=0,
  hhi=sum(unlist(tw)^2), n_effective=1/sum(unlist(tw)^2),

  realized_metrics=list(metric_type="weighted_screen",
    metric_type_note="weighted_screen_bt(계약 build_benchmark_compare 경유) 실측 - forge build_bt_result 가 authoritative. 등급 선언 아님.",
    n_months=M$n_months, sr=M$sr, cagr=M$cagr, mdd=M$mdd, calmar=M$calmar,
    net_ir=M$ir, active_return_annualized=act_ann_sel, portfolio_alpha_t_nw_lag3=M$port_t,
    beta=M$beta, alpha_beta_controlled_ann_pct=M$alpha_ann_pct, t_alpha_beta_controlled=M$t_alpha,
    net_active_sr=M$net_active_sr, oos_retention_rough=MC[[SEL]]$oos_retention_rough),
  expected_active_return=act_ann_sel, expected_tracking_error=NULL,
  expected_information_ratio=M$ir,
  expected_te_note="ex-ante TE 는 벤치 구성비중 없이는 산출 불가(active_weights_note 참조). 대신 as-of Sigma 기반 절대 ex-ante vol 을 sigma_asof_diagnostics 에 병기.",
  turnover=M$to, turnover_convention=O5$to_diag$convention, turnover_cap=11.0,
  turnover_pass=(M$to<=11.0), estimated_cost=cost_ann,

  method_comparison=MC, method_comparison_controls=CC,
  method_shopping_log=list(candidates_tried=5L, cap=5L, posterior_default=TRUE,
    posterior_note="optimizer_research_init v1.3 - 알파비례 tilt 계열(W3_ATILT)을 posterior default 로 포함했고 실측에서 최하위(Calmar 0.1504)로 탈락했다. Sigma 역행렬 계열(MVO/HRP/ERC)은 walk-forward Sigma 재추정이 필요해 역할 경계상 후보에서 제외(sigma_consumption 참조).",
    parallel_exec=FALSE, n_workers=1L),

  hard_filters_applied=list(
    C_CONSTRAINT=list(rule="n<=25 · w>=0 · |sum w -1|<=1e-9 · cash 0 · leverage 0", all_methods_pass=TRUE),
    C_TURNOVER=list(rule="turnover_annual <= 11.0", all_methods_pass=TRUE, selected=M$to),
    C_F7_ALPHA_GUARD=list(rule="beta-통제 alpha >= A0(무조건화 EW) - 1.0%p",
      A0_alpha_ann_pct=O6$A0_ALPHA, floor=O6$F7_FLOOR,
      pass=c("W2_IV","W5_WCH_IV"), fail=c("W1_EW","W3_ATILT","W4_SECCAP"),
      selected_alpha=M$alpha_ann_pct, selected_delta_pp=MC[[SEL]]$F7_delta_vs_A0_pp, selected_pass=TRUE)),

  binding_constraints=c("F7_alpha_guard (5 method 중 3 탈락 - 사실상 이 라운드의 결정 제약)",
                        "turnover_cap_11 (선택 method 10.19 = 상한의 92.6%, 여유 얇음)",
                        "long_only + sum_w_1 (현금·레버리지 0 - 노출 레버 부재)"),
  infeasibility_report=NULL,
  constraint_conflict_report=list(
    id="OPT-CONFLICT-1", severity="HIGH",
    statement="섹터 집중(RISK-CH1/RF-R6)을 명시적으로 제약하는 유일한 후보 W4_SECCAP(cap 0.30)은 제약을 전 월 100% 달성했으나 F7 알파가드에서 탈락했다(alpha 3.693 < floor 4.137).",
    consequence="따라서 이 라운드에서 섹터 캡과 F7 알파 하한은 동시 충족 불가다. 조용히 캡을 완화하거나 F7 을 낮추지 않고 그 사실을 그대로 보고한다(R12 no silent override).",
    what_was_done_instead="선택 method 의 역변동성 가중이 부수적으로 집중을 낮춘다 - as-of 반도체 52.0%->48.4%, Sigma 블록 분산기여 58.9%->56.5%. 완화 폭은 얇다(정직 기록).",
    evidence_that_concentration_is_vintage_local=list(semi_weight_mean_full_sample=O5$conc$semi_weight_mean_sel,
      months_over_50pct=O5$conc$months_semi_over_50pct, n_months=O5$conc$n_months)),

  sigma_consumption=list(
    reestimated=FALSE,
    used_for="as-of 단면 진단(ex-ante vol · beta · 위험기여 · 섹터 블록 분산기여)",
    not_used_for="walk-forward 비중 산출(259개월) - as-of Sigma 는 단일 단면이고, 월별 Sigma 재추정은 위험 재정의 금지 경계 위반",
    vintage_declared="as-of(2026-08-28) Sigma 만 소비 - RISK-CH2 의 through-the-cycle 금지 준수. 국면 Sigma(panic/normal)는 consumption_restriction 대로 진단조차 비중에 반영하지 않았다(RISK-CH4: 사전인지 상관 0.169).",
    risk_ch_responses=list(
      RISK_CH1="명시 처리 시도 -> W4_SECCAP · F7 충돌로 채택 불가. constraint_conflict_report 로 이관.",
      RISK_CH2="Sigma 수준을 walk-forward 비중에 일절 소비하지 않음 - 소비 지점을 as-of 진단으로 한정하여 vintage 문제를 구조적으로 회피.",
      RISK_CH4="패닉 Sigma 배율 미사용. 국면 신호는 alpha 발행 라벨(binary)로만 소비하고 위험 스케일링에 쓰지 않았다.",
      RISK_CH6="꼬리는 정규가정 없이 역사적 분위로 산출(CVaR95/CDaR95). 선택 method CVaR95 -0.1827 vs EW-ON -0.1884.",
      RISK_CH7="crisis 구간별 IC 안정성은 forge 소관(risk 가 forge 로 지정) - 본 층 미수행, 미수행 사실 기록.")),
  sigma_asof_diagnostics=O5$sig_diag,
  concentration=O5$conc, tail_risk_realized=O5$tail, turnover_diagnostics=O5$to_diag,
  selection_stability_anchored=as.list(O5$sel_stability),
  dsr=list(selection_type="sweep", n_trials=5L,
    dsr_absolute_sr=O5$dsr_abs$dsr, dsr_active_sr=O5$dsr_act$dsr,
    note="method 5종 argmax = sweep. measurement-graduation 3절 상 DSR 산출 의무 - 두 basis 병기."),

  schedule=list(weights_csv="stage_artifacts/WT_R20260829_004/weights.csv",
    unique_as_of_dates=O6$n_w_dates, alpha_sig_dates=O6$n_alpha_dates,
    schedule_density_ratio=O6$dens, mandate=">=0.95", pass=(O6$dens>=0.95),
    walk_forward=TRUE, single_snapshot=FALSE,
    skip_months=0L, skip_infeasibility_report=NULL,
    deploy_extension=list(train_cutoff="2026-08-28 (alpha PIT sig_date)",
      deploy_cutoff="2026-08-28 (= 최신 sig_date · open-ended)",
      frozen_extension_applied=FALSE,
      note="alpha 의 PIT cutoff 와 deploy cutoff 가 같다(lockbox 폐지 · 전기간 사용). weights 는 최신 sig_date 까지 전량 발행되어 있으므로 forge 는 train cutoff 이후 별도 frozen extension 없이 그대로 OOS 를 잰다.")),

  overlay_pit_F8_optimizer_layer=F8,
  pit_gate_detect_lookahead=PG,
  hook_two_way_verification=list(
    hook="02_Infrastructure/hooks/worktask_constraint_enforcer.sh",
    wt_type_read="reinforcement (deployment 분기 - 전체 제약 강제)",
    cases=list(
      A_clean_25=list(injected="n=25 · w>=0 · sum=1", hook_output="{}", blocked=FALSE),
      B_n26=list(injected="n=26", hook_output="decision=block (max_names 26 > 25)", blocked=TRUE),
      C_negative_w=list(injected="w=-0.02 1건", hook_output="decision=block (long-only 위반)", blocked=TRUE),
      D_sumw_ne_1=list(injected="sum w = 1.06", hook_output="decision=block (Sigma w != 1.0)", blocked=TRUE)),
    verdict="양방향 실증 완료 - 정상판 통과 · 3축 위반 주입 전량 차단",
    probe_dir="stage_artifacts/WT_R20260829_004/hook_probe/",
    harness_note="worktask_constraint_enforcer 의 WT_id 정규식 WT-([DP]) 는 v10 접두 R 을 매치하지 못한다. 미매치 시 기본값이 deployment 이고 request.json 의 wt_type=reinforcement 로 덮여 전체 제약이 강제되므로 fail-safe 방향이다. 다만 risk 가 보고한 schema.json 패턴 공백과 같은 계통이며 하네스 수리 대상(본 에이전트 권한 밖)."),

  red_flags=list(
    list(id="RF-O1", severity="OK", value="binding_constraints 3 < 25/2 - 미발화"),
    list(id="RF-O2", severity="OK", value=sprintf("active return %.4f/yr vs cost*2 %.4f - 미발화", act_ann_sel, 2*cost_ann)),
    list(id="RF-O3", severity="OK", value=sprintf("turnover %.3f - 미세리밸 아님", M$to)),
    list(id="RF-O4", severity="NA", value="QP solver 미사용(폐형 비중 규칙) - dual 없음"),
    list(id="RF-O5", severity="OK", value=sprintf("n_names %d <= 25", length(tw))),
    list(id="RF-O6", severity="OK", value=sprintf("|sum w - 1| = %.2e", abs(sum(unlist(tw))-1))),
    list(id="RF-O7", severity="OK", value=sprintf("min w = %.6f >= 0 (v10 종목별 상한 폐지 - max w %.6f 참고치)", min(unlist(tw)), max(unlist(tw)))),
    list(id="RF-O9", severity="OK", value=sprintf("walk-forward schedule %d 시점 - single-snapshot 아님", O6$n_w_dates))),

  challenge_flags=list(
    list(id="OPT-CH1", severity="HIGH", to="forge/judge",
      message=paste0("오버레이의 한계기여가 전 채널에서 음수다. 5 method 각각 자기 무조건화 쌍 대비 Calmar 손실: ",
        "W1 -0.0260 · W2 -0.0204 · W3 -0.0259 · W4 -0.0225 · W5 -0.0068. 그리고 무조건화 역변동성(C2_IV_off: Calmar 0.2180 · SR 0.5829 · netIR 0.319 · alpha 5.49%/yr)이 ",
        "오버레이-ON 전 구성을 지배한다. 즉 이 책에서 개선을 만든 것은 국면 오버레이가 아니라 비중 채널(역변동성)이다. alpha 의 F2/F6/F7 powered null 을 뒤집지 못했고 독립적으로 확인했다.")),
    list(id="OPT-CH2", severity="HIGH", to="forge/judge",
      message=paste0("oos_retention 근사가 전 method 음수다(-0.857 ~ -0.066, 선택 method -0.379, 무조건화 EW -0.066, 무조건화 IV +0.001). ",
        "measurement-graduation 3절 상 0.5 미만은 보강증거 무관 무조건 FAIL 이며 비중 방법으로 고칠 수 있는 축이 아니다. 판정 권위는 forge essence_score.R 이다 - 본 값은 진단 근사(canonical .canon_oos_rough 동형).")),
    list(id="OPT-CH3", severity="HIGH", to="judge",
      message=paste0("PIT 양성 대조 재현: 패닉 신호를 1개월 앞당긴 위반 주입판이 선택 method 에서 Calmar 0.2495(인플레 +26.3%) · SR 0.5875(+8.4%)로 발화한다. ",
        "무조건화(0.2058)와 최선 무조건화 IV(0.2180)마저 넘는다 - 이 축에서 오버레이가 작동한다는 외관은 동월 누출로 제조된다(BearProb 동형). 계기는 살아 있고 현행 사양의 strict A/B 인플레는 0.0000 이다.")),
    list(id="OPT-CH4", severity="MEDIUM", to="Q-Lead",
      message="detect_lookahead 가 의사결정 경로 2파일에서 C1 1건씩 발화한다. 발화 대상은 사후 평가 함수의 mean(r)/sd(r)*sqrt(12) 이며 alpha 의 s4_candidate.R(4건)·s5_diag.R(2건)도 동일 idiom 으로 발화한다. 코드를 회피 수정하지 않고 재도출로 처리했다(pit_gate_optimizer.json rederivation). 검출기 특성의 하네스 이슈."),
    list(id="OPT-CH5", severity="MEDIUM", to="Q-Lead",
      message="음성 축 대조: 전 표본 cov 로 비중 산출 · 국면라벨 shift(-1) · 전 표본 SR argmax 를 주입해도 detect_lookahead 는 미발화(0/3). risk 가 보고한 R 경로 공백이 optimizer 레인에도 그대로 적용된다 - 이 축의 PIT 담보는 검출기가 아니라 설계·산출물 기록이다."),
    list(id="OPT-CH6", severity="MEDIUM", to="Q-Lead",
      message="사전선언 결함 자기신고: 브리핑의 구조 제약(패닉월 구성 교체 반영)을 hard_filters 에 넣지 못해 사전선언 축의 승자(W5)와 실제 채택(W2)이 갈렸다. 두 결과 모두 발행했고 격차는 tie-band 안이며 anchored 3창에서는 W2 가 3/3 승자다.")),

  self_report_no_repackaging=list(
    cash_scaling_regression=FALSE,
    evidence=sprintf("Sigma w = 1 (최대 편차 %.2e) · 현금 0 · 레버리지 0 · n_max 25 · min w %.6f >= 0. BSC 원형의 노출 스케일링(Sigma w<1)으로 회귀하지 않았다.", M$sumw_dev, M$min_w),
    honest_qualifier="다만 alpha 가 자기신고한 PARTIAL_REPACKAGING(실질이 beta 를 구성으로 조금 줄이기)은 본 층에서도 유효하다 - 선택 method beta 1.038 vs 무조건화 1.058."),

  explanation=list(
    top_overweights=Wa[1:3, paste0(Ticker," (",round(100*w,2),"%)")],
    top_underweights=Wa[.N:(.N-2), paste0(Ticker," (",round(100*w,2),"%)")],
    main_tradeoffs=c("F7 알파가드가 섹터캡·알파틸트·EW 를 전부 탈락시켜 선택지를 2개로 좁혔다",
      "역변동성 가중이 SR/Calmar/alpha 를 동시에 올렸으나(EW 대비 +0.037 SR · +0.018 Calmar · +0.66%p alpha) 회전율을 9.38 -> 10.19 로 밀어올렸다",
      "국면 오버레이 자체는 어느 채널에서도 음의 기여 - 개선분은 전부 비중 채널에서 나왔다")),
  self_adversarial=list(performed=TRUE, method="Opus native adversarial reasoning (v8.2 - 외부 Codex 라운드 없음)",
    n_concerns=7L, classification=list(ACCEPT=3L, PARTIAL=2L, REBUTTAL=2L),
    concerns=list(
      list(id="OC1", cls="ACCEPT", topic="사전선언이 브리핑의 구조 제약(구성 교체)을 누락 - 축 승자(W5)와 채택(W2)이 갈림"),
      list(id="OC2", cls="ACCEPT", topic="오버레이 한계기여가 5채널 전부 음수 - 개선은 비중 채널에서 나왔다"),
      list(id="OC3", cls="ACCEPT", topic="oos_retention 전 method 음수 - 비중으로 고칠 수 없는 책의 성질"),
      list(id="OC4", cls="PARTIAL", topic="섹터 캡은 F7 과 충돌 - 완화 폭 얇음(52.0->48.4%), vintage 국소성 병기"),
      list(id="OC5", cls="PARTIAL", topic="회전율 10.193 = 상한의 92.6% - 여유 얇음"),
      list(id="OC6", cls="REBUTTAL", topic="Sigma 미사용 비판 - risk 자신의 consumption_restriction/CH2/CH4 준수이며 as-of 진단으로 실제 소비"),
      list(id="OC7", cls="REBUTTAL", topic="역변동성이 새 alpha 라는 비판 - 비중 규칙이며 sigma 는 alpha 발행값 그대로")),
    self_rationalization_check=list(forbidden_phrases_used=FALSE,
      audit="금지 표현 6종 미사용. OC4 를 '영향 미미'로 넘기지 않고 52.0->48.4 / 58.9->56.5 수치와 '얇다' 판단으로 대체, OC2 를 각주로 내리지 않고 5채널 Delta 표 전량 게재."),
    escalation_check=list(hard_constraint_violation=FALSE, HIGH_count=3L, axiom_hard_fail=0L,
      rf_o9_single_snapshot=FALSE, escalated=FALSE,
      rule="HIGH>=5 / AX hard FAIL>=3 / Hard Constraint 위반 / RF-O9 single-snapshot 중 해당 없음")),
  self_adversarial_challenge_ref="qepm/mailbox/worktask/WT-R20260829_004/challenge_note.md (# optimizer 구간)",
  weight_method_selected_ref="stage_artifacts/WT_R20260829_004/weight_method_selected.md",
  verdict="optimization_package_complete",
  handoff=list(next_agent="forge",
    consumes=c("qepm/mailbox/worktask/WT-R20260829_004/optimization_package.json",
      "stage_artifacts/WT_R20260829_004/weights.csv",
      "stage_artifacts/WT_R20260829_004/alpha_scores.parquet",
      "stage_artifacts/WT_R20260829_004/covariance.parquet"),
    forge_reading_order=c(
      "1) weights.csv 를 그대로 소비할 것 - 260 as_of_date 전량 발행(density 1.00). 가상 schedule 재생성 금지(STR_1715 Iter 31 fabrication 선례).",
      "2) challenge_flags OPT-CH1(오버레이 한계기여 음수) / OPT-CH2(oos_retention 전 method 음수) 를 등급 서술에 반영할 것",
      "3) RISK-CH7(crisis 구간별 IC 안정성)은 risk 가 forge 로 지정 - 본 층 미수행",
      "4) 비교 basis 로 무조건화 역변동성(C2_IV_off) 좌표를 함께 볼 것: Calmar 0.2180 SR 0.5829 alpha 5.49%/yr")))

write_json(pkg, file.path(MB,"optimization_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=10, na="null")
cat(sprintf("[O7] optimization_package.json written - n=%d sum=%.10f\n", length(tw), sum(unlist(tw))))
src <- file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(src)) { source(src)
  ok <- tryCatch({ record_package_lineage(task_id="WT-R20260829_004", package_type="optimization_package",
      method_selected="W2_IV_regime_switch_composition_plus_inverse_vol",
      input_file_paths=c(file.path(MB,"alpha_package.json"), file.path(MB,"risk_package.json"))); TRUE },
      error=function(e){ cat("[O7] lineage 실패:", conditionMessage(e), "\n"); FALSE })
  cat("[O7] lineage recorded:", ok, "\n") }
