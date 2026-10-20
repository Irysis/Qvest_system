## round_core v1 · standing — 상설 자격 모드(WP5 · 도훈 10-20 채택 'P1 상설 자격 등록' · 결정 L1-SPEED-LEVERS-20261020)
##   엔진 자격 규칙을 프로그램 단위로 한 번 사전등록(사양 standing: true · P1S01)하면, 그 뒤 충실구현 레인이 낸 엔진마다
##   라운드 의식 없이 스캔 → 칸 사양 생성 → 측정 → 판정 → 보고가 돈다. R2(측정 전 등록)는 그대로다.
##   · 규칙 · 스캔 규칙 · 생성 함수 핀(rc_p1_cell_spec md5 · 선례 · 정본 고정 축)은 등록본(prereg.json 의 spec)에 고정된다.
##   · 항목 칸 사양은 등록된 생성 함수가 재량 없이 만들고, 측정 · 판정 직전 다시 만들어 md5 를 대조한다.
##   · 항목마다 사전등록 md5(= 등록부) · 사양 md5(= 등록본) · 생성 함수 핀 · 판정 경로 핀(rc_pins_mismatches)을 본다.
##   판정 원장 = 사전등록 정본 옆 standing_ledger.jsonl — 추가 전용, 줄마다 앞 줄 md5(prev) 사슬(중간 수정 · 삭제를 잡는다).
##   규칙 · 생성 함수 · 판정 경로가 바뀌면 새 판(P1S02 …)을 등록한다 — 옛 판정은 남고, 새 판이 등록되면 옛 판은 새 항목을 받지 않는다.
##   등록부(research_programs.json)는 읽기만 한다(쓰기 잠금 WP3 전 동시 갱신 유실 방지 — 등록부 쓰기는 rc_register 한 번뿐).
##   수치는 R 계약 산출만(AX-008 — 칸 평가 rc_eval_cell · 판정 표 rc_p1_table). 원장 · 스캔 기록에는 보는 창 값만 싣는다(τ_D).

RC_STANDING_LEDGER_SCHEMA <- "rc_standing_ledger_v1"
RC_STANDING_ORIENT <- c("engine_native", "factor_db_asof", "orientation_layer")
RC_STANDING_FDB_CALLS <- c("load_month_factors", "load_daily_factors")            # 정본 커넥터(C15) — 방향 = as-of IC 3단 부호(C13 Z_Score_Aligned)
RC_STANDING_ORIENT_CALLS <- c("align_factor_direction", "compute_rolling_ic_all")  # 엔진이 방향 · IC 를 스스로 다루는 층
RC_STANDING_SIGN_IDS <- c("ic_sign", "sign_ic", "ic_dir", "ic_direction", "flip_sign", "sign_flip", "negate_factors")   # 소문자 비교
RC_STANDING_W_TOL <- 1e-9          # 보유 비중 수치 허용오차(cell_eval.R rc_axis_audit 과 같은 크기)
RC_STANDING_MIN_BYTES <- 200L      # 엔진 파일 하한(검증기 rf_replication_verify.R 'engine_too_small' 과 같은 값)
RC_STANDING_MAX_FAILS <- 2L        # 인프라 실패 · 지문 불일치 재측정 횟수(round.sh measure 의 '1회 재측정'과 같은 뜻 — 2번째 실패면 사람이 본다)
RC_STANDING_SCAN_DEFAULT <- list(source = "lane_handoff", lane_root = "04_Research/strategies", dir_glob = "RP_AUTO_*",
                                 routed_program = "P1_RETURN", audit_admit = list("faithful", "adapted"),
                                 orientation_admit = list("engine_native"), long_leg_window = "visible",
                                 exclude_combination = TRUE, pit_static = TRUE)
## 레인 스캔 제외 사유(코드 → 뜻) — 스캔 · 규칙 문서(rc_standing_rules_md)가 이 한 곳을 쓴다. 성과 수치(등급 · PORT_t · CR)는 쓰지 않는다.
RC_STANDING_REASONS <- c(
  no_engine = "engine.R 없음 또는 200바이트 미만(검증기 하한)",
  no_handoff = "레인 인계 기록 없음 — 등록부 재료 큐 · 소비 기록 · 미분류 보류에 kind = engine 항목이 없다(구판 · 검증 미완)",
  not_routed = "인계 프로그램 ≠ 이 판의 프로그램(라우터 v5 분류 — 다른 엔진 재료 · 미분류)",
  combination = "결합(combination) — 단일 논문 엔진이 아니다(결합은 P4 · 도훈 확인)",
  audit_not_passed = "충실도 감사 판정이 허용 목록 밖(인계 기록 · fidelity_audit.json 둘 다 본다)",
  implementation_suspect = "구현 의심(재구현 뒤 감사 기각 · 측정 뒤 보유 대조 어긋남) — 꼬리표 판독 불가도 제외",
  engine_changed_since_handoff = "인계 뒤 엔진이 바뀌었다(인계 engine_md5 ≠ 지금 · md5 미기록이면 파일 시각 > 인계 시각 · 인계 시각 없음)",
  engine_parse_failed = "엔진 파싱 실패(정적 검사 불가)",
  output_contract_unknown = "FACTORS · PORTFOLIO 대입을 찾지 못했다",
  dynamic_sign = "동적 부호 — 방향 층이 허용 목록 밖(factor_db_asof = 정본 커넥터의 as-of IC 부호 · orientation_layer = 엔진이 부호 · IC 를 스스로 다룸)",
  long_leg_absent = "보는 창 신호일 중 롱 레그(비중 > 0)가 없는 날이 있다 — 시계열 방향 · 현금 타이밍 층(표준 구성이 그날 숏 대상을 사거나 비게 된다)",
  long_leg_unverifiable = "레인 측정 보유(04_holdings.csv)를 읽지 못해 롱 레그를 확인할 수 없다",
  pit_static = "PIT 정적 검사(lookahead_detector) 위반 또는 미스캔",
  paper_meta_missing = "논문 url · 제목 · 키를 정하지 못했다")
RC_STANDING_VIS_COLS <- c("engine", "code", "status", "t_alpha_vis", "alpha_ann_vis", "beta_vis", "port_t_vis", "n_vis", "uc_vis", "cagr_vis",
                          "dd_capture_median_vis", "dd_capture_worst_vis", "n_crisis_vis", "error")
.RCS <- new.env(parent = emptyenv())

