setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p0 <- readRDS("stage_artifacts/FQ182/p0.rds"); D <- as.data.frame(p0$D); D$Date <- as.Date(D$Date)
R  <- as.data.frame(p0$R)
mom_skew <- function(x){x<-x[is.finite(x)];m<-mean(x);s<-sqrt(mean((x-m)^2));mean(((x-m)/s)^3)}
mom_kurt <- function(x){x<-x[is.finite(x)];m<-mean(x);s<-sqrt(mean((x-m)^2));mean(((x-m)/s)^4)-3}
p_up3<-function(x,s)mean(x> 3*s); p_dn3<-function(x,s)mean(x< -3*s)

cat("[goal] which target variable reproduces p0$R 'obs'?  candidates: BM_Ret (same-day), fwd1, fwd20\n\n")
for(v in c("BM_Ret","fwd1","fwd20")){
  cat("---- target =", v, "----\n")
  dv <- D[is.finite(D[[v]]),]; s_all <- sd(dv[[v]])
  for(th in c(-0.10,-0.20,-0.30)){
    on <- dv$dd252 <= th; a <- dv[[v]][on]; b <- dv[[v]][!on]
    cat(sprintf("  thr%3.0f%%  mean %+0.6f  sd %+0.6f  skew %+0.4f  kurt %+0.4f  p_up3 %+0.5f  p_dn3 %+0.5f  tail_asym %+0.5f\n",
      th*100, mean(a)-mean(b), sd(a)-sd(b), mom_skew(a)-mom_skew(b), mom_kurt(a)-mom_kurt(b),
      p_up3(a,s_all)-p_up3(b,s_all), p_dn3(a,s_all)-p_dn3(b,s_all),
      (p_up3(a,s_all)-p_dn3(a,s_all))-(p_up3(b,s_all)-p_dn3(b,s_all))))
  }
}
cat("\n---- p0$R 'obs' for reference ----\n")
print(R[,c("thr","stat","obs","ratio")], row.names=FALSE)
