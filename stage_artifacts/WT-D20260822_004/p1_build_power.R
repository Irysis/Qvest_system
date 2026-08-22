## WT-D20260822_004 · P1 — arm 구성 + 대조군 parity + ★검정력 관문 (MEAN-BLIND)
## ★본 파일은 처치 arm 의 paired 평균·t 를 출력하지 않는다. 출력 = parity / sd / nw / MDE.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
SRC <- "stage_artifacts/fq233_probe0_20260813"; OUT <- "stage_artifacts/WT-D20260822_004"
K <- 5L; W <- 36L; TOPN <- 25L; COST <- 15; CLIP <- 2.0   # 사전고정 상수 (스윕 0회)

P0 <- readRDS(file.path(OUT,"p0_probe.rds")); sel_rank <- P0$sel_rank; anchors <- P0$anchors
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]; pan <- pan[anchor %in% anchors & is.finite(fwd_ret_1m)]
stopifnot(length(sel_rank) == 221L)

## ── 결합 규칙 4종 (비-ML · 폐형식) ──────────────────────────────────────────
pctrank <- function(v) { ok <- is.finite(v); r <- rep(NA_real_, length(v))
  if (sum(ok) >= 2L) r[ok] <- (data.table::frank(v[ok], ties.method="average") - 0.5)/sum(ok); r }
COMB <- list(
  C0_zscore_ew   = function(Z) rowMeans(Z, na.rm = TRUE),
  C1_rank_avg    = function(Z) rowMeans(apply(Z, 2L, pctrank), na.rm = TRUE),
  C2_winsor_z_ew = function(Z) rowMeans(pmax(pmin(Z, CLIP), -CLIP), na.rm = TRUE),
  C3_max_z_negctl= function(Z) apply(Z, 1L, function(x) if (all(!is.finite(x))) NA_real_ else max(x, na.rm=TRUE))
)
build_scores <- function(fn) rbindlist(lapply(names(sel_rank), function(nm) {
  fs <- sel_rank[[nm]]; d <- pan[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); nv <- rowSums(is.finite(Z)); sc <- fn(Z)
  data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker),
             score = ifelse(nv >= 1L, sc, NA_real_), n_fac_used = nv)[is.finite(score)]
}))
cat("=== 1) arm 스코어 구성 (선별 궤적 = FQ-237 SEL_RANK 자구 재사용) ===\n")
SC <- lapply(COMB, build_scores)
for (a in names(SC)) cat(sprintf("  %-16s %6d행 · %d개월 · 월중앙 %d종목 · 평균 사용팩터 %.2f/%d\n", a,
  nrow(SC[[a]]), uniqueN(SC[[a]]$Date), as.integer(median(SC[[a]][,.N,by=Date]$N)), mean(SC[[a]]$n_fac_used), K))

cat("\n=== 2) 축 정합 (합성 → forward rank-IC 부호, 양수 정상) ===\n")
fwd <- pan[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
for (a in names(SC)) { j <- merge(SC[[a]], fwd, by=c("Date","Ticker"))
  ic <- j[, .(ic = if (.N>=30 && sd(score)>0) cor(rank(score), rank(fwd)) else NA_real_), by=Date]
  cat(sprintf("  %-16s 평균 rank-IC %+.5f  %s\n", a, mean(ic$ic,na.rm=TRUE),
              if (mean(ic$ic,na.rm=TRUE)>0) "부호 정상(+)" else "★음수")) }

cat("\n=== 3) 벤치 (FQ-237 자구: .cache/benchmark.parquet IKS200) ===\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by=bm$Date), Return.cumulative)
bench_m <- data.table(ym=format(as.Date(index(bmm)),"%Y%m"), BM_Ret=as.numeric(bmm[,1]))
axis_dt <- unique(fwd[,.(Date)])[, ym := format(Date,"%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by="ym")[, .(Date, BM_Ret)]
cat(sprintf("  벤치 정렬 %d개월 / 포트 축 %d개월\n", nrow(bench_dt), uniqueN(fwd$Date)))
returns_dt <- fwd[, .(Date, Ticker, Ret_1m=fwd)]

cat("\n=== 4) canonical_screen_bt (top-25 EW long-only · 15bps · 동점 = Ticker 오름차순 사전고정) ===\n")
run_arm <- function(a) { s <- copy(SC[[a]]); setorder(s, Date, Ticker)   # 결정적 동점처리
  canonical_screen_bt(s[,.(Date,Ticker,score)], returns_dt, bench_dt, top_n=TOPN,
                      cost_bps_oneway=COST, run_id=paste0("FQ244_",a), strategy_id=paste0("FQ244_",a),
                      diag_dual_basis=TRUE) }
BT <- lapply(setNames(names(SC), names(SC)), function(a) { cat("  ",a,"\n"); run_arm(a) })
act <- lapply(BT, function(b) { s <- b$active_series; if (is.null(s)) NULL else s })
str(BT$C0_zscore_ew$portfolio_alpha_t_nw_lag3)
saveRDS(list(SC=SC, BT=BT, bench_dt=bench_dt, returns_dt=returns_dt, anchors=anchors,
             sel_rank=sel_rank, K=K, W=W, TOPN=TOPN, COST=COST, CLIP=CLIP),
        file.path(OUT,"p1_arms.rds"))
cat("\n[saved] p1_arms.rds\n")
