#==============================================================================
# rf_rebase_driver.R — P0-05 재측정 → P0-06 원장 rebase 드라이버 (2026-09-24 신설 · 통합 검증 I1)
#
# ★왜: P0-05(contracts/remeasure_from_holdings.R)는 칸 산출물마다 새 규약 형제 판을 내고, P0-06 writer
#   (reinforce_ledger.R::rf_rebase_essence_batch)는 형제 판을 받아 원장 essence 를 교체한다. 그 사이의 일 —
#   ① 대상 선정(원장 → 산출물) ② 채점 인자(결정 D-A: DSR N = 계보 누적 raw 측정 칸 수) ③ regime 라벨(P0-05 키)
#   ④ essence_new 조립 ⑤ 기저 rebase ⑥ 축 epoch 전환 조건 — 을 하는 코드가 저장소에 없었다(통합 드라이런은 스크래치 스크립트로 대신).
#   이 파일이 그 일을 한다. 판정 수치는 만들지 않는다(AX-008) — 측정 = P0-05 계약 · 등급 = 형제 판 essence_grade · 쓰기 = 원장 writer.
#
# 단계 (각각 따로 부를 수 있다 — 운영 실행은 도훈 승인 뒤 · 러너 정지(idle) 상태에서):
#   rfr_plan(layer, root, scope)          원장(읽기만) → 대상 행(base_id · n|"base" · artifact · 구 regime · 채점 인자 · C11 skip)
#   rfr_remeasure(plan, exec_price, ...)  rfh_batch(칸별 채점 열 · in_place) — 형제 판 = <artifact>/remeasure_<키>/
#   rfr_items(plan, exec_price, root)     형제 판 → rebase 항목(regime = 키 · essence_new = rf_rebase_essence_from_sibling) ·
#                                         형제 판 채점(selection_type·N)이 계획과 다르면 그 칸은 항목에서 빼고 사유를 남긴다(scoring_mismatch)
#   rfr_rebase(layer, plan, items, ...)   원장이 계획 뒤 바뀌었으면 멈춘다(N 이 낡는다) → rf_rebase_essence_batch
#   rfr_epoch(layer, exec_price, ...)     축 전환 — require_regime = 규약명 ∪ 원장의 그 규약 키 라벨 · 부분 rebase(off_regime entry) ·
#                                         승계 0 이면 거부(통합 검증: 승계 0 인데 전환이 기록됐다 — 결합 풀이 빈다)
#   rfr_run(...)                          위를 순서대로(기본 dry_run = TRUE — 재측정·원장 쓰기 없음)
#
# 채점 인자 (결정 D-A · 06_Registry/decision_register.json "raw 누적 시행수 — DSR N 은 계보 누적 측정 칸 수(P0-01 현행)"):
#   칸(attempt) = selection_type "sweep" · N = 1(기저) + 계보(이 entry + 부모 사슬) 측정 칸 수(상속 칸 제외) — 러너의 등록 시점 산식
#   (rf_runner_gates.R::rf_selection_accounting · rf_lineage_measured) 을 **rebase 시점** 계보에 적용한다(재채점 = 지금의 선택 ·
#   그 뒤 측정 칸까지 센다 = 보수). 한 산출물을 여러 칸이 가리키면 최대 N(보수 — 더 엄격한 DSR).
#   기저 전용 산출물(충실구현 1회 — 칸 참조 없음) = 저장 기록 그대로(chain/1 · 선택 가족이 없다). 승격 entry 의 기저는 부모 승자 칸의
#   산출물이라 칸 참조가 있다 → 그 칸의 sweep N 으로 채점된 같은 형제 판을 쓴다.
# PIT: C11 표식 칸·격리 텍스트 칸은 계획에서 skip(결정 PIT-C11-CONVENTIONS ⑧) — rfh_batch·원장 writer 도 각각 다시 막는다(3중).
# 검사 = 08_Tests/reinforcement/test_rf_rebase_driver.R (골든 사본 · 샌드박스 원장 · 실제 P0-05 판 → rebase → 적대검증 규약 판독 · epoch)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

