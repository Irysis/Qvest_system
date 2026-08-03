# =============================================================================
# analyze_dualbasis.R — WT-D20260803_005 (FQ-131) Step D
#   Step C2가 드러낸 지배 구조: 창별 전체-factor 평균 t (era 공통성분)가 부호 판정을
#   좌우한다 (primary 창4 = 2021-07~2026-06 에서 285 factor 중 양수 2.1%).
#   v8.3 dual-basis mandate: cap-w 판정 권위는 불변이되, **EW-유니버스 벤치**에서도
#   같은 era 붕괴가 나는지 확인해야 "판정 불안정 = 벤치 구성 아티팩트" 가설을 가른다.
#
#   추가 처리:
#     D1 EW-유니버스 벤치 기준 active 재산출 → 지속성/era 전량 재측정 (진단, 비바인딩)
#     D2 era 분해: 판정 부호가 era 부호와 몇 % 일치하는가 (= 판정이 factor 라벨인가 era 라벨인가)
#     D3 time-clustered 추론 (창 전이 단위) + 전이별 persistence 원자료
#     D4 클러스터링 재설계: 단일연결 chaining(246/285 한 덩어리) → 평균연결 k=PC90
#     D5 lag1 스트레스 (대표 12 factor) + AX-001 조건부(BM<0 월) 병기
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/analyze_dualbasis.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005D] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag = 3L) .nw_t_mean(x, lag = lag)

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
CP  <- readRDS(file.path(OUT, "canonical_pool.rds"))
META<- readRDS(file.path(OUT, "pool_meta.rds"))
A <- P1R$A; POOL <- P1R$pool; GRIDS <- P1R$grids; RES <- CP$res
DATES <- as.Date(rownames(A))

make_bounds <- function(n, W) { b <- list(); e <- n
  while (e - W + 1L >= 1L) { b[[length(b)+1L]] <- c(e-W+1L, e); e <- e-W }; rev(b) }
window_t <- function(vec, bounds, min_obs) vapply(bounds, function(ix) {
  x <- vec[ix[1]:ix[2]]; xv <- x[is.finite(x)]
  if (length(xv) < min_obs || length(xv)/(ix[2]-ix[1]+1L) < 0.90) return(NA_real_)
  nw_t(xv) }, numeric(1))
pairs_of <- function(TT) rbindlist(lapply(seq_len(nrow(TT)-1L), function(k) {
  tk <- TT[k,]; tn <- TT[k+1L,]; ok <- is.finite(tk) & is.finite(tn)
  if (!any(ok)) return(NULL)
  data.table(Factor_Name = colnames(TT)[ok], k = k, t_k = tk[ok], t_next = tn[ok]) }))
build_T <- function(M, W, min_obs) {
  bnd <- make_bounds(nrow(M), W)
  TT <- vapply(colnames(M), function(f) window_t(M[, f], bnd, min_obs), numeric(length(bnd)))
  if (is.null(dim(TT))) TT <- matrix(TT, nrow = length(bnd), dimnames = list(NULL, colnames(M)))
  list(t = TT, from = DATES[vapply(bnd,`[`,integer(1),1)], to = DATES[vapply(bnd,`[`,integer(1),2)])
}

# ── D1. EW-유니버스 벤치 기준 active ────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, META$sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
BM_EW <- returns_dt[, .(BM_EW = mean(Ret_1m, na.rm = TRUE)), by = Date]
BMS <- merge(bench_dt, BM_EW, by = "Date")[Date %in% DATES]
setkey(BMS, Date)
shift_v <- BMS[.(DATES), BM_Ret - BM_EW]        # cap-w − EW (벤치 구성 차이)
A_EW <- A + matrix(shift_v, nrow = nrow(A), ncol = ncol(A))   # active_ew = active_cap + (BMcap − BMew)
say("벤치 차이(cap-w − EW) 월평균 %+.3f%% | 연율 %+.2f%% | 2021-07~ 구간 월평균 %+.3f%%",
    100*mean(shift_v, na.rm=TRUE), 100*mean(shift_v, na.rm=TRUE)*12,
    100*mean(shift_v[DATES >= as.Date("2021-07-01")], na.rm=TRUE))

