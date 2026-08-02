# =============================================================================
# FQ-108 run_03: walk-forward 예측분산 vs 실현분산
#   estimator {lw_nls(PRIMARY), lw_linear(대조)} × 대각처치 {A_base, A2_recal,
#     B_d35, C_d45, D_max, F_sv63, G_full, X_oracle(위반주입)}
#   포트 {real_book_overlaid(PRIMARY, production parity), ew_top25(CONTROL)}
#   타깃 {total, te}
#   상관구조 C 는 처치 불변 — 처치는 대각(개별 분산 예측)에만 작용.
#   Output: fq108_pairs.parquet / fq108_sigma_diag.parquet / fq108_coef_panel.parquet
#           fq108_stock_pred.parquet (전이시험용 종목-월 예측/실현)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq108_tailvol_risk_axis/fq108_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

# ---- 사전등록 고정 파라미터 (P1/P1c 정합) ------------------------------------
BOUNDS <- c(0, 0.20); MAX_NAMES_EW <- 25L; N_TARGET_BOOK <- 20L; LAMBDA <- 1.5
LIQ_MIN <- 2e8; WIN <- 60L; MOM_FROM <- 11L; MOM_TO <- 1L
REB_FROM <- 200912L; REB_TO <- 202605L
DAILY_CAP <- 0.6
MIN_TRAIN_MONTHS <- 24L

TREATMENTS <- list(
  A2_recal = c("x"),
  B_d35    = c("x", "g35"),
  C_d45    = c("x", "g45"),
  D_max    = c("x", "g05"),
  F_sv63   = c("x", "s63"),
  G_full   = c("x", "s63", "g35"),
  X_oracle = c("x", "mlev_future")     # ★위반 주입 — 미래 월 평균 log-RV
)

# ---- production .tilt/.norm (forward_weights_R05_noLayer4.R verbatim port) ----
.norm <- function(w, lb = 0, ub = BOUNDS[2], ts = 1, mi = 50) {
  w[is.na(w)] <- 0; w[w < lb] <- lb; w[w > ub] <- ub
  for (i in seq_len(mi)) { s <- sum(w); if (abs(s - ts) < 1e-8) break; if (s == 0) break
    w <- w * (ts / s); w[w > ub] <- ub; w[w < lb] <- lb }
  w }
.tilt <- function(a, lam = LAMBDA, lb = 0, ub = BOUNDS[2]) {
  if (!length(a)) return(numeric(0))
  z <- (a - mean(a)) / pmax(sd(a), 1e-10)
  w <- pmax(0, 1 / length(a) + lam * z / length(a))
  if (sum(w) > 0) w <- w / sum(w)
  .norm(w, lb, ub) }

# ---- 입력 (pinned) -----------------------------------------------------------
mr    <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
liq   <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_liq_snapshot.parquet")))
dret  <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_daily_returns.parquet")))
FPAN  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_factor_panel.parquet")))
SRV   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_stock_rv.parquet")))
setkey(FPAN, t_ym, Ticker); setkey(SRV, holding_ym, Ticker)

# 종목-월 log RV + 월 평균 (mlev)
SRV[, logrv := log(rv)]
MLEV <- SRV[, .(mlev = mean(logrv, na.rm = TRUE)), by = holding_ym]
setkey(MLEV, holding_ym)

# ---- 실 book score_eff (production_parity_verified) --------------------------
CP <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet")
sc <- as.data.table(read_parquet(CP, col_select = c("Date", "Ticker", "score_eff")))
sc[, Date := as.Date(Date)]
sc[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]
setkey(sc, ym, Ticker)
cat("[score] cleanT1 rows:", nrow(sc), " ym:", min(sc$ym), "..", max(sc$ym), "\n")

L5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
L5[, ry := as.integer(gsub("-", "", return_ym))]
L5[, invested := m4 * beta_R05]
inv_by_ym <- setNames(L5$invested, L5$ry)
reg_by_ym <- setNames(L5$regime, L5$ry)
cat("[invested] layer5 ym:", min(L5$ry), "..", max(L5$ry),
    " median:", round(median(L5$invested), 4), "\n")

# ---- 월간 행렬 ---------------------------------------------------------------
Mw <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
yms <- Mw$ym
mat <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
ym_next <- function(y) { yy <- y %/% 100L; mm <- y %% 100L; if (mm == 12L) (yy + 1L) * 100L + 1L else y + 1L }
for (i in seq_len(length(yms) - 1L)) stopifnot(yms[i + 1L] == ym_next(yms[i]))
reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]
cat("[panel] months:", length(yms), " rebalances:", length(reb_months), "\n")