## ── 작은 도구 ────────────────────────────────────────────────────────────────
.rcs_err <- function(...) stop(paste0("[round_core standing] ", ...), call. = FALSE)
.rcs_str <- function(x) { v <- unlist(x); if (!length(v)) return(NA_character_); v <- as.character(v[1]); if (is.na(v) || !nzchar(v)) NA_character_ else v }
.rcs_lgl <- function(x) { v <- unlist(x); if (!length(v) || !is.logical(v)) NA else v[1] }
.rcs_or <- function(a, b) if (length(a) == 1L && !is.na(a)) a else b
.rcs_md5s <- function(s) {   # 문자열(UTF-8 바이트)의 md5 — 원장 사슬
  b <- charToRaw(enc2utf8(as.character(s)))
  if (requireNamespace("openssl", quietly = TRUE)) { h <- as.character(openssl::md5(b)); attributes(h) <- NULL; return(h) }   # 'hash' 클래스 제거
  tf <- tempfile(); on.exit(unlink(tf), add = TRUE); writeBin(b, tf); rc_md5(tf)
}
.rcs_time <- function(s) { s <- .rcs_str(s); if (is.na(s)) return(as.POSIXct(NA)); suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z")) }
.rcs_same <- function(x, y) { x <- unlist(x); y <- unlist(y)
  if (is.numeric(x) && is.numeric(y)) length(x) == length(y) && isTRUE(all.equal(as.numeric(x), as.numeric(y))) else identical(as.character(x), as.character(y)) }
## 저장소 안 경로면 저장소 상대로(한글 경로를 깨는 정규화 함수 금지 — 구분자 치환 + 최상위 폴더 표식). 저장소 밖(임시 폴더)이면 그대로
.rcs_repo_rel <- function(p, root = rc_root()) {
  p <- gsub("\\\\", "/", p); r <- rc_rel(p, root)
  if (!grepl("^([A-Za-z]:|/)", r)) return(r)
  m <- regmatches(r, regexec("^.*?/(0[0-9]_[^/]+/.*)$", r, perl = TRUE))[[1]]
  if (length(m) == 2L && file.exists(file.path(root, m[2]))) m[2] else r
}
.rcs_fn_md5 <- function(f) .rcs_md5s(paste(deparse(utils::removeSource(f)), collapse = "\n"))

## ── 생성 함수 핀 — 칸 사양을 정하는 전부(함수 본문 · 선례 · 정본 고정 축) ─────────────────
rc_standing_generator_pin <- function(root = rc_root()) {
  g <- function(k) rc_ref_value(paste0("02_Infrastructure/worktask/constraint_defaults.json::", k), root)
  list(fn = "rc_p1_cell_spec", fn_md5 = .rcs_fn_md5(rc_p1_cell_spec), like = RC_P1_LIKE, like_md5 = rc_md5(rc_abs(RC_P1_LIKE, root)),
       canon = list(measurement_axis = g("measurement_axis.active"), max_names = g("tier_soft_deployment.max_names"),
                    cost_bps = g("tier_soft_deployment.transaction_cost_bps_one_way"),
                    liq_min = g("tier_soft_deployment.liquidity_min_won_20d_avg"), long_only = g("tier_soft_deployment.long_only")))
}
rc_standing_pin_diff <- function(a, b) {
  out <- character(0)
  for (k in c("fn", "fn_md5", "like", "like_md5")) if (!.rcs_same(a[[k]], b[[k]])) out <- c(out, k)
  ca <- a[["canon"]] %||% list(); cb <- b[["canon"]] %||% list()
  for (k in union(names(ca), names(cb))) if (!.rcs_same(ca[[k]], cb[[k]])) out <- c(out, paste0("canon.", k))
  out
}

## ── 사양 검사(상설 판) — 등록 전 standing-check 와 등록 뒤 맥락이 같은 함수를 쓴다 ──────────────
rc_standing_validate <- function(spec, root = rc_root(), check_pin = TRUE, check_files = TRUE) {
  if (!isTRUE(spec[["standing"]])) .rcs_err("standing: true 가 아니다")
  if (!identical(spec[["template"]], "p1_qualification")) .rcs_err("상설 판은 p1_qualification 템플릿만 지원한다")
  rc_spec_validate(spec, root = root, check_files = check_files)
  cfg <- spec[["standing_cfg"]]; if (!is.list(cfg)) .rcs_err("standing_cfg 없음")
  ed <- suppressWarnings(as.integer(cfg[["edition"]]))
  if (length(ed) != 1L || is.na(ed) || ed < 1L) .rcs_err("standing_cfg.edition 은 1 이상 정수")
  if (!identical(cfg[["program"]], spec[["program"]])) .rcs_err("standing_cfg.program ≠ program")
  if (!identical(cfg[["generator"]], "rc_p1_cell_spec")) .rcs_err("생성 함수는 rc_p1_cell_spec 만 지원한다")
  pin <- cfg[["generator_pin"]]
  if (!is.list(pin) || is.null(pin[["fn_md5"]]) || is.null(pin[["like_md5"]]) || !is.list(pin[["canon"]])) .rcs_err("standing_cfg.generator_pin 형식")
  sc <- cfg[["scan"]]; if (!is.list(sc)) .rcs_err("standing_cfg.scan 없음")
  for (k in c("source", "lane_root", "dir_glob", "routed_program", "long_leg_window"))
    if (!is.character(sc[[k]]) || length(sc[[k]]) != 1L || !nzchar(sc[[k]])) .rcs_err("scan.", k, " 없음")
  if (!identical(sc[["source"]], "lane_handoff")) .rcs_err("scan.source 는 lane_handoff 만")
  if (!identical(sc[["routed_program"]], spec[["program"]])) .rcs_err("scan.routed_program ≠ program")
  aa <- unlist(sc[["audit_admit"]]); if (!length(aa) || !all(aa %in% c("faithful", "adapted"))) .rcs_err("scan.audit_admit 은 faithful · adapted 의 부분집합(1개 이상)")
  oa <- unlist(sc[["orientation_admit"]]); if (!length(oa) || !all(oa %in% RC_STANDING_ORIENT)) .rcs_err("scan.orientation_admit 은 ", paste(RC_STANDING_ORIENT, collapse = "|"), " 의 부분집합")
  if (!identical(sc[["long_leg_window"]], "visible")) .rcs_err("scan.long_leg_window 는 visible(τ_D 이전)만 — 입구 규칙도 보는 창 정보만")
  if (!isTRUE(sc[["exclude_combination"]])) .rcs_err("결합 제외(exclude_combination)는 끌 수 없다")
  if (!is.logical(sc[["pit_static"]]) || length(sc[["pit_static"]]) != 1L) .rcs_err("scan.pit_static 은 논리값 1개")
  rj <- cfg[["rejudge_prior_editions"]]; if (!is.logical(rj) || length(rj) != 1L) .rcs_err("rejudge_prior_editions 는 논리값 1개")
  if (!identical(spec[["selection"]][["rule"]], "none")) .rcs_err("상설 판의 selection.rule 은 none(자격 목록 = P4 후보 · 선택 없음)")
  tw <- rc_rules_test_window_use(spec[["rules"]]); if (length(tw)) .rcs_err("판정 규칙이 시험 창 열을 쓴다(τ_D): ", paste(tw, collapse = ","))
  qr <- spec[["qualify_rule"]] %||% "qualify"
  if (!qr %in% vapply(spec[["rules"]], function(r) r[["id"]], character(1))) .rcs_err("자격 규칙 id 없음: ", qr)
  for (c in spec[["cells"]]) if (!identical(c[["role"]], "reference"))
    .rcs_err(c[["code"]], ": 시드 칸은 reference(같은 판본 재측정 · 시행 수 무가산)만 — 새 엔진은 스캔이 넣는다")
  if (check_pin) { d <- rc_standing_pin_diff(pin, rc_standing_generator_pin(root))
    if (length(d)) .rcs_err("generator_pin 이 지금 생성 함수와 다르다(", paste(d, collapse = " · "), ") — 사양을 다시 만든다") }
  invisible(TRUE)
}

## ── 판정 원장(추가 전용 jsonl · md5 사슬) ───────────────────────────────────
.rcs_read_lines <- function(path) {
  if (!file.exists(path)) return(list())
  L <- readLines(path, encoding = "UTF-8", warn = FALSE)
  lapply(L[nzchar(L)], function(s) fromJSON(s, simplifyVector = FALSE))
}
## 한 번 읽어 사슬 검사 · 해석을 같이 한다(검사 · 읽기 · 추가가 같은 판독을 쓴다)
.rcs_ledger_scan <- function(path) {
  if (!file.exists(path)) return(list(ok = TRUE, n = 0L, bad = integer(0), lines = character(0), recs = list()))
  L <- readLines(path, encoding = "UTF-8", warn = FALSE); bad <- integer(0); prev <- "genesis"; recs <- vector("list", length(L))
  for (i in seq_along(L)) {
    r <- tryCatch(fromJSON(L[i], simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(r) || !identical(r[["schema"]], RC_STANDING_LEDGER_SCHEMA) || !identical(r[["prev"]], prev)) bad <- c(bad, i)
    if (!is.null(r)) recs[[i]] <- r
    prev <- .rcs_md5s(L[i])
  }
  list(ok = !length(bad), n = length(L), bad = bad, lines = L, recs = recs)
}
rc_standing_ledger_verify <- function(path) .rcs_ledger_scan(path)[c("ok", "n", "bad")]
rc_standing_ledger_read <- function(path) {
  s <- .rcs_ledger_scan(path)
  if (!s$ok) .rcs_err("판정 원장 사슬이 끊겼다(추가 전용 위반 — 줄 ", paste(s$bad, collapse = ","), "): ", path)
  s$recs
}
## 추가 잠금 — 같은 원장에 두 프로세스(scan · standing-measure)가 동시에 쓰면 같은 앞 줄 md5 로 갈라져 사슬이 끊긴다.
##   잠금 = 디렉터리 생성(원자적). 추가는 1초 미만(바이너리 쓰기 1회)이라 대기 30초면 겹친 실행을 넘기고,
##   10분 넘은 잠금은 죽은 프로세스의 잔재로 보고 치운다(경고를 남긴다 · 추가 1회보다 수백 배 긴 시간).
RC_STANDING_LOCK_WAIT_S <- 30; RC_STANDING_LOCK_STALE_S <- 600
.rcs_lock <- function(path) {
  lk <- paste0(path, ".lock"); t0 <- Sys.time()
  repeat {
    if (dir.create(lk, showWarnings = FALSE)) return(lk)
    age <- as.numeric(difftime(Sys.time(), file.info(lk)$mtime, units = "secs"))
    if (is.finite(age) && age > RC_STANDING_LOCK_STALE_S) { warning("[round_core standing] 오래된 원장 잠금을 치운다: ", lk); unlink(lk, recursive = TRUE); next }
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > RC_STANDING_LOCK_WAIT_S) .rcs_err("원장 잠금 대기 초과(", RC_STANDING_LOCK_WAIT_S, "초): ", lk)
    Sys.sleep(0.2)
  }
}
## 한 줄 추가 — 공통 머리(스키마 · 시각 · 판 · 사전등록 md5 · 앞 줄 md5)를 붙인다. 바이너리 추가 1회(LF · UTF-8 바이트 그대로) · 잠금 안에서
rc_standing_append <- function(ctx, rec) {
  path <- ctx$ledger; dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lk <- .rcs_lock(path); on.exit(unlink(lk, recursive = TRUE), add = TRUE)
  s <- .rcs_ledger_scan(path); if (!s$ok) .rcs_err("판정 원장 사슬이 끊겼다 — 추가하지 않는다: ", path)
  full <- c(list(schema = RC_STANDING_LEDGER_SCHEMA, at = rc_now(), round_id = ctx$spec[["round_id"]], edition = ctx$cfg[["edition"]],
                 prereg_md5 = ctx$prereg_md5, prev = if (s$n) .rcs_md5s(s$lines[s$n]) else "genesis"), rec)
  js <- as.character(toJSON(full, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
  if (grepl("\n", js, fixed = TRUE)) .rcs_err("원장 줄에 줄바꿈이 있다")
  con <- file(path, open = "ab"); tryCatch(writeBin(charToRaw(paste0(enc2utf8(js), "\n")), con), finally = close(con))   # 잠금 풀기 전에 닫는다(버퍼 비움)
  invisible(full)
}
## 항목 상태 — enqueue 가 항목을 만들고 measure · verdict · reported · superfan 이 붙는다
rc_standing_items <- function(recs) {
  I <- list()
  for (r in recs) {
    ev <- .rcs_str(r[["event"]]); cd <- .rcs_str(r[["code"]])
    if (identical(ev, "enqueue")) { r[["measures"]] <- list(); r[["reported"]] <- character(0); r[["superfan"]] <- list(); r[["eval_fails"]] <- 0L; I[[cd]] <- r
    } else if (ev %in% c("measure", "verdict", "eval_failed") && !is.na(cd) && !is.null(I[[cd]])) {
      if (identical(ev, "measure")) I[[cd]][["measures"]] <- c(I[[cd]][["measures"]], list(r))
      else if (identical(ev, "eval_failed")) I[[cd]][["eval_fails"]] <- I[[cd]][["eval_fails"]] + 1L
      else I[[cd]][["verdict"]] <- r
    } else if (ev %in% c("reported", "superfan")) {
      for (c2 in as.character(unlist(r[["codes"]]))) if (!is.null(I[[c2]])) {
        if (identical(ev, "reported")) I[[c2]][["reported"]] <- c(I[[c2]][["reported"]], .rcs_str(r[["kind"]]))
        else I[[c2]][["superfan"]] <- c(I[[c2]][["superfan"]], list(r))
      }
    }
  }
  I
}
.rcs_meas_ok <- function(m) isTRUE(m[["ok"]]) && isTRUE(m[["fp_same"]])
.rcs_measured <- function(it) any(vapply(it[["measures"]], .rcs_meas_ok, logical(1)))
.rcs_r2_blocked <- function(it) { m <- it[["measures"]]; length(m) > 0L && length(m[[length(m)]][["r2"]]) > 0L }
.rcs_fails <- function(it) sum(vapply(it[["measures"]], function(m) !.rcs_meas_ok(m) && !length(m[["r2"]]) &&
                                        !identical(.rcs_str(m[["deferred"]]), "refresh_lock"), logical(1)))
.rcs_pending <- function(it) is.null(it[["verdict"]]) && is.null(it[["source_results"]]) && !.rcs_measured(it) && !.rcs_r2_blocked(it) &&
  .rcs_fails(it) < RC_STANDING_MAX_FAILS   # 측정 대기(공유 측정 시드 · R2 차단 · 실패 상한 제외)
.rcs_judgeable <- function(it) is.null(it[["verdict"]]) && (it[["eval_fails"]] %||% 0L) < RC_STANDING_MAX_FAILS &&
  (!is.null(it[["source_results"]]) || .rcs_measured(it))   # 칸 평가 예외는 판정이 아니다(재시도 · 상한 뒤 사람 확인)

## ── 맥락(등록 · R2 판 단위 검사) ─────────────────────────────────────────────
## 등록본의 사양을 쓴다(디스크 사양이 등록 뒤 바뀌면 멈춘다). mode = enqueue 면 더 높은 판이 등록됐을 때 새 항목을 거부한다
rc_standing_context <- function(round_dir, root = rc_root(), registry_path = NULL, mode = c("judge", "enqueue")) {
  mode <- match.arg(mode)
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root, check_files = FALSE)
  P <- rc_paths(round_dir, spec, root)
  pre <- rc_registered(spec, P, root, registry_path)
  rs <- pre[["spec"]]
  if (!isTRUE(rs[["standing"]])) .rcs_err("상설 판이 아니다(등록본 standing ≠ true): ", spec[["round_id"]])
  if (!identical(rc_md5(file.path(round_dir, "round_spec.json")), pre[["spec_md5"]])) .rcs_err("사양이 등록 뒤 바뀌었다(R2) — 바꿀 일은 새 판으로: ", spec[["round_id"]])
  rc_standing_validate(rs, root, check_pin = FALSE, check_files = FALSE)
  cfg <- rs[["standing_cfg"]]
  gd <- rc_standing_pin_diff(cfg[["generator_pin"]], rc_standing_generator_pin(root))
  if (length(gd)) .rcs_err("생성 함수 핀 ≠ 등록(R2: ", paste(gd, collapse = " · "), ") — 생성 함수 · 정본 고정 축이 바뀌면 새 판을 등록한다")
  mm <- rc_pins_mismatches(pre[["pins"]], root)
  if (length(mm)) .rcs_err("판정 경로 핀 불일치(R2) — 새 판 등록이 필요하다:\n", paste(mm, collapse = "\n"))
  if (identical(mode, "enqueue")) {
    E <- rc_standing_editions(rs[["program"]], root, registry_path)
    nw <- E[!is.na(edition) & edition > as.integer(cfg[["edition"]]) & round_id != rs[["round_id"]]]
    if (nrow(nw)) .rcs_err("더 높은 판이 등록됐다(", paste(nw$round_id, collapse = ","), ") — 옛 판은 새 항목을 받지 않는다(옛 판정은 유지)")
  }
  list(spec = rs, pre = pre, P = P, cfg = cfg, tau = as.Date(rs[["tau_d"]]), ledger = file.path(P$sa_dir, "standing_ledger.jsonl"),
       prereg_md5 = rc_md5(P$prereg), round_dir = round_dir, root = root, registry_path = registry_path, tag = rc_round_tag(rs[["round_id"]]))
}
## 등록된 상설 판 목록(등록부 라운드의 사전등록을 읽어 standing 판만)
rc_standing_editions <- function(program, root = rc_root(), registry_path = NULL) {
  R <- pr_get(pr_load(root, registry_path), program)[["rounds"]] %||% list()
  sar <- Sys.getenv("RC_SA_ROOT", root); out <- list()
  for (r in R) {
    rel <- .rcs_str(r[["prereg"]]); if (is.na(rel)) next
    f <- c(file.path(sar, rel), rc_abs(rel, root)); f <- f[file.exists(f)][1]; if (is.na(f)) next
    p <- tryCatch(rc_json_read(f), error = function(e) NULL)
    if (!isTRUE(p[["spec"]][["standing"]])) next
    out[[length(out) + 1L]] <- data.table(round_id = .rcs_str(r[["round_id"]]), status = .rcs_str(r[["status"]]),
                                          edition = suppressWarnings(as.integer(.rcs_str(p[["spec"]][["standing_cfg"]][["edition"]]))))
  }
  if (length(out)) rbindlist(out) else data.table(round_id = character(0), status = character(0), edition = integer(0))
}
## 상설 원장들에 이미 들어간 엔진(md5) — 판 사이 중복 판정을 막는다
rc_standing_known <- function(program, root = rc_root()) {
  sar <- Sys.getenv("RC_SA_ROOT", root)
  fs <- unique(c(Sys.glob(file.path(sar, "stage_artifacts/programs", program, "*", "standing_ledger.jsonl")),
                 Sys.glob(file.path(root, "stage_artifacts/programs", program, "*", "standing_ledger.jsonl"))))
  rows <- list()
  for (f in fs) for (r in .rcs_read_lines(f)) if (identical(r[["event"]], "enqueue"))
    rows[[length(rows) + 1L]] <- data.table(engine_md5 = .rcs_str(r[["engine_md5"]]), round_id = .rcs_str(r[["round_id"]]), code = .rcs_str(r[["code"]]))
  if (length(rows)) unique(rbindlist(rows)) else data.table(engine_md5 = character(0), round_id = character(0), code = character(0))
}

## ── 시행 회계(계보 = family_root) — P2R04 · P3R03 nf_prior 규칙 + 상설 원장 + 레인 측정 수 ─────────
rc_standing_nf_prior <- function(fam, root = rc_root()) {
  sar <- Sys.getenv("RC_SA_ROOT", root)
  pp <- unique(c(Sys.glob(file.path(root, "stage_artifacts/programs/*/*/prereg.json")), Sys.glob(file.path(sar, "stage_artifacts/programs/*/*/prereg.json"))))
  sa_of <- function(path) tryCatch(rc_json_read(rc_abs(path, root))[["selection_accounting"]], error = function(e) NULL)
  v <- integer(0)
  for (p in pp) {
    d <- tryCatch(rc_json_read(p), error = function(e) NULL)
    for (c in d[["cells"]] %||% list()) {
      if (!is.list(c)) next
      if (is.numeric(c[["n_family"]]) && !is.null(c[["path"]])) {            # 구판(rx_prereg_v1) — 칸 기록의 n_family
        if (identical(.rcs_str(sa_of(c[["path"]])[["family_root"]]), fam)) v <- c(v, as.integer(c[["n_family"]]))
      } else if (identical(c[["role"]], "variant") && !is.null(c[["spec"]])) {   # 코어 판 — 변형 칸 사양의 회계(reference · diagnostic 무가산)
        sa <- sa_of(c[["spec"]]); n <- suppressWarnings(as.integer(.rcs_str(sa[["n_family_at_registration"]])))
        if (identical(.rcs_str(sa[["family_root"]]), fam) && !is.na(n)) v <- c(v, n)
      }
    }
  }
  for (f in unique(Sys.glob(file.path(c(sar, root), "stage_artifacts/programs/*/*/standing_ledger.jsonl"))))
    for (r in .rcs_read_lines(f)) if (identical(r[["event"]], "enqueue") && identical(r[["role"]], "variant") && identical(.rcs_str(r[["family_root"]]), fam))
      v <- c(v, as.integer(r[["n_family"]]))
  if (length(v)) max(v) else 0L
}
## 레인 측정 수 = 대표 + 변형(REPLICATION-ALL-METHODS-20261017 · variants_summary.json n_variants) — 없으면 대표 1
rc_standing_lane_n <- function(artifacts) {
  a <- .rcs_str(artifacts); if (is.na(a)) return(1L)
  f <- file.path(a, "variants_summary.json"); if (!file.exists(f)) return(1L)
  n <- suppressWarnings(as.integer(.rcs_str(tryCatch(rc_json_read(f)[["n_variants"]], error = function(e) NA))))
  if (!is.na(n) && n >= 1L) n else 1L
}

## ── 레인 스캔: 엔진 정적 검사 · PIT · 롱 레그 · 논문 · 인계 기록 ───────────────────────
## 정적 검사 — R 파서 토큰으로(주석 · 문자열은 보지 않는다): 산출 대입(FACTORS · PORTFOLIO) · 방향 층 분류
rc_standing_static <- function(path) {
  bad <- function(e) list(ok = FALSE, error = e, outputs = character(0), orientation = NA_character_, factor_db = character(0), orientation_tokens = character(0), lines = integer(0))
  ex <- tryCatch(parse(file = path, keep.source = TRUE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(ex, "error")) return(bad(conditionMessage(ex)))
  pd <- utils::getParseData(ex)
  if (is.null(pd) || !nrow(pd)) return(bad("파싱 자료 없음"))
  pd <- pd[pd$terminal, c("line1", "col1", "token", "text")]; pd <- pd[order(pd$line1, pd$col1), , drop = FALSE]
  tok <- pd$token; txt <- pd$text; n <- nrow(pd)
  nx <- c(tok[-1L], NA_character_); pv <- c(NA_character_, tok[-n])
  is_sym <- tok %in% c("SYMBOL", "SYMBOL_SUB", "SYMBOL_FUNCTION_CALL")
  outs <- txt[tok == "SYMBOL" & txt %in% c("FACTORS", "PORTFOLIO") & (nx %in% c("LEFT_ASSIGN", "EQ_ASSIGN") | pv %in% "RIGHT_ASSIGN")]
  for (i in which(tok == "SYMBOL_FUNCTION_CALL" & txt == "assign")) if (i + 2L <= n && tok[i + 2L] == "STR_CONST") {
    v <- gsub("^[\"']|[\"']$", "", txt[i + 2L]); if (v %in% c("FACTORS", "PORTFOLIO")) outs <- c(outs, v) }
  calls <- txt[tok == "SYMBOL_FUNCTION_CALL"]
  fdb <- intersect(RC_STANDING_FDB_CALLS, calls)
  orl <- unique(c(intersect(RC_STANDING_ORIENT_CALLS, calls), txt[is_sym & tolower(txt) %in% RC_STANDING_SIGN_IDS]))
  list(ok = TRUE, error = NA_character_, outputs = sort(unique(outs)),
       orientation = if (length(orl)) "orientation_layer" else if (length(fdb)) "factor_db_asof" else "engine_native",
       factor_db = fdb, orientation_tokens = orl, lines = sort(unique(pd$line1[is_sym & txt %in% c(fdb, orl)])))
}
## PIT 정적 검사 — 레인 사전 점검과 같은 함수(detect_lookahead) · 격리 환경에 한 번 적재
rc_standing_pit <- function(path, root = rc_root()) {
  if (is.null(.RCS$la)) { e <- new.env(parent = globalenv()); sys.source(file.path(root, "02_Infrastructure/validation/lookahead_detector.R"), envir = e); .RCS$la <- e$detect_lookahead }
  r <- tryCatch(.RCS$la(path, verbose = FALSE), error = function(e) list(clean = NA, violations = list(), error = conditionMessage(e)))
  ck <- vapply(r$violations %||% list(), function(v) as.character(v$check %||% "?")[1], character(1))
  list(clean = r$clean, checks = unique(ck), error = .rcs_str(r$error))
}
## 롱 레그 — 레인 측정 보유의 보는 창(≤ τ_D) 신호일마다 비중 > 0 종목이 있는가(시계열 방향 · 현금 타이밍 층 탐지 · 필요한 두 열만 읽는다)
rc_standing_long_leg <- function(artifacts, tau) {
  a <- .rcs_str(artifacts); f <- if (is.na(a)) NA_character_ else file.path(a, "04_holdings.csv")
  if (is.na(f) || !file.exists(f)) return(list(ok = NA, why = "holdings_missing", n_dates = 0L, n_absent = NA_integer_))
  hdr <- names(fread(f, nrows = 0L, showProgress = FALSE)); wc <- intersect(c("target_weight", "actual_weight"), hdr)[1]
  if (is.na(wc) || !"date" %in% hdr) return(list(ok = NA, why = "holdings_columns", n_dates = 0L, n_absent = NA_integer_))
  H <- fread(f, select = c("date", wc), showProgress = FALSE); setnames(H, c("d", "w"))
  H[, d := as.integer(as.IDate(d))][, w := as.numeric(w)]
  H <- H[d <= as.integer(as.IDate(tau))]
  if (!nrow(H)) return(list(ok = NA, why = "no_visible_dates", n_dates = 0L, n_absent = NA_integer_))
  Pd <- H[, .(np = sum(w > RC_STANDING_W_TOL, na.rm = TRUE), nn = sum(w < -RC_STANDING_W_TOL, na.rm = TRUE)), by = d]
  ab <- Pd[np == 0L]
  list(ok = !nrow(ab), why = if (nrow(ab)) "absent" else "ok", n_dates = nrow(Pd), n_absent = nrow(ab), n_short_only = sum(ab$nn > 0L))
}
## 논문 메타 — 인계 기록 → lane_provenance → FIDELITY → 측정 산출물 → arXiv 키 유도 순(출처를 남긴다)
rc_standing_paper <- function(d, h) {
  rj <- function(f) tryCatch(rc_json_read(f), error = function(e) NULL)
  lp <- rj(file.path(d, "lane_provenance.json")); fj <- rj(file.path(d, "FIDELITY.json"))
  ar <- if (!is.na(.rcs_str(h$artifacts))) rj(file.path(h$artifacts, "authoritative_remeasure.json")) else NULL
  sf <- fj[["source_paper"]] %||% fj[["paper"]]; if (!is.list(sf)) sf <- list()
  sa <- ar[["replication"]][["source_paper"]]; if (!is.list(sa)) sa <- list()
  key <- .rcs_or(.rcs_str(h$paper_key), .rcs_or(.rcs_str(lp[["paper_key"]]), .rcs_or(.rcs_str(sf[["paper_key"]]), .rcs_str(sa[["paper_key"]]))))
  title <- .rcs_or(.rcs_str(h$title), .rcs_or(.rcs_str(sf[["title"]]), .rcs_str(sa[["title"]])))
  cand <- c(lane_provenance = .rcs_str(lp[["paper_url"]]), fidelity = .rcs_str(sf[["url"]]), artifacts = .rcs_str(sa[["url"]]))
  cand <- cand[!is.na(cand)]
  url <- if (length(cand)) unname(cand[1]) else NA_character_; src <- if (length(cand)) names(cand)[1] else NA_character_
  if (is.na(url) && !is.na(key) && grepl("^[0-9]{4}\\.[0-9]{4,5}$", key)) { url <- paste0("https://arxiv.org/abs/", key); src <- "arxiv_key" }
  list(ok = !is.na(key) && !is.na(title) && !is.na(url), url = url, title = title, paper_key = key, url_source = src)
}
## 레인 인계 기록 — 등록부 프로그램 재료 큐 · 소비 기록 · 미분류 보류의 kind = engine 항목(검증기 .v1001_handoff 가 쓴다)
rc_standing_handoffs <- function(reg) {
  one <- function(it, prog, where) {
    if (!identical(.rcs_str(it[["kind"]]), "engine")) return(NULL)
    ep <- gsub("\\\\", "/", .rcs_str(it[["engine_path"]]))
    data.table(program = prog, where = where, ho_key = .rcs_str(it[["key"]]), base_id = .rcs_str(it[["base_id"]]),   # key = data.table 예약 인자
               dir = if (is.na(ep)) NA_character_ else basename(dirname(ep)), at = .rcs_str(it[["enqueued_at"]] %||% it[["held_at"]]),
               title = .rcs_str(it[["title"]]), paper_key = .rcs_str(it[["paper_key"]]), fidelity = .rcs_str(it[["fidelity"]]),
               audit_verdict = .rcs_str(it[["audit_verdict"]]), implementation_suspect = .rcs_lgl(it[["implementation_suspect"]]),
               holdings_claim_mismatch = .rcs_lgl(it[["holdings_claim_mismatch"]]), has_short = .rcs_lgl(it[["has_short"]]),
               artifacts = gsub("\\\\", "/", .rcs_str(it[["artifacts"]])), engine_md5 = .rcs_str(it[["engine_md5"]]))
  }
  rows <- list()
  for (p in reg[["programs"]] %||% list()) for (w in c("queue", "consumed")) for (it in p[[w]] %||% list()) rows[[length(rows) + 1L]] <- one(it, .rcs_str(p[["id"]]), w)
  for (it in reg[["paper_routing"]][["unrouted"]] %||% list()) rows[[length(rows) + 1L]] <- one(it, NA_character_, "unrouted")
  rows <- Filter(Negate(is.null), rows)
  if (length(rows)) rbindlist(rows, fill = TRUE) else
    data.table(program = character(0), where = character(0), ho_key = character(0), base_id = character(0), dir = character(0), at = character(0))
}
## 디렉터리 1개 판독 — 모든 실패 사유를 모은다(첫 사유에서 멈추지 않는다)
.rcs_scan_dir <- function(d, H, sc, root, tau) {
  nm <- basename(d); ep <- file.path(d, "engine.R"); rs <- character(0)
  has_eng <- file.exists(ep) && isTRUE(file.info(ep)$size >= RC_STANDING_MIN_BYTES)
  if (!has_eng) rs <- c(rs, "no_engine")
  h <- if (nrow(H)) H[H$dir %in% nm] else H
  if (nrow(h)) h <- h[order(h$at, decreasing = TRUE, na.last = TRUE)][1]
  hv <- function(k) if (nrow(h) && k %in% names(h)) h[[k]][1] else NA
  fj <- tryCatch(rc_json_read(file.path(d, "FIDELITY.json")), error = function(e) NULL)
  fa <- tryCatch(rc_json_read(file.path(d, "fidelity_audit.json")), error = function(e) NULL)
  fid <- .rcs_or(.rcs_str(hv("fidelity")), .rcs_str(fj[["fidelity"]])); afile <- .rcs_str(fa[["verdict"]]); aitem <- .rcs_str(hv("audit_verdict"))
  if (identical(fid, "combination") || identical(.rcs_str(fj[["fidelity"]]), "combination") || grepl("COMBO", nm, fixed = TRUE) ||
      grepl("^combo:", .rcs_or(.rcs_str(hv("paper_key")), ""))) rs <- c(rs, "combination")
  if (!nrow(h)) rs <- c(rs, "no_handoff") else {
    if (!identical(.rcs_str(hv("program")), sc[["routed_program"]])) rs <- c(rs, "not_routed")
    adm <- unlist(sc[["audit_admit"]])
    if (!(aitem %in% adm) || !(afile %in% adm)) rs <- c(rs, "audit_not_passed")
    if (!identical(hv("implementation_suspect"), FALSE) || isTRUE(hv("holdings_claim_mismatch"))) rs <- c(rs, "implementation_suspect")
  }
  emd5 <- if (has_eng) rc_md5(ep) else NA_character_
  if (has_eng && nrow(h)) {
    chg <- if (!is.na(.rcs_str(hv("engine_md5")))) !identical(emd5, .rcs_str(hv("engine_md5"))) else {
      ht <- .rcs_time(hv("at")); mt <- file.info(ep)$mtime; is.na(ht) || is.na(mt) || mt > ht }
    if (isTRUE(chg)) rs <- c(rs, "engine_changed_since_handoff")
  }
  st <- if (has_eng) rc_standing_static(ep) else NULL
  if (has_eng) {
    if (!isTRUE(st$ok)) rs <- c(rs, "engine_parse_failed") else {
      if (!length(st$outputs)) rs <- c(rs, "output_contract_unknown")
      if (!(st$orientation %in% unlist(sc[["orientation_admit"]]))) rs <- c(rs, "dynamic_sign")
    }
  }
  ll <- if (nrow(h)) rc_standing_long_leg(hv("artifacts"), tau) else list(ok = NA, why = "no_handoff", n_dates = 0L, n_absent = NA_integer_)
  if (nrow(h)) { if (isFALSE(ll$ok)) rs <- c(rs, "long_leg_absent") else if (is.na(ll$ok)) rs <- c(rs, "long_leg_unverifiable") }
  pit <- if (has_eng && isTRUE(sc[["pit_static"]])) rc_standing_pit(ep, root) else list(clean = NA, checks = character(0), error = NA_character_)
  if (has_eng && isTRUE(sc[["pit_static"]]) && !isTRUE(pit$clean)) rs <- c(rs, "pit_static")
  pa <- if (nrow(h)) rc_standing_paper(d, h) else list(ok = FALSE, url = NA_character_, title = NA_character_, paper_key = NA_character_, url_source = NA_character_)
  if (nrow(h) && !isTRUE(pa$ok)) rs <- c(rs, "paper_meta_missing")
  data.table(dir = nm, engine = rc_rel(ep, root), engine_md5 = emd5, base_id = .rcs_str(hv("base_id")), program = .rcs_str(hv("program")),
             where = .rcs_str(hv("where")), at = .rcs_str(hv("at")), eligible = !length(rs), reasons = paste(unique(rs), collapse = ";"),
             orientation = if (is.null(st)) NA_character_ else st$orientation,
             orientation_evidence = if (is.null(st)) NA_character_ else paste(c(st$factor_db, st$orientation_tokens), collapse = ","),
             outputs = if (is.null(st)) NA_character_ else paste(st$outputs, collapse = ","),
             long_leg = if (is.na(ll$n_absent)) ll$why else sprintf("%d/%d", ll$n_absent, ll$n_dates),
             pit = if (isTRUE(pit$clean)) "clean" else if (isFALSE(pit$clean)) paste(pit$checks, collapse = ",") else "unscanned",
             paper_key = pa$paper_key, title = pa$title, url = pa$url, url_source = pa$url_source,
             fidelity = fid, audit_item = aitem, audit_file = afile, has_short = hv("has_short"), artifacts = .rcs_str(hv("artifacts")))
}
## 레인 산출 전체 판독 — 디렉터리마다 1행(입구 통과 = eligible · 아니면 reasons). 성과 수치는 읽지 않는다(등급 · PORT_t · CR)
rc_standing_lane_candidates <- function(sc, root = rc_root(), registry_path = NULL, tau = "2022-12-31", lane_root = NULL) {
  lr <- lane_root %||% rc_abs(sc[["lane_root"]], root)
  dirs <- sort(Sys.glob(file.path(lr, sc[["dir_glob"]] %||% "RP_AUTO_*"))); dirs <- dirs[dir.exists(dirs)]
  H <- rc_standing_handoffs(pr_load(root, registry_path))
  if (!length(dirs)) return(data.table(dir = character(0), eligible = logical(0), reasons = character(0), engine_md5 = character(0), at = character(0)))
  rbindlist(lapply(dirs, .rcs_scan_dir, H = H, sc = sc, root = root, tau = tau), fill = TRUE)
}

## ── 항목 넣기 · R2 대조 ─────────────────────────────────────────────────────
## 엔진 1개 → 칸 사양(등록 생성 함수 · 재량 없음) + 원장 enqueue. 같은 엔진(md5)은 이 판에서 한 번, 옛 판에 있으면 넣지 않는다(rejudge 판 제외)
rc_standing_enqueue <- function(engine_path, paper, family_root, round_dir, handoff = list(), tags = list(), source = c("scan", "manual"),
                                engine_label = NULL, root = rc_root(), registry_path = NULL, ctx = NULL) {
  source <- match.arg(source)
  ctx <- ctx %||% rc_standing_context(round_dir, root, registry_path, mode = "enqueue"); root <- ctx$root
  ep_rel <- .rcs_repo_rel(engine_path, root); ep <- rc_abs(ep_rel, root)
  if (!file.exists(ep)) .rcs_err("엔진 파일 없음: ", engine_path)
  pp <- list(url = .rcs_str(paper[["url"]]), title = .rcs_str(paper[["title"]]), paper_key = .rcs_str(paper[["paper_key"]]))
  if (anyNA(unlist(pp))) .rcs_err("paper 의 url · title · paper_key 가 모두 있어야 한다")
  fam <- .rcs_str(family_root); if (is.na(fam)) .rcs_err("family_root 없음")
  emd5 <- rc_md5(ep)
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))
  dup <- Filter(function(it) identical(.rcs_str(it[["engine_md5"]]), emd5), I)
  if (length(dup)) return(invisible(list(code = dup[[1]][["code"]], status = "duplicate")))
  if (!isTRUE(ctx$cfg[["rejudge_prior_editions"]])) {
    K <- rc_standing_known(ctx$spec[["program"]], root); K <- K[engine_md5 == emd5 & round_id != ctx$spec[["round_id"]]]
    if (nrow(K)) return(invisible(list(code = K$code[1], status = paste0("known:", K$round_id[1]))))
  }
  code <- sprintf("%s_%s_%s", ctx$tag, gsub("[^A-Za-z0-9]+", "_", pp$paper_key), substr(emd5, 1L, 6L))
  if (!is.null(I[[code]])) .rcs_err("항목 code 충돌: ", code)
  lane_n <- rc_standing_lane_n(handoff[["artifacts"]]); nf0 <- rc_standing_nf_prior(fam, root)
  nf <- as.integer(max(nf0, lane_n) + 1L)
  basis <- sprintf("%s 상설 자격(판 %s): 계보 %s 의 앞선 사전등록 · 상설 원장 회계 최댓값 %d 와 레인 측정 %d(대표 + 변형) 중 큰 값 + 이 칸 1",
                   ctx$tag, ctx$cfg[["edition"]], fam, nf0, lane_n)
  cs <- rc_p1_cell_spec(code, ep, pp, fam, nf, basis, root = root)
  sp <- file.path(ctx$round_dir, "specs", paste0(code, ".json"))
  if (file.exists(sp)) .rcs_err("칸 사양이 이미 있다 — 덮어쓰지 않는다: ", sp)
  rc_json_write(cs, sp)
  rc_standing_append(ctx, list(event = "enqueue", code = code, engine = engine_label %||% sub(paste0("^", ctx$tag, "_"), "", code), role = "variant",
                               source = source, engine_path = ep_rel, engine_md5 = emd5, cell_spec = rc_rel(sp, root), cell_spec_md5 = rc_md5(sp),
                               paper = pp, family_root = fam, n_family = nf, n_trials_basis = basis, nf_prior = nf0, lane_n = lane_n,
                               generator_md5 = ctx$cfg[["generator_pin"]][["fn_md5"]], handoff = handoff, tags = tags))
  invisible(list(code = code, status = "enqueued", spec = sp))
}
## 시드(등록본 칸 · reference) — 원장에 없으면 넣는다(사양 · md5 = 등록본 그대로)
.rcs_enqueue_seeds <- function(ctx, I) {
  out <- character(0)
  for (c in ctx$pre[["cells"]]) {
    if (!is.null(I[[c[["code"]]]])) next
    ep <- NA_character_; emd5 <- NA_character_; pp <- NULL; fam <- NA_character_; nf <- NA_integer_
    if (!is.null(c[["spec"]])) {
      cs <- rc_json_read(rc_abs(c[["spec"]], ctx$root)); p <- .rcs_str(cs[["base_signal"]][["path"]])
      if (!is.na(p)) { ep <- .rcs_repo_rel(p, ctx$root); emd5 <- rc_md5(rc_abs(ep, ctx$root)) }
      pp <- cs[["root_paper"]]; fam <- .rcs_str(cs[["selection_accounting"]][["family_root"]])
      nf <- suppressWarnings(as.integer(.rcs_str(cs[["selection_accounting"]][["n_family_at_registration"]])))
    }
    rc_standing_append(ctx, c(list(event = "enqueue", code = c[["code"]], engine = c[["engine"]], role = c[["role"]] %||% "reference", source = "seed",
                                   engine_path = ep, engine_md5 = emd5, paper = pp, family_root = fam, n_family = nf),
                              if (!is.null(c[["spec"]])) list(cell_spec = c[["spec"]], cell_spec_md5 = c[["md5"]]) else list(source_results = c[["source_results"]])))
    out <- c(out, c[["code"]])
  }
  out
}
## 등록된 생성 함수로 칸 사양을 다시 만들어 md5(쓰는 형식 그대로 — rc_json_write)
rc_standing_regen_md5 <- function(it, ctx) {
  cs <- rc_p1_cell_spec(it[["code"]], rc_abs(it[["engine_path"]], ctx$root), it[["paper"]], it[["family_root"]],
                        as.integer(it[["n_family"]]), it[["n_trials_basis"]], root = ctx$root)
  tf <- tempfile(fileext = ".json"); on.exit(unlink(tf), add = TRUE); rc_json_write(cs, tf); rc_md5(tf)
}
## 항목 R2 — 엔진 md5 · 칸 사양 md5 = 원장(넣을 때) · 시드는 등록본 칸 md5 · 스캔 항목은 다시 만든 사양 md5
rc_standing_item_check <- function(it, ctx) {
  root <- ctx$root; bad <- character(0)
  if (!is.na(.rcs_str(it[["engine_path"]]))) {
    ep <- rc_abs(it[["engine_path"]], root)
    if (!file.exists(ep) || !identical(rc_md5(ep), .rcs_str(it[["engine_md5"]]))) bad <- c(bad, "engine_md5_changed")
  }
  if (!is.null(it[["cell_spec"]])) {
    sp <- rc_abs(it[["cell_spec"]], root)
    if (!file.exists(sp) || !identical(rc_md5(sp), .rcs_str(it[["cell_spec_md5"]]))) bad <- c(bad, "cell_spec_md5_changed")
  }
  if (identical(it[["source"]], "seed")) {
    pc <- Filter(function(c) identical(c[["code"]], it[["code"]]), ctx$pre[["cells"]])
    if (!length(pc)) bad <- c(bad, "seed_not_in_prereg")
    else if (!is.null(it[["cell_spec"]]) && !identical(.rcs_str(pc[[1]][["md5"]]), .rcs_str(it[["cell_spec_md5"]]))) bad <- c(bad, "seed_md5_not_prereg")
  } else if (!length(bad)) {
    rg <- tryCatch(rc_standing_regen_md5(it, ctx), error = function(e) NA_character_)
    if (!identical(rg, .rcs_str(it[["cell_spec_md5"]]))) bad <- c(bad, "cell_spec_not_regenerable")
  }
  bad
}

## ── 스캔(레인 산출 → 자격 큐) ──────────────────────────────────────────────
## dry_run = 등록 전에도 판독만(쓰기 없음) · 아니면 등록 R2 를 본 뒤 시드 + 입구 통과 새 엔진을 넣는다(인계 시각 순 · max_new 상한)
rc_standing_scan <- function(round_dir, root = rc_root(), registry_path = NULL, dry_run = FALSE, lane_root = NULL, max_new = NULL, out = NULL) {
  if (dry_run) {
    S <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root, check_files = FALSE)
    rc_standing_validate(S, root, check_pin = FALSE, check_files = FALSE); ctx <- NULL
  } else { ctx <- rc_standing_context(round_dir, root, registry_path, mode = "enqueue"); S <- ctx$spec }
  cfg <- S[["standing_cfg"]]
  t0 <- Sys.time()
  C <- rc_standing_lane_candidates(cfg[["scan"]], root, registry_path, S[["tau_d"]], lane_root)
  K <- rc_standing_known(S[["program"]], root)
  if (isTRUE(cfg[["rejudge_prior_editions"]])) K <- K[round_id == S[["round_id"]]]
  C[, status := ifelse(!eligible, "excluded", ifelse(engine_md5 %in% K$engine_md5, "known", "new"))]
  enq <- character(0)
  if (!dry_run) {
    enq <- .rcs_enqueue_seeds(ctx, rc_standing_items(rc_standing_ledger_read(ctx$ledger)))
    nw <- C[status == "new"][order(at, na.last = TRUE)]
    if (!is.null(max_new)) nw <- head(nw, as.integer(max_new))
    for (i in seq_len(nrow(nw))) {
      r <- nw[i]
      x <- rc_standing_enqueue(rc_abs(r$engine, root), list(url = r$url, title = r$title, paper_key = r$paper_key), r$paper_key, round_dir,
                               handoff = list(base_id = r$base_id, program = r$program, where = r$where, at = r$at, artifacts = r$artifacts,
                                              audit_item = r$audit_item, audit_file = r$audit_file, fidelity = r$fidelity, has_short = r$has_short),
                               tags = list(orientation = r$orientation, outputs = r$outputs, long_leg = r$long_leg, url_source = r$url_source),
                               source = "scan", root = root, registry_path = registry_path, ctx = ctx)
      if (identical(x$status, "enqueued")) enq <- c(enq, x$code)
    }
    rc_standing_append(ctx, list(event = "scan", n_dirs = nrow(C), n_eligible = sum(C$eligible), n_new = nrow(nw), enqueued = as.list(enq),
                                 excluded = as.list(table(unlist(strsplit(C[eligible == FALSE]$reasons, ";", fixed = TRUE))))))
    rc_perf_log(S[["round_id"]], "standing_scan", difftime(Sys.time(), t0, units = "secs"), list(n_dirs = nrow(C), n_enqueued = length(enq)), root = root)
  }
  if (!is.null(out)) rc_json_write(list(schema = "rc_standing_scan_v1", round_id = S[["round_id"]], at = rc_now(), dry_run = dry_run,
                                        reasons = as.list(RC_STANDING_REASONS), table = C), out)
  invisible(list(table = C, enqueued = enq))
}

