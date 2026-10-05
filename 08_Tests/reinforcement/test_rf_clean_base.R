#!/usr/bin/env Rscript
#==============================================================================
# test_rf_clean_base.R — A 경로 청정 기저 선정 계약(rf_clean_base.R · 결정 FLOOR-BASE-ENGINE-Q4) 양방향 검사
#
# 재는 것 (전부 tempdir 합성 픽스처 — 루트는 코드·설정 원천으로 읽기만)
#   F  설정 fail-closed — performance_blind 부재 · 성과 필드 허용 · 모르는 노출 통로 · 결정 부재/미결/문구 불일치 → stop
#   S  구조 술어 — 양성 대조(청정 합성 엔진 전 술어 통과) + 위반 주입 12종(결합 레인 · 자기 라벨 · 감사 기각/부재 · PIT 정적 ·
#      C11 격리 원천 · PIT/빈티지 표식 · 패널 부재(NA) · 폭 경계 25/26 · 커버리지 경계 · 지문 밖 원천 · 숨은 로더)
#   X  노출 통로 — 결합 절 · 재구현 피드백의 측정 덤프(양성) vs 논문 인용 수치(음성) · 모르는 재구현 절(NA) · 시계 역전 ·
#      작업 폴더 레인 밖 파일(엔진 전 = 노출 / 엔진 뒤 = 기록만) · 자동 주입 기억 수치(양성) vs 수치 없음(음성) ·
#      성과 경로 열람(양성) vs 코드 열람(음성) · 전사 부재 · 엔진 뒤 전사는 무시(엔진을 쓴 실행 선택)
#   O  순서 — sha256(salt|paper_key) 재도출 일치 · 원장 entry 순서 불변 · salt(결정 decided_at) 교란 → 해시 변화
#   P  성과 비노출 — 원장 성과 필드(base_grade·attempts·status…) 교란 + 성과 산출물(authoritative_remeasure.json) 투입 → 문서 불변
#      / ★돌연변이: 투영을 끄고 등급을 순서 키에 섞은 사본 → 같은 교란에서 선택이 바뀐다(red 를 잰다)
#   V  투영 — rfc_ledger_view 필드 ⊆ 허용 목록
#   L  as-of 팩터 층 배선 — 깊이 = 격자 B1 depths 최대 · 시드·as-of = 설정 · match_floor/literal 분기 · F1 ⊆ F_A 판정
#   D  문서 — 성과 키 0 · 성과 키 주입 검출 · 청정 0 이면 blocked + 청정실 대기열 · 청정 ≥1 이면 draft + 1순위 = 순서 1위
#      · D7 fail-closed — 판독 불가(NA) 통로뿐인 후보는 어느 범위에서도 자격 없음(선정 귀결 · 2026-09-26 적대 검증 추가)
#   W  쓰기 — written → already → 내용 다르면 거부(파일 불변) · verify 드리프트 0 / 원장 엔진 경로 변경 → 드리프트
#   H  숨은 로더 흐름(FA-CLEAN-BASE-PATH) — 진단 전용(2001.04185 형) 통과 · 산출 합류·전역 대입·문자열 참조·다른 함수 경유·:=·파일 쓰기·난수 → 탈락
#   C  청정 레인 출처 기록 대조(FA-CLEAN-BASE-PATH) — 양성 대조 · 증명 없음·차단 문형·sha·시각 창·훅 문맥·웹 사본·User 규칙·폴백·감사 출처 위반 주입 ·
#      (10-03) 새 엔진 경로(C21 옛 디렉터리 · C22 다른 엔진 · C23 engine_rel 부재) · 돌연변이 C20(증명·sha) · C24(경로 대조 삭제)
#   R  읽기 전용 — 루트 지문 전후 동일
# 실행: QM_ROOT=<코드 루트> Rscript --no-environ 08_Tests/reinforcement/test_rf_clean_base.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
cat(sprintf("ROOT(읽기 전용) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && any(nzchar(why))) paste0(" — ", paste(why, collapse = " ")) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
emit <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"rf_clean_base","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ch <- function(x) as.character(unlist(x))   # 문서 배열(AsIs) 비교용
TMP <- normalizePath(tempdir(), winslash = "/")
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)),
                                    tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(TMP, ROOT)) { ng("tempdir 가 루트 안에 있다 — 쓰기 위험(중단)", TMP); emit(); quit(status = 1L) }
LIB <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_clean_base.R")
CFG0 <- file.path(ROOT, "06_Registry/prereg/clean_base_rule.config.json")
for (p in c(LIB, CFG0, file.path(ROOT, "06_Registry/prereg/reference_floors_v2.config.json"), file.path(ROOT, "06_Registry/pit_quarantine.json")))
  if (!file.exists(p)) { ng("원천 부재", p); emit(); quit(status = 1L) }
PROD <- c(LIB, CFG0, file.path(ROOT, c("06_Registry/reinforce_ledger_l1.json", "06_Registry/decision_register.json", "06_Registry/pit_quarantine.json",
                                       "06_Registry/prereg/reference_floors_v2.config.json")))
md5_prod <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
PROD0 <- md5_prod()
source(LIB)
EN <- rfc_env(ROOT)

# ── 합성 픽스처 ─────────────────────────────────────────────────────────────────────
FX <- file.path(TMP, "rfc_fx"); TD <- file.path(FX, "_transcripts")
w_json <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write_json(x, p, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA) }
w_txt <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeLines(enc2utf8(x), p, useBytes = TRUE) }
setmt <- function(p, iso) Sys.setFileTime(p, as.POSIXct(iso, tz = "UTC", format = "%Y-%m-%dT%H:%M:%S"))
ENG_CLEAN <- c("suppressPackageStartupMessages(library(data.table))",
               "DT <- as.data.table(RAWDATA)",
               "setorder(DT, Ticker, Date)",
               "DT[, r1 := data.table::shift(Close, 1L, type = \"lag\") / data.table::shift(Close, 2L, type = \"lag\") - 1, by = Ticker]",
               "FACTORS <- DT[is.finite(r1), .(Date, Ticker, Score = -r1)]")
