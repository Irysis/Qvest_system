#!/usr/bin/env Rscript
#==============================================================================
# retro_rolling_defensive.R — 롤링 등급·방어형 스코어 **소급 적용** (도훈 지시 2026-09-04)
#
# 무엇을 하나: 이미 측정된 replication 산출물 전건에 대해
#   ① 롤링 등급 지표(rolling_grade) · 방어형 스코어(defensive_score) 를 산출해 기입
#   ② F 구제 조건을 만족하면 essence_grade 를 F -> C 로 올리고 grade_base 에 원값 보존
#   ③ 강화 원장(reinforce_ledger_l1.json)의 grade 미러도 함께 갱신
#
# ★왜 원장까지 건드리나: 원장의 grade 는 산출물의 **미러**다. 한쪽만 고치면 두 원장이
#   갈리고, 갈린 뒤엔 어느 쪽이 맞는지 아무도 모른다 — 오늘 큐 카운터에서 밟은 형태다.
#
# ★원장 매칭 규약: attempt 에 strategy_id/run_id **필드가 없다**(실측: 385 attempt 중
#   그 키를 가진 것 0건). 대신 343건이 `artifacts` 경로 문자열 안에 run id 를 담고 있다.
#   그래서 attempt 를 JSON 으로 직렬화해 run id 를 **검색**한다. 고정 필드가 생기면
#   그때 이 경로를 걷어낼 것 — 지금은 blob 검색이 유일하게 작동하는 링크다.
#
# ★감사 가능성: 원값을 지우지 않는다. grade_base 보존 + retro 블록에 적용 시각·사유 기록.
#   재실행해도 멱등이다(이미 소급된 건은 건너뛴다). 원장은 쓰기 전에 백업한다.
#
# 사용: Rscript -e 'source(".../retro_rolling_defensive.R")'          # dry-run
#       RETRO_APPLY=1 Rscript -e 'source(".../retro_rolling_defensive.R")'  # 실제 적용
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
APPLY <- identical(Sys.getenv("RETRO_APPLY", "0"), "1")

suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/rolling_grade.R")))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/defensive_score.R")))
RP <- rg_params(ROOT); DP <- ds_params(ROOT)
STAMP <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

.wr <- function(obj, path) {
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 8)
  if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
    stop("재파싱 검증 실패: ", path)
  tmp <- paste0(path, ".tmp"); write(txt, tmp)
  if (!suppressWarnings(file.rename(tmp, path))) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(TRUE)
}

# ── 1. 산출물 순회 ───────────────────────────────────────────────────────────
ds <- list.dirs(file.path(ROOT, "stage_artifacts/replication"), recursive = FALSE)
LOG <- list(); n_seen <- 0L; n_roll <- 0L; n_def <- 0L; n_skip <- 0L
for (dd in ds) {
  fa <- file.path(dd, "authoritative_remeasure.json")
  fr <- file.path(dd, "03_period_returns.csv"); fb <- file.path(dd, "05_benchmark_returns.csv")
  if (!file.exists(fa) || !file.exists(fr)) next
  aj <- tryCatch(fromJSON(fa, simplifyVector = FALSE), error = function(e) NULL); if (is.null(aj)) next
  n_seen <- n_seen + 1L
  g0 <- as.character(aj$essence_grade %||% NA)
  if (identical(as.character(aj$retro$version %||% ""), "rolling_defensive_v1")) {
    n_skip <- n_skip + 1L; next
  }
  pr <- tryCatch(fread(fr, select = c("date","ret_net"), showProgress = FALSE), error = function(e) NULL)
  br <- if (file.exists(fb)) tryCatch(fread(fb, select = c("date","benchmark_ret"), showProgress = FALSE),
                                      error = function(e) NULL) else NULL
  if (is.null(pr)) next

  roll <- tryCatch(rg_rolling(pr, br, RP), error = function(e) NULL)
  defn <- if (!is.null(br)) tryCatch(ds_score(pr, br, DP), error = function(e) NULL) else NULL
  if (!is.null(roll) && identical(roll$status, "ok")) n_roll <- n_roll + 1L
  if (!is.null(defn) && identical(defn$status, "ok")) n_def <- n_def + 1L

  resc <- if (!is.na(g0)) tryCatch(rg_rescue(g0, roll, RP), error = function(e) NULL) else NULL
  g1 <- if (!is.null(resc) && isTRUE(resc$rescued)) resc$new_grade else g0

  LOG[[length(LOG)+1L]] <- data.table(
    run = basename(dd), sid = as.character(aj$strategy_id %||% ""),
    g0 = g0, g1 = g1, changed = !identical(g0, g1),
    pass_life = roll$pass_life %||% NA_real_, pass_recent = roll$pass_recent %||% NA_real_,
    prior_rec = as.integer(roll$history$prior_recoveries %||% NA_integer_),
    cur_calmar = roll$current$calmar %||% NA_real_,
    defensive = defn$defensive %||% NA,
    down_excess = defn$down$excess %||% NA_real_, down_t = defn$down$t %||% NA_real_)

  if (APPLY) {
    if (!identical(g0, g1)) {
      aj$grade_base <- g0; aj$essence_grade <- g1
      aj$reasons <- paste0(as.character(aj$reasons %||% ""),
                           "; [소급 2026-09-04] recent_regime 구제(", g0, "->", g1, "): ", resc$reason)
    }
    aj$rolling_grade <- if (is.null(roll) || !identical(roll$status, "ok")) NULL else list(
      status = roll$status, n_points = roll$n_points, window_months = roll$window_months,
      pass_life = round(roll$pass_life, 4), pass_recent = round(roll$pass_recent, 4),
      current = roll$current, prior_recoveries = roll$history$prior_recoveries,
      current_run = roll$history$current_run, span = roll$span)
    aj$defensive_score <- if (is.null(defn) || !identical(defn$status, "ok")) NULL else list(
      status = defn$status, defensive = defn$defensive,   # convex 폐기 2026-09-07
      down = defn$down, mid = defn$mid, deep = defn$deep, up = defn$up, reason = defn$reason)
    aj$recent_regime_rescued <- isTRUE(resc$rescued)
    aj$retro <- list(version = "rolling_defensive_v1", applied_at = STAMP,
                     grade_before = g0, grade_after = g1,
                     note = "롤링 등급 지표·방어형 스코어 소급 산출 + F 구제 적용. 원값은 grade_base 보존.")
    tryCatch(.wr(aj, fa),
             error = function(e) cat(sprintf("  !! 쓰기 실패 %s: %s\n", basename(dd), conditionMessage(e))))
  }
}
D <- rbindlist(LOG, fill = TRUE)

