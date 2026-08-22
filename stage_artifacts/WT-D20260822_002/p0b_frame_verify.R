## P0b — 앵커 프레임 검증 재설계 (p0_probe 의 음성 대조가 무효였음을 수리)
##
## ★p0_probe 실측: FIXED +0.0053 (지문 광고 +0.0170 과 불일치) · "BROKEN" +0.0183 (광고 -0.9423 과 불일치).
##   진단: 내 BROKEN 은 팩터를 **월말**(sig_date) 스탬프한 것인데, 문서화된 결함은 팩터를
##   **자기 달 월초 1일**로 스탬프하는 것이다. 월말 스탬프는 asof(월말)→asof(익월말) = 익월 수익이라
##   FIXED(익월1일→익익월1일)와 사실상 같은 달을 잰다 ⇒ 내 음성 대조는 결함이 아니었고 검출력 0.
##   ⇒ 여기서 **진짜 결함**(자기 달 월초 스탬프)을 주입해 지문이 발화하는지 실측한다.
##
## ★성능 수리: 팩터별로 259개월을 각각 도는 초판은 파일 읽기 O(팩터 x 월) 이었다.
##   load_month_factors(factor_names=vector) 가 Arrow 푸시다운을 하므로 **월당 1회 읽기**로 접는다.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p0b_frame_verify.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")
OUT <- "stage_artifacts/WT-D20260822_002"
SRC <- "stage_artifacts/fq233_probe0_20260813"

p0 <- readRDS(file.path(OUT, "p0_returns.rds"))
sig_dates <- p0$sig_dates
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet")); raw[, Date := as.Date(Date)]
nextm <- function(d) as.Date(cut(as.Date(d) + 40L, "month"))
thism <- function(d) as.Date(cut(as.Date(d),       "month"))   # 자기 달 월초 = 문서화된 결함

pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
featcols <- setdiff(names(pan), c("anchor","sig_date","Ticker","fwd_ret_1m"))
set.seed(20260822L)
SAMP <- unique(c("M04_Mom_1", "M08_ResidMom", sample(featcols, 12L)))
cat("대상 팩터", length(SAMP), "종:", paste(SAMP, collapse=", "), "\n\n")

cat("=== 0) 원천 로드 (월당 1회 읽기, 푸시다운) ===\n")
t0 <- Sys.time()
FL <- rbindlist(lapply(seq_along(sig_dates), function(i) {
  d <- sig_dates[i]
  y <- tryCatch(load_month_factors(d, factor_names = SAMP), error = function(e) NULL)
  if (is.null(y) || !nrow(y)) return(NULL)
  y <- as.data.table(y)[is.finite(Z_Score_Aligned)]
  if (!nrow(y)) return(NULL)
  data.table(sig_date = as.Date(d), Ticker = as.character(y$Ticker),
             fac = as.character(y$Factor_Name), z = as.numeric(y$Z_Score_Aligned))
}), fill = TRUE)
cat(sprintf("  %d행 · %d팩터 · %d개월 · %.1f분\n", nrow(FL), uniqueN(FL$fac), uniqueN(FL$sig_date),
            as.numeric(difftime(Sys.time(), t0, units="mins"))))

## 두 스탬프 프레임의 forward return 을 각각 1회만 만든다
mk_frd <- function(stamp_fun) {
  dts <- sort(unique(stamp_fun(sig_dates)))
  as.data.table(build_monthly_forward_returns(raw, dts)$returns_dt)
}
frd_fix <- mk_frd(nextm)
frd_bad <- mk_frd(thism)