PROMPT_OK <- c("논문 1편의 **충실구현**을 수행하라.", "## 논문", "제목: 합성", "## 산출 (이것만)", "engine.R", "## 공리 (전제 — 지시가 아니다)", "- AX-000 · 한계란 없다")
panel <- function(n_names, first = "2005-01-31", n_months = 12L) {
  ds <- seq(as.Date(format(as.Date(first), "%Y-%m-01")), by = "month", length.out = n_months + 1L)[-1L] - 1L
  rbindlist(lapply(ds, function(d) data.table(Date = d, Ticker = sprintf("A%05d", seq_len(n_names)), Score = seq_len(n_names) / n_names)))
}
tr_lines <- function(eng_dir, ts, automem = "기억 색인 — 수치 없음", reads = c("02_Infrastructure/alpha_search/run_paper_replication.R")) {
  q <- list(type = "queue-operation", operation = "enqueue", timestamp = ts, sessionId = "s",
            content = paste0("논문 1편의 **충실구현**을 수행하라. 산출 `C:/X/04_Research/strategies/", eng_dir, "/engine.R`"))
  a <- list(type = "attachment", attachment = list(type = "instructions", files = list(list(path = "MEMORY.md", type = "AutoMem", content = automem))))
  tu <- lapply(reads, function(r) list(type = "tool_use", name = "Read", input = list(file_path = r)))
  m <- list(type = "assistant", message = list(role = "assistant", content = tu))
  vapply(list(q, a, m), function(x) as.character(toJSON(x, auto_unbox = TRUE)), "")
}
# 엔진 1개 생성 — opts 로 위반 주입
mk_engine <- function(id, pk, opts = list()) {
  d <- sprintf("04_Research/strategies/%s", id); wd <- file.path(FX, d)
  dir.create(wd, recursive = TRUE, showWarnings = FALSE)
  w_txt(opts$engine %||% ENG_CLEAN, file.path(wd, "engine.R"))
  if (!isTRUE(opts$no_fid)) w_json(list(fidelity = opts$self %||% "faithful"), file.path(wd, "FIDELITY.json"))
  if (!isTRUE(opts$no_audit)) w_json(list(verdict = opts$audit %||% "faithful", undeclared_changes = list(), signal_mismatch = list()), file.path(wd, "fidelity_audit.json"))
  if (!isTRUE(opts$no_prompt)) w_txt(opts$prompt %||% PROMPT_OK, file.path(wd, "prompt.txt"))
  run <- sprintf("stage_artifacts/replication/run_%s", id); rd <- file.path(FX, run)
  w_json(list(run_id = id, run_datetime = "2026-09-10T02:00:00+09:00", start_date = "2005-02-01"), file.path(rd, "00_manifest.json"))
  w_json(list(run_id = id, construction = opts$construction %||% "top_n_long", source_paper_url = sprintf("https://arxiv.org/abs/%s", pk)), file.path(rd, "01_strategy_spec.json"))
  if (!isTRUE(opts$no_panel)) write_parquet(panel(opts$n_names %||% 40L, opts$first %||% "2005-01-31"), file.path(rd, "factors_panel.parquet"))
  if (!is.null(opts$extra)) { w_txt("x", file.path(wd, opts$extra)); setmt(file.path(wd, opts$extra), opts$extra_mt %||% "2026-09-09T23:00:00") }
  setmt(file.path(wd, "prompt.txt"), opts$p_mt %||% "2026-09-10T00:00:00")
  setmt(file.path(wd, "engine.R"), opts$e_mt %||% "2026-09-10T00:30:00")
  setmt(file.path(wd, "fidelity_audit.json"), opts$a_mt %||% "2026-09-10T01:00:00")
  if (!isTRUE(opts$no_transcript)) w_txt(tr_lines(id, opts$tr_ts %||% "2026-09-10T00:05:00.000Z", opts$automem %||% "기억 색인 — 수치 없음",
                                                  opts$reads %||% "C:/X/02_Infrastructure/alpha_search/run_paper_replication.R"),
                                         file.path(TD, sprintf("%s.jsonl", id)))
  if (!is.null(opts$tr2_ts)) w_txt(tr_lines(id, opts$tr2_ts, "PORT_t 9.999 기억"), file.path(TD, sprintf("%s_later.jsonl", id)))
  list(base_id = sprintf("RP_T_%s", id), paper_key = pk, engine_path = paste0("C:/X/", d, "/engine.R"), base_artifacts = paste0("C:/X/", run),
       base_grade = opts$grade %||% "C", status = "exhausted", attempts = list(list(n = 1L, grade = "B", essence = list(port_t = 2.1, calmar = 0.4))),
       base_vintage_flags = opts$flags %||% list())
}
fix_engine_paths <- function(E) lapply(E, function(e) { e$engine_path <- sub("^C:/X", FX, e$engine_path); e$base_artifacts <- sub("^C:/X", FX, e$base_artifacts); e })
write_ledger <- function(E) w_json(list(schema_version = 1L, current_axis = "exec_v2_close_t1", entries = fix_engine_paths(E)), file.path(FX, "06_Registry/reinforce_ledger_l1.json"))
setup_fx <- function() {
  unlink(FX, recursive = TRUE); dir.create(FX, recursive = TRUE)
  G <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
  w_json(list(fixed_axes = G$fixed_axes, blocks = list(list(id = "B1", depths = list(1L, 2L, 3L)))), file.path(FX, "06_Registry/reinforce_program.json"))
  w_json(list(schema = "decision_register_v1", items = list(list(id = "FLOOR-BASE-ENGINE-Q4", status = "resolved", decided_at = "2026-09-25T21:38:52+0900",
                                                                  decision = "Q④ … A 경로용 청정 기저(…)를 별도 floor 로 신설"))), file.path(FX, "06_Registry/decision_register.json"))
  for (f in c("06_Registry/prereg/reference_floors_v2.config.json", "06_Registry/pit_quarantine.json", "06_Registry/fred_availability_rules.json"))
    if (file.exists(file.path(ROOT, f))) { dir.create(dirname(file.path(FX, f)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(ROOT, f), file.path(FX, f)) }
  w_json(list(floors = list(F1 = list(selection_path = list(depth = 2L), reselect = list(picked_ids = list("FA_1", "FA_2"))))), file.path(FX, "06_Registry/prereg/reference_floors_v2.json"))
  cfg <- fromJSON(CFG0, simplifyVector = FALSE); cfg$exposure$transcript$dir <- TD
  w_json(cfg, file.path(FX, "06_Registry/prereg/clean_base_rule.config.json"))
  dir.create(file.path(FX, ".cache/factor_db"), recursive = TRUE); dir.create(TD, recursive = TRUE)
  for (f in c("RAWDATA.parquet", "benchmark.parquet", "factor_db/_m.parquet", "fundamental_merged.parquet")) file.create(file.path(FX, ".cache", f))
}
STUB <- new.env()
mk_stub <- function() {
  STUB$calls <- list()
  STUB$rf_pick_factor_sets <- function(n = 5L, exclude = character(0), seed_offset = 0L, depths = NULL, fallback_paper = NULL, root = NULL, asof = NULL) {
    STUB$calls[[length(STUB$calls) + 1L]] <- list(n = n, depths = depths, seed_offset = seed_offset, asof = asof)
    ch <- sprintf("FA_%d", 1:6); depths <- as.integer(depths %||% seq_len(n))[seq_len(min(n, length(depths %||% seq_len(n))))]
    cells <- lapply(seq_along(depths), function(i) list(code = sprintf("B1_%d", i), label = sprintf("%d팩터 직교(stub)", depths[i]),
                                                         factors = lapply(ch[seq_len(depths[i])], function(z) list(kind = "db", id = z)),
                                                         basis = "stub", selection_basis = "asof_ic", selection_asof = "2005-01-01"))
    list(cells = cells, picked_ids = ch[seq_len(max(depths))], seed_id = ch[1], seed_offset = seed_offset, max_rho = 0.01)
  }
  STUB$rf_root_papers_for <- function(ids, base_paper = NULL, families = NULL, root = NULL) list(papers = list(base_paper), families = character(0), unmapped_families = character(0))
  STUB
}
EN$.fe <- mk_stub()
CFGP <- function() file.path(FX, "06_Registry/prereg/clean_base_rule.config.json")
setup_fx()
BASE <- list(mk_engine("RP_AUTO_T01", "9901.00001"), mk_engine("RP_AUTO_T02", "9901.00002"), mk_engine("RP_AUTO_T03", "9901.00003"))
write_ledger(BASE)
CFG <- rfc_load_cfg(CFGP()); GRID <- fromJSON(file.path(FX, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
FCFG <- fromJSON(file.path(FX, "06_Registry/prereg/reference_floors_v2.config.json"), simplifyVector = FALSE)
cand_of <- function(id) {
  V <- rfc_ledger_view(FX, CFG); C <- rfc_candidates(V, FX, CFG); k <- grep(paste0("/", id, "/"), names(C), fixed = TRUE)
  if (!length(k)) stop("픽스처 후보 없음: ", id)
  C[[k[1]]]
}
TI <- function() rfc_transcript_index(rfc_load_cfg(CFGP()))
S_of <- function(id) rfc_structural(cand_of(id), FX, CFG, EN, GRID)
X_of <- function(id) rfc_exposure(cand_of(id), FX, CFG, EN, FCFG, TI())

# ═══ F 설정 fail-closed ═══
cat("\n[F] 설정 fail-closed\n")
badw <- function(mod, nm) { c1 <- fromJSON(CFGP(), simplifyVector = FALSE); c1 <- mod(c1); p <- file.path(TMP, paste0("rfc_bad_", nm, ".json")); w_json(c1, p); p }
chk(inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$performance_blind <- NULL; c }, "pb")), error = function(e) e), "error"), "F1 performance_blind 부재 → stop")
chk(inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$performance_blind$ledger_fields_allowed <- c(c$performance_blind$ledger_fields_allowed, "base_grade"); c }, "pbg")), error = function(e) e), "error"),
    "F2 성과 필드(base_grade) 허용 → stop")
chk(inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$exposure$scopes$full <- c(c$exposure$scopes$full, "mystery"); c }, "sc")), error = function(e) e), "error"), "F3 모르는 노출 통로 → stop")
chk(inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$exposure$scope <- "nope"; c }, "sc2")), error = function(e) e), "error"), "F4 채택 범위가 scopes 밖 → stop")
DR <- file.path(FX, "06_Registry/decision_register.json"); DR0 <- readLines(DR, warn = FALSE)
w_json(list(items = list(list(id = "FLOOR-BASE-ENGINE-Q4", status = "open", decided_at = "x", decision = "청정 기저"))), DR)
chk(inherits(tryCatch(rfc_salt(FX, CFG), error = function(e) e), "error"), "F5 결정 미결(open) → stop")
w_json(list(items = list(list(id = "FLOOR-BASE-ENGINE-Q4", status = "resolved", decided_at = "x", decision = "Q① 다중검정"))), DR)
chk(inherits(tryCatch(rfc_salt(FX, CFG), error = function(e) e), "error"), "F6 결정 문구에 '청정 기저' 없음 → stop")
w_json(list(items = list()), DR)
chk(inherits(tryCatch(rfc_salt(FX, CFG), error = function(e) e), "error"), "F7 결정 부재 → stop")
writeLines(DR0, DR)
chk(nzchar(rfc_salt(FX, CFG)$salt), "F8 양성 대조 — resolved + '청정 기저' 문구면 salt 도출")

# ═══ S 구조 술어 ═══
cat("\n[S] 구조 술어\n")
VF <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
if (!file.exists(VF)) ng("S0 정본 레인 검증기 부재", VF) else {
  pd <- utils::getParseData(parse(VF, encoding = "UTF-8", keep.source = TRUE))
  lits <- vapply(pd$text[pd$token == "STR_CONST"], function(s) tryCatch(eval(str2lang(s)), error = function(e) ""), "", USE.NAMES = FALSE)
  rx_cfg <- unique(unlist(lapply(CFG$predicates$pit_static$structural_checks, function(k) c(unlist(k$all), unlist(k$none)))))
  miss <- setdiff(rx_cfg, lits)
  chk(length(rx_cfg) > 0L && !length(miss), "S0 구조 검사 정규식 사본 = 정본(rf_replication_verify.R ③) 문자열 상수(동기화 가드)", paste(miss, collapse = " | "))
  lits2 <- lits; lits2[lits2 == rx_cfg[1]] <- paste0(rx_cfg[1], "X")
  chk(length(setdiff(rx_cfg, lits2)) == 1L, "S0b 돌연변이 — 정본 정규식 1개가 바뀌면 가드가 잡는다")
}
s1 <- S_of("RP_AUTO_T01")
chk(isTRUE(s1$ok) && !length(s1$failed), "S1 양성 대조 — 청정 합성 엔진 전 술어 통과", paste(unlist(s1$failed), collapse = ","))
inj <- function(id, pk, opts) { e <- mk_engine(id, pk, opts); write_ledger(c(BASE, list(e))); S_of(id) }
fails <- function(s, k) !isTRUE(s$predicates[[k]]$ok)
s <- inj("RP_AUTO_COMBO_T11", "9901.00011", list()); chk(fails(s, "lane"), "S2 결합 레인 디렉터리 → lane 실패")
e <- mk_engine("RP_AUTO_T12", "combo:9901.1+9901.2", list()); write_ledger(c(BASE, list(e))); s <- S_of("RP_AUTO_T12"); chk(fails(s, "lane"), "S3 paper_key combo: → lane 실패")
s <- inj("RP_AUTO_T13", "9901.00013", list(self = "combination")); chk(fails(s, "fidelity_self"), "S4 자기 라벨 combination → 실패")
s <- inj("RP_AUTO_T14", "9901.00014", list(audit = "misdeclared")); chk(fails(s, "fidelity_audit") && identical(s$predicates$fidelity_audit$verdict, "misdeclared"), "S5 감사 misdeclared → 실패")
s <- inj("RP_AUTO_T15", "9901.00015", list(no_audit = TRUE)); chk(fails(s, "fidelity_audit") && identical(s$predicates$fidelity_audit$verdict, "unverifiable"), "S6 감사 부재 → unverifiable 실패")
s <- inj("RP_AUTO_T16", "9901.00016", list(engine = c(ENG_CLEAN, "FACTORS[, Score := data.table::shift(Score, -1L)]")))
chk(fails(s, "pit_static") && "음수 shift(미래 인덱싱)" %in% ch(s$predicates$pit_static$structural_hits),
    "S7 PIT 정적 — 음수 shift(미래) 주입 → 구조 검사 적중(현행 검출기는 R 음수 shift 를 못 본다)", paste(ch(s$predicates$pit_static$structural_hits), collapse = ","))
