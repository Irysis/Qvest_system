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
## v2.3 (07-18 도훈): VAL = 순수 포워드 컴포지트 __fval = mean( z(eps_1y/P), z(bps_1y/P), z(dps_1y/P) )
##   — V12의 trailing CFP 혼입 제거, 컨센서스 캐시 직접 계산(3지표 중 2개 이상 있으면 산출).
STYLES <- list(VAL = list(f = "__fval", hi = TRUE), QUAL = list(f = "__froe", hi = TRUE),
               MOM = list(f = "M01_Mom_12_1", hi = TRUE), LOWVOL = list(f = "D03_RealVol", hi = FALSE),
               SIZE = list(f = NA_character_, hi = FALSE), DIV = list(f = "V06_fDY", hi = TRUE),
               EREV = list(f = "C03_EPS_Chg_3m", hi = TRUE))
FNAMES <- unique(unlist(lapply(STYLES, function(x) x$f)))
FNAMES <- FNAMES[!is.na(FNAMES) & !startsWith(FNAMES, "__")]

## fROE 재료: 컨센서스 캐시 직접 소비 (도훈 지시 — 팩터 DB 미경유 직접 산출)
CONS_EPS <- as.data.table(read_parquet(".cache/consensus/eps_1y.parquet")); CONS_EPS[, Date := as.Date(Date)]; setkey(CONS_EPS, Ticker, Date)
CONS_BPS <- as.data.table(read_parquet(".cache/consensus/bps_1y.parquet")); CONS_BPS[, Date := as.Date(Date)]; setkey(CONS_BPS, Ticker, Date)
CONS_DPS <- as.data.table(read_parquet(".cache/consensus/dps_1y.parquet")); CONS_DPS[, Date := as.Date(Date)]; setkey(CONS_DPS, Ticker, Date)
get_froe <- function(tickers, sig_d, max_stale = 92) {
  q <- data.table(Ticker = tickers, Date = as.Date(sig_d))
  e <- CONS_EPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, eps = eps_1y)]
  b <- CONS_BPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, bps = bps_1y)]
  m <- merge(e, b, by = "Ticker")
  m[!is.na(eps) & !is.na(bps) & bps > 0, .(Ticker, froe = eps / bps)]
}
get_fval <- function(tickers, close, sig_d, max_stale = 92) {  # 순수 포워드 밸류 컴포지트
  q <- data.table(Ticker = tickers, Date = as.Date(sig_d))
  e <- CONS_EPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, eps = eps_1y)]
  b <- CONS_BPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, bps = bps_1y)]
  dv <- CONS_DPS[q, on = .(Ticker, Date), roll = max_stale][, .(Ticker, dps = dps_1y)]
  m <- Reduce(function(a, b2) merge(a, b2, by = "Ticker"), list(data.table(Ticker = tickers, Close = close), e, b, dv))
  m[Close > 0, `:=`(ey = eps / Close, by_ = bps / Close, dy = dps / Close)]
  zz <- function(x) { mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s == 0) return(rep(NA_real_, length(x))); (x - mu) / s }
  m[, `:=`(z1 = zz(ey), z2 = zz(by_), z3 = zz(dy))]
  m[, nz := rowSums(!is.na(cbind(z1, z2, z3)))]
  m[, fval := rowMeans(cbind(z1, z2, z3), na.rm = TRUE)]
  m[nz >= 2, .(Ticker, fval)]
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
## 완결월 가드 (07-18 수리): forward 홀딩월이 진행 중인 달이면 부분월 수익이 됨 — 다음 월말의
##   달(ym)이 데이터 최신달보다 과거인 신호월만 발행 (구판: 2026-06 신호가 7/16까지 11일 부분월로 발행됐던 오염)
last_ym <- format(max(ud), "%Y-%m")
sig_dates <- me[format(me, "%Y-%m") >= "2005-01" & me < max(me)]
sig_dates <- sig_dates[vapply(sig_dates, function(d) { nx <- me[me > d][1]
  !is.na(nx) && format(nx, "%Y-%m") < last_ym }, logical(1))]
