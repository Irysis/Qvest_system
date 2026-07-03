## hybrid_mode.R — Qvest hybrid_commit() ghost function 정의 (Phase 3a B2)
##
## 도훈 명령 (정도 회복 lifecycle 내재화):
## "새 strategy 개발 끝났을 때 메모리/registry/텔레그램에 한 번에 자동 등록"
##
## 8 단계 (R0~R4 + Registry + L-code + Telegram):
##   R0: raw artifact store → qepm/research/results/{strategy_name}/
##   R1: experiment digest → qepm/memory/evidence/digest_{strategy_name}.json
##   R2: family/mechanism memory → qepm/memory/registry/family_{family}.json
##   R3: statistical evidence → qepm/memory/evidence_summary/sr_{strategy_name}.json
##   R4: portfolio policy → qepm/mailbox/governor/policy_updates/{date}.json
##   5: Registry update → 06_Registry/strategy_registry.json
##   6: L-code lesson → methodology_active.md (검증 fact only)
##   7: Telegram brief → tg_agent_brief()
##
## Safeguard (Charter v1.4 정합):
##   - hurdle_result$pass == TRUE 검증 (실패 strategy 자동 commit 차단)
##   - measurement_basis_primary == "forge_realized_share_based" 강제 (추정 차단)
##   - 추정 표현 grep filter (lessons에 estimated/likely/probably 0건)
##   - 사용자 manual approval flag (force=TRUE) 옵션

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})

QEPM_BASE <- (function() {
  cand <- c(
    Sys.getenv("QM_ROOT", unset = ""),
    "C:/Users/99922/OneDrive/Quant_Module_Moltbot",     # OneDrive canonical (도훈 mandate 2026-06-10)
    "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot", # WSL OneDrive canonical
    "G:/Quant_Module_Moltbot",                          # Windows-native (2026-06-03, legacy)
    "/mnt/g/Quant_Module_Moltbot",                      # WSL G:\
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
  )
  cand <- cand[nzchar(cand)]
  base <- cand[dir.exists(cand)][1]
  # HYG-03 가드 (2026-07-03): 경로 해석 실패 시 NA가 file.path()에 흘러들어
  # 루트에 'NA/qepm/...' 디렉토리를 만드는 사고 실증 (TO1099) — fail-loud.
  if (is.na(base)) {
    stop("[hybrid_mode] QEPM_BASE 해석 실패 — 후보 경로 전부 부재. QM_ROOT env 설정 필요.")
  }
  base
})()

cat(sprintf("[hybrid_mode] Loaded — Qvest hybrid_commit() Charter v1.4 정합 (2026-04-29).\n"))

# ─────────────────────────────────────────────────────
# 추정 표현 grep filter — 도훈 명령 추정 0건 강제
# ─────────────────────────────────────────────────────
.estimation_patterns <- c("estimated", "likely", "probably", "approximately",
                          "추정", "예상되는", "아마")

check_estimation_filter <- function(text) {
  if (is.null(text) || length(text) == 0) return(list(pass = TRUE))  # OK
  text_lower <- tolower(paste(text, collapse = " "))
  for (pat in .estimation_patterns) {
    if (grepl(pat, text_lower, fixed = TRUE)) {
      return(list(pass = FALSE, pattern = pat))
    }
  }
  list(pass = TRUE)
}

# ─────────────────────────────────────────────────────
# Measurement basis enum 검증
# ─────────────────────────────────────────────────────
.allowed_measurement_basis <- c(
  "forge_realized_share_based",                       # Charter §9 표준
  "forge_realized_share_based_extension_buy_and_hold", # POST_002 stylе
  "forge_realized_share_based_charter_v1_4_full_period" # POST_001 redo / 전기간 재평가
)

check_measurement_basis <- function(basis) {
  if (is.null(basis)) return(list(pass = FALSE, reason = "missing"))
  if (!basis %in% .allowed_measurement_basis) {
    return(list(pass = FALSE, reason = sprintf("not in enum: %s", basis)))
  }
  list(pass = TRUE)
}

