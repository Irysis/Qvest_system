#!/usr/bin/env Rscript
# overlay_candidate_queue.R — screen_route=OVERLAY_CANDIDATE 소비 배관 (감사 CAP-P1-1, SC-03/04)
#
# 문제: 게이트 2계층(measurement-graduation §3)의 screening tier가 OVERLAY_CANDIDATE 라벨을
#       *생산*만 하고(hurdle_gate.R verdict$screening$screen_route → strategy_manifest.json)
#       소비자가 0 — "MDD 구조 사유로 죽었으나 신호 실재" 후보의 재활용 경로가 라벨에서 끊김.
# 역할: 라벨 보유 후보를 전수 수집해 단일 큐(06_Registry/overlay_candidate_queue.json)에 적재.
#       소비자 = overlay A/B 하네스(02_Infrastructure/ops/auto_regime_overlay_ab.R 계열 —
#       첫 케이스 러너는 02_Infrastructure/regime/overlay_candidate_ab_lh.R).
#
# 스캔 소스:
#   ① stage_artifacts/alpha_search/*/strategy_manifest.json (hurdle_gate 라벨 원산지)
#   ② 06_Registry/module_catalog.json + module_quarantine.json meta (register_module 경유분 — 현재 0건, 배관 선설치)
#   ③ manual_entries — 레지스트리 밖 산출물 수동 등재 (첫 케이스: LH/D2 loser-augment, 07-03 메모리 최우선 큐.
#       수치는 D2_forge_result.rds 실측값을 런타임에 읽음 — 손기입 금지)
# A/B 실측 결과(06_Registry/overlay_ab_results/<id>.json 존재 시) → 후보에 ab_result 첨부 + status="measured".
#
# 실행: Rscript 02_Infrastructure/regime/overlay_candidate_queue.R  (재실행 idempotent — 전량 재생성)
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)

QUEUE_PATH   <- "06_Registry/overlay_candidate_queue.json"
AB_RESULT_DIR <- "06_Registry/overlay_ab_results"

.num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x[1]))
.chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[1])

# ── ① alpha-search strategy_manifest 스캔 ────────────────────────────────────
collect_manifests <- function() {
  files <- Sys.glob("stage_artifacts/alpha_search/*/strategy_manifest.json")
  out <- list()
  for (f in files) {
    m <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(m)) next
    route <- .chr(m$verdict$screening$screen_route)
    if (is.na(route) || !grepl("OVERLAY_CANDIDATE", route, fixed = TRUE)) next
    mt <- m$metrics %||% list()
    out[[length(out) + 1]] <- list(
      id            = .chr(m$strategy_id),
      source        = "alpha_search_manifest",
      source_path   = f,
      strategy_name = .chr(m$strategy_name),
      screen_route  = route,
      label_time    = .chr(m$created_at),
      grade         = .chr(m$verdict$grade),
      essence_grade = .chr(m$authoritative$essence_grade),
      metric_type   = .chr(m$backtest_contract$metric_type) %||% "backtested",
      bt_result_path = .chr(m$execution$bt_result_path),
      signal_summary = list(
        sharpe = .num(mt$Sharpe), cagr_pct = .num(mt$CAGR), mdd_pct = .num(mt$MDD),
        ir = .num(mt$IR), calmar = .num(mt$Calmar), turnover_ann_pct = .num(mt$Turnover_Ann),
        bm_corr = .num(mt$BM_Corr),
        fmt_codes = paste(vapply(m$fmt$code %||% character(0), as.character, ""), collapse = "|")
      )
    )
  }
  out
}

# ── ② register_module 경유분 (module_catalog + module_quarantine) — 배관 선설치 ──
collect_module_registries <- function() {
  out <- list()
  for (reg in c("06_Registry/module_catalog.json", "06_Registry/module_quarantine.json")) {
    if (!file.exists(reg)) next
    d <- tryCatch(fromJSON(reg, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d) || is.null(d$modules)) next
    for (nm in names(d$modules)) {
      mod <- d$modules[[nm]]
      route <- .chr(mod$meta$screen_route %||% mod$screen_route)
      if (is.na(route) || !grepl("OVERLAY_CANDIDATE", route, fixed = TRUE)) next
      out[[length(out) + 1]] <- list(
        id = nm, source = basename(reg), source_path = reg,
        strategy_name = .chr(mod$meta$strategy_name %||% nm),
        screen_route = route, label_time = .chr(mod$registered_at),
        grade = .chr(mod$grade), essence_grade = NA_character_,
        metric_type = .chr(mod$metric_type) %||% NA_character_,
        bt_result_path = .chr(mod$bt_result_path),
        signal_summary = list()
      )
    }
  }
  out
}

