#==============================================================================
# emission_guard.R — factor DB 월 빌드의 "등재 대비 실산출" 대조 (1차 방어선)
#
# 사고 배경 (FQ-163, 2026-08-08):
#   compute_consensus.R 의 하류 7개 블록이 `if ("<metric>" %in% names(cons))` 로
#   게이트돼 있었는데 성능 리팩터가 `cons` 를 (Ticker, Date) 2열로 줄이면서 조건이
#   **영구 거짓**이 됐다. 결과: C10/C11/C13/C14/C15/C17/C18 이 440개 월 파일
#   전 구간 0행. 등재는 19종인데 실산출은 12종이었고, **누구도 몰랐다** —
#   빌더가 "이 팩터가 안 나왔다"를 물어보는 코드를 갖고 있지 않았기 때문이다.
#
# 설계 원칙:
#   ① 전면 stop 금지. 정당한 vintage 결측(초기 연도·원천 미탑재)까지 죽인다.
#      → 경고 + 산출물 기록이 정본.
#   ② "없음"을 판정하려면 **정체 검사**가 필요하다. 단순 setdiff(등재, 산출)는
#      202608 실측에서 54종을 뱉는다(대부분 정당) — 그대로 쓰면 경보가 소음이 되고
#      소음은 곧 무시된다. 그래서 두 축으로 나눈다:
#        · Class R (회귀): 직전 관측 빌드에선 났는데 지금 없다. vintage 무관하게
#          항상 이상. 초기 연도에는 "직전에 난 적" 이 없으므로 오발화하지 않는다.
#        · Class S (구조적 침묵): active 인데 원장 전 구간 한 번도 배출된 적 없고
#          선언된 기준선에도 없다. ★원 사고를 잡는 축은 이쪽이다 —
#          C10 은 **한 번도** 난 적이 없어서 델타 감시로는 영원히 안 잡힌다.
#   ③ 기준선(baseline)은 래칫이다. 알려진 결측은 사유와 함께 선언하고, 사유가
#      "미조사" 인 항목 수를 매 빌드 보고해 묻히지 않게 한다.
#   ④ 순수 함수로 분리한다. 인라인 판정은 위반 주입 테스트를 걸 수 없고,
#      검사 없는 가드는 무력화돼도 "경보 0건" 으로만 보인다.
#
# 상설 검사: 08_Tests/factor_db/test_emission_guard.R
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

#------------------------------------------------------------------------------
# registry 에서 (factor, category, status) 추출
#------------------------------------------------------------------------------
emission_registry_meta <- function(registry) {
  if (is.character(registry) && length(registry) == 1L) {
    if (!file.exists(registry)) stop("[emission_guard] registry 파일 없음: ", registry)
    registry <- fromJSON(registry, simplifyVector = FALSE)
  }
  if (!is.list(registry) || length(registry) == 0L) {
    stop("[emission_guard] registry 가 비었거나 리스트가 아님 — 0 을 '등재 없음'으로 읽지 않는다")
  }
  pick <- function(e, path, default = NA_character_) {
    v <- e
    for (p in path) {
      if (!is.list(v) || is.null(v[[p]])) return(default)
      v <- v[[p]]
    }
    if (is.null(v) || length(v) == 0L) default else as.character(v)[1]
  }
  rbindlist(lapply(names(registry), function(k) {
    e <- registry[[k]]
    data.table(
      Factor_Name = k,
      category    = pick(e, "category", "__uncategorized__"),
      status      = pick(e, c("lifecycle", "status"), "__nostatus__")
    )
  }))
}

#------------------------------------------------------------------------------
# 기준선 로드 — 선언된 "결측이 정상인" 팩터 목록
#------------------------------------------------------------------------------
emission_load_baseline <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(data.table(Factor_Name = character(), reason = character(),
                      diagnosed = logical(), declared_ym = character()))
  }
  b <- fromJSON(path, simplifyVector = FALSE)
  ent <- b$expected_absent
  if (is.null(ent) || length(ent) == 0L) {
    return(data.table(Factor_Name = character(), reason = character(),
                      diagnosed = logical(), declared_ym = character()))
  }
  rbindlist(lapply(ent, function(e) data.table(
    Factor_Name = as.character(e$factor)[1],
    reason      = if (is.null(e$reason)) NA_character_ else as.character(e$reason)[1],
    diagnosed   = isTRUE(e$diagnosed),
    declared_ym = if (is.null(e$declared_ym)) NA_character_ else as.character(e$declared_ym)[1]
  )))
}

