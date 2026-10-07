## noLayer4 book — 데일리 mark-to-market (모닝브리핑용). 현 라이브 홀딩 × RAWDATA 일별.
## 월간 리밸(forward_weights_R05_noLayer4.R)이 최신 배포홀딩 산출 → 이 스크립트가 매일 평가.
## mark_faithtrend_daily.R 미러 (도훈 지시 2026-07-03 Layer4 제거 → noLayer4 book 전환).
##   변경점: BOOK_ID/HU(슬롯2-3)/홀딩패턴(_noLayer4_)/LT(noLayer4 live_track)/ledger seed(2-3 03_period_returns, ret_net·date→ym).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT,"02_Infrastructure/portfolio/resolve_admitted_slot.R"))
PRIOR_BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"   # 이관 원본(이력 승계용) — 갱신 불요
.slotres <- tryCatch(resolve_admitted_slot(root=ROOT, fallback_id=PRIOR_BOOK_ID), error=function(e) NULL)
BOOK_ID  <- if (!is.null(.slotres)) .slotres$id else PRIOR_BOOK_ID
HU <- if (!is.null(.slotres)) .slotres$holdings_dir else
        file.path(ROOT,"05_Production/2.Factor_Model",paste0("2-3.",PRIOR_BOOK_ID),"02_holdings_universe")
LT <- live_track_lane(BOOK_ID, root=ROOT, carry_from=PRIOR_BOOK_ID)
send_tg <- Sys.getenv("NOLAYER4_DAILY_TG", Sys.getenv("FAITH_DAILY_TG","1"))=="1"

## 0) ★배포 북 정합 (2026-08-01 수리) — 마킹 대상은 이제 admitted 북에서 **해석**된다.
##    사건: 2026-07-19 D3 swap-in 으로 admitted 가 ..._M4gAE_...(슬롯 2-4)로 바뀌었는데
##    이 스크립트는 슬롯 2-3 에 묶여 있었다. gate=1.00 인 달에는 두 북 산출이 같아 티가 안 나고,
##    m4 발화월에만 **배포되지 않은 북을 매일 마킹**하게 된다 — 조용히 틀리는 유형.
##    이제 남은 위험은 "해석 자체가 실패해 폴백으로 내려간 경우"뿐이므로 그것만 경고한다.
if (is.null(.slotres)) {
  cat(sprintf(paste0("[nolayer4-daily][WARN] ★admitted 슬롯 해석 실패 — 구 북 %s 폴백으로 마킹 중.\n",
                     "   book_state.json / 05_Production 슬롯 구성 확인 필요.\n"), BOOK_ID))
}

## 1) 보유 파일 체인 (리밸 date = 파일명) — 그날 유효한 북 = reb_date < 그날 인 최신 파일(파일 날짜 다음 거래일부터 적용)
##    ★2026-10-07 수리(도훈 "YTD 연누적 이상"): 구판은 **최신 파일 하나**로 reb_date 이후를 매수후보유했다.
##      ① 리밸이 늦으면(10월 비중 10-07 저녁 산출) 'MTD' 가 09-01 부터 쌓여 9·10월이 섞였다.
##      ② QTD/YTD 원장(book_monthly_ledger.csv)이 슬롯 2-4 이관(08-01) 때 seed 원천 부재로 **빈 파일**이 되고,
##         월말 append 도 없어 8월부터 YTD = MTD 였다(07-27 YTD +84% → 08-03 +0.27%).
##    → 일별 북 수익을 보유 기간별로 이어 붙이고(기간 안 = 매수후보유 드리프트), MTD = 이번 달 1일부터.
##      완료월 수익 = 같은 레인의 live_book_series.csv(월간 러너가 매달 연장 · 15bps 순수익). 없는 달만 일별 체인으로 메운다.
TAG <- if (!is.null(.slotres)) .slotres$tag else "noLayer4"
HUD <- if (!is.null(.slotres)) .slotres$holdings_dir else HU
hf <- data.table(path = list.files(HUD, pattern = sprintf("^\\d{8}_%s_weights_cap_0p20\\.csv$", TAG), full.names = TRUE))
if (!nrow(hf)) { cat("[nolayer4-daily] 배포 홀딩 없음 — 월간 리밸 선행 필요.\n"); quit(save = "no") }
hf[, reb := as.Date(substr(basename(path), 1, 8), "%Y%m%d")]; setorder(hf, reb)
hf <- hf[!is.na(reb)]
.W <- lapply(hf$path, function(p) { w <- fread(p); w[Ticker != "CASH" & Weight > 0, .(Ticker, Name, Weight)] })
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"), col_select = c("Date", "Ticker", "Ret")))
raw[, Date := as.Date(Date)]
raw <- raw[Ticker %in% unique(unlist(lapply(.W, function(w) w$Ticker))) & Date > min(hf$reb)]
cal <- sort(unique(raw$Date))
if (!length(cal)) { cat("[nolayer4-daily] 리밸 이후 신규 거래일 없음 — 데이터 대기.\n"); quit(save = "no") }
.kof <- function(d) { k <- which(hf$reb < d); if (length(k)) max(k) else NA_integer_ }

