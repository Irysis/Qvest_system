# =============================================================================
# FQ-057 NP4-P1c run_03: walk-forward 예측분산 + 실현분산 (실 book active vector)
#   - P1 run_03 의 elig/Σ/bench/realized 머신러리 정확 재사용 (pinned 입력).
#   - 유일 변경: 포트폴리오 active vector = 실 book FORM 재구성.
#       capw_mom_proxy    : P1 replica (mom_12_1 cap-w top-25)
#       real_book_fullinv : score_eff top-20 LinearTilt(λ=1.5) 완전투자
#       real_book_overlaid: real_book_fullinv × invested(m4×β_R05) + CASH
#   - score_eff: cleanT1 (production_parity_verified). invested: layer5_faith (production).
#   Output: p1c_pairs.parquet / p1c_sigma_diag.parquet / p1c_book_panel.parquet
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

# ---- 사전등록 고정 파라미터 (P1 정합 + 실 book) -----------------------------
BOUNDS <- c(0, 0.20); MAX_NAMES_PROXY <- 25L; N_TARGET_BOOK <- 20L; LAMBDA <- 1.5
LIQ_MIN <- 2e8; WIN <- 60L; MOM_FROM <- 11L; MOM_TO <- 1L
REB_FROM <- 200912L; REB_TO <- 202605L
EWMA_LAMBDA <- 0.94
DAILY_CAP <- 0.6

# ---- production .tilt/.norm (forward_weights_R05_noLayer4.R verbatim port) ----
.norm <- function(w, lb=0, ub=BOUNDS[2], ts=1, mi=50){
  w[is.na(w)]<-0; w[w<lb]<-lb; w[w>ub]<-ub
  for(i in seq_len(mi)){ s<-sum(w); if(abs(s-ts)<1e-8) break; if(s==0) break
    w<-w*(ts/s); w[w>ub]<-ub; w[w<lb]<-lb }
  w }
.tilt <- function(a, lam=LAMBDA, lb=0, ub=BOUNDS[2]){
  if(!length(a)) return(numeric(0))
  z <- (a-mean(a))/pmax(sd(a),1e-10)
  w <- pmax(0, 1/length(a) + lam*z/length(a))
  if(sum(w)>0) w <- w/sum(w)
  .norm(w, lb, ub) }

# ---- 입력 (P1 pinned 재사용) -------------------------------------------------
mr   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
liq  <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_liq_snapshot.parquet")))
dret <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_daily_returns.parquet")))

# ---- 실 book score_eff (production_parity_verified) --------------------------
CP <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet")
sc <- as.data.table(read_parquet(CP, col_select=c("Date","Ticker","score_eff")))
sc[, Date := as.Date(Date)]
sc[, ym := as.integer(format(Date,"%Y"))*100L + as.integer(format(Date,"%m"))]
setkey(sc, ym, Ticker)
cat("[score] cleanT1 rows:", nrow(sc), " ym:", min(sc$ym), "..", max(sc$ym), "\n")

# ---- invested = m4 × beta_R05 (production layer5_faith) ----------------------
L5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
L5[, ry := as.integer(gsub("-","",return_ym))]        # return_ym(=rebalance t) → int ym
L5[, invested := m4 * beta_R05]
inv_by_ym <- setNames(L5$invested, L5$ry)
reg_by_ym <- setNames(L5$regime,  L5$ry)
cat("[invested] layer5 return_ym:", min(L5$ry), "..", max(L5$ry),
    " median invested:", round(median(L5$invested),4), "\n")

# 월간 수익 행렬
Mw <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
yms <- Mw$ym
mat <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
ym_next <- function(y){ yy<-y%/%100L; mm<-y%%100L; if(mm==12L)(yy+1L)*100L+1L else y+1L }
for (i in seq_len(length(yms)-1L)) stopifnot(yms[i+1L]==ym_next(yms[i]))
reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]
cat("[panel] months:", length(yms), " rebalances:", length(reb_months), "\n")

# ---- 일간 → 캘린더 + 월말 트레이딩일 ----------------------------------------
dret <- dret[!is.na(Ret)]
n_cap <- dret[abs(Ret) > DAILY_CAP, .N]
dret[Ret >  DAILY_CAP, Ret :=  DAILY_CAP]; dret[Ret < -DAILY_CAP, Ret := -DAILY_CAP]
cat("[daily] monster-capped cells:", n_cap, "\n")
all_days <- sort(unique(dret$Date))
day_ym   <- as.integer(format(all_days, "%Y"))*100L + as.integer(format(all_days, "%m"))
last_td  <- data.table(Date = all_days, ym = day_ym)[, .(reb_date = max(Date)), by = ym]
setkey(last_td, ym)
dwide <- dcast(dret, Date ~ Ticker, value.var = "Ret")
dwide_dates <- dwide$Date
Dmat <- as.matrix(dwide[, -1, drop = FALSE]); Dmat[is.na(Dmat)] <- 0
rownames(Dmat) <- as.character(dwide_dates)
Dmat <- cbind(Dmat, CASH = 0)                 # CASH col (overlaid 실현용, r=0)
cat("[daily] wide matrix:", nrow(Dmat), "days x", ncol(Dmat), "cols(+CASH)\n")

