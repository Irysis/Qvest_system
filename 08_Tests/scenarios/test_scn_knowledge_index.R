#!/usr/bin/env Rscript
#==============================================================================
# test_scn_knowledge_index.R — hypothesis_index 조회 품질 · 안전 시나리오 (감사 레인 K · 2026-11-10)
#   격리: 임시 루트(합성 corpus · 원본 L-code · 결과 원장 · 걸음 원장 · 상태 파일) · 운영 06_Registry/hypothesis_index.json 무쓰기.
#   I1 corpus 정체 중 새 원본 L-code 에 철회 표식 → 보충 스캔이 거른다(정본 lcode_validity.py check)
#   I2 정본 판정기 부재 → 보수 폴백(판정 필드가 있으면 제외) · basis 에 폴백 기록
#   I3 [돌연변이] 거르는 줄을 소스 치환으로 지우면 철회 L-code 가 다시 색인된다(가드 발화 실증)
#   I4 v10.2 학습 원장(h): 결과 원장 교훈 · P4 걸음(기각) 이 조회에 나온다 · 수치 없음
#   I5 결과 원장이 인덱스보다 새면 stale
#   I6 재빌드 잠금이 살아 있으면 lookup 은 재빌드하지 않고 기존 인덱스로 답한다 · 죽은 잠금(600초+)은 회수
#   I7 HI_NO_AUTO_REBUILD=1 → 읽기 전용(인덱스 무변경)
#   I8 교체 쓰기: 기존 인덱스 위로 rename(먼저 지우지 않음 — 소스 대조 + 동작)
#   I9 DIST 퇴역 상태면 날짜 순 · 아니면 DIST 우선(구 동작 보존)
#   I10 벡터화 매칭 = 구 항목별 매칭(.hi_entry_matches)과 같은 결과
#   I12 (11-10(2) 감사 U11) 수확 뒤 철회 — corpus 사본도 빠진다 · invalidated 와 겹친 corpus 키도 빠진다 · [돌연변이] 건너뛰기 줄 삭제 → 다시 색인
#   I13 (11-10(2) 감사 U11) 결과 원장 = 설계 입력과 같은 규율(격리 · 처방 입력 미통과 줄 제외 · 반파 줄 경고 · coverage 건수) · [돌연변이] 직접 읽기 복원 → 다시 색인
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
CR <- gsub("\\", "/", dirname(dirname(dirname(self))), fixed = TRUE)
HI <- file.path(CR, "02_Infrastructure/tools/hypothesis_index.R")
if (!file.exists(HI)) stop("코드 루트 해석 실패: ", CR)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(c, m, why = "") if (isTRUE(c)) ok(m) else ng(m, why)
q <- function(expr) suppressMessages(suppressWarnings(expr))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

S <- gsub("\\", "/", file.path(tempdir(), sprintf("scn_kidx_%d", Sys.getpid())), fixed = TRUE)
mk <- function(rel) { p <- file.path(S, rel); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); p }
old <- Sys.time() - 3 * 86400
cp <- mk(".cache/lcode_corpus.json")
write_json(list(lcodes = list(list(l_code = "L-OLD-1", strategy_id = "RP_OLD_1", grade = "C", lesson_text = "old momentum lesson",
                                   research_mode = "paper_replication", mtime = "2026-10-01T00:00:00")), invalidated_lcodes = list()), cp, auto_unbox = TRUE)
Sys.setFileTime(cp, old)
la <- mk("stage_artifacts/l_code/paper_replication/l_code_RP_NEW_A.json")
lb <- mk("stage_artifacts/l_code/paper_replication/l_code_RP_NEW_B.json")
write_json(list(l_code = "L-RP-NEW-A", strategy_id = "RP_NEW_A", grade = "F", lesson_text = "residual momentum 충실구현", research_mode = "paper_replication",
                metric_type = "backtested"), la, auto_unbox = TRUE)
write_json(list(l_code = "L-RP-NEW-B", strategy_id = "RP_NEW_B", grade = "B", lesson_text = "철회된 momentum 측정", research_mode = "paper_replication",
                metric_type = "backtested", pit_invalid = TRUE, retracted_by = "L-RP-FIX-1", retracted_at = "2026-11-08"), lb, auto_unbox = TRUE)
