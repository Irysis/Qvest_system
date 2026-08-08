## run_16 — next_probe ②: 계약 rds 를 live-z 기준으로 재도출하면 성과가 어떻게 바뀌나 (읽기전용)
##
## 방법: 원장이 이미 두 계열을 나란히 갖고 있다.
##   ret_net              = 현행(계약 rds 앵커, 2016+ 는 동결 고정방향 기준)
##   ret_recompute_panel  = 현 패널 기준 재계산 = **live-z 기준 전기간 재산출과 동치**
##   (2026-08-08 z 원천을 live 로 통일했으므로 재계산치는 live 기준이다)
## ★자체합성 금지: SR/CAGR/MDD 는 PerformanceAnalytics 표준함수만 사용.
## ★라벨: metric_type = "backtested_recon" — 계약 rds 재도출의 **대리 측정**이다(forge 재실행 아님).
suppressPackageStartupMessages({library(data.table); library(xts); library(PerformanceAnalytics)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
L <- fread(file.path(R, "06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv"))
L[, date := as.Date(date)]
setorder(L, date)

mk <- function(v, d) { x <- xts(v, order.by = d); x[is.finite(coredata(x))] }
cur <- mk(L$ret_net, L$date)
liv <- mk(L$ret_recompute_panel, L$date)
cat(sprintf("[계열] 현행 %d행 · live재산출 %d행 · 공통 %d행\n\n",
            length(cur), length(liv), length(index(cur)[index(cur) %in% index(liv)])))

stat <- function(x, nm) {
  ann <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  data.table(계열 = nm,
             CAGR = as.numeric(ann[1, 1]),
             변동성 = as.numeric(ann[2, 1]),
             SR = as.numeric(ann[3, 1]),
             MDD = as.numeric(maxDrawdown(x)),
             누적 = as.numeric(Return.cumulative(x)),
             n = length(x))
}
s <- rbindlist(list(stat(cur, "현행(rds 앵커·동결 기준)"), stat(liv, "live-z 전기간 재산출")))
s[, Calmar := CAGR / MDD]
cat("=== 성과 대조 (PerformanceAnalytics 표준함수) ===\n")
print(s[, .(계열, CAGR = round(CAGR, 4), SR = round(SR, 4), MDD = round(MDD, 4),
            Calmar = round(Calmar, 3), 누적 = round(누적, 3), n)])

d <- s[2] ; b <- s[1]
cat(sprintf("\n[차이] SR %+.4f · CAGR %+.4f%%pt · MDD %+.4f%%pt · Calmar %+.3f\n",
            d$SR - b$SR, 100*(d$CAGR - b$CAGR), 100*(d$MDD - b$MDD), d$Calmar - b$Calmar))

## 제약 충족 여부 (제2목표: SR 2.5+ / CAGR 16%+ / MDD <25%)
cat("\n=== 목표 대비 ===\n")
for (k in 1:2) with(s[k], cat(sprintf("  %-26s SR %.3f %s · CAGR %.1f%% %s · MDD %.1f%% %s\n",
    계열, SR, ifelse(SR >= 2.5, "OK", "미달"), 100*CAGR, ifelse(CAGR >= 0.16, "OK", "미달"),
    100*MDD, ifelse(MDD < 0.25, "OK", "★위반"))))

## 최근 구간(2016+) 만 — 기준이 갈리는 구간
cat("\n=== 2016+ 부분구간 (기준이 실제로 다른 구간) ===\n")
i16 <- index(cur) >= as.Date("2016-01-01")
s16 <- rbindlist(list(stat(cur[i16], "현행"), stat(liv[index(liv) >= as.Date("2016-01-01")], "live재산출")))
s16[, Calmar := CAGR / MDD]
print(s16[, .(계열, CAGR = round(CAGR,4), SR = round(SR,4), MDD = round(MDD,4), Calmar = round(Calmar,3), n)])
cat(sprintf("  [2016+ 차이] SR %+.4f · MDD %+.4f%%pt\n", s16[2]$SR - s16[1]$SR, 100*(s16[2]$MDD - s16[1]$MDD)))

cat("\n[라벨] metric_type = backtested_recon (원장 계열 기반 대리 측정 — 계약 rds forge 재실행 아님)\n")
fwrite(rbind(s[, era := "full"], s16[, era := "2016+"], fill = TRUE),
       file.path(R, "stage_artifacts/beta_z_source_20260808/rds_rederive_impact.csv"))
cat("[저장] rds_rederive_impact.csv\n")
