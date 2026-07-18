##=============================================================================
## smartbeta_kr_tracker.R — KR 스마트베타 6스타일 월간 트래커 (시장 리뷰 전용)
##
## FF5 트래커와의 구분: FF5=학술 long-short·전체상장·연1회 formation /
##   본 트래커=**투자가능 long-only**·K200∪KQ150·월간 리밸 — smart-beta ETF 관점.
## 스타일(6): VAL(V01_BM高) QUAL(Q01_GPA高) MOM(M01_Mom_12_1高) LOWVOL(D03_RealVol低)
##   SIZE(Size低) DIV(V11_Shareholder_Yield高) — 각 top-tercile VW.
## active = 스타일 VW 수익 − 유니버스 VW(cap-w) 수익. metric_type=diagnostic_monitoring.
## 라벨: 시장 스타일 국면 서술 전용 — 전략 판정/자본 인용 금지. 거래비용 미반영(진단).
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT_DIR <- "outputs/smartbeta_kr"
dir.create(file.path(OUT_DIR, "charts"), recursive = TRUE, showWarnings = FALSE)
RUNTAG <- format(Sys.Date(), "%Y%m%d")
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
nwt <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(lmtest::coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3]) }
t0 <- Sys.time()

## v2 (2026-07-18 도훈 지시): QUAL=F-Score / VAL=컴포지트(V12 = mean z(-fPER,-fPBR,+fDY,+CFP) — 포워드 중심) /
##   DIV=포워드 고배당(fDY). 구판(GPA/BM/V11)은 git 이력 보존. fDY 초기연도 커버 얇음 → <100 종목 월은 NA(정직).
## v2.2 (07-18 도훈 정정 지시 "캐시에 다 있다"): QUAL = **fROE(포워드 ROE = eps_1y/bps_1y)** —
##   컨센서스 캐시 직접 계산(SIZE의 rawdata 직접 소비와 동일 경로, 팩터 DB 미경유).
##   월말 기준 최근 92일 내 최신 컨센서스 LOCF(과거 방향만 = PIT-safe)·bps>0 가드.
##   포워드 스위트 완성: VAL(컴포지트)·QUAL(fROE)·DIV(fDY)·EREV(전망수정). F-Score판은 git 이력.
STYLES <- list(VAL = list(f = "V12_Composite_Value", hi = TRUE), QUAL = list(f = "__froe", hi = TRUE),
               MOM = list(f = "M01_Mom_12_1", hi = TRUE), LOWVOL = list(f = "D03_RealVol", hi = FALSE),
               SIZE = list(f = NA_character_, hi = FALSE), DIV = list(f = "V06_fDY", hi = TRUE),
               EREV = list(f = "C03_EPS_Chg_3m", hi = TRUE))
FNAMES <- unique(unlist(lapply(STYLES, function(x) x$f)))
FNAMES <- FNAMES[!is.na(FNAMES) & !startsWith(FNAMES, "__")]

## fROE 재료: 컨센서스 캐시 직접 소비 (도훈 지시 — 팩터 DB 미경유 직접 산출)
CONS_EPS <- as.data.table(read_parquet(".cache/consensus/eps_1y.parquet")); CONS_EPS[, Date := as.Date(Date)]; setkey(CONS_EPS, Ticker, Date)
CONS_BPS <- as.data.table(read_parquet(".cache/consensus/bps_1y.parquet")); CONS_BPS[, Date := as.Date(Date)]; setkey(CONS_BPS, Ticker, Date)
get_froe <- function(tickers, sig_d, max_stale = 92) {
  q <- data.table(Ticker = tickers, Date = as.Date(sig_d))
  e <- CONS_EPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, eps = eps_1y)]
  b <- CONS_BPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, bps = bps_1y)]
  m <- merge(e, b, by = "Ticker")
  m[!is.na(eps) & !is.na(bps) & bps > 0, .(Ticker, froe = eps / bps)]
}

