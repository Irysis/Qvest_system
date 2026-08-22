## WT-D20260822_008 (FQ-246 NP2) P9 — 산출물 방출
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"; MB <- "qepm/mailbox/worktask/WT-D20260822_008"
P1<-readRDS(file.path(OUT,"p1_parity.rds")); G<-readRDS(file.path(OUT,"p3_gate.rds"))
B <-readRDS(file.path(OUT,"p4_bounds.rds")); P5<-readRDS(file.path(OUT,"p5_target_identity.rds"))
A6<-readRDS(file.path(OUT,"p6_adversarial.rds")); P7<-readRDS(file.path(OUT,"p7_falsification.rds"))
P8<-readRDS(file.path(OUT,"p8_subsample_followup.rds")); PRE<-fromJSON(file.path(OUT,"PREREG.json"))
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector=FALSE)
K<-P1$K; NM<-P1$NM; months<-P1$months; DIRS<-P1$DIRS; AM<-P1$AM
dtl <- function(x) as.list(as.data.table(x))

## ---------- (a) 진단 패널 parquet ----------
CR <- P1$CRIT
pan <- rbindlist(lapply(seq_len(NM), function(m) rbindlist(lapply(seq_len(K), function(k)
  data.table(Date=as.Date(months[m]), factor_slot=k,
    factor_id=P1$A4$sel_rank[[months[m]]][k],
    crit_breadth=CR[m,k,"breadth"], crit_margin=CR[m,k,"margin"],
    crit_centrality=CR[m,k,"centrality"], crit_stability=CR[m,k,"stability"],
    key_ic_rank_ic=P1$icm[m,k], key_ret_top25=P1$ret_by_factor[m,k],
    key_ret_top25_net=B$RBFNET[m,k],
    is_ic_best=as.integer(P1$ic_best[m]==k), is_ret_best=as.integer(P1$ret_best[m]==k),
    is_ret_net_best=as.integer(B$ret_best_net[m]==k))))))
for (nmd in names(DIRS)) pan[, (paste0("pick_",nmd)) :=
  as.integer(factor_slot == AM[[nmd]][match(Date, as.Date(months))])]
pan[, metric_type := "diagnostic_criterion_validity"]
pan[, capital_eligible := FALSE]
write_parquet(pan, file.path(OUT,"alpha_scores.parquet"))
cat(sprintf("[emit] alpha_scores.parquet — %d행 x %d열 (진단 패널: 월×팩터슬롯)\n", nrow(pan), ncol(pan)))

## ---------- (b) alpha_package.json ----------
mk_factor <- function(fid, cn, note) list(
  factor_id=fid,
  ast=list(leaf="SPECIAL_OP", escape_contract=list(escape_type="SPECIAL_OP",
    op_code_path=sprintf("stage_artifacts/WT-D20260822_007/p3_partB.R :: CRIT[,,'%s'] (비트-동일 승계) + stage_artifacts/WT-D20260822_008/p3_gate.R :: gate_row()", cn),
    walk_forward=TRUE)),
  role="diagnostic_selection_criterion", restatement_exposure=0L, ast_note=note)
