# S1 — 패널 구축 (WT-R20260829_007 · GH2004 52주 신고가 근접도)
#  신호 = 근접도 FH = P_t / high_t. 두 사양 병기:
#    fh252 : max(Close, 최근 252 거래일)          — in-house M06_High_52w 규약 (선행 런 비교용)
#    fh12m : max(월별 최고 Close, 최근 12 캘린더월) — GH2004 원문 규약 ("highest price over past 12 months")
#  PIT: 전부 월말 t 시점까지의 Close 만. forward 수익은 t -> t+1 (build_monthly_forward_returns).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite); library(RcppRoll)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
t0 <- Sys.time()

rl <- load_rawdata(use_cache = TRUE)
RAWDATA <- as.data.table(rl$RAWDATA); BM_DT <- as.data.table(rl$BM_DT); rm(rl); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date"))   BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= as.Date("2000-01-01")]

## ── ever-member 축소 (유니버스 정의이지 생존편향 아님 — 멤버십은 시변 적용) ──
ever <- unique(RAWDATA[K200 == TRUE | KQ150 == TRUE, Ticker])
RAWDATA <- RAWDATA[Ticker %in% ever]
gc(verbose = FALSE)
cat(sprintf("[S1] RAWDATA %d rows · ever-member ticker %d · %s ~ %s\n",
            nrow(RAWDATA), length(ever), min(RAWDATA$Date), max(RAWDATA$Date)))

## ── H1 사전점검: 수정주가 연속성 (분할 이벤트에서 Close/max 비율의 인위적 붕괴 여부) ──
## 지문 = 하루 |log(Close_t/Close_{t-1})| > log(3) 인데 |Ret| < 0.5 인 케이스(= Close 조정 불일치)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .pxjump := log(Close / shift(Close)), by = Ticker]
h1 <- RAWDATA[is.finite(.pxjump) & abs(.pxjump) > log(3) & is.finite(Ret) & abs(Ret) < 0.5]
h1_by_year <- h1[, .N, by = .(yr = format(Date, "%Y"))][order(yr)]
sam <- RAWDATA[Ticker == "A005930" & Date >= as.Date("2018-04-25") & Date <= as.Date("2018-05-10"),
               .(Date, Close, Vol, Size, Ret)]
h1_check <- list(
  rule = "Close 로그점프 |>log(3)| 인데 |일간 Ret| < 0.5 = 수정주가 불일치 지문. 분할 조정이 정합이면 0 이어야 한다.",
  n_flag = nrow(h1), n_rows_scanned = nrow(RAWDATA),
  flag_rate = nrow(h1)/nrow(RAWDATA),
  by_year = lapply(split(h1_by_year, seq_len(nrow(h1_by_year))), as.list),
  samsung_2018_05_split = lapply(split(sam, seq_len(nrow(sam))), as.list),
  samsung_implied_shares = sam[, .(Date, implied_shares = Size/Close)])
cat(sprintf("[S1][H1] 수정주가 불일치 지문 %d건 / %d행 (%.2e)\n", nrow(h1), nrow(RAWDATA), nrow(h1)/nrow(RAWDATA)))
print(sam)
RAWDATA[, .pxjump := NULL]

## ── 월말 거래일 ─────────────────────────────────────────────────────────────
udates <- sort(unique(RAWDATA$Date))
ME_all <- as.Date(tapply(as.character(udates), format(udates, "%Y-%m"), max))
ME_all <- sort(ME_all)

## ── 일간 → 252일 rolling max / min (RcppRoll, ticker 별) ────────────────────
DX <- RAWDATA[!is.na(Close) & Close > 0, .(Date, Ticker, Close, Ret, Vol, Size, Sector, K200, KQ150)]
setorder(DX, Ticker, Date)
DX[, `:=`(
  hi252 = { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_max(Close, n = min(252L, n), align = "right", fill = NA) },
  lo252 = { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_min(Close, n = min(252L, n), align = "right", fill = NA) }
), by = Ticker]
## 실현변동성 63d + Amihud 20d (자체 산출 — L-family 는 별도 커넥터 경유)
DX[, absret_over_dval := fifelse(is.finite(Ret) & is.finite(Vol) & is.finite(Close) & Vol*Close > 0,
                                 abs(Ret)/(Vol*Close), NA_real_)]
