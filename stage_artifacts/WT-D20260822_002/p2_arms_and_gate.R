## WT-D20260822_002 · P2 — walk-forward 6 arm 측정 + 반증 축 1 + ★검정력 관문 (mean-blind)
##
## 사전등록: stage_artifacts/WT-D20260822_002/PREREG.json (측정 전 봉인)
## 승계 harness: stage_artifacts/WT-D20260813_005/depth_aligned/d2_walkforward_depth.R (자구)
##
## ★본 파일은 co-primary paired **평균·t 를 출력하지 않는다**(PREREG entry_gate_order_enforced).
##   출력 = 승계 재현 검문 + 반증 축 1(성과 무관) + sd/nw/MDE. paired t 는 P3 소관.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p2_arms_and_gate.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")      # → backtest_result_contract.R (.nw_t_mean)
source("02_Infrastructure/contracts/required_effect_size.R")
SRC  <- "stage_artifacts/fq233_probe0_20260813"
W005 <- "stage_artifacts/WT-D20260813_005"
OUT  <- "stage_artifacts/WT-D20260822_002"

K <- 5L; W <- 36L; TOPN <- 25L; COST <- 15; MIN_OBS <- 30L      # ★PREREG fixed_constants (스윕 0회)

cat("=== 1) 입력 (승계 RDS 자구 + 본 라운드 Pearson 원자료) ===\n")
S1 <- readRDS(file.path(W005, "s1_factor_month_stats.rds"))
D1 <- readRDS(file.path(W005, "depth_aligned", "d1_depth_stats.rds"))
P1 <- readRDS(file.path(OUT,  "p1_pearson_stats.rds"))
FS <- S1$FS; FACS <- S1$FACS; anchors <- S1$anchors; DS <- D1$DS; PS <- P1$PS
stopifnot(identical(D1$FACS, FACS), identical(D1$anchors, anchors), D1$D_DEPTH == TOPN,
          identical(P1$FACS, FACS), identical(P1$anchors, anchors))
cat(sprintf("  %d팩터 · %d개월 (%s ~ %s) · 깊이 D=%d\n", length(FACS), length(anchors),
            min(anchors), max(anchors), D1$D_DEPTH))
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
pan <- pan[anchor %in% anchors & is.finite(fwd_ret_1m)]
cat(sprintf("  z 패널 %d행 · %d개월 · 월중앙 %d종목\n", nrow(pan), uniqueN(pan$anchor),
            as.integer(median(pan[, .N, by = anchor]$N))))

to_mat <- function(dt, col) {
  m <- dcast(dt, anchor ~ fac, value.var = col); a <- m$anchor; m[, anchor := NULL]
  mm <- as.matrix(m); rownames(mm) <- as.character(a); mm[, FACS, drop = FALSE]
}
M_ic <- to_mat(FS, "ic")           # 대조군: Spearman IC          (승계 자구)
M_pe <- to_mat(PS, "ic_pe")        # 처치 a: Pearson IC           (본 라운드)
M_dp <- to_mat(DS, "meandepth")    # 처치 b: top-25 평균 스프레드  (승계 자구)
M_dm <- to_mat(DS, "meddepth")     # 음성 대조: top-25 중앙 스프레드(승계 자구)
stopifnot(identical(rownames(M_ic), as.character(anchors)),
          identical(rownames(M_pe), as.character(anchors)))

cat("\n=== 2) walk-forward 선별 (창: 홀딩월 i 의 선별은 anchor < anchors[i] 만 소비) ===\n")
sel_t <- function(M, rows) {
  sub <- M[rows, , drop = FALSE]
  apply(sub, 2L, function(x) { x <- x[is.finite(x)]
    if (length(x) < MIN_OBS) return(NA_real_); .nw_t_mean(x, lag = 3L) })
}
pick <- function(tv) { ok <- is.finite(tv); if (sum(ok) < K) return(character(0))
                       names(sort(tv[ok], decreasing = TRUE))[seq_len(K)] }
i0 <- W + 1L; hold_idx <- i0:length(anchors)
cat(sprintf("  홀딩월 %d개 (%s ~ %s) · burn-in %d개월\n", length(hold_idx),
            anchors[i0], anchors[length(anchors)], W))
stopifnot(length(hold_idx) == 221L)                       # ★PREREG 재현 검문

ARMS <- c("SEL_RANK","SEL_PEARSON","SEL_MEANDEPTH","NEG_MEDDEPTH","INJ_LOOKAHEAD_PEARSON","LAG1_PEARSON")
sel <- setNames(lapply(ARMS, function(a) setNames(vector("list", length(hold_idx)),
                                                  as.character(anchors[hold_idx]))), ARMS)
