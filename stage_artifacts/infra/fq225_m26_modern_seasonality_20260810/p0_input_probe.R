## =============================================================================
## FQ-225/226 [P0] 입력 실측 — 판정량 산출 전, 구조만 확인한다.
## 규약: 측정 첫 출력 = 입력 실측(행수·관측단위·범위). 가정하고 재기 시작 금지.
## 이 스크립트는 사전등록 문턱을 정하기 위한 **구조 정보**만 뽑는다(효과크기·t 미산출).
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
say <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }

D4 <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
say("판정 패널 %d행", nrow(D4))
say("컬럼: %s", paste(names(D4), collapse = ", "))
say("관측단위 후보 — 고유 signal_ym %d · 고유 Date %d · 고유 Ticker %d",
    uniqueN(D4$signal_ym), uniqueN(D4$Date), uniqueN(D4$Ticker))
say("signal_ym 범위 %s ~ %s · Date 범위 %s ~ %s",
    min(D4$signal_ym), max(D4$signal_ym), min(as.Date(D4$Date)), max(as.Date(D4$Date)))
say("월당 평균 종목 %.1f (최소 %d · 최대 %d)",
    nrow(D4)/uniqueN(D4$signal_ym),
    min(D4[, .N, by=signal_ym]$N), max(D4[, .N, by=signal_ym]$N))

FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")
for (f in c(FACS, "Ret_1m")) {
  x <- D4[[f]]
  say("  %-18s 유한 %6d/%6d (%.3f) · 중앙 %+.5f · sd %.5f",
      f, sum(is.finite(x)), length(x), mean(is.finite(x)), median(x, na.rm=TRUE), sd(x, na.rm=TRUE))
}

## 연도별 월수 + 유효 관측수 (구성 변화 진단의 입력)
D4[, yr := as.integer(substr(signal_ym, 1, 4))]
cc <- D4[complete.cases(D4[, .(C01_SUE,C02_EPS_Chg_1m,C04_ESBR,M26_Revenue_Mom,Ret_1m)])]
yb <- merge(D4[, .(n_rows=.N, n_months=uniqueN(signal_ym)), by=yr],
            cc[, .(n_cc=.N, n_months_cc=uniqueN(signal_ym)), by=yr], by="yr", all.x=TRUE)
yb[is.na(n_cc), `:=`(n_cc=0L, n_months_cc=0L)][, cc_frac := n_cc/n_rows]
say("--- 연도별 커버리지 ---")
for (i in seq_len(nrow(yb))) with(yb[i], say("  %d  행 %6d · 완전케이스 %6d (%.3f) · 월 %2d/%2d", yr, n_rows, n_cc, cc_frac, n_months_cc, n_months))

## 현대 구간 후보 월수 (2017-01 이후) — 검정력 선판정 입력
mm_all <- sort(unique(cc$signal_ym))
n_modern <- sum(mm_all >= "2017-01"); n_early <- sum(mm_all < "2017-01")
say("★완전케이스 월수 총 %d = 초기(<2017-01) %d + 현대(>=2017-01) %d", length(mm_all), n_early, n_modern)
say("★월당 최소 30종목 필터 후 월수 = %d", nrow(cc[, .N, by=signal_ym][N>=30L]))

## 달력 월별 관측 연수 (B 축 검정력 입력)
cc[, mon := substr(signal_ym, 6, 7)]
mo <- cc[, .(n_years = uniqueN(signal_ym)), by = mon][order(mon)]
say("--- 달력 월별 연수 (B축 표본) ---  %s", paste(sprintf("%s:%d", mo$mon, mo$n_years), collapse=" "))

fwrite(yb, file.path(OUT, "p0_coverage_by_year.csv"))
fwrite(mo, file.path(OUT, "p0_month_sample.csv"))
saveRDS(list(n_modern=n_modern, n_early=n_early, n_total=length(mm_all), yb=yb, mo=mo),
        file.path(OUT, "p0_probe.rds"))
say("저장 완료 → %s", OUT)
