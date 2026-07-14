suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
data.table::setDTthreads(1); arrow::set_io_thread_count(2)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_014")
m <- fread(file.path(OUT,"mismatch_census_ALL.csv"))
m[, Date := as.Date(Date)]; m[, prevDate := as.Date(prevDate)]

cat("=== prevDate 분포 (recompute이 참조한 이전 종가 날짜) ===\n")
print(m[, .N, by=prevDate][order(prevDate)])
cat("\n=== Date 분포 ===\n")
print(m[, .N, by=Date][order(Date)])

cat("\n=== gapdays 분포 ===\n")
print(m[, .N, by=gapdays][order(gapdays)])

cat("\n=== cause=unknown 35건 상세 ===\n")
print(m[cause=="unknown", .(Date, Ticker, Name, in_univ, Close, prevClose, gapdays,
   Ret_stored=round(Ret_stored,4), Ret_recompute=round(Ret_recompute,4),
   dAbs=round(dAbs,4), source, prevSource)][order(-dAbs)])

# stored vs recompute: 어느쪽이 물리적으로 타당한가? |stored|<=0.31 (제한내) 비율
cat(sprintf("\n=== 방향 판정 ===\n"))
cat(sprintf(" |Ret_stored|<=0.31 (KR 제한내·물리타당): %d/%d (%.1f%%)\n",
    m[abs(Ret_stored)<=0.31,.N], nrow(m), 100*m[abs(Ret_stored)<=0.31,.N]/nrow(m)))
cat(sprintf(" |Ret_recompute|<=0.31: %d/%d (%.1f%%)\n",
    m[abs(Ret_recompute)<=0.31,.N], nrow(m), 100*m[abs(Ret_recompute)<=0.31,.N]/nrow(m)))
cat(" → stored가 제한내면 stored가 참값(recompute은 gap 넘어 stale prevClose 참조)\n")

# 종목 성격: 우선주(우/우B) + 신규상장 추정
m[, is_pref := grepl("우$|우B$|우C$", Name)]
cat(sprintf("\n 우선주(Name 끝 '우/우B') 추정: %d/%d\n", m[is_pref==TRUE,.N], nrow(m)))
cat(sprintf(" Name NA(마스터 미매칭 신규/희귀): %d/%d\n", m[is.na(Name)|Name=="",.N], nrow(m)))
