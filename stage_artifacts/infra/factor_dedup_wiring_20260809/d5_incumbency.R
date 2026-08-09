#==============================================================================
# d5_incumbency.R — 정본 선택 근거를 **실측**으로 (precedent 만으로 고르지 않는다)
#   축 1: 배출 이력 길이 (emission_ledger.csv 재판독)
#   축 2: 저장소 내 참조 빈도 (book/전략/파이프라인이 실제로 부르는 코드인가)
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/infra/factor_dedup_wiring_20260809")

led <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))
cat(sprintf("[d5] ledger rows=%s  factors=%d  ym %s..%s\n",
            format(nrow(led), big.mark = ","), uniqueN(led$Factor_Name),
            min(led$ym), max(led$ym)))

TARGETS <- c("C01_SUE", "C09_Earnings_Surprise_Sq", "C10_SUE_Persistence",
             "C04_ESBR", "C13_Revision_Breadth_3m",
             "C11_Earnings_Streak", "M25_Earnings_Mom_Streak")

s <- led[Factor_Name %in% TARGETS,
         .(n_months = uniqueN(ym), first_ym = min(ym), last_ym = max(ym),
           median_rows = as.integer(median(n_rows)),
           total_rows = sum(as.numeric(n_rows))), by = Factor_Name]
setorder(s, -n_months)
cat("\n[d5] 배출 이력:\n"); print(s)
fwrite(s, file.path(OUT, "d5_emission_history.csv"))

# 쌍별 대조
cat("\n[d5] 쌍별 배출 대조 (긴 쪽 = 정본 후보):\n")
prs <- list(c("C01_SUE", "C09_Earnings_Surprise_Sq"),
            c("C01_SUE", "C10_SUE_Persistence"),
            c("C04_ESBR", "C13_Revision_Breadth_3m"),
            c("C11_Earnings_Streak", "M25_Earnings_Mom_Streak"))
for (p in prs) {
  a <- s[Factor_Name == p[1]]; b <- s[Factor_Name == p[2]]
  ga <- if (nrow(a)) a$n_months else 0L; gb <- if (nrow(b)) b$n_months else 0L
  cat(sprintf("  %-26s %4d개월  vs  %-26s %4d개월   → 더 긴 쪽: %s\n",
              p[1], ga, p[2], gb, if (ga >= gb) p[1] else p[2]))
}
cat("[d5] done\n")
