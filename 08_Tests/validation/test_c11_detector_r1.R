#!/usr/bin/env Rscript
# =============================================================================
# test_c11_detector_r1.R — lookahead_detector C11 계보 분석기 r1 수리 + ast_verify AS_OF 해외 클램프 (양방향)
# =============================================================================
# 막는 결함(V6 BLOCKING · 통합 검증):
#   B1 구판이 잡던 결합 형태를 신판(S6)이 통과시켰다 — setkey X[Y] · match · findInterval · approx · 이름 벡터 조회 ·
#      Date == d 루프 · between · substr 월 조회 · Date < d + 1 · Date <= d - 0L · 실파일 regime_derivatives.R(소문자
#      fred_cache · macro_regime.parquet · else 가지의 빈 표가 계보를 지움).
#   B2 lag 증거가 결합된 계열 열에 묶이지 않았다 — 무관한 열의 shift(ret_prev)·차분(dVIX = VIX − shift(VIX))을 lag 로
#      인정 · 파이썬은 파일 어디든 .shift(1) 이면 lag · fred_asof_join 을 한 번 부르면 파일 전체 면제 · .loc[:d] 누락.
#   B3 ast_verify.py 의 '해외 계열에 AS_OF 관측일 클램프 불인정' 을 되돌려도 기존 스위트가 초록이었다.
# 방법: 합성 픽스처(판정서 V-08 형태의 변형) — 위반 픽스처는 C11 코드로 빨개지고, 적합 대조(가용시점 층 경유·계열
#   열 lag)는 깨끗해야 한다. 규칙마다 검출기 사본에서 그 규칙만 끈 돌연변이가 해당 픽스처를 놓쳐야(red) 한다.
# 쓰기: tempdir() 만. 실행: Rscript 08_Tests/validation/test_c11_detector_r1.R (R_ENVIRON_USER=<빈 파일> 권장)
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))
.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
DET   <- file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")
ASTV  <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")
FAPY  <- file.path(ROOT, "02_Infrastructure/data/fred_availability.py")
RULES <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
skip <- function(axis, reason) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason); cat("  SKIP ", axis, "—", reason, "\n") }
`%||%` <- function(a, b) if (is.null(a)) b else a
TD <- normalizePath(file.path(tempdir(), paste0("c11det_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(file.path(TD, "fx"), recursive = TRUE, showWarnings = FALSE)
for (p in c(DET, ASTV, FAPY, RULES)) ok(file.exists(p), paste("존재", basename(p)))
options(lookahead.c11_rules = RULES)
load_det <- function(f) { e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(f, envir = e))); e }
mutant <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(TD, paste0(tag, "_", basename(src))); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}

H <- c('m <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
       'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]')
BAD <- list(                                                     # 위반(빨개져야 한다)
  lt_plus1   = c(H, 'last_v <- v[Date < sig_d + 1][Date == max(Date)]$VIX'),
  setkey_xy  = c(H, 'setkey(v, Date)', 'setkey(RW, Date)', 'RW <- v[RW]'),
  match      = c(H, 'RW[, VIX := v$VIX[match(Date, v$Date)]]'),
  findint    = c(H, 'idx <- findInterval(as.numeric(RW$Date), as.numeric(v$Date))', 'RW$VIX <- v$VIX[idx]'),
  approx     = c(H, 'RW$VIX <- approx(v$Date, v$VIX, xout = RW$Date, method = "constant", rule = 2)$y'),
  named_vec  = c(H, 'lk <- setNames(v$VIX, as.character(v$Date))', 'RW[, VIX := lk[as.character(Date)]]'),
  eq_loop    = c(H, 'for (d in kr_dates) {', '  val <- v[Date == d, VIX]', '}'),
  between    = c(H, 'w <- v[between(Date, sig_d - 250, sig_d)]', 'beta <- cov(w$VIX, w$x)'),
  substr_ym  = c('mr <- as.data.table(read_parquet(FRED_REGIME_CACHE))', 'for (i in seq_len(n)) {',
                 '  row_i <- mr[substr(Date, 1, 7) == daily_ym[i]]', '}'),
  minus_zero = c(H, 'last_v <- v[Date <= sig_d - 0L][Date == max(Date)]$VIX'),
  shift_other= c(H, 'RW <- merge(RW, v, by = "Date")', 'RW[, ret_lag := shift(ret, 1L), by = Ticker]'),
  diff_same  = c(H, 'v[, dVIX := VIX - shift(VIX, 1L)]', 'RW <- merge(RW, v, by = "Date", all.x = TRUE)'),
  merge_ret  = c('build <- function(RAWDATA, CACHE_DIR) {', '  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
                 '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]', '  RAWDATA <- merge(RAWDATA, vix, by = "Date", all.x = TRUE)',
                 '  RAWDATA[, ret := Close / shift(Close) - 1, by = Ticker]', '  RAWDATA', '}'),
  branch_lc  = c('f <- function(drv, fred_regime = NULL) {', '  if (is.null(fred_regime)) {',
                 '    fred_cache <- file.path(CACHE_DIR, "macro_regime.parquet")',
                 '    if (file.exists(fred_cache)) { fred_regime <- as.data.table(read_parquet(fred_cache)) } else { fred_regime <- data.table() }',
                 '  }', '  fs <- fred_regime[, .(Date, Macro_Risk_Score)]', '  setkey(fs, Date)', '  fs[drv, roll = TRUE]', '}'))