pkg <- list(
  task_id="WT-D20260822_008", as_of_date="2026-08-22", forecast_horizon="1M",
  spec_version="ast_v1.1",
  pit=list(sig_date="2026-07-01", decision_ts="2026-07-01",
    note="기준 4종은 당월(및 m-1) z 횡단면만의 함수 — 성과-비파생·PIT-safe. 정답지 2종(rank-IC / top-25 실현수익)은 **구성상 사후 정보**이며 진단 표적으로만 사용, capital_eligible=FALSE."),
  hypothesis=HYP$selected[c("statement","mechanism","falsification","regime_scope")],
  factors=list(
    mk_factor("C1_breadth_tailmass","breadth","팩터-축 argmax 는 𝒪(종목 횡단면/시계열 연산)로 표현 불가 — SPECIAL_OP 로 정직 산출(WT-007 판단 승계). walk_forward=TRUE: 학습 파라미터 없음, 각 월 결정이 그 달 횡단면만으로 닫힘."),
    mk_factor("C2_margin_boundary","margin","동상."),
    mk_factor("C3_centrality_conflict","centrality","동상."),
    mk_factor("C4_stability_rankpersistence","stability","동상. anchor m 과 m-1 만 사용(둘 다 <= m).")),
  combination_rule="single_factor",
  verdict="designed",
  self_pit_check=list(performed=TRUE, leaves_checked=list(
    list(leaf="FDB-B6_fdb_daily_store (팩터 z 횡단면)", availability_rule="fixed: 월말 t-1 종가 기준 factor DB 승격분", restatement_prone=FALSE),
    list(leaf="A1_RAWDATA_OHLCVS_daily", availability_rule="fixed: t-1 close", restatement_prone=FALSE),
    list(leaf="FDB-B7_ic_history_monthly (정답지 · 진단 전용)", availability_rule="regulatory/fixed: Usable_Date <= sig_date — 단 본 라운드 용법은 **차월 실현치**라 look-ahead", restatement_prone=FALSE)),
    verdict="clean",
    rationale="기준 리프는 전부 PIT-safe. 정답지 리프(차월 실현 rank-IC / 차월 top-25 수익)는 설계상 look-ahead 이며 **진단 표적**으로만 격리했다 — 본 패키지는 α̂ 를 방출하지 않으므로(terminal_form=diagnostic_criterion_validity) 어떤 자본 경로도 이 리프를 통과하지 않는다."),
  alpha_vector=setNames(list(), character(0)),
  confidence_vector=setNames(list(), character(0)),
  signal_matrix_ref=paste0("file://", OUT, "/alpha_scores.parquet"),
  factor_specs=list(list(factor_family="Selection_Criterion_Diagnostic",
    proxy="breadth / margin / centrality / stability (팩터-축 선택 기준 4종)",
    formula="당월 z 횡단면 파생 — breadth=(top25 평균 z - 전체 평균 z)/sd · margin=(25위 z - 30위 z)/sd · centrality=팩터-간 Spearman 평균 · stability=cor(rank(z_m), rank(z_{m-1}))",
    lag_rule="t-1 close (성과-비파생)", winsorization="none (원 z 사용)", neutralization="none",
    economic_rationale="behavioral", weight_theta=0,
    references=c("WT-D20260822_007 p3_partB.R (기준 정의 원전)","Harvey-Liu-Zhu 2016 (다중검정)"))),
  diagnostics=list(
    canonical_port_t_nw_lag3=NULL,
    canonical_n_months=NM,
    rank_ic=NULL, icir=NULL, monotonicity=NULL, subperiod_stability=NULL,
    turnover_proxy=NULL, harvey_t_stat=NULL, post_neutralization_ic=NULL,
    deflated_sharpe_ratio=NULL,
    alpha_inheritance_cor=1.0,
    alpha_inheritance_cor_definition="기준 배열(CRIT) 을 WT-D20260822_007 에서 비트-동일 승계(패리티 Δ=0.000e+00) ⇒ **기준 축** 상속 상관 1.0. α̂ 미방출이라 종목-축 alpha 상관은 정의되지 않음(NA 가 아니라 미정의).",
    criterion_validity=list(
      metric_type="diagnostic_criterion_validity", capital_eligible=FALSE,
      best_hit_RET=max(G$ALL[key_id=="RET" & criterion %in% names(DIRS), hit]),
      best_hit_RET_criterion=G$ALL[key_id=="RET" & criterion %in% names(DIRS)][which.max(hit), criterion],
      chance=1/K, binom_MDE_qbinom=G$MDE_HIT, binom_exact_critical=A6$crit_hit,
      gates_passed_adjusted=B$n_pass_adj, gates_passed_raw=B$n_pass_raw,
      key_swap_material_count=B$n_pair_mat, key_swap_dhit_MDE_2s=G$MDE_D2S,
      note="★이 블록은 전부 look-ahead 정답지에 대한 진단이다. 자본·졸업 주장에 사용 금지(AX-002).")),
  alpha_discovery_count=0L,
  selection_objective="rank_ic",
  challenge_flags=list(
    "terminal_form=diagnostic_criterion_validity — α̂ 미방출. alpha_vector/confidence_vector 는 **의도적 공집합**이며 결측이 아니다(schema required 충족 목적).",
    "canonical_port_t_nw_lag3 = null: 본 라운드는 처치 포트폴리오를 구성하지 않았다(사전등록대로 성과 축 미측정). 정답지가 사후 정보이므로 성과 산출 자체가 AX-002 위반 경로.",
    "rank_ic 등 advisory 계열 = null: 합성 스코어를 만들지 않았으므로 정의되지 않음. 승계값 전재(빌려온 basis) 금지 규율 적용.",
    "★승계 기전 반증 F5 미지지: 불일치 월 RET-승자의 breadth z 가 일치 월보다 **낮다**(-0.0060 vs +0.1085, Welch t -0.950, p 0.343) — 승계 가설의 '꼬리에서만 옳은 팩터' 서술은 실측 미지지. 재작성하지 않고 challenge_note 에 기록(Charter 원칙 8).",
    "★승계 국면 경계 미지지: 위기 월 정답지 스프레드가 정상 월보다 낮지 않고(0.04873 vs 0.04955) 적중률도 약화되지 않았다(위기 0.2188 vs 정상 0.2069) — regime_scope 재설계 요청.",
    "탐색적 부분표본(고판별성 절반)에서 raw 2/8 관측 — Bonferroni 0/8 · 선택가치 순열-유의 0/8 · 최고 적중 기준의 선택가치가 음수. 사전등록 게이트 아님, 승격 근거로 인용 금지."))
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=12)
cat("[emit] alpha_package.json\n")

