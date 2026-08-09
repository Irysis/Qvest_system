#!/usr/bin/env Rscript
# np_depth_response_surface_20260809.R — regime chain step 4 후속: 깊이-방어 반응면.
#
# ★step 4 실측: 바닥 0.70 이 방어를 **0 손실**로 유지하면서(ΔMDD +0.0207 = 통제와 동일)
#   IR 대가를 +0.115 줄였다. 최저 노출 0.387→0.700 인데 MDD 개선이 같다
#   ⇒ 깊은 축소는 순수 IR 손실이었다. 그렇다면 **어느 노출 수준에서 방어가 포화되는가?**
#
# ★★이것은 sweep 이 아니다 — **argmax 로 고르지 않는다.**
#   여러 바닥값을 재되 곡선 자체를 보고할 뿐이고, 어떤 값도 채택·권고하지 않는다.
#   (선택하지 않으면 selection operator 가 아니다 — measurement-graduation §3.)
#   ★이 곡선을 보고 나중에 바닥값을 고르면 **그때가 selection 이다** — 별도 사전등록 +
#     DSR≥0.5 HARD 게이트 대상이 된다. 본 산출물은 그 사전등록의 *입력*이지 판정이 아니다.
#   그래서 verdict/adopt 필드를 만들지 않는다(있으면 다음 사람이 판정으로 읽는다).
#
# 자본 판정 아님(metric_type=diagnostic). 배포 형태인 `× book` 스택으로 잰다.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")
Sys.setenv(QVEST_REGIME_AB_NORUN = "1", QVEST_WEIGHTING_AB_NORUN = "1")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ops/auto_weighting_ab.R")   # build_period_bench

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)
bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
W <- car[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
bare <- car[, .(r = sum((weight_strategy / sum(weight_strategy)) * ret_fwd)), by = .(Date = eval_date)]
setorder(bare, Date)
book_exp <- unique(car[, .(Date = eval_date, exposure = as.numeric(invested))])
say("캐리어 %d개월 · basis=%s", nrow(periods), mt$strategy)

# vol 스케줄 (step 4 어댑터와 동일: 12개월 sd, 홀딩월 M-2 까지)
VT_T <- 0.055; VT_W <- 12L
n <- nrow(periods); raw_exp <- rep(1.0, n)
for (i in seq_len(n)) {
  hi <- i - 2L; if (hi < VT_W) next
  s <- stats::sd(bare$r[(hi - VT_W + 1L):hi], na.rm = TRUE)
  if (is.finite(s) && s > 0) raw_exp[i] <- min(1.0, VT_T / s)
}
ep <- format(periods$decision_date, "%Y-%m") >= "2006-01" & format(periods$decision_date, "%Y-%m") <= "2006-06"

run_arm <- function(exp_vec, tag) {
  e <- if (is.null(exp_vec)) NULL else
       book_exp[data.table(Date = periods$eval_date, ex = exp_vec), on = "Date",
                .(Date, exposure = x.exposure * i.ex)]
  r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = 15,
                          run_id = tag, strategy_id = tag, exposure_dt = e)
  data.table(arm = tag, IR = r$information_ratio, abs_MDD = r$abs_mdd,
             abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr,
             mean_exp = if (is.null(e)) 1 else mean(e$exposure))
}

base <- run_arm(NULL, "book_only")
say("\n기준선 book_only: IR %.4f · MDD %.4f", base$IR, base$abs_MDD)

FLOORS <- c(0.00, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95, 1.00)
res <- rbindlist(lapply(FLOORS, function(f) {
  v <- pmax(f, raw_exp)
  out <- run_arm(v, sprintf("floor_%.2f", f))
  out[, `:=`(floor = f, min_exp_signal = min(v), fire_rate = mean(v < 1 - 1e-12),
             fire_2006 = mean(v[ep] < 1 - 1e-12))]
  out
}))
res[, `:=`(dIR = round(IR - base$IR, 4), dMDD = round(abs_MDD - base$abs_MDD, 4))]

say("\n=== 깊이-방어 반응면 (× book 스택, 271개월) ===")
print(res[, .(floor, min_exp_signal = round(min_exp_signal, 3), mean_exp = round(mean_exp, 4),
              IR = round(IR, 4), dIR, abs_MDD = round(abs_MDD, 4), dMDD,
              fire = round(fire_rate, 3), fire_2006 = round(fire_2006, 3))])

say("\n★읽는 법: dMDD > 0 = 낙폭 완화. floor 를 올려도 dMDD 가 유지되면 그 구간의 축소는 IR 만 깎은 것.")
say("★어떤 floor 도 채택·권고하지 않는다 — 이 표는 반응면 측정이고, 값 선택은 별도 사전등록 대상이다.")

out <- list(schema = "depth_response_surface_v1", date = "20260809", metric_type = "diagnostic",
            not_a_selection = "argmax 미수행. 값 선택 시 별도 사전등록 + DSR HARD 게이트 대상.",
            window_months = nrow(periods), carrier = mt$strategy,
            baseline = list(arm = "book_only", IR = round(base$IR, 4), abs_MDD = round(base$abs_MDD, 4)),
            surface = lapply(seq_len(nrow(res)), function(i)
              as.list(res[i, .(floor, mean_exp = round(mean_exp,4), IR = round(IR,4), dIR,
                               abs_MDD = round(abs_MDD,4), dMDD, fire_rate = round(fire_rate,3),
                               fire_2006 = round(fire_2006,3))])))
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/depth_response_surface_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/depth_response_surface_20260809.json")
