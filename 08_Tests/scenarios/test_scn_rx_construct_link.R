#!/usr/bin/env Rscript
#==============================================================================
# test_scn_rx_construct_link.R — 셀 엔진 ↔ 구성 엔진(E3) 연결 P-1 · P-2 · P-3 시나리오 (2026-11-10 감사 레인 E2)
#   P-1 weighting.sigma_provider(요인 위험모형 Σ) · P-2 weighting.allow_cash(구성 층 Σw ≤ 1) · P-3 weighting.lean_n_days(lean 창)
#   본다: (a) 기존 칸 사양 = 수리 전 엔진(git HEAD 판)과 PORTFOLIO 비트 동일 · 기본값을 명시해도 동일
#         (b) 요인 Σ 칸이 실제로 다른 비중을 낸다(Σ 를 쓰는 arm) · Σ 를 안 쓰는 arm 은 '처치 미전달'로 멈춘다
#         (c) PIT — 결정일 이후 요인 수익 주입 → Σ 불변(같은 ctx 구성 · rfc_sigma_ctx)
#         (d) 현금 통과 마무리 함수 · 카탈로그 정규형(Σw = 1)이면 '현금 미전달'로 멈춘다 · lean 캐리어가 n_days 를 안 읽으면 멈춘다
#         (e) 돌연변이 — 마무리 함수의 기본 재정규화 삭제 → (d) 가 잡는다(치환 성사 단정)
#   격리: 합성 가격 픽스처 · 스펙 · 엔진 사본 = tempdir. 운영 파일은 읽기만(요인 수익 parquet 날짜 · 등록부). 운영 쓰기 0.
#   ★요인 Σ 양성 칸(b)은 운영 .cache/kr_factor_returns_daily.parquet 의 거래일로 픽스처 날짜를 만든다 — 없으면 SKIP.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = FALSE); me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(if (!is.na(me)) dirname(dirname(dirname(me))), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || is.na(p) || !nzchar(p)) next; p <- gsub("\\\\", "/", p)
  if (!grepl("^([A-Za-z]:|/)", p)) p <- if (p %in% c(".", "")) gsub("\\\\", "/", getwd()) else file.path(gsub("\\\\", "/", getwd()), p)   # 절대 경로(엔진이 setwd 한다)
  if (file.exists(file.path(p, "02_Infrastructure/reinforcement/rf_cell_engine.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
Sys.setenv(QM_ROOT = ROOT)
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(name, cond, why = "") { ok <- isTRUE(tryCatch(cond, error = function(e) { why <<- conditionMessage(e); FALSE }))
  if (ok) PASS <<- PASS + 1L else FAIL <<- FAIL + 1L
  cat(sprintf("  [%s] %s%s\n", if (ok) "PASS" else "FAIL", name, if (!ok && nzchar(why)) paste0(" — ", substr(why, 1, 300)) else "")) }
skp <- function(name) { SKIP <<- SKIP + 1L; cat(sprintf("  [SKIP] %s\n", name)) }

## 수리 전 엔진(git HEAD 판) — 기존 칸 사양의 결과 불변 기준
HEADENG <- file.path(tempdir(), "rf_cell_engine_HEAD.R")
gh <- suppressWarnings(system2("git", c("-C", shQuote(ROOT), "show", "HEAD:02_Infrastructure/reinforcement/rf_cell_engine.R"), stdout = HEADENG, stderr = FALSE))
HAVE_HEAD <- identical(as.integer(gh), 0L) && file.exists(HEADENG) && file.size(HEADENG) > 1000

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
make_fixture <- function(d, n_tk = 50L, idx_n = 40L) {
  set.seed(20261110L)
  tk <- sprintf("T%03d", seq_len(n_tk)); x <- CJ(Ticker = tk, Date = d); setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]; x[, Close := 10000 * cumprod(1 + .r), by = Ticker]; x[, .r := NULL]
  x[, Vol := 200000]; x[, Size := Close * 1e6]
  x[, K200 := as.integer(sub("T", "", Ticker, fixed = TRUE)) <= idx_n]; x[, KQ150 := FALSE]
  x[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker, fixed = TRUE)) %% 5L) + 1L)]
  x[]
}
FRP <- file.path(ROOT, ".cache/kr_factor_returns_daily.parquet")
DATES <- if (file.exists(FRP)) { suppressMessages(library(arrow)); fd <- sort(unique(as.Date(arrow::read_parquet(FRP, col_select = "Date")$Date)))
                                 fd[fd >= as.Date("2003-06-02") & fd <= as.Date("2009-12-30")] } else as.Date(character(0))
