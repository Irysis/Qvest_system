# rerun_rank.R — rank 변형 재측정(2026-11-09 · 첫 판은 FY2002 후보 1개뿐인 '직전 분포'로 FY2003 을 5분위로 갈랐다 → 엔진 수리 후 재측정)
#   첫 판 산출 = <대표>/variants/<run>_superseded_prior1 로 이름을 바꿔 남긴다(측정 기록 보존 · 인용 금지)
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT,
           QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1", QVEST_RP_SEED_BASE_CACHE = "0")
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
SDIR <- file.path(ROOT, "04_Research/strategies/RP_SESSION_piotroski2000_v2")
RD <- jsonlite::fromJSON(file.path(SDIR, "run_dirs.json"), simplifyVector = FALSE)
old <- RD$rank$out_dir
if (!is.null(old) && dir.exists(old) && !grepl("_superseded", old)) {
  nw <- paste0(old, "_superseded_prior1"); stopifnot(file.rename(old, nw)); RD$rank_superseded <- list(out_dir = nw, why = "FY2002 후보 1개 직전 분포로 FY2003 5분위 구성 — 엔진 수리 전 판")
}
TITLE <- "Value Investing: The Use of Historical Financial Statement Information to Separate Winners from Losers"
r <- run_paper_replication(
  strategy_name = "Piotroski2000_FSCORE_HighBM_v_rank",
  strategy_idea = paste("고 BM(직전 회계연도 분포 기준 최상위 5분위) 가치주 안에서 아홉 재무 이진 신호의 합 F_SCORE 로",
                        "재무 건전성이 좋은 종목(8~9)을 사고 나쁜 종목(0~1)을 판다 — 시장이 과거 재무제표 정보를 늦게 반영한다는 가설"),
  factor_engine_path = file.path(SDIR, "engine.R"),
  portfolio_spec = list(construction = "engine_direct", weighting = "paper", rebalance = "annual"),
  source_paper = list(url = "https://doi.org/10.2307/2672906", paper_key = "doi:10.2307/2672906", title = TITLE),
  commission_paper = NULL, send_telegram = FALSE,
  out_root = file.path(RD$hl$out_dir, "variants"), selection_type = "sweep", n_trials_cumulative = 3L,
  engine_vars = list(.RP_VARIANT = "rank"),
  measurement_tags = list(variant_id = "rank", variant_headline = FALSE, variant_of = basename(RD$hl$out_dir), n_variants = 3L))
RD$rank <- list(out_dir = r$out_dir, grade = r$grade, a_gate = r$a_gate$action %||% NA)
jsonlite::write_json(RD, file.path(SDIR, "run_dirs.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[session] rank 재측정 —", r$out_dir, r$grade, "\n")
