## ============================================================================
## register_module.R — 공용 모듈 적재 계약 (Factor Rotation Mode).
## 어느 모드(QEPM / alpha-search / ML/DPL)든 sim_result를 표준화하되, FR 소비
## canonical 경로는 "계약 실측 + frozen + provenance hash"가 있는 모듈만 허용한다.
##   ① sim_result 스키마 검증 (DAILY_NAV_DT[Date, Strategy_Ret] + bm_xts)
##   ② 계약 미충족 → stage_artifacts/module_quarantine/{id}/sim_result.rds
##   ③ 계약 충족 → 04_Research/strategies/{id}/sim_result.rds + module_catalog
## 등급은 정보용이다. FR 사용여부는 먼저 본 input floor를 통과한 뒤 RCMA가 판단한다.
## 발효: 2026-06-05 (도훈 mandate: 두 모드 산출물 표준화).
## ============================================================================
suppressMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.na(a)) return(b)
  if (is.character(a) && length(a) == 1 && a == "") return(b)
  a
}

.RM_ROOT <- function() {
  if (exists("PROJECT_ROOT")) return(get("PROJECT_ROOT"))
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
            Sys.getenv("QM_ROOT", unset = ""),
            getwd(),
            "C:/Users/99922/OneDrive/Quant_Module_Moltbot",
            "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot")
  for (p in cand[nzchar(cand)]) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (dir.exists(file.path(p, "02_Infrastructure")) &&
        dir.exists(file.path(p, "04_Research"))) return(p)
  }
  stop("[register_module] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
MODULE_CATALOG_PATH <- file.path(.RM_ROOT(), "06_Registry", "module_catalog.json")
MODULE_QUARANTINE_PATH <- file.path(.RM_ROOT(), "06_Registry", "module_quarantine.json")

#' Validate sim_result is FR-consumable (build_module_performance / run_wf_ensemble 적재 스키마)
.validate_module_sim <- function(sim_result) {
  if (is.null(sim_result) || is.null(sim_result$DAILY_NAV_DT))
    stop("[register_module] sim_result$DAILY_NAV_DT 없음 — FR 적재 불가")
  d <- as.data.table(sim_result$DAILY_NAV_DT)
  if (!all(c("Date", "Strategy_Ret") %in% names(d)))
    stop(sprintf("[register_module] DAILY_NAV_DT에 Date+Strategy_Ret 필요 (현재: %s)", paste(names(d), collapse = ",")))
  if (is.null(sim_result$bm_xts))
    stop("[register_module] sim_result$bm_xts 없음 — active(초과)수익 산출 불가, FR 적재 불가")
  if (sum(is.finite(d$Strategy_Ret)) < 60L)
    stop("[register_module] 유효 일간 Strategy_Ret < 60 — 표본 부족")
  invisible(TRUE)
}

.sim_hash <- function(sim_result) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(sim_result, tmp)
  unname(tools::md5sum(tmp))
}

.nz1 <- function(x) !is.null(x) && length(x) == 1L && !is.na(x) && nzchar(as.character(x))

.as_flag <- function(x) {
  if (isTRUE(x)) return(TRUE)
  if (isFALSE(x) || is.null(x) || length(x) == 0L || is.na(x[1])) return(FALSE)
  tolower(as.character(x[1])) %in% c("true", "t", "1", "yes", "y")
}

.read_json_obj <- function(path, default) {
  if (file.exists(path)) {
    obj <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(obj)) return(obj)
  }
  default
}

.write_json_obj <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(obj, path, auto_unbox = TRUE, pretty = TRUE, na = "null")
}

.contract_from_args <- function(meta, metric_type, contract_pass, frozen,
                                source_contract_id, module_hash, build_version,
                                cost_model_version, bt_result_path) {
  meta_contract <- meta$contract %||% list()
  metric_type <- metric_type %||% meta$metric_type %||% meta_contract$metric_type %||% "proxy"
  contract_pass <- contract_pass %||% meta$contract_pass %||% meta_contract$contract_pass %||% FALSE
  frozen <- frozen %||% meta$frozen %||% meta_contract$frozen %||% FALSE
  source_contract_id <- source_contract_id %||% meta$source_contract_id %||% meta_contract$source_contract_id %||% NA_character_
  module_hash <- module_hash %||% meta$module_hash %||% meta_contract$module_hash %||% NA_character_
  build_version <- build_version %||% meta$build_version %||% meta_contract$build_version %||% NA_character_
  cost_model_version <- cost_model_version %||% meta$cost_model_version %||% meta_contract$cost_model_version %||% NA_character_
  bt_result_path <- bt_result_path %||% meta$bt_result_path %||% meta_contract$bt_result_path %||% NA_character_

  list(metric_type = as.character(metric_type),
       contract_pass = .as_flag(contract_pass),
       frozen = .as_flag(frozen),
       source_contract_id = as.character(source_contract_id),
       module_hash = as.character(module_hash),
       build_version = as.character(build_version),
       cost_model_version = as.character(cost_model_version),
       bt_result_path = as.character(bt_result_path))
}

