#!/usr/bin/env Rscript
# test_rf_cdar_construct.R — 낙폭 목적 구성(rf_cdar_construct.R) 합성 자료 시험 (2026-11-10 · 레인 E3)
#   ① 평가기(손계산 경로 · α 극한) ② LP 목적값 = 독립 평가기 재도출 ③ 최적성 표본 점검(무작위 2,000개)
#   ④ 등가 문제 대조 — 현행 qepm:CDaR_LP(advanced_weights.R::calc_cdar_weights, 밀집 판)와 같은 CDaR
#   ⑤ max_mu 방식 — 제약 충족 · EW 보다 μ 높음 · Σw ≤ 1 현금판 ⑥ ≤ 25종(후보 80 → 가지치기)
#   ⑦ 회전 인지 항 ⑧ 비중 어댑터(운영 래퍼 wrap_adapter · 등재 검증기 verify_adapter) ⑨ 소요 시간 표(실측)
.root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_cdar_construct.R"); r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)]); if (length(f)) { d <- dirname(gsub("\\\\", "/", f[1])); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } } }
  if (is.null(r)) stop("root 미발견"); r
})
Sys.setenv(QM_ROOT = .root)
suppressWarnings(suppressMessages(source(file.path(.root, "02_Infrastructure/reinforcement/rf_cdar_construct.R"))))
cfg <- rcd_config(file.path(.root, "02_Infrastructure/reinforcement/rf_cdar_construct.json"))
P <- 0L; Fl <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { P <<- P + 1L; cat("  [PASS]", msg, "\n") } else { Fl <<- Fl + 1L; cat("  [FAIL]", msg, "\n") } }
TIME_ONLY <- identical(Sys.getenv("RCD_TIME_GRID"), "1")

world <- function(Tn, n, seed = 1L) {
  set.seed(seed)
  f <- stats::rnorm(Tn, 0.0003, 0.012)
  R <- outer(f, stats::runif(n, 0.6, 1.4)) + matrix(stats::rnorm(Tn * n, 0.0002, 0.015), Tn)
  colnames(R) <- sprintf("A%03d", seq_len(n)); R
}

cat("[1] 평가기\n")
rp <- c(0.10, -0.05, -0.05, 0.20, -0.10)            # y = .10 .05 0 .20 .10 · 고점 = .10 .10 .10 .20 .20 → D = 0 .05 .10 0 .10
ck(isTRUE(all.equal(rcd_drawdowns(rp), c(0, 0.05, 0.10, 0, 0.10))), "비복리 낙폭 손계산 대조")
ck(abs(rcd_cdar(rp, 0) - mean(c(0, 0.05, 0.10, 0, 0.10))) < 1e-12, "α = 0 → 평균 낙폭")
ck(abs(rcd_cdar(rp, 1 - 1 / 5) - 0.10) < 1e-12, "α = 1 − 1/T → 최대 낙폭")
ck(abs(rcd_cdar(c(-0.2, 0.1), 0.5) - 0.2) < 1e-12, "y_0 = 0 고점 포함(첫날 손실도 낙폭)")

cat("[2] LP 목적값 재도출 · [3] 최적성 표본 점검\n")
R <- world(252, 25)
s <- rcd_solve(R, cfg, mode = "min_cdar")
ck(s$ok && abs(s$lp_cdar - s$cdar) < 1e-8, sprintf("LP 목적 %.8f = 평가기 %.8f", s$lp_cdar, s$cdar))
ck(abs(sum(s$w) - 1) < 1e-9 && all(s$w >= 0), "Σw = 1 · w ≥ 0")
set.seed(2); Wr <- matrix(stats::rexp(2000 * 25), 2000); Wr <- Wr / rowSums(Wr)
cr <- apply(Wr, 1, function(w) rcd_cdar(R %*% w, cfg$alpha))
ck(min(cr) >= s$cdar - 1e-10, sprintf("무작위 2,000개 최소 CDaR %.5f ≥ LP %.5f", min(cr), s$cdar))

