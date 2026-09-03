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

## 1) 최신 배포 홀딩 = admitted 슬롯의 최신 파일 (리밸 date = 파일명)
##    구판 3중 결함 (도훈 mandate 2026-08-01 "날짜 하드코딩은 다 없애라"):
##      ① HU 가 슬롯 2-3 고정 → 교체 후 배포되지 않은 북을 매일 마킹
##      ② 패턴 `_noLayer4_` 고정 → 슬롯 2-4 의 `20260801_M4gAE_...` 을 **0건**으로 보고 종료
##      ③ `which.max(file.mtime())` → 파일 재생성/복사에 최신 판정이 뒤집힘
##    → 해석기(정확일치 슬롯 + 파일명 사전순)로 교체. 실패 시 구 경로 폴백 후 경고.
wf <- if (!is.null(.slotres)) .slotres$holdings else {
  .w <- list.files(HU, pattern="_weights_cap_0p20\\.csv$", full.names=TRUE)
  if (length(.w)) .w[order(basename(.w))][length(.w)] else character(0)
}
if(!length(wf)){cat("[nolayer4-daily] 배포 홀딩 없음 — 월간 리밸 선행 필요.\n"); quit(save="no")}
reb_date <- as.Date(gsub(".*/(\\d{8})_.*","\\1",wf),format="%Y%m%d")
if (is.na(reb_date)) { cat(sprintf("[nolayer4-daily] 보유 파일명에서 리밸일 파싱 실패: %s\n", basename(wf))); quit(save="no") }
cat(sprintf("[nolayer4-daily] 마킹 대상: %s (리밸 %s)\n", basename(wf), reb_date))
W <- fread(wf); stk <- W[Ticker!="CASH" & Weight>0]; invested <- sum(stk$Weight); cash <- 1-invested

