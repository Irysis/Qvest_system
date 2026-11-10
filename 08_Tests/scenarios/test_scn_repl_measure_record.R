#!/usr/bin/env Rscript
#==============================================================================
# test_scn_repl_measure_record.R — 레인 D 시나리오(2026-11-10 v10.2 감사): 충실구현 측정 기록의 판 표식 · 원자적 쓰기 · 낡은 판 판정
#   러너(run_paper_replication.R)를 통째로 source 하지 않는다(데이터 적재 · 텔레그램). 대상 정의만 parse → eval 로 꺼내 격리 환경에서 부른다.
#   S1 판 표식 — 수리 뒤 측정: status ok · measured_at = run_id · 원장 md5 일치 · 수리 3건 · stale_at_measure FALSE · 빌드 도장
#   S2 판 표식 — 수리 앞 측정(낡은 판): stale_at_measure TRUE · hits = 수리 id → 같은 폴더를 계약 fdv_stale 이 낡음으로 판정(A 관문 factor_db_stale 의 입력)
#   S2b~S2e 선언 팩터(G2 수리 11-10) — 셀 엔진 칸 사양 → 기록 → 계약 fdv_stale 이 팩터 목록 수리를 비켜 간다 · 엔진 기저 · 사양 없음 = 낡음(대조)
#   S3 판 표식 — 진행 중 수리(completed_at 없음): in_progress 에 id · 측정 시각과 무관하게 낡음 · valid_from = NA
#   S4 판 표식 — 원장 파손: 측정을 막지 않고 status = "error: …"(판정 경로 불변)
#   S5 원자적 쓰기 — 정상: 파일 생성 · 임시 파일 없음 · 되읽기 일치 / 직렬화 실패: 권위 이름 미생성 · 임시 파일 정리 · 오류 전파
#   S6 배선 — 러너 본문이 판 표식을 auth 에 싣고(끄기 스위치 포함) 권위 기록을 원자적 쓰기로 쓴다 · 돌연변이(배선 제거) 탐지
#   S7 변형 일부 실패(검증기 .v1001_measure_variants · 대역 러너) — 실패 변형은 그 행에만 status=error · 대표 행 · 요약 파일 · 대표 = 권위 유지
# 격리: tempfile() 루트 · 운영 원장 · .cache · 등록부에 쓰지 않는다. 네트워크 · 텔레그램 · 실제 측정 없음.
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
.root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    p <- gsub("\\\\", "/", p)
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/alpha_search/run_paper_replication.R"))) return(p)
  }
  d <- gsub("\\\\", "/", getwd())
  repeat { if (file.exists(file.path(d, "02_Infrastructure/alpha_search/run_paper_replication.R"))) return(d)
           nd <- dirname(d); if (identical(nd, d)) break; d <- nd }
  stop("루트 못 찾음")
}
ROOT <- .root()
P <- 0L; F <- 0L
ok <- function(cond, msg, detail = "") { if (isTRUE(cond)) { P <<- P + 1L; cat("  OK  ", msg, "\n") } else { F <<- F + 1L; cat("  FAIL", msg, detail, "\n") } }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

RUNNER <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
pull_defs <- function(path, names, env) {
  ex <- parse(path, encoding = "UTF-8", keep.source = FALSE)
  got <- character(0)
  for (e in as.list(ex)) if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && as.character(e[[2]]) %in% names) {
    eval(e, env); got <- c(got, as.character(e[[2]])) }
  got
}
E <- new.env(parent = globalenv()); assign("%||%", `%||%`, envir = E)
got <- pull_defs(RUNNER, c(".rp_fdv_stamp", ".rp_write_json_atomic"), E)
ok(setequal(got, c(".rp_fdv_stamp", ".rp_write_json_atomic")), "S0 러너에서 대상 정의 2개 추출", paste(got, collapse = ","))

