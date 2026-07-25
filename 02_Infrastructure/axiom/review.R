# Sprint 4 AX-P3: Axiom Review Loop
# 분기별 (or on-demand) active axiom 재검증 → deprecate 처리.
#
# Criteria for deprecation:
#   1) supporting_strategies의 최근 hurdle_result가 IS 대비 50% 이하로 열화
#   2) 새 반증 실험(L-code)에서 AX 주장 기각 증거 >= 2건
#
# v7.2.1 Sprint 3 — Dry-Run Safety:
#   - apply=FALSE default — active/deprecated/CLAUDE.md 0건 변경
#   - --apply flag만 실제 변경 권한
#   - dry-run report → review_log/dryrun/review_dryrun_YYYYMMDD.json
#
# Usage:
#   Rscript review.R --all                # dry-run
#   Rscript review.R --all --apply        # apply
#   Rscript review.R AX-003               # dry-run single
#   Rscript review.R AX-003 --apply       # apply single

suppressPackageStartupMessages({
  library(jsonlite)
})

.rv_root <- function() {
  cands <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

# mode-local 포함 axiom 경로 탐색 (active/ + active/modes/**)
.find_axiom_path <- function(root, axiom_id) {
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  direct <- file.path(active_dir, paste0(axiom_id, ".json"))
  if (file.exists(direct)) return(direct)
  hits <- list.files(active_dir, pattern = paste0("^", axiom_id, "\\.json$"),
                     full.names = TRUE, recursive = TRUE)
  if (length(hits)) hits[1] else NA_character_
}

# ─── OOS 열화 체크 ──────────────────────────────────────────────────
.check_oos_degradation <- function(axiom) {
  # INV-3/INV-7: proxy/estimated 유래 공리는 STR hurdle_result 부재 → 자동 OOS 판정 불가, human-review 플래그
  mt <- axiom$metric_type %||% ""
  if (mt %in% c("proxy", "estimated")) {
    return(list(degraded = FALSE, human_review = TRUE,
                reason = sprintf("metric_type=%s — 자동 OOS deprecation 불가, 매 사이클 human-review", mt)))
  }
  root <- .rv_root()
  supporting <- axiom$supporting_l_codes %||% character(0)
  if (length(supporting) == 0L) return(list(degraded = FALSE, reason = "no supporting L-codes"))

  corpus_path <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(corpus_path)) {
    return(list(degraded = FALSE, reason = "lcode_corpus missing"))
  }
  corpus <- fromJSON(corpus_path, simplifyVector = FALSE)

  strategies <- character(0)
  for (lc in supporting) {
    idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
    if (length(idx)) strategies <- c(strategies, corpus$lcodes[[idx[1]]]$strategy_id %||% "")
  }
  strategies <- unique(strategies[nzchar(strategies)])
  if (length(strategies) == 0L) return(list(degraded = FALSE, reason = "no strategies"))

  # 최근 hurdle_result에서 rolling_sharpe_positive_ratio 확인
  # 2026-07-25 수리: 종전 `grepl(s, basename(d), fixed=TRUE)` = substring 매칭이라
  #   ① 접두 오매칭(STR_146 ⊂ STR_1469) ② 같은 STR 번호를 쓰는 **서로 다른 전략**
  #   (실측 7건 — 예: STR_1571_bayesian_bl_c11fix vs STR_1571_c19_v14_d01_l22_dd_regime)
  #   양쪽을 다 주워 담아 무관한 전략의 ratio를 평균에 섞었다. 열화 판정이 조용히 틀어지는 경로.
  #   → 토큰경계 매칭으로 ①을 제거하고, ②(진짜 모호)는 **평균에 섞지 않고 스킵 + 기록**한다
  #     (틀린 수치보다 입력이 적은 정직한 수치가 낫다).
  ratios <- numeric(0)
  ambiguous <- character(0)
  all_dirs <- list.dirs(file.path(root, "04_Research", "strategies"),
                        recursive = FALSE, full.names = TRUE)
  for (s in strategies) {
    bn <- basename(all_dirs)
    hit <- all_dirs[bn == s | startsWith(bn, paste0(s, "_"))]
    if (length(hit) > 1L) {
      ambiguous <- c(ambiguous, sprintf("%s(%d dirs)", s, length(hit)))
      next
    }
    for (d in hit) {
      hf <- list.files(d, pattern = "^hurdle_result\\.json$",
                        recursive = TRUE, full.names = TRUE)
      if (length(hf) == 0L) next
      hd <- tryCatch(fromJSON(hf[1], simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(hd)) next
      rs <- hd$metrics$rolling_sharpe_positive_ratio %||%
            hd$rolling_sharpe_positive_ratio %||% NA_real_
      if (!is.na(rs)) ratios <- c(ratios, as.numeric(rs))
    }
  }
  if (length(ambiguous))
    cat(sprintf("[review][WARN] strategy_id 모호 %d건 — 평균에서 제외: %s\n",
                length(ambiguous), paste(ambiguous, collapse = ", ")))

  if (length(ratios) == 0L) return(list(degraded = FALSE, reason = "no rolling metrics"))
  mean_ratio <- mean(ratios)
  # 0.5 미만이면 IS 대비 상당 열화
  degraded <- mean_ratio < 0.5
  list(
    degraded = degraded,
    mean_rolling_sharpe_positive_ratio = round(mean_ratio, 3),
    n_strategies = length(ratios),
    ambiguous_strategy_ids = as.list(ambiguous),   # 2026-07-25: 평균 제외분 정직 기록
    reason = sprintf("mean rolling_sharpe_positive_ratio=%.3f (%s 0.5)",
                     mean_ratio, if (degraded) "<" else ">=")
  )
}

# ─── 반증 증거 체크 ─────────────────────────────────────────────────
.check_new_falsification <- function(axiom) {
  root <- .rv_root()
  scope <- axiom$scope %||% list()
  ax_family <- tolower(scope$factor_family %||% "")
  if (!nzchar(ax_family)) return(list(falsified = FALSE, reason = "no family scope"))

  # 최근 L-code 중 같은 family이면서 AX polarity 반대되는 것 카운트
  corpus_path <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(corpus_path)) return(list(falsified = FALSE, reason = "corpus missing"))
  corpus <- fromJSON(corpus_path, simplifyVector = FALSE)

  polarity <- axiom$polarity %||% "unknown"
  supporting <- axiom$supporting_l_codes %||% character(0)

  contradictions <- 0L
  contradicting_l_codes <- character(0)
  for (lc in corpus$lcodes) {
    if (lc$l_code %in% supporting) next  # 자기 자신은 제외
    fam <- tolower(lc$family %||% "")
    if (!nzchar(fam) || !grepl(ax_family, fam, fixed = TRUE)) next
    grade <- lc$grade %||% ""
    # negative axiom인데 같은 family에서 Grade A가 나옴 → 반증
    if (polarity == "negative" && grade == "A") {
      contradictions <- contradictions + 1L
      contradicting_l_codes <- c(contradicting_l_codes, lc$l_code)
    }
    # positive/conditional axiom인데 같은 family에서 Grade F가 반복적으로 나옴
    if (polarity %in% c("positive", "conditional") && grade == "F") {
      contradictions <- contradictions + 1L
      contradicting_l_codes <- c(contradicting_l_codes, lc$l_code)
    }
  }

  list(
    falsified = contradictions >= 2L,
    n_contradictions = contradictions,
    contradicting_l_codes = contradicting_l_codes,
    reason = sprintf("%d contradicting L-codes in %s family", contradictions, ax_family)
  )
}

