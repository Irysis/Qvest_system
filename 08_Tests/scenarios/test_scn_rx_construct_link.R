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

## 기존 칸 사양의 결과 불변 기준 = 고정 골든 지문(2026-11-10 감사 U13 수리 — 구판은 git HEAD 엔진과 비교해 커밋 뒤 자기 자신과의 비교가 됐다).
##   값 = 선택지 도입 직전 엔진(98b679826 = 9a35a915b^)과 수리 전 HEAD(f6622318f) 둘 다로 이 픽스처를 돌려 얻은 PORTFOLIO 지문(두 판 일치 실측).
##   지문 = 행 수 : md5(Date, Ticker, Weight 의 16진 부동소수 표기(%a · 비트 정확), Leg 를 (Date, Ticker) 순으로 한 줄씩).
##   픽스처 날짜 = 운영 요인 수익 거래일(real) 또는 합성 평일(synth) — 두 경우를 각각 고정한다(SCN_FORCE_SYNTH_DATES=1 이면 synth 강제).
##   ★이 값이 바뀌면 기존 칸 결과가 바뀐 것이다 — 엔진만이 아니라 카탈로그 · 하네스 변경도 잡는다(의도한 변경이면 근거와 함께 새 값으로).
GOLDEN <- list(real  = c(`lean:ivol` = "1500:690f47d3eada66dfca4f4c7771715d91", `paper:ERCMRT2010` = "1500:4da66bcc54d19adae0e62004194d16d4"),
               synth = c(`lean:ivol` = "1500:fd4b85e8620665e2bfb4e7a9681a2ff1", `paper:ERCMRT2010` = "1500:c7809fd0e187c92f53b02db115142809"))
port_fp <- function(P) { if (is.null(P)) return(NA_character_); X <- P[order(Date, Ticker)]
  f <- tempfile("scn_fp_"); writeLines(paste(format(X$Date), X$Ticker, sprintf("%a", as.numeric(X$Weight)), X$Leg, sep = ","), f, useBytes = TRUE)
  paste0(nrow(X), ":", unname(tools::md5sum(f))) }

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
REAL_DATES <- length(DATES) > 1000L && !nzchar(Sys.getenv("SCN_FORCE_SYNTH_DATES", ""))
if (!REAL_DATES) { DATES <- seq(as.Date("2003-06-02"), as.Date("2009-12-30"), by = "day"); DATES <- DATES[as.integer(format(DATES, "%w")) %in% 1:5] }
FIX <- make_fixture(DATES)
BMF <- { t <- copy(FIX); setorder(t, Ticker, Date); t[, r := Close / shift(Close, 1L) - 1, by = Ticker]; t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }
PX <- list(kind = "price", id = "lowvol60")
base_spec <- function(...) modifyList(list(code = "SCN", label = "scn", block = "T", fixed_axes = AXES, base_signal = list(kind = "mom_12_1"),
                                           factor2 = PX, weighting = list(kind = "ew"), universe = list(kind = "k200_kq150")), list(...))
