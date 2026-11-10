#!/usr/bin/env Rscript
# test_rf_cdar_bench_budget.R — CDaR 낙폭 예산 ν 규칙 선택지 nu_rule = "bench" (2026-11-10 · 레인 E3 3단계)
#   bench = 같은 창 공표 KOSPI200 일별 수익의 CDaR × 1(등급 CR '강함' = 전략 MDD ≤ 같은 창 벤치 MDD 와 같은 기준 · 새 숫자 없음)
#   ① 빡빡한 사례(후보 β 1.5 > 벤치) + allow_cash → 현금 · CDaR ≤ ν ② 느슨한 사례(후보 β 0.5) → 완전 투자
#   ③ PIT — 결정일 이후 벤치 교란 · 금지 날짜 행 → 결과 불변 ④ 기본(ew) 비트 동일 ⑤ 벤치 부재 · 교집합 부족 · 어휘 밖 → 멈춤
#   ⑥ 셀 엔진 두 줄을 실제 문장 그대로 평가(어휘 · BM_DT 부재 멈춤 · 벤치 Date < d) ⑦ 가드 돌연변이(소스 텍스트 치환 · 치환 수 단언)
.root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_cdar_construct.R"); r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)]); if (length(f)) { d <- dirname(gsub("\\\\", "/", f[1])); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } } }
  if (is.null(r)) stop("root 미발견"); r
})
Sys.setenv(QM_ROOT = .root)
suppressWarnings(suppressMessages({ library(data.table); source(file.path(.root, "02_Infrastructure/portfolio/strategy_tilt_weights.R")) }))
P <- 0L; Fl <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { P <<- P + 1L; cat("  [PASS]", msg, "\n") } else { Fl <<- Fl + 1L; cat("  [FAIL]", msg, "\n") } }
errs <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
q <- function(expr) { invisible(utils::capture.output(v <- expr)); v }
CDAR <- file.path(.root, "02_Infrastructure/reinforcement/rf_cdar_construct.R")
ADP  <- file.path(.root, "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R")
ENG  <- file.path(.root, "02_Infrastructure/reinforcement/rf_cell_engine.R")
mutate <- function(path, pairs) {
  src <- readLines(path, warn = FALSE, encoding = "UTF-8"); n <- 0L
  for (p in pairs) { hit <- grepl(p[1], src, fixed = TRUE); n <- n + sum(hit); src[hit] <- gsub(p[1], p[2], src[hit], fixed = TRUE) }
  f <- tempfile(fileext = ".R"); writeLines(src, f, useBytes = TRUE); list(path = f, n = n)
}
# 어댑터를 (필요하면 돌연변이 모듈로) 싣는다 — 어댑터 파일은 모듈을 source 하므로, 모듈 경로를 사본으로 바꾼 어댑터 사본을 만든다
load_adapter <- function(cdar_path = CDAR, adp_path = ADP) {
  src <- readLines(adp_path, warn = FALSE, encoding = "UTF-8")
  i <- grep('source(file.path(.cuz_root, "02_Infrastructure", "reinforcement", "rf_cdar_construct.R"), local = TRUE)', src, fixed = TRUE)
  stopifnot(length(i) == 1L)
  src[i] <- sprintf('source("%s", local = TRUE)', gsub("\\\\", "/", cdar_path))
  f <- tempfile(fileext = ".R"); writeLines(src, f, useBytes = TRUE); e <- new.env(parent = globalenv()); sys.source(f, envir = e); e
}
mr <- new.env(parent = globalenv()); suppressMessages(sys.source(file.path(.root, "02_Infrastructure/methods/method_registry.R"), envir = mr))
wrapped <- function(e) mr$wrap_adapter(get("method_weights", e), "CDaRCapCUZ2005", ub = 1, budget = "le")

# 합성 세계 — 시장(벤치) 요인 m · 후보 25종 = β × m + 잡음
set.seed(11); Tn <- 260L; d <- as.Date("2024-01-02"); dts <- d - rev(seq_len(Tn))
m <- stats::rnorm(Tn, 0.0002, 0.013); m[60:110] <- m[60:110] - 0.006            # 창 안 약세 구간(낙폭 경로가 생기게)
A <- sprintf("A%02d", 1:25)
mk <- function(beta) { R <- outer(m, rep(beta, 25) * stats::runif(25, 0.9, 1.1)) + matrix(stats::rnorm(Tn * 25, 0, 0.004), Tn); dimnames(R) <- list(NULL, A); R }
BM <- data.table(Date = c(dts, d + 0:9), r = c(m, stats::rnorm(10, 0, 0.01)))   # 결정일 뒤 10일 포함(엔진이 자르기 전 표 모양)
mu <- stats::setNames(seq(1, 0.2, length.out = 25), A)
ctxf <- function(R, rule = "bench", cash = TRUE, bench = BM[Date < d], Rd = dts) {
  x <- list(assets = A, R = R, mu = mu, ub = 1, decision_date = d, R_dates = Rd, bench_ret = bench)
  if (!is.null(rule)) x$cdar_nu_rule <- rule
  if (cash) x$allow_cash <- TRUE
  x
}
E <- load_adapter(); W <- wrapped(E); alpha <- E$.CUZ_CFG$alpha

