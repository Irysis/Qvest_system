# S1 — 패널 구축 (WT-R20260829_003 · LS2000 회전율 조건부 모멘텀 생애주기)
#  신호 = 기저 fe_jt1993_momentum.R 그대로(J=6 형성 t-2..t-7, skip 1M) — 강화 시도의 신호 고정 의무
#  신규 재료 = 형성기 일평균 회전율(LS2000 원정의: 거래주식수/상장주식수 = Vol*Close/Size)
#  PIT: 회전율도 t-2..t-7 월만 사용(당월·t-1 월 전면 배제 — C10 계열 보수적 준수)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

t0 <- Sys.time()
rl <- load_rawdata(use_cache = TRUE)
RAWDATA <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date"))   BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= as.Date("2003-06-01")]
gc(verbose = FALSE)

## ── 신호: 기저 엔진 그대로 ───────────────────────────────────────────────
fe_env <- new.env(parent = globalenv()); fe_env$RAWDATA <- RAWDATA; fe_env$BM_DT <- BM_DT
source(file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"), local = fe_env)
FACTORS <- as.data.table(fe_env$FACTORS); rm(fe_env); gc(verbose = FALSE)
FACTORS <- FACTORS[Date >= as.Date("2005-01-01")]
cat(sprintf("[S1] FACTORS: %d rows · %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

## ── 회전율(LS2000): 일별 turnover = Vol*Close/Size = 거래주식수/상장주식수 ──
##   (Vol·Close·Size 는 동일 조정기준 — 2018-05 삼성전자 50:1 액면분할 구간에서
##    implied shares(Size/Close) 불변 6.4193e9 로 실증 확인)
TO <- RAWDATA[is.finite(Vol) & is.finite(Close) & is.finite(Size) & Size > 0 & Close > 0,
              .(Date, Ticker, to_d = Vol * Close / Size)]
TO[, ym := format(Date, "%Y-%m")]
TOM <- TO[, .(to_m = mean(to_d, na.rm = TRUE), nd = .N), by = .(Ticker, ym)]
setorder(TOM, Ticker, ym)
## 형성기(t-2..t-7) 평균 — 신호와 동일 창. shift 로 과거만.
TOM[, `:=`(turn_form = {
  s <- rep(0, .N); c0 <- rep(0L, .N)
  for (k in 2:7) { xx <- shift(to_m, k); s <- s + fifelse(is.finite(xx), xx, 0); c0 <- c0 + as.integer(is.finite(xx)) }
  fifelse(c0 >= 4L, s / pmax(c0, 1L), NA_real_)
}, n_turn = {
  c0 <- rep(0L, .N); for (k in 2:7) c0 <- c0 + as.integer(is.finite(shift(to_m, k))); c0
}), by = Ticker]
## ΔTurnover 대조 사양(C2 예약축): 형성기 평균 / 그 이전 12개월(t-8..t-19) 평균
TOM[, turn_base := {
  s <- rep(0, .N); c0 <- rep(0L, .N)
  for (k in 8:19) { xx <- shift(to_m, k); s <- s + fifelse(is.finite(xx), xx, 0); c0 <- c0 + as.integer(is.finite(xx)) }
  fifelse(c0 >= 8L, s / pmax(c0, 1L), NA_real_)
}, by = Ticker]
TOM[, d_turn := fifelse(is.finite(turn_base) & turn_base > 0, log(turn_form / turn_base), NA_real_)]

ME <- sort(unique(FACTORS$Date))
ym_me <- data.table(ym = format(ME, "%Y-%m"), Date = ME)
TURN <- merge(TOM[is.finite(turn_form), .(Ticker, ym, turn_form, n_turn, d_turn)], ym_me, by = "ym")[, ym := NULL]
cat(sprintf("[S1] TURN: %d rows · %d months · d_turn 가용 %.1f%%\n",
            nrow(TURN), uniqueN(TURN$Date), 100*mean(is.finite(TURN$d_turn))))

## ── 유니버스(K200∪KQ150 PIT 시변) + 시장 라벨 (LS2000 의 Nasdaq 배제 대응) ──
mem <- unique(RAWDATA[Date %in% ME & (K200 == TRUE | KQ150 == TRUE),
                      .(Date, Ticker, mkt = fifelse(K200 == TRUE, "K200", "KQ150"))])
FACTORS <- merge(FACTORS, mem, by = c("Date","Ticker"))
cat(sprintf("[S1] universe 치환 후: %d rows · %d months · median names %.0f (K200 %.0f / KQ150 %.0f)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), median(FACTORS[, .N, by = Date]$N),
            median(FACTORS[mkt=="K200", .N, by=Date]$N), median(FACTORS[mkt=="KQ150", .N, by=Date]$N)))

## ── 월간 forward 패널 (헌법 자 = 20일 평균 거래대금 t-1) ──
ADV20 <- build_adv20_t1(RAWDATA[, .(Date, Ticker, Vol, Close)], at_dates = ME)
SIZE  <- RAWDATA[Date %in% ME & is.finite(Size), .(Date, Ticker, Size)]
RAWME <- RAWDATA[Date %in% ME]
DAILY <- RAWDATA[Date >= as.Date("2005-01-01") & is.finite(Ret), .(Date, Ticker, Ret, BM_Ret)]  # 공시창 CAR 용
rm(RAWDATA); gc(verbose = FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
cat(sprintf("[S1] returns_dt %d rows · bench %d · liq %d · ruler=%s(%s)\n",
            nrow(fwd$returns_dt), nrow(fwd$bench_dt), nrow(fwd$liq_dt), fwd$liq_ruler, fwd$liq_ruler_source))

saveRDS(list(FACTORS = FACTORS, TURN = TURN, fwd = fwd, SIZE = SIZE, ME = ME, DAILY = DAILY),
        file.path(OUT, "panel.rds"))
cat(sprintf("[S1] done elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
