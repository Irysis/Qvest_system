#==============================================================================
# rf_prereg.R — 사전등록 레버 실험 (P2-01 · 플랜 qvest-1-drifting-eclipse §P2 · 2026-09-25)
#
# ★왜 필요한가: 레버 감사(scratchpad/organic/lever_audit_final.md)는 격자·선택 규칙으로는 A 가 나오지 않는다고
#   결론냈다. 남은 레버(PR-L2 B7 as-of 구조 방어 · PR-L1 벤치 인지 코어-위성)는 사전확률이 낮고(A 1~3%),
#   가장 흔한 결말이 Calmar 축 '미결'이다. 이런 실험은 **결과를 본 뒤 arm·절단일·지표를 바꾸면** 무엇이든
#   '예상대로'로 읽힌다. 이 파일은 그 자유도를 결과 전에 잠근다:
#   ① 스키마 — 가설 · arms(사후 추가 금지) · 지표 3층(1차 기전 · 2차 · 안전) · 성공/실패/멈춤 · 검정력 3종 ·
#      예산 · 사전확률 · hypothesis_index lookup 첨부 · SE 원천(null 희석·블록 부트스트랩 — 위상쌍 금지) · 라벨 4종
#   ② writer — 원자 쓰기 · sha256 고정(색인) · 덮어쓰기 거부 · 초안 개정 = 새 rev · 등록본 개정 = 새 가족
#   ③ 판정(rf_prereg_verdict) — R 계약 산출물만 입력(산출물 sha 대조 · 규약 대조) · 멈춤 조건 기계 집행 ·
#      rf_record_decision(kind='prereg_verdict') · 1회만
#   ④ rf_prereg_run — **드라이런 전용**. 원장 entry 개설은 P1-08(priority/experiment 필드) 뒤 별판(러너 본체 불변)
#   ⑤ (2026-10-03 PREREGFIX · 결정 09-26 [위임]) — 결과 전 잠금을 더 좁힌다:
#      · PREREG-MECHANISM-ONLY-FLOOR (가): 바닥 status confirmed_mechanism_only 는 초안 scope.label=mechanism_only ∧ scope.a_eligible=false
#        일 때만 받는다(+ 바닥 permitted_use·a_eligible·use_restriction.decision_id 일치). A 경로는 confirmed 뿐(fail-closed 유지)
#      · PREREG-POWERED-NULL-CALIBRATION: 판정의 mechanism_detected·powered_null 을 명목 90% CI 가 아니라 등록본의 교정 문턱
#        (power.calibration — bootstrap_p: 교정 α · null_t_quantile: 경험 귀무 t 분위)으로 낸다. 명목 CI 는 병기만
#      · decision_params + 조건 rhs {param: id} — 등록 전 산출 수치(교정 α·경험 귀무 문턱·전달량 하한)를 이름으로 한 곳에 두고
#        조건·교정이 그 이름을 가리킨다. 등록 시 산출물(from: 파일+sha256+경로)·규칙(derive)에서 재도출 — 손 입력 수치는 등록 차단
#      · criteria.validity — 처치 전달 타당성(PR-L2-B7-EXCL-UNIT (c) treatment_dilution): 미달 = status invalid · 라벨 없음 · 1회 기록
#
# ★경계
#   · 등급 대체 아님 — 등급은 essence 하나(authoritative_remeasure.json::essence_grade). 라벨 4종은 레버 가설의 판정이다.
#   · Q-Lead 측정 금지(AX-008) — 판정 입력은 R 계약 산출물(파일 + sha256)만. 손계산·python·LLM 라벨은 거부한다.
#   · 하드코딩 금지 — 수치는 06_Registry/prereg/prereg_config.json(근거 문헌 원문 링크 동봉)에서만 읽는다.
#     설정이 없거나 키가 비면 멈춘다(fail-closed · 코드 안 기본값 없음).
#   · 쓰기 범위 = <root>/06_Registry/prereg/ · <root>/stage_artifacts/prereg/ · rf_decisions.jsonl(판정 1줄) 뿐.
#     원장(reinforce_ledger_l*.json)은 읽기만 한다(드라이런 전후 md5 불변을 스스로 확인).
#   · 루트는 인자로 받는다 — ~/.Renviron QM_ROOT 역류 사고(09-24~25 3건) 뒤 규약: 검사·샌드박스는 root 를 명시한다.
#
# 제공: rf_prereg_config · rf_prereg_validate · rf_prereg_write · rf_prereg_load · rf_prereg_register · rf_prereg_index ·
#       rf_prereg_power · rf_prereg_paired_boot · rf_prereg_se_null · rf_prereg_combine_se · rf_prereg_artifact ·
#       rf_prereg_lineage_n · rf_prereg_lookup · rf_prereg_eval · rf_prereg_verdict · rf_prereg_run
# 재사용(복제 금지): required_effect_size.R::required_effect(MDE) · rf_overlay_adversary.R::adv_block_len·adv_calmar_from_ret ·
#       rf_runner_gates.R::rf_lineage_ids·rf_lineage_measured·rf_selection_accounting(parse 로 정의만) ·
#       reinforce_ledger.R::rf_record_decision·rf_read_decisions · tools/hypothesis_index.R::lookup_hypothesis ·
#       contracts/defensive_score.R::ds_params(심층 문턱)
# 검사: 08_Tests/reinforcement/test_rf_prereg.R (양성 대조 · 위반 주입 · 돌연변이)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RF_PREREG_SCHEMA  <- "rf_prereg_v1"
RF_PREREG_CFG_REL <- "06_Registry/prereg/prereg_config.json"
RF_PREREG_KINDS   <- c("draft", "registered")
RF_PREREG_ROLES   <- c("treatment", "control", "spare")
RF_PREREG_TIERS   <- c("primary", "secondary", "safety")
RF_PREREG_DIRS    <- c("decrease", "increase", "report")
RF_PREREG_SELBASIS <- c("as_of", "none")      # full_sample = C1(D-E) — 스키마가 받지 않는다

# ── 루트 · 시간 · 해시 ────────────────────────────────────────────────────────────────
.rfp_is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
.rfp_root <- function(root = NULL) {
  if (!is.null(root)) {
    if (!.rfp_is_root(root)) stop(sprintf("[rf_prereg] root 가 프로젝트 루트가 아니다(02_Infrastructure/config.R 부재): %s", root))
    return(normalizePath(root, winslash = "/", mustWork = TRUE))
  }
  for (p in unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())))
    if (.rfp_is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  stop("[rf_prereg] project root 미발견 — root 인자 또는 QM_ROOT")
}
.rfp_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.rfp_sha_raw <- function(r) {
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(r, algo = "sha256", serialize = FALSE))
  if (requireNamespace("openssl", quietly = TRUE)) return(as.character(openssl::sha256(r)))
  stop("[rf_prereg] sha256 도구(digest/openssl) 부재")
}
.rfp_read_raw <- function(p) readBin(p, "raw", n = file.info(p)$size)
.rfp_sha_file <- function(p) .rfp_sha_raw(.rfp_read_raw(p))
.rfp_read_json <- function(p) {
  txt <- rawToChar(.rfp_read_raw(p)); Encoding(txt) <- "UTF-8"
  fromJSON(txt, simplifyVector = FALSE)
}
.rfp_json <- function(x) {
  txt <- as.character(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA))
  enc2utf8(paste0(txt, "\n"))
}
.rfp_abs <- function(root, rel) if (grepl("^([A-Za-z]:)?[/\\\\]", rel)) rel else file.path(root, rel)
.rfp_under <- function(root, p) {
  a <- normalizePath(p, winslash = "/", mustWork = FALSE); r <- normalizePath(root, winslash = "/", mustWork = TRUE)
  startsWith(tolower(a), tolower(paste0(r, "/")))
}
.rfp_write_new <- function(path, txt) {
  # 원자 쓰기 + 덮어쓰기 거부: 같은 디렉터리 임시 파일 → 대상 부재 재확인 → rename. 대상이 있으면 쓰지 않는다.
  if (file.exists(path)) stop(sprintf("[rf_prereg] 덮어쓰기 거부: %s", path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(dirname(path), sprintf(".%s.tmp.%d", basename(path), Sys.getpid()))
  con <- file(tmp, open = "wb"); writeBin(charToRaw(txt), con); close(con)
  if (file.exists(path)) { unlink(tmp); stop(sprintf("[rf_prereg] 덮어쓰기 거부(경합): %s", path)) }
  ok <- suppressWarnings(file.rename(tmp, path))
  if (!ok) { unlink(tmp); stop(sprintf("[rf_prereg] 원자 rename 실패 — 쓰지 않았다: %s", path)) }
  invisible(path)
}
.rfp_append_line <- function(path, line) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "ab"); on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(line, "\n"))), con)
}
.rfp_lock <- function(dir, key) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  lk <- file.path(dir, paste0(".lock_", gsub("[^A-Za-z0-9_.-]", "_", key)))
  if (!dir.create(lk, showWarnings = FALSE)) stop(sprintf("[rf_prereg] 다른 writer 가 쓰는 중(잠금 %s) — 쓰지 않는다", lk))
  lk
}

# ── 설정 (fail-closed) ────────────────────────────────────────────────────────────────
rf_prereg_config <- function(root = NULL) {
  root <- .rfp_root(root)
  p <- file.path(root, RF_PREREG_CFG_REL)
  if (!file.exists(p)) stop(sprintf("[rf_prereg] 설정 부재(fail-closed · 코드 기본값 없음): %s", p))
  cfg <- .rfp_read_json(p)
  need <- list(c("layout", "registered_dir"), c("layout", "draft_dir"), c("layout", "index"),
               c("layout", "prereg_id_pattern"), c("layout", "family_id_pattern"), "labels", "label_precedence",
               c("power_gate", "power_target"), c("power_gate", "alpha_two_sided"),
               c("power_gate", "ratio_forbidden_below"), c("power_gate", "ratio_conditional_below"),
               c("power_gate", "ratio_design80_at"), c("se_sources", "allowed"), c("se_sources", "forbidden"),
               c("se_sources", "combine"), c("bootstrap", "B"), c("bootstrap", "ci_level"), c("bootstrap", "block_rule"),
               c("bootstrap", "seed"), c("bootstrap", "ann_periods_daily"), c("bootstrap", "min_valid_frac"),
               c("verdict", "contracts"), c("verdict", "forbidden_contract_labels"), c("verdict", "regime_key"),
               c("verdict", "stats"), c("verdict", "ops"), c("verdict", "forbidden_record_keys"),
               c("verdict", "require_artifact_sha"), c("verdict", "arm_artifacts_after_registration"),
               c("verdict", "pin_to_registration_config"),
               c("registration", "floor_ref_path"), c("registration", "floor_required_fields"),
               c("registration", "floor_status_ok"), c("registration", "floor_selection_basis_ok"),
               c("registration", "floor_forbidden_flag_patterns"), c("run", "required_open_entry_formals"),
               c("registration", "floor_status_mechanism_only"), c("registration", "mechanism_only_scope", "label"),
               c("registration", "mechanism_only_scope", "a_eligible"), c("registration", "floor_permitted_use_mechanism_only"),
               c("verdict", "calibration", "kinds"), c("verdict", "param_derivations"),
               c("verdict", "validity_outcomes"))
  for (k in need) {
    v <- cfg; for (kk in k) v <- if (is.list(v)) v[[kk]] else NULL
    if (is.null(v) || !length(v)) stop(sprintf("[rf_prereg] 설정 키 부재(fail-closed): %s", paste(k, collapse = ".")))
  }
  # 기전 한정 바닥 수락은 'A 자격 없음' 범위에만 — 설정이 a_eligible=true 로 바뀌면 A 경로가 열리는 셈이라 멈춘다
  if (!identical(cfg$registration$mechanism_only_scope$a_eligible, FALSE))
    stop("[rf_prereg] registration.mechanism_only_scope.a_eligible 은 false 여야 한다(기전 한정 바닥은 A 경로가 아니다 · PREREG-MECHANISM-ONLY-FLOOR)")
  if (length(intersect(unlist(cfg$registration$floor_status_mechanism_only), unlist(cfg$registration$floor_status_ok))))
    stop("[rf_prereg] floor_status_mechanism_only ∩ floor_status_ok ≠ ∅ — 기전 한정 상태가 A 경로 상태와 섞였다")
  ck <- cfg$verdict$calibration$kinds
  for (kn in names(ck)) if (!length(unlist(ck[[kn]]$params)) || !length(unlist(ck[[kn]]$stats)))
    stop(sprintf("[rf_prereg] verdict.calibration.kinds.%s 에 params·stats 가 없다", kn))
  if (!all(c("bootstrap_p", "null_t_quantile") %in% names(ck)))
    stop("[rf_prereg] verdict.calibration.kinds 는 bootstrap_p·null_t_quantile 을 싣는다(판정 코드가 아는 종류)")
  if (!setequal(unlist(cfg$labels), c("confirmed", "powered_null", "undetermined", "failed")))
    stop("[rf_prereg] 설정 labels 가 4종(confirmed/powered_null/undetermined/failed)과 다르다")
  if (!setequal(unlist(cfg$label_precedence), unlist(cfg$labels)))
    stop("[rf_prereg] label_precedence 가 labels 의 순열이 아니다")
  if (length(intersect(unlist(cfg$se_sources$allowed), names(cfg$se_sources$forbidden))))
    stop("[rf_prereg] SE 원천 allowed ∩ forbidden ≠ ∅")
  attr(cfg, "sha256") <- .rfp_sha_file(p)
  attr(cfg, "root") <- root
  cfg
}

# ── 색인 (append-only jsonl · 무결성 정본) ───────────────────────────────────────────────
rf_prereg_index <- function(root = NULL, cfg = NULL) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  p <- file.path(root, cfg$layout$index)
  if (!file.exists(p)) return(list())
  L <- readLines(p, warn = FALSE, encoding = "UTF-8"); out <- list()
  for (l in L) {
    if (!nzchar(trimws(l))) next
    r <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(r)) stop(sprintf("[rf_prereg] 색인 파싱 실패 줄 — 색인 손상은 조용히 건너뛰지 않는다: %s", substr(l, 1, 120)))
    out[[length(out) + 1L]] <- r
  }
  out
}
.rfp_idx_find <- function(idx, prereg_id, kind = NULL, rev = NULL) {
  Filter(function(r) identical(r$prereg_id, prereg_id) && (is.null(kind) || identical(r$kind, kind)) &&
           (is.null(rev) || identical(as.integer(r$rev %||% NA), as.integer(rev))), idx)
}

# ── 스키마 검증 ───────────────────────────────────────────────────────────────────────
.rfp_chr1 <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
.rfp_num1 <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
.rfp_ids  <- function(L) vapply(L %||% list(), function(z) as.character(z$id %||% ""), character(1))
.rfp_prob <- function(x) {
  if (.rfp_num1(x)) return(x >= 0 && x <= 1)
  if (is.list(x) && .rfp_num1(x$lo) && .rfp_num1(x$hi)) return(x$lo >= 0 && x$hi <= 1 && x$lo <= x$hi)
  FALSE
}

