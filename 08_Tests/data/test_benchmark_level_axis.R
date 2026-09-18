# test_benchmark_level_axis.R — 벤치마크 레벨 축 위반 주입 검사 (2026-09-07 신설)
#
# ★2026-09-18 축 정규화에 맞춰 개정. 규약이 바뀌었다:
#     BM_Close = **공표 코스피200 지수 종가(포인트) 그대로**. 배율 개념 없음.
#   따라서 재는 것도 둘이 됐다 — ①정합(값이 같은가) ②이음매(하루 사이 비율 계단).
#   구판 축 C 는 체인 축(8.83배) 위에서 |배수-1|<=0.01 을 요구했으므로 **원리적으로
#   통과 불가**였다(09-07 신설 이후 매일 FAIL). 상시 빨강은 상시 침묵이다.
#
# 지키는 것: `.cache/benchmark.parquet::BM_Close` 가 공표 코스피200 **레벨**에서
#   떨어져 나갔을 때 그것이 **드러나는가**. 2026-07~09 에는 안 드러났다 —
#   BM_Close 가 지수의 8.834448배 위에 있었는데 하루 사이 배수 점프가 0건이라
#   "연속이면 정상" 으로 보였고, 이 불변식을 적어 둔 가드(build_cache.R)는
#   ① daily_refresh 가 부르지 않는 찬 경로에 있었고
#   ② 바로 앞 build_index_cache.py 가 같은 프로세스에서 방금 쓴 자기 산출물을
#      비교하는 동어반복이라 구조적으로 통과했다.
#
# ★핵심은 가드가 **진짜 위반에 빨개지는가**이다. 주입 없이 초록은 무의미하다.
# ★그리고 이 검사는 **운영 상태를 빌리지 않는다** — 판정 절은 전부 tempdir 픽스처이고,
#   실데이터 절(L)은 "지금 어긋나 있다" 가 아니라 "가드 판정이 실측값과 일치한다" 를
#   재므로 재구축 전후 어느 쪽에서도 성립한다.
#
# 실행: Rscript 08_Tests/data/test_benchmark_level_axis.R

suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
ROOT <- gsub("\\\\", "/", ROOT)
LVL  <- file.path(ROOT, "02_Infrastructure/data/benchmark_level_axis.R")
GATE <- file.path(ROOT, "02_Infrastructure/data/benchmark_currency_gate.R")
RSCRIPT <- file.path(R.home("bin"), "Rscript")

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(name, why) { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP  %s (%s)\n", name, why)) }
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

stopifnot(file.exists(LVL), file.exists(GATE))
source(LVL)

# 실측 배수 — 이 값 자체가 검사 대상이 아니라 **위반 주입의 크기**다.
REAL_SCALE <- 8.834448439104

TD <- file.path(tempdir(), paste0("bla_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)

# ── 픽스처: 지수 레벨과 그 위에서 체인한 벤치 ────────────────────────────────
mk_fixture <- function(n = 60L, scale = 1, drop_bm_close = FALSE, seed = 7L) {
  set.seed(seed)
  d <- seq(as.Date("2026-06-01"), by = "day", length.out = n)
  r <- c(0, rnorm(n - 1L, 0.0003, 0.01))
  lvl <- 1000 * cumprod(1 + r)
  ref <- data.table(Date = d, ref_close = lvl, ref_source = "fixture")
  bm  <- data.table(Date = d, BM_Close = lvl * scale, BM_Ret = c(NA_real_, diff(lvl) / head(lvl, -1)))
  if (drop_bm_close) bm[, BM_Close := NULL]
  list(bm = bm, ref = ref)
}
wr <- function(dt, nm) { p <- file.path(TD, nm); write_parquet(dt, p); p }

run_gate <- function(bm_path, ref_path = NULL, today = as.Date("2026-07-30"),
                     max_lag = 3650, tol = NULL) {
  a <- c(GATE, "--today", format(today), "--path", bm_path,
         "--max-lag-days", as.character(max_lag), "--updater-rc", "0", "--quiet")
  if (!is.null(ref_path)) a <- c(a, "--ref-path", ref_path)
  if (!is.null(tol))      a <- c(a, "--level-tol", format(tol, scientific = FALSE))
  out <- suppressWarnings(system2(RSCRIPT, args = c("--no-save", a), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  list(status = as.integer(st), out = paste(out, collapse = "\n"))
}

TOL <- 1e-4          # 새 축 문턱(manifest::tolerance). 구판 0.01 은 8.83배만 잡았다
SEAM <- 1e-4         # 이음매 문턱(manifest::seam_tolerance)

cat("=== 양성 대조 (가드가 정상 데이터를 막지 않는다) ===\n")
f0 <- mk_fixture()
v0 <- bench_level_axis_check(f0$bm, f0$ref, tol = TOL)
chk("P1 정합 레벨 → status ok", identical(v0$status, "ok"), sprintf("(status=%s)", v0$status))
chk("P2 배수 1.0", isTRUE(abs(v0$scale - 1) < 1e-9), sprintf("(scale=%s)", format(v0$scale)))
bp0 <- wr(f0$bm, "bm_ok.parquet"); rp0 <- wr(f0$ref, "ref.parquet")
g0 <- run_gate(bp0, rp0)
chk("P3 게이트 exit 0", g0$status == 0L, sprintf("(status=%d)", g0$status))

cat("\n=== 위반 주입 INJ-1 — 실사고 재현 (BM_Close x 8.834448) ===\n")
f1 <- mk_fixture(scale = REAL_SCALE)
v1 <- bench_level_axis_check(f1$bm, f1$ref, tol = TOL)
chk("I1 8.834배 → status violation", identical(v1$status, "violation"), sprintf("(status=%s)", v1$status))
chk("I2 측정 배수가 주입값과 일치",
    isTRUE(abs(v1$scale / REAL_SCALE - 1) < 1e-9), sprintf("(scale=%s)", format(v1$scale)))
bp1 <- wr(f1$bm, "bm_inj1.parquet")
g1 <- run_gate(bp1, rp0)
chk("I3 게이트 exit 1", g1$status == 1L, sprintf("(status=%d)", g1$status))
chk("I4 사유에 C축이 명시됨", grepl("C:", g1$out, fixed = TRUE), "")

cat("\n=== 위반 주입 INJ-2 — 반대 방향 (BM_Close / 8.834448) ===\n")
f2 <- mk_fixture(scale = 1 / REAL_SCALE)
v2 <- bench_level_axis_check(f2$bm, f2$ref, tol = TOL)
chk("I5 축소 방향도 잡힌다", identical(v2$status, "violation"), sprintf("(status=%s)", v2$status))
g2 <- run_gate(wr(f2$bm, "bm_inj2.parquet"), rp0)
chk("I6 게이트 exit 1", g2$status == 1L, sprintf("(status=%d)", g2$status))

cat("\n=== 위반 주입 INJ-3 — **이음매**(정합 축만으로는 못 잡는 하루짜리 계단) ===\n")
# ★이것이 실제로 재발한 형태다: 2025-01-02 에 비율이 8.800942 → 8.834448 로 한 칸 움직였고
#   (배수비 1.0038), 레벨은 연속이라 "연속이면 정상" 으로 보였다. 정합 축만 재면 이 구간의
#   중앙값 배수가 1 근처인 파일에서도 계단을 놓친다 — 그래서 이음매 축이 따로 필요하다.
mk_seam <- function(n = 60L, at = 40L, jump = 1.0038, seed = 7L) {
  f <- mk_fixture(n = n, seed = seed)
  f$bm[at:n, BM_Close := BM_Close * jump]        # 뒤쪽 구간만 한 칸 밀어 올린다
  f
}
f3 <- mk_seam()
v3 <- bench_level_axis_check(f3$bm, f3$ref, tol = TOL, seam_tol = SEAM)
chk("I7 이음매 → status violation", identical(v3$status, "violation"), sprintf("(status=%s)", v3$status))
chk("I8 실패 축에 seam 이 명시됨", grepl("seam", v3$failed_axis %||% "", fixed = TRUE),
    sprintf("(failed_axis=%s)", v3$failed_axis))
chk("I9 계단 날짜를 특정한다", identical(v3$worst_seam_date, f3$bm$Date[40L]),
    sprintf("(worst_seam_date=%s, 기대 %s)", format(v3$worst_seam_date), format(f3$bm$Date[40L])))
g3 <- run_gate(wr(f3$bm, "bm_inj3.parquet"), rp0 <- wr(f3$ref, "ref3.parquet"))
chk("I10 게이트 exit 1", g3$status == 1L, sprintf("(status=%d)", g3$status))
rp0 <- wr(f0$ref, "ref.parquet")   # ★기본 참조 복원 (뒤 절이 f0 기준이다)
# ★음성 대조: 정합 축만 재면(이음매 문턱을 크게) 이 계단은 **통과한다** — 축이 둘인 이유
v3b <- bench_level_axis_check(f3$bm, f3$ref, tol = 0.01, seam_tol = 0.5)
chk("I11 이음매 축을 끄면 같은 파일이 통과 (축 분리의 필요성 실증)",
    identical(v3b$status, "ok"), sprintf("(status=%s)", v3b$status))

cat("\n=== 경계 (문턱이 실제로 그 자리에 있는가) ===\n")
# ★정확히 1+TOL 로 잡지 않는다 — (1+0.01)-1 = 0.010000000000000009 로 IEEE 배정도에서
#   등호 경계가 표현되지 않아 판정이 아니라 부동소수점을 재게 된다. 문턱 **양옆**을 재라.
ve <- bench_level_axis_check(mk_fixture(scale = 1 + TOL * 0.99)$bm, f0$ref, tol = TOL)
chk("E1 배수==1+문턱*0.99 → 통과", identical(ve$status, "ok"), sprintf("(status=%s)", ve$status))
vg <- bench_level_axis_check(mk_fixture(scale = 1 + TOL * 1.01)$bm, f0$ref, tol = TOL)
chk("E1b 배수==1+문턱*1.01 → 차단", identical(vg$status, "violation"), sprintf("(status=%s)", vg$status))
vf <- bench_level_axis_check(mk_fixture(scale = 1 + TOL * 1.5)$bm, f0$ref, tol = TOL)
chk("E2 배수==1+문턱*1.5 → 차단", identical(vf$status, "violation"), sprintf("(status=%s)", vf$status))

cat("\n=== 부재 (부재를 '정상' 으로 읽지 않는다 — no_measure) ===\n")
vn <- bench_level_axis_check(f0$bm, NULL, tol = TOL)
chk("N1 참조 부재 → no_measure(초록 아님)", identical(vn$status, "no_measure"), sprintf("(status=%s)", vn$status))
fnc <- mk_fixture(drop_bm_close = TRUE)
vc <- bench_level_axis_check(fnc$bm, f0$ref, tol = TOL)
chk("N2 BM_Close 컬럼 부재 → no_measure", identical(vc$status, "no_measure"), sprintf("(status=%s)", vc$status))
vs <- bench_level_axis_check(mk_fixture(n = 3L)$bm, mk_fixture(n = 3L)$ref, tol = TOL, min_sessions = 5L)
chk("N3 공통 세션 부족 → no_measure", identical(vs$status, "no_measure"), sprintf("(status=%s)", vs$status))
# ★형제 검사(test_benchmark_currency_gate.R)의 픽스처는 BM_Close 가 없다 —
#   축 C 가 그것을 '위반' 으로 읽으면 그 검사 12건이 통째로 빨개진다. 여기서 못박는다.
gnc <- run_gate(wr(fnc$bm, "bm_nocol.parquet"), rp0)
chk("N4 BM_Close 없는 파일에 게이트 exit 0 (형제 검사 픽스처 호환)",
    gnc$status == 0L, sprintf("(status=%d)", gnc$status))
gnr <- run_gate(bp1, file.path(TD, "no_such_ref.parquet"))
chk("N5 참조 파일 부재 시 게이트가 위반을 날조하지 않는다",
    gnr$status %in% c(0L, 1L), sprintf("(status=%d)", gnr$status))

cat("\n=== 재척도가 BM_Ret 을 건드리지 않는다 (수익률은 스케일 불변) ===\n")
src  <- copy(f1$bm)
resc <- bench_level_rescale(src, REAL_SCALE)
chk("R1 BM_Ret 비트 동일", identical(resc$BM_Ret, src$BM_Ret), "")
chk("R2 BM_Close 가 정확히 배수만큼 이동",
    isTRUE(max(abs(resc$BM_Close * REAL_SCALE - src$BM_Close)) < 1e-9), "")
chk("R3 재척도 후 status ok",
    identical(bench_level_axis_check(resc, f1$ref, tol = TOL)$status, "ok"), "")
chk("R4 행/열 불변", nrow(resc) == nrow(src) && identical(names(resc), names(src)), "")

cat("\n=== 소비자 재도출 — 레벨을 쓰는 엔진이 정말 비율만 쓰는가 ===\n")
# ★파일을 grep 해서 '비율만 쓴다' 고 단정하지 않는다(소스 좌표 단정 금지).
#   엔진을 **두 번 실제로 돌려** 산출물이 비트 동일한지 본다.
ENG <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R")
if (!file.exists(ENG)) {
  skip("C1 pindex 엔진 재도출", "엔진 파일 부재")
} else {
  run_engine <- function(bm_scale) {
    set.seed(11)
    d <- seq(as.Date("2024-01-01"), by = "day", length.out = 200L)
    lvl <- 1000 * cumprod(1 + c(0, rnorm(199L, 0.0003, 0.01)))
    tk <- c("A0001", "A0002", "A0003", "A0004")
    raw <- rbindlist(lapply(seq_along(tk), function(i) {
      p <- 5000 * cumprod(1 + c(0, rnorm(199L, 0.0002 * i, 0.015)))
      data.table(Date = d, Ticker = tk[i], Close = p, High = p * 1.01, Low = p * 0.99,
                 Open = p, Vol = 1e6, Size = 1e12, Ret = c(NA, diff(p) / head(p, -1)),
                 LiqPass = TRUE)
    }))
    e <- new.env(parent = globalenv())
    assign("RAWDATA", copy(raw), envir = e)
    assign("BM_DT", data.table(Date = d, BM_Close = lvl * bm_scale,
                               BM_Ret = c(NA_real_, diff(lvl) / head(lvl, -1))), envir = e)
    out <- capture.output(suppressWarnings(sys.source(ENG, envir = e)))
    list(f = get("FACTORS", envir = e), bmax = max(get("BM_DT", envir = e)$BM_Close))
  }
  ra <- tryCatch(run_engine(1), error = function(err) err)
  rb <- tryCatch(run_engine(REAL_SCALE), error = function(err) err)
  if (inherits(ra, "error") || inherits(rb, "error")) {
    skip("C1 pindex 엔진 재도출",
         paste("엔진 실행 실패:", conditionMessage(if (inherits(ra, "error")) ra else rb)))
  } else {
    # ★처치 전달 확인 먼저 — 재척도가 엔진까지 닿지 않았다면 '불변' 은 공짜로 참이 된다
    #   (제약을 만족한다고 설정이 전달된 건 아니다).
    chk("C0 재척도가 엔진 입력까지 전달됐다",
        isTRUE(abs(rb$bmax / ra$bmax / REAL_SCALE - 1) < 1e-12),
        sprintf("(bmax 비=%s)", format(rb$bmax / ra$bmax)))
    fa <- ra$f; fb <- rb$f
    chk("C1 pindex FACTORS 가 배수에 불변 (행수)", nrow(fa) == nrow(fb) && nrow(fa) > 0L,
        sprintf("(rows %d vs %d)", nrow(fa), nrow(fb)))
    setorder(fa, Date, Ticker); setorder(fb, Date, Ticker)
    # ★비트 동일을 요구하지 않는다 — uHi/S0_M 은 두 피연산자를 같은 배수로 곱해도
    #   IEEE 배정도에서 마지막 자리가 갈릴 수 있다(실측 max 상대차 7.9e-14).
    #   "레벨에 의존한다" 면 상대차가 O(1) 로 나온다 — 두 자릿수가 아니라 열 자릿수 차이다.
    rel <- max(abs(fa$Score - fb$Score) / pmax(abs(fa$Score), 1e-300))
    chk("C2 pindex Score 가 배수에 불변 (상대차 < 1e-10 = 배정도 반올림 수준)",
        isTRUE(rel < 1e-10) && identical(fa$Ticker, fb$Ticker),
        sprintf("(max 상대차=%.3e)", rel))
    rka <- fa[, .(r = frank(-Score)), by = Date]$r
    rkb <- fb[, .(r = frank(-Score)), by = Date]$r
    chk("C3 횡단면 순위 동일 — 신호가 실제로 쓰는 축이 불변", identical(rka, rkb), "")
  }
}

cat("\n=== 소비자 표면 고정 (새 소비자가 분류 없이 들어오는 것을 잡는다) ===\n")
# ★08_Tests 는 분모에서 뺀다 — 이 파일 자신이 후보가 되어 '자기 참조로 통과' 하는
#   함정을 피한다(픽스처는 소비자가 아니다). 기록과 소비를 가르는 지점이 여기다.
PINNED <- c(
  "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R",
  "02_Infrastructure/data/benchmark_axis.py",
  "02_Infrastructure/data/benchmark_currency_gate.R",
  "02_Infrastructure/data/benchmark_level_axis.R",
  "02_Infrastructure/data/build_cache.R",
  "02_Infrastructure/data/build_index_cache.py",
  "02_Infrastructure/data/cache_registry.json",
  "02_Infrastructure/data/daily_refresh.sh",
  "02_Infrastructure/data/krx_build_rawdata.R",
  "02_Infrastructure/data/naver_benchmark_update.py",
  "02_Infrastructure/data/naver_data_collector.R",
  "02_Infrastructure/data/rawdata_sanitize.R",
  "02_Infrastructure/data/rebuild_benchmark_canonical.py",
  "02_Infrastructure/data/repair_benchmark_level_axis.R",
  "02_Infrastructure/data/repair_benchmark_scale_break_20260727.R",
  "02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R",
  "02_Infrastructure/docs/rules/data_table_shift_convention.md",
  "02_Infrastructure/ml_pipeline/dpl_regime_export.py",
  "02_Infrastructure/ops/morning_briefing.sh",
  "02_Infrastructure/ops/triple_monitor.sh",
  "02_Infrastructure/regime/README.md",
  "02_Infrastructure/regime/ae_regime_backfill.py",
  "02_Infrastructure/regime/ae_seed_sensitivity_probe.py",
  "02_Infrastructure/regime/ktri_v3_builder.R",
  "02_Infrastructure/regime/msm_daily_refit.R",
  "02_Infrastructure/regime/regime_cusum.R",
  "02_Infrastructure/regime/regime_ensemble.R",
  "02_Infrastructure/regime/regime_hmm.R",
  "02_Infrastructure/regime/regime_jump_model.R",
  "02_Infrastructure/regime/regime_vrp.R",
  "02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R",
  "02_Infrastructure/reports/index_factor_beta.R",
  "02_Infrastructure/sanity_checks/bear_date_audit.R",
  "02_Infrastructure/validation/benchmark_source_parity.R",
  "02_Infrastructure/validation/judge_oos_helper.R",
  "02_Infrastructure/validation/pit_enforcement.R",
  "04_Research/strategies/RP_AUTO_2007_08115/engine.R",
  "04_Research/strategies/RP_AUTO_COMBO_combo_1403_8125_2007_081/engine.R",
  "04_Research/strategies/RP_AUTO_COMBO_combo_1403_8125_2007_081/engine.rejected1.R",
  "04_Research/strategies/RP_AUTO_COMBO_combo_2007_08115_2301_09/engine.R",
  "04_Research/strategies/STR_1697_WT009_MEGA05_FF5v2/run_all.R",
  "04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/run_all.R",
  "04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/run_phase4.R",
  "04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/run_phase45.R",
  "04_Research/strategies/STR_1700_WT011_MEGA_06/run_all.R",
  "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/run_all.R",
  "04_Research/strategies/STR_1701_WT011_Iter26_DDThreshold/run_all.R",
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/compute_june_regime.R",
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/run_all.R",
  "04_Research/strategies/WT_D20260511_001_5sleeve_high20pct/run_all.R",
  "04_Research/strategies/WT_D20260511_001_5sleeve_med10pct/run_all.R",
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code/_recompute_alpha_asof.R",
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code/run_all.R",
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code_backup_20260617/run_all.R",
  "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/01_reproducible_code/_recompute_alpha_asof.R",
  "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/01_reproducible_code/run_all.R",
  "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R",
  "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/run_all.R",
  "05_Production/4.Statistical-Technical/4-1.Samsara_Protocol/Samsara_Protocol.R",
  "05_Production/4.Statistical-Technical/4-1.Samsara_Protocol/Step_1_Setting.R",
  "05_Production/4.Statistical-Technical/4-1.Samsara_Protocol/Step_2_Nirvana_Calc.R",
  "05_Production/4.Statistical-Technical/4-1.Samsara_Protocol/Step_4_Placebo_Test.R"
)
# 2026-09-18 실측 분류: 계산이 **절대 레벨**에 의존하는 소비자. 나머지는 전부
# 비율(체인·z·drawdown·rebase-to-1) 또는 표시용이다.
#   ★z-score·drawdown-from-running-max·MA 교차는 전부 비율이라 축 이전에 불변이다 —
#     "레벨을 만진다" 와 "레벨에 의존한다" 는 다른 명제다.
ABS_LEVEL <- c(
  "02_Infrastructure/data/benchmark_axis.py",                   # 정합/이음매 판정 정본(Python)
  "02_Infrastructure/data/rebuild_benchmark_canonical.py",      # 정본 재구축기
  "02_Infrastructure/data/build_cache.R",                       # tail 대 tail 등식(writer 자기검사)
  "02_Infrastructure/data/build_index_cache.py",                # 100 < last200 < 5000 밴드 + writer
  "02_Infrastructure/data/naver_benchmark_update.py",           # 트립와이어(겹치는 날 레벨 대조)
  "02_Infrastructure/data/krx_build_rawdata.R",                 # 타 소스 레벨과의 비
  "02_Infrastructure/data/naver_data_collector.R",              # 종합지수 레벨을 BM_Close 로 기록
  "02_Infrastructure/regime/ktri_v3_builder.R",                 # 레벨을 IKS200 이름으로 CSV 수출
  "02_Infrastructure/regime/msm_daily_refit.R",                 # Price 컬럼으로 parquet 수출
  "02_Infrastructure/regime/regime_jump_model.R",               # Price 컬럼(피처표 carry)
  "05_Production/4.Statistical-Technical/4-1.Samsara_Protocol/Step_2_Nirvana_Calc.R"  # sum(BM_Close) md5
)
scan_dirs <- c("02_Infrastructure", "05_Production", "04_Research/strategies")
found <- character(0)
for (dd in scan_dirs) {
  base <- file.path(ROOT, dd)
  if (!dir.exists(base)) next
  fs <- list.files(base, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  # 텍스트 소스만 — 분모를 확장자로 선언하고 센다(세기 전에 범위를 선언할 것).
  fs <- fs[grepl("[.](R|r|py|sh|json|md|yml|yaml|sql|txt)$", fs)]
  sz <- file.info(fs)$size
  fs <- fs[is.na(sz) | sz < 4e6]
  for (f in fs) {
    txt <- tryCatch(readLines(f, warn = FALSE, n = -1L), error = function(e) character(0))
    if (length(txt) && any(grepl("BM_Close", txt, fixed = TRUE)))
      found <- c(found, sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", f)))
  }
}
found <- sort(unique(found))
newcomers <- setdiff(found, PINNED)
gone      <- setdiff(PINNED, found)
chk(sprintf("S1 새 BM_Close 소비자 0건 (실측 %d파일)", length(found)),
    length(newcomers) == 0L,
    sprintf("(미분류 신규: %s)", paste(head(newcomers, 8), collapse = ", ")))
chk("S2 절대-레벨 소비자 목록이 표면 안에 있다",
    all(ABS_LEVEL %in% PINNED), "")
if (length(gone)) cat(sprintf("  note  사라진 소비자 %d건(실패 아님): %s\n",
                              length(gone), paste(head(gone, 5), collapse = ", ")))

cat("\n=== 실데이터 (상태-불가지 — 수리 전후 어느 쪽에서도 성립해야 한다) ===\n")
BM_REAL <- file.path(ROOT, ".cache/benchmark.parquet")
if (!file.exists(BM_REAL)) {
  skip("L1 실데이터 판정 일치", "benchmark.parquet 부재")
} else {
  bmr <- as.data.table(read_parquet(BM_REAL))
  ref <- bench_level_reference(ROOT)
  cfg <- bench_level_config(ROOT)
  lv  <- bench_level_axis_check(bmr, ref, tol = cfg$BENCH_LEVEL_TOL,
                                seam_tol = cfg$BENCH_LEVEL_SEAM_TOL,
                                min_sessions = cfg$BENCH_LEVEL_MIN_SESSIONS,
                                window_sessions = cfg$BENCH_LEVEL_WINDOW_SESSIONS)
  cat(sprintf("  실측: status=%s  detail=%s\n", lv$status, lv$detail))
  if (identical(lv$status, "no_measure")) {
    skip("L1 실데이터 판정 일치", lv$detail)
  } else {
    # ★상태-불가지: "지금 어긋나 있다" 가 아니라 **판정이 실측값과 맞물리는가**를 잰다.
    #   두 축을 모두 통과해야 ok 다 — 정합만 보면 이음매가 있는 파일에서 오판한다.
    ok_dev  <- isTRUE(lv$max_dev <= cfg$BENCH_LEVEL_TOL)
    ok_seam <- !is.finite(lv$max_seam) || isTRUE(lv$max_seam <= cfg$BENCH_LEVEL_SEAM_TOL)
    expect <- if (ok_dev && ok_seam) "ok" else "violation"
    chk("L1 게이트 판정이 실측값과 일치 (재구축 전후 어느 쪽에서도 성립)",
        identical(lv$status, expect),
        sprintf("(status=%s expect=%s dev=%.3e seam=%.3e)",
                lv$status, expect, lv$max_dev, lv$max_seam))
    # 재척도(진단 보조)가 실데이터에서도 BM_Ret 을 안 건드린다 — 운영 파일에 쓰지 않는다.
    rs <- bench_level_rescale(copy(bmr), if (is.finite(lv$scale)) lv$scale else 1)
    chk("L2 실데이터 재척도 후 BM_Ret 비트 동일", identical(rs$BM_Ret, bmr$BM_Ret), "")
    # ★L3: 재척도는 **정합 축만** 고친다(이음매는 상수배로 안 없어진다). 그것을 못박는다.
    lv3 <- bench_level_axis_check(rs, ref, tol = cfg$BENCH_LEVEL_TOL,
                                  seam_tol = cfg$BENCH_LEVEL_SEAM_TOL,
                                  min_sessions = cfg$BENCH_LEVEL_MIN_SESSIONS,
                                  window_sessions = cfg$BENCH_LEVEL_WINDOW_SESSIONS)
    chk("L3 상수 재척도로 정합 편차는 줄지만 이음매는 그대로 (재구축이 필요한 이유)",
        isTRUE(lv3$max_dev <= max(lv$max_dev, cfg$BENCH_LEVEL_TOL)) &&
          isTRUE(all.equal(lv3$max_seam, lv$max_seam)),
        sprintf("(dev %.3e→%.3e, seam %.3e→%.3e)",
                lv$max_dev, lv3$max_dev, lv$max_seam, lv3$max_seam))
    # ★manifest 가 배율을 선언하지 않는다 — 승계 가능한 배율은 재발의 씨앗이었다.
    mfp <- file.path(ROOT, ".cache/benchmark_axis.json")
    if (!file.exists(mfp)) {
      skip("L4 manifest 규약", "manifest 부재 (재구축 전)")
    } else {
      mj <- jsonlite::fromJSON(mfp, simplifyVector = TRUE)
      chk("L4 manifest: unit=index_points 이고 scale 필드가 없다",
          identical(as.character(mj$unit), "index_points") && is.null(mj$scale),
          sprintf("(unit=%s scale=%s)", mj$unit, if (is.null(mj$scale)) "없음" else mj$scale))
    }
  }
}

unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== test_benchmark_level_axis: %d PASS / %d FAIL / %d SKIP ===\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"benchmark_level_axis","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n',
            PASS, FAIL, SKIP, PASS + FAIL + SKIP))
if (FAIL > 0L) quit(status = 1L)
