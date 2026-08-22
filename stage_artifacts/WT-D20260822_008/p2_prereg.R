## WT-D20260822_008 (FQ-246 NP2) P2 — 사전등록 봉인 (MDE **사전** 계산 포함)
## ★봉인 시점 = 결과 통계량 산출 前. 여기 쓰인 입력은 전부 설계 구조(n·K·정답지 일치율)이며
##   가설의 결과(기준×정답지 적중률)는 아직 계산하지 않았다.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds"))
K <- P1$K; NM <- P1$NM; a <- P1$agree; p0 <- 1/K

## ---- (A) 한계 적중률 검정 MDE (단측 5%, 이항) ----
mde_hit  <- qbinom(0.95, NM, p0)/NM
mde_hit2 <- qbinom(0.95, NM, 2/K)/NM        # 보조 표적: top-2 멤버십(우연 0.4)
## ---- (B) 순위상관(rho) 검정 MDE — 해석적 상한 ----
##  K=5 항목 Spearman 의 귀무 sd = 1/sqrt(K-1) = 0.5 (동률 없을 때). NW3 는 실측에서 재산출.
rho_null_sd <- 1/sqrt(K-1)
mde_rho_iid <- 1.96*rho_null_sd/sqrt(NM)
## ---- (C) ★paired Δ적중률 MDE — 정답지 일치율 a 로 정확 산출 ----
##  귀무: 기준이 두 정답지 어느 쪽도 모름(월별 균등 픽). 두 정답지가 일치한 월(비율 a)은
##  Δ 에 구조적으로 0 을 기여하므로 유효 표본 = 불일치 월 n_disc 만.
n_disc <- round(NM*(1-a))
var_dhit <- n_disc*(2/K)/NM^2; sd_dhit <- sqrt(var_dhit)
mde_dhit_1s <- 1.645*sd_dhit; mde_dhit_2s <- 1.96*sd_dhit
## 시뮬레이션 확인 (해석식 검산 — 결과 아님)
set.seed(20260822L)
sim <- replicate(20000L, { pick <- sample.int(K, NM, replace=TRUE)
  mean(pick==P1$ret_best) - mean(pick==P1$ic_best) })