#' 조건 문법 검사 — list(all=) | list(any=) | list(not=) | 원자 {metric, target, stat, op, rhs}
#'   rhs = 수치 | {ref:{metric,target,stat}, offset?, noise?:{metric,target,stat,k}} | {param: <decision_params id>}
#'   {param} = 등록 전 산출 수치(교정 α · 경험 귀무 문턱 · 전달량 하한)를 이름으로 가리킨다 — 초안에서는 값이 비어도 되고,
#'   등록 단계에서 값·출처(from/derive)가 재도출돼야 한다(rf_prereg_validate registration_blockers)
.rfp_cond_errors <- function(c, decl, where) {
  e <- character(0)
  if (!is.list(c)) return(sprintf("%s: 조건이 객체가 아니다", where))
  if (!is.null(c$all) || !is.null(c$any)) {
    kids <- c$all %||% c$any
    if (!is.list(kids) || !length(kids)) return(sprintf("%s: all/any 가 비었다", where))
    for (i in seq_along(kids)) e <- c(e, .rfp_cond_errors(kids[[i]], decl, sprintf("%s[%d]", where, i)))
    return(e)
  }
  if (!is.null(c$not)) return(.rfp_cond_errors(c$not, decl, paste0(where, ".not")))
  .ref_err <- function(r, w) {
    ee <- character(0)
    if (!(as.character(r$metric %||% "") %in% decl$metrics)) ee <- c(ee, sprintf("%s: 미선언 지표 '%s'", w, r$metric %||% ""))
    if (!(as.character(r$target %||% "") %in% decl$targets)) ee <- c(ee, sprintf("%s: 미선언 대상 '%s'", w, r$target %||% ""))
    if (!(as.character(r$stat %||% "") %in% decl$stats)) ee <- c(ee, sprintf("%s: 미지원 stat '%s'", w, r$stat %||% ""))
    ee
  }
  e <- c(e, .ref_err(c, where))
  if (!(as.character(c$op %||% "") %in% decl$ops)) e <- c(e, sprintf("%s: 미지원 op '%s'", where, c$op %||% ""))
  r <- c$rhs
  if (is.null(r)) e <- c(e, sprintf("%s: rhs 부재", where))
  else if (is.list(r) && !is.null(r$param)) {
    if (length(setdiff(names(r), "param"))) e <- c(e, sprintf("%s: rhs {param} 은 단독이어야 한다(ref·offset·noise 와 섞지 않는다)", where))
    if (!.rfp_chr1(r$param) || !(r$param %in% (decl$params %||% character(0))))
      e <- c(e, sprintf("%s: 미선언 결정 파라미터 '%s'(decision_params)", where, as.character(r$param %||% "")))
  }
  else if (is.list(r)) {
    if (is.null(r$ref)) e <- c(e, sprintf("%s: rhs 객체에 ref 부재", where)) else e <- c(e, .ref_err(r$ref, paste0(where, ".rhs.ref")))
    if (!is.null(r$offset) && !.rfp_num1(r$offset)) e <- c(e, sprintf("%s: rhs.offset 비수치", where))
    if (!is.null(r$noise)) {
      e <- c(e, .ref_err(r$noise, paste0(where, ".rhs.noise")))
      if (!.rfp_num1(r$noise$k) || r$noise$k < 0) e <- c(e, sprintf("%s: rhs.noise.k 비수치/음수", where))
    }
  } else if (!.rfp_num1(r)) e <- c(e, sprintf("%s: rhs 비수치", where))
  e
}
.rfp_cond_targets <- function(c) {
  if (!is.list(c)) return(character(0))
  if (!is.null(c$all) || !is.null(c$any)) return(unique(unlist(lapply(c$all %||% c$any, .rfp_cond_targets))))
  if (!is.null(c$not)) return(.rfp_cond_targets(c$not))
  t <- as.character(c$target %||% character(0))
  if (is.list(c$rhs)) t <- c(t, as.character(c$rhs$ref$target %||% character(0)), as.character(c$rhs$noise$target %||% character(0)))
  unique(t)
}
.rfp_cond_pairs <- function(c) {
  # 조건이 요구하는 (지표|대상) 측정 쌍
  if (!is.list(c)) return(character(0))
  if (!is.null(c$all) || !is.null(c$any)) return(unique(unlist(lapply(c$all %||% c$any, .rfp_cond_pairs))))
  if (!is.null(c$not)) return(.rfp_cond_pairs(c$not))
  p <- paste(c$metric, c$target, sep = "|")
  if (is.list(c$rhs)) {
    p <- c(p, paste(c$rhs$ref$metric, c$rhs$ref$target, sep = "|"))
    if (!is.null(c$rhs$noise)) p <- c(p, paste(c$rhs$noise$metric, c$rhs$noise$target, sep = "|"))
  }
  unique(p)
}
.rfp_cond_params <- function(c) {
  # 조건이 가리키는 결정 파라미터 id
  if (!is.list(c)) return(character(0))
  if (!is.null(c$all) || !is.null(c$any)) return(unique(unlist(lapply(c$all %||% c$any, .rfp_cond_params))))
  if (!is.null(c$not)) return(.rfp_cond_params(c$not))
  if (is.list(c$rhs) && !is.null(c$rhs$param)) return(as.character(c$rhs$param))
  character(0)
}
.rfp_param_ids <- function(pr) .rfp_ids(pr$decision_params)
.rfp_param_vals <- function(pr) {
  # id → 수치(없거나 비유한 = NA) — 판정·등록 검증이 같은 표를 쓴다
  ps <- pr$decision_params %||% list()
  v <- vapply(ps, function(p) if (.rfp_num1(p$value)) as.numeric(p$value) else NA_real_, numeric(1))
  setNames(as.list(v), .rfp_ids(ps))
}
.rfp_scope_mech_only <- function(pr, cfg) {
  # 초안 scope 가 기전 한정(설정 registration.mechanism_only_scope 와 일치)인가 — a_eligible 은 identical(FALSE) 만(NULL·NA·"false" 거부)
  ms <- cfg$registration$mechanism_only_scope
  is.list(pr$scope) && identical(as.character(pr$scope$label %||% ""), as.character(ms$label)) && identical(pr$scope$a_eligible, FALSE)
}
.rfp_scan_forbidden_se <- function(pr, cfg) {
  bad <- names(cfg$se_sources$forbidden)
  used <- c(unlist(pr$se_source$methods), unlist(pr$power$se$source),
            unlist(lapply(pr$se_cells %||% list(), function(z) z$kind)))
  intersect(as.character(used), bad)
}
.rfp_contrast_arms <- function(pr) {
  a <- .rfp_ids(pr$arms); out <- list()
  for (c in pr$contrasts %||% list()) out[[as.character(c$id)]] <- intersect(c(as.character(c$a), as.character(c$b)), a)
  out
}
.rfp_target_arms <- function(pr, t) {
  a <- .rfp_ids(pr$arms)
  if (t %in% a) return(t)
  ca <- .rfp_contrast_arms(pr)
  if (t %in% names(ca)) return(ca[[t]])
  character(0)
}

.rfp_floor_check <- function(pr, root, cfg) {
  e <- character(0); R <- cfg$registration
  fp <- file.path(root, R$floor_ref_path)
  if (!file.exists(fp)) return(sprintf("바닥 정본 부재(P2-03 floor v2 미확정): %s", R$floor_ref_path))
  fl <- tryCatch(.rfp_read_json(fp), error = function(err) NULL)
  if (is.null(fl)) return(sprintf("바닥 정본 파싱 실패: %s", R$floor_ref_path))
  ent <- fl$floors %||% fl
  # floor v2 가 {"floors": {"F1": {...}}}(키 = id) 형태로 실어도 읽는다 — 형태 차이로 조용히 '바닥 없음'이 되지 않게(필드 대조는 그대로)
  if (!is.null(fl$floors) && is.list(ent) && !is.null(names(ent)) && all(nzchar(names(ent))))
    ent <- lapply(names(ent), function(k) { x <- ent[[k]]; if (is.list(x) && is.null(x$id)) x$id <- k; x })
  ids <- .rfp_ids(ent)
  for (f in pr$floors) {
    fid <- as.character(f$id); k <- which(ids == fid)
    if (!length(k)) { e <- c(e, sprintf("바닥 %s 가 %s 에 없다", fid, R$floor_ref_path)); next }
    x <- ent[[k[1]]]
    miss <- setdiff(unlist(R$floor_required_fields), names(x))
    if (length(miss)) e <- c(e, sprintf("바닥 %s 필드 부재: %s", fid, paste(miss, collapse = ",")))
    # 상태 — A 경로 = floor_status_ok(confirmed)만. 기전 한정 상태(confirmed_mechanism_only)는 초안 scope 가 mechanism_only ∧
    #   a_eligible=false 일 때만 받는다(PREREG-MECHANISM-ONLY-FLOOR (가) · 2026-09-26 [위임]) — 그 밖 = fail-closed 그대로
    st <- as.character(x$status %||% "")
    st_mo <- st %in% unlist(R$floor_status_mechanism_only)
    if (!(st %in% unlist(R$floor_status_ok))) {
      if (!st_mo) e <- c(e, sprintf("바닥 %s status=%s (확정 아님)", fid, x$status %||% "?"))
      else if (!.rfp_scope_mech_only(pr, cfg))
        e <- c(e, sprintf("바닥 %s status=%s — 기전 한정 바닥은 scope.label=%s ∧ scope.a_eligible=false 사전등록만 받는다(A 경로 fail-closed · PREREG-MECHANISM-ONLY-FLOOR)",
                          fid, st, as.character(R$mechanism_only_scope$label)))
      else {
        # 바닥 문서 자체도 기전 한정이라고 말해야 한다 — 상태 문자열만 맞고 사용 제한 필드가 어긋나면 생성기·손편집 불일치
        if (!(as.character(x$permitted_use %||% "") %in% unlist(R$floor_permitted_use_mechanism_only)))
          e <- c(e, sprintf("바닥 %s permitted_use=%s — 기전 한정 상태와 불일치", fid, x$permitted_use %||% "?"))
        if (!identical(x$a_eligible, FALSE)) e <- c(e, sprintf("바닥 %s a_eligible=%s — 기전 한정 상태는 a_eligible=false 여야 한다", fid, format(x$a_eligible %||% "부재")))
        ur <- as.character(x$use_restriction$decision_id %||% "")
        if (nzchar(ur) && !identical(ur, as.character(pr$scope$decision_ref %||% "")))
          e <- c(e, sprintf("바닥 %s use_restriction.decision_id=%s ≠ 초안 scope.decision_ref=%s — 다른 제한 결정 아래 바닥", fid, ur, pr$scope$decision_ref %||% "?"))
      }
    }
    if (!isTRUE(x$determinism_ok)) e <- c(e, sprintf("바닥 %s 결정론 미확인(F1 2회 재실행 — 플랜 P2-03)", fid))
    if (!(as.character(x$selection_basis %||% "") %in% unlist(R$floor_selection_basis_ok)))
      e <- c(e, sprintf("바닥 %s selection_basis=%s — as-of 재선정 칸만(C1 · D-E)", fid, x$selection_basis %||% "?"))
    fl_flags <- as.character(unlist(lapply(x$vintage_flags %||% list(), function(z) if (is.list(z)) z$flag else z)))
    for (pat in unlist(R$floor_forbidden_flag_patterns))
      if (any(grepl(pat, fl_flags))) e <- c(e, sprintf("바닥 %s 금지 표식(%s)", fid, pat))
    rk <- cfg$verdict$regime_key
    if (!identical(as.character(x$measurement_regime[[rk]] %||% ""), as.character(pr$measurement_regime[[rk]] %||% "")))
      e <- c(e, sprintf("바닥 %s 규약(%s) ≠ 사전등록 규약", fid, rk))
  }
  e
}

#' 결정 파라미터 규칙(derive) — 설정 verdict.param_derivations 에 등재된 연산만
#'   one_minus                    : 1 − (of 의 값)  — 교정 α 의 반대 꼬리(1−α_cal)
#'   disposition_floor_over_ratio : (등록 처분 등급의 하한 ratio) / (rf_prereg_power 재계산 ratio) — 처치 전달량이 이 아래면 전달된
#'                                  효과(≈ 전달량 × 기전-함의 효과)의 ratio 가 등록 처분 등급 밖으로 떨어진다(설정 power_gate 단일 출처)
.rfp_derive_param <- function(p, vals, pr, root, cfg) {
  op <- as.character(p$derive$op %||% "")
  if (!(op %in% unlist(cfg$verdict$param_derivations))) return(NA_real_)
  if (identical(op, "one_minus")) { x <- vals[[as.character(p$derive$of %||% "")]] %||% NA_real_; return(1 - as.numeric(x)) }
  if (identical(op, "disposition_floor_over_ratio")) {
    ie <- pr$power$implied_effect$value; se <- pr$power$se$value
    if (!.rfp_num1(ie) || !.rfp_num1(se) || se <= 0) return(NA_real_)
    re <- tryCatch(rf_prereg_power(ie, se = se, root = root, cfg = cfg), error = function(e) NULL)
    if (is.null(re) || !is.finite(re$ratio) || re$ratio <= 0) return(NA_real_)
    g <- cfg$power_gate
    lo <- switch(re$disposition, conditional = g$ratio_forbidden_below, normal = g$ratio_conditional_below, design80 = g$ratio_design80_at, NA_real_)
    return(as.numeric(lo) / re$ratio)
  }
  NA_real_
}

#' 등록 단계 — 1차 판정 교정 · 결정 파라미터 재도출(PREREG-POWERED-NULL-CALIBRATION · 2026-09-26 [위임])
#'   ① 교정 필수(설정 스위치 없음 — power.calibration 없는 등록은 언제나 차단) — 명목 90% CI 로 mechanism_detected·powered_null 을 내지 않는다
#'   ② 쓰이는 파라미터(조건 rhs{param} · 교정 · derive.of) 값이 전부 유한
#'   ③ 값은 출처에서 재도출: from = 루트 안 산출물(sha256 대조 + JSON 경로 값 = 기재값) · derive = 규칙 재계산. 출처 없는 값 = 손 입력 = 차단
#'   ④ 교정 범위: α ∈ (0, 0.5) · t_lo < 0 < t_hi
.rfp_params_blockers <- function(pr, root, cfg) {
  b <- character(0); addb <- function(...) b <<- c(b, sprintf(...))
  pc <- pr$power$calibration
  kd <- if (is.list(pc)) cfg$verdict$calibration$kinds[[as.character(pc$kind %||% "")]] else NULL
  if (!is.list(pc))   # 설정 스위치 없음 — 교정 없는 등록은 언제나 차단(판정도 교정 없이는 거부)
    addb("1차 판정 교정 미선언(power.calibration) — 명목 90%% CI 로 기전 탐지·검정력 있는 무효를 내지 않는다(PREREG-POWERED-NULL-CALIBRATION)")
  vals <- .rfp_param_vals(pr)
  ps <- setNames(pr$decision_params %||% list(), .rfp_param_ids(pr))
  cr <- pr$criteria
  used <- unique(c(unlist(lapply(cr$success %||% list(), .rfp_cond_params)), unlist(lapply(cr$failure %||% list(), .rfp_cond_params)),
                   unlist(lapply(cr$stop %||% list(), function(s) .rfp_cond_params(s$when))), unlist(lapply(cr$validity %||% list(), .rfp_cond_params)),
                   if (is.list(pc)) as.character(unlist(pc$params)) else character(0)))
  repeat {   # derive.of 가 가리키는 파라미터도 쓰임
    more <- unlist(lapply(ps[intersect(used, names(ps))], function(p) if (identical(p$derive$op, "one_minus")) as.character(p$derive$of) else character(0)))
    more <- setdiff(more, used); if (!length(more)) break; used <- c(used, more)
  }
  used <- intersect(used, names(ps))
  miss <- used[!vapply(used, function(i) is.finite(vals[[i]] %||% NA_real_), logical(1))]
  if (length(miss)) addb("결정 파라미터 미산출: %s — 등록 전 산출(초안에는 규칙·절차만)", paste(miss, collapse = ","))
  for (i in setdiff(used, miss)) {
    p <- ps[[i]]; v <- as.numeric(p$value)
    if (is.list(p$from)) {
      ap <- .rfp_abs(root, as.character(p$from$artifact))
      if (!file.exists(ap) || !.rfp_under(root, ap)) { addb("결정 파라미터 %s 출처 산출물 부재/루트 밖: %s", i, p$from$artifact); next }
      if (!identical(tolower(.rfp_sha_file(ap)), tolower(as.character(p$from$artifact_sha256 %||% "")))) { addb("결정 파라미터 %s 출처 산출물 sha256 불일치(바뀐 파일)", i); next }
      aj <- tryCatch(.rfp_read_json(ap), error = function(e) NULL)
      hit <- if (is.list(aj)) .rfp_ptr(aj, p$from$field) else list(found = FALSE)
      av <- if (isTRUE(hit$found) && is.numeric(hit$value) && length(hit$value) == 1L) as.numeric(hit$value) else NA_real_
      if (!is.finite(av) || abs(av - v) > 1e-12 * max(1, abs(av)))
        addb("결정 파라미터 %s=%s ≠ 산출물 %s#%s=%s — 수치는 산출물에서만(손 입력 금지 · AX-008)", i, format(v), p$from$artifact, p$from$field, format(av))
    } else if (is.list(p$derive)) {
      dv <- .rfp_derive_param(p, vals, pr, root, cfg)
      if (!is.finite(dv) || abs(dv - v) > 1e-12 * max(1, abs(dv))) addb("결정 파라미터 %s=%s ≠ 규칙 %s 재계산 %s", i, format(v), p$derive$op, format(dv))
    } else addb("결정 파라미터 %s 출처 없음(from·derive) — 손으로 넣은 수치는 등록하지 않는다(AX-008)", i)
  }
  if (is.list(pc) && !is.null(kd)) {
    pv <- function(k) vals[[as.character(pc$params[[k]] %||% "")]] %||% NA_real_
    if (identical(pc$kind, "bootstrap_p")) { a <- pv("alpha"); if (is.finite(a) && !(a > 0 && a < 0.5)) addb("교정 α=%s 는 (0, 0.5) 밖", format(a)) }
    if (identical(pc$kind, "null_t_quantile")) { lo <- pv("t_lo"); hi <- pv("t_hi")
      if (is.finite(lo) && is.finite(hi) && !(lo < 0 && hi > 0)) addb("교정 t 문턱 t_lo=%s < 0 < t_hi=%s 가 아니다", format(lo), format(hi)) }
  }
  b
}

