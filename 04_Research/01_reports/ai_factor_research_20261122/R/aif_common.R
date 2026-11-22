## aif_common.R — AI 팩터 연구(독립 연구) 공통 층: 경로 · 설정 · 시장 자료(유니버스 · 일별 수익 · 월말 신호일 · 앞으로의 수익)
##   설계 = ../README.md · 설정 = ../aif_config.json. 원자료 캐시는 읽기만 한다.
##   PIT: 신호일(월말 거래일) 종가까지의 자료로 만든 점수를, 다음 달 첫 거래일 ~ 마지막 거래일 수익과 맞댄다.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
data.table::setDTthreads(1L)   # R 세그폴트 가드(인프라 운영 규칙). arrow IO 스레드는 기본값(2 이상)을 유지한다 — 1 로 두면 read_parquet 가 멈춘다.
## PerformanceAnalytics 는 2.0.8 로 고정한다 — 2.1.0 은 Return.portfolio 의 출력 날짜와 Sharpe 기본값을 바꾼다(인프라 판 고정과 같은 이유).
if (as.character(utils::packageVersion("PerformanceAnalytics")) != "2.0.8")
  stop("[aif] PerformanceAnalytics 판이 2.0.8 이 아니다: ", as.character(utils::packageVersion("PerformanceAnalytics")))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
AIF_DIR_REL <- "04_Research/01_reports/ai_factor_research_20261122"

aif_root <- function() {
  r <- Sys.getenv("AIF_ROOT", ""); if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  r <- sub("/+$", "", gsub("\\\\", "/", r))            # 구분자만 맞춘다(경로 정규화 함수는 한글 경로를 깨뜨릴 수 있어 쓰지 않는다)
  if (!nzchar(r) || !dir.exists(file.path(r, "02_Infrastructure")))
    stop("[aif] 저장소 루트를 찾지 못했다(AIF_ROOT 또는 QM_ROOT)")
  r
}
aif_dir <- function(root = aif_root()) file.path(root, AIF_DIR_REL)
aif_cfg <- function(root = aif_root()) fromJSON(file.path(aif_dir(root), "aif_config.json"), simplifyVector = FALSE)
aif_out <- function(..., root = aif_root(), cfg = aif_cfg(root)) file.path(root, cfg$paths$out_cache, ...)
aif_results <- function(..., root = aif_root(), cfg = aif_cfg(root)) file.path(root, cfg$paths$results, ...)
aif_log <- function(...) cat(sprintf("[aif %s] %s\n", format(Sys.time(), "%H:%M:%S"), sprintf(...)))

## 확정 저장 — 임시 파일에 쓰고 이름을 바꾼다(쓰다 끊겨도 반쪽 파일이 남지 않는다)
aif_write_atomic <- function(path, write_fn) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  write_fn(tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("[aif] 이름 바꾸기 실패: ", path)
  invisible(path)
}
aif_write_json <- function(x, path) aif_write_atomic(path, function(p) writeLines(toJSON(x, auto_unbox = TRUE, digits = NA, null = "null", pretty = TRUE), p, useBytes = TRUE))

## parquet 의 날짜 열 → Date. 시각 없는 타임스탬프는 화면에 찍히는 날짜 그대로 읽는다(시간대 환산으로 하루 밀리는 것을 막는다).
aif_as_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(format(x, "%Y-%m-%d")))
  as.Date(as.character(x))
}

