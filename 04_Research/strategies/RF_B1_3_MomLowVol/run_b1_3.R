# B1-3 rulefast 실행 래퍼 — 텔레그램/L-code 차단(블록 일괄 지시), 산출물 = 전략 디렉터리 내
ROOT <- Sys.getenv("QM_ROOT")
stopifnot(nzchar(ROOT))
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))

# L-code 발행 차단 — 부모 오케스트레이터가 블록 일괄 처리 (지시: 텔레그램·L-code 금지)
emit_lcode <- function(...) { cat("[B1-3] emit_lcode suppressed (block-level)\n"); NULL }
# 강화 원장 자동 open 차단 — entry 는 이미 존재(RP_20260829_122020_9192_rulefast, attempt n=3 사전 등록)
rf_open_entry <- function(...) stop("suppressed: ledger entry pre-registered by orchestrator")
lockBinding("rf_open_entry", globalenv())

res <- run_paper_replication(
  strategy_name = "RF_B1_3_MomLowVol",
  strategy_idea = "규칙기반 고속강화 B1-3: 모멘텀(12-1) rank-Z + 저변동성(60일 sigma 역방향) rank-Z 50/50 → long-only top-25 EW (JT1993 + AHXZ2006)",
  factor_engine_path = file.path(ROOT, "04_Research/strategies/RF_B1_3_MomLowVol/fe_rf_b1_3_momlowvol.R"),
  portfolio_spec = list(construction = "top_n_long", n_long = 25L,
                        weighting = "ew", rebalance = "monthly"),
  source_paper = list(
    url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.2006.00836.x",
    title = "The Cross-Section of Volatility and Expected Returns (Ang, Hodrick, Xing & Zhang 2006, JF 61)",
    paper_key = "doi:10.1111/j.1540-6261.2006.00836.x"),
  commission_paper = 0.0015,   # 실투형 15bps 단일 판 (sim_paper == sim_grade)
  start_date = "2005-01-01",
  out_root = file.path(ROOT, "04_Research/strategies/RF_B1_3_MomLowVol/stage_artifacts"),
  send_telegram = FALSE)
cat(sprintf("\n[B1-3] DONE grade=%s out=%s\n", res$grade, res$out_dir))
