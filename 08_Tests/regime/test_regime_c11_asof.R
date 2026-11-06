# test_regime_c11_asof.R — PIT C11 수리 1단계 S3(국면): 해외 시계열 가용시점 결합 검사 (2026-09-24 신설)
#
# 지키는 것 (판정서 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md ①·②·⑤-3·⑤-5):
#   V-10 regime_engine_daily 이름 충돌(출력 VIX_z_smooth = 같은 날짜 값) · V-11 주간·월간 축 공표 전 사용 ·
#   V-05 regime_signal 일간 FRED_MRS 같은 날짜 병합 · V-14 macro_regime 월말 행의 공표 전 값 ·
#   1-3 잠재 위반(merge_regime_to_signals lag 없음 · compute_bcs_daily 같은 날짜 + 전표본 순위 C1) ·
#   ⑤-3 엔진 자체검증(regime_daily_backtest_check)이 **출력 열**을 보고 누출을 잡는가.
#
# ★양방향. 양성 대조(수리판이 판정서 실례·독립 기준선과 맞는가)만으로는 부족하다 — 이름 충돌·라벨 결합·
#   계산식 lead·DEXKOUS 재유입·같은 날짜 결합·전표본 순위를 주입했을 때 **빨개지는가**를 함께 잰다.
#   (pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다)
#
# 축:
#   A 판정서 실례(실데이터 사본): VIX 한국 2026-08-31 = 미국 08-28(14.43) · Claims 2020-03-23 = ICSA 03-14 라벨,
#     03-21 라벨은 03-27부터 · NFCI +6 · STLFSI4 +7 · UMCSENT M+2 · HY d+2 · KRW = ECOS · 전 이력 가용일 위반 0
#     (S0 판정기 fred_join_violations) + 판정기 양성 대조(라벨+1일 결합은 위반으로 잡힌다)
#   B 엔진 E2E: 스키마 불변 · 한국 거래일 전부 · 자체검증 PASS(판별력 >0) · Claims_z 도약일 = 03-27(구판 03-23)
#   C 위반 주입(돌연변이 red): M1 이름 충돌 재현 · M2 라벨 결합(관측일+1일) · M3 계산식 lead · M4 DEXKOUS 재유입
#   D regime_signal 일간: 척추 = 한국 거래일 · FRED_MRS = 독립 기준선(둘 다 사전 조건 달력 최신일 ≥ 벤치 최신일 —
#     어긋나면 SKIP·사유) · V-05 상관 부호 · 돌연변이(같은 날짜) red
#     + MSM as-of 입력 계약(2026-11-06 · 아래): D0 as-of 로더 경유 빌드 · D5 첫 행 = as-of 첫날(D1 A) · D5b 판별 사본 ·
#       D6 msm_estimator 열 · D6b 속성 생존(메모리 · parquet 왕복 = Gate M 판독식) · D7 스키마 · Category_basis ·
#       D8 월간 빌드(첫 달 · 표식 · fw_* 없음 · Category_basis) · DM 돌연변이(D1 절단 두 줄 삭제 사본 — 소스 텍스트
#       치환) → D5b · D8a red
#   E macro_regime: Asof_Date · 계열값 = 독립 기준선 · 2026-08 실례 · ECOS 원/달러 · CPI 날짜 기준 12개월(합성) ·
#     merge_regime_to_signals Asof 결합·fail-closed · 누출 구성(구판식 월내 마지막 관측) red
#   F BCS: 확장창 백분위·분위 접두 불변(전표본판 red) · VIX 가용시점(D 와 같은 달력 사전 조건) ·
#     merge_regime_with_bcs 월중 날짜(구판 YM red)
#   G merge_daily_regime(mode = "exposure_return") = 직전 한국 거래일 행
# 쓰기: tempdir() 만. 운영 .cache·원장·로그에 쓰지 않는다(운영 캐시는 읽기 전용으로 복사해 쓴다).
# 실행: Rscript 08_Tests/regime/test_regime_c11_asof.R   (R_ENVIRON_USER=<빈 파일> 권장)
#
# ★2026-11-06 MSM as-of 전환(결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017 D1 A · D4 B · 적대 검토 #1·#8·#13·#17):
#   regime_signal.R 의 MSM 로더는 이제 .cache/msm_asof_daily.parquet 만 읽고 없음 · 추정기 표식 ≠ asof_yearly:v1 ·
#   벤치보다 낡음이면 stop 한다(폴백 없음). 그래서 사본 목록(NEED)이 구 msm_daily_latest 대신 as-of 경로를
#   벤치와 같은 시점에 복사하고(낡음 검사 = 사본끼리 대조), HAVE_REAL 도 as-of 경로 존재로 정한다.
#   사전 조건이 어긋나면(운영 리프레시 중간 상태) 사유(두 날짜 · 운영 경로)를 SKIP 으로 남긴다 — 조용히 넘기거나
#   판정 범위를 줄여 통과시키지 않는다: as-of 사본 < 벤치 사본 → 기본 경로(낡음 검사 포함) 미측정 SKIP 후 D 절은
#   경로 덮어쓰기(options(qvest.msm_asof_path) · 낡음 검사만 생략)로 잰다 · 거래일 캘린더 사본 < 벤치 사본 → 달력 기반
#   정확 대조 축 D1(척추) · D2(FRED_MRS 기준선) · F4(BCS VIX) SKIP — 기준선 fred_avail_date 는 달력 밖 = NA, 엔진
#   fred_asof_join(extend_calendar=TRUE)은 달력 끝 뒤 평일을 붙여 끝 구간이 계약상 갈린다(가짜 루트 양성 대조로 F4 실측).
#   기대값 asof_yearly:v1 은 계약값(결정 · Gate M 리터럴)으로 이 시험이 따로 적는다 — 로더 상수를 기대값으로 쓰면
#   그 상수가 바뀌는 회귀를 못 잡는다. 첫날 · 첫 달은 as-of 사본을 이 시험이 직접 읽어 정한다(특정 날짜 리터럴 없음).
#   현 자료에선 KTRI(2012-09~)가 as-of 첫날(2004-01-02) 뒤에 시작해 실데이터 일간 빌드의 D1 절단이 지우는 행이 0 이다
#   → D5 만으론 절단이 빠져도 초록이다. 그래서 as-of 를 KTRI 시작 다음 해부터로 자른 판별 사본(D5b)과 FRED 층이 앞서는
#   월간 빌드(D8a)로 재고, DM 이 절단 삭제 사본에서 그 둘이 실제로 빨개지는지 매 실행 확인한다.
#   시험 전체를 돌연변이 사본으로 돌릴 때: C11S3_SRC_SIGNAL=<사본 경로> (정상 실행 아님 — 배너 · 요약 JSON 에 경로 기록).

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(arrow) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))
SRC_ENGINE    <- file.path(ROOT, "02_Infrastructure/regime/regime_engine_daily.R")
SRC_SIGNAL_DEFAULT <- file.path(ROOT, "02_Infrastructure/regime/regime_signal.R")
SRC_SIGNAL    <- gsub("\\\\", "/", Sys.getenv("C11S3_SRC_SIGNAL", SRC_SIGNAL_DEFAULT))   # 돌연변이 대조 실행 전용 덮어쓰기
SRC_OVERRIDDEN <- !identical(SRC_SIGNAL, SRC_SIGNAL_DEFAULT)
SRC_COLLECTOR <- file.path(ROOT, "02_Infrastructure/data/data_collector_fred.R")
HELPER        <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(axis, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  SKIP  %s — %s [%s]\n", axis, reason, missing))
}
quiet <- function(expr) { v <- NULL; invisible(capture.output(v <- suppressWarnings(force(expr)))); v }
raises <- function(expr) inherits(tryCatch({ quiet(expr); NULL }, error = function(e) e), "error")

TD <- gsub("\\\\", "/", file.path(tempdir(), paste0("c11s3_", as.integer(runif(1, 1e6, 9e6)))))   # 슬래시 경로(옵션 · 로그 일관)
for (d in c("root", ".cache", "research/regime_comparison/output")) dir.create(file.path(TD, d), recursive = TRUE, showWarnings = FALSE)
writeLines("FRED_API_KEY=TEST_ONLY_DUMMY_KEY_000", file.path(TD, "root", ".env"))   # 수집기 source 용(네트워크 호출 없음)

