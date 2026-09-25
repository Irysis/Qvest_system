# =============================================================================
# reinforce_ledger.R — 강화 프로세스 원장 (v10 2026-08-29 신설, 통일 스키마 v2)
# =============================================================================
# 도훈 지시:
#   1계층: "강화 프로세스는 최대 20회 진행 … 실패의 재생산을 방지하기 위해 20회 제한"
#          ★2026-09-01 격자 재편(B5 리스크 오버레이 블록 신설 · 5블록×5)으로 상한 25 — 원장 파일 max_attempts=25 가 정본. 위 인용은 8-29 원문.
#          + "논문 3개마다 Q-Lead 가 아이디어 결합을 자체 검토"
#   2계층: "강화 프로세스 시도 횟수 제한이 없으며 교훈을 지속적으로 주입 받으면서
#          A등급 달성까지 무한 리서치 모드"
#   공통: "리서치 계획 설계 전에 Axiom 엔진을 활용하여 공리·교훈 주입, 완결 이후
#          교훈 생산 필수" + "모든 의사결정에 근거 논문(원문 링크) 필수"
#
# ★코드베이스에 시도 카운터 개념이 없었다(2026-08-29 전수 실측) — 이 원장이 유일 정본.
# ★root_papers 필수 거부는 2026-09-03 **해제**(도훈 "강화에는 근거논문 필요없게 배선해").
#   지금은 거부하지 않고 시도 레코드에 evidence = paper/method/none 을 남긴다.
# ★구 reinforce_ladder_ledger.json(기계 사다리, v9.21)은 read-only 동결 — 별개 파일.
#
# 파일: 06_Registry/reinforce_ledger_l1.json (max_attempts=25)
#       06_Registry/reinforce_ledger_l2.json (max_attempts=null — 무한)
# 쓰기 계약: 원자(tmp+rename) + 쓰기 직전 재파싱 검증 (paper_id_norm append 계약 미러).
# =============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.rf_root <- function() {
  cands <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cands) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[reinforce_ledger] project root 미발견 — QM_ROOT 설정 필요")
}

# ★universe 는 2026-08-30 도훈 지시로 격자 B3 가 리스크오버레이 → 유니버스로 바뀌면서 생겼다.
#   그런데 이 목록은 안 따라와서 B3 5칸이 **등록 자체로 거부**됐고(append_failed → halt_no_jobs)
#   루프가 10/20 에서 멈췄다. risk_overlay 는 격자 밖 경로에서 쓰이므로 존치한다.
# ★execution_cadence(B6 · 2026-09-21 도훈 승인) — 집행 주기·회전 통제 축.
#   격자에만 넣고 여기를 안 고치면 rf_append_attempt 가 그 블록의 등록을 **거부**해 루프가 멈춘다
#   (배터리 "격자↔원장 계약" 이 그 상태를 잡는다 — 실제로 잡혔다).
RF_KEYWORD_AXES_L1 <- c("multifactor", "weighting", "universe", "risk_overlay", "combination",
                        "execution_cadence",
                        # ★structural_defense(B7 · 2026-09-21 도훈 승인) — 선정 축의 구조적 방어.
                        #   노출(B5)도 상대배분(B2)도 아닌 '무엇을 보유하는가'. 축이 허용목록에
                        #   없으면 원장이 블록 등록을 거부해 칸이 한 번도 안 선다.
                        "structural_defense")
RF_KEYWORD_AXES_L2 <- c("regime_identification", "strategy_combination")
RF_STATUS_ENUM <- c("active", "graduated", "exhausted", "superseded", "parked")

.rf_path <- function(layer, root = .rf_root()) {
  stopifnot(layer %in% c(1L, 2L))
  file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", layer))
}

.rf_skeleton <- function(layer) {
  list(
    schema_version = "reinforce_ledger_v2",
    layer = as.integer(layer),
    # ★2026-09-21 도훈 승인 — B6(집행 주기) 축 신설로 격자가 6블록x5 = 30칸이 됐다.
    #   기반 예산이 25 에 머물면 새 축은 칸을 못 받고 굶는다(러너의 자동 상향은 설계 초과분만 더한다).
    max_attempts = if (layer == 1L) 35L else NULL,   # NULL = 무한 (2계층 · 7블록x5)
    note = if (layer == 1L)
      "v10 1계층 강화 원장 — QEPM(alpha→risk→optimizer→forge→등급) 기반, 논문당 최대 30회(격자 6블록×5). root_papers 는 선택(2026-09-03 의무 해제) — 시도마다 evidence=paper/method/none 기록. 논문 3편마다 combination_review 의무." else
      "v10 2계층 강화 원장 — 국면식별/전략결합 축, A등급까지 무한. 착수 시 직전 attempts 의 lessons 주입 의무.",
    entries = list(),
    combination_review = if (layer == 1L)
      list(papers_since_last_review = 0L, last_review_date = "", history = list()) else NULL,
    last_updated = ""
  )
}

rf_load <- function(layer, root = .rf_root()) {
  p <- .rf_path(layer, root)
  if (!file.exists(p)) return(.rf_skeleton(layer))
  obj <- fromJSON(p, simplifyVector = FALSE)
  if (!identical(obj$schema_version, "reinforce_ledger_v2"))
    stop(sprintf("[reinforce_ledger] schema_version 불일치: %s", obj$schema_version))
  obj
}

.rf_write <- function(obj, layer, root = .rf_root()) {
  # 재파싱 검증 후 원자 쓰기
  obj$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || length(chk$entries) != length(obj$entries))
    stop("[reinforce_ledger] 쓰기 직전 재파싱 검증 실패 — 원본 불변")
  p <- .rf_path(layer, root)
  tmp <- paste0(p, ".tmp")
  write(txt, tmp)
  ok <- suppressWarnings(file.rename(tmp, p))
  if (!ok) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }  # Windows 폴백(소비자 재시도 별도)
  invisible(p)
}

.rf_find <- function(obj, base_id) {
  for (i in seq_along(obj$entries)) if (identical(obj$entries[[i]]$base_id, base_id)) return(i)
  NA_integer_
}

#' 소진 요약 표식 — 요약·승격 판정은 entry 당 한 번이다 (2026-09-04).
#'   실측: 결합 설계 요청이 진행 중이면 handed_off 가 안 서서(둘 중 하나만 간다) exhausted_summary·
#'   promote_skipped 가 tick 마다 다시 찍혔다(combo_rulefast 3회). 이월은 handed_off 가, 요약은 이 표식이 막는다.
rf_is_summarized <- function(entry) nzchar(as.character(entry$summarized_at %||% ""))
rf_mark_summarized <- function(layer, base_id, root = .rf_root()) {
  obj <- rf_load(layer, root)
  k <- which(vapply(obj$entries, function(e) identical(e$base_id, base_id), logical(1)))
  if (!length(k)) stop("[reinforce_ledger] entry not found: ", base_id)
  obj$entries[[k[1]]]$summarized_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .rf_write(obj, layer, root)
  invisible(TRUE)
}

#' 이월 완료 표식 — 이 entry 는 다음 tick 부터 요약·승격 대상이 아니다.
#'   두 이월 경로(다음 논문 hand-off · 승격)가 **같은 표식**을 남겨야 한다. 2026-09-05 실사고: 승격 경로가
#'   부모에 표식을 안 남겨, 손자가 큐로 넘어간 뒤 부모(promo2)가 "마지막 미이월 소진 entry" 로 다시 떠올라
#'   매 tick 재승격(기존 promo3 재사용)했다 — 큐 논문 미착수 + 라운드 리뷰 텔레그램 중복.
#' @param promoted_to 승격 경로면 자식 base_id (provenance) · hand-off 면 NULL
#' @param reason 소급 표식 등 사유(선택)
rf_mark_handed_off <- function(layer, base_id, root = .rf_root(), promoted_to = NULL, reason = NULL) {
  obj <- rf_load(layer, root)
  k <- which(vapply(obj$entries, function(e) identical(e$base_id, base_id), logical(1)))
  if (!length(k)) stop("[reinforce_ledger] entry not found: ", base_id)
  obj$entries[[k[1]]]$handed_off    <- TRUE
  obj$entries[[k[1]]]$handed_off_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (!is.null(promoted_to) && nzchar(promoted_to)) obj$entries[[k[1]]]$promoted_to <- promoted_to
  if (!is.null(reason) && nzchar(reason)) obj$entries[[k[1]]]$handed_off_reason <- reason
  .rf_write(obj, layer, root)
  invisible(TRUE)
}

# =============================================================================
# 데이터 컷오프·빈티지 지문 (P0-07 · 2026-09-24 · 감사 D4-11·D8-03 · 플랜 qvest-1-drifting-eclipse P0-07)
# =============================================================================
# ★왜: 강화 레인은 판본을 고정하지 않았다. 한 entry 의 칸들이 서로 다른 데이터 종료일에서 측정됐고(원장 재도출
#   rf_entry_end_dates — 감사 시점 6개 · 09-24 8개), 승격은 부모 저장값(다른 판본)과 자식 칸을 비교했다. 09-18 벤치 축
#   이관처럼 **과거 행이 개정**되면 같은 스펙도 다른 값이 된다(measurement-graduation §7).
# 계약:
#   · entry 는 태어날 때 data_cutoff(직전 완결 월말 — pin_cache.R::pin_complete_month_end: 데이터가 그 월말을 넘어섰음이
#     증명된 마지막 월말)와 data_fingerprint(pin_cache.R::pin_fingerprint scheme pin_fp_v2 — cutoff 이하 RAWDATA **소비 열**의
#     행 키(Date·Ticker) 정렬 바이트 해시 + 벤치 같은 방식 + 팩터 DB 월 파일 목록)를 단다. 호출자가 data_cutoff 를 주면 그 값을 쓴다.
#     ★소비 열 = 측정 경로 소비자 코드(러너·하네스·셀 엔진 + source 폐포 + 이 entry 의 engine_path)에서 재도출한다 — 열 목록을
#     여기 적지 않는다(수리 2026-09-25 적대검증 F1: v1 은 Close·Ret·K200·KQ150 연도별 정렬 합이라 셀 엔진의 Vol·Size 개정과
#     합 보존 맞교체를 'match' 로 적었다).
#   · 승격 자식(parent 인자)은 **부모 cutoff·부모 지문의 열로 다시 잰 지문**을 부모 지문과 대조한다(같은 cutoff·같은 열끼리만
#     비교 가능 — cutoff 가 다르면 창 자체가 다르다). 결과 = data_vintage_vs_parent{status = match|mismatch|unknown, reason =
#     history_revised(부모 cutoff 이하 과거 행 개정) · cutoff_changed(자식 창이 부모와 다름), parts, years, cols(다른 열)}.
#     mismatch → jlog 'vintage_mismatch' · 부모 지문 부재(P0-07 이전 entry)·계산 실패 → jlog 'vintage_unverified'.
#     ★지문 밖 소비 원천(2차 적대검증 F2 — 엔진이 직접 읽는 fundamental_merged·consensus 등 · pin_cache.R sources)이나 한쪽만 본
#     팩터 DB 가 있으면 해시가 같아도 match 로 세지 않는다 → unknown(why history_match_unverified:…) + jlog 'vintage_unverified'.
#     ★기록·로그만 한다(차단 아님) — 승격 판정 교체는 P1(같은 판본 재측정 비교)의 일이다.
#   · 측정 창 절단(run_paper_replication(data_cutoff=))은 **이 원장이 켜지 않는다** — 러너 spec(SPEC$data_cutoff ←
#     E$data_cutoff)·워커 인자 배선은 소유 밖이고, 켜는 순간 측정 창이 바뀌어 한 entry 안에 두 창이 섞인다 →
#     P0-06 epoch 전환과 함께 켠다(보고서 '남은 일').
#   · 지문 계산(키 + 소비 열 11종 적재·소비자 재도출 약 4초 + 계산 약 12초 · 최대 약 1.1GB — 2026-09-25 실측 1,412만 행 ·
#     승격 자식이 부모와 cutoff 가 다르면 부모 cutoff 재계산 약 12초 추가)은 원장 read-modify-write 창 **밖**에서 한다 —
#     적재 동안 다른 writer 가 쓴 것을 덮지 않게 계산 뒤 원장을 다시 읽어 붙인다.
#   · 실패는 개설을 막지 않는다 — data_fingerprint$status = error/absent(+why)로 남는다(조용한 누락 아님).
#     끄개: 환경변수 QVEST_RF_VINTAGE=0 → status=disabled(계산 0 · 비상용).
#   · pin_cache.R 은 통째로 source 하지 않는다(머리의 config.R source 가 호출자 전역을 덮는다) — 지문 정의만 parse→eval.
RF_DATA_VINTAGE_SWITCH <- "QVEST_RF_VINTAGE"
RF_PIN_FP_DEF_RE <- "^(pin_fingerprint|pin_complete_month_end|pin_fp_|\\.pin_fp_)"

#' 지문 함수 적재 — <root> 사본 우선(사본 트리에서 운영 코드를 섞지 않게), 없으면 코드 루트.
.rf_pin_fp_env <- function(root) {
  cand <- file.path(c(root, tryCatch(.rf_root(), error = function(e) character(0))), "02_Infrastructure/data/pin_cache.R")
  cand <- unique(cand[file.exists(cand)])
  if (!length(cand)) stop("pin_cache.R 부재 — 지문 정의를 찾을 수 없다")
  ex <- parse(cand[1], encoding = "UTF-8", keep.source = FALSE)
  env <- new.env(parent = baseenv())
  for (e in as.list(ex))
    if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) &&
        grepl(RF_PIN_FP_DEF_RE, as.character(e[[2]]))) eval(e, env)
  for (nm in c("pin_fingerprint", "pin_fingerprint_load", "pin_fingerprint_compare", "pin_complete_month_end", ".pin_fp_cutoff",
               "pin_fp_consumers"))
    if (!exists(nm, envir = env, inherits = FALSE)) stop(sprintf("pin_cache.R 에 %s 정의 부재 — 판본 확인", nm))
  env$.src <- cand[1]
  env
}

#' entry 개설용 빈티지 계산(원장 무쓰기) — list(data_cutoff = "YYYY-MM-DD"|NULL, fp, vs_parent|NULL)
#' @param parent_entry 부모 entry(같은 원장 · 없으면 NULL) · has_parent = 승격 개설인가(parent 인자 유무)
#' @param engine_path 이 entry 의 엔진(충실구현 엔진) — 그 파일이 읽는 열도 소비 열이다(없거나 못 찾으면 why 에 engine_absent)
.rf_entry_vintage <- function(root, data_cutoff = NULL, parent_entry = NULL, has_parent = FALSE, parent_base_id = "",
                              engine_path = "") {
  out <- list(data_cutoff = NULL, fp = NULL, vs_parent = NULL)
  if (identical(Sys.getenv(RF_DATA_VINTAGE_SWITCH, "1"), "0")) {
    out$fp <- list(status = "disabled", why = paste0(RF_DATA_VINTAGE_SWITCH, "=0"))
    if (has_parent) out$vs_parent <- list(status = "unknown", why = "vintage_disabled", parent_base_id = parent_base_id)
    return(out)
  }
  pfp <- if (is.list(parent_entry)) parent_entry$data_fingerprint else NULL
  pco <- if (is.list(parent_entry)) .rf_s1(parent_entry$data_cutoff) else ""
  # 부모 지문의 열(부모 cutoff 재측정은 **부모 열로** — 소비자 코드가 그 뒤 바뀌어도 대조 가능) — 한 번 적재에 함께 싣는다
  p_raw <- if (is.list(pfp) && identical(.rf_s1(pfp$status), "ok")) as.character(unlist(pfp$raw$cols)) else NULL
  p_bm  <- if (is.list(pfp) && identical(.rf_s1(pfp$status), "ok")) as.character(unlist(pfp$bm$cols)) else NULL
  r <- tryCatch({
    F <- .rf_pin_fp_env(root)
    croots <- unique(c(root, tryCatch(.rf_root(), error = function(e) character(0))))   # 소비자 코드: 사본 루트 우선 → 코드 루트
    eng <- .rf_s1(engine_path)
    eng <- if (nzchar(eng)) { a <- tryCatch(.rf_abs_path(eng, root), error = function(e) NA_character_)
                              if (length(a) == 1L && !is.na(a) && file.exists(a)) a else eng } else NULL
    L <- F$pin_fingerprint_load(root, code_root = croots, engines = eng, extra_raw_cols = p_raw)
    if (is.null(L$raw) || is.null(L$bm)) {
      list(data_cutoff = NULL, fp = list(scheme = F$.pin_fp_SCHEME, status = "absent", why = L$why), F = F, L = NULL, co = NA)
    } else {
      co <- if (!is.null(data_cutoff)) F$.pin_fp_cutoff(data_cutoff) else F$pin_complete_month_end(L$raw$Date, L$bm$Date)
      if (is.na(co)) stop("데이터 최대일에서 직전 완결 월말을 정할 수 없다")
      fp <- F$pin_fingerprint(co, raw = L$raw, bm = L$bm, fdb_dir = L$fdb_dir, raw_cols = L$raw_cols, bm_cols = L$bm_cols,
                              consumers = L$consumers)
      if (length(L$why)) fp$why <- unique(c(fp$why, L$why))   # engine_absent 등 — 조용한 누락 없음
      list(data_cutoff = format(co), fp = fp, F = F, L = L, co = co)
    }
  }, error = function(e) list(data_cutoff = NULL, fp = list(status = "error", why = conditionMessage(e)), F = NULL, L = NULL))
  out$data_cutoff <- r$data_cutoff; out$fp <- r$fp
  if (!has_parent) return(out)
  vs <- list(parent_base_id = parent_base_id, parent_cutoff = if (nzchar(pco)) pco else NULL, child_cutoff = r$data_cutoff)
  if (is.null(parent_entry)) {
    vs$status <- "unknown"; vs$why <- "parent_entry_absent"
  } else if (!is.list(pfp) || !identical(.rf_s1(pfp$status), "ok") || !nzchar(pco)) {
    vs$status <- "unknown"; vs$why <- "parent_fingerprint_absent"          # P0-07 이전 부모 — 대조 불가(추정하지 않는다)
  } else if (is.null(r$L) || !identical(.rf_s1(r$fp$status), "ok")) {
    vs$status <- "unknown"; vs$why <- paste0("child_fingerprint_", .rf_s1(r$fp$status))
  } else {
    cmp <- tryCatch({
      same_cols <- identical(p_raw, as.character(r$fp$raw$cols)) && identical(p_bm, as.character(r$fp$bm$cols))
      fpp <- if (identical(pco, r$data_cutoff) && same_cols) r$fp else
        r$F$pin_fingerprint(pco, raw = r$L$raw, bm = r$L$bm, fdb_dir = r$L$fdb_dir,
                            raw_cols = p_raw, bm_cols = p_bm)   # 부모 cutoff·부모 열로 다시 잰 지문
      # F2 — 재측정본(열 지정 = 소비자 재도출 없음)에는 자식 판의 소비 원천 범위를 싣는다(지문 밖 원천이 대조에서 사라지지 않게)
      if (!identical(.rf_s1(fpp$sources$status), "ok")) fpp$sources <- r$fp$sources
      r$F$pin_fingerprint_compare(pfp, fpp)
    }, error = function(e) list(status = "unknown", why = paste0("compare_error: ", conditionMessage(e))))
    chg <- !identical(pco, r$data_cutoff)
    rev <- identical(cmp$status, "mismatch")
    vs$history <- cmp$status; vs$history_why <- cmp$why %||% ""
    vs$parts <- cmp$parts %||% character(0); vs$years <- cmp$years %||% integer(0)
    vs$cols <- cmp$cols %||% character(0)
    vs$unverified <- cmp$unverified %||% character(0)
    vs$cutoff_changed <- chg
    # ★F2 — 해시한 원천이 같아도 지문 밖에서 확인 못 한 부분(unverified: 지문 밖 소비 원천 src:* · 한쪽만 본 팩터 DB)이 있으면
    #   '일치'로 세지 않는다(unknown + jlog vintage_unverified · history 는 match 그대로 남긴다).
    vs$status <- if (rev || chg) "mismatch" else if (identical(cmp$status, "match") && !length(vs$unverified)) "match" else "unknown"
    vs$reason <- paste(c(if (rev) "history_revised", if (chg) "cutoff_changed"), collapse = "+")
    if (identical(vs$status, "unknown"))
      vs$why <- if (identical(cmp$status, "match")) paste0("history_match_unverified:", paste(vs$unverified, collapse = ",")) else
        paste0("history_", cmp$status)
  }
  out$vs_parent <- vs
  out
}

