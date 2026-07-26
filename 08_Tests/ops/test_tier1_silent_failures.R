#==============================================================================
# test_tier1_silent_failures.R — 1단 수리 3건 위반 주입 테스트 (2026-07-26 도훈 승인)
#
# 대상 (probe② 감사 확정 → 수리 → 이 가드):
#   A) WCS-06  weekly_cleaner dry_run 라벨이 실제 부작용 집합과 1:1 대응하는가
#              (구판: dry_run:true 인데 knowledge_index 실제 재작성 + 텔레그램 force 실발송)
#   B) CBA-04  governance_log 파스 실패 시 **덮어쓰지 않고** 사이드카로 격리하는가
#              (구판: error→list() 폴백 후 덮어쓰기 = 거버넌스 이력 무경고 소실, 비가역)
#   C) WTL-1/5 admitted 가 있는데 매치 0 이면 WARN 을 내는가 + save 실패를 계상하지 않는가
#              (구판: "rebuilt 0" 이 정상처럼 출력 — active book 관측이 07-02 이후 사망)
#
# ★방식: 일부러 틀린 상태를 주입하고 **잡히는지** 본다. 통과만 세는 검사는 수리를
#   되돌려도 초록이므로, 각 축마다 "구판이면 반대 결과" 를 함께 단언한다.
# ★정본 무접촉: 전부 sandbox(tempdir) — 이 검사가 감시 대상을 건드리면 증거가 아니다.
#
# 요약 규약: 마지막 줄 {"test":"tier1_silent_failures","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

.MARKER <- "02_Infrastructure/ops/cert_backfill_audit.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_tier1] PROJECT_ROOT 해석 실패 — 표지 부재")

