## WT-D20260822_006 (FQ-246) P5 — AX-001 v2 수리 + 산출물 emit
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
P <- readRDS(file.path(OUT,"p2_arms.rds")); V3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
V4 <- readRDS(file.path(OUT,"p4_conduit.rds"))
A4 <- readRDS(file.path(W004,"p1_arms.rds"))
act <- P$act; c0 <- act$C0$act; SC <- P$SC; BT <- P$BT

cat("=== AX-001 v2 재산출 (벤치 정렬 수리) ===\n")
bm <- A4$bench_dt[order(Date)]
mo <- act$C0$Date
b <- bm[match(mo, bm$Date), BM_Ret]
cat("  벤치 정렬:", sum(is.finite(b)), "/", length(mo), "\n")
bad <- is.finite(b) & b < quantile(b, 0.20, na.rm=TRUE); norm <- is.finite(b) & !bad
cat(sprintf("  bad 월 %d · normal 월 %d · bad 평균 벤치 %+.4f\n", sum(bad), sum(norm), mean(b[bad])))
AX <- rbindlist(lapply(c("T2_AGREE","T3_DISP","T1_AGREE","T4_BOTH"), function(a){ d <- act[[a]]$act - c0
  data.table(arm=a, crisis_alpha_ann=round(mean(d[bad])*12*100,4),
             normal_alpha_ann=round(mean(d[norm])*12*100,4),
             bad_over_normal_ic_ratio=round(mean(d[bad])/mean(d[norm]),4),
             crisis_t=round(.nw_t_mean(d[bad],3L),4)) }))
print(AX)

cat("\n=== alpha_scores.parquet emit ===\n")
SCORES <- rbindlist(lapply(names(SC), function(a) copy(SC[[a]])[, arm := a]))
SCORES[, metric_type := "canonical_screen"]
write_parquet(SCORES, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("  %d행 · %d arm · %d개월 · %s ~ %s\n", nrow(SCORES), uniqueN(SCORES$arm),
            uniqueN(SCORES$Date), format(min(SCORES$Date)), format(max(SCORES$Date))))

cat("\n=== alpha_vector_live.parquet (최신 단면) ===\n")
last_d <- max(SCORES$Date)
LIVE <- SCORES[Date == last_d & arm %in% c("C0","T3_DISP")]
LIVE <- dcast(LIVE, Date + Ticker ~ arm, value.var="score")
setnames(LIVE, c("C0","T3_DISP"), c("alpha_C0","alpha_T3_DISP"))
## confidence_vector: 사용 팩터 수 커버리지 x 횡단면 순위 안정성(두 arm 순위 상관 기반)
LIVE[, rk_c0 := frank(-alpha_C0)][, rk_t3 := frank(-alpha_T3_DISP)]
LIVE[, rank_gap := abs(rk_c0 - rk_t3)/.N]
LIVE[, confidence := pmax(0, pmin(1, 1 - rank_gap))]
write_parquet(LIVE, file.path(OUT, "alpha_vector_live.parquet"))
cat(sprintf("  %s · %d종목 · confidence 중앙 %.4f\n", format(last_d), nrow(LIVE), median(LIVE$confidence)))

saveRDS(list(AX=AX, last_d=last_d, LIVE=LIVE), file.path(OUT,"p5_emit.rds"))
cat("\n[saved] p5_emit.rds\nOK\n")