## 일별 북 수익 (d_from, d_to] — 기간 k 마다 cash + Σ w·Π(1+r) 경로, 일수익 = nav/전일 nav − 1
book_daily <- function(d_from, d_to) {
  days <- cal[cal > d_from & cal <= d_to]
  if (!length(days)) return(data.table(Date = as.Date(character()), ret = numeric(), k = integer()))
  ks <- vapply(days, .kof, 1L)
  out <- list()
  for (k in unique(ks[!is.na(ks)])) {
    w <- .W[[k]]; cash <- 1 - sum(w$Weight); dk <- days[ks %in% k]
    r <- raw[Ticker %in% w$Ticker & Date > hf$reb[k] & Date <= max(dk)]
    allD <- cal[cal > hf$reb[k] & cal <= max(dk)]
    g <- CJ(Ticker = w$Ticker, Date = allD); g <- merge(g, r, by = c("Ticker", "Date"), all.x = TRUE)
    g[is.na(Ret), Ret := 0]; setorder(g, Ticker, Date); g[, cr := cumprod(1 + Ret), by = Ticker]
    g <- merge(g, w[, .(Ticker, Weight)], by = "Ticker")
    nav <- g[, .(nav = cash + sum(Weight * cr)), by = Date][order(Date)]
    nav[, ret := nav / shift(nav, fill = 1) - 1]
    out[[length(out) + 1L]] <- nav[Date %in% dk, .(Date, ret, k = k)]
  }
  rbindlist(out)[order(Date)]
}

