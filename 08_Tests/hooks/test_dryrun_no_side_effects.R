## test_dryrun_no_side_effects.R — 억제 플래그의 **행동 검사** 픽스처 (FQ-127 F7)
##
## 왜: 2026-08-10 하루에 자유 형식 패턴 감사가 **3/3 실패**했다
##   (Q2 '즉시가능 49건' 과다 · C1 'base 미명시 24.9%' 표본 5/5 오분류 ·
##    F5 '거짓보고 8건' 중 3/4가 '갱신 **생략**' 을 부정어째 잡은 오탐).
##   ⇒ 대안 3종 중 ③**행동 검사**: 문구를 읽지 않고 **실제 부작용이 없는지**를 본다.
##   억제 플래그(`dry_run`/`write_marker`/`apply`…)의 계약은 "말" 이 아니라 "안 쓴다" 이므로,
##   **감시 경로의 상태 스냅샷 전후 비교**가 정본 검사다.
##
## ★이 파일은 **픽스처 시연**이다: `assert_no_side_effects()` 를 다른 계약에 이식하는 것이 목적.
## ★검사 사망 통제 필수 — 픽스처가 "변화 없음" 만 말할 줄 알면 무용하다.
##   그래서 **일부러 규약을 어기는 함수**(플래그 무시하고 쓰는)를 주입해 검거되는지 본다.
suppressPackageStartupMessages({ library(jsonlite) })
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash="/", mustWork=FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
CR <- file.path(.root, "02_Infrastructure/contracts/close_round.R")
if (!file.exists(CR)) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand)) { .root <- cand; CR <- file.path(cand, "02_Infrastructure/contracts/close_round.R") }
}
if (!file.exists(CR)) stop(sprintf("계약 미발견: %s (러너 위치 문제이지 계약 실패 아님)", CR))

PASS <- 0L; FAIL <- 0L
.m1 <- function(x){x<-as.character(x); if(!length(x)) "" else x[1]}
ok  <- function(n,m=""){PASS<<-PASS+1L; cat(sprintf("  PASS: %s%s\n", n, if(nzchar(.m1(m))) paste0(" — ",.m1(m)) else ""))}
bad <- function(n,m=""){FAIL<<-FAIL+1L; cat(sprintf("  FAIL: %s%s\n", n, if(nzchar(.m1(m))) paste0(" — ",.m1(m)) else ""))}
chk <- function(n,c,m="") if (isTRUE(c)) ok(n,m) else bad(n,m)

## ── 픽스처 ────────────────────────────────────────────────────────────────
#' 감시 경로의 상태 스냅샷 — **신규 생성도 잡도록** 부재를 명시적으로 표현한다
#'   (부재를 NA 로 두면 '변화 없음' 과 섞인다 — 오늘 반복된 '결측≠해당없음' 규약)
snap <- function(paths) lapply(paths, function(p) {
  if (!file.exists(p)) return(list(exists = FALSE))
  list(exists = TRUE, size = file.size(p), mtime = file.mtime(p),
       nline = tryCatch(length(readLines(p, warn = FALSE)), error = function(e) NA_integer_))
})
#' 억제 플래그 하 실행이 **감시 경로를 하나도 건드리지 않았는지** 판정
#' @return list(clean=logical, changed=character) — 변한 경로를 이름으로 돌려준다
assert_no_side_effects <- function(expr, paths) {
  before <- snap(paths)
  force(expr)
  after <- snap(paths)
  changed <- paths[!vapply(seq_along(paths), function(i) identical(before[[i]], after[[i]]), logical(1))]
  list(clean = length(changed) == 0L, changed = changed)
}

cat("\n[A] 픽스처 자체 — 규약을 지키는 함수 (양성 대조)\n")
tf <- file.path(tempdir(), "f7_good.txt"); unlink(tf)
good <- function(dry_run = FALSE) { if (!dry_run) cat("x\n", file = tf, append = TRUE); invisible(TRUE) }
r <- assert_no_side_effects(good(dry_run = TRUE), tf)
chk("A1_good_dryrun_clean", isTRUE(r$clean), "플래그를 지키면 감시 경로 무변화 → clean")
chk("A2_file_absent", !file.exists(tf), "드라이런이므로 파일 자체가 생기지 않았다")

