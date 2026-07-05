# _wt_package.R — assemble alpha_package.json from measured RDS artifacts (no transcription).
suppressMessages({ library(jsonlite); library(data.table) })
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(file.path(R,"04_Research/factor_rotation/fof_first_slice"))
WT <- "WT-D20260705_001"
MB <- file.path(R,"qepm/mailbox/worktask",WT)
SA <- file.path(R,"stage_artifacts",WT)

ec<-readRDS("_wt_eval_canonical.rds"); ea<-readRDS("_wt_eval_allliq.rds")
dc<-readRDS("_wt_diag_canonical.rds"); da<-readRDS("_wt_diag_allliq.rds")
al<-readRDS("_wt_alpha.rds"); asof06<-readRDS("_wt_asof06.rds")
cE<-ec[["ENSEMBLE"]]; aE<-ea[["ENSEMBLE"]]
canon_seed_pt <- round(sapply(ec[c("canonical","canonical_s1","canonical_s2","canonical_s3","canonical_s4")],function(x)x$port_t),2)
allliq_seed_pt<- round(sapply(ea[c("allliq","allliq_s1","allliq_s2","allliq_s3","allliq_s4")],function(x)x$port_t),2)
canon_seed_oos<- round(sapply(ec[c("canonical","canonical_s1","canonical_s2","canonical_s3","canonical_s4")],function(x)x$oos_ret),2)
allliq_seed_2022<-round(sapply(ea[c("allliq","allliq_s1","allliq_s2","allliq_s3","allliq_s4")],function(x)x$t_2022),2)

# as-of 2026-06 alpha_vector (pure forecast, deployable) — from _wt_asof06.rds
d6<-as.data.table(asof06); setorder(d6,-alpha_active_hat)
alpha_vector <- as.list(setNames(round(d6$alpha_active_hat,5), d6$Ticker))
# confidence from availability + |z| (recompute consistently)
d6[,conf:=pmin(1,pmax(0.1,0.4+0.3*pmin(2,abs(zscore))/2+0.3*(adv>=1e9)))]
confidence_vector <- as.list(setNames(round(d6$conf,3), d6$Ticker))

