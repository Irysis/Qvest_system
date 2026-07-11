## _r6_ppure_paired.R — 중간 P-pure/controls paired 조기 확인 (Boruta 완료 전, 읽기 전용)
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
x <- readRDS(".cache/_ramp_r6_ppure_20260711.rds")
RES <- x$RES; PR <- x$PR
nwt <- function(v){ v<-v[is.finite(v)]; if(length(v)<12) return(NA)
  m<-lm(v~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
cat("=== gates (controls + P-pure) ===\n")
TAB <- rbindlist(RES, fill=TRUE)
print(TAB[, .(model, pt_capwt=round(port_t_capwt,2), pt_EWuni=round(port_t_EWuni,2),
              oos=round(oos_retention,2), calmar=round(calmar,2), dsr=round(dsr,2),
              post17=round(post2017_bm_sr,2), TO=round(turnover,1), n=n_months)])
pair1 <- function(la, lb, kind){ if(is.null(PR[[la]])||is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date,a=act_bm)], PR[[lb]][,.(date,b=act_bm)], by="date")
  d <- m$a - m$b; data.table(model=la, base=lb, kind=kind, dmean_ann=round(mean(d)*12,4), paired_t=round(nwt(d),2), n=nrow(m)) }
P <- list()
for(W in c(36,60)) for(k in c(10,20)){ P[[length(P)+1]]<-pair1(sprintf("Ppure_W%d_K%d",W,k), sprintf("base_all11_W%d",W), "trait_vs_base11")
  P[[length(P)+1]]<-pair1(sprintf("Ppure_W%d_K%d",W,k), sprintf("ctrl_all102_W%d",W), "sel_vs_all102") }
PP <- rbindlist(Filter(Negate(is.null),P), fill=TRUE)
cat("\n=== paired NW-t (P-pure) ===\n"); print(PP)
cat("\nmax paired trait_vs_base11:", max(PP[kind=="trait_vs_base11",paired_t],na.rm=TRUE), "\n")
cat("max paired sel_vs_all102:", max(PP[kind=="sel_vs_all102",paired_t],na.rm=TRUE), "\n")
cat("PPURE_PAIRED_DONE\n")
