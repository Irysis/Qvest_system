# test_qepm_freeze_residual.R — QEPM 동결 잔여 수리(2026-09-25 · 결정 QEPM-R0-FREEZE / QEPM-ADVISOR-MODE)의 양방향 검사
#
# 근거: 동결 워크플로 wf_c04d114b-aa3 잔여 목록 — ① Judge 트리거 문서 모순(judge.md 스폰 조건 안에서 "충실구현 A 도 스폰"과
#   "충실구현 산출물 judge_request.json 은 트리거가 아니다"가 함께 있었고, lean-loop·alpha-search 3종·judge_init 은 산출물
#   judge_request.json 을 트리거로 적었다) ② 표지 없는 휴면 진입로(kr-inverse /worktask create · factor-db-discovery dossier ·
#   state_transitions JUDGE_* 허용 목록).
#
#   T. 트리거 사실을 **발행 코드에서 재도출**해 문서와 대조한다(문서 문구를 정답으로 쓰지 않는다):
#      강화 = reinforce_auto_parallel.R 의 후보별 요청 파일명·status · 2계층 = rf_l2_auto.R · 충실구현 = run_paper_replication.R §11
#      이 관문(rf_a_eligibility·grade_a_queue)을 거치는가. ★충실구현이 관문을 거치게 바뀌면(B07) '관문 전 파일' 문서가 red 가 된다.
#      ★P0-13(2026-09-25) 이관 완료 — §11 이 A 면 관문 정본(rf_a_eligibility)을 충실구현 어댑터로 태운다(통과 judge_request.eligible.json ·
#      보류 judge_request.held.json · 강화 셀 = 구판 judge_request.json). 대조는 양방향 그대로다: 관문 경유 판정은 **주석을 뺀 코드**에서
#      재도출하고(주석 속 함수명은 증거가 아니다), 파일 이름은 러너 상수(.RP_JR_*)에서 parse 로 읽어 문서 줄과 맞춘다 — 코드를 되돌리면
#      (관문 우회 · M2c 실코드 돌연변이) 현 문서가 red, 구 문서(관문 없음 · B07)를 재주입하면 현 코드에서 red.
#   D. 휴면 진입로 표지 + state_transitions 의 JUDGE_* 허용 목록이 남아 있으면 동결 주석과 실재 가드(state_machine.R)가 함께 있어야 한다.
#   M. 돌연변이 — 구 문언 재주입 · 코드 관문 가상 이관 · 주석 삭제 사본에서 각 검사기가 red 를 내는가.
#
# 쓰기 0: 운영 파일은 읽기만 한다. 돌연변이는 전부 메모리 안 문자열이다.
# 실행: Rscript 08_Tests/worktask/test_qepm_freeze_residual.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure", "config.R")))
  ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

P <- 0L; F <- 0L; S <- 0L; SKIPS <- character(0)
ok   <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng   <- function(m, d = "") { d <- paste(as.character(d), collapse = " "); F <<- F + 1L
  cat(sprintf("  NG   %s%s\n", m, if (length(d) && nzchar(d)) paste0(" — ", d) else "")) }
