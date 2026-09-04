#!/usr/bin/env Rscript
#==============================================================================
# rolling_grade.R — 등급 지표를 **롤링 시계열**로 산출한다 (도훈 제안 2026-09-04)
#
# 왜: 전기간 1점은 오래된 사건에 지배된다. 실측(2026-09-04, 380건): 전기간 MDD 가 찍힌
#   시점의 중앙값이 **17.6년 전**이고, 56%가 10년 이상 전이다. Calmar 는 유일한 위험
#   게이트인데 그 분모가 대개 십수 년 전 사건이다.
#   사례 1403.8125: 전기간 Calmar 0.107(분모 = 2012-02 의 MDD 61.1%) vs
#   최근 롤링 36M Calmar 1.317(MDD 19.7%). 같은 전략이 어느 시대를 재느냐로 12배 갈린다.
#
# 왜 '최근창 1점'이 아니라 롤링인가: 창을 고르는 순간 그 선택이 판정을 만든다. 그리고
#   롤링이 아니면 못 보는 것이 있다 — 1403.8125 는 **2015년에도 문턱을 넘었다가 6년을
#   다시 죽어 있었다**. 지금 회복이 처음이 아니라는 사실은 단일 최근창에서 사라진다.
#   ⇒ 그래서 회복→재붕괴 이력(prior_recoveries)을 함께 싣는다. 구제하되 감추지 않는다.
#
# 경계: 이 파일은 **등급을 재계산하지 않는다.** 궤적을 기록하고, F 구제 후보인지만 말한다.
#   구제는 F → C 한 칸이고 그 위로는 못 간다. 판정 정본은 essence_score 다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.rg_null <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RG_FALLBACK <- list(
  enabled          = TRUE,
  window_months    = 36L,   # 롤링 창
  step_months      = 1L,
  recent_points    = 12L,   # "지금" 을 보는 최근 롤링점 수
  floor_sharpe     = 0.8,   # 절대 문턱 (essence A 의 비-알파 floor 와 같은 값)
  floor_cagr       = 0.16,
  floor_calmar     = 0.64,
  rescue_enabled   = TRUE,
  rescue_from      = "F",   # 이 등급에서만 구제
  rescue_to        = "C",   # 여기까지만 (그 위로 못 감)
  rescue_min_recent_pass = 0.5,  # 최근 롤링점의 절반 이상이 문턱 통과
  rescue_min_points      = 24L   # 롤링점이 이보다 적으면 판단 보류
)

rg_params <- function(root = Sys.getenv("QM_ROOT", getwd())) {
  p <- file.path(root, "06_Registry/rolling_grade.json")
  cfg <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL) else NULL
  out <- RG_FALLBACK
  if (!is.null(cfg)) for (k in names(RG_FALLBACK))
    if (!is.null(cfg[[k]]) && length(cfg[[k]])) out[[k]] <- cfg[[k]]
  out
}

.rg_monthly <- function(period_returns, benchmark_returns = NULL) {
  pr <- tryCatch(as.data.table(period_returns), error = function(e) NULL)
  if (is.null(pr) || !all(c("date", "ret_net") %in% names(pr))) return(NULL)
  pr <- pr[is.finite(ret_net), .(date = as.Date(date), ret_net)]
  if (!is.null(benchmark_returns)) {
    br <- tryCatch(as.data.table(benchmark_returns), error = function(e) NULL)
    if (!is.null(br) && all(c("date", "benchmark_ret") %in% names(br))) {
      br <- br[is.finite(benchmark_ret), .(date = as.Date(date), benchmark_ret)]
      pr <- merge(pr, br, by = "date")
    }
  }
  if (!nrow(pr)) return(NULL)
  pr[, ym := format(date, "%Y-%m")]
  if ("benchmark_ret" %in% names(pr))
    pr[, .(s = prod(1 + ret_net) - 1, k = prod(1 + benchmark_ret) - 1), by = ym][order(ym)]
  else pr[, .(s = prod(1 + ret_net) - 1), by = ym][order(ym)]
}

#' 회복→재붕괴 이력 — 문턱을 넘었다가 다시 내려간 구간을 센다
.rg_history <- function(pass) {
  r <- rle(as.logical(pass))
  idx <- which(r$values)
  if (!length(idx)) return(list(prior_recoveries = 0L, run_lengths = integer(0), current_run = 0L))
  last_is_open <- idx[length(idx)] == length(r$values)          # 마지막 run 이 진행 중
  closed <- if (last_is_open) idx[-length(idx)] else idx
  list(prior_recoveries = length(closed),                       # 되돌아간 회복 횟수
       run_lengths = as.integer(r$lengths[idx]),
       current_run = if (last_is_open) as.integer(r$lengths[idx[length(idx)]]) else 0L)
}

