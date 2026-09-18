setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/validate_world.R")
ws <- readRDS("out/worlds.rds")
lane <- ar_lane_batches(); recon <- ar_recon_batches(ws)
cat("레인 batch_start:", nrow(lane), " · 재구성 배치:", nrow(recon), "\n")
m <- ar_batch_match(lane, recon)
cat(sprintf("\n=== 일치율 %d/%d = %.1f%% (사전등록 바 95%%) ===\n",
            sum(m$matched), nrow(m), 100*mean(m$matched)))
cat("\n불일치 사유:\n"); print(sort(table(sub("_[0-9]+min$","_TIME", m$why[!m$matched])), decreasing=TRUE))
cat("\n체제별(로그 시각 기준 09-04 이후):\n")
post <- m[!is.na(m$ts) & m$ts >= AR_REGIME_CUT, ]
cat(sprintf("  post_0904 %d/%d = %.1f%%\n", sum(post$matched), nrow(post), 100*mean(post$matched)))
pre <- m[!is.na(m$ts) & m$ts < AR_REGIME_CUT, ]
cat(sprintf("  pre_0904  %d/%d = %.1f%%\n", sum(pre$matched), nrow(pre), 100*mean(pre$matched)))
cat("\n미일치 표본 5건:\n")
print(head(m[!m$matched, c("ts","block","n_cells","codes","why")], 5), row.names=FALSE)
