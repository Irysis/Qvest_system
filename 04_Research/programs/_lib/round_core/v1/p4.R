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
## 경계: 루프가 고쳐 쓰는 것은 생성기(프롬프트 파일)뿐이다 — 판정 규칙(채택 규칙 · 예산)은 사슬 판에 고정되고, 바꾸려면 새 사슬 판을 등록한다.
##   수치는 R 계약 산출만(AX-008). 이 파일은 측정하지 않는다(칸 측정 = 정본 셀 워커 · 호출자). 시험 창 값은 계산도 반환도 하지 않는다.

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
               audit_verdict = .rcs_str(it[["audit_verdict"]]), paper_key = .rcs_str(it[["paper_key"]]), at = .rcs_str(it[["enqueued_at"]] %||% it[["held_at"]])))
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
                                      audit_verdict = r$audit_verdict, paper_key = r$paper_key, lane_artifacts = .rcp4_rel(r$artifacts_raw, root),
                                      from_registry = TRUE)
  }
  paths <- vapply(rows, function(x) as.character(x$engine_path), "")
  sq <- list()
  for (j in seq_len(nrow(Q))) {
    q <- Q[j]; ep <- .rcp4_rel(q$engine_path, root); hit <- which(paths %in% ep)
    if (!length(hit)) { rows[[length(rows) + 1L]] <- list(key = sprintf("standing:%s:%s", q$round_id, q$code), engine_path = ep, program = "P1_RETURN",
                                                          where = "standing", has_short = NA, implementation_suspect = NA, holdings_claim_mismatch = NA,
                                                          audit_verdict = NA_character_, paper_key = q$paper_key, lane_artifacts = NA_character_, from_registry = FALSE)
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
               artifacts = art, lane_artifacts = x$lane_artifacts, paper_key = x$paper_key, fdv_stale = fv$stale,
               eligible = !length(rs), reason = paste(unique(rs), collapse = ";"), reason_detail = paste(det, collapse = " | ")))
  }), fill = TRUE)
  out[order(-eligible, key)]
}
## 풀 스냅샷 md5 — 자격 판정에 닿는 열만(정렬 · 직렬화 고정)
rc_p4_pool_md5 <- function(pool) {
  P <- as.data.table(pool)[, .(key, engine_path, engine_md5, standing_qualified, eligible, reason)][order(key)]
  .rcs_md5s(as.character(toJSON(P, dataframe = "rows", null = "null", na = "null", digits = NA)))
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
rxg_revise <- function(new_dir, reason, evidence, root = rc_root(), path = NULL, outcomes_path = NULL) {
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
  n0 <- length(G$versions)
  G$versions[[n0 + 1L]] <- list(id = id, dir = rel, files = files, created_at = rc_now(), reason = reason, evidence = as.list(ev))
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
rc_p4_chain_new <- function(chain_dir, chain_id, base_key, pool, base_cell_spec, adoption_rules, budget, generator_id = NULL,
                            purpose = "", base_artifacts = NULL, root = rc_root(), gen_path = NULL) {
  sp <- rc_p4_spec_path(chain_dir); if (file.exists(sp)) .rcp4_err("이미 사슬 판이 있다 — 덮어쓰지 않는다: ", chain_dir)
  P <- as.data.table(pool); row <- P[key == base_key]
  if (!nrow(row)) .rcp4_err("기저 풀 밖 key: ", base_key)
  if (!isTRUE(row$eligible[1])) .rcp4_err("기저 풀 자격 미달 key(", base_key, "): ", row$reason[1])
  art <- base_artifacts %||% row$artifacts[1]; if (is.na(art)) .rcp4_err("기저 산출(artifacts) 없음: ", base_key)
  csr <- .rcp4_rel(base_cell_spec, root); csa <- .rcp4_abs(csr, root); if (!file.exists(csa)) .rcp4_err("기저 칸 사양 없음: ", base_cell_spec)
  gp <- rxg_pin(generator_id, root, gen_path)
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
  rc_p4_chain_check(spec, root, gen_path)
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
  head_k <- if (length(acc)) as.integer(acc[[length(acc)]]$k) else 0L
  head_m <- if (length(acc)) acc[[length(acc)]]$metrics else reg$base_metrics
  streak <- 0L; for (r in rev(res)) { if (is.null(r$r7) || is.na(r$r7)) next; if (identical(r$r7, "noise")) streak <- streak + 1L else break }
  list(spec = spec, reg = reg, recs = recs, opens = opens, results = res, open_ks = ks, decided_ks = rk, head_k = head_k, head_metrics = head_m,
       noise_streak = streak, closed = any(vapply(recs, function(r) identical(r$event, "chain_closed"), TRUE)), tau = as.Date(spec$tau_d))
}
.rcp4_cell_of <- function(st, k) {
  if (k == 0L) return(st$spec$base$cell_spec)
  o <- Filter(function(r) identical(as.integer(r$k), as.integer(k)), st$opens); if (!length(o)) .rcp4_err("그런 걸음이 없다: ", k)
  o[[1]]$cell_spec_path
}
.rcp4_artifacts_of <- function(st, k) {
  if (k == 0L) return(st$spec$base$artifacts)
  r <- Filter(function(r) identical(as.integer(r$k), as.integer(k)), st$results); if (!length(r)) NA_character_ else r[[1]]$artifacts
}
#' 사슬 판 등록(한 번) — 검사 · 풀 md5 대조(지금 풀 = 사양 스냅샷) · 기저 자격 · 기저 보는 창 지표 → 원장 첫 줄 chain_registered
rc_p4_chain_register <- function(chain_dir, pool, root = rc_root(), gen_path = NULL, metrics_fun = rc_p4_visible_metrics, ...) {
  spec <- rc_json_read(rc_p4_spec_path(chain_dir))
  rr <- rc_p4_chain_check(spec, root, gen_path)
  if (length(rc_p4_steps_read(chain_dir))) .rcp4_err("이미 등록된 사슬 판(원장이 비어 있지 않다): ", chain_dir)
  P <- as.data.table(pool)
  if (!identical(rc_p4_pool_md5(P), spec$base$pool_md5)) .rcp4_err("기저 풀이 사양 스냅샷과 다르다 — 지금 풀로 새 사슬 판을 만든다(pool_md5)")
  row <- P[key == spec$base$key]
  if (!nrow(row) || !isTRUE(row$eligible[1])) .rcp4_err("기저가 풀 밖이거나 자격 미달: ", spec$base$key)
  bm <- metrics_fun(.rcp4_abs(spec$base$artifacts, root), root = root, tau = spec$tau_d, ...)
  bm <- bm[intersect(names(bm), c(sub("^d_?", "", RC_P4_METRICS), RC_P4_METRICS, "n_crisis_vis", "window", "bottleneck", "card_error"))]
  lk <- rc_after_tau_leaks(bm, as.Date(spec$tau_d)); if (length(lk)) .rcp4_err("기저 지표에 τ_D 뒤 날짜: ", paste(lk, collapse = ","))
  .rcp4_append(chain_dir, list(event = "chain_registered", chain_id = spec$chain_id, spec_md5 = rc_md5(rc_p4_spec_path(chain_dir)),
                               rules_resolved = rr, generator = spec$generator, base_key = spec$base$key, base_metrics = bm, git_head = rc_git_head(root)))
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
#' 걸음 판정 — 산출 폴더 → 보는 창 지표(②) → 등록된 채택 규칙(해석본) 기계 적용 → 원장 step_result
#'   판정 표 = 걸음 지표 + 부모(사슬 머리) 대비 차이 · 미측정 = 기각(accept 는 모든 규칙이 참일 때만) · r7 = |dS_vis| ≥ 개선 여유면 signal · 아니면 noise
rc_p4_step_decide <- function(chain_dir, k, artifacts, root = rc_root(), metrics_fun = rc_p4_visible_metrics, ...) {
  st <- .rcp4_state(chain_dir, root); k <- as.integer(k)
  o <- Filter(function(r) identical(as.integer(r$k), k), st$opens)
  if (!length(o)) .rcp4_err("열지 않은 걸음: ", k)
  if (k %in% st$decided_ks) .rcp4_err("이미 판정한 걸음 — 다시 판정하지 않는다: ", k)
  o <- o[[1]]; csa <- .rcp4_abs(o$cell_spec_path, root)
  if (!file.exists(csa) || !identical(rc_md5(csa), o$cell_spec_md5)) .rcp4_err("칸 사양이 열린 뒤 바뀌었다(R2): ", o$cell_spec_path)
  pm <- if (identical(as.integer(o$parent), 0L)) st$reg$base_metrics else
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
  rec <- list(event = "step_result", k = k, artifacts = .rcp4_rel(artifacts, root), metrics = mk,
              table = as.list(T[1]), rules = as.list(stats::setNames(v, ids)), decision = if (accept) "accept" else "reject",
              reasons = as.list(reasons), r7 = r7)
  lk <- rc_after_tau_leaks(rec, st$tau); if (length(lk)) .rcp4_err("걸음 판정 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  .rcp4_append(chain_dir, rec)
}
#' 상태 줄
rc_p4_status <- function(chain_dir, root = rc_root()) {
  st <- tryCatch(.rcp4_state(chain_dir, root, need_registered = FALSE), error = function(e) e)
  if (inherits(st, "error")) return(sprintf("[P4 사슬] %s — 판독 실패: %s", basename(chain_dir), conditionMessage(st)))
  na <- sum(vapply(st$results, function(r) identical(r$decision, "accept"), TRUE)); vv <- rc_p4_steps_verify(chain_dir)
  c(sprintf("[P4 사슬] %s · %s · 걸음 %d(판정 %d · 채택 %d · 기각 %d) · 머리 = %s · 연속 잡음 %d/%s · 최대 %s · 생성기 %s · 원장 사슬 %s(%d줄)%s",
            st$spec$chain_id, if (is.null(st$reg)) "등록 전" else "등록", length(st$opens), length(st$results), na, length(st$results) - na,
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

## ── ⑥ 닫기 ──────────────────────────────────────────────────────────────────
#' 닫기 — 최종 후보 = 마지막 채택 걸음(없으면 '개선 없음') · 결과 원장(rc_outcome_record → rc_outcome_append_round) · 마감 훅 · 원장 chain_closed
#'   마감 훅: 02_Infrastructure/programs/selection_regrade.R::sr_regrade(후보, 시행 = 기저 + 모든 걸음 칸)가 있으면 부른다 — 결과(전기간 · 사람 쪽)는
#'   finalize.json 에만 쓰고 원장 · 결과 원장에는 상태 · 파일 md5 만 싣는다(결과 원장 = 다음 설계 입력 · 보는 창 규율). 없으면 finalize = "pending".
#'   Judge 요청 파일은 쓰지 않는다.
rc_p4_close <- function(chain_dir, note, probes = character(0), lessons = character(0), r7 = NA_character_, no_probes_reason = NULL,
                        root = rc_root(), outcomes_path = NULL, registry_path = NULL, regrade = TRUE, regrade_write = FALSE) {
  st <- .rcp4_state(chain_dir, root)
  if (st$closed) .rcp4_err("이미 닫힌 사슬이다")
  und <- setdiff(st$open_ks, st$decided_ks); if (length(und)) .rcp4_err("판정 안 된 걸음이 있다 — 판정 뒤 닫는다: ", paste(und, collapse = ","))
  acc <- Filter(function(r) identical(r$decision, "accept"), st$results); fin <- if (length(acc)) acc[[length(acc)]] else NULL
  ns <- length(st$results); na <- length(acc)
  by <- list(); for (o in st$opens) { bt <- o$block_type; r <- Filter(function(x) identical(as.integer(x$k), as.integer(o$k)), st$results)[[1]]
    if (is.null(by[[bt]])) by[[bt]] <- list(accept = 0L, reject = 0L)
    by[[bt]][[r$decision]] <- by[[bt]][[r$decision]] + 1L }
  if (is.na(r7)) r7 <- if (na) "signal" else if (ns) "noise" else NA_character_
  label <- sprintf("사슬 %s — 걸음 %d(채택 %d · 기각 %d) · 최종 후보 %s", st$spec$chain_id, ns, na, ns - na, if (is.null(fin)) "개선 없음" else paste("걸음", fin$k))
  spec_like <- list(program = RC_P4_PROGRAM, round_id = st$spec$chain_id, template = "p4_chain", tau_d = st$spec$tau_d,
                    cells = lapply(st$opens, function(o) list(code = paste0("k", o$k), role = "variant")))
  P <- list(prereg = rc_p4_spec_path(chain_dir), results = chain_dir)
  rec <- rc_outcome_record(spec_like, list(summary = list(label = label)), note, probes = probes, lessons = lessons, r7 = r7,
                           no_probes_reason = no_probes_reason, P = P, root = root)
  rec$report <- rc_rel(rc_p4_steps_path(chain_dir), root)
  fz <- list(status = "pending", why = "selection_regrade.R 없음")
  srf <- file.path(root, "02_Infrastructure/programs/selection_regrade.R")
  if (is.null(fin)) fz <- list(status = "no_candidate", why = "채택 걸음 없음")
  else if (isTRUE(regrade) && file.exists(srf)) {
    trials <- unique(na.omit(c(.rcp4_abs(st$spec$base$artifacts, root), vapply(st$results, function(r) .rcp4_abs(as.character(r$artifacts), root), ""))))
    e <- new.env(parent = globalenv())
    res <- tryCatch({ invisible(utils::capture.output(suppressMessages(sys.source(srf, envir = e, keep.source = FALSE))))
                      e$sr_regrade(.rcp4_abs(fin$artifacts, root), trials, root = root, write = isTRUE(regrade_write)) },
                    error = function(z) structure(list(error = conditionMessage(z)), class = "rcp4_err"))
    ff <- file.path(chain_dir, "finalize.json")
    rc_json_write(list(schema = "rc_p4_finalize_v1", audience = "사람 쪽(전기간 · 시험 창 포함 가능) — 처방 · 리뷰 레인 열람 금지",
                       at = rc_now(), candidate = fin$artifacts, trials = as.list(vapply(trials, .rcp4_rel, "", root = root)), write = isTRUE(regrade_write),
                       result = if (inherits(res, "rcp4_err")) list(error = res$error) else res), ff)
    fz <- list(status = if (inherits(res, "rcp4_err")) "error" else "done", regrade_status = if (inherits(res, "rcp4_err")) NA_character_ else as.character(res$status %||% NA)[1],
               file = rc_rel(ff, root), md5 = rc_md5(ff), n_trials = length(trials), write = isTRUE(regrade_write))
  } else if (!isTRUE(regrade)) fz <- list(status = "pending", why = "regrade = FALSE")
  rec$extra <- list(generator_version = st$spec$generator$id, n_steps = ns, n_accepted = na, by_block = by,
                    final_candidate = if (is.null(fin)) NULL else list(k = fin$k, artifacts = fin$artifacts), chain_spec_md5 = st$reg$spec_md5,
                    finalize = fz[c("status", intersect(names(fz), c("regrade_status", "why", "md5")))])   # 등급 전후 값은 finalize.json 에만(전기간)
  ap <- if (is.null(outcomes_path)) rc_outcomes_path(root, registry_path) else outcomes_path
  rc_outcome_append_round(rec, ap)
  .rcp4_append(chain_dir, list(event = "chain_closed", label = label, final_k = if (is.null(fin)) NULL else fin$k, finalize = fz, outcomes = rc_rel(ap, root)))
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
