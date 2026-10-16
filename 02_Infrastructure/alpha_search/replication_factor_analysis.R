## replication_factor_analysis.R — 충실구현 산출물의 팩터 분석(파마-맥베스 · FF3/FF5/Carhart) 사후 실행 · 보고 섹션
##   (도훈 2026-10-16 "파마맥베스 회귀로 알파의 통계적 유의성 검증해서 보내주던 메세지 누락된거 다시 살려줘")
##
## 왜: 러너(run_paper_replication.R 7-b)는 엔진이 종목 점수(FACTORS)를 낼 때만 분석기(strategy_analyzer.R::run_analysis)를 돈다.
##   10-05 뒤 충실구현 11건은 전부 비중(PORTFOLIO)만 내는 엔진이라 '팩터분석 생략 — FACTORS 부재'로 건너뛰었고, [팩터 분석]이 끊겼다
##   (마지막 산출 20261005_170345_8524 · 레인 로그 · .cache/reinforce_auto_log.jsonl factor_analysis_absent).
## 무엇: 산출물(04_holdings · 03_period_returns · 05_benchmark_returns · authoritative_remeasure 의 측정 축)로 분석기 입력을 복원해
##   **같은 분석기**를 돈다. 점수 = 그 신호일의 보유 비중 — 측정 축 유니버스(K200/KQ150 플래그 = 1 · ALL_HYG 면 위생 멤버십 주입)의
##   비보유 종목은 0. 신호일 = 집행일 직전 거래일(holdings 의 date 는 집행일 — 비중은 신호일 정보로 정해졌다 · PIT).
##   파마-맥베스 기울기 = '더 많이 담은 종목이 다음 기간에 더 벌었나'(분석기 정의: 다음 리밸까지 수익 ~ 점수 + 규모 + 12개월 모멘텀 · NW t).
##   롱숏 논문이면 공매도 비중이 음수 점수가 된다.
## 경계: 진단이다 — 권위 등급 · 측정 산출물을 바꾸지 않는다(산출물 폴더에 analysis_* · analysis_basis.json 을 더할 뿐).
##   알파가 있다는 주장은 β-통제 α t 로만 한다(측정 규범 §2). 러너가 이미 분석했으면(점수형 엔진) 다시 돌지 않는다.
## 사용: Rscript replication_factor_analysis.R <산출물 폴더>         (검증 단계 rf_replication_verify.R 가 부른다 · 별도 프로세스)
##       source 하면 rfa_section(art) — prep_send extra 섹션 1개(파마-맥베스 · FF 알파 · 진단 표기 · 미산출 사유)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RFA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

rfa_has_outputs <- function(art) file.exists(file.path(art, "analysis_fmb_summary.csv")) || file.exists(file.path(art, "analysis_multifactor.csv"))
rfa_basis_path <- function(art) file.path(art, "analysis_basis.json")
.rfa_write_basis <- function(art, x) writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), rfa_basis_path(art), useBytes = TRUE)

## 보유 비중 점수판 — H(집행일 date · ticker · 비중 w) · RAW(Date · Ticker · K200 · KQ150) → data.table(Date = 신호일, Ticker, Score)
##   신호일 = 집행일 직전 거래일(RAW 달력) · 그날 유니버스(K200 또는 KQ150 = 1) 전부 + 보유 종목 · 점수 = 비중(비보유 0)
rfa_weight_scores <- function(H, RAW) {
  cal <- sort(unique(RAW$Date))
  ex <- sort(unique(as.Date(H$date)))
  i <- findInterval(as.numeric(ex) - 1, as.numeric(cal))
  map <- data.table(date = ex, sig = as.Date(ifelse(i >= 1L, as.numeric(cal[pmax(i, 1L)]), NA_real_), origin = "1970-01-01"))[!is.na(sig)]
  if (!nrow(map)) return(list(scores = data.table(Date = as.Date(character(0)), Ticker = character(0), Score = numeric(0)), map = map))
  U <- RAW[.(unique(map$sig)), on = "Date", nomatch = 0L][(K200 %in% c(1, TRUE)) | (KQ150 %in% c(1, TRUE)), .(Date, Ticker)]
  Hs <- merge(as.data.table(H)[, .(date = as.Date(date), Ticker = ticker, w = as.numeric(w))], map, by = "date")[is.finite(w) & w != 0, .(Date = sig, Ticker, w)]
  Hs <- Hs[, .(w = sum(w)), by = .(Date, Ticker)]
  S <- merge(unique(U), Hs, by = c("Date", "Ticker"), all = TRUE)
  S[is.na(w), w := 0]
  list(scores = S[, .(Date, Ticker, Score = w)], map = map)
}

