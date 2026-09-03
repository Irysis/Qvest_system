# S2 — Step 0 사전 검정력 계약 (앵커 3종 전부) + 착수 게이트
#  ★규율: 이 단계는 근접도 신호를 소비하지 않는다. MDE80 의 sd 는 **기저 arm**(JT 모멘텀 top-25,
#    = 강화 체인의 base · 2/20 cell4 재현)에서만 뽑는다 — 사전 약속의 조건.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
P <- readRDS(file.path(OUT, "panel.rds")); SIG <- P$SIG; fwd <- P$fwd; ME <- P$ME
LIQ_MIN <- 2e8; COST_BPS <- 15; PPY <- 12L

beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], se_alpha_ann = abs(12*ct[1,1])/abs(ct[1,3]),
       beta = ct[2,1], t_beta = ct[2,3], beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }

## ── 기저 신호(JT 6-1): 월말 s 에서 s-1 시점의 6개월 수익 (skip 1M) ──────────
setorder(SIG, Ticker, Date)
SIG[, jt6_skip1 := shift(jt6, 1L), by = Ticker]
E0 <- SIG[Date %in% ME & in_univ == TRUE]
E0 <- merge(E0, fwd$liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
E0 <- E0[is.na(adv) | adv >= LIQ_MIN]
R <- as.data.table(fwd$returns_dt)[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
bench <- as.data.table(fwd$bench_dt)

base_scores <- E0[is.finite(jt6_skip1), .(Date, Ticker, score = jt6_skip1)]
cs_base <- canonical_screen_bt(base_scores, R, bench, top_n = 25L, cost_bps_oneway = COST_BPS,
                               liq_dt = NULL, run_id = "base_JT61", strategy_id = "base_JT61_top25",
                               diag_dual_basis = FALSE)
pr_b <- as.data.table(cs_base$period_returns)
ba_b <- beta_alpha(pr_b$ret_net, pr_b$benchmark_ret)
act_b <- pr_b$ret_net - pr_b$benchmark_ret
cat(sprintf("[S2] base arm(JT6-1 top25): n=%d PORT_t=%+.3f  a=%+.2f%%/yr t=%+.3f b=%.3f  SE(a)=%.4f\n",
            nrow(pr_b), cs_base$portfolio_alpha_t_nw_lag3, 100*ba_b$alpha_ann, ba_b$t_alpha, ba_b$beta, ba_b$se_alpha_ann))

## ── 검정력 계약 (앵커 3종) ──────────────────────────────────────────────────
SE <- ba_b$se_alpha_ann                      # 연율 alpha 의 표준오차 (beta-통제, NW lag-3)
MDE80 <- 2.8016 * SE
SE_rep <- 0.0514/1.205                       # 2/20 보고치에서 역산한 SE (병기)
MDE80_rep <- 2.8016 * SE_rep

mk <- function(id, val_ann, src, why) list(
  anchor_id = id, effect_size_target_ann = val_ann, source = src, why = why,
  mde80_ann = MDE80, ratio = val_ann/MDE80, expected_t = (val_ann/MDE80)*2.8016,
  power = pnorm((val_ann/MDE80)*2.8016 - 1.96),
  disposition = if (!is.finite(val_ann/MDE80) || val_ann/MDE80 < 0.15) "(a) 착수금지구간 — 우연 수준"
                else if (val_ann/MDE80 < 0.70) "(b) 조건부 착수 — 미결이 최빈 결말"
                else "(c) 통상 착수",
  mde80_ann_from_reported_cell4 = MDE80_rep, ratio_from_reported_cell4 = val_ann/MDE80_rep)

anchors <- list(
  A_paper_winner_leg_raw = mk("A_paper_winner_leg (raw, Jan 포함)", 12*0.0016,
    "GH2004 Table V FHH(52주 신고가 winner 더미) = +0.16%/월 (t 3.06)",
    "롱온리 mandate 에서 법적으로 수확 가능한 유일한 절반. 연환산 = x12(산술합) — sd 규약 정합."),
  A_paper_winner_leg_riskadj = mk("A_paper_winner_leg (risk-adjusted, Jan 포함)", 12*0.0027,
    "GH2004 Table V FHH risk-adjusted = +0.27%/월 (t 6.49)", "동일 앵커의 위험조정판."),
  B_increment_over_JT_raw = mk("B_paper_increment_over_JT (raw)", 12*(0.0016-0.0017),
    "GH2004 Table V FHH(+0.16) - JH(+0.17) [raw]",
    "★과거수익률 신호 대비 증분. raw 에서 GH2004 자신이 음(-)이다."),
  B_increment_over_JT_riskadj = mk("B_paper_increment_over_JT (risk-adj)", 12*(0.0027-0.0016),
    "GH2004 Table V FHH(+0.27) - JH(+0.16) [risk-adjusted]", "증분은 위험조정에서만 양(+)이다."),
  C_inhouse_prior_ff3 = mk("C_inhouse_prior (FF3 alpha)", 0.0346,
    "STR_AS_20260612_132740_321992 — FF3 alpha 3.46%/yr (t 1.178, n=254월)",
    "동일 신호의 KR 실측 사전. 같은 런의 Carhart4 alpha 는 0.71%/yr 로 소멸한다(병기)."),
  C_inhouse_prior_carhart4 = mk("C_inhouse_prior (Carhart4 alpha)", 0.0071,
    "동일 런 Carhart4 alpha 0.71%/yr (t 0.275)", "모멘텀 팩터 흡수 후 남는 잔여 — 하한 앵커."))

forbidden <- list(
  banned_anchor = "GH2004 자기금융 스프레드 0.65%/월 (t 4.08)",
  reason = "그 값의 약 74%가 loser(숏) 레그이고 KR 롱온리에서 수확 불가. 앵커로 쓰면 검정력을 약 4배 과대 산출한다.",
  counterfactual_if_used = { v <- 12*0.0065; list(effect_ann = v, ratio = v/MDE80, power = pnorm((v/MDE80)*2.8016 - 1.96)) },
  used = FALSE)

## ── 게이트 판정 ─────────────────────────────────────────────────────────────
gov <- c(anchors$A_paper_winner_leg_raw$ratio, anchors$A_paper_winner_leg_riskadj$ratio,
         anchors$C_inhouse_prior_ff3$ratio)
gate <- list(
  rule = "ratio < 0.15 이면 착수 중단 — 재량 없이 사전지정 배제형 구성으로 전환.",
  governing_anchors = "★2급(cell4 대비 증분)이 도훈 지시 3 으로 취소됐으므로 게이트를 지배하는 앵커는 후보 단독 alpha 를 재는 A/C 다. B(증분)는 산출/보고하되 대응 검정이 없다.",
  ratios = list(A_raw = anchors$A_paper_winner_leg_raw$ratio,
                A_riskadj = anchors$A_paper_winner_leg_riskadj$ratio,
                B_raw = anchors$B_increment_over_JT_raw$ratio,
                B_riskadj = anchors$B_increment_over_JT_riskadj$ratio,
                C_ff3 = anchors$C_inhouse_prior_ff3$ratio,
                C_carhart4 = anchors$C_inhouse_prior_carhart4$ratio),
  min_governing_ratio = min(gov), max_governing_ratio = max(gov),
  verdict = if (max(gov) < 0.15) "ABORT_SWITCH_TO_EXCLUSION" else "PROCEED_CONDITIONAL",
  band = "(b) 조건부 착수 — 미결이 최빈 결말",
  what_this_round_leaves_if_undecided = c(
    "선행 C 등급 런에 없던 통제(시장-내 랭킹/L-family/변동성/산업모멘텀) 뒤에서 FM t +3.199 가 생존하는지의 확정",
    "GH2004 Table VI 장기 무반전(F2)의 KR 최초 좌표 — anchoring vs 수익률 외삽 분기점",
    "신고가 부근 개인 순매수 부호(F3)의 KR 최초 좌표 — GK2001 주체 증거의 KR 대응",
    "M17_Low_52w 흡수 여부(F5) — '52주 신고가가 준거점' 주장의 식별",
    "실투형 후보의 회전율/비용 실측 좌표 + period_returns_production.csv 재사용 패널"))

reach_base <- list(n_months = length(act_b), sd_monthly_active = sd(act_b),
                   required_active_ann_for_t295 = 2.95*sd(act_b)/sqrt(length(act_b))*12,
                   observed_active_ann = 12*mean(act_b),
                   coverage_ratio = (12*mean(act_b))/(2.95*sd(act_b)/sqrt(length(act_b))*12))

res <- list(
  meta = list(wt_id = "WT-R20260829_007", step = "Step 0 — 사전 검정력 계약",
              metric_type = "canonical_screen", n_months = nrow(pr_b),
              window = paste(as.character(range(pr_b$date)), collapse = " ~ "),
              annualization_convention = "월평균 효과 x12 (산술합) — sqrt(12) 금지(3.46배 어긋남)",
              t_threshold_mde80 = 2.8016),
  sd_donor = list(
    arm = "기저 JT 6-1 모멘텀 top-25 EW long-only (강화 체인 base / 2/20 cell4 대응)",
    why = "근접도 신호를 쓰지 않는 arm 에서만 sd 를 뽑는다 — 착수 전 계약의 조건.",
    port_t = cs_base$portfolio_alpha_t_nw_lag3, beta_controlled = ba_b,
    se_alpha_ann_measured = SE, mde80_ann_measured = MDE80,
    se_alpha_ann_from_reported_cell4 = SE_rep, mde80_ann_from_reported_cell4 = MDE80_rep,
    reproduction_note = "2/20 보고 cell4 = alpha +5.14%/yr / t 1.205 / PORT_t 1.294. 본 재현은 신호 정의가 미세히 다르다(본 라운드는 패널 자체 산출 jt6_skip1) — 두 SE 를 병기한다."),
  anchors = anchors, forbidden_anchor = forbidden, gate = gate,
  reachability_ceiling_base = reach_base)
write_json(res, file.path(OUT, "s2_power.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(E0 = E0, R = R, bench = bench, cs_base = cs_base, pr_b = pr_b, ba_b = ba_b, SIG = SIG),
        file.path(OUT, "s2_objects.rds"))

cat("\n===== STEP 0 POWER CONTRACT =====\n")
cat(sprintf("SE(alpha_ann) = %.4f (measured base arm)  |  MDE80 = %.4f (= %.2f%%/yr)\n", SE, MDE80, 100*MDE80))
for (k in names(anchors)) { a <- anchors[[k]]
  cat(sprintf("%-30s eff=%+7.2f%%/yr ratio=%+6.3f E[t]=%+6.3f power=%.3f  %s\n",
              k, 100*a$effect_size_target_ann, a$ratio, a$expected_t, a$power, a$disposition)) }
cat(sprintf("\n금지앵커(자기금융 0.65%%/월) 반사실: ratio=%.3f power=%.3f — 사용 안 함\n",
            forbidden$counterfactual_if_used$ratio, forbidden$counterfactual_if_used$power))
cat(sprintf("GATE: %s (지배 ratio %.3f ~ %.3f)\n", gate$verdict, gate$min_governing_ratio, gate$max_governing_ratio))
cat(sprintf("base 창 도달가능성: 필요 활성 %+.2f%%/yr / 관측 %+.2f%%/yr / 비율 %.3f\n",
            100*reach_base$required_active_ann_for_t295, 100*reach_base$observed_active_ann, reach_base$coverage_ratio))