vp <- mk("02_Infrastructure/axiom/lcode_validity.py"); file.copy(file.path(CR, "02_Infrastructure/axiom/lcode_validity.py"), vp, overwrite = TRUE)
op <- mk("06_Registry/round_outcomes.jsonl")
## τ_D 정본(behavior_card.json::tau_d) — 색인의 결과 원장 읽기는 설계 입력과 같은 처방 입력 검사를 쓴다(없으면 fail-closed 로 전부 빠진다 · 11-10(2))
invisible(file.copy(file.path(CR, "06_Registry/behavior_card.json"), mk("06_Registry/behavior_card.json")))
writeLines(as.character(toJSON(list(schema = "round_outcome_v1", kind = "round", at = "2026-11-09T10:00:00+0900", program = "P2_DEFENSE", round_id = "P2R90",
  template = "p2_device", epoch = "all_hyg_px1000_2000_v1", verdict_label = "기각", n_cells = 3, n_variants = 2, note = "해석",
  probes = list("하락 국면 노출 경로", "위기 분해"), lessons = list("모멘텀 붕괴 구간에서 방어 장치가 늦다"), r7 = "noise"), auto_unbox = TRUE)), op)
cs <- mk("04_Research/programs/P4_ASSEMBLY/P4C01/chain_steps.jsonl")
writeLines(c('{"schema":"rc_p4_chain_steps_v1","at":"2026-11-09T11:00:00+0900","event":"step_open","k":1,"block_type":"tail_overlay","hypothesis":"꼬리 오버레이로 위기 하락 포착을 낮춘다","mechanism":"변동성 급등 선행","generator_version":"g1","parent":0}',
             '{"schema":"rc_p4_chain_steps_v1","at":"2026-11-09T12:00:00+0900","event":"step_result","k":1,"decision":"reject","reasons":["d_dd_capture_median_vis: 0.031 > 0","uc_vis: 하한 미달"]}'), cs)
dk <- mk("06_Registry/distilled_knowledge.json")
write_json(list(entries = list(list(dist_id = "DIST-AR-900", status = "distilled", polarity = "negative", research_mode = "alpha_research",
                                    statement_refined = "momentum 단독 경로 실패 지도", created_at = "2026-07-01", supporting_l_codes = list("L-OLD-1")))), dk, auto_unbox = TRUE)
IDX <- file.path(S, "06_Registry/hypothesis_index.json")

load_hi <- function(path = HI) { e <- new.env(); q(sys.source(path, envir = e)); e }
E <- load_hi()
cat("\n[I1] 철회 표식 — 정본 판정기\n")
x <- q(E$build_hypothesis_index(root = S, out_path = IDX, verbose = FALSE))
ids <- vapply(x$entries, function(e) e$strategy_id, "")
chk("RP_NEW_A" %in% ids && !("RP_NEW_B" %in% ids), "I1a 새 원본 A 색인 · 철회 B 제외", paste(ids, collapse = ","))
chk(identical(x$coverage$lcode_supplement_invalidated_excluded, 1L) && identical(x$coverage$lcode_supplement_validity_basis, "lcode_validity.py check"),
    "I1b coverage = 제외 1 · 정본 basis", paste(x$coverage$lcode_supplement_validity_basis))

cat("\n[I2] 정본 판정기 부재 → 보수 폴백\n")
file.rename(vp, paste0(vp, ".off"))
x2 <- q(E$build_hypothesis_index(root = S, out_path = IDX, verbose = FALSE))
ids2 <- vapply(x2$entries, function(e) e$strategy_id, "")
chk(!("RP_NEW_B" %in% ids2) && "RP_NEW_A" %in% ids2 && grepl("^fallback_presence", x2$coverage$lcode_supplement_validity_basis %||% ""),
    "I2 폴백도 B 제외 · A 유지 · basis 폴백", paste(x2$coverage$lcode_supplement_validity_basis))
file.rename(paste0(vp, ".off"), vp)

cat("\n[I3] [돌연변이] 거르는 줄 삭제\n")
src <- readLines(HI, warn = FALSE, encoding = "UTF-8"); tgt <- "        raw_new <- raw_new[!inv$exclude]"
n_hit <- sum(src == tgt); mut <- file.path(S, "hi_mut.R"); writeLines(src[src != tgt], mut, useBytes = TRUE)
chk(n_hit == 1L, "I3a 치환 1곳 성사")
xm <- q(load_hi(mut)$build_hypothesis_index(root = S, out_path = file.path(S, "mut_idx.json"), verbose = FALSE))
chk("RP_NEW_B" %in% vapply(xm$entries, function(e) e$strategy_id, ""), "I3b 돌연변이 사본은 철회 B 를 다시 색인한다(가드가 실제로 막고 있었다)")

