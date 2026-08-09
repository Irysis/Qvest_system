#==============================================================================
# s1_rebuild_scope.R — FQ-219 재빌드 범위 + FQ-218 과의 통합 가능성 (실측)
#  ★재빌드 실행 없음. 도훈 confirm 재료.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
led <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))

grp <- list(
  FQ218_C10C13C15 = c("C10_SUE_Persistence", "C13_Revision_Breadth_3m",
                      "C15_Forecast_Error_Trend"),
  FQ219_C11M25    = c("C11_Earnings_Streak", "M25_Earnings_Mom_Streak"),
  FQ219_M32_prop  = c("M32_Composite_Mom_v2"),
  SE02_pending    = c("SE02_Consensus_Revision")
)
mo <- lapply(grp, function(f) sort(unique(led[Factor_Name %in% f, ym])))
for (nm in names(mo)) {
  m <- mo[[nm]]
  if (!length(m)) { cat(sprintf("[STOP] %s 원장 0건 — 0은 결론이 아니라 정지 신호\n", nm)); next }
  cat(sprintf("%-16s %3d개월  %s .. %s\n", nm, length(m), min(m), max(m)))
}

# ★배출월 ≠ 변경월. M32 는 428개월 배출되지만 **M25 가 있는 달에만 값이 바뀐다**
#   (M32 = mean(z(M01,M10,M13,M24,M25)), M25 전건 NA 인 달은 z_M25 가 전후 모두 NA).
#   v2 실측이 이를 확인했다: 바뀐 M32 티커의 100% 가 M25-touched 집합 안이다.
#   그러므로 M32 의 **변경월** = M25 배출월 ∩ M32 배출월.
mo$FQ219_M32_prop <- intersect(mo$FQ219_M32_prop, mo$FQ219_C11M25)
cat(sprintf("%-16s %3d개월  (배출월이 아니라 **변경월**로 교정)\n",
            "FQ219_M32_chg", length(mo$FQ219_M32_prop)))

FULL_M <- 440L; FULL_MIN <- 460L
pm <- FULL_MIN * 60 / FULL_M
scen <- list(
  "A. FQ-218 단독(현 confirm 대기)"      = mo$FQ218_C10C13C15,
  "B. FQ-219 단독(C11/M25/M32)"          = union(mo$FQ219_C11M25, mo$FQ219_M32_prop),
  "C. A+B 통합"                          = Reduce(union, list(mo$FQ218_C10C13C15,
                                                              mo$FQ219_C11M25, mo$FQ219_M32_prop)),
  "D. A+B+SE02 통합(SE02 수리 시)"       = Reduce(union, list(mo$FQ218_C10C13C15,
                                                              mo$FQ219_C11M25, mo$FQ219_M32_prop,
                                                              mo$SE02_pending))
)
cat("\n-- 시나리오별 재빌드 월수/시간 (월당 단가 %.1f초) --\n")
res <- rbindlist(lapply(names(scen), function(k) data.table(
  scenario = k, n_months = length(scen[[k]]),
  minutes = round(length(scen[[k]]) * pm / 60))))
print(res)
cat(sprintf("\n통합(C) 절감 = A 따로 + B 따로(%d분) - 통합(%d분) = %d분\n",
            round((length(scen[[1]]) + length(scen[[2]])) * pm / 60),
            round(length(scen[[3]]) * pm / 60),
            round((length(scen[[1]]) + length(scen[[2]]) - length(scen[[3]])) * pm / 60)))
cat(sprintf("SE02 추가 한계비용 = D - C = %d개월 / %d분\n",
            length(scen[[4]]) - length(scen[[3]]),
            round((length(scen[[4]]) - length(scen[[3]])) * pm / 60)))
cat(sprintf("\nB 가 A 의 진부분집합인가: %s (B\\A = %d개월)\n",
            all(scen[[2]] %in% scen[[1]]), length(setdiff(scen[[2]], scen[[1]]))))
fwrite(res, file.path(OUT, "s1_rebuild_scenarios.csv"))
fwrite(data.table(ym = scen[[4]]), file.path(OUT, "s1_union_months_with_se02.csv"))
