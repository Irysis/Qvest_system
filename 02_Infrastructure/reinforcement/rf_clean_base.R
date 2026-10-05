#==============================================================================
# rf_clean_base.R — A 경로 청정 기저(F_A) 선정 계약 (결정 FLOOR-BASE-ENGINE-Q4 · 2026-09-25)
#
# 무엇: "성과를 보지 않고 고른 충실구현 논문 엔진 + as-of 팩터 층 · 교차 entry 노출 0" 을 규칙으로 고른다.
#   ① 후보 = 원장 L1 entry 의 engine_path(허용 필드 투영 뒤) — 엔진 파일 단위.
#   ② 구조 술어(성과 무관): 충실구현 레인 · 충실도 감사(미신고 변경 0) · 현행 PIT 정적 검출 · C11 격리(P0-14 관문 함수) ·
#      PIT/빈티지 표식 · FACTORS 산출 + 후보 폭 > n_max · 격자 창 커버리지 · 지문 밖 원천 0.
#   ③ 노출 통로(엔진을 쓴 에이전트가 무엇을 봤나): 설계 프롬프트(결합 절 · 재구현 피드백의 측정 성과) · 작업 디렉터리의 레인 밖 파일 ·
#      구현 전사(자동 주입 기억 MEMORY.md 의 성과 수치 · Read/Grep/Glob 의 성과 경로 열람) · 시계 순서(prompt ≤ engine ≤ audit).
#   ④ 순서 = 결정 레코드(id·decided_at) salt 의 sha256(paper_key) — 운영자 재량 0. 상위 n = F_A 후보(1순위 + 사전 선언 승계자).
#   ⑤ 채택 범위(full)에서 후보가 0 이면 문서가 그렇게 말하고(blocked_no_clean_candidate), 구조 술어만 통과한 논문을 같은 순서로
#      청정실(clean-room) 재구현 대기열로 싣는다 — 새 엔진은 측정하지 않은 채 사전등록 핀으로 들어간다.
#   ⑥ as-of 팩터 층 = rf_factor_arms.R::rf_pick_factor_sets(깊이 = 격자 B1 depths 최대 · 시드 오프셋 · as-of = 격자 start_date) 드라이런.
#
# ★성과 비노출(검사로 증명): 원장은 cfg$performance_blind$ledger_fields_allowed 투영 뒤에만 쓴다 · 산출물은 00_manifest.json·
#   01_strategy_spec.json(허용 필드)·factors_panel.parquet(Date·Ticker·Score 의 개수·날짜)만 연다 · 문서에 성과 키가 있으면 stop.
#   검사 = 08_Tests/reinforcement/test_rf_clean_base.R [P] 성과 필드 교란 불변 + 등급을 읽는 돌연변이 red.
# ★재사용(사본 금지): rf_floor_v2.R(rfv_base_engine_exposure · .rfv_section_hits · rfv_write · rfv_diff · rfv_env) ·
#   rf_lineage_flags.R::rflf_c11_derive · lookahead_detector.R::detect_lookahead · pin_cache.R 지문 정의(parse→eval) ·
#   rf_fidelity_audit_lib.R::rf_audit_read(parse→eval — 파일 머리의 ROOT/LOG 부작용 회피) · rf_factor_arms.R::rf_pick_factor_sets.
# 쓰기: rfc_write 만(원자적 · 기존 파일과 내용이 다르면 거부 = rfv_write 규약). 원장·결정 레지스터·다른 파일 무쓰기. 측정 0.
# 공개: rfc_load_cfg · rfc_env · rfc_ledger_view · rfc_candidates · rfc_structural · rfc_exposure · rfc_transcript_index ·
#       rfc_salt · rfc_order · rfc_select · rfc_factor_layer · rfc_fa_spec · rfc_build · rfc_write · rfc_verify · rfc_forbidden_keys
# 검사: 08_Tests/reinforcement/test_rf_clean_base.R
#
# (FA-CLEAN-BASE-PATH 2026-09-26 · 도훈 결정 (나) 기존 레인 강화) — 청정 실행 인정 + 탐지기 위양성 수리:
#   ▸ 무인 충실구현 레인 청정 모드(rf_replication_auto.sh · rf_clean_lane.py)가 작업 디렉터리에 남기는 출처 기록(lane_provenance.json)을
#     **믿지 않고 대조**한다(rfc_lane_provenance → rfc_exposure): 프롬프트 sha256 = 현재 prompt.txt = 전사 첫 레코드 content ·
#     엔진 sha256 = 현재 engine.R · 전사의 Read/Grep/Glob 전부에 청정 가드 증명(hook_success stdout 통과 표식 또는 clean_lane 차단 결과) ·
#     재구현이면 감사 지적 출처 = 보존된 감사 프롬프트 사본의 '청정 모드 — 비공개' · (10-03) 새 엔진 경로 = 기록 engine_rel 이 이 후보이고
#     디렉터리 이름이 청정 접두(설정 engine_dir_regex). 하나라도 어긋나면 판독 불가(NA · D7 로 자격 없음).
#   ▸ 전사 판독: 가드가 **막은** 성과 경로 시도는 열람이 아니다(tool_result 오류 문형으로 가른다) · 훅 주입 문맥(hook_additional_context)의
#     수치는 자동 주입 노출 · 규칙 파일(프로젝트 종류 — CLAUDE.md·.claude/rules)은 알려진 경계로 경로·sha256·수치 개수만 기록 · 저장소 웹 사본 열람 = 노출.
#   ▸ 숨은 로더: 원문 텍스트 문형 → 파싱한 식의 호출 흐름(.rfc_hidden_loader_flow) — 진단 전용 호출(2001.04185 .crowding_diag)은
#     지문 밖 원천으로 세지 않되 산출로 흐르면 여전히 탈락(설정 hidden_loader_flow · 검사 [H] 양방향).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
.rfc_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.rfc_chr1 <- function(x) { x <- as.character(unlist(.rfc_or(x, ""))); if (!length(x) || is.na(x[1])) "" else x[1] }
.RFC_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.RFC_CANON_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"   # 원장 절대경로 정규화 전용(설정값 아님)
.rfc_np <- function(p) gsub("\\", "/", .rfc_chr1(p), fixed = TRUE)
.rfc_md5 <- function(p) { p <- .rfc_chr1(p); if (nzchar(p) && file.exists(p) && !dir.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_ }
.rfc_json <- function(p) { p <- .rfc_chr1(p); if (nzchar(p) && file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL }
RFC_SCHEMA <- "reference_floor_clean_v1"
.rfc_I <- function(x) I(as.character(unlist(x)))   # 문자 벡터를 JSON 배열로 고정(길이 0·1 포함 · NULL 안전)

#' 설정 판독 — 필수 키 부재·어휘 밖 값이면 stop(후보·수치를 코드에 박지 않는다)
rfc_load_cfg <- function(path) {
  if (!file.exists(path)) stop("[rf_clean_base] 설정 부재: ", path)
  cfg <- fromJSON(path, simplifyVector = FALSE)
  need <- c("schema", "decision", "floor_v2", "performance_blind", "predicates", "exposure", "ordering", "pick", "factor_layer", "spec", "evidence")
  miss <- setdiff(need, names(cfg)); if (length(miss)) stop("[rf_clean_base] 설정 필수 키 부재: ", paste(miss, collapse = ", "))
  pb <- cfg$performance_blind
  if (!length(pb$ledger_fields_allowed) || !length(pb$artifact_files_allowed) || !nzchar(.rfc_chr1(pb$doc_forbidden_key_regex)))
    stop("[rf_clean_base] performance_blind(ledger_fields_allowed · artifact_files_allowed · doc_forbidden_key_regex) 부재 — 성과 비노출을 건너뛰지 않는다")
  bad <- intersect(unlist(pb$ledger_fields_allowed), c("base_grade", "attempts", "status", "base_remeasure", "base_essence_history", "parked_reason"))
  if (length(bad)) stop("[rf_clean_base] 성과 필드가 허용 목록에 있다: ", paste(bad, collapse = ", "))
  ex <- cfg$exposure
  sc <- .rfc_chr1(ex$scope)
  if (!nzchar(sc) || is.null(ex$scopes[[sc]])) stop("[rf_clean_base] exposure.scope(", sc, ")가 exposure.scopes 에 없다")
  known <- c("prompt_missing", "prompt_combo", "prompt_feedback_measured", "provenance_order", "wdir_extra_before_engine",
             "transcript_missing", "transcript_auto_memory", "transcript_tool_reads")
  for (s in names(ex$scopes)) { u <- setdiff(unlist(ex$scopes[[s]]), known)
    if (length(u)) stop("[rf_clean_base] exposure.scopes.", s, " 에 알 수 없는 통로: ", paste(u, collapse = ", ")) }
  if (!identical(.rfc_chr1(cfg$ordering$kind), "sha256_salted") || !length(cfg$ordering$salt_from_decision_fields))
    stop("[rf_clean_base] ordering 은 {kind: sha256_salted, salt_from_decision_fields: [...]} 여야 한다")
  n <- suppressWarnings(as.integer(.rfc_or(cfg$pick$n, NA)))
  if (!is.finite(n) || n < 1L) stop("[rf_clean_base] pick.n 은 1 이상 정수")
  dk <- .rfc_chr1(cfg$factor_layer$depth_rule$kind)
  if (!dk %in% c("grid_b1_depths_max", "match_floor", "literal")) stop("[rf_clean_base] 알 수 없는 factor_layer.depth_rule.kind: ", dk)
  so <- cfg$factor_layer$seed_offset
  if (!is.numeric(so) || so < 0) stop("[rf_clean_base] factor_layer.seed_offset 은 0 이상 정수")
  if (!nzchar(.rfc_chr1(cfg$floor_v2$config))) stop("[rf_clean_base] floor_v2.config 부재 — 결합 절 검출식을 빌릴 곳이 없다")
  # (FA-CLEAN-BASE-PATH 2026-09-26) 청정 레인 대조 설정 — 있으면 온전해야 한다(반쪽 설정으로 청정을 인정하지 않는다)
  lp <- cfg$exposure$lane_provenance
  if (!is.null(lp)) {
    tol <- suppressWarnings(as.numeric(.rfc_or(lp$start_tolerance_sec, NA)))
    if (!nzchar(.rfc_chr1(lp$file)) || !nzchar(.rfc_chr1(lp$schema)) || !nzchar(.rfc_chr1(lp$clean_mode_value)) || !is.finite(tol) || tol < 0 ||
        !nzchar(.rfc_chr1(lp$audit_src_clean_regex)) || !nzchar(.rfc_chr1(lp$audit_src_art_regex)) ||
        !nzchar(.rfc_chr1(lp$engine_dir_regex)) || inherits(tryCatch(grepl(.rfc_chr1(lp$engine_dir_regex), "x", perl = TRUE), error = function(e) e), "error"))
      stop("[rf_clean_base] exposure.lane_provenance 불완전(file·schema·clean_mode_value·start_tolerance_sec·audit_src_*·engine_dir_regex)")
    ga <- cfg$exposure$transcript$guard_attestation
    if (is.null(ga) || !nzchar(.rfc_chr1(ga$pass_stdout)) || !nzchar(.rfc_chr1(ga$command_regex)) || !nzchar(.rfc_chr1(ga$clean_block_regex)) ||
        !nzchar(.rfc_chr1(cfg$exposure$transcript$blocked_result_regex)))
      stop("[rf_clean_base] 청정 대조 설정은 있는데 transcript.guard_attestation·blocked_result_regex 가 불완전 — 가드 작동을 재도출할 수 없다")
  }
  fl <- cfg$predicates$source_scope$hidden_loader_flow
  if (!is.null(fl) && (!identical(.rfc_chr1(fl$rule), "diagnostic_only_exempt") || !length(fl$side_effect_calls) || !length(fl$global_assign_ops)))
    stop("[rf_clean_base] predicates.source_scope.hidden_loader_flow 불완전(rule=diagnostic_only_exempt · side_effect_calls · global_assign_ops)")
  # (10-04 F_A v2 D2) 가드 증명 없는 실행의 열람 범위 — 허용 목록은 청정 가드 정책 파일이 단일 출처다(사본 금지 · 코드 루트에서 읽는다).
  #   설정이 있으면 온전해야 한다: 정책 판독 불가·항목 결함 = stop(빈 허용 목록으로 '전부 밖'이 되면 조용히 전원 탈락 — 그것도 fail-closed 지만 원인을 숨긴다)
  us <- cfg$exposure$transcript$unattested_scope
  if (!is.null(us)) {
    pp <- file.path(.RFC_ROOT(), .rfc_chr1(us$allow_policy))
    if (!nzchar(.rfc_chr1(us$allow_policy)) || !file.exists(pp)) stop("[rf_clean_base] unattested_scope.allow_policy 부재: ", pp)
    pol <- tryCatch(fromJSON(pp, simplifyVector = FALSE)$clean_lane, error = function(e) NULL)
    al <- vapply(.rfc_or(pol$read_allow, list()), function(a) tolower(sub("^/+", "", gsub("\\", "/", .rfc_chr1(a$path), fixed = TRUE))), "")
    if (!length(al) || any(!nzchar(al)) || any(grepl("(^|/)\\.\\.(/|$)|[*?\\[]", al)))
      stop("[rf_clean_base] unattested_scope 허용 목록(", pp, " clean_lane.read_allow) 판독 불가·항목 결함")
    if (!length(us$exec_tool_names)) stop("[rf_clean_base] unattested_scope.exec_tool_names 부재")
    cfg$exposure$transcript$unattested_scope$.allow <- al
    cfg$exposure$transcript$unattested_scope$.glob_names_in_repo <- isTRUE(pol$glob_names_in_repo)
  } else if (!is.null(cfg$exposure$lane_provenance)) stop("[rf_clean_base] exposure.transcript.unattested_scope 부재 — 가드 증명 없는 실행의 열람 범위를 잴 수 없다(F_A v2 D2)")
  cfg
}

# ── 정본 적재 ──────────────────────────────────────────────────────────────────────
.rfc_parse_defs <- function(path, name_re) {
  ex <- parse(path, encoding = "UTF-8", keep.source = FALSE)
  env <- new.env(parent = globalenv())   # rf_audit_read 는 jsonlite::fromJSON 을 한정 없이 부른다 — baseenv 부모면 조용히 '파손'이 된다
  for (e in as.list(ex))
    if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && grepl(name_re, as.character(e[[2]]))) eval(e, env)
  env
}
#' 정본 계약 적재(격리 환경) — rf_floor_v2.R(+rfv_env → rf_factor_arms.R·rf_runner_gates.R) · rf_lineage_flags.R · lookahead_detector.R ·
#'   pin_cache.R 지문 정의 · rf_fidelity_audit_lib.R 판독기
rfc_env <- function(code_root = .RFC_ROOT()) {
  en <- new.env(parent = globalenv())
  rel <- c(floor = "02_Infrastructure/reinforcement/rf_floor_v2.R", lflags = "02_Infrastructure/reinforcement/rf_lineage_flags.R",
           la = "02_Infrastructure/validation/lookahead_detector.R", pin = "02_Infrastructure/data/pin_cache.R",
           aud = "02_Infrastructure/ops/rf_fidelity_audit_lib.R")
  for (k in names(rel)) if (!file.exists(file.path(code_root, rel[[k]]))) stop("[rf_clean_base] 정본 계약 부재: ", file.path(code_root, rel[[k]]))
  invisible(capture.output(suppressMessages(sys.source(file.path(code_root, rel[["floor"]]), envir = en, keep.source = FALSE))))
  invisible(capture.output(suppressMessages(sys.source(file.path(code_root, rel[["lflags"]]), envir = en, keep.source = FALSE))))
  en$.fe <- en$rfv_env(code_root)                                    # rf_pick_factor_sets · rf_root_papers_for · rf_adversary_status
  la <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(file.path(code_root, rel[["la"]]), envir = la, keep.source = FALSE))))
  en$.la <- la
  en$.pin <- .rfc_parse_defs(file.path(code_root, rel[["pin"]]), "^(pin_fingerprint|pin_complete_month_end|pin_fp_|\\.pin_fp_)")
  en$.aud <- .rfc_parse_defs(file.path(code_root, rel[["aud"]]), "^(RF_AUDIT_VERDICTS|rf_audit_read|`%\\|\\|%`|%\\|\\|%)$")
  if (!exists("%||%", envir = en$.aud, inherits = FALSE)) assign("%||%", function(a, b) if (is.null(a) || length(a) == 0L) b else a, envir = en$.aud)
  environment(en$.aud$rf_audit_read) <- en$.aud
  for (fn in c("rfv_base_engine_exposure", ".rfv_section_hits", "rfv_write", "rfv_diff", ".rfv_cmp_view", ".rfv_rt", "rflf_c11_derive"))
    if (!exists(fn, envir = en, mode = "function", inherits = FALSE)) stop("[rf_clean_base] 정본 함수 부재: ", fn)
  for (fn in c("rf_pick_factor_sets", "rf_root_papers_for")) if (!exists(fn, envir = en$.fe, mode = "function")) stop("[rf_clean_base] 정본 함수 부재: ", fn)
  if (!exists("detect_lookahead", envir = la, mode = "function")) stop("[rf_clean_base] detect_lookahead 부재")
  for (fn in c("pin_fp_consumers", ".pin_fp_sources")) if (!exists(fn, envir = en$.pin, mode = "function")) stop("[rf_clean_base] pin_cache.R 정의 부재: ", fn)
  if (!exists("rf_audit_read", envir = en$.aud, mode = "function")) stop("[rf_clean_base] rf_audit_read 부재")
  en$.code_root <- code_root
  en
}