#' 스키마 검증 — errors(이 단계에서 거부) · registration_blockers(등록 단계 기준 — 초안에서 '무엇이 막고 있나')
rf_prereg_validate <- function(pr, stage = c("draft", "registered"), root = NULL, cfg = NULL) {
  stage <- match.arg(stage); root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  if (is.list(pr) && identical(pr$schema, RF_PREREG_ORGANIC_SCHEMA)) return(.rfp_validate_organic(pr, stage, root, cfg))   ## O0a 유기체 정책 사전등록(아래 절)
  E <- character(0); add <- function(...) E <<- c(E, sprintf(...))
  if (!is.list(pr)) return(list(ok = FALSE, errors = "사전등록이 객체가 아니다", registration_blockers = character(0)))
  if (!identical(pr$schema, RF_PREREG_SCHEMA)) add("schema ≠ %s", RF_PREREG_SCHEMA)
  if (!.rfp_chr1(pr$prereg_id) || !grepl(cfg$layout$prereg_id_pattern, pr$prereg_id)) add("prereg_id 형식 위반")
  if (!.rfp_chr1(pr$family_id) || !grepl(cfg$layout$family_id_pattern, pr$family_id)) add("family_id 형식 위반")
  if (!identical(as.character(pr$status %||% ""), stage)) add("status(%s) ≠ 단계(%s)", pr$status %||% "?", stage)
  if (stage == "draft" && !(.rfp_num1(pr$draft_rev) && pr$draft_rev >= 1 && pr$draft_rev == round(pr$draft_rev))) add("draft_rev 는 1 이상 정수")
  if (!(.rfp_num1(pr$layer) && pr$layer %in% c(1, 2))) add("layer 는 1 또는 2")
  if (!identical(pr$framing, "falsification_attempt")) add("framing 은 'falsification_attempt' 여야 한다(확증 아닌 반증 시도 · 플랜 P2 공통 규약)")
  h <- pr$hypothesis
  if (!is.list(h) || !.rfp_chr1(h$statement) || !.rfp_chr1(h$mechanism)) add("hypothesis.statement·mechanism 필수")
  # 바닥 · arm · 대조
  fids <- .rfp_ids(pr$floors); aids <- .rfp_ids(pr$arms); cids <- .rfp_ids(pr$contrasts)
  sids <- .rfp_ids(pr$se_cells); dids <- .rfp_ids(pr$deleted_arms)
  if (!length(fids)) add("floors 가 비었다")
  if (!length(aids)) add("arms 가 비었다")
  all_ids <- c(fids, aids, cids, sids)
  if (any(!nzchar(all_ids))) add("id 없는 바닥/arm/대조/SE 칸")
  if (anyDuplicated(all_ids)) add("id 중복: %s", paste(unique(all_ids[duplicated(all_ids)]), collapse = ","))
  if (length(intersect(dids, c(aids, cids)))) add("삭제 arm id 가 살아 있는 arm/대조와 겹친다(사후 부활 금지)")
  if (!isTRUE(pr$arms_frozen)) add("arms_frozen 은 TRUE 여야 한다(arm 사후 추가 금지)")
  ord <- vapply(pr$arms %||% list(), function(a) as.numeric(a$order %||% NA), numeric(1))
  if (length(ord) && (anyNA(ord) || anyDuplicated(ord))) add("arm order 는 유일한 정수여야 한다(멈춤 집행 순서)")
  for (a in pr$arms %||% list()) {
    w <- sprintf("arm %s", a$id %||% "?")
    if (!(as.character(a$role %||% "") %in% RF_PREREG_ROLES)) add("%s: role 은 %s", w, paste(RF_PREREG_ROLES, collapse = "/"))
    if (!(as.character(a$on_floor %||% "") %in% fids)) add("%s: on_floor 미선언 바닥", w)
    if (!is.list(a$spec) || !length(a$spec)) add("%s: spec 비었다(스펙 고정)", w)
    sb <- as.character(a$selection_basis %||% "")
    if (!(sb %in% RF_PREREG_SELBASIS)) add("%s: selection_basis='%s' — as_of|none 만(전기간 통계 선정 = C1 · D-E)", w, sb)
    if (identical(a$role, "spare") && !.rfp_chr1(a$activation)) add("%s: 예비 arm 은 activation 조건을 선언해야 한다", w)
  }
  for (d in pr$deleted_arms %||% list()) {
    if (!.rfp_chr1(d$reason)) add("삭제 arm %s: reason 필수", d$id %||% "?")
    if (!identical(d$counted_in_n, FALSE)) add("삭제 arm %s: counted_in_n 은 FALSE(측정 0 칸은 N 에 넣지 않는다)", d$id %||% "?")
  }
  for (c in pr$contrasts %||% list())
    if (!all(c(as.character(c$a %||% ""), as.character(c$b %||% "")) %in% c(aids, fids)))
      add("대조 %s: a/b 가 선언된 arm/바닥이 아니다", c$id %||% "?")
  for (s in pr$se_cells %||% list())
    if (!(as.character(s$on_floor %||% "") %in% fids)) add("SE 칸 %s: on_floor 미선언", s$id %||% "?")
  targets <- c(fids, aids, cids, sids)
  # 지표
  mids <- .rfp_ids(pr$metrics); contracts <- names(cfg$verdict$contracts)
  if (anyDuplicated(mids)) add("지표 id 중복")
  tiers <- vapply(pr$metrics %||% list(), function(m) as.character(m$tier %||% ""), character(1))
  if (!any(tiers == "primary")) add("1차(primary) 지표가 없다")
  for (m in pr$metrics %||% list()) {
    w <- sprintf("지표 %s", m$id %||% "?")
    if (!(as.character(m$tier %||% "") %in% RF_PREREG_TIERS)) add("%s: tier", w)
    if (!(as.character(m$contract %||% "") %in% contracts)) add("%s: 계약 '%s' 미등재(판정 입력은 R 계약만)", w, m$contract %||% "")
    if (!(as.character(m$direction %||% "") %in% RF_PREREG_DIRS)) add("%s: direction", w)
    if (identical(m$tier, "primary") && !(m$direction %in% c("decrease", "increase"))) add("%s: 1차 지표는 방향(decrease/increase)이 있어야 한다", w)
    tg <- as.character(unlist(m$targets))
    if (!length(tg) || !all(tg %in% targets)) add("%s: targets 가 비었거나 미선언", w)
  }
  # 결정 파라미터(구조) — 값은 초안에서 비어도 된다(등록 전 산출) · 출처는 from(산출물) 또는 derive(규칙) 중 하나
  pids <- .rfp_param_ids(pr)
  if (anyDuplicated(pids) || any(!nzchar(pids))) add("decision_params id 중복/공백")
  for (p in pr$decision_params %||% list()) {
    w <- sprintf("결정 파라미터 %s", p$id %||% "?")
    if (!is.null(p$value) && !.rfp_num1(p$value)) add("%s: value 는 수치 1개 또는 null(등록 전 산출)", w)
    if (!is.null(p$from) && !is.null(p$derive)) add("%s: from(산출물)·derive(규칙) 중 하나만", w)
    if (!is.null(p$from) && (!is.list(p$from) || !.rfp_chr1(p$from$artifact) || !.rfp_chr1(p$from$field)))
      add("%s: from 은 {artifact, artifact_sha256, field}", w)
    if (!is.null(p$derive)) {
      if (!is.list(p$derive) || !(as.character(p$derive$op %||% "") %in% unlist(cfg$verdict$param_derivations)))
        add("%s: derive.op 은 %s 중 하나", w, paste(unlist(cfg$verdict$param_derivations), collapse = "/"))
      else if (identical(p$derive$op, "one_minus") && !(as.character(p$derive$of %||% "") %in% setdiff(pids, p$id)))
        add("%s: derive one_minus 의 of 는 다른 선언 파라미터", w)
    }
  }
  # 기준
  decl <- list(metrics = mids, targets = targets, stats = unlist(cfg$verdict$stats), ops = unlist(cfg$verdict$ops), params = pids)
  cr <- pr$criteria
  if (!is.list(cr) || !length(cr$success)) add("criteria.success 가 비었다")
  if (!is.list(cr) || !length(cr$failure)) add("criteria.failure 가 비었다(반증 조건 없는 사전등록은 무엇이든 성공으로 읽힌다)")
  for (i in seq_along(cr$success)) E <- c(E, .rfp_cond_errors(cr$success[[i]], decl, sprintf("success[%d]", i)))
  for (i in seq_along(cr$failure)) E <- c(E, .rfp_cond_errors(cr$failure[[i]], decl, sprintf("failure[%d]", i)))
  # 처치 전달 타당성(validity) — 조건이 FALSE 면 라벨 대신 outcome(판정 불가) · outcome 어휘 = 설정 verdict.validity_outcomes
  vids <- .rfp_ids(cr$validity)
  if (anyDuplicated(vids) || any(!nzchar(vids))) add("criteria.validity id 중복/공백")
  for (x in cr$validity %||% list()) {
    E <- c(E, .rfp_cond_errors(x, decl, sprintf("validity %s", x$id %||% "?")))
    if (!(as.character(x$outcome %||% "") %in% names(cfg$verdict$validity_outcomes)))
      add("validity %s: outcome '%s' 은 설정 verdict.validity_outcomes(%s) 밖", x$id %||% "?", x$outcome %||% "", paste(names(cfg$verdict$validity_outcomes), collapse = "/"))
  }
  # 범위(scope) — 있으면 label·a_eligible(논리값) 형식
  if (!is.null(pr$scope) && (!is.list(pr$scope) || !.rfp_chr1(pr$scope$label) || !is.logical(pr$scope$a_eligible) || length(pr$scope$a_eligible) != 1L || is.na(pr$scope$a_eligible)))
    add("scope 는 {label, a_eligible(true|false), decision_ref}")
  # 1차 판정 교정(구조) — 종류·파라미터 이름. 값·출처는 등록 단계(PREREG-POWERED-NULL-CALIBRATION)
  pc <- pr$power$calibration
  if (!is.null(pc)) {
    kd <- cfg$verdict$calibration$kinds[[as.character(pc$kind %||% "")]]
    if (is.null(kd)) add("power.calibration.kind '%s' 은 %s 중 하나", pc$kind %||% "", paste(names(cfg$verdict$calibration$kinds), collapse = "/"))
    else {
      need_p <- unlist(kd$params)
      if (!setequal(names(pc$params %||% list()), need_p)) add("power.calibration.params 는 {%s} → decision_params id", paste(need_p, collapse = ", "))
      else for (k in need_p) if (!(as.character(pc$params[[k]] %||% "") %in% pids))
        add("power.calibration.params.%s='%s' 는 선언된 decision_params 가 아니다", k, pc$params[[k]] %||% "")
    }
  }
  for (s in cr$stop %||% list()) {
    w <- sprintf("stop %s", s$id %||% "?")
    if (!length(s$after_arms) || !all(unlist(s$after_arms) %in% aids)) add("%s: after_arms 는 선언된 arm", w)
    E <- c(E, .rfp_cond_errors(s$when, decl, paste0(w, ".when")))
    act <- s$action
    if (!is.list(act) || !(isTRUE(act$halt) || length(act$skip_arms))) add("%s: action 은 halt 또는 skip_arms", w)
    if (length(act$skip_arms) && !all(unlist(act$skip_arms) %in% aids)) add("%s: skip_arms 미선언 arm", w)
    if (length(intersect(unlist(act$skip_arms), unlist(s$after_arms)))) add("%s: 이미 측정한 arm 을 건너뛸 수 없다", w)
    # 멈춤 조건은 체크포인트에서 판정 가능해야 한다 — 뒤 arm 을 참조하면 '뒤 arm 을 안 재면 멈춤이 불발'하는 우회가 된다
    aa <- as.character(unlist(s$after_arms))
    for (t in .rfp_cond_targets(s$when)) {
      ar <- .rfp_target_arms(pr, t)
      if (!(t %in% c(fids, sids)) && (t %in% c(aids, cids)) && !all(ar %in% aa))
        add("%s: when 이 체크포인트 뒤 arm 을 참조한다(%s) — 멈춤 조건 대상은 after_arms·바닥·SE 칸만", w, t)
    }
  }
  # 라벨 · SE · 예산 · 사전확률 · PIT · 규약
  if (!identical(unlist(pr$labels), unlist(cfg$labels))) add("labels 는 설정의 4종과 같아야 한다(%s)", paste(unlist(cfg$labels), collapse = "/"))
  fse <- .rfp_scan_forbidden_se(pr, cfg)
  if (length(fse)) add("금지 SE 원천: %s — %s", paste(fse, collapse = ","), paste(unlist(cfg$se_sources$forbidden[fse]), collapse = " | "))
  sm <- as.character(unlist(pr$se_source$methods))
  if (!length(sm) || !all(sm %in% unlist(cfg$se_sources$allowed))) add("se_source.methods ⊆ {%s} 이어야 한다", paste(unlist(cfg$se_sources$allowed), collapse = ","))
  b <- pr$budget
  if (!is.list(b) || !.rfp_num1(b$max_cells) || b$max_cells < 1) add("budget.max_cells 필수")
  else if (length(aids) > b$max_cells) add("arm 수 %d > budget.max_cells %d", length(aids), as.integer(b$max_cells))
  pz <- pr$priors
  if (!is.list(pz) || !.rfp_prob(pz$mechanism) || !.rfp_prob(pz$success) || !.rfp_prob(pz$grade_a) || !.rfp_chr1(pz$basis))
    add("priors(mechanism·success·grade_a ∈ [0,1] 또는 {lo,hi} + basis) 필수")
  if (!is.list(pr$pit) || !isTRUE(pr$pit$as_of_selection) || !length(pr$pit$statements)) add("pit.as_of_selection=TRUE + statements 필수(C1~C15)")
  rk <- cfg$verdict$regime_key
  if (!is.list(pr$measurement_regime) || !.rfp_chr1(pr$measurement_regime[[rk]])) add("measurement_regime.%s 필수", rk)
  # 검정력 블록(구조)
  pw <- pr$power
  if (!is.list(pw) || !is.list(pw$primary)) add("power.primary 필수")
  else {
    pm <- Filter(function(m) identical(m$id, pw$primary$metric), pr$metrics %||% list())
    if (!length(pm) || !identical(pm[[1]]$tier, "primary")) add("power.primary.metric 은 1차 지표여야 한다")
    if (!(as.character(pw$primary$target %||% "") %in% targets)) add("power.primary.target 미선언")
    if (!.rfp_num1(pw$ci_level) || abs(pw$ci_level - cfg$bootstrap$ci_level) > 1e-12) add("power.ci_level ≠ 설정 bootstrap.ci_level")
    if (!is.list(pw$implied_effect) || !(.rfp_chr1(pw$implied_effect$formula) || .rfp_chr1(pw$implied_effect$source)))
      add("power.implied_effect 에 formula 또는 source 필수(기전-함의 효과의 출처)")
  }
  lk <- pr$hypothesis_index_lookup
  if (!is.list(lk) || !(as.character(lk$status %||% "") %in% c("attached", "pending"))) add("hypothesis_index_lookup(status attached|pending) 필수")
  if (!is.null(pr$revision_of)) {
    idx <- rf_prereg_index(root, cfg); prev <- .rfp_idx_find(idx, as.character(pr$revision_of), "registered")
    if (!length(prev)) add("revision_of=%s 는 등록본이 아니다", pr$revision_of)
    else if (identical(prev[[1]]$family_id, pr$family_id)) add("등록본 개정은 새 가족이어야 한다(family_id 재사용 금지)")
  }
  errors <- E
  # 등록 단계 전용(엄격) — 초안에서는 blockers 로만 보고
  B <- character(0); addb <- function(...) B <<- c(B, sprintf(...))
  B <- c(B, .rfp_floor_check(pr, root, cfg))
  if (is.list(pw) && is.list(pw$primary)) {
    ie <- pw$implied_effect$value; se <- pw$se$value
    if (!.rfp_num1(ie)) addb("기전-함의 효과 미산출(power.implied_effect.value)")
    else {
      pdir <- Filter(function(m) identical(m$id, pw$primary$metric), pr$metrics %||% list())
      pdir <- if (length(pdir)) as.character(pdir[[1]]$direction %||% "") else ""
      # 검정력은 |효과| 라 부호가 틀려도 통과한다 — 그러면 powered_null(함의 효과 배제) 판정이 반대편을 본다
      if ((identical(pdir, "decrease") && !(ie < 0)) || (identical(pdir, "increase") && !(ie > 0)))
        addb("기전-함의 효과 부호(%g)가 1차 지표 방향(%s)과 맞지 않다 — powered_null 판정이 반대편 꼬리를 본다", ie, pdir)
    }
    if (!.rfp_num1(se) || se <= 0) addb("SE 미산출(power.se.value)")
    if (!length(pw$se$source) || !all(unlist(pw$se$source) %in% unlist(cfg$se_sources$allowed))) addb("power.se.source 가 허용 원천이 아니다")
    if (.rfp_num1(ie) && .rfp_num1(se) && se > 0) {
      re <- tryCatch(rf_prereg_power(ie, se = se, root = root, cfg = cfg), error = function(err) NULL)
      cp <- pw$computed
      if (is.null(re)) addb("검정력 재계산 실패")
      else if (!is.list(cp) || !all(vapply(c("ratio", "expected_t", "power"), function(k)
        .rfp_num1(cp[[k]]) && abs(cp[[k]] - re[[k]]) < 1e-9, logical(1))) || !identical(cp$disposition, re$disposition))
        addb("power.computed 가 rf_prereg_power 재계산과 다르다(손편집 금지 · 계약 산출만)")
      else {
        if (identical(re$disposition, "forbidden")) addb("착수 금지: ratio %.4f < %.2f (기대 t %.3f · 검정력 %.1f%%)", re$ratio, cfg$power_gate$ratio_forbidden_below, re$expected_t, 100 * re$power)
        if (identical(re$disposition, "conditional") && (!identical(pw$modal_outcome, "undetermined") || !length(pw$leaves_behind)))
          addb("조건부 착수(0.15≤ratio<0.70)는 modal_outcome='undetermined' + leaves_behind 명시 필수")
      }
    }
  }
  # 1차 판정 교정 · 결정 파라미터(등록 단계) — 명목 CI 판정 금지(PREREG-POWERED-NULL-CALIBRATION) · 수치는 산출물·규칙에서 재도출
  B <- c(B, .rfp_params_blockers(pr, root, cfg))
  if (!is.list(lk) || !identical(lk$status, "attached") || !length(lk$queries)) addb("hypothesis_index lookup 미첨부")
  else if (length(lk$index_stale_sources))
    addb("hypothesis_index 가 stale 상태에서 조회됨(%s) — 재빌드 인덱스로 재조회 뒤 등록(최근 negative 누락 방지)",
         paste(unlist(lk$index_stale_sources), collapse = ","))
  sa <- pr$selection_accounting
  if (!is.list(sa) || !identical(sa$selection_type, "sweep") || !.rfp_num1(sa$n_family) || sa$n_family < 2 || !.rfp_chr1(sa$n_source))
    addb("selection_accounting(sweep · n_family ≥ 2 · n_source) 미산출 — N 에 바닥 계보 선택 이력 포함")
  if (length(pr$open_questions)) addb("미결 질문 %d건: %s", length(pr$open_questions), paste(.rfp_ids(pr$open_questions), collapse = ","))
  for (d in pr$dependencies %||% list()) {
    if (!identical(d$status, "available")) addb("의존 %s 미충족(%s)", d$id %||% "?", d$status %||% "?")
    else if (.rfp_chr1(d$file) && !file.exists(file.path(root, d$file))) addb("의존 %s 파일 부재: %s", d$id %||% "?", d$file)
  }
  for (a in pr$arms %||% list()) if (is.list(a$conditional_on) && !isTRUE(a$conditional_on$resolved))
    addb("조건부 arm %s 미해소(%s) — 발동 또는 deleted_arms 로 이동", a$id %||% "?", a$conditional_on$require %||% "?")
  del_t <- .rfp_ids(pr$deleted_arms)
  used_t <- unique(c(unlist(lapply(cr$success %||% list(), .rfp_cond_targets)), unlist(lapply(cr$failure %||% list(), .rfp_cond_targets)),
                     unlist(lapply(cr$stop %||% list(), function(s) .rfp_cond_targets(s$when))), unlist(lapply(cr$validity %||% list(), .rfp_cond_targets))))
  if (length(intersect(used_t, del_t))) addb("기준이 삭제 arm 을 참조: %s", paste(intersect(used_t, del_t), collapse = ","))
  if (!.rfp_chr1(pr$measurement_regime$pin_tag %||% NA_character_)) addb("measurement_regime.pin_tag 미기재(floor v2 pin 스냅샷)")
  if (stage == "registered") errors <- c(errors, B)
  list(ok = !length(errors), errors = errors, registration_blockers = B, stage = stage)
}