.eligibility_reason <- function(contract) {
  miss <- character(0)
  if (!identical(contract$metric_type, "backtested")) miss <- c(miss, "metric_type != backtested")
  if (!isTRUE(contract$contract_pass)) miss <- c(miss, "contract_pass != TRUE")
  if (!isTRUE(contract$frozen)) miss <- c(miss, "frozen != TRUE")
  for (nm in c("source_contract_id", "module_hash", "build_version", "cost_model_version")) {
    if (!.nz1(contract[[nm]])) miss <- c(miss, paste0(nm, " missing"))
  }
  if (!length(miss)) "FR_ELIGIBLE" else paste(miss, collapse = "; ")
}

.upsert_registry <- function(path, key, entry, kind = c("catalog", "quarantine")) {
  kind <- match.arg(kind)
  default <- if (identical(kind, "catalog")) {
    list(schema_version = "v2.0",
         note = "FR module catalog. Only fr_eligible=true modules with contract_pass+frozen+hash/build_version are consumed by build_module_performance; grade is informational.",
         modules = list())
  } else {
    list(schema_version = "v1.0",
         note = "Quarantine for module-like outputs that failed the FR input floor. These artifacts are preserved for research/diagnostics but are not consumed by factor rotation.",
         modules = list())
  }
  obj <- .read_json_obj(path, default)
  if (is.null(obj$modules)) obj$modules <- list()
  obj$schema_version <- obj$schema_version %||% default$schema_version
  obj$note <- default$note
  obj$modules[[key]] <- entry
  obj$last_updated <- entry$registered_at
  obj$n_modules <- length(obj$modules)
  .write_json_obj(obj, path)
  obj$n_modules
}

