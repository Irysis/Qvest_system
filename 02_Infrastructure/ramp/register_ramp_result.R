## register_ramp_result.R — RAMP_XXXX 운용체계 등급 레지스트리 writer.
## factor_rotation_registry.R 패턴 clone. RAMP 운영체계(풀 + 순수팩터군 + M-code + 배분정책 + 등급)를 적재.
## ★실측-only: ramp$metric_type=backtested(build_bt_result/canonical_screen_bt) 아니면 등재 거부.
##   (hook `ramp_measurement_gate.sh`가 PreToolUse[Write]로 보강 — subprocess write 대비 R 계약 내부 게이트가 1차.)
## 출력 메타 §2.4: as_of_date/generated_at/source_version + security_id 매핑 문서화.

suppressMessages({ library(jsonlite) })

RAMP_REGISTRY_PATH <- "06_Registry/ramp/ramp_registry.json"

#' RAMP 운용체계 결과를 레지스트리에 upsert (실측-only hard gate)
#' @param ramp list(ramp_id, grade, metric_type, essence, ccs, module_pool, factor_groups,
#'                  mcode_specs, allocation_policy, regime_engine_version, n_trials, generated_at, source_version)
#' @return 등재된 ramp_id (거부 시 stop)
register_ramp_result <- function(ramp,
                                 regime_engine_version = NA_character_,
                                 allocation_policy = NA_character_,
                                 path = RAMP_REGISTRY_PATH) {
  stopifnot(is.list(ramp), !is.null(ramp$ramp_id))

  # ── 실측-only HARD GATE ──
  mt <- ramp$metric_type %||% "unknown"
  if (!identical(mt, "backtested")) {
    stop(sprintf("[register_ramp_result][BLOCKED] %s: metric_type='%s' != 'backtested'. proxy/estimated/자체합성 등재 거부(룰 §4, AX-002).",
                 ramp$ramp_id, mt))
  }
  # 자체합성 흔적 차단(방어)
  if (isTRUE(ramp$self_synthesized)) {
    stop(sprintf("[register_ramp_result][BLOCKED] %s: self_synthesized=TRUE (prod/cumprod 금지).", ramp$ramp_id))
  }

  # ── load-or-init ──
  reg <- if (file.exists(path)) {
    tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  } else NULL
  if (is.null(reg) || is.null(reg$ramps)) {
    reg <- list(
      schema_version = "v1.0",
      note = "RAMP_XXXX 운용체계 등급 레지스트리(STR 모듈/FR과 분리). register_ramp_result() 적재. 실측-only. 자본 admit은 governor 수동(도훈 confirm).",
      ramps = list()
    )
  }

  entry <- list(
    ramp_id              = ramp$ramp_id,
    grade                = ramp$grade %||% NA,
    metric_type          = "backtested",
    essence              = ramp$essence %||% NULL,
    ccs                  = ramp$ccs %||% NULL,
    module_pool_n        = ramp$module_pool_n %||% NA,
    factor_groups        = ramp$factor_groups %||% NULL,
    mcode_specs          = ramp$mcode_specs %||% NULL,
    allocation_policy    = allocation_policy,
    regime_engine_version= regime_engine_version,
    n_trials             = ramp$n_trials %||% NA,
    as_of_date           = ramp$as_of_date %||% NA,
    generated_at         = ramp$generated_at %||% NA,
    source_version       = ramp$source_version %||% NA,
    capital_state        = "pending_manual"   # governor 정지 — 자본 편입은 수동
  )
  reg$ramps[[ramp$ramp_id]] <- entry

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(reg, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  cat(sprintf("[register_ramp_result] %s 등재 (grade=%s, ccs=%s). capital_state=pending_manual(도훈 confirm).\n",
              ramp$ramp_id, entry$grade %||% "NA", if (is.null(entry$ccs)) "NA" else entry$ccs))
  invisible(ramp$ramp_id)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[register_ramp_result.R] Loaded — register_ramp_result() (실측-only hard gate, governor 정지)\n")
