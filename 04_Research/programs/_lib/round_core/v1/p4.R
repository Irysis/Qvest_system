## round_core v1 · p4 — P4 강화 사슬(p4_chain · v10.2 사다리 루프 · 2026-11-10 도훈 지시)
##
## 왜: "충실구현 레인이 찾아내는 알파 기저로 BOOK_0001급 전략을 1계층 강화 프로세스가 재귀적 자기개선으로 스스로 찾게 하라."
##   P4 조립 · 처방 루프는 0회였다 — 골격이 P0 하나에 묶였고(prepare_analyst.R), 사슬형(한 걸음 = 가설 하나 → 칸 하나) 구현 ·
##   상설 자격 → P4 배선 · 격차(병목 하한) 입력 · 결과 원장 소비 · 생성기 판 관리가 없었다(전수점검 지도 고리 1 · 2 · 3 · 7 · 8 · 9).
## 무엇: 한 사슬 = 기저 엔진 1개에서 출발해 한 걸음에 가설 하나 · 칸 하나 · 블록 유형 하나씩 얹는 순차 루프.
##   ① 기저 풀 rc_p4_base_pool — 등록부 kind = engine 재료 + P1 상설 자격 원장 → 자격(상설 통과 ∨ 권위 등급 A/B) · 제외 사유 코드
##   ② 격차 rc_p4_gap — 보는 창(≤ τ_D) 지표만 등급 계약(gv3_window · gv3_thresholds · gv3_S)으로 → A 하한별 값 · 문턱 · 여유 · 병목
##   ③ 사슬 판 chain_spec.json(rc_p4_chain_v1) — 채택 규칙(보는 창 지표만 · 정본 참조 + 출처 문구) · 예산 · 생성기 판 핀 · 최종 후보 규칙
##      판은 한 번 등록(rc_p4_chain_register — 사양 md5 · 해석된 규칙 · 기저 보는 창 지표를 원장 첫 줄에)하고 걸음은 흐른다(상설 판과 같은 발상)
##   ④ 걸음 원장 chain_steps.jsonl — 추가 전용 · 앞 줄 md5 사슬(standing.R 원장 방식) · step_open 기계 검사 · step_decide 기계 판정
##   ⑤ 설계 입력 rc_p4_design_input — 생성기(처방 에이전트)에게 줄 md(보는 창 정보만 · τ_D 날짜 · 등급 표기 검사)
##   ⑥ 닫기 rc_p4_close — 최종 후보 = 마지막 채택 걸음 · 결과 원장 기록 · 마감 훅(selection_regrade.R::sr_regrade 가 있으면)
##   ⑦ 생성기 판 rxg_* — 06_Registry/rx_generator.json(추가 전용) · 생성기 검토 rc_p4_generator_review
##   (11-10 실운용 연결) 기저 칸 사양 rc_p4_base_cell_spec(P1 표준 구성 생성기 재사용) · 걸음 측정 rc_p4_step_measure(정본 셀 워커 · 배리어 ·
##   스윕 시행 회계 · step_measured) · 감독 영수증(등록 P1 · T1 / 닫기 P2 · T2 / 생성기 개정 철학 의견 — register.R::rc_p1_check 재사용) ·
##   닫기 후보 관문(round_candidate_gate.R::rcg_route — 새 등급 A 일 때 · finalize.json 에만)
## 경계: 루프가 고쳐 쓰는 것은 생성기(프롬프트 파일)뿐이다 — 판정 규칙(채택 규칙 · 예산)은 사슬 판에 고정되고, 바꾸려면 새 사슬 판을 등록한다.
##   수치는 R 계약 산출만(AX-008). 칸 측정은 정본 셀 워커(rf_cell_worker.R)에 맡기고 결과 경로만 원장에 남긴다. 시험 창 값은 계산도 반환도 하지 않는다.

RC_P4_CHAIN_SCHEMA <- "rc_p4_chain_v1"
RC_P4_STEPS_SCHEMA <- "rc_p4_chain_steps_v1"
RC_P4_POOL_SCHEMA  <- "rc_p4_pool_v1"
RC_P4_PROGRAM <- "P4_ASSEMBLY"
RC_P4_BLOCK_TYPES <- c("base", "blend", "regime_exposure", "tail_overlay", "weighting", "construction", "defense_sleeve", "universe", "rebalance")
## 칸 사양 축 → 그 축을 바꾸는 블록 유형(base_signal 은 새 값의 kind 로 가른다 — engine_blend = blend · 그 밖 = base)
RC_P4_KEY_BLOCKS <- list(factors = "blend", base_weight = "blend", overlay = c("regime_exposure", "tail_overlay"),
                         overlay_shift = c("regime_exposure", "tail_overlay"), weighting = "weighting", cap_core = "construction",
                         defense_sleeve = "defense_sleeve", universe = "universe", rebalance = "rebalance")
RC_P4_META_KEYS <- c("code", "label", "idea", "block", "selection_accounting", "root_paper", "root_papers", "root_paper_families",
                     "unmapped_families", "preflight", "notes", "p4")
## 채택 규칙이 쓸 수 있는 판정 표 열(전부 보는 창 · d* = 걸음 − 부모)
RC_P4_METRICS <- c("S_vis", "dS_vis", "calmar_vis", "port_t_vis", "cagr_vis", "sharpe_vis", "mdd_vis",
                   "uc_vis", "d_uc_vis", "dd_capture_median_vis", "d_dd_capture_median_vis")
RC_P4_FORBIDDEN_METRIC_RX <- "(test|_tw$|oos|full|overall|lifetime|_all$)"
RC_P4_REASONS <- c(
  not_qualified = "자격 없음 — P1 상설 자격 통과도 아니고 권위 등급(authoritative_remeasure.json::essence_grade)이 A/B 도 아니다(미측정 = 자격 없음)",
  implementation_suspect = "구현 의심 꼬리표(재구현 뒤 감사 기각 · 보유 대조 어긋남) — 꼬리표 판독 불가도 제외",
  audit_not_passed = "충실도 감사 판정이 faithful · adapted 밖",
  no_engine = "엔진 파일 없음",
  needs_long_leg = "롱숏(또는 롱온리 확인 불가) 엔진인데 롱 다리 변환이 없다 — 상설 자격(표준 구성 롱온리 측정 통과)으로만 들어온다",
  standing_engine_changed = "상설 자격 판정 뒤 엔진 파일이 바뀌었다(넣을 때 md5 ≠ 지금)",
  factor_db_stale = "팩터 DB 판 낡음(contracts/factor_db_vintage.R::fdv_stale = TRUE) — 재측정 전 기저로 쓰지 않는다")

.rcp4_err <- function(...) stop(paste0("[round_core p4] ", ...), call. = FALSE)
.rcp4_num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))); if (length(v) == 1L) v else NA_real_ }
.rcp4_txt <- function(x) { v <- unlist(x); length(v) == 1L && is.character(v) && !is.na(v) && nzchar(trimws(v)) }
.rcp4_tau <- function(root) as.character(rc_ref_value("06_Registry/behavior_card.json::tau_d", root))

## 저장소 상대 경로(한글 경로를 깨는 정규화 함수 금지 — 구분자 치환 + 최상위 폴더 표식). 다른 기기 절대 경로(C:\Users\99922\OneDrive\… = G:\OneDrive\… 정션)도
##   저장소 최상위 폴더(0x_* · stage_artifacts) 표식으로 상대화한다. 저장소 밖(임시 폴더)은 그대로.
.rcp4_rel <- function(p, root = rc_root()) {
  if (is.null(p) || !length(p) || is.na(p[1]) || !nzchar(p[1])) return(NA_character_)
  p <- gsub("\\\\", "/", as.character(p[1])); r <- rc_rel(p, root)
  if (!grepl("^([A-Za-z]:|/)", r)) return(r)
  m <- regmatches(r, regexec("^.*?/((0[0-9]_[^/]+|stage_artifacts)/.*)$", r, perl = TRUE))[[1]]
  if (length(m) == 3L) m[2] else r
}
.rcp4_abs <- function(p, root = rc_root()) if (is.na(p)) NA_character_ else rc_abs(p, root)

## 처방 입력 문서 검사(fail-closed) — τ_D 뒤 날짜(일 · 연월) · 등급 표기(rx_round.R .rx_assert_clean 과 같은 규칙)
.rcp4_assert_clean <- function(txt, tau, what) {
  txt <- iconv(paste(unlist(txt), collapse = "\n"), from = "UTF-8", to = "UTF-8", sub = "")
  if (is.na(txt)) .rcp4_err(what, " 인코딩 판독 불가(fail-closed)")
  lk <- rc_after_tau_leaks(txt, tau)
  gr <- regmatches(txt, gregexpr("(등급|Grade|grade)\\s*[ABCF](?![A-Za-z])", txt, perl = TRUE))[[1]]
  if (length(lk) || length(gr)) .rcp4_err(what, " 에 처방 입력 금지 정보: τ_D 뒤 날짜 ", paste(head(lk, 5), collapse = ","), " · 등급 표기 ", paste(head(gr, 5), collapse = ","))
  invisible(TRUE)
}

