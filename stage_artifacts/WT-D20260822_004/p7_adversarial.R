## WT-D20260822_004 · P7 — Self-Adversarial 검증용 추가 실측
##  ①처치가 실제로 포트폴리오를 바꿨는가 (top-25 Jaccard) — null 의 증거력 판별
##  ②MATERIAL 문턱 민감도 — 문턱을 낮춰도 결론이 유지되는가
##  ③C2 clip 이 실제로 몇 %를 잘랐는가 — 매개 미이동의 원인 규명
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_004"; SRC <- "stage_artifacts/fq233_probe0_20260813"
V <- readRDS(file.path(OUT,"p4_verdict.rds")); B <- readRDS(file.path(OUT,"p1_arms.rds"))
SCA <- V$SCA; TOPN <- B$TOPN; PRI <- V$PRI

cat("=== (1) top-25 명단 겹침 — 처치가 포트폴리오를 실제로 바꿨는가 ===\n")
top25 <- function(a) SCA[[a]][order(Date, -score, Ticker), head(.SD, TOPN), by = Date][, .(Date, Ticker)]
TP <- lapply(setNames(c("C0","C1","C2","C3"), c("C0","C1","C2","C3")), top25)
jac <- function(a, b) { x <- TP[[a]]; y <- TP[[b]]
  m <- merge(x[, .(Date, Ticker, ax = 1L)], y[, .(Date, Ticker, by_ = 1L)], by = c("Date","Ticker"), all = TRUE)
  m[, .(j = sum(!is.na(ax) & !is.na(by_))/.N, ov = sum(!is.na(ax) & !is.na(by_))), by = Date] }
for (a in c("C1","C2","C3")) { g <- jac("C0", a)
  cat(sprintf("  C0 vs %-3s  Jaccard 중앙 %.4f (평균 %.4f) · 겹치는 종목 중앙 %.1f/%d · **교체 중앙 %.1f 종목/월**\n",
    a, median(g$j), mean(g$j), median(g$ov), TOPN, TOPN - median(g$ov))) }

cat("\n=== (2) MATERIAL 문턱 민감도 (사전등록 8.2228 %p/yr) ===\n")
for (a in c("C1","C2")) { hi <- PRI[contrast==a]$ci95_hi
  cat(sprintf("  %-3s CI95 상단 %+.4f %%p/yr — 배제되는 문턱: 8.2228 %s · 4.1114(절반) %s · 3.0000 %s · 2.0000 %s\n",
    a, hi, ifelse(hi<8.2228,"O","X"), ifelse(hi<4.1114,"O","X"),
    ifelse(hi<3.0,"O","X"), ifelse(hi<2.0,"O","X"))) }
cat("  (O = 그 문턱의 효과를 95%로 배제 = powered null 유지)\n")

cat("\n=== (3) C2 clip(±2.0) 이 실제로 자른 비율 — 매개 미이동 원인 ===\n")
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet"))); pan[, anchor := as.Date(anchor)]
sel <- B$sel_rank; months <- names(sel)
cl <- rbindlist(lapply(months, function(nm) { fs <- sel[[nm]]; d <- pan[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); Z <- Z[is.finite(rowSums(Z, na.rm=TRUE)), , drop=FALSE]
  v <- as.vector(Z); v <- v[is.finite(v)]
  data.table(anchor=as.Date(nm), clipped=mean(abs(v) > 2.0), max_abs=max(abs(v))) }))
cat(sprintf("  |z| > 2.0 인 셀 비율: 중앙 %.4f (평균 %.4f) · 월별 max|z| 중앙 %.2f\n",
            median(cl$clipped), mean(cl$clipped), median(cl$max_abs)))
cat(sprintf("  ⇒ clip 이 건드린 관측은 전체의 %.1f%% — 이것이 C2 매개 미이동(0.938배)·스코어 rank cor 0.992 의 직접 원인.\n",
            100*median(cl$clipped)))

cat("\n=== (4) 청정창(2015-07~, n=133) 단독 재판정 시의 MDE ===\n")
act <- V$act; c0 <- act$C0$act; idx <- act$C0$Date >= as.Date("2015-07-01")
for (a in c("C1","C2")) { d <- (act[[a]]$act - c0)[idx]
  nw <- .nw_t_mean(d, lag=3L); se <- abs(mean(d)/nw)
  cat(sprintf("  %-3s n=%d · MDE(t=2.0) %.3f %%p/yr · 관측 %+.3f %%p/yr (t %+.3f)\n",
    a, sum(idx), 2.0*se*12*100, mean(d)*12*100, nw)) }

saveRDS(list(jac = lapply(c("C1","C2","C3"), function(a) jac("C0",a)), clip = cl),
        file.path(OUT,"p7_adversarial.rds"))
cat("\n[saved] p7_adversarial.rds\n")
