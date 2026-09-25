#!/usr/bin/env Rscript
# =============================================================================
# test_c11_consumers.R — PIT C11 수리 1단계 · S4 소비자(규약 b/c) 양방향 검사
# =============================================================================
# 대상(판정서 V-06 · V-14 · ⑤-6 "소비자 4곳 규약 (b)"):
#   02_Infrastructure/validation/overlay_pit_guard.R (C11 층 — 가용일 결합·HARD 검사)
#   02_Infrastructure/regime/apply_regime_overlay.R · 02_Infrastructure/portfolio/regime_module_admission.R
#   02_Infrastructure/regime/build_module_performance.R · 04_Research/factor_rotation/run_wf_ensemble.R
#   02_Infrastructure/contracts/regime_label_gate.R · 02_Infrastructure/backtest_harness.R(regime_tilt·load_macro_regime)
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md ② (a)(b)(c)
# 원칙:
#   · 합성 픽스처 — 기대값은 검사 대상과 **독립인** 손 유도(루프)로 만든다. 국면 값의 가용일 = 한국 다음 거래일
#     (VIX 류 '미국 d → 한국 d+1' 규약, S0 fred_avail_date 와 일치를 따로 대조).
#   · 양성 대조(수리판 = 손 유도 기대값) + 위반 주입(구판·돌연변이는 같은 픽스처에서 빨개진다).
#   · 원판 대조 = git blob 고정(수리 직전 HEAD 7ea5d8377 의 파일) — 이후 자동 커밋이 HEAD 를 옮겨도 불변.
#   · 운영 무쓰기 — 모든 산출은 tempdir 샌드박스. 자식 Rscript 는 R_ENVIRON_USER=빈 파일 + QM_ROOT/CLAUDE_PROJECT_DIR
#     = 샌드박스(~/.Renviron 이 QM_ROOT 를 운영 루트로 덮으므로). 끝에서 운영 파일 md5 불변을 단정한다.
# 실행: Rscript 08_Tests/regime/test_c11_consumers.R
#   env C11S4_CODE_ROOT = 검사할 코드 트리(기본 = 이 파일 기준 저장소) · C11S4_GIT_ROOT = git blob 을 읽을 저장소
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow); library(xts) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else "."
}, error = function(e) ".")
CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("C11S4_CODE_ROOT", ""))
if (!nzchar(CODE_ROOT)) CODE_ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(CODE_ROOT, "02_Infrastructure/validation/overlay_pit_guard.R")))
  CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