# ── writer · 로드 · 등록 ──────────────────────────────────────────────────────────────
#' 쓰기 — 초안(drafts/<id>.draft<rev>.json) 또는 등록본(<id>.json). 덮어쓰기 거부 · 원자 쓰기 · 색인에 sha256
rf_prereg_write <- function(pr, kind = c("draft", "registered"), root = NULL, cfg = NULL) {
  kind <- match.arg(kind); root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  .rfp_organic_ctx_guard(pr)   ## O0a — 유기체 문맥은 유기체 정책 사전등록만 쓴다(레버 실험 사전등록은 세션 소관)
  v <- rf_prereg_validate(pr, kind, root, cfg)
  if (!v$ok) stop(sprintf("[rf_prereg] 검증 실패(%s) — 쓰지 않는다:\n  - %s", kind, paste(v$errors, collapse = "\n  - ")))
  id <- pr$prereg_id
  rel <- if (kind == "draft") file.path(cfg$layout$draft_dir, sprintf("%s.draft%d.json", id, as.integer(pr$draft_rev)))
         else file.path(cfg$layout$registered_dir, sprintf("%s.json", id))
  path <- file.path(root, rel)
  if (!.rfp_under(file.path(root, "06_Registry/prereg"), path)) stop("[rf_prereg] 쓰기 경로가 06_Registry/prereg 밖이다")
  lk <- .rfp_lock(file.path(root, cfg$layout$registered_dir), id); on.exit(unlink(lk, recursive = TRUE), add = TRUE)
  idx <- rf_prereg_index(root, cfg)
  if (kind == "registered") {
    if (length(.rfp_idx_find(idx, id, "registered"))) stop(sprintf("[rf_prereg] 이미 등록된 id(색인 묘비 포함): %s — 개정은 새 prereg_id·새 가족", id))
    fam <- Filter(function(r) identical(r$kind, "registered") && identical(r$family_id, pr$family_id), idx)
    if (length(fam)) stop(sprintf("[rf_prereg] 가족 %s 는 이미 등록본(%s)이 있다 — 개정 = 새 가족", pr$family_id, fam[[1]]$prereg_id))
  } else {
    if (length(.rfp_idx_find(idx, id, "registered"))) stop(sprintf("[rf_prereg] %s 는 이미 등록됐다 — 초안을 더 쓸 수 없다", id))
    revs <- vapply(.rfp_idx_find(idx, id, "draft"), function(r) as.integer(r$rev), integer(1))
    want <- if (length(revs)) max(revs) + 1L else 1L
    if (!identical(as.integer(pr$draft_rev), want)) stop(sprintf("[rf_prereg] draft_rev=%d — 다음 rev 는 %d(초안 개정 = 새 rev 파일 · 덮어쓰기 없음)", as.integer(pr$draft_rev), want))
  }
  # 정규형: R 원자 벡터와 JSON 배열(list)의 pretty 표기가 달라 1회 왕복으로 정규화한 뒤, 정규형이 고정점인지 재확인
  txt <- tryCatch(.rfp_json(fromJSON(.rfp_json(pr), simplifyVector = FALSE)), error = function(e) NULL)
  chk <- if (is.null(txt)) NULL else tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || !identical(.rfp_json(chk), txt)) stop("[rf_prereg] 직렬화 정규형이 고정점이 아니다 — 쓰지 않는다")
  .rfp_write_new(path, txt)
  sha <- .rfp_sha_file(path)
  rec <- list(schema = "rf_prereg_index_v1", prereg_id = id, family_id = pr$family_id, kind = kind,
              rev = if (kind == "draft") as.integer(pr$draft_rev) else NULL, path = rel, sha256 = sha,
              bytes = file.info(path)$size, written_at = .rfp_now(), revision_of = pr$revision_of %||% NULL,
              registered_from = if (kind == "registered") pr$registered_from %||% NULL else NULL,
              config_sha256 = attr(cfg, "sha256"))
  .rfp_append_line(file.path(root, cfg$layout$index), as.character(toJSON(rec, auto_unbox = TRUE, null = "null")))
  cat(sprintf("[rf_prereg] %s 기록: %s (sha256 %s)\n", kind, rel, substr(sha, 1, 12)))
  invisible(list(path = path, rel = rel, sha256 = sha, kind = kind))
}

#' 로드 — 색인의 sha256 과 파일 바이트를 대조한다(다르면 거부 = 변조 · 손편집)
rf_prereg_load <- function(prereg_id, kind = c("registered", "draft"), rev = NULL, root = NULL, cfg = NULL) {
  kind <- match.arg(kind); root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  hits <- .rfp_idx_find(rf_prereg_index(root, cfg), prereg_id, kind, rev)
  if (!length(hits)) stop(sprintf("[rf_prereg] 색인에 없다: %s (%s%s) — 색인 밖 파일은 읽지 않는다(선례 파일 포함)", prereg_id, kind, if (is.null(rev)) "" else paste0(" rev ", rev)))
  if (kind == "draft" && is.null(rev)) hits <- hits[order(vapply(hits, function(r) as.integer(r$rev), integer(1)))]
  r <- hits[[length(hits)]]
  p <- file.path(root, r$path)
  if (!file.exists(p)) stop(sprintf("[rf_prereg] 색인된 파일이 사라졌다: %s", r$path))
  sha <- .rfp_sha_file(p)
  if (!identical(sha, r$sha256)) stop(sprintf("[rf_prereg] 무결성 불일치(변조): %s 색인 %s ≠ 파일 %s", r$path, substr(r$sha256, 1, 12), substr(sha, 1, 12)))
  pr <- .rfp_read_json(p)
  attr(pr, "integrity") <- list(path = r$path, sha256 = sha, kind = kind, rev = r$rev %||% NULL, verified_at = .rfp_now())
  pr
}

#' 등록 — 최신(또는 지정) 초안에서 등록본을 새로 쓴다(초안은 남는다). 엄격 검증 통과 전에는 거부
rf_prereg_register <- function(prereg_id, rev = NULL, registered_by = "Q(세션)", root = NULL, cfg = NULL) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  d <- rf_prereg_load(prereg_id, "draft", rev, root, cfg)
  integ <- attr(d, "integrity")
  pr <- d; attributes(pr) <- attributes(d)[intersect(names(attributes(d)), "names")]
  pr$status <- "registered"; pr$draft_rev <- NULL
  pr$registered_at <- .rfp_now(); pr$registered_by <- registered_by
  pr$registered_from <- list(path = integ$path, sha256 = integ$sha256, rev = integ$rev)
  rf_prereg_write(pr, "registered", root, cfg)
}

# ── 검정력 3종 (MDE 는 required_effect_size.R 단일 출처) ───────────────────────────────
.rfp_env_cache <- new.env(parent = emptyenv())
.rfp_src <- function(root, rel, key) {
  k <- paste(root, key)
  if (!is.null(.rfp_env_cache[[k]])) return(.rfp_env_cache[[k]])
  p <- file.path(root, rel)
  if (!file.exists(p)) stop(sprintf("[rf_prereg] 정본 파일 부재: %s", rel))
  env <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(p, envir = env, keep.source = FALSE))))
  assign(k, env, envir = .rfp_env_cache)
  env
}

#' 착수 관문 검정력 3종 — ratio = |기전-함의 효과| / MDE80 · 기대 t = ratio × t80 · 검정력 = Φ(기대 t − z)
#' @param implied_effect 기전-함의 효과(사전 선언 · 관측 효과 금지 — Hoenig & Heisey 2001)
#' @param se  직접 SE(블록 부트스트랩·null 희석) — 주면 required_effect(n=1, sd=se, nw=1) ≡ t80·se
#' @param sd,n,nw_inflation SE 를 (sd, n) 로 줄 때 — required_effect 의 표준 경로
rf_prereg_power <- function(implied_effect, se = NULL, sd = NULL, n = NULL, nw_inflation = 1, root = NULL, cfg = NULL) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  if (!.rfp_num1(implied_effect)) stop("[rf_prereg] implied_effect 비수치")
  g <- cfg$power_gate
  z <- stats::qnorm(1 - g$alpha_two_sided / 2); t80 <- stats::qnorm(g$power_target) + z
  env <- .rfp_src(root, "02_Infrastructure/contracts/required_effect_size.R", "res")
  if (!is.null(se)) {
    if (!.rfp_num1(se) || se <= 0) stop("[rf_prereg] se 는 양수")
    req <- env$required_effect(n = 1, t_threshold = t80, sd_monthly = se, design = "full", nw_inflation = 1); path <- "se_direct"
  } else {
    if (!.rfp_num1(sd) || !.rfp_num1(n) || sd <= 0 || n < 2) stop("[rf_prereg] (sd, n) 또는 se 필요")
    req <- env$required_effect(n = n, t_threshold = t80, sd_monthly = sd, design = "full", nw_inflation = nw_inflation); path <- "sd_n"
  }
  mde <- req$required_monthly
  ratio <- abs(implied_effect) / mde; et <- ratio * t80; pw <- stats::pnorm(et - z)
  disp <- if (ratio < g$ratio_forbidden_below) "forbidden" else if (ratio < g$ratio_conditional_below) "conditional"
          else if (ratio < g$ratio_design80_at) "normal" else "design80"
  list(contract = "rf_prereg_power", implied_effect = implied_effect, mde80 = mde, t80 = t80, z_crit = z,
       ratio = ratio, expected_t = et, power = pw, disposition = disp, mde_path = path,
       mde_source = "required_effect_size.R::required_effect", nw_inflation_source = req$nw_inflation_source,
       config_sha256 = attr(cfg, "sha256"))
}

