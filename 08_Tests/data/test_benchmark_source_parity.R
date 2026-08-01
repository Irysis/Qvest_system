# ============================================================================
# test_benchmark_source_parity.R — 벤치 2소스 정합 검사 위반 주입 테스트
# ----------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/validation/benchmark_source_parity.R
#
# ★왜: `.cache/RAWDATA.parquet::BM_Ret` 과 `.cache/benchmark.parquet::BM_Ret` 은
#   독립 생성 경로를 갖는데(krx_build_rawdata.R:223 자체계산 vs
#   incremental_update_file.R:181 조인) **정합 검사가 없었다**. 그 결과 2026-07 에
#   8일이 갈렸고 4일은 RAWDATA 가 정확히 0 — 07-28 폭락 -11.55% 가 0으로 소실됐다.
#   값이 0 이면 "그날 안 움직였다"로 읽혀 **결손이 정상 데이터로 위장**된다.
#   2026-07-25 date32 writer 불일치(조인 silent all-NA, 7일 방치, 감지장치 0)와 같은 계통.
#
#   이 검사기가 죽으면 두 소스가 조용히 갈리는 상태로 되돌아가므로,
#   양성 대조 + 위반 주입 양방향으로 차단 실효를 상시 시험한다.
#
# 실행: Rscript 08_Tests/data/test_benchmark_source_parity.R
# ============================================================================
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))