# ---- 일간 ------------------------------------------------------------------
dret <- dret[!is.na(Ret)]
n_cap <- dret[abs(Ret) > DAILY_CAP, .N]
dret[Ret >  DAILY_CAP, Ret :=  DAILY_CAP]; dret[Ret < -DAILY_CAP, Ret := -DAILY_CAP]
all_days <- sort(unique(dret$Date))
day_ym <- as.integer(format(all_days, "%Y")) * 100L + as.integer(format(all_days, "%m"))
last_td <- data.table(Date = all_days, ym = day_ym)[, .(reb_date = max(Date)), by = ym]
setkey(last_td, ym)
dwide <- dcast(dret, Date ~ Ticker, value.var = "Ret")
dwide_dates <- dwide$Date
Dmat <- as.matrix(dwide[, -1, drop = FALSE]); Dmat[is.na(Dmat)] <- 0
rownames(Dmat) <- as.character(dwide_dates)
Dmat <- cbind(Dmat, CASH = 0)
cat("[daily] wide:", nrow(Dmat), "days x", ncol(Dmat), "cols(+CASH)\n")

# =============================================================================
# walk-forward
# =============================================================================
ESTS <- c("lw_nls", "lw_linear")
pool <- list(lw_nls = list(), lw_linear = list())      # 확장창 훈련 누적
pred_rows <- list(); diag_rows <- list(); coef_rows <- list()
held_store <- list(); cov_rows <- list(); stock_pred_rows <- list()
lw_degen <- 0L; t0 <- Sys.time(); guard_hits <- 0L

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

  # ===== 포트 비중 (Σ·처치 무관) =====
  mom_rows <- (idx - MOM_FROM):(idx - MOM_TO)
  mom <- expm1(colSums(log1p(mat[mom_rows, elig, drop = FALSE])))
  zmom <- as.numeric(scale(mom)); names(zmom) <- elig
  top25 <- names(sort(zmom, decreasing = TRUE))[seq_len(min(MAX_NAMES_EW, length(elig)))]
  w_ew <- setNames(rep(1 / length(top25), length(top25)), top25)

  sc_t <- sc[ym == t_ym]
  s_all <- setNames(sc_t$score_eff, sc_t$Ticker)
  s_elig <- s_all[names(s_all) %in% elig]; s_elig <- s_elig[!is.na(s_elig)]
  book_ok <- length(s_elig) >= N_TARGET_BOOK
  if (book_ok) {
    top20 <- names(sort(s_elig, decreasing = TRUE))[seq_len(N_TARGET_BOOK)]
    w_base <- .tilt(s_elig[top20]); names(w_base) <- top20
  } else { top20 <- character(0); w_base <- numeric(0) }
  invested_t <- if (as.character(t_ym) %in% names(inv_by_ym)) as.numeric(inv_by_ym[[as.character(t_ym)]]) else 1.0
  if (is.na(invested_t)) invested_t <- 1.0
  w_over <- if (book_ok) w_base * invested_t else numeric(0)

  szb <- snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
  szbv <- setNames(pmax(szb$size, 0), szb$Ticker)[elig]; szbv[is.na(szbv)] <- 0
  w_bench <- if (sum(szbv) > 0) szbv / sum(szbv) else setNames(rep(1 / length(elig), length(elig)), elig)
  mk_active <- function(wv) { a <- setNames(rep(0, length(elig)), elig); a[names(wv)] <- a[names(wv)] + wv; a - w_bench }
  a_ew   <- mk_active(w_ew)
  a_over <- if (book_ok) mk_active(w_over) else NULL

  # ===== 회귀 재료 (elig 순서) =====
  # ★ data.table 함정: i 의 .() 는 DT 자기 컬럼을 먼저 본다. FPAN 에 t_ym 컬럼이
  #   있으므로 .(t_ym, elig) 는 스칼라가 아니라 439k 컬럼으로 해석돼 elig 가
  #   recycle 된다(무경고 아님 — warning 만 나고 조용히 439k행 반환).
  #   → 컬럼명과 겹치지 않는 지역변수로 키를 넘기고, 행수를 hard assert.
  tkey <- t_ym; hkey <- h_ym
  fp <- FPAN[.(tkey, elig), .(Ticker, g_d35, g_d45, g_d05, rv63_m)]
  stopifnot(nrow(fp) == length(elig), identical(fp$Ticker, elig))
  cov_g35 <- mean(is.finite(fp$g_d35)); cov_s63 <- mean(is.finite(fp$rv63_m) & fp$rv63_m > 0)
  s63raw <- log(pmax(fp$rv63_m, .Machine$double.eps))
  s63raw[!is.finite(s63raw)] <- NA_real_
  med_s63 <- median(s63raw, na.rm = TRUE)
  s63 <- ifelse(is.finite(s63raw), s63raw, med_s63)
  g35 <- cs_z(fp$g_d35); g45 <- cs_z(fp$g_d45); g05 <- cs_z(fp$g_d05)

  # target y = log RV_{i, h_ym}
  yv <- SRV[.(hkey, elig), logrv]
  mlev_fut <- MLEV[.(hkey), mlev]
  if (length(mlev_fut) != 1L || !is.finite(mlev_fut)) mlev_fut <- NA_real_
  mlev_cur_for_train <- mlev_fut          # 훈련행에 붙는 '그 행의 홀딩월 평균'(과거엔 기지)

  cov_rows[[length(cov_rows) + 1L]] <- data.table(
    t_ym = t_ym, n_elig = length(elig), cov_g35 = cov_g35, cov_s63 = cov_s63,
    cov_y = mean(is.finite(yv)), book_ok = as.integer(book_ok), invested = invested_t)

  # ===== Σ arms =====
  ccA <- withCallingHandlers(.get_cor_cov(ret60, "ledoit_wolf"),
                             warning = function(w) invokeRestart("muffleWarning"))
  if (!is.null(attr(ccA, "lw_degenerate"))) lw_degen <- lw_degen + 1L
  Sig_list <- list(lw_nls = est_lw_nls_p1(ret60), lw_linear = ccA$cov)

  for (est in ESTS) {
    Sig <- Sig_list[[est]]
    stopifnot(identical(colnames(Sig), elig))
    cp <- cond_psd_p1(Sig)
    cc <- cor_from_cov_108(Sig)
    Cm <- cc$C; sd0 <- cc$sd
    diag_rows[[length(diag_rows) + 1L]] <- data.table(
      t_ym = t_ym, holding_ym = h_ym, est = est, p = length(elig),
      cond = cp$cond, min_ev = cp$min_ev, psd = as.integer(isTRUE(cp$psd)),
      sd_cs_sd = sd(log(sd0)))

    xv <- log(pmax(sd0^2, .Machine$double.eps))

    # ---- 훈련 pool (PIT: 홀딩월 <= t_ym) ----
    P <- pool[[est]]
    trn <- if (length(P)) rbindlist(P) else NULL
    n_train_months <- if (is.null(trn)) 0L else uniqueN(trn$holding_ym)
    if (!is.null(trn)) {
      # ★PIT 가드 3 (fail-closed): 훈련 홀딩월은 결정시점 t_ym 이하만
      if (max(trn$holding_ym) > t_ym)
        stop(sprintf("[PIT-GUARD] train max holding_ym(%d) > decision ym(%d)",
                     max(trn$holding_ym), t_ym))
      guard_hits <- guard_hits + 1L
    }

    newd <- data.table(x = xv, g35 = g35, g45 = g45, g05 = g05, s63 = s63,
                       mlev_future = rep(mlev_fut, length(elig)))

    # ---- A_base (처치 없음) ----
    v_list <- list(A_base = sd0^2)

    # ---- H_hybrid (사후 추가, 탐색용 — 사전등록 판정규칙 대상 아님) -----------
    #  파라미터 없는 교과서 하이브리드: 상관=장기창(불변), 분산=장기·단기 기하평균.
    #  A2 계열의 pooled-회귀 핸디캡(레벨 추적 상실) 없이 '단기 꼬리-vol 배선'의
    #  운영형(operational form)을 그대로 잰다.
    v_hyb <- exp(0.5 * xv + 0.5 * s63)
    v_list[["H_hybrid"]] <- v_hyb

    # ---- X_perfect (★위반 주입 2 — 결정적 canary) -----------------------------
    #  v̂_i = 홀딩월 t+1 의 실현 종목분산 그 자체(완전 미래참조).
    #  이것조차 유의하게 개선을 못 내면 = 측정계 사망(검정력 부재). 판정 대상 아님.
    rvi <- SRV[.(hkey, elig), rv]
    if (mean(is.finite(rvi)) > 0.8) {
      rvi[!is.finite(rvi)] <- median(rvi[is.finite(rvi)])
      v_list[["X_perfect"]] <- rvi
    }

    if (n_train_months >= MIN_TRAIN_MONTHS) {
      for (tr in names(TREATMENTS)) {
        vars <- TREATMENTS[[tr]]
        fpr <- fit_predict_logvar(trn, newd, vars)
        if (is.null(fpr)) next
        v_list[[tr]] <- fpr$v
        coef_rows[[length(coef_rows) + 1L]] <- data.table(
          t_ym = t_ym, est = est, treatment = tr,
          term = names(fpr$coef), coef = as.numeric(fpr$coef),
          n_train = fpr$n_train, s2 = fpr$s2, rank_ok = as.integer(fpr$rank_ok))
      }
    }

    for (arm in names(v_list)) {
      vnew <- v_list[[arm]]
      if (any(!is.finite(vnew))) vnew[!is.finite(vnew)] <- median(vnew[is.finite(vnew)])
      sdn <- sqrt(pmax(vnew, .Machine$double.eps))
      add <- function(pf, tg, wv) data.table(
        holding_ym = h_ym, portfolio = pf, target = tg, est = est, arm = arm,
        pred_var = pred_var_scaled(wv, Cm, sdn))
      rr <- list(add("ew_top25", "total", w_ew), add("ew_top25", "te", a_ew))
      if (book_ok) rr <- c(rr, list(add("real_book_overlaid", "total", w_over),
                                    add("real_book_overlaid", "te", a_over)))
      pred_rows[[length(pred_rows) + 1L]] <- rbindlist(rr)
      # 종목-레벨 예측 저장 (전이시험 — lw_nls 만)
      if (est == "lw_nls" && arm %in% c("A_base", "A2_recal", "B_d35")) {
        stock_pred_rows[[length(stock_pred_rows) + 1L]] <- data.table(
          t_ym = t_ym, holding_ym = h_ym, arm = arm, Ticker = elig,
          pred_var = vnew, realized_var = SRV[.(hkey, elig), rv],
          ret_m = SRV[.(hkey, elig), ret_m], g35 = g35, xv = xv, s63 = s63)
      }
    }

    # ---- pool 갱신 (이번 달 행 append — y 는 홀딩월 h_ym 에 실현) ----
    newrow <- data.table(holding_ym = h_ym, y = yv, x = xv, g35 = g35, g45 = g45,
                         g05 = g05, s63 = s63, mlev_future = rep(mlev_fut, length(elig)))
    newrow <- newrow[is.finite(y)]
    pool[[est]][[length(pool[[est]]) + 1L]] <- newrow
  }

  held_store[[length(held_store) + 1L]] <- list(
    h_ym = h_ym, reb_ym = t_ym, book_ok = book_ok, invested = invested_t,
    w_ew = w_ew, w_over = w_over, w_bench = w_bench)

  if (match(t_ym, reb_months) %% 36 == 0)
    cat(sprintf("[wf] %d done (%.1f min) elig=%d\n", t_ym,
                as.numeric(difftime(Sys.time(), t0, units = "mins")), length(elig)))
}
PRED <- rbindlist(pred_rows); DIAG <- rbindlist(diag_rows)
COEF <- rbindlist(coef_rows); COVG <- rbindlist(cov_rows)
SPRED <- rbindlist(stock_pred_rows)
cat("[wf] pred rows:", nrow(PRED), " lw_degen months:", lw_degen,
    " guard checks:", guard_hits, "\n")