## ── 1) 월말 유니버스 패널 + forward 1m (유니버스=K200∪KQ150) ───────────────
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
mgrid <- seq(as.Date("2004-12-01"), max(ud), by = "1 month")
me <- unique(as.Date(vapply(mgrid, function(d) { m0 <- as.Date(cut(d, "month")); e <- seq(m0, by = "1 month", length.out = 2)[2] - 1
  v <- ud[ud <= e & ud >= m0]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
pn <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |>
        select(all_of(c("Date", "Ticker", "Close", "Size", "K200", "KQ150"))) |> collect())
pn[, Date := as.Date(Date)]
pn <- pn[!is.na(Close) & Close > 0]
setorder(pn, Ticker, Date)
me_idx <- data.table(Date = me, i = seq_along(me))
pn <- merge(pn, me_idx, by = "Date")
pn[, `:=`(Close_n = shift(Close, type = "lead"), i_n = shift(i, type = "lead")), by = Ticker]
pn[, fwd := fifelse(!is.na(Close_n) & i_n == i + 1, Close_n / Close - 1, NA_real_)]
pn[fwd > 5.0 | fwd < -1.0, fwd := NA_real_]                 # R44 sanity
uni <- pn[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size) & Size > 0 & !is.na(fwd)]
wf("universe month-end rows=%d, months=%d", nrow(uni), uniqueN(uni$Date))

## ── 2) z_raw 복원 로더 (FF5 트래커 동일 패턴) ──────────────────────────────
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
recover_raw_z <- function(sig_d, fnames) {
  f <- as.data.table(load_month_factors(sig_d, factor_names = fnames))
  if (!nrow(f)) return(NULL)
  dm <- tryCatch(.load_ic_direction_cached(sig_d, 36L), error = function(e) NULL)
  if (!is.null(dm) && nrow(dm)) f <- merge(f, dm[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
  else f[, ic_sign := NA_integer_]
  reg <- tryCatch(.load_registry(), error = function(e) NULL)
  if (!is.null(reg)) {
    rd <- data.table(Factor_Name = names(reg),
                     reg_sign = sapply(reg, function(x) if ((x$direction %||% "higher_better") == "lower_better") -1L else 1L))
    f <- merge(f, rd, by = "Factor_Name", all.x = TRUE)
    f[is.na(ic_sign), ic_sign := reg_sign]; f[, reg_sign := NULL]
  }
  f[is.na(ic_sign), ic_sign := 1L]
  f[, z_raw := Z_Score_Aligned * ic_sign]
  dcast(f, Ticker ~ Factor_Name, value.var = "z_raw")
}

## ── 3) 월간 리밸: 스타일 top-tercile VW active ─────────────────────────────
sig_dates <- me[format(me, "%Y-%m") >= "2005-01" & me < max(me)]   # 마지막 월말은 fwd 미실현
## 증분 갱신: 기존 parquet 존재 시 미계산 월만 (SB_FORCE_REBUILD=1로 전량 재빌드)
SB_prev <- NULL
pq <- file.path(OUT_DIR, "smartbeta_kr_monthly.parquet")
if (file.exists(pq) && !nzchar(Sys.getenv("SB_FORCE_REBUILD", ""))) {
  SB_prev <- as.data.table(read_parquet(pq))
  invisible(gc())                                   # mmap 해제 (Windows arrow 1224 회피 1/2)
  sig_dates <- sig_dates[!format(sig_dates, "%Y-%m") %in% SB_prev$ym]
  wf("incremental: 기존 %d개월 스킵, 신규 %d개월", nrow(SB_prev), length(sig_dates))
}
rows <- list(); nmov <- 0L
for (sd_ in sig_dates) {
  sd_ <- as.Date(sd_, origin = "1970-01-01")
  u <- uni[Date == sd_]
  if (nrow(u) < 150) next
  fz <- tryCatch(recover_raw_z(sd_, FNAMES), error = function(e) NULL)
  if (is.null(fz)) next
  u <- merge(u, fz, by = "Ticker", all.x = TRUE)
  fr <- tryCatch(get_froe(u$Ticker, sd_), error = function(e) NULL)
  if (!is.null(fr) && nrow(fr)) u <- merge(u, fr, by = "Ticker", all.x = TRUE) else u[, froe := NA_real_]
  bench <- u[, sum(fwd * Size) / sum(Size)]
  out <- list(ym = format(sd_, "%Y-%m"), BENCH = bench)
  for (st in names(STYLES)) {
    cfg <- STYLES[[st]]
    v <- if (st == "SIZE") -u$Size
         else if (identical(cfg$f, "__froe")) u$froe
         else { if (is.na(cfg$f) || !cfg$f %in% names(u)) NA else (if (cfg$hi) 1 else -1) * u[[cfg$f]] }
    if (length(v) == 1 && is.na(v)) { out[[st]] <- NA_real_; next }
    ok <- !is.na(v)
    if (sum(ok) < 100) { out[[st]] <- NA_real_; next }
    thr <- quantile(v[ok], 0.7)
    sel <- ok & v >= thr
    out[[st]] <- u[sel, sum(fwd * Size) / sum(Size)] - bench
  }
  nmov <- nmov + 1L
  rows[[format(sd_)]] <- as.data.table(out)
  if (nmov %% 48 == 0) wf("  %s (%.1f min)", format(sd_), as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
SB <- rbindlist(c(if (!is.null(SB_prev)) list(SB_prev), rows), fill = TRUE)
SB <- unique(SB, by = "ym")[order(ym)]
wf("SB series: %d months (%s..%s)", nrow(SB), min(SB$ym), max(SB$ym))
.tmp_pq <- file.path(OUT_DIR, ".smartbeta_kr_monthly.tmp.parquet")   # temp-rename (1224 회피 2/2)
write_parquet(SB, .tmp_pq)
if (file.exists(pq)) invisible(file.remove(pq))
invisible(file.rename(.tmp_pq, pq))

## ── 4) 기간 요약 + 정합 게이트 ──────────────────────────────────────────────
sty <- names(STYLES)
per <- list(c("2005-01", "2009-12"), c("2010-01", "2014-12"), c("2015-01", "2015-12"),
            c("2016-01", "2019-12"), c("2020-01", "2021-12"), c("2022-01", "2023-12"), c("2024-01", "2026-12"))
tab <- list()
for (p in per) {
  s <- SB[ym >= p[1] & ym <= p[2]]
  if (!nrow(s)) next
  r <- data.table(period = paste(p[1], p[2], sep = "~"), n = nrow(s))
  for (st in sty) { r[[st]] <- mean(s[[st]], na.rm = TRUE); r[[paste0(st, "_t")]] <- nwt(s[[st]]) }
  tab[[p[1]]] <- r
}
TAB <- rbindlist(tab, fill = TRUE)
print(TAB[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)])
## v2 게이트: VAL이 forward-yield 중심 컴포지트로 바뀌어 "2024+ 음" 기대는 정의-특이(BM/EV배수 죽고
##   yield 생존 실측 — value arc)라 게이트에서 제외, 정보성 로그만. SIZE·MOM이 구성 검증 담당.
g1 <- TAB[period == "2024-01~2026-12", MOM] > 0     # mega 레짐 모멘텀 강세 정합
g2 <- TAB[period == "2024-01~2026-12", SIZE] < 0    # mega 레짐 정합
wf("[정합게이트] MOM 2024+ 양: %s | SIZE 2024+ 음: %s | (정보) VAL_composite 2024+ = %+.4f", g1, g2,
   TAB[period == "2024-01~2026-12", VAL])
if (!all(g1, g2, na.rm = TRUE)) wf("[!!] 부호/구성 재점검 필요")

## ── 5) 차트 (rolling 12m, 범례 플롯 밖 우측) ───────────────────────────────
SBc <- copy(SB)
for (st in sty) SBc[, (paste0("r12_", st)) := frollmean(get(st), 12)]
SBc[, d := as.Date(paste0(ym, "-01"))]
cols <- c(VAL = "steelblue", QUAL = "darkgreen", MOM = "firebrick", LOWVOL = "purple", SIZE = "darkorange", DIV = "gray40", EREV = "deeppink3")
png(file.path(OUT_DIR, "charts", "smartbeta_rolling12.png"), width = 1150, height = 480)
par(mar = c(3, 4, 2.5, 8))
rng <- range(SBc[, paste0("r12_", sty), with = FALSE], na.rm = TRUE) * 100
plot(SBc$d, SBc$r12_VAL * 100, type = "l", lwd = 2, col = cols["VAL"], ylim = rng,
     main = "KR 스마트베타 6스타일 — active(vs 유니버스 VW) rolling 12m mean", xlab = "", ylab = "월평균 active %")
for (st in setdiff(sty, "VAL")) lines(SBc$d, SBc[[paste0("r12_", st)]] * 100, lwd = 2, col = cols[st])
abline(h = 0, lty = 3)
legend(x = par("usr")[2], y = par("usr")[4], legend = sty, col = cols[sty], lwd = 2, cex = 0.9, xpd = TRUE, bty = "n")
dev.off()
wf("chart written: smartbeta_rolling12.png")

rec <- SB[(.N - 11):.N]
write_json(list(runtag = RUNTAG, metric_type = "diagnostic_monitoring",
                usage_label = "시장 스타일 리뷰 전용 — 전략 판정/자본 인용 금지·비용 미반영",
                construction = "v2: K200∪KQ150·월간 리밸·top-tercile VW·active=vs 유니버스 VW. QUAL=Piotroski F / VAL=V12 composite(forward 중심) / DIV=fDY(forward 고배당)",
                styles = lapply(STYLES, function(x) x$f %||% "Size(low)"),
                n_months = nrow(SB), period_table = TAB, recent12 = rec,
                sanity_gates = list(val_2024_neg = g1, size_2024_neg = g2),
                runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")),
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, sprintf("smartbeta_kr_summary_%s.json", RUNTAG)), auto_unbox = TRUE, pretty = TRUE, digits = 5)
wf("=== smartbeta_kr_tracker done %.1f min ===", as.numeric(difftime(Sys.time(), t0, units = "mins")))
