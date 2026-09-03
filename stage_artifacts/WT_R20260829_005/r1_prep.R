# ── R1 — Risk 층 데이터 준비 (WT-R20260829_005)
#  PIT: 모든 자료를 sig_date(2026-07-31) 이하로 하드 컷. 노출은 월말 t 자료만.
#  C1 : 롤링 창만 사용 (full-sample 통계 금지) — 창 정의는 r2 에서 소비.
#  C6 : 각 월의 유니버스는 그 달의 PIT 멤버십(mem)으로만.
#  C10: 유동성/ADV = t-1 기준(build_adv20_t1 승계분 사용).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")

SIG <- as.Date("2026-07-31")
WIN_Y <- 5L                                # 롤링 추정창 (년)
WIN_START <- as.Date("2021-08-01")

ap <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json"),
               simplifyVector = FALSE)
UNIV <- names(ap$alpha_vector)
cat(sprintf("[R1] alpha universe n=%d\n", length(UNIV)))

P <- readRDS(file.path(OUT, "panel.rds"))
mem <- P$mem; V01 <- P$V01; MOM <- P$MOM; BMp <- P$BM; ME <- P$ME; fwd <- P$fwd
ME <- ME[ME <= SIG]

rl <- load_rawdata(use_cache = TRUE); RAWDATA <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
## ★PIT 하드 컷 — RAWDATA 는 2026-08-28 까지 있으나 sig_date 이후는 전량 폐기 (C11)
n_before <- nrow(RAWDATA)
RAWDATA <- RAWDATA[Date <= SIG]; BM_DT <- BM_DT[Date <= SIG]
cat(sprintf("[R1] PIT cut @ %s : RAWDATA %d -> %d rows (dropped %d future rows)\n",
            SIG, n_before, nrow(RAWDATA), n_before - nrow(RAWDATA)))
stopifnot(max(RAWDATA$Date) <= SIG, max(BM_DT$Date) <= SIG)

## ── 섹터 (시변, 최신 <= 각 월말) ─────────────────────────────────────────────
SEC <- unique(RAWDATA[Date %in% ME, .(Date, Ticker, Sector = as.character(Sector))])
SEC[is.na(Sector) | Sector == "", Sector := "UNKNOWN"]

## ── 일별 수익 패널 (추정창) ─────────────────────────────────────────────────
mem_win <- mem[Date >= WIN_START - 400 & Date <= SIG]
TIC_WIN <- sort(unique(c(mem_win$Ticker, UNIV)))
D <- RAWDATA[Date >= WIN_START - 400 & Date <= SIG & Ticker %in% TIC_WIN & is.finite(Ret),
             .(Date, Ticker, Ret, Size, Vol, Close)]
D[, Ret := pmin(pmax(Ret, -0.60), 0.60)]     # 상하한 60% (KR 일일 제한폭 밖 = 데이터 잡음)
cat(sprintf("[R1] daily panel rows=%d tickers=%d %s..%s\n", nrow(D), uniqueN(D$Ticker),
            min(D$Date), max(D$Date)))

BMd <- BM_DT[Date >= WIN_START - 400 & Date <= SIG, .(Date, BM_Ret)]

## ── 월말 노출 (BETA / RVOL / SIZE / VALUE / MOM / LIQ) ───────────────────────
ME_win <- ME[ME >= WIN_START & ME <= SIG]
cat(sprintf("[R1] exposure month-ends: %d (%s .. %s)\n", length(ME_win), min(ME_win), max(ME_win)))

setkey(D, Date)
alldates <- sort(unique(D$Date))
bmv <- setNames(BMd$BM_Ret, as.character(BMd$Date))

expo_list <- vector("list", length(ME_win))
for (i in seq_along(ME_win)) {
  d0 <- ME_win[i]
  dd <- alldates[alldates <= d0]; dd <- tail(dd, 252L)
  sub <- D[Date %in% dd, .(Date, Ticker, Ret)]
  sub[, bm := bmv[as.character(Date)]]
  st <- sub[is.finite(bm), .(n = .N, sd_i = sd(Ret), cv = cov(Ret, bm), vb = var(bm)), by = Ticker]
  st <- st[n >= 120L]
  st[, beta_raw := cv / vb]
  st[, beta := 0.67 * beta_raw + 0.33]                  # Blume
  st[, rvol := sd_i * sqrt(252)]
  # 월말 스냅샷
  snap <- RAWDATA[Date == d0, .(Ticker, Size, Sector = as.character(Sector))]
  snap[is.na(Sector) | Sector == "", Sector := "UNKNOWN"]
  liq <- fwd$liq_dt[Date == d0, .(Ticker, adv)]
  v <- V01[Date == d0, .(Ticker, v01)]
  m <- MOM[Date == d0, .(Ticker, mom61)]
  u <- mem[Date == d0, .(Ticker, mkt)]
  x <- Reduce(function(a, b) merge(a, b, by = "Ticker", all.x = TRUE),
              list(u, snap, liq, v, m, st[, .(Ticker, beta, rvol)]))
  x <- x[is.finite(Size) & Size > 0 & is.finite(beta)]
  x[, Date := d0]
  expo_list[[i]] <- x
  if (i %% 12 == 0) cat(sprintf("  [R1] expo %d/%d\n", i, length(ME_win)))
}
EXPO <- rbindlist(expo_list, fill = TRUE)

## 횡단면 z (winsor ±3) — 각 월 독립 (C1: 전기간 통계 미사용)
zs <- function(x) { m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
                    if (!is.finite(s) || s == 0) return(rep(0, length(x)))
                    pmin(pmax((x - m) / s, -3), 3) }
EXPO[, `:=`(
  X_SIZE = zs(log(Size)),
  X_VAL  = zs(pmin(pmax(v01, -3), 3)),
  X_MOM  = zs(pmin(pmax(mom61, -3), 3)),
  X_LIQ  = zs(log(pmax(adv, 1))),
  X_BETA = zs(beta),
  X_RVOL = zs(log(pmax(rvol, 1e-4)))
), by = Date]
for (cc in c("X_SIZE","X_VAL","X_MOM","X_LIQ","X_BETA","X_RVOL")) EXPO[!is.finite(get(cc)), (cc) := 0]
cat(sprintf("[R1] EXPO rows=%d months=%d median names/mo=%.0f\n",
            nrow(EXPO), uniqueN(EXPO$Date), median(EXPO[, .N, by = Date]$N)))

## ── 장기 월별 수익 (레짐 상관용, 2005~) ─────────────────────────────────────
MRET <- fwd$returns_dt[Date <= SIG]
BMM  <- fwd$bench_dt[Date <= SIG]

saveRDS(list(D = D, BMd = BMd, EXPO = EXPO, SEC = SEC, ME_win = ME_win, ME = ME,
             UNIV = UNIV, SIG = SIG, MRET = MRET, BMM = BMM, mem = mem,
             liq_dt = fwd$liq_dt[Date <= SIG]),
        file.path(OUT, "risk_r1.rds"))
cat("[R1] done\n")
