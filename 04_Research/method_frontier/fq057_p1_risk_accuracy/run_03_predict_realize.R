# =============================================================================
# FQ-057 NP4-P1 run_03: walk-forward 예측분산 + 실현분산 (predicted vs realized)
#   - 예측: 각 arm Σ(60m 월간, month-end t) 의 이차형식 w'Σw  (total=port / te=active)
#   - 실현: 홀딩월(t+1) 일간 포트/벤치 수익 (Return.portfolio) → RV=Σ_d r_d^2
#   - arm: lw_linear / lw_nls / ewma_struct (structural) + ewma_direct (univariate)
#   - 포트: capw_tilt_top25(PRIMARY, book-form proxy) / ew_top25(CONTROL)  ← Σ-무관 비중
#   Output: p1_pairs.parquet (holding_ym x portfolio x target x arm x pred/realized)
#           p1_sigma_diag.parquet (arm x ym cond/psd/min_ev)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_p1_risk_accuracy/p1_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

# ---- 사전등록 고정 파라미터 (NP4 정합) -------------------------------------
BOUNDS <- c(0, 0.20); MAX_NAMES <- 25L
LIQ_MIN <- 2e8; WIN <- 60L; MOM_FROM <- 11L; MOM_TO <- 1L
REB_FROM <- 200912L; REB_TO <- 202605L
EWMA_LAMBDA <- 0.94
DAILY_CAP <- 0.6   # 물리불가 monster 방어(±60%>KR 일일한도 30%) — 전 arm/포트/벤치 동일

# ---- 입력 --------------------------------------------------------------------
mr   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
liq  <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_liq_snapshot.parquet")))
dret <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_daily_returns.parquet")))

# 월간 수익 행렬 (rows=ym asc, cols=Ticker)
Mw <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
yms <- Mw$ym
mat <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
ym_next <- function(y){ yy<-y%/%100L; mm<-y%%100L; if(mm==12L)(yy+1L)*100L+1L else y+1L }
for (i in seq_len(length(yms)-1L)) stopifnot(yms[i+1L]==ym_next(yms[i]))
reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]
cat("[panel] months:", length(yms), " rebalances:", length(reb_months), "\n")

# ---- 일간 → 트레이딩캘린더 + 월말 트레이딩일 --------------------------------
dret <- dret[!is.na(Ret)]
n_cap <- dret[abs(Ret) > DAILY_CAP, .N]
dret[Ret >  DAILY_CAP, Ret :=  DAILY_CAP]
dret[Ret < -DAILY_CAP, Ret := -DAILY_CAP]
cat("[daily] monster-capped cells (|Ret|>", DAILY_CAP, "):", n_cap, "\n")
all_days <- sort(unique(dret$Date))
day_ym   <- as.integer(format(all_days, "%Y"))*100L + as.integer(format(all_days, "%m"))
# 각 ym 의 마지막 트레이딩일 (리밸 weight date)
last_td <- data.table(Date = all_days, ym = day_ym)[, .(reb_date = max(Date)), by = ym]
setkey(last_td, ym)

# 일간 wide 행렬 (dates x ticker, NA->0)
dwide <- dcast(dret, Date ~ Ticker, value.var = "Ret")
dwide_dates <- dwide$Date
Dmat <- as.matrix(dwide[, -1, drop = FALSE]); Dmat[is.na(Dmat)] <- 0
rownames(Dmat) <- as.character(dwide_dates)
cat("[daily] wide matrix:", nrow(Dmat), "days x", ncol(Dmat), "tickers\n")

# ---- helper: cap 0.20 반복 renorm -------------------------------------------
cap_renorm <- function(w, cap = 0.20, iter = 50L) {
  for (i in seq_len(iter)) {
    over <- w > cap + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - cap); w[over] <- cap
    under <- !over & w > 0
    if (!any(under)) break
    w[under] <- w[under] + excess * w[under]/sum(w[under])
  }
  w / sum(w)
}

# ---- walk-forward: 비중 + 예측분산 ------------------------------------------
pred_rows <- list(); diag_rows <- list()
held_store <- list()   # 홀딩월별 held/weights/bench (실현용)
lw_degen <- 0L; t0 <- Sys.time()

