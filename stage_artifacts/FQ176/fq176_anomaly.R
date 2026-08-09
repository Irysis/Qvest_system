## FQ176 이상치 2건 정체 확인
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/FQ176")
say <- function(fmt, ...) cat(sprintf(paste0("[an] ", fmt, "\n"), ...))

PN <- readRDS(file.path(OUT, "panel_full.rds"))

say("=== 1. CR02_Volume_Concentration vs L03_Volume_Mom (ic 동일) ===")
a <- PN$CR02_Volume_Concentration; b <- PN$L03_Volume_Mom
say("  동일 결측패턴: %s", identical(is.na(a), is.na(b)))
ok <- !is.na(a) & !is.na(b)
say("  값 최대 절대차: %.3e · 완전동일: %s · corr %.6f",
    max(abs(a[ok]-b[ok])), isTRUE(all.equal(a[ok], b[ok])), cor(a[ok], b[ok]))
say("  -> 두 팩터는 %s", ifelse(max(abs(a[ok]-b[ok])) < 1e-12,
    "수치적으로 동일 시리즈(중복 등재 의심)", "다른 시리즈"))

say("=== 2. XF_LL01_DebtToCapital: n_mo 195 (비결측 99.4%%) 정체 ===")
D <- PN[!is.na(XF_LL01_DebtToCapital), .(Date, z = XF_LL01_DebtToCapital, r = Ret_1m)]
M <- D[, .(n = .N, sd_z = sd(z), n_uniq = uniqueN(z)), by = Date][order(Date)]
say("  비결측 월 %d · n>=30 인 월 %d · sd_z==0 인 월 %d · n_uniq==1 인 월 %d",
    nrow(M), sum(M$n >= 30), sum(M$sd_z == 0, na.rm = TRUE), sum(M$n_uniq == 1))
bad <- M[sd_z == 0 | n_uniq == 1]
if (nrow(bad)) say("  상수 월 기간: %s ~ %s (%d개월)", format(min(bad$Date)), format(max(bad$Date)), nrow(bad))
say("  -> IC 산출 %d개월 = 비결측월 %d − 상수월 %d", sum(M$n>=30) - nrow(bad), sum(M$n>=30), nrow(bad))

say("=== 3. 다른 팩터 상수월 점검 (n_mo < 282 전건) ===")
IC <- readRDS(file.path(OUT, "ic_series.rds"))
ST <- IC[, .(n_mo = .N), by = factor][n_mo < 282][order(n_mo)]
FN <- setdiff(names(PN), c("Date","Ticker","Ret_1m","adv"))
for (f in ST$factor) {
  Dd <- PN[!is.na(get(f)), .(n = .N, sd_z = sd(get(f))), by = Date]
  say("  %-30s n_mo %3d · 비결측월 %3d · n<30 월 %2d · 상수월 %2d",
      f, ST[factor==f, n_mo], nrow(Dd), sum(Dd$n < 30), sum(Dd$sd_z == 0, na.rm=TRUE))
}
