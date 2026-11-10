#!/usr/bin/env Rscript
# test_rf_cash_budget_link.R — 구성 층 현금 통과(P-2b) · lean 창 전달(P-3b) 시험 (2026-11-10 · 레인 E3 2단계)
#   P-2b: 현금은 arm 판 표식(budget = "le") ∧ 칸 opt-in(ctx$allow_cash) 둘 다일 때만. 한쪽만이면 합 = 1(종전과 비트 동일).
#         합 ≤ 1 판은 음수 · 합 > 1 · 비유한 · 상한 초과를 거부한다(재분배 없음).
#   P-3b: ctx$n_days 가 있을 때만 lean 빌트인 창 = 그 값. 없으면 함수 기본 창(종전).
#   각 가드는 소스 텍스트 치환 돌연변이로 발화 실증(치환 수 단언).
#   (기존 58 arm 비트 불변 = 수정 전후 스냅샷 대조 — 보고서 · 어댑터 계약 시험 61 은 별도 실행)
.root <- local({
  m <- file.path("02_Infrastructure", "portfolio", "weight_catalog.R"); r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)]); if (length(f)) { d <- dirname(gsub("\\\\", "/", f[1])); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } } }
  if (is.null(r)) stop("root 미발견"); r
})
Sys.setenv(QM_ROOT = .root)
P <- 0L; Fl <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { P <<- P + 1L; cat("  [PASS]", msg, "\n") } else { Fl <<- Fl + 1L; cat("  [FAIL]", msg, "\n") } }
errs <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
q <- function(expr) { invisible(utils::capture.output(v <- expr)); v }
MR <- file.path(.root, "02_Infrastructure/methods/method_registry.R")
WC <- file.path(.root, "02_Infrastructure/portfolio/weight_catalog.R")
CUZ <- "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R"
suppressWarnings(suppressMessages({ library(data.table); source(file.path(.root, "02_Infrastructure/portfolio/strategy_tilt_weights.R")) }))
load_mr <- function(path) { e <- new.env(parent = globalenv()); suppressMessages(sys.source(path, envir = e)); e }
mutate <- function(path, pairs) {
  src <- readLines(path, warn = FALSE, encoding = "UTF-8"); n <- 0L
  for (p in pairs) { hit <- grepl(p[1], src, fixed = TRUE); n <- n + sum(hit); src[hit] <- gsub(p[1], p[2], src[hit], fixed = TRUE) }
  f <- tempfile(fileext = ".R"); writeLines(src, f, useBytes = TRUE); list(path = f, n = n)
}
A <- sprintf("A%02d", 1:25)
set.seed(1); ctx <- list(assets = A, R = matrix(stats::rnorm(252 * 25, 0, 0.02), 252, dimnames = list(NULL, A)),
                         mu = stats::setNames(seq(1, -1, length.out = 25), A), ub = 1, decision_date = as.Date("2024-01-02"))
ctxc <- c(ctx, list(allow_cash = TRUE))
# 현금 시험용 세계 — 공통 시장 요인이 지배(분산으로 낙폭을 반으로 못 줄인다 → κ 0.5 예산은 현금으로만 맞는다)
set.seed(2); .f <- stats::rnorm(252, 0.0003, 0.015)
ctx3 <- ctx; ctx3$R <- outer(.f, stats::runif(25, 0.8, 1.2)) + matrix(stats::rnorm(252 * 25, 0, 0.004), 252, dimnames = list(NULL, A))
ctx3c <- c(ctx3, list(allow_cash = TRUE))
half <- function(ctx) stats::setNames(rep(0.5 / length(ctx$assets), length(ctx$assets)), ctx$assets)

## ── 핵심 성질 함수(원본 · 돌연변이 공통) ───────────────────────────────────────
mr_props <- function(e) {
  wa <- e$wrap_adapter
  r <- list()
  r$no_mark_cash   <- abs(sum(q(wa(half, "x")(ctxc))) - 1) < 1e-12                      # 표식 없음 + opt-in → 합 1
  r$mark_no_optin  <- identical(q(wa(half, "x", budget = "le")(ctx)), q(wa(half, "x")(ctx)))  # 표식 + opt-in 없음 → eq 와 비트 동일
  r$both_cash      <- isTRUE(all.equal(q(wa(half, "x", budget = "le")(ctxc)), half(ctx)))      # 둘 다 → 값 그대로(합 0.5)
  neg <- function(ctx) { v <- half(ctx); v[1] <- -0.01; v }
  over <- function(ctx) stats::setNames(rep(1.2 / 25, 25), ctx$assets)
  nonf <- function(ctx) { v <- half(ctx); v[2] <- NA; v }
  r$rej_neg  <- grepl("음수", errs(q(wa(neg, "x", budget = "le")(ctxc))))
  r$rej_over <- grepl("합 .* > 1", errs(q(wa(over, "x", budget = "le")(ctxc))))
  r$rej_nonf <- grepl("비유한", errs(q(wa(nonf, "x", budget = "le")(ctxc))))
  r$rej_ub   <- grepl("상한", errs(q(wa(function(ctx) { v <- half(ctx); v[1] <- 0.3; v }, "x", ub = 0.2, budget = "le")(ctxc))))
  r$rej_vocab <- !is.na(errs(wa(half, "x", budget = "lt")))
  r
}

