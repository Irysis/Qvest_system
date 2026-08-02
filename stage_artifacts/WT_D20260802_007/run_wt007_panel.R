# =============================================================================
# run_wt007_panel.R — WT-D20260802_007 insider '참여의 질' 3축 패널 빌드
#   사전등록 preregistration.json 정의 그대로 (성과 데이터 무접촉 — 신호 구성만).
#   축: INS_MAGQ3(★primary, FQ-078) / INS_SEQ12(FQ-079) / INS_EVT3(FQ-080)
#   대조: INS01_BASE3(R9 재현) / INS_MAG_NOFILT3(분해) / INS02_BREADTH6(R33 재현)
#
# PIT: 신호월 m = rcept 접수월(T+0 공개). trailing 창(3m/12m/36m tercile)만 사용
#   — build_axes()는 months<=m 데이터만 소비 (truncation-invariance assert는 eval에서).
# 함정 반영: corp_code 컬럼=6자리 stock_code / encoding UTF-8 / stale parquet 미사용 /
#   D1 원천 직접 (D3 파생 패널 §7b 소비 금지).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_007/run_wt007_panel.R", encoding="UTF-8")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_007")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007p] ", fmt, "\n"), ...))

RX_OFF <- "\uc784\uc6d0"                                  # 임원
RX_MKT <- "\uc7a5\ub0b4|\uc7a5\uc678|\uc2dc\uac04\uc678"  # 장내|장외|시간외
COL_VD <- "\ubcc0\ub3d9\uc77c"                            # 변동일
RX_EVT <- paste0("\uac10\uc790\uacb0\uc815|\ud68c\uc0dd\uc808\ucc28|\uc601\uc5c5\uc815\uc9c0|",
                 "\ud574\uc0b0\uc0ac\uc720|\ubd80\ub3c4\ubc1c\uc0dd|\ucc44\uad8c\uc740\ud589|",
                 "\uad00\ub9ac\uc808\ucc28|\uc601\uc5c5\uc591\ub3c4")
# 감자결정|회생절차|영업정지|해산사유|부도발생|채권은행|관리절차|영업양도 (영업양수 비매칭)

ym_seq <- function(a, b) {
  d <- seq(as.Date(paste0(a, "01"), "%Y%m%d"), as.Date(paste0(b, "01"), "%Y%m%d"), by = "month")
  format(d, "%Y%m")
}

## ── 1. D1 원천 로드 (read-only) ──────────────────────────────────────────────
files <- list.files(".cache/dart/insider_backfill", pattern = "^[0-9]{6}\\.csv$", full.names = TRUE)
stopifnot(length(files) >= 250L)
raw <- rbindlist(lapply(files, function(f)
  tryCatch(fread(f, colClasses = list(character = c("corp_code", "rcept_dt")), showProgress = FALSE),
           error = function(e) NULL)), fill = TRUE)
say("체크포인트 %d개월, %d행", length(files), nrow(raw))

tr <- raw[!is.na(qty_change) & !is.na(reporter_class)]
off <- tr[grepl(RX_OFF, reporter_class) &
          grepl(RX_MKT, ifelse(is.na(report_reason), "", report_reason))]
off[, `:=`(qb = as.numeric(qty_before), qa = as.numeric(qty_after),
           qc = as.numeric(qty_change), pr = as.numeric(price))]
off <- off[is.finite(qc) & qc != 0]
off[, notional := qc * fifelse(is.finite(pr) & pr > 0, pr, 0)]
off[, den := pmax(qb, qa)]
off[, cr := fifelse(is.finite(den) & den > 0, pmin(1, abs(qc) / den), NA_real_)]
off[, sig_ym := substr(gsub("[^0-9]", "", fifelse(!is.na(rcept_dt) & nzchar(rcept_dt),
                       rcept_dt, as.character(filing_date))), 1, 6)]
off <- off[nchar(sig_ym) == 6]
off[, vd := suppressWarnings(as.Date(get(COL_VD)))]
off[, rd := as.Date(rcept_dt, "%Y%m%d")]

uni <- fread(".cache/dart/universe_corpcodes.csv", colClasses = "character")
off <- merge(off, uni[, .(stock_code, Ticker = ticker)], by.x = "corp_code", by.y = "stock_code")
off <- off[!is.na(Ticker)]
say("임원 시장거래 %d행 | 종목 %d | cr 유효 %.1f%%",
    nrow(off), uniqueN(off$Ticker), 100 * mean(is.finite(off$cr)))

