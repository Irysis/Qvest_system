## run_13 — "2026-06 동결 쪽 부호 반전" 이 실재하는가 (단일정렬 정본 사용법으로 재측정)
##
## 경위: run_01(이중정렬, 무효)은 2026-06 rank = **−0.689**, run_07(정정)은 **+0.689** 로 부호가 갈렸다.
##       메모리에는 무효본 수치가 "동결 쪽 이상"으로 적혀 있다 — 실재 여부부터 판별한다.
## 설계: 2026-01~2026-08 연속 구간을 동일 절차로 재고, 2026-05 규약 전환(n 343→2529, sd_z=1.0)
##       전후에서 무엇이 실제로 달라지는지 분리한다.
## ★정본 사용법: raw parquet 직접 읽기 → align_factor_direction 1회. 재정렬 금지.
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(R)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")

frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"))
reg <- .load_registry()

live_one <- function(sig) {
  ym <- format(as.Date(sig) - 1L, "%Y%m")
  fp <- file.path(R, sprintf(".cache/factor_db/factor_db_%s.parquet", ym))
  if (!file.exists(fp)) return(NULL)
  f <- as.data.table(read_parquet(fp, col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
  r <- f[Factor_Name == "R05_Tail_Risk" & Coverage == TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(r)) return(NULL)
  r[, sig_date := as.Date(sig)]
  ra <- align_factor_direction(r, reg, sig_date = as.Date(sig), min_ic_months = 12L)   # ← 1회만
  if ("Z_Score_Aligned" %in% names(ra)) ra[, Z_Score := Z_Score_Aligned]
  ra[, .(Ticker, z_live = Z_Score)]
}

sigs <- as.Date(c("2026-01-01","2026-02-01","2026-03-01","2026-04-01",
                  "2026-05-01","2026-06-01","2026-07-01","2026-08-01"))
res <- rbindlist(lapply(sigs, function(s) {
  fz <- frz[Date == s, .(Ticker, z_frozen = R05_Tail_Risk_Z)]
  lz <- live_one(s)
  if (is.null(lz) || !nrow(fz)) return(data.table(Date = s, n_frozen = nrow(fz),
      n_live = if (is.null(lz)) 0L else nrow(lz), n_match = 0L,
      rank = NA_real_, pearson = NA_real_, sd_f = NA_real_, sd_l = NA_real_))
  m <- merge(fz, lz, by = "Ticker")
  data.table(Date = s, n_frozen = nrow(fz), n_live = nrow(lz), n_match = nrow(m),
             rank = if (nrow(m) > 2) suppressWarnings(cor(m$z_frozen, m$z_live, method = "spearman",
                                                          use = "complete.obs")) else NA_real_,
             pearson = if (nrow(m) > 2) suppressWarnings(cor(m$z_frozen, m$z_live,
                                                             use = "complete.obs")) else NA_real_,
             sd_f = sd(m$z_frozen, na.rm = TRUE), sd_l = sd(m$z_live, na.rm = TRUE))
}))

cat("=== 2026 연속 구간 — 단일정렬 재측정 ===\n")
print(res[, .(Date, n_frozen, n_live, n_match,
              rank = round(rank, 4), pearson = round(pearson, 4),
              sd_f = round(sd_f, 4), sd_l = round(sd_l, 4))])

cat("\n[판정]\n")
r6 <- res[Date == as.Date("2026-06-01")]$rank
pre <- res[Date < as.Date("2026-05-01") & !is.na(rank)]$rank
if (length(pre) && !is.na(r6)) {
  cat(sprintf("  2026-06 rank = %+.4f · 전환 전(2026-01~04) 중앙 %+.4f\n", r6, median(pre)))
  if (r6 < 0 && median(pre) > 0) {
    cat("  ★부호 반전 실재 — 동결 쪽 이상 확인\n")
  } else if (sign(r6) == sign(median(pre))) {
    cat("  ★★부호 반전 **없음** — 메모리의 '−0.689 반전'은 이중정렬 산물(무효본 run_01)이었다.\n")
    cat(sprintf("     단 크기는 전환 전 대비 %s (%.4f vs %.4f) — 규약 전환의 흔적은 남는다.\n",
                if (abs(r6) < abs(median(pre))) "감소" else "증가", abs(r6), abs(median(pre))))
  }
}
cat(sprintf("\n[규약 전환] n_frozen: %s\n", paste(sprintf("%s=%d", format(res$Date, "%m월"), res$n_frozen), collapse = " · ")))
fwrite(res, "stage_artifacts/beta_z_source_20260808/anomaly_202606_clean.csv")
cat("\n[저장] anomaly_202606_clean.csv\n")