# ─────────────────────────────────────────────────────
# hybrid_commit() — 8단계 자동화
# ─────────────────────────────────────────────────────
hybrid_commit <- function(strategy_name,
                          family,
                          hurdle_result,
                          artifact_paths = list(),
                          construction = list(),
                          role = "core_alpha",
                          lessons = character(),
                          measurement_basis = "forge_realized_share_based",
                          send_telegram = FALSE,
                          force = FALSE,
                          verbose = TRUE) {

  # ═══ Safeguard 1: hurdle_result$pass 검증 ═══
  if (!isTRUE(hurdle_result$pass) && !isTRUE(force)) {
    if (verbose) cat(sprintf("[hybrid_commit] BLOCKED — hurdle_result$pass=%s. force=TRUE 필요.\n",
                              isTRUE(hurdle_result$pass)))
    return(invisible(list(committed = FALSE, reason = "hurdle_fail")))
  }

  # ═══ Safeguard 2: measurement_basis enum 검증 ═══
  basis_check <- check_measurement_basis(measurement_basis)
  if (!isTRUE(basis_check$pass) && !isTRUE(force)) {
    if (verbose) cat(sprintf("[hybrid_commit] BLOCKED — measurement_basis %s. force=TRUE 필요.\n",
                              basis_check$reason))
    return(invisible(list(committed = FALSE, reason = "measurement_basis_invalid")))
  }

  # ═══ Safeguard 3: 추정 표현 grep filter ═══
  est_check <- check_estimation_filter(lessons)
  if (!isTRUE(est_check$pass) && !isTRUE(force)) {
    if (verbose) cat(sprintf("[hybrid_commit] BLOCKED — lessons에 추정 표현 '%s' 발견. force=TRUE 필요.\n",
                              est_check$pattern))
    return(invisible(list(committed = FALSE, reason = "estimation_term_in_lessons")))
  }

  if (verbose) cat(sprintf("[hybrid_commit] %s · family=%s · 8단계 commit 시작\n",
                            strategy_name, family))

  ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  date_tag <- format(Sys.Date(), "%Y%m%d")
  result_paths <- list()

  # ═══ R0: Raw artifact store ═══
  R0_dir <- file.path(QEPM_BASE, "qepm/research/results", strategy_name)
  dir.create(R0_dir, recursive = TRUE, showWarnings = FALSE)
  if (length(artifact_paths) > 0) {
    for (nm in names(artifact_paths)) {
      src <- artifact_paths[[nm]]
      if (is.character(src) && file.exists(src)) {
        file.copy(src, file.path(R0_dir, nm), overwrite = TRUE)
      }
    }
  }
  manifest <- list(
    strategy_name = strategy_name,
    family = family,
    role = role,
    measurement_basis_primary = measurement_basis,
    artifacts_n = length(artifact_paths),
    committed_at = ts
  )
  R0_manifest <- file.path(R0_dir, "_manifest.json")
  write_json(manifest, R0_manifest, pretty = TRUE, auto_unbox = TRUE, null = "null")
  result_paths$R0_manifest <- R0_manifest
  if (verbose) cat(sprintf("  [R0] manifest → %s\n", R0_manifest))

  # ═══ R1: Experiment digest ═══
  R1_dir <- file.path(QEPM_BASE, "qepm/memory/evidence")
  dir.create(R1_dir, recursive = TRUE, showWarnings = FALSE)
  digest <- list(
    strategy_name = strategy_name,
    family = family,
    role = role,
    grade = hurdle_result$grade %||% NA,
    score = hurdle_result$total_score %||% hurdle_result$score %||% NA,
    construction = construction,
    metrics_summary = hurdle_result$metrics %||% list(),
    statistical_defense = hurdle_result$statistical_defense %||% list(),
    measurement_basis_primary = measurement_basis,
    committed_at = ts
  )
  R1_path <- file.path(R1_dir, sprintf("digest_%s.json", strategy_name))
  write_json(digest, R1_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  result_paths$R1_digest <- R1_path
  if (verbose) cat(sprintf("  [R1] digest → %s\n", R1_path))

  # ═══ R2: Family/mechanism memory ═══
  R2_dir <- file.path(QEPM_BASE, "qepm/memory/registry")
  dir.create(R2_dir, recursive = TRUE, showWarnings = FALSE)
  R2_path <- file.path(R2_dir, sprintf("family_%s.json", gsub("[^A-Za-z0-9_]", "_", family)))
  family_memory <- if (file.exists(R2_path)) {
    fromJSON(R2_path, simplifyVector = FALSE)
  } else {
    list(family = family, members = list(), updated_at = ts)
  }
  family_memory$members[[strategy_name]] <- list(
    role = role,
    grade = hurdle_result$grade %||% NA,
    score = hurdle_result$total_score %||% hurdle_result$score %||% NA,
    committed_at = ts
  )
  family_memory$updated_at <- ts
  write_json(family_memory, R2_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  result_paths$R2_family <- R2_path
  if (verbose) cat(sprintf("  [R2] family → %s\n", R2_path))

  # ═══ R3: Statistical evidence ═══
  R3_dir <- file.path(QEPM_BASE, "qepm/memory/evidence_summary")
  dir.create(R3_dir, recursive = TRUE, showWarnings = FALSE)
  R3_path <- file.path(R3_dir, sprintf("sr_%s.json", strategy_name))
  stat_evidence <- list(
    strategy_name = strategy_name,
    sharpe = hurdle_result$metrics$Sharpe %||% NA,
    sharpe_m = hurdle_result$metrics$Sharpe_m %||% NA,
    cagr = hurdle_result$metrics$CAGR %||% NA,
    mdd = hurdle_result$metrics$MDD %||% NA,
    dsr = hurdle_result$statistical_defense$dsr %||% NA,
    dsr_significant = hurdle_result$statistical_defense$dsr_significant %||% NA,
    sr_max_expected = hurdle_result$statistical_defense$sr_max_expected %||% NA,
    n_trials = hurdle_result$statistical_defense$n_trials %||% NA,
    measurement_basis_primary = measurement_basis,
    committed_at = ts
  )
  write_json(stat_evidence, R3_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  result_paths$R3_stat <- R3_path
  if (verbose) cat(sprintf("  [R3] stat_evidence → %s\n", R3_path))

  # ═══ R4: Portfolio policy update ═══
  R4_dir <- file.path(QEPM_BASE, "qepm/mailbox/governor/policy_updates")
  dir.create(R4_dir, recursive = TRUE, showWarnings = FALSE)
  R4_path <- file.path(R4_dir, sprintf("%s_%s.json", date_tag, strategy_name))
  policy <- list(
    strategy_name = strategy_name,
    family = family,
    role = role,
    grade = hurdle_result$grade %||% NA,
    pass = hurdle_result$pass %||% FALSE,
    measurement_basis_primary = measurement_basis,
    committed_at = ts
  )
  write_json(policy, R4_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  result_paths$R4_policy <- R4_path
  if (verbose) cat(sprintf("  [R4] policy → %s\n", R4_path))

  # ═══ Step 5: Strategy registry update ═══
  reg_path <- file.path(QEPM_BASE, "06_Registry/strategy_registry.json")
  if (file.exists(reg_path)) {
    reg <- fromJSON(reg_path, simplifyVector = FALSE)
    str_ids <- sapply(reg, function(e) e$strategy_id %||% "NA")
    if (!(strategy_name %in% str_ids)) {
      new_entry <- list(
        strategy_id = strategy_name,
        family = family,
        role = role,
        grade = hurdle_result$grade %||% NA,
        score = hurdle_result$total_score %||% hurdle_result$score %||% NA,
        committed_via = "hybrid_commit_v1.4",
        committed_at = ts
      )
      reg[[length(reg) + 1L]] <- new_entry
      write_json(reg, reg_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
      result_paths$reg_step5 <- reg_path
      if (verbose) cat(sprintf("  [5] registry add (%d total) → %s\n",
                                length(reg), reg_path))
    } else if (verbose) cat("  [5] registry: already exists, skip\n")
  }

  # ═══ Step 6: L-code lesson append ═══
  meth_path <- {
    .mc <- c(
      file.path(Sys.getenv("USERPROFILE", unset = "C:/Users/User"),
                ".claude/projects/G--Quant-Module-Moltbot/memory/methodology_active.md"),  # Windows (2026-06-03)
      "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_active.md"
    )
    .e <- .mc[file.exists(.mc)]; if (length(.e)) .e[1] else .mc[1]
  }
  if (file.exists(meth_path) && length(lessons) > 0) {
    # Find next L-code
    existing_codes <- readLines(meth_path)
    code_lines <- grep("^### L-[0-9]+", existing_codes, value = TRUE)
    nums <- as.integer(gsub("^### L-([0-9]+).*$", "\\1", code_lines))
    next_l <- max(nums, na.rm = TRUE) + 1L

    lesson_block <- c(
      "",
      sprintf("### L-%d — %s hybrid_commit (auto-recorded)", next_l, strategy_name),
      "",
      sprintf("- **grade**: %s", hurdle_result$grade %||% "NA"),
      sprintf("- **lesson_text**: %s", paste(lessons, collapse = " ")),
      sprintf("- **core_reference**: %s + family=%s + measurement_basis=%s",
              strategy_name, family, measurement_basis),
      sprintf("- **태그**: HYBRID_COMMIT_AUTO, %s, ROLE_%s",
              gsub("[^A-Za-z0-9]", "_", toupper(family)),
              toupper(role))
    )
    cat(paste(lesson_block, collapse = "\n"), "\n", file = meth_path, append = TRUE)
    result_paths$step6_lcode <- next_l
    if (verbose) cat(sprintf("  [6] L-%d appended → %s\n", next_l, meth_path))
  } else if (verbose) cat("  [6] L-code skip (no lessons or path missing)\n")

  # ═══ Step 7: Telegram brief ═══
  # 기본 OFF. hybrid_commit은 내부 기록 이벤트라, 사용자 알림은 각 모드의
  # 결과 브리프(alpha-search/QEPM/factor-rotation)가 담당한다.
  if (isTRUE(send_telegram)) {
    tg_path <- file.path(QEPM_BASE, "02_Infrastructure/telegram/telegram_notify.R")
    if (file.exists(tg_path)) {
      tryCatch({
        source(tg_path, local = TRUE)
        if (exists("tg_send")) {
          msg <- sprintf(
            "🤖 hybrid_commit — %s\n\n• Family: %s\n• Role: %s\n• Grade: %s\n• Score: %s\n• Measurement: %s\n• 8단계 모두 commit ✅",
            strategy_name, family, role,
            hurdle_result$grade %||% "NA",
            hurdle_result$total_score %||% hurdle_result$score %||% "NA",
            measurement_basis
          )
          tg_send(msg)
          result_paths$step7_telegram <- TRUE
          if (verbose) cat("  [7] telegram brief 발송 ✅\n")
        }
      }, error = function(e) {
        if (verbose) cat(sprintf("  [7] telegram failed: %s\n", conditionMessage(e)))
      })
    }
  }

  if (verbose) cat(sprintf("[hybrid_commit] %s 8단계 commit 완료.\n", strategy_name))

  invisible(list(
    committed = TRUE,
    strategy_name = strategy_name,
    paths = result_paths,
    timestamp = ts
  ))
}

# ─────────────────────────────────────────────────────
# hybrid_status() — 메모리 + registry 현황 1줄 요약
# ─────────────────────────────────────────────────────
hybrid_status <- function() {
  reg_path <- file.path(QEPM_BASE, "06_Registry/strategy_registry.json")
  evid_dir <- file.path(QEPM_BASE, "qepm/memory/evidence")
  reg_n <- if (file.exists(reg_path)) length(fromJSON(reg_path, simplifyVector = FALSE)) else 0
  evid_n <- length(list.files(evid_dir, pattern = "^digest_.*\\.json$"))
  cat(sprintf("[hybrid_status] registry=%d entries / evidence digests=%d\n",
              reg_n, evid_n))
  invisible(list(registry = reg_n, evidence = evid_n))
}

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L) return(b)
  if (length(a) == 1L && is.atomic(a) && is.na(a)) return(b)
  a
}

cat("  Functions: hybrid_commit / hybrid_status / check_estimation_filter / check_measurement_basis\n")