mark_day <- function(last_d) {
  ms <- as.Date(format(last_d, "%Y-%m-01")); pe <- suppressWarnings(max(cal[cal < ms])); if (!is.finite(pe)) pe <- min(hf$reb)
  bd <- book_daily(pe, last_d)
  mtd <- prod(1 + bd$ret) - 1; dayret <- if (nrow(bd) && max(bd$Date) == last_d) bd$ret[nrow(bd)] else NA_real_
  k <- .kof(last_d); w <- .W[[k]]
  ## 완료월 원장 = live_book_series(return_ym · ret_net) → 없는 달은 일별 체인
  ser <- tryCatch(fread(file.path(LT, "live_book_series.csv"), select = c("return_ym", "ret_net", "ret_net_source")), error = function(e) NULL)
  cy <- format(last_d, "%Y"); cym <- format(last_d, "%Y-%m")
  want <- sprintf("%s-%02d", cy, seq_len(as.integer(format(last_d, "%m")) - 1L))
  led <- if (!is.null(ser)) ser[return_ym %in% want, .(ym = return_ym, ret = ret_net,
                                source = fifelse(grepl("^manifest_anchor", ret_net_source), "live", "backtest"))] else data.table(ym = character(), ret = numeric(), source = character())
  for (m in setdiff(want, led$ym)) {
    m1 <- as.Date(paste0(m, "-01")); m2 <- seq(m1, by = "month", length.out = 2)[2] - 1
    p0 <- suppressWarnings(max(cal[cal < m1])); if (!is.finite(p0) || p0 < min(hf$reb)) next
    x <- book_daily(p0, m2); if (nrow(x)) led <- rbind(led, data.table(ym = m, ret = prod(1 + x$ret) - 1, source = "daily_chain"))
  }
  setorder(led, ym)
  cq <- (as.integer(format(last_d, "%m")) - 1L) %/% 3L + 1L; qmos <- sprintf("%s-%02d", cy, ((cq - 1L) * 3L + 1L):((cq - 1L) * 3L + 3L))
  qd <- led[ym %in% qmos]; yd <- led
  list(last_d = last_d, k = k, reb = hf$reb[k], w = w, invested = sum(w$Weight), mtd = mtd, dayret = dayret,
       qtd = prod(1 + qd$ret) * (1 + mtd) - 1, ytd = prod(1 + yd$ret) * (1 + mtd) - 1, led = led,
       n_days = nrow(bd), pending = hf$reb[nrow(hf)] < ms, ms = ms, pe = pe)
}

bmk <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet"))); bcol <- intersect(c("BM_Ret", "Ret"), names(bmk))[1]
bmk[, Date := as.Date(Date)]
kospi <- function(pe, d) { x <- bmk[Date > pe & Date <= d & is.finite(get(bcol))]; c(mtd = prod(1 + x[[bcol]]) - 1, day = { v <- bmk[Date == d, get(bcol)]; if (length(v)) v[1] else NA_real_ }) }