#' 원장 저널 1줄(러너 jlog 와 같은 파일·같은 모양 · src=ledger). 싱크 = QVEST_RP_JLOG(검사 격리) → <root>/.cache/reinforce_auto_log.jsonl.
.rf_ledger_jlog <- function(root, event, ...) {
  p <- Sys.getenv("QVEST_RP_JLOG", file.path(root, ".cache", "reinforce_auto_log.jsonl"))
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "ledger"), list(...))
  tryCatch({
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = p, append = TRUE)
  }, error = function(e) cat(sprintf("[reinforce_ledger] jlog 실패(비치명): %s\n", conditionMessage(e))))
  invisible(TRUE)
}

#' 원장 재도출(읽기 전용) — entry 별 칸 측정 데이터 종료일 분포(칸 산출물 00_manifest.json 의 end_date).
#'   감사 D8-03 "entry 안 end_date 혼재" 의 계기. idx0 = 0-기준 색인(감사 표기와 같은 번호).
#' @param obj 원장 객체(검사·사본용) — NULL 이면 rf_load(layer, root)
#' @return data.frame(idx0, base_id, n_cells, n_manifest, n_end_dates, end_dates("날짜:칸수;…"), data_cutoff)
rf_entry_end_dates <- function(layer = 1L, root = .rf_root(), obj = NULL) {
  if (is.null(obj)) obj <- rf_load(layer, root)
  rows <- lapply(seq_along(obj$entries), function(k) {
    e <- obj$entries[[k]]; ends <- character(0); nc <- 0L
    for (a in (e$attempts %||% list())) {
      art <- a$artifacts
      if (!is.character(art) || length(art) != 1L || is.na(art) || !nzchar(art)) next   # dict(WT 시기)·미측정 = 칸 산출물 아님
      nc <- nc + 1L
      d <- .rf_abs_path(art, root)
      j <- if (!is.na(d) && file.exists(file.path(d, "00_manifest.json"))) .rf_read_json(file.path(d, "00_manifest.json")) else NULL
      v <- if (is.null(j)) "" else .rf_s1(j$end_date)
      if (nzchar(v)) ends <- c(ends, v)
    }
    tb <- table(ends)
    data.frame(idx0 = k - 1L, base_id = .rf_s1(e$base_id), n_cells = nc, n_manifest = length(ends),
               n_end_dates = length(tb),
               end_dates = paste(sprintf("%s:%d", names(tb), as.integer(tb)), collapse = ";"),
               data_cutoff = .rf_s1(e$data_cutoff), stringsAsFactors = FALSE)
  })
  if (!length(rows)) return(data.frame(idx0 = integer(0), base_id = character(0), n_cells = integer(0),
                                       n_manifest = integer(0), n_end_dates = integer(0), end_dates = character(0),
                                       data_cutoff = character(0), stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

#' 강화 대상 등록 (충실구현/로테이션 라운드가 A 미달로 끝났을 때)
#' @param carry  승격 entry 전용 — 부모의 승자 구성(factors/weighting/universe).
#'   러너가 매 셀 스펙에 이것을 먼저 깔고 그 위에 격자 축을 얹는다.
#' @param parent 승격 계보(부모 base_id · 승자 셀 · 그 때 port_t · 깊이).
#' @param count_paper 논문 소비 카운터를 올릴지. ★승격은 새 논문이 아니다 — FALSE 로 부른다.
#'   (TRUE 로 두면 결합 검토 3편 주기가 승격 횟수만큼 앞당겨져 검토 대상이 헛돈다)
#' @param data_cutoff P0-07 — NULL = 직전 완결 월말(데이터에서 증명) · "YYYY-MM-DD" = 그 값(재현·검사). 위 절 계약 참조.
rf_open_entry <- function(layer, base_id, base_grade,
                          paper_key = "", paper_id = "",
                          base_artifacts = "", engine_path = "",
                          carry = NULL, parent = NULL, count_paper = TRUE,
                          root = .rf_root(), data_cutoff = NULL) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (!is.na(i)) {
    cat(sprintf("[reinforce_ledger] 기존 entry 재사용: %s (attempts %d)\n",
                base_id, obj$entries[[i]]$attempts_used))
    return(invisible(obj$entries[[i]]))
  }
  # ★P0-07 빈티지 — 원장 read-modify-write 창 밖에서 잰다(수 초). 부모 지문은 이 적재본에서 읽는다(개설 뒤 불변 필드).
  .pbid <- if (!is.null(parent)) .rf_s1(parent$base_id) else ""
  .pk <- if (nzchar(.pbid)) .rf_find(obj, .pbid) else NA_integer_
  vin <- .rf_entry_vintage(root, data_cutoff = data_cutoff,
                           parent_entry = if (!is.na(.pk)) obj$entries[[.pk]] else NULL,
                           has_parent = !is.null(parent), parent_base_id = .pbid, engine_path = engine_path)
  obj <- rf_load(layer, root)   # 재적재 — 계산 동안 다른 writer 가 쓴 것을 덮지 않게
  i <- .rf_find(obj, base_id)
  if (!is.na(i)) {
    cat(sprintf("[reinforce_ledger] 기존 entry 재사용(지문 계산 중 다른 경로가 개설): %s\n", base_id))
    return(invisible(obj$entries[[i]]))
  }
  entry <- list(
    base_id = base_id, base_grade = as.character(base_grade),
    paper_key = as.character(paper_key), paper_id = as.character(paper_id),
    base_artifacts = as.character(base_artifacts), engine_path = as.character(engine_path),
    status = "active", target_grade = "A",
    # ★측정 축 각인 (2026-09-01) — 새 entry 는 그 시점의 current_axis 를 달고 태어난다.
    #   이게 없으면 다음 축 전환 때 rf_mark_axis_epoch 이 "라벨 없음 = 구축" 으로 보고
    #   **신규분을 legacy 로 오분류**한다. 축은 비교 가능성의 경계이므로 태어날 때 정해야 한다.
    measurement_axis = obj$current_axis %||% "unlabeled", axis_valid = TRUE,
    attempts_used = 0L, attempts = list(),
    judge = list(spawned = FALSE, verdict_path = NULL),
    opened_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  if (!is.null(carry))  entry$carry  <- carry
  if (!is.null(parent)) entry$parent <- parent
  # ★P0-07 — 필드가 있으면 P0-07 이후 개설(data_cutoff null = 정하지 못함 · 사유는 data_fingerprint$why), 없으면 이전 entry.
  entry["data_cutoff"] <- list(vin$data_cutoff)
  entry$data_fingerprint <- vin$fp
  if (!is.null(parent)) entry$data_vintage_vs_parent <- vin$vs_parent
  obj$entries[[length(obj$entries) + 1L]] <- entry
  # 1계층: 논문 소비 카운터 +1 → 3편마다 결합 검토 플래그
  if (layer == 1L && isTRUE(count_paper)) {
    n <- as.integer(obj$combination_review$papers_since_last_review %||% 0L) + 1L
    obj$combination_review$papers_since_last_review <- n
    if (n >= 3L)
      cat("[reinforce_ledger] ★결합 검토 도래 — 논문 3편 소비. Q-Lead 는 논문 간 아이디어 결합 기회를 검토하고 rf_record_combination_review() 로 기록할 것 (착수 여부 무관 — 검토 자체가 의무)\n")
  }
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] L%d entry open: %s (base %s · data_cutoff %s · 지문 %s)\n", layer, base_id, base_grade,
              vin$data_cutoff %||% "NA", .rf_s1(vin$fp$status)))
  # 저널은 개설이 실제로 원장에 쓰인 뒤에만(개설 실패 경로의 로그 오인 방지)
  vs <- vin$vs_parent
  if (!is.null(parent) && is.list(vs)) {
    if (identical(vs$status, "mismatch"))
      .rf_ledger_jlog(root, "vintage_mismatch", base_id = base_id, parent = vs$parent_base_id,
                      reason = vs$reason, parent_cutoff = vs$parent_cutoff, child_cutoff = vs$child_cutoff,
                      parts = paste(vs$parts %||% character(0), collapse = ","),
                      years = paste(vs$years %||% integer(0), collapse = ","),
                      cols = paste(vs$cols %||% character(0), collapse = ","),
                      note = "부모 best_* 와 자식 칸은 다른 판본 위의 값이다 — 승격 비교는 같은 판본 재측정으로(P1)")
    else if (!identical(vs$status, "match"))
      .rf_ledger_jlog(root, "vintage_unverified", base_id = base_id, parent = vs$parent_base_id,
                      why = vs$why %||% "", note = "부모·자식 판본 대조 불가 — 일치로 간주하지 않는다")
  }
  if (identical(.rf_s1(vin$fp$status), "error"))
    .rf_ledger_jlog(root, "vintage_fingerprint_failed", base_id = base_id, err = .rf_s1(vin$fp$why))
  invisible(entry)
}

#' 강화 시도 1회 사전 등록 — ★여기가 횟수 게이트다 (1계층 — 값은 **원장 max_attempts** · 현행 30)
#' root_papers = list(list(url=..., claim=...), ...) — 선택. 비어도 거부하지 않고 evidence="none" 으로 기록한다.
rf_append_attempt <- function(layer, base_id, idea, keyword_axis, root_papers,
                              wt_id = NULL, root = .rf_root(),
                              unmapped_families = NULL,
                              axiom_injected = FALSE,
                              cell_code = NULL) {
  axes <- if (layer == 1L) RF_KEYWORD_AXES_L1 else RF_KEYWORD_AXES_L2
  if (!keyword_axis %in% axes)
    stop(sprintf("[reinforce_ledger] keyword_axis '%s' 는 L%d 축이 아님 (허용: %s)",
                 keyword_axis, layer, paste(axes, collapse = "/")))
  # ★근거 논문 의무 — 강화 레인에서 해제 (도훈 지시 2026-09-03 "강화에는 근거논문 필요없게 배선해").
  #   구판은 url(또는 risk_overlay 의 method)이 하나도 없으면 stop 으로 거부했다. 이제 거부하지 않는다.
  #   ★해제 범위는 이 함수(강화 전용)뿐이다 — 충실구현은 run_paper_replication 의 source_paper 를
  #     쓰는 별도 경로이고, 논문을 재현하는 단계에서 논문을 뺄 수는 없으므로 그대로 둔다.
  #   ★왜 바뀌었나: 계열→논문 표(.RFF_FAMILY_PAPER)가 8계열만 담아 선정 풀 332종 중 91종(27%)이
  #     미매핑이었다. 깊이 1 셀은 거부되고 깊이 2+ 는 **형제 계열의 논문**으로 통과했다 —
  #     게이트가 시험 중인 축을 덮지 않는 근거로 충족되는, 지키는 척만 하는 상태였다.
  #     축의 정당성은 이제 격자(reinforce_program.json)와 팩터 등록부가 진다.
  #   root_papers 는 **있으면 그대로 기록**한다(출처 추적은 유지). 없다고 막지만 않는다.
  .rp   <- root_papers %||% list()
  urls  <- vapply(.rp, function(x) as.character(x$url    %||% ""), character(1))
  meths <- vapply(.rp, function(x) as.character(x$method %||% ""), character(1))
  .ok_url    <- length(urls)  && any(nzchar(urls))
  .ok_method <- length(meths) && any(nzchar(meths))
  .evidence  <- if (.ok_url) "paper" else if (.ok_method) "method" else "none"
  if (identical(.evidence, "none"))
    cat("[reinforce_ledger] 근거 논문 없음 — 기록만 하고 진행 (강화 레인 근거 의무 해제, 2026-09-03)\n")

  # ★서술 의무 (2026-09-03 신설) — 근거 의무(root_papers)와 같은 층에 둔다.
  #   sprintf 는 인자 하나가 NULL/character(0) 이면 **경고 없이** character(0) 을 돌려준다.
  #   호출자가 그걸 그대로 넘기면 원장에 idea=[] 가 박히고, 그 시도는 등급만 있고
  #   무엇을 한 시도인지 영원히 알 수 없게 된다(실측 184/305 = 60%).
  #   원장 밖 강화가 없듯, 서술 없는 시도도 없다.
  .idea <- suppressWarnings(as.character(idea %||% character(0)))
  .idea <- .idea[!is.na(.idea) & nzchar(trimws(.idea))]
  if (!length(.idea))
    stop("[reinforce_ledger] idea 가 비었다 — 무엇을 시도하는지 적지 않은 강화는 거부한다. ",
         "sprintf 조립이면 조각 하나가 NULL/character(0) 일 수 있다(영길이 붕괴).")

  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s — rf_open_entry 먼저", base_id))
  e <- obj$entries[[i]]
  if (!identical(e$status, "active"))
    stop(sprintf("[reinforce_ledger] entry status=%s — active 아님", e$status))
  # ★횟수 상한 (1계층만 — 원장 max_attempts · 격자 칸 수에서 온다)
# ★entry 별 상한 (2026-09-04 도훈 지시). B1 이 설계에 따라 가변 길이가 되면서,
#   전역 25 를 그대로 두면 B1 이 쓴 만큼 뒤 블록이 잘린다 — 실측: B1 14칸 -> B4(결합)가
#   아예 못 돌았다. 각 블록 승자를 합치는 칸을 못 보면 그 entry 는 A 로 갈 길이 없다.
#   "칸 수 제한을 두지 마라" 를 B1 에만 적용하고 총예산에 안 적용한 비대칭을 닫는다.
  maxa <- e$max_attempts %||% obj$max_attempts
  if (!is.null(maxa) && e$attempts_used >= maxa) {
    e$status <- "exhausted"
    obj$entries[[i]] <- e
    .rf_write(obj, layer, root)
    stop(sprintf("[reinforce_ledger] ★%d회 소진 — entry %s status=exhausted. 새 논문으로 1계층 재개 (도훈 지시: 실패의 재생산 방지)", maxa, base_id))
  }
  # 같은 뿌리 논문 연속 3회 경고 (한 논문 매몰 금지 — 차단 아님)
  prev_urls <- unlist(lapply(tail(e$attempts, 2L), function(a)
    vapply(a$root_papers %||% list(), function(x) as.character(x$url %||% ""), character(1))))
  if (length(e$attempts) >= 2L && all(urls %in% prev_urls) && length(urls) > 0)
    cat("[reinforce_ledger] WARN: 같은 root_papers 3회 연속 — 한 논문 매몰 금지 (교차 논문 탐색 권장)\n")

  n <- e$attempts_used + 1L
  # ★격자 좌표를 **등록 시점에** 박는다 (2026-09-04). 구판은 cell_code 가 essence 안에만
  #   있어서, 측정 전에는 이 시도가 격자의 어느 칸인지 원장만 봐서는 알 수 없었다.
  #   그래서 러너 커서가 개수(attempts_used+1)로 움직였고, 등록이 한 건 거부되면
  #   격자 위치와 시도 수가 영구히 어긋났다(실측: B1_1 미측정 · B1_5 2회 소각 ·
  #   승자 스펙이 재실행분으로 덮여 20칸이 다른 기저 위에 섬). 좌표는 자리를 잡을 때 남긴다.
  .cell_code <- { .cc <- suppressWarnings(as.character(cell_code %||% character(0)))
                  .cc <- .cc[!is.na(.cc) & nzchar(trimws(.cc))]
                  if (length(.cc)) .cc[1] else NA_character_ }
  att <- list(n = n, date = format(Sys.Date(), "%Y%m%d"),
              cell_code = .cell_code,
              idea = .idea, keyword_axis = keyword_axis,
              root_papers = root_papers, wt_id = wt_id,
              # ★근거 종류 — paper(원문 url) / method(방법 명시) / none. 의무는 해제됐지만
              #   사후에 "이 시도가 무엇에 기대어 돌았는가" 는 계속 셀 수 있어야 한다.
              evidence = .evidence,
              # ★근거 공백 표식 — 이 시도의 팩터 계열 중 논문 매핑이 없는 것들.
              #   비어 있지 않다는 것은 "형제 계열 논문으로 게이트를 통과했다" 는 뜻이다.
              unmapped_families = as.character(unmapped_families %||% character(0)),
              # ★상수 TRUE 였다(2026-09-03 수리). axiom_context_inject 는 PreToolUse[Agent] 라
              #   무인 R 레인을 지나지 않는데 316 시도 전부 TRUE 로 적혀 있었다 — 거짓 기록이다.
              #   지금은 호출자가 **실제 적재 여부**를 넘긴다. 기본값 FALSE = 증명 못 하면 안 적는다.
              axiom_injected = isTRUE(axiom_injected),
              grade = NA, essence = NULL, artifacts = NULL, l_code = NULL,
              lessons = NULL, opened_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  e$attempts[[length(e$attempts) + 1L]] <- att
  e$attempts_used <- n
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cap_txt <- if (is.null(maxa)) "무한" else sprintf("%d/%d", n, maxa)
  cat(sprintf("[reinforce_ledger] L%d attempt %s 등록: %s [%s]\n", layer, cap_txt, base_id, keyword_axis))
  invisible(att)
}


#' 블록 순서 사전등록 (v10.2 2026-09-03 · C층)
#' ★한 번만 쓴다. 이미 있으면 거부한다 — 결과를 보고 순서를 고쳐 쓰면 사후 선택이다.
#' @param order  블록 id 벡터(격자 blocks 의 부분순열이 아니라 **전체 순열**이어야 한다)
#' @param reason 결정 근거 — 진단 수치를 그대로 담는다(사후에 규칙을 재구성할 수 있게)
#' entry 별 시도 상한 기록 (2026-09-04) — B1 설계가 기본 칸수보다 많이 쓰면 총예산을 늘린다.
#'   ★전역 max_attempts 는 건드리지 않는다. 다른 논문의 예산까지 같이 움직이면 그건
#'   "이 설계가 진 교환" 이 아니라 규율 완화가 된다.
rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root = .rf_root()) {
  stopifnot(is.numeric(max_attempts) || !is.na(suppressWarnings(as.integer(max_attempts))))
  if (!nzchar(as.character(reason %||% ""))) stop("[reinforce_ledger] entry 상한 변경은 사유 필수")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  obj$entries[[i]]$max_attempts <- as.integer(max_attempts)
  obj$entries[[i]]$max_attempts_reason <- as.character(reason)
  obj$entries[[i]]$max_attempts_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] entry 상한 %s -> %d (%s)\n", base_id,
              as.integer(max_attempts), substr(reason, 1, 60)))
  invisible(as.integer(max_attempts))
}

rf_record_block_order <- function(layer, base_id, order, reason, adaptive = FALSE,
                                  root = .rf_root()) {
  order <- as.character(order); order <- order[nzchar(order)]
  if (!length(order)) stop("[reinforce_ledger] block_order 가 비었다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  if (length(as.character(e$block_order %||% character(0))))
    stop("[reinforce_ledger] block_order 는 이미 기록됐다 — 덮어쓰기 금지(사후 선택 방지)")
  e$block_order        <- as.list(order)
  e$block_order_reason <- as.character(reason %||% "")
  e$block_order_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  # ★적응 탐색이면 표시한다 — 이 entry 의 탐색 경로가 측정에 의존했다는 사실이 남아야
  #   Judge 6축(selection 정직성)이 사후에 판정할 수 있다.
  e$search_adaptive    <- isTRUE(adaptive)
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] block_order 사전등록: %s [%s]%s\n",
              base_id, paste(order, collapse = ">"),
              if (isTRUE(adaptive)) " ★적응" else ""))
  invisible(order)
}