## ---- (D) ★검정력 전이 — "IC 정답지로는 애초에 못 볼 신호" 의 정량화 ----
##  기준이 ret_best 를 확률 h 로 맞히고 나머지는 균등이라 가정하면
##  h_IC = h*a + (1-h)*(1-a)/(K-1)  ⇒ IC 게이트 MDE(0.2443)에 해당하는 h_RET 를 역산.
base_IC <- (1-a)/(K-1); slope <- a - base_IC
h_ret_needed_for_IC_gate <- (mde_hit - base_IC)/slope
PRE <- list(
  task_id="WT-D20260822_008", fq_ref="FQ-246 NP2", round_id=sprintf(
    "FQ-246_NP2_consumption_matched_selection_target_WT-D20260822_008_%s", format(Sys.Date(),"%Y%m%d")),
  sealed_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  terminal_form="diagnostic_criterion_validity",
  capital_eligible=FALSE,
  capital_note=paste0("★정답지(top-25 실현수익)는 구성상 사후 정보(look-ahead)다. 본 라운드는 '그 정답지를 ",
    "맞히는 기준이 존재하는가' 만 묻는다. 어떤 산출로도 자본·성과를 주장하지 않는다(주장 시 AX-002). ",
    "α̂ 미방출 · alpha_vector 미방출 · canonical_screen_bt 성과 arm 미측정."),
  design=list(
    principle="기준·K·창을 전부 고정하고 **정답지만** 교체하는 paired 대조",
    criteria_source="stage_artifacts/WT-D20260822_007/p3_partB.rds::CRIT (221x5x4) — 재계산 아님, 비트-동일 승계",
    criteria=c("breadth(top-25 꼬리질량)","margin(top-25 경계마진)","centrality(팩터-간 상충도)","stability(순위지속성)"),
    directions=8L, control_arms=c("selrank1(성과-파생, WT-007 승계)","lag1_winner(전월 실현 승자 — 지속성 대조, 본 라운드 신규)",
                                  "ORACLE 자기-정답지(양성 대조·전도성)","무작위 픽(음성 대조)"),
    key_control="rank-IC argmax (icm) — WT-007 재현, 패리티 확인 완료",
    key_treatment="top-25 실현수익 argmax (ret_by_factor) — 소비면 정합",
    window=sprintf("%d개월 (%s ~ %s)", NM, P1$months[1], P1$months[NM]), K=K, top_n=P1$TOPN),
  measured_design_inputs=list(
    n_months=NM, K=K, chance_hit=p0,
    key_agreement_rate=a, n_discordant_months=n_disc,
    cross_key_mean_rho=mean(P1$rho_keys, na.rm=TRUE),
    note="이 3값은 정답지 **구조**이지 가설의 결과가 아니다 — 기준×정답지 통계량은 봉인 후 산출."),
  MDE_precomputed=list(
    marginal_hit_binom_1s5pct=mde_hit,
    marginal_hit_excess_pp=(mde_hit-p0)*100,
    top2_hit_binom_1s5pct=mde_hit2, top2_chance=2/K,
    rho_iid_analytic_95=mde_rho_iid, rho_null_sd_K5=rho_null_sd,
    paired_dhit_sd_null=sd_dhit, paired_dhit_mde_1s=mde_dhit_1s, paired_dhit_mde_2s=mde_dhit_2s,
    paired_dhit_sim_sd=sd(sim), paired_dhit_sim_q95=unname(quantile(sim,0.95)),
    sim_n=20000L,
    note="paired MDE 는 정답지 일치율 a 에서 정확 산출 — 일치 월은 Δ 에 구조적 0 을 기여하므로 유효 표본 = 불일치 월"),
  power_transfer=list(
    claim="IC 정답지 게이트는 소비면 신호에 대해 **구조적으로 둔감**하다 — 그 둔감함을 사전에 정량화한다",
    h_IC_intercept_if_uninformative_about_IC=base_IC, slope_dh_IC_per_dh_RET=slope,
    h_RET_needed_to_trip_IC_gate=h_ret_needed_for_IC_gate,
    h_RET_needed_to_trip_RET_gate=mde_hit,
    interpretation=sprintf(paste0("IC 정답지로는 h_RET >= %.4f 여야 게이트가 발화하는데, RET 정답지로는 ",
      "h_RET >= %.4f 면 발화한다. 즉 WT-007 의 9/9 null 은 h_RET ∈ [%.4f, %.4f) 구간의 신호를 ",
      "**볼 수 없었다**. 이 구간의 존재가 본 라운드의 존재 이유이며, 본 라운드가 null 이면 그 구간도 함께 배제된다."),
      h_ret_needed_for_IC_gate, mde_hit, mde_hit, h_ret_needed_for_IC_gate)),
  primary_statistics=list(
    P1="hit_RET — 기준 argmax 팩터 == ret_by_factor argmax 인 월 비율. 단측 이항 vs p0=0.2",
    P2="rho_RET — 월별 Spearman(기준값, ret_by_factor) across K, MIN 방향은 부호 반전. 평균의 NW3 t"),
  secondary_statistics=list(
    S1="hit2_RET — 기준 argmax 팩터가 ret 순위 top-2 에 드는 비율. 우연 0.4 (검정력 축)",
    S2="SELVAL_ann_pct — mean_m(ret_by_factor[m, 선택] - mean_k ret_by_factor[m,k])*12*100, NW3 t (연속 축, 적중률보다 고검정력)",
    S3="IC 공간 대칭 통계량 (paired 좌표 정합용)"),
  paired_statistics=list(
    D1="Δhit = hit_RET - hit_IC (기준별). McNemar 정규근사 + 위 시뮬 귀무분포",
    D2="Δrho 계열 = rho_RET(m) - rho_IC(m) 의 평균, NW3 t"),
  gates=list(
    transport_pass_raw="hit_p_binom < 0.05 OR |rho_t_nw3| >= 1.5 (WT-007 규칙 승계 — 대조 동형성 보존)",
    transport_pass_adjusted="Bonferroni over 8 방향: hit_p_binom < 0.00625 OR |rho_t_nw3| >= 2.734",
    multiplicity_rule="raw·adjusted 양쪽 보고. **헤드라인 판정은 adjusted 기준**(WT-007 은 8방향 보정을 하지 않았음 — 본 라운드에서 보강)",
    paired_pass=sprintf("|Δhit| >= %.4f (양측 5%%, 시뮬 귀무) 또는 Δrho NW3 |t| >= 1.96", mde_dhit_2s),
    threshold_freeze="★문턱 사후 완화 금지. 미달 시 완화가 아니라 미결/효과없음 라벨로 강등한다(WT-007 선례)"),
  labels=list(
    TRANSPORT_ESTABLISHED="게이트 통과 — 기준이 소비면 정답지를 안다",
    POWERED_NULL_CRITERION_UNINFORMATIVE="미통과 ∧ |rho|+MDE95 < 0.15 ∧ hit 관측이 MDE 밖 — 효과 없음(미결 아님)",
    UNRESOLVED_UNDERPOWERED="미통과 ∧ 관측이 MDE 안 — 미결",
    KEY_SWAP_MATERIAL="Δ 게이트 통과 — 정답지 교체가 기준의 정보량을 유의하게 바꿈",
    KEY_SWAP_NULL="Δ 게이트 미통과 — 정답지 교체가 기준의 정보량을 바꾸지 않음"),
  conductivity_requirement=paste0("측정 전 **전도성 먼저**: 게이트에 (i) 자기-정답지 오라클 기준(hit=1.0 기대) ",
    "(ii) 잡음 주입 오라클 사다리 3단 (iii) 균등 무작위(hit≈0.2 기대) 를 통과시켜, 게이트가 ",
    "존재하는 정보를 실제로 검출하는지 실증한 뒤에만 본 기준 결과에 판정 자격을 부여한다."),
  prohibitions=c("정답지로 자본·성과 주장(AX-002)","공분산·weight·최적화","ML 사이징/selection",
    "sweep 의 DSR 회피 — 챔피언 argmax 선발 금지(전 방향 독립 라벨 유지)",
    "graduation 주장","문턱 사후 완화","Production Constraints 를 레버로 제시"),
  inherited_anchors_with_units=list(
    ORACLE_K_IC_port_t=4.646999095, ORACLE_K_RET_port_t=8.8381268503,
    ORACLE_K_RET_paired_ann_pct=31.492557813, oracle_ret_over_ic_multiple=2.2999022859,
    WT007_hit_range=c(0.17194570,0.23076923), WT007_max_abs_rho=0.0413,
    WT007_binom_MDE=0.2443, WT007_rho_MDE95_mean=0.073679157357,
    collision_warning=paste0("★규율 6 — 'SELSPACE_headroom_ann_pct %.6f %%p/yr'(선택공간 내부, 본 라운드 신규) 와 ",
      "'ORACLE_K_RET paired 31.492558 %%p/yr'(C0 결합 대비 포트 net active) 는 **다른 양**이다. ",
      "인용 시 이름과 경로를 함께 적을 것.") ))