# ── 성과 비노출 투영 ───────────────────────────────────────────────────────────────
#' 원장 L1 을 허용 필드만 남긴 투영으로 — 규칙은 이 투영만 본다(등급·attempts·status 는 투영 밖)
rfc_ledger_view <- function(root, cfg) {
  p <- file.path(root, "06_Registry/reinforce_ledger_l1.json")
  if (!file.exists(p)) stop("[rf_clean_base] 원장 부재: ", p)
  L <- fromJSON(p, simplifyVector = FALSE)
  keep <- as.character(unlist(cfg$performance_blind$ledger_fields_allowed))
  E <- lapply(.rfc_or(L$entries, list()), function(e) e[intersect(names(e), keep)])
  list(entries = E, md5 = .rfc_md5(p), path = "06_Registry/reinforce_ledger_l1.json")
}
.rfc_rel <- function(p, root) {
  p <- .rfc_np(p); if (!nzchar(p)) return("")
  for (r in unique(c(.rfc_np(root), .RFC_CANON_ROOT))) if (startsWith(tolower(p), tolower(paste0(r, "/")))) return(substring(p, nchar(r) + 2L))
  sub("^\\./", "", p)
}
.rfc_abs <- function(rel, root) if (!nzchar(rel)) "" else if (grepl("^([A-Za-z]:)?/", rel)) rel else file.path(root, rel)
.rfc_allowed_json <- function(p, keep) { j <- .rfc_json(p); if (is.null(j)) NULL else j[intersect(names(j), as.character(unlist(keep)))] }

#' 후보 = 엔진 파일 단위 묶음(투영 원장)
rfc_candidates <- function(view, root, cfg) {
  pk_combo <- .rfc_chr1(cfg$predicates$lane$paper_key_combo_regex)
  by <- list()
  for (e in view$entries) {
    rel <- .rfc_rel(e$engine_path, root); if (!nzchar(rel)) next
    is_root <- is.null(e$parent) && is.null(e$combo)
    x <- .rfc_or(by[[rel]], list(engine = rel, entries = character(0), root_entries = list()))
    x$entries <- c(x$entries, .rfc_chr1(e$base_id))
    if (is_root) x$root_entries[[length(x$root_entries) + 1L]] <- e
    by[[rel]] <- x
  }
  lapply(by, function(x) {
    R <- x$root_entries
    pks <- unique(vapply(R, function(e) .rfc_chr1(e$paper_key), ""))
    arts <- unique(vapply(R, function(e) .rfc_rel(e$base_artifacts, root), ""))
    arts <- arts[nzchar(arts)]
    # 산출물이 여럿이면 매니페스트 run_datetime 이 가장 늦은 것(허용 필드) — 성과 무관
    rdt <- vapply(arts, function(a) .rfc_chr1(.rfc_allowed_json(file.path(root, a, "00_manifest.json"), cfg$performance_blind$manifest_fields_allowed)$run_datetime), "")
    art <- if (length(arts)) arts[order(rdt, arts, decreasing = TRUE)][1] else ""
    flags <- unique(unlist(lapply(R, function(e) vapply(.rfc_or(e$base_vintage_flags, list()), function(z) .rfc_chr1(z$flag), ""))))
    list(engine = x$engine, engine_dir = dirname(x$engine), entries = x$entries,
         root_entries = vapply(R, function(e) .rfc_chr1(e$base_id), ""),
         paper_key = paste(sort(pks[nzchar(pks)]), collapse = "+"),
         paper_key_combo = any(grepl(pk_combo, pks, perl = TRUE)),
         artifacts = art, artifacts_all = arts, base_vintage_flags = flags[nzchar(flags)])
  })
}