## 임시 루트 — 수리 원장 사본(운영 원장 구조 그대로 · 시각은 고정 값) + 가짜 팩터 DB 폴더
TMP <- gsub("\\\\", "/", tempfile("scn_repl_rec_")); dir.create(file.path(TMP, "06_Registry"), recursive = TRUE)
dir.create(file.path(TMP, ".cache/factor_db"), recursive = TRUE)
writeLines("abc123 build 2026-11-10", file.path(TMP, ".cache/factor_db/build_hash.txt"))
invisible(file.create(file.path(TMP, ".cache/factor_db", c("factor_db_202610.parquet", "factor_db_202611.parquet"))))
mk_ledger <- function(entries) {
  write_json(list(schema = "factor_db_vintage_v1", entries = entries), file.path(TMP, "06_Registry/factor_db_vintage.json"), auto_unbox = TRUE, null = "null")
}
L3 <- list(list(id = "R1", completed_at = "2026-11-09T23:31:00+09:00", scope = "all"),
           list(id = "R2", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"),
           list(id = "R3", completed_at = "2026-11-10T11:26:00+09:00", scope = list(factors = list("Q16_Debt_to_Assets"))))
mk_ledger(L3)
FDV <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/contracts/factor_db_vintage.R"), envir = FDV)
mk_out <- function(run_id) { d <- file.path(TMP, "stage_artifacts/replication", run_id); dir.create(d, recursive = TRUE, showWarnings = FALSE); d }

cat("=== S1 수리 뒤 측정 ===\n")
d1 <- mk_out("20261110_130000_111"); s1 <- E$.rp_fdv_stamp(d1, "20261110_130000_111", code_root = ROOT, data_root = TMP)
ok(identical(s1$status, "ok"), "S1 status ok", s1$status)
ok(identical(s1$measured_at, "2026-11-10T13:00:00+0900"), "S1 measured_at = run_id 시각", s1$measured_at)
ok(identical(s1$ledger_md5, unname(tools::md5sum(file.path(TMP, "06_Registry/factor_db_vintage.json")))), "S1 원장 md5 = 측정 순간 원장 파일")
ok(length(s1$repairs) == 3L && identical(s1$repairs[[3]]$id, "R3"), "S1 수리 3건 기록")
ok(identical(s1$stale_at_measure, FALSE) && !length(s1$in_progress), "S1 낡지 않음 · 진행 중 수리 없음")
ok(identical(s1$factor_db_build$n_month_files, 2L) && grepl("abc123", s1$factor_db_build$build_hash), "S1 팩터 DB 빌드 도장(build_hash · 월 파일 수)")
ok(is.na(s1$declared_factors[1]) && nzchar(s1$declared_factors_note), "S1 엔진 기저 = 선언 팩터 알 수 없음(보수적 — 범위 수리도 닿음)")

cat("=== S2 수리 앞 측정(낡은 판) ===\n")
d2 <- mk_out("20261106_215452_30584"); s2 <- E$.rp_fdv_stamp(d2, "20261106_215452_30584", code_root = ROOT, data_root = TMP)
ok(isTRUE(s2$stale_at_measure) && setequal(unlist(s2$stale_hits), c("R1", "R2", "R3")), "S2 stale_at_measure TRUE · hits R1~R3", paste(unlist(s2$stale_hits), collapse = ","))
write_json(list(run_id = "20261106_215452_30584", essence_grade = "A", factor_db_vintage = s2), file.path(d2, "authoritative_remeasure.json"), auto_unbox = TRUE, null = "null")
v2 <- FDV$fdv_stale(d2, ledger = FDV$fdv_ledger(TMP))
ok(isTRUE(v2$stale), "S2 같은 폴더를 계약 fdv_stale 이 낡음으로 판정 — A 관문 factor_db_stale · 기저 풀 제외의 입력", v2$reason)
## S2b~S2e (G2 수리 11-10) 선언 팩터 = 셀 엔진의 칸 사양(spec_path = RF_CELL_SPEC)에서 뽑아 기록 → 계약 fdv_stale 이 그 기록으로 비켜 간다
SPD <- file.path(TMP, "specs"); dir.create(SPD, showWarnings = FALSE)
SP_MOM <- file.path(SPD, "cell_mom.json")
writeLines(toJSON(list(code = "B2_1", base_signal = list(kind = "mom_12_1"), factors = list(list(kind = "db", id = "M01_Mom12_1"))), auto_unbox = TRUE), SP_MOM)
SP_ENG <- file.path(SPD, "cell_eng.json")
writeLines(toJSON(list(code = "B2_2", base_signal = list(kind = "engine", path = "x/engine.R"), factors = list(list(kind = "db", id = "M01_Mom12_1"))), auto_unbox = TRUE), SP_ENG)
d2b <- mk_out("20261110_120000_222")
s2b <- E$.rp_fdv_stamp(d2b, "20261110_120000_222", code_root = ROOT, data_root = TMP, spec_path = SP_MOM)
ok(identical(s2b$stale_at_measure, FALSE) && identical(unlist(s2b$declared_factors), "M01_Mom12_1") && identical(s2b$declared_factors_basis, "cell_spec") &&
     identical(s2b$declared_spec_md5, unname(tools::md5sum(SP_MOM))),
   "S2b 셀 엔진 칸 사양 → 선언 팩터 · 근거(cell_spec) · 사양 md5 기록")
d2c <- mk_out("20261110_100000_333")        # R2(01:38) 뒤 · R3(11:26 · Q16 만) 앞
s2c <- E$.rp_fdv_stamp(d2c, "20261110_100000_333", code_root = ROOT, data_root = TMP, spec_path = SP_MOM)
write_json(list(run_id = "20261110_100000_333", essence_grade = "A", factor_db_vintage = s2c), file.path(d2c, "authoritative_remeasure.json"), auto_unbox = TRUE, null = "null", na = "null")
v2c <- FDV$fdv_stale(d2c, ledger = FDV$fdv_ledger(TMP))
ok(identical(s2c$stale_at_measure, FALSE) && identical(v2c$stale, FALSE) && identical(v2c$declared_factors, 1L),
   "S2c 팩터 목록 수리(R3) 앞 측정이지만 선언 팩터가 범위 밖 → 기록 · 계약 판정 둘 다 현행(선언 비켜 가기가 운영 산출물에서 발화)", v2c$reason)
d2d <- mk_out("20261110_100000_444")
s2d <- E$.rp_fdv_stamp(d2d, "20261110_100000_444", code_root = ROOT, data_root = TMP, spec_path = SP_ENG)
write_json(list(run_id = "20261110_100000_444", essence_grade = "A", factor_db_vintage = s2d), file.path(d2d, "authoritative_remeasure.json"), auto_unbox = TRUE, null = "null", na = "null")
ok(is.na(s2d$declared_factors[1]) && isTRUE(s2d$stale_at_measure) && isTRUE(FDV$fdv_stale(d2d, ledger = FDV$fdv_ledger(TMP))$stale),
   "S2d 엔진 기저 칸 사양 → 선언 알 수 없음(NA) → 같은 시각이라도 R3 에 닿아 낡음(보수)")
d2e <- mk_out("20261110_100000_555")
s2e <- E$.rp_fdv_stamp(d2e, "20261110_100000_555", code_root = ROOT, data_root = TMP)
write_json(list(run_id = "20261110_100000_555", essence_grade = "A", factor_db_vintage = s2e), file.path(d2e, "authoritative_remeasure.json"), auto_unbox = TRUE, null = "null", na = "null")
ok(is.na(s2e$declared_factors[1]) && isTRUE(FDV$fdv_stale(d2e, ledger = FDV$fdv_ledger(TMP))$stale),
   "S2e [대조] 칸 사양 없이(논문 엔진) 같은 시각 측정 → 낡음 — S2c 의 현행은 기록된 선언에서 왔다")

cat("=== S3 진행 중 수리 ===\n")
mk_ledger(c(L3, list(list(id = "R4_RUNNING", scope = "all"))))
s3 <- E$.rp_fdv_stamp(d1, "20261110_130000_111", code_root = ROOT, data_root = TMP)
ok(identical(unlist(s3$in_progress), "R4_RUNNING") && isTRUE(s3$stale_at_measure), "S3 진행 중 수리(completed_at 없음) → in_progress · 측정 시각과 무관하게 낡음")
ok(is.na(s3$valid_from) && identical(s1$valid_from, "2026-11-10T11:26:00"),
   "S3 진행 중 수리가 있으면 기록의 valid_from = NA(아직 유효한 판 없음 — 기록이 자기 낡음 판정과 모순되지 않는다) · 완료뿐이면 마지막 완료 시각")
ok(!identical(s3$ledger_md5, s1$ledger_md5), "S3 원장이 바뀌면 원장 md5 도 바뀐다(사후 재도출 키)")

cat("=== S4 원장 파손 ===\n")
writeLines("{ not json", file.path(TMP, "06_Registry/factor_db_vintage.json"))
s4 <- tryCatch(E$.rp_fdv_stamp(d1, "20261110_130000_111", code_root = ROOT, data_root = TMP), error = function(e) list(status = "THREW"))
ok(grepl("^error:", s4$status) && identical(s4$measured_at, "2026-11-10T13:00:00+0900"), "S4 원장 파손 — 멈추지 않고 status=error · measured_at 은 남는다", s4$status)
mk_ledger(L3)

cat("=== S5 원자적 쓰기 ===\n")
p5 <- file.path(d1, "authoritative_remeasure.json")
E$.rp_write_json_atomic(list(a = 1, b = "x", essence_grade = "B"), p5, auto_unbox = TRUE)
ok(file.exists(p5) && identical(fromJSON(p5)$essence_grade, "B") && !length(list.files(d1, pattern = "\\.tmp")), "S5 정상 쓰기 — 파일 · 되읽기 일치 · 임시 파일 없음")
E$.rp_write_json_atomic(list(essence_grade = "C"), p5, auto_unbox = TRUE)
ok(identical(fromJSON(p5)$essence_grade, "C"), "S5 덮어쓰기(같은 이름 재측정)")
p5b <- file.path(d1, "authoritative_remeasure_bad.json")
r5 <- tryCatch({ E$.rp_write_json_atomic(list(f = new.env()), p5b, auto_unbox = TRUE); "no_error" }, error = function(e) "error")
ok(identical(r5, "error") && !file.exists(p5b) && !length(list.files(d1, pattern = "_bad\\.json\\.tmp")), "S5 직렬화 실패 — 오류 전파 · 권위 이름 미생성 · 임시 파일 정리(반쪽 기록 없음)")

cat("=== S6 배선(러너 본문 · 돌연변이) ===\n")
src <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")
wired <- function(s) any(grepl("auth\\$factor_db_vintage <- \\.rp_fdv_stamp\\(OUT_DIR, run_id", s)) &&
  any(grepl("\\.rp_write_json_atomic\\(auth, file\\.path\\(OUT_DIR, \"authoritative_remeasure\\.json\"\\)", s)) &&
  !any(grepl("^\\s*write_json\\(auth, file\\.path\\(OUT_DIR, \"authoritative_remeasure\\.json\"\\)", s)) &&
  any(grepl("QVEST_RP_FDV_STAMP", s)) &&
  any(grepl('Sys.getenv("RF_CELL_SPEC", "") else NULL)', s, fixed = TRUE))
ok(wired(src), "S6 러너가 판 표식을 auth 에 싣고(셀 엔진이면 칸 사양 경로를 넘긴다) 권위 기록을 원자적 쓰기로 쓴다(끄기 스위치 포함)")
m3 <- sub('Sys.getenv("RF_CELL_SPEC", "") else NULL)', 'NULL else NULL)', src, fixed = TRUE)
ok(sum(m3 != src) == 1L && !wired(m3), "S6 돌연변이 ③ 칸 사양 경로 전달 제거 → 탐지(치환 1곳 성사)")
m1 <- sub("auth$factor_db_vintage <- .rp_fdv_stamp(", "auth$factor_db_vintage_DISABLED <- .rp_fdv_stamp(", src, fixed = TRUE)
ok(sum(m1 != src) == 1L && !wired(m1), "S6 돌연변이 ① 판 표식 배선 제거 → 탐지(치환 1곳 성사)")
m2 <- sub(".rp_write_json_atomic(auth, file.path(OUT_DIR, \"authoritative_remeasure.json\"),", "write_json(auth, file.path(OUT_DIR, \"authoritative_remeasure.json\"),", src, fixed = TRUE)
ok(sum(m2 != src) == 1L && !wired(m2), "S6 돌연변이 ② 비원자 쓰기로 되돌림 → 탐지(치환 1곳 성사)")
# 표식 키가 권위 기록의 기존 키를 덮지 않는다(이름 충돌 없음)
ok(sum(grepl("factor_db_vintage\\s*=", src)) == 0L, "S6 auth 리스트 리터럴 안에 같은 이름 키 없음(중복 키 방지)")

cat("=== S7 변형 일부 실패 ===\n")
VER <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
V <- new.env(parent = globalenv()); assign("%||%", `%||%`, envir = V)
gv <- pull_defs(VER, c(".v1001_variant_row", ".v1001_measure_variants", ".v1001_holdings_check"), V)
ok(length(gv) == 3L, "S7 검증기에서 변형 정의 3개 추출", paste(gv, collapse = ","))
assign("ROOT", TMP, envir = V); assign(".RV_CFG", list(holdings_claims = list(short_share_min = 0.5, n_names_ratio_max = 2, net_abs_tol_of_gross = 0.25)), envir = V)
JL <- character(0); assign("jlog", function(ev, ...) JL <<- c(JL, ev), envir = V)
assign("bc_card_from_artifacts", function(...) stop("no card in test"), envir = V)    # 행동 카드 = 비치명(NULL)
mk_art <- function(dir, grade) { dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_json(list(essence_grade = grade, run_id = basename(dir), selection_type = "sweep", n_trials_cumulative = 3L, essence = list(cagr = 0.1)),
             file.path(dir, "authoritative_remeasure.json"), auto_unbox = TRUE)
  fwrite(data.table(date = rep(as.Date("2020-01-31"), 3), target_weight = c(0.4, 0.3, 0.3)), file.path(dir, "04_holdings.csv")); dir }
HEAD <- mk_art(file.path(TMP, "head_run"), "B")
assign("run_paper_replication", function(...) { a <- list(...); id <- a$engine_vars$.RP_VARIANT
  if (identical(id, "v_bad")) stop("엔진 변형 v_bad 실패(대역)")
  d <- mk_art(file.path(a$out_root, paste0("run_", id)), "C"); list(authoritative_remeasure_path = file.path(d, "authoritative_remeasure.json")) }, envir = V)
VP <- list(ids = c("v_head", "v_bad", "v_ok"), headline = "v_head", n = 3L, label = c("대표", "나쁜", "좋은"), spec = list(NULL, NULL, NULL), claims = list(NULL, NULL, NULL))
SM <- V$.v1001_measure_variants(VP, HEAD, "head_run", list(strategy_name = "S"), list(construction = "top_n_long"))
st <- vapply(SM$variants, function(v) v$status, "")
ok(identical(st, c("ok", "error", "ok")), "S7 실패 변형은 그 행에만 error · 나머지 계속", paste(st, collapse = ","))
ok(isTRUE(SM$variants[[1]]$headline) && identical(SM$variants[[1]]$grade, "B") && identical(SM$headline, "v_head"), "S7 대표 행 = 권위 산출물(B) 그대로 · 요약 대표 불변")
ok(file.exists(file.path(HEAD, "variants_summary.json")) && grepl("v_bad", SM$variants[[2]]$error %||% "") && grepl("실패", SM$variants[[2]]$error %||% ""),
   "S7 요약 파일 기록 · 실패 사유 보존")
ok(identical(Sys.getenv("QVEST_RP_SEED_BASE_CACHE", ""), ""), "S7 변형 측정 뒤 기저 캐시 시드 스위치 복원")

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf('{"test":"scn_repl_measure_record","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
