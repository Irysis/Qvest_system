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

#==============================================================================
# 정체 검사 3축 (D / T / I) — 2026-08-09 FQ-210 실측 배선
#
# 왜 필요한가: 위 factor_emission_check 는 `n_rows > 0` 만 본다. 그래서
#   · 다른 팩터와 **값이 같은** 배출 (C01≡C10, C11≡M25, C01≡C09 …)
#   · 행은 나오는데 **횡단면 상수**라 소비면에 0으로 도달하는 배출
#     (C15 50/50월 · D60/Q16 각 22/53월 = 2015-06~2025-12 연속 11년)
# 을 **원리적으로** 못 본다. 존재를 확인했을 뿐 정체를 확인하지 않았다.
#
# ★추가 IO 가 0이다: 빌더가 넘기는 `result` 는 이미
#   (Date, Ticker, Factor_Name, Raw_Value, Z_Score, Z_Sector, Rank_Pct, Coverage)
#   전 스키마를 갖고 있는데(factor_db_builder.R:928) 기존 진입점이 첫 줄에서
#   `n_rows` 만 세고 버렸다. 그 자리에서 세 축을 전부 잰다.
#
# ★★계측 사망 방지 (이 배선의 1차 교훈):
#   FQ-210 초판이 "죽은 배출"의 판별통계로 `sd(Z_Score)` 를 썼다가 331종 전부
#   정확히 1.0000 을 얻었다 — Z 는 횡단면 표준화 산물이라 sd=1 이 **항등**이고
#   판별력이 원리적으로 0이다. 그런데 산출물은 "죽은 배출 0종"이라는 **결론처럼**
#   생긴 문자열이었다. 재확인(2026-08-09, 커넥터 가시 989셀):
#     sd(Z)      범위 [1.000000, 1.000000] · 고유값 1   → 죽은 통계
#     modal_frac 범위 [0.010008, 0.983711] · 고유값 799 → 살아있음
#     uniq_ratio 범위 [0.000589, 0.983240] · 고유값 824 → 살아있음
#   ⇒ 축 D 는 sd 가 아니라 **Coverage 합**으로 판정하고(빌더가 sd<1e-12 를 이미
#     Z=NA→Coverage=FALSE 로 번역해 둔다), 축 T 는 modal_frac 을 쓴다.
#   ⇒ 나아가 **통계가 그 면에서 변동하는지를 가드 자신이 매 빌드 재확인**한다
#     (`stat_liveness`). 퇴화하면 "경보 0"이 아니라 `UNMEASURED` 를 낸다.
#     ★0 을 결론으로 발행하지 않는 것이 이 축들의 계약이다.
#
# 설계 원칙은 위와 동일 — 전부 warn + 기록. **stop() 없음.**
#   정당한 상수 팩터(시장레벨 15종)가 실재하므로 전면 차단은 유해하다.
#==============================================================================

#------------------------------------------------------------------------------
# registry `dedup` → 선언된 중복 쌍 집합. 축 I 는 이 대조 없이는 소음이 된다
# (실측: 대조 없으면 |rho|>=0.99 가 139쌍 상시 발화 → 곧 무시됨. 대조 붙이면 5쌍).
#------------------------------------------------------------------------------
emission_dedup_pairs <- function(registry) {
  if (is.character(registry) && length(registry) == 1L) {
    if (!file.exists(registry)) return(character(0))
    registry <- fromJSON(registry, simplifyVector = FALSE)
  }
  if (!is.list(registry) || length(registry) == 0L) return(character(0))
  keys <- names(registry)
  clus <- vapply(keys, function(k) {
    v <- registry[[k]]$dedup$cluster
    if (is.null(v) || length(v) == 0L) NA_character_ else as.character(v)[1]
  }, character(1))
  pk <- function(a, b) paste(pmin(a, b), pmax(a, b), sep = "||")
  out <- character(0)
  # (1) 같은 cluster 안의 모든 쌍
  for (cl in unique(clus[!is.na(clus)])) {
    mem <- sort(keys[!is.na(clus) & clus == cl])
    if (length(mem) >= 2L) {
      cb <- utils::combn(mem, 2L)
      out <- c(out, pk(cb[1, ], cb[2, ]))
    }
  }
  # (2) canonical / aliases / partners 로 명시된 쌍
  for (k in keys) {
    d <- registry[[k]]$dedup
    if (is.null(d)) next
    linked <- unlist(lapply(c("canonical", "aliases", "partners"), function(f) {
      v <- d[[f]]; if (is.null(v)) character(0) else as.character(unlist(v))
    }), use.names = FALSE)
    linked <- linked[nzchar(linked) & linked != k]
    if (length(linked)) out <- c(out, pk(rep(k, length(linked)), linked))
  }
  unique(out)
}