cat("[1] wrap_adapter(budget) — 원본\n")
e0 <- load_mr(MR); p0 <- mr_props(e0)
ck(p0$no_mark_cash, "표식 없는 arm + allow_cash → 합 1(현금 안 생김)")
ck(p0$mark_no_optin, "표식 arm + opt-in 없음 → 합 1 경로와 비트 동일")
ck(p0$both_cash, "표식 + opt-in → 값 그대로(Σw = 0.5 · 재분배 없음)")
ck(p0$rej_neg && p0$rej_over && p0$rej_nonf && p0$rej_ub, "합 ≤ 1 판 거부: 음수 · 합 > 1 · 비유한 · 상한 초과")
ck(p0$rej_vocab, "budget 어휘 밖 → 멈춤")

cat("[2] 돌연변이 — method_registry.R\n")
muts <- list(
  list(nm = "opt-in 조건 제거", pr = list(c('if (identical(budget, "le") && isTRUE(ctx$allow_cash)) return', 'if (identical(budget, "le")) return')), key = "mark_no_optin"),
  list(nm = "합 > 1 거부 제거", pr = list(c("if (sum(w) > 1 + 1e-6) stop(sprintf(\"[method:%s] 합 ≤ 1 판", "if (FALSE) stop(sprintf(\"[method:%s] 합 ≤ 1 판")), key = "rej_over"),
  list(nm = "음수 거부 제거", pr = list(c("if (any(w < -1e-9)) stop(", "if (FALSE) stop(")), key = "rej_neg"),
  list(nm = "합 ≤ 1 판 분기 제거", pr = list(c("return(.wrap_le_finalize(fn, method_id, ub, ctx))", "NULL")), key = "both_cash"))
for (m in muts) {
  mm <- mutate(MR, m$pr); pm <- tryCatch(mr_props(load_mr(mm$path)), error = function(e) list())
  ck(mm$n == 1L && !isTRUE(pm[[m$key]]), sprintf("돌연변이 '%s'(치환 %d) → 성질 %s 가 깨져 검출", m$nm, mm$n, m$key))
}

cat("[3] 카탈로그 판 표식 · CDaR 어댑터 현금 통과\n")
.WC_QUIET_LOAD <- TRUE
wc_props <- function(path) {
  w <- new.env(parent = globalenv()); suppressWarnings(suppressMessages(sys.source(path, envir = w)))
  ent_cuz <- list(catalog_id = "paper:CDaRCapCUZ2005", resolver = list(kind = "adapter_file", adapter = CUZ, entrypoint = "method_weights"))
  ent_erc <- list(catalog_id = "paper:ERCMRT2010", resolver = list(kind = "adapter_file", adapter = "02_Infrastructure/methods/adapters/erc_maillard_roncalli_teiletche_2010.R", entrypoint = "method_weights"))
  r <- list()
  r$b_cuz <- w$.wc_entry_budget(ent_cuz, .root); r$b_erc <- w$.wc_entry_budget(ent_erc, .root)
  r$b_bad <- !is.na(errs(w$.wc_entry_budget(c(ent_erc, list(budget = "zz")), .root)))
  ae <- w$.wc_adapter_env(CUZ, .root); ae$.CUZ_CFG$nu_kappa <- 0.5          # 낙폭 예산을 줄인다(시험 환경 사본 · 운영 설정 파일 불변)
  f <- w$as_ctx_adapter(ent_cuz, root = .root)
  r$w_cash <- q(f(ctx3c)); r$w_full <- q(f(ctx3))
  r$cdar <- ae$rcd_cdar(ctx3$R %*% r$w_cash, ae$.CUZ_CFG$alpha); r$nu <- 0.5 * ae$rcd_cdar(rowMeans(ctx3$R), ae$.CUZ_CFG$alpha)
  r$w_erc_c <- q(w$as_ctx_adapter(ent_erc, root = .root)(ctxc)); r$w_erc <- q(w$as_ctx_adapter(ent_erc, root = .root)(ctx))
  r$w
  r$env <- w
  r
}
c0 <- wc_props(WC)
ck(identical(c0$b_cuz, "le") && identical(c0$b_erc, "eq") && c0$b_bad, "판 표식: CDaR = le(어댑터 METHOD_BUDGET) · ERC = eq(표식 없음) · 어휘 밖 = 멈춤")
ck(sum(c0$w_cash) < 1 - 1e-6 && all(c0$w_cash >= 0) && c0$cdar <= c0$nu + 1e-8,
   sprintf("CDaR 예산 κ 0.5 + allow_cash → Σw %.4f < 1 · CDaR %.5f ≤ ν %.5f", sum(c0$w_cash), c0$cdar, c0$nu))