cat("\n[I4] v10.2 학습 원장(h)\n")
r4 <- q(E$lookup_hypothesis("모멘텀", index_path = IDX, root = S, auto_rebuild = FALSE))
chk(is.data.frame(r4) && "RO_P2R90" %in% r4$strategy_id && r4$verdict[r4$strategy_id == "RO_P2R90"] == "ROUND_NOISE", "I4a 결과 원장 교훈이 조회된다(ROUND_NOISE)")
r4b <- q(E$lookup_hypothesis("tail_overlay", index_path = IDX, root = S, auto_rebuild = FALSE))
row <- r4b[r4b$strategy_id == "P4S_P4C01_k1", , drop = FALSE]
chk(nrow(row) == 1L && row$verdict == "STEP_REJECT" && row$research_mode == "p4_chain", "I4b P4 기각 걸음이 조회된다(STEP_REJECT)")
ent <- Filter(function(e) identical(e$strategy_id, "P4S_P4C01_k1"), x$entries)[[1]]
chk(identical(ent$key_metrics$reject_codes, "d_dd_capture_median_vis;uc_vis") && !grepl("0\\.031", toJSON(ent, auto_unbox = TRUE)),
    "I4c 사유는 코드만 · 보는 창 수치(0.031)는 옮기지 않는다")
chk(grepl("all_hyg_px1000_2000_v1", Filter(function(e) identical(e$strategy_id, "RO_P2R90"), x$entries)[[1]]$hypothesis_signature, fixed = TRUE),
    "I4d 결과 원장 항목 서명에 측정 축 epoch")
## I4e (2026-11-10 감사 U11) 측정 실패로 포기한 걸음 = STEP_ABANDONED(가설 기각 아님) · 기각 사유 코드에 싣지 않는다. 같은 원장의 진짜 기각은 그대로.
abd <- file.path(S, "abn_chain", "P4C_ABN"); dir.create(abd, recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  '{"event":"step_open","k":1,"block_type":"overlay","hypothesis":"포기 걸음 시험","mechanism":"m","at":"2026-11-10T10:00:00"}',
  '{"event":"step_result","k":1,"decision":"reject","abandoned":true,"reasons":["measure_failed: 3회"]}',
  '{"event":"step_open","k":2,"block_type":"overlay","hypothesis":"기각 걸음 시험","mechanism":"m","at":"2026-11-10T11:00:00"}',
  '{"event":"step_result","k":2,"decision":"reject","reasons":["uc_vis: x"]}'), file.path(abd, "steps.jsonl"), useBytes = TRUE)
pa <- q(E$.hi_parse_chain_steps(file.path(abd, "steps.jsonl"), root = S))
va <- vapply(pa, function(e) e$verdict, ""); ca <- vapply(pa, function(e) e$key_metrics$reject_codes, "")
chk(identical(va, c("STEP_ABANDONED", "STEP_REJECT")) && identical(ca, c("", "uc_vis")),
    "I4e 포기 걸음 = STEP_ABANDONED · 사유 코드 비움 / 진짜 기각 = STEP_REJECT · 코드 유지", paste(va, ca, collapse = " | "))

cat("\n[I5] stale 감지\n")
Sys.setFileTime(IDX, Sys.time() - 60); Sys.setFileTime(op, Sys.time())
chk(any(grepl("v10.2", q(E$.hi_stale_check(IDX, root = S, warn = FALSE)))), "I5 결과 원장이 새면 stale")

cat("\n[I6] 재빌드 잠금\n")
lk <- paste0(IDX, ".rebuild.lock"); dir.create(lk); m0 <- file.info(IDX)$mtime
r6 <- q(E$lookup_hypothesis("momentum", index_path = IDX, root = S))
chk(identical(file.info(IDX)$mtime, m0) && is.data.frame(r6) && nrow(r6) > 0, "I6a 잠금 중엔 재빌드 없이 기존 인덱스로 응답")
Sys.setFileTime(lk, Sys.time() - 700)
invisible(q(E$lookup_hypothesis("momentum", index_path = IDX, root = S)))
chk(!identical(file.info(IDX)$mtime, m0) && !dir.exists(lk), "I6b 죽은 잠금(700초)은 회수하고 재빌드 · 잠금 해제")

