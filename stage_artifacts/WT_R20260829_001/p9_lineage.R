## p9_lineage.R — R11 lineage 의무 (alpha_package.json write **후** 호출 — L-194 순서 규약)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-R20260829_001",
  package_type = "alpha_package",
  method_selected = "독립 2-way 3분위 정렬 교집합 (M02_Mom_6_1 x C01_SUE, min-rank 절단, top-25 EW long-only, 15bps) — CJL1996 Section III.A",
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-R20260829_001/request.json",
    "qepm/mailbox/worktask/WT-R20260829_001/alpha_hypothesis.json",
    ".cache/rawdata.parquet",
    "02_Infrastructure/factor_db/factor_registry.json",
    "stage_artifacts/WT_R20260829_001/panel_factors.parquet",
    "stage_artifacts/WT_R20260829_001/panel_returns.parquet",
    "stage_artifacts/WT_R20260829_001/panel_bench.parquet",
    "stage_artifacts/WT_R20260829_001/panel_liq.parquet",
    "stage_artifacts/WT_R20260829_001/alpha_scores.parquet"
  ),
  windows = list(sig_start = "2005-01-31", sig_end = "2026-08-28",
                 n_signal_months = 260L, n_return_months = 259L),
  extra = list(
    wt_type = "reinforcement",
    reinforce_attempt = "1/20",
    base_id = "RP_20260829_122020_9192",
    metric_type = "canonical_screen",
    selection_type = "chain",
    n_trials = 5L,
    canonical_port_t_nw_lag3 = 0.503698,
    preregistered_primary_verdict = "FAIL_AS_PREREGISTERED (T1 layer-avg NW-t 1.291, power 45.5% -> 미결)",
    decisive_verdict = "T2 REJECTED powered null (NW-t 0.150, power 100%)",
    no_signal_gate = "INDISTINGUISHABLE_FROM_NO_SIGNAL",
    self_pit_check_verdict = "fail_lookahead_suspected",
    engines = paste(c("p1_build_panel.R","p2_measure.R","p3_diagnostics.R","p4_pit_gate.R",
                      "p5_emit.R","p7_nosignal_fix.R","p8_universe_v2.R"), collapse=",")
  )
)
cat("[p9] lineage recorded\n")