## ── 측정(항목 1개 · 정본 셀 워커) ────────────────────────────────────────────
rc_standing_pending <- function(round_dir, root = rc_root(), registry_path = NULL) {
  ctx <- rc_standing_context(round_dir, root, registry_path)
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))
  names(I)[vapply(I, .rcs_pending, logical(1))]
}
rc_standing_fingerprint <- function() paste(suppressWarnings(system2("bash", c(shQuote(file.path(RC_DIR, "fingerprint.sh")), "equality"),
                                                                    stdout = TRUE, stderr = FALSE)), collapse = "\n")
rc_standing_measure_item <- function(round_dir, code, root = rc_root(), registry_path = NULL,
                                     worker = file.path(root, "02_Infrastructure/ops/rf_cell_worker.R"), fingerprint = rc_standing_fingerprint) {
  ctx <- rc_standing_context(round_dir, root, registry_path)
  it <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))[[code]]
  if (is.null(it)) .rcs_err("상설 원장에 그런 항목이 없다: ", code)
  if (!is.null(it[["source_results"]])) .rcs_err("공유 측정 항목 — 측정하지 않는다: ", code)
  if (!is.null(it[["verdict"]])) .rcs_err("이미 판정한 항목 — 다시 재지 않는다(판정 유지): ", code)
  if (.rcs_measured(it)) return(invisible(list(code = code, status = "already")))
  bad <- rc_standing_item_check(it, ctx)
  if (length(bad)) { rc_standing_append(ctx, list(event = "measure", code = code, ok = FALSE, r2 = as.list(bad)))
                     .rcs_err("R2 대조 실패 — 측정하지 않는다(", code, "): ", paste(bad, collapse = ",")) }
  dir.create(ctx$P$results, recursive = TRUE, showWarnings = FALSE)
  res <- file.path(ctx$P$results, paste0(code, ".json")); unlink(res)   # 원장에 ok 측정이 없으면 디스크 결과는 잔재다
  role <- it[["role"]] %||% "variant"; ev <- c("QVEST_RP_REGISTER", "QVEST_RP_NO_FACTOR_ANALYSIS"); old <- Sys.getenv(ev, unset = NA)
  on.exit({ for (k in ev) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)) }, add = TRUE)
  if (!identical(role, "variant")) Sys.setenv(QVEST_RP_REGISTER = "0", QVEST_RP_NO_FACTOR_ANALYSIS = "1")
  fp0 <- tryCatch(fingerprint(), error = function(e) ""); t0 <- Sys.time()
  rc <- system2("Rscript", c(shQuote(worker), shQuote(rc_abs(it[["cell_spec"]], root)), "1", code, shQuote(res)),
                stdout = file.path(ctx$P$results, paste0(code, ".log")), stderr = file.path(ctx$P$results, paste0(code, ".err.log")))
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs")); fp1 <- tryCatch(fingerprint(), error = function(e) "")
  r <- tryCatch(rc_json_read(res), error = function(e) list(ok = FALSE))
  rec <- list(event = "measure", code = code, ok = isTRUE(r[["ok"]]), rc = as.integer(rc), deferred = .rcs_str(r[["deferred"]]), seconds = round(sec, 1),
              artifacts = .rcs_str(r[["artifacts"]]), result_md5 = if (file.exists(res)) rc_md5(res) else NA_character_,
              fp_same = nzchar(fp0) && identical(fp0, fp1), engine_md5 = it[["engine_md5"]], cell_spec_md5 = it[["cell_spec_md5"]])
  rc_perf_log(ctx$spec[["round_id"]], "standing_measure", sec, list(code = code, ok = rec$ok, fp_same = rec$fp_same), root = root)
  rc_standing_append(ctx, rec)
  cat(sprintf("[상설] 측정 %s ok=%s · 지문 동일=%s · %.1f분\n", code, rec$ok, rec$fp_same, sec / 60))
  invisible(rec)
}

