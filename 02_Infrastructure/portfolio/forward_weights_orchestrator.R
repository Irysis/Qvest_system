## Forward Weights Orchestrator (Phase 1, Plan v1.0 2026-04-29)
##
## Goal: 3 마일스톤 admitted 전략의 forward production weights 통합 entry-point
##   - STR_1715 (현 PG2 100%)
##   - STR_1631_SYN_06 (이전 PG2 80% diversifier 기반)
##   - STR_1656_MLRA_M05 (ML diversifier; STUB Phase 1)
##
## 도훈 명령 enforcement:
##   - apply_mandate_cap = "cap_0.20" default 강제
##   - measurement_basis_primary = "forge_realized_share_based"
##   - 추정 표현 금지

suppressMessages({
  library(data.table); library(jsonlite)
})
options(scipen = 999)

orchestrate_forward_weights <- function(
  as_of_date         = NULL,
  apply_mandate_cap  = "cap_0.20",
  strategies         = c("STR_1715", "STR_1631_SYN_06", "STR_1656_MLRA"),
  send_telegram      = FALSE,
  manifest_root      = NULL
) {
  ## ★2026-08-08 루트 해석 수리 (칩 task_29584825).
  ##   구판: normalizePath(dirname(sys.frame(1)$ofile) + "../..") — daily_refresh.sh 가
  ##   `cd $INFRA` 후 상대경로로 source 하므로 ofile 이 상대경로가 되고 `../..` 이 **프로젝트 밖**
  ##   (사용자 홈)으로 나갔다. 결과: 5주 이상 3전략 전부 MISSING_WRAPPER + manifest 가 홈에 적재.
  ##   실측: manifest_20260701/0715/0801/0808 전부 436바이트 동일(전건 MISSING_WRAPPER).
  ##   정정: r-portability.md 금칙 ④ — resolver 는 CLAUDE_PROJECT_DIR → QM_ROOT 우선.
  ##   ★marker 검증까지 한다(경로가 있다고 프로젝트 루트인 건 아니다).
  PROJECT_ROOT <- local({
    .marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
    cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
               normalizePath(file.path(dirname(sys.frame(1)$ofile %||% getwd()), "..", ".."),
                             mustWork = FALSE))
    cands <- cands[nzchar(cands)]
    hit <- cands[file.exists(file.path(cands, .marker))]
    if (!length(hit)) stop(sprintf(
      "[orchestrator] 프로젝트 루트 해석 실패 — 후보 %s 중 marker(%s) 보유 없음. CLAUDE_PROJECT_DIR/QM_ROOT 설정 필요",
      paste(cands, collapse=" | "), .marker))
    normalizePath(hit[1])
  })
  cat(sprintf("[orchestrator] PROJECT_ROOT = %s\n", PROJECT_ROOT))

  results <- list()

  if ("STR_1715" %in% strategies) {
    cat("\n========== STR_1715 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1715(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1715"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1715 forward_weights.R not found\n")
      results[["STR_1715"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  if ("STR_1631_SYN_06" %in% strategies) {
    cat("\n========== STR_1631_SYN_06 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1631_SYN_06/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1631_syn06(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1631_SYN_06"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1631_SYN_06 forward_weights.R not found\n")
      results[["STR_1631_SYN_06"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  if ("STR_1656_MLRA" %in% strategies) {
    cat("\n========== STR_1656_MLRA_M05 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1656_MLRA/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1656_mlra(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1656_MLRA"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1656_MLRA forward_weights.R not found\n")
      results[["STR_1656_MLRA"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  # ─── Manifest 통합 저장 ──────────────────────────────
  if (is.null(manifest_root)) {
    manifest_root <- file.path(PROJECT_ROOT, "qepm/mailbox/governor/forward_weights_manifests")
  }
  dir.create(manifest_root, recursive = TRUE, showWarnings = FALSE)

  date_tag <- if (is.null(as_of_date)) format(Sys.Date(), "%Y%m%d") else
              format(as.Date(as_of_date), "%Y%m%d")
  manifest_path <- file.path(manifest_root,
                              sprintf("manifest_%s_%s.json", date_tag, apply_mandate_cap))

  combined <- list(
    orchestrated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    as_of_date = if (is.null(as_of_date)) NA else as.character(as_of_date),
    apply_mandate_cap = apply_mandate_cap,
    strategies = results,
    measurement_basis_primary = "forge_realized_share_based",
    plan_version = "v1.0_2026-04-29"
  )
  write_json(combined, manifest_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("\n[orchestrator] manifest: %s\n", manifest_path))

  ## ★2026-08-08 fail-closed 승격 (칩 task_29584825 ②).
  ##   구판은 전 전략이 MISSING_WRAPPER 여도 **빈 manifest 를 정상 산출로 쓰고 종료**했다 —
  ##   error 가 아니라 정상 종료라 daily_refresh.sh 의 tryCatch 조차 발화하지 않았고,
  ##   그래서 5주 이상 아무도 몰랐다("빈 결과 = 합격" 계통).
  ##   요청 전략이 하나도 산출되지 않으면 **비정상 종료**한다.
  .st <- vapply(results, function(r) as.character(r$status %||% "OK")[1], character(1))
  .bad <- .st %in% c("MISSING_WRAPPER", "MISSING_SCRIPT", "STUB")
  if (length(.st) && all(.bad)) {
    stop(sprintf(paste0("[fail-closed] 요청 전략 %d개가 전부 미산출(%s) — 빈 manifest 를 정상으로 쓰지 않는다.\n",
                        "  PROJECT_ROOT=%s\n",
                        "  확인: 전략 wrapper 경로 존재 여부, CLAUDE_PROJECT_DIR/QM_ROOT 설정."),
                 length(.st), paste(unique(.st), collapse=","), PROJECT_ROOT))
  }
  if (any(.bad)) cat(sprintf("[orchestrator][WARN] 일부 전략 미산출: %s\n",
                             paste(names(results)[.bad], collapse=", ")))

  # ─── Telegram brief (optional) ───────────────────────
  if (send_telegram) {
    tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R")
    if (file.exists(tg_path)) {
      tryCatch({
        source(tg_path)
        msg_lines <- c(
          "[Q-Lead] Forward Weights Orchestrator",
          sprintf("as_of_date: %s | mandate: %s",
                  if (is.null(as_of_date)) "max(schedule)" else as.character(as_of_date),
                  apply_mandate_cap),
          "",
          sprintf("STR_1715: %s",
                  results[["STR_1715"]]$status %||% "ok"),
          sprintf("STR_1631_SYN_06: %s",
                  results[["STR_1631_SYN_06"]]$status %||% "ok"),
          sprintf("STR_1656_MLRA: %s",
                  results[["STR_1656_MLRA"]]$status %||% "STUB"),
          "",
          sprintf("manifest: %s", manifest_path)
        )
        if (exists("tg_send")) tg_send(paste(msg_lines, collapse = "\n"))
      }, error = function(e) cat(sprintf("[orchestrator] telegram send failed: %s\n",
                                          conditionMessage(e))))
    }
  }

  invisible(combined)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (!interactive() && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  as_of <- if (length(args) >= 1 && nchar(args[1]) > 0) args[1] else NULL
  cap_mode <- if (length(args) >= 2) args[2] else "cap_0.20"
  send_tg <- if (length(args) >= 3) as.logical(args[3]) else FALSE
  orchestrate_forward_weights(as_of_date = as_of,
                               apply_mandate_cap = cap_mode,
                               send_telegram = send_tg)
}