cat("[4] 등가 문제 대조 — 현행 qepm:CDaR_LP(밀집 판)\n")
ae <- new.env(parent = globalenv())
suppressWarnings(suppressMessages(sys.source(file.path(.root, "02_Infrastructure/portfolio/advanced_weights.R"), envir = ae)))
library(data.table)
rdt <- data.table(Date = rep(as.Date("2024-01-01") + seq_len(252), 25), Ticker = rep(colnames(R), each = 252), Ret = as.numeric(R))
t0 <- proc.time()[[3]]
w_old <- utils::capture.output(wo <- get("calc_cdar_weights", ae)(colnames(R), rdt, alpha = cfg$alpha, n_days = 252, max_w = 1))
t_old <- proc.time()[[3]] - t0
c_old <- rcd_cdar(R %*% wo[colnames(R)], cfg$alpha)
ck(abs(c_old - s$cdar) < 1e-6, sprintf("현행 밀집 판 CDaR %.8f = 새 희소 판 %.8f (현행 솔버 %s · %.2fs · 새 %.2fs)", c_old, s$cdar,
                                       ae$.CDAR_LAST$solver %||% "?", t_old, s$sec))

cat("[5] max_mu 방식 · 현금판\n")
set.seed(3); mu <- stats::setNames(stats::rnorm(25), colnames(R))
o <- rcd_construct(R, cfg, mu = mu)
ew <- rep(1 / 25, 25); nu_ew <- rcd_cdar(R %*% ew, cfg$alpha)
ck(identical(o$mode, "max_mu_cdar_cap") && abs(o$nu - nu_ew) < 1e-12, "ν = 같은 후보 EW 의 CDaR × 1")
ck(o$cdar <= o$nu + 1e-8, sprintf("CDaR %.5f ≤ ν %.5f", o$cdar, o$nu))
ck(sum(o$w * mu) >= sum(ew * mu) - 1e-12, sprintf("μᵀw %.4f ≥ EW %.4f (EW 가 가능해)", sum(o$w * mu), sum(ew * mu)))
ck(abs(sum(o$w) - 1) < 1e-9 && o$cash < 1e-9, "eq 예산 → 현금 0")
cfg_h <- cfg; cfg_h$nu_kappa <- 0.5
oh <- rcd_construct(R, cfg_h, mu = mu, budget = "le")
ck(oh$cdar <= oh$nu + 1e-8 && sum(oh$w) <= 1 + 1e-9 && oh$cash > 1e-6, sprintf("Σw ≤ 1 · κ 0.5 → 현금 %.3f · CDaR %.5f ≤ ν %.5f", oh$cash, oh$cdar, oh$nu))
ck(inherits(try(rcd_lp(R, cfg$alpha, mode = "min_cdar", budget = "le"), silent = TRUE), "try-error"), "min_cdar + Σw ≤ 1 은 퇴화(w = 0) — 거부")
cat(sprintf("  [INFO] max_mu 해 집중도: 활성 %d · 최대 비중 %.3f · 유효 종목 수 %.2f (헌장 실패 형태 '집중' — 측정 때 기록)\n", o$n_active, max(o$w), o$effn))
cat(sprintf("  [INFO] 행동 카드 판(복리) CDaR: min_cdar %.4f · EW %.4f\n", rcd_cdar_card(R %*% s$w, cfg$alpha), rcd_cdar_card(R %*% ew, cfg$alpha)))

cat("[6] ≤ 25종 — 후보 80 · pool 50\n")
R80 <- world(252, 80, seed = 4); set.seed(5); mu80 <- stats::setNames(stats::rnorm(80), colnames(R80))
o80 <- rcd_construct(R80, cfg, mode = "min_cdar", mu = mu80)
top50 <- names(sort(mu80, decreasing = TRUE))[1:50]
ck(o80$n_active <= cfg$max_names && all(o80$w[setdiff(names(mu80), top50)] == 0), sprintf("활성 %d ≤ 25 · 후보 밖 비중 0 · 라운드 %d", o80$n_active, o80$rounds))
cfg_s <- cfg; cfg_s$max_names <- 3
o3 <- rcd_construct(R80, cfg_s, mode = "min_cdar", mu = mu80)
ck(o3$n_active <= 3 && o3$rounds >= 2, sprintf("max_names 3 강제 → 가지치기 발동(라운드 %d · 활성 %d)", o3$rounds, o3$n_active))

