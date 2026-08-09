## FQ-143 P9 — 오라클 MDD 천장 + 산출물 발행 (alpha_scores.parquet / alpha_validation.json)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts)
                                 library(PerformanceAnalytics); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
WT   <- "WT-D20260809_002"
SA   <- file.path(ROOT, "stage_artifacts", gsub("-", "_", WT)); dir.create(SA, showWarnings = FALSE, recursive = TRUE)
p2 <- readRDS(file.path(DIR, "p4_panel_labeled.rds")); setDT(p2); setorder(p2, hold_ym)
COST <- 0.0015
p2[, scale_cur := beta_R05 * m4]
ser <- function(sv) { ds <- abs(sv - shift(sv, 1, fill = 1.0)); sv * p2$ret_orig - ds * COST }
mdd <- function(r) as.numeric(maxDrawdown(xts(r, order.by = as.Date(paste0(p2$hold_ym, "-01")))))
ann <- function(r) as.numeric(Return.annualized(xts(r, order.by = as.Date(paste0(p2$hold_ym,"-01"))), scale = 12))

cat("=== [P9-1] 오라클 천장 — 낙폭 축 (incumbent 위) ===\n")
inc <- ser(p2$scale_cur)
rows <- list()
addv <- function(nm, sv) { r <- ser(sv)
  rows[[length(rows)+1L]] <<- data.table(variant = nm, ann_ret = ann(r), MDD = mdd(r),
    Calmar = ann(r)/mdd(r), dMDD_vs_inc = mdd(r) - mdd(inc), dCalmar_vs_inc = ann(r)/mdd(r) - ann(inc)/mdd(inc)) }
addv("incumbent M4xR05",                p2$scale_cur)
addv("inc x label(-50%)",               p2$scale_cur*ifelse(p2$lab_on, .5, 1))
addv("inc x label(-70%)",               p2$scale_cur*ifelse(p2$lab_on, .3, 1))
addv("ORACLE inc x realized<-10%(-50%)",p2$scale_cur*ifelse(p2$ret_orig < -.10, .5, 1))
addv("ORACLE inc x realized<-10%(-100%)",p2$scale_cur*ifelse(p2$ret_orig < -.10, 0, 1))
vt <- rbindlist(rows)
print(vt[, .(variant, ann_ret = round(ann_ret,4), MDD = round(MDD,4), Calmar = round(Calmar,3),
             dMDD = round(dMDD_vs_inc,4), dCalmar = round(dCalmar_vs_inc,3))])
cat("  -> 완전 예지로 꼬리월 노출을 0 으로 만들어도 incumbent 대비 낙폭 개선폭이 이 라운드 레버의 천장\n")

## ---- alpha_scores.parquet : 월간 노출 스케일 패널 (종목별 alpha 아님 — 시장레벨 오버레이 라운드) ----
sc <- p2[, .(holding_ym = hold_ym, signal_ym = sig_ym, label_category = Category,
             label_on = lab_on, base_ret_orig = ret_orig, bm_ret,
             scale_incumbent = scale_cur,
             scale_tail_cc50 = ifelse(lab_on, .5, 1),
             scale_tail_crisis30 = ifelse(Category == "CRISIS", .3, 1),
             scale_inc_x_cc50 = scale_cur*ifelse(lab_on, .5, 1))]
sc[, `:=`(ret_incumbent = inc, ret_inc_x_cc50 = ser(p2$scale_cur*ifelse(p2$lab_on,.5,1)))]
write_parquet(sc, file.path(SA, "alpha_scores.parquet"))
cat(sprintf("\n[emit] %s  (%d행 x %d열, 월간 노출 스케일 패널)\n",
            file.path(SA, "alpha_scores.parquet"), nrow(sc), ncol(sc)))
fwrite(vt, file.path(DIR, "p9_oracle_mdd_ceiling.csv"))
saveRDS(vt, file.path(DIR, "p9_vt.rds"))
cat("\n[P9 DONE]\n")
