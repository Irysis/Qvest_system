## test_tg_scope_key.R — 텔레그램 중복 발송 차단 키(.tg_title_scope · 2026-10-15 수리) — 발송 0(키 함수만 · 네트워크 무접촉)
##   ① 같은 제목 = 같은 키(진짜 중복은 계속 막는다) ② ASCII 골격이 같은 서로 다른 한글 제목 = 다른 키(10-15 실측 충돌 재현)
##   ③ 구판 공식은 ②를 충돌시킨다(이 검사가 막는 회귀를 양성 대조로 보인다) ④ tg_agent_brief 가 이 함수를 쓴다(소스 문장)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))))
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
t1 <- "[1계층] 리서치 용어집 — 셀 · 라운드 · 레인 코드 사전(인쇄본 첨부)"
t2 <- "[1계층] 다음 리서치 브리핑 — 알파는 엔진에, 막힌 곳은 급락기 낙폭"
k1 <- .tg_title_scope("Q-Lead", t1); k1b <- .tg_title_scope("Q-Lead", t1); k2 <- .tg_title_scope("Q-Lead", t2)
chk("① 같은 제목 = 같은 키", identical(k1, k1b))
chk("② 다른 한글 제목(같은 ASCII 골격) = 다른 키", !identical(k1, k2), paste(k1, k2))
old <- function(agent, title) sprintf("%s_%s", agent, gsub("[^A-Za-z0-9]", "_", substr(title, 1, 40)))
chk("③ 양성 대조 — 구판 공식은 두 제목을 충돌시킨다", identical(old("Q-Lead", t1), old("Q-Lead", t2)))
chk("① 다른 에이전트 = 다른 키", !identical(k1, .tg_title_scope("AlphaSearch", t1)))
chk("키 = 파일 이름 안전(영숫자 · _ · -)", grepl("^[A-Za-z0-9_-]+$", k1) && grepl("^[A-Za-z0-9_-]+$", k2))
src <- paste(readLines(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("④ tg_agent_brief 가 .tg_title_scope 로 키를 만든다(구판 공식 잔존 없음)",
    grepl(".tg_title_scope(agent, title)", src, fixed = TRUE) &&
      !grepl('sprintf("%s_%s", agent,\n                 gsub("[^A-Za-z0-9]", "_", substr(title, 1, 40)))', src, fixed = TRUE))
cat(sprintf("\n== tg_scope_key: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"tg_scope_key","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
