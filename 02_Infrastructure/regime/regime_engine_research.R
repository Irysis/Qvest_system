#!/usr/bin/env Rscript
# =============================================================================
# regime_engine_research.R — Factor Rotation Mode Track1 (국면 정의 + 판별력 검증).
# 후보 축(경제논리)이 모듈 성과를 *실제로 가르는가*를 검증: 축 버킷별 모듈 IR →
#   순위역전 Kendall τ(≤0.5 채택) + 버킷간 IR spread. 판별축만 채택(과적합 회피).
# PIT: 축 z는 t-1, 버킷은 expanding percentile. 실측.
# 산출: 판별력 보고 + best 축의 월별 regime 라벨 → run_wf_ensemble가 사용.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
.qvest_root <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[regime_engine_research] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
PROJ <- .qvest_root(); setwd(PROJ)
`%||%`<-function(a,b) if(is.null(a)||length(a)==0||all(is.na(a)))b else a
ANN <- 252; sr <- function(r){r<-r[is.finite(r)];if(length(r)<20||sd(r)==0)NA else mean(r)/sd(r)*sqrt(ANN)}

# 1. 후보 축 (경제논리, t-1 lagged) ------------------------------------------
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
MS <- as.data.table(read_parquet(file.path(PROJ,".cache/msm_daily_latest.parquet")))[, Date:=as.Date(Date)]
AX <- merge(RD[, .(Date, MRS, VIX_z=VIX_z_smooth, TS_z=TS_z_smooth, HY_z=HY_z_smooth)],
            UN[, .(Date, VEA=VEA_Score, KTRI=KTRI_Score)], by="Date", all=TRUE)
AX <- merge(AX, MS[, .(Date, CrisisP=Crisis_Prob)], by="Date", all.x=TRUE)
setorder(AX, Date)
axes <- c("MRS","VEA","KTRI","VIX_z","TS_z","HY_z","CrisisP")
for(a in axes) AX[, (paste0(a,"_lag")) := shift(get(a),1L)]   # t-1

# 2. 모듈 일간 수익 (module_performance.json) ---------------------------------
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules)
rets <- lapply(mod_ids, function(s){ p<-file.path(PROJ,MP$modules[[s]]$sim_result_path); x<-readRDS(p)$DAILY_NAV_DT; data.table(Date=as.Date(x$Date), r=x$Strategy_Ret) })
names(rets)<-mod_ids
RM <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE), lapply(mod_ids,function(s){x<-copy(rets[[s]]);setnames(x,"r",s);x}))
D <- merge(RM, AX[, c("Date",paste0(axes,"_lag")), with=FALSE], by="Date"); setorder(D, Date)

# 3. 축별 판별력: expanding-percentile 3버킷 → 모듈 IR → Kendall τ ------------
bucket_exp <- function(x){ # PIT expanding tercile: low/mid/high (직전까지 분포)
  n<-length(x); b<-rep(NA_character_,n)
  for(i in seq_len(n)){ if(i<60||is.na(x[i])) next; q<-quantile(x[1:(i-1)],c(.33,.67),na.rm=TRUE)
    if(any(is.na(q))||q[1]>=q[2]) next
    b[i]<-if(x[i]<=q[1])"low" else if(x[i]<=q[2])"mid" else "high" }
  b }
report <- list()
for(a in axes){
  col<-paste0(a,"_lag"); D[, bk := bucket_exp(get(col))]
  irs <- sapply(c("low","mid","high"), function(bb) sapply(mod_ids, function(s){ sr(D[bk==bb][[s]]) }))
  # 순위역전: low vs high 버킷 모듈 IR 순위 Kendall τ
  ok <- complete.cases(irs[,"low"], irs[,"high"])
  tau <- if(sum(ok)>=4) suppressWarnings(cor(rank(irs[ok,"low"]), rank(irs[ok,"high"]), method="kendall")) else NA
  spread <- mean(abs(irs[,"high"]-irs[,"low"]), na.rm=TRUE)
  n_sig <- sum(abs(irs[,"high"]-irs[,"low"]) > 0.3, na.rm=TRUE)  # 간이 유의(IR차>0.3)
  report[[a]] <- list(axis=a, kendall_tau_low_high=round(tau,3), mean_IR_spread=round(spread,3),
                      n_modules_IRspread_gt_0.3=n_sig, discriminative=(!is.na(tau)&&tau<=0.5&&n_sig>=2))
}
RES <- rbindlist(lapply(report, as.data.table), fill=TRUE)[order(kendall_tau_low_high)]
write_json(list(schema_version="v1.0", generated="2026-06-02",
  method="expanding-tercile bucket per axis → per-module IR → Kendall τ(low vs high rank) + IR spread. 채택=τ≤0.5 & 유의모듈≥2.",
  n_modules=length(mod_ids), axes=report),
  file.path(PROJ,"04_Research/factor_rotation/output/regime_discrimination.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n==== 레짐 축 판별력 (모듈 순위를 가르는가) ====\n")
print(RES[, .(axis, kendall_tau=kendall_tau_low_high, IR_spread=mean_IR_spread, n_sig=n_modules_IRspread_gt_0.3, 판별=discriminative)])
best <- RES[discriminative==TRUE][order(kendall_tau_low_high)][1]
cat(sprintf("\n★ 최강 판별축: %s (τ=%.2f, spread=%.2f). 채택 축 %d개.\n",
  if(nrow(best)&&!is.na(best$axis)) best$axis else "없음", best$kendall_tau_low_high%||%NA, best$mean_IR_spread%||%NA, RES[discriminative==TRUE,.N]))
`%||%`<-function(a,b) if(is.null(a)||length(a)==0||all(is.na(a)))b else a
