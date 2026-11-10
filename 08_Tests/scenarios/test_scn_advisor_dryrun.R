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
#   ★11-10 감사 U18 수리(A1_advisor) — 문자열 결합이 아니라 실제 러너 · 관문 · 워크플로 코드를 탄다:
#   S3 시행 회계 = 정본 A 자격 관문(rf_a_eligibility)을 러너 라우터(.rp_a_route)로 태워 chain/1 · sweep/2 판정을 잰다
#   S8 어드바이저 표지(measurement_tags$lane · strategy_name ADVISOR_(적대 재실행 ADV_… 는 아님) · 권위 기록 lane · 호출자 표지) → 관문 통과여도 held:advisor_lane ·
#      judge_request.eligible.json 없음 · 일반 레인(표지 없음)은 구판 그대로 발행(대조) · 표지 판별 진리표(러너 함수 = 라우터)
#   S9 §7-c 모듈 등재 블록(러너 소스에서 잘라 eval · 등재 함수는 대역) — 어드바이저 = 등재 호출 0 · 일반 = 호출 1
#   S10 권위 기록 표지 블록 — lane · measurement_regime.lane · module_admission(advisor_lane) · 일반 = 키 추가 0 · 러너 본문 배선 순서
#   S11 wt_create 동결 가드(QEPM-R0-FREEZE) — 거부 · 디렉터리 0 / 가드 줄 삭제 돌연변이 = WT 가 다시 생긴다(하네스 양성 대조)
#   S12 qvest-multi-track 워크플로 합성 실행(node) — QEPM_FROZEN · 에이전트 0 / 동결 블록 삭제 돌연변이 = alpha-research 스폰
#   S13 스킬 τ_D 절 — 규정 문언 + 스킬의 검사 한 줄을 실제로 돌려 τ_D 뒤 수치가 든 메모는 멈추고 깨끗한 메모는 통과
#   코드 원천 = QVEST_ADV_SRC_ROOT(선택 · 수리 전 트리 대조용 — 기본 = 이 저장소). 문서는 늘 이 저장소에서 읽는다.
suppressMessages({ library(jsonlite); library(data.table) })

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
## S1m — 같은 검출 파이프라인(ticks → path_like → resolve)에 가짜 경로를 넣은 스킬 사본을 통과시킨다(검출기 자체가 망가지면 red)
s1_miss <- function(txt) { ps <- unique(path_like(ticks(txt)))
  ps <- ps[!basename(ps) %in% GEN & !ps %in% FORBID_ONLY & !grepl("^stage_artifacts/|^04_Research/advisor/[^R]", ps, perl = TRUE)]
  ps[!vapply(ps, resolve, logical(1))] }
FAKE_P <- "02_Infrastructure/alpha_search/run_paper_replication_v0.R"
chk("S1m 돌연변이 — 스킬 사본에 없는 경로 주입 → 검출 파이프라인이 그 경로를 놓친 것으로 잡는다",
    !length(s1_miss(SKL)) && identical(s1_miss(paste0(SKL, "\n- 참조 `", FAKE_P, "`")), FAKE_P))
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
## (S3a 구판 = 시험 안에서 정의한 next_trial 의 출력만 봤다 — 공허 단언 · 11-10 감사 U18). 회계 판정은 아래 S8 이 정본 관문으로 잰다.
chk("S3b 스킬이 규칙 문언을 갖는다(1 + trials.jsonl 줄 수 · 둘째부터 sweep)", has(SKL, "1 + 이 계보에서 이미 측정한 칸 수(`trials.jsonl` 줄 수)") && has(SKL, "두 번째부터) = `\"sweep\"`"))
gate <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE), error = function(e) NULL)
req <- tryCatch(gate$codes$accounting_fail$replication_required_selection_type, error = function(e) NULL)
if (is.null(req)) req <- tryCatch({ x <- unlist(gate); unname(x[grepl("replication_required_selection_type$", names(x))])[1] }, error = function(e) NULL)
chk("S3c A 관문 설정 재도출 — 충실구현 회계 요건 = chain", identical(as.character(req), "chain"), as.character(req))
chk("S3d 스킬이 둘째 판(sweep) A 관문 구조 보류를 적었다(판정 자체는 S8e 가 정본 관문으로 잰다)", has(SKL, "A → Judge 경로가 구조적으로 닫혀 있다"))
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
## 검출 루프 = 문서 읽기 함수(rdf)를 받는 한 함수 — 실문서와 돌연변이 사본에 같은 루프를 태운다(구판 S6m = paste 동어반복 · 11-10 감사 U18)
stale_scan <- function(rdf) vapply(STALE, function(x) stale_hit(rdf(x[[1]]), x[[2]]), logical(1))
S6_REAL <- stale_scan(rd)
for (i in seq_along(STALE)) chk(sprintf("S6 %s — 낡은 문언 없음: %s", basename(dirname(STALE[[i]][[1]])), substr(STALE[[i]][[2]], 1, 30)), !S6_REAL[[i]])
S6_MUT <- stale_scan(function(p) if (identical(p, STALE[[2]][[1]])) paste(rd(p), STALE[[2]][[2]]) else rd(p))
chk("S6m 돌연변이 — 스킬 사본에 낡은 문언(2번 항목) 주입 → 같은 검출 루프가 그 항목만 red",
    !any(S6_REAL) && identical(which(S6_MUT), 2L))