cat("[coverage] median cov_g35:", round(median(COVG$cov_g35), 4),
    " cov_s63:", round(median(COVG$cov_s63), 4),
    " cov_y:", round(median(COVG$cov_y), 4), "\n")

# =============================================================================
# 실현분산 (Return.portfolio → 홀딩월 RV)
# =============================================================================
reb_ym_vec <- as.integer(sapply(held_store, function(s) s$reb_ym))
reb_dates <- last_td[.(reb_ym_vec), reb_date]; stopifnot(!anyNA(reb_dates))
Dx <- xts(Dmat, order.by = as.Date(rownames(Dmat))); DCOLS <- colnames(Dmat)

build_wxts <- function(getter, need_flag = NULL) {
  keep <- if (is.null(need_flag)) rep(TRUE, length(held_store)) else sapply(held_store, function(s) isTRUE(s[[need_flag]]))
  idxk <- which(keep)
  uni <- sort(unique(unlist(lapply(idxk, function(i) names(getter(held_store[[i]]))))))
  uni <- intersect(uni, DCOLS)
  M <- matrix(0, nrow = length(idxk), ncol = length(uni), dimnames = list(NULL, uni))
  for (j in seq_along(idxk)) {
    w <- getter(held_store[[idxk[j]]]); nm <- intersect(names(w), uni)
    if (length(nm)) M[j, nm] <- as.numeric(w[nm])
  }
  list(M = M, dates = reb_dates[idxk], cols = uni)
}
port_daily <- function(b, add_cash = FALSE) {
  M <- b$M
  if (add_cash) {
    cashw <- pmax(0, 1 - rowSums(M))
    if (!("CASH" %in% colnames(M))) M <- cbind(M, CASH = 0)
    M[, "CASH"] <- M[, "CASH"] + cashw
  } else {
    rs <- rowSums(M); rs[rs <= 0] <- 1; M <- M / rs
  }
  cols <- intersect(colnames(M), DCOLS)
  wx <- xts(M[, cols, drop = FALSE], order.by = b$dates)
  pf <- Return.portfolio(Dx[, cols, drop = FALSE], weights = wx, verbose = FALSE)
  data.table(Date = index(pf), r = as.numeric(pf))
}
b_ew <- build_wxts(function(s) s$w_ew)
b_bench <- build_wxts(function(s) s$w_bench)
b_over <- build_wxts(function(s) s$w_over, need_flag = "book_ok")
pd_ew <- port_daily(b_ew); setnames(pd_ew, "r", "r_ew")
pd_bench <- port_daily(b_bench); setnames(pd_bench, "r", "r_bench")
pd_over <- port_daily(b_over, add_cash = TRUE); setnames(pd_over, "r", "r_over")
D <- Reduce(function(a, b) merge(a, b, by = "Date", all = TRUE), list(pd_ew, pd_bench, pd_over))
for (cc in c("r_ew", "r_bench", "r_over")) D[is.na(get(cc)), (cc) := 0]
D[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]
D[, act_ew := r_ew - r_bench][, act_over := r_over - r_bench]
rv <- D[, .(rv_total_ew = sum(r_ew^2), rv_te_ew = sum(act_ew^2),
            rv_total_over = sum(r_over^2), rv_te_over = sum(act_over^2),
            n_days = .N), by = ym]