run_cell <- function(spec, engine = ENGINE, afn = NULL, bm = BMF) {
  p <- tempfile("scn_spec_", fileext = ".json"); writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  Sys.setenv(RF_CELL_SPEC = p); on.exit(Sys.unsetenv("RF_CELL_SPEC"))
  env <- new.env(); assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", bm, envir = env); err <- NULL
  if (!is.null(afn)) assign(".TEST_AFN", afn, envir = env)   # 주입 엔진 사본(inj_engine)만 읽는다 — 운영 엔진은 이 이름을 모른다
  logs <- utils::capture.output(suppressWarnings(suppressMessages(tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, logs = logs, P = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) get("PORTFOLIO", envir = env) else NULL)
}
same_port <- function(a, b) !is.null(a$P) && !is.null(b$P) && isTRUE(all.equal(a$P[order(Date, Ticker)], b$P[order(Date, Ticker)], tolerance = 0, check.attributes = FALSE))

cat("== (a) 기존 칸 사양 결과 불변 ==\n")
WC <- list(kind = "catalog", catalog_id = "lean:ivol")
GM <- GOLDEN[[if (REAL_DATES) "real" else "synth"]]
r_new <- run_cell(base_spec(weighting = WC))
chk(sprintf("A1 카탈로그 lean:ivol — 고정 골든 지문(%s 날짜)과 PORTFOLIO 비트 동일", if (REAL_DATES) "real" else "synth"),
    is.null(r_new$err) && identical(port_fp(r_new$P), GM[["lean:ivol"]]), r_new$err %||% sprintf("지문 %s ≠ %s", port_fp(r_new$P), GM[["lean:ivol"]]))
r_exp <- run_cell(base_spec(weighting = c(WC, list(sigma_provider = "sample", allow_cash = FALSE, lean_n_days = "native"))))
chk("A2 기본값을 명시해도(sample · allow_cash false · native) 골든과 비트 동일", is.null(r_exp$err) && identical(port_fp(r_exp$P), GM[["lean:ivol"]]), r_exp$err %||% port_fp(r_exp$P))
WE <- list(kind = "catalog", catalog_id = "paper:ERCMRT2010")
e_new <- run_cell(base_spec(weighting = WE))
chk("A3 Σ 를 쓰는 arm(paper:ERCMRT2010) 표본 Σ 기본 — 골든과 비트 동일", is.null(e_new$err) && identical(port_fp(e_new$P), GM[["paper:ERCMRT2010"]]), e_new$err %||% port_fp(e_new$P))
## A4 [양성 대조] 지문은 결과 변화를 잡는다 — 비중 한 칸을 2⁻⁵² 상대만큼 바꾸면 지문이 달라진다(동어반복 비교가 아님)
P4 <- copy(r_new$P); if (!is.null(P4) && nrow(P4)) P4[1L, Weight := Weight * (1 + .Machine$double.eps)]
chk("A4 [양성 대조] 비중 1칸 1 ulp 교란 → 지문 불일치(골든 비교가 공허하지 않다)", !is.null(P4) && !identical(port_fp(P4), GM[["lean:ivol"]]))

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

## ── (h)~(l) 2026-11-10 감사 U13 — 칸이 선언한 처치가 포트폴리오에 안 닿으면 멈춘다(조용한 다른 것으로의 대체 금지) ──
##   주입 엔진 사본: '.afn <- .row$adapter_fn[[1]]' 한 줄만 '.TEST_AFN 이 있으면 그것' 으로 바꾼다(치환 1곳 단정) — 등록부에 아직 없는
##   낙폭 예산 어댑터(CUZ 2005 · rf_cdar_construct.R)를 카탈로그 행(lean:ivol) 자리에 끼워 엔진의 실제 루프 · 가드를 태운다.
INJ_FROM <- "      .afn <- .row$adapter_fn[[1]]"
inj_engine <- function(extra = list(), src = etxt) {
  pairs <- c(list(c(INJ_FROM, "      .afn <- if (exists(\".TEST_AFN\", inherits = FALSE)) .TEST_AFN else .row$adapter_fn[[1]]")), extra)
  hits <- integer(0)
  for (p in pairs) { hits <- c(hits, lengths(regmatches(src, gregexpr(p[1], src, fixed = TRUE)))); src <- sub(p[1], p[2], src, fixed = TRUE) }
  if (any(hits != 1L)) return(NULL)
  f <- tempfile("rf_cell_engine_inj_", fileext = ".R"); writeLines(src, f, useBytes = TRUE); f
}
CDAR_SRC <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cdar_construct.R")
ADP_SRC  <- file.path(ROOT, "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R")
MRE <- new.env(parent = globalenv()); suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/methods/method_registry.R"), envir = MRE))
load_cuz <- function(cdar_path = CDAR_SRC) {   # 어댑터 사본(모듈 경로만 바꿈) → 판 표식 arm 과 같은 래퍼(budget = le)
  s <- readLines(ADP_SRC, warn = FALSE, encoding = "UTF-8")
  i <- grep('source(file.path(.cuz_root, "02_Infrastructure", "reinforcement", "rf_cdar_construct.R"), local = TRUE)', s, fixed = TRUE)
  if (length(i) != 1L) return(NULL)
  s[i] <- sprintf('source("%s", local = TRUE)', gsub("\\\\", "/", cdar_path))
  f <- tempfile("cuz_", fileext = ".R"); writeLines(s, f, useBytes = TRUE); e <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(f, envir = e))))
  MRE$wrap_adapter(get("method_weights", e), "CDaRCapCUZ2005", ub = 1, budget = "le")
}
CUZ <- load_cuz(); IE <- inj_engine()
n_cash_days <- function(P) if (is.null(P)) NA_integer_ else P[, sum(Weight), by = Date][V1 < 1 - 1e-6, .N]
WI <- list(kind = "catalog", catalog_id = "lean:ivol")   # 주입 사본에서는 행 확인용 자리(비중은 .TEST_AFN 이 낸다)
BM_FLAT <- BMF[, .(Date, BM_Ret = 0.0005)]               # 낙폭 0 인 벤치 — Σw = 1 로는 어떤 후보 묶음도 예산(ν = 0)을 못 맞춘다
BM_SOFT <- BMF[, .(Date, BM_Ret = BM_Ret * 0.3)]         # 같은 경로 · 진폭 30% — 현금(Σw ≤ 1)으로만 맞는 예산
chk("H0 [배선] 주입 엔진 사본 치환 1곳 · CUZ 어댑터 적재", !is.null(IE) && is.function(CUZ))

