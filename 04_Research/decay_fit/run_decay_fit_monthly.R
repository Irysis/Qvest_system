##=============================================================================
## run_decay_fit_monthly.R — FQ-055 감쇠 함수형 진단 (월간 2계층: S-M + C-M)
##
## ★진단 전용 (metric_type=diagnostic_fit) — 자본/graduation 판정 아님.
## 사전등록: stage_artifacts/decay_fit/preregistration.json (SHA 기록)
## 모델: M0 null / M1 linear / M2 exponential / M3 hyperbolic / M4 break
##       λ·τ 그리드 프로파일 + closed-form OLS (nls 미사용 — 결정론)
## 실행: cwd=프로젝트 루트, Rscript --no-save 04_Research/decay_fit/run_decay_fit_monthly.R
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite); library(digest); library(dplyr) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- "stage_artifacts/decay_fit"
dir.create(file.path(OUT, "charts"), recursive = TRUE, showWarnings = FALSE)
RUNTAG <- "20260717"
LOG <- file.path(OUT, "_run_log.txt")
wf <- function(fmt, ...) { m <- sprintf(fmt, ...); cat(m, "\n"); cat(m, "\n", file = LOG, append = TRUE) }
t_start <- Sys.time()
set.seed(20260717)

wf("=== FQ-055 decay_fit monthly start %s ===", format(t_start))

## ── 사전등록 동결 확인 ─────────────────────────────────────────────────────
PREREG_PATH <- file.path(OUT, "preregistration.json")
stopifnot(file.exists(PREREG_PATH))
PREREG_SHA <- digest(readChar(PREREG_PATH, file.info(PREREG_PATH)$size), algo = "sha256")
wf("prereg sha256=%s", substr(PREREG_SHA, 1, 16))

## ── vintage pin (소형 입력 2종; §7 비례 원칙 — prereg 기재) ────────────────
source("02_Infrastructure/data/pin_cache.R")
PIN_TAG <- paste0("decay_fit_", RUNTAG)
IC_PATH <- ".cache/factor_db/factor_ic_monthly.parquet"
R6_PATH <- "outputs/ramp/r6_factor_deployzone_active.parquet"
get_pinned <- function(p) tryCatch(read_pinned(p, PIN_TAG), error = function(e) { pin_cache(c(IC_PATH, R6_PATH), PIN_TAG); read_pinned(p, PIN_TAG) })
ic_dt <- as.data.table(read_parquet(get_pinned(IC_PATH)))
r6_dt <- as.data.table(read_parquet(get_pinned(R6_PATH)))
wf("pinned inputs: ic rows=%d, r6 rows=%d (tag=%s)", nrow(ic_dt), nrow(r6_dt), PIN_TAG)

## rawdata 상태 기록 (복사 없이 — prereg 비례 원칙)
rd_info <- file.info(".cache/rawdata.parquet")
wf("rawdata: size=%.2fGB mtime=%s (R47 parity 상태 — 유니버스 행 불변 확인분)", rd_info$size/1e9, format(rd_info$mtime))

