## run_plan_b1.R — Build1: S2(가지치기·생존가중) + S-base 절대지표 재정립 + 레짐 OFF/ON (H2 미리보기)
source("04_Research/factor_rotation/fof_first_slice/plan_lib.R")
con<-file(file.path(OUT,"_plan_b1.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("======== Build1: S2 + S-base 절대지표 ========"); w(sprintf("실행 %s",as.character(Sys.time())))
D<-.load_data(); S2<-build_S2(D)
w(sprintf("\n=== S2 가지치기: 316 → %d (sign-stable) | 생존가중 분포: 롱점유 중앙 %.2f ===", length(S2$kept), median(S2$surv$survival,na.rm=T)))
w(sprintf("  숏의존 팩터(생존<0.4) 수=%d, 롱우위(>0.6) 수=%d", sum(S2$surv$survival<0.4,na.rm=T), sum(S2$surv$survival>0.6,na.rm=T)))
## S-base score: pruned factors, w_f = pmax(IC,0) × survival
FIC<-D$FIC; FIC[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
mkbase<-function(use_surv=TRUE, use_prune=TRUE){
  sc<-D$sc; fk<-if(use_prune) S2$kept else unique(sc$factor_id)
  x<-merge(sc[factor_id %in% fk,.(date,tic,factor_id,nz)], FIC[,.(date=Date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]
  x[, sv:=if(use_surv) S2$surv_w[factor_id] else 1]; x[!is.finite(sv),sv:=0.5]
  x[, wf:=pmax(tw,0)*sv]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
pr<-function(lab,d){ m<-metrics_abs(d); w(sprintf("  [%-22s] absSR=%.2f Sortino=%.2f CAGR=%+.1f%% MDD=%.1f%% Calmar=%.2f CDaR=%.1f%% avg_inv=%.2f",
  lab,m$SR,m$Sortino,m$CAGR,m$MDD,m$Calmar,m$CDaR,m$avg_inv)); m }
w("\n=== S-base 절대지표 (Kelly 사영, 레짐 OFF vs ON) ===")
sbase<-mkbase(TRUE,TRUE)
d_off<-project_portfolio(sbase, D, kelly=TRUE, use_regime=FALSE); m_off<-pr("S-base 레짐OFF(α_select)", d_off)
d_on <-project_portfolio(sbase, D, kelly=TRUE, use_regime=TRUE ); m_on <-pr("S-base 레짐ON(+α_defense)", d_on)
## ablation: 가지치기/생존가중 효과
w("\n=== S2 ablation (레짐OFF, 절대지표) ===")
pr("full316 no-surv", project_portfolio(mkbase(FALSE,FALSE), D, kelly=TRUE, use_regime=FALSE))
pr("pruned no-surv",  project_portfolio(mkbase(FALSE,TRUE ), D, kelly=TRUE, use_regime=FALSE))
pr("pruned+surv",     d_off)
w(sprintf("\n  → 레짐 ON이 MDD/Calmar 개선하면 α_defense 실재(H2). Calmar %.2f→%.2f, MDD %.1f→%.1f", m_off$Calmar,m_on$Calmar,m_off$MDD,m_on$MDD))
saveRDS(list(D=D,S2=S2,FIC=FIC,sbase=sbase,d_off=d_off,d_on=d_on,mkbase=mkbase), file.path(OUT,"_plan_state.rds"))
cat(sprintf("PLANB1| kept=%d select_Calmar=%.2f defense_Calmar=%.2f select_MDD=%.1f defense_MDD=%.1f\n",length(S2$kept),m_off$Calmar,m_on$Calmar,m_off$MDD,m_on$MDD))
close(con); cat("PLAN_B1_DONE\n")
