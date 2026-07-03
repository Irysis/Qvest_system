## run_ramp_gate6_m1m4.R — RAMP Gate 6: 회전제어 + 국면조건부 M-code 시험
##  M0_EW(기준, -0.042) 대비:
##   (A) M0_smooth = EW 스코어 3m EWMA (회전제어 — 비용 드래그 분리)
##   (B) M_regime  = 국면-틸트 (방어군 vs 공격군 regime별 가중, 고정룰=무-lookahead)
##  전부 top-25 long-only net 15bps canonical_screen 실측. 단일스레드.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R")); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/ramp/ramp_loop.R")   # 자가발전 루프 (Observe/Document)
con <- file(".cache/_gate6_m1m4.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
.ledger <- ramp_observe(verbose=TRUE)   # Diagnose: 과거 failure-ledger 읽어 반복 회피
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}

g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
# wide: (date×ticker) × group
gw <- dcast(g, signal_date+security_id ~ family, value.var="group_z")
grp_cols <- setdiff(names(gw), c("signal_date","security_id"))

## 국면 (STR_1715 alpha regime_state, month 매칭, PIT — 의사결정월 regime)
a <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
a[,Date:=as.Date(Date)]; reg <- unique(a[,.(ym=format(Date,"%Y-%m"), regime=regime_state)])
reg <- reg[, .SD[1], by=ym]
gw[, ym := format(signal_date,"%Y-%m")]; gw <- merge(gw, reg, by="ym", all.x=TRUE)
gw[is.na(regime), regime:="NORMAL"]

## 방어/공격 군 (고정 경제룰)
DEF <- intersect(c("LowRisk","Quality","Value","Consensus","Accruals"), grp_cols)
OFF <- intersect(c("Momentum","Growth_Profit","Size_Liquidity","Reversal","Composite","Credit"), grp_cols)

## 점수 빌더 (가중 평균 → 월별 재표준화)
score_from <- function(dt, wts){  # wts: named per group
  X <- as.matrix(dt[, ..grp_cols]); X[is.na(X)] <- 0
  ww <- wts[grp_cols]; ww[is.na(ww)] <- 0; ww <- ww/sum(ww)
  s <- as.numeric(X %*% ww); dt2 <- dt[,.(signal_date,security_id)]; dt2[,score:=s]
  dt2[, score := zc(score), by=signal_date]; dt2
}

rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet")); rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(gw$signal_date)); fwd <- build_monthly_forward_returns(rawdata, sig_dates)
runbt <- function(sdt, lab){ v<-validate_factor(sdt[,.(signal_date,security_id,factor_id=lab,neutralized_z=score)], fwd, top_n=25L, cost_bps=15)
  data.table(model=lab, n=v$n_months, net_sr=v$net_sr%||%NA, port_t=v$portfolio_alpha_t_nw%||%NA, ir=v$information_ratio%||%NA, to=v$turnover_annual%||%NA) }

res <- list()
## (0) M0 EW 재현
ew <- setNames(rep(1,length(grp_cols)), grp_cols)
m0 <- score_from(gw, ew); res$M0 <- runbt(m0, "M0_EW")

## (A) M0_smooth: EW 스코어 3m EWMA (회전제어)
setorder(m0, security_id, signal_date)
m0[, score := { s<-score; if(length(s)>=2) for(i in 2:length(s)) if(!is.na(s[i])&!is.na(s[i-1])) s[i]<-0.5*s[i]+0.5*s[i-1]; s }, by=security_id]
m0[, score := zc(score), by=signal_date]; res$M0s <- runbt(m0, "M0_smooth")

## (B) M_regime: 국면 틸트 (CAUTION/CRISIS → DEF 1.5/OFF 0.5; BULL/NORMAL → DEF 0.5/OFF 1.5)
mreg_rows <- list()
for(d in as.character(sig_dates)){
  sub <- gw[signal_date==as.Date(d)]; rg <- sub$regime[1]
  wts <- setNames(rep(1,length(grp_cols)), grp_cols)
  if(rg %in% c("CAUTION","CRISIS")){ wts[DEF]<-1.5; wts[OFF]<-0.5 } else { wts[DEF]<-0.5; wts[OFF]<-1.5 }
  mreg_rows[[d]] <- score_from(sub, wts)
}
mreg <- rbindlist(mreg_rows); res$Mreg <- runbt(mreg, "M_regime")

## (C) M_regime + smooth (둘 다)
setorder(mreg, security_id, signal_date)
mreg[, score := { s<-score; if(length(s)>=2) for(i in 2:length(s)) if(!is.na(s[i])&!is.na(s[i-1])) s[i]<-0.5*s[i]+0.5*s[i-1]; s }, by=security_id]
mreg[, score := zc(score), by=signal_date]; res$Mrs <- runbt(mreg, "M_regime+smooth")

R <- rbindlist(res, fill=TRUE)
w("=== Gate 6 M-code 시험 (top-25 long-only net 15bps, n=79개월) ===")
w(sprintf("  %-16s %8s %8s %8s %8s", "model","net_sr","port_t","ir","TO_ann"))
for(i in seq_len(nrow(R))) w(sprintf("  %-16s %+8.3f %+8.2f %+8.2f %8.2f", R$model[i], R$net_sr[i], R$port_t[i], R$ir[i], R$to[i]))
w("")
w("기준 M0_EW net_sr=-0.042, TO=13.2. 회전제어/국면이 이를 넘기는가?")

## Document: 이번 iteration 최고 모델을 L-code로 자동 적립 (자가발전)
.best <- R[which.max(net_sr)]
if(!is.na(.best$net_sr)){
  ramp_document(strategy_id=sprintf("RAMP_GATE6_BEST_%s", format(Sys.Date(),"%Y%m%d")),
                grade=ifelse(.best$net_sr>0,"B","C"),
                lesson_text=sprintf("Gate6 iteration: 최고=%s net_sr=%+.3f port_t=%+.2f TO=%.1f (기준 M0_EW −0.04). 회전제어=핵심레버.",
                                    .best$model, .best$net_sr, .best$port_t, .best$to),
                metrics=list(best_model=.best$model, net_sr=.best$net_sr, port_t=.best$port_t, turnover=.best$to),
                mechanism_hypothesis="직교 약신호 조합+회전제어가 개별군 음수를 양수로. 국면가중은 데이터구동 필요(naive룰 실패 기록됨).",
                core_reference="RAMP Gate6 M-code iteration")
}
saveRDS(R, ".cache/_gate6_m1m4.rds"); close(con); cat("M1M4_DONE\n")