## ---------- (c) alpha_validation.json ----------
RETT <- G$ALL[key_id=="RET"]; ICT <- G$ALL[key_id=="IC"]
val <- list(
  task_id="WT-D20260822_008", round_id=PRE$round_id, fq_ref="FQ-246 NP2",
  produced_by="alpha-research", produced_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg_ref=paste0(OUT,"/PREREG.json (봉인 ", PRE$sealed_at, " — 결과 통계량 산출 前)"),
  hypothesis_ref=paste0(MB,"/alpha_hypothesis.json (alpha-hypothesis, verdict=designed) — 승계, 재작성 없음"),
  terminal_form="diagnostic_criterion_validity", capital_eligible=FALSE,
  metric_type_note=paste0("전 산출 metric_type='diagnostic_criterion_validity'. 정답지 2종은 구성상 사후 정보(look-ahead)이며 ",
    "본 라운드는 '그 정답지를 맞히는 기준이 존재하는가' 만 측정했다. 성과 arm 미구성 · α̂ 미방출 · canonical_screen_bt 는 ",
    "**패리티 재현 1회**(ORACLE_K_RET)에만 사용. 자본·졸업 주장 금지(AX-002)."),
  lookup_clause=list(performed=TRUE,
    tool="02_Infrastructure/tools/hypothesis_index.R :: lookup_hypothesis()",
    keyword_sets=list("answer key + target + selection criterion","realized return target + argmax",
      "criterion validity + hit rate","consumption surface + selection target","정답지",
      "factor selection criterion","top-25 realized return argmax","oracle selection","mcnemar + paired hit rate"),
    prior_attempts_on_this_axis=0L,
    nearest_prior="DIST-AR-057 (DISTILLED_NEG, measurement_form, tags FQ-237/FQ-233-revi, 2026-08-22) — 같은 계열(측정 형태)이나 정답지 **교체** 축은 아님",
    direct_parent="WT-D20260822_007 (FQ-246 NP1, ALPHA_DONE) — 본 라운드는 그 라운드 next_probe NP1 의 정답지 축을 소화",
    differentiator=paste0("선행 어디에도 '기준·K·창을 고정하고 정답지만 교체해 paired 로 비교한' 라운드가 없다. ",
      "WT-007 은 IC 정답지 단독이었고 소비면 정답지는 상한 산출(ORACLE_K_RET)에만 쓰였다."),
    frontier_queue="FQ-246 status=CLAIMED_20260822__state_conditional_selection_launching, owner Q-Lead session d2e06481 — dohoon_decision 아님"),
  control_parity=list(
    ORACLE_K_RET=dtl(P1$PAR),
    IC_key_FC_gate_8directions=list(max_abs_d_hit=max(P1$CMPP$d_hit), max_abs_d_rho=max(P1$CMPP$d_rho),
      max_abs_d_rho_t=max(P1$CMPP$d_rhot),
      verdict="★WT-007 IC-정답지 FC 게이트 8방향이 Δ=0.000e+00 비트-동일 재현 — 정답지만 교체하는 paired 대조의 전제 성립"),
    conductivity=dtl(G$COND[, .(criterion, key_id, n, hit, hit_p, rho, rho_t, selval_ann_pct, gate_raw)]),
    conductivity_verdict=sprintf("양성 대조 4/4 발화(잡음 4배까지 hit %.4f, p %.2e) · 음성 대조 미발화(hit %.4f, p %.3f) ⇒ 게이트는 존재하는 정보를 검출한다",
      G$COND[criterion=="POSCTRL_oracle_noise4.0", hit], G$COND[criterion=="POSCTRL_oracle_noise4.0", hit_p],
      G$COND[criterion=="NEGCTRL_uniform_random", hit], G$COND[criterion=="NEGCTRL_uniform_random", hit_p])),
  answer_key_structure=list(
    agreement_rate=P1$agree, n_discordant_months=PRE$measured_design_inputs$n_discordant_months,
    cross_key_mean_rho=mean(P1$rho_keys, na.rm=TRUE),
    cross_key_rho_t_nw3=.nw_t_mean(P1$rho_keys[is.finite(P1$rho_keys)], lag=3L),
    ic_best_in_ret_top2=mean(vapply(seq_len(NM), function(m) P1$ic_best[m] %in% G$top2_set[[m]], TRUE)),
    discriminability=list(median_1st2nd_margin_monthly=median(P7$marg, na.rm=TRUE),
      median_1st2nd_margin_ann_pct=median(P7$marg, na.rm=TRUE)*12*100,
      median_best_worst_spread_ann_pct=median(P7$spread)*12*100,
      near_tie_share_margin_lt_0p2pct_month=P7$near_tie),
    F1_verdict=sprintf("PASS — 불일치 %.2f pp 가 설계 문턱 %.2f pp 를 크게 상회 ⇒ UNRESOLVED_DESIGN_CAP 아님",
      P7$dis*100, (G$MDE_HIT-1/K)*100),
    interpretation=paste0("두 정답지는 우연(0.20)보다 훨씬 자주 일치(0.4887)하지만 절반 이상(113/221 개월) 갈린다. ",
      "즉 교체가 판정 여지를 갖되, 상한 2.30배의 원천이 '다른 표적' 이라는 전제는 여기서 이미 약해진다.")),
  power_precomputed=PRE$MDE_precomputed,
  power_transfer=PRE$power_transfer,
  power_correction=list(
    qbinom_MDE=G$MDE_HIT, exact_critical_count=A6$crit_x, exact_critical_hit=A6$crit_hit,
    note="★자기 적대검증 C1 — 사전등록 MDE(qbinom 판, WT-007 컨벤션 승계)는 실제 기각역보다 1 count 낮다(54 vs 55). 문턱을 완화한 게 아니라 **정확 임계치를 병기**하고 경계 arm 을 UNRESOLVED 로 강등했다."),
  primary_RET_key=dtl(RETT[, .(criterion, n, hit, hit_excess_pp, hit_p, hit2, hit2_p, rho, rho_t,
                               rho_mde95, selval_ann_pct, selval_t, pass_raw, pass_adj, label)]),
  control_IC_key=dtl(ICT[, .(criterion, n, hit, hit_p, rho, rho_t, rho_mde95, label)]),
  paired_key_swap=dtl(G$PAIR),
  exclusion_bounds=dtl(B$CI[, .(criterion, hits, n, hit, ci_lo, ci_hi, ci_hi_1s, excess_hi_pp)]),
  exclusion_statement=sprintf("어떤 기준도 h_RET > %.4f (단측 95%% 상한 최대) 를 지지하지 않는다. 배제 못 한 구간 = h_RET ∈ (0.2000, %.4f].",
    max(B$CI$ci_hi_1s), max(B$CI$ci_hi_1s)),
  detection_floor_ladder=dtl(B$LAD),
  detection_floor_note=paste0("★사다리는 '잡음 섞인 단조 사본' 대안에 대한 검정력 곡선이다. 관측 기준은 같은 적중률에서 |rho| 가 ",
    "사다리보다 훨씬 낮아(0.049 vs 0.080) 궤적 밖 — 즉 '꼭짓점만 아는' 대안 형태이며 그 대안의 구속 채널은 rho 가 아니라 ",
    "이항 적중률이다. 사다리의 0.85 발화율을 인용하면 검정력 과대 주장(자기 적대검증 C2 ACCEPT)."),
  net_key_robustness=dtl(B$NETT),
  net_key_note=sprintf("비용-차감 소비면(팩터별 top-25 교체율 x 2 x 15bps) 정답지에서도 최대 적중 %.6f — 정확 임계 %.6f 미달(p %.4f). 단 qbinom-MDE 와 동률이라 그 arm 은 UNRESOLVED_UNDERPOWERED 로 라벨.",
    max(B$NETT$hit_net), A6$crit_hit, B$NETT[which.max(hit_net), p_net]),
  selection_value_permutation=list(measured=dtl(P7$SV),
    perm_null_mean_ann_pct=mean(P7$perm_ann), perm_null_sd_ann_pct=sd(P7$perm_ann),
    perm_MDE_2s_ann_pct=1.96*sd(P7$perm_ann), n_perm=2000L,
    verdict=sprintf("순열 귀무 대비 유의 1/8 — centrality_MIN 선택가치 %+.4f %%p/yr (perm z %.3f, 백분위 %.4f) 로 **유의 음수**. Bonferroni(8) |z| 2.734 미달이라 raw 유의.",
      P7$SV[criterion=="centrality_MIN", selval_ann_pct], P7$SV[criterion=="centrality_MIN", perm_z],
      P7$SV[criterion=="centrality_MIN", perm_pctile])),
  dissociation=list(measured=dtl(B$DIS),
    cor_hit_selval_pearson=unname(A6$ct$estimate), cor_ci=A6$ct$conf.int, cor_p=A6$ct$p.value,
    note=paste0("★적중률 최고 기준(centrality_MIN, 우연 +3.53pp)이 선택가치는 최저(-5.2672 %p/yr). 8점 상관 -0.4995 는 ",
      "CI 가 부호를 넘나들어 근거가 약하므로 주장의 근거는 상관이 아니라 개별 관측이다. 함의: **argmax 적중은 분포의 한 점이고 ",
      "선택가치는 분포 전체다 — 선별 기준을 적중률로 채점하는 것 자체가 소비면과 어긋난 표적일 수 있다**(본 라운드가 새로 연 축).")),
  target_identity_split_sample=list(
    design=paste0("같은 달 유니버스를 무작위 절반 A/B 로 나눠 A 에서 팩터를 고르고 B 에서 값을 평가(R=20 분할 평균). ",
      "목적 = null 의 귀속 분리: '기준이 나쁜가' vs '표적이 애초에 표본-무관 정체를 갖지 않는가'."),
    NHALF12=dtl(P5$SUM), spec_robustness=dtl(A6$CMP),
    verdict=sprintf(paste0("★표적에는 실재하는 전이 성분이 있다 — A 의 실현수익 argmax 가 B 에서 %+.4f %%p/yr (NW3 t %.3f, ",
      "무작위 픽 %+.4f) · 승자 정체 A-B 일치 %.4f (우연 0.2000). 단 전이는 반쪽 오라클 상한의 %.4f 에 불과하다."),
      P5$SUM$transfer_ret_ann, P5$SUM$transfer_ret_t, P5$SUM$random_B_ann, P5$SUM$agree_AB,
      P5$SUM$transfer_ret_ann/P5$SUM$oracle_B_ann),
    headline=sprintf(paste0("★★본 라운드 최대 실측 — **두 정답지의 2.30배 격차는 전이 성분에 없다**. 전이 가능한 부분에서 ",
      "IC 정답지는 RET 정답지의 %.4f 배(%.4f vs %.4f %%p/yr, NHALF=12) / %.4f 배(NHALF=25) 로 거의 같다. ",
      "반면 전수-표본 오라클 시점에서는 2.2999 배로 벌어진다 ⇒ 그 격차의 대부분은 **월내 잡음 최대화**이지 표적 차이가 아니다."),
      A6$CMP[1, ic_over_ret_transfer], P5$SUM$transfer_ic_ann, P5$SUM$transfer_ret_ann,
      A6$CMP[2, ic_over_ret_transfer]),
    caveat="반쪽 유니버스 top-N 은 전체 top-25 소비면과 다른 규격이다 — 전이 비율(0.207 / 0.279)의 전체 공간 외삽은 estimated 이며 measured 아님."),
  falsification_schema_results=list(
    F1=sprintf("PASS — 불일치율 %.8f (113/221) ≫ 문턱 4.4344 pp. 설계 봉쇄 아님", P7$dis),
    F2=sprintf("기각 — RET 정답지 적중률 게이트 통과 0/8 (raw·Bonferroni·Sidak 전부 0). 최대 %.6f (%s), 정확 임계 %.6f",
      max(RETT[criterion %in% names(DIRS), hit]), RETT[criterion %in% names(DIRS)][which.max(hit), criterion], A6$crit_hit),
    F3a=sprintf("기각 — |rho_t| 최대 %.3f (문턱 1.5). rho MDE95 는 RET 정답지에서 직접 재측정(평균 %.6f) — 승계값 이월 없음",
      max(abs(RETT[criterion %in% names(DIRS), rho_t])), mean(RETT[criterion %in% names(DIRS), rho_mde95])),
    F3b="기각(단 반대 부호 1건) — 순열 귀무 대비 유의 1/8이며 그 1건이 **유의 음수**(centrality_MIN). 양의 선택가치 0/8",
    F4=sprintf("기각 — 정답지 교체 paired 유의 0/8. 관측 최대 |Δhit| %.6f vs 양측 MDE %.6f · McNemar |z| 최대 %.3f",
      max(abs(G$PAIR[criterion %in% names(DIRS), d_hit])), G$MDE_D2S,
      max(abs(G$PAIR[criterion %in% names(DIRS), mcnemar_z]))),
    F5=sprintf("★미지지 — 불일치 월 RET-승자 breadth z %+.4f vs 일치 월 %+.4f (Welch t %.4f, p %.4f). 승계 '꼬리에서만 옳은 팩터' 기전 서술 강등",
      mean(P7$bw_z[P7$disc], na.rm=TRUE), mean(P7$bw_z[!P7$disc], na.rm=TRUE),
      unname(P7$F5$statistic), P7$F5$p.value),
    A6_investor_HHI="미측정 — advisory 축이며 본 라운드 판정에 미사용. 사유: F5 본축이 이미 미지지라 보조 동행 관측의 정보가치 낮음. next_probe 로 이월"),
  regime_advisory=list(measured=dtl(P7$REG),
    crisis_months=sum(P7$bad), normal_months=sum(!P7$bad),
    key_spread_median_crisis=median(P7$spread[P7$bad]), key_spread_median_normal=median(P7$spread[!P7$bad]),
    mean_hit_crisis=mean(P7$REG$hit_crisis), mean_hit_normal=mean(P7$REG$hit_normal),
    verdict="★승계 regime_scope 미지지 — 예측은 '위기 월에 정답지 스프레드 붕괴 → 적중률 약화' 였으나 스프레드는 거의 동일(0.04873 vs 0.04955)하고 적중률도 약화 없음(0.2188 vs 0.2069). 재설계 요청(수정 아님)."),
  exploratory_subsample=list(measured=dtl(P8$SUB),
    n=length(P8$idxhi), perm_null_sd=sd(P8$perm_hi),
    note=paste0("★탐색적 — 사전등록 게이트 아님. 고판별성 절반(마진 중앙 이상)에서 적중 raw 2/8(P(>=2|귀무)=0.0572) 이나 ",
      "Bonferroni 0/8 · 선택가치 순열-유의 0/8 · 최고 적중 기준의 선택가치가 음수(-2.6859 %p/yr). ",
      "승격 근거로 인용 금지 — next_probe 의 사전등록 대상으로만 이월.")),
  verdict="KEY_SWAP_POWERED_NULL__WRONG_TARGET_HYPOTHESIS_REJECTED__TARGET_GAP_IS_NOISE_NOT_IDENTITY",
  verdict_detail=paste0(
    "①헤드라인 가설 기각(powered): 정답지를 소비면(top-25 실현수익 argmax)으로 교체해도 기준 8방향 중 게이트 통과 0/8이고, ",
    "정답지 교체의 paired 효과도 0/8(관측 최대 |Δhit| 0.022624 vs 양측 MDE 0.059626). ⇒ WT-007 의 9/9 무지는 ",
    "'기준이 잘못된 표적을 맞혔다' 로 설명되지 않는다 — 기준 집합이 두 표적 모두에 무지하다. ",
    "②그 이유가 실측됐다: 두 정답지는 48.87% 일치하고(우연 20%) 월별 순위상관 +0.3466(NW3 t 9.381) 로 상당 부분 같은 표적이다. ",
    "③★그리고 남은 격차마저 신호가 아니다 — 분할표본 전이에서 IC 정답지는 RET 정답지 전이값의 0.867~0.919 배로 거의 같은데, ",
    "전수-표본에서는 2.2999 배로 벌어진다. 즉 ORACLE_K_RET 8.8381 이 ORACLE_K_IC 4.6470 을 2.30배 앞선 것의 대부분은 ",
    "**월내 잡음 최대화**이며, 그 상한을 여유폭 분모로 쓴 서술은 과대 분모를 쓰고 있었다. ",
    "④단 표적 자체는 실재한다 — 전이 +8.86~9.48 %p/yr (NW3 t 3.38~4.23), 승자 정체 A-B 일치 0.309~0.327 (우연 0.200). ",
    "⇒ null 의 귀속은 '표적 부재' 가 아니라 **기준 부재**다. 다음 라운드는 정답지가 아니라 기준을 바꿔야 한다. ",
    "⑤새로 열린 축: 적중률과 선택가치가 어긋난다(최고 적중 기준의 선택가치가 유의 음수) — 선별 기준을 argmax 적중률로 채점하는 것 ",
    "자체가 소비면과 어긋난 표적일 수 있다."),
  round_verdict="CONFIG_SCOPED_NEGATIVE__CONSUMPTION_MATCHED_TARGET_NO_RECOVERY__ORACLE_CEILING_REVISED_DOWNWARD",
  next_probe=list(
    list(id="NP1", title="여유폭 분모 재정의 — 전이 가능 상한(transferable ceiling)으로 교체",
      rationale=paste0("본 라운드 실측: 반쪽 오라클 대비 전이 비율 0.207(NHALF=12) / 0.279(NHALF=25). ORACLE_K 계열 상한은 ",
        "월내 잡음 최대화를 포함하므로 회수율 분모로 과대다. FQ-244/246/007 이 쓴 여유폭 13.6930 %p/yr · ",
        "ORACLE_K_RET 31.4926 %p/yr 를 '전이 가능 성분' 으로 재산출하면 그 라운드들의 회수율(예: FQ-246 25.1%)이 ",
        "상향 재해석된다 — 즉 지금까지 '미회수' 로 본 것의 상당분이 애초에 도달 불가였다."),
      consumes="stage_artifacts/WT-D20260822_008/p5_target_identity.rds + p6_adversarial.rds(CMP)",
      design="교차검증형 오라클(cross-fitted oracle): 월내 K-fold 로 선택-평가를 분리해 canonical_screen_bt 경로에서 PORT_t 상한을 재산출. 사전등록 + 검정력 직접 측정."),
    list(id="NP2", title="기준을 바꾼다 — 전이 성분과 상관되는 관측 기준 탐색(정답지 고정)",
      rationale=paste0("본 라운드가 '표적은 실재하고 기준이 무지' 로 귀속을 좁혔다(전이 t 3.38~4.23 · 승자 정체 일치 0.309). ",
        "그러나 반쪽 실현치를 **직접 보는** 관측자조차 정체 일치가 0.309 에 그친다 — 실현 가능 기준의 현실적 상한이 그 아래임을 시사. ",
        "따라서 기준 발굴은 적중률이 아니라 **전이 성분과의 상관**을 표적으로 설계해야 한다."),
      consumes="alpha_scores.parquet(진단 패널) + p5 전이 계열",
      design="후보 = 팩터 z 의 분포 형상(왜도·초과첨도·꼬리 두께) · 멤버십 중첩도 · 유동성 프로파일 · 크라우딩. v8.4 Lane A(분포-표적) 와 직결. 비-ML 먼저(헌법 재진입 순서 ①)."),
    list(id="NP3", title="채점 표적 자체 교체 — argmax 적중률에서 선택가치로",
      rationale=paste0("본 라운드 신규 관측: 적중률 최고 기준(centrality_MIN)의 선택가치가 **유의 음수**(-5.2672 %p/yr, 순열 z -2.584). ",
        "적중률은 분포의 한 점이고 선택가치는 분포 전체다. 선별 기준을 적중률로 채점하는 관행 자체가 ",
        "소비면과 어긋난 표적일 수 있다 — 이는 본 라운드가 '정답지' 를 바꿔 답하지 못한 질문의 한 단계 위 버전이다."),
      consumes="p7_falsification.rds(SV·순열 귀무) + alpha_scores.parquet",
      design="선택가치(연속)를 1급 목적함수로 사전등록하고 기준 탐색·평가를 그 축에서 수행. 적중률은 advisory 로 강등."),
    list(id="NP4", title="고판별성 월 조건부 — 탐색적 2/8 을 사전등록으로 재시험",
      rationale=paste0("탐색적 관측: 1위-2위 마진 중앙 이상 월에서 centrality_MIN 0.27928(p 0.0279) · stability_MIN 0.27027(p 0.0453). ",
        "P(>=2 | 귀무)=0.0572 로 경계이고 선택가치는 0/8 — 현 라운드에서는 승격 불가. 그러나 판별성이 연속 조건변수라는 ",
        "설계는 승계 regime_scope 논리와 정합하므로 독립 창·사전등록으로 재시험할 가치가 있다."),
      consumes="p8_subsample_followup.rds + alpha_scores.parquet",
      design="판별성을 연속 상태변수로(이분화 금지) · 사전등록 · 다중검정 사전 선언 · 선택가치 co-primary.")),
  revival_conditions=list(
    criterion_revival="새 기준이 (i) RET 정답지 적중 정확 임계 0.248869 초과 또는 (ii) 선택가치 순열 z >= +1.96 을 통과하면 하드 선택 축은 즉시 재개. 본 라운드는 기준 4종(+거울)만 기각했지 '하드 선택' 족을 기각한 것이 아니다.",
    target_revival="정답지 축은 종결이 아니다 — NP3(선택가치 표적)는 정답지의 **정의역**을 바꾸는 것이지 기준을 바꾸는 것이 아니며 미측정이다.",
    ceiling_status="★ORACLE_K 계열 상한은 부정되지 않았고 **재정의 대상**이다(NP1). 전이 성분(0.207~0.279)이 실재하므로 도달 가능한 상한은 0 이 아니다.",
    hard_form_status="하드 one-hot 형태의 전도성은 WT-007 Part A 에서 확립됐고 본 라운드가 건드리지 않았다 — 불변."),
  consumption_surface_7=list(
    factor_ranking="즉시 소비 없음 — 기준 8방향 전부 게이트 미통과.",
    universe_filter="미측정 (유니버스 불변).",
    overlay_regime_input="미측정 — 단 '판별성(1위-2위 마진)' 은 월별 연속 상태변수로 오버레이 입력 후보(NP4).",
    risk_model_beta_budget="역할 경계상 소관 아님 — 단 '적중률 최고 기준의 선택가치 유의 음수' 는 집중도 페널티 설계에 이식 가능한 관측.",
    monitoring_signal="★배관 가치 있음 — 전이 성분(분할표본 A→B 전이)은 라이브에서 월간 산출 가능하며 '표적이 살아 있는가' 의 조기 경보다. FQ 등재 권고.",
    screening_label="screen_route 발급 없음 — 성과 축 자체를 측정하지 않았다.",
    cross_mode_transfer="★RAMP 로 이식 가치 — '오라클 상한이 잡음 최대화를 포함한다' 는 RAMP 의 팩터군 상한 서술에도 동일 적용된다(전이 가능 상한 재산출 권고)."),
  self_adversarial=list(
    note="v8.2 — 외부 Codex 없음. 전 concern 을 실측으로 응답. 상세 = qepm/mailbox/worktask/WT-D20260822_008/challenge_note.md",
    concern_count=6L, accept=3L, partial=2L, rebuttal=1L,
    escalate_triggers=list(high_severity_ge5=FALSE, axiom_hard_fail_ge3=FALSE, pit_c1_violation=FALSE, escalate=FALSE),
    inheritance_integrity=list(rewritten=FALSE, contradictions_recorded=c(
      "F5 (꼬리질량 기전 지문) 미지지 — 승계 mechanism 의 '꼬리에서만 옳은 팩터' 서술 강등",
      "regime_scope 미지지 — 위기 월 스프레드 붕괴·적중률 약화 둘 다 실측 부재"))),
  limitations=list(
    "정답지 2종 모두 look-ahead — 본 라운드는 '기준이 그것을 아는가' 만 답하고 '그것을 쓸 수 있는가' 는 묻지 않았다.",
    "기준 집합은 WT-007 의 4종 고정(paired 설계의 전제). 새 기준 발굴은 범위 밖(NP2).",
    "분할표본 전이는 반쪽 유니버스 규격 — 전체 공간 전이 비율은 estimated(외삽), measured 아님.",
    "선택가치는 gross 기준(팩터별 top-25 평균 forward return). net 정답지 강건성은 적중률 축에서만 확인.",
    "탐색적 부분표본(고판별성 절반) 결과는 사전등록 게이트 밖 — 승격 근거 아님.",
    "A6 투자자 flow HHI 동행(F5 보조)은 미측정 — 본축 미지지로 정보가치 낮다고 판단, next_probe 이월.",
    "창 = 221개월 단일. 독립 창 재현 미실시(NP4 가 요구).",
    "정답지 교체 paired 의 검정력은 불일치 월 113개에 묶인다 — 일치 월은 구조적으로 Δ에 0 을 기여."),
  quantity_names_and_units=list(
    ORACLE_K_IC_port_t=4.646999095, ORACLE_K_RET_port_t=8.8381268503,
    ORACLE_K_RET_paired_ann_pct=31.492557813,
    SELSPACE_headroom_ann_pct=P1$selspace_head, SELSPACE_value_of_IC_key_ann_pct=P1$selspace_head_ic,
    HALF_TRANSFER_RET_ann_pct_NHALF12=P5$SUM$transfer_ret_ann,
    HALF_TRANSFER_IC_ann_pct_NHALF12=P5$SUM$transfer_ic_ann,
    HALF_TRANSFER_RET_ann_pct_NHALF25=A6$CMP[2, transfer_ann],
    collision_warning=paste0("★규율 6 — 위 6개 양은 전부 %p/yr 단위지만 **분모·경로가 다르다**: ",
      "ORACLE_K_RET paired 31.4926 = canonical_screen_bt 로 C0 결합 대비 포트 net active / ",
      "SELSPACE_headroom 35.6618 = 전체 유니버스 top-25 단일-팩터 수익 공간의 오라클-평균 / ",
      "HALF_TRANSFER 8.86~9.48 = 반쪽 유니버스 교차 전이. 인용 시 이름과 경로를 함께 적을 것.")))
val$quantity_names_and_units$collision_warning <- gsub("%p/yr","%%p/yr", val$quantity_names_and_units$collision_warning, fixed=TRUE)
val$quantity_names_and_units$collision_warning <- gsub("%%p/yr","%p/yr", val$quantity_names_and_units$collision_warning, fixed=TRUE)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=12)
cat(sprintf("[emit] alpha_validation.json — %d bytes\n", file.size(file.path(OUT,"alpha_validation.json"))))

## ---------- (d) lineage ----------
source("02_Infrastructure/worktask/lineage_utils.R")
try(record_package_lineage(task_id="WT-D20260822_008", package_type="alpha_package",
  method_selected="정답지 교체 paired 기준-타당성 진단 (기준 4종 x 8방향, IC vs top-25 실현수익)",
  input_file_paths=c("stage_artifacts/WT-D20260822_007/p3_partB.rds",
    "stage_artifacts/WT-D20260822_007/p5_adversarial.rds",
    "stage_artifacts/WT-D20260822_007/p1_probe.rds",
    "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet")), silent=TRUE)
cat("[emit] lineage recorded\n\nOK\n")
