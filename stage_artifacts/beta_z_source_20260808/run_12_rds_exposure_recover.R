## run_12 — 계약 rds 의 cash_weight 로 "그 시리즈가 실제 쓴 노출"을 복원할 수 있는가
## 가설 H: invested_rds = 1 - cash_weight  이고, 이는 통일 **전**(frozen z) 원장의 beta_R05 × m4 와 일치한다.
##   확인되면 rds 앵커월의 β 열도 정합 가능(= ret_net 을 만든 노출을 열이 정직하게 표시).
suppressPackageStartupMessages(library(data.table))
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
D <- file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2")

rds <- readRDS(file.path(R, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds"))
pr  <- as.data.table(rds$period_returns)[, .(anchor_date = as.Date(date),
                                             cash_weight, leverage, ret_rds = as.numeric(ret_net))]
pr[, inv_rds := 1 - cash_weight]

## 통일 '전' 원장(frozen z 기반)에서 β×m4 를 뽑는다
baks <- sort(list.files(D, pattern = "^live_book_series\\.csv\\.bak_frozen_", full.names = TRUE))
o <- fread(tail(baks, 1))
o[, anchor_date := as.Date(date)]
n <- fread(file.path(D, "live_book_series.csv"))
n[, anchor_date := as.Date(date)]

m <- merge(pr, o[, .(anchor_date, inv_frozen = beta_R05 * m4, ret_o = ret_net, src = ret_net_source)],
           by = "anchor_date")
m <- merge(m, n[, .(anchor_date, inv_live = beta_R05 * m4)], by = "anchor_date", all.x = TRUE)
r <- m[grepl("^rds_anchor", src)]
cat(sprintf("[대조] rds 앵커월 %d건\n\n", nrow(r)))

cat("=== H: inv_rds(1-cash_weight) == inv_frozen(통일 전 β×m4) ? ===\n")
d1 <- abs(r$inv_rds - r$inv_frozen)
cat(sprintf("  일치(1e-9) %d/%d (%.1f%%) · 최대오차 %.2e · 중앙오차 %.2e\n",
            sum(d1 < 1e-9, na.rm = TRUE), nrow(r), 100*mean(d1 < 1e-9, na.rm = TRUE),
            max(d1, na.rm = TRUE), median(d1, na.rm = TRUE)))

cat("\n=== 대조군: inv_rds vs inv_live(통일 후) ===\n")
d2 <- abs(r$inv_rds - r$inv_live)
cat(sprintf("  일치(1e-9) %d/%d (%.1f%%) · 최대오차 %.2e\n",
            sum(d2 < 1e-9, na.rm = TRUE), nrow(r), 100*mean(d2 < 1e-9, na.rm = TRUE),
            max(d2, na.rm = TRUE)))

cat("\n[판정]\n")
if (mean(d1 < 1e-9, na.rm = TRUE) > 0.99 && mean(d2 < 1e-9, na.rm = TRUE) < 0.99) {
  cat("  ★H 확정 — cash_weight 로 rds 노출 복원 가능. 통일 후 β 열이 rds ret_net 과 어긋난 것도 확정.\n")
  cat("  ⇒ rds 앵커월의 beta_R05 는 (1-cash_weight)/m4 로 정합해야 열이 정직해진다.\n")
} else if (mean(d1 < 1e-9, na.rm = TRUE) > 0.99) {
  cat("  H 성립하나 live 도 동일 — 통일이 rds 구간 노출을 안 바꿨다는 뜻(정합 불필요).\n")
} else {
  cat("  ★H 불성립 — cash_weight 는 β×m4 와 다른 것을 담는다. 다른 복원 경로 필요.\n")
  print(head(r[d1 >= 1e-9, .(anchor_date, cash_weight, inv_rds, inv_frozen, inv_live)], 8))
}
fwrite(m, file.path(R, "stage_artifacts/beta_z_source_20260808/rds_exposure_recover.csv"))