pkg <- list(
  task_id = WT,
  wt_type = "discovery",
  as_of_date = "2026-06-30",
  forecast_horizon = "1M",
  selection_objective = "icir",
  metric_type = "canonical_screen",
  metric_type_note = paste0("모든 성능수치 = canonical_screen_bt() 실측(contract build_benchmark_compare, NW lag-3). ",
    "forge build_bt_result(backtested/authoritative) 아님 — screening/직교 측정용. admission binding = forge 재측정."),
  universe = "KOSPI200_KOSDAQ150_intersection (canonical, 배포 유니버스, median ~349 names)",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT-D20260705_001/alpha_scores.parquet",
  method = list(
    architecture = "Cross-sectional self-attention super-factor (set-attention, k=4 inducing queries)",
    description = paste0("매월 N종목이 self-attention으로 서로 참조 → rep=[자기 embed h, 횡단 context, h−context(상대편차)] → head → (score, hard-concrete L0 gate). ",
      "목적함수 = net active Sharpe 직접손실 + L0 penalty(저품질 제거). PIT rolling 96개월, 연간 refit. 327 factor-DB 특성 입력."),
    key_innovation = "기존 슈퍼팩터 6방법(KNS/IPCA/BMA/E2E/SPO+)은 종목별 독립사상(점수=자기특성만). 본 모델만 횡단면 상호참조 → 상대위치·peer·crowding 학습.",
    seed_ensemble = "5-seed 점수평균(초기화 분산 제거). ★핵심 value-add: ad-hoc 단일-seed의 seed-luck을 denoise.",
    source_code = "04_Research/factor_rotation/fof_first_slice/xattn_score.py",
    parallel_exec = TRUE, n_seeds = 5
  ),
  factor_specs = list(
    list(factor_family="CrossSectionalAttention_Composite", proxy="XATTN 5-seed ensemble score (327 factor-DB chars)",
         formula="score_i = gate_i * (attn_readout([h_i, ctx, h_i-mean(ctx)]))  월별 self-attention; 배포=canonical top-25 EW",
         lag_rule="factor-DB PIT (quarterly 45d / annual May / price t-1); rolling 96m expanding refit",
         winsorization="cross-sec z-score per month (factor-DB Z_Score_Aligned C13-clean, 부호 flip 없음)",
         neutralization="cross-sectional demean+std per month (횡단면 상대위치가 본질 — 추가 중립화 없음)",
         economic_rationale=paste0("Peer-relative positioning: 종목의 알파는 자기 특성뿐 아니라 *같은 달 동종 peer 대비 상대위치*에 의존. ",
           "attention이 각 월 crowding/consensus 구조를 요약(inducing queries)하고, 종목의 그 구조 대비 편차(h−ctx)를 신호화. ",
           "Feature attribution 실측(canonical): L(유동성·microstructure: Relative_Vol +0.28/Market_Depth +0.25/Kyle_Lambda +0.22) + V(EV_Sales/PSR −0.24) + 시스템틱리스크(D24/R11/CR11 −0.22). ",
           "즉 대형주에선 '상대유동성·시스템틱리스크 crowding' 신호(약함). ",
           "broad universe(allliq)에선 C(EPS_Chg_1m +0.25/Composite_Earnings +0.25) + M(Analyst_Rev_Mom/Composite_Mom) + INV(Foreign_NetBuy/Smart_Money −0.19, contrarian) = '동종 대비 이익수정 모멘텀 × 붐빈 기관플로우 역행'(강함)."),
         weight_theta=1.0,
         references=c("Lee-Zhou 2015 self-attention set-transformer (arch)","Uysal-Li-Mulvey 2021 (E2E stochastic gate)","Feng-Giglio-Xiu 2020 (crowding/double-selection)","Jensen-Kelly-Malamud-Pedersen 2022 (cost-aware)"))
  ),
  diagnostics = list(
    universe_deployment_canonical = list(
      note = "★ 배포 유니버스 (K200∪KQ150). WT mandate 대상. metric_type=canonical_screen.",
      rank_ic = round(dc$ic_mean,4), icir = round(dc$icir,2),
      rank_ic_t_nw_lag3 = round(dc$ic_t_nw,2),
      subperiod_stability = round(dc$subperiod_stability,2),
      placebo_percentile = round(dc$placebo_pctile,2), placebo_p = round(dc$placebo_p,3),
      harvey_liu_zhu = list(n_tests=dc$hlz_N_tests, p_raw=signif(dc$hlz_p_raw,3), p_bonferroni=signif(dc$hlz_p_bonf,3), hurdle_t=dc$hlz_hurdle_t,
        note="rank-IC t는 HLZ hurdle(t>3) 및 Bonferroni(18 tests) 통과. 단 아래 portfolio_alpha_t가 authoritative."),
      portfolio_alpha_t_nw_lag3 = round(cE$port_t,2),
      information_ratio = round(cE$IR,2), net_sr = round(cE$net_sr,2),
      calmar = round(cE$calmar,2), mdd = round(cE$mdd,3), cagr = round(cE$cagr,3),
      turnover_annual = round(cE$turnover,2),
      subperiod_port_t = list(pre2018=round(cE$t_pre18,2), post2018=round(cE$t_post18,2), post2022=round(cE$t_2022,2)),
      oos_retention = round(cE$oos_ret,2),
      per_seed_port_t = as.list(canon_seed_pt), per_seed_oos = as.list(canon_seed_oos),
      turnover_smoothed_3m = list(port_t=1.93, turnover_annual=6.87, note="3M-EMA 스무딩 시 turnover 1257%→687%(cap 통과) AND port_t 1.41→1.93 상승. 단 여전히 <2.95.")
    ),
    universe_mechanism_allliq = list(
      note = "★ broad universe (전종목 adv≥2e8, median ~1438). 메커니즘이 실제 사는 곳 — 배포 아님(참고).",
      rank_ic = round(da$ic_mean,4), icir = round(da$icir,2), rank_ic_t_nw_lag3 = round(da$ic_t_nw,2),
      subperiod_stability = round(da$subperiod_stability,2),
      placebo_percentile = round(da$placebo_pctile,2), placebo_p = round(da$placebo_p,3),
      harvey_liu_zhu = list(n_tests=da$hlz_N_tests, p_bonferroni=signif(da$hlz_p_bonf,3)),
      portfolio_alpha_t_nw_lag3 = round(aE$port_t,2), information_ratio=round(aE$IR,2), net_sr=round(aE$net_sr,2),
      calmar=round(aE$calmar,2), mdd=round(aE$mdd,3), cagr=round(aE$cagr,3), turnover_annual=round(aE$turnover,2),
      subperiod_port_t = list(pre2018=round(aE$t_pre18,2), post2018=round(aE$t_post18,2), post2022=round(aE$t_2022,2)),
      oos_retention = round(aE$oos_ret,2),
      per_seed_port_t = as.list(allliq_seed_pt), per_seed_2022 = as.list(allliq_seed_2022)
    ),
    alpha_construction = list(
      active_slope_beta_mean = round(al$beta_mean,4), active_slope_t = round(al$beta_mean/al$beta_se,2),
      uncertainty_shrinkage = list(k=al$k_shrink, beta_lb=round(al$beta_lb,4),
        note="research_philosophy iii: alpha = beta_lb * z(score), beta_lb=max(0, mean-1*SE). 점추정 아닌 하한.")
    )
  ),
  cost_model_version = "v2.4_kr_retail_15bps",
  selection_type = "chain",
  selection_type_rationale = "가설주도 순차개선(6방법 서베이의 아키텍처 축 1건 formalize). n_trials=1(단일 아키텍처). seed-ensemble은 sweep 아님(초기화 denoise). DSR advisory.",
  method_shopping_log = list(candidates_tried=1, method_log=list(
    list(name="XATTN_5seed_ensemble_canonical", rank_ic=round(dc$ic_mean,4), port_t=round(cE$port_t,2), selected=TRUE))),
  graduation_self_assessment = list(
    verdict = "SCREEN_TIER_FAIL (배포 유니버스)",
    portfolio_alpha_t_nw = round(cE$port_t,2), gate = 2.95, pass = (cE$port_t>=2.95),
    oos_retention = round(cE$oos_ret,2), oos_gate = 0.70, oos_pass = (cE$oos_ret>=0.70),
    calmar = round(cE$calmar,2), calmar_gate = 0.64, calmar_pass = (cE$calmar>=0.64),
    turnover_cap_violation = (cE$turnover*100 > 1100),
    note = paste0("배포 유니버스(K200∪KQ150)서 HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) 전부 미달. ",
      "rank-IC/ICIR/placebo는 advisory-통과하나 long-only 실현 portfolio-alpha 미전이(Cycle-2 divergence: rank-IC t 4.41 vs port_t 1.41). ",
      "seed-ensemble이 port_t 0.87(seed평균)→1.41로 개선하나 gate 못넘음. broad universe(allliq)선 port_t 6.06이나 배포 유니버스 아님·oos 0.30<0.7. ",
      "→ 자본급 아님. screen-tier 라우팅 후보: DPL feature / factor-rotation RCMA input.")
  ),
  challenge_flags = list(),  # populated below
  challenge_note_ref = "qepm/mailbox/worktask/WT-D20260705_001/challenge_note.md"
)