## ── EW-uni 벤치 구성 (r13 동일 lineage, arrow pushdown으로 월말 행만) ──────
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns (K200|KQ150 필터 + R44 방화벽 내장)
sigs <- sort(unique(as.Date(r6_dt$signal_date)))
month_end <- function(d) { m0 <- as.Date(cut(d, "month")); seq(m0, by = "1 month", length.out = 2)[2] - 1 }  # 해당 월의 말일 (버그수정 20260718: 구판 by="2 months"는 다음달 말 반환 → 터미널월 오염)
sigs_ext <- c(sigs, month_end(max(sigs) + 1))          # 터미널 forward 커버용: 다음 달 월말(2026-06-30)
ud <- unique(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)
ud <- sort(as.Date(ud))
me_dates <- as.Date(vapply(sigs_ext, function(d) { v <- ud[ud <= d]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1)))
me_dates <- unique(me_dates[!is.na(me_dates)])
wf("month-end trading dates: %d (range %s..%s)", length(me_dates), format(min(me_dates)), format(max(me_dates)))
.need <- c("Date", "Ticker", "Close", "K200", "KQ150", "Vol", "Size")
raw_me <- tryCatch({
  x <- open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me_dates) |> select(all_of(.need)) |> collect()
  as.data.table(x)
}, error = function(e) data.table())
if (nrow(raw_me) == 0) {
  wf("pushdown 0행/실패 — full col_select 폴백 (RAM 주의)")
  raw_me <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = all_of(.need)))
  raw_me[, Date := as.Date(Date)]
  raw_me <- raw_me[Date %in% me_dates]
  invisible(gc())
} else raw_me[, Date := as.Date(Date)]
stopifnot(nrow(raw_me) > 0)
wf("raw_me rows=%d", nrow(raw_me))
## 헬퍼는 sig_dates의 asof 월말을 스스로 매핑 — rawme를 me_dates 행으로 한정했으므로 동일 동작
fwd <- build_monthly_forward_returns(raw_me, sigs_ext)
rm(raw_me); invisible(gc())
ewb <- fwd$returns_dt[, .(signal_date = as.Date(Date), ew = mean(Ret_1m, na.rm = TRUE)), by = .(Date)][, .(signal_date, ew)]
## parity 체크: 재구성 cap-w 벤치 vs r6 저장 benchmark_ret
par_chk <- merge(unique(r6_dt[, .(signal_date = as.Date(signal_date), benchmark_ret)]),
                 fwd$bench_dt[, .(signal_date = as.Date(Date), BM_Ret)], by = "signal_date")
par_max <- par_chk[, max(abs(benchmark_ret - BM_Ret), na.rm = TRUE)]
wf("bench parity max|d| = %.2e over %d months %s", par_max, nrow(par_chk),
   ifelse(par_max < 1e-8, "(PASS — 정렬 검증)", "(!! MISMATCH — ewb 정렬 재점검 필요, capw는 저장 패널 사용이라 판정 영향 없음)"))

cm_base <- merge(r6_dt[, .(signal_date = as.Date(signal_date), factor_id, family, ret_net, active_bm)],
                 ewb, by = "signal_date", all.x = TRUE)
cm_base[, active_ew := ret_net - ew]
n_na_ew <- cm_base[is.na(active_ew), .N]
wf("cm_base rows=%d (active_ew NA=%d)", nrow(cm_base), n_na_ew)

##=============================================================================
## 적합 엔진
##=============================================================================
LGRID <- exp(seq(log(5e-4), log(0.5), length.out = 60))
AICC <- function(rss, n, k) { if (n - k - 1 <= 0 || rss <= 0) return(Inf); n * log(rss / n) + 2 * k + 2 * k * (k + 1) / (n - k - 1) }

