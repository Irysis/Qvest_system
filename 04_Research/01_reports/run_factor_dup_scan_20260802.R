## run_factor_dup_scan_20260802.R
## ─────────────────────────────────────────────────────────────────────────────
## Factor DB 중복 스캔 — WT-D20260802_003 risk 라운드 적발 후속 위생 태스크.
## 두 basis 실측:
##   (A) signal basis  = 월별 횡단면 Z_Score_Aligned 상관 (C15: load_month_factors 경유)
##   (B) deploy basis  = r6 배포존 active 수익 시계열 상관 (WT-003 재현/확인)
## 대상: approved 102 (의무) + factor DB 전체 (부수 — 미래 선별 오염 선차단)
##
## 실행: 데이터(.cache/factor_db)는 main 저장소에만 있으므로 QM_DATA 에서 setwd,
##       코드는 QM_CODE(현 worktree)에서 source 한다.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
setDTthreads(2); try(arrow::set_cpu_count(2), silent = TRUE)

QM_DATA <- Sys.getenv("QM_DATA", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM_CODE <- Sys.getenv("QM_CODE", QM_DATA)
setwd(QM_DATA)

OUT <- file.path(QM_CODE, "04_Research/01_reports")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
RUNTAG <- "20260802"
logf <- file.path(OUT, sprintf("_factor_dup_scan_log_%s.txt", RUNTAG))
con <- file(logf, "w", encoding = "UTF-8")
w  <- function(...) { m <- paste0(...); writeLines(m, con); flush(con); cat(m, "\n") }
wf <- function(...) w(sprintf(...))

source("02_Infrastructure/factor_db/factor_db_connector.R")
source(file.path(QM_CODE, "02_Infrastructure/factor_db/factor_dup_scan.R"))

wf("=== factor dup scan start %s ===", format(Sys.time()))
wf("QM_DATA=%s", QM_DATA); wf("QM_CODE=%s", QM_CODE)

bh <- tryCatch(readLines(file.path(FACTOR_DB_DIR, "build_hash.txt"), n = 1L),
               error = function(e) "unknown")
wf("factor_db build_hash = %s", bh)

## ── 대상 집합 ────────────────────────────────────────────────────────────────
reg <- fromJSON(file.path(QM_CODE, "02_Infrastructure/factor_db/factor_registry.json"),
                simplifyVector = FALSE)
ALL_REG <- sort(names(reg))
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- sort(af[status == "approved", factor_id])
wf("registry entries=%d | approved=%d | approved not in registry: %s",
   length(ALL_REG), length(APPROVED),
   paste(setdiff(APPROVED, ALL_REG), collapse = ",") )

## ── 기간 격자 (2005~ 고정, 헌법 alpha-search 기간 정합) ──────────────────────
## seq.Date by="month" from a 31st overflows (Feb 31 -> Mar 3), so anchor on the
## 1st and step back one day. 31일 앵커로 seq 하면 Feb/Apr/Jun/Sep/Nov 이 통째로
## 빠지고 이웃 달이 2번 세어진다 — 개수(257)는 맞게 나와 스스로를 가린다.
MONTHS <- seq(as.Date("2005-02-01"), as.Date("2026-07-01"), by = "month") - 1L
stopifnot(length(unique(format(MONTHS, "%Y%m"))) == length(MONTHS))
stopifnot(all(format(MONTHS + 1L, "%d") == "01"))          # 전부 월말인가
wf("months: %d distinct-YM=%d (%s .. %s)", length(MONTHS),
   length(unique(format(MONTHS, "%Y%m"))), format(min(MONTHS)), format(max(MONTHS)))

## ═════════════════════════════════════════════════════════════════════════════
## (A) SIGNAL BASIS — 전체 registry 격자로 1회 스캔, approved 는 부분집합으로 리포트
## ═════════════════════════════════════════════════════════════════════════════
t0 <- Sys.time()
sig_pairs <- scan_signal_dup(
  months       = MONTHS,
  factor_names = ALL_REG,
  coverage_min = 0.05,
  min_obs      = 30L,
  screen_thr   = 0.90,
  verbose      = TRUE
)
wf("(A) signal scan done in %.1f min — %d candidate pairs",
   as.numeric(difftime(Sys.time(), t0, units = "mins")), nrow(sig_pairs))

sig_pairs <- classify_dup(sig_pairs, stat = "median_abs",
                          exact_thr = 0.99, near_thr = 0.95)
sig_pairs[, both_approved := factor_a %in% APPROVED & factor_b %in% APPROVED]
sig_pairs[, any_approved  := factor_a %in% APPROVED | factor_b %in% APPROVED]

wf("(A) verdict — ALL registry : EXACT=%d NEAR=%d OK=%d",
   sum(sig_pairs$verdict == "EXACT_DUP", na.rm = TRUE),
   sum(sig_pairs$verdict == "NEAR_DUP",  na.rm = TRUE),
   sum(sig_pairs$verdict == "OK",        na.rm = TRUE))
wf("(A) verdict — APPROVED-102 : EXACT=%d NEAR=%d",
   sig_pairs[both_approved == TRUE & verdict == "EXACT_DUP", .N],
   sig_pairs[both_approved == TRUE & verdict == "NEAR_DUP",  .N])

w("")
w("--- (A) APPROVED-102 duplicates (median |cor| desc) ---")
ap <- sig_pairs[both_approved == TRUE & verdict %in% c("EXACT_DUP", "NEAR_DUP")]
setorder(ap, -median_abs)
for (i in seq_len(nrow(ap))) {
  wf("  %-10s %-34s ~ %-34s med=%+.4f |med|=%.4f n=%3d min=%+.3f max=%+.3f flips=%d",
     ap$verdict[i], ap$factor_a[i], ap$factor_b[i], ap$median_cor[i],
     ap$median_abs[i], ap$n_months[i], ap$min_cor[i], ap$max_cor[i], ap$sign_flips[i])
}

w("")
w("--- (A) NON-approved-pair duplicates (registry-wide, EXACT only) ---")
np <- sig_pairs[both_approved == FALSE & verdict == "EXACT_DUP"]
setorder(np, -median_abs)
for (i in seq_len(nrow(np))) {
  wf("  %-34s ~ %-34s med=%+.4f n=%3d  (approved touch=%s)",
     np$factor_a[i], np$factor_b[i], np$median_cor[i], np$n_months[i],
     ifelse(np$any_approved[i], "YES", "no"))
}

## ═════════════════════════════════════════════════════════════════════════════
## (B) DEPLOY BASIS — WT-003 재현 (독립 계산)
## ═════════════════════════════════════════════════════════════════════════════
r6 <- as.data.table(read_parquet("outputs/ramp/r6_factor_deployzone_active.parquet"))
r6[, signal_date := as.Date(signal_date)]
dep_pairs <- scan_deploy_dup(r6, factor_names = APPROVED, min_months = 36L)
dep_pairs[, verdict := fifelse(abs_cor >= 0.99, "EXACT_DUP",
                        fifelse(abs_cor >= 0.95, "NEAR_DUP", "OK"))]
wf("")
wf("(B) deploy basis (approved 102, n_months>=36): EXACT=%d NEAR=%d of %d pairs",
   dep_pairs[verdict == "EXACT_DUP", .N], dep_pairs[verdict == "NEAR_DUP", .N],
   nrow(dep_pairs))
w("--- (B) top-20 by |cor| ---")
for (i in seq_len(min(20L, nrow(dep_pairs)))) {
  wf("  %-10s %-34s ~ %-34s cor=%+.4f n=%3d",
     dep_pairs$verdict[i], dep_pairs$factor_a[i], dep_pairs$factor_b[i],
     dep_pairs$cor[i], dep_pairs$n_months[i])
}

## WT-003 이 명시한 3쌍 직접 확인
w("")
w("--- (B) WT-003 claimed pairs, independently recomputed ---")
claim <- list(c("D01_IdioVol", "R12_Idiosyncratic_Risk"),
              c("D01_IdioVol", "D22_Tracking_Error"),
              c("R12_Idiosyncratic_Risk", "D22_Tracking_Error"))
for (cp in claim) {
  r <- dep_pairs[(factor_a == cp[1] & factor_b == cp[2]) |
                 (factor_a == cp[2] & factor_b == cp[1])]
  s <- sig_pairs[(factor_a == cp[1] & factor_b == cp[2]) |
                 (factor_a == cp[2] & factor_b == cp[1])]
  wf("  %s ~ %s : deploy cor=%s (n=%s) | signal median cor=%s (n=%s)",
     cp[1], cp[2],
     if (nrow(r)) sprintf("%+.4f", r$cor[1]) else "NA",
     if (nrow(r)) r$n_months[1] else NA,
     if (nrow(s)) sprintf("%+.4f", s$median_cor[1]) else "NA",
     if (nrow(s)) s$n_months[1] else NA)
}

## ── 저장 ────────────────────────────────────────────────────────────────────
write_parquet(sig_pairs, file.path(OUT, sprintf("factor_dup_signal_pairs_%s.parquet", RUNTAG)))
write_parquet(dep_pairs, file.path(OUT, sprintf("factor_dup_deploy_pairs_%s.parquet", RUNTAG)))
meta <- list(
  run_tag = RUNTAG, generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  factor_db_build_hash = bh,
  months_n = length(MONTHS), month_min = format(min(MONTHS)), month_max = format(max(MONTHS)),
  n_registry = length(ALL_REG), n_approved = length(APPROVED),
  metric_type = "signal_zscore_cross_section / deploy_active_series",
  thresholds = list(exact = 0.99, near = 0.95, min_obs = 30, screen = 0.90)
)
write_json(meta, file.path(OUT, sprintf("factor_dup_scan_meta_%s.json", RUNTAG)),
           auto_unbox = TRUE, pretty = TRUE)
wf("saved to %s", OUT)
wf("=== done %s ===", format(Sys.time()))
close(con)
