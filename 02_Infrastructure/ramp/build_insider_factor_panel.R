## build_insider_factor_panel.R — FQ-019: insider 파생 팩터 패널 빌더 (armed 배관)
## ─────────────────────────────────────────────────────────────────────────────
## 목적: DART insider 크롤 체크포인트(.cache/dart/insider_backfill/*.csv, read-only)를
##   소비해 월별 종목단 insider 파생 팩터 3종을 만들고, 각 팩터의 배포권
##   top-25 EW long-only net(15bps) active 월수익 패널을 r6 패널
##   (outputs/ramp/r6_factor_deployzone_active.parquet)과 **동일 산식·동일 스키마**로 산출.
##
## ⚠ 이 스크립트는 빌드 배관이다 — 부분 데이터(크롤 진행중) 위에서도 실행 가능하나,
##   그 산출로 판정·L-code·텔레그램 발화 금지 (meta.partial_data 라벨 확인 의무).
##
## 팩터 정의 (기존 dart_insider_signal_ic.R / cmp_signal.py 정의 재사용):
##   공통 필터 = 임원(reporter_class에 '임원') × 시장거래(report_reason에 장내/장외/시간외)
##               — mechanical(스톡옵션·유상신주·상속증여 등) 제외, Cohen-Malloy-Pomorski 2012.
##   INS01_OffNetBuyIntensity3m: trailing 3m 임원 순매수 notional(부호), sign*log1p(|·|) — 강도
##   INS02_OffBuyBreadth6m:      trailing 6m (매수건-매도건)/(매수건+매도건) — 빈도/breadth
##   INS03_OffNetBuyRecency:     최근 순매수월로부터 경과월 * (-1), 24m cap — 최근성
##   (활동 없는 종목-월 = NA — 이벤트 팩터 규약, ic/build_insider_signal 정합.
##    하네스 composite 단계에서 NA→0 중립 처리됨.)
##
## PIT: 신호월 m = 공시 접수월(rcept_dt) — m월 말 시점에 알 수 있는 접수분만 사용.
##      forward 수익 = m+1월 (build_monthly_forward_returns) → 홀딩월 시작 전 데이터만. C5 정합.
##      + truncation-invariance assert: 표본월 3곳에서 "미래 행 제거 후 재계산 == 전체 계산" 검증.
##
## 산출:
##   outputs/ramp/insider_factor_scores.parquet           (signal_date, security_id, factor_id, z)
##   outputs/ramp/insider_factor_deployzone_active.parquet (r6 패널 스키마 + family="Insider")
##   outputs/ramp/insider_panel_meta.json                  (커버리지·gap·PIT assert·partial 라벨)
##
## 실행: cd QM_ROOT && Rscript -e 'source("02_Infrastructure/ramp/build_insider_factor_panel.R")'
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")     # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")

CKDIR   <- ".cache/dart/insider_backfill"                # read-only (크롤 무간섭)
OUT     <- "outputs/ramp"
SCORE_P <- file.path(OUT, "insider_factor_scores.parquet")
PANEL_P <- file.path(OUT, "insider_factor_deployzone_active.parquet")
META_P  <- file.path(OUT, "insider_panel_meta.json")
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8            # r6 Step1과 동일
RECENCY_CAP <- 24L
logf <- file.path(".cache", sprintf("_insider_panel_build_%s.txt", format(Sys.Date(), "%Y%m%d")))
con <- file(logf, "w", encoding="UTF-8")
w <- function(...){ msg <- paste0(...); writeLines(msg, con); flush(con); cat(msg, "\n") }
wf <- function(...) w(sprintf(...))

## ── 1. 체크포인트 로드 (read-only) ───────────────────────────────────────────
files <- list.files(CKDIR, pattern="^\\d{6}\\.csv$", full.names=TRUE)
stopifnot(length(files) > 0)
yms <- sort(gsub("\\.csv$", "", basename(files)))
ym_seq <- function(a, b){ d <- seq(as.Date(paste0(a,"01"), "%Y%m%d"), as.Date(paste0(b,"01"), "%Y%m%d"), by="month"); format(d, "%Y%m") }
full_span <- ym_seq(yms[1], yms[length(yms)])
gaps <- setdiff(full_span, yms)
wf("[panel] 체크포인트 %d개월: %s~%s | gap=%d%s", length(yms), yms[1], yms[length(yms)],
   length(gaps), if(length(gaps)) paste0(" {", paste(head(gaps,10), collapse=","), "}") else "")

