## WT-D20260822_004 · P0 — 재료 실측 (사전등록 전 · 대조군 재현만, 처치 미측정)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
W005 <- "stage_artifacts/WT-D20260813_005"; W002 <- "stage_artifacts/WT-D20260822_002"
SRC  <- "stage_artifacts/fq233_probe0_20260813"

cat("=== p2_arms.rds 구조 ===\n")
A <- readRDS(file.path(W002,"p2_arms.rds")); cat(" names:", paste(names(A), collapse=", "), "\n")
for (n in names(A)) cat(sprintf("  %-14s %s\n", n, paste(class(A[[n]]),collapse="/")))
if (!is.null(A$sel)) { cat("  sel arms:", paste(names(A$sel),collapse=", "),"\n")
  cat("  sel$SEL_RANK 길이:", length(A$sel$SEL_RANK), " 첫달:", names(A$sel$SEL_RANK)[1],
      " -> ", paste(A$sel$SEL_RANK[[1]],collapse=","), "\n")
  cat("  마지막달:", tail(names(A$sel$SEL_RANK),1), "->", paste(tail(A$sel$SEL_RANK,1)[[1]],collapse=","), "\n") }

cat("\n=== 선별 팩터 빈도 (SEL_RANK 221개월) ===\n")
if (!is.null(A$sel)) { tb <- sort(table(unlist(A$sel$SEL_RANK)), decreasing=TRUE)
  print(head(tb, 25)); cat("  distinct 팩터 수:", length(tb), "\n") }

cat("\n=== z 패널 ===\n")
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
cat(" 행", nrow(pan), " 월", uniqueN(pan$anchor), " 범위", format(min(pan$anchor)), "~", format(max(pan$anchor)), "\n")
S1 <- readRDS(file.path(W005,"s1_factor_month_stats.rds")); FACS <- S1$FACS
cat(" FACS:", length(FACS), " 예:", paste(head(FACS,5),collapse=","), "\n")
zc <- intersect(FACS, names(pan)); cat(" 패널에 있는 FACS 컬럼:", length(zc), "\n")
sub <- pan[anchor==A$anchors[100]]
cat(" 표본월", format(A$anchors[100]), " 종목", nrow(sub), "\n")
zz <- as.matrix(sub[, ..zc])
cat(sprintf(" z 통계: 중앙 %.4f · sd %.4f · min %.3f · max %.3f · 결측률 %.3f\n",
            median(zz,na.rm=TRUE), sd(as.vector(zz),na.rm=TRUE), min(zz,na.rm=TRUE), max(zz,na.rm=TRUE),
            mean(!is.finite(zz))))
saveRDS(list(anchors=A$anchors, sel_rank=A$sel$SEL_RANK, FACS=FACS),
        "stage_artifacts/WT-D20260822_004/p0_probe.rds")
cat("\nOK\n")
