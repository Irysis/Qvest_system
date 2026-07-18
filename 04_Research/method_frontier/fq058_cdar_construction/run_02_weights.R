# =============================================================================
# FQ-058 run_02: 5-arm walk-forward weight 생성 (동일 top-25 basket, 위험 measure swap)
#   EW / MVO(alpha+60m lw_nls var) / MinVar(daily-120 var) /
#   MinCDaR(daily-120 CDaR cccp) / MinCVaR(daily-120 CVaR cccp)
#   PRIMARY 판정축 = MinCDaR vs MinVar (measure만 상이, alpha 미사용 동일).
#   parallel: future_lapply over (factor, month) cells. LP fallback 감사.
# Output: fq058_weights.parquet + fq058_run02_meta.json
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/fq058_cdar_construction/fq058_lib.R")
suppressPackageStartupMessages({ library(quadprog); library(future.apply) })

ROOT <- ROOT_F58; OUT <- OUT_F58
LIQ_MIN <- 2e8; WIN_M <- 60L; N_DAYS <- 120L; MAXW <- 0.20; TOPN <- 25L
LAMBDA <- 2.0; PSI <- 0.3; ALPHA_SCALE <- 0.01; MINN <- 15L; HHI_CAP <- 0.10; AWINSOR <- 2.0
CVAR_ALPHA <- 0.95

P  <- load_panels_f58()
BK <- as.data.table(read_parquet(file.path(OUT, "fq058_baskets.parquet")))
factors <- sort(unique(BK$factor))
basket_tks <- sort(unique(BK$Ticker))
cat("[input] factors:", paste(factors, collapse = ","), "| basket tickers:", length(basket_tks), "\n")

# daily returns (basket 종목만) — 워커 export 축소
DAILY <- as.data.table(read_parquet(file.path(OUT, "p1_daily_returns.parquet"),
                                    col_select = c("Date", "Ticker", "Ret")))
DAILY <- DAILY[Ticker %in% basket_tks]
setkey(DAILY, Ticker, Date)
MATm <- P$mat; YMS <- P$yms
cat("[input] daily rows(basket):", nrow(DAILY), "\n")

# task list
tasks <- unique(BK[, .(factor, ym)])
cat("[tasks]", nrow(tasks), "cells\n")

# ---- 워커 함수 --------------------------------------------------------------
compute_cell <- function(i) {
  suppressPackageStartupMessages({ library(data.table); library(quadprog) })
  setDTthreads(1)
  # 워커별 1회 infra source (persistent multisession worker — 전역 guard)
  if (!exists(".FQ058_SRC", envir = .GlobalEnv)) {
    rt <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
    source(file.path(rt, "04_Research/method_frontier/fq058_cdar_construction/fq058_lib.R"))
    source(file.path(rt, "02_Infrastructure/portfolio/hrp_core.R"))
    source(file.path(rt, "02_Infrastructure/portfolio/mean_variance_optimizer.R"))
    source(file.path(rt, "02_Infrastructure/portfolio/advanced_weights.R"))
    assign(".FQ058_SRC", TRUE, envir = .GlobalEnv)
  }
  f <- tasks$factor[i]; t_ym <- tasks$ym[i]
  bk <- BK[factor == f & ym == t_ym]
  tks <- bk$Ticker; z <- setNames(bk$z, bk$Ticker)
  out <- list(); metas <- list()
  add <- function(arm, w, fb = FALSE, nn = NA_integer_) {
    w[!is.finite(w) | w < 0] <- 0
    if (sum(w) <= 0) return(invisible())
    w <- w / sum(w)
    out[[length(out) + 1L]] <<- data.table(factor = f, arm = arm, ym = t_ym, Ticker = names(w), w = as.numeric(w))
    metas[[length(metas) + 1L]] <<- data.table(factor = f, arm = arm, ym = t_ym,
      n_names = sum(w > 1e-4), max_w = max(w), fallback = fb)
  }

  # ---- EW ----
  w_ew <- setNames(rep(1 / length(tks), length(tks)), tks); add("EW", w_ew)

  # ---- MVO (alpha + 60m lw_nls monthly var) ----
  idx <- match(t_ym, YMS); w_idx <- (idx - WIN_M + 1L):idx
  ret60 <- MATm[w_idx, tks, drop = FALSE]
  keep <- colSums(!is.na(ret60)) == WIN_M
  tks_m <- tks[keep]
  mvo_ok <- FALSE
  if (length(tks_m) >= MINN) {
    ret60m <- ret60[, tks_m, drop = FALSE]
    Sig <- tryCatch(.get_cor_cov(ret60m, "lw_nls")$cov, error = function(e) NULL)
    if (!is.null(Sig)) {
      zz <- z[tks_m]; zz <- (zz - mean(zz)) / (sd(zz) + 1e-12)
      av <- ALPHA_SCALE * zz; names(av) <- tks_m
      res <- tryCatch(mvo_weights(alpha = av, cov_matrix = Sig, confidence = NULL,
                     lambda = LAMBDA, psi = PSI, bounds = c(0, MAXW),
                     max_names = TOPN, min_names = MINN, hhi_cap = HHI_CAP,
                     alpha_winsor = AWINSOR, turnover_penalty = 0.0, active = FALSE),
                     error = function(e) NULL)
      if (!is.null(res) && !is.null(res$weights)) {
        w <- res$weights; names(w) <- names(res$weights); add("MVO", w); mvo_ok <- TRUE
      }
    }
  }
  if (!mvo_ok) add("MVO", w_ew, fb = TRUE)   # 퇴화 시 EW 대체(카운트) — paired 무결 유지

  # ---- daily 표본 (Date <= month-end t) ----
  cutoff <- ym2date_f(t_ym)
  dsub <- DAILY[Ticker %in% tks & Date <= cutoff]
  recent <- tail(sort(unique(dsub$Date)), N_DAYS)
  dsub <- dsub[Date %in% recent]

  # ---- MinVar (daily-120 sample cov, quadprog) ----
  minvar_ok <- FALSE
  wide <- dcast(dsub, Date ~ Ticker, value.var = "Ret")
  Rd <- as.matrix(wide[, -1, with = FALSE]); Rd[is.na(Rd)] <- 0
  colnames(Rd) <- names(wide)[-1]
  good <- colSums(Rd != 0) >= 60L; Rd <- Rd[, good, drop = FALSE]
  if (ncol(Rd) >= 2L && nrow(Rd) >= ncol(Rd) + 5L) {
    S <- cov(Rd); S <- (S + t(S)) / 2 + diag(1e-8, ncol(S))
    p <- ncol(S)
    Dmat <- 2 * S; dvec <- rep(0, p)
    Amat <- cbind(rep(1, p), diag(p), -diag(p))
    bvec <- c(1, rep(0, p), rep(-MAXW, p))
    sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
    if (!is.null(sol)) {
      w <- pmax(sol$solution, 0); names(w) <- colnames(S)
      if (sum(w) > 1e-8) { add("MinVar", w); minvar_ok <- TRUE }
    }
  }
  if (!minvar_ok) add("MinVar", w_ew, fb = TRUE)

  # ---- MinCDaR / MinCVaR (cccp LP) — fallback 감사(capture) ----
  ret_dt <- dsub[, .(Date, Ticker, Ret)]
  run_lp <- function(fn, arm) {
    ok <- FALSE
    co <- capture.output({ w <- tryCatch(fn(tks, ret_dt, alpha = CVAR_ALPHA, n_days = N_DAYS, max_w = MAXW),
                                         error = function(e) { cat("ERRLP", conditionMessage(e), "\n"); NULL }) })
    fb <- any(grepl("falling back|failed|ERRLP", co))
    if (!is.null(w) && sum(w, na.rm = TRUE) > 1e-8) { names(w) <- tks; add(arm, w, fb = fb) }
    else add(arm, w_ew, fb = TRUE)
  }
  run_lp(calc_cdar_weights, "MinCDaR")
  run_lp(calc_cvar_lp_weights, "MinCVaR")

  list(w = rbindlist(out), meta = rbindlist(metas))
}

