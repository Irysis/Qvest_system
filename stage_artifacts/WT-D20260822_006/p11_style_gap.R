## P11 — qvest-alpha-style 출력 의무 대조에서 적발한 누락 2건 수리
##   (net-of-cost SR / AX-001 v2 ratio 가 alpha_validation 에만 있고 alpha_package 에 부재)
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_006"; MB <- "qepm/mailbox/worktask/WT-D20260822_006"
P  <- readRDS(file.path(OUT,"p2_arms.rds")); V5 <- readRDS(file.path(OUT,"p5_emit.rds"))
BT <- P$BT; AX <- V5$AX
pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)

pkg$diagnostics$net_sr_after_cost <- as.numeric(BT$T3_DISP$net_sr)
pkg$diagnostics$net_sr_control_C0 <- as.numeric(BT$C0$net_sr)
pkg$diagnostics$net_sr_note <- paste(
  "net-of-cost 활성 SR (delta-based 15bps 차감 후, cost_model_version v2.4_kr_retail_15bps).",
  "gross 단독 보고 없음 — 본 라운드 전 수치가 net 이다.")
pkg$diagnostics$alpha_annualized_net <- as.numeric(BT$T3_DISP$alpha_annualized)
pkg$diagnostics$ax001_v2_ratio <- list(
  bad_over_normal = as.numeric(AX[arm=="T3_DISP", bad_over_normal_ic_ratio]),
  crisis_alpha_annual_pct = as.numeric(AX[arm=="T3_DISP", crisis_alpha_ann]),
  normal_alpha_annual_pct = as.numeric(AX[arm=="T3_DISP", normal_alpha_ann]),
  crisis_t_nw3 = as.numeric(AX[arm=="T3_DISP", crisis_t]),
  bad_months = 44L, normal_months = 177L,
  note = paste("방어형 팩터 라운드가 아니므로 AX-001 v2 는 판정 축이 아니라 조건부 기록 의무 이행용.",
    "실측은 승계 regime_scope 의 holds_in('위기-회복')과 반대 방향이나 |t| < 2 라 국면 주장으로 승격하지 않는다(CF-06)."))
pkg$diagnostics$cor_vs_admitted_incumbent <- NA
pkg$diagnostics$cor_vs_admitted_note <- paste(
  "★미산출 — style 계약의 'cor vs 기존 admitted < 0.95' 는 book incumbent alpha 계열과의 상관을 뜻하는데,",
  "그 비교의 base 권위는 05_Production 현행 코드 실산출(measurement-graduation §7b)이고 본 라운드는",
  "round_verdict = CONFIG_SCOPED_NEGATIVE 로 admission 을 주장하지 않아 incumbent 소집 사유가 없다.",
  "대신 본 마디의 직접 부모(FQ-244 C0)와의 상관을 alpha_inheritance_cor 0.9282 로 실측·신고했다.",
  "자본 경로 진입 시에는 이 필드를 production 실산출로 채워야 하며, 지금 비운 것은 누락이 아니라 미소집이다.")
cfs <- unlist(pkg$challenge_flags)
cfs <- c(cfs, paste("CF-17 [LOW] style 계약의 'cor vs 기존 admitted(<0.95)' 는 미산출 —",
  "incumbent base 권위가 05_Production 실산출이고 본 라운드는 admission 미주장이라 소집 사유 부재.",
  "부모 마디(FQ-244 C0) 대비 상관 0.9282 로 대체 신고. 자본 경로 진입 시 필수 산출 항목."))
pkg$challenge_flags <- as.list(cfs)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat(sprintf("net_sr T3_DISP %.4f / C0 %.4f · ax001 ratio %.4f · flags %d\n",
  BT$T3_DISP$net_sr, BT$C0$net_sr, AX[arm=="T3_DISP", bad_over_normal_ic_ratio], length(cfs)))