#' 시도 결과 기록 (QEPM 완주 후 — 등급·교훈·산출물)
#'
#' @param terminal 이 칸을 **더 이상 재시도하지 않는다**는 표식. 병렬 러너의 재개(resume)는
#'   essence 없는 칸을 무한히 다시 띄우는데, 그 설계는 *일시적* 실패(워커 미기동·시간초과)만
#'   상정했다. 구조적 실패 — 같은 스펙이면 몇 번을 돌려도 같은 자리에서 죽는 것 — 에는
#'   출구가 없어 루프가 제자리를 돈다(2026-08-31 실사고: B3_11 이 7.5시간 16회 동일 실패).
#'   terminal 은 "측정하지 못했다" 를 기록으로 **닫는다** — 성공으로 위장하지 않고(essence 는
#'   여전히 NULL), 재개 대상에서만 빠진다.
#' @param terminal_reason 왜 닫는가. 사유 없이 닫지 않는다.
#' @param graduate Grade A 를 적을 때 entry 를 graduated 로 바꿀지 (P0-12 · 2026-09-24 도훈 승인 플랜).
#'   ★왜: 구판은 A 를 적는 순간 entry 를 graduated 로 바꿨다. A 자격 관문(rf_a_eligibility)이 A 를 **보류**하는
#'   동안(등급 불변 · 발행만 미룸) 그 계보의 탐색이 멈춘다 — 러너는 graduated entry 를 다시 돌리지 않는다.
#'   FALSE 면 등급은 A 로 기록하되 entry status 는 그대로 두고(active 면 active — 다음 tick 이 칸을 계속 소비),
#'   attempt 에 graduate_deferred 표식만 남긴다. 보류가 풀리면 rf_graduate_entry() 로 졸업시킨다.
#'   기본 TRUE = 구판과 비트 동일. NA 등 TRUE 가 아닌 값은 보류로 읽는다(fail-closed — 모르면 졸업시키지 않는다).
rf_record_result <- function(layer, base_id, n, grade, essence = NULL,
                             artifacts = NULL, l_code = NULL, lessons = NULL,
                             terminal = FALSE, terminal_reason = NULL,
                             root = .rf_root(), graduate = TRUE) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  if (!length(j)) stop(sprintf("[reinforce_ledger] attempt n=%s 부재 (%s)", n, base_id))
  j <- j[1]
  e$attempts[[j]]$grade <- as.character(grade)
  e$attempts[[j]]$essence <- essence
  e$attempts[[j]]$artifacts <- artifacts
  e$attempts[[j]]$l_code <- l_code
  e$attempts[[j]]$lessons <- lessons
  e$attempts[[j]]$closed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  # 실패 횟수는 등급이 아니라 **재시도 예산**의 축이다 — 소비자(러너)가 상한을 건다.
  if (is.null(essence)) {
    e$attempts[[j]]$fail_count <- as.integer(e$attempts[[j]]$fail_count %||% 0L) + 1L
  }
  if (isTRUE(terminal)) {
    if (!nzchar(as.character(terminal_reason %||% "")))
      stop("[reinforce_ledger] terminal 은 사유 필수 — 왜 닫는지 없이 닫지 않는다")
    e$attempts[[j]]$terminal <- TRUE
    e$attempts[[j]]$terminal_reason <- as.character(terminal_reason)
  }
  if (identical(as.character(grade), "A")) {
    if (isTRUE(graduate)) {
      e$status <- "graduated"
      cat(sprintf("[reinforce_ledger] ★Grade A — %s graduated. Judge(PIT) 스폰 → PASS 시 BOOK 등록\n", base_id))
    } else {
      e$attempts[[j]]$graduate_deferred    <- TRUE
      e$attempts[[j]]$graduate_deferred_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
      cat(sprintf("[reinforce_ledger] Grade A 기록 · graduate=FALSE(A 자격 관문 보류) — %s status=%s 유지 · 해제 = rf_graduate_entry()\n",
                  base_id, as.character(e$status %||% "?")))
    }
  }
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  invisible(e$attempts[[j]])
}

#' 보류 A 의 졸업 (P0-12 짝 writer · 2026-09-24) — rf_record_result(graduate = FALSE) 로 적은 A 를 관문 해제 뒤 졸업시킨다.
#'   ★기록 등급이 A 인 시도만 · active/exhausted entry 만(parked 는 도훈 결정 · superseded 는 대체 — 둘 다 여기서 안 푼다).
#'   이미 graduated 면 멱등(쓰지 않는다). 사유 필수 — 어떤 보류가 무엇으로 풀렸는지 없이 졸업시키지 않는다.
rf_graduate_entry <- function(layer, base_id, n, reason, root = .rf_root()) {
  if (!nzchar(.rf_s1(reason)))
    stop("[reinforce_ledger] 졸업(보류 해제)은 사유 필수 — 어떤 관문이 무엇으로 풀렸는지 없이 졸업시키지 않는다", call. = FALSE)
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id), call. = FALSE)
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  if (!length(j)) stop(sprintf("[reinforce_ledger] attempt n=%s 부재 (%s)", n, base_id), call. = FALSE)
  j <- j[1]
  g <- .rf_s1(e$attempts[[j]]$grade)
  if (!identical(g, "A"))
    stop(sprintf("[reinforce_ledger] n=%s 의 기록 등급이 A 가 아니다(%s) — 졸업 불가", n, g), call. = FALSE)
  if (identical(e$status, "graduated")) {
    cat(sprintf("[reinforce_ledger] %s 이미 graduated — 쓰지 않는다\n", base_id))
    return(invisible(e))
  }
  if (!(.rf_s1(e$status) %in% c("active", "exhausted")))
    stop(sprintf("[reinforce_ledger] status=%s — active/exhausted 만 졸업시킨다", .rf_s1(e$status)), call. = FALSE)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  e$graduated_by <- list(n = as.integer(n), reason = as.character(reason), from_status = .rf_s1(e$status), at = now)
  e$status <- "graduated"
  e$attempts[[j]]$graduate_released_at <- now
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] ★%s graduated (n=%s · %s)\n", base_id, n, substr(as.character(reason), 1, 60)))
  invisible(e)
}

#' 닫힌 칸을 되살린다 — **원인이 제거됐을 때만** (2026-09-07)
#'
#' ★왜 필요한가: `terminal` 은 켜는 어휘만 있고 끄는 어휘가 없었다. 그 설계는 "닫는 이유는
#'   구조적 실패(같은 스펙이면 같은 자리에서 죽는다)" 를 상정했는데, 실제로 닫힌 칸의 상당수는
#'   **일시 실패의 상한 도달**이었고 그 원인이 나중에 하네스 수리로 제거된다. 2026-09-07 실사고:
#'   qepm:CDaR_LP 칸이 세 entry 연속 워커 90분 초과로 terminal — 원인은 arm 이 아니라 솔버였고
#'   (cccp 밀집 IPM ~T³ · 월 30초 × 260회 = 130분), lpSolve 사슬로 고치자 0.1초가 됐다. 원인이
#'   사라졌는데도 그 칸은 영영 미측정으로 남는다 — 미측정 칸은 절약이 아니라 헌법 위반이다.
#' ★남용 방지: 사유(무엇이 원인이었고 무엇으로 제거됐나)를 필수로 받고, 되살린 이력을
#'   `reopened` 에 누적한다(지운 기록 없음). essence 가 이미 있는 칸은 되살리지 않는다 —
#'   그건 재측정 요청이지 미측정 복구가 아니다(측정된 값을 덮는 경로는 이 함수가 아니다).
#' @param reason 원인 제거 서술. 없이 되살리지 않는다(terminal 이 사유를 요구하는 것과 대칭).
rf_reopen_attempt <- function(layer, base_id, n, reason, root = .rf_root()) {
  if (!nzchar(as.character(reason %||% "")))
    stop("[reinforce_ledger] reopen 은 사유 필수 — 무엇이 원인이었고 무엇으로 제거됐는지 없이 되살리지 않는다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  if (!length(j)) stop(sprintf("[reinforce_ledger] attempt n=%s 부재 (%s)", n, base_id))
  j <- j[1]
  a <- e$attempts[[j]]
  if (!is.null(a$essence) && !is.null(a$essence$port_t))
    stop(sprintf("[reinforce_ledger] n=%s 는 이미 측정됐다(port_t=%s) — reopen 대상 아님", n, a$essence$port_t))
  a$reopened <- c(as.list(a$reopened %||% list()),
                  list(list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                            reason = as.character(reason),
                            was_terminal = isTRUE(a$terminal),
                            was_fail_count = as.integer(a$fail_count %||% 0L),
                            prev_terminal_reason = as.character(a$terminal_reason %||% ""))))
  a$terminal <- FALSE          # 재개 대상으로 되돌린다 (러너 pending = essence 없음 ∧ !terminal)
  a$terminal_reason <- NULL
  a$fail_count <- 0L           # 재시도 예산도 함께 되돌린다 — 원인이 다르면 상한도 새로 센다
  e$attempts[[j]] <- a
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] reopen n=%s (%s) — %s\n", n, e$attempts[[j]]$cell_code %||% "?", reason))
  invisible(e$attempts[[j]])
}

#' 조기 중단(파킹) — 상한 소진 전에 도훈 결정으로 논문을 접을 때
#'
#' ★왜 필요한가: status enum 은 active / exhausted(25회 소진) / graduated(Grade A) 뿐이라
#' "25회를 다 쓰지 않았지만 도훈이 접기로 했다" 를 표현할 어휘가 없었다. active 로 남기면
#' v10 /qvest 규칙("원장 L1 active 우선")이 다음 세션에서 그 논문을 **자동 재개**해 결정과
#' 어긋난다(boot_lean.sh:56 이 status=="active" 만 센다). parked 는 재개 가능한 중단이다 —
#' 되돌리려면 status 를 active 로 명시적으로 되돌려야 하고, 그 사이 rf_append_attempt 의
#' active 검사(line ~142)가 새 시도를 막는다.
#' 측정 축 전환 기록 — 과거 entry 를 **무효 표시**하고 새 축의 시작을 남긴다
#'
#' 왜 필요한가 (2026-09-01 실사고): 강화 셀이 전부 **3종목 포트폴리오**를 재고 있었다.
#'   고정 축은 25인데 ① 엔진이 이미 상위 25를 잘라 FACTORS 를 내보내고
#'   ② run_paper_replication 의 top_n_long 이 그 25를 다시 분위(10%)로 잘랐다.
#'   거들던 것은 키 불일치 — 셀 실행 경로가 `n =` 을 넘기는데 러너는 spec$n_max/$n_long 을
#'   읽어서 **격자의 n_max 가 한 번도 전달된 적이 없었다**.
#'   축이 바뀌면 과거 측정은 "틀린 값" 이 아니라 **다른 축에서 잰 값**이다. 지우지 않고
#'   표시한다 — 비교만 막고 기록은 남긴다(사후 재현·귀속이 살아 있어야 한다).
#'
#' @param epoch  새 축 이름(예: "n_max_25")
#' @param legacy 과거 축 이름(예: "legacy_double_selection")
#' @param reason 왜 축이 바뀌었나 (필수)
#' @param evidence 실측 근거 1줄 (필수 — 진술만으로 무효화하지 않는다)
#' 25칸 소진 — status=exhausted (2026-09-05 · 퇴역 러너의 인라인 루틴을 writer 로 승격)
#'   실사고: 러너 단일화(09-05)로 병렬 러너의 소진 위임부가 퇴역된 reinforce_auto_run.R 을 부르고 있었고,
#'   그 파일은 안내문만 찍고 종료해 promo2 소진 → 승격이 조용히 실패했다(exhaust_reached 이벤트 0건).
#'   park 아님 — park 은 도훈 조기중단 전용. 이미 exhausted 면 멱등.
rf_exhaust_entry <- function(layer, base_id, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  if (!identical(obj$entries[[i]]$status, "exhausted")) {
    obj$entries[[i]]$status <- "exhausted"
    obj$entries[[i]]$exhausted_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    .rf_write(obj, layer, root)
  }
  invisible(obj$entries[[i]])
}

#' 측정 축 전환 (current_axis 교체) — ★P0-06 수리판 (2026-09-24 · 도훈 승인 플랜 qvest-1-drifting-eclipse)
#'
#' ★무발화 결함(수리 전): 구판은 measurement_axis 가 NULL 인 entry 만 표시했다. 그런데 rf_open_entry 가 09-01 부터
#'   entry 를 태어날 때 current_axis 로 각인하므로 현 원장에서 표시 대상이 **0건**이었다(원장 사본 재도출 ·
#'   test_rf_rebase.R C1). 부르면 "전환했다" 는 axis_epochs 기록만 남고 과거 칸은 새 축과 계속 비교됐다.
#' 수리:
#'   · relabel_from = 이 축 이름을 가진 entry 를 전환 대상으로 삼는다(보통 현 current_axis).
#'   · require_regime = 새 축에 남을 자격(측정 규약 regime 집합). 대상 entry 의 **측정된 모든 칸**(기저 포함)의 regime 이
#'     이 집합 안이면 epoch 로 승계(axis_valid 유지), 하나라도 밖이면 legacy 로 표시(axis_valid=FALSE — 비교에서 뺀다).
#'     regime 은 원장 표식(rebase) → 산출물 auth 의 measurement_regime 순으로 재도출한다(rf_attempt_regime).
#'     C11 등 PIT 표식 칸(rebase 비편입)은 자격 판정에서 빼되, 어느 칸이 구 규약으로 남았는지 axis_blocked_legacy 에 적는다
#'     (소비자 필터 몫 — 조용한 혼입 아님). 측정 칸이 전부 표식 칸이면 legacy 다(표식 칸만으로 새 축에 서지 않는다).
#'     NULL 이면 relabel_from 대상 전부 legacy(순수 무효 표시).
#'   · measurement_axis 가 NULL 인 entry 는 구판 규칙 그대로 legacy.
#'   · relabel_from 이 한 건도 안 맞으면 멈춘다(allow_empty=TRUE 로만 통과) — 무발화를 다시 조용히 통과시키지 않는다.
#'   · 현 current_axis 가 relabel_from 밖이면 멈춘다 — 그 축으로 태어난 신규 entry 가 비교 불가 축에 남는다.
#'   · 원자: 러너 claim(idle 에서만 · 같은 프로세스가 이미 쥐었으면 그대로 사용) · CAS · 보호 투영(축 필드·axis_epochs·
#'     current_axis 밖 불변) · axis_epochs append-only · 사후 재적재 대조 → 어긋나면 원본 바이트 복원. dry_run 은 쓰지 않고 계획만.
#' @return list(n_marked(legacy 로 표시), n_carried(epoch 로 승계), n_matched, written, plan, md5_before, md5_after)
rf_mark_axis_epoch <- function(layer, epoch, legacy, reason, evidence, root = .rf_root(),
                               relabel_from = NULL, require_regime = NULL, allow_empty = FALSE,
                               claim = NULL, wait_s = RF_LEDGER_CLAIM_WAIT_S, poll_s = RF_LEDGER_CLAIM_POLL_S,
                               dry_run = FALSE, .pre_write_hook = NULL) {
  for (.a in list(epoch, legacy, reason, evidence))
    if (!nzchar(.rf_s1(.a)))
      stop("[reinforce_ledger] 축 전환은 epoch/legacy/reason/evidence 전부 필수 — 근거 없이 무효화하지 않는다", call. = FALSE)
  epoch <- .rf_s1(epoch); legacy <- .rf_s1(legacy)
  if (identical(epoch, legacy)) stop("[reinforce_ledger] 축 전환 — epoch 와 legacy 가 같다", call. = FALSE)
  rf_from <- unique(as.character(unlist(relabel_from %||% character(0)))); rf_from <- rf_from[!is.na(rf_from) & nzchar(rf_from)]
  acc <- unique(as.character(unlist(require_regime %||% character(0)))); acc <- acc[!is.na(acc) & nzchar(acc)]
  if (length(acc) && !length(rf_from))
    stop("[reinforce_ledger] 축 전환 — require_regime 은 relabel_from 과 함께만 쓴다", call. = FALSE)
  if (epoch %in% rf_from) stop("[reinforce_ledger] 축 전환 — epoch 가 relabel_from 안에 있다", call. = FALSE)
  blocked <- if (length(acc)) rf_rebase_block_flags(root) else character(0)

  .plan <- function(obj) {
    if (length(rf_from) && !is.null(obj$current_axis) && !(.rf_s1(obj$current_axis) %in% rf_from))
      stop(sprintf("[reinforce_ledger] 축 전환 — 현 current_axis(%s) 가 relabel_from(%s) 밖이다: 그 축으로 태어난 entry 가 비교 불가 축에 남는다",
                   .rf_s1(obj$current_axis), paste(rf_from, collapse = ",")), call. = FALSE)
    if (identical(.rf_s1(obj$current_axis), epoch))
      stop(sprintf("[reinforce_ledger] 축 전환 — 이미 current_axis=%s", epoch), call. = FALSE)
    lapply(seq_along(obj$entries), function(i) {
      e <- obj$entries[[i]]; ax <- e$measurement_axis
      if (is.null(ax)) return(list(i = i, base_id = .rf_s1(e$base_id), from = NA_character_, to = "legacy", why = "unlabeled"))
      ax <- .rf_s1(ax)
      if (!(ax %in% rf_from)) return(list(i = i, base_id = .rf_s1(e$base_id), from = ax, to = "keep", why = "other_axis"))
      if (!length(acc)) return(list(i = i, base_id = .rf_s1(e$base_id), from = ax, to = "legacy", why = "relabel_from"))
      st <- .rf_entry_regime_status(e, acc, blocked, root)
      list(i = i, base_id = .rf_s1(e$base_id), from = ax, to = st$verdict, why = st$why,
           off = st$off, blocked = st$blocked, n_on = st$n_on, n_measured = st$n_measured)
    })
  }
  .apply <- function(obj, P, now) {
    for (x in P) {
      if (identical(x$to, "keep")) next
      e <- obj$entries[[x$i]]
      hist <- list(at = now, to = if (identical(x$to, "epoch")) epoch else legacy, why = x$why, epoch_switch = epoch)
      if (!is.na(x$from)) hist$from <- x$from
      if (identical(x$to, "epoch")) {
        e$measurement_axis <- epoch; e$axis_valid <- TRUE
        if (length(x$blocked)) e$axis_blocked_legacy <- as.list(as.character(x$blocked))
      } else {
        e$measurement_axis <- legacy; e$axis_valid <- FALSE; e$axis_marked_at <- now
        if (length(x$off)) hist$off_regime <- as.list(as.character(x$off))
      }
      e$axis_history <- c(if (is.list(e$axis_history)) e$axis_history else list(), list(hist))
      obj$entries[[x$i]] <- e
    }
    obj
  }

  if (isTRUE(dry_run)) {
    P <- .plan(rf_load(layer, root))
    n_m <- sum(vapply(P, function(x) identical(x$to, "legacy"), logical(1)))
    n_c <- sum(vapply(P, function(x) identical(x$to, "epoch"), logical(1)))
    return(invisible(list(n_marked = n_m, n_carried = n_c, n_matched = sum(vapply(P, function(x) !identical(x$to, "keep"), logical(1))),
                          written = FALSE, plan = P, md5_before = NA_character_, md5_after = NA_character_)))
  }
  hold <- .rf_ledger_claim(root, claim, wait_s, poll_s, "축 전환")
  on.exit(hold$release(), add = TRUE)
  p <- .rf_path(layer, root)
  if (!file.exists(p)) stop("[reinforce_ledger] 축 전환 — 원장 부재: ", p, call. = FALSE)
  md5_a <- unname(tools::md5sum(p)); raw_a <- readBin(p, "raw", file.info(p)$size)
  orig <- rf_load(layer, root)
  P <- .plan(orig)
  n_matched <- sum(vapply(P, function(x) !identical(x$to, "keep"), logical(1)))
  n_rf <- sum(vapply(P, function(x) !is.na(x$from) && x$from %in% rf_from, logical(1)))
  if (length(rf_from) && n_rf == 0L && !isTRUE(allow_empty))
    stop(sprintf("[reinforce_ledger] 축 전환 — relabel_from(%s) 과 맞는 entry 0건: 무발화 전환 거부(allow_empty=TRUE 로만)",
                 paste(rf_from, collapse = ",")), call. = FALSE)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  obj <- .apply(orig, P, now)
  n_marked  <- sum(vapply(P, function(x) identical(x$to, "legacy"), logical(1)))
  n_carried <- sum(vapply(P, function(x) identical(x$to, "epoch"), logical(1)))
  # 구판 호출형(relabel_from 없음)이 0건을 표시하면 그것이 바로 수리 전 무발화다 — 기록만 남기고 넘어가지 않는다
  if (!length(rf_from) && (n_marked + n_carried) == 0L && !isTRUE(allow_empty))
    stop("[reinforce_ledger] 축 전환 — relabel_from 없이 표시 대상 0건(모든 entry 가 이미 축 라벨을 가진다): 무발화 전환 거부. relabel_from 을 주거나 allow_empty=TRUE",
         call. = FALSE)
  obj$axis_epochs <- c(if (is.list(orig$axis_epochs)) orig$axis_epochs else list(), list(list(
    epoch = epoch, legacy = legacy, switched_at = now,
    reason = reason, evidence = evidence, entries_marked = n_marked, entries_carried = n_carried,
    relabel_from = as.list(rf_from), require_regime = as.list(acc), from_axis = .rf_s1(orig$current_axis),
    note = paste0("이 시점 이후 개설되는 entry 는 measurement_axis='", epoch,
                  "' 로 태어난다. 축이 다른 entry 끼리는 등급·PORT_t 를 비교하지 않는다."))))
  obj$current_axis <- epoch
  .ep_ok <- function(x) { eo <- orig$axis_epochs
    if (!is.list(eo) || !length(eo)) TRUE else identical(x$axis_epochs[seq_along(eo)], eo) }
  if (!identical(.rf_axis_strip(obj), .rf_axis_strip(orig)) || !.ep_ok(obj))
    stop("[reinforce_ledger] 축 전환 — 축 필드 밖이 바뀌었다(보호 투영 불일치) — 쓰지 않는다", call. = FALSE)
  .rt <- fromJSON(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), simplifyVector = FALSE)
  if (!identical(.rf_axis_strip(.rt), .rf_axis_strip(orig)))
    stop("[reinforce_ledger] 축 전환 — 직렬화 왕복이 축 필드 밖 값을 바꾼다 — 쓰지 않는다", call. = FALSE)
  if (is.function(.pre_write_hook)) .pre_write_hook(p)
  if (!identical(unname(tools::md5sum(p)), md5_a))
    stop("[reinforce_ledger] 축 전환 — 적재 뒤 원장이 바뀌었다(claim 밖 쓰기) — 덮어쓰지 않는다", call. = FALSE)
  .rf_write(obj, layer, root)
  back <- tryCatch(rf_load(layer, root), error = function(e) NULL)
  .nl <- function(x) { x$last_updated <- NULL; x }
  if (is.null(back) || !identical(.nl(back), .nl(.rt))) {
    .rf_restore_bytes(p, raw_a, "axis")
    stop("[reinforce_ledger] 축 전환 — 사후 재적재 대조 실패, 원본 바이트로 되돌렸다", call. = FALSE)
  }
  cat(sprintf("[reinforce_ledger] 축 전환 %s -> %s · legacy 표시 %d건 · 승계 %d건 (relabel_from=%s · regime=%s)\n",
              .rf_s1(orig$current_axis %||% "∅"), epoch, n_marked, n_carried,
              if (length(rf_from)) paste(rf_from, collapse = ",") else "∅(NULL 만)",
              if (length(acc)) paste(acc, collapse = ",") else "∅"))
  invisible(list(n_marked = n_marked, n_carried = n_carried, n_matched = n_matched, written = TRUE, plan = P,
                 md5_before = md5_a, md5_after = unname(tools::md5sum(p))))
}

