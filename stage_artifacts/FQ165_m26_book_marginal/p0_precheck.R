## ============================================================================
## FQ-165 P0 — 입력 실측 + 기준선 parity + 직교성 사전확인 + 검정력 바
## ★측정 전 실행. 사전등록은 이 결과를 보고 확정한다(설계 확정 전 단계).
## 규율: 첫 출력 = 입력 실측(행수·관측단위·범위). 손으로 적은 수치 금지.
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)
                  library(PerformanceAnalytics); library(xts)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
source("02_Infrastructure/contracts/required_effect_size.R")

cat("================ [A] 입력 실측 (선언 대조 전) ================\n")

## --- A1. base sleeve score panel (production forward/recompute 가 읽는 그 파일) ---
BASE_PANEL <- "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
ap <- as.data.table(read_parquet(BASE_PANEL)); ap[, Date := as.Date(Date)]
cat(sprintf("[A1] base panel  %s\n", BASE_PANEL))
cat(sprintf("     rows=%d · cols=%s\n", nrow(ap), paste(names(ap), collapse=",")))
cat(sprintf("     unique Date=%d · range %s ~ %s · unique Ticker=%d\n",
            uniqueN(ap$Date), min(ap$Date), max(ap$Date), uniqueN(ap$Ticker)))
cat(sprintf("     score_eff non-NA=%d · 관측단위=(Date x Ticker) 중복행 %d\n",
            sum(!is.na(ap$score_eff)), sum(duplicated(ap[, .(Date, Ticker)]))))

## --- A2. M26 score panel (WT-002 산출 — 재구현 금지, 승계) ---
M26_PANEL <- "stage_artifacts/WT_D20260808_002/alpha_scores.parquet"
m26 <- as.data.table(read_parquet(M26_PANEL)); m26[, Date := as.Date(Date)]
cat(sprintf("\n[A2] M26 panel   %s\n", M26_PANEL))
cat(sprintf("     rows=%d · cols=%s\n", nrow(m26), paste(names(m26), collapse=",")))
cat(sprintf("     unique Date=%d · range %s ~ %s · unique Ticker=%d\n",
            uniqueN(m26$Date), min(m26$Date), max(m26$Date), uniqueN(m26$Ticker)))
cat(sprintf("     중복행(Date x Ticker)=%d\n", sum(duplicated(m26[, .(Date, Ticker)]))))
print(head(m26, 3))

## --- A3. 캐리어(오버레이 실측 — 북 정체성 권위) ---
CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"
car <- as.data.table(read_parquet(CARRIER)); car[, decision_date := as.Date(decision_date)]
cat(sprintf("\n[A3] carrier     %s\n", CARRIER))
cat(sprintf("     rows=%d · cols=%s\n", nrow(car), paste(names(car), collapse=",")))
cat(sprintf("     months=%d · range %s ~ %s\n", uniqueN(car$decision_date),
            min(car$decision_date), max(car$decision_date)))
bs <- fromJSON("qepm/mailbox/governor/book_state.json")
cat(sprintf("     book_state admitted_ids=%s · incumbent_book_ir=%.4f · ir_convention=%s\n",
            paste(bs[["admitted_ids"]], collapse=","), bs[["incumbent_book_ir"]], bs[["ir_convention"]]))
cat(sprintf("     carrier_meta.strategy=%s  → 정체성 일치: %s\n",
            fromJSON("06_Registry/book_carrier/carrier_meta.json")$strategy,
            identical(fromJSON("06_Registry/book_carrier/carrier_meta.json")$strategy,
                      bs[["admitted_ids"]][1])))

## --- A4. rawdata (일간! 월간 아님 — 2026-08-08 실사고 재발방지) ---
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                  col_select = c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw[, TV := Close*Vol]; setkey(raw, Date, Ticker)
cat(sprintf("\n[A4] rawdata     rows=%d · unique Date=%d · 관측단위=DAILY · range %s ~ %s\n",
            nrow(raw), uniqueN(raw$Date), min(raw$Date), max(raw$Date)))

## --- A5. 벤치 (vintage pin) ---
BM_PIN <- "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet"
bm <- as.data.table(read_parquet(BM_PIN)); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
cat(sprintf("[A5] benchmark   %s · rows=%d · range %s ~ %s (IKS200 pinned 20260702)\n",
            BM_PIN, nrow(bm), min(bm$Date), max(bm$Date)))

## --- A6. 교집합 (측정 가능 창) ---
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))
ovl <- unique(car[, .(decision_date, invested)]); setkey(ovl, decision_date)
common <- intersect(as.character(sig_dates), as.character(ovl$decision_date))
m26_dates <- sort(unique(m26[!is.na(Date), Date]))
common_m26 <- intersect(common, as.character(m26_dates))
cat(sprintf("\n[A6] base sig_dates=%d · overlay months=%d · base∩overlay=%d · ∩M26=%d\n",
            length(sig_dates), nrow(ovl), length(common), length(common_m26)))
cat(sprintf("     측정 창 = %s ~ %s\n", min(common_m26), max(common_m26)))

saveRDS(list(ap=ap, m26=m26, car=car, raw=raw, bm=bm, ovl=ovl, sig_dates=sig_dates),
        file.path(OUT, "p0_inputs.rds"))
cat("\n[saved] p0_inputs.rds\n")