#------------------------------------------------------------------------------
# ★핵심 순수 함수 — 위반 주입 테스트가 직접 구동하는 지점
#
# @param produced   data.table(Factor_Name, n_rows, n_tickers) — 이번 빌드 실산출
# @param reg_meta   emission_registry_meta() 산출
# @param ledger     data.table(ym, Factor_Name, n_rows) — **이전** 빌드들의 기록
# @param ym         이번 빌드의 YYYYMM
# @param baseline   emission_load_baseline() 산출
# @return list(report, warnings)   ★어떤 경우에도 stop() 하지 않는다
#------------------------------------------------------------------------------
factor_emission_check <- function(produced, reg_meta, ledger, ym, baseline = NULL) {
  stopifnot(is.data.table(reg_meta), nzchar(ym))
  # ★`ym` 은 원장의 컬럼명이기도 하다. data.table i-표현식에서 인자와 컬럼이
  #   같은 이름이면 컬럼이 이긴다 — 다른 이름의 지역변수로 못박는다.
  ym_cur <- as.character(ym)[1]
  if (is.null(baseline)) {
    baseline <- data.table(Factor_Name = character(), reason = character(),
                           diagnosed = logical(), declared_ym = character())
  }
  if (is.null(produced) || nrow(produced) == 0L) {
    produced <- data.table(Factor_Name = character(), n_rows = integer(), n_tickers = integer())
  }
  produced <- produced[!is.na(Factor_Name) & n_rows > 0L]
  prod_set <- unique(produced$Factor_Name)

  active   <- reg_meta[status == "active", Factor_Name]
  absent   <- setdiff(active, prod_set)
  unreg    <- setdiff(prod_set, reg_meta[status == "active", Factor_Name])

  warnings <- character(0)

  # ── Class R: 회귀 (직전 관측 빌드엔 있었는데 지금 없다) ────────────────────
  prev_ym    <- NA_character_
  regression <- character(0)
  ledger_ok  <- !is.null(ledger) && is.data.table(ledger) && nrow(ledger) > 0L
  if (ledger_ok) {
    prior <- ledger[ym < ym_cur & !is.na(n_rows) & n_rows > 0L]
    if (nrow(prior) > 0L) {
      prev_ym <- max(prior$ym)
      prev_set <- prior[ym == prev_ym, unique(Factor_Name)]
      regression <- sort(intersect(absent, prev_set))
    }
  }
  if (length(regression) > 0L) {
    warnings <- c(warnings, sprintf(
      "[emission_guard] %s — 회귀 %d종: 직전 빌드(%s)에선 산출됐으나 이번엔 0행 → %s",
      ym, length(regression), prev_ym, paste(regression, collapse = ", ")))
  }

  # ── Class S: 구조적 침묵 (원장 전 구간 미배출 + 기준선 미선언) ─────────────
  # ★원 사고(C10 등 440개월 0행)를 잡는 축. 델타 감시는 원리적으로 못 잡는다.
  silent <- character(0)
  silent_suppressed_reason <- NA_character_
  if (ledger_ok) {
    ever <- ledger[!is.na(n_rows) & n_rows > 0L, unique(Factor_Name)]
    never <- setdiff(absent, ever)
    silent <- sort(setdiff(never, baseline$Factor_Name))
  } else {
    silent_suppressed_reason <- "원장 비어 있음 — '한 번도 안 났다'와 '기록이 없다'를 구별 불가 (seed_emission_ledger.R 먼저)"
  }
  if (length(silent) > 0L) {
    warnings <- c(warnings, sprintf(
      "[emission_guard] %s — 구조적 침묵 %d종: registry active 인데 원장 전 구간 0행이고 기준선에도 없음 → %s",
      ym, length(silent), paste(silent, collapse = ", ")))
  }

  # ── 부가: 등재 안 된 산출물 ────────────────────────────────────────────────
  if (length(unreg) > 0L) {
    warnings <- c(warnings, sprintf(
      "[emission_guard] %s — registry active 아닌 팩터 %d종이 산출됨 → %s",
      ym, length(unreg), paste(sort(unreg), collapse = ", ")))
  }

  # ── 계열별 분해 (부분 결측이 전체 결측보다 훨씬 강한 신호) ─────────────────
  fam <- merge(reg_meta[status == "active"],
               data.table(Factor_Name = prod_set, produced = TRUE),
               by = "Factor_Name", all.x = TRUE)
  fam[is.na(produced), produced := FALSE]
  fam_summary <- fam[, .(n_active = .N, n_produced = sum(produced),
                         n_absent = sum(!produced),
                         absent = paste(sort(Factor_Name[!produced]), collapse = ",")),
                     by = category][order(-n_absent)]

  # ── 연속 결측 개월수 (기록 의무) ───────────────────────────────────────────
  streak <- data.table(Factor_Name = character(), consecutive_absent = integer(),
                       last_seen_ym = character())
  if (ledger_ok && length(absent) > 0L) {
    yms <- sort(unique(ledger[ym < ym_cur, ym]))
    streak <- rbindlist(lapply(absent, function(f) {
      seen <- ledger[Factor_Name == f & !is.na(n_rows) & n_rows > 0L, ym]
      seen <- seen[seen < ym_cur]
      last_seen <- if (length(seen) > 0L) max(seen) else NA_character_
      n_after <- if (is.na(last_seen)) length(yms) else sum(yms > last_seen)
      data.table(Factor_Name = f,
                 consecutive_absent = as.integer(n_after + 1L),  # 이번 빌드 포함
                 last_seen_ym = last_seen)
    }))
    setorder(streak, -consecutive_absent, Factor_Name)
  }

  bl_undiag <- baseline[diagnosed == FALSE, Factor_Name]

  report <- list(
    guard          = "factor_emission_check",
    version        = "1.0",
    ym             = ym,
    prev_observed_ym = prev_ym,
    n_registry_active = length(active),
    n_produced        = length(prod_set),
    n_absent          = length(absent),
    absent            = sort(absent),
    class_R_regression = regression,
    class_S_silent     = silent,
    class_S_suppressed = silent_suppressed_reason,
    unregistered_produced = sort(unreg),
    baseline_declared  = nrow(baseline),
    baseline_undiagnosed = sort(bl_undiag),
    family_breakdown   = fam_summary,
    absent_streak      = streak,
    warnings           = warnings,
    verdict            = if (length(warnings) > 0L) "WARN" else "OK"
  )
  report
}

