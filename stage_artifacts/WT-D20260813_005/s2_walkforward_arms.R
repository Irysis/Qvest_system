## WT-D20260813_005 · S2 — walk-forward 선별 3 arm + 위반주입 대조 + 측정
##
## 사전등록: stage_artifacts/WT-D20260813_005/PREREG_impl_lock.md (측정 전 봉인)
##   K=5 · W=36 · 3 arm 전부 NW lag-3 t 정규화 · Q5 · 320종 · EW 결합 · top-25 · 15bps
##
## arm 4종 (재료·구성 전부 동일, **선별 통계량만** 다르다):
##   OBJ_RANK  = trailing rank-IC 의 NW3 t 상위 K        ← base (현행)
##   OBJ_MEAN  = trailing top-분위 평균 활성의 NW3 t 상위 K ← primary
##   OBJ_MED   = trailing 중앙값 스프레드의 NW3 t 상위 K  ← negative control (개선 시 기전 기각)
##   LOOKAHEAD = OBJ_MEAN 인데 창에 **홀딩월 자신**을 포함 ← ★위반 주입 (검사 판별력 확인용)
##   LAG1      = OBJ_MEAN 인데 창을 한 칸 더 물림(T−2 까지) ← PIT 스트레스
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/s2_walkforward_arms.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # → backtest_result_contract.R (.nw_t_mean)
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_005"

K <- 5L; W <- 36L; TOPN <- 25L; COST <- 15               # ★PREREG §1 고정값 (스윕 없음)
MIN_OBS <- 30L                                            # 창 36 중 최소 유효 관측

cat("=== 1) 입력 ===\n")
S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
FS <- S1$FS; FACS <- S1$FACS; anchors <- S1$anchors
cat(sprintf("  통계 %d행 · %d개월 · %d팩터\n", nrow(FS), length(anchors), length(FACS)))
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
pan <- pan[anchor %in% anchors & is.finite(fwd_ret_1m)]
cat(sprintf("  z 패널 %d행 · %d개월 · 월중앙 %d종목\n", nrow(pan), uniqueN(pan$anchor),
            as.integer(median(pan[, .N, by = anchor]$N))))

## 통계 → 행렬 (월 × 팩터) — 창 슬라이스를 싸게
to_mat <- function(col) {
  m <- dcast(FS, anchor ~ fac, value.var = col)
  a <- m$anchor; m[, anchor := NULL]
  mm <- as.matrix(m); rownames(mm) <- as.character(a); mm[, FACS, drop = FALSE]
}
M_ic <- to_mat("ic"); M_ms <- to_mat("meanspread"); M_md <- to_mat("medspread"); M_ss <- to_mat("skewslope")
stopifnot(identical(rownames(M_ic), as.character(anchors)))

cat("\n=== 2) walk-forward 선별 ===\n")
## 창 규약: 홀딩월 i 의 선별은 **anchor < anchors[i]** 인 실현 통계만 소비 (PREREG §1).
##   OBJ_*     : rows (i-W) .. (i-1)
##   LOOKAHEAD : rows (i-W+1) .. i        ← 홀딩월 자신 포함 = 1개월 누출 (위반 주입)
##   LAG1      : rows (i-W) .. (i-2)      ← 한 칸 더 물림
sel_topK <- function(M, rows) {
  sub <- M[rows, , drop = FALSE]
  tv <- apply(sub, 2L, function(x) { x <- x[is.finite(x)]
    if (length(x) < MIN_OBS) return(NA_real_); .nw_t_mean(x, lag = 3L) })
  ok <- is.finite(tv)
  if (sum(ok) < K) return(character(0))
  names(sort(tv[ok], decreasing = TRUE))[seq_len(K)]
}
i0 <- W + 1L
hold_idx <- i0:length(anchors)
cat(sprintf("  홀딩월 %d개 (%s ~ %s) · burn-in %d개월\n", length(hold_idx),
            anchors[i0], anchors[length(anchors)], W))

