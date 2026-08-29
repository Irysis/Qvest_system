#!/usr/bin/env Rscript
#==============================================================================
# essence_regrade_20260824.R — v9.21 §1-d 전수 재계산표 (보고 전용, 원장 미수정)
#
# 왜 3열인가 — **두 원인을 분리하지 않으면 표가 아무것도 말하지 않는다.**
#   2026-08-24 재채점에서 두 변화가 겹쳐 있는 것이 실측됐다:
#     ① 이번 지시(도훈): essence 의 `hard_fail` 에서 MDD 추론을 걷어냄
#     ② **선행 드리프트**: 저장된 산출물의 drawdown 프로파일을 현행 코드가 재현하지 못한다
#        (같은 rds·같은 mdd_hard 0.45 인데 2026-06-12 저장분 2 에피소드/2021기간/frac 0.3838
#         vs 현행 8/391/frac 0.0742 = 5.2배. 저장 JSON 에 catastrophic/hard_count 계열 5필드 없음)
#   ⇒ 한 열만 내면 "재계산 때문에 바뀐 것"과 "이미 갈라져 있던 것"이 같은 숫자에 섞인다.
#
#   열 정의:
#     old_grade  = 저장된 essence_grade (authoritative_remeasure.json). 없으면 NA.
#     cf_grade   = **반사실**: 현행 코드 + MDD 추론 복원(hard_fail = structural_drawdown 주입).
#                  → (cf_grade − old_grade) = ②선행 드리프트만의 효과
#     new_grade  = 현행 코드 그대로 (MDD 추론 제거).
#                  → (new_grade − cf_grade) = ①이번 지시만의 효과
#
# ★원장을 쓰지 않는다. 산출은 06_Registry/essence_regrade_20260824.json 1건뿐이고,
#   L-code corpus · module_catalog 반영은 **도훈 확인 후** 별도 단계다(플랜 §1-d).
#
# 실행: Rscript 02_Infrastructure/ops/essence_regrade_20260824.R [--limit N]
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.root <- function() {
  for (c0 in c(Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(c0)) next
    c0 <- gsub("\\\\", "/", c0)
    if (file.exists(file.path(c0, "CLAUDE.md")) && dir.exists(file.path(c0, "06_Registry")))
      return(c0)
  }
  stop("프로젝트 루트 해석 실패 — QM_ROOT 확인")
}
ROOT <- .root(); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "contracts", "essence_score.R"))

args  <- commandArgs(trailingOnly = TRUE)
LIMIT <- if ("--limit" %in% args) as.integer(args[which(args == "--limit") + 1L]) else NA_integer_

runs <- list.dirs(file.path(ROOT, "stage_artifacts", "alpha_search"),
                  recursive = FALSE, full.names = TRUE)
runs <- runs[file.exists(file.path(runs, "bt_result.rds"))]
if (!is.na(LIMIT) && LIMIT > 0L) runs <- head(runs, LIMIT)
cat(sprintf("[regrade] bt_result.rds 보유 런: %d\n", length(runs)))

.g <- function(x) if (is.null(x) || length(x) == 0L || is.na(x[1])) NA_character_ else as.character(x[1])
.n <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else suppressWarnings(as.numeric(x[1]))

rows <- vector("list", length(runs))
for (i in seq_along(runs)) {
  d <- runs[i]
  if (i %% 25L == 0L) cat(sprintf("  … %d/%d\n", i, length(runs)))
  bt <- tryCatch(readRDS(file.path(d, "bt_result.rds")), error = function(e) NULL)
  if (is.null(bt)) { rows[[i]] <- data.table(dir = basename(d), status = "unreadable_rds"); next }

  ar <- tryCatch(fromJSON(file.path(d, "authoritative_remeasure.json")), error = function(e) NULL)
  hr <- tryCatch(fromJSON(file.path(d, "hurdle_result.json")), error = function(e) NULL)

  es <- tryCatch(essence_score(bt, selection_type = "chain"), error = function(e) NULL)
  if (is.null(es)) { rows[[i]] <- data.table(dir = basename(d), status = "essence_error"); next }

  # 반사실 = 구 동작 복원. 구판은 `hard_fail <- isTRUE(dd_profile$structural_hard_fail)` 였고
  #   그 값이 지금은 `structural_drawdown` 로 반환된다 ⇒ 그걸 주입하면 구 판정이 재현된다.
  cf <- if (isTRUE(es$structural_drawdown))
          tryCatch(essence_score(bt, selection_type = "chain", hard_fail = TRUE),
                   error = function(e) NULL) else es
  if (is.null(cf)) cf <- es

  rows[[i]] <- data.table(
    dir         = basename(d),
    status      = "ok",
    strategy_id = .g(if (!is.null(ar)) ar$strategy_id else bt$manifest$strategy_id),
    old_grade   = .g(if (!is.null(ar)) ar$essence_grade else NA),
    cf_grade    = .g(cf$grade),
    new_grade   = .g(es$grade),
    proxy_grade = .g(if (!is.null(hr)) hr$grade else NA),
    metric_type = .g(es$metric_type),
    structural_drawdown = isTRUE(es$structural_drawdown),
    old_structural      = isTRUE(if (!is.null(ar)) ar$hard_fail else NA),
    port_t = .n(es$essence$portfolio_alpha_t_nw_lag3), net_ir = .n(es$essence$net_ir),
    oos    = .n(es$essence$oos_retention), calmar = .n(es$essence$calmar),
    mdd    = .n(es$essence$mdd), cagr = .n(es$essence$cagr), sharpe = .n(es$essence$net_sharpe))
}
R <- rbindlist(rows, fill = TRUE)
ok <- R[status == "ok"]

