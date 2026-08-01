#==============================================================================
# test_paper_intake_resolvers.R — 논문 인입 라인 해석기 위반 주입 테스트
#
# 배경 (2026-08-02 실측 사고):
#   paper_recharge_daily.R 의 MCP 탐색 프로브가 `Sys.which("python3")` 로
#   인터프리터를 골랐다. Windows 에서 이 이름은 Microsoft Store 스텁
#   (WindowsApps/AppInstallerPythonRedirector) 으로 해석되며, 스텁은
#   "Python" 한 줄만 찍고 **exit 0** 으로 끝나고 산출 파일을 쓰지 않는다.
#   → system() 은 성공(0) 으로 보이고 fromJSON(out) 만 실패해
#     status="read_failed" candidates=0 이 되어, "신규 논문이 없음" 과
#     구분 불가한 침묵 정지가 6일간 지속됐다(2026-07-28~08-02).
#   같은 스크립트를 실 인터프리터로 돌리면 mcp_ok / candidates=34.
#
# 이 파일이 지키는 것:
#   (1) 스텁 판별자가 **실제로 발화**하는가 (위반 주입)
#       — 최초 수리본은 "WindowsApps" 문자열만 봤는데 Sys.which() 는 8.3
#         단축경로("...MICROS~1/WINDOW~1/python3.exe") 를 돌려주므로 한 건도
#         못 잡는 죽은 검사였다. 오탐 제거와 검사 사망은 겉보기가 같다.
#   (2) 정상 인터프리터를 잘못 기각하지 않는가 (음성 통제)
#
# 실행: Rscript 08_Tests/ops/test_paper_intake_resolvers.R
# exit 0 = 전건 PASS / exit 1 = FAIL 존재
#==============================================================================

root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(root)) root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root) || !dir.exists(file.path(root, "02_Infrastructure"))) {
  # 테스트 파일 자신의 위치에서 역산 (env 오염에 독립)
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) root <- normalizePath(file.path(dirname(f), "..", ".."), mustWork = FALSE)
}
target <- file.path(root, "02_Infrastructure", "tools", "paper_recharge_daily.R")
if (!file.exists(target)) stop("대상 부재: ", target)

src <- readLines(target, warn = FALSE)
b <- which(startsWith(trimws(src), "is_store_stub <- function(p) {"))
if (length(b) != 1L) {
  stop("is_store_stub 판별자를 찾지 못함 (리팩터링으로 이름/형태 변경 시 본 테스트 갱신 필요). 매치 수=",
       length(b))
}
e <- b; depth <- 0L
repeat {
  opens  <- lengths(regmatches(src[e], gregexpr("{", src[e], fixed = TRUE)))
  closes <- lengths(regmatches(src[e], gregexpr("}", src[e], fixed = TRUE)))
  depth  <- depth + opens - closes
  if (depth <= 0L) break
  e <- e + 1L
}
# 사본이 아니라 원본 파일 본문을 그대로 평가 — 수리가 원본에서 풀리면 여기서 잡힌다.
eval(parse(text = paste(src[b:e], collapse = "\n")))

pass <- 0L; fail <- 0L
chk <- function(label, got, want) {
  ok <- identical(got, want)
  cat(sprintf("  [%s] %-50s got=%-5s want=%s\n",
              if (ok) "PASS" else "FAIL", label, got, want))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
}

cat("== 위반 주입: 일부러 스텁 경로를 넣었을 때 판별자가 발화하는가 ==\n")
chk("Sys.which('python3') (실제 회귀 입력·단축경로)", is_store_stub(Sys.which("python3")), TRUE)
chk("Sys.which('python')  (단축경로)",                is_store_stub(Sys.which("python")),  TRUE)
chk("긴 이름 스텁 경로",
    is_store_stub("C:/Users/x/AppData/Local/Microsoft/WindowsApps/python3.exe"), TRUE)
chk("역슬래시 8.3 단축형 리터럴",
    is_store_stub("C:\\Users\\x\\AppData\\Local\\MICROS~1\\WINDOW~1\\python.exe"), TRUE)

cat("== 음성 통제: 정상 인터프리터를 잘못 기각하지 않는가 ==\n")
qp <- Sys.getenv("QVEST_PY", "")
if (nzchar(qp)) chk("실 인터프리터 QVEST_PY", is_store_stub(qp), FALSE)
chk("venv python",   is_store_stub("C:/x/.venv_qvest_ml/Scripts/python.exe"), FALSE)
chk("system python", is_store_stub("C:/Program Files/Python312/python.exe"),  FALSE)
chk("빈 문자열",     is_store_stub(""), FALSE)

cat(sprintf("\nRESULT: %d PASS / %d FAIL\n", pass, fail))
if (fail > 0L) quit(status = 1L)
