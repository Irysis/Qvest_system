#==============================================================================
# test_wt_inflight_lock.R — WT in-flight 잠금 **차단 실효** 검사
#
# 검사 대상 = 02_Infrastructure/worktask/wt_inflight_lock.R
#
# ★설계 원칙 (도훈 지시 2026-08-08): "존재 = 배선 완료" 로 읽지 않는다.
#   이 저장소의 반복 계통이 정확히 그것이다 — v8.3 "in-flight 인덱싱" 은 **문장으로
#   존재**했고 `in_flight_since` 필드도 **실재**했지만, 그것을 읽는 코드가 0건이라
#   FQ-122 에서 두 alpha-research 실행이 나란히 돌았다.
#   ⇒ 여기서 재는 것은 "잠금 파일이 생기는가" 가 **아니라**
#      "잠금이 있는데 두 번째 실행이 진입하면 실제로 **멈추는가**" 다.
#
# 축:
#   A 기능 프로브 (검사기 자신이 죽지 않았는지)
#   B 정상 취득
#   C ★위반 주입 — 잠긴 WT 에 2차 취득 → **stop 해야 한다** (핵심 축)
#   D assert 토큰 소유권
#   E release 토큰 검증
#   F stale 승계 (6h) + 비-stale 은 여전히 차단
#   G ★fail-open 차단 — owner.json 결손을 free 로 내려앉히지 않는가
#   H ★표기 갈림 — WT_D... 와 WT-D... 가 **같은 잠금**인가
#   I ★진짜 2번째 OS 프로세스 (모의가 아닌 실제 동시성)
#   J ★돌연변이 — 가드를 무력화하면 C 가 실제로 빨개지는가 (검출력 실증)
#   K escalate 원장 기록
#   L 사후 검거 wt_inflight_audit()
#
# 실제 mailbox 는 건드리지 않는다 — 전부 임시 루트 위에서 돈다.
#==============================================================================
suppressMessages(library(jsonlite))

## 앵커는 self-first — env-first 면 worktree 배터리가 main 을 검사한다(2026-08-02 실사고).
## ★`sys.frame(1)$ofile` 만 보는 구판 관용구는 **source() 일 때만** 자기 경로를 안다.
##   `Rscript <file>` 로 돌면 NULL 이라 조용히 env 폴백 → main 을 검사한다.
##   (2026-08-08 실측: 그 상태로 worktree 신규 가드를 "19/19 통과" 로 오독할 뻔했다.
##    통과한 것은 main 의 구판 코드였다.) 두 실행 경로를 모두 덮는다.
.self_path <- function() {
  f <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(f)) return(normalizePath(f, winslash = "/", mustWork = FALSE))
  a <- commandArgs(trailingOnly = FALSE)
  m <- a[substr(a, 1, 7) == "--file="]
  if (length(m)) return(normalizePath(substring(m[1], 8), winslash = "/", mustWork = FALSE))
  NA_character_
}
MARKER <- "02_Infrastructure/worktask/wt_inflight_lock.R"
ROOT <- NA_character_
self <- .self_path()
if (!is.na(self)) {
  cand <- normalizePath(file.path(dirname(self), "..", ".."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, MARKER))) ROOT <- cand
}
if (is.na(ROOT)) {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(gsub("\\\\", "/", v), MARKER))) { ROOT <- gsub("\\\\", "/", v); break }
  }
}
if (is.na(ROOT)) stop("[test] 프로젝트 루트를 해석하지 못했다 — 검사 불능은 통과가 아니다.")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
MODULE <- file.path(ROOT, "02_Infrastructure/worktask/wt_inflight_lock.R")
source(MODULE)

PASS <- 0L; FAIL <- 0L
ok <- function(label, cond, note = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", label)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", label, note)) }
}
threw <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")
errmsg <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))