cat("== (h) weighting 닫힌 어휘 — 읽지 않는 kind 의 선택지 · 오타 키 = 멈춤 ==\n")
h1 <- run_cell(base_spec(weighting = list(kind = "ew", allow_cash = TRUE)))
chk("H1 {kind: ew, allow_cash: true} → 멈춘다(ew 가지는 선택지를 안 읽는다 · 부모와 같은 포트폴리오를 '현금 칸'으로 재지 않는다)",
    !is.null(h1$err) && grepl("읽지 않는 키", h1$err, fixed = TRUE) && grepl("allow_cash", h1$err, fixed = TRUE), h1$err %||% "멈추지 않았다")
h2 <- run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L, cdar_nu_rule = "bench")))
chk("H2 {kind: inv_vol, cdar_nu_rule: bench} → 멈춘다", !is.null(h2$err) && grepl("cdar_nu_rule", h2$err, fixed = TRUE), h2$err %||% "멈추지 않았다")
h3 <- run_cell(base_spec(weighting = c(WC, list(alow_cash = TRUE))))
chk("H3 catalog 오타 키(alow_cash) → 멈춘다(기본 Σw = 1 로 조용히 측정 금지)", !is.null(h3$err) && grepl("alow_cash", h3$err, fixed = TRUE), h3$err %||% "멈추지 않았다")
h4 <- run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L, label = "iv60")))
chk("H4 [음성 대조] 어휘 안 키(inv_vol window · label)는 통과", is.null(h4$err), h4$err %||% "")
mH <- mut_engine("  if (length(.wbad)) stop(", "  if (FALSE) stop(")
rh <- if (is.null(mH)) list(err = "치환 불성사") else run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L, cdar_nu_rule = "bench")), engine = mH)
chk("H5 [돌연변이 red] 어휘 가드 삭제 → H2 칸이 조용히 완주한다(치환 1곳 · 가드가 유일한 방어선)", !is.null(mH) && is.null(rh$err), rh$err %||% "")
rh6 <- if (is.null(mH)) list(err = "치환 불성사") else run_cell(base_spec(weighting = list(kind = "ew", allow_cash = TRUE)), engine = mH)
chk("H6 [이중 방어] 어휘 가드를 지워도 ew + allow_cash 는 최종 비중 현금 재확인이 멈춘다", !is.null(mH) && !is.null(rh6$err) && grepl("최종 비중", rh6$err, fixed = TRUE), rh6$err %||% "멈추지 않았다")

cat("== (i) allow_cash + cap_core — 합성이 구성 층 현금을 지우면 멈춘다 ==\n")
WCASH <- c(WI, list(allow_cash = TRUE, cdar_nu_rule = "bench"))
i0 <- if (is.null(IE)) list(err = "주입 불가") else run_cell(base_spec(weighting = WCASH), engine = IE, afn = CUZ, bm = BM_SOFT)
chk("I0 [양성 대조] 낙폭 예산 + allow_cash(cap_core 없음) → 완주 · 최종 비중에 현금 신호일 > 0", is.null(i0$err) && isTRUE(n_cash_days(i0$P) > 0L), i0$err %||% sprintf("현금일 %s", n_cash_days(i0$P)))
i1 <- if (is.null(IE)) list(err = "주입 불가") else run_cell(base_spec(weighting = WCASH, cap_core = list(k = 2L)), engine = IE, afn = CUZ, bm = BM_SOFT)
chk("I1 allow_cash + cap_core(k = 2) → 멈춘다(위성 재정규화가 현금을 지운다 · 처치 미전달)", !is.null(i1$err) && grepl("cap_core", i1$err, fixed = TRUE) && grepl("allow_cash", i1$err, fixed = TRUE), i1$err %||% sprintf("멈추지 않았다(최종 현금일 %s)", n_cash_days(i1$P)))
IE2 <- inj_engine(list(c("if (!is.null(.CC) && .CASH_DECL) stop(", "if (FALSE) stop(")))
i2 <- if (is.null(IE2)) list(err = "치환 불성사") else run_cell(base_spec(weighting = WCASH, cap_core = list(k = 2L)), engine = IE2, afn = CUZ, bm = BM_SOFT)
chk("I2 [이중 방어] 조합 가드를 지운 사본 → 최종 비중 현금 재확인이 멈춘다", !is.null(IE2) && !is.null(i2$err) && grepl("최종 비중", i2$err, fixed = TRUE), i2$err %||% "멈추지 않았다")
IE3 <- inj_engine(list(c("if (!is.null(.CC) && .CASH_DECL) stop(", "if (FALSE) stop("), c("  if (.nCashF == 0L) stop(", "  if (FALSE) stop(")))
i3 <- if (is.null(IE3)) list(err = "치환 불성사") else run_cell(base_spec(weighting = WCASH, cap_core = list(k = 2L)), engine = IE3, afn = CUZ, bm = BM_SOFT)
chk("I3 [돌연변이 red · 결함 재현] 두 가드를 다 지우면 조용히 완주하고 최종 현금 0(구성 층 현금이 사라진 채 '현금 칸'으로 측정)",
    !is.null(IE3) && is.null(i3$err) && identical(n_cash_days(i3$P), 0L), i3$err %||% sprintf("현금일 %s", n_cash_days(i3$P)))

