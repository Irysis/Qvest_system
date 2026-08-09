#!/usr/bin/env Rscript
# np1_mdd_episode_signals_20260809.R — regime 라운드 next_probe 1.
#
# 질문: 두 Hurst 팔의 ΔMDD 가 소수 4자리까지 동일(-0.1746)하고 bare(-0.1747)와 같다.
#       = **최대낙폭을 만드는 구간에서 어느 규칙도 발화하지 않았다**는 뜻이다.
#       그렇다면 그 구간에서 각 신호는 실제로 무엇이었나? 발화한 신호는 있나?
#
# 이건 "발화율" 가설이 기각된 뒤 남은 축 = **정렬(alignment)** 을 재료 수준에서 보는 것이다.
# 자본 판정 아님 — 진단(metric_type=diagnostic). 낙폭 구간 식별은 PerformanceAnalytics 표준함수만.
suppressMessages({ library(data.table); library(arrow); library(jsonlite)
                   library(xts); library(PerformanceAnalytics) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

# ── 1) 캐리어 → bare 월간 수익 + 북 노출 ─────────────────────────────────────
mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
M <- car[, .(bare = sum((weight_strategy / sum(weight_strategy)) * ret_fwd),
             invested = invested[1]), by = .(decision_date = decision_date, eval_date = eval_date)]
setorder(M, eval_date)
M[, hold_ym := format(decision_date, "%Y-%m")]
M[, book := bare * invested]
say("캐리어 %d개월 (%s ~ %s) · metric_type=diagnostic(gross, 배터리 권위 수치는 net)",
    nrow(M), min(M$hold_ym), max(M$hold_ym))

# ── 2) 낙폭 구간 식별 (PerformanceAnalytics 표준함수) ────────────────────────
x_bare <- xts(M$bare, order.by = M$eval_date)
x_book <- xts(M$book, order.by = M$eval_date)
td_bare <- table.Drawdowns(x_bare, top = 3)
td_book <- table.Drawdowns(x_book, top = 3)
say("\n=== bare 최대낙폭 3건 (PerformanceAnalytics::table.Drawdowns) ===")
print(td_bare)
say("\n=== book(오버레이 적용) 최대낙폭 3건 ===")
print(td_book)

ep_from <- as.Date(td_bare$From[1]); ep_to <- as.Date(td_bare$Trough[1])
say("\n★bare 최대낙폭 구간: %s ~ %s (%.1f%%)", as.character(ep_from), as.character(ep_to),
    100 * td_bare$Depth[1])

# ── 3) 그 구간에서 각 신호가 무엇이었나 ──────────────────────────────────────
src <- new.env(parent = globalenv())
Sys.setenv(QVEST_REGIME_AB_NORUN = "1")
sys.source("02_Infrastructure/methods/adapters/hurst_rate_matched_overlay.R", envir = src)
ctx <- list(periods = M[, .(decision_date, eval_date)], bare_gross = M[, .(Date = eval_date, r = bare)])
rm_out <- src$exposure_schedule(ctx)
src2 <- new.env(parent = globalenv())
sys.source("02_Infrastructure/methods/adapters/hurst_trend_overlay.R", envir = src2)
ht_out <- src2$exposure_schedule(ctx)

rg <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(ym = as.character(YM), Category = as.character(Category))]
prev_ym <- function(d) format(as.Date(format(as.Date(d), "%Y-%m-01")) - 1, "%Y-%m")
M[, ym_sig := prev_ym(decision_date)]
M[rg, on = c(ym_sig = "ym"), uni_cat := i.Category]

# trailing 12m 변동성 (PIT: 직전 12개월, 당월 제외)
M[, vol12 := shift(frollapply(bare, 12, sd, align = "right"), 1L)]
M[, voltgt_exp := pmin(1, 0.055 / vol12)]
M[!is.finite(voltgt_exp), voltgt_exp := 1]

M[, ht_exp := as.numeric(ht_out$exposure$exposure)]
M[, rm_exp := as.numeric(rm_out$exposure$exposure)]

EP <- M[eval_date >= ep_from & eval_date <= ep_to]
say("\n=== 낙폭 구간 %d개월 · 신호별 발화 현황 ===", nrow(EP))
print(EP[, .(hold_ym, bare = round(bare, 4), uni_cat,
             uni_fire = uni_cat %in% c("CRISIS", "CAUTION"),
             ht_fire = ht_exp < 1, rm_fire = rm_exp < 1,
             voltgt = round(voltgt_exp, 3), vt_fire = voltgt_exp < 0.95,
             book_inv = round(invested, 3))])

say("\n=== 발화율: 낙폭 구간 vs 전체 ===")
cmp <- data.table(
  signal   = c("unified(CRISIS/CAUTION)", "HurstTrendOverlay", "HurstRateMatched", "voltarget(<0.95)", "book invested(<0.95)"),
  in_mdd   = c(mean(EP$uni_cat %in% c("CRISIS", "CAUTION")), mean(EP$ht_exp < 1),
               mean(EP$rm_exp < 1), mean(EP$voltgt_exp < 0.95), mean(EP$invested < 0.95)),
  overall  = c(mean(M$uni_cat %in% c("CRISIS", "CAUTION"), na.rm = TRUE), mean(M$ht_exp < 1),
               mean(M$rm_exp < 1), mean(M$voltgt_exp < 0.95), mean(M$invested < 0.95)))
cmp[, lift := round(in_mdd / overall, 3)]
cmp[, `:=`(in_mdd = round(in_mdd, 3), overall = round(overall, 3))]
print(cmp)
say("\n★lift > 1 = 낙폭 구간에서 더 자주 발화(정렬됨) · lift < 1 = 오히려 덜 발화(역정렬)")

out <- list(schema = "np1_mdd_episode_signals_v1", date = "20260809",
            metric_type = "diagnostic",
            note = "낙폭 구간 식별 = PerformanceAnalytics::table.Drawdowns(gross). 배터리 권위 MDD 는 net(weighted_screen_bt).",
            episode = list(from = as.character(ep_from), trough = as.character(ep_to),
                           depth = round(td_bare$Depth[1], 4), n_months = nrow(EP)),
            firing = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i])))
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/np1_mdd_episode_signals_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/np1_mdd_episode_signals_20260809.json")
