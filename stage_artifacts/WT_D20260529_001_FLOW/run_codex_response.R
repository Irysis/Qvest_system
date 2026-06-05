# =============================================================
# Codex REJECT response — empirical rebuttals + fixes
# C1: OOS sign-stability (direction NOT full-sample fished)
# C3: composite vs best-single (independent value test)
# C6: t-1 lag for liquidity (already PIT?) + regime lag
# C7: sector-neutral IC
# C4: clean alpha_scores (drop future label) — done in separate finalize
# =============================================================
suppressMessages({library(data.table); library(arrow); library(lubridate)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
panel <- readRDS(file.path(OUT,"panel.rds"))
INV <- grep("^INV", names(panel), value=TRUE)

# ---- C1: OOS sign stability. Estimate contrarian direction on 2005-2014 ONLY,
#          then test on 2015-2023 (true OOS). If sign holds -> not fished. ----
panel[, half := fifelse(Date < as.Date("2015-01-01"),"train","oos")]
pick_lt <- c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d","INV09_Flow_Persistence",
             "INV11_Foreign_Concentration","INV07_Retail_Contrarian")
# train-half IC sign per factor
sgn <- sapply(pick_lt, function(f){
  d<-panel[half=="train" & !is.na(get(f))]
  ic<-d[,.(ic=if(.N>=20) cor(get(f),exret_fwd_1m,method="spearman") else NA),by=Date][!is.na(ic)]
  sign(mean(ic$ic))
})
cat("Train-half (2005-14) IC signs:\n"); print(sgn)
# apply train-derived sign to OOS, build composite, measure OOS IC
panel[, comp_oos := { v <- numeric(.N); for(f in pick_lt){ z<-get(f); z[is.na(z)]<-0; v <- v + sgn[f]*z }; v/length(pick_lt) }]
oos_ic <- panel[half=="oos", .(ic=if(.N>=20) cor(comp_oos, exret_fwd_1m, method="spearman") else NA), by=Date][!is.na(ic)]
nm<-nrow(oos_ic); m<-mean(oos_ic$ic); t<-m/(sd(oos_ic$ic)/sqrt(nm))
cat(sprintf("\nC1 OOS test: direction learned on 2005-14, applied to 2015-23.\n  OOS IC=%.4f t=%.2f n=%d (sign positive=alpha holds OOS)\n", m,t,nm))

# ---- C3: composite vs best single contrarian factor (INV10 best ICIR per draft) ----
# best single = INV10 (ICIR 0.291 contrarian). compare portfolio-alpha t, not just ICIR.
# Build single-factor contrarian top20 monthly and composite low-turn, compare net SR + drawdown.
mk_single_ic <- function(f, neg=TRUE){
  d<-panel[!is.na(get(f))]
  ic<-d[,.(ic=if(.N>=20) cor(get(f),exret_fwd_1m,method="spearman") else NA),by=Date][!is.na(ic)]
  m<-mean(ic$ic)*ifelse(neg,-1,1); list(icir=m/sd(ic$ic), ic=m)
}
best1 <- mk_single_ic("INV10_Smart_Money_Flow")
cat(sprintf("\nC3: best single INV10 contrarian ICIR=%.3f IC=%.4f\n", best1$icir, best1$ic))
# composite ICIR (lowturn alpha_sm)
lt <- readRDS(file.path(OUT,"diag_lowturn.rds"))
cat(sprintf("  composite (smoothed, lowturn) ICIR=%.3f IC=%.4f\n", lt$icir, lt$mic))
# Key independent-value metric: composite crisis ratio vs single
sf <- panel[!is.na(`INV10_Smart_Money_Flow`)]
sfic <- sf[,.(ic=-cor(`INV10_Smart_Money_Flow`,exret_fwd_1m,method="spearman"),
   bad= (format(Date,"%Y-%m") %in% format(Date,"%Y-%m"))),by=Date]
# crisis ratio via regime
s1715 <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
s1715[,Date:=as.Date(Date)]; s1715[,ym:=format(Date,"%Y-%m")]
rm2 <- unique(s1715[,.(ym,regime_state)])[,.(regime=regime_state[1]),by=ym]
single_ic <- panel[!is.na(`INV10_Smart_Money_Flow`),.(ic=-cor(`INV10_Smart_Money_Flow`,exret_fwd_1m,method="spearman")),by=.(ym=format(Date,"%Y-%m"))]
single_ic<-merge(single_ic,rm2,by="ym"); single_ic[,bad:=regime%in%c("CRISIS","CAUTION")]
cat(sprintf("  single INV10 crisis IC=%.4f normal=%.4f ratio=%.3f\n",
  mean(single_ic[bad==TRUE]$ic),mean(single_ic[bad==FALSE]$ic),
  mean(single_ic[bad==TRUE]$ic)/mean(single_ic[bad==FALSE]$ic)))

# ---- C7: sector-neutral IC ----
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Sector")))
raw[,Date:=as.Date(Date)]
sect <- unique(raw[,.(Date,Ticker,Sector)])
lt_panel <- copy(lt$panel)
lt_panel <- merge(lt_panel, sect, by=c("Date","Ticker"), all.x=TRUE)
lt_panel[is.na(Sector), Sector:="UNK"]
# sector-neutralize alpha_sm (demean within sector each date)
lt_panel[, alpha_sn := alpha_sm - mean(alpha_sm,na.rm=TRUE), by=.(Date,Sector)]
lt_panel[, alpha_sn := (alpha_sn-mean(alpha_sn,na.rm=TRUE))/sd(alpha_sn,na.rm=TRUE), by=Date]
sn_ic <- lt_panel[!is.na(alpha_sn)&!is.na(exret_fwd_1m),.(ic=if(.N>=20) cor(alpha_sn,exret_fwd_1m,method="spearman") else NA),by=Date][!is.na(ic)]
nm2<-nrow(sn_ic); m2<-mean(sn_ic$ic); t2<-m2/(sd(sn_ic$ic)/sqrt(nm2))
cat(sprintf("\nC7 sector-neutral IC=%.4f t=%.2f (vs raw IC=%.4f) retention=%.0f%%\n",
  m2,t2,lt$mic, 100*m2/lt$mic))

saveRDS(list(oos_ic=m, oos_t=t, oos_n=nm, train_signs=sgn,
  single_icir=best1$icir, comp_icir=lt$icir,
  single_crisis_ratio=mean(single_ic[bad==TRUE]$ic)/mean(single_ic[bad==FALSE]$ic),
  sn_ic=m2, sn_t=t2, sn_retention=m2/lt$mic), file.path(OUT,"codex_rebuttal.rds"))
cat("\n[codex_rebuttal] saved.\n")