rf_park_entry <- function(layer, base_id, reason, root = .rf_root()) {
  if (!nzchar(as.character(reason %||% "")))
    stop("[reinforce_ledger] parked 는 사유 필수 — 왜 접었는지 없이 접지 않는다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  if (!identical(e$status, "active"))
    stop(sprintf("[reinforce_ledger] entry status=%s — active 만 park 할 수 있다", e$status))
  e$status        <- "parked"
  e$parked_reason <- as.character(reason)
  e$parked_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  e$parked_at_attempt <- as.integer(e$attempts_used %||% 0L)
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] entry %s parked (시도 %d/%s 소진) — %s
",
              base_id, as.integer(e$attempts_used %||% 0L),
              as.character(obj$max_attempts %||% "inf"), reason))
  invisible(e)
}

#' Judge verdict 기록
rf_record_judge <- function(layer, base_id, verdict_path, pit_pass, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  obj$entries[[i]]$judge <- list(spawned = TRUE, verdict_path = as.character(verdict_path),
                                 pit_pass = isTRUE(pit_pass),
                                 judged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (!isTRUE(pit_pass)) {
    obj$entries[[i]]$status <- "active"   # PIT FAIL → 결과 무효, 수리·재측정 (등급 재산출)
    cat("[reinforce_ledger] PIT FAIL — 등급 무효, entry 재활성화 (수리 후 재측정)\n")
  }
  .rf_write(obj, layer, root)
  invisible(obj$entries[[i]])
}

#' 결합 검토 기록 (1계층 — 논문 3편마다 의무. 착수 여부와 무관하게 검토 자체를 기록)
rf_record_combination_review <- function(reviewed_papers, verdict, note = "",
                                         combined_entry_base_id = NULL, root = .rf_root()) {
  obj <- rf_load(1L, root)
  h <- obj$combination_review$history %||% list()
  h[[length(h) + 1L]] <- list(
    date = format(Sys.Date(), "%Y-%m-%d"),
    reviewed_papers = reviewed_papers,
    verdict = as.character(verdict),   # "combined" | "no_combination" (+사유)
    note = as.character(note),
    combined_entry_base_id = combined_entry_base_id)
  obj$combination_review$history <- h
  obj$combination_review$papers_since_last_review <- 0L
  obj$combination_review$last_review_date <- format(Sys.Date(), "%Y-%m-%d")
  .rf_write(obj, 1L, root)
  cat(sprintf("[reinforce_ledger] 결합 검토 기록 (%s) — 카운터 리셋\n", verdict))
  invisible(h[[length(h)]])
}

#' 착수 시 교훈 주입용 — 해당 entry 의 직전 attempts 요약 (2계층 무한 모드의 "지속 주입")
rf_lessons_digest <- function(layer, base_id, n_last = 5L, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) return(character(0))
  atts <- tail(obj$entries[[i]]$attempts, n_last)
  vapply(atts, function(a) sprintf("n%s [%s] %s → %s%s",
                                   a$n, a$keyword_axis,
                                   substr(as.character(a$idea), 1, 60),
                                   a$grade %||% "미측정",
                                   if (!is.null(a$lessons)) paste0(" | ", paste(unlist(a$lessons), collapse = "; ")) else ""),
         character(1))
}

#' 결정 기록 (리서치 디렉터 · 2026-09-21 도훈 승인 플랜 Part 3 · D1) — 06_Registry/rf_decisions.jsonl 에 **한 줄 append**
#'
#' ★왜 필요한가: 루프의 37개 결정 중 대안을 남기는 것은 6개뿐이다(반증·설계 기각·arm 수락·carry 탈락·결합 후보·reopen).
#'   순위 결정(배치·승자·바닥·승격·논문·결합)과 디렉터의 방향 결정은 이긴 선택만 남아 "다른 규칙이었으면" 을 되돌려
#'   볼 수 없었다. 이 writer 는 결정 시점의 **후보 집합 + 순위 + 기각 사유 + 선택** 을 남긴다.
#' ★홈이 원장이 아니라 형제 jsonl 인 이유: 원장은 전량 read-modify-write 라 연 ~10k 레코드가 매 tick 파싱을 느리게 한다.
#'   소비자는 주간 리플레이·검사·디렉터뿐 — **러너 판정은 이 파일을 읽지 않는다**(선례 overlay_arm_ledger.jsonl).
#' ★경계(AX-008): 후보/선택에 `essence`·`essence_grade`·`authoritative_remeasure` 키가 있으면 거부한다 —
#'   결정 기록은 등급을 주장하는 자리가 아니다(등급 값을 피처로 옮기는 것은 허용, 등급 객체를 싣는 것은 금지).
#' @param kind       RF_DECISION_KINDS 중 하나
#' @param candidates list(list(id=, rank=, features=list(), reason=), ...) — rank 1 = 선택. 상한 초과분은 잘리고 n_candidates_total 만 남는다
#' @param chosen     character(ids) 또는 list(ids=, units=, ...) — ids ⊆ candidates$id 여야 한다("none" 은 후보에 없어도 허용)
#' @param rule       list(src=, sha=, knobs=list(...)) 또는 문자열 — 결정을 낸 규칙과 그 출처
#' @param policy     list(policy_id=, policy_sha=, mode=) — 부재 = pi0/live
#' @param shadow     list(policy_id=, choice=, agrees=) — 그림자 정책 판정(D4+) · 부재 = NULL
RF_DECISION_KINDS <- c("direction", "batch", "block_order", "b1_factor_pick", "b5_overlay_pick", "b2_weight_pick",
                       "block_winner", "floor", "budget", "promote", "combination", "b1_design_verify", "base_gate",
                       # ★P0-12(2026-09-24) A 자격 관문 판정(보류 사유 코드 · 발행/보류) · P2-01 사전등록 판정
                       #   (confirmed/powered_null/undetermined/failed) — 미등재 kind 는 위에서 stop 하므로 호출 전에 있어야 한다.
                       "a_eligibility", "prereg_verdict")
rf_decisions_path <- function(root = .rf_root()) file.path(root, "06_Registry/rf_decisions.jsonl")
rf_record_decision <- function(kind, base_id, candidates, chosen, rule, policy = NULL, scope = list(), shadow = NULL,
                               root = .rf_root(), max_candidates = 40L, layer = 1L) {
  if (!is.character(kind) || length(kind) != 1L || !(kind %in% RF_DECISION_KINDS))
    stop(sprintf("[reinforce_ledger] decision kind 미등재: %s", paste(kind, collapse = ",")))
  if (!is.list(candidates)) stop("[reinforce_ledger] candidates 는 list(list(id=...)) 여야 한다")
  ids <- vapply(candidates, function(c) as.character((c %||% list())$id %||% ""), character(1))
  if (length(candidates) && any(!nzchar(ids))) stop("[reinforce_ledger] 후보마다 id 가 있어야 한다")
  .forbid <- c("essence", "essence_grade", "authoritative_remeasure")
  .has_forbidden <- function(x) {
    if (!is.list(x)) return(FALSE)
    if (any(names(x) %in% .forbid)) return(TRUE)
    any(vapply(x, .has_forbidden, logical(1)))
  }
  if (.has_forbidden(candidates) || .has_forbidden(if (is.list(chosen)) chosen else list()))
    stop("[reinforce_ledger] 결정 기록에 essence/등급 객체를 싣지 않는다(AX-008 경계)")
  ch <- if (is.character(chosen)) list(ids = as.list(chosen)) else if (is.list(chosen)) chosen else stop("[reinforce_ledger] chosen 형식")
  ch_ids <- as.character(unlist(ch$ids %||% list()))
  bad <- setdiff(ch_ids, c(ids, "none"))
  if (length(bad)) stop(sprintf("[reinforce_ledger] chosen ⊄ candidates: %s", paste(bad, collapse = ",")))
  n_total <- length(candidates)
  if (n_total > max_candidates) candidates <- candidates[seq_len(max_candidates)]
  rec <- list(schema = "rf_decision_v1",
              decision_id = sprintf("%s_%s_%s", kind, substr(as.character(base_id %||% "program"), 1L, 24L), format(Sys.time(), "%Y%m%dT%H%M%S")),
              kind = kind, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), layer = as.integer(layer),
              scope = c(list(base_id = as.character(base_id %||% "program")), scope),
              policy = policy %||% list(policy_id = "pi0", policy_sha = "", mode = "live"),
              rule = if (is.character(rule)) list(src = rule) else rule,
              candidates = candidates, chosen = ch, n_candidates_total = n_total, shadow = shadow)
  p <- rf_decisions_path(root)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  txt <- toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = 6)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || !identical(chk$kind, kind)) stop("[reinforce_ledger] 결정 레코드 재파싱 실패 — 쓰지 않는다")
  cat(txt, "\n", sep = "", file = p, append = TRUE)
  invisible(rec)
}
#' 결정 기록 읽기 — kind·날짜 접두 필터 (파싱 실패 줄은 건너뛴다)
rf_read_decisions <- function(root = .rf_root(), kind = NULL, day_prefix = NULL) {
  p <- rf_decisions_path(root); if (!file.exists(p)) return(list())
  L <- readLines(p, warn = FALSE, encoding = "UTF-8"); out <- list()
  for (l in L) { if (!nzchar(trimws(l))) next
    r <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL); if (is.null(r)) next
    if (!is.null(kind) && !identical(r$kind, kind)) next
    if (!is.null(day_prefix) && !startsWith(as.character(r$at %||% ""), day_prefix)) next
    out[[length(out) + 1L]] <- r }
  out
}

#' 오버레이 적대 반증 기록 (G2 · 2026-09-17) — attempts[[j]]$adversary 만 쓴다
#'
#' ★왜 필요한가: B5 칸이 바닥보다 Calmar 를 올렸다는 사실만으로 블록 승자·승격 carry·Grade A 후보로
#'   소비됐다. 반증(lag-1 · strict-PIT · 노출 짝지은 placebo · 정적 등가)을 거친 칸만 소비하려면
#'   그 판정이 **원장 attempt 안**에 있어야 소비자(.winner_of · rf_promote · grade_a 큐)가 읽는다.
#' ★경계(AX-008): essence·grade 는 건드리지 않는다 — 이 writer 는 `adversary` 필드 하나만 세운다.
#'   verdict ∈ pass / fail / error / not_candidate. pass 가 아니면 소비 보류이지 등급 변경이 아니다.
#' ★쓰기 직전 재적재(read-modify-write 최소 창) + .rf_write 원자 쓰기. attempt 부재는 거부한다.
#'   직전 기록이 있으면 verdict·at 만 history 로 누적한다(덮어써도 이력은 남는다).
#' @param adversary rf_overlay_adversary.R 이 만든 레코드(list · schema rf_overlay_adversary_v1)
rf_record_adversary <- function(layer, base_id, n, adversary, root = .rf_root()) {
  if (!is.list(adversary) || !nzchar(as.character(adversary$verdict %||% "")))
    stop("[reinforce_ledger] adversary 레코드에 verdict 가 없다 — 판정 없는 표식은 쓰지 않는다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  if (!length(j)) stop(sprintf("[reinforce_ledger] attempt n=%s 부재 (%s)", n, base_id))
  j <- j[1]
  prev <- e$attempts[[j]]$adversary
  hist <- if (is.list(prev)) c(prev$history %||% list(),
                               list(list(at = as.character(prev$at %||% ""), verdict = as.character(prev$verdict %||% ""))))
          else list()
  adversary$history <- hist
  adversary$recorded_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  e$attempts[[j]]$adversary <- adversary
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] adversary n=%s (%s) → %s%s\n", n, e$attempts[[j]]$cell_code %||% "?",
              as.character(adversary$verdict), if (length(hist)) sprintf(" (이력 %d)", length(hist)) else ""))
  invisible(e$attempts[[j]])
}

#' B5 재설계 라운드 표식 (WP-R · 2026-09-17 · B5 설계 레인 계약) — entry$b5_redesign 필드만 **병합**한다
#'
#' 계약 필드: active(logical) · round(integer · 2 = 첫 재설계) · at · cells_added · base_design_cells.
#'   레인(rf_b5_design)이 연다(active=TRUE · 새 칸을 설계 뒤에 덧붙인다 — 코드 안정) · 러너가 B5 경계(재설계 배치 완료 +
#'   적대검증)에서 닫는다(active=FALSE · closed_at · closed_by). 러너는 active·cells_added·base_design_cells 만 읽는다
#'   (rf_runner_gates.R::rf_b5_redesign_active / rf_b5_design_counts).
#' ★경계(AX-008): 등급·시도·carry 는 건드리지 않는다 — 이 writer 는 b5_redesign 하나만 세운다. 부재 필드는 그대로 둔다.
rf_record_b5_redesign <- function(layer, base_id, fields, root = .rf_root()) {
  if (!is.list(fields) || !length(fields) || is.null(names(fields)) || any(!nzchar(names(fields))))
    stop("[reinforce_ledger] b5_redesign 은 이름 있는 필드 목록이 필요하다(active/round/at/cells_added/base_design_cells)")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  cur <- obj$entries[[i]]$b5_redesign
  if (!is.list(cur)) cur <- list()
  for (k in names(fields)) cur[[k]] <- fields[[k]]
  cur$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  obj$entries[[i]]$b5_redesign <- cur
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] b5_redesign %s: active=%s round=%s cells_added=%s\n", base_id,
              as.character(cur$active %||% NA), as.character(cur$round %||% NA), as.character(cur$cells_added %||% NA)))
  invisible(cur)
}

#' B5 설계 레인 **라운드 기록** (WP-C · 2026-09-17 도훈 지시 "매 강화 사이클마다 LLM 이 오버레이를 자체 설계") — entry$b5_design$rounds 에 누적
#'
#' 계약 레코드: {round, at, source:"b5_design_lane", n_cells, new_arms_admitted, new_arms_rejected, compose_only, fallback}
#'   + 레인이 덧붙이는 필드(new_arm_ids · fallback_reason · n_total_cells · design_path — 가드 H3 정체 판정과 사후 대조용).
#'   round 1 = entry 당 자동 설계(가드 H1 이 이 기록으로 "이미 설계됨" 을 센다) · round ≥ 2 = 수동 재설계.
#'   fields$redesign = list(cells_added, base_design_cells) 가 있으면 rf_record_b5_redesign 으로 **같은 원장 안의**
#'   b5_redesign 표식(active=TRUE)을 함께 연다 — 러너 계약(rf_runner_gates.R::rf_b5_design_counts)이 그것을 읽는다.
#' ★경계(AX-008): 등급·시도·carry 는 건드리지 않는다. 폴백 라운드(fallback=TRUE)도 기록한다 — 시도한 설계는 숨기지 않는다
#'   (환경 실패(auth·한도)는 라운드가 아니라 레인 이벤트로만 남는다 — 그때는 재시도가 정당하다).
rf_record_b5_design <- function(layer, base_id, fields, root = .rf_root()) {
  if (!is.list(fields) || is.null(fields$round))
    stop("[reinforce_ledger] b5_design 라운드 기록은 round 필수")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  rec <- list(round = as.integer(fields$round), at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = "b5_design_lane",
              n_cells = as.integer(fields$n_cells %||% 0L),
              new_arms_admitted = as.integer(fields$new_arms_admitted %||% 0L),
              new_arms_rejected = as.integer(fields$new_arms_rejected %||% 0L),
              compose_only = isTRUE(fields$compose_only), fallback = isTRUE(fields$fallback))
  extra <- fields[setdiff(names(fields), c(names(rec), "redesign"))]
  for (k in names(extra)) rec[[k]] <- extra[[k]]
  bd <- e$b5_design; if (!is.list(bd)) bd <- list()
  bd$rounds <- c(if (is.list(bd$rounds)) bd$rounds else list(), list(rec))
  e$b5_design <- bd
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] b5_design 라운드 %d 기록 %s: cells=%d arms +%d/-%d compose_only=%s fallback=%s\n",
              rec$round, base_id, rec$n_cells, rec$new_arms_admitted, rec$new_arms_rejected, rec$compose_only, rec$fallback))
  if (is.list(fields$redesign))
    rf_record_b5_redesign(layer, base_id, list(active = TRUE, round = rec$round, at = rec$at,
                                               cells_added = as.integer(fields$redesign$cells_added %||% 0L),
                                               base_design_cells = as.integer(fields$redesign$base_design_cells %||% 0L)), root = root)
  invisible(rec)
}

