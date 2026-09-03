# S1 — 패널 구축 (WT-R20260829_005 · AMP2013 value-momentum 점수수준 결합)
#  momentum  : 기저 fe_jt1993_momentum.R (J=6, skip 1M) 승계 = primary(6-1)
#              + AMP2013 원문 MOM2-12 (t-2..t-13) = paper-fidelity arm
#  value     : V01_BM (BE/ME, contemporaneous ME) — load_month_factors() 경유 (C15)
#              + FAL-1 분해용 자체계산 BM 2사양 (contemporaneous ME / price-lagged ME)
#  PIT       : 모멘텀 형성 = shift 로 과거만. 재무 = Factor_Date <= sig_date (C4).
#              유동성 = 20일 평균 거래대금 t-1 (C10). 팩터 = load_month_factors (C15/C13/C14).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

t0 <- Sys.time()
rl <- load_rawdata(use_cache = TRUE)
RAWDATA <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date"))   BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= as.Date("2002-06-01")]   # 12-1 형성 + 14M ME lag 여유
gc(verbose = FALSE)

## ── 모멘텀 2 arm (사전등록 병기) ─────────────────────────────────────────────
rd <- RAWDATA[is.finite(Ret), .(Date, Ticker, Ret)]
setorder(rd, Ticker, Date)
rd[, ym := format(Date, "%Y-%m")]
me_set <- sort(unique(rd[, .(me = max(Date)), by = ym]$me))
mret <- rd[, .(mr = prod(1 + Ret) - 1), by = .(Ticker, ym)]
setorder(mret, Ticker, ym)
rm(rd); gc(verbose = FALSE)

acc <- function(dt, kmin, kmax, nm_s, nm_n) {
  dt[, (nm_s) := {
    s <- rep(0, .N); for (k in kmin:kmax) { xx <- shift(mr, k); s <- s + fifelse(is.finite(xx), log(1 + pmax(xx, -0.999)), 0) }; s
  }, by = Ticker]
  dt[, (nm_n) := {
    c0 <- rep(0L, .N); for (k in kmin:kmax) c0 <- c0 + as.integer(is.finite(shift(mr, k))); c0
  }, by = Ticker]
  dt
}
mret <- acc(mret, 2L, 7L,  "mom61",  "n61")    # 기저 승계 (J=6, skip 1M)
mret <- acc(mret, 2L, 13L, "mom121", "n121")   # AMP2013 MOM2-12
ym_me <- data.table(ym = format(me_set, "%Y-%m"), Date = me_set)
MOM <- merge(mret[n61 == 6L | n121 == 12L,
                  .(ym, Ticker, mom61 = fifelse(n61 == 6L, mom61, NA_real_),
                    mom121 = fifelse(n121 == 12L, mom121, NA_real_))],
             ym_me, by = "ym")[, ym := NULL]
MOM <- MOM[Date >= as.Date("2005-01-01")]
cat(sprintf("[S1] MOM: %d rows · %d months · mom61 %.1f%% · mom121 %.1f%%\n",
            nrow(MOM), uniqueN(MOM$Date), 100*mean(is.finite(MOM$mom61)), 100*mean(is.finite(MOM$mom121))))

## ── 유니버스 (K200 ∪ KQ150 · PIT 시변) + 시장 라벨 ──────────────────────────
ME <- sort(unique(MOM$Date)); ME <- ME[ME >= as.Date("2005-01-01")]
mem <- unique(RAWDATA[Date %in% ME & (K200 == TRUE | KQ150 == TRUE),
                      .(Date, Ticker, mkt = fifelse(K200 == TRUE, "K200", "KQ150"))])
cat(sprintf("[S1] universe: %d months · median names %.0f\n", uniqueN(mem$Date), median(mem[, .N, by = Date]$N)))

## ── 자체계산 BE/ME 2사양 (FAL-1 기계/경제 분해) ─────────────────────────────
##   BE  = fundamental_merged 의 TotalEquity, Factor_Date <= sig_date (C4 규약 그대로)
##   (a) contemporaneous ME  = Size(월말 t)             ← AMP2013 주식 정의
##   (b) price-lagged   ME   = Size(월말 t-14)          ← 두 신호가 어떤 가격관측도 공유 X
##       (12-1 형성창이 t-2..t-13 이므로 t-14 로 잡아야 완전 비공유)
FUNDP <- file.path(CACHE_DIR, "fundamental_merged.parquet")
FE <- as.data.table(open_dataset(FUNDP, format = "parquet") |>
        dplyr::filter(Item == "TotalEquity") |>
        dplyr::select(Ticker, Factor_Date, Value) |> dplyr::collect())
