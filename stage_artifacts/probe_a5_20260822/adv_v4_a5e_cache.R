QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
x<-readRDS(".cache/_dfa_a5e_r12.rds")
cat("names:",paste(names(x),collapse=","),"\n")
b<-x$base; e<-x$essence
cat(sprintf("R12 A5E base: pt=%.4f IR=%.4f SR=%.4f MDD=%.4f CAGR=%.4f TO=%.3f n=%d\n",
  b$pt,b$IR,b$SR,b$MDD,b$CAGR,b$TO,b$n))
cat("essence names:",paste(names(e),collapse=","),"\n")
ee<-e$essence
cat(sprintf("grade=%s pt=%.4f oos=%.4f calmar=%.4f SR=%.3f MDD=%.4f dsr=%.4f\n",
  e$grade,ee$portfolio_alpha_t_nw_lag3,ee$oos_retention,ee$calmar,ee$net_sharpe,ee$mdd,ee$dsr))
cat("oos splits:",paste(round(unlist(e$oos_retention_splits),4),collapse=" / "),"\n")
cat("band:",e$oos_band_status,"\n")
