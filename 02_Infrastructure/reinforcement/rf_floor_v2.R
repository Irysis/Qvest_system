#==============================================================================
# rf_floor_v2.R — floor v2 정의 계약 (플랜 P2-03 · 2026-09-25)
#
# 무엇: 사전등록 레버 실험(P2: PR-L2 → PR-L1)의 바닥(floor) 후보를
#   ① 원장에서 **그대로 인용**하고(grade·essence·vintage_flags·adversary·measurement_regime — 손계산 0),
#   ② 최고 계보(22632)를 as-of 규칙(B08 rf_factor_arms.R::rf_pick_factor_sets · asof = 격자 fixed_axes.start_date)으로
#      팩터 재선정한 **새 칸 F1** 의 스펙을 정의한다(측정 0 — 측정은 사전등록 뒤 prereg 러너가 한다).
#
# 왜: current_axis=exec_v2_close_t1 원장의 최고 칸 22632 promo3 B1_3 에는 selection_basis_full_sample_ic_inherited(C1) 표식이
#   있다. 표식 정책 = '재측정 금지 — 규칙이 바뀌면 새 칸'(P0-08). 그래서 바닥은 옛 칸의 재측정이 아니라 새 칸이다.
#   ★as-of 재선정이 원 집합과 **같아도** 표식 해제 근거가 아니다(새 칸 측정이 필요) — 다르면 새 집합이다.
#
# 규칙(판단이 아니라 정의):
#   · 인용: 원장 attempt 필드를 그대로 싣는다. 같은 코드가 여러 번 측정됐으면 essence 가 전부 같을 때만 인용(다르면 stop).
#   · 적대검증 상태 = rf_runner_gates.R::rf_adversary_status (P0-11 소비자 술어 — 사본 금지 · 자격 술어는 소비자의 함수).
#   · 제외 = config.exclusion: PIT 표식(pit_flags) · exec_price ≠ 요구 · entry 축 ≠ 원장 current_axis · 적대검증 !ok · 미측정.
#     그 밖의 빈티지 표식 = caveat(제외 아님 — 레버 Δ 기준은 사전등록 뒤 같은 빈티지 재실행판).
#   · F1 = rf_pick_factor_sets(n = 1, depths = 계보 칸 DB 팩터 수, seed_offset = config, asof = config|격자) 셀 그대로 +
#     계보 칸 스펙의 기저 엔진·비중·유니버스 + 격자 fixed_axes. 원 집합 비교 = setequal. 진단: 접두 사슬 · 계보 팩터의 as-of 통계 ·
#     계보 계열 시드 대안(비채택). ★as-of 인자는 정본 상한 가드(R3)를 그대로 받는다 — 결정 시점 뒤·NA·미래 = stop(우회 금지).
#   · 계보 출처: 칸 팩터가 carry 사슬 어디서 처음 들어왔는가(규칙 선정기 라벨 / B1 설계 레인 / 그 밖) + 승계 표식 집합의 출처
#     칸이 계보 안인지(계보 carry) 밖인지(교차 entry 부분집합 일치) — 표식 해제 근거가 아니라 기록이다.
#   · 쓰기: 원자적 · 기존 파일과 내용(생성 시각 제외)이 다르면 거부(사전등록 불변성) · 같으면 already.
#   · ★적대검증 수리(2026-09-25 · FLOOR BLOCKING): ① 기저 엔진 설계 노출 — 칸 스펙 base_signal 엔진 디렉터리의 설계 프롬프트에
#     교차 entry 성과 수치가 있는지 재도출(rfv_base_engine_exposure · 칸 팩터 출처 판정과 같은 절 검출 함수). F1 은 기저 엔진을
#     승계하므로 여기서만 보인다(22632 결합 엔진 프롬프트 = 재료 6편의 '단독 다중검정 t' 교차 entry 수치). 인용 칸은 제외 사유로,
#     F1 은 prereg_blockers 로 싣는다. ② 사전등록 관문 prereg_gate — F1 기저 엔진 노출 없음 ∧ 설정 required_decisions 가
#     결정 레지스터에서 전부 resolved 일 때만 ready. 사전등록은 ready 가 아니면 착수하지 않는다(판정 = 도훈 결정 · 여기는 사실만).
#
# 요구: <code_root>/02_Infrastructure/ops/rf_factor_arms.R · reinforcement/rf_runner_gates.R(+ rf_spec_sig.R · rf_block_design.R —
#   rf_runner_gates.R 가 QM_ROOT 에서 적재) · 데이터 = <root>/06_Registry(원장·격자·factor_evidence·axis·pit_quarantine) ·
#   <root>/.cache/factor_db(factor_ic_monthly.parquet · factor_registry.json)
# 공개: rfv_load_cfg · rfv_env · rfv_ledger · rfv_cite · rfv_assess · rfv_lineage_provenance · rfv_asof_reselect ·
#       rfv_family_seed_offset · rfv_f1_spec · rfv_build · rfv_check_citations · rfv_write · rfv_verify · rfv_diff ·
#       rfv_design_exposure · rfv_base_engine_exposure · rfv_prereg_gate
# 검사: 08_Tests/reinforcement/test_rf_floor_v2.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
.rfv_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.rfv_chr1 <- function(x) { x <- as.character(unlist(.rfv_or(x, ""))); if (!length(x) || is.na(x[1])) "" else x[1] }
.RFV_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.rfv_md5 <- function(p) { p <- .rfv_chr1(p); if (nzchar(p) && file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_ }
.rfv_np <- function(p) gsub("\\", "/", .rfv_chr1(p), fixed = TRUE)
.rfv_json <- function(p) { p <- .rfv_chr1(p); if (nzchar(p) && file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
RFV_SCHEMA <- "reference_floors_v2"
RFV_RULE_LABEL_RE <- "[0-9]팩터 직교\\("          # rf_pick_factor_sets 셀 라벨 형식(규칙 선정기 칸 판별 — P0-08 derive 와 같은 정규식)

#' 설정 판독 — 필수 키 부재면 stop(수치·후보를 코드에 박지 않는다)
rfv_load_cfg <- function(path) {
  if (!file.exists(path)) stop("[rf_floor_v2] 설정 부재: ", path)
  cfg <- fromJSON(path, simplifyVector = FALSE)
  need <- c("schema", "floors", "exclusion", "evidence")
  miss <- setdiff(need, names(cfg)); if (length(miss)) stop("[rf_floor_v2] 설정 필수 키 부재: ", paste(miss, collapse = ", "))
  fl <- cfg$floors
  for (k in c("F1", "F1p", "F2", "F3_DNN")) if (is.null(fl[[k]])) stop("[rf_floor_v2] 설정 floors.", k, " 부재")
  if (is.null(fl$F1$lineage_cell$base_id) || is.null(fl$F1$lineage_cell$cell_code)) stop("[rf_floor_v2] F1.lineage_cell 부재")
  sr <- fl$F1$seed_rule
  if (!identical(.rfv_chr1(sr$kind), "offset") || !is.numeric(sr$seed_offset) || sr$seed_offset < 0)
    stop("[rf_floor_v2] F1.seed_rule 은 {kind: offset, seed_offset: >=0 정수} 여야 한다")
  if (!identical(.rfv_chr1(fl$F1$depth_rule), "lineage_db_factor_count")) stop("[rf_floor_v2] 알 수 없는 F1.depth_rule: ", .rfv_chr1(fl$F1$depth_rule))
  ex <- cfg$exclusion
  if (!length(ex$pit_flags) || !nzchar(.rfv_chr1(ex$exec_price_required))) stop("[rf_floor_v2] exclusion.pit_flags / exec_price_required 부재")
  dx <- ex$design_exposure
  if (!is.list(dx) || !length(dx$stat_regex) || !nzchar(.rfv_chr1(dx$section_start_regex)) || !nzchar(.rfv_chr1(dx$materials_dir)))
    stop("[rf_floor_v2] exclusion.design_exposure(materials_dir · section_start_regex · stat_regex) 부재 — Q④ 재도출을 건너뛰지 않는다")
  if (!is.numeric(fl$F1p$e3_tolerance)) stop("[rf_floor_v2] F1p.e3_tolerance 부재")
  # ★적대검증 수리(2026-09-25 · FLOOR BLOCKING) — 기저 엔진 설계 노출 · 사전등록 관문(결정 대기)을 건너뛰지 않는다
  bx <- ex$base_engine_exposure
  if (!is.list(bx) || !nzchar(.rfv_chr1(bx$materials_file)) || !length(bx$section_start_regex) || !nzchar(.rfv_chr1(bx$section_end_regex)))
    stop("[rf_floor_v2] exclusion.base_engine_exposure(materials_file · section_start_regex · section_end_regex) 부재 — 기저 엔진 Q④ 재도출을 건너뛰지 않는다")
  pg <- cfg$prereg_gate
  if (!is.list(pg) || is.null(pg$required_decisions) || !nzchar(.rfv_chr1(pg$register)))
    stop("[rf_floor_v2] prereg_gate(register · required_decisions) 부재 — 사전등록 관문을 건너뛰지 않는다")
  for (d in pg$required_decisions) if (!nzchar(.rfv_chr1(d$id))) stop("[rf_floor_v2] prereg_gate.required_decisions 항목에 id 가 없다")
  cid <- .rfv_chr1(.rfv_or(bx$clearing, list())$decision_id)
  if (nzchar(cid) && !(cid %in% vapply(pg$required_decisions, function(d) .rfv_chr1(d$id), "")))
    stop("[rf_floor_v2] base_engine_exposure.clearing.decision_id(", cid, ")가 prereg_gate.required_decisions 에 없다 — 해제 결정은 필수 결정이어야 한다")
  cfg
}

#' 정본 계약 적재(격리 환경) — rf_factor_arms.R(B08 as-of 선정) + rf_runner_gates.R(P0-11 적대검증 술어)
rfv_env <- function(code_root = .RFV_ROOT()) {
  en <- new.env(parent = globalenv())
  for (rel in c("02_Infrastructure/ops/rf_factor_arms.R", "02_Infrastructure/reinforcement/rf_runner_gates.R")) {
    p <- file.path(code_root, rel)
    if (!file.exists(p)) stop("[rf_floor_v2] 정본 계약 부재: ", p)
    invisible(capture.output(suppressMessages(sys.source(p, envir = en, keep.source = FALSE))))
  }
  for (fn in c("rf_pick_factor_sets", "rf_factor_pool", "rf_ic_cormat", "rf_root_papers_for", "rf_adversary_status"))
    if (!exists(fn, envir = en, mode = "function", inherits = FALSE)) stop("[rf_floor_v2] 정본 함수 부재: ", fn)
  en$.code_root <- code_root
  en
}

rfv_ledger <- function(root, layer = 1L) {
  p <- file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", as.integer(layer)))
  if (!file.exists(p)) stop("[rf_floor_v2] 원장 부재: ", p)
  L <- fromJSON(p, simplifyVector = FALSE); L$.path <- p; L$.md5 <- .rfv_md5(p); L
}

# 칸 스펙의 DB 팩터 id(스펙 순서 보존) — factors + factor2/3(kind != none) 중 kind == db(부재 = db)
.rfv_fids <- function(s, sorted = FALSE) {
  if (is.null(s)) return(character(0))
  fs <- c(.rfv_or(s$factors, list()),
          if (!is.null(s$factor2) && !identical(.rfv_chr1(s$factor2$kind), "none")) list(s$factor2),
          if (!is.null(s$factor3) && !identical(.rfv_chr1(s$factor3$kind), "none")) list(s$factor3))
  v <- unique(vapply(Filter(function(f) is.list(f) && identical(.rfv_chr1(.rfv_or(f$kind, "db")), "db"), fs), function(f) .rfv_chr1(f$id), ""))
  if (sorted) sort(v) else v
}
.rfv_code <- function(a) { c1 <- .rfv_chr1(a$cell_code); if (nzchar(c1)) c1 else .rfv_chr1(.rfv_or(a[["essence"]], list())$cell_code) }

#' entry + attempt 찾기 (cell_code NULL/"" = entry 만)
.rfv_find <- function(L, base_id, cell_code = NULL) {
  E <- Filter(function(e) identical(.rfv_chr1(e$base_id), base_id), .rfv_or(L$entries, list()))
  if (length(E) != 1L) stop(sprintf("[rf_floor_v2] 원장에 entry %s 가 %d건", base_id, length(E)))
  E <- E[[1]]
  if (is.null(cell_code) || !nzchar(cell_code)) return(list(entry = E, attempt = NULL, n_dups = 0L))
  A <- Filter(function(a) identical(.rfv_code(a), cell_code) && !is.null(a[["essence"]]), .rfv_or(E$attempts, list()))
  if (!length(A)) stop(sprintf("[rf_floor_v2] %s 에 측정 칸 %s 없음", base_id, cell_code))
  if (length(A) > 1L) {
    e1 <- A[[1]][["essence"]]
    if (!all(vapply(A, function(a) identical(a[["essence"]], e1), logical(1))))
      stop(sprintf("[rf_floor_v2] %s %s 가 %d회 측정됐고 essence 가 서로 다르다 — 어느 칸인지 정할 수 없다", base_id, cell_code, length(A)))
  }
  list(entry = E, attempt = A[[length(A)]], n_dups = length(A))
}

#' 후보 칸 인용 — 원장 필드 그대로(손계산 0). 적대검증 상태는 정본 술어(rf_adversary_status).
rfv_cite <- function(L, base_id, cell_code, en) {
  f <- .rfv_find(L, base_id, cell_code); E <- f$entry; a <- f$attempt
  sp_path <- .rfv_chr1(a[["essence"]]$spec); spec <- .rfv_json(sp_path)
  adv <- en$rf_adversary_status(a, carry_overlay = .rfv_or(E$carry, list())$overlay, spec = spec)
  vf <- lapply(.rfv_or(a$vintage_flags, list()), function(z)
    list(flag = z$flag, verdict = z$verdict, source = z$source, policy = z$policy, marked_at = z$marked_at))
  list(base_id = base_id, n = a$n, cell_code = cell_code, n_measurements_same_code = f$n_dups,
       grade = a$grade, essence = a[["essence"]], measurement_regime = a$measurement_regime,
       vintage_flags = vf,
       adversary = list(status = adv$status, ok = isTRUE(adv$ok), detail = adv$detail,
                        ledger_verdict = .rfv_or(a$adversary, list())$verdict, ledger_at = .rfv_or(a$adversary, list())$at,
                        predicate = "rf_runner_gates.R::rf_adversary_status (P0-11)"),
       artifacts = a$artifacts, spec_path = sp_path, spec_md5 = .rfv_md5(sp_path),
       label = if (is.null(spec)) NULL else spec$label, factors = .rfv_fids(spec),
       overlay = if (is.null(spec)) NULL else spec$overlay,
       weighting = if (is.null(spec)) NULL else spec$weighting,
       entry = list(measurement_axis = E$measurement_axis, status = E$status, parent = E$parent,
                    carry_source_cell = .rfv_or(E$carry, list())$source_cell,
                    base_remeasure = E$base_remeasure),
       ledger_current_axis = L$current_axis)
}

#' 설계 레인 교차 entry 노출(ORGANIC-DE Q④) — entry 1개의 B1 설계 재료 파일에서 재도출(읽기만 · 표식 writer 아님)
#'   exposed = '앞선 논문' 절(식별자 보호 뒤)에 통계 식이 하나라도 있다 · 파일 부재 = NA(호출자가 fail-closed)
#' 절 노출 판정(공용 · 순수) — 시작 정규식마다 그 절(다음 section_end 전까지)을 모아 식별자 보호 뒤 통계 식을 찾는다.
#'   칸 팩터 출처(rfv_design_exposure)와 기저 엔진(rfv_base_engine_exposure)이 **같은 함수**를 쓴다(사본 금지).
.rfv_section_hits <- function(x, start_rx, end_rx, protect_rx, stat_rx) {
  sec <- character(0); found <- FALSE
  for (srx in as.character(unlist(start_rx))) {
    st <- grep(srx, x, perl = TRUE)
    if (!length(st)) next
    found <- TRUE
    rest <- if (st[1] < length(x)) x[(st[1] + 1L):length(x)] else character(0)
    en_ <- grep(end_rx, rest, perl = TRUE)
    sec <- c(sec, if (length(en_)) rest[seq_len(en_[1] - 1L)] else rest)
  }
  y <- sec
  for (rx in as.character(unlist(protect_rx))) y <- gsub(rx, " ", y, perl = TRUE)
  hit <- if (length(y)) Reduce(`|`, lapply(as.character(unlist(stat_rx)), function(rx) grepl(rx, y, perl = TRUE))) else logical(0)
  list(section_found = found, n_section_lines = length(sec), n_stat_lines = sum(hit), exposed = any(hit))
}

rfv_design_exposure <- function(root, base_id, dx) {
  p <- file.path(root, .rfv_chr1(dx$materials_dir), paste0(base_id, .rfv_chr1(dx$materials_suffix)))
  dj <- file.path(root, .rfv_chr1(dx$materials_dir), paste0(base_id, ".json"))
  rel <- file.path(.rfv_chr1(dx$materials_dir), paste0(base_id, .rfv_chr1(dx$materials_suffix)))
  if (!file.exists(p)) return(list(base_id = base_id, file = rel, exists = FALSE, exposed = NA, n_stat_lines = NA_integer_))
  x <- readLines(p, warn = FALSE, encoding = "UTF-8")
  h <- .rfv_section_hits(x, .rfv_chr1(dx$section_start_regex), .rfv_chr1(dx$section_end_regex), dx$protect_regex, dx$stat_regex)
  # ★시각(mtime)은 싣지 않는다 — 사본·미러마다 달라 핀 대조가 상시 드리프트를 낸다(내용 = md5 로만 고정)
  c(list(base_id = base_id, file = rel, exists = TRUE, md5 = .rfv_md5(p), design_json_md5 = .rfv_md5(dj)), h)
}

# 경로 해석 — 정본 루트 접두 경로는 데이터 루트 아래 같은 상대 경로를 먼저 본다(사본·미러) · 없으면 원 경로 · 둘 다 없으면 NA
.rfv_relroot <- function(p) {
  p <- .rfv_np(p); cr <- .RFV_CANON_ROOT
  if (startsWith(tolower(p), tolower(paste0(cr, "/")))) substring(p, nchar(cr) + 2L) else p
}
.rfv_resolve <- function(p, root) {
  p <- .rfv_np(p); if (!nzchar(p)) return(NA_character_)
  rel <- .rfv_relroot(p)
  if (!identical(rel, p)) { q <- file.path(root, rel); if (file.exists(q)) return(q) }
  if (file.exists(p)) p else NA_character_
}

#' 기저 엔진 설계 노출(★적대검증 수리 2026-09-25) — 칸 스펙 base_signal 엔진 디렉터리의 설계 프롬프트(결합 설계 레인)에
#'   교차 entry 성과 수치가 있는가. 칸 팩터 출처 노출(rfv_design_exposure)과 **다른 통로**다 — F1 은 팩터 층만 as-of 로 바꾸고
#'   기저 엔진을 승계하므로 팩터 출처 판정으로는 안 보인다. 사실 도출만(읽기) · 판독 불가 = NA(호출자 fail-closed).
#'   결합 설계 레인이 ORGANIC-DE Q④(열거 = B1·B2·B3·B5 설계 레인) 대상인지는 도훈 결정 — verdict 는 설정값(pending_decision).
rfv_base_engine_exposure <- function(root, base_signal, bx, dx) {
  ep <- .rfv_np(.rfv_or(base_signal, list())$path)
  if (!nzchar(ep)) return(list(kind = "base_engine", engine = "", file = "", exists = FALSE, exposed = NA, n_stat_lines = NA_integer_,
                               why = "base_signal.path 없음"))
  pf <- paste0(dirname(ep), "/", .rfv_chr1(bx$materials_file))
  rel <- .rfv_relroot(pf); rp <- .rfv_resolve(pf, root)
  base <- list(kind = "base_engine", engine = .rfv_relroot(ep), engine_id = basename(dirname(ep)), file = rel)
  if (is.na(rp)) return(c(base, list(exists = FALSE, exposed = NA, n_stat_lines = NA_integer_)))
  x <- readLines(rp, warn = FALSE, encoding = "UTF-8")
  h <- .rfv_section_hits(x, bx$section_start_regex, .rfv_chr1(bx$section_end_regex),
                         .rfv_or(bx$protect_regex, dx$protect_regex), .rfv_or(bx$stat_regex, dx$stat_regex))
  c(base, list(exists = TRUE, md5 = .rfv_md5(rp)), h)
}

#' 사전등록 관문(★적대검증 수리) — F1 기저 엔진 노출 + 결정 레지스터의 필수 결정(resolved 아니면 막는다). 순수 판독 · 쓰기 없음.
#'   레지스터 판독 불가 = 전 결정 blocker(fail-closed). ready = blocker 0.
#'   F1 기저 엔진 노출 blocker 는 bx$clearing 결정(id)이 resolved 이고 그 decision 문자열이 clears_if_decision_matches 중 하나에
#'   맞을 때만 풀린다(예: 'Q①' = 다중검정 + 서류 감사로 분류) — 노출 사실은 그대로 싣고 해제 근거(결정 id·문구)를 기록한다.
rfv_prereg_gate <- function(root, pg, f1_bx, bx_verdict, bx = NULL) {
  bl <- character(0)
  rp <- file.path(root, .rfv_chr1(pg$register))
  R <- tryCatch(fromJSON(rp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.list(R) && !is.null(names(R))) R <- .rfv_or(R$decisions, .rfv_or(R$entries, R$items))
  look <- function(id) {
    hit <- if (is.list(R)) Filter(function(z) is.list(z) && identical(.rfv_chr1(z$id), id), R) else list()
    s <- if (!is.list(R)) "register_unreadable" else if (!length(hit)) "absent" else .rfv_chr1(hit[[length(hit)]]$status)
    list(status = s, decision = if (length(hit) && identical(s, "resolved")) .rfv_chr1(hit[[length(hit)]]$decision) else "")
  }
  cl <- .rfv_or(.rfv_or(bx, list())$clearing, list())
  cleared_by <- NULL
  if (isTRUE(f1_bx$exposed)) {
    cid <- .rfv_chr1(cl$decision_id); lk <- if (nzchar(cid)) look(cid) else list(status = "no_clearing_decision", decision = "")
    ok <- identical(lk$status, "resolved") &&
      any(vapply(as.character(unlist(cl$clears_if_decision_matches)), function(rx) grepl(rx, lk$decision, perl = TRUE), logical(1)))
    if (ok) cleared_by <- list(decision_id = cid, decision = lk$decision)
    else bl <- c(bl, sprintf("F1:q4_base_engine_exposure(%s · %s)", bx_verdict, .rfv_chr1(f1_bx$file)))
  } else if (!isFALSE(f1_bx$exposed)) bl <- c(bl, sprintf("F1:q4_base_engine_unknown(%s)", .rfv_chr1(f1_bx$file)))
  st <- lapply(.rfv_or(pg$required_decisions, list()), function(d) {
    id <- .rfv_chr1(d$id); lk <- look(id)
    list(id = id, what = d$what, register_status = lk$status, decision = if (nzchar(lk$decision)) lk$decision else NULL)
  })
  for (z in st) if (!identical(z$register_status, "resolved")) bl <- c(bl, sprintf("decision_pending:%s(%s)", z$id, z$register_status))
  list(ready = !length(bl), blockers = bl, required_decisions = st, register = .rfv_chr1(pg$register),
       f1_base_engine_cleared_by = cleared_by,
       rule = paste0("ready = F1 기저 엔진 노출 없음(또는 해제 결정 resolved ∧ 해제 문구 일치) ∧ 필수 결정 전부 resolved — ",
                     "사전등록(rf_prereg)은 ready 가 아니면 착수하지 않는다. 결정이 바뀌면 문서 내용이 바뀌므로 새 판(rfv_write 불변성)"))
}

#' 칸 출처 중 설계 레인 origin entry 들의 노출 판정 모음
rfv_provenance_exposure <- function(root, prov, dx) {
  org <- .rfv_or(prov$factor_origin, list())
  ids <- unique(vapply(Filter(function(o) identical(.rfv_chr1(o$origin_kind), "b1_design_lane"), org), function(o) .rfv_chr1(o$base_id), ""))
  lapply(ids, function(b) rfv_design_exposure(root, b, dx))
}

#' 바닥 자격 판정(순수) — reasons 가 있으면 제외. caveats 는 제외가 아니다.
#'   exposure = rfv_provenance_exposure 결과(선택) — 노출 TRUE 또는 판독 불가(NA) = 'derived:q4_crossentry_exposure' 제외(fail-closed)
rfv_assess <- function(cite, ex, exposure = NULL) {
  reasons <- character(0); caveats <- character(0)
  for (z in .rfv_or(exposure, list())) {
    if (identical(.rfv_chr1(z$kind), "base_engine")) {        # ★적대검증 수리 — 기저 엔진 설계 노출(결합 설계 레인)
      if (isTRUE(z$exposed)) reasons <- c(reasons, sprintf("derived:q4_base_engine_exposure(%s · %s)", .rfv_chr1(.rfv_or(ex$base_engine_exposure, list())$verdict), .rfv_chr1(z$file)))
      else if (!isFALSE(z$exposed)) reasons <- c(reasons, sprintf("derived:q4_base_engine_unknown(materials_missing · %s)", .rfv_chr1(z$file)))
      next
    }
    if (isTRUE(z$exposed)) reasons <- c(reasons, sprintf("derived:q4_crossentry_exposure(%s · %s)", .rfv_chr1(.rfv_or(ex$design_exposure, list())$verdict), .rfv_chr1(z$base_id)))
    else if (is.na(z$exposed)) reasons <- c(reasons, sprintf("derived:q4_unknown(materials_missing · %s)", .rfv_chr1(z$base_id)))
  }
  flags <- vapply(.rfv_or(cite$vintage_flags, list()), function(z) .rfv_chr1(z$flag), "")
  pf <- as.character(unlist(ex$pit_flags))
  hit <- intersect(flags, pf); if (length(hit)) reasons <- c(reasons, paste0("pit_flag:", hit))
  oth <- setdiff(flags[nzchar(flags)], pf); if (length(oth)) caveats <- c(caveats, paste0("vintage_flag:", oth))
  ep <- .rfv_chr1(.rfv_or(cite$measurement_regime, list())$exec_price)
  if (!identical(ep, .rfv_chr1(ex$exec_price_required))) reasons <- c(reasons, sprintf("regime:exec_price=%s(요구 %s)", if (nzchar(ep)) ep else "없음", .rfv_chr1(ex$exec_price_required)))
  ax <- .rfv_chr1(.rfv_or(cite$entry, list())$measurement_axis); cur <- .rfv_chr1(cite$ledger_current_axis)
  if (!identical(ax, cur)) reasons <- c(reasons, sprintf("axis:entry=%s(원장 current_axis %s)", if (nzchar(ax)) ax else "없음", cur))
  if (!isTRUE(.rfv_or(cite$adversary, list())$ok)) reasons <- c(reasons, paste0("adversary:", .rfv_chr1(.rfv_or(cite$adversary, list())$status)))
  pt <- suppressWarnings(as.numeric(.rfv_or(.rfv_or(cite$essence, list())$port_t, NA)))
  if (!(length(pt) == 1L && is.finite(pt))) reasons <- c(reasons, "unmeasured")
  list(eligible = !length(reasons), reasons = reasons, caveats = caveats)
}

#' 계보 출처 — 칸 팩터가 carry 사슬(entry$parent · carry$source_cell) 어디서 처음 들어왔는가 + 승계 표식 집합의 출처 칸
#'   origin_kind: rule_selector(<selection_basis|구판 전표본>) · b1_design_lane(설계 산출물 라벨 일치) · other
rfv_lineage_provenance <- function(L, base_id, cell_code, root) {
  f <- .rfv_find(L, base_id, cell_code)
  steps <- list(); E <- f$entry; a <- f$attempt; code <- cell_code; seen <- character(0)
  repeat {
    s <- .rfv_json(.rfv_or(a[["essence"]], list())$spec)
    carryF <- .rfv_fids(E$carry); ids <- .rfv_fids(s)
    via <- ""
    # B1 밖 칸(B2~B7)이 carry 밖 팩터를 가지면 그 집합은 같은 entry 의 B1 칸(블록 바닥)에서 왔다 — 팩터 집합이 같은 B1 칸으로 귀속
    if (!startsWith(code, "B1_") && length(setdiff(ids, carryF))) {
      tgt <- sort(ids)
      B <- Filter(function(x) startsWith(.rfv_code(x), "B1_") &&
                    identical(.rfv_fids(.rfv_json(.rfv_or(x[["essence"]], list())$spec), sorted = TRUE), tgt), .rfv_or(E$attempts, list()))
      if (length(B)) { via <- code; code <- .rfv_code(B[[1]]); s <- .rfv_json(.rfv_or(B[[1]][["essence"]], list())$spec) }
    }
    lab <- .rfv_chr1(if (is.null(s)) "" else s$label)
    dz <- .rfv_json(file.path(root, ".cache/rf_b1_design", paste0(.rfv_chr1(E$base_id), ".json")))
    dlabs <- vapply(.rfv_or(dz$cells, list()), function(z) .rfv_chr1(z$label), "")
    kind <- if (grepl(RFV_RULE_LABEL_RE, lab)) sprintf("rule_selector(%s)", if (nzchar(.rfv_chr1(s$selection_basis))) .rfv_chr1(s$selection_basis) else "필드 없음=구판 전표본")
            else if (nzchar(lab) && lab %in% dlabs) "b1_design_lane" else "other"
    steps[[length(steps) + 1L]] <- list(base_id = .rfv_chr1(E$base_id), cell_code = code, via_cell = via, label = lab, origin_kind = kind,
                                        added = setdiff(ids, carryF), carry = carryF)
    seen <- c(seen, .rfv_chr1(E$base_id))
    pid <- .rfv_chr1(.rfv_or(E$parent, list())$base_id)
    if (!length(carryF) || !nzchar(pid) || pid %in% seen) break
    pc <- .rfv_chr1(.rfv_or(E$carry, list())$source_cell); if (!nzchar(pc)) pc <- .rfv_chr1(E$parent$cell)
    pf <- tryCatch(.rfv_find(L, pid, pc), error = function(e) NULL)
    if (is.null(pf)) { steps[[length(steps) + 1L]] <- list(base_id = pid, cell_code = pc, origin_kind = "unreadable"); break }
    E <- pf$entry; a <- pf$attempt; code <- pc
  }
  steps <- rev(steps)                               # 루트 → 칸
  lineage_ids <- vapply(steps, function(z) .rfv_chr1(z$base_id), "")
  origin <- list()
  for (z in steps) for (fid in .rfv_or(z$added, character(0))) if (is.null(origin[[fid]]))
    origin[[fid]] <- list(base_id = z$base_id, cell_code = z$cell_code, via_cell = .rfv_chr1(z$via_cell), label = z$label, origin_kind = z$origin_kind)
  # 승계 표식 집합("승계 집합 X ⊆ factors")의 출처 = 원장 전역에서 그 집합으로 자기 표식된 칸
  flagsrc <- lapply(Filter(function(z) identical(.rfv_chr1(z$flag), "selection_basis_full_sample_ic_inherited"),
                           .rfv_or(f$attempt$vintage_flags, list())), function(z) {
    m <- regmatches(.rfv_chr1(z$source), regexpr("승계 집합 [A-Za-z0-9_+]+", .rfv_chr1(z$source)))
    set <- if (length(m)) sort(strsplit(sub("^승계 집합 ", "", m), "+", fixed = TRUE)[[1]]) else character(0)
    org <- list()
    for (e in .rfv_or(L$entries, list())) for (x in .rfv_or(e$attempts, list())) {
      if (!any(vapply(.rfv_or(x$vintage_flags, list()), function(v) identical(.rfv_chr1(v$flag), "selection_basis_full_sample_ic"), logical(1)))) next
      xs <- .rfv_fids(.rfv_json(.rfv_or(x[["essence"]], list())$spec), sorted = TRUE)
      if (identical(xs, set)) org[[length(org) + 1L]] <- list(base_id = .rfv_chr1(e$base_id), cell_code = .rfv_code(x),
                                                               in_lineage = .rfv_chr1(e$base_id) %in% lineage_ids)
    }
    list(set = set, self_marked_origins = org,
         relation = if (!length(org)) "origin_not_found"
                    else if (any(vapply(org, function(o) isTRUE(o$in_lineage), logical(1)))) "lineage_carry"
                    else "cross_entry_subset_match")
  })
  list(steps = steps, factor_origin = origin, inherited_flag_sets = flagsrc,
       note = "기록 전용 — 표식 해제 근거가 아니다(표식 정책: 재측정 금지 · 규칙이 바뀌면 새 칸)")
}

#' as-of 재선정(정본 rf_pick_factor_sets) + 원 집합 비교 + 진단(접두 사슬 · 전표본 대조 · 계보 팩터 as-of 통계)
rfv_asof_reselect <- function(root, en, lineage_ids, depth, seed_offset, asof = NULL) {
  depth <- as.integer(depth); seed_offset <- as.integer(seed_offset)
  X <- en$rf_pick_factor_sets(n = 1L, depths = depth, seed_offset = seed_offset, root = root, asof = asof)
  if (is.null(X) || !length(X$cells)) stop("[rf_floor_v2] as-of 재선정 실패 — rf_pick_factor_sets 가 칸을 내지 않았다")
  cell <- X$cells[[1]]
  ids <- vapply(cell$factors, function(f) .rfv_chr1(f$id), "")
  if (length(ids) != depth) stop(sprintf("[rf_floor_v2] as-of 사슬 깊이 %d < 요구 %d (계열 소진) — 바닥 깊이를 채울 수 없다", length(ids), depth))
  Xc <- en$rf_pick_factor_sets(n = depth, depths = seq_len(depth), seed_offset = seed_offset, root = root, asof = asof)
  P <- en$rf_factor_pool(root, asof = asof)
  pool <- P$pool
  st <- lapply(lineage_ids, function(i) {
    r <- pool[pool$id == i]
    if (!nrow(r)) return(list(id = i, in_pool = FALSE))
    list(id = i, in_pool = TRUE, category = r$category, tier_asof = r$tier, ic_asof = r$ic_asof, n_asof = r$n_asof,
         icir3_asof = r$icir3_asof, rankable = isTRUE(r$rankable))
  })
  rk <- intersect(lineage_ids, colnames(en$rf_ic_cormat(P$IC, lineage_ids, asof = P$asof_date)))
  R <- if (length(rk) >= 2L) en$rf_ic_cormat(P$IC, rk, asof = P$asof_date) else NULL
  lin_rho <- if (is.null(R)) NA_real_ else { v <- abs(R[upper.tri(R)]); v <- v[is.finite(v)]; if (length(v)) max(v) else NA_real_ }
  same <- setequal(ids, lineage_ids)
  list(cell = cell, picked_ids = ids, seed_id = X$seed_id, seed_offset = seed_offset, max_rho = X$max_rho,
       prefix_chain = as.character(Xc$picked_ids),
       pool = list(asof = P$asof, asof_source = P$asof_source, selection_basis = P$selection_basis,
                   ic_max_usable = P$ic_max_usable, n_pool = nrow(P$pool), n_rankable = X$n_available,
                   n_unrankable = P$n_unrankable, min_ic_months = P$min_ic_months, tier_levels = P$tier_levels,
                   excluded_pit = P$excluded_pit),
       compare = list(lineage_set = lineage_ids, asof_set = ids, same_set = same,
                      overlap = intersect(ids, lineage_ids), only_asof = setdiff(ids, lineage_ids),
                      only_lineage = setdiff(lineage_ids, ids),
                      jaccard = length(intersect(ids, lineage_ids)) / length(union(ids, lineage_ids)),
                      lineage_asof_max_abs_rho = lin_rho, asof_chain_max_abs_rho = X$max_rho,
                      verdict = if (same) "same_set: 오염 집합이 as-of 로도 선택됨 — 표식 해제 근거 아님 · 새 칸 측정 필요"
                                else "new_set: as-of 규칙은 다른 집합을 고른다 — F1 = 새 집합 새 칸"),
       lineage_factor_asof_stats = st,
       asof_bound_note = "선정 통계 창의 끝은 결정 시점(격자 fixed_axes.start_date) 이하 — rf_factor_arms.R 상한 가드(P0-08 잔여 R3 · 2026-09-25)가 NA(전표본)·미래·결정 시점 뒤 as-of 를 거부한다. 전표본 대조 진단 경로는 폐지됐다(양성 대조는 검사 test_rf_floor_v2.R [I] 의 창 안·창 밖 주입 짝이 맡는다)")
}

#' 계보 루트 팩터 계열의 as-of 1위가 시드가 되는 오프셋 — 라운드로빈 첫 바퀴(계열 수만큼)만 훑는다(정본 호출 · 정렬 사본 금지)
rfv_family_seed_offset <- function(root, en, family, asof = NULL) {
  P <- en$rf_factor_pool(root, asof = asof)
  fams <- unique(P$pool[P$pool$rankable == TRUE]$category)
  for (k in seq_along(fams) - 1L) {
    X <- en$rf_pick_factor_sets(n = 1L, depths = 1L, seed_offset = k, root = root, asof = asof)
    if (!is.null(X) && identical(P$pool[P$pool$id == X$seed_id]$category, family)) return(k)
  }
  NA_integer_
}

#' F1 스펙 — 셀(정본 선정 결과) + 계보 칸 스펙의 기저 엔진·비중·유니버스·리밸 + 격자 fixed_axes(고정 축 정본)
rfv_f1_spec <- function(root, en, cell, lineage_spec, grid, floor_id = "F1") {
  fa <- grid$fixed_axes
  if (is.null(fa) || is.null(fa$base_weight)) stop("[rf_floor_v2] 격자 fixed_axes.base_weight 부재")
  ids <- vapply(cell$factors, function(f) .rfv_chr1(f$id), "")
  rp <- en$rf_root_papers_for(ids, base_paper = lineage_spec$root_paper, root = root)
  strip_note <- function(x) { x$base_weight_note <- NULL; x }
  list(code = cell$code, floor_id = floor_id, label = cell$label, block = "B1",
       fixed_axes = fa, fixed_axes_match_lineage_spec = identical(strip_note(fa), strip_note(.rfv_or(lineage_spec$fixed_axes, list()))),
       base_signal = lineage_spec$base_signal, base_signal_md5 = .rfv_md5(.rfv_np(.rfv_or(lineage_spec$base_signal, list())$path)),
       base_weight = fa$base_weight,
       factors = cell$factors, weighting = lineage_spec$weighting, universe = lineage_spec$universe,
       rebalance = lineage_spec$rebalance, overlay = list(), overlay_cell = list(),
       root_paper = lineage_spec$root_paper, root_papers = rp$papers, root_paper_families = rp$families,
       unmapped_families = rp$unmapped_families,
       selection_basis = cell$selection_basis, selection_asof = cell$selection_asof, basis = cell$basis,
       idea = sprintf("[floor v2 %s] %s — B1/multifactor(as-of 규칙 선정기) · weighting=%s · universe=%s · overlay=none · 기저 엔진 = 계보 칸 스펙 승계",
                      floor_id, .rfv_chr1(cell$label), .rfv_chr1(.rfv_or(lineage_spec$weighting, list())$kind),
                      .rfv_chr1(.rfv_or(lineage_spec$universe, list())$kind)),
       gate_note = "P0-14 관문(rf_lineage_flags.R) 이 이 칸의 팩터를 as-of 증명으로 보려면 원장 attempt 의 셀 코드가 B1_ 으로 시작하고 라벨이 규칙 선정기 형식('N팩터 직교(')이며 spec$selection_basis == 'asof_ic' 여야 한다 — 이 스펙을 그대로 쓸 것")
}

#' floor v2 문서 생성(쓰기 없음)
rfv_build <- function(root = .RFV_ROOT(), cfg_path = file.path(root, "06_Registry/prereg/reference_floors_v2.config.json"),
                      code_root = root, en = NULL) {
  cfg <- rfv_load_cfg(cfg_path)
  if (is.null(en)) en <- rfv_env(code_root)
  L <- rfv_ledger(root, 1L)
  gp <- file.path(root, "06_Registry/reinforce_program.json"); grid <- .rfv_json(gp)
  if (is.null(grid)) stop("[rf_floor_v2] 격자 부재: ", gp)
  ex <- cfg$exclusion; fl <- cfg$floors
  asof <- cfg$asof   # NULL = 격자 start_date

  # ── 계보 칸(옛 F1) 인용 + 판정 + 출처 ──
  lc <- fl$F1$lineage_cell
  lin <- rfv_cite(L, lc$base_id, lc$cell_code, en)
  lin_prov <- rfv_lineage_provenance(L, lc$base_id, lc$cell_code, root)
  lin_expo <- rfv_provenance_exposure(root, lin_prov, ex$design_exposure)
  lin_spec <- .rfv_json(lin$spec_path)
  if (is.null(lin_spec)) stop("[rf_floor_v2] 계보 칸 스펙 판독 불가: ", lin$spec_path)
  lin_bx <- rfv_base_engine_exposure(root, lin_spec$base_signal, ex$base_engine_exposure, ex$design_exposure)
  lin_assess <- rfv_assess(lin, ex, c(lin_expo, list(lin_bx)))
  lineage_ids <- lin$factors
  depth <- length(lineage_ids)
  if (depth < 1L) stop("[rf_floor_v2] 계보 칸에 DB 팩터가 없다 — 깊이를 정할 수 없다")

  # ── F1: as-of 재선정 ──
  sel <- rfv_asof_reselect(root, en, lineage_ids, depth, fl$F1$seed_rule$seed_offset, asof = asof)
  f1_spec <- rfv_f1_spec(root, en, sel$cell, lin_spec, grid, "F1")
  # ★적대검증 수리 — F1 은 기저 엔진을 승계한다: 그 엔진의 설계 노출을 F1 에 싣고 사전등록 관문을 문서가 스스로 낸다
  bxv <- .rfv_chr1(ex$base_engine_exposure$verdict)
  f1_bx <- rfv_base_engine_exposure(root, f1_spec$base_signal, ex$base_engine_exposure, ex$design_exposure)
  gate <- rfv_prereg_gate(root, cfg$prereg_gate, f1_bx, bxv, ex$base_engine_exposure)

  # ── 대안(비채택 · 진단): 계보 루트 팩터 계열 시드 ──
  alts <- lapply(.rfv_or(fl$F1$alternatives, list()), function(al) {
    if (!identical(.rfv_chr1(.rfv_or(al$seed_rule, list())$kind), "family_top_of_lineage_root")) return(list(id = al$id, adopted = FALSE, error = "알 수 없는 seed_rule"))
    root_fid <- names(lin_prov$factor_origin)[1]
    st <- Filter(function(z) identical(z$id, root_fid), sel$lineage_factor_asof_stats)
    fam <- if (length(st) && isTRUE(st[[1]]$in_pool)) st[[1]]$category else NA_character_
    off <- if (is.na(fam)) NA_integer_ else rfv_family_seed_offset(root, en, fam, asof)
    if (is.na(off)) return(list(id = al$id, adopted = FALSE, lineage_root_factor = root_fid, family = fam, error = "계열 시드 오프셋 없음"))
    s2 <- rfv_asof_reselect(root, en, lineage_ids, depth, off, asof = asof)
    ro <- lin_prov$factor_origin[[root_fid]]
    anchor_expo <- Filter(function(z) identical(.rfv_chr1(z$base_id), .rfv_chr1(ro$base_id)), lin_expo)
    list(id = al$id, adopted = isTRUE(al$adopted), why_not_adopted = al$why_not_adopted,
         anchor_origin = ro, anchor_origin_exposure = anchor_expo,
         anchor_note = "시드 계열 = 계보 루트 팩터의 계열 — 그 팩터를 고른 칸(anchor_origin)의 설계 재료 노출이 이 대안의 시드 결정에 승계된다",
         lineage_root_factor = root_fid, family = fam, seed_offset = off, seed_id = s2$seed_id,
         picked_ids = s2$picked_ids, compare = s2$compare)
  })

  # ── F1p: carry 재현 쌍(정의) + 옛 promo4 carry 사실 ──
  pe <- .rfv_find(L, fl$F1p$legacy_entry)$entry
  legacy_f1p <- list(base_id = pe$base_id, carry = pe$carry, parent = pe$parent, base_remeasure = pe$base_remeasure,
                     base_artifacts = pe$base_artifacts,
                     same_artifact_as_lineage_cell = identical(.rfv_np(pe$base_artifacts), .rfv_np(lin$artifacts)),
                     same_remeasure_md5_as_lineage_cell = identical(.rfv_chr1(.rfv_or(pe$base_remeasure, list())$md5),
                                                                    .rfv_chr1(.rfv_or(lin$measurement_regime, list())$remeasure_md5)),
                     carry_set_equals_lineage_set = setequal(.rfv_fids(pe$carry), lineage_ids))

  # ── F2 · F3 인용 + 판정 ──
  cite_assess <- function(k) {
    c1 <- rfv_cite(L, fl[[k]]$base_id, fl[[k]]$cell_code, en)
    pv <- rfv_lineage_provenance(L, fl[[k]]$base_id, fl[[k]]$cell_code, root)
    xp <- rfv_provenance_exposure(root, pv, ex$design_exposure)
    bx <- rfv_base_engine_exposure(root, .rfv_or(.rfv_json(c1$spec_path), list())$base_signal, ex$base_engine_exposure, ex$design_exposure)
    list(cite = c1, assess = rfv_assess(c1, ex, c(xp, list(bx))), provenance = pv, design_exposure = xp, base_engine_exposure = bx)
  }
  f2 <- cite_assess("F2"); f3 <- cite_assess("F3_DNN")

  pin <- function(rel) list(path = rel, md5 = .rfv_md5(file.path(root, rel)))
  cpin <- function(rel) list(path = rel, md5 = .rfv_md5(file.path(code_root, rel)))
  list(
    schema = RFV_SCHEMA, version = 2L, status = "draft_pre_registration",
    status_note = "초안 — F1·F1p 는 스펙만(측정 0). 사전등록(rf_prereg) 뒤 측정. 인용 수치는 원장 그대로(close_t1) · 레버 판정 인용 금지(등급 대체 아님).",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    generator = list(file = "02_Infrastructure/reinforcement/rf_floor_v2.R", fn = "rfv_build", root = .rfv_np(root), code_root = .rfv_np(code_root),
                     config = .rfv_np(cfg_path), config_md5 = .rfv_md5(cfg_path),
                     path_note = "경로 문자열에는 생성 루트가 박힌다(rf_pick_factor_sets basis·asof_source 등) — 비교(rfv_write·rfv_verify)는 생성 루트·정본 루트를 <ROOT> 로 정규화해서 한다"),
    pins = list(ledger_l1 = list(path = "06_Registry/reinforce_ledger_l1.json", md5 = L$.md5, current_axis = L$current_axis,
                                 last_updated = L$last_updated),
                grid = pin("06_Registry/reinforce_program.json"), factor_evidence = pin("06_Registry/factor_evidence.json"),
                factor_panel_axis = pin("06_Registry/factor_panel_axis.json"), pit_quarantine = pin("06_Registry/pit_quarantine.json"),
                factor_ic_monthly = pin(".cache/factor_db/factor_ic_monthly.parquet"), factor_registry = pin(".cache/factor_db/factor_registry.json"),
                rf_factor_arms = cpin("02_Infrastructure/ops/rf_factor_arms.R"), rf_runner_gates = cpin("02_Infrastructure/reinforcement/rf_runner_gates.R"),
                rf_floor_v2 = cpin("02_Infrastructure/reinforcement/rf_floor_v2.R"),
                f1_base_engine = list(path = .rfv_np(f1_spec$base_signal$path), md5 = f1_spec$base_signal_md5),
                lineage_spec = list(path = .rfv_np(lin$spec_path), md5 = lin$spec_md5)),
    floors = list(
      F1 = list(status = "defined_unmeasured", kind = fl$F1$kind, role = fl$F1$role,
                selection_path = list(rule = "rf_factor_arms.R::rf_pick_factor_sets(n=1, depths=depth, seed_offset, asof)",
                                      depth = depth, depth_rule = fl$F1$depth_rule, seed_rule = fl$F1$seed_rule,
                                      asof_config = if (is.null(asof)) "null(격자 fixed_axes.start_date)" else asof),
                reselect = sel, spec = f1_spec, alternatives = alts,
                base_engine_exposure = f1_bx,
                prereg_blockers = grep("^F1:", gate$blockers, value = TRUE)),
      F1p = list(status = "defined_unmeasured", kind = fl$F1p$kind, role = fl$F1p$role,
                 definition = list(spec_ref = "floors.F1.spec(carry = F1 팩터 집합 · weighting·universe 동일 · 추가 팩터 0 = B1_0 재현 칸)",
                                   e3_tolerance = fl$F1p$e3_tolerance, e3_tolerance_source = fl$F1p$e3_tolerance_source),
                 legacy_promo4_carry = legacy_f1p),
      F2 = list(status = if (isTRUE(f2$assess$eligible)) "cited_eligible" else "excluded", role = fl$F2$role,
                cite = f2$cite, assess = f2$assess, provenance = f2$provenance, design_exposure = f2$design_exposure, base_engine_exposure = f2$base_engine_exposure),
      F3_DNN = list(status = if (isTRUE(f3$assess$eligible)) "cited_eligible" else "excluded", role = fl$F3_DNN$role,
                    cite = f3$cite, assess = f3$assess, provenance = f3$provenance, design_exposure = f3$design_exposure, base_engine_exposure = f3$base_engine_exposure)),
    lineage_reference = list(role = "옛 F1(플랜 원안 22632 promo3 B1_3) — 바닥 아님 · 기록", cite = lin, assess = lin_assess,
                             provenance = lin_prov, design_exposure = lin_expo, base_engine_exposure = lin_bx),
    prereg_gate = gate,
    measurement_policy = list(
      numbers = "원장 인용 전용(close_t1) — 손계산·재구성 0",
      lever_delta_basis = "레버 Δ 는 사전등록 뒤 같은 regime·빈티지에서 잰 바닥 재실행판 기준(인용 수치 기준 아님)",
      n_accounting = "F1 측정의 n_trials 에 바닥 계보 선택 이력 포함(플랜 P2 공통 규약 · ORGANIC-DE Q①)"),
    evidence = cfg$evidence, open_items_after_prereg = cfg$open_items_after_prereg,
    config_basis = cfg$decided_basis)
}

# ── 인용 충실도 검사(순수 재독) — 문서의 인용 칸이 원장 attempt 필드와 같은가. 다르면 차이 목록.
rfv_check_citations <- function(doc, root) {
  L <- fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  cites <- list(F2 = doc$floors$F2$cite, F3_DNN = doc$floors$F3_DNN$cite, lineage = doc$lineage_reference$cite)
  bad <- character(0)
  for (nm in names(cites)) {
    c1 <- cites[[nm]]; if (is.null(c1)) { bad <- c(bad, paste0(nm, ":missing")); next }
    E <- Filter(function(e) identical(.rfv_chr1(e$base_id), .rfv_chr1(c1$base_id)), L$entries)
    A <- if (length(E)) Filter(function(a) identical(as.character(a$n), as.character(c1$n)), E[[1]]$attempts) else list()
    if (length(A) != 1L) { bad <- c(bad, paste0(nm, ":attempt_not_found")); next }
    a <- A[[1]]
    if (!identical(rfv_diff(c1$essence, a[["essence"]]), character(0))) bad <- c(bad, paste0(nm, ":essence"))
    if (!identical(.rfv_chr1(c1$grade), .rfv_chr1(a$grade))) bad <- c(bad, paste0(nm, ":grade"))
    if (!identical(rfv_diff(c1$measurement_regime, a$measurement_regime), character(0))) bad <- c(bad, paste0(nm, ":measurement_regime"))
    fl_doc <- vapply(.rfv_or(c1$vintage_flags, list()), function(z) .rfv_chr1(z$flag), "")
    fl_led <- vapply(.rfv_or(a$vintage_flags, list()), function(z) .rfv_chr1(z$flag), "")
    if (!identical(fl_doc, fl_led)) bad <- c(bad, paste0(nm, ":vintage_flags"))
    if (!identical(.rfv_chr1(.rfv_or(c1$adversary, list())$ledger_verdict), .rfv_chr1(.rfv_or(a$adversary, list())$verdict)))
      bad <- c(bad, paste0(nm, ":adversary_verdict"))
  }
  bad
}

# ── 구조 비교(경로 목록) — JSON 왕복 뒤 비교(수치 표기 차이 제거)
.rfv_rt <- function(x) fromJSON(toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA), simplifyVector = FALSE)
rfv_diff <- function(a, b, path = "") {
  a <- .rfv_rt(a); b <- .rfv_rt(b)
  walk <- function(x, y, p) {
    if (is.list(x) && is.list(y)) {
      nx <- names(x); ny <- names(y)
      if (is.null(nx) && is.null(ny)) {
        if (length(x) != length(y)) return(paste0(p, "[len]"))
        return(unlist(lapply(seq_along(x), function(i) walk(x[[i]], y[[i]], sprintf("%s[%d]", p, i)))))
      }
      ks <- union(nx, ny)
      return(unlist(lapply(ks, function(k) if (!(k %in% nx) || !(k %in% ny)) paste0(p, "/", k, "[missing]") else walk(x[[k]], y[[k]], paste0(p, "/", k)))))
    }
    if (identical(x, y)) character(0) else p
  }
  out <- walk(a, b, path); if (is.null(out)) character(0) else out
}

.rfv_strip <- function(doc) { doc$generated_at <- NULL; doc }
.RFV_CANON_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"   # 정본(운영) 루트 — 경로 정규화 전용(설정값 아님)
#' 경로 정규화(비교 전용) — 백슬래시 → 슬래시 · 생성 루트·정본 루트 접두 → <ROOT>. 저장 문서는 바꾸지 않는다.
.rfv_norm <- function(x, roots) {
  roots <- unique(gsub("\\", "/", as.character(unlist(roots)), fixed = TRUE)); roots <- roots[!is.na(roots) & nzchar(roots)]
  roots <- roots[order(-nchar(roots))]
  rec <- function(v) {
    if (is.list(v)) { nm <- names(v); v <- lapply(v, rec); names(v) <- nm; return(v) }
    if (is.character(v)) { v <- gsub("\\", "/", v, fixed = TRUE); for (r in roots) v <- gsub(r, "<ROOT>", v, fixed = TRUE); return(v) }
    v
  }
  rec(x)
}
.rfv_cmp_view <- function(doc, extra_root = NULL) {
  r <- c(.rfv_or(.rfv_or(doc$generator, list())$root, ""), .rfv_or(.rfv_or(doc$generator, list())$code_root, ""), extra_root, .RFV_CANON_ROOT)
  x <- .rfv_norm(.rfv_strip(doc), r); x$generator$root <- NULL; x$generator$code_root <- NULL; x
}

#' 쓰기 — 원자적 · 기존 파일과 내용(생성 시각 제외)이 다르면 거부(사전등록 불변성) · 같으면 already
rfv_write <- function(doc, out) {
  txt <- toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
  if (file.exists(out)) {
    old <- fromJSON(out, simplifyVector = FALSE)
    d <- rfv_diff(.rfv_cmp_view(old), .rfv_cmp_view(fromJSON(txt, simplifyVector = FALSE)))
    if (!length(d)) return(invisible("already"))
    stop(sprintf("[rf_floor_v2] 기존 파일과 내용이 다르다(%d곳 · 예: %s) — 덮어쓰지 않는다(사전등록 불변성): %s",
                 length(d), paste(head(d, 3), collapse = " ; "), out))
  }
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  tmp <- sprintf("%s.tmp%d", out, Sys.getpid())
  con <- file(tmp, open = "wb"); writeBin(charToRaw(enc2utf8(as.character(txt))), con); close(con)
  if (!file.rename(tmp, out)) { unlink(tmp); stop("[rf_floor_v2] 원자 교체 실패: ", out) }
  invisible("written")
}

#' 핀 대조 — 저장된 문서와 지금 재생성한 문서의 차이(생성 시각 제외). 사전등록 직전에 부른다.
rfv_verify <- function(path, root = .RFV_ROOT(), cfg_path = file.path(root, "06_Registry/prereg/reference_floors_v2.config.json"),
                       code_root = root, en = NULL) {
  old <- fromJSON(path, simplifyVector = FALSE)
  new <- rfv_build(root, cfg_path, code_root, en)
  d <- rfv_diff(.rfv_cmp_view(old), .rfv_cmp_view(.rfv_rt(new)))
  list(drift = d, n_drift = length(d), pins_drift = grep("^/pins", d, value = TRUE),
       floors_drift = grep("^/floors", d, value = TRUE), gate_drift = grep("^/prereg_gate", d, value = TRUE),
       gate_ready_now = isTRUE(new$prereg_gate$ready), gate_blockers_now = as.character(unlist(new$prereg_gate$blockers)),
       citations = rfv_check_citations(old, root))
}

cat("[rf_floor_v2.R] Loaded (P2-03) — rfv_build / rfv_cite / rfv_assess / rfv_lineage_provenance / rfv_asof_reselect / rfv_f1_spec / rfv_check_citations / rfv_write / rfv_verify\n")