for (t_ym in reb_months) {
  idx <- match(t_ym, yms); stopifnot(idx >= WIN)
  w_idx <- (idx - WIN + 1L):idx
  h_ym <- ym_next(t_ym)                      # 홀딩월

  members <- snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= LIQ_MIN, Ticker]
  cand    <- intersect(intersect(members, liq_ok), colnames(mat))
  if (length(cand) < 40L) next
  sub60 <- mat[w_idx, cand, drop = FALSE]
  elig  <- cand[colSums(!is.na(sub60)) == WIN]
  if (length(elig) < 40L) next
  ret60 <- sub60[, elig, drop = FALSE]

  # 알파: mom_12_1 z
  mom_rows <- (idx - MOM_FROM):(idx - MOM_TO)
  mom <- expm1(colSums(log1p(mat[mom_rows, elig, drop = FALSE])))
  z <- as.numeric(scale(mom)); names(z) <- elig
  top25 <- names(sort(z, decreasing = TRUE))[seq_len(min(MAX_NAMES, length(elig)))]

  # 포트 비중 (Σ-무관)
  w_ew   <- setNames(rep(1/length(top25), length(top25)), top25)
  sz     <- snap[ym == t_ym & Ticker %in% top25, .(Ticker, size)]
  szv    <- setNames(pmax(sz$size, 0), sz$Ticker)[top25]
  szv[is.na(szv)] <- 0
  w_capw <- if (sum(szv) > 0) cap_renorm(szv/sum(szv), BOUNDS[2]) else w_ew
  names(w_capw) <- top25

  # 벤치: cap-w over elig (risk universe 정합)
  szb <- snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
  szbv <- setNames(pmax(szb$size, 0), szb$Ticker)[elig]; szbv[is.na(szbv)] <- 0
  w_bench <- if (sum(szbv) > 0) szbv/sum(szbv) else setNames(rep(1/length(elig), length(elig)), elig)

  # active 벡터 (elig space)
  a_ew <- setNames(rep(0, length(elig)), elig); a_ew[names(w_ew)] <- a_ew[names(w_ew)] + w_ew
  a_ew <- a_ew - w_bench
  a_capw <- setNames(rep(0, length(elig)), elig); a_capw[names(w_capw)] <- a_capw[names(w_capw)] + w_capw
  a_capw <- a_capw - w_bench

  # Σ arms (elig x elig)
  Sig_list <- list(
    lw_linear   = est_lw_linear_p1(ret60),
    lw_nls      = est_lw_nls_p1(ret60),
    ewma_struct = est_ewma_struct_p1(ret60, EWMA_LAMBDA))
  # lw degeneracy 진단(재산출 attr)
  degA <- attr(.get_cor_cov(ret60, "ledoit_wolf"), "lw_degenerate")
  if (!is.null(degA)) lw_degen <- lw_degen + 1L

  for (arm in names(Sig_list)) {
    Sig <- Sig_list[[arm]]
    cp <- cond_psd_p1(Sig)
    diag_rows[[length(diag_rows)+1L]] <- data.table(
      ym = t_ym, holding_ym = h_ym, arm = arm, p = length(elig),
      cond = cp$cond, min_ev = cp$min_ev, psd = as.integer(isTRUE(cp$psd)))
    # 예측: total(port) / te(active), 두 포트
    pv_total_ew   <- pred_var_qform(w_ew,   Sig)
    pv_total_capw <- pred_var_qform(w_capw, Sig)
    pv_te_ew      <- pred_var_qform(a_ew,   Sig)
    pv_te_capw    <- pred_var_qform(a_capw, Sig)
    pred_rows[[length(pred_rows)+1L]] <- rbindlist(list(
      data.table(holding_ym=h_ym, portfolio="ew_top25",   target="total", arm=arm, pred_var=pv_total_ew),
      data.table(holding_ym=h_ym, portfolio="capw_tilt_top25", target="total", arm=arm, pred_var=pv_total_capw),
      data.table(holding_ym=h_ym, portfolio="ew_top25",   target="te",    arm=arm, pred_var=pv_te_ew),
      data.table(holding_ym=h_ym, portfolio="capw_tilt_top25", target="te",    arm=arm, pred_var=pv_te_capw)))
  }

  # 실현용 저장 (홀딩월 h_ym)
  held_store[[length(held_store)+1L]] <- list(
    h_ym = h_ym, reb_ym = t_ym,
    w_ew = w_ew, w_capw = w_capw, w_bench = w_bench)

  if (match(t_ym, reb_months) %% 48 == 0)
    cat(sprintf("[wf] %d done (%.1f min)\n", t_ym, as.numeric(difftime(Sys.time(),t0,units="mins"))))
}
PRED <- rbindlist(pred_rows); DIAG <- rbindlist(diag_rows)
cat("[wf] pred rows:", nrow(PRED), " lw_degenerate months:", lw_degen, "\n")

# =============================================================================
# 실현분산: Return.portfolio 로 일간 포트/벤치 수익 구성 → 홀딩월 RV
# =============================================================================
reb_ym_vec <- as.integer(sapply(held_store, function(s) s$reb_ym))
reb_dates  <- last_td[.(reb_ym_vec), reb_date]     # keyed join, i-order 보존
stopifnot(!anyNA(reb_dates))
Dx <- xts(Dmat, order.by = as.Date(rownames(Dmat)))
DCOLS <- colnames(Dmat)
# 각 포트/벤치 weights xts (union columns ∩ 일간패널 존재 종목)
build_wxts <- function(getter) {
  uni <- sort(unique(unlist(lapply(held_store, function(s) names(getter(s))))))
  uni <- intersect(uni, DCOLS)
  M <- matrix(0, nrow=length(held_store), ncol=length(uni), dimnames=list(NULL, uni))
  for (i in seq_along(held_store)) {
    w <- getter(held_store[[i]]); nm <- intersect(names(w), uni)
    M[i, nm] <- as.numeric(w[nm])
  }
  M <- M / rowSums(M)                              # 일간 부재 종목 제외 후 재정규화
  list(wx = xts(M, order.by = reb_dates), cols = uni)
}
b_ew <- build_wxts(function(s) s$w_ew)
b_capw <- build_wxts(function(s) s$w_capw)
b_bench <- build_wxts(function(s) s$w_bench)