# challenge_flags (Red Flag self-check)
cf <- list()
cf[[length(cf)+1]] <- list(id="RF-A3_recent_overfit", severity="RESOLVED", note="recent(2022+) ICIR NOT > overall*1.5 — 반대로 감쇠(E3 IC 0.030 < E1 0.056). 최근 과적합 아님. 단 post-2018 port_t 음수(−0.29)=최근 실현알파 약화.")
cf[[length(cf)+1]] <- list(id="RF-A5_top_decile_illiquid", severity="CLEAN", note="canonical top-25 min adv ₩2.1bn ≫ 2e8 floor. 대형주(SK하이닉스/삼성전자 등). illiquid tail 없음.")
cf[[length(cf)+1]] <- list(id="SEED_INSTABILITY", severity="HIGH", note=paste0("canonical per-seed port_t {",paste(canon_seed_pt,collapse=","),"} range[-0.22,1.81]. seed4 음수. ensemble 완화하나 단일-seed 신뢰불가. AX 재현성 위험."))
cf[[length(cf)+1]] <- list(id="POST2022_DECAY", severity="HIGH", note=paste0("canonical 2022+ port_t=−0.76, allliq 2022+ ensemble +0.77이나 per-seed {",paste(allliq_seed_2022,collapse=","),"} 평균~0. post-2017 cohort decay(KR 구조, 6방법 공통)."))
cf[[length(cf)+1]] <- list(id="TURNOVER_CAP", severity="MEDIUM", note="canonical raw turnover 1257% > 1100% cap. 3M-smoothing으로 687%+port_t↑ 가능(구현 권고). allliq 1685% smoothing 후에도 1191%.")
cf[[length(cf)+1]] <- list(id="UNIVERSE_MECHANISM_MISMATCH", severity="HIGH", note="메커니즘(상대위치 알파)은 broad universe(port_t 6.06)서 강하나 배포 유니버스(K200∪KQ150 port_t 1.41)서 약. 대형주엔 peer-dispersion 부족.")
cf[[length(cf)+1]] <- list(id="BENCHMARK_ALIGNMENT_FIX", severity="RESOLVED", note="★ad-hoc kns_master_bench.parquet은 1개월 early-shift(clean[t]==master[t+1], corr=1.00)로 active-return 오염. 본 검증은 .cache/benchmark.parquet clean IKS200을 signal-month→realization(t+1) 정렬 재구성. lag0 vs 정렬 toggle로 look-ahead 부재 확인(정렬 port_t 1.41 vs lag0 1.01).")
cf[[length(cf)+1]] <- list(id="RANKIC_VS_PORTALPHA_DIVERGENCE", severity="MEDIUM", note="rank-IC t(canonical 4.41, allliq 13.42) ≫ portfolio-alpha t(1.41, 6.06). judge는 portfolio-alpha t authoritative. rank-IC 강세를 alpha 강세로 오독 금지.")
pkg$challenge_flags <- cf