chk  <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
skip <- function(m) { S <<- S + 1L; SKIPS <<- c(SKIPS, m); cat(sprintf("  SKIP %s\n", m)) }
rd   <- function(rel) paste(readLines(file.path(ROOT, rel), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
rl   <- function(rel) readLines(file.path(ROOT, rel), warn = FALSE, encoding = "UTF-8")
has  <- function(txt, s) grepl(s, txt, fixed = TRUE)
all_has <- function(txt, keys) all(vapply(keys, function(k) has(txt, k), logical(1)))
missing_of <- function(txt, keys) paste(keys[!vapply(keys, function(k) has(txt, k), logical(1))], collapse = " | ")
# perl=TRUE 필수(r-portability 금칙 ⑥ — TRE 색인은 non-BMP 앞에서 추출 창이 밀린다)
first_match <- function(txt, pat) { m <- regmatches(txt, regexpr(pat, txt, perl = TRUE)); if (length(m)) m else "" }

# ═════════════════════════════ T0. 발행 코드에서 트리거 사실 재도출 ═════════════════════════════
cat("=== T0. 트리거 사실 재도출(코드) ===\n")
EMI <- rd("02_Infrastructure/ops/reinforce_auto_parallel.R")
RPR <- rd("02_Infrastructure/alpha_search/run_paper_replication.R")
L2A <- rd("02_Infrastructure/ops/rf_l2_auto.R")
emi_ok <- has(EMI, "judge_request_%s_%d.json") && has(EMI, 'status = "pending"') && has(EMI, 'status = "awaiting_judge"') &&
  has(EMI, "rf_a_eligibility")
chk("T0 강화 발행 = 후보별 judge_request_%s_%d.json(pending) + grade_a_queue awaiting_judge + rf_a_eligibility 관문", emi_ok)
# 충실구현 §11 라우팅 블록 — '# ---- 11.' 머리부터 미달 분기('} else if') 전까지
RP11 <- first_match(RPR, "(?s)# ---- 11\\.[^\n]*\n.*?\n  \\} else if")
chk("T0 run_paper_replication.R §11 라우팅 블록 추출(검사 드리프트 방지)", nzchar(RP11), "블록 머리/꼬리 표지가 바뀌었으면 이 검사도 옮겨라")
# ★관문 경유 판정 = 주석을 뺀 코드(P0-13) — 주석에 함수명을 남긴 채 코드를 되돌리면 구판 판정은 '경유' 로 속았다(M2d)
strip_c <- function(x) paste(sub("(^|[[:space:]])#.*$", "\\1", strsplit(x, "\n", fixed = TRUE)[[1]]), collapse = "\n")
gated_of <- function(rpr) { b <- first_match(rpr, "(?s)# ---- 11\\.[^\n]*\n.*?\n  \\} else if")
  nzchar(b) && grepl("rf_a_eligibility|grade_a_queue|judge_request_%s", strip_c(b), perl = TRUE) }
fa_gated <- gated_of(RPR)
# 파일 이름 = 러너 상수(parse) — 문서 대조의 정답을 문서가 아니라 코드에서 가져온다
RP_EX <- tryCatch(parse(text = RPR, keep.source = FALSE), error = function(e) NULL)
def_of <- function(nm) { for (e in RP_EX) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(nm))) return(e[[3]]); NULL }
const_of <- function(nm) { d <- def_of(nm); if (is.character(d) && length(d) == 1L) d else NA_character_ }
FA_ELIG <- const_of(".RP_JR_ELIGIBLE"); FA_HELD <- const_of(".RP_JR_HELD"); FA_LEG <- const_of(".RP_JR_LEGACY")
ROUTE <- paste(deparse(def_of(".rp_a_route"), width.cutoff = 500L), collapse = "\n")
cat(sprintf("       (재도출: 충실구현 §11 관문 경유=%s · 통과=%s · 보류=%s · 셀=%s)\n", fa_gated, FA_ELIG, FA_HELD, FA_LEG))
chk("T0 충실구현 A = §11 이 관문 정본을 경유(주석 제외 코드 재도출 · P0-13)", fa_gated)
route_ok <- function(src) nzchar(src) && all(vapply(c(".RP_JR_ELIGIBLE", ".RP_JR_HELD", ".RP_JR_LEGACY", "gate(inp$entry, inp$attempt, inp$spec, inp$ctx)",
                                                      ".rp_a_gate_inputs(", "isTRUE(cell)"), function(k) has(src, k), logical(1)))
chk("T0 라우터 .rp_a_route = 셀이면 구판 이름 · 아니면 관문 술어 호출 → 통과/보류 이름으로 가른다(상수 3종 실재)",
    route_ok(ROUTE) && !anyNA(c(FA_ELIG, FA_HELD, FA_LEG)) && length(unique(c(FA_ELIG, FA_HELD, FA_LEG))) == 3L)
# 강화 러너가 park/restore 하는 이름 = 셀 구판 이름 · 보류 이름(두 레인이 같은 뜻의 같은 이름을 쓴다)
park_ok <- function(emi, leg = FA_LEG, held = FA_HELD) !anyNA(c(leg, held)) &&
  has(emi, sprintf('file.path(d, "%s")', leg)) && has(emi, sprintf('file.path(d, "%s")', held))
chk("T0 셀 구판 이름·보류 이름 = 강화 러너 .a_art_request 의 live/held 이름(셀 모드 불변의 전제)", park_ok(EMI))
l2_ok <- has(L2A, "l2_judge_request.json") && grepl('schema = "l2_judge_request_v1", status = "pending"', L2A, fixed = TRUE)
chk("T0 2계층 발행 = 06_Registry/l2_judge_request.json(status=pending) · rf_l2_auto.R", l2_ok)