AR <- rd(".claude/agents/alpha-research.md")
chk("S6b alpha-research 구 유니버스 절에 현행 epoch 정정 표기", has(AR, "all_hyg_px1000_2000_v1") && has(AR, "(사료) Universe v2 옵션"))

## ── S7 검정력 문턱 키 실재 ────────────────────────────────────────────────
CD <- tryCatch(fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation, error = function(e) NULL)
chk("S7a tier_graduation 두 키 실재(2.0 · 2.95)", is.numeric(CD$grade_b_min_portfolio_alpha_t) && is.numeric(CD$min_portfolio_alpha_t_nw))
chk("S7b grade_v3 floors.port_t → grade_b_min_portfolio_alpha_t", identical(GV$floors$port_t, "tier_graduation.grade_b_min_portfolio_alpha_t"))
RE <- rd("02_Infrastructure/contracts/required_effect_size.R")
chk("S7c required_effect(n, t_threshold) 서명 실재 · 스킬이 두 키를 가리킨다",
    grepl("required_effect <- function(n, t_threshold", RE, fixed = TRUE) && has(SKL, "grade_b_min_portfolio_alpha_t") && has(SKL, "min_portfolio_alpha_t_nw"))

## ═════════════ S8~S13 — 실제 러너 · 관문 · 워크플로 코드를 탄다 (11-10 감사 U18 수리) ═════════════
SRC <- gsub("\\\\", "/", Sys.getenv("QVEST_ADV_SRC_ROOT", ROOT))     # 코드 원천(수리 전 트리 대조용 · 기본 = 이 저장소)
cat(sprintf("  (코드 원천 = %s)\n", SRC))
rd_src <- function(p) { f <- file.path(SRC, p); if (!file.exists(f)) return(""); paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n") }
ENV_KEYS <- c("QM_ROOT", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_NO_LEDGER_OPEN", "RF_CELL_SPEC")
ENV0 <- Sys.getenv(ENV_KEYS, unset = NA_character_, names = TRUE)
env_restore <- function() for (k in ENV_KEYS) if (is.na(ENV0[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(ENV0[[k]]), k))
Sys.unsetenv(c("QVEST_CONSTRAINT_DEFAULTS", "QVEST_NO_LEDGER_OPEN", "RF_CELL_SPEC"))
WD0 <- getwd()

## ── 샌드박스 루트(관문 정본이 읽는 최소 파일만 사본 — test_replication_a_gate.R 와 같은 목록 · 관문 source 재도출) ──
SB <- file.path(tempdir(), sprintf("adv_gate_%d", Sys.getpid())); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE, showWarnings = FALSE)
NEED <- c("02_Infrastructure/reinforcement/rf_runner_gates.R", "02_Infrastructure/reinforcement/rf_spec_sig.R",
          "02_Infrastructure/reinforcement/rf_block_design.R", "02_Infrastructure/reinforcement/reinforce_ledger.R",
          "02_Infrastructure/contracts/essence_score.R", "02_Infrastructure/worktask/constraint_defaults.json",
          "06_Registry/a_eligibility_gate.json", "02_Infrastructure/reinforcement/rf_lineage_flags.R",
          "02_Infrastructure/reinforcement/rf_spec_axes.R")
NEED <- unique(c(NEED, tryCatch({
  .g <- readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), warn = FALSE, encoding = "UTF-8")
  unlist(regmatches(.g, gregexpr('(?<=source\\(file\\.path\\(\\.RFG_ROOT\\(\\), ")02_Infrastructure/[A-Za-z0-9_/]+[.]R', .g, perl = TRUE)))
}, error = function(e) character(0))))
sb_ok <- all(vapply(NEED, function(r) { dir.create(dirname(file.path(SB, r)), recursive = TRUE, showWarnings = FALSE)
  isTRUE(file.copy(file.path(ROOT, r), file.path(SB, r), overwrite = TRUE)) }, logical(1)))
chk("S8_0 관문 샌드박스 사본(tempdir · 운영 트리 쓰기 0)", sb_ok && !startsWith(tolower(SB), tolower(paste0(ROOT, "/"))))

## ── 러너 정의 · 블록을 parse 로 떼어 낸다(러너 통째 source 없음 — 데이터 적재 · 텔레그램 없음) ──
RUNNER_REL <- "02_Infrastructure/alpha_search/run_paper_replication.R"
RP_TXT <- rd_src(RUNNER_REL)
WANT <- c(".RP_JR_LEGACY", ".RP_JR_ELIGIBLE", ".RP_JR_HELD", ".rp_is_cell_run", ".rp_gate_env", ".rp_a_gate_inputs",
          ".rp_gate_err_verdict", ".rp_a_route", ".rp_is_advisor_lane", ".RP_ADVISOR_PREFIX")