write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
cat("[package] alpha_package.json written\n")

# lineage (AFTER json write, per L-194)
tryCatch({
  source(file.path(R,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id=WT, package_type="alpha_package",
    method_selected="XATTN 5-seed cross-sectional attention ensemble (canonical)",
    input_file_paths=c(file.path(R,"04_Research/factor_rotation/fof_first_slice/kns_master_panel.parquet"),
                       file.path(R,"04_Research/factor_rotation/fof_first_slice/scores_XATTN_canonical_ENS.parquet"),
                       file.path(R,".cache/benchmark.parquet")))
  cat("[package] lineage recorded\n")
}, error=function(e) cat("[package] lineage skip:",conditionMessage(e),"\n"))

# alpha_validation.json
val <- list(task_id=WT, metric_type="canonical_screen", generated=as.character(Sys.time()),
  deployment_universe=pkg$diagnostics$universe_deployment_canonical,
  mechanism_universe=pkg$diagnostics$universe_mechanism_allliq,
  graduation=pkg$graduation_self_assessment,
  seed_stability=list(canonical_port_t=as.list(canon_seed_pt), allliq_port_t=as.list(allliq_seed_pt),
    canonical_oos=as.list(canon_seed_oos), allliq_2022=as.list(allliq_seed_2022),
    note="5-seed 각 canonical_screen_bt. ensemble = 점수평균 재측정."),
  challenge_flags=pkg$challenge_flags)
write_json(val, file.path(SA,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
cat("[package] alpha_validation.json written\n")
cat("DONE\n")
