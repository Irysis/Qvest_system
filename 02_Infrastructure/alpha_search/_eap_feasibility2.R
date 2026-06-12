# =============================================================================
# _eap_feasibility2.R — EAP 2차 점검: PIT '예상공시' 포트 규모 + 분할 안정성
# =============================================================================
# 1차에서 FEASIBLE(공시집중월 비공시 20.8%)이나 경계선. 핵심 추가 검증:
#   (a) 실제 전략이 쓰는 PIT 예측("전년 동일분기 보고서의 접수월" → 다음달 공시예상)
#       으로 분할 시, 매월 '예상공시 long 포트'가 백테 가능한 규모(>=8~10종목)인가.
#   (b) off-season(공시 비집중월) 에 예상공시 포트가 붕괴(<5종목)하는가 → 백테 불가월.
#   (c) 예상공시 vs 비공시 분할이 매월 양쪽 다 유의미 규모로 공존하는 달이 몇 %인가.
# PIT: 예측은 t 시점 가관측(전년 접수월 이력)만. 미래 누설 없음.
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/alpha_search/run_alpha_search.R")

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
RAWDATA[, .ym := format(Date, "%Y-%m")]
MEND <- RAWDATA[, .(Date = max(Date)), by = .ym][order(Date)]
UNI <- unique(RAWDATA[Date %in% MEND$Date & (K200 == TRUE | KQ150 == TRUE), .(ym = .ym, Ticker)])

dcp <- file.path(ROOT, ".cache", "dart", "dart_raw_quarterly.parquet")
D <- as.data.table(read_parquet(dcp, col_select = c("rcept_no","reprt_code","bsns_year","Ticker")))
FIL <- unique(D[, .(rcept_no, reprt_code, bsns_year, Ticker)]); rm(D); gc(verbose=FALSE)
FIL[, rcept_date := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
FIL <- FIL[!is.na(rcept_date)]
FIL[, rym := format(rcept_date, "%Y-%m")]
FIL[, ryr := as.integer(substr(rym,1,4))]
FIL[, rmon := as.integer(substr(rym,6,7))]
FIL <- FIL[Ticker %in% unique(UNI$Ticker)]

# ---- PIT 예측: 종목 i, 보고서종류 rc 가 전년(ryr-1) 동일 rc 를 접수한 '월' ----
#   → 올해 같은 rc 를 그 월(또는 ±1)에 공시할 것으로 예측. (전년 패턴, t 시점 가관측)
hist <- unique(FIL[, .(Ticker, reprt_code, ryr, rmon)])
hist[, pred_yr := ryr + 1L]   # 전년 패턴 → 다음해 예측
setnames(hist, "rmon", "pred_mon")
pred <- hist[, .(Ticker, reprt_code, pred_yr, pred_mon)]
# 예측 (year, month, Ticker): 그 달에 '예상공시'
pred[, pred_ym := sprintf("%04d-%02d", pred_yr, pred_mon)]
pred_set <- unique(pred[, .(ym = pred_ym, Ticker, pred_ann = 1L)])

# 유니버스 결합 → 월별 예상공시/비공시 분할
SP <- merge(UNI[, .(ym, Ticker)], pred_set, by = c("ym","Ticker"), all.x = TRUE)
SP[is.na(pred_ann), pred_ann := 0L]
SP[, yr := as.integer(substr(ym,1,4))]
SP[, cmon := as.integer(substr(ym,6,7))]
mo <- SP[yr >= 2016, .(uni_n = .N, pann_n = sum(pred_ann), non_n = sum(pred_ann==0L)), by = .(ym, yr, cmon)][order(ym)]
mo[, pann_pct := round(100*pann_n/uni_n,1)]

cat("=== [EAP-FEAS2] PIT 예상공시 포트 규모 (2016~) ===\n")
cat(sprintf("월수=%d | 예상공시 종목수: 중앙값=%d min=%d max=%d\n",
            nrow(mo), as.integer(median(mo$pann_n)), min(mo$pann_n), max(mo$pann_n)))

# (a) 백테 가능 규모: 예상공시 >= 10종목인 월 비율
ok10 <- round(100*mean(mo$pann_n >= 10),1)
ok8  <- round(100*mean(mo$pann_n >= 8),1)
collapse5 <- round(100*mean(mo$pann_n < 5),1)
cat(sprintf("예상공시 >=10종목 월 비율 = %.1f%% | >=8 = %.1f%% | <5(붕괴) = %.1f%%\n", ok10, ok8, collapse5))

# (b) 양쪽 공존: 예상공시>=10 AND 비공시>=10% 인 월 비율
both <- round(100*mean(mo$pann_n >= 10 & (mo$non_n/mo$uni_n) >= 0.10),1)
cat(sprintf("예상공시>=10 AND 비공시>=10%% 공존 월 비율 = %.1f%%\n", both))

# 캘린더 월별 예상공시 규모
cm <- mo[, .(mean_pann_n = round(mean(pann_n),1), mean_pann_pct = round(mean(pann_pct),1),
             med_pann_n = as.integer(median(pann_n)), n_mo=.N), by = cmon][order(cmon)]
cat("\n[EAP-FEAS2] 캘린더 월별 예상공시 포트 규모 (2016~):\n")
print(cm)

# 예측 정확도(진단): 예상공시한 종목이 실제 그 달 ±1 공시했나
real <- unique(FIL[, .(ym = rym, Ticker, real_ann = 1L)])
acc <- merge(pred_set[, .(ym, Ticker)], real, by = c("ym","Ticker"), all.x = TRUE)
acc[is.na(real_ann), real_ann := 0L]
hit_rate <- round(100*mean(acc$real_ann),1)
cat(sprintf("\n[EAP-FEAS2] PIT 예측 적중률(예상공시→실제 동월 공시) = %.1f%% (진단)\n", hit_rate))

# 종합 판정
cat("\n=== [EAP-FEAS2] 종합 ===\n")
feas2 <- ok10 >= 70 && both >= 50 && collapse5 <= 20
cat(sprintf("백테가능성 기준: 예상공시>=10 월 %.1f%%(>=70?) AND 공존 %.1f%%(>=50?) AND 붕괴 %.1f%%(<=20?)\n",
            ok10, both, collapse5))
cat(sprintf("[EAP-FEAS2] 2차 백테가능성 = %s\n", if(feas2) "PASS" else "MARGINAL/FAIL"))

saveRDS(list(ok10=ok10, ok8=ok8, collapse5=collapse5, both=both, hit_rate=hit_rate,
             med_pann_n=median(mo$pann_n), cm=cm, feas2=feas2),
        "02_Infrastructure/alpha_search/_eap_feasibility2_result.rds")
cat(sprintf("FEAS2=%s OK10=%.1f BOTH=%.1f COLLAPSE5=%.1f HIT=%.1f\n",
            if(feas2)"PASS" else "MARGINAL", ok10, both, collapse5, hit_rate))
