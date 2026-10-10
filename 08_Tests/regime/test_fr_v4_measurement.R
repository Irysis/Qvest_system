#!/usr/bin/env Rscript
# =============================================================================
# test_fr_v4_measurement.R — run_wf_ensemble v4 측정 수리 양방향 검사
#   (결정 CALMAR-FREQ-DAILY · FR-REMEASURE-PREREG · FR 시리즈 감사 wf_d1890719-231 · 2026-09-24)
# =============================================================================
# 막는 결함:
#   ① 등급 Calmar 가 월간 NAV 에서 나왔다(1계층 = 일간) → 등급 = 일간 bt_result · 일간 격자 = 한국 거래일.
#   ② 월말 RM 날짜가 일요일(주말 라벨 모듈 행)이면 구판 정확 일치 병합이 NA → NEUTRAL 강제 → 결정일을 한국 거래일로 내림
#      + 평가 월 NEUTRAL 강제 = 중단.
#   ③ 데이터가 끝난 모듈이 편입돼 NA→0(현금)으로 채워졌다 → r1(2026-09-25 적대 검증 BLOCKING 수리): **결정 시점에 이미 끝난**
#      모듈만 편입 제외(as-of) + 월중 사망 = 관측일(종료 뒤 첫 한국 거래일) 종가 재배분 + HARD 사후검사(관측일 뒤 비중 0).
#      r0 의 '홀딩월 마지막 평가일' 기준 제외는 결정 시점에 살아 있던 모듈을 그 달 시작부터 뺐다(월중 사망 선견 — A19 가 잡는다).
#   ④ SR·Calmar(성과 전 행)와 PORT_t·OOS(벤치 병합 행)가 다른 창 → 평가 창 = 벤치 기간 안 · 같은 날짜 집합.
#   ⑤ FR_REGISTER 기본 = 0(등재는 "1" 명시 때만).
#   ⑥ (v4r2 · 2026-10-10 · 감사 I7) 벤치를 '가장 긴 bm_xts' 모듈에서 가져와 그 모듈의 날짜 라벨(+1일)을 들였고 격자 어긋남은 기록만 했다
#      → 벤치 = 정본 .cache/benchmark.parquet BM_Ret(같은 날짜) · 풀 모듈 시차 ≠0/NA = 중단 · 정본 벤치가 거래일 격자에 제 날짜로 안 놓이면 중단(§E).
# 방법: 합성 샌드박스(평일 = 한국 거래일 · 일요일 월말 행 모듈 · 중도 사망 모듈 · 토요일 가용 국면 행 · 벤치가 먼저 끝남)에서
#   자식 실행 → 산출(결과 JSON · 진단 CSV · bt_result)을 **검사 대상과 독립인 손 유도**와 대조. 분해 대조(FR_V4_ABLATE)와
#   돌연변이 7종은 같은 픽스처에서 빨개져야 한다.
# 운영 무쓰기: 전부 tempdir 샌드박스. 자식 = 빈 Renviron + QM_ROOT/CLAUDE_PROJECT_DIR = 샌드박스. 끝에서 운영 파일 불변 단정.
# 실행: Rscript 08_Tests/regime/test_fr_v4_measurement.R
#   env FRV4_CODE_ROOT = run_wf_ensemble.R 를 읽을 트리(기본 = 이 파일 기준 저장소) · FRV4_INFRA_ROOT = 계약·도우미 트리(기본 = CODE_ROOT)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow); library(xts) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else "."
}, error = function(e) ".")
CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("FRV4_CODE_ROOT", ""))
if (!nzchar(CODE_ROOT)) CODE_ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(CODE_ROOT, "04_Research/factor_rotation/run_wf_ensemble.R")))
  CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
