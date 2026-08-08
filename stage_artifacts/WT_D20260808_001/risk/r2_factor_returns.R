# =============================================================================
# r2_factor_returns.R — Step 2/3: 월별 횡단면 회귀 → 팩터수익 f_t + 잔차 e_it
#   Ret_1m ~ 1(Market) + Sector dummies + Style z  (WLS, w = sqrt(Size))
#   PIT: 좌변은 [d, d+1] forward, 우변 노출은 d 시점 trailing → 미래참조 없음.
#   metric_type = risk_estimate (성과 주장 아님)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt, ...) cat(sprintf(paste0("[r2] ", fmt, "\n"), ...))

E <- as.data.table(read_parquet(file.path(OUT, "exposure_panel.parquet")))
E[, Date := as.Date(Date)]
say("입력 exposure_panel rows=%d 월 %d (%s~%s) 관측단위 월간",
    nrow(E), uniqueN(E$Date), as.character(min(E$Date)), as.character(max(E$Date)))

STY <- c("X_BETA","X_SIZE","X_IVOL","X_LIQ","X_MOM","X_QUAL","X_VAL")
# ★X_D03 은 회귀 우변에서 제외 — IVOL 과 -0.644 로 겹치고, 본 라운드의 질문이
#   "D03 tier 의 공동움직임이 기존 축(BETA/IVOL)으로 설명되는가" 이므로 D03 을 넣으면
#   질문 자체가 자명해진다. D03 은 진단 축(tier 라벨)으로만 쓴다.

# 유효 표본: 스타일 전부 관측 + 수익 관측
D <- E[is.finite(Ret_1m) & Reduce(`&`, lapply(STY, function(c) is.finite(E[[c]])))]
say("회귀 표본 rows=%d (%.1f%% of panel) | 월 %d", nrow(D), 100*nrow(D)/nrow(E), uniqueN(D$Date))

# 섹터 축약 (월별 5종목 미만 → OTHER)
D[, sec := as.character(Sector)]
sec_n <- D[, .N, by = .(Date, sec)]
small <- sec_n[N < 5]
D[sec_n[N < 5], on = .(Date, sec), sec := "OTHER"]
sec_lv <- sort(unique(D$sec))
say("섹터 수준 %d (축약 후) | OTHER 비중 %.3f", length(sec_lv), mean(D$sec == "OTHER"))
base_sec <- names(sort(table(D$sec), decreasing = TRUE))[1]
say("기준 섹터(합-0 제약의 종속 열) = %s", base_sec)
sec_use <- setdiff(sec_lv, base_sec)
# ★섹터는 sum-to-zero 제약(Barra 표준)으로 코딩한다. 단순 omitted-dummy 로 두면
#   MKT 절편이 '기준섹터 수익'이 되어 MKT↔SEC 공분산이 -var(기준섹터) 로 크게 음이 되고
#   Ω 조건수가 악화된다(1차 실행: cond 3358, 개별 예측 연변동 중앙 0.649 = 실현 대비 과대).
#   제약 코딩: col_s = 1{sec=s} - (n_s/n_base)*1{sec=base}  ⇒ Σ_s n_s f_s = 0, MKT = 시장수익.

fac_names <- c("MKT", paste0("SEC_", sec_use), STY)
K <- length(fac_names); say("팩터 수 K=%d", K)

dts <- sort(unique(D$Date))
f_mat <- matrix(NA_real_, nrow = length(dts), ncol = K,
                dimnames = list(as.character(dts), fac_names))
r2_vec <- rep(NA_real_, length(dts)); nobs <- rep(NA_integer_, length(dts))
res_list <- vector("list", length(dts))

for (i in seq_along(dts)) {
  d <- dts[i]; sub <- D[Date == d]
  if (nrow(sub) < K + 20L) next
  Xd <- matrix(0, nrow(sub), K, dimnames = list(NULL, fac_names))
  Xd[, "MKT"] <- 1
  is_base <- as.numeric(sub$sec == base_sec); n_base <- sum(is_base)
  for (s in sec_use) {
    ns <- sum(sub$sec == s)
    Xd[, paste0("SEC_", s)] <- as.numeric(sub$sec == s) -
      (if (n_base > 0) (ns / n_base) * is_base else 0)
  }
  for (s in STY) Xd[, s] <- sub[[s]]
  keep <- which(apply(Xd, 2, function(z) stats::sd(z) > 0 | all(z == 1)))
  Xu <- Xd[, keep, drop = FALSE]
  wt <- sqrt(pmax(sub$Size, 1)); wt <- wt / mean(wt)
  fit <- tryCatch(stats::lm.wfit(Xu, sub$Ret_1m, w = wt), error = function(e) NULL)
  if (is.null(fit)) next
  cf <- fit$coefficients; cf[is.na(cf)] <- 0
  f_mat[i, colnames(Xu)] <- cf
  e <- sub$Ret_1m - as.numeric(Xu %*% cf)
  ssr <- sum(wt * e^2); sst <- sum(wt * (sub$Ret_1m - stats::weighted.mean(sub$Ret_1m, wt))^2)
  r2_vec[i] <- 1 - ssr/sst; nobs[i] <- nrow(sub)
  res_list[[i]] <- data.table(Date = d, Ticker = sub$Ticker, resid = e)
}

RES <- rbindlist(res_list)
ok <- which(!is.na(r2_vec))
say("회귀 성공 월 %d/%d | 평균 R2 %.3f (중앙 %.3f) | 월평균 종목 %.0f",
    length(ok), length(dts), mean(r2_vec[ok]), median(r2_vec[ok]), mean(nobs[ok]))
say("잔차 패널 rows=%d | 잔차 sd(pooled) %.4f", nrow(RES), stats::sd(RES$resid))

F_dt <- data.table(Date = dts)[, (fac_names) := as.data.table(f_mat)][ok]
say("팩터수익 시계열 rows=%d (%s ~ %s)", nrow(F_dt),
    as.character(min(F_dt$Date)), as.character(max(F_dt$Date)))

fs <- F_dt[, lapply(.SD, function(x) c(mean(x, na.rm=TRUE)*12, stats::sd(x, na.rm=TRUE)*sqrt(12))),
           .SDcols = fac_names]
say("팩터 연율 평균/변동 (상위 몇 개):")
.tb <- data.table(fname = fac_names,
                  ann_mean = round(as.numeric(fs[1]), 4),
                  ann_vol  = round(as.numeric(fs[2]), 4))
print(.tb[order(-abs(ann_mean))][1:12])

write_parquet(F_dt, file.path(OUT, "factor_returns.parquet"))
write_parquet(RES,  file.path(OUT, "residuals_panel.parquet"))
sec_counts <- D[, .N, by = .(Date, sec)]
saveRDS(list(fac_names = fac_names, sty = STY, base_sec = base_sec, sec_use = sec_use,
             r2 = r2_vec[ok], dates = dts[ok], nobs = nobs[ok], sec_counts = sec_counts),
        file.path(OUT, "r2_meta.rds"))
write_parquet(D[, .(Date, Ticker, sec)], file.path(OUT, "sector_map.parquet"))
say("저장 완료")
