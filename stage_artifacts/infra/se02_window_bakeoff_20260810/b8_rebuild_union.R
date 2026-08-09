#==============================================================================
# b8_rebuild_union.R — 재빌드 월 집합 산술 (도훈 confirm 재료)
#   ★재빌드 실행 없음. 월 집합만 센다.
#
#   확정 배경: SE02 배출 318개월(200003..202608) ⊇ 통합C 303개월.
#   질문: 롤오버 계열(C14/C17/M26/M28)까지 같은 배치에 넣으면 월수가 늘어나는가?
#         늘지 않으면 한 번의 재빌드로 FQ-218 + FQ-219 + SE02 + 롤오버 계열을
#         전부 처리할 수 있다(한계비용 0).
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
led  <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))

grp <- list(
  FQ218 = c("C10_SUE_Persistence","C13_Revision_Breadth_3m","C15_Forecast_Error_Trend"),
  FQ219 = c("C11_Earnings_Streak","M25_Earnings_Mom_Streak"),
  M32   = c("M32_Composite_Mom_v2"),
  SE02  = c("SE02_Consensus_Revision"),
  ROLL  = c("C14_Revenue_Surprise","C17_OP_Revision","M26_Revenue_Mom","M28_OP_Rev_Mom"))
mo <- lapply(grp, function(f) sort(unique(led[Factor_Name %in% f, ym])))
for (nm in names(mo)) {
  m <- mo[[nm]]
  if (!length(m)) { cat(sprintf("[STOP] %s 원장 0건 — 0은 결론이 아니라 정지 신호\n", nm)); next }
  cat(sprintf("%-6s %3d개월  %s .. %s\n", nm, length(m), min(m), max(m)))
}
cat("\n-- 롤오버 계열 팩터별 --\n")
print(led[Factor_Name %in% grp$ROLL, .(n_months = uniqueN(ym), first = min(ym),
                                       last = max(ym), med_rows = median(n_rows)),
          by = Factor_Name])

mo$M32 <- intersect(mo$M32, mo$FQ219)      # M32 는 M25 있는 달에만 값이 바뀐다
FULL_M <- 440L; FULL_MIN <- 460L; pm <- FULL_MIN*60/FULL_M

scen <- list(
  "C. FQ218+FQ219 (현 confirm 대기)"       = Reduce(union, list(mo$FQ218, mo$FQ219, mo$M32)),
  "D. C + SE02"                            = Reduce(union, list(mo$FQ218, mo$FQ219, mo$M32, mo$SE02)),
  "E. C + SE02 + 롤오버계열(C14/C17/M26/M28)" = Reduce(union, list(mo$FQ218, mo$FQ219, mo$M32,
                                                                   mo$SE02, mo$ROLL)),
  "F. 롤오버계열 단독(나중에 따로 할 경우)"   = mo$ROLL,
  "G. SE02 단독(나중에 따로 할 경우)"         = mo$SE02)
R <- rbindlist(lapply(names(scen), function(k) data.table(
  scenario = k, n_months = length(scen[[k]]), minutes = round(length(scen[[k]])*pm/60))))
cat("\n-- 시나리오별 월수/분 --\n"); print(R)
fwrite(R, file.path(OUT, "b8_rebuild_scenarios.csv"))

cat(sprintf("\nSE02 한계비용  (D - C) = %d개월 / %d분\n",
            R$n_months[2]-R$n_months[1], R$minutes[2]-R$minutes[1]))
cat(sprintf("롤오버계열 한계비용 (E - D) = %d개월 / %d분\n",
            R$n_months[3]-R$n_months[2], R$minutes[3]-R$minutes[2]))
cat(sprintf("나중에 따로 할 때: SE02 단독 %d분 · 롤오버계열 단독 %d분 · 둘 합 %d분\n",
            R$minutes[5], R$minutes[4], R$minutes[4]+R$minutes[5]))
cat(sprintf("\n롤오버계열이 SE02 월집합의 부분집합인가: %s (ROLL\\SE02 = %d개월)\n",
            all(mo$ROLL %in% mo$SE02), length(setdiff(mo$ROLL, mo$SE02))))
cat(sprintf("C 가 SE02 월집합의 부분집합인가: %s\n", all(scen[[1]] %in% mo$SE02)))
fwrite(data.table(ym = scen[[3]]), file.path(OUT, "b8_union_months_scenarioE.csv"))
cat("\n[b8 완료]\n")
