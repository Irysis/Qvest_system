## ============================================================================
## test_wiring_map.R — 배선 지도 생성기 위반 주입 테스트 (2026-08-08 신설)
## ----------------------------------------------------------------------------
## 대상: 02_Infrastructure/ops/wiring_map_build.R
##
## ★왜 이 검사기가 특히 필요한가 — 생성기가 개발 중 **네 번 틀렸고 네 번 다 양성 대조가
##   잡았다**(정답을 미리 아는 표준 1건을 대조로 두지 않았으면 그럴듯한 초록이 나왔다):
##     ① 심볼 매치 과대계상(일반명 ym_of 로 무관 파일 16개 매치)
##     ② 자기참조(생성기 헤더·자기 산출물이 전 표준의 소비자로 계상 → orphan 3→0)
##     ③ 문서/데이터 언급을 배선으로 계상
##     ④ 재구현 축 미재현 (→ 발행 보류 상태)
##   지도가 틀리면 "배선 완료"라는 **거짓 초록**이 되므로, 계수 규칙을 픽스처로 고정한다.
##
## 방식: 임시 트리에 저장소 구조를 만들고 QM_ROOT 로 지정해 **원본 생성기를 그대로 구동**.
## 실행: Rscript 08_Tests/hooks/test_wiring_map.R
## ============================================================================
suppressWarnings(suppressMessages({ library(jsonlite) }))

## 앵커 1순위 = 자기가 실린 트리 (r-portability ④-b 러너 self-first)
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/") else ""
}, error = function(e) "")
PROJ <- ""
cands <- c(if (nzchar(.self)) normalizePath(file.path(dirname(.self), "..", ".."), winslash = "/", mustWork = FALSE),
           Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd())
for (c in cands) if (nzchar(c) && file.exists(file.path(c, "02_Infrastructure/hooks/qvest_hook_router.py"))) { PROJ <- c; break }
if (!nzchar(PROJ)) {
  cat('{"test":"wiring_map","pass":0,"fail":1,"total":1,"preflight":"no_root"}\n'); quit(status = 1L)
}
GEN <- file.path(PROJ, "02_Infrastructure/ops/wiring_map_build.R")
if (!file.exists(GEN)) {
  cat('{"test":"wiring_map","pass":0,"fail":1,"total":1,"preflight":"no_generator"}\n'); quit(status = 1L)
}

