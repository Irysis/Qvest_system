#!/usr/bin/env Rscript
# test_scn_advisor_dryrun.R — /advisor 흐름 건식 시나리오 (2026-11-10 v10.2 감사 레인 Q)
#
# 무엇: 실제 측정 · 에이전트 스폰 · 텔레그램 · 원장 쓰기 없이, /advisor 절차(스킬 · 명령 · 에이전트 4종)가
#   요구하는 파일 · 함수 · 인자 · 산출 필드가 오늘 코드에 실재하는지와, 장난감 아이디어로 시행 회계 절차를
#   임시 디렉터리에서 끝까지 걸어 본다. 운영 등록부 · .cache · 원장에는 쓰지 않는다(쓰기 = tempdir 뿐).
#   기존 계약 검사(08_Tests/worktask/test_qepm_advisor_contract.R · 문서 문언 140 단언)와 겹치지 않는 것만 본다:
#   S1 참조 경로 실재 · S2 측정 호출 인자 ⊆ 러너 형식 인자 · S3 장난감 계보의 시행 회계(chain → sweep → A 관문 구조 보류)
#   S4 보고 필드 ⊆ essence 산출 필드 · S5 소비 기록 억제의 대가가 문서화됐는가(레인 선택기 재도출)
#   S6 낡은 사실 재유입 차단(돌연변이 주입 red) · S7 검정력 문턱 키 실재.
suppressMessages(library(jsonlite))

