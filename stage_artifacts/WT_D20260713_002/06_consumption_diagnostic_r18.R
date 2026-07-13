#==============================================================================
# WT-D20260713_002 R18 — Step 06: POST-VERDICT CONSUMPTION DIAGNOSTIC (exclusion mode)
#   게이트 판정 불변·재측정 없음. 기존 alpha_scores(worst-decile) + P-pure holdings 소비.
#   binding rate (cap-tier) + exclusion A/B (F-B, F-A∪F-B) + random control + 4 prereg criteria.
#   신규 백테 엔진 없음 — d3/R6 데이터 파이프(build_monthly_forward_returns) + canonical 비용 컨벤션 재사용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
OUT <- "stage_artifacts/WT_D20260713_002"
ym_of <- function(d) { d<-as.Date(d); as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m")) }
COST_BPS <- 15

## ── returns/size/memb from rawdata (d3 pipeline) ─────────────────────────────
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need)))
raw[, Date := as.Date(Date)]
sig_dates <- sort(unique(raw[, Date]))
# monthly grid = month-end trading days
raw[, ym := ym_of(Date)]
me_dates <- raw[, .(Date=max(Date)), by=ym]$Date
rawm <- raw[Date %in% me_dates]
fwd <- build_monthly_forward_returns(rawm, sort(unique(rawm$Date)))
RET  <- as.data.table(fwd$returns_dt)[,.(ym=ym_of(Date), Ticker, Ret_1m)][!is.na(Ret_1m)]
SIZE <- rawm[, .(ym=ym_of(Date), Ticker, Size)][!is.na(Size)]
setorder(SIZE, ym, -Size); SIZE[, cap_rank := seq_len(.N), by=ym]
SIZE[, tier := fifelse(cap_rank<=10L,"MEGA", fifelse(cap_rank<=30L,"MID","OTHER"))]