# ─── Deprecate 처리 ─────────────────────────────────────────────────
.deprecate_axiom <- function(axiom_id, reason_list, apply = FALSE) {
  root <- .rv_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  dep_dir <- file.path(root, "qepm", "memory", "axioms", "deprecated")

  src <- file.path(active_dir, paste0(axiom_id, ".json"))
  if (!file.exists(src)) return(FALSE)

  if (!isTRUE(apply)) {
    cat(sprintf("[review] dry-run: %s would be deprecated (reasons: %s)\n",
                axiom_id, paste(reason_list, collapse = "; ")))
    return(TRUE)
  }

  dir.create(dep_dir, recursive = TRUE, showWarnings = FALSE)
  axiom <- fromJSON(src, simplifyVector = FALSE)
  axiom$status <- "deprecated"
  axiom$deprecated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  axiom$deprecation_reasons <- reason_list

  ts <- format(Sys.time(), "%Y%m%d")
  dst <- file.path(dep_dir, sprintf("%s_deprecated_%s.json", axiom_id, ts))
  write_json(axiom, dst, pretty = TRUE, auto_unbox = TRUE, null = "null")
  file.remove(src)
  cat(sprintf("[review] %s → deprecated/%s\n", axiom_id, basename(dst)))

  # L-code 역링크 클리어
  for (lc in (axiom$supporting_l_codes %||% character(0))) {
    stage_arts <- file.path(root, "stage_artifacts")
    files <- list.files(stage_arts, pattern = "^l_code_.*\\.json$", full.names = TRUE)
    for (f in files) {
      d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(d)) next
      if (identical(d$l_code, lc) && identical(d$promoted_to_axiom, axiom_id)) {
        d$promoted_to_axiom <- NULL
        d$deprecation_note <- sprintf("previously promoted to %s, deprecated %s",
                                        axiom_id, axiom$deprecated_at)
        write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
        cat(sprintf("[review] L-code 역링크 클리어: %s\n", basename(f)))
        break
      }
    }
  }

  # CLAUDE.md에서 해당 AX 블록 제거 (간이: 해당 ### 헤더부터 다음 ###/## 까지)
  claude_md <- file.path(root, "CLAUDE.md")
  if (file.exists(claude_md)) {
    raw <- readLines(claude_md, warn = FALSE, encoding = "UTF-8")
    pat <- sprintf("^### %s", axiom_id)
    start <- grep(pat, raw, perl = TRUE)
    if (length(start) > 0L) {
      s <- start[1]
      # 블록 끝: 다음 ### 또는 ## 까지
      next_hdr <- grep("^(###|##)\\s+", raw, perl = TRUE)
      next_hdr <- next_hdr[next_hdr > s]
      e <- if (length(next_hdr) == 0L) length(raw) else (next_hdr[1] - 1L)
      new <- c(raw[1:(s - 1L)], if (e < length(raw)) raw[(e + 1L):length(raw)] else character(0))
      if (as.integer(Sys.getenv("QVEST_AXIOM_AUTO_INJECT", "0")) == 1L) {
        writeLines(new, claude_md, useBytes = TRUE)
        cat(sprintf("[review] CLAUDE.md에서 %s 블록 제거\n", axiom_id))
      } else {
        cat(sprintf("[review] dry-run: CLAUDE.md %s 제거 스킵 (AUTO_INJECT=1 필요)\n", axiom_id))
      }
    }
  }

  TRUE
}