cat("=== 전제: 소스·도우미 존재 · 실데이터 읽기 전용 사본 ===\n")
if (SRC_OVERRIDDEN) cat(sprintf("  ★SRC_SIGNAL 덮어쓰기(C11S3_SRC_SIGNAL — 돌연변이 대조 실행 · 정상 실행 아님): %s\n", SRC_SIGNAL))
for (p in c(SRC_ENGINE, SRC_SIGNAL, SRC_COLLECTOR, HELPER)) chk(paste("존재", basename(p)), file.exists(p), p)
# ★2026-11-06: 구 msm_daily_latest(전 표본 MLE 모수 · C1) 대신 as-of 경로. 벤치와 한 번의 복사로 같은 시점 사본을 만든다 —
#   로더의 낡음 검사(as-of 최신일 < 벤치 최신일 = stop)가 사본끼리 대조되게. HAVE_REAL 도 이 목록(= as-of 경로 포함)으로 정한다.
NEED <- c("macro_fred.parquet", "fred_macro_wide.parquet", "ecos_krw_usd.parquet",
          "trading_calendar.parquet", "msm_asof_daily.parquet", "benchmark.parquet")
src_cache <- file.path(DATA_ROOT, ".cache", NEED)
HAVE_REAL <- all(file.exists(src_cache))
if (HAVE_REAL) invisible(file.copy(src_cache, file.path(TD, ".cache", NEED), overwrite = TRUE))
src_of <- function(f) src_cache[match(f, NEED)]                     # 사본의 운영 원본 경로(SKIP 사유 기록용)
DRV <- file.path(DATA_ROOT, "04_Research/regime_comparison/output/derivatives_indicators_daily.parquet")
HAVE_DRV <- HAVE_REAL && file.exists(DRV)
if (HAVE_DRV) invisible(file.copy(DRV, file.path(TD, "research/regime_comparison/output", basename(DRV))))
KTRI <- file.path(DATA_ROOT, "04_Research/regime_comparison/output/ktri_v3_signals.csv")
if (file.exists(KTRI)) invisible(file.copy(KTRI, file.path(TD, "research/regime_comparison/output", basename(KTRI))))
# 월간 load_ktri_signal 은 PROJECT_ROOT/04_Research/… 를 본다(일간은 RESEARCH_OUTPUT) — 운영에선 같은 파일이라 두 자리에 같은 사본
KTRI_ROOT_DIR <- file.path(TD, "root/04_Research/regime_comparison/output")
if (file.exists(KTRI)) { dir.create(KTRI_ROOT_DIR, recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(KTRI, file.path(KTRI_ROOT_DIR, basename(KTRI)))) }

