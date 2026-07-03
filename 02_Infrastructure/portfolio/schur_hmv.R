## ============================================================================
## schur_hmv.R — DEPRECATED SHIM. Canonical impl: frontier_hrp/cotton_schur.R
## ----------------------------------------------------------------------------
## The original schur_hmv.R transcribed the paper's Table 1 LITERALLY
## (intra-group A'' = Ac/(bA bA^T) element-wise + inter-group fitness bA^T Ac^{-1} bA
##  + per-level renormalization). That transcription FAILS the paper's own
## replication theorem: it does not recover minimum variance at gamma=1
## (max weight error ~0.048 on a 6-asset case) and breaks the 3-asset
## equal-correlation symmetry (returns 0.263/0.368/0.368 instead of 1/3,1/3,1/3).
##
## Root cause: A'' = Ac/(bA bA^T) yields the within-group shape diag(bA) Ac^{-1} bA,
## off by a diag(bA) factor from the true min-var subvector Ac^{-1} bA (eq 8.1).
## The exact realization propagates the rhs vector b through the recursion and
## does NOT renormalize between levels (see cotton_schur.R FAITHFULNESS NOTE).
##
## This shim re-exports the corrected functions under the old names so any legacy
## caller keeps working while getting the correct behavior.
## ============================================================================
local({
  .here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
  cand <- c(
    file.path(getwd(), "frontier_hrp", "cotton_schur.R"),
    file.path(getwd(), "02_Infrastructure", "portfolio", "frontier_hrp", "cotton_schur.R"),
    if (!is.null(.here)) file.path(.here, "frontier_hrp", "cotton_schur.R"),
    Sys.getenv("QM_ROOT", NA)
  )
  qm <- Sys.getenv("QM_ROOT", "")
  if (nzchar(qm)) cand <- c(cand, file.path(qm, "02_Infrastructure", "portfolio", "frontier_hrp", "cotton_schur.R"))
  path <- cand[file.exists(cand)][1]
  if (is.na(path) || is.null(path)) stop("cotton_schur.R not found; source it directly from frontier_hrp/")
  sys.source(path, envir = globalenv())
})

## ---- legacy API mapping (old names -> corrected impl) ----------------------
schur_seriation   <- function(S) cotton_seriation(S)
schur_weak_shrink <- function(S, grid = seq(1, 0.5, by = -0.02)) cotton_weak_shrink(S, grid)

## schur_hmv(S, gamma, term, shrink, long_only, ub): old signature preserved.
schur_hmv <- function(S, gamma = 0.5, term = 5, shrink = TRUE, long_only = TRUE, ub = 0.20) {
  cotton_schur(S, gamma = gamma, term = term, shrink = shrink,
               adaptive = TRUE, long_only = long_only, ub = ub)
}

schur_hmv_validate <- function(verbose = TRUE) cotton_schur_validate(verbose)