raw <- rbindlist(lapply(files, function(f)
  tryCatch(fread(f, colClasses=list(character=c("corp_code","rcept_dt")), showProgress=FALSE),
           error=function(e) NULL)), fill=TRUE)
trades <- raw[!is.na(qty_change) & !is.na(reporter_class)]
wf("[panel] 총 거래행 %d | 고유 corp %d", nrow(trades), uniqueN(trades$corp_code))

## ── 2. 임원 시장거래 필터 + ticker 조인 (dart_insider_signal_ic.R 재사용) ──────
MKT <- "장내|장외|시간외"          # 장내|장외|시간외
OFF <- "임원"                                          # 임원
trades[, qc := as.numeric(qty_change)]; trades[, pr := as.numeric(price)]
off <- trades[grepl(OFF, reporter_class) & grepl(MKT, ifelse(is.na(report_reason), "", report_reason)) & is.finite(qc)]
off[, notional := qc * ifelse(is.finite(pr) & pr > 0, pr, 0)]
off[, dt := as.character(fifelse(!is.na(rcept_dt) & nzchar(rcept_dt), rcept_dt, as.character(filing_date)))]
off[, sig_ym := substr(gsub("[^0-9]", "", dt), 1, 6)]
off <- off[nchar(sig_ym) == 6]
## ★파서 corp_code = 실제 6자리 stock_code → uni.stock_code 조인 (ic 스크립트 규약)
uni <- fread(".cache/dart/universe_corpcodes.csv", colClasses="character")
off <- merge(off, uni[, .(stock_code, ticker)], by.x="corp_code", by.y="stock_code", all.x=TRUE)
off <- off[!is.na(ticker)]
wf("[panel] 임원 시장거래 %d행 | 유니버스 매칭 종목 %d", nrow(off), uniqueN(off$ticker))

## ── 3. 종목-월 집계 → trailing 파생 팩터 3종 (PIT: 접수월 m까지 데이터만) ─────
agg <- off[, .(net_notional = sum(notional, na.rm=TRUE), net_shares = sum(qc, na.rm=TRUE),
               n_buy = sum(qc > 0), n_sell = sum(qc < 0), n_rep = .N), by=.(ticker, sig_ym)]

build_factors <- function(agg_dt, ym_grid){
  ## full ticker×month grid (활동 0 월 채움 — trailing/recency 계산용)
  grid <- CJ(ticker = sort(unique(agg_dt$ticker)), sig_ym = ym_grid)
  g <- merge(grid, agg_dt, by=c("ticker","sig_ym"), all.x=TRUE)
  for (cc in c("net_notional","net_shares","n_buy","n_sell","n_rep")) set(g, which(is.na(g[[cc]])), cc, 0)
  setorder(g, ticker, sig_ym)
  g[, `:=`(nn3 = frollsum(net_notional, 3), rep3 = frollsum(n_rep, 3),
           b6 = frollsum(n_buy, 6), s6 = frollsum(n_sell, 6)), by=ticker]
  ## INS01 강도: trailing 3m signed notional, 활동 없으면 NA
  g[, INS01_OffNetBuyIntensity3m := fifelse(!is.na(rep3) & rep3 > 0, sign(nn3) * log1p(abs(nn3)), NA_real_)]
  ## INS02 빈도/breadth: trailing 6m
  g[, INS02_OffBuyBreadth6m := fifelse(!is.na(b6) & (b6 + s6) > 0, (b6 - s6) / (b6 + s6), NA_real_)]
  ## INS03 최근성: 최근 순매수월(net_shares>0)로부터 경과월, 24m cap, 없으면 NA
  g[, midx := seq_len(.N), by=ticker]
  g[, last_buy := { lb <- fifelse(net_shares > 0, midx, NA_integer_); nafill(lb, type="locf") }, by=ticker]
  g[, INS03_OffNetBuyRecency := fifelse(!is.na(last_buy) & (midx - last_buy) <= RECENCY_CAP,
                                        -as.numeric(midx - last_buy), NA_real_)]
  g[, c("midx","last_buy") := NULL]
  g
}
g <- build_factors(agg, ym_seq(yms[1], yms[length(yms)]))
FIDS <- c("INS01_OffNetBuyIntensity3m","INS02_OffBuyBreadth6m","INS03_OffNetBuyRecency")

