#!/usr/bin/env Rscript
# =============================================================================
# register_research_outputs.R — ML/DPL sweep 산출물 표준화 runner (sweep/cycle 끝에 호출).
# "마지막 다리": GPU sweep·DPL pilot·ML 앙상블이 끝나면 본 runner가 산출물을
#   register_ml_prediction/register_return_series 경유로 표준화한다. 계약 floor 없는 산출물은
#   stage_artifacts/module_quarantine/에 보관되며, FR 편입은 contract_pass/backtested/frozen floor 통과분만 허용.
# freshness: source가 canonical/quarantine sim_result.rds보다 새로울 때만 재등재(idempotent). ML pred는 백테 동반(heavy).
# Usage: Rscript register_research_outputs.R   (또는 run_ml_cycle.py 끝에서 system2 호출)
# 도훈 mandate 2026-06-05.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.find_root <- function() {
  script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) "")
  script_dir <- if (is.character(script_file) && nzchar(script_file)) dirname(script_file) else "."
  candidates <- unique(c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", ""),
    getwd(),
    normalizePath(file.path(script_dir, "../.."), mustWork = FALSE)
  ))
  is_root <- function(p) {
    nzchar(p) && dir.exists(p) &&
      file.exists(file.path(p, "02_Infrastructure/contracts/register_research_module.R"))
  }
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[register_research_outputs] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

PROJ <- .find_root(); setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/contracts/register_research_module.R"))
.newer <- function(src, sim) file.exists(src) && (!file.exists(sim) || file.info(src)$mtime > file.info(sim)$mtime)
.registered_artifact <- function(id) {
  canonical <- file.path("04_Research/strategies", id, "sim_result.rds")
  quarantine <- file.path("stage_artifacts/module_quarantine", id, "sim_result.rds")
  if (file.exists(canonical)) canonical else quarantine
}
n_reg <- 0L

# 1. ML 예측(per-ticker) → 일간 백테 → 등재. (heavy: 새로울 때만)
ml_specs <- list(list(pred=".cache/ml_momentum_pred.parquet", id="ML_momentum_ensemble"))
for(sp in ml_specs){
  sim <- .registered_artifact(sp$id)
  if(.newer(sp$pred, sim)){
    cat(sprintf("[register_research_outputs] ML 표준화(계약 없으면 quarantine): %s → %s\n", sp$pred, sp$id))
    tryCatch({ register_ml_prediction(as.data.table(read_parquet(sp$pred)), sp$id, origin_mode="ml", grade="ungraded"); n_reg<-n_reg+1L },
             error=function(e) cat("  ML 등재 실패:", conditionMessage(e), "\n"))
  } else cat(sprintf("[register_research_outputs] ML 최신 — skip: %s\n", sp$id))
}

# 2. DPL net return series → 등재 (fast). method=="DPL"만.
for(dplf in Sys.glob(file.path(PROJ, "stage_artifacts/*/dpl_pilot_net_returns.parquet"))){
  tag <- basename(dirname(dplf)); id <- paste0("DPL_", sub("^WT_", "", tag))
  sim <- .registered_artifact(id)
  if(.newer(dplf, sim)){
    dd <- as.data.table(read_parquet(dplf)); dd <- dd[method=="DPL"]
    if(nrow(dd) >= 36){ cat(sprintf("[register_research_outputs] DPL 표준화(계약 없으면 quarantine): %s → %s\n", tag, id))
      tryCatch({ register_return_series(dd, id, date_col="date", ret_col="ret_net", bm_col="BM_Ret",
                   origin_mode="dpl", grade="ungraded", role="ml_dpl"); n_reg<-n_reg+1L },
               error=function(e) cat("  DPL 등재 실패:", conditionMessage(e), "\n")) }
  } else cat(sprintf("[register_research_outputs] DPL 최신 — skip: %s\n", id))
}

cat(sprintf("[register_research_outputs] 완료 — %d개 신규/갱신 표준화. FR 편입은 floor 통과분만 허용.\n", n_reg))