fit_models <- function(y, tvec) {
  n <- length(y)
  out <- list()
  ybar <- mean(y); rss0 <- sum((y - ybar)^2)
  if (rss0 < 1e-14) return(NULL)
  out$M0 <- list(rss = rss0, k = 2, par = list(c = ybar))
  ## M1 linear (b>=0)
  cf <- .lm.fit(cbind(1, tvec), y)$coefficients
  if (cf[2] < 0) {
    rss <- sum((y - (cf[1] + cf[2] * tvec))^2)
    out$M1 <- list(rss = rss, k = 3, par = list(K = cf[1], b = -cf[2]))
  }
  ## M2 exponential / M3 hyperbolic — λ 프로파일 + optimize 정련
  prof <- function(basis_fun) {
    best <- NULL
    for (lam in LGRID) {
      b <- basis_fun(lam); Kh <- sum(y * b) / sum(b * b)
      if (Kh > 0) { rss <- sum((y - Kh * b)^2); if (is.null(best) || rss < best$rss) best <- list(rss = rss, K = Kh, lam = lam) }
    }
    if (is.null(best)) return(NULL)
    o <- tryCatch(optimize(function(l) { b <- basis_fun(l); Kh <- sum(y * b) / sum(b * b); if (Kh <= 0) return(Inf); sum((y - Kh * b)^2) },
                           interval = c(max(best$lam / 3, 1e-5), min(best$lam * 3, 1)), tol = 1e-7), error = function(e) NULL)
    if (!is.null(o) && is.finite(o$objective) && o$objective < best$rss) {
      b <- basis_fun(o$minimum); best <- list(rss = o$objective, K = sum(y * b) / sum(b * b), lam = o$minimum)
    }
    best
  }
  e2 <- prof(function(l) exp(-l * tvec))
  if (!is.null(e2)) out$M2 <- list(rss = e2$rss, k = 3, par = list(K = e2$K, lambda = e2$lam))
  e3 <- prof(function(l) 1 / (1 + l * tvec))
  if (!is.null(e3)) out$M3 <- list(rss = e3$rss, k = 3, par = list(K = e3$K, lambda = e3$lam))
  ## M4 break (τ interior, margin 24)
  if (n >= 60) {
    cs <- cumsum(y); cs2 <- cumsum(y^2); best4 <- NULL
    for (tau in 24:(n - 24)) {
      n1 <- tau; n2 <- n - tau
      m1 <- cs[tau] / n1; m2 <- (cs[n] - cs[tau]) / n2
      rss <- (cs2[tau] - n1 * m1^2) + (cs2[n] - cs2[tau] - n2 * m2^2)
      if (is.null(best4) || rss < best4$rss) best4 <- list(rss = rss, tau = tau, c1 = m1, c2 = m2)
    }
    out$M4 <- list(rss = best4$rss, k = 4, par = best4)
  }
  n_out <- lapply(out, function(m) { m$aicc <- AICC(m$rss, n, m$k); m })
  n_out
}

eval_model <- function(form, par, t) {
  switch(form,
    M0 = rep(par$c, length(t)),
    M1 = par$K - par$b * t,
    M2 = par$K * exp(-par$lambda * t),
    M3 = par$K / (1 + par$lambda * t),
    M4 = ifelse(t < par$tau, par$c1, par$c2))
}

select_label <- function(fits) {
  ai <- sapply(fits, `[[`, "aicc")
  rank_str <- paste(names(sort(ai)), collapse = ">")
  cand <- setdiff(names(ai), "M0")
  if (!length(cand)) return(list(label = "cycling_nofit", best = "M0", d_null = 0, d_second = NA_real_, rank = rank_str))
  best <- cand[which.min(ai[cand])]
  d_null <- ai["M0"] - ai[best]
  if (!is.finite(d_null) || d_null < 2) return(list(label = "cycling_nofit", best = "M0", d_null = d_null, d_second = NA_real_, rank = rank_str))
  smooth <- intersect(c("M1", "M2", "M3"), names(ai))
  if (best == "M4") {
    d_sm <- if (length(smooth)) min(ai[smooth]) - ai["M4"] else Inf
    if (d_sm >= 2) return(list(label = "break_dominated", best = "M4", d_null = d_null, d_second = d_sm, rank = rank_str))
    best <- smooth[which.min(ai[smooth])]  # margin 미달 — smooth 최선으로 계속
  }
  others <- setdiff(cand, best)
  d_second <- if (length(others)) min(ai[others]) - ai[best] else Inf
  lab <- if (d_second < 2) "ambiguous_decay" else switch(best, M3 = "crowding_hyperbolic", M2 = "absorbed_exponential", M1 = "linear_trend", M4 = "break_dominated")
  list(label = lab, best = best, d_null = d_null, d_second = d_second, rank = rank_str)
}

mbb <- function(u, block = 12) {
  n <- length(u); nb <- ceiling(n / block)
  starts <- sample.int(n - block + 1, nb, replace = TRUE)
  idx <- unlist(lapply(starts, function(s) s:(s + block - 1)))[1:n]
  u[idx]
}

