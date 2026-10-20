## test_round_core_v1_standing.R — 공통 판정 코어 v1 상설 자격 모드(WP5 · 2026-10-20) 격리 검사
##   실제 등록부 · 판단 원장 · stage_artifacts · 레인 디렉터리에 쓰지 않는다(RC_SA_ROOT · 임시 등록부 · 임시 원장 · 임시 레인).
##   A 사양 검사 · 생성 함수 핀  B 레인 스캔 규칙(사유 코드 전수 · 주석 토큰 양성 대조 · τ_D 창 · 성과 무관 불변)
##   C 등록 → 스캔(시드 + 새 엔진 · 회계 · 재생성 md5) → 중복 없음  D 항목 R2 거부(생성 함수 · 사전등록 · 사양 · 칸 사양 · 엔진)
##   E 측정(대체 워커 · 지문 불일치 재측정) → 판정(코어 P1 판정과 같은 값 · 원장은 보는 창만)  F 보고(통과 push · 미달 일 요약) · Superfan · 상태
##   G 원장 추가 전용(사슬 변조 · 삭제 탐지)  H 새 판(옛 판정 유지 · 옛 판 새 항목 거부 · 판 사이 회계)  I CLI
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
has_reason <- function(C, d, r) { x <- C[C$dir == d]$reasons; length(x) == 1L && r %in% strsplit(x, ";", fixed = TRUE)[[1]] }
source("04_Research/programs/_lib/round_core/v1/load.R")
suppressPackageStartupMessages(library(data.table))

SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_standing")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE), onexit = TRUE))  # r-portability 금칙 ②: 최상위 on.exit 는 no-op
Sys.setenv(RC_SA_ROOT = file.path(SB, "sa"))
REG <- file.path(SB, "research_programs.json"); LED <- file.path(SB, "ledger.json"); RVR <- file.path(SB, "rv"); LANE <- file.path(SB, "lane")
TAU <- "2022-12-31"; HO_AT <- "2026-10-18T10:00:00+0900"
T_BEFORE <- as.POSIXct("2026-10-18 09:00:00", tz = "Asia/Seoul"); T_AFTER <- as.POSIXct("2026-10-18 11:00:00", tz = "Asia/Seoul")
P0RES <- "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results"
ART_E1 <- rc_json_read(file.path(P0RES, "P0R01_E1_C0", "eval.json"))$artifacts
ART_E2 <- rc_json_read(file.path(P0RES, "P0R01_E2_C0", "eval.json"))$artifacts

## ── 레인 고정물(fixture) ─────────────────────────────────────────────────────
PAD <- "## fixture padding — 검증기 하한(200바이트)을 넘기기 위한 설명 줄: 이 엔진은 시험용이며 측정하지 않는다."
E_NATIVE <- c("## fixture — 가격 모멘텀(엔진 고유 방향 · 커넥터 부호 없음)", PAD, "x <- RAWDATA[, .(Date, Ticker, Close)]",
              "x[, s := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]", "FACTORS <- x[is.finite(s), .(Date, Ticker, Score = s)]")
E_FDB <- c(E_NATIVE, "f <- load_month_factors(as.Date('2010-01-29'), factor_names = 'V01_BM')")
E_SIGN <- c(E_NATIVE, "ic_sign <- sign(cumsum(x$s))")
E_COMMENT <- c(E_NATIVE, "# load_month_factors() · align_factor_direction() · ic_sign 은 쓰지 않는다(주석)",
               "cat('load_month_factors ic_sign align_factor_direction — 문자열일 뿐\\n')")
