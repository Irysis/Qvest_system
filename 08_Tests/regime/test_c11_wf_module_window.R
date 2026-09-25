#!/usr/bin/env Rscript
# =============================================================================
# test_c11_wf_module_window.R — run_wf_ensemble IS 국면 IR 의 규약 (b) 창 시작 = 모듈 자기 직전 행 (PIT C11 r1)
# =============================================================================
# 막는 결함(V4 B1 · 통합 검증 BLOCKING): 04_Research/factor_rotation/run_wf_ensemble.R 가 IS 국면 IR 라벨의
#   결정일을 **RM 합집합**의 직전 행으로 잡았다. 모듈에 결측 공백이 있으면 합집합 직전 행이 모듈 자기 직전 행보다
#   늦어, 그 모듈 수익 창(자기 직전 행 종가 → 당일 종가) 안의 정보가 라벨에 들어간다(실측 1,427 모듈·일 라벨 변화).
#   동반(통합 검증 (2)-3): 수익 계열에 주말 행이 있으면 직전 행이 일요일 → 토요일 가용 행(미국 금 세션)이 월요일
#   수익 창에 들어갈 수 있다 → 한국 거래일 달력으로 창 시작을 내린다.
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md ② (b) · pit.md C5
# 방법: 합성 샌드박스(4모듈 · 공백 모듈 W2 = 수요일 결측 · 주말 행 모듈 W3 = 월 중 일요일 행)에서 자식 실행 →
#   FR_DIAG_IS_LABELS=1 진단(모듈·일 라벨)을 **검사 대상과 독립인 손 유도 루프**와 대조. 돌연변이 3종(합집합 직전 행 ·
#   달력 내림 삭제 · 결정일=당일)은 같은 픽스처에서 빨개져야 한다.
# 운영 무쓰기: 전부 tempdir 샌드박스. 자식 = 빈 Renviron + QM_ROOT/CLAUDE_PROJECT_DIR = 샌드박스.
# 실행: Rscript 08_Tests/regime/test_c11_wf_module_window.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow); library(xts) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else "."
}, error = function(e) ".")
CODE_ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(CODE_ROOT, "04_Research/factor_rotation/run_wf_ensemble.R")))
  CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
cat(sprintf("=== test_c11_wf_module_window ===\n  CODE_ROOT=%s\n", CODE_ROOT))