## ── 3b. PIT truncation-invariance assert (표본월 3곳) ────────────────────────
## 접수월 m*까지의 체크포인트 행만으로 재계산한 팩터값 == 전체 데이터 계산값 (미래 누출 부재 증명)
pit_ok <- TRUE; pit_detail <- list()
smp <- yms[pmax(1L, floor(length(yms) * c(0.3, 0.6, 0.9)))]
for (m_star in smp) {
  g_tr <- build_factors(agg[sig_ym <= m_star], ym_seq(yms[1], m_star))
  a <- melt(g[sig_ym == m_star, c("ticker", FIDS), with=FALSE], id.vars="ticker", variable.factor=FALSE)
  b <- melt(g_tr[sig_ym == m_star, c("ticker", FIDS), with=FALSE], id.vars="ticker", variable.factor=FALSE)
  m2 <- merge(a, b, by=c("ticker","variable"), all=TRUE)
  same <- m2[, all((is.na(value.x) & is.na(value.y)) | (abs(value.x - value.y) < 1e-12), na.rm=FALSE)]
  same <- isTRUE(same) || isTRUE(m2[, all(fifelse(is.na(value.x), is.na(value.y), !is.na(value.y) & abs(value.x - value.y) < 1e-12))])
  pit_ok <- pit_ok && isTRUE(same)
  pit_detail[[m_star]] <- isTRUE(same)
  wf("[PIT] truncation-invariance @%s: %s (rows %d)", m_star, ifelse(isTRUE(same), "PASS", "FAIL"), nrow(m2))
}
if (!pit_ok) { w("[PIT] ★FAIL — 팩터 구성에 forward 누출. 중단."); close(con); stop("PIT truncation-invariance FAIL") }

## ── 4. sig_ym → r6 signal_date 매핑 + 횡단 z ────────────────────────────────
gd <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_map <- unique(gd[, .(signal_date = as.Date(signal_date))])[, .(signal_date, sig_ym = format(signal_date, "%Y%m"))]
setkey(sig_map, sig_ym)
long <- melt(g[, c("ticker","sig_ym", FIDS), with=FALSE], id.vars=c("ticker","sig_ym"),
             variable.name="factor_id", value.name="v", variable.factor=FALSE)[is.finite(v)]
long <- merge(long, sig_map, by="sig_ym")          # r6 sig_dates 달만 (범위 밖 drop)
## PIT 상한: 신호 최종월 = 크롤 최종월 (그 이후 signal_date 없음을 보장)
stopifnot(max(long$sig_ym) <= yms[length(yms)])
zc <- function(x){ m <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE); if (is.na(s) || s < 1e-9) x - m else (x - m) / s }
long <- long[, if (.N >= 3L) .(security_id = ticker, z = zc(v)) else NULL, by=.(signal_date, factor_id)]
scores <- long[, .(signal_date, security_id, factor_id, z)][is.finite(z)]
wf("[panel] 신호 z 패널: %d행 | 월 %d | 팩터 %s", nrow(scores), uniqueN(scores$signal_date), paste(FIDS, collapse=","))
cov_by_m <- scores[, .(n_names = uniqueN(security_id)), by=.(signal_date, factor_id)]
wf("[panel] 월별 이름수 중앙값: %s",
   paste(cov_by_m[, .(md = median(n_names)), by=factor_id][, sprintf("%s=%d", factor_id, as.integer(md))], collapse=" | "))

