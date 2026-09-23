#==============================================================================
# test_rf_base_cache_key.R — 강화 기저 신호 캐시 **키** 양방향 검사 (2026-09-23 신설)
#
# 사고(적대 검증 실측 2026-09-23):
#   rf_cell_engine.R 의 기저 캐시 키 = paste(엔진 md5, RAWDATA mtime, nrow, start) 를 영숫자만 남겨
#   substr(1, 40) 으로 잘랐다. md5 32자 + mtime **날짜 8자리**만 남았다(base_5d8a…20260923.rds).
#   같은 날 RAWDATA 수리(Size 18:49 · BM_Ret 20:52)·factor DB 재빌드(18:53/18:56/20:58) 뒤에도
#   교정 전 신호를 재사용했다(당일 셀 로그 38건 적중).
#
# 무엇을 재는가 (대상 = 02_Infrastructure/reinforcement/rf_base_cache.R + rf_cell_engine.R 의 소비):
#   K  단위 — 키 함수. 양성 대조(무변경 = 같은 키) + 변경 6종(같은 날 mtime · size · build_hash ·
#      월 파일 재작성 · benchmark · 메모리 패널) = 다른 키 + 판독 실패 = 캐시 금지
#   M  돌연변이 — 같은 시나리오를 **구판 키 함수**(절단 40자)와 build_hash 생략 변형에 걸면 red
#   E  엔진 경유 — 실제 rf_cell_engine.R 을 격리 루트에서 돌려 적중/미스를 기저 엔진 실행 횟수로 잰다
#   L  구판 엔진(git blob) — 같은 격리 절차에서 같은 날 mtime 변경을 **적중**시키는지(결함 재현 = red)
#
# 부작용 없음: 격리 루트·픽스처·스펙·캐시 전부 tempdir. QM_ROOT 는 엔진 실행 동안만 바꾸고 복원한다.
#   운영 .cache·원장·로그 무접촉.
# 실행: Rscript 08_Tests/reinforcement/test_rf_base_cache_key.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
HELPER <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_base_cache.R")
LEGACY_BLOB <- "2aebd239c79033fb526c72309dccbb629a43b893"   # 7fdc6f682:02_Infrastructure/reinforcement/rf_cell_engine.R (수리 전)

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
ok   <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng   <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
skip <- function(axis, reason, missing = "") {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  writeLines(paste("  SKIP ", axis, "—", reason))
}
emit <- function() {
  cat(sprintf('{"test":"rf_base_cache_key","pass":%d,"fail":%d,"skipped":%d,"total":%d,"skips":%s}\n',
              PASS, FAIL, length(SKIPS), PASS + FAIL,
              jsonlite::toJSON(SKIPS, auto_unbox = TRUE)))
}

if (!file.exists(HELPER) || !file.exists(ENGINE)) {
  ng("전제", paste("대상 파일 부재:", HELPER, ENGINE)); emit(); quit(status = 1L)
}
source(HELPER)

TMP <- file.path(tempdir(), sprintf("rfbck_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)

# 같은 날 두 시각 — 구 키는 날짜 8자리만 남으므로 이 둘을 구분하지 못한다.
T_MORNING <- as.POSIXct("2026-09-23 15:05:00", tz = "Asia/Seoul")
T_EVENING <- as.POSIXct("2026-09-23 20:52:38", tz = "Asia/Seoul")

# 격리 루트 — 엔진이 .RF_ROOT 에서 읽는 도장 파일 + source 하는 보조 파일만.
make_root <- function(tag) {
  r <- file.path(TMP, tag)
  dir.create(file.path(r, ".cache", "factor_db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure", "reinforcement"), recursive = TRUE, showWarnings = FALSE)
  for (f in c("rf_rebalance.R", "rf_sleeve.R", "rf_base_cache.R"))
    file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f),
              file.path(r, "02_Infrastructure/reinforcement", f), overwrite = TRUE)
  writeBin(as.raw(rep(1L, 1000L)), file.path(r, ".cache", "rawdata.parquet"))
  writeBin(as.raw(rep(2L, 300L)),  file.path(r, ".cache", "benchmark.parquet"))
  writeLines("20260923185300_aaaaaaa", file.path(r, ".cache", "factor_db", "build_hash.txt"))
  writeBin(as.raw(rep(3L, 500L)), file.path(r, ".cache", "factor_db", "factor_db_202608.parquet"))
  writeBin(as.raw(rep(4L, 500L)), file.path(r, ".cache", "factor_db", "factor_db_202609.parquet"))
  Sys.setFileTime(file.path(r, ".cache", "rawdata.parquet"), T_MORNING)
  Sys.setFileTime(file.path(r, ".cache", "benchmark.parquet"), T_MORNING)
  for (f in list.files(file.path(r, ".cache", "factor_db"), full.names = TRUE)) Sys.setFileTime(f, T_MORNING)
  r
}
rawp  <- function(r) file.path(r, ".cache", "rawdata.parquet")
benchp <- function(r) file.path(r, ".cache", "benchmark.parquet")
fdbd  <- function(r) file.path(r, ".cache", "factor_db")