s <- inj("RP_AUTO_T27", "9901.00027", list(engine = c(ENG_CLEAN, "vt_scale <- 1", "after_vt <- FACTORS$Score * vt_scale")))
chk(fails(s, "pit_static") && isFALSE(s$predicates$pit_static$detector_clean), "S7b PIT 정적 — 검출기 패턴(VT same-day) 주입 → detect_lookahead 실패",
    paste(ch(s$predicates$pit_static$checks), collapse = ","))
s <- inj("RP_AUTO_T17", "9901.00017", list(engine = c(ENG_CLEAN, "mf <- arrow::read_parquet(file.path(Sys.getenv('QM_ROOT'), '.cache', 'macro_fred.parquet'))")))
chk(fails(s, "c11") && length(s$predicates$c11$sources) > 0L, "S8 C11 — 격리 원천(macro_fred) 참조 → rflf_c11_derive 적중")
s <- inj("RP_AUTO_T18", "9901.00018", list(flags = list(list(flag = "pit_c11")))); chk(fails(s, "flags") && fails(s, "c11"), "S9 기저 표식 pit_c11 → flags·c11 실패")
s <- inj("RP_AUTO_T19", "9901.00019", list(flags = list(list(flag = "fdb_202608_v1")))); chk(fails(s, "flags") && isTRUE(s$predicates$c11$ok), "S10 빈티지 표식 fdb_ → flags 실패(C11 은 무관)")
s <- inj("RP_AUTO_T20", "9901.00020", list(no_panel = TRUE, construction = "engine_direct"))
chk(is.na(s$predicates$output$ok) && !isTRUE(s$ok), "S11 factors_panel 부재 → output NA(미관측 · fail-closed)")
s <- inj("RP_AUTO_T21", "9901.00021", list(n_names = as.integer(GRID$fixed_axes$n_max))); chk(isFALSE(s$predicates$output$ok), "S12 폭 경계 — 중앙 = n_max → 실패")
s <- inj("RP_AUTO_T22", "9901.00022", list(n_names = as.integer(GRID$fixed_axes$n_max) + 1L)); chk(isTRUE(s$predicates$output$ok), "S13 폭 경계 — 중앙 = n_max+1 → 통과")
s <- inj("RP_AUTO_T23", "9901.00023", list(first = "2005-02-28")); chk(isFALSE(s$predicates$coverage$ok), "S14 커버리지 — 첫 신호 2005-02-28 → 실패")
chk(isTRUE(s1$predicates$coverage$ok) && identical(s1$predicates$coverage$first_signal_date, "2005-01-31"), "S15 커버리지 경계 — 첫 월말 2005-01-31 → 통과")
s <- inj("RP_AUTO_T24", "9901.00024", list(engine = c(ENG_CLEAN, "fm <- arrow::read_parquet(file.path(Sys.getenv('QM_ROOT'), '.cache', 'fundamental_merged.parquet'))")))
chk(fails(s, "source_scope") && "fundamental_merged.parquet" %in% unlist(s$predicates$source_scope$uncovered), "S16 지문 밖 원천(fundamental_merged) → 실패")
s <- inj("RP_AUTO_T25", "9901.00025", list(engine = c(ENG_CLEAN, "inv <- load_investor('wide')")))
chk(fails(s, "source_scope") && "load_investor" %in% unlist(s$predicates$source_scope$hidden_loaders), "S17 숨은 로더(load_investor) → 실패")
s <- inj("RP_AUTO_T26", "9901.00026", list(engine = c(ENG_CLEAN, "x <- load_month_factors(as.Date('2005-01-31'))")))
chk(isTRUE(s$predicates$source_scope$ok), "S18 음성 대조 — 지문 안 로더(load_month_factors)는 통과")
write_ledger(BASE)

# ═══ X 노출 통로 ═══
cat("\n[X] 노출 통로\n")
x1 <- X_of("RP_AUTO_T01")
chk(all(vapply(x1, function(z) isFALSE(z$exposed), logical(1))), "X1 양성 대조 — 청정 합성 엔진 전 통로 노출 0",
    paste(names(Filter(function(z) !isFALSE(z$exposed), x1)), collapse = ","))
injx <- function(id, pk, opts) { e <- mk_engine(id, pk, opts); write_ledger(c(BASE, list(e))); X_of(id) }
combo_p <- c(PROMPT_OK[1:3], "## 이 재료들의 이전 구현 (참고용 — 합치는 것이 설계가 아니다)", "- 2002.06975 : engine.R  (단독 다중검정 t 3.589)", PROMPT_OK[4:7])
x <- injx("RP_AUTO_T31", "9901.00031", list(prompt = combo_p)); chk(isTRUE(x$prompt_combo$exposed), "X2 결합 절(교차 entry t) → prompt_combo 노출")
fb_m <- c(PROMPT_OK[1:5], "## ★재구현이다 — 앞 구현이 적대적 충실도 감사에서 기각됐다",
          "- 측정 산출물 authoritative_remeasure.json::replication.paper_basis (cagr=0.119379, sharpe=0.380497)", PROMPT_OK[6:7])
x <- injx("RP_AUTO_T32", "9901.00032", list(prompt = fb_m)); chk(isTRUE(x$prompt_feedback_measured$exposed), "X3 재구현 피드백의 측정 덤프 → 노출")
fb_p <- c(PROMPT_OK[1:5], "## ★재구현이다 — 앞 구현이 적대적 충실도 감사에서 기각됐다",
          "- 논문은 EW Sharpe 0.887 vs min-var 0.917 로 min-variance 를 택했다(원문 §IV)", PROMPT_OK[6:7])
x <- injx("RP_AUTO_T33", "9901.00033", list(prompt = fb_p)); chk(isFALSE(x$prompt_feedback_measured$exposed), "X4 음성 대조 — 논문 인용 수치('=' 덤프 아님)는 비노출")
fb_u <- c(PROMPT_OK[1:5], "## ★재구현 — 새 형식 절", "- cagr=0.5", PROMPT_OK[6:7])
x <- injx("RP_AUTO_T34", "9901.00034", list(prompt = fb_u)); chk(is.na(x$prompt_feedback_measured$exposed), "X5 모르는 재구현 절 머리 → NA(fail-closed)")
x <- injx("RP_AUTO_T35", "9901.00035", list(e_mt = "2026-09-10T02:00:00", tr_ts = "2026-09-10T00:05:00.000Z"))
chk(isTRUE(x$provenance_order$exposed), "X6 시계 역전(엔진이 감사 뒤) → 노출")
x <- injx("RP_AUTO_T36", "9901.00036", list(extra = "_diag.R", extra_mt = "2026-09-09T23:00:00"))
chk(isTRUE(x$wdir_extra_before_engine$exposed) && "_diag.R" %in% unlist(x$wdir_extra_before_engine$before), "X7 레인 밖 파일이 엔진 전 → 노출")
x <- injx("RP_AUTO_T37", "9901.00037", list(extra = "_work", extra_mt = "2026-09-20T00:00:00"))
chk(isFALSE(x$wdir_extra_before_engine$exposed) && "_work" %in% unlist(x$wdir_extra_before_engine$after), "X8 음성 대조 — 엔진 뒤 레인 밖 파일은 기록만")
x <- injx("RP_AUTO_T38", "9901.00038", list(automem = "- 기저 −0.280 → 3.589(최고) · B5_19 Calmar 0.504")); chk(isTRUE(x$transcript_auto_memory$exposed), "X9 자동 주입 기억의 성과 수치 → 노출")
chk(isFALSE(x1$transcript_auto_memory$exposed) && isTRUE(x1$transcript_auto_memory$auto_memory_seen), "X10 음성 대조 — 기억은 주입됐으나 수치 없음 → 비노출")
x <- injx("RP_AUTO_T39", "9901.00039", list(reads = c("C:/X/06_Registry/reinforce_ledger_l1.json"))); chk(isTRUE(x$transcript_tool_reads$exposed), "X11 원장 열람 → 노출")
# (10-04 F_A v2 D2) 구판 X12 는 '다른 엔진 코드 열람 = 비노출'을 기대했다 — 다른 엔진 주석에 실측 PORT_t·Calmar 가 있다(가드 정책 read_allow_basis 09-26 전수).
#   가드 증명 없는 실행의 허용 범위 밖 열람 = 판독 불가(NA)로 정정. 음성 대조는 자기 작업 디렉터리·허용 목록 파일로 옮긴다(X12b·X12c).
x <- injx("RP_AUTO_T40", "9901.00040", list(reads = c("C:/X/04_Research/strategies/RP_AUTO_T02/engine.R")))
chk(is.na(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_scope_out), 1L), "X12 위반 주입(D2) — 다른 엔진 코드 열람 → 판독 불가(허용 범위 밖)")
x <- injx("RP_AUTO_T50", "9901.00050", list(reads = c("C:/X/04_Research/strategies/RP_AUTO_T50/engine.rejected_1.R")))
chk(isFALSE(x$transcript_tool_reads$exposed), "X12b 음성 대조 — 자기 작업 디렉터리 열람은 비노출")
x <- injx("RP_AUTO_T51", "9901.00051", list(reads = c("C:/X/02_Infrastructure/data/load_rawdata.R", "C:/X/.claude/rules/pit.md")))
chk(isFALSE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_scope_out), 0L), "X12c 음성 대조 — 허용 목록(디렉터리·파일 항목) 열람은 비노출")
x <- injx("RP_AUTO_T52", "9901.00052", list(reads = c("C:/Users/x/.claude/plans/p.md")))
chk(is.na(x$transcript_tool_reads$exposed), "X12d 위반 주입(D2) — 저장소 밖 계획서 열람 → 판독 불가")
x <- injx("RP_AUTO_T53", "9901.00053", list(reads = c("C:/X/06_Registry/factor_evidence.json", "C:/X/02_Infrastructure/docs/knowledge_index.md")))
chk(is.na(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_scope_out), 2L), "X12e 위반 주입(D2) — factor_evidence·knowledge_index 열람 → 판독 불가")
x <- injx("RP_AUTO_T54", "9901.00054", list(reads = c("C:/X/02_Infrastructure/data/../../06_Registry/x.json")))
chk(is.na(x$transcript_tool_reads$exposed), "X12f 위반 주입(D2) — '..' 로 허용 디렉터리 탈출 → 판독 불가")
x <- injx("RP_AUTO_T41", "9901.00041", list(no_transcript = TRUE)); chk(isTRUE(x$transcript_missing$exposed) && is.na(x$transcript_auto_memory$exposed), "X13 전사 부재 → 노출(판독 불가)")
x <- injx("RP_AUTO_T42", "9901.00042", list(tr2_ts = "2026-09-10T03:00:00.000Z"))
chk(isFALSE(x$transcript_auto_memory$exposed) && grepl("RP_AUTO_T42.jsonl", x$transcript_missing$transcript, fixed = TRUE),
    "X14 엔진 mtime 뒤 전사(수치 있음)는 무시 — 엔진을 쓴 실행만 본다")
