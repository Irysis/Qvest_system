## ============================================================================
## register_module.R — 공용 모듈 적재 계약 (Factor Rotation Mode).
## 어느 모드(QEPM / alpha-search / ML/DPL)든 sim_result를 표준화하되, FR 소비
## canonical 경로는 "계약 실측 + frozen + provenance hash"가 있는 모듈만 허용한다.
##   ① sim_result 스키마 검증 (DAILY_NAV_DT[Date, Strategy_Ret] + bm_xts)
##   ② 계약 미충족 → stage_artifacts/module_quarantine/{id}/sim_result.rds
##   ③ 계약 충족 → 04_Research/strategies/{id}/sim_result.rds + module_catalog
## 등급은 정보용이다. FR 사용여부는 먼저 본 input floor를 통과한 뒤 RCMA가 판단한다.
## 발효: 2026-06-05 (도훈 mandate: 두 모드 산출물 표준화).
##
## ── 원장 상호배타 계약 (2026-08-02 신설) ────────────────────────────────────
## ★불변식: 하나의 strategy_id 는 module_catalog.modules 와 module_quarantine.modules
##   중 **최대 한 곳**에만 존재한다.
##
## 왜: 구판은 승격 시 기존 quarantine 행을 회수하지 않았다. run_alpha_search 는 같은
##   전략을 두 번 등록한다 — 6c(재측정 전 proxy → quarantine) → 6e(권위 재측정 후
##   backtested → catalog). 두 행이 공존하면 **quarantine 만 읽는 소비자가 최종상태를
##   정반대로 읽는다**(fr_eligible=FALSE = 기각처럼 보이는데 실제 최종은 FR_ELIGIBLE).
##   실사고: 2026-08-02 STANDALONE_TRACK 배관 수리의 "quarantine 에 유실" 오진단.
##   실측 피해 5건 (Chen-Welch STR_AS_20260709_074129_30048 등).
##
## 두 방향 모두 닫는다 (한 방향만 고치면 거울상 결함이 남는다):
##   ㆍ승격(→catalog): quarantine.modules 행을 quarantine.superseded 로 이동
##     (mode="promoted"). **삭제가 아니라 tombstone** — 격리소의 존재이유가 "연구·진단용
##     보존"이므로 proxy 단계 기록(grade/f_grade_reasons/fmt_codes)을 버리지 않는다.
##     동시에 modules 밖으로 빼므로 기존 소비자(modules 순회)는 코드 변경 없이 교정된다.
##   ㆍ강등(catalog 행이 이미 있는데 floor 미달 등록): catalog 행을 지우지 **않고**
##     quarantine.superseded 에 mode="shadowed" 로 기록 + WARN. 근거 = measurement-graduation
##     §1 — proxy 는 backtested 보다 하위 증거 tier 이므로 권위 측정을 뒤집을 수 없다.
##     (6c 는 매 실행 proxy 로 먼저 등록한다. 대칭 삭제로 만들면 재실행 때마다 catalog 행이
##      일시 소멸하고, 6c~6e 사이에 죽으면 영구 소실된다.) 의도적 강등은 거버넌스 수동 작업.
##
## ── 동일-산출물 이명 차단 (2026-08-20 신설) ─────────────────────────────────
## ★불변식: catalog.modules 안에서 하나의 module_hash 는 **최대 한** strategy_id 에만
##   결려 있다(이명 등록은 기본 차단, QVEST_ALLOW_DUP_MODULE_HASH=1 + duplicate_of
##   주석으로만 예외). 근거 실사고 = batch_434 (2026-06-12/13): codegen-blocked 러너를
##   keyword-fallback 콤보로 치환 실행한 batch 가 서로 다른 가설명 116건을 바이트 동일
##   sim_result 로 catalog 에 등재 — 30개 실산출물이 130개 "독립 모듈"로 위장, FR 입력면
##   128/210 오염 + v8.4 ML 원장 "동일 3짝 클러스터 16+9건"의 정체가 이것이었음
##   (16/16·9/9 id 대응 실측). 전수/수리: audits/module_catalog_dup_hash_audit_20260820.
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
  # modules ↔ superseded 도 서로소로 유지한다. 같은 id 가 live 격리로 되돌아오면
  # (catalog 행이 수동 회수된 뒤 등) 낡은 tombstone 은 남겨두면 안 된다.
  if (identical(kind, "quarantine") && !is.null(obj$superseded) &&
      !is.null(obj$superseded[[key]])) obj$superseded[[key]] <- NULL
  obj$last_updated <- entry$registered_at
  obj$n_modules <- length(obj$modules)
  if (!is.null(obj$superseded)) obj$n_superseded <- length(obj$superseded)
  .write_json_obj(obj, path)
  obj$n_modules
}

