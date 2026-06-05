#==============================================================================
# 95_fred_parse_to_csv.R — Cycle 47B precondition
#
# Parses 4 FRED series from saved tool-results + Write files:
#   T10Y2Y     daily   1995+   (saved tool-result file)
#   ICSA       weekly  1990+   (saved tool-result file)
#   STLFSI4    weekly  1993+   (Write _fred_stlfsi4_cfnai.txt)
#   CFNAI      monthly 1967+   (Write _fred_stlfsi4_cfnai.txt)
#
# Output:
#   outputs/01_data/fred_us_macro_daily.csv
#     Date | t10y2y_raw | icsa_raw | cfnai_raw | stlfsi4_raw
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA <- file.path(WS, "outputs/01_data")

T10Y2Y_PATH <- "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/0ae30f53-36fd-40a5-ab40-e7b65756a52e/tool-results/mcp-fred-get_series-1779244182834.txt"
ICSA_PATH   <- "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/0ae30f53-36fd-40a5-ab40-e7b65756a52e/tool-results/mcp-fred-get_series-1779244576787.txt"
STLFSI_CFNAI_PATH <- file.path(DATA, "_fred_stlfsi4_cfnai.txt")

cat("\n========== Cycle 47B FRED parse ==========\n")

parse_mcp_series <- function(path, expected_label) {
  # Format: "<LABEL> (<N> obs):\nYYYY-MM-DD: <value>" lines.
  # Value "." or "" → NA.
  lines <- readLines(path, warn = FALSE)
  header_idx <- grep(sprintf("^%s \\(", expected_label), lines)
  if (length(header_idx) == 0) {
    stop(sprintf("Header for '%s' not found in %s", expected_label, path))
  }
  start_idx <- header_idx[1] + 1
  # End at next "##" or "<LABEL>" line if present
  end_idx <- length(lines)
  later_headers <- grep("^(##|[A-Z]+ \\()", lines[(start_idx+1):end_idx])
  if (length(later_headers) > 0) {
    end_idx <- start_idx + later_headers[1] - 1
  }
  data_lines <- lines[start_idx:end_idx]
  data_lines <- data_lines[grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}:", data_lines)]
  parts <- strsplit(data_lines, ":")
  dates <- as.Date(sapply(parts, function(x) trimws(x[1])))
  values <- as.numeric(sapply(parts, function(x) {
    v <- trimws(x[2])
    if (v %in% c(".", "", "NA")) NA_real_ else suppressWarnings(as.numeric(v))
  }))
  data.table(Date = dates, value = values)[!is.na(Date)]
}

parse_inline_section <- function(path, section_label) {
  # Path is a Write file with "## STLFSI4" or "## CFNAI" section headers.
  lines <- readLines(path, warn = FALSE)
  section_idx <- grep(sprintf("^## %s\\s*$", section_label), lines)
  if (length(section_idx) == 0) {
    stop(sprintf("Section '## %s' not found in %s", section_label, path))
  }
  start_idx <- section_idx[1] + 1
  next_section <- grep("^## ", lines[(start_idx+1):length(lines)])
  end_idx <- if (length(next_section) > 0) start_idx + next_section[1] - 1 else length(lines)
  data_lines <- lines[start_idx:end_idx]
  data_lines <- data_lines[grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}:", data_lines)]
  parts <- strsplit(data_lines, ":")
  dates <- as.Date(sapply(parts, function(x) trimws(x[1])))
  values <- as.numeric(sapply(parts, function(x) {
    v <- trimws(x[2])
    if (v %in% c(".", "", "NA")) NA_real_ else suppressWarnings(as.numeric(v))
  }))
  data.table(Date = dates, value = values)[!is.na(Date)]
}

# Parse
t10y2y_dt <- parse_mcp_series(T10Y2Y_PATH, "T10Y2Y")
icsa_dt   <- parse_mcp_series(ICSA_PATH, "ICSA")
stlfsi_dt <- parse_inline_section(STLFSI_CFNAI_PATH, "STLFSI4")
cfnai_dt  <- parse_inline_section(STLFSI_CFNAI_PATH, "CFNAI")

cat(sprintf("[T10Y2Y]  obs=%d  range=%s ~ %s\n",
            nrow(t10y2y_dt),
            as.character(min(t10y2y_dt$Date)),
            as.character(max(t10y2y_dt$Date))))
cat(sprintf("[ICSA]    obs=%d  range=%s ~ %s\n",
            nrow(icsa_dt),
            as.character(min(icsa_dt$Date)),
            as.character(max(icsa_dt$Date))))
cat(sprintf("[STLFSI4] obs=%d  range=%s ~ %s\n",
            nrow(stlfsi_dt),
            as.character(min(stlfsi_dt$Date)),
            as.character(max(stlfsi_dt$Date))))
cat(sprintf("[CFNAI]   obs=%d  range=%s ~ %s\n",
            nrow(cfnai_dt),
            as.character(min(cfnai_dt$Date)),
            as.character(max(cfnai_dt$Date))))

# Build daily spine 1995-01-01 ~ today
spine <- data.table(Date = seq(as.Date("1995-01-01"), as.Date("2026-05-19"), by = "day"))

setnames(t10y2y_dt, "value", "t10y2y_raw")
setnames(icsa_dt,   "value", "icsa_raw")
setnames(stlfsi_dt, "value", "stlfsi4_raw")
setnames(cfnai_dt,  "value", "cfnai_raw")

out <- merge(spine, t10y2y_dt, by = "Date", all.x = TRUE)
out <- merge(out, icsa_dt, by = "Date", all.x = TRUE)
out <- merge(out, cfnai_dt, by = "Date", all.x = TRUE)
out <- merge(out, stlfsi_dt, by = "Date", all.x = TRUE)

# raw values only — lag-1 + forward-fill in 96 build script
out_path <- file.path(DATA, "fred_us_macro_daily.csv")
fwrite(out, out_path)
cat(sprintf("\n[saved] %s\n", out_path))
cat(sprintf("  rows: %d\n", nrow(out)))

for (col in c("t10y2y_raw", "icsa_raw", "cfnai_raw", "stlfsi4_raw")) {
  n_valid <- sum(!is.na(out[[col]]))
  first_valid <- if (n_valid > 0) as.character(out$Date[which(!is.na(out[[col]]))[1]]) else "n/a"
  last_valid <- if (n_valid > 0) as.character(out$Date[max(which(!is.na(out[[col]])))]) else "n/a"
  cat(sprintf("  %-12s valid=%6d  first=%s  last=%s\n", col, n_valid, first_valid, last_valid))
}

cat("\n[DONE] Cycle 47B FRED parse — proceed to scripts/96_5way_retrain_v3f_us_macro.R\n")