div <- vector("list", length(hold_idx))    # 반증 축 1 원자료
t0 <- Sys.time()
for (k in seq_along(hold_idx)) {
  i <- hold_idx[k]; nm <- as.character(anchors[i]); rw <- (i-W):(i-1)
  t_ic <- sel_t(M_ic, rw); t_pe <- sel_t(M_pe, rw); t_dp <- sel_t(M_dp, rw); t_dm <- sel_t(M_dm, rw)
  sel$SEL_RANK[[nm]]             <- pick(t_ic)
  sel$SEL_PEARSON[[nm]]          <- pick(t_pe)
  sel$SEL_MEANDEPTH[[nm]]        <- pick(t_dp)
  sel$NEG_MEDDEPTH[[nm]]         <- pick(t_dm)
  sel$INJ_LOOKAHEAD_PEARSON[[nm]] <- pick(sel_t(M_pe, (i-W+1):i))     # ★위반 주입(1개월 누출)
  sel$LAG1_PEARSON[[nm]]          <- pick(sel_t(M_pe, (i-W):(i-2)))   # PIT 스트레스
  ok <- is.finite(t_ic) & is.finite(t_pe)
  jac <- function(a, b) if (!length(a) || !length(b)) NA_real_ else
    length(intersect(a,b)) / length(union(a,b))
  div[[k]] <- data.table(anchor = anchors[i], n_fac = sum(ok),
    rho_rank_pearson = if (sum(ok) >= 30L) stats::cor(t_ic[ok], t_pe[ok], method="spearman") else NA_real_,
    rho_rank_depth   = { o2 <- is.finite(t_ic) & is.finite(t_dp)
                         if (sum(o2) >= 30L) stats::cor(t_ic[o2], t_dp[o2], method="spearman") else NA_real_ },
    jac_rank_pearson = jac(sel$SEL_RANK[[nm]], sel$SEL_PEARSON[[nm]]),
    jac_rank_depth   = jac(sel$SEL_RANK[[nm]], sel$SEL_MEANDEPTH[[nm]]))
  if (k %% 60 == 0) cat(sprintf("    %d/%d (%.1f분)\n", k, length(hold_idx),
                                as.numeric(difftime(Sys.time(), t0, units="mins"))))
}
DIV <- rbindlist(div)
for (a in ARMS) if (any(lengths(sel[[a]]) < K)) stop(sprintf("★arm %s: K 미달 월 존재 — 중단", a))
cat(sprintf("  선별 완료 %.1f분\n", as.numeric(difftime(Sys.time(), t0, units="mins"))))

cat("\n=== 3) ★반증 축 1 — 선별 분기 (성과 무관 · PREREG falsification_axes) ===\n")
cat(sprintf("  rho(rank-IC t 서열, Pearson-IC t 서열)  중앙 %+.4f  [기각 문턱 >= 0.90]\n", median(DIV$rho_rank_pearson, na.rm=TRUE)))
cat(sprintf("  rho(rank-IC t 서열, meandepth t 서열)   중앙 %+.4f  (대조 병기)\n", median(DIV$rho_rank_depth, na.rm=TRUE)))
cat(sprintf("  top-%d Jaccard  rank vs Pearson  중앙 %.4f  평균 %.4f  [기각 문턱 >= 0.80]\n", K,
            median(DIV$jac_rank_pearson, na.rm=TRUE), mean(DIV$jac_rank_pearson, na.rm=TRUE)))
cat(sprintf("  top-%d Jaccard  rank vs meandepth 중앙 %.4f  평균 %.4f  (WT005 실측 0.111~0.25 대조)\n", K,
            median(DIV$jac_rank_depth, na.rm=TRUE), mean(DIV$jac_rank_depth, na.rm=TRUE)))
axis1_fire <- (median(DIV$rho_rank_pearson, na.rm=TRUE) >= 0.90) || (median(DIV$jac_rank_pearson, na.rm=TRUE) >= 0.80)
cat(sprintf("  ⇒ 반증 축 1 (a) : %s\n", if (axis1_fire) "★발화 — 판정 불능(AXIS1_NO_DIVERGENCE)" else "미발화 (집합 분기 확인)"))

cat("\n=== 4) 합성 스코어 (선별 K개 Z_Score_Aligned 종목별 단순평균 · 결측 제외, 0 대입 없음) ===\n")
build_scores <- function(selmap) {
  rbindlist(lapply(names(selmap), function(nm) {
    fs <- selmap[[nm]]; if (!length(fs)) return(NULL)
    d <- pan[anchor == as.Date(nm)]
    Z <- as.matrix(d[, ..fs]); sc <- rowMeans(Z, na.rm = TRUE); nv <- rowSums(is.finite(Z))
    data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker),
               score = ifelse(nv >= 1L, sc, NA_real_), n_fac_used = nv)[is.finite(score)]
  }))
}
SC <- lapply(sel, build_scores)
for (a in ARMS) cat(sprintf("  %-22s %6d행 · %d개월 · 월중앙 %d종목 · 평균 사용팩터 %.2f/%d\n", a,
    nrow(SC[[a]]), uniqueN(SC[[a]]$Date), as.integer(median(SC[[a]][, .N, by=Date]$N)),
    mean(SC[[a]]$n_fac_used), K))