# ★행/열을 **명시 인덱싱**한다. 구판은 `as.integer(t)`(열-우선 평탄화)에 행-우선으로 만든
#   이름을 붙여 전이표가 **전치**됐다 — R 콘솔의 table() 출력과 JSON 이 서로 다른 말을 했다
#   (예: 실제 `C->C 138` 이 JSON 에 `C->F 138` 로 실렸다). 평탄화 순서를 가정하지 않는다.
.tab <- function(a, b) {
  t <- table(ifelse(is.na(a), "NA", a), ifelse(is.na(b), "NA", b))
  out <- list()
  for (r in rownames(t)) for (c in colnames(t)) out[[paste(r, c, sep = "->")]] <- as.integer(t[r, c])
  out
}
.cnt <- function(x) as.list(table(ifelse(is.na(x), "NA", x)))

cat("\n== 등급 분포 ==\n")
cat("  proxy(hurdle) :"); print(.cnt(ok$proxy_grade))
cat("  old(저장 essence):"); print(.cnt(ok$old_grade))
cat("  cf(드리프트만) :"); print(.cnt(ok$cf_grade))
cat("  new(현행 전체) :"); print(.cnt(ok$new_grade))
cat("\n== ②선행 드리프트 효과 (old -> cf) ==\n"); print(table(ok$old_grade, ok$cf_grade))
cat("\n== ①MDD 탈락 제거 효과 (cf -> new) ==\n"); print(table(ok$cf_grade, ok$new_grade))

out <- list(
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = paste("v9.21 §1-d 전수 재계산표. 보고 전용 — 원장(L-code corpus · module_catalog)",
                  "반영은 도훈 확인 후 별도 단계."),
  column_semantics = list(
    old_grade = "저장된 authoritative_remeasure.json::essence_grade (없으면 null)",
    cf_grade  = "반사실: 현행 코드 + MDD 추론 복원 → 선행 드리프트만의 효과",
    new_grade = "현행 코드 (2026-08-24 도훈 지시 반영: MDD 가 등급을 접지 않는다)",
    proxy_grade = "hurdle_gate 18-component (2026-05-31 DEMOTED — 진단 축)"),
  caveat = paste("★old 열은 현행 코드가 재현하지 못하는 drawdown 프로파일 위에서 만들어졌다",
                 "(같은 rds·같은 mdd_hard 0.45 인데 저장분과 현행이 5.2배 차이).",
                 "그래서 old->new 를 한 걸음으로 읽으면 두 원인이 섞인다. cf 열이 분리한다."),
  n_runs = nrow(R), n_ok = nrow(ok),
  distribution = list(proxy = .cnt(ok$proxy_grade), old = .cnt(ok$old_grade),
                      cf = .cnt(ok$cf_grade), new = .cnt(ok$new_grade)),
  transition_drift_old_to_cf = .tab(ok$old_grade, ok$cf_grade),
  transition_mdd_cf_to_new   = .tab(ok$cf_grade, ok$new_grade),
  transition_proxy_to_new    = .tab(ok$proxy_grade, ok$new_grade),
  structural_label = list(current = sum(ok$structural_drawdown),
                          stored  = sum(ok$old_structural, na.rm = TRUE)),
  rows = ok)

op <- file.path(ROOT, "06_Registry", "essence_regrade_20260824.json")
tmp <- paste0(op, ".tmp")
write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 6), tmp)
file.rename(tmp, op)
cat(sprintf("\n[regrade] 표 발행: %s  (ok %d / %d)\n", op, nrow(ok), nrow(R)))
cat("[regrade] ★원장 미수정 — 반영은 도훈 확인 후.\n")