TG_cap <- lapply(GRIDS, function(g) build_T(A,    g$W, g$min_obs))
TG_ew  <- lapply(GRIDS, function(g) build_T(A_EW, g$W, g$min_obs))
PR_cap <- lapply(TG_cap, function(g) pairs_of(g$t))
PR_ew  <- lapply(TG_ew,  function(g) pairs_of(g$t))
DB <- rbindlist(lapply(names(GRIDS), function(nm) data.table(grid = nm,
  p_cap = mean(sign(PR_cap[[nm]]$t_k) == sign(PR_cap[[nm]]$t_next)),
  p_ew  = mean(sign(PR_ew[[nm]]$t_k)  == sign(PR_ew[[nm]]$t_next)),
  share_pos_cap = mean(TG_cap[[nm]]$t > 0, na.rm = TRUE),
  share_pos_ew  = mean(TG_ew[[nm]]$t  > 0, na.rm = TRUE))))
print(DB)

ERA2 <- rbindlist(lapply(names(GRIDS), function(nm) data.table(grid = nm,
  k = seq_len(nrow(TG_cap[[nm]]$t)), from = TG_cap[[nm]]$from, to = TG_cap[[nm]]$to,
  mean_t_cap = apply(TG_cap[[nm]]$t, 1, mean, na.rm = TRUE),
  pos_cap    = apply(TG_cap[[nm]]$t, 1, function(x) mean(x[is.finite(x)] > 0)),
  mean_t_ew  = apply(TG_ew[[nm]]$t, 1, mean, na.rm = TRUE),
  pos_ew     = apply(TG_ew[[nm]]$t, 1, function(x) mean(x[is.finite(x)] > 0)))))
say("--- era 공통성분: cap-w vs EW-유니버스 (primary) ---"); print(ERA2[grid == "primary"])
say("--- 동 (rob36) ---"); print(ERA2[grid == "rob36"])

# ── D2. 판정이 factor 라벨인가 era 라벨인가 ────────────────────────────────
era_share <- function(TT) {
  em <- sign(apply(TT, 1, mean, na.rm = TRUE))
  vapply(seq_len(nrow(TT)), function(k) {
    x <- TT[k, ]; x <- x[is.finite(x)]; mean(sign(x) == em[k]) }, numeric(1))
}
ES <- data.table(grid = "primary", k = seq_len(nrow(TG_cap$primary$t)),
                 agree_cap = era_share(TG_cap$primary$t), agree_ew = era_share(TG_ew$primary$t))
print(ES)
say("★ 판정부호가 era 부호와 일치하는 비율: cap-w 평균 %.3f / EW 평균 %.3f — 1.0에 가까울수록 '판정 = era 라벨'",
    mean(ES$agree_cap), mean(ES$agree_ew))

# ── D3. time-clustered 추론 (창 전이 단위) ─────────────────────────────────
per_k <- rbindlist(lapply(names(GRIDS), function(nm) {
  P <- PR_cap[[nm]]
  P[, .(n = .N, p = mean(sign(t_k) == sign(t_next))), by = k][, grid := nm][] }))
print(per_k)
time_boot <- function(P, B = 5000L, seed = 20260803L) {
  set.seed(seed); ks <- unique(P$k); idx <- split(seq_len(nrow(P)), P$k)
  bs <- vapply(seq_len(B), function(b) {
    kk <- sample(ks, length(ks), replace = TRUE)
    Q <- P[unlist(idx[as.character(kk)])]
    mean(sign(Q$t_k) == sign(Q$t_next)) }, numeric(1))
  c(est = mean(sign(P$t_k) == sign(P$t_next)),
    lo = unname(quantile(bs,.025)), hi = unname(quantile(bs,.975)), n_k = length(ks))
}
TB <- rbindlist(lapply(names(GRIDS), function(nm) {
  r <- time_boot(PR_cap[[nm]]); data.table(grid = nm, p = r["est"], lo = r["lo"], hi = r["hi"], n_transitions = r["n_k"]) }))
print(TB)
say("★ time-clustered CI (전이 단위): primary [%.3f, %.3f] — 0.5 %s",
    TB[grid=="primary", lo], TB[grid=="primary", hi],
    ifelse(TB[grid=="primary", lo <= .5 & hi >= .5], "포함", "배제"))

# ── D4. 클러스터 재설계 (평균연결 k = PC90) ────────────────────────────────
CM <- suppressWarnings(cor(A, use = "pairwise.complete.obs")); CM[!is.finite(CM)] <- 0
HC2 <- hclust(as.dist(1 - abs(CM)), method = "average")
K2  <- P2R$n_pc90
CL2 <- cutree(HC2, k = K2)
say("평균연결 k=%d 클러스터: 크기 중앙값 %.0f / 최대 %d (단일연결 최대 246 대비)",
    K2, median(table(CL2)), max(table(CL2)))