x <- injx("RP_AUTO_T43", "9901.00043", list(no_prompt = TRUE)); chk(isTRUE(x$prompt_missing$exposed) && is.na(x$prompt_feedback_measured$exposed), "X15 프롬프트 부재 → 노출(판독 불가)")
write_ledger(BASE)

# ═══ O 순서 ═══
cat("\n[O] 순서\n")
d1 <- rfc_build(FX, CFGP(), ROOT, EN)
salt <- rfc_salt(FX, CFG)$salt
hh <- vapply(c("9901.00001", "9901.00002", "9901.00003"), function(k) digest::digest(paste(salt, k, sep = "|"), algo = "sha256", serialize = FALSE), "")
exp_order <- sprintf("04_Research/strategies/RP_AUTO_T0%d/engine.R", order(hh))
chk(identical(ch(d1$selection$order), exp_order), "O1 순서 = sha256(salt|paper_key) 재도출과 일치")
write_ledger(rev(BASE)); d2 <- rfc_build(FX, CFGP(), ROOT, EN)
chk(identical(ch(d2$selection$order), ch(d1$selection$order)) && identical(ch(d2$selection$picks), ch(d1$selection$picks)), "O2 원장 entry 순서 뒤집기 → 순서 불변")
write_ledger(BASE)
w_json(list(schema = "decision_register_v1", items = list(list(id = "FLOOR-BASE-ENGINE-Q4", status = "resolved", decided_at = "2026-09-25T21:38:53+0900",
                                                                decision = "청정 기저"))), DR)
d3 <- rfc_build(FX, CFGP(), ROOT, EN)
chk(!identical(unlist(d3$candidates[[1]]$order_hash), unlist(d1$candidates[[1]]$order_hash)), "O3 salt(decided_at 1초) 교란 → 해시가 바뀐다(순서가 salt 에서 온다)")
writeLines(DR0, DR)

# ═══ D 문서 ═══
cat("\n[D] 문서\n")
fk <- rfc_forbidden_keys(d1, CFG$performance_blind$doc_forbidden_key_regex)
chk(!length(fk), "D1 문서 성과 키 0", paste(head(fk, 3), collapse = ","))
chk(length(rfc_forbidden_keys(list(a = list(b = list(port_t = 1))), CFG$performance_blind$doc_forbidden_key_regex)) == 1L, "D2 성과 키 주입(port_t) 검출")
chk(identical(d1$status, "draft_pre_registration") && identical(ch(d1$floors[[1]]$source_engine$engine), ch(d1$selection$order)[1]) &&
      length(d1$floors) == min(as.integer(CFG$pick$n), 3L), "D3 청정 ≥1 → draft · F_A1 = 순서 1위 · n = min(pick.n, 자격)")
chk(identical(d1$floors[[1]]$selection_basis, "as_of") && isFALSE(d1$floors[[1]]$determinism_ok) && isTRUE(d1$floors[[1]]$a_path) &&
      all(c("id", "status", "determinism_ok", "selection_basis", "measurement_regime") %in% names(d1$floors[[1]])), "D4 소비 계약 필드(id·status·determinism_ok·selection_basis=as_of·measurement_regime)")
mem_all <- lapply(BASE, function(e) { e$engine_path <- e$engine_path; e })
X2 <- lapply(1:3, function(i) mk_engine(sprintf("RP_AUTO_T0%d", i), sprintf("9901.0000%d", i), list(automem = "PORT_t 3.133 · Calmar 0.504")))
write_ledger(X2); d4 <- rfc_build(FX, CFGP(), ROOT, EN)
chk(identical(d4$status, "blocked_no_clean_candidate") && !length(ch(d4$selection$picks)) &&
      identical(vapply(d4$floors, function(f) ch(f$source_engine$engine), "", USE.NAMES = FALSE), ch(d4$selection$clean_room_queue)) &&
      all(vapply(d4$floors, function(f) identical(f$status, "pending_clean_room_engine") && is.null(f$spec$base_signal$path), logical(1))),
    "D5 청정 0 → blocked · floors = 청정실 대기열(엔진 경로 없음 · pending)")
chk(isTRUE(unlist(d4$selection$by_scope$prompt$n_eligible) == 3L), "D6 범위 민감도 — prompt 범위에서는 3종 자격(자동 기억은 full 통로)")
BASE <- lapply(1:3, function(i) mk_engine(sprintf("RP_AUTO_T0%d", i), sprintf("9901.0000%d", i), list()))
write_ledger(BASE)
# D7 fail-closed(적대 검증 2026-09-26 추가) — 판독 불가(NA) 통로 하나뿐인 후보(구조 통과 · 나머지 통로 노출 0 확인)는 어느 범위에서도
#   자격이 없어야 한다. .rfc_scope_ok 가 isFALSE 로 NA 를 노출로 센다 — 이 판정을 '!isTRUE'(NA → 비노출)로 바꾼 돌연변이는 X5 가 못 잡는다
#   (X5 는 통로 값만 본다 · 선정 귀결은 이 검사가 잰다).
e7 <- mk_engine("RP_AUTO_T45", "9901.00045", list(prompt = c(PROMPT_OK[1:5], "## ★재구현 — 새 형식 절", "- cagr=0.5", PROMPT_OK[6:7])))
write_ledger(c(BASE, list(e7))); d7 <- rfc_build(FX, CFGP(), ROOT, EN)
c7 <- Filter(function(z) grepl("/RP_AUTO_T45/", z$engine, fixed = TRUE), d7$candidates)
c7 <- if (length(c7)) c7[[1]] else NULL
el7 <- unlist(lapply(d7$selection$by_scope, function(s) ch(s$eligible_in_order)))
chk(!is.null(c7) && isTRUE(c7$structural_ok) && is.na(c7$exposure$prompt_feedback_measured$exposed) &&
      all(vapply(setdiff(names(c7$exposure), "prompt_feedback_measured"), function(k) isFALSE(c7$exposure[[k]]$exposed), logical(1))) &&
      !any(grepl("/RP_AUTO_T45/", el7, fixed = TRUE)) && !isTRUE(c7$eligible$prompt) && !isTRUE(c7$eligible$full),
    "D7 fail-closed — 판독 불가(NA) 통로 하나뿐인 후보(구조 통과 · 나머지 통로 노출 0)는 어느 범위에서도 자격 없음",
    if (is.null(c7)) "후보 없음" else paste(names(Filter(function(z) !isFALSE(z$exposed), c7$exposure)), collapse = ","))
write_ledger(BASE)

# ═══ P 성과 비노출 ═══
cat("\n[P] 성과 비노출\n")
strip <- function(d) { d$generated_at <- NULL; d$pins$ledger_l1 <- NULL; d }
perturb <- function(E) lapply(seq_along(E), function(i) { e <- E[[i]]; e$base_grade <- c("A", "F", "B")[i]; e$status <- c("active", "parked", "skipped_base_quality")[i]
  e$parked_reason <- "x"; e$attempts <- list(list(n = 9L, grade = c("A", "C", "F")[i], essence = list(port_t = c(9, -3, 0.1)[i], calmar = c(2, 0.1, 0.5)[i]))); e })
