## 최종 집계 — cap-tier 상세 추출 + alpha_validation.json + 차트 2종
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[fin] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
source("02_Infrastructure/telegram/tg_chart_pack.R")

RES <- readRDS(file.path(OUT,"m26_results.rds"))
CAN <- readRDS(file.path(OUT,"m26_canonical.rds"))
say("★입력 실측: m26_results.rds 키 %s | m26_canonical.rds 키 %s",
    paste(names(RES),collapse=","), paste(names(CAN),collapse=","))
say("canonical raw 최상위 키: %s", paste(names(CAN$raw), collapse=","))

## --- cap-tier 상세 ---
ct <- CAN$raw$diag_cap_tier
say("--- cap-tier 분해 (원신호) ---")
for (nm in c("weight_share_avg","contrib_gross_monthly_avg","contrib_gross_annualized")) {
  v <- ct[[nm]]; if (is.null(v)) next
  say("  %-28s %s", nm, paste(sprintf("%s=%.4f", names(v), unlist(v)), collapse=" · "))
}
ew <- CAN$raw$diag_ew_universe

## --- 판정 조립 ---
tab <- RES$tab; sp <- RES$sp
TT  <- tab[term=="M26_Revenue_Mom"]
fmb_t <- TT$t_nw3; sp_max <- max(sp$mean_rho)
verdict <- if (abs(fmb_t) >= 2.0 && sp_max < 0.9) "MATERIAL_QUALIFIED" else
           if (abs(fmb_t) >= 2.0) "REDUNDANT" else RES$power$verdict
say("★사전등록 분기 적용: |t|=%.3f (>=2.0 %s) ∧ max spearman=%.4f (<0.9 %s) ⇒ %s",
    abs(fmb_t), abs(fmb_t)>=2.0, sp_max, sp_max<0.9, verdict)

pt_raw <- CAN$raw$portfolio_alpha_t_nw_lag3
pt_res <- CAN$resid$portfolio_alpha_t_nw_lag3