cat("[1] 빡빡한 예산(후보 β 1.5) — 현금\n")
Rt <- mk(1.5); nu_b <- E$rcd_cdar(m, alpha); nu_e <- E$rcd_cdar(rowMeans(Rt), alpha)
wt <- q(W(ctxf(Rt)))
ck(nu_b < nu_e, sprintf("bench ν %.4f < ew ν %.4f (빡빡한 사례 성립)", nu_b, nu_e))
ck(sum(wt) < 1 - 1e-6 && all(wt >= 0), sprintf("allow_cash → Σw %.4f · 현금 %.4f", sum(wt), 1 - sum(wt)))
ck(E$rcd_cdar(Rt %*% wt, alpha) <= nu_b + 1e-8, sprintf("CDaR %.5f ≤ bench ν %.5f", E$rcd_cdar(Rt %*% wt, alpha), nu_b))
wt_nc <- q(W(ctxf(Rt, cash = FALSE)))
ck(abs(sum(wt_nc) - 1) < 1e-9, "opt-in 없음(allow_cash 없음) → Σw = 1(실행 불가면 min_cdar 복원 · 기록)")

cat("[2] 느슨한 예산(후보 β 0.5) — 완전 투자\n")
Rl <- mk(0.5); wl <- q(W(ctxf(Rl)))
ck(E$rcd_cdar(rowMeans(Rl), alpha) < nu_b && abs(sum(wl) - 1) < 1e-6, sprintf("ew ν %.4f < bench ν %.4f → Σw %.4f", E$rcd_cdar(rowMeans(Rl), alpha), nu_b, sum(wl)))

cat("[3] PIT\n")
BMp <- copy(BM)[Date >= d, r := -0.5]
ck(identical(q(W(ctxf(Rt, bench = BMp))), wt), "결정일 이후 벤치 −50%/일 교란(표에 남겨도) → 비중 비트 동일")
Rd_bad <- dts; Rd_bad[Tn] <- d                                             # 호출자 결함 모사: R 마지막 행 날짜가 결정일
BMq <- copy(BMp); BMq[Date == d, r := -0.3]
o1 <- q(W(ctxf(Rt, bench = BM, Rd = Rd_bad))); o2 <- q(W(ctxf(Rt, bench = BMq, Rd = Rd_bad)))
ck(identical(o1, o2), "R 행 날짜가 결정일이어도 그 행은 교집합에서 빠진다(결정일 벤치 교란 → 불변)")

cat("[4] 기본(ew) 비트 동일\n")
Rb <- mk(1.0); cx0 <- ctxf(Rb, rule = NULL)
w0 <- q(W(cx0)); wd <- E$rcd_construct(Rb, E$.CUZ_CFG, mu = mu, budget = "le")$w
ck(identical(unname(w0), unname(wd)), "nu_rule 미지정 → 종전 rcd_construct(설정 ew_candidates) 해와 비트 동일")
ck(identical(q(W(ctxf(Rb, rule = "ew"))), w0), "nu_rule = \"ew\"(별칭) → 미지정과 비트 동일")
ck(identical(E$rcd_nu_rule("ew"), "ew_candidates") && !is.na(errs(E$rcd_nu_rule("zz"))), "어휘: ew → ew_candidates · 밖 = 멈춤")

cat("[5] 멈춤\n")
raw <- get("method_weights", E)
m1 <- errs(q(raw(ctxf(Rt, bench = NULL))))
ck(!is.na(m1) && grepl("벤치 수익이 없다", m1), sprintf("벤치 부재 → 멈춤: %s", m1))
lg <- utils::capture.output(wf <- W(ctxf(Rt, bench = NULL)))
ck(any(grepl("벤치 수익이 없다", lg)) && !any(grepl("nu_rule=ew", lg)), "래퍼 경유도 사유 호명(조용한 ew 아님 — 엔진 EW 폴백 과반 가드가 칸을 멈춘다)")
n_min <- as.integer(ceiling(1 / (1 - alpha)))
m2 <- errs(q(raw(ctxf(Rt, bench = BM[Date %in% dts[1:(n_min - 1L)]]))))
ck(!is.na(m2) && grepl("교집합", m2), sprintf("교집합 %d일 < %d → 멈춤", n_min - 1L, n_min))
ok_n <- is.na(errs(q(raw(ctxf(Rt, bench = BM[Date %in% dts[1:n_min]])))))
ck(ok_n, sprintf("교집합 = %d일(최소) → 진행 · 시나리오도 교집합으로 줄인다", n_min))
m3 <- errs(q(raw(ctxf(Rt, Rd = NULL))))
ck(!is.na(m3) && grepl("R_dates", m3), "R 행 날짜 없음 → 멈춤")