ARMS <- c("OBJ_RANK","OBJ_MEAN","OBJ_MED","LOOKAHEAD","LAG1")
sel <- setNames(vector("list", length(ARMS)), ARMS)
for (a in ARMS) sel[[a]] <- setNames(vector("list", length(hold_idx)), as.character(anchors[hold_idx]))
t0 <- Sys.time()
for (k in seq_along(hold_idx)) {
  i <- hold_idx[k]; nm <- as.character(anchors[i])
  sel$OBJ_RANK[[nm]]  <- sel_topK(M_ic, (i-W):(i-1))
  sel$OBJ_MEAN[[nm]]  <- sel_topK(M_ms, (i-W):(i-1))
  sel$OBJ_MED[[nm]]   <- sel_topK(M_md, (i-W):(i-1))
  sel$LOOKAHEAD[[nm]] <- sel_topK(M_ms, (i-W+1):i)          # ★위반 주입
  sel$LAG1[[nm]]      <- sel_topK(M_ms, (i-W):(i-2))
  if (k %% 60 == 0) cat(sprintf("    %d/%d (%.1f분)\n", k, length(hold_idx),
                                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
cat(sprintf("  선별 완료 %.1f분 · 월평균 선별수: %s\n",
            as.numeric(difftime(Sys.time(), t0, units="mins")),
            paste(sprintf("%s=%.1f", ARMS, sapply(ARMS, function(a) mean(lengths(sel[[a]])))), collapse=" ")))
for (a in ARMS) if (any(lengths(sel[[a]]) < K)) stop(sprintf("★arm %s: K 미달 월 존재 — 중단", a))

cat("\n=== 3) 합성 스코어 (선별 K개 Z_Score_Aligned 의 종목별 단순평균) ===\n")
build_scores <- function(selmap) {
  rbindlist(lapply(names(selmap), function(nm) {
    fs <- selmap[[nm]]; if (!length(fs)) return(NULL)
    d <- pan[anchor == as.Date(nm)]
    Z <- as.matrix(d[, ..fs])
    sc <- rowMeans(Z, na.rm = TRUE)
    nv <- rowSums(is.finite(Z))
    data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker),
               score = ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)]
  }))
}
SC <- lapply(sel, build_scores)
for (a in ARMS) cat(sprintf("  %-10s %6d행 · %d개월 · 월중앙 %d종목\n", a, nrow(SC[[a]]),
                            uniqueN(SC[[a]]$Date), as.integer(median(SC[[a]][, .N, by=Date]$N))))

cat("\n=== 4) 축 정합 검증 (PREREG §5-b) — 합성 스코어 → forward IC 부호 ===\n")
fwd <- pan[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)]
for (a in ARMS) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_), by = Date]
  cat(sprintf("  %-10s 평균 IC = %+.5f (n=%d개월)  %s\n", a, mean(ic$ic, na.rm=TRUE), nrow(ic),
              if (mean(ic$ic, na.rm=TRUE) > 0) "부호 정상(+)" else "★부호 음수 — 앵커 오정렬 의심"))
}

