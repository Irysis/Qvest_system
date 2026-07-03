## run_h4_diagnostic.R — 플랜 Phase 2 (H4 진단, front-load) + Phase 3 viability keystone
## 사전등록 임계(데이터 접촉 前 고정): off-diag>0.05 / max_eig>λ+ / cor(ridge α20,α2000)<0.95
## keystone: 팩터 상관행렬 RMT 스펙트럼 — λ+ 초과 고유값 = 팩터의팩터 공통구조 실재(H5/CAE viability)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_h4_diag.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("======== H4 진단 + Phase3 keystone (RMT 팩터-of-팩터 구조) ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
months<-sort(unique(sc$date)); nf<-uniqueN(sc$factor_id)
w("\n=== [keystone] 팩터 상관행렬 고유스펙트럼 vs RMT λ+ ===")
samp<-months[seq(60,length(months),by=6)]
eigres<-data.table()
for(t in samp){ M<-dcast(sc[date==t],tic~factor_id,value.var="nz")
  X<-as.matrix(M[,-1]); X<-X[,colSums(is.finite(X))>=nrow(X)*0.8,drop=FALSE]; X<-X[complete.cases(X),,drop=FALSE]
  if(nrow(X)<50||ncol(X)<50) next
  Ns<-nrow(X); Nf<-ncol(X); C<-suppressWarnings(cor(X)); C[!is.finite(C)]<-0
  ev<-sort(eigen(C,only.values=TRUE)$values,decreasing=TRUE); lam_plus<-(1+sqrt(Nf/Ns))^2
  eigres<-rbind(eigres,data.table(date=t,Ns=Ns,Nf=Nf,lam_plus=lam_plus,ev1=ev[1],ev2=ev[2],ev3=ev[3],
    nsig=sum(ev>lam_plus), offdiag=mean(abs(C[upper.tri(C)]),na.rm=TRUE), var_top3=sum(ev[1:3])/sum(ev))) }
w(sprintf("  대표월 %d개 평균: λ+=%.2f | ev1=%.2f ev2=%.2f ev3=%.2f | λ+초과 고유값수=%.1f | off-diag 평균|cor|=%.3f | top3 분산점유=%.1f%%",
  nrow(eigres),mean(eigres$lam_plus),mean(eigres$ev1),mean(eigres$ev2),mean(eigres$ev3),mean(eigres$nsig),mean(eigres$offdiag),100*mean(eigres$var_top3)))
w(sprintf("  판정: 공통구조 %s | 잔차공선성 %s",
  ifelse(mean(eigres$ev1)>mean(eigres$lam_plus),"★실재(ev1>λ+)","부재"),
  ifelse(mean(eigres$offdiag)>0.05,"★확정(>0.05)","미미")))
fwrite(eigres,file.path(OUT,"h4_eigspectrum.csv"))
if(file.exists(file.path(OUT,"proper_ipca_scores.csv"))){ ip<-fread(file.path(OUT,"proper_ipca_scores.csv"))
  cc<-ip[is.finite(ridge_a20)&is.finite(ridge_a2000), .(r=cor(ridge_a20,ridge_a2000,method="spearman")), by=ym][,mean(r,na.rm=TRUE)]
  w(sprintf("\n=== ridge 랭킹불변: 월별 cor(α20,α2000) 평균=%.3f → %s ===", cc, ifelse(cc<0.95,"★off-diag 확정(랭킹 변함, §1.3 해소)","랭킹 거의 불변"))) }
close(con); cat(sprintf("H4DIAG| ev1=%.2f lam+=%.2f nsig=%.1f off=%.3f top3=%.0f%%\n",mean(eigres$ev1),mean(eigres$lam_plus),mean(eigres$nsig),mean(eigres$offdiag),100*mean(eigres$var_top3)))
