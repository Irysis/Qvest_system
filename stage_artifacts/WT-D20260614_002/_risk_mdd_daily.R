suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics) })
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260614_002"
btr <- readRDS("stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds")
pr <- as.data.table(btr$period_returns)[, .(date, ret_net)]; setorder(pr, date)
# daily NAV + drawdown (PIT-safe DD: standard cummax path, no lookahead in DD calc itself)
nav <- cumprod(1 + pr$ret_net)
peak <- cummax(nav); dd <- nav/peak - 1
mdd_daily <- min(dd)
ti <- which.min(dd); pi <- max(which(dd[1:ti] == 0))
cat(sprintf("[mdd-daily] MDD=%.4f peak=%s trough=%s\n", mdd_daily, pr$date[pi], pr$date[ti]))
# also via PerformanceAnalytics for parity
rx <- xts::xts(pr$ret_net, order.by = pr$date)
cat("[mdd-daily] PerformanceAnalytics maxDrawdown=", round(as.numeric(maxDrawdown(rx)),4), "\n")
# count severe drawdown episodes (peak-to-trough >=20% / >=30% / >=45%)
# episode = contiguous underwater period
underwater <- dd < -1e-9
rle_uw <- rle(underwater)
ends <- cumsum(rle_uw$lengths); starts <- ends - rle_uw$lengths + 1
ep_depth <- c()
for (k in which(rle_uw$values)) ep_depth <- c(ep_depth, min(dd[starts[k]:ends[k]]))
cat(sprintf("[mdd-daily] episodes >=20%%: %d  >=30%%: %d  >=45%%: %d\n",
            sum(ep_depth <= -0.20), sum(ep_depth <= -0.30), sum(ep_depth <= -0.45)))
saveRDS(list(mdd_daily=mdd_daily, peak=as.character(pr$date[pi]), trough=as.character(pr$date[ti]),
             n_ep_20=sum(ep_depth<=-0.20), n_ep_30=sum(ep_depth<=-0.30), n_ep_45=sum(ep_depth<=-0.45),
             longest_uw_days = max(rle_uw$lengths[rle_uw$values])),
        file.path(OUT, "_risk_mdd_daily.rds"))