# ═════════════════════════════ T1. judge.md 스폰 조건 ═════════════════════════════
cat("\n=== T1. judge.md 스폰 조건 = 코드 사실 ===\n")
JD <- rd(".claude/agents/judge.md")
spawn_sec <- function(txt) first_match(txt, "(?s)## 스폰 조건[^\n]*\n.*?(?=\n## )")
JKEYS <- c("Grade A 확정 직후에만", "judge_request_<BID>_<n>.json", "status=pending", "grade_a_queue", "awaiting_judge", "rf_a_eligibility",
           "l2_judge_request.json", "rf_l2_auto.R", "run_paper_replication.R", "트리거가 아니다", "QEPM-R0-FREEZE", "재상정")
# ③ 충실구현 절만 떼어 본다(P0-13) — ② 2계층 줄은 코드 사실대로 '관문 없음' 을 말해야 하므로(test_qepm_advisor_contract G6g) 절 전체에
#   '관문 없음' 부재를 요구하면 관문 경유 상태에서 영원히 red 다. 절 = '  ③ **1계층 충실구현**' 줄부터 다음 '- ' 항목 전까지.
fa_clause <- function(s) first_match(s, "(?s)\n  ③ \\*\\*1계층 충실구현\\*\\*.*?(?=\n- |\\z)")
judge_ok <- function(txt, gated = fa_gated, elig = FA_ELIG, held = FA_HELD) {
  s <- spawn_sec(txt)
  if (!nzchar(s) || !all_has(s, JKEYS)) return(FALSE)
  if (has(s, "어느 리서치 모드든 동일")) return(FALSE)   # 구판 모순의 전칭 주장(충실구현 A 도 스폰)
  c3 <- fa_clause(s)
  if (!nzchar(c3)) return(FALSE)
  # 충실구현 절 = 코드가 관문을 안 거치면 '관문 없음 · 스폰하지 않고 · B07' 을 말해야 하고,
  #   거치면 관문 정본·통과/보류 이름(러너 상수)·pending 을 말하고 '관문 없음 · B07' 이 없어야 한다
  claim_ungated <- has(c3, "관문 없음") && has(c3, "스폰하지 않고") && has(c3, "B07")
  claim_gated <- !anyNA(c(elig, held)) && all_has(c3, c("rf_a_eligibility", elig, held, "status=pending")) &&
    !has(c3, "관문 없음") && !has(c3, "B07")
  if (gated) claim_gated else claim_ungated
}
chk("T1 스폰 조건 = 강화(후보별 요청 ∧ awaiting_judge) · 2계층(l2) · 충실구현(§11 관문 경유 → 통과 eligible·보류 held · P0-13) · 동결",
    judge_ok(JD), paste(missing_of(spawn_sec(JD), JKEYS), substr(fa_clause(spawn_sec(JD)), 1, 120)))

# ═════════════════════════════ T2. 충실구현 A 분기 문서 5곳 + Judge 프롬프트 ═════════════════════════════
cat("\n=== T2. 충실구현 A 분기 문서 = 코드 사실 ===\n")
line_by <- function(rel, pat) { l <- rl(rel); l[grepl(pat, l, perl = TRUE)] }
fa_line_ok <- function(lines, gated = fa_gated, elig = FA_ELIG, held = FA_HELD) {
  if (length(lines) != 1L) return(FALSE)
  x <- lines[1]
  says_pre_gate <- has(x, "judge_request.json") && has(x, "관문") && (has(x, "트리거가 아니다") || has(x, "트리거 아님")) && has(x, "B07")
  # P0-13 뒤: 관문(정본 이름 또는 'A 자격 관문') + 통과·보류 파일 이름(러너 상수) · 구 문언('관문 전 파일'·'관문 없음'·B07) 0
  says_gated <- !anyNA(c(elig, held)) && has(x, elig) && has(x, held) && (has(x, "rf_a_eligibility") || has(x, "A 자격 관문")) &&
    !has(x, "관문 전 파일") && !has(x, "관문 없음") && !has(x, "B07")
  if (gated) says_gated else says_pre_gate
}
FA_SITES <- list(
  list(rel = ".claude/rules/lean-loop.md",           pat = "^   - \\*\\*Grade A\\*\\* → "),
  list(rel = ".claude/commands/alpha-search.md",     pat = "^7\\. \\*\\*Grade A"),
  list(rel = ".claude/agents/alpha-search.md",       pat = "Judge 는 essence Grade A 확정 시에만"),
  list(rel = ".claude/skills/alpha-search/SKILL.md", pat = "^→ 분기\\(A → "),
  list(rel = ".claude/skills/alpha-search/SKILL.md", pat = "^- \\*\\*Grade A\\*\\* → "))