# =============================================================================
# 결정 대기 레지스터 (P3-07 · 2026-09-23 도훈 승인 플랜 qvest-1-drifting-eclipse) — dr_open / dr_resolve / dr_list
# =============================================================================
# ★왜: 도훈 결정 대기 항목(R1 → l2_auto.enabled → director.act 사슬 등)이 2계층 A 경로와 자기개선 채점기를
#   막고 있었는데 부팅 어디에도 안 보였다(감사 D7-04·D8-05). 결정이 config 공란(`l2_auto.selection_type: ""`)·
#   frontier `parked_reason`·플랜 표에 흩어져 있으면 "무엇이 무엇을 막는가"를 아무도 세지 않는다.
#   저장소 1곳 + writer 3종 + 부팅 Director 줄 부기(boot_lean.sh::DECISIONS — 읽기만).
# 파일: 06_Registry/decision_register.json
#   {schema, items:[{id, title, status(open/resolved), opened_at, options, recommendation, default_until_decided,
#                    blocks, owner, source, decision, decided_by, decided_at, note, registered_at[, opened_at_basis]}]}
# 계약:
#   · 쓰기 = 공용 정본 qvest_atomic_write_json(02_Infrastructure/utils/atomic_json.R — 선삭제 없음 · 유한 재시도 ·
#     copy 폴백 없음). .rf_write 를 안 쓰는 이유: 원장 층 경로에 묶여 있고, 그 copy 폴백은 atomic_json.R
#     [측정 2] 가 '소비자가 읽는 순간 파일을 찢는' 경로로 실증했다. 부팅이 매 세션 이 파일을 읽는다.
#   · dr_resolve 는 decided_by == 항목 owner 일 때만 — 세션·무인 레인이 도훈 결정을 대신 적지 못하게.
#   · resolved 재결정 거부 — 바꾸려면 새 항목(새 id)으로. 덮어쓰면 무엇을 언제 바꿨는지가 사라진다.
#   · blocks 어휘 = "lane:<레인>"(부팅 '차단' 표기) · "decision:<다른 항목 id>"(사슬 — 등록 시 존재해야 함) ·
#     "item:<작업 항목>". 접두 없는 자유 문자열은 거부한다(부팅이 무엇을 레인으로 셀지 모호해진다).
#   · 소급 개시일(opened_at 지정)은 근거(opened_at_basis) 필수 — 최고령 표기가 추정이면 추정이라고 남긴다.
#   · 읽기 실패(부재·파손 JSON·schema·파손 항목)는 **명시 오류** — 빈 목록으로 접지 않는다
#     (못 읽은 레지스터 ≠ 대기 결정 0 · 빈결과=합격 병리).
#   · 전 함수 root 인자로 격리 가능. 검사 = 08_Tests/ops/test_decision_register.R(부팅 표시 양성 대조·돌연변이 포함).
DR_SCHEMA <- "decision_register_v1"
DR_STATUS_ENUM <- c("open", "resolved")
DR_BLOCK_KINDS <- c("lane", "decision", "item")
dr_path <- function(root = .rf_root()) file.path(root, "06_Registry", "decision_register.json")
.dr_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.dr_str1 <- function(x, what, allow_empty = FALSE) {
  if (!is.character(x) || length(x) != 1L || is.na(x))
    stop(sprintf("[decision_register] %s 는 문자열 1개여야 한다", what), call. = FALSE)
  x <- trimws(x)
  if (!allow_empty && !nzchar(x)) stop(sprintf("[decision_register] %s 가 비었다", what), call. = FALSE)
  x
}
.dr_chr <- function(x, what, min_n = 0L) {
  if (is.list(x)) {
    if (!all(vapply(x, function(v) is.character(v) && length(v) == 1L && !is.na(v), logical(1))))
      stop(sprintf("[decision_register] %s 원소는 문자열이어야 한다", what), call. = FALSE)
    x <- unlist(x, use.names = FALSE)
  }
  if (is.null(x)) x <- character(0)
  if (!is.character(x) || anyNA(x)) stop(sprintf("[decision_register] %s 는 문자 벡터여야 한다", what), call. = FALSE)
  x <- trimws(x)
  if (any(!nzchar(x))) stop(sprintf("[decision_register] %s 에 빈 원소", what), call. = FALSE)
  if (length(x) < min_n) stop(sprintf("[decision_register] %s 는 최소 %d개", what, min_n), call. = FALSE)
  x
}
.dr_date_ok <- function(s) grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", s) && !is.na(as.Date(substr(s, 1L, 10L), "%Y-%m-%d"))

#' 레지스터 적재 — create=TRUE 는 writer(dr_open) 전용(부재 시 골격). 그 외 부재·파손은 명시 오류.
dr_load <- function(root = .rf_root(), create = FALSE) {
  p <- dr_path(root)
  if (!file.exists(p)) {
    if (isTRUE(create))
      return(list(schema = DR_SCHEMA,
                  note = "도훈 결정 대기 레지스터 (P3-07). writer = reinforce_ledger.R::dr_open/dr_resolve 만(owner 만 resolve · 재결정은 새 id). 부팅 Director 줄이 open 수·최고령·차단 레인을 읽는다.",
                  items = list(), last_updated = ""))
    stop(sprintf("[decision_register] 레지스터 부재: %s", p), call. = FALSE)
  }
  obj <- tryCatch(fromJSON(p, simplifyVector = FALSE),
                  error = function(e) stop(sprintf("[decision_register] 파손 JSON: %s (%s)", p, conditionMessage(e)), call. = FALSE))
  if (!is.list(obj) || !identical(obj$schema, DR_SCHEMA))
    stop(sprintf("[decision_register] schema 불일치: %s (기대 %s)",
                 if (is.list(obj)) as.character(obj$schema %||% "<없음>") else class(obj)[1], DR_SCHEMA), call. = FALSE)
  if (!is.list(obj$items)) stop("[decision_register] items 가 배열이 아니다", call. = FALSE)
  ids <- character(0)
  for (k in seq_along(obj$items)) {
    it <- obj$items[[k]]
    if (!is.list(it) || !is.character(it$id) || length(it$id) != 1L || !nzchar(it$id) ||
        !is.character(it$status) || length(it$status) != 1L || !(it$status %in% DR_STATUS_ENUM))
      stop(sprintf("[decision_register] 파손 항목 #%d (id/status)", k), call. = FALSE)
    ids <- c(ids, it$id)
  }
  if (anyDuplicated(ids)) stop(sprintf("[decision_register] 중복 id: %s", paste(unique(ids[duplicated(ids)]), collapse = ",")), call. = FALSE)
  obj
}

.dr_write <- function(obj, root) {
  obj$last_updated <- .dr_now()
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || !identical(chk$schema, DR_SCHEMA) || length(chk$items) != length(obj$items))
    stop("[decision_register] 쓰기 직전 재파싱 검증 실패 — 정본 불변", call. = FALSE)
  if (!exists("qvest_atomic_write_json", mode = "function")) {
    # 코드 루트(.rf_root) ≠ 데이터 루트(root) — 격리 검사는 root 만 임시 디렉터리로 바꾼다.
    src <- file.path(.rf_root(), "02_Infrastructure", "utils", "atomic_json.R")
    if (!file.exists(src)) stop(sprintf("[decision_register] 원자 쓰기 정본 부재: %s", src), call. = FALSE)
    source(src)
  }
  qvest_atomic_write_json(obj, dr_path(root), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null",
                          digits = 6, tag = "decision_register")
  invisible(dr_path(root))
}

#' 결정 대기 항목 등록
#' @param options     선택지(문자 벡터 ≥1)
#' @param blocks      "lane:" / "decision:" / "item:" 접두 문자 벡터(0개 허용). decision: 대상은 이미 등록돼 있어야 한다
#' @param opened_at   NULL = 지금. 소급 지정 시 "YYYY-MM-DD…" + opened_at_basis(근거) 필수
dr_open <- function(id, title, options, recommendation, default_until_decided, blocks,
                    owner = "dohoon", source, root = .rf_root(), opened_at = NULL, opened_at_basis = NULL) {
  id <- .dr_str1(id, "id")
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", id))
    stop(sprintf("[decision_register] id 형식(영숫자·_.-): %s", id), call. = FALSE)
  title <- .dr_str1(title, "title")
  opts  <- .dr_chr(options, "options", min_n = 1L)
  rec   <- .dr_str1(recommendation, "recommendation", allow_empty = TRUE)
  dflt  <- .dr_str1(default_until_decided, "default_until_decided")
  bl    <- .dr_chr(blocks, "blocks")
  owner <- .dr_str1(owner, "owner")
  src   <- .dr_str1(source, "source")
  bad <- bl[!grepl(sprintf("^(%s):[^[:space:]]", paste(DR_BLOCK_KINDS, collapse = "|")), bl)]
  if (length(bad))
    stop(sprintf("[decision_register] blocks 접두는 lane:/decision:/item: 뿐: %s", paste(bad, collapse = " | ")), call. = FALSE)
  now <- .dr_now(); basis <- NULL
  if (is.null(opened_at)) oa <- now else {
    oa <- .dr_str1(opened_at, "opened_at")
    if (!.dr_date_ok(oa)) stop(sprintf("[decision_register] opened_at 날짜 형식: %s", oa), call. = FALSE)
    basis <- .dr_str1(opened_at_basis %||% "", "opened_at_basis(소급 개시일 근거)")
  }
  obj <- dr_load(root, create = TRUE)
  ids <- vapply(obj$items, function(x) x$id, character(1))
  if (id %in% ids) {
    st <- obj$items[[match(id, ids)]]$status
    stop(sprintf("[decision_register] 이미 있는 id: %s (status=%s) — 재결정·재상정은 새 id 로", id, st), call. = FALSE)
  }
  dec <- sub("^decision:", "", bl[startsWith(bl, "decision:")])
  if (id %in% dec) stop("[decision_register] 자기 자신을 막을 수 없다", call. = FALSE)
  miss <- setdiff(dec, ids)
  if (length(miss))
    stop(sprintf("[decision_register] blocks 의 decision 대상 미등록: %s (막히는 쪽을 먼저 등록)", paste(miss, collapse = ",")), call. = FALSE)
  item <- list(id = id, title = title, status = "open", opened_at = oa, options = as.list(opts),
               recommendation = rec, default_until_decided = dflt, blocks = as.list(bl), owner = owner,
               source = src, decision = NULL, decided_by = NULL, decided_at = NULL, note = NULL, registered_at = now)
  if (!is.null(basis)) item$opened_at_basis <- basis
  obj$items[[length(obj$items) + 1L]] <- item
  .dr_write(obj, root)
  invisible(item)
}

#' 결정 기록 — decided_by 가 항목 owner 와 다르면 거부 · 이미 resolved 면 거부(새 항목으로)
## ★출처 필드 (2026-09-23 적대 리뷰): owner 대조는 **문자열 규약이지 인증이 아니다** — 어떤 세션도 decided_by="dohoon" 을 넘길 수 있다.
##   그래서 누가 적었는지(recorded_by)와 결정의 근거(evidence — 채팅 응답·파일 경로 인용)를 함께 남겨
##   세션이 대신 적은 결정과 도훈이 직접 적은 결정을 사후에 가를 수 있게 한다. 선택 인자(구 호출 호환).
dr_resolve <- function(id, decision, decided_by, note = "", root = .rf_root(), decided_at = NULL,
                       recorded_by = NULL, evidence = NULL) {
  id <- .dr_str1(id, "id")
  decision <- .dr_str1(decision, "decision")
  decided_by <- .dr_str1(decided_by, "decided_by")
  note <- .dr_str1(note %||% "", "note", allow_empty = TRUE)
  da <- if (is.null(decided_at)) .dr_now() else {
    d <- .dr_str1(decided_at, "decided_at")
    if (!.dr_date_ok(d)) stop(sprintf("[decision_register] decided_at 날짜 형식: %s", d), call. = FALSE)
    d
  }
  obj <- dr_load(root)
  k <- which(vapply(obj$items, function(x) identical(x$id, id), logical(1)))
  if (!length(k)) stop(sprintf("[decision_register] 항목 부재: %s", id), call. = FALSE)
  it <- obj$items[[k]]
  if (identical(it$status, "resolved"))
    stop(sprintf("[decision_register] 재결정 거부: %s 는 %s 에 %s 가 결정(%s) — 바꾸려면 새 항목(dr_open)으로",
                 id, as.character(it$decided_at %||% "?"), as.character(it$decided_by %||% "?"),
                 as.character(it$decision %||% "?")), call. = FALSE)
  own <- trimws(as.character(it$owner %||% ""))
  if (!identical(decided_by, own))
    stop(sprintf("[decision_register] owner 불일치 거부: %s 의 owner=%s · decided_by=%s", id, own, decided_by), call. = FALSE)
  it$status <- "resolved"; it$decision <- decision; it$decided_by <- decided_by
  it$decided_at <- da; it$note <- note
  if (!is.null(recorded_by)) it$recorded_by <- .dr_str1(recorded_by, "recorded_by")
  if (!is.null(evidence))    it$evidence    <- .dr_str1(evidence, "evidence")
  obj$items[[k]] <- it
  .dr_write(obj, root)
  invisible(it)
}

#' 목록 — status = "open"(기본) / "resolved" / "all". 오래된 순(opened_at → id). 부재·파손은 명시 오류.
dr_list <- function(status = "open", root = .rf_root()) {
  st <- .dr_str1(status, "status")
  if (!(st %in% c(DR_STATUS_ENUM, "all"))) stop(sprintf("[decision_register] status: %s", st), call. = FALSE)
  its <- dr_load(root)$items
  if (st != "all") its <- Filter(function(x) identical(x$status, st), its)
  if (length(its)) {
    oa <- vapply(its, function(x) substr(as.character(x$opened_at %||% "9999-99-99"), 1L, 10L), character(1))
    its <- its[order(oa, vapply(its, function(x) x$id, character(1)))]
  }
  its
}


# =============================================================================
# 빈티지 표식 (2026-09-23 · 도훈 결정 "결손된 9월 팩터 DB 를 읽은 강화 측정 = 목록화 + 표식만")
# =============================================================================
# ★왜: factor_db_202608(2026-08-31 00:27 빌드 — 08-28 데이터를 08-31 라벨로 · class_R 22종 결손)과
#   factor_db_202609(Size 결측 → class_R 27종)가 교정 재빌드(09-23 18:53 / 18:56) 전까지 측정에 소비됐다.
#   재측정은 P0-05 rebase 가 흡수한다. 여기서는 "어느 칸이 어느 빈티지를 먹었나" 를 **덧붙이기만** 한다.
#   목록·판정 근거 = 06_Registry/vintage_cascade_20260923.json (판정: consumed / consumed_absence / possible / not_consumed —
#   표식 대상은 consumed·consumed_absence·possible 뿐이다).
#   consumed_absence(v2 · 2026-09-23 적대 검증 수리) = 결손 팩터가 rf_cell_engine.R:237-243 inner merge 로 08-31 신호일을
#   통째로 버려 9월 리밸을 잃은 채 8월 보유로 9월 수익을 실현한 소비. flag 는 같은 빈티지 flag, 사유는 evidence 의 reason=.
# 계약:
#   · append-only — attempt 의 `vintage_flags`(entry 의 기저 측정이면 `base_vintage_flags`)에 원소를 더할 뿐이다.
#     essence·grade·artifacts·lessons 를 포함한 기존 필드는 한 비트도 바꾸지 않는다. 쓰기 직전
#     보호 투영(표식 필드·last_updated 를 뺀 원장 전체)을 **직렬화 왕복 후** 원본과 대조해 다르면 쓰지 않고,
#     쓴 뒤 다시 읽어 대조해 다르면 원본 바이트로 되돌리고 멈춘다.
#   · 표식 레코드 키는 허용목록(RF_VINTAGE_MARK_KEYS)만 — essence/grade 같은 키를 실어 보내면 거부한다.
#   · 멱등 — 같은 flag 가 이미 있으면 건너뛴다(덮어쓰지 않는다. 판정을 바꾸려면 새 flag 이름).
#   · 잠금 — 러너 claim(QVEST_RF_CLAIM · 기본 <root>/.cache/reinforce_auto.claim)을 rf_claim_acquire 로 잡고 쓴다.
#     L2 레인도 원장 쓰기를 같은 claim 으로 직렬화한다(rf_l2_auto.R:47). 못 잡으면 wait_s 까지 재시도 후 거부.
#     + CAS: 적재 시 md5 와 쓰기 직전 md5 가 다르면(claim 밖 writer) 쓰지 않는다.
#   · 원자 쓰기 = .rf_write(tmp+rename · 재파싱 검증) — 이 파일의 다른 원장 writer 와 같은 경로.
#   · 배치가 한 단위 — 검증 실패가 하나라도 있으면 아무것도 쓰지 않는다.
#   · 검사 = 08_Tests/reinforcement/test_rf_mark_vintage.R (합성 픽스처 · 운영 원장 무접촉 · 돌연변이 red).
RF_VINTAGE_VERDICTS  <- c("consumed", "consumed_absence", "possible")
RF_VINTAGE_MARK_KEYS <- c("base_id", "attempt_key", "flag", "verdict", "evidence", "source")
RF_VINTAGE_POLICY    <- "표식만 — 재측정 금지(P0-05 rebase 흡수) · 도훈 2026-09-23"

#' 보호 투영 — 표식 필드와 last_updated 만 뺀 원장. 두 투영이 identical 이면 표식 밖 변경 0.
.rf_vintage_protected <- function(obj) {
  obj$last_updated <- NULL
  obj$entries <- lapply(obj$entries, function(e) {
    e$base_vintage_flags <- NULL
    if (!is.null(e$attempts)) e$attempts <- lapply(e$attempts, function(a) { a$vintage_flags <- NULL; a })
    e
  })
  obj
}
.rf_vintage_same <- function(a, b) identical(.rf_vintage_protected(a), .rf_vintage_protected(b))

.rf_vintage_validate <- function(m, k) {
  if (!is.list(m) || is.null(names(m)))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — 이름 있는 list 여야 한다", k), call. = FALSE)
  extra <- setdiff(names(m), RF_VINTAGE_MARK_KEYS)
  if (length(extra))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — 허용 밖 키 거부: %s (표식은 essence·grade 를 싣지 못한다)",
                 k, paste(extra, collapse = ",")), call. = FALSE)
  s1 <- function(x) { x <- suppressWarnings(as.character(x %||% "")); if (length(x) != 1L || is.na(x)) "" else trimws(x) }
  if (!nzchar(s1(m$base_id))) stop(sprintf("[reinforce_ledger] vintage 표식 #%d — base_id 비었음", k), call. = FALSE)
  ak <- s1(m$attempt_key)
  if (!(identical(ak, "base") || grepl("^[0-9]+$", ak)))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — attempt_key 는 시도 번호 n 또는 \"base\": %s", k, ak), call. = FALSE)
  if (!grepl("^[a-z0-9_]{3,64}$", s1(m$flag)))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — flag 는 [a-z0-9_]{3,64}: %s", k, s1(m$flag)), call. = FALSE)
  if (!(s1(m$verdict) %in% RF_VINTAGE_VERDICTS))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — verdict 는 %s 만 표식한다(not_consumed 는 목록에만): %s",
                 k, paste(RF_VINTAGE_VERDICTS, collapse = "/"), s1(m$verdict)), call. = FALSE)
  if (!nzchar(s1(m$evidence)))
    stop(sprintf("[reinforce_ledger] vintage 표식 #%d — evidence 필수(근거 없이 표식하지 않는다)", k), call. = FALSE)
  list(base_id = s1(m$base_id), attempt_key = ak, flag = s1(m$flag), verdict = s1(m$verdict),
       evidence = s1(m$evidence), source = s1(m$source))
}

