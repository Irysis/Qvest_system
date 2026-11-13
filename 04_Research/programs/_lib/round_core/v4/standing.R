## round_core v4 · standing — 상설 자격 모드(WP5 · 도훈 10-20 채택 'P1 상설 자격 등록' · 결정 L1-SPEED-LEVERS-20261020)
##   엔진 자격 규칙을 프로그램 단위로 한 번 사전등록(사양 standing: true · P1S01)하면, 그 뒤 충실구현 레인이 낸 엔진마다
##   라운드 의식 없이 스캔 → 칸 사양 생성 → 측정 → 판정 → 보고가 돈다. R2(측정 전 등록)는 그대로다.
##   · 규칙 · 스캔 규칙 · 생성 함수 핀(rc_p1_cell_spec md5 · 선례 · 정본 고정 축)은 등록본(prereg.json 의 spec)에 고정된다.
##   · 항목 칸 사양은 등록된 생성 함수가 재량 없이 만들고, 측정 · 판정 직전 다시 만들어 md5 를 대조한다.
##   · 항목마다 사전등록 md5(= 등록부) · 사양 md5(= 등록본) · 생성 함수 핀 · 판정 경로 핀(rc_pins_mismatches)을 본다.
##   판정 원장 = 사전등록 정본 옆 standing_ledger.jsonl — 추가 전용, 줄마다 앞 줄 md5(prev) 사슬(중간 수정 · 삭제를 잡는다).
##   규칙 · 생성 함수 · 판정 경로가 바뀌면 새 판(P1S02 …)을 등록한다 — 옛 판정은 남고, 새 판이 등록되면 옛 판은 새 항목을 받지 않는다.
##   등록부(research_programs.json)는 읽기만 한다(쓰기 잠금 WP3 전 동시 갱신 유실 방지 — 등록부 쓰기는 rc_register 한 번뿐).
##   수치는 R 계약 산출만(AX-008 — 칸 평가 rc_eval_cell · 판정 표 rc_p1_table). 원장 · 스캔 기록에는 보는 창 값만 싣는다(τ_D).
##   v3(2026-11-11 · 판 2 P1S02 · 설계 04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §6-4 · §8 · BUILD_EDITION2.md S4):
##   ① 입구 사유 2개 — portfolio_only_base(FACTORS 대입 없음 · 정적) · breadth_insufficient(레인 점수 패널의 보는 창 신호일 중 폭 ≥ 보유 상한 × 배수인 날 없음 ·
##     숫자 = 정본 참조 · τ_D 절단 뒤 센다 · 필요조건) ② 측정 기록에 기저 정합 진단(셀 엔진 rf_engine_diag.json::base_alignment)을 싣고, 없거나 규칙이
##     다르면 base_alignment_missing · 기저가 점수 패널이 아니면 base_not_score_panel 로 실패 기록(판 표식) ③ 같은 칸(엔진 경로 + 구성)을 여러 판이 판정했으면
##     기저 풀 입구(rc_standing_qualified)는 판 번호가 가장 큰 판의 판정만 읽는다.
##   v4(2026-11-13 · 도훈 결정 FACTOR-SPINE-STAGE1-20261112 D4 (a) · 설계 04_Research/01_reports/factor_spine_design_20261111/README.md §3-6 · P1R03 결론 범위):
##   ① 자체 사양 입구(scan.source = "own_spec") — 생성기가 own_spec.json 에서 만든 점수 패널 엔진(04_Research/strategies/FC_*)을 레인 인계 없이 받는다.
##     입구 판독 = own_spec 형식 · core md5 · 생성기 목록 · 생성기 md5 · 엔진 md5 · 재생성 본문 md5(.rcs_scan_own_dir · 성과를 읽지 않는다).
##     원천 라운드(source_rounds) = 같은 엔진(등록 md5)을 칸으로 등록한 P1 라운드 — 있으면 같은 시행의 재측정이라 계보 시행 수를 더하지 않는다.
##   ② 입구 갈래(standing_cfg.track = lane | own_spec) — 판 번호는 갈래마다 1 부터 · 옛 판 받기 정지(enqueue 맥락)는 같은 갈래의 더 높은 판만 본다
##     (자체 사양 입구 판 1 이 레인 입구 판 2(P1S02 · 코어 v3)를 막지 않게 — v3 는 갈래를 모르지만 1 < 2 라 막지 않는다).
##   ③ 원장 줄 머리에 track · 자격 통과 표(rc_standing_qualified)에 origin · own_spec · families · source_rounds · superfan_pass_p2 · track ·
##     paper_title · paper_url 열(P4 기저 풀의 철학 P2 영수증 · 저위험 확인 · 원천 시행 회계가 읽는다).
##   v4 출시 전 수리(11-13 · 격리 점검 isolation_review_v4.md M1 · R1 · R3 · R5 · S6 · 판단 T4 C-20261113-035 · 036 · P1S03 감독 C-046 · 049 · 058):
##   ④ 자체 사양 여부 = 엔진 속성(원장 갈래 own_spec ∨ 엔진 폴더 own_spec.json — 열 own_spec_engine · 시드 · 손 항목도) · 못 채운 행 = own_resolved FALSE
##   ⑤ 원천 라운드 = 엔진 md5 칸 ∪ 같은 계보(family_root) 칸을 가진 P1 라운드(.rcs_own_source — 다시 만든 엔진도 앞선 계보 시행을 물려받는다)
##   ⑥ enqueue 시행 수 = 원천 칸(같은 md5 · 변형 · 같은 계보)이 있으면 max(계보 최댓값, 원천 라운드 칸 수 — 사슬 원천 시행과 같은 집합) · 아니면 그 위에 +1
##   ⑦ 입구 사유 own_spec_family_mismatch · own_spec_undeclared · 자체 사양 갈래 판정은 RELEASES 출시 판 ≥ v4 뒤에만(v3 기저 풀이 관문 없이 읽지 않게)
##   ⑧ 통과 보고 = 판정 줄(판정 두 조건) / 보고 열(판정 아님) / OOS 줄 분리 · report.pass = daily_summary 허용 · 결론 범위 앞 P1 표준 철학 줄 · 자체 사양 판 생성기 자동 핀.

RC_STANDING_LEDGER_SCHEMA <- "rc_standing_ledger_v1"
## v4 입구 원천 · 갈래 — 레인 인계(lane_handoff → 갈래 lane) · 자체 사양(own_spec → 갈래 own_spec). 판 번호 · 옛 판 받기 정지는 갈래 안에서만.
RC_STANDING_SOURCES <- c(lane_handoff = "lane", own_spec = "own_spec")
RC_STANDING_TRACKS <- unname(RC_STANDING_SOURCES)
RC_STANDING_OWN_SCHEMA <- "fc_own_spec_v0"   # 자체 사양 형식(T0 생성기 fc_engine_gen.R 의 FCE_SCHEMA · T1 생성기 fc_combiner_gen.R 의 FCC_SCHEMA 와 같은 값)
RC_STANDING_ORIENT <- c("engine_native", "factor_db_static", "factor_db_asof", "orientation_layer")
## 정본 커넥터(C15) + 결합용 뷰(factor_combinable.R) — 방향 인자로 정적/동적을 가른다(2026-11-10 · 상설 판 입구 수리)
##   direction = "registry" | "defensive"(등록부에 미리 선언된 방향 = 정적 부호) → factor_db_static(엔진 고유와 같은 취급 — 동적 부호 아님)
##   인자 없음 · "ic_asof" · 상수가 아닌 값(정적으로 판정 불가) · 함수 값으로 넘김 · do.call 문자열 → factor_db_asof(동적 부호)
##   전에는 load_month_factors 호출만 보면 인자와 무관하게 동적으로 뺐고(레인 프롬프트의 registry 권장과 상쇄), 결합용 뷰 호출은
##   목록에 없어 ic_asof 판도 engine_native 로 통과했다(레인 W 조사 P0-3).
RC_STANDING_FDB_CALLS <- c("load_month_factors", "load_daily_factors", "fc_load_month", "fc_load_months", "fc_daily")
RC_STANDING_FDB_STATIC_DIR <- c("registry", "defensive")
## 위치 인자 대응(정본 서명 사본 — 커넥터 · 결합용 뷰 서명이 바뀌면 시험 J 가 대조한다) · fc_load_months 의 ... 는 fc_load_month(d, family = FALSE, ...) 로 간다
.RCS_FDB_FORMALS <- list(
  load_month_factors = function(sig_date, coverage_min, factor_names, dedup, direction) NULL,
  load_daily_factors = function(ym, date_range, factors, align_direction, direction) NULL,
  fc_load_month = function(sig_date, direction, factors, tickers, missing, dedup, family, root, dir, registry, resolve) NULL,
  fc_load_months = function(sig_dates, direction, factors, tickers, missing, dedup, root, dir, registry, resolve) NULL,
  fc_daily = function(ym, date_range, factors, direction, tickers, missing, dedup, root) NULL)
RC_STANDING_ORIENT_CALLS <- c("align_factor_direction", "compute_rolling_ic_all")  # 엔진이 방향 · IC 를 스스로 다루는 층
RC_STANDING_SIGN_IDS <- c("ic_sign", "sign_ic", "ic_dir", "ic_direction", "flip_sign", "sign_flip", "negate_factors")   # 소문자 비교
RC_STANDING_W_TOL <- 1e-9          # 보유 비중 수치 허용오차(cell_eval.R rc_axis_audit 과 같은 크기)
RC_STANDING_MIN_BYTES <- 200L      # 엔진 파일 하한(검증기 rf_replication_verify.R 'engine_too_small' 과 같은 값)
RC_STANDING_MAX_FAILS <- 2L        # 인프라 실패 · 지문 불일치 재측정 횟수(round.sh measure 의 '1회 재측정'과 같은 뜻 — 2번째 실패면 사람이 본다)
RC_STANDING_REPORT_PASS <- c("push_each", "daily_summary")   # v4 통과 보고 단위(판단 T1 C-20261113-058 — 30 항목이 한 번에 흐르는 판의 통과마다 push 를 일 요약 1통으로)
## v4 통과 보고의 보고 열 고정 문구(철학 P1 C-20261113-046 · 도훈 결정 CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113 — 위기 하락노출 = 판정 아님 · 방어 근거 아님)
RC_STANDING_REPORT_NOTE <- "시장 대비 귀속 전 원값 — 시가총액 × β 무작위 대조 포트폴리오 미측정 · 방어 주장 없음(도훈 결정 CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113)"
RC_STANDING_SCAN_DEFAULT <- list(source = "lane_handoff", lane_root = "04_Research/strategies", dir_glob = "RP_AUTO_*",
                                 routed_program = "P1_RETURN", audit_admit = list("faithful", "adapted"),
                                 orientation_admit = list("engine_native"), long_leg_window = "visible",
                                 exclude_combination = TRUE, pit_static = TRUE)
## v4 자체 사양 입구 기본값 — 생성기 둘(T0 가족 · 토탈 등가중 / T1 as-of IC 가중)과 각 엔진 본문 함수 · 방향 층 = 엔진 고유 + 부호 층.
##   orientation_layer 허용 조건(이 갈래에서만): 엔진 본문 = 생성기 산출(재생성 md5 대조 — own_generator_mismatch) + 본문의 실행 단정
##   (부호 = 등록부 s_reg 고정 · 가중 유한 · 비음수 — 어기면 엔진이 멈춘다 · T1 생성기 fc_combiner_gen.R 본문 틀). 레인 갈래는 부호 층을 받지 않는다.
RC_STANDING_SCAN_OWN_DEFAULT <- list(source = "own_spec", lane_root = "04_Research/strategies", dir_glob = "FC_*", routed_program = "P1_RETURN",
                                     generators = list(list(path = "02_Infrastructure/factor_db/fc_engine_gen.R", text_fn = "fce_engine_text"),
                                                       list(path = "02_Infrastructure/factor_db/fc_combiner_gen.R", text_fn = "fcc_engine_text")),
                                     orientation_admit = list("engine_native", "orientation_layer"), long_leg_window = "visible",
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
  portfolio_only_base = "포트폴리오만 내는 엔진 — FACTORS 대입이 없다(정적 검사 · v3). 표준 구성은 점수로 상위 N 을 고르는데, 셀 경로는 비중을 점수로 읽게 된다(설계 §2-2 · §6-4)",
  breadth_insufficient = "후보 폭 부족 — 레인 점수 패널(factors_panel.parquet · Date · Ticker 만 읽는다)의 보는 창(τ_D 이전 — 세기 전에 자른다) 신호일 가운데 종목 수 ≥ 보유 상한(tier_soft_deployment.max_names) × 배수(측정 축 effective_start.breadth_mult)인 날이 없다(v3). ★필요조건일 뿐이다 — 레인 패널의 개수는 셀 필터(위생 · 유동성 · 동전주 · 그날 유니버스) 전 값이라 통과해도 셀에서 미달일 수 있다. 패널 없음 · 판독 불가 · 보는 창 날짜 0 이면 이 사유를 붙이지 않는다(측정의 실효 시작 규칙이 가른다)",
  base_off_month_grid = "주간 · 일간 신호 엔진 — 셀 경로는 월말 표본이 되므로 판정하지 않는다(측정 축: 주간 신호면 주간 리밸 · 셀 엔진 주간 신호 미구현). 판독 = 레인 점수 패널의 보는 창(τ_D 이전) 신호일 중 한 달력 월에 2개 이상인 달이 있다(v3 · 판단 Superfan T4 R-20261111-008 · 모수 없음 · 패널 판독 불가면 사유 없음)",
  dynamic_sign = "동적 부호 — 방향 층이 허용 목록 밖(factor_db_asof = 정본 커넥터 · 결합용 뷰의 as-of IC 부호(방향 인자 없음 · ic_asof · 판정 불가) · orientation_layer = 엔진이 부호 · IC 를 스스로 다룸 · factor_db_static(등록부 방향 registry · defensive)은 engine_native 를 허용하면 함께 허용)",
  long_leg_absent = "보는 창 신호일 중 롱 레그(비중 > 0)가 없는 날이 있다 — 시계열 방향 · 현금 타이밍 층(표준 구성이 그날 숏 대상을 사거나 비게 된다)",
  long_leg_unverifiable = "레인 측정 보유(04_holdings.csv)를 읽지 못해 롱 레그를 확인할 수 없다",
  pit_static = "PIT 정적 검사(lookahead_detector) 위반 또는 미스캔",
  paper_meta_missing = "논문 url · 제목 · 키를 정하지 못했다(자체 사양 = own_spec root_paper 의 url · title · paper_key 중 빈 것)",
  own_spec_missing = "자체 사양(own_spec.json) 없음 · 판독 불가 · schema 가 fc_own_spec_v0 아님 · core 의 md5 ≠ spec_md5(생성기와 같은 직렬화 — 손 편집 · 손상)(v4 · 자체 사양 입구)",
  own_generator_unknown = "자체 사양의 생성기(generator.path)가 이 판의 생성기 목록(scan.generators) 밖이다(v4 · 자체 사양 입구)",
  own_generator_mismatch = "생성기 대조 실패 — 지금 생성기 파일 md5 ≠ core.generator_md5 · 엔진 파일 md5 ≠ own_spec engine.md5 · own_spec 에서 그 생성기의 본문 함수로 다시 만든 본문 md5 ≠ 엔진 파일 md5 · 생성기 적재 · 본문 생성 실패 중 하나 이상(v4 · 자체 사양 입구 — 엔진 본문 = 생성기 산출이어야 한다)",
  own_spec_family_mismatch = "원천 칸(이 엔진 md5 를 칸으로 등록한 P1 라운드 칸)의 계보(칸 사양 selection_accounting.family_root)가 own_spec family_root 와 다르다 — 시행 회계 계보가 갈린다(v4 · 격리 점검 R1)",
  own_spec_undeclared = "선언 기록이 없다 — ① 등록부 선언 줄(origin = own_spec · kind ≠ engine · engine_path · engine_md5 = 지금 엔진) ② own_spec.json decision 이 결정 기록부에 status = resolved ③ 이 엔진 md5 를 칸으로 등록한 P1 라운드 중 하나도 없다(v4 · 설계 factor_spine_design_20261111 §3-6 (a) · 격리 점검 R3 — 계보 승계는 시행 회계일 뿐 선언이 아니다)")
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
## v4 입구 갈래 — 사양의 standing_cfg.track · 없으면 scan.source 의 갈래(own_spec) · 그 밖 = lane(v3 이전 판 · 표식 없는 판)
.rcs_track_of <- function(cfg) {
  t <- .rcs_str(cfg[["track"]]); if (!is.na(t)) return(t)
  if (identical(.rcs_str(cfg[["scan"]][["source"]]), "own_spec")) "own_spec" else "lane"
}

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
  if (!(sc[["source"]] %in% names(RC_STANDING_SOURCES))) .rcs_err("scan.source 는 ", paste(names(RC_STANDING_SOURCES), collapse = " | "))
  if (!identical(sc[["routed_program"]], spec[["program"]])) .rcs_err("scan.routed_program ≠ program")
  ## v4 입구 갈래 — lane_handoff = 갈래 lane(키 없음 = lane) · own_spec = 갈래 own_spec(키 필수) · 원천과 갈래가 어긋나면 거부
  tr <- cfg[["track"]]; want <- RC_STANDING_SOURCES[[sc[["source"]]]]
  if (is.null(tr) && identical(sc[["source"]], "own_spec")) .rcs_err("standing_cfg.track 없음 — 자체 사양 입구(scan.source = own_spec)는 track = \"own_spec\" 를 적는다")
  if (!is.null(tr) && (!is.character(tr) || length(tr) != 1L || !(tr %in% RC_STANDING_TRACKS))) .rcs_err("standing_cfg.track 은 ", paste(RC_STANDING_TRACKS, collapse = " | "))
  if (!is.null(tr) && !identical(tr, want)) .rcs_err("standing_cfg.track(", tr, ") ≠ scan.source(", sc[["source"]], ")의 갈래 ", want)
  if (identical(sc[["source"]], "own_spec")) {
    ## 자체 사양 입구 — 생성기 목록(저장소 상대 경로 · 파일 실재 · 엔진 본문 함수 이름) · 감사 판정 허용 목록은 쓰지 않는다(레인 인계가 없다)
    G <- sc[["generators"]]
    if (!is.list(G) || !length(G) || !is.null(names(G))) .rcs_err("scan.generators 는 이름 없는 목록 1개 이상({path, text_fn})")
    gp <- character(0)
    for (g in G) {
      p <- .rcs_str(g[["path"]]); fn <- .rcs_str(g[["text_fn"]])
      if (is.na(p) || grepl("^([A-Za-z]:|/)", p) || grepl("\\\\", p)) .rcs_err("scan.generators[].path 는 저장소 상대 경로(슬래시): ", p)
      if (check_files && !file.exists(rc_abs(p, root))) .rcs_err("scan.generators[].path 파일 없음: ", p)
      if (is.na(fn) || !grepl("^[A-Za-z.][A-Za-z0-9._]*$", fn)) .rcs_err("scan.generators[].text_fn 은 엔진 본문 함수 이름: ", fn)
      gp <- c(gp, p)
    }
    if (anyDuplicated(gp)) .rcs_err("scan.generators 경로 중복: ", paste(gp[duplicated(gp)], collapse = ","))
    oa <- unlist(sc[["orientation_admit"]]); if (!length(oa) || !all(oa %in% RC_STANDING_ORIENT)) .rcs_err("scan.orientation_admit 은 ", paste(RC_STANDING_ORIENT, collapse = "|"), " 의 부분집합")
  } else {
    aa <- unlist(sc[["audit_admit"]]); if (!length(aa) || !all(aa %in% c("faithful", "adapted"))) .rcs_err("scan.audit_admit 은 faithful · adapted 의 부분집합(1개 이상)")
    ## v4: 부호 층(orientation_layer)은 자체 사양 입구에서만(엔진 본문 = 생성기 산출 · 본문 실행 단정이 허용 조건 — 레인 엔진에는 그 두 장치가 없다)
    lo <- setdiff(RC_STANDING_ORIENT, "orientation_layer")
    oa <- unlist(sc[["orientation_admit"]]); if (!length(oa) || !all(oa %in% lo)) .rcs_err("scan.orientation_admit 은 ", paste(lo, collapse = "|"), " 의 부분집합(레인 입구 — orientation_layer 는 자체 사양 입구에서만)")
  }
  if (!identical(sc[["long_leg_window"]], "visible")) .rcs_err("scan.long_leg_window 는 visible(τ_D 이전)만 — 입구 규칙도 보는 창 정보만")
  if (!isTRUE(sc[["exclude_combination"]])) .rcs_err("결합 제외(exclude_combination)는 끌 수 없다")
  if (!is.logical(sc[["pit_static"]]) || length(sc[["pit_static"]]) != 1L) .rcs_err("scan.pit_static 은 논리값 1개")
  rj <- cfg[["rejudge_prior_editions"]]; if (!is.logical(rj) || length(rj) != 1L) .rcs_err("rejudge_prior_editions 는 논리값 1개")
  ## v4(판단 T1 C-20261113-058): 통과 보고 단위 — push_each(통과마다 push 1통 · 기본) | daily_summary(통과도 일 요약 1통)
  rp <- cfg[["report"]][["pass"]]
  if (!is.null(rp) && !(is.character(rp) && length(rp) == 1L && rp %in% RC_STANDING_REPORT_PASS)) .rcs_err("standing_cfg.report.pass 는 ", paste(RC_STANDING_REPORT_PASS, collapse = " | "))
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
  ## v4: 머리에 입구 갈래(track) — 판 번호가 갈래마다 1 부터라 원장만 보는 독자(감시기 등)가 갈래별로 묶을 수 있게
  full <- c(list(schema = RC_STANDING_LEDGER_SCHEMA, at = rc_now(), round_id = ctx$spec[["round_id"]], edition = ctx$cfg[["edition"]],
                 track = ctx$track %||% .rcs_track_of(ctx$cfg), prereg_md5 = ctx$prereg_md5, prev = if (s$n) .rcs_md5s(s$lines[s$n]) else "genesis"), rec)
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
  trk <- .rcs_track_of(cfg)
  if (identical(mode, "enqueue")) {
    ## v4: 같은 입구 갈래(track)의 더 높은 판만 본다 — 갈래가 다른 판(레인 입구 판 2 · 자체 사양 입구 판 1)은 서로 막지 않는다(판 번호는 갈래마다 1 부터)
    E <- rc_standing_editions(rs[["program"]], root, registry_path)
    nw <- E[!is.na(edition) & edition > as.integer(cfg[["edition"]]) & round_id != rs[["round_id"]] & track == trk]
    if (nrow(nw)) .rcs_err("같은 입구 갈래(", trk, ")에 더 높은 판이 등록됐다(", paste(nw$round_id, collapse = ","), ") — 옛 판은 새 항목을 받지 않는다(옛 판정은 유지)")
  }
  list(spec = rs, pre = pre, P = P, cfg = cfg, tau = as.Date(rs[["tau_d"]]), ledger = file.path(P$sa_dir, "standing_ledger.jsonl"),
       prereg_md5 = rc_md5(P$prereg), round_dir = round_dir, root = root, registry_path = registry_path, tag = rc_round_tag(rs[["round_id"]]), track = trk)
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
                                          edition = suppressWarnings(as.integer(.rcs_str(p[["spec"]][["standing_cfg"]][["edition"]]))),
                                          track = .rcs_track_of(p[["spec"]][["standing_cfg"]]))   # v4 입구 갈래(표식 없음 = lane)
  }
  if (length(out)) rbindlist(out) else data.table(round_id = character(0), status = character(0), edition = integer(0), track = character(0))
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

