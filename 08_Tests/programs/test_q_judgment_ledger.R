## test_q_judgment_ledger.R — Q 판단 원장 · Superfan 논쟁 writer(programs/q_judgment_ledger.py · 2026-10-15) — 임시 원장으로만(운영 원장 무접촉)
##   ① 판단 기록 · 어휘 ② 리뷰 등록(범위 = reviewed) ③ 도전 등급 규칙 — 위반 주입: 규칙 없는 stop · 절대 규칙 밖 stop · 대안/반증 조건 없는 도전 ·
##   리뷰당 상한 5 초과 ④ 논쟁 절차 — 수용엔 바꾼 것 필수 · 재반박 1회 · stop 은 이견으로 못 닫음 · 상신은 결정 기록부 id 필수
##   ⑤ 사후 채점 · 채점표 ⑥ 부팅 꼬리(빈 원장 = '' · Q 차례 · Superfan 차례 · 깨진 원장 = '?(…)' · rc 0) ⑦ 세션 재개 배선(Resume 줄 꼬리 · resolve)
##   ⑧ 원자적 교체 ⑨ 에이전트 · 규약 배선
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"); if (!file.exists(PY)) PY <- Sys.which("python")
TOOL <- file.path(ROOT, "02_Infrastructure/programs/q_judgment_ledger.py")
SR <- file.path(ROOT, "02_Infrastructure/programs/session_resume.py")
TMP <- normalizePath(tempfile("qjl_"), winslash = "/", mustWork = FALSE); dir.create(TMP)
LG <- file.path(TMP, "q_judgment_ledger.json"); ST <- file.path(TMP, "session_resume.json")
Sys.setenv(QVEST_JUDGMENT_LEDGER_PATH = LG, QVEST_SESSION_RESUME_PATH = ST, PYTHONUTF8 = "1")   # Windows system2(env=) 미동작 — 프로세스 환경으로
run <- function(..., tool = TOOL) {
  out <- suppressWarnings(system2(PY, c("-X", "utf8", shQuote(tool), ...), stdout = TRUE, stderr = TRUE))
  list(out = out, rc = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}
idof <- function(r) sub(".* ", "", r$out[length(r$out)])
q <- function(x) shQuote(x)
rd <- function() jsonlite::fromJSON(LG, simplifyVector = FALSE)

## ⑥ 빈 원장(파일 없음) → 부팅 꼬리 ''
chk("⑥ 원장 없음 → 부팅 꼬리 빈 문자열", identical(trimws(paste(run("boot-fragment")$out, collapse = "")), ""))

## ① 판단 기록
r1 <- run("record", "--op", "OP-T", "--kind", "round_selection", "--summary", q("P3R03 선택"), "--rationale", q("병목 = 급락기 낙폭"),
          "--ref", q("§2-3"), "--evidence", "a.md", "--alt", q("P2 방어 라운드"), "--expect", q("위기 포착 < RX0"), "--confidence", "0.6")
J1 <- idof(r1)
chk("① 판단 기록 rc 0 · id 형식 J-YYYYMMDD-001", r1$rc == 0L && grepl("^J-[0-9]{8}-001$", J1), paste(r1$out, collapse = " | "))
chk("① 종류 어휘 밖 거부(위반 주입)", run("record", "--kind", "whim", "--summary", "x", "--rationale", "y")$rc != 0L)
chk("① 근거 빈칸 거부(위반 주입)", run("record", "--kind", "design", "--summary", "x", "--rationale", q(" "))$rc != 0L)
J2 <- idof(run("record", "--kind", "escalation", "--summary", q("셀 수를 도훈께 여쭘"), "--rationale", q("확신 없음")))
J3 <- idof(run("record", "--kind", "verdict", "--summary", q("판정 해석"), "--rationale", q("반증 조건대로")))
d <- rd()
chk("① 저장 — 필드 · 상태 open", identical(d$judgments[[1]]$status, "open") && identical(d$judgments[[1]]$expectation, "위기 포착 < RX0") &&
      identical(unlist(d$judgments[[1]]$framework_refs), "§2-3") && isTRUE(abs(d$judgments[[1]]$confidence - 0.6) < 1e-9))

## ② 리뷰 등록
chk("② 없는 판단을 범위로 거부", run("review", "--trigger", "T1", "--file", "r.md", "--scope", "J-19990101-001")$rc != 0L)
chk("② 트리거 어휘 밖 거부", run("review", "--trigger", "T9", "--file", "r.md")$rc != 0L)
rv <- run("review", "--trigger", "T1", "--file", "r1.md", "--scope", J1, J2); R1 <- idof(rv)
d <- rd()
chk("② 리뷰 등록 · 범위 판단 reviewed · 미범위 open", rv$rc == 0L && grepl("^R-", R1) && identical(d$judgments[[1]]$status, "reviewed") &&
      identical(d$judgments[[2]]$status, "reviewed") && identical(d$judgments[[3]]$status, "open"))

## ③ 도전 등급 규칙
chk("③ 규칙 없는 stop 거부(위반 주입)",
    run("raise", "--review", R1, "--target", J1, "--grade", "stop", "--claim", "x", "--alternative", "a", "--falsifier", "f")$rc != 0L)
chk("③ 절대 규칙 밖 stop 거부(위반 주입 · '취향'은 stop 이 아니다)",
    run("raise", "--review", R1, "--target", J1, "--grade", "stop", "--rule", "STYLE", "--claim", "x", "--alternative", "a", "--falsifier", "f")$rc != 0L)
chk("③ 대안 없는 도전 거부(위반 주입)",
    run("raise", "--review", R1, "--target", J1, "--grade", "challenge", "--claim", "x", "--falsifier", "f")$rc != 0L)
chk("③ 반증 조건 없는 도전 거부(위반 주입)",
    run("raise", "--review", R1, "--target", J1, "--grade", "challenge", "--claim", "x", "--alternative", "a")$rc != 0L)
chk("③ 없는 대상 거부", run("raise", "--review", R1, "--target", "J-19990101-009", "--grade", "note", "--claim", "x")$rc != 0L)
S1 <- idof(run("raise", "--review", R1, "--target", J1, "--grade", "stop", "--rule", "TAU_D", "--claim", q("시험 창 수치로 선택"),
               "--evidence", "p.json", "--alternative", q("보는 창 지표로 재선정"), "--falsifier", q("근거 문장에 2023~ 수치 없음")))
C1 <- idof(run("raise", "--review", R1, "--target", J2, "--grade", "challenge", "--claim", q("Q 권한을 상신"),
               "--alternative", q("체계 §6 대로 Q 가 결정"), "--falsifier", q("셀 수가 비용 정책이면 상신 맞음")))
N1 <- idof(run("raise", "--review", R1, "--target", "SYSTEM", "--grade", "note", "--claim", q("참고")))
d <- rd()
cs <- setNames(d$challenges, vapply(d$challenges, `[[`, "", "id"))
chk("③ stop(TAU_D) · challenge = open · note = closed_note(응답 불필요)",
    identical(cs[[S1]]$status, "open") && identical(cs[[S1]]$rule, "TAU_D") && identical(cs[[C1]]$status, "open") && identical(cs[[N1]]$status, "closed_note"))
for (i in 1:3) run("raise", "--review", R1, "--target", J1, "--grade", "challenge", "--claim", q(paste("c", i)), "--alternative", "a", "--falsifier", "f")
chk("③ 리뷰당 stop+challenge 상한 5 — 6번째 거부(위반 주입)",
    run("raise", "--review", R1, "--target", J1, "--grade", "challenge", "--claim", "c6", "--alternative", "a", "--falsifier", "f")$rc != 0L)
chk("③ 상한 뒤에도 note 는 기록", run("raise", "--review", R1, "--target", J1, "--grade", "note", "--claim", "n2")$rc == 0L)

## ⑥ 부팅 꼬리 — Q 차례
bf <- paste(run("boot-fragment")$out, collapse = "")
chk("⑥ 부팅 꼬리 — Q 응답 대기 · 정지 수 · 미검토 판단", grepl("Q 응답 대기 5", bf, fixed = TRUE) && grepl("(정지 1)", bf, fixed = TRUE) &&
      grepl("미검토 판단 1", bf, fixed = TRUE), bf)

## ④ 논쟁 절차
chk("④ 수용엔 바꾼 것 필수(위반 주입)", run("respond", "--id", C1, "--kind", "accept", "--text", "ok")$rc != 0L)
r <- run("respond", "--id", C1, "--kind", "rebut", "--text", q("셀 수는 예산 정책"))
bf <- paste(run("boot-fragment")$out, collapse = "")
chk("④ 반박 → rebutted · 부팅 꼬리 'Superfan 차례 1'", r$rc == 0L && identical(rd()$challenges[[2]]$status, "rebutted") && grepl("Superfan 차례 1", bf, fixed = TRUE), bf)
chk("④ 반박 전 재반박 불가(open 도전에 counter 거부)", run("counter", "--id", S1, "--text", "x")$rc != 0L)
chk("④ 재반박 1회 → countered", run("counter", "--id", C1, "--text", q("정책 아님 — 라운드 설계"))$rc == 0L && identical(rd()$challenges[[2]]$status, "countered"))
chk("④ 재반박 2회 거부(위반 주입)", run("counter", "--id", C1, "--text", "again")$rc != 0L)
chk("④ 재반박 뒤 재반박 응답(rebut) 거부 — 수용 또는 종결만", run("respond", "--id", C1, "--kind", "rebut", "--text", "x")$rc != 0L)
chk("④ 이견으로 종결(challenge · 재반박 뒤) → disagreement", run("settle", "--id", C1, "--kind", "disagreement", "--text", q("Q 판단 유지"))$rc == 0L &&
      identical(rd()$challenges[[2]]$status, "disagreement"))
chk("④ 닫힌 도전 재종결 거부", run("settle", "--id", C1, "--kind", "withdrawn", "--text", "x")$rc != 0L)
invisible(run("respond", "--id", S1, "--kind", "rebut", "--text", q("근거 문장은 보는 창")))
chk("④ stop 은 이견으로 못 닫음(위반 주입)", run("settle", "--id", S1, "--kind", "disagreement", "--text", "x")$rc != 0L)
chk("④ 상신 종결엔 결정 기록부 id 필수(위반 주입)", run("settle", "--id", S1, "--kind", "escalated", "--text", "x")$rc != 0L)
chk("④ stop 철회(Superfan 수긍) → withdrawn", run("settle", "--id", S1, "--kind", "withdrawn", "--text", q("반박 수긍"))$rc == 0L &&
      identical(rd()$challenges[[1]]$status, "withdrawn"))
C3 <- vapply(rd()$challenges, `[[`, "", "id")[4]
chk("④ 수용(바꾼 것 기록) → accepted", run("respond", "--id", C3, "--kind", "accept", "--text", "ok", "--change", q("사전등록 문구 수정"))$rc == 0L)

## ⑤ 사후 채점 · 채점표
chk("⑤ note 는 채점 대상 아님(거부)", run("outcome", "--id", N1, "--kind", "vindicated", "--text", "x")$rc != 0L)
chk("⑤ 사후 채점 vindicated", run("outcome", "--id", C1, "--kind", "vindicated", "--text", q("다음 라운드가 보여 줌"))$rc == 0L)
s <- jsonlite::fromJSON(paste(run("stats", "--json")$out, collapse = "\n"))
chk("⑤ 채점표 — 수용 1 · 철회 1 · 적중 1/1 · 등급별 수", s$accepted == 1L && s$withdrawn == 1L && s$vindicated == 1L && isTRUE(s$hit_rate == 1) &&
      s$by_grade$stop == 1L && s$by_grade$note == 2L, paste(names(s), unlist(s), collapse = " "))
sh <- paste(run("show", "--open")$out, collapse = "\n")
chk("⑤ show — 응답 대기 · 미검토 판단 절", grepl("응답 대기 도전", sh, fixed = TRUE) && grepl(J3, sh, fixed = TRUE))

## ⑩ 철학 Superfan 역할(2026-10-16) — 역할 · 트리거 · 방향 판정 · 보류 요청
J4 <- idof(run("record", "--kind", "design", "--summary", q("P3R03 설계"), "--rationale", q("급락기 낙폭")))
chk("⑩ 역할 어휘 밖 거부", run("review", "--role", "critic", "--trigger", "P1", "--file", "p.md")$rc != 0L)
chk("⑩ 판단 역할에 P 트리거 거부(역할별 어휘)", run("review", "--trigger", "P1", "--file", "p.md")$rc != 0L)
chk("⑩ 철학 역할에 T 트리거 거부", run("review", "--role", "philosophy", "--trigger", "T1", "--file", "p.md")$rc != 0L)
chk("⑩ 철학 P2 는 방향 판정 필수(위반 주입)", run("review", "--role", "philosophy", "--trigger", "P2", "--file", "p.md")$rc != 0L)
chk("⑩ 방향 판정 어휘 밖 거부", run("review", "--role", "philosophy", "--trigger", "P2", "--direction", "sideways", "--file", "p.md")$rc != 0L)
chk("⑩ 판단 리뷰에 방향 판정 거부", run("review", "--trigger", "T2", "--direction", "toward", "--file", "p.md")$rc != 0L)
RP1 <- idof(run("review", "--role", "philosophy", "--trigger", "P1", "--file", "p1.md", "--round", "P3R03", "--scope", J4))
RP2 <- idof(run("review", "--role", "philosophy", "--trigger", "P2", "--direction", "toward", "--round", "P3R03", "--file", "p2.md"))
CH <- idof(run("raise", "--review", RP1, "--target", J4, "--grade", "challenge", "--claim", q("집중 지표 없음"), "--alternative", q("유효 종목 수 판정 추가"),
               "--falsifier", q("최대 비중이 낮으면 무관"), "--hold"))
d <- rd(); cs <- setNames(d$challenges, vapply(d$challenges, `[[`, "", "id"))
chk("⑩ 철학 리뷰 · 도전 — 역할 philosophy · 보류 요청 기록", identical(cs[[CH]]$role, "philosophy") && isTRUE(cs[[CH]]$hold_request) &&
      identical(Filter(function(r) identical(r$id, RP2), d$reviews)[[1]]$direction, "toward"))
s2 <- jsonlite::fromJSON(paste(run("stats", "--json")$out, collapse = "\n"), simplifyVector = FALSE)
chk("⑩ 채점표 — 역할별 수 · 열린 보류 요청 · 방향 판정 시계열", s2$by_role$philosophy == 1L && s2$holds_open == 1L &&
      length(s2$direction) == 1L && identical(s2$direction[[1]]$direction, "toward") && identical(s2$direction[[1]]$round, "P3R03"))
chk("⑩ 부팅 꼬리에 보류 요청", grepl("보류 요청 1", paste(run("boot-fragment")$out, collapse = ""), fixed = TRUE))

## ⑦ 세션 재개 배선 — Resume 줄 꼬리 · resolve
invisible(run("begin", "--id", "OP-T", "--title", q("검사"), "--step", q("S1=하나"), tool = SR))
invisible(run("decide", "--id", "OP-T", "--text", q("P0 안건(결정 기록부 대기)"), tool = SR))
bl <- paste(run("boot-line", tool = SR)$out, collapse = "")
chk("⑦ Resume 줄 꼬리에 Superfan 상태", grepl("| Superfan: ", bl, fixed = TRUE), bl)
chk("⑦ resolve — 없는 대기 거부", run("resolve", "--id", "OP-T", "--text", q("없는 것"), "--outcome", "x", tool = SR)$rc != 0L)
r <- run("resolve", "--id", "OP-T", "--text", q("P0 안건"), "--outcome", q("③+④+P4"), tool = SR)
o <- jsonlite::fromJSON(ST, simplifyVector = FALSE)$operations[[1]]
chk("⑦ resolve — 대기에서 빠지고 기록에 남는다", r$rc == 0L && !length(o$decisions) && any(grepl("결정 해소", vapply(o$log, `[[`, "", "text"))))

## ⑥ 깨진 원장 → '?(…)' · rc 0 · Resume 줄도 살아 있다
writeLines("{not json", LG)
r <- run("boot-fragment")
chk("⑥ 깨진 원장 → 'Superfan ?(' · rc 0(부팅 계속)", r$rc == 0L && grepl("^Superfan \\?\\(", r$out[1]), paste(r$out, collapse = " | "))
chk("⑥ 깨진 원장이어도 Resume 줄 생성", grepl("^Resume: ", run("boot-line", tool = SR)$out[1]))

## ⑧ 원자적 교체
chk("⑧ 임시 파일 잔재 0", !length(list.files(TMP, pattern = "^\\.q_judgment_ledger_.*\\.tmp$", all.files = TRUE)))

## ⑨ 에이전트 · 규약 배선
A <- paste(readLines(file.path(ROOT, ".claude/agents/superfan.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("⑨ 에이전트 정의 — opus · max · 도구에 Edit 없음 · 원장 writer · 규약 · τ_D",
    grepl("\nmodel: opus\n", A, fixed = TRUE) && grepl("\neffort: max\n", A, fixed = TRUE) && grepl("\ntools: Read, Grep, Glob, Bash, Write\n", A, fixed = TRUE) &&
      grepl("q_judgment_ledger.py", A, fixed = TRUE) && grepl("superfan_protocol.md", A, fixed = TRUE) && grepl("2022-12-31", A, fixed = TRUE))
P <- paste(readLines(file.path(ROOT, "00_Lawbook/specs/superfan_protocol.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("⑨ 규약 — 비차단 · 상한 5 · 재반박 1회 · stop 은 이견 종결 불가", grepl("Q 는 기다리지 않는다", P, fixed = TRUE) && grepl("최대 5건", P, fixed = TRUE) &&
      grepl("재반박(1회)", P, fixed = TRUE) && grepl("`stop` 은 이견으로 닫지 않는다", P, fixed = TRUE))

Sys.unsetenv(c("QVEST_JUDGMENT_LEDGER_PATH", "QVEST_SESSION_RESUME_PATH")); unlink(TMP, recursive = TRUE)
cat(sprintf("\n== q_judgment_ledger: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"q_judgment_ledger","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