## 롤링 시계열 구성기 (underlying → y,t,date)
build_roll <- function(u, dates, w, minobs, stat = c("mean", "sr")) {
  stat <- match.arg(stat)
  cnt <- frollsum(!is.na(u), w)
  if (stat == "mean") { y <- frollmean(u, w, na.rm = TRUE) }
  else {
    mu <- frollmean(u, w, na.rm = TRUE)
    sdv <- frollapply(u, w, function(z) sd(z, na.rm = TRUE))
    y <- (mu / sdv) * sqrt(12)
  }
  y[is.na(cnt) | cnt < minobs] <- NA
  ok <- which(!is.na(y))
  if (!length(ok)) return(NULL)
  i0 <- min(ok)
  keep <- i0:length(y)
  cc <- keep[!is.na(y[keep])]
  list(y = y[cc], tvec = cc - i0, dates = dates[cc])
}

## 시리즈 1건 처리 (point fit + bootstrap stability)
run_one <- function(u, dates, w, minobs, stat, n_boot, min_n_fit = 96) {
  early36 <- { v <- u[!is.na(u)]; if (length(v) >= 36) mean(v[1:36]) else NA_real_ }
  last36  <- { v <- u[!is.na(u)]; if (length(v) >= 36) mean(tail(v, 36)) else NA_real_ }
  base <- list(early36 = early36, last36 = last36)
  if (!is.na(early36) && early36 <= 0)
    return(c(base, list(label = "no_initial_signal", best = NA_character_, n_fit = NA_integer_)))
  rl <- build_roll(u, dates, w, minobs, stat)
  if (is.null(rl) || length(rl$y) < min_n_fit)
    return(c(base, list(label = "insufficient_series", best = NA_character_, n_fit = if (is.null(rl)) 0L else length(rl$y))))
  fits <- fit_models(rl$y, rl$tvec)
  if (is.null(fits)) return(c(base, list(label = "degenerate", best = NA_character_, n_fit = length(rl$y))))
  sel <- select_label(fits)
  bp <- fits[[sel$best]]$par
  t_now <- max(rl$tvec)
  fit_now <- eval_model(sel$best, bp, t_now); fit_p24 <- eval_model(sel$best, bp, t_now + 24)
  r2 <- 1 - fits[[sel$best]]$rss / fits[["M0"]]$rss
  brk <- if (sel$best == "M4") format(rl$dates[bp$tau]) else NA_character_
  Kv <- if (sel$best %in% c("M1", "M2", "M3")) bp$K else NA_real_
  rate <- if (sel$best == "M2" || sel$best == "M3") bp$lambda else if (sel$best == "M1") bp$b else NA_real_
  ## bootstrap stability
  match_n <- 0L
  for (b in seq_len(n_boot)) {
    ub <- mbb(u[!is.na(u)])
    rb <- build_roll(ub, seq_along(ub), w, minobs, stat)
    if (is.null(rb) || length(rb$y) < min_n_fit) next
    fb <- fit_models(rb$y, rb$tvec)
    if (is.null(fb)) next
    if (select_label(fb)$label == sel$label) match_n <- match_n + 1L
  }
  stab <- match_n / n_boot
  tier <- if (stab >= 0.70) "high" else if (stab >= 0.50) "med" else "low"
  c(base, list(label = sel$label, best = sel$best, d_aicc_null = sel$d_null, d_aicc_second = sel$d_second,
               K = Kv, rate = rate, fitted_now = fit_now, fitted_p24 = fit_p24, break_date = brk,
               r2 = r2, n_fit = length(rl$y), sel_stability = stab, conf_tier = tier, rank = sel$rank,
               date_start = format(min(rl$dates)), date_end = format(max(rl$dates))))
}

as_row <- function(res, id_cols) {
  full <- list(label = NA_character_, best = NA_character_, d_aicc_null = NA_real_, d_aicc_second = NA_real_,
               K = NA_real_, rate = NA_real_, fitted_now = NA_real_, fitted_p24 = NA_real_, break_date = NA_character_,
               r2 = NA_real_, n_fit = NA_integer_, sel_stability = NA_real_, conf_tier = NA_character_, rank = NA_character_,
               date_start = NA_character_, date_end = NA_character_, early36 = NA_real_, last36 = NA_real_)
  for (nm in names(res)) full[[nm]] <- res[[nm]]
  as.data.table(c(id_cols, full))
}

