## run_ramp_autonomous.R — RAMP 완전자율 iteration driver
## Observe(ledger) → M-code 설정그리드 자동탐색 → Document(각 결과) → best surface(governor 정지=수동).
## 실패 ledger에서 학습: 순진한 국면틸트(failed) 대신 데이터-구동 regime 가중(PIT trailing IC) 자동 제안.
## 단일스레드·실측-only(canonical_screen via validate_factor). 무인 구동(스케줄)용.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R"))
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/ramp/ramp_loop.R")
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
log <- file(".cache/_ramp_autonomous.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),log)

w(sprintf("=== RAMP 자율 iteration | %s ===", format(Sys.Date())))
## ── 1. OBSERVE ──
led <- ramp_observe(verbose=FALSE)
w(sprintf("[Observe] L-code %d건 | failure-ledger %d건 (반복 회피)", nrow(led$all %||% data.frame()), nrow(led$fails)))
if(nrow(led$fails)) for(i in seq_len(nrow(led$fails))) w(sprintf("   ⛔ %s", led$fails$sid[i]))

## ── 2. 입력 ──
g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw <- dcast(g, signal_date+security_id ~ family, value.var="group_z")
grp_cols <- setdiff(names(gw), c("signal_date","security_id"))
a <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg <- unique(a[,.(ym=format(Date,"%Y-%m"), regime=regime_state)])[, .SD[1], by=ym]
gw[, ym:=format(signal_date,"%Y-%m")]; gw <- merge(gw, reg, by="ym", all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet")); rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(gw$signal_date)); fwd <- build_monthly_forward_returns(rawdata, sig_dates)

## 점수→백테 헬퍼
score_wts <- function(dt, wts){ X<-as.matrix(dt[,..grp_cols]); X[is.na(X)]<-0; ww<-wts[grp_cols]; ww[is.na(ww)]<-0; ww<-ww/sum(ww)
  d2<-dt[,.(signal_date,security_id)]; d2[,score:=as.numeric(X%*%ww)]; d2[,score:=zc(score),by=signal_date]; d2 }
smooth <- function(d){ setorder(d,security_id,signal_date)
  d[, score:={s<-score; if(length(s)>=2) for(i in 2:length(s)) if(!is.na(s[i])&!is.na(s[i-1])) s[i]<-0.5*s[i]+0.5*s[i-1]; s}, by=security_id]
  d[,score:=zc(score),by=signal_date]; d }
runbt <- function(d,lab){ v<-validate_factor(d[,.(signal_date,security_id,factor_id=lab,neutralized_z=score)],fwd,top_n=25L,cost_bps=15)
  data.table(model=lab, net_sr=v$net_sr%||%NA, port_t=v$portfolio_alpha_t_nw%||%NA, to=v$turnover_annual%||%NA) }

## ── 3. PROPOSE/IMPLEMENT/TEST: 설정 그리드 (ledger 학습 반영) ──
ew <- setNames(rep(1,length(grp_cols)),grp_cols)
res <- list()
res$EW    <- runbt(score_wts(gw,ew), "M_EW")
res$SMOOTH<- runbt(smooth(score_wts(gw,ew)), "M_smooth")

## 데이터-구동 regime 가중 (PIT trailing regime-conditional 그룹 IC) — naive 틸트(failed) 대체
ic <- merge(g[,.(signal_date,security_id,family,group_z)],
            fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],
            by=c("signal_date","security_id"))
gic <- ic[, .(ic=if(.N>=10 && sd(group_z)>0 && sd(Ret_1m)>0) cor(group_z,Ret_1m,method="spearman") else NA_real_),
          by=.(signal_date,family)]
gic <- merge(gic, unique(gw[,.(signal_date,regime)]), by="signal_date")
# 각 (signal_date, family): 동일 regime 과거(strictly <)의 평균 IC → weight = max(.,0)
setorder(gic, family, signal_date)
mreg_rows <- list()
for(d in as.character(sig_dates)){
  dd <- as.Date(d); rg <- gw[signal_date==dd, regime][1]
  wts <- sapply(grp_cols, function(fm){ past <- gic[family==fm & regime==rg & signal_date<dd, ic]; past<-past[is.finite(past)]
    if(length(past)>=3) max(mean(past),0) else 0 })
  if(sum(wts)<1e-9) wts <- ew  # 워밍업: 데이터 부족 시 EW
  mreg_rows[[d]] <- score_wts(gw[signal_date==dd], wts)
}
mdd <- rbindlist(mreg_rows)
res$REGDD  <- runbt(mdd, "M_regime_datadriven")
res$REGDDs <- runbt(smooth(copy(mdd)), "M_regime_dd+smooth")

## (E) 오버레이 — best base(M_regime_dd)에 regime-cash 스칼라 (CRISIS 0.3/CAUTION 0.6/else 1.0, STR_1715 R05류).
##     노출 축소(현금)가 risk-adj 개선하는가 = 검증된 최대 레버를 자율 그리드에 추가.
source("02_Infrastructure/contracts/canonical_screen_bt.R")
ov_in <- mdd[,.(Date=as.Date(signal_date), Ticker=security_id, score)]
cs <- tryCatch(canonical_screen_bt(ov_in,
        fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
        top_n=25L, cost_bps_oneway=15, liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)], liq_min=2e8,
        run_id="ramp_ov", strategy_id="M_regdd_overlay"), error=function(e){w(sprintf("[overlay] err: %s",conditionMessage(e)));NULL})