rfa_run <- function(art, root = RFA_ROOT) {
  t0 <- Sys.time()
  if (rfa_has_outputs(art)) {
    if (!file.exists(rfa_basis_path(art)))
      .rfa_write_basis(art, list(basis = "engine_score", status = "runner", note = "러너(점수형 엔진)가 분석 — 점수 = 엔진 점수", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))
    return(invisible("runner"))
  }
  need <- file.path(art, c("04_holdings.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "authoritative_remeasure.json"))
  if (!all(file.exists(need))) {
    .rfa_write_basis(art, list(basis = NA, status = "skipped", reason = paste("산출물 없음:", paste(basename(need[!file.exists(need)]), collapse = ","))))
    return(invisible("skipped"))
  }
  setwd(root); Sys.setenv(QM_ROOT = root, CLAUDE_PROJECT_DIR = root)
  infra <- file.path(root, "02_Infrastructure")
  invisible(capture.output(suppressMessages({
    source(file.path(infra, "config.R")); source(file.path(infra, "backtest_harness.R"))
    source(file.path(infra, "contracts/measurement_axis.R")); source(file.path(infra, "strategy_analyzer.R"))
  })))
  ar <- fromJSON(file.path(art, "authoritative_remeasure.json"), simplifyVector = FALSE)
  uni <- as.character(ar$measurement_axis$universe %||% "K200_KQ150"); ep_id <- ar$measurement_axis$epoch %||% NULL
  res <- load_rawdata(use_cache = TRUE); RAW <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  mem_med <- NA_real_
  if (identical(uni, "ALL_HYG")) {
    ep <- if (!is.null(ep_id)) ma_epoch(ep_id, root = root) else ma_epoch_by_universe("ALL_HYG", root = root)
    inj <- ma_inject_universe(RAW, ep); RAW <- inj$RAWDATA; mem_med <- inj$diag$members_per_day_median; rm(inj)
  }
  H <- fread(file.path(art, "04_holdings.csv"), colClasses = list(character = "ticker"))
  wc <- intersect(c("target_weight", "actual_weight"), names(H))[1]
  H <- H[, .(date = as.Date(date), ticker, w = as.numeric(get(wc)))]
  ws <- rfa_weight_scores(H, RAW)
  if (length(unique(ws$scores$Date)) < 6L) {
    .rfa_write_basis(art, list(basis = "holding_weight", status = "skipped", reason = sprintf("신호일 %d개 — 파마-맥베스 집계 최소 6개 미만", length(unique(ws$scores$Date)))))
    return(invisible("skipped"))
  }
  pr <- fread(file.path(art, "03_period_returns.csv")); pr[, date := as.Date(date)]; setorder(pr, date)
  br <- fread(file.path(art, "05_benchmark_returns.csv")); br[, date := as.Date(date)]; setorder(br, date)
  HL <- merge(H[is.finite(w) & w != 0], ws$map, by = "date")[, .(Date = date, Signal_Date = sig, Ticker = ticker, Weight = w)]
  sim <- list(strategy_xts = xts::xts(pr$ret_net, order.by = pr$date), bm_xts = xts::xts(br$benchmark_ret, order.by = br$date),
              PORTFOLIO_LOG = NULL, HOLDINGS_LOG = HL)
  assign("FUNC_PATH", infra, envir = globalenv())                      # 분석기의 factor_portfolios.R 경로(러너 7-b 경계 어댑터 ② 와 같다)
  st <- tryCatch({ run_analysis(sim, ws$scores, RAW, BM_DT, output_dir = art, strategy_name = basename(art)); "ran" },
                 error = function(e) paste("failed:", conditionMessage(e)))
  .rfa_write_basis(art, list(basis = "holding_weight", status = if (identical(st, "ran")) "ran" else "failed", reason = if (identical(st, "ran")) NULL else st,
                             universe = uni, epoch = ep_id, members_per_day_median = mem_med, n_signal_dates = length(unique(ws$scores$Date)),
                             fmb_written = file.exists(file.path(art, "analysis_fmb_summary.csv")), ff_written = file.exists(file.path(art, "analysis_multifactor.csv")),
                             note = "점수 = 신호일(집행일 직전 거래일) 보유 비중 · 측정 축 유니버스의 비보유 종목 = 0 · 분석기 = strategy_analyzer.R::run_analysis",
                             secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))
  invisible(st)
}

## ── 보고 섹션(prep_send extra) — 파마-맥베스 · FF3/FF5/Carhart 알파 · 진단 표기(발송 규칙 §0.2 — 등급 글자 대신 ★유의) · 미산출 사유 ──
.rfa_num <- function(x, d = 2L) { x <- suppressWarnings(as.numeric(x)); if (!length(x) || !is.finite(x)) "—" else sub("^-", "−", formatC(x, format = "f", digits = d)) }
rfa_section <- function(art) {
  b <- tryCatch(fromJSON(rfa_basis_path(art), simplifyVector = FALSE), error = function(e) list())
  basis_txt <- if (identical(b$basis, "holding_weight")) "점수 = 보유 비중 · 비보유 0" else "점수 = 엔진 점수"
  items <- character(0)
  fs <- file.path(art, "analysis_fmb_summary.csv")
  if (file.exists(fs)) {
    d <- tryCatch(fread(fs), error = function(e) data.table())
    s <- if (nrow(d) && "Variable" %in% names(d)) d[Variable == "Score"] else data.table()
    nd <- tryCatch(nrow(fread(file.path(art, "analysis_fmb.csv"))), error = function(e) NA_integer_)
    if (nrow(s)) {
      t <- as.numeric(s$t_stat_NW[1])
      items <- c(items, sprintf("파마-맥베스(%s · 규모 · 12개월 모멘텀 통제 · 신호일 %s): 기울기 %s · NW t %s · %s · 평균 R² %s",
                                basis_txt, if (is.finite(nd)) format(nd) else "—", .rfa_num(s$Lambda_Mean[1], 5L), .rfa_num(t),
                                if (is.finite(t) && abs(t) >= 1.96) "★유의(|t| ≥ 1.96)" else "비유의", .rfa_num(s$Avg_R2[1], 3L)))
    }
  }
  fm <- file.path(art, "analysis_multifactor.csv")
  if (file.exists(fm)) {
    d <- tryCatch(fread(fm), error = function(e) data.table())
    if (nrow(d) && all(c("Model", "Alpha_Annual_Pct", "Alpha_tstat") %in% names(d)))
      items <- c(items, vapply(seq_len(nrow(d)), function(j) sprintf("%s 알파 %s%%/년 · t %s · %s%s", d$Model[j], .rfa_num(d$Alpha_Annual_Pct[j], 1L), .rfa_num(d$Alpha_tstat[j]),
                                                                  if (abs(as.numeric(d$Alpha_tstat[j])) >= 1.96) "★유의" else "비유의",
                                                                  if ("Adj_R2" %in% names(d)) paste0(" · 수정 R² ", .rfa_num(d$Adj_R2[j])) else ""), character(1)))
  }
  if (!length(items)) items <- sprintf("산출 안 됨 — %s", b$reason %||% if (identical(b$status, "failed")) "분석기 실패" else "분석 산출물 없음")
  items <- c(items, "진단이다 — 권위 등급이 아니고, 알파가 있다는 주장은 β-통제 α t 로만 한다(측정 규범 §2)")
  list(list(type = "bullet", heading = "팩터 분석 — 알파 유의성(진단)", items = items))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (!length(a) || !dir.exists(a[1])) { cat("usage: Rscript replication_factor_analysis.R <산출물 폴더>\n"); quit(status = 2L) }
  st <- tryCatch(rfa_run(gsub("\\\\", "/", a[1])), error = function(e) { cat("[rfa] 실패:", conditionMessage(e), "\n"); "failed" })
  cat(sprintf("[rfa] %s · %s\n", st, a[1]))
  quit(status = if (identical(st, "failed")) 1L else 0L)
}
