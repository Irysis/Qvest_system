# FQ-236 Lane D — 조건부 비대칭 회귀 엔진 (사전등록 spec 고정, 탐색 도구 아님)
# Y_t = a + b * S_{t-} + e_t,  NW lag-3.  판정 그리드 F_A~F_E 는 preregistration_spec.json.
suppressMessages({library(data.table); library(sandwich); library(lmtest)})

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT-D20260822_001")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))

.load_Y <- function(tag) {
  d <- fread(file.path(OUT, sprintf("outcome_panel_%s.csv", tag)))
  d[, ym_d := as.Date(paste0(ym, "-01"))]
  d[ym_d <= as.Date("2026-07-01")]                    # 진행월 제외
}
.load_S <- function() {
  s <- fread(file.path(OUT, "S_panel_monthly.csv"))
  s[, ym_d := as.Date(paste0(ym, "-01"))]
  s[]
}
S_ALL <- .load_S()

# 120m rolling median/MAD z (rolling only — C1)
.rollz <- function(x, w = 120L) {
  n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    j <- max(1L, i - w); h <- x[j:i]           # 자기 포함(당월 S 는 이미 PIT-clean 관측)
    if (length(h) < 24L) next
    md <- stats::median(h); ma <- stats::mad(h)
    if (is.finite(ma) && ma > 0) o[i] <- (x[i] - md) / ma
  }
  o
}

.nw_fit <- function(y, s, lag = 3L) {
  fit <- stats::lm(y ~ s)
  V <- sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE, adjust = TRUE)
  ct <- lmtest::coeftest(fit, vcov. = V)
  list(b = unname(coef(fit)[2]), se = unname(ct[2, 2]), t = unname(ct[2, 3]),
       p = unname(ct[2, 4]), r2 = summary(fit)$r.squared, n = length(y),
       resid_sd = stats::sd(stats::resid(fit)))
}