## ── broad F-A / F-B monthly raw (same signal logic as 01, NO member restriction) ──
FUND <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
FUND[, fy := as.integer(substr(Period,1,4))]; FUND[, pm := as.integer(substr(Period,5,6))]
ann <- FUND[pm==12L & is.finite(Value)]
ann_wide <- function(items){
  s <- ann[Item %in% items, .(Value=Value[.N], Factor_Date=max(Factor_Date)), by=.(Ticker,fy,Item)]
  w <- dcast(s, Ticker+fy ~ Item, value.var="Value")
  merge(w, s[, .(Factor_Date=max(Factor_Date)), by=.(Ticker,fy)], by=c("Ticker","fy"))
}
winsor <- function(v,p=0.01){ q<-quantile(v,c(p,1-p),na.rm=TRUE,names=FALSE); pmin(pmax(v,q[1]),q[2]) }
ym_add <- function(ym,k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
dt2ym  <- function(d) ym_of(d)
expand_hold_raw <- function(sig,H){   # broad: keep raw, most-recent per (Ticker,decision_ym)
  sig<-sig[is.finite(raw)]; sig[, us:=ym_add(rcept_ym,1L)]
  rows<-sig[, { dm<-vapply(0:(H-1L),function(k) ym_add(us,k),integer(1)); .(ym=dm, raw=raw, rcept_ym=rcept_ym) }, by=.(Ticker,seq_len(nrow(sig)))]
  rows[, seq_len:=NULL]; setorder(rows,Ticker,ym,-rcept_ym); rows[, .SD[1L], by=.(Ticker,ym)][, .(Ticker,ym,raw)]
}
# F-A modified Jones residual (broad)
itA <- c("NetIncome","OperatingCF","TotalAssets","Revenue","AccountsRecv","TangibleAssets")
WA <- ann_wide(itA); setorder(WA,Ticker,fy)
WA[, `:=`(A_lag=shift(TotalAssets),Rev_lag=shift(Revenue),AR_lag=shift(AccountsRecv),fy_lag=shift(fy)), by=Ticker]
WA <- WA[is.finite(A_lag)&A_lag>0&(fy-fy_lag==1L)]
WA[, ta_sc:=(NetIncome-OperatingCF)/A_lag][, inv_ta:=1/A_lag]
WA[, drev_adj:=((Revenue-Rev_lag)-(AccountsRecv-AR_lag))/A_lag][, ppe_sc:=TangibleAssets/A_lag]
WA <- WA[is.finite(ta_sc)&is.finite(drev_adj)&is.finite(ppe_sc)]
faR <- WA[, { y<-winsor(ta_sc);x1<-inv_ta;x2<-winsor(drev_adj);x3<-winsor(ppe_sc)
  ok<-is.finite(y)&is.finite(x1)&is.finite(x2)&is.finite(x3)
  if(sum(ok)>=30L){ fit<-tryCatch(lm.fit(cbind(x1[ok],x2[ok],x3[ok]),y[ok]),error=function(e)NULL)
    if(!is.null(fit)){res<-rep(NA_real_,.N);res[ok]<-fit$residuals;.(Ticker,Factor_Date,disc_acc=res)}
    else .(Ticker=character(0),Factor_Date=as.Date(character(0)),disc_acc=numeric(0)) }
  else .(Ticker=character(0),Factor_Date=as.Date(character(0)),disc_acc=numeric(0)) }, by=fy]
faR<-faR[is.finite(disc_acc)]
FA_raw <- expand_hold_raw(faR[,.(Ticker,rcept_ym=dt2ym(Factor_Date),raw=disc_acc)],12L)  # higher=worse
# F-B Benford FSD (broad)
RAW_MON <- c("TotalAssets","TotalLiab","TotalEquity","CurrentAssets","NonCurrentAssets","CurrentLiab","NonCurrentLiab","CashAndEquiv","AccountsRecv","Inventory","TangibleAssets","IntangibleAssets","ShortTermBorr","LongTermBorr","AccountsPay","LongTermPay","LongTermRecv","RetainedEarnings","CapitalStock","TotalDebt","NetDebt","WorkingCapital","Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","NetIncome","TaxExpense","InterestExp","InterestIncome","DepAmort","EBITDA","EBIT","NOPAT","RandD","Dividends","OperatingCF","InvestCF","FinanceCF","FCF1","FCF2")
bexp<-log10(1+1/(1:9)); bf<-ann[Item %in% RAW_MON][abs(Value)>0&is.finite(Value)]
bf[, x:=abs(Value)][, fd:=as.integer(floor(x/10^floor(log10(x))))]; bf<-bf[fd>=1L&fd<=9L]
fsd<-bf[, { n<-.N; if(n>=15L){ tab<-tabulate(fd,9L)/n; .(Factor_Date=max(Factor_Date),fsd=mean(abs(tab-bexp))) } else .(Factor_Date=as.Date(NA),fsd=NA_real_) }, by=.(Ticker,fy)]
fsd<-fsd[is.finite(fsd)]
FB_raw <- expand_hold_raw(fsd[,.(Ticker,rcept_ym=dt2ym(Factor_Date),raw=fsd)],12L)  # higher=worse
# worst-decile per ym (raw >= p90)
wd <- function(R){ R[, p90:=quantile(raw,0.90,na.rm=TRUE), by=ym]; R[raw>=p90, .(ym,Ticker)] }
WD_FA<-wd(FA_raw); WD_FB<-wd(FB_raw)
WD_UNION<-unique(rbindlist(list(WD_FA,WD_FB)))
cat("[06] worst-decile stock-months: FA",nrow(WD_FA)," FB",nrow(WD_FB)," union",nrow(WD_UNION),"\n")

## ── P-pure holdings + book snapshots ─────────────────────────────────────────
PPH <- as.data.table(read_parquet("stage_artifacts/d3_dossier/holdings_monthly_ppure.parquet"))
PPH[, ym:=ym_of(Date)]; PPH<-PPH[ym>=200906 & ym<=202506]
# binding: held ∩ worst-decile, cap-tier decomp
bind_tab <- function(WD,lab){
  H<-merge(PPH[,.(ym,Ticker)], SIZE[,.(ym,Ticker,tier)], by=c("ym","Ticker"), all.x=TRUE)
  H[is.na(tier),tier:="UNRANKED"]
  H[, bound:=Ticker %in% WD[, paste(ym,Ticker)][match(paste(H$ym,H$Ticker), WD[,paste(ym,Ticker)])]]
  # simpler robust flag:
  key<-WD[, paste(ym,Ticker)]; H[, bound:=paste(ym,Ticker) %in% key]
  tot<-nrow(H); byt<-H[, .(held=.N, bound=sum(bound), rate=mean(bound)), by=tier][order(-held)]
  list(label=lab, total_held_sm=tot, bound_sm=sum(H$bound), overall_rate=mean(H$bound), by_tier=byt)
}
BIND_FB<-bind_tab(WD_FB,"FB"); BIND_UNION<-bind_tab(WD_UNION,"UNION"); BIND_FA<-bind_tab(WD_FA,"FA")

# book snapshots (large-cap) — stock-level production_weights
bkdir<-"04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights"
bk_files<-list.files(bkdir, pattern="weights.*0p20.*\\.csv$", full.names=TRUE)
book_bind<-list()
for(f in bk_files){
  b<-tryCatch(fread(f),error=function(e)NULL); if(is.null(b)||!("Ticker"%in%names(b))) next
  b<-b[Ticker!="CASH" & !grepl("CASH",Ticker)]
  dstr<-regmatches(basename(f),regexpr("[0-9]{8}",basename(f))); if(length(dstr)==0) next
  y<-as.integer(substr(dstr,1,4))*100L+as.integer(substr(dstr,5,6))
  held<-b$Ticker; nfb<-sum(paste(y,held) %in% WD_FB[,paste(ym,Ticker)])
  nun<-sum(paste(y,held) %in% WD_UNION[,paste(ym,Ticker)])
  tiers<-SIZE[ym==y & Ticker %in% held, tier]
  book_bind[[basename(f)]]<-list(ym=y,n_held=length(held),bound_FB=nfb,bound_UNION=nun,
    mega=sum(tiers=="MEGA"),mid=sum(tiers=="MID"),other=sum(tiers=="OTHER"))
}

## ── exclusion A/B on P-pure holdings (drop+renormalize) ──────────────────────
# baseline & excluded net returns; canon cost on |Δw|
port_series <- function(W){   # W: ym,Ticker,w
  WR<-merge(W, RET, by=c("ym","Ticker"), all.x=TRUE); WR[is.na(Ret_1m),Ret_1m:=0]
  g<-WR[, .(gross=sum(w*Ret_1m)), by=ym]; setorder(g,ym)
  yms<-sort(unique(W$ym)); traded<-numeric(length(yms)); names(traded)<-as.character(yms); prev<-data.table(Ticker=character(0),w=numeric(0))
  for(i in seq_along(yms)){ cur<-W[ym==yms[i],.(Ticker,w)]; m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
    m[is.na(w_c),w_c:=0];m[is.na(w_p),w_p:=0]; traded[i]<-sum(abs(m$w_c-m$w_p)); prev<-cur }
  g[, traded:=traded[as.character(ym)]][, net:=gross - traded*COST_BPS/1e4]; g
}
excl_W <- function(WD){   # drop worst-decile from PPH, renormalize EW
  H<-merge(PPH[,.(ym,Ticker)], WD[, .(ym,Ticker,drop=1L)], by=c("ym","Ticker"), all.x=TRUE)
  H<-H[is.na(drop)]; H[, w:=1/.N, by=ym]; H[, .(ym,Ticker,w)]
}
rand_W <- function(k_by_ym, seed){   # drop same #(k_t) at random from PPH
  set.seed(seed); H<-copy(PPH[,.(ym,Ticker)])
  keep<-H[, { k<-k_by_ym[[as.character(ym[1])]]; k<-ifelse(is.null(k)||is.na(k),0L,k)
    idx<-if(k>0 && k<.N) sample(.N,.N-k) else seq_len(.N); .(Ticker=Ticker[idx]) }, by=ym]
  keep[, w:=1/.N, by=ym]; keep[, .(ym,Ticker,w)]
}
base_W <- PPH[, .(ym,Ticker,w=1/.N), by=ym][, .(ym,Ticker,w)]
tail_metrics <- function(g){ r<-g$net; nav<-cumprod(1+r); mdd<- -min(nav/cummax(nav)-1)
  dd<-sqrt(mean(pmin(r,0)^2))*sqrt(12); w5<-sum(sort(r)[1:min(5,length(r))])
  list(mdd=mdd, worst_month=min(r), downside_dev=dd, worst5=w5, sr=mean(r)/sd(r)*sqrt(12), n=length(r), g=g) }
paired_nwt <- function(ge,gb){ m<-merge(ge[,.(ym,ne=net)],gb[,.(ym,nb=net)],by="ym"); d<-m$ne-m$nb
  fit<-lm(d~1); list(t=as.numeric(coeftest(fit,vcov=NeweyWest(fit,lag=3,prewhite=FALSE))[1,3]),
    mean=mean(d), n=length(d)) }

base_g<-port_series(base_W); base_t<-tail_metrics(base_g)
# k per ym for random control (from union exclusion — the primary filter)
run_filter <- function(WD, name){
  eW<-excl_W(WD); eg<-port_series(eW); et<-tail_metrics(eg)
  # k_t excluded each month
  kc<-merge(PPH[,.N,by=ym], eW[,.N,by=ym], by="ym", suffixes=c("_all","_keep"))
  k_by<-setNames(as.list(kc$N_all-kc$N_keep), as.character(kc$ym))
  rseeds<-c(101L,202L,303L); rmet<-lapply(rseeds<-c(101L,202L,303L), function(s){ tail_metrics(port_series(rand_W(k_by,s))) })
  rmdd<-sapply(rmet,function(x)x$mdd); rdd<-sapply(rmet,function(x)x$downside_dev); rw5<-sapply(rmet,function(x)x$worst5)
  pt<-paired_nwt(eg, base_g)
  # C4: remove baseline worst-2 months, re-tail direction
  worst2<-base_g[order(net)][1:2, ym]
  bg2<-base_g[!ym %in% worst2]; eg2<-eg[!ym %in% worst2]
  b2<-tail_metrics(bg2); e2<-tail_metrics(eg2)
  list(name=name, n_excl_sm=nrow(PPH)-nrow(eW), mean_k=mean(unlist(k_by)),
    excl=et, paired=pt,
    d_mdd=base_t$mdd-et$mdd, d_dd=base_t$downside_dev-et$downside_dev, d_w5=et$worst5-base_t$worst5,
    rand_mdd_mean=mean(rmdd), rand_dd_mean=mean(rdd), rand_dd_best=max(base_t$downside_dev-rdd), # best random Δdd improvement
    rand_d_mdd_mean=mean(base_t$mdd-rmdd), rand_d_dd_mean=mean(base_t$downside_dev-rdd),
    rand_d_dd_seeds=base_t$downside_dev-rdd,
    c4_d_mdd_ex2=b2$mdd-e2$mdd, c4_d_dd_ex2=b2$downside_dev-e2$downside_dev)
}
AB_FB <- run_filter(WD_FB, "FB_only")
AB_UNION <- run_filter(WD_UNION, "FA_union_FB")

## ── 4 pre-registered promotion criteria ─────────────────────────────────────
eval_crit <- function(AB, BIND){
  other_rate <- BIND$by_tier[tier=="OTHER", rate]; mid_rate<-BIND$by_tier[tier=="MID", rate]
  mega_rate  <- tryCatch(BIND$by_tier[tier=="MEGA", rate], error=function(e)NA)
  C1 <- (length(other_rate)&&!is.na(other_rate)&&other_rate>=0.05) || (length(mid_rate)&&!is.na(mid_rate)&&mid_rate>=0.05)
  # C2: forensic ΔMDD > random mean ΔMDD AND forensic Δdd > best of 3 random seeds
  C2 <- (AB$d_mdd > AB$rand_d_mdd_mean) && (AB$d_dd > max(AB$rand_d_dd_seeds))
  C3 <- AB$paired$t > -1.64
  C4 <- (AB$c4_d_mdd_ex2 > 0) || (AB$c4_d_dd_ex2 > 0)
  list(C1_binding_real=C1, C2_tail_beats_random=C2, C3_alpha_intact=C3, C4_not_concentrated=C4,
       pass_count=sum(C1,C2,C3,C4))
}
CR_FB<-eval_crit(AB_FB,BIND_FB); CR_UNION<-eval_crit(AB_UNION,BIND_UNION)

res <- list(binding=list(FB=BIND_FB, UNION=BIND_UNION, FA=BIND_FA, book=book_bind),
            baseline_tail=base_t[c("mdd","worst_month","downside_dev","worst5","sr","n")],
            ab=list(FB=AB_FB[setdiff(names(AB_FB),"excl")], UNION=AB_UNION[setdiff(names(AB_UNION),"excl")]),
            ab_excl_tail=list(FB=AB_FB$excl[c("mdd","worst_month","downside_dev","worst5","sr")],
                              UNION=AB_UNION$excl[c("mdd","worst_month","downside_dev","worst5","sr")]),
            criteria=list(FB=CR_FB, UNION=CR_UNION))
saveRDS(res, file.path(OUT,"consumption_diagnostic.rds"))

cat("\n===== BINDING RATE (P-pure ⓑ, cap-tier) =====\n")
cat("FB filter:\n"); print(BIND_FB$by_tier); cat(sprintf("  overall bound %d/%d = %.1f%%\n",BIND_FB$bound_sm,BIND_FB$total_held_sm,100*BIND_FB$overall_rate))
cat("UNION filter:\n"); print(BIND_UNION$by_tier); cat(sprintf("  overall %.1f%%\n",100*BIND_UNION$overall_rate))
cat("\n===== BOOK ⓐ snapshots (large-cap) =====\n"); print(rbindlist(lapply(book_bind,as.data.table),fill=TRUE))
cat("\n===== EXCLUSION A/B (tail; base MDD",round(base_t$mdd,3)," dd",round(base_t$downside_dev,3),") =====\n")
for(nm in c("FB","UNION")){ A<-res$ab[[nm]]
  cat(sprintf("[%s] mean_k=%.2f | ΔMDD=%.4f (rand %.4f) | Δdd=%.4f (rand best %.4f, seeds %s) | paired NW-t=%.2f | C4 ΔMDD_ex2=%.4f\n",
    nm, A$mean_k, A$d_mdd, A$rand_d_mdd_mean, A$d_dd, max(A$rand_d_dd_seeds),
    paste(round(A$rand_d_dd_seeds,4),collapse=","), A$paired$t, A$c4_d_mdd_ex2)) }
cat("\n===== 4 PREREG CRITERIA =====\n")
cat("FB   :",unlist(CR_FB),"\n"); cat("UNION:",unlist(CR_UNION),"\n")
cat("[06] DONE\n")
