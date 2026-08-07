#!/usr/bin/env Rscript
# repair_benchmark_scale_break_20260727.R — benchmark.parquet 2026-07-27 스케일 단절 국소 수리
#
# 사건(2026-08-08 실측):
#   `.cache/benchmark.parquet` 의 BM_Close 가 2026-07-27 에 9,325.467 → 1,069.220 으로
#   **8.72배 축소**된 다른 스케일로 갈아탔다. BM_Ret 은 BM_Close 와 9,003행 전부 정합
#   (잔차 0행)이므로 결함은 수익률 계산이 아니라 **종가 시리즈 자체**다.
#   그 결과 07-27 수익률이 -88.53% 로 기록됐고(KOSPI 계열에서 물리적으로 불가),
#   2026-07 복리 월수익이 **-91.36%** 가 됐다 — 정상값 -23.63% 대비 **67.72%p 과대 오차**.
#   7월을 포함하는 모든 초과수익 측정이 이 벤치를 쓰면 그만큼 부풀려진다.
#
# 판정 근거 (추정 아님):
#   1. **수익률은 스케일 불변**이다. 그래서 break 를 가로지르는 07-27 하루만 오염되고
#      07-28 이후 일간 수익률은 정상이다 — 실제로 `RAWDATA::BM_Ret` 과 07-28~08-07 전 구간 **일치**.
#   2. 07-27 의 참값은 `RAWDATA::BM_Ret` = +0.012922. RAWDATA 에는 BM_Close 가 없어
#      (컬럼 실측: BM_Ret 만 존재) **break 를 타지 않았다** = 독립 증거.
#   3. 07-27 을 제외하면 두 소스의 2026-07 복리수익이 **-24.6054% 로 완전 일치**한다.
#   4. 08-02 수리([[project-benchmark-two-source-divergence-20260802]])가 정본으로 확정한
#      7월 값이 -23.63% 이고, 현재 RAWDATA 가 정확히 그 값을 갖는다.
#
# 수리 내용:
#   · BM_Ret[2026-07-27] := RAWDATA 값(+0.012922)
#   · BM_Close[2026-07-27 이후] := 마지막 정상 종가(07-24 = 9,325.467)에서 교정된 수익률로 **재체인**
#     → 1990년부터 이어지던 스케일 연속성 복원 + BM_Ret↔BM_Close 내부 정합(잔차 0) 유지.
#     ★07-28 이후 **수익률은 한 값도 바꾸지 않는다**(두 소스가 이미 합의한 값이므로).
#
# 가드: 하나라도 어긋나면 write 하지 않는다. 백업 필수.
# 읽기 전용 아님 — 실행 전 백업 경로 확인할 것.
suppressPackageStartupMessages({ library(arrow); library(data.table) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
BENCH_P <- ".cache/benchmark.parquet"
RAW_P   <- ".cache/RAWDATA.parquet"
BREAK_D <- as.Date("2026-07-27")
stopifnot(file.exists(BENCH_P), file.exists(RAW_P))

b <- as.data.table(read_parquet(BENCH_P)); b[, Date := as.Date(Date)]; setorder(b, Date)
n0 <- nrow(b); cols0 <- names(b)
pre <- copy(b)

# 참값 조달 — RAWDATA 의 07-27 BM_Ret (독립 소스)
r <- as.data.table(read_parquet(RAW_P, col_select = all_of(c("Date", "BM_Ret"))))
r[, Date := as.Date(Date)]
true_ret <- unique(r[Date == BREAK_D & !is.na(BM_Ret)]$BM_Ret)
if (length(true_ret) != 1L) {
  cat(sprintf("[repair] ★RAWDATA 의 %s BM_Ret 이 유일하지 않음(%d개) — 중단\n",
              BREAK_D, length(true_ret))); quit(status = 1L)
}
old_ret   <- b[Date == BREAK_D]$BM_Ret
anchor_px <- b[Date < BREAK_D][.N]$BM_Close      # 마지막 정상 종가 (07-24)
cat(sprintf("[repair] 07-27 BM_Ret  %.6f → %.6f  (앵커 종가 %.3f)\n", old_ret, true_ret, anchor_px))

# ── 적용: 07-27 수익률 교정 후 그 날부터 종가 재체인
idx <- which(b$Date >= BREAK_D)
b[Date == BREAK_D, BM_Ret := true_ret]
b[idx, BM_Close := anchor_px * cumprod(1 + BM_Ret)]

# ── 가드 ──────────────────────────────────────────────────────────────────────
g <- list()
g$rows_unchanged   <- nrow(b) == n0
g$cols_unchanged   <- identical(names(b), cols0)
g$dates_unchanged  <- identical(b$Date, pre$Date)
# 구간 밖(07-27 이전)은 종가·수익률 모두 완전 불변
g$pre_break_frozen <- {
  a <- pre[Date < BREAK_D]; z <- b[Date < BREAK_D]
  isTRUE(all.equal(a$BM_Close, z$BM_Close)) && isTRUE(all.equal(a$BM_Ret, z$BM_Ret))
}
# 07-28 이후 **수익률은 한 값도 바뀌지 않았다**
g$post_returns_frozen <- isTRUE(all.equal(pre[Date > BREAK_D]$BM_Ret, b[Date > BREAK_D]$BM_Ret))
# 수익률이 바뀐 날은 정확히 07-27 하루
g$only_break_ret_changed <- {
  d <- which(!mapply(function(x, y) isTRUE(all.equal(x, y)), pre$BM_Ret, b$BM_Ret))
  length(d) == 1L && identical(b$Date[d], BREAK_D)
}
# 내부 정합 복원: BM_Ret == BM_Close/lag-1 (첫 행 NA 제외)
g$internal_consistent <- {
  chk <- copy(b)[, rfc := BM_Close / shift(BM_Close) - 1]
  max(abs(chk[!is.na(rfc)]$BM_Ret - chk[!is.na(rfc)]$rfc)) < 1e-9
}
# 스케일 연속성: break 전후 종가 점프가 정상 범위
g$no_scale_jump <- abs(b[Date == BREAK_D]$BM_Close / anchor_px - 1) < 0.30
# 2026-07 복리수익이 RAWDATA 와 일치
g$july_matches_raw <- {
  jb <- b[Date >= as.Date("2026-07-01") & Date <= as.Date("2026-07-31")]
  jr <- unique(r[!is.na(BM_Ret)], by = "Date")[Date >= as.Date("2026-07-01") & Date <= as.Date("2026-07-31")]
  abs((prod(1 + jb$BM_Ret) - 1) - (prod(1 + jr$BM_Ret) - 1)) < 1e-9
}

cat("\n[repair] 가드:\n")
for (k in names(g)) cat(sprintf("  %-24s %s\n", k, if (isTRUE(g[[k]])) "PASS" else "★FAIL"))
if (!all(vapply(g, isTRUE, logical(1)))) {
  cat("\n[repair] ★가드 FAIL — 쓰지 않고 중단합니다.\n"); quit(status = 1L)
}

# ── 백업 후 write
bak <- sprintf("%s.bak_%s_scalebreak", BENCH_P, format(Sys.time(), "%Y%m%d_%H%M%S"))
file.copy(BENCH_P, bak, overwrite = FALSE)
cat(sprintf("\n[repair] 백업 → %s\n", bak))
tmp <- paste0(BENCH_P, ".tmp")
write_parquet(b, tmp); file.rename(tmp, BENCH_P)
cat(sprintf("[repair] 완료 — 2026-07 복리 %.4f%% (수리 전 -91.3556%%)\n",
            100 * (prod(1 + b[Date >= as.Date("2026-07-01") & Date <= as.Date("2026-07-31")]$BM_Ret) - 1)))
cat(sprintf("[repair] 최종 종가 %s = %.2f (수리 전 %.2f)\n",
            b[.N]$Date, b[.N]$BM_Close, pre[.N]$BM_Close))