BADPY <- list(
  py_import_bypass = c('import pandas as pd', 'import fred_availability as fa', 'nf = fa.fred_asof_join(kr, nf_raw, "NFCI", mode="decision_close")',
                       'f = pd.read_parquet("fred_macro_wide.parquet")', 'out = kr.merge(f[["Date", "VIXCLS"]], on="Date", how="left")'),
  py_loc_slice     = c('import pandas as pd', 'f = pd.read_parquet("fred_macro_wide.parquet").set_index("Date")',
                       'vals = [f.loc[:d, "VIXCLS"].iloc[-1] for d in kr_dates]'),
  py_shift_other   = c('import pandas as pd', 'f = pd.read_parquet("fred_macro_wide.parquet")', 'kr["ret_prev"] = kr.groupby("Ticker")["ret"].shift(1)',
                       'out = kr.merge(f[["Date", "VIXCLS"]], on="Date", how="left")'))
GOOD <- list(                                                    # 적합 대조(깨끗해야 한다)
  asof_layer = c('source(file.path(QM_ROOT, "02_Infrastructure/data/fred_availability.R"))', H,
                 'j <- fred_asof_join(RW$Date, v[, .(Date, Value = VIX)], "VIXCLS", mode = "decision_close")', 'RW[, VIX := j$value]'),
  col_lag    = c(H, 'v[, VIX := shift(VIX, 1L)]', 'RW <- merge(RW, v, by = "Date", all.x = TRUE)'),
  lt_strict  = c(H, 'last_v <- v[Date < sig_d][Date == max(Date)]$VIX'),
  no_fred    = c('RAWDATA[, VIX_chg := VIX - shift(VIX, 1L), by = Ticker]', 'beta <- RAWDATA[, cov(ret, VIX_chg)]'),
  # 판정서 1-6 '1개월 shift 판 적합'(STR_1563 형태): 순수 해외 표의 새 열 = 다른 열의 lag → 같은 달 조회해도 lag 열만 쓴다
  pure_newcol_lag = c('mr <- as.data.table(read_parquet(FRED_REGIME_CACHE))', 'mu <- mr[, .(YM, Macro_Risk_Score)][!duplicated(YM)]',
                      'mu[, prev_MRS := shift(Macro_Risk_Score, 1, type = "lag")]', 'row <- mu[YM == sig_ym]', 'risk <- row$prev_MRS[1]'),
  # 순수 해외 표(원천 VIX 에서만 파생)의 다른 이름 열 lag(xl := shift(x)) → 결합에 lag 열만 싣는다 = 일간 class1 적합
  pure_col_lag_vix = c('m <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
                       'v <- m[Series_ID == "VIXCLS", .(Date, x = Value)]', 'v[, xl := shift(x, 1L)]',
                       'RW <- merge(RW, v[, .(Date, xl)], by = "Date", all.x = TRUE)'))
GOODPY <- list(
  py_layer_only = c('import pandas as pd', 'import fred_availability as fa', 'f = pd.read_parquet("fred_macro_wide.parquet")',
                    'j = fa.fred_asof_join(kr_dates, f[["Date", "VIXCLS"]].rename(columns={"VIXCLS": "Value"}), "VIXCLS", mode="decision_close")',
                    'out = kr.merge(j, left_on="Date", right_on="kr_date", how="left")'),
  py_col_lag    = c('import pandas as pd', 'f = pd.read_parquet("fred_macro_wide.parquet")', 'f["VIXCLS"] = f["VIXCLS"].shift(1)',
                    'out = kr.merge(f[["Date", "VIXCLS"]], on="Date", how="left")'))
