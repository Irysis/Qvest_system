## ============================================================================
## reconcile_module_registries.R — module_catalog ↔ module_quarantine 상호배타 정리
## ----------------------------------------------------------------------------
## 신설 2026-08-02. 대상 원장:
##   06_Registry/module_catalog.json   (.modules)
##   06_Registry/module_quarantine.json(.modules / .superseded)
##
## 계약(register_module.R 헤더 참조): 하나의 strategy_id 는 두 원장의 `modules` 중
## **최대 한 곳**에만 존재한다. 구판 .upsert_registry() 는 catalog 승격 시 기존
## quarantine 행을 회수하지 않아, run_alpha_search 의 2회 등록(6c proxy → 6e backtested)이
## 같은 전략을 두 원장에 상반된 상태로 남겼다. quarantine 만 읽는 소비자는 최종상태를
## **정반대로** 읽는다(fr_eligible=FALSE = 기각처럼 보이나 실제 최종은 FR_ELIGIBLE).
##
## 본 스크립트는 그 소급분을 정리한다. tombstone 모양은 register_module.R 의
## .supersede_quarantine() 을 **재사용**한다 — 여기서 형태를 재구현하면 원장 스키마가
## 두 벌로 갈라져 나중에 한쪽만 바뀐다(선례: 리더가 술어를 재구현해 수리가 안 닿은 건).
##
## 사용:
##   Rscript 02_Infrastructure/tools/reconcile_module_registries.R          # dry-run (기본)
##   Rscript 02_Infrastructure/tools/reconcile_module_registries.R --apply  # 실제 반영
## 종료코드: 미해소 중복이 남으면 1, 아니면 0 (dry-run 에서 중복 발견 시에도 1).
## ============================================================================
suppressMessages({ library(jsonlite) })

.args  <- commandArgs(trailingOnly = TRUE)
APPLY  <- "--apply" %in% .args

## 프로젝트 루트: 스크립트 위치에서 역산(호출 위치 무관) → env → r-portability 금칙 ③ 정합.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
ROOT <- if (!is.na(.self) && nzchar(.self)) {
  normalizePath(file.path(dirname(.self), "..", ".."), winslash = "/", mustWork = FALSE)
} else NA_character_
.is_root <- function(p) !is.na(p) && nzchar(p) &&
  file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))
if (!.is_root(ROOT)) {
  for (cand in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (nzchar(cand)) {
      p <- normalizePath(cand, winslash = "/", mustWork = FALSE)
      if (.is_root(p)) { ROOT <- p; break }
    }
  }
}
if (!.is_root(ROOT)) stop("[reconcile] project root 판별 실패 (CLAUDE.md + 06_Registry marker 부재)")

PROJECT_ROOT <- ROOT   # register_module.R 의 .RM_ROOT() 가 이 값을 우선 사용
source(file.path(ROOT, "02_Infrastructure", "contracts", "register_module.R"))

CAT_P <- file.path(ROOT, "06_Registry", "module_catalog.json")
QUA_P <- file.path(ROOT, "06_Registry", "module_quarantine.json")
cat(sprintf("[reconcile] root=%s  mode=%s\n", ROOT, if (APPLY) "APPLY" else "DRY-RUN"))

read_obj <- function(p) {
  if (!file.exists(p)) stop(sprintf("[reconcile] 원장 부재: %s", p))
  o <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(o)) stop(sprintf("[reconcile] 원장 파싱 실패: %s", p))
  o
}

cj <- read_obj(CAT_P); qj <- read_obj(QUA_P)
cm <- cj$modules %||% list(); qm <- qj$modules %||% list()
qs <- qj$superseded %||% list()
dupes <- intersect(names(cm), names(qm))
## 축2: modules ↔ superseded 서로소. register_module 은 .upsert_registry 에서 이를 보장하지만
## **원장을 쓰는 writer 가 register_module 뿐이 아니다** — 예: batch434 감사도구
## (04_Research/.../patch_catalog_label_annotations.R:68-84) 는 --quarantine-mismatch 로
## catalog→quarantine 직접 이동을 하며 .upsert_registry 를 우회한다(이동 자체는 정상이나
## 낡은 tombstone 을 못 지운다). 모든 writer 를 쫓는 대신 **누가 깼든 스크린이 잡게** 한다.
stale_tomb <- intersect(names(qm), names(qs))
cat(sprintf("[reconcile] catalog.modules=%d  quarantine.modules=%d  quarantine.superseded=%d\n",
            length(cm), length(qm), length(qs)))
cat(sprintf("[reconcile] 중복(양쪽 modules 동시 등재) = %d건\n", length(dupes)))
cat(sprintf("[reconcile] 낡은 tombstone(modules ∧ superseded 동시) = %d건\n", length(stale_tomb)))

