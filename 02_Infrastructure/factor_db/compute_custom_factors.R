#==============================================================================
# compute_custom_factors.R — 선언형 팩터 온보딩 컴퓨트 모듈 (2026-07-01)
#
# 목적: "적재 = 코드 hand-surgery"를 "적재 = 선언(spec)"으로. 코어 compute_*.R을
#   건드리지 않고, custom_factors.json 의 PIT-safe 템플릿 spec만으로 신규 팩터 계산.
#   add_factor() 헬퍼가 spec을 씀. 복잡한 팩터는 여전히 전용 compute_*.R 사용.
#
# 계약(빌더 호출): compute_custom_factors(RAWDATA, sig_date, FUND, CONSENSUS)
#   → data.table(Ticker, Factor_Name, Raw_Value).  RAWDATA는 이미 Date<=sig_date PIT-slice.
#   spec 없으면 NULL(무해 no-op).
#
# spec (custom_factors.json, list of):
#   {id, category, direction, template, params{...}, source="rawdata", disabled}
# 템플릿(PIT-safe, trailing≤sig_date, 종목당 sig_date 1값):
#   momentum{window,skip} · reversal{window} · volatility{window,col=Ret}
#   mean_reversion{window} · trailing_agg{col,window,agg=mean|std|sum|median}
#   ratio{num,den} · gap_freq{window}
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.cf_spec_path <- function() {
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
  cands <- c(file.path(root, "02_Infrastructure", "factor_db", "custom_factors.json"),
             file.path(getwd(), "02_Infrastructure", "factor_db", "custom_factors.json"))
  for (p in cands) if (file.exists(p)) return(p)
  cands[1]
}

# 종목당 trailing 윈도우로 단일값 산출 (RAWDATA sorted by Ticker,Date; Date<=sig_date 가정)
.cf_apply <- function(dt, tmpl, p, sig_date = NULL) {
  W <- as.integer(p$window %||% 0L); K <- as.integer(p$skip %||% 0L)
  col <- p$col %||% "Ret"
  if (tmpl == "momentum") {
    dt[, .(Raw_Value = { n<-.N; if (n < W+1L) NA_real_ else {
      a<-Close[n-K]; b<-Close[n-W]; if (is.na(a)||is.na(b)||b<=0) NA_real_ else a/b-1 } }), by=Ticker]
  } else if (tmpl == "reversal") {
    dt[, .(Raw_Value = { n<-.N; if (n < W+1L) NA_real_ else {
      a<-Close[n]; b<-Close[n-W]; if (is.na(a)||is.na(b)||b<=0) NA_real_ else -(a/b-1) } }), by=Ticker]
  } else if (tmpl == "volatility") {
    dt[, .(Raw_Value = { n<-.N; if (n < W) NA_real_ else sd(get(col)[(n-W+1L):n], na.rm=TRUE) }), by=Ticker]
  } else if (tmpl == "mean_reversion") {
    dt[, .(Raw_Value = { n<-.N; if (n < W) NA_real_ else {
      a<-Close[n]; m<-mean(Close[(n-W+1L):n], na.rm=TRUE); if (is.na(a)||is.na(m)||m<=0) NA_real_ else -(a/m-1) } }), by=Ticker]
  } else if (tmpl == "trailing_agg") {
    agg <- p$agg %||% "mean"
    fn <- switch(agg, mean=function(x) mean(x,na.rm=TRUE), std=function(x) sd(x,na.rm=TRUE),
                 sum=function(x) sum(x,na.rm=TRUE), median=function(x) median(x,na.rm=TRUE), stop("agg"))
    dt[, .(Raw_Value = { n<-.N; if (n < W) NA_real_ else fn(get(col)[(n-W+1L):n]) }), by=Ticker]
  } else if (tmpl == "ratio") {
    num<-p$num; den<-p$den
    dt[, .(Raw_Value = { n<-.N; a<-get(num)[n]; b<-get(den)[n]; if (is.na(a)||is.na(b)||b==0) NA_real_ else a/b }), by=Ticker]
  } else if (tmpl == "gap_freq") {
    dt[, .(Raw_Value = { n<-.N; if (n < W+1L) NA_real_ else {
      idx<-(n-W+1L):n; up<-Open[idx] > Close[idx-1L]; mean(up, na.rm=TRUE) } }), by=Ticker]
  } else if (tmpl == "engine") {
    # ★동결 패널 소비 — 논문 충실구현이 낸 (Date,Ticker,Score) 를 그대로 읽는다.
    #   PIT: 패널의 Date 는 시그널일이고 Score 는 그 날까지의 데이터로 계산됐다(엔진이 강제).
    #   sig_date 에 정확히 해당 행이 없으면 **그 이전 최신 시그널일**을 쓴다 — 미래를 당기지 않는다.
    pp <- p$panel_path
    if (is.null(pp) || !nzchar(pp) || !file.exists(pp))
      stop(sprintf("engine 템플릿: 동결 패널 부재 (%s)", pp %||% "NULL"))
    suppressPackageStartupMessages(library(arrow))
    PN <- as.data.table(arrow::read_parquet(pp))
    if (!all(c("Date", "Ticker", "Score") %in% names(PN)))
      stop("engine 템플릿: 패널에 Date/Ticker/Score 가 없다")
    if (!inherits(PN$Date, "Date")) PN[, Date := as.Date(Date)]
    sd0 <- as.Date(sig_date %||% max(PN$Date, na.rm = TRUE))
    av <- PN[Date <= sd0, unique(Date)]
    if (!length(av)) return(data.table(Ticker = character(0), Raw_Value = numeric(0)))
    PN[Date == max(av) & is.finite(Score), .(Ticker = as.character(Ticker), Raw_Value = as.numeric(Score))]
  } else {
    stop(sprintf("unknown template '%s'", tmpl))
  }
}

`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || (length(a)==1 && is.na(a))) b else a

compute_custom_factors <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sp <- .cf_spec_path()
  if (!file.exists(sp)) return(NULL)
  specs <- tryCatch(jsonlite::fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(specs) || length(specs) == 0) return(NULL)

  dt <- as.data.table(RAWDATA)
  if (!"Ticker" %in% names(dt) || !"Date" %in% names(dt)) return(NULL)
  setorder(dt, Ticker, Date)

  out <- list()
  for (s in specs) {
    if (isTRUE(s$disabled)) next
    id <- s$id; tmpl <- s$template
    if (is.null(id) || is.null(tmpl)) next
    val <- tryCatch(.cf_apply(dt, tmpl, s$params %||% list(), sig_date = sig_date),
                    error = function(e) { cat(sprintf("  [custom] %s ERR: %s\n", id, conditionMessage(e))); NULL })
    if (!is.null(val) && nrow(val) > 0) {
      val <- val[!is.na(Raw_Value)]
      if (nrow(val) > 0) { val[, Factor_Name := id]; out[[id]] <- val[, .(Ticker, Factor_Name, Raw_Value)] }
    }
  }
  if (length(out) == 0) return(NULL)
  rbindlist(out, use.names = TRUE)
}

cat("[compute_custom_factors] Loaded — 선언형 온보딩(custom_factors.json spec). 코어 compute 수정 불필요.\n")