DX[, `:=`(
  rv63 = { n <- .N; if (n < 21L) NA_real_ else RcppRoll::roll_sd(fifelse(is.finite(Ret), Ret, 0), n = min(63L, n), align="right", fill=NA) },
  amih20 = { n <- .N; if (n < 21L) NA_real_ else RcppRoll::roll_mean(fifelse(is.finite(absret_over_dval), absret_over_dval, NA_real_), n = min(20L, n), align="right", fill=NA, na.rm=TRUE) }
), by = Ticker]
cat(sprintf("[S1] rolling 완료 elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))

## ── GH2004 원문 규약: 최근 12 캘린더월 최고가 ───────────────────────────────
DX[, ym := format(Date, "%Y-%m")]
MMAX <- DX[, .(mmax = max(Close, na.rm = TRUE)), by = .(Ticker, ym)]
setorder(MMAX, Ticker, ym)
MMAX[, hi12m := { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_max(mmax, n = min(12L, n), align="right", fill=NA) }, by = Ticker]

## ── 월말 단면 ───────────────────────────────────────────────────────────────
SIG <- DX[Date %in% ME_all, .(Date, ym, Ticker, Close, Size, Sector, K200, KQ150, hi252, lo252, rv63, amih20)]
SIG <- merge(SIG, MMAX[, .(Ticker, ym, hi12m)], by = c("Ticker","ym"), all.x = TRUE)
SIG[, `:=`(fh252 = fifelse(is.finite(hi252) & hi252 > 0, Close/hi252, NA_real_),
           fh12m = fifelse(is.finite(hi12m) & hi12m > 0, Close/hi12m, NA_real_),
           lo52  = fifelse(is.finite(lo252) & lo252 > 0, Close/lo252, NA_real_))]

## ── 월간 수익 · JT 6개월 수익 · 산업 6개월 수익 ─────────────────────────────
setorder(SIG, Ticker, Date)
SIG[, mret := Close/shift(Close) - 1, by = Ticker]
SIG[, gap_m := as.integer(round(as.numeric(Date - shift(Date))/30.4)), by = Ticker]
SIG[is.finite(gap_m) & gap_m > 1L, mret := NA_real_]   # 월 연속성 깨지면 결측
SIG[, jt6 := { s <- rep(0, .N); c0 <- rep(0L, .N)
               for (k in 0:5) { xx <- shift(mret, k); s <- s + fifelse(is.finite(xx), log1p(xx), 0); c0 <- c0 + as.integer(is.finite(xx)) }
               fifelse(c0 >= 5L, expm1(s), NA_real_) }, by = Ticker]
## 산업(Sector) EW 월수익 -> 6개월
SEC <- SIG[!is.na(Sector) & is.finite(mret), .(sret = mean(mret, na.rm=TRUE), nsec = .N), by = .(Sector, Date)]
setorder(SEC, Sector, Date)
SEC[, ind6 := { s <- rep(0, .N); c0 <- rep(0L, .N)
                for (k in 0:5) { xx <- shift(sret, k); s <- s + fifelse(is.finite(xx), log1p(xx), 0); c0 <- c0 + as.integer(is.finite(xx)) }
                fifelse(c0 >= 5L, expm1(s), NA_real_) }, by = Sector]
SIG <- merge(SIG, SEC[, .(Sector, Date, ind6, sec_n = nsec)], by = c("Sector","Date"), all.x = TRUE)

## ── 유니버스 라벨 + 유동성 자 ───────────────────────────────────────────────
SIG[, mkt := fifelse(K200 == TRUE, "K200", fifelse(KQ150 == TRUE, "KQ150", NA_character_))]
SIG[, in_univ := !is.na(mkt)]

ME <- ME_all[ME_all >= as.Date("2005-01-01")]
ADV20 <- build_adv20_t1(RAWDATA[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAWDATA[Date %in% ME]
DAILY_FLOW_DATES <- ME   # F3 에서 사용
rm(DX); gc(verbose = FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
cat(sprintf("[S1] returns_dt %d rows · bench %d · liq %d · ruler=%s(%s)\n",
            nrow(fwd$returns_dt), nrow(fwd$bench_dt), nrow(fwd$liq_dt), fwd$liq_ruler, fwd$liq_ruler_source))

SIGK <- SIG[, .(Date, Ticker, mkt, in_univ, Close, Size, Sector, sec_n,
                fh252, fh12m, lo52, mret, jt6, ind6, rv63, amih20)]
saveRDS(list(SIG = SIGK, fwd = fwd, ME = ME, ME_all = ME_all, BM_DT = BM_DT,
             h1_check = h1_check), file.path(OUT, "panel.rds"))
write_json(list(h1_precheck = h1_check,
                n_months_signal = length(ME_all), n_months_eval = length(ME),
                window_eval = paste(as.character(range(ME)), collapse=" ~ "),
                liq_ruler = fwd$liq_ruler, liq_ruler_source = fwd$liq_ruler_source,
                univ_median_names = median(SIGK[in_univ == TRUE & Date %in% ME, .N, by=Date]$N)),
           file.path(OUT, "s1_panel.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("[S1] SIG %d rows · %d months · univ median %.0f · done %.1fs\n",
            nrow(SIGK), uniqueN(SIGK$Date), median(SIGK[in_univ == TRUE & Date %in% ME, .N, by=Date]$N),
            as.numeric(difftime(Sys.time(), t0, units="secs"))))