## ── 5. 배포권 패널 (r6 Step1과 동일 산식: canonical_screen_bt top-25 EW net active) ──
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[, Date := as.Date(Date)]
sig_dates <- sort(unique(sig_map$signal_date))
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if (length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata); invisible(gc())
RET_DT   <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[, .(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]

rows <- list()
for (fid in FIDS) {
  s <- scores[factor_id == fid, .(Date=as.Date(signal_date), Ticker=security_id, score=z)][!is.na(score)]
  cs <- tryCatch(canonical_screen_bt(s, RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
          liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="ins_panel", strategy_id=fid, diag_dual_basis=FALSE),
          error=function(e){ wf("[panel][ERR %s] %s", fid, conditionMessage(e)); NULL })
  if (is.null(cs) || is.null(cs$period_returns)) next
  pr <- as.data.table(cs$period_returns)
  rows[[fid]] <- data.table(signal_date=as.Date(pr$date), factor_id=fid,
    ret_net=pr$ret_net, benchmark_ret=pr$benchmark_ret, active_bm=pr$ret_net - pr$benchmark_ret,
    family="Insider")
  wf("[panel] %s: %d개월 (%s~%s)", fid, nrow(pr), as.character(min(pr$date)), as.character(max(pr$date)))
}
PANEL_INS <- rbindlist(rows, fill=TRUE)
stopifnot(nrow(PANEL_INS) > 0)
## 스키마 assert: r6 패널과 동일 (append 가능)
stopifnot(identical(sort(names(PANEL_INS)),
                    sort(c("signal_date","factor_id","ret_net","benchmark_ret","active_bm","family"))))

## ── 6. 저장 + meta ──────────────────────────────────────────────────────────
write_parquet(scores, SCORE_P)
write_parquet(PANEL_INS, PANEL_P)
cur_ym <- format(Sys.Date(), "%Y%m")
crawl_complete_hint <- (length(gaps) == 0L) && (yms[length(yms)] >= format(seq(Sys.Date(), by="-2 month", length.out=2)[2], "%Y%m"))
meta <- list(
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  source = "FQ-019 build_insider_factor_panel.R",
  checkpoint_dir = CKDIR, checkpoint_readonly = TRUE,
  crawl_first_ym = yms[1], crawl_last_ym = yms[length(yms)], crawl_n_months = length(yms),
  crawl_gaps = gaps,
  partial_data = !crawl_complete_hint,
  partial_note = if (!crawl_complete_hint) "★부분 데이터 — 이 패널로 판정·L-code·텔레그램 발화 금지 (armed spec 참조)" else "coverage current",
  factors = FIDS, factor_family = "Insider",
  n_score_rows = nrow(scores), n_score_months = uniqueN(scores$signal_date),
  n_panel_rows = nrow(PANEL_INS), n_panel_months = uniqueN(PANEL_INS$signal_date),
  panel_date_range = as.character(range(PANEL_INS$signal_date)),
  pit_truncation_invariance = pit_detail, pit_ok = pit_ok,
  pit_convention = "신호월 m = rcept 접수월; forward = m+1월 (홀딩월 시작 전 데이터만, C5 정합)",
  formula = sprintf("canonical_screen_bt top_n=%d cost_bps=%d liq_min=%.0e (r6 Step1 동일)", TOP_N, COST_BPS, LIQ_MIN),
  schema_parity_with = "outputs/ramp/r6_factor_deployzone_active.parquet"
)
write_json(meta, META_P, auto_unbox=TRUE, pretty=TRUE)
wf("[panel] 저장: %s (%d행) / %s (%d행) / %s", SCORE_P, nrow(scores), PANEL_P, nrow(PANEL_INS), META_P)
wf("[panel] partial_data=%s | PIT ok=%s | DONE", meta$partial_data, pit_ok)
close(con)
cat(sprintf("INSIDER_PANEL_DONE rows_scores=%d rows_panel=%d partial=%s pit_ok=%s log=%s\n",
            nrow(scores), nrow(PANEL_INS), meta$partial_data, pit_ok, logf))
