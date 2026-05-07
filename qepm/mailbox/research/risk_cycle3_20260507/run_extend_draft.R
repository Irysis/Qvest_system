suppressPackageStartupMessages({library(jsonlite); library(data.table)})

j <- read_json("qepm/mailbox/research/risk_cycle3_20260507/risk_package_draft.json", simplifyVector=FALSE)

# Read robustness CSVs
jc_dt <- fread("qepm/mailbox/research/risk_cycle3_20260507/robust_jc_BB7_pairwise_tdc.csv")
dcc_dt <- fread("qepm/mailbox/research/risk_cycle3_20260507/robust_dcc_garch_summary.csv")
boot_dt <- fread("qepm/mailbox/research/risk_cycle3_20260507/robust_bootstrap_crisis_pass_ci.csv")

# Add robustness extension as new section
j$axis_4_robustness_extensions <- list(
  purpose = "Cycle 3 axis 1~3 robustness 보강 — Joe-Clayton parametric TDC + DCC-GARCH dynamic + Bootstrap CI",
  jc_BB7_clayton_gumbel_decomposition = list(
    method = "Clayton (lower TDC) + Gumbel (upper TDC) separate fitCopula MPL — Joe-Clayton (BB7) 부재 환경 우회",
    pairs_fit = lapply(seq_len(nrow(jc_dt)), function(i) {
      list(
        pair = jc_dt$pair[i],
        src_a = jc_dt$src_a[i], src_b = jc_dt$src_b[i],
        clayton_theta = round(as.numeric(jc_dt$theta_BB7[i]), 4),
        gumbel_delta = round(as.numeric(jc_dt$delta_BB7[i]), 4),
        lambda_L_lower_TDC = signif(as.numeric(jc_dt$lambda_L_lower_TDC[i]), 4),
        lambda_U_upper_TDC = signif(as.numeric(jc_dt$lambda_U_upper_TDC[i]), 4),
        log_likelihood = round(as.numeric(jc_dt$log_likelihood[i]), 4)
      )
    }),
    key_finding = "AR-VRP / KR10y-VRP / DEF-VRP는 Clayton theta < 0 → lower TDC = 0 (negative dependence). COM-VRP가 lower TDC 0.028 + upper 0.149로 가장 큰 positive dependence. 사이클 2 axis_4 empirical TDC (VRP-Hybrid 0.077) 일관 — VRP는 directional negative하지만 lower-tail co-loss 무, opposite-direction movement 정합성 입증"
  ),
  dcc_garch_dynamic_correlation_3src = list(
    method = "rmgarch::dccfit (DCC(1,1) + sGARCH(1,1) Student-t marginals)",
    sample = "ret3 (AR/KR10y/TSMOM) post-2015 n=135",
    summary = list(
      AR_KR_dynamic_mean = round(dcc_dt[metric=="AR_KR_mean", value], 4),
      AR_KR_static = round(dcc_dt[metric=="static_AR_KR", value], 4),
      AR_TS_dynamic_mean = round(dcc_dt[metric=="AR_TS_mean", value], 4),
      AR_TS_static = round(dcc_dt[metric=="static_AR_TS", value], 4),
      KR_TS_dynamic_mean = round(dcc_dt[metric=="KR_TS_mean", value], 4),
      KR_TS_static = round(dcc_dt[metric=="static_KR_TS", value], 4),
      crisis_n = round(dcc_dt[metric=="crisis_n", value], 0),
      crisis_AR_KR = round(dcc_dt[metric=="crisis_AR_KR_mean", value], 4),
      crisis_AR_TS = round(dcc_dt[metric=="crisis_AR_TS_mean", value], 4),
      crisis_KR_TS = round(dcc_dt[metric=="crisis_KR_TS_mean", value], 4)
    ),
    key_finding = "DCC dynamic correlation은 static에 매우 가까움 (AR_KR -0.115 vs -0.122, AR_TS 0.063 vs 0.075, KR_TS 0.159 vs 0.119). KR 3-source는 시계열 dynamics 약함 — 사이클 3 axis 3의 정적 Sample covariance 사용 정당화. 단 6-source 확장 + crisis n=14 DCC fit은 차후 보강 필요 (사이클 4 topic_4 inheritance)"
  ),
  bootstrap_crisis_pass_rate_ci_1000_trials = list(
    method = "사이클 2 axis_3 stress 결과 bootstrap CI 보강. 1000 trial × bottom 10% Hybrid q-cutoff",
    samples_used = list(
      sample_256m_full = "n=254 (1990~2026, defensive/vrp/currency available)",
      sample_192m_post2010 = "n=192 (2010-04~ commodity GLD/COPX since)"
    ),
    results = lapply(seq_len(nrow(boot_dt)), function(i) {
      list(
        sample = boot_dt$sample[i],
        candidate = boot_dt$candidate[i],
        crisis_pass_mean = round(as.numeric(boot_dt$crisis_pass_mean[i]), 4),
        crisis_pass_median = round(as.numeric(boot_dt$crisis_pass_median[i]), 4),
        ci_2_5pct = round(as.numeric(boot_dt$ci_2_5pct[i]), 4),
        ci_97_5pct = round(as.numeric(boot_dt$ci_97_5pct[i]), 4),
        ci_width = round(as.numeric(boot_dt$ci_width[i]), 4),
        sd = round(as.numeric(boot_dt$sd[i]), 4)
      )
    }),
    key_finding = "VRP crisis PASS rate = 100% (CI [1.0, 1.0]) on both samples — VRP 가장 robust crisis hedge. Defensive 88~91% (CI [0.73, 1.0]) + Commodity 85% (CI [0.65, 1.0] 가장 wide) + Currency 89% (CI [0.76, 1.0]). 사이클 2 'VRP highest crisis alpha' finding 강력 입증 (Codex C4 사이클 2 disposition bootstrap CI 부재 critique 부분 해소)"
  ),
  artifacts = c(
    "qepm/mailbox/research/risk_cycle3_20260507/robust_jc_BB7_pairwise_tdc.csv",
    "qepm/mailbox/research/risk_cycle3_20260507/robust_dcc_garch_summary.csv",
    "qepm/mailbox/research/risk_cycle3_20260507/robust_dcc_garch_dynamic_correlation.csv",
    "qepm/mailbox/research/risk_cycle3_20260507/robust_bootstrap_crisis_pass_ci.csv",
    "qepm/mailbox/research/risk_cycle3_20260507/robustness_results.json"
  )
)

j$version <- "v1_draft_pre_codex_with_robustness"

write_json(j, "qepm/mailbox/research/risk_cycle3_20260507/risk_package_draft.json",
           pretty=TRUE, auto_unbox=TRUE, na="null", null="null")
cat("Robustness extension added to draft.\n")
