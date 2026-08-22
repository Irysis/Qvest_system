## postlock_controls.R — WT-D20260821_002
## (1) F0 paired t 재현 = **사후 양성 대조**. F0 는 사다리 후보가 아니라 축1 의 분모/기준선이고,
##     바인딩 프레임은 gate_lock.json 으로 이미 고정된 뒤이므로 프레임 선택에 영향 불가.
##     선행 라운드 공표치(armB −1.25 · armC +0.0876) 재현 여부를 확인한다.
## (2) 랭크-기울기 진단을 **정확히 198개월 paired 창**으로 재산출 + gross/net 채널 분리.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("stage_artifacts/WT-D20260821_002/frame_lib.R")
OUT <- "stage_artifacts/WT-D20260821_002"
S <- readRDS(file.path(OUT, "step0_inputs.rds")); GS <- readRDS(file.path(OUT, "gate_series.rds"))
VF <- readRDS(file.path(OUT, "verdict_full.rds"))
frd <- S$frd
sc <- list(armA = S$panels$armA[, .(Date, Ticker, score = as.numeric(score))],
           armB = S$panels$armB[, .(Date, Ticker, score = as.numeric(q50))],
           armC = S$panels$armC[, .(Date, Ticker, score = as.numeric(score))])

## ---- (1) F0 사후 양성 대조 ----
pc <- list()
for (pn in c("c_vs_a", "b_vs_a")) {
  d <- GS$diffs[[paste("F0", pn, sep = "|")]]
  pc[[pn]] <- list(n = nrow(d), nw3_t = nw_t(d$d), mean_annual_pct = 100*12*mean(d$d))
}
published <- list(c_vs_a = 0.0876, b_vs_a = -1.25)
cat("=== (1) F0 사후 양성 대조 (선행 라운드 공표 paired t 재현) ===\n")
for (pn in names(pc))
  cat(sprintf("  %s : 재산출 t %+.4f vs 공표 t %+.4f  (n=%d, 연 %+.3f%%p)\n",
              pn, pc[[pn]]$nw3_t, published[[pn]], pc[[pn]]$n, pc[[pn]]$mean_annual_pct))

## ---- (2) 랭크-기울기 (198개월 paired 창 · gross/net 채널 분리) ----
paired_dates <- VF$coprimary$c_vs_a$diff_series$date
rs <- list(); ch <- list()
for (pn in c("c_vs_a","b_vs_a")) {
  arm <- if (pn == "c_vs_a") "armC" else "armB"
  A <- copy(sc$armA)[, .(Date, Ticker, sA = score)]
  X <- copy(sc[[arm]])[, .(Date, Ticker, sX = score)]
  M <- merge(A, X, by = c("Date","Ticker"))
  M <- merge(M, frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  M <- M[Date %in% paired_dates]
  setorder(M, Date, -sA); M[, rA := seq_len(.N), by = Date]
  setorder(M, Date, -sX); M[, rX := seq_len(.N), by = Date]
  M[, nD := .N, by = Date]
  M[, wA := (nD - rA) / (nD*(nD-1)/2)]; M[, wX := (nD - rX) / (nD*(nD-1)/2)]
  M[, contrib := (wX - wA) * Ret_1m]
  M[, bucket := fifelse(rA <= 25L, "rA_001_025", fifelse(rA <= 50L, "rA_026_050",
                fifelse(rA <= 100L, "rA_051_100", fifelse(rA <= 200L, "rA_101_200", "rA_201_plus"))))]
  bm <- M[, .(c = sum(contrib)), by = .(Date, bucket)]
  gross_tot <- M[, .(g = sum(contrib)), by = Date]
  tab <- bm[, .(mean_monthly = mean(c), annual_pct = 100*12*mean(c),
                t_nw3 = nw_t(c), n = .N), by = bucket][order(bucket)]
  tab[, share_of_gross_diff := mean_monthly / mean(gross_tot$g)]
  rs[[pn]] <- tab
  ## gross/net 채널: net diff = gross diff − 비용 diff
  tA <- VF$res$armA$period_returns[date %in% paired_dates]
  tX <- VF$res[[arm]]$period_returns[date %in% paired_dates]
  ch[[pn]] <- list(
    gross_diff_annual_pct = 100*12*mean(gross_tot$g),
    gross_diff_from_pr_annual_pct = 100*12*mean(tX$port_gross - tA$port_gross),
    cost_diff_annual_pct = 100*12*mean((tX$traded - tA$traded)*15/1e4),
    net_diff_annual_pct  = 100*12*mean(tX$ret_net - tA$ret_net))
  cat(sprintf("\n=== (2) 랭크-기울기 %s (198개월) ===\n", pn)); print(tab)
  cat(sprintf("  채널: gross %+.4f%%p/yr · 비용차 %+.4f%%p/yr · net %+.4f%%p/yr\n",
              ch[[pn]]$gross_diff_annual_pct, ch[[pn]]$cost_diff_annual_pct,
              ch[[pn]]$net_diff_annual_pct))
  ## top-25 버킷이 총 gross diff 와 **부호가 반대**인가 (스코프 한정 라벨의 정량 근거)
  t25 <- tab[bucket == "rA_001_025"]
  cat(sprintf("  ★top-25 랭크대 기여 %+.4f%%p/yr (t %+.3f) — 총 gross %+.4f%%p/yr 대비 부호 %s\n",
              t25$annual_pct, t25$t_nw3, ch[[pn]]$gross_diff_annual_pct,
              ifelse(sign(t25$annual_pct) == sign(ch[[pn]]$gross_diff_annual_pct), "동일", "반대")))
}

write_json(list(
  wt_id = "WT-D20260821_002", step = "postlock_controls",
  computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  f0_positive_control = list(recomputed = pc, published_prior = published,
    note = "F0 는 사다리 후보가 아니라 축1 분모·기준선. gate_lock 이후 산출이므로 프레임 선택에 영향 불가 — 배관 재현 확인 전용."),
  rank_slope_198m = rs, gross_net_channels = ch),
  file.path(OUT, "postlock_controls.json"), auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null")
cat("\n저장: postlock_controls.json\n")