## ── ① 기저 풀 ───────────────────────────────────────────────────────────────
## 팩터 DB 판 검사(contracts/factor_db_vintage.R::fdv_stale) — 계약 파일이 있으면 부르고, 없으면 건너뛴다(NA · 실패하지 않는다)
.RCP4 <- new.env(parent = emptyenv())
##   fdv_ledger_path = 수리 원장 경로(기본 = 계약 기본 06_Registry/factor_db_vintage.json · 시험은 임시 원장)
##   판정 불가(stale = NA · 측정 시각 모름 · 오류)는 제외하지 않는다 — 계약이 '호출자가 정한다'고 둔 칸이고, 사유는 reason_detail 에 남긴다.
.rcp4_fdv <- function(dir, root, fdv_ledger_path = NULL) {
  f <- file.path(root, "02_Infrastructure/contracts/factor_db_vintage.R")
  if (!file.exists(f) || is.na(dir)) return(list(stale = NA, reason = if (!file.exists(f)) "fdv_contract_absent" else "no_artifacts"))
  if (!identical(.RCP4$fdv_root, root)) { e <- new.env(parent = globalenv())
    invisible(utils::capture.output(suppressMessages(sys.source(f, envir = e, keep.source = FALSE)))); .RCP4$fdv <- e; .RCP4$fdv_root <- root }
  r <- tryCatch({ L <- if (is.null(fdv_ledger_path)) NULL else .RCP4$fdv$fdv_ledger(root, path = fdv_ledger_path)
                  .RCP4$fdv$fdv_stale(dir, root, ledger = L) }, error = function(e) list(stale = NA, reason = paste("error:", conditionMessage(e))))
  list(stale = if (is.logical(r$stale) && length(r$stale) == 1L) r$stale else NA, reason = as.character(r$reason %||% NA_character_)[1])
}
## 권위 등급(authoritative_remeasure.json::essence_grade 만 · 손계산 없음 · 파일 없으면 NA = 미측정)
.rcp4_grade <- function(art_abs) {
  if (is.na(art_abs)) return(NA_character_)
  f <- file.path(art_abs, "authoritative_remeasure.json"); if (!file.exists(f)) return(NA_character_)
  g <- tryCatch(rc_json_read(f)[["essence_grade"]], error = function(e) NULL)
  if (is.character(g) && length(g) == 1L && g %in% c("A", "B", "C", "F")) g else NA_character_
}
## 등록부 kind = engine 항목(모든 프로그램 큐 · 소비 목록 · 미분류 보류)
.rcp4_registry_engines <- function(reg) {
  one <- function(it, prog, where) {
    if (!identical(.rcs_str(it[["kind"]]), "engine")) return(NULL)
    setDT(list(key = .rcs_str(it[["key"]]), program = prog, where = where, engine_raw = .rcs_str(it[["engine_path"]]),
               artifacts_raw = .rcs_str(it[["artifacts"]]), has_short = .rcs_lgl(it[["has_short"]]),
               implementation_suspect = .rcs_lgl(it[["implementation_suspect"]]), holdings_claim_mismatch = .rcs_lgl(it[["holdings_claim_mismatch"]]),
               audit_verdict = .rcs_str(it[["audit_verdict"]]), paper_key = .rcs_str(it[["paper_key"]]), title = .rcs_str(it[["title"]]),
               at = .rcs_str(it[["enqueued_at"]] %||% it[["held_at"]])))
  }
  rows <- list()
  for (p in reg[["programs"]] %||% list()) for (w in c("queue", "consumed")) for (it in p[[w]] %||% list()) rows[[length(rows) + 1L]] <- one(it, .rcs_str(p[["id"]]), w)
  for (it in reg[["paper_routing"]][["unrouted"]] %||% list()) rows[[length(rows) + 1L]] <- one(it, NA_character_, "unrouted")
  rows <- Filter(Negate(is.null), rows)
  if (length(rows)) rbindlist(rows, fill = TRUE) else NULL
}
#' 기저 풀 — 열: key · engine_path(저장소 상대) · engine_md5(지금) · grade(권위 · 사람 쪽) · has_short · program · standing_qualified · artifacts · eligible · reason(코드 ;) · reason_detail
#' @param standing rc_standing_qualified() 산출(기본 = 지금 원장들) · 같은 엔진(경로)은 한 행으로 합친다(등록부 key 우선)
rc_p4_base_pool <- function(root = rc_root(), registry_path = NULL, standing = NULL, fdv_ledger_path = NULL) {
  R <- .rcp4_registry_engines(pr_load(root, registry_path))
  Q <- standing %||% rc_standing_qualified(root = root)
  rows <- list()
  if (!is.null(R)) for (i in seq_len(nrow(R))) {
    r <- R[i]; ep <- .rcp4_rel(r$engine_raw, root)
    rows[[length(rows) + 1L]] <- list(key = r$key, engine_path = ep, program = r$program, where = r$where, has_short = r$has_short,
                                      implementation_suspect = r$implementation_suspect, holdings_claim_mismatch = r$holdings_claim_mismatch,
                                      audit_verdict = r$audit_verdict, paper_key = r$paper_key, title = r$title, lane_artifacts = .rcp4_rel(r$artifacts_raw, root),
                                      from_registry = TRUE)
  }
  paths <- vapply(rows, function(x) as.character(x$engine_path), "")
  sq <- list()
  for (j in seq_len(nrow(Q))) {
    q <- Q[j]; ep <- .rcp4_rel(q$engine_path, root); hit <- which(paths %in% ep)
    if (!length(hit)) { rows[[length(rows) + 1L]] <- list(key = sprintf("standing:%s:%s", q$round_id, q$code), engine_path = ep, program = "P1_RETURN",
                                                          where = "standing", has_short = NA, implementation_suspect = NA, holdings_claim_mismatch = NA,
                                                          audit_verdict = NA_character_, paper_key = q$paper_key, title = NA_character_, lane_artifacts = NA_character_,
                                                          from_registry = FALSE)
                        paths <- c(paths, ep); hit <- length(rows) }
    for (h in hit) sq[[as.character(h)]] <- q
  }
  if (!length(rows)) return(setDT(list(key = character(0), engine_path = character(0), engine_md5 = character(0), grade = character(0), has_short = logical(0),
                                       program = character(0), standing_qualified = logical(0), artifacts = character(0), eligible = logical(0), reason = character(0))))
  out <- rbindlist(lapply(seq_along(rows), function(i) {
    x <- rows[[i]]; q <- sq[[as.character(i)]]; rs <- character(0); det <- character(0)
    ea <- .rcp4_abs(x$engine_path, root); has_eng <- !is.na(ea) && file.exists(ea)
    if (!has_eng) rs <- c(rs, "no_engine")
    stq <- !is.null(q)
    if (stq && !isTRUE(q$engine_same)) { rs <- c(rs, "standing_engine_changed"); stq <- FALSE }
    art <- if (stq && !is.na(q$artifacts)) .rcp4_rel(q$artifacts, root) else x$lane_artifacts
    grade <- .rcp4_grade(.rcp4_abs(x$lane_artifacts, root))
    if (!stq && !(grade %in% c("A", "B"))) rs <- c(rs, "not_qualified")
    if (isTRUE(x$from_registry)) {
      if (!identical(x$implementation_suspect, FALSE) || isTRUE(x$holdings_claim_mismatch)) rs <- c(rs, "implementation_suspect")
      if (!(x$audit_verdict %in% c("faithful", "adapted"))) rs <- c(rs, "audit_not_passed")
    }
    if (!stq && !identical(x$has_short, FALSE)) rs <- c(rs, "needs_long_leg")
    fv <- .rcp4_fdv(.rcp4_abs(art, root), root, fdv_ledger_path)
    if (isTRUE(fv$stale)) { rs <- c(rs, "factor_db_stale"); det <- c(det, paste0("factor_db_stale: ", fv$reason)) }
    else if (is.na(fv$stale)) det <- c(det, paste0("factor_db_vintage 판정 불가: ", fv$reason))
    setDT(list(key = x$key, engine_path = x$engine_path, engine_md5 = if (has_eng) rc_md5(ea) else NA_character_, grade = grade, has_short = x$has_short,
               program = x$program, where = x$where, standing_qualified = stq, standing_code = if (is.null(q)) NA_character_ else q$code,
               artifacts = art, lane_artifacts = x$lane_artifacts, paper_key = x$paper_key, title = x$title %||% NA_character_, fdv_stale = fv$stale,
               eligible = !length(rs), reason = paste(unique(rs), collapse = ";"), reason_detail = paste(det, collapse = " | ")))
  }), fill = TRUE)
  out[order(-eligible, key)]
}
## 풀 스냅샷 md5 — 자격 판정에 닿는 열만(정렬 · 직렬화 고정)
rc_p4_pool_md5 <- function(pool) {
  P <- as.data.table(pool)[, .(key, engine_path, engine_md5, standing_qualified, eligible, reason)][order(key)]
  .rcs_md5s(as.character(toJSON(P, dataframe = "rows", null = "null", na = "null", digits = NA)))
}
#' 기저 칸 사양 — 풀 한 행(엔진)에서 사슬의 기저 칸 사양(JSON)을 만든다. P1 상설 자격의 표준 구성 칸 생성기(v1/p1.R::rc_p1_cell_spec —
#'   엔진 신호 그대로 · 표준 롱온리 구성 · 정본 고정 축 대조)를 그대로 불러 같은 모양으로 만든다(복제 없음 · 바꾸는 것은 메타 키뿐).
#'   논문 메타 = 상설 판 입구와 같은 판독(v1/standing.R::rc_standing_paper — 인계 기록 → lane_provenance → FIDELITY → 측정 산출 → arXiv 키 · 출처를 남긴다).
#'   시행 회계 = 사슬 계보의 기저 1(selection_accounting.lineage = P4_chain_base) — 걸음 측정 회계는 rc_p4_step_measure 가 측정 사본에 싣는다.
#'   p4.same_construction = 풀 산출(기저 보는 창 지표의 출처)이 이 표준 구성으로 잰 것인가(상설 자격 = TRUE · 등록부 권위 등급 경로 = FALSE —
#'   레인 산출은 논문 구성이라 첫 걸음의 dS_vis 에 구성 차이가 섞인다 · 기록만 하고 막지 않는다).
#' @return out_path(보이지 않게) · 이미 있으면 덮어쓰지 않는다
rc_p4_base_cell_spec <- function(key, pool, root = rc_root(), out_path) {
  k0 <- key; P <- as.data.table(pool); row <- P[P[["key"]] %in% k0]
  if (!nrow(row)) .rcp4_err("기저 풀 밖 key: ", k0)
  if (!isTRUE(row$eligible[1])) .rcp4_err("기저 풀 자격 미달 key(", k0, "): ", row$reason[1])
  if (missing(out_path) || !.rcp4_txt(out_path)) .rcp4_err("out_path 없음")
  if (file.exists(out_path)) .rcp4_err("기저 칸 사양이 이미 있다 — 덮어쓰지 않는다: ", out_path)
  ea <- .rcp4_abs(row$engine_path[1], root); if (is.na(ea) || !file.exists(ea)) .rcp4_err("엔진 파일 없음: ", row$engine_path[1])
  col <- function(nm) if (nm %in% names(row)) row[[nm]][1] else NA_character_
  art <- .rcs_or(.rcs_str(col("lane_artifacts")), .rcs_str(col("artifacts")))
  pa <- rc_standing_paper(dirname(ea), list(paper_key = .rcs_str(col("paper_key")), title = .rcs_str(col("title")),
                                            artifacts = if (is.na(art)) NA_character_ else .rcp4_abs(.rcp4_rel(art, root), root)))
  if (!isTRUE(pa$ok)) .rcp4_err("기저 엔진의 논문 메타(url · title · paper_key)를 찾지 못했다(", k0, ") — 인계 기록 · lane_provenance · FIDELITY · 측정 산출 순으로 본다")
  code <- sprintf("P4B_%s_%s", gsub("[^A-Za-z0-9]+", "_", pa$paper_key), substr(rc_md5(ea), 1L, 6L))
  basis <- sprintf("P4 강화 사슬 기저 칸(풀 key %s · 표준 구성 그대로 · 처치 없음) — 사슬 계보 시행 1 = 기저", k0)
  cs <- rc_p1_cell_spec(code, ea, pa[c("url", "title", "paper_key")], pa$paper_key, 1L, basis, root = root)
  cs[["selection_accounting"]][["lineage"]] <- "P4_chain_base"
  cs[["p4"]] <- list(role = "base", pool_key = k0, engine_md5 = rc_md5(ea), paper_url_source = pa$url_source,
                     same_construction = isTRUE(col("standing_qualified")))
  rc_json_write(cs, out_path)
  invisible(out_path)
}

## ── 감독 영수증(Superfan 규약 §11 · 라운드 등록 register.R::rc_register ⑥ 과 같은 규율) ──────────────────
##   철학 P1 = 라운드 등록의 확인 함수(register.R::rc_p1_check — 대상 round · 파일 이름 형식 · 도전 · 정지 응답 · 열린 보류 요청 없음)를 그대로 부르고,
##   받은 id 가 그 수령 목록에 있는지 본다. 그 밖(판단 T1 · T2 · 철학 P2 · 생성기 개정 철학 의견)은 같은 규칙을 그 리뷰 하나에 적용한다 —
##   원장에 그 id 가 있고 · 역할 · 트리거 · 대상(round) 일치 · 파일 실재 · 그 리뷰의 도전 · 정지 항목 모두 응답 · 열린 보류 요청 없음.
##   시험 우회 = 기존 코어와 같은 인자(ledger = 임시 원장 · review_root = 임시 리뷰 뿌리)뿐이다.
.rcp4_receipt <- function(id, role, trigger, target, root = rc_root(), ledger = file.path(root, RC_LEDGER_DEFAULT), review_root = root) {
  what <- sprintf("%s %s", role, paste(trigger, collapse = "|"))
  if (!.rcp4_txt(id)) return(list(ok = FALSE, why = sprintf("%s 리뷰 id 없음(영수증 없이 진행하지 않는다)", what)))
  if (identical(role, "philosophy") && identical(trigger, "P1")) {
    p1 <- rc_p1_check(target, root, ledger, review_root)
    if (!isTRUE(p1$ok)) return(list(ok = FALSE, why = p1$why))
    if (!(id %in% p1$reviews)) return(list(ok = FALSE, why = sprintf("철학 P1 리뷰 %s 가 이 대상(%s)의 P1 수령 목록(%s)에 없다", id, target, paste(p1$reviews, collapse = ","))))
    return(list(ok = TRUE, id = id, role = role, trigger = "P1", file = p1$files[match(id, p1$reviews)], n_challenges = p1$n_challenges))
  }
  L <- tryCatch(rc_json_read(ledger), error = function(e) NULL)
  if (is.null(L)) return(list(ok = FALSE, why = "판단 원장 판독 실패"))
  rv <- Filter(function(r) identical(r$id, id), L$reviews %||% list())
  if (!length(rv)) return(list(ok = FALSE, why = sprintf("판단 원장에 없는 리뷰 id: %s", id)))
  r <- rv[[1]]; ro <- r$role %||% "judgment"
  if (!identical(ro, role) || !(isTRUE(r$trigger %in% trigger))) return(list(ok = FALSE, why = sprintf("리뷰 %s 는 %s %s — 요구 %s", id, ro, r$trigger %||% "?", what)))
  if (!identical(r$round, target)) return(list(ok = FALSE, why = sprintf("리뷰 %s 의 대상(round) = %s — 이 대상은 %s", id, r$round %||% "없음", target)))
  f <- as.character(r$file %||% NA_character_)
  if (is.na(f) || !file.exists(file.path(review_root, f))) return(list(ok = FALSE, why = sprintf("리뷰 %s 의 파일이 없다: %s", id, f)))
  ids <- unique(unlist(r$challenges))
  ch <- Filter(function(c) c$id %in% ids && (c$grade %||% "") %in% c("challenge", "stop"), L$challenges %||% list())
  open <- vapply(Filter(function(c) identical(c$status, "open") || !length(c$responses), ch), function(c) c$id, character(1))
  hold <- vapply(Filter(function(c) isTRUE(c$hold_request) && !(c$status %in% c("accepted", "withdrawn", "escalated", "settled")), ch), function(c) c$id, character(1))
  if (length(open)) return(list(ok = FALSE, why = paste("응답 없는 도전:", paste(open, collapse = ","))))
  if (length(hold)) return(list(ok = FALSE, why = paste("열린 보류 요청:", paste(hold, collapse = ","))))
  list(ok = TRUE, id = id, role = ro, trigger = r$trigger, file = f, n_challenges = length(ch))
}
.rcp4_receipt_need <- function(..., stage) {
  r <- .rcp4_receipt(...)
  if (!isTRUE(r$ok)) .rcp4_err(stage, " 거부 — 감독 영수증 미충족: ", r$why)
  r[c("id", "role", "trigger", "file", "n_challenges")]
}

