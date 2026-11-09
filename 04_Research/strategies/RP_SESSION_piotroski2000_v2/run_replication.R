# run_replication.R — Piotroski (2000) 충실구현 측정(세션 · 2026-11-09 · 퀀티 재무 DB v2 직접 판독)
#   대표 hl = chain/1(권위) → 나머지 ha · rank = sweep(n = 3 · DSR 대상) · 산출 = <대표>/variants/
#   v2 전환 전 판독 — 원장 · 풀 · L-code 부작용 끔(QVEST_RP_REGISTER=0 · QVEST_RP_NO_LCODE=1 · QVEST_NO_LEDGER_OPEN=1) · 텔레그램 끔
#   실행: 프로젝트 루트에서 Rscript 04_Research/strategies/RP_SESSION_piotroski2000_v2/run_replication.R
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT,
           QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1", QVEST_RP_SEED_BASE_CACHE = "0")
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))
SDIR <- file.path(ROOT, "04_Research/strategies/RP_SESSION_piotroski2000_v2")
ENG  <- file.path(SDIR, "engine.R")
TITLE <- "Value Investing: The Use of Historical Financial Statement Information to Separate Winners from Losers"
base <- list(
  strategy_name = "Piotroski2000_FSCORE_HighBM",
  strategy_idea = paste("고 BM(직전 회계연도 분포 기준 최상위 5분위) 가치주 안에서 아홉 재무 이진 신호의 합 F_SCORE 로",
                        "재무 건전성이 좋은 종목(8~9)을 사고 나쁜 종목(0~1)을 판다 — 시장이 과거 재무제표 정보를 늦게 반영한다는 가설"),
  factor_engine_path = ENG,
  portfolio_spec = list(construction = "engine_direct", weighting = "paper", rebalance = "annual"),
  source_paper = list(url = "https://doi.org/10.2307/2672906", paper_key = "doi:10.2307/2672906", title = TITLE),
  commission_paper = NULL, send_telegram = FALSE)

t0 <- Sys.time()
r_hl <- do.call(run_paper_replication, base)
cat(sprintf("[session] 대표 hl 완료 — %s · 등급 %s · %.1f분\n", r_hl$out_dir, r_hl$grade, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
out <- list(hl = list(out_dir = r_hl$out_dir, grade = r_hl$grade, a_gate = r_hl$a_gate$action %||% NA))
for (v in c("ha", "rank")) {
  t1 <- Sys.time()
  args <- utils::modifyList(base, list(
    strategy_name = paste0(base$strategy_name, "_v_", v),
    out_root = file.path(r_hl$out_dir, "variants"),
    selection_type = "sweep", n_trials_cumulative = 3L,
    engine_vars = list(.RP_VARIANT = v),
    measurement_tags = list(variant_id = v, variant_headline = FALSE, variant_of = basename(r_hl$out_dir), n_variants = 3L)))
  r <- tryCatch(do.call(run_paper_replication, args), error = function(e) list(err = conditionMessage(e)))
  out[[v]] <- if (!is.null(r$err)) list(err = r$err) else list(out_dir = r$out_dir, grade = r$grade, a_gate = r$a_gate$action %||% NA)
  cat(sprintf("[session] 변형 %s — %s · %.1f분\n", v, if (!is.null(r$err)) paste("실패:", r$err) else r$grade,
              as.numeric(difftime(Sys.time(), t1, units = "mins"))))
}
jsonlite::write_json(out, file.path(SDIR, "run_dirs.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[session] 끝 —", file.path(SDIR, "run_dirs.json"), "\n")