#' 데이터 루트(원장·설정·산출물). ★명시한 root 는 **그대로** 쓴다 — 다른 후보로 넘어가지 않는다(2026-09-24 실사고: 샌드박스 root 에
#'   코드 표지가 없어 운영 루트로 넘어가, 샌드박스 검사가 운영 원장으로 계획하고 운영 산출물 안에 형제 판을 썼다). 명시 root 는
#'   06_Registry 만 있으면 된다. NULL 일 때만 환경(QM_ROOT → CLAUDE_PROJECT_DIR → getwd)에서 코드 표지로 찾는다.
.rfr_root <- function(root = NULL) {
  if (!is.null(root)) {
    r <- sub("/+$", "", gsub("\\\\", "/", as.character(root)[1]))
    if (is.na(r) || !nzchar(r) || !dir.exists(file.path(r, "06_Registry")))
      stop("[rf_rebase_driver] 명시 root 에 06_Registry 가 없다(다른 루트로 넘어가지 않는다): ", as.character(root)[1])
    return(r)
  }
  cands <- c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), getwd())
  cands <- gsub("\\\\", "/", cands[!is.na(cands) & nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/reinforcement/reinforce_ledger.R"))]
  if (!length(hit)) stop("[rf_rebase_driver] 프로젝트 루트를 찾지 못했다 — root 인자 또는 QM_ROOT")
  hit[1]
}
#' 정본 적재 — 원장 writer · 러너 관문(계보 산식 · 현행 규약) · P0-05 계약. 코드 루트(code_root)와 데이터 루트(root)를 가른다
#'   (검사는 샌드박스 root 에 운영 코드를 적재한다).
rfr_load <- function(code_root = NULL) {
  cr <- if (is.null(code_root)) .rfr_root(NULL) else sub("/+$", "", gsub("\\\\", "/", code_root))
  if (!file.exists(file.path(cr, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
    stop("[rf_rebase_driver] 코드 루트에 reinforce_ledger.R 이 없다: ", cr)
  if (!exists("rf_rebase_essence_batch", mode = "function") || !exists("rf_rebase_essence_from_sibling", mode = "function"))
    invisible(capture.output(suppressMessages(source(file.path(cr, "02_Infrastructure/reinforcement/reinforce_ledger.R"), encoding = "UTF-8"))))
  if (!exists("rf_lineage_measured", mode = "function") || !exists("rf_current_regime", mode = "function")) {
    old <- Sys.getenv("QM_ROOT", NA); Sys.setenv(QM_ROOT = cr)
    on.exit(if (is.na(old)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old), add = TRUE)
    invisible(capture.output(suppressMessages(source(file.path(cr, "02_Infrastructure/reinforcement/rf_runner_gates.R"), encoding = "UTF-8"))))
  }
  if (!exists("rfh_batch", mode = "function")) {
    op <- options(rfh.verbose = FALSE); on.exit(options(op), add = TRUE)
    source(file.path(cr, "02_Infrastructure/contracts/remeasure_from_holdings.R"), encoding = "UTF-8")
  }
  invisible(cr)
}

.rfr_s1 <- function(x) { x <- tryCatch(as.character(unlist(x %||% ""))[1], error = function(e) ""); if (is.na(x)) "" else trimws(x) }
.rfr_abs <- function(p, root) {
  p <- gsub("\\\\", "/", .rfr_s1(p)); if (!nzchar(p)) return(NA_character_)
  if (!grepl("^([A-Za-z]:/|/)", p)) p <- file.path(root, p)
  sub("/+$", "", p)
}
#' 규약 라벨 → 체결 규약명 정규화(키 "<규약>_<md5 8>" 도 그 규약) — rf_runner_gates.R::.rfg_exec_label 과 같은 규칙(허용 규약명 접두)
.rfr_exec_of <- function(label, allowed) {
  l <- .rfr_s1(label); if (!nzchar(l)) return(NA_character_)
  for (x in allowed) if (identical(l, x) || startsWith(l, paste0(x, "_"))) return(x)
  l
}

#' rebase 계획 (원장 읽기만)
#' @param scope "all" = 전환 이전(현행 규약이 아닌) 측정 칸·기저 전수 · "stage1" = rfh_select_stage1 산출물로 좁힌다
#' @param exec_price NULL = 현행 규약(constraint_defaults.json::execution.exec_price — rf_current_regime)
#' @return data.table(base_id, n, role, artifact, regime_old, target, selection_type, n_trials_cumulative, n_trials_basis,
#'   skip, skip_reason) · attr(plan_md5 = 계획 시점 원장 md5, exec_price, layer)
rfr_plan <- function(layer = 1L, root = NULL, scope = c("all", "stage1"), exec_price = NULL, code_root = NULL, ledger_path = NULL) {
  scope <- match.arg(scope)
  root <- .rfr_root(root); rfr_load(code_root)
  lp <- ledger_path %||% file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", as.integer(layer)))
  if (!file.exists(lp)) stop("[rf_rebase_driver] 원장 부재: ", lp)
  md5 <- unname(tools::md5sum(lp))
  L <- jsonlite::fromJSON(lp, simplifyVector = FALSE)
  cur <- rf_current_regime(root)
  ep <- .rfr_s1(exec_price %||% cur$regime)
  if (!nzchar(ep)) stop("[rf_rebase_driver] 목표 규약을 모른다(현행 규약 판독 불가: ", cur$why, ") — exec_price 를 명시하라")
  cdj <- tryCatch(jsonlite::fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE),
                  error = function(e) list())
  allowed <- as.character(unlist((cdj$execution %||% list())$exec_price_allowed %||% c("close_d_legacy", "close_t1", "open_t1")))
  E <- L$entries %||% list()
  blocked <- rf_rebase_block_flags(root)
  rows <- list()
  # D-A — 계보 raw 측정 칸 수(rebase 시점) · entry 별 1회
  nda <- vapply(E, function(e) {
    ids <- rf_lineage_ids(E, .rfr_s1(e$base_id))
    as.integer(1L + rf_lineage_measured(E, ids))
  }, integer(1))
  names(nda) <- vapply(E, function(e) .rfr_s1(e$base_id), character(1))
  for (e in E) {
    bid <- .rfr_s1(e$base_id)
    for (a in e$attempts %||% list()) {
      if (is.null(a[["essence"]])) next
      if (is.list(a$artifacts)) { rows[[length(rows) + 1L]] <- data.table(base_id = bid, n = .rfr_s1(a$n), role = "attempt", artifact = NA_character_,
                                    regime_old = NA_character_, flags = "", skip = TRUE, skip_reason = "artifacts_form(WT dict)"); next }
      r <- rf_attempt_regime(a, root)
      if (identical(.rfr_exec_of(r$regime, allowed), ep)) next                 # 이미 목표 규약(native 신규 칸 · rebase 끝난 칸)
      fl <- .rf_flags_hit(a$vintage_flags, blocked)
      rows[[length(rows) + 1L]] <- data.table(base_id = bid, n = .rfr_s1(a$n), role = "attempt", artifact = .rfr_abs(a$artifacts, root),
                                              regime_old = .rfr_s1(r$regime %||% r$basis), flags = paste(fl, collapse = ","),
                                              skip = length(fl) > 0L, skip_reason = if (length(fl)) paste0("blocked_flag:", paste(fl, collapse = "+")) else "")
    }
    if (nzchar(.rfr_s1(e$base_artifacts)) && !is.list(e$base_artifacts)) {
      br <- rf_base_regime(e, root)
      if (!identical(br$basis, "base_unmeasured") && !identical(.rfr_exec_of(br$regime, allowed), ep)) {
        fl <- .rf_flags_hit(e$base_vintage_flags, blocked)
        rows[[length(rows) + 1L]] <- data.table(base_id = bid, n = "base", role = "base", artifact = .rfr_abs(e$base_artifacts, root),
                                                regime_old = .rfr_s1(br$regime %||% br$basis), flags = paste(fl, collapse = ","),
                                                skip = length(fl) > 0L, skip_reason = if (length(fl)) paste0("blocked_flag:", paste(fl, collapse = "+")) else "")
      }
    }
  }
  P <- if (length(rows)) rbindlist(rows, fill = TRUE) else
    data.table(base_id = character(0), n = character(0), role = character(0), artifact = character(0), regime_old = character(0),
               flags = character(0), skip = logical(0), skip_reason = character(0))
  if (identical(scope, "stage1") && nrow(P)) {
    s1 <- rfh_select_stage1(layer = layer, root = NULL, ledger = lp)       # 원장 = 이 root 의 원장(명시) · 문턱·격리 = 계약 루트
    keep <- tolower(P$artifact) %in% tolower(s1$artifact)
    P <- P[keep | is.na(artifact)]
  }
  # 채점 인자 — 산출물 단위(형제 판은 산출물당 하나): 칸 참조가 있으면 sweep · 최대 D-A N · 없으면(기저 전용) 저장 기록
  P[, target := ep]
  P[, `:=`(selection_type = NA_character_, n_trials_cumulative = NA_integer_, n_trials_basis = NA_character_)]
  if (nrow(P)) {
    att_n <- P[role == "attempt" & !is.na(artifact), .(nmax = max(nda[base_id]), ents = paste(unique(base_id), collapse = ";")), by = .(akey = tolower(artifact))]
    P[, akey := tolower(artifact)]
    P[att_n, on = "akey", `:=`(selection_type = "sweep", n_trials_cumulative = i.nmax,
                               n_trials_basis = sprintf("D-A raw 누적(rebase 시점): 1(기저) + 계보 측정 칸(상속 제외) · 산출물 참조 entry 최대 · %s", i.ents))]
    P[is.na(selection_type) & role == "base", n_trials_basis := "stored_auth(기저 전용 산출물 — 충실구현 1회 · 선택 가족 없음)"]
    P[, akey := NULL]
  }
  attr(P, "plan_md5") <- md5; attr(P, "exec_price") <- ep; attr(P, "layer") <- as.integer(layer); attr(P, "ledger_path") <- lp
  P[]
}

#' 재측정 — 산출물 단위(skip 아닌 행) · 칸별 채점 열로 rfh_batch. in_place=TRUE 가 없으면 멈춘다(원장 writer 는 칸 산출물 안 형제만 받는다).
rfr_remeasure <- function(plan, root = NULL, in_place = FALSE, n_workers = NULL, claim = NULL, barrier = TRUE, ledger = NULL, force = FALSE, ...) {
  root <- .rfr_root(root)
  if (!isTRUE(in_place)) stop("[rf_rebase_driver] 재측정은 칸 산출물 안(in_place=TRUE)에 써야 원장 writer 가 형제로 받는다 — 운영 실행은 별도 승인")
  P <- as.data.table(plan)[skip == FALSE & !is.na(artifact)]
  if (!nrow(P)) return(list(status = "empty", rows = data.table(), skipped = data.table(), failed = list()))
  # ★쓰기 경계 — 계획의 원장이 이 root 의 원장이고, 쓸 산출물이 전부 root 아래여야 한다(샌드박스 root 로 운영 계획을 돌리거나 그 반대를
  #   막는다 · 2026-09-24 실사고 재발 방지). 원장 경로·산출물 경로 모두 대소문자 무시 접두 비교.
  lk <- function(p) tolower(sub("/+$", "", gsub("\\\\", "/", p)))
  if (!startsWith(lk(attr(plan, "ledger_path")), paste0(lk(root), "/")))
    stop("[rf_rebase_driver] 계획의 원장이 이 root 밖이다 — 계획과 쓰기 root 가 다르다(아무것도 쓰지 않았다): ", attr(plan, "ledger_path"))
  out <- P$artifact[!startsWith(lk(P$artifact), paste0(lk(root), "/"))]
  if (length(out)) stop(sprintf("[rf_rebase_driver] root 밖 산출물 %d건(예: %s) — in-place 쓰기 거부(아무것도 쓰지 않았다)", length(out), out[1]))
  sel <- unique(P[, .(artifact, selection_type, n_trials_cumulative, n_trials_basis)], by = "artifact")
  # 측정 코드·시장 데이터 = 계약 자신의 루트(rfh_root(NULL)) · PIT 판정 원장 = 계획의 원장(데이터 root) · 쓰기 = 산출물 안(root 아래)
  #   배치 manifest 도 데이터 root 아래(rfh_batch 기본은 계약 루트의 .cache — 샌드박스 실행이 운영 .cache 에 쓰지 않게)
  mp <- file.path(root, ".cache", "remeasure", sprintf("rfr_batch_%s_%d.json", format(Sys.time(), "%Y%m%d_%H%M%S"), Sys.getpid()))
  rfh_batch(sel, exec_prices = attr(plan, "exec_price"), in_place = TRUE, n_workers = n_workers, claim = claim, force = force,
            root = NULL, barrier = barrier, ledger = ledger %||% attr(plan, "ledger_path"), manifest_path = mp, ...)
}

#' rebase 항목 — 형제 판(<artifact>/remeasure_<키>/authoritative_remeasure.json)이 있고 채점이 계획과 같은 행만.
#' @return list(items, missing = data.table(base_id, n, artifact, reason))
rfr_items <- function(plan, root = NULL, code_root = NULL) {
  root <- .rfr_root(root); rfr_load(code_root)
  ep <- attr(plan, "exec_price"); key <- rfh_regime(ep, NULL)$key          # 키 = 계약 자신의 하네스(rfr_remeasure 와 같은 루트)
  lp <- attr(plan, "ledger_path"); L <- jsonlite::fromJSON(lp, simplifyVector = FALSE)
  items <- list(); miss <- list()
  P <- as.data.table(plan)
  for (k in seq_len(nrow(P))) {
    r <- P[k]
    if (isTRUE(r$skip) || is.na(r$artifact)) { miss[[length(miss) + 1L]] <- data.table(base_id = r$base_id, n = r$n, artifact = r$artifact, reason = r$skip_reason); next }
    sp <- file.path(r$artifact, paste0("remeasure_", key), "authoritative_remeasure.json")
    if (!file.exists(sp)) { miss[[length(miss) + 1L]] <- data.table(base_id = r$base_id, n = r$n, artifact = r$artifact, reason = "sibling_absent"); next }
    sj <- jsonlite::fromJSON(sp, simplifyVector = FALSE)
    mr <- sj$measurement_regime %||% list()
    want_st <- r$selection_type; want_n <- r$n_trials_cumulative
    if (!is.na(want_st) && (!identical(.rfr_s1(mr$selection_type), want_st) ||
                            !identical(suppressWarnings(as.integer(mr$n_trials_cumulative)), as.integer(want_n)))) {
      miss[[length(miss) + 1L]] <- data.table(base_id = r$base_id, n = r$n, artifact = r$artifact,
                                              reason = sprintf("scoring_mismatch(형제 %s/%s ≠ 계획 %s/%s)", .rfr_s1(mr$selection_type),
                                                               .rfr_s1(mr$n_trials_cumulative), want_st, want_n)); next
    }
    it <- list(base_id = r$base_id, n = if (identical(r$n, "base")) "base" else as.integer(r$n), regime = key,
               provenance = list(remeasure_path = sp, driver = "rf_rebase_driver.R", plan_md5 = attr(plan, "plan_md5"),
                                 n_trials_basis = .rfr_s1(mr$n_trials_basis), scoring_md5 = .rfr_s1(mr$scoring_md5)))
    if (identical(r$n, "base")) it$essence_new <- NULL else {
      e <- L$entries[[.rf_find(L, r$base_id)]]
      a <- Filter(function(x) identical(.rfr_s1(x$n), r$n), e$attempts %||% list())[[1]]
      it$essence_new <- rf_rebase_essence_from_sibling(a[["essence"]], sj)
    }
    items[[length(items) + 1L]] <- it
  }
  list(items = items, missing = if (length(miss)) rbindlist(miss, fill = TRUE) else data.table())
}

#' 원장 rebase — 계획 뒤 원장이 바뀌었으면 멈춘다(D-A N 이 낡는다). dry_run 기본.
rfr_rebase <- function(plan, items, root = NULL, dry_run = TRUE, skip_rejected = TRUE, claim = NULL, ...) {
  root <- .rfr_root(root)
  lp <- attr(plan, "ledger_path")
  if (!identical(unname(tools::md5sum(lp)), attr(plan, "plan_md5")))
    stop("[rf_rebase_driver] 계획 뒤 원장이 바뀌었다 — D-A N·대상이 낡았다. rfr_plan 부터 다시(아무것도 쓰지 않았다)")
  if (!length(items)) return(list(n_rebased = 0L, written = FALSE, items = list()))
  rf_rebase_essence_batch(attr(plan, "layer"), items, root = root, skip_rejected = skip_rejected, dry_run = dry_run, claim = claim, ...)
}

#' 축 epoch 전환 — require_regime = 목표 규약명 ∪ 원장에 기록된 그 규약의 키 라벨. 부분 rebase·승계 0 이면 거부(dry_run 기본).
rfr_epoch <- function(layer = 1L, root = NULL, exec_price = NULL, epoch, legacy, reason, evidence, relabel_from = NULL,
                      allow_partial = FALSE, dry_run = TRUE, claim = NULL, code_root = NULL) {
  root <- .rfr_root(root); rfr_load(code_root)
  L <- rf_load(layer, root)
  ep <- .rfr_s1(exec_price %||% rf_current_regime(root)$regime)
  labs <- unique(c(unlist(lapply(L$entries, function(e) c(
    vapply(e$attempts %||% list(), function(a) .rfr_s1((if (is.list(a$measurement_regime)) a$measurement_regime else list())$regime), character(1)),
    .rfr_s1((if (is.list(e$base_measurement_regime)) e$base_measurement_regime else list())$regime))))))
  labs <- labs[nzchar(labs) & (labs == ep | startsWith(labs, paste0(ep, "_")))]
  acc <- unique(c(ep, labs))
  rel <- relabel_from %||% .rfr_s1(L$current_axis)
  d <- rf_mark_axis_epoch(layer, epoch, legacy, reason, evidence, root = root, relabel_from = rel, require_regime = acc, dry_run = TRUE)
  off <- Filter(function(x) identical(x$to, "legacy") && identical(x$why, "off_regime"), d$plan)
  if (length(off) && !isTRUE(allow_partial))
    stop(sprintf("[rf_rebase_driver] 축 전환 거부 — rebase 가 안 끝난 entry %d건(off_regime · 예: %s). 전 칸 rebase 뒤에만 전환한다(allow_partial=TRUE 로만)",
                 length(off), paste(utils::head(vapply(off, function(x) sprintf("%s[%s]", x$base_id, paste(utils::head(unlist(x$off), 2), collapse = ",")),
                                                       character(1)), 3), collapse = " · ")), call. = FALSE)
  if (d$n_carried == 0L)
    stop("[rf_rebase_driver] 축 전환 거부 — 새 축 승계 0건(전환하면 결합 풀·비교 대상이 빈다 · 통합 검증 지적)", call. = FALSE)
  if (isTRUE(dry_run)) return(c(d, list(require_regime = acc)))
  c(rf_mark_axis_epoch(layer, epoch, legacy, reason, evidence, root = root, relabel_from = rel, require_regime = acc, claim = claim),
    list(require_regime = acc))
}

#' 전 과정 — 기본 dry_run(재측정·원장 쓰기 없음: 계획 + 이미 있는 형제 판으로 항목 검증까지)
rfr_run <- function(layer = 1L, root = NULL, scope = "all", exec_price = NULL, dry_run = TRUE, in_place = FALSE, n_workers = NULL,
                    claim = NULL, barrier = TRUE, code_root = NULL) {
  P <- rfr_plan(layer, root, scope, exec_price, code_root = code_root)
  B <- if (!isTRUE(dry_run)) rfr_remeasure(P, root, in_place = in_place, n_workers = n_workers, claim = claim, barrier = barrier) else NULL
  I <- rfr_items(P, root, code_root = code_root)
  R <- rfr_rebase(P, I$items, root, dry_run = dry_run, claim = claim)
  list(plan = P, batch = B, items = I, rebase = R)
}

if (sys.nframe() == 0L)
  cat("[rf_rebase_driver.R] Loaded (P0-05→06 · I1) — rfr_plan / rfr_remeasure / rfr_items / rfr_rebase / rfr_epoch / rfr_run\n")