#------------------------------------------------------------------------------
# 선언 래칫 — 정당한 상수/중복을 축별로 선언한다 (emission_expected_absent 방식 답습)
#------------------------------------------------------------------------------
emission_load_identity_baseline <- function(path) {
  empty <- data.table(factor = character(), axis = character(),
                      reason = character(), diagnosed = logical())
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(empty)
  b <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(b) || is.null(b$declared) || length(b$declared) == 0L) return(empty)
  rbindlist(lapply(b$declared, function(e) data.table(
    factor    = as.character(e$factor)[1],
    axis      = if (is.null(e$axis)) "D" else as.character(e$axis)[1],
    reason    = if (is.null(e$reason)) NA_character_ else as.character(e$reason)[1],
    diagnosed = isTRUE(e$diagnosed))))
}

#------------------------------------------------------------------------------
# ★핵심 순수 함수 — 위반 주입 테스트가 직접 구동하는 지점
#
# @param result     data.table(Factor_Name, Ticker, Raw_Value, Z_Score, Coverage)
#                   = 빌더가 write 직전에 쥐고 있는 바로 그 객체
# @param dedup_pairs emission_dedup_pairs() 산출 ("a||b" 정렬 키)
# @param identity_baseline emission_load_identity_baseline() 산출
# @return list(axis_D, axis_T, axis_I, warnings, verdict)  ★stop() 하지 않는다
#------------------------------------------------------------------------------
factor_identity_check <- function(result, ym,
                                  dedup_pairs = character(0),
                                  identity_baseline = NULL,
                                  tie_warn = 0.99, tie_watch = 0.95,
                                  rho_warn = 0.999, min_obs = 30L,
                                  value_col = "Z_Score",
                                  max_identity_factors = 1200L) {
  ym_cur <- as.character(ym)[1]
  if (is.null(identity_baseline)) {
    identity_baseline <- data.table(factor = character(), axis = character(),
                                    reason = character(), diagnosed = logical())
  }
  decl_axis <- function(ax) identity_baseline[axis == ax | axis == "ALL", factor]
  warnings <- character(0)
  na_dt <- function(...) data.table(...)

  # ── 입력 계약 검사. ★못 재는 상태를 "이상 없음"으로 내려앉히지 않는다 ─────────
  need <- c("Factor_Name", "Coverage")
  missing_cols <- if (!is.data.table(result)) need else setdiff(need, names(result))
  if (length(missing_cols) > 0L || is.null(result) || nrow(result) == 0L) {
    why <- if (is.null(result) || !is.data.table(result)) "result 가 data.table 이 아님"
           else if (nrow(result) == 0L) "result 0행"
           else sprintf("필수 컬럼 결측: %s", paste(missing_cols, collapse = ","))
    return(list(guard = "factor_identity_check", version = "1.0", ym = ym_cur,
                axis_D = list(status = "UNMEASURED", reason = why, dead = character(0),
                              dead_declared = character(0), detail = na_dt()),
                axis_T = list(status = "UNMEASURED", reason = why, tie_warn = character(0),
                              tie_watch = character(0), stat_liveness = NA_real_, detail = na_dt()),
                axis_I = list(status = "UNMEASURED", reason = why, undeclared = na_dt(),
                              n_pairs_hit = 0L, n_declared = 0L, detail = na_dt()),
                warnings = sprintf("[identity_guard] %s — 3축 전부 측정 불가 (%s). ★'경보 0'이 아니라 UNMEASURED 다", ym_cur, why),
                verdict = "UNMEASURED"))
  }

  cov_ok <- result$Coverage %in% TRUE
  # ── 축 D: 무분산/죽은 배출 (행은 나오는데 소비면 도달 0) ────────────────────
  #   ★sd 로 판정하지 않는다 — 빌더가 sd<1e-12 를 이미 Z=NA→Coverage=FALSE 로
  #     번역해 두었고, Z 면의 sd 는 표준화 항등이라 판별력이 0이다.
  dD <- result[, .(n_rows = .N, n_cov = sum(Coverage %in% TRUE),
                   n_tickers = uniqueN(Ticker)), by = Factor_Name]
  dD[, dead := n_rows > 0L & n_cov == 0L]
  dead_all  <- sort(dD[dead == TRUE, Factor_Name])
  dead_decl <- intersect(dead_all, decl_axis("D"))
  dead_new  <- setdiff(dead_all, dead_decl)
  if (length(dead_new) > 0L) {
    warnings <- c(warnings, sprintf(
      "[identity_guard] %s — 죽은 배출(축 D) %d종: 행은 배출되나 Coverage 전건 FALSE → 소비면 0행이고 선언에도 없음 → %s",
      ym_cur, length(dead_new), paste(dead_new, collapse = ", ")))
  }

  # ── 축 T·I 는 소비면(커버된 행) 위에서 잰다 ─────────────────────────────────
  vcol <- if (value_col %in% names(result)) value_col else NA_character_
  live <- if (!is.na(vcol)) result[cov_ok & is.finite(get(vcol))] else result[0L]

  axis_T <- list(status = "UNMEASURED", reason = NA_character_,
                 tie_warn = character(0), tie_watch = character(0),
                 stat_liveness = NA_real_, detail = na_dt())
  axis_I <- list(status = "UNMEASURED", reason = NA_character_, undeclared = na_dt(),
                 n_pairs_hit = 0L, n_declared = length(dedup_pairs), detail = na_dt())

  if (is.na(vcol)) {
    r <- sprintf("value_col '%s' 부재 — 축 T/I 측정 불가", value_col)
    axis_T$reason <- r; axis_I$reason <- r
    warnings <- c(warnings, sprintf("[identity_guard] %s — %s. ★'경보 0'이 아니라 UNMEASURED", ym_cur, r))
  } else if (nrow(live) == 0L) {
    r <- "커버된 유한값 0행 — 축 T/I 측정 불가"
    axis_T$reason <- r; axis_I$reason <- r
    warnings <- c(warnings, sprintf("[identity_guard] %s — %s. ★'경보 0'이 아니라 UNMEASURED", ym_cur, r))
  } else {
    # ── 축 T: 동률/준-죽은 배출 ──────────────────────────────────────────────
    tstat <- live[, {
      v <- sort(round(get(vcol), 10))
      r <- rle(v)
      .(n_obs = length(v), modal_frac = max(r$lengths) / length(v),
        uniq_ratio = length(r$lengths) / length(v))
    }, by = Factor_Name]
    tstat <- tstat[n_obs >= min_obs]
    if (nrow(tstat) == 0L) {
      axis_T$reason <- sprintf("min_obs=%d 이상인 팩터 없음", min_obs)
      warnings <- c(warnings, sprintf("[identity_guard] %s — 축 T %s. ★UNMEASURED", ym_cur, axis_T$reason))
    } else {
      # ★통계 자신의 생존 확인 — 퇴화하면 '경보 0'이 아니라 UNMEASURED 를 낸다.
      #   단 "상수"만으로 판정하면 안 된다: 값이 전부 서로 다른 건강한 패널은
      #   modal_frac 이 전 팩터에서 바닥값 1/n 으로 **정당하게** 같다. 죽은 통계
      #   (sd(Z)=1 항등)는 상수이면서 그 값이 **바닥이 아니다**. 두 조건을 함께 본다.
      liveness <- if (nrow(tstat) >= 10L) stats::sd(tstat$modal_frac, na.rm = TRUE) else NA_real_
      axis_T$stat_liveness <- liveness
      floor_lvl <- 2 / stats::median(tstat$n_obs)
      degenerate <- nrow(tstat) >= 10L && (is.na(liveness) || liveness < 1e-9) &&
                    stats::median(tstat$modal_frac) > floor_lvl
      if (degenerate) {
        axis_T$status <- "UNMEASURED"
        axis_T$reason <- sprintf("modal_frac 이 %d종에서 전부 동일(sd=%.3e)하고 그 값 %.4f 이 바닥 %.4f 을 넘음 — 계측 사망 (sd(Z)=1 항등과 같은 계통)",
                                 nrow(tstat), liveness, stats::median(tstat$modal_frac), floor_lvl)
        warnings <- c(warnings, sprintf("[identity_guard] %s — ★축 T 계측 사망 의심: %s", ym_cur, axis_T$reason))
      } else {
        axis_T$status <- "OK"
        tw <- sort(setdiff(tstat[modal_frac >= tie_warn, Factor_Name], decl_axis("T")))
        tc <- sort(setdiff(tstat[modal_frac >= tie_watch & modal_frac < tie_warn, Factor_Name], decl_axis("T")))
        axis_T$tie_warn <- tw; axis_T$tie_watch <- tc
        if (length(tw) > 0L) {
          warnings <- c(warnings, sprintf(
            "[identity_guard] %s — 동률 배출(축 T) %d종: 최빈값 점유율 >= %.2f → %s",
            ym_cur, length(tw), tie_warn,
            paste(sprintf("%s(%.4f)", tw, tstat[match(tw, Factor_Name), modal_frac]), collapse = ", ")))
        }
      }
      axis_T$detail <- tstat[order(-modal_frac)]
    }

    # ── 축 I: 정체/중복 배출 (랭크 상관) ─────────────────────────────────────
    #   ★값 차이(maxdiff)가 아니라 **랭크**로 잰다. C09 = sign(sue)*sue^2 는
    #     순증가 단조변환이라 maxdiff 1.85 인데 순위는 동일 — 값 축은 못 잡는다.
    #   ★계열(prefix) 안으로 좁히지 않는다. C11≡M25 는 계열 교차이고,
    #     전x전 격자 비용은 월 0.85초로 실측됐다.
    nf <- uniqueN(live$Factor_Name)
    if (nf < 2L) {
      axis_I$reason <- sprintf("팩터 %d종 — 쌍 없음", nf)
    } else if (nf > max_identity_factors) {
      axis_I$reason <- sprintf("팩터 %d종 > 상한 %d — 격자 생략", nf, max_identity_factors)
      warnings <- c(warnings, sprintf("[identity_guard] %s — 축 I %s. ★UNMEASURED", ym_cur, axis_I$reason))
    } else {
      W <- dcast(live, Ticker ~ Factor_Name, value.var = vcol, fun.aggregate = function(x) x[1])
      M <- as.matrix(W[, -1L, with = FALSE])
      R <- vapply(seq_len(ncol(M)), function(j) {
        v <- M[, j]; r <- rep(NA_real_, length(v)); k <- is.finite(v)
        if (any(k)) r[k] <- rank(v[k], ties.method = "average")
        r
      }, numeric(nrow(M)))
      R <- matrix(R, ncol = ncol(M), dimnames = list(NULL, colnames(M)))
      C <- suppressWarnings(stats::cor(R, use = "pairwise.complete.obs"))
      A <- is.finite(R); storage.mode(A) <- "integer"; N <- crossprod(A)
      ut <- upper.tri(C)
      hit <- which(ut & is.finite(C) & abs(C) >= rho_warn & N >= min_obs, arr.ind = TRUE)
      gn <- colnames(M)
      det <- if (nrow(hit) == 0L) na_dt() else data.table(
        factor_a = gn[hit[, 1]], factor_b = gn[hit[, 2]],
        abs_rho = abs(C[hit]), signed_rho = C[hit], n_common = as.integer(N[hit]))
      axis_I$status <- "OK"
      axis_I$n_pairs_hit <- nrow(det)
      if (nrow(det) > 0L) {
        det[, pair_key := paste(pmin(factor_a, factor_b), pmax(factor_a, factor_b), sep = "||")]
        det[, declared := pair_key %in% dedup_pairs]
        setorder(det, -abs_rho)
        axis_I$detail <- det
        und <- det[declared == FALSE]
        axis_I$undeclared <- und
        if (nrow(und) > 0L) {
          warnings <- c(warnings, sprintf(
            "[identity_guard] %s — 중복 배출(축 I) 미선언 %d쌍 (|rho| >= %.3f, 선언 %d쌍은 침묵): %s",
            ym_cur, nrow(und), rho_warn, det[declared == TRUE, .N],
            paste(sprintf("%s~%s(%.6f)", und$factor_a, und$factor_b, und$abs_rho), collapse = ", ")))
        }
      }
    }
  }
  axis_D <- list(status = "OK", reason = NA_character_, dead = dead_new,
                 dead_declared = dead_decl,
                 detail = dD[order(-as.integer(dead), Factor_Name)])

  undiag <- identity_baseline[diagnosed == FALSE, factor]

  list(guard = "factor_identity_check", version = "1.0", ym = ym_cur,
       thresholds = list(tie_warn = tie_warn, tie_watch = tie_watch,
                         rho_warn = rho_warn, min_obs = min_obs, value_col = value_col),
       axis_D = axis_D, axis_T = axis_T, axis_I = axis_I,
       baseline_declared = nrow(identity_baseline),
       baseline_undiagnosed = sort(undiag),
       warnings = warnings,
       verdict = if (length(warnings) > 0L) "WARN" else "OK")
}

