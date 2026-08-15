## D7 — EW-유니버스 basis 에서 sp3 붕괴가 유지되는가 (cap-w mega-cap 아티팩트 배제)
## ★진단 전용. cap-w HARD 판정 불변 (v8.3 dual-basis 의무 — 기각/결론 전 EW-대비 확인).
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/backtest_result_contract.R")
DOUT <- "stage_artifacts/WT-D20260813_005/depth_aligned"
R <- readRDS(file.path(DOUT, "d2_result.rds"))
AN <- c("OBJ_RANK","OBJ_MEAN_Q5","OBJ_MEAN_DEPTH","OBJ_MED_DEPTH")
cat("EW diag period_returns 컬럼:", paste(names(as.data.table(R$RES$OBJ_MEAN_DEPTH$diag_ew_universe$period_returns)), collapse=" | "), "\n\n")
L <- rbindlist(lapply(AN, function(a) {
  p <- as.data.table(R$RES[[a]]$diag_ew_universe$period_returns)
  nm <- names(p); rc <- grep("ret_net|port", nm, value=TRUE)[1]; bc <- grep("bench|bm", nm, value=TRUE)[1]
  dc <- grep("date", nm, value=TRUE)[1]
  x <- data.table(date = as.Date(p[[dc]]), act = p[[rc]] - p[[bc]])
  x[, blk := ifelse(date < as.Date("2015-01-01"),"sp1", ifelse(date < as.Date("2020-01-01"),"sp2","sp3"))]
  cbind(arm = a, x[, .(n = .N, mean = mean(act), t = .nw_t_mean(act, lag = 3L)), by = blk])
}))
cat("EW-유니버스 basis · 블록별 월평균 active:\n"); print(dcast(L, blk ~ arm, value.var = "mean"))
cat("\nEW-유니버스 basis · 블록별 NW3 t:\n");      print(dcast(L, blk ~ arm, value.var = "t"))
cat("\n계약 산출 post2017 (EW basis):\n")
for (a in AN) { e <- R$RES[[a]]$diag_ew_universe
  cat(sprintf("  %-16s full EW t %+.4f · post2017 t %+.4f (n=%d) · oos_retention_approx %s\n",
      a, e$portfolio_alpha_t_nw_lag3, e$post2017_t_nw_lag3, e$n_months_post2017,
      format(round(e$oos_retention_approx, 4))))
}
sp3_all_neg <- all(L[blk == "sp3", mean] < 0)
cat(sprintf("\n⇒ EW basis 에서도 sp3 4-arm 전부 음수: %s\n", if (sp3_all_neg) "예 (cap-w 아티팩트 아님)" else "아니오 (★cap-w 아티팩트 가능 — 결론 재검토)"))
write_json(list(by_block = L, sp3_all_negative_ew = sp3_all_neg,
  label = "diagnostic — cap-w 판정 불변. EW basis 는 기각 전 재분류 확인용(se_shrink 채널 포함이라 알파 증거 아님)."),
  file.path(DOUT, "d7_ew_basis_subperiod.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