# Return.portfolio: weights 날짜(월말 t) 이후(홀딩월 t+1) 일간수익에 적용
port_daily <- function(b) {
  pf <- Return.portfolio(Dx[, b$cols, drop=FALSE], weights = b$wx, verbose = FALSE)
  data.table(Date = index(pf), r = as.numeric(pf))
}
pd_ew    <- port_daily(b_ew)
pd_capw  <- port_daily(b_capw)
pd_bench <- port_daily(b_bench)
setnames(pd_ew,   "r", "r_ew");   setnames(pd_capw, "r", "r_capw"); setnames(pd_bench,"r","r_bench")
D <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE), list(pd_ew, pd_capw, pd_bench))
D[, ym := as.integer(format(Date,"%Y"))*100L + as.integer(format(Date,"%m"))]
D[is.na(r_ew), r_ew:=0]; D[is.na(r_capw), r_capw:=0]; D[is.na(r_bench), r_bench:=0]
D[, act_ew := r_ew - r_bench][, act_capw := r_capw - r_bench]

# 홀딩월 RV = Σ_d r_d^2 (월간분산 스케일)
rv <- D[, .(
  rv_total_ew   = sum(r_ew^2),   rv_total_capw = sum(r_capw^2),
  rv_te_ew      = sum(act_ew^2), rv_te_capw    = sum(act_capw^2),
  n_days = .N), by = ym]
setnames(rv, "ym", "holding_ym")

# long 형태 realized
REAL <- rbindlist(list(
  rv[, .(holding_ym, portfolio="ew_top25",        target="total", realized_var=rv_total_ew)],
  rv[, .(holding_ym, portfolio="capw_tilt_top25", target="total", realized_var=rv_total_capw)],
  rv[, .(holding_ym, portfolio="ew_top25",        target="te",    realized_var=rv_te_ew)],
  rv[, .(holding_ym, portfolio="capw_tilt_top25", target="te",    realized_var=rv_te_capw)]))

# ---- pairs 병합 (structural arms) -------------------------------------------
PAIRS <- merge(PRED, REAL, by=c("holding_ym","portfolio","target"), all.x=TRUE)
PAIRS <- PAIRS[!is.na(realized_var)]

# ---- ewma_direct: 포트 자기 실현분산의 λ-EWMA (PIT: 과거 실현만) --------------
ed_rows <- list()
for (pf in unique(REAL$portfolio)) for (tg in unique(REAL$target)) {
  sub <- REAL[portfolio==pf & target==tg][order(holding_ym)]
  state <- NA_real_; preds <- rep(NA_real_, nrow(sub)); nprior <- rep(0L, nrow(sub))
  for (i in seq_len(nrow(sub))) {
    preds[i] <- state; nprior[i] <- if (is.na(state)) 0L else i-1L
    rv_i <- sub$realized_var[i]
    state <- if (is.na(state)) rv_i else EWMA_LAMBDA*state + (1-EWMA_LAMBDA)*rv_i
  }
  ed_rows[[length(ed_rows)+1L]] <- data.table(
    holding_ym=sub$holding_ym, portfolio=pf, target=tg, arm="ewma_direct",
    pred_var=preds, realized_var=sub$realized_var, n_prior=nprior)
}
ED <- rbindlist(ed_rows)[!is.na(pred_var) & n_prior >= 12L]
PAIRS[, n_prior := NA_integer_]
PAIRS <- rbindlist(list(PAIRS, ED), use.names=TRUE)

write_parquet(PAIRS, file.path(OUT_DIR, "p1_pairs.parquet"))
write_parquet(DIAG,  file.path(OUT_DIR, "p1_sigma_diag.parquet"))
meta <- list(pin_tag="fq057_20260718_171024", built_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
             n_pairs=nrow(PAIRS), n_holding_months=length(unique(PAIRS$holding_ym)),
             holding_range=range(PAIRS$holding_ym), lw_degenerate_months=lw_degen,
             monster_capped_daily=n_cap, ewma_lambda=EWMA_LAMBDA,
             realized_rule="Return.portfolio daily -> RV=sum(r_d^2) per holding month; active=port-bench",
             bench="cap-w over elig (risk universe, size-prop)")
write_json(meta, file.path(OUT_DIR, "p1_run03_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("[done] run_03 —", round(as.numeric(difftime(Sys.time(),t0,units="mins")),1), "min\n")
