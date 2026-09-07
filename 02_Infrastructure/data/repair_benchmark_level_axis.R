#!/usr/bin/env Rscript
#==============================================================================
# repair_benchmark_level_axis.R — 벤치마크 레벨 축 재척도 (기본 dry-run)
#
# 대상: .cache/benchmark.parquet::BM_Close
# 하는 일: BM_Close := BM_Close / 실측배수.  **BM_Ret 은 한 값도 건드리지 않는다**
#          (수익률은 스케일 불변 — 그래서 이 수리는 어떤 백테스트 수치도 바꾸지 않는다).
#
# ─── 왜 상수 나눗셈인가, 그리고 그 한계 (실측 2026-09-07) ─────────────────────
# BM_Close / kospi200 은 **상수가 아니다**. 계단 433개로 갈리고, 계단의 위치가 전부
# indices.parquet 에는 있는데 benchmark.parquet 에는 없는 세션(1990~98 토요장 438건 +
# 2024-12-30 유령 세션 + 2건)과 일치한다. 검증:
#     ratio(2025-01-02)/ratio(2024-12-27) = 1.003807186458
#     1/(1 + kospi200 2024-12-30 수익률)  = 1.003807186458   (오차 <1e-9)
# 즉 BM_Close 는 지수 레벨이 아니라 **벤치 자신의 거래일 위에서 BM_Ret 을 체인한 NAV** 다.
#
# ⇒ 이 수리는 **현행 구간을 공표 지수 레벨에 맞춘다**. 그 앞 구간에 남는 잔차
#   (1998-12-07~2024-12-27 에서 0.38% · 1990~98 에서 최대 43%)는 재척도가 만든 오차가
#   아니라 **결손 세션 441건이라는 기존 결함**이다. 지금은 8.8배 오프셋 안에 숨어 있고,
#   재척도 후에는 배수가 1 에서 벗어난 값으로 **보이게** 된다. 그것을 상수로 지울 수는
#   없다 — 지우려면 결손 세션을 복원해야 하고 그건 BM_Ret 을 바꾸는 별개 과제다.
#   숨기는 것보다 드러내는 쪽을 고른다.
#
# ─── 실쓰기 규약 ─────────────────────────────────────────────────────────────
#   · 기본 dry-run. 실제 쓰기는 --write 명시.
#   · 06_Registry/reinforce_auto_config.json::enabled == true 면 **쓰지 않는다**.
#     무인 강화 레인이 도는 중에 벤치를 갈아끼우면 진행 중 측정과 완료 측정이 다른
#     파일 위에 서게 된다. 킬스위치를 내린 뒤 다시 부를 것(--ignore-kill-switch 는
#     오케스트레이터가 그 사실을 확인했을 때만).
#   · 백업 = .cache/benchmark_pre_rescale_<YYYYMMDD>.parquet (있으면 덮어쓰지 않음).
#   · 가드가 하나라도 어긋나면 쓰지 않는다.
#
# 사용:
#   Rscript 02_Infrastructure/data/repair_benchmark_level_axis.R              # dry-run
#   Rscript 02_Infrastructure/data/repair_benchmark_level_axis.R --write      # 실쓰기
#   [--path P] [--scale X] [--backup-tag YYYYMMDD] [--ignore-kill-switch]
# 종료코드: 0=정상(수리 불요 또는 dry-run 정상) / 1=가드 실패·차단 / 2=판정 불가
#==============================================================================

suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) == 1L && length(args) >= i + 1L) args[i + 1L] else default
}
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
ROOT <- gsub("\\\\", "/", ROOT)

BM_PATH <- getarg("--path", file.path(ROOT, ".cache", "benchmark.parquet"))
DO_WRITE <- "--write" %in% args
TAG <- getarg("--backup-tag", format(Sys.Date(), "%Y%m%d"))

source(file.path(ROOT, "02_Infrastructure/data/benchmark_level_axis.R"))
cfg <- bench_level_config(ROOT)