# ── 숨은 로더 흐름 판정 (FA-CLEAN-BASE-PATH 2026-09-26 · 2001.04185 위양성 수리) ───────────────────────────────
#   구판: 엔진 **원문 텍스트**(주석 포함)에 로더 호출 문형이 있으면 원천으로 셌다 — 진단 전용 호출(2001.04185 engine.R:251-257
#   .crowding_diag() 의 load_investor → cat 출력만 · 산출물 무영향)도 탈락시켰다.
#   신판: 파싱한 식에서 **실제 호출**만 찾고, 산출(FACTORS/PORTFOLIO)로 흐를 수 없는 진단 전용 호출만 뺀다(설정 hidden_loader_flow ·
#   판정 5조건 = 설정 why). 모르면 센다(fail-closed) — 파싱 실패 = NA.
.RFC_EMPTY <- function(x) is.symbol(x) && !nzchar(as.character(x))
.rfc_callee <- function(x) {
  f <- x[[1]]
  if (is.name(f)) return(as.character(f))
  if (is.call(f) && length(f) == 3L && as.character(f[[1]])[1] %in% c("::", ":::") && is.name(f[[3]])) return(as.character(f[[3]]))
  ""
}
# 식 순회 — 호출 노드마다 fun(node, in_fun_literal). function(...) 리터럴 안으로도 들어간다(기본값·본문).
.rfc_walk <- function(x, fun, in_fn = FALSE) {
  if (is.call(x)) {
    fun(x, in_fn)
    isfn <- identical(x[[1]], as.name("function"))
    for (i in seq_len(length(x))[-1]) {
      if (isfn && i == 4L) next                                   # srcref
      if (.RFC_EMPTY(x[[i]])) next
      if (isfn && i == 2L) { fm <- x[[2]]; for (j in seq_along(fm)) if (!.RFC_EMPTY(fm[[j]])) .rfc_walk(fm[[j]], fun, TRUE); next }
      .rfc_walk(x[[i]], fun, in_fn || isfn)
    }
  }
  invisible(NULL)
}
.rfc_syms <- function(x) {                                        # 식 안의 기호 전부(호출 함수 위치 포함)
  out <- character(0)
  rec <- function(z) {
    if (is.name(z)) { if (nzchar(as.character(z))) out <<- c(out, as.character(z)); return(invisible()) }
    if (is.call(z) || is.pairlist(z)) for (i in seq_along(z)) if (!.RFC_EMPTY(z[[i]])) rec(z[[i]])
  }
  rec(x); out
}
.rfc_lhs_base <- function(l) { while (is.call(l) && length(l) >= 2L) l <- l[[2]]; if (is.name(l)) as.character(l) else "" }
.rfc_hidden_loader_flow <- function(eng_abs, loaders, fcfg) {
  res <- list(status = "ok", counted = character(0), diagnostic = character(0), detail = list())
  if (!length(loaders)) return(res)
  ex <- tryCatch(parse(eng_abs, keep.source = TRUE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(ex, "error")) return(list(status = "parse_error", counted = loaders, diagnostic = character(0), detail = list(error = conditionMessage(ex))))
  sr <- attr(ex, "srcref")
  line_of <- function(i) if (!is.null(sr) && length(sr) >= i) as.integer(sr[[i]][1]) else NA_integer_
  sidefx <- as.character(unlist(fcfg$side_effect_calls)); gops <- as.character(unlist(fcfg$global_assign_ops))
  wfile <- c("cat", "print", "message", "writeLines", "saveRDS", "fwrite", "write.csv", "write.table", "write", "save", "sink",
             "write_parquet", "write_feather", "file.create", "file.copy", "file.rename", "file.remove", "unlink", "dir.create", "library", "require")
  # 최상위 이름 함수 정의
  fdefs <- list()
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))) {
      nm <- as.character(e[[2]]); fdefs[[nm]] <- c(fdefs[[nm]], i)
    }
  }
  strs <- character(0)                                             # 문자열 상수 전부(문자열 참조 판정)
  for (i in seq_along(ex)) .rfc_walk(ex[[i]], function(n, f) for (k in seq_len(length(n))[-1]) if (!.RFC_EMPTY(n[[k]]) && is.character(n[[k]])) strs <<- c(strs, n[[k]]))
  allsym <- unlist(lapply(as.list(ex), .rfc_syms))
  lhs_all <- character(0)                                          # 대입 대상 기호(단순·복합 LHS 의 밑 기호)
  for (i in seq_along(ex)) .rfc_walk(ex[[i]], function(n, f) if (as.character(n[[1]])[1] %in% c("<-", "=", "<<-") && length(n) == 3L) lhs_all <<- c(lhs_all, .rfc_lhs_base(n[[2]])))
  refd <- function(s) sum(allsym == s) - sum(lhs_all == s) > 0L || s %in% strs
  # 로더 호출 지점: (최상위 식 번호, 둘러싼 최상위 함수 이름 | NA)
  sites <- list()
  for (i in seq_along(ex)) {
    e <- ex[[i]]; encl <- NA_character_
    is_def <- is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
    if (is_def) encl <- as.character(e[[2]])
    .rfc_walk(e, function(n, f) {
      cn <- .rfc_callee(n)
      if (cn %in% loaders) sites[[length(sites) + 1L]] <<- list(loader = cn, i = i, encl = encl, how = "call")
      if (cn %in% c("do.call", "match.fun", "get", "get0", "mget", "exists", "Recall") && length(n) >= 2L && is.character(n[[2]]) && n[[2]] %in% loaders &&
          !identical(cn, "exists"))
        sites[[length(sites) + 1L]] <<- list(loader = n[[2]], i = i, encl = encl, how = paste0("string:", cn))
    })
  }
  why_not <- function(F) {                                         # 진단 전용 자격 — 사유(빈 문자열 = 자격)
    if (length(fdefs[[F]]) != 1L) return("defined_more_than_once")
    di <- fdefs[[F]]; fl <- ex[[di]][[3]]; body <- fl[[3]]
    formals_ <- names(as.list(fl[[2]]))
    loc <- character(0)
    .rfc_walk(body, function(n, f) {
      op <- as.character(n[[1]])[1]
      if (op %in% c("<-", "=") && length(n) == 3L && is.name(n[[2]])) loc <<- c(loc, as.character(n[[2]]))
      if (op == "for" && is.name(n[[2]])) loc <<- c(loc, as.character(n[[2]]))
    })
    loc <- setdiff(loc, formals_)
    bad <- character(0)
    .rfc_walk(body, function(n, f) {
      op <- .rfc_callee(n)
      if (op %in% gops) bad <<- c(bad, paste0("global_assign:", op))
      if (op %in% sidefx) bad <<- c(bad, paste0("side_effect:", op))
      if (op %in% wfile && "file" %in% names(n)) bad <<- c(bad, paste0("file_write:", op))
      if (op %in% setdiff(wfile, c("cat", "print", "message"))) bad <<- c(bad, paste0("file_or_attach:", op))
      if (op == ":=") bad <<- c(bad, "walrus_seen")               # 표적은 아래 [ 판정이 가른다 — 여기서는 표식만
      if (op == "[" && length(n) >= 2L) {
        has_w <- FALSE
        for (k in seq_len(length(n))[-(1:2)]) if (!.RFC_EMPTY(n[[k]]) && is.call(n[[k]]) && identical(.rfc_callee(n[[k]]), ":=")) has_w <- TRUE
        if (has_w) { tb <- .rfc_lhs_base(n[[2]]); if (!nzchar(tb) || !(tb %in% loc)) bad <<- c(bad, paste0("walrus_nonlocal:", tb)) else bad <<- c(bad, "walrus_local_ok") }
      }
      if (op %in% c("<-", "=") && length(n) == 3L && is.call(n[[2]])) {
        tb <- .rfc_lhs_base(n[[2]]); if (!nzchar(tb) || !(tb %in% loc)) bad <<- c(bad, paste0("complex_assign_nonlocal:", tb))
      }
    })
    # := 는 [ 안에서만 쓰였고 전부 지역 표적이면 통과(표식 두 종 상쇄)
    nw <- sum(bad == "walrus_seen"); nl <- sum(bad == "walrus_local_ok")
    bad <- setdiff(bad, c("walrus_seen", "walrus_local_ok")); if (nw > nl) bad <- c(bad, "walrus_outside_bracket")
    if (length(bad)) return(paste(unique(bad), collapse = ","))
    if (F %in% strs) return("string_reference")
    # F 사용처: 정의 밖 — 호출 위치로만 · 최상위 문장 · 값 흐름 없음
    for (i in setdiff(seq_along(ex), di)) {
      e <- ex[[i]]
      is_def <- is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
      calls <- 0L; vals <- 0L
      .rfc_walk(e, function(n, f) { if (identical(.rfc_callee(n), F)) calls <<- calls + 1L })
      vals <- sum(.rfc_syms(e) == F) - calls
      if (vals > 0L) return("value_reference")
      if (!calls) next
      if (is_def) return(paste0("called_from_function:", as.character(e[[2]])))
      stmt_bad <- character(0); tgts <- character(0)
      .rfc_walk(e, function(n, f) {
        op <- .rfc_callee(n)
        if (op %in% c(gops, ":=") || op %in% sidefx) stmt_bad <<- c(stmt_bad, op)
        if (op %in% c("<-", "=") && length(n) == 3L) {
          has_f <- FALSE; .rfc_walk(n[[3]], function(m, g) if (identical(.rfc_callee(m), F)) has_f <<- TRUE)
          if (has_f) tgts <<- c(tgts, .rfc_lhs_base(n[[2]]))
        }
      })
      if (length(stmt_bad)) return(paste0("call_statement_side_effect:", paste(unique(stmt_bad), collapse = "+")))
      for (t in tgts) if (!nzchar(t) || refd(t)) return(paste0("value_flows_to:", t))
    }
    ""
  }
  for (L in unique(vapply(sites, function(s) s$loader, ""))) {
    ss <- Filter(function(s) identical(s$loader, L), sites)
    top <- Filter(function(s) is.na(s$encl) || !identical(s$how, "call"), ss)
    if (length(top)) {
      res$counted <- c(res$counted, L)
      res$detail[[L]] <- list(verdict = "source", why = if (any(!vapply(top, function(s) identical(s$how, "call"), logical(1)))) "string_reference" else "top_level_call",
                              lines = .rfc_I(vapply(top, function(s) as.character(line_of(s$i)), "")))
      next
    }
    Fs <- unique(vapply(ss, function(s) s$encl, ""))
    w <- vapply(Fs, why_not, "")
    if (any(nzchar(w))) {
      res$counted <- c(res$counted, L)
      res$detail[[L]] <- list(verdict = "source", why = paste(sprintf("%s:%s", Fs[nzchar(w)], w[nzchar(w)]), collapse = " | "),
                              functions = .rfc_I(Fs))
    } else {
      res$diagnostic <- c(res$diagnostic, sprintf("%s@%s(L%s)", L, Fs, vapply(Fs, function(F) as.character(line_of(fdefs[[F]][1])), "")))
      res$detail[[L]] <- list(verdict = "diagnostic_only", functions = .rfc_I(Fs))
    }
  }
  res
}

# ── 구조 술어(성과 무관) ────────────────────────────────────────────────────────────
.rfc_p <- function(ok, ...) list(ok = ok, ...)
.rfc_first_month_end <- function(d) { d <- as.Date(d); m1 <- as.Date(format(d, "%Y-%m-01")); seq(m1, by = "month", length.out = 2L)[2L] - 1L }