.root <- local({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  d <- if (length(f)) dirname(f[1]) else getwd()
  for (i in 1:8) { if (file.exists(file.path(d, "CLAUDE.md")) && dir.exists(file.path(d, ".claude"))) break; d <- dirname(d) }
  d
})
stopifnot(file.exists(file.path(.root, "CLAUDE.md")))
ROOT <- .root
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat("  ok  ", m, "\n") }
ng <- function(m, why = "") { F <<- F + 1L; cat("  NG  ", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(m, cond, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
rd <- function(p) { f <- file.path(ROOT, p); if (!file.exists(f)) return(""); paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n") }
has <- function(t, s) grepl(s, t, fixed = TRUE)

SKL <- rd(".claude/skills/qvest-advisor/SKILL.md")
CMD <- rd(".claude/commands/advisor.md")
RPR <- rd("02_Infrastructure/alpha_search/run_paper_replication.R")
ESS <- rd("02_Infrastructure/contracts/essence_score.R")
PICK <- rd("02_Infrastructure/ops/rf_next_paper_pick.py")
chk("S0 원천 문서 · 코드 적재", nzchar(SKL) && nzchar(CMD) && nzchar(RPR) && nzchar(ESS) && nzchar(PICK))

## ── S1 참조 경로 실재 ─────────────────────────────────────────────────────────
ticks <- function(t) { m <- gregexpr("`[^`\n]+`", t, perl = TRUE); gsub("`", "", regmatches(t, m)[[1]], fixed = TRUE) }
path_like <- function(x) {
  x <- sub("::.*$", "", x); x <- sub("\\(.*$", "", x); x <- trimws(x)
  x[grepl("^[A-Za-z0-9_./-]+\\.(R|sh|json|md|py|jsonl)$", x, perl = TRUE) & grepl("/", x, fixed = TRUE) &
      !grepl("<|>|\\*|YYYY", x, perl = TRUE)]
}
resolve <- function(p) {
  cand <- c(p, file.path("02_Infrastructure", p))
  any(file.exists(file.path(ROOT, cand)))
}
GEN <- c("trials.jsonl", "authoritative_remeasure.json")   # 산출물 이름(측정 때 생긴다)
# 금지 목록에만 나오는 퇴역 경로(쓰지 말라는 대상 — 없어도 절차는 끊기지 않는다 · 1계층 강화 후보별 요청 퇴역 v10.01)
FORBID_ONLY <- c("06_Registry/grade_a_queue.json")
for (doc in list(c(".claude/skills/qvest-advisor/SKILL.md", "10"), c(".claude/commands/advisor.md", "1"))) {
  ps <- unique(path_like(ticks(rd(doc[1]))))
  ps <- ps[!basename(ps) %in% GEN & !ps %in% FORBID_ONLY & !grepl("^stage_artifacts/|^04_Research/advisor/[^R]", ps, perl = TRUE)]
  miss <- ps[!vapply(ps, resolve, logical(1))]
  chk(sprintf("S1 %s — 참조 경로 %d건 전부 실재", basename(doc[1]), length(ps)), length(ps) >= as.integer(doc[2]) && !length(miss), paste(miss, collapse = " | "))
}
chk("S1m 돌연변이 — 스킬에 없는 경로 주입 → red", !resolve("02_Infrastructure/alpha_search/run_paper_replication_v0.R"))
# 스폰 표의 subagent_type 은 에이전트 정의가 있고, 그 정의의 어드바이저 산출 파일명이 표와 같다
tb <- regmatches(SKL, gregexpr("\\| [^|\n]+ \\| `([a-z-]+)` \\| `([a-z_]+\\.md)` \\|", SKL, perl = TRUE))[[1]]
chk("S1b 스폰 표 행 ≥ 4", length(tb) >= 4L, as.character(length(tb)))
for (row in tb) {
  ag <- sub("^.*\\| `([a-z-]+)` \\| `([a-z_]+\\.md)` \\|$", "\\1", row, perl = TRUE)
  fl <- sub("^.*\\| `([a-z-]+)` \\| `([a-z_]+\\.md)` \\|$", "\\2", row, perl = TRUE)
  A <- rd(file.path(".claude/agents", paste0(ag, ".md")))
  chk(sprintf("S1c %s — 정의 실재 · 어드바이저 모드 · 산출 %s 일치", ag, fl),
      nzchar(A) && has(A, "★**어드바이저 모드**") && has(A, paste0("<YYYYMMDD>_<slug>/", fl)))
}

## ── S2 측정 호출 인자 ⊆ 러너 형식 인자 · 환경변수는 러너가 읽는다 ─────────────────
rp_formals <- local({
  ex <- parse(text = RPR, keep.source = FALSE)
  hit <- NULL
  for (e in ex) if (is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "run_paper_replication")) hit <- e[[3]]
  if (is.null(hit)) character(0) else names(formals(eval(hit, envir = new.env(parent = baseenv()))))
})
chk("S2a 러너 형식 인자 재도출", length(rp_formals) > 10L, as.character(length(rp_formals)))
blk <- local({
  L <- strsplit(SKL, "\n", fixed = TRUE)[[1]]; s <- grep("^```r\\s*$", L, perl = TRUE); out <- character(0)
  for (i in s) { j <- i + 1L; while (j <= length(L) && !grepl("^```\\s*$", L[j], perl = TRUE)) j <- j + 1L
    b <- paste(L[(i + 1L):(j - 1L)], collapse = "\n"); if (has(b, "run_paper_replication(")) out <- b }
  out
})
call_args <- local({
  if (!length(blk)) return(NULL)
  ex <- tryCatch(parse(text = blk, keep.source = FALSE), error = function(e) NULL); if (is.null(ex)) return(NULL)
  a <- NULL
  walk <- function(x) { if (is.call(x)) { if (identical(as.character(x[[1]])[1], "run_paper_replication")) a <<- names(as.list(x))[-1]
    for (k in as.list(x)[-1]) walk(k) } }
  for (e in ex) walk(e); a
})
chk("S2b 스킬 측정 블록 파싱 · 이름 인자 추출", length(call_args) >= 8L, paste(call_args, collapse = ","))
chk("S2c 스킬 측정 인자 ⊆ 러너 형식 인자", length(call_args) && all(call_args %in% rp_formals), paste(setdiff(call_args, rp_formals), collapse = ","))
envs <- unique(regmatches(blk, gregexpr("Sys\\.setenv\\(([A-Z_]+)", blk, perl = TRUE))[[1]])
envs <- sub("Sys\\.setenv\\(", "", envs)
chk("S2d 측정 블록 환경변수를 러너가 읽는다", length(envs) >= 1L && all(vapply(envs, function(v) has(RPR, sprintf("Sys.getenv(\"%s\"", v)), logical(1))), paste(envs, collapse = ","))

## ── S3 장난감 계보 — 시행 회계 건식 보행(임시 디렉터리 · 측정 없음) ──────────────
td <- file.path(tempdir(), paste0("adv_dry_", Sys.getpid())); dir.create(td, recursive = TRUE, showWarnings = FALSE)
writeLines(c("# input", "toy: KR 저변동 상위 25종 월간 — 근거 논문 Ang et al. 2006"), file.path(td, "input.md"))
tj <- file.path(td, "trials.jsonl")
next_trial <- function(tj) {   # 스킬 ④ 시행 회계 규칙의 기계 판: n = 1 + 줄 수 · 첫 판 chain · 둘째부터 sweep
  n_prev <- if (file.exists(tj)) length(readLines(tj, warn = FALSE)) else 0L
  list(k = n_prev + 1L, n_trials_cumulative = 1L + n_prev, selection_type = if (n_prev == 0L) "chain" else "sweep")
}
t1 <- next_trial(tj); cat(toJSON(c(t1, run_id = "DRY1"), auto_unbox = TRUE), "\n", file = tj, append = TRUE)
t2 <- next_trial(tj)
chk("S3a 첫 판 = chain/1 · 둘째 판 = sweep/2", identical(t1$selection_type, "chain") && t1$n_trials_cumulative == 1L &&
      identical(t2$selection_type, "sweep") && t2$n_trials_cumulative == 2L)
chk("S3b 스킬이 규칙 문언을 갖는다(1 + trials.jsonl 줄 수 · 둘째부터 sweep)", has(SKL, "1 + 이 계보에서 이미 측정한 칸 수(`trials.jsonl` 줄 수)") && has(SKL, "두 번째부터) = `\"sweep\"`"))
gate <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE), error = function(e) NULL)
req <- tryCatch(gate$codes$accounting_fail$replication_required_selection_type, error = function(e) NULL)
if (is.null(req)) req <- tryCatch({ x <- unlist(gate); unname(x[grepl("replication_required_selection_type$", names(x))])[1] }, error = function(e) NULL)
chk("S3c A 관문 설정 재도출 — 충실구현 회계 요건 = chain", identical(as.character(req), "chain"), as.character(req))
chk("S3d 둘째 판(sweep)은 A 관문 구조 보류 — 스킬이 그 사실을 적었다", !identical(t2$selection_type, req) && has(SKL, "A → Judge 경로가 구조적으로 닫혀 있다"))
GV <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE), error = function(e) NULL)
chk("S3e 등급 v3.4 스윕 관문 = 선택 현실 점검 · 미제출 = dsr_legacy (스킬 서술과 일치)",
    identical(GV$rules_version, "v3.4") && identical(GV$selection_bias$without_check, "dsr_legacy") && has(SKL, "경과 규정(종전 DSR 관문)") &&
      file.exists(file.path(ROOT, "02_Infrastructure/programs/selection_regrade.R")))