## ── 시장 자료 ────────────────────────────────────────────────────────────────
## 돌려주는 것(list):
##   dates(거래일) · tickers · R0(일별 수익 행렬 · 결측 = 0) · sig_dates(월말 신호일) · sig_idx(dates 안 위치)
##   hold_rng(신호 s 의 보유월 = 다음 달의 날짜 위치 범위) · hold_ok(보유월이 자료 안에서 끝났는가)
##   MEM(신호일 유니버스 멤버 · 신호 × 종목) · FWD[[h]](신호 뒤 h 개월 수익 · 신호 × 종목 · 첫 달 자료 없음 = NA)
##   bm(일별 벤치마크 수익) · rf(일별 무위험 수익) · ep(유니버스 epoch) · last_hold_end
aif_market <- function(root = aif_root(), cfg = aif_cfg(root), use_cache = TRUE) {
  src <- file.path(root, cfg$paths$rawdata)
  tag <- sprintf("%s_%s", format(file.mtime(src), "%Y%m%d%H%M%S"), file.size(src))
  cache <- aif_out("_scratch", sprintf("market_%s.rds", tag), root = root, cfg = cfg)
  if (use_cache && file.exists(cache)) { aif_log("시장 자료 캐시 사용: %s", basename(cache)); return(readRDS(cache)) }
  t0 <- Sys.time()
  env <- new.env()
  sys.source(file.path(root, cfg$universe$contract), envir = env, keep.source = FALSE)
  ep <- env$ma_epoch(NULL, root)
  start <- as.Date(ep$start_date)
  raw <- as.data.table(read_parquet(src, col_select = c("Date", "Ticker", "Close", "Vol", "Ret", "AdminStock", "TradingHalt", "UnfaithfulDisc")))
  raw[, Date := aif_as_date(Date)]
  raw <- raw[Date >= start - 90L]                    # 20거래일 평균 거래대금(전날까지) 계산용 앞 여유
  setkey(raw, Ticker, Date)
  raw[, mem := env$ma_membership(raw, ep)]           # 인프라 측정 축의 판정식 그대로
  raw <- raw[Date >= start]
  dates <- sort(unique(raw$Date)); tickers <- sort(unique(raw$Ticker))
  di <- match(raw$Date, dates); ti <- match(raw$Ticker, tickers)
  R <- matrix(NA_real_, length(dates), length(tickers), dimnames = list(NULL, tickers))
  R[cbind(di, ti)] <- raw$Ret
  HAS <- !is.na(R); R[!HAS] <- 0                     # 행이 없는 날(정지 · 폐지 뒤) = 수익 0(현금) 근사

  ## 달 · 월말 신호일. 마지막 달은 자료가 끝나지 않았을 수 있어 신호로 쓰지 않는다.
  ym <- format(dates, "%Y%m"); yms <- unique(ym); K <- length(yms)
  m_first <- as.integer(tapply(seq_along(dates), ym, min)[yms]); m_last <- as.integer(tapply(seq_along(dates), ym, max)[yms])
  ns <- K - 1L                                        # 신호 = 1..K-1 번째 달의 마지막 거래일
  sig_idx <- m_last[seq_len(ns)]; sig_dates <- dates[sig_idx]
  hold_rng <- cbind(a = m_first[2:K], b = m_last[2:K])
  hold_ok <- seq_len(ns) + 1L < K                     # 보유월(다음 달) 뒤에 달이 하나 더 있어야 끝난 달이다
  last_hold_end <- dates[max(hold_rng[hold_ok, "b"])]

  MEM <- matrix(FALSE, ns, length(tickers))
  rs <- raw[Date %in% sig_dates]
  MEM[cbind(match(rs$Date, sig_dates), match(rs$Ticker, tickers))] <- rs$mem %in% TRUE

  ## 달별 로그 수익(종목) · 그 달에 수익 행이 하나라도 있었는가
  LM <- matrix(0, ns, length(tickers)); HM <- matrix(FALSE, ns, length(tickers))
  for (s in seq_len(ns)) {
    rr <- hold_rng[s, "a"]:hold_rng[s, "b"]
    LM[s, ] <- colSums(log1p(R[rr, , drop = FALSE])); HM[s, ] <- colSums(HAS[rr, , drop = FALSE]) > 0L
  }
  FWD <- list()
  for (h in unlist(cfg$measure$ic_horizons_m)) {
    Fm <- matrix(NA_real_, ns, length(tickers))
    for (s in seq_len(ns)) {
      e <- s + h - 1L
      if (e > ns || !hold_ok[e]) next                 # 지평 끝 달까지 자료 안에서 끝나야 한다
      v <- if (h == 1L) LM[s, ] else colSums(LM[s:e, , drop = FALSE])
      v <- expm1(v); v[!HM[s, ]] <- NA_real_          # 첫 보유월에 수익 행이 없으면 맞댈 수익이 없다
      Fm[s, ] <- v
    }
    FWD[[as.character(h)]] <- Fm
  }
  rm(HAS, LM, HM, raw, rs); gc()

  bm <- as.data.table(read_parquet(file.path(root, cfg$paths$benchmark), col_select = c("Date", "BM_Ret")))
  bm[, Date := aif_as_date(Date)]
  if (anyDuplicated(bm$Date)) stop("[aif] 벤치마크 파일에 같은 날짜가 여러 줄이다(출처가 여럿?) — 한 출처만 남겨 읽어야 한다")
  bmv <- bm$BM_Ret[match(dates, bm$Date)]
  if (anyNA(bmv)) { aif_log("벤치마크 수익 결측 %d일 → 0 으로 둔다", sum(is.na(bmv))); bmv[is.na(bmv)] <- 0 }
  rf <- as.data.table(read_parquet(file.path(root, cfg$paths$rf), col_select = c("Date", "Series_ID", "Value")))
  rf <- rf[Series_ID == cfg$measure$rf_series_id][, Date := aif_as_date(Date)][order(Date)]
  if (!nrow(rf)) stop("[aif] 무위험 수익 계열 없음: ", cfg$measure$rf_series_id)
  ix <- findInterval(as.numeric(dates), as.numeric(rf$Date))                   # 그날까지의 마지막 값
  if (any(ix == 0L)) stop("[aif] 무위험 수익이 시작일 이전에 없다")
  y <- rf$Value[ix]
  if (anyNA(y)) stop("[aif] 무위험 수익 값 결측")
  rfv <- (1 + y / 100)^(1 / cfg$measure$days_per_year) - 1

  M <- list(dates = dates, tickers = tickers, R0 = R, sig_dates = sig_dates, sig_idx = sig_idx, hold_rng = hold_rng,
            hold_ok = hold_ok, last_hold_end = last_hold_end, MEM = MEM, FWD = FWD, bm = bmv, rf = rfv,
            ep = list(id = ep$id, start_date = as.character(start), liq_min = ep$liq_min, price_min = ep$price_min),
            source = list(rawdata = src, tag = tag, built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  aif_log("시장 자료: 거래일 %d(%s ~ %s) · 종목 %d · 신호 %d(%s ~ %s) · 완결 보유월 끝 %s · 멤버 평균 %.0f · %.0f초",
          length(dates), dates[1], dates[length(dates)], length(tickers), ns, sig_dates[1], sig_dates[ns], last_hold_end,
          mean(rowSums(MEM)), as.numeric(difftime(Sys.time(), t0, units = "secs")))
  if (use_cache) aif_write_atomic(cache, function(p) saveRDS(M, p, compress = FALSE))
  M
}

## 점수 패널(Date · Ticker · Score) → 신호 × 종목 행렬. 방향 -1 이면 부호를 뒤집어 '클수록 좋음'으로 맞춘다.
aif_score_matrix <- function(dt, M, direction = 1) {
  dt <- data.table(Date = aif_as_date(dt[[1]]), Ticker = as.character(dt[[2]]), Score = as.numeric(dt[[3]]))
  si <- match(dt$Date, M$sig_dates); ti <- match(dt$Ticker, M$tickers)
  nd <- uniqueN(dt$Date); nd_hit <- uniqueN(dt$Date[!is.na(si)])
  if (nd_hit < 0.9 * nd) {
    late <- sum(unique(dt$Date) > max(M$sig_dates))
    if (nd - nd_hit > late + 1L) stop(sprintf("[aif] 점수 날짜가 월말 신호일과 맞지 않는다(%d / %d 일치)", nd_hit, nd))
  }
  ok <- !is.na(si) & !is.na(ti) & is.finite(dt$Score)
  S <- matrix(NA_real_, length(M$sig_dates), length(M$tickers))
  S[cbind(si[ok], ti[ok])] <- direction * dt$Score[ok]
  attr(S, "match") <- list(dates = nd, dates_hit = nd_hit, rows = nrow(dt), rows_used = sum(ok))
  S
}