#' 빈티지 표식 배치 writer
#' @param marks list(list(base_id, attempt_key = n | "base", flag, verdict = consumed|consumed_absence|possible, evidence, source?))
#' @param claim 잠금 claim 경로. NULL = QVEST_RF_CLAIM 또는 <root>/.cache/reinforce_auto.claim (러너와 같은 해석)
#' @param backup_to / snapshot_after_to 선택 — 잠금 안에서 쓰기 전 원본 바이트 / 쓴 직후 바이트를 이 경로에 복사
#'   (운영 호출의 전후 diff 증명용 — 잠금 밖에서 뜬 사본은 그 사이 러너 쓰기가 섞인다).
#' @param .pre_write_hook 검사 전용 — CAS 검사 직전에 불린다(외부 writer 주입). 운영 호출은 NULL.
#' @return list(n_new, n_already, written, md5_before, md5_after)
rf_mark_vintage_batch <- function(layer, marks, root = .rf_root(), claim = NULL,
                                  wait_s = 900, poll_s = 5, policy = RF_VINTAGE_POLICY,
                                  backup_to = NULL, snapshot_after_to = NULL,
                                  .pre_write_hook = NULL) {
  stopifnot(layer %in% c(1L, 2L))
  if (!length(marks)) stop("[reinforce_ledger] vintage 표식 — marks 가 비었다", call. = FALSE)
  M <- lapply(seq_along(marks), function(k) .rf_vintage_validate(marks[[k]], k))   # I/O 전 전수 검증

  # ── 잠금: 러너 claim (전용 env 에 적재 — rf_claim.R 의 %||% 가 이 파일의 NA 인지 %||% 를 덮지 않게) ──
  .cl <- new.env(parent = globalenv())
  .lib <- c(file.path(root, "02_Infrastructure/ops/rf_claim.R"), file.path(.rf_root(), "02_Infrastructure/ops/rf_claim.R"))
  .lib <- .lib[file.exists(.lib)]
  if (!length(.lib)) stop("[reinforce_ledger] vintage 표식 — rf_claim.R 부재(잠금 없이 쓰지 않는다)", call. = FALSE)
  sys.source(.lib[1], envir = .cl)
  claim <- claim %||% { .e <- Sys.getenv("QVEST_RF_CLAIM", "")
                        if (nzchar(.e)) .e else file.path(root, ".cache", "reinforce_auto.claim") }
  dir.create(dirname(claim), recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()
  repeat {
    ac <- .cl$rf_claim_acquire(claim, stale_hours = 6)
    if (isTRUE(ac$ok)) break
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) >= wait_s)
      stop(sprintf("[reinforce_ledger] vintage 표식 — 원장 잠금(claim) 획득 실패(%s · owner_pid=%s · %.0f초 대기) — 아무것도 쓰지 않았다",
                   ac$reason, as.character(ac$owner_pid %||% NA), wait_s), call. = FALSE)
    Sys.sleep(poll_s)
  }
  on.exit(.cl$rf_claim_release(claim), add = TRUE)

  # ── 적재 (CAS 기준 md5 + 원본 바이트) ─────────────────────────────────────────
  p <- .rf_path(layer, root)
  if (!file.exists(p)) stop("[reinforce_ledger] vintage 표식 — 원장 부재: ", p, call. = FALSE)
  md5_0 <- unname(tools::md5sum(p))
  raw0  <- readBin(p, "raw", file.info(p)$size)
  if (!is.null(backup_to)) { writeBin(raw0, backup_to)
    if (!identical(unname(tools::md5sum(backup_to)), md5_0))
      stop("[reinforce_ledger] vintage 표식 — 쓰기 전 백업 검증 실패 — 쓰지 않는다: ", backup_to, call. = FALSE) }
  orig  <- rf_load(layer, root)
  obj   <- orig
  now   <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  n_new <- 0L; n_already <- 0L
  for (m in M) {
    i <- .rf_find(obj, m$base_id)
    if (is.na(i)) stop(sprintf("[reinforce_ledger] vintage 표식 — entry 부재: %s", m$base_id), call. = FALSE)
    rec <- list(flag = m$flag, verdict = m$verdict, evidence = m$evidence, source = m$source,
                policy = policy, marked_at = now)
    if (identical(m$attempt_key, "base")) {
      fl <- obj$entries[[i]]$base_vintage_flags %||% list()
      if (any(vapply(fl, function(x) identical(as.character(x$flag %||% ""), m$flag), logical(1)))) {
        n_already <- n_already + 1L; next }
      obj$entries[[i]]$base_vintage_flags <- c(fl, list(rec))
    } else {
      e <- obj$entries[[i]]
      j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(m$attempt_key)), logical(1)))
      if (!length(j)) stop(sprintf("[reinforce_ledger] vintage 표식 — attempt n=%s 부재 (%s)", m$attempt_key, m$base_id), call. = FALSE)
      j <- j[1]
      if (is.null(e$attempts[[j]]$essence))
        stop(sprintf("[reinforce_ledger] vintage 표식 — n=%s (%s) 는 미측정(essence 없음) — 측정 빈티지 표식 대상 아님",
                     m$attempt_key, m$base_id), call. = FALSE)
      fl <- e$attempts[[j]]$vintage_flags %||% list()
      if (any(vapply(fl, function(x) identical(as.character(x$flag %||% ""), m$flag), logical(1)))) {
        n_already <- n_already + 1L; next }
      obj$entries[[i]]$attempts[[j]]$vintage_flags <- c(fl, list(rec))
    }
    n_new <- n_new + 1L
  }
  if (n_new == 0L)
    return(invisible(list(n_new = 0L, n_already = n_already, written = FALSE, md5_before = md5_0, md5_after = md5_0)))

  # ── 보호 투영 대조: 메모리 + 직렬화 왕복(.rf_write 와 같은 인자) ─────────────────
  if (!.rf_vintage_same(obj, orig))
    stop("[reinforce_ledger] vintage 표식 — 표식 밖 필드가 바뀌었다(essence·grade 포함 보호 투영 불일치) — 쓰지 않는다", call. = FALSE)
  .rt <- fromJSON(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6),
                  simplifyVector = FALSE)
  if (!.rf_vintage_same(.rt, orig))
    stop("[reinforce_ledger] vintage 표식 — 직렬화 왕복이 표식 밖 값을 바꾼다(숫자 자릿수 등) — 쓰지 않는다", call. = FALSE)

  if (is.function(.pre_write_hook)) .pre_write_hook(p)
  if (!identical(unname(tools::md5sum(p)), md5_0))
    stop("[reinforce_ledger] vintage 표식 — 적재 후 원장이 바뀌었다(claim 밖 동시 쓰기) — 덮어쓰지 않는다. 재시도하라", call. = FALSE)
  .rf_write(obj, layer, root)

  # ── 사후 검증: 다시 읽어 보호 투영 대조 — 어긋나면 원본 바이트로 되돌리고 멈춘다 ─────
  back <- tryCatch(rf_load(layer, root), error = function(e) NULL)
  if (is.null(back) || !.rf_vintage_same(back, orig)) {
    tmp <- paste0(p, ".vintage_restore.tmp"); writeBin(raw0, tmp)
    if (!suppressWarnings(file.rename(tmp, p))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
    stop("[reinforce_ledger] vintage 표식 — 사후 검증 실패, 원본 바이트로 되돌렸다", call. = FALSE)
  }
  md5_1 <- unname(tools::md5sum(p))
  if (!is.null(snapshot_after_to)) file.copy(p, snapshot_after_to, overwrite = TRUE)
  cat(sprintf("[reinforce_ledger] vintage 표식 L%d: 신규 %d · 기존 %d (보호 투영 불변 확인)\n", layer, n_new, n_already))
  invisible(list(n_new = n_new, n_already = n_already, written = TRUE, md5_before = md5_0, md5_after = md5_1))
}

#' 단건 wrapper — rf_mark_vintage(layer, base_id, attempt_key, flag, evidence, verdict)
rf_mark_vintage <- function(layer, base_id, attempt_key, flag, evidence, verdict = "consumed",
                            source = "", root = .rf_root(), ...) {
  rf_mark_vintage_batch(layer, list(list(base_id = base_id, attempt_key = attempt_key, flag = flag,
                                         verdict = verdict, evidence = evidence, source = source)),
                        root = root, ...)
}

#' 소비자용 — 이 attempt(또는 entry 의 base 측정)에 flag 가 있는가. 없으면 FALSE.
rf_has_vintage_flag <- function(x, flag) {
  fl <- x$vintage_flags %||% x$base_vintage_flags %||% list()
  any(vapply(fl, function(z) identical(as.character(z$flag %||% ""), as.character(flag)), logical(1)))
}

# =============================================================================
# 측정 규약 rebase · 축 epoch (P0-06 · 2026-09-24 도훈 승인 플랜 qvest-1-drifting-eclipse · 결정 EXEC-PRICE)
# =============================================================================
# ★왜: P0-04(2026-09-24)가 등급 하네스의 체결 규약을 close_d_legacy(시그널일 종가 체결) → close_t1(익일 종가)로 바꿨다.
#   원장의 측정 칸은 전부 구 규약 값이다. 규약이 다른 수치끼리 비교하면 바닥·carry·승격·결합 풀이 섞인 자로 잰다.
#   P0-05 가 칸마다 04_holdings 로 새 규약 판을 형제 파일 `<artifacts>/remeasure_<regime>/authoritative_remeasure.json`
#   에 내면, 이 writer 가 원장 essence 를 그 판으로 **교체하고 구판은 essence_history[[구 regime]] 으로 옮긴다**
#   (append-only — 지우지도 덮지도 않는다). 그 뒤 rf_mark_axis_epoch(relabel_from=, require_regime=) 이 current_axis 를 바꾼다.
#   순서(플랜 P0-06): config 전환 → 신규 칸은 새 규약 → 전환 이전 칸 전수 remeasure·rebase → current_axis 교체.
# 계약:
#   · 등급 = 형제 파일의 essence_grade 만(권위 등급 — 호출자는 등급을 넘기지 못한다 · 손계산 금지).
#   · 형제 = 그 칸 artifacts 디렉터리 바로 아래 remeasure_<regime>/authoritative_remeasure.json. 다른 칸·다른 regime 의 판은 거부.
#     파일의 regime 키(measurement_regime$regime → $key → $exec_price)가 인자 regime 과 다르면 거부(regime 불일치 형제).
#     ★P0-05 판(remeasure_from_holdings.R)의 계약(2026-09-24 수리 · 통합 검증 L-B1): 디렉터리 remeasure_<key> · 파일
#     measurement_regime{regime = key, key, exec_price} — regime 인자 = 키("<exec_price>_<md5 8>"). 구판 writer 는 regime →
#     exec_price 만 봐서 실제 P0-05 산출을 어느 regime 으로 불러도 거부했다(regime_mismatch / regime_dir_mismatch 5/5).
#   · ★원장 essence 는 writer 가 **조립**한다(2026-09-24 수리 · L-B2): 새 essence = 신원 키(RF_REBASE_ID_KEYS — 구 essence 값 그대로)
#     + 측정 키(RF_REBASE_MEAS — 전부 형제 판 값 · 형제에 없으면 **뺀다**) + source. 구 essence 의 그 밖 키(dsr·net_ir·세션이 적은
#     보조 수치 등)는 새 essence 에 남지 않는다 — essence_history[[구 regime]] 에만 있다. 구판은 essence_new 를 그대로 써서
#     핵심 6지표만 대조했고, 호출자가 원장 essence 에서 핵심만 바꾸면 dsr·net_ir·N 이 구 규약 값으로 조용히 남았다(실측
#     dsr 0.609 대 형제 0.555). essence_new 는 호출자의 **주장**이다 — 측정 키는 형제와 같아야 하고(다르면 essence_mismatch:<키>),
#     신원 키는 구 essence 와 같아야 하며(identity_mismatch), 허용 밖 키는 거부한다(essence_new_foreign_keys).
#     조립기 = rf_rebase_essence_from_sibling(구 essence, 형제 판) — 드라이버·검사가 같은 함수로 essence_new 를 만든다.
#   · 구 regime 은 **재도출**한다: 원장 표식(measurement_regime$regime) → 칸 산출물 auth 의 measurement_regime.
#     호출자가 준 regime_old 는 재도출값과 대조만 한다(재도출 불가일 때만 채택). P0-01(2026-09-23) 이전 auth 는
#     measurement_regime 이 없는데, 그때 하네스(replication_harness.R)의 체결 규약은 하나뿐이었고 P0-04 가 그것을
#     'close_d_legacy' 로 명명했다(P0-01 은 같은 값을 리터럴로 적었다) → RF_REGIME_PRE_P0_01.
#   · history 키가 이미 있으면 거부(덮어쓰기 0) · 새 regime 이 history 에 이미 있으면 거부 · 같은 regime 재기록은 같은 판
#     (md5·핵심 지표 동일)이면 멱등, 아니면 거부.
#   · PIT 표식 칸 거부 — RF_REBASE_BLOCK_FLAGS(pit_c11) ∪ 06_Registry/pit_quarantine.json active flag.
#     근거 = 도훈 결정 PIT-C11-CONVENTIONS ⑧ "P0-05·06 재측정 경로 비편입": C11 오염은 보유를 고른 신호 안에 있어 보유
#     재측정으로 씻기지 않는다 — 편입하면 오염 보유가 rebase 된 essence 로 세탁된다. 그 칸은 수리 뒤 새 칸으로 잰다.
#   · 자식 entry 의 parent$best_* 는 rebase 된 승자 칸 값으로 다시 쓰고, 구값은 parent_rebased_from 에 쌓는다(append-only).
#   · 잠금 = 러너 claim(idle 에서만 — 같은 프로세스가 이미 쥐었으면 그대로 쓰고 풀지 않는다) · CAS(적재 md5) ·
#     보호 투영(허용 필드 밖 불변 — 검사 대상 칸이 아닌 모든 칸 포함) · history append-only 전수 대조 · 직렬화 왕복 ·
#     사후 재적재 대조 → 어긋나면 원본 바이트 복원.
#   · 배치가 한 단위(기본) — 거부가 하나라도 있으면 아무것도 쓰지 않는다. skip_rejected=TRUE 면 거부 칸은 사유 코드와 함께
#     반환만 하고(조용한 배제 아님 · items 에 남는다) 나머지를 쓴다. dry_run=TRUE 는 검증·계획만(쓰기·잠금 없음).
#   · 등급·지표 밖 필드(lessons · adversary · vintage_flags · l_code)는 건드리지 않는다 — 구 측정에 대한 사실 기록이다.
#   · 검사 = 08_Tests/reinforcement/test_rf_rebase.R (합성 픽스처 + 운영 원장 사본 · 운영 원장 무접촉 · 돌연변이 red).
RF_REGIME_PRE_P0_01     <- "close_d_legacy"
RF_REGIME_LABEL_RE      <- "^[a-z0-9][a-z0-9_.-]{1,63}$"      # 디렉터리 이름(remeasure_<regime>)이 되므로 경로 안전 문자만
RF_REBASE_REGIME_FIELDS <- c("essence", "grade", "grade_base", "retro", "retro_inherited", "measurement_regime")
RF_REBASE_BASE_FIELDS   <- c("base_grade", "base_measurement_regime", "base_remeasure")
RF_REBASE_BLOCK_FLAGS   <- c("pit_c11")                          # 결정 PIT-C11-CONVENTIONS ⑧ (06_Registry/decision_register.json)
# 원장 요약 키 ← 형제 파일 essence 키 (rf_cell_worker.R 의 원장 요약 매핑과 같은 짝)
RF_REBASE_CORE <- list(port_t = c("portfolio_alpha_t_nw_lag3", "port_t"), net_sharpe = "net_sharpe", cagr = "cagr",
                       mdd = "mdd", calmar = "calmar", oos_retention = "oos_retention")
# ★rebase essence 조립(L-B2) — 신원 키(구 essence 값 그대로 · 측정과 무관한 칸 식별·스펙 경로·상속 표식)와
#   측정 키(원장 요약 키 ← 형제 파일 위치 목록 · 앞에서부터 첫 값). 측정 키 짝은 rf_cell_worker.R 의 원장 요약과 같다
#   (핵심 6 + 시행 회계 3 — dsr·selection_type·n_trials_cumulative) + net_ir(구 세션 칸의 원장 요약 키 · essence_score 산출).
#   위치 표기: "essence:<키>" = 형제 essence 안 · "top:<키>" = 형제 최상위 · "mr:<키>" = 형제 measurement_regime 안.
RF_REBASE_ID_KEYS <- c("cell_code", "block", "spec", "inherited_from", "strategy_name")
RF_REBASE_MEAS <- list(port_t = c("essence:portfolio_alpha_t_nw_lag3", "essence:port_t"), net_sharpe = "essence:net_sharpe",
                       cagr = "essence:cagr", mdd = "essence:mdd", calmar = "essence:calmar", oos_retention = "essence:oos_retention",
                       net_ir = "essence:net_ir", dsr = c("essence:dsr", "top:dsr"),
                       selection_type = c("top:selection_type", "mr:selection_type"),
                       n_trials_cumulative = c("top:n_trials_cumulative", "mr:n_trials_cumulative"))
# 대조 허용오차 = .rf_write 의 직렬화 해상도(toJSON digits = 6 · 소수 6자리) — 새 문턱이 아니라 원장이 담을 수 있는 자릿수
RF_REBASE_TOL <- 1e-6
# 잠금 대기 — rf_mark_vintage_batch(2026-09-23) 기본값(wait_s 900 · poll_s 5 · stale_hours 6)과 같은 값을 이름으로 둔다.
#   stale 6h = reinforce_auto_config.json::claim_stale_hours 기본(러너 CFG$claim_stale_hours %||% 6)과 같다. 새 수치 아님.
RF_LEDGER_CLAIM_WAIT_S  <- 900
RF_LEDGER_CLAIM_POLL_S  <- 5
RF_LEDGER_CLAIM_STALE_H <- 6
RF_AXIS_ENTRY_FIELDS    <- c("measurement_axis", "axis_valid", "axis_marked_at", "axis_history", "axis_blocked_legacy")