## ★ym 라벨 = 실현(홀딩)월 (07-18 도훈 정정 "완결월은 6월" — 구판 신호월 라벨이 FF5 실현월 라벨과 불일치.
##   북 realized_ym 규약 정합: 2026-05 신호 행 → ym "2026-06"으로 표기)
rym_map <- data.table(sig = sig_dates,
                      rym = vapply(sig_dates, function(d) format(me[me > d][1], "%Y-%m"), character(1)))
## 증분 갱신: 기존 parquet 존재 시 미계산 월만 (SB_FORCE_REBUILD=1로 전량 재빌드)
SB_prev <- NULL
pq <- file.path(OUT_DIR, "smartbeta_kr_monthly.parquet")
if (file.exists(pq) && !nzchar(Sys.getenv("SB_FORCE_REBUILD", ""))) {
  SB_prev <- as.data.table(read_parquet(pq))
  invisible(gc())                                   # mmap 해제 (Windows arrow 1224 회피 1/2)
  SB_prev <- SB_prev[ym %in% rym_map$rym]                  # 부분월·구라벨 잔재 자동 제거 (실현월 기준)
  sig_dates <- rym_map[!rym %in% SB_prev$ym, sig]
  wf("incremental: 기존 %d개월 스킵, 신규 %d개월", nrow(SB_prev), length(sig_dates))
}
## 스타일 active 산출 공용 헬퍼 (월간 시계열 + 진행월 MTD 공용)
style_actives <- function(u) {
  bench <- u[, sum(fwd * Size) / sum(Size)]
  out <- list(BENCH = bench)
  for (st in names(STYLES)) {
    cfg <- STYLES[[st]]
    v <- if (st == "SIZE") -u$Size
         else if (identical(cfg$f, "__froe")) u$froe
         else if (identical(cfg$f, "__fval")) u$fval
         else { if (is.na(cfg$f) || !cfg$f %in% names(u)) NA else (if (cfg$hi) 1 else -1) * u[[cfg$f]] }
    if (length(v) == 1 && is.na(v)) { out[[st]] <- NA_real_; next }
    ok <- !is.na(v)
    if (sum(ok) < 100) { out[[st]] <- NA_real_; next }
    thr <- quantile(v[ok], 0.7)
    sel <- ok & v >= thr
    out[[st]] <- u[sel, sum(fwd * Size) / sum(Size)] - bench
  }
  out
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
  fv <- tryCatch(get_fval(u$Ticker, u$Close, sd_), error = function(e) NULL)
  if (!is.null(fv) && nrow(fv)) u <- merge(u, fv, by = "Ticker", all.x = TRUE) else u[, fval := NA_real_]
  out <- c(list(ym = rym_map[sig == sd_, rym]), style_actives(u))   # 실현월 라벨
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

## ── 3b) 진행월 MTD — 직전영업일까지 (시계열 미포함 별도 산출, 도훈 지시 07-18) ──
mtd_ym <- format(max(ud), "%Y-%m")
mtd_sig <- max(me[format(me, "%Y-%m") < mtd_ym])
SB_MTD <- NULL
if (format(max(me), "%Y-%m") == mtd_ym && max(me) > mtd_sig) {
  um <- uni[Date == mtd_sig]                                  # uni의 fwd = mtd_sig→최신 월중일 (부분월 = MTD 정의 그 자체)
  if (nrow(um) >= 150) {
    fzm <- tryCatch(recover_raw_z(mtd_sig, FNAMES), error = function(e) NULL)
    if (!is.null(fzm)) {
      um <- merge(um, fzm, by = "Ticker", all.x = TRUE)
      frm <- tryCatch(get_froe(um$Ticker, mtd_sig), error = function(e) NULL)
      if (!is.null(frm) && nrow(frm)) um <- merge(um, frm, by = "Ticker", all.x = TRUE) else um[, froe := NA_real_]
      fvm <- tryCatch(get_fval(um$Ticker, um$Close, mtd_sig), error = function(e) NULL)
      if (!is.null(fvm) && nrow(fvm)) um <- merge(um, fvm, by = "Ticker", all.x = TRUE) else um[, fval := NA_real_]
      SB_MTD <- c(list(as_of = format(max(ud)), sig = format(mtd_sig),
                       n_days = sum(format(ud, "%Y-%m") == mtd_ym)), style_actives(um))
      write_json(SB_MTD, file.path(OUT_DIR, "smartbeta_kr_mtd.json"), auto_unbox = TRUE, digits = 6)
      wf("MTD %s~%s (%d거래일) 산출·저장", mtd_ym, SB_MTD$as_of, SB_MTD$n_days)
    }
  }
}

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

## ── 5) 차트 v3 (도훈 지시 07-18: 최근동향 가독성 — 정렬 막대 + 히트맵 + 소형패널) ──
KRN <- c(VAL = "가치포워드", QUAL = "퀄리티(fROE)", MOM = "모멘텀", LOWVOL = "저변동성",
         SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
cols <- c(VAL = "steelblue", QUAL = "darkgreen", MOM = "firebrick", LOWVOL = "purple",
          SIZE = "darkorange", DIV = "gray40", EREV = "deeppink3")

## (A) 최근 성과 정렬 막대 — 1M / 3M평균 / 12M평균
a1  <- vapply(sty, function(s) tail(SB[[s]], 1) * 100, numeric(1))
a3  <- vapply(sty, function(s) mean(tail(SB[[s]], 3), na.rm = TRUE) * 100, numeric(1))
a12 <- vapply(sty, function(s) mean(tail(SB[[s]], 12), na.rm = TRUE) * 100, numeric(1))
ord <- order(a12)
M <- rbind(`1M` = a1[ord], `3M avg` = a3[ord], `12M avg` = a12[ord])
if (!is.null(SB_MTD)) {
  mtd_v <- vapply(sty[ord], function(s) { x <- SB_MTD[[s]]; if (is.null(x) || is.na(x)) NA_real_ else x * 100 }, numeric(1))
  M <- rbind(M, matrix(mtd_v, nrow = 1, dimnames = list(sprintf("MTD~%s", substr(SB_MTD$as_of, 6, 10)), NULL)))
  M <- M[c(nrow(M), 1:(nrow(M) - 1)), , drop = FALSE]        # MTD를 맨 앞(그룹 최하단 막대)으로
}
bar_cols <- if (nrow(M) == 4) c("lightsteelblue", "gray75", "gray45", "black") else c("gray75", "gray45", "black")
png(file.path(OUT_DIR, "charts", "smartbeta_recent_bars.png"), width = 1250, height = 620)
par(mar = c(5, 11.5, 3.5, 8), cex.main = 1.45, cex.lab = 1.25)
bp <- barplot(M, beside = TRUE, horiz = TRUE, names.arg = KRN[sty[ord]], las = 1,
              col = bar_cols, border = NA, cex.names = 1.25, cex.axis = 1.15,
              main = sprintf("스마트베타 최근 성과 — 월 active %% (완결월 %s 기준 + 진행월 MTD)", max(SB$ym)),
              xlab = "월 active %", xlim = range(0, M, na.rm = TRUE) * 1.38)
abline(v = 0, lty = 1)
text(x = M + sign(M) * max(abs(M), na.rm = TRUE) * 0.06, y = bp, labels = sprintf("%+.1f", M), cex = 0.98, xpd = TRUE)
legend("bottomright", rev(rownames(M)), fill = rev(bar_cols), bty = "n", cex = 1.15, inset = c(0.01, 0.02))
dev.off()
wf("chart written: smartbeta_recent_bars.png")

## (B) 24개월 로테이션 히트맵 — 스타일 x 월, 적청 발산 팔레트
n_hm <- min(24, nrow(SB))
H <- sapply(sty, function(s) tail(SB[[s]], n_hm)) * 100      # n_hm x styles
ymv <- tail(SB$ym, n_hm)
if (!is.null(SB_MTD)) {                                       # 진행월 MTD 컬럼 추가 (도훈 지시 07-18)
  H <- rbind(H, vapply(sty, function(s) { x <- SB_MTD[[s]]; if (is.null(x) || is.na(x)) NA_real_ else x * 100 }, numeric(1)))
  ymv <- c(ymv, sprintf("%s MTD", substr(SB_MTD$as_of, 6, 10)))
  n_hm <- n_hm + 1L
}
Hm <- t(H)[length(sty):1, , drop = FALSE]                     # rows=styles(역순: 위가 첫 스타일)
brk <- max(abs(Hm), na.rm = TRUE)
pal <- colorRampPalette(c("#2166AC", "#F7F7F7", "#B2182B"))(64)
png(file.path(OUT_DIR, "charts", "smartbeta_heatmap24.png"), width = 1250, height = 540)
par(mar = c(5.5, 11, 3.5, 2), cex.main = 1.45)
image(x = 1:n_hm, y = 1:length(sty), z = t(Hm), col = pal, zlim = c(-brk, brk),
      axes = FALSE, xlab = "", ylab = "", main = "스마트베타 로테이션 — 최근 24개월 월 active % (청=마이너스 / 적=플러스)")
axis(2, at = 1:length(sty), labels = KRN[rev(sty)], las = 1, tick = FALSE, cex.axis = 1.2)
sel <- unique(c(seq(1, n_hm, by = 2), n_hm))                  # MTD 컬럼 라벨 항상 표기
axis(1, at = sel, labels = ymv[sel], las = 2, cex.axis = 1.05, tick = FALSE)
if (!is.null(SB_MTD)) abline(v = n_hm - 0.5, col = "black", lwd = 2.5, lty = 2)   # 완결월|MTD 경계
for (i in 1:n_hm) for (j in 1:length(sty))
  text(i, j, sprintf("%.0f", t(Hm)[i, j]), cex = 0.85, col = ifelse(abs(t(Hm)[i, j]) > brk * 0.55, "white", "gray25"))
abline(h = (0:length(sty)) + 0.5, col = "white", lwd = 2)
dev.off()
wf("chart written: smartbeta_heatmap24.png")

## (C) 장기 rolling 12m — 스타일별 소형 패널 (겹침 제거)
SBc <- copy(SB)
for (st in sty) SBc[, (paste0("r12_", st)) := frollmean(get(st), 12)]
SBc[, d := as.Date(paste0(ym, "-01"))]
png(file.path(OUT_DIR, "charts", "smartbeta_rolling12.png"), width = 1250, height = 980)
par(mfrow = c(4, 2), mar = c(2.8, 4.5, 2.8, 1), cex.main = 1.5, cex.axis = 1.15, cex.lab = 1.2)
rng <- range(SBc[, paste0("r12_", sty), with = FALSE], na.rm = TRUE) * 100
for (st in sty) {
  plot(SBc$d, SBc[[paste0("r12_", st)]] * 100, type = "l", lwd = 2.4, col = cols[st], ylim = rng,
       main = KRN[st], xlab = "", ylab = "r12 %")
  abline(h = 0, lty = 3); polygon(c(SBc$d, rev(SBc$d)),
    c(pmax(SBc[[paste0("r12_", st)]] * 100, 0), rep(0, nrow(SBc))), col = adjustcolor(cols[st], 0.15), border = NA)
}
dev.off()
wf("chart written: smartbeta_rolling12.png (small multiples)")

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
