## WT-D20260822_006 (FQ-246) P0 — 재료 실측 (사전등록 전, 처치 미측정)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_006"
W004 <- "stage_artifacts/WT-D20260822_004"
SRC  <- "stage_artifacts/fq233_probe0_20260813"

P0 <- readRDS(file.path(W004, "p0_probe.rds"))
anchors <- P0$anchors; sel_rank <- P0$sel_rank; FACS <- P0$FACS
cat("== 선별 궤적 ==\n")
cat(" anchors:", length(anchors), format(min(anchors)), "~", format(max(anchors)), "\n")
cat(" sel_rank months:", length(sel_rank), "\n")
cat(" first:", names(sel_rank)[1], "->", paste(sel_rank[[1]], collapse=","), "\n")
cat(" last :", tail(names(sel_rank),1), "->", paste(tail(sel_rank,1)[[1]], collapse=","), "\n")
tb <- sort(table(unlist(sel_rank)), decreasing=TRUE)
cat(" distinct selected:", length(tb), " / FACS pool:", length(FACS), "\n")
print(head(tb, 20))
cat(" 월별 교체율(전월 대비 신규 팩터 수 / 5):\n")
ch <- sapply(2:length(sel_rank), function(i) length(setdiff(sel_rank[[i]], sel_rank[[i-1]]))/5)
cat(sprintf("  중앙 %.3f · 평균 %.3f\n", median(ch), mean(ch)))

cat("\n== z 패널 ==\n")
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
cat(" 행", nrow(pan), " 월", uniqueN(pan$anchor), " 컬럼", ncol(pan), "\n")
cat(" 주요 컬럼:", paste(head(setdiff(names(pan), FACS), 12), collapse=", "), "\n")

cat("\n== 상태변수 후보 A: 당월 K=5 팩터 간 횡단면 순위 일치도 (성과 무관) ==\n")
pan2 <- pan[anchor %in% anchors & is.finite(fwd_ret_1m)]
agree <- rbindlist(lapply(names(sel_rank), function(nm) {
  fs <- sel_rank[[nm]]; d <- pan2[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs])
  keep <- colSums(is.finite(Z)) >= 30
  if (sum(keep) < 2L) return(data.table(Date=as.Date(nm), agree=NA_real_, n_pair=0L))
  Z <- Z[, keep, drop=FALSE]
  cm <- suppressWarnings(cor(Z, method="spearman", use="pairwise.complete.obs"))
  v <- cm[upper.tri(cm)]
  data.table(Date=as.Date(nm), agree=mean(v, na.rm=TRUE), n_pair=length(v))
}))
cat(sprintf(" n=%d · 평균 %.4f · sd %.4f · min %.4f · max %.4f · NA %d\n",
  nrow(agree), mean(agree$agree,na.rm=TRUE), sd(agree$agree,na.rm=TRUE),
  min(agree$agree,na.rm=TRUE), max(agree$agree,na.rm=TRUE), sum(is.na(agree$agree))))
cat(sprintf(" AR(1) = %.4f\n", cor(agree$agree[-1], agree$agree[-nrow(agree)], use="complete.obs")))

cat("\n== 상태변수 후보 B: bear_prob (smv_factor_regime_daily) ==\n")
sm <- as.data.table(read_parquet("outputs/ramp/smv_factor_regime_daily.parquet"))
sm[, Date := as.Date(Date)]
cat(" factors:", paste(sort(unique(sm$factor)), collapse=", "), "\n")
smv <- sm[is.finite(bear_prob)]
cat(" 유효 범위:", format(min(smv$Date)), "~", format(max(smv$Date)), " 일수", uniqueN(smv$Date), "\n")
cat(" anchors 중 2014-03-31 이후:", sum(anchors >= as.Date("2014-03-31")), "/", length(anchors), "\n")

cat("\n== 상태변수 후보 C: 횡단면 수익 분산 (dispersion) ==\n")
disp <- pan2[, .(disp = sd(fwd_ret_1m, na.rm=TRUE), n=.N), by=.(Date=anchor)]
cat(sprintf(" ★주의: fwd_ret_1m 기반 = 홀딩월 실현 → 조건변수로 직접 사용 불가(동월 look-ahead). lag 필요.\n"))
cat(sprintf(" 참고 통계: 평균 %.4f · sd %.4f · AR1 %.4f\n", mean(disp$disp), sd(disp$disp),
  cor(disp$disp[-1], disp$disp[-nrow(disp)], use="complete.obs")))

saveRDS(list(anchors=anchors, sel_rank=sel_rank, FACS=FACS, agree=agree, disp=disp),
        file.path(OUT, "p0_probe.rds"))
cat("\n[saved] p0_probe.rds\nOK\n")