##=============================================================================
## S-M 계층: factor_ic_monthly rolling 36m mean IC
##=============================================================================
wf("--- S-M layer start ---")
ic_dt[, Date := as.Date(Date)]
elig_sm <- ic_dt[, .N, by = Factor_Name][N >= 180, Factor_Name]
wf("S-M eligible factors: %d / %d (>=180 IC months)", length(elig_sm), uniqueN(ic_dt$Factor_Name))
sm_rows <- list()
for (i in seq_along(elig_sm)) {
  fn <- elig_sm[i]
  sub <- ic_dt[Factor_Name == fn][order(Date)]
  res <- run_one(sub$IC, sub$Date, w = 36, minobs = 30, stat = "mean", n_boot = 120)
  sm_rows[[i]] <- as_row(res, list(layer = "SM", basis = "ic", factor = fn, family = NA_character_))
  if (i %% 25 == 0) wf("  S-M %d/%d (%.1f min)", i, length(elig_sm), as.numeric(difftime(Sys.time(), t_start, units = "mins")))
}
SM <- rbindlist(sm_rows, fill = TRUE)
write_parquet(SM, file.path(OUT, sprintf("decay_fit_SM_%s.parquet", RUNTAG)))
wf("S-M done: %d rows. label dist: %s", nrow(SM), paste(capture.output(print(SM[, .N, by = label][order(-N)])), collapse = " | "))

##=============================================================================
## C-M 계층: r6 배포권 active — capw + ewuni dual-basis, rolling 60m SR
##=============================================================================
wf("--- C-M layer start ---")
elig_cm <- cm_base[!is.na(active_bm), .N, by = factor_id][N >= 120, factor_id]
wf("C-M eligible factors: %d / %d (>=120 active months)", length(elig_cm), uniqueN(cm_base$factor_id))
cm_rows <- list(); k <- 0L
for (i in seq_along(elig_cm)) {
  fid <- elig_cm[i]
  sub <- cm_base[factor_id == fid][order(signal_date)]
  fam <- sub$family[1]
  for (bas in c("capw", "ewuni")) {
    u <- if (bas == "capw") sub$active_bm else sub$active_ew
    res <- run_one(u, sub$signal_date, w = 60, minobs = 54, stat = "sr", n_boot = 200)
    k <- k + 1L
    cm_rows[[k]] <- as_row(res, list(layer = "CM", basis = bas, factor = fid, family = fam))
  }
  if (i %% 20 == 0) wf("  C-M %d/%d (%.1f min)", i, length(elig_cm), as.numeric(difftime(Sys.time(), t_start, units = "mins")))
}
CM <- rbindlist(cm_rows, fill = TRUE)
## dual-basis divergence flag
dv <- dcast(CM, factor ~ basis, value.var = "label")
dv[, divergence_flag := !is.na(capw) & !is.na(ewuni) & capw != ewuni]
CM <- merge(CM, dv[, .(factor, divergence_flag)], by = "factor", all.x = TRUE)
write_parquet(CM, file.path(OUT, sprintf("decay_fit_CM_%s.parquet", RUNTAG)))
wf("C-M done: %d rows. divergence n=%d/%d", nrow(CM), dv[divergence_flag == TRUE, .N], nrow(dv))
wf("C-M capw label dist: %s", paste(capture.output(print(CM[basis == "capw", .N, by = label][order(-N)])), collapse = " | "))
wf("C-M ewuni label dist: %s", paste(capture.output(print(CM[basis == "ewuni", .N, by = label][order(-N)])), collapse = " | "))