## ── 판정(칸 평가 → 등록 규칙 기계 적용 → 원장 · 판정 파일) ──────────────────────────────
rc_standing_judge <- function(round_dir, root = rc_root(), registry_path = NULL, eval_fun = rc_eval_cell) {
  ctx <- rc_standing_context(round_dir, root, registry_path); t0 <- Sys.time()
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))
  todo <- Filter(.rcs_judgeable, I); if (!length(todo)) return(invisible(list(judged = character(0))))
  ok <- list()
  for (it in todo) {
    bad <- rc_standing_item_check(it, ctx)
    if (length(bad)) rc_standing_append(ctx, list(event = "verdict", code = it[["code"]], engine = it[["engine"]], status = "r2_violation", qualify = NA, r2 = as.list(bad)))
    else ok[[it[["code"]]]] <- it
  }
  if (!length(ok)) return(invisible(list(judged = character(0))))
  need <- Filter(function(it) is.null(it[["source_results"]]), ok)
  if (length(need)) {
    env <- rc_eval_env(root, ctx$spec[["behavior_card_cfg"]])
    for (it in need) {
      t1 <- Sys.time()
      ev <- rc_safe(eval_fun, root, ctx$round_dir, list(code = it[["code"]], engine = it[["engine"]], role = it[["role"]], spec = it[["cell_spec"]]),
                    env, ctx$tau, what = it[["code"]])
      rc_perf_log(ctx$spec[["round_id"]], "standing_eval_cell", difftime(Sys.time(), t1, units = "secs"), list(code = it[["code"]], ok = ev$ok), root = root)
      if (!isTRUE(ev$ok)) { rc_standing_append(ctx, list(event = "eval_failed", code = it[["code"]], error = .rcs_str(ev$error)))
                            ok[[it[["code"]]]] <- NULL }   # 판정을 남기지 않는다 — 다음 judge 가 다시 평가(상한 RC_STANDING_MAX_FAILS)
    }
    if (!length(ok)) return(invisible(list(judged = character(0))))
  }
  ps <- ctx$spec
  ps[["cells"]] <- unname(lapply(ok, function(it) c(list(code = it[["code"]], engine = it[["engine"]], role = it[["role"]] %||% "variant"),
                                                    if (!is.null(it[["source_results"]])) list(source_results = it[["source_results"]]) else list(spec = it[["cell_spec"]]))))
  ps[[".path"]] <- file.path(ctx$round_dir, "round_spec.json")
  rules <- ctx$pre[["rules_resolved"]]; qr <- ctx$spec[["qualify_rule"]] %||% "qualify"
  tw <- rc_rules_test_window_use(rules); if (length(tw)) .rcs_err("판정 규칙이 시험 창 열을 쓴다(τ_D): ", paste(tw, collapse = ","))
  T <- rc_p1_table(ps, root)
  evs <- lapply(ok, function(it) { src <- rc_abs(it[["source_results"]] %||% file.path(ctx$round_dir, "results"), root)
                                   tryCatch(rc_json_read(file.path(src, it[["code"]], "eval.json")), error = function(e) NULL) })
  X <- rbindlist(lapply(names(ok), function(cd) { m <- if (is.null(evs[[cd]])) list() else rc_metric_from_eval(evs[[cd]])
    data.table(code = cd, dd_capture_median_vis = m[["dd_capture_median_vis"]] %||% NA_real_,
               dd_capture_worst_vis = m[["dd_capture_worst_vis"]] %||% NA_real_, n_crisis_vis = m[["n_crisis_vis"]] %||% NA_real_) }))
  T <- merge(T, X, by = "code", all.x = TRUE, sort = FALSE)
  T <- rc_rules_apply(rules, T, eligible = T$status == "evaluated")
  sent <- as.list(rc_rules_sentences(rules)); vd <- file.path(ctx$P$results, "standing"); dir.create(vd, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(T))) {
    cd <- T$code[i]; it <- ok[[cd]]; row <- as.list(T[i])
    fv <- file.path(vd, paste0(cd, ".verdict.json"))
    rc_json_write(list(schema = "rc_standing_verdict_v1", audience = "사람 쪽(전기간 · 시험 창 열 포함) — 처방 · 리뷰 레인은 원장 · standing_visible.json 만",
                       round_id = ctx$spec[["round_id"]], edition = ctx$cfg[["edition"]], code = cd, prereg_md5 = ctx$prereg_md5, judged_at = rc_now(),
                       rules = rules, sentences = sent, row = row), fv)
    vis <- row[intersect(c(RC_STANDING_VIS_COLS, qr), names(row))]
    vis[["window"]] <- evs[[cd]][["visible"]][["window"]]
    lk <- rc_after_tau_leaks(vis, ctx$tau)
    if (length(lk)) .rcs_err("보는 창 기록에 τ_D 이후 날짜가 남았다(", cd, "): ", paste(head(lk, 3), collapse = ","))
    q <- row[[qr]]; q <- if (is.logical(q) && length(q) == 1L) q else NA
    rc_standing_append(ctx, list(event = "verdict", code = cd, engine = it[["engine"]], status = .rcs_str(row[["status"]]), qualify = q,
                                 rule = qr, visible = vis, verdict_file = rc_rel(fv, root), verdict_md5 = rc_md5(fv),
                                 engine_md5 = it[["engine_md5"]], cell_spec_md5 = it[["cell_spec_md5"]]))
  }
  rc_standing_visible_write(ctx)
  rc_perf_log(ctx$spec[["round_id"]], "standing_judge", difftime(Sys.time(), t0, units = "secs"), list(n = nrow(T)), root = root)
  cat(sprintf("[상설] 판정 %d건 — 자격 %d\n", nrow(T), sum(T[[qr]] %in% TRUE)))
  invisible(list(judged = T$code, qualified = T[T[[qr]] %in% TRUE]$code))
}
## 보는 창 판정 표(원장에서 · 시험 창 열 없음) — Superfan · 처방 레인이 읽는 파일
rc_standing_visible_write <- function(ctx) {
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))
  rows <- lapply(Filter(function(it) !is.null(it[["verdict"]]), I), function(it) {
    v <- it[["verdict"]]; c(list(code = it[["code"]], engine = it[["engine"]], source = it[["source"]], status = v[["status"]], qualify = v[["qualify"]]),
                            v[["visible"]][setdiff(names(v[["visible"]]), c("code", "engine", "status"))]) })
  vis <- list(schema = "rc_standing_visible_v1", round_id = ctx$spec[["round_id"]], edition = ctx$cfg[["edition"]],
              audience = "보는 창(τ_D 이전) — 시험 창 열 제외 · 처방 · 리뷰 레인 열람 가능", items = unname(rows))
  lk <- rc_after_tau_leaks(vis$items, ctx$tau); if (length(lk)) .rcs_err("보는 창 파일에 τ_D 이후 날짜: ", paste(head(lk, 3), collapse = ","))
  rc_json_write(vis, file.path(ctx$P$results, "standing_visible.json"))
}