FE[, Factor_Date := as.Date(Factor_Date)]
FE <- FE[is.finite(Value) & Value > 0]
setorder(FE, Ticker, Factor_Date)
cat(sprintf("[S1] TotalEquity rows=%d · tickers=%d · Factor_Date %s..%s\n",
            nrow(FE), uniqueN(FE$Ticker), min(FE$Factor_Date), max(FE$Factor_Date)))

SIZE_ALL <- RAWDATA[Date %in% ME & is.finite(Size) & Size > 0, .(Date, Ticker, Size)]
setorder(SIZE_ALL, Ticker, Date)
SIZE_ALL[, midx := match(Date, ME)]
SIZE_LAG <- copy(SIZE_ALL)[, .(Ticker, midx_t = midx + 14L, Size_lag14 = Size)]
SIZE_J <- merge(SIZE_ALL[, .(Date, Ticker, midx, Size)],
                SIZE_LAG, by.x = c("Ticker","midx"), by.y = c("Ticker","midx_t"), all.x = TRUE)

# PIT rolling join: 각 sig_date 에서 Factor_Date <= sig_date 인 최신 TotalEquity
grid <- CJ(Ticker = unique(SIZE_J$Ticker), Date = ME)
setkey(FE, Ticker, Factor_Date)
BEj <- FE[grid, on = .(Ticker, Factor_Date = Date), roll = TRUE, mult = "last",
          .(Ticker, Date = Factor_Date, BE = Value, BE_asof = x.Factor_Date)]
BM <- merge(SIZE_J, BEj[is.finite(BE)], by = c("Ticker","Date"))
BM[, `:=`(bm_a = BE / Size, bm_b = fifelse(is.finite(Size_lag14), BE / Size_lag14, NA_real_))]
BM <- BM[is.finite(bm_a), .(Date, Ticker, BE, Size, Size_lag14, bm_a, bm_b)]
cat(sprintf("[S1] self-BM: %d rows · bm_b 가용 %.1f%%\n", nrow(BM), 100*mean(is.finite(BM$bm_b))))

## ── V01_BM (권위 경로: load_month_factors) ──────────────────────────────────
vlist <- vector("list", length(ME))
for (i in seq_along(ME)) {
  vlist[[i]] <- tryCatch({
    x <- load_month_factors(ME[i], factor_names = "V01_BM")
    if (is.null(x) || !nrow(x)) NULL else data.table(Date = ME[i], Ticker = x$Ticker, v01 = x$Z_Score_Aligned)
  }, error = function(e) NULL)
  if (i %% 60 == 0) cat(sprintf("  [S1] V01_BM %d/%d\n", i, length(ME)))
}
V01 <- rbindlist(vlist[!vapply(vlist, is.null, TRUE)])
V01 <- V01[is.finite(v01)]
cat(sprintf("[S1] V01_BM: %d rows · %d months (요청 %d)\n", nrow(V01), uniqueN(V01$Date), length(ME)))

## ── 월간 forward 패널 ──────────────────────────────────────────────────────
ADV20 <- build_adv20_t1(RAWDATA[, .(Date, Ticker, Vol, Close)], at_dates = ME)
SIZE  <- RAWDATA[Date %in% ME & is.finite(Size), .(Date, Ticker, Size)]
RAWME <- RAWDATA[Date %in% ME]
rm(RAWDATA); gc(verbose = FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
cat(sprintf("[S1] returns_dt %d rows · bench %d · liq %d · ruler=%s(%s)\n",
            nrow(fwd$returns_dt), nrow(fwd$bench_dt), nrow(fwd$liq_dt), fwd$liq_ruler, fwd$liq_ruler_source))

saveRDS(list(MOM = MOM, V01 = V01, BM = BM, mem = mem, fwd = fwd, SIZE = SIZE, ME = ME),
        file.path(OUT, "panel.rds"))
cat(sprintf("[S1] done elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