## 2) RAWDATA 일별 (리밸 이후) — 신선 캐시
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),col_select=c("Date","Ticker","Ret")))
raw[, Date:=as.Date(Date)]; rd <- raw[Ticker %in% stk$Ticker & Date>reb_date]
if(!nrow(rd)){cat(sprintf("[nolayer4-daily] 리밸(%s) 이후 신규 거래일 없음 — 데이터 대기.\n",reb_date)); quit(save="no")}
days <- sort(unique(rd$Date)); last_d <- days[length(days)]
## 종목 누적/전일 수익 → 북 (매수후보유, CASH=0)
cum <- rd[, .(cum=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
lastret <- rd[Date==last_d, .(Ticker,dret=Ret)]
m <- merge(stk[,.(Ticker,Weight)], cum, by="Ticker", all.x=TRUE); m <- merge(m, lastret, by="Ticker", all.x=TRUE)
mtd <- sum(m$Weight*m$cum, na.rm=TRUE); dayret <- sum(m$Weight*m$dret, na.rm=TRUE)

## 2b) QTD/YTD (월수익 원장 ledger: 배포前 = 백테 seed, 배포後 = 라이브 월말 append) ─────
##   DTD=dayret(일간) / MTD=mtd(당월) 는 위에서 산출. QTD/YTD = 원장 완료월 × (1+현 MTD).
led_path <- file.path(LT, "book_monthly_ledger.csv")
if (!file.exists(led_path)) {
  ## 원장 seed 도 admitted 슬롯에서 (구판 슬롯 2-3 고정 — 교체 후 구 북 수익으로 seed 했다)
  .pr <- if (!is.null(.slotres)) file.path(.slotres$slot_dir,"04_backtest_results/03_period_returns.csv")
         else file.path(ROOT,"05_Production/2.Factor_Model",paste0("2-3.",PRIOR_BOOK_ID),
                        "04_backtest_results/03_period_returns.csv")
  btf <- tryCatch(fread(.pr), error=function(e) NULL)
  dym <- format(reb_date, "%Y-%m")
  if (!is.null(btf) && "date" %in% names(btf) && "ret_net" %in% names(btf)) {
    btf[, ym := substr(as.character(date), 1, 7)]
    seed <- btf[ym >= paste0(format(reb_date,"%Y"),"-01") & ym < dym, .(ym, ret=ret_net, source="backtest")]
    fwrite(seed, led_path)
  } else fwrite(data.table(ym=character(), ret=numeric(), source=character()), led_path)
}
led <- fread(led_path)
cy <- format(last_d,"%Y"); cq <- (as.integer(format(last_d,"%m"))-1L)%/%3L+1L; cym <- format(last_d,"%Y-%m")
qmos <- sprintf("%s-%02d", cy, ((cq-1L)*3L+1L):((cq-1L)*3L+3L))
qd <- led[ym %in% qmos & ym < cym]; yd <- led[substr(ym,1,4)==cy & ym < cym]
qtd <- prod(1+qd$ret, na.rm=TRUE)*(1+mtd)-1; ytd <- prod(1+yd$ret, na.rm=TRUE)*(1+mtd)-1
cat(sprintf("  DTD %+.2f%% | MTD %+.2f%% | QTD %+.2f%% (완료 %d개월+MTD) | YTD %+.2f%% (백테 %d개월+라이브)\n",
            dayret*100, mtd*100, qtd*100, nrow(qd), ytd*100, nrow(yd)))
## KOSPI 비교
bmk <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet"))); bcol<-intersect(c("BM_Ret","Ret"),names(bmk))[1]
bmk[, Date:=as.Date(Date)]; bmd <- bmk[Date>reb_date & Date<=last_d & is.finite(get(bcol))]
bm_mtd <- prod(1+bmd[[bcol]],na.rm=TRUE)-1; bm_day <- bmk[Date==last_d, get(bcol)][1]

cat(sprintf("[nolayer4-daily] %s | 리밸 %s 이후 %d거래일\n", last_d, reb_date, length(days)))
cat(sprintf("  북 MTD %+.2f%% (전일 %+.2f%%) | 노출 %.0f%% 현금 %.0f%% | KOSPI MTD %+.2f%%\n",
            mtd*100, dayret*100, invested*100, cash*100, bm_mtd*100))

## 3) daily_nav.csv append
dn_path <- file.path(LT,"daily_nav.csv")
row <- data.table(date=as.character(last_d), reb_date=as.character(reb_date), book_dtd=dayret, book_mtd=mtd, book_qtd=qtd, book_ytd=ytd, book_day=dayret,
                  invested=invested, cash=cash, kospi_mtd=bm_mtd, kospi_day=bm_day, n_days=length(days))
if(file.exists(dn_path)){dn<-fread(dn_path, colClasses=list(character=c("date","reb_date"))); dn<-dn[date!=as.character(last_d)]; dn<-rbind(dn,row,fill=TRUE)} else dn<-row
setorder(dn,date); fwrite(dn,dn_path)

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
      list(type="summary", emoji="📈", body=sprintf("현 라이브 북 평가 (리밸 %s 이후 %d거래일). 노출 %.0f%%·현금 %.0f%% (Layer4 제거·m4×β_R05).", reb_date, length(days), invested*100, cash*100)),
      list(type="kv", emoji="📊", heading=sprintf("성과 북/KOSPI (기준 %s)", last_d),
        kv=list("DTD 일간"=sprintf("%+.2f%% / %+.2f%%", dayret*100, ifelse(is.na(bm_day),0,bm_day)*100),
                "MTD 월누적"=sprintf("%+.2f%% / %+.2f%%", mtd*100, bm_mtd*100),
                "QTD 분기누적"=sprintf("%+.2f%%", qtd*100),
                "YTD 연누적"=sprintf("%+.2f%% (백테+라이브)", ytd*100),
                "노출 / 현금"=sprintf("%.0f%% / %.0f%%", invested*100, cash*100))),
      list(type="bullet", emoji="📌", heading="상위 보유",
        items=sprintf("%s %.1f%% (누적 %+.1f%%)", top$Name, top$Weight*100, merge(top[,.(Ticker)],cum,by="Ticker",all.x=TRUE)$cum*100))),
    footer="📚 월간 리밸=forward_weights_R05_noLayer4 · 데일리 mark-to-market")
}, error=function(e) cat("[TG skip]",conditionMessage(e),"\n"))
cat("=== nolayer4-daily done ===\n")
