suppressPackageStartupMessages({library(data.table); library(jsonlite); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_006"; MB <- "qepm/mailbox/worktask/WT-D20260822_006"
P <- readRDS(file.path(OUT,"p2_arms.rds"))
j <- merge(P$SC$C0[, .(Date,Ticker,s0=score)], P$SC$T3_DISP[, .(Date,Ticker,s1=score)], by=c("Date","Ticker"))
inh_x <- j[, .(c=cor(s0,s1)), by=Date]
inh <- mean(inh_x$c)
inh_rank <- mean(j[, .(c=cor(rank(s0),rank(s1))), by=Date]$c)
cat(sprintf("alpha_inheritance_cor (월별 횡단면 pearson 평균) = %.6f · rank 평균 = %.6f\n", inh, inh_rank))
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
cf <- pkg$challenge_flags
pkg$challenge_flags <- lapply(cf, function(x) paste0(x$id, " [", x$severity, "] ", x$flag))
pkg$diagnostics$alpha_inheritance_cor <- inh
pkg$diagnostics$alpha_inheritance_cor_rank <- inh_rank
pkg$diagnostics$alpha_inheritance_note <- paste(
  "★wt_type=discovery 의 role card 기준(alpha_inheritance_cor < 0.95)을 실측이 초과한다 —",
  sprintf("%.4f.", inh),
  "본 라운드는 신규 알파 원천을 만든 것이 아니라 기존 결합 마디(C0)를 상태로 조절한 것이므로 이는 설계상 필연이며",
  "(전 처치 arm 이 u=0 에서 C0 로 정확히 환원되도록 설계됨), 은폐 없이 신고한다.",
  "판정 결과가 powered null 이라 admission 경로에 진입하지 않으므로 certificate 미발급이 정상 동작이며,",
  "재분류가 필요하다면 discovery 가 아니라 'node_modulation' 계열이다 — governance_log 에 reclassify_proposal 로 기록 권고.")
pkg$diagnostics$post_neutralization_ic <- NULL
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[patched] alpha_package.json\n")