## 상설 자격 통과 엔진(P4 기저 풀의 읽기 입구 · 2026-11-10) — 상설 원장들의 판정(qualify = TRUE) 항목. 원장 사슬이 끊긴 판은 읽지 않는다(경고 · 자격 인정 없음).
##   열: round_id · edition · code · engine · engine_path(저장소 상대) · engine_md5(넣을 때) · engine_same(지금 파일 md5 = 넣을 때) ·
##       artifacts(마지막 ok 측정 산출) · paper_key · verdict_at · ledger. 성과 수치는 싣지 않는다(판정 여부만).
##   v3: 같은 칸 = 같은 엔진 경로 + 같은 구성(표준 구성 · 처치 칸은 처치 축 문자열)을 여러 판이 판정했으면 판 번호가 가장 큰 판의 판정만 쓴다
##     (앞 판 통과 · 뒤 판 미달 = 자격 없음 · 미시험(r2_violation 등) 판정도 판정으로 센다 — fail-closed). 판정이 한 판에만 있으면 v2 와 같다.
##     엔진 경로 · 구성을 판독하지 못한 항목(공유 측정 시드 · 구성 NA)은 다른 판과 묶지 않는다(그 항목 혼자 — 자격 판독은 v2 그대로).
##   v4: ① 판 번호 비교는 같은 입구 갈래(track) 안에서만 한다(판 번호가 갈래마다 1 부터). 같은 칸 묶음 키(엔진 경로 + 구성)에는 갈래를 넣지 않는다 —
##     넣으면 두 갈래가 같은 칸을 판정했을 때 한쪽 미달이 다른 쪽 통과를 지우지 못한다(fail-open). 대신 묶음이 두 갈래 이상에 걸치면 갈래마다의
##     최신 판정이 모두 통과일 때만 자격이고(fail-closed), 행은 판정 시각이 가장 늦은 갈래의 것 하나다(기저 풀 입력 = 칸마다 한 행).
##     ★갈래가 다르면 같은 엔진이 두 판에 들어갈 일이 없다는 가정이 깨지는 경우: 두 갈래의 dir_glob · lane_root 가 겹칠 때 · 손으로 넣은 항목(source manual) ·
##     한 갈래 판의 시드(reference)가 다른 갈래 엔진일 때 · rejudge_prior_editions = TRUE 판 · 엔진이 바뀌어(md5) 판 사이 중복 막기(rc_standing_known)를 지날 때.
##   ② 열 추가(P4 기저 풀 v4 관문 재료 · 성과 수치 없음): track · origin(인계 origin · 없으면 lane · 시드 = seed) · own_spec · own_spec_md5 · families · source_rounds ·
##     superfan_pass_p2(그 항목 superfan 기록 중 kind = pass 이고 codes 에 그 code 가 있는 것의 p2 id 들) · paper_title · paper_url(항목 paper = 칸 사양 root_paper).
##   ③(출시 전 수리 · 격리 점검 M1 · 판단 T4 C-20261113-035): own_spec_engine = 엔진 속성(행 갈래 own_spec ∨ 엔진 폴더에 own_spec.json) — origin(시드 = seed)과 따로 둔다.
##     자체 사양 행의 families · source_rounds · own_spec 이 인계 기록에 없으면(시드 · 손 항목 · 옛 줄) 그 자리에서 채운다(families = own_spec.json core.families ·
##     형식 · core md5 확인 / source_rounds = .rcs_own_source — 엔진 md5 ∪ 계보). 못 채우면 own_resolved = FALSE(기저 풀이 own_spec_unresolved 로 뺀다 · fail-closed).
##     family_root = 항목 계보(자체 사양 = own_spec family_root · 레인 = paper_key). registry_path = 원천 라운드 판독용 등록부(채울 때만 읽는다).
rc_standing_qualified <- function(program = "P1_RETURN", root = rc_root(), sa_root = Sys.getenv("RC_SA_ROOT", root), registry_path = NULL) {
  fs <- unique(c(Sys.glob(file.path(sa_root, "stage_artifacts/programs", program, "*", "standing_ledger.jsonl")),
                 Sys.glob(file.path(root, "stage_artifacts/programs", program, "*", "standing_ledger.jsonl"))))
  rows <- list()
  jn <- function(x) { v <- as.character(unlist(x)); v <- v[!is.na(v) & nzchar(v)]; paste(v, collapse = ",") }
  SRC <- NULL; src_of <- function() { if (is.null(SRC)) SRC <<- tryCatch(rc_standing_source_cells(program, root, registry_path), error = function(e) e); SRC }
  for (f in fs) {
    recs <- tryCatch(rc_standing_ledger_read(f), error = function(e) { warning("[round_core standing] 사슬이 끊긴 원장은 읽지 않는다: ", f); NULL })
    if (is.null(recs)) next
    ## 원장의 입구 갈래 — 줄 머리 track(v4) · 없으면 원장 옆 사전등록의 standing_cfg(표식 없음 = lane)
    trk_f <- local({ p <- tryCatch(rc_json_read(file.path(dirname(f), "prereg.json")), error = function(e) NULL)
                     if (is.list(p)) .rcs_track_of(p[["spec"]][["standing_cfg"]]) else "lane" })
    for (it in rc_standing_items(recs)) {
      v <- it[["verdict"]]; if (is.null(v)) next                       # v3: 미달 판정도 모은다(최신 판 우선 판독용) — 통과만 남기는 것은 아래
      ms <- Filter(.rcs_meas_ok, it[["measures"]]); art <- if (length(ms)) .rcs_str(ms[[length(ms)]][["artifacts"]]) else NA_character_
      if (is.na(art) && !is.null(it[["source_results"]])) art <- tryCatch(rc_json_read(file.path(rc_abs(it[["source_results"]], root), it[["code"]], "eval.json"))[["artifacts"]],
                                                                       error = function(e) NA_character_) %||% NA_character_
      ep <- .rcs_str(it[["engine_path"]]); em <- .rcs_str(it[["engine_md5"]])
      now <- if (!is.na(ep) && file.exists(rc_abs(ep, root))) rc_md5(rc_abs(ep, root)) else NA_character_
      csp <- .rcs_str(it[["cell_spec"]]); cmd <- .rcs_str(it[["cell_spec_md5"]]); con <- rc_standing_construction(csp, cmd, root)
      ho <- it[["handoff"]]; if (!is.list(ho)) ho <- list()
      org <- if (identical(.rcs_str(it[["source"]]), "seed")) "seed" else .rcs_or(.rcs_str(ho[["origin"]]), "lane")
      trk <- .rcs_or(.rcs_str(it[["track"]]), trk_f); fam <- .rcs_str(it[["family_root"]])
      ea <- if (is.na(ep)) NA_character_ else rc_abs(.rcs_repo_rel(ep, root), root)
      own <- identical(trk, "own_spec") || identical(.rcs_str(ho[["origin"]]), "own_spec") || (!is.na(ea) && file.exists(file.path(dirname(ea), "own_spec.json")))
      oi <- if (own && (is.null(ho[["families"]]) || is.null(ho[["own_spec"]]))) .rcs_own_info(ea, root) else NULL
      fams <- if (!own) NA_character_ else if (!is.null(ho[["families"]])) jn(ho[["families"]]) else if (isTRUE(oi$ok)) jn(oi$families) else NA_character_
      srcr <- if (!own) NA_character_ else if (!is.null(ho[["source_rounds"]])) jn(ho[["source_rounds"]]) else {
        S <- src_of(); if (inherits(S, "error")) NA_character_ else jn(.rcs_own_source(S, em, fam)$rounds) }
      ores <- own && !is.na(fams) && nzchar(fams) && !is.na(srcr)
      sfp <- unlist(lapply(it[["superfan"]], function(s) if (identical(.rcs_str(s[["kind"]]), "pass") && it[["code"]] %in% as.character(unlist(s[["codes"]])))
                                                         .rcs_str(s[["p2"]]) else NULL))
      rows[[length(rows) + 1L]] <- data.table(round_id = .rcs_str(it[["round_id"]]), edition = suppressWarnings(as.integer(.rcs_str(it[["edition"]]))),
                                              code = .rcs_str(it[["code"]]), engine = .rcs_str(it[["engine"]]), engine_path = if (is.na(ep)) NA_character_ else .rcs_repo_rel(ep, root),
                                              engine_md5 = em, engine_same = !is.na(now) && identical(now, em), artifacts = .rcs_str(art),
                                              paper_key = .rcs_str(it[["paper"]][["paper_key"]]), verdict_at = .rcs_str(v[["at"]]), ledger = gsub("\\\\", "/", f),
                                              uc_vis = suppressWarnings(as.numeric(.rcs_str(v[["visible"]][["uc_vis"]]))),   # 보는 창 상승 포착(판정 기록 · P4 기저 풀 현금 기계 판독)
                                              cell_spec = if (is.na(csp)) NA_character_ else .rcs_repo_rel(csp, root), cell_spec_md5 = cmd,
                                              construction = con$construction, treatment_axes = paste(con$axes, collapse = ","), construction_why = con$why,
                                              track = trk, origin = org,
                                              own_spec = if (!own) NA_character_ else .rcs_or(.rcs_str(ho[["own_spec"]]), .rcs_or(.rcs_str(oi$own_spec), NA_character_)),
                                              own_spec_md5 = if (!own) NA_character_ else .rcs_or(.rcs_str(ho[["own_spec_md5"]]), .rcs_or(.rcs_str(oi$own_spec_md5), NA_character_)),
                                              families = fams, source_rounds = srcr, own_spec_engine = own, own_resolved = ores, family_root = fam,
                                              superfan_pass_p2 = jn(sfp), paper_title = .rcs_str(it[["paper"]][["title"]]), paper_url = .rcs_str(it[["paper"]][["url"]]),
                                              .q = isTRUE(v[["qualify"]]))
    }
  }
  if (length(rows)) {
    Q <- rbindlist(rows, fill = TRUE)
    Q[, .grp := ifelse(is.na(engine_path) | is.na(construction), paste0("solo:", round_id, ":", code),
                       paste0(engine_path, "|", ifelse(construction == "treatment", paste0("treatment:", treatment_axes), construction)))]
    Q[, .ed := ifelse(is.na(edition), -Inf, as.numeric(edition))]
    Q[, .latest := .ed == max(.ed), by = .(.grp, track)]                 # v4: 판 번호 비교 = 같은 갈래 안
    Q <- Q[.latest == TRUE]
    Q[, .ntr := uniqueN(track), by = .grp]
    Q[, .allq := all(.q), by = .grp]
    Q[, .vt := as.numeric(.rcs_time_vec(verdict_at))]
    ## 두 갈래 이상에 걸친 칸 — 모든 갈래의 최신 판정이 통과일 때만 · 행 = 판정 시각이 가장 늦은 갈래(시각 판독 불가 = 가장 이른 것으로 · 같으면 갈래 이름 순)
    Q[, .pick := NA_character_]
    if (any(Q$.ntr > 1L)) Q[.ntr > 1L, .pick := { o <- order(-ifelse(is.na(.vt), -Inf, .vt), track); track[o][1] }, by = .grp]
    Q <- Q[.q & (.ntr == 1L | (.allq & ((track == .pick) %in% TRUE)))]
    Q[, c(".q", ".grp", ".ed", ".latest", ".ntr", ".allq", ".vt", ".pick") := NULL]
    Q
  } else
    data.table(round_id = character(0), edition = integer(0), code = character(0), engine = character(0), engine_path = character(0),
               engine_md5 = character(0), engine_same = logical(0), artifacts = character(0), paper_key = character(0), verdict_at = character(0), ledger = character(0),
               uc_vis = numeric(0), cell_spec = character(0), cell_spec_md5 = character(0), construction = character(0), treatment_axes = character(0),
               construction_why = character(0), track = character(0), origin = character(0), own_spec = character(0), own_spec_md5 = character(0),
               families = character(0), source_rounds = character(0), own_spec_engine = logical(0), own_resolved = logical(0), family_root = character(0),
               superfan_pass_p2 = character(0), paper_title = character(0), paper_url = character(0))
}
## 시각 문자열 벡터 → POSIXct(판독 불가 = NA) — 원장 'at' 형식(%Y-%m-%dT%H:%M:%S%z)
.rcs_time_vec <- function(s) { s <- as.character(s); out <- suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z")); out[is.na(s) | !nzchar(s)] <- NA; out }
## 구성 판독(v2 · 11-11 판단 T1 C-20261111-001) — 통과 칸의 사양이 그 엔진의 표준 구성(등록된 생성 함수 rc_p1_cell_spec 이 같은 엔진에 만드는 칸)과
##   처치 축에서 같은가. 처치 축 = P4 블록 어휘의 칸 축(p4.R RC_P4_KEY_BLOCKS 의 이름 — 단일 출처) + base_signal(종류 · 경로) — 고정 축(fixed_axes) ·
##   메타 키(code · label · 회계 …)는 보지 않는다(비교 = p4.R::rc_p4_spec_diff 정규화 그대로).
##   반환 list(construction = "standard" | "treatment" | NA, axes = 표준 구성과 다른 처치 축, why). 사양 없음 · md5 ≠ 넣을 때 · 판독 · 생성 실패 = NA —
##   기저 풀은 NA 칸을 맨 엔진 행에 합치지 않고 자격도 주지 않는다(fail-closed · construction_unknown).
rc_standing_construction <- function(cell_spec, cell_spec_md5 = NA_character_, root = rc_root()) {
  na <- function(why) list(construction = NA_character_, axes = character(0), why = why)
  p <- .rcs_str(cell_spec); if (is.na(p)) return(na("cell_spec 없음(공유 측정 항목)"))
  f <- rc_abs(.rcs_repo_rel(p, root), root); if (!file.exists(f)) return(na(paste0("칸 사양 없음: ", p)))
  m <- .rcs_str(cell_spec_md5); if (!is.na(m) && !identical(rc_md5(f), m)) return(na("칸 사양 md5 ≠ 원장(넣을 때)"))
  s <- tryCatch(rc_json_read(f), error = function(e) NULL)
  ep <- if (is.list(s)) .rcs_str(s[["base_signal"]][["path"]]) else NA_character_
  if (is.na(ep)) return(na("칸 사양 판독 불가 · base_signal.path 없음"))
  ea <- rc_abs(.rcs_repo_rel(ep, root), root); if (!file.exists(ea)) return(na("엔진 파일 없음"))
  std <- tryCatch(rc_p1_cell_spec("construction_probe", ea, list(url = "-", title = "-", paper_key = "-"), "-", 1L, "construction probe", root = root),
                  error = function(e) NULL)
  if (!is.list(std)) return(na("표준 구성 생성 실패(rc_p1_cell_spec)"))
  d <- tryCatch(rc_p4_spec_diff(std, s, "base", root = root, pool = NULL), error = function(e) NULL)
  if (is.null(d)) return(na("구성 비교 실패(rc_p4_spec_diff)"))
  ax <- intersect(d$changed, c(names(RC_P4_KEY_BLOCKS), "base_signal"))
  list(construction = if (length(ax)) "treatment" else "standard", axes = ax, why = "")
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
  ## v2(11-11 · P1S01 격리 점검 R-2): 부호 층 함수는 커넥터처럼 본다 — 호출 토큰만이 아니라 식 나무의 기호 참조(함수 값 · 별칭 대입 · $ · ::) ·
  ##   간접 호출 문자열(do.call · match.fun · get 류)까지(v1 은 호출 토큰만 봐서 탐침 8종 중 4종을 놓쳤다 — v1 이 잡는 형태는 v2 도 전부 잡는다)
  orl <- unique(c(rc_standing_orient_refs(ex), txt[is_sym & tolower(txt) %in% RC_STANDING_SIGN_IDS]))
  fc <- rc_standing_fdb_calls(ex)                                   # 호출마다 방향 인자 판독(식 나무 — 주석 · 문자열 제외)
  fdb <- unique(fc$fn); dyn <- fc[!fc$static, , drop = FALSE]
  list(ok = TRUE, error = NA_character_, outputs = sort(unique(outs)),
       orientation = if (length(orl)) "orientation_layer" else if (nrow(dyn)) "factor_db_asof" else if (nrow(fc)) "factor_db_static" else "engine_native",
       factor_db = fdb, factor_db_calls = fc, orientation_tokens = orl,
       lines = sort(unique(pd$line1[is_sym & txt %in% c(fdb, orl)])))
}
## 부호 층 함수 참조(v2 · R-2) — 식 나무에서 이름이 RC_STANDING_ORIENT_CALLS 인 기호(호출 머리 · 함수 값 · 별칭 대입의 오른쪽 · $ · :: 꼬리)와
##   간접 호출 함수(.RCS_INDIRECT_FNS)의 문자열 인자를 모은다. 주석 · 다른 문자열 · 인자 이름(list(align_factor_direction = 1))은 보지 않는다.
.RCS_INDIRECT_FNS <- c("do.call", "match.fun", "get", "get0", "mget", "getFunction", "exists")
rc_standing_orient_refs <- function(ex, names = RC_STANDING_ORIENT_CALLS) {
  hit <- character(0)
  head_name <- function(f) {
    if (is.symbol(f)) return(as.character(f))
    if (is.call(f) && is.symbol(f[[1]]) && as.character(f[[1]]) %in% c("$", "::", ":::", "@") && length(f) >= 3L && is.symbol(f[[length(f)]]))
      return(as.character(f[[length(f)]]))
    NA_character_
  }
  walk <- function(e) {
    if (is.symbol(e)) { s <- as.character(e); if (s %in% names) hit <<- c(hit, s); return(invisible(NULL)) }
    if (is.call(e)) {
      fn <- head_name(e[[1]])
      if (!is.na(fn) && fn %in% .RCS_INDIRECT_FNS) for (i in seq_along(e)[-1]) {
        a <- e[[i]]; if (!missing(a) && is.character(a) && length(a) >= 1L && any(a %in% names)) hit <<- c(hit, a[a %in% names]) }
      for (i in seq_along(e)) { a <- e[[i]]; if (!missing(a)) walk(a) }
    } else if (is.pairlist(e)) { for (a in as.list(e)) if (!missing(a)) walk(a) }
    invisible(NULL)
  }
  for (x in as.list(ex)) walk(x)
  unique(hit)
}
## 커넥터 · 결합용 뷰 호출의 방향 인자 — 식 나무를 훑어 호출마다 (함수 · 방향 · 정적 여부 · 근거)를 낸다.
##   정적 = 방향 인자가 문자열 상수 "registry" | "defensive" 일 때만. 인자 없음(= 기본 ic_asof) · "ic_asof" · 변수 · 식 · 위치 대응 실패 ·
##   함수 값 참조(lapply(x, load_month_factors) 등) · do.call/match.fun 문자열 = 동적(정적으로 확인할 수 없으면 동적 — 보수 판정).
rc_standing_fdb_calls <- function(ex) {
  out <- list(); F <- RC_STANDING_FDB_CALLS
  rec <- function(fn, dir, why) out[[length(out) + 1L]] <<- data.frame(fn = fn, direction = dir, static = dir %in% RC_STANDING_FDB_STATIC_DIR,
                                                                         why = why, stringsAsFactors = FALSE)
  fname <- function(f) {
    if (is.symbol(f)) return(as.character(f))
    if (is.call(f) && is.symbol(f[[1]]) && as.character(f[[1]]) %in% c("$", "::", ":::", "@") && length(f) >= 3L && is.symbol(f[[length(f)]]))
      return(as.character(f[[length(f)]]))
    NA_character_
  }
  one_call <- function(nm, e) {
    m <- tryCatch(match.call(.RCS_FDB_FORMALS[[nm]], e, expand.dots = FALSE), error = function(z) NULL)
    if (is.null(m)) return(rec(nm, NA_character_, "argument_match_failed"))
    d <- m[["direction"]]
    if (is.null(d)) rec(nm, "ic_asof", "default")
    else if (is.character(d) && length(d) == 1L && !is.na(d)) rec(nm, d, "constant")
    else rec(nm, NA_character_, "non_constant")
  }
  walk <- function(e) {
    if (is.call(e)) {
      f <- e[[1]]; nm <- fname(f)
      if (!is.na(nm) && nm %in% F) one_call(nm, e)
      if (!is.na(nm) && nm %in% c("do.call", "match.fun", "get", "getFunction") && length(e) >= 2L && is.character(e[[2]]) && e[[2]][1] %in% F)
        rec(e[[2]][1], NA_character_, "indirect_call")
      if (is.call(f)) { if (is.na(nm)) walk(f) else for (i in seq_along(f)[-1]) if (!is.symbol(f[[i]])) walk(f[[i]]) }
      for (i in seq_along(e)[-1]) { a <- e[[i]]; if (!missing(a)) walk(a) }
    } else if (is.pairlist(e)) { for (a in as.list(e)) if (!missing(a)) walk(a)
    } else if (is.symbol(e) && as.character(e) %in% F) rec(as.character(e), NA_character_, "function_value")
  }
  for (x in as.list(ex)) walk(x)
  if (length(out)) do.call(rbind, out) else data.frame(fn = character(0), direction = character(0), static = logical(0), why = character(0), stringsAsFactors = FALSE)
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
## 폭 문턱(v3 · breadth_insufficient) — 보유 상한 × 배수. 숫자는 정본에서만 읽는다(새 숫자 없음):
##   보유 상한 = constraint_defaults.json::tier_soft_deployment.max_names · 배수 = 그 판 측정 축 epoch 의 effective_start.breadth_mult
##   (contracts/measurement_axis.R::ma_epoch — 계약의 형식 검사를 그대로 탄다). 판독 실패 · 규칙 없는 축 = 멈춘다(기본값으로 접지 않는다).
rc_standing_breadth_need <- function(axis, root = rc_root()) {
  ax <- .rcs_str(axis); if (is.na(ax)) .rcs_err("폭 문턱: 측정 축 id 가 없다(standing_cfg.generator_pin.canon.measurement_axis)")
  mx <- tryCatch(rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::tier_soft_deployment.max_names", root), error = function(e) .rcs_err("폭 문턱: 보유 상한 판독 실패 — ", conditionMessage(e)))
  mx <- suppressWarnings(as.numeric(unlist(mx)))
  if (length(mx) != 1L || !is.finite(mx) || mx < 1) .rcs_err("폭 문턱: 보유 상한(tier_soft_deployment.max_names)이 1 이상 수 하나가 아니다")
  if (!identical(.RCS$ma_root, root)) {
    f <- file.path(root, "02_Infrastructure/contracts/measurement_axis.R"); if (!file.exists(f)) .rcs_err("폭 문턱: 측정 축 계약 없음: ", f)
    e <- new.env(parent = globalenv()); invisible(utils::capture.output(suppressMessages(sys.source(f, envir = e, keep.source = FALSE))))
    .RCS$ma <- e; .RCS$ma_root <- root
  }
  ep <- tryCatch(.RCS$ma$ma_epoch(ax, root), error = function(e) .rcs_err("폭 문턱: 측정 축 ", ax, " 판독 실패 — ", conditionMessage(e)))
  m <- suppressWarnings(as.numeric(unlist(ep[["effective_start"]][["breadth_mult"]])))
  if (length(m) != 1L || !is.finite(m)) .rcs_err("폭 문턱: 측정 축 ", ax, " 에 실효 시작 배수(effective_start.breadth_mult)가 없다 — 문턱을 지어내지 않는다")
  list(axis = ax, max_names = mx, mult = m, need = mx * m)
}
## 후보 폭(v3) — 레인 측정 산출의 점수 패널(run_paper_replication.R 이 유니버스 적용 뒤 저장) 에서 Date · Ticker 두 열만 읽는다(점수 · 성과 없음).
##   τ_D 절단을 먼저 하고 센다 — τ_D 뒤 날짜의 폭은 판정에 닿지 않는다. 날짜별 폭 = 서로 다른 종목 수(점수 유한 여부는 보지 않는다 — 필요조건이라 느슨한 쪽).
##   반환 ok = TRUE(충족 날 ≥ 1) | FALSE(0 — 사유) | NA(패널 없음 · 판독 불가 · 보는 창 날짜 0 — 사유를 붙이지 않는다)
## 보는 창 패널 판독(폭 · 격자 공용 — 파일을 한 번만 읽는다) — list(P = data.table(d, t) | NULL, why)
.rcs_panel_vis <- function(artifacts, tau) {
  na <- function(why) list(P = NULL, why = why)
  a <- .rcs_str(artifacts); if (is.na(a)) return(na("no_artifacts"))
  f <- file.path(a, "factors_panel.parquet"); if (!file.exists(f)) return(na("panel_missing"))
  P <- tryCatch(as.data.table(arrow::read_parquet(f, col_select = c("Date", "Ticker"), mmap = FALSE)), error = function(e) NULL)
  if (is.null(P) || !all(c("Date", "Ticker") %in% names(P))) return(na("panel_unreadable"))
  dd <- tryCatch(as.Date(P$Date), error = function(e) NULL)
  if (is.null(dd) || length(dd) != nrow(P)) return(na("panel_date_unreadable"))
  P <- data.table(d = dd, t = as.character(P$Ticker))
  P <- P[!is.na(d) & d <= as.Date(tau)]   # τ_D 절단(세기 전에) — rc_standing_breadth:tau_cut
  P <- P[!is.na(t) & nzchar(t)]
  if (!nrow(P)) return(na("no_visible_dates"))
  list(P = P, why = "ok")
}
.rcs_breadth_of <- function(V, need) {
  if (is.null(V$P)) return(list(ok = NA, why = V$why, n_met = NA_integer_, n_vis = 0L, max = NA_integer_, need = need))
  W <- V$P[, .(w = uniqueN(t)), by = d]; nm <- sum(W$w >= need)
  list(ok = nm > 0L, why = if (nm > 0L) "ok" else "insufficient", n_met = as.integer(nm), n_vis = nrow(W), max = as.integer(max(W$w)), need = need)
}
rc_standing_breadth <- function(artifacts, tau, need) .rcs_breadth_of(.rcs_panel_vis(artifacts, tau), need)
.rcs_breadth_str <- function(b) if (is.na(b$ok)) paste0("na:", b$why) else sprintf("%d/%d(max %d · need %s)", b$n_met, b$n_vis, b$max, format(b$need))
## 신호 격자(v3 · 판단 Superfan T4 R-20261111-008) — 보는 창 신호일을 달력 월로 묶어 한 달 최대 신호일 수를 센다(모수 없음 · 2 이상 = 조밀).
##   ok = TRUE(모든 달 ≤ 1 = 월 격자 · 분기 · 연간 포함) | FALSE(한 달에 2개 이상 — 주간 · 일간) | NA(판독 불가 — 사유 없음)
.rcs_grid_of <- function(V) {
  if (is.null(V$P)) return(list(ok = NA, why = V$why, max = NA_integer_))
  G <- unique(V$P[, .(d)])[, .(n = .N), by = .(ym = format(d, "%Y-%m"))]; mx <- as.integer(max(G$n))
  list(ok = mx <= 1L, why = if (mx <= 1L) "month" else "dense", max = mx)
}
rc_standing_grid <- function(artifacts, tau) .rcs_grid_of(.rcs_panel_vis(artifacts, tau))
.rcs_grid_str <- function(g) if (is.na(g$ok)) paste0("na:", g$why) else if (isTRUE(g$ok)) "month" else sprintf("dense(max %d)", g$max)
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
## 팩터 DB 판(2026-11-10) — 계약 factor_db_vintage.R 과 원장(기본 06_Registry/factor_db_vintage.json · 시험 = ledger_path 또는 RC_FDV_LEDGER)이
##   둘 다 있을 때만 판정한다(없으면 skipped). 반환 list(stale = TRUE|FALSE|NA, reason)
rc_standing_fdv <- function(artifacts, root = rc_root(), ledger_path = NULL) {
  cf <- file.path(root, "02_Infrastructure/contracts/factor_db_vintage.R")
  lp <- ledger_path %||% { e <- Sys.getenv("RC_FDV_LEDGER", ""); if (nzchar(e)) e else file.path(root, "06_Registry/factor_db_vintage.json") }
  a <- .rcs_str(artifacts)
  if (!file.exists(cf) || !file.exists(lp)) return(list(stale = NA, reason = "skipped"))
  if (is.na(a)) return(list(stale = NA, reason = "no_artifacts"))
  if (!identical(.RCS$fdv_root, root)) { e <- new.env(parent = globalenv())
    invisible(utils::capture.output(suppressMessages(sys.source(cf, envir = e, keep.source = FALSE)))); .RCS$fdv <- e; .RCS$fdv_root <- root }
  r <- tryCatch(.RCS$fdv$fdv_stale(a, root, ledger = .RCS$fdv$fdv_ledger(root, path = lp)), error = function(e) list(stale = NA, reason = paste("error:", conditionMessage(e))))
  list(stale = if (is.logical(r$stale) && length(r$stale) == 1L) r$stale else NA, reason = .rcs_str(r$reason))
}
## 허용 방향 층 — engine_native 를 허용하면 factor_db_static(등록부에 미리 선언된 정적 방향)도 허용한다(동적 부호가 아니다)
rc_standing_orient_admitted <- function(admit) { a <- unlist(admit); if ("engine_native" %in% a) union(a, "factor_db_static") else a }
## 디렉터리 1개 판독 — 모든 실패 사유를 모은다(첫 사유에서 멈추지 않는다)
.rcs_scan_dir <- function(d, H, sc, root, tau, need) {
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
      else if (!("FACTORS" %in% st$outputs)) rs <- c(rs, "portfolio_only_base")   # v3 — 산출 대입이 PORTFOLIO 뿐(비면 위 사유 그대로)
      if (!(st$orientation %in% rc_standing_orient_admitted(sc[["orientation_admit"]]))) rs <- c(rs, "dynamic_sign")
    }
  }
  ## v3 후보 폭 — 점수 패널을 내는 엔진만 잰다(포트폴리오만 내는 엔진 = na:portfolio_only). 판독 불가(na:…)는 사유 없음(막지 않는다)
  ##   + 신호 격자(base_off_month_grid · 같은 패널 · 같은 판독 불가 규칙)
  vna <- function(why) list(P = NULL, why = why)
  V <- if (!has_eng) vna("no_engine") else if (!isTRUE(st$ok)) vna("engine_parse_failed") else if (!length(st$outputs)) vna("output_contract_unknown") else
    if (!("FACTORS" %in% st$outputs)) vna("portfolio_only") else if (!nrow(h)) vna("no_handoff") else .rcs_panel_vis(hv("artifacts"), tau)
  br <- .rcs_breadth_of(V, need); gr <- .rcs_grid_of(V); rm(V)
  if (isFALSE(br$ok)) rs <- c(rs, "breadth_insufficient")
  if (isFALSE(gr$ok)) rs <- c(rs, "base_off_month_grid")
  ll <- if (nrow(h)) rc_standing_long_leg(hv("artifacts"), tau) else list(ok = NA, why = "no_handoff", n_dates = 0L, n_absent = NA_integer_)
  if (nrow(h)) { if (isFALSE(ll$ok)) rs <- c(rs, "long_leg_absent") else if (is.na(ll$ok)) rs <- c(rs, "long_leg_unverifiable") }
  pit <- if (has_eng && isTRUE(sc[["pit_static"]])) rc_standing_pit(ep, root) else list(clean = NA, checks = character(0), error = NA_character_)
  if (has_eng && isTRUE(sc[["pit_static"]]) && !isTRUE(pit$clean)) rs <- c(rs, "pit_static")
  fdv <- if (nrow(h)) rc_standing_fdv(hv("artifacts"), root) else list(stale = NA, reason = "no_handoff")
  ## (11-10 Q 검토) 레인 측정이 팩터 DB 수리 전이어도 입구에서 빼지 않는다 — 상설 측정은 엔진 코드를 지금의 팩터 DB 위에서 새로 돌리고
  ##   입구는 성과를 읽지 않는다(레인의 옛 측정값에 기대지 않는다). 빼면 레인이 다시 재기 전까지 판이 통째로 멈춘다(막지 않는다 · v10.2 5항).
  ##   표식만 남긴다(열 factor_db_vintage = stale | current | na:…). 낡은 측정의 소비는 A 자격 관문과 P4 기저 풀(등급 경로)이 막는다.
  pa <- if (nrow(h)) rc_standing_paper(d, h) else list(ok = FALSE, url = NA_character_, title = NA_character_, paper_key = NA_character_, url_source = NA_character_)
  if (nrow(h) && !isTRUE(pa$ok)) rs <- c(rs, "paper_meta_missing")
  data.table(dir = nm, engine = rc_rel(ep, root), engine_md5 = emd5, base_id = .rcs_str(hv("base_id")), program = .rcs_str(hv("program")),
             where = .rcs_str(hv("where")), at = .rcs_str(hv("at")), eligible = !length(rs), reasons = paste(unique(rs), collapse = ";"),
             orientation = if (is.null(st)) NA_character_ else st$orientation,
             orientation_evidence = if (is.null(st)) NA_character_ else paste(c(st$factor_db, st$orientation_tokens), collapse = ","),
             outputs = if (is.null(st)) NA_character_ else paste(st$outputs, collapse = ","),
             long_leg = if (is.na(ll$n_absent)) ll$why else sprintf("%d/%d", ll$n_absent, ll$n_dates),
             breadth = .rcs_breadth_str(br), grid = .rcs_grid_str(gr),
             pit = if (isTRUE(pit$clean)) "clean" else if (isFALSE(pit$clean)) paste(pit$checks, collapse = ",") else "unscanned",
             factor_db_vintage = if (isTRUE(fdv$stale)) "stale" else if (isFALSE(fdv$stale)) "current" else paste0("na:", fdv$reason),
             paper_key = pa$paper_key, title = pa$title, url = pa$url, url_source = pa$url_source,
             fidelity = fid, audit_item = aitem, audit_file = afile, has_short = hv("has_short"), artifacts = .rcs_str(hv("artifacts")))
}
## 레인 산출 전체 판독 — 디렉터리마다 1행(입구 통과 = eligible · 아니면 reasons). 성과 수치는 읽지 않는다(등급 · PORT_t · CR)
##   v3: axis = 그 판의 측정 축 id(rc_standing_scan 이 standing_cfg.generator_pin.canon.measurement_axis 를 넘긴다) — 폭 문턱의 배수를 정한다.
##     NULL 이면 정본 활성 축(constraint_defaults.json::measurement_axis.active — 등록된 판은 맥락 검사가 핀 = 활성을 이미 확인한다)
##   v4: scan.source = "own_spec" 이면 자체 사양 입구(.rcs_scan_own_dir)로 간다 — 레인 인계 · 폭 · 격자 · 롱 레그 판독이 없다(레인 갈래 동작은 v3 그대로).
##     decision_register · src = 자체 사양 입구만(선언 검사 · 원천 칸 표 — src 를 넘기면 다시 읽지 않는다) · 레인 갈래는 쓰지 않는다
rc_standing_lane_candidates <- function(sc, root = rc_root(), registry_path = NULL, tau = "2022-12-31", lane_root = NULL, axis = NULL,
                                        decision_register = NULL, src = NULL) {
  lr <- lane_root %||% rc_abs(sc[["lane_root"]], root)
  if (identical(.rcs_str(sc[["source"]]), "own_spec")) return(rc_standing_own_candidates(sc, root, registry_path, tau, lr, decision_register = decision_register, src = src))
  dirs <- sort(Sys.glob(file.path(lr, sc[["dir_glob"]] %||% "RP_AUTO_*"))); dirs <- dirs[dir.exists(dirs)]
  H <- rc_standing_handoffs(pr_load(root, registry_path))
  ax <- axis %||% rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active", root)
  need <- rc_standing_breadth_need(ax, root)$need   # 판독 실패 = 스캔 전체를 멈춘다(fail-closed)
  if (!length(dirs)) return(data.table(dir = character(0), eligible = logical(0), reasons = character(0), engine_md5 = character(0), at = character(0)))
  rbindlist(lapply(dirs, .rcs_scan_dir, H = H, sc = sc, root = root, tau = tau, need = need), fill = TRUE)
}

## ── v4 자체 사양 입구(scan.source = own_spec) ──────────────────────────────────────────
## 원천 라운드의 칸(v4) — 등록부 프로그램 라운드 중 등록된 사전등록(파일 md5 = 등록부 prereg_md5 · 상설 판 제외)의 칸마다
##   칸 사양(md5 = 사전등록 칸 md5) base_signal.path 의 엔진과 그 엔진의 등록 md5(사전등록 핀 pins.files — 측정 전에 고정된 바이트)를 모은다.
##   반환 data.table(round_id, code, role, spec(저장소 상대), engine_path(저장소 상대), engine_md5, family_root, n_family). 성과를 읽지 않는다(사전등록 · 칸 사양만).
##   핀에 그 엔진이 없는 사전등록(옛 형식 — P1R01 · P1R02)은 싣지 않는다(등록 바이트를 모르면 같은 엔진이라고 단정하지 않는다).
##   출시 전 수리(격리 점검 R4 (ii)): 속성 rounds = data.table(round_id, n_cells = 사전등록 칸 수 — 사슬 원천 시행 · enqueue 시행 수가 같은 수를 센다) ·
##     unverified = data.table(round_id, engine_md5, why) — 사전등록 md5 ≠ 등록부 · 칸 사양 검증 실패(파일 없음 · md5 ≠ 등록 · 판독 불가 · 엔진 경로 없음)인 라운드의
##     핀 md5 가운데 검증된 칸이 덮지 못한 것(그 엔진을 쟀을 수 있는데 확인이 안 된다) · 사전등록 파일 없음 · 판독 불가 = engine_md5 "*"(모든 엔진 — fail-closed).
rc_standing_source_cells <- function(program = "P1_RETURN", root = rc_root(), registry_path = NULL) {
  R <- pr_get(pr_load(root, registry_path), program)[["rounds"]] %||% list()
  sar <- Sys.getenv("RC_SA_ROOT", root); rows <- list(); rn <- list(); uv <- list()
  unv <- function(rid, m, why) { m <- unique(m[!is.na(m) & nzchar(m)]); if (length(m)) uv[[length(uv) + 1L]] <<- data.table(round_id = rid, engine_md5 = m, why = why) }
  for (r in R) {
    rid <- .rcs_str(r[["round_id"]]); rel <- .rcs_str(r[["prereg"]]); if (is.na(rid) || is.na(rel)) next
    f <- c(file.path(sar, rel), rc_abs(rel, root)); f <- f[file.exists(f)][1]
    if (is.na(f)) { unv(rid, "*", "사전등록 파일 없음"); next }
    p <- tryCatch(rc_json_read(f), error = function(e) NULL)
    if (!is.list(p)) { unv(rid, "*", "사전등록 판독 불가"); next }
    if (isTRUE(p[["spec"]][["standing"]])) next
    pins <- p[["pins"]][["files"]] %||% list()
    pp <- vapply(pins, function(x) .rcs_or(.rcs_str(x[["path"]]), ""), ""); pm <- vapply(pins, function(x) .rcs_or(.rcs_str(x[["md5"]]), NA_character_), "")
    pp <- vapply(pp, function(x) if (nzchar(x)) .rcs_repo_rel(x, root) else "", "")
    rm5 <- .rcs_str(r[["prereg_md5"]])
    if (is.na(rm5) || !identical(rc_md5(f), rm5)) { unv(rid, pm, "사전등록 md5 ≠ 등록부(R2)"); next }          # 등록본이 아니다(R2)
    cells <- p[["cells"]] %||% list(); rn[[length(rn) + 1L]] <- data.table(round_id = rid, n_cells = length(cells))
    okm <- character(0); bad <- FALSE
    for (c in cells) {
      sp <- .rcs_str(c[["spec"]]); if (is.na(sp)) next                                                     # 공유 측정 칸(사양 없음)
      spa <- rc_abs(.rcs_repo_rel(sp, root), root)
      if (!file.exists(spa) || !identical(rc_md5(spa), .rcs_str(c[["md5"]]))) { bad <- TRUE; next }       # 칸 사양 = 등록본(R2)
      cs <- tryCatch(rc_json_read(spa), error = function(e) NULL); if (!is.list(cs)) { bad <- TRUE; next }
      ep <- .rcs_str(cs[["base_signal"]][["path"]]); if (is.na(ep)) { bad <- TRUE; next }
      er <- .rcs_repo_rel(ep, root); k <- match(er, pp); if (is.na(k) || is.na(pm[k])) next                # 핀에 엔진 없음(옛 형식) — 단정하지 않는다
      sa <- cs[["selection_accounting"]]; okm <- c(okm, pm[k])
      rows[[length(rows) + 1L]] <- data.table(round_id = rid, code = .rcs_str(c[["code"]]), role = .rcs_or(.rcs_str(c[["role"]]), "variant"),
                                              spec = .rcs_repo_rel(sp, root), engine_path = er, engine_md5 = pm[k], family_root = .rcs_str(sa[["family_root"]]),
                                              n_family = suppressWarnings(as.integer(.rcs_str(sa[["n_family_at_registration"]]))))
    }
    if (bad) unv(rid, setdiff(pm, okm), "칸 사양 검증 실패(파일 없음 · md5 ≠ 등록 · 판독 불가 · 엔진 경로 없음)")
  }
  out <- if (length(rows)) rbindlist(rows) else
    data.table(round_id = character(0), code = character(0), role = character(0), spec = character(0), engine_path = character(0), engine_md5 = character(0),
               family_root = character(0), n_family = integer(0))
  setattr(out, "rounds", if (length(rn)) rbindlist(rn) else data.table(round_id = character(0), n_cells = integer(0)))
  setattr(out, "unverified", if (length(uv)) unique(rbindlist(uv)) else data.table(round_id = character(0), engine_md5 = character(0), why = character(0)))
  out
}
## 자체 사양 엔진 하나의 원천 라운드(출시 전 수리 · 판단 T4 C-20261113-035 ② · 036 · 격리 점검 R1 · R4) — src = rc_standing_source_cells 산출(속성 포함)
##   rounds = 이 엔진 md5 를 칸으로 등록한 라운드 ∪ 같은 계보(family_root) 칸을 가진 라운드(역할 무관 — 다시 만든 엔진(새 md5)도 앞선 계보 시행을 물려받는다)
##   md5_rounds = 이 엔진 md5 칸이 있는 라운드 · n_cells = rounds 의 사전등록 칸 수 합(사슬 원천 시행 = 그 라운드 전 칸 — 같은 집합의 크기)
##   remeasure = 이 엔진 md5 를 변형(variant) 칸으로 · 같은 계보로 회계한 원천 칸이 있다(상설 칸 = 그 시행의 재측정 · +1 없음)
##   mismatch = 이 엔진 md5 칸 가운데 계보 ≠ fam 인 칸의 라운드(입구 own_spec_family_mismatch) · unverified = 검증 불가 라운드(이 md5 또는 "*")
.rcs_own_source <- function(src, emd5, fam) {
  S <- if (is.data.frame(src)) as.data.table(src) else data.table(round_id = character(0), code = character(0), role = character(0), engine_md5 = character(0), family_root = character(0))
  e0 <- .rcs_str(emd5); f0 <- .rcs_str(fam)
  mc <- if (!is.na(e0)) S[S$engine_md5 %in% e0] else S[0]
  lc <- if (!is.na(f0)) S[S$family_root %in% f0] else S[0]
  rounds <- sort(unique(c(mc$round_id, lc$round_id)))
  RN <- attr(src, "rounds"); UV <- attr(src, "unverified")
  n <- if (length(rounds) && is.data.frame(RN)) sum(as.integer(RN$n_cells[RN$round_id %in% rounds])) else 0L
  uvr <- if (is.data.frame(UV) && nrow(UV)) as.data.table(UV)[engine_md5 %in% c(e0, "*")] else NULL
  list(rounds = rounds, md5_rounds = sort(unique(mc$round_id)), n_cells = as.integer(n), unknown = setdiff(rounds, if (is.data.frame(RN)) RN$round_id else character(0)),
       remeasure = nrow(mc[mc$role %in% "variant" & mc$family_root %in% f0]) > 0L,
       mismatch = sort(unique(mc$round_id[!(mc$family_root %in% f0)])), unverified = if (is.null(uvr) || !nrow(uvr)) NULL else uvr)
}
## 엔진 옆 own_spec.json 판독(형식 · core md5 = spec_md5 — 생성기 직렬화) — 자격 통과 표 채우기 · 시드 인계 기록이 쓴다(입구 판독은 .rcs_scan_own_dir 가 따로 더 본다)
.rcs_own_info <- function(ea, root) {
  ea <- .rcs_str(ea); f <- if (is.na(ea)) NA_character_ else file.path(dirname(ea), "own_spec.json")
  if (is.na(f) || !file.exists(f)) return(list(exists = FALSE, ok = FALSE, families = character(0)))
  os <- tryCatch(rc_json_read(f), error = function(e) NULL)
  ok <- is.list(os) && identical(.rcs_str(os[["schema"]]), RC_STANDING_OWN_SCHEMA) && is.list(os[["core"]]) && length(os[["core"]]) > 0L &&
    identical(.rcs_own_core_md5(os[["core"]]), .rcs_str(os[["spec_md5"]]))
  gp <- if (ok) .rcs_str(os[["generator"]][["path"]]) else NA_character_
  list(exists = TRUE, ok = ok, own_spec = .rcs_repo_rel(f, root), own_spec_md5 = rc_md5(f), generator = if (is.na(gp)) NA_character_ else .rcs_repo_rel(gp, root),
       families = if (ok) as.character(unlist(os[["core"]][["families"]])) else character(0), family_root = if (ok) .rcs_str(os[["family_root"]]) else NA_character_,
       declared_at = if (ok) .rcs_str(os[["declared_at"]]) else NA_character_, decision = if (ok) .rcs_str(os[["decision"]]) else NA_character_)
}
## 등록부 자체 사양 선언 줄(설계 §3-6 (a) · 격리 점검 R3) — 모든 프로그램 큐 · 소비 목록 · 미분류 보류에서 origin = own_spec 이고 kind ≠ engine 인 줄
##   (kind = engine 줄은 기저 풀 · 레인 스캔이 레인 엔진으로 읽는다 — 선언 줄은 kind = own_spec 으로 적는다). 반환 data.table(engine_path · engine_md5 · at · decl_key) | NULL
##   (열 이름 key 는 data.table() 의 예약 인자라 decl_key 로 적는다 — rc_standing_handoffs 의 ho_key 와 같은 이유)
.rcs_own_declarations <- function(reg, root) {
  one <- function(it) {
    if (!is.list(it) || !identical(.rcs_str(it[["origin"]]), "own_spec") || identical(.rcs_str(it[["kind"]]), "engine")) return(NULL)
    ep <- .rcs_str(it[["engine_path"]]); if (is.na(ep)) return(NULL)
    data.table(engine_path = .rcs_repo_rel(gsub("\\\\", "/", ep), root), engine_md5 = .rcs_str(it[["engine_md5"]]),
               at = .rcs_str(it[["declared_at"]] %||% it[["enqueued_at"]]), decl_key = .rcs_str(it[["key"]]))
  }
  rows <- list()
  for (p in reg[["programs"]] %||% list()) for (w in c("queue", "consumed")) for (it in p[[w]] %||% list()) rows[[length(rows) + 1L]] <- one(it)
  for (it in reg[["paper_routing"]][["unrouted"]] %||% list()) rows[[length(rows) + 1L]] <- one(it)
  rows <- Filter(Negate(is.null), rows)
  if (length(rows)) rbindlist(rows, fill = TRUE) else NULL
}
## 자체 사양 인계 기록(스캔 행 · 시드 공통 — 격리 점검 M1 · 판단 T4 C-035) — 엔진 경로(저장소 밖이면 절대) · 원천 칸 표 S
.rcs_own_handoff <- function(ea, fam, root, S) {
  oi <- .rcs_own_info(ea, root); em <- if (!is.na(ea) && file.exists(ea)) rc_md5(ea) else NA_character_
  o <- .rcs_own_source(S, em, fam)
  c(list(origin = "own_spec", own_spec = .rcs_or(.rcs_str(oi$own_spec), NA_character_), own_spec_md5 = .rcs_or(.rcs_str(oi$own_spec_md5), NA_character_),
         generator = .rcs_or(.rcs_str(oi$generator), NA_character_)),
    if (isTRUE(oi$ok)) list(families = as.list(oi$families)),                     # 판독 불가면 families 를 적지 않는다 — 자격 통과 표가 다시 보고 못 채우면 own_resolved = FALSE
    list(source_rounds = as.list(o$rounds), declared_at = .rcs_or(.rcs_str(oi$declared_at), NA_character_)))
}
## v4 출시 전 수리(격리 점검 R5) — 자체 사양 갈래 판정은 RELEASES.json 의 출시 판 ≥ v4 뒤에만. 출시 전에는 사양 없는 호출의 기본 판(RELEASES 마지막 판 = v3)이
##   상설 원장의 통과를 철학 P2 · 저위험 관문 없이 기저 풀 자격으로 읽는다(v3 rc_standing_qualified 는 원장 형식이 같아 갈래를 모른다). 레인 갈래는 막지 않는다.
.rcs_release_guard <- function(track, releases_path = file.path(dirname(RC_DIR), "RELEASES.json")) {
  if (!identical(track, "own_spec")) return(invisible(TRUE))
  R <- tryCatch(rc_json_read(releases_path), error = function(e) NULL)
  v <- unlist(lapply(R[["releases"]] %||% list(), function(r) if (identical(.rcs_str(r[["status"]]), "released")) .rcs_str(r[["version"]]) else NULL))
  n <- suppressWarnings(as.integer(sub("^v", "", v[!is.na(v) & grepl("^v[0-9]+$", v)])))
  if (!length(n) || max(n) < 4L)
    .rcs_err("자체 사양 갈래 판정 거부 — RELEASES.json 의 출시 판이 v4 미만이다(", if (length(n)) paste0("v", max(n)) else "판독 불가", "). 출시 전에는 v3 기저 풀(사양 없는 호출의 기본 판)이 ",
             "이 원장의 통과를 철학 P2 · 저위험 관문 없이 읽는다 — RELEASES 에 v4 항목을 넣은 뒤 판정한다(격리 점검 R5)")
  invisible(TRUE)
}
## 자체 사양 core md5 — 생성기와 같은 직렬화(fc_engine_gen.R .fce_core_json · fc_combiner_gen.R .fcc_core_json: toJSON auto_unbox · digits NA · null/na "null")의 UTF-8 바이트 md5
.rcs_own_core_md5 <- function(core) .rcs_md5s(as.character(toJSON(core, auto_unbox = TRUE, digits = NA, null = "null", na = "null")))
## 생성기 적재(스캔 안에서 경로마다 한 번) — 새 환경에 sys.source(keep.source = FALSE) · 본문 함수(text_fn)를 꺼낸다(CLI 블록은 sys.source 안에서 돌지 않는다)
.rcs_own_generators <- function(G, root) {
  out <- list()
  for (g in G) {
    p <- .rcs_repo_rel(.rcs_or(.rcs_str(g[["path"]]), ""), root); fn <- .rcs_str(g[["text_fn"]])
    if (!nzchar(p) || !is.null(out[[p]])) next
    f <- rc_abs(p, root)
    if (!file.exists(f)) { out[[p]] <- list(ok = FALSE, why = "generator_file_missing", md5 = NA_character_); next }
    e <- new.env(parent = globalenv())
    ld <- tryCatch({ invisible(utils::capture.output(suppressMessages(sys.source(f, envir = e, keep.source = FALSE)))); TRUE }, error = function(z) conditionMessage(z))
    tf <- if (isTRUE(ld) && !is.na(fn) && exists(fn, envir = e, mode = "function", inherits = FALSE)) get(fn, envir = e, inherits = FALSE) else NULL
    out[[p]] <- list(ok = isTRUE(ld) && is.function(tf), why = if (!isTRUE(ld)) "generator_load_failed" else if (!is.function(tf)) "text_fn_missing" else "",
                     md5 = rc_md5(f), fn = tf, text_fn = fn)
  }
  out
}
## 디렉터리 1개 판독(자체 사양) — 모든 실패 사유를 모은다(첫 사유에서 멈추지 않는다 · 성과를 읽지 않는다).
##   사유: own_spec_missing · own_generator_unknown · own_generator_mismatch + 공통(no_engine · engine_parse_failed · output_contract_unknown ·
##   portfolio_only_base · dynamic_sign · pit_static · paper_meta_missing). 레인 점수 패널 · 레인 보유가 없으므로 폭 · 격자 · 롱 레그 사유는 붙이지 않는다
##   (측정의 실효 시작 규칙 · 측정 관문 rc_standing_base_alignment 가 가른다).
##   출시 전 수리: 사유 own_spec_family_mismatch(격리 점검 R1) · own_spec_undeclared(R3 — decl = list(lines = .rcs_own_declarations, D = 결정 기록부)) ·
##   source_rounds = 엔진 md5 ∪ 계보(.rcs_own_source · 판단 T4 C-20261113-035 ②) · 열 source_md5_rounds · n_source_cells · remeasure · declared.
.rcs_scan_own_dir <- function(d, sc, root, tau, gens = .rcs_own_generators(sc[["generators"]], root), src = NULL, decl = NULL) {
  nm <- basename(d); ep <- file.path(d, "engine.R"); spf <- file.path(d, "own_spec.json"); rs <- character(0); det <- character(0)
  has_eng <- file.exists(ep) && isTRUE(file.info(ep)$size >= RC_STANDING_MIN_BYTES)
  if (!has_eng) rs <- c(rs, "no_engine")
  emd5 <- if (has_eng) rc_md5(ep) else NA_character_
  os <- if (file.exists(spf)) tryCatch(rc_json_read(spf), error = function(e) NULL) else NULL
  os_ok <- is.list(os) && identical(.rcs_str(os[["schema"]]), RC_STANDING_OWN_SCHEMA) && is.list(os[["core"]]) && length(os[["core"]]) > 0L &&
    identical(.rcs_own_core_md5(os[["core"]]), .rcs_str(os[["spec_md5"]]))
  if (!os_ok) { rs <- c(rs, "own_spec_missing")
                det <- c(det, if (!file.exists(spf)) "own_spec.json 없음" else if (!is.list(os)) "own_spec.json 판독 불가" else
                                if (!identical(.rcs_str(os[["schema"]]), RC_STANDING_OWN_SCHEMA)) paste0("schema ", .rcs_or(.rcs_str(os[["schema"]]), "없음")) else "core md5 ≠ spec_md5") }
  gp <- if (os_ok) .rcs_str(os[["generator"]][["path"]]) else NA_character_
  gk <- if (is.na(gp)) NA_character_ else .rcs_repo_rel(gp, root)
  if (os_ok) {
    g <- if (is.na(gk)) NULL else gens[[gk]]
    if (is.null(g)) { rs <- c(rs, "own_generator_unknown"); det <- c(det, paste0("생성기 ", .rcs_or(gk, "없음"), " ∉ scan.generators")) }
    else {
      mm <- character(0)
      if (!isTRUE(g$ok)) mm <- c(mm, g$why)
      else {
        if (!identical(g$md5, .rcs_str(os[["core"]][["generator_md5"]]))) mm <- c(mm, "generator_md5")
        if (has_eng) {
          if (!identical(emd5, .rcs_str(os[["engine"]][["md5"]]))) mm <- c(mm, "engine_md5")
          txt <- tryCatch(g$fn(os), error = function(e) e)
          if (inherits(txt, "error") || !is.character(txt) || length(txt) != 1L) mm <- c(mm, "regen_failed")
          else if (!identical(.rcs_md5s(txt), emd5)) mm <- c(mm, "regen_md5")
        }
      }
      if (length(mm)) { rs <- c(rs, "own_generator_mismatch"); det <- c(det, paste0("생성기 대조: ", paste(mm, collapse = ","))) }
    }
  }
  st <- if (has_eng) rc_standing_static(ep) else NULL
  if (has_eng) {
    if (!isTRUE(st$ok)) rs <- c(rs, "engine_parse_failed") else {
      if (!length(st$outputs)) rs <- c(rs, "output_contract_unknown")
      else if (!("FACTORS" %in% st$outputs)) rs <- c(rs, "portfolio_only_base")
      if (!(st$orientation %in% rc_standing_orient_admitted(sc[["orientation_admit"]]))) rs <- c(rs, "dynamic_sign")
    }
  }
  pit <- if (has_eng && isTRUE(sc[["pit_static"]])) rc_standing_pit(ep, root) else list(clean = NA, checks = character(0), error = NA_character_)
  if (has_eng && isTRUE(sc[["pit_static"]]) && !isTRUE(pit$clean)) rs <- c(rs, "pit_static")
  rp <- if (is.list(os) && is.list(os[["root_paper"]])) os[["root_paper"]] else list()
  pa <- list(url = .rcs_str(rp[["url"]]), title = .rcs_str(rp[["title"]]), paper_key = .rcs_str(rp[["paper_key"]]))
  if (anyNA(unlist(pa))) rs <- c(rs, "paper_meta_missing")
  fr0 <- if (os_ok) .rcs_str(os[["family_root"]]) else NA_character_                    # 사양을 못 읽으면 계보를 모른다(계보 판독 · 불일치 검사 없음 — own_spec_missing 이 이미 뺀다)
  o <- .rcs_own_source(src, emd5, fr0); sr <- o$rounds
  if (os_ok && !is.na(emd5) && length(o$mismatch)) { rs <- c(rs, "own_spec_family_mismatch"); det <- c(det, paste0("원천 칸 계보 ≠ ", .rcs_or(fr0, "없음"), ": ", paste(o$mismatch, collapse = ","))) }
  ## 선언(R3) — ① 등록부 선언 줄(같은 경로 · 같은 md5) ② own_spec decision = 결정 기록부 resolved ③ 이 엔진 md5 의 원천 라운드 ≥ 1(계보만으로는 선언 아님)
  dl <- decl$lines; dw <- character(0)
  if (!is.na(emd5) && is.data.frame(dl) && nrow(dl) && any(dl$engine_path == .rcs_repo_rel(ep, root) & dl$engine_md5 %in% emd5 & !is.na(dl$at))) dw <- c(dw, "registry")
  dc <- if (os_ok) .rcs_str(os[["decision"]]) else NA_character_
  if (!is.na(dc) && isTRUE(.rcp4_decision_resolved(dc, decl$D))) dw <- c(dw, paste0("decision:", dc))
  if (length(o$md5_rounds)) dw <- c(dw, "source_round")
  if (has_eng && os_ok && !length(dw)) { rs <- c(rs, "own_spec_undeclared"); det <- c(det, "선언 기록 없음(등록부 선언 줄 · 결정 id resolved · 엔진 md5 원천 라운드 모두 없음)") }
  fams <- if (os_ok) as.character(unlist(os[["core"]][["families"]])) else character(0)
  data.table(dir = nm, engine = rc_rel(ep, root), engine_md5 = emd5, base_id = NA_character_, program = .rcs_str(sc[["routed_program"]]),
             where = "own_spec", at = if (is.list(os)) .rcs_str(os[["declared_at"]]) else NA_character_, eligible = !length(rs), reasons = paste(unique(rs), collapse = ";"),
             orientation = if (is.null(st)) NA_character_ else st$orientation,
             orientation_evidence = if (is.null(st)) NA_character_ else paste(c(st$factor_db, st$orientation_tokens), collapse = ","),
             outputs = if (is.null(st)) NA_character_ else paste(st$outputs, collapse = ","),
             long_leg = "na:own_spec", breadth = "na:own_spec", grid = "na:own_spec",
             pit = if (isTRUE(pit$clean)) "clean" else if (isFALSE(pit$clean)) paste(pit$checks, collapse = ",") else "unscanned",
             factor_db_vintage = "na:own_spec", paper_key = pa$paper_key, title = pa$title, url = pa$url, url_source = "own_spec",
             fidelity = "own_spec", audit_item = NA_character_, audit_file = NA_character_, has_short = FALSE, artifacts = NA_character_,
             family_root = if (is.list(os)) .rcs_str(os[["family_root"]]) else NA_character_, own_spec = rc_rel(spf, root),
             own_spec_md5 = if (file.exists(spf)) rc_md5(spf) else NA_character_, generator = .rcs_or(gk, NA_character_),
             families = paste(fams, collapse = ","), source_rounds = paste(sr, collapse = ","), source_md5_rounds = paste(o$md5_rounds, collapse = ","),
             n_source_cells = o$n_cells, remeasure = isTRUE(o$remeasure), declared = paste(dw, collapse = ","), own_detail = paste(det, collapse = " | "))
}
## 자체 사양 입구 전체 판독 — 디렉터리마다 1행 · 생성기는 경로마다 한 번 적재 · 원천 라운드 칸 표 · 선언 판독(등록부 선언 줄 · 결정 기록부)은 한 번 만든다
##   decision_register = 결정 기록부 경로(기본 06_Registry/decision_register.json · 판독 불가 = 결정 선언 없음 — fail-closed) · src = 원천 칸 표(넘기면 다시 읽지 않는다)
rc_standing_own_candidates <- function(sc, root = rc_root(), registry_path = NULL, tau = "2022-12-31", lane_root = NULL, decision_register = NULL, src = NULL) {
  lr <- lane_root %||% rc_abs(sc[["lane_root"]], root)
  dirs <- sort(Sys.glob(file.path(lr, sc[["dir_glob"]] %||% "FC_*"))); dirs <- dirs[dir.exists(dirs)]
  if (!length(dirs)) return(data.table(dir = character(0), eligible = logical(0), reasons = character(0), engine_md5 = character(0), at = character(0)))
  gens <- .rcs_own_generators(sc[["generators"]], root)
  src <- src %||% rc_standing_source_cells(.rcs_or(.rcs_str(sc[["routed_program"]]), "P1_RETURN"), root, registry_path)
  decl <- list(lines = .rcs_own_declarations(pr_load(root, registry_path), root),
               D = tryCatch(rc_json_read(decision_register %||% file.path(root, "06_Registry/decision_register.json")), error = function(e) NULL))
  rbindlist(lapply(dirs, .rcs_scan_own_dir, sc = sc, root = root, tau = tau, gens = gens, src = src, decl = decl), fill = TRUE)
}

## ── 항목 넣기 · R2 대조 ─────────────────────────────────────────────────────
## 엔진 1개 → 칸 사양(등록 생성 함수 · 재량 없음) + 원장 enqueue. 같은 엔진(md5)은 이 판에서 한 번, 옛 판에 있으면 넣지 않는다(rejudge 판 제외)
##   src = 원천 칸 표(rc_standing_source_cells — 스캔이 한 번 만든 것을 넘긴다 · 없으면 맥락 등록부로 만든다 · 자체 사양 행만 쓴다)
rc_standing_enqueue <- function(engine_path, paper, family_root, round_dir, handoff = list(), tags = list(), source = c("scan", "manual"),
                                engine_label = NULL, root = rc_root(), registry_path = NULL, ctx = NULL, src = NULL) {
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
  ## v4 시행 수(출시 전 수리 · 판단 T4 C-20261113-036 · 격리 점검 R1 · M1) — 자체 사양 행 = 엔진 속성(인계 origin own_spec ∨ 맥락 갈래 own_spec ∨ 엔진 폴더 own_spec.json).
  ##   원천 라운드 = 인계 source_rounds ∪ 지금 등록부의 엔진 md5 · 계보 칸 라운드(.rcs_own_source) · 원천 칸 수 n = 그 라운드 사전등록 칸 수 합(사슬 원천 시행과 같은 집합).
  ##   ① 이 엔진 md5 를 변형 칸 · 같은 계보로 회계한 원천 칸이 있으면 = 같은 시행의 재측정 → n_family = max(계보 최댓값, n)(+1 없음 · 상설 행과 사슬이 같은 시행 수)
  ##   ② 아니면(원천 없음 · 계보만 · reference 로만) = 새 시행 → max(계보 최댓값, n, 레인 회계 하한) + 1(원천 없으면 레인 규칙과 같다).
  ##   원천 칸 계보 ≠ 이 계보 · own_spec family_root ≠ 이 계보 · 등록부에 없는 원천 라운드 = 멈춘다(fail-closed). 근거 문장은 원장에 남는다(rc_standing_regen_md5).
  oi <- .rcs_own_info(ep, root)
  own <- identical(.rcs_str(handoff[["origin"]]), "own_spec") || identical(ctx$track, "own_spec") || isTRUE(oi$exists)
  if (own) {
    if (isTRUE(oi$ok) && !identical(oi$family_root, fam)) .rcs_err("자체 사양 계보 불일치 — own_spec family_root ", .rcs_or(oi$family_root, "없음"), " ≠ 넣는 계보 ", fam)
    S <- src %||% rc_standing_source_cells(.rcs_or(.rcs_str(ctx$spec[["program"]]), "P1_RETURN"), root, ctx$registry_path)
    o <- .rcs_own_source(S, emd5, fam)
    if (length(o$mismatch)) .rcs_err("자체 사양 계보 불일치(own_spec_family_mismatch) — 원천 칸 계보 ≠ ", fam, ": ", paste(o$mismatch, collapse = ","))
    hr <- as.character(unlist(handoff[["source_rounds"]])); hr <- hr[!is.na(hr) & nzchar(hr)]
    srcr <- sort(unique(c(hr, o$rounds))); RN <- attr(S, "rounds")
    unk <- setdiff(srcr, if (is.data.frame(RN)) RN$round_id else character(0))
    if (length(unk)) .rcs_err("원천 라운드가 등록부의 등록된 P1 라운드가 아니다(사전등록 판독 불가 · 상설 판 · 미등록): ", paste(unk, collapse = ","))
    nsc <- if (length(srcr)) sum(as.integer(RN$n_cells[RN$round_id %in% srcr])) else 0L
    ## 인계 기록 = 자체 사양 기록(원장 판독자 — 자격 통과 표 · 기저 풀 — 가 같은 원천 라운드 · 가족을 읽게)
    handoff[["origin"]] <- "own_spec"; handoff[["source_rounds"]] <- as.list(srcr)
    if (is.null(handoff[["families"]]) && isTRUE(oi$ok)) handoff[["families"]] <- as.list(oi$families)
    if (is.null(handoff[["own_spec"]]) && isTRUE(oi$exists)) { handoff[["own_spec"]] <- oi$own_spec; handoff[["own_spec_md5"]] <- oi$own_spec_md5 }
  }
  if (own && isTRUE(o$remeasure)) {
    nf <- as.integer(max(nf0, nsc))
    basis <- sprintf("%s 상설 자격(판 %s · 자체 사양 입구): 계보 %s 의 앞선 사전등록 · 상설 원장 회계 최댓값 %d 와 원천 라운드 %s 의 칸 수 %d(사슬 원천 시행과 같은 집합) 중 큰 값 — 같은 엔진(md5)을 원천 라운드 %s 가 변형 칸 · 같은 계보로 회계했다(같은 시행의 재측정 · 이 칸 +1 없음)",
                     ctx$tag, ctx$cfg[["edition"]], fam, nf0, paste(srcr, collapse = ","), nsc, paste(o$md5_rounds, collapse = ","))
  } else if (own) {
    nf <- as.integer(max(nf0, nsc, lane_n) + 1L)
    basis <- sprintf("%s 상설 자격(판 %s · 자체 사양 입구): 계보 %s 의 앞선 사전등록 · 상설 원장 회계 최댓값 %d · 원천 라운드 칸 수 %d · 레인 회계 하한 %d 중 큰 값 + 이 칸 1(원천 라운드 %s)",
                     ctx$tag, ctx$cfg[["edition"]], fam, nf0, nsc, lane_n,
                     if (length(srcr)) paste0(paste(srcr, collapse = ","), " — 이 엔진 md5 를 변형 칸 · 같은 계보로 회계한 원천 칸 없음") else "없음")
  } else {
    nf <- as.integer(max(nf0, lane_n) + 1L)
    basis <- sprintf("%s 상설 자격(판 %s): 계보 %s 의 앞선 사전등록 · 상설 원장 회계 최댓값 %d 와 레인 측정 %d(대표 + 변형) 중 큰 값 + 이 칸 1",
                     ctx$tag, ctx$cfg[["edition"]], fam, nf0, lane_n)
  }
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
##   출시 전 수리(격리 점검 M1 · 판단 T4 C-20261113-035): 자체 사양 시드(맥락 갈래 own_spec ∨ 엔진 폴더 own_spec.json)는 스캔 행과 같은 인계 기록
##   (origin own_spec · own_spec · own_spec_md5 · generator · families · source_rounds · declared_at)을 함께 적는다 — 시드 행도 기저 풀 관문 · 사슬 원천 시행 대상.
.rcs_enqueue_seeds <- function(ctx, I, src = NULL) {
  out <- character(0); S <- src
  for (c in ctx$pre[["cells"]]) {
    if (!is.null(I[[c[["code"]]]])) next
    ep <- NA_character_; emd5 <- NA_character_; pp <- NULL; fam <- NA_character_; nf <- NA_integer_; ho <- NULL
    if (!is.null(c[["spec"]])) {
      cs <- rc_json_read(rc_abs(c[["spec"]], ctx$root)); p <- .rcs_str(cs[["base_signal"]][["path"]])
      if (!is.na(p)) { ep <- .rcs_repo_rel(p, ctx$root); emd5 <- rc_md5(rc_abs(ep, ctx$root)) }
      pp <- cs[["root_paper"]]; fam <- .rcs_str(cs[["selection_accounting"]][["family_root"]])
      nf <- suppressWarnings(as.integer(.rcs_str(cs[["selection_accounting"]][["n_family_at_registration"]])))
      ea <- if (is.na(ep)) NA_character_ else rc_abs(ep, ctx$root)
      if (!is.na(ea) && file.exists(ea) && (identical(ctx$track, "own_spec") || file.exists(file.path(dirname(ea), "own_spec.json")))) {
        if (is.null(S)) S <- rc_standing_source_cells(.rcs_or(.rcs_str(ctx$spec[["program"]]), "P1_RETURN"), ctx$root, ctx$registry_path)
        ho <- .rcs_own_handoff(ea, fam, ctx$root, S)
      }
    }
    rc_standing_append(ctx, c(list(event = "enqueue", code = c[["code"]], engine = c[["engine"]], role = c[["role"]] %||% "reference", source = "seed",
                                   engine_path = ep, engine_md5 = emd5, paper = pp, family_root = fam, n_family = nf),
                              if (!is.null(c[["spec"]])) list(cell_spec = c[["spec"]], cell_spec_md5 = c[["md5"]]) else list(source_results = c[["source_results"]]),
                              if (!is.null(ho)) list(handoff = ho)))
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
  own <- identical(.rcs_str(cfg[["scan"]][["source"]]), "own_spec")
  ## 자체 사양 판 = 원천 칸 표를 한 번 만들어 입구 판독 · 시드 · enqueue 가 같이 쓴다(같은 등록부 시점 · 다시 읽지 않는다)
  SRC <- if (own || identical(ctx$track, "own_spec")) rc_standing_source_cells(S[["program"]], root, registry_path) else NULL
  C <- rc_standing_lane_candidates(cfg[["scan"]], root, registry_path, S[["tau_d"]], lane_root,
                                   axis = .rcs_str(cfg[["generator_pin"]][["canon"]][["measurement_axis"]]) %||% NA_character_, src = SRC)   # v3 — 그 판의 측정 축(없으면 폭 문턱이 멈춘다)
  K <- rc_standing_known(S[["program"]], root)
  if (isTRUE(cfg[["rejudge_prior_editions"]])) K <- K[round_id == S[["round_id"]]]
  C[, status := ifelse(!eligible, "excluded", ifelse(engine_md5 %in% K$engine_md5, "known", "new"))]
  enq <- character(0)
  if (!dry_run) {
    enq <- .rcs_enqueue_seeds(ctx, rc_standing_items(rc_standing_ledger_read(ctx$ledger)), src = SRC)
    nw <- C[status == "new"][order(at, na.last = TRUE)]
    if (!is.null(max_new)) nw <- head(nw, as.integer(max_new))
    spl <- function(s) { v <- strsplit(.rcs_or(.rcs_str(s), ""), ",", fixed = TRUE)[[1]]; as.list(v[nzchar(v)]) }
    for (i in seq_len(nrow(nw))) {
      r <- nw[i]
      ## v4 자체 사양 행 = 계보 family_root(own_spec) · 인계 기록 대신 자체 사양 기록(origin own_spec · 사양 경로 · md5 · 생성기 · 가족 · 원천 라운드 · 선언 시각)
      ho <- if (own) list(origin = "own_spec", own_spec = r$own_spec, own_spec_md5 = r$own_spec_md5, generator = r$generator,
                          families = spl(r$families), source_rounds = spl(r$source_rounds), declared_at = r$at)
            else list(base_id = r$base_id, program = r$program, where = r$where, at = r$at, artifacts = r$artifacts,
                      audit_item = r$audit_item, audit_file = r$audit_file, fidelity = r$fidelity, has_short = r$has_short)
      x <- rc_standing_enqueue(rc_abs(r$engine, root), list(url = r$url, title = r$title, paper_key = r$paper_key), if (own) r$family_root else r$paper_key, round_dir,
                               handoff = ho,
                               tags = list(orientation = r$orientation, outputs = r$outputs, long_leg = r$long_leg, breadth = r$breadth, grid = r$grid, url_source = r$url_source),
                               source = "scan", root = root, registry_path = registry_path, ctx = ctx, src = SRC)
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
rc_standing_fingerprint <- function() paste(suppressWarnings(system2(qv_bash(), c(shQuote(file.path(RC_DIR, "fingerprint.sh")), "equality"),
                                                                    stdout = TRUE, stderr = FALSE)), collapse = "\n")
## GPU 임대(v2 · 11-11 P1S01 격리 점검 S-2 · WP3 임대 규칙 L1-SPEED-LEVERS-20261020) — 상설 측정 · 사슬 측정의 공통 관문.
##   판별 = 레인 정본(rf_replication_slots.py classify → rf_compute_class.py · 엔진 디렉터리의 구현 의존성: torch · tensorflow · jax · CUDA).
##   GPU 엔진이면 ① 레인 측정이 하나라도 살아 있으면(rf_replication_slots.py status — slot claim = live) 재지 않는다(같은 PC 의 RAM · VRAM 겹침 —
##   DNN 칸 지속 25~33 GB · 레인 측정 12.8 GB · 커밋 상한 55.8 GB · 설계 README §10.8) ② GPU 임대(qv_lock.R::gpu_lease_acquire — 레인 GPU 슬롯이
##   새 claim 을 보류)를 잡고 잰 뒤 놓는다(release). 다른 보유자 · 판별 · 상태 판독 불가 = 재지 않는다(fail-closed — 원장 무기록 · 실패 횟수 무증가 ·
##   다음 틱 재개). GPU 를 쓰지 않는 엔진은 그대로 잰다(임대 없음).
##   반환 list(ok, need, state = cpu | acquired | lane_busy | lease_held | check_error, reason, release = function()) · 시험은 측정 함수의 gpu 인자에 판정 함수를 넣는다.
rc_gpu_guard <- function(engine_path, holder, purpose = holder, root = rc_root()) {
  noop <- function() invisible(NULL)
  out <- function(ok, need, state, reason, release = noop) list(ok = ok, need = need, state = state, reason = reason, release = release)
  py <- Sys.getenv("QVEST_PY", ""); if (!nzchar(py)) py <- "python"
  slots <- file.path(root, "02_Infrastructure/ops/rf_replication_slots.py")
  if (!file.exists(slots)) return(out(FALSE, NA, "check_error", "rf_replication_slots.py 없음"))
  run <- function(args) { r <- tryCatch(suppressWarnings(system2(py, c("-X", "utf8", shQuote(slots), args), stdout = TRUE, stderr = FALSE)),
                                        error = function(e) structure(character(0), status = 99L))
                          list(rc = as.integer(attr(r, "status") %||% 0L), out = r[nzchar(trimws(r))]) }
  wd <- dirname(rc_abs(.rcs_repo_rel(engine_path, root), root))
  cl <- run(c("classify", "--req", shQuote(file.path(tempdir(), "rc_gpu_guard_no_req.json")), "--wdir", shQuote(wd)))
  cls <- if (identical(cl$rc, 0L) && length(cl$out)) strsplit(cl$out[length(cl$out)], " ", fixed = TRUE)[[1]] else character(0)
  if (length(cls) < 2L || !(cls[1] %in% c("gpu", "cpu"))) return(out(FALSE, NA, "check_error", "계산 등급 판별 실패(rf_replication_slots.py classify)"))
  if (identical(cls[1], "cpu")) return(out(TRUE, FALSE, "cpu", paste(cls[-1], collapse = " ")))
  st <- run(c("status", "--json"))
  S <- tryCatch(fromJSON(paste(st$out, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
  if (!identical(st$rc, 0L) || !is.list(S) || is.null(S[["slots"]])) return(out(FALSE, TRUE, "check_error", "레인 슬롯 상태 판독 불가(rf_replication_slots.py status)"))
  live <- Filter(function(s) identical(.rcs_str(s[["claim"]]), "live"), S[["slots"]])
  if (identical(.rcs_str(S[["legacy"]][["claim"]]), "live")) live <- c(live, list(list(slot = "legacy", paper = NA)))
  if (length(live)) return(out(FALSE, TRUE, "lane_busy", sprintf("레인 측정 %d 진행 중(%s) — GPU 엔진은 레인 측정 0 일 때만 잰다", length(live),
                                                                 paste(vapply(live, function(s) paste0(.rcs_str(s[["slot"]]), ":", .rcs_str(s[["paper"]])), ""), collapse = ","))))
  if (!exists("gpu_lease_acquire", mode = "function")) {
    f <- file.path(root, "02_Infrastructure/ops/qv_lock.R"); if (!file.exists(f)) return(out(FALSE, TRUE, "check_error", "qv_lock.R 없음"))
    sys.source(f, envir = globalenv())
  }
  a <- tryCatch(gpu_lease_acquire(holder, purpose, holder_pid = Sys.getpid()), error = function(e) list(ok = FALSE, reason = conditionMessage(e)))
  if (!isTRUE(a[["ok"]])) return(out(FALSE, TRUE, "lease_held", paste0("GPU 임대를 잡지 못했다: ", .rcs_str(a[["reason"]]))))
  out(TRUE, TRUE, "acquired", sprintf("GPU 임대 %s", holder), release = function() invisible(tryCatch(gpu_lease_release(holder), error = function(e) NULL)))
}
## 기저 정합 진단(v3 · 판 표식) — 셀 엔진(rf_cell_engine.R · 11-11 개정)이 기저가 엔진인 칸마다 산출 폴더에 쓰는 rf_engine_diag.json::base_alignment
##   (키 = "<엔진 폴더>/<엔진 파일>"). 칸 사양 base_signal.kind 가 engine | engine_blend 인데 ① 진단 없음 · 칸의 엔진 키 없음 · 규칙 ≠ month_snap_v1 =
##   base_alignment_missing(옛 셀 엔진으로 잰 측정이 판정으로 가지 않게) ② base_kind ≠ factors(없으면 unknown) = base_not_score_panel(비중을 점수로 읽은 측정 차단).
##   요약은 보는 창 필드만 — last_cell_date 는 싣지 않는다(τ_D 뒤 날짜) · 다른 날짜도 τ_D 뒤면 가린다.
RC_STANDING_BASE_RULE <- "month_snap_v1"   # 셀 엔진 달 스냅 규칙 id(02_Infrastructure/reinforcement/rf_base_align.R · 판 2 S1)
##   관문 순서 = base_alignment_missing → base_not_score_panel → base_off_month_grid(n_superseded > 0 또는 n_offcal > 0 — 엔진 신호가 월말 격자가 아니다:
##   주간 · 일간 신호의 월말 표본이거나 비거래일 도장 · 모수 없음 · 판단 Superfan T4 R-20261111-008). 상설 측정과 P4 사슬 측정(p4.R)이 이 함수를 같이 쓴다.
##   요약 필드 = 아래 목록(없으면 NA) — last_engine_date · last_cell_date 는 싣지 않는다(τ_D 뒤 날짜).
RC_STANDING_BASE_SUMMARY <- c("rule", "n_engine_dates", "n_cell_dates", "n_moved", "n_superseded", "n_offcal", "max_lag_td", "start", "from_cache",
                              "first_engine_date", "first_cell_date", "n_cell_dates_from_start", "base_kind")
RC_STANDING_BASE_DATE_FIELDS <- c("start", "first_engine_date", "first_cell_date")   # τ_D 뒤면 가린다
#' 공용 관문(상설 측정 · P4 사슬 측정) — 반환 list(need, ok, error, why, summary). need = FALSE = 기저가 엔진이 아닌 칸(관문 대상 아님)
rc_standing_base_alignment <- function(cell_spec, artifacts, tau, root = rc_root()) {
  s <- tryCatch(rc_json_read(rc_abs(.rcs_or(.rcs_str(cell_spec), ""), root)), error = function(e) NULL)
  bad <- function(err, why, summary = NULL) list(need = TRUE, ok = FALSE, error = err, why = why, summary = summary)
  if (!is.list(s)) return(bad("base_alignment_missing", "칸 사양 판독 불가"))   # 기저 종류를 모르면 검사를 건너뛰지 않는다(fail-closed)
  bs <- s[["base_signal"]]; kind <- .rcs_str(bs[["kind"]])
  if (!(kind %in% c("engine", "engine_blend"))) return(list(need = FALSE, ok = TRUE, error = NA_character_, why = "", summary = NULL))
  paths <- gsub("\\\\", "/", if (identical(kind, "engine")) .rcs_str(bs[["path"]]) else as.character(unlist(bs[["paths"]])))
  keys <- paste0(basename(dirname(paths)), "/", basename(paths))
  a <- .rcs_str(artifacts); f <- if (is.na(a)) NA_character_ else file.path(a, "rf_engine_diag.json")
  D <- if (!is.na(f) && file.exists(f)) tryCatch(rc_json_read(f), error = function(e) NULL) else NULL
  B <- D[["base_alignment"]]
  if (!is.list(B) || !length(B) || is.null(names(B))) return(bad("base_alignment_missing", if (is.na(f) || !file.exists(f)) "rf_engine_diag.json 없음" else "base_alignment 없음"))
  if (anyNA(paths) || !all(keys %in% names(B))) return(bad("base_alignment_missing", paste0("칸 기저 엔진 키 없음: ", paste(setdiff(keys, names(B)), collapse = ","))))
  rl <- vapply(B, function(x) .rcs_or(.rcs_str(x[["rule"]]), "?"), "")
  if (any(rl != RC_STANDING_BASE_RULE)) return(bad("base_alignment_missing", paste0("정렬 규칙 ≠ ", RC_STANDING_BASE_RULE, ": ", paste(unique(rl), collapse = ","))))
  tau <- as.Date(tau)
  sm <- lapply(B, function(x) {
    y <- lapply(setNames(RC_STANDING_BASE_SUMMARY, RC_STANDING_BASE_SUMMARY), function(k) { v <- unlist(x[[k]]); if (length(v)) v[1] else NA })
    y[["base_kind"]] <- .rcs_or(.rcs_str(y[["base_kind"]]), "unknown")
    for (k in RC_STANDING_BASE_DATE_FIELDS) { d <- suppressWarnings(as.Date(.rcs_str(y[[k]]))); if (!is.na(d) && d > tau) y[[k]] <- "after_tau_d" }
    y })
  bk <- vapply(sm, function(y) y[["base_kind"]], "")
  if (any(bk != "factors")) return(bad("base_not_score_panel", paste0("기저 종류 ≠ factors: ", paste(sprintf("%s=%s", names(bk), bk), collapse = ",")), sm))
  ## 격자 — 0 초과 여부만(모수 없음). 필드가 없으면(NA) 관문을 걸지 않는다(구판 진단 = 필드 없음은 규칙 확인으로 이미 걸러진다 · 지시 '없으면 NA')
  off <- vapply(sm, function(y) { a <- suppressWarnings(as.numeric(y[["n_superseded"]])); b <- suppressWarnings(as.numeric(y[["n_offcal"]]))
                                  isTRUE(a > 0) || isTRUE(b > 0) }, logical(1))
  if (any(off)) return(bad("base_off_month_grid", paste0("엔진 신호가 월말 격자가 아니다(n_superseded · n_offcal > 0): ", paste(names(sm)[off], collapse = ",")), sm))
  list(need = TRUE, ok = TRUE, error = NA_character_, why = "", summary = sm)
}
rc_standing_measure_item <- function(round_dir, code, root = rc_root(), registry_path = NULL,
                                     worker = file.path(root, "02_Infrastructure/ops/rf_cell_worker.R"), fingerprint = rc_standing_fingerprint,
                                     freshness = rc_data_freshness, gpu = rc_gpu_guard) {
  ctx <- rc_standing_context(round_dir, root, registry_path)
  it <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))[[code]]
  if (is.null(it)) .rcs_err("상설 원장에 그런 항목이 없다: ", code)
  if (!is.null(it[["source_results"]])) .rcs_err("공유 측정 항목 — 측정하지 않는다: ", code)
  if (!is.null(it[["verdict"]])) .rcs_err("이미 판정한 항목 — 다시 재지 않는다(판정 유지): ", code)
  if (.rcs_measured(it)) return(invisible(list(code = code, status = "already")))
  bad <- rc_standing_item_check(it, ctx)
  if (length(bad)) { rc_standing_append(ctx, list(event = "measure", code = code, ok = FALSE, r2 = as.list(bad)))
                     .rcs_err("R2 대조 실패 — 측정하지 않는다(", code, "): ", paste(bad, collapse = ",")) }
  ## 데이터 신선도(11-10 · v1/freshness.R — 측정 경로 공통 판정) — 낡음 · 판독 불가 = 재지 않는다 · 원장 무기록(실패 횟수 무증가 · 다음 틱 재개)
  fr <- rc_fresh_gate(freshness, root)
  if (!isTRUE(fr$ok)) { cat(sprintf("[상설] 측정 %s 건너뜀 — 데이터 신선도 %s · %s\n", code, fr$state, fr$reason %||% ""))
                        return(invisible(list(code = code, status = "data_stale", reason = fr$reason))) }
  ## GPU 임대(v2 · S-2) — GPU 엔진은 레인 측정 0 + 임대를 잡은 뒤에만 잰다 · 못 잡으면 원장 무기록(다음 틱 재개)
  gg <- gpu(it[["engine_path"]], sprintf("rc_standing:%s:%s", ctx$tag, code), sprintf("상설 측정 %s", code), root)
  if (!isTRUE(gg$ok)) { cat(sprintf("[상설] 측정 %s 건너뜀 — GPU %s · %s\n", code, gg$state, gg$reason %||% ""))
                        return(invisible(list(code = code, status = "gpu_wait", reason = gg$reason))) }
  on.exit(gg$release(), add = TRUE)
  dir.create(ctx$P$results, recursive = TRUE, showWarnings = FALSE)
  res <- file.path(ctx$P$results, paste0(code, ".json")); unlink(res)   # 원장에 ok 측정이 없으면 디스크 결과는 잔재다
  role <- it[["role"]] %||% "variant"; ev <- c("QVEST_RP_REGISTER", "QVEST_RP_NO_FACTOR_ANALYSIS", "QVEST_RP_NO_LCODE"); old <- Sys.getenv(ev, unset = NA)
  on.exit({ for (k in ev) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)) }, add = TRUE)
  if (!identical(role, "variant")) Sys.setenv(QVEST_RP_REGISTER = "0", QVEST_RP_NO_FACTOR_ANALYSIS = "1")
  Sys.setenv(QVEST_RP_NO_LCODE = "1")   # 칸 L-code 끔(11-10 · 감사 K P5)
  fp0 <- tryCatch(fingerprint(), error = function(e) ""); t0 <- Sys.time()
  rc <- system2("Rscript", c(shQuote(worker), shQuote(rc_abs(it[["cell_spec"]], root)), "1", code, shQuote(res)),
                stdout = file.path(ctx$P$results, paste0(code, ".log")), stderr = file.path(ctx$P$results, paste0(code, ".err.log")))
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs")); fp1 <- tryCatch(fingerprint(), error = function(e) "")
  r <- tryCatch(rc_json_read(res), error = function(e) list(ok = FALSE))
  ## v3 기저 정합 진단 — 워커가 ok 일 때만 읽는다. 실패(진단 없음 · 규칙 다름 · 점수 패널 아님)는 측정 실패로 적는다
  ##   (.rcs_meas_ok = FALSE → 판정 대기 아님 · .rcs_fails 가 센다 → RC_STANDING_MAX_FAILS 번째면 사람 확인 — 기존 실패 셈법 그대로)
  ba <- if (isTRUE(r[["ok"]])) rc_standing_base_alignment(it[["cell_spec"]], r[["artifacts"]], ctx$tau, root) else NULL
  rec <- list(event = "measure", code = code, ok = isTRUE(r[["ok"]]) && (is.null(ba) || isTRUE(ba$ok)), rc = as.integer(rc), deferred = .rcs_str(r[["deferred"]]), seconds = round(sec, 1),
              artifacts = .rcs_str(r[["artifacts"]]), result_md5 = if (file.exists(res)) rc_md5(res) else NA_character_,
              fp_same = nzchar(fp0) && identical(fp0, fp1), engine_md5 = it[["engine_md5"]], cell_spec_md5 = it[["cell_spec_md5"]])
  if (!is.null(ba) && isTRUE(ba$need)) {
    if (!is.null(ba$summary)) rec[["base_alignment"]] <- ba$summary
    if (!isTRUE(ba$ok)) { rec[["error"]] <- ba$error; rec[["error_detail"]] <- ba$why; rec[["worker_ok"]] <- TRUE }
  }
  rc_perf_log(ctx$spec[["round_id"]], "standing_measure", sec, list(code = code, ok = rec$ok, fp_same = rec$fp_same), root = root)
  rc_standing_append(ctx, rec)
  cat(sprintf("[상설] 측정 %s ok=%s · 지문 동일=%s · %.1f분%s\n", code, rec$ok, rec$fp_same, sec / 60,
              if (!is.null(rec[["error"]])) paste0(" · ", rec[["error"]], "(", rec[["error_detail"]], ")") else ""))
  invisible(rec)
}

## ── 판정(칸 평가 → 등록 규칙 기계 적용 → 원장 · 판정 파일) ──────────────────────────────
##   v4 출시 전 수리(격리 점검 R5): 자체 사양 갈래는 RELEASES 출시 판 ≥ v4 일 때만 판정한다(.rcs_release_guard — releases_path 는 시험만 바꾼다)
rc_standing_judge <- function(round_dir, root = rc_root(), registry_path = NULL, eval_fun = rc_eval_cell, releases_path = file.path(dirname(RC_DIR), "RELEASES.json")) {
  ctx <- rc_standing_context(round_dir, root, registry_path); t0 <- Sys.time()
  .rcs_release_guard(ctx$track, releases_path)
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
  ## v3(판단 T3 C-20261111-049 · P1S01 마감 감독): 판정 지표 계산 예외(status ≠ evaluated) · 자격 열 NA 행은 판정이 아니다 — verdict 줄 · 판정 파일 없이
  ##   eval_failed(사유)로 적는다(칸 평가 예외와 같은 길: 다음 judge 가 다시 평가 · RC_STANDING_MAX_FAILS 에 닿으면 판정 대상에서 빠지고 standing-status 가 사람 확인으로 띄운다).
  ##   v1 · v2 는 이 행에도 verdict 를 남겨 항목을 다시 재지도 평가하지도 못하게 굳혔다. 자격 지표 이름 = 자격 규칙(qr)의 metric(보는 창 — 시험 창 보고 규칙은 보지 않는다)
  qmets <- local({ acc <- character(0); walk <- function(r) { if (!is.null(r[["metric"]])) acc <<- c(acc, as.character(r[["metric"]])); for (k in r[["of"]] %||% list()) walk(k) }
                   for (r in rules) if (identical(r[["id"]], qr)) walk(r); unique(acc) })
  nv <- 0L
  for (i in seq_len(nrow(T))) {
    cd <- T$code[i]; it <- ok[[cd]]; row <- as.list(T[i])
    q0 <- row[[qr]]; q0 <- if (is.logical(q0) && length(q0) == 1L) q0 else NA; st0 <- .rcs_str(row[["status"]])
    if (.rcs_judge_unsettled(st0, q0)) {
      na_m <- qmets[vapply(qmets, function(m) { v <- suppressWarnings(as.numeric(unlist(row[[m]]))); length(v) != 1L || !is.finite(v) }, logical(1))]
      er <- .rcs_or(.rcs_str(row[["error"]]), if (!identical(st0, "evaluated")) paste0("judge_status: ", .rcs_or(st0, "NA")) else
                    paste0("judge_metric_na: ", if (length(na_m)) paste(na_m, collapse = ",") else qr))
      if (length(rc_after_tau_leaks(er, ctx$tau))) er <- paste0("judge_error(τ_D 뒤 날짜 가림): ", gsub("(19|20)[0-9]{2}-[0-9]{2}(-[0-9]{2})?", "YYYY-MM", er))
      rc_standing_append(ctx, list(event = "eval_failed", code = cd, stage = "judge", error = er))
      next
    }
    nv <- nv + 1L
    fv <- file.path(vd, paste0(cd, ".verdict.json"))
    rc_json_write(list(schema = "rc_standing_verdict_v1", audience = "사람 쪽(전기간 · 시험 창 열 포함) — 처방 · 리뷰 레인은 원장 · standing_visible.json 만",
                       round_id = ctx$spec[["round_id"]], edition = ctx$cfg[["edition"]], code = cd, prereg_md5 = ctx$prereg_md5, judged_at = rc_now(),
                       rules = rules, sentences = sent, row = row), fv)
    vis <- row[intersect(c(RC_STANDING_VIS_COLS, qr), names(row))]
    vis[["window"]] <- evs[[cd]][["visible"]][["window"]]
    lk <- rc_after_tau_leaks(vis, ctx$tau)
    if (length(lk)) .rcs_err("보는 창 기록에 τ_D 이후 날짜가 남았다(", cd, "): ", paste(head(lk, 3), collapse = ","))
    q <- q0
    rc_standing_append(ctx, list(event = "verdict", code = cd, engine = it[["engine"]], status = .rcs_str(row[["status"]]), qualify = q,
                                 rule = qr, visible = vis, verdict_file = rc_rel(fv, root), verdict_md5 = rc_md5(fv),
                                 engine_md5 = it[["engine_md5"]], cell_spec_md5 = it[["cell_spec_md5"]]))
  }
  rc_standing_visible_write(ctx)
  TV <- T[!mapply(function(s, q) .rcs_judge_unsettled(.rcs_str(s), if (is.logical(q) && length(q) == 1L) q else NA), T$status, T[[qr]])]
  rc_perf_log(ctx$spec[["round_id"]], "standing_judge", difftime(Sys.time(), t0, units = "secs"), list(n = nv, n_unsettled = nrow(T) - nv), root = root)
  cat(sprintf("[상설] 판정 %d건 — 자격 %d%s\n", nv, sum(TV[[qr]] %in% TRUE), if (nrow(T) > nv) sprintf(" · 판정 아님(지표 계산 예외 · 자격 NA → eval_failed) %d", nrow(T) - nv) else ""))
  invisible(list(judged = TV$code, qualified = TV[TV[[qr]] %in% TRUE]$code, unsettled = setdiff(T$code, TV$code)))
}
## v3 — 판정 표 행이 판정으로 굳지 않는 경우(지표 계산 예외 = status ≠ evaluated · 자격 NA)
.rcs_judge_unsettled <- function(status, q) !identical(status, "evaluated") || is.na(q)
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
##   v4 출시 전 수리(철학 P1 C-20261113-046 · 판단 T1 C-20261113-058 · qvest-telegram §0.2 표기 — IS/OOS · 동일가중 · 하락노출):
##   ① 판정 줄 = 판정 두 조건(IS β-통제 t(α) · IS 상승 포착률)만 ② 보고 열(판정 아님) = IS 하락노출 중앙 · 최악 · 위기 수 · IS β + 고정 문구 RC_STANDING_REPORT_NOTE
##   ③ OOS 유지 = 판정 줄 밖 사람 쪽 줄 ④ standing_cfg.report.pass = daily_summary 면 통과도 일 요약 1통(통과가 있으면 그 요약을 push · 통과마다 push 없음).
##   ctx = 맥락(시험이 보고 단위를 바꿔 넘긴다 · 없으면 등록본에서 만든다).
rc_standing_report <- function(round_dir, send = FALSE, day = format(Sys.Date()), root = rc_root(), registry_path = NULL, sender = NULL, ctx = NULL) {
  ctx <- ctx %||% rc_standing_context(round_dir, root, registry_path)
  recs <- rc_standing_ledger_read(ctx$ledger); I <- rc_standing_items(recs)
  scl <- Filter(function(r) identical(r[["event"]], "scan"), recs); scl <- if (length(scl)) scl[[length(scl)]] else NULL
  pmode <- .rcs_or(.rcs_str(ctx$cfg[["report"]][["pass"]]), "push_each")
  if (!(pmode %in% RC_STANDING_REPORT_PASS)) .rcs_err("standing_cfg.report.pass 는 ", paste(RC_STANDING_REPORT_PASS, collapse = " | "))
  J <- Filter(function(it) !is.null(it[["verdict"]]) && !length(it[["reported"]]), I)
  by_day <- function(it) substr(.rcs_str(it[["verdict"]][["at"]]), 1L, 10L) <= day
  pass <- Filter(function(it) isTRUE(it[["verdict"]][["qualify"]]), J)
  fail <- Filter(function(it) !isTRUE(it[["verdict"]][["qualify"]]) && by_day(it), J)
  dpass <- if (identical(pmode, "daily_summary")) Filter(by_day, pass) else list()
  if (identical(pmode, "daily_summary")) pass <- list()
  snd <- sender %||% function(...) { if (!exists("prep_send", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure/programs/program_report.R"))))); prep_send(...) }
  nm <- function(it) .rcs_or(.rcs_str(it[["paper"]][["title"]]), it[["engine"]])
  num <- function(x, d = 2L) { x <- suppressWarnings(as.numeric(unlist(x))[1]); if (is.finite(x)) sub("^-", "−", formatC(x, format = "f", digits = d)) else "NA" }
  thr <- function(id) { for (r in ctx$pre[["rules_resolved"]]) for (k in c(list(r), r[["of"]] %||% list())) if (identical(k[["id"]], id)) return(num(k[["value"]])); "NA" }
  oos <- function(it) { fv <- tryCatch(rc_json_read(rc_abs(it[["verdict"]][["verdict_file"]], root))[["row"]], error = function(e) list())   # 사람 쪽 판정 파일
                        if (isTRUE(fv[["test_hold"]])) "예" else if (isFALSE(fv[["test_hold"]])) "아니오" else "판정 불가" }
  vline <- function(v) sprintf("IS β-통제 t(α) %s ≥ %s · IS 상승 포착률 %s ≥ %s", num(v[["t_alpha_vis"]]), thr("q_t_alpha"), num(v[["uc_vis"]]), thr("q_uc"))
  rline <- function(v) sprintf("IS 하락노출 중앙 %s(최악 %s · 위기 %s번) · IS β %s", num(v[["dd_capture_median_vis"]]), num(v[["dd_capture_worst_vis"]]),
                               num(v[["n_crisis_vis"]], 0L), num(v[["beta_vis"]]))
  oline <- function(it) sprintf("OOS 유지(OOS 연 알파 > 0): %s", oos(it))
  one <- function(heading, x) if (length(x) >= 2L) list(heading = heading, type = "bullet", items = unname(x)) else list(heading = heading, type = "text", body = x[1])
  nmax <- .rcs_or(.rcs_str(ctx$cfg[["generator_pin"]][["canon"]][["max_names"]]), "?")
  prev <- sprintf("%s → 표준 구성(롱온리 %s종 동일가중 · 활성 측정 축)", if (identical(ctx$track, "own_spec")) "자체 사양 엔진(생성기 산출)" else "충실구현 레인 산출", nmax)
  art <- rc_rel(ctx$P$results, root)
  for (it in pass) {
    v <- it[["verdict"]][["visible"]]
    snd(program = "수익 엔진", target = sprintf("%s(%s)", nm(it), .rcs_or(.rcs_str(it[["paper"]][["paper_key"]]), it[["code"]])),
        status = list(stage = sprintf("상설 자격 판정(%s · 에디션 %s)", ctx$tag, ctx$cfg[["edition"]]), position = it[["code"]], previous = prev),
        verdict_line = paste0("자격 통과 — ", vline(v)),
        extra = list(list(heading = "보고 열(판정 아님)", type = "text", body = paste0(rline(v), " — ", RC_STANDING_REPORT_NOTE)),
                     list(heading = "OOS(사람 쪽 보고 · 판정 아님)", type = "text", body = oline(it))),
        next_step = "P4 수익 엔진 후보 · Superfan 판단 T2 · 철학 P2(즉시)", artifact = art, push = TRUE, dry_run = !isTRUE(send), root = root)
    if (isTRUE(send)) rc_standing_append(ctx, list(event = "reported", kind = "push", codes = list(it[["code"]])))
  }
  if (length(fail) || length(dpass)) {
    ln <- vapply(fail, function(it) { v <- it[["verdict"]]; vv <- v[["visible"]]
      if (identical(.rcs_str(v[["status"]]), "evaluated"))
        sprintf("%s — 미달 · IS β-통제 t(α) %s · IS 상승 포착률 %s", nm(it), num(vv[["t_alpha_vis"]]), num(vv[["uc_vis"]]))
      else sprintf("%s — 미시험(%s)", nm(it), paste(c(.rcs_str(v[["status"]]), unlist(v[["r2"]])), collapse = " · ")) }, character(1))
    nf <- sum(vapply(fail, function(it) identical(.rcs_str(it[["verdict"]][["status"]]), "evaluated"), logical(1)))
    lp <- vapply(dpass, function(it) sprintf("%s — 자격 통과 · %s", nm(it), vline(it[["verdict"]][["visible"]])), character(1))
    lr <- vapply(dpass, function(it) sprintf("%s — %s", nm(it), rline(it[["verdict"]][["visible"]])), character(1))
    lo <- vapply(dpass, function(it) sprintf("%s — %s", nm(it), oline(it)), character(1))
    ex <- scl[["excluded"]]
    ent <- if (is.null(scl)) NULL else list(heading = sprintf("입구(%s 스캔 — 판정 아님)", if (identical(ctx$track, "own_spec")) "자체 사양" else "레인"), type = "text",
      body = sprintf("마지막 스캔: 디렉터리 %s · 입구 통과 %s · 새로 넣음 %d%s", .rcs_str(scl[["n_dirs"]]), .rcs_str(scl[["n_eligible"]]), length(scl[["enqueued"]]),
                     if (length(ex)) paste0(" · 제외 사유 ", paste(sprintf("%s %s", names(ex), unlist(ex)), collapse = " · ")) else ""))
    secs <- Filter(Negate(is.null), list(if (length(lp)) one("자격 통과(IS 판정)", lp),
                                         if (length(lr)) list(heading = "보고 열(판정 아님)", type = "bullet", items = unname(c(lr, RC_STANDING_REPORT_NOTE))),
                                         if (length(lo)) one("OOS(사람 쪽 보고 · 판정 아님)", lo),
                                         if (length(ln)) one("엔진별 판정(IS)", ln), ent))
    np <- length(dpass)
    snd(program = "수익 엔진", target = sprintf("상설 자격 일 요약 %s — %s미달 %d · 미시험 %d", day, if (np) sprintf("통과 %d · ", np) else "", nf, length(fail) - nf),
        status = list(stage = sprintf("상설 자격 일 요약(%s · 에디션 %s)", ctx$tag, ctx$cfg[["edition"]]), position = sprintf("%d건", length(fail) + np), previous = if (np) prev else "—"),
        verdict_line = if (np) sprintf("자격 통과 %d · 미달 %d · 미시험 %d(통과 보고 = 일 요약 1통)", np, nf, length(fail) - nf) else
                         sprintf("자격 미달 %d · 미시험 %d(통과는 따로 보냈다)", nf, length(fail) - nf), extra = secs,
        next_step = if (np) "P4 수익 엔진 후보(통과) · Superfan 판단 T2 · 철학 P2(통과 즉시) · 미달 일 묶음 1회" else "Superfan 판단 T2 · 철학 P2 일 묶음 1회",
        artifact = art, push = np > 0L, dry_run = !isTRUE(send), root = root)
    if (isTRUE(send)) rc_standing_append(ctx, list(event = "reported", kind = "daily_summary", day = day,
                                                   codes = as.list(c(vapply(dpass, function(it) it[["code"]], ""), vapply(fail, function(it) it[["code"]], "")))))
  }
  invisible(list(pass = c(vapply(pass, function(it) it[["code"]], ""), vapply(dpass, function(it) it[["code"]], "")),
                 fail = vapply(fail, function(it) it[["code"]], ""), mode = pmode, sent = isTRUE(send)))
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
##   v4: scan$source = "own_spec" 이면 자체 사양 입구 기본값(RC_STANDING_SCAN_OWN_DEFAULT)에서 시작하고 track = "own_spec" · 회계 문구를 그 입구 것으로 적는다.
##     판 번호(edition)는 입구 갈래마다 1 부터(자체 사양 입구 첫 판 = edition 1 — round_id 는 P1S03_… 여도).
##   출시 전 수리: ① 결론 범위 = P1 표준 철학 줄(RC_P1_PHILOSOPHY_LINES · 철학 C-20261113-049) 뒤에 호출자 줄 ② 자체 사양 판은 scan.generators 를 pins.files 에
##     자동으로 넣는다(생성기가 바뀌면 판정 경로 핀이 갈려 새 판 — 격리 점검 S6 · orientation_layer 허용 조건 ② 가 생성기 본문에 달려 있다) ③ report = 보고 단위(통과 push_each | daily_summary).
rc_init_standing_p1 <- function(round_dir, round_id, seeds, purpose, hypothesis, edition = 1L, scan = list(), exposures = list(),
                                conclusion_scope = list(), tests = list(), bcfg = "06_Registry/behavior_card.json", root = rc_root(),
                                report = list(pass = "push_each", fail = "daily_summary")) {
  sp_path <- file.path(round_dir, "round_spec.json")
  if (file.exists(sp_path)) .rcs_err("이미 사양이 있다 — 덮어쓰지 않는다: ", round_dir)
  dir.create(file.path(round_dir, "specs"), recursive = TRUE, showWarnings = FALSE)
  own <- identical(.rcs_str(scan[["source"]]), "own_spec")
  sc <- if (own) RC_STANDING_SCAN_OWN_DEFAULT else RC_STANDING_SCAN_DEFAULT; sc[names(scan)] <- scan   # 얕은 덮어쓰기(modifyList 는 이름 없는 목록을 덮지 않는다 — orientation_admit 등)
  acc <- if (own) list(family_root = "own_spec.family_root",
                       rule = paste0("원천 라운드 = 이 엔진 md5 를 칸으로 등록한 P1 라운드 ∪ 같은 계보(family_root) 칸을 가진 P1 라운드 · n = 그 라운드 사전등록 칸 수 합(사슬 원천 시행과 같은 집합). ",
                                     "이 엔진 md5 를 변형 칸 · 같은 계보로 회계한 원천 칸이 있으면 n_family = max(계보 앞선 사전등록 · 상설 원장 회계 최댓값, n)(같은 시행의 재측정 · +1 없음) · ",
                                     "아니면 max(그 최댓값, n, 레인 회계 하한 1) + 1 · 원천 칸 계보 ≠ own_spec family_root = 입구 제외(own_spec_family_mismatch) · 시드 = 무가산"))
         else list(family_root = "paper_key", rule = "n_family = max(계보 앞선 사전등록 · 상설 원장 회계 최댓값, 레인 측정 수(대표 + 변형)) + 1 · 시드 = 무가산")
  cfg <- list(edition = as.integer(edition), program = "P1_RETURN", track = if (own) "own_spec" else "lane", generator = "rc_p1_cell_spec",
              generator_pin = rc_standing_generator_pin(root), scan = sc, accounting = acc,
              rejudge_prior_editions = FALSE, report = report,
              superfan = list(on_register = list("T1", "P1"), on_pass = list("T2", "P2"), on_fail = "daily_batch"))
  spec <- list(schema = RC_SPEC_SCHEMA, program = "P1_RETURN", round_id = round_id, template = "p1_qualification", core_version = RC_VERSION,
               tau_d = "2022-12-31", purpose = purpose, hypothesis = hypothesis, standing = TRUE, standing_cfg = cfg, cells = seeds,
               rules = .rcs_p1_template_rules(root),
               selection = list(rule = "none", text = "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"),
               exposures = exposures, conclusion_scope = c(as.list(RC_P1_PHILOSOPHY_LINES), as.list(unlist(conclusion_scope))),
               changes_after_review = list(), changes_after_superfan = list(), tests = tests)
  if (own) spec[["pins"]] <- list(files = as.list(unique(vapply(sc[["generators"]], function(g) .rcs_repo_rel(.rcs_or(.rcs_str(g[["path"]]), ""), root), ""))),
                                  basis = "자체 사양 입구 생성기(scan.generators) 자동 핀 — 입구가 엔진 본문을 다시 만들어 대조하는 함수(코어 v4 · 격리 점검 S6)")
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
    sprintf("## 3. %s(자격 큐 입구 — 성과 수치를 읽지 않는다 · 입구 갈래 %s)", if (identical(sc[["source"]], "own_spec")) "자체 사양 입구 규칙" else "레인 스캔 규칙", .rcs_track_of(cfg)), "",
    if (identical(sc[["source"]], "own_spec"))
      c(sprintf("- 원천: `%s/%s` 디렉터리의 `own_spec.json`(schema %s · core md5 = spec_md5) + `engine.R` · 프로그램 = %s · 생성기 = %s · 허용 방향 층 = %s · PIT 정적 검사 = %s",
                sc[["lane_root"]], sc[["dir_glob"]], RC_STANDING_OWN_SCHEMA, sc[["routed_program"]],
                paste(vapply(sc[["generators"]], function(g) sprintf("`%s`::%s", .rcs_str(g[["path"]]), .rcs_str(g[["text_fn"]])), ""), collapse = " · "),
                paste(unlist(sc[["orientation_admit"]]), collapse = " · "), if (isTRUE(sc[["pit_static"]])) "켬" else "끔"),
        "- 입구 판독: 생성기 목록 안(own_generator_unknown) · 지금 생성기 md5 = core.generator_md5 · 엔진 md5 = own_spec engine.md5 · own_spec 에서 생성기 본문 함수로 다시 만든 본문 md5 = 엔진 md5(own_generator_mismatch). 레인 인계 · 감사 판정 · 폭 · 격자 · 롱 레그 판독은 없다(측정의 실효 시작 규칙 · 기저 정합 관문이 가른다).",
        "- orientation_layer 허용 조건(이 입구에서만): ① 엔진 본문 = 생성기 산출(재생성 md5 대조 — 손 편집 · 부호 층 변조는 own_generator_mismatch) ② 본문의 실행 단정(부호 = 등록부 s_reg 고정 · 가중 유한 · 비음수 — 어기면 엔진이 멈춘다).",
        "- 원천 라운드(source_rounds) = 같은 엔진(등록 md5 · 사전등록 핀)을 칸으로 등록한 P1 라운드 ∪ 같은 계보(family_root) 칸을 가진 P1 라운드(다시 만든 엔진도 앞선 계보 시행을 물려받는다). 시행 수 = 원천 칸(같은 md5 · 변형 · 같은 계보)이 있으면 max(계보 최댓값, 원천 라운드 칸 수) · 아니면 그 위에 +1. 기저 풀 · 사슬은 원천 라운드의 모든 칸을 사슬 시행 집합에 넣는다(빠지거나 검증 불가 · 갈음 없는 낡은 판이면 사슬 등록 거부).",
        "- 선언(own_spec_undeclared): 등록부 선언 줄(origin = own_spec · kind ≠ engine · 같은 경로 · 같은 md5) · own_spec decision 이 결정 기록부 resolved · 이 엔진 md5 의 원천 라운드 중 하나. 원천 칸 계보 ≠ own_spec family_root = own_spec_family_mismatch.",
        "- 자체 사양 갈래 판정은 RELEASES.json 출시 판 ≥ v4 뒤에만(그 전에는 v3 기저 풀이 관문 없이 읽는다 — 격리 점검 R5).")
    else sprintf("- 원천: `%s/%s` 디렉터리 × 등록부 인계 기록(kind = engine) · 인계 프로그램 = %s · 허용 감사 판정 = %s · 허용 방향 층 = %s · 롱 레그 창 = %s(τ_D %s 이전) · PIT 정적 검사 = %s",
            sc[["lane_root"]], sc[["dir_glob"]], sc[["routed_program"]], paste(unlist(sc[["audit_admit"]]), collapse = " · "),
            paste(unlist(sc[["orientation_admit"]]), collapse = " · "), sc[["long_leg_window"]], spec[["tau_d"]], if (isTRUE(sc[["pit_static"]])) "켬" else "끔"),
    "- 방향 층: engine_native = 엔진 고유 특성(커넥터 부호를 쓰지 않음) · factor_db_static = 커넥터 · 결합용 뷰를 등록부 방향(`direction = \"registry\"` | `\"defensive\"` 문자열 상수)으로만 부름(engine_native 허용 시 함께 허용) · factor_db_asof = 정본 커넥터 `load_month_factors`/`load_daily_factors` · 결합용 뷰 `fc_load_month(s)`/`fc_daily` 를 방향 인자 없이 · `ic_asof` · 판정 불가 값으로 부름(as-of IC 부호) · orientation_layer = `align_factor_direction`/`compute_rolling_ic_all` 호출 또는 부호 층 식별자(R 파서 토큰 — 주석 · 문자열 제외)",
    "- 한 디렉터리의 모든 실패 사유를 모은다. 통과 + 처음 보는 엔진(md5)만 인계 시각 순으로 넣는다. 같은 엔진은 판 사이에서도 다시 판정하지 않는다(새 판의 rejudge_prior_editions = true 일 때만).", "",
    "| 사유 코드 | 제외 조건 |", "|---|---|", sprintf("| `%s` | %s |", names(RC_STANDING_REASONS), unname(RC_STANDING_REASONS)), "",
    "## 4. 항목마다 R2", "",
    "- 판 단위: 사전등록 md5 = 등록부 · 사양 md5 = 등록본 · 생성 함수 핀 = 지금 · 판정 경로 핀(rc_pins_mismatches) — 하나라도 다르면 넣기 · 측정 · 판정을 멈춘다(새 판 등록).",
    "- 항목 단위: 엔진 md5 · 칸 사양 md5 = 원장(넣을 때) · 시드 = 등록본 칸 md5 · 스캔 항목 = 생성 함수로 다시 만든 md5. 측정 중 데이터 지문이 바뀌면 그 측정은 쓰지 않는다(1회 재측정).",
    sprintf("- 인프라 실패(측정 ok ≠ true · 지문 불일치 · 칸 평가 예외 · 판정 지표 계산 예외)는 판정이 아니다 — 다시 재거나 다시 평가하고, %d번째 실패면 사람이 본다(standing-status). R2 대조 실패는 그 항목만 멈춘다.", RC_STANDING_MAX_FAILS),
    "- 같은 입구 갈래(track)에 더 높은 판이 등록되면 옛 판은 새 항목을 받지 않는다(옛 판정 유지 · 판 번호는 갈래마다 1 부터 · 다른 갈래 판은 막지 않는다).", "",
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
  source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "04_Research/programs/_lib/round_core/v4/load.R"))
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