ic_by_fac <- function(frd, stamp_fun) {
  x <- copy(FL)[, Date := stamp_fun(sig_date)]
  m <- merge(x[, .(Date, Ticker, fac, z)], frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  ic <- m[, .(ic = if (.N >= 30L) suppressWarnings(stats::cor(z, Ret_1m, method="spearman")) else NA_real_),
          by = .(fac, Date)]
  ic[is.finite(ic), .(mean_ic = mean(ic), n = .N), by = fac]
}

cat("\n=== A) 위반 주입 — 자기 달 월초 스탬프(문서화된 결함)가 지문을 발화시키는가 ===\n")
A <- merge(ic_by_fac(frd_fix, nextm)[, .(fac, ic_fixed = mean_ic, n_fixed = n)],
           ic_by_fac(frd_bad, thism)[, .(fac, ic_broken = mean_ic, n_broken = n)], by = "fac")
A[, delta := ic_broken - ic_fixed]
print(A[order(delta)])
cat(sprintf("\n  |ic_broken| > 0.10 인 팩터: %d/%d · 최대 |ic_broken| = %.4f (%s)\n",
            A[abs(ic_broken) > 0.10, .N], nrow(A), max(abs(A$ic_broken)), A[which.max(abs(ic_broken)), fac]))
cat(sprintf("  |ic_fixed|  > 0.10 인 팩터: %d/%d · 최대 |ic_fixed|  = %.4f (%s)\n",
            A[abs(ic_fixed) > 0.10, .N], nrow(A), max(abs(A$ic_fixed)), A[which.max(abs(ic_fixed)), fac]))
cat("  ⇒ 결함 프레임이 |IC| 를 폭발시키면 지문 검사가 실제 검출력을 가진다는 뜻이다.\n")

cat("\n=== B) 승계 패널(lane_a_feature_panel) 원천 충실도 — 표본 ", length(SAMP), "종 ===\n", sep="")
x <- copy(FL)[, Date := nextm(sig_date)]
m <- merge(x[, .(Date, Ticker, fac, z)], frd_fix[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
ic_src <- m[, .(ic_src = if (.N >= 30L) suppressWarnings(stats::cor(z, Ret_1m, method="spearman")) else NA_real_),
            by = .(fac, Date)]
pl <- melt(pan[, c("anchor","Ticker", intersect(SAMP, featcols)), with = FALSE],
           id.vars = c("anchor","Ticker"), variable.name = "fac", value.name = "z")
pl <- merge(pl, pan[, .(anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)],
            by.x = c("anchor","Ticker"), by.y = c("anchor","Ticker"))
pl <- pl[is.finite(z) & is.finite(fwd)]
ic_pan <- pl[, .(ic_pan = if (.N >= 30L) suppressWarnings(stats::cor(z, fwd, method="spearman")) else NA_real_),
             by = .(fac = as.character(fac), Date = anchor)]
J <- merge(ic_src, ic_pan, by = c("fac","Date"))[is.finite(ic_src) & is.finite(ic_pan)]
FID <- J[, .(cor_ic = stats::cor(ic_src, ic_pan), n = .N,
             mean_src = mean(ic_src), mean_pan = mean(ic_pan)), by = fac]
print(FID[order(cor_ic)])
cat(sprintf("\n  cor >= 0.99 : %d/%d · 중앙 %.4f · 최소 %.4f\n",
            FID[cor_ic >= 0.99, .N], nrow(FID), median(FID$cor_ic), min(FID$cor_ic)))

cat("\n=== C) IC 프로파일 정상성 (승계 패널 전 320팩터, |평균 Spearman IC| > 0.10 개수 — 요구 0) ===\n")
LAST_COMPLETE <- as.Date("2026-07-01")
pw <- pan[anchor <= LAST_COMPLETE & is.finite(fwd_ret_1m)]
prof <- rbindlist(lapply(featcols, function(f) {
  x2 <- pw[[f]]; ok <- is.finite(x2)
  d2 <- data.table(anchor = pw$anchor[ok], z = x2[ok], fwd = pw$fwd_ret_1m[ok])
  ic <- d2[, .(ic = if (.N >= 30L) suppressWarnings(stats::cor(z, fwd, method="spearman")) else NA_real_), by = anchor]
  data.table(fac = f, mean_ic = mean(ic$ic, na.rm=TRUE), n_m = sum(is.finite(ic$ic)))
}))
cat(sprintf("  팩터 %d종 · |평균IC|>0.10 = %d종 · 최대 |평균IC| = %.4f (%s)\n",
            nrow(prof), prof[abs(mean_ic) > 0.10, .N], max(abs(prof$mean_ic), na.rm=TRUE),
            prof[which.max(abs(mean_ic)), fac]))
cat(sprintf("  M04_Mom_1 패널 평균IC = %+.4f · 원천 재산출 = %+.4f\n",
            prof[fac == "M04_Mom_1", mean_ic], FID[fac == "M04_Mom_1", mean_src]))
cat(sprintf("  패널 월수 %d (%s ~ %s) · 월중앙 종목 %d\n", uniqueN(pw$anchor), min(pw$anchor), max(pw$anchor),
            as.integer(median(pw[, .N, by = anchor]$N))))
saveRDS(list(inject = A, fidelity = FID, profile = prof, samp = SAMP), file.path(OUT, "p0b_frame_verify.rds"))
cat("\n[saved] p0b_frame_verify.rds\n")