E_PIT <- c(E_NATIVE, "vol <- sd(ret) * sqrt(252)")
E_PARSE <- c(PAD, PAD, "FACTORS <- (")
E_NOOUT <- c(PAD, PAD, "y <- RAWDATA[, .N]")
E_PORT <- c(PAD, PAD, "PORTFOLIO <- data.table(Date = as.Date('2010-01-29'), Ticker = 'A', Weight = -1, Leg = 'short')")
mk_art <- function(nm, d, w, variants = NULL) {
  a <- file.path(SB, "art", nm); dir.create(a, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(run_id = "t", date = d, ticker = paste0("A", seq_along(d)), target_weight = w), file.path(a, "04_holdings.csv"))
  if (!is.null(variants)) rc_json_write(list(schema = "replication_variants_v1", n_variants = variants), file.path(a, "variants_summary.json"))
  a
}
A_OK <- mk_art("ok", c("2010-01-29", "2010-01-29", "2010-02-26", "2023-03-31"), c(0.5, 0.5, 1, 1))
A_TIMING <- mk_art("timing", c("2010-01-29", "2010-02-26"), c(1, -1))
A_TPOST <- mk_art("tpost", c("2010-01-29", "2010-02-26", "2023-03-31"), c(1, 1, -1), variants = 3L)
mk_dir <- function(nm, eng, key, url = TRUE, fidelity = "faithful", audit = "faithful", mtime = T_BEFORE) {
  d <- file.path(LANE, nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(eng, paste("##", nm)), file.path(d, "engine.R"), useBytes = TRUE); Sys.setFileTime(file.path(d, "engine.R"), mtime)   # 디렉터리마다 다른 엔진(md5)
  rc_json_write(list(fidelity = fidelity, kept = "k", changed = "c"), file.path(d, "FIDELITY.json"))
  if (!is.null(audit)) rc_json_write(list(verdict = audit), file.path(d, "fidelity_audit.json"))
  if (isTRUE(url)) rc_json_write(list(paper_key = key, paper_url = paste0("https://arxiv.org/abs/", key)), file.path(d, "lane_provenance.json"))
  d
}
ho <- function(nm, key, art = A_OK, ...) {
  it <- list(key = paste0("engine:RP_T_", nm), kind = "engine", base_status = "engine", title = paste("시험 엔진", nm), paper_key = key,
             base_id = paste0("RP_T_", nm), grade = "F", fidelity = "faithful", artifacts = art,
             engine_path = file.path(LANE, nm, "engine.R"), routed_by = "program_queue", cr_verdict = "weak",
             implementation_suspect = FALSE, has_short = FALSE, audit_verdict = "faithful", enqueued_at = HO_AT)
  modifyList(it, list(...))
}
FX <- list(   # 이름 · 엔진 · 키 · 인계 수정 · 기대 사유(NULL = 통과)
  list("RP_AUTO_T_NATIVE", E_NATIVE, "9901.00001", list(), NULL),
  list("RP_AUTO_T_COMMENT", E_COMMENT, "9901.00002", list(), NULL),
  list("RP_AUTO_T_TPOST", E_NATIVE, "9901.00003", list(artifacts = A_TPOST), NULL),
  list("RP_AUTO_T_SUSPECT", E_NATIVE, "9901.00004", list(implementation_suspect = TRUE), "implementation_suspect"),
  list("RP_AUTO_T_SUSPNA", E_NATIVE, "9901.00005", list(implementation_suspect = NULL), "implementation_suspect"),
  list("RP_AUTO_T_MISDECL", E_NATIVE, "9901.00006", list(audit_verdict = "misdeclared"), "audit_not_passed"),
  list("RP_AUTO_T_AUDFILE", E_NATIVE, "9901.00007", list(), "audit_not_passed"),
  list("RP_AUTO_COMBO_T", E_NATIVE, "9901.00008", list(fidelity = "combination"), "combination"),
  list("RP_AUTO_T_FDB", E_FDB, "9901.00009", list(), "dynamic_sign"),
  list("RP_AUTO_T_SIGN", E_SIGN, "9901.00010", list(), "dynamic_sign"),
  list("RP_AUTO_T_TIMING", E_PORT, "9901.00011", list(artifacts = A_TIMING), "long_leg_absent"),
  list("RP_AUTO_T_NOART", E_NATIVE, "9901.00012", list(artifacts = file.path(SB, "art", "none")), "long_leg_unverifiable"),
  list("RP_AUTO_T_P2", E_NATIVE, "9901.00013", list(), "not_routed"),
  list("RP_AUTO_T_NOHAND", E_NATIVE, "9901.00014", NULL, "no_handoff"),
  list("RP_AUTO_T_EDITED", E_NATIVE, "9901.00015", list(), "engine_changed_since_handoff"),
  list("RP_AUTO_T_MD5HO", E_NATIVE, "9901.00016", list(engine_md5 = "00000000000000000000000000000000"), "engine_changed_since_handoff"),
  list("RP_AUTO_T_PIT", E_PIT, "9901.00017", list(), "pit_static"),
  list("RP_AUTO_T_PARSE", E_PARSE, "9901.00018", list(), "engine_parse_failed"),
  list("RP_AUTO_T_NOOUT", E_NOOUT, "9901.00019", list(), "output_contract_unknown"),
  list("RP_AUTO_T_NOURL", E_NATIVE, "localkey", list(), "paper_meta_missing"),
  list("RP_AUTO_T_SMALL", "x <- 1", "9901.00021", list(), "no_engine"),
  list("RP_AUTO_T_ZDUP", E_NATIVE, "9901.00022", list(enqueued_at = "2026-10-18T10:30:00+0900"), NULL))   # NATIVE 와 바이트 같은 엔진(아래에서 복사)
reg <- rc_json_read("06_Registry/research_programs.json")
pidx <- function(id) which(vapply(reg$programs, function(p) p$id, "") == id)
for (f in FX) {
  nm <- f[[1]]
  mk_dir(nm, f[[2]], f[[3]], url = !identical(f[[3]], "localkey"), fidelity = if (grepl("COMBO", nm)) "combination" else "faithful",
         audit = if (nm == "RP_AUTO_T_AUDFILE") "unverifiable" else if (nm == "RP_AUTO_T_MISDECL") "misdeclared" else "faithful",
         mtime = if (nm == "RP_AUTO_T_EDITED") T_AFTER else T_BEFORE)
  if (is.null(f[[4]])) next
  it <- do.call(ho, c(list(nm, f[[3]]), f[[4]]))
  if (nm == "RP_AUTO_T_SUSPNA") it$implementation_suspect <- NULL
  prog <- if (nm == "RP_AUTO_T_P2") "P2_DEFENSE" else "P1_RETURN"
  reg$programs[[pidx(prog)]]$queue <- c(reg$programs[[pidx(prog)]]$queue, list(it))
}
rc_json_write(reg, REG)
invisible(file.copy(file.path(LANE, "RP_AUTO_T_NATIVE", "engine.R"), file.path(LANE, "RP_AUTO_T_ZDUP", "engine.R"), overwrite = TRUE))
Sys.setFileTime(file.path(LANE, "RP_AUTO_T_ZDUP", "engine.R"), T_BEFORE)