find_a11 <- function(ex) {
  fdef <- NULL
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("run_paper_replication"))) fdef <- e[[3]]
  if (is.null(fdef)) return(NULL)
  walk <- function(x) { if (!is.call(x)) return(NULL)
    if (identical(x[[1]], as.name("if")) && identical(deparse(x[[2]]), 'identical(grade, "A")')) return(x)
    for (i in seq_along(x)) { if (is.symbol(x[[i]]) && !nzchar(as.character(x[[i]]))) next
      r <- walk(x[[i]]); if (!is.null(r)) return(r) }
    NULL }
  walk(fdef[[3]])
}
load_defs <- function(txt) {
  ex <- tryCatch(parse(text = txt, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(ex)) return(list(env = NULL, a11 = NULL))
  env <- new.env(parent = globalenv())
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% WANT) eval(e, envir = env)
  list(env = env, a11 = find_a11(ex))
}
take_expr <- function(lines, i0, maxlen = 200L) {     # i0 줄부터 처음으로 parse 되는 최소 구간(test_module_admission_seam.R 와 같은 방식)
  for (j in i0:min(length(lines), i0 + maxlen)) {
    e <- tryCatch(parse(text = paste(lines[i0:j], collapse = "\n"), keep.source = FALSE), error = function(e) NULL)
    if (!is.null(e) && length(e) >= 1L) return(e) }
  NULL
}
RPD <- load_defs(RP_TXT)
R <- RPD$env
chk("S8_1 러너 라우터 · 관문 적재 정의 실재(.rp_a_route · .rp_gate_env · .rp_a_gate_inputs) · §11 A 분기 추출",
    is.environment(R) && all(c(".rp_a_route", ".rp_gate_env", ".rp_a_gate_inputs") %in% ls(R, all.names = TRUE)) && !is.null(RPD$a11))
