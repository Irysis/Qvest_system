#!/usr/bin/env Rscript
# =============================================================================
# dpl_c2_quality_features.R — Qvest DPL cycle2: 추가 직교/방어 피처 R 산출.
#
# 90f base panel(WT_DPL_GPU_SWEEP)이 이미 momentum/value/quality(GPA·ROE·ROA)/
# accrual/consensus/defense/flow를 보유 → C2는 task가 명시한 *추가* 피처만 산출:
#   (1) PIOTROSKI : factor_engine_piotroski_f9.R  F-Score 0..9 (crisis 방어/quality 종합)
#   (2) MOHANRAM  : factor_engine_mohanram_g.R    G-Score 신호율 (저BM growth 방어)
#   (3) NETISSUE  : Net Equity Issuance = -Δlog(CapitalStock, YoY)  (Pontiff-Woodgate 2008;
#                   higher=better=주식 미발행/자사주, IN04 직교 LS t2.83 검증됨)
#                   ★ Piotroski F7(EQ_OFFER)의 연속판 — 분리 피처로 정보 추가.
#
# 출력: stage_artifacts/WT_DPL_C2/extra_scores.parquet (ym, Ticker, PIOTROSKI, MOHANRAM, NETISSUE)
#   month-end signal(t-known), cross-section z는 Python augment에서. 여기선 raw score.
#
# PIT: 각 엔진은 Factor_Date <= sig_date 만 사용(C4 재무 lag 반영). NETISSUE도 동일.
#   universe/period 필터는 augment merge(90f base가 K200∪KQ150·2005~ 이미 적용)에서 흡수.
#
# 실행(무거움 — fundamental 5.4M rows): PowerShell run_in_background 권장.
#   $env:QM_ROOT="G:/Quant_Module_Moltbot"; Rscript dpl_c2_quality_features.R
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))

ROOT  <- Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
INFRA <- file.path(ROOT, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))
OUT <- file.path(ROOT, "stage_artifacts", "WT_DPL_C2")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ---- RAWDATA + LiqPass (build_alphasearch_feature_panel.R 패턴 동일) ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
cat(sprintf("[c2-feat] RAWDATA rows=%d tickers=%d\n", nrow(RAWDATA), uniqueN(RAWDATA$Ticker)))

ymk <- function(d) format(as.Date(d), "%Y-%m")

# ── (1) Piotroski F-Score ────────────────────────────────────────────
cat("[c2-feat] (1) Piotroski F9 ...\n")
FE_DIR <- file.path(INFRA, "alpha_search")
FACTORS <- NULL
source(file.path(FE_DIR, "factor_engine_piotroski_f9.R"), local = TRUE)
pio <- copy(FACTORS); FACTORS <- NULL
pio <- pio[is.finite(Score), .(ym = ymk(Date), Ticker, PIOTROSKI = as.numeric(Score))]
cat(sprintf("[c2-feat]   Piotroski rows=%d months=%d tickers=%d\n",
            nrow(pio), uniqueN(pio$ym), uniqueN(pio$Ticker)))

# ── (2) Mohanram G-Score ─────────────────────────────────────────────
cat("[c2-feat] (2) Mohanram G ...\n")
FACTORS <- NULL
source(file.path(FE_DIR, "factor_engine_mohanram_g.R"), local = TRUE)
moh <- copy(FACTORS); FACTORS <- NULL
moh <- moh[is.finite(Score), .(ym = ymk(Date), Ticker, MOHANRAM = as.numeric(Score))]
cat(sprintf("[c2-feat]   Mohanram rows=%d months=%d tickers=%d\n",
            nrow(moh), uniqueN(moh$ym), uniqueN(moh$Ticker)))

# ── (3) Net Equity Issuance = -Δlog(CapitalStock) YoY (Pontiff-Woodgate) ──
cat("[c2-feat] (3) Net Equity Issuance (-dlog shares YoY, PIT Factor_Date<=sig) ...\n")
FUND <- file.path(ROOT, ".cache", "fundamental_merged.parquet")
fd <- as.data.table(read_parquet(FUND, col_select = c("Ticker","Period","Factor_Date","Item","Value")))
fd <- fd[Item == "CapitalStock" & is.finite(Value) & Value > 0]
# 동일 (Ticker,Period)에 복수 Source → Factor_Date 가장 이른 행 1개 (가장 먼저 가용)
setorder(fd, Ticker, Period, Factor_Date)
fd <- fd[, .SD[1], by = .(Ticker, Period)]
setorder(fd, Ticker, Period)
# YoY = 4분기 전 (Period 분기 가정). log 변화. 발행(↑ shares)= 음의 alpha → 부호반전(higher=better)
fd[, shares_lag4 := shift(Value, 4L), by = Ticker]
fd[, dlog_shares := log(Value) - log(shares_lag4)]
fd[, NETISSUE_raw := -dlog_shares]                # higher = 미발행/감자 = 우량(Pontiff-Woodgate)
iss <- fd[is.finite(NETISSUE_raw) & is.finite(Factor_Date),
          .(Ticker, Factor_Date, NETISSUE_raw)]
setorder(iss, Ticker, Factor_Date)

# 월말 sig_date에 PIT rolling join (Factor_Date <= sig_date 중 최신) — Piotroski 패턴 동일
RAWDATA[, .ym := format(Date, "%Y-%m")]
month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
grid <- CJ(Ticker = unique(iss$Ticker), Date = month_ends)
setkey(iss, Ticker, Factor_Date); setkey(grid, Ticker, Date)
issm <- iss[grid, on = .(Ticker, Factor_Date = Date), roll = TRUE,
            .(Ticker, Date = Factor_Date, NETISSUE_raw)]
issm <- issm[is.finite(NETISSUE_raw)]
# 유동성 통과 종목만 (다른 피처와 universe 정합)
liq <- RAWDATA[Date %in% month_ends & LiqPass == TRUE, .(Date, Ticker)]
issm <- merge(issm, liq, by = c("Date","Ticker"))
iss_out <- issm[, .(ym = ymk(Date), Ticker, NETISSUE = NETISSUE_raw)]
RAWDATA[, .ym := NULL]
cat(sprintf("[c2-feat]   NetIssue rows=%d months=%d tickers=%d (mean=%.4f sd=%.4f)\n",
            nrow(iss_out), uniqueN(iss_out$ym), uniqueN(iss_out$Ticker),
            mean(iss_out$NETISSUE), sd(iss_out$NETISSUE)))

# ── merge 3 scores (full outer on ym,Ticker) ─────────────────────────
extra <- Reduce(function(a,b) merge(a, b, by = c("ym","Ticker"), all = TRUE),
                list(pio, moh, iss_out))
setorder(extra, ym, Ticker)
write_parquet(extra, file.path(OUT, "extra_scores.parquet"))
cat(sprintf("\n[c2-feat] extra_scores rows=%d | PIOTROSKI nNA=%d MOHANRAM nNA=%d NETISSUE nNA=%d\n",
            nrow(extra), sum(is.na(extra$PIOTROSKI)), sum(is.na(extra$MOHANRAM)), sum(is.na(extra$NETISSUE))))
cat(sprintf("[c2-feat] -> %s\n", file.path(OUT, "extra_scores.parquet")))