# 픽스처 — 종목 45(지수 멤버 40 > n_max 25) · 평일 2003-06~2008-12
make_fixture <- function() {
  set.seed(20260923L)
  d <- seq(as.Date("2003-06-02"), as.Date("2008-12-31"), by = "day")
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  x <- CJ(Ticker = sprintf("T%03d", 1:45), Date = d)
  setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0003, 0.012)]
  x[, Close := 10000 * cumprod(1 + .r), by = Ticker][, .r := NULL]
  x[, Vol := 200000]
  x[, Size := Close * 1e6]
  x[, K200 := as.integer(sub("T", "", Ticker, fixed = TRUE)) <= 40L]
  x[, KQ150 := FALSE]
  x[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker, fixed = TRUE)) %% 5L) + 1L)]
  x[]
}
FIX <- make_fixture()
FIX_SIZE_FIX <- copy(FIX)[Date >= as.Date("2008-12-10"), Size := NA_real_]   # Size 수리 전/후 판(행수 동일)
BMF <- FIX[, .(BM_Ret = mean(Close / shift(Close) - 1, na.rm = TRUE)), by = Date]

# 기저 엔진 스텁 — 실행될 때마다 카운터 +1. RF_BCK_TOUCH_BH 가 있으면 실행 **중** build_hash 를 바꾼다(E8).
STUB <- file.path(TMP, "stub_base_engine.R")
writeLines(c(
  "cnt <- Sys.getenv('RF_BCK_COUNTER')",
  "n <- if (file.exists(cnt)) as.integer(readLines(cnt, warn = FALSE)) else 0L",
  "writeLines(as.character(n + 1L), cnt)",
  "bh <- Sys.getenv('RF_BCK_TOUCH_BH')",
  "if (nzchar(bh)) writeLines(paste0('during_run_', n + 1L), bh)",
  "x <- RAWDATA[, .(Date, Ticker, Close, Size)]",
  "x[, Score := data.table::shift(Close, 21L) / data.table::shift(Close, 252L) - 1 + 1e-12 * data.table::fcoalesce(Size, 0), by = Ticker]",
  "FACTORS <- x[is.finite(Score), .(Date, Ticker, Score)]"), STUB)

# ════════════════════════════════════════════════════════════════════════════
# K / M — 키 함수 시나리오. keyfun(root, DT) → 캐시 파일 경로를 가르는 문자열.
# ════════════════════════════════════════════════════════════════════════════
START <- as.Date("2005-01-01")
new_keyfun <- function(r, DT, eng = STUB) {
  k <- rf_base_cache_key(unname(tools::md5sum(eng)), rawp(r), benchp(r), fdbd(r),
                         rf_base_data_fingerprint(DT), nrow(DT), START)
  paste(k$file, k$key, k$cacheable)
}
# 구판(7fdc6f682 rf_cell_engine.R:80-84) 을 그대로 옮긴 것 — 돌연변이 기준
legacy_keyfun <- function(r, DT, eng = STUB) {
  k <- paste(tryCatch(unname(tools::md5sum(eng)), error = function(e) "nohash"),
             tryCatch(as.character(file.info(rawp(r))$mtime), error = function(e) "nomtime"),
             nrow(DT), as.character(START), sep = "_")
  k <- gsub("[^A-Za-z0-9]", "", k)
  paste0("base_", substr(k, 1, 40), ".rds")
}
# 돌연변이 2 — 신판에서 factor DB 도장만 뺀 변형(엔진이 factor DB 를 안 읽는다고 가정한 판)
nofdb_keyfun <- function(r, DT, eng = STUB) {
  k <- rf_base_cache_key(unname(tools::md5sum(eng)), rawp(r), benchp(r), file.path(r, "__nope__"),
                         rf_base_data_fingerprint(DT), nrow(DT), START)
  paste(k$file, k$key)
}