GXL <- if (is.environment(R)) tryCatch(R$.rp_gate_env(SB), error = function(e) list(env = NULL, err = conditionMessage(e))) else list(env = NULL, err = "정의 없음")
GX <- GXL$env
chk("S8_2 관문 정본 격리 적재(rf_a_eligibility)", is.environment(GX) && is.function(GX$rf_a_eligibility), GXL$err)
CFGD <- tryCatch(fromJSON(file.path(SB, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = TRUE), error = function(e) NULL)
CUR <- tryCatch(GX$rf_current_regime(SB)$regime, error = function(e) NA_character_)
ANCHOR <- tryCatch(as.Date(CFGD[["diagnostics"]][["window_anchor_date"]]), error = function(e) as.Date(NA))
PAPER_ENGINE <- file.path(SB, "paper_engine", "engine.R"); dir.create(dirname(PAPER_ENGINE), recursive = TRUE, showWarnings = FALSE)
writeLines("FACTORS <- NULL", PAPER_ENGINE)
## 합성 권위 산출물(러너가 쓰는 모양 — authoritative_remeasure.json + bt_result.rds). lane/sname/top_lane = 표지 주입점
mk_art <- function(tag, sel = "chain", nt = 1L, lane = NULL, sname = paste0("RP_T_", tag), top_lane = NULL) {
  d <- file.path(SB, "stage_artifacts", "replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  mr <- list(selection_type = sel, n_trials_cumulative = nt, exec_price = CUR, exec_price_basis = "argument", cost_model_version = "synthetic")
  if (!is.null(lane)) mr$lane <- lane
  au <- list(status = "OK", strategy_id = paste0("RP_T_", tag), strategy_name = sname, essence_grade = "A", metric_type = "backtested",
             selection_type = sel, n_trials_cumulative = nt, dsr = NULL, essence = list(dsr = NULL, cagr = 0.2, calmar = 0.9),
             measurement_regime = mr)
  if (!is.null(top_lane)) au$lane <- top_lane
  write(toJSON(au, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(d, "authoritative_remeasure.json"))
  dates <- seq(ANCHOR, by = "month", length.out = 24L)
  saveRDS(list(holdings = data.table(date = dates, ticker = "A000001", weight = 1),
               period_returns = data.table(date = dates, ret_net = rep(0.01, 24L))), file.path(d, "bt_result.rds"))
  d
}
files_of <- function(d) sort(list.files(d, pattern = "^judge_request"))
jr <- function(d, nm) { p <- file.path(d, nm); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
route <- function(d, advisor = NULL) {
  a <- list(d, grade = "A", strategy_id = basename(d), engine_path = PAPER_ENGINE, cell = FALSE,
            gate = GX$rf_a_eligibility, gx = GX, root = SB, gate_err = "")
  if (!is.null(advisor)) a$advisor <- advisor
  tryCatch(do.call(R$.rp_a_route, a), error = function(e) list(action = paste("error:", conditionMessage(e))))
}
adv_held <- function(d, a, gate_pass = TRUE) {     # 어드바이저 보류의 모양 — 보류 파일만 · advisor_lane · lane/requires/gate_eligible
  j <- jr(d, "judge_request.held.json")
  identical(files_of(d), "judge_request.held.json") && identical(a$action, "hold") && !is.null(j) &&
    "advisor_lane" %in% unlist(j$a_eligibility$codes) && "advisor_lane" %in% unlist(j$held$codes) &&
    identical(j$a_eligibility$lane, "advisor") && identical(j$lane, "advisor") && identical(j$requires, "dohoon_instruction") &&
    identical(isTRUE(j$gate_eligible), gate_pass) && nzchar(as.character(j$a_eligibility$detail$advisor_lane %||% "")) &&
    startsWith(as.character(j$status), "held:") && grepl("advisor_lane", j$status, fixed = TRUE)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
if (is.environment(R) && is.environment(GX) && !is.na(CUR) && !is.na(ANCHOR)) {
  ## S8a 대조 — 일반 충실구현(표지 없음) chain/1 → judge_request.eligible.json(lane replication) · 구판 동작 그대로
  d <- mk_art("s8a_plain"); s0 <- unname(tools::md5sum(file.path(d, "authoritative_remeasure.json"))); a <- route(d); j <- jr(d, "judge_request.eligible.json")
  chk("S8a 대조: 일반 충실구현 chain/1 → eligible 만 · status pending · lane replication · 어드바이저 키 없음",
      identical(files_of(d), "judge_request.eligible.json") && identical(a$action, "publish") && identical(j$status, "pending") &&
        identical(j$a_eligibility$lane, "replication") && is.null(j$lane) && is.null(j$requires), paste(files_of(d), a$action))
  chk("S8a 권위 산출물 바이트 불변(등급 불변)", identical(unname(tools::md5sum(file.path(d, "authoritative_remeasure.json"))), s0))
  ## S8b 어드바이저 표지(measurement_regime.lane = advisor) chain/1 — 관문은 통과하지만 발행 없음
  d <- mk_art("s8b_tag", lane = "advisor"); a <- route(d)
  chk("S8b 어드바이저(measurement_tags$lane) · 관문 통과 → held:advisor_lane 만 · eligible 없음 · gate_eligible TRUE · requires dohoon_instruction",
      adv_held(d, a, TRUE) && identical(unlist(jr(d, "judge_request.held.json")$a_eligibility$codes), "advisor_lane"), paste(files_of(d), a$action))
  d <- mk_art("s8c_name", sname = "ADVISOR_toy-lowvol_1"); a <- route(d)
  chk("S8c 어드바이저(strategy_name 접두 ADVISOR_ · 태그 없음) → held:advisor_lane(표지 하나만 있어도 · fail-closed)", adv_held(d, a, TRUE), paste(files_of(d), a$action))
  d <- mk_art("s8d_top", top_lane = "advisor"); a <- route(d)
  chk("S8d 어드바이저(권위 기록 lane = advisor) → held:advisor_lane", adv_held(d, a, TRUE), paste(files_of(d), a$action))
  ## S8e 시행 회계 — 어드바이저 둘째 판(sweep/2) → 관문 자체가 accounting_fail 보류 + advisor_lane(구판 S3d 의 공허 단언 대체)
  d <- mk_art("s8e_sweep", sel = "sweep", nt = 2L, lane = "advisor"); a <- route(d); j <- jr(d, "judge_request.held.json")
  chk("S8e 어드바이저 sweep/2 → held(accounting_fail + advisor_lane) · gate_eligible FALSE",
      adv_held(d, a, FALSE) && all(c("accounting_fail", "advisor_lane") %in% unlist(j$a_eligibility$codes)), paste(unlist(j$a_eligibility$codes), collapse = "+"))
  d <- mk_art("s8f_plain_sweep", sel = "sweep", nt = 2L); a <- route(d); j <- jr(d, "judge_request.held.json")
  chk("S8f 대조: 일반 sweep/2 → held:accounting_fail · advisor_lane 없음 · lane replication",
      identical(files_of(d), "judge_request.held.json") && "accounting_fail" %in% unlist(j$a_eligibility$codes) &&
        !("advisor_lane" %in% unlist(j$a_eligibility$codes)) && identical(j$a_eligibility$lane, "replication"))
  ## S8g 호출자 표지(§11 이 넘기는 advisor = TRUE · 권위 기록에 표지 없음) → held:advisor_lane
  d <- mk_art("s8g_flag"); a <- route(d, advisor = TRUE)
  chk("S8g 호출자 표지(advisor = TRUE · 권위 기록 표지 없음) → held:advisor_lane", adv_held(d, a, TRUE), paste(files_of(d), a$action))
  ## S8h §11 실블록 — 러너 함수 본문에서 떼어 eval · 표지 변수 .rp_adv_lane 이 TRUE/FALSE 일 때
  run_a11 <- function(d, adv) { E <- new.env(parent = R); E$grade <- "A"; E$OUT_DIR <- d; E$strategy_id <- basename(d)
    E$factor_engine_path <- PAPER_ENGINE; E$PROJECT_ROOT <- SB; E$a_gate <- NULL; E$.rp_adv_lane <- adv
    tryCatch({ invisible(capture.output(eval(RPD$a11, envir = E))); E$a_gate }, error = function(e) list(action = paste("error:", conditionMessage(e)))) }
  d1 <- mk_art("s8h_adv"); a1 <- run_a11(d1, TRUE); d2 <- mk_art("s8h_plain"); a2 <- run_a11(d2, FALSE)
  chk("S8h §11 실블록 — .rp_adv_lane TRUE → held:advisor_lane · FALSE → eligible(같은 산출물 모양)",
      adv_held(d1, a1, TRUE) && identical(files_of(d2), "judge_request.eligible.json"), paste(a1$action, a2$action))
  ## S8i 표지 판별 진리표 — 러너 함수(.rp_is_advisor_lane) = 라우터 판정(권위 기록 재판독)
  ## ★적대 재실행 이름(11-10 재검증) — rf_overlay_adversary.R 의 이름 서식을 소스에서 떼어 실제 모양의 이름을 만든다(사본 문자열 아님).
  ##   그 이름은 셀 워커를 거쳐 strategy_name 으로 러너에 들어온다 — 어드바이저 표지로 잡히면 비어드바이저 권위 기록에 lane = advisor 가 적힌다.
  ADV_FMT <- local({ t <- rd_src("02_Infrastructure/reinforcement/rf_overlay_adversary.R")
    m <- regmatches(t, regexpr('name <- sprintf\\("[^"]+"', t, perl = TRUE)); if (length(m)) sub('^name <- sprintf\\("', "", sub('"$', "", m)) else "" })
  ADVERSARY_NM <- if (nzchar(ADV_FMT)) tryCatch(sprintf(ADV_FMT, "lag1", "OV01", "RP_20260831_204546"), error = function(e) "") else ""
  chk("S8i_0 적대 재실행 이름 서식을 rf_overlay_adversary.R 에서 떼어 냈다(이름 = ADV_… 모양)",
      nzchar(ADVERSARY_NM) && startsWith(ADVERSARY_NM, "ADV_"), paste0("fmt=", ADV_FMT, " nm=", ADVERSARY_NM))
  TT <- list(list(tags = list(lane = "advisor"), nm = "RP_x", want = TRUE), list(tags = NULL, nm = "ADVISOR_x_1", want = TRUE),
             list(tags = list(lane = " Advisor "), nm = "RP_x", want = TRUE), list(tags = list(lane = "replication"), nm = "RP_x", want = FALSE),
             list(tags = NULL, nm = "RP_ADVISOR_x", want = FALSE), list(tags = list(n_trials_basis = "advisor_lineage:x:1"), nm = "x", want = FALSE),
             list(tags = NULL, nm = "ADV_x_1", want = FALSE),
             list(tags = NULL, nm = if (nzchar(ADVERSARY_NM)) ADVERSARY_NM else "ADV_lag1_OV01_RP_x", want = FALSE),
             list(tags = NULL, nm = "ADV_T1_B5_16_RP_20260831_204546_skipped_base", want = FALSE))   # 원장 L1 실재 이름 모양
  tt_fn <- function(f) is.function(f) && all(vapply(TT, function(t) identical(f(t$tags, t$nm), t$want), logical(1)))
  fn_ok <- tt_fn(R$.rp_is_advisor_lane)
  rt_ok <- all(vapply(seq_along(TT), function(i) { t <- TT[[i]]
    d <- mk_art(sprintf("s8i_%d", i), lane = t$tags$lane, sname = t$nm); a <- route(d)
    identical(identical(a$action, "hold"), t$want) }, logical(1)))
  chk(sprintf("S8i 표지 판별 진리표 %d행 — 러너 함수 .rp_is_advisor_lane 과 라우터 판정이 같다(lane 대소문자 · 공백 · ADVISOR_ 는 접두만 · 적대 재실행 ADV_… 는 어드바이저 아님)", length(TT)),
      fn_ok && rt_ok, sprintf("함수=%s 라우터=%s", fn_ok, rt_ok))
  chk("S8i' 접두 상수 .RP_ADVISOR_PREFIX = 라우터 글자 그대로 접두(\"ADVISOR_\") · 적대 재실행 접두 ADV_ 와 겹치지 않는다",
      identical(R$.RP_ADVISOR_PREFIX, "ADVISOR_") && grepl('startsWith(adv_nm, "ADVISOR_")', RP_TXT, fixed = TRUE) &&
        nzchar(ADVERSARY_NM) && !startsWith(ADVERSARY_NM, R$.RP_ADVISOR_PREFIX %||% "ADVISOR_"))
  ## 돌연변이(소스 텍스트 치환 · 성사 단정) — 접두를 구판 "ADV_" 로 되돌리면 적대 재실행 행이 어드바이저로 잡힌다(red)
  MUT_TXT <- sub('.RP_ADVISOR_PREFIX <- "ADVISOR_"', '.RP_ADVISOR_PREFIX <- "ADV_"', RP_TXT, fixed = TRUE)
  MUT_TXT <- sub('startsWith(adv_nm, "ADVISOR_")', 'startsWith(adv_nm, "ADV_")', MUT_TXT, fixed = TRUE)
  mut_made <- !identical(MUT_TXT, RP_TXT) && grepl('.RP_ADVISOR_PREFIX <- "ADV_"', MUT_TXT, fixed = TRUE) &&
    grepl('startsWith(adv_nm, "ADV_")', MUT_TXT, fixed = TRUE)
  RM <- if (mut_made) load_defs(MUT_TXT)$env else NULL
  mut_fn_red <- is.environment(RM) && isTRUE(RM$.rp_is_advisor_lane(NULL, ADVERSARY_NM))
  mut_rt_red <- is.environment(RM) && local({ d <- mk_art("s8i_mut", sname = ADVERSARY_NM)
    a <- tryCatch(RM$.rp_a_route(d, grade = "A", strategy_id = basename(d), engine_path = PAPER_ENGINE, cell = FALSE,
                                 gate = GX$rf_a_eligibility, gx = GX, root = SB), error = function(e) list(action = "error"))
    identical(a$action, "hold") && "judge_request.held.json" %in% files_of(d) })
  chk("S8im 돌연변이(접두 → ADV_ · 치환 2곳 성사) → 적대 재실행 이름이 함수 · 라우터 모두에서 어드바이저로 잡힌다(진리표가 그 결함을 본다)",
      mut_made && mut_fn_red && mut_rt_red && !tt_fn(RM$.rp_is_advisor_lane), sprintf("치환=%s 함수=%s 라우터=%s", mut_made, mut_fn_red, mut_rt_red))
} else ng("S8 관문 샌드박스 준비 실패 — 이하 S8 생략", sprintf("R=%s GX=%s CUR=%s", is.environment(R), is.environment(GX), CUR))

## ── S9 §7-c 모듈 등재 블록 — 러너 소스에서 잘라 eval(등재 함수 = 대역 · 호출 표식 파일) ──
RL <- strsplit(RP_TXT, "\n", fixed = TRUE)[[1]]
i_reg <- grep("QVEST_RP_REGISTER", RL, fixed = TRUE); i_reg <- i_reg[grepl("if (", RL[i_reg], fixed = TRUE)]
REG_BLK <- if (length(i_reg)) take_expr(RL, i_reg[1]) else NULL
STUB <- file.path(tempdir(), sprintf("adv_rmm_%d", Sys.getpid())); dir.create(file.path(STUB, "contracts"), recursive = TRUE, showWarnings = FALSE)
MARK <- gsub("\\\\", "/", file.path(STUB, "called.txt"))   # R 코드 문자열에 들어간다 — 역슬래시(\U) 금지
writeLines(c(sprintf('rmm_register_measured <- function(...) { cat("called\\n", file = "%s", append = TRUE); list(registered = TRUE, code = "stub") }', MARK)),
           file.path(STUB, "contracts", "register_measured_module.R"))
run_reg <- function(adv) {
  unlink(MARK); sb <- new.env(parent = globalenv())
  sb$.RP_INFRA <- STUB; sb$OUT_DIR <- td; sb$sim_grade <- NULL; sb$strategy_idea <- "toy"; sb$strategy_name <- "ADVISOR_toy_1"
  sb$.sp_url <- "http://x"; sb$source_paper <- list(paper_key = "toy"); sb$portfolio_spec <- list(construction = "top_n_long")
  sb$weights_engine_direct <- FALSE; sb$`%||%` <- `%||%`; if (!is.null(adv)) sb$.rp_adv_lane <- adv
  err <- tryCatch({ invisible(capture.output(eval(REG_BLK[[1]], envir = sb))); "" }, error = function(e) conditionMessage(e))
  list(err = err, called = file.exists(MARK))
}
if (is.null(REG_BLK)) ng("S9 등재 블록(앵커 QVEST_RP_REGISTER) 부재 — 검사 드리프트") else {
  r_adv <- run_reg(TRUE); r_pl <- run_reg(FALSE); r_na <- run_reg(NULL)
  chk("S9a 어드바이저(.rp_adv_lane TRUE) → 등재 함수 호출 0(module_catalog 자동 등재 없음)", !nzchar(r_adv$err) && !r_adv$called, r_adv$err)
  chk("S9b 대조: 일반(.rp_adv_lane FALSE) → 등재 함수 호출 1(일반 레인 등재 불변)", !nzchar(r_pl$err) && r_pl$called, r_pl$err)
  chk("S9c 대조: 표지 변수 없는 샌드박스(test_module_admission_seam C6 모양) → 등재 호출(그 검사의 블록 eval 이 깨지지 않는다)", !nzchar(r_na$err) && r_na$called, r_na$err)
}
pos <- function(s) { m <- regexpr(s, RP_TXT, fixed = TRUE); as.integer(m) }
p_def <- pos(".rp_adv_lane <- .rp_is_advisor_lane(measurement_tags, strategy_name)")
p_auth <- pos("if (isTRUE(.rp_adv_lane)) {"); p_reg <- pos("QVEST_RP_REGISTER\", \"1\"), \"0\") && !isTRUE(get0(\".rp_adv_lane\"")
p_a11 <- pos("advisor = isTRUE(get0(\".rp_adv_lane\", ifnotfound = FALSE))")
chk("S9d 러너 본문 배선 — 표지 정의(measurement_tags · strategy_name) → 권위 기록 표지 → §7-c 등재 조건 → §11 라우터 인자 순서",
    all(c(p_def, p_auth, p_reg, p_a11) > 0L) && p_def < p_auth && p_auth < p_reg && p_reg < p_a11, paste(p_def, p_auth, p_reg, p_a11))

## ── S10 권위 기록 표지 블록 — 러너 소스에서 잘라 eval ──
i_au <- grep("if (isTRUE(.rp_adv_lane)) {", RL, fixed = TRUE)
AU_BLK <- if (length(i_au)) take_expr(RL, i_au[1]) else NULL
if (is.null(AU_BLK)) ng("S10 권위 기록 표지 블록(if (isTRUE(.rp_adv_lane)) {) 부재") else {
  run_au <- function(adv) { sb <- new.env(parent = globalenv()); sb$.rp_adv_lane <- adv
    sb$auth <- list(status = "OK", measurement_regime = list(selection_type = "chain", lane = "advisor_typo")); eval(AU_BLK[[1]], envir = sb); sb$auth }
  a1 <- run_au(TRUE); a0 <- run_au(FALSE)
  chk("S10a 어드바이저 → 권위 기록 lane = advisor · measurement_regime.lane = advisor · module_admission = advisor_lane(미등재)",
      identical(a1$lane, "advisor") && identical(a1$measurement_regime$lane, "advisor") && identical(a1$module_admission$code, "advisor_lane") &&
        identical(a1$module_admission$registered, FALSE))
  chk("S10b 대조: 일반 → 권위 기록 키 추가 0(구판 그대로)",
      identical(a0, list(status = "OK", measurement_regime = list(selection_type = "chain", lane = "advisor_typo"))))
}

## ── S11 wt_create 동결 가드 — 정의만 떼어 임시 루트에서 부른다(쓰기 = tempdir) ──
WM_TXT <- rd_src("02_Infrastructure/worktask/worktask_manager.R")
WTR <- file.path(tempdir(), sprintf("adv_wt_%d", Sys.getpid())); unlink(WTR, recursive = TRUE)
dir.create(file.path(WTR, "02_Infrastructure/worktask"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(WTR, "02_Infrastructure/worktask/constraint_defaults.json")))
run_wt <- function(txt) {
  ex <- tryCatch(parse(text = txt, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(ex)) return(list(err = "parse 실패", dirs = character(0)))
  env <- new.env(parent = globalenv())
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
                    as.character(e[[2]]) %in% c("WT_ROOT", "WT_SCHEMA", "WT_CONSTRAINT_DEFAULTS", "wt_generate_id", "wt_create")) eval(e, envir = env)
  if (!is.function(env$wt_create)) return(list(err = "wt_create 정의 없음", dirs = character(0)))
  unlink(file.path(WTR, c("qepm", "stage_artifacts")), recursive = TRUE)
  setwd(WTR); on.exit(setwd(WD0), add = TRUE)
  err <- tryCatch({ invisible(capture.output(suppressWarnings(env$wt_create(hypothesis_title = "toy", wt_type = "discovery")))); "" },
                  error = function(e) conditionMessage(e))
  list(err = err, dirs = c(list.files(file.path(WTR, "qepm/mailbox/worktask")), list.files(file.path(WTR, "stage_artifacts"))))
}
w0 <- run_wt(WM_TXT)
chk("S11a wt_create → QEPM 동결(QEPM-R0-FREEZE) 거부 · 해제 = 재상정 · WT 디렉터리 0",
    grepl("QEPM 동결(QEPM-R0-FREEZE)", w0$err, fixed = TRUE) && grepl("재상정", w0$err, fixed = TRUE) && !length(w0$dirs), paste(w0$err, paste(w0$dirs, collapse = ",")))
WM_L <- strsplit(WM_TXT, "\n", fixed = TRUE)[[1]]
gi <- grep('stop("[wt_create] QEPM 동결(QEPM-R0-FREEZE)', WM_L, fixed = TRUE)
if (length(gi) != 1L) ng("S11m 돌연변이 대상(가드 줄) 부재/중복 — 검사 드리프트", as.character(length(gi))) else {
  w1 <- run_wt(paste(WM_L[-gi], collapse = "\n"))
  chk("S11m 돌연변이(가드 줄 삭제) → WT 디렉터리가 다시 생긴다(하네스가 생성을 본다 = 양성 대조)", length(w1$dirs) >= 1L, paste(w1$err, length(w1$dirs)))
}
chk("S11b 우회 스위치 없음 — wt_create 가드 줄 주변에 Sys.getenv 조건이 없다",
    length(gi) == 1L && !any(grepl("Sys.getenv", WM_L[max(1L, gi - 4L):gi], fixed = TRUE)))

## ── S12 qvest-multi-track 워크플로 합성 실행(node · agent/phase/log 모의) ──
MT_SRC <- file.path(SRC, ".claude/workflows/qvest-multi-track.js")
node <- Sys.which("node"); if (!nzchar(node) && file.exists("C:/Program Files/nodejs/node.exe")) node <- "C:/Program Files/nodejs/node.exe"
if (!nzchar(node) || !file.exists(node)) ng("S12 node 실행기 없음 — 워크플로 합성 실행 미측정") else {
  HARN <- file.path(td, "wf_harness.mjs")
  writeLines(c(
    "import { readFileSync } from 'node:fs'",
    "let src = readFileSync(process.argv[2], 'utf8')",
    "src = src.replace(/^export\\s+const\\s+meta\\s*=/m, 'const meta = __box.meta =')",
    "const calls = [], logs = []",
    "const agent = async (prompt, opts) => { calls.push((opts && opts.agentType) || '?'); return { tag: 't1', icir: 1, dsr: 0.5, net_sr: 1, verdict: 'PASS' } }",
    "const phase = () => {}",
    "const log = (m) => { logs.push(String(m)) }",
    "const parallel = async (fns) => Promise.all(fns.map((f) => f()))",
    "const args = { wt_id: 'WT-D20990101_001', tracks: [{ tag: 't1', prompt: 'p' }, { tag: 't2', prompt: 'q' }] }",
    "const __box = {}",
    "const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor",
    "let result = null, error = null",
    "try { const fn = new AsyncFunction('args', 'agent', 'phase', 'log', 'parallel', '__box', src)",
    "      result = await fn(args, agent, phase, log, parallel, __box) } catch (e) { error = String(e && e.message || e) }",
    "process.stdout.write(JSON.stringify({ result, error, calls, logs }))"), HARN)
  run_wf <- function(js) { out <- tryCatch(suppressWarnings(system2(node, c(shQuote(HARN), shQuote(js)), stdout = TRUE, stderr = TRUE)), error = function(e) "")
    tryCatch(fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE), error = function(e) list(error = paste(out, collapse = " "))) }
  r0 <- run_wf(MT_SRC)
  chk("S12a multi-track 실행 → QEPM_FROZEN 반환 · alpha-research 스폰 0 · 로그에 동결 · 재상정",
      is.null(r0$error) && identical(r0$result$status, "QEPM_FROZEN") && !length(r0$calls) &&
        any(grepl("QEPM 동결(QEPM-R0-FREEZE)", r0$logs, fixed = TRUE)) && any(grepl("재상정", r0$logs, fixed = TRUE)),
      paste(r0$error, paste(r0$calls, collapse = ",")))
  ML <- readLines(MT_SRC, warn = FALSE, encoding = "UTF-8")
  ri <- grep("^return \\{ wt_id: wt, status: 'QEPM_FROZEN'", ML, perl = TRUE)
  if (length(ri) != 1L || !grepl("^  note:", ML[ri + 1L])) ng("S12m 돌연변이 대상(동결 return 블록) 부재 — 검사 드리프트") else {
    f1 <- file.path(td, "mt_mut.js"); writeLines(ML[-c(ri, ri + 1L)], f1, useBytes = TRUE)
    r1 <- run_wf(f1)
    chk("S12m 돌연변이(동결 return 삭제) → alpha-research 2건 스폰 · ICIR 순위 반환(하네스가 스폰을 본다)",
        is.null(r1$error) && sum(r1$calls == "alpha-research") == 2L && length(r1$result$ranking_by_icir$tag) == 2L,
        paste(r1$error, paste(r1$calls, collapse = ",")))
  }
}

## ── S13 스킬 τ_D 절 — 규정 문언 + 검사 한 줄을 실제로 돌린다 ──
tau_sec <- local({ L <- strsplit(SKL, "\n", fixed = TRUE)[[1]]; s <- grep("^## 정보 경계 τ_D", L, perl = TRUE)
  if (length(s) != 1L) return("")
  e <- s + which(grepl("^## ", L[(s + 1L):length(L)], perl = TRUE))[1]; if (is.na(e)) e <- length(L) + 1L
  paste(L[s:(e - 1L)], collapse = "\n") })
tau_rules_ok <- function(t) has(t, "06_Registry/behavior_card.json::tau_d") && has(t, ".claude/rules/pit.md") &&
  has(t, "`selection_type = \"sweep\"`") && has(t, "`\"chain\"` 금지") && has(t, "앞 판을 모두 포함") &&
  has(t, "rc_input_issues") && has(t, "`ok = TRUE` 일 때만 넘긴다") && has(t, "자동 등재되지 않는다")
chk("S13a 스킬 τ_D 절 — 볼 수 있음(사람 쪽) · 본 뒤 고친 판 = sweep(chain 금지 · N 포함) · 이관 = 검사기 통과 사본 · 풀 자동 등재 없음",
    nzchar(tau_sec) && tau_rules_ok(tau_sec))
chk("S13a' 돌연변이 — 'chain 금지' 문언 삭제 → red", !tau_rules_ok(sub("`\"chain\"` 금지", "", tau_sec, fixed = TRUE)))
snip <- local({ L <- strsplit(tau_sec, "\n", fixed = TRUE)[[1]]; s <- grep("^```\\s*$", L, perl = TRUE)
  if (length(s) < 2L) "" else paste(L[(s[1] + 1L):(s[2] - 1L)], collapse = "\n") })
run_snip <- function(code, memo_lines) {
  dd <- file.path(td, "snip"); dir.create(dd, showWarnings = FALSE); writeLines(memo_lines, file.path(dd, "memo_for_queue.md"), useBytes = TRUE)
  abs_root <- if (grepl("^([A-Za-z]:)?/", gsub("\\\\", "/", ROOT))) ROOT else file.path(WD0, ROOT)   # 스킬 줄은 QM_ROOT 절대 경로를 쓴다(setwd 뒤)
  old <- Sys.getenv("QM_ROOT", NA_character_); Sys.setenv(QM_ROOT = abs_root); setwd(dd)
  on.exit({ setwd(WD0); if (is.na(old)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old) }, add = TRUE)
  r <- tryCatch({ eval(parse(text = code, encoding = "UTF-8"), envir = new.env(parent = globalenv())); "pass" },
                error = function(e) structure("stop", why = conditionMessage(e)))
  if (identical(as.character(r), "stop")) {
    cat("       (검사 줄 멈춤:", substr(attr(r, "why"), 1, 160), ")\n")
    if (!grepl("isTRUE(ci$ok)", attr(r, "why"), fixed = TRUE)) return("error")   # 검사 판정이 아닌 실행 오류는 '멈춤'으로 세지 않는다
  }
  as.character(r)
}
LEAK <- c("# 메모", "2024년 시험 창 CAGR 21.3% · Grade A — 2023년 급락 방어가 좋았다")
CLEAN <- c("# 메모", "가설: 저변동 상위 25종 · 2015~2022 표본에서 하락월 초과수익 · 반증 = 하락 포착 개선 없음")
chk("S13b 스킬 검사 한 줄 실행 — τ_D 뒤 연도 · 수치 · 등급이 든 메모 → 멈춘다(이관 안 함)", nzchar(snip) && identical(run_snip(snip, LEAK), "stop"))
chk("S13c 대조: τ_D 이전 정보만 든 메모 → 통과", nzchar(snip) && identical(run_snip(snip, CLEAN), "pass"))
chk("S13m 돌연변이 — 검사 줄에서 stopifnot 제거 → 새는 메모도 통과(red)",
    nzchar(snip) && identical(run_snip(sub("stopifnot(isTRUE(ci$ok))", "invisible(ci)", snip, fixed = TRUE), LEAK), "pass"))

setwd(WD0); env_restore()
unlink(c(SB, STUB, WTR), recursive = TRUE)
unlink(td, recursive = TRUE)
cat(sprintf('{"test":"scn_advisor_dryrun","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