.now_stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")

#' catalog 원장에 해당 strategy_id 의 live 행이 있으면 그 entry 를, 없으면 NULL.
#' 파일 부재/파손은 NULL — 단 "읽기 실패"와 "행 없음"을 호출부가 구분할 필요가 없는
#' 자리에서만 쓴다(양쪽 다 "회수/차폐할 대상 없음"으로 같게 처리해도 안전).
.catalog_entry <- function(catalog_path, strategy_id) {
  if (!file.exists(catalog_path)) return(NULL)
  obj <- .read_json_obj(catalog_path, NULL)
  if (is.null(obj) || is.null(obj$modules)) return(NULL)
  obj$modules[[strategy_id]]
}

#' catalog 원장에서 같은 module_hash 를 가진 **다른** strategy_id 들을 찾는다.
#' 반환: character(0) = 이명 없음. 파일 부재/파손도 character(0) — 이 자리는
#' "차단할 근거를 못 찾음 = 통과"가 맞는 방향이다(신규 원장 생성 경로를 막으면 안 됨).
.catalog_hash_dups <- function(catalog_path, module_hash, strategy_id) {
  if (!.nz1(module_hash) || !file.exists(catalog_path)) return(character(0))
  obj <- .read_json_obj(catalog_path, NULL)
  if (is.null(obj) || is.null(obj$modules) || !length(obj$modules)) return(character(0))
  ids <- names(obj$modules)
  hit <- vapply(ids, function(id) {
    identical(as.character(obj$modules[[id]]$module_hash %||% ""), as.character(module_hash))
  }, logical(1))
  setdiff(ids[hit], strategy_id)
}

