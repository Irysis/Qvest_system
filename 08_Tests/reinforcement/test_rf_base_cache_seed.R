#!/usr/bin/env Rscript
#==============================================================================
# test_rf_base_cache_seed.R — 기저 캐시 시드(2026-10-05) 양방향 검사
#   정본 = 02_Infrastructure/reinforcement/rf_base_cache.R ('기저 캐시 시드' 절) · 배선 = run_paper_replication.R(QVEST_RP_SEED_BASE_CACHE)
#   · 켜는 자 = ops/rf_replication_verify.R.
#
#   S1  순열 지문 = 정렬 사본 지문(비트 동일 · 부동소수 합 순서 포함)
#   S2  음성 대조 — 순열 없이 재면 다르다(S1 이 공허하지 않다)
#   S3  ord = NULL 은 구판 알고리즘과 비트 동일(기존 셀 키 불변)
#   S4  시드 키 = 셀 키(셀처럼 정렬 + '.' 파생 열을 더한 뒤 잰 키)
#   S5  시드 저장 → 셀 키로 적재 적중 · 값·속성 · 호출자 FACTORS 불변
#   S6  PORTFOLIO 만 있으면 Weight · 둘 다 있으면 FACTORS 우선(셀 .load_one 규약)
#   S7  실행 중 도장 변경 → 저장 생략(혼합 판본 금지)
#   S8  음성 대조 — start 가 다르면 셀 키로 적중하지 않는다
#   S9  Date 형이 아니면 시드 키를 만들지 않는다(틀린 키 대신 건너뜀)
#   S10 배선 — 러너는 환경변수=1 ∧ data_cutoff NULL 일 때만 · 검증기만 켠다 · 셀 워커·병렬 러너는 켜지 않는다
#   S11 (선택 · RF_SEED_REALDATA=1) 실데이터 RAWDATA 로 시드 키 = 셀 키
# 운영 상태를 빌리지 않는다(임시 루트) — S11 만 운영 .cache 를 **읽기만** 한다.
#==============================================================================
suppressMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- Sys.getenv("RF_BASE_CACHE_SRC", file.path(ROOT, "02_Infrastructure/reinforcement/rf_base_cache.R"))
RPR  <- Sys.getenv("RF_RPR_SRC", file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
VER  <- Sys.getenv("RF_VERIFY_SRC", file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"))
source(SRC)
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, info = "") { F <<- F + 1L; cat("  FAIL", m, if (nzchar(info)) paste0(" — ", info) else "", "\n") }
chk <- function(cond, m, info = "") if (isTRUE(cond)) ok(m) else ng(m, info)

# ── 합성 패널: parquet 처럼 (Date, Ticker) 순 · 부동소수 합이 순서에 민감한 값 ─────────────────
set.seed(11)
tk <- sprintf("A%06d", sample(1e5:9e5, 40))
dd <- seq(as.Date("2004-01-01"), by = "day", length.out = 600)
DT <- CJ(Date = dd, Ticker = tk)                                   # Date-major (parquet 순서 흉내)
n <- nrow(DT)
DT[, Close := exp(rnorm(n, 5, 3)) * 10^sample(-6:6, n, TRUE)]      # 큰 동적범위 — 합 순서가 끝자리를 바꾼다
DT[, Vol := sample.int(1e6, n, TRUE)]
DT[, Flag := sample(c(TRUE, FALSE, NA), n, TRUE)]
DT[, Name := sample(c("x", "yy", NA, "zzz"), n, TRUE)]
DT[sample.int(n, 50), Close := NA]
setcolorder(DT, c("Ticker", "Date", "Close", "Vol", "Flag", "Name"))
ord_of <- function(D) { o <- data.table(Ticker = D$Ticker, Date = D$Date, .i = seq_len(nrow(D))); setorderv(o, c("Ticker", "Date")); o$.i }

cat("=== S1~S3 지문 ===\n")
S <- copy(DT); setorder(S, Ticker, Date)
fp_sorted <- rf_base_data_fingerprint(S)
fp_ord    <- rf_base_data_fingerprint(DT, ord = ord_of(DT))
chk(identical(fp_ord, fp_sorted), "S1 순열 지문 = 정렬 사본 지문(비트 동일)", substr(fp_ord, 1, 80))
chk(!identical(rf_base_data_fingerprint(DT), fp_sorted), "S2 순열 없이 재면 다르다(음성 대조 — S1 이 공허하지 않다)")
.old_fp <- function(DT) {                                          # 2026-09-23 구판 그대로(비교 기준)
  cols <- names(DT); cols <- cols[!startsWith(cols, ".")]
  n <- nrow(DT); idx <- if (n > 0L) seq.int(1L, n, by = 7L) else integer(0); wv <- as.numeric(seq_along(idx))
  parts <- vapply(cols, function(cn) {
    x <- DT[[cn]]; na <- sum(is.na(x))
    if (is.numeric(x) || is.logical(x) || inherits(x, "Date") || inherits(x, "POSIXt")) {
      v <- as.numeric(unclass(x)); s1 <- sum(v, na.rm = TRUE)
      s2 <- if (length(idx)) sum(v[idx] * wv, na.rm = TRUE) else 0
      sprintf("%s:%d:%.17g:%.17g", cn, na, s1, s2)
    } else {
      xs <- as.character(x)[idx]; nb <- nchar(xs, type = "bytes"); nb[is.na(xs)] <- 0L
      sprintf("%s:%d:%d:%.17g", cn, na, data.table::uniqueN(xs), sum(as.numeric(nb) * wv))
    }
  }, character(1))
  paste(c(sprintf("n=%d", n), parts), collapse = "|")
}
chk(identical(rf_base_data_fingerprint(DT), .old_fp(DT)) && identical(fp_sorted, .old_fp(S)),
    "S3 ord = NULL 은 구판과 비트 동일(기존 셀 키 불변)")

cat("=== S4~S9 키·저장·적재 ===\n")
R0 <- file.path(tempdir(), paste0("seedroot_", Sys.getpid()))
dir.create(file.path(R0, ".cache", "factor_db"), recursive = TRUE, showWarnings = FALSE)
writeLines("rawdata-bytes", file.path(R0, ".cache", "rawdata.parquet"))
writeLines("bench-bytes", file.path(R0, ".cache", "benchmark.parquet"))
writeLines("bh-1", file.path(R0, ".cache", "factor_db", "build_hash.txt"))
writeLines("m", file.path(R0, ".cache", "factor_db", "factor_db_200401.parquet"))
ENG <- file.path(R0, "engine.R"); writeLines("FACTORS <- NULL # test engine", ENG)
cell_key <- function(D, start) {                                   # 셀(rf_cell_engine.R)과 같은 순서로 잰다
  C <- copy(D); setorder(C, Ticker, Date)
  C[, .TV := 1][, .adv20_l1 := 2][, .mom_12_1 := 3]                # '.' 파생 열(지문 제외)
  rf_base_cache_key(unname(tools::md5sum(ENG)), file.path(R0, ".cache", "rawdata.parquet"),
                    file.path(R0, ".cache", "benchmark.parquet"), file.path(R0, ".cache", "factor_db"),
                    data_fp = rf_base_data_fingerprint(C), n_rows = nrow(C), start = start)
}
ck_seed <- rf_base_cache_seed_key(ENG, DT, root = R0, start = "2005-01-01")
ck_cell <- cell_key(DT, as.Date("2005-01-01"))
chk(isTRUE(ck_seed$cacheable) && identical(ck_seed$key, ck_cell$key) && identical(ck_seed$file, ck_cell$file),
    "S4 시드 키 = 셀 키(정렬 + 파생 열 뒤 셀 지문)", paste(substr(ck_seed$key, 1, 60), "|", ck_seed$file))
FX <- DT[, .(Date, Ticker, Score = Close / 7, extra = 1L)]
sv <- rf_base_cache_seed_save(FX, NULL, ck_seed, root = R0, provenance = "test-run")
hit <- rf_base_cache_load(file.path(R0, ".cache", "rf_base_signal", ck_cell$file), ck_cell$key)
b <- hit$obj
chk(identical(sv, "saved") && identical(hit$why, "hit"), "S5a 시드 저장 → 셀 키로 적중", paste(sv, hit$why))
chk(!is.null(b) && identical(names(b), c("Date", "Ticker", ".base_sig")) && isTRUE(all.equal(b$.base_sig, FX$Score)),
    "S5b 셀 .load_one 모양((Date, Ticker, .base_sig) · Score 값)")
chk(identical(attr(b, "rf_base_seeded_from"), "test-run"), "S5c 시드 출처 속성")
chk("Score" %in% names(FX) && !(".base_sig" %in% names(FX)), "S5d 호출자 FACTORS 를 바꾸지 않는다(러너가 뒤에서 Score 를 쓴다)")
PF <- DT[1:30, .(Date, Ticker, Weight = 1 / 30, Leg = "L")]
R1 <- file.path(tempdir(), paste0("seedroot1_", Sys.getpid())); dir.create(R1)
invisible(file.copy(file.path(R0, ".cache"), R1, recursive = TRUE))
ck1 <- rf_base_cache_seed_key(ENG, DT, root = R1, start = "2005-01-01")
s6a <- rf_base_cache_seed_save(NULL, PF, ck1, root = R1)
b6 <- rf_base_cache_load(file.path(R1, ".cache", "rf_base_signal", ck1$file), ck1$key)$obj
chk(identical(s6a, "saved") && isTRUE(all.equal(b6$.base_sig, PF$Weight)), "S6a PORTFOLIO 만 있으면 Weight 를 기저로")
unlink(file.path(R1, ".cache", "rf_base_signal"), recursive = TRUE)
ck1 <- rf_base_cache_seed_key(ENG, DT, root = R1, start = "2005-01-01")
s6b <- rf_base_cache_seed_save(FX, PF, ck1, root = R1)
b6b <- rf_base_cache_load(file.path(R1, ".cache", "rf_base_signal", ck1$file), ck1$key)$obj
chk(identical(s6b, "saved") && nrow(b6b) == nrow(FX), "S6b 둘 다 있으면 FACTORS 우선(셀 규약)")
R2 <- file.path(tempdir(), paste0("seedroot2_", Sys.getpid())); dir.create(R2)
invisible(file.copy(file.path(R0, ".cache"), R2, recursive = TRUE))
ck2 <- rf_base_cache_seed_key(ENG, DT, root = R2, start = "2005-01-01")
Sys.sleep(1.1); writeLines("rawdata-bytes-CHANGED", file.path(R2, ".cache", "rawdata.parquet"))
s7 <- rf_base_cache_seed_save(FX, NULL, ck2, root = R2)
chk(startsWith(s7, "stamp_changed_during_run") && !file.exists(file.path(R2, ".cache", "rf_base_signal", ck2$file)),
    "S7 실행 중 도장 변경 → 저장 생략", s7)
ck8 <- cell_key(DT, as.Date("2005-01-01"))
R3 <- file.path(tempdir(), paste0("seedroot3_", Sys.getpid())); dir.create(R3)
invisible(file.copy(file.path(R0, ".cache"), R3, recursive = TRUE)); unlink(file.path(R3, ".cache", "rf_base_signal"), recursive = TRUE)
ck8s <- rf_base_cache_seed_key(ENG, DT, root = R3, start = "2006-01-01")
invisible(rf_base_cache_seed_save(FX, NULL, ck8s, root = R3))
h8 <- rf_base_cache_load(file.path(R3, ".cache", "rf_base_signal", ck8$file), ck8$key)
chk(!identical(h8$why, "hit"), "S8 start 가 다르면 셀 키로 적중하지 않는다(음성 대조)", h8$why)
D9 <- copy(DT)[, Date := as.character(Date)]
e9 <- tryCatch({ rf_base_cache_seed_key(ENG, D9, root = R0, start = "2005-01-01"); "no_error" }, error = function(e) conditionMessage(e))
chk(grepl("Date 형", e9), "S9 Date 형이 아니면 시드 키를 만들지 않는다", e9)

cat("=== S10 배선(소스 재도출 — 주석 제외) ===\n")
strip <- function(p) sub("#.*$", "", readLines(p, warn = FALSE, encoding = "UTF-8"))
rp <- strip(RPR); vf <- strip(VER)
gate_ln <- grep('QVEST_RP_SEED_BASE_CACHE', rp, fixed = TRUE)
chk(length(gate_ln) == 1L && grepl("is.null(data_cutoff)", rp[gate_ln], fixed = TRUE) && grepl('"1"', rp[gate_ln], fixed = TRUE),
    "S10a 러너 시드 관문 = 환경변수 \"1\" ∧ data_cutoff NULL (한 곳)", paste(gate_ln, collapse = ","))
i_key <- grep("rf_base_cache_seed_key(", rp, fixed = TRUE)[1]; i_src <- grep("source(factor_engine_path", rp, fixed = TRUE)[1]
i_sav <- grep("rf_base_cache_seed_save(", rp, fixed = TRUE)[1]; i_flt <- grep("FACTORS <- FACTORS[Date <= data_cutoff]", rp, fixed = TRUE)[1]
chk(!anyNA(c(i_key, i_src, i_sav)) && i_key < i_src && i_src < i_sav && (is.na(i_flt) || i_sav < i_flt),
    "S10b 키는 엔진 실행 **전**(지문이 엔진의 참조 수정에 안 흔들림) · 저장은 원산출 직후 필터 **전**",
    sprintf("key=%s src=%s save=%s filter=%s", i_key, i_src, i_sav, i_flt))
chk(any(grepl('Sys.setenv(QVEST_RP_SEED_BASE_CACHE = "1")', vf, fixed = TRUE)), "S10c 레인 검증기가 시드를 켠다")
others <- c(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R"), file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
            file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
on_elsewhere <- others[vapply(others, function(p) file.exists(p) && any(grepl("QVEST_RP_SEED_BASE_CACHE", strip(p), fixed = TRUE)), logical(1))]
chk(!length(on_elsewhere), "S10d 셀 워커·병렬 러너·셀 엔진은 시드를 켜지 않는다(셀 산출을 기저로 심지 않는다)", paste(basename(on_elsewhere), collapse = ","))

if (identical(Sys.getenv("RF_SEED_REALDATA", ""), "1")) {
  cat("=== S11 실데이터(운영 .cache 읽기 전용) ===\n")
  suppressMessages(library(arrow))
  RW <- as.data.table(read_parquet(file.path(ROOT, ".cache", "rawdata.parquet")))
  if (!inherits(RW$Date, "Date")) RW[, Date := as.Date(Date, tz = "Asia/Seoul")]      # 러너와 같은 변환
  t0 <- Sys.time()
  ks <- rf_base_cache_seed_key(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"), RW, root = ROOT, start = "2005-01-01")
  t_seed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  setorder(RW, Ticker, Date)                                                        # 셀과 같은 정렬(참조)
  RW[, .TV := 0][, .adv20_l1 := 0][, .mom_12_1 := 0]
  kc <- rf_base_cache_key(unname(tools::md5sum(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"))),
                          file.path(ROOT, ".cache", "rawdata.parquet"), file.path(ROOT, ".cache", "benchmark.parquet"),
                          file.path(ROOT, ".cache", "factor_db"), data_fp = rf_base_data_fingerprint(RW),
                          n_rows = nrow(RW), start = as.Date("2005-01-01"))
  chk(identical(ks$key, kc$key), sprintf("S11 실데이터 %d행 — 시드 키 = 셀 키 (시드 키 계산 %.1f초)", nrow(RW), t_seed),
      paste(substr(ks$key, 1, 80), "vs", substr(kc$key, 1, 80)))
}
for (r in c(R0, R1, R2, R3)) unlink(r, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", P, F))
cat(sprintf('{"test":"rf_base_cache_seed","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
quit(status = if (F > 0L) 1L else 0L)
