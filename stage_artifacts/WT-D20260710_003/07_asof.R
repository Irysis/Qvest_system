# 07_asof.R — winner as-of alpha vector + alpha_scores.parquet (screen-tier, negative discovery)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "stage_artifacts/WT-D20260710_003/02_harness.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_003")
bundle <- readRDS(file.path(OUT, "panel_bundle.rds"))
regime <- build_regime_signal(bundle)
CFG <- readRDS(file.path(OUT, "all_configs.rds"))
win <- fromJSON(file.path(OUT, "winner_config.json"))
wcfg <- CFG[[which(sapply(CFG, function(c) c$id) == win$winner_id)]]

# full-panel score + weights, take latest signal month as as_of
S <- build_score(bundle$features, bundle$size, wcfg)
S <- merge(S, bundle$univ[,.(Date,Ticker,adv20)], by=c("Date","Ticker"), all.x=TRUE)
S <- S[is.na(adv20)|adv20>=2e8]; S[,adv20:=NULL]
W <- build_weights(S, wcfg, regime=regime)
asof <- max(W$Date)
wa <- W[Date==asof]
sc <- S[Date==asof, .(Ticker, score)]
av <- merge(wa, sc, by="Ticker")
setorder(av, -w)
# alpha proxy = cross-sectional score (expected active-return signal); confidence from |z| percentile
av[, alpha := score]
av[, confidence := pmin(1, pmax(0.2, 0.5 + 0.15*score))]
scores_out <- av[, .(Date=asof, Ticker, alpha, weight=w, confidence)]
write_parquet(scores_out, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[asof] as_of=%s  %d names. top: %s\n", as.character(asof), nrow(scores_out),
    paste(head(av$Ticker,6), collapse=", ")))
# emit as_of vectors for the package
av_json <- as.list(setNames(round(scores_out$alpha,4), scores_out$Ticker))
cv_json <- as.list(setNames(round(scores_out$confidence,3), scores_out$Ticker))
write_json(list(as_of=as.character(asof), alpha_vector=av_json, confidence_vector=cv_json,
                top_names=head(scores_out$Ticker,25)),
           file.path(OUT, "asof_vectors.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[asof] alpha_scores.parquet + asof_vectors.json written\n")