cap_renorm <- function(w, cap = 0.20, iter = 50L) {
  for (i in seq_len(iter)) {
    over <- w > cap + 1e-12; if (!any(over)) break
    excess <- sum(w[over] - cap); w[over] <- cap
    under <- !over & w > 0; if (!any(under)) break
    w[under] <- w[under] + excess * w[under]/sum(w[under])
  }
  w / sum(w) }

# ---- walk-forward -----------------------------------------------------------
pred_rows <- list(); diag_rows <- list(); held_store <- list()
book_panel <- list(); overlap_rows <- list()
lw_degen <- 0L; t0 <- Sys.time()

for (t_ym in reb_months) {
  idx <- match(t_ym, yms); stopifnot(idx >= WIN)
  w_idx <- (idx - WIN + 1L):idx
  h_ym <- ym_next(t_ym)

  members <- snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= LIQ_MIN, Ticker]
  cand    <- intersect(intersect(members, liq_ok), colnames(mat))
  if (length(cand) < 40L) next
  sub60 <- mat[w_idx, cand, drop = FALSE]
  elig  <- cand[colSums(!is.na(sub60)) == WIN]
  if (length(elig) < 40L) next
  ret60 <- sub60[, elig, drop = FALSE]

  # ===== 포트 1: capw_mom_proxy (P1 replica) =====
  mom_rows <- (idx - MOM_FROM):(idx - MOM_TO)
  mom <- expm1(colSums(log1p(mat[mom_rows, elig, drop = FALSE])))
  zmom <- as.numeric(scale(mom)); names(zmom) <- elig
  top25 <- names(sort(zmom, decreasing = TRUE))[seq_len(min(MAX_NAMES_PROXY, length(elig)))]
  sz  <- snap[ym == t_ym & Ticker %in% top25, .(Ticker, size)]
  szv <- setNames(pmax(sz$size, 0), sz$Ticker)[top25]; szv[is.na(szv)] <- 0
  w_capwmom <- if (sum(szv) > 0) cap_renorm(szv/sum(szv), BOUNDS[2]) else setNames(rep(1/length(top25),length(top25)),top25)
  names(w_capwmom) <- top25

  # ===== 포트 2/3: 실 book (score_eff top-20 LinearTilt) =====
  sc_t <- sc[ym == t_ym]
  s_all <- setNames(sc_t$score_eff, sc_t$Ticker)          # 전 유니버스 score (elig 무관)
  s_elig <- s_all[names(s_all) %in% elig]; s_elig <- s_elig[!is.na(s_elig)]
  book_ok <- length(s_elig) >= N_TARGET_BOOK
  if (book_ok) {
    top20 <- names(sort(s_elig, decreasing = TRUE))[seq_len(N_TARGET_BOOK)]
    w_base <- .tilt(s_elig[top20]); names(w_base) <- top20   # 완전투자 stock 구조
    # elig-vs-prod overlap 진단: prod top20 = (member∩liq) score_eff 상위 20 (complete60 미요구)
    prod_cand <- s_all[names(s_all) %in% intersect(members, liq_ok)]; prod_cand <- prod_cand[!is.na(prod_cand)]
    prod20 <- if (length(prod_cand) >= N_TARGET_BOOK) names(sort(prod_cand, decreasing=TRUE))[seq_len(N_TARGET_BOOK)] else names(prod_cand)
    overlap_rows[[length(overlap_rows)+1L]] <- data.table(
      t_ym=t_ym, n_elig=length(elig), n_score=length(s_all),
      overlap_top20=length(intersect(top20, prod20)))
  } else {
    top20 <- character(0); w_base <- numeric(0)
  }
  invested_t <- if (as.character(t_ym) %in% names(inv_by_ym)) as.numeric(inv_by_ym[[as.character(t_ym)]]) else NA_real_
  if (is.na(invested_t)) invested_t <- 1.0        # 조인 실패 방어(로깅)
  w_overlaid <- if (book_ok) w_base * invested_t else numeric(0)

  # 벤치: cap-w over elig
  szb <- snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
  szbv <- setNames(pmax(szb$size, 0), szb$Ticker)[elig]; szbv[is.na(szbv)] <- 0
  w_bench <- if (sum(szbv) > 0) szbv/sum(szbv) else setNames(rep(1/length(elig), length(elig)), elig)

  # active 벡터 (elig space) — 이차형식용
  mk_active <- function(wv){ a<-setNames(rep(0,length(elig)),elig); a[names(wv)]<-a[names(wv)]+wv; a-w_bench }
  a_capwmom <- mk_active(w_capwmom)
  a_fullinv <- if (book_ok) mk_active(w_base)     else NULL
  a_overlaid<- if (book_ok) mk_active(w_overlaid) else NULL

  # Σ arms
  ccA <- withCallingHandlers(.get_cor_cov(ret60, "ledoit_wolf"),
                             warning = function(w) invokeRestart("muffleWarning"))
  if (!is.null(attr(ccA, "lw_degenerate"))) lw_degen <- lw_degen + 1L
  Sig_list <- list(lw_linear=ccA$cov, lw_nls=est_lw_nls_p1(ret60),
                   ewma_struct=est_ewma_struct_p1(ret60, EWMA_LAMBDA))

  for (arm in names(Sig_list)) {
    Sig <- Sig_list[[arm]]; cp <- cond_psd_p1(Sig)
    diag_rows[[length(diag_rows)+1L]] <- data.table(
      ym=t_ym, holding_ym=h_ym, arm=arm, p=length(elig),
      cond=cp$cond, min_ev=cp$min_ev, psd=as.integer(isTRUE(cp$psd)))
    add <- function(pf, tg, wv) data.table(holding_ym=h_ym, portfolio=pf, target=tg, arm=arm,
                                           pred_var=pred_var_qform(wv, Sig))
    rr <- list(
      add("capw_mom_proxy","total", w_capwmom), add("capw_mom_proxy","te", a_capwmom))
    if (book_ok) rr <- c(rr, list(
      add("real_book_fullinv","total", w_base),      add("real_book_fullinv","te", a_fullinv),
      add("real_book_overlaid","total", w_overlaid), add("real_book_overlaid","te", a_overlaid)))
    pred_rows[[length(pred_rows)+1L]] <- rbindlist(rr)
  }

  held_store[[length(held_store)+1L]] <- list(
    h_ym=h_ym, reb_ym=t_ym, book_ok=book_ok, invested=invested_t,
    w_capwmom=w_capwmom, w_base=w_base, w_overlaid=w_overlaid, w_bench=w_bench)

  if (book_ok) book_panel[[length(book_panel)+1L]] <- data.table(
    t_ym=t_ym, h_ym=h_ym, regime=reg_by_ym[[as.character(t_ym)]], invested=invested_t,
    ticker=top20, w_base=as.numeric(w_base[top20]), w_overlaid=as.numeric(w_overlaid[top20]))

  if (match(t_ym, reb_months) %% 48 == 0)
    cat(sprintf("[wf] %d done (%.1f min)\n", t_ym, as.numeric(difftime(Sys.time(),t0,units="mins"))))
}
PRED <- rbindlist(pred_rows); DIAG <- rbindlist(diag_rows)
BOOK <- rbindlist(book_panel); OVL <- rbindlist(overlap_rows)
cat("[wf] pred rows:", nrow(PRED), " lw_degen months:", lw_degen,
    " book months:", length(unique(BOOK$t_ym)),
    " median top20 overlap(elig vs prod):", median(OVL$overlap_top20), "/20\n")