cat("A 사양 검사 · 생성 함수 핀\n")
pin <- rc_standing_generator_pin()
chk("A1 생성 함수 핀 — 함수 md5 · 선례 md5 · 정본 고정 축(활성 측정 축)", nchar(pin$fn_md5) == 32L && identical(pin$like_md5, rc_md5(RC_P1_LIKE)) &&
      identical(pin$canon$measurement_axis, rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active")))
chk("A2 핀은 결정론(두 번 계산 동일 · 차이 0)", !length(rc_standing_pin_diff(pin, rc_standing_generator_pin())))
RD <- file.path(SB, "round", "P1S99_standing_selftest"); RID <- "P1S99_standing_selftest"
SEEDS <- lapply(c("E2", "E1"), function(e) list(code = sprintf("P0R01_%s_C0", e), engine = e, role = "reference", source_results = P0RES))
mk_round <- function(rd, rid, seeds, edition = 1L, scan = list(lane_root = LANE))
  rc_init_standing_p1(rd, rid, seeds, purpose = "상설 자격 자체 시험(격리)", hypothesis = "P1R01 규칙 · 레인 스캔 규칙 재현", edition = edition,
                      scan = scan, exposures = list("시험 창 성과를 본 상태(보고 전용)"), conclusion_scope = list("자체 시험"), bcfg = NULL)
chk("A3 골격 생성(standing: true · 규칙 = P1 템플릿 · 검사 통과)", identical(err_of(mk_round(RD, RID, SEEDS)), ""))
S0 <- rc_spec_load(file.path(RD, "round_spec.json"))
tmpl <- .rcs_p1_template_rules()
chk("A4 규칙 = rc_init_p1 템플릿 선언 그대로(사본 없음 · t ≥ 정본 참조 · 상승 포착 0.55 · 시험 창 보고 전용)",
    identical(S0$rules, tmpl) && identical(rc_rules_resolve(S0$rules)[[1]]$of[[1]]$value, 2) && identical(rc_rules_resolve(S0$rules)[[1]]$of[[2]]$value, 0.55))
bad <- S0; bad$standing_cfg <- NULL
chk("A5 standing_cfg 없음 = 거부", grepl("standing_cfg", err_of(rc_standing_validate(bad))))
bad <- S0; bad$standing_cfg$scan$orientation_admit <- list("anything")
chk("A6 방향 층 허용 목록 어휘 밖 = 거부", grepl("orientation_admit", err_of(rc_standing_validate(bad))))
bad <- S0; bad$rules[[1]]$of[[1]]$metric <- "t_alpha_test"
chk("A7 판정 규칙이 시험 창 열 = 거부(τ_D)", grepl("시험 창", err_of(rc_standing_validate(bad))))
bad <- S0; bad$cells[[1]]$role <- "variant"
chk("A8 시드가 variant = 거부(새 엔진은 스캔이 넣는다)", grepl("reference", err_of(rc_standing_validate(bad))))
bad <- S0; bad$standing_cfg$generator_pin$fn_md5 <- "0"
chk("A9 낡은 생성 함수 핀 = 거부(check_pin)", grepl("generator_pin", err_of(rc_standing_validate(bad))))
bad <- S0; bad$standing_cfg$scan$long_leg_window <- "full"
chk("A10 롱 레그 창 = 보는 창만", grepl("long_leg_window", err_of(rc_standing_validate(bad))))
md <- rc_standing_rules_md(S0)
chk("A11 규칙 문서 — 선언에서 생성(규칙 문장 · 사유 코드 전수 · 핀)", any(grepl("t_alpha_vis >= 2", md)) && all(vapply(names(RC_STANDING_REASONS), function(k) any(grepl(k, md, fixed = TRUE)), TRUE)) &&
      any(grepl(pin$fn_md5, md, fixed = TRUE)))

cat("B 레인 스캔 규칙\n")
SC <- S0$standing_cfg$scan
C <- rc_standing_lane_candidates(SC, registry_path = REG, tau = TAU, lane_root = LANE)
chk("B1 디렉터리마다 1행", nrow(C) == length(FX), paste(nrow(C), length(FX)))
want_ok <- vapply(Filter(function(f) is.null(f[[5]]), FX), function(f) f[[1]], "")
chk("B2 입구 통과 = 고유 방향 · 감사 통과 · 꼬리표 없음 · 롱 레그 · PIT 깨끗 · 논문 메타(4건 — 바이트 같은 엔진 1건 포함)", setequal(C[eligible == TRUE]$dir, want_ok),
    paste(C[eligible == TRUE]$dir, collapse = ","))
for (f in Filter(function(f) !is.null(f[[5]]), FX))
  chk(sprintf("B3 %s → %s", sub("^RP_AUTO_", "", f[[1]]), f[[5]]), has_reason(C, f[[1]], f[[5]]), C[C$dir == f[[1]]]$reasons)
chk("B4 주석 · 문자열 속 이름은 방향 층이 아니다(파서 토큰 — 양성 대조)", identical(C[dir == "RP_AUTO_T_COMMENT"]$orientation, "engine_native") &&
      identical(C[dir == "RP_AUTO_T_FDB"]$orientation, "factor_db_asof") && identical(C[dir == "RP_AUTO_T_SIGN"]$orientation, "orientation_layer"))
chk("B5 롱 레그 창 = 보는 창(τ_D 뒤 숏 전용 날은 보지 않는다)", isTRUE(C[dir == "RP_AUTO_T_TPOST"]$eligible) && identical(C[dir == "RP_AUTO_T_TIMING"]$long_leg, "1/2"))
chk("B6 스캔 표에 성과 열이 없다(등급 · PORT_t · CR · 성과 수치를 입구에 쓰지 않는다)",
    !any(c("grade", "base_port_t", "cr_verdict", "port_t", "cagr", "calmar") %in% names(C)))
reg2 <- rc_json_read(REG); q <- reg2$programs[[pidx("P1_RETURN")]]$queue
for (i in seq_along(q)) if (identical(q[[i]]$base_id, "RP_T_RP_AUTO_T_NATIVE")) { q[[i]]$grade <- "A"; q[[i]]$base_port_t <- 9.9; q[[i]]$cr_verdict <- "strong" }
reg2$programs[[pidx("P1_RETURN")]]$queue <- q; REG2 <- file.path(SB, "reg_perf_flip.json"); rc_json_write(reg2, REG2)
C2 <- rc_standing_lane_candidates(SC, registry_path = REG2, tau = TAU, lane_root = LANE)
chk("B7 성과 무관 불변 — 인계 등급 · PORT_t · CR 을 바꿔도 입구 판정 동일(음성 대조)", identical(C$eligible, C2$eligible) && identical(C$reasons, C2$reasons))
SCp <- SC; SCp$orientation_admit <- list("engine_native", "factor_db_asof")
C3 <- rc_standing_lane_candidates(SCp, registry_path = REG, tau = TAU, lane_root = LANE)
chk("B8 방향 정책 대안(C13 표준 as-of 정렬 허용) — FDB 통과 · 부호 층은 그대로 제외", isTRUE(C3[dir == "RP_AUTO_T_FDB"]$eligible) && has_reason(C3, "RP_AUTO_T_SIGN", "dynamic_sign"))
chk("B9 논문 메타 — lane_provenance url · 키 없는 url 은 arXiv 키 유도만", identical(C[dir == "RP_AUTO_T_NATIVE"]$url_source, "lane_provenance"))
dr <- rc_standing_scan(RD, dry_run = TRUE, registry_path = REG)
chk("B10 등록 전 dry-run — 판독만(원장 없음 · 칸 사양 없음)", nrow(dr$table) == length(FX) && !file.exists(rc_paths(RD, S0)$sa_dir) &&
      !length(list.files(file.path(RD, "specs"))))

cat("C 등록 → 스캔 → 회계\n")
review <- function(rd, v) { f <- file.path(SB, sprintf("review_%s_v%d.md", basename(rd), v)); writeLines("점검 ok", f); rc_mark_reviewed(rd, v, f, "ok") }
p1_review <- function(rid) {
  tag <- rc_round_tag(rid); rvf <- sprintf("04_Research/programs/_supervision/superfan/philosophy/20261020_1200_P1_%s.md", tag)
  dir.create(dirname(file.path(RVR, rvf)), recursive = TRUE, showWarnings = FALSE); writeLines("P1 리뷰", file.path(RVR, rvf))
  L <- if (file.exists(LED)) rc_json_read(LED) else list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = list(), challenges = list())
  L$reviews <- c(L$reviews, list(list(id = paste0("R-", tag), role = "philosophy", trigger = "P1", round = rid, file = rvf, challenges = list())))
  writeLines(as.character(jsonlite::toJSON(L, auto_unbox = TRUE, null = "null", pretty = TRUE)), LED, useBytes = TRUE)
}
register <- function(rd, rid) { rc_draft(rd); review(rd, 1L); p1_review(rid)
  rc_register(rd, registry_path = REG, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR) }
r <- tryCatch(register(RD, RID), error = function(e) e)
chk("C1 상설 판 등록(임시 등록부 · 두 사본)", !inherits(r, "error"), if (inherits(r, "error")) conditionMessage(r) else "")
P <- rc_paths(RD, S0); LEDGER <- file.path(P$sa_dir, "standing_ledger.jsonl"); REG_MD5_AT_REGISTER <- rc_md5(REG)
sc1 <- tryCatch(rc_standing_scan(RD, registry_path = REG), error = function(e) e)
chk("C2 스캔 — 시드 2 + 새 엔진 3 넣음(바이트 같은 엔진은 먼저 인계된 1개만 — 인계 시각 순)", !inherits(sc1, "error") && length(sc1$enqueued) == 5L &&
      !any(grepl("9901_00022", sc1$enqueued)) && identical(sc1$table[dir == "RP_AUTO_T_ZDUP"]$status, "new"),
    if (inherits(sc1, "error")) conditionMessage(sc1) else paste(sc1$enqueued, collapse = ","))
recs <- rc_standing_ledger_read(LEDGER); I <- rc_standing_items(recs)
chk("C3 원장 사슬 정상 · enqueue 5 + scan 1", rc_standing_ledger_verify(LEDGER)$ok && sum(vapply(recs, function(x) identical(x$event, "enqueue"), TRUE)) == 5L)
code_of <- function(key) names(I)[vapply(I, function(it) identical(it$paper$paper_key, key), TRUE)]
CN <- code_of("9901.00001"); CC <- code_of("9901.00002"); CT <- code_of("9901.00003")
chk("C4 항목 code = 판 태그 + 키 + 엔진 md5 앞 6자", length(CN) == 1L && grepl("^P1S99_9901_00001_[0-9a-f]{6}$", CN), paste(CN))
gs <- rc_json_read(rc_abs(I[[CN]]$cell_spec)); ref <- rc_json_read(RC_P1_LIKE)
chk("C5 칸 사양 = 등록 생성 함수(선례 고정 축 · 활성 측정 축 · 엔진 경로 · 논문)",
    identical(gs$fixed_axes[setdiff(names(ref$fixed_axes), "measurement_axis")], ref$fixed_axes[setdiff(names(ref$fixed_axes), "measurement_axis")]) &&
      identical(gs$fixed_axes$measurement_axis, pin$canon$measurement_axis) && identical(gs$base_signal$path, file.path(LANE, "RP_AUTO_T_NATIVE", "engine.R")) &&
      identical(gs$root_paper$paper_key, "9901.00001") && identical(gs$weighting, ref$weighting))
chk("C6 원장 칸 사양 md5 = 파일 = 재생성(재량 없음)", identical(I[[CN]]$cell_spec_md5, rc_md5(rc_abs(I[[CN]]$cell_spec))) &&
      identical(rc_standing_regen_md5(I[[CN]], rc_standing_context(RD, registry_path = REG)), I[[CN]]$cell_spec_md5))
chk("C7 시행 회계 — 새 계보 = max(0, 레인 1) + 1 = 2 · 변형 3 레인 = 3 + 1 = 4 · 시드 무가산(원천 = 등록본)",
    identical(as.integer(I[[CN]]$n_family), 2L) && identical(as.integer(I[[CT]]$n_family), 4L) && identical(I[["P0R01_E2_C0"]]$source, "seed") &&
      identical(I[["P0R01_E2_C0"]]$source_results, P0RES))
sc2 <- rc_standing_scan(RD, registry_path = REG)
chk("C8 두 번째 스캔 — 새로 넣는 항목 0(같은 엔진 md5 중복 금지)", !length(sc2$enqueued) && length(rc_standing_items(rc_standing_ledger_read(LEDGER))) == 5L)
chk("C9 측정 대기 = 스캔 항목 3(공유 측정 시드 제외)", setequal(rc_standing_pending(RD, registry_path = REG), c(CN, CC, CT)))
chk("C10 등록부는 읽기만(스캔 두 번 뒤에도 등록 직후 md5 그대로)", identical(rc_md5(REG), REG_MD5_AT_REGISTER) &&
      length(Filter(function(r) identical(r$round_id, RID), pr_get(pr_load(path = REG), "P1_RETURN")$rounds)) == 1L)

cat("D 항목 R2 거부\n")
FP <- function() "fp-stable"
STUB <- file.path(SB, "stub_worker.R")
writeLines(c("a <- commandArgs(trailingOnly = TRUE); code <- a[3]; out <- a[4]",
             sprintf("art <- if (grepl('9901_00002', code)) '%s' else '%s'", ART_E1, ART_E2),
             "writeLines(as.character(jsonlite::toJSON(list(n = 1, code = code, ok = TRUE, artifacts = art), auto_unbox = TRUE)), out)"), STUB)
orig_gen <- rc_p1_cell_spec
assign("rc_p1_cell_spec", function(...) { s <- orig_gen(...); s }, envir = globalenv())
chk("D1 생성 함수가 바뀌면(md5 ≠ 등록 핀) 측정 · 판정 거부(R2 · 새 판 필요)", grepl("생성 함수 핀", err_of(rc_standing_measure_item(RD, CN, registry_path = REG, worker = STUB, fingerprint = FP))))
assign("rc_p1_cell_spec", orig_gen, envir = globalenv())
pb <- readBin(P$prereg, "raw", file.info(P$prereg)$size); cat("x", file = P$prereg, append = TRUE)
chk("D2 사전등록 변조 = 거부(md5 ≠ 등록부)", grepl("R2", err_of(rc_standing_judge(RD, registry_path = REG))))
writeBin(pb, P$prereg)
sb <- readBin(file.path(RD, "round_spec.json"), "raw", file.info(file.path(RD, "round_spec.json"))$size); cat(" ", file = file.path(RD, "round_spec.json"), append = TRUE)
chk("D3 등록 뒤 사양 변경 = 거부", grepl("사양이 등록 뒤 바뀌었다", err_of(rc_standing_pending(RD, registry_path = REG))))
writeBin(sb, file.path(RD, "round_spec.json"))
tsp <- rc_abs(I[[CT]]$cell_spec); tb <- readBin(tsp, "raw", file.info(tsp)$size); cat(" ", file = tsp, append = TRUE)
chk("D4 칸 사양 변조 = 그 항목 측정 거부 · 원장 r2 기록 · 대기 목록에서 빠짐",
    grepl("cell_spec_md5_changed", err_of(rc_standing_measure_item(RD, CT, registry_path = REG, worker = STUB, fingerprint = FP))) &&
      !(CT %in% rc_standing_pending(RD, registry_path = REG)))
writeBin(tb, tsp)
cep <- file.path(LANE, "RP_AUTO_T_COMMENT", "engine.R"); cb <- readBin(cep, "raw", file.info(cep)$size); cat("# 수정\n", file = cep, append = TRUE)
chk("D5 엔진 변경 = 그 항목 측정 거부(engine_md5_changed)", grepl("engine_md5_changed", err_of(rc_standing_measure_item(RD, CC, registry_path = REG, worker = STUB, fingerprint = FP))))
writeBin(cb, cep)
## D6 — 생성 함수를 거치지 않은 칸 사양(손으로 만든 사양 · md5 는 원장과 일치)을 원장에 직접 넣으면 재생성 대조가 잡는다(양성 대조)
hd <- mk_dir("RP_AUTO_T_HAND", E_NATIVE, "9901.00099"); ctxD <- rc_standing_context(RD, registry_path = REG)
hp <- list(url = "https://arxiv.org/abs/9901.00099", title = "손 사양", paper_key = "9901.00099"); hcode <- "P1S99_9901_00099_hand00"
hs <- rc_p1_cell_spec(hcode, file.path(hd, "engine.R"), hp, "9901.00099", 2L, "손 사양 시험"); hs$weighting <- list(kind = "catalog", catalog_id = "lean:entropy")
hsp <- file.path(RD, "specs", paste0(hcode, ".json")); rc_json_write(hs, hsp)
rc_standing_append(ctxD, list(event = "enqueue", code = hcode, engine = "hand", role = "variant", source = "manual", engine_path = file.path(hd, "engine.R"),
                              engine_md5 = rc_md5(file.path(hd, "engine.R")), cell_spec = rc_rel(hsp), cell_spec_md5 = rc_md5(hsp), paper = hp,
                              family_root = "9901.00099", n_family = 2L, n_trials_basis = "손 사양 시험"))
chk("D6 손으로 만든 칸 사양(md5 일치여도) = 재생성 불일치로 측정 거부(cell_spec_not_regenerable)",
    grepl("cell_spec_not_regenerable", err_of(rc_standing_measure_item(RD, hcode, registry_path = REG, worker = STUB, fingerprint = FP))) &&
      !(hcode %in% rc_standing_pending(RD, registry_path = REG)))

cat("E 측정 → 판정\n")
m1 <- rc_standing_measure_item(RD, CN, registry_path = REG, worker = STUB, fingerprint = FP)
chk("E1 측정(정본 워커 자리 · 대체 워커) — ok · 지문 동일 · 결과 md5", isTRUE(m1$ok) && isTRUE(m1$fp_same) && !is.na(m1$result_md5))
flip <- local({ i <- 0L; function() { i <<- i + 1L; paste0("fp-", i) } })
m2 <- rc_standing_measure_item(RD, CT, registry_path = REG, worker = STUB, fingerprint = flip)
chk("E2 측정 중 데이터 지문이 바뀌면 그 측정은 쓰지 않는다(대기 유지 · 재측정)", isTRUE(m2$ok) && isFALSE(m2$fp_same) && CT %in% rc_standing_pending(RD, registry_path = REG))
invisible(rc_standing_measure_item(RD, CT, registry_path = REG, worker = STUB, fingerprint = FP))
invisible(rc_standing_measure_item(RD, CC, registry_path = REG, worker = STUB, fingerprint = FP))
chk("E3 측정 대기 0(R2 차단 해소 뒤 재측정 포함)", !length(rc_standing_pending(RD, registry_path = REG)))
eval_stub <- function(root, round_dir, cell, env, tau) {
  src <- if (grepl("9901_00002", cell$code)) "P0R01_E1_C0" else "P0R01_E2_C0"
  ev <- rc_json_read(file.path(P0RES, src, "eval.json")); ev$code <- cell$code; ev$engine <- cell$engine
  od <- file.path(round_dir, "results", cell$code); dir.create(od, recursive = TRUE, showWarnings = FALSE); rc_json_write(ev, file.path(od, "eval.json")); ev
}
eval_flaky <- function(root, round_dir, cell, env, tau) if (grepl("9901_00003", cell$code)) stop("칸 평가 시험 예외") else eval_stub(root, round_dir, cell, env, tau)
J0 <- tryCatch(rc_standing_judge(RD, registry_path = REG, eval_fun = eval_flaky), error = function(e) e)
I0 <- rc_standing_items(rc_standing_ledger_read(LEDGER))
chk("E4a 칸 평가 예외 = 판정 아님(그 항목만 eval_failed · 판정 없이 다음 judge 로) · 나머지 4건 판정", !inherits(J0, "error") && length(J0$judged) == 4L &&
      is.null(I0[[CT]]$verdict) && identical(I0[[CT]]$eval_fails, 1L) && .rcs_judgeable(I0[[CT]]), if (inherits(J0, "error")) conditionMessage(J0) else "")
J <- tryCatch(rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub), error = function(e) e)
chk("E4 판정 — 시드 E2 · 새 엔진(E2 자료) 2건 통과 · 시드 E1 · 새 엔진(E1 자료) 미달(두 번의 judge 합)", !inherits(J, "error") &&
      setequal(c(J0$qualified, J$qualified), c("P0R01_E2_C0", CN, CT)) && identical(J$judged, CT) && length(c(J0$judged, J$judged)) == 5L,
    if (inherits(J, "error")) conditionMessage(J) else paste(c(J0$qualified, J$qualified), collapse = ","))