## ── 보고(통과 = 엔진마다 push 1통 · 미달 · 미시험 = 일 요약 1통(무음) — qvest-telegram §0.1 · §0.4) ──────────────
rc_standing_report <- function(round_dir, send = FALSE, day = format(Sys.Date()), root = rc_root(), registry_path = NULL, sender = NULL) {
  ctx <- rc_standing_context(round_dir, root, registry_path)
  recs <- rc_standing_ledger_read(ctx$ledger); I <- rc_standing_items(recs)
  scl <- Filter(function(r) identical(r[["event"]], "scan"), recs); scl <- if (length(scl)) scl[[length(scl)]] else NULL
  J <- Filter(function(it) !is.null(it[["verdict"]]) && !length(it[["reported"]]), I)
  pass <- Filter(function(it) isTRUE(it[["verdict"]][["qualify"]]), J)
  fail <- Filter(function(it) !isTRUE(it[["verdict"]][["qualify"]]) && substr(.rcs_str(it[["verdict"]][["at"]]), 1L, 10L) <= day, J)
  snd <- sender %||% function(...) { if (!exists("prep_send", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure/programs/program_report.R"))))); prep_send(...) }
  nm <- function(it) .rcs_or(.rcs_str(it[["paper"]][["title"]]), it[["engine"]])
  num <- function(x, d = 2L) { x <- suppressWarnings(as.numeric(unlist(x))[1]); if (is.finite(x)) sub("^-", "−", formatC(x, format = "f", digits = d)) else "NA" }
  thr <- function(id) { for (r in ctx$pre[["rules_resolved"]]) for (k in c(list(r), r[["of"]] %||% list())) if (identical(k[["id"]], id)) return(num(k[["value"]])); "NA" }
  art <- rc_rel(ctx$P$results, root)
  for (it in pass) {
    v <- it[["verdict"]][["visible"]]
    fv <- tryCatch(rc_json_read(rc_abs(it[["verdict"]][["verdict_file"]], root))[["row"]], error = function(e) list())   # 사람 쪽 보고(시험 창 유지)
    snd(program = "수익 엔진", target = sprintf("%s(%s)", nm(it), .rcs_or(.rcs_str(it[["paper"]][["paper_key"]]), it[["code"]])),
        status = list(stage = sprintf("상설 자격 판정(%s · 판 %s)", ctx$tag, ctx$cfg[["edition"]]), position = it[["code"]],
                      previous = "충실구현 레인 산출 → 표준 구성(롱온리 · 활성 측정 축)"),
        verdict_line = sprintf("자격 통과 — 보는 창 β-통제 t(α) %s ≥ %s · 상승 포착률 %s ≥ %s · 위기 하락노출 중앙 %s(최악 %s · 위기 %s번) · 시험 창 유지 %s",
                               num(v[["t_alpha_vis"]]), thr("q_t_alpha"), num(v[["uc_vis"]]), thr("q_uc"), num(v[["dd_capture_median_vis"]]),
                               num(v[["dd_capture_worst_vis"]]), num(v[["n_crisis_vis"]], 0L),
                               if (isTRUE(fv[["test_hold"]])) "예" else if (isFALSE(fv[["test_hold"]])) "아니오" else "판정 불가"),
        next_step = "P4 수익 엔진 후보 · Superfan 판단 T2 · 철학 P2(즉시)", artifact = art, push = TRUE, dry_run = !isTRUE(send), root = root)
    if (isTRUE(send)) rc_standing_append(ctx, list(event = "reported", kind = "push", codes = list(it[["code"]])))
  }
  if (length(fail)) {
    ln <- vapply(fail, function(it) { v <- it[["verdict"]]; vv <- v[["visible"]]
      if (identical(.rcs_str(v[["status"]]), "evaluated"))
        sprintf("%s — 미달 · t(α) %s · 상승 포착률 %s", nm(it), num(vv[["t_alpha_vis"]]), num(vv[["uc_vis"]]))
      else sprintf("%s — 미시험(%s)", nm(it), paste(c(.rcs_str(v[["status"]]), unlist(v[["r2"]])), collapse = " · ")) }, character(1))
    nf <- sum(vapply(fail, function(it) identical(.rcs_str(it[["verdict"]][["status"]]), "evaluated"), logical(1)))
    sec <- if (length(ln) >= 2L) list(heading = "엔진별 판정(보는 창)", type = "bullet", items = unname(ln)) else list(heading = "엔진별 판정(보는 창)", type = "text", body = ln[1])
    ex <- scl[["excluded"]]
    ent <- if (is.null(scl)) NULL else list(heading = "입구(레인 스캔 — 판정 아님)", type = "text",
      body = sprintf("마지막 스캔: 디렉터리 %s · 입구 통과 %s · 새로 넣음 %d%s", .rcs_str(scl[["n_dirs"]]), .rcs_str(scl[["n_eligible"]]), length(scl[["enqueued"]]),
                     if (length(ex)) paste0(" · 제외 사유 ", paste(sprintf("%s %s", names(ex), unlist(ex)), collapse = " · ")) else ""))
    snd(program = "수익 엔진", target = sprintf("상설 자격 일 요약 %s — 미달 %d · 미시험 %d", day, nf, length(fail) - nf),
        status = list(stage = sprintf("상설 자격 일 요약(%s · 판 %s)", ctx$tag, ctx$cfg[["edition"]]), position = sprintf("%d건", length(fail)), previous = "—"),
        verdict_line = sprintf("자격 미달 %d · 미시험 %d(통과는 따로 보냈다)", nf, length(fail) - nf), extra = Filter(Negate(is.null), list(sec, ent)),
        next_step = "Superfan 판단 T2 · 철학 P2 일 묶음 1회", artifact = art, push = FALSE, dry_run = !isTRUE(send), root = root)
    if (isTRUE(send)) rc_standing_append(ctx, list(event = "reported", kind = "daily_summary", day = day, codes = as.list(vapply(fail, function(it) it[["code"]], ""))))
  }
  invisible(list(pass = vapply(pass, function(it) it[["code"]], ""), fail = vapply(fail, function(it) it[["code"]], ""), sent = isTRUE(send)))
}

## ── Superfan(규약 §11 · §12 상설 자격 절) — 통과 = 즉시 T2 · P2 · 미달 = 일 묶음 1회 ──────────────
rc_standing_superfan_due <- function(I) {
  J <- Filter(function(it) !is.null(it[["verdict"]]), I)
  done <- function(it, kind) any(vapply(it[["superfan"]], function(s) identical(.rcs_str(s[["kind"]]), kind), logical(1)))
  pass <- vapply(Filter(function(it) isTRUE(it[["verdict"]][["qualify"]]) && !done(it, "pass"), J), function(it) it[["code"]], "")
  fl <- Filter(function(it) !isTRUE(it[["verdict"]][["qualify"]]) && !done(it, "daily"), J)
  daily <- split(vapply(fl, function(it) it[["code"]], ""), vapply(fl, function(it) substr(.rcs_str(it[["verdict"]][["at"]]), 1L, 10L), ""))
  list(pass = unname(pass), daily = daily)
}
rc_standing_mark_superfan <- function(round_dir, codes, kind = c("pass", "daily"), p2 = NA_character_, t2 = NA_character_, day = NA_character_,
                                      root = rc_root(), registry_path = NULL) {
  kind <- match.arg(kind); ctx <- rc_standing_context(round_dir, root, registry_path)
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger)); miss <- setdiff(codes, names(I))
  if (length(miss)) .rcs_err("원장에 없는 항목: ", paste(miss, collapse = ","))
  rc_standing_append(ctx, list(event = "superfan", kind = kind, codes = as.list(codes), p2 = p2, t2 = t2, day = day))
}

## ── 상태 줄 ────────────────────────────────────────────────────────────────
rc_standing_status_lines <- function(round_dir, root = rc_root(), registry_path = NULL) {
  ctx <- tryCatch(rc_standing_context(round_dir, root, registry_path), error = function(e) e)
  if (inherits(ctx, "error")) return(sprintf("[상설] %s — 등록 전이거나 R2 대조 실패: %s", basename(round_dir), conditionMessage(ctx)))
  I <- rc_standing_items(rc_standing_ledger_read(ctx$ledger)); src <- vapply(I, function(it) .rcs_or(.rcs_str(it[["source"]]), "?"), "")
  vq <- lapply(I, function(it) it[["verdict"]]); judged <- !vapply(vq, is.null, TRUE)
  q <- vapply(vq[judged], function(v) if (isTRUE(v[["qualify"]])) "pass" else if (identical(.rcs_str(v[["status"]]), "evaluated")) "fail" else "untested", "")
  pm <- sum(vapply(I, .rcs_pending, TRUE))
  pj <- sum(vapply(I, .rcs_judgeable, TRUE)); rb <- names(I)[vapply(I, .rcs_r2_blocked, TRUE)]
  mf <- names(I)[vapply(I, function(it) is.null(it[["verdict"]]) && (.rcs_fails(it) >= RC_STANDING_MAX_FAILS || (it[["eval_fails"]] %||% 0L) >= RC_STANDING_MAX_FAILS), TRUE)]
  ur <- sum(vapply(I, function(it) !is.null(it[["verdict"]]) && !length(it[["reported"]]), TRUE)); sd <- rc_standing_superfan_due(I)
  vv <- rc_standing_ledger_verify(ctx$ledger)
  c(sprintf("[상설] %s 판 %s · 항목 %d(시드 %d · 스캔 %d) · 측정 대기 %d · 판정 대기 %d · 판정 %d(통과 %d · 미달 %d · 미시험 %d) · 원장 사슬 %s(%d줄)",
            ctx$spec[["round_id"]], ctx$cfg[["edition"]], length(I), sum(src == "seed"), sum(src == "scan"), pm, pj, sum(judged),
            sum(q == "pass"), sum(q == "fail"), sum(q == "untested"), if (vv$ok) "정상" else "끊김", vv$n),
    sprintf("[상설] 보고 대기 %d · Superfan 즉시(T2 · P2) %d · 일 묶음 %d일", ur, length(sd$pass), length(sd$daily)),
    if (length(rb)) sprintf("[상설] R2 차단(사람 확인) %d: %s", length(rb), paste(rb, collapse = ",")),
    if (length(mf)) sprintf("[상설] 측정 · 칸 평가 실패 %d회 이상(사람 확인) %d: %s", RC_STANDING_MAX_FAILS, length(mf), paste(mf, collapse = ",")))
}

## ── 사양 만들기(P1 상설 판) · 시드 · 규칙 문서 ───────────────────────────────
## P1 템플릿 규칙 = rc_init_p1 이 쓰는 선언 그대로(P1R01 승계 · 한 곳에서 읽는다 — 사본을 만들지 않는다)
.rcs_p1_template_rules <- function(root = rc_root()) {
  td <- tempfile("rcs_tmpl_"); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  rc_init_p1(td, "P1R00_template", engines = list(), purpose = "", hypothesis = "", root = root)
  rc_json_read(file.path(td, "round_spec.json"))[["rules"]]
}
## 같은 판본 기준 재측정 시드(P2R04 RX0 선례) — 선례 사양 그대로 · 측정 축만 활성 epoch · 시행 수 무가산 표기
rc_standing_seed_respec <- function(like, code, n_family, n_trials_basis, root = rc_root()) {
  s <- rc_json_read(rc_abs(like, root)); base <- sub("[.]json$", "", basename(like))
  s[["code"]] <- code
  s[["fixed_axes"]][["measurement_axis"]] <- rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active", root)
  s[["label"]] <- sprintf("%s × 같은 판본 기준 재측정(활성 측정 축 · %s 사양 그대로)", s[["label"]], base)
  s[["idea"]] <- sprintf("[상설 자격 시드] %s 사양 그대로 · 측정 축만 활성 epoch · 시행 수 무가산", base)
  sa <- s[["selection_accounting"]] %||% list()
  sa[["n_family_at_registration"]] <- as.integer(n_family); sa[["n_trials_basis"]] <- n_trials_basis
  sa[["n_trials_note"]] <- "같은 판본 기준 재측정 — 시행 수 무가산(research-program SKILL §2 · P2R04 RX0 선례)"; sa[["remeasure_of"]] <- base
  s[["selection_accounting"]] <- sa
  s
}
## 골격 — round_spec.json(standing: true · 규칙 = P1 템플릿 · 스캔 규칙 · 생성 함수 핀 · 행동 카드 설정 사본) — 시드 칸 사양은 호출자가 먼저 쓴다
rc_init_standing_p1 <- function(round_dir, round_id, seeds, purpose, hypothesis, edition = 1L, scan = list(), exposures = list(),
                                conclusion_scope = list(), tests = list(), bcfg = "06_Registry/behavior_card.json", root = rc_root()) {
  sp_path <- file.path(round_dir, "round_spec.json")
  if (file.exists(sp_path)) .rcs_err("이미 사양이 있다 — 덮어쓰지 않는다: ", round_dir)
  dir.create(file.path(round_dir, "specs"), recursive = TRUE, showWarnings = FALSE)
  sc <- RC_STANDING_SCAN_DEFAULT; sc[names(scan)] <- scan   # 얕은 덮어쓰기(modifyList 는 이름 없는 목록을 덮지 않는다 — orientation_admit 등)
  cfg <- list(edition = as.integer(edition), program = "P1_RETURN", generator = "rc_p1_cell_spec", generator_pin = rc_standing_generator_pin(root),
              scan = sc,
              accounting = list(family_root = "paper_key", rule = "n_family = max(계보 앞선 사전등록 · 상설 원장 회계 최댓값, 레인 측정 수(대표 + 변형)) + 1 · 시드 = 무가산"),
              rejudge_prior_editions = FALSE, report = list(pass = "push_each", fail = "daily_summary"),
              superfan = list(on_register = list("T1", "P1"), on_pass = list("T2", "P2"), on_fail = "daily_batch"))
  spec <- list(schema = RC_SPEC_SCHEMA, program = "P1_RETURN", round_id = round_id, template = "p1_qualification", core_version = RC_VERSION,
               tau_d = "2022-12-31", purpose = purpose, hypothesis = hypothesis, standing = TRUE, standing_cfg = cfg, cells = seeds,
               rules = .rcs_p1_template_rules(root),
               selection = list(rule = "none", text = "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"),
               exposures = exposures, conclusion_scope = conclusion_scope, changes_after_review = list(), changes_after_superfan = list(), tests = tests)
  if (!is.null(bcfg)) { dst <- file.path(round_dir, "behavior_card_cfg_at_prereg.json")
    if (!file.exists(dst) && !isTRUE(file.copy(rc_abs(bcfg, root), dst))) .rcs_err("행동 카드 설정 사본 실패: ", bcfg)
    spec[["behavior_card_cfg"]] <- rc_rel(dst, root) }
  rc_standing_validate(spec, root)
  rc_json_write(spec, sp_path)
  invisible(sp_path)
}
## 규칙 문서(사람 · 점검자용) — 사양 선언에서 생성(손으로 고치지 않는다)
rc_standing_rules_md <- function(spec, root = rc_root()) {
  cfg <- spec[["standing_cfg"]]; sc <- cfg[["scan"]]; pin <- cfg[["generator_pin"]]; rr <- rc_rules_resolve(spec[["rules"]], root)
  cn <- pin[["canon"]]
  c(sprintf("# %s 상설 자격 규칙 — 판 %s (rc_standing_rules_md 가 사양에서 생성 · 손으로 고치지 않는다)", spec[["round_id"]], cfg[["edition"]]), "",
    "## 1. 판정 규칙(선언에서 생성 — 판정 코드와 같은 출처)", "", paste0("- ", rc_rules_sentences(rr)), "", rc_rules_table_md(rr), "",
    "## 2. 처치 = 표준 구성(생성 함수 핀)", "",
    sprintf("- 생성 함수 `%s` md5 %s · 선례 `%s` md5 %s", pin[["fn"]], pin[["fn_md5"]], pin[["like"]], pin[["like_md5"]]),
    sprintf("- 정본 고정 축: 측정 축 %s · 종목 ≤ %s · 비용 %s bps · 유동성 하한 %s원 · 롱온리 %s",
            cn[["measurement_axis"]], cn[["max_names"]], cn[["cost_bps"]], format(as.numeric(cn[["liq_min"]]), big.mark = ",", scientific = FALSE), cn[["long_only"]]),
    "- 칸 사양은 등록 뒤 이 함수가 재량 없이 만들고, 측정 · 판정 직전 다시 만들어 md5 를 대조한다(다르면 그 항목 미시험 · r2_violation).", "",
    "## 3. 레인 스캔 규칙(자격 큐 입구 — 성과 수치를 읽지 않는다)", "",
    sprintf("- 원천: `%s/%s` 디렉터리 × 등록부 인계 기록(kind = engine) · 인계 프로그램 = %s · 허용 감사 판정 = %s · 허용 방향 층 = %s · 롱 레그 창 = %s(τ_D %s 이전) · PIT 정적 검사 = %s",
            sc[["lane_root"]], sc[["dir_glob"]], sc[["routed_program"]], paste(unlist(sc[["audit_admit"]]), collapse = " · "),
            paste(unlist(sc[["orientation_admit"]]), collapse = " · "), sc[["long_leg_window"]], spec[["tau_d"]], if (isTRUE(sc[["pit_static"]])) "켬" else "끔"),
    "- 방향 층: engine_native = 엔진 고유 특성(커넥터 부호를 쓰지 않음) · factor_db_asof = 정본 커넥터 `load_month_factors`/`load_daily_factors` 의 as-of IC 3단 부호 · orientation_layer = `align_factor_direction`/`compute_rolling_ic_all` 호출 또는 부호 층 식별자(R 파서 토큰 — 주석 · 문자열 제외)",
    "- 한 디렉터리의 모든 실패 사유를 모은다. 통과 + 처음 보는 엔진(md5)만 인계 시각 순으로 넣는다. 같은 엔진은 판 사이에서도 다시 판정하지 않는다(새 판의 rejudge_prior_editions = true 일 때만).", "",
    "| 사유 코드 | 제외 조건 |", "|---|---|", sprintf("| `%s` | %s |", names(RC_STANDING_REASONS), unname(RC_STANDING_REASONS)), "",
    "## 4. 항목마다 R2", "",
    "- 판 단위: 사전등록 md5 = 등록부 · 사양 md5 = 등록본 · 생성 함수 핀 = 지금 · 판정 경로 핀(rc_pins_mismatches) — 하나라도 다르면 넣기 · 측정 · 판정을 멈춘다(새 판 등록).",
    "- 항목 단위: 엔진 md5 · 칸 사양 md5 = 원장(넣을 때) · 시드 = 등록본 칸 md5 · 스캔 항목 = 생성 함수로 다시 만든 md5. 측정 중 데이터 지문이 바뀌면 그 측정은 쓰지 않는다(1회 재측정).",
    sprintf("- 인프라 실패(측정 ok ≠ true · 지문 불일치 · 칸 평가 예외)는 판정이 아니다 — 다시 재거나 다시 평가하고, %d번째 실패면 사람이 본다(standing-status). R2 대조 실패는 그 항목만 멈춘다.", RC_STANDING_MAX_FAILS),
    "- 더 높은 판이 등록되면 옛 판은 새 항목을 받지 않는다(옛 판정 유지).", "",
    "## 5. 원장 · 보고 · Superfan", "",
    "- 원장 = 사전등록 정본 옆 `standing_ledger.jsonl`(추가 전용 · 줄마다 앞 줄 md5 사슬 · 보는 창 값만). 사람 쪽 판정 파일 = `results/standing/<code>.verdict.json`(시험 창 열 포함).",
    sprintf("- 보고: 통과 = %s · 미달 · 미시험 = %s(qvest-telegram §0.1 단위 · §0.4 푸시).", cfg[["report"]][["pass"]], cfg[["report"]][["fail"]]),
    sprintf("- Superfan(규약 §11-1 · §12): 등록 = %s 1회 · 통과 = 즉시 %s · 미달 = %s.", paste(unlist(cfg[["superfan"]][["on_register"]]), collapse = " · "),
            paste(unlist(cfg[["superfan"]][["on_pass"]]), collapse = " · "), cfg[["superfan"]][["on_fail"]]))
}

## CLI — Rscript standing.R <round_dir> <단계> [인자] (round.sh 가 부른다)
##   standing-check · scan [--dry-run] [--max N] [--out f] · pending · measure-item <code> · judge · standing-report [--send] [--day D] ·
##   standing-status · superfan-mark --codes a,b --kind pass|daily [--p2 id] [--t2 id] [--day D]
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) < 2L) stop("usage: standing.R <round_dir> <stage> [args]")
  source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "04_Research/programs/_lib/round_core/v1/load.R"))
  ROOT <- rc_root(); setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
  rd <- rc_abs(a[1], ROOT); st <- a[2]; rest <- a[-(1:2)]
  opt <- function(k) { i <- match(k, rest); if (is.na(i) || i == length(rest)) NULL else rest[i + 1L] }
  flag <- function(k) k %in% rest
  switch(st,
    "standing-check" = {
      s <- rc_spec_load(file.path(rd, "round_spec.json"), ROOT); rc_standing_validate(s, ROOT)
      cat(paste0("- ", rc_rules_sentences(rc_rules_resolve(s[["rules"]], ROOT))), sep = "\n")
      for (c in s[["cells"]]) if (!is.null(c[["spec"]])) {
        sa <- rc_json_read(rc_abs(c[["spec"]], ROOT))[["selection_accounting"]]; fam <- .rcs_str(sa[["family_root"]])
        nf_now <- rc_standing_nf_prior(fam, ROOT); nf_spec <- suppressWarnings(as.integer(.rcs_str(sa[["n_family_at_registration"]])))
        cat(sprintf("[standing-check] 시드 %s · 계보 %s 회계 %s(지금 앞선 최댓값 %d)%s\n", c[["code"]], fam, nf_spec, nf_now,
                    if (!identical(nf_spec, as.integer(nf_now))) " — ★다르다: 등록 직전 시드 사양을 다시 만든다" else ""))
      }
      writeLines(rc_standing_rules_md(s, ROOT), file.path(rd, "standing_rules.md"), useBytes = TRUE)
      cat(sprintf("[standing-check] %s 판 %s · 생성 함수 핀 일치 · 규칙 문서 %s\n", s[["round_id"]], s[["standing_cfg"]][["edition"]],
                  rc_rel(file.path(rd, "standing_rules.md"), ROOT))) },
    scan = {
      r <- rc_standing_scan(rd, ROOT, dry_run = flag("--dry-run"), max_new = opt("--max"), out = opt("--out")); C <- r$table
      cat(sprintf("[scan] %s · 디렉터리 %d · 입구 통과 %d(새 엔진 %d · 이미 판정 %d)%s\n", basename(rd), nrow(C), sum(C$eligible),
                  sum(C$status == "new"), sum(C$status == "known"), if (flag("--dry-run")) " · dry-run(쓰기 없음)" else sprintf(" · 넣음 %d", length(r$enqueued))))
      rs <- table(unlist(strsplit(C[eligible == FALSE]$reasons, ";", fixed = TRUE)))
      if (length(rs)) cat(sprintf("  제외 사유: %s\n", paste(sprintf("%s %d", names(rs), as.integer(rs)), collapse = " · ")))
      for (i in which(C$eligible)) cat(sprintf("  통과: %s · %s · %s\n", C$dir[i], C$paper_key[i], C$status[i])) },
    pending = cat(rc_standing_pending(rd, ROOT), sep = "\n"),
    "measure-item" = rc_standing_measure_item(rd, rest[1], ROOT),
    judge = rc_standing_judge(rd, ROOT),
    "standing-report" = { r <- rc_standing_report(rd, send = flag("--send"), day = opt("--day") %||% format(Sys.Date()), root = ROOT)
                          cat(sprintf("[standing-report] 통과 push %d · 일 요약 %d건%s\n", length(r$pass), length(r$fail), if (r$sent) "" else " · dry-run")) },
    "standing-status" = writeLines(rc_standing_status_lines(rd, ROOT)),
    "superfan-mark" = { rc_standing_mark_superfan(rd, strsplit(opt("--codes") %||% stop("--codes 필요"), ",", fixed = TRUE)[[1]],
                                                  kind = opt("--kind") %||% "pass", p2 = opt("--p2") %||% NA_character_, t2 = opt("--t2") %||% NA_character_,
                                                  day = opt("--day") %||% NA_character_, root = ROOT); cat("[superfan-mark] 원장 기록\n") },
    stop("모르는 단계: ", st))
}
