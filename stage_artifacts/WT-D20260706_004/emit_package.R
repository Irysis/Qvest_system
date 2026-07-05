# emit_package.R — WT-D20260706_004 — write alpha_package.json (KILL) + alpha_validation.json + alpha_scores.parquet
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
WT <- "WT-D20260706_004"
MBX <- file.path(ROOT, "qepm/mailbox/worktask", WT)
SA  <- file.path(ROOT, "stage_artifacts", WT)

sr <- readRDS(file.path(SA, "screen_results.rds"))
getrow <- function(dt, lbl, col) { v <- dt[label==lbl, get(col)]; if(length(v)==0) NA else v[1] }

# alpha_scores.parquet — full-universe score at latest signal date (as_of), for completeness/lineage.
fx <- as.data.table(read_parquet(file.path(SA, "panel/fx_scores_monthly.parquet")))
asof <- max(fx$Date)
scores_latest <- fx[Date == asof & is.finite(beta_fx_2f),
                    .(Date, Ticker, alpha_hat = 0.0, score_beta_fx_2f = beta_fx_2f,
                      score_beta_fx_uni = beta_fx, beta_mkt, r2)]
# alpha_hat = 0 (KILL — no deployable forecast). scores retained for diagnostics/lineage only.
write_parquet(scores_latest, file.path(SA, "alpha_scores.parquet"))

diag <- list(
  rank_ic = round(sr$rank_ic, 4),
  rank_ic_t = round(sr$ic_t, 3),
  icir = round(sr$icir, 3),
  metric_type = "canonical_screen",
  portfolio_alpha_t_full_capw = getrow(sr$res_cw, "FULL_capw", "port_t"),
  portfolio_alpha_t_post2017_capw = getrow(sr$res_cw, "POST2017_capw", "port_t"),
  portfolio_alpha_t_regime_weak_capw = getrow(sr$res_cw, "REGIME_WEAK_capw", "port_t"),
  portfolio_alpha_t_regime_strong_capw = getrow(sr$res_cw, "REGIME_STRONG_capw", "port_t"),
  portfolio_alpha_t_full_ew = getrow(sr$res_ew, "FULL_ew", "port_t"),
  portfolio_alpha_t_post2017_ew = getrow(sr$res_ew, "POST2017_ew", "port_t"),
  inverse_full_capw_port_t = getrow(sr$res_inv, "INV_FULL_capw", "port_t"),
  turnover_annual = getrow(sr$res_cw, "FULL_capw", "turnover"),
  megacap_top25_share = round(sr$mega_share, 3),
  top25_median_size_pctile = round(sr$top25_med_size_pctile, 1)
)

alpha_package <- list(
  task_id = WT,
  as_of_date = as.character(asof),
  forecast_horizon = "1M",
  wt_type = "discovery",
  verdict = "KILL_FALSIFIED",
  metric_type = "canonical_screen",
  selection_objective = "rank_ic",
  hypothesis = "종목별 rolling KRW/USD 2-factor beta(export-sensitivity) 국면조건부(원약세 regime) 수출노출 alpha",
  economic_rationale = "KR 수출주도: 원약세(KRW/USD up)는 수출주 달러매출 번역+경쟁력 수혜. 원약세 regime에서 고-FX-beta 틸트.",
  redundancy_cluster_id = "macro_fx_linkage_return_derived",
  alpha_vector = setNames(list(), character(0)),      # empty — no deployable forecast (KILL)
  confidence_vector = setNames(list(), character(0)),
  factor_specs = list(list(
    factor_family = "Macro-FX-linkage",
    proxy = "rolling 120d 2-factor beta on KRW/USD dlog (mkt-orthogonalized)",
    formula = "OLS: r_i,d = a + b_mkt*mkt_d + b_fx*dlog(KRW/USD)_d over trailing 120 trading days ending month-end t; score = b_fx",
    lag_rule = "daily t-1 close for returns; KRW/USD spot@t (C11 contemporaneous); regime = KRW vs trailing 12m MA <= t",
    winsorization = "none (raw beta; cross-sectional rank via canonical top-N)",
    neutralization = "market-beta (2-factor OLS orthogonalizes market)",
    economic_rationale = "export earnings translation to KRW weakness",
    weight_theta = 0.0,
    references = c("Adler-Dumas 1984 exposure regression", "KR export-market macro linkage (hypothesis-level)")
  )),
  diagnostics = diag,
  challenge_flags = list(
    list(id="RF-KILL", severity="HIGH", note="graduation HARD 3종 전부 미달: best PORT_t +0.356 <<2.95. 원약세 regime PORT_t -0.940(메커니즘 반대). post2017 -2.371."),
    list(id="RF-A1", severity="HIGH", note="rank-IC 0.0058 t=0.87 subperiod 방향력 부재"),
    list(id="megacap_check", severity="INFO", note="top-25 mega-cap share 3.2%, median size pctile 45.3%(중형) — mega-cap 재포착 아님. cap-w/EW 양쪽 음 → 벤치 아티팩트 아닌 진짜 신호 부재.")
  ),
  survivors = list(),
  next_step = "none — honest kill; no handoff to Risk/Optimizer",
  self_adversarial_challenge = "challenge_note.md (5 concern: mega-cap재포착[RULED OUT] / FX-beta look-ahead[CLEAN] / regime look-ahead[CLEAN] / rank-IC 오독[분리보고] / regime 표본[충분,반증강화])"
)

write_json(alpha_package, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")

alpha_validation <- list(
  task_id = WT, verdict = "KILL_FALSIFIED",
  graduation_gate = list(
    min_portfolio_alpha_t_nw = 2.95,
    best_observed_port_t = max(unlist(sr$res_cw$port_t), na.rm = TRUE),
    pass = FALSE
  ),
  regime_split = list(
    weak_capw_port_t = getrow(sr$res_cw, "REGIME_WEAK_capw", "port_t"),
    strong_capw_port_t = getrow(sr$res_cw, "REGIME_STRONG_capw", "port_t"),
    interpretation = "가설 핵심 regime(원약세 WEAK)이 최악(-0.940). 메커니즘 방향 반증."
  ),
  megacap_recapture_diagnostic = list(
    top25_megacap_share = round(sr$mega_share, 3),
    top25_median_size_pctile = round(sr$top25_med_size_pctile, 1),
    conclusion = "mega-cap 재포착 아님(중형주). cap-w/EW 양쪽 음 → return-additive 아님, 벤치 아티팩트도 아님."
  ),
  pit_checks = list(fx_beta_window="rolling 120d trailing ending t (C1 no full-sample)",
                    krw_usd="spot@t contemporaneous (C11)", regime="trailing 12m MA <= t (no look-ahead)",
                    forward_return="Ret_1m realized t->t+1 (C2-safe shift -1)"),
  universe_comparison = list(note="single universe KOSPI200 union KQ150 (KR_top342 family), liq 2e8. v2 미실행 — 신호가 방향력 자체 없어(rank-IC 0.006) universe 확장이 구제할 여지 없음."),
  n_months_full = 258, as_of_date = as.character(asof)
)
write_json(alpha_validation, file.path(SA, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")

cat("[emit] alpha_package.json + alpha_validation.json + alpha_scores.parquet written\n")
cat("[emit] best cap-w PORT_t =", max(unlist(sr$res_cw$port_t), na.rm=TRUE), " verdict=KILL\n")