#' laned_run — 단일 사전등록 스펙 실측
laned_run <- function(y_tag, y_var, s_series, win_start, win_end,
                      transform = c("level", "rollz120"), n_placebo = 200L, seed = 20260822L,
                      label = NULL) {
  transform <- match.arg(transform)
  Y <- .load_Y(y_tag)[ym_d >= as.Date(win_start) & ym_d <= as.Date(win_end)]
  S <- S_ALL[series == s_series]
  # ── PIT HARD: 컷오프가 홀딩월 캘린더 시작 이후면 stop
  assert_overlay_pit(S$cutoff, S$holding_month_start, label = paste0("LaneD:", s_series))
  Sx <- S[, .(ym_d, S_raw = S)]
  setorder(Sx, ym_d)
  Sx[, S_z := .rollz(S_raw)]
  d <- merge(Y[, .(ym_d, y = get(y_var), n_names, xs_sd, xs_mean)], Sx, by = "ym_d")
  d <- d[is.finite(y)]
  d[, s := if (transform == "level") S_raw else S_z]
  d <- d[is.finite(s)]
  if (nrow(d) < 36L) return(list(error = "n < 36", n = nrow(d)))
  setorder(d, ym_d)

  f <- .nw_fit(d$y, d$s)
  sd_s <- stats::sd(d$s); sd_y <- stats::sd(d$y)
  eff <- f$b * sd_s                       # 1-sd(S) 이동당 Y 변화
  eff_ci <- eff + c(-1.96, 1.96) * f$se * sd_s

  # 필요효과 (계열 실측 nw) — 결과량 자기 sd 기준 (bar_restates_t 퇴화 축 병기)
  re <- required_effect(n = f$n, t_threshold = 2.0, sd_monthly = sd_y, series = d$y)
  vp <- verdict_with_power(observed_t = f$t, observed_monthly = eff, n = f$n,
                           sd_monthly = sd_y, series = d$y)

  # ── F_D placebo: AR(1)-matched 무작위 조건변수 ────────────────────────────
  phi <- as.numeric(stats::acf(d$s, lag.max = 1, plot = FALSE)$acf[2])
  set.seed(seed)
  pb <- vapply(seq_len(n_placebo), function(i) {
    e <- stats::rnorm(f$n); z <- numeric(f$n); z[1] <- e[1]
    for (k in 2:f$n) z[k] <- phi * z[k - 1] + sqrt(max(1e-9, 1 - phi^2)) * e[k]
    z <- (z - mean(z)) / stats::sd(z) * sd_s
    ff <- .nw_fit(d$y, z)
    c(abs(ff$t), abs(ff$b * stats::sd(z)))
  }, numeric(2))
  pb_t95 <- stats::quantile(pb[1, ], 0.95); pb_e95 <- stats::quantile(pb[2, ], 0.95)

  # ── 양성 대조: 같은 S 에 대해 사전에 양성이 알려진 관계 (횡단면 산포) ─────
  #   변동성 군집으로 '경색 ↑ ⇒ 횡단면 산포 ↑' 는 기지 사실. 이 축이 죽으면 측정 프레임 결함.
  pc <- .nw_fit(d$xs_sd, d$s)

  # ── lag1 스트레스: S 를 한 달 더 과거로 (동월 누출 판별) ──────────────────
  d[, s_lag1 := shift(s, 1L)]
  dl <- d[is.finite(s_lag1)]
  fl <- .nw_fit(dl$y, dl$s_lag1)

  # ── 오염판(strict-PIT A/B 반대편): 홀딩월 '말' 관측을 쓰면 얼마나 부풀거나 바뀌나 ──
  Sc <- S_ALL[series == s_series][, .(ym_d, S_raw = S)]
  setorder(Sc, ym_d)
  Sc[, S_contam := shift(S_raw, -1L)]      # 다음 달 컷오프값 = 홀딩월 말 정보
  dc <- merge(d[, .(ym_d, y)], Sc[, .(ym_d, S_contam)], by = "ym_d")[is.finite(S_contam)]
  fc <- .nw_fit(dc$y, dc$S_contam)

  # ── F_E: leave-2026-out ──────────────────────────────────────────────────
  d26 <- d[ym_d < as.Date("2026-01-01")]
  f26 <- if (nrow(d26) >= 36L) .nw_fit(d26$y, d26$s) else NULL

  # ── 시대분해 (advisory, 판정축 아님) ─────────────────────────────────────
  k <- floor(nrow(d) / 3)
  eras <- lapply(1:3, function(i) {
    idx <- if (i < 3) ((i - 1) * k + 1):(i * k) else ((2 * k) + 1):nrow(d)
    if (length(idx) < 24L) return(NULL)
    e <- .nw_fit(d$y[idx], d$s[idx])
    list(period = paste(format(min(d$ym_d[idx]), "%Y-%m"), format(max(d$ym_d[idx]), "%Y-%m"), sep = ".."),
         b = e$b, t = e$t, n = e$n)
  })

  # ── 식별력 집중도: 회귀 leverage 가 몇 개 달에 몰려 있나 (에피소드 붕괴 진단) ──
  lev <- (d$s - mean(d$s))^2
  # D_G (rev2 advisory): C_top = 상위 3분위 S 달의 |b·(S−S̄)| 기여 비중. ④경계 참이면 > 1/3
  thr_ter <- stats::quantile(d$s, 2/3)
  contrib <- abs(d$s - mean(d$s))
  c_top <- sum(contrib[d$s >= thr_ter]) / sum(contrib)
  conc <- list(D_G_C_top_upper_tercile = c_top, D_G_baseline_uniform = 1/3,
               top1_share  = max(lev) / sum(lev),
               top5_share  = sum(sort(lev, decreasing = TRUE)[1:min(5, length(lev))]) / sum(lev),
               top10pct_share = sum(sort(lev, decreasing = TRUE)[1:max(1, floor(0.1 * length(lev)))]) / sum(lev),
               effective_months_kish = (sum(lev)^2) / sum(lev^2))

  list(label = label %||% paste(y_tag, y_var, s_series, transform, sep = "|"),
       spec = list(y_tag = y_tag, y_var = y_var, s_series = s_series, transform = transform,
                   window = paste(win_start, win_end, sep = ".."), n = f$n,
                   lag_days = S$lag_days[1], nw_lag = 3L),
       fit = list(b = f$b, se_nw = f$se, t_nw = f$t, p_nw = f$p, r2 = f$r2,
                  sd_S = sd_s, sd_Y = sd_y, resid_sd = f$resid_sd,
                  effect_per_1sd_S = eff, effect_ci95 = eff_ci,
                  effect_in_sdY_units = eff / sd_y),
       power = list(required_native = re$required_monthly,
                    required_in_sdY = re$required_monthly / sd_y,
                    required_annual_pct_if_return_units = re$required_annual * 100,
                    nw_inflation = re$nw_inflation, nw_source = re$nw_inflation_source,
                    verdict_with_power = vp$verdict, note = vp$note,
                    implied_t_threshold = vp$implied_t_threshold,
                    bar_restates_t = vp$bar_restates_t),
       F_D_placebo = list(phi_ar1 = phi, n_draw = n_placebo,
                          abs_t_obs = abs(f$t), abs_t_p95 = unname(pb_t95),
                          abs_eff_obs = abs(eff), abs_eff_p95 = unname(pb_e95),
                          passes = abs(f$t) > unname(pb_t95),
                          positive_control = list(target = "xs_sd (횡단면 산포)",
                                                  b = pc$b, t_nw = pc$t, r2 = pc$r2,
                                                  alive = abs(pc$t) >= 2.0)),
       pit_stress = list(lag1 = list(b = fl$b, t_nw = fl$t, n = fl$n),
                         contaminated_end_of_month = list(b = fc$b, t_nw = fc$t, n = fc$n)),
       F_E_leave2026out = if (is.null(f26)) NULL else list(b = f26$b, t_nw = f26$t, n = f26$n,
                                                           sign_flip = sign(f26$b) != sign(f$b)),
       era_decomposition_advisory = Filter(Negate(is.null), eras),
       identification_concentration = conc,
       series_data = d[, .(ym_d, y, s)])
}

`%||%` <- function(a, b) if (!is.null(a)) a else b
cat("[lane_d_regression.R] loaded — laned_run() ready\n")