## ── S4 보고 필드 ⊆ essence 산출 필드 ─────────────────────────────────────────
fld <- c("dd_capture_median = ", "uc_median = ", "cdar = ", "mc8 = list(", "cr = list(overall = ")
chk("S4a essence 산출에 행동 카드 요약 필드 실재", all(vapply(fld, function(s) has(ESS, s), logical(1))))
rep_ok <- function(t) all(vapply(c("`cr.dd_capture_median`", "`cr.uc_median`", "`cr.cdar`", "`mc8.label`", "위기 방어"), function(s) has(t, s), logical(1)))
chk("S4b 스킬 보고 양식 = lean-loop ①(위기 방어 · 하락 포착 · 상승 포착 · 귀속)", rep_ok(SKL))
chk("S4c 돌연변이 — 보고 양식에서 상승 포착 필드 삭제 → red", !rep_ok(sub("`cr.uc_median`", "", SKL, fixed = TRUE)))

## ── S5 소비 기록 억제의 대가 — 레인 선택기 재도출 ─────────────────────────────
pick_reads_l1 <- has(PICK, "reinforce_ledger_l1.json") && grepl("def _consumed", PICK, fixed = TRUE)
rpr_gated <- grepl("identical\\(Sys.getenv\\(\"QVEST_NO_LEDGER_OPEN\", \"0\"\\), \"1\"\\)\\) \\{[^}]*auto-open 억제", RPR, perl = TRUE) && has(RPR, "rf_park_entry(1L")
chk("S5a 사실 재도출 — 선택기 소비 정본 = L1 원장 · 러너 L1 기록은 억제 스위치로 꺼진다", pick_reads_l1 && rpr_gated)
cost_ok <- function(t) has(t, "rf_next_paper_pick.py::_consumed") && has(t, "같은 논문이 큐에 있으면 레인이 다시")
chk("S5b 스킬이 억제의 대가(중복 측정 위험)를 적었다", cost_ok(SKL))
chk("S5c 돌연변이 — 대가 문단 삭제 → red", !cost_ok(sub("같은 논문이 큐에 있으면 레인이 다시", "", SKL, fixed = TRUE)))