cat("\n=== 5) 축 정합 검증 — 합성 스코어 → forward IC 부호 (양수여야 정상) ===\n")
fwd <- pan[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)]
axis_ok <- TRUE
for (a in ARMS) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_), by = Date]
  mi <- mean(ic$ic, na.rm=TRUE); if (mi <= 0) axis_ok <- FALSE
  cat(sprintf("  %-22s 평균 IC = %+.5f (n=%d)  %s\n", a, mi, nrow(ic),
              if (mi > 0) "부호 정상(+)" else "★부호 음수 — 앵커 오정렬 의심"))
}
stopifnot(axis_ok)

cat("\n=== 6) 벤치마크 (일별 → apply.monthly · ym 키) ===\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(fwd[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
.cov <- nrow(bench_dt) / uniqueN(fwd$Date)
cat(sprintf("  벤치 월간 %d개월 → 포트 축 정렬 %d개월 (덮개 %.1f%%) · 원천 .cache/benchmark.parquet\n",
            nrow(bench_m), nrow(bench_dt), 100*.cov))
if (.cov < 0.95) stop("벤치 축 덮개 <95% — 중단")

cat("\n=== 7) canonical_screen_bt (top-25 EW long-only · 15bps · 유동성 미적용 = 승계 자구) ===\n")
returns_dt <- fwd[, .(Date, Ticker, Ret_1m = fwd)]
RES <- setNames(vector("list", length(ARMS)), ARMS)
for (a in ARMS) {
  RES[[a]] <- canonical_screen_bt(scores_dt = SC[[a]], returns_dt = returns_dt, bench_dt = bench_dt,
                                  top_n = TOPN, cost_bps_oneway = COST,
                                  strategy_id = paste0("FQ237_", a), run_id = paste0("FQ237_", a, "_20260822"),
                                  diag_dual_basis = TRUE)
  r <- RES[[a]]; exp_m <- uniqueN(SC[[a]]$Date)
  if (r$n_months < 0.95 * exp_m) stop(sprintf("★arm %s 기간 손실 %.1f%% — 중단", a, 100*(1-r$n_months/exp_m)))
}
cat("  (arm 별 성과 수치는 P3 에서 출력 — 관문 전 mean-blind 유지)\n")

cat("\n=== 8) ★승계 재현 검문 (PREREG reproduction_checkpoints — 사전 고정값) ===\n")
chk <- function(label, got, want, tol = 5e-4) {
  ok <- is.finite(got) && abs(got - want) <= tol
  cat(sprintf("  %-38s 실측 %+.5f · 사전등록 %+.5f · Δ %+.6f  ⇒ %s\n",
              label, got, want, got - want, if (ok) "재현" else "★불일치"))
  ok
}
rep_ok <- c(
  chk("SEL_RANK cap-w PORT_t",      RES$SEL_RANK$portfolio_alpha_t_nw_lag3,      0.94741),
  chk("SEL_RANK active_sr(=IR)",    RES$SEL_RANK$net_sr,                        0.22811),
  chk("SEL_MEANDEPTH cap-w PORT_t", RES$SEL_MEANDEPTH$portfolio_alpha_t_nw_lag3, 1.77748),
  chk("SEL_MEANDEPTH active_sr",    RES$SEL_MEANDEPTH$net_sr,                    0.48594))
cat(sprintf("  재현 %d/%d\n", sum(rep_ok), length(rep_ok)))

cat("\n=== 9) ★검정력 관문 (mean-blind — sd/nw/MDE 만) ===\n")
getpr <- function(a) RES[[a]]$period_returns[, .(date, ret_net)]
mkdiff <- function(a, b) {
  m <- merge(getpr(a), getpr(b), by = "date", suffixes = c("_a","_b"))
  m[, .(date, d = ret_net_a - ret_net_b)]
}
GATE <- rbindlist(lapply(list(c("SEL_PEARSON","SEL_RANK"), c("SEL_MEANDEPTH","SEL_RANK"),
                              c("NEG_MEDDEPTH","SEL_RANK"), c("INJ_LOOKAHEAD_PEARSON","SEL_RANK"),
                              c("LAG1_PEARSON","SEL_RANK")), function(p) {
  dd <- mkdiff(p[1], p[2]); s <- sd(dd$d); n <- nrow(dd)
  re <- required_effect(n = n, t_threshold = 2.0, sd_monthly = s, design = "full", series = dd$d)
  data.table(contrast = paste(p[1], "-", p[2]), n = n, sd_monthly = s,
             nw_inflation = re$nw_inflation, nw_source = re$nw_inflation_source,
             mde_annual_pct = 100 * re$required_annual)
}))
print(GATE)
cat(sprintf("\n  관문 문턱 = 연 3.0%%p. 통과 = %s\n",
            paste(GATE[mde_annual_pct <= 3.0, contrast], collapse = " | ")))

saveRDS(list(sel = sel, SC = SC, RES = RES, DIV = DIV, GATE = GATE, bench_dt = bench_dt,
             returns_dt = returns_dt, anchors = anchors, hold_idx = hold_idx, ARMS = ARMS,
             K = K, W = W, TOPN = TOPN, COST = COST, rep_ok = rep_ok, axis1_fire = axis1_fire),
        file.path(OUT, "p2_arms.rds"))
cat("\n[saved] p2_arms.rds — P3 가 소비\n")