I <- rc_standing_items(rc_standing_ledger_read(LEDGER))
core <- rc_p1_evaluate(list(round_id = "X", tau_d = TAU, cells = SEEDS), rc_rules_resolve(S0$rules))
cv <- core$table[code == "P0R01_E2_C0"]; sv <- I[["P0R01_E2_C0"]]$verdict$visible
fvE2 <- rc_json_read(rc_abs(I[["P0R01_E2_C0"]]$verdict$verdict_file))$row
chk("E5 상설 판정 = 코어 P1 판정(같은 입력 · 같은 계약 — t(α) · 상승 포착 · 자격 · JSON 직렬화 허용오차 1e-12)",
    isTRUE(all.equal(sv$t_alpha_vis, cv$t_alpha_vis, tolerance = 1e-12)) && isTRUE(all.equal(sv$uc_vis, cv$uc_vis, tolerance = 1e-12)) &&
      isTRUE(all.equal(fvE2$alpha_ann_test, cv$alpha_ann_test, tolerance = 1e-12)) &&
      identical(I[["P0R01_E2_C0"]]$verdict$qualify, isTRUE(core$table[code == "P0R01_E2_C0"]$qualify)),
    sprintf("%s vs %s", format(sv$t_alpha_vis, digits = 17), format(cv$t_alpha_vis, digits = 17)))
