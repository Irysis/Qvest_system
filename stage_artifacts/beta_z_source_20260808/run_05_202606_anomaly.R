# run_05_202606_anomaly.R — 2026-06 동결 패널 이상 규명 (z 원천 결정의 선행 조건)
# run_01/04 실측: 2026-06 만 per-ticker rank 상관 −0.689, top20 평균도 동결 −0.4249 vs live +0.3734 로 반대.
# 가설 후보: ①부호 정렬(align_factor_direction) 차이 ②전환월 규약 혼입 ③데이터 손상
# 검증: 2026-05·06 을 per-ticker 로 직접 대조하고, 부호 반전 여부·정렬 전후 값을 분해한다.
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/beta_z_source_20260808"; reg <- .load_registry()
frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")); frz[, Date := as.Date(Date)]

probe <- function(dd) {
  dd <- as.Date(dd)
  fz <- frz[Date == dd & is.finite(R05_Tail_Risk_Z), .(Ticker, z_frozen = R05_Tail_Risk_Z)]
  f <- tryCatch(load_month_factors(dd, factor_names = "R05_Tail_Risk"), error = function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- as.data.table(f)
  zc0 <- if ("Z_Score" %in% names(f)) "Z_Score" else "Z_Score_Aligned"
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(get(zc0))]
  raw_live <- f[, .(Ticker, z_raw = get(zc0))]                      ## 정렬 **전**
  fa <- as.data.table(tryCatch(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date = dd, min_ic_months = 12L),
                               error = function(e) copy(f)))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  ali_live <- fa[, .(Ticker, z_ali = get(zc))]                      ## 정렬 **후**
  m <- Reduce(function(a,b) merge(a,b,by="Ticker"), list(fz, raw_live, ali_live))
  if (nrow(m) < 30) return(NULL)
  data.table(Date = dd, n = nrow(m),
             cor_frozen_raw = cor(m$z_frozen, m$z_raw, method="spearman"),
             cor_frozen_ali = cor(m$z_frozen, m$z_ali, method="spearman"),
             cor_raw_ali    = cor(m$z_raw,   m$z_ali,  method="spearman"),
             mean_frozen = mean(m$z_frozen), mean_raw = mean(m$z_raw), mean_ali = mean(m$z_ali),
             sd_frozen = sd(m$z_frozen), sd_raw = sd(m$z_raw))
}
R <- rbindlist(Filter(Negate(is.null), lapply(
  c("2026-01-01","2026-02-01","2026-03-01","2026-04-01","2026-05-01","2026-06-01"), probe)), fill=TRUE)
cat("[per-ticker Spearman — 동결 vs live(정렬 전/후)]\n"); print(R[, .(Date, n,
  `동결~raw` = round(cor_frozen_raw,4), `동결~정렬후` = round(cor_frozen_ali,4), `raw~정렬후` = round(cor_raw_ali,4))])
cat("\n[수준]\n"); print(R[, .(Date, mean_frozen = round(mean_frozen,4), mean_raw = round(mean_raw,4),
                              mean_ali = round(mean_ali,4), sd_frozen = round(sd_frozen,4), sd_raw = round(sd_raw,4))])
cat("\n[해석 규약]\n")
cat("  · `raw~정렬후` 가 −1 이면 그 달 align_factor_direction 이 **부호를 뒤집었다**.\n")
cat("  · `동결~raw` 는 +1 인데 `동결~정렬후` 가 −1 이면 → 동결 패널은 **정렬 전** 값을 담고 있다.\n")
cat("  · 둘 다 −1 이 아니면 부호 문제가 아니라 **다른 계산**(유니버스·winsor 등).\n")
flip <- R[abs(cor_raw_ali + 1) < 0.05]
cat(sprintf("\n[판정] 정렬이 부호를 뒤집은 달: %s\n",
            if (nrow(flip)) paste(as.character(flip$Date), collapse=", ") else "없음"))
d6 <- R[Date == as.Date("2026-06-01")]
if (nrow(d6)) cat(sprintf("[2026-06] 동결~raw %.4f · 동결~정렬후 %.4f · raw~정렬후 %.4f → %s\n",
  d6$cor_frozen_raw, d6$cor_frozen_ali, d6$cor_raw_ali,
  ifelse(abs(d6$cor_frozen_raw) > 0.9 && d6$cor_frozen_ali < -0.5,
         "★동결은 **정렬 전 값** — 정렬 규약 불일치가 원인",
         ifelse(abs(d6$cor_frozen_raw) < 0.5, "★동결이 raw 와도 안 맞음 — 별개 계산/손상 의심", "혼합"))))
fwrite(R, file.path(OUT, "anomaly_202606.csv"))
