# =============================================================================
# emit_wt018.R — WT-D20260802_018 alpha_package + stage_artifacts 방출
#   (run_fq002_pilot.R 완료 후 실행. 수치는 전부 pilot_results.json 실측 소비)
#   순서 의무: alpha_package.json write → record_package_lineage (L-194)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
WT   <- "WT-D20260802_018"
MBX  <- file.path("qepm/mailbox/worktask", WT)
STG  <- file.path("stage_artifacts", paste0("WT_", gsub("^WT-", "", WT)))
dir.create(STG, recursive = TRUE, showWarnings = FALSE)

J <- fromJSON(file.path(OUTD, "pilot_results.json"), simplifyVector = TRUE)
panelA <- as.data.table(read_parquet(file.path(OUTD, "panel_A.parquet")))
MEM <- as.data.table(read_parquet(file.path(OUTD, "grid_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
Lg  <- as.data.table(read_parquet(file.path(OUTD, "grid_liq.parquet")));  Lg[, Date := as.Date(Date)]

# ── alpha_scores: 최신 시그널월 단면 (primary = A_revenue) ────────────────────
last_ym <- max(panelA$ym)
last_me <- MEM[, max(Date)]
S <- panelA[ym == last_ym, .(Ticker, score = w_ratio, w_n)]
S <- merge(S, MEM[Date == last_me, .(Ticker, Size)], by = "Ticker")
S <- merge(S, Lg[Date == last_me, .(Ticker, adv)], by = "Ticker", all.x = TRUE)
S <- S[!is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0]
zs <- (S$score - mean(S$score)) / max(sd(S$score), 1e-12)
# 기대초과수익 스케일: 실측 meanIC × 단면 수익 산포(연구 표준 선형 맵) — pilot 라벨
ic_hat <- J$ic$A_revenue$mean_ic
alpha_hat <- ic_hat * zs * 0.06   # 0.06 ≈ 단면 월수익 산포(진단 스케일, 자본 판정 아님)
S[, alpha := alpha_hat]
S[, confidence := pmin(1, pmax(0.2, 0.4 + 0.05 * pmin(w_n, 6)))]
setorder(S, -alpha)

write_parquet(S[, .(Date = last_me, Ticker, score, alpha, confidence)],
              file.path(STG, "alpha_scores.parquet"))

# ── alpha_validation.json ────────────────────────────────────────────────────
validation <- list(
  task_id = WT, measured_at = J$measured_at, grid_vintage = J$grid_vintage,
  pilot_scope = J$pilot_scope, prereg = J$prereg,
  selection_type = "chain", n_trials = 1,
  ic = J$ic[setdiff(names(J$ic), "ic_series")],
  correction_ab = J$correction_ab,
  canonical = J$canonical,
  coverage = J$coverage[setdiff(names(J$coverage), "monthly")],
  metric_type_map = list(ic = "diagnostic_statistic", canonical = "canonical_screen",
                         cells = "backtested (run_alpha_search essence)"),
  universe_comparison = NULL,
  notes = c("파일럿 — graduation HARD 미적용(사전등록 §5). 전구간 확장 판정은 IC 부호·크기.",
            "IC는 covered names 내 단면 = occurrence 통제된 magnitude 효과.",
            "canonical PORT_t는 occurrence+magnitude 혼합(포트가 covered set에서만 구성).")
)
cells_p <- file.path(OUTD, "cells_results.json")
if (file.exists(cells_p)) validation$cells <- fromJSON(cells_p, simplifyVector = TRUE)
write_json(validation, file.path(STG, "alpha_validation.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 6, null = "null")

cat("[emit] alpha_scores + alpha_validation →", STG, "\n")
cat("[emit] alpha_package.json 은 메인이 Write 도구로 직접 작성 (ast_spec_gate 경유)\n")