# 시나리오 — 각 항목 TRUE = 기대대로(무변경이면 같은 키, 변경이면 다른 키)
scenarios <- function(keyfun, tag) {
  r <- make_root(tag); DT <- copy(FIX)
  res <- list()
  k0 <- keyfun(r, DT)
  res$K1_same <- identical(keyfun(r, copy(FIX)), k0)                               # 무변경 → 같은 키
  Sys.setFileTime(rawp(r), T_EVENING)
  res$K2_mtime_same_day <- !identical(keyfun(r, DT), k0)                           # 같은 날 저녁 재작성
  k2 <- keyfun(r, DT)
  writeBin(as.raw(rep(1L, 1001L)), rawp(r)); Sys.setFileTime(rawp(r), T_EVENING)
  res$K3_size <- !identical(keyfun(r, DT), k2)                                     # mtime 같고 size 다름
  k3 <- keyfun(r, DT)
  bh <- file.path(fdbd(r), "build_hash.txt"); bh_mt <- file.info(bh)$mtime
  writeLines("20260923205841_9be5e291a", bh); Sys.setFileTime(bh, bh_mt)
  res$K4_build_hash <- !identical(keyfun(r, DT), k3)                               # factor DB 재빌드
  k4 <- keyfun(r, DT)
  writeBin(as.raw(rep(9L, 520L)), file.path(fdbd(r), "factor_db_202609.parquet"))
  res$K5_month_file <- !identical(keyfun(r, DT), k4)                               # build_hash 불변 월 파일 재작성
  k5 <- keyfun(r, DT)
  writeBin(as.raw(rep(2L, 310L)), benchp(r))
  res$K6_bench <- !identical(keyfun(r, DT), k5)                                    # benchmark 교체
  k6 <- keyfun(r, DT)
  res$K7_memory_panel <- !identical(keyfun(r, copy(FIX_SIZE_FIX)), k6)             # 파일 불변 · 메모리만 수리판
  writeLines("x", file.path(r, ".cache", "unrelated.txt"))
  writeLines("{}", file.path(fdbd(r), "emission_report_202609.json"))
  res$K8_unrelated_same <- identical(keyfun(r, DT), k6)                            # 무관 파일 → 같은 키
  unlist(res)
}

writeLines("=== K. 신판 키 — 양성 대조 + 변경 6종 ===")
SN <- scenarios(new_keyfun, "K_new")
for (nm in names(SN)) if (isTRUE(SN[[nm]])) ok(paste("신판", nm)) else ng(paste("신판", nm), "기대와 다른 키 판정")

# K9 판독 실패 — 엔진 md5 NA · build_hash 판독 불가 → 캐시 금지(구판은 'nohash' 상수 키로 영원히 적중)
r9 <- make_root("K9")
k9 <- rf_base_cache_key(NA_character_, rawp(r9), benchp(r9), fdbd(r9), rf_base_data_fingerprint(FIX), nrow(FIX), START)
if (!isTRUE(k9$cacheable)) ok("K9a 엔진 md5 판독 실패 → cacheable=FALSE") else ng("K9a", "상수 키로 캐시 허용")
k9b <- rf_base_cache_key(unname(tools::md5sum(STUB)), rawp(r9), benchp(r9), fdbd(r9), "", nrow(FIX), START)
if (!isTRUE(k9b$cacheable)) ok("K9b 메모리 지문 부재 → cacheable=FALSE") else ng("K9b", "지문 없이 캐시 허용")
k9c <- rf_base_cache_key(unname(tools::md5sum(STUB)), rawp(r9), benchp(r9), fdbd(r9),
                         rf_base_data_fingerprint(FIX), nrow(FIX), START)
if (isTRUE(k9c$cacheable) && grepl("^base_v2_[0-9a-f]{12}_[0-9a-f]{32}\\.rds$", k9c$file))
  ok(paste("K9c 정상 판독 → cacheable · 파일명", k9c$file)) else ng("K9c", paste(k9c$cacheable, k9c$file))
# K10 키 전문 대조 — 파일명이 같아도 속성 키가 다르면 적중 금지
f10 <- file.path(TMP, "k10.rds"); o10 <- data.table(a = 1); setattr(o10, "rf_base_cache_key", "other"); saveRDS(o10, f10)
l10 <- rf_base_cache_load(f10, k9c$key)
if (is.null(l10$obj) && identical(l10$why, "key_mismatch")) ok("K10 속성 키 불일치 → 미스(key_mismatch)") else
  ng("K10", paste("why =", l10$why))