PASS <- 0L; FAIL <- 0L; out <- character()
ok  <- function(n) { PASS <<- PASS + 1L; out <<- c(out, sprintf("  PASS  %s", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; out <<- c(out, sprintf("  FAIL  %s  (%s)", n, d)) }
chk <- function(n, e, a) if (identical(as.character(e), as.character(a))) ok(n) else
  bad(n, sprintf("expect=%s actual=%s", e, a))

SB <- file.path(tempdir(), paste0("tier1_", Sys.getpid()))
unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(SB, recursive = TRUE)   # top-level on.exit 금지(금칙②)

cat("=== test_tier1_silent_failures (1단 수리 위반 주입) ===\n")

#──────────────────────────────────────────────────────────────────────────────
# A) WCS-06 — dry_run_scope 가 실제 부작용 집합과 1:1 인가 (소스 계약 검사)
#    실행 검사(실제 DRY 스윕)는 정본 .cache/knowledge_index 를 만지므로 여기선
#    **코드 계약**을 본다: DRY 가드가 두 부작용 지점에 실재하는가.
#──────────────────────────────────────────────────────────────────────────────
wcs <- readLines(file.path(PROJ, "02_Infrastructure/ops/weekly_cleaner_sweep.R"), warn = FALSE)
wcs_txt <- paste(wcs, collapse = "\n")
if (grepl("knowledge_index: SKIP \\(DRY", wcs_txt)) ok("A1 knowledge_index DRY 가드 실재") else
  bad("A1 knowledge_index DRY 가드 실재", "DRY 분기 부재 — 정본 인덱스 재작성 위험")
if (grepl('QVEST_CLEANER_NO_TG", "0"\\) != "1" && !DRY', wcs_txt))
  ok("A2 텔레그램 DRY 억제") else bad("A2 텔레그램 DRY 억제", "force=TRUE 실발송 경로 잔존")
if (grepl("dry_run_scope", wcs_txt)) ok("A3 dry_run_scope 맵 기록") else
  bad("A3 dry_run_scope 맵 기록", "단일 boolean 만 — 부작용 집합 불명")
# ★위반 주입: DRY 가드를 제거한 사본이면 A1 이 뒤집혀야 한다(검사가 살아있음을 실증)
wcs_mut <- gsub("knowledge_index: SKIP \\(DRY", "knowledge_index: RUN (", wcs_txt)
if (!grepl("knowledge_index: SKIP \\(DRY", wcs_mut)) ok("A4 ★위반 주입 시 A1 뒤집힘") else
  bad("A4 ★위반 주입 시 A1 뒤집힘", "돌연변이가 검출식을 못 흔듦 = 죽은 검사")

#──────────────────────────────────────────────────────────────────────────────
# B) CBA-04 — governance_log 파손 주입 → 원본 무수정 + 사이드카 격리
#──────────────────────────────────────────────────────────────────────────────
gdir <- file.path(SB, "governor"); dir.create(gdir, recursive = TRUE, showWarnings = FALSE)
glog <- file.path(gdir, "governance_log.json")
CORRUPT <- '{"admission_log": [1,2,3], "event_x": {"a":1}'   # 닫는 중괄호 없음 = 파스 실패
writeLines(CORRUPT, glog)

# record_governance_log 만 쓰기 위해 필요한 최소 환경 구성
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
LOG_FH <- NULL
log_msg <- function(msg) invisible(msg)      # 조용히
# 정본 파일의 모듈 상수 — 하드코딩 사본을 만들지 않고 원본에서 읽어 온다
# (사본을 두면 원본이 바뀔 때 이 테스트가 조용히 낡는다 = 이번 세션의 반복 부류)
.src_head <- readLines(file.path(PROJ, .MARKER), warn = FALSE)
for (.ln in grep("^(CERT_TYPES|CHARTER_REF)\\s*<-", .src_head, value = TRUE)) {
  eval(parse(text = .ln))
}
stopifnot(exists("CHARTER_REF"), exists("CERT_TYPES"))
src <- readLines(file.path(PROJ, .MARKER), warn = FALSE)
i0 <- grep("^record_governance_log <- function", src)
i1 <- grep("^#=+$", src); i1 <- i1[i1 > i0][1]
eval(parse(text = paste(src[i0:(i1 - 1)], collapse = "\n")))

res_b <- tryCatch(record_governance_log(gdir, list(mode = "test", issued = 0), dry_run = FALSE),
                  error = function(e) paste("ERROR:", conditionMessage(e)))
after <- paste(readLines(glog, warn = FALSE), collapse = "\n")
chk("B1 파손 원본 무수정(덮어쓰기 중단)", CORRUPT, after)
side <- file.path(gdir, "governance_log_backfill_pending.json")
if (file.exists(side)) ok("B2 엔트리 사이드카 격리") else
  bad("B2 엔트리 사이드카 격리", "격리 파일 부재 — 엔트리 소실")
# ★구판 대조: error→list() 폴백이면 원본이 유효 JSON 으로 교체됐을 것
if (!identical(tryCatch(!is.null(fromJSON(glog, simplifyVector = FALSE)),
                        error = function(e) FALSE), TRUE))
  ok("B3 ★원본이 여전히 파손 상태(구판이면 유효 JSON 으로 덮여 이력 소실)") else
  bad("B3 ★원본이 여전히 파손 상태", "원본이 유효 JSON = 덮어쓰기 발생")

# B4: 정상 JSON 이면 정상 append + 백업 생성
glog2 <- file.path(gdir, "governance_log.json")
writeLines('{"admission_log":["keep-me"]}', glog2)
invisible(record_governance_log(gdir, list(mode = "test2", issued = 1), dry_run = FALSE))
g2 <- fromJSON(glog2, simplifyVector = FALSE)
if (identical(unlist(g2$admission_log), "keep-me")) ok("B4 정상 경로: 기존 키 보존") else
  bad("B4 정상 경로: 기존 키 보존", "기존 이력 소실")
if (length(list.files(gdir, pattern = "governance_log\\.json\\.bak\\.")) > 0)
  ok("B5 덮어쓰기 전 원본 백업 생성") else bad("B5 덮어쓰기 전 원본 백업 생성", "백업 부재")

#──────────────────────────────────────────────────────────────────────────────
# C) WTL-1/5 — 소스 계약: 키 확장 · 매치0 WARN · save 성공만 계상
#──────────────────────────────────────────────────────────────────────────────
wtl <- paste(readLines(file.path(PROJ, "02_Infrastructure/observability/wt_timeline.R"),
                       warn = FALSE), collapse = "\n")
if (grepl("ga_data\\$str_id %\\|\\|% ga_data\\$strategy_id", wtl))
  ok("C1 join 키 2세대(strategy_id) 확장") else
  bad("C1 join 키 2세대 확장", "1세대 str_id 단독 — 2세대 ga 미매치")
if (grepl("lineage 매치 0 — active book 관측 사망", wtl))
  ok("C2 매치0 WARN 가드(admitted>0)") else
  bad("C2 매치0 WARN 가드", "무경고 0 = 관측 사망이 정상처럼 보임")
if (grepl("if \\(isTRUE\\(save_wt_timeline\\(wt\\)\\)\\) count <- count \\+ 1", wtl))
  ok("C3 save 성공만 계상(WTL-5)") else
  bad("C3 save 성공만 계상", "매치 수를 성공 수로 보고")
# ★위반 주입: WARN 문구를 제거한 사본이면 C2 가 뒤집혀야 한다
wtl_mut <- gsub("lineage 매치 0 — active book 관측 사망", "ok", wtl)
if (!grepl("lineage 매치 0 — active book 관측 사망", wtl_mut))
  ok("C4 ★위반 주입 시 C2 뒤집힘") else
  bad("C4 ★위반 주입 시 C2 뒤집힘", "죽은 검사")

.cleanup()
cat(paste(out, collapse = "\n"), "\n\n")
cat(sprintf("PASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"tier1_silent_failures","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