# ─── 메인 함수 ─────────────────────────────────────────────────────
review_axiom <- function(axiom_id, apply = FALSE) {
  root <- .rv_root()
  ax_path <- .find_axiom_path(root, axiom_id)
  if (is.na(ax_path) || !file.exists(ax_path)) {
    cat(sprintf("[review] %s active 파일 없음\n", axiom_id))
    return(NULL)
  }
  axiom <- fromJSON(ax_path, simplifyVector = FALSE)

  # IMMUTABLE 공리는 review 대상 제외
  if (identical(axiom$grade, "IMMUTABLE")) {
    cat(sprintf("[review] %s: IMMUTABLE — skip\n", axiom_id))
    return(list(axiom_id = axiom_id, action = "skip", reason = "IMMUTABLE"))
  }

  oos <- .check_oos_degradation(axiom)
  fal <- .check_new_falsification(axiom)

  cat(sprintf("[review] %s — OOS: %s | Falsification: %s\n",
              axiom_id, oos$reason, fal$reason))

  reasons <- character(0)
  if (isTRUE(oos$degraded)) {
    reasons <- c(reasons, paste("OOS_degraded:", oos$reason))
  }
  if (isTRUE(fal$falsified)) {
    reasons <- c(reasons, paste("new_falsification:", fal$reason))
  }

  if (length(reasons) > 0L) {
    # INV-7: provisional negative가 반증되면 deprecate가 아니라 NARROW(범위 축소) + 재도전 트리거
    is_provisional <- identical(axiom$epistemic_status %||% "", "provisional")
    if (is_provisional && isTRUE(fal$falsified)) {
      if (isTRUE(apply)) {
        axiom$scope_narrowed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        axiom$narrow_reasons <- reasons
        axiom$retry_trigger <- "반증 출현 — kr-inverse-pattern-miner 역가설 재도전 대상"
        write_json(axiom, ax_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
        cat(sprintf("[review] %s → NARROW (provisional negative 반증, 재도전 트리거)\n", axiom_id))
      } else {
        cat(sprintf("[review] dry-run: %s would_narrow (provisional negative 반증)\n", axiom_id))
      }
      return(list(axiom_id = axiom_id, action = if (apply) "narrowed" else "would_narrow",
                  reasons = reasons, apply = apply))
    }
    .deprecate_axiom(axiom_id, reasons, apply = apply)
    return(list(axiom_id = axiom_id,
                action = if (apply) "deprecated" else "would_deprecate",
                reasons = reasons,
                apply = apply))
  }

  # 성공 — next_review 업데이트 (apply=TRUE만 write)
  if (isTRUE(apply)) {
    axiom$promotion$last_review <- format(Sys.time(), "%Y-%m-%d")
    axiom$promotion$next_review <- format(Sys.Date() + 90, "%Y-%m-%d")
    write_json(axiom, ax_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[review] %s — 재확인 통과, next_review=%s\n",
                axiom_id, axiom$promotion$next_review))
    list(axiom_id = axiom_id, action = "confirmed",
         next_review = axiom$promotion$next_review,
         apply = TRUE)
  } else {
    cat(sprintf("[review] dry-run: %s — 재확인 통과 (no write)\n", axiom_id))
    list(axiom_id = axiom_id, action = "would_confirm",
         next_review_proposed = format(Sys.Date() + 90, "%Y-%m-%d"),
         apply = FALSE)
  }
}