#' quarantine.superseded 에 tombstone 기록. mode = "promoted" | "shadowed".
#'   promoted: 기존 quarantine.modules 행을 회수(이동)한다.
#'   shadowed: 신규 floor-미달 entry 를 modules 에 넣지 않고 여기에만 남긴다.
#' 반환: list(moved=<logical>, n_modules=<int>, n_superseded=<int>).
#'   moved=FALSE 는 "회수할 행이 없었다"(정상)이고, 실패는 stop() 으로 올린다 —
#'   결손을 FALSE 로 내려앉히면 호출부에서 "중복 없음"과 구분되지 않는다.
.supersede_quarantine <- function(quarantine_path, strategy_id, catalog_entry,
                                  mode = c("promoted", "shadowed"),
                                  shadow_entry = NULL) {
  mode <- match.arg(mode)
  obj <- .read_json_obj(quarantine_path, NULL)
  if (is.null(obj)) {
    if (identical(mode, "promoted")) return(list(moved = FALSE, n_modules = 0L, n_superseded = 0L))
    obj <- list(schema_version = "v1.0", modules = list())
  }
  if (is.null(obj$modules)) obj$modules <- list()
  if (is.null(obj$superseded)) obj$superseded <- list()

  row <- if (identical(mode, "promoted")) obj$modules[[strategy_id]] else shadow_entry
  moved <- FALSE
  if (identical(mode, "promoted")) {
    if (is.null(row)) return(list(moved = FALSE,
                                  n_modules = length(obj$modules),
                                  n_superseded = length(obj$superseded)))
    obj$modules[[strategy_id]] <- NULL
    moved <- TRUE
  }
  if (is.null(row)) stop("[register_module] .supersede_quarantine: shadow_entry 없음")

  row$superseded_by <- list(
    registry              = "module_catalog",
    strategy_id           = strategy_id,
    mode                  = mode,
    catalog_registered_at = as.character(catalog_entry$registered_at %||% NA_character_),
    catalog_metric_type   = as.character(catalog_entry$metric_type %||% NA_character_),
    catalog_grade         = as.character(catalog_entry$grade %||% NA_character_),
    catalog_fr_eligible   = isTRUE(catalog_entry$fr_eligible),
    at                    = .now_stamp(),
    reason                = if (identical(mode, "promoted"))
      "catalog 승격으로 격리행 회수 — 최종상태는 module_catalog 를 볼 것"
    else
      "이미 module_catalog 에 등재된 id 에 floor 미달(하위 tier) 등록이 들어옴 — catalog 행이 권위"
  )
  obj$superseded[[strategy_id]] <- row
  obj$last_updated  <- row$superseded_by$at
  obj$n_modules     <- length(obj$modules)
  obj$n_superseded  <- length(obj$superseded)
  obj$superseded_note <- paste(
    "modules 밖으로 뺀 격리 tombstone. 이 id 의 권위 상태는 module_catalog 에 있다.",
    "mode=promoted(승격 회수) / shadowed(catalog 존재 상태의 하위-tier 등록).")
  .write_json_obj(obj, quarantine_path)
  list(moved = moved, n_modules = obj$n_modules, n_superseded = obj$n_superseded)
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
    # 강등 방향: 이미 catalog 에 권위 등재된 id 면 modules 에 넣지 않는다(상호배타 계약).
    cat_row <- .catalog_entry(catalog_path, strategy_id)
    if (!is.null(cat_row)) {
      sh <- .supersede_quarantine(quarantine_path, strategy_id, cat_row,
                                  mode = "shadowed", shadow_entry = entry)
      cat(sprintf(paste0("[register_module] WARN SHADOWED %s — module_catalog 에 이미 권위 등재",
                         "(grade=%s metric=%s reg=%s). floor 미달 등록은 하위 tier 이므로 catalog 를 뒤집지 않는다.\n",
                         "                 → %s + module_quarantine.superseded(mode=shadowed, n=%d) | %s\n"),
                  strategy_id, as.character(cat_row$grade), as.character(cat_row$metric_type),
                  as.character(cat_row$registered_at), sim_result_path, sh$n_superseded, reason))
      return(invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path,
                            entry = entry, fr_eligible = FALSE, quarantined = TRUE,
                            reason = reason, shadowed = TRUE,
                            quarantine_reclaimed = FALSE)))
    }
    n <- .upsert_registry(quarantine_path, strategy_id, entry, kind = "quarantine")
    cat(sprintf("[register_module] QUARANTINE %s (grade=%s · origin=%s) → %s + module_quarantine(n=%d) | %s\n",
                strategy_id, entry$grade, origin_mode, sim_result_path, n, reason))
    return(invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path,
                          entry = entry, fr_eligible = FALSE, quarantined = TRUE,
                          reason = reason, shadowed = FALSE,
                          quarantine_reclaimed = FALSE)))
  }

  # ── 동일-산출물 이명(異名) 등록 차단 (2026-08-20 신설 — batch_434 치환 오염 재발 방지) ──
  # 같은 module_hash(= sim_result 바이트 동일)가 이미 **다른** strategy_id 로 catalog 에
  # 있으면 이 등록은 "새 모듈"이 아니라 기존 산출물의 이명이다. 실사고: 2026-06-12/13
  # batch_434 keyword-fallback 치환이 서로 다른 가설명 116건을 바이트 동일 sim 으로 등재
  # → catalog 275 중 130 이 30개 실산출물의 복제본, FR 입력면(module_performance) 210 중
  # 128 오염 (전수: 04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820).
  # 동일 가설의 의도적 재등록이면 QVEST_ALLOW_DUP_MODULE_HASH=1 로 통과시키되
  # meta$duplicate_of 주석이 강제 기록된다. 같은 id 재등록(upsert 갱신)은 대상 아님.
  # quarantine-행 등록도 대상 아님(소비면이 아니고, run_alpha_search 6c proxy 선등록을 막으면 안 됨).
  dup_ids <- .catalog_hash_dups(catalog_path, contract$module_hash, strategy_id)
  if (length(dup_ids)) {
    if (!.as_flag(Sys.getenv("QVEST_ALLOW_DUP_MODULE_HASH", ""))) {
      stop(sprintf(paste0(
        "[register_module] DUP_MODULE_HASH BLOCK %s: module_hash %s 가 이미 다른 id 로 catalog 에 존재 — %s.\n",
        "  같은 sim_result 를 다른 가설명으로 등재하면 label≠signal 오염(batch_434 계통)이 된다.\n",
        "  동일 가설의 의도적 재등록이면 QVEST_ALLOW_DUP_MODULE_HASH=1 로 재실행 (meta$duplicate_of 자동 기록)."),
        strategy_id, contract$module_hash, paste(dup_ids, collapse = ", ")))
    }
    if (is.null(entry$meta)) entry$meta <- list()
    entry$meta$duplicate_of <- dup_ids[[1]]
    entry$meta$dup_module_hash_ack <- .now_stamp()
    cat(sprintf("[register_module] WARN DUP_MODULE_HASH %s == %s (override 승인) — meta$duplicate_of=%s 기록\n",
                strategy_id, paste(dup_ids, collapse = ", "), dup_ids[[1]]))
  }

  # 승격 방향: catalog 를 **먼저** 쓰고 그 다음 격리행을 회수한다.
  #   역순이면 회수 성공 후 catalog 쓰기 실패 시 두 modules 어디에도 없는 유령이 된다.
  #   이 순서에선 최악이 "구판과 동일한 중복 잔존"이라 되돌림이 안전하다.
  n <- .upsert_registry(catalog_path, strategy_id, entry, kind = "catalog")
  reclaimed <- tryCatch(
    .supersede_quarantine(quarantine_path, strategy_id, entry, mode = "promoted"),
    error = function(e) { attr(e, "qvest_failed") <- TRUE; e })
  if (inherits(reclaimed, "error")) {
    # 실패를 FALSE(=회수할 것 없음)로 내려앉히지 않는다 — NA 로 구분해 올린다.
    cat(sprintf(paste0("[register_module] WARN %s: catalog 승격은 됐으나 quarantine 회수 실패 — ",
                       "중복 행이 남아 있을 수 있다: %s\n"), strategy_id, conditionMessage(reclaimed)))
    reclaimed_flag <- NA
  } else {
    reclaimed_flag <- isTRUE(reclaimed$moved)
    if (reclaimed_flag)
      cat(sprintf("[register_module] RECLAIM %s: module_quarantine.modules → superseded(mode=promoted) (modules n=%d)\n",
                  strategy_id, reclaimed$n_modules))
  }
  cat(sprintf("[register_module] FR-ELIGIBLE %s (grade=%s · origin=%s) → %s + module_catalog(n=%d)\n",
              strategy_id, entry$grade, origin_mode, sim_result_path, n))
  invisible(list(strategy_id = strategy_id, sim_result_path = sim_result_path,
                 entry = entry, fr_eligible = TRUE, quarantined = FALSE,
                 shadowed = FALSE, quarantine_reclaimed = reclaimed_flag))
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
