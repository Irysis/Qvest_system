##=============================================================================
## krx_index_monthend_backfill.R — 지수 월말 종가 백필 (지수-팩터 베타용)
## 대상: 코스피 / 코스피 200 / 코스닥 / 코스닥 150 (IDX_NM 정확 일치)
## 날짜: 최근 N_M 완결월 월말 + 직전영업일(진행월 MTD 회귀점) — 격자 = RAWDATA 거래일(구판 그대로).
## 원천 (2026-11-13 개정 · 도훈 지시 "스타일 국면 브리핑 … 최신데이터 기반으로 계산되서 발송되게"):
##   ① 1순위 = 퀀티와이즈 지수 정본 .cache/indices.parquet(kospi · kospi200 · kosdaq · kosdaq150 — 밤 체인이
##      03_Universe/Benchmark_price.xlsx → build_index_cache.py 로 만든다 · 결정 BENCHMARK-QW-ONLY-20261017).
##      네 지수가 모두 있는 날짜만 그 날의 원천으로 쓴다(한 날짜 안에서 원천을 섞지 않는다).
##   ② 그 날짜가 퀀티 정본에 없을 때만 KRX OPEN API(캐시 우선 · .cache/krx/{board}_index/ — 일별 수집기와 같은 이름 ·
##      krx_api 내장 0.5s 스로틀).
##   왜: 구판은 KRX OPEN API 만 썼다. KRX 는 직전 영업일 자료를 익일 08시 무렵에 낸다(캐시 파일 생성 시각 실측: 전일분
##     최초 08:03). 07:30 브리핑은 그 전에 돌아 진행월 MTD 회귀점(직전영업일 종가)이 빠졌고, 지수 민감도 절 2개 · 차트 2장 ·
##     '지수 함의' 줄이 '36개월 ~<지난 완결월>'에 머물렀다(11-13 실측: 20261112 응답 없음 → '36개월 ~2026-10').
##     퀀티 정본에는 같은 날 00:17 에 이미 직전영업일 종가가 있다.
##   두 원천은 같은 공표 지수다 — KRX 캐시 154일(2022-05-31~2026-11-10) × 4지수 종가 |차이| 최대 0(11-13 실측).
## 출력 열: Date · idx · close · src(quantiwise | krx).
##=============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/data/krx_data_collector.R")
OUT_DIR <- Sys.getenv("FF5_KR_OUT_DIR", "outputs/ff5_kr")      # 검사용 덮어쓰기(운영 = 기본값)
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
N_M <- 50L
TARGETS <- c("코스피", "코스피 200", "코스닥", "코스닥 150")
QW_COLS <- c(kospi = "코스피", kospi200 = "코스피 200", kosdaq = "코스닥", kosdaq150 = "코스닥 150")   # 퀀티 정본 열 → IDX_NM

ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
mgrid <- seq(as.Date("2004-12-01"), max(ud), by = "1 month")
me <- unique(as.Date(vapply(mgrid, function(d) { m0 <- as.Date(cut(d, "month")); e <- seq(m0, by = "1 month", length.out = 2)[2] - 1
  v <- ud[ud <= e & ud >= m0]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
me <- me[format(me, "%Y-%m") < format(max(ud), "%Y-%m")]     # 완결월 월말만
me <- tail(me, N_M)
me <- unique(c(me, max(ud)))                                  # + 직전영업일 (MTD 회귀점용, 도훈 지시 07-18)
wf("backfill 대상 %d개 (%s..%s, 마지막=직전영업일)", length(me), format(min(me)), format(max(me)))

## ① 퀀티와이즈 지수 정본 — 판독 실패면 빈 표(전 날짜 KRX 경로 · 구판 동작)
QW <- tryCatch({
  q <- as.data.table(read_parquet(".cache/indices.parquet", col_select = c("Date", names(QW_COLS))))
  q[, Date := as.Date(Date)]
  q <- melt(q[Date %in% me], id.vars = "Date", variable.name = "col", value.name = "close", variable.factor = FALSE)
  q[, idx := unname(QW_COLS[col])]
  q[is.finite(close) & close > 0, .(Date, idx, close)]
}, error = function(e) {
  wf("  [warn] 퀀티 지수 정본(.cache/indices.parquet) 판독 실패: %s — KRX 원천만 쓴다", conditionMessage(e))
  data.table(Date = as.Date(character(0)), idx = character(0), close = numeric(0))
})
qw_days <- QW[, .N, by = Date][N == length(TARGETS), Date]

## ② KRX OPEN API (캐시 우선)
get_board <- function(d, board) {
  ds <- format(d, "%Y%m%d")
  cdir <- file.path(".cache/krx", sprintf("%s_index", board))
  dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
  cf <- file.path(cdir, sprintf("%s_index_%s.parquet", board, ds))
  if (file.exists(cf)) return(as.data.table(read_parquet(cf)))
  x <- if (board == "kospi") krx_kospi_index(ds) else krx_kosdaq_index(ds)
  if (!is.null(x) && nrow(x)) { x <- as.data.table(x); write_parquet(x, cf); return(x) }
  NULL
}

rows <- list(); n_api <- 0L; n_qw <- 0L; n_krx <- 0L
for (d in me) {
  d <- as.Date(d, origin = "1970-01-01")
  if (d %in% qw_days) {
    rows[[format(d)]] <- QW[Date == d, .(Date, idx, close, src = "quantiwise")]
    n_qw <- n_qw + 1L
    next
  }
  got <- list()
  for (bd in c("kospi", "kosdaq")) {
    cf_exists <- file.exists(file.path(".cache/krx", sprintf("%s_index", bd), sprintf("%s_index_%s.parquet", bd, format(d, "%Y%m%d"))))
    x <- tryCatch(get_board(d, bd), error = function(e) NULL)
    if (!cf_exists && !is.null(x)) n_api <- n_api + 1L
    if (is.null(x) || !nrow(x)) next
    x <- x[IDX_NM %in% TARGETS]
    if (!nrow(x)) next
    x[, close := as.numeric(gsub(",", "", CLSPRC_IDX))]
    got[[bd]] <- x[, .(Date = d, idx = IDX_NM, close, src = "krx")]
  }
  if (length(got)) { rows[[format(d)]] <- rbindlist(got); n_krx <- n_krx + 1L }
}
IX <- rbindlist(rows)
wf("수집: %d행 | 원천 퀀티와이즈 %d일 · KRX %d일 · 없음 %d일 | API 신규호출 %d | 지수별 월수:",
   nrow(IX), n_qw, n_krx, length(me) - n_qw - n_krx, n_api)
print(IX[, .N, by = idx])
if (nrow(IX)) wf("마지막 날짜 %s (원천 %s) — RAWDATA 직전영업일 %s", format(max(IX$Date)),
                 paste(unique(IX[Date == max(Date), src]), collapse = "+"), format(max(ud)))

## 교차 대조(API 호출 없음) — 퀀티 원천을 쓴 날 중 KRX 캐시 파일이 있는 날만 · 종가 차이 최댓값을 로그에 남긴다
xc <- rbindlist(lapply(qw_days, function(d) rbindlist(lapply(c("kospi", "kosdaq"), function(bd) {
  cf <- file.path(".cache/krx", sprintf("%s_index", bd), sprintf("%s_index_%s.parquet", bd, format(d, "%Y%m%d")))
  x <- if (file.exists(cf)) tryCatch(as.data.table(read_parquet(cf)), error = function(e) NULL) else NULL
  if (is.null(x) || !nrow(x) || !"IDX_NM" %in% names(x)) return(NULL)
  x[IDX_NM %in% TARGETS, .(Date = d, idx = IDX_NM, krx = as.numeric(gsub(",", "", CLSPRC_IDX)))]
}))))
if (nrow(xc)) {
  xm <- merge(xc, QW, by = c("Date", "idx"))
  wf("교차 대조 퀀티와이즈 vs KRX 캐시: %d점 · 종가 |차이| 최대 %.4f", nrow(xm), max(abs(xm$krx - xm$close)))
}
write_parquet(IX, file.path(OUT_DIR, "krx_index_monthend.parquet"))
wf("[krx_index_backfill] done -> %s", file.path(OUT_DIR, "krx_index_monthend.parquet"))