cat("[7] 회전 인지 항\n")
wp <- stats::setNames(rep(1 / 25, 25), colnames(R))
tov <- vapply(c(0, 0.001, 0.01, 1), function(l) sum(abs(rcd_solve(R, cfg, mode = "min_cdar", w_prev = wp, tc_lambda = l)$w - wp)), numeric(1))
ck(all(diff(tov) <= 1e-9), sprintf("λ ↑ → 회전 ↓ (%s)", paste(sprintf("%.3f", tov), collapse = " ≥ ")))
ck(tov[4] < 1e-8, "큰 λ → 직전 비중 유지")

cat("[8] 비중 어댑터 — wrap_adapter · verify_adapter\n")
suppressWarnings(suppressMessages({ source(file.path(.root, "02_Infrastructure/portfolio/strategy_tilt_weights.R")); source(file.path(.root, "02_Infrastructure/methods/method_registry.R")) }))
ad <- new.env(); sys.source(file.path(.root, "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R"), envir = ad)
wa <- wrap_adapter(get("method_weights", ad), "CDaRCapCUZ2005", ub = 1)
ctx <- list(assets = colnames(R), R = R, mu = mu, Sigma = stats::cov(R), ub = 1, lookback_days = 252, decision_date = as.Date("2024-01-02"))
lg <- utils::capture.output(wq <- wa(ctx))
ck(max(abs(wq - o$w)) < 1e-9 && !any(grepl("EW 폴백", lg)) && any(grepl("\\[cdar_cuz\\]", lg)), "래퍼 경유 = 순수 함수 해 · 폴백 없음 · 진단 줄")
ctx_nomu <- ctx; ctx_nomu$mu <- NULL
lg2 <- utils::capture.output(wq2 <- wa(ctx_nomu))
ck(any(grepl("mode=min_cdar", lg2)) && abs(rcd_cdar(R %*% wq2, cfg$alpha) - s$cdar) < 1e-8, "μ 없음 → min_cdar(현행 끝점과 같은 해)")
if (!TIME_ONLY) {
  rm_env <- new.env(); suppressWarnings(suppressMessages(sys.source(file.path(.root, "02_Infrastructure/methods/register_method.R"), envir = rm_env)))
  if (exists("rm_fixture", envir = rm_env)) { .ofx <- get("rm_fixture", rm_env); assign("rm_fixture", function(n_assets = 25L, n_obs = 260L, seed = 20260813L) .ofx(25L, n_obs, seed), envir = rm_env) }
  vlog <- utils::capture.output(v <- get("verify_adapter", rm_env)(file.path(.root, "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R"), "weight", "CDaRCapCUZ2005", root = .root))
  ck(isTRUE(v$ok), sprintf("verify_adapter(25종 fixture) ok — %s", paste(names(v$checks), unlist(lapply(v$checks, as.character)), sep = "=", collapse = " · ")))
}

cat("[9] 소요 시간 표(실측 · 이 기계 · lpSolve 단체법 희소 입력)\n")
grid <- if (TIME_ONLY) expand.grid(T = c(252, 504, 1260), n = c(25, 50, 100)) else expand.grid(T = c(252, 504), n = c(25, 50))
tab <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  Rg <- world(grid$T[i], grid$n[i], seed = 10 + i); set.seed(i); mg <- stats::setNames(stats::rnorm(grid$n[i]), colnames(Rg))
  a1 <- rcd_construct(Rg, cfg, mode = "min_cdar"); a2 <- rcd_construct(Rg, cfg, mu = mg)
  data.frame(T = grid$T[i], n = grid$n[i], nnz = a1$nnz, min_cdar_s = round(a1$sec, 3), max_mu_s = round(a2$sec, 3),
             active_min = a1$n_active, active_max = a2$n_active)
}))
print(tab, row.names = FALSE)
ck(tab$min_cdar_s[tab$T == 252 & tab$n == 25] < 2, sprintf("T 252 · n 25 min_cdar %.3fs < 2s (09-07 이전 cccp 27~36s)", tab$min_cdar_s[tab$T == 252 & tab$n == 25]))
cat(sprintf("  [INFO] 월 1회 × 리밸 312(2000-01~2025-12) 추정 = T252·n25 기준 %.1f 초\n", 312 * max(tab$min_cdar_s[tab$T == 252 & tab$n == 25], tab$max_mu_s[tab$T == 252 & tab$n == 25])))

cat(sprintf('{"test":"test_rf_cdar_construct","pass":%d,"fail":%d,"total":%d}\n', P, Fl, P + Fl))
if (Fl > 0L) quit(status = 1L)
