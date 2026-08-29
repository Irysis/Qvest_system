#!/usr/bin/env Rscript
#==============================================================================
# essence_regrade_apply.R — v9.21 §1-d 재계산표의 **원장 반영** (도훈 승인 2026-08-24)
#
# ★반영 원칙 = **병기(annotate)이지 덮어쓰기가 아니다.**
#   원장은 역사다. 과거 L-code 의 `grade` 를 덮으면 "그때 그렇게 판정했다" 는 사실이 사라진다.
#   이 저장소가 같은 날 개명에서 지킨 규약과 동일하다 — `factor_rotation` 을 enum 에서 빼지 않았고
#   (원장 1건이 그 값을 갖는다), hurdle 의 구조 사유 문자열도 판정에서 뺄 때 남겼다.
#   ⇒ 기존 `grade` 는 **그대로 두고** 권위 등급을 별도 필드로 **덧붙인다.**
#
# 반영 대상 2곳 (실측 조인):
#   ① stage_artifacts/l_code/**/*.json  — 132 / 423 (strategy_id 조인)
#        + essence_grade          : 권위 등급 (A/B/C/F, 미발행은 null)
#        + essence_regrade        : { ref · applied_at · grade_at_emit · proxy_grade · 지표 }
#   ② 06_Registry/module_catalog.json   — 200 / 275
#        + meta.essence_grade     : 권위 등급  ← run_alpha_search 6c 가 신규 등재에 쓰는 자리와 동일
#        + meta.essence_regrade_ref
#
# ★건드리지 않는 것: 기존 `grade` · `grade_raw` · `score` · top-level 판정 필드 전부.
#   `.cache/lcode_corpus.json` 은 **캐시**라 여기서 쓰지 않는다 — 원본 반영 후 재생성한다.
#   `qepm/mailbox/governor/book_state.json` 은 **도훈만** 쓴다(자동화 금지) — 이 스크립트는 접근하지 않는다.
#
# 실행:
#   Rscript 02_Infrastructure/ops/essence_regrade_apply.R              # dry-run (기본)
#   Rscript 02_Infrastructure/ops/essence_regrade_apply.R --apply      # 실제 반영
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

.root <- function() {
  for (c0 in c(Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(c0)) next
    c0 <- gsub("\\\\", "/", c0)
    if (file.exists(file.path(c0, "CLAUDE.md")) && dir.exists(file.path(c0, "06_Registry"))) return(c0)
  }
  stop("프로젝트 루트 해석 실패 — QM_ROOT 확인")
}
ROOT <- .root(); setwd(ROOT)

args  <- commandArgs(trailingOnly = TRUE)
APPLY <- "--apply" %in% args
STAMP <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
REF   <- "essence_regrade_20260824"
cat(sprintf("[apply] 모드 = %s\n", if (APPLY) "★실반영" else "dry-run (기본)"))

RG <- fromJSON(file.path(ROOT, "06_Registry", "essence_regrade_20260824.json"),
               simplifyVector = FALSE)
rows <- RG$rows
# 재계산표는 data.table 직렬화라 열-지향일 수 있다 — 두 형태를 모두 흡수한다.
if (!is.null(rows$strategy_id) && is.null(rows[[1]]$strategy_id)) {
  n <- length(rows$strategy_id)
  rows <- lapply(seq_len(n), function(i) lapply(rows, function(col) col[[i]]))
}
## ★`%||%` 를 **명시 정의**한다 — base 상속에 기대지 않는다.
##   R 4.4 부터 base 에 있지만 판본에 따라 없고, 없으면 조용히 다른 것을 찾아 쓴다.
##   같은 함정을 이 저장소가 두 번 기록했다(essence_score.R:590 · close_round.R 주석).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.chr <- function(x) if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x)[1]
.num <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else suppressWarnings(as.numeric(x)[1])

BY <- list()
for (r in rows) {
  sid <- .chr(r$strategy_id)
  if (is.na(sid) || !nzchar(sid)) next
  BY[[sid]] <- r
}
cat(sprintf("[apply] 재계산표 %d행 · strategy_id 색인 %d건\n", length(rows), length(BY)))

## 권위 등급 정규화 — 표의 "NA" 문자열은 **미발행**이지 등급이 아니다.
.grade_of <- function(r) {
  g <- .chr(r$new_grade)
  if (is.na(g) || !nzchar(g) || identical(g, "NA")) NULL else g
}

# ── ① L-code 원본 ────────────────────────────────────────────────────────────
lc_files <- list.files(file.path(ROOT, "stage_artifacts", "l_code"),
                       pattern = "\\.json$", recursive = TRUE, full.names = TRUE)
