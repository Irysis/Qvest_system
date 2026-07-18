##=============================================================================
## decay_fit_engine.R — FQ-055 공용 적합 엔진 (월간 러너에서 추출)
## 모델: M0 null / M1 linear / M2 exp / M3 hyperbolic / M4 break
## λ·τ 그리드 프로파일 + closed-form OLS. metric_type=diagnostic_fit 전용.
##=============================================================================
LGRID <- exp(seq(log(5e-4), log(0.5), length.out = 60))
AICC <- function(rss, n, k) { if (n - k - 1 <= 0 || rss <= 0) return(Inf); n * log(rss / n) + 2 * k + 2 * k * (k + 1) / (n - k - 1) }

fit_models <- function(y, tvec) {
  n <- length(y); out <- list()
  ybar <- mean(y); rss0 <- sum((y - ybar)^2)
  if (rss0 < 1e-14) return(NULL)
  out$M0 <- list(rss = rss0, k = 2, par = list(c = ybar))
  cf <- .lm.fit(cbind(1, tvec), y)$coefficients
  if (cf[2] < 0) out$M1 <- list(rss = sum((y - (cf[1] + cf[2] * tvec))^2), k = 3, par = list(K = cf[1], b = -cf[2]))
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
  e2 <- prof(function(l) exp(-l * tvec));      if (!is.null(e2)) out$M2 <- list(rss = e2$rss, k = 3, par = list(K = e2$K, lambda = e2$lam))
  e3 <- prof(function(l) 1 / (1 + l * tvec));  if (!is.null(e3)) out$M3 <- list(rss = e3$rss, k = 3, par = list(K = e3$K, lambda = e3$lam))
  if (n >= 60) {
    m4margin <- max(24, floor(n * 0.1))
    cs <- cumsum(y); cs2 <- cumsum(y^2); best4 <- NULL
    for (tau in m4margin:(n - m4margin)) {
      n1 <- tau; n2 <- n - tau
      m1 <- cs[tau] / n1; m2 <- (cs[n] - cs[tau]) / n2
      rss <- (cs2[tau] - n1 * m1^2) + (cs2[n] - cs2[tau] - n2 * m2^2)
      if (is.null(best4) || rss < best4$rss) best4 <- list(rss = rss, tau = tau, c1 = m1, c2 = m2)
    }
    out$M4 <- list(rss = best4$rss, k = 4, par = best4)
  }
  lapply(out, function(m) { m$aicc <- AICC(m$rss, n, m$k); m })
}

eval_model <- function(form, par, t) {
  switch(form,
    M0 = rep(par$c, length(t)), M1 = par$K - par$b * t,
    M2 = par$K * exp(-par$lambda * t), M3 = par$K / (1 + par$lambda * t),
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
    best <- smooth[which.min(ai[smooth])]
  }
  others <- setdiff(cand, best)
  d_second <- if (length(others)) min(ai[others]) - ai[best] else Inf
  lab <- if (d_second < 2) "ambiguous_decay" else switch(best, M3 = "crowding_hyperbolic", M2 = "absorbed_exponential", M1 = "linear_trend", M4 = "break_dominated")
  list(label = lab, best = best, d_null = d_null, d_second = d_second, rank = rank_str)
}

mbb <- function(u, block = 12) {
  n <- length(u); nb <- ceiling(n / block)
  starts <- sample.int(n - block + 1, nb, replace = TRUE)
  u[unlist(lapply(starts, function(s) s:(s + block - 1)))[1:n]]
}

build_roll <- function(u, dates, w, minobs, stat = c("mean", "sr")) {
  stat <- match.arg(stat)
  cnt <- frollsum(!is.na(u), w)
  if (stat == "mean") y <- frollmean(u, w, na.rm = TRUE)
  else { mu <- frollmean(u, w, na.rm = TRUE); sdv <- frollapply(u, w, function(z) sd(z, na.rm = TRUE)); y <- (mu / sdv) * sqrt(12) }
  y[is.na(cnt) | cnt < minobs] <- NA
  ok <- which(!is.na(y)); if (!length(ok)) return(NULL)
  keep <- min(ok):length(y); cc <- keep[!is.na(y[keep])]
  list(y = y[cc], tvec = cc - min(ok), dates = dates[cc])
}

