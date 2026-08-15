## WT-D20260813_005 후속 · D2 — 깊이-정합 walk-forward 6 arm + 위반주입 대조 + primary
##
## 사전등록: stage_artifacts/WT-D20260813_005/depth_aligned/PREREG_depth.md (측정 전 봉인)
##   유일한 변경점 = 선별 통계량의 상위 버킷 깊이 Q5(20%) → **top-25(7.27%)**. 그 외 전부 직전과 동일.
##
## arm 6종 (재료·구성 전부 동일, **선별 통계량만** 다르다):
##   OBJ_RANK        = trailing rank-IC 의 NW3 t 상위 K            ← base (직전 재현 검문)
##   OBJ_MEAN_DEPTH  = trailing (top-25 평균 − 전체 평균) NW3 t     ← ★primary
##   OBJ_MEAN_Q5     = trailing (Q5 평균 − 전체 평균) NW3 t         ← 보조 대조 (직전 재현 검문)
##   OBJ_MED_DEPTH   = trailing (top-25 중앙 − 전체 중앙) NW3 t     ← negative control (같은 깊이)
##   LOOKAHEAD_DEPTH = OBJ_MEAN_DEPTH 인데 창에 **홀딩월 자신** 포함 ← ★위반 주입 (검사 판별력)
##   LAG1_DEPTH      = OBJ_MEAN_DEPTH 인데 창을 한 칸 더 물림(T−2)  ← PIT 스트레스
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d2_walkforward_depth.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # → backtest_result_contract.R (.nw_t_mean)
SRC  <- "stage_artifacts/fq233_probe0_20260813"
OUT  <- "stage_artifacts/WT-D20260813_005"
DOUT <- file.path(OUT, "depth_aligned")

K <- 5L; W <- 36L; TOPN <- 25L; COST <- 15                # ★PREREG §2 승계 (스윕 0회)
MIN_OBS <- 30L

cat("=== 1) 입력 ===\n")
S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
D1 <- readRDS(file.path(DOUT, "d1_depth_stats.rds"))
FS <- S1$FS; FACS <- S1$FACS; anchors <- S1$anchors
stopifnot(identical(D1$FACS, FACS), identical(D1$anchors, anchors), D1$D_DEPTH == TOPN)
DS <- D1$DS
cat(sprintf("  Q5 통계 %d행 · DEPTH 통계 %d행 · %d개월 · %d팩터 · 깊이 D=%d (%.2f%%)\n",
            nrow(FS), nrow(DS), length(anchors), length(FACS), D1$D_DEPTH, 100*D1$depth_frac_median))
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
pan <- pan[anchor %in% anchors & is.finite(fwd_ret_1m)]
cat(sprintf("  z 패널 %d행 · %d개월 · 월중앙 %d종목\n", nrow(pan), uniqueN(pan$anchor),
            as.integer(median(pan[, .N, by = anchor]$N))))

to_mat <- function(dt, col) {
  m <- dcast(dt, anchor ~ fac, value.var = col)
  a <- m$anchor; m[, anchor := NULL]
  mm <- as.matrix(m); rownames(mm) <- as.character(a); mm[, FACS, drop = FALSE]
}
M_ic <- to_mat(FS, "ic")            # rank-IC          (base)
M_q5 <- to_mat(FS, "meanspread")    # Q5 평균 스프레드  (직전 primary)
M_dp <- to_mat(DS, "meandepth")     # top-25 평균 스프레드 (★신규 primary)
M_dm <- to_mat(DS, "meddepth")      # top-25 중앙 스프레드 (negative control)
M_ss <- to_mat(FS, "skewslope")     # 분위 왜도기울기   (반증축 ② 계승)
M_st <- to_mat(DS, "skewtop")       # 상위 25종 왜도    (반증축 ② 깊이-네이티브)
stopifnot(identical(rownames(M_ic), as.character(anchors)),
          identical(rownames(M_dp), as.character(anchors)))