# ---- 병렬 실행 --------------------------------------------------------------
nw <- min(6L, max(1L, parallel::detectCores() - 1L))
plan(multisession, workers = nw)
cat("[parallel] workers:", nw, "\n")
t0 <- Sys.time()
res <- future_lapply(seq_len(nrow(tasks)), compute_cell,
        future.globals = list(tasks = tasks, BK = BK, DAILY = DAILY, MATm = MATm, YMS = YMS,
                              ym2date_f = ym2date_f, WIN_M = WIN_M, N_DAYS = N_DAYS, MAXW = MAXW,
                              TOPN = TOPN, LAMBDA = LAMBDA, PSI = PSI, ALPHA_SCALE = ALPHA_SCALE,
                              MINN = MINN, HHI_CAP = HHI_CAP, AWINSOR = AWINSOR, CVAR_ALPHA = CVAR_ALPHA),
        future.packages = c("data.table", "quadprog", "cccp", "arrow"),
        future.seed = TRUE)
plan(sequential)
cat("[parallel] done", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")

# 워커는 fq058_lib/advanced_weights/mvo 를 source 해야 함 — future.globals 로 함수 미포함분 대비
# (compute_cell 이 .get_cor_cov/mvo_weights/calc_* 참조 → 아래 재보증)
W   <- rbindlist(lapply(res, `[[`, "w"))
MET <- rbindlist(lapply(res, `[[`, "meta"))

# ---- hard constraint audit --------------------------------------------------
aud <- W[, .(n = uniqueN(Ticker), sw = sum(w), mx = max(w), mn = min(w)), by = .(factor, arm, ym)]
viol <- aud[n > 25 | abs(sw - 1) > 1e-5 | mx > MAXW + 1e-6 | mn < -1e-9]
cat("[audit] weight cells:", nrow(aud), " violations:", nrow(viol), "\n")
if (nrow(viol) > 0) { print(head(viol, 10)); stop("HARD CONSTRAINT VIOLATION") }

fb_summary <- MET[, .(cells = .N, fallbacks = sum(fallback)), by = arm][order(arm)]
cat("=== fallback summary ===\n"); print(fb_summary)

write_parquet(W,   file.path(OUT, "fq058_weights.parquet"))
write_parquet(MET, file.path(OUT, "fq058_weight_meta.parquet"))
meta <- list(round_tag = ROUND_TAG_F58, pin_consumed = PIN_F58,
             built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             n_cells = nrow(tasks), workers = nw,
             fallback_summary = fb_summary,
             params = list(win_m = WIN_M, n_days = N_DAYS, max_w = MAXW, topn = TOPN,
                           cvar_alpha = CVAR_ALPHA, lambda = LAMBDA, psi = PSI))
write_json(meta, file.path(OUT, "fq058_run02_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_02 — weight rows:", nrow(W), "\n")