## ── 2. 부정 이벤트 (disc_ck 로컬 아카이브 — 크롤 0) ──────────────────────────
DK <- file.path(ROOT, "stage_artifacts/WT-D20260710_005/disc_ck")
ev_files <- list.files(DK, pattern = "\\.csv$", full.names = TRUE)
ev <- rbindlist(lapply(ev_files, function(f)
  tryCatch(fread(f, colClasses = "character", showProgress = FALSE), error = function(e) NULL)),
  fill = TRUE)
ev <- ev[grepl(RX_EVT, report_nm)]
ev[, evt_dt := as.Date(rcept_dt, "%Y%m%d")]
ev <- ev[!is.na(evt_dt) & nchar(stock_code) == 6]
ev <- merge(ev, uni[, .(stock_code, Ticker = ticker)], by = "stock_code")
ev <- unique(ev[, .(Ticker, evt_dt)])
say("부정 이벤트 %d건 | 종목 %d | %s~%s (★348 corp 생존 tilt C6 caveat)",
    nrow(ev), uniqueN(ev$Ticker), as.character(min(ev$evt_dt)), as.character(max(ev$evt_dt)))

## in-window 매수 flag: vd ∈ (evt, evt+60] AND rd >= evt (전 정보 공개 후 소비 보장)
off[, evt_buy := FALSE]
off[, rid := .I]
buys <- off[qc > 0 & !is.na(vd), .(Ticker, vd, rd, rid)]
ev2 <- ev[, .(Ticker, w0 = evt_dt, w1 = evt_dt + 60L)]
hit <- buys[ev2, on = .(Ticker, vd > w0, vd <= w1), nomatch = 0L, allow.cartesian = TRUE,
            .(rid = x.rid, rd = x.rd, w0 = i.w0)]
hit <- hit[rd >= w0]
if (nrow(hit)) off[unique(hit$rid), evt_buy := TRUE]
say("이벤트-창 임원 매수 %d건 (전 매수의 %.2f%%)", sum(off$evt_buy), 100 * mean(off[qc > 0, evt_buy]))