cat("\n=== 2) walk-forward 선별 ===\n")
## 창 규약(PREREG §2): 홀딩월 i 의 선별은 **anchor < anchors[i]** 인 실현 통계만 소비.
##   OBJ_*           : rows (i-W) .. (i-1)
##   LOOKAHEAD_DEPTH : rows (i-W+1) .. i    ← 홀딩월 자신 포함 = 1개월 누출 (위반 주입)
##   LAG1_DEPTH      : rows (i-W) .. (i-2)  ← 한 칸 더 물림
sel_topK <- function(M, rows) {
  sub <- M[rows, , drop = FALSE]
  tv <- apply(sub, 2L, function(x) { x <- x[is.finite(x)]
    if (length(x) < MIN_OBS) return(NA_real_); .nw_t_mean(x, lag = 3L) })
  ok <- is.finite(tv)
  if (sum(ok) < K) return(character(0))
  names(sort(tv[ok], decreasing = TRUE))[seq_len(K)]
}
i0 <- W + 1L; hold_idx <- i0:length(anchors)
cat(sprintf("  홀딩월 %d개 (%s ~ %s) · burn-in %d개월\n", length(hold_idx),
            anchors[i0], anchors[length(anchors)], W))
stopifnot(length(hold_idx) == 221L)                       # ★PREREG §6-c 재현 검문

ARMS <- c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5","OBJ_MED_DEPTH","LOOKAHEAD_DEPTH","LAG1_DEPTH")
sel <- setNames(vector("list", length(ARMS)), ARMS)
for (a in ARMS) sel[[a]] <- setNames(vector("list", length(hold_idx)), as.character(anchors[hold_idx]))
t0 <- Sys.time()
for (k in seq_along(hold_idx)) {
  i <- hold_idx[k]; nm <- as.character(anchors[i])
  sel$OBJ_RANK[[nm]]        <- sel_topK(M_ic, (i-W):(i-1))
  sel$OBJ_MEAN_DEPTH[[nm]]  <- sel_topK(M_dp, (i-W):(i-1))
  sel$OBJ_MEAN_Q5[[nm]]     <- sel_topK(M_q5, (i-W):(i-1))
  sel$OBJ_MED_DEPTH[[nm]]   <- sel_topK(M_dm, (i-W):(i-1))
  sel$LOOKAHEAD_DEPTH[[nm]] <- sel_topK(M_dp, (i-W+1):i)         # ★위반 주입
  sel$LAG1_DEPTH[[nm]]      <- sel_topK(M_dp, (i-W):(i-2))
  if (k %% 60 == 0) cat(sprintf("    %d/%d (%.1f분)\n", k, length(hold_idx),
                                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
cat(sprintf("  선별 완료 %.1f분\n", as.numeric(difftime(Sys.time(), t0, units="mins"))))
for (a in ARMS) if (any(lengths(sel[[a]]) < K)) stop(sprintf("★arm %s: K 미달 월 존재 — 중단", a))

cat("\n=== 3) 합성 스코어 (선별 K개 Z_Score_Aligned 종목별 단순평균) ===\n")
build_scores <- function(selmap) {
  rbindlist(lapply(names(selmap), function(nm) {
    fs <- selmap[[nm]]; if (!length(fs)) return(NULL)
    d <- pan[anchor == as.Date(nm)]
    Z <- as.matrix(d[, ..fs]); sc <- rowMeans(Z, na.rm = TRUE); nv <- rowSums(is.finite(Z))
    data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker),
               score = ifelse(nv >= 1L, sc, NA_real_))[is.finite(score)]
  }))
}
SC <- lapply(sel, build_scores)
for (a in ARMS) cat(sprintf("  %-16s %6d행 · %d개월 · 월중앙 %d종목\n", a, nrow(SC[[a]]),
                            uniqueN(SC[[a]]$Date), as.integer(median(SC[[a]][, .N, by=Date]$N))))

cat("\n=== 4) 축 정합 검증 (PREREG §7-b) — 합성 스코어 → forward IC 부호 ===\n")
fwd <- pan[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)]
for (a in ARMS) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_), by = Date]
  cat(sprintf("  %-16s 평균 IC = %+.5f (n=%d개월)  %s\n", a, mean(ic$ic, na.rm=TRUE), nrow(ic),
              if (mean(ic$ic, na.rm=TRUE) > 0) "부호 정상(+)" else "★부호 음수 — 앵커 오정렬 의심"))
}