##=============================================================================
## 요약 + 차트
##=============================================================================
summ <- list(
  round_id = "FQ-055_decay_fit_monthly", runtag = RUNTAG, prereg_sha256 = PREREG_SHA,
  metric_type = "diagnostic_fit", pin_tag = PIN_TAG,
  bench_parity_max_abs = par_max,
  sm = list(n_series = nrow(SM), labels = SM[, .N, by = label][order(-N)]),
  cm = list(n_series = nrow(CM), n_factors = uniqueN(CM$factor),
            labels_capw = CM[basis == "capw", .N, by = label][order(-N)],
            labels_ewuni = CM[basis == "ewuni", .N, by = label][order(-N)],
            divergence_n = dv[divergence_flag == TRUE, .N]),
  runtime_min = as.numeric(difftime(Sys.time(), t_start, units = "mins")),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(summ, file.path(OUT, sprintf("decay_fit_summary_%s.json", RUNTAG)), auto_unbox = TRUE, pretty = TRUE, digits = 8)

## 차트 1: 라벨 분포
tryCatch({
  png(file.path(OUT, "charts", "label_distribution.png"), width = 1100, height = 500)
  par(mfrow = c(1, 3), mar = c(9, 4, 3, 1))
  for (nm in list(list(d = SM, ti = "S-M (rolling 36m IC)"), list(d = CM[basis == "capw"], ti = "C-M capw (rolling 60m SR)"), list(d = CM[basis == "ewuni"], ti = "C-M ewuni"))) {
    tb <- nm$d[, .N, by = label][order(-N)]
    barplot(tb$N, names.arg = tb$label, las = 2, main = nm$ti, col = "steelblue")
  }
  dev.off()
}, error = function(e) wf("chart label_distribution FAIL: %s", conditionMessage(e)))

## 차트 2: 대표 적합 곡선 (C-M capw 중 stability 상위 decay 3건 + break 1건)
plot_fit <- function(fid, bas, fname) {
  sub <- cm_base[factor_id == fid][order(signal_date)]
  u <- if (bas == "capw") sub$active_bm else sub$active_ew
  rl <- build_roll(u, sub$signal_date, 60, 54, "sr"); if (is.null(rl)) return(invisible(NULL))
  fits <- fit_models(rl$y, rl$tvec); if (is.null(fits)) return(invisible(NULL))
  sel <- select_label(fits)
  png(fname, width = 900, height = 480)
  plot(rl$dates, rl$y, type = "l", lwd = 2, main = sprintf("%s [%s] %s", fid, bas, sel$label),
       xlab = "date", ylab = "rolling 60m ann. SR (net active)")
  abline(h = 0, lty = 3)
  cols <- c(M1 = "orange", M2 = "red", M3 = "blue", M4 = "darkgreen")
  for (m in intersect(names(fits), names(cols)))
    lines(rl$dates, eval_model(m, fits[[m]]$par, rl$tvec), col = cols[m], lty = ifelse(m == sel$best, 1, 2), lwd = ifelse(m == sel$best, 2.5, 1.2))
  legend("topright", legend = c("series", names(cols)), col = c("black", cols), lwd = 2, cex = 0.85)
  dev.off()
}
tryCatch({
  cw <- CM[basis == "capw" & label %in% c("crowding_hyperbolic", "absorbed_exponential", "linear_trend", "ambiguous_decay")][order(-sel_stability)]
  for (j in seq_len(min(3, nrow(cw)))) plot_fit(cw$factor[j], "capw", file.path(OUT, "charts", sprintf("fit_decay_%d_%s.png", j, cw$factor[j])))
  bw <- CM[basis == "capw" & label == "break_dominated"][order(-sel_stability)]
  if (nrow(bw)) plot_fit(bw$factor[1], "capw", file.path(OUT, "charts", sprintf("fit_break_%s.png", bw$factor[1])))
  dvf <- CM[basis == "capw" & divergence_flag == TRUE][order(-sel_stability)]
  if (nrow(dvf)) { plot_fit(dvf$factor[1], "capw", file.path(OUT, "charts", sprintf("fit_diverge_capw_%s.png", dvf$factor[1])))
                   plot_fit(dvf$factor[1], "ewuni", file.path(OUT, "charts", sprintf("fit_diverge_ewuni_%s.png", dvf$factor[1]))) }
}, error = function(e) wf("chart exemplar FAIL: %s", conditionMessage(e)))

wf("=== ALL DONE %.1f min ===", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