# ── 임시 프로젝트 루트 픽스처 ────────────────────────────────────────────────
TR <- file.path(tempdir(), sprintf("wtl_fixture_%d", Sys.getpid()))
WT <- "WT-D20260101_001"
setup <- function() {
  unlink(TR, recursive = TRUE, force = TRUE)
  dir.create(file.path(TR, "qepm", "mailbox", "worktask", WT), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(TR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  invisible(TR)
}
LD <- function(id = WT) file.path(TR, "qepm/mailbox/worktask", id, ".inflight.lock")

cat("=== wt_inflight_lock 차단 실효 검사 ===\n")

## ── A. 기능 프로브 ───────────────────────────────────────────────────────────
ok("A1 함수 존재", all(vapply(c("wt_acquire_inflight", "wt_assert_inflight", "wt_release_inflight",
                               "wt_inflight_state", "wt_inflight_list", "wt_inflight_audit"),
                             function(f) is.function(get0(f)), logical(1))))
setup()
ok("A2 픽스처 mailbox 성립", dir.exists(file.path(TR, "qepm/mailbox/worktask", WT)))
ok("A3 잠금 없는 WT 는 held=FALSE", isFALSE(wt_inflight_state(WT, root = TR)$held))

## ── B. 정상 취득 ─────────────────────────────────────────────────────────────
cl1 <- wt_acquire_inflight(WT, agent = "alpha-research", root = TR)
ok("B1 status=ACQUIRED", identical(cl1$status, "ACQUIRED"))
ok("B2 잠금 디렉토리 생성", dir.exists(LD()))
ok("B3 owner.json 판독 가능", {
  o <- fromJSON(file.path(LD(), "owner.json")); identical(as.character(o$agent), "alpha-research")
})
ok("B4 토큰 발급", nzchar(cl1$claim_token %||% ""))
ok("B5 state held=TRUE", isTRUE(wt_inflight_state(WT, root = TR)$held))

## ── C. ★위반 주입: 2차 실행 진입 시도 = FQ-122 의 형태 ──────────────────────
##    같은 agent 이름으로 온다는 것이 사건의 핵심이다(양쪽 다 alpha-research).
ok("C1 ★2차 취득이 **stop 한다**",
   threw(wt_acquire_inflight(WT, agent = "alpha-research", root = TR)))
m <- errmsg(wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
ok("C2 사유가 in-flight 차단임을 확인", grepl("이미 in-flight", m, fixed = TRUE),
   paste0("(실제: ", substr(m, 1, 70), ")"))
ok("C3 escalate 안내 포함", grepl("Q-Lead escalate", m, fixed = TRUE))
ok("C4 다른 agent 이름이어도 차단",
   threw(wt_acquire_inflight(WT, agent = "risk-research", root = TR)))
ok("C5 차단 후에도 원 소유자 토큰 불변",
   identical(as.character(wt_inflight_state(WT, root = TR)$owner$claim_token), cl1$claim_token))
ok("C6 on_conflict='return' 은 BLOCKED 반환(검사용)", {
  r <- suppressMessages(wt_acquire_inflight(WT, agent = "x", on_conflict = "return", root = TR))
  identical(r$status, "BLOCKED")
})

## ── D. assert = 같은 실행의 후속 스크립트 ────────────────────────────────────
ok("D1 올바른 토큰은 통과", !threw(wt_assert_inflight(WT, cl1$claim_token, root = TR)))
ok("D2 토큰 없이도 '잠금 존재'는 통과", !threw(wt_assert_inflight(WT, root = TR)))
ok("D3 ★틀린 토큰은 stop", threw(wt_assert_inflight(WT, "bogus-token", root = TR)))
ok("D4 틀린 토큰 사유가 토큰 불일치", grepl("토큰 불일치", errmsg(wt_assert_inflight(WT, "bogus", root = TR)), fixed = TRUE))

## ── E. release ───────────────────────────────────────────────────────────────
ok("E1 토큰 없이 해제 거부", threw(wt_release_inflight(WT, root = TR)))
ok("E2 틀린 토큰 해제 거부", threw(wt_release_inflight(WT, "bogus", root = TR)))
ok("E3 force 인데 reason 없으면 거부", threw(wt_release_inflight(WT, force = TRUE, root = TR)))
ok("E4 거부 3회 후에도 잠금 유지", dir.exists(LD()))
ok("E5 올바른 토큰 해제 성공", !threw(suppressMessages(wt_release_inflight(WT, cl1$claim_token, root = TR))))
ok("E6 해제 후 디렉토리 소멸", !dir.exists(LD()))
ok("E7 해제 후 재취득 가능", {
  r <- suppressMessages(wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
  identical(r$status, "ACQUIRED")
})
suppressMessages(wt_release_inflight(WT, wt_inflight_state(WT, root = TR)$owner$claim_token,
                                     root = TR))

## ── F. stale 승계 ────────────────────────────────────────────────────────────
setup()
cl2 <- suppressMessages(wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
backdate <- function(hours) {
  op <- file.path(LD(), "owner.json"); o <- fromJSON(op)
  o$started_at <- format(Sys.time() - hours * 3600, "%Y-%m-%dT%H:%M:%S%z")
  write_json(o, op, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}
backdate(1)
ok("F1 1h 경과 = 아직 live → 차단 유지",
   threw(wt_acquire_inflight(WT, agent = "alpha-research", root = TR)))
backdate(7)
ok("F2 7h 경과 = stale → 승계 허용", {
  r <- suppressWarnings(suppressMessages(
    wt_acquire_inflight(WT, agent = "alpha-research-2", root = TR)))
  identical(r$status, "TAKEOVER_STALE")
})
ok("F3 승계 시 warning 발화", {
  backdate(7)
  ws <- character(0)
  withCallingHandlers(suppressMessages(wt_acquire_inflight(WT, agent = "a3", root = TR)),
                      warning = function(w) { ws <<- c(ws, conditionMessage(w)); invokeRestart("muffleWarning") })
  any(grepl("stale 잠금 승계", ws, fixed = TRUE))
})
ok("F4 승계 후 소유자 교체", identical(as.character(wt_inflight_state(WT, root = TR)$owner$agent), "a3"))
ok("F5 승계 기록에 takeover_of 남음",
   nzchar(as.character(wt_inflight_state(WT, root = TR)$owner$takeover_of %||% "")))
ok("F6 stale_hours 상향 시 같은 나이도 차단(문턱 실효)", {
  backdate(7)
  threw(wt_acquire_inflight(WT, agent = "a4", stale_hours = 24, root = TR))
})

## ── G. ★fail-open 차단 — owner.json 결손 ────────────────────────────────────
##   "판독 불가 = 잠금 없음" 으로 떨어뜨리면 그게 곧 이 사건의 재발이다.
setup()
suppressMessages(wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
unlink(file.path(LD(), "owner.json"), force = TRUE)                       # ← 위반 주입
st <- wt_inflight_state(WT, root = TR)
ok("G1 owner.json 없어도 held=TRUE", isTRUE(st$held))
ok("G2 owner_readable=FALSE 로 구분 표기", isFALSE(st$owner_readable))
ok("G3 ★그래도 2차 취득은 차단", threw(wt_acquire_inflight(WT, agent = "x", root = TR)))
ok("G4 나이를 NA 로 방치하지 않음(mtime 폴백)", !is.na(st$age_hours))

## ── H. ★표기 갈림 (WT_D vs WT-D) — 잠금 우회 경로 ──────────────────────────
##   2026-08-02 에 이 저장소는 이미 두 표기가 갈려 산출물 13파일을 '0건'으로 오판했다.
##   두 표기가 서로 다른 잠금을 잡으면 **잠금이 있는 채로 병렬 실행이 성립한다.**
setup()
suppressMessages(wt_acquire_inflight("WT-D20260101_001", agent = "alpha-research", root = TR))
ok("H1 ★언더스코어 표기로도 같은 잠금에 막힌다",
   threw(wt_acquire_inflight("WT_D20260101_001", agent = "alpha-research", root = TR)))
ok("H2 두 표기의 잠금 경로가 동일",
   identical(wt_inflight_state("WT_D20260101_001", root = TR)$lock_dir,
             wt_inflight_state("WT-D20260101_001", root = TR)$lock_dir))

## ── I. ★진짜 2번째 OS 프로세스 (모의 아님) ──────────────────────────────────
##   같은 R 세션 안의 재호출은 "함수가 stop 한다"만 보여준다. 실제 사건은 **다른
##   프로세스**였으므로, 원자성(dir.create)이 프로세스 경계에서도 성립하는지 잰다.
##   ⚠ system2(env=) 금지(r-portability 금칙①) — 루트를 스크립트에 리터럴로 박는다.
RSCRIPT <- file.path(R.home("bin"), "Rscript")
if (!file.exists(RSCRIPT)) RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
child <- file.path(TR, "child_acquire.R")
writeLines(c(
  sprintf('setwd("%s")', ROOT),
  sprintf('source("%s")', gsub("\\\\", "/", MODULE)),
  sprintf('r <- wt_acquire_inflight("%s", agent="alpha-research", on_conflict="stop", root="%s")',
          WT, gsub("\\\\", "/", TR))
), child, useBytes = TRUE)
if (file.exists(RSCRIPT)) {
  out <- suppressWarnings(system2(RSCRIPT, child, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  ok("I1 ★별도 프로세스의 취득이 실패 종료", !is.null(status) && status != 0L,
     paste0("(status=", status %||% "NULL", ")"))
  ok("I2 실패 사유가 in-flight 차단", any(grepl("이미 in-flight", out, fixed = TRUE)),
     paste0("(출력: ", substr(paste(out, collapse = " | "), 1, 90), ")"))
  ok("I3 자식 실패 후에도 원 잠금 온전", dir.exists(LD()))
} else {
  ok("I1 Rscript 미발견 — 프로세스 축 실행 불가", FALSE, "(SKIP 아님: 검사 불능은 실패)")
}

## ── J. ★돌연변이: 가드를 끄면 C 가 실제로 빨개지는가 (검출력 실증) ──────────
##   C1 이 초록인 이유가 "가드가 발화해서" 인지 "다른 이유로 stop 나서" 인지 가른다.
setup()
src <- paste(readLines(MODULE, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
NEEDLE <- "isTRUE(suppressWarnings(dir.create(ld, showWarnings = FALSE)))"
ok("J1 돌연변이 대상 줄이 실재 (needle 유효)", grepl(NEEDLE, src, fixed = TRUE))
mut_src <- sub(NEEDLE, "isTRUE({dir.create(ld, showWarnings=FALSE, recursive=TRUE); TRUE})",
               src, fixed = TRUE)
ok("J2 돌연변이가 실제로 적용됨(무변경 아님)", !identical(src, mut_src))
mut_path <- file.path(TR, "mutant_lock.R")
writeLines(mut_src, mut_path, useBytes = TRUE)
menv <- new.env(parent = globalenv())
source(mut_path, local = menv)
suppressMessages(menv$wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
ok("J3 ★가드 무력화판은 2차 취득을 **통과시킨다** (⇒ C1 의 초록은 가드 덕분)",
   !threw(suppressMessages(menv$wt_acquire_inflight(WT, agent = "alpha-research", root = TR))))
ok("J4 원본 모듈은 같은 상황에서 여전히 차단",
   threw(wt_acquire_inflight(WT, agent = "alpha-research", root = TR)))

## ── K. escalate 원장 ────────────────────────────────────────────────────────
led <- file.path(TR, "06_Registry", "inflight_conflicts.jsonl")
ok("K1 원장 파일 생성", file.exists(led))
recs <- lapply(readLines(led, warn = FALSE, encoding = "UTF-8"),
               function(l) tryCatch(fromJSON(l), error = function(e) NULL))
recs <- Filter(Negate(is.null), recs)
evs <- vapply(recs, function(r) as.character(r$event %||% ""), character(1))
ok("K2 BLOCKED 이벤트 기록", any(evs == "BLOCKED"))
ok("K3 ACQUIRED 이벤트 기록", any(evs == "ACQUIRED"))
ok("K4 모든 줄이 유효 JSON", length(recs) == length(readLines(led, warn = FALSE)))

## ── L. 사후 검거 (acquire 를 아예 안 부른 실행) ─────────────────────────────
setup()
## 잠금 없이 산출물만 생긴 WT = 규약 미경유 실행의 흔적
write_json(list(x = 1), file.path(TR, "qepm/mailbox/worktask", WT, "alpha_package.json"),
           auto_unbox = TRUE)
aud <- wt_inflight_audit(since = format(Sys.time() - 3600, "%Y-%m-%dT%H:%M:%S"), root = TR)
ok("L1 ★잠금 기록 없는 산출물 WT 를 적발", nrow(aud) >= 1L && WT %in% aud$wt_id)
suppressMessages(wt_acquire_inflight(WT, agent = "alpha-research", root = TR))
aud2 <- wt_inflight_audit(since = format(Sys.time() - 3600, "%Y-%m-%dT%H:%M:%S"), root = TR)
ok("L2 acquire 기록 후에는 미적발(오탐 아님)", !(WT %in% (aud2$wt_id %||% character(0))))

## ── M. list 조회면 ──────────────────────────────────────────────────────────
lst <- wt_inflight_list(root = TR)
ok("M1 보유 잠금이 목록에 나온다", nrow(lst) >= 1L && WT %in% lst$wt_id)

unlink(TR, recursive = TRUE, force = TRUE)
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"wt_inflight_lock","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