vnames <- unique(unlist(lapply(Filter(function(it) !is.null(it$verdict), I), function(it) names(it$verdict$visible))))
chk("E6 원장 판정 = 보는 창만(시험 창 열 · test_hold 없음 · τ_D 이후 날짜 없음)", !any(grepl("_test$|^test_hold$", vnames)) &&
      !length(rc_after_tau_leaks(lapply(I, function(it) it$verdict$visible), as.Date(TAU))), paste(vnames, collapse = ","))
fv <- rc_json_read(rc_abs(I[[CN]]$verdict$verdict_file))
chk("E7 사람 쪽 판정 파일 — 시험 창 열 · 시험 창 유지 보고 포함 · md5 = 원장", all(c("alpha_ann_test", "test_hold") %in% names(fv$row)) &&
      identical(rc_md5(rc_abs(I[[CN]]$verdict$verdict_file)), I[[CN]]$verdict$verdict_md5))
vf <- rc_json_read(file.path(RD, "results", "standing_visible.json"))
chk("E8 보는 창 판정 표(standing_visible.json) — 5건 · 시험 창 열 없음", length(vf$items) == 5L && !any(grepl("_test$", unlist(lapply(vf$items, names)))))
J2 <- rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub)
chk("E9 다시 판정해도 새 판정 0(판정 유지) · 판정한 항목은 다시 재지 않는다", !length(J2$judged) &&
      grepl("이미 판정한 항목", err_of(rc_standing_measure_item(RD, CN, registry_path = REG, worker = STUB, fingerprint = FP))))

