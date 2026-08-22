## gate.R — WT-D20260821_002 **mean-blind 검정력 관문** (PREREG §3 단계 1)
##
## ★이 스크립트는 diff 의 평균·t 를 계산하지도, 출력하지도, 저장하지도 않는다.
##   arm 별 성과량(PORT_t/SR/…)도 산출하지 않는다(frame_screen_bt metrics=FALSE).
##   산출 대상 = 프레임별 paired diff 의 sd · 실측 nw_inflation · MDE 뿐.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
T0 <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
cat("[gate] start ", T0, "\n")

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean (nw_inflation_measured 의존)
source("02_Infrastructure/contracts/required_effect_size.R")
source("stage_artifacts/WT-D20260821_002/frame_lib.R")
OUT <- "stage_artifacts/WT-D20260821_002"

S <- readRDS(file.path(OUT, "step0_inputs.rds"))
frd <- S$frd; bench_dt <- S$bench_dt
sc <- list(
  armA = S$panels$armA[, .(Date, Ticker, score = as.numeric(score))],
  armB = S$panels$armB[, .(Date, Ticker, score = as.numeric(q50))],
  armC = S$panels$armC[, .(Date, Ticker, score = as.numeric(score))])

FRAMES <- c("F0", "F1", "F2", "F3L", "F3")   # F3 = 롱숏 원안, 진단 전용(PREREG §7)
PAIRS  <- list(c_vs_a = c("armC", "armA"), b_vs_a = c("armB", "armA"))
MDE_BAR_ANNUAL <- 0.030
LADDER <- c("F1", "F2", "F3L")               # 사전 고정 우선순위(성과 무관)

runs <- list(); diffs <- list(); gate_rows <- list()
for (fr in FRAMES) {
  runs[[fr]] <- lapply(sc, function(s)
    frame_screen_bt(s, frd, bench_dt, frame = fr, cost_bps_oneway = 15, metrics = FALSE))
  cat(sprintf("[gate] %-4s 구성완료 · 평균 종목수 %.1f · 유효종목수(ENN) %.1f · n_months %d\n",
              fr, runs[[fr]]$armA$avg_n_names, runs[[fr]]$armA$avg_eff_n_names,
              runs[[fr]]$armA$n_months))
  for (pn in names(PAIRS)) {
    a <- PAIRS[[pn]][2]; b <- PAIRS[[pn]][1]
    jA <- runs[[fr]][[a]]$period_returns[, .(date, a = ret_net)]
    jB <- runs[[fr]][[b]]$period_returns[, .(date, b = ret_net)]
    j <- merge(jA, jB, by = "date")
    d <- j$b - j$a
    diffs[[paste(fr, pn, sep = "|")]] <- data.table(date = j$date, d = d)

    ## ★sd·nw·MDE 만. mean/t 는 산출하지 않는다.
    sd_m <- stats::sd(d)
    nw_meas <- nw_inflation_measured(d)                       # 계약 함수 — series 실측
    re <- required_effect(n = length(d), t_threshold = 2.0, sd_monthly = sd_m,
                          design = "full", series = d)        # series= 로 실측 우선
    gate_rows[[length(gate_rows) + 1L]] <- data.table(
      frame = fr, pair = pn, n = length(d),
      diff_sd_monthly = sd_m,
      nw_inflation = re$nw_inflation, nw_inflation_source = re$nw_inflation_source,
      nw_inflation_measured_raw = nw_meas,
      mde_monthly = re$required_monthly, mde_annual = re$required_annual,
      ## 참고: 가정 상수 1.25 로 계산했을 때의 MDE (addendum 대조용)
      mde_annual_assumed125 = required_effect(n = length(d), sd_monthly = sd_m,
                                              nw_inflation = 1.25)$required_annual,
      ret_net_sd_armA = stats::sd(jA$a), ret_net_sd_other = stats::sd(jB$b))
  }
}
G <- rbindlist(gate_rows)