#' 롤링 등급 지표
rg_rolling <- function(period_returns, benchmark_returns = NULL, params = rg_params(),
                       keep_series = FALSE) {
  na <- function(why) list(status = why, n_points = 0L, pass_life = NA_real_,
                           pass_recent = NA_real_, current = NULL, history = NULL)
  if (!isTRUE(params$enabled)) return(na("disabled"))
  m <- .rg_monthly(period_returns, benchmark_returns)
  if (is.null(m)) return(na("no_series"))
  W <- as.integer(params$window_months); st <- max(1L, as.integer(params$step_months))
  n <- nrow(m)
  if (n < W) return(na("too_short"))
  starts <- seq.int(1L, n - W + 1L, by = st)
  res <- vector("list", length(starts))
  for (j in seq_along(starts)) {
    i <- starts[j]; v <- m$s[i:(i + W - 1L)]
    if (!length(v) || !all(is.finite(v))) { res[[j]] <- NULL; next }
    nav <- cumprod(1 + v); mdd <- max(1 - nav / cummax(nav))
    cg  <- prod(1 + v)^(12 / W) - 1
    sdv <- stats::sd(v)
    res[[j]] <- list(ym = m$ym[i + W - 1L],
                     sr = if (sdv > 0) mean(v)/sdv*sqrt(12) else NA_real_,
                     cagr = cg, mdd = mdd,
                     cal = if (is.finite(mdd) && mdd > 1e-6) cg/mdd else NA_real_)
  }
  R <- rbindlist(Filter(Negate(is.null), res))
  if (!nrow(R)) return(na("no_points"))
  R[, pass := is.finite(sr) & sr >= params$floor_sharpe &
              is.finite(cagr) & cagr >= params$floor_cagr &
              is.finite(cal) & cal >= params$floor_calmar]
  k <- min(nrow(R), as.integer(params$recent_points))
  cur <- R[nrow(R)]
  out <- list(status = "ok", n_points = nrow(R), window_months = W,
              pass_life = mean(R$pass), pass_recent = mean(R$pass[(nrow(R)-k+1L):nrow(R)]),
              recent_points = k,
              current = list(ym = cur$ym, sharpe = cur$sr, cagr = cur$cagr,
                             mdd = cur$mdd, calmar = cur$cal, pass = cur$pass),
              history = .rg_history(R$pass),
              span = c(R$ym[1], R$ym[nrow(R)]))
  if (isTRUE(keep_series)) out$series <- R
  out
}

#' F 구제 판단 — 구제 여부와 **왜** 를 함께 낸다. 등급을 직접 바꾸지 않는다.
rg_rescue <- function(grade, roll, params = rg_params()) {
  no <- function(why) list(rescued = FALSE, new_grade = grade, label = NA_character_, reason = why)
  if (!isTRUE(params$rescue_enabled)) return(no("rescue_disabled"))
  if (is.null(roll) || !identical(roll$status, "ok")) return(no("no_rolling"))
  if (is.na(grade) || !identical(as.character(grade), as.character(params$rescue_from)))
    return(no("grade_not_eligible"))
  if (roll$n_points < as.integer(params$rescue_min_points))
    return(no(sprintf("롤링점 %d < %d — 판단 보류", roll$n_points, params$rescue_min_points)))
  if (!is.finite(roll$pass_recent) || roll$pass_recent < params$rescue_min_recent_pass)
    return(no(sprintf("최근 문턱 충족 %.2f < %.2f", roll$pass_recent %||% NA,
                      params$rescue_min_recent_pass)))
  pr <- (roll$history$prior_recoveries %||% 0L)
  list(rescued = TRUE, new_grade = as.character(params$rescue_to),
       label = "recent_regime",
       reason = sprintf(paste0("전기간 %s 이나 롤링 %d개월 기준 최근 %d점 중 %.0f%% 가 절대문턱 통과",
                               " (현재 SR %.2f · CAGR %.1f%% · MDD %.1f%% · Calmar %.2f). ",
                               "생애 충족 %.0f%%. ★과거 회복→재붕괴 %d회%s"),
                       grade, roll$window_months, roll$recent_points, 100*roll$pass_recent,
                       roll$current$sharpe %||% NA_real_, 100*(roll$current$cagr %||% NA_real_),
                       100*(roll$current$mdd %||% NA_real_), roll$current$calmar %||% NA_real_,
                       100*roll$pass_life, pr,
                       if (pr > 0) " — 이번 회복이 처음이 아니다" else ""))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