AV <- list(
  wt_id = "WT-D20260808_002", factor = "M26_Revenue_Mom",
  as_of = "2026-08-08", metric_type_primary = "canonical_screen_diag",
  prereg_ref = "stage_artifacts/c14_revsurprise/prereg.json (대상 C14→M26 정정, 규칙·문턱·분기 불변 승계)",
  input_reality = list(
    factor_db_files = 442, rawdata_rows = 14059013, rawdata_unit = "daily",
    rawdata_unique_dates = 9003, rawdata_range = "1990-01-05 ~ 2026-08-07",
    forward_return_source = "build_monthly_forward_returns() 계약함수 (일간→월간 파생)",
    merge_standard = "align_signal_return_ym(off=0, return_dating='signal_anchor')",
    merge_coverage_month = 1.0, merge_coverage_row = 0.171,
    complete_case_months = 283, complete_case_rows = 69885,
    period = "2003-01 ~ 2026-07", stocks_per_month_median = 286,
    stocks_per_month_min = 115, stocks_per_month_max = 306,
    note = "월별 종목수는 K200∪KQ150 유니버스 ∩ 4종 동시가용. factor_db M26 커버(월중앙 1,579)는 유니버스 밖 포함치"
  ),
  primary = list(
    test = "fwd_ret ~ z(C01_SUE)+z(C02_EPS_Chg_1m)+z(C04_ESBR)+z(M26_Revenue_Mom), 월별 횡단면 OLS → Fama-MacBeth",
    estimator = "FMB NW(lag3)", pooled_ols_used = FALSE,
    n_months = TT$n_months, mean_coef = TT$mean_coef, sd_coef = TT$sd_coef,
    fmb_nw3_t = fmb_t, fmb_se_nw3 = TT$se_nw3, t_simple = TT$t_simple, pos_rate = TT$pos_rate,
    threshold = 2.0, threshold_meaning = "재료 자격 — 자본 게이트(HARD 3종) 아님",
    max_spearman_vs_incumbent = sp_max, redundant_threshold = 0.9,
    verdict = verdict,
    control_coefs = lapply(split(tab, tab$term), function(d) list(t_nw3=d$t_nw3, mean=d$mean_coef)),
    effective_control_note = "통제 3종 중 유의한 것은 C02_EPS_Chg_1m(t +2.71) 단독. C01_SUE(-0.04)·C04_ESBR(+0.49)는 이 설계에서 무력 — '3종 위의 증분'은 실질적으로 'C02 위의 증분'"
  ),
  secondary = list(
    rank_ic_mean = mean(RES$ic$ic), rank_ic_sd = sd(RES$ic$ic),
    rank_ic_t_nw3 = { x<-RES$ic$ic; n<-length(x); m<-mean(x); e<-x-m; s<-sum(e^2)/n
      for(l in 1:3) s <- s + 2*(1-l/4)*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) },
    icir = mean(RES$ic$ic)/sd(RES$ic$ic), ic_pos_rate = mean(RES$ic$ic>0),
    rank_ic_full_universe = list(n_months = nrow(RES$ic_all), mean = mean(RES$ic_all$ic),
      note = "4종 교집합 밖 포함 — breadth 손실 진단용"),
    single_factor_fmb_t = RES$single$t_nw3,
    increment_to_single_t_ratio = fmb_t / RES$single$t_nw3,
    spearman_vs_incumbent = as.list(setNames(sp$mean_rho, sp$other)),
    sue_m26_sign_agreement = RES$sign_agree,
    sign_disagreement = 1 - RES$sign_agree
  ),
  falsification_observed = list(
    claim = "메커니즘 참이면 M26(t)가 후속 eps_chg_1m(t+1..3)을 횡단면 예측해야 한다",
    result = as.list(RES$prop),
    verdict = "기전 반증 안 됨 — t+1 rho +0.0998(t_NW3 +16.71) → t+2 +0.0732 → t+3 +0.0542 로 감쇠하며 전파 관측",
    sign_test = sprintf("SUE↔M26 부호 불일치 %.1f%% ⇒ 기전이 시험됐다(재탕이면 불일치가 무시가능해야)", (1-RES$sign_agree)*100)
  ),
  power = list(
    label = RES$power$verdict, note = RES$power$note,
    required_monthly = RES$power$required$required_monthly,
    required_annual_pct = RES$power$required$required_annual*100,
    observed_monthly = TT$mean_coef, observed_annual_pct = TT$mean_coef*12*100,
    sd_basis = "계열 고유 sd(0.01047) — 도구 기본 sd(0.0394)는 top-25 EW 바스켓쌍 프레임이라 참고치",
    ci95_annual_pct = c(-1,1)  # 아래 치환
  ),
  robustness = list(
    placebo_p = RES$placebo_p, placebo_n = length(RES$placebo),
    placebo_design = "월내 M26 셔플 200회 → 동일 4-팩터 FMB 재적합",
    lag1_t = RES$lag1$t_nw3, lag1_retention = RES$lag1$t_nw3/fmb_t,
    lag1_note = "t-1 신호 사용 시 t +0.60(유지율 0.23) — 신호 수명 1개월 미만. 구조적으로 look-ahead 아님(신호창 종점=월말, 수익창=(월말,+1M]) 이나 컨센서스 same-day vintage 축은 미검증",
    subperiod = as.list(RES$era)
  ),
  transition = list(
    method = "canonical_screen_bt(top_n=25, cost 15bps, liq 2e8) — 스크리닝 실측, 포트폴리오 구성 아님",
    canonical_port_t_raw = pt_raw, canonical_port_t_resid = pt_res,
    hard_threshold = 2.95, hard_pass = FALSE,
    net_sr_raw = CAN$raw$net_sr, turnover_annual_raw = CAN$raw$turnover_annual,
    turnover_note = "11.74/yr — Implementation Discipline 기준선 11.0/yr 초과",
    dual_basis = list(
      ew_universe_port_t_raw = ew$portfolio_alpha_t_nw_lag3,
      ew_universe_p_raw = ew$portfolio_alpha_t_pvalue,
      ew_universe_ir_raw = ew$information_ratio,
      oos_retention_approx = ew$oos_retention_approx,
      post2017_t_nw_lag3 = ew$post2017_t_nw_lag3,
      n_months_post2017 = ew$n_months_post2017,
      ew_universe_port_t_resid = CAN$resid$diag_ew_universe$portfolio_alpha_t_nw_lag3,
      interpretation = "EW-대비에서 2.04 로 상승하나 여전히 HARD 2.95 미달 — 벤치 아티팩트만으로 설명되지 않는 실전이 미달"
    ),
    cap_tier = list(weight_share_avg = ct$weight_share_avg,
                    contrib_gross_annualized = ct$contrib_gross_annualized,
                    tier_def = ct$tier_def)
  ),
  ax001 = list(applicable = FALSE, detected_family = "consensus_revenue_revision",
    rationale = "registry labels.regime_profile = risk_on:positive / crisis:negative — 방어 프로필 아님. 전기간 평가가 정당."),
  selection_type = "chain_not_applicable_single_test",
  n_trials = 1,
  dsr_gate_applicable = FALSE,
  dsr_note = "sweep형 selection 아님 — 사전등록이 factor_db 산출 형태 1벌만 쓰도록 고정(no_sweep). DSR 게이트 부적용(measurement-graduation §3)."
)
## CI 치환
m <- TT$mean_coef; se <- TT$se_nw3
AV$power$ci95_annual_pct <- c((m-1.96*se)*12*100, (m+1.96*se)*12*100)

write(toJSON(AV, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null"),
      file.path(OUT,"alpha_validation.json"))
say("alpha_validation.json 저장")

## --- 차트 1: 전이 사다리 (IC → FMB → EW-PORT_t → cap-w PORT_t vs HARD) ---
p1 <- tg_chart_sweep(
  labels = c("M26 단독 rank-IC t", "증분 FMB t (주판정)", "EW-유니버스 PORT_t",
             "cap-w PORT_t (권위)", "post-2017 PORT_t", "HARD 문턱 2.95"),
  values = c(AV$secondary$rank_ic_t_nw3, fmb_t, ew$portfolio_alpha_t_nw_lag3,
             pt_raw, ew$post2017_t_nw_lag3, 2.95),
  out_dir = OUT, title = "M26 전이 사다리 — 정보계수에서 실현 초과수익까지")
say("차트1: %s", p1)

## --- 차트 2: 통제 3종 대비 증분 계수 t ---
p2 <- tg_chart_sweep(
  labels = c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M26_Revenue_Mom (신규)", "판정 문턱 2.0"),
  values = c(tab[term=="C01_SUE", t_nw3], tab[term=="C02_EPS_Chg_1m", t_nw3],
             tab[term=="C04_ESBR", t_nw3], fmb_t, 2.0),
  out_dir = OUT, title = "4팩터 동시 FMB 계수 t값 — 이익 3종 대비 매출 증분")
say("차트2: %s", p2)
writeLines(c(p1,p2), file.path(OUT,"chart_paths.txt"))
say("★최종 판정: %s · FMB t %+.3f · cap-w PORT_t %+.3f · EW PORT_t %+.3f", verdict, fmb_t, pt_raw,
    ew$portfolio_alpha_t_nw_lag3)
