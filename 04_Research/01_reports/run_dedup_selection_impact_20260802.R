## run_dedup_selection_impact_20260802.R
## ─────────────────────────────────────────────────────────────────────────────
## 선별 통계 오염 평가 — 중복 팩터는 ICIR 랭킹에서 **이중 투표**한다.
## WT-D20260802_003 의 실제 선별(trailing 36m rank-IC ICIR top-20, anchor 2026-01-31)
## 을 원장으로 삼아, 중복 붕괴(collapse) 전/후 풀을 대조한다.
## 읽기 전용 — WT 산출물은 동결(artifact-storage §1 ①).
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
QM_DATA <- Sys.getenv("QM_DATA", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM_CODE <- Sys.getenv("QM_CODE", QM_DATA)
setwd(QM_DATA)
OUT <- file.path(QM_CODE, "04_Research/01_reports")
logf <- file.path(OUT, "_dedup_selection_impact_20260802.txt")
con <- file(logf, "w", encoding = "UTF-8")
w  <- function(...) { m <- paste0(...); writeLines(m, con); flush(con); cat(m, "\n") }
wf <- function(...) w(sprintf(...))

full <- readRDS("stage_artifacts/WT_D20260802_003/wt003_full_20260802.rds")
POOL <- full$ANCH_last$pool
ICIR <- full$ANCH_last$icir
TT   <- full$ANCH_last$tt
K    <- length(POOL)
wf("=== dedup selection impact === anchor=%s  K=%d  |ICIR universe|=%d",
   as.character(full$ANCH_last$anchor_date), K, length(ICIR))

sig <- as.data.table(read_parquet(file.path(OUT, "factor_dup_signal_pairs_20260802.parquet")))
dup <- sig[both_approved == TRUE & verdict %in% c("EXACT_DUP", "NEAR_DUP")]

## ── 중복 그룹화 (연결 성분) ─────────────────────────────────────────────────
.components <- function(pairs) {
  nodes <- unique(c(pairs$factor_a, pairs$factor_b))
  parent <- setNames(nodes, nodes)
  find <- function(x) { while (parent[[x]] != x) x <- parent[[x]]; x }
  for (i in seq_len(nrow(pairs))) {
    ra <- find(pairs$factor_a[i]); rb <- find(pairs$factor_b[i])
    if (ra != rb) parent[[rb]] <- ra
  }
  split(nodes, vapply(nodes, find, character(1)))
}
GRP_EXACT <- .components(dup[verdict == "EXACT_DUP"])
GRP_ALL   <- .components(dup)

w("")
w("--- EXACT_DUP 그룹 (|median cor| >= 0.99) ---")
for (g in GRP_EXACT) wf("  {%s}", paste(sort(g), collapse = ", "))
w("--- EXACT+NEAR 그룹 (>= 0.95) ---")
for (g in GRP_ALL) wf("  {%s}", paste(sort(g), collapse = ", "))

## ── 풀 안의 중복 점유 ────────────────────────────────────────────────────────
w("")
w("--- WT-003 ICIR top-20 풀에서 중복이 차지한 슬롯 ---")
occupancy <- function(groups, label) {
  used <- 0L
  for (g in groups) {
    inpool <- intersect(g, POOL)
    if (length(inpool) >= 2L) {
      used <- used + (length(inpool) - 1L)
      wf("  [%s] {%s} -> 풀 안 %d개 (여분 %d슬롯)  ICIR=%s",
         label, paste(sort(inpool), collapse = ", "), length(inpool), length(inpool) - 1L,
         paste(sprintf("%.6f", ICIR[inpool]), collapse = " / "))
    }
  }
  used
}
waste_exact <- occupancy(GRP_EXACT, "EXACT")
waste_all   <- occupancy(GRP_ALL,   "ALL  ")
wf("  => 여분 슬롯: EXACT 기준 %d / %d  (유효 폭 %d)", waste_exact, K, K - waste_exact)
wf("  => 여분 슬롯: EXACT+NEAR 기준 %d / %d  (유효 폭 %d)", waste_all, K, K - waste_all)

## ── 붕괴 후 재선별 ───────────────────────────────────────────────────────────
## canonical = 그룹 내 ICIR 최대(동률이면 코드 사전순) — 선별 규율 자체는 불변,
## 중복만 1개로 접고 나머지를 후보에서 제거한 뒤 동일하게 top-K.
collapse_reselect <- function(groups, label) {
  drop <- character(0)
  for (g in groups) {
    if (length(g) < 2L) next
    sc <- ICIR[g]; sc[is.na(sc)] <- -Inf
    keep <- names(sort(sc, decreasing = TRUE))[1]
    if (is.na(keep) || is.null(keep)) keep <- sort(g)[1]
    drop <- c(drop, setdiff(g, keep))
  }
  cand <- ICIR[!names(ICIR) %in% drop]
  newpool <- names(head(sort(cand, decreasing = TRUE), K))
  w("")
  wf("--- [%s] 중복 붕괴 후 재선별 (drop %d) ---", label, length(drop))
  wf("  들어옴: %s", paste(setdiff(newpool, POOL), collapse = ", "))
  wf("  나감  : %s", paste(setdiff(POOL, newpool), collapse = ", "))
  wf("  Jaccard(old, new) = %.3f",
     length(intersect(POOL, newpool)) / length(union(POOL, newpool)))
  newpool
}
NP_EXACT <- collapse_reselect(GRP_EXACT, "EXACT")
NP_ALL   <- collapse_reselect(GRP_ALL,   "EXACT+NEAR")

## ── EW 합성에서의 신호별 실효 비중 ───────────────────────────────────────────
w("")
w("--- base_icir_EW (팩터 EW) 에서 중복 클러스터의 실효 비중 ---")
for (g in GRP_ALL) {
  inpool <- intersect(g, POOL)
  if (length(inpool) >= 2L)
    wf("  {%s}: %d/%d 슬롯 = %.1f%% (de-dup 시 %.1f%%)",
       paste(sort(inpool), collapse=", "), length(inpool), K,
       100 * length(inpool) / K, 100 / K)
}

## ── 승인 게이트 통계의 동일성 (approved_factor_library) ─────────────────────
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
w("")
w("--- approved 게이트 통계가 중복 쌍에서 동일한가 (이중 승인 증거) ---")
for (i in seq_len(nrow(dup[verdict == "EXACT_DUP"]))) {
  a <- dup[verdict == "EXACT_DUP"][i, factor_a]; b <- dup[verdict == "EXACT_DUP"][i, factor_b]
  ra <- af[factor_id == a]; rb <- af[factor_id == b]
  if (!nrow(ra) || !nrow(rb)) next
  same <- isTRUE(all.equal(ra$rank_ic_ir[1], rb$rank_ic_ir[1], tolerance = 1e-6)) &&
          isTRUE(all.equal(ra$portfolio_alpha_t_nw[1], rb$portfolio_alpha_t_nw[1], tolerance = 1e-6))
  wf("  %-32s ~ %-32s ic_ir %.4f/%.4f  port_t %+.3f/%+.3f  %s",
     a, b, ra$rank_ic_ir[1], rb$rank_ic_ir[1],
     ra$portfolio_alpha_t_nw[1], rb$portfolio_alpha_t_nw[1],
     if (same) "<< 통계 동일" else "")
}

res <- list(
  anchor = as.character(full$ANCH_last$anchor_date), K = K,
  wasted_slots_exact = waste_exact, wasted_slots_all = waste_all,
  pool_old = POOL, pool_collapsed_exact = NP_EXACT, pool_collapsed_all = NP_ALL,
  groups_exact = unname(lapply(GRP_EXACT, sort)),
  groups_all = unname(lapply(GRP_ALL, sort)),
  metric_type = "selection_bookkeeping (재선별은 저장 ICIR 원장 기반 — 수익 재측정 아님)"
)
write_json(res, file.path(OUT, "dedup_selection_impact_20260802.json"),
           auto_unbox = TRUE, pretty = TRUE)
wf("\nsaved: %s", file.path(OUT, "dedup_selection_impact_20260802.json"))
close(con)
