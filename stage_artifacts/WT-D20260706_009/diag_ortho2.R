suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PAN <- file.path(ROOT,"stage_artifacts/WT-D20260706_009/panel")
sc <- as.data.table(read_parquet(file.path(PAN,"nsi_scores_monthly.parquet")))[Date>=as.Date("2005-01-01")]
bkp <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
bk <- as.data.table(read_parquet(bkp))[, .(Date, Ticker, book_alpha=score_eff)]

m <- merge(sc[is.finite(nsi_shares), .(Date,Ticker,nsi_shares,nsi_cei,size_pctile)], bk, by=c("Date","Ticker"))
m <- m[is.finite(book_alpha)]

# monthly cross-sectional Spearman corr, then average (Fisher-z)
bym <- m[, .(rho = suppressWarnings(cor(nsi_shares, book_alpha, method="spearman"))), by=Date][is.finite(rho)]
cat(sprintf("[ortho] NSI_shares vs book_alpha(STR_1715 AR): mean monthly Spearman = %.3f  (n=%d months)\n",
            mean(bym$rho), nrow(bym)))
# pearson too
bymp <- m[, .(rho = suppressWarnings(cor(nsi_shares, book_alpha, method="pearson"))), by=Date][is.finite(rho)]
cat(sprintf("[ortho] NSI_shares vs book_alpha: mean monthly Pearson = %.3f\n", mean(bymp$rho)))
# CEI vs book
bymc <- m[, .(rho = suppressWarnings(cor(nsi_cei, book_alpha, method="spearman"))), by=Date][is.finite(rho)]
cat(sprintf("[ortho] NSI_cei   vs book_alpha: mean monthly Spearman = %.3f\n", mean(bymc$rho)))

# vs Size (large-cap confound check)
bys <- sc[is.finite(nsi_shares), .(rho=suppressWarnings(cor(nsi_shares, size_pctile, method="spearman"))), by=Date][is.finite(rho)]
cat(sprintf("[ortho] NSI_shares vs Size percentile: mean monthly Spearman = %.3f\n", mean(bys$rho)))
saveRDS(list(nsi_vs_book_spear=mean(bym$rho), nsi_vs_book_pear=mean(bymp$rho),
             cei_vs_book_spear=mean(bymc$rho), nsi_vs_size=mean(bys$rho), n_months=nrow(bym)),
        file.path(ROOT,"stage_artifacts/WT-D20260706_009/ortho_results.rds"))
cat("[ortho] DONE\n")