# ── ③ manual entries — 레지스트리 밖 산출물 (첫 케이스: LH/D2 loser-augment) ──
# 근거: 메모리 project-smartbeta-allstock-rotation 07-03 "다음 = ① LH → register_module screen-tier
#   (OVERLAY_CANDIDATE) 라벨 적재 ② factor-rotation overlay 소비 실측". register_module 미이행이라 수동 등재.
# config: loser-harvest qm/D0.30/lam0.85 rank3 mf4 tmb18 lv2 lvb20 buf2.5 + iskew5%+amihud5%+gov 배제 @2e8 topn25.
collect_manual <- function() {
  out <- list()
  d2_rds <- "04_Research/factor_rotation/smartbeta_allstock/D2_forge_result.rds"
  if (file.exists(d2_rds)) {
    res <- tryCatch(readRDS(d2_rds), error = function(e) NULL)
    if (!is.null(res)) {
      # forge-authoritative 수치 실독 (D2_forge_bridge.R 산출, weighted_screen_bt/NW lag-3)
      pr <- as.data.table(res$period_returns)
      a  <- pr$ret_net - pr$benchmark_ret
      oos_split <- function(a, frac) {
        n <- length(a); k <- floor(n * frac)
        is_sr <- mean(a[1:k]) / sd(a[1:k]) * sqrt(12)
        oos_sr <- mean(a[(k + 1):n]) / sd(a[(k + 1):n]) * sqrt(12)
        if (!is.finite(is_sr) || is_sr <= 0) return(NA_real_)
        oos_sr / is_sr
      }
      oos_v <- median(sapply(c(.55, .65, .75), function(f) oos_split(a, f)), na.rm = TRUE)
      cagr <- prod(1 + pr$ret_net)^(12 / nrow(pr)) - 1
      mdd  <- { cum <- cumprod(1 + pr$ret_net); abs(min(cum / cummax(cum) - 1)) }
      out[[length(out) + 1]] <- list(
        id            = "LH_D2_loser_augment",
        source        = "manual_memory_20260703",
        source_path   = d2_rds,
        strategy_name = "smartbeta allstock loser-harvest D2 (qm/D0.30/lam0.85 + iskew/amihud/gov 배제, 2e8 topn25)",
        screen_route  = "OVERLAY_CANDIDATE",
        label_time    = format(file.mtime(d2_rds), "%Y-%m-%dT%H:%M:%S%z"),
        grade         = "screen_tier",
        essence_grade = NA_character_,
        metric_type   = "weighted_screen",  # contract-grade(build_benchmark_compare NW lag-3), forge build_bt_result 아님
        bt_result_path = d2_rds,
        signal_summary = list(
          n_months = res$n_months,
          portfolio_alpha_t_nw_lag3 = .num(res$portfolio_alpha_t_nw_lag3),
          information_ratio = .num(res$information_ratio),
          net_sr_active = .num(res$net_sr),
          cagr_pct = round(cagr * 100, 2), mdd_pct = round(mdd * 100, 2),
          calmar = round(cagr / mdd, 3), oos_retention_v2 = round(oos_v, 3),
          turnover_ann_pct = round(.num(res$turnover_annual) * 100, 0),
          note = "graduation 3/3(screen-tier 실측) — 자본게이트 아님. weights=D2_winner_weights.parquet"
        )
      )
    } else cat(sprintf("[queue] WARN: %s 읽기 실패 — LH 수동 등재 생략\n", d2_rds))
  } else cat(sprintf("[queue] WARN: %s 없음 — LH 수동 등재 생략\n", d2_rds))
  out
}

# ── A/B 실측 결과 첨부 ────────────────────────────────────────────────────────
attach_ab_results <- function(cands) {
  for (i in seq_along(cands)) {
    rf <- file.path(AB_RESULT_DIR, paste0(cands[[i]]$id, ".json"))
    if (file.exists(rf)) {
      cands[[i]]$ab_result <- tryCatch(fromJSON(rf, simplifyVector = TRUE), error = function(e) NULL)
      cands[[i]]$status <- "measured"
    } else cands[[i]]$status <- "queued"
  }
  cands
}

# ── main ─────────────────────────────────────────────────────────────────────
build_overlay_candidate_queue <- function(write = TRUE) {
  cands <- c(collect_manifests(), collect_module_registries(), collect_manual())
  # dedupe by id (manifest 우선순위 유지 — 최초 발견분)
  ids <- vapply(cands, function(x) x$id, "")
  cands <- cands[!duplicated(ids)]
  cands <- attach_ab_results(cands)
  queue <- list(
    schema_version = "overlay_candidate_queue_v1",
    generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    producer_ref   = "hurdle_gate.R verdict$screening$screen_route (measurement-graduation §3 screening tier)",
    consumer_ref   = "02_Infrastructure/ops/auto_regime_overlay_ab.R + 02_Infrastructure/regime/overlay_candidate_ab_lh.R",
    note           = "screening tier 라벨 — 자본/졸업 게이트 아님. overlay A/B 실측(clean-timing +1 lag 스트레스 의무) 후 status=measured.",
    n_candidates   = length(cands),
    candidates     = cands
  )
  if (write) {
    write_json(queue, QUEUE_PATH, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
    cat(sprintf("[queue] wrote %s — n_candidates=%d (measured=%d)\n", QUEUE_PATH, length(cands),
                sum(vapply(cands, function(x) identical(x$status, "measured"), FALSE))))
  }
  invisible(queue)
}

if (sys.nframe() == 0L && Sys.getenv("QVEST_OVERLAY_QUEUE_NORUN") != "1") {
  q <- build_overlay_candidate_queue(write = TRUE)
  by_src <- table(vapply(q$candidates, function(x) x$source, ""))
  cat("[queue] by source:\n"); print(by_src)
}