# ── 2. 원장 grade 미러 ───────────────────────────────────────────────────────
.led_changed <- 0L; .led_unmatched <- 0L
if (nrow(D) && any(D$changed)) {
  CHG <- D[changed == TRUE]
  LP <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")
  led <- if (file.exists(LP)) tryCatch(fromJSON(LP, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (!is.null(led)) {
    BK <- paste0(LP, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    if (APPLY) file.copy(LP, BK)
    for (i in seq_along(led$entries)) {
      ats <- led$entries[[i]]$attempts %||% list()
      for (j in seq_along(ats)) {
        blob <- tryCatch(toJSON(ats[[j]], auto_unbox = TRUE, null = "null"), error = function(e) "")
        hit <- CHG$run[vapply(CHG$run, function(r) grepl(r, blob, fixed = TRUE), logical(1))]
        if (!length(hit)) next
        newg <- CHG$g1[match(hit[1], CHG$run)]
        oldg <- as.character(ats[[j]]$grade %||% "")
        if (identical(oldg, newg)) next
        .led_changed <- .led_changed + 1L
        if (APPLY) {
          led$entries[[i]]$attempts[[j]]$grade_base <- ats[[j]]$grade
          led$entries[[i]]$attempts[[j]]$grade <- newg
          led$entries[[i]]$attempts[[j]]$retro <- "rolling_defensive_v1"
        }
      }
    }
    .led_unmatched <- nrow(CHG) - .led_changed
    if (APPLY && .led_changed > 0L) {
      led$retro_rolling_defensive <- list(applied_at = STAMP, n_attempts = .led_changed,
        n_artifact_changes = nrow(CHG), backup = basename(BK),
        note = "산출물 소급과 동기 — 원장 grade 는 미러다. 원값은 attempt.grade_base 보존. 매칭 = artifacts 경로 안 run id 검색(attempt 에 strategy_id/run_id 필드가 없다).")
      tryCatch(.wr(led, LP),
               error = function(e) cat(sprintf("  !! 원장 쓰기 실패: %s\n", conditionMessage(e))))
    }
  }
}

# ── 3. 보고 ──────────────────────────────────────────────────────────────────
cat(sprintf("\n=== 소급 %s ===\n", if (APPLY) "적용" else "DRY-RUN (쓰기 없음)"))
cat(sprintf("산출물 %d건 · 롤링 산출 %d · 방어형 산출 %d · 이미 적용됨 %d\n",
            n_seen, n_roll, n_def, n_skip))
if (nrow(D)) {
  cat(sprintf("\n등급 이동 %d건\n", sum(D$changed)))
  if (any(D$changed)) print(D[changed == TRUE, .N, by = .(g0, g1)])
  cat(sprintf("\n방어형 %d / %d\n", sum(D$defensive %in% TRUE), sum(!is.na(D$defensive))))
  z <- D[changed == TRUE & is.finite(prior_rec)]
  if (nrow(z)) cat(sprintf("구제 대상 중 過去 회복 前例 있음: %d / %d (중앙 %s회)\n",
                           sum(z$prior_rec > 0), nrow(z), as.character(median(z$prior_rec))))
  cat(sprintf("\n원장 미러: %d개 attempt %s · 미매칭 %d\n", .led_changed,
              if (APPLY) "갱신" else "갱신 예정", max(0L, .led_unmatched)))
  outp <- file.path(ROOT, "06_Registry/retro_rolling_defensive_report.csv")
  fwrite(D, outp)
  cat(sprintf("상세: %s\n", sub(paste0(ROOT, "/"), "", outp)))
}