## t_scale: tvec을 월 단위로 환산하는 제수 (월간=1, 일간=21 — LGRID 범위 재사용)
run_one <- function(u, dates, w, minobs, stat, n_boot, min_n_fit = 96, block = 12, t_scale = 1) {
  early_n <- if (t_scale > 1) 756 else 36    # 일간이면 첫 36개월≈756거래일
  v <- u[!is.na(u)]
  early <- if (length(v) >= early_n) mean(v[1:early_n]) else NA_real_
  lastm <- if (length(v) >= early_n) mean(tail(v, early_n)) else NA_real_
  base <- list(early36 = early, last36 = lastm)
  if (!is.na(early) && early <= 0) return(c(base, list(label = "no_initial_signal", best = NA_character_, n_fit = NA_integer_)))
  rl <- build_roll(u, dates, w, minobs, stat)
  if (is.null(rl) || length(rl$y) < min_n_fit)
    return(c(base, list(label = "insufficient_series", best = NA_character_, n_fit = if (is.null(rl)) 0L else length(rl$y))))
  tv <- rl$tvec / t_scale
  fits <- fit_models(rl$y, tv); if (is.null(fits)) return(c(base, list(label = "degenerate", best = NA_character_, n_fit = length(rl$y))))
  sel <- select_label(fits)
  bp <- fits[[sel$best]]$par
  t_now <- max(tv)
  brk <- if (sel$best == "M4") format(rl$dates[bp$tau]) else NA_character_
  Kv <- if (sel$best %in% c("M1", "M2", "M3")) bp$K else NA_real_
  rate <- if (sel$best %in% c("M2", "M3")) bp$lambda else if (sel$best == "M1") bp$b else NA_real_
  match_n <- 0L
  for (b in seq_len(n_boot)) {
    ub <- mbb(u[!is.na(u)], block = block)
    rb <- build_roll(ub, seq_along(ub), w, minobs, stat)
    if (is.null(rb) || length(rb$y) < min_n_fit) next
    fb <- fit_models(rb$y, rb$tvec / t_scale); if (is.null(fb)) next
    if (select_label(fb)$label == sel$label) match_n <- match_n + 1L
  }
  stab <- match_n / n_boot
  c(base, list(label = sel$label, best = sel$best, d_aicc_null = sel$d_null, d_aicc_second = sel$d_second,
               K = Kv, rate = rate, fitted_now = eval_model(sel$best, bp, t_now), fitted_p24 = eval_model(sel$best, bp, t_now + 24),
               break_date = brk, r2 = 1 - fits[[sel$best]]$rss / fits[["M0"]]$rss, n_fit = length(rl$y),
               sel_stability = stab, conf_tier = if (stab >= 0.70) "high" else if (stab >= 0.50) "med" else "low",
               rank = sel$rank, date_start = format(min(rl$dates)), date_end = format(max(rl$dates))))
}

as_row <- function(res, id_cols) {
  full <- list(label = NA_character_, best = NA_character_, d_aicc_null = NA_real_, d_aicc_second = NA_real_,
               K = NA_real_, rate = NA_real_, fitted_now = NA_real_, fitted_p24 = NA_real_, break_date = NA_character_,
               r2 = NA_real_, n_fit = NA_integer_, sel_stability = NA_real_, conf_tier = NA_character_, rank = NA_character_,
               date_start = NA_character_, date_end = NA_character_, early36 = NA_real_, last36 = NA_real_)
  for (nm in names(res)) full[[nm]] <- res[[nm]]
  as.data.table(c(id_cols, full))
}