# ── SE 원천: 짝지은 원형 블록 부트스트랩 · null 희석 ───────────────────────────────────
.rfp_cb_idx <- function(n, b) {
  nb <- ceiling(n / b); st <- sample.int(n, nb, replace = TRUE)
  idx <- unlist(lapply(st, function(s) ((s - 1L + 0:(b - 1L)) %% n) + 1L), use.names = FALSE)
  idx[seq_len(n)]
}

#' 짝지은 원형 블록 부트스트랩 — Δ = stat(a) − stat(b), 두 계열에 **같은 인덱스**(Ledoit & Wolf 2008)
#' @param stat "mean" | "calmar"(일간 경로 · adv_calmar_from_ret) | "deep_capture"(월간 · 벤치 < 심층 문턱 월의 평균비 —
#'   defensive_score.R 과 같은 식 · 문턱 = ds_params()$deep_threshold 단일 출처)
#' @param dates deep_capture 에서 주면 a·b·bench 를 달력월 복리(prod(1+r)−1)로 먼저 합산한다 — defensive_score.R::ds_score 의
#'   월 테이블과 같은 식(일간 산출물을 그대로 넣어도 같은 값). 없으면 입력을 이미 달력월 수익으로 본다.
#' @param cal_alpha 교정 단측 수준(등록본 power.calibration 의 α — PREREG-POWERED-NULL-CALIBRATION). 주면 같은 재표본에서
#'   cal_q_lo = α 분위 · cal_q_hi = 1−α 분위를 함께 싣는다(판정이 이 값과 등록본 α 를 대조 — 수준 쇼핑 차단). 없으면 싣지 않는다.
rf_prereg_paired_boot <- function(a, b, stat = c("mean", "calmar", "deep_capture"), bench = NULL, deep_threshold = NULL,
                                  root = NULL, cfg = NULL, B = NULL, seed = NULL, dates = NULL, cal_alpha = NULL) {
  stat <- match.arg(stat); root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  if (!is.null(cal_alpha) && !(.rfp_num1(cal_alpha) && cal_alpha > 0 && cal_alpha < 0.5)) stop("[rf_prereg] cal_alpha 는 (0, 0.5) 수치")
  if (stat == "deep_capture" && !is.null(dates)) {
    if (length(dates) != length(a) || length(a) != length(b) || length(bench) != length(a)) stop("[rf_prereg] dates·a·b·bench 길이 불일치")
    ym <- format(as.Date(dates), "%Y-%m"); g <- factor(ym, levels = sort(unique(ym)))
    agg <- function(x) as.numeric(tapply(as.numeric(x), g, function(v) prod(1 + v) - 1))
    a <- agg(a); b <- agg(b); bench <- agg(bench)
  }
  a <- as.numeric(a); b <- as.numeric(b); n <- length(a)
  if (n != length(b) || n < 8L) stop("[rf_prereg] a·b 는 같은 길이(≥8)의 짝지은 계열이어야 한다")
  if (anyNA(a) || anyNA(b)) stop("[rf_prereg] 결측 수익 — 짝지음 전에 정렬·정리할 것(0 채움 금지)")
  bc <- cfg$bootstrap; B <- as.integer(B %||% bc$B); seed <- as.integer(seed %||% bc$seed)
  adv <- .rfp_src(root, "02_Infrastructure/reinforcement/rf_overlay_adversary.R", "adv")
  if (stat == "deep_capture") {
    if (is.null(bench) || length(bench) != n || anyNA(bench)) stop("[rf_prereg] deep_capture 는 같은 길이의 bench 필요")
    if (is.null(deep_threshold)) {
      ds <- .rfp_src(root, "02_Infrastructure/contracts/defensive_score.R", "ds")
      deep_threshold <- ds$ds_params(root)$deep_threshold
    }
  }
  ann <- bc$ann_periods_daily
  f <- switch(stat,
    mean   = function(x, k) mean(x),
    calmar = function(x, k) adv$adv_calmar_from_ret(x, ann)$calmar,
    deep_capture = function(x, k) { s <- k < deep_threshold; if (sum(s) < 1L || mean(k[s]) == 0) NA_real_ else mean(x[s]) / mean(k[s]) })
  bl <- adv$adv_block_len(a - b, bc$block_rule)
  obs <- f(a, bench) - f(b, bench)
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (!is.null(old)) assign(".Random.seed", old, envir = globalenv()), add = TRUE)
  set.seed(seed)
  d <- vapply(seq_len(B), function(i) { ix <- .rfp_cb_idx(n, bl$b); f(a[ix], bench[ix]) - f(b[ix], bench[ix]) }, numeric(1))
  ok <- is.finite(d); vf <- mean(ok)
  lev <- bc$ci_level
  base <- list(contract = "rf_prereg_paired_boot", stat = stat, n = n, B = B, seed = seed, block_len = bl$b, block_rule = bl$rule,
               ci_level = lev, valid_frac = vf, deep_threshold = if (stat == "deep_capture") deep_threshold else NULL,
               config_sha256 = attr(cfg, "sha256"))
  calx <- if (is.null(cal_alpha)) list() else list(cal_alpha = as.numeric(cal_alpha), cal_q_lo = NA_real_, cal_q_hi = NA_real_)
  if (!is.finite(obs) || vf < bc$min_valid_frac)
    return(c(base, list(value = NA_real_, se = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_, p_gt0 = NA_real_,
                        invalid_reason = sprintf("관측 Δ 비유한 또는 유효 재표본 비율 %.3f < %.2f", vf, bc$min_valid_frac)), calx))
  q <- stats::quantile(d[ok], c((1 - lev) / 2, 1 - (1 - lev) / 2), names = FALSE, type = 7)
  if (length(calx)) { qc <- stats::quantile(d[ok], c(cal_alpha, 1 - cal_alpha), names = FALSE, type = 7); calx$cal_q_lo <- qc[1]; calx$cal_q_hi <- qc[2] }
  # boot_bias = 재표본 평균 − 관측 — 경로 의존 통계(calmar 의 MDD)는 블록이 낙폭 지속보다 짧으면 재표본 분포가 관측에서
  #   벗어난다(백분위 CI·p_gt0 오중심). 진단 기록만 한다(판정 식 불변).
  c(base, list(value = obs, se = stats::sd(d[ok]), ci_lo = q[1], ci_hi = q[2], p_gt0 = mean(d[ok] > 0),
               boot_mean = mean(d[ok]), boot_bias = mean(d[ok]) - obs), calx)
}

#' null 희석 SE — P1-06 null-factor 희석 상주 칸(월내 순열 · seed 고정)들의 지표 Δ 표본 표준편차
rf_prereg_se_null <- function(values, root = NULL) {
  .rfp_root(root)
  v <- as.numeric(values)
  if (anyNA(v) || length(v) < 2L) stop("[rf_prereg] null 희석 SE 는 유한한 칸 값 2개 이상 필요")
  list(contract = "null_dilution", n = length(v), df = length(v) - 1L, mean = mean(v), se = stats::sd(v))
}

#' 두 SE 원천 결합 — 설정 combine(현행 max · 보수). 위상쌍 등 금지 원천은 이름으로 거부
rf_prereg_combine_se <- function(se_null = NULL, se_boot = NULL, sources = NULL, root = NULL, cfg = NULL) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  if (length(intersect(as.character(sources), names(cfg$se_sources$forbidden))))
    stop(sprintf("[rf_prereg] 금지 SE 원천: %s", paste(intersect(sources, names(cfg$se_sources$forbidden)), collapse = ",")))
  x <- c(null_dilution = if (.rfp_num1(se_null)) se_null else NA, block_bootstrap = if (.rfp_num1(se_boot)) se_boot else NA)
  x <- x[is.finite(x)]
  if (!length(x)) stop("[rf_prereg] 유효 SE 원천이 없다")
  if (!identical(cfg$se_sources$combine, "max")) stop(sprintf("[rf_prereg] 미지원 combine: %s", cfg$se_sources$combine))
  list(se = max(x), source = names(x), used = names(x)[which.max(x)], combine = "max")
}

#' 측정 산출물 기록 — stage_artifacts/prereg/<prereg_id>/<name>.json (덮어쓰기 거부) → 판정 입력의 source 블록
rf_prereg_artifact <- function(obj, prereg_id, name, measurement_regime, root = NULL) {
  root <- .rfp_root(root)
  if (!grepl("^[A-Za-z0-9_.-]+$", name)) stop("[rf_prereg] 산출물 이름은 [A-Za-z0-9_.-]")
  rel <- file.path("stage_artifacts/prereg", prereg_id, paste0(name, ".json"))
  if (!is.list(measurement_regime) || !length(measurement_regime)) stop("[rf_prereg] measurement_regime 필수(산출물에 실현 규약을 싣는다)")
  obj$measurement_regime <- measurement_regime
  .rfp_write_new(file.path(root, rel), .rfp_json(obj))
  list(contract = as.character(obj$contract %||% ""), artifact = rel, artifact_sha256 = .rfp_sha_file(file.path(root, rel)),
       measurement_regime = measurement_regime)
}

# ── N 회계 (바닥 계보 선택 이력 포함 — rf_runner_gates.R 정의 재사용) ──────────────────
.rfp_defs_from <- function(path, names_wanted) {
  ex <- parse(file = path, encoding = "UTF-8", keep.source = FALSE); env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env)) assign("%||%", function(a, b) if (is.null(a) || length(a) == 0L) b else a, envir = env)
  for (e in as.list(ex)) if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
                              as.character(e[[2]]) %in% names_wanted) eval(e, envir = env)
  miss <- setdiff(names_wanted, ls(env, all.names = TRUE))
  if (length(miss)) stop(sprintf("[rf_prereg] %s 에 정의 부재: %s", basename(path), paste(miss, collapse = ",")))
  env
}
#' @param floor_base_id 바닥 칸이 속한 원장 entry base_id · n_arms 가족 arm 수(삭제 arm 제외)
rf_prereg_lineage_n <- function(floor_base_id, n_arms, layer = 1L, root = NULL) {
  root <- .rfp_root(root)
  g <- .rfp_defs_from(file.path(root, "02_Infrastructure/reinforcement/rf_runner_gates.R"),
                      c("rf_lineage_ids", "rf_lineage_measured", "rf_selection_accounting"))
  lp <- file.path(root, sprintf("06_Registry/reinforce_ledger_l%d.json", as.integer(layer)))
  L <- .rfp_read_json(lp)
  ids <- g$rf_lineage_ids(L$entries, floor_base_id)
  nm <- g$rf_lineage_measured(L$entries, ids)
  sa <- g$rf_selection_accounting(ids, nm, as.integer(n_arms))
  c(sa, list(n_lineage_measured = nm, ledger_sha256 = .rfp_sha_file(lp), computed_at = .rfp_now(),
             n_source = "rf_runner_gates.R::rf_selection_accounting(rf_lineage_ids, rf_lineage_measured, n_arms)"))
}

# ── hypothesis_index lookup 첨부 (재빌드 없음 · 읽기 전용) ─────────────────────────────
rf_prereg_lookup <- function(keyword_sets, root = NULL, max_rows = 10L) {
  root <- .rfp_root(root)
  hi <- .rfp_src(root, "02_Infrastructure/tools/hypothesis_index.R", "hi")
  ip <- file.path(root, "06_Registry/hypothesis_index.json")
  stale <- tryCatch(hi$.hi_stale_check(ip, root = root, warn = FALSE), error = function(e) paste("stale 검사 실패:", conditionMessage(e)))
  qs <- lapply(keyword_sets, function(kw) {
    msgs <- character(0)
    df <- withCallingHandlers(
      hi$lookup_hypothesis(kw, index_path = ip, max_rows = max_rows, auto_rebuild = FALSE, root = root),
      message = function(m) { msgs <<- c(msgs, trimws(conditionMessage(m))); invokeRestart("muffleMessage") })
    rows <- if (is.data.frame(df) && nrow(df)) lapply(seq_len(nrow(df)), function(i) list(
      strategy_id = df$strategy_id[i], verdict = df$verdict[i], grade = df$grade[i], title = df$title[i],
      date = df$date[i], research_mode = df$research_mode[i] %||% "")) else list()
    list(keywords = as.list(kw), n_hits = length(rows), fallback_single_word = any(grepl("단일어 폴백", msgs)), hits = rows)
  })
  list(status = "attached", tool = "02_Infrastructure/tools/hypothesis_index.R::lookup_hypothesis(auto_rebuild=FALSE)",
       run_at = .rfp_now(), index_sha256 = .rfp_sha_file(ip), index_mtime = format(file.info(ip)$mtime, "%Y-%m-%dT%H:%M:%S%z"),
       index_stale_sources = as.list(as.character(stale %||% character(0))),
       note = "과거 negative 는 사실 기록이지 금지 목록이 아니다(AX-000) — 새 각도면 재시도 정당", queries = qs)
}

# ── 조건 평가 ─────────────────────────────────────────────────────────────────────────
.rfp_get <- function(M, metric, target, stat) {
  m <- M[[paste(metric, target, sep = "|")]]
  if (is.null(m)) return(NA_real_)
  v <- m[[stat]]
  if (.rfp_num1(v)) v else NA_real_
}
#' 조건 평가 — TRUE / FALSE / NA(측정 부재·비유한). all: FALSE 우선 · any: TRUE 우선(Kleene 3값)
#' @param K 결정 파라미터 값(id → 수치 · .rfp_param_vals) — rhs {param} 를 푼다. 없거나 비유한이면 NA(판정 불능)
rf_prereg_eval <- function(c, M, K = NULL) {
  if (!is.null(c$all)) { v <- vapply(c$all, rf_prereg_eval, logical(1), M = M, K = K)
    return(if (any(v %in% FALSE)) FALSE else if (anyNA(v)) NA else TRUE) }
  if (!is.null(c$any)) { v <- vapply(c$any, rf_prereg_eval, logical(1), M = M, K = K)
    return(if (any(v %in% TRUE)) TRUE else if (anyNA(v)) NA else FALSE) }
  if (!is.null(c$not)) return(!rf_prereg_eval(c$not, M, K))
  lhs <- .rfp_get(M, c$metric, c$target, c$stat)
  r <- c$rhs
  rhs <- if (is.list(r) && !is.null(r$param)) {
    x <- (K %||% list())[[as.character(r$param)]]
    if (.rfp_num1(x)) as.numeric(x) else NA_real_
  } else if (is.list(r)) {
    x <- .rfp_get(M, r$ref$metric, r$ref$target, r$ref$stat) + as.numeric(r$offset %||% 0)
    if (!is.null(r$noise)) x <- x - as.numeric(r$noise$k) * .rfp_get(M, r$noise$metric, r$noise$target, r$noise$stat)
    x
  } else as.numeric(r)
  if (!is.finite(lhs) || !is.finite(rhs)) return(NA)
  switch(c$op, "<" = lhs < rhs, "<=" = lhs <= rhs, ">" = lhs > rhs, ">=" = lhs >= rhs, "==" = isTRUE(all.equal(lhs, rhs)), NA)
}