## ── S6 낡은 사실 재유입 차단 ───────────────────────────────────────────────
STALE <- list(
  list(".claude/skills/qvest-advisor/SKILL.md", "도훈이 강화 이관을 승인했을 때만 이 줄을 뺀다"),
  list(".claude/skills/qvest-advisor/SKILL.md", "통과분의 후보별 요청"),
  list(".claude/skills/qvest-advisor/SKILL.md", "t = Grade A PORT_t 문턱"),
  list(".claude/skills/qvest-attribution-style/SKILL.md", "graduation gate (HARD 3종"),
  list(".claude/skills/qvest-attribution-style/SKILL.md", "분기별 자동(attribution_quarterly_trigger)."),
  list(".claude/skills/qvest-risk-style/SKILL.md", "risk_crowding_score_check hook 강제"),
  list(".claude/skills/qvest-alpha-style/SKILL.md", "(agent_role_guard Hook 차단)"),
  list(".claude/agents/alpha-research.md", "**🆕 Universe v2 옵션**"))
stale_hit <- function(doc_txt, s) has(doc_txt, s)
for (x in STALE) chk(sprintf("S6 %s — 낡은 문언 없음: %s", basename(dirname(x[[1]])), substr(x[[2]], 1, 30)), !stale_hit(rd(x[[1]]), x[[2]]))
chk("S6m 돌연변이 — 스킬에 낡은 문언 주입 → red", stale_hit(paste(SKL, STALE[[1]][[2]]), STALE[[1]][[2]]))
AR <- rd(".claude/agents/alpha-research.md")
chk("S6b alpha-research 구 유니버스 절에 현행 epoch 정정 표기", has(AR, "all_hyg_px1000_2000_v1") && has(AR, "(사료) Universe v2 옵션"))

## ── S7 검정력 문턱 키 실재 ────────────────────────────────────────────────
CD <- tryCatch(fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation, error = function(e) NULL)
chk("S7a tier_graduation 두 키 실재(2.0 · 2.95)", is.numeric(CD$grade_b_min_portfolio_alpha_t) && is.numeric(CD$min_portfolio_alpha_t_nw))
chk("S7b grade_v3 floors.port_t → grade_b_min_portfolio_alpha_t", identical(GV$floors$port_t, "tier_graduation.grade_b_min_portfolio_alpha_t"))
RE <- rd("02_Infrastructure/contracts/required_effect_size.R")
chk("S7c required_effect(n, t_threshold) 서명 실재 · 스킬이 두 키를 가리킨다",
    grepl("required_effect <- function(n, t_threshold", RE, fixed = TRUE) && has(SKL, "grade_b_min_portfolio_alpha_t") && has(SKL, "min_portfolio_alpha_t_nw"))

unlink(td, recursive = TRUE)
cat(sprintf('{"test":"scn_advisor_dryrun","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