setnames(rv, "ym", "holding_ym")
REAL <- rbindlist(list(
  rv[, .(holding_ym, portfolio = "ew_top25", target = "total", realized_var = rv_total_ew)],
  rv[, .(holding_ym, portfolio = "ew_top25", target = "te", realized_var = rv_te_ew)],
  rv[, .(holding_ym, portfolio = "real_book_overlaid", target = "total", realized_var = rv_total_over)],
  rv[, .(holding_ym, portfolio = "real_book_overlaid", target = "te", realized_var = rv_te_over)]))

PAIRS <- merge(PRED, REAL, by = c("holding_ym", "portfolio", "target"), all.x = TRUE)
PAIRS <- PAIRS[!is.na(realized_var) & is.finite(pred_var)]

write_parquet(PAIRS, file.path(OUT_DIR, "fq108_pairs.parquet"))
write_parquet(DIAG,  file.path(OUT_DIR, "fq108_sigma_diag.parquet"))
write_parquet(COEF,  file.path(OUT_DIR, "fq108_coef_panel.parquet"))
write_parquet(COVG,  file.path(OUT_DIR, "fq108_coverage.parquet"))
write_parquet(SPRED, file.path(OUT_DIR, "fq108_stock_pred.parquet"))

meta <- list(
  pin_tag = "fq057_20260718_171024", built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_pairs = nrow(PAIRS), n_holding_months = uniqueN(PAIRS$holding_ym),
  holding_range = range(PAIRS$holding_ym), lw_degenerate_months = lw_degen,
  estimators = ESTS, treatments = c("A_base", names(TREATMENTS)),
  min_train_months = MIN_TRAIN_MONTHS,
  pit_guards = c("factor asof (run_02, 198/198 PASS)",
                 sprintf("train max holding_ym <= decision ym (%d checks)", guard_hits)),
  coverage_median = list(g35 = median(COVG$cov_g35), s63 = median(COVG$cov_s63), y = median(COVG$cov_y)),
  realized_rule = "Return.portfolio daily -> RV=sum(r_d^2); active=port-bench; overlaid=CASH col r=0",
  bench = "cap-w over elig (risk universe)",
  sigma_treatment_scope = "대각(개별분산)만. 상관행렬 C 는 전 arm 동일 — 처치 효과가 상관구조 변화로 오염되지 않음.")
write_json(meta, file.path(OUT_DIR, "fq108_run03_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_03 —", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