ck(abs(sum(c0$w_full) - 1) < 1e-9, "같은 arm · opt-in 없음 → Σw = 1")
ck(identical(c0$w_erc_c, c0$w_erc) && abs(sum(c0$w_erc) - 1) < 1e-9, "표식 없는 ERC arm 은 allow_cash 를 줘도 비트 동일 · 합 1")

cat("[4] P-3b lean n_days\n")
invisible(utils::capture.output(c0$env$.wc_ensure_lean_builtins(.root, quiet = TRUE)))
lean_props <- function(w) {
  mv <- w$as_ctx_adapter(list(catalog_id = "lean:minvar", resolver = list(kind = "lean_builtin", lean_name = "minvar", needs_score = FALSE)), root = .root)
  st <- w$as_ctx_adapter(list(catalog_id = "lean:score_tilt", resolver = list(kind = "lean_builtin", lean_name = "score_tilt", needs_score = TRUE)), root = .root)   # score_pure(α 1)는 Σ 를 안 써 창에 무감 — 창 전달 실증엔 score_tilt
  nd <- function(x, n) { x$n_days <- n; x }
  list(mv_native = q(mv(ctx)), mv_120 = q(mv(nd(ctx, 120L))), mv_252 = q(mv(nd(ctx, 252L))),
       sp_native = q(st(ctx)), sp_60 = q(st(nd(ctx, 60L))), sp_252 = q(st(nd(ctx, 252L))),
       bad_log = paste(utils::capture.output(mv(nd(ctx, "x"))), collapse = " "),
       body_ok = grepl("ctx$n_days", paste(deparse(body(w$.wc_lean_carrier_fn)), collapse = " "), fixed = TRUE))
}
l0 <- lean_props(c0$env)
ck(identical(l0$mv_native, l0$mv_120) && !identical(l0$mv_native, l0$mv_252), "minvar: n_days 120(=기본) 비트 동일 · 252 는 다름(전달 실증)")
ck(identical(l0$sp_native, l0$sp_60) && !identical(l0$sp_native, l0$sp_252), "score_tilt: n_days 60(=기본) 비트 동일 · 252 는 다름")
ck(grepl("n_days", l0$bad_log), "n_days 비정수 → 멈춤(래퍼가 호명 · 기본 창으로 조용히 안 돌아감)")
ck(l0$body_ok, "셀 엔진 P-3 가드가 보는 문장(ctx$n_days)이 캐리어 본문에 있다")

cat("[5] 돌연변이 — weight_catalog.R\n")
m1 <- mutate(WC, list(c('if (!is.null(e) && exists("METHOD_BUDGET", envir = e, inherits = FALSE)) b <- get("METHOD_BUDGET", envir = e)', "NULL")))
c1 <- wc_props(m1$path)
ck(m1$n == 1L && identical(c1$b_cuz, "eq") && abs(sum(c1$w_cash) - 1) < 1e-9, sprintf("표식 판독 제거(치환 %d) → CDaR 현금 사라짐(검출)", m1$n))
m2 <- mutate(WC, list(c('if (!is.null(ctx$n_days) && "n_days" %in% names(formals(fn))) mx <- c(mx, list(n_days = .wc_n_days(ctx$n_days)))', "NULL")))
w2 <- new.env(parent = globalenv()); suppressWarnings(suppressMessages(sys.source(m2$path, envir = w2))); l2 <- lean_props(w2)
ck(m2$n == 1L && identical(l2$mv_native, l2$mv_252), sprintf("n_days 전달 제거(치환 %d) → minvar 252 = 기본(검출)", m2$n))
m3 <- mutate(WC, list(c("else get(\"wrap_adapter\", envir = we)(raw, as.character(entry$catalog_id), ub = ub, budget = \"le\")",
                        "else get(\"wrap_adapter\", envir = we)(raw, as.character(entry$catalog_id), ub = ub)")))
c3 <- wc_props(m3$path)
ck(m3$n == 1L && abs(sum(c3$w_cash) - 1) < 1e-9, sprintf("le 래퍼 배선 제거(치환 %d) → 현금 사라짐(검출)", m3$n))

cat(sprintf('{"test":"test_rf_cash_budget_link","pass":%d,"fail":%d,"total":%d}\n', P, Fl, P + Fl))
if (Fl > 0L) quit(status = 1L)
