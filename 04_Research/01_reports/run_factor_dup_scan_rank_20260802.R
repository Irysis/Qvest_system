## run_factor_dup_scan_rank_20260802.R
## ─────────────────────────────────────────────────────────────────────────────
## 보완 스캔 — **rank basis** (approved 102 한정).
## 이유: Pearson-on-Z 는 서로 역수/단조변환인 쌍을 놓친다(V08_PSR=MC/Rev vs
##   V20_SP=Rev/MC 는 Pearson<1 이나 순위 동일 → top-N 선별에서 같은 포트).
##   deploy basis 가 V13~V20 = 1.0000, V16~V18 = 1.0000 로 이를 드러냈다.
##   선별(top-N)이 실제로 쓰는 정보는 순위이므로 rank basis 가 de-dup 판정의
##   보수적(더 넓은) 기준이다.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(2); try(arrow::set_cpu_count(2), silent = TRUE)

QM_DATA <- Sys.getenv("QM_DATA", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM_CODE <- Sys.getenv("QM_CODE", QM_DATA)
setwd(QM_DATA)
OUT <- file.path(QM_CODE, "04_Research/01_reports")
RUNTAG <- "20260802"
logf <- file.path(OUT, sprintf("_factor_dup_scan_rank_log_%s.txt", RUNTAG))
con <- file(logf, "w", encoding = "UTF-8")
w  <- function(...) { m <- paste0(...); writeLines(m, con); flush(con); cat(m, "\n") }
wf <- function(...) w(sprintf(...))

source("02_Infrastructure/factor_db/factor_db_connector.R")
source(file.path(QM_CODE, "02_Infrastructure/factor_db/factor_dup_scan.R"))

af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- sort(af[status == "approved", factor_id])

MONTHS <- seq(as.Date("2005-02-01"), as.Date("2026-07-01"), by = "month") - 1L
stopifnot(length(unique(format(MONTHS, "%Y%m"))) == length(MONTHS))

wf("=== rank-basis dup scan start %s === months=%d approved=%d",
   format(Sys.time()), length(MONTHS), length(APPROVED))

t0 <- Sys.time()
rk <- scan_signal_dup(months = MONTHS, factor_names = APPROVED,
                      coverage_min = 0.05, min_obs = 30L, screen_thr = 0.90,
                      rank_transform = TRUE, verbose = TRUE)
wf("rank scan done in %.1f min — %d candidates",
   as.numeric(difftime(Sys.time(), t0, units = "mins")), nrow(rk))
rk <- classify_dup(rk, stat = "median_abs", exact_thr = 0.99, near_thr = 0.95)
wf("rank basis APPROVED-102: EXACT=%d NEAR=%d",
   rk[verdict == "EXACT_DUP", .N], rk[verdict == "NEAR_DUP", .N])

hit <- rk[verdict %in% c("EXACT_DUP", "NEAR_DUP")]
setorder(hit, -median_abs)
w("")
w("--- rank-basis duplicates (approved 102) ---")
for (i in seq_len(nrow(hit))) {
  wf("  %-10s %-34s ~ %-34s med=%+.4f |med|=%.4f n=%3d min=%+.3f max=%+.3f",
     hit$verdict[i], hit$factor_a[i], hit$factor_b[i], hit$median_cor[i],
     hit$median_abs[i], hit$n_months[i], hit$min_cor[i], hit$max_cor[i])
}

## Pearson basis 와의 차집합 — rank 에서만 잡히는 쌍이 "역수/단조" 계열
pz <- as.data.table(read_parquet(file.path(OUT, sprintf("factor_dup_signal_pairs_%s.parquet", RUNTAG))))
pz_hit <- pz[both_approved == TRUE & verdict %in% c("EXACT_DUP","NEAR_DUP"),
             .(key = paste(pmin(factor_a, factor_b), pmax(factor_a, factor_b)))]
hit[, key := paste(pmin(factor_a, factor_b), pmax(factor_a, factor_b))]
only_rank <- hit[!key %in% pz_hit$key]
w("")
wf("--- rank 에서만 적발 (Pearson-on-Z 사각지대): %d 쌍 ---", nrow(only_rank))
for (i in seq_len(nrow(only_rank))) {
  wf("  %-10s %-34s ~ %-34s med=%+.4f", only_rank$verdict[i],
     only_rank$factor_a[i], only_rank$factor_b[i], only_rank$median_cor[i])
}

write_parquet(rk, file.path(OUT, sprintf("factor_dup_rank_pairs_%s.parquet", RUNTAG)))
wf("=== done %s ===", format(Sys.time()))
close(con)