for (s in FA_SITES) {
  L <- line_by(s$rel, s$pat)
  chk(sprintf("T2 %s — A 분기 = 코드 사실(관문 경유=%s → 통과 %s · 보류 %s / 미경유면 '관문 전 파일·B07')", s$rel, fa_gated, FA_ELIG, FA_HELD),
      fa_line_ok(L), if (length(L) != 1L) sprintf("표지 줄 %d개", length(L)) else substr(L[1], 1, 140))
}
JI <- line_by("02_Infrastructure/prompts/judge_init.md", "을 소화해$")
ji_ok <- function(ji, gated = fa_gated, elig = FA_ELIG)
  length(ji) == 1L && has(ji, "judge_request_<BID>_<n>.json") && has(ji, "l2_judge_request.json") && has(ji, "트리거가 아니다") &&
    (!gated || (!is.na(elig) && has(ji, elig)))
chk("T2 judge_init.md 소화 대상 = 후보별 요청·(관문 경유면) 충실구현 통과 요청·l2 요청(강화 셀 산출물 judge_request.json·보류는 트리거 아님)",
    ji_ok(JI), paste(JI, collapse = " / "))
# T3 frontmatter description 3종(judge.md · alpha-search SKILL · 에이전트) — 코드가 관문을 거치면 '관문 전/없는 파일 · B07 뒤' 가 없고 통과 이름을 말한다
fm_desc <- function(rel) { l <- rl(rel); d <- l[grepl("^description: ", l)]; if (length(d)) d[1] else "" }
desc_ok <- function(d, gated = fa_gated, elig = FA_ELIG) {
  if (!nzchar(d)) return(FALSE)
  pre <- has(d, "관문 전 파일") || has(d, "관문 없는 파일")
  if (gated) !pre && !has(d, "B07") && !is.na(elig) && has(d, elig) && has(d, "rf_a_eligibility") else pre && has(d, "B07")
}
for (rel in c(".claude/agents/judge.md", ".claude/skills/alpha-search/SKILL.md", ".claude/agents/alpha-search.md"))
  chk(sprintf("T3 %s description = 충실구현 관문 사실(경유=%s)", rel, fa_gated), desc_ok(fm_desc(rel)), substr(fm_desc(rel), 1, 140))

# ═════════════════════════════ D. 휴면 진입로 표지 ═════════════════════════════
cat("\n=== D. 휴면 진입로 표지 ===\n")
DR <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/decision_register.json"), simplifyVector = FALSE), error = function(e) NULL)
dec <- function(id) if (is.null(DR)) NULL else Filter(function(x) identical(x$id, id), DR$items)
fz <- dec("QEPM-R0-FREEZE"); am <- dec("QEPM-ADVISOR-MODE")
chk("D0 표지가 가리키는 결정 2건 실재(resolved) — QEPM-R0-FREEZE · QEPM-ADVISOR-MODE",
    length(fz) == 1L && identical(fz[[1]]$status, "resolved") && length(am) == 1L && identical(am[[1]]$status, "resolved"))
kr_ok <- function(lines) { w <- lines[has(lines, "/worktask create")]
  length(w) >= 1L && all(vapply(w, function(x) has(x, "동결") && has(x, "QEPM-R0-FREEZE") && has(x, "/advisor"), logical(1))) }
KRL <- rl(".claude/skills/kr-inverse-pattern-miner/SKILL.md")
chk("D1 kr-inverse-pattern-miner — /worktask create 줄 = 동결 표지 + /advisor 안내", kr_ok(KRL))
fd_ok <- function(lines) { w <- lines[has(lines, "dossier")]
  length(w) >= 1L && all(vapply(w, function(x) has(x, "QEPM-R0-FREEZE"), logical(1))) &&
    any(has(lines, "/advisor")) && !any(has(lines, "QEPM/충실구현으로 권위 등급")) }