# ── 판정 ─────────────────────────────────────────────────────────────────────────────
.rfp_has_key <- function(x, keys) {
  if (!is.list(x)) return(FALSE)
  if (any(names(x) %in% keys)) return(TRUE)
  any(vapply(x, .rfp_has_key, logical(1), keys = keys))
}
.rfp_ptr <- function(x, path) {
  for (k in Filter(nzchar, strsplit(as.character(path), "/", fixed = TRUE)[[1]])) {
    if (!is.list(x) || !(k %in% names(x))) return(list(found = FALSE))
    x <- x[[k]]
  }
  list(found = TRUE, value = x)
}
.rfp_num_or_na <- function(v, w) {
  if (is.null(v) || (is.logical(v) && length(v) == 1L && is.na(v))) return(NA_real_)
  if (is.numeric(v) && length(v) == 1L) return(as.numeric(v))
  stop(sprintf("[rf_prereg] %s: 산출물 값이 수치 스칼라가 아니다", w))
}
.rfp_parse_time <- function(s) if (.rfp_chr1(s)) as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC") else as.POSIXct(NA)
#' 측정 1건 검사 → 산출물에서 재도출한 수치로 채운 측정을 돌려준다(측정 객체의 수치는 주장일 뿐 · AX-008)
.rfp_check_measurement <- function(m, pr, root, cfg, verify_artifacts, reg_time = NULL, cal = NULL) {
  w <- sprintf("측정 %s|%s", m$metric %||% "?", m$target %||% "?")
  mids <- .rfp_ids(pr$metrics)
  tg <- c(.rfp_ids(pr$floors), .rfp_ids(pr$arms), .rfp_ids(pr$contrasts), .rfp_ids(pr$se_cells))
  if (!(as.character(m$metric %||% "") %in% mids)) stop(sprintf("[rf_prereg] %s: 미선언 지표(사후 추가 금지)", w))
  if (!(as.character(m$target %||% "") %in% tg)) stop(sprintf("[rf_prereg] %s: 미선언 대상(arm 사후 추가 금지)", w))
  s <- m$source
  if (!is.list(s)) stop(sprintf("[rf_prereg] %s: source 없음 — R 계약 산출물만 받는다", w))
  ct <- tolower(as.character(s$contract %||% ""))
  if (!nzchar(ct) || ct %in% tolower(unlist(cfg$verdict$forbidden_contract_labels)))
    stop(sprintf("[rf_prereg] %s: 계약 '%s' 거부 — 손계산·python·LLM 산출은 판정 입력이 아니다(AX-008)", w, s$contract %||% ""))
  cdef <- cfg$verdict$contracts[[as.character(s$contract)]]
  if (is.null(cdef)) stop(sprintf("[rf_prereg] %s: 미등재 계약 '%s'", w, s$contract))
  if (!file.exists(file.path(root, cdef$file))) stop(sprintf("[rf_prereg] %s: 계약 파일 부재(%s) — 없는 계약의 산출물은 받지 않는다", w, cdef$file))
  metric_contract <- Filter(function(x) identical(x$id, m$metric), pr$metrics)[[1]]$contract
  if (!identical(as.character(metric_contract), as.character(s$contract)))
    stop(sprintf("[rf_prereg] %s: 선언 계약 %s ≠ 산출 계약 %s", w, metric_contract, s$contract))
  if (isTRUE(verify_artifacts)) {
    if (!.rfp_chr1(s$artifact) || !.rfp_chr1(s$artifact_sha256)) stop(sprintf("[rf_prereg] %s: artifact·artifact_sha256 필수", w))
    ap <- .rfp_abs(root, s$artifact)
    if (!file.exists(ap)) stop(sprintf("[rf_prereg] %s: 산출물 부재 %s", w, s$artifact))
    if (!.rfp_under(root, ap)) stop(sprintf("[rf_prereg] %s: 산출물이 루트 밖 — 운영 트리의 계약 산출물만", w))
    if (!identical(tolower(.rfp_sha_file(ap)), tolower(s$artifact_sha256))) stop(sprintf("[rf_prereg] %s: 산출물 sha256 불일치(바뀐 파일)", w))
    # 규약은 주장(source 블록)이 아니라 산출물 안의 실현값으로도 재도출한다 — authoritative_remeasure.json·rf_prereg_artifact 는
    #   최상위 measurement_regime 을 싣는다. 싣는 계약(artifact_regime_required)인데 없으면 거부(fail-closed).
    rk0 <- cfg$verdict$regime_key
    aj <- if (grepl("\\.json$", ap, ignore.case = TRUE)) tryCatch(.rfp_read_json(ap), error = function(e) NULL) else NULL
    ar <- if (is.list(aj) && is.list(aj$measurement_regime)) as.character(aj$measurement_regime[[rk0]] %||% "") else ""
    if (nzchar(ar) && !identical(ar, as.character(pr$measurement_regime[[rk0]])))
      stop(sprintf("[rf_prereg] %s: 산출물 안 규약 %s=%s ≠ 사전등록 %s(주장이 아니라 실현값으로 대조)", w, rk0, ar, pr$measurement_regime[[rk0]]))
    if (!nzchar(ar) && isTRUE(cdef$artifact_regime_required))
      stop(sprintf("[rf_prereg] %s: 계약 %s 산출물에 measurement_regime.%s 가 없다(실현 규약 재도출 불가)", w, s$contract, rk0))
    # 시간 순서 — arm 이 걸린 측정(arm·arm 포함 대조)의 산출물은 등록 뒤에 쓰였어야 한다(결과 전 잠금의 본체).
    #   바닥·SE 칸은 등록 전 측정이 정당하다(바닥 결정론 · 검정력 SE 가 등록 차단 해소 조건).
    if (!is.null(reg_time) && length(.rfp_target_arms(pr, as.character(m$target)))) {
      mt <- file.info(ap)$mtime
      if (is.na(mt) || mt < reg_time)
        stop(sprintf("[rf_prereg] %s: arm 산출물이 등록(%s)보다 먼저 쓰였다(%s) — 결과를 본 뒤 등록한 측정은 받지 않는다", w, pr$registered_at, format(mt, "%Y-%m-%dT%H:%M:%S%z")))
    }
    # 재표본 설정 고정 — 계약이 pinned 를 선언하면 산출물의 그 필드가 설정값과 같아야 한다(seed·B 쇼핑 차단)
    if (is.list(aj) && is.list(cdef$pinned)) for (k in names(cdef$pinned)) {
      want <- cfg; for (kk in strsplit(as.character(cdef$pinned[[k]]), ".", fixed = TRUE)[[1]]) want <- if (is.list(want)) want[[kk]] else NULL
      got <- aj[[k]]
      if (is.null(got) || is.null(want) || !isTRUE(all.equal(as.numeric(got), as.numeric(want))))
        stop(sprintf("[rf_prereg] %s: 산출물 %s=%s ≠ 설정 %s=%s — 재표본 설정은 설정값으로 고정(쇼핑 금지)", w, k, format(got %||% "부재"), cdef$pinned[[k]], format(want %||% "부재")))
    }
    if (is.list(aj) && isTRUE(cdef$pin_config_sha) && !identical(as.character(aj$config_sha256 %||% ""), as.character(attr(cfg, "sha256"))))
      stop(sprintf("[rf_prereg] %s: 산출물 config_sha256 ≠ 현재 설정 — 다른 설정으로 낸 산출물", w))
    # 교정 수준 고정(PREREG-POWERED-NULL-CALIBRATION) — 1차 (지표|대상) 산출물의 교정 키(bootstrap_p: cal_alpha)가 등록본 값과 같아야 한다.
    #   등록 뒤 다른 α 로 분위를 다시 내 powered_null·기전 탐지를 고르는 경로 차단(seed 쇼핑과 같은 꼴)
    if (is.list(cal) && identical(as.character(m$metric), as.character(cal$metric)) && identical(as.character(m$target), as.character(cal$target)) &&
        .rfp_chr1(cal$artifact_key %||% NA_character_)) {
      got <- if (is.list(aj)) aj[[cal$artifact_key]] else NULL
      if (!(is.numeric(got) && length(got) == 1L && is.finite(got) && isTRUE(abs(as.numeric(got) - as.numeric(cal$value)) <= 1e-12)))
        stop(sprintf("[rf_prereg] %s: 산출물 %s=%s ≠ 등록 교정값 %s — 교정 수준은 등록본 값으로 고정(수준 고르기 차단 · PREREG-POWERED-NULL-CALIBRATION)",
                     w, cal$artifact_key, format(got %||% "부재"), format(cal$value)))
    }
    if (is.list(aj) && identical(as.character(s$contract), "rf_prereg_paired_boot") && identical(aj$stat, "deep_capture")) {
      ds <- .rfp_src(root, "02_Infrastructure/contracts/defensive_score.R", "ds")
      if (!isTRUE(all.equal(as.numeric(aj$deep_threshold %||% NA), as.numeric(ds$ds_params(root)$deep_threshold))))
        stop(sprintf("[rf_prereg] %s: deep_threshold 가 ds_params() 와 다르다(문턱 쇼핑 금지)", w))
    }
    # ★수치는 산출물에서 재도출한다 — 측정 객체의 수치는 주장이다. 다르면 거부 · 없으면 채운다(AX-008 · 손 수치·전사 오류 차단).
    #   source$fields = {stat: "json/경로"} 로 중첩 산출물(authoritative_remeasure.json::essence/calmar 등)을 가리킨다. 없으면 최상위 같은 이름 키.
    if (!is.list(aj)) stop(sprintf("[rf_prereg] %s: 산출물이 JSON 객체가 아니다 — 수치를 재도출할 수 없다", w))
    dst <- c(unlist(cfg$verdict$stats), "ci_level"); fl <- s$fields
    if (!is.null(fl) && (!is.list(fl) || is.null(names(fl)) || !all(names(fl) %in% dst)))
      stop(sprintf("[rf_prereg] %s: source.fields 는 {%s 중 stat: 'json/경로'}", w, paste(dst, collapse = "|")))
    der <- list()
    for (st in dst) {
      path <- if (is.null(fl)) st else fl[[st]]
      if (is.null(path)) next
      hit <- .rfp_ptr(aj, path)
      if (isTRUE(hit$found)) der[[st]] <- .rfp_num_or_na(hit$value, sprintf("%s.%s", w, st))
    }
    if (!length(der)) stop(sprintf("[rf_prereg] %s: 산출물에서 재도출된 수치가 없다", w))
    for (st in dst) if (!is.null(m[[st]])) {
      sv <- suppressWarnings(as.numeric(m[[st]])[1])
      if (is.null(der[[st]])) stop(sprintf("[rf_prereg] %s: %s 는 산출물에 없다 — 손으로 넣은 수치는 판정 입력이 아니다(AX-008)", w, st))
      dv <- der[[st]]
      same <- (is.na(sv) && is.na(dv)) || (!is.na(sv) && !is.na(dv) && abs(sv - dv) <= 1e-9 * max(1, abs(dv)))
      if (!same) stop(sprintf("[rf_prereg] %s: %s=%s ≠ 산출물 %s — 수치는 산출물에서만(AX-008)", w, st, format(sv), format(dv)))
    }
    if (is.null(fl)) for (k in c("metric", "target"))
      if (!is.null(aj[[k]]) && !identical(as.character(aj[[k]]), as.character(m[[k]] %||% "")))
        stop(sprintf("[rf_prereg] %s: 산출물의 %s=%s ≠ 측정 %s(다른 대상의 산출물)", w, k, aj[[k]], m[[k]] %||% "?"))
    for (st in names(der)) m[[st]] <- der[[st]]
  }
  rk <- cfg$verdict$regime_key
  if (!identical(as.character(s$measurement_regime[[rk]] %||% ""), as.character(pr$measurement_regime[[rk]])))
    stop(sprintf("[rf_prereg] %s: 규약 %s=%s ≠ 사전등록 %s(규약이 다른 칸끼리 비교하지 않는다)", w, rk, s$measurement_regime[[rk]] %||% "?", pr$measurement_regime[[rk]]))
  for (k in c("value", "ci_lo", "ci_hi", "p_gt0", "t", "se"))
    if (!is.null(m[[k]]) && !(is.numeric(m[[k]]) && length(m[[k]]) == 1L)) stop(sprintf("[rf_prereg] %s: %s 비수치", w, k))
  m
}

