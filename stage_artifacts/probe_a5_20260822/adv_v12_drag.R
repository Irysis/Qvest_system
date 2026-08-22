QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R"); library(data.table)
S<-fread("stage_artifacts/probe_a5_20260822/adv_intraindex_turnover_full.csv")
FACN<-colnames(S12); AX<-c("Market",FACN)
drag<-setNames(rep(NA_real_,length(AX)),AX)
for(a in AX) drag[a]<-S[idx==a]$drag/100     # 연 비율
cat("결측 지수:",paste(AX[!is.finite(drag)],collapse=","),"\n")
wavg<-function(r){ k<-which(is.finite(r$pr)); W<-r$W[k,]; colMeans(W) }
res<-list()
for(nm in c("C1","A5_p0","A5E_p1","A5E_p2")){
  r<-switch(nm,C1=engine(dec_freq(1,0),bps=15),A5_p0=engine(dec_freq(3,0),bps=15),
            A5E_p1=engine(dec_freq(3,1),bps=15),A5E_p2=engine(dec_freq(3,2),bps=15))
  w<-wavg(r); m<-MET(r)
  port_drag<-sum(w*drag); bm_drag<-drag["Market"]
  net_act<-m$amean; new_act<-net_act-(port_drag-bm_drag)
  res[[length(res)+1]]<-data.table(arm=nm, w_Market=w[1],
    top_high_TO_w=sum(w[AX %in% c("Reversal","SmartMoney","ForeignFlow","Consensus","TailRisk","ResidMom")]),
    port_drag_pct=port_drag*100, bm_drag_pct=bm_drag*100, unpriced_active_drag_pct=(port_drag-bm_drag)*100,
    net_act_now_pct=net_act*100, net_act_adj_pct=new_act*100,
    pt_now=m$pt, pt_scaled=m$pt*new_act/net_act) }
RES<-rbindlist(res); print(RES,digits=4)
cat("\n  ※ pt_scaled = 평균만 축소하고 sd 불변 가정한 1차 근사(보수적: 실제 비용은 결정론적이라 sd 거의 불변)\n")
## 지수별 평균 보유비중 (상위)
w<-wavg(engine(dec_freq(3,0),bps=15)); names(w)<-AX
print(round(sort(w,decreasing=TRUE)[1:10],4))