cat("F 보고 · Superfan · 상태\n")
calls <- list(); snd <- function(...) { calls[[length(calls) + 1L]] <<- list(...); invisible(TRUE) }
rp0 <- rc_standing_report(RD, send = FALSE, registry_path = REG, sender = snd)
chk("F1 dry-run — 통과 3통(push) + 미달 일 요약 1통(무음) · 전부 dry_run · 원장 표식 없음", length(calls) == 4L &&
      all(vapply(calls, function(x) isTRUE(x$dry_run), TRUE)) && sum(vapply(calls, function(x) isTRUE(x$push), TRUE)) == 3L &&
      !any(vapply(rc_standing_ledger_read(LEDGER), function(x) identical(x$event, "reported"), TRUE)))
pc <- Filter(function(x) isTRUE(x$push), calls)[[1]]; dc <- Filter(function(x) !isTRUE(x$push), calls)[[1]]
chk("F1b 일 요약 — 엔진별 판정(2줄) + 입구(마지막 스캔 · 판정 아님) 섹션", length(dc$extra) == 2L && identical(dc$extra[[1]]$type, "bullet") &&
      grepl("입구", dc$extra[[2]]$heading) && grepl("디렉터리", dc$extra[[2]]$body))
chk("F2 통과 1통 — 판정 줄(자격 통과 · 문턱 2.00 · 0.55 · 시험 창 유지 = 사람 쪽 보고)", grepl("자격 통과", pc$verdict_line) && grepl("2.00", pc$verdict_line, fixed = TRUE) &&
      grepl("0.55", pc$verdict_line, fixed = TRUE) && grepl("시험 창 유지", pc$verdict_line))
