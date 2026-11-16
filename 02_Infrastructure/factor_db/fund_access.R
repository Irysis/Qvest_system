#==============================================================================
# fund_access.R — 재무 캐시 조회기 (2026-11-16 도훈 '분기파일 · 연간파일 하나씩 · 인프라 맞춰 수정')
#
# 재무 캐시 두 개(02_Infrastructure/data/build_fundamental_caches.R 가 만든다):
#   .cache/fundamental_quarterly.parquet — 결산 분기 행 · 흐름 = 최근 4분기 합(TTM) · 잔액 = 분기 말 · 파생 = TTM 기준(1년 전 = 4분기 전)
#   .cache/fundamental_annual.parquet    — 회계연도 말 행 · 흐름 = 그 회계연도 합 · 잔액 = 연말 · 파생 = 회계연도 기준
# 행마다 Factor_Date = 그 값을 쓸 수 있는 첫날(pit.md C4) — 조회는 Factor_Date <= 결정일 인 마지막 행만 쓴다(PIT).
#
# fa_latest(sig_date, basis = "q" | "a", items = NULL) → data.table(Ticker, <item>...) — 종목 × 항목마다 결정일 기준 최신 값
#   · 묵은 값 거르기: 그 값의 기간 말(Period_Date)이 결정일보다 FA_MAX_AGE_M[basis] 개월 넘게 앞서면 쓰지 않는다(상장폐지 · 공시 중단 종목이
#     몇 해 전 값으로 남지 않게). 분기 = 15개월(법정기한 + 45일 ≈ 기간 말 + 4~6개월에 한 분기 누락 여유) · 연간 = 24개월(Fama & French 1993 —
#     t−1 회계연도 값을 t 년 6월부터 다음 해 5월까지 쓴다 = 기간 말 + 18개월 · 결산월 차이 여유 6개월).
#   · 항목마다 따로 최신을 고른다(한 비율의 분자 · 분모가 다른 기간에서 올 수 있다 — 같은 행(Period)인 항목만 쓰려면 fa_latest(…, same_period = TRUE)).
# 캐시는 세션당 한 번 읽어 .fa_env 에 둔다(fa_reset() 으로 비움). 경로 덮어쓰기(시험) = QVEST_FUND_Q · QVEST_FUND_A.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.fa_env <- new.env(parent = emptyenv())
FA_MAX_AGE_M <- c(q = 15L, a = 24L)

.fa_root <- function() {
  r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r) && exists("PROJECT_ROOT")) r <- get("PROJECT_ROOT")
  if (!nzchar(r) && exists("CACHE_DIR")) return(dirname(get("CACHE_DIR")))
  gsub("\\\\", "/", r)
}
.fa_path <- function(basis) {
  ev <- if (basis == "q") Sys.getenv("QVEST_FUND_Q", "") else Sys.getenv("QVEST_FUND_A", "")
  if (nzchar(ev)) return(ev)
  cdir <- if (exists("CACHE_DIR")) get("CACHE_DIR") else file.path(.fa_root(), ".cache")
  file.path(cdir, if (basis == "q") "fundamental_quarterly.parquet" else "fundamental_annual.parquet")
}
fa_reset <- function() rm(list = ls(.fa_env), envir = .fa_env)

.fa_load <- function(basis) {
  key <- paste0("tab_", basis)
  if (!is.null(.fa_env[[key]])) return(.fa_env[[key]])
  p <- .fa_path(basis)
  if (!file.exists(p)) stop(sprintf("[fund_access] 재무 캐시 없음: %s (build_fundamental_caches.R)", p), call. = FALSE)
  X <- as.data.table(read_parquet(p, col_select = c("Ticker", "Item", "Factor_Date", "Period_Date", "Value")))
  X[, `:=`(Factor_Date = as.Date(Factor_Date), Period_Date = as.Date(Period_Date))]
  setkey(X, Item, Ticker, Factor_Date)
  .fa_env[[key]] <- X
  X
}

fa_latest <- function(sig_date, basis = c("q", "a"), items = NULL, same_period = FALSE) {
  basis <- match.arg(basis)
  sig <- as.Date(sig_date)
  X <- .fa_load(basis)
  pairs <- .fa_env[[paste0("pairs_", basis)]]
  if (is.null(pairs)) { pairs <- unique(X[, .(Item, Ticker)]); .fa_env[[paste0("pairs_", basis)]] <- pairs }
  Q <- if (is.null(items)) copy(pairs) else pairs[Item %in% items]
  if (!nrow(Q)) return(data.table(Ticker = character()))
  Q[, Factor_Date := sig]
  R <- X[Q, on = .(Item, Ticker, Factor_Date), roll = Inf, nomatch = 0L]
  min_pd <- seq(sig, by = sprintf("-%d months", FA_MAX_AGE_M[[basis]]), length.out = 2L)[2L]
  R <- R[!is.na(Value) & Period_Date >= min_pd]
  if (same_period) {
    lp <- R[, .(Period_Date = max(Period_Date)), by = Ticker]
    R <- R[lp, on = .(Ticker, Period_Date), nomatch = 0L]
  }
  if (!nrow(R)) return(data.table(Ticker = character()))
  W <- dcast(R, Ticker ~ Item, value.var = "Value")
  if (!is.null(items)) for (it in setdiff(items, names(W))) set(W, j = it, value = NA_real_)
  W
}
