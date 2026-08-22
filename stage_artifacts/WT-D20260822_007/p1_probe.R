## WT-D20260822_007 (FQ-246 NP1) P1 — 승계 구조 실측 확인 (측정 아님, 구조 점검)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
W004 <- "stage_artifacts/WT-D20260822_004"; W006 <- "stage_artifacts/WT-D20260822_006"
SRC  <- "stage_artifacts/fq233_probe0_20260813"
OUT  <- "stage_artifacts/WT-D20260822_007"

A4 <- readRDS(file.path(W004, "p1_arms.rds"))
cat("== A4 (FQ-244 p1_arms) names ==\n"); print(names(A4))
cat("K =", A4$K, " TOPN =", A4$TOPN, " CLIP =", A4$CLIP, "\n")
cat("months n =", length(A4$sel_rank), " first/last =", names(A4$sel_rank)[1],
    names(A4$sel_rank)[length(A4$sel_rank)], "\n")
cat("sel_rank[[1]] =", paste(A4$sel_rank[[1]], collapse=", "), "\n")
cat("sel_rank[[120]] =", paste(A4$sel_rank[[120]], collapse=", "), "\n")
cat("unique factors across months =",
    length(unique(unlist(A4$sel_rank))), "\n")
tb <- sort(table(unlist(A4$sel_rank)), decreasing=TRUE)
cat("top-12 factor frequency:\n"); print(head(tb, 12))
cat("returns_dt:\n"); print(head(A4$returns_dt, 3)); cat("n =", nrow(A4$returns_dt), "\n")
cat("bench_dt:\n"); print(head(A4$bench_dt, 3)); cat("n =", nrow(A4$bench_dt), "\n")

P6 <- readRDS(file.path(W006, "p2_arms.rds"))
cat("\n== P6 (FQ-246 p2_arms) names ==\n"); print(names(P6))
cat("TOPN =", P6$TOPN, " UCLIP =", P6$UCLIP, " MIN_WARM =", P6$MIN_WARM,
    " MATERIAL =", P6$MATERIAL, "\n")
cat("GV head:\n"); print(head(P6$GV, 8))
cat("U names:", paste(names(P6$U), collapse=", "), "\n")
cat("act names:", paste(names(P6$act), collapse=", "), "\n")
cat("C0 act n =", nrow(P6$act$C0), " head:\n"); print(head(P6$act$C0, 3))

V4 <- readRDS(file.path(W004, "p4_verdict.rds"))
cat("\n== V4 (FQ-244 p4_verdict) names ==\n"); print(names(V4))
if (!is.null(V4$act)) cat("V4$act arms:", paste(names(V4$act), collapse=", "), "\n")

pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
cat("\n== panel ==\n"); cat("rows =", nrow(pan), " cols =", ncol(pan), "\n")
cat("anchors =", length(unique(pan$anchor)), " range",
    format(min(pan$anchor)), "~", format(max(pan$anchor)), "\n")
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
cat("holding-month rows =", nrow(panh), " anchors =", length(unique(panh$anchor)), "\n")

## 하드 선택 사다리에 필요한 월별 IC 벡터 구조 확인
months <- names(A4$sel_rank)
icm <- t(vapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  vapply(fs, function(f) { v <- d[[f]]; ok <- is.finite(v) & is.finite(d$fwd_ret_1m)
    if (sum(ok) < 30L) return(NA_real_); cor(rank(v[ok]), rank(d$fwd_ret_1m[ok])) }, 0)
}, numeric(A4$K)))
cat("\n== 월별 실현 rank-IC 행렬 (221 x K=5) ==\n")
cat("finite cells =", sum(is.finite(icm)), "/", length(icm), "\n")
cat("IC mean =", round(mean(icm, na.rm=TRUE), 5),
    " sd(within-month across K) mean =", round(mean(apply(icm, 1, sd, na.rm=TRUE), na.rm=TRUE), 5), "\n")
cat("월별 best-worst IC 스프레드 평균 =",
    round(mean(apply(icm, 1, function(x) diff(range(x, na.rm=TRUE))), na.rm=TRUE), 5), "\n")
saveRDS(list(A4=A4, P6=P6, icm=icm, months=months), file.path(OUT, "p1_probe.rds"))
cat("\n[saved] p1_probe.rds\nOK\n")