lc_hit <- 0L; lc_skip_nojoin <- 0L; lc_bad <- 0L; lc_grade_kept <- 0L
lc_dist <- list()
for (f in lc_files) {
  y <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(y)) { lc_bad <- lc_bad + 1L; next }
  sid <- .chr(y$strategy_id)
  r <- if (!is.na(sid)) BY[[sid]] else NULL
  if (is.null(r)) { lc_skip_nojoin <- lc_skip_nojoin + 1L; next }

  eg <- .grade_of(r)
  key <- if (is.null(eg)) "미발행" else eg
  lc_dist[[key]] <- (lc_dist[[key]] %||% 0L) + 1L

  ## ★기존 grade 는 손대지 않는다 — 그 값이 "발행 시점의 판정"이라는 사실이 근거다.
  y$essence_grade <- eg                       # NULL 이면 필드가 안 실린다(미발행 = 없음)
  y$essence_regrade <- list(
    ref            = REF,
    applied_at     = STAMP,
    basis          = "essence_score.R (v9.21 권위 등급) — bt_result.rds 재채점",
    grade_at_emit  = .chr(y$grade),           # 발행 시점 판정(불변 보존, 대조용 사본)
    proxy_grade    = .chr(r$proxy_grade),
    metric_type    = .chr(r$metric_type),
    structural_drawdown = isTRUE(r$structural_drawdown),
    port_t = .num(r$port_t), net_ir = .num(r$net_ir),
    calmar = .num(r$calmar), mdd = .num(r$mdd),
    note = paste("판정 축 병기 — 기존 `grade` 는 발행 시점 기록으로 불변.",
                 "MDD 는 등급을 접지 않는다(2026-08-24): 구조 낙폭은 structural_drawdown 라벨로만 남는다.")
  )
  if (identical(.chr(y$grade), .chr(y$essence_regrade$grade_at_emit))) lc_grade_kept <- lc_grade_kept + 1L
  lc_hit <- lc_hit + 1L
  if (APPLY) {
    tmp <- paste0(f, ".tmp")
    write(toJSON(y, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 8), tmp)
    file.rename(tmp, f)
  }
}
cat(sprintf("[apply] ① L-code 원본: 조인 %d / 전체 %d (미조인 %d · 판독실패 %d)\n",
            lc_hit, length(lc_files), lc_skip_nojoin, lc_bad))
cat("        권위 등급 분포:",
    paste(sprintf("%s %d", names(lc_dist), unlist(lc_dist)), collapse = " · "), "\n")
cat(sprintf("        기존 grade 무손상 확인: %d / %d\n", lc_grade_kept, lc_hit))

# ── ② module_catalog ─────────────────────────────────────────────────────────
mcp <- file.path(ROOT, "06_Registry", "module_catalog.json")
MC <- fromJSON(mcp, simplifyVector = FALSE)
mods <- MC$modules
mc_hit <- 0L; mc_dist <- list()
for (k in names(mods)) {
  sid <- .chr(mods[[k]]$strategy_id); if (is.na(sid)) sid <- k
  r <- BY[[sid]]; if (is.null(r)) next
  eg <- .grade_of(r)
  key <- if (is.null(eg)) "미발행" else eg
  mc_dist[[key]] <- (mc_dist[[key]] %||% 0L) + 1L
  if (is.null(mods[[k]]$meta)) mods[[k]]$meta <- list()
  ## ★신규 등재가 쓰는 자리와 **같은 필드**에 채운다(run_alpha_search 6c meta$essence_grade).
  ##   backfill 과 신규가 다른 자리에 쌓이면 소비자가 둘을 다 봐야 한다 = 드리프트 경로.
  mods[[k]]$meta$essence_grade <- eg
  mods[[k]]$meta$essence_regrade_ref <- REF
  mods[[k]]$meta$essence_regrade_at <- STAMP
  mc_hit <- mc_hit + 1L
}
cat(sprintf("[apply] ② module_catalog: 조인 %d / 전체 %d\n", mc_hit, length(mods)))
cat("        권위 등급 분포:",
    paste(sprintf("%s %d", names(mc_dist), unlist(mc_dist)), collapse = " · "), "\n")
if (APPLY) {
  MC$modules <- mods
  MC$last_updated <- STAMP
  MC$essence_regrade <- list(ref = REF, applied_at = STAMP, n_annotated = mc_hit,
                             note = "meta.essence_grade 병기. top-level grade 는 불변(발행 시점 기록).")
  tmp <- paste0(mcp, ".tmp")
  write(toJSON(MC, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 8), tmp)
  file.rename(tmp, mcp)
}

cat(sprintf("\n[apply] %s\n", if (APPLY)
  "★반영 완료 — 다음: corpus 캐시 재생성 후 검증. 롤백 = git checkout (두 경로 모두 추적됨)." else
  "dry-run 종료 — 실제 반영은 --apply. 아무것도 쓰지 않았다."))
