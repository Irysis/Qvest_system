## ============================================================================
## register_module.R — 공용 모듈 적재 계약 (Factor Rotation Mode).
## 어느 모드(QEPM / alpha-search / 기타)든 sim_result를 FR 소비 가능 표준형으로 표준화:
##   ① sim_result 스키마 검증 (DAILY_NAV_DT[Date, Strategy_Ret] + bm_xts)
##   ② saveRDS → 04_Research/strategies/{id}/sim_result.rds  (FR canonical 경로)
##   ③ upsert 06_Registry/module_catalog.json  (FR 모듈 SOT — 모드무관·등급무관)
## 등급 무관 등재. 사용여부는 국면조건부 admission(RCMA: regime_module_admission.R)이 판단.
## registry_writer.R 패턴 미러(init→build→read→dedup by id→write). 실측-only.
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
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}
MODULE_CATALOG_PATH <- file.path(.RM_ROOT(), "06_Registry", "module_catalog.json")

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

#' Register a strategy output as an FR-consumable module (mode-agnostic, GRADE-agnostic).
#' @param sim_result list(DAILY_NAV_DT[Date,NAV,Strategy_Ret], bm_xts, ...) (run_monthly_simulation 산출)
#' @param strategy_id 예 "STR_AS_<run_id>" / "STR_1715"
#' @param grade overall 등급(A/B/C/F/ungraded) — 정보용. ★ FR 사용 게이트 아님(RCMA가 국면조건부 판단)
#' @param origin_mode "alpha_search" | "qepm" | "factor_rotation" | ...
#' @param role 선택 (diversifier/defensive/core 등 — RCMA 경제논리 휴리스틱에 활용)
register_module <- function(sim_result, strategy_id, grade = NA_character_,
                            origin_mode = "unknown", role = NA_character_, meta = list(),
                            catalog_path = MODULE_CATALOG_PATH) {
  .validate_module_sim(sim_result)
  root <- .RM_ROOT()

  ## ② canonical sim_result.rds (FR find_sim 경로)
  sdir <- file.path(root, "04_Research", "strategies", strategy_id)
  dir.create(sdir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(sim_result, file.path(sdir, "sim_result.rds"))
  sim_result_path <- file.path("04_Research/strategies", strategy_id, "sim_result.rds")

  d <- as.data.table(sim_result$DAILY_NAV_DT)[, Date := as.Date(Date)]
  entry <- list(
    strategy_id     = strategy_id,
    grade           = grade %||% "ungraded",
    role            = role %||% NA,
    origin_mode     = origin_mode,
    sim_result_path = sim_result_path,
    n_days          = nrow(d),
    date_range      = c(as.character(min(d$Date, na.rm = TRUE)), as.character(max(d$Date, na.rm = TRUE))),
    registered_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )
  if (length(meta)) entry$meta <- meta

  ## ③ upsert module_catalog.json (id 중복 = update)
  cat_obj <- if (file.exists(catalog_path)) {
    tryCatch(fromJSON(catalog_path, simplifyVector = FALSE), error = function(e) NULL)
  } else NULL
  if (is.null(cat_obj) || is.null(cat_obj$modules)) {
    cat_obj <- list(schema_version = "v1.0",
                    note = "FR 모듈 카탈로그 — register_module() 적재. 등급무관(RCMA가 국면조건부 사용 판단). grade_a_catalog(QEPM)와 union으로 build_module_performance가 소비.",
                    modules = list())
  }
  cat_obj$modules[[strategy_id]] <- entry
  cat_obj$last_updated <- entry$registered_at
  cat_obj$n_modules    <- length(cat_obj$modules)

  dir.create(dirname(catalog_path), recursive = TRUE, showWarnings = FALSE)
  write_json(cat_obj, catalog_path, auto_unbox = TRUE, pretty = TRUE, na = "null")

  cat(sprintf("[register_module] %s (grade=%s · origin=%s) → %s + module_catalog(n=%d)\n",
              strategy_id, entry$grade, origin_mode, sim_result_path, cat_obj$n_modules))
  invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path, entry = entry))
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
    ok <- tryCatch({ register_module(sim, basename(dirname(g[1])), grade = s$grade %||% "A",
                                     origin_mode = "qepm", role = s$role %||% NA); TRUE },
                   error = function(e) FALSE)
    if (ok) n <- n + 1L
  }
  cat(sprintf("[register_module] QEPM 일원화: %d 모듈 module_catalog 등재\n", n)); invisible(n)
}

cat("[register_module.R] Loaded — register_module(sim_result, strategy_id, grade, origin_mode, role, meta)\n")