#' 판정 — 등록본 + R 계약 산출물 → 라벨 4종 중 하나 + 멈춤 집행 + rf_record_decision(kind='prereg_verdict')
#' @param pr rf_prereg_load 로 읽은 등록본(무결성 attr 필수)
#' @param measurements list(list(metric, target, value, ci_lo, ci_hi, ci_level, p_gt0, t, se, n,
#'        source = list(contract, artifact, artifact_sha256, measurement_regime = list(exec_price=))), ...)
#' @return status ∈ concluded | halted | incomplete(기록 없음) · label
rf_prereg_verdict <- function(pr, measurements, root = NULL, cfg = NULL, record = TRUE, verify_artifacts = TRUE) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  integ <- attr(pr, "integrity")
  if (!identical(pr$status, "registered") || is.null(integ) || !identical(integ$kind, "registered"))
    stop("[rf_prereg] 판정은 rf_prereg_load 로 읽은 등록본에만 — 초안·손으로 만든 객체 거부")
  cur <- .rfp_idx_find(rf_prereg_index(root, cfg), pr$prereg_id, "registered")
  if (!length(cur) || !identical(cur[[1]]$sha256, integ$sha256) || !identical(.rfp_sha_file(file.path(root, cur[[1]]$path)), integ$sha256))
    stop("[rf_prereg] 등록본 무결성 재확인 실패")
  # 판정 규칙(라벨 우선순위·부트스트랩·계약 목록·문턱)은 등록 시점 설정으로만 — 등록 뒤 설정을 바꾸면 결과를 보고 규칙을 고른 것이다
  if (isTRUE(cfg$verdict$pin_to_registration_config) && !identical(as.character(cur[[1]]$config_sha256 %||% ""), as.character(attr(cfg, "sha256"))))
    stop(sprintf("[rf_prereg] 설정이 등록 뒤 바뀌었다(등록 %s ≠ 현재 %s) — 재보정은 새 사전등록(새 가족)으로만",
                 substr(as.character(cur[[1]]$config_sha256 %||% "?"), 1, 12), substr(attr(cfg, "sha256"), 1, 12)))
  if (!isTRUE(verify_artifacts) && (isTRUE(record) || isTRUE(cfg$verdict$require_artifact_sha)))
    stop("[rf_prereg] verify_artifacts=FALSE 거부 — 산출물(파일+sha256)에서 재도출하지 않은 수치로는 판정하지 않는다(설정 require_artifact_sha · AX-008)")
  reg_time <- NULL
  if (isTRUE(cfg$verdict$arm_artifacts_after_registration)) {
    reg_time <- .rfp_parse_time(pr$registered_at)
    if (is.na(reg_time)) stop("[rf_prereg] 등록본 registered_at 파싱 불가 — 등록-측정 시간 순서를 잴 수 없다(fail-closed)")
  }
  led <- .rfp_src(root, "02_Infrastructure/reinforcement/reinforce_ledger.R", "led")
  if (!("prereg_verdict" %in% led$RF_DECISION_KINDS)) stop("[rf_prereg] RF_DECISION_KINDS 에 prereg_verdict 부재 — 기록 경로 없음")
  prior <- Filter(function(r) identical(r$scope$prereg_id, pr$prereg_id), led$rf_read_decisions(root = root, kind = "prereg_verdict"))
  if (length(prior)) stop(sprintf("[rf_prereg] %s 는 이미 판정됐다(%s) — 재판정 = 새 사전등록(새 가족)", pr$prereg_id, prior[[1]]$decision_id %||% "?"))
  if (!is.list(measurements)) stop("[rf_prereg] measurements 는 list")
  # 1차 판정 교정 · 결정 파라미터(등록본) — 명목 CI 로 판정하지 않는다(PREREG-POWERED-NULL-CALIBRATION · 교정 없음 = 판정 거부 · 대체 경로 없음)
  K <- .rfp_param_vals(pr)
  pc <- pr$power$calibration
  kd <- if (is.list(pc)) cfg$verdict$calibration$kinds[[as.character(pc$kind %||% "")]] else NULL
  if (is.null(kd)) stop("[rf_prereg] 등록본에 1차 판정 교정(power.calibration)이 없다 — 명목 90% CI 로 판정하지 않는다(등록 검증 우회 · PREREG-POWERED-NULL-CALIBRATION)")
  cpar <- setNames(lapply(unlist(kd$params), function(k) K[[as.character(pc$params[[k]] %||% "")]] %||% NA_real_), unlist(kd$params))
  up <- unique(c(unlist(lapply(pr$criteria$success %||% list(), .rfp_cond_params)), unlist(lapply(pr$criteria$failure %||% list(), .rfp_cond_params)),
                 unlist(lapply(pr$criteria$stop %||% list(), function(s) .rfp_cond_params(s$when))), unlist(lapply(pr$criteria$validity %||% list(), .rfp_cond_params))))
  nf <- c(names(cpar)[!vapply(cpar, .rfp_num1, logical(1))], up[!vapply(up, function(i) .rfp_num1(K[[i]]), logical(1))])
  if (length(nf)) stop(sprintf("[rf_prereg] 교정·결정 파라미터 미산출(%s) — 등록 검증 우회(fail-closed)", paste(unique(nf), collapse = ",")))
  calpin <- if (.rfp_chr1(kd$artifact_key %||% NA_character_) && identical(pc$kind, "bootstrap_p"))
    list(metric = pr$power$primary$metric, target = pr$power$primary$target, artifact_key = kd$artifact_key, value = cpar$alpha) else NULL
  measurements <- lapply(measurements, .rfp_check_measurement, pr = pr, root = root, cfg = cfg, verify_artifacts = verify_artifacts, reg_time = reg_time, cal = calpin)
  keys <- vapply(measurements, function(m) paste(m$metric, m$target, sep = "|"), character(1))
  if (anyDuplicated(keys)) stop(sprintf("[rf_prereg] 같은 (지표|대상) 측정이 둘 이상: %s — 어느 쪽을 쓸지 고르는 것 자체가 사후 선택", paste(unique(keys[duplicated(keys)]), collapse = ",")))
  # 같은 산출물·같은 필드를 서로 다른 대상의 측정으로 쓰면 대상 귀속 위조다(바닥 산출물을 arm 측정으로 제출 등)
  if (isTRUE(verify_artifacts)) {
    sig <- vapply(measurements, function(m) paste(tolower(normalizePath(.rfp_abs(root, m$source$artifact), winslash = "/", mustWork = FALSE)),
                                                   as.character(toJSON(m$source$fields %||% list(), auto_unbox = TRUE))), character(1))
    tg <- vapply(measurements, function(m) as.character(m$target), character(1))
    multi <- names(which(tapply(tg, sig, function(z) length(unique(z))) > 1L))
    if (length(multi)) stop(sprintf("[rf_prereg] 같은 산출물(같은 필드)이 서로 다른 대상의 측정으로 쓰였다: %s", paste(unique(tg[sig %in% multi]), collapse = ",")))
  }
  M <- setNames(measurements, keys)
  # 측정된 arm (대조는 양쪽 arm 을 측정한 것으로 센다)
  arm_ids <- .rfp_ids(pr$arms)
  measured <- unique(unlist(lapply(measurements, function(m) .rfp_target_arms(pr, as.character(m$target)))))
  if (length(measured) > pr$budget$max_cells) stop(sprintf("[rf_prereg] 예산 초과: 측정 arm %d > max_cells %d", length(measured), as.integer(pr$budget$max_cells)))
  # 멈춤 — arm order 순으로 체크포인트 도달(after_arms 전부 측정) 시 평가 · 발동하면 skip/halt 기계 집행
  skipped <- character(0); halted <- FALSE; stops <- list()
  arm_ord <- setNames(vapply(pr$arms, function(a) as.numeric(a$order), numeric(1)), arm_ids)
  for (s in pr$criteria$stop %||% list()) {
    aa <- as.character(unlist(s$after_arms)); cp <- max(arm_ord[aa])
    reached <- all(aa %in% measured)
    beyond <- measured[arm_ord[measured] > cp]
    ev <- if (reached) rf_prereg_eval(s$when, M, K) else NA
    # 체크포인트를 판정 가능한 상태로 통과하지 않고 뒤 arm 을 쟀으면 거부 — 멈춤 조건 지표를 빼거나 NA 로 내면 멈춤이 불발하는 우회
    if (length(beyond) && !reached)
      stop(sprintf("[rf_prereg] 멈춤 %s: 체크포인트 arm(%s) 미측정인데 뒤 arm(%s)을 쟀다 — arm order 순서 위반", s$id, paste(setdiff(aa, measured), collapse = ","), paste(beyond, collapse = ",")))
    if (length(beyond) && is.na(ev))
      stop(sprintf("[rf_prereg] 멈춤 %s: 조건이 판정 불능(측정 부재·NA)인데 뒤 arm(%s)을 쟀다 — 멈춤을 건너뛸 수 없다", s$id, paste(beyond, collapse = ",")))
    fire <- reached && isTRUE(ev)
    if (fire) {
      skipped <- union(skipped, as.character(unlist(s$action$skip_arms)))
      if (isTRUE(s$action$halt)) {
        mx <- max(vapply(Filter(function(a) a$id %in% unlist(s$after_arms), pr$arms), function(a) as.numeric(a$order), numeric(1)))
        skipped <- union(skipped, vapply(Filter(function(a) as.numeric(a$order) > mx, pr$arms), function(a) as.character(a$id), character(1)))
        halted <- TRUE
      }
    }
    stops[[length(stops) + 1L]] <- list(id = s$id, reached = reached, fired = fire)
  }
  viol <- intersect(measured, skipped)
  if (length(viol)) stop(sprintf("[rf_prereg] 멈춤 위반 — 건너뛰어야 할 arm 이 측정됐다: %s", paste(viol, collapse = ",")))
  # 요구 측정: 성공·실패 조건 + 1차 지표 + must_report — 건너뛴 arm 이 걸린 대상은 제외
  live_target <- function(t) !length(intersect(.rfp_target_arms(pr, t), skipped))
  cr <- pr$criteria
  # 핵심 요구(멈춤과 무관하게 항상) = 1차 지표 + must_report + 멈춤 조건 지표 · 전체 요구 = 핵심 + 성공·실패 조건.
  #   halt 는 뒤 arm 을 건너뛸 뿐 핵심 요구를 면제하지 않는다(구판: halt 면 must_report 누락도 라벨이 났다).
  core <- unique(c(paste(pr$power$primary$metric, pr$power$primary$target, sep = "|"),
                   unlist(lapply(Filter(function(m) isTRUE(m$must_report), pr$metrics), function(m) paste(m$id, unlist(m$targets), sep = "|"))),
                   unlist(lapply(cr$stop %||% list(), function(s) .rfp_cond_pairs(s$when))),
                   unlist(lapply(cr$validity %||% list(), .rfp_cond_pairs))))   # 처치 전달 타당성도 halt 와 무관하게 항상 요구
  req <- if (halted) core else unique(c(core, unlist(lapply(cr$success, .rfp_cond_pairs)), unlist(lapply(cr$failure, .rfp_cond_pairs))))
  req <- req[vapply(req, function(k) live_target(sub("^[^|]*\\|", "", k)), logical(1))]
  missing <- setdiff(req, keys)
  if (length(missing))
    return(list(schema = "rf_prereg_verdict_v1", prereg_id = pr$prereg_id, status = "incomplete", label = NULL,
                missing = as.list(missing), arms_measured = as.list(measured), arms_skipped = as.list(skipped), stops = stops,
                recorded = FALSE, note = "요구 측정 부재 — 라벨을 내지 않는다(기록 없음)"))
  mm <- lapply(measurements, function(m) list(metric = m$metric, target = m$target, value = m$value %||% NULL,
                                              ci_lo = m$ci_lo %||% NULL, ci_hi = m$ci_hi %||% NULL, p_gt0 = m$p_gt0 %||% NULL,
                                              t = m$t %||% NULL, cal_q_lo = m$cal_q_lo %||% NULL, cal_q_hi = m$cal_q_hi %||% NULL,
                                              contract = m$source$contract, artifact = m$source$artifact %||% NULL,
                                              artifact_sha256 = m$source$artifact_sha256 %||% NULL))
  if (.rfp_has_key(mm, unlist(cfg$verdict$forbidden_record_keys))) stop("[rf_prereg] 판정 기록에 등급 객체 키 — AX-008")
  scope_out <- if (is.list(pr$scope)) list(label = pr$scope$label %||% NULL, a_eligible = pr$scope$a_eligible %||% NULL,
                                           decision_ref = pr$scope$decision_ref %||% NULL) else NULL
  prec <- unlist(cfg$label_precedence)
  rule_rec <- list(src = "02_Infrastructure/reinforcement/rf_prereg.R::rf_prereg_verdict", sha = integ$sha256,
                   knobs = list(config_sha256 = attr(cfg, "sha256"), label_precedence = as.list(prec), calibration_kind = pc$kind, calibration = cpar))
  # 처치 전달 타당성(criteria.validity) — 살아 있는 대상의 조건이 FALSE·NA 면 라벨 대신 outcome(판정 불가 · 예: treatment_dilution).
  #   처치가 전달되지 않은 칸의 '기전 없음'·'실패'는 기전에 대한 증거가 아니다(검정력 있는 무효가 거짓으로 서면 유망 레버를 닫는다).
  #   기록 1회(record=TRUE) — 재측정으로 전달량을 고르는 경로 차단(재판정 = 새 사전등록)
  vchk <- Filter(function(x) all(vapply(.rfp_cond_targets(x), live_target, logical(1))), cr$validity %||% list())
  vres <- lapply(vchk, function(x) list(id = x$id, outcome = x$outcome, ok = rf_prereg_eval(x, M, K)))
  vbad <- Filter(function(z) !isTRUE(z$ok), vres)
  if (length(vbad)) {
    oc <- unique(vapply(vbad, function(z) as.character(z$outcome), character(1)))
    out <- list(schema = "rf_prereg_verdict_v1", prereg_id = pr$prereg_id, family_id = pr$family_id, prereg_sha256 = integ$sha256,
                status = "invalid", label = NULL,
                invalid = list(outcome = as.list(oc), failed = as.list(vapply(vbad, function(z) as.character(z$id), character(1))),
                               semantics = lapply(setNames(oc, oc), function(o) cfg$verdict$validity_outcomes[[o]])),
                validity = vres, stops = stops, arms_measured = as.list(measured), arms_skipped = as.list(skipped), scope = scope_out,
                framing = "falsification_attempt", not_a_grade = TRUE, at = .rfp_now(), recorded = FALSE)
    if (isTRUE(record)) {
      cands <- lapply(seq_along(prec), function(i) list(id = prec[i], rank = i, reason = unlist(cfg$label_semantics[[prec[i]]] %||% prec[i]),
                                                        features = list(condition_true = FALSE)))
      rec <- led$rf_record_decision(kind = "prereg_verdict", base_id = pr$prereg_id, candidates = cands, chosen = "none", rule = rule_rec,
               scope = list(prereg_id = pr$prereg_id, family_id = pr$family_id, status = "invalid", invalid_outcome = as.list(oc),
                            validity = vres, arms_measured = as.list(measured), arms_skipped = as.list(skipped), stops = stops,
                            measurements = mm, prereg_scope = scope_out, not_a_grade = TRUE),
               root = root, layer = as.integer(pr$layer))
      out$recorded <- TRUE; out$decision_id <- rec$decision_id
    }
    return(out)
  }
  succ <- vapply(cr$success, rf_prereg_eval, logical(1), M = M, K = K)
  fail <- vapply(cr$failure, rf_prereg_eval, logical(1), M = M, K = K)
  pm <- M[[paste(pr$power$primary$metric, pr$power$primary$target, sep = "|")]]
  dirn <- Filter(function(m) identical(m$id, pr$power$primary$metric), pr$metrics)[[1]]$direction
  ie <- pr$power$implied_effect$value
  lo <- if (is.null(pm)) NA_real_ else as.numeric(pm$ci_lo %||% NA); hi <- if (is.null(pm)) NA_real_ else as.numeric(pm$ci_hi %||% NA)
  if (!is.null(pm) && !isTRUE(abs(as.numeric(pm$ci_level %||% NA) - pr$power$ci_level) < 1e-12))
    stop("[rf_prereg] 1차 지표 측정의 ci_level 이 사전등록과 다르다")
  # 기전 탐지 · 검정력 있는 무효 — 교정 문턱으로만(명목 CI 는 병기). powered_null = 교정 수준에서 0 을 배제하지 못함 ∧ 함의 효과를 배제
  #   (Lakens 2017 동등성 논리를 교정 수준으로 · 반대 방향 유의는 '부재'가 아니다)
  gs <- function(k) { x <- if (is.null(pm)) NULL else pm[[k]]; if (.rfp_num1(x)) as.numeric(x) else NA_real_ }
  miss_st <- setdiff(unlist(kd$stats), names(Filter(is.finite, vapply(setNames(unlist(kd$stats), unlist(kd$stats)), gs, numeric(1)))))
  if (length(miss_st)) stop(sprintf("[rf_prereg] 1차 측정에 교정 통계(%s) 부재·비유한 — 교정 판정 불가(산출물을 교정 인자로 다시 낼 것 · 등록본 값 고정)", paste(miss_st, collapse = ",")))
  if (identical(pc$kind, "bootstrap_p")) {
    a <- cpar$alpha; p0 <- gs("p_gt0"); qlo <- gs("cal_q_lo"); qhi <- gs("cal_q_hi")
    zero_in <- p0 >= a && p0 <= 1 - a
    mech <- if (dirn == "decrease") p0 < a else p0 > 1 - a
    excl_ie <- if (dirn == "decrease") qlo > ie else qhi < ie
  } else if (identical(pc$kind, "null_t_quantile")) {
    tl <- cpar$t_lo; th <- cpar$t_hi; tt <- gs("t"); te <- (gs("value") - ie) / gs("se")
    if (!is.finite(te)) stop("[rf_prereg] 1차 측정 se ≤ 0 또는 비유한 — 함의 효과 배제 t 를 낼 수 없다")
    zero_in <- tt > tl && tt < th
    mech <- if (dirn == "decrease") tt <= tl else tt >= th
    excl_ie <- if (dirn == "decrease") te >= th else te <= tl
  } else stop(sprintf("[rf_prereg] 판정 코드가 모르는 교정 종류: %s", pc$kind))
  pn <- isTRUE(zero_in) && isTRUE(excl_ie)
  flags <- list(failed = any(fail %in% TRUE), confirmed = length(succ) > 0 && all(succ %in% TRUE),
                powered_null = isTRUE(pn), undetermined = TRUE)
  label <- NULL
  for (l in unlist(cfg$label_precedence)) if (isTRUE(flags[[l]])) { label <- l; break }
  status <- if (halted) "halted" else "concluded"
  out <- list(schema = "rf_prereg_verdict_v1", prereg_id = pr$prereg_id, family_id = pr$family_id, prereg_sha256 = integ$sha256,
              status = status, label = label,
              success = as.list(succ), failure = as.list(fail),
              primary = list(metric = pr$power$primary$metric, target = pr$power$primary$target, direction = dirn,
                             ci_lo = lo, ci_hi = hi, ci_note = "명목 CI(병기용) — 판정은 calibration",
                             calibration = c(list(kind = pc$kind), cpar), implied_effect = ie,
                             mechanism_detected = isTRUE(mech), zero_included_calibrated = isTRUE(zero_in), implied_excluded_calibrated = isTRUE(excl_ie),
                             powered_null = isTRUE(pn)),
              validity = vres, stops = stops, arms_measured = as.list(measured), arms_skipped = as.list(skipped), missing = as.list(missing),
              scope = scope_out, framing = "falsification_attempt", not_a_grade = TRUE, at = .rfp_now(), recorded = FALSE)
  if (isTRUE(record)) {
    ranks <- c(label, setdiff(prec, label))
    cands <- lapply(seq_along(ranks), function(i) list(id = ranks[i], rank = i,
                    reason = unlist(cfg$label_semantics[[ranks[i]]] %||% ranks[i]),
                    features = list(condition_true = isTRUE(flags[[ranks[i]]]))))
    rec <- led$rf_record_decision(kind = "prereg_verdict", base_id = pr$prereg_id, candidates = cands, chosen = label,
             rule = rule_rec,
             scope = list(prereg_id = pr$prereg_id, family_id = pr$family_id, status = status,
                          arms_measured = as.list(measured), arms_skipped = as.list(skipped), stops = stops,
                          primary = out$primary, validity = vres, measurements = mm, prereg_scope = scope_out, not_a_grade = TRUE),
             root = root, layer = as.integer(pr$layer))
    out$recorded <- TRUE; out$decision_id <- rec$decision_id
  }
  out
}

