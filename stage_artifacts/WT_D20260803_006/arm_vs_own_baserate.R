# =============================================================================
# arm_vs_own_baserate.R — WT-D20260803_006 최종 정정 실측
#  ★내 초안 서술 "실시간 arm 10종 중 자기 평가구간 상수규칙을 넘은 것 0건" 을 검증한다.
#   전체표본 arm(rt_cusum/trail*)은 BR_maj=0.5025 를 **명목상 넘는다**(0.512~0.552).
#   따라서 그 서술은 과대주장이며 정정 필요. 각 arm 의 **자기 평가 부분집합** base rate 를
#   실측해 정확한 표를 만든다.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006BR] ", fmt, "\n"), ...))

R6 <- readRDS(file.path(OUT, "era_results.rds")); AP3 <- readRDS(file.path(OUT, "adversarial_probes3.rds"))
Sp <- R6$Sp; P <- copy(Sp$P)
const_acc <- function(y) max(mean(y == 1L), mean(y == -1L))

rows <- list()
add <- function(id, pred, idx, leaked = FALSE) {
  y <- P$y[idx]; p <- pred[idx]; ok <- !is.na(p)
  rows[[length(rows) + 1L]] <<- data.table(arm = id, n = sum(ok),
    acc = mean(p[ok] == y[ok]), own_base = const_acc(y[ok]),
    delta = mean(p[ok] == y[ok]) - const_acc(y[ok]), leaked = leaked)
}
allidx <- seq_len(nrow(P))
for (cc in c("rt_cusum","br_rt","trail12","trail24","trail36","trail60"))
  add(cc, P[[paste0("p_", cc)]], allidx)
# 로지스틱 arm 3종 — 자기 평가 부분집합
for (nm in c("L3","L4","L5")) {
  L <- R6[[nm]]; D <- L$D; pr <- L$pred; ok <- !is.na(pr)
  rows[[length(rows)+1L]] <- data.table(arm = c(L3="XSEC_STRUCT", L4="SPREAD_COMPRESS", L5="CONCENTRATION")[nm],
    n = sum(ok), acc = mean(pr[ok] == D$y[ok]), own_base = const_acc(D$y[ok]),
    delta = mean(pr[ok] == D$y[ok]) - const_acc(D$y[ok]), leaked = FALSE)
}
rows[[length(rows)+1L]] <- data.table(arm = "MULTIVAR_13F", n = AP3$n_eval, acc = AP3$F_acc,
  own_base = AP3$base_subset, delta = AP3$F_acc - AP3$base_subset, leaked = FALSE)
# 음성대조
Pm <- R6$Pm
rows[[length(rows)+1L]] <- data.table(arm = "REGIME_LABEL_NC(음성대조)", n = 139L, acc = R6$acc_nc,
  own_base = const_acc(Pm$y), delta = R6$acc_nc - const_acc(Pm$y), leaked = FALSE)
for (cc in c("peek6","fullcusum","oracle")) add(paste0("INJ_", toupper(cc)), P[[paste0("p_", cc)]], allidx, TRUE)

TAB <- rbindlist(rows)
TAB[, `:=`(acc = round(acc,4), own_base = round(own_base,4), delta = round(delta,4))]
say("=== arm vs 자기 평가 부분집합 base rate ===")
print(TAB)
rt <- TAB[leaked == FALSE]
say("PIT-clean arm %d 중 자기 base 초과 %d건 (명목), 초과폭 최대 %+.4f (%s)",
    nrow(rt), sum(rt$delta > 0), max(rt$delta), rt$arm[which.max(rt$delta)])
say("★정정: '자기 base 를 넘은 것 0건' 은 **과대주장**. 정확한 서술 =")
say("   '명목 초과 %d건이나 초과폭 최대 %+.3f 이고 primary 의 bootstrap p=0.362 — 어느 것도 유의하지 않다'",
    sum(rt$delta > 0), max(rt$delta))
say("누출 arm 초과폭: %s", paste(sprintf("%s %+.3f", TAB[leaked==TRUE]$arm, TAB[leaked==TRUE]$delta), collapse=" / "))
saveRDS(TAB, file.path(OUT, "arm_vs_own_baserate.rds"))
write.csv(TAB, file.path(OUT, "arm_vs_own_baserate.csv"), row.names = FALSE, fileEncoding = "UTF-8")
say("DONE")