## --- 반증 축 1: sd 감소율 (분모 = 본 세션 재산출 F0) ---
f0 <- G[frame == "F0", .(pair, sd0 = diff_sd_monthly)]
G <- merge(G, f0, by = "pair")
G[, sd_ratio_vs_F0 := diff_sd_monthly / sd0]
G[, sd_reduction_pct := 100 * (1 - sd_ratio_vs_F0)]
G[, gate_pass := is.finite(mde_annual) & mde_annual <= MDE_BAR_ANNUAL]
setorder(G, pair, frame)
cat("\n=== 관문표 (sd·MDE 만 — 평균/t 미산출) ===\n")
print(G[, .(frame, pair, n, diff_sd_monthly = round(diff_sd_monthly, 6),
            nw = round(nw_inflation, 4), nw_src = nw_inflation_source,
            mde_ann_pct = round(100*mde_annual, 3),
            mde_ann_pct_if125 = round(100*mde_annual_assumed125, 3),
            sd_red_pct = round(sd_reduction_pct, 1), pass = gate_pass)])

## --- 바인딩 프레임 선택: 사다리 우선순위 최상위 통과 프레임 (co-primary 양쪽 모두 통과 요구) ---
sel <- NA_character_
for (fr in LADDER) {
  ok <- G[frame == fr, all(gate_pass)]
  if (isTRUE(ok)) { sel <- fr; break }
}
cat(sprintf("\n★관문 결과: 바인딩 프레임 = %s (사다리 %s, 문턱 MDE <= 연 %.1f%%p)\n",
            ifelse(is.na(sel), "없음 — 전 프레임 탈락", sel),
            paste(LADDER, collapse = " > "), 100*MDE_BAR_ANNUAL))

## --- 축 1 판정 ---
ax1 <- G[frame %in% LADDER, .(min_sd_ratio = min(sd_ratio_vs_F0)), by = pair]
ax1[, axis1_pass := min_sd_ratio <= 0.50]
cat("\n=== 반증 축 1 (sd 가 F0 의 50% 이하로 감소했는가) ===\n"); print(ax1)

## --- 스케일 진단: 잡음 축소와 브레드스의 관계 ---
scale_diag <- G[pair == "c_vs_a", .(frame, diff_sd_monthly, sd_ratio_vs_F0,
                                    ret_net_sd_armA,
                                    ret_sd_ratio_vs_F0 = ret_net_sd_armA / G[pair=="c_vs_a" & frame=="F0", ret_net_sd_armA])]
scale_diag <- merge(scale_diag,
  data.table(frame = FRAMES,
             avg_n = sapply(FRAMES, function(f) runs[[f]]$armA$avg_n_names),
             enn   = sapply(FRAMES, function(f) runs[[f]]$armA$avg_eff_n_names),
             turnover_annual = sapply(FRAMES, function(f) runs[[f]]$armA$turnover_annual)),
  by = "frame")
cat("\n=== 스케일 진단 (잡음 축소 배율 vs 브레드스) ===\n"); print(scale_diag)

T1 <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
write_json(list(
  wt_id = "WT-D20260821_002", round_id = "FQ233_FRAME_20260821",
  step = "gate_mean_blind", prereg = "PREREG_WT002_20260821.md",
  started_at = T0, finished_at = T1,
  mean_blind_declaration = paste0(
    "이 산출물에는 paired diff 의 평균·t 가 존재하지 않는다. gate.R 은 sd/nw/MDE 만 계산하며 ",
    "arm 별 성과량도 metrics=FALSE 로 우회했다. 프레임 선택은 사전 고정 사다리 F1>F2>F3L 의 ",
    "최상위 통과분이며 성과와 무관하다(PREREG §3)."),
  mde_bar_annual = MDE_BAR_ANNUAL, ladder = LADDER,
  gate_table = G, binding_frame = sel,
  axis1_sd_reduction = ax1, scale_diagnostic = scale_diag,
  stored_reference = list(
    armC_addendum_sd = 0.043381, armC_addendum_mde_annual = 0.092489,
    armC_addendum_nw = 1.25, armC_addendum_nw_source = "assumed_default_series_unmeasurable",
    note = "본 세션 F0 재산출치와 대조할 것 — ret_net 은 Step0 에서 bit-parity 확인됨")),
  file.path(OUT, "gate_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null")
saveRDS(list(runs = runs, diffs = diffs, G = G, binding = sel),
        file.path(OUT, "gate_series.rds"))
cat("\n[gate] end ", T1, " — 저장: gate_result.json · gate_series.rds\n")