wr <- function(L, ext) lapply(names(L), function(nm) { f <- file.path(TD, "fx", paste0(nm, ext)); writeLines(L[[nm]], f, useBytes = TRUE); f })
FB <- setNames(wr(BAD, ".R"), names(BAD)); FBP <- setNames(wr(BADPY, ".py"), names(BADPY))
FG <- setNames(wr(GOOD, ".R"), names(GOOD)); FGP <- setNames(wr(GOODPY, ".py"), names(GOODPY))
c11_hit <- function(D, f) {
  r <- tryCatch(D$detect_lookahead(f, verbose = FALSE), error = function(e) NULL)
  if (is.null(r)) return(NA)
  any(grepl("C11_(FRED_SAMEDATE|PUB_LAG)", vapply(r$violations, function(v) v$check %||% "", "")))
}

cat("\n── A. 현판 검출기: 위반 빨강 · 적합 초록 ──\n")
D0 <- load_det(DET)
for (nm in names(FB))  ok(isTRUE(c11_hit(D0, FB[[nm]])),  sprintf("A-bad %s → C11 위반 검출", nm))
for (nm in names(FBP)) ok(isTRUE(c11_hit(D0, FBP[[nm]])), sprintf("A-bad %s(py) → C11 위반 검출", nm))
for (nm in names(FG))  ok(identical(c11_hit(D0, FG[[nm]]), FALSE),  sprintf("A-good %s → C11 위반 없음(과잉 검출 통제)", nm))
for (nm in names(FGP)) ok(identical(c11_hit(D0, FGP[[nm]]), FALSE), sprintf("A-good %s(py) → C11 위반 없음", nm))
RD <- file.path(ROOT, "02_Infrastructure/regime/regime_derivatives.R")
if (file.exists(RD)) ok(isTRUE(c11_hit(D0, RD)), "A-real regime_derivatives.R(macro_regime roll 결합) → 판정 불가 = 위반 표면(fail-closed · 구판과 같게)") else
  skip("A-real", "regime_derivatives.R 부재")

cat("\n── B. 돌연변이: 규칙을 하나씩 끄면 그 픽스처를 놓친다(red) ──\n")
MUT <- list(
  list(tag = "no_align", old = "if (!is_join && grepl(P$align, nostr, perl = TRUE)) is_join <- TRUE", new = "if (FALSE) is_join <- TRUE",
       miss = c("match", "findint", "approx", "named_vec", "eq_loop", "between", "substr_ym")),
  list(tag = "no_dtjoin", old = "if ((fo && (!is.null(si) || keyed)) || (fi && !is.null(so))) { is_join <- TRUE; break }", new = "if (FALSE) break",
       miss = c("setkey_xy")),
  list(tag = "untied_shift", old = "(if (is.null(names)) .la_c11_shift_lag(code, nostr) else .la_c11_shift_lag_on(code, nostr, names))",
       new = ".la_c11_shift_lag(code, nostr)", miss = c("shift_other", "diff_same", "merge_ret")),
  list(tag = "lt_plus", old = "(?![^\\\\]\\\\[,&|;)]*\\\\+\\\\s*[0-9]*[1-9])\",", new = "\",", miss = c("lt_plus1")),
  list(tag = "branch_erase", old = "keep_old <- !is.null(s_old) && identical(s_old$kind, \"data\") && isTRUE(s_old$fred)",
       new = "keep_old <- FALSE", miss = c("branch_lc")),
  list(tag = "py_any_shift", old = "lag_file <- grepl(lag_rx, code_all, perl = TRUE)",
       new = "lag_file <- grepl(\"\\\\.shift\\\\s*\\\\(\\\\s*(periods\\\\s*=\\\\s*)?[1-9]|\\\\.shift\\\\s*\\\\(\\\\s*\\\\)\", code_all, perl = TRUE)",
       miss = c("py_shift_other")),
  list(tag = "py_file_exempt", old = "    fv <- .la_c11_py_fred_vars(cl, nl)\n", new = "    fv <- character(0)\n", miss = c("py_import_bypass")),
  list(tag = "py_no_loc", old = "|\\\\.loc\\\\s*\\\\[\\\\s*:\\\\s*[A-Za-z_]\",", new = "\",", miss = c("py_loc_slice")))
ALLF <- c(FB, FBP)
# 반대 방향(과잉 검출 통제의 돌연변이): 순수 해외 표 열 lag 인정을 끄면 적합 대조가 빨개진다(= 규칙이 실제로 그 대조를 지킨다)
fP <- mutant(DET, "tp <- !is.null(tgt) && identical(tgt$kind, \"data\") && isTRUE(tgt$fred) && isTRUE(tgt$pure)", "tp <- FALSE", "no_pure")
if (is.na(fP)) ok(FALSE, "B no_pure 돌연변이 대상 줄 부재") else
  ok(isTRUE(c11_hit(load_det(fP), FG[["pure_col_lag_vix"]])), "B no_pure ★red(반대 방향): 순수 해외 표 열 lag 인정 삭제 → pure_col_lag_vix 오검출")