cat("=== benchmark 레벨 축 재척도 ===\n")
cat(sprintf("  대상   : %s\n", BM_PATH))
cat(sprintf("  정본 축: %s (허용 |배수-1| <= %.4f)\n", cfg$BENCH_LEVEL_AXIS, cfg$BENCH_LEVEL_TOL))
if (!file.exists(BM_PATH)) { cat("  ★대상 부재 — 판정 불가\n"); quit(status = 2L) }

bm <- as.data.table(read_parquet(BM_PATH))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
pre <- copy(bm)
n0 <- nrow(bm); cols0 <- names(bm)

ref <- bench_level_reference(ROOT)
lv  <- bench_level_axis_check(bm, ref, tol = cfg$BENCH_LEVEL_TOL,
                              min_sessions = cfg$BENCH_LEVEL_MIN_SESSIONS,
                              window_sessions = cfg$BENCH_LEVEL_WINDOW_SESSIONS)
cat(sprintf("  현 상태: %s — %s\n", lv$status, lv$detail))
if (identical(lv$status, "no_measure")) { cat("  ★판정 불가 — 참조 지수를 구하지 못했다.\n"); quit(status = 2L) }
if (identical(lv$status, "ok")) { cat("  수리 불요 (이미 정본 축).\n"); quit(status = 0L) }

SCALE <- suppressWarnings(as.numeric(getarg("--scale", as.character(lv$scale))))
if (!is.finite(SCALE) || SCALE <= 0) { cat("  ★배수 산출 불가 — 중단\n"); quit(status = 2L) }
cat(sprintf("\n  재척도 배수 = %.9f  (BM_Close := BM_Close / %.9f)\n", SCALE, SCALE))

post <- bench_level_rescale(bm, SCALE)

# ── 전후 (dry-run 산출) ───────────────────────────────────────────────────────
show_rows <- function(d, lbl) {
  s <- rbind(head(d, 2), tail(d, 3))
  cat(sprintf("  [%s]\n", lbl))
  for (i in seq_len(nrow(s)))
    cat(sprintf("    %s  BM_Close=%14.6f  BM_Ret=%+.6f\n",
                format(s$Date[i]), s$BM_Close[i], s$BM_Ret[i]))
}
cat("\n--- 전후 ---\n"); show_rows(pre, "before"); show_rows(post, "after")

lv2 <- bench_level_axis_check(post, ref, tol = cfg$BENCH_LEVEL_TOL,
                              min_sessions = cfg$BENCH_LEVEL_MIN_SESSIONS,
                              window_sessions = cfg$BENCH_LEVEL_WINDOW_SESSIONS)
cat(sprintf("\n  수리 후 판정: %s — %s\n", lv2$status, lv2$detail))

# 재척도로 **드러나는** 구간(결손 세션 잔재)을 정직하게 보고한다 — 이 수리가 만든 오차가 아니다.
if (nrow(ref)) {
  mm <- merge(post[, .(Date, BM_Close)], ref[, .(Date, ref_close)], by = "Date")
  if (nrow(mm)) {
    mm[, ratio := BM_Close / ref_close]
    era <- function(a, b) { s <- mm[Date >= as.Date(a) & Date <= as.Date(b)]
      if (!nrow(s)) return("n/a")
      sprintf("%.6f~%.6f (n=%d)", min(s$ratio), max(s$ratio), nrow(s)) }
    cat("\n  [수리 후 배수 구간별 — 잔차는 결손 세션 441건(1990~98 토요장 438 + 2024-12-30 등)의 것이다]\n")
    cat(sprintf("    1990-01-05~1998-12-04 : %s\n", era("1990-01-05", "1998-12-04")))
    cat(sprintf("    1998-12-07~2024-12-27 : %s\n", era("1998-12-07", "2024-12-27")))
    cat(sprintf("    2025-01-02~            : %s\n", era("2025-01-02", "2999-12-31")))
  }
}

