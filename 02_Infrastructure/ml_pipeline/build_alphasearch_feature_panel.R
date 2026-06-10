#!/usr/bin/env Rscript
# =============================================================================
# build_alphasearch_feature_panel.R
#   alpha-search factor_engine들의 Score를 DPL feature panel로 빌드.
#   (measurement-graduation §5: 실패 alpha = DPL 입력 feature / research_philosophy ④)
#
# 출력: stage_artifacts/WT_DPL_ALPHASEARCH/dpl_feature_panel.parquet
#   컬럼: ym(str) | Ticker | {alpha}__lvl ×N | Ret_1m(forward 1M)
#   (dpl_gpu_sweep.py load_panel()이 "__lvl/__slp/__vol" suffix로 feature 인식)
# + benchmark_monthly.parquet (기존 WT_DPL_GPU_SWEEP에서 복사 — 동일 KOSPI200 정의)
#
# PIT: feature=월말 Score(과거 윈도우), label=forward 1M(shift lead). DPL이 walk-forward split.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))

ROOT  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(ROOT, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))

# ---- RAWDATA + LiqPass (run_alpha_search 패턴 복제) ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

# ---- alpha-search factor engines (가격기반 RAWDATA-only PoC 8종) ----
FE_DIR <- file.path(INFRA, "alpha_search")
fe_map <- c(
  mom12_1   = "fe_mom12_1.R",
  mom6_1    = "fe_mom6_1.R",
  streversal= "fe_streversal.R",
  lowvol    = "fe_lowvol.R",
  turnover  = "fe_turnover.R",
  amihud    = "fe_amihud.R",
  mom52wlow = "fe_mom52wlow.R",
  # --- 신호 검증 알파만 (IC 양 + FMB 유의). 노이즈(varratio/seasonality/dbeta) 제거 ---
  coskew      = "fe_coskew.R",        # 동조왜도 (Harvey-Siddique, FMB t2.16)
  high52w     = "fe_52whigh.R",       # 52주고점 (George-Hwang, IR+ Sharpe최고)
  volpremium  = "fe_volpremium.R",    # 고거래량 (GKM, FMB t1.89)
  rskew       = "fe_rskew.R"          # 실현왜도 (skew preference, FMB t2.99 최강)
)

panels <- list()
for (nm in names(fe_map)) {
  FACTORS <- NULL
  ok <- tryCatch({ source(file.path(FE_DIR, fe_map[[nm]]), local = TRUE); TRUE },
                 error = function(e) { cat("[FAIL]", nm, "::", conditionMessage(e), "\n"); FALSE })
  if (!ok || is.null(FACTORS) || !is.data.table(FACTORS)) next
  if (!all(c("Date","Ticker","Score") %in% names(FACTORS))) { cat("[SKIP]", nm, "no Score\n"); next }
  f <- FACTORS[is.finite(Score), .(Date, Ticker, v = as.numeric(Score))]
  setnames(f, "v", paste0(nm, "__lvl"))
  panels[[nm]] <- f
  cat(sprintf("[OK] %-10s rows=%d\n", nm, nrow(f)))
}
stopifnot(length(panels) >= 2)

panel <- Reduce(function(a, b) merge(a, b, by = c("Date","Ticker"), all = TRUE), panels)

# ---- forward 1M return (month-end close, PIT forward = shift lead) ----
me  <- RAWDATA[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date
mec <- RAWDATA[Date %in% me, .(Date, Ticker, Close)]
setorder(mec, Ticker, Date)
mec[, Ret_1m := shift(Close, n = 1L, type = "lead") / Close - 1, by = Ticker]   # forward
panel <- merge(panel, mec[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)

# ---- universe = K200∪KQ150 (alpha-search 제1원칙) + 기간 2005~ 고정 ----
mem <- unique(RAWDATA[(K200 == TRUE | KQ150 == TRUE) & Date >= as.Date("2005-01-01"),
                      .(Date, Ticker)])
panel <- merge(panel, mem, by = c("Date","Ticker"))

panel[, ym := format(Date, "%Y-%m")]
feat_cols <- grep("__lvl$", names(panel), value = TRUE)
for (cc in feat_cols) set(panel, which(is.na(panel[[cc]])), cc, 0)   # 결측 feature = 0(중립 z)
panel <- panel[is.finite(Ret_1m)]

OUT <- file.path(ROOT, "stage_artifacts", "WT_DPL_ALPHASEARCH")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
out_cols <- c("ym", "Ticker", feat_cols, "Ret_1m")
write_parquet(panel[, ..out_cols], file.path(OUT, "dpl_feature_panel.parquet"))

# benchmark 재사용 (동일 KOSPI200 월간 정의)
src_bm <- file.path(ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP", "benchmark_monthly.parquet")
if (file.exists(src_bm)) file.copy(src_bm, file.path(OUT, "benchmark_monthly.parquet"), overwrite = TRUE)

cat(sprintf("\n[panel] rows=%d | feats=%d | months=%d | tickers=%d\n  -> %s\n",
            nrow(panel), length(feat_cols), uniqueN(panel$ym), uniqueN(panel$Ticker), OUT))
cat("feat_cols:", paste(feat_cols, collapse = ", "), "\n")