cat("\n[I7] 읽기 전용 스위치\n")
Sys.setFileTime(IDX, Sys.time() - 60); Sys.setFileTime(op, Sys.time()); m1 <- file.info(IDX)$mtime
Sys.setenv(HI_NO_AUTO_REBUILD = "1"); invisible(q(E$lookup_hypothesis("momentum", index_path = IDX, root = S))); Sys.unsetenv("HI_NO_AUTO_REBUILD")
chk(identical(file.info(IDX)$mtime, m1), "I7 HI_NO_AUTO_REBUILD=1 → 인덱스 무변경")

cat("\n[I8] 교체 쓰기\n")
body <- paste(deparse(E$build_hypothesis_index), collapse = "\n")
i_ren <- regexpr("renamed <- suppressWarnings(file.rename(tmp_path, out_path))", body, fixed = TRUE)
i_rm <- regexpr("file.remove(out_path)", body, fixed = TRUE)
chk(i_ren > 0 && i_rm > i_ren, "I8a 먼저 rename(덮어쓰기) · 지우기는 실패 폴백에서만")
q(E$build_hypothesis_index(root = S, out_path = IDX, verbose = FALSE))
chk(file.exists(IDX) && length(Sys.glob(file.path(S, "06_Registry", ".hypothesis_index.json.tmp_*"))) == 0L, "I8b 기존 파일 위 교체 · 임시 파일 잔재 없음")

cat("\n[I9] 정렬 — DIST 퇴역 여부\n")
rA <- q(E$lookup_hypothesis("momentum", index_path = IDX, root = S, auto_rebuild = FALSE))
chk(grepl("^DISTILLED", rA$verdict[1]), "I9a 퇴역 표식 없으면 DIST 우선(구 동작)")
write_json(list(promotion_enabled = FALSE), mk("06_Registry/axiom_engine_status.json"), auto_unbox = TRUE)
rB <- q(E$lookup_hypothesis("momentum", index_path = IDX, root = S, auto_rebuild = FALSE))
chk(!grepl("^DISTILLED", rB$verdict[1]) && rB$date[1] >= max(rB$date), "I9b 퇴역이면 날짜 순(최신 먼저)")

cat("\n[I10] 벡터화 매칭 ≡ 항목별 매칭\n")
idx <- fromJSON(IDX, simplifyVector = FALSE); eq <- TRUE
for (kw in list("momentum", c("tail_overlay"), c("모멘텀", "방어"), c("defense", "regime"), "p4_chain")) {
  ex <- lapply(tolower(kw), E$.hi_expand_kw)
  old_ids <- vapply(Filter(function(e) E$.hi_entry_matches(e, ex), idx$entries), function(e) e$strategy_id, "")
  new <- q(E$lookup_hypothesis(kw, index_path = IDX, root = S, auto_rebuild = FALSE, max_rows = 10000L))
  new_ids <- if (is.data.frame(new) && nrow(new)) new$strategy_id else character(0)
  if (length(kw) > 1L && !length(old_ids)) next   # 다어 폴백 경로는 비교 대상 밖
  if (!setequal(old_ids, new_ids)) { eq <- FALSE; cat("    불일치:", paste(kw, collapse = " "), "\n") }
}
chk(eq, "I10 같은 항목 집합")

cat("\n[I11] CLI 블록 — ASCII 전용 · 실행(lookup regime)\n")
cli_nonascii <- function(lines) { i <- grep("^if \\(sys.nframe\\(\\) == 0 && !interactive\\(\\)\\) \\{", lines)
  if (length(i) != 1L) return(NA_integer_); b <- lines[i:length(lines)]; b <- b[!grepl("^\\s*#", b)]
  sum(vapply(b, function(l) any(utf8ToInt(l) > 127L), logical(1))) }