calls <- list(); rp1 <- rc_standing_report(RD, send = TRUE, registry_path = REG, sender = snd)
calls_sent <- length(calls); calls <- list(); rp2 <- rc_standing_report(RD, send = TRUE, registry_path = REG, sender = snd)
chk("F3 발송 → 원장 표식 → 다시 불러도 0통(중복 발송 없음)", calls_sent == 4L && !length(calls) && length(rp1$pass) == 3L && length(rp1$fail) == 2L)
I <- rc_standing_items(rc_standing_ledger_read(LEDGER)); due <- rc_standing_superfan_due(I)
chk("F4 Superfan 대기 — 통과 3(즉시 T2 · P2) · 미달 일 묶음 1일(2건)", length(due$pass) == 3L && length(due$daily) == 1L && length(due$daily[[1]]) == 2L)
rc_standing_mark_superfan(RD, due$pass, "pass", p2 = "R-P2-x", t2 = "R-T2-x", registry_path = REG)
rc_standing_mark_superfan(RD, due$daily[[1]], "daily", p2 = "R-P2-d", t2 = "R-T2-d", day = names(due$daily)[1], registry_path = REG)
due2 <- rc_standing_superfan_due(rc_standing_items(rc_standing_ledger_read(LEDGER)))
chk("F5 Superfan 표식 뒤 대기 0 · 원장에 없는 항목 표식 = 거부", !length(due2$pass) && !length(due2$daily) &&
      grepl("원장에 없는", err_of(rc_standing_mark_superfan(RD, "NOPE", "pass", registry_path = REG))))
st <- rc_standing_status_lines(RD, registry_path = REG)
chk("F6 상태 줄 — 항목 6(시드 2 · 스캔 3 · 손 1) · 판정 5(통과 3 · 미달 2) · 사슬 정상 · R2 차단 1(손 사양)", grepl("항목 6", st[1]) &&
      grepl("통과 3 · 미달 2", st[1]) && grepl("사슬 정상", st[1]) && any(grepl("R2 차단.*hand00", st)), paste(st, collapse = " | "))

cat("G 원장 추가 전용\n")
lb <- readBin(LEDGER, "raw", file.info(LEDGER)$size); L <- readLines(LEDGER, encoding = "UTF-8")
L2 <- L; L2[2] <- sub("\"source\":\"seed\"", "\"source\":\"seeX\"", L2[2], fixed = TRUE); writeLines(L2, LEDGER, useBytes = TRUE)
v <- rc_standing_ledger_verify(LEDGER)
chk("G1 중간 줄 변조 = 사슬 끊김(다음 줄) · 추가 거부", !identical(L2[2], L[2]) && !v$ok && 3L %in% v$bad &&
      grepl("사슬", err_of(rc_standing_mark_superfan(RD, CN, "pass", registry_path = REG))), paste(v$bad, collapse = ","))
writeBin(lb, LEDGER); L3 <- L[-3]; writeLines(L3, LEDGER, useBytes = TRUE)
chk("G2 줄 삭제 = 사슬 끊김", !rc_standing_ledger_verify(LEDGER)$ok)
writeBin(lb, LEDGER)
chk("G3 복원 뒤 사슬 정상", rc_standing_ledger_verify(LEDGER)$ok)
lk <- paste0(LEDGER, ".lock"); dir.create(lk); assign("RC_STANDING_LOCK_WAIT_S", 1, envir = globalenv())
e_held <- err_of(rc_standing_mark_superfan(RD, CN, "pass", registry_path = REG))
Sys.setFileTime(lk, Sys.time() - 1200)
e_stale <- tryCatch({ withCallingHandlers(rc_standing_mark_superfan(RD, CN, "pass", registry_path = REG), warning = function(w) invokeRestart("muffleWarning")); "" },
                    error = function(e) conditionMessage(e))
