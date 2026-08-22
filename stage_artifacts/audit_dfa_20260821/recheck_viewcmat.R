suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
mainr<-function(key) readRDS(sprintf(".cache/_dfa_v5_%s.rds",key))
nacmp<-function(a,b){ a<-as.matrix(a); b<-as.matrix(b)
  if(!identical(dim(a),dim(b))) return("DIM_MISMATCH")
  na_mis<-sum(is.na(a)!=is.na(b)); both<-!is.na(a)&!is.na(b)
  sprintf("NA패턴 불일치=%d | 유효셀 max|Δ|=%.3g (유효 %d셀)", na_mis,
          ifelse(any(both),max(abs(a[both]-b[both])),0), sum(both)) }
ZA<-mainr("audit_a")
for(cfg in list(c("audit_b1","2010-06-30"),c("audit_b2","2012-03-30"))){
  ZB<-mainr(cfg[1]); me<-ZA$medates; pre<-which(me<=as.Date(cfg[2]))
  cat(sprintf("[%s t*=%s] view_me(pre): %s\n", cfg[1], cfg[2], nacmp(ZA$view_me[pre,],ZB$view_me[pre,])))
  cat(sprintf("[%s t*=%s] cmat(pre)   : %s\n", cfg[1], cfg[2], nacmp(ZA$cmat[pre,,drop=FALSE],ZB$cmat[pre,,drop=FALSE])))
}
cat("RECHECK_DONE\n")