chk(identical(cli_nonascii(src), 0L), "I11a CLI 블록 코드 줄 비ASCII 0(파싱 오류 보고 11-10 E2 의 방어)")
mut2 <- src; k <- grep("hits \\(FAIL %d", mut2); mut2[k] <- sub("\\\\u00b7", "·", mut2[k])
chk(length(k) == 1L && cli_nonascii(mut2) >= 1L, "I11b [돌연변이] 가운뎃점을 날문자로 되돌리면 red")
ev <- file.path(S, ".Renviron_empty"); writeLines("", ev)
old_env <- Sys.getenv(c("QM_ROOT", "R_ENVIRON_USER"), unset = NA); Sys.setenv(QM_ROOT = S, R_ENVIRON_USER = ev)   # Windows system2 는 env= 를 무시한다
out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(shQuote(HI), "lookup", "regime", "--no-rebuild"), stdout = TRUE, stderr = TRUE))
for (n in names(old_env)) if (is.na(old_env[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, stats::setNames(list(old_env[[n]]), n))
st <- attr(out, "status") %||% 0L
chk(st == 0L && any(grepl("^\\[hypothesis_index\\] [0-9]+ hits \\(FAIL", out)) && !any(grepl("Error|unexpected", out)),
    "I11c CLI lookup regime --no-rebuild = 종료 0 · 요약 1줄 · 오류 없음", paste(utils::tail(out, 3), collapse = " | "))

cat("\n[I12] 수확 뒤 철회 — corpus 사본도 색인에서 빠진다(11-10(2) 감사 U11 · 철회 수리 나머지 절반)\n")
S2 <- paste0(S, "_hv")
mk2 <- function(rel) { p <- file.path(S2, rel); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); p }
lc2 <- function(id, sid, txt) list(l_code = id, strategy_id = sid, grade = "F", lesson_text = txt, research_mode = "paper_replication", mtime = "2026-11-01T00:00:00")
cp2 <- mk2(".cache/lcode_corpus.json")
write_json(list(lcodes = list(lc2("L-HV-1", "RP_HV_1", "harvested then retracted carry"), lc2("L-HV-2", "RP_HV_2", "harvested valid carry"),
                              lc2("L-HV-3", "RP_HV_3", "listed in both carry")),
                invalidated_lcodes = list(list(l_code = "L-HV-3", why = "retracted_by"))), cp2, auto_unbox = TRUE)
Sys.setFileTime(cp2, old)
h1 <- mk2("stage_artifacts/l_code/paper_replication/l_code_RP_HV_1.json")   # 수확 뒤(mtime > corpus) 철회 표식을 단 원본
write_json(list(l_code = "L-HV-1", strategy_id = "RP_HV_1", grade = "F", lesson_text = "harvested then retracted carry", research_mode = "paper_replication",
                metric_type = "backtested", pit_invalid = TRUE, retracted_by = "L-HV-FIX", retracted_at = "2026-11-09"), h1, auto_unbox = TRUE)
invisible(file.copy(file.path(CR, "02_Infrastructure/axiom/lcode_validity.py"), mk2("02_Infrastructure/axiom/lcode_validity.py"), overwrite = TRUE))
x12 <- q(E$build_hypothesis_index(root = S2, out_path = file.path(S2, "idx.json"), verbose = FALSE))
ids12 <- vapply(x12$entries, function(e) e$strategy_id, "")
chk(!("RP_HV_1" %in% ids12) && "RP_HV_2" %in% ids12, "I12a 수확 뒤 철회된 L-code 는 corpus 사본으로도 색인되지 않는다 · 유효한 것은 남는다", paste(ids12, collapse = ","))
chk(!("RP_HV_3" %in% ids12), "I12b corpus.invalidated_lcodes 에 있는 키는 corpus lcodes 에 같이 있어도 뺀다(모든 추가 경로에 같은 철회 집합)")
chk(identical(x12$coverage$lcode_corpus_retracted_excluded, 2L), "I12c coverage = corpus 사본 제외 2", paste(x12$coverage$lcode_corpus_retracted_excluded %||% "NULL"))
src12 <- readLines(HI, warn = FALSE, encoding = "UTF-8")
tgt12 <- "      if (nzchar(k) && k %in% lc_retracted) { cov$lcode_corpus_retracted_excluded <- cov$lcode_corpus_retracted_excluded + 1L; next }"
mut12 <- file.path(S2, "hi_mut12.R"); writeLines(src12[src12 != tgt12], mut12, useBytes = TRUE)
chk(sum(src12 == tgt12) == 1L, "I12d 치환 1곳 성사")
xm12 <- q(load_hi(mut12)$build_hypothesis_index(root = S2, out_path = file.path(S2, "mut_idx.json"), verbose = FALSE))
chk("RP_HV_1" %in% vapply(xm12$entries, function(e) e$strategy_id, ""), "I12e [돌연변이] 건너뛰기 줄을 지우면 철회된 corpus 사본이 다시 색인된다")
unlink(S2, recursive = TRUE)

cat("\n[I13] 결과 원장 — 설계 입력과 같은 규율(격리 · 처방 입력 미통과 줄 제외 · 반파 줄 경고 · 11-10(2) 감사 U11)\n")
S3 <- paste0(S, "_ro"); dir.create(file.path(S3, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(CR, "06_Registry/behavior_card.json"), file.path(S3, "06_Registry/behavior_card.json")))
op3 <- file.path(S3, "06_Registry/round_outcomes.jsonl")
rec3 <- function(id, lesson) as.character(toJSON(list(schema = "round_outcome_v1", kind = "round", at = "2026-11-09T10:00:00+0900", program = "P2_DEFENSE",
  round_id = id, template = "p2_device", epoch = "all_hyg_px1000_2000_v1", verdict_label = "기각", n_cells = 2, n_variants = 1, note = "해석",
  probes = list("탐침 하나", "탐침 둘"), lessons = list(lesson), r7 = "noise"), auto_unbox = TRUE))
writeLines(c(rec3("P2R71", "깨끗한 교훈 carry"), rec3("P2R72", "전기간 A등급 후보 carry"), rec3("P2R73", "격리할 교훈 carry"),
             '{"schema":"round_outcome_v1","kind":"round",'), op3, useBytes = TRUE)
RE <- new.env(parent = globalenv())
for (f in c("util.R", "standing.R", "outcomes.R")) q(sys.source(file.path(CR, "04_Research/programs/_lib/round_core/v1", f), envir = RE))
invisible(RE$rc_outcomes_quarantine(op3, 3L, "시험 — 격리"))
w13 <- character(0)
x13 <- withCallingHandlers(suppressMessages(E$build_hypothesis_index(root = S3, out_path = file.path(S3, "idx.json"), verbose = FALSE)),
                           warning = function(w) { w13 <<- c(w13, conditionMessage(w)); invokeRestart("muffleWarning") })
ids13 <- vapply(x13$entries, function(e) e$strategy_id, "")
chk("RO_P2R71" %in% ids13 && !("RO_P2R72" %in% ids13) && !("RO_P2R73" %in% ids13), "I13a 깨끗한 줄만 색인 · 미통과(A등급 · 전기간) · 격리 줄은 빠진다", paste(ids13, collapse = ","))
cv13 <- x13$coverage
chk(identical(cv13$v102_outcomes_input_excluded, 1L) && identical(cv13$v102_outcomes_quarantined, 1L) && identical(cv13$v102_outcomes_bad_lines, 1L),
    "I13b coverage = 미통과 1 · 격리 1 · 반파 1(따로 센다)", paste(cv13$v102_outcomes_input_excluded %||% "NULL", cv13$v102_outcomes_quarantined %||% "NULL", cv13$v102_outcomes_bad_lines %||% "NULL"))
chk(any(grepl("반파|판독 불가", w13)), "I13c 반파 줄은 조용히 버리지 않고 경고", paste(w13, collapse = " | "))
src13 <- readLines(HI, warn = FALSE, encoding = "UTF-8"); tgt13 <- "  rd <- .hi_outcome_recs(path, root)"
mut13 <- file.path(S3, "hi_mut13.R"); writeLines(sub(tgt13, "  rd <- list(recs = .hi_jsonl(path))", src13, fixed = TRUE), mut13, useBytes = TRUE)
chk(sum(src13 == tgt13) == 1L, "I13d 치환 1곳 성사")
xm13 <- q(load_hi(mut13)$build_hypothesis_index(root = S3, out_path = file.path(S3, "mut_idx.json"), verbose = FALSE))
chk("RO_P2R72" %in% vapply(xm13$entries, function(e) e$strategy_id, ""), "I13e [돌연변이] 공용 읽기를 원래 직접 읽기로 되돌리면 미통과 줄이 다시 색인된다")
unlink(S3, recursive = TRUE)

unlink(S, recursive = TRUE)
cat(sprintf('{"test":"test_scn_knowledge_index","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
