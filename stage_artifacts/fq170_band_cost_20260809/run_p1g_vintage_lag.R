## P1g — 내 아크 패널이 same-month(off+1) look-ahead 인가 T-1 clean 인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  FQ-044(R29 완료): str1715 계열 저장 패널 = **전기간 균일 same-month(off+1) look-ahead**,
##    controlled 비교로 top-25 cap-w PORT_t **2.08~2.18x 부풀림**. production forward recompute = T-1 clean.
##  ★내 패널(merged_panel, 08-08 WT 빌드)은 **별도 빌드**다 — 같은 매핑을 썼는지 미검.
##  측정: 내 D03_EWMA(월 T) 를 DB D03_RealVol 의 월 T, T-1, T-2, T+1 과 각각 대조(월별 spearman 중앙값).
##    ★내 D03_EWMA ~ DB D03_RealVol 동월 rho = 0.959 (BD1 실측)이 이미 있다 — 그 0.959 가
##      **어느 lag 에서 최대인지**가 판별점이다.
##   R1 clean: 최대 상관이 **lag -1**(전월 DB 값) → 내 패널은 T-1, FQ-044 오염과 무관
##   R2 오염: 최대 상관이 **lag 0**(동월 DB 값) → same-month. 정본 2.137 을 clean 기준으로 재산출 필요
##   R3 불명: 최대가 |rho|<0.5 이거나 lag 간 차이 < 0.05 → 판별 불가, 다른 통제 필요
##  ★성과 측정 없음. vintage 판별만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
B[, Date := as.Date(Date)]
ds <- sort(unique(B[!is.na(D03_EWMA)]$Date))
smp <- ds[seq(1, length(ds), by = 6L)]; smp <- smp[smp >= as.Date("2008-01-01")]
cat(sprintf("[내 패널] %d개월 · 샘플 %d개월\n", length(ds), length(smp)))

## DB 월 목록(내 패널 날짜와 앵커가 다를 수 있으므로 ym 으로 매칭)
res <- list()
for (L in c(-2L,-1L,0L,1L)) {
  v <- numeric(0)
  for (i in seq_along(smp)) {
    t_my <- smp[i]
    j <- match(as.character(t_my), as.character(ds))
    t_db <- ds[j + L]                      # 내 패널 날짜축에서 L 만큼 이동한 달
    if (is.na(t_db)) next
    z <- try(load_month_factors(t_db, factor_names = "D03_RealVol"), silent = TRUE)
    if (inherits(z, "try-error")) next
    z <- as.data.table(z)[!is.na(Z_Score_Aligned), .(Ticker, db = Z_Score_Aligned)]
    m <- merge(B[Date == t_my, .(Ticker, mine = D03_EWMA)], z, by = "Ticker")
    if (nrow(m) < 60L) next
    v <- c(v, suppressWarnings(cor(m$mine, m$db, method = "spearman", use = "complete.obs")))
  }
  if (length(v)) res[[length(res)+1L]] <- data.table(lag = L, n_months = length(v),
                                                     rho = round(median(abs(v)), 4))
}
R <- rbindlist(res); print(R[])
if (!nrow(R)) { cat("★산출 0 — 정지 신호\n"); quit(status=0) }
best <- R[which.max(rho)]
sec  <- R[order(-rho)][2]
cat(sprintf("\n최대 상관 lag = **%d** (rho %.4f) · 2위 lag %d (%.4f) · 차이 %.4f\n",
            best$lag, best$rho, sec$lag, sec$rho, best$rho - sec$rho))
verdict <- {
  if (best$rho < 0.5 || (best$rho - sec$rho) < 0.05) "R3_INDETERMINATE"
  else if (best$lag == -1L) "R1_CLEAN_T_MINUS_1"
  else if (best$lag == 0L)  "R2_SAME_MONTH_CONTAMINATED"
  else "R3_INDETERMINATE"
}
cat(sprintf("판정: %s\n", verdict))
if (verdict == "R2_SAME_MONTH_CONTAMINATED")
  cat("★★아크 정본 2.137 을 clean 기준으로 재산출해야 한다(FQ-044 배율 2.08~2.18x 참조)\n")
write_json(list(verdict=verdict, best_lag=best$lag, best_rho=best$rho,
                gap=best$rho-sec$rho, scan=R),
           file.path(OUT,"p1g_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
