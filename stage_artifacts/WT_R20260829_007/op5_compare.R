# OP5 — 5방법론 공통창 비교 + 사전선언 게이트 적용
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(quadprog); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1 <- readRDS(file.path(OUT,"op1_objects.rds")); A<-o1$A; BM<-o1$BM; DTS_BT<-o1$DTS_BT
source(file.path(OUT,"op3_sigma_mod.R"))
CVEC <- { cj <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))$confidence_vector
          setNames(as.numeric(unlist(cj)), names(cj)) }
COST_BPS<-0.0015; LAM<-2.0; PSI<-0.3; PHI<-0.00405
source(file.path(OUT,"op4_core.R"))
FLR <- new.env(); FLR$n <- c(); FLR$rat <- c()
DTS_C <- DTS_BT[13:length(DTS_BT)]
# EVT GPD ES99 (Pfaff FRM Ch7 관례 · risk tail_risk.json 과 동일 절차: 손실 상위 10% 초과분 POT/MLE)
gpd_es99 <- function(r){
  L <- -r; u <- quantile(L, 0.90); ex <- L[L>u]-u; n<-length(L); k<-length(ex)
  if(k<10) return(NA_real_)
  nll <- function(p){ xi<-p[1]; b<-exp(p[2]); if(any(1+xi*ex/b<=0)) return(1e10)
    k*log(b)+(1+1/xi)*sum(log(1+xi*ex/b)) }
  op <- tryCatch(optim(c(0.1,log(sd(ex))), nll), error=function(e) NULL); if(is.null(op)) return(NA_real_)
  xi<-op$par[1]; b<-exp(op$par[2])
  q <- u + b/xi*(((n/k)*(1-0.99))^(-xi)-1)
  as.numeric(q + (b + xi*(q-u))/(1-xi))
}
summ <- function(m){ p<-m$perf; act<-p$ret_net-p$bm
  data.table(method=m$method, months=nrow(p),
    to_2way=mean(p$traded)*12, net_ir=mean(act)*12/(sd(act)*sqrt(12)),
    active_ann=mean(act)*12, net_cagr=prod(1+p$ret_net)^(12/nrow(p))-1,
    net_sr=mean(p$ret_net)*12/(sd(p$ret_net)*sqrt(12)),
    hhi=mean(p$hhi), maxw=max(p$maxw), nmed=median(p$n),
    cap_med=median(p$cap_aum,na.rm=TRUE), cap_p10=quantile(p$cap_aum,.10,na.rm=TRUE),
    cap_12m=median(tail(p$cap_aum,12),na.rm=TRUE),
    es99_evt=gpd_es99(p$ret_net), new_nm=mean(p$n_new), cost_ann=mean(p$cost)*12,
    beta=as.numeric(coef(lm(p$ret_net~p$bm))[2])) }
R <- list()
R[["M1"]] <- run_wf(sel_top,        size_ew,   DTS_C, "M1_EW25_base")
for(B in c(40,50,60,75)) R[[paste0("M2_B",B)]] <- run_wf(mk_selbuf(B), size_ew,  DTS_C, paste0("M2_EW25_buffer",B))
R[["M3"]] <- run_wf(sel_top,        size_tilt, DTS_C, "M3_ALPHA_TILT")
R[["M4"]] <- run_wf(sel_top,        size_mvo,  DTS_C, "M4_MVO_TO")
for(B in c(40,50,60,75)) R[[paste0("M5_B",B)]] <- run_wf(mk_selbuf(B), size_mvo, DTS_C, paste0("M5_BUF",B,"_MVO_TO"))
S <- rbindlist(lapply(R, summ)); S[, G5_pass := to_2way <= 11.0]
print(S[, .(method, to=round(to_2way,3), G5=G5_pass, net_ir=round(net_ir,4), act=round(active_ann,4),
            cagr=round(net_cagr,4), sr=round(net_sr,4), cost=round(cost_ann,4), hhi=round(hhi,4),
            maxw=round(maxw,4), cap_med=round(cap_med/1e8,1), cap12=round(cap_12m/1e8,1),
            es99=round(es99_evt,4), beta=round(beta,3), newnm=round(new_nm,2))])
cat("\nD-floor 발동: 평균", round(mean(FLR$n),2), "/25 종 · floored/raw 평균비", round(mean(FLR$rat,na.rm=TRUE),4), "\n")
saveRDS(list(R=R,S=S,DTS_C=DTS_C,FLR=as.list(FLR)), file.path(OUT,"op5_objects.rds"))