REAL_DATES <- length(DATES) > 1000L
if (!REAL_DATES) { DATES <- seq(as.Date("2003-06-02"), as.Date("2009-12-30"), by = "day"); DATES <- DATES[as.integer(format(DATES, "%w")) %in% 1:5] }
FIX <- make_fixture(DATES)
BMF <- { t <- copy(FIX); setorder(t, Ticker, Date); t[, r := Close / shift(Close, 1L) - 1, by = Ticker]; t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }
PX <- list(kind = "price", id = "lowvol60")
base_spec <- function(...) modifyList(list(code = "SCN", label = "scn", block = "T", fixed_axes = AXES, base_signal = list(kind = "mom_12_1"),
                                           factor2 = PX, weighting = list(kind = "ew"), universe = list(kind = "k200_kq150")), list(...))
run_cell <- function(spec, engine = ENGINE) {
  p <- tempfile("scn_spec_", fileext = ".json"); writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  Sys.setenv(RF_CELL_SPEC = p); on.exit(Sys.unsetenv("RF_CELL_SPEC"))
  env <- new.env(); assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", BMF, envir = env); err <- NULL
  logs <- utils::capture.output(suppressWarnings(suppressMessages(tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, logs = logs, P = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) get("PORTFOLIO", envir = env) else NULL)
}
same_port <- function(a, b) !is.null(a$P) && !is.null(b$P) && isTRUE(all.equal(a$P[order(Date, Ticker)], b$P[order(Date, Ticker)], tolerance = 0, check.attributes = FALSE))

cat("== (a) 기존 칸 사양 결과 불변 ==\n")
WC <- list(kind = "catalog", catalog_id = "lean:ivol")
r_new <- run_cell(base_spec(weighting = WC))
if (HAVE_HEAD) {
  r_old <- run_cell(base_spec(weighting = WC), engine = HEADENG)
  chk("A1 카탈로그 lean:ivol — 수리 전(HEAD) 엔진과 PORTFOLIO 비트 동일", is.null(r_new$err) && is.null(r_old$err) && same_port(r_new, r_old), r_new$err %||% r_old$err %||% "")
  r_exp <- run_cell(base_spec(weighting = c(WC, list(sigma_provider = "sample", allow_cash = FALSE, lean_n_days = "native"))))
  chk("A2 기본값을 명시해도(sample · allow_cash false · native) HEAD 와 비트 동일", is.null(r_exp$err) && same_port(r_exp, r_old), r_exp$err %||% "")
  WE <- list(kind = "catalog", catalog_id = "paper:ERCMRT2010")
  e_new <- run_cell(base_spec(weighting = WE)); e_old <- run_cell(base_spec(weighting = WE), engine = HEADENG)
  chk("A3 Σ 를 쓰는 arm(paper:ERCMRT2010) 표본 Σ 기본 — HEAD 와 비트 동일", is.null(e_new$err) && same_port(e_new, e_old), e_new$err %||% e_old$err %||% "")
} else { skp("A1~A3 git HEAD 판 엔진을 꺼내지 못함"); e_new <- run_cell(base_spec(weighting = list(kind = "catalog", catalog_id = "paper:ERCMRT2010"))) }

cat("== (b) P-1 요인 Σ ==\n")
if (REAL_DATES) {
  f1 <- run_cell(base_spec(weighting = list(kind = "catalog", catalog_id = "paper:ERCMRT2010", sigma_provider = "factor:ts:base")))
  chk("B1 [양성] factor:ts:base — 완주 · 관측 요인 Σ 신호일 > 0 · pca 폴백 소수 · 비중이 표본 Σ 판과 다르다",
      is.null(f1$err) && any(grepl("sigma_provider factor:ts:base | 요인 Σ 신호일", f1$logs, fixed = TRUE)) && !same_port(f1, e_new), f1$err %||% "")
  f2 <- run_cell(base_spec(weighting = list(kind = "catalog", catalog_id = "lean:ivol", sigma_provider = "factor:ts:base")))
  chk("B2 [처치 미전달] Σ 를 안 쓰는 arm(lean:ivol)에 요인 Σ → 멈춘다", !is.null(f2$err) && grepl("처치 미전달", f2$err), f2$err %||% "멈추지 않았다")
} else skp("B1 · B2 운영 요인 수익 parquet 없음(픽스처 날짜를 거래일로 못 맞춤)")
f3 <- run_cell(base_spec(weighting = list(kind = "catalog", catalog_id = "lean:ivol", sigma_provider = "factor:fm:base")))
chk("B3 어휘 밖 sigma_provider → 멈춘다", !is.null(f3$err) && grepl("어휘 밖", f3$err), f3$err %||% "")
## (c) PIT — 엔진과 같은 ctx 구성(R_dates · factor_returns = Date < d)으로 rfc_sigma_ctx · 결정일 뒤 요인 수익 교란 → Σ 불변
FE <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_factor_cov.R"), envir = FE))))
cfg <- FE$rfc_config(file.path(ROOT, "02_Infrastructure/reinforcement/rf_factor_cov.json"))
set.seed(7); dd <- seq(as.Date("2010-01-01"), by = "day", length.out = 400L); d0 <- dd[301]
FR <- data.table(Date = dd); for (cn in cfg$factor_columns) FR[, (cn) := rnorm(.N, 0, 0.01)]
Bt <- matrix(rnorm(8 * length(cfg$factor_columns), 1, 0.3), 8)
Rm <- as.matrix(FR[Date < d0, cfg$factor_columns, with = FALSE]) %*% t(Bt) + matrix(rnorm(300 * 8, 0, 0.01), 300); colnames(Rm) <- sprintf("A%d", 1:8)
mk <- function(F) list(assets = colnames(Rm), R = Rm, R_dates = dd[1:300], decision_date = d0, factor_returns = function() F[Date < d0])
s1 <- FE$rfc_sigma_ctx(mk(FR), cfg, "dd_state")
FRp <- copy(FR); for (cn in cfg$factor_columns) FRp[Date >= d0, (cn) := get(cn) * 50 + 1]
s2 <- FE$rfc_sigma_ctx(mk(FRp), cfg, "dd_state")
chk("C1 [PIT] 결정일 이후 요인 수익 교란 → 요인 Σ(dd_state 변형 · 확장 창 이력 포함) 불변 · 관측 요인 모형(ts)",
    identical(s1$model, "ts") && isTRUE(all.equal(s1$Sigma, s2$Sigma, tolerance = 0)))
etxt <- paste(readLines(ENGINE, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("C2 [배선] 엔진이 요인 수익을 신호일마다 Date < d 로 자르고 R 행 날짜(M$Date)를 넘긴다",
    grepl("R_dates = M$Date, decision_date = d,", etxt, fixed = TRUE) && grepl("factor_returns = function() .FCV$FR[Date < d]", etxt, fixed = TRUE))

cat("== (d) P-2 현금 · P-3 lean 창 ==\n")
fdef <- NULL; for (ex in parse(ENGINE, keep.source = FALSE)) if (is.call(ex) && identical(as.character(ex[[1]]), "<-") && identical(as.character(ex[[2]]), ".rf_wt_finalize")) fdef <- ex
FZ <- new.env(parent = globalenv()); if (!is.null(fdef)) eval(fdef, FZ)
w0 <- c(0.2, 0.3, 0.1)
chk("D1 마무리 기본 = 종전 식 w / sum(w)(비트 동일) · allow_cash = Σw ≤ 1 그대로 · 합 > 1 은 멈춘다",
    identical(FZ$.rf_wt_finalize(w0, FALSE), w0 / sum(w0)) && identical(FZ$.rf_wt_finalize(w0, TRUE), w0) &&
      grepl("레버리지 금지", tryCatch({ FZ$.rf_wt_finalize(c(0.7, 0.6), TRUE); "" }, error = function(e) conditionMessage(e))))
c1 <- run_cell(base_spec(weighting = c(WC, list(allow_cash = TRUE))))
chk("D2 [처치 미전달 · 지키던 성질] 판 표식(budget = le) 없는 arm(lean:ivol)은 allow_cash 여도 Σw = 1 → 멈춘다(현금 0 을 '현금 칸'으로 기록하지 않는다)",
    !is.null(c1$err) && grepl("현금(Σw < 1)을 만든 신호일 0", c1$err, fixed = TRUE), c1$err %||% "멈추지 않았다")
chk("D2b [배선 · P-2b] 엔진은 allow_cash 칸에서만 ctx$allow_cash 를 싣는다(합 ≤ 1 정규형은 판 표식 arm + 이 표식 둘 다일 때만 — test_rf_cash_budget_link.R)",
    grepl("if (.CASH) ctx$allow_cash <- TRUE", etxt, fixed = TRUE) && lengths(regmatches(etxt, gregexpr("ctx$allow_cash <-", etxt, fixed = TRUE))) == 1L)
c2 <- run_cell(base_spec(weighting = c(WC, list(allow_cash = "yes"))))
chk("D3 allow_cash 형식 오류 → 멈춘다", !is.null(c2$err) && grepl("true | false", c2$err, fixed = TRUE), c2$err %||% "")
l1 <- run_cell(base_spec(weighting = c(WC, list(lean_n_days = "cell"))))
chk("D4 [P-3b 양성] lean_n_days = cell — 캐리어가 ctx$n_days(창 행 수)를 받아 완주 · lean:ivol 비중이 기본 창(60일) 판과 다르다",
    is.null(l1$err) && !same_port(l1, r_new), l1$err %||% "기본 창 판과 같다(전달 안 됨)")

cat("== (e) 돌연변이 ==\n")
from <- "  if (!isTRUE(allow_cash)) return(w / sum(w))"
n_hit <- lengths(regmatches(etxt, gregexpr(from, etxt, fixed = TRUE)))
mx <- parse(text = sub(from, "  if (FALSE) return(w / sum(w))", etxt, fixed = TRUE), keep.source = FALSE); md <- NULL
for (ex in mx) if (is.call(ex) && identical(as.character(ex[[1]]), "<-") && identical(as.character(ex[[2]]), ".rf_wt_finalize")) md <- ex
MZ <- new.env(parent = globalenv()); eval(md, MZ)
chk("E1 [돌연변이 red] 기본 재정규화 삭제 → D1 의 '기본 = w / sum(w)' 가 깨진다(치환 1곳 성사)",
    n_hit == 1L && !identical(MZ$.rf_wt_finalize(w0, FALSE), w0 / sum(w0)))

## 가드 돌연변이 — 엔진 사본에서 가드 한 줄을 지우면 같은 칸이 조용히 완주한다(= 그 가드가 유일한 방어선 · 치환 성사 단정)
mut_engine <- function(from, to) {
  if (lengths(regmatches(etxt, gregexpr(from, etxt, fixed = TRUE))) != 1L) return(NULL)
  f <- tempfile("rf_cell_engine_mut_", fileext = ".R"); writeLines(sub(from, to, etxt, fixed = TRUE), f, useBytes = TRUE); f
}
mP1 <- mut_engine("        if (.nProbe > 0L && .nSame == .nProbe) stop(", "        if (FALSE) stop(")
mP3 <- mut_engine("        if (!grepl(\"ctx$n_days\", .car, fixed = TRUE))", "        if (!grepl(\"ctx$n_days_absent_token\", .car, fixed = TRUE))")
if (REAL_DATES) {
  rm1 <- if (is.null(mP1)) list(err = "치환 불성사") else run_cell(base_spec(weighting = list(kind = "catalog", catalog_id = "lean:ivol", sigma_provider = "factor:ts:base")), engine = mP1)
  chk("E2 [돌연변이 red] Σ 전달 탐침 가드 삭제 → B2 칸이 조용히 완주한다(가드가 유일한 방어선)", !is.null(mP1) && is.null(rm1$err), rm1$err %||% "")
} else skp("E2 운영 요인 수익 parquet 없음")
rm3 <- if (is.null(mP3)) list(err = "치환 불성사") else run_cell(base_spec(weighting = c(WC, list(lean_n_days = "cell"))), engine = mP3)
chk("E3 [가드 양성 대조] 엔진의 캐리어 판독 문장을 없는 토큰으로 바꾸면 D4 칸이 멈춘다(캐리어가 n_days 를 안 읽는 판을 잡는 가드가 살아 있다)", !is.null(mP3) && !is.null(rm3$err) && grepl("ctx$n_days", rm3$err, fixed = TRUE), rm3$err %||% "멈추지 않았다")

cat("== (f) 변형 미전달 집계 · cdar_nu_rule 전달 가드 (2026-11-10 G8) ==\n")
## F1~F3: 엔진의 실제 문장(집계 한 줄 · 가드 한 줄)을 그대로 평가 — 변형(downside · dd_state)이 표본 부족으로 base 로 떨어진 신호일을 센다
el <- readLines(ENGINE, warn = FALSE, encoding = "UTF-8")
l_cnt <- grep(".vu <- .so$variant_used %||% NA_character_;", el, fixed = TRUE)
l_grd <- grep("if (.nUnt * 2L > .nSig) stop(", el, fixed = TRUE)
chk("F0 엔진에 변형 미전달 집계 · 가드 문장이 각 1곳", length(l_cnt) == 1L && length(l_grd) == 1L, sprintf("집계 %d · 가드 %d", length(l_cnt), length(l_grd)))
## 실제 공급자 출력으로 .so 를 만든다 — 상태 없는 이력(fallback → variant_used base) · 급락 이력(상태 표본 충분)
Hst <- copy(FR); Hst[1:150, MKT_TOTAL := -0.004]                        # 앞 150일 약 45% 하락 · 이후 고점 아래
mkS <- function(F) list(assets = colnames(Rm), R = Rm, R_dates = dd[1:300], decision_date = d0, factor_returns = function() F[Date < d0])
FRn <- copy(FR); FRn[, MKT_TOTAL := abs(MKT_TOTAL) * 0.1]               # 시장이 오르기만 하는 이력 — 상태일 0(폴백 확정)
so_fb <- FE$rfc_sigma_ctx(mkS(FRn), cfg, "dd_state"); so_ok <- FE$rfc_sigma_ctx(mkS(Hst), cfg, "dd_state")
chk("F1 공급자 — 상태 없는 이력은 ts 이면서 variant_used = base · 급락 이력은 dd_state",
    identical(so_fb$model, "ts") && identical(so_fb$variant_used, "base") && identical(so_ok$variant_used, "dd_state"),
    sprintf("fb %s/%s · ok %s/%s", so_fb$model, so_fb$variant_used %||% "NULL", so_ok$model, so_ok$variant_used %||% "NULL"))
run_counts <- function(sos, variant, cnt_line = el[l_cnt], grd_line = el[l_grd]) {
  p <- new.env(parent = globalenv()); p$.nFB <- 0L; p$.nVFB <- 0L; p$.nUnt <- 0L; p$.nSig <- length(sos); p$.SP <- paste0("factor:ts:", variant)
  p$.FCV <- list(variant = variant)
  for (s in sos) { e <- new.env(parent = p); e$.so <- s; if (length(cnt_line)) eval(parse(text = cnt_line), e)
                   if (!identical(s$model, "ts")) p$.nFB <- p$.nFB + 1L }
  err <- tryCatch({ if (length(grd_line)) eval(parse(text = grd_line), new.env(parent = p)); NULL }, error = function(e) conditionMessage(e))
  list(nVFB = p$.nVFB, nUnt = p$.nUnt, err = err)
}
c_maj <- if (length(l_cnt) == 1L && length(l_grd) == 1L) run_counts(list(so_fb, so_fb, so_fb, so_ok, so_ok), "dd_state") else list(err = NULL, nVFB = NA)
chk("F2 [처치 미전달] 변형이 base 로 떨어진 신호일 3/5(과반) → 멈춘다 · 폴백 3 으로 센다",
    identical(c_maj$nVFB, 3L) && !is.null(c_maj$err) && grepl("처치 미전달", c_maj$err), c_maj$err %||% sprintf("멈추지 않았다(폴백 %s)", c_maj$nVFB))
c_min <- if (length(l_cnt) == 1L && length(l_grd) == 1L) run_counts(list(so_fb, so_fb, so_ok, so_ok, so_ok), "dd_state") else list(err = "문장 없음", nVFB = NA)
chk("F3 소수(2/5)면 진행하고 센다(기존 pca 폴백 과반 규칙과 같은 문턱)", identical(c_min$nVFB, 2L) && is.null(c_min$err), c_min$err %||% "")
so_b <- FE$rfc_sigma_ctx(mkS(FRn), cfg, "base")
c_base <- if (length(l_cnt) == 1L) run_counts(list(so_b, so_b, so_b), "base") else list(err = "문장 없음", nUnt = NA)
chk("F4 base 변형은 집계 0 · 가드 미발화(기본 경로 동작 불변)", identical(c_base$nUnt, 0L) && is.null(c_base$err), c_base$err %||% "")
c_mut <- if (length(l_cnt) == 1L) run_counts(list(so_fb, so_fb, so_fb, so_ok, so_ok), "dd_state", cnt_line = "invisible(NULL)") else list(err = "x")
chk("F5 [돌연변이 red] 집계 문장 제거 → F2 칸이 멈추지 않는다(집계가 유일한 방어선)", is.null(c_mut$err), c_mut$err %||% "")
chk("F6 [배선] 요약 줄에 변형 폴백 수가 실린다", grepl("변형 폴백 %d", etxt, fixed = TRUE))

## G1~G3: cdar_nu_rule 은 그 규칙을 읽는 arm 이 아니면 멈춘다(sigma_provider 탐침과 같은 모양 · 양성 대조 = test_rf_cdar_bench_budget.R [8] CUZ 어댑터)
g1 <- run_cell(base_spec(weighting = c(WC, list(cdar_nu_rule = "ew"))))
chk("G1 [처치 미전달] 규칙을 안 읽는 arm(lean:ivol)에 cdar_nu_rule = ew → 멈춘다(조용한 무시 · 별도 칸 계상 금지)",
    !is.null(g1$err) && grepl("cdar_nu_rule", g1$err, fixed = TRUE) && grepl("처치 미전달", g1$err, fixed = TRUE), g1$err %||% "멈추지 않았다")
g2 <- run_cell(base_spec(weighting = c(WC, list(cdar_nu_rule = "bench"))))
chk("G2 [처치 미전달] cdar_nu_rule = bench 도 같은 arm 에서 멈춘다", !is.null(g2$err) && grepl("처치 미전달", g2$err, fixed = TRUE), g2$err %||% "멈추지 않았다")
mG <- mut_engine("        if (.nNuP > 0L && .nNuSame == .nNuP) stop(", "        if (FALSE) stop(")
rg <- if (is.null(mG)) list(err = "치환 불성사") else run_cell(base_spec(weighting = c(WC, list(cdar_nu_rule = "ew"))), engine = mG)
chk("G3 [돌연변이 red] 전달 가드 삭제 → G1 칸이 조용히 완주한다(치환 1곳 성사 · 가드가 유일한 방어선)", !is.null(mG) && is.null(rg$err), rg$err %||% "")

cat(sprintf("\n%s\n", toJSON(list(test = "test_scn_rx_construct_link", pass = PASS, fail = FAIL, total = PASS + FAIL, skipped = SKIP), auto_unbox = TRUE)))
quit(status = if (FAIL > 0L) 1L else 0L)