# =============================================================================
# 실현분산: Return.portfolio → 홀딩월 RV
# =============================================================================
reb_ym_vec <- as.integer(sapply(held_store, function(s) s$reb_ym))
reb_dates  <- last_td[.(reb_ym_vec), reb_date]; stopifnot(!anyNA(reb_dates))
Dx <- xts(Dmat, order.by = as.Date(rownames(Dmat))); DCOLS <- colnames(Dmat)

# getter: 각 held_store 항목의 weight 벡터(부재월은 NULL). rows=held_store, cols=union.
build_wxts <- function(getter, need_flag = NULL) {
  keep <- if (is.null(need_flag)) rep(TRUE, length(held_store)) else sapply(held_store, function(s) isTRUE(s[[need_flag]]))
  idxk <- which(keep)
  uni <- sort(unique(unlist(lapply(idxk, function(i) names(getter(held_store[[i]]))))))
  uni <- intersect(uni, DCOLS)
  M <- matrix(0, nrow=length(idxk), ncol=length(uni), dimnames=list(NULL, uni))
  for (j in seq_along(idxk)) {
    w <- getter(held_store[[idxk[j]]]); nm <- intersect(names(w), uni)
    if (length(nm)) M[j, nm] <- as.numeric(w[nm])
  }
  list(M=M, dates=reb_dates[idxk], cols=uni)
}
# port 실현: weights 합=1 정규화(fullinv·proxy·bench) 또는 CASH 잔여(overlaid)
port_daily <- function(b, add_cash=FALSE) {
  M <- b$M
  if (add_cash) {                      # stock weight 합<1, 잔여를 CASH(r=0)로
    cashw <- pmax(0, 1 - rowSums(M))
    if (!("CASH" %in% colnames(M))) { M <- cbind(M, CASH=0) ; b$cols <- c(b$cols,"CASH") }
    M[,"CASH"] <- M[,"CASH"] + cashw
  } else {
    rs <- rowSums(M); rs[rs<=0] <- 1; M <- M / rs      # 완전투자 재정규화
  }
  cols <- intersect(colnames(M), DCOLS)
  wx <- xts(M[,cols,drop=FALSE], order.by=b$dates)
  pf <- Return.portfolio(Dx[, cols, drop=FALSE], weights=wx, verbose=FALSE)
  data.table(Date=index(pf), r=as.numeric(pf))
}

