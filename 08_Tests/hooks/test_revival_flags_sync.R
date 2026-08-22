#!/usr/bin/env Rscript
#==============================================================================
# test_revival_flags_sync.R — 주입 사본(failure_revival_flags) 동기화 2층 검증
#
# 배경 (2026-08-20 실사고):
#   status=distilled 카드 4장의 stale frontier 를 고쳤는데 **주입면에는 구 문장이 그대로 나갔다**.
#   경로가 하나 더 있었기 때문 — .cache/failure_revival_flags.json 이 frontier *사본*을 들고
#   있고 axiom_context_inject 의 '부활 발화' 블록이 그 사본을 주입한다.
#   그 파일 갱신자는 morning_briefing.sh:99 인데 morning_run.sh:195 가 **주말엔 skip** 하므로
#   카드 수정과 주입 반영 사이에 최대 3~4일 지연이 난다(08-13 사본이 08-20 까지 주입된 실사례).
#
# 2층으로 막았고 이 검사가 둘 다 고정한다:
#   [예방] refine_distilled 가 정본 수정 시 파생을 동기 갱신 (실측 0.82초)
#   [관측] memory_knowledge_health WARN_11 이 mtime 역전을 잡는다
#   ★한 층만 있으면 부족하다 — 예방만이면 approve_proposed·수동편집 경로가 남고,
#     관측만이면 매번 사람이 고쳐야 한다.
#
# 축:
#   [A] 예방 — 사본을 오염시킨 뒤 refine_distilled 1회로 따라오는가 (조작 선행검증 포함)
#   [B] 관측 정상 — 사본이 정본보다 새것이면 WARN_11 무발화
#   [C] 관측 위반 — 정본이 더 새것이면 WARN_11 발화 (판정 근거 = mtime 역전, 절대시간 아님)
#   [D] 배선 잔존 — refine_distilled 본문이 revival 갱신을 실제로 호출하는가(주석만 아님)
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressWarnings(suppressMessages(library(jsonlite)))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
ng <- function(m) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s\n", m)) }

FL   <- file.path(ROOT, ".cache", "failure_revival_flags.json")
DK   <- file.path(ROOT, "06_Registry", "distilled_knowledge.json")
HLTH <- file.path(ROOT, "02_Infrastructure", "memory", "memory_knowledge_health.R")
DIST <- file.path(ROOT, "02_Infrastructure", "axiom", "distilled.R")

# 원상 복구용 백업 — 이 검사는 실파일을 건드리므로 반드시 되돌린다.
# ★2026-08-22 수리 (감사 HLT-4/HLT-3): 구판은 (a) 최상위 on.exit 를 썼는데 그건
#   r-portability 금칙② — **함수 프레임이 없어 조용히 no-op** 이라 복구가 dead code 였고
#   (물증: .cache/_test_frf_sync_backup.json 이 회차마다 잔존), (b) 백업 대상이 사본(FL)
#   뿐이라 이 검사가 refine_distilled 로 덮어쓴 **실카드의 provenance**(refined_by/at)가
#   ②Distilled 계층에 그대로 박혔다(실측: DIST-AR-001.refined_by="test_revival_flags_sync").
#   ⇒ 대체는 규칙 정본이 지정한 reg.finalizer(globalenv(), onexit=TRUE) 이고,
#     백업 범위를 사본 + **대상 카드 파일**로 넓힌 뒤 파생 인덱스를 재생성해 정합을 되돌린다.
BK      <- file.path(ROOT, ".cache", "_test_frf_sync_backup.json")
CARD_BK <- file.path(ROOT, ".cache", "_test_frf_card_backup.json")
CARD_OF <- function(id) file.path(ROOT, "qepm", "memory", "axioms", "distilled",
                                  paste0(id, ".json"))
.card_path <- NA_character_          # [A] 축이 대상 확정 시 채운다
if (file.exists(FL)) file.copy(FL, BK, overwrite = TRUE)
restore <- function() {
  if (file.exists(BK)) file.copy(BK, FL, overwrite = TRUE)
  # 카드 provenance 원복 + 파생 인덱스 재생성(인덱스는 카드에서 결정적으로 재빌드된다)
  if (!is.na(.card_path) && file.exists(CARD_BK)) {
    file.copy(CARD_BK, .card_path, overwrite = TRUE)
    try(suppressWarnings(suppressMessages(env$rebuild_distilled_index(verbose = FALSE))),
        silent = TRUE)
  }
}
invisible(reg.finalizer(globalenv(),
                        function(e) { restore(); unlink(c(BK, CARD_BK)) },
                        onexit = TRUE))