write_ledger(BASE); dA <- rfc_build(FX, CFGP(), ROOT, EN)
write_ledger(perturb(BASE))
for (i in 1:3) w_json(list(essence_grade = c("A", "F", "B")[i], essence = list(port_t = c(9, -3, 0.1)[i])), file.path(FX, sprintf("stage_artifacts/replication/run_RP_AUTO_T0%d/authoritative_remeasure.json", i)))
dB <- rfc_build(FX, CFGP(), ROOT, EN)
dd <- EN$rfv_diff(strip(dA), strip(dB))
chk(!length(dd), "P1 원장 성과 필드 교란 + 성과 산출물 투입 → 문서 불변(핀 제외)", paste(head(dd, 3), collapse = ","))
# 돌연변이: 투영을 끄고 등급을 순서 키에 섞은 사본
src <- readLines(LIB, warn = FALSE, encoding = "UTF-8")
m1 <- sub("E <- lapply(.rfc_or(L$entries, list()), function(e) e[intersect(names(e), keep)])", "E <- .rfc_or(L$entries, list())", src, fixed = TRUE)
m2 <- sub("paper_key = paste(sort(pks[nzchar(pks)]), collapse = \"+\"),",
          "paper_key = paste(c(vapply(R, function(e) as.character(e$base_grade %||% \"\"), \"\"), sort(pks[nzchar(pks)])), collapse = \"+\"),", m1, fixed = TRUE)
if (identical(m2, src) || identical(m1, src)) ng("P2 돌연변이 적용 실패(소스 좌표 이동)") else {
  MU <- file.path(TMP, "rf_clean_base_mutant.R"); writeLines(m2, MU, useBytes = TRUE)
  ME <- new.env(parent = globalenv()); invisible(capture.output(sys.source(MU, envir = ME)))
  write_ledger(BASE); mA <- ME$rfc_build(FX, CFGP(), ROOT, EN)
  write_ledger(perturb(BASE)); mB <- ME$rfc_build(FX, CFGP(), ROOT, EN)
  chk(length(EN$rfv_diff(strip(mA), strip(mB))) > 0L, "P2 ★돌연변이(투영 해제 + 등급을 순서 키에) → 같은 교란에서 선택이 바뀐다(검사가 red 를 잰다)")
}
for (i in 1:3) unlink(file.path(FX, sprintf("stage_artifacts/replication/run_RP_AUTO_T0%d/authoritative_remeasure.json", i)))
write_ledger(BASE)

# ═══ V 투영 ═══
cat("\n[V] 투영\n")
write_ledger(perturb(BASE)); V <- rfc_ledger_view(FX, CFG)
chk(all(unlist(lapply(V$entries, names)) %in% unlist(CFG$performance_blind$ledger_fields_allowed)) &&
      !any(c("base_grade", "attempts", "status", "parked_reason") %in% unlist(lapply(V$entries, names))), "V1 투영 필드 ⊆ 허용 목록(성과 필드 부재)")
write_ledger(BASE)

# ═══ L as-of 팩터 층 배선 ═══
cat("\n[L] as-of 팩터 층 배선\n")
mk_stub(); LY <- rfc_factor_layer(FX, CFG, EN, GRID)
c1 <- STUB$calls[[1]]
chk(identical(LY$depth, 3L) && identical(as.integer(c1$depths), 3L) && identical(as.integer(c1$seed_offset), as.integer(CFG$factor_layer$seed_offset)) && is.null(c1$asof),
    "L1 깊이 = 격자 B1 depths 최대 · 시드 = 설정 · as-of = 설정(null → 격자 start_date)")
chk(isTRUE(LY$vs_F1$f1_subset_of_FA) && identical(ch(LY$vs_F1$only_FA), "FA_3"), "L2 F1 ⊆ F_A 판정(접두 사슬)")
cfgm <- CFG; cfgm$factor_layer$depth_rule <- list(kind = "match_floor", floor_id = "F1")
mk_stub(); LM <- rfc_factor_layer(FX, cfgm, EN, GRID); chk(identical(LM$depth, 2L), "L3 match_floor → floor 문서 F1 깊이(2)")
cfgl <- CFG; cfgl$factor_layer$depth_rule <- list(kind = "literal", depth = 1L, source = "test")
mk_stub(); LL <- rfc_factor_layer(FX, cfgl, EN, GRID); chk(identical(LL$depth, 1L), "L4 literal 깊이")
cfga <- CFG; cfga$factor_layer$asof <- "2004-12-31"
mk_stub(); invisible(rfc_factor_layer(FX, cfga, EN, GRID)); chk(identical(STUB$calls[[1]]$asof, "2004-12-31"), "L5 as-of 설정값이 정본 선정기로 전달")
Gb <- GRID; Gb$blocks <- list(list(id = "B2")); chk(inherits(tryCatch(rfc_factor_layer(FX, CFG, EN, Gb), error = function(e) e), "error"), "L6 격자 B1 depths 부재 → stop")
EN$.fe <- mk_stub()

# ═══ W 쓰기 · 핀 대조 ═══
cat("\n[W] 쓰기 · 핀 대조\n")
OUT <- file.path(TMP, "rfc_out", "reference_floor_FA.json"); unlink(dirname(OUT), recursive = TRUE)
chk(identical(rfc_write(dA, OUT, EN), "written"), "W1 첫 쓰기 = written")
chk(identical(rfc_write(rfc_build(FX, CFGP(), ROOT, EN), OUT, EN), "already"), "W2 같은 입력 재생성 = already")
m0 <- unname(tools::md5sum(OUT)); dX <- dA; dX$selection$picks <- list("x")
chk(inherits(tryCatch(rfc_write(dX, OUT, EN), error = function(e) e), "error") && identical(unname(tools::md5sum(OUT)), m0), "W3 내용이 다르면 거부 · 파일 불변")
vv <- rfc_verify(OUT, FX, CFGP(), ROOT, EN)
chk(identical(vv$n_drift, 0L), "W4 verify 드리프트 0", paste(head(vv$drift, 3), collapse = ","))
B2 <- BASE; B2[[1]]$engine_path <- sub("RP_AUTO_T01", "RP_AUTO_T02", B2[[1]]$engine_path); write_ledger(B2)
vv2 <- rfc_verify(OUT, FX, CFGP(), ROOT, EN)
chk(vv2$n_drift > 0L && length(vv2$pins_drift) > 0L, "W5 원장 엔진 경로 변경 → 드리프트(핀·선택)")
write_ledger(BASE)

# ═══ H 숨은 로더 흐름 (FA-CLEAN-BASE-PATH · 2001.04185 위양성 수리) ═══
cat("\n[H] 숨은 로더 흐름(진단 전용 면제 · 산출 합류는 탈락)\n")
DIAG <- c(".diag <- function() {",
          "  if (!exists(\"load_investor\", mode = \"function\")) return(invisible(NULL))",
          "  inv <- load_investor(\"wide\")",
          "  inv <- data.table::as.data.table(inv)",
          "  inv[, Ticker := as.character(Ticker)]",
          "  out <- list(); out[[1]] <- nrow(inv)",
          "  cat(sprintf(\"diag %d\\n\", nrow(inv)))",
          "  invisible(NULL)",
          "}")
DIAG_CALL <- ".diag_res <- tryCatch(.diag(), error = function(e) cat(\"diag fail\\n\"))"
hs <- function(id, pk, eng) { e <- mk_engine(id, pk, list(engine = eng)); write_ledger(c(BASE, list(e))); S_of(id) }
ss <- function(s) s$predicates$source_scope
s <- hs("RP_AUTO_T60", "9901.00060", c(ENG_CLEAN, DIAG, DIAG_CALL))
chk(isTRUE(ss(s)$ok) && !length(ch(ss(s)$hidden_loaders)) && any(grepl("^load_investor@\\.diag\\(L", ch(ss(s)$hidden_flow$diagnostic_only))) &&
      identical(ch(ss(s)$hidden_flow$text_match_legacy), "load_investor"),
    "H1 양성 대조 — 2001.04185 형 진단 전용(.diag + tryCatch · 값 미사용) → 원천 아님 · 구판 문형 판정은 기록만",
    paste(ch(ss(s)$hidden_loaders), ch(ss(s)$hidden_flow$diagnostic_only), ss(s)$hidden_flow$status))
hmut <- list(
  H2 = list(c(ENG_CLEAN, DIAG, DIAG_CALL, "FACTORS[, Score := Score + nrow(.diag())]"), "산출에 := 로 합류"),
  H3 = list(c(ENG_CLEAN, sub("  out <- list(); out[[1]] <- nrow(inv)", "  .G <<- inv", DIAG, fixed = TRUE), DIAG_CALL), "진단 함수 안 전역 대입(<<-)"),
  H4 = list(c(ENG_CLEAN, DIAG, "invisible(do.call(\".diag\", list()))"), "문자열 참조(do.call)"),
  H5 = list(c(ENG_CLEAN, DIAG, "G <- function() .diag()", "g_res <- G()"), "다른 함수 경유 호출"),
  H6 = list(c(ENG_CLEAN, DIAG, ".r <- .diag()", "FACTORS <- FACTORS[Score > length(.r)]"), "진단 값이 산출로 흐름"),
  H7 = list(c(ENG_CLEAN, sub("  out <- list(); out[[1]] <- nrow(inv)", "  FACTORS[, Score := 0]", DIAG, fixed = TRUE), DIAG_CALL), "진단 함수가 전역 표(:=) 변경"),
  H8 = list(c(ENG_CLEAN, sub("  out <- list(); out[[1]] <- nrow(inv)", "  data.table::fwrite(inv, \"x.csv\")", DIAG, fixed = TRUE), DIAG_CALL), "진단 함수가 파일 쓰기"),
  H9 = list(c(ENG_CLEAN, sub("  out <- list(); out[[1]] <- nrow(inv)", "  set.seed(1)", DIAG, fixed = TRUE), DIAG_CALL), "진단 함수가 난수 상태 변경"))