#' Register a strategy output. FR-consumable only when the v8.1 input floor passes.
#' @param sim_result list(DAILY_NAV_DT[Date,NAV,Strategy_Ret], bm_xts, ...) (run_monthly_simulation 산출)
#' @param strategy_id 예 "STR_AS_<run_id>" / "STR_1715"
#' @param grade overall 등급(A/B/C/F/ungraded) — 정보용. FR 입력 floor 통과 후 RCMA가 사용 판단.
#' @param origin_mode "alpha_search" | "qepm" | "factor_rotation" | ...
#' @param role 선택 (diversifier/defensive/core 등 — RCMA 경제논리 휴리스틱에 활용)
register_module <- function(sim_result, strategy_id, grade = NA_character_,
                            origin_mode = "unknown", role = NA_character_, meta = list(),
                            catalog_path = MODULE_CATALOG_PATH,
                            metric_type = NULL, contract_pass = NULL, frozen = NULL,
                            source_contract_id = NULL, module_hash = NULL,
                            build_version = NULL, cost_model_version = NULL,
                            bt_result_path = NULL,
                            quarantine_path = MODULE_QUARANTINE_PATH,
                            allow_quarantine = TRUE) {
  .validate_module_sim(sim_result)
  root <- .RM_ROOT()
  if (is.null(meta)) meta <- list()
  contract <- .contract_from_args(meta, metric_type, contract_pass, frozen,
                                  source_contract_id, module_hash, build_version,
                                  cost_model_version, bt_result_path)
  if (!.nz1(contract$module_hash)) contract$module_hash <- .sim_hash(sim_result)
  reason <- .eligibility_reason(contract)
  fr_eligible <- identical(reason, "FR_ELIGIBLE")

  rel_dir <- if (fr_eligible) {
    file.path("04_Research", "strategies", strategy_id)
  } else {
    file.path("stage_artifacts", "module_quarantine", strategy_id)
  }
  sdir <- file.path(root, rel_dir)
  dir.create(sdir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(sim_result, file.path(sdir, "sim_result.rds"))
  sim_result_path <- file.path(rel_dir, "sim_result.rds")

  d <- as.data.table(sim_result$DAILY_NAV_DT)[, Date := as.Date(Date)]
  entry <- list(
    strategy_id     = strategy_id,
    grade           = grade %||% "ungraded",
    role            = role %||% NA,
    origin_mode     = origin_mode,
    sim_result_path = sim_result_path,
    n_days          = nrow(d),
    date_range      = c(as.character(min(d$Date, na.rm = TRUE)), as.character(max(d$Date, na.rm = TRUE))),
    registered_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    metric_type     = contract$metric_type,
    fr_eligible     = fr_eligible,
    frozen          = contract$frozen,
    source_contract_id = contract$source_contract_id,
    module_hash     = contract$module_hash,
    build_version   = contract$build_version,
    cost_model_version = contract$cost_model_version,
    bt_result_path  = contract$bt_result_path,
    contract        = list(
      policy = "v8.1_fr_input_floor",
      contract_pass = contract$contract_pass,
      eligibility_reason = reason
    )
  )
  if (length(meta)) entry$meta <- meta

  if (!fr_eligible) {
    if (!isTRUE(allow_quarantine)) {
      stop(sprintf("[register_module] FR input floor failed for %s: %s", strategy_id, reason))
    }
    n <- .upsert_registry(quarantine_path, strategy_id, entry, kind = "quarantine")
    cat(sprintf("[register_module] QUARANTINE %s (grade=%s · origin=%s) → %s + module_quarantine(n=%d) | %s\n",
                strategy_id, entry$grade, origin_mode, sim_result_path, n, reason))
    return(invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path,
                          entry = entry, fr_eligible = FALSE, quarantined = TRUE,
                          reason = reason)))
  }

  n <- .upsert_registry(catalog_path, strategy_id, entry, kind = "catalog")
  cat(sprintf("[register_module] FR-ELIGIBLE %s (grade=%s · origin=%s) → %s + module_catalog(n=%d)\n",
              strategy_id, entry$grade, origin_mode, sim_result_path, n))
  invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path,
                 entry = entry, fr_eligible = TRUE, quarantined = FALSE))
}

#' (선택) QEPM grade_a_catalog 전략들을 module_catalog로 일원화 등재.
#' QEPM은 이미 build_module_performance의 grade_a_catalog union으로 FR 소비 가능(native).
#' 본 helper는 향후 module_catalog 단일경로 일원화를 원할 때 명시 호출(중복 등재라 기본 미실행).
register_existing_qepm_modules <- function(catalog_json = file.path(.RM_ROOT(), "04_Research/grade_a_catalog.json")) {
  if (!file.exists(catalog_json)) { cat("[register_module] grade_a_catalog 없음\n"); return(invisible(0L)) }
  strat <- tryCatch(fromJSON(catalog_json, simplifyVector = FALSE)$strategies, error = function(e) NULL)
  if (is.null(strat)) return(invisible(0L))
  n <- 0L
  for (s in strat) {
    sid <- s$strategy_id %||% NA_character_; if (is.na(sid)) next
    g <- Sys.glob(file.path(.RM_ROOT(), "04_Research/strategies", paste0(sid, "*"), "sim_result.rds"))
    if (!length(g)) next
    sim <- tryCatch(readRDS(g[1]), error = function(e) NULL); if (is.null(sim)) next
    ok <- tryCatch({ register_module(
      sim, basename(dirname(g[1])), grade = s$grade %||% "A",
      origin_mode = "qepm", role = s$role %||% NA,
      metric_type = "backtested", contract_pass = TRUE, frozen = TRUE,
      source_contract_id = paste0("legacy_grade_a_catalog:", sid),
      build_version = "legacy_qepm_grade_a_catalog",
      cost_model_version = "legacy_qepm_cost_label_unknown",
      meta = list(legacy_migration_exception = TRUE,
                  grade_a_catalog_source = s$source %||% NA)
    ); TRUE },
                   error = function(e) FALSE)
    if (ok) n <- n + 1L
  }
  cat(sprintf("[register_module] QEPM 일원화: %d 모듈 module_catalog 등재\n", n)); invisible(n)
}

cat("[register_module.R] Loaded — register_module(sim_result, strategy_id, grade, origin_mode, role, meta)\n")