#------------------------------------------------------------------------------
# 부작용 래퍼 — 빌더가 부르는 진입점. 경고 발행 + 사이드카 + 원장 append.
# ★어떤 경우에도 빌드를 멈추지 않는다(설계 원칙 ①).
#------------------------------------------------------------------------------
factor_emission_guard <- function(result, ym, fdb_dir, registry_path,
                                  baseline_path = NULL, write_artifacts = TRUE) {
  out <- tryCatch({
    produced <- if (is.data.table(result) && nrow(result) > 0L) {
      result[, .(n_rows = .N, n_tickers = uniqueN(Ticker)), by = Factor_Name]
    } else {
      data.table(Factor_Name = character(), n_rows = integer(), n_tickers = integer())
    }
    reg_meta <- emission_registry_meta(registry_path)
    baseline <- emission_load_baseline(baseline_path)

    ledger_path <- file.path(fdb_dir, "emission_ledger.csv")
    ledger <- if (file.exists(ledger_path)) {
      tryCatch(fread(ledger_path, colClasses = list(character = "ym")),
               error = function(e) NULL)
    } else NULL

    rep <- factor_emission_check(produced, reg_meta, ledger, ym, baseline)

    cat(sprintf("  [emission_guard] %s: registry active %d · 산출 %d · 결측 %d (회귀 %d / 구조적침묵 %d) → %s\n",
                ym, rep$n_registry_active, rep$n_produced, rep$n_absent,
                length(rep$class_R_regression), length(rep$class_S_silent), rep$verdict))
    if (length(rep$baseline_undiagnosed) > 0L) {
      cat(sprintf("  [emission_guard] 기준선 미조사 항목 %d종 (묻히지 않게 매 빌드 표시)\n",
                  length(rep$baseline_undiagnosed)))
    }
    for (w in rep$warnings) warning(w, call. = FALSE)

    if (isTRUE(write_artifacts)) {
      sc <- file.path(fdb_dir, sprintf("emission_report_%s.json", ym))
      write_json(rep, sc, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
      ym_cur <- as.character(ym)[1]   # ★컬럼명 'ym' 과 충돌 방지 (i-표현식에선 컬럼이 이긴다)
      new_rows <- copy(produced)[, `:=`(ym = ym_cur, built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))]
      setcolorder(new_rows, c("ym", "Factor_Name", "n_rows", "n_tickers", "built_at"))
      if (file.exists(ledger_path)) {
        old <- fread(ledger_path, colClasses = list(character = "ym"))
        old <- old[ym != ym_cur]                   # 같은 달 재빌드는 교체
        fwrite(rbindlist(list(old, new_rows), use.names = TRUE, fill = TRUE), ledger_path)
      } else {
        fwrite(new_rows, ledger_path)
      }
    }
    rep
  }, error = function(e) {
    # ★가드가 죽어도 빌드는 계속된다. 단 **조용히** 죽지는 않는다.
    warning(sprintf("[emission_guard] 가드 자체 실패 (빌드는 계속) — %s", conditionMessage(e)),
            call. = FALSE)
    cat(sprintf("  [emission_guard] ERROR: %s\n", conditionMessage(e)))
    NULL
  })
  invisible(out)
}

cat("[factor_db] emission_guard.R loaded (v1.0)\n")