P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
finish <- function() {
  cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
  cat(as.character(toJSON(list(test = "test_c11_wf_module_window", pass = P, fail = FL, total = P + FL,
                               skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
  quit(status = if (FL > 0L || length(SKIPS) > 0L) 1L else 0L, save = "no")
}
code <- function(rel) file.path(CODE_ROOT, rel)
TMP <- normalizePath(file.path(tempdir(), paste0("c11wf_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); file.create(EMPTY_RENV)
RSCRIPT <- file.path(R.home("bin"), "Rscript")
run_child <- function(script, envs) {
  keys <- names(envs); old <- Sys.getenv(keys, unset = NA, names = TRUE)
  on.exit(for (k in keys) { if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  do.call(Sys.setenv, as.list(envs))
  out <- suppressWarnings(system2(RSCRIPT, c("--no-save", shQuote(script)), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); list(status = if (is.null(st)) 0L else as.integer(st), out = out)
}
mutate_file <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(dirname(src), paste0("run_wf_ensemble_", tag, ".R")); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}

# ── 샌드박스 ────────────────────────────────────────────────────────────────
PW <- file.path(TMP, "proj")
for (d in c(".cache", "06_Registry", "04_Research/factor_rotation/output", "diag")) dir.create(file.path(PW, d), recursive = TRUE, showWarnings = FALSE)
rels <- c(file.path("02_Infrastructure/contracts", list.files(code("02_Infrastructure/contracts"), pattern = "\\.R$")),
          "02_Infrastructure/portfolio/module_dispatcher.R", "02_Infrastructure/portfolio/regime_module_admission.R",
          "02_Infrastructure/validation/overlay_pit_guard.R", "02_Infrastructure/data/fred_availability.R",
          "06_Registry/fred_availability_rules.json", "04_Research/factor_rotation/run_wf_ensemble.R")
for (r in rels) { dir.create(dirname(file.path(PW, r)), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(code(r), file.path(PW, r), overwrite = TRUE)) stop("copy 실패: ", r) }

set.seed(20260924)
wkdays <- function(a, b) { d <- seq(as.Date(a), as.Date(b), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] }
WD <- wkdays("2012-01-02", "2019-12-31")                                      # 합성 한국 거래일 = 평일
write_parquet(data.table(Date = WD), file.path(PW, ".cache/trading_calendar.parquet"))
SAT <- seq(as.Date("2012-01-07"), as.Date("2019-12-28"), by = "7 days")      # 토요일
CYC <- c("RISK_ON", "NEUTRAL", "CRISIS", "RISK_OFF")
# 국면 패널: 평일 행 = 날마다 바뀌는 라벨 · 가용일 = 다음 평일 / 토요일 행 = 'SATX'(미국 금 세션을 담은 주말 행 모사) · 가용일 = 토요일
UW <- rbind(data.table(Date = WD, Category = CYC[(seq_along(WD) %% 4L) + 1L], avail_date = c(WD[-1], as.Date(NA))),
            data.table(Date = SAT, Category = "SATX", avail_date = SAT))
setorder(UW, Date)
write_parquet(UW, file.path(PW, ".cache/unified_regime_signal_daily.parquet"))
write_parquet(data.table(Date = WD, BM_Ret = round(rnorm(length(WD), 0.0003, 0.011), 6)), file.path(PW, ".cache/benchmark.parquet"))
# 모듈: W1 전 평일 · W2 수요일 결측(공백) · W3 월 중 일요일 행 추가(월말 3일 제외 — 월간 배분 결정일은 건드리지 않게) · W4 전 평일
SUN <- seq(as.Date("2012-01-08"), as.Date("2019-12-29"), by = "7 days")
SUN <- SUN[as.POSIXlt(SUN)$mday <= 25L]
MD <- list(W1 = WD, W2 = WD[as.POSIXlt(WD)$wday != 3L], W3 = sort(c(WD, SUN)), W4 = WD)
mods <- list()
for (k in seq_along(MD)) {
  sid <- names(MD)[k]; d <- MD[[sid]]; dir.create(file.path(PW, "04_Research/strategies", sid), recursive = TRUE, showWarnings = FALSE)
  r <- round(0.0002 * k + 0.008 * sin(seq_along(d) / (5 + 2 * k)) + rnorm(length(d), 0, 0.004), 6)
  saveRDS(list(DAILY_NAV_DT = data.table(Date = d, Strategy_Ret = r), bm_xts = xts(rep(0.0003, length(WD)), order.by = WD), freq = "daily"),
          file.path(PW, "04_Research/strategies", sid, "sim_result.rds"))
  mods[[sid]] <- list(sim_result_path = file.path("04_Research/strategies", sid, "sim_result.rds"), grade = "B",
                      role = if (k == 4) "defensive" else "core", freq = "daily", admission_route = "grade_floor")
}
write_json(list(regimes = as.list(c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS", "RISK_OFF")), modules = mods),
           file.path(PW, "06_Registry/module_performance.json"), auto_unbox = TRUE, pretty = TRUE)

# ── 독립 손 유도: 창 시작 = 자기 직전 행 → 그 날 이하 마지막 평일 · 라벨 = 가용일 <= 결정일 중 관측일 최신 ──
exp_labels <- function(d) {
  dec <- c(as.Date(NA), d[-length(d)])
  snap <- as.Date(vapply(as.integer(dec), function(x) { if (is.na(x)) return(NA_integer_); k <- WD[as.integer(WD) <= x]
    if (length(k)) as.integer(k[length(k)]) else NA_integer_ }, integer(1)), origin = "1970-01-01")
  lab <- vapply(as.integer(snap), function(x) { if (is.na(x)) return(NA_character_); k <- which(as.integer(UW$avail_date) <= x)
    if (!length(k)) NA_character_ else UW$Category[k[which.max(as.integer(UW$Date[k]))]] }, character(1))
  data.table(Date = d, dec_exp = snap, label_exp = lab)
}
EXP <- rbindlist(lapply(names(MD), function(s) cbind(module = s, exp_labels(MD[[s]]))))

WN <- file.path(PW, "04_Research/factor_rotation/run_wf_ensemble.R")
wf_run <- function(script, tag) {
  r <- run_child(script, c(QM_ROOT = PW, CLAUDE_PROJECT_DIR = PW, R_ENVIRON_USER = EMPTY_RENV, FR_REGISTER = "0",
                           FR_RUN_ID = tag, FR_DIAG_DIR = file.path(PW, "diag"), FR_DIAG_IS_LABELS = "1", FR_EXTRA_REGIME_LAG = "0",
                           FR_ARM_TAG = "", QVEST_C11_LEGACY_REGIME = "", FR_MODULE_PERF = "", FR_REGIME_SOURCE = "",
                           FR_SELECTION_TYPE = "", QVEST_LABEL_GATE_MODE = "warn", QVEST_TG_DRY_RUN = "1"))
  f <- file.path(PW, "diag", paste0(tag, "_is_regime_labels.csv"))
  lab <- if (file.exists(f)) fread(f, colClasses = list(character = c("module", "label"))) else NULL
  if (!is.null(lab)) { lab[, Date := as.Date(Date)]; lab[, dec_date := as.Date(dec_date)] }
  list(r = r, lab = lab)
}
cmp <- function(lab) {
  if (is.null(lab)) return(NULL)
  m <- merge(EXP, lab[, .(module, Date, dec_date, label)], by = c("module", "Date"), all.x = TRUE)
  m[, same := (is.na(label_exp) & (is.na(label) | label == "")) | (!is.na(label_exp) & !is.na(label) & label_exp == label)]
  m
}

cat("\n── A. 수리판: 모듈별 라벨 = 손 유도 ──\n")
w0 <- wf_run(WN, "FR_WIN")
ok(w0$r$status == 0L, sprintf("A0 완주(status %d)", w0$r$status))
if (w0$r$status != 0L) cat(tail(w0$r$out, 25), sep = "\n")
ok(any(grepl("모듈별 자기 직전 행", w0$r$out, fixed = TRUE)), "A0b 모듈별 창 시작 경로 로그")
M0 <- cmp(w0$lab)
ok(!is.null(M0) && nrow(M0) == nrow(EXP), sprintf("A1 진단 라벨 %s행 = 기대 %d행(4모듈 전 행)", if (is.null(M0)) "NA" else nrow(M0), nrow(EXP)))
if (!is.null(M0)) {
  for (s in names(MD)) ok(all(M0[module == s, same]), sprintf("A2 %s 전 행 라벨 = 손 유도(불일치 %d)", s, sum(!M0[module == s, same])))
  thu <- M0[module == "W2" & as.POSIXlt(Date)$wday == 4L]
  ok(nrow(thu) > 300L && all(thu$dec_date[-1] == thu$Date[-1] - 2L),
     sprintf("A3 ★W2(수요일 결측) 목요일 수익의 창 시작 = 화요일(자기 직전 행) — %d주", nrow(thu)))
  # 토요일 행은 월요일 15:30 결정엔 정당하게 가용하다(화요일 수익 라벨엔 SATX 가 나온다). 누출 지문 = **일요일 행 뒤 월요일 수익**
  #   (수익 창 = 금 종가 → 월 종가)이 토요일 행을 쓰는 것.
  mon <- M0[module == "W3" & as.POSIXlt(Date)$wday == 1L & (Date - 1L) %in% SUN]
  ok(nrow(mon) > 100L && !any(mon$label == "SATX", na.rm = TRUE), "A4 ★W3 일요일 행 뒤 월요일 수익 라벨에 토요일 행(SATX) 0건 — 창 시작을 한국 거래일로 내림")
  ok(nrow(mon) > 100L && all(as.POSIXlt(mon$dec_date)$wday == 5L), sprintf("A5 W3 일요일 뒤 월요일 창 시작 = 금요일(%d건)", nrow(mon)))
}

cat("\n── B. 위반 주입(같은 픽스처에서 빨개져야 한다) ──\n")
muts <- list(
  list(tag = "union",  new = ".dec_s <- .WF_C11$c11_window_start(RM_DATES, kr_calendar = .kr_cal)[match(.ds, RM_DATES)]",
       why = "합성 결정일 = RM 합집합 직전 행(구 r0 방식 · V4 MG)", chk = function(m) !all(m[module == "W2", same])),
  list(tag = "nosnap", new = ".dec_s <- .WF_C11$c11_window_start(.ds)",
       why = "한국 거래일 내림 삭제", chk = function(m) any(m[module == "W3" & as.POSIXlt(Date)$wday == 1L & (Date - 1L) %in% SUN, label] == "SATX", na.rm = TRUE)),
  list(tag = "sameday", new = ".dec_s <- .ds",
       why = "결정일 = 수익일 당일", chk = function(m) !all(m$same)))
OLD <- ".dec_s <- .WF_C11$c11_window_start(.ds, kr_calendar = .kr_cal)"
for (mu in muts) {
  fm <- mutate_file(WN, OLD, mu$new, mu$tag)
  if (is.na(fm)) { ok(FALSE, sprintf("B %s 돌연변이 대상 줄 부재", mu$tag)); next }
  wm <- wf_run(fm, paste0("FR_M_", mu$tag)); mm <- cmp(wm$lab)
  ok(wm$r$status != 0L || (!is.null(mm) && isTRUE(mu$chk(mm))),
     sprintf("B %s ★red: %s (status %d · 라벨 불일치 %s)", mu$tag, mu$why, wm$r$status, if (is.null(mm)) "NA" else sum(!mm$same)))
}
finish()