## ── ② 격차(보는 창 · 등급 계약 호출만) ────────────────────────────────────────
.rcp4_read_art <- function(dir, E) {
  f <- function(n) { p <- file.path(dir, n); if (!file.exists(p)) .rcp4_err("산출물 없음: ", p); p }
  emptyM <- data.table(metric_name = character(0), metric_value = numeric(0)); emptyC <- data.table(metric_name = character(0), active_value = numeric(0))
  E$.gv3_prep(fread(f("03_period_returns.csv")), fread(f("05_benchmark_returns.csv")), fread(f("02_nav.csv")), emptyM, emptyC)
}
#' 격차 — 산출 폴더의 보는 창(≤ τ_D) 지표로 A 하한마다 값 · 문턱 · 여유 · 통과 + 병목(상대 여유 최소). 시험 창 값은 계산도 반환도 하지 않는다.
#'   입력 표는 τ_D 에서 먼저 자른 뒤 계약 함수에 넣는다(시험 창 행이 계약 안으로 들어가지도 않는다).
rc_p4_gap <- function(dir, root = rc_root(), tau = NULL) {
  E <- rc_deps(root); tau <- as.Date(tau %||% .rcp4_tau(root)); dir <- .rcp4_abs(.rcp4_rel(dir, root), root)
  X <- .rcp4_read_art(dir, E)
  P <- X$pr[date <= tau]; B <- X$br[date <= tau]; N <- X$nv[date <= tau]
  if (!nrow(P)) .rcp4_err("보는 창 행이 없다: ", dir)
  w <- E$gv3_window(P, B, N, to = tau, root = root)
  th <- E$gv3_thresholds(root); cf <- E$gv3_cfg(root)
  S <- E$gv3_S(w$calmar, w$port_t, th, cf$weights)
  BP <- B[, .(date, ret_net = benchmark_ret, risk_free_ret = 0, leverage = 1, frequency = as.character(P$frequency[1]))]
  bw <- E$gv3_window(BP, BP[, .(date, benchmark_ret = ret_net, benchmark_id = as.character(B$benchmark_id[1]))], B[, .(date, nav_net = benchmark_nav)], to = tau, root = root)
  fl <- data.table(floor = c("S", "port_t", "calmar", "cagr", "sharpe"),
                   value = c(S, w$port_t, w$calmar, w$cagr, w$sharpe),
                   threshold = c(cf$a_boundary, th$port_t_b, bw$calmar, th$cagr_min, th$sharpe_min),
                   threshold_source = c("06_Registry/grade_v3.json::a_boundary", paste0(th$source %||% "tier_graduation", " · grade_b_min_portfolio_alpha_t"),
                                        "같은 보는 창 KOSPI200 Calmar(gv3_window — 벤치를 전략처럼)", paste0(th$source %||% "tier_graduation", " · cagr_min"),
                                        paste0(th$source %||% "tier_graduation", " · sharpe_min")))
  fl[, margin := value - threshold]
  fl[, margin_rel := ifelse(is.finite(threshold) & abs(threshold) > 0, margin / abs(threshold), margin)]
  fl[, pass := is.finite(value) & is.finite(threshold) & value >= threshold]
  bn <- fl[is.finite(margin_rel)]; bott <- if (nrow(bn)) bn$floor[which.min(bn$margin_rel)] else NA_character_
  out <- list(schema = "rc_p4_gap_v1", audience = "보는 창(τ_D 이전) — 처방 · 리뷰 레인 열람 가능 · 시험 창 값 없음", tau_d = format(tau),
              window = c(format(min(P$date)), format(max(P$date))), n_obs = w$n_obs,
              metrics = list(S_vis = S, calmar_vis = w$calmar, port_t_vis = w$port_t, cagr_vis = w$cagr, sharpe_vis = w$sharpe, mdd_vis = w$mdd),
              bench = list(calmar_vis = bw$calmar, cagr_vis = bw$cagr, mdd_vis = bw$mdd), floors = fl, bottleneck = bott,
              a_ready_visible = isTRUE(all(fl$pass)))
  lk <- rc_after_tau_leaks(out, tau); if (length(lk)) .rcp4_err("격차 기록에 τ_D 뒤 날짜가 남았다: ", paste(head(lk, 3), collapse = ","))
  out
}
#' 보는 창 지표(걸음 판정 입력) — 격차(등급 계약) + 행동 카드 보는 창(상승 포착 · 위기 하락 포착 중앙값 · 위기 수)
#'   행동 카드는 τ_D 에서 자른 수익 · 벤치 이력으로 부른다(시험 창 정보가 위기 경계에도 들어가지 않는다 — 보수 판).
#' @param bm_hist "auto" = 정본 긴 벤치 이력(.cache/benchmark.parquet · gv3_bench_history) · NULL = 산출물 벤치 수익
rc_p4_visible_metrics <- function(artifacts, root = rc_root(), tau = NULL, bm_hist = "auto") {
  E <- rc_deps(root); tau <- as.Date(tau %||% .rcp4_tau(root)); dir <- .rcp4_abs(.rcp4_rel(artifacts, root), root)
  g <- rc_p4_gap(dir, root, tau)
  X <- .rcp4_read_art(dir, E); P <- X$pr[date <= tau]; B <- X$br[date <= tau]
  bh <- if (identical(bm_hist, "auto")) E$gv3_bench_history(root) else bm_hist
  if (!is.null(bh)) bh <- as.data.table(bh)[date <= tau]
  card <- tryCatch(E$bc_card(P[, .(date, ret_net)], B[, .(date, benchmark_ret)], cfg = E$bc_cfg(root), bm_hist = bh, root = root),
                   error = function(e) structure(list(err = conditionMessage(e)), class = "rcp4_err"))
  cv <- if (inherits(card, "rcp4_err")) list() else card$visible
  c(g$metrics, list(uc_vis = .rcp4_num(cv$bull_up_capture_median), dd_capture_median_vis = .rcp4_num(cv$crisis_dd_capture_median),
                    n_crisis_vis = .rcp4_num(cv$n_crisis), card_error = if (inherits(card, "rcp4_err")) card$err else NA_character_,
                    window = g$window, bottleneck = g$bottleneck))
}

## ── ⑦ 생성기 판(06_Registry/rx_generator.json · 추가 전용) ───────────────────────
rxg_path <- function(root = rc_root(), path = NULL) {
  p <- path %||% Sys.getenv("RC_RXG_PATH", ""); if (nzchar(p)) p else file.path(root, "06_Registry/rx_generator.json")
}
rxg_load <- function(root = rc_root(), path = NULL) {
  G <- rc_json_read(rxg_path(root, path))
  if (!identical(G$schema, "rx_generator_v1")) .rcp4_err("생성기 등록부 스키마 ≠ rx_generator_v1: ", rxg_path(root, path))
  G
}
## 판 디렉터리의 프롬프트 파일(md) md5 — 이름 정렬
rxg_files_md5 <- function(dir, root = rc_root()) {
  d <- .rcp4_abs(.rcp4_rel(dir, root), root); fs <- sort(list.files(d, pattern = "[.]md$"))
  if (!length(fs)) .rcp4_err("생성기 판에 프롬프트(md) 파일이 없다: ", dir)
  as.list(stats::setNames(vapply(fs, function(f) rc_md5(file.path(d, f)), ""), fs))
}
rxg_get <- function(id, root = rc_root(), path = NULL) {
  v <- Filter(function(x) identical(x$id, id), rxg_load(root, path)$versions %||% list())
  if (!length(v)) .rcp4_err("생성기 등록부에 없는 판: ", id)
  v[[1]]
}
rxg_current <- function(root = rc_root(), path = NULL) rxg_get(rxg_load(root, path)$current, root, path)
#' 판 핀 — 등록부 기록(파일별 md5)과 지금 디스크가 같아야 돌려준다(다르면 멈춘다 · 등록 없이 프롬프트를 고친 것)
rxg_pin <- function(id = NULL, root = rc_root(), path = NULL) {
  v <- if (is.null(id)) rxg_current(root, path) else rxg_get(id, root, path)
  now <- rxg_files_md5(v$dir, root)
  if (!identical(now[sort(names(now))], v$files[sort(names(v$files))]))
    .rcp4_err("생성기 판 ", v$id, " 의 파일이 등록부 md5 와 다르다 — 프롬프트를 고쳤으면 rxg_revise 로 새 판을 등록한다")
  list(id = v$id, dir = v$dir, files = v$files)
}
#' 새 판 등록(추가 전용) — new_dir = 새 프롬프트 디렉터리(이름 g<n> · md 파일만 · 판정 규칙 파일 금지) · reason · evidence = 결과 원장 round_id(≥ 1 · 원장에 있어야 함)
#'   philosophy_review = 철학 Superfan 의견 id(판단 원장 · 역할 philosophy · 트리거 P1 | P4 · 대상 round = "P4_generator_<새 판 id>" · 도전 응답 · 보류 없음) —
#'   없으면 거부(생성기 개정도 투자철학 정렬을 본다 · 2026-11-10). 등록부 판 기록에 id 를 적는다.
rxg_revise <- function(new_dir, reason, evidence, root = rc_root(), path = NULL, outcomes_path = NULL, philosophy_review = NULL,
                       ledger = file.path(root, RC_LEDGER_DEFAULT), review_root = root) {
  G <- rxg_load(root, path); rel <- .rcp4_rel(new_dir, root); id <- basename(rel); d <- .rcp4_abs(rel, root)
  if (!grepl("^g[0-9]+$", id)) .rcp4_err("새 판 디렉터리 이름은 g<번호>: ", id)
  if (id %in% vapply(G$versions, function(v) v$id, "")) .rcp4_err("이미 있는 판 id: ", id)
  if (!dir.exists(d)) .rcp4_err("새 판 디렉터리 없음: ", new_dir)
  other <- setdiff(list.files(d, all.files = FALSE), list.files(d, pattern = "[.]md$"))
  if (length(other)) .rcp4_err("생성기 판에는 프롬프트(md)만 둔다 — 판정 규칙 · 코드 · 설정 파일은 생성기가 아니다: ", paste(other, collapse = ","))
  if (!.rcp4_txt(reason)) .rcp4_err("개정 사유(reason) 없음")
  ev <- unique(trimws(as.character(unlist(evidence)))); ev <- ev[nzchar(ev)]
  if (!length(ev)) .rcp4_err("근거(evidence) = 결과 원장 round_id 1개 이상")
  op <- outcomes_path %||% rc_outcomes_path(root)
  known <- vapply(rc_outcomes_read(op, kind = "round"), function(x) as.character(x$round_id), "")
  miss <- setdiff(ev, known); if (length(miss)) .rcp4_err("결과 원장에 없는 근거 round_id: ", paste(miss, collapse = ","))
  lk <- rc_after_tau_leaks(list(reason), .rcp4_tau(root)); if (length(lk)) .rcp4_err("개정 사유에 τ_D 뒤 날짜: ", paste(lk, collapse = ","))
  files <- rxg_files_md5(rel, root)
  if (any(vapply(G$versions, function(v) identical(v$files[sort(names(v$files))], files[sort(names(files))]), TRUE))) .rcp4_err("기존 판과 파일이 같다 — 새 판이 아니다")
  pr <- .rcp4_receipt_need(philosophy_review, "philosophy", c("P1", "P4"), paste0("P4_generator_", id), root = root, ledger = ledger, review_root = review_root,
                           stage = "생성기 개정")
  n0 <- length(G$versions)
  G$versions[[n0 + 1L]] <- list(id = id, dir = rel, files = files, created_at = rc_now(), reason = reason, evidence = as.list(ev),
                                philosophy_review = pr$id, philosophy_review_file = pr$file)
  G$current <- id
  rc_json_write(G, rxg_path(root, path))
  invisible(G$versions[[n0 + 1L]])
}