FDL <- rl(".claude/skills/factor-db-discovery/SKILL.md")
chk("D2 factor-db-discovery — dossier 언급 줄 전부 동결 표지 · /advisor 안내 · 'QEPM/충실구현으로' 0", fd_ok(FDL))
RPP <- rd("02_Infrastructure/ops/research_pool_predicates.py")
chk("D3 research_pool_predicates.py — qepm_dossier·paper_promotion 레인 동결 표지 상수(행동 검사 = test_research_queue_lanes.py F절)",
    grepl('QEPM_FREEZE_MARK = "QEPM-R0-FREEZE"', RPP, fixed = TRUE) && has(RPP, '"frozen": QEPM_FREEZE_MARK'))
ST <- fromJSON(file.path(ROOT, "02_Infrastructure/hooks/policies/state_transitions.json"), simplifyVector = FALSE)
SMR <- rl("02_Infrastructure/worktask/state_machine.R")
guard_real <- any(grepl("QEPM-R0-FREEZE", SMR, fixed = TRUE) & grepl("stop(", SMR, fixed = TRUE) &
                  grepl("JUDGE_PASSED", SMR, fixed = TRUE))
st_ok <- function(st, guard = guard_real) {
  fd <- st$transitions$FORGE_DONE
  jn <- intersect(unlist(fd$allowed_next), c("JUDGE_PASSED", "JUDGE_FAILED"))
  if (!length(jn)) return(TRUE)            # 허용 목록에서 빠졌으면 표지가 필요 없다
  note <- as.character(fd[["_freeze_note"]] %||% "")
  guard && has(note, "QEPM-R0-FREEZE") && has(note, "sm_validated_advance") && has(note, "재상정")
}
chk("D4 state_transitions FORGE_DONE→JUDGE_* 허용이 남아 있으면 _freeze_note(동결·가드 위치·재상정) + state_machine.R 가드 실재",
    st_ok(ST), sprintf("guard_real=%s note=%s", guard_real, substr(as.character(ST$transitions$FORGE_DONE[["_freeze_note"]] %||% "(없음)"), 1, 80)))
ADV <- file.path(ROOT, ".claude/commands/advisor.md")
if (file.exists(ADV)) chk("D5 표지가 안내하는 /advisor 명령 실재", TRUE) else
  skip("D5 /advisor 명령 파일 미생성 — 어드바이저 갈래 배포 전(표지는 결정 QEPM-ADVISOR-MODE 를 가리킨다)")

# ═════════════════════════════ M. 돌연변이(검사기 양방향) ═════════════════════════════
cat("\n=== M. 돌연변이 ===\n")
OLD_JUDGE <- paste0("## 스폰 조건 (유일)\n- **essence Grade A 확정 직후에만** 스폰된다 — 어느 리서치 모드든 동일\n",
  "  (1계층 충실구현 / 1계층 강화 / 2계층 전략 로테이션).\n",
  "- ★**트리거** = **후보별 요청** `qepm/mailbox/judge_request_<BID>_<n>.json`(`status=pending`) **∧** `06_Registry/grade_a_queue.json` `status=awaiting_judge`.\n",
  "  발행자 = `rf_runner_gates.R::rf_a_eligibility` 통과분. 2계층 = `06_Registry/l2_judge_request.json`(`rf_l2_auto.R`).\n",
  "- 산출 디렉터리의 `judge_request.json`(`run_paper_replication.R`)은 **트리거가 아니다**. `QEPM-R0-FREEZE` — 재상정.\n")
JD_M1 <- sub("(?s)## 스폰 조건[^\n]*\n.*?(?=\n## )", gsub("\\\\", "\\\\\\\\", OLD_JUDGE), JD, perl = TRUE)
chk("M1 judge.md 구 스폰 조건(전칭 '어느 모드든 동일' + 충실구현 절 없음) 재주입 → red", !judge_ok(JD_M1))
chk("M2 코드가 관문 우회로 되돌아간 가상 상태 → 현 judge.md(관문 경유 서술) 가 red(문서-코드 불일치 검출)", !judge_ok(JD, gated = FALSE))
# M2b — P0-13 직전 판 ③ 절(관문 없음 · B07 · 스폰하지 않고) 재주입 → 현 코드(관문 경유)에서 red
OLD_J3 <- paste0("\n  ③ **1계층 충실구현**(`run_paper_replication` 단독 실행 · 어드바이저 측정 포함) = 러너가 산출 디렉터리에 `judge_request.json` 만 쓴다\n",
  "     (`run_paper_replication.R` §11 — **관문 없음** · grade_a_queue 미기록). 관문 전 파일이라 **트리거가 아니다** → 스폰하지 않고\n",
  "     `[1계층]` A 후보로 도훈에게 보고한다(그 뒤 스폰 = 세션이 `rf_a_eligibility` 를 확인하고 **도훈 지시**가 있을 때만). 관문 경유 발행(①과 같은 후보별 요청)으로의 이관 = **B07 배포 뒤**(코드는 그때 고친다).")