# 전역 = 격리 경로 (config.R 을 source 하지 않는다 — 운영 경로가 섞이지 않게)
PROJECT_ROOT <- file.path(TD, "root"); FUNC_PATH <- file.path(ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(TD, ".cache"); RESEARCH_OUTPUT <- file.path(TD, "research")
FRED_MACRO_CACHE <- file.path(CACHE_DIR, "macro_fred.parquet")
invisible(quiet(source(HELPER))); options(fred_avail.root = ROOT)
invisible(quiet(source(SRC_ENGINE))); invisible(quiet(source(SRC_SIGNAL))); invisible(quiet(source(SRC_COLLECTOR)))
chk("격리: 엔진 캐시 경로가 tempdir", startsWith(REGIME_DAILY_CACHE, TD), REGIME_DAILY_CACHE)
chk("격리: macro_regime 경로가 tempdir", startsWith(FRED_REGIME_CACHE, TD), FRED_REGIME_CACHE)

# 독립 가용시점 선택(테스트 자체 구현 — 엔진·신호·수집기 코드를 쓰지 않는다): 가용일 ≤ D 중 관측일 최대
identical_d <- function(a, b) length(a) == 1L && length(b) == 1L && !is.na(a) && !is.na(b) &&
  as.integer(as.Date(a)) == as.integer(as.Date(b))
pick <- function(dates, obs_date, avail, value) {
  ok <- !is.na(avail) & !is.na(obs_date) & !is.na(value)
  a <- as.integer(avail[ok]); o <- as.integer(obs_date[ok]); v <- value[ok]
  ord <- order(a, o); a <- a[ord]; o <- o[ord]; v <- v[ord]
  best <- cummax(o); k <- findInterval(as.integer(as.Date(dates)), a)
  idx <- rep(NA_integer_, length(dates)); idx[k > 0] <- match(best[k[k > 0]], o)
  list(value = v[idx], obs = as.Date(o[idx]))
}

# ── MSM as-of 입력 계약 판정(2026-11-06) — 정상 빌드(D5b·D8a)와 돌연변이 사본(DM)이 **같은 함수**로 판정된다 ──
# D1 A 일간: 첫 행 = as-of 첫날 · MSM 결측 행 0(절단이 없으면 as-of 앞 척추 행이 MSM 결측으로 남는다)
d1_daily_ok <- function(S, first) is.data.frame(S) && nrow(S) > 0L && identical_d(min(S$Date), first) &&
  !anyNA(S$MSM_Crisis_Prob)
# D1 A 월간: 첫 달 = as-of 첫 달
d1_month_ok <- function(S, first_ym) is.data.frame(S) && nrow(S) > 0L && identical(min(as.character(S$YM)), first_ym)
first_of <- function(S, col) if (is.data.frame(S) && nrow(S) > 0L) format(min(S[[col]])) else "빌드 없음"
# Gate M(run_pg2_rebalance_full.sh) 판독식 그대로: parquet 을 읽어 열 고유값 + 파일 속성(attr) — 표식이 왕복에서 살아남는가
gate_m_read <- function(p) {
  x <- tryCatch(arrow::read_parquet(p, mmap = FALSE), error = function(e) NULL)
  if (is.null(x)) return(list(col = "판독 실패", at = "판독 실패"))
  list(col = unique(as.character(x[["msm_estimator"]])), at = as.character(attr(x, "msm_estimator")))
}
stamp_ok <- function(S, g, est) identical(as.character(attr(S, "msm_estimator")), est) && identical(g$col, est) && identical(g$at, est)
stamp_detail <- function(S, g) sprintf("(메모리 attr %s · 왕복 열 %s · 왕복 attr %s)", paste(attr(S, "msm_estimator"), collapse = ","),
                                       paste(g$col, collapse = ","), paste(g$at, collapse = ","))
# Category_basis 독립 판독(5-15 MSM 단락 규칙 — classify_regime_category 를 쓰지 않는다): MSM ≥ 0.9 → CRISIS 는 점수 분류에
#   없는 라벨이라 언제나 msm_override · MSM < 0.7(또는 결측)이면 단락이 없으므로 score · 그 사이는 점수에 달려 판정하지 않는다
basis_ok <- function(S, need_hi) {
  if (!("Category_basis" %in% names(S))) return(FALSE)
  p <- S$MSM_Crisis_Prob; b <- as.character(S$Category_basis)
  hi <- !is.na(p) & p >= 0.9; lo <- is.na(p) | p < 0.7
  !anyNA(b) && all(b %in% c("score", "msm_override")) && (!need_hi || any(hi)) &&
    all(b[hi] == "msm_override") && all(b[lo] == "score")
}

if (!HAVE_REAL) {
  skip("A~E·F3·G", "실데이터 캐시 부재 — 실데이터 축 미측정", paste(src_cache[!file.exists(src_cache)], collapse = " | "))
} else {
  CAL <- fred_kr_calendar(file.path(CACHE_DIR, "trading_calendar.parquet"))
  MF  <- as.data.table(read_parquet(FRED_MACRO_CACHE)); MF[, Date := as.Date(Date)]
  ECO <- as.data.table(read_parquet(file.path(CACHE_DIR, "ecos_krw_usd.parquet"))); ECO[, Date := as.Date(Date)]
  sval <- function(sid, d) MF[Series_ID == sid & Date == as.Date(d), Value]

  # ═══ A. 판정서 실례 — 엔진 격자 감사(audit): 어느 관측을 어느 결정일에 썼나 ═══
  cat("\n=== A. 판정서 실례 (엔진 가용시점 격자) ===\n")
  G <- quiet(.load_fred_daily_grid())
  AU <- G$audit
  used <- function(cl, d) { x <- AU[col == cl & Date == as.Date(d), obs_date]   # Date 저장형(int/double) 무관 비교
    if (length(x) == 1L && !is.na(x)) as.Date(as.integer(x)) else as.Date(NA) }
  chk("A1 VIX 한국 2026-08-31 = 미국 08-28 (V-08 PIT 값)", identical_d(used("VIX", "2026-08-31"), as.Date("2026-08-28")))
  chk("A1b 그 값 = 14.43", isTRUE(all.equal(G$data[Date == as.Date("2026-08-31"), VIX], 14.43)))
  chk("A2 미국 08-31 VIX 는 한국 09-01 부터", identical_d(used("VIX", "2026-09-01"), as.Date("2026-08-31")))
  chk("A3 Claims 2020-03-23 = ICSA 03-14 라벨 (03-21 라벨은 03-26 공표 — V-11)",
      identical_d(used("Init_Claims", "2020-03-23"), as.Date("2020-03-14")))
  chk("A3b ICSA 03-21 라벨은 한국 03-26 에도 미사용, 03-27 부터",
      identical_d(used("Init_Claims", "2020-03-26"), as.Date("2020-03-14")) &&
      identical_d(used("Init_Claims", "2020-03-27"), as.Date("2020-03-21")))
  chk("A4 NFCI 03-20 라벨 = 한국 03-26(+6)부터", identical_d(used("Chi_Fin_Cond", "2020-03-25"), as.Date("2020-03-13")) &&
      identical_d(used("Chi_Fin_Cond", "2020-03-26"), as.Date("2020-03-20")))
  chk("A5 STLFSI4 03-20 라벨 = 한국 03-27(+7)부터", identical_d(used("StL_Fin_Stress", "2020-03-26"), as.Date("2020-03-13")) &&
      identical_d(used("StL_Fin_Stress", "2020-03-27"), as.Date("2020-03-20")))
  chk("A6 UMCSENT 한국 2026-08-31 = 06월분(M+2월 5일 규칙)", identical_d(used("UMich_Sentiment", "2026-08-31"), as.Date("2026-06-01")))
  hy_last <- max(MF[Series_ID == "BAMLH0A0HYM2", Date])
  d_hy <- CAL[CAL > hy_last][1]
  if (!is.na(d_hy)) chk(sprintf("A7 HY 마지막 관측 %s 은 다음 한국 거래일 %s 에 미사용(d+2)", hy_last, d_hy),
                        !is.na(used("HY_Spread", d_hy)) && used("HY_Spread", d_hy) < hy_last) else
    skip("A7_hy_d2", "달력이 HY 마지막 관측일 뒤로 없음 — 미측정", format(hy_last))
  kd <- as.Date("2026-08-31")
  chk("A8 KRW 축 원천 = ECOS 731Y001(lag 0) · DEXKOUS 아님",
      isTRUE(all.equal(G$data[Date == kd, KRW_USD], ECO[Date == kd, KRW_USD])) &&
        !isTRUE(all.equal(G$data[Date == kd, KRW_USD], sval("DEXKOUS", "2026-08-28"))))
  nviol <- 0L; nrow_all <- 0L
  for (i in seq_len(nrow(REGIME_DAILY_AXES))) {
    ax <- REGIME_DAILY_AXES[i]; x <- AU[col == ax$col & !is.na(obs_date)]
    nrow_all <- nrow_all + nrow(x)
    nviol <- nviol + nrow(fred_join_violations(x$Date, x$obs_date, ax$rule_id, "decision_close", kr_calendar = CAL))
  }
  chk(sprintf("A9 전 이력 9축 결합 %d쌍 — S0 판정기 기준 가용일 위반 0", nrow_all), nviol == 0L, sprintf("(위반 %d)", nviol))
  # 판정기 양성 대조: 구판식 라벨+1일 결합(관측일 < 결정일)은 주간 계열에서 위반으로 잡혀야 한다
  cl_obs <- MF[Series_ID == "ICSA", .(Date, Value)][order(Date)]
  g_dates <- AU[col == "Init_Claims", Date]
  lk <- pick(g_dates, cl_obs$Date, cl_obs$Date + 1L, cl_obs$Value)
  nv_leak <- nrow(fred_join_violations(g_dates[!is.na(lk$obs)], lk$obs[!is.na(lk$obs)], "ICSA", "decision_close", kr_calendar = CAL))
  chk("A10 판정기 양성 대조: 라벨+1일 결합 ICSA 는 위반으로 잡힌다", nv_leak > 1000L, sprintf("(위반 %d)", nv_leak))

  # ═══ B. 엔진 E2E ═══
  cat("\n=== B. 엔진 E2E (build_daily_regime + 자체검증) ===\n")
  RES <- quiet(build_daily_regime())
  EXP_COLS <- c("Date", "MRS", "exposure", "n_axes_firing", "VIX_z_smooth", "HY_z_smooth", "TS_z_smooth",
                "BBB_z_smooth", "KRW_z_smooth", "FinStress_z_smooth", "NFCI_z_smooth", "Claims_z_smooth",
                "Sentiment_z_smooth", "ax1_VIX", "ax2_HY", "ax3_TS", "ax4_BBB", "ax5_KRW", "ax6_FinStress",
                "ax7_NFCI", "ax8_Claims", "ax9_Sentiment")
  # r1(표식 계약 통일 · 통합 검증 BLOCKING): 구판 22열은 이름·순서 그대로, 뒤에 계약 2열(avail_date·c11_regime_key)만 붙는다
  chk("B1 출력 스키마 = 구판 22열(이름·순서) + 끝에 표식 계약 2열만", identical(names(RES)[seq_along(EXP_COLS)], EXP_COLS) &&
        identical(setdiff(names(RES), EXP_COLS), c("avail_date", "c11_regime_key")), paste(names(RES), collapse = ","))
  CUR_KEY <- fred_avail_rules_meta()$regime_key
  chk("B1c 표식 계약: avail_date = Date 형·행 날짜(형태 a) · c11_regime_key = 현행 규칙 키 · 파일 속성 동일",
      inherits(RES$avail_date, "Date") && identical(as.integer(RES$avail_date), as.integer(as.Date(RES$Date))) &&
        all(RES$c11_regime_key == CUR_KEY) &&
        identical(tryCatch(arrow::read_parquet(REGIME_DAILY_CACHE, as_data_frame = FALSE)$metadata$r$attributes$c11_avail_regime_key,
                           error = function(e) NULL), CUR_KEY))
  chk("B1b 형식: Date=Date · n_axes_firing=integer · 나머지 double",
      inherits(RES$Date, "Date") && is.integer(RES$n_axes_firing) &&
        all(vapply(EXP_COLS[-c(1, 4)], function(cl) is.double(RES[[cl]]), TRUE)))
  kr_in <- CAL[CAL >= min(RES$Date) & CAL <= max(RES$Date)]
  chk("B2 범위 안 한국 거래일 전부 행 존재 · MRS 결측 0", all(kr_in %in% RES$Date) && !anyNA(RES$MRS),
      sprintf("(누락 %d)", sum(!(kr_in %in% RES$Date))))
  CK <- quiet(regime_daily_backtest_check(regime = RES, verbose = FALSE))
  chk("B3 자체검증 PASS(기준선 불일치 0 · 누출판 일치 0 · 접두 불변 · 격자 밖 행 잇기)", isTRUE(CK$pass))
  pc <- CK$per_col
  chk("B3b 판별력: VIX·Claims·NFCI·FinStress·Sentiment z 열에서 기준선과 누출판이 갈리는 날 > 0",
      all(pc[col %in% c("VIX_z_smooth", "Claims_z_smooth", "NFCI_z_smooth", "FinStress_z_smooth", "Sentiment_z_smooth"),
             disc_same > 0 & disc_lag1 > 0]))
  chk("B4 V-10: 출력 VIX_z_smooth 가 같은 날짜 판과 일치하는 날 0 (갈리는 날 중)",
      pc[col == "VIX_z_smooth", hit_same] == 0L && pc[col == "VIX_z_smooth", disc_same] > 1000L)
  w <- RES[Date >= as.Date("2020-03-16") & Date <= as.Date("2020-04-03") & Date %in% CAL, .(Date, z = Claims_z_smooth)]
  w[, dz := z - shift(z)]
  jd <- w[!is.na(dz) & dz > 1, Date][1]
  chk("B5 V-11: 2020-03 Claims_z 가 하루에 1 넘게 뛴 첫날 = 03-27(03-26 공표 다음 한국 거래일 · 구판 03-23)",
      isTRUE(as.integer(jd) == as.integer(as.Date("2020-03-27"))), format(jd))
  chk("B6 측정 epoch 표식(c11_avail_regime_key)이 parquet 에 남는다",
      grepl("^c11_avail:", attr(read_parquet(REGIME_DAILY_CACHE), "c11_avail_regime_key") %||% ""))

  # ═══ C. 위반 주입 — 자체검증이 빨개지는가 ═══
  cat("\n=== C. 위반 주입(돌연변이 red) ===\n")
  inp <- .re_check_inputs(CAL); kg <- .re_compute_grid(inp$d0, max(CAL))
  # M1 V-10 재현: 출력 VIX_z_smooth 자리에 같은 날짜 판 값을 넣는다
  sd_z <- .re_zsmooth(.re_values_from(kg, inp$obs, "same_day")$values)
  M1 <- copy(RES); M1[data.table(Date = kg, v = sd_z$VIX_z_smooth), on = "Date", VIX_z_smooth := i.v]
  c1 <- quiet(regime_daily_backtest_check(regime = M1, verbose = FALSE))
  chk("C1 M1(이름 충돌 재현 — 같은 날짜 VIX_z) → FAIL · VIX 누출판 일치 > 0",
      !isTRUE(c1$pass) && c1$per_col[col == "VIX_z_smooth", hit_same] > 0L)
  # M2 라벨 결합: fred_asof_join 을 '관측일 다음 역일부터'(구판 1행 lag 식)로 바꿔치기
  .orig_join <- fred_asof_join
  fred_asof_join <- function(kr_dates, series_dt, series_id, mode = "decision_close", kr_calendar = NULL,
                             rules = NULL, date_col = "Date", value_col = "Value", extend_calendar = TRUE) {
    sd <- as.data.table(series_dt); p <- pick(kr_dates, as.Date(sd[[date_col]]), as.Date(sd[[date_col]]) + 1L, sd[[value_col]])
    data.table(kr_date = as.Date(kr_dates), value = p$value, obs_date = p$obs, avail_date = p$obs + 1L)
  }
  RM2 <- tryCatch(quiet(build_daily_regime(verify = FALSE)), error = function(e) NULL)
  refuse2 <- raises(build_daily_regime(verify = TRUE))
  fred_asof_join <- .orig_join; rm(.orig_join)
  c2 <- if (is.null(RM2)) NULL else quiet(regime_daily_backtest_check(regime = RM2, verbose = FALSE))
  chk("C2 M2(주간·월간 라벨 결합 = V-11 기전) → FAIL · Claims/NFCI 기준선 불일치 > 0",
      !is.null(c2) && !isTRUE(c2$pass) && c2$per_col[col == "Claims_z_smooth", mism_ref] > 0L &&
        c2$per_col[col == "NFCI_z_smooth", mism_ref] > 0L)
  chk("C2b M2 를 기본 빌드(verify=TRUE)로 돌리면 캐시 기록 전에 거부(fail-closed)", isTRUE(refuse2))
  # M3 계산식 lead: z 평활에 미래 1행을 섞는다(시간축 선택은 정상) → 접두 불변이 잡아야 한다
  .orig_zs <- .re_zsmooth
  .re_zsmooth <- function(values_dt, z_lookback = 756L, smooth_window = 20L) {
    r <- .orig_zs(values_dt, z_lookback, smooth_window)
    for (cl in setdiff(names(r), "Date")) set(r, j = cl, value = shift(r[[cl]], 1L, type = "lead"))
    r
  }
  RM3 <- quiet(build_daily_regime(verify = FALSE)); c3 <- quiet(regime_daily_backtest_check(regime = RM3, verbose = FALSE))
  refuse3 <- raises(build_daily_regime(verify = TRUE))
  .re_zsmooth <- .orig_zs; rm(.orig_zs)
  chk("C3 M3(계산식 lead) → FAIL · 접두 불변 불일치 > 0 (기준선도 같은 식이라 전열 대조만으론 못 잡는 축)",
      !isTRUE(c3$pass) && any(c3$prefix$n_mism > 0L))
  chk("C3b M3 기본 빌드 거부(fail-closed)", isTRUE(refuse3))
  # M4 DEXKOUS 재유입: 엔진의 원/달러 로더가 FRED DEXKOUS 를 돌려준다
  .orig_ek <- .re_load_ecos_krw
  .re_load_ecos_krw <- function() unique(MF[Series_ID == "DEXKOUS", .(Date, Value)])
  RM4 <- quiet(build_daily_regime(verify = FALSE)); c4 <- quiet(regime_daily_backtest_check(regime = RM4, verbose = FALSE))
  refuse4 <- raises(build_daily_regime(verify = TRUE))
  .re_load_ecos_krw <- .orig_ek; rm(.orig_ek)
  chk("C4 M4(DEXKOUS 재유입) → FAIL · KRW_z 기준선 불일치 > 0",
      !isTRUE(c4$pass) && c4$per_col[col == "KRW_z_smooth", mism_ref] > 0L)
  chk("C4b M4 기본 빌드 거부(fail-closed)", isTRUE(refuse4))
  .orig_ek <- .re_load_ecos_krw
  .re_load_ecos_krw <- function() unique(MF[Series_ID == "DEXKOUS", .(Date, Value)])
  mt_before <- file.mtime(REGIME_DAILY_CACHE); Sys.sleep(1.1)
  invisible(raises(build_daily_regime()))
  .re_load_ecos_krw <- .orig_ek; rm(.orig_ek)
  chk("C4c 거부된 빌드는 캐시 파일을 건드리지 않는다", identical(file.mtime(REGIME_DAILY_CACHE), mt_before))
  RES2 <- quiet(build_daily_regime())
  chk("C5 돌연변이 복구 뒤 재빌드 = 원 결과(주입이 새지 않았다)", isTRUE(all.equal(RES2, RES, check.attributes = FALSE)))

  # ═══ D. regime_signal 일간 + MSM as-of 입력 계약 ═══
  cat("\n=== D. regime_signal 일간 FRED_MRS (V-05) · MSM as-of 입력 계약(2026-11-06) ===\n")
  FW <- as.data.table(read_parquet(file.path(CACHE_DIR, "fred_macro_wide.parquet"))); FW[, Date := as.Date(Date)]
  FCOLS <- c("VIX", "HY_Spread", "Term_Spread", "Fed_Funds_Rate", "BBB_Spread", "Chi_Fin_Cond")
  ref_mrs <- function(dates) {
    v <- data.table(Date = dates)
    for (cl in intersect(FCOLS, names(FW))) {
      o <- FW[!is.na(get(cl)), .(Date, Value = get(cl))]
      av <- fred_avail_date(cl, o$Date, kr_calendar = CAL)
      v[, (cl) := pick(dates, o$Date, av, o$Value)$value]
    }
    compute_fred_mrs_daily(v)
  }
  vcor <- function(u) {
    u <- u[Date %in% CAL & Date >= as.Date("2005-01-01")][order(Date)]
    u[, dF := FRED_MRS - shift(FRED_MRS)]
    vv <- FW[!is.na(VIX), .(Date, VIX)][order(Date)]; vv[, dV := VIX - shift(VIX)]
    same <- vv$dV[match(u$Date, vv$Date)]
    prev <- vv[data.table(Date = u$Date - 1L), on = "Date", roll = TRUE]$dV
    c(same = cor(u$dF, same, use = "complete.obs"), prev = cor(u$dF, prev, use = "complete.obs"))
  }
  # ── D 사전 판독(2026-11-06) — 사본을 이 시험이 직접 읽는다(regime_signal 코드를 쓰지 않는 독립 판독) ──
  #   EST = 계약값(결정 MSM-ASOF-SWITCH-20261017 · Gate M 리터럴 · 생산자 msm_asof.R::MSMA_ESTIMATOR). 로더 상수
  #   MSM_ESTIMATOR_EXPECTED 를 기대값으로 쓰지 않는다 — 그 상수가 바뀌는 회귀를 잡아야 하므로.
  EST <- "asof_yearly:v1"
  ASOF_P <- file.path(CACHE_DIR, "msm_asof_daily.parquet")
  ASOF_TB <- read_parquet(ASOF_P, as_data_frame = FALSE, mmap = FALSE)
  ASOF_EST <- paste(as.character(ASOF_TB$metadata$msm_estimator %||% "없음"), collapse = ",")
  ASOF <- as.data.table(as.data.frame(ASOF_TB)); rm(ASOF_TB)
  ASOF[, Date := as.Date(Date)]
  ASOF <- ASOF[!is.na(Date) & !is.na(Crisis_Prob)][order(Date)]          # 로더와 같은 행 정의(Date · Crisis_Prob 결측 제외)
  asof_first <- min(ASOF$Date); asof_max <- max(ASOF$Date); asof_first_ym <- format(asof_first, "%Y-%m")
  bm_max  <- max(as.Date(read_parquet(file.path(CACHE_DIR, "benchmark.parquet"), col_select = "Date", mmap = FALSE)$Date), na.rm = TRUE)
  cal_max <- max(CAL)
  KT_P <- file.path(TD, "research/regime_comparison/output/ktri_v3_signals.csv")
  kt_d <- if (file.exists(KT_P)) { kt0 <- fread(KT_P); sort(unique(as.Date(kt0[!is.na(KTRI), DATE]))) } else as.Date(character(0))
  kt_d <- kt_d[!is.na(kt_d)]
  cat(sprintf("  (사본) as-of %s ~ %s · 벤치 최신 %s · 거래일 캘린더 최신 %s · KTRI 시작 %s\n", asof_first, asof_max, bm_max,
              cal_max, if (length(kt_d)) format(min(kt_d)) else "없음"))
  chk(sprintf("D0a as-of 사본 메타 msm_estimator = %s (로더 입력 계약)", EST), identical(ASOF_EST, EST), ASOF_EST)
  # 달력이 벤치를 따라왔는가(운영 리프레시 중간 상태 판별). 아니면 달력 기반 정확 대조 축(D1 척추 · D2 기준선 · F4)은
  #   판정 불가로 SKIP 한다 — 기준선 fred_avail_date 는 달력 밖 가용일 = NA 이고 엔진 fred_asof_join(extend_calendar=TRUE)
  #   은 달력 끝 뒤 평일을 거래일로 붙이므로 끝 구간에서 계약상 갈린다. 범위를 줄여 통과시키지 않는다(달력 결함을 가리지 않게).
  CAL_COVERS <- cal_max >= bm_max
  CALBM_PATHS <- paste(src_of("trading_calendar.parquet"), src_of("benchmark.parquet"), sep = " | ")
  # as-of 사본이 벤치 사본보다 낡았으면(운영 리프레시 중간 상태 — 생산자 미실행) 기본 경로 로더는 설계대로 stop 한다.
  #   그 경로는 미측정으로 SKIP 기록하고, D 절은 경로 덮어쓰기(낡음 검사만 생략 · 나머지 동일)로 잰다.
  op_d <- NULL
  if (asof_max < bm_max) {
    skip("D0_asof_default_path",
         sprintf("as-of 사본 최신일 %s < 벤치 사본 최신일 %s — 운영 리프레시 중간 상태(msm_asof_update.R 미실행). 기본 경로 로더는 설계대로 stop 하므로 기본 경로(낡음 검사 포함)는 미측정 · D 절은 경로 덮어쓰기(qvest.msm_asof_path)로 잰다",
                 asof_max, bm_max),
         paste(src_of("msm_asof_daily.parquet"), src_of("benchmark.parquet"), sep = " | "))
    op_d <- options(qvest.msm_asof_path = ASOF_P)
  }
  SD_P <- file.path(TD, "u_daily.parquet"); SD_ERR <- ""
  SD <- tryCatch(quiet(build_regime_signal_table_daily(save_path = SD_P, verbose = FALSE)),
                 error = function(e) { SD_ERR <<- conditionMessage(e); NULL })
  chk("D0 일간 통합 신호 빌드(as-of 로더 경유 · 사본)", is.data.frame(SD) && nrow(SD) > 0L, SD_ERR)
  if (is.data.frame(SD) && nrow(SD) > 0L) {
    # 척추 판정은 달력이 벤치를 따라왔을 때만 — 달력 < 벤치면 벤치 끝 며칠이 달력에 없어 정상 척추도 FAIL 한다.
    #   그때는 판정 범위를 줄이지 않고(달력 결함을 가리지 않게) 이 축을 사유와 함께 SKIP 한다.
    if (CAL_COVERS) {
      chk("D1 척추 = 한국 거래일만(FRED 관측일이 행을 만들지 않는다)", all(SD$Date %in% CAL), sprintf("(비거래일 %d)", sum(!(SD$Date %in% CAL))))
    } else {
      skip("D1_spine_kr",
           sprintf("거래일 캘린더 사본 최신일 %s < 벤치 사본 최신일 %s — 달력이 벤치를 따라오지 못한 상태(운영 리프레시 중간 상태일 수 있다)라 '척추 = 한국 거래일' 판정 불가(척추 중 달력 최신일 뒤 %d행) · 판정 범위를 줄여 통과시키지 않는다",
                   cal_max, bm_max, sum(SD$Date > cal_max)), CALBM_PATHS)
    }
    chk("D1c 표식 계약(r1): unified 일간 avail_date = Date 형·행 날짜 · c11_regime_key = 현행 규칙 키",
        inherits(SD$avail_date, "Date") && identical(as.integer(SD$avail_date), as.integer(as.Date(SD$Date))) &&
          all(SD$c11_regime_key == fred_avail_rules_meta()$regime_key))
    RF <- ref_mrs(SD$Date)
    dmax <- max(abs(SD$FRED_MRS - RF$FRED_MRS), na.rm = TRUE); nna <- sum(is.na(SD$FRED_MRS) != is.na(RF$FRED_MRS))
    if (CAL_COVERS) {
      chk("D2 FRED_MRS = 독립 가용시점 기준선(전 행)", dmax < 1e-9 && nna == 0L, sprintf("(max|d| %.3g · NA 불일치 %d)", dmax, nna))
    } else {
      skip("D2_fred_mrs_ref",
           sprintf("거래일 캘린더 사본 최신일 %s < 벤치 사본 최신일 %s — 기준선(fred_avail_date: 달력 밖 가용일 = NA)과 엔진(fred_asof_join extend_calendar=TRUE: 달력 끝 뒤 평일을 붙임)이 끝 구간에서 계약상 갈릴 수 있어 전 행 일치 판정 불가(이번 차이 max|d| %.3g · NA 불일치 %d) · 시점 결합 판별은 D3·D4 가 계속 잰다",
                   cal_max, bm_max, dmax, nna), CALBM_PATHS)
    }
    cc <- vcor(SD)
    chk(sprintf("D3 V-05 부호: cor(ΔFRED_MRS_t, ΔVIX 미국 t)=%+.3f < 0.2 · cor(…, 미국 ≤t−1)=%+.3f > 0.5 (구판 +0.84/−0.08)",
                cc["same"], cc["prev"]), cc["same"] < 0.2 && cc["prev"] > 0.5)
    .orig_aw <- .rs_asof_wide
    .rs_asof_wide <- function(kr_dates, wide, cols, cal) {       # 돌연변이: 관측일 당일 결합(V-05 기전)
      out <- data.table(Date = as.Date(kr_dates))
      for (cl in cols) { o <- wide[!is.na(get(cl)), .(Date = as.Date(Date), Value = get(cl))]
        out[, (cl) := pick(out$Date, o$Date, o$Date, o$Value)$value] }
      out
    }
    SDm_ERR <- ""
    SDm <- tryCatch(quiet(build_regime_signal_table_daily(save_path = file.path(TD, "u_daily_m.parquet"), verbose = FALSE)),
                    error = function(e) { SDm_ERR <<- conditionMessage(e); NULL })
    .rs_asof_wide <- .orig_aw; rm(.orig_aw)                       # 돌연변이 빌드가 실패해도 반드시 복구
    if (is.data.frame(SDm)) {
      dm <- max(abs(SDm$FRED_MRS - RF$FRED_MRS), na.rm = TRUE); ccm <- vcor(SDm)
      chk(sprintf("D4 돌연변이(같은 날짜 결합) → 기준선 불일치(max|d| %.2f) · 같은 날 상관 %+.3f > 0.5", dm, ccm["same"]),
          dm > 1 && ccm["same"] > 0.5)
    } else chk("D4 돌연변이(같은 날짜 결합) 빌드", FALSE, SDm_ERR)

    # ── MSM as-of 입력 계약(일간 · 실데이터 사본) ──
    chk(sprintf("D5 D1 A: 일간 첫 행 = as-of 첫날 %s (사본 독립 판독)", asof_first), identical_d(min(SD$Date), asof_first),
        format(min(SD$Date)))
    cat(sprintf("  (참고) 실데이터에서 절단 대상 척추 행(as-of 첫날 앞 KTRI 날짜) = %d — 0 이면 D5 는 절단 유무를 가르지 못한다(판별 = D5b · D8a · DM)\n",
                sum(kt_d < asof_first)))
    chk(sprintf("D6 표식 열: msm_estimator 전 행 = %s (일간)", EST), identical(unique(as.character(SD$msm_estimator)), EST),
        paste(unique(SD$msm_estimator), collapse = ","))
    gmd <- gate_m_read(SD_P)
    chk("D6b 표식 속성 생존: 메모리 attr · parquet 왕복(Gate M 판독식 — 열 고유값 · attr) 모두 계약값",
        stamp_ok(SD, gmd, EST), stamp_detail(SD, gmd))
    DAILY_COLS <- c("Date", "YM", "MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score", "Regime_Score", "Regime_Score_smooth",
                    "Category", "Cash_Pct", "Active_Layers", "Is_Month_End", "last_updated",
                    "avail_date", "c11_regime_key", "msm_estimator", "Category_basis")
    chk("D7 일간 스키마 = 구 13열(이름·순서) + 끝에 표식 계약 4열(avail_date · c11_regime_key · msm_estimator · Category_basis) · fw_* 없음",
        identical(names(SD), DAILY_COLS) && !any(grepl("^fw_", names(SD))), paste(names(SD), collapse = ","))
    chk(sprintf("D7b Category_basis(라벨 근거): 값 ∈ {score, msm_override} · MSM≥0.9 행(%d) 전부 msm_override · MSM<0.7 행 전부 score",
                sum(SD$MSM_Crisis_Prob >= 0.9, na.rm = TRUE)), basis_ok(SD, need_hi = TRUE))
  }

  # ── D5b 판별 사본: 실데이터는 절단 대상이 0행이라(위 참고) as-of 를 KTRI 시작 다음 해 첫 날부터로 자른 사본을 만든다 —
  #    그 앞 KTRI 날짜가 척추에 들어오므로 절단이 실제로 행을 지워야 첫 행 = 사본 첫날이 된다.
  #    사본은 경로 덮어쓰기로 준다(낡음 검사 생략 — 이 축과 무관 · 끝 날짜는 원본과 같다). 표식 메타는 그대로 싣는다.
  CUT_P <- file.path(TD, "msm_cut", "msm_asof_daily.parquet"); cut2 <- as.Date(NA); n_pre <- 0L
  if (length(kt_d)) {
    nx <- ASOF[Date > min(kt_d) & format(Date, "%Y") > format(min(kt_d), "%Y"), Date]
    if (length(nx)) { cut2 <- min(nx); n_pre <- sum(kt_d < cut2) }
  }
  SDb <- NULL; SDb_ERR <- ""
  if (!is.na(cut2)) {
    dir.create(dirname(CUT_P), recursive = TRUE, showWarnings = FALSE)
    tb_cut <- arrow::Table$create(as.data.frame(ASOF[Date >= cut2]))
    tb_cut$metadata$msm_estimator <- EST
    write_parquet(tb_cut, CUT_P); rm(tb_cut)
    op <- options(qvest.msm_asof_path = CUT_P)
    SDb <- tryCatch(quiet(build_regime_signal_table_daily(save_path = file.path(TD, "u_daily_cut.parquet"), verbose = FALSE)),
                    error = function(e) { SDb_ERR <<- conditionMessage(e); NULL })
    options(op)
    chk(sprintf("D5b 판별 사본(as-of 를 %s 부터 · 그 앞 KTRI 척추 %d행): 첫 행 = 사본 첫날 · MSM 결측 행 0", cut2, n_pre),
        d1_daily_ok(SDb, cut2),
        if (is.data.frame(SDb)) sprintf("(첫 행 %s · MSM 결측 %d)", first_of(SDb, "Date"), sum(is.na(SDb$MSM_Crisis_Prob))) else SDb_ERR)
  } else skip("D5b_discriminating_copy", "KTRI 사본이 없거나 KTRI 시작 다음 해의 as-of 날짜가 없다 — 판별 사본 미구성(일간 D1 절단 판별 미측정)", KT_P)

  # ── D8 월간 통합 신호 = Gate M 이 읽는 .cache/unified_regime_signal.parquet 의 생산자(build_regime_signal_table) ──
  #    FRED 층은 이 시점에 macro_regime 사본이 없어(E 가 만든다) fred_macro_wide 경로로 온다 — 그 달들이 as-of 첫 달 앞에서
  #    시작하므로 절단이 그 달들을 지워야 첫 달 = as-of 첫 달이 된다(실데이터 판별).
  SM_P <- file.path(TD, "u_month.parquet"); SM_ERR <- ""
  SM <- tryCatch(quiet(build_regime_signal_table(save_path = SM_P)), error = function(e) { SM_ERR <<- conditionMessage(e); NULL })
  chk("D8 월간 통합 신호 빌드(as-of 로더 경유 · 달력 월평균 · 사본)", is.data.frame(SM) && nrow(SM) > 0L, SM_ERR)
  if (is.data.frame(SM) && nrow(SM) > 0L) {
    n_pre_m <- sum(unique(format(FW$Date, "%Y-%m")) < asof_first_ym)
    chk(sprintf("D8a D1 A: 월간 첫 달 = as-of 첫 달 %s (FRED 층이 그 앞 %d개월을 갖는다 — 절단 대상)", asof_first_ym, n_pre_m),
        d1_month_ok(SM, asof_first_ym), first_of(SM, "YM"))
    gmm <- gate_m_read(SM_P)
    chk(sprintf("D8b 월간 표식: msm_estimator 열 전 행 · 메모리 attr · parquet 왕복(Gate M 판독식) 모두 %s", EST),
        identical(unique(as.character(SM$msm_estimator)), EST) && stamp_ok(SM, gmm, EST), stamp_detail(SM, gmm))
    MONTH_COLS <- c("Date", "YM", "MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score", "Layer1_Alert", "Layer2_Alert",
                    "Layer3_Alert", "Regime_Score", "Category", "Cash_Pct",
                    "avail_date", "c11_regime_key", "msm_estimator", "Category_basis")
    sm_file_cols <- tryCatch(names(read_parquet(SM_P, mmap = FALSE)), error = function(e) "판독 실패")
    chk("D8c 월간 스키마 = 구 12열(이름·순서) + 끝에 표식 계약 4열 · fw_* 없음(고정 기울기 표 폐지 2026-11-06 · parquet 도)",
        identical(names(SM), MONTH_COLS) && identical(sm_file_cols, MONTH_COLS), paste(names(SM), collapse = ","))
    chk("D8d 월간 Category_basis: 값 ∈ {score, msm_override} · MSM≥0.9 달 전부 msm_override · MSM<0.7 달 전부 score",
        basis_ok(SM, need_hi = FALSE))
  }

  # ═══ DM. 돌연변이 대조 — D1 절단 두 줄을 지운 사본(소스 텍스트 치환 · deparse 아님) → D5b · D8a 가 빨개지는가 ═══
  #   사본은 별도 환경(ME)에 source 한다 — 전역 함수(E~G 가 쓰는)는 건드리지 않는다. 판정 = 위와 같은 d1_*_ok 함수.
  CUT_LINES <- c(daily = "base <- base[Date >= .cut_d]", monthly = "base <- base[YM >= .cut_ym]")
  SRC_TXT <- readLines(SRC_SIGNAL, encoding = "UTF-8", warn = FALSE)
  hit <- vapply(CUT_LINES, function(l) sum(trimws(SRC_TXT) == l), integer(1))
  MUT_TXT <- SRC_TXT
  MUT_TXT[trimws(MUT_TXT) %in% CUT_LINES] <- "  # (돌연변이 DM: D1 절단 삭제)"
  chk(sprintf("DM0 치환 성사: 대상 줄 일간 %d · 월간 %d(각 정확히 1) · 사본에 절단 줄 0 · 바뀐 줄 2", hit[["daily"]], hit[["monthly"]]),
      all(hit == 1L) && !any(trimws(MUT_TXT) %in% CUT_LINES) && sum(MUT_TXT != SRC_TXT) == 2L)
  MUT_P <- file.path(TD, "regime_signal_mut_d1cut.R")
  writeLines(MUT_TXT, MUT_P, useBytes = TRUE)
  ME <- new.env(parent = globalenv()); ME_ERR <- character(0)
  src_ok <- tryCatch({ quiet(source(MUT_P, local = ME, encoding = "UTF-8")); TRUE },
                     error = function(e) { ME_ERR <<- c(ME_ERR, paste("source:", conditionMessage(e))); FALSE })
  SDx <- SMx <- NULL
  if (src_ok) {
    if (!is.na(cut2)) {
      op <- options(qvest.msm_asof_path = CUT_P)
      SDx <- tryCatch(quiet(ME$build_regime_signal_table_daily(save_path = file.path(TD, "u_daily_cut_mut.parquet"), verbose = FALSE)),
                      error = function(e) { ME_ERR <<- c(ME_ERR, paste("일간:", conditionMessage(e))); NULL })
      options(op)
    }
    SMx <- tryCatch(quiet(ME$build_regime_signal_table(save_path = file.path(TD, "u_month_mut.parquet"))),
                    error = function(e) { ME_ERR <<- c(ME_ERR, paste("월간:", conditionMessage(e))); NULL })
  }
  chk("DM1 돌연변이 사본 단독 실행: source · 월간 · 일간(판별 사본) 빌드가 돈다(크래시를 red 로 세지 않게)",
      src_ok && is.data.frame(SMx) && (is.na(cut2) || is.data.frame(SDx)), paste(ME_ERR, collapse = " | "))
  if (!is.na(cut2)) {
    chk(sprintf("DM2 돌연변이(일간 절단 삭제) → D5b 단정 red (첫 행 %s · MSM 결측 %d · 사본 첫날 %s)", first_of(SDx, "Date"),
                if (is.data.frame(SDx)) sum(is.na(SDx$MSM_Crisis_Prob)) else NA_integer_, cut2),
        is.data.frame(SDx) && !d1_daily_ok(SDx, cut2))
  } else skip("DM2_daily_mutant", "판별 사본 미구성(D5b SKIP) — 일간 D1 절단 돌연변이 판별 미측정", KT_P)
  chk(sprintf("DM3 돌연변이(월간 절단 삭제) → D8a 단정 red (첫 달 %s · as-of 첫 달 %s)", first_of(SMx, "YM"), asof_first_ym),
      is.data.frame(SMx) && !d1_month_ok(SMx, asof_first_ym))
  if (!is.null(op_d)) options(op_d)

  # ═══ E. macro_regime (fred_compute_regime · V-14) ═══
  cat("\n=== E. macro_regime 월 행 = 결정일까지 공표분 ===\n")
  MR <- quiet(fred_compute_regime())
  ii <- findInterval(as.integer(MR$Date), as.integer(CAL))
  me_dec <- rep(NA_integer_, nrow(MR)); me_dec[ii > 0] <- as.integer(CAL)[ii[ii > 0]]
  chk("E1 Asof_Date = 말일 이하 마지막 한국 거래일(전 행)", identical(as.integer(MR$Asof_Date), me_dec))
  chk("E1c 표식 계약(r1): macro_regime avail_date = Asof_Date(Date 형) · c11_regime_key = 현행 규칙 키",
      inherits(MR$avail_date, "Date") && identical(as.integer(MR$avail_date), as.integer(MR$Asof_Date)) &&
        all(MR$c11_regime_key == fred_avail_rules_meta()$regime_key))
  macro_viol <- function(tbl, dec_col) {
    bad <- 0L; n <- 0L
    ids <- unique(MF[, .(Series_ID, Series)])
    for (k in seq_len(nrow(ids))) {
      sid <- ids$Series_ID[k]; nm <- ids$Series[k]
      if (sid == "DEXKOUS" || !(nm %in% names(tbl))) next
      o <- MF[Series_ID == sid, .(Date, Value)]
      p <- pick(tbl[[dec_col]], o$Date, fred_avail_date(sid, o$Date, kr_calendar = CAL), o$Value)
      x <- tbl[[nm]]; n <- n + length(x)
      bad <- bad + sum(!((is.na(x) & is.na(p$value)) | (!is.na(x) & !is.na(p$value) & abs(x - p$value) < 1e-9)))
    }
    c(bad = bad, n = n)
  }
  mv <- macro_viol(MR, "Asof_Date")
  chk(sprintf("E2 계열 22종 × %d월 = 독립 기준선(Asof_Date 가용분)", nrow(MR)), mv["bad"] == 0L, sprintf("(불일치 %d/%d)", mv["bad"], mv["n"]))
  r8 <- MR[YM == "2026-08"]
  chk("E3 2026-08 행 VIX = 14.43(미국 08-28 · 구판 08-31 14.92)", isTRUE(all.equal(r8$VIX, 14.43)))
  chk("E3b 2026-08 행 ICSA = 08-22 라벨(08-29 라벨은 09-03 공표) · NFCI/STLFSI4 = 08-21 라벨",
      isTRUE(all.equal(r8$Init_Claims, sval("ICSA", "2026-08-22"))) &&
        isTRUE(all.equal(r8$Chi_Fin_Cond, sval("NFCI", "2026-08-21"))) &&
        isTRUE(all.equal(r8$StL_Fin_Stress, sval("STLFSI4", "2026-08-21"))))
  chk("E3c 2026-08 행 CPI·INDPRO = 07월분(08월분 미공표)",
      isTRUE(all.equal(r8$US_CPI, sval("CPIAUCSL", "2026-07-01"))) && isTRUE(all.equal(r8$US_IndProd, sval("INDPRO", "2026-07-01"))))
  ek <- ECO[, .(Date, Value = KRW_USD)]
  pk <- pick(MR$Asof_Date, ek$Date, fred_avail_date("ECOS_KRW_USD", ek$Date, kr_calendar = CAL), ek$Value)
  chk("E4 KRW_USD = ECOS 731Y001 가용분(전 행)", isTRUE(all.equal(MR$KRW_USD, pk$value)))
  # 누출 구성(구판식: 월내 마지막 관측 라벨) → 같은 판정 함수가 잡아야 한다
  OLDW <- dcast(MF[Series_ID != "DEXKOUS", .(Date, Series, Value)], Date ~ Series, value.var = "Value")
  OLDW[, YM := format(Date, "%Y-%m")]
  OLDM <- OLDW[, lapply(.SD, function(x) { x <- x[!is.na(x)]; if (length(x)) tail(x, 1) else NA_real_ }),
               by = YM, .SDcols = setdiff(names(OLDW), c("Date", "YM"))]
  OLDM <- merge(OLDM, MR[, .(YM, Asof_Date)], by = "YM")
  mvo <- macro_viol(OLDM, "Asof_Date")
  chk(sprintf("E5 누출 구성(구판식 월내 마지막 관측)은 같은 판정에서 불일치 %d > 0", mvo["bad"]), mvo["bad"] > 100L)
  # merge_regime_to_signals — Asof_Date ≤ 신호일 · Asof 없는 캐시 fail-closed
  FF <- data.table(Date = as.Date(c("2026-08-28", "2026-08-31", "2026-09-01", "2020-03-31")), Ticker = "A", Score = 1)
  MM <- quiet(merge_regime_to_signals(FF, regime_dt = MR))
  exp_row <- vapply(seq_len(nrow(MM)), function(i) MR[Asof_Date <= MM$Date[i]][.N, VIX], 1)
  chk("E6 merge_regime_to_signals: 각 신호일 d 에 Asof_Date ≤ d 행(2026-08-28 은 07월 행)",
      isTRUE(all.equal(MM$VIX, exp_row)) && isTRUE(all.equal(MM[Date == as.Date("2026-08-28"), VIX], MR[YM == "2026-07", VIX])))
  chk("E7 Asof_Date 없는 수리 전 캐시 → 결합 거부(fail-closed)",
      raises(merge_regime_to_signals(FF, regime_dt = MR[, !"Asof_Date"])))
  # CPI 날짜 기준 12개월(합성: 2025-10 결측) — CONVENTIONS ③
  cpi_d <- seq(as.Date("2023-01-01"), as.Date("2026-12-01"), by = "month")
  cpi_d <- cpi_d[cpi_d != as.Date("2025-10-01")]
  SYN <- data.table(Date = cpi_d, Series = "US_CPI", Series_ID = "CPIAUCSL", Value = 300 + seq_along(cpi_d) * 0.7)
  syn_cal <- local({ d <- seq(as.Date("2023-01-02"), as.Date("2027-03-31"), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] })
  MRS <- quiet(fred_compute_regime(macro_dt = SYN, kr_calendar = syn_cal))
  cv <- function(d) SYN[Date == as.Date(d), Value]
  pa <- pick(MRS$Asof_Date, SYN$Date, fred_avail_date("CPIAUCSL", SYN$Date, kr_calendar = syn_cal), SYN$Value)
  i_n <- which(pa$obs == as.Date("2025-11-01"))[1]; i_o <- which(pa$obs == as.Date("2026-10-01"))[1]
  chk("E8 CPI_YoY(관측 2025-11) = 2025-11/2024-11 − 1 (날짜 기준)", !is.na(i_n) &&
        isTRUE(all.equal(MRS$CPI_YoY[i_n], cv("2025-11-01") / cv("2024-11-01") - 1)))
  chk("E8b CPI_YoY(관측 2026-10) = NA — 12개월 전(2025-10) 관측 없음, 13개월 변화로 대체하지 않는다",
      !is.na(i_o) && is.na(MRS$CPI_YoY[i_o]))
  alt <- MRS$US_CPI / shift(MRS$US_CPI, 12) - 1
  chk("E8c 대조: 행 기준 shift(12) 는 그 행에 값을 낸다(검사가 차이를 볼 수 있다)", !is.na(i_o) && !is.na(alt[i_o]))
}

# ═══ F. BCS — 확장창(C1) · 가용시점 · 월중 병합 ═══
cat("\n=== F. BCS 확장창·가용시점·병합 ===\n")
set.seed(11); xx <- round(rnorm(600), 1); xx[sample(600, 40)] <- NA
fp <- .rs_expanding_pct(xx)
pref_ok <- all(vapply(c(50L, 200L, 450L), function(k) isTRUE(all.equal(fp[1:k], .rs_expanding_pct(xx[1:k]))), TRUE))
chk("F1 확장창 백분위 접두 불변(동값·결측 포함)", pref_ok)
chk("F1b 마지막 점 = 전표본 frank(평균 순위)/비결측수 와 같다", isTRUE(all.equal(fp[600], (frank(xx, na.last = "keep") / sum(!is.na(xx)))[600])) || is.na(xx[600]))
full_pct <- function(x) frank(x, na.last = "keep") / sum(!is.na(x))                  # 구판(전표본)
chk("F1c 대조: 전표본 백분위는 접두 불변을 깬다(검사가 C1 을 볼 수 있다)",
    !isTRUE(all.equal(full_pct(xx)[1:200], full_pct(xx[1:200]))))
fq <- .rs_expanding_quintile(xx)
chk("F2 확장창 5분위 접두 불변", identical(as.character(fq[1:300]), as.character(.rs_expanding_quintile(xx[1:300]))))
full_q <- function(x) as.character(cut(x, quantile(x, seq(0, 1, 0.2), na.rm = TRUE), include.lowest = TRUE, labels = paste0("Q", 1:5)))
chk("F2b 대조: 전표본 분위 경계는 접두 불변을 깬다", !identical(full_q(xx)[1:300], full_q(xx[1:300])))
BC <- data.table(Date = as.Date(c("2020-03-02", "2020-03-31")), BCS = c(0.1, 0.9), BCS_Q = c("Q1", "Q5"))
SIG <- data.table(Date = as.Date("2020-02-29"), Regime_Score = 10, Category = "RISK_ON", Cash_Pct = 0)   # 현행 월간 스키마(fw_* 4열 2026-11-06 폐지)
FB <- quiet(merge_regime_with_bcs(data.table(Date = as.Date(c("2020-03-16", "2020-03-31")), Ticker = "A"),
                                  signal_dt = SIG, bcs_dt = copy(BC)))
chk("F3 merge_regime_with_bcs: 월중 03-16 은 03-02 BCS(구판 YM 병합은 03-31 값 = 미래)",
    isTRUE(all.equal(FB[Date == as.Date("2020-03-16"), BCS], 0.1)) && isTRUE(all.equal(FB[Date == as.Date("2020-03-31"), BCS], 0.9)))
if (HAVE_DRV) {
  B <- quiet(compute_bcs_daily())
  vo <- MF[Series_ID == "VIXCLS", .(Date, Value)]
  bm_d <- sort(unique(as.Date(read_parquet(file.path(CACHE_DIR, "benchmark.parquet"))$Date)))
  pv <- pick(bm_d, vo$Date, fred_avail_date("VIXCLS", vo$Date, kr_calendar = CAL), vo$Value)
  rv <- data.table(Date = bm_d, V = pv$value); rv[, chg3 := V - shift(V, 3)]
  j <- rv[B, on = "Date"]
  # D1·D2 와 같은 사전 조건: 달력이 벤치를 못 따라왔으면 기준선(달력 밖 = NA)과 엔진(달력 끝 뒤 평일 붙임)이 끝 구간에서 갈린다
  if (max(CAL) >= max(bm_d)) {
    chk("F4 BCS VIX_Chg3 = 가용시점 VIX(미국 날짜 < 한국 날짜)의 3행 변화(전 행)",
        isTRUE(all.equal(j$VIX_Chg3, j$chg3)), sprintf("(n=%d)", nrow(j)))
  } else {
    skip("F4_bcs_vix_ref",
         sprintf("거래일 캘린더 사본 최신일 %s < 벤치 사본 최신일 %s — 기준선(fred_avail_date: 달력 밖 가용일 = NA)과 엔진(fred_asof_join extend_calendar=TRUE: 달력 끝 뒤 평일을 붙임)이 끝 구간에서 계약상 갈릴 수 있어 전 행 일치 판정 불가 · 범위를 줄여 통과시키지 않는다",
                 max(CAL), max(bm_d)),
         paste(src_of("trading_calendar.parquet"), src_of("benchmark.parquet"), sep = " | "))
  }
} else skip("F4_bcs_real", "파생지표 캐시 부재 — BCS 실데이터 미측정", DRV)

# ═══ G. merge_daily_regime — 형태 b(노출×r_t) ═══
cat("\n=== G. merge_daily_regime(mode) ===\n")
if (HAVE_REAL) {
  td <- CAL[CAL >= as.Date("2020-03-02") & CAL <= as.Date("2020-03-31")]
  FD <- data.table(Date = td, Ticker = "A")
  e1 <- quiet(merge_daily_regime(copy(FD), regime_dt = RES, mode = "exposure_return"))
  e0 <- quiet(merge_daily_regime(copy(FD), regime_dt = RES, mode = "decision_close"))
  prev <- CAL[findInterval(as.integer(td) - 1L, as.integer(CAL))]
  chk("G1 exposure_return: r_t 에 직전 한국 거래일 행", isTRUE(all.equal(e1$MRS, RES$MRS[match(prev, RES$Date)])))
  chk("G2 decision_close: 같은 날 행(구판 동작)", isTRUE(all.equal(e0$MRS, RES$MRS[match(td, RES$Date)])))
}

unlink(TD, recursive = TRUE)
cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
SUMMARY <- list(test = "regime_c11_asof", pass = PASS, fail = FAIL, skipped = length(SKIPS), total = PASS + FAIL, skips = SKIPS)
if (SRC_OVERRIDDEN) SUMMARY$src_signal_override <- SRC_SIGNAL   # 돌연변이 대조 실행 표시(정상 실행이 아님)
cat(toJSON(SUMMARY, auto_unbox = TRUE), "\n", sep = "")
quit(status = if (FAIL > 0L) 1L else 0L, save = "no")
