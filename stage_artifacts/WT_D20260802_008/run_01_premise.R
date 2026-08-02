## run_01_premise.R — NP-2 커버리지 조건화: 전제 검증 (WT-002 CF-08 형) + 게이트 패널 구축
##   BASE = WT-002 의 BASE 그대로 (하네스 정합 앵커). 커버리지는 as-of d0 (30일 스테일 한도, 부재=0).
##   측정(수익) 없음 — 데이터 실측만. 사전등록 stop_rule: share(cov0) < 0.05 → 존재-전제 공허.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(4); try(arrow::set_io_thread_count(4), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"
TD2 <- "stage_artifacts/WT_D20260802_002"

## ── [1] WT-002 BASE 재구성 (run_03 과 동일 레시피 — 앵커 정합) ──────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
S <- as.data.table(read_parquet(file.path(TD2, "gate_panel.parquet")))
S[, Date := as.Date(Date)]
LIQ_MIN <- 2e8
BASE <- merge(S, liqf[, .(Date, Ticker, adv2 = adv)], by = c("Date", "Ticker"), all.x = TRUE)
BASE <- BASE[is.na(adv2) | adv2 >= LIQ_MIN][is.finite(score) & is.finite(fa_share_l0)]
BASE[, adv2 := NULL]
cat(sprintf("[BASE] rows=%d months=%d  월평균=%.1f  (WT-002: 78131/268/291.5 기대)\n",
            nrow(BASE), uniqueN(BASE$Date), nrow(BASE) / uniqueN(BASE$Date)))

## ── [2] 커버리지 as-of 조인 (rolling join, 30일 스테일 한도) ────────────────────
cov <- as.data.table(read_parquet(".cache/consensus/coverage.parquet"))
cov[, Date := as.Date(Date)]
cat(sprintf("[cov] rows=%d tickers=%d  %s ~ %s (수동 export 스테일 검사: max=%s, as_of 2026-08-02)\n",
            nrow(cov), uniqueN(cov$Ticker), min(cov$Date), max(cov$Date), max(cov$Date)))
setkey(cov, Ticker, Date)

asof_cov <- function(q_dates_dt, cutoff_shift_months = 0L) {
  ## q_dates_dt: unique (Date, Ticker). cutoff = d0 (shift=0) 또는 d0 - 1개월 (shift=1)
  Q <- copy(q_dates_dt)
  Q[, cut_date := if (cutoff_shift_months == 0L) Date else {
    d <- as.POSIXlt(Date); d$mon <- d$mon - cutoff_shift_months; as.Date(d)
  }]
  qq <- Q[, .(Ticker, Date = cut_date)]
  setkey(qq, Ticker, Date)
  j <- cov[qq, on = .(Ticker, Date), roll = 30]   # 마지막 관측(<= cut, 30일 이내), 없으면 NA
  Q[, cov_val := fifelse(is.na(j$coverage), 0, j$coverage)]
  Q[, cut_date := NULL][]
}
KEY <- unique(BASE[, .(Date, Ticker)])
K0 <- asof_cov(KEY, 0L); setnames(K0, "cov_val", "cov_l0")
K1 <- asof_cov(KEY, 1L); setnames(K1, "cov_val", "cov_l1")
BASE <- merge(BASE, K0, by = c("Date", "Ticker"))
BASE <- merge(BASE, K1, by = c("Date", "Ticker"))
stopifnot(!anyNA(BASE$cov_l0), !anyNA(BASE$cov_l1))

## ── [3] 전제 검증 (CF-08 형) ────────────────────────────────────────────────────
sh0  <- mean(BASE$cov_l0 == 0)
sh1  <- mean(BASE$cov_l0 <= 1)
sh2  <- mean(BASE$cov_l0 <= 2)
cat(sprintf("\n[전제] BASE 종목-월 커버리지: cov==0 비율 = %.4f | cov<=1 = %.4f | cov<=2 = %.4f\n", sh0, sh1, sh2))
cat("[전제] cov_l0 분포:\n"); print(round(quantile(BASE$cov_l0, c(0,.05,.25,.5,.75,.95,1)), 2))
byyr <- BASE[, .(sh_cov0 = mean(cov_l0 == 0), sh_le1 = mean(cov_l0 <= 1),
                 med_cov = median(cov_l0), n = .N), by = .(yr = year(Date))][order(yr)]
cat("[전제] 연도별:\n"); print(byyr)

## 월별 분할 실효성: 상위 50% 경계값(중앙값)이 0 인 달 = 분할이 존재/부재 경계와 겹침
mo <- BASE[, .(med = as.numeric(median(cov_l0)), sh0 = mean(cov_l0 == 0)), by = Date]
cat(sprintf("[전제] 월 중앙값 cov 분포: min=%.1f q25=%.1f q50=%.1f q75=%.1f max=%.1f | 중앙값==0 인 달 = %d/%d\n",
            min(mo$med), quantile(mo$med, .25), median(mo$med), quantile(mo$med, .75), max(mo$med),
            sum(mo$med == 0), nrow(mo)))

## 게이트 vs 대조변수 상관 (WT-002 진단 동형)
sub <- BASE[is.finite(adv) & is.finite(Size)]
cs <- sub[, .(r_adv = suppressWarnings(cor(frank(cov_l0), frank(adv))),
              r_size = suppressWarnings(cor(frank(cov_l0), frank(Size)))), by = Date]
cat(sprintf("[진단] cov~adv 월별 Spearman 평균 = %+.3f | cov~Size = %+.3f\n",
            mean(cs$r_adv, na.rm = TRUE), mean(cs$r_size, na.rm = TRUE)))

## A_base top-25 (score 순) 내 cov0 비중 — 게이트가 실제 선택을 바꿀 여지
top25 <- BASE[order(Date, -score), .SD[1:min(25, .N)], by = Date]
t25_sh0 <- mean(top25$cov_l0 == 0); t25_le1 <- mean(top25$cov_l0 <= 1)
cat(sprintf("[진단] A_base top-25 내 cov==0 비율 = %.4f | cov<=1 = %.4f | 중앙값 cov = %.1f\n",
            t25_sh0, t25_le1, median(top25$cov_l0)))

verdict <- if (sh0 < 0.05) "PREMISE_VOID_EXISTENCE" else "PREMISE_HOLDS"
cat(sprintf("\n[전제 판정] share(cov0)=%.4f vs stop_rule 0.05 → %s\n", sh0, verdict))

write_parquet(BASE, file.path(TD, "cov_panel.parquet"))
prem <- list(share_cov0 = sh0, share_cov_le1 = sh1, share_cov_le2 = sh2,
             by_year = byyr, monthly_median_zero_months = sum(mo$med == 0),
             n_months = nrow(mo), cor_cov_adv = mean(cs$r_adv, na.rm = TRUE),
             cor_cov_size = mean(cs$r_size, na.rm = TRUE),
             top25_share_cov0 = t25_sh0, top25_share_le1 = t25_le1,
             cov_file_max_date = as.character(max(cov$Date)),
             base_rows = nrow(BASE), base_months = uniqueN(BASE$Date),
             verdict = verdict)
saveRDS(prem, file.path(TD, "premise.rds"))
write_json(prem, file.path(TD, "premise.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[SAVED] cov_panel.parquet / premise.json\n[DONE]\n")