cat("[6] 셀 엔진 두 줄(실제 문장 평가)\n")
el <- readLines(ENG, warn = FALSE, encoding = "UTF-8")
l_pre <- grep(".NUR <- if (is.null(.wt$cdar_nu_rule)) NULL", el, fixed = TRUE); l_in <- grep("if (!is.null(.NUR)) { ctx$cdar_nu_rule <- .NUR;", el, fixed = TRUE)
ck(length(l_pre) == 1L && length(l_in) == 1L, "엔진에 ν 규칙 두 줄이 각 1곳")
BMD <- data.table(Date = BM$Date, BM_Ret = BM$r)
ck(grepl("어휘 밖", errs(eval(parse(text = el[l_pre]), list2env(list(.wt = list(cdar_nu_rule = "zz")))))), "어휘 밖 → 멈춤")
ck(grepl("BM_DT", errs(eval(parse(text = el[l_pre]), list2env(list(.wt = list(cdar_nu_rule = "bench")), parent = baseenv())))), "bench + BM_DT 없음 → 멈춤(fail-closed)")
e1 <- new.env(); e1$.wt <- list(cdar_nu_rule = "bench"); e1$BM_DT <- BMD; eval(parse(text = el[l_pre]), e1)
e1$ctx <- list(); e1$M <- data.table(Date = dts); e1$d <- d; eval(parse(text = el[l_in]), e1)
ck(identical(e1$ctx$cdar_nu_rule, "bench") && max(e1$ctx$bench_ret$Date) < d && identical(e1$ctx$R_dates, dts), "칸 bench → ctx 에 규칙 · R 행 날짜 · 벤치(Date < d) 실음")
e2 <- new.env(); e2$.wt <- list(); eval(parse(text = el[l_pre]), e2); e2$ctx <- list(a = 1); e2$M <- data.table(Date = dts); e2$d <- d; eval(parse(text = el[l_in]), e2)
ck(identical(e2$ctx, list(a = 1)), "칸 미지정 → ctx 모양 그대로(기본 비트 동일)")

cat("[7] 돌연변이\n")
M1 <- mutate(CDAR, list(c("if (sum(keep) < n_min) stop(", "if (FALSE) stop(")))
EM1 <- load_adapter(M1$path)
ck(M1$n == 1L && is.na(errs(q(get("method_weights", EM1)(ctxf(Rt, bench = BM[Date %in% dts[1:(n_min - 1L)]]))))), sprintf("최소 관측 가드 제거(치환 %d) → 부족해도 진행(검출)", M1$n))
M2 <- mutate(CDAR, list(c("B <- B[as.Date(Date) < as.Date(decision_date) & is.finite(r),", "B <- B[is.finite(r),"),
                        c("keep <- rd %in% B$Date & rd < as.Date(decision_date)", "keep <- rd %in% B$Date")))
EM2 <- load_adapter(M2$path); W2 <- wrapped(EM2)
ck(M2$n == 2L && !identical(q(W2(ctxf(Rt, bench = BM, Rd = Rd_bad))), q(W2(ctxf(Rt, bench = BMq, Rd = Rd_bad)))), sprintf("결정일 컷 제거(치환 %d) → 결정일 벤치 교란이 비중을 바꾼다(검출)", M2$n))
M3 <- mutate(ADP, list(c('if (identical(nr, "bench")) {', 'if (FALSE) {')))
EM3 <- load_adapter(CDAR, M3$path)
ck(M3$n == 1L && !is.na(errs(q(get("method_weights", EM3)(ctxf(Rt))))), sprintf("어댑터 bench 분기 제거(치환 %d) → 벤치 없이 bench 를 못 풀고 멈춤(조용한 ew 아님)", M3$n))
el_m <- sub("ctx$bench_ret <- .BMB[Date < d]", "ctx$bench_ret <- .BMB", el[l_in], fixed = TRUE)
e3 <- new.env(); e3$.wt <- list(cdar_nu_rule = "bench"); e3$BM_DT <- BMD; eval(parse(text = el[l_pre]), e3); e3$ctx <- list(); e3$M <- data.table(Date = dts); e3$d <- d; eval(parse(text = el_m), e3)
ck(!identical(el_m, el[l_in]) && max(e3$ctx$bench_ret$Date) >= d, "엔진 벤치 컷 제거(치환 1) → 결정일 이후 행이 ctx 에 실림(검출)")

cat(sprintf('{"test":"test_rf_cdar_bench_budget","pass":%d,"fail":%d,"total":%d}\n', P, Fl, P + Fl))
if (Fl > 0L) quit(status = 1L)