cat("\n=== 5) 벤치마크 (일별 → apply.monthly · ym 키) ===\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]
bx <- xts(bm$BM_Ret, order.by = bm$Date)
bmm <- apply.monthly(bx, Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(fwd[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
.cov <- nrow(bench_dt) / uniqueN(fwd$Date)
cat(sprintf("  벤치 월간 %d개월 → 포트 축 정렬 %d개월 (덮개 %.1f%%)\n", nrow(bench_m), nrow(bench_dt), 100*.cov))
if (.cov < 0.95) stop("벤치 축 덮개 <95% — 컨벤션 불일치 의심(중단)")
## ★축 정합(PREREG §5-c): ym 일치율 100% 확인 — 개수만으로는 키 오류를 못 잡는다
stopifnot(all(format(bench_dt$Date, "%Y%m") %in% bench_m$ym), uniqueN(bench_dt$Date) == nrow(bench_dt))
cat("  ym 일치율 100% · 중복 0 — 축 정합 확인\n")

cat("\n=== 6) canonical_screen_bt 측정 (top-25 EW long-only · 15bps) ===\n")
returns_dt <- fwd[, .(Date, Ticker, Ret_1m = fwd)]
RES <- setNames(vector("list", length(ARMS)), ARMS)
for (a in ARMS) {
  RES[[a]] <- canonical_screen_bt(scores_dt = SC[[a]], returns_dt = returns_dt, bench_dt = bench_dt,
                                  top_n = TOPN, cost_bps_oneway = COST,
                                  strategy_id = paste0("WT005_", a), run_id = paste0("WT005_", a, "_20260813"),
                                  diag_dual_basis = TRUE)
  r <- RES[[a]]
  ## ★기간 손실 감시 (PREREG §5-a): 5% 초과 손실 시 중단
  exp_m <- uniqueN(SC[[a]]$Date)
  if (r$n_months < 0.95 * exp_m) stop(sprintf("★arm %s 기간 손실 %.1f%% — 중단", a, 100*(1-r$n_months/exp_m)))
  cat(sprintf("  %-10s n=%d개월 PORT_t=%+.4f active_sr(=IR)=%+.4f IR=%+.4f alpha_ann=%+.4f TO=%.2f cov=%.3f\n",
              a, r$n_months, r$portfolio_alpha_t_nw_lag3, r$net_sr, r$information_ratio,
              r$alpha_annualized, r$turnover_annual, r$selected_ret_coverage))
}

cat("\n=== 7) ★PRIMARY — paired 월별 active 차이 NW lag-3 t ===\n")
act <- function(a) { p <- as.data.table(RES[[a]]$period_returns)
                     p[, .(date, active = ret_net - benchmark_ret)] }
A <- act("OBJ_RANK")
paired <- function(a) {
  j <- merge(act(a), A, by = "date", suffixes = c("_x","_base"))
  stopifnot(nrow(j) == nrow(A))                     # ★조인 손실 0 요구 (동일 축)
  d <- j$active_x - j$active_base
  list(n = nrow(j), mean = mean(d), t = .nw_t_mean(d, lag = 3L), d = d, date = j$date)
}
PR <- lapply(setNames(setdiff(ARMS, "OBJ_RANK"), setdiff(ARMS, "OBJ_RANK")), paired)
for (a in names(PR)) cat(sprintf("  %-10s − OBJ_RANK : n=%d  월평균차 %+.5f (연 %+.2f%%)  **NW3 t = %+.4f**\n",
                                 a, PR[[a]]$n, PR[[a]]$mean, 100*12*PR[[a]]$mean, PR[[a]]$t))
cat(sprintf("\n  ★사전등록 문턱 +2.0 → OBJ_MEAN t = %+.4f ⇒ **%s**\n", PR$OBJ_MEAN$t,
            if (is.finite(PR$OBJ_MEAN$t) && PR$OBJ_MEAN$t >= 2.0) "SUPPORTED" else "NOT_SUPPORTED"))

cat("\n=== 8) 반증축 ①③ + 안정성 비용 ===\n")
jac <- function(x, y) { u <- length(union(x,y)); if (!u) return(NA_real_); length(intersect(x,y))/u }
nmz <- names(sel$OBJ_MEAN)
j_mr <- vapply(nmz, function(nm) jac(sel$OBJ_MEAN[[nm]], sel$OBJ_RANK[[nm]]), numeric(1))
j_dr <- vapply(nmz, function(nm) jac(sel$OBJ_MED[[nm]],  sel$OBJ_RANK[[nm]]), numeric(1))
j_md <- vapply(nmz, function(nm) jac(sel$OBJ_MEAN[[nm]], sel$OBJ_MED[[nm]]),  numeric(1))
cat(sprintf("  ①집합 분기 Jaccard(S_mean,S_rank) 중앙 %.4f 평균 %.4f (기각선 >0.8)  ⇒ %s\n",
            median(j_mr), mean(j_mr), if (median(j_mr) > 0.8) "★기전 부재 기각" else "통과(집합이 실제로 갈림)"))
cat(sprintf("     참고 Jaccard(S_med,S_rank) 중앙 %.4f · Jaccard(S_mean,S_med) 중앙 %.4f\n", median(j_dr), median(j_md)))
cat(sprintf("  ③특이성 대조 OBJ_MED paired t = %+.4f (기각선 >= +2.0) ⇒ %s\n", PR$OBJ_MED$t,
            if (is.finite(PR$OBJ_MED$t) && PR$OBJ_MED$t >= 2.0) "★특이성 기각" else "통과(대조군 미개선)"))
selfj <- function(a) { s <- sel[[a]]; n <- names(s)
  vapply(2:length(n), function(i) jac(s[[n[i]]], s[[n[i-1]]]), numeric(1)) }
cat("  안정성(자기-겹침 Jaccard 중앙) + 실현 회전율:\n")
for (a in c("OBJ_RANK","OBJ_MEAN","OBJ_MED")) cat(sprintf("     %-9s selfJ=%.4f  turnover_annual=%.3f\n",
            a, median(selfj(a), na.rm=TRUE), RES[[a]]$turnover_annual))
to_ratio <- RES$OBJ_MEAN$turnover_annual / RES$OBJ_RANK$turnover_annual
cat(sprintf("     회전율 배율 OBJ_MEAN/OBJ_RANK = %.3f (상쇄판정선 1.5)\n", to_ratio))

cat("\n=== 9) ★위반 주입 검사의 판별력 (PREREG §4) ===\n")
cat(sprintf("  LOOKAHEAD(1개월 누출) paired t = %+.4f vs clean OBJ_MEAN %+.4f · PORT_t %+.4f vs %+.4f\n",
            PR$LOOKAHEAD$t, PR$OBJ_MEAN$t, RES$LOOKAHEAD$portfolio_alpha_t_nw_lag3, RES$OBJ_MEAN$portfolio_alpha_t_nw_lag3))
cat(sprintf("  LAG1(한 칸 더 물림)  paired t = %+.4f · PORT_t %+.4f\n", PR$LAG1$t, RES$LAG1$portfolio_alpha_t_nw_lag3))
det <- RES$LOOKAHEAD$portfolio_alpha_t_nw_lag3 - RES$OBJ_MEAN$portfolio_alpha_t_nw_lag3
cat(sprintf("  ⇒ 누출 주입 시 PORT_t 상승폭 = %+.4f — %s\n", det,
            if (det > 0.5) "성과 축이 1개월 누출에 **민감**(검사 판별력 있음)" else
                           "★성과 축이 1개월 누출에 **둔감** — 'PIT 통과'를 근거로 쓸 수 없음(정직 기록)"))

saveRDS(list(K=K, W=W, TOPN=TOPN, COST=COST, sel=sel, RES=RES, PR=PR,
             jaccard=list(mean_rank=j_mr, med_rank=j_dr, mean_med=j_md),
             selfj=lapply(c("OBJ_RANK","OBJ_MEAN","OBJ_MED"), function(a) selfj(a)),
             to_ratio=to_ratio, hold_anchors=anchors[hold_idx]),
        file.path(OUT, "s2_walkforward_result.rds"))
write_parquet(SC$OBJ_MEAN, file.path(OUT, "alpha_scores.parquet"))
saveRDS(SC, file.path(OUT, "s2_scores_all_arms.rds"))
cat(sprintf("\n저장: s2_walkforward_result.rds · alpha_scores.parquet (primary arm)\n"))