C3_now <- fa_clause(spawn_sec(JD))
JD_M2b <- if (nzchar(C3_now)) sub(C3_now, OLD_J3, JD, fixed = TRUE) else ""
chk("M2b P0-13 직전 판 ③ 절('관문 없음 · 스폰하지 않고 · B07') 재주입 → 현 코드(관문 경유)에서 red · 그 절은 미경유 코드에서는 green(양성 대조)",
    nzchar(JD_M2b) && !judge_ok(JD_M2b) && judge_ok(JD_M2b, gated = FALSE))
# M2c — **실코드 돌연변이**: §11 A 분기를 P0-13 직전 판(관문 없이 judge_request.json 무조건 기록)으로 되돌린 러너 사본에서 재도출
OLD_A11 <- paste0("# ---- 11. 라우팅: A → Judge / 미달 → 강화 원장 ----\n",   # RP11 은 '#' 에서 시작한다(앞 공백은 원문에 남는다)
  "  if (identical(grade, \"A\")) {\n",
  "    write_json(list(strategy_id = strategy_id, layer = 1L, grade = grade,\n",
  "                    artifacts = OUT_DIR, engine_path = factor_engine_path,\n",
  "                    requested_at = format(Sys.time(), \"%Y-%m-%dT%H:%M:%S%z\"),\n",
  "                    note = \"v10: Grade A → Judge(PIT 전담) 스폰 요청 — 세션(Q-Lead)이 Agent 스폰\"),\n",
  "               file.path(OUT_DIR, \"judge_request.json\"), auto_unbox = TRUE, pretty = TRUE)\n",
  "    cat(\"[replication] ★Grade A — judge_request.json 발행 (Judge 스폰은 세션 소관)\\n\")\n",
  "  } else if")
RPR_M <- if (nzchar(RP11)) sub(RP11, OLD_A11, RPR, fixed = TRUE) else ""
g_M <- gated_of(RPR_M)
FA_LINES <- lapply(FA_SITES, function(s) line_by(s$rel, s$pat))
chk("M2c 실코드 되돌림(§11 = 관문 없이 judge_request.json) → 재도출 '미경유' · 현 judge.md·A 분기 5줄·description 3종 전부 red",
    nzchar(RPR_M) && !identical(RPR_M, RPR) && !g_M && !judge_ok(JD, gated = g_M) &&
      !any(vapply(FA_LINES, function(L) fa_line_ok(L, gated = g_M), logical(1))) &&
      !any(vapply(c(".claude/agents/judge.md", ".claude/skills/alpha-search/SKILL.md", ".claude/agents/alpha-search.md"),
                  function(r) desc_ok(fm_desc(r), gated = g_M), logical(1))))
# M2d — 주석에만 관문 이름을 남긴 되돌림은 '경유' 가 아니다(주석 제외 재도출이 막는다 · 구판 판정은 여기서 속았다)
RPR_D <- sub("  if (identical(grade, \"A\")) {\n", "  if (identical(grade, \"A\")) {\n    # rf_a_eligibility 는 나중에 — 지금은 구판 그대로\n",
             RPR_M, fixed = TRUE)
chk("M2d 주석에만 'rf_a_eligibility' 를 남긴 되돌림 → 미경유로 재도출(주석은 증거 아님) · 구판 판정(주석 포함)은 경유로 속는다(대조)",
    nzchar(RPR_D) && !identical(RPR_D, RPR_M) && !gated_of(RPR_D) &&
      grepl("rf_a_eligibility", first_match(RPR_D, "(?s)# ---- 11\\.[^\n]*\n.*?\n  \\} else if"), fixed = TRUE))
# M2e — 셀 구판 이름을 강화 러너 park 이름과 어긋나게 바꾼 가상 러너 → T0 park 대조 red(셀 모드 불변 전제 붕괴 검출)
chk("M2e 셀 구판 이름이 강화 러너 park 이름과 어긋나면 red · 보류 이름도 같다",
    !park_ok(EMI, leg = "judge_request.cell.json") && !park_ok(EMI, held = "judge_request.hold.json") && !park_ok(EMI, leg = NA_character_))
