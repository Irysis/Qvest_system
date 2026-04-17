#' @title Backfill construction metadata for experiments.json
#' @description Parses each strategy's run_all.R to extract construction metadata
#'   (type, sleeves, overlays, weight method, N holdings) and updates experiments.json.

# ---- classify_construction ----

#' Classify construction from run_all.R code
#' @param run_all_path Path to a strategy's run_all.R
#' @return Named list with construction_type, n_sleeves, overlays, has_fm, weight_method, n_holdings
classify_construction <- function(run_all_path) {
  if (!file.exists(run_all_path)) {
    return(list(construction_type = "unknown", n_sleeves = 1L,
                overlays = list(), has_fm = FALSE,
                weight_method = "equal", n_holdings = 20L))
  }

  code <- paste(readLines(run_all_path, warn = FALSE), collapse = "\n")
  code_lower <- tolower(code)

  # Sleeve count
  sleeve_matches <- gregexpr("sim_sleeve_|sim_def|sim_ind|sim_cons|phase 1[a-h]", code_lower)[[1]]
  n_sleeves <- if (sleeve_matches[1] == -1L) 1L else max(1L, length(sleeve_matches))

  # Construction type
  type <- if (n_sleeves >= 4) "multi_sleeve_4plus"
          else if (n_sleeves == 3) "multi_sleeve_3"
          else if (n_sleeves == 2) "dual_sleeve"
          else "single_factor"

  # Overlays
  has_vt  <- grepl("vol_target|vt_target|exposure.*vol", code_lower)

  has_dd  <- grepl("dd_brake|drawdown.*brake|dd_exp|dd_med", code_lower)
  has_mrs <- grepl("soft.*mrs|mrs_score|macro_risk", code_lower)

  overlays <- c(
    if (has_vt) "vol_target",
    if (has_dd) "dd_brake",
    if (has_mrs) "soft_mrs"
  )
  if (length(overlays) == 0) overlays <- list()  # ensure JSON []

  # Factor Momentum
  has_fm <- grepl("factor.*momentum|fm_weight|trailing.*return.*sleeve|cum_def.*cum_ind", code_lower)

  # Weight method
  weight <- if (grepl("weight_method.*ivol|weighting.*ivol|ivol.*weight", code_lower)) "ivol"
            else "equal"

  # N holdings
  n_match <- regmatches(code, regexpr("n_holdings\\s*=\\s*\\d+|N\\s*<-\\s*\\d+|top_n\\s*=\\s*\\d+", code))
  n_holdings <- if (length(n_match) > 0) as.integer(gsub("\\D", "", n_match[1])) else 20L

  list(
    construction_type = type,
    n_sleeves         = n_sleeves,
    overlays          = as.list(overlays),
    has_fm            = has_fm,
    weight_method     = weight,
    n_holdings        = n_holdings
  )
}


# ---- backfill_construction ----

#' Backfill construction metadata for all experiments in experiments.json
#' @return Invisible NULL. Prints summary.
backfill_construction <- function() {
  library(jsonlite)

  PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT",
    unset = "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot")

  exp_path   <- file.path(PROJECT_ROOT, "qepm", "registry", "experiments.json")
  strat_base <- file.path(PROJECT_ROOT, "research_output", "strategies")

  if (!file.exists(exp_path)) stop("[backfill] experiments.json not found: ", exp_path)

  experiments <- fromJSON(exp_path, simplifyVector = FALSE)
  cat(sprintf("[backfill] Loaded %d experiments\n", length(experiments)))

  # Pre-list all strategy dirs once
  all_dirs <- list.dirs(strat_base, recursive = FALSE)
  dir_basenames <- basename(all_dirs)

  n_updated <- 0L
  type_counts <- list()

  for (i in seq_along(experiments)) {
    e <- experiments[[i]]
    strategy_id <- e$strategy_id %||% ""
    if (nchar(strategy_id) == 0) next

    # Find matching directory
    matched_idx <- which(grepl(strategy_id, dir_basenames, fixed = TRUE))
    if (length(matched_idx) == 0) next

    # Use the most recently modified directory if multiple matches
    matched_dirs <- all_dirs[matched_idx]
    if (length(matched_dirs) > 1) {
      mtimes <- file.mtime(matched_dirs)
      matched_dirs <- matched_dirs[which.max(mtimes)]
    }

    run_path <- file.path(matched_dirs[1], "run_all.R")
    if (!file.exists(run_path)) next

    # Classify and assign
    construction <- classify_construction(run_path)
    experiments[[i]]$construction <- construction
    n_updated <- n_updated + 1L

    # Track distribution
    ct <- construction$construction_type
    type_counts[[ct]] <- (type_counts[[ct]] %||% 0L) + 1L
  }

  # Save
  write_json(experiments, exp_path, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("\n[backfill] Updated %d / %d experiments with construction\n",
              n_updated, length(experiments)))
  cat("\n[backfill] Construction type distribution:\n")
  for (nm in sort(names(type_counts))) {
    cat(sprintf("  %-25s %d\n", nm, type_counts[[nm]]))
  }

  # Count remaining NULLs
  n_null <- sum(vapply(experiments, function(x) is.null(x$construction), logical(1)))
  cat(sprintf("\n[backfill] Remaining NULL construction: %d\n", n_null))

  invisible(NULL)
}

# Run if executed directly
if (sys.nframe() == 0) {
  backfill_construction()
}