fr_of <- function(id) {
  f <- tryCatch(fromJSON(FL, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(f)) return(NA_character_)
  for (x in f$fired %||% list()) if (identical(x$dist_id, id)) return(as.character(x$frontier)[1])
  NA_character_
}
health_warn11 <- function() {
  out <- suppressWarnings(system2("Rscript", shQuote(HLTH), stdout = TRUE, stderr = TRUE))
  any(grepl("WARN_11_revival_flags_stale", out, fixed = TRUE))
}

cat("== [D] 배선 잔존 (주석이 아니라 호출) ==\n")
dsrc <- readLines(DIST, warn = FALSE, encoding = "UTF-8")
i_ref <- grep("^refine_distilled <- function", dsrc)
if (!length(i_ref)) {
  ng("refine_distilled 정의 미발견 — 판정 불가")
} else {
  body <- dsrc[i_ref[1]:min(i_ref[1] + 60, length(dsrc))]
  code <- body[!grepl("^\\s*#", body)]                    # 주석 제외 — '주석만 있고 호출 없음' 방지
  if (any(grepl("revival_monitor_run", code, fixed = TRUE)))
    ok("refine_distilled 본문이 revival_monitor_run 을 호출(주석 아님)") else
    ng("배선 소실 — 주석만 남고 호출이 없다")
}

cat("== [A] 예방 — 정본 수정이 사본을 끌고 오는가 ==\n")
src <- suppressWarnings(suppressMessages(source(DIST, local = new.env())))
env <- new.env(); suppressWarnings(suppressMessages(sys.source(DIST, envir = env)))
dk <- fromJSON(DK, simplifyVector = FALSE)
target <- NULL
for (e in dk$entries) if (identical(e$status, "distilled") && !is.na(fr_of(e$dist_id))) { target <- e; break }
if (is.null(target)) {
  ng("[선행검증] 발화 중인 distilled 카드 없음 — 이 축 판정 불가")
} else {
  ok(sprintf("[선행검증] 대상 카드 %s (발화 중)", target$dist_id))
  .card_path <- CARD_OF(target$dist_id)          # 복구 범위에 실카드 편입
  if (file.exists(.card_path)) file.copy(.card_path, CARD_BK, overwrite = TRUE)
  f <- fromJSON(FL, simplifyVector = FALSE)
  for (k in seq_along(f$fired))
    if (identical(f$fired[[k]]$dist_id, target$dist_id))
      f$fired[[k]]$frontier <- "ZZSTALE_SYNC_TEST"
  write_json(f, FL, pretty = TRUE, auto_unbox = TRUE, null = "null")
  if (grepl("ZZSTALE_SYNC_TEST", fr_of(target$dist_id), fixed = TRUE))
    ok("[선행검증] 사본 오염이 실제로 적용됨") else
    ng("[선행검증] 오염 미적용 — 판정 불가")
  invisible(suppressWarnings(suppressMessages(
    env$refine_distilled(target$dist_id,
                         statement_refined = target$statement_refined,
                         frontier = target$frontier,
                         retry_condition = target$retry_condition,
                         refined_by = "test_revival_flags_sync"))))
  if (!grepl("ZZSTALE_SYNC_TEST", fr_of(target$dist_id) %||% "", fixed = TRUE))
    ok("재정제 1회로 사본이 정본을 따라옴 (지연 원천 제거)") else
    ng("사본이 여전히 오염 — 동기화 미작동")
}

cat("== [B]/[C] 관측 — WARN_11 양방향 ==\n")
Sys.setFileTime(FL, Sys.time())          # 사본을 최신으로
Sys.sleep(1)
if (!health_warn11()) ok("정상(사본이 더 새것) — WARN_11 무발화") else
  ng("정상인데 WARN_11 발화 — 오탐")
Sys.setFileTime(DK, Sys.time() + 5)      # 정본을 더 새것으로 = mtime 역전
if (health_warn11()) ok("위반(정본이 더 새것) — WARN_11 발화") else
  ng("mtime 역전인데 무발화 — 검출력 사망")
Sys.setFileTime(FL, Sys.time() + 10)     # 복구
if (!health_warn11()) ok("복구 후 무발화 (자기치유 확인)") else
  ng("복구했는데 계속 발화")

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", PASS, FAIL))
cat(sprintf("{\"test\":\"revival_flags_sync\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