cat("\n=== 5) 벤치마크 (일별 → apply.monthly · ym 키) ===\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(fwd[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
.cov <- nrow(bench_dt) / uniqueN(fwd$Date)
cat(sprintf("  벤치 월간 %d개월 → 포트 축 정렬 %d개월 (덮개 %.1f%%)\n", nrow(bench_m), nrow(bench_dt), 100*.cov))
if (.cov < 0.95) stop("벤치 축 덮개 <95% — 컨벤션 불일치 의심(중단)")
stopifnot(all(format(bench_dt$Date, "%Y%m") %in% bench_m$ym), uniqueN(bench_dt$Date) == nrow(bench_dt))
cat("  ym 일치율 100% · 중복 0 — 축 정합 확인 (PREREG §7-c)\n")

cat("\n=== 6) canonical_screen_bt 측정 (top-25 EW long-only · 15bps) ===\n")
returns_dt <- fwd[, .(Date, Ticker, Ret_1m = fwd)]
RES <- setNames(vector("list", length(ARMS)), ARMS)
for (a in ARMS) {
  RES[[a]] <- canonical_screen_bt(scores_dt = SC[[a]], returns_dt = returns_dt, bench_dt = bench_dt,
                                  top_n = TOPN, cost_bps_oneway = COST,
                                  strategy_id = paste0("WT005D_", a), run_id = paste0("WT005D_", a, "_20260813"),
                                  diag_dual_basis = TRUE)
  r <- RES[[a]]; exp_m <- uniqueN(SC[[a]]$Date)
  if (r$n_months < 0.95 * exp_m) stop(sprintf("★arm %s 기간 손실 %.1f%% — 중단", a, 100*(1-r$n_months/exp_m)))
  cat(sprintf("  %-16s n=%d PORT_t=%+.4f active_sr(=IR)=%+.4f alpha_ann=%+.4f TO=%.2f cov=%.3f\n",
              a, r$n_months, r$portfolio_alpha_t_nw_lag3, r$net_sr, r$alpha_annualized,
              r$turnover_annual, r$selected_ret_coverage))
}

cat("\n=== 7) ★프레임 재현 검문 (PREREG §6) — 깊이만 바꿨으므로 직전 arm 은 재현되어야 한다 ===\n")
chk <- function(label, got, want, tol = 5e-4) {
  ok <- is.finite(got) && abs(got - want) <= tol
  cat(sprintf("  %-34s 실측 %+.5f · 사전등록 %+.5f · Δ %+.6f  ⇒ %s\n",
              label, got, want, got - want, if (ok) "재현" else "★불일치"))
  ok
}
ok1 <- chk("(a) OBJ_RANK cap-w PORT_t",    RES$OBJ_RANK$portfolio_alpha_t_nw_lag3, 0.94741)
ok2 <- chk("(a) OBJ_RANK active_sr(=IR)",  RES$OBJ_RANK$net_sr,                    0.22811)
ok4 <- chk("(b) OBJ_MEAN_Q5 PORT_t",       RES$OBJ_MEAN_Q5$portfolio_alpha_t_nw_lag3, 0.98991)

cat("\n=== 8) ★PRIMARY — paired 월별 active 차이 NW lag-3 t (vs OBJ_RANK) ===\n")
act <- function(a) { p <- as.data.table(RES[[a]]$period_returns)
                     p[, .(date, active = ret_net - benchmark_ret)] }
A <- act("OBJ_RANK")
paired <- function(a) {
  j <- merge(act(a), A, by = "date", suffixes = c("_x","_base"))
  stopifnot(nrow(j) == nrow(A))                 # ★조인 손실 0 요구 (PREREG §7-d)
  d <- j$active_x - j$active_base
  list(n = nrow(j), mean = mean(d), t = .nw_t_mean(d, lag = 3L), d = d, date = j$date)
}
onm <- setdiff(ARMS, "OBJ_RANK")
PR <- lapply(setNames(onm, onm), paired)
for (a in onm) cat(sprintf("  %-16s − OBJ_RANK : n=%d  월평균차 %+.5f (연 %+.2f%%)  **NW3 t = %+.4f**\n",
                           a, PR[[a]]$n, PR[[a]]$mean, 100*12*PR[[a]]$mean, PR[[a]]$t))
ok3 <- chk("(b) OBJ_MEAN_Q5 paired NW3 t", PR$OBJ_MEAN_Q5$t, 0.49298)
frame_ok <- ok1 && ok2 && ok3 && ok4
cat(sprintf("  ⇒ 프레임 재현 %s\n", if (frame_ok) "PASS (4/4) — 승계 성립" else "★FAIL — 프레임 드리프트, 판정 보류"))

cat("\n  ★사전등록 문턱 +2.0\n")
cat(sprintf("     OBJ_MEAN_DEPTH (primary) t = %+.4f ⇒ **%s**\n", PR$OBJ_MEAN_DEPTH$t,
            if (is.finite(PR$OBJ_MEAN_DEPTH$t) && PR$OBJ_MEAN_DEPTH$t >= 2.0) "SUPPORTED" else "NOT_SUPPORTED"))
cat(sprintf("     OBJ_MEAN_Q5 (직전, 보조)  t = %+.4f\n", PR$OBJ_MEAN_Q5$t))
cat(sprintf("     깊이 효과 = primary − 직전 = %+.4f\n", PR$OBJ_MEAN_DEPTH$t - PR$OBJ_MEAN_Q5$t))
## 두 arm 이 서로 다른지 직접 검정 (깊이가 드라이버인지 — paired of paired)
dd <- PR$OBJ_MEAN_DEPTH$d - PR$OBJ_MEAN_Q5$d
cat(sprintf("     DEPTH vs Q5 직접 paired: 월평균차 %+.5f · NW3 t %+.4f (두 arm 이 같은 수익을 내는가)\n",
            mean(dd), .nw_t_mean(dd, lag = 3L)))

cat("\n=== 9) 반증축 ①③ + 안정성 비용 ===\n")
jac <- function(x, y) { u <- length(union(x,y)); if (!u) return(NA_real_); length(intersect(x,y))/u }
nmz <- names(sel$OBJ_MEAN_DEPTH)
j_dr <- vapply(nmz, function(nm) jac(sel$OBJ_MEAN_DEPTH[[nm]], sel$OBJ_RANK[[nm]]),    numeric(1))
j_dq <- vapply(nmz, function(nm) jac(sel$OBJ_MEAN_DEPTH[[nm]], sel$OBJ_MEAN_Q5[[nm]]), numeric(1))
j_dm <- vapply(nmz, function(nm) jac(sel$OBJ_MEAN_DEPTH[[nm]], sel$OBJ_MED_DEPTH[[nm]]), numeric(1))
ax1_fired <- median(j_dr) > 0.8
cat(sprintf("  ①집합 분기 Jaccard(S_depth, S_rank) 중앙 %.4f 평균 %.4f (기각선 >0.8) ⇒ %s\n",
            median(j_dr), mean(j_dr), if (ax1_fired) "★기전 부재 기각" else "통과(집합이 실제로 갈림)"))
cat(sprintf("     참고 Jaccard(S_depth, S_meanQ5) 중앙 %.4f  ← 깊이 변경이 선별 집합을 얼마나 바꿨나\n", median(j_dq)))
cat(sprintf("     참고 Jaccard(S_depth, S_medDepth) 중앙 %.4f\n", median(j_dm)))
ax3_fired <- is.finite(PR$OBJ_MED_DEPTH$t) && PR$OBJ_MED_DEPTH$t >= 2.0
cat(sprintf("  ③특이성 대조 OBJ_MED_DEPTH paired t = %+.4f (기각선 >= +2.0) ⇒ %s\n", PR$OBJ_MED_DEPTH$t,
            if (ax3_fired) "★특이성 기각" else "통과(대조군 미개선)"))
selfj <- function(a) { s <- sel[[a]]; n <- names(s)
  vapply(2:length(n), function(i) jac(s[[n[i]]], s[[n[i-1]]]), numeric(1)) }
cat("  안정성(자기-겹침 Jaccard 중앙) + 실현 회전율:\n")
for (a in c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5","OBJ_MED_DEPTH"))
  cat(sprintf("     %-16s selfJ=%.4f  turnover_annual=%.3f\n", a, median(selfj(a), na.rm=TRUE),
              RES[[a]]$turnover_annual))
to_ratio <- RES$OBJ_MEAN_DEPTH$turnover_annual / RES$OBJ_RANK$turnover_annual
cat(sprintf("     회전율 배율 DEPTH/RANK = %.3f (상쇄판정선 1.5)\n", to_ratio))

cat("\n=== 10) 반증축 ② — 왜도 프로파일 분기 (계승 축 + 깊이-네이티브 축) ===\n")
idx <- match(as.character(anchors[hold_idx]), rownames(M_ss))
ss_grp <- rbindlist(lapply(seq_along(hold_idx), function(k) {
  nm <- as.character(anchors[hold_idx[k]])
  sr <- setdiff(sel$OBJ_RANK[[nm]],       sel$OBJ_MEAN_DEPTH[[nm]])   # rank-단독
  sd_ <- setdiff(sel$OBJ_MEAN_DEPTH[[nm]], sel$OBJ_RANK[[nm]])        # depth-단독
  if (!length(sr) || !length(sd_)) return(NULL)
  rows <- (idx[k]-W):(idx[k]-1)                                       # 선별과 같은 정보집합 (PIT)
  s1s <- M_ss[rows, , drop=FALSE]; s2s <- M_st[rows, , drop=FALSE]
  data.table(anchor = anchors[hold_idx[k]],
             ss_rank_only  = mean(colMeans(s1s[, sr,  drop=FALSE], na.rm=TRUE), na.rm=TRUE),
             ss_depth_only = mean(colMeans(s1s[, sd_, drop=FALSE], na.rm=TRUE), na.rm=TRUE),
             st_rank_only  = mean(colMeans(s2s[, sr,  drop=FALSE], na.rm=TRUE), na.rm=TRUE),
             st_depth_only = mean(colMeans(s2s[, sd_, drop=FALSE], na.rm=TRUE), na.rm=TRUE))
}))
ss_grp[, `:=`(d_slope = ss_rank_only - ss_depth_only, d_top = st_depth_only - st_rank_only)]
t_slope <- .nw_t_mean(ss_grp$d_slope[is.finite(ss_grp$d_slope)], lag = 3L)
t_top   <- .nw_t_mean(ss_grp$d_top[is.finite(ss_grp$d_top)],     lag = 3L)
cat(sprintf("  (계승) 분위 왜도기울기: rank-단독 %+.5f · depth-단독 %+.5f · 차 %+.5f · NW3 t %+.4f (예측: 음)\n",
            mean(ss_grp$ss_rank_only, na.rm=TRUE), mean(ss_grp$ss_depth_only, na.rm=TRUE),
            mean(ss_grp$d_slope, na.rm=TRUE), t_slope))
cat(sprintf("  (깊이) 상위25 왜도    : rank-단독 %+.5f · depth-단독 %+.5f · 차 %+.5f · NW3 t %+.4f (예측: 양)\n",
            mean(ss_grp$st_rank_only, na.rm=TRUE), mean(ss_grp$st_depth_only, na.rm=TRUE),
            mean(ss_grp$d_top, na.rm=TRUE), t_top))
ax2_dir_ok <- is.finite(t_slope) && mean(ss_grp$d_slope, na.rm=TRUE) < 0
ax2_sig <- is.finite(t_slope) && t_slope <= -2
ax2_fired <- (!ax2_dir_ok || !ax2_sig)
cat(sprintf("  ⇒ 반증축 ② : %s\n", if (ax2_fired) "★발화(방향 불일치 또는 구분 불가)" else "통과"))

cat("\n=== 11) ★위반 주입 검사의 판별력 (PREREG §5) ===\n")
cat(sprintf("  LOOKAHEAD_DEPTH paired t = %+.4f vs clean %+.4f · PORT_t %+.4f vs %+.4f\n",
            PR$LOOKAHEAD_DEPTH$t, PR$OBJ_MEAN_DEPTH$t,
            RES$LOOKAHEAD_DEPTH$portfolio_alpha_t_nw_lag3, RES$OBJ_MEAN_DEPTH$portfolio_alpha_t_nw_lag3))
cat(sprintf("  LAG1_DEPTH      paired t = %+.4f · PORT_t %+.4f\n",
            PR$LAG1_DEPTH$t, RES$LAG1_DEPTH$portfolio_alpha_t_nw_lag3))
det <- RES$LOOKAHEAD_DEPTH$portfolio_alpha_t_nw_lag3 - RES$OBJ_MEAN_DEPTH$portfolio_alpha_t_nw_lag3
mono <- RES$LAG1_DEPTH$portfolio_alpha_t_nw_lag3 < RES$OBJ_MEAN_DEPTH$portfolio_alpha_t_nw_lag3 &&
        RES$OBJ_MEAN_DEPTH$portfolio_alpha_t_nw_lag3 < RES$LOOKAHEAD_DEPTH$portfolio_alpha_t_nw_lag3
cat(sprintf("  ⇒ 누출 주입 시 PORT_t 상승폭 = %+.4f · paired t 상승 %+.4f — %s\n", det,
            PR$LOOKAHEAD_DEPTH$t - PR$OBJ_MEAN_DEPTH$t,
            if (det > 0.5) "판별력 있음 (성과 축이 1개월 누출에 민감)" else
                           "★둔감 — 'PIT 통과'를 근거로 쓸 수 없음(정직 기록)"))
cat(sprintf("  단조 lag-반응 (LAG1 < clean < LOOKAHEAD): %s (%.4f < %.4f < %.4f)\n",
            if (mono) "유지" else "★깨짐", RES$LAG1_DEPTH$portfolio_alpha_t_nw_lag3,
            RES$OBJ_MEAN_DEPTH$portfolio_alpha_t_nw_lag3, RES$LOOKAHEAD_DEPTH$portfolio_alpha_t_nw_lag3))

saveRDS(list(K=K, W=W, TOPN=TOPN, COST=COST, D_DEPTH=D1$D_DEPTH, sel=sel, RES=RES, PR=PR,
             frame_repro = list(rank_port_t = RES$OBJ_RANK$portfolio_alpha_t_nw_lag3,
                                rank_ir = RES$OBJ_RANK$net_sr,
                                q5_port_t = RES$OBJ_MEAN_Q5$portfolio_alpha_t_nw_lag3,
                                q5_paired_t = PR$OBJ_MEAN_Q5$t, pass = frame_ok),
             depth_vs_q5 = list(mean = mean(dd), nw3_t = .nw_t_mean(dd, lag=3L)),
             jaccard = list(depth_rank = j_dr, depth_q5 = j_dq, depth_med = j_dm),
             selfj = lapply(setNames(c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5","OBJ_MED_DEPTH"),
                                     c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5","OBJ_MED_DEPTH")), selfj),
             to_ratio = to_ratio, ss_grp = ss_grp,
             falsification = list(ax1_fired = ax1_fired, ax2_fired = ax2_fired, ax3_fired = ax3_fired,
                                  ax2_slope_t = t_slope, ax2_top_t = t_top),
             detection = list(delta_port_t = det, monotone = mono),
             hold_anchors = anchors[hold_idx]),
        file.path(DOUT, "d2_result.rds"))
saveRDS(SC, file.path(DOUT, "d2_scores_all_arms.rds"))
write_parquet(SC$OBJ_MEAN_DEPTH, file.path(DOUT, "alpha_scores_depth.parquet"))
cat(sprintf("\n저장: %s/d2_result.rds · alpha_scores_depth.parquet (primary arm)\n", DOUT))