PASS <- 0L; FAIL <- 0L
ok <- function(cond, name, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

SBX <- file.path(tempdir(), paste0("wmap_", as.integer(Sys.time())))
wr <- function(rel, txt) {
  p <- file.path(SBX, rel); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(txt, p, useBytes = TRUE); p
}

## ── 픽스처: 저장소 구조 + 표준 3종 + 다양한 참조 형태 ──────────────────────
build_fixture <- function() {
  unlink(SBX, recursive = TRUE); dir.create(SBX, recursive = TRUE, showWarnings = FALSE)
  wr("02_Infrastructure/hooks/qvest_hook_router.py", "# marker")
  ## 표준 A — 코드 소비자 3(비검사) + 검사기 1  → wired
  wr("02_Infrastructure/contracts/std_alpha.R", c("alpha_fn <- function(x) x"))
  for (i in 1:3) wr(sprintf("02_Infrastructure/portfolio/consumer_%d.R", i),
                    c("source('02_Infrastructure/contracts/std_alpha.R')", "alpha_fn(1)"))
  wr("08_Tests/contract_regression/test_alpha.R", "source('02_Infrastructure/contracts/std_alpha.R')")
  ## 표준 B — 아무도 안 부름 → orphan
  wr("02_Infrastructure/contracts/std_orphan.R", c("orphan_fn <- function(x) x"))
  ## 표준 C — .md 문서와 .json 데이터만 이름 언급 → 배선 아님(orphan 이어야)
  wr("02_Infrastructure/contracts/std_doconly.R", c("doc_fn <- function(x) x"))
  wr("04_Research/01_reports/note.md", "std_doconly.R 을 참고할 것")
  wr("06_Registry/somemap.json", '{"ref":"std_doconly.R"}')
  ## 표준 D — 일반명 심볼을 무관 파일이 **직접 정의**(과대계상 함정 ①)
  wr("02_Infrastructure/contracts/std_generic.R", c("ym_of <- function(d) format(d, '%Y-%m')"))
  for (i in 1:5) wr(sprintf("04_Research/unrelated_%d.R", i),
                    c("ym_of <- function(d) format(d, '%Y-%m')", "ym_of(Sys.Date())"))
}

## ★r-portability 금칙 ①: Windows 에서 `system2(..., env=)` 는 환경변수가 아니라
##   **인자 주입**이다(실측: rc=5 · 출력 0바이트로 즉사). Sys.setenv 로 세우고 자식이 상속하게 한다.
run_gen <- function(extra = character(0)) {
  old <- Sys.getenv("QM_ROOT", unset = NA_character_)
  Sys.setenv(QM_ROOT = SBX)
  on.exit({ if (is.na(old)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old) }, add = TRUE)
  out <- suppressWarnings(system2("Rscript", shQuote(c(GEN, extra)), stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status"); if (is.null(rc)) rc <- 0L
  list(rc = rc, out = paste(out, collapse = "\n"))
}
readmap <- function() {
  p <- file.path(SBX, "06_Registry/wiring_map.json")
  if (!file.exists(p)) return(NULL)
  fromJSON(p, simplifyVector = TRUE)
}
getstd <- function(m, nm) {
  s <- m$standards
  if (is.null(s) || !nrow(s)) return(NULL)
  r <- s[s$standard == nm, , drop = FALSE]
  if (!nrow(r)) NULL else as.list(r[1, ])
}

cat("=== test_wiring_map (양성 대조 + 위반 주입) ===\n")
build_fixture()
r <- run_gen()
m <- readmap()
ok(!is.null(m), "A0 지도 생성됨", r$out)

if (!is.null(m)) {
  A <- getstd(m, "std_alpha.R"); B <- getstd(m, "std_orphan.R")
  C <- getstd(m, "std_doconly.R"); D <- getstd(m, "std_generic.R")

  ## A. 양성 대조 — 정답을 아는 표준이 정확히 그 수로 나와야 한다
  ok(!is.null(A) && A$n_consumers_nontest == 3,
     "A1 비검사 코드 소비자 3 정확", sprintf("(got %s)", if (is.null(A)) "NULL" else A$n_consumers_nontest))
  ok(!is.null(A) && A$status == "wired", "A2 status=wired")
  ok(!is.null(A) && grepl("tests:1", A$zones), "A3 검사기는 별도 존으로 분리(비검사에서 제외)",
     sprintf("(zones=%s)", if (is.null(A)) "NULL" else A$zones))

  ## B. orphan 검출 — 이 축이 죽으면 감사 전체가 무의미
  ok(!is.null(B) && B$status == "orphan", "B1 아무도 안 쓰는 표준 → orphan")

  ## C. 함정 ③ — 문서/데이터 언급은 배선이 아니다
  ok(!is.null(C) && C$n_consumers_nontest == 0 && C$status == "orphan",
     "C1 .md/.json 언급만 → 소비자 0 (배선 아님)",
     sprintf("(n=%s)", if (is.null(C)) "NULL" else C$n_consumers_nontest))

  ## D. 함정 ① — 같은 이름을 직접 정의한 무관 파일을 소비자로 세지 않는다
  ok(!is.null(D) && D$n_consumers_nontest == 0,
     "D1 일반명 심볼 자체정의 5건 → 소비자 0 (과대계상 차단)",
     sprintf("(n=%s)", if (is.null(D)) "NULL" else D$n_consumers_nontest))

  ## E. 자기참조 (함정 ②) — 생성기·자기 산출물이 소비자로 들어오면 안 된다
  allc <- paste(m$standards$consumers, collapse = ";")
  ok(!grepl("wiring_map_build\\.R|wiring_map\\.json", allc),
     "E1 생성기·자기 산출물이 소비자로 계상되지 않음")
}

## F. 드리프트 — 소비자를 끊으면 악화로 잡혀야 한다 (감지기 차단 실효)
run_gen("--set-baseline")
file.remove(file.path(SBX, "02_Infrastructure/portfolio/consumer_3.R"))
r2 <- run_gen()
m2 <- readmap()
A2 <- if (is.null(m2)) NULL else getstd(m2, "std_alpha.R")
ok(!is.null(A2) && A2$n_consumers_nontest == 2, "F1 소비자 제거가 계수에 반영",
   sprintf("(got %s)", if (is.null(A2)) "NULL" else A2$n_consumers_nontest))
ok(r2$rc == 2L, "F2 ★소비자 감소 → 드리프트 exit 2 (표준 우회 시작 감지)",
   sprintf("(rc=%s)", r2$rc))
ok(!is.null(m2) && length(m2$drift$consumers_decreased) > 0,
   "F3 드리프트 내역이 원장에 기록됨")

## G. 음성 통제 — 변화가 없으면 조용해야 한다 (무조건 경고하는 게 아님)
run_gen("--set-baseline")
r3 <- run_gen()
ok(r3$rc == 0L, "G1 변화 없으면 exit 0 (상시 경고 아님)", sprintf("(rc=%s)", r3$rc))

unlink(SBX, recursive = TRUE)
TOT <- PASS + FAIL
cat(sprintf("\nPASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"wiring_map","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOT))
if (FAIL > 0L) quit(status = 1L)
