#==============================================================================
# msm_asof.R — MSM(Calvet-Fisher binomial · k̄ = 10) 위기확률의 as-of 판 — 운영 라이브러리
#   (PIT C1 수리 · 결정 PIT-C1-MSM-PARAMS 안 A · 도훈 2026-10-15 'A로 교체')
#
# 왜: 운영 생산자 04_Research/regime_comparison/msm_update.R 의 Hamilton 필터는 인과(전방)지만 모수 4개(m0 · σ · b · γ1)가
#   전기간 MLE 핀(K_Fractal_Master 2026-01-18 · 표본 1990-01~2026-01)이라 2026-01-18 이전 날짜의 값이 전부 C1 이다
#   (감사 04_Research/01_reports/msm_c1_chain_audit_20261010 §1 · §6). 지연(lag)으로는 풀리지 않는다.
# 수리: 같은 모형 · 같은 필터 · 같은 디민(expanding) · 같은 목적함수(MSM.R estimate_msm_windows 의 음의 우도 · 벌점 경계 · 3 초기점)를
#   매년 마지막 한국 거래일 r_k 에 Date ≤ r_k 자료로만 재적합하고, θ_k 를 (r_k, r_{k+1}] 에 전방 적용한다(결정문 · 감사 §6-2).
#   r_k 당일 값은 θ_{k−1} 로 계산한다(그날 종가로 적합한 θ_k 를 그날 값에 쓰지 않는다) — 원형 [r_k, r_{k+1}) 에서 하루 민 것.
#   위기 상태 = s > σ_k · 필터만(평활 금지) · 첫 적합 2003 년 말(그 이전 날짜는 값 없음).
# 원형: 04_Research/l2_role_rotation/build_msm_asof.R(2026-10-10 · PC1 1.6e-14 · PC3 · PC4 통과) — 추정(변환 모수 NM 재시작 + BFGS 연마 —
#   운영 NM maxit 1000 은 PC3 에서 핀보다 나쁜 점에서 멈췄다) · 식별 가드를 그대로 옮겼다.
# 식별 가드(사전 고정 2026-10-10 · 어떤 판별력 지표도 보기 전): γ1 < 1e-5 또는 σ/sd(창) ∉ [0.8, 1.25] = 퇴화
#   → 3 초기점 최적점 중 비퇴화 최고 우도 · 전부 퇴화면 직전 유효 θ 승계(과거 정보 = 인과).
# 원장: 06_Registry/msm_param_schedule.json — append-only(과거 θ_k 재기록 · 날짜 역행 추가 거부). 행마다 벤치 해시(그 적합이 본 자료).
# 모형: Calvet & Fisher (2004) "How to Forecast Long-Run Volatility: Regime Switching and the Estimation of Multifractal Processes",
#   J. Financial Econometrics 2(1):49–83 https://doi.org/10.1093/jjfinec/nbh003 — 예측 평가는 표본 앞부분으로 추정한 모수를 쓴다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

MSMA_ESTIMATOR <- "asof_yearly:v1"
MSMA_K_BAR <- 10L                                     # msm_update.R extract_msm_path(k_bar = 10L)
MSMA_FIRST_YEAR <- 2003L                              # 결정문 '첫 적합 2003-12'
MSMA_GUARD <- list(gamma_min = 1e-5, sd_ratio = c(0.8, 1.25))   # 사전 고정(2026-10-10)

.msma_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))) {
    if (!is.null(p) && nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(gsub("\\\\", "/", p))
  }
  stop("[msm_asof] 프로젝트 루트 해석 실패(QM_ROOT)")
}
.MSMA <- new.env(parent = emptyenv())

