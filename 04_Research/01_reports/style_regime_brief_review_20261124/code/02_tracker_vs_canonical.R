## 02_tracker_vs_canonical.R — 브리핑 FF5 트래커(outputs/ff5_kr) 대 한국 FF 요인 정본(build_kr_factor_returns.R v1.1)
##   같은 실현월끼리 상관 · 부호 일치율 · 12개월 평균 부호 일치율. 정본 = 현 측정 축(all_hyg_px1000_2000_v1) · 일간 + 월간.
##   입력 = 스크래치 사본(아침 산출물 · 08:38 정본) — 팩터 DB · 재무 캐시는 읽지 않는다.
suppressMessages({ library(arrow); library(data.table) })
args <- commandArgs(trailingOnly = TRUE)
SNAP <- args[1]; OUT <- args[2]
TR <- as.data.table(read_parquet(file.path(SNAP, "ff5_kr_monthly.parquet")))
CA <- as.data.table(read_parquet(file.path(SNAP, "kr_factor_returns_v2.parquet")))
CA[, ym := sprintf("%s-%s", substr(ym, 1, 4), substr(ym, 5, 6))]
f <- c("MKT", "SMB", "HML", "RMW", "CMA")
j <- merge(TR[, c("ym", f), with = FALSE], CA[, c("ym", f, "SMB5", "WML"), with = FALSE], by = "ym", suffixes = c("_tr", "_ca"))
cat(sprintf("공통 실현월 %d개 (%s~%s)\n", nrow(j), min(j$ym), max(j$ym)))
r12 <- function(x) frollmean(x, 12)
rows <- rbindlist(lapply(f, function(k) {
  a <- j[[paste0(k, "_tr")]]; b <- j[[paste0(k, "_ca")]]
  ok <- is.finite(a) & is.finite(b)
  ra <- r12(a); rb <- r12(b); ok12 <- is.finite(ra) & is.finite(rb)
  data.table(factor = k, n = sum(ok), cor_monthly = round(cor(a[ok], b[ok]), 3),
             sign_agree_monthly = round(mean(sign(a[ok]) == sign(b[ok])), 3),
             cor_r12 = round(cor(ra[ok12], rb[ok12]), 3),
             sign_agree_r12 = round(mean(sign(ra[ok12]) == sign(rb[ok12])), 3),
             cor_r12_2016plus = round(cor(ra[ok12 & j$ym >= "2016-01"], rb[ok12 & j$ym >= "2016-01"]), 3),
             sign_agree_r12_2016plus = round(mean(sign(ra[ok12 & j$ym >= "2016-01"]) == sign(rb[ok12 & j$ym >= "2016-01"])), 3))
}))
print(rows)
## 트래커 SMB 는 FF2015 3-정렬 평균 → 정본 SMB5 와도 대조
ok <- is.finite(j$SMB_tr) & is.finite(j$SMB5)
cat(sprintf("\nSMB 트래커 대 정본 SMB5: cor %.3f · 부호 일치 %.3f\n", cor(j$SMB_tr[ok], j$SMB5[ok]), mean(sign(j$SMB_tr[ok]) == sign(j$SMB5[ok]))))
## 정본 안의 HML-CMA 상관(정상 부호 확인용)
cat(sprintf("정본 cor(HML, CMA) = %.3f · 트래커 cor(HML, CMA) = %.3f\n",
            cor(CA$HML, CA$CMA, use = "complete.obs"), cor(TR$HML, TR$CMA, use = "complete.obs")))
cat(sprintf("트래커 CMA 대 정본 −CMA: cor %.3f\n", cor(j$CMA_tr, -j$CMA_ca, use = "complete.obs")))
fwrite(rows, file.path(OUT, "tracker_vs_canonical.csv"))
## 최근 12개월 표(발송 판독과 직접 비교)
cat("\n[최근 14개월 · 트래커 대 정본]\n")
print(tail(j[, .(ym, SMB_tr = round(SMB_tr, 4), SMB_ca = round(SMB_ca, 4), HML_tr = round(HML_tr, 4), HML_ca = round(HML_ca, 4),
                 RMW_tr = round(RMW_tr, 4), RMW_ca = round(RMW_ca, 4), CMA_tr = round(CMA_tr, 4), CMA_ca = round(CMA_ca, 4))], 14))
