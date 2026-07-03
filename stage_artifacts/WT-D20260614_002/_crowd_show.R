suppressMessages(library(data.table))
r <- as.data.table(readRDS("stage_artifacts/WT-D20260614_002/_risk_crowding.rds"))
print(r[, .(factor_name, crowding_score=round(crowding_score,3), hhi_top=round(hhi_top,3),
            vol_concentration=round(vol_concentration,3), passive=round(passive_overlap_proxy,2),
            elasticity=round(demand_elasticity_proxy,3))][order(-crowding_score)])