GIT_ROOT <- gsub("\\\\", "/", Sys.getenv("C11S4_GIT_ROOT", CODE_ROOT))
OPS_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", CODE_ROOT))
cat(sprintf("=== test_c11_consumers ===\n  CODE_ROOT=%s\n  GIT_ROOT=%s\n  OPS_ROOT=%s\n", CODE_ROOT, GIT_ROOT, OPS_ROOT))

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
for (.k in c("QVEST_C11_LEGACY_REGIME", "FR_MODULE_PERF", "FR_REGIME_SOURCE")) Sys.unsetenv(.k)   # 검사 프로세스의 정책 = 기본
P <- 0L; FL <- 0L; SK <- 0L; SKIPS <- list()
ok <- function(c, m) {
  if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") }
}
skip <- function(axis, reason, missing = "") {
  SK <<- SK + 1L; SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat("  SKIP ", axis, "—", reason, "\n")
}
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
finish <- function() {
  cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, SK))
  cat(as.character(toJSON(list(test = "test_c11_consumers", pass = P, fail = FL, total = P + FL,
                               skipped = SK, skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
  quit(status = if (FL > 0L) 1L else 0L, save = "no")
}

# ── 운영 무쓰기 기준선 ─────────────────────────────────────────────────────────
## 이 검사가 쓸 수 있는 운영 경로만(일간 파이프라인이 정상 갱신하는 .cache 는 대상 아님 — 동시 갱신 오탐 방지)
OPS_FILES <- file.path(OPS_ROOT, c("06_Registry/module_performance.json", "06_Registry/module_regime_admission.json",
                                   "06_Registry/pit_quarantine.json", "06_Registry/factor_rotation_registry.json"))
OPS_FILES <- OPS_FILES[file.exists(OPS_FILES)]
MD5_BEFORE <- tools::md5sum(OPS_FILES)
FR_OUT_DIR <- file.path(OPS_ROOT, "04_Research/factor_rotation/output")
FR_OUT_BEFORE <- if (dir.exists(FR_OUT_DIR)) sort(list.files(FR_OUT_DIR, recursive = TRUE)) else character(0)

TMP <- normalizePath(file.path(tempdir(), paste0("c11s4_", format(Sys.time(), "%H%M%S"), "_", Sys.getpid())),
                     winslash = "/", mustWork = FALSE)
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); file.create(EMPTY_RENV)
RSCRIPT <- file.path(R.home("bin"), "Rscript")

# ── 원판(git blob 고정) ────────────────────────────────────────────────────────
BLOB <- c(guard = "c5a6dcb226aa171c72b0b941a361712cf64bd245", aro = "d1ffc2d12e2c9d9dc794ee35c76c2dc3672dab6b",
          rma = "047eb222de858cd58cabf2af28e77181e76b6482", bmp = "3f00848af0ddd2dd193a3f6e1dd196ad8976e7b9",
          wf = "331d137a3d56a4f044ba514074fc9039ce37f75b", bh = "b1e31ccf6d25884f23208b8347b5ccc09fa3756a",
          rlg = "9369ecbec786dc822932a18de81f468c2fa89486")
blob_file <- function(key) {
  f <- file.path(TMP, paste0("orig_", key, ".R"))
  if (file.exists(f)) return(f)
  o <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(GIT_ROOT), "cat-file", "-p", BLOB[[key]]),
                                         stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
  if (is.null(o) || !is.null(attr(o, "status")) || !length(o)) return(NA_character_)
  writeLines(o, f, useBytes = TRUE)
  f
}
code <- function(rel) file.path(CODE_ROOT, rel)
load_env <- function(path, wd = CODE_ROOT, pre = list()) {
  e <- new.env(parent = globalenv())
  for (k in names(pre)) assign(k, pre[[k]], envir = e)
  owd <- setwd(wd); on.exit(setwd(owd), add = TRUE)
  suppressMessages(sys.source(path, envir = e))
  e
}
mutate_file <- function(src, old, new, tag) {
  t <- readLines(src, warn = FALSE, encoding = "UTF-8"); t <- paste(t, collapse = "\n")
  n <- lengths(regmatches(t, gregexpr(old, t, fixed = TRUE)))
  if (n != 1L) return(NA_character_)
  f <- file.path(TMP, paste0("mut_", tag, ".R"))
  writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE)
  f
}
run_child <- function(script, envs, args = character(0)) {
  keys <- names(envs)
  old <- Sys.getenv(keys, unset = NA, names = TRUE)
  on.exit(for (k in keys) {
    if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
  }, add = TRUE)
  do.call(Sys.setenv, as.list(envs))
  out <- suppressWarnings(system2(RSCRIPT, c("--no-save", shQuote(script), args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else as.integer(st), out = out)
}
child_env <- function(root, extra = list()) {
  base <- list(QM_ROOT = root, CLAUDE_PROJECT_DIR = root, R_ENVIRON_USER = EMPTY_RENV,
               QVEST_C11_LEGACY_REGIME = "", FR_MODULE_PERF = "", FR_REGIME_SOURCE = "", FR_SELECTION_TYPE = "",
               QVEST_LABEL_GATE_MODE = "warn", QVEST_TG_DRY_RUN = "1")
  for (k in names(extra)) base[[k]] <- extra[[k]]
  unlist(base)
}
cp_code <- function(root, rels) for (r in rels) {
  dir.create(dirname(file.path(root, r)), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(code(r), file.path(root, r), overwrite = TRUE)) stop("copy 실패: ", r)
}

# ── 합성 달력 · 손 유도 기대값 ─────────────────────────────────────────────────
wkdays <- function(a, b) { d <- seq(as.Date(a), as.Date(b), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] }
KR_HOL <- as.Date(c("2020-01-24", "2020-01-27"))       # 합성 한국 휴장(설)
US_HOL <- as.Date(c("2020-01-20", "2020-02-17"))       # 합성 미국 휴장(MLK · Presidents)
KR <- sort(setdiff(wkdays("2014-12-01", "2020-06-30"), KR_HOL)); KR <- as.Date(KR, origin = "1970-01-01")
US <- sort(setdiff(wkdays("2014-12-01", "2020-06-30"), US_HOL)); US <- as.Date(US, origin = "1970-01-01")
next_kr <- function(d) as.Date(vapply(as.integer(d), function(x) { k <- KR[as.integer(KR) > x]; if (length(k)) as.integer(k[1]) else NA_integer_ }, integer(1)), origin = "1970-01-01")
# 결정일 x 까지 가용한(avail <= x) 행 중 관측일이 가장 늦은 행의 값 — 검사 대상과 독립인 정의
exp_asof <- function(dec, rdate, ravail, rval) {
  out <- rep(rval[1][NA], length(dec))
  for (i in seq_along(dec)) {
    x <- dec[i]; if (is.na(x)) next
    k <- which(ravail <= x); if (!length(k)) next
    out[i] <- rval[k[which.max(rdate[k])]]
  }
  out
}
prev_row <- function(d) c(as.Date(NA), d[-length(d)])
ds <- function(x) as.character(as.Date(x))                       # 날짜 비교는 문자열로(Date 저장형 int/double 무관)
same_dt <- function(a, b) is.data.frame(a) && is.data.frame(b) && identical(names(a), names(b)) && nrow(a) == nrow(b) &&
  all(vapply(names(a), function(k) identical(a[[k]], b[[k]]), logical(1)))   # 값 비트 동일(data.table 내부 포인터 제외)

# =============================================================================
cat("\n── A. overlay_pit_guard C11 층 ──\n")
G <- load_env(code("02_Infrastructure/validation/overlay_pit_guard.R"))
pa <- data.table(Date = as.Date(c("2020-01-02", "2020-01-03", "2020-01-06")), V = c(1, 2, 3),
                 avail_date = as.Date(c("2020-01-03", "2020-01-08", "2020-01-07")))
ok(identical(G$c11_panel_status(pa, "V"), "avail_annotated") && identical(G$c11_panel_avail_col(pa, "V"), "avail_date"),
   "A1a 가용일 열(avail_date) 인식")
pa2 <- copy(pa)[, V_avail_date := avail_date + 1L]
ok(identical(G$c11_panel_avail_col(pa2, "V"), "V_avail_date"), "A1b 열별 가용일(<열>_avail_date) 우선")
ok(identical(G$c11_panel_status(pa[, .(Date, V)], "V"), "legacy_unannotated"), "A1c 가용일 열 없음 = legacy")
decA <- as.Date(c("2020-01-02", "2020-01-03", "2020-01-06", "2020-01-07", "2020-01-08"))
expA <- c(NA, 1, 1, 3, 3)
gotA <- G$c11_asof_align(decA, pa, "V")$value
ok(identical(gotA, expA), sprintf("A2a as-of 결합 손 유도 일치 (%s)", paste(gotA, collapse = ",")))
naive <- vapply(decA, function(x) { k <- which(pa$avail_date <= x); if (!length(k)) NA_real_ else pa$V[k[which.max(pa$avail_date[k])]] }, numeric(1))
ok(!identical(naive, expA), "A2b ★돌연변이 red: '가용일 최대' 선택(늦게 가용해진 옛 행이 새 행을 덮음)은 기대값과 다르다")
pa3 <- rbind(pa, data.table(Date = as.Date("2020-01-09"), V = 9, avail_date = as.Date(NA)))
ok(identical(G$c11_asof_align(as.Date("2020-01-20"), pa3, "V")$value, 3), "A2c 가용일 NA 행 = 아직 불가(결합 제외 · fail-closed)")
ok(!is.na(err_of(G$c11_asof_align(decA, rbind(pa, pa[1]), "V"))), "A2d 같은 날짜 2행 = 결합 거부")
ok(!is.na(err_of(G$c11_asof_align(decA, pa[, .(Date, V)], "V"))), "A2e legacy 패널을 가용일 결합에 넣으면 거부")
d5 <- as.Date("2020-03-02") + c(0, 1, 2, 3, 4)
ok(identical(G$c11_window_start(d5), c(as.Date(NA), d5[1:4])), "A3a 창 시작 = 직전 행")
ok(identical(G$c11_window_start(d5, 1L), c(as.Date(NA), as.Date(NA), d5[1:3])), "A3b extra_lag=1 = 한 행 더(lag1 스트레스)")
ok(!is.na(err_of(G$c11_window_start(rev(d5)))) && !is.na(err_of(G$c11_window_start(c(d5, d5[5])))) &&
   !is.na(err_of(G$c11_window_start(d5, -1L))), "A3c 역순·중복·음수 지연 = 거부")
ok(is.na(err_of(G$assert_overlay_pit_avail(d5, d5))), "A4a 가용일 = 결정일 통과(15:30 결정에 쓸 수 있음)")
e4 <- err_of(G$assert_overlay_pit_avail(d5 + 1L, d5))
ok(!is.na(e4) && grepl("C11", e4), "A4b ★위반 주입: 가용일 > 결정일 = HARD stop")
ok(!is.na(err_of(G$assert_overlay_pit_avail(d5, c(d5[1:4], NA)))), "A4c 결정일 없이 쓰인 값 = 위반")
ok(!is.na(err_of(G$assert_overlay_pit_avail(d5, d5[1:4]))), "A4d 길이 불일치 = 거부")
Sys.unsetenv("QVEST_C11_LEGACY_REGIME")
ok(identical(G$c11_legacy_policy(), "stop"), "A5a legacy 정책 기본 = stop(fail-closed)")
Sys.setenv(QVEST_C11_LEGACY_REGIME = "label")
ok(identical(G$c11_legacy_policy(), "label") && identical(G$c11_legacy_policy("stop"), "stop"), "A5b env label · 인자 우선")
Sys.setenv(QVEST_C11_LEGACY_REGIME = "maybe")
ok(!is.na(err_of(G$c11_legacy_policy())), "A5c 알 수 없는 정책 = 거부(조용한 통과 금지)")
Sys.unsetenv("QVEST_C11_LEGACY_REGIME")
eg <- err_of(G$c11_legacy_gate(pa[, .(Date, V)], "V", site = "unit"))
ok(!is.na(eg) && grepl("PITQ-C11-20260924", eg), "A5d legacy 패널 + stop = 중단(격리 id 명시)")
wg <- NULL
gl <- withCallingHandlers(G$c11_legacy_gate(pa[, .(Date, V)], "V", site = "unit2", policy = "label"),
                          warning = function(w) { wg <<- conditionMessage(w); invokeRestart("muffleWarning") })
ok(isTRUE(gl$legacy) && identical(gl$status, "unresolved_legacy_panel") && !is.null(wg), "A5e label = 진행 + 미해소 표식 + 경고")
# A6 기존 C5 4함수 본문 보존(원판 blob 대조)
fo <- blob_file("guard")
if (is.na(fo)) skip("A6", "git blob 판독 불가 — 원판 대조 생략", BLOB[["guard"]]) else {
  GO <- load_env(fo)
  for (fn in c("overlay_signal_cutoff", "holdings_signal_cutoff", "assert_overlay_pit", "overlay_lookahead_ab"))
    ok(identical(deparse(get(fn, GO)), deparse(get(fn, G))), sprintf("A6 C5 함수 보존: %s (원판과 동일)", fn))
  ok(is.na(err_of(G$assert_overlay_pit(as.Date("2020-03-01"), as.Date("2020-03-01")))) &&
     !is.na(err_of(G$assert_overlay_pit(as.Date("2020-03-02"), as.Date("2020-03-01")))), "A6b C5 동작(u==h 통과 · u>h 차단) 불변")
}
# A7 S0 도우미와 정합 — 소비자 결합 = fred_asof_join(exposure_return)
S0 <- tryCatch(load_env(code("02_Infrastructure/data/fred_availability.R")), error = function(e) NULL)
RULES <- code("06_Registry/fred_availability_rules.json")
if (is.null(S0) || !file.exists(RULES)) skip("A7", "S0 도우미/규칙 파일 부재", "fred_availability.R|rules") else {
  KRq <- KR[KR >= as.Date("2019-11-01") & KR <= as.Date("2020-04-30")]
  USq <- US[US >= as.Date("2019-10-25") & US <= as.Date("2020-04-30")]
  vix <- data.table(Date = USq, Value = 10 + seq_along(USq) %% 17)
  ann <- S0$fred_avail_annotate(vix, "VIXCLS", kr_calendar = KRq, rules = RULES)
  ok(identical(ann$avail_date[!is.na(ann$avail_date)], next_kr(ann$Date)[!is.na(ann$avail_date)]),
     "A7a 픽스처 가용일 규약(미국 d → 한국 다음 거래일) = S0 VIXCLS 규칙")
  dec7 <- G$c11_window_start(KRq)[-1]
  ok(identical(dec7, S0$fred_decision_date(KRq[-1], "exposure_return", kr_calendar = KRq)),
     "A7b 창 시작(직전 행) = S0 exposure_return 결정일")
  c7 <- G$c11_asof_align(dec7, ann, "Value")$value
  s7 <- S0$fred_asof_join(KRq[-1], vix, "VIXCLS", mode = "exposure_return", kr_calendar = KRq, rules = RULES)$value
  ok(identical(c7, s7), sprintf("A7c ★소비자 결합 = S0 fred_asof_join(exposure_return) 전 구간 일치 (n=%d)", length(c7)))
  same_day <- G$c11_asof_align(KRq[-1], ann, "Value")$value            # 돌연변이: 결정일 = 수익일 당일
  lbl_lag <- exp_asof(prev_row(KRq)[-1], ann$Date, ann$Date, ann$Value)  # 돌연변이: 날짜 라벨 1행 lag(가용일 무시)
  ok(sum(same_day != s7, na.rm = TRUE) > 0L, "A7d ★돌연변이 red: 당일 결정(decision=t) ≠ 규약 (b)")
  ok(sum(lbl_lag != s7, na.rm = TRUE) > 0L, sprintf("A7e ★돌연변이 red: 라벨 1행 lag(구판) ≠ 규약 (b) (%d일 다름)", sum(lbl_lag != s7, na.rm = TRUE)))
}

# =============================================================================
cat("\n── B. apply_regime_overlay (규약 b) ──\n")
AN <- load_env(code("02_Infrastructure/regime/apply_regime_overlay.R"))
navd <- KR[KR >= as.Date("2020-01-02") & KR <= as.Date("2020-03-31")]
SIM <- list(DAILY_NAV_DT = data.table(Date = navd, NAV = 1e8 * 1.001^seq_along(navd), Strategy_Ret = 0.001),
            bm_xts = xts(rep(0, length(navd)), order.by = navd), PORTFOLIO_LOG = data.table(), HOLDINGS_LOG = data.table())
BMD <- data.table(Date = navd, BM_Ret = 0)
usd <- US[US >= as.Date("2019-12-02") & US <= as.Date("2020-03-31")]
RAW <- data.table(Date = usd, MRS = ifelse(usd == as.Date("2020-02-12"), 50, 0), n_axes_firing = 0L)
RAW[, avail_date := next_kr(Date)]
LAG <- copy(RAW)[, `:=`(MRS = shift(MRS, 1L, fill = 0), avail_date = shift(avail_date, 1L))]   # build_daily_regime 식 선-lag 패널
LAG <- LAG[!is.na(avail_date)]
expM <- exp_asof(prev_row(navd), RAW$Date, RAW$avail_date, RAW$MRS); expM[is.na(expM)] <- 0
l2d <- function(ov) ov$DAILY_NAV_DT[Layer == 2L, Date]
ovR <- suppressMessages(AN$apply_regime_overlay(SIM, copy(RAW), BMD))
ovL <- suppressMessages(AN$apply_regime_overlay(SIM, copy(LAG), BMD))
ok(identical(ovR$DAILY_NAV_DT$MRS, expM), "B1a MRS = 수익 창 시작까지 가용한 값(손 유도 · 원시 패널)")
ok(identical(ds(l2d(ovR)), "2020-02-14"), sprintf("B1b 미국 02-12 경보 → 한국 02-14 수익부터(창 시작 02-13 15:30) [%s]", paste(l2d(ovR), collapse = ",")))
ok(identical(ovL$DAILY_NAV_DT$MRS, expM), "B1c 선-lag 패널도 같은 답(생산자 lag 방식과 무관 — 가용일이 결정)")
ok(identical(ovR$pit_c11$status, "avail_annotated") && identical(ovR$pit_c11$quarantine, "PITQ-C11-20260924"), "B1d pit_c11 기록")
ov1 <- suppressMessages(AN$apply_regime_overlay(SIM, copy(RAW), BMD, extra_lag = 1L))
ok(identical(ds(l2d(ov1)), "2020-02-17"), "B1e extra_lag=1(lag1 스트레스) → 한 거래일 뒤")
LEG <- LAG[, .(Date, MRS, n_axes_firing)]
eB <- err_of(suppressMessages(AN$apply_regime_overlay(SIM, copy(LEG), BMD)))
ok(!is.na(eB) && grepl("C11", eB), "B2a legacy 패널(가용일 없음) 기본 = 중단")
fo <- blob_file("aro")
if (is.na(fo)) skip("B2", "git blob 판독 불가", BLOB[["aro"]]) else {
  AO <- load_env(fo)
  ovO <- suppressMessages(AO$apply_regime_overlay(SIM, copy(LEG), BMD))
  ok(identical(ds(l2d(ovO)), "2020-02-13"), "B2b ★구판(1행 lag roll join) = 02-13 — 미국 02-12 세션(한국 02-13 06시 도착)을 02-12 15:30 창에 씀(V-06)")
  ovLab <- suppressWarnings(suppressMessages(AN$apply_regime_overlay(SIM, copy(LEG), BMD, c11_legacy = "label")))
  ok(same_dt(ovLab$DAILY_NAV_DT, ovO$DAILY_NAV_DT) && identical(ovLab$strategy_xts, ovO$strategy_xts) &&
     same_dt(ovLab$overlay_stats$layer_distribution, ovO$overlay_stats$layer_distribution) &&
     identical(ovLab$overlay_stats[-1], ovO$overlay_stats[-1]), "B2c label 재현 = 구판 산출과 비트 동일")
  ok(identical(ovLab$pit_c11$status, "unresolved_legacy_panel"), "B2d label 재현 산출물에 미해소 표식")
}
fm <- mutate_file(code("02_Infrastructure/regime/apply_regime_overlay.R"),
                  ".ARO_C11$c11_window_start(nav_dt$Date, extra_lag = extra_lag)", "nav_dt$Date", "aro_sameday")
if (is.na(fm)) ok(FALSE, "B3 돌연변이 대상 줄 부재(수리판 구조 변경?)") else {
  AM <- load_env(fm)
  ovM <- suppressMessages(AM$apply_regime_overlay(SIM, copy(RAW), BMD))
  ok(!identical(ds(l2d(ovM)), "2020-02-14"), sprintf("B3 ★돌연변이 red(결정일=수익일 당일): 경보일 %s ≠ 02-14", paste(l2d(ovM), collapse = ",")))
}

# =============================================================================
cat("\n── C·D. RCMA(.rcma_load) · 라벨 관문 (규약 b · 월간 = 창 시작) ──\n")
PC <- file.path(TMP, "proj_c"); PCL <- file.path(TMP, "proj_cl")   # 가용일판 · legacy판 — 같은 파일을 덮어쓰지 않는다(mmap 잠금)
spine <- sort(unique(c(KR, US)))
UNI <- data.table(Date = spine, Category = "NEUTRAL")
UNI[Date == as.Date("2020-02-12"), Category := "CRISIS"]
UNI[Date %in% as.Date(c("2020-02-26", "2020-02-27")), Category := "RISK_OFF"]
UNI[, avail_date := next_kr(Date)]
set.seed(20260924L)
BMK <- data.table(Date = KR, BM_Ret = round(rnorm(length(KR), 0.0003, 0.012), 6))
m1d <- KR[KR >= as.Date("2019-01-02")]
m1 <- data.table(Date = m1d, Strategy_Ret = round(0.0004 + 0.01 * sin(seq_along(m1d) / 7), 6))
me_kr <- KR[!duplicated(format(KR, "%Y%m"), fromLast = TRUE)]
m2d <- me_kr[me_kr >= as.Date("2015-01-01")]
m2 <- data.table(Date = m2d, Strategy_Ret = round(0.002 * seq_along(m2d) %% 7 - 0.005, 6))
MPJ <- list(regimes = list("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS", "RISK_OFF"),
            modules = list(M1 = list(sim_result_path = "04_Research/strategies/M1/sim_result.rds", grade = "B", role = "core", freq = "daily"),
                           M2 = list(sim_result_path = "04_Research/strategies/M2/sim_result.rds", grade = "B", role = "defensive", freq = "monthly")))
mk_proj <- function(root, ann) {
  for (d in c(".cache", "06_Registry", "04_Research/strategies/M1", "04_Research/strategies/M2")) dir.create(file.path(root, d), recursive = TRUE, showWarnings = FALSE)
  cp_code(root, c("02_Infrastructure/contracts/label_eligibility_gate.R", "02_Infrastructure/validation/overlay_pit_guard.R"))
  write_parquet(BMK, file.path(root, ".cache/benchmark.parquet"))
  saveRDS(list(DAILY_NAV_DT = m1, bm_xts = xts(rep(0.0002, length(m1d)), order.by = m1d), freq = "daily"),
          file.path(root, "04_Research/strategies/M1/sim_result.rds"))
  saveRDS(list(DAILY_NAV_DT = m2, bm_xts = xts(rep(0.001, length(m2d)), order.by = m2d), freq = "monthly"),
          file.path(root, "04_Research/strategies/M2/sim_result.rds"))
  write_json(MPJ, file.path(root, "06_Registry/module_performance.json"), auto_unbox = TRUE, pretty = TRUE)
  write_parquet(if (ann) UNI else UNI[, .(Date, Category)], file.path(root, ".cache/unified_regime_signal_daily.parquet"))
}
mk_proj(PC, TRUE); mk_proj(PCL, FALSE)
load_rma <- function(path) load_env(path, pre = list(PROJ = PC, .RCMA_FUNC_ONLY = TRUE))
RN <- suppressWarnings(load_rma(code("02_Infrastructure/portfolio/regime_module_admission.R")))
ctx <- suppressWarnings(RN$.rcma_load(PC))
a1 <- ctx$AL$M1; a2 <- ctx$AL$M2
e1 <- exp_asof(prev_row(m1d), UNI$Date, UNI$avail_date, UNI$Category)
ok(!is.null(a1) && identical(a1$regime, e1[!is.na(e1)]) && identical(ds(a1$Date), ds(m1d[!is.na(e1)])),
   "C1a 일간 모듈 라벨 = 수익 창 시작(직전 행)까지 가용한 Category(손 유도 전 구간)")
ok(!is.null(a1) && identical(ds(a1[regime == "CRISIS", Date]), "2020-02-14"), "C1b 한국 02-12 라벨(가용 02-13) → 02-14 수익에만")
ok(!is.null(a2) && identical(a2[Date == as.Date("2020-02-28"), regime], "NEUTRAL") && identical(a2[Date == as.Date("2020-03-31"), regime], "RISK_OFF"),
   "C1c ★월간 모듈 = 직전 월말(창 시작) 라벨: 2월 수익 NEUTRAL · 3월 수익 RISK_OFF(2월말 라벨)")
ok(identical(ctx$pit_c11$status, "avail_annotated"), "C1d ctx$pit_c11 기록")
rc <- suppressWarnings(RN$compute_rcma(as.Date("2020-03-31"), ctx, PC))
ok(identical(rc$pit_c11$status, "avail_annotated"), "C1e compute_rcma 반환에 pit_c11 동반")
eC <- err_of(suppressWarnings(RN$.rcma_load(PCL)))
ok(!is.na(eC) && grepl("C11", eC), "C2a legacy 패널 기본 = 중단")
fo <- blob_file("rma")
if (is.na(fo)) skip("C2", "git blob 판독 불가", BLOB[["rma"]]) else {
  RO <- suppressWarnings(load_rma(fo))
  ctxO <- suppressWarnings(RO$.rcma_load(PCL))
  ok(identical(ctxO$AL$M2[Date == as.Date("2020-02-28"), regime], "RISK_OFF"),
     "C2b ★구판 월간 = 월말 라벨로 그 달 수익 분류(2월 수익 ← 2월 26~27일 라벨 · 동월 누출)")
  ok(identical(ds(ctxO$AL$M1[regime == "CRISIS", Date]), "2020-02-13"), "C2c ★구판 일간 = 02-13(미국 전일 세션 14시간 누출)")
  Sys.setenv(QVEST_C11_LEGACY_REGIME = "label")
  ctxL <- suppressWarnings(RN$.rcma_load(PCL))
  Sys.unsetenv("QVEST_C11_LEGACY_REGIME")
  ok(identical(names(ctxL$AL), names(ctxO$AL)) && all(vapply(names(ctxO$AL), function(s) same_dt(ctxL$AL[[s]], ctxO$AL[[s]]), logical(1))) &&
     identical(ctxL$regime_share, ctxO$regime_share), "C2d label 재현 = 구판 AL·regime_share 비트 동일")
  ok(identical(ctxL$pit_c11$status, "unresolved_legacy_panel"), "C2e label 재현 표식")
}
fm <- mutate_file(code("02_Infrastructure/portfolio/regime_module_admission.R"),
                  ".RMA_C11$c11_window_start(d$Date)", "d$Date", "rma_sameday")
if (is.na(fm)) ok(FALSE, "C3 돌연변이 대상 줄 부재") else {
  RM_ <- suppressWarnings(load_rma(fm)); cm <- suppressWarnings(RM_$.rcma_load(PC))
  ok(!identical(ds(cm$AL$M1[regime == "CRISIS", Date]), "2020-02-14"), "C3 ★돌연변이 red(결정일=당일): CRISIS 귀속일이 02-14 가 아니다")
}
# D. 라벨 관문 daily_t1_monthstart — RCMA 와 같은 구성(가용일)
suppressWarnings(suppressMessages(sys.source(code("02_Infrastructure/contracts/regime_label_gate.R"), envir = (LG <- new.env(parent = globalenv())))))
pD <- LG$regime_label_monthly_panel(PC, refresh = TRUE, label_basis = "daily_t1_monthstart")
ok(!is.null(pD) && identical(pD[ym == "202003", regime], "RISK_OFF") && identical(pD[ym == "202002", regime], "NEUTRAL"),
   "D1a 홀딩월 라벨 = 직전월 마지막 벤치 거래일 종가까지 가용한 값(3월 ← 2월 27일 RISK_OFF)")
ok(identical(attr(pD, "pit_c11"), "avail_annotated"), "D1b 패널 pit_c11 = avail_annotated")
gD <- suppressWarnings(LG$regime_label_gate(asof = as.Date("2020-06-30"), proj = PC))
ok(identical(gD$pit_c11, "avail_annotated") && identical(LG$rlg_summary(gD)$pit_c11, "avail_annotated"), "D1c 관문 결과·요약에 pit_c11")
pDl <- LG$regime_label_monthly_panel(PCL, refresh = TRUE, label_basis = "daily_t1_monthstart")
ok(!is.null(pDl) && identical(pDl[ym == "202003", regime], "NEUTRAL") && identical(attr(pDl, "pit_c11"), "unresolved_legacy_panel"),
   "D2 legacy 패널 = 구판 구성(3월 ← 2월 28일 라벨) + 미해소 표식(진단 도구 — 멈추지 않음)")
fo <- blob_file("rlg")
if (!is.na(fo)) {
  suppressWarnings(suppressMessages(sys.source(fo, envir = (LGO <- new.env(parent = globalenv())))))
  pO <- LGO$regime_label_monthly_panel(PCL, refresh = TRUE, label_basis = "daily_t1_monthstart")
  ok(same_dt(pO, pDl), "D3 legacy 패널 구성 = 구판과 비트 동일(값)")
} else skip("D3", "git blob 판독 불가", BLOB[["rlg"]])
fm <- mutate_file(code("02_Infrastructure/contracts/regime_label_gate.R"), ".pos <- match(.first, .bd) - 1L", ".pos <- match(.first, .bd)", "rlg_firstday")
if (is.na(fm)) ok(FALSE, "D4 돌연변이 대상 줄 부재") else {
  suppressWarnings(suppressMessages(sys.source(fm, envir = (LGM <- new.env(parent = globalenv())))))
  pM <- LGM$regime_label_monthly_panel(PC, refresh = TRUE, label_basis = "daily_t1_monthstart")
  ok(!identical(pM[ym == "202003", regime], "RISK_OFF"), "D4 ★돌연변이 red(결정일 = 홀딩월 첫날): 3월 라벨이 달라진다")
}

# =============================================================================
cat("\n── E. build_module_performance (자식 · dry-run) ──\n")
PB <- file.path(TMP, "proj_b")
dir.create(PB, recursive = TRUE, showWarnings = FALSE)
for (d in c(".cache", "06_Registry", "04_Research/strategies")) dir.create(file.path(PB, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(PC, "04_Research/strategies/M1"), file.path(PB, "04_Research/strategies"), recursive = TRUE))
invisible(file.copy(file.path(PC, "04_Research/strategies/M2"), file.path(PB, "04_Research/strategies"), recursive = TRUE))
cp_code(PB, c("02_Infrastructure/regime/build_module_performance.R", "02_Infrastructure/regime/l2_pool_admission.R",
              "02_Infrastructure/contracts/defensive_score.R", "02_Infrastructure/validation/overlay_pit_guard.R",
              "02_Infrastructure/data/fred_availability.R", "06_Registry/fred_availability_rules.json"))
MC <- list(modules = list(
  M1 = list(sim_result_path = "04_Research/strategies/M1/sim_result.rds", fr_eligible = TRUE, metric_type = "backtested",
            contract = list(contract_pass = TRUE), grade = "B", essence_grade = "B", role = "core", origin_mode = "test"),
  M2 = list(sim_result_path = "04_Research/strategies/M2/sim_result.rds", fr_eligible = TRUE, metric_type = "backtested",
            contract = list(contract_pass = TRUE), grade = "B", essence_grade = "B", role = "defensive", origin_mode = "test")))
write_json(MC, file.path(PB, "06_Registry/module_catalog.json"), auto_unbox = TRUE, pretty = TRUE)
write_parquet(BMK, file.path(PB, ".cache/benchmark.parquet"))
bmp_run <- function(script, ann, policy = "", tag) {
  write_parquet(if (ann) UNI else UNI[, .(Date, Category)], file.path(PB, ".cache/unified_regime_signal_daily.parquet"))   # 부모는 PB 를 읽지 않는다(자식만)
  out <- file.path(PB, paste0("out_", tag, ".json")); if (file.exists(out)) file.remove(out)
  r <- run_child(script, child_env(PB, list(QVEST_L2_DRY_RUN = "1", QVEST_L2_DRY_RUN_OUT = out, QVEST_C11_LEGACY_REGIME = policy)))
  j <- if (file.exists(out)) fromJSON(out, simplifyVector = FALSE) else NULL
  if (is.null(j)) cat(tail(r$out, 15), sep = "\n")
  list(r = r, j = j)
}
BN <- file.path(PB, "02_Infrastructure/regime/build_module_performance.R")
bA <- bmp_run(BN, TRUE, "", "ann")
ok(!is.null(bA$j) && identical(bA$j$regime_pit_c11$status, "avail_annotated") && !is.na(bA$j$regime_pit_c11$rules_key_at_consumption %||% NA),
   "E1a 가용일 패널 → 국면 분할 산출 + regime_pit_c11(규칙 epoch 키 동반)")
if (!is.null(bA$j)) {
  pr1 <- bA$j$modules$M1$per_regime; pr2 <- bA$j$modules$M2$per_regime
  ok(identical(as.integer(pr1$CRISIS$n_days), 1L) && identical(as.integer(pr1$RISK_OFF$n_days), 2L),
     "E1b 일간 모듈 CRISIS 1일(02-14) · RISK_OFF 2일(02-28·03-02) — 손 유도")
  r_mar <- m2[Date == as.Date("2020-03-31"), Strategy_Ret]
  ok(identical(as.integer(pr2$RISK_OFF$n_days), 1L) && isTRUE(abs(pr2$RISK_OFF$mean_ann - round(r_mar * 12, 4)) < 1e-9),
     "E1c ★월간 모듈 RISK_OFF = 3월 수익(창 시작 2월말 라벨) — 2월 수익 아님")
  ok(identical(bA$j$modules$M1$per_regime_pit_c11, "avail_annotated"), "E1d 모듈별 per_regime_pit_c11")
}
bW <- bmp_run(BN, FALSE, "", "withheld")
ok(!is.null(bW$j) && is.null(bW$j$modules$M1$per_regime) && identical(bW$j$modules$M1$per_regime_pit_c11, "withheld_legacy_panel") &&
   identical(bW$j$regime_pit_c11$status, "withheld_legacy_panel"), "E2a legacy + stop(기본) = 풀은 조립 · per_regime 보류(null) · 표식")
fo <- blob_file("bmp")
if (is.na(fo)) skip("E2", "git blob 판독 불가", BLOB[["bmp"]]) else {
  BO <- file.path(PB, "02_Infrastructure/regime/build_module_performance_orig.R"); file.copy(fo, BO, overwrite = TRUE)
  bO <- bmp_run(BO, FALSE, "", "orig")
  strip <- function(j, drop_per = FALSE) {
    j$generated <- NULL; j$regime_source <- NULL; j$regime_pit_c11 <- NULL
    for (m in names(j$modules)) { j$modules[[m]]$per_regime_pit_c11 <- NULL; if (drop_per) j$modules[[m]]$per_regime <- NULL }
    j }
  ok(!is.null(bO$j) && identical(strip(bO$j, TRUE), strip(bW$j, TRUE)), "E2b 보류판 = 구판과 per_regime 외 전부 동일(풀 구성 불변)")
  bL <- bmp_run(BN, FALSE, "label", "label")
  ok(!is.null(bL$j) && identical(strip(bO$j), strip(bL$j)) && identical(bL$j$modules$M2$per_regime_pit_c11, "unresolved_legacy_panel"),
     "E2c label 재현 = 구판 per_regime 포함 동일 + 미해소 표식")
  ok(!is.null(bO$j) && identical(as.integer(bO$j$modules$M2$per_regime$RISK_OFF$n_days), 1L) &&
     isTRUE(abs(bO$j$modules$M2$per_regime$RISK_OFF$mean_ann - round(m2[Date == as.Date("2020-02-28"), Strategy_Ret] * 12, 4)) < 1e-9),
     "E2d ★구판 월간 RISK_OFF = 2월 수익(동월 누출) — 수리판과 갈린다")
}
fm <- mutate_file(BN, ".BMP_C11$c11_window_start(dm$Date)", "dm$Date", "bmp_sameday")
if (is.na(fm)) ok(FALSE, "E3 돌연변이 대상 줄 부재") else {
  BM_ <- file.path(PB, "02_Infrastructure/regime/build_module_performance_mut.R"); file.copy(fm, BM_, overwrite = TRUE)
  bM <- bmp_run(BM_, TRUE, "", "mut")
  ok(!is.null(bM$j) && !identical(as.integer(bM$j$modules$M2$per_regime$RISK_OFF$n_days), 1L) ||
     (!is.null(bM$j) && !isTRUE(abs(bM$j$modules$M2$per_regime$RISK_OFF$mean_ann - round(m2[Date == as.Date("2020-03-31"), Strategy_Ret] * 12, 4)) < 1e-9)),
     "E3 ★돌연변이 red(결정일=당일): 월간 RISK_OFF 귀속이 3월이 아니다")
}

# =============================================================================
cat("\n── F. run_wf_ensemble (자식 · 등재 끔) ──\n")
PW <- file.path(TMP, "proj_w")
for (d in c(".cache", "06_Registry", "04_Research/factor_rotation/output", "diag")) dir.create(file.path(PW, d), recursive = TRUE, showWarnings = FALSE)
ctr <- list.files(code("02_Infrastructure/contracts"), pattern = "\\.R$")
cp_code(PW, c(file.path("02_Infrastructure/contracts", ctr), "02_Infrastructure/portfolio/module_dispatcher.R",
              "02_Infrastructure/portfolio/regime_module_admission.R", "02_Infrastructure/validation/overlay_pit_guard.R",
              "02_Infrastructure/data/fred_availability.R", "06_Registry/fred_availability_rules.json",
              "04_Research/factor_rotation/run_wf_ensemble.R"))
WD <- wkdays("2012-01-02", "2019-12-31")
WME <- WD[!duplicated(format(WD, "%Y%m"), fromLast = TRUE)]
CYC <- c("RISK_ON", "NEUTRAL", "CRISIS", "RISK_OFF")
xm <- function(ym) { y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 5, 6)); CYC[((y * 12 + m) %% 4) + 1L] }
UW <- data.table(Date = WD, Category = xm(format(WD, "%Y%m")))
UW[Date %in% WME, Category := "CAUTION"]                                  # 월말 당일만 CAUTION — 날짜 라벨로 읽으면 전부 CAUTION
UW[, avail_date := c(WD[-1], as.Date(NA))]                                # 다음 거래일 가용
write_parquet(data.table(Date = WD, BM_Ret = round(rnorm(length(WD), 0.0003, 0.011), 6)), file.path(PW, ".cache/benchmark.parquet"))
write_parquet(data.table(Date = WD), file.path(PW, ".cache/trading_calendar.parquet"))   # r1: IS 국면 IR 창 시작 = 모듈 직전 행 → 한국 거래일로 내림(달력 필요)
mods <- list()
for (k in 1:4) {
  sid <- sprintf("W%d", k); dir.create(file.path(PW, "04_Research/strategies", sid), recursive = TRUE, showWarnings = FALSE)
  r <- round(0.0002 * k + 0.008 * sin(seq_along(WD) / (5 + 2 * k)) + rnorm(length(WD), 0, 0.004), 6)
  saveRDS(list(DAILY_NAV_DT = data.table(Date = WD, Strategy_Ret = r), bm_xts = xts(rep(0.0003, length(WD)), order.by = WD), freq = "daily"),
          file.path(PW, "04_Research/strategies", sid, "sim_result.rds"))
  mods[[sid]] <- list(sim_result_path = file.path("04_Research/strategies", sid, "sim_result.rds"), grade = "B",
                      role = if (k == 4) "defensive" else "core", freq = "daily", admission_route = "grade_floor")
}
write_json(list(regimes = as.list(c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS", "RISK_OFF")), modules = mods),
           file.path(PW, "06_Registry/module_performance.json"), auto_unbox = TRUE, pretty = TRUE)
wf_run <- function(script, ann, policy = "", lag = "0", tag = "FR_T") {
  write_parquet(if (ann) UW else UW[, .(Date, Category)], file.path(PW, ".cache/unified_regime_signal_daily.parquet"))
  run_child(script, child_env(PW, list(FR_REGISTER = "0", FR_RUN_ID = tag, FR_DIAG_DIR = file.path(PW, "diag"),
                                        FR_EXTRA_REGIME_LAG = lag, FR_ARM_TAG = "", QVEST_C11_LEGACY_REGIME = policy)))
}
diag_of <- function(id) { f <- file.path(PW, "diag", paste0(id, "_dispatch_diag.csv")); if (file.exists(f)) fread(f, colClasses = list(character = "ym")) else NULL }
exp_disp <- function(ym, back) { d <- as.Date(paste0(ym, "01"), "%Y%m%d"); vapply(seq_along(d), function(i) {
  p <- seq(d[i], by = "-1 month", length.out = back + 1L)[back + 1L]; xm(format(p, "%Y%m")) }, character(1)) }
WN <- file.path(PW, "04_Research/factor_rotation/run_wf_ensemble.R")
w0 <- wf_run(WN, TRUE, "", "0", "FR_T")
dg <- diag_of("FR_T")
fj <- file.path(PW, "04_Research/factor_rotation/output/FR_T_result.json")
ok(w0$status == 0L && !is.null(dg) && nrow(dg) >= 12L, sprintf("F1a 가용일 패널 완주(status %d · 배분월 %s)", w0$status, if (is.null(dg)) "NA" else nrow(dg)))
if (w0$status != 0L) cat(tail(w0$out, 20), sep = "\n")
if (!is.null(dg)) {
  ok(!any(dg$regime == "CAUTION"), "F1b 월말 당일 라벨(CAUTION)은 한 번도 배분에 안 쓰였다(가용일 = 다음 거래일)")
  ok(identical(dg$regime, exp_disp(dg$ym, 1L)), "F1c 배분 국면 = 직전월 마지막 거래일 종가까지 가용한 라벨(손 유도 전 월)")
}
if (file.exists(fj)) { J <- fromJSON(fj, simplifyVector = FALSE)
  ok(identical(J$pit_c11$status, "avail_annotated") && identical(J$pit_c11$legacy_run, FALSE), "F1d FR 결과 JSON 에 pit_c11") } else ok(FALSE, "F1d 결과 JSON 부재")
w1 <- wf_run(WN, TRUE, "", "1", "FR_T1")
dg1 <- diag_of("FR_T1")
ok(w1$status == 0L && !is.null(dg1) && identical(dg1$regime, exp_disp(dg1$ym, 2L)), "F2 lag1 스트레스(FR_EXTRA_REGIME_LAG=1) = 전전월 라벨")
wl <- wf_run(WN, FALSE, "", "0", "FR_TL")
ok(wl$status != 0L && any(grepl("C11", wl$out)), "F3a legacy 패널 기본 = 중단(fail-closed)")
wb <- wf_run(WN, FALSE, "label", "0", "FR_TB")
dgb <- diag_of("FR_TB_c11legacy")
fjb <- file.path(PW, "04_Research/factor_rotation/output/FR_TB_c11legacy_result.json")
ok(wb$status == 0L && file.exists(fjb) && !file.exists(file.path(PW, "04_Research/factor_rotation/output/FR_TB_result.json")),
   "F3b label 재현 = 완주 · 산출 파일명 _c11legacy(정본 이름 비점유)")
if (file.exists(fjb)) ok(isTRUE(fromJSON(fjb, simplifyVector = FALSE)$pit_c11$legacy_run), "F3c label 재현 결과에 legacy_run 표식")
ok(!is.null(dgb) && all(dgb$regime == "CAUTION"), "F3d ★구판 정렬 = 월말 날짜 라벨(CAUTION)을 배분에 씀 — 수리판과 갈린다")
ok(any(grepl("L-code 발행 생략", wb$out)), "F3e label 재현 = L-code 발행 생략")
fm <- mutate_file(WN, 'mreg[, dec_date := shift(me_date, 1L + FR_EXTRA_REGIME_LAG)]', 'mreg[, dec_date := me_date]', "wf_sameday")
if (is.na(fm)) ok(FALSE, "F4 돌연변이 대상 줄 부재") else {
  WM <- file.path(PW, "04_Research/factor_rotation/run_wf_ensemble_mut.R"); file.copy(fm, WM, overwrite = TRUE)
  wm <- wf_run(WM, TRUE, "", "0", "FR_TM"); dgm <- diag_of("FR_TM")
  ok(wm$status != 0L || is.null(dgm) || !identical(dgm$regime, exp_disp(dgm$ym, 1L)),
     sprintf("F4 ★돌연변이 red(결정일 = 홀딩월 말): 중단 또는 배분 불일치 (status %d)", wm$status))
}

# =============================================================================
cat("\n── G. backtest_harness (regime_tilt · load_macro_regime · 나머지 비트 동일) ──\n")
PH <- file.path(TMP, "proj_h")
dir.create(file.path(PH, "03_Universe"), recursive = TRUE, showWarnings = FALSE)
cp_code(PH, c("02_Infrastructure/config.R", "02_Infrastructure/F1. QT_to_xts.r", "02_Infrastructure/portfolio/advanced_weights.R",
              "02_Infrastructure/portfolio/strategy_tilt_weights.R", "02_Infrastructure/validation/overlay_pit_guard.R"))
HN <- code("02_Infrastructure/backtest_harness.R"); HO <- blob_file("bh")
if (is.na(HO)) skip("G", "git blob 판독 불가", BLOB[["bh"]]) else {
  # G1 정적: 수정 대상 외 최상위 정의 전부 동일
  tl <- function(f) { ex <- parse(f, keep.source = FALSE, encoding = "UTF-8"); out <- list()
    for (i in seq_along(ex)) { e <- ex[[i]]
      k <- if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && is.name(e[[2]])) as.character(e[[2]]) else paste0("#", i, ":", substr(paste(deparse(e), collapse = ""), 1, 60))
      out[[k]] <- paste(deparse(e), collapse = "\n") }
    out }
  TO <- tl(HO); TN <- tl(HN)
  MOD <- c("load_macro_regime", "run_monthly_simulation", ".bh_c11_guard_env", ".bh_c11_guard", ".bh_regime_mrs_at")
  kO <- setdiff(names(TO), MOD); kN <- setdiff(names(TN), MOD)
  nk <- function(k) sub("^#[0-9]+:", "#", k)
  ok(identical(nk(kO), nk(kN)) && identical(unname(unlist(TO[kO])), unname(unlist(TN[kN]))),
     sprintf("G1a 수정 대상 외 최상위 %d개 정의·문장 원판과 동일", length(kO)))
  ok(setequal(setdiff(names(TN), names(TO)), c(".bh_c11_guard_env", ".bh_c11_guard", ".bh_regime_mrs_at")), "G1b 신규 정의 = C11 도우미 3개뿐")
  # G2 동적: 합성 시뮬 비트 동일(regime_dt = NULL 경로) + C11 probe
  set.seed(7L)
  hd <- wkdays("2018-01-01", "2020-06-30"); tk <- sprintf("T%02d", 1:30)
  RAWH <- CJ(Ticker = tk, Date = hd)[, Ret := round(rnorm(.N, 0.0003, 0.02), 6)]
  RAWH[, Close := 1000 * cumprod(1 + Ret), by = Ticker][, `:=`(Name = paste0("N", Ticker), Sector = "S")]
  hme <- hd[!duplicated(format(hd, "%Y%m"), fromLast = TRUE)]
  FAC <- CJ(Date = hme[1:28], Ticker = tk)[, Score := round(rnorm(.N), 4)]
  BMH <- data.table(Date = hd, BM_Ret = round(rnorm(length(hd), 0.0002, 0.01), 6))
  hus <- setdiff(hd, as.Date("2020-02-17")); hus <- as.Date(hus, origin = "1970-01-01")
  RP <- data.table(Date = hus, MRS = as.numeric(seq_along(hus) %% 40), n_axes_firing = 0L)
  RP[Date == as.Date("2020-02-12"), MRS := 55]
  RP[, avail_date := c(hd[match(hus, hd) + 1L])]
  MR <- data.table(Date = hme, VIX = round(runif(length(hme), 10, 30), 2))
  saveRDS(list(RAW = RAWH, BM = BMH, FAC = FAC, RP = RP, MR = MR), file.path(PH, "fx.rds"))
  drv <- file.path(PH, "driver.R")
  writeLines(c(
    'a <- commandArgs(TRUE); harness <- a[1]; outp <- a[2]; fx <- readRDS(a[3])',
    'suppressPackageStartupMessages(library(data.table))',
    'source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure", "config.R"))',
    'suppressMessages(source(harness, encoding = "UTF-8"))',
    'res <- list()',
    'for (wm in c("ivol", "hrp", "score_tilt", "regime_tilt", "regime_softmax", "minvar")) res[[wm]] <- tryCatch(',
    '  suppressWarnings(run_monthly_simulation(copy(fx$RAW), copy(fx$BM), copy(fx$FAC), n_holdings = 10L, weight_method = wm, regime_dt = NULL))[c("DAILY_NAV_DT", "PORTFOLIO_LOG", "HOLDINGS_LOG")],',
    '  error = function(e) paste("ERR", conditionMessage(e)))',
    'res$flat <- tryCatch(suppressWarnings(run_monthly_simulation(copy(fx$RAW), copy(fx$BM), copy(fx$FAC), n_holdings = 10L, weight_method = "ivol", cost_model_version = "v2.3_flat"))[c("DAILY_NAV_DT", "PORTFOLIO_LOG")], error = function(e) paste("ERR", conditionMessage(e)))',
    'mp <- file.path(Sys.getenv("QM_ROOT"), ".cache", "macro_regime.parquet"); dir.create(dirname(mp), showWarnings = FALSE, recursive = TRUE)',
    'arrow::write_parquet(fx$MR, mp); FRED_REGIME_CACHE <- mp',
    'res$lmr <- load_macro_regime()',
    'mp2 <- file.path(dirname(mp), "macro_regime_ann.parquet"); arrow::write_parquet(cbind(fx$MR, avail_date = fx$MR$Date + 20L), mp2); FRED_REGIME_CACHE <- mp2; res$lmr_ann <- load_macro_regime()',
    'if (exists(".bh_regime_mrs_at")) {',
    '  RP <- fx$RP; LG <- RP[, .(Date, MRS, n_axes_firing)]',
    '  res$p_ann13 <- .bh_regime_mrs_at(RP, as.Date("2020-02-13")); res$p_ann12 <- .bh_regime_mrs_at(RP, as.Date("2020-02-12"))',
    '  res$p_leg_err <- tryCatch({ .bh_regime_mrs_at(LG, as.Date("2020-02-13")); NA_character_ }, error = function(e) conditionMessage(e))',
    '  Sys.setenv(QVEST_C11_LEGACY_REGIME = "label"); res$p_leg_lab <- suppressWarnings(.bh_regime_mrs_at(LG, as.Date("2020-02-13"))); Sys.unsetenv("QVEST_C11_LEGACY_REGIME")',
    '  res$sim_ann <- tryCatch({ s <- suppressWarnings(run_monthly_simulation(copy(fx$RAW), copy(fx$BM), copy(fx$FAC), n_holdings = 10L, weight_method = "regime_tilt", regime_dt = RP)); nrow(s$PORTFOLIO_LOG) }, error = function(e) paste("ERR", conditionMessage(e)))',
    '  res$sim_leg <- tryCatch({ suppressWarnings(run_monthly_simulation(copy(fx$RAW), copy(fx$BM), copy(fx$FAC), n_holdings = 10L, weight_method = "regime_tilt", regime_dt = LG)); "NO_ERROR" }, error = function(e) conditionMessage(e))',
    '}',
    'saveRDS(res, outp)'), drv, useBytes = TRUE)
  hrun <- function(h, tag) { o <- file.path(PH, paste0("res_", tag, ".rds")); if (file.exists(o)) file.remove(o)
    r <- run_child(drv, child_env(PH), c(shQuote(h), shQuote(o), shQuote(file.path(PH, "fx.rds"))))
    if (!file.exists(o)) { cat(tail(r$out, 15), sep = "\n"); return(NULL) }
    readRDS(o) }
  rO <- hrun(HO, "old"); rN <- hrun(HN, "new")
  if (is.null(rO) || is.null(rN)) ok(FALSE, "G2 자식 시뮬 실행 실패") else {
    for (wm in c("ivol", "hrp", "score_tilt", "regime_tilt", "regime_softmax", "minvar", "flat"))
      ok(!is.character(rN[[wm]]) && identical(rO[[wm]], rN[[wm]]), sprintf("G2 run_monthly_simulation 비트 동일: %s", wm))
    lo <- rO$lmr; ln <- rN$lmr; st <- attr(ln, "pit_c11")$status; setattr(ln, "pit_c11", NULL)
    ok(identical(lo, ln) && identical(st, "unresolved_legacy_panel"), "G3a load_macro_regime 값 불변 + legacy 표식(속성만)")
    ok(identical(attr(rN$lmr_ann, "pit_c11")$status, "avail_annotated"), "G3b avail_date 열 있는 재빌드판 = avail_annotated")
    ok(identical(rN$p_ann13, 55) && identical(rN$p_ann12, RP[Date == as.Date("2020-02-11"), MRS]),
       "G4a regime_tilt MRS = 집행일 종가까지 가용한 값(02-13 집행 ← 미국 02-12 · 02-12 집행 ← 02-11)")
    ok(!is.na(rN$p_leg_err) && grepl("C11", rN$p_leg_err), "G4b legacy regime_dt 기본 = 중단")
    ok(identical(rN$p_leg_lab, RP[Date == as.Date("2020-02-13"), MRS]), "G4c label 재현 = 구판 날짜 일치 조회")
    ok(is.numeric(rN$sim_ann) && rN$sim_ann > 0, "G4d 가용일 패널로 regime_tilt 시뮬 완주")
    ok(grepl("C11", rN$sim_leg), "G4e legacy 패널로 regime_tilt 시뮬 = 중단")
    fm <- mutate_file(HN, 'a <- g$c11_asof_align(exec_date, regime_dt, "MRS")',
                      'a <- list(value = regime_dt[Date == exec_date, MRS], avail_date = exec_date, decision_date = exec_date)', "bh_exact")
    if (is.na(fm)) ok(FALSE, "G5 돌연변이 대상 줄 부재") else {
      rM <- hrun(fm, "mut")
      ok(!is.null(rM) && !identical(rM$p_ann13, 55), "G5 ★돌연변이 red(날짜 일치 조회): 02-13 집행 MRS 가 55 가 아니다")
    }
  }
}

# =============================================================================
cat("\n── Z. 운영 무쓰기 ──\n")
MD5_AFTER <- tools::md5sum(OPS_FILES)
ok(identical(unname(MD5_BEFORE), unname(MD5_AFTER)), sprintf("Z1 운영 파일 %d개 md5 불변", length(OPS_FILES)))
FR_OUT_AFTER <- if (dir.exists(FR_OUT_DIR)) sort(list.files(FR_OUT_DIR, recursive = TRUE)) else character(0)
ok(identical(FR_OUT_BEFORE, FR_OUT_AFTER), "Z2 운영 FR 산출 디렉터리 무변경")
finish()