assign("RC_STANDING_LOCK_WAIT_S", 30, envir = globalenv())
chk("G4 원장 추가 잠금 — 잡힌 잠금은 기다리다 거부(사슬 갈라짐 방지) · 10분 넘은 잠금은 치우고 추가", grepl("잠금 대기 초과", e_held) && identical(e_stale, "") &&
      !dir.exists(lk) && rc_standing_ledger_verify(LEDGER)$ok, paste(e_held, "|", e_stale))

cat("H 새 판\n")
led1_md5 <- rc_md5(LEDGER)
RD2 <- file.path(SB, "round", "P1S98_standing_selftest2"); RID2 <- "P1S98_standing_selftest2"
mk_round(RD2, RID2, list(list(code = "P0R01_E3_C0", engine = "E3", role = "reference", source_results = P0RES)), edition = 2L)
r2 <- tryCatch(register(RD2, RID2), error = function(e) e)
chk("H1 새 판(판 2) 등록", !inherits(r2, "error"), if (inherits(r2, "error")) conditionMessage(r2) else "")
invisible(mk_dir("RP_AUTO_T_NATIVE2", c(E_NATIVE, "## 재구현 판(같은 논문 · 다른 엔진)"), "9901.00001"))
reg3 <- rc_json_read(REG); reg3$programs[[pidx("P1_RETURN")]]$queue <- c(reg3$programs[[pidx("P1_RETURN")]]$queue, list(ho("RP_AUTO_T_NATIVE2", "9901.00001")))
rc_json_write(reg3, REG)
sc3 <- tryCatch(rc_standing_scan(RD2, registry_path = REG), error = function(e) e)
I2 <- if (inherits(sc3, "error")) list() else rc_standing_items(rc_standing_ledger_read(file.path(rc_paths(RD2, rc_spec_load(file.path(RD2, "round_spec.json")))$sa_dir, "standing_ledger.jsonl")))
CN2 <- names(I2)[vapply(I2, function(it) identical(it$source, "scan"), TRUE)]
chk("H2 새 판 스캔 — 옛 판에서 판정한 엔진은 넣지 않는다(옛 판정 유지) · 새 엔진만", !inherits(sc3, "error") && length(CN2) == 1L &&
      identical(I2[[CN2]]$paper$paper_key, "9901.00001") && !any(vapply(I2, function(it) identical(it$engine_md5, I[[CN]]$engine_md5), TRUE)),
    if (inherits(sc3, "error")) conditionMessage(sc3) else paste(names(I2), collapse = ","))
chk("H3 판 사이 회계 — 같은 계보 앞선 상설 항목(2) + 1 = 3", length(CN2) == 1L && identical(as.integer(I2[[CN2]]$n_family), 3L))
chk("H4 옛 판 원장 불변 · 옛 판은 새 항목을 받지 않는다(판정 · 측정은 계속)", identical(rc_md5(LEDGER), led1_md5) &&
      grepl("더 높은 판", err_of(rc_standing_scan(RD, registry_path = REG))) && identical(err_of(rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub)), ""))
eds <- rc_standing_editions("P1_RETURN", registry_path = REG)
chk("H5 등록된 상설 판 목록(판 1 · 판 2)", setequal(eds$round_id, c(RID, RID2)) && setequal(eds$edition, 1:2))

cat("I 생성 함수 양성 대조 · CLI\n")
g2 <- rc_p1_cell_spec("X_E2", "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
                      list(url = "https://arxiv.org/abs/2002.06975", title = "t", paper_key = "2002.06975"), "2002.06975", 1L, "b")
rx <- rc_json_read("04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/specs/P2R04_E2_RX0.json")
same <- setdiff(intersect(names(rx), names(g2)), c("code", "label", "idea", "selection_accounting", "base_signal", "root_paper", "root_papers"))
tail_rel <- function(p) sub("^.*?/(04_Research/)", "\\1", gsub("\\\\", "/", p), perl = TRUE)
chk("I1 생성 함수(활성 축) = P2R04 E2 RX0 사양(코드 · 이름 · 회계 · 논문 제목 밖 동일 · 엔진 = 같은 저장소 경로)", identical(g2[same], rx[same]) &&
      identical(tail_rel(g2$base_signal$path), tail_rel(rx$base_signal$path)), paste(same, collapse = ","))
e3 <- rc_standing_seed_respec("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E3_C0.json", "X_E3", 1L, "b")
rx3 <- rc_json_read("04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/specs/P2R04_E3_RX0.json")
same3 <- setdiff(intersect(names(rx3), names(e3)), c("code", "label", "idea", "selection_accounting"))
chk("I2 시드 재사양(선례 그대로 · 축만 활성) = P2R04 E3 RX0 사양", identical(e3[same3], rx3[same3]) && identical(e3$selection_accounting$remeasure_of, "P0R01_E3_C0"))
o <- suppressWarnings(system2("Rscript", c(shQuote(file.path(RC_DIR, "standing.R")), shQuote(RD), "standing-status"), stdout = TRUE, stderr = TRUE))
chk("I3 CLI standing-status(기본 등록부 — 이 판은 거기 없으니 '등록 전' 줄)", any(grepl("^\\[상설\\]", o)), paste(tail(o, 2), collapse = " | "))
o2 <- suppressWarnings(system2("Rscript", c(shQuote(file.path(RC_DIR, "standing.R")), shQuote(RD), "nope"), stdout = TRUE, stderr = TRUE))
chk("I4 CLI 모르는 단계 = 실패", !is.null(attr(o2, "status")) && attr(o2, "status") != 0L)

Sys.unsetenv("RC_SA_ROOT")
cat(sprintf("\n== round_core_v1_standing: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1_standing","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