#' 엔진 1개의 구조 술어 — 각 술어 ok = TRUE/FALSE/NA(NA = 판독 불가 · 자격에서는 실패로 센다)
rfc_structural <- function(cand, root, cfg, en, grid) {
  P <- cfg$predicates; eng_abs <- .rfc_abs(cand$engine, root); wd <- dirname(eng_abs)
  out <- list()
  has_fid <- file.exists(file.path(wd, .rfc_chr1(P$lane$fidelity_file)))
  lane_ok <- grepl(.rfc_chr1(P$lane$engine_rel_regex), cand$engine, perl = TRUE) && !grepl(.rfc_chr1(P$lane$combo_dir_regex), cand$engine, fixed = TRUE) &&
    !isTRUE(cand$paper_key_combo) && has_fid && length(cand$root_entries) > 0L && file.exists(eng_abs)
  out$lane <- .rfc_p(lane_ok, engine_exists = file.exists(eng_abs), fidelity_file = has_fid, root_entries = length(cand$root_entries))
  fid <- .rfc_json(file.path(wd, .rfc_chr1(P$lane$fidelity_file)))
  lab <- .rfc_chr1(fid$fidelity)
  out$fidelity_self <- .rfc_p(if (is.null(fid)) NA else lab %in% unlist(P$fidelity$self_labels_ok), label = lab)
  ar <- en$.aud$rf_audit_read(file.path(wd, .rfc_chr1(P$fidelity$audit_file)))
  out$fidelity_audit <- .rfc_p(.rfc_chr1(ar$verdict) %in% unlist(P$fidelity$audit_verdicts_ok), verdict = .rfc_chr1(ar$verdict),
                               reason = .rfc_chr1(ar$reason), audit_md5 = .rfc_md5(file.path(wd, .rfc_chr1(P$fidelity$audit_file))))
  if (file.exists(eng_abs)) {
    rules <- file.path(root, .rfc_chr1(P$pit_static$c11_rules))
    op <- options(lookahead.c11_rules = if (file.exists(rules)) rules else getOption("lookahead.c11_rules")); on.exit(options(op), add = TRUE)
    la <- tryCatch(en$.la$detect_lookahead(eng_abs, verbose = FALSE), error = function(e) list(clean = NA, error = conditionMessage(e)))
    # 레인 검증기 ③ 구조 검사(설정 사본 · 동기화 가드 = 검사 S0) — 주석 제거 뒤 기본 정규식으로(정본과 같은 엔진)
    src_nc <- gsub(.rfc_chr1(P$pit_static$structural_comment_strip), "", paste(readLines(eng_abs, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
    sbad <- character(0)
    for (k in .rfc_or(P$pit_static$structural_checks, list())) {
      a1 <- all(vapply(as.character(unlist(k$all)), function(r) grepl(r, src_nc), logical(1)))
      n1 <- any(vapply(as.character(unlist(k$none)), function(r) grepl(r, src_nc), logical(1)))
      if (isTRUE(a1) && !isTRUE(n1)) sbad <- c(sbad, .rfc_chr1(k$label))
    }
    out$pit_static <- .rfc_p(if (is.na(.rfc_or(la$clean, NA))) NA else isTRUE(la$clean) && !length(sbad),
                             detector_clean = if (isTRUE(la$clean)) TRUE else if (isFALSE(la$clean)) FALSE else NA,
                             structural_hits = .rfc_I(sbad),
                             n_violations = as.integer(.rfc_or(la$n_violations, NA)),
                             checks = .rfc_I(unique(vapply(.rfc_or(la$violations, list()), function(v) .rfc_chr1(v$check), ""))),
                             error = .rfc_chr1(la$error))
    c11 <- tryCatch(en$rflf_c11_derive(entry = list(base_vintage_flags = lapply(cand$base_vintage_flags, function(f) list(flag = f))),
                                       attempt = list(), spec = list(base_signal = list(kind = "engine", path = eng_abs)),
                                       root = root, cache = NULL, engine_paths = eng_abs),
                    error = function(e) list(hit = NA, error = conditionMessage(e)))
    out$c11 <- .rfc_p(if (is.na(c11$hit)) NA else !isTRUE(c11$hit) && !length(c11$unreadable),
                      factors = .rfc_I(as.character(unlist(c11$factors))), sources = .rfc_I(as.character(names(.rfc_or(c11$sources, list())))),
                      base_flag = .rfc_I(as.character(unlist(c11$base_flag))), unreadable = .rfc_I(as.character(unlist(c11$unreadable))), error = .rfc_chr1(c11$error))
  } else {
    out$pit_static <- .rfc_p(NA, error = "engine_absent"); out$c11 <- .rfc_p(NA, error = "engine_absent")
  }
  frx <- unlist(P$flags$exclude_flag_regex)
  fh <- cand$base_vintage_flags[vapply(cand$base_vintage_flags, function(f) any(vapply(frx, function(r) grepl(r, f, perl = TRUE), logical(1))), logical(1))]
  out$flags <- .rfc_p(!length(fh), hit = .rfc_I(fh))
  # FACTORS 산출 · 후보 폭 · 커버리지 — 산출물 factors_panel.parquet 의 (Date,Ticker,Score) 개수·날짜만
  fp <- if (nzchar(cand$artifacts)) file.path(root, cand$artifacts, "factors_panel.parquet") else ""
  nmax <- as.integer(grid$fixed_axes$n_max); st <- as.Date(.rfc_chr1(grid$fixed_axes$start_date))
  if (nzchar(fp) && file.exists(fp)) {
    X <- tryCatch(as.data.table(arrow::read_parquet(fp, col_select = c("Date", "Ticker", "Score"))), error = function(e) NULL)
    if (is.null(X)) {
      out$output <- .rfc_p(NA, factors_panel = TRUE, error = "factors_panel 판독 불가"); out$coverage <- .rfc_p(NA, error = "factors_panel 판독 불가")
    } else {
      X <- X[is.finite(Score)]; X[, Date := as.Date(Date)]
      cnt <- X[, .(n = uniqueN(Ticker)), by = Date]
      med <- if (nrow(cnt)) stats::median(cnt$n) else NA_real_
      out$output <- .rfc_p(isTRUE(is.finite(med) && med > nmax), factors_panel = TRUE, median_names_per_date = med, n_max = nmax, n_dates = nrow(cnt))
      d0 <- if (nrow(cnt)) min(cnt$Date) else as.Date(NA); lim <- .rfc_first_month_end(st)
      out$coverage <- .rfc_p(isTRUE(!is.na(d0) && d0 <= lim), first_signal_date = format(d0), limit = format(lim), start_date = format(st))
    }
  } else {
    # 패널 부재 = 산출 형태 미관측(초기 러너는 패널을 저장하지 않았다) — 선언(construction)은 원천을 말하지 산출 축을 말하지 않는다 → NA(fail-closed)
    sp <- if (nzchar(cand$artifacts)) .rfc_allowed_json(file.path(root, cand$artifacts, "01_strategy_spec.json"), cfg$performance_blind$spec_fields_allowed) else NULL
    out$output <- .rfc_p(NA, factors_panel = FALSE, n_max = nmax, declared_construction = .rfc_chr1(sp$construction),
                         why = if (nzchar(cand$artifacts)) "factors_panel.parquet 부재 — 산출 형태 미관측(선언만으로 FACTORS 폭을 인정하지 않는다)" else "기저 산출물 없음")
    out$coverage <- .rfc_p(NA, why = "factors_panel 부재")
  }
  # 지문 밖 원천
  sc <- tryCatch({
    cons <- en$.pin$pin_fp_consumers(code_root = en$.code_root, engines = eng_abs, root = root)
    en$.pin$.pin_fp_sources(cons, file.path(root, ".cache"), c(en$.pin$.pin_fp_RAW_FILE, en$.pin$.pin_fp_BM_FILE, en$.pin$.pin_fp_FDB_DIR))
  }, error = function(e) list(status = "error", why = conditionMessage(e)))
  # 숨은 로더(설정 목록) — pin_fp 토큰 재도출은 함수 호출 기호를 세지 않아 로더 안의 경로를 못 본다(pin_cache.R 머리 주석의 사각)
  hl <- .rfc_or(P$source_scope$hidden_loader_sources, list())
  etxt <- if (file.exists(eng_abs)) paste(readLines(eng_abs, warn = FALSE, encoding = "UTF-8"), collapse = "\n") else ""
  # 구판 문형 판정(원문 텍스트 · 주석 포함) — 기록용 대조(흐름 판정과 갈리는 로더를 문서에 남긴다)
  hidden_text <- names(hl)[vapply(names(hl), function(fn) grepl(sprintf("(?<![A-Za-z0-9_.])%s\\s*\\(", fn), etxt, perl = TRUE), logical(1))]
  fcf <- P$source_scope$hidden_loader_flow
  fl <- if (is.null(fcf) || !nzchar(etxt)) list(status = if (is.null(fcf)) "legacy_text" else "no_engine", counted = hidden_text, diagnostic = character(0), detail = list())
        else .rfc_hidden_loader_flow(eng_abs, names(hl), fcf)
  hidden <- as.character(fl$counted)
  out$source_scope <- .rfc_p(if (identical(.rfc_chr1(sc$status), "ok") && nzchar(etxt) && fl$status %in% c("ok", "legacy_text")) !length(sc$uncovered) && !length(hidden) else NA,
                             status = .rfc_chr1(sc$status), consumed = .rfc_I(as.character(unlist(sc$consumed))), uncovered = .rfc_I(as.character(unlist(sc$uncovered))),
                             hidden_loaders = .rfc_I(hidden), hidden_sources = .rfc_I(vapply(hidden, function(h) .rfc_chr1(hl[[h]]), "", USE.NAMES = FALSE)),
                             hidden_flow = list(status = .rfc_chr1(fl$status), diagnostic_only = .rfc_I(fl$diagnostic),
                                                text_match_legacy = .rfc_I(hidden_text), detail = fl$detail),
                             why = .rfc_chr1(sc$why))
  ok <- all(vapply(out, function(z) isTRUE(z$ok), logical(1)))
  list(ok = ok, predicates = out, failed = .rfc_I(names(out)[!vapply(out, function(z) isTRUE(z$ok), logical(1))]))
}

# ── 노출 통로 ──────────────────────────────────────────────────────────────────────
#' 구현 전사 색인 — 첫 레코드 content 가 충실구현 프롬프트인 전사(파일 · timestamp · 엔진 참조 문자열). 디렉터리 부재 = 빈 색인(available FALSE)
rfc_transcript_index <- function(cfg) {
  T <- cfg$exposure$transcript
  d <- path.expand(.rfc_chr1(T$dir))
  if (!nzchar(d) || !dir.exists(d)) return(list(available = FALSE, dir = d, rows = list()))
  fs <- list.files(d, pattern = "\\.jsonl$", full.names = TRUE)
  rx <- .rfc_chr1(T$first_content_regex)
  rows <- list()
  for (f in fs) {
    l <- tryCatch(readLines(f, n = 1L, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
    if (!length(l) || !grepl(.rfc_chr1(T$first_line_prefilter), l, fixed = TRUE)) next
    j <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)
    ct <- .rfc_chr1(j$content)
    if (!nzchar(ct) || !grepl(rx, ct, perl = TRUE)) next
    # content_sha = 첫 레코드 content(= 레인이 stdin 으로 준 prompt.txt 바이트 그대로 · 09-26 실측 일치)의 sha256 — 청정 실행 전사를 이것으로 고른다
    rows[[length(rows) + 1L]] <- list(file = basename(f), path = f, ts = .rfc_chr1(j$timestamp), content = gsub("\\", "/", ct, fixed = TRUE),
                                      content_sha = digest::digest(enc2utf8(ct), algo = "sha256", serialize = FALSE))
  }
  list(available = TRUE, dir = d, rows = rows)
}
.rfc_ts <- function(s) as.numeric(as.POSIXct(sub("Z$", "", s), tz = "UTC", format = "%Y-%m-%dT%H:%M:%OS"))
.rfc_rx_count <- function(txt, rxs) sum(vapply(as.character(unlist(rxs)), function(r) {
  m <- gregexpr(r, txt, perl = TRUE)[[1]]; if (identical(as.integer(m[1]), -1L)) 0L else length(m) }, integer(1)))

#' 전사 1개 판독 — 자동 주입 기억·훅 주입 문맥의 성과 수치 수 · Read/Grep/Glob 성과 경로 열람(막힌 시도 제외) · 청정 가드 증명 · 금지 웹 대상
#'   (FA-CLEAN-BASE-PATH 2026-09-26) 구판은 tool_use 만 봐서 가드가 **막은** 시도도 열람으로 셌다 — 막힌 시도는 결과(tool_result is_error ·
#'   'PreToolUse:<도구> hook error: …ARM_GEN_READ_BLOCKED[')로 가른다(결과 없음·다른 오류 = 열람 · fail-closed). 규칙 파일(프로젝트 종류)은
#'   알려진 경계 — 경로·sha256·수치 개수만 기록한다. 훅 주입 문맥(hook_additional_context)의 수치는 자동 주입 노출로 센다.
#' (10-04 F_A v2 D2) 가드 증명 없는 실행의 Read/Grep/Glob 1건이 청정 허용 범위(가드 정책 clean_lane.read_allow ∪ 자기 작업 디렉터리) 안인가.
#'   저장소 루트 = 전사 cwd · 프롬프트가 지시한 엔진 경로의 접두 · 호출자 루트. 루트 밖·'..'·Grep 뿌리 없음(= 저장소 전체) = 밖.
#'   Glob 은 이름만 돌려준다 — 저장소 안이면 열림(가드 glob_names_in_repo 와 같은 규칙).
.rfc_np_l <- function(p) tolower(sub("/+$", "", gsub("\\", "/", .rfc_chr1(p), fixed = TRUE)))
.rfc_scope_in <- function(name, inp, roots, eng_dir, US) {
  abs_ <- function(p) grepl("^([a-z]:/|/)", p)
  rel_of <- function(p) { if (!abs_(p)) return(sub("^(\\./)+", "", p))
    for (r in roots) if (nzchar(r) && startsWith(paste0(p, "/"), paste0(r, "/"))) return(substring(p, nchar(r) + 2L)); NULL }
  if (identical(name, "Glob")) {
    p <- .rfc_np_l(inp$path); if (!nzchar(p)) { p <- .rfc_np_l(inp$pattern); if (!abs_(p)) p <- "" }
    if (!nzchar(p)) return(isTRUE(US$.glob_names_in_repo))
    return(isTRUE(US$.glob_names_in_repo) && !is.null(rel_of(p)))
  }
  p <- .rfc_np_l(if (identical(name, "Read")) inp$file_path else inp$path)
  if (!nzchar(p)) return(FALSE)
  rel <- rel_of(p)
  if (is.null(rel) || !nzchar(rel) || grepl("(^|/)\\.\\.(/|$)", rel)) return(FALSE)
  own <- paste0("04_research/strategies/", tolower(eng_dir))
  if (nzchar(eng_dir) && (rel == own || startsWith(rel, paste0(own, "/")))) return(TRUE)
  for (a in US$.allow) if (endsWith(a, "/")) { if (startsWith(paste0(rel, "/"), a)) return(TRUE) } else if (rel == a) return(TRUE)
  FALSE
}

.rfc_transcript_probe <- function(path, cfg, eng_dir = "", roots = character(0)) {
  T <- cfg$exposure$transcript
  GA <- T$guard_attestation; HC <- T$hook_context; IA <- T$instruction_attachments; WB <- T$web; US <- T$unattested_scope
  xtools <- as.character(unlist(US$exec_tool_names)); exec_hits <- character(0); cwds <- character(0); first_ct <- ""
  am_hits <- 0L; am_seen <- FALSE; hc_hits <- 0L; hc_n <- 0L; n_tool <- 0L
  prx <- .rfc_chr1(T$perf_path_regex); keys <- as.character(unlist(T$tool_target_keys)); tools_ <- as.character(unlist(T$tool_names))
  brx <- .rfc_chr1(T$blocked_result_regex); cbrx <- .rfc_chr1(GA$clean_block_regex); crx <- .rfc_chr1(GA$command_regex); pass_out <- .rfc_chr1(GA$pass_stdout)
  itypes <- as.character(unlist(IA$types)); btypes <- as.character(unlist(IA$boundary_file_types))
  wtools <- as.character(unlist(WB$tool_names)); wkeys <- as.character(unlist(WB$target_keys)); wrx <- .rfc_chr1(WB$forbidden_regex)
  tu <- list(); res <- list(); hs <- list(); instr <- list(); web_hits <- character(0)
  mk_instr <- function(pth, typ, content) {
    list(path = gsub("\\", "/", .rfc_chr1(pth), fixed = TRUE), type = typ, sha256 = digest::digest(enc2utf8(.rfc_chr1(content)), algo = "sha256", serialize = FALSE),
         metric_hits = .rfc_rx_count(.rfc_chr1(content), T$auto_memory$metric_regex))
  }
  fx <- c(.rfc_chr1(T$auto_memory$attachment_type), .rfc_chr1(T$auto_memory$user_text_marker), "\"tool_use\"", "\"tool_result\"",
          .rfc_chr1(GA$attachment_type), .rfc_chr1(HC$attachment_type), itypes)
  fx <- fx[nzchar(fx)]
  con <- file(path, open = "r", encoding = "UTF-8"); on.exit(close(con), add = TRUE)
  repeat {
    ls <- readLines(con, n = 200L, warn = FALSE); if (!length(ls)) break
    for (l in ls) {
      if (!any(vapply(fx, function(z) grepl(z, l, fixed = TRUE), logical(1)))) next
      j <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL); if (is.null(j)) next
      att <- j$attachment
      if (is.list(att)) {
        at <- .rfc_chr1(att$type)
        if (identical(at, "instructions") && at %in% itypes) {
          for (fl in .rfc_or(att$files, list())) {
            ft <- .rfc_chr1(fl$type)
            if (identical(ft, .rfc_chr1(T$auto_memory$attachment_type))) {
              am_seen <- TRUE; am_hits <- am_hits + .rfc_rx_count(.rfc_chr1(fl$content), T$auto_memory$metric_regex)
            } else {
              ii <- mk_instr(fl$path, ft, fl$content); instr[[length(instr) + 1L]] <- ii
              if (!(ft %in% btypes)) am_hits <- am_hits + ii$metric_hits      # 프로젝트 밖 종류(User·Local…) = 자동 주입 노출
            }
          }
        } else if (identical(at, "nested_memory") && at %in% itypes) {
          ct <- .rfc_chr1(att$content)
          mm <- regmatches(ct, regexec("'type': '([A-Za-z]+)'", ct))[[1]]   # 경로 주입 규칙 첨부 = 파이썬 dict 문자열(09-26 실측)
          ft <- if (length(mm) >= 2L) mm[2] else "unknown"
          ii <- mk_instr(att$path, ft, ct); instr[[length(instr) + 1L]] <- ii
          if (!(ft %in% btypes)) am_hits <- am_hits + ii$metric_hits
        } else if (nzchar(.rfc_chr1(HC$attachment_type)) && identical(at, .rfc_chr1(HC$attachment_type))) {
          hc_n <- hc_n + 1L
          hc_hits <- hc_hits + sum(vapply(as.character(unlist(.rfc_or(att$content, list()))), function(s) .rfc_rx_count(s, T$auto_memory$metric_regex), integer(1)))
        } else if (identical(at, .rfc_chr1(GA$attachment_type)) && nzchar(crx) && grepl(crx, .rfc_chr1(att$command), perl = TRUE)) {
          hs[[.rfc_chr1(att$toolUseID)]] <- trimws(.rfc_chr1(att$stdout))
        }
      }
      cw <- .rfc_np_l(j$cwd); if (nzchar(cw) && !(cw %in% cwds)) cwds <- c(cwds, cw)
      msg <- j$message; cont <- if (is.list(msg)) msg$content else NULL
      if (identical(.rfc_chr1(j$type), "user") && is.character(cont) && grepl(.rfc_chr1(T$auto_memory$user_text_marker), cont, fixed = TRUE)) {
        am_seen <- TRUE; am_hits <- am_hits + .rfc_rx_count(cont, T$auto_memory$metric_regex) }
      if (is.list(cont)) for (it in cont) if (is.list(it)) {
        ty <- .rfc_chr1(it$type)
        if (identical(ty, "tool_use")) {
          nm <- .rfc_chr1(it$name)
          tid <- .rfc_chr1(it$id); if (!nzchar(tid)) tid <- sprintf("__noid_%d", length(tu) + 1L)   # id 없는 호출 = 결과와 짝 불가 → 막힘 인정 없음(fail-closed)
          if (nm %in% tools_) tu[[tid]] <- list(name = nm, tg = paste(vapply(keys, function(k) .rfc_chr1(it$input[[k]]), ""), collapse = " "),
                                                inp = lapply(setNames(keys, keys), function(k) .rfc_chr1(it$input[[k]])))
          if (nm %in% xtools) exec_hits <- c(exec_hits, sprintf("%s %s", nm, substr(gsub("\\s+", " ", paste(unlist(it$input), collapse = " ")), 1L, 120L)))
          if (nm %in% wtools && nzchar(wrx)) {
            wt <- paste(vapply(wkeys, function(k) .rfc_chr1(it$input[[k]]), ""), collapse = " ")
            if (grepl(wrx, wt, perl = TRUE)) web_hits <- c(web_hits, sprintf("%s %s", nm, substr(wt, 1L, 160L)))
          }
        } else if (identical(ty, "tool_result")) {
          ctt <- it$content
          ctt <- if (is.character(ctt)) paste(ctt, collapse = "\n")
                 else paste(vapply(.rfc_or(ctt, list()), function(b) if (is.list(b)) .rfc_chr1(b$text) else .rfc_chr1(b), ""), collapse = "\n")
          res[[.rfc_chr1(it$tool_use_id)]] <- list(err = isTRUE(it$is_error), content = ctt)
        }
      }
    }
  }
  reads <- character(0); blocked <- character(0); unatt <- character(0); n_att_pass <- 0L; n_att_block <- 0L; scope_out <- character(0)
  rts <- unique(c(cwds, vapply(as.character(roots), .rfc_np_l, "")))
  for (id in names(tu)) {
    t <- tu[[id]]; r <- res[[id]]; n_tool <- n_tool + 1L
    is_blk <- !is.null(r) && isTRUE(r$err) && nzchar(brx) && grepl(brx, r$content, perl = TRUE)
    lab <- sprintf("%s %s", t$name, substr(gsub("\\", "/", trimws(t$tg), fixed = TRUE), 1L, 160L))
    if (grepl(prx, t$tg, perl = TRUE)) { if (is_blk) blocked <- c(blocked, lab) else reads <- c(reads, lab) }
    else if (!is_blk && !is.null(US) && !.rfc_scope_in(t$name, t$inp, rts, eng_dir, US)) scope_out <- c(scope_out, lab)
    if (identical(.rfc_or(hs[[id]], ""), pass_out) && nzchar(pass_out)) n_att_pass <- n_att_pass + 1L
    else if (is_blk && nzchar(cbrx) && grepl(cbrx, r$content, perl = TRUE)) n_att_block <- n_att_block + 1L
    else unatt <- c(unatt, lab)
  }
  list(auto_memory_seen = am_seen, auto_memory_metric_hits = am_hits, hook_context_n = hc_n, hook_context_metric_hits = hc_hits,
       n_tool_uses = n_tool, perf_path_reads = reads, perf_path_blocked = blocked,
       guard_attested_pass = n_att_pass, guard_attested_block = n_att_block, guard_unattested = unatt,
       web_forbidden = web_hits, instruction_files = instr, scope_out = scope_out, exec_tools = exec_hits)
}

.rfc_sha256 <- function(p) { p <- .rfc_chr1(p); if (nzchar(p) && file.exists(p) && !dir.exists(p)) digest::digest(p, algo = "sha256", file = TRUE) else NA_character_ }

#' 레인 출처 기록(작업 디렉터리 lane_provenance.json · FA-CLEAN-BASE-PATH) 판독 — **자기 신고**다. 판정은 rfc_exposure 가 전사·파일과 대조해서 낸다.
#'   claims_clean = TRUE(mode=clean) / FALSE(기록 없음·normal) / NA(기록은 있는데 판독 불가 — 청정 주장 여부를 모른다 = fail-closed)
rfc_lane_provenance <- function(cand, root, cfg) {
  XP <- cfg$exposure$lane_provenance
  if (is.null(XP)) return(list(present = FALSE, claims_clean = FALSE, why = "설정 exposure.lane_provenance 없음(구판 설정)"))
  wd <- dirname(.rfc_abs(cand$engine, root)); p <- file.path(wd, .rfc_chr1(XP$file))
  if (!file.exists(p)) return(list(present = FALSE, claims_clean = FALSE))
  P <- .rfc_json(p)
  if (!is.list(P)) return(list(present = TRUE, readable = FALSE, claims_clean = NA, file = .rfc_rel(p, root)))
  mode <- .rfc_chr1(P$mode)
  fb <- .rfc_or(P$pre$feedback, list())
  list(present = TRUE, readable = TRUE, file = .rfc_rel(p, root), sha256 = .rfc_sha256(p),
       schema_ok = identical(.rfc_chr1(P$schema), .rfc_chr1(XP$schema)), mode = mode, mode_source = .rfc_chr1(P$mode_source),
       claims_clean = identical(mode, .rfc_chr1(XP$clean_mode_value)), engine_rel = .rfc_np(P$engine_rel),
       prompt_sha = .rfc_chr1(P$pre$prompt$sha256), engine_sha_post = .rfc_chr1(P$post$engine_sha256),
       post_present = is.list(P$post), guard_applied = isTRUE(P$pre$guard$applied),
       guard_env = .rfc_or(P$pre$guard$env, list()), cli_disallowed = .rfc_chr1(P$pre$cli$disallowed_tools),
       audit_source_mode = .rfc_chr1(fb$audit_source_mode), audit_source_dir = .rfc_chr1(fb$audit_source_dir),
       feedback_stats = list(failure = fb$failure, audit = fb$audit),
       instruction_files_recorded = .rfc_or(P$pre$known_boundary$instruction_files, list()),
       n_audits = length(.rfc_or(P$audits, list())))
}

#' 청정 재구현 프롬프트의 감사 지적 출처 재도출 — 보존된 감사 프롬프트 사본(.clean_audit_src/r<n>)이 전부 '청정 모드 — 비공개' 줄을 갖고
#'   산출물 경로가 없어야 한다(감사 파일은 다음 감사가 덮으므로 사본이 유일한 증거다 · rf_clean_lane_lib.R rcl_archive_audit_src)
.rfc_audit_src_ok <- function(wd, rel, XP) {
  rel <- .rfc_chr1(rel)
  if (!nzchar(rel)) return(list(ok = FALSE, why = "감사 원천 사본 위치 없음(요청 audit_feedback_src)"))
  d <- file.path(wd, rel)
  fs <- list.files(d, pattern = "^(\\.audit_prompt_.*|fidelity_prompt)\\.txt$", all.files = TRUE, full.names = TRUE)
  if (!length(fs)) return(list(ok = FALSE, why = "감사 프롬프트 사본 0", dir = rel))
  bad <- character(0)
  for (f in fs) {
    tx <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (!grepl(.rfc_chr1(XP$audit_src_clean_regex), tx, perl = TRUE) || grepl(.rfc_chr1(XP$audit_src_art_regex), tx, perl = TRUE)) bad <- c(bad, basename(f))
  }
  list(ok = !length(bad), n_prompts = length(fs), bad = .rfc_I(bad), dir = rel)
}

#' 엔진 1개의 노출 통로 — 통로별 exposed = TRUE(노출 발견) / FALSE(확인 · 없음) / NA(판독 불가)
rfc_exposure <- function(cand, root, cfg, en, fcfg, tindex) {
  X <- cfg$exposure; eng_abs <- .rfc_abs(cand$engine, root); wd <- dirname(eng_abs)
  ch <- list()
  pf <- file.path(wd, .rfc_chr1(X$prompt$file))
  ch$prompt_missing <- list(exposed = !file.exists(pf), file = .rfc_rel(pf, root), md5 = .rfc_md5(pf))
  bx <- en$rfv_base_engine_exposure(root, list(path = eng_abs), fcfg$exclusion$base_engine_exposure, fcfg$exclusion$design_exposure)
  ch$prompt_combo <- list(exposed = if (isTRUE(bx$exposed)) TRUE else if (isFALSE(bx$exposed)) FALSE else NA,
                          section_found = isTRUE(bx$section_found), n_stat_lines = as.integer(.rfc_or(bx$n_stat_lines, NA)),
                          detector = "rf_floor_v2.R::rfv_base_engine_exposure")
  if (file.exists(pf)) {
    x <- readLines(pf, warn = FALSE, encoding = "UTF-8")
    h <- en$.rfv_section_hits(x, X$prompt$feedback_section_regex, .rfc_chr1(X$prompt$section_end_regex), character(0), X$prompt$measured_ref_regex)
    # 절 검출은 정규식마다 첫 등장만 본다(.rfv_section_hits) — 일반 머리 수 > 알려진 절 수면 모르는 재구현 절이 있다 = 판독 불가(fail-closed)
    n_gen <- sum(grepl(.rfc_chr1(X$prompt$feedback_header_generic_regex), x, perl = TRUE))
    n_known <- sum(vapply(as.character(unlist(X$prompt$feedback_section_regex)), function(r) any(grepl(r, x, perl = TRUE)), logical(1)))
    ch$prompt_feedback_measured <- list(exposed = if (n_gen > n_known) NA else isTRUE(h$exposed), section_found = isTRUE(h$section_found),
                                        n_feedback_headers = n_gen, n_known_sections = n_known,
                                        n_section_lines = h$n_section_lines, n_hit_lines = h$n_stat_lines)
  } else ch$prompt_feedback_measured <- list(exposed = NA, why = "prompt 부재")
  af <- file.path(wd, .rfc_chr1(cfg$predicates$fidelity$audit_file))
  mt <- c(prompt = if (file.exists(pf)) as.numeric(file.mtime(pf)) else NA_real_, engine = if (file.exists(eng_abs)) as.numeric(file.mtime(eng_abs)) else NA_real_,
          audit = if (file.exists(af)) as.numeric(file.mtime(af)) else NA_real_)
  ch$provenance_order <- list(exposed = if (anyNA(mt)) NA else !(mt[["prompt"]] <= mt[["engine"]] && mt[["engine"]] <= mt[["audit"]]),
                              mtime_utc = lapply(as.list(mt), function(v) if (is.na(v)) NA else format(as.POSIXct(v, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")))
  fs <- if (dir.exists(wd)) list.files(wd, all.files = TRUE, no.. = TRUE) else character(0)
  lane <- vapply(fs, function(f) any(vapply(unlist(X$wdir$lane_file_regex), function(r) grepl(r, f, perl = TRUE), logical(1))), logical(1))
  extra <- fs[!lane]
  emt <- if (length(extra)) as.numeric(file.mtime(file.path(wd, extra))) else numeric(0)
  before <- extra[is.finite(emt) & is.finite(mt[["engine"]]) & emt <= mt[["engine"]]]
  ch$wdir_extra_before_engine <- list(exposed = if (is.na(mt[["engine"]])) NA else length(before) > 0L, before = .rfc_I(before), after = .rfc_I(setdiff(extra, before)))
  # 전사 — 레인 출처 기록이 청정을 주장하면(FA-CLEAN-BASE-PATH) 기록을 믿지 않고 대조해서 고른다:
  #   프롬프트 sha256(기록) = 현재 prompt.txt = 전사 첫 레코드 content · 엔진 sha256(기록 · 실행 후) = 현재 engine.R · 시작 ∈ [prompt mtime − 허용 오차, engine mtime]
  #   → 해당 전사 **전부**(1차·폴백)를 판독하고, Read/Grep/Glob 전부에 청정 가드 증명을 요구한다. 어긋나면 판독 불가(NA · fail-closed).
  #   청정 주장이 없으면 구판 그대로(현행 엔진을 쓴 실행 = 첫 레코드 ts <= engine mtime 인 것 중 가장 늦은 것).
  key <- gsub("<engine_dir>", basename(wd), .rfc_chr1(X$transcript$engine_ref), fixed = TRUE)
  rows <- Filter(function(r) grepl(key, r$content, fixed = TRUE), .rfc_or(tindex$rows, list()))
  ts <- vapply(rows, function(r) .rfc_ts(r$ts), numeric(1))
  sel <- which(is.finite(ts) & is.finite(mt[["engine"]]) & ts <= mt[["engine"]])
  LP <- rfc_lane_provenance(cand, root, cfg)
  agg <- function(prs) list(am = sum(vapply(prs, function(p) as.integer(p$auto_memory_metric_hits), integer(1))),
                            am_seen = any(vapply(prs, function(p) isTRUE(p$auto_memory_seen), logical(1))),
                            hc = sum(vapply(prs, function(p) as.integer(p$hook_context_metric_hits), integer(1))),
                            hc_n = sum(vapply(prs, function(p) as.integer(p$hook_context_n), integer(1))),
                            n_tool = sum(vapply(prs, function(p) as.integer(p$n_tool_uses), integer(1))),
                            reads = unlist(lapply(prs, `[[`, "perf_path_reads")), blocked = unlist(lapply(prs, `[[`, "perf_path_blocked")),
                            unatt = unlist(lapply(prs, `[[`, "guard_unattested")), web = unlist(lapply(prs, `[[`, "web_forbidden")),
                            att_pass = sum(vapply(prs, function(p) as.integer(p$guard_attested_pass), integer(1))),
                            att_block = sum(vapply(prs, function(p) as.integer(p$guard_attested_block), integer(1))),
                            instr = unlist(lapply(prs, `[[`, "instruction_files"), recursive = FALSE),
                            scope_out = unlist(lapply(prs, `[[`, "scope_out")), exec = unlist(lapply(prs, `[[`, "exec_tools")))
  # (10-04 F_A v2 D2) 저장소 루트 후보 = 프롬프트가 지시한 엔진 경로의 접두(전사 첫 레코드) + 호출자 루트 + 코드 루트 — 전사 cwd 는 탐침이 더한다
  eng_dir <- basename(wd)
  roots_of <- function(r) {
    ct <- tolower(.rfc_chr1(r$content)); nd <- paste0("/04_research/strategies/", tolower(eng_dir), "/")
    pos <- gregexpr(nd, ct, fixed = TRUE)[[1]]
    pre <- if (identical(as.integer(pos[1]), -1L)) character(0) else vapply(as.integer(pos), function(p) sub("^.*[\\s`\"'(<\\[]", "", substr(ct, 1L, p - 1L), perl = TRUE), "")
    unique(c(pre[nzchar(pre)], .rfc_np_l(root), .rfc_np_l(.RFC_ROOT())))
  }
  probe_row <- function(r) .rfc_transcript_probe(r$path, cfg, eng_dir, roots_of(r))
  put_tr <- function(A, clean, trs) {
    ch$transcript_missing <<- c(list(exposed = FALSE), trs)
    ch$transcript_auto_memory <<- list(exposed = (A$am + A$hc) > 0L, auto_memory_seen = A$am_seen, metric_hits = A$am,
                                       hook_context_n = A$hc_n, hook_context_metric_hits = A$hc,
                                       known_boundary_instruction_files = lapply(Filter(function(z) z$type %in% as.character(unlist(X$transcript$instruction_attachments$boundary_file_types)),
                                                                                   .rfc_or(A$instr, list())), function(z) z[c("path", "sha256", "metric_hits")]))
    # 노출 확인(TRUE) = 성과 경로 열람 · 금지 웹 · (청정 주장) 가드 증명 없는 호출.
    # 판독 불가(NA · D2) = 실행 도구(셸 등 — 무엇을 읽었는지 전사가 말하지 않는다) · (가드 증명 없는 실행) 허용 범위 밖 열람(계획서·지식 색인·
    #   factor_evidence·다른 엔진 주석의 실측 수치 — 성과 경로 정규식만으로는 못 잡는다). 청정 주장 실행의 범위는 가드 증명이 맡는다(R6_scope).
    hard <- length(A$reads) > 0L || length(A$web) > 0L || (clean && length(A$unatt) > 0L)
    soft <- length(A$exec) > 0L || (!clean && length(A$scope_out) > 0L)
    ch$transcript_tool_reads <<- list(exposed = if (hard) TRUE else if (soft) NA else FALSE,
                                      why = if (!hard && soft) "가드 증명 없이 허용 범위 밖 열람 또는 실행 도구 사용 — 노출 여부 판독 불가(F_A v2 D2 · fail-closed)" else NULL,
                                      n_scope_out = length(A$scope_out), scope_out = .rfc_I(head(A$scope_out, 12L)), exec_tools = .rfc_I(head(A$exec, 6L)),
                                      n_tool_uses = A$n_tool, n_perf_path_reads = length(A$reads), perf_path_reads = .rfc_I(head(A$reads, 12L)),
                                      n_perf_path_blocked = length(A$blocked), perf_path_blocked = .rfc_I(head(A$blocked, 12L)),
                                      web_forbidden = .rfc_I(head(A$web, 6L)),
                                      guard_attestation = if (clean) list(required = TRUE, pass = A$att_pass, block = A$att_block,
                                                                         n_unattested = length(A$unatt), unattested = .rfc_I(head(A$unatt, 12L)))
                                                          else list(required = FALSE))
  }
  if (!isFALSE(LP$claims_clean)) {
    XP <- X$lane_provenance
    psha <- .rfc_sha256(pf); esha <- .rfc_sha256(eng_abs)
    chk <- list(provenance_readable = isTRUE(LP$readable), schema_ok = isTRUE(LP$schema_ok),
                prompt_sha_match = !is.na(psha) && identical(psha, LP$prompt_sha),
                engine_sha_match = !is.na(esha) && identical(esha, LP$engine_sha_post),
                guard_applied_recorded = isTRUE(LP$guard_applied),
                # (10-03) 새 엔진 경로 — 기록이 이 엔진을 가리키고(engine_rel = 후보 경로) 디렉터리가 청정 접두다. 옛 작업 디렉터리·다른 엔진의 기록 = 불인정
                engine_path_new = identical(tolower(.rfc_chr1(LP$engine_rel)), tolower(.rfc_np(cand$engine))) &&
                  grepl(.rfc_chr1(XP$engine_dir_regex), basename(wd), perl = TRUE))
    rows_c <- Filter(function(r) identical(.rfc_chr1(r$content_sha), psha), .rfc_or(tindex$rows, list()))
    ts_c <- vapply(rows_c, function(r) .rfc_ts(r$ts), numeric(1))
    tol <- suppressWarnings(as.numeric(.rfc_or(XP$start_tolerance_sec, NA)))
    selc <- which(is.finite(ts_c) & is.finite(mt[["prompt"]]) & is.finite(mt[["engine"]]) & is.finite(tol) &
                    ts_c >= mt[["prompt"]] - tol & ts_c <= mt[["engine"]])
    if (!all(vapply(chk, isTRUE, logical(1)))) {
      why <- paste0("레인 출처 기록 대조 실패(청정 주장 불인정): ", paste(names(chk)[!vapply(chk, isTRUE, logical(1))], collapse = ","))
      ch$transcript_missing <- list(exposed = NA, why = why, checks = chk)
      ch$transcript_auto_memory <- list(exposed = NA, why = why); ch$transcript_tool_reads <- list(exposed = NA, why = why)
    } else if (!isTRUE(tindex$available) || !length(selc)) {
      ch$transcript_missing <- list(exposed = TRUE, why = if (!isTRUE(tindex$available)) "전사 디렉터리 부재" else "청정 실행 전사 없음(첫 레코드 sha256 = prompt.txt · 시각 창 안 0건)",
                                    checks = chk, n_content_sha_match = length(rows_c))
      ch$transcript_auto_memory <- list(exposed = NA, why = "전사 없음"); ch$transcript_tool_reads <- list(exposed = NA, why = "전사 없음")
    } else {
      # (10-04 F_A v2 D1) 재구현은 같은 작업 디렉터리에서 앞 회차 engine.R 을 이어 쓰거나 engine.rejected*.R 을 읽는다 — 그리고 prov-pre 는
      #   회차마다 기록을 덮어쓴다. 그래서 이번 프롬프트 sha 의 전사만 보면 앞 회차 에이전트가 본 것이 엔진에 실려도 판정에 안 들어온다.
      #   이 엔진 디렉터리를 가리키는 구현 전사 중 엔진 mtime 이전 것 **전부**(앞 회차)를 같은 기준(가드 증명 요구 포함)으로 함께 판독한다.
      cur <- rows_c[selc]; cur_p <- vapply(cur, function(r) r$path, "")
      prior <- Filter(function(r) !(r$path %in% cur_p), rows[sel])
      prs <- lapply(c(cur, prior), probe_row)
      put_tr(agg(prs), TRUE, list(selection = "clean_provenance", transcripts = .rfc_I(vapply(cur, function(r) r$file, "")),
                                  started_utc = .rfc_I(vapply(cur, function(r) r$ts, "")), checks = chk,
                                  n_prior_runs = length(prior), prior_transcripts = .rfc_I(vapply(prior, function(r) r$file, "")),
                                  n_runs_referencing = length(rows), n_content_sha_match = length(rows_c)))
      # 앞 회차 프롬프트(전사 첫 레코드)의 재구현 절도 같은 검출식으로 — 측정 수치 = 노출 · 모르는 절 = 판독 불가
      if (length(prior)) {
        hp <- lapply(prior, function(r) {
          x <- strsplit(.rfc_chr1(r$content), "\n", fixed = TRUE)[[1]]
          h <- en$.rfv_section_hits(x, X$prompt$feedback_section_regex, .rfc_chr1(X$prompt$section_end_regex), character(0), X$prompt$measured_ref_regex)
          n_gen <- sum(grepl(.rfc_chr1(X$prompt$feedback_header_generic_regex), x, perl = TRUE))
          n_known <- sum(vapply(as.character(unlist(X$prompt$feedback_section_regex)), function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))
          aud_rx <- as.character(unlist(X$prompt$feedback_section_regex))[2]
          list(hit = isTRUE(h$exposed), unknown = n_gen > n_known, audit = !is.na(aud_rx) && any(grepl(aud_rx, x, perl = TRUE)))
        })
        pf_prior <- list(n_prior = length(prior), n_hit = sum(vapply(hp, `[[`, logical(1), "hit")), n_unknown = sum(vapply(hp, `[[`, logical(1), "unknown")))
        if (any(vapply(hp, `[[`, logical(1), "audit"))) {
          # 앞 회차의 감사 지적 출처 = 보존 사본 디렉터리 전부(.clean_audit_src/r*) — 하나라도 비청정·부재면 판독 불가
          sd <- list.dirs(file.path(wd, ".clean_audit_src"), recursive = FALSE, full.names = FALSE)
          aos <- lapply(sd, function(d) .rfc_audit_src_ok(wd, file.path(".clean_audit_src", d), XP))
          pf_prior$audit_sources <- lapply(aos, function(a) a[c("ok", "dir")])
          if (!length(aos) || !all(vapply(aos, function(a) isTRUE(a$ok), logical(1)))) pf_prior$unknown_audit <- TRUE
        }
        ch$prompt_feedback_measured$prior_prompts <- pf_prior
        if (pf_prior$n_hit > 0L) { ch$prompt_feedback_measured$exposed <- TRUE; ch$prompt_feedback_measured$why <- "앞 회차 프롬프트 재구현 절에 측정 수치(F_A v2 D1)" }
        else if ((pf_prior$n_unknown > 0L || isTRUE(pf_prior$unknown_audit)) && isFALSE(ch$prompt_feedback_measured$exposed)) {
          ch$prompt_feedback_measured$exposed <- NA; ch$prompt_feedback_measured$why <- "앞 회차 프롬프트의 모르는 재구현 절 또는 감사 지적 출처 미확인(F_A v2 D1)" }
      }
    }
    # 재구현 절(감사 지적)이 있으면 그 지적의 출처(보존된 감사 프롬프트 사본)가 청정 감사였는지 재도출 — 아니면 판독 불가
    if (file.exists(pf) && isFALSE(ch$prompt_feedback_measured$exposed)) {
      xx <- readLines(pf, warn = FALSE, encoding = "UTF-8")
      aud_rx <- as.character(unlist(X$prompt$feedback_section_regex))[2]
      if (!is.na(aud_rx) && any(grepl(aud_rx, xx, perl = TRUE))) {
        ao <- .rfc_audit_src_ok(wd, LP$audit_source_dir, XP)
        ch$prompt_feedback_measured$audit_source <- ao
        if (!isTRUE(ao$ok) || !identical(LP$audit_source_mode, "clean")) {
          ch$prompt_feedback_measured$exposed <- NA
          ch$prompt_feedback_measured$why <- "청정 재구현의 감사 지적 출처 미확인(비청정 감사 또는 원천 사본 불일치)"
        }
      }
    }
  } else if (!isTRUE(tindex$available) || !length(sel)) {
    ch$transcript_missing <- list(exposed = TRUE, why = if (!isTRUE(tindex$available)) "전사 디렉터리 부재" else "엔진 mtime 이전 구현 전사 없음",
                                  n_runs_referencing = length(rows))
    ch$transcript_auto_memory <- list(exposed = NA, why = "전사 없음"); ch$transcript_tool_reads <- list(exposed = NA, why = "전사 없음")
  } else {
    k <- sel[which.max(ts[sel])]; r <- rows[[k]]
    pr <- probe_row(r)
    put_tr(agg(list(pr)), FALSE, list(transcript = r$file, started_utc = r$ts, md5 = .rfc_md5(r$path), n_runs_referencing = length(rows),
                                     n_runs_before_engine = length(sel)))
  }
  ch
}
.rfc_scope_ok <- function(ch, chans) all(vapply(as.character(unlist(chans)), function(c) isFALSE(.rfc_or(ch[[c]], list())$exposed), logical(1)))

# ── 순서 ───────────────────────────────────────────────────────────────────────────
#' salt = 결정 레코드 필드(설정 순서) 연접 — 결정이 resolved 이고 문구가 요구 정규식에 맞아야 한다
rfc_salt <- function(root, cfg) {
  D <- cfg$decision
  R <- .rfc_json(file.path(root, .rfc_chr1(D$register)))
  if (is.null(R)) stop("[rf_clean_base] 결정 레지스터 판독 불가: ", .rfc_chr1(D$register))
  items <- .rfc_or(R$items, .rfc_or(R$decisions, R$entries))
  hit <- Filter(function(z) is.list(z) && identical(.rfc_chr1(z$id), .rfc_chr1(D$id)), .rfc_or(items, list()))
  if (!length(hit)) stop("[rf_clean_base] 결정 ", .rfc_chr1(D$id), " 이 레지스터에 없다 — 규칙의 존재 근거 부재")
  z <- hit[[length(hit)]]
  if (!identical(.rfc_chr1(z$status), .rfc_chr1(D$require_status))) stop("[rf_clean_base] 결정 ", .rfc_chr1(D$id), " status=", .rfc_chr1(z$status), " — ", .rfc_chr1(D$require_status), " 아님")
  if (!grepl(.rfc_chr1(D$require_decision_regex), .rfc_chr1(z$decision), perl = TRUE)) stop("[rf_clean_base] 결정 문구가 요구 정규식(", .rfc_chr1(D$require_decision_regex), ")에 맞지 않는다")
  f <- as.character(unlist(cfg$ordering$salt_from_decision_fields))
  v <- vapply(f, function(k) .rfc_chr1(z[[k]]), "")
  if (any(!nzchar(v))) stop("[rf_clean_base] salt 필드 부재: ", paste(f[!nzchar(v)], collapse = ", "))
  list(salt = paste(v, collapse = "|"), fields = f, decision = list(id = .rfc_chr1(z$id), status = .rfc_chr1(z$status), decided_at = .rfc_chr1(z$decided_at),
                                                                   decision_md5 = digest::digest(.rfc_chr1(z$decision), algo = "md5", serialize = FALSE)))
}
#' 순서 키 — sha256(salt|paper_key) 오름차순 · 동률 = 엔진 경로
rfc_order <- function(keys, engines, salt) {
  h <- vapply(keys, function(k) digest::digest(paste(salt, k, sep = "|"), algo = "sha256", serialize = FALSE), "", USE.NAMES = FALSE)
  list(hash = h, order = order(h, engines, method = "radix"))
}

#' 선택 — 범위별 자격(구조 ∧ 노출 0) · 청정실 대기열(구조만) · 상위 n
rfc_select <- function(rows, cfg, salt) {
  n <- as.integer(cfg$pick$n)
  eng <- vapply(rows, function(r) r$engine, "")
  key <- vapply(rows, function(r) if (nzchar(r$paper_key)) r$paper_key else r$engine, "")   # root entry 없는 엔진(결합·승격 전용) = 경로가 키
  O <- rfc_order(key, eng, salt); ord <- O$order
  struct_ok <- vapply(rows, function(r) isTRUE(r$structural$ok), logical(1))
  scopes <- lapply(names(cfg$exposure$scopes), function(s) {
    ok <- struct_ok & vapply(rows, function(r) .rfc_scope_ok(r$exposure, cfg$exposure$scopes[[s]]), logical(1))
    el <- ord[ok[ord]]
    list(scope = s, n_eligible = sum(ok), eligible_in_order = .rfc_I(eng[el]), picks = .rfc_I(head(eng[el], n)))
  }); names(scopes) <- names(cfg$exposure$scopes)
  cr <- ord[struct_ok[ord]]
  list(order_hash = setNames(as.list(O$hash), eng), order = .rfc_I(eng[ord]), structural_ok = .rfc_I(eng[struct_ok]), scopes = scopes,
       adopted_scope = .rfc_chr1(cfg$exposure$scope), picks = scopes[[.rfc_chr1(cfg$exposure$scope)]]$picks,
       clean_room_queue = .rfc_I(head(eng[cr], n)), clean_room_order = .rfc_I(eng[cr]))
}

# ── as-of 팩터 층 ───────────────────────────────────────────────────────────────────
.rfc_depth <- function(root, cfg, grid) {
  dr <- cfg$factor_layer$depth_rule; k <- .rfc_chr1(dr$kind)
  if (identical(k, "grid_b1_depths_max")) {
    b1 <- Filter(function(b) identical(.rfc_chr1(b$id), "B1"), .rfc_or(grid$blocks, list()))
    d <- if (length(b1)) suppressWarnings(max(as.integer(unlist(b1[[1]]$depths)))) else NA_integer_
    if (!is.finite(d) || d < 1L) stop("[rf_clean_base] 격자 blocks[B1].depths 부재 — 깊이를 정할 수 없다")
    return(list(depth = d, source = "reinforce_program.json blocks[B1].depths 최대"))
  }
  if (identical(k, "match_floor")) {
    F <- .rfc_json(file.path(root, .rfc_chr1(cfg$floor_v2$doc)))
    d <- suppressWarnings(as.integer(.rfc_or(F$floors[[.rfc_chr1(dr$floor_id)]]$selection_path$depth, NA)))
    if (!is.finite(d)) stop("[rf_clean_base] floor 문서에서 깊이를 읽지 못했다: ", .rfc_chr1(dr$floor_id))
    return(list(depth = d, source = sprintf("%s floors.%s.selection_path.depth", .rfc_chr1(cfg$floor_v2$doc), .rfc_chr1(dr$floor_id))))
  }
  d <- suppressWarnings(as.integer(dr$depth)); if (!is.finite(d) || d < 1L) stop("[rf_clean_base] literal depth 부재")
  list(depth = d, source = .rfc_chr1(.rfc_or(dr$source, "literal")))
}
#' as-of 팩터 층 드라이런(측정 0) — 정본 선정기 직접 호출. 기저 엔진과 무관(선정 = 팩터 IC as-of 통계)이라 후보 공통.
rfc_factor_layer <- function(root, cfg, en, grid) {
  D <- .rfc_depth(root, cfg, grid); off <- as.integer(cfg$factor_layer$seed_offset); asof <- cfg$factor_layer$asof
  X <- en$.fe$rf_pick_factor_sets(n = 1L, depths = D$depth, seed_offset = off, root = root, asof = asof)
  if (is.null(X) || !length(X$cells)) stop("[rf_clean_base] as-of 선정 실패 — rf_pick_factor_sets 가 칸을 내지 않았다")
  cell <- X$cells[[1]]; ids <- vapply(cell$factors, function(f) .rfc_chr1(f$id), "")
  if (length(ids) != D$depth) stop(sprintf("[rf_clean_base] as-of 사슬 깊이 %d < 요구 %d (계열 소진)", length(ids), D$depth))
  Xc <- en$.fe$rf_pick_factor_sets(n = D$depth, depths = seq_len(D$depth), seed_offset = off, root = root, asof = asof)
  F <- .rfc_json(file.path(root, .rfc_chr1(cfg$floor_v2$doc)))
  f1 <- as.character(unlist(.rfc_or(F$floors$F1$reselect$picked_ids, list())))
  list(depth = D$depth, depth_source = D$source, seed_offset = off, asof_config = if (is.null(asof)) "null(격자 fixed_axes.start_date)" else asof,
       cell = cell, picked_ids = .rfc_I(ids), seed_id = X$seed_id, max_rho = X$max_rho, prefix_chain = .rfc_I(as.character(Xc$picked_ids)),
       prefix_cells = lapply(Xc$cells, function(c1) list(label = c1$label, ids = .rfc_I(vapply(c1$factors, function(f) .rfc_chr1(f$id), "")))),
       vs_F1 = list(f1_ids = .rfc_I(f1), f1_subset_of_FA = length(f1) > 0L && all(f1 %in% ids), only_FA = .rfc_I(setdiff(ids, f1)),
                    note = "사슬은 접두 일관 — 같은 as-of·시드면 F1 집합 ⊆ F_A 집합(깊이만 다름). 레버 이식 비교성의 근거"),
       selection_basis = .rfc_chr1(cell$selection_basis), selection_asof = .rfc_chr1(cell$selection_asof))
}

#' F_A 스펙 — 격자 fixed_axes + as-of 셀 + 후보 엔진(없으면 청정실 자리표시) · 계보 스펙 승계 없음
rfc_fa_spec <- function(root, en, cfg, grid, layer, cand = NULL, floor_id, paper_url = "") {
  fa <- grid$fixed_axes
  if (is.null(fa) || is.null(fa$base_weight)) stop("[rf_clean_base] 격자 fixed_axes.base_weight 부재")
  ids <- layer$picked_ids
  bp <- if (nzchar(paper_url)) list(url = paper_url) else NULL
  rp <- en$.fe$rf_root_papers_for(ids, base_paper = bp, root = root)
  eng_abs <- if (is.null(cand)) "" else .rfc_abs(cand$engine, root)
  list(code = .rfc_chr1(layer$cell$code), floor_id = floor_id, label = layer$cell$label, block = "B1",
       fixed_axes = fa, base_weight = fa$base_weight,
       base_signal = if (is.null(cand)) list(kind = "engine", path = NULL, pending = "clean_room_engine", paper_url = paper_url)
                     else list(kind = "engine", path = .rfc_np(eng_abs)),
       base_signal_md5 = if (is.null(cand)) NA_character_ else .rfc_md5(eng_abs),
       factors = layer$cell$factors, weighting = cfg$spec$weighting, universe = cfg$spec$universe, rebalance = cfg$spec$rebalance,
       overlay = list(), overlay_cell = list(),
       root_paper = bp, root_papers = rp$papers, root_paper_families = rp$families, unmapped_families = rp$unmapped_families,
       selection_basis = layer$selection_basis, selection_asof = layer$selection_asof, basis = layer$cell$basis,
       idea = sprintf("[floor clean %s] %s — B1/multifactor(as-of 규칙 선정기) · weighting=%s · universe=%s · overlay=none · 기저 엔진 = 청정 규칙 선정(계보 승계 없음)",
                      floor_id, .rfc_chr1(layer$cell$label), .rfc_chr1(cfg$spec$weighting$kind), .rfc_chr1(cfg$spec$universe$kind)),
       gate_note = "P0-14 관문(rf_lineage_flags.R)이 이 칸의 팩터를 as-of 증명으로 보려면 원장 attempt 셀 코드 B1_ · 라벨 'N팩터 직교(' · spec$selection_basis == 'asof_ic' — 이 스펙 그대로")
}

#' 문서의 금지 키(성과) — 경로 목록(비었으면 없음)
rfc_forbidden_keys <- function(x, rx, path = "") {
  out <- character(0)
  if (is.list(x)) {
    nm <- names(x)
    for (i in seq_along(x)) {
      k <- if (!is.null(nm) && nzchar(nm[i])) nm[i] else sprintf("[%d]", i)
      if (!is.null(nm) && nzchar(nm[i]) && grepl(rx, nm[i], perl = TRUE)) out <- c(out, paste0(path, "/", k))
      out <- c(out, rfc_forbidden_keys(x[[i]], rx, paste0(path, "/", k)))
    }
  }
  out
}

#' 청정 기저 문서 생성(쓰기 없음 · 측정 0)
rfc_build <- function(root = .RFC_ROOT(), cfg_path = file.path(root, "06_Registry/prereg/clean_base_rule.config.json"), code_root = root, en = NULL, tindex = NULL) {
  cfg <- rfc_load_cfg(cfg_path)
  if (is.null(en)) en <- rfc_env(code_root)
  fcfg_p <- file.path(root, .rfc_chr1(cfg$floor_v2$config)); fcfg <- .rfc_json(fcfg_p)
  if (is.null(fcfg$exclusion$base_engine_exposure) || is.null(fcfg$exclusion$design_exposure)) stop("[rf_clean_base] floor v2 설정 판독 불가(결합 절 검출식): ", fcfg_p)
  gp <- file.path(root, "06_Registry/reinforce_program.json"); grid <- .rfc_json(gp)
  if (is.null(grid$fixed_axes)) stop("[rf_clean_base] 격자 부재: ", gp)
  S <- rfc_salt(root, cfg)
  V <- rfc_ledger_view(root, cfg)
  C <- rfc_candidates(V, root, cfg)
  if (is.null(tindex)) tindex <- rfc_transcript_index(cfg)
  rows <- lapply(C, function(cd) {
    st <- rfc_structural(cd, root, cfg, en, grid)
    ex <- rfc_exposure(cd, root, cfg, en, fcfg, tindex)
    lp <- rfc_lane_provenance(cd, root, cfg)
    sp <- .rfc_allowed_json(file.path(root, cd$artifacts, "01_strategy_spec.json"), cfg$performance_blind$spec_fields_allowed)
    wd <- dirname(.rfc_abs(cd$engine, root))
    c(cd, list(structural = st, exposure = ex, paper_url = .rfc_chr1(sp$source_paper_url),
               lane_provenance = list(present = isTRUE(lp$present), mode = .rfc_chr1(lp$mode), mode_source = .rfc_chr1(lp$mode_source),
                                      claims_clean = lp$claims_clean, file = .rfc_chr1(lp$file), sha256 = .rfc_chr1(lp$sha256), engine_rel = .rfc_chr1(lp$engine_rel),
                                      guard_applied = isTRUE(lp$guard_applied), n_audits = as.integer(.rfc_or(lp$n_audits, 0L)),
                                      note = "자기 신고 — 판정은 exposure 통로가 전사·파일과 대조한 결과다(FA-CLEAN-BASE-PATH)"),
               md5 = list(engine = .rfc_md5(.rfc_abs(cd$engine, root)), fidelity = .rfc_md5(file.path(wd, .rfc_chr1(cfg$predicates$lane$fidelity_file))),
                          audit = .rfc_md5(file.path(wd, .rfc_chr1(cfg$predicates$fidelity$audit_file))),
                          prompt = .rfc_md5(file.path(wd, .rfc_chr1(cfg$exposure$prompt$file))))))
  })
  names(rows) <- NULL
  SEL <- rfc_select(rows, cfg, S$salt)
  layer <- rfc_factor_layer(root, cfg, en, grid)
  byeng <- setNames(rows, vapply(rows, function(r) r$engine, ""))
  mk_floor <- function(eng, i, pending) {
    r <- byeng[[eng]]; fid <- sprintf("F_A%d", i)
    list(id = fid, rank = i, status = if (pending) "pending_clean_room_engine" else "defined_unmeasured",
         a_path = TRUE, mechanism_only = FALSE,
         determinism_ok = FALSE, selection_basis = "as_of", selection_basis_detail = layer$selection_basis,
         measurement_regime = list(exec_price = .rfc_chr1(fcfg$exclusion$exec_price_required), regime = NULL,
                                   note = "측정 0 — 사전등록 뒤 같은 regime 으로 2회(결정론) 측정"),
         vintage_flags = list(),
         paper_key = r$paper_key, paper_url = r$paper_url,
         source_engine = list(engine = r$engine, md5 = r$md5$engine, role = if (pending) "청정실 재구현의 논문 출처(엔진 재사용 아님 — 노출)" else "기저 엔진 그대로"),
         order_hash = SEL$order_hash[[eng]],
         spec = rfc_fa_spec(root, en, cfg, grid, layer, cand = if (pending) NULL else r, floor_id = fid, paper_url = r$paper_url))
  }
  adopted <- SEL$picks; pending <- !length(adopted)
  src <- if (pending) SEL$clean_room_queue else adopted
  floors <- lapply(seq_along(src), function(i) mk_floor(src[i], i, pending)); names(floors) <- vapply(floors, function(f) f$id, "")
  blockers <- c(if (pending) sprintf("FA:no_clean_candidate(scope=%s · 구조 통과 %d · 채택 범위 자격 0)", SEL$adopted_scope, length(SEL$structural_ok)),
                if (pending) "FA:clean_room_engine_absent(청정실 재구현 전 — 규칙 대기열 1순위부터)",
                "FA:unmeasured(결정론 2회 · 사전등록 뒤)",
                if (!identical(.rfc_chr1(cfg$factor_layer$depth_rule$kind), "match_floor")) character(0) else "FA:depth_from_lineage(도훈 결정 필요)")
  cand_tab <- lapply(rows, function(r) list(
    engine = r$engine, paper_key = r$paper_key, root_entries = .rfc_I(r$root_entries), artifacts = r$artifacts, base_vintage_flags = .rfc_I(r$base_vintage_flags),
    structural_ok = isTRUE(r$structural$ok), structural_failed = r$structural$failed, structural = r$structural$predicates,
    exposure = r$exposure, lane_provenance = r$lane_provenance,
    eligible = setNames(lapply(names(cfg$exposure$scopes), function(s) isTRUE(r$structural$ok) && .rfc_scope_ok(r$exposure, cfg$exposure$scopes[[s]])),
                        names(cfg$exposure$scopes)),
    order_hash = SEL$order_hash[[r$engine]], md5 = r$md5))
  pin <- function(rel, base = root) list(path = rel, md5 = .rfc_md5(file.path(base, rel)))
  doc <- list(
    schema = RFC_SCHEMA, version = 1L,
    status = if (pending) "blocked_no_clean_candidate" else "draft_pre_registration",
    status_note = if (pending) sprintf("채택 범위(%s)에서 청정 후보 0 — A 경로 기저는 청정실 재구현으로만 선다. floors = 규칙 순서의 재구현 대기열(측정 0).", SEL$adopted_scope)
                  else "초안 — F_A 는 스펙만(측정 0). 사전등록 뒤 측정.",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    generator = list(file = "02_Infrastructure/reinforcement/rf_clean_base.R", fn = "rfc_build", root = .rfc_np(root), code_root = .rfc_np(code_root),
                     config = .rfc_np(cfg_path), config_md5 = .rfc_md5(cfg_path),
                     path_note = "경로 비교는 생성 루트·정본 루트를 <ROOT> 로 정규화(rf_floor_v2.R .rfv_cmp_view)"),
    decision = S$decision, extends = list(doc = .rfc_chr1(cfg$floor_v2$doc), md5 = .rfc_md5(file.path(root, .rfc_chr1(cfg$floor_v2$doc))),
                                          relation = "F1(기전 반증 전용 · mechanism_only) 와 별도 가족 — 기전이 확인된 레버만 F_A 위 새 사전등록 가족으로 이식"),
    pins = list(ledger_l1 = list(path = V$path, md5 = V$md5), grid = pin("06_Registry/reinforce_program.json"),
                floor_v2_config = pin(.rfc_chr1(cfg$floor_v2$config)), pit_quarantine = pin("06_Registry/pit_quarantine.json"),
                fred_rules = pin(.rfc_chr1(cfg$predicates$pit_static$c11_rules)),
                factor_ic_monthly = pin(".cache/factor_db/factor_ic_monthly.parquet"), factor_registry = pin(".cache/factor_db/factor_registry.json"),
                factor_evidence = pin("06_Registry/factor_evidence.json"),
                rf_clean_base = pin("02_Infrastructure/reinforcement/rf_clean_base.R", code_root), rf_floor_v2 = pin("02_Infrastructure/reinforcement/rf_floor_v2.R", code_root),
                rf_factor_arms = pin("02_Infrastructure/ops/rf_factor_arms.R", code_root), rf_lineage_flags = pin("02_Infrastructure/reinforcement/rf_lineage_flags.R", code_root),
                lookahead_detector = pin("02_Infrastructure/validation/lookahead_detector.R", code_root), pin_cache = pin("02_Infrastructure/data/pin_cache.R", code_root),
                rf_fidelity_audit_lib = pin("02_Infrastructure/ops/rf_fidelity_audit_lib.R", code_root),
                transcript_dir = list(path = .rfc_np(tindex$dir), available = isTRUE(tindex$available))),
    rule = list(config = .rfc_np(cfg_path), config_md5 = .rfc_md5(cfg_path), ordering = cfg$ordering, salt_fields = S$fields,
                pick_n = as.integer(cfg$pick$n), adopted_scope = SEL$adopted_scope, scopes = cfg$exposure$scopes),
    performance_blind = list(ledger_fields_read = as.character(unlist(cfg$performance_blind$ledger_fields_allowed)),
                             artifact_files_read = as.character(unlist(cfg$performance_blind$artifact_files_allowed)),
                             note = "원장 성과 필드·성과 산출물 무판독(투영) · 문서 성과 키 0(rfc_forbidden_keys 자기 검사)"),
    candidates = cand_tab,
    selection = list(order = SEL$order, structural_ok = SEL$structural_ok, by_scope = SEL$scopes, adopted_scope = SEL$adopted_scope,
                     picks = SEL$picks, clean_room_queue = SEL$clean_room_queue, clean_room_order = SEL$clean_room_order),
    factor_layer = layer,
    floors = floors,
    clean_room = if (pending) cfg$clean_room else NULL,
    prereg_gate = list(ready = FALSE, blockers = blockers,
                       rule = "ready = 청정 후보(채택 범위) ≥ 1 ∧ F_A 결정론 2회 측정 ∧ 소비 계약 필드(status confirmed) — 초안은 항상 false"),
    measurement_policy = list(numbers = "성과 수치 0 — 인용도 하지 않는다(후보 간 사후 선택 방지)",
                              n_accounting = "F_A 가족 N 에 청정실 재구현 횟수·승계자 사용 횟수를 넣는다(Bailey & López de Prado 2014)"),
    evidence = cfg$evidence)
  fk <- rfc_forbidden_keys(doc, .rfc_chr1(cfg$performance_blind$doc_forbidden_key_regex))
  if (length(fk)) stop("[rf_clean_base] 문서에 성과 키가 있다(성과 비노출 위반): ", paste(head(fk, 5), collapse = ", "))
  doc
}

#' 쓰기 — rf_floor_v2.R::rfv_write 규약(원자적 · 기존과 내용이 다르면 거부 · 같으면 already)
rfc_write <- function(doc, out, en) en$rfv_write(doc, out)

#' 핀 대조 — 저장 문서와 재생성 문서의 차이(생성 시각 제외 · 루트 정규화)
rfc_verify <- function(path, root = .RFC_ROOT(), cfg_path = file.path(root, "06_Registry/prereg/clean_base_rule.config.json"), code_root = root, en = NULL, tindex = NULL) {
  if (is.null(en)) en <- rfc_env(code_root)
  old <- fromJSON(path, simplifyVector = FALSE)
  new <- rfc_build(root, cfg_path, code_root, en, tindex)
  d <- en$rfv_diff(en$.rfv_cmp_view(old), en$.rfv_cmp_view(en$.rfv_rt(new)))
  list(drift = d, n_drift = length(d), pins_drift = grep("^/pins", d, value = TRUE), selection_drift = grep("^/selection|^/floors", d, value = TRUE),
       status_now = new$status, picks_now = as.character(unlist(new$selection$picks)))
}

cat("[rf_clean_base.R] Loaded (FLOOR-BASE-ENGINE-Q4) — rfc_build / rfc_structural / rfc_exposure / rfc_select / rfc_factor_layer / rfc_write / rfc_verify\n")
