## run_17 — era-aware 안: 증거가 있는 구간(IC 유의)만 live-z, 그 이전은 현행 유지
##
## 배경(run_15/16): live 는 2016+ 에서 3지표 전부 우위이나 전기간 재도출은 pre-2016 손해로 상쇄된다.
##   ⇒ 변경을 증거 구간에만 국한하면 이득만 취할 수 있는가?
## ★경계 단일값 판정 회피: cut 을 2013~2019 로 흔들어 결론이 경계 선택에 얼마나 의존하는지 함께 잰다
##   (교훈 [[project-threshold-single-draw-fragility]] — 단일 draw 판정 금지).
## ★자체합성 금지: PerformanceAnalytics 표준함수만. 라벨 backtested_recon.
suppressPackageStartupMessages({library(data.table); library(xts); library(PerformanceAnalytics)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
L <- fread(file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv"))
L[, date := as.Date(date)]; setorder(L, date)
L <- L[is.finite(ret_net) & is.finite(ret_recompute_panel)]
cat(sprintf("[계열] %d행 · %s ~ %s\n\n", nrow(L), min(L$date), max(L$date)))

stat <- function(v, d, nm) {
  x <- xts(v, order.by = d)
  ann <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  cagr <- as.numeric(ann[1,1]); mdd <- as.numeric(maxDrawdown(x))
  data.table(안 = nm, CAGR = cagr, SR = as.numeric(ann[3,1]), MDD = mdd,
             Calmar = cagr/mdd, 누적 = as.numeric(Return.cumulative(x)))
}

base_cur  <- stat(L$ret_net,             L$date, "(b) 현행 = rds 앵커 전기간")
base_live <- stat(L$ret_recompute_panel, L$date, "(a) 전기간 live-z 재산출")

## era-aware: cut 이전 = 현행, cut 이후 = live 재산출
era_row <- function(cut) {
  v <- ifelse(L$date >= as.Date(sprintf("%d-01-01", cut)), L$ret_recompute_panel, L$ret_net)
  s <- stat(v, L$date, sprintf("(c) era-aware cut=%d", cut))
  s[, cut := cut][, n_live := sum(L$date >= as.Date(sprintf("%d-01-01", cut)))]
  s
}
eras <- rbindlist(lapply(2013:2019, era_row), fill = TRUE)

all <- rbind(base_cur, base_live, eras, fill = TRUE)
cat("=== 전기간 성과 (PerformanceAnalytics) ===\n")
print(all[, .(안, CAGR = round(CAGR,4), SR = round(SR,4), MDD = round(MDD,4),
              Calmar = round(Calmar,3), 누적 = round(누적,1))])

cur <- base_cur$Calmar; curS <- base_cur$SR; curM <- base_cur$MDD
cat(sprintf("\n=== 현행 대비 (기준: Calmar %.3f · SR %.4f · MDD %.4f) ===\n", cur, curS, curM))
cmp <- all[grepl("^\\(c\\)", 안)]
cmp[, `:=`(dCalmar = Calmar - cur, dSR = SR - curS, dMDD = MDD - curM)]
print(cmp[, .(cut, n_live, SR = round(SR,4), dSR = round(dSR,4),
              MDD = round(MDD,4), dMDD_pp = round(100*dMDD,2),
              Calmar = round(Calmar,3), dCalmar = round(dCalmar,3),
              판정 = ifelse(Calmar >= cur & SR >= curS, "★현행 우위 유지+개선",
                     ifelse(Calmar >= cur, "Calmar 유지", "현행 미만")))])

cat("\n[경계 민감도]\n")
cat(sprintf("  Calmar 범위 %.3f ~ %.3f (현행 %.3f) · 현행 이상인 cut: %s\n",
            min(cmp$Calmar), max(cmp$Calmar), cur,
            if (any(cmp$Calmar >= cur)) paste(cmp[Calmar >= cur]$cut, collapse = ", ") else "없음"))
cat(sprintf("  SR 범위 %.4f ~ %.4f (현행 %.4f) · MDD 전 cut 제약(<25%%) 충족: %s\n",
            min(cmp$SR), max(cmp$SR), curS, all(cmp$MDD < 0.25)))

cat("\n[판정]\n")
win <- cmp[Calmar >= cur & SR >= curS]
if (nrow(win) >= 4) {
  cat(sprintf("  ★era-aware 안 성립 — %d/7 경계에서 현행 대비 SR·Calmar 동시 개선(경계 강건).\n", nrow(win)))
  cat("    ⇒ 부활조건 ① 충족 → rds 재도출(era-aware) 상신 가능.\n")
} else if (nrow(win) >= 1) {
  cat(sprintf("  △조건부 — %d/7 경계에서만 성립. 경계 선택에 의존하므로 단독 상신 부적합.\n", nrow(win)))
} else {
  cat("  ★era-aware 도 현행을 못 넘는다 — 부활조건 ① 미충족, 재도출 상신하지 않는다.\n")
  cat("    ⇒ 현행(rds 앵커 유지 + beta_matches_ret_net 로 이음매 표시)이 실측상 최선.\n")
}
fwrite(all, file.path(R, "stage_artifacts/beta_z_source_20260808/era_aware_impact.csv"))
cat("\n[저장] era_aware_impact.csv · 라벨 metric_type=backtested_recon\n")
