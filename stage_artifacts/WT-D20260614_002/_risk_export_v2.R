# Export v2 parquets (security cov with market factor, factor cov 11x11, exposure, specific)
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260614_002"
rc <- readRDS(file.path(OUT,"_risk_core_v2.rds"))
FACTORS <- rc$FACTORS; names_alpha <- rownames(rc$Sigma)
Sig<-rc$Sigma; covdt<-as.data.table(Sig); covdt[,Ticker:=names_alpha]; setcolorder(covdt,c("Ticker",names_alpha))
write_parquet(covdt, file.path(OUT,"covariance.parquet"))
Om<-as.data.table(rc$Omega); Om[,Factor:=FACTORS]; setcolorder(Om,c("Factor",FACTORS))
write_parquet(Om, file.path(OUT,"factor_covariance.parquet"))
Bdt<-as.data.table(rc$B); Bdt[,Ticker:=names_alpha]; setcolorder(Bdt,c("Ticker",FACTORS))
write_parquet(Bdt, file.path(OUT,"exposure_matrix.parquet"))
sr<-data.table(Ticker=names_alpha, market_beta=as.numeric(rc$beta_vec[names_alpha]),
               specific_var_annual=as.numeric(rc$D_vec), specific_vol_annual=sqrt(as.numeric(rc$D_vec)),
               factor_var_explained=as.numeric(rc$fve[names_alpha]))
write_parquet(sr, file.path(OUT,"specific_risk.parquet"))
cat("[export v2] covariance.parquet", nrow(covdt),"x",ncol(covdt)-1,
    "| factor_cov", nrow(Om),"| exposure", nrow(Bdt),"x",ncol(Bdt)-1,"\n")
cat("[export v2] mean factor R2 =", round(mean(sr$factor_var_explained,na.rm=TRUE),3),
    "| (vs pre-market-factor 0.011)\n")