OLD_LL <- "   - **Grade A** → **Judge(PIT 전담) 스폰**(`judge_request.json` 발행됨) → PASS → BOOK 등록 후보(도훈 confirm) / FAIL → 결과 무효·수리·재측정."
chk("M3 lean-loop 구 A 분기('judge_request.json 발행됨 → 스폰') 재주입 → red", !fa_line_ok(OLD_LL))
OLD_CMD <- "7. **Grade A → `judge_request.json` 발행 → Judge(PIT 6축) → PASS 시 BOOK 등록 후보(도훈 confirm)**."
chk("M3 /alpha-search 구 7단계 재주입 → red", !fa_line_ok(OLD_CMD))
LL_now <- line_by(".claude/rules/lean-loop.md", "^   - \\*\\*Grade A\\*\\* → ")
chk("M4 코드 되돌림(관문 우회) 가상 상태 → 현 lean-loop A 분기(관문 경유 서술)가 red", !fa_line_ok(LL_now, gated = FALSE))
OLD_LL_PRE <- paste0("   - **Grade A** → 러너가 산출물 `judge_request.json` 을 쓰지만 **관문 전 파일이라 Judge 트리거가 아니다**(충실구현 러너엔 A 자격 관문 없음 · ",
  "관문 경유 이관 = B07 배포 뒤) → `[1계층]` A 후보로 도훈 보고. 트리거가 서면 Judge(PIT 전담) → PASS → BOOK 등록 후보(도훈 confirm) / FAIL → 결과 무효·수리·재측정. ",
  "트리거 정본 = `judge.md` §스폰 조건.")
chk("M4b P0-13 직전 lean-loop A 분기('관문 전 파일 · B07') → 현 코드(관문 경유)에서 red · 미경유 코드에서는 green(양성 대조)",
    !fa_line_ok(OLD_LL_PRE) && fa_line_ok(OLD_LL_PRE, gated = FALSE))
OLD_JI <- "트리거 요청 1건(1계층 강화 = `qepm/mailbox/judge_request_<BID>_<n>.json` judge_request_v2 · 2계층 = `06_Registry/l2_judge_request.json` — 정본 `.claude/agents/judge.md` §스폰 조건 · 산출물 `judge_request.json` 은 트리거가 아니다)을 소화해"
chk("M4c P0-13 직전 judge_init 소화 줄(충실구현 통과 요청 부재) → 현 코드에서 red · 미경유 코드에서는 green", !ji_ok(OLD_JI) && ji_ok(OLD_JI, gated = FALSE))
chk("M5 kr-inverse 구 문언('정밀 편입 → `/worktask create`(WT-R).') 재주입 → red",
    !kr_ok(c(KRL, "등재 후 착수는 진입점 경유: 정밀 편입 → `/worktask create`(WT-R). 착수 전 큐 확인")))
chk("M6 factor-db-discovery 구 문언('PASS 후보는 dossier(qvest-dossier-pipeline)로.') 재주입 → red",
    !fd_ok(c(FDL, "- 유의한 결과/의미있는 실패 → 메모리 적립. PASS 후보는 dossier(qvest-dossier-pipeline)로.")))
ST_M <- ST; ST_M$transitions$FORGE_DONE[["_freeze_note"]] <- NULL
chk("M7 state_transitions _freeze_note 삭제 사본(JUDGE_* 허용 잔존) → red", !st_ok(ST_M))
chk("M8 state_machine.R 가드 줄이 없는 가상 상태 → 주석만 남은 표지는 red(가드 실재 대조)", !st_ok(ST, guard = FALSE))
ST_N <- ST; ST_N$transitions$FORGE_DONE$allowed_next <- list("COMPLETED", "ABORTED"); ST_N$transitions$FORGE_DONE[["_freeze_note"]] <- NULL
chk("M9 음성 대조: JUDGE_* 가 허용 목록에서 빠진 사본은 표지 없이도 통과(과잉 요구 아님)", st_ok(ST_N, guard = FALSE))

cat(sprintf("\n== test_qepm_freeze_residual: %d pass · %d fail · %d skip ==\n", P, F, S))
cat(toJSON(list(test = "qepm_freeze_residual", pass = P, fail = F, total = P + F, skipped = S, skips = as.list(SKIPS)), auto_unbox = TRUE), "\n", sep = "")
if (F > 0L) quit(status = 1L)
