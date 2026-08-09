#!/usr/bin/env Rscript
# run_regime_basis_ab_20260809.R — regime 하네스 basis 수리의 **A/B 실측** (도훈 "진행해" 2026-08-09).
#
# 왜: 배선 전에 basis 를 바꿨다. 교체만 하고 넘어가면 그것도 선언이다 —
#     같은 창에서 구/신 기준선을 나란히 재서 "무엇이 얼마나 바뀌었나"를 수치로 남긴다.
#   구(legacy): carrier = carrier_STR_1715_AR_on_M4_R05_overlay_PG2 (2026-06-18 빌드, 퇴역 PG2)
#               book 노출 = 05_Production 2-1 period_returns_layer5.csv (퇴역 Layer4/faith 오버레이)
#   신(정본)  : carrier = carrier_meta.json 경유 (현 admitted_ids = STR_1715_on_M4gAE_R05_noLayer4_PG2)
#               book 노출 = 캐리어 `invested` (북 실측, net 재현 cor 0.9999)
# 자본 admit 없음 — 측정·보고만(governor 정지).
suppressMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
Sys.setenv(QVEST_REGIME_AB_NORUN = "1")
source("02_Infrastructure/ops/auto_regime_overlay_ab.R")

LEGACY_CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"

cat("\n########## A) 구 basis (퇴역 캐리어 + layer5 노출) ##########\n")
old <- run_regime_overlay_ab(carrier_path = LEGACY_CARRIER, book_exposure_source = "layer5")
print(old$tab)

cat("\n########## B) 신 basis (meta 캐리어 + carrier invested) ##########\n")
new <- run_regime_overlay_ab()          # 기본값 = 정본
print(new$tab)

cat("\n########## Δ (신 − 구), 공통 시나리오 ##########\n")
j <- merge(old$tab[, .(scenario, IR_old = IR, SR_old = abs_SR, MDD_old = abs_MDD, exp_old = avg_exposure)],
           new$tab[, .(scenario, IR_new = IR, SR_new = abs_SR, MDD_new = abs_MDD, exp_new = avg_exposure)],
           by = "scenario")
j[, `:=`(dIR = round(IR_new - IR_old, 3), dSR = round(SR_new - SR_old, 3),
         dMDD = round(MDD_new - MDD_old, 4), dExp = round(exp_new - exp_old, 4))]
print(j[, .(scenario, IR_old = round(IR_old, 3), IR_new = round(IR_new, 3), dIR,
            SR_old = round(SR_old, 3), SR_new = round(SR_new, 3), dSR, dMDD, dExp)])

cat(sprintf("\n구 basis: carrier=%s · book_exposure=%s · months=%d\n", old$carrier, old$book_basis, old$n_months))
cat(sprintf("신 basis: carrier=%s · book_exposure=%s · months=%d\n", new$carrier, new$book_basis, new$n_months))
cat(sprintf("PIT(신): 최종 사용 컷오프 %s · 홀딩월 시작까지 최소 간격 %.0f일\n",
            new$pit$max_used_cutoff, new$pit$min_gap_days))

cat("\n=== AX-001 crisis-conditional (신 basis) ===\n"); print(new$crisis)

fwrite(new$tab,    "06_Registry/book_carrier/h2_regime_overlay_ab.csv")
fwrite(new$crisis, "06_Registry/book_carrier/h2_regime_crisis_eval.csv")
fwrite(j,          "stage_artifacts/paper_recharge/regime_basis_ab_20260809.csv")
cat("\n저장: h2_regime_overlay_ab.csv (신 basis 정본) · regime_basis_ab_20260809.csv (구/신 Δ)\n")
