cat("=== STR_1425: S3 Orthogonality Analysis ===\n")
## 핵심아이디어: Grade A 참조군 대비 적응형 IC 회전 전략의 독립성 측정

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# --- 0. Config ---
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure", "config.R"))

STR_DIR <- file.path(ROOT, "04_Research/strategies/STR_1425_adaptive_ic_rotation")
ART_DIR <- file.path(STR_DIR, "stage_artifacts")
if (!dir.exists(ART_DIR)) dir.create(ART_DIR, recursive = TRUE)

# --- 1. Helper: extract monthly returns from sim_result.rds ---
extract_monthly_ret <- function(path) {
  if (!file.exists(path)) return(NULL)
  x <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(x)) return(NULL)

  daily <- NULL

  # Format 1: list with DAILY_NAV_DT$Strategy_Ret

if (is.list(x) && "DAILY_NAV_DT" %in% names(x)) {
    dt <- as.data.table(x$DAILY_NAV_DT)
    if ("Strategy_Ret" %in% names(dt) && "Date" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      daily <- dt[, .(Date, Ret = as.numeric(Strategy_Ret))]
    }
  }

  # Format 2: list with PORTFOLIO_LOG$NAV
  if (is.null(daily) && is.list(x) && "PORTFOLIO_LOG" %in% names(x)) {
    dt <- as.data.table(x$PORTFOLIO_LOG)
    if ("NAV" %in% names(dt) && "Date" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      setorder(dt, Date)
      dt[, Ret := NAV / shift(NAV, 1) - 1]
      daily <- dt[!is.na(Ret), .(Date, Ret)]
    }
  }

  # Format 3: list with port
  if (is.null(daily) && is.list(x) && "port" %in% names(x)) {
    dt <- as.data.table(x$port)
    if ("Ret" %in% names(dt) && "Date" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      daily <- dt[, .(Date, Ret = as.numeric(Ret))]
    }
  }

  # Format 4: direct data.table
  if (is.null(daily) && is.data.frame(x)) {
    dt <- as.data.table(x)
    if ("Ret" %in% names(dt) && "Date" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      daily <- dt[, .(Date, Ret = as.numeric(Ret))]
    }
  }

  if (is.null(daily) || nrow(daily) < 20) return(NULL)

  # Aggregate daily -> monthly
  daily[, YM := format(Date, "%Y-%m")]
  monthly <- daily[, .(MRet = prod(1 + Ret, na.rm = TRUE) - 1), by = YM]
  setorder(monthly, YM)
  return(monthly)
}

# --- 2. Load target strategy ---
cat("[1/4] Loading STR_1425 returns...\n")
target_path <- file.path(STR_DIR, "sim_result.rds")
target_m <- extract_monthly_ret(target_path)
stopifnot(!is.null(target_m))
cat("  -> ", nrow(target_m), " months loaded\n")

# --- 3. Grade A references ---
cat("[2/4] Loading Grade A references...\n")
ref_list <- list(
  STR_1433 = file.path(ROOT, "04_Research/strategies/STR_1433_consgate_c11fix_dd722/sim_result.rds"),
  STR_1375 = file.path(ROOT, "04_Research/strategies/STR_1375_5sleeve_cons_heavy/sim_result.rds"),
  STR_1071 = file.path(ROOT, "04_Research/strategies/STR_1071_noShortDD_mrs1225/sim_result.rds"),
  STR_1033 = file.path(ROOT, "04_Research/strategies/STR_1033_nco/sim_result.rds"),
  STR_1060 = file.path(ROOT, "04_Research/strategies/STR_1060_brk02_no_short_dd/sim_result.rds"),
  STR_1435 = file.path(ROOT, "04_Research/strategies/STR_1435_5sleeve_dd620_repair/sim_result.rds")
)

ref_monthly <- lapply(ref_list, extract_monthly_ret)
ref_ok <- !sapply(ref_monthly, is.null)
cat("  -> Loaded", sum(ref_ok), "/", length(ref_list), "references\n")

