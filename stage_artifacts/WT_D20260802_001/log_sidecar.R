# =============================================================================
# log_sidecar.R — WT-D20260802_001 / FQ-073
#   AST v1.1 Step 4 사이드카 **실전 레코드 1호** 기록.
#   lane="canonical_screen" (alpha 단계 스크리닝 판정 — 생존편향 없음, 기각분 포함 전량)
#   ast_features 는 ast_compile manifest 실산출을 그대로 전달 (손기입 금지).
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
`%||%` <- function(a, b) if (is.null(a)) b else a
source("02_Infrastructure/contracts/ast_sidecar.R")

z  <- readRDS(file.path(OUT, "fq073_ast_results.rds"))
dg <- readRDS(file.path(OUT, "fq073_diag_results.rds"))

before <- length(readLines(file.path(ROOT, "06_Registry/ast_structure_log.jsonl"), warn = FALSE))
cat(sprintf("[sidecar] BEFORE rows = %d\n", before))

n_ok <- 0L
for (fid in names(z$results)) {
  r <- z$results[[fid]]; mf <- z$manifests[[fid]]
  ok <- ast_sidecar_log(
    lane = "canonical_screen",
    strategy_id = paste0("WT_D20260802_001_FQ073_", fid),
    ast_features = mf$ast_features,
    metrics = list(
      port_t_nw            = r$portfolio_alpha_t_nw_lag3,
      port_t_pvalue        = r$portfolio_alpha_t_pvalue,
      information_ratio    = r$information_ratio,
      net_sr               = r$net_sr,
      turnover_annual      = r$turnover_annual,
      n_months             = r$n_months,
      metric_type          = r$metric_type,
      oos_retention        = NA_real_,   # forge-authoritative 아님 — alpha 단계 미산출
      ew_universe_port_t   = r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_
    ),
    extra = list(
      wt_id            = "WT-D20260802_001",
      factor_id        = fid,
      mode             = "QPM",
      selection_type   = "chain",
      active_regime    = NA_character_,
      judge_verdict    = NA_character_,
      governor_verdict = NA_character_,
      ast_verify_verdict = if (fid == "F1_export_surprise") "FAIL_CONTRACT(production_parity_verified)"
                           else "FAIL_CONTRACT(production_parity_verified)",
      escape_leaf_types  = "STORED_SCORE",
      cap_tier_weight_share_MEGA = r$diag_cap_tier$weight_share_avg$MEGA %||% NA_real_,
      cap_tier_weight_share_MID  = r$diag_cap_tier$weight_share_avg$MID  %||% NA_real_,
      cap_tier_weight_share_OTHER= r$diag_cap_tier$weight_share_avg$OTHER%||% NA_real_,
      vintage_basis      = "revised_asof_pull",
      map_vintage_mode   = "static_current",
      gate_eligible      = FALSE,
      lane_label         = "LANE_UPPER_BOUND_lookahead_inflated"
    ))
  n_ok <- n_ok + as.integer(isTRUE(ok))
  cat(sprintf("[sidecar] %-32s logged=%s nodes=%s\n", fid, isTRUE(ok),
              mf$ast_features$node_count %||% NA))
}

# F5 = 대형주 제한 변형 (F1 AST 동일, 유니버스만 제한) — 커버리지 완결 위해 함께 기록
if (!is.null(dg$F5)) {
  r <- dg$F5
  ok <- ast_sidecar_log(
    lane = "canonical_screen",
    strategy_id = "WT_D20260802_001_FQ073_F5_large_cap_restricted",
    ast_features = z$manifests$F1_export_surprise$ast_features,
    metrics = list(port_t_nw = r$portfolio_alpha_t_nw_lag3,
                   port_t_pvalue = r$portfolio_alpha_t_pvalue,
                   information_ratio = r$information_ratio,
                   turnover_annual = r$turnover_annual,
                   n_months = r$n_months, metric_type = r$metric_type),
    extra = list(wt_id = "WT-D20260802_001", factor_id = "F5_large_cap_restricted",
                 mode = "QPM", selection_type = "chain",
                 universe_override = "cap_rank<=100 within K200uKQ150",
                 gate_eligible = FALSE, lane_label = "LANE_UPPER_BOUND_lookahead_inflated"))
  n_ok <- n_ok + as.integer(isTRUE(ok))
  cat(sprintf("[sidecar] %-32s logged=%s\n", "F5_large_cap_restricted", isTRUE(ok)))
}

after <- length(readLines(file.path(ROOT, "06_Registry/ast_structure_log.jsonl"), warn = FALSE))
cat(sprintf("[sidecar] AFTER rows = %d (delta %d, 성공보고 %d)\n", after, after - before, n_ok))

if (exists("ast_sidecar_counts", mode = "function")) {
  cnt <- ast_sidecar_counts()
  cat("[sidecar] counts: ", toJSON(cnt, auto_unbox = TRUE), "\n")
}
