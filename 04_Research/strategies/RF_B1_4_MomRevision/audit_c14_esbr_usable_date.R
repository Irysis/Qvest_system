# =============================================================================
# audit_c14_esbr_usable_date.R — B1-4 C14 명시 검증 (컨센서스 same-day 이슈)
# =============================================================================
# 배경: 1/20 에서 C01_SUE 가 정적 검증기 FAIL_LOOKAHEAD (컨센서스 33종 공통
#   same-day 이슈 — 보수 +1d fail-closed 규약이면 Date=t 값의 Usable_Date=t+1).
#   C13_Revision_Breadth_3m 도 같은 컨센서스(esbr) 계열이므로, B1-4 지시가
#   "Usable_Date 준수를 명시 검증하라"를 부과했다.
#
# 검증 논리: C13(sig_date) 는 esbr 패널의 Date <= sig_date 행만의 함수다
#   (compute_consensus.R — 빌더가 재절단). 따라서 보수 +1d 규약 하에서
#   Usable_Date <= sig_date 위반이 생길 수 있는 유일한 경우 =
#   **esbr 값 변경일(릴리스 런 시작일)이 시그널일(월말 거래일)과 동일**한 경우.
#   릴리스일이 시그널일보다 하루라도 이르면 release+1d <= sig_date 로 안전.
#
# 측정: esbr.parquet 의 종목별 값-변경일(런 시작일) 전수 추출 →
#   ① 월말 시그널 그리드와의 동일일 건수 / 비율
#   ② 변경일의 월내 위치 분포 (빌더 주장: 분기 첫 영업일 100% — 재도출)
#   ③ 시그널월별 최근 릴리스일 → sig_date 갭 분포
#   (감사 = 재도출. 빌더 주석 진술을 증거로 삼지 않는다.)
# 산출: c14_audit_result.json (전략 디렉터리 내부)
# =============================================================================
suppressWarnings(suppressMessages({ library(arrow); library(data.table); library(jsonlite) }))

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- file.path(ROOT, "04_Research", "strategies", "RF_B1_4_MomRevision")

# ---- 1. esbr 패널 (원천 감사용 — 시그널 소비는 load_month_factors 경유 C15) ----
eb <- as.data.table(read_parquet(file.path(ROOT, ".cache", "consensus", "esbr.parquet")))
eb <- eb[!is.na(esbr)]
eb[, Date := as.Date(Date)]
setorder(eb, Ticker, Date)

# ---- 2. 값-변경일 (릴리스 런 시작일) — compute_consensus .cons_quarters 동일 규약 ----
TIE_TOL <- 1e-12
eb[, newrun := is.na(shift(esbr)) | Ticker != shift(Ticker) |
               abs(esbr - shift(esbr)) > TIE_TOL]
runs <- eb[newrun == TRUE, .(Ticker, Release_Date = Date)]

# ---- 3. 월말 시그널 그리드 (엔진과 동일: RAWDATA 거래일 월말) ----
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RD <- res$RAWDATA; rm(res)
if (!inherits(RD$Date, "Date")) RD[, Date := as.Date(Date)]
RD[, .ym := format(Date, "%Y-%m")]
sig_dates <- sort(RD[, .(Date = max(Date)), by = .ym]$Date)
sig_dates <- sig_dates[sig_dates >= as.Date("2004-01-01")]
rm(RD); gc(verbose = FALSE)

# ---- 4-①: 릴리스일 == 시그널일(월말) 동일일 건수 ----
runs[, on_sig_date := Release_Date %in% sig_dates]
n_runs <- nrow(runs)
n_same_day <- sum(runs$on_sig_date)

# ---- 4-②: 릴리스일 월내 위치 / 월 분포 (재도출 — 빌더 주장 검증) ----
runs[, dom := as.integer(format(Release_Date, "%d"))]
runs[, mon := as.integer(format(Release_Date, "%m"))]
dom_dist <- runs[, .N, by = .(early = dom <= 5L)]
mon_dist <- runs[, .N, by = mon][order(-N)]

# ---- 4-③: 시그널월별 최근 릴리스 → sig_date 갭 (전 종목 최소 갭) ----
setkey(runs, Release_Date)
gap_list <- vapply(sig_dates[sig_dates >= as.Date("2005-01-01")], function(d) {
  r <- runs[Release_Date <= d, max(Release_Date)]
  if (!is.finite(as.numeric(r))) return(NA_real_)
  as.numeric(d - r)
}, numeric(1))
gap_list <- gap_list[is.finite(gap_list)]

result <- list(
  audit = "C14 — esbr(C13 원천) 릴리스일 vs 월말 시그널일 same-day 검증",
  convention = "보수 +1d fail-closed: Usable_Date = Release_Date + 1. 위반 가능 유일 케이스 = Release_Date == sig_date",
  n_release_runs_total = n_runs,
  n_release_on_sig_date = n_same_day,
  frac_release_on_sig_date = n_same_day / n_runs,
  release_dom_le5_frac = dom_dist[early == TRUE, N] / n_runs,
  release_month_top = mon_dist[1:6],
  min_gap_latest_release_to_sigdate_days = min(gap_list),
  p10_gap_days = as.numeric(quantile(gap_list, 0.10)),
  median_gap_days = as.numeric(median(gap_list)),
  verdict = if (n_same_day == 0L) "PASS — 릴리스일이 월말 시그널일과 동일한 건 0. +1d 규약 하에서도 Usable_Date <= sig_date 전 건 성립"
            else sprintf("REVIEW — same-day 릴리스 %d건 (%.4f%%): 해당 (Ticker, month) 열거 필요", n_same_day, 100 * n_same_day / n_runs),
  measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(result, file.path(OUT_DIR, "c14_audit_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("[c14_audit] runs=", n_runs, " same-day=", n_same_day,
    " min_gap=", min(gap_list), "d median_gap=", median(gap_list), "d\n", sep = "")
cat("[c14_audit] verdict: ", result$verdict, "\n", sep = "")
print(mon_dist)
