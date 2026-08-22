solveMVO<-function(muv,Sig){ D<-delta*Sig; D<-D+diag(1e-6,NA_); A<-cbind(rep(1,NA_),diag(NA_));b0<-c(1,rep(0,NA_))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL); if(is.null(r))return(w_ew); pmax(r$solution,0)/sum(pmax(r$solution,0)) }
bl_w<-function(Sig,vv,cc){ pri<-delta*as.numeric(Sig%*%w_ew)
  M<-P%*%Sig%*%t(P); Om<-cc*diag(diag(M))
  muBL<-pri + as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv - as.numeric(P%*%pri))))
  solveMVO(muBL,Sig) }
te_ex<-function(w,Sig) sqrt(max(as.numeric(t(w-w_ew)%*%Sig%*%(w-w_ew)),0))