b_capwmom <- build_wxts(function(s) s$w_capwmom)
b_bench   <- build_wxts(function(s) s$w_bench)
b_full    <- build_wxts(function(s) s$w_base,     need_flag="book_ok")
b_over    <- build_wxts(function(s) s$w_overlaid, need_flag="book_ok")

pd_capwmom <- port_daily(b_capwmom);        setnames(pd_capwmom,"r","r_capwmom")
pd_bench   <- port_daily(b_bench);          setnames(pd_bench,  "r","r_bench")
pd_full    <- port_daily(b_full);           setnames(pd_full,   "r","r_full")
pd_over    <- port_daily(b_over, add_cash=TRUE); setnames(pd_over, "r","r_over")

D <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE),
            list(pd_capwmom, pd_bench, pd_full, pd_over))
for (cc in c("r_capwmom","r_bench","r_full","r_over")) D[is.na(get(cc)), (cc):=0]
D[, ym := as.integer(format(Date,"%Y"))*100L + as.integer(format(Date,"%m"))]
D[, act_capwmom := r_capwmom - r_bench]
D[, act_full    := r_full    - r_bench]
D[, act_over    := r_over    - r_bench]

rv <- D[, .(
  rv_total_capwmom=sum(r_capwmom^2), rv_te_capwmom=sum(act_capwmom^2),
  rv_total_full=sum(r_full^2),       rv_te_full=sum(act_full^2),
  rv_total_over=sum(r_over^2),       rv_te_over=sum(act_over^2),
  n_days=.N), by=ym]
setnames(rv, "ym", "holding_ym")

REAL <- rbindlist(list(
  rv[, .(holding_ym, portfolio="capw_mom_proxy",    target="total", realized_var=rv_total_capwmom)],
  rv[, .(holding_ym, portfolio="capw_mom_proxy",    target="te",    realized_var=rv_te_capwmom)],
  rv[, .(holding_ym, portfolio="real_book_fullinv", target="total", realized_var=rv_total_full)],
  rv[, .(holding_ym, portfolio="real_book_fullinv", target="te",    realized_var=rv_te_full)],
  rv[, .(holding_ym, portfolio="real_book_overlaid",target="total", realized_var=rv_total_over)],
  rv[, .(holding_ym, portfolio="real_book_overlaid",target="te",    realized_var=rv_te_over)]))

PAIRS <- merge(PRED, REAL, by=c("holding_ym","portfolio","target"), all.x=TRUE)
PAIRS <- PAIRS[!is.na(realized_var)]

# ewma_direct: 포트 자기 실현분산 λ-EWMA (PIT: 과거 실현만)
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

write_parquet(PAIRS, file.path(OUT_DIR, "p1c_pairs.parquet"))
write_parquet(DIAG,  file.path(OUT_DIR, "p1c_sigma_diag.parquet"))
write_parquet(BOOK,  file.path(OUT_DIR, "p1c_book_panel.parquet"))
write_parquet(OVL,   file.path(OUT_DIR, "p1c_elig_overlap.parquet"))
meta <- list(pin_tag="fq057_20260718_171024", built_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  n_pairs=nrow(PAIRS), n_holding_months=length(unique(PAIRS$holding_ym)),
  holding_range=range(PAIRS$holding_ym), lw_degenerate_months=lw_degen,
  monster_capped_daily=n_cap, ewma_lambda=EWMA_LAMBDA,
  book_months=length(unique(BOOK$t_ym)),
  median_elig_prod_overlap_top20=median(OVL$overlap_top20),
  invested_median=round(median(BOOK$invested),4),
  realized_rule="Return.portfolio daily -> RV=sum(r_d^2); active=port-bench; overlaid=CASH col r=0",
  bench="cap-w over elig (risk universe)",
  portfolios=c("capw_mom_proxy(P1 replica)","real_book_fullinv","real_book_overlaid"))
write_json(meta, file.path(OUT_DIR, "p1c_run03_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("[done] run_03 —", round(as.numeric(difftime(Sys.time(),t0,units="mins")),1), "min\n")