review_all_active_axioms <- function(apply = FALSE) {
  root <- .rv_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  files <- list.files(active_dir, pattern = "^AX-.*\\.json$",
                      full.names = FALSE, recursive = TRUE)  # mode-local(modes/**) 포함
  ax_ids <- sub("\\.json$", "", basename(files))
  results <- list()
  for (id in ax_ids) {
    r <- tryCatch(review_axiom(id, apply = apply), error = function(e) {
      cat(sprintf("[review] %s 오류: %s\n", id, conditionMessage(e)))
      NULL
    })
    if (!is.null(r)) results[[id]] <- r
  }
  cat(sprintf("\n[review] 완료 — %d 건 처리 (apply=%s)\n",
              length(results), apply))

  # ─── Dry-run report ─────────────────────────────────────────────
  if (!isTRUE(apply)) {
    dryrun_dir <- file.path(root, "qepm", "memory", "axioms",
                            "review_log", "dryrun")
    dir.create(dryrun_dir, recursive = TRUE, showWarnings = FALSE)
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    out_path <- file.path(dryrun_dir, sprintf("review_dryrun_%s.json", ts))
    report <- list(
      schema_version = "v7.2.1_review_dryrun",
      ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      apply = FALSE,
      axiom_count = length(results),
      results = results,
      note = paste("dry-run only — active/deprecated/CLAUDE.md 0건 변경.",
                   "실제 변경은 --apply flag 의무.")
    )
    write_json(report, out_path,
               pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[review] dry-run report → %s\n", out_path))
  }

  invisible(results)
}

# CLI
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .a <- commandArgs(trailingOnly = TRUE)
  apply <- "--apply" %in% .a
  .a <- setdiff(.a, "--apply")
  if (length(.a) == 0L || .a[1] == "--all") {
    invisible(review_all_active_axioms(apply = apply))
  } else {
    invisible(review_axiom(.a[1], apply = apply))
  }
}

cat("[review] Loaded. Functions: review_axiom(ax_id, apply=FALSE) / review_all_active_axioms(apply=FALSE)\n")
cat("[review] Default = dry-run. Use --apply (CLI) or apply=TRUE (R) to write.\n")