# ── 드라이런 러너 ─────────────────────────────────────────────────────────────────────
#' 드라이런 전용 — 착수 계획(arm 순서 · 멈춤 체크포인트 · rf_open_entry 가 받을 인자)과 등록 차단 사유를 낸다. 쓰기 0.
#'   dry_run=FALSE 는 거부한다: 원장 entry 개설은 P1-08(priority/experiment) 배포 + 별판 검토 뒤(러너 본체 불변).
rf_prereg_run <- function(prereg_id, kind = c("registered", "draft"), rev = NULL, root = NULL, cfg = NULL, dry_run = TRUE) {
  kind <- match.arg(kind)
  if (!isTRUE(dry_run)) stop("[rf_prereg] rf_prereg_run 은 드라이런 전용 — 원장 entry 개설은 P1-08(priority/experiment 필드) 배포 뒤 별판에서만(러너 본체 불변)")
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  lp <- file.path(root, "06_Registry/reinforce_ledger_l1.json")
  md5_0 <- if (file.exists(lp)) unname(tools::md5sum(lp)) else NA_character_
  pr <- rf_prereg_load(prereg_id, kind, rev, root, cfg)
  v <- rf_prereg_validate(pr, "registered", root, cfg)
  ex <- parse(file = file.path(root, "02_Infrastructure/reinforcement/reinforce_ledger.R"), encoding = "UTF-8", keep.source = FALSE)
  oe <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "rf_open_entry"), as.list(ex))
  fm <- if (length(oe)) names(as.list(oe[[1]][[3]][[2]])) else character(0)
  need <- unlist(cfg$run$required_open_entry_formals)
  arms <- pr$arms[order(vapply(pr$arms, function(a) as.numeric(a$order), numeric(1)))]
  steps <- lapply(arms, function(a) {
    cps <- Filter(function(s) a$id %in% unlist(s$after_arms) &&
                    max(vapply(Filter(function(z) z$id %in% unlist(s$after_arms), pr$arms), function(z) as.numeric(z$order), numeric(1))) == as.numeric(a$order),
                  pr$criteria$stop %||% list())
    list(order = a$order, arm = a$id, role = a$role, on_floor = a$on_floor,
         would_call = list(fn = "rf_open_entry", layer = pr$layer, base_id = sprintf("%s__%s", pr$prereg_id, a$id),
                           priority = "prereg", experiment = list(prereg_id = pr$prereg_id, family_id = pr$family_id, arm_id = a$id)),
         stop_checkpoints_after = as.list(vapply(cps, function(s) as.character(s$id), character(1))))
  })
  md5_1 <- if (file.exists(lp)) unname(tools::md5sum(lp)) else NA_character_
  if (!identical(md5_0, md5_1)) stop("[rf_prereg] 드라이런 중 원장이 바뀌었다 — 이 함수는 원장을 쓰지 않는다(동시 writer 확인)")
  # 실행 전제(run_prerequisites) — 등록 차단이 아니라 실행 차단(설계를 바꾸지 않는 실행 경로 의존). P1-08 은 formals 재도출로 따로 잰다
  p108 <- all(need %in% fm)
  rq <- Filter(function(d) !identical(d$status, "available"), pr$run_prerequisites %||% list())
  run_blockers <- c(if (!p108) sprintf("P1-08: rf_open_entry formals 에 %s 부재(재도출)", paste(setdiff(need, fm), collapse = ",")) else character(0),
                    if (!isTRUE(cfg$run$live_enabled)) "run.live_enabled=false · live 경로 없음(이 판)" else character(0),
                    vapply(rq, function(d) sprintf("실행 전제 %s 미충족(%s)", d$id %||% "?", d$status %||% "?"), character(1)))
  list(dry_run = TRUE, prereg_id = pr$prereg_id, kind = kind, integrity = attr(pr, "integrity"),
       ready_to_register = length(v$errors) == 0L, blockers = as.list(v$errors),
       p108_ready = p108, open_entry_formals = as.list(fm), live_enabled = isTRUE(cfg$run$live_enabled),
       live_path = "없음(이 판) — P1-08 뒤 별판", run_blockers = as.list(run_blockers),
       budget = pr$budget$max_cells, steps = steps, ledger_md5 = md5_0, writes = 0L)
}

if (sys.nframe() == 0L) cat("[rf_prereg.R] 라이브러리 — source() 해서 쓴다(검사: 08_Tests/reinforcement/test_rf_prereg.R)\n")

# ══════════════════════════════════════════════════════════════════════════════════════
# 유기체 정책 사전등록 (O0a · 2026-09-25 · 설계 organic_design_final §3 G3 — "최소 writer 를 O0a 에 · P2-01 과 같은 저장소 ·
#   두 번째 writer 금지") — 이 파일의 writer(rf_prereg_write: 덮어쓰기 거부 · 원자 쓰기 · 색인 sha256)를 **그대로** 쓰고
#   스키마 한 벌(rf_prereg_organic_v1)과 관문 술어만 더한다.
# ★P2-01 판으로 충족되는 것(재사용): 저장소 06_Registry/prereg/ · 덮어쓰기 거부(파일·색인 묘비) · 원자 쓰기 · sha256 무결성 로드 ·
#   가족 = 등록본 1개 · 검정력 3종 계산(rf_prereg_power — MDE 는 required_effect_size.R 단일 출처) · hypothesis_index 첨부(rf_prereg_lookup).
# ★부족분(여기서 더한 것):
#   ① 스키마 — 레버 스키마의 layer 는 1/2(계층)이고 floors·arms·contrasts 가 필수라 유기체 정책(층·규칙·파라미터 sha·두 단 창 τ₀/τ_D·
#     리플레이 사전확률)을 담지 못한다 → schema 로 분기(rf_prereg_validate 첫 줄) · layer = "organic" 으로 구분.
#   ② 정책 판 식별 = sha256(규칙 + 파라미터 정규형) — 파라미터가 바뀌면 새 sha = 새 prereg_id(PR-ORG-<정책>-<sha12>) = 새 가족.
#   ③ 관문 rf_prereg_organic_gate — 사전등록 없는 정책(또는 sha 불일치·변조)은 shadow 진입 거부 · 검정력 ratio < 착수 금지 문턱
#     (prereg_config.json::power_gate.ratio_forbidden_below — 단일 출처 · 유기체 config 는 이 키를 가리킨다)이면 '미결 전용'.
#   ④ 문맥 봉쇄 — QVEST_ORGANIC_CTX=1 이면 rf_prereg_write 는 유기체 스키마만 받는다(레버 실험 사전등록은 세션 소관).
RF_PREREG_ORGANIC_SCHEMA <- "rf_prereg_organic_v1"
RF_PREREG_ORGANIC_LAYERS <- c("budget", "space", "select", "structure")
RF_PREREG_ORGANIC_FORBID <- c("essence", "essence_grade", "authoritative_remeasure")   # rf_record_decision 과 같은 AX-008 경계

.rfp_organic_ctx_guard <- function(pr) {
  if (identical(Sys.getenv("QVEST_ORGANIC_CTX", ""), "1") && !(is.list(pr) && identical(pr$schema, RF_PREREG_ORGANIC_SCHEMA)))
    stop("[rf_prereg] 유기체 문맥(QVEST_ORGANIC_CTX=1)은 유기체 정책 사전등록(rf_prereg_organic_v1)만 쓴다 — 레버 실험 사전등록은 세션 소관")
  invisible(TRUE)
}
#' 정규형 — 이름 있는 list 는 키 정렬(재귀) · 이름 없는 list 는 순서 유지
.rfp_canon <- function(x) {
  if (is.list(x)) {
    nm <- names(x)
    if (!is.null(nm) && all(nzchar(nm))) { x <- x[order(nm)]; return(lapply(x, .rfp_canon)) }
    return(lapply(unname(x), .rfp_canon))
  }
  x
}
#' 정책 판 sha — sha256(정규 JSON{rule, params}) · 파라미터가 바뀌면 새 sha(= 새 사전등록 · 새 epoch 는 호출자 몫)
rf_prereg_policy_sha <- function(rule, params) {
  txt <- as.character(toJSON(.rfp_canon(list(rule = rule, params = params %||% list())), auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  .rfp_sha_raw(charToRaw(enc2utf8(txt)))
}
rf_prereg_organic_id <- function(policy_id, sha) {
  pid <- gsub("[^A-Za-z0-9_.-]", "_", as.character(policy_id))
  list(prereg_id = sprintf("PR-ORG-%s-%s", pid, substr(sha, 1L, 12L)), family_id = sprintf("FAM-ORG-%s-%s", pid, substr(sha, 1L, 12L)))
}
.rfp_date1 <- function(s) .rfp_chr1(s) && !is.na(suppressWarnings(as.Date(s, "%Y-%m-%d")))
.rfp_prob_or_na <- function(x) is.null(x) || (length(x) == 1L && (is.na(x) || (is.numeric(x) && x >= 0 && x <= 1)))

#' 유기체 정책 사전등록 검증 — 반환 모양은 rf_prereg_validate 와 같다(ok · errors · registration_blockers · stage)
.rfp_validate_organic <- function(pr, stage, root, cfg) {
  E <- character(0); add <- function(...) E <<- c(E, sprintf(...))
  if (!.rfp_chr1(pr$prereg_id) || !grepl(cfg$layout$prereg_id_pattern, pr$prereg_id) || !startsWith(pr$prereg_id, "PR-ORG-")) add("prereg_id 형식(PR-ORG-…)")
  if (!.rfp_chr1(pr$family_id) || !grepl(cfg$layout$family_id_pattern, pr$family_id) || !startsWith(pr$family_id, "FAM-ORG-")) add("family_id 형식(FAM-ORG-…)")
  if (!identical(as.character(pr$status %||% ""), stage)) add("status(%s) ≠ 단계(%s)", pr$status %||% "?", stage)
  if (stage == "draft" && !(.rfp_num1(pr$draft_rev) && pr$draft_rev >= 1 && pr$draft_rev == round(pr$draft_rev))) add("draft_rev 는 1 이상 정수")
  if (!identical(pr$layer, "organic")) add("layer 는 organic")
  if (!(as.character(pr$organic_layer %||% "") %in% RF_PREREG_ORGANIC_LAYERS)) add("organic_layer 는 %s", paste(RF_PREREG_ORGANIC_LAYERS, collapse = "/"))
  if (!identical(pr$framing, "falsification_attempt")) add("framing 은 falsification_attempt")
  if (.rfp_has_key(pr, RF_PREREG_ORGANIC_FORBID)) add("essence/등급 객체 금지(AX-008)")
  po <- pr$policy
  if (!is.list(po) || !.rfp_chr1(po$policy_id) || is.null(po$rule) || !.rfp_chr1(po$sha)) add("policy{policy_id, rule, params, sha} 필수")
  else {
    want <- rf_prereg_policy_sha(po$rule, po$params)
    if (!identical(po$sha, want)) add("policy.sha 불일치(규칙·파라미터 정규형 재계산 %s ≠ 기재 %s) — 파라미터가 바뀌면 새 sha·새 사전등록", substr(want, 1, 12), substr(po$sha, 1, 12))
    ids <- rf_prereg_organic_id(po$policy_id, po$sha)
    if (!identical(pr$prereg_id, ids$prereg_id)) add("prereg_id ≠ %s(정책·sha 에서 재도출)", ids$prereg_id)
    if (!identical(pr$family_id, ids$family_id)) add("family_id ≠ %s(정책·sha 에서 재도출)", ids$family_id)
  }
  h <- pr$hypothesis
  if (!is.list(h) || !.rfp_chr1(h$statement) || !.rfp_chr1(h$mechanism)) add("hypothesis.statement·mechanism 필수")
  m <- pr$metrics
  if (!is.list(m) || !is.list(m$primary) || !.rfp_chr1(m$primary$id) || !(as.character(m$primary$direction %||% "") %in% RF_PREREG_DIRS))
    add("metrics.primary{id, direction ∈ %s} 필수", paste(RF_PREREG_DIRS, collapse = "/"))
  w <- pr$windows
  if (!is.list(w) || !.rfp_date1(w$tau_0) || !.rfp_date1(w$tau_D) || !.rfp_chr1(w$source)) add("windows{tau_0, tau_D, source} 필수(날짜)")
  else if (!(as.Date(w$tau_0) < as.Date(w$tau_D))) add("windows: tau_0 < tau_D 여야 한다(두 단 as-of — (τ₀, τ_D] 가 채점 창)")
  pw <- pr$power
  if (!is.list(pw) || !.rfp_num1(pw$ratio) || !.rfp_num1(pw$expected_t) || !.rfp_num1(pw$power) || !.rfp_chr1(pw$source))
    add("power{ratio, expected_t, power, source} 필수(검정력 3종 — rf_prereg_power)")
  rp <- pr$replay_prior
  if (!is.list(rp) || !.rfp_chr1(rp$source) || !.rfp_prob_or_na(rp$discovery) || !.rfp_prob_or_na(rp$unreachable))
    add("replay_prior{discovery, unreachable ∈ [0,1]|NA, source} 필수(09-18 리플레이 사전확률)")
  cr <- pr$criteria
  if (!is.list(cr) || !length(cr$success) || !length(cr$failure)) add("criteria.success·failure 필수")
  if (!length(pr$stop)) add("stop(멈춤 조건) 필수")
  lk <- pr$lookup
  if (!is.list(lk) || !.rfp_chr1(lk$status %||% lk$source)) add("lookup(hypothesis_index 첨부) 필수")
  list(ok = !length(E), errors = E, registration_blockers = character(0), stage = stage)
}

#' 유기체 정책 관문 — 정책(policy_id, sha)이 shadow 에 들어갈 수 있는가.
#' @return list(mode = "shadow_ok" | "undetermined_only" | "refused", why, prereg_id, ratio, threshold, threshold_source)
rf_prereg_organic_gate <- function(policy_id, policy_sha, root = NULL, cfg = NULL) {
  root <- .rfp_root(root); cfg <- cfg %||% rf_prereg_config(root)
  ids <- rf_prereg_organic_id(policy_id, policy_sha)
  thr <- cfg$power_gate$ratio_forbidden_below
  out <- function(mode, why, ratio = NA_real_) list(mode = mode, why = why, prereg_id = ids$prereg_id, ratio = ratio, threshold = thr,
                                                   threshold_source = "06_Registry/prereg/prereg_config.json::power_gate.ratio_forbidden_below")
  pr <- tryCatch(rf_prereg_load(ids$prereg_id, "registered", root = root, cfg = cfg), error = function(e) e)
  if (inherits(pr, "error")) return(out("refused", paste0("no_valid_prereg: ", conditionMessage(pr))))
  if (!identical(pr$schema, RF_PREREG_ORGANIC_SCHEMA)) return(out("refused", "schema_not_organic"))
  if (!identical(pr$policy$sha, policy_sha) || !identical(rf_prereg_policy_sha(pr$policy$rule, pr$policy$params), policy_sha))
    return(out("refused", "policy_sha_mismatch"))
  r <- suppressWarnings(as.numeric(pr$power$ratio))
  if (!(length(r) == 1L && is.finite(r))) return(out("refused", "power_ratio_absent"))
  if (!(is.numeric(thr) && length(thr) == 1L && is.finite(thr))) return(out("refused", "threshold_unreadable"))
  if (r < thr) return(out("undetermined_only", sprintf("power ratio %.3f < %.3f — 착수 금지 구간: 판정은 미결 전용(live 불가)", r, thr), r))
  out("shadow_ok", "registered", r)
}