saveRDS(data.table(a = 1), f10)
l10b <- rf_base_cache_load(f10, k9c$key)
if (is.null(l10b$obj)) ok("K10b 속성 키 없는 구판형 파일 → 미스") else ng("K10b", "구판형 파일 적중")

# K11~K13 보조 데이터원(⑦, 2026-09-24) — 기저 엔진이 RAWDATA 밖에서 직접 읽는 패널이 바뀌면 미스,
#   목록 밖 파일이 바뀌면 적중 유지. M-aux = ⑦ 을 뺀 판(도장 상수화)에서 K11·K12 가 red 여야 한다.
aux_scen <- function(tag) {
  r <- make_root(tag); DT <- copy(FIX); res <- list()
  dir.create(file.path(r, ".cache", "consensus"), showWarnings = FALSE)
  writeBin(as.raw(rep(5L, 200L)), file.path(r, ".cache", "consensus", "eps_1y.parquet"))
  writeBin(as.raw(rep(6L, 200L)), file.path(r, ".cache", "fundamental_merged.parquet"))
  k0 <- new_keyfun(r, DT)
  writeBin(as.raw(rep(5L, 260L)), file.path(r, ".cache", "consensus", "eps_1y.parquet"))
  res$K11_consensus <- !identical(new_keyfun(r, DT), k0); k1 <- new_keyfun(r, DT)
  writeBin(as.raw(rep(6L, 230L)), file.path(r, ".cache", "fundamental_merged.parquet"))
  res$K12_fundamental <- !identical(new_keyfun(r, DT), k1); k2 <- new_keyfun(r, DT)
  writeBin(as.raw(rep(7L, 50L)), file.path(r, ".cache", "P3_daily.parquet"))
  res$K13_unlisted_same <- identical(new_keyfun(r, DT), k2)
  unlist(res)
}
SA <- aux_scen("K_aux")
for (nm in names(SA)) if (isTRUE(SA[[nm]])) ok(paste("신판", nm)) else ng(paste("신판", nm), "기대와 다른 키 판정")
.aux_orig <- rf_base_cache_aux_stamp
rf_base_cache_aux_stamp <- function(cache_dir) "absent"          # 돌연변이: ⑦ 제거
SAm <- aux_scen("M_aux")
rf_base_cache_aux_stamp <- .aux_orig
if (!isTRUE(SAm[["K11_consensus"]]) && !isTRUE(SAm[["K12_fundamental"]]))
  ok("M-aux ⑦ 을 뺀 판에서 K11·K12 red — 검사가 보조 데이터원 누락을 잡는다") else
  ng("M-aux", "⑦ 없이도 K11/K12 초록 — 검사가 누락을 못 잡는다")

writeLines("=== M. 돌연변이 — 같은 시나리오를 구판·생략판 키에 걸면 red ===")
SL <- scenarios(legacy_keyfun, "M_legacy")
if (isTRUE(SL[["K1_same"]])) ok("M0 구판도 무변경엔 같은 키(대조가 퇴화 입력이 아님)") else ng("M0", "구판 K1 불일치 — 시나리오 자체 결함")
for (nm in c("K2_mtime_same_day", "K4_build_hash", "K7_memory_panel"))
  if (!isTRUE(SL[[nm]])) ok(paste("M1 구판 키", nm, "red — 검사가 결함을 잡는다")) else
    ng(paste("M1 구판 키", nm), "구판에서도 초록 — 검사가 결함을 못 잡는다")
SF <- scenarios(nofdb_keyfun, "M_nofdb")
for (nm in c("K4_build_hash", "K5_month_file"))
  if (!isTRUE(SF[[nm]])) ok(paste("M2 factor DB 생략판", nm, "red")) else
    ng(paste("M2 factor DB 생략판", nm), "생략판에서도 초록")
if (isTRUE(SF[["K2_mtime_same_day"]])) ok("M2 생략판은 RAWDATA 축은 여전히 초록(돌연변이가 한 축만 죽였다)") else
  ng("M2 대조", "생략판 K2 도 red — 돌연변이 격리 실패")