# ★$ 는 부분 일치다 — essence 키가 없고 essence_history 가 있으면 a$essence 가 history 를 돌려준다(검사 A6 에서 실측).
#   측정 여부·구 essence 판독은 [["essence"]](정확 일치)로만 한다.
.rf_s1 <- function(x) {
  x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) != 1L || is.na(x)) "" else trimws(x)
}
.rf_abs_path <- function(p, root) {
  p <- .rf_s1(p); if (!nzchar(p)) return(NA_character_)
  if (!grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)", p)) p <- file.path(root, p)
  normalizePath(sub("[/\\\\]+$", "", p), winslash = "/", mustWork = FALSE)
}
.rf_same_path <- function(a, b) {
  if (is.na(a) || is.na(b)) return(FALSE)
  if (identical(.Platform$OS.type, "windows")) identical(tolower(a), tolower(b)) else identical(a, b)
}
#' 칸 산출물의 auth 파일 경로 — artifacts 가 dict(2026-08-29 WT 시기)면 $authoritative, 디렉터리면 그 아래 파일
.rf_auth_file <- function(artifacts, root) {
  if (is.list(artifacts)) artifacts <- artifacts$authoritative %||% ""
  d <- .rf_abs_path(artifacts, root); if (is.na(d)) return(NA_character_)
  if (grepl("\\.json$", d, ignore.case = TRUE)) d else file.path(d, "authoritative_remeasure.json")
}
.rf_read_json <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
#' auth 객체의 regime 키 — measurement_regime$regime → $key(P0-05 재측정 판 키 · 2026-09-24 L-B1) → $exec_price.
#'   부재 = P0-01 이전 판(RF_REGIME_PRE_P0_01). (충실구현 러너 판은 key 가 없어 exec_price — 종전과 같다)
.rf_regime_key <- function(auth) {
  mr <- auth$measurement_regime
  if (is.null(mr)) return(list(regime = RF_REGIME_PRE_P0_01, basis = "pre_p0_01"))
  if (!is.list(mr)) return(list(regime = NA_character_, basis = "measurement_regime_malformed"))
  r <- .rf_s1(mr[["regime"]]);     if (nzchar(r)) return(list(regime = r, basis = "auth_regime"))
  r <- .rf_s1(mr[["key"]]);        if (nzchar(r)) return(list(regime = r, basis = "auth_key"))
  r <- .rf_s1(mr[["exec_price"]]); if (nzchar(r)) return(list(regime = r, basis = "auth_exec_price"))
  list(regime = NA_character_, basis = "measurement_regime_without_key")
}
#' 시도 1칸의 측정 regime — 원장 표식(rebase) → 산출물 auth 재도출. 미측정·산출물 부재는 NA(+basis).
rf_attempt_regime <- function(a, root = .rf_root()) {
  if (is.null(a[["essence"]])) return(list(regime = NA_character_, basis = "unmeasured"))
  mr <- a$measurement_regime
  r <- if (is.list(mr)) .rf_s1(mr$regime) else ""
  if (nzchar(r)) return(list(regime = r, basis = "ledger"))
  f <- .rf_auth_file(a$artifacts, root)
  if (is.na(f) || !file.exists(f)) return(list(regime = NA_character_, basis = "auth_absent"))
  j <- .rf_read_json(f)
  if (is.null(j)) return(list(regime = NA_character_, basis = "auth_parse_failed"))
  .rf_regime_key(j)
}
#' entry 기저 측정의 regime — 원장 표식(base rebase) → base_artifacts auth. 기저 auth 부재 = 미측정(base_unmeasured).
rf_base_regime <- function(e, root = .rf_root()) {
  mr <- e$base_measurement_regime
  r <- if (is.list(mr)) .rf_s1(mr$regime) else ""
  if (nzchar(r)) return(list(regime = r, basis = "ledger"))
  f <- .rf_auth_file(e$base_artifacts, root)
  if (is.na(f) || !file.exists(f)) return(list(regime = NA_character_, basis = "base_unmeasured"))
  j <- .rf_read_json(f)
  if (is.null(j)) return(list(regime = NA_character_, basis = "base_auth_parse_failed"))
  .rf_regime_key(j)
}
#' rebase 비편입 표식 — 상수(결정 ⑧) ∪ pit_quarantine.json 의 active 격리 flag. 파손 = stop(조용한 해제 금지 · 그 파일의 fail_policy).
rf_rebase_block_flags <- function(root = .rf_root()) {
  fl <- RF_REBASE_BLOCK_FLAGS
  p <- file.path(root, "06_Registry", "pit_quarantine.json")
  if (file.exists(p)) {
    q <- tryCatch(fromJSON(p, simplifyVector = FALSE),
                  error = function(e) stop(sprintf("[reinforce_ledger] pit_quarantine.json 파손 — rebase 비편입 목록을 못 읽는다(조용한 해제 금지): %s",
                                                   conditionMessage(e)), call. = FALSE))
    if (!is.list(q) || !is.list(q$quarantines))
      stop("[reinforce_ledger] pit_quarantine.json 형식 불량(quarantines 배열 부재) — rebase 거부", call. = FALSE)
    for (x in q$quarantines) if (identical(.rf_s1(x$status), "active") && nzchar(.rf_s1(x$flag))) fl <- c(fl, .rf_s1(x$flag))
  }
  unique(fl)
}
.rf_flags_hit <- function(fl_list, flags) {
  if (!is.list(fl_list) || !length(fl_list)) return(character(0))
  h <- vapply(fl_list, function(z) .rf_s1(if (is.list(z)) z$flag else NULL), character(1))
  unique(h[h %in% flags])
}

#' 러너 claim — 이미 이 프로세스가 쥐었으면 그대로(풀지 않는다), 아니면 획득·대기(못 잡으면 거부). idle 에서만 쓴다.
.rf_ledger_claim <- function(root, claim, wait_s, poll_s, what) {
  .cl <- new.env(parent = globalenv())
  .lib <- c(file.path(root, "02_Infrastructure/ops/rf_claim.R"), file.path(.rf_root(), "02_Infrastructure/ops/rf_claim.R"))
  .lib <- .lib[file.exists(.lib)]
  if (!length(.lib)) stop(sprintf("[reinforce_ledger] %s — rf_claim.R 부재(잠금 없이 쓰지 않는다)", what), call. = FALSE)
  sys.source(.lib[1], envir = .cl)
  claim <- claim %||% { .e <- Sys.getenv("QVEST_RF_CLAIM", "")
                        if (nzchar(.e)) .e else file.path(root, ".cache", "reinforce_auto.claim") }
  own <- file.path(claim, "owner.json")
  if (dir.exists(claim) && file.exists(own) && !file.exists(file.path(claim, "released.json"))) {
    o <- tryCatch(fromJSON(own, simplifyVector = TRUE), error = function(e) NULL)
    if (identical(suppressWarnings(as.integer(o$pid %||% NA)), as.integer(Sys.getpid())) &&
        (is.null(o$proc_start) || isTRUE(.cl$rf_claim_start_matches(o$proc_start, .cl$rf_claim_proc_start(Sys.getpid())))))
      return(list(claim = claim, mode = "held_by_caller", release = function() invisible(NULL)))
  }
  dir.create(dirname(claim), recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()
  repeat {
    got <- .cl$rf_claim_acquire(claim, stale_hours = RF_LEDGER_CLAIM_STALE_H)
    if (isTRUE(got$ok)) break
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) >= wait_s)
      stop(sprintf("[reinforce_ledger] %s — 러너 claim 획득 실패(%s · owner_pid=%s · %.0f초 대기) — 러너 idle 에서만 쓴다 · 아무것도 쓰지 않았다",
                   what, as.character(got$reason), as.character(got$owner_pid %||% NA), wait_s), call. = FALSE)
    Sys.sleep(poll_s)
  }
  list(claim = claim, mode = "acquired", release = function() .cl$rf_claim_release(claim))
}
.rf_restore_bytes <- function(p, raw, tag) {
  .rtmp <- paste0(p, ".", tag, "_restore.tmp")
  writeBin(raw, .rtmp)
  if (!suppressWarnings(file.rename(.rtmp, p))) { file.copy(.rtmp, p, overwrite = TRUE); unlink(.rtmp) }
  invisible(p)
}
.rf_axis_strip <- function(obj) {
  obj$last_updated <- NULL; obj$axis_epochs <- NULL; obj$current_axis <- NULL
  obj$entries <- lapply(obj$entries, function(e) { for (f in RF_AXIS_ENTRY_FIELDS) e[[f]] <- NULL; e })
  obj
}

#' entry 가 새 축 자격(require_regime)을 갖췄는가 — 기저 + 측정 칸 전부. 표식 칸은 판정에서 빼고 목록으로 돌려준다.
.rf_entry_regime_status <- function(e, accept, blocked_flags, root) {
  off <- character(0); blocked <- character(0); n_on <- 0L; n_meas <- 0L
  br <- rf_base_regime(e, root)
  if (!identical(br$basis, "base_unmeasured")) {
    n_meas <- n_meas + 1L
    if (length(.rf_flags_hit(e$base_vintage_flags, blocked_flags))) blocked <- c(blocked, "base")
    else if (!is.na(br$regime) && br$regime %in% accept) n_on <- n_on + 1L
    else off <- c(off, sprintf("base:%s", if (is.na(br$regime)) br$basis else br$regime))
  }
  for (a in e$attempts %||% list()) {
    if (is.null(a[["essence"]])) next
    n_meas <- n_meas + 1L
    if (length(.rf_flags_hit(a$vintage_flags, blocked_flags))) { blocked <- c(blocked, as.character(a$n)); next }
    r <- rf_attempt_regime(a, root)
    if (!is.na(r$regime) && r$regime %in% accept) n_on <- n_on + 1L
    else off <- c(off, sprintf("n%s:%s", as.character(a$n), if (is.na(r$regime)) r$basis else r$regime))
  }
  verdict <- if (length(off)) "legacy" else if (n_on >= 1L || n_meas == 0L) "epoch" else "legacy"
  why <- if (length(off)) "off_regime" else if (n_on >= 1L) "on_regime" else if (n_meas == 0L) "no_measurement" else "blocked_only"
  list(verdict = verdict, why = why, off = off, blocked = blocked, n_on = n_on, n_measured = n_meas)
}

# ── rebase writer ────────────────────────────────────────────────────────────
.rf_rb_reject <- function(code, msg) stop(structure(class = c("rf_rb_reject", "error", "condition"),
                                                     list(message = msg, call = NULL, code = code)))
.rf_rb_item <- function(it, k) {
  if (!is.list(it) || is.null(names(it)) || any(!nzchar(names(it))))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — 이름 있는 list 여야 한다", k), call. = FALSE)
  # (변수명을 extra 로 쓰지 않는다 — test_rf_mark_vintage.R 돌연변이가 빈티지 writer 의 그 줄을 문자열 1회로 찾는다)
  bad_keys <- setdiff(names(it), c("base_id", "n", "essence_new", "regime", "provenance", "regime_old"))
  if (length(bad_keys)) stop(sprintf("[reinforce_ledger] rebase 항목 #%d — 허용 밖 키 거부: %s (등급은 형제 파일에서만 온다)",
                                     k, paste(bad_keys, collapse = ",")), call. = FALSE)
  bid <- .rf_s1(it$base_id)
  if (!nzchar(bid)) stop(sprintf("[reinforce_ledger] rebase 항목 #%d — base_id 비었음", k), call. = FALSE)
  nk <- .rf_s1(it$n)
  if (!(identical(nk, "base") || grepl("^[0-9]+$", nk)))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — n 은 시도 번호 또는 \"base\": %s", k, nk), call. = FALSE)
  rg <- .rf_s1(it$regime)
  if (!grepl(RF_REGIME_LABEL_RE, rg))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — regime 이름 형식(%s): %s", k, RF_REGIME_LABEL_RE, rg), call. = FALSE)
  ro <- .rf_s1(it$regime_old)
  if (nzchar(ro) && !grepl(RF_REGIME_LABEL_RE, ro))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — regime_old 이름 형식: %s", k, ro), call. = FALSE)
  pv <- it$provenance
  if (!is.list(pv) || is.null(names(pv)) || any(!nzchar(names(pv))) || !nzchar(.rf_s1(pv$remeasure_path)))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — provenance$remeasure_path 필수(형제 판 없이 rebase 하지 않는다)", k), call. = FALSE)
  if (any(names(pv) %in% c("essence", "essence_grade", "grade", "authoritative_remeasure")) ||
      !all(vapply(pv, function(v) is.atomic(v) && length(v) <= 1L, logical(1))))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — provenance 는 스칼라 출처 필드만(essence·등급 객체 금지 · AX-008)", k), call. = FALSE)
  es <- it$essence_new
  if (identical(nk, "base")) {
    if (!is.null(es) && !is.list(es)) stop(sprintf("[reinforce_ledger] rebase 항목 #%d — base 의 essence_new 는 list 또는 NULL", k), call. = FALSE)
  } else if (!is.list(es) || !length(es) || is.null(names(es))) {
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — essence_new 필수(원장 요약 list)", k), call. = FALSE)
  }
  if (is.list(es) && any(c("essence_history", "grade", "essence_grade") %in% names(es)))
    stop(sprintf("[reinforce_ledger] rebase 항목 #%d — essence_new 에 history·등급 키 금지", k), call. = FALSE)
  list(base_id = bid, n = nk, essence_new = es, regime = rg, regime_old = ro, provenance = pv)
}
.rf_core_of_file <- function(fe) vapply(names(RF_REBASE_CORE), function(k) {
  for (src in RF_REBASE_CORE[[k]]) { v <- fe[[src]]
    if (!is.null(v)) return(tryCatch(suppressWarnings(as.numeric(unlist(v))[1]), error = function(e) NA_real_)) }
  NA_real_ }, numeric(1))
.rf_core_of_essence <- function(es) vapply(names(RF_REBASE_CORE), function(k) {
  v <- es[[k]]; if (is.null(v)) NA_real_ else tryCatch(suppressWarnings(as.numeric(unlist(v))[1]), error = function(e) NA_real_) },
  numeric(1))
.rf_core_equal <- function(a, b) all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= RF_REBASE_TOL))

#' 형제 판 측정 값 — RF_REBASE_MEAS 키마다 위치 목록에서 첫 비결측 값(형제에 없으면 그 키는 결과에 없다).
.rf_meas_of_file <- function(j) {
  out <- list()
  for (k in names(RF_REBASE_MEAS)) for (loc in RF_REBASE_MEAS[[k]]) {
    sp <- strsplit(loc, ":", fixed = TRUE)[[1]]
    src <- switch(sp[1], essence = j[["essence"]], top = j, mr = j[["measurement_regime"]], NULL)
    v <- if (is.list(src)) tryCatch(unlist(src[[sp[2]]]), error = function(e) NULL) else NULL
    if (is.null(v) || !length(v) || is.na(v[1]) || (is.character(v) && !nzchar(v[1]))) next
    out[[k]] <- v[1]
    break
  }
  out
}
#' rebase essence 조립기(정본 · L-B2) — 신원 키(구 essence 값) + 측정 키(형제 판 값 전부 · 형제에 없으면 뺀다) + source.
#'   드라이버(rf_rebase_driver.R)·검사가 essence_new 를 이 함수로 만들고, writer 는 같은 함수의 결과로 **다시 조립**해 쓴다
#'   (essence_new 는 대조용 주장 — 원장에 쓰이는 값은 늘 형제 판에서 온다).
#' @param sibling 형제 판 경로 또는 판독한 list
rf_rebase_essence_from_sibling <- function(old_essence, sibling) {
  j <- if (is.character(sibling)) .rf_read_json(sibling) else sibling
  if (!is.list(j)) stop("[reinforce_ledger] rebase essence 조립 — 형제 판 판독 불가", call. = FALSE)
  old <- if (is.list(old_essence)) old_essence else list()
  es <- list()
  for (k in RF_REBASE_ID_KEYS) if (!is.null(old[[k]])) es[[k]] <- old[[k]]
  m <- .rf_meas_of_file(j)
  for (k in names(m)) es[[k]] <- m[[k]]
  es$source <- "authoritative_remeasure.json(rebase)"
  es
}
#' essence_new(호출자 주장) 대조 → writer 조립값. 허용 밖 키·신원 불일치·측정 불일치(형제 판과 다름 · 형제에 없는 측정 값) = 거부.
.rf_rb_compose <- function(old_es, en, sib) {
  want <- rf_rebase_essence_from_sibling(old_es, sib$auth)
  en <- if (is.list(en)) en else list()
  foreign <- setdiff(names(en), c(RF_REBASE_ID_KEYS, names(RF_REBASE_MEAS), "source"))
  if (length(foreign))
    .rf_rb_reject("essence_new_foreign_keys", sprintf("essence_new 에 허용 밖 키 %s — 구 측정의 보조 값은 history 에만 남는다(새 essence 에 싣지 않는다)",
                                                      paste(foreign, collapse = ",")))
  old <- if (is.list(old_es)) old_es else list()
  for (k in intersect(names(en), RF_REBASE_ID_KEYS))
    if (!identical(en[[k]], old[[k]])) .rf_rb_reject("identity_mismatch", sprintf("essence_new 신원 키 %s 가 구 essence 와 다르다", k))
  for (k in intersect(names(en), names(RF_REBASE_MEAS))) {
    a <- tryCatch(unlist(en[[k]]), error = function(e) NULL); b <- want[[k]]
    a_na <- is.null(a) || !length(a) || is.na(a[1])
    same <- if (is.null(b)) a_na else if (a_na) FALSE else if (is.numeric(b)) {
      av <- suppressWarnings(as.numeric(a[1])); if (is.finite(b)) is.finite(av) && abs(av - b) <= RF_REBASE_TOL else identical(av, as.numeric(b))
    } else identical(as.character(a[1]), as.character(b))
    if (!isTRUE(same))
      .rf_rb_reject(paste0("essence_mismatch:", k), sprintf("essence_new %s=%s ≠ 형제 판 %s — 측정 값은 형제 판에서만 온다",
                                                            k, paste(format(a), collapse = ","), if (is.null(b)) "(형제에 없음)" else format(b)))
  }
  want
}

#' 형제 판 검증 — 위치(칸 artifacts 바로 아래 remeasure_<regime>/) · regime 키 · 등급 · 핵심 지표.
.rf_rb_sibling <- function(artifacts, it, root) {
  if (is.list(artifacts))
    .rf_rb_reject("artifacts_form", "artifacts 가 디렉터리가 아니다(WT 시기 dict) — 형제 판을 특정할 수 없다")
  d <- .rf_abs_path(artifacts, root)
  if (is.na(d) || !dir.exists(d)) .rf_rb_reject("artifacts_unresolvable", sprintf("칸 산출물 디렉터리 부재: %s", .rf_s1(artifacts)))
  f <- .rf_abs_path(it$provenance$remeasure_path, root)
  if (is.na(f) || !file.exists(f)) .rf_rb_reject("remeasure_absent", sprintf("형제 판 부재: %s", .rf_s1(it$provenance$remeasure_path)))
  if (!identical(tolower(basename(f)), "authoritative_remeasure.json"))
    .rf_rb_reject("remeasure_name", sprintf("형제 판은 authoritative_remeasure.json 이어야 한다: %s", basename(f)))
  if (!identical(basename(dirname(f)), paste0("remeasure_", it$regime)))
    .rf_rb_reject("regime_dir_mismatch", sprintf("형제 판 디렉터리 %s ≠ remeasure_%s", basename(dirname(f)), it$regime))
  if (!.rf_same_path(dirname(dirname(f)), d))
    .rf_rb_reject("not_sibling", sprintf("형제가 아니다 — %s 는 이 칸(%s) 아래가 아니다", f, d))
  j <- .rf_read_json(f)
  if (is.null(j)) .rf_rb_reject("remeasure_parse", sprintf("형제 판 파손: %s", f))
  if (!is.list(j$measurement_regime))
    .rf_rb_reject("remeasure_regime_absent", "형제 판에 measurement_regime 이 없다 — 규약을 모르는 판으로 rebase 하지 않는다")
  rk <- .rf_regime_key(j)
  if (!identical(rk$regime, it$regime))
    .rf_rb_reject("regime_mismatch", sprintf("형제 판 regime 키 %s ≠ 인자 regime %s", as.character(rk$regime), it$regime))
  g <- .rf_s1(j$essence_grade)
  if (!nzchar(g)) .rf_rb_reject("grade_absent", "형제 판에 essence_grade(권위 등급)가 없다")
  if (!is.list(j[["essence"]])) .rf_rb_reject("remeasure_essence_absent", "형제 판에 essence 가 없다")
  core <- .rf_core_of_file(j[["essence"]])
  if (!any(is.finite(core))) .rf_rb_reject("remeasure_core_na", "형제 판 핵심 지표가 전부 NA")
  list(path = f, md5 = unname(tools::md5sum(f)), auth = j, grade = g, core = core)
}
.rf_rb_regime_old <- function(derived, it) {
  if (is.na(derived$regime)) {
    if (nzchar(it$regime_old)) return(list(regime = it$regime_old, basis = paste0("caller(", derived$basis, ")")))
    .rf_rb_reject("regime_old_unknown", sprintf("구 regime 재도출 불가(%s) — regime_old 를 명시하라", derived$basis))
  }
  if (nzchar(it$regime_old) && !identical(it$regime_old, derived$regime))
    .rf_rb_reject("regime_old_conflict", sprintf("호출자 regime_old %s ≠ 재도출 %s(%s)", it$regime_old, derived$regime, derived$basis))
  derived
}
.rf_rb_mr_new <- function(sib, it, now) {
  mr <- sib$auth$measurement_regime; if (!is.list(mr)) mr <- list()
  mr$regime <- it$regime; mr$basis <- "rebase"; mr$remeasure_path <- sib$path; mr$remeasure_md5 <- sib$md5; mr$rebased_at <- now
  mr
}

