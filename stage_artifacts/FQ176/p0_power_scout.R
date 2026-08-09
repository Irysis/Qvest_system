## FQ-176 P0 — ★내 등재 문구("검정력이 수만으로 회복") 자체를 먼저 검증
## 혐의: 조건부 IC 는 **월별 계열**이라 유효표본 n = ON 개월수이지 종목수가 아니다.
##       종목수가 늘리는 것은 n 이 아니라 **월별 IC 의 정밀도(sd 감소)** 다.
## 이 구분이 틀리면 FQ-176 설계 전체가 무효 — 착수 전 확정.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")

## ---- 1. 기존 패널로 월별 IC 의 실제 sd 를 실측 -------------------------------
W <- readRDS(file.path(ROOT, "stage_artifacts/FQ169/panel.rds"))
W <- W[is.na(adv) | adv >= 2e8]
say("=== 1. 입력 실측 === %d행 · %d개월 · %s ~ %s", nrow(W), uniqueN(W$Date), min(W$Date), max(W$Date))
fcols <- setdiff(names(W), c("Date","Ticker","Ret_1m","adv"))
say("  팩터 %d종: %s", length(fcols), paste(fcols, collapse=", "))

ic_series <- function(k) {
  D <- W[!is.na(get(k)) & !is.na(Ret_1m)]
  D[, .(ic = suppressWarnings(cor(get(k), Ret_1m, method="spearman")), n = .N), by = Date][!is.na(ic)]
}
S <- rbindlist(lapply(fcols, function(k) {
  I <- ic_series(k)
  data.table(factor = k, n_months = nrow(I), ic_mean = mean(I$ic), ic_sd = sd(I$ic),
             avg_n_stock = mean(I$n))
}))
say("=== 2. 월별 rank-IC 의 실측 sd (검정력의 진짜 재료) ===")
print(S[, .(factor, n_months, avg_n_stock = round(avg_n_stock), ic_mean = round(ic_mean,4),
            ic_sd = round(ic_sd,4))])
say("  ★월별 IC sd 중앙값 = %.4f (종목수 중앙 %.0f)", median(S$ic_sd), median(S$avg_n_stock))

## ---- 2. 종목수가 IC sd 를 실제로 줄이는가 — 직접 실측 -------------------------
say("=== 3. ★종목수 ↔ IC 정밀도 관계 실측 (주장이 아니라 측정) ===")
k <- "M26_Revenue_Mom"
D <- W[!is.na(get(k)) & !is.na(Ret_1m)]
set.seed(42)
for (m in c(30L, 60L, 120L, 240L)) {
  ics <- D[, {
    if (.N < m) .(ic = NA_real_) else {
      idx <- sample.int(.N, m)
      .(ic = suppressWarnings(cor(get(k)[idx], Ret_1m[idx], method="spearman")))
    }
  }, by = Date]$ic
  ics <- ics[!is.na(ics)]
  say("  월별 %3d종목 표본: IC sd %.4f (n_month %d)", m, sd(ics), length(ics))
}
full_sd <- sd(ic_series(k)$ic)
say("  월별 전체(중앙 %.0f종목):  IC sd %.4f", median(ic_series(k)$n), full_sd)
say("  ★해석: 종목수가 늘면 IC sd 가 준다 = **월별 관측의 정밀도**가 오른다.")
say("    그러나 유효표본 n 은 여전히 **개월수**다. 내 FQ-176 등재 문구 '수만' 은 부정확하다 — 정정 대상.")

## ---- 3. 조건부 IC 검정의 진짜 바 --------------------------------------------
say("=== 4. ★조건부 ΔIC 검정의 필요 효과 (착수 자격 판정) ===")
ic_sd <- median(S$ic_sd)
say("  기준 IC sd = %.4f · 무조건부 IC 평균 범위 %.4f ~ %.4f", ic_sd, min(S$ic_mean), max(S$ic_mean))
say("  n_ON   n_OFF   필요ΔIC(t=2)   무조건부 IC 대비 배수")
for (n_on in c(31L, 34L, 61L, 69L, 80L, 160L)) {
  n_off <- 282L - n_on
  se <- ic_sd * sqrt(1/n_on + 1/n_off) * 1.25
  req <- 2.0 * se
  say("  %4d   %5d   %12.4f   %.2fx (평균 IC 0.0179 기준)", n_on, n_off, req, req/0.0179)
}
say("  ★대조: P4 수익-기반 검정은 필요 효과가 연 24.6~87.7%% 였다(관측 4.7~23.4%%, 전건 미달).")
say("    IC 기반은 필요 ΔIC 가 무조건부 IC 의 몇 배인지로 읽는다 — 2배 이하면 현실적 범위다.")

saveRDS(list(ic_summary = S, ic_sd_median = ic_sd), file.path(OUT, "p0_power.rds"))
say("=== P0 완료 ===")
