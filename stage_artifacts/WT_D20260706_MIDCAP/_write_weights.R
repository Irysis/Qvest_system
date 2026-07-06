# Write weights.csv (full 268-month schedule, selected method = alpha_prop best net_ir standalone)
# + as_of target_weights snapshot for optimization_package.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; DIR<-file.path(ROOT,"stage_artifacts/WT_D20260706_MIDCAP")
ap<-as.data.table(arrow::read_parquet(file.path(DIR,"alpha_scores.parquet")));ap[,Date:=as.Date(Date)]
setorder(ap,Date,-alpha_hat); top25<-ap[,.SD[seq_len(min(25,.N))],by=Date]
# selected method for schedule = EW top-25 (Implementation-Discipline compliant: turnover 11.41 vs
#   alpha_prop 13.84 which is DISQUALIFIED >11.0/yr per opt-style Cycle-2 rule + DGU-2009 1/N OOS).
#   verdict is HOLD/infeasible on success gates; EW is the disciplined handoff schedule for forge.
W<-top25[,{ w<-rep(1/.N,.N)
  wr<-round(w,6); resid<-1-sum(wr); ii<-which(wr>0 & wr<0.20); j<-ii[which.min(wr[ii])]; wr[j]<-wr[j]+resid
  .(Ticker=Ticker,w=wr)},by=Date]
# schedule density check
sig_dates<-length(unique(ap$Date)); wf_dates<-length(unique(W$Date))
cat("sig_dates:",sig_dates," weights_dates:",wf_dates," ratio:",round(wf_dates/sig_dates,4),"\n")
# per-Date constraint audit
chk<-W[,.(n=.N,sw=sum(w),maxw=max(w),minw=min(w)),by=Date]
cat("max names:",max(chk$n)," Sigma-w range:[",round(min(chk$sw),6),",",round(max(chk$sw),6),"]",
    " max weight:",round(max(chk$maxw),4)," min weight:",round(min(chk$minw),6),"\n")
stopifnot(max(chk$n)<=25, all(abs(chk$sw-1)<1e-6), max(chk$maxw)<=0.20+1e-9, min(chk$minw)>=0)
# write weights.csv (as_of_date column = the sig_date; walk-forward schedule RF-O9)
out<-W[,.(as_of_date=Date,Ticker,weight=w)]
fwrite(out, file.path(DIR,"weights.csv"))
cat("weights.csv rows:",nrow(out)," unique as_of_date:",length(unique(out$as_of_date)),"\n")
# as_of snapshot (2026-04-01) target_weights
asof<-as.Date("2026-04-01"); snap<-W[Date==asof][order(-w)]
tw<-setNames(as.list(snap$w), snap$Ticker)
writeLines(toJSON(tw,auto_unbox=TRUE,digits=6), file.path(DIR,"_target_weights_asof.json"))
cat("as_of target_weights (2026-04-01):",nrow(snap),"names, sum",round(sum(snap$w),6),"\n")
print(head(snap,8))
cat("[done]\n")