k <- 61L
for (nm in names(hmut)) {
  s <- hs(sprintf("RP_AUTO_T%d", k), sprintf("9901.000%d", k), hmut[[nm]][[1]]); k <- k + 1L
  chk(!isTRUE(ss(s)$ok) && "load_investor" %in% ch(ss(s)$hidden_loaders) && !length(ch(ss(s)$hidden_flow$diagnostic_only)),
      sprintf("%s 위반 주입 — %s → 원천으로 센다(source_scope 실패)", nm, hmut[[nm]][[2]]),
      paste(ch(ss(s)$hidden_loaders), jsonlite::toJSON(ss(s)$hidden_flow$detail, auto_unbox = TRUE)))
}
s <- hs("RP_AUTO_T70", "9901.00070", c(ENG_CLEAN, "# 참고: load_investor('wide') 는 쓰지 않는다"))
chk(isTRUE(ss(s)$ok) && !length(ch(ss(s)$hidden_loaders)) && identical(ch(ss(s)$hidden_flow$text_match_legacy), "load_investor"),
    "H10 음성 대조 — 주석 속 로더 문형은 호출이 아니다(구판은 세었다 · 기록만)")
s <- hs("RP_AUTO_T71", "9901.00071", c(ENG_CLEAN, "x <- function( {"))
chk(is.na(ss(s)$ok) && identical(ss(s)$hidden_flow$status, "parse_error"), "H11 파싱 실패 → 판독 불가(NA · fail-closed)")
write_ledger(BASE)

# ═══ C 청정 레인 출처 기록 대조 (FA-CLEAN-BASE-PATH) ═══
cat("\n[C] 청정 레인 출처 기록 — 자기 신고를 전사·파일로 대조\n")
sha_f <- function(p) digest::digest(p, algo = "sha256", file = TRUE)
rdtxt <- function(p) { x <- rawToChar(readBin(p, "raw", n = file.size(p))); Encoding(x) <- "UTF-8"; x }
jl <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null"))
PASS_OUT <- CFG$exposure$transcript$guard_attestation$pass_stdout
GUARD_CMD <- "DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}; bash \"$DIR/02_Infrastructure/hooks/arm_gen_read_guard.sh\""
BLK_CLEAN <- "PreToolUse:Read hook error: ARM_GEN_READ_BLOCKED[clean_lane · R6_target]: reinforce_ledger — 청정 충실구현 레인…"
tr_clean <- function(P, ts, reads = list(list(id = "t1", path = "C:/X/02_Infrastructure/factor_db/factor_db_connector.R", out = PASS_OUT, res = "ok")),
                     extra = character(0), instr = list(list(path = "C:/X/CLAUDE.md", type = "Project", content = "SR 2.5+ 목표 · Calmar 0.64"),
                                                        list(path = "C:/X/.claude/rules/pit.md", type = "Project", content = "Calmar 2.50→1.83·SR 2.10→1.84"))) {
  L <- c(jl(list(type = "queue-operation", operation = "enqueue", timestamp = ts, sessionId = "s", content = P)),
         jl(list(type = "attachment", attachment = list(type = "instructions", files = instr))))
  for (r in reads) {
    L <- c(L, jl(list(type = "assistant", message = list(role = "assistant", content = list(list(type = "tool_use", id = r$id, name = r$tool %||% "Read",
                                                                                                  input = if (identical(r$tool, "WebFetch")) list(url = r$path) else list(file_path = r$path)))))))
    if (!is.null(r$out)) L <- c(L, jl(list(type = "attachment", attachment = list(type = "hook_success", hookName = "PreToolUse:Read", toolUseID = r$id,
                                                                                  hookEvent = "PreToolUse", stdout = paste0(r$out, "\n"), command = GUARD_CMD))))
    L <- c(L, jl(list(type = "user", message = list(role = "user", content = list(list(type = "tool_result", tool_use_id = r$id,
                                                                                       is_error = !identical(r$res, "ok"), content = if (identical(r$res, "ok")) "1\tcontent" else r$res))))))
  }
  c(L, extra)
}
mk_clean <- function(id, pk, reads = NULL, extra = character(0), instr = NULL, prov = list(), ts = "2026-09-10T00:05:00.000Z", prompt = NULL, n_tr = 1L) {
  P0 <- prompt %||% c(PROMPT_OK, sprintf("산출 `C:/X/04_Research/strategies/%s/engine.R`", id))
  e <- mk_engine(id, pk, list(no_transcript = TRUE, prompt = P0))
  wd <- file.path(FX, "04_Research/strategies", id); P <- rdtxt(file.path(wd, "prompt.txt"))
  pv <- list(schema = "lane_provenance_v1", mode = "clean", mode_source = "config_default", engine_rel = sprintf("04_Research/strategies/%s/engine.R", id),
             pre = list(prompt = list(file = "prompt.txt", sha256 = sha_f(file.path(wd, "prompt.txt"))), guard = list(applied = TRUE),
                        feedback = list(audit_source_mode = prov$audit_source_mode, audit_source_dir = prov$audit_source_dir)),
             post = list(engine_sha256 = sha_f(file.path(wd, "engine.R"))))
  for (k in names(prov$override)) pv[[k]] <- prov$override[[k]]
  w_json(pv, file.path(wd, "lane_provenance.json"))
  args <- list(P = P, ts = ts, extra = extra); if (!is.null(reads)) args$reads <- reads; if (!is.null(instr)) args$instr <- instr
  for (i in seq_len(n_tr)) w_txt(do.call(tr_clean, args), file.path(TD, sprintf("%s_%d.jsonl", id, i)))
  list(e = e, wd = wd, P = P)
}
cx <- function(z) { write_ledger(c(BASE, list(z$e))); X_of(basename(z$wd)) }
elig_full <- function(z) { write_ledger(c(BASE, list(z$e))); d <- rfc_build(FX, CFGP(), ROOT, EN)
  c9 <- Filter(function(q) grepl(paste0("/", basename(z$wd), "/"), q$engine, fixed = TRUE), d$candidates)
  if (!length(c9)) NA else isTRUE(c9[[1]]$eligible$full) }
RD_LEDGER <- list(id = "t2", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = NULL, res = BLK_CLEAN)
z <- mk_clean("RP_AUTO_CLEAN_T80", "9901.00080", reads = list(list(id = "t1", path = "C:/X/02_Infrastructure/factor_db/factor_db_connector.R", out = PASS_OUT, res = "ok"), RD_LEDGER))
x <- cx(z)
chk(all(vapply(x, function(q) isFALSE(q$exposed), logical(1))) && identical(x$transcript_missing$selection, "clean_provenance") &&
      identical(as.integer(x$transcript_tool_reads$n_perf_path_blocked), 1L) && identical(as.integer(x$transcript_tool_reads$guard_attestation$n_unattested), 0L),
    "C1 양성 대조 — 청정 실행(sha 일치 · 통과 증명 + clean_lane 차단 · 막힌 원장 시도 1) → 전 통로 노출 0",
    paste(names(Filter(function(q) !isFALSE(q$exposed), x)), collapse = ","))
chk(isTRUE(elig_full(z)), "C2 청정 실행 엔진이 full 범위 자격을 얻는다(선정 귀결)")
kb <- x$transcript_auto_memory$known_boundary_instruction_files
chk(length(kb) == 2L && all(vapply(kb, function(q) q$metric_hits > 0L, logical(1))) && isFALSE(x$transcript_auto_memory$exposed),
    "C3 알려진 경계 — 프로젝트 규칙 파일(CLAUDE.md·pit.md 수치)은 노출이 아니고 경로·sha256·수치 개수로 기록된다")
z <- mk_clean("RP_AUTO_CLEAN_T81", "9901.00081", reads = list(list(id = "t1", path = "C:/X/02_Infrastructure/x.R", out = "{}", res = "ok")))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && x$transcript_tool_reads$guard_attestation$n_unattested == 1L,
                "C4 위반 주입 — 가드 통과 출력이 '{}'(청정 모드 아님) → 증명 없음 = 노출(자기 신고 불인정)")
z <- mk_clean("RP_AUTO_CLEAN_T82", "9901.00082", reads = list(list(id = "t2", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = NULL,
                                                                   res = "PreToolUse:Read hook error: ARM_GEN_READ_BLOCKED[design_lane · R1_path]: x")))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_perf_path_blocked), 1L),
                "C5 위반 주입 — 설계 레인 표식 차단(clean_lane 아님) → 막혔어도 청정 증명 없음 = 노출")
z <- mk_clean("RP_AUTO_CLEAN_T83", "9901.00083", reads = list(list(id = "t2", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = PASS_OUT,
                                                                   res = "File does not exist.")))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_perf_path_reads), 1L),
                "C6 위반 주입 — 성과 경로 시도의 오류가 가드 차단 문형이 아니다 → 열람으로 센다(fail-closed)")
z <- mk_clean("RP_AUTO_CLEAN_T84", "9901.00084"); cat("# 청정 실행 뒤 손댄 줄\n", file = file.path(z$wd, "engine.R"), append = TRUE)
setmt(file.path(z$wd, "engine.R"), "2026-09-10T00:30:00")
x <- cx(z); chk(is.na(x$transcript_tool_reads$exposed) && isFALSE(x$transcript_missing$checks$engine_sha_match) && isFALSE(elig_full(z)),
                "C7 위반 주입 — 청정 실행 뒤 엔진 변경(sha 불일치) → 판독 불가 · 자격 없음")