.rf_rb_apply_attempt <- function(obj, i, it, blocked, root, now) {
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts %||% list(), function(a) identical(as.integer(a$n), as.integer(it$n)), logical(1)))
  if (!length(j)) .rf_rb_reject("attempt_absent", sprintf("attempt n=%s 부재", it$n))
  j <- j[1]; a <- e$attempts[[j]]
  if (is.null(a[["essence"]])) .rf_rb_reject("unmeasured", "미측정 칸(essence 없음) — rebase 대상 아님")
  hit <- .rf_flags_hit(a$vintage_flags, blocked)
  if (length(hit))
    .rf_rb_reject(paste0("blocked_flag:", paste(hit, collapse = "+")),
                  sprintf("PIT 표식 칸(%s) — P0-05·06 재측정 경로 비편입(결정 PIT-C11-CONVENTIONS ⑧: 오염 선택은 보유 재측정으로 씻기지 않는다)",
                          paste(hit, collapse = ",")))
  sib <- .rf_rb_sibling(a$artifacts, it, root)
  if (!.rf_core_equal(.rf_core_of_essence(it$essence_new), sib$core))
    .rf_rb_reject("essence_mismatch", "essence_new 핵심 지표가 형제 판과 다르다")
  # ★칸 라벨 = 구 essence$cell_code(없으면 격자 좌표 attempt$cell_code). 승격 기록 parent$cell 이 이 값에서 온다
  #   (reinforce_auto_next_paper.R best$cell_code = essence$cell_code). B4 결합 칸은 두 라벨이 다르다(운영 원장 실측 30칸 —
  #   essence 는 빠뜨린 축의 칸을 적는다) — 격자 좌표로 대조하면 정상 칸이 거부되고 자식 매칭이 빗나간다(사본 검사 C3 에서 실측).
  .cl_of <- function(x) { ce <- .rf_s1((x[["essence"]] %||% list())$cell_code); if (nzchar(ce)) ce else .rf_s1(x$cell_code) }
  cc <- .cl_of(a)
  cn <- .rf_s1(it$essence_new$cell_code)
  if (nzchar(cc) && nzchar(cn) && !identical(cc, cn))
    .rf_rb_reject("cell_mismatch", sprintf("essence_new cell_code %s ≠ 구 essence 칸 %s", cn, cc))
  es_new <- .rf_rb_compose(a[["essence"]], it$essence_new, sib)     # ★L-B2 — 원장에 쓰는 값 = writer 조립(형제 판)
  ro <- .rf_rb_regime_old(rf_attempt_regime(a, root), it)
  H <- a$essence_history
  if (!is.null(H) && !is.list(H)) .rf_rb_reject("history_malformed", "essence_history 형식 불량")
  if (identical(ro$regime, it$regime)) {
    mr <- a$measurement_regime
    if (is.list(mr) && identical(.rf_s1(mr$remeasure_md5), sib$md5) &&
        .rf_core_equal(.rf_core_of_essence(a[["essence"]]), sib$core) && identical(.rf_s1(a$grade), sib$grade))
      return(list(obj = obj, status = "already", regime_old = ro$regime, touch_att = NULL, kids = integer(0)))
    .rf_rb_reject("same_regime_overwrite",
                  sprintf("이미 regime %s(%s) — 같은 regime 으로 다른 판을 쓰면 history 없이 덮어쓴다(새 regime 이름으로)", ro$regime, ro$basis))
  }
  if (!is.null(H[[ro$regime]]))
    .rf_rb_reject("history_exists", sprintf("essence_history[[%s]] 가 이미 있다 — append-only(덮어쓰기 0)", ro$regime))
  if (!is.null(H[[it$regime]]))
    .rf_rb_reject("regime_in_history", sprintf("regime %s 는 이미 history 에 있다 — 새 regime 이름으로", it$regime))
  rec <- list(essence = a[["essence"]], grade = a[["grade"]])
  for (f in setdiff(RF_REBASE_REGIME_FIELDS, c("essence", "grade"))) if (!is.null(a[[f]])) rec[[f]] <- a[[f]]
  if (!is.null(a$artifacts)) rec$artifacts <- a$artifacts
  rec$regime <- ro$regime; rec$regime_basis <- ro$basis; rec$moved_at <- now; rec$superseded_by <- it$regime
  H2 <- if (is.list(H)) H else list()
  H2[[ro$regime]] <- rec
  a$essence <- es_new
  a$grade   <- sib$grade
  gb <- .rf_s1(sib$auth$grade_base)
  a$grade_base <- if (nzchar(gb)) gb else NULL
  a$retro <- NULL; a$retro_inherited <- NULL
  a$measurement_regime <- .rf_rb_mr_new(sib, it, now)
  a$essence_history <- H2
  a$rebase_log <- c(if (is.list(a$rebase_log)) a$rebase_log else list(),
                    list(list(at = now, from = ro$regime, to = it$regime, remeasure_path = sib$path, remeasure_md5 = sib$md5,
                              provenance = it$provenance)))
  obj$entries[[i]]$attempts[[j]] <- a
  # 자식 entry 의 parent$best_* — 이 칸이 그 자식을 낳은 승자면 새 regime 값으로
  kids <- integer(0)
  if (nzchar(cc)) {
    same_cell <- which(vapply(e$attempts, function(x) identical(.cl_of(x), cc), logical(1)))
    for (k2 in seq_along(obj$entries)) {
      pr <- obj$entries[[k2]]$parent
      if (!is.list(pr) || !identical(.rf_s1(pr$base_id), it$base_id) || !identical(.rf_s1(pr$cell), cc)) next
      if (length(same_cell) > 1L) {   # 같은 칸 코드가 여럿이면 승자 = 구 port_t 가 기록과 같은 시도만
        op <- suppressWarnings(as.numeric(rec$essence$port_t)); bp <- suppressWarnings(as.numeric(pr$best_port_t))
        if (!(length(op) && length(bp) && is.finite(op[1]) && is.finite(bp[1]) && abs(op[1] - bp[1]) <= RF_REBASE_TOL)) next
      }
      bk <- grep("^best_", names(pr), value = TRUE)
      before <- pr[bk]; after <- list()
      for (b in bk) { nv <- es_new[[sub("^best_", "", b)]]; if (!is.null(nv)) { pr[[b]] <- nv; after[[b]] <- nv } }
      if (!length(after)) next
      obj$entries[[k2]]$parent <- pr
      prf <- obj$entries[[k2]]$parent_rebased_from
      obj$entries[[k2]]$parent_rebased_from <- c(if (is.list(prf)) prf else list(), list(list(
        at = now, parent_base_id = it$base_id, cell = cc, n = as.integer(it$n),
        regime_old = ro$regime, regime_new = it$regime, before = before, after = after)))
      kids <- c(kids, k2)
    }
  }
  list(obj = obj, status = "rebased", regime_old = ro$regime, touch_att = c(i, j), kids = kids)
}

.rf_rb_apply_base <- function(obj, i, it, blocked, root, now) {
  e <- obj$entries[[i]]
  hit <- .rf_flags_hit(e$base_vintage_flags, blocked)
  if (length(hit))
    .rf_rb_reject(paste0("blocked_flag:", paste(hit, collapse = "+")),
                  sprintf("PIT 표식 기저(%s) — P0-05·06 재측정 경로 비편입(결정 PIT-C11-CONVENTIONS ⑧)", paste(hit, collapse = ",")))
  sib <- .rf_rb_sibling(e$base_artifacts, it, root)
  if (is.list(it$essence_new) && length(it$essence_new) &&
      !.rf_core_equal(.rf_core_of_essence(it$essence_new), sib$core))
    .rf_rb_reject("essence_mismatch", "essence_new 핵심 지표가 형제 판과 다르다")
  if (is.list(it$essence_new) && length(it$essence_new)) invisible(.rf_rb_compose(list(), it$essence_new, sib))   # L-B2 같은 대조
  ro <- .rf_rb_regime_old(rf_base_regime(e, root), it)
  H <- e$base_essence_history
  if (!is.null(H) && !is.list(H)) .rf_rb_reject("history_malformed", "base_essence_history 형식 불량")
  if (identical(ro$regime, it$regime)) {
    if (is.list(e$base_remeasure) && identical(.rf_s1(e$base_remeasure$md5), sib$md5) && identical(.rf_s1(e$base_grade), sib$grade))
      return(list(obj = obj, status = "already", regime_old = ro$regime, touch_base = NULL))
    .rf_rb_reject("same_regime_overwrite", sprintf("기저가 이미 regime %s(%s) — 새 regime 이름으로", ro$regime, ro$basis))
  }
  if (!is.null(H[[ro$regime]]))
    .rf_rb_reject("history_exists", sprintf("base_essence_history[[%s]] 가 이미 있다 — append-only", ro$regime))
  if (!is.null(H[[it$regime]]))
    .rf_rb_reject("regime_in_history", sprintf("regime %s 는 이미 기저 history 에 있다", it$regime))
  rec <- list(base_grade = e$base_grade)
  for (f in setdiff(RF_REBASE_BASE_FIELDS, "base_grade")) if (!is.null(e[[f]])) rec[[f]] <- e[[f]]
  if (!is.null(e$base_artifacts)) rec$base_artifacts <- e$base_artifacts
  rec$regime <- ro$regime; rec$regime_basis <- ro$basis; rec$moved_at <- now; rec$superseded_by <- it$regime
  H2 <- if (is.list(H)) H else list()
  H2[[ro$regime]] <- rec
  e$base_grade <- sib$grade
  e$base_measurement_regime <- .rf_rb_mr_new(sib, it, now)
  e$base_remeasure <- list(path = sib$path, md5 = sib$md5, grade = sib$grade, core = as.list(sib$core[is.finite(sib$core)]))
  e$base_essence_history <- H2
  e$base_rebase_log <- c(if (is.list(e$base_rebase_log)) e$base_rebase_log else list(),
                         list(list(at = now, from = ro$regime, to = it$regime, remeasure_path = sib$path, remeasure_md5 = sib$md5,
                                   provenance = it$provenance)))
  obj$entries[[i]] <- e
  list(obj = obj, status = "rebased", regime_old = ro$regime, touch_base = i)
}

#' 보호 투영 — 이번 배치가 만질 수 있는 필드만 뺀 원장. 두 투영이 identical 이면 그 밖의 변경 0.
.rf_rb_strip <- function(obj, att, base, kids) {
  obj$last_updated <- NULL
  for (t in att) {
    ij <- t$ij
    a <- obj$entries[[ij[1]]]$attempts[[ij[2]]]
    for (f in c(RF_REBASE_REGIME_FIELDS, "essence_history", "rebase_log")) a[[f]] <- NULL
    obj$entries[[ij[1]]]$attempts[[ij[2]]] <- a
  }
  for (i in base) {
    e <- obj$entries[[i]]
    for (f in c(RF_REBASE_BASE_FIELDS, "base_essence_history", "base_rebase_log")) e[[f]] <- NULL
    obj$entries[[i]] <- e
  }
  for (i in unique(kids)) {
    e <- obj$entries[[i]]
    if (is.list(e$parent) && length(e$parent)) e$parent <- e$parent[!startsWith(names(e$parent), "best_")]
    e$parent_rebased_from <- NULL
    obj$entries[[i]] <- e
  }
  obj
}
#' append-only 전수 대조 — 기존 history·log 원소는 한 비트도 바뀌지 않고 순서대로 남아 있어야 한다(모든 칸).
.rf_rb_history_kept <- function(orig, obj) {
  .prefix <- function(o, n) { if (!is.list(o) || !length(o)) return(TRUE)
                              is.list(n) && length(n) >= length(o) && identical(n[seq_along(o)], o) }
  .named <- function(o, n) { if (!is.list(o) || !length(o)) return(TRUE)
                             is.list(n) && all(vapply(names(o), function(k) identical(n[[k]], o[[k]]), logical(1))) }
  for (i in seq_along(orig$entries)) {
    eo <- orig$entries[[i]]; en <- obj$entries[[i]]
    if (!.named(eo$base_essence_history, en$base_essence_history) || !.prefix(eo$base_rebase_log, en$base_rebase_log) ||
        !.prefix(eo$parent_rebased_from, en$parent_rebased_from)) return(FALSE)
    for (j in seq_along(eo$attempts)) {
      ao <- eo$attempts[[j]]; an <- en$attempts[[j]]
      if (!.named(ao$essence_history, an$essence_history) || !.prefix(ao$rebase_log, an$rebase_log)) return(FALSE)
    }
  }
  TRUE
}

#' rebase 배치 writer
#' @param items list(list(base_id, n = 시도 번호 | "base", essence_new = 원장 요약 list(base 는 선택),
#'   regime = 새 regime 이름, provenance = list(remeasure_path = 형제 판 경로, ...스칼라 출처), regime_old = 선택 대조값))
#' @param skip_rejected TRUE 면 거부 칸을 사유 코드와 함께 items 결과에 남기고 나머지를 쓴다(기본 FALSE = 하나라도 거부면 0 쓰기)
#' @param dry_run TRUE 면 잠금·쓰기 없이 검증과 결과만
#' @return list(n_rebased, n_already, n_rejected, n_children, written, md5_before, md5_after, items)
rf_rebase_essence_batch <- function(layer, items, root = .rf_root(), claim = NULL,
                                    wait_s = RF_LEDGER_CLAIM_WAIT_S, poll_s = RF_LEDGER_CLAIM_POLL_S,
                                    skip_rejected = FALSE, dry_run = FALSE,
                                    backup_to = NULL, snapshot_after_to = NULL, .pre_write_hook = NULL) {
  stopifnot(layer %in% c(1L, 2L))
  if (!length(items)) stop("[reinforce_ledger] rebase — items 가 비었다", call. = FALSE)
  IT <- lapply(seq_along(items), function(k) .rf_rb_item(items[[k]], k))      # I/O 전 전수 형식 검증
  keys <- vapply(IT, function(x) paste0(x$base_id, "#", x$n), character(1))
  if (anyDuplicated(keys)) stop(sprintf("[reinforce_ledger] rebase — 같은 칸이 배치에 두 번: %s",
                                        paste(unique(keys[duplicated(keys)]), collapse = ",")), call. = FALSE)
  blocked <- rf_rebase_block_flags(root)
  hold <- if (isTRUE(dry_run)) NULL else .rf_ledger_claim(root, claim, wait_s, poll_s, "rebase")
  if (!is.null(hold)) on.exit(hold$release(), add = TRUE)
  p <- .rf_path(layer, root)
  if (!file.exists(p)) stop("[reinforce_ledger] rebase — 원장 부재: ", p, call. = FALSE)
  md5_a <- unname(tools::md5sum(p)); raw_a <- readBin(p, "raw", file.info(p)$size)
  if (!isTRUE(dry_run) && !is.null(backup_to)) {
    writeBin(raw_a, backup_to)
    if (!identical(unname(tools::md5sum(backup_to)), md5_a))
      stop("[reinforce_ledger] rebase — 쓰기 전 백업 대조 실패 — 쓰지 않는다: ", backup_to, call. = FALSE)
  }
  orig <- rf_load(layer, root); obj <- orig
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  att <- list(); base <- integer(0); kids <- integer(0); res <- vector("list", length(IT))
  for (k in seq_along(IT)) {
    it <- IT[[k]]
    r <- tryCatch({
      i <- .rf_find(obj, it$base_id)
      if (is.na(i)) .rf_rb_reject("entry_absent", sprintf("entry 부재: %s", it$base_id))
      if (identical(it$n, "base")) .rf_rb_apply_base(obj, i, it, blocked, root, now)
      else .rf_rb_apply_attempt(obj, i, it, blocked, root, now)
    }, rf_rb_reject = function(cnd) cnd)
    if (inherits(r, "rf_rb_reject")) {
      if (!isTRUE(skip_rejected))
        stop(sprintf("[reinforce_ledger] rebase 거부 #%d %s [%s] — %s — 배치 전체를 쓰지 않았다", k, keys[k], r$code,
                     conditionMessage(r)), call. = FALSE)
      res[[k]] <- list(key = keys[k], status = "rejected", code = r$code, reason = conditionMessage(r))
      next
    }
    obj <- r$obj
    if (!is.null(r$touch_att)) att[[length(att) + 1L]] <- list(ij = r$touch_att, ro = r$regime_old)
    if (!is.null(r$touch_base)) base <- c(base, r$touch_base)
    kids <- c(kids, r$kids %||% integer(0))
    res[[k]] <- list(key = keys[k], status = r$status, regime_old = r$regime_old, regime = it$regime,
                     n_children = length(r$kids %||% integer(0)))
  }
  st <- vapply(res, function(x) x$status, character(1))
  out <- list(n_rebased = sum(st == "rebased"), n_already = sum(st == "already"), n_rejected = sum(st == "rejected"),
              n_children = length(kids), written = FALSE, md5_before = md5_a, md5_after = md5_a, items = res)
  if (out$n_rebased == 0L) return(invisible(out))

  # ── 보호 투영 · append-only · 구판 보존(비트) — 메모리 + 직렬화 왕복 ────────────────────
  if (!identical(.rf_rb_strip(obj, att, base, kids), .rf_rb_strip(orig, att, base, kids)))
    stop("[reinforce_ledger] rebase — 허용 필드 밖이 바뀌었다(보호 투영 불일치) — 쓰지 않는다", call. = FALSE)
  if (!.rf_rb_history_kept(orig, obj))
    stop("[reinforce_ledger] rebase — 기존 history/log 원소가 바뀌었다(append-only 위반) — 쓰지 않는다", call. = FALSE)
  .moved_ok <- function(x) all(vapply(att, function(t) { ij <- t$ij; rk <- t$ro
    ao <- orig$entries[[ij[1]]]$attempts[[ij[2]]]; an <- x$entries[[ij[1]]]$attempts[[ij[2]]]
    identical(an$essence_history[[rk]]$essence, ao$essence) && identical(an$essence_history[[rk]]$grade, ao$grade) }, logical(1)))
  if (!.moved_ok(obj)) stop("[reinforce_ledger] rebase — 구 essence 가 history 로 비트 그대로 옮겨지지 않았다 — 쓰지 않는다", call. = FALSE)
  .rt <- fromJSON(toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), simplifyVector = FALSE)
  if (!identical(.rf_rb_strip(.rt, att, base, kids), .rf_rb_strip(orig, att, base, kids)) ||
      !.rf_rb_history_kept(orig, .rt) || !.moved_ok(.rt))
    stop("[reinforce_ledger] rebase — 직렬화 왕복이 보호 값·구판 history 를 바꾼다 — 쓰지 않는다", call. = FALSE)
  if (isTRUE(dry_run)) return(invisible(out))

  if (is.function(.pre_write_hook)) .pre_write_hook(p)
  if (!identical(unname(tools::md5sum(p)), md5_a))
    stop("[reinforce_ledger] rebase — 적재 뒤 원장이 바뀌었다(claim 밖 쓰기) — 덮어쓰지 않는다. 재시도하라", call. = FALSE)
  .rf_write(obj, layer, root)
  back <- tryCatch(rf_load(layer, root), error = function(e) NULL)
  .nl <- function(x) { x$last_updated <- NULL; x }
  if (is.null(back) || !identical(.nl(back), .nl(.rt))) {
    .rf_restore_bytes(p, raw_a, "rebase")
    stop("[reinforce_ledger] rebase — 사후 재적재 대조 실패, 원본 바이트로 되돌렸다", call. = FALSE)
  }
  out$written <- TRUE; out$md5_after <- unname(tools::md5sum(p))
  if (!is.null(snapshot_after_to)) file.copy(p, snapshot_after_to, overwrite = TRUE)
  cat(sprintf("[reinforce_ledger] rebase L%d: %d칸 · 멱등 %d · 거부 %d · 자식 parent 갱신 %d (보호 투영·history 보존 확인)\n",
              layer, out$n_rebased, out$n_already, out$n_rejected, out$n_children))
  invisible(out)
}

#' 단건 wrapper — rf_rebase_essence(layer, base_id, n, essence_new, regime, provenance)
rf_rebase_essence <- function(layer, base_id, n, essence_new, regime, provenance, root = .rf_root(), regime_old = NULL, ...) {
  it <- list(base_id = base_id, n = n, essence_new = essence_new, regime = regime, provenance = provenance)
  if (!is.null(regime_old)) it$regime_old <- regime_old
  rf_rebase_essence_batch(layer, list(it), root = root, ...)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[reinforce_ledger.R] Loaded (v10) — rf_open_entry / rf_append_attempt(★L1 25회 게이트·서술 의무 · root_papers 선택) / rf_record_result / rf_park_entry(조기 중단·사유 필수) / rf_record_judge / rf_record_combination_review / rf_lessons_digest / rf_record_adversary(G2 오버레이 반증 표식) / rf_record_b5_redesign(B5 재설계 라운드 표식) / rf_rebase_essence(_batch)(P0-06 · history append-only) / rf_mark_axis_epoch(relabel_from · require_regime · claim) / rf_graduate_entry(보류 A 졸업)\n")