cat("== (k) 낙폭 예산 실행 불가 → 최소 CDaR 복원을 센다 · 과반이면 멈춘다 ==\n")
WB <- c(WI, list(cdar_nu_rule = "bench"))
k1 <- if (is.null(IE)) list(err = "주입 불가") else run_cell(base_spec(weighting = WB), engine = IE, afn = CUZ, bm = BM_FLAT)
chk("K1 bench + Σw = 1 · 예산을 못 맞추는 신호일 전부 → 멈춘다(최소 CDaR 로 조용히 바뀐 칸을 '점수 최대화 s.t. CDaR ≤ 벤치' 로 채점하지 않는다)",
    !is.null(k1$err) && grepl("최소 CDaR", k1$err, fixed = TRUE) && grepl("과반", k1$err, fixed = TRUE), k1$err %||% "멈추지 않았다")
k2 <- if (is.null(IE)) list(err = "주입 불가") else run_cell(base_spec(weighting = WB), engine = IE, afn = CUZ, bm = BMF)
chk("K2 [음성 대조] 같은 칸 · 실제 같은 창 벤치(동일가중 50종) → 완주하고 복원 수를 로그에 적거나 0", is.null(k2$err), k2$err %||% "")
CDAR_M <- { s <- readLines(CDAR_SRC, warn = FALSE, encoding = "UTF-8"); h <- grepl("if (is.function(.lis)) .lis(fb)", s, fixed = TRUE)
            s[h] <- sub("if (is.function(.lis)) .lis(fb)", "if (FALSE) .lis(fb)", s[h], fixed = TRUE); f <- tempfile("cdar_m_", fileext = ".R"); writeLines(s, f, useBytes = TRUE); list(f = f, n = sum(h)) }
CUZ_M <- if (CDAR_M$n == 1L) load_cuz(CDAR_M$f) else NULL
k3 <- if (is.null(CUZ_M) || is.null(IE)) list(err = "치환 불성사") else run_cell(base_spec(weighting = WB), engine = IE, afn = CUZ_M, bm = BM_FLAT)
chk("K3 [돌연변이 red · 결함 재현] 구성 모듈의 복원 통지 한 줄 삭제(치환 1곳) → K1 칸이 조용히 완주한다", CDAR_M$n == 1L && is.null(k3$err), k3$err %||% "")

cat("== (l) lean_n_days = cell 전달 탐침 ==\n")
l2 <- run_cell(base_spec(weighting = c(WE, list(lean_n_days = "cell"))))
chk("L1 n_days 를 안 읽는 arm(paper:ERCMRT2010 · 이미 칸 창 전체를 쓴다)에 lean_n_days = cell → 멈춘다(처치 미전달 · 별도 시행 금지)",
    !is.null(l2$err) && grepl("lean_n_days", l2$err, fixed = TRUE) && grepl("처치 미전달", l2$err, fixed = TRUE), l2$err %||% "멈추지 않았다")
