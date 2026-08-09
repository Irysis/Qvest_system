#==============================================================================
# a3_scope_and_overlap.R — C11/M25 영향월 + FQ-218 303개월과의 겹침 (실측)
# 읽기 전용. 재빌드 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
FQ218 <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

led <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))
cat(sprintf("[ledger] %s행  컬럼: %s\n", format(nrow(led), big.mark = ","),
            paste(names(led), collapse = ",")))

TGT <- c("C11_Earnings_Streak", "M25_Earnings_Mom_Streak")
sub <- led[Factor_Name %in% TGT]
if (!nrow(sub)) stop("[STOP] C11/M25 원장 행 0 — 0은 결론이 아니라 정지 신호. 이름 확인 필요.")

per <- sub[, .(n_months = uniqueN(ym), first_ym = min(ym), last_ym = max(ym),
               median_rows = as.numeric(median(n_rows)),
               total_rows = sum(n_rows)), by = Factor_Name]
print(per)

aff_new <- sort(unique(sub$ym))
cat(sprintf("\n[영향월] C11 or M25 배출월 = %d개월 (%s .. %s)\n",
            length(aff_new), min(aff_new), max(aff_new)))

aff218 <- fread(file.path(FQ218, "s1_affected_months.csv"))$ym
cat(sprintf("[FQ-218] C10/C13/C15 배출월 = %d개월 (%s .. %s)\n",
            length(aff218), min(aff218), max(aff218)))

inter <- intersect(aff_new, aff218)
only_new <- setdiff(aff_new, aff218)
only_218 <- setdiff(aff218, aff_new)
un <- union(aff_new, aff218)
cat(sprintf("\n[겹침] 교집합 = %d개월\n", length(inter)))
cat(sprintf("[겹침] C11/M25 에만 있는 월 = %d개월%s\n", length(only_new),
            if (length(only_new)) sprintf(" (%s .. %s)", min(only_new), max(only_new)) else ""))
cat(sprintf("[겹침] FQ-218 에만 있는 월 = %d개월%s\n", length(only_218),
            if (length(only_218)) sprintf(" (%s .. %s)", min(only_218), max(only_218)) else ""))
cat(sprintf("[겹침] 합집합 = %d개월  ⇒ 통합 재빌드 시 총 월수\n", length(un)))

all_m <- sort(unique(led$ym))
FULL_M <- 440L; FULL_MIN <- 460L
per_month_s <- FULL_MIN * 60 / FULL_M
cat(sprintf("\n[시간] 월당 단가 %.1f초 (전면 440개월/460분 실측)\n", per_month_s))
cat(sprintf("[시간] FQ-218 단독 %d개월 = %.0f분\n", length(aff218), length(aff218) * per_month_s / 60))
cat(sprintf("[시간] C11/M25 단독 %d개월 = %.0f분\n", length(aff_new), length(aff_new) * per_month_s / 60))
cat(sprintf("[시간] 통합(합집합) %d개월 = %.0f분\n", length(un), length(un) * per_month_s / 60))
cat(sprintf("[시간] 따로 두 번   = %.0f분  ⇒ 통합 절감 %.0f분\n",
            (length(aff218) + length(aff_new)) * per_month_s / 60,
            (length(aff218) + length(aff_new) - length(un)) * per_month_s / 60))
cat(sprintf("[시간] 전면 %d개월 = %.0f분\n", length(all_m), length(all_m) * per_month_s / 60))

fwrite(data.table(ym = un, in_fq218 = un %in% aff218, in_c11 = un %in% aff_new),
       file.path(OUT, "a3_union_months.csv"))
fwrite(per, file.path(OUT, "a3_affected_factors.csv"))
cat(sprintf("\n[out] %s\n", file.path(OUT, "a3_union_months.csv")))