INFRA_ROOT <- gsub("\\\\", "/", Sys.getenv("FRV4_INFRA_ROOT", CODE_ROOT))
OPS_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", INFRA_ROOT))
cat(sprintf("=== test_fr_v4_measurement ===\n  CODE_ROOT=%s\n  INFRA_ROOT=%s\n", CODE_ROOT, INFRA_ROOT))
for (.k in c("QVEST_C11_LEGACY_REGIME", "FR_MODULE_PERF", "FR_REGIME_SOURCE", "FR_V4_ABLATE", "FR_REGISTER", "FR_SELECTION_TYPE")) Sys.unsetenv(.k)

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
.s <- function(x) if (is.null(x) || !length(x)) "NA" else as.character(x)[1]   # 메시지 인자(NULL 이면 sprintf 가 문자열 전체를 없앤다)
P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
finish <- function() {
  cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
  cat(as.character(toJSON(list(test = "test_fr_v4_measurement", pass = P, fail = FL, total = P + FL,
                               skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
  ## 성공 시 quit 하지 않는다 — 08_Tests/regime/run_all.R 가 같은 프로세스에서 sys.source 한다(수렴 규약).
  if (FL > 0L || length(SKIPS) > 0L) quit(status = 1L, save = "no")
  invisible(TRUE)
}

# ── 운영 무쓰기 기준선 ─────────────────────────────────────────────────────────
OPS_FILES <- file.path(OPS_ROOT, c("06_Registry/factor_rotation_registry.json", "06_Registry/module_performance.json"))
OPS_FILES <- OPS_FILES[file.exists(OPS_FILES)]
MD5_BEFORE <- tools::md5sum(OPS_FILES)
FR_OUT_OPS <- file.path(OPS_ROOT, "04_Research/factor_rotation/output")
FR_OUT_BEFORE <- if (dir.exists(FR_OUT_OPS)) sort(list.files(FR_OUT_OPS, recursive = TRUE)) else character(0)

TMP <- normalizePath(file.path(tempdir(), paste0("frv4_", Sys.getpid())), winslash = "/", mustWork = FALSE)
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
  f <- file.path(dirname(src), paste0("rwe_", tag, ".R")); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}

# ── 샌드박스 ────────────────────────────────────────────────────────────────
PW <- file.path(TMP, "proj")
for (d in c(".cache", "06_Registry", "04_Research/factor_rotation/output", "diag", "02_Infrastructure")) dir.create(file.path(PW, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# sandbox marker (factor_rotation_registry 루트 판정용)", file.path(PW, "02_Infrastructure/config.R"))
rels <- c(file.path("02_Infrastructure/contracts", list.files(file.path(INFRA_ROOT, "02_Infrastructure/contracts"), pattern = "\\.R$")),
          "02_Infrastructure/portfolio/module_dispatcher.R", "02_Infrastructure/portfolio/regime_module_admission.R",
          "02_Infrastructure/validation/overlay_pit_guard.R", "02_Infrastructure/data/fred_availability.R",
          "06_Registry/fred_availability_rules.json")
for (r in rels) { dir.create(dirname(file.path(PW, r)), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(file.path(INFRA_ROOT, r), file.path(PW, r), overwrite = TRUE)) stop("copy 실패: ", r) }
WN <- file.path(PW, "04_Research/factor_rotation/run_wf_ensemble.R")
dir.create(dirname(WN), recursive = TRUE, showWarnings = FALSE)
if (!file.copy(file.path(CODE_ROOT, "04_Research/factor_rotation/run_wf_ensemble.R"), WN, overwrite = TRUE)) stop("copy 실패: run_wf_ensemble.R")

set.seed(20260924)
wkdays <- function(a, b) { d <- seq(as.Date(a), as.Date(b), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] }
WD <- wkdays("2012-01-02", "2019-12-31")                                      # 합성 한국 거래일 = 평일
write_parquet(data.table(Date = WD), file.path(PW, ".cache/trading_calendar.parquet"))
BMR <- round(rnorm(length(WD), 0.0003, 0.011), 6)
# 일요일 월말(모듈 W1 에 그 일요일 행을 둔다 → RM 월말 = 일요일)
ALLD <- seq(as.Date("2012-01-01"), as.Date("2019-12-31"), by = "day")
MEND <- ALLD[!duplicated(format(ALLD, "%Y%m"), fromLast = TRUE)]
SUNME <- MEND[as.POSIXlt(MEND)$wday == 0L]
BM_END <- as.Date("2019-06-28")                                                # 벤치가 모듈보다 먼저 끝난다(④)
BM_GAP <- WD[seq(40L, length(WD), by = 97L)]; BM_GAP <- BM_GAP[BM_GAP <= BM_END]   # 벤치 세션 결측일(④ 0 채움 대상)
## ★v4r2(2026-10-10 · I7): 벤치 = 정본 .cache/benchmark.parquet BM_Ret. ④ 픽스처(먼저 끝남 · 세션 결측일)를 **정본 파일**에 싣는다
##   (구판은 이 성질을 '가장 긴 bm_xts' 모듈 W1 에 실었다). 모듈 bm_xts 는 같은 값(정렬 = 시차 0)이라 격자 감사를 통과한다.
BMD <- as.Date(setdiff(WD[WD <= BM_END], BM_GAP), origin = "1970-01-01")
write_parquet(data.table(Date = BMD, BM_Ret = BMR[match(BMD, WD)]), file.path(PW, ".cache/benchmark.parquet"))
DEAD_END <- as.Date("2018-03-14")                                              # ③ 사망 모듈 데이터 종료(평가 구간 2017-01~ 안 · 월 중간)
mk_mod <- function(k, d, drift) round(drift + 0.006 * sin(seq_along(d) / (4 + 2 * k)) + rnorm(length(d), 0, 0.004), 6)
MODS <- list(W1 = sort(c(WD, SUNME)), W2 = WD, W3 = WD, W4 = WD, W5 = WD[WD <= DEAD_END])
DRIFT <- c(W1 = 0.0003, W2 = 0.0002, W3 = 0.0004, W4 = 0.0001, W5 = 0.0012)     # W5 = 죽기 전 성과 최상(편입될 모듈)
write_mods <- function(pad_zero = FALSE) {
  mods <- list()
  for (k in seq_along(MODS)) {
    sid <- names(MODS)[k]; d <- MODS[[sid]]; dir.create(file.path(PW, "04_Research/strategies", sid), recursive = TRUE, showWarnings = FALSE)
    set.seed(1000L + k); r <- mk_mod(k, d, DRIFT[[sid]])
    if (sid == "W5" && pad_zero) { dz <- WD[WD > DEAD_END]; d <- c(d, dz); r <- c(r, rep(0, length(dz))) }   # 생산자가 0 으로 덧댄 판
    bd <- if (sid == "W1") setdiff(WD[WD <= BM_END], BM_GAP) else WD
    bd <- as.Date(bd, origin = "1970-01-01")
    saveRDS(list(DAILY_NAV_DT = data.table(Date = d, Strategy_Ret = r), bm_xts = xts(BMR[match(bd, WD)], order.by = bd), freq = "daily"),
            file.path(PW, "04_Research/strategies", sid, "sim_result.rds"))
    mods[[sid]] <- list(sim_result_path = file.path("04_Research/strategies", sid, "sim_result.rds"), grade = "B",
                        role = "core", freq = "daily", admission_route = "grade_floor")
  }
  write_json(list(regimes = as.list(c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS", "RISK_OFF")), modules = mods),
             file.path(PW, "06_Registry/module_performance.json"), auto_unbox = TRUE, pretty = TRUE)
}
# W1 bm_xts 는 짧고(BM_END) 결측(BM_GAP)이 있어도 가장 길어야 bmref(가장 긴 bm_xts)가 된다 → 다른 모듈 bm_xts 를 더 짧게.
#   ★v4r2: 정본 경로는 bm_xts 를 벤치로 쓰지 않는다 — 이 배치는 분해 대조(FR_V4_ABLATE=canonical_bench = 구판 최장 bm_xts)가
#   정본과 **같은 벤치**(W1 bm_xts = 정본 값)를 집게 해 E5 양성 대조(정렬 픽스처에선 결과 동일)를 만든다.
write_mods_bm <- function(pad_zero = FALSE) {
  write_mods(pad_zero)
  for (sid in setdiff(names(MODS), "W1")) { f <- file.path(PW, "04_Research/strategies", sid, "sim_result.rds"); z <- readRDS(f)
    bd <- WD[WD <= as.Date("2014-12-31")]; z$bm_xts <- xts(BMR[match(bd, WD)], order.by = bd); saveRDS(z, f) }
}
# 국면 패널: 평일 행 = 월별 순환 라벨 · 월말 평일 = CAUTION(당일 라벨 누출 지문) · 가용일 = 다음 평일.
#   토요일 행 = SATX(미국 금 세션을 담은 주말 행 모사) · 가용일 = 토요일 — 일요일 결정일을 내리지 않으면 이 행이 배분에 들어온다.
CYC <- c("RISK_ON", "NEUTRAL", "CRISIS", "RISK_OFF")
xm <- function(ym) { y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 5, 6)); CYC[((y * 12 + m) %% 4) + 1L] }
WME <- WD[!duplicated(format(WD, "%Y%m"), fromLast = TRUE)]
SAT <- ALLD[as.POSIXlt(ALLD)$wday == 6L]
UW <- rbind(data.table(Date = WD, Category = xm(format(WD, "%Y%m")), avail_date = c(WD[-1], as.Date(NA))),
            data.table(Date = SAT, Category = "SATX", avail_date = SAT))
UW[Date %in% WME, Category := "CAUTION"]
setorder(UW, Date)
write_panel <- function(p) write_parquet(p, file.path(PW, ".cache/unified_regime_signal_daily.parquet"))

wf_run <- function(script, tag, extra = character(0)) {
  env <- c(QM_ROOT = PW, CLAUDE_PROJECT_DIR = PW, R_ENVIRON_USER = EMPTY_RENV, FR_RUN_ID = tag, FR_DIAG_DIR = file.path(PW, "diag"),
           FR_EXTRA_REGIME_LAG = "0", FR_ARM_TAG = "", QVEST_C11_LEGACY_REGIME = "", FR_MODULE_PERF = "", FR_REGIME_SOURCE = "",
           FR_SELECTION_TYPE = "", FR_V4_ABLATE = "", FR_REGISTER = "", QVEST_LABEL_GATE_MODE = "warn", QVEST_TG_DRY_RUN = "1")
  env[names(extra)] <- extra
  if (!nzchar(env[["FR_REGISTER"]])) env <- env[names(env) != "FR_REGISTER"]      # 미설정 = 기본값 검사
  r <- run_child(script, env)
  ids <- sub("_result\\.json$", "", list.files(file.path(PW, "04_Research/factor_rotation/output"), pattern = paste0("^", tag, ".*_result\\.json$")))
  id <- if (length(ids)) ids[which.min(nchar(ids))] else NA_character_
  j <- if (!is.na(id)) fromJSON(file.path(PW, "04_Research/factor_rotation/output", paste0(id, "_result.json")), simplifyVector = FALSE) else NULL
  bt <- if (!is.na(id)) tryCatch(readRDS(file.path(PW, "04_Research/factor_rotation/output", paste0(id, "_bt_result.rds"))), error = function(e) NULL) else NULL
  dd <- if (!is.na(id) && file.exists(f <- file.path(PW, "diag", paste0(id, "_dispatch_decisions.csv")))) fread(f, colClasses = list(character = "ym")) else NULL
  adm <- if (!is.na(id) && file.exists(f <- file.path(PW, "diag", paste0(id, "_admitted_by_month.rds")))) readRDS(f) else NULL
  dg <- if (!is.na(id) && file.exists(f <- file.path(PW, "diag", paste0(id, "_dispatch_diag.csv")))) fread(f, colClasses = list(character = "ym")) else NULL
  list(r = r, id = id, j = j, bt = bt, dd = dd, adm = adm, dg = dg)
}
clean_out <- function() { unlink(list.files(file.path(PW, "04_Research/factor_rotation/output"), full.names = TRUE))
  unlink(list.files(file.path(PW, "diag"), full.names = TRUE)); unlink(file.path(PW, "06_Registry/factor_rotation_registry.json")) }

# ── 독립 손 유도 ──────────────────────────────────────────────────────────────
# 월 m 배분: 월말 RM 날짜(모듈 날짜 합집합의 그 달 마지막 날) of m-1 → 그 날 이하 마지막 평일 → 가용일 <= 그 날인 행 중 관측일 최신.
RMD <- sort(unique(do.call(c, MODS)))
ME <- data.table(Date = RMD)[, .(me = max(Date)), by = .(ym = format(Date, "%Y%m"))]
floor_wd <- function(x) as.Date(vapply(as.integer(x), function(v) { if (is.na(v)) return(NA_integer_); k <- WD[as.integer(WD) <= v]
  if (length(k)) as.integer(k[length(k)]) else NA_integer_ }, integer(1)), origin = "1970-01-01")
asof_lab <- function(dec, panel) vapply(as.integer(dec), function(v) { if (is.na(v)) return(NA_character_)
  k <- which(!is.na(panel$avail_date) & as.integer(panel$avail_date) <= v & !is.na(panel$Category))
  if (!length(k)) NA_character_ else panel$Category[k[which.max(as.integer(panel$Date[k]))]] }, character(1))
exp_dispatch <- function(panel, floor = TRUE) {
  e <- copy(ME); e[, dec_raw := shift(me, 1L)]; e[, dec := if (floor) floor_wd(dec_raw) else dec_raw]; e[, lab := asof_lab(dec, panel)]; e }

# =============================================================================
cat("\n── A. 신판(수리 전부 · 기본 env) ──\n")
write_mods_bm(); write_panel(UW); clean_out()
A <- wf_run(WN, "FRV4A")
ok(A$r$status == 0L && !is.null(A$j), sprintf("A0 완주(status %d)", A$r$status))
if (A$r$status != 0L) cat(tail(A$r$out, 30), sep = "\n")
EXP <- exp_dispatch(UW, TRUE)
if (!is.null(A$dd)) {
  m <- merge(A$dd[, .(ym, dec_date = as.Date(dec_date), dec_date_raw = as.Date(dec_date_raw), regime_lag, eval_month)], EXP, by = "ym")
  ok(nrow(m) > 60L && all(m$dec_date == m$dec | (is.na(m$dec_date) & is.na(m$dec))), sprintf("A1 ② 결정일 = 월말 RM 날짜를 평일로 내린 날(손 유도 %d개월)", nrow(m)))
  sun_m <- m[weekdays(dec_raw) %in% weekdays(as.Date("2024-03-31"))]                # 원 결정일이 일요일인 달
  ok(nrow(sun_m) >= 5L && all(as.POSIXlt(sun_m$dec_date)$wday == 5L), sprintf("A2 ★일요일 월말 %d개월 → 결정일 금요일", nrow(sun_m)))
  ok(all(m$regime_lag == m$lab | is.na(m$lab)), "A3 배분 라벨 = 손 유도 as-of 라벨(전 월)")
  ## 토요일 행은 월요일 결정엔 정당하게 가용하다(월말이 월요일인 달). 누출 지문 = 일요일 월말 → 결정일을 안 내리면 토요일 행을 쓴다.
  ok(nrow(sun_m[eval_month == TRUE]) >= 3L && !any(sun_m[eval_month == TRUE, regime_lag] == "SATX") && !any(m$regime_lag == "CAUTION"),
     sprintf("A4 ★일요일 월말 뒤 평가 월 %d개 배분에 토요일 행(SATX) 0건 · 월말 당일 라벨(CAUTION) 0건", nrow(sun_m[eval_month == TRUE])))
  ok(all(!is.na(m[eval_month == TRUE, lab])) && isTRUE(A$j$dispatch$n_neutral_forced_eval == 0L),
     "A5 평가 월 전부 가용 라벨 있음 · NEUTRAL 강제 0건")
} else ok(FALSE, "A1 dispatch_decisions.csv 부재")
if (!is.null(A$j)) {
  J <- A$j
  ok(identical(J$grade_frequency, "daily"), "A6 ① 등급 빈도 = daily")
  pr <- if (!is.null(A$bt)) as.data.table(A$bt$period_returns) else NULL
  ok(!is.null(pr) && all(pr$frequency == "daily") && isTRUE(abs(as.numeric(as.data.table(A$bt$metrics)$annualization_factor[1]) - 252) < 1e-9),
     "A7 ① 등급 bt_result = 일간 · 연율 252(계약 유도)")
  ok(!is.null(pr) && all(as.Date(pr$date) %in% WD), "A8 ① 일간 격자 = 한국 거래일(일요일 월말 행이 격자에 없다)")
  # 독립 재도출: 등급 Calmar = 일간 NAV 의 CAGR / 일간 MDD
  if (!is.null(pr)) {
    nav <- cumprod(1 + pr$ret_net); cagr <- (nav[length(nav)] / nav[1])^(252 / length(nav)) - 1
    dd <- 1 - nav / cummax(c(1, nav))[-1]; mdd <- max(dd)
    ok(isTRUE(abs(round(cagr / mdd, 3) - J$essence$calmar) <= 0.0011), sprintf("A9 ★등급 Calmar = 일간 CAGR/MDD 손 재도출(%.3f vs essence %s)", cagr / mdd, .s(J$essence$calmar)))
  }
  ok(isTRUE(J$eval_window$n_period_returns == J$eval_window$n_bench_merged), sprintf("A10 ④ 단일 창: 성과 %s행 = 벤치 병합 %s행", .s(J$eval_window$n_period_returns), .s(J$eval_window$n_bench_merged)))
  ok(!is.null(pr) && max(as.Date(pr$date)) <= BM_END && as.Date(J$eval_window$end) <= BM_END,
     sprintf("A11 ④ 평가 창 끝(%s) <= 벤치 끝(%s) — 벤치 없는 달을 SR·Calmar 에 넣지 않는다", .s(J$eval_window$end), .s(BM_END)))
  ok(isTRUE(J$eval_window$n_port_days_no_bench >= 1L), sprintf("A12 ④ 벤치 세션 결측일 %s일 = 0 채움(같은 날짜 집합 유지)", .s(J$eval_window$n_port_days_no_bench)))
  ok(isTRUE(J$dead_modules$n_post_death_zero_filled == 0L) && isTRUE(J$dead_modules$n_module_months_excluded >= 1L) &&
       isTRUE(J$dead_modules$n_midmonth_renorm_rows >= 1L),
     sprintf("A13 ③ 관측일 뒤 현금화 0 · 결정 시점 편입 제외 %s 모듈·월 · 월중 재배분 %s행", .s(J$dead_modules$n_module_months_excluded),
             .s(J$dead_modules$n_midmonth_renorm_rows)))
  if (!is.null(A$adm)) {
    late <- Filter(function(x) x$ym > format(DEAD_END, "%Y%m"), A$adm)
    ok(length(late) > 6L && !any(vapply(late, function(x) "W5" %in% x$admitted, logical(1))), sprintf("A14 ③ W5 사망 뒤 %d개월 편입 0", length(late)))
    pre <- Filter(function(x) x$ym < format(DEAD_END, "%Y%m"), A$adm)
    ok(any(vapply(pre, function(x) "W5" %in% x$admitted, logical(1))), "A15 ③ 양성 대조: W5 는 살아 있을 때 편입됐다(검사가 헛돌지 않는다)")
    ## A19 ★as-of: 사망 월(2018-03)의 결정 시점(2018-02 말)에 W5 는 살아 있었다 → 그 달 편입 후보에 있어야 한다.
    ##   r0(홀딩월 마지막 평가일 기준)는 여기서 W5 를 뺐다 = 3월 중순 사망을 2월 말에 안 것(선견).
    dm <- A$adm[[format(DEAD_END, "%Y%m")]]
    ok(!is.null(dm) && "W5" %in% dm$admitted, sprintf("A19 ★③ as-of: 사망 월 %s 결정 시점엔 W5 생존 → 편입 후보 유지(홀딩월 정보로 빼지 않는다)", format(DEAD_END, "%Y%m")))
  }
  ## A20/A21 ★월중 재배분 손 재도출 — 관측일 = DEAD_END 뒤 첫 평일(합성 한국 거래일). 그 날 종가 EOP 에서 W5 몫을 생존 보유 모듈로 비례 재배분.
  OBS_EXP <- min(WD[WD > DEAD_END])
  evs <- J$dead_modules$renorm_events %||% list()
  e5 <- Filter(function(e) "W5" %in% unlist(e$modules), evs)
  RW <- if (file.exists(f <- file.path(PW, "diag", paste0(A$id, "_rebalance_weights.csv")))) fread(f) else NULL
  if (length(e5) == 1L && !is.null(RW)) {
    RW[, Date := as.Date(Date)]
    mods <- setdiff(names(RW), "Date")
    r0 <- RW[Date < OBS_EXP][.N]                                          # 관측일 직전 리밸 행(3월 월초 행)
    grid <- sort(unique(do.call(c, lapply(names(MODS), function(s) readRDS(file.path(PW, "04_Research/strategies", s, "sim_result.rds"))$DAILY_NAV_DT$Date))))
    seg <- grid[grid > r0$Date & grid <= OBS_EXP]
    gr <- vapply(mods, function(s) { z <- as.data.table(readRDS(file.path(PW, "04_Research/strategies", s, "sim_result.rds"))$DAILY_NAV_DT)
      v <- z$Strategy_Ret[match(seg, as.Date(z$Date))]; v[!is.finite(v)] <- 0; prod(1 + v) }, numeric(1))
    v <- unlist(r0[, ..mods]) * gr
    mv_hand <- unname(v[["W5"]] / sum(v)); v[["W5"]] <- 0; w_hand <- v / sum(v)
    r1 <- RW[Date == OBS_EXP]
    ok(identical(e5[[1]]$date, as.character(OBS_EXP)) && nrow(r1) == 1L && isTRUE(abs(e5[[1]]$moved_weight - mv_hand) < 1e-4) &&
         isTRUE(max(abs(unlist(r1[, ..mods]) - w_hand)) < 1e-8) && isTRUE(unlist(r1[, "W5"]) == 0),
       sprintf("A20 ★③ 월중 재배분 = 관측일 %s 종가(사망일 %s 아님) · W5 드리프트 몫 %.6f(손 재도출 %.6f) · 재배분 비중 손 재도출 일치",
               .s(e5[[1]]$date), as.character(DEAD_END), as.numeric(e5[[1]]$moved_weight %||% NA), mv_hand))
  } else ok(FALSE, sprintf("A20 ③ W5 재배분 사건 %d건 · 비중 CSV %s", length(e5), if (is.null(RW)) "없음" else "있음"))
  ok(isTRUE(J$dead_modules$n_obs_lag_cash_days == 1L),
     sprintf("A21 ③ 관측 지연 현금 = 사망일 뒤~관측일 격자 1일(%s) — 기록 %s", as.character(OBS_EXP), .s(J$dead_modules$n_obs_lag_cash_days)))
  ok(!file.exists(file.path(PW, "06_Registry/factor_rotation_registry.json")) && any(grepl("등재 생략", A$r$out)),
     "A16 ⑤ FR_REGISTER 미설정 = 등재 안 함")
  ok(is.list(J$diagnostic_other_frequency) && identical(J$diagnostic_other_frequency$frequency, "monthly") && !is.null(J$diagnostic_other_frequency$calmar),
     "A17 ① 월간 판 = 진단 병기(diagnostic_other_frequency)")
  ok(identical(J$grid_audit$bmref_lag, 0L) && identical(length(J$grid_audit$misaligned_used), 0L), "A18 격자 감사: 정렬 픽스처 = 시차 0 · 경고 없음")
}

cat("\n── B. ⑤ 등재 양성 대조 · ③ 0 덧댐 · 분해 대조(구판 동작 재현) ──\n")
clean_out(); B1 <- wf_run(WN, "FRV4R", c(FR_REGISTER = "1"))
ok(B1$r$status == 0L && file.exists(file.path(PW, "06_Registry/factor_rotation_registry.json")), "B1 ⑤ 양성 대조: FR_REGISTER=1 이면 샌드박스 레지스트리에 등재")
write_mods_bm(pad_zero = TRUE); clean_out()
B2 <- wf_run(WN, "FRV4Z")
ok(B2$r$status == 0L && !is.null(B2$adm) && !any(vapply(Filter(function(x) x$ym > format(DEAD_END, "%Y%m"), B2$adm), function(x) "W5" %in% x$admitted, logical(1))),
   "B2 ③ ★위반 주입: 사망 뒤 0 수익을 덧댄 W5 도 편입 제외(끝의 0 연속 = 채움)")
write_mods_bm(); clean_out()
B3 <- wf_run(WN, "FRV4X", c(FR_V4_ABLATE = "dead_exclude"))
ok(B3$r$status == 0L && isTRUE(B3$j$dead_modules$n_post_death_zero_filled > 0L),
   sprintf("B3 ③ 분해(dead_exclude 끔) = 구판 결함 재현: 사망 뒤 NA→0 %s 모듈·일", .s(B3$j$dead_modules$n_post_death_zero_filled)))
ok(B3$r$status == 0L && grepl("v4ablate-X", B3$id %||% "") && !file.exists(file.path(PW, "06_Registry/factor_rotation_registry.json")),
   "B3b 분해 대조 = _v4ablate 태그 · 등재 없음")
B4 <- wf_run(WN, "FRV4K", c(FR_V4_ABLATE = "dispatch_kr_floor"))
EXPN <- exp_dispatch(UW, FALSE)
if (!is.null(B4$dd)) {
  m4 <- merge(B4$dd[, .(ym, regime_lag, eval_month)], EXPN, by = "ym")
  ok(any(m4[eval_month == TRUE, regime_lag] == "SATX") && all(m4$regime_lag == m4$lab | is.na(m4$lab)),
     sprintf("B4 ② 분해(kr_floor 끔): 일요일 결정일이 토요일 행(SATX)을 %d개월 씀 — 내림이 결과를 바꾼다", sum(m4[eval_month == TRUE, regime_lag] == "SATX")))
} else ok(FALSE, "B4 분해 실행 실패")
B5 <- wf_run(WN, "FRV4M", c(FR_V4_ABLATE = "daily_grade,single_window"))
ok(B5$r$status == 0L && identical(B5$j$grade_frequency, "monthly") && isTRUE(B5$j$eval_window$n_period_returns != B5$j$eval_window$n_bench_merged ||
   as.Date(B5$j$eval_window$end) > BM_END), "B5 ①④ 분해 = 구판 재현: 월간 등급 · 성과 창 ≠ 벤치 병합 창")
# 구판 결함 재현(legacy label 정책): 날짜 라벨 정확 일치 → 일요일 월말 다음 달 NEUTRAL 강제
write_panel(UW[, .(Date, Category)]); clean_out()
B6 <- wf_run(WN, "FRV4L", c(QVEST_C11_LEGACY_REGIME = "label"))
ok(B6$r$status == 0L && isTRUE(B6$j$dispatch$n_neutral_forced_eval >= 1L),
   sprintf("B6 ② 구판 결함 재현(legacy 정확 일치): 평가 월 NEUTRAL 강제 %s개월 — 기록됨", .s(B6$j$dispatch$n_neutral_forced_eval)))
# NEUTRAL 강제 = 중단: 2016년 말까지 모든 행의 가용일 NA(아직 불가) → 첫 평가 월(2017-01)의 결정일에 as-of 로도 가용 라벨이 없다
UG <- copy(UW); UG[Date <= as.Date("2016-12-31"), avail_date := as.Date(NA)]
write_panel(UG); clean_out()
B7 <- wf_run(WN, "FRV4N")
ok(B7$r$status != 0L && any(grepl("FR v4 ②", B7$r$out, fixed = TRUE)), "B7 ② 평가 월 가용 라벨 없음 → NEUTRAL 로 지어내지 않고 중단")
B7b <- wf_run(WN, "FRV4NK", c(FR_V4_ABLATE = "dispatch_kr_floor"))
ok(B7b$r$status == 0L && isTRUE(B7b$j$dispatch$n_neutral_forced_eval >= 1L), "B7b 분해(kr_floor 끔)는 구판처럼 NEUTRAL 로 진행·기록(중단 조건이 ②에 묶여 있음)")
write_panel(UW)

cat("\n── C. 돌연변이(같은 픽스처에서 빨개져야 한다) ──\n")
muts <- list(
  list(tag = "nofloor", old = 'mreg[, dec_date := as.Date(.fl, origin = "1970-01-01")]', new = 'invisible(NULL)',
       chk = function(w) w$r$status != 0L || is.null(w$dd) || any(w$dd[eval_month == TRUE, regime_lag] == "SATX")),
  list(tag = "nodead", old = 'n_dead_excl <- length(.dead); avail <- setdiff(avail, .dead)', new = 'n_dead_excl <- 0L',
       chk = function(w) w$r$status != 0L),
  list(tag = "nodeadchk", old = 'n_dead_excl <- length(.dead); avail <- setdiff(avail, .dead)', new = 'n_dead_excl <- 0L',
       post = list(old = 'if (isTRUE(FIX$dead_exclude) && NA_FILL$n_post_death > 0L)', new = 'if (FALSE)'),
       chk = function(w) w$r$status != 0L || is.null(w$adm) || any(vapply(Filter(function(x) x$ym > format(DEAD_END, "%Y%m"), w$adm), function(x) "W5" %in% x$admitted, logical(1)))),
  list(tag = "lookahead", old = '.dead <- avail[MOD_END[avail] < excl_date]', new = '.dead <- avail[MOD_END[avail] < hold_end]',
       chk = function(w) w$r$status != 0L || is.null(w$adm) || !("W5" %in% (w$adm[[format(DEAD_END, "%Y%m")]]$admitted %||% character(0)))),
  list(tag = "norenorm", old = '  RENORM <- .renorm_midmonth(Wdt, Rdt, all_used_mods, "앙상블")', new = '  RENORM <- list(W = Wdt, events = list())',
       chk = function(w) w$r$status != 0L),
  list(tag = "renormdeath", old = 'k <- findInterval(as.integer(d), .KR_CAL_I) + 1L; if (k <= length(.KR_CAL_I))', new = 'k <- findInterval(as.integer(d), .KR_CAL_I); if (k <= length(.KR_CAL_I))',
       chk = function(w) w$r$status != 0L || !any(vapply(w$j$dead_modules$renorm_events %||% list(), function(e) identical(e$date, as.character(min(WD[WD > DEAD_END]))), logical(1)))),
  list(tag = "monthly", old = 'GRADE_FREQ <- if (isTRUE(FIX$daily_grade)) "daily" else "monthly"', new = 'GRADE_FREQ <- "monthly"',
       chk = function(w) w$r$status != 0L || !identical(w$j$grade_frequency, "daily") || !all(as.data.table(w$bt$period_returns)$frequency == "daily")),
  list(tag = "nofill", old = 'N_PORT_DAYS_NO_BENCH <- sum(is.na(bm_eval$bm)); bm_eval[is.na(bm), bm := 0]', new = 'N_PORT_DAYS_NO_BENCH <- 0L; bm_eval <- bm_eval[!is.na(bm)]',
       chk = function(w) w$r$status != 0L || !isTRUE(w$j$eval_window$n_period_returns == w$j$eval_window$n_bench_merged)),
  list(tag = "noevalend", old = 'EVAL_END <- if (isTRUE(FIX$single_window)) min(RM_END_RAW, max(bmref$Date)) else RM_END_RAW', new = 'EVAL_END <- RM_END_RAW',
       chk = function(w) w$r$status != 0L || as.Date(w$j$eval_window$end) > BM_END),
  list(tag = "regdefault", old = 'FR_REGISTER <- identical(Sys.getenv("FR_REGISTER", "0"), "1")', new = 'FR_REGISTER <- !identical(Sys.getenv("FR_REGISTER", "1"), "0")',
       chk = function(w) file.exists(file.path(PW, "06_Registry/factor_rotation_registry.json"))))
for (mu in muts) {
  fm <- mutate_file(WN, mu$old, mu$new, mu$tag)
  if (!is.na(fm) && !is.null(mu$post)) { fm2 <- mutate_file(fm, mu$post$old, mu$post$new, paste0(mu$tag, "2")); fm <- fm2 }
  if (is.na(fm)) { ok(FALSE, sprintf("C %s 돌연변이 대상 줄 부재", mu$tag)); next }
  clean_out(); wm <- wf_run(fm, paste0("FRM", mu$tag))
  ok(isTRUE(mu$chk(wm)), sprintf("C %s ★red (status %d)", mu$tag, wm$r$status))
}

cat("\n── E. 정본 벤치 · 격자 감사 HARD (v4r2 · 감사 2026-10-08 I7) ──\n")
## 막는 결함: 벤치를 '가장 긴 bm_xts' 모듈에서 가져와 그 모듈의 날짜 라벨(실측 STR_943 = 정본 대비 +1일)을 들였고,
##   레거시 QEPM 7개가 하루 밀린 채 풀에 섞여도 GRID_LAG 는 기록만 했다.
REG_FILE <- file.path(PW, "06_Registry/factor_rotation_registry.json")
## E1 양성 대조(정렬 픽스처 = A 실행): 벤치 원천 = 정본 · 등급 판 벤치 = 정본 BM_Ret 을 **같은 날짜**에 놓은 값(손 유도 · 결측일 0)
if (!is.null(A$j) && !is.null(A$bt)) {
  br <- as.data.table(A$bt$benchmark_returns)[, .(date = as.Date(date), b = as.numeric(benchmark_ret))]
  exp_b <- ifelse(br$date %in% BMD, BMR[match(br$date, WD)], 0)
  ok(identical(A$j$eval_window$bench_source, "canonical:.cache/benchmark.parquet") && isTRUE(A$j$grid_audit$enforced) &&
       nrow(br) > 500L && isTRUE(max(abs(br$b - exp_b)) < 1e-12),
     sprintf("E1 벤치 = 정본 BM_Ret 같은 날짜(손 유도 %d일 · 최대 차 %.2g) · grid_audit.enforced", nrow(br), max(abs(br$b - exp_b))))
} else ok(FALSE, "E1 A 실행 산출 부재")
## 레거시 지문 주입: 라벨을 하루 당긴다(라벨 d 에 d+1 의 수익·벤치 = 정본 대비 시차 +1)
shift_mod <- function(sid, L = -1L) { f <- file.path(PW, "04_Research/strategies", sid, "sim_result.rds"); z <- readRDS(f)
  z$DAILY_NAV_DT <- as.data.table(z$DAILY_NAV_DT)[, Date := Date + L]
  z$bm_xts <- xts(as.numeric(z$bm_xts[, 1]), order.by = as.Date(index(z$bm_xts)) + L); saveRDS(z, f) }
write_mods_bm(); shift_mod("W3"); clean_out()
E2 <- wf_run(WN, "FRV4G")
ok(E2$r$status != 0L && any(grepl("[FR bench ★격자]", E2$r$out, fixed = TRUE)) && any(grepl("W3(+1일)", E2$r$out, fixed = TRUE)) &&
     !file.exists(REG_FILE) && is.null(E2$j),
   sprintf("E2 ★위반 주입: +1일 밀린 모듈(W3) → 중단(fail-closed) · 모듈·시차 명시 · 산출·등재 없음 (status %d)", E2$r$status))
write_mods_bm(); local({ f <- file.path(PW, "04_Research/strategies/W2/sim_result.rds"); z <- readRDS(f); z$bm_xts <- NULL; saveRDS(z, f) }); clean_out()
E3 <- wf_run(WN, "FRV4G0")
ok(E3$r$status != 0L && any(grepl("W2(NA)", E3$r$out, fixed = TRUE)),
   sprintf("E3 bm_xts 없는 모듈(시차 판독 불가 = NA) → 중단 — 확인 못 한 정렬은 정렬이 아니다 (status %d)", E3$r$status))
write_mods_bm(); shift_mod("W3"); clean_out()
E4 <- wf_run(WN, "FRV4GB", c(FR_V4_ABLATE = "canonical_bench"))
ok(E4$r$status == 0L && grepl("v4ablate-B", E4$id %||% "") && "W3" %in% unlist(E4$j$grid_audit$misaligned_used) &&
     identical(E4$j$grid_audit$enforced, FALSE) && !file.exists(REG_FILE),
   sprintf("E4 분해 대조(canonical_bench 끔) = 구판 재현: 완주 · 어긋난 W3 기록만 · _v4ablate-B · 등재 없음 (status %d)", E4$r$status))
write_mods_bm(); clean_out()
E5 <- wf_run(WN, "FRV4AB", c(FR_V4_ABLATE = "canonical_bench"))
ok(E5$r$status == 0L && !is.null(A$j) && identical(E5$j$grade, A$j$grade) &&
     isTRUE(all.equal(E5$j$essence$portfolio_alpha_t_nw_lag3, A$j$essence$portfolio_alpha_t_nw_lag3)) &&
     isTRUE(all.equal(E5$j$essence$calmar, A$j$essence$calmar)),
   "E5 양성 대조: 정렬 픽스처(W1 bm_xts = 정본 값)에선 구판 벤치와 등급·PORT_t·Calmar 동일 — 수리는 어긋남이 있을 때만 결과를 바꾼다")
fm <- mutate_file(WN, "  if (length(.gl_bad))\n", "  if (FALSE)\n", "nogridstop")
if (is.na(fm)) ok(FALSE, "E6 돌연변이 대상 줄 부재") else {
  write_mods_bm(); shift_mod("W3"); clean_out()
  wm <- wf_run(fm, "FRMgrid")
  ok(wm$r$status == 0L && !is.null(wm$j), sprintf("E6 ★돌연변이 red(격자 중단 줄 삭제): 밀린 W3 를 섞은 채 완주 — 중단은 그 줄이 낸다 (status %d)", wm$r$status))
}
fm <- mutate_file(WN, "if (isTRUE(FIX$canonical_bench) && isTRUE(FIX$daily_grade) && n_moved > 0L)", "if (FALSE)", "nobenchgrid")
if (is.na(fm)) ok(FALSE, "E7 돌연변이 대상 줄 부재") else {
  ## 정본 벤치에 비거래일(토요일) 관측 1개를 끼운다 — 한국 거래일 격자에 제 날짜로 못 놓인다(격자 불일치)
  SAT1 <- as.Date("2017-06-10")
  write_parquet(data.table(Date = sort(c(BMD, SAT1)), BM_Ret = c(BMR[match(BMD, WD)], 0.0123)[order(c(BMD, SAT1))]), file.path(PW, ".cache/benchmark.parquet"))
  write_mods_bm(); clean_out()
  E7 <- wf_run(WN, "FRV4S")
  wm7 <- wf_run(fm, "FRMbgrid")
  ok(E7$r$status != 0L && any(grepl("제 날짜로 놓이지 않는다", E7$r$out, fixed = TRUE)) && wm7$r$status == 0L,
     sprintf("E7 정본 벤치 관측이 한국 거래일 격자 밖(토요일) → 중단 · 돌연변이(검사 삭제) red = 완주 (status %d / %d)", E7$r$status, wm7$r$status))
  write_parquet(data.table(Date = BMD, BM_Ret = BMR[match(BMD, WD)]), file.path(PW, ".cache/benchmark.parquet"))
}

cat("\n── D. 운영 무쓰기 ──\n")
ok(identical(unname(tools::md5sum(OPS_FILES)), unname(MD5_BEFORE)), "D1 운영 레지스트리·풀 md5 불변")
FR_OUT_AFTER <- if (dir.exists(FR_OUT_OPS)) sort(list.files(FR_OUT_OPS, recursive = TRUE)) else character(0)
ok(identical(FR_OUT_AFTER, FR_OUT_BEFORE), "D2 운영 FR output 파일 목록 불변")
finish()
