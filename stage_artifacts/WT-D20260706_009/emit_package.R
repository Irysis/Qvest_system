# emit_package.R — WT-D20260706_009 alpha deliverables (alpha_package.json + alpha_scores.parquet + alpha_validation.json)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PAN <- file.path(ROOT,"stage_artifacts/WT-D20260706_009/panel")
SA  <- file.path(ROOT,"stage_artifacts/WT-D20260706_009")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260706_009")

sr <- readRDS(file.path(SA,"screen_results.rds"))
og <- readRDS(file.path(SA,"ortho_results.rds"))
sc <- as.data.table(read_parquet(file.path(PAN,"nsi_scores_monthly.parquet")))

# ---- alpha_scores.parquet : latest-month cross-sectional alpha for the universe ----
AS_OF <- as.Date("2026-07-01")   # latest signal month in panel
last <- sc[Date==AS_OF & is.finite(nsi_shares)]
if (nrow(last)==0) { AS_OF <- max(sc[is.finite(nsi_shares)]$Date); last <- sc[Date==AS_OF & is.finite(nsi_shares)] }
# cross-sectional z of nsi_shares = alpha score (higher = more retirement = long)
last[, z := (nsi_shares - mean(nsi_shares))/sd(nsi_shares)]
last[, alpha_hat := 0.0102 * z]   # scale z by ~1 monthly-vol-ish (indicative expected active; screening-tier)
# confidence: higher for nonzero signal + liquid + mid-large size
last[, confidence := pmin(1, pmax(0.1, 0.3 + 0.5*(abs(nsi_shares)>0.005) + 0.2*(size_pctile>=0.5)))]
alpha_scores <- last[, .(Date=AS_OF, Ticker, nsi_shares, nsi_cei, size_pctile,
                         alpha_hat, confidence)]
write_parquet(alpha_scores, file.path(SA,"alpha_scores.parquet"))
cat(sprintf("[emit] alpha_scores.parquet: %d names @ %s\n", nrow(alpha_scores), as.character(AS_OF)))

