## rf3 — 팩터별 재현 패리티: 프로브의 H_f 재구성이 실제 지수 보유와 같은가 (합산 상쇄 배제)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
OUT <- file.path(QM,"stage_artifacts/probe_a5_20260822/adv_refute2")
PRB <- file.path(QM,"stage_artifacts/probe_a5_20260822")
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC)
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
cat(sprintf("[순서 대조] parquet 팩터열 순서 == names(FAC) 순서 ? %s\n", identical(fac, facn)))
R[,ym:=format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]; setorder(mon,medate)

RAWD <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)]; RAWD<-RAWD[Date>=as.Date("2011-01-01") & Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date)); rym<-format(alld,"%Y-%m"); ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME <- ME_all[format(ME_all,"%Y-%m")>="2011-07" & format(ME_all,"%Y-%m")<="2026-07"]
RAWME <- RAWD[Date %in% ME]; rm(RAWD); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME)
RET<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
DEC <- data.table(d0=ME[-length(ME)]); DEC[,fwd_ym:=format(ME[-1],"%Y-%m")]
DEC <- DEC[fwd_ym>="2011-08" & fwd_ym<="2026-07"]
ZP <- readRDS(file.path(PRB,"_zpanel_long.rds"))

rows <- list()
for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
  rr <- RET[Date==d0]; if(!nrow(rr)) next
  capv <- setNames(z$uni$cap, z$uni$Ticker); rv <- setNames(rr$Ret_1m, rr$Ticker)
  # Market 재현 = 유니버스 전체 cap-w
  tkM <- intersect(names(capv), names(rv))
  mktr <- sum(capv[tkM]*rv[tkM])/sum(capv[tkM])
  for(nm in facn){ sub<-z$f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]
    if(nrow(sub)<15) next
    thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); H<-sub[Z_Score_Aligned>=thr,Ticker]
    H<-intersect(H, names(rv)); if(length(H)<5) next
    rows[[length(rows)+1L]] <- data.table(fwd_ym=DEC$fwd_ym[i], f=nm, nH=length(H),
      recon=sum(capv[H]*rv[H])/sum(capv[H]), recon_mkt=mktr) } }
P <- rbindlist(rows)
LG <- melt(mon[, c("ym", facn, "Market"), with=FALSE], id.vars="ym",
           variable.name="f", value.name="idx")[, f:=as.character(f)]
P2 <- merge(P, LG[f!="Market"], by.x=c("fwd_ym","f"), by.y=c("ym","f"))
P2 <- merge(P2, LG[f=="Market", .(ym, idx_mkt=idx)], by.x="fwd_ym", by.y="ym")
res <- P2[, .(n=.N, nH=mean(nH), cor=cor(recon, idx), rmse=sqrt(mean((recon-idx)^2)),
              ann_diff=100*mean(recon-idx)*12), by=f]
setorder(res, cor)
cat("\n===== 팩터별 재현 대조 (프로브 H_f 재구성 월간 cap-w 수익 vs 파켓 지수 월간 수익) =====\n")
print(res, digits=4)
cat(sprintf("\nMarket 재현: cor=%.4f | ann차 %+.2f%%p | 재현 %+.2f%%/yr vs 지수 %+.2f%%/yr\n",
  cor(unique(P2[,.(fwd_ym,recon_mkt,idx_mkt)])$recon_mkt, unique(P2[,.(fwd_ym,recon_mkt,idx_mkt)])$idx_mkt),
  100*mean(unique(P2[,.(fwd_ym,recon_mkt,idx_mkt)])[,recon_mkt-idx_mkt])*12,
  100*mean(unique(P2[,.(fwd_ym,recon_mkt,idx_mkt)])$recon_mkt)*12,
  100*mean(unique(P2[,.(fwd_ym,recon_mkt,idx_mkt)])$idx_mkt)*12))
fwrite(res, file.path(OUT,"v10_perfactor_parity.csv"))
cat("\nRF3_DONE\n")
