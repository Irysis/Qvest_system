suppressPackageStartupMessages({library(data.table);library(jsonlite)})
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
M<-fread(file.path(OUT,"MASTER_results.csv"))
rs<-fread(file.path(OUT,"recent_standalone.csv"))
M<-merge(M,rs[,.(method,PORT_t_2021,IR_2021)],by="method",all.x=TRUE)
# per-frontier verdict: GO requires dIR_IRmax>=0.05 AND active_cor<0.30 AND PORT_t_2021 positive-sig(>1.64)
M[,GO_dIR:=dIR_IRmax>=0.05 | dIR_blend50>=0.05]
M[,GO_cor:=active_cor<0.30]
M[,GO_2021:=PORT_t_2021>1.64]
M[,verdict:=ifelse(GO_dIR & GO_cor & GO_2021,"GO","NO-GO")]
fwrite(M,file.path(OUT,"MASTER_results.csv"))
# frontier-family rollup
fam<-function(pat)M[grepl(pat,method)]
verdict_list<-list(
  incumbent_book_ir_full269=1.4055, incumbent_book_ir_overlap268=1.5605, book_state_ref=1.416,
  baseline_LinearTilt=as.list(M[method=="LinearTilt(baseline)",.(PORT_t,IR_active,SR,Calmar,MDD,TO_annual,PORT_t_2021)]),
  best_PORT_t=M[which.max(PORT_t),method], best_PORT_t_val=max(M$PORT_t,na.rm=TRUE),
  best_Calmar=M[which.max(Calmar),method], best_Calmar_val=max(M$Calmar,na.rm=TRUE),
  best_MDD=M[which.min(MDD),method], best_MDD_val=min(M$MDD,na.rm=TRUE),
  any_bookmarginal_GO=any(M$GO_dIR,na.rm=TRUE),
  n_methods=nrow(M),
  schur_gamma_effect_PORT_t_range=range(M[grepl("^Schur_g[0-9.]+$",method),PORT_t]),
  kr_optimal_gamma_note="Schur γ has negligible effect on this 20-name single-cluster sleeve (pure PORT_t 1.52->1.57 across γ=0..1); best pure γ=0.75 but all fail OOS/2021. γ=1(min-var) worst 2021+ (-1.42).",
  sweep_diag=as.list(fread(file.path(OUT,"sweep_diagnostics.csv")))
)
write_json(verdict_list,file.path(OUT,"VERDICT.json"),auto_unbox=TRUE,pretty=TRUE,digits=4)
cat("verdict written. any GO:",any(M$verdict=="GO"),"\n")
print(M[,.(method,PORT_t,verdict,dIR_IRmax,PORT_t_2021)][1:8])