PASS <- 0L; FAIL <- 0L
ok <- function(cond, name, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

source("02_Infrastructure/validation/benchmark_source_parity.R")

sbx <- file.path(tempdir(), paste0("bsp_", as.integer(Sys.time())))
dir.create(sbx, recursive = TRUE, showWarnings = FALSE)

# 합성 시계열: 300 거래일, 최근 구간 포함(오늘 기준 역산 — 최근/과거 판정 축 시험)
mk <- function(bm_raw, bm_bench, dates) {
  rp <- file.path(sbx, paste0("raw_",   as.integer(runif(1, 1e6, 9e6)), ".parquet"))
  bp <- file.path(sbx, paste0("bench_", as.integer(runif(1, 1e6, 9e6)), ".parquet"))
  # RAWDATA 형상: Ticker 다중 행에 같은 BM_Ret (실제 구조 모사)
  raw <- rbindlist(lapply(c("A001", "A002"), function(tk)
    data.table(Date = dates, Ticker = tk, BM_Ret = bm_raw)))
  write_parquet(raw, rp)
  write_parquet(data.table(Date = dates, BM_Close = cumprod(1 + bm_bench) * 1000,
                           BM_Ret = bm_bench), bp)
  list(raw = rp, bench = bp)
}

set.seed(42)
n <- 300L
dates <- seq(Sys.Date() - (n * 2L), by = "1 day", length.out = n)  # 최근까지 포함
base_ret <- round(rnorm(n, 0, 0.01), 8)

cat("=== test_benchmark_source_parity (양성 대조 + 위반 주입) ===\n")
cat("--- A. 양성 대조: 두 소스가 같으면 OK 여야 한다 ---\n")
p <- mk(base_ret, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench)
ok(identical(r$severity, "OK"), "A1 동일 소스 → OK", sprintf("(got %s: %s)", r$severity, r$note))
ok(r$n_mismatch == 0L, "A2 불일치 0")
ok(r$n_common == n, "A3 공통 날짜 전량 대조", sprintf("(%d vs %d)", r$n_common, n))

cat("--- B. 위반 주입: 값이 갈리면 잡아야 한다 ---\n")
bad <- base_ret; bad[n - 3L] <- bad[n - 3L] + 0.02          # 최근 구간 2%p 괴리
p <- mk(bad, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench)
ok(identical(r$severity, "CRITICAL"), "B1 최근 불일치 → CRITICAL", sprintf("(got %s)", r$severity))
ok(r$n_mismatch == 1L, "B2 불일치 1일 특정", sprintf("(got %d)", r$n_mismatch))
ok(abs(r$max_abs_diff - 0.02) < 1e-6, "B3 최대 diff 정확", sprintf("(got %g)", r$max_abs_diff))

cat("--- C. ★0-위장 감지 (이번 실사고의 핵심 형상) ---\n")
z <- base_ret; z[n - 5L] <- 0                                # RAWDATA 만 0, bench 는 non-zero
p <- mk(z, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench)
ok(nrow(r$zero_masked) == 1L, "C1 RAWDATA=0 ∧ bench≠0 을 zero_masked 로 분리",
   sprintf("(got %d)", nrow(r$zero_masked)))
ok(identical(r$severity, "CRITICAL"), "C2 0-위장도 CRITICAL")
ok(grepl("0-위장", r$note), "C3 note 에 0-위장 건수 노출")

cat("--- D. 과거 전용 불일치는 WARN (최근/과거 축 분리) ---\n")
old <- base_ret; old[3L] <- old[3L] + 0.002   # 아주 오래된 1일, 월 괴리 0.5%p 미만
p <- mk(old, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench, recent_window = 30L, month_gap_pp = 5.0)
ok(identical(r$severity, "WARN"), "D1 과거 구간만 불일치 → WARN(CRITICAL 아님)",
   sprintf("(got %s: %s)", r$severity, r$note))
ok(r$n_recent_mismatch == 0L, "D2 최근 창 내 불일치 0으로 계산")

cat("--- E. 월 누적 괴리 축 ---\n")
m <- base_ret
idx <- (n - 25L):(n - 20L); m[idx] <- m[idx] + 0.01          # 한 달에 누적 괴리
p <- mk(m, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench, recent_window = 5L)   # 최근창 밖으로 밀어냄
ok(nrow(r$bad_months) >= 1L, "E1 월 누적 괴리 0.5%p 초과 월 검출",
   sprintf("(got %d)", nrow(r$bad_months)))
ok(identical(r$severity, "CRITICAL"), "E2 월 괴리는 최근 여부와 무관하게 CRITICAL")

cat("--- F. Date별 BM_Ret 유일성 위반 ---\n")
rp <- file.path(sbx, "raw_dup.parquet"); bp <- file.path(sbx, "bench_dup.parquet")
dupraw <- rbind(data.table(Date = dates, Ticker = "A001", BM_Ret = base_ret),
                data.table(Date = dates, Ticker = "A002", BM_Ret = base_ret + 0.001))
write_parquet(dupraw, rp)
write_parquet(data.table(Date = dates, BM_Close = 1000, BM_Ret = base_ret), bp)
r <- benchmark_source_parity(rp, bp)
ok(nrow(r$dup_dates) > 0L, "F1 한 Date 에 서로 다른 BM_Ret → 검출")
ok(identical(r$severity, "CRITICAL"), "F2 소스 자체 불일치는 CRITICAL")

cat("--- G. 소스 부재는 UNMEASURED (OK 위장 금지) ---\n")
r <- benchmark_source_parity(file.path(sbx, "nonexistent.parquet"), p$bench)
ok(identical(r$severity, "UNMEASURED"), "G1 파일 부재 → UNMEASURED",
   sprintf("(got %s)", r$severity))
ok(!identical(r$severity, "OK"), "G2 ★측정 불가를 '정상'으로 위장하지 않음")

cat("--- H. 음성 통제: 검사기가 무조건 CRITICAL 을 뱉는 게 아님 ---\n")
p <- mk(base_ret, base_ret, dates)
r <- benchmark_source_parity(p$raw, p$bench)
ok(identical(r$severity, "OK"), "H1 B~G 주입 후에도 정상 입력은 OK (검사기 생존)")

unlink(sbx, recursive = TRUE)
cat(sprintf("\nPASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"benchmark_source_parity","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