# ════════════════════════════════════════════════════════════════════════════
# E / L — 엔진 경유. 격리 루트 + 카운터로 적중/미스를 잰다.
# ════════════════════════════════════════════════════════════════════════════
run_engine <- function(engine, r, fixture, counter, touch_bh = "") {
  spec <- list(code = "BCK", label = "base-cache-key", block = "T",
               fixed_axes = list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
                                 start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8),
               base_signal = list(kind = "engine", path = STUB),
               factor2 = list(kind = "none"),
               weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
  sp <- file.path(TMP, sprintf("spec_%s.json", basename(r)))
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  old <- Sys.getenv(c("QM_ROOT", "RF_CELL_SPEC", "RF_BCK_COUNTER", "RF_BCK_TOUCH_BH"), unset = NA)
  on.exit({
    for (nm in names(old)) if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, setNames(list(old[[nm]]), nm))
  }, add = TRUE)
  Sys.setenv(QM_ROOT = r, RF_CELL_SPEC = sp, RF_BCK_COUNTER = counter)
  if (nzchar(touch_bh)) Sys.setenv(RF_BCK_TOUCH_BH = touch_bh) else Sys.unsetenv("RF_BCK_TOUCH_BH")
  env <- new.env()
  assign("RAWDATA", copy(fixture), envir = env); assign("BM_DT", BMF, envir = env)
  err <- NULL
  log <- capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))), type = "output")
  n <- if (file.exists(counter)) as.integer(readLines(counter, warn = FALSE)) else 0L
  list(err = err, log = log, runs = n,
       hit = any(grepl("기저 캐시 적중", log, fixed = TRUE)),
       miss = any(grepl("기저 캐시 미스", log, fixed = TRUE)),
       skipped_save = any(grepl("기저 캐시 저장 생략", log, fixed = TRUE)),
       out = if (exists("FACTORS", envir = env, inherits = FALSE)) get("FACTORS", envir = env) else NULL)
}

writeLines("=== E. 엔진 경유 — 실제 rf_cell_engine.R · 격리 루트 ===")
RE <- make_root("E_new"); CNT <- file.path(TMP, "cnt_E"); unlink(CNT)
e1 <- run_engine(ENGINE, RE, FIX, CNT)
if (is.null(e1$err) && e1$miss && e1$runs == 1L) ok("E1 첫 실행 = 미스(기저 엔진 1회)") else
  ng("E1", paste(e1$err %||% "", "runs", e1$runs, paste(tail(e1$log, 3), collapse = " | ")))
cf <- list.files(file.path(RE, ".cache", "rf_base_signal"), full.names = TRUE)
if (length(cf) == 1L && grepl("^base_v2_", basename(cf)) &&
    grepl("^rf_base_cache_v2\\|", attr(readRDS(cf), "rf_base_cache_key") %||% ""))
  ok(paste("E1b 캐시 1개 생성 · 속성에 키 전문 —", basename(cf))) else ng("E1b", paste(basename(cf), collapse = ","))
e2 <- run_engine(ENGINE, RE, FIX, CNT)
if (is.null(e2$err) && e2$hit && e2$runs == 1L) ok("E2 무변경 재실행 = 적중(기저 엔진 미실행) — 양성 대조") else
  ng("E2", paste(e2$err %||% "", "hit", e2$hit, "runs", e2$runs))
if (!is.null(e1$out) && !is.null(e2$out) && isTRUE(all.equal(e1$out, e2$out)))
  ok("E7 적중 산출 == 미스 산출(값 동일)") else ng("E7", "적중 산출이 미스 산출과 다르다")
Sys.setFileTime(rawp(RE), T_EVENING)
e3 <- run_engine(ENGINE, RE, FIX, CNT)
if (is.null(e3$err) && e3$miss && !e3$hit && e3$runs == 2L) ok("E3 같은 날 RAWDATA 재작성(15:05→20:52) = 미스") else
  ng("E3", paste(e3$err %||% "", "hit", e3$hit, "runs", e3$runs))
e4 <- run_engine(ENGINE, RE, FIX, CNT)
if (is.null(e4$err) && e4$hit && e4$runs == 2L) ok("E4 그 판본 재실행 = 적중") else ng("E4", paste("hit", e4$hit, "runs", e4$runs))
bhE <- file.path(fdbd(RE), "build_hash.txt"); writeLines("20260923205841_9be5e291a", bhE)
e5 <- run_engine(ENGINE, RE, FIX, CNT)
if (is.null(e5$err) && e5$miss && !e5$hit && e5$runs == 3L) ok("E5 factor DB build_hash 변경 = 미스") else
  ng("E5", paste(e5$err %||% "", "hit", e5$hit, "runs", e5$runs))