# ---- alpha_validation.json ----
getrow <- function(dt,lab) { r<-dt[label==lab]; if(nrow(r)==0) return(list(port_t=NA,ir=NA,net_sr=NA,alpha_ann=NA,turnover=NA,n_months=NA)); as.list(r[1]) }
A_cw <- sr$resA$cw; A_ew <- sr$resA$ew
validation <- list(
  task_id = "WT-D20260706_009",
  as_of_date = "2026-07-06",
  metric_type = "canonical_screen",
  verdict = "CLEAN_NEGATIVE",
  verdict_rationale = "Net-issuance는 실재 횡단면 프리미엄(rank-IC t=4.30, RETIRE 2.04%/월, 직교 0.064)이나 top-25 long-only cap-w PORT_t 全 <2.95(best 0.08). value-up 2024+ cap-w 음(-1.02). thesis(감쇠벽 밖=large-cap-relevant) 반증: cap-w 음 + EW만 양 = small/mid 틸트, mega-cap 앵커 부재. IC->PORT_t 전이 벽 안.",
  primary_signal = "NSI_shares (split-adjusted -Δlog shares outstanding TTM 4Q), long net-retirement",
  diagnostics = list(
    rank_ic = round(sr$icA$rank_ic,4),
    rank_ic_harvey_t = round(sr$icA$ic_t,3),
    icir = round(sr$icA$icir,3),
    rank_ic_liquid_t = 4.35,
    rank_ic_raw_noSplitAdj_t = round(sr$icA_raw$ic_t,3),
    rank_ic_cei = round(sr$icB$rank_ic,4),
    rank_ic_cei_t = round(sr$icB$ic_t,3),
    monotonicity = round(sr$mono,3),
    n_months = sr$icA$n
  ),
  portfolio_alpha_t_canonical = list(
    note = "canonical_screen_bt top-25 EW long-only 15bps 2e8. NW lag-3. metric_type=canonical_screen (NOT forge-authoritative). HARD gate=portfolio_alpha_t_nw>=2.95 on forge value.",
    NSI_shares_FULL_capw = getrow(A_cw,"FULL_capw")$port_t,
    NSI_shares_FULL_ew   = getrow(A_ew,"FULL_ew")$port_t,
    NSI_shares_PRE2017_capw = getrow(A_cw,"PRE2017_capw")$port_t,
    NSI_shares_POST2017_capw = getrow(A_cw,"POST2017_capw")$port_t,
    NSI_shares_POST2017_ew  = getrow(A_ew,"POST2017_ew")$port_t,
    NSI_shares_VALUEUP2024_capw = getrow(A_cw,"VALUEUP2024_capw")$port_t,
    NSI_shares_VALUEUP2024_ew   = getrow(A_ew,"VALUEUP2024_ew")$port_t
  ),
  large_cap_decomposition = list(
    LARGE_rank_ic_t = round(sr$icL$ic_t,3),
    SMALL_rank_ic_t = round(sr$icS$ic_t,3),
    LARGE_capw_port_t = sr$lc[group=="LARGE"&bench=="capw"]$port_t,
    LARGE_ew_port_t   = sr$lc[group=="LARGE"&bench=="ew"]$port_t,
    SMALL_capw_port_t = sr$lc[group=="SMALL"&bench=="capw"]$port_t,
    interpretation = "신호는 SMALL(t=4.57)에서 LARGE(t=2.41)보다 강함 → large-cap-relevant thesis 반증. large-cap top-25 PORT_t dead(0.09~0.17)."
  ),
  ew_vs_capw_reframe = list(
    finding = "POST2017 cap-w PORT_t=-0.58(음) EW=+1.58(양). VALUEUP2024 cap-w=-1.02 EW=+1.92.",
    conclusion = "cap-w 음 + EW만 양 = small/mid-vs-megacap 틸트(벤치아티팩트 아님). 신호는 EW-평균 이기나 cap-w 지수 못 이김 = 벽 안. insider 유형(cap-w 생존) 아님."
  ),
  subperiod = list(
    PRE2017_capw_port_t = getrow(A_cw,"PRE2017_capw")$port_t,
    POST2017_capw_port_t = getrow(A_cw,"POST2017_capw")$port_t,
    VALUEUP2024_capw_port_t = getrow(A_cw,"VALUEUP2024_capw")$port_t,
    trend = "cap-w 기준 PRE +0.77 -> POST -0.58 -> VALUEUP -1.02 단조 하락. value-up이 규율 강화 못함(cap-w)."
  ),
  orthogonality = list(
    nsi_vs_book_alpha_spearman = round(og$nsi_vs_book_spear,3),
    nsi_vs_book_alpha_pearson = round(og$nsi_vs_book_pear,3),
    nsi_vs_size_spearman = round(og$nsi_vs_size,3),
    incumbent_book = "STR_1715 AR (earnings-revision core + defense)",
    conclusion = "NSI vs book 0.064 = 고도 직교(재중복 아님, 상속 아님). 그러나 직교!=수익(measurement-graduation §6): PORT_t 미통과."
  ),
  split_adjustment = list(
    split_quarters_flagged_pct = 1.80,
    rank_ic_adj_vs_raw = "4.30 vs 4.41 (거의 동일 -> 신호는 split 아닌 실 issuance)",
    top25_overlap_adj_raw_pct = 92.1,
    cei_crosscheck = "split-proof CEI도 PORT_t 全 음(방향 일치)로 split 아티팩트 배제"
  ),
  distribution_caveat = "nsi_shares 72.3% exactly-zero(shares 대부분 불변), 실 retirer 3.8%. RETIRERS-only 스크린도 PORT_t 음. long-short가 자연 표현이나 KR no-short. top-25 이식성 구조적 벽.",
  screen_route = "DPL_FEATURE (financing-side 직교 피처, measurement-graduation §5 DPL 연료)",
  challenge_flags = list("RF-A4? no (post-neut 미해당)","EW-only survivor small/mid tilt (ACCEPT)","signal sparsity 72% zero (ACCEPT)"),
  references = list("Daniel-Titman 2006 (composite equity issuance)","Pontiff-Woodgate 2008 (net share issuance)")
)
write_json(validation, file.path(SA,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[emit] alpha_validation.json written\n")

# ---- alpha_package.json (schema alpha_package) ----
alpha_vec <- setNames(as.list(round(alpha_scores$alpha_hat,5)), alpha_scores$Ticker)
conf_vec  <- setNames(as.list(round(alpha_scores$confidence,3)), alpha_scores$Ticker)
alpha_package <- list(
  task_id = "WT-D20260706_009",
  wt_type = "discovery",
  as_of_date = "2026-07-06",
  forecast_horizon = "1M",
  verdict = "CLEAN_NEGATIVE",
  selection_objective = "rank_ic",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT-D20260706_009/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "CapitalDiscipline/Financing",
    proxy = "Net Share Issuance (split-adjusted)",
    formula = "-Δlog(split_adjusted_shares_outstanding, TTM 4Q); split=단일분기|Δlog|>0.35 cumsum-jump 제거",
    lag_rule = "quarterly Factor_Date (period+~45d, 재무 5월/45일 규칙)",
    winsorization = "split-jump removal (SPLIT_THRESH=0.35)",
    neutralization = "none (raw cross-sectional; size confound 0.104 낮음)",
    economic_rationale = "Daniel-Titman 2006 / Pontiff-Woodgate 2008: 순-발행 음(자사주 소각·감자)=capital discipline=positive future active return; 순-발행 양(SEO·희석)=negative. financing-side 특정으로 asset-growth(총자산 F)·buyback-decision-event(F)와 구분되는 별개 축.",
    weight_theta = 1.0,
    references = list("Daniel-Titman 2006","Pontiff-Woodgate 2008")
  )),
  diagnostics = list(
    rank_ic = round(sr$icA$rank_ic,4),
    icir = round(sr$icA$icir,3),
    monotonicity = round(sr$mono,3),
    subperiod_stability = 0.0,
    turnover_proxy = 1.55,
    harvey_t_stat = round(sr$icA$ic_t,3),
    portfolio_alpha_t_canonical_best = 0.082,
    portfolio_alpha_t_canonical_full_capw = A_cw[label=="FULL_capw"]$port_t,
    metric_type = "canonical_screen",
    orthogonality_vs_book = round(og$nsi_vs_book_spear,3)
  ),
  alpha_inheritance_cor = round(og$nsi_vs_book_spear,3),
  method_shopping_log = list(candidates_tried = 2, method_log = list(
    list(name="NSI_shares_split_adjusted", rank_ic=round(sr$icA$rank_ic,4), selected=TRUE),
    list(name="NSI_cei_composite_equity_issuance", rank_ic=round(sr$icB$rank_ic,4), selected=FALSE)
  )),
  challenge_flags = list(
    "CLEAN_NEGATIVE: cap-w PORT_t 全 <2.95 (best 0.08). IC->PORT_t 전이 벽.",
    "thesis 반증: cap-w 음 + EW만 양 = small/mid 틸트(large-cap-relevant 아님).",
    "value-up 2024+ cap-w 음(-1.02) — 규율 강화 thesis 성립 안 함(cap-w).",
    "직교(0.064)이나 직교!=수익. screen_route=DPL_FEATURE.",
    "signal sparsity 72% zero — long-only 이식 구조적 벽 (no-short mandate)."
  ),
  recommendation = "NO forge 승격 (cap-w PORT_t 0.08 ≪ 2.95). screen-route=DPL_FEATURE. CLEAN_NEGATIVE mechanism 기록."
)
write_json(alpha_package, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[emit] alpha_package.json written to mailbox\n")

# lineage (after write)
lu <- file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  tryCatch({ source(lu); record_package_lineage(task_id="WT-D20260706_009", package_type="alpha_package",
    method_selected="NSI_shares split-adjusted (Net Share Issuance)",
    input_file_paths=c(".cache/shares_issued.parquet",".cache/RAWDATA.parquet")) ; cat("[emit] lineage recorded\n") },
    error=function(e) cat("[emit] lineage skip:", conditionMessage(e), "\n"))
}
cat("[emit] DONE\n")