## ── ③ 사슬 판 ────────────────────────────────────────────────────────────────
rc_p4_spec_path <- function(chain_dir) file.path(chain_dir, "chain_spec.json")
rc_p4_steps_path <- function(chain_dir) file.path(chain_dir, "chain_steps.jsonl")
.rcp4_rule_walk_metrics <- function(r) if (r[["type"]] %in% c("all_of", "any_of")) unlist(lapply(r[["of"]], .rcp4_rule_walk_metrics)) else r[["metric"]]
#' 사슬 판 검사 — 반환 = 해석된 채택 규칙(rc_rules_resolve) · 거부 = 멈춘다
#'   ① 스키마 · 프로그램 · chain_id · τ_D(= behavior_card.json 정본 · 출처 문구) ② 기저(key · 풀 md5 · 칸 사양 md5 · 산출)
#'   ③ 채택 규칙: threshold 만 · 지표 = 보는 창 판정 표 열만(시험 창 · 전 기간 이름 거부) · 규칙마다 source 문구 · 필수 셋(개선 dS_vis · 상승 포착 uc_vis · 위기 비악화 d_dd_capture_median_vis)
#'   ④ 예산: max_steps · noise_k(정수 ≥ 1 · *_source 문구) ⑤ 생성기: 등록부 판의 파일 md5 = 사양 = 지금 디스크 ⑥ final_rule = last_accepted ⑦ 사양 글에 τ_D 뒤 날짜 없음
rc_p4_chain_check <- function(spec, root = rc_root(), gen_path = NULL, check_files = TRUE) {
  if (!identical(spec[["schema"]], RC_P4_CHAIN_SCHEMA)) .rcp4_err("schema 는 ", RC_P4_CHAIN_SCHEMA)
  if (!identical(spec[["program"]], RC_P4_PROGRAM)) .rcp4_err("program 은 ", RC_P4_PROGRAM)
  if (!.rcp4_txt(spec[["chain_id"]]) || !grepl("^P4C[0-9]+_[a-z0-9_]+$", spec[["chain_id"]])) .rcp4_err("chain_id 형식(P4C<nn>_이름 · 소문자): ", spec[["chain_id"]] %||% "")
  tau <- .rcp4_tau(root)
  if (!identical(spec[["tau_d"]], tau) || !.rcp4_txt(spec[["tau_d_source"]])) .rcp4_err("tau_d 는 06_Registry/behavior_card.json::tau_d(", tau, ") + tau_d_source 문구")
  b <- spec[["base"]]; if (!is.list(b)) .rcp4_err("base 없음")
  for (k in c("key", "pool_md5", "cell_spec", "cell_spec_md5", "artifacts")) if (!.rcp4_txt(b[[k]])) .rcp4_err("base.", k, " 없음")
  if (check_files) {
    cs <- .rcp4_abs(.rcp4_rel(b$cell_spec, root), root)
    if (!file.exists(cs) || !identical(rc_md5(cs), b$cell_spec_md5)) .rcp4_err("기저 칸 사양 md5 ≠ 사양(또는 파일 없음): ", b$cell_spec)
  }
  ad <- spec[["adoption"]]; rules <- ad[["rules"]]
  if (!is.list(rules) || !length(rules) || !is.null(names(rules))) .rcp4_err("adoption.rules 는 이름 없는 목록 1개 이상")
  for (r in rules) {
    ms <- .rcp4_rule_walk_metrics(r)
    bad <- ms[grepl(RC_P4_FORBIDDEN_METRIC_RX, ms, perl = TRUE)]
    if (length(bad)) .rcp4_err("채택 규칙이 시험 창 · 전 기간 지표를 쓴다(τ_D — 보는 창만): ", paste(bad, collapse = ","))
    if (!identical(r[["type"]], "threshold")) .rcp4_err("채택 규칙은 threshold 만(", r[["id"]] %||% "?", ")")
    if (!(r[["metric"]] %in% RC_P4_METRICS)) .rcp4_err("채택 규칙 지표가 보는 창 판정 표 열 밖: ", r[["metric"]], " (", paste(RC_P4_METRICS, collapse = " | "), ")")
    if (!.rcp4_txt(r[["source"]])) .rcp4_err("채택 규칙 ", r[["id"]] %||% "?", " 에 출처 문구(source) 없음 — 숫자는 정본 참조 + 출처")
  }
  ms <- vapply(rules, function(r) r[["metric"]], "")
  for (need in c("dS_vis", "uc_vis", "d_dd_capture_median_vis")) if (!(need %in% ms)) .rcp4_err("채택 규칙에 필수 지표가 없다: ", need, "(S 개선 · 상승 포착 하한 · 위기 하락 포착 비악화)")
  rr <- rc_rules_resolve(rules, root)
  bu <- spec[["budget"]]; if (!is.list(bu)) .rcp4_err("budget 없음")
  for (k in c("max_steps", "noise_k")) {
    v <- suppressWarnings(as.integer(.rcp4_num(bu[[k]])))
    if (is.na(v) || v < 1L || !isTRUE(all.equal(.rcp4_num(bu[[k]]), v))) .rcp4_err("budget.", k, " 은 1 이상 정수")
    if (!.rcp4_txt(bu[[paste0(k, "_source")]])) .rcp4_err("budget.", k, "_source 문구 없음 — 예산 숫자에 출처")
  }
  gn <- spec[["generator"]]; if (!is.list(gn) || !.rcp4_txt(gn[["id"]]) || !is.list(gn[["files"]]) || !length(gn[["files"]])) .rcp4_err("generator(id · files) 없음")
  rv <- rxg_get(gn$id, root, gen_path)
  sf <- gn$files[sort(names(gn$files))]
  if (!identical(sf, rv$files[sort(names(rv$files))])) .rcp4_err("생성기 판 ", gn$id, " 의 파일 md5 ≠ 등록부(rx_generator.json)")
  if (check_files) { now <- rxg_files_md5(rv$dir, root); if (!identical(now[sort(names(now))], sf)) .rcp4_err("생성기 판 ", gn$id, " 디스크 파일 md5 ≠ 등록부 — 낡은 판 · 무등록 수정") }
  if (!identical(spec[["final_rule"]], "last_accepted")) .rcp4_err("final_rule 은 last_accepted")
  lk <- rc_after_tau_leaks(spec, as.Date(tau)); if (length(lk)) .rcp4_err("사슬 판 글에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  invisible(rr)
}
#' 사슬 판 만들기 — 기저 = 풀의 자격 행(key) · 풀 스냅샷(pool_snapshot.json) · 사양 파일 · 검사(쓰기 전)
#'   base_cell_spec 을 생략하면(NULL) rc_p4_base_cell_spec 이 사슬 디렉터리에 base_cell_spec.json 을 만든다(표준 구성 · P1 상설 자격 생성기).
rc_p4_chain_new <- function(chain_dir, chain_id, base_key, pool, base_cell_spec = NULL, adoption_rules, budget, generator_id = NULL,
                            purpose = "", base_artifacts = NULL, root = rc_root(), gen_path = NULL) {
  sp <- rc_p4_spec_path(chain_dir); if (file.exists(sp)) .rcp4_err("이미 사슬 판이 있다 — 덮어쓰지 않는다: ", chain_dir)
  P <- as.data.table(pool); row <- P[key == base_key]
  if (!nrow(row)) .rcp4_err("기저 풀 밖 key: ", base_key)
  if (!isTRUE(row$eligible[1])) .rcp4_err("기저 풀 자격 미달 key(", base_key, "): ", row$reason[1])
  art <- base_artifacts %||% row$artifacts[1]; if (is.na(art)) .rcp4_err("기저 산출(artifacts) 없음: ", base_key)
  gp <- rxg_pin(generator_id, root, gen_path)
  if (is.null(base_cell_spec)) {
    bcs <- file.path(chain_dir, "base_cell_spec.json")
    if (file.exists(bcs)) .rcp4_err("사슬 디렉터리에 base_cell_spec.json 이 이미 있다 — 덮어쓰지 않는다(쓰려면 base_cell_spec 인자로 넘긴다): ", bcs)
    base_cell_spec <- rc_p4_base_cell_spec(base_key, P, root, bcs)
  }
  csr <- .rcp4_rel(base_cell_spec, root); csa <- .rcp4_abs(csr, root); if (!file.exists(csa)) .rcp4_err("기저 칸 사양 없음: ", base_cell_spec)
  dir.create(chain_dir, recursive = TRUE, showWarnings = FALSE)
  rc_json_write(list(schema = RC_P4_POOL_SCHEMA, at = rc_now(), pool_md5 = rc_p4_pool_md5(P),
                     table = P[, intersect(c("key", "engine_path", "engine_md5", "standing_qualified", "eligible", "reason", "program", "where"), names(P)), with = FALSE]),
                file.path(chain_dir, "pool_snapshot.json"))
  spec <- list(schema = RC_P4_CHAIN_SCHEMA, program = RC_P4_PROGRAM, chain_id = chain_id, core_version = RC_VERSION, purpose = purpose,
               tau_d = .rcp4_tau(root), tau_d_source = "06_Registry/behavior_card.json::tau_d(정보 경계 τ_D · 채택 규칙 · 설계 입력은 그 이전만)",
               base = list(key = base_key, pool_md5 = rc_p4_pool_md5(P), engine_path = row$engine_path[1], cell_spec = csr, cell_spec_md5 = rc_md5(csa),
                           artifacts = .rcp4_rel(art, root)),
               adoption = list(rules = adoption_rules, decision = "accept = 모든 채택 규칙이 참(미측정 = 기각)"),
               budget = budget, generator = list(id = gp$id, files = gp$files), final_rule = "last_accepted")
  ck <- tryCatch({ rc_p4_chain_check(spec, root, gen_path); NULL }, error = function(e) e)
  if (!is.null(ck)) { if (exists("bcs", inherits = FALSE)) unlink(c(bcs, file.path(chain_dir, "pool_snapshot.json"))); stop(ck) }   # 만든 기저 칸을 남기지 않는다(재시도 막힘 방지)
  rc_json_write(spec, sp)
  invisible(sp)
}

## ── ④ 걸음 원장(추가 전용 · 앞 줄 md5 사슬) ─────────────────────────────────────
.rcp4_scan <- function(path) {
  if (!file.exists(path)) return(list(ok = TRUE, n = 0L, bad = integer(0), lines = character(0), recs = list()))
  L <- readLines(path, encoding = "UTF-8", warn = FALSE); L <- L[nzchar(L)]; bad <- integer(0); prev <- "genesis"; recs <- vector("list", length(L))
  for (i in seq_along(L)) {
    r <- tryCatch(fromJSON(L[i], simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(r) || !identical(r[["schema"]], RC_P4_STEPS_SCHEMA) || !identical(r[["prev"]], prev)) bad <- c(bad, i)
    if (!is.null(r)) recs[[i]] <- r
    prev <- .rcs_md5s(L[i])
  }
  list(ok = !length(bad), n = length(L), bad = bad, lines = L, recs = recs)
}
rc_p4_steps_verify <- function(chain_dir) .rcp4_scan(rc_p4_steps_path(chain_dir))[c("ok", "n", "bad")]
rc_p4_steps_read <- function(chain_dir) {
  s <- .rcp4_scan(rc_p4_steps_path(chain_dir))
  if (!s$ok) .rcp4_err("걸음 원장 사슬이 끊겼다(추가 전용 위반 — 줄 ", paste(s$bad, collapse = ","), "): ", rc_p4_steps_path(chain_dir))
  s$recs
}
.rcp4_append <- function(chain_dir, rec) {
  path <- rc_p4_steps_path(chain_dir); lk <- .rcs_lock(path); on.exit(unlink(lk, recursive = TRUE), add = TRUE)
  s <- .rcp4_scan(path); if (!s$ok) .rcp4_err("걸음 원장 사슬이 끊겼다 — 추가하지 않는다: ", path)
  full <- c(list(schema = RC_P4_STEPS_SCHEMA, at = rc_now(), prev = if (s$n) .rcs_md5s(s$lines[s$n]) else "genesis"), rec)
  js <- as.character(toJSON(full, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  if (grepl("\n", js, fixed = TRUE)) .rcp4_err("원장 줄에 줄바꿈이 있다")
  con <- file(path, open = "ab"); tryCatch(writeBin(charToRaw(paste0(enc2utf8(js), "\n")), con), finally = close(con))
  invisible(full)
}
## 사슬 상태 — 등록 기록 · 걸음(열림 · 판정) · 머리(마지막 채택 · 없으면 기저 0) · 연속 '잡음 이내' · 닫힘
.rcp4_state <- function(chain_dir, root = rc_root(), need_registered = TRUE) {
  spec <- rc_json_read(rc_p4_spec_path(chain_dir)); recs <- rc_p4_steps_read(chain_dir)
  reg <- Filter(function(r) identical(r$event, "chain_registered"), recs)
  if (need_registered && !length(reg)) .rcp4_err("등록 전 사슬 판이다 — rc_p4_chain_register 먼저")
  reg <- if (length(reg)) reg[[1]] else NULL
  if (!is.null(reg) && !identical(rc_md5(rc_p4_spec_path(chain_dir)), reg$spec_md5)) .rcp4_err("사슬 판이 등록 뒤 바뀌었다(R2) — 판정 규칙을 바꾸려면 새 사슬 판을 등록한다")
  opens <- Filter(function(r) identical(r$event, "step_open"), recs); res <- Filter(function(r) identical(r$event, "step_result"), recs)
  ks <- vapply(opens, function(r) as.integer(r$k), 1L); rk <- vapply(res, function(r) as.integer(r$k), 1L)
  acc <- Filter(function(r) identical(r$decision, "accept"), res)
  ## 기준 칸 = 사슬이 직접 잰 기저(base_measured · 11-10) — 비교 · 재채점의 기저는 이것뿐이다. 등록 기록의 base_metrics(풀 산출)는 참고 기록.
  bm <- Filter(function(r) identical(r$event, "base_measured"), recs); bm <- if (length(bm)) bm[[length(bm)]] else NULL
  head_k <- if (length(acc)) as.integer(acc[[length(acc)]]$k) else 0L
  head_m <- if (length(acc)) acc[[length(acc)]]$metrics else bm$metrics
  streak <- 0L; for (r in rev(res)) { if (is.null(r$r7) || is.na(r$r7)) next; if (identical(r$r7, "noise")) streak <- streak + 1L else break }
  list(spec = spec, reg = reg, recs = recs, opens = opens, results = res, open_ks = ks, decided_ks = rk, head_k = head_k, head_metrics = head_m,
       base_meas = bm, noise_streak = streak, closed = any(vapply(recs, function(r) identical(r$event, "chain_closed"), TRUE)), tau = as.Date(spec$tau_d))
}
.rcp4_need_base <- function(st, what) if (is.null(st$base_meas)) .rcp4_err(what, " 거부 — 기준 칸 측정 먼저(p4-base-measure · 기저 칸을 사슬이 같은 러너 · 같은 축으로 잰다)")
.rcp4_cell_of <- function(st, k) {
  if (k == 0L) return(st$spec$base$cell_spec)
  o <- Filter(function(r) identical(as.integer(r$k), as.integer(k)), st$opens); if (!length(o)) .rcp4_err("그런 걸음이 없다: ", k)
  o[[1]]$cell_spec_path
}
.rcp4_artifacts_of <- function(st, k) {
  if (k == 0L) return(if (is.null(st$base_meas)) NA_character_ else st$base_meas$artifacts)
  r <- Filter(function(r) identical(as.integer(r$k), as.integer(k)), st$results); if (!length(r)) NA_character_ else r[[1]]$artifacts
}
#' 사슬 판 등록(한 번) — 검사 · 풀 md5 대조(지금 풀 = 사양 스냅샷) · 기저 자격 · 감독 영수증 · 기저 보는 창 지표 → 원장 첫 줄 chain_registered
#'   감독 영수증(라운드 등록 ⑥ 과 같은 규율 · 없으면 거부): p1 = 철학 Superfan P1 리뷰 id(register.R::rc_p1_check — 대상 round = chain_id ·
#'   파일 이름 …_P1_<P4Cnn>.md) · t1 = 판단 Superfan T1 리뷰 id(역할 judgment · 대상 round = chain_id). ledger · review_root = 시험용 임시 원장 · 리뷰 뿌리.
rc_p4_chain_register <- function(chain_dir, pool, root = rc_root(), gen_path = NULL, metrics_fun = rc_p4_visible_metrics, p1 = NULL, t1 = NULL,
                                 ledger = file.path(root, RC_LEDGER_DEFAULT), review_root = root, ...) {
  spec <- rc_json_read(rc_p4_spec_path(chain_dir))
  rr <- rc_p4_chain_check(spec, root, gen_path)
  if (length(rc_p4_steps_read(chain_dir))) .rcp4_err("이미 등록된 사슬 판(원장이 비어 있지 않다): ", chain_dir)
  rp1 <- .rcp4_receipt_need(p1, "philosophy", "P1", spec$chain_id, root = root, ledger = ledger, review_root = review_root, stage = "사슬 판 등록")
  rt1 <- .rcp4_receipt_need(t1, "judgment", "T1", spec$chain_id, root = root, ledger = ledger, review_root = review_root, stage = "사슬 판 등록")
  P <- as.data.table(pool)
  if (!identical(rc_p4_pool_md5(P), spec$base$pool_md5)) .rcp4_err("기저 풀이 사양 스냅샷과 다르다 — 지금 풀로 새 사슬 판을 만든다(pool_md5)")
  row <- P[key == spec$base$key]
  if (!nrow(row) || !isTRUE(row$eligible[1])) .rcp4_err("기저가 풀 밖이거나 자격 미달: ", spec$base$key)
  bm <- metrics_fun(.rcp4_abs(spec$base$artifacts, root), root = root, tau = spec$tau_d, ...)
  bm <- bm[intersect(names(bm), c(sub("^d_?", "", RC_P4_METRICS), RC_P4_METRICS, "n_crisis_vis", "window", "bottleneck", "card_error"))]
  lk <- rc_after_tau_leaks(bm, as.Date(spec$tau_d)); if (length(lk)) .rcp4_err("기저 지표에 τ_D 뒤 날짜: ", paste(lk, collapse = ","))
  .rcp4_append(chain_dir, list(event = "chain_registered", chain_id = spec$chain_id, spec_md5 = rc_md5(rc_p4_spec_path(chain_dir)),
                               rules_resolved = rr, generator = spec$generator, base_key = spec$base$key, base_metrics = bm, git_head = rc_git_head(root),
                               superfan = list(philosophy_p1 = rp1, superfan_t1 = rt1)))
}
## 칸 사양 비교용 정규화 — 메타 키 제외 · 기저 경로 저장소 상대 · 풀 꼬리표 제외 · null/빈 목록 = 없음
.rcp4_norm_spec <- function(s, root) {
  s <- s[setdiff(names(s), RC_P4_META_KEYS)]
  if (is.list(s$base_signal)) { b <- s$base_signal
    if (!is.null(b$path)) b$path <- .rcp4_rel(b$path, root)
    if (!is.null(b$paths)) b$paths <- lapply(b$paths, .rcp4_rel, root = root)
    b$pool_key <- NULL; b$pool_keys <- NULL; s$base_signal <- b }
  s[!vapply(s, function(v) is.null(v) || (is.list(v) && !length(v)), logical(1))]
}
.rcp4_js <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
#' 칸 사양 차이 — 반환 = list(changed = 바뀐 축 · ok · why · blocks = 축별 블록 유형)
rc_p4_spec_diff <- function(parent, child, block_type, root = rc_root(), pool = NULL) {
  a <- .rcp4_norm_spec(parent, root); b <- .rcp4_norm_spec(child, root)
  ks <- union(names(a), names(b)); ch <- ks[!vapply(ks, function(k) identical(.rcp4_js(a[[k]]), .rcp4_js(b[[k]])), TRUE)]
  why <- character(0); blocks <- list()
  if (!length(ch)) why <- c(why, "부모와 같은 칸이다(바뀐 축 없음)")
  if ("fixed_axes" %in% ch) why <- c(why, "고정 축(fixed_axes)을 바꿨다")
  for (k in setdiff(ch, "fixed_axes")) {
    bt <- if (identical(k, "base_signal")) { if (identical(b$base_signal$kind, "engine_blend")) "blend" else "base" } else RC_P4_KEY_BLOCKS[[k]]
    if (is.null(bt)) { why <- c(why, paste0("어휘 밖 축: ", k)); next }
    blocks[[k]] <- bt
    if (!(block_type %in% bt)) why <- c(why, sprintf("축 %s 는 블록 %s — 선언 블록 %s 와 다르다(한 걸음 = 블록 유형 하나)", k, paste(bt, collapse = "|"), block_type))
  }
  if ("base_signal" %in% ch) {
    bs <- b$base_signal; ps <- unlist(c(bs$path, bs$paths))
    if (is.null(pool)) why <- c(why, "기저 신호를 바꾸는 걸음은 기저 풀과 함께만 검사한다")
    else { el <- as.data.table(pool)[eligible %in% TRUE]$engine_path; out <- setdiff(vapply(ps, .rcp4_rel, "", root = root), el)
      if (!length(ps) || length(out)) why <- c(why, paste0("기저 풀(자격) 밖 엔진: ", paste(out, collapse = ","))) }
    if (identical(bs$kind, "engine_blend") && length(unique(ps)) < 2L) why <- c(why, "engine_blend 는 풀 안 엔진 2개 이상")
  }
  list(changed = ch, ok = !length(why), why = why, blocks = blocks)
}
#' 걸음 열기 — 기계 검사(전부 통과해야 원장에 쓴다)
#'   앞 걸음 판정됨 · k = 앞 걸음 + 1 · 칸 사양 정확히 1개(처음 보는 md5) · 부모 = 사슬 머리 · 블록 유형 어휘 · 부모와 한 블록 유형만 다름 ·
#'   가설 · 기전 문장 있음 · 글에 τ_D 뒤 날짜 없음 · 예산(최대 걸음 · 연속 잡음 K) 안 · 생성기 판 = 사양(지금 디스크 md5 포함) · 사슬 닫힘 아님
rc_p4_step_open <- function(chain_dir, k, hypothesis, mechanism, block_type, cell_spec_path, parent, generator_version,
                            root = rc_root(), pool = NULL, gen_path = NULL) {
  st <- .rcp4_state(chain_dir, root); spec <- st$spec; why <- character(0)
  if (st$closed) .rcp4_err("닫힌 사슬이다 — 새 걸음은 새 사슬 판에서")
  .rcp4_need_base(st, "걸음 열기")
  k <- suppressWarnings(as.integer(k)); parent <- suppressWarnings(as.integer(parent))
  if (length(setdiff(st$open_ks, st$decided_ks))) why <- c(why, paste0("앞 걸음이 판정되지 않았다: ", paste(setdiff(st$open_ks, st$decided_ks), collapse = ",")))
  if (!identical(k, length(st$open_ks) + 1L)) why <- c(why, sprintf("k = %s — 다음 걸음 번호는 %d", k, length(st$open_ks) + 1L))
  mx <- as.integer(.rcp4_num(spec$budget$max_steps)); nk <- as.integer(.rcp4_num(spec$budget$noise_k))
  if (length(st$open_ks) >= mx) why <- c(why, sprintf("예산 소진 — 최대 걸음 %d", mx))
  if (st$noise_streak >= nk) why <- c(why, sprintf("예산 소진 — 연속 '잡음 이내' %d ≥ K %d(목표 축 R7)", st$noise_streak, nk))
  if (!identical(parent, st$head_k)) why <- c(why, sprintf("부모 = %s — 사슬 머리(마지막 채택 · 없으면 기저 0)는 %d", parent, st$head_k))
  if (!(is.character(block_type) && length(block_type) == 1L && block_type %in% RC_P4_BLOCK_TYPES)) why <- c(why, paste0("블록 유형 어휘 밖: ", paste(block_type, collapse = ",")))
  if (!identical(generator_version, spec$generator$id)) why <- c(why, sprintf("생성기 판 %s ≠ 사슬 판 %s", paste(generator_version, collapse = ","), spec$generator$id))
  else { gv <- tryCatch(rxg_files_md5(rxg_get(spec$generator$id, root, gen_path)$dir, root), error = function(e) NULL)
    if (is.null(gv) || !identical(gv[sort(names(gv))], spec$generator$files[sort(names(spec$generator$files))])) why <- c(why, "생성기 판 파일 md5 ≠ 사슬 판(낡은 · 무등록 수정 생성기)") }
  for (nm in c("hypothesis", "mechanism")) if (!.rcp4_txt(get(nm))) why <- c(why, paste0(nm, " 문장 없음"))
  lk <- rc_after_tau_leaks(list(hypothesis, mechanism), st$tau); if (length(lk)) why <- c(why, paste0("가설 · 기전 글에 τ_D 뒤 날짜: ", paste(lk, collapse = ",")))
  if (length(cell_spec_path) != 1L) why <- c(why, sprintf("칸 사양은 정확히 1개(받은 수 %d)", length(cell_spec_path)))
  csr <- if (length(cell_spec_path) == 1L) .rcp4_rel(cell_spec_path, root) else NA_character_
  csa <- .rcp4_abs(csr, root); dif <- NULL; cmd5 <- NA_character_
  if (is.na(csa) || !file.exists(csa)) why <- c(why, paste0("칸 사양 파일 없음: ", csr))
  else {
    cmd5 <- rc_md5(csa)
    used <- c(spec$base$cell_spec_md5, vapply(st$opens, function(r) as.character(r$cell_spec_md5), ""))
    if (cmd5 %in% used) why <- c(why, "이미 쓴 칸 사양(md5) — 새 칸이 아니다")
    if (!is.na(parent) && parent >= 0L && parent <= length(st$open_ks)) {
      pp <- .rcp4_abs(.rcp4_rel(.rcp4_cell_of(st, parent), root), root)
      dif <- rc_p4_spec_diff(rc_json_read(pp), rc_json_read(csa), block_type %||% "", root, pool)
      if (!dif$ok) why <- c(why, dif$why)
    }
  }
  if (length(why)) .rcp4_err("걸음 열기 거부(k = ", k, "):\n- ", paste(unique(why), collapse = "\n- "))
  .rcp4_append(chain_dir, list(event = "step_open", k = k, hypothesis = hypothesis, mechanism = mechanism, block_type = block_type,
                               cell_spec_path = csr, cell_spec_md5 = cmd5, parent = parent, generator_version = generator_version,
                               changed_axes = as.list(dif$changed)))
}
## ── 기준 칸 · 걸음 측정(정본 셀 워커) ────────────────────────────────────────────
#' 정본 측정 러너(기본) — 프로그램 라운드 칸 측정과 같은 호출(v1/measure_cell.R:22-28 · v1/standing.R:646-651 —
#'   Rscript 02_Infrastructure/ops/rf_cell_worker.R <칸 사양> 1 <code> <결과 json> · 로그 = <code>.log / .err.log · 요인 분석 기본 끔(RC_FACTOR_ANALYSIS=1 이면 켬)).
#'   ★2계층 모듈 풀 등재는 기준 칸 · 걸음 칸 모두 끈다(QVEST_RP_REGISTER = 0 · 11-10) — 걸음마다 거의 같은 칸이 선택 보정 전 등급으로 풀에 쌓이지 않게.
#'   등재는 닫기에서 최종 후보 1개만(재채점 뒤 · rc_p4_close). 반환 = 워커 종료 코드. 시험은 runner 인자로 가짜 러너를 넣는다.
rc_p4_runner_default <- function(spec_path, code, out_json, log_dir, root = rc_root(), role = "variant") {
  ev <- c("QVEST_RP_REGISTER", "QVEST_RP_NO_FACTOR_ANALYSIS"); old <- Sys.getenv(ev, unset = NA)
  on.exit({ for (k in ev) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)) }, add = TRUE)
  if (!identical(Sys.getenv("RC_FACTOR_ANALYSIS", "0"), "1")) Sys.setenv(QVEST_RP_NO_FACTOR_ANALYSIS = "1")
  Sys.setenv(QVEST_RP_REGISTER = "0")
  system2("Rscript", c(shQuote(file.path(root, "02_Infrastructure/ops/rf_cell_worker.R")), shQuote(spec_path), "1", code, shQuote(out_json)),
          stdout = file.path(log_dir, paste0(code, ".log")), stderr = file.path(log_dir, paste0(code, ".err.log")))
}
#' 리프레시 배리어(기본) — 02_Infrastructure/ops/refresh_barrier.R::rb_status(판정 = refresh_barrier.sh 단일 정본 · held · error = 막음)
rc_p4_barrier_default <- function(root = rc_root()) {
  e <- new.env(parent = globalenv()); sys.source(file.path(root, "02_Infrastructure/ops/refresh_barrier.R"), envir = e, keep.source = FALSE)
  e$rb_status(root)
}
#' 팩터 DB 판 표식(기본) — 02_Infrastructure/contracts/factor_db_vintage.R::fdv_stamp(root)(수리 원장의 수리 id · 완료 시각 · 유효 시작)를 그대로 받고,
#'   원장 · 비교에는 그 직렬화 md5(id)와 수리 수만 싣는다(완료 시각은 τ_D 뒤 날짜라 보는 창 원장에 넣지 않는다). 판독 불가 = NULL(측정 거부 · fail-closed).
rc_p4_vintage_default <- function(root = rc_root()) {
  f <- file.path(root, "02_Infrastructure/contracts/factor_db_vintage.R"); if (!file.exists(f)) return(NULL)
  e <- new.env(parent = globalenv()); invisible(utils::capture.output(suppressMessages(sys.source(f, envir = e, keep.source = FALSE))))
  s <- tryCatch(e$fdv_stamp(root), error = function(z) NULL); if (is.null(s)) return(NULL)
  list(id = .rcs_md5s(as.character(toJSON(s, auto_unbox = TRUE, null = "null", na = "null", digits = NA))), n_repairs = length(s$repairs %||% list()))
}
.rcp4_vint <- function(vintage, root) { v <- tryCatch(vintage(root), error = function(e) NULL); if (is.list(v) && .rcp4_txt(v$id)) v[c("id", "n_repairs")] else NULL }
.rcp4_measured_of <- function(st, k) {
  m <- Filter(function(r) identical(r$event, "step_measured") && identical(as.integer(r$k), as.integer(k)), st$recs)
  if (length(m)) m[[length(m)]] else NULL
}
## 측정 공통 — 배리어(잠김 = 원장 무기록 · 사유 반환) → 판 표식 → 측정 사본(selection_accounting 만 다시 씀) → 러너 → 지문 대조
##   반환 list(status = barrier_held | vintage_unknown | failed | ok, ...) · failed 는 호출자가 *_measure_failed 로 남긴다
.rcp4_run_cell <- function(chain_dir, st, csa, tag, code, n_trials, basis, role, root, runner, barrier, fingerprint, vintage) {
  b <- tryCatch(barrier(root), error = function(e) list(state = "error", reason = conditionMessage(e), blocking = TRUE))
  if (!identical(b$blocking, FALSE)) {
    why <- sprintf("리프레시 배리어 %s(%s%s) — 측정하지 않는다(다음 실행에서 다시)", b$state %||% "?", b$reason %||% "", if (nzchar(b$lock %||% "")) paste0(" · ", b$lock) else "")
    cat("[P4 측정] ", why, "\n", sep = "")
    return(list(status = "barrier_held", reason = why, barrier = b[intersect(names(b), c("state", "reason", "lock", "path"))]))
  }
  v0 <- .rcp4_vint(vintage, root)
  if (is.null(v0)) { why <- "팩터 DB 판 표식 판독 불가(contracts/factor_db_vintage.R::fdv_stamp) — 측정하지 않는다(fail-closed)"; cat("[P4 측정] ", why, "\n", sep = "")
                     return(list(status = "vintage_unknown", reason = why)) }
  if (!is.null(st$base_meas) && !identical(v0$id, st$base_meas$vintage$id)) {
    why <- "팩터 DB 판이 기준 칸 측정 뒤 바뀌었다 — 이 사슬을 닫고 새 사슬에서 기준 칸부터 다시(측정하지 않는다)"; cat("[P4 측정] ", why, "\n", sep = "")
    return(list(status = "vintage_changed", reason = why))
  }
  s <- rc_json_read(csa)
  s[["selection_accounting"]] <- list(selection_type = "sweep", family_root = st$spec$chain_id, lineage = "P4_chain",
                                      n_family_at_registration = as.integer(n_trials), n_trials_basis = basis)
  md <- file.path(chain_dir, "measure"); dir.create(md, recursive = TRUE, showWarnings = FALSE)
  msp <- file.path(md, paste0(tag, ".spec.json")); out <- file.path(md, paste0(tag, ".json"))
  rc_json_write(s, msp); unlink(out)
  fp0 <- tryCatch(fingerprint(), error = function(e) ""); t0 <- Sys.time()
  rc <- tryCatch(runner(msp, code, out, md, root = root, role = role), error = function(e) structure(-1L, err = conditionMessage(e)))
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs")); fp1 <- tryCatch(fingerprint(), error = function(e) "")
  r <- tryCatch(rc_json_read(out), error = function(e) list(ok = FALSE))
  art <- .rcs_str(r[["artifacts"]]); fp_same <- nzchar(fp0) && identical(fp0, fp1)
  ok <- isTRUE(r[["ok"]]) && !is.na(art) && dir.exists(.rcp4_abs(.rcp4_rel(art, root), root))
  rec <- list(code = code, measured_spec = .rcp4_rel(msp, root), measured_spec_md5 = rc_md5(msp), n_trials = as.integer(n_trials),
              rc = as.integer(rc), seconds = round(sec, 1), fp_same = fp_same, vintage = v0)
  why <- c(if (!isTRUE(r[["ok"]])) paste0("워커 ok ≠ true", if (!is.na(.rcs_str(r[["deferred"]]))) paste0("(deferred ", .rcs_str(r[["deferred"]]), ")") else ""),
           if (isTRUE(r[["ok"]]) && (is.na(art) || !ok)) "산출 폴더 없음", if (!fp_same) "측정 중 데이터 지문이 바뀌었다(이 측정은 쓰지 않는다)",
           if (!is.null(attr(rc, "err"))) paste("러너 예외:", attr(rc, "err")))
  if (!(ok && fp_same)) return(list(status = "failed", rec = rec, why = why))
  list(status = "ok", rec = c(rec, list(artifacts = .rcp4_rel(art, root), result_md5 = rc_md5(out))), sec = sec)
}
.rcp4_metric_keys <- function() c(sub("^d_?", "", RC_P4_METRICS), RC_P4_METRICS, "n_crisis_vis", "window", "bottleneck", "card_error")
#' 기준 칸 측정(k = 0 · 11-10) — 등록된 사슬의 기저 칸 사양(md5 = 사양 · 등록 때와 같음)을 걸음과 같은 러너 · 배리어 · 지문 · 판 표식으로 잰다.
#'   측정 사본 measure/k0.spec.json(sweep · family_root = 사슬 id · 시행 1) · role = "base"(등재 끔). 성공 = 원장 base_measured{artifacts ·
#'   measured_spec_md5 · metrics(보는 창 — rc_p4_visible_metrics) · vintage · same_construction(기록) · measured_at} · 실패 = base_measure_failed(다시 잴 수 있다).
#'   건너뛰기 경로는 없다 — 모든 비교 · 재채점의 기저 = 이 측정. 등록 기록의 base_metrics(풀 산출)는 참고 기록으로만 남는다.
rc_p4_base_measure <- function(chain_dir, root = rc_root(), runner = rc_p4_runner_default, barrier = rc_p4_barrier_default,
                               fingerprint = rc_standing_fingerprint, vintage = rc_p4_vintage_default, metrics_fun = rc_p4_visible_metrics, ...) {
  st <- .rcp4_state(chain_dir, root)
  if (st$closed) .rcp4_err("닫힌 사슬이다 — 측정하지 않는다")
  if (!is.null(st$base_meas)) return(invisible(list(k = 0L, status = "already", artifacts = st$base_meas$artifacts)))
  csa <- .rcp4_abs(.rcp4_rel(st$spec$base$cell_spec, root), root)
  if (!file.exists(csa) || !identical(rc_md5(csa), st$spec$base$cell_spec_md5)) .rcp4_err("기저 칸 사양 md5 ≠ 사슬 판(R2) — 측정하지 않는다: ", st$spec$base$cell_spec)
  x <- .rcp4_run_cell(chain_dir, st, csa, "k0", sprintf("%s_k0", st$spec$chain_id), 1L,
                      sprintf("P4 강화 사슬 %s 기준 칸(기저 · 걸음 0): 계보 누적 시행 = 기저 1(시행 회계는 스윕 그대로)", st$spec$chain_id),
                      "base", root, runner, barrier, fingerprint, vintage)
  if (!(x$status %in% c("ok", "failed"))) return(invisible(c(list(k = 0L), x)))
  if (identical(x$status, "ok")) {
    m <- tryCatch(metrics_fun(.rcp4_abs(x$rec$artifacts, root), root = root, tau = st$spec$tau_d, ...), error = function(e) structure(list(), err = conditionMessage(e)))
    if (!is.null(attr(m, "err"))) x <- list(status = "failed", rec = x$rec, why = paste("보는 창 지표 실패:", attr(m, "err")))
  }
  if (identical(x$status, "failed")) {
    .rcp4_append(chain_dir, c(list(event = "base_measure_failed", k = 0L, cell_spec_md5 = st$spec$base$cell_spec_md5), x$rec, list(why = as.list(x$why))))
    cat(sprintf("[P4 측정] 기준 칸 실패 — %s\n", paste(x$why, collapse = " · ")))
    return(invisible(list(k = 0L, status = "failed", why = x$why)))
  }
  m <- m[intersect(names(m), .rcp4_metric_keys())]
  sc <- tryCatch(rc_json_read(csa)$p4$same_construction, error = function(e) NULL)
  rec <- c(list(event = "base_measured", k = 0L, cell_spec_md5 = st$spec$base$cell_spec_md5), x$rec,
           list(metrics = m, same_construction = if (is.logical(sc) && length(sc) == 1L) sc else NA, measured_at = rc_now()))
  lk <- rc_after_tau_leaks(rec[setdiff(names(rec), "measured_at")], st$tau); if (length(lk)) .rcp4_err("기준 칸 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  .rcp4_append(chain_dir, rec)
  cat(sprintf("[P4 측정] 기준 칸 측정 — 산출 %s · %.1f분\n", rec$artifacts, x$sec / 60))
  invisible(list(k = 0L, status = "measured", artifacts = rec$artifacts))
}
#' 걸음 측정 — 열린 걸음(미판정)의 칸 사양을 정본 측정 경로로 잰다 → 원장 step_measured{k · artifacts · vintage · measured_at}
#'   ① 사슬 등록 · 닫힘 아님 · 기준 칸 측정됨 · 열린 미판정 걸음 · 칸 사양 md5 = 열 때(R2) ② 리프레시 배리어 잠김 · 판 표식 판독 불가 ·
#'      판 표식 ≠ 기준 칸(팩터 DB 가 사슬 도중 수리됨)이면 재지 않고 사유를 돌려준다(원장 무기록)
#'   ③ 시행 회계 = 스윕 그대로 — 측정 사본(measure/k<k>.spec.json)의 selection_accounting 만 다시 쓴다(sweep · family_root = 사슬 id ·
#'      계보 누적 시행 수 = 기저 1 + 지금까지 연 걸음 수 · n_trials_basis 문구). 메타 키라 칸(전략)은 열린 사양과 같다(rc_p4_spec_diff 정규화 기준).
#'   ④ 러너(role variant · 등재 끔) → 결과 json(ok · artifacts) · 데이터 지문 앞뒤 대조 — ok ∧ 산출 폴더 실재 ∧ 지문 같음일 때만 step_measured,
#'      아니면 step_measure_failed(다시 잴 수 있다). 측정 성과 수치는 원장에 싣지 않는다(경로 · md5 · 시각 · 판 표식만).
rc_p4_step_measure <- function(chain_dir, k, root = rc_root(), runner = rc_p4_runner_default, barrier = rc_p4_barrier_default,
                               fingerprint = rc_standing_fingerprint, vintage = rc_p4_vintage_default) {
  st <- .rcp4_state(chain_dir, root); k <- suppressWarnings(as.integer(k))
  if (st$closed) .rcp4_err("닫힌 사슬이다 — 측정하지 않는다")
  .rcp4_need_base(st, "걸음 측정")
  o <- Filter(function(r) identical(as.integer(r$k), k), st$opens)
  if (is.na(k) || !length(o)) .rcp4_err("열지 않은 걸음 — 측정하지 않는다: ", k)
  if (k %in% st$decided_ks) .rcp4_err("이미 판정한 걸음 — 다시 재지 않는다: ", k)
  o <- o[[1]]; csa <- .rcp4_abs(o$cell_spec_path, root)
  if (!file.exists(csa) || !identical(rc_md5(csa), o$cell_spec_md5)) .rcp4_err("칸 사양이 열린 뒤 바뀌었다(R2) — 측정하지 않는다: ", o$cell_spec_path)
  pm <- .rcp4_measured_of(st, k)
  if (!is.null(pm)) return(invisible(list(k = k, status = "already", artifacts = pm$artifacts)))
  n_open <- length(st$opens)
  x <- .rcp4_run_cell(chain_dir, st, csa, sprintf("k%d", k), sprintf("%s_k%d", st$spec$chain_id, k), 1L + n_open,
                      sprintf("P4 강화 사슬 %s: 계보 누적 시행 = 기저 1 + 지금까지 연 걸음 %d = %d(걸음마다 채택 판정이 고르는 일이라 시행 회계는 스윕 그대로)",
                              st$spec$chain_id, n_open, 1L + n_open), "variant", root, runner, barrier, fingerprint, vintage)
  if (!(x$status %in% c("ok", "failed"))) return(invisible(c(list(k = k), x)))
  if (identical(x$status, "failed")) {
    .rcp4_append(chain_dir, c(list(event = "step_measure_failed", k = k, cell_spec_md5 = o$cell_spec_md5), x$rec, list(why = as.list(x$why))))
    cat(sprintf("[P4 측정] 걸음 %d 실패 — %s\n", k, paste(x$why, collapse = " · ")))
    return(invisible(list(k = k, status = "failed", why = x$why)))
  }
  rec <- c(list(event = "step_measured", k = k, cell_spec_md5 = o$cell_spec_md5), x$rec, list(measured_at = rc_now()))
  lk <- rc_after_tau_leaks(rec[setdiff(names(rec), "measured_at")], st$tau)
  if (length(lk)) .rcp4_err("측정 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  .rcp4_append(chain_dir, rec)
  cat(sprintf("[P4 측정] 걸음 %d 측정 — 산출 %s · 시행 %d · %.1f분\n", k, rec$artifacts, rec$n_trials, x$sec / 60))
  invisible(list(k = k, status = "measured", artifacts = rec$artifacts))
}

#' 걸음 판정 — 측정 기록(step_measured)의 산출 → 보는 창 지표(②) → 등록된 채택 규칙(해석본) 기계 적용 → 원장 step_result
#'   판정 표 = 걸음 지표 + 부모(사슬 머리) 대비 차이 · 부모 0 = 기준 칸(base_measured$metrics · 풀 산출 지표 아님) · 미측정 = 기각 ·
#'   r7 = |dS_vis| ≥ 개선 여유면 signal · 아니면 noise.
#'   거부: 기준 칸 미측정 · 걸음 미측정(코어 밖 측정 경로 없음 — 판 표식을 확인할 수 없다) · artifacts 를 넘겼는데 측정 기록과 다름 ·
#'   측정 판 표식 ≠ 기준 칸 판 표식. artifacts 인자는 측정 기록과 같은지 확인할 때만 쓴다.
rc_p4_step_decide <- function(chain_dir, k, artifacts = NULL, root = rc_root(), metrics_fun = rc_p4_visible_metrics, ...) {
  st <- .rcp4_state(chain_dir, root); k <- as.integer(k)
  .rcp4_need_base(st, "걸음 판정")
  o <- Filter(function(r) identical(as.integer(r$k), k), st$opens)
  if (!length(o)) .rcp4_err("열지 않은 걸음: ", k)
  if (k %in% st$decided_ks) .rcp4_err("이미 판정한 걸음 — 다시 판정하지 않는다: ", k)
  o <- o[[1]]; csa <- .rcp4_abs(o$cell_spec_path, root)
  if (!file.exists(csa) || !identical(rc_md5(csa), o$cell_spec_md5)) .rcp4_err("칸 사양이 열린 뒤 바뀌었다(R2): ", o$cell_spec_path)
  ms <- .rcp4_measured_of(st, k)
  if (is.null(ms)) .rcp4_err("측정 안 된 걸음 — 판정하지 않는다(p4-step-measure 먼저): ", k)
  if (!identical(ms$cell_spec_md5, o$cell_spec_md5)) .rcp4_err("측정 기록의 칸 사양 md5 ≠ 열린 걸음(R2): ", k)
  if (!identical(ms$vintage$id, st$base_meas$vintage$id)) .rcp4_err("걸음 측정의 팩터 DB 판 표식 ≠ 기준 칸 — 판정하지 않는다(이 사슬을 닫고 새 사슬에서 기준 칸부터 다시): ", k)
  if (!(is.null(artifacts) || !length(artifacts) || is.na(artifacts[1]) || !nzchar(artifacts[1])) && !identical(.rcp4_rel(artifacts, root), ms$artifacts))
    .rcp4_err("측정 기록(", ms$artifacts, ")과 다른 산출을 넘겼다 — 판정하지 않는다: ", artifacts)
  artifacts <- ms$artifacts; asrc <- "step_measured"
  pm <- if (identical(as.integer(o$parent), 0L)) st$base_meas$metrics else
    (Filter(function(r) identical(as.integer(r$k), as.integer(o$parent)), st$results)[[1]])$metrics
  m <- metrics_fun(.rcp4_abs(.rcp4_rel(artifacts, root), root), root = root, tau = st$spec$tau_d, ...)
  g <- function(x, nm) .rcp4_num(x[[nm]])
  T <- data.table(S_vis = g(m, "S_vis"), calmar_vis = g(m, "calmar_vis"), port_t_vis = g(m, "port_t_vis"), cagr_vis = g(m, "cagr_vis"),
                  sharpe_vis = g(m, "sharpe_vis"), mdd_vis = g(m, "mdd_vis"), uc_vis = g(m, "uc_vis"), dd_capture_median_vis = g(m, "dd_capture_median_vis"))
  T[, `:=`(dS_vis = S_vis - g(pm, "S_vis"), d_uc_vis = uc_vis - g(pm, "uc_vis"), d_dd_capture_median_vis = dd_capture_median_vis - g(pm, "dd_capture_median_vis"))]
  rules <- st$reg$rules_resolved
  A <- rc_rules_apply(rules, T)
  ids <- vapply(rules, function(r) r$id, ""); v <- vapply(ids, function(i) A[[i]][1], NA)
  accept <- all(v %in% TRUE)
  reasons <- c(sprintf("%s: 미달", ids[v %in% FALSE]), sprintf("%s: 미측정", ids[is.na(v)]))
  mg <- NA_real_; for (r in rules) if (identical(r$metric, "dS_vis")) mg <- .rcp4_num(r$value)
  ds <- T$dS_vis[1]; r7 <- if (is.finite(ds) && is.finite(mg)) (if (abs(ds) >= abs(mg)) "signal" else "noise") else NA_character_
  mk <- m[intersect(names(m), c(names(T), "n_crisis_vis", "window", "bottleneck", "card_error"))]
  rec <- list(event = "step_result", k = k, artifacts = .rcp4_rel(artifacts, root), artifacts_source = asrc, parent_basis = if (identical(as.integer(o$parent), 0L)) "base_measured" else "step",
              metrics = mk, table = as.list(T[1]), rules = as.list(stats::setNames(v, ids)), decision = if (accept) "accept" else "reject",
              reasons = as.list(reasons), r7 = r7)
  lk <- rc_after_tau_leaks(rec, st$tau); if (length(lk)) .rcp4_err("걸음 판정 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  .rcp4_append(chain_dir, rec)
}
#' 상태 줄
rc_p4_status <- function(chain_dir, root = rc_root()) {
  st <- tryCatch(.rcp4_state(chain_dir, root, need_registered = FALSE), error = function(e) e)
  if (inherits(st, "error")) return(sprintf("[P4 사슬] %s — 판독 실패: %s", basename(chain_dir), conditionMessage(st)))
  na <- sum(vapply(st$results, function(r) identical(r$decision, "accept"), TRUE)); vv <- rc_p4_steps_verify(chain_dir)
  nm <- sum(vapply(st$recs, function(r) identical(r$event, "step_measured"), TRUE))
  c(sprintf("[P4 사슬] %s · %s · 걸음 %d(판정 %d · 채택 %d · 기각 %d) · 기준 칸 %s · 측정 기록 %d · 머리 = %s · 연속 잡음 %d/%s · 최대 %s · 생성기 %s · 원장 사슬 %s(%d줄)%s",
            st$spec$chain_id, if (is.null(st$reg)) "등록 전" else "등록", length(st$opens), length(st$results), na, length(st$results) - na, if (is.null(st$base_meas)) "미측정" else "측정", nm,
            if (st$head_k == 0L) "기저" else paste("걸음", st$head_k), st$noise_streak, st$spec$budget$noise_k, st$spec$budget$max_steps,
            st$spec$generator$id, if (vv$ok) "정상" else "끊김", vv$n, if (st$closed) " · 닫힘" else ""),
    vapply(st$results, function(r) sprintf("  걸음 %s %s — %s", r$k, r$decision, if (length(r$reasons)) paste(unlist(r$reasons), collapse = " · ") else "규칙 전부 참"), ""))
}

## ── ⑤ 설계 입력(생성기에게 · 보는 창 정보만) ──────────────────────────────────────
.rcp4_f3 <- function(x) { x <- .rcp4_num(x); if (is.finite(x)) formatC(x, format = "f", digits = 3) else "—" }
#' 설계 입력 md — 기저 풀 표(성과 · 등급 열 없음 · 사유는 코드만) · 현재 최선(사슬 머리) 보는 창 지표 · A 하한별 여유 · 병목 · 열린 탐침 · 결과 원장 요약 · 걸음 이력 · 도구 상자 안내
rc_p4_design_input <- function(root = rc_root(), chain_dir, pool = NULL, outcomes_path = NULL, gap = NULL, out = NULL) {
  st <- .rcp4_state(chain_dir, root); tau <- st$tau
  op <- outcomes_path %||% rc_outcomes_path(root)
  .rcp4_need_base(st, "설계 입력")
  ha <- .rcp4_artifacts_of(st, st$head_k)
  gap <- gap %||% rc_p4_gap(.rcp4_abs(ha, root), root, tau)
  L <- character(0); a <- function(...) L <<- c(L, paste0(...))
  a("# P4 강화 사슬 설계 입력 — ", st$spec$chain_id, " (생성기 판 ", st$spec$generator$id, ")")
  a(""); a("> 보는 창(τ_D = ", format(tau), " 까지)의 R 계약 산출만 싣는다. 시험 창 값 · 등급 · 그 뒤 날짜는 없다. 수치를 새로 계산하지 마라.")
  a(""); a("## 1. 기저 풀(자격 · 사유 코드 — 성과 열 없음)"); a("")
  if (!is.null(pool) && nrow(as.data.table(pool))) {
    P <- as.data.table(pool); a("| key | 프로그램 | 상설 자격 | 자격 | 제외 사유 |"); a("|---|---|---|---|---|")
    for (i in seq_len(nrow(P))) a("| ", P$key[i], " | ", P$program[i] %||% "", " | ", if (isTRUE(P$standing_qualified[i])) "통과" else "—", " | ",
                                  if (isTRUE(P$eligible[i])) "예" else "아니오", " | ", if (nzchar(P$reason[i] %||% "")) P$reason[i] else "—", " |")
    a(""); a("- 사유 코드: ", paste(sprintf("`%s` = %s", names(RC_P4_REASONS), unname(RC_P4_REASONS)), collapse = " · "))
  } else a("- (풀을 넘기지 않았다 — 기저를 바꾸는 걸음(base · blend)은 이번에 낼 수 없다)")
  a(""); a("## 2. 현재 최선 칸(사슬 머리 = ", if (st$head_k == 0L) "기저" else paste("걸음", st$head_k), ") — 보는 창 ", gap$window[1], " ~ ", gap$window[2]); a("")
  a("| A 하한 | 값 | 문턱 | 여유 | 상대 여유 | 통과 | 문턱 출처 |"); a("|---|---|---|---|---|---|---|")
  F <- gap$floors; for (i in seq_len(nrow(F))) a("| ", F$floor[i], " | ", .rcp4_f3(F$value[i]), " | ", .rcp4_f3(F$threshold[i]), " | ", .rcp4_f3(F$margin[i]), " | ",
                                                .rcp4_f3(F$margin_rel[i]), " | ", if (isTRUE(F$pass[i])) "예" else "아니오", " | ", F$threshold_source[i], " |")
  a(""); a("- **병목(상대 여유 최소)**: ", gap$bottleneck %||% "—", " · 보는 창 MDD ", .rcp4_f3(gap$metrics$mdd_vis), " · 같은 창 KOSPI200 MDD ", .rcp4_f3(gap$bench$mdd_vis))
  hm <- st$head_metrics
  a("- 행동 카드(보는 창): 강세 상승 포착 중앙값 ", .rcp4_f3(hm$uc_vis), " · 위기 하락 포착 중앙값 ", .rcp4_f3(hm$dd_capture_median_vis), " · 위기 수 ", .rcp4_f3(hm$n_crisis_vis))
  a(""); a("## 3. 채택 규칙(사슬 판 — 기계 판정 · 당신이 판정하지 않는다)"); a(""); a(paste0("- ", rc_rules_sentences(st$reg$rules_resolved)))
  a(sprintf("- 예산: 최대 걸음 %s · 연속 '잡음 이내' %s 회면 사슬 종료 · 지금 걸음 %d · 연속 잡음 %d", st$spec$budget$max_steps, st$spec$budget$noise_k, length(st$opens), st$noise_streak))
  a(""); a("## 4. 걸음 이력"); a("")
  if (!length(st$opens)) a("- (아직 없음 — 첫 걸음)") else for (o in st$opens) {
    r <- Filter(function(x) identical(as.integer(x$k), as.integer(o$k)), st$results)
    a(sprintf("- 걸음 %s [%s · 부모 %s · 축 %s] %s — %s", o$k, o$block_type, o$parent, paste(unlist(o$changed_axes), collapse = ","),
              if (length(r)) r[[1]]$decision else "판정 대기", if (length(r)) paste(c(sprintf("dS_vis %s", .rcp4_f3(r[[1]]$table$dS_vis)), unlist(r[[1]]$reasons)), collapse = " · ") else ""))
    a("  - 가설: ", o$hypothesis); a("  - 기전: ", o$mechanism)
  }
  a(""); a("## 5. 열린 탐침(결과 원장 — 아직 아무도 이어받지 않은 다음 탐침)"); a("")
  pr <- rc_open_probes(op); if (!length(pr)) a("- (없음)") else for (p in pr) a("- ", p$ref, " (", p$program, "): ", p$text)
  a(""); a("## 6. 결과 원장 요약(최근 닫힌 라운드)"); a(""); a(rc_outcomes_md(op, program = NULL, last = 5L))
  a(""); a("## 7. 도구 상자 안내")
  a("- 한 걸음 = 블록 유형 하나: ", paste(sprintf("`%s`", RC_P4_BLOCK_TYPES), collapse = " · "), ".")
  a("- 블록 ↔ 셀 사양 축: base = base_signal(engine · 풀 key) · blend = base_signal(engine_blend · 풀 key ≥ 2) · factors · base_weight · regime_exposure · tail_overlay = overlay(+ overlay_shift) · weighting · construction = cap_core · defense_sleeve · universe · rebalance.")
  a("- 축 값의 형식 · 어휘 = `toolbox.md`(rx_toolbox_md). 고정 축(fixed_axes · 롱온리 · ≤ 25종 · 15bps · 유동성 하한)은 바꿀 수 없다.")
  txt <- paste(L, collapse = "\n")
  .rcp4_assert_clean(txt, tau, "설계 입력")
  if (!is.null(out)) writeLines(enc2utf8(txt), out, useBytes = TRUE)
  txt
}

## 최종 후보의 칸 사양 — 기저(k = 0) = 기준 칸 측정 사본 · 걸음 = 그 걸음 측정 사본(있으면) · 없으면 열린 사양
.rcp4_cand_spec <- function(st, k) {
  if (identical(as.integer(k), 0L)) return(st$base_meas$measured_spec %||% st$spec$base$cell_spec)
  fm <- .rcp4_measured_of(st, k); if (!is.null(fm)) return(fm$measured_spec)
  Filter(function(o) identical(as.integer(o$k), as.integer(k)), st$opens)[[1]]$cell_spec_path
}
## 최종 후보 모듈 풀 등재 — 반환 list(status = registered | not_registered | not_attempted | error, why, code)
.rcp4_module_pool <- function(res, fin, st, write, register_file, root) {
  if (inherits(res, "rcp4_err")) return(list(status = "not_attempted", why = "재채점 오류"))
  if (!isTRUE(write)) return(list(status = "not_attempted", why = "재채점 쓰기 없음(regrade_write = FALSE) — 선택 보정 전 등급은 올리지 않는다"))
  g <- as.character(res$grade_after %||% NA)[1]
  if (!(g %in% c("A", "B"))) return(list(status = "not_registered", why = "재채점 뒤 등급 A · B 아님"))
  if (!file.exists(register_file)) return(list(status = "pending_manual", why = "정본 등재기 파일 없음"))
  e <- new.env(parent = globalenv())
  r <- tryCatch({ invisible(utils::capture.output(suppressMessages(sys.source(register_file, envir = e, keep.source = FALSE))))
                  e$rmm_register_measured(.rcp4_abs(fin$artifacts, root), origin_mode = "replication",
                                          meta = list(origin_lane = "p4_chain", chain_id = st$spec$chain_id, chain_k = as.integer(fin$k),
                                                      strategy_idea = sprintf("[P4 강화 사슬] %s 최종 후보(걸음 %s)", st$spec$chain_id, fin$k),
                                                      registered_after_regrade = TRUE)) },
                error = function(z) structure(list(error = conditionMessage(z)), class = "rcp4_err"))
  if (inherits(r, "rcp4_err")) return(list(status = "error", why = r$error))
  list(status = if (isTRUE(r$registered)) "registered" else "not_registered", code = as.character(r$code %||% NA)[1], why = as.character(r$reason %||% "")[1])
}

## ── ⑥ 닫기 ──────────────────────────────────────────────────────────────────
#' 닫기 — 최종 후보 = 마지막 채택 걸음(없으면 '개선 없음') · 결과 원장(rc_outcome_record → rc_outcome_append_round) · 마감 훅 · 원장 chain_closed
#'   마감 훅: 02_Infrastructure/programs/selection_regrade.R::sr_regrade(후보, 시행 = 기저 + 모든 걸음 칸)가 있으면 부른다 — 결과(전기간 · 사람 쪽)는
#'   finalize.json 에만 쓰고 원장 · 결과 원장에는 상태 · 파일 md5 만 싣는다(결과 원장 = 다음 설계 입력 · 보는 창 규율). 없으면 finalize = "pending".
#'   Judge 요청 파일은 쓰지 않는다.
#'   후보 관문(2026-11-10): sr_regrade 뒤 새 등급이 A 면 02_Infrastructure/programs/round_candidate_gate.R::rcg_route(후보 산출, strategy_id, 칸 사양, root, write)를
#'   파일이 있으면 부르고 요약(action · eligible · codes · path)을 finalize.json 에 싣는다. 원장 · 결과 원장에는 상태 문자열만(candidate_gate =
#'   pending(관문 파일 없음) | evaluated(관문 판정 · A 아님 포함 — 등급이 상태로 새지 않게) | error | not_run(재채점 없음)).
#'   감독 영수증(rc_close 와 같은 자리 · 없으면 거부): philosophy_p2 = 철학 P2 리뷰 id · superfan_t2 = 판단 T2 리뷰 id(둘 다 대상 round = chain_id ·
#'   도전 응답 · 열린 보류 요청 없음). regrade_file · gate_file = 시험용 대체 파일 경로(기본 = 정본).
rc_p4_close <- function(chain_dir, note, probes = character(0), lessons = character(0), r7 = NA_character_, no_probes_reason = NULL,
                        root = rc_root(), outcomes_path = NULL, registry_path = NULL, regrade = TRUE, regrade_write = FALSE,
                        philosophy_p2 = NA_character_, superfan_t2 = NA_character_, ledger = file.path(root, RC_LEDGER_DEFAULT), review_root = root,
                        regrade_file = file.path(root, "02_Infrastructure/programs/selection_regrade.R"),
                        gate_file = file.path(root, "02_Infrastructure/programs/round_candidate_gate.R"),
                        register_file = file.path(root, "02_Infrastructure/contracts/register_measured_module.R")) {
  st <- .rcp4_state(chain_dir, root)
  if (st$closed) .rcp4_err("이미 닫힌 사슬이다")
  und <- setdiff(st$open_ks, st$decided_ks); if (length(und)) .rcp4_err("판정 안 된 걸음이 있다 — 판정 뒤 닫는다: ", paste(und, collapse = ","))
  rp2 <- .rcp4_receipt_need(philosophy_p2, "philosophy", "P2", st$spec$chain_id, root = root, ledger = ledger, review_root = review_root, stage = "사슬 닫기")
  rt2 <- .rcp4_receipt_need(superfan_t2, "judgment", "T2", st$spec$chain_id, root = root, ledger = ledger, review_root = review_root, stage = "사슬 닫기")
  acc <- Filter(function(r) identical(r$decision, "accept"), st$results); fin <- if (length(acc)) acc[[length(acc)]] else NULL
  ## 채택 0 · 걸음 ≥ 1 = 최종 후보는 기저 자신(k = 0 · 기준 칸 측정 산출) — 걸음들과 견줘 남은 것도 고른 결과라 같은 재채점을 받는다
  if (is.null(fin) && length(st$results) && !is.null(st$base_meas)) fin <- list(k = 0L, artifacts = st$base_meas$artifacts)
  ns <- length(st$results); na <- length(acc)
  by <- list(); for (o in st$opens) { bt <- o$block_type; r <- Filter(function(x) identical(as.integer(x$k), as.integer(o$k)), st$results)[[1]]
    if (is.null(by[[bt]])) by[[bt]] <- list(accept = 0L, reject = 0L)
    by[[bt]][[r$decision]] <- by[[bt]][[r$decision]] + 1L }
  if (is.na(r7)) r7 <- if (na) "signal" else if (ns) "noise" else NA_character_
  label <- sprintf("사슬 %s — 걸음 %d(채택 %d · 기각 %d) · 최종 후보 %s", st$spec$chain_id, ns, na, ns - na, if (is.null(fin)) "개선 없음" else if (identical(as.integer(fin$k), 0L)) "기저(채택 0)" else paste("걸음", fin$k))
  spec_like <- list(program = RC_P4_PROGRAM, round_id = st$spec$chain_id, template = "p4_chain", tau_d = st$spec$tau_d,
                    cells = lapply(st$opens, function(o) list(code = paste0("k", o$k), role = "variant")))
  P <- list(prereg = rc_p4_spec_path(chain_dir), results = chain_dir)
  rec <- rc_outcome_record(spec_like, list(summary = list(label = label)), note, probes = probes, lessons = lessons, r7 = r7,
                           no_probes_reason = no_probes_reason, P = P, root = root)
  rec$report <- rc_rel(rc_p4_steps_path(chain_dir), root)
  srf <- regrade_file; cg_state <- if (file.exists(gate_file)) "not_run" else "pending"
  fz <- list(status = "pending", why = "selection_regrade.R 없음", candidate_gate = cg_state)
  if (is.null(fin)) fz <- list(status = "no_candidate", why = "걸음 없음(고른 일이 없다)", candidate_gate = cg_state)
  else if (isTRUE(regrade) && file.exists(srf)) {
    trials <- unique(na.omit(c(.rcp4_abs(st$base_meas$artifacts, root), vapply(st$results, function(r) .rcp4_abs(as.character(r$artifacts), root), ""))))
    e <- new.env(parent = globalenv())
    res <- tryCatch({ invisible(utils::capture.output(suppressMessages(sys.source(srf, envir = e, keep.source = FALSE))))
                      e$sr_regrade(.rcp4_abs(fin$artifacts, root), trials, root = root, write = isTRUE(regrade_write)) },
                    error = function(z) structure(list(error = conditionMessage(z)), class = "rcp4_err"))
    ## 후보 관문 — 새 등급 A 일 때만 부른다(관문 파일이 있을 때) · 칸 사양 = 그 걸음의 측정 사본(있으면) · 없으면 열린 사양
    cg <- list(status = cg_state)
    if (!inherits(res, "rcp4_err") && file.exists(gate_file)) {
      if (!identical(as.character(res$grade_after %||% NA)[1], "A")) cg <- list(status = "evaluated", action = "not_called", why = "새 등급 A 아님")
      else {
        spec_path <- .rcp4_abs(.rcp4_cand_spec(st, fin$k), root)
        sid <- sprintf("%s_k%s", st$spec$chain_id, fin$k); ge <- new.env(parent = globalenv())
        g <- tryCatch({ invisible(utils::capture.output(suppressMessages(sys.source(gate_file, envir = ge, keep.source = FALSE))))
                        ge$rcg_route(.rcp4_abs(fin$artifacts, root), sid, spec_path, root, isTRUE(regrade_write)) },
                      error = function(z) structure(list(error = conditionMessage(z)), class = "rcp4_err"))
        cg <- if (inherits(g, "rcp4_err")) list(status = "error", error = g$error) else
          list(status = "evaluated", action = as.character(g$action %||% NA)[1], eligible = g$eligible %||% NA, codes = as.list(unlist(g$codes)),
               path = if (is.null(g$path) || all(is.na(g$path))) NA_character_ else .rcp4_rel(as.character(g$path)[1], root), strategy_id = sid,
               spec_path = .rcp4_rel(spec_path, root))
      }
    } else if (inherits(res, "rcp4_err") && file.exists(gate_file)) cg <- list(status = "not_run", why = "재채점 오류")
    ## 2계층 모듈 풀 등재 — 최종 후보 1개만 · 재채점을 실제로 썼고(regrade_write) 재채점 뒤 등급 A | B 일 때 · 정본 등재기를 측정 밖에서 산출 폴더만으로 부른다
    ##   (contracts/register_measured_module.R::rmm_register_measured — sim 없으면 계약 CSV 로 재조립 · 새 측정 없음 · rf_replication_verify.R 감사 뒤 등재와 같은 사후 호출).
    ##   자격은 등재기의 계약 술어(rmm_admission)가 다시 낸다. 걸음 · 기준 칸 측정은 등재를 끈다(rc_p4_runner_default).
    mp <- .rcp4_module_pool(res, fin, st, regrade_write, register_file, root)
    ff <- file.path(chain_dir, "finalize.json")
    rc_json_write(list(schema = "rc_p4_finalize_v1", audience = "사람 쪽(전기간 · 시험 창 포함 가능) — 처방 · 리뷰 레인 열람 금지",
                       at = rc_now(), candidate = fin$artifacts, trials = as.list(vapply(trials, .rcp4_rel, "", root = root)), write = isTRUE(regrade_write),
                       result = if (inherits(res, "rcp4_err")) list(error = res$error) else res, candidate_gate = cg, module_pool = mp), ff)
    fz <- list(status = if (inherits(res, "rcp4_err")) "error" else "done", regrade_status = if (inherits(res, "rcp4_err")) NA_character_ else as.character(res$status %||% NA)[1],
               candidate_gate = cg$status,
               ## 등재 여부(registered | not_registered)는 전기간 등급 B 이상인지를 드러낸다 — 결과 원장 · 사슬 원장은 다음 설계 입력이 읽는
               ##   자리라 'evaluated' 로만 싣는다(candidate_gate 와 같은 규율 · 실제 상태는 finalize.json 에만).
               module_pool = if (mp$status %in% c("registered", "not_registered")) "evaluated" else mp$status,
               file = rc_rel(ff, root), md5 = rc_md5(ff), n_trials = length(trials), write = isTRUE(regrade_write))
  } else if (!isTRUE(regrade)) fz <- list(status = "pending", why = "regrade = FALSE", candidate_gate = cg_state)
  sf <- list(philosophy_p2 = rp2, superfan_t2 = rt2)
  rec$extra <- list(generator_version = st$spec$generator$id, n_steps = ns, n_accepted = na, by_block = by,
                    final_candidate = if (is.null(fin)) NULL else list(k = fin$k, artifacts = fin$artifacts), chain_spec_md5 = st$reg$spec_md5,
                    finalize = fz[c("status", intersect(names(fz), c("regrade_status", "candidate_gate", "module_pool", "why", "md5")))],   # 등급 전후 값 · 관문 판정은 finalize.json 에만(전기간)
                    philosophy_p2 = rp2$id, superfan_t2 = rt2$id)
  ap <- if (is.null(outcomes_path)) rc_outcomes_path(root, registry_path) else outcomes_path
  rc_outcome_append_round(rec, ap)
  .rcp4_append(chain_dir, list(event = "chain_closed", label = label, final_k = if (is.null(fin)) NULL else fin$k, finalize = fz, outcomes = rc_rel(ap, root),
                               superfan = sf))
  invisible(list(label = label, final = fin, finalize = fz))
}

## ── ⑦' 생성기 검토(다음 판을 쓰는 재료 · 보는 창 정보만) ───────────────────────────
#' 걸음 원장들 + 결과 원장(P4)에서 블록 유형별 채택률 · 보는 창 S 개선(걸음 dS_vis 목록) · 주된 기각 사유 · 생성기 판별 집계
rc_p4_generator_review <- function(root = rc_root(), chain_dirs = NULL, outcomes_path = NULL, out = NULL) {
  tau <- as.Date(.rcp4_tau(root))
  chain_dirs <- chain_dirs %||% dirname(Sys.glob(file.path(root, "04_Research/programs", RC_P4_PROGRAM, "*", "chain_spec.json")))
  rows <- list()
  for (d in chain_dirs) {
    st <- tryCatch(.rcp4_state(d, root, need_registered = FALSE), error = function(e) NULL); if (is.null(st)) next
    for (o in st$opens) { r <- Filter(function(x) identical(as.integer(x$k), as.integer(o$k)), st$results)
      rows[[length(rows) + 1L]] <- data.table(chain = st$spec$chain_id, generator = o$generator_version, k = as.integer(o$k), block = o$block_type,
                                              decision = if (length(r)) r[[1]]$decision else "pending", dS = if (length(r)) .rcp4_num(r[[1]]$table$dS_vis) else NA_real_,
                                              reasons = if (length(r)) paste(sub(":.*$", "", unlist(r[[1]]$reasons)), collapse = ";") else "") }
  }
  D <- if (length(rows)) rbindlist(rows) else data.table(chain = character(0), generator = character(0), k = integer(0), block = character(0),
                                                         decision = character(0), dS = numeric(0), reasons = character(0))
  L <- character(0); a <- function(...) L <<- c(L, paste0(...))
  a("# P4 생성기 검토 — 다음 판을 쓰는 재료(보는 창 정보만)"); a("")
  a(sprintf("- 사슬 %d · 걸음 %d · 판정 %d", uniqueN(D$chain), nrow(D), sum(D$decision != "pending")))
  a(""); a("## 블록 유형별"); a(""); a("| 블록 | 걸음 | 채택 | 기각 | 채택 비율 | 보는 창 dS_vis(걸음 순) | 주된 기각 사유 |"); a("|---|---|---|---|---|---|---|")
  for (b in sort(unique(D$block))) { X <- D[block == b]; nj <- sum(X$decision != "pending"); nac <- sum(X$decision == "accept")
    rs <- table(unlist(strsplit(X[decision == "reject"]$reasons, ";", fixed = TRUE))); rs <- rs[nzchar(names(rs))]
    a("| ", b, " | ", nrow(X), " | ", nac, " | ", sum(X$decision == "reject"), " | ", if (nj) sprintf("%d/%d", nac, nj) else "—", " | ",
      paste(vapply(X$dS, .rcp4_f3, ""), collapse = ", "), " | ", if (length(rs)) paste(sprintf("%s %d", names(sort(rs, decreasing = TRUE)), as.integer(sort(rs, decreasing = TRUE))), collapse = " · ") else "—", " |") }
  a(""); a("## 생성기 판별"); a("")
  for (g in sort(unique(D$generator))) { X <- D[generator == g]; a(sprintf("- %s: 걸음 %d · 채택 %d · 기각 %d", g, nrow(X), sum(X$decision == "accept"), sum(X$decision == "reject"))) }
  a(""); a("## 결과 원장(P4)"); a(""); a(rc_outcomes_md(outcomes_path %||% rc_outcomes_path(root), program = RC_P4_PROGRAM, last = 10L))
  txt <- paste(L, collapse = "\n"); .rcp4_assert_clean(txt, tau, "생성기 검토")
  if (!is.null(out)) writeLines(enc2utf8(txt), out, useBytes = TRUE)
  invisible(list(md = txt, table = D))
}