cat("\n[B] 위반 주입 — 플래그를 **무시하고 쓰는** 함수가 검거되는가 (검사 사망 통제)\n")
tb <- file.path(tempdir(), "f7_bad.txt"); unlink(tb)
badf <- function(dry_run = FALSE) { cat("x\n", file = tb, append = TRUE); invisible(TRUE) }  # 플래그 무시
r2 <- assert_no_side_effects(badf(dry_run = TRUE), tb)
chk("B1_violation_caught", isFALSE(r2$clean), "★플래그를 무시하고 **신규 생성**하면 검거된다")
chk("B2_names_the_path", identical(r2$changed, tb), "어느 경로가 변했는지 이름으로 돌려준다")

cat("\n[C] 기존 파일에 append 하는 위반도 잡히는가 (신규 생성만 잡으면 반쪽)\n")
tc <- file.path(tempdir(), "f7_exist.txt"); writeLines("seed", tc)
badf2 <- function(dry_run = FALSE) { cat("y\n", file = tc, append = TRUE); invisible(TRUE) }
r3 <- assert_no_side_effects(badf2(dry_run = TRUE), tc)
chk("C1_append_caught", isFALSE(r3$clean), "기존 파일 append 도 검거(size/nline 변화)")
r4 <- assert_no_side_effects(invisible(NULL), tc)
chk("C2_noop_clean", isTRUE(r4$clean), "아무것도 안 하면 clean — 오탐 없음")

cat("\n[D] 실전 적용 — close_round(write_marker=FALSE) 가 원장을 안 건드리는가\n")
suppressMessages(source(CR))
## ★감시 경로는 **계약 자신의 루트 해석기**로 잡는다. 초판은 검사 파일 위치(.root)를 썼는데
##   `.cache` 는 main 루트의 **심볼릭 링크**라 worktree 엔 없다 ⇒ 없는 경로를 보고 '변화 없음' =
##   **공허한 PASS**(오늘 반복된 '빈 결과 = 합격'). D2 가드가 그걸 잡아 이 수리가 나왔다.
cr_root <- tryCatch(.cr_root(), error = function(e) .root)
watch <- c(file.path(cr_root, ".cache/last_round_closure.json"),
           file.path(cr_root, ".cache/round_closures.jsonl"))
cat(sprintf("  감시 경로 루트: %s\n", cr_root))
r5 <- assert_no_side_effects(
  suppressMessages(close_round(
    round_id = "TEST_f7_dryrun", verdict_type = "capability_established",
    mechanism_diagnosis = "F7 행동 검사용 더미 기전 진단 — 20자 요건 충족 본문.",
    next_probes = c("p1","p2"), consumer_surfaces = "c", frontier_update = "f",
    live_trigger = "t", layer = "test", evidence_refs = "e.json",
    write_marker = FALSE)), watch)
chk("D1_close_round_dryrun_clean", isTRUE(r5$clean),
    sprintf("write_marker=FALSE 가 **실제로** 원장을 안 건드린다%s",
            if (!r5$clean) paste0(" — 변한 경로: ", paste(basename(r5$changed), collapse=", ")) else ""))
chk("D2_watch_paths_meaningful", any(vapply(watch, file.exists, logical(1))),
    "감시 경로 중 최소 1개가 실재 — 없는 경로만 보면 검사가 공허하다")

cat("\n[E] 픽스처의 한계 명시 (과신 방지)\n")
chk("E1_only_watched_paths", TRUE,
    "★감시 경로 **밖**의 부작용(DB·네트워크·전역변수)은 못 본다 — 경로 목록이 검사의 시야다")
chk("E2_no_text_read", TRUE,
    "★문구를 전혀 읽지 않는다 — 오늘 3/3 실패한 패턴 감사의 대체재인 이유")

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"dryrun_no_side_effects","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS+FAIL))
if (FAIL > 0L) quit(status = 1L)