if(!is.null(cs$period_returns)){
  pr <- as.data.table(cs$period_returns); pr[, ym:=format(as.Date(date),"%Y-%m")]
  pr <- merge(pr, reg, by="ym", all.x=TRUE); pr[is.na(regime),regime:="NORMAL"]
  pr[, cash:=data.table::fcase(regime=="CRISIS",0.3, regime=="CAUTION",0.6, default=1.0)]
  ova <- pr$cash*pr$ret_net - pr$benchmark_ret
  res$OVERLAY <- data.table(model="M_regdd+overlay", net_sr=mean(ova)/sd(ova)*sqrt(12),
                            port_t=NA_real_, to=cs$turnover_annual %||% NA)
}

R <- rbindlist(res, fill=TRUE)[order(-net_sr)]
w("\n[Test] 설정 그리드 (top-25 long-only net):")
for(i in seq_len(nrow(R))) w(sprintf("  %-22s net_sr=%+.3f port_t=%+.2f TO=%.1f", R$model[i], R$net_sr[i], R$port_t[i], R$to[i]))

## ── 4. DOCUMENT (각 + best) + 5. PROMOTE(surface, governor 정지) ──
best <- R[1]
w(sprintf("\n[Best] %s net_sr=%+.3f port_t=%+.2f", best$model, best$net_sr, best$port_t))
improved <- best$model %in% c("M_regime_datadriven","M_regime_dd+smooth") && best$net_sr > R[model=="M_smooth",net_sr]
ramp_document(strategy_id=sprintf("RAMP_AUTO_%s", format(Sys.Date(),"%Y%m%d")),
  grade=ifelse(best$net_sr>0,"B","C"),
  lesson_text=sprintf("자율 iteration: best=%s net_sr=%+.3f port_t=%+.2f. 데이터구동 regime(%s) vs smooth(%+.3f). %s",
    best$model, best$net_sr, best$port_t, R[model=="M_regime_datadriven",sprintf("%+.3f",net_sr)],
    R[model=="M_smooth",net_sr], ifelse(improved,"데이터구동 regime 개선✓","regime 미개선")),
  metrics=list(best_model=best$model, net_sr=best$net_sr, port_t=best$port_t),
  mechanism_hypothesis="PIT trailing regime-IC 가중이 naive 경제틸트(ledger 실패) 대체. governor 정지=자본 도훈 수동.",
  core_reference="RAMP autonomous iteration")
w("\n[Promote] best는 candidate surface만 — 자본 편입 governor 정지(도훈 수동 confirm).")
saveRDS(R, ".cache/_ramp_autonomous.rds"); close(log); cat("AUTO_DONE\n")
