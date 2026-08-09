#!/usr/bin/env Rscript
# verify_regime_numbers_20260809.R — 보고한 regime 수치를 **재계산**해 대조 (performance_realmeasure_gate).
#
# 규약: 인용이 아니라 실측. 저장된 CSV 를 읽어 옮기는 것은 "돌렸다"가 아니다
#       ([[feedback-performance-real-code-only]]). 그래서 배터리를 **처음부터 다시 돌리고**,
#       저장본과 일치하는지까지 확인한다(재현 실패 = 보고 무효).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
Sys.setenv(QVEST_REGIME_AB_NORUN = "1")
source("02_Infrastructure/ops/auto_regime_overlay_ab.R")

cat("\n########## 1) H2 regime A/B 재계산 (신 basis, 캐시 미사용) ##########\n")
o <- run_regime_overlay_ab()
tab <- o$tab
print(tab[, .(scenario, abs_SR = round(abs_SR, 4), abs_CAGR = round(abs_CAGR, 4),
              abs_MDD = round(abs_MDD, 4), IR = round(IR, 4), PORT_t = round(PORT_t, 3),
              avg_exposure = round(avg_exposure, 4), n_months)])

cat(sprintf("\nbasis: book_exposure=%s · carrier=%s · months=%d\n", o$book_basis, o$carrier, o$n_months))
cat(sprintf("PIT: 최종 사용 컷오프 %s · 홀딩월 시작까지 최소 간격 %.0f일\n",
            o$pit$max_used_cutoff, o$pit$min_gap_days))

g <- function(s, col) as.numeric(tab[scenario == s, get(col)])

cat("\n########## 2) 보고한 수치 재계산 ##########\n")
base_ir  <- g("book_L5", "IR");  base_mdd <- g("book_L5", "abs_MDD")
bare_ir  <- g("bare", "IR");     bare_mdd <- g("bare", "abs_MDD")
uni_ir   <- g("uni_cat", "IR");  lag1_ir  <- g("uni_cat_lag1", "IR")
cat(sprintf("  book_L5 IR            = %.4f   (보고 1.410)\n", base_ir))
cat(sprintf("  bare    IR            = %.4f   (보고 1.477)\n", bare_ir))
cat(sprintf("  bare − book_L5 IR     = %+.4f  (보고 +0.067 — 오버레이가 IR 을 지불)\n", bare_ir - base_ir))
cat(sprintf("  book_L5 MDD           = %.4f  (보고 -23.3%%)\n", base_mdd))
cat(sprintf("  bare    MDD           = %.4f  (보고 -40.7%%)\n", bare_mdd))
cat(sprintf("  MDD 차이(절대 %%p)      = %.2f%%p (보고 17.5%%p — 오버레이가 사는 것)\n",
            (abs(bare_mdd) - abs(base_mdd)) * 100))
cat(sprintf("  lag1 보존율            = %.4f  (보고 0.936; uni_cat %.4f → lag1 %.4f)\n",
            lag1_ir / uni_ir, uni_ir, lag1_ir))
for (s in c("uni_cat", "uni_cat_x_book", "voltgt", "voltgt_x_book")) {
  cat(sprintf("  %-16s IR %.4f  ΔIR %+.4f  ΔMDD %+.4f (%s)\n", s, g(s, "IR"),
              g(s, "IR") - base_ir, g(s, "abs_MDD") - base_mdd,
              if (g(s, "abs_MDD") - base_mdd > 0) "낙폭 완화" else if (g(s, "abs_MDD") - base_mdd < 0) "낙폭 심화" else "동일"))
}

cat("\n########## 3) AX-001 조건부 (CRISIS/CAUTION 월) 재계산 ##########\n")
cr <- o$crisis
print(cr)
tr <- cr[crisis == TRUE]
cat(sprintf("  위기 라벨 %d개월 · bare %.4f%% / book %.4f%% / uni %.4f%% (월평균, 보고 4.15/3.54/1.89)\n",
            tr$n, tr$bare_mean * 100, tr$book_mean * 100, tr$uni_mean * 100))

cat("\n########## 4) 저장본 재현 대조 (h2_regime_overlay_ab.csv) ##########\n")
st <- fread("06_Registry/book_carrier/h2_regime_overlay_ab.csv")
j <- merge(tab[, .(scenario, IR_new = IR, MDD_new = abs_MDD)],
           st[, .(scenario, IR_old = IR, MDD_old = abs_MDD)], by = "scenario")
j[, `:=`(dIR = IR_new - IR_old, dMDD = MDD_new - MDD_old)]
print(j[, .(scenario, dIR = signif(dIR, 3), dMDD = signif(dMDD, 3))])
cat(sprintf("  ★재현 판정: max|ΔIR| = %.3g · max|ΔMDD| = %.3g → %s\n",
            max(abs(j$dIR)), max(abs(j$dMDD)),
            if (max(abs(j$dIR)) < 1e-9 && max(abs(j$dMDD)) < 1e-9) "완전 재현(저장본 = 재계산)" else "★불일치 — 보고 무효"))

cat("\n########## 5) Σ 배터리 risk 팔 재확인 (저장본 실측치) ##########\n")
sg <- fread("06_Registry/book_carrier/h1b_sigma_ab_overlay.csv")
gs <- function(m) as.numeric(sg[method == m, IR])
cat(sprintf("  strategy(book)               IR %.4f\n", gs("strategy")))
cat(sprintf("  minvar_lw                    IR %.4f\n", gs("minvar_lw")))
cat(sprintf("  minvar@ProperScoreGASFilter  IR %.4f  ΔIR vs minvar_lw = %+.4f (보고 -0.222)\n",
            gs("minvar@ProperScoreGASFilter"), gs("minvar@ProperScoreGASFilter") - gs("minvar_lw")))
cat(sprintf("  PreferenceRobustDistortion   IR %.4f  ΔIR vs book      = %+.4f (보고 -0.751)\n",
            gs("PreferenceRobustDistortion"), gs("PreferenceRobustDistortion") - gs("strategy")))
cat("\n[verify] done\n")
