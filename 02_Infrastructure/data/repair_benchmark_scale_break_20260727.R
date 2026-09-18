#!/usr/bin/env Rscript
#==============================================================================
# ★RETIRED 2026-09-18 — 구 리베이스 체인 전용 이음매 수리기 (07-27 국소 수리)
#
# 이 스크립트는 `.cache/benchmark.parquet` 이 **리베이스 체인**(공표 코스피200 × 8.83)이던
# 시절의 일회성 수리기다. 2026-09-18 축 정규화로 그 전제가 사라졌다:
#   BM_Close = 공표 코스피200 지수 종가(포인트) 그대로. 배율 개념 없음.
# ★이 스크립트는 마지막 정상 종가(구 8.834배 앵커) 위에 BM_Ret 을 재체인한다 —
#   새 축에서 실행하면 벤치를 다시 8.83배로 밀어올려 정본을 조용히 파괴한다.
#
# 대체 경로(정본): `python 02_Infrastructure/data/rebuild_benchmark_canonical.py --write`
#   (원천 우선순위 03_Universe/Benchmark_price.xlsx > .cache/krx/kospi_index > 구 체인 환산,
#    manifest = .cache/benchmark_axis.json, 백업 = *.bak_axis_migration_<ts>)
#
# ★파일은 남긴다(사료). 실행만 막는다 — 호출부는 2026-09-18 기준 0곳이다.
#   되살리려면 이 블록을 지우는 것이 아니라, 왜 새 축에서 필요한지를 먼저 적을 것.
#==============================================================================
if (!("--i-know-this-is-retired" %in% commandArgs(trailingOnly = TRUE))) {
  cat("[RETIRED] 이 수리기는 2026-09-18 축 정규화로 퇴역했습니다.
")
  cat("  대체: python 02_Infrastructure/data/rebuild_benchmark_canonical.py --write
")
  cat("  (구 축(8.83배 체인)으로 되돌리는 동작이라 새 축에서 실행하면 정본을 파괴합니다.)
")
  quit(status = 2L)
}


# repair_benchmark_scale_break_20260727.R — benchmark.parquet 2026-07-27 스케일 단절 국소 수리
#
# ██ SUPERSEDED 2026-08-09 — 실행하지 말 것 (도훈 적발 "어제 고쳤는데 왜이러냐 또?") ██
#
#   이 스크립트는 **재발했다**. 다음날 2026-07-29 에 같은 -89% 단절이 다시 나타났고,
#   원인은 이 수리가 두 가지를 놓쳤기 때문이다:
#
#   (1) **날짜를 박았다.** 단절은 고정점이 아니라 **매일 하루씩 전진하는 이음매**다.
#       생성기 호출부가 `--start_date "$(date -d '10 days ago')"`(daily_refresh.sh:122 /
#       morning_briefing.sh:124)이므로 cutoff 가 매일 이동하고, 이음매는 그 cutoff 에 생긴다.
#       특정 날짜를 고치는 수리는 원리적으로 하루밖에 못 버틴다.
#
#   (2) **단절의 틀린 쪽을 고쳤다.** 아래 수리는 BM_Close 를 break 이후로 **구 스케일
#       앵커(9,325=8.834×KPI200)에서 재체인**한다. 그런데 정본은 생 KPI200 쪽이고
#       구 스케일은 리베이스 배수일 뿐이다. 결과적으로 이 수리가 **정상 스케일이던
#       naver 꼬리를 8.834× 로 되돌려놓고**, 다음 daily 패치가 그것을 다시 1.0× 로
#       되돌리는 **두 writer 간 줄다리기**가 됐다 — 매일 이음매 재생산.
#
#   ★근본 수리는 생성기에 있다: `naver_benchmark_update.py::patch_benchmark_parquet()` 를
#     **레벨 접합 → 수익률 접합**으로 교체(2026-08-09). 수익률은 스케일 불변이라 이음매가
#     구조적으로 생기지 않으며, canonical 스케일 median + 앵커 후퇴로 **기존 이음매도
#     같은 경로에서 자동 치유**된다(멱등 실측: 2회차 healed=0, 정체 일치 100%).
#     검사기 = `08_Tests/hooks/test_benchmark_scale_seam.py` (위반 주입 8/8,
#     MUT-1 이 구 레벨-접합 구현의 -88.9% 이음매 생성을 실증).
#
#   본 파일은 사건 기록으로만 retain 한다. 재실행 시 벤치가 다시 갈라진다.
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

# ── SUPERSEDED 차단 (2026-08-09) ──────────────────────────────────────────────
# 이 수리는 벤치를 8.834× 구 스케일로 되돌려 daily naver 패치와 줄다리기를 만든다.
# 재실행 = 이음매 재생산. 근본 수리는 naver_benchmark_update.py(수익률 접합)에 있다.
if (!identical(Sys.getenv("QVEST_ALLOW_SUPERSEDED_BENCH_REPAIR"), "1")) {
  cat("[repair] ★SUPERSEDED — 실행 차단 (2026-08-09).\n",
      "  이 스크립트는 스케일 단절의 *틀린 쪽*을 고치고 날짜를 박아, 07-27 수리 다음날\n",
      "  07-29 로 재발시켰다. 정본 수리 = naver_benchmark_update.py 의 수익률 접합.\n",
      "  검사기 = 08_Tests/hooks/test_benchmark_scale_seam.py\n",
      "  그래도 실행하려면 QVEST_ALLOW_SUPERSEDED_BENCH_REPAIR=1 를 명시할 것.\n", sep = "")
  quit(status = 0L)
}

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