## 2) 오늘(최신 거래일) 마킹
last_d <- max(cal); M <- mark_day(last_d)
reb_date <- M$reb; stk <- M$w; invested <- M$invested; cash <- 1 - invested
mtd <- M$mtd; dayret <- M$dayret; qtd <- M$qtd; ytd <- M$ytd; days <- seq_len(M$n_days)
kb <- kospi(M$pe, last_d); bm_mtd <- kb[["mtd"]]; bm_day <- kb[["day"]]
cum <- raw[Ticker %in% stk$Ticker & Date > reb_date & Date <= last_d][, .(cum = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
fwrite(M$led, file.path(LT, "book_monthly_ledger.csv"))   # 원장 = 파생 거울(완료월 · 출처 표기)
n_bt <- sum(M$led$source == "backtest"); n_lv <- sum(M$led$source != "backtest")
cat(sprintf("[nolayer4-daily] %s | 보유 %s (리밸 %s)%s | 이번 달 %d거래일\n", last_d, basename(hf$path[M$k]), reb_date,
            if (M$pending) " ★이번 달 리밸 대기 — 직전 보유로 평가" else "", M$n_days))
cat(sprintf("  DTD %+.2f%% | MTD %+.2f%% | QTD %+.2f%% | YTD %+.2f%% (백테 %d개월 + 라이브 %d개월 + 당월) | KOSPI MTD %+.2f%%\n",
            dayret * 100, mtd * 100, qtd * 100, ytd * 100, n_bt, n_lv, bm_mtd * 100))

## 3) daily_nav.csv append (★NOLAYER4_BACKFILL=1 이면 기존 행 전부를 같은 산식으로 재계산 — 소급 표식 recalc)
dn_path <- file.path(LT, "daily_nav.csv")
.row <- function(MM, note = "") { kk <- kospi(MM$pe, MM$last_d)
  data.table(date = as.character(MM$last_d), reb_date = as.character(MM$reb), book_dtd = MM$dayret, book_mtd = MM$mtd, book_qtd = MM$qtd,
             book_ytd = MM$ytd, book_day = MM$dayret, invested = MM$invested, cash = 1 - MM$invested, kospi_mtd = kk[["mtd"]],
             kospi_day = kk[["day"]], n_days = MM$n_days, recalc = note) }
row <- .row(M)
dn <- if (file.exists(dn_path)) fread(dn_path, colClasses = list(character = c("date", "reb_date"))) else NULL
if (identical(Sys.getenv("NOLAYER4_BACKFILL"), "1") && !is.null(dn)) {
  tag <- sprintf("backfill_%s(체인·월초 MTD·live_book_series 원장)", format(Sys.Date(), "%Y%m%d"))
  old <- as.Date(dn$date); old <- old[old > min(hf$reb) & old %in% cal & old != last_d]
  keep <- dn[!(as.Date(date) %in% old) & date != as.character(last_d)]   # 체인으로 못 재는 행(레인 승계 이전 등)은 원본 유지
  dn <- rbindlist(c(list(keep), lapply(old, function(d) .row(mark_day(d), tag)), list(row)), fill = TRUE)
  cat(sprintf("[nolayer4-daily] ★소급 재계산 %d행 (%s)\n", length(old), tag))
} else if (!is.null(dn)) { dn <- dn[date != as.character(last_d)]; dn <- rbind(dn, row, fill = TRUE) } else dn <- row
setorder(dn, date); fwrite(dn, dn_path)

## 4) 모닝브리핑 Telegram (데일리 북 성과)
if(send_tg) tryCatch({
  source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
  top <- stk[order(-Weight)][seq_len(min(5,nrow(stk)))]
  ## ★v10 (2026-09-03): agent Monitoring(v10 퇴역) → Book · §5.6b 계층 표제 [BOOK].
  .bkid <- tryCatch({
    .br  <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/book/book_registry.json"), simplifyVector = FALSE)
    .act <- Filter(function(e) identical(e$status, "active"), .br$entries)
    .mm  <- Filter(function(e) identical(e$strategy_id, BOOK_ID), .act)
    if (length(.mm)) .mm[[1]]$book_id else if (length(.act)) .act[[1]]$book_id else "BOOK"
  }, error = function(e) "BOOK")
  tg_agent_brief(agent="Book", title=sprintf("[BOOK] 트래킹 — %s 일별 (%s)", .bkid, as.character(last_d)),
    sections=list(
      list(type="summary", emoji="📈", body=sprintf("%s 보유 기준 평가 (이번 달 %d거래일)%s. 노출 %.0f%%·현금 %.0f%%.", format(reb_date, "%m월"), length(days), if (isTRUE(M$pending)) " — 이번 달 리밸 대기, 직전 보유로 평가" else "", invested*100, cash*100)),
      list(type="kv", emoji="📊", heading=sprintf("성과 북/KOSPI (기준 %s)", last_d),
        kv=list("DTD 일간"=sprintf("%+.2f%% / %+.2f%%", dayret*100, ifelse(is.na(bm_day),0,bm_day)*100),
                "MTD 월누적"=sprintf("%+.2f%% / %+.2f%%", mtd*100, bm_mtd*100),
                "QTD 분기누적"=sprintf("%+.2f%%", qtd*100),
                "YTD 연누적"=sprintf("%+.2f%% (백테 %d개월+라이브 %d개월+당월)", ytd*100, n_bt, n_lv),
                "노출 / 현금"=sprintf("%.0f%% / %.0f%%", invested*100, cash*100))),
      list(type="bullet", emoji="📌", heading="상위 보유",
        items=sprintf("%s %.1f%% (누적 %+.1f%%)", top$Name, top$Weight*100, merge(top[,.(Ticker)],cum,by="Ticker",all.x=TRUE)$cum*100))),
    footer="📚 월간 리밸=forward_weights_R05_noLayer4 · 데일리 mark-to-market")
}, error=function(e) cat("[TG skip]",conditionMessage(e),"\n"))
cat("=== nolayer4-daily done ===\n")