# --- 4. Spearman correlations vs Grade A ---
cat("[3/4] Computing Spearman correlations vs Grade A...\n")
corr_results <- list()
for (nm in names(ref_monthly)[ref_ok]) {
  ref <- ref_monthly[[nm]]
  merged <- merge(target_m, ref, by = "YM", suffixes = c("_tgt", "_ref"))
  if (nrow(merged) >= 12) {
    cr <- cor(merged$MRet_tgt, merged$MRet_ref, method = "spearman", use = "complete.obs")
    corr_results[[nm]] <- round(cr, 4)
    cat(sprintf("  %s: rho = %.4f (n=%d months)\n", nm, cr, nrow(merged)))
  } else {
    cat(sprintf("  %s: insufficient overlap (%d months)\n", nm, nrow(merged)))
  }
}

# --- 5. Lineage comparison (adaptive/rotation/ic_ strategies) ---
cat("[4/4] Searching lineage strategies...\n")
all_strs <- list.dirs(file.path(ROOT, "04_Research/strategies"), full.names = TRUE, recursive = FALSE)
lineage_pattern <- "adaptive|rotation|ic_"
lineage_dirs <- all_strs[grepl(lineage_pattern, basename(all_strs), ignore.case = TRUE)]
# Exclude self
lineage_dirs <- lineage_dirs[!grepl("STR_1425_adaptive_ic_rotation$", lineage_dirs)]

lineage_corrs <- list()
for (ld in lineage_dirs) {
  sr_path <- file.path(ld, "sim_result.rds")
  m <- extract_monthly_ret(sr_path)
  if (!is.null(m)) {
    merged <- merge(target_m, m, by = "YM", suffixes = c("_tgt", "_lin"))
    if (nrow(merged) >= 12) {
      cr <- cor(merged$MRet_tgt, merged$MRet_lin, method = "spearman", use = "complete.obs")
      nm <- basename(ld)
      lineage_corrs[[nm]] <- round(cr, 4)
      cat(sprintf("  Lineage %s: rho = %.4f (n=%d)\n", nm, cr, nrow(merged)))
    }
  }
}
if (length(lineage_corrs) == 0) cat("  -> No lineage strategies with sufficient data found\n")

# --- 6. Novelty score ---
abs_corrs <- abs(unlist(corr_results))
if (length(abs_corrs) >= 3) {
  top3 <- sort(abs_corrs, decreasing = TRUE)[1:3]
} else {
  top3 <- abs_corrs
}
novelty_score <- round(1 - mean(top3), 4)
cat(sprintf("\n=== Novelty Score: %.4f ===\n", novelty_score))
cat(sprintf("  (1 - mean(top3 abs corr): 1 - %.4f = %.4f)\n", mean(top3), novelty_score))

# --- 7. Summary ---
max_corr_name <- names(which.max(abs(unlist(corr_results))))
max_corr_val  <- unlist(corr_results)[max_corr_name]
min_corr_name <- names(which.min(abs(unlist(corr_results))))
min_corr_val  <- unlist(corr_results)[min_corr_name]

cat("\n--- S3 Summary ---\n")
cat(sprintf("  Most similar Grade A:  %s (rho=%.4f)\n", max_corr_name, max_corr_val))
cat(sprintf("  Most different Grade A: %s (rho=%.4f)\n", min_corr_name, min_corr_val))
cat(sprintf("  Novelty score: %.4f\n", novelty_score))
cat(sprintf("  Candidate role hint: diversifier\n"))

# --- 8. Save JSON artifact ---
artifact <- list(
  stage       = "S3",
  strategy    = "STR_1425_adaptive_ic_rotation",
  description = "Adaptive IC rotation with 5 factors",
  s2_grade    = "C",
  s2_sr       = 0.812,
  grade_a_correlations = corr_results,
  lineage_correlations = if (length(lineage_corrs) > 0) lineage_corrs else "none_found",
  top3_abs_corr        = as.list(round(top3, 4)),
  novelty_score        = novelty_score,
  candidate_role_hint  = "diversifier",
  most_similar         = list(name = max_corr_name, rho = unname(max_corr_val)),
  most_different       = list(name = min_corr_name, rho = unname(min_corr_val)),
  note_s4_exists       = "S4 already completed: delta_sharpe=-0.212, KOSPI beat=TRUE",
  timestamp            = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

json_path <- file.path(ART_DIR, "s3_orthogonality_adaptive_ic.json")
write_json(artifact, json_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\nArtifact saved: %s\n", json_path))
cat("=== S3 Orthogonality Complete ===\n")