mL <- mut_engine("    if (.nLnSame == .nLnP) stop(", "    if (FALSE) stop(")
rl <- if (is.null(mL)) list(err = "치환 불성사") else run_cell(base_spec(weighting = c(WE, list(lean_n_days = "cell"))), engine = mL)
chk("L2 [돌연변이 red · 결함 재현] 탐침 가드 삭제 → L1 칸이 조용히 완주하고 기본 칸과 비트 동일", !is.null(mL) && is.null(rl$err) && identical(port_fp(rl$P), port_fp(e_new$P)), rl$err %||% "")

cat("== (m) 요인 Σ — 설정 요인 열 축소 신호일 집계(엔진 실제 문장 평가) ==\n")
el2 <- readLines(ENGINE, warn = FALSE, encoding = "UTF-8")
l_dc <- grep("if (identical(.so$model, \"ts\") && length(.so$diag$requested_missing)) .nDrop <<- .nDrop + 1L", el2, fixed = TRUE)
l_dg <- grep("if (.nDrop * 2L > .nSig) stop(", el2, fixed = TRUE)
chk("M0 엔진에 열 축소 집계 · 가드 문장이 각 1곳", length(l_dc) == 1L && length(l_dg) == 1L, sprintf("집계 %d · 가드 %d", length(l_dc), length(l_dg)))
run_drop <- function(sos, cnt_line = el2[l_dc]) {
  p <- new.env(parent = globalenv()); p$.nDrop <- 0L; p$.nSig <- length(sos); p$.SP <- "factor:ts:base"; p$.FCV <- list(cfg = list(factor_columns = c("MKT_TOTAL", "WML")))
  for (s in sos) { e <- new.env(parent = p); e$.so <- s; if (length(cnt_line)) eval(parse(text = cnt_line), e) }
  list(n = p$.nDrop, err = tryCatch({ if (length(l_dg)) eval(parse(text = el2[l_dg]), new.env(parent = p)); NULL }, error = function(e) conditionMessage(e)))
}
so_full <- list(model = "ts", diag = list(requested_missing = character(0))); so_drop <- list(model = "ts", diag = list(requested_missing = "WML"))
dm <- if (length(l_dc) == 1L) run_drop(list(so_drop, so_drop, so_full)) else list(n = NA, err = NULL)
chk("M1 열 축소 신호일 2/3(과반) → 멈춘다 · 2 로 센다", identical(dm$n, 2L) && !is.null(dm$err) && grepl("요인 모형 미전달", dm$err, fixed = TRUE), dm$err %||% "멈추지 않았다")
dn <- if (length(l_dc) == 1L) run_drop(list(so_drop, so_full, so_full)) else list(n = NA, err = "x")
chk("M2 소수(1/3)면 진행하고 센다(pca 폴백 과반 규칙과 같은 문턱)", identical(dn$n, 1L) && is.null(dn$err), dn$err %||% "")
dmu <- if (length(l_dc) == 1L) run_drop(list(so_drop, so_drop, so_full), cnt_line = "invisible(NULL)") else list(err = "x")
chk("M3 [돌연변이 red] 집계 문장 제거 → M1 칸이 멈추지 않는다", is.null(dmu$err), dmu$err %||% "")

cat("== (s) 서명 — 기본값과 같은 선언은 기본 칸과 같은 칸 ==\n")
SG <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = SG)
sg <- function(w) SG$.spec_sig(base_spec(weighting = w))
SIG_WC_GOLD <- "price:lowvol60|ew|{\"kind\":\"catalog\",\"catalog_id\":\"lean:ivol\"}|{\"kind\":\"k200_kq150\"}|[]|mom_12_1"
chk("S1 기존 칸 서명 불변(고정 문자열)", identical(sg(WC), SIG_WC_GOLD), sg(WC))
chk("S2 기본값 명시(cdar_nu_rule ew · allow_cash false · sample · native) = 생략과 같은 서명",
    identical(sg(c(WC, list(cdar_nu_rule = "ew"))), sg(WC)) && identical(sg(c(WC, list(allow_cash = FALSE, sigma_provider = "sample", lean_n_days = "native"))), sg(WC)))
chk("S3 처치 값(bench · allow_cash true)은 다른 서명", !identical(sg(c(WC, list(cdar_nu_rule = "bench"))), sg(WC)) && !identical(sg(c(WC, list(allow_cash = TRUE))), sg(WC)))

cat(sprintf("\n%s\n", toJSON(list(test = "test_scn_rx_construct_link", pass = PASS, fail = FAIL, total = PASS + FAIL, skipped = SKIP), auto_unbox = TRUE)))
quit(status = if (FAIL > 0L) 1L else 0L)
