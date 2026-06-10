#!/usr/bin/env Rscript
# =============================================================================
# leadlag_multihorizon_ic.R — Price lead-lag 신호의 horizon 진단 (소멸 vs 부재)
# -----------------------------------------------------------------------------
# 배경: probe1(fe_leadlag_network, 월간 long-only top25)은 직교성 PASS(return_cor
#   vs STR_1715 = 0.07, eigenmode-1 탈출)였으나 알파 DEAD(월간 IC≈0, PORT_t −0.08).
#   메모리(project-longonly-relational-alpha) 미해결 질문: "월간 IC=0은 신호의
#   *소멸(decay)*인가 *부재(absence)*인가? multi-horizon IC로 cheap 확인 가능."
#
# 본 진단: 동일 lead-lag 신호(월말 산출)를 *여러 forward horizon*(1/5/10/21/63 거래일)
#   에 대해 횡단면 rank-IC로 측정.
#   - decay 패턴 (h작을수록 IC↑, h커질수록 →0): 신호 실재하나 빠르게 소멸
#       → 짧은 horizon에 살아있는 직교 알파 가능성 (단 turnover 제약과 충돌).
#   - absence 패턴 (전 h에서 IC≈0): 신호 자체 없음 → 관계형 분기 공식 종료.
#
# ★ PIT/방법론: forward 수익은 *평가*용 IC(신호 t vs 실현 미래수익) — lookahead 아님.
#   신호 자체는 fe_leadlag_network가 t까지 데이터로만 생성(probe1서 detect_lookahead PASS).
#   forward return: data_table_shift_convention.md 준수 shift(Close, n=H, type="lead").
#   유니버스: run_alpha_search 동일 K200∪KQ150 멤버십(PIT 시변) + LiqPass.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))   # load_rawdata 정의
`%||%` <- function(a,b) if(is.null(a)||length(a)==0L||(length(a)==1L&&is.na(a))) b else a

# ---- 1. Data (run_alpha_search 동일) ----------------------------------------
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
LIQ <- 2e8
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ]
START <- as.Date("2005-01-01")   # 표준 백테 시작(도훈 mandate)

# ---- 2. forward h-day 수익 (평가용; per-ticker lead) -------------------------
HORIZONS <- c(1L, 5L, 10L, 21L, 63L)
setorder(RAWDATA, Ticker, Date)
for (h in HORIZONS)
  RAWDATA[, (paste0("fwd", h)) := shift(Close, n = h, type = "lead") / Close - 1, by = Ticker]  # FORWARD (convention)

# ---- 3. lead-lag 신호 (fe_leadlag_network 재사용; 월말 Date/Ticker/Score) ----
source(file.path(INFRA, "alpha_search", "fe_leadlag_network.R"))   # → FACTORS
stopifnot(exists("FACTORS"), nrow(FACTORS) > 0L)
FACTORS <- FACTORS[Date >= START]

# ---- 4. 유니버스 K200∪KQ150 멤버십 (PIT 시변) -------------------------------
stopifnot(all(c("K200","KQ150") %in% names(RAWDATA)))
.me <- unique(FACTORS$Date)
.mem <- unique(RAWDATA[Date %in% .me & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
FACTORS <- merge(FACTORS, .mem, by = c("Date","Ticker"))
cat(sprintf("[ll-ic] signal rows=%d | dates=%d | tickers=%d (K200∪KQ150)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# ---- 5. forward 수익 merge + 횡단면 rank-IC per date per horizon -------------
FWD <- RAWDATA[Date %in% .me, c("Date","Ticker", paste0("fwd", HORIZONS)), with = FALSE]
D <- merge(FACTORS, FWD, by = c("Date","Ticker"))

ic_by_h <- list()
for (h in HORIZONS) {
  fc <- paste0("fwd", h)
  per_date <- D[is.finite(Score) & is.finite(get(fc)),
                .(ic = if (.N >= 20L) suppressWarnings(cor(Score, get(fc), method = "spearman")) else NA_real_,
                  n = .N), by = Date]
  ic_v <- per_date[is.finite(ic), ic]
  nd <- length(ic_v)
  mean_ic <- mean(ic_v); sd_ic <- sd(ic_v)
  tstat <- if (nd >= 2 && is.finite(sd_ic) && sd_ic > 0) mean_ic / sd_ic * sqrt(nd) else NA_real_
  icir  <- if (is.finite(sd_ic) && sd_ic > 0) mean_ic / sd_ic else NA_real_
  ic_by_h[[as.character(h)]] <- list(
    horizon_days = h, mean_ic = round(mean_ic,4), ic_tstat = round(tstat,3),
    icir = round(icir,4), hit_rate = round(mean(ic_v > 0),3),
    n_dates = nd, avg_breadth = round(mean(per_date$n),1))
}

# ---- 6. 평결: decay vs absence ----------------------------------------------
mic <- sapply(HORIZONS, function(h) ic_by_h[[as.character(h)]]$mean_ic)
tv  <- sapply(HORIZONS, function(h) ic_by_h[[as.character(h)]]$ic_tstat)
any_sig <- any(abs(tv) >= 2, na.rm = TRUE)
short_strong <- (abs(mic[1]) > abs(mic[length(mic)])) && abs(mic[1]) > 0.02   # 단기>장기 & 단기 비미미
verdict <- if (!any_sig && max(abs(mic), na.rm=TRUE) < 0.02) "ABSENCE — 전 horizon IC≈0, 신호 부재 → 관계형 분기 종료" else
           if (short_strong || (any_sig && which.max(abs(mic)) <= 2)) "DECAY — 단기 horizon에 신호 실재, 빠르게 소멸 → 짧은 horizon 직교알파 가능성(turnover 검토)" else
           "MIXED/WEAK — 명확한 decay도 absence도 아님; 정직 보고"

out <- list(schema_version="v1.0", generated=as.character(Sys.Date()),
  signal="fe_leadlag_network (price lead-lag network momentum)",
  method="cross-sectional Spearman rank-IC of month-end signal vs forward h-day returns. PIT: 신호 t까지·forward는 평가용.",
  universe="K200_KQ150 membership (PIT)", start=as.character(START),
  horizons_days=HORIZONS, ic_by_horizon=ic_by_h,
  verdict=verdict,
  open_question_resolved="월간 IC=0의 정체(decay vs absence)")
dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
write_json(out, file.path(PROJ,"04_Research/factor_rotation/output/leadlag_multihorizon_ic.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)

cat("\n==== lead-lag 신호 multi-horizon rank-IC (소멸 vs 부재) ====\n")
cat(sprintf("%-8s %10s %10s %8s %9s %8s\n","horizon","mean_IC","IC_tstat","ICIR","hit_rate","n_dates"))
for (h in HORIZONS) { x <- ic_by_h[[as.character(h)]]
  cat(sprintf("%-8s %10.4f %10.3f %8.4f %9.3f %8d\n",
      paste0(h,"d"), x$mean_ic, x$ic_tstat %||% NA, x$icir %||% NA, x$hit_rate, x$n_dates)) }
cat(sprintf("\n★ 평결: %s\n", verdict))
