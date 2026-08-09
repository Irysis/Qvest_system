#!/usr/bin/env Rscript
# np2_book_binding_dd_20260809.R — regime 라운드 next_probe 2.
#
# 배경(np1 부수 발견): bare 최대낙폭은 GFC(2008-07~2009-03, -39.8%)인데
#   **북(오버레이 적용) 최대낙폭은 2006-02~07 (-22.7%)** 로 다른 구간이다.
#   북 오버레이가 GFC 를 실제로 방어했고(invested 0.227~0.378, 8/9 발화), 그 결과
#   **구속 낙폭이 오버레이가 방어하지 못한 구간으로 이동**했다.
#   ⇒ 잔여 MDD 레버를 찾으려면 GFC 가 아니라 **거기**를 봐야 한다.
#
# 질문 2개:
#   Q1. 북 구속 낙폭 구간에서 각 신호는 발화했나? (아무도 안 하면 그게 미탐색 면)
#   Q2. voltgt_x_book 이 유일하게 ΔMDD +0.0171 를 낸 것이 이 구간 덕인가?
# 자본 판정 아님(metric_type=diagnostic). 낙폭 구간 식별 = PerformanceAnalytics 표준함수.
suppressMessages({ library(data.table); library(arrow); library(jsonlite)
                   library(xts); library(PerformanceAnalytics) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
M <- car[, .(bare = sum((weight_strategy / sum(weight_strategy)) * ret_fwd),
             invested = invested[1]), by = .(decision_date, eval_date)]
setorder(M, eval_date)
M[, hold_ym := format(decision_date, "%Y-%m")]
M[, book := bare * invested]

# 신호들
src  <- new.env(parent = globalenv()); sys.source("02_Infrastructure/methods/adapters/hurst_trend_overlay.R", envir = src)
src2 <- new.env(parent = globalenv()); sys.source("02_Infrastructure/methods/adapters/hurst_rate_matched_overlay.R", envir = src2)
ctx <- list(periods = M[, .(decision_date, eval_date)], bare_gross = M[, .(Date = eval_date, r = bare)])
M[, ht_exp := as.numeric(src$exposure_schedule(ctx)$exposure$exposure)]
M[, rm_exp := as.numeric(src2$exposure_schedule(ctx)$exposure$exposure)]
rg <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(ym = as.character(YM), Category = as.character(Category))]
M[, ym_sig := format(as.Date(format(decision_date, "%Y-%m-01")) - 1, "%Y-%m")]
M[rg, on = c(ym_sig = "ym"), uni := i.Category]
M[, vol12 := shift(frollapply(bare, 12, sd, align = "right"), 1L)]
M[, voltgt_exp := pmin(1, 0.055 / vol12)]; M[!is.finite(voltgt_exp), voltgt_exp := 1]

td <- table.Drawdowns(xts(M$book, order.by = M$eval_date), top = 3)
say("=== 북(오버레이 적용) 최대낙폭 3건 ===" ); print(td)
ep_from <- as.Date(td$From[1]); ep_to <- as.Date(td$Trough[1])
say("\n★북 구속 낙폭: %s ~ %s (%.1f%%)", as.character(ep_from), as.character(ep_to), 100 * td$Depth[1])

EP <- M[eval_date >= ep_from & eval_date <= ep_to]
say("\n=== 구간 %d개월 · 신호 현황 ===", nrow(EP))
print(EP[, .(hold_ym, bare = round(bare, 4), book = round(book, 4), uni,
             uni_fire = uni %in% c("CRISIS", "CAUTION"), ht_fire = ht_exp < 1, rm_fire = rm_exp < 1,
             voltgt = round(voltgt_exp, 3), vt_fire = voltgt_exp < 0.95, book_inv = round(invested, 3))])

sig <- c("unified", "HurstTrendOverlay", "HurstRateMatched", "voltarget", "book_invested")
inm <- c(mean(EP$uni %in% c("CRISIS","CAUTION")), mean(EP$ht_exp < 1), mean(EP$rm_exp < 1),
         mean(EP$voltgt_exp < 0.95), mean(EP$invested < 0.95))
ovr <- c(mean(M$uni %in% c("CRISIS","CAUTION"), na.rm = TRUE), mean(M$ht_exp < 1), mean(M$rm_exp < 1),
         mean(M$voltgt_exp < 0.95), mean(M$invested < 0.95))
cmp <- data.table(signal = sig, in_dd = round(inm, 3), overall = round(ovr, 3), lift = round(inm / ovr, 3))
say("\n=== 발화율: 북 구속 낙폭 구간 vs 전체 ===" ); print(cmp)

# Q2: voltgt 가 이 구간에서 실제로 낙폭을 줄이나 — 구간 내 누적 대조(진단)
EP2 <- copy(EP)[, `:=`(book_vt = book * voltgt_exp)]
say("\n=== Q2 · 구간 내 누적(진단, 단순 곱 아님 — Return.cumulative) ===")
cum <- function(x) as.numeric(Return.cumulative(xts(x, order.by = EP2$eval_date)))
say("  book 그대로        : %+.4f", cum(EP2$book))
say("  book × voltarget   : %+.4f  (차이 %+.4f)", cum(EP2$book_vt), cum(EP2$book_vt) - cum(EP2$book))
say("  평균 voltgt 노출    : %.3f", mean(EP2$voltgt_exp))

out <- list(schema = "np2_book_binding_dd_v1", date = "20260809", metric_type = "diagnostic",
            episode = list(from = as.character(ep_from), trough = as.character(ep_to),
                           depth = round(td$Depth[1], 4), n_months = nrow(EP)),
            firing = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i])),
            q2_voltarget = list(book = round(cum(EP2$book), 4), book_x_voltgt = round(cum(EP2$book_vt), 4),
                                mean_exposure = round(mean(EP2$voltgt_exp), 3)))
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/np2_book_binding_dd_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/np2_book_binding_dd_20260809.json")
