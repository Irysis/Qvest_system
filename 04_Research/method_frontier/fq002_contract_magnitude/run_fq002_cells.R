# =============================================================================
# run_fq002_cells.R — FQ-002 사전등록 4셀 (DENOM {revenue,size} × weight {equal,ivol})
#   run_alpha_search() 정본 러너 · n_holdings=20 · 전량 보고 · 셀 선택 없음(sweep 아님)
#   send_telegram=FALSE — 최종 보고는 WT-D20260802_018 tg_agent_brief 1건으로 통합
#   (파일럿 판정 권위 = IC 부호·크기. 셀 시뮬은 부호 일치 판정 + 참고 성과)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"

source("02_Infrastructure/alpha_search/run_alpha_search.R")

ENG <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_contract.R")
# Panel A(최초 체결값·WINDOW 12·SCOPE all)를 명시 지정 — run_fq002_pilot.R 산출 소비
PANEL_A <- file.path(ROOT, OUTD, "panel_A.parquet")
stopifnot(file.exists(PANEL_A))
Sys.setenv(CONTRACT_PANEL = PANEL_A)
cells <- list(
  list(denom = "revenue", w = "equal"),
  list(denom = "revenue", w = "ivol"),
  list(denom = "size",    w = "equal"),
  list(denom = "size",    w = "ivol")
)
res <- list()
for (cl in cells) {
  key <- sprintf("%s_%s", cl$denom, cl$w)
  Sys.setenv(DENOM = cl$denom)
  cat(sprintf("\n########## FQ-002 cell %s ##########\n", key))
  r <- tryCatch(
    run_alpha_search(
      strategy_name = sprintf("CTR_MAG12_%s_%s", toupper(cl$denom), cl$w),
      strategy_idea = paste0("FQ-002 계약수주 magnitude 파일럿(WT-D20260802_018): 공시 계약금액 ",
                             "12M 누적 상대규모(", cl$denom, " 분모) long-side directional. ",
                             "사전등록 4셀 중 ", key, ". pilot_scope=2023-08..2026-07 크롤(전구간 아님)."),
      factor_engine_path = ENG,
      n_holdings = 20L,
      weight_method = cl$w,
      commission = 0.0015,
      start_date = "2023-01-01",
      send_telegram = FALSE
    ),
    error = function(e) list(error = conditionMessage(e)))
  res[[key]] <- if (!is.null(r$error)) list(error = r$error) else
    list(strategy_id = r$strategy_id, grade = r$grade, score = r$score,
         pass = r$pass, excess_cagr = r$excess_cagr, out_dir = r$out_dir,
         essence = tryCatch(r$authoritative$essence, error = function(e) NULL))
  Sys.unsetenv("DENOM")
}
write_json(res, file.path(OUTD, "cells_results.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null", force = TRUE)
cat("\n[cells] → ", file.path(OUTD, "cells_results.json"), "\n")