# ── 가드 ──────────────────────────────────────────────────────────────────────
g <- list()
g$rows_unchanged  <- nrow(post) == n0
g$cols_unchanged  <- identical(names(post), cols0)
g$dates_unchanged <- identical(post$Date, pre$Date)
# ★핵심: BM_Ret 은 **비트 단위로** 불변이어야 한다.
g$bm_ret_bit_identical <- identical(post$BM_Ret, pre$BM_Ret)
# 레벨은 전 행이 정확히 같은 배수만큼 이동했다
g$level_uniform_scale <- {
  ok <- is.finite(pre$BM_Close) & pre$BM_Close != 0
  isTRUE(all(abs(post$BM_Close[ok] / pre$BM_Close[ok] - 1 / SCALE) < 1e-12))
}
# 내부 정합(BM_Ret == BM_Close 전일대비)이 수리 전과 같은 수준으로 유지된다
resid <- function(d) { r <- d$BM_Close / shift(d$BM_Close) - 1
  i <- which(!is.na(r) & !is.na(d$BM_Ret)); if (!length(i)) NA_real_ else max(abs(r[i] - d$BM_Ret[i])) }
g$internal_consistency_kept <- {
  a <- resid(pre); b <- resid(post); is.finite(a) && is.finite(b) && b <= max(a, 1e-9) * 10 }
g$post_axis_ok <- identical(lv2$status, "ok")

cat("\n--- 가드 ---\n")
for (k in names(g)) cat(sprintf("  %-26s %s\n", k, if (isTRUE(g[[k]])) "PASS" else "★FAIL"))
if (!all(vapply(g, isTRUE, logical(1)))) {
  cat("\n★가드 FAIL — 쓰지 않고 중단합니다.\n"); quit(status = 1L)
}

if (!DO_WRITE) {
  cat("\n[dry-run] --write 가 없어 파일을 바꾸지 않았습니다.\n"); quit(status = 0L)
}

# ── 실쓰기 규약 ───────────────────────────────────────────────────────────────
RAC <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")
if (!"--ignore-kill-switch" %in% args) {
  if (!file.exists(RAC)) {
    cat("\n★reinforce_auto_config.json 부재 — 무인 레인 상태를 확인할 수 없어 쓰지 않습니다.\n")
    quit(status = 1L)
  }
  rac <- tryCatch(jsonlite::fromJSON(RAC, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(rac) || is.null(rac$enabled)) {
    cat("\n★reinforce_auto_config.json::enabled 판독 불가 — 쓰지 않습니다.\n"); quit(status = 1L)
  }
  if (isTRUE(rac$enabled)) {
    cat("\n★무인 강화 레인이 켜져 있습니다(reinforce_auto_config.json::enabled=true) — 쓰지 않습니다.\n")
    cat("  진행 중 측정과 완료 측정이 서로 다른 벤치 위에 서게 됩니다.\n")
    cat("  킬스위치를 내린 뒤 다시 부르십시오.\n")
    quit(status = 1L)
  }
}

BAK <- file.path(dirname(BM_PATH), sprintf("benchmark_pre_rescale_%s.parquet", TAG))
if (file.exists(BAK)) {
  cat(sprintf("\n★백업이 이미 있습니다: %s — 덮어쓰지 않고 중단합니다.\n", BAK)); quit(status = 1L)
}
file.copy(BM_PATH, BAK, overwrite = FALSE)
cat(sprintf("\n백업 → %s\n", BAK))

src <- file.path(ROOT, "02_Infrastructure/utils/atomic_parquet.R")
if (file.exists(src)) {
  source(src)
  qvest_atomic_write_parquet(post, BM_PATH, tag = "repair/bench_level_axis")
} else {
  tmp <- paste0(BM_PATH, ".tmp", Sys.getpid())
  write_parquet(post, tmp)
  if (!file.rename(tmp, BM_PATH)) { cat("★교체 실패 — 원본 보존, tmp 잔존: ", tmp, "\n"); quit(status = 1L) }
}
cat("완료.\n")
quit(status = 0L)