if (length(stale_tomb)) {
  ## live 격리행이 권위 — tombstone 이 낡은 것이므로 tombstone 을 제거한다.
  for (id in stale_tomb) cat(sprintf("  - %s → %s 낡은 tombstone 제거\n", id, if (APPLY) "APPLY" else "WOULD"))
  if (APPLY) {
    o <- read_obj(QUA_P)
    for (id in stale_tomb) o$superseded[[id]] <- NULL
    o$n_superseded <- length(o$superseded %||% list())
    write_json(o, QUA_P, auto_unbox = TRUE, pretty = TRUE, na = "null")
  }
}

if (!length(dupes)) {
  if (!length(stale_tomb)) {
    cat("[reconcile] 정리할 항목 없음 — 상호배타 계약 충족.\n")
    quit(save = "no", status = 0L)
  }
  qj3 <- read_obj(QUA_P)
  left2 <- intersect(names(qj3$modules %||% list()), names(qj3$superseded %||% list()))
  cat(sprintf("[reconcile] 축2 처리 완료 · 잔존 %d건\n", length(left2)))
  quit(save = "no", status = if (length(left2) > 0L) 1L else 0L)
}

## 어느 쪽이 권위인가: 증거 tier 가 먼저다(measurement-graduation §1 — proxy 는
## backtested 를 뒤집지 못한다). 시계는 tombstone mode 라벨에만 쓴다.
skipped <- character(0); fixed <- character(0)
for (id in dupes) {
  ce <- cm[[id]]; qe <- qm[[id]]
  c_auth <- isTRUE(ce$fr_eligible) && identical(as.character(ce$metric_type), "backtested")
  q_auth <- isTRUE(qe$fr_eligible) && identical(as.character(qe$metric_type), "backtested")
  cat(sprintf("  - %s\n      catalog   : grade=%-3s fr=%-5s metric=%-10s reg=%s\n      quarantine: grade=%-3s fr=%-5s metric=%-10s reg=%s\n",
              id,
              as.character(ce$grade), as.character(ce$fr_eligible),
              as.character(ce$metric_type), as.character(ce$registered_at),
              as.character(qe$grade), as.character(qe$fr_eligible),
              as.character(qe$metric_type), as.character(qe$registered_at)))
  if (!c_auth || q_auth) {
    ## 자동 판정 불가 — 추정으로 지우지 않는다(원장 손실은 비가역).
    cat("      → SKIP: catalog 행이 권위(backtested+fr_eligible)가 아니거나 격리행도 권위 — 수동 판단 필요\n")
    skipped <- c(skipped, id); next
  }
  mode <- if (is.na(as.character(qe$registered_at)) ||
              as.character(ce$registered_at) >= as.character(qe$registered_at))
    "promoted" else "shadowed"
  cat(sprintf("      → %s tombstone(mode=%s)\n", if (APPLY) "APPLY" else "WOULD", mode))
  if (APPLY) {
    r <- .supersede_quarantine(QUA_P, id, ce, mode = mode,
                               shadow_entry = if (identical(mode, "shadowed")) qe else NULL)
    if (identical(mode, "shadowed")) {
      ## shadowed 경로는 modules 를 건드리지 않으므로 여기서 직접 회수한다.
      o <- read_obj(QUA_P); o$modules[[id]] <- NULL
      o$n_modules <- length(o$modules); o$n_superseded <- length(o$superseded %||% list())
      write_json(o, QUA_P, auto_unbox = TRUE, pretty = TRUE, na = "null")
    }
    fixed <- c(fixed, id)
  }
}

## 재검증 — 쓰기 후 실제로 0 이 됐는지 원장을 다시 읽어 확인한다("적용했다"는 자기신고 금지).
qj2 <- read_obj(QUA_P); cj2 <- read_obj(CAT_P)
left  <- intersect(names(cj2$modules %||% list()), names(qj2$modules %||% list()))
left2 <- intersect(names(qj2$modules %||% list()), names(qj2$superseded %||% list()))
cat(sprintf("\n[reconcile] 결과: 처리=%d  스킵=%d  잔존 중복=%d  잔존 낡은tombstone=%d  (quarantine.modules=%d, superseded=%d)\n",
            length(fixed), length(skipped), length(left), length(left2),
            length(qj2$modules %||% list()), length(qj2$superseded %||% list())))
if (length(skipped)) cat(sprintf("[reconcile] 수동 판단 대기: %s\n", paste(skipped, collapse = ", ")))
if (length(left))    cat(sprintf("[reconcile] 잔존: %s\n", paste(left, collapse = ", ")))
quit(save = "no", status = if (length(left) > 0L || length(left2) > 0L) 1L else 0L)