e6 <- run_engine(ENGINE, RE, FIX_SIZE_FIX, CNT)
if (is.null(e6$err) && e6$miss && !e6$hit && e6$runs == 4L) ok("E6 파일 불변 · 메모리 패널만 수리판 = 미스(적재 후 교체 경합)") else
  ng("E6", paste(e6$err %||% "", "hit", e6$hit, "runs", e6$runs))
# E8 실행 중 도장 변경 → 저장 생략, 다음 실행은 (새 도장 기준) 미스여야 한다
RE8 <- make_root("E8"); CNT8 <- file.path(TMP, "cnt_E8"); unlink(CNT8)
e8 <- run_engine(ENGINE, RE8, FIX, CNT8, touch_bh = file.path(fdbd(RE8), "build_hash.txt"))
n8 <- length(list.files(file.path(RE8, ".cache", "rf_base_signal"), pattern = "\\.rds$"))
if (is.null(e8$err) && e8$skipped_save && n8 == 0L) ok("E8 실행 중 build_hash 변경 → 저장 생략(혼합 판본 미저장)") else
  ng("E8", paste(e8$err %||% "", "skipped", e8$skipped_save, "rds", n8))
tmpleft <- list.files(file.path(RE, ".cache", "rf_base_signal"), pattern = "\\.tmp")
if (!length(tmpleft)) ok("E9 tmp 잔재 0(원자 교체)") else ng("E9", paste(tmpleft, collapse = ","))

writeLines("=== L. 구판 엔진(git blob) — 같은 절차에서 결함 재현 = red ===")
LEG <- file.path(TMP, "rf_cell_engine_legacy.R")
gs <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(ROOT), "cat-file", "-p", LEGACY_BLOB),
                                        stdout = LEG, stderr = FALSE)), error = function(e) 1L)
if (!identical(as.integer(gs), 0L) || !file.exists(LEG) || file.info(LEG)$size < 1000) {
  skip("L 구판 엔진 재현", "git blob 을 꺼낼 수 없다(저장소 밖 실행 또는 gc)", LEGACY_BLOB)
} else {
  RL <- make_root("L_legacy"); CNTL <- file.path(TMP, "cnt_L"); unlink(CNTL)
  l1 <- run_engine(LEG, RL, FIX, CNTL)
  if (!is.null(l1$err) || !l1$miss) {
    skip("L 구판 엔진 재현", paste("구판 엔진이 현 픽스처에서 기저 캐시 단계까지 못 간다:", l1$err %||% "미스 로그 없음"), LEGACY_BLOB)
  } else {
    Sys.setFileTime(rawp(RL), T_EVENING)
    l2 <- run_engine(LEG, RL, FIX, CNTL)
    if (l2$hit && l2$runs == 1L) ok("L1 구판 엔진은 같은 날 RAWDATA 재작성에도 적중 — E3 단정이 구판에서 red(결함 재현)") else
      ng("L1", paste("구판이 미스 — 돌연변이 기준 무효(hit", l2$hit, "runs", l2$runs, ")"))
    writeLines("20260923205841_9be5e291a", file.path(fdbd(RL), "build_hash.txt"))
    l3 <- run_engine(LEG, RL, FIX, CNTL)
    if (l3$hit && l3$runs == 1L) ok("L2 구판 엔진은 build_hash 변경에도 적중 — E5 단정이 구판에서 red") else
      ng("L2", paste("hit", l3$hit, "runs", l3$runs))
  }
}

# 정적 — 엔진이 실제로 신판 키를 소비하는가(구판 절단식 부활 방지)
writeLines("=== S. 소비 배선 ===")
esrc <- paste(sub("#.*$", "", readLines(ENGINE, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
if (grepl("rf_base_cache_key(", esrc, fixed = TRUE) && grepl("rf_base_cache_load(", esrc, fixed = TRUE) &&
    grepl("rf_base_cache_save(", esrc, fixed = TRUE)) ok("S1 엔진이 rf_base_cache_key/load/save 를 호출") else
  ng("S1", "엔진이 신판 키 함수를 부르지 않는다")
if (!grepl("substr\\(\\.key, *1, *40\\)", esrc)) ok("S2 구판 절단 키(substr(.key,1,40)) 부재") else ng("S2", "구판 절단 키 잔존")

unlink(TMP, recursive = TRUE)
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
