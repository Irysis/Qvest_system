## ============================================================================
## register_research_module.R — ML/DPL(Python) 산출물 → FR-소비 sim_result 표준화 + register_module.
## python→R 브릿지 (python-policy: 포트수익률/bt_result는 R 표준함수 경유). 신규 리서치 모드를
##   factor-rotation 풀에 자동 유입시키는 "마지막 다리".
## 두 진입:
##   ① register_ml_prediction(pred, id, ...): per-ticker 예측(Date,Ticker,pred|Score) → run_monthly_simulation
##      → 일간 sim_result(DAILY_NAV_DT+bm_xts) → register_module(origin_mode="ml"). (mini-alpha-search; 실측)
##   ② register_return_series(rs, id, ...): 준비된 수익률 시계열(date, ret, bm) → sim_result(granularity-aware)
##      → register_module(origin_mode="dpl"). DPL처럼 자체 net return을 이미 산출한 경우.
## 발효 2026-06-05 (도훈 mandate: 밤샘 alpha-search/ML·DPL을 FR 풀로 자동 유입).
## ============================================================================
suppressMessages({ library(data.table); library(xts) })

.RRM_INFRA <- function() file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT","G:/Quant_Module_Moltbot")), "02_Infrastructure")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

#' ① ML 예측(per-ticker score) → 일간 백테(run_monthly_simulation) → sim_result → register_module
#' @param pred data.table/df: Date, Ticker, pred(또는 Score)
register_ml_prediction <- function(pred, strategy_id, grade="ungraded", origin_mode="ml",
                                   n_holdings=20L, weight_method="ivol", commission=0.0015,
                                   start_date=NULL, role=NA, meta=list()) {
  INFRA <- .RRM_INFRA()
  if(!exists("PROJECT_ROOT"))            source(file.path(INFRA, "config.R"))   # backtest_harness 상대 재소스 스킵용 선소스
  if(!exists("run_monthly_simulation"))  source(file.path(INFRA, "backtest_harness.R"))
  if(!exists("register_module"))         source(file.path(INFRA, "contracts", "register_module.R"))
  pd <- as.data.table(pred)
  if("pred" %in% names(pd) && !"Score" %in% names(pd)) setnames(pd, "pred", "Score")
  stopifnot(all(c("Date","Ticker","Score") %in% names(pd)))
  pd[, Date := as.Date(Date)]
  if(!is.null(start_date)) pd <- pd[Date >= as.Date(start_date)]
  res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)
  if(!inherits(BM_DT$Date,"Date"))   BM_DT[,   Date:=as.Date(Date)]
  if(!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date:=as.Date(Date)]
  sim <- run_monthly_simulation(RAWDATA, BM_DT, pd, n_holdings=n_holdings, weight_method=weight_method,
           commission=commission, buffer_zone=list(keep_n=as.integer(2L*n_holdings), entry_n=as.integer(0.8*n_holdings)))
  register_module(sim, strategy_id, grade=grade, origin_mode=origin_mode, role=role,
                  meta=modifyList(list(bridge="ml_prediction", n_holdings=n_holdings, weight_method=weight_method), meta))
}

#' ② 준비된 수익률 시계열 → sim_result → register_module. (DPL 월별 net return 등)
#' @param rs data.table/df: date_col, ret_col(net return), bm_col(benchmark return)
register_return_series <- function(rs, strategy_id, date_col="date", ret_col="ret_net", bm_col="BM_Ret",
                                   grade="ungraded", origin_mode="dpl", role=NA, meta=list()) {
  INFRA <- .RRM_INFRA()
  if(!exists("register_module")) source(file.path(INFRA, "contracts", "register_module.R"))
  d <- as.data.table(rs)
  stopifnot(all(c(date_col, ret_col) %in% names(d)))
  d <- d[, .(Date=as.Date(get(date_col)), r=as.numeric(get(ret_col)),
             bm=if(bm_col %in% names(d)) as.numeric(get(bm_col)) else 0)]
  setorder(d, Date); d <- d[is.finite(r)]
  # 빈도 감지 (granularity flag — build_module_performance/RCMA가 월간 모듈 정합 처리)
  med_diff <- if(nrow(d) > 3) stats::median(as.numeric(diff(d$Date))) else 1
  freq <- if(med_diff >= 20) "monthly" else "daily"
  # Strategy_Ret = 주어진 net return(자체합성 아님). NAV = 그 수익률의 누적가치(표시/MDD용).
  sim <- list(
    DAILY_NAV_DT = data.table(Date=d$Date, NAV=cumprod(1+d$r), Strategy_Ret=d$r),
    bm_xts = xts(d$bm, order.by=d$Date), strategy_xts = xts(d$r, order.by=d$Date),
    freq = freq)
  register_module(sim, strategy_id, grade=grade, origin_mode=origin_mode, role=role,
                  meta=modifyList(list(bridge="return_series", freq=freq), meta))
}

cat("[register_research_module.R] Loaded — register_ml_prediction() / register_return_series()\n")