z <- mk_clean("RP_AUTO_CLEAN_T85", "9901.00085"); cat("추가 줄\n", file = file.path(z$wd, "prompt.txt"), append = TRUE)
setmt(file.path(z$wd, "prompt.txt"), "2026-09-10T00:00:00")
x <- cx(z); chk(is.na(x$transcript_missing$exposed) && isFALSE(x$transcript_missing$checks$prompt_sha_match), "C8 위반 주입 — prompt.txt 변경(기록 sha 불일치) → 판독 불가")
z <- mk_clean("RP_AUTO_CLEAN_T86", "9901.00086"); unlink(Sys.glob(file.path(TD, "RP_AUTO_CLEAN_T86_*.jsonl")))
w_txt(tr_clean(paste0(z$P, "x"), "2026-09-10T00:05:00.000Z"), file.path(TD, "RP_AUTO_CLEAN_T86_x.jsonl"))
x <- cx(z); chk(isTRUE(x$transcript_missing$exposed) && is.na(x$transcript_tool_reads$exposed), "C9 전사 첫 레코드 sha 불일치(다른 프롬프트) → 전사 없음 = 노출")
z <- mk_clean("RP_AUTO_CLEAN_T87", "9901.00087", ts = "2026-09-09T23:50:00.000Z")
x <- cx(z); chk(isTRUE(x$transcript_missing$exposed), "C10 전사 시작이 prompt.txt 보다 허용 오차(120초) 넘게 앞선다 → 이 실행이 아니다 = 노출")
z <- mk_clean("RP_AUTO_CLEAN_T88", "9901.00088", extra = jl(list(type = "attachment", attachment = list(type = "hook_additional_context", hookName = "PreToolUse:Agent",
                     toolUseID = "a1", hookEvent = "PreToolUse", content = list("[현재 최고 연구-tier 전략] STR_x PORT_t 2.58 SR 0.87")))))
x <- cx(z); chk(isTRUE(x$transcript_auto_memory$exposed) && x$transcript_auto_memory$hook_context_metric_hits >= 2L, "C11 훅 주입 문맥의 성과 수치 → 자동 주입 노출")
z <- mk_clean("RP_AUTO_CLEAN_T89", "9901.00089", reads = list(list(id = "w1", tool = "WebFetch", path = "https://raw.githubusercontent.com/Irysis/Qvest_system/main/06_Registry/x.json", out = NULL, res = "ok")))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && length(ch(x$transcript_tool_reads$web_forbidden)) == 1L, "C12 저장소 웹 사본 열람(WebFetch) → 노출")
z <- mk_clean("RP_AUTO_CLEAN_T90", "9901.00090", extra = jl(list(type = "attachment", attachment = list(type = "nested_memory", path = "C:/Users/x/.claude/CLAUDE.md",
                     content = "{'path': 'C:/Users/x/.claude/CLAUDE.md', 'type': 'User', 'content': 'PORT_t 3.589 · Calmar 0.609'}"))))
x <- cx(z); chk(isTRUE(x$transcript_auto_memory$exposed), "C13 프로젝트 밖 종류(User) 규칙 주입의 수치 → 노출(알려진 경계는 프로젝트 파일만)")
z <- mk_clean("RP_AUTO_CLEAN_T91", "9901.00091", n_tr = 2L)
w_txt(tr_clean(z$P, "2026-09-10T00:06:00.000Z", reads = list(list(id = "t9", path = "C:/X/stage_artifacts/replication/r1/06_metrics.csv", out = PASS_OUT, res = "ok"))),
      file.path(TD, "RP_AUTO_CLEAN_T91_2.jsonl"))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && length(ch(x$transcript_missing$transcripts)) == 2L,
                "C14 1차·폴백 두 실행을 모두 본다 — 한쪽의 막히지 않은 성과 열람 → 노출")
z <- mk_clean("RP_AUTO_CLEAN_T92", "9901.00092"); writeLines("{not json", file.path(z$wd, "lane_provenance.json"))
x <- cx(z); chk(is.na(x$transcript_missing$exposed) && isFALSE(elig_full(z)), "C15 출처 기록 판독 불가 → 청정 주장 여부 불명 = 판독 불가(fail-closed)")
AUD_P <- c(PROMPT_OK[1:5], "## ★재구현이다 — 앞 구현이 적대적 충실도 감사에서 기각됐다", "- 미신고 변경: [부호] 논문 식 (3) 은 룩백 12개월 — 구현은 부호 반대", PROMPT_OK[6:7])
mk_src <- function(wd, art = FALSE) { d <- file.path(wd, ".clean_audit_src/r1"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  w_txt(c("너는 **적대적 검증자**다.", if (art) "- 측정 산출물: C:/X/stage_artifacts/replication/r1" else "- 측정 산출물: (청정 모드 — 비공개. 논문과 코드만 대조하라)"),
        file.path(d, ".audit_prompt_signal.txt")) }
z <- mk_clean("RP_AUTO_CLEAN_T93", "9901.00093", prompt = AUD_P, prov = list(audit_source_mode = "clean", audit_source_dir = ".clean_audit_src/r1")); mk_src(z$wd)
setmt(file.path(z$wd, "prompt.txt"), "2026-09-10T00:00:00")
x <- cx(z); chk(isFALSE(x$prompt_feedback_measured$exposed) && isTRUE(x$prompt_feedback_measured$audit_source$ok),
                "C16 청정 재구현 — 감사 지적 출처 = 보존 사본(비공개 줄 · 경로 없음) → 비노출")
z <- mk_clean("RP_AUTO_CLEAN_T94", "9901.00094", prompt = AUD_P, prov = list(audit_source_mode = "clean", audit_source_dir = ".clean_audit_src/r1")); mk_src(z$wd, art = TRUE)
x <- cx(z); chk(is.na(x$prompt_feedback_measured$exposed), "C17 위반 주입 — 보존 사본에 산출물 경로(측정을 본 감사) → 판독 불가")
z <- mk_clean("RP_AUTO_CLEAN_T95", "9901.00095", prompt = AUD_P, prov = list(audit_source_mode = "normal", audit_source_dir = ".clean_audit_src/r1")); mk_src(z$wd)
x <- cx(z); chk(is.na(x$prompt_feedback_measured$exposed), "C18 위반 주입 — 감사 출처 모드 normal → 판독 불가")
e96 <- mk_engine("RP_AUTO_T96", "9901.00096", list(reads = c("C:/X/02_Infrastructure/alpha_search/run_paper_replication.R")))
w_txt(c(tr_lines("RP_AUTO_T96", "2026-09-10T00:05:00.000Z", reads = character(0)),
        jl(list(type = "assistant", message = list(role = "assistant", content = list(list(type = "tool_use", id = "q2", name = "Read", input = list(file_path = "C:/X/06_Registry/reinforce_ledger_l1.json")))))),
        jl(list(type = "user", message = list(role = "user", content = list(list(type = "tool_result", tool_use_id = "q2", is_error = TRUE,
                                                                                 content = "PreToolUse:Read hook error: ARM_GEN_READ_BLOCKED[design_lane · R1_path]: x")))))),
      file.path(TD, "RP_AUTO_T96.jsonl"))
write_ledger(c(BASE, list(e96))); x <- X_of("RP_AUTO_T96")
chk(isFALSE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_tool_reads$n_perf_path_blocked), 1L) && isFALSE(x$transcript_tool_reads$guard_attestation$required),
    "C19 레인 밖 실행(출처 기록 없음) — 가드가 막은 성과 경로 시도는 열람이 아니다 · 증명 요구 없음(구판 판정 규칙 유지)")
# (10-03) 새 엔진 경로 — 청정 기록·전사·sha 가 전부 맞아도 엔진 디렉터리가 청정 접두가 아니거나 기록이 다른 엔진을 가리키면 청정 불인정
z <- mk_clean("RP_AUTO_T79", "9901.00079")
x <- cx(z); chk(is.na(x$transcript_missing$exposed) && isFALSE(x$transcript_missing$checks$engine_path_new) &&
                  isTRUE(x$transcript_missing$checks$prompt_sha_match) && isTRUE(x$transcript_missing$checks$engine_sha_match) && isFALSE(elig_full(z)),
                "C21 위반 주입 — 옛 작업 디렉터리 이름(청정 접두 아님)에 얹은 청정 기록(나머지 대조 전부 일치) → 판독 불가 · 자격 없음")
z <- mk_clean("RP_AUTO_CLEAN_T78", "9901.00078", prov = list(override = list(engine_rel = "04_Research/strategies/RP_AUTO_CLEAN_T77/engine.R")))
x <- cx(z); chk(is.na(x$transcript_missing$exposed) && isFALSE(x$transcript_missing$checks$engine_path_new) && isFALSE(elig_full(z)),
                "C22 위반 주입 — 기록의 engine_rel 이 다른 엔진(청정 접두는 맞음) → 판독 불가 · 자격 없음")
z <- mk_clean("RP_AUTO_CLEAN_T76", "9901.00076", prov = list(override = list(engine_rel = NULL)))
x <- cx(z); chk(is.na(x$transcript_missing$exposed) && isFALSE(x$transcript_missing$checks$engine_path_new),
                "C23 위반 주입 — 기록에 engine_rel 없음(구판 기록) → 판독 불가(fail-closed)")