#------------------------------------------------------------------------------
# 부작용 래퍼 — 빌더가 부르는 진입점. 경고 발행 + 사이드카 + 원장 append.
# ★어떤 경우에도 빌드를 멈추지 않는다(설계 원칙 ①).
#------------------------------------------------------------------------------
factor_emission_guard <- function(result, ym, fdb_dir, registry_path,
                                  baseline_path = NULL, write_artifacts = TRUE,
                                  identity_baseline_path = NULL,
                                  run_identity = TRUE) {
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

    # ── 정체 검사 3축 (D/T/I) — 존재 확인 다음에 정체 확인 ────────────────────
    # ★가드 자체 실패가 존재 축까지 삼키지 않도록 별도 tryCatch 로 감싼다.
    if (isTRUE(run_identity)) {
      rep$identity <- tryCatch({
        idr <- factor_identity_check(
          result            = result,
          ym                = ym,
          dedup_pairs       = emission_dedup_pairs(registry_path),
          identity_baseline = emission_load_identity_baseline(identity_baseline_path))
        cat(sprintf("  [identity_guard] %s: 죽은배출 %d종(선언 %d) · 동률 %d종(관찰 %d) · 중복 미선언 %d쌍(선언대조 %d쌍) → %s\n",
                    ym, length(idr$axis_D$dead), length(idr$axis_D$dead_declared),
                    length(idr$axis_T$tie_warn), length(idr$axis_T$tie_watch),
                    nrow(idr$axis_I$undeclared), idr$axis_I$n_declared, idr$verdict))
        for (ax in c("axis_D", "axis_T", "axis_I")) {
          if (identical(idr[[ax]]$status, "UNMEASURED")) {
            cat(sprintf("  [identity_guard] ★%s UNMEASURED — %s (경보 0 이 아니다)\n",
                        ax, idr[[ax]]$reason))
          }
        }
        for (w in idr$warnings) warning(w, call. = FALSE)
        idr
      }, error = function(e) {
        warning(sprintf("[identity_guard] 정체 검사 실패 (빌드·존재축은 계속) — %s",
                        conditionMessage(e)), call. = FALSE)
        list(guard = "factor_identity_check", ym = as.character(ym)[1],
             verdict = "UNMEASURED", error = conditionMessage(e))
      })
    }

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

cat("[factor_db] emission_guard.R loaded (v1.1 — 존재축 + 정체 3축 D/T/I)\n")