PRE$inherited_anchors_with_units$collision_warning <- sprintf(
  PRE$inherited_anchors_with_units$collision_warning, P1$selspace_head)
write_json(PRE, file.path(OUT,"PREREG.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=12)
cat("=== 사전 계산된 MDE ===\n")
cat(sprintf("  한계 적중률 (이항 단측 5%%, n=%d, p0=%.3f)     = %.6f  (우연 대비 +%.3f pp)\n", NM, p0, mde_hit, (mde_hit-p0)*100))
cat(sprintf("  top-2 멤버십 (우연 %.3f)                        = %.6f\n", 2/K, mde_hit2))
cat(sprintf("  rho 해석적 95%% (K=5 귀무 sd %.3f)               = %.6f\n", rho_null_sd, mde_rho_iid))
cat(sprintf("  ★paired Δhit: 불일치 월 %d · 귀무 sd %.6f\n", n_disc, sd_dhit))
cat(sprintf("     단측 MDE %.6f · 양측 MDE %.6f · 시뮬 sd %.6f · 시뮬 q95 %.6f\n",
            mde_dhit_1s, mde_dhit_2s, sd(sim), quantile(sim,0.95)))
cat("=== 검정력 전이 (사전 산출) ===\n")
cat(sprintf("  IC 정답지 게이트 발화에 필요한 h_RET = %.6f\n", h_ret_needed_for_IC_gate))
cat(sprintf("  RET 정답지 게이트 발화에 필요한 h_RET = %.6f\n", mde_hit))
cat(sprintf("  ⇒ WT-007 이 볼 수 없던 구간 = h_RET ∈ [%.4f, %.4f)\n", mde_hit, h_ret_needed_for_IC_gate))
cat("\n[sealed] PREREG.json\nOK\n")