## 고속 커널(Kronecker 분해 · 운영 조밀 커널과 같은 재귀 · 하한 1e-10 · 위기 집합) — 프로세스당 1회 컴파일
msma_kernel <- function(root = NULL) {
  if (is.null(.MSMA$fast)) {
    e <- new.env()
    Rcpp::sourceCpp(file.path(.msma_root(root), "02_Infrastructure/regime/msm_fast_kernel.cpp"), env = e, verbose = FALSE)
    .MSMA$fast <- e
  }
  .MSMA$fast
}
## 운영 조밀 커널(msm_update.R 안 C++ 문자열을 텍스트로 읽어 컴파일 — msm_update.R 은 source 하지 않는다: source 하면 운영 캐시를 덮어쓴다) · PC1 전용
msma_prod_kernel <- function(root = NULL) {
  src <- readLines(file.path(.msma_root(root), "04_Research/regime_comparison/msm_update.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^\\s*msm_cpp_code <- '", src); i1 <- which(trimws(src) == "'"); i1 <- i1[i1 > i0][1]
  if (length(i0) != 1L || !is.finite(i1)) stop("[msm_asof] 운영 커널 문자열 판독 실패")
  e <- new.env()
  Rcpp::sourceCpp(code = paste(c(sub("^\\s*msm_cpp_code <- '", "", src[i0]), src[(i0 + 1L):(i1 - 1L)]), collapse = "\n"), env = e, verbose = FALSE)
  e
}

## 정본 벤치(.cache/benchmark.parquet) · 로그수익 + expanding 과거만 디민(msm_update.R §3-4 · 2026-08-13 PIT 수리판)
msma_load_bm <- function(root = NULL) {
  b <- as.data.table(arrow::read_parquet(file.path(.msma_root(root), ".cache/benchmark.parquet")))
  b[, Date := as.Date(Date)]; setorder(b, Date)
  b[!is.na(BM_Close) & BM_Close > 0, .(Date, BM_Close)]
}
msma_returns <- function(bm) {
  r <- c(NA_real_, diff(log(bm$BM_Close))); d <- bm$Date; p <- bm$BM_Close
  r <- r[-1]; d <- d[-1]; p <- p[-1]
  cs_n <- cumsum(!is.na(r)); cs_s <- cumsum(ifelse(is.na(r), 0, r))
  data.table(Date = d, Price = p, r_raw = r, r = r - cs_s / pmax(cs_n, 1L))
}
## 벤치 해시 — 적합이 본 자료(Date ≤ data_end 의 Date · BM_Close)의 sha256(뒤 수정 탐지용 · 재적합 근거 아님)
msma_bench_sha <- function(bm, data_end) {
  x <- bm[Date <= as.Date(data_end)]
  as.character(openssl::sha256(paste(format(x$Date), sprintf("%.10f", x$BM_Close), sep = ",", collapse = "\n")))
}
## 완료된 해의 마지막 거래일 — 해 y 는 벤치에 y+1 년 자료가 있을 때만 완료(연말 휴장일에 미리 적합하지 않는다)
msma_year_ends <- function(dates, from_year = MSMA_FIRST_YEAR) {
  d <- sort(unique(as.Date(dates))); y <- as.integer(format(d, "%Y"))
  YE <- data.table(y = y, d = d)[, .(rf = max(d)), by = y]
  YE[y >= from_year & y < max(as.integer(format(d, "%Y")))][order(y)]
}

## 추정(원형 fit_msm 그대로) — 변환 모수(R^4) NM 재시작(개선 < 1e-7 이면 수렴 · 최대 8회) + BFGS 연마 · 3 초기점은 자료 무관(+ 창 sd)
msma_fit <- function(ret, k_bar = MSMA_K_BAR, root = NULL) {
  e <- msma_kernel(root)
  nll <- function(par) e$msm_fast_filter(ret, k_bar, par[1], par[2], par[3], par[4], FALSE)$negloglik
  inb <- function(par) par[1] > 1.001 && par[1] < 1.999 && par[2] > 0 && par[3] > 1.0 && par[4] > 0 && par[4] < 0.999
  to_th <- function(p) c(qlogis((p[1] - 1.001) / 0.998), log(p[2]), log(p[3] - 1), qlogis(p[4] / 0.999))
  to_p <- function(th) c(1.001 + 0.998 * plogis(th[1]), exp(th[2]), 1 + exp(th[3]), 0.999 * plogis(th[4]))
  obj_th <- function(th) { p <- to_p(th); if (!all(is.finite(p)) || !inb(p)) return(1e10); nll(p) }
  grids <- list(c(m0 = 1.3, sigma = sd(ret), b = 2.0, gamma_1 = 0.05),
                c(m0 = 1.4, sigma = sd(ret), b = 3.0, gamma_1 = 0.01),
                c(m0 = 1.5, sigma = sd(ret), b = 5.0, gamma_1 = 0.10))
  t0 <- Sys.time()
  one <- function(gp) {
    th <- to_th(gp); v <- obj_th(th); n_ev <- 0L
    for (rs in 1:8) {
      o <- optim(th, obj_th, method = "Nelder-Mead", control = list(maxit = 3000, reltol = 1e-12))
      n_ev <- n_ev + o$counts[1]
      if (v - o$value < 1e-7) { th <- if (o$value < v) o$par else th; v <- min(v, o$value); break }
      th <- o$par; v <- o$value
    }
    bf <- tryCatch(optim(th, obj_th, method = "BFGS", control = list(maxit = 500, reltol = 1e-14)), error = function(err) NULL)
    if (!is.null(bf) && bf$value < v) { th <- bf$par; v <- bf$value }
    list(par = stats::setNames(to_p(th), c("m0", "sigma", "b", "gamma_1")), value = v, evals = n_ev)
  }
  res <- lapply(grids, one)
  list(inits = lapply(res, function(z) list(par = as.list(z$par), negloglik = z$value)),
       secs = as.numeric(difftime(Sys.time(), t0, units = "secs")), evals = sum(vapply(res, function(z) as.numeric(z$evals), 1)))
}
msma_is_degen <- function(par, sdw, guard = MSMA_GUARD) {
  r <- as.numeric(par[["sigma"]]) / sdw
  as.numeric(par[["gamma_1"]]) < guard$gamma_min || r < guard$sd_ratio[1] || r > guard$sd_ratio[2]
}
## 식별 가드 — fit = msma_fit 결과 · prev_theta = 직전 유효 θ(NULL 가능). 반환 = theta · guard_action · negloglik · raw_mle · init_degenerate
msma_guard <- function(fit, sdw, prev_theta = NULL) {
  v <- vapply(fit$inits, function(z) z$negloglik, numeric(1)); dg <- vapply(fit$inits, function(z) msma_is_degen(z$par, sdw), logical(1))
  raw <- fit$inits[[which.min(v)]]
  if (any(!dg)) {
    j <- which(!dg)[which.min(v[!dg])]
    list(theta = fit$inits[[j]]$par, negloglik = v[j], guard_action = if (j == which.min(v)) "mle" else "best_nondegenerate",
         raw_mle = raw, init_degenerate = dg)
  } else {
    if (is.null(prev_theta)) stop("[msm_asof] 첫 적합이 전부 퇴화 — 승계할 직전 유효 θ 가 없다(사전 고정 규칙 밖 · 중단)")
    list(theta = prev_theta, negloglik = NA_real_, guard_action = "carry_forward_previous", raw_mle = raw, init_degenerate = dg)
  }
}

## ── 모수 일정 원장(append-only) ───────────────────────────────────────────────
msma_ledger_path <- function(root = NULL) file.path(.msma_root(root), "06_Registry/msm_param_schedule.json")
msma_ledger_read <- function(path) {
  if (!file.exists(path)) return(list(schema = "msm_param_schedule_v1", estimator = MSMA_ESTIMATOR, k_bar = MSMA_K_BAR, rows = list()))
  fromJSON(path, simplifyVector = FALSE)
}
msma_ledger_append <- function(path, row) {
  L <- msma_ledger_read(path)
  if (!identical(L$estimator, MSMA_ESTIMATOR)) stop("[msm_asof] 원장 추정기 ≠ ", MSMA_ESTIMATOR, ": ", L$estimator)
  have <- vapply(L$rows, function(z) as.character(z$fit_date), character(1))
  if (row$fit_date %in% have) stop("[msm_asof] append-only — fit_date ", row$fit_date, " 는 이미 원장에 있다(과거 θ 재기록 거부)")
  if (length(have) && as.Date(row$fit_date) <= max(as.Date(have))) stop("[msm_asof] append-only — fit_date ", row$fit_date, " ≤ 원장 마지막 ", max(have), "(역행 추가 거부)")
  L$rows[[length(L$rows) + 1L]] <- row
  L$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  writeLines(toJSON(L, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(L)
}
## 원장 → 일정표(fit_date 순 · θ)
msma_schedule <- function(L) {
  if (!length(L$rows)) return(data.table(fit_date = as.Date(character(0))))
  S <- rbindlist(lapply(L$rows, function(z) data.table(fit_date = as.Date(z$fit_date), m0 = as.numeric(z$theta$m0), sigma = as.numeric(z$theta$sigma),
                                                       b = as.numeric(z$theta$b), gamma_1 = as.numeric(z$theta$gamma_1), guard_action = as.character(z$guard_action))))
  S[order(fit_date)]
}

## ── 일별 경로 — θ_k 를 (r_k, r_{k+1}] 에 적용(마지막 블록은 (r_K, 자료 끝]) · 블록마다 처음부터 블록 끝까지 1회 전방 필터 ──
msma_path <- function(RT, S, k_bar = MSMA_K_BAR, root = NULL) {
  if (!nrow(S)) return(data.table(Date = as.Date(character(0)), Price = numeric(0), Vol_Est = numeric(0), Crisis_Prob = numeric(0),
                                  msm_fit_date = as.Date(character(0)), guard_action = character(0)))
  e <- msma_kernel(root); S <- S[order(fit_date)]
  out <- vector("list", nrow(S))
  for (k in seq_len(nrow(S))) {
    lo <- S$fit_date[k]; hi <- if (k < nrow(S)) S$fit_date[k + 1L] else max(RT$Date)
    keep <- which(RT$Date > lo & RT$Date <= hi)
    if (!length(keep)) next
    end_i <- max(keep)
    p <- e$msm_fast_filter(RT$r[1:end_i], k_bar, S$m0[k], S$sigma[k], S$b[k], S$gamma_1[k], TRUE)
    out[[k]] <- data.table(Date = RT$Date[keep], Price = RT$Price[keep], Vol_Est = p$vol[keep], Crisis_Prob = p$crisis_prob[keep],
                           msm_fit_date = S$fit_date[k], guard_action = S$guard_action[k])
  }
  P <- rbindlist(out)
  if (anyDuplicated(P$Date) || any(P$msm_fit_date >= P$Date)) stop("[msm_asof] 경로 무결성 실패(중복 날짜 또는 적합일 ≥ 값 날짜)")
  P
}

## ── 생산자 — 원장에 없는 완료 연도를 적합해 붙이고(순서대로 · 가드 승계) 일별 경로를 쓴다 ─────────────
##   cores > 1 이면 빠진 해들의 적합만 병렬(적합끼리 독립 · 가드는 뒤에서 순서대로). out = 일별 캐시(NULL 이면 쓰지 않음)
msma_update <- function(root = NULL, ledger = msma_ledger_path(root), out = file.path(.msma_root(root), ".cache/msm_asof_daily.parquet"),
                        cores = 1L, bm = NULL, verbose = TRUE) {
  root <- .msma_root(root)
  bm <- bm %||% msma_load_bm(root); RT <- msma_returns(bm)
  L <- msma_ledger_read(ledger); have <- vapply(L$rows, function(z) as.character(z$fit_date), character(1))
  YE <- msma_year_ends(RT$Date)
  todo <- YE[!(format(rf) %in% have)]
  if (length(have) && nrow(todo) && min(todo$rf) < max(as.Date(have)))
    stop("[msm_asof] 원장 사이에 빠진 해가 있다(", paste(format(todo$rf[todo$rf < max(as.Date(have))]), collapse = ","), ") — append-only 라 끼워 넣지 않는다")
  if (nrow(todo)) {
    jobs <- lapply(seq_len(nrow(todo)), function(i) list(rf = todo$rf[i]))
    fitj <- function(j) { x <- RT[Date <= j$rf]; f <- msma_fit(x$r, root = root); c(j, list(n_obs = nrow(x), first = format(min(x$Date)), sdw = sd(x$r), fit = f)) }
    fits <- if (cores > 1L && length(jobs) > 1L) {
      cl <- parallel::makeCluster(min(cores, length(jobs))); on.exit(parallel::stopCluster(cl), add = TRUE)
      parallel::clusterExport(cl, c("RT", "root"), envir = environment())
      parallel::clusterCall(cl, function(rt) { Sys.setenv(QM_ROOT = rt); source(file.path(rt, "02_Infrastructure/regime/msm_asof.R")); NULL }, root)
      parallel::parLapply(cl, jobs, fitj)
    } else lapply(jobs, fitj)
    prev <- if (length(L$rows)) L$rows[[length(L$rows)]]$theta else NULL
    for (f in fits) {
      gd <- msma_guard(f$fit, f$sdw, prev)
      row <- list(fit_date = format(f$rf), data_end = format(f$rf), first_date = f$first, n_obs = f$n_obs, estimator = MSMA_ESTIMATOR, k_bar = MSMA_K_BAR,
                  theta = gd$theta, negloglik = gd$negloglik, guard_action = gd$guard_action, guard_rule = MSMA_GUARD,
                  raw_mle = gd$raw_mle, inits = f$fit$inits, init_degenerate = as.list(gd$init_degenerate), window_sd = f$sdw,
                  bench_sha256 = msma_bench_sha(bm, f$rf), fit_secs = f$fit$secs, fit_evals = f$fit$evals,
                  recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
      msma_ledger_append(ledger, row); prev <- gd$theta
      if (verbose) cat(sprintf("[msm_asof] 적합 %s · n %d · %s · m0 %.4f σ %.5f b %.3f γ1 %.6f · %.0f초\n", row$fit_date, row$n_obs, row$guard_action,
                               gd$theta$m0, gd$theta$sigma, gd$theta$b, gd$theta$gamma_1, f$fit$secs))
    }
    L <- msma_ledger_read(ledger)
  }
  S <- msma_schedule(L)
  revised <- Filter(Negate(is.null), lapply(L$rows, function(z) if (!identical(z$bench_sha256, msma_bench_sha(bm, z$data_end))) z$fit_date else NULL))
  P <- msma_path(RT, S, root = root)
  if (!is.null(out)) {
    setattr(P, "msm_estimator", MSMA_ESTIMATOR)
    tb <- arrow::arrow_table(P)
    tb$metadata$msm_estimator <- MSMA_ESTIMATOR
    tb$metadata$msm_ledger_sha256 <- as.character(openssl::sha256(file(ledger)))
    tb$metadata$msm_bench_revised_since_fit <- paste(unlist(revised), collapse = ",")
    tmp <- paste0(out, ".tmp_", Sys.getpid()); arrow::write_parquet(tb, tmp)
    if (!file.rename(tmp, out)) { file.copy(tmp, out, overwrite = TRUE); unlink(tmp) }
  }
  if (verbose) cat(sprintf("[msm_asof] 원장 %d행(%s~%s) · 경로 %d일(%s~%s) · 새 적합 %d · 벤치 수정 감지 %d\n", nrow(S), format(min(S$fit_date)), format(max(S$fit_date)),
                           nrow(P), format(min(P$Date)), format(max(P$Date)), nrow(todo), length(revised)))
  invisible(list(schedule = S, path = P, new_fits = nrow(todo), bench_revised = unlist(revised)))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