CL2DT <- data.table(Factor_Name = names(CL2), cluster2 = as.integer(CL2))
boot2 <- function(P, B = 3000L, seed = 20260803L) {
  set.seed(seed); Q <- merge(P, CL2DT, by = "Factor_Name")
  gs <- unique(Q$cluster2); idx <- split(seq_len(nrow(Q)), Q$cluster2)
  bs <- vapply(seq_len(B), function(b) {
    gg <- sample(gs, length(gs), replace = TRUE)
    S <- Q[unlist(idx[as.character(gg)])]
    mean(sign(S$t_k) == sign(S$t_next)) }, numeric(1))
  c(est = mean(sign(Q$t_k) == sign(Q$t_next)),
    lo = unname(quantile(bs,.025)), hi = unname(quantile(bs,.975)), n_units = length(gs))
}
CB2 <- rbindlist(lapply(names(GRIDS), function(nm) {
  r <- boot2(PR_cap[[nm]]); data.table(grid = nm, p = r["est"], lo = r["lo"], hi = r["hi"], n_clusters = r["n_units"]) }))
print(CB2)
# 최상위 bin 재검
tb2 <- { Q <- copy(PR_cap$primary)[abs(t_k) >= 2]; boot2(Q) }
say("★ primary 최상위 bin |t|>=2 (평균연결 클러스터 CI): p=%.3f [%.3f, %.3f]", tb2["est"], tb2["lo"], tb2["hi"])

# ── D5. lag1 스트레스 + AX-001 (대표 12 factor: |전기간 t| 상하위 6+6) ──────
SUMM <- CP$summary
PANEL <- as.data.table(read_parquet(file.path(OUT, "pool_panel.parquet")))
PANEL[, Date := as.Date(Date)]; setkey(PANEL, Factor_Name, Date, Ticker)
S2 <- SUMM[Factor_Name %in% POOL][order(-abs(port_t_full))]
REP <- c(head(S2$Factor_Name, 6L), tail(S2$Factor_Name, 6L))
canon <- function(sc, tag, dual = FALSE) canonical_screen_bt(sc, returns_dt, bench_dt,
  top_n = 25L, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
  run_id = "WT-D20260803_005", strategy_id = paste0("WT_D20260803_005_", tag),
  diag_dual_basis = dual, size_dt = NULL)
lag1_scores <- function(sc) { d <- sort(unique(sc$Date))
  mp <- data.table(Date = d[-1], src = d[-length(d)])
  merge(mp, sc, by.x = "src", by.y = "Date", allow.cartesian = TRUE)[, .(Date, Ticker, score)] }
LAG <- rbindlist(lapply(REP, function(f) {
  sc <- PANEL[.(f), .(Date, Ticker, score), nomatch = 0L]
  b <- SUMM[Factor_Name == f, port_t_full]
  l <- canon(lag1_scores(sc), paste0("LAG1_", f))
  # AX-001 조건부 (advisory)
  pr <- RES[[f]]; bad <- pr$benchmark_ret < 0
  data.table(Factor_Name = f, port_t_base = b, port_t_lag1 = l$portfolio_alpha_t_nw_lag3,
             delta = l$portfolio_alpha_t_nw_lag3 - b,
             ax001_bad_act_pct_m = 100*mean(pr$active[bad]),
             ax001_norm_act_pct_m = 100*mean(pr$active[!bad]), n_bad = sum(bad))
}))
print(LAG)
say("lag1 스트레스: |Δt| 중앙값 %.3f / 최대 %.3f | 부호 유지 %d/%d — 붕괴 시 동월 누출 의심",
    median(abs(LAG$delta)), max(abs(LAG$delta)),
    sum(sign(LAG$port_t_base) == sign(LAG$port_t_lag1)), nrow(LAG))
# lag1을 창 단위로도: 대표 factor의 창별 부호 유지가 base와 같은가
say("AX-001 조건부(advisory): 대표 %d factor 중 bad월 active > normal월 active = %d건",
    nrow(LAG), LAG[ax001_bad_act_pct_m > ax001_norm_act_pct_m, .N])

saveRDS(list(shift = data.table(Date = DATES, cap_minus_ew = shift_v),
             dual = DB, era2 = ERA2, era_share = ES, per_k = per_k, time_boot = TB,
             clust2 = CL2DT, clboot2 = CB2, top_bin2 = tb2, lag1 = LAG,
             A_EW_pool = colnames(A_EW),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "dualbasis_results.rds"))
saveRDS(list(TG_ew = TG_ew, PR_ew = PR_ew), file.path(OUT, "ew_basis_grids.rds"))
say("저장 — dualbasis_results.rds + ew_basis_grids.rds")