# 돌연변이 — 증명 요구·엔진 sha 대조를 끈 사본은 C4·C7 을 통과시킨다(검사가 red 를 잰다)
src2 <- readLines(LIB, warn = FALSE, encoding = "UTF-8")
m1 <- sub("(clean && length(A$unatt) > 0L)", "FALSE", src2, fixed = TRUE)
m2 <- sub("engine_sha_match = !is.na(esha) && identical(esha, LP$engine_sha_post),", "engine_sha_match = TRUE,", src2, fixed = TRUE)
if (identical(m1, src2) || identical(m2, src2)) ng("C20 돌연변이 적용 실패(좌표 이동)") else {
  run_mut <- function(m, id) { MU <- file.path(TMP, paste0("rfc_mut_", id, ".R")); writeLines(m, MU, useBytes = TRUE)
    ME <- new.env(parent = globalenv()); invisible(capture.output(sys.source(MU, envir = ME)))
    cd <- ME$rfc_candidates(ME$rfc_ledger_view(FX, CFG), FX, CFG); k <- grep(paste0("/", id, "/"), names(cd), fixed = TRUE)
    ME$rfc_exposure(cd[[k[1]]], FX, CFG, EN, FCFG, ME$rfc_transcript_index(rfc_load_cfg(CFGP()))) }
  z4 <- mk_clean("RP_AUTO_CLEAN_T97", "9901.00097", reads = list(list(id = "t1", path = "C:/X/02_Infrastructure/x.R", out = "{}", res = "ok")))
  write_ledger(c(BASE, list(z4$e))); xm1 <- run_mut(m1, "RP_AUTO_CLEAN_T97")
  z7 <- mk_clean("RP_AUTO_CLEAN_T98", "9901.00098"); cat("# x\n", file = file.path(z7$wd, "engine.R"), append = TRUE); setmt(file.path(z7$wd, "engine.R"), "2026-09-10T00:30:00")
  write_ledger(c(BASE, list(z7$e))); xm2 <- run_mut(m2, "RP_AUTO_CLEAN_T98")
  chk(isFALSE(xm1$transcript_tool_reads$exposed) && isFALSE(xm2$transcript_tool_reads$exposed),
      "C20 ★돌연변이(증명 요구 삭제 · 엔진 sha 대조 삭제) → C4·C7 형 위반이 통과한다(검사가 red 를 잰다)")
  # (10-03) 새 엔진 경로 대조를 끈 사본 → C21 형(옛 디렉터리 이름의 청정 기록)이 청정으로 통과한다
  m3 <- sub("engine_path_new = identical(", "engine_path_new = TRUE || identical(", src2, fixed = TRUE)
  if (identical(m3, src2)) ng("C24 돌연변이 적용 실패(좌표 이동)") else {
    z21 <- mk_clean("RP_AUTO_T75", "9901.00075")
    write_ledger(c(BASE, list(z21$e))); xm3 <- run_mut(m3, "RP_AUTO_T75"); write_ledger(c(BASE, list(z21$e))); x21 <- X_of("RP_AUTO_T75")
    chk(isFALSE(xm3$transcript_missing$exposed) && isFALSE(xm3$transcript_tool_reads$exposed) && is.na(x21$transcript_missing$exposed),
        "C24 ★돌연변이(새 엔진 경로 대조 삭제) → C21 형 위반이 청정으로 통과한다 · 원판은 판독 불가(검사가 red 를 잰다)")
  }
}
# ═══ (10-04 F_A v2 D1) 앞 회차 구현 전사·프롬프트 — 재구현은 같은 작업 디렉터리의 앞 판을 이어 쓴다 · prov-pre 는 회차마다 덮어쓴다 ═══
prior_tr <- function(z, id, ts, reads, body = PROMPT_OK, tag = "prior") {
  Pp <- paste(c(body, sprintf("산출 `C:/X/04_Research/strategies/%s/engine.R`", id), "(앞 회차)"), collapse = "\n")
  w_txt(tr_clean(Pp, ts, reads = reads), file.path(TD, sprintf("%s_%s.jsonl", id, tag)))
}
RD_ALLOWED <- list(list(id = "p0", path = "C:/X/02_Infrastructure/factor_db/factor_db_connector.R", out = PASS_OUT, res = "ok"))
z <- mk_clean("RP_AUTO_CLEAN_T73", "9901.00073")
prior_tr(z, "RP_AUTO_CLEAN_T73", "2026-09-09T22:00:00.000Z", list(list(id = "p1", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = NULL, res = "ok")))
x <- cx(z); chk(isTRUE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_missing$n_prior_runs), 1L) && isFALSE(elig_full(z)),
                "C25 위반 주입(D1) — 앞 회차 전사의 미증명 원장 열람(이번 회차는 청정) → 노출 · 자격 없음",
                sprintf("exposed=%s prior=%s", format(x$transcript_tool_reads$exposed), format(x$transcript_missing$n_prior_runs)))
z <- mk_clean("RP_AUTO_CLEAN_T72", "9901.00072")
prior_tr(z, "RP_AUTO_CLEAN_T72", "2026-09-09T22:00:00.000Z", RD_ALLOWED)
x <- cx(z); chk(all(vapply(x, function(q) isFALSE(q$exposed), logical(1))) && identical(as.integer(x$transcript_missing$n_prior_runs), 1L) && isTRUE(elig_full(z)),
                "C26 양성 대조(D1) — 앞 회차도 청정(가드 증명 · 허용 열람) → 전 통로 노출 0 · full 자격",
                paste(names(Filter(function(q) !isFALSE(q$exposed), x)), collapse = ","))
z <- mk_clean("RP_AUTO_CLEAN_T71", "9901.00071")
prior_tr(z, "RP_AUTO_CLEAN_T71", "2026-09-09T22:00:00.000Z", RD_ALLOWED, body = fb_m)
x <- cx(z); chk(isTRUE(x$prompt_feedback_measured$exposed) && identical(as.integer(x$prompt_feedback_measured$prior_prompts$n_hit), 1L),
                "C27 위반 주입(D1) — 앞 회차 프롬프트 재구현 절에 측정 덤프 → 노출")
z <- mk_clean("RP_AUTO_CLEAN_T70", "9901.00070")
prior_tr(z, "RP_AUTO_CLEAN_T70", "2026-09-10T02:00:00.000Z", list(list(id = "p1", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = NULL, res = "ok")))
x <- cx(z); chk(isFALSE(x$transcript_tool_reads$exposed) && identical(as.integer(x$transcript_missing$n_prior_runs), 0L),
                "C28 음성 대조(D1) — 엔진 mtime 뒤 전사(다음 회차 등)는 이 엔진의 앞 회차가 아니다 → 무시")
# 실행 도구(D2) — 무엇을 읽었는지 전사가 말하지 않는다: 청정·구판 무관 판독 불가
PS_LINE <- jl(list(type = "assistant", message = list(role = "assistant", content = list(list(type = "tool_use", id = "b1", name = "PowerShell",
                                                                                                  input = list(command = "Get-Content C:/X/06_Registry/x.json"))))))
z <- mk_clean("RP_AUTO_CLEAN_T69", "9901.00069", extra = PS_LINE)
x <- cx(z); chk(is.na(x$transcript_tool_reads$exposed) && length(ch(x$transcript_tool_reads$exec_tools)) == 1L && isFALSE(elig_full(z)),
                "C29 위반 주입(D2) — 청정 주장 실행에 실행 도구(PowerShell) → 판독 불가 · 자격 없음")
e68 <- mk_engine("RP_AUTO_T68", "9901.00068", list())
w_txt(c(tr_lines("RP_AUTO_T68", "2026-09-10T00:05:00.000Z"), PS_LINE), file.path(TD, "RP_AUTO_T68.jsonl"))
write_ledger(c(BASE, list(e68))); x <- X_of("RP_AUTO_T68")
chk(is.na(x$transcript_tool_reads$exposed), "C30 위반 주입(D2) — 구판 실행의 실행 도구 → 판독 불가")
# 돌연변이(D1·D2) — 앞 회차 판독 삭제 · 범위 밖 판정 삭제 사본은 C25·X12 형 위반을 통과시킨다(검사가 red 를 잰다)
src3 <- readLines(LIB, warn = FALSE, encoding = "UTF-8")
m4 <- sub("prs <- lapply(c(cur, prior), probe_row)", "prs <- lapply(cur, probe_row)", src3, fixed = TRUE)
m5 <- sub("(!clean && length(A$scope_out) > 0L)", "FALSE", src3, fixed = TRUE)
if (identical(m4, src3) || identical(m5, src3)) ng("C31 돌연변이 적용 실패(좌표 이동)") else {
  run_mut2 <- function(m, id) { MU <- file.path(TMP, paste0("rfc_mut2_", id, ".R")); writeLines(m, MU, useBytes = TRUE)
    ME <- new.env(parent = globalenv()); invisible(capture.output(sys.source(MU, envir = ME)))
    cg <- ME$rfc_load_cfg(CFGP()); cd <- ME$rfc_candidates(ME$rfc_ledger_view(FX, cg), FX, cg); k <- grep(paste0("/", id, "/"), names(cd), fixed = TRUE)
    ME$rfc_exposure(cd[[k[1]]], FX, cg, EN, FCFG, ME$rfc_transcript_index(cg)) }
  z25 <- mk_clean("RP_AUTO_CLEAN_T67", "9901.00067")
  prior_tr(z25, "RP_AUTO_CLEAN_T67", "2026-09-09T22:00:00.000Z", list(list(id = "p1", path = "C:/X/06_Registry/reinforce_ledger_l1.json", out = NULL, res = "ok")))
  write_ledger(c(BASE, list(z25$e))); xm4 <- run_mut2(m4, "RP_AUTO_CLEAN_T67")
  e66 <- mk_engine("RP_AUTO_T66", "9901.00066", list(reads = c("C:/X/04_Research/strategies/RP_AUTO_T02/engine.R")))
  write_ledger(c(BASE, list(e66))); xm5 <- run_mut2(m5, "RP_AUTO_T66")
  chk(isFALSE(xm4$transcript_tool_reads$exposed) && isFALSE(xm5$transcript_tool_reads$exposed),
      "C31 ★돌연변이(앞 회차 판독 삭제 · 범위 밖 판정 삭제) → C25·X12 형 위반이 통과한다(검사가 red 를 잰다)",
      sprintf("m4=%s m5=%s", format(xm4$transcript_tool_reads$exposed), format(xm5$transcript_tool_reads$exposed)))
}
# 설정 fail-closed(D2) — 허용 목록 정책 부재 → stop
chk(inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$exposure$transcript$unattested_scope$allow_policy <- "02_Infrastructure/hooks/policies/__none__.json"; c }, "us")),
                      error = function(e) e), "error") &&
      inherits(tryCatch(rfc_load_cfg(badw(function(c) { c$exposure$transcript$unattested_scope <- NULL; c }, "us0")), error = function(e) e), "error"),
    "C32 설정 fail-closed(D2) — 허용 목록 정책 부재 · unattested_scope 부재 → stop")
write_ledger(BASE)

# ═══ R 읽기 전용 ═══
cat("\n[R] 읽기 전용\n")
chk(identical(md5_prod(), PROD0), "R1 루트 지문 불변")
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
