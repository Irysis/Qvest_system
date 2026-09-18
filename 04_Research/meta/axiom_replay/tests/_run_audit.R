setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/build_world.R")
ws <- readRDS("out/worlds.rds")
nd <- do.call(rbind, lapply(ws, function(w) cbind(base_id = w$base_id, regime = w$regime, w$nodes)))
um <- nd[grepl("^unmatched", nd$floor_audit), ]
cat("=== 불일치 52건의 어긋난 축 ===\n")
print(sort(table(sub("^unmatched:", "", um$floor_audit)), decreasing = TRUE))
cat("\n=== 불일치 × 블록 × 체제 ===\n"); print(table(um$block, um$regime))
cat("\n=== 감사 통과율 (양쪽 스펙 존재분) ===\n")
den <- nd[nd$floor_audit %in% c("spec_matched") | grepl("^unmatched", nd$floor_audit), ]
cat(sprintf("  전체 %d/%d = %.1f%%\n", sum(den$floor_audit == "spec_matched"), nrow(den),
            100*sum(den$floor_audit == "spec_matched")/nrow(den)))
for (rg in unique(den$regime)) { d <- den[den$regime == rg, ]
  cat(sprintf("  %-9s %d/%d = %.1f%%\n", rg, sum(d$floor_audit=="spec_matched"), nrow(d),
              100*sum(d$floor_audit=="spec_matched")/nrow(d))) }
cat("\n=== 스펙 결측 90건의 소재 ===\n")
ns <- nd[nd$floor_audit %in% c("no_spec","parent_no_spec"), ]
print(table(ns$regime, ns$evaluated))