## ── 3. build_axes() — months<=m 데이터만 소비 (truncation-invariance 대상) ────
build_axes <- function(off_dt, ym_grid) {
  ymi <- setNames(seq_along(ym_grid), ym_grid)
  o <- off_dt[sig_ym %chin% ym_grid][, mi := ymi[sig_ym]]

  ## 3a. rolling tercile breakpoint b_m (36m rolling, min 300건 미달 시 expanding)
  crm <- o[is.finite(cr), .(cr = cr, mi = mi)]
  b_m <- sapply(seq_along(ym_grid), function(m) {
    w <- crm[mi >= max(1L, m - 35L) & mi <= m, cr]
    if (length(w) < 300L) w <- crm[mi <= m, cr]
    if (length(w) < 30L) return(NA_real_)
    unname(quantile(w, 1/3, type = 7))
  })

  ## 3b. 월×종목 집계 (INS01/breadth용)
  agg <- o[, .(net_notional = sum(notional, na.rm = TRUE), net_sh = sum(qc, na.rm = TRUE),
               n_buy = sum(qc > 0), n_sell = sum(qc < 0), n_rep = .N), by = .(Ticker, mi)]
  grid <- CJ(Ticker = sort(unique(o$Ticker)), mi = seq_along(ym_grid))
  g <- merge(grid, agg, by = c("Ticker", "mi"), all.x = TRUE)
  for (cc in c("net_notional", "net_sh", "n_buy", "n_sell", "n_rep"))
    set(g, which(is.na(g[[cc]])), cc, 0)
  setorder(g, Ticker, mi)
  g[, `:=`(nn3 = frollsum(net_notional, 3), rep3 = frollsum(n_rep, 3),
           b6 = frollsum(n_buy, 6), s6 = frollsum(n_sell, 6)), by = Ticker]
  g[, INS01_BASE3 := fifelse(!is.na(rep3) & rep3 > 0, sign(nn3) * log1p(abs(nn3)), NA_real_)]
  g[, INS02_BREADTH6 := fifelse(!is.na(b6) & (b6 + s6) > 0, (b6 - s6) / (b6 + s6), NA_real_)]

  ## 3c. MAGQ3 / NOFILT3 (월 루프 — trailing 3m trade-레벨)
  ocr <- o[is.finite(cr)]
  magq <- rbindlist(lapply(seq_along(ym_grid), function(m) {
    w <- ocr[mi >= m - 2L & mi <= m]
    if (nrow(w) == 0L) return(NULL)
    nf <- w[, .(INS_MAG_NOFILT3 = sum(sign(qc) * cr)), by = Ticker]
    fl <- if (is.finite(b_m[m])) w[cr >= b_m[m], .(INS_MAGQ3 = sum(sign(qc) * cr)), by = Ticker]
          else w[0L, .(INS_MAGQ3 = numeric(0)), by = Ticker]
    out <- merge(nf, fl, by = "Ticker", all = TRUE)
    out[, mi := m]
    out
  }))

  ## 3d. SEQ12 (종목 내 활동월 terminal run, lookback 12m, cap 6)
  act <- agg[net_sh != 0][, dir := sign(net_sh)]
  setorder(act, Ticker, mi)
  seq12 <- rbindlist(lapply(seq_along(ym_grid), function(m) {
    a <- act[mi <= m & mi >= m - 11L]
    if (nrow(a) == 0L) return(NULL)
    ## 활동월 sequence에서 terminal 연속 same-dir run 카운트 (12m 창 안 활동월만)
    aw <- a[order(Ticker, mi)]
    aw[, rid := rleid(dir), by = Ticker]
    term <- aw[, .(dir0 = dir[.N], rid0 = rid[.N]), by = Ticker]
    cnt <- aw[term, on = .(Ticker, rid = rid0)][, .(run_n = .N, dir0 = dir0[1]), by = Ticker]
    cnt[, .(Ticker, INS_SEQ12 = dir0 * pmin(run_n, 6L), mi = m)]
  }))

  ## 3e. EVT3 (이벤트-창 매수 notional, trailing 3m)
  oev <- o[evt_buy == TRUE]
  evt3 <- if (nrow(oev)) rbindlist(lapply(seq_along(ym_grid), function(m) {
    w <- oev[mi >= m - 2L & mi <= m]
    if (nrow(w) == 0L) return(NULL)
    w[, .(INS_EVT3 = log1p(sum(pmax(notional, 0)))), by = Ticker][, mi := m]
  })) else data.table(Ticker = character(0), INS_EVT3 = numeric(0), mi = integer(0))

  ## 3f. wide 병합
  base <- g[, .(Ticker, mi, INS01_BASE3, INS02_BREADTH6)]
  P <- Reduce(function(a, b) merge(a, b, by = c("Ticker", "mi"), all = TRUE),
              list(base, magq, seq12, evt3))
  P[, sig_ym := ym_grid[mi]]
  P[]
}

YMG <- ym_seq(min(off$sig_ym), max(off$sig_ym))
say("월 그리드 %s ~ %s (%d)", YMG[1], YMG[length(YMG)], length(YMG))
PAN <- build_axes(off, YMG)
say("패널 %d행 | MAGQ3 non-NA %d | SEQ12 %d | EVT3 %d | BASE3 %d",
    nrow(PAN), sum(is.finite(PAN$INS_MAGQ3)), sum(is.finite(PAN$INS_SEQ12)),
    sum(is.finite(PAN$INS_EVT3)), sum(is.finite(PAN$INS01_BASE3)))

## 월별 이름수 커버리지 (sparsity 정직 보고 재료)
cov <- melt(PAN, id.vars = c("Ticker", "mi", "sig_ym"), variable.factor = FALSE)[is.finite(value)]
cv <- cov[, .(n = uniqueN(Ticker)), by = .(variable, sig_ym)][
  , .(med_names = as.numeric(median(n)), p10 = as.numeric(quantile(n, .1)),
      max = as.numeric(max(n)), n_months = .N), by = variable]
print(cv)

write_parquet(PAN, file.path(OUT, "insider_axes_panel.parquet"))
slim <- off[, .(Ticker, sig_ym, qc, cr, notional, evt_buy, vd, rd)]
write_parquet(slim, file.path(OUT, "trades_slim.parquet"))
write_parquet(ev, file.path(OUT, "neg_events.parquet"))
saveRDS(build_axes, file.path(OUT, "build_axes_fn.rds"))
say("저장 완료 — insider_axes_panel.parquet / trades_slim.parquet / neg_events.parquet")
