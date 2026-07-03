suppressPackageStartupMessages(library(data.table))
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
# gather all summary_*.csv and bookmarginal_*.csv
sfiles<-list.files(OUT,pattern="^summary_.*csv$",full.names=TRUE)
bfiles<-list.files(OUT,pattern="^bookmarginal_.*csv$",full.names=TRUE)
S<-unique(rbindlist(lapply(sfiles,fread),fill=TRUE),by="method")
B<-unique(rbindlist(lapply(bfiles,fread),fill=TRUE),by="method")
M<-merge(S,B[,.(method,cand_IR,active_cor,blend50_IR,dIR_blend50,IRmax_w,dIR_IRmax,t21_blend_opt)],by="method",all.x=TRUE)
# order: baselines first, then families
ord<-c("LinearTilt(baseline)","EW","hrp_legacy","minvar","nco",
 grep("^Schur_g[0-9.]+$",M$method,value=TRUE),grep("_tilt$",grep("Schur",M$method,value=TRUE),value=TRUE),
 "TailDep_HRP","TailDep_HRP_tilt","Network_softmax","Network_prop","Network_prop_tilt",
 "HeavyTail_DCC_RP","HeavyTail_DCC_RP_tilt","Regime_CVaR","Regime_CVaR_tilt","Regime_CDaR","Regime_CDaR_tilt")
M[,ord:=match(method,ord)]; setorder(M,ord); M[,ord:=NULL]
fwrite(M,file.path(OUT,"MASTER_results.csv"))
print(M[,.(method,PORT_t,IR_active,SR,Calmar,MDD,TO_annual,active_cor,dIR_blend50,dIR_IRmax,t21_blend_opt)])
cat("\nrows:",nrow(M),"\n")