for (mu in MUT) {
  f <- mutant(DET, mu$old, mu$new, mu$tag)
  if (is.na(f)) { ok(FALSE, sprintf("B %s 돌연변이 대상 줄 부재(규칙 좌표가 바뀌었다 — 검사 갱신 필요)", mu$tag)); next }
  Dm <- tryCatch(load_det(f), error = function(e) NULL)
  if (is.null(Dm)) { ok(FALSE, sprintf("B %s 돌연변이 적재 실패", mu$tag)); next }
  missed <- mu$miss[vapply(mu$miss, function(k) identical(c11_hit(Dm, ALLF[[k]]), FALSE), logical(1))]
  ok(length(missed) >= 1L, sprintf("B %s ★red: 규칙을 끄면 %s 중 %d개를 놓친다(%s)", mu$tag, paste(mu$miss, collapse = ","),
                                   length(missed), paste(missed, collapse = ",")))
}

cat("\n── C. ast_verify: 해외 계열 AS_OF 관측일 클램프 불인정 ──\n")
PY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(PY) || !file.exists(PY)) PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")
if (!file.exists(PY)) skip("C", "파이썬 부재") else {
  pkg <- function(series) {
    f <- file.path(TD, paste0("pkg_", series, ".json"))
    writeLines(toJSON(list(strategy_id = "x", pit = list(sig_date = "2026-09-04", decision_ts = "2026-09-07"),
                           ast = list(op = "AS_OF", rule = "date<=t",
                                      children = list(list(leaf = "FIELD", group_id = "E1_fred_macro_raw", field = "Value", series = series)))),
                      auto_unbox = TRUE), f)
    f
  }
  verdict <- function(script, series) {
    out <- file.path(TD, paste0("out_", basename(dirname(dirname(script))), "_", series, ".json"))
    Sys.setenv(PYTHONDONTWRITEBYTECODE = "1")
    invisible(suppressWarnings(system2(PY, c(shQuote(script), shQuote(pkg(series)), "--out", shQuote(out),
                                             "--registry", shQuote(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json")),
                                             "--map", shQuote(file.path(ROOT, "06_Registry/ast_field_map_v0.json")),
                                             "--fred-rules", shQuote(RULES),
                                             "--quarantine", shQuote(file.path(ROOT, "06_Registry/pit_quarantine.json"))),
                                   stdout = TRUE, stderr = TRUE)))
    if (!file.exists(out)) return(NA_character_)
    fromJSON(out)$verdict
  }
  v_nfci <- verdict(ASTV, "NFCI"); v_vix <- verdict(ASTV, "VIXCLS")
  ok(identical(v_nfci, "FAIL_LOOKAHEAD"), sprintf("C1 NFCI(금 09-04 라벨)를 AS_OF(date<=t)로 감싸도 결정 09-07 에 FAIL_LOOKAHEAD — %s", v_nfci))
  ok(!is.na(v_vix) && !identical(v_vix, "FAIL_LOOKAHEAD"), sprintf("C2 적합 대조: VIXCLS(미국 09-04 → 한국 09-07 가용)는 통과 — %s", v_vix))
  # 돌연변이: 해외 계열 클램프 불인정을 되돌린 사본(임시 트리 ast/·data/)
  MT <- file.path(TD, "astmut"); dir.create(file.path(MT, "ast"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(MT, "data"), recursive = TRUE, showWarnings = FALSE)
  file.copy(FAPY, file.path(MT, "data", "fred_availability.py"), overwrite = TRUE)
  t <- paste(readLines(ASTV, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  old <- "if clamp_asof and kind == \"c11_fred\":"
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) ok(FALSE, "C-mut 대상 줄 부재") else {
    writeLines(sub(old, "if False:", t, fixed = TRUE), file.path(MT, "ast", "ast_verify.py"), useBytes = TRUE)
    v_m <- verdict(file.path(MT, "ast", "ast_verify.py"), "NFCI")
    ok(!is.na(v_m) && !identical(v_m, "FAIL_LOOKAHEAD"), sprintf("C-mut ★red: 클램프 불인정 삭제 → NFCI AS_OF 가 통과로 바뀐다 — %s", v_m))
  }
}

cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
cat(as.character(toJSON(list(test = "test_c11_detector_r1", pass = P, fail = FL, total = P + FL,
                             skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
quit(status = if (FL > 0L || length(SKIPS) > 0L) 1L else 0L, save = "no")
