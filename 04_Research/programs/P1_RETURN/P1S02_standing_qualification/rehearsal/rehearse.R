#!/usr/bin/env Rscript
## P1S02 등록 전 리허설(판단 T1 C-20261111-085 · 격리 교차 점검 v1 · BUILD_EDITION2.md S5 · 2026-11-12)
##   목적: 판 2 의 측정 · 판정 경로(실제 셀 워커 → 러너 → 측정 관문(신선도 · GPU · 기저 정합) → 판정 전 점검 → 칸 평가 패킷 · β-통제 알파 →
##         judge → 판정 원장 → 보고 드라이런 → 상태 줄)를 싼 CPU 월말 격자 점수 엔진(rehearsal/engine/RP_REHEARSAL_MOM121 · 12-1 모멘텀)으로
##         격리해 한 번 끝까지 지난다. DNN 시드로 처음 지나면 결함 하나가 새 판 + GPU 재측정이 된다 — 그 전에 싼 엔진으로 지난다. 리서치 산출이 아니다.
##   값: 성과 값은 찍지도 요약에 싣지도 않는다 — 통과 여부 · 유한 여부 · 개수 · τ_D 이전 날짜 · 상태 문자열만. 판정 · 보고 원문은 out/<run>/ 파일에만.
##   격리: 사전등록 · 상설 원장 = RC_SA_ROOT(out/<run>/sa) · 등록부 = 실제 등록부 사본(out/<run>/iso) · 판단 원장 = 스텁(P1 리뷰 스텁) ·
##         리뷰 뿌리 = out/<run>/iso/rv · 판 폴더 = out/<run>/<리허설 판 id> · check_git = FALSE · run_tests = FALSE · QVEST_TG_DRY_RUN = 1 · 보고 send = FALSE.
##         실제 등록부 · 상설 원장(판 1 · 판 2) · 판 폴더(판 1 · 판 2 의 rehearsal/ 밖) · 결과 원장 · GPU 임대 · 코어 출시 기록 = 앞뒤 md5 대조 ·
##         다른 세션이 쓰는 공유 원장(판단 · 결정 · 재개) = 리허설 표식 없음 대조. 워커 산출(stage_artifacts/replication/…)은 경로만 보고한다(지우지 않는다).
##   신선도: 실제 관문을 먼저 지난다. 낡음이면 측정 없이 data_stale · 원장 무기록이어야 한다(음성 대조). --inject-fresh 일 때만 주입 함수로 한 번 더 잰다
##         (배선 시험 — 요약 freshness 에 실제 판정 · 주입 여부를 남긴다). 판 2 의 실제 시드 측정은 늘 실제 관문을 지난다(주입 없음).
## 실행(저장소 루트): Rscript 04_Research/programs/P1_RETURN/P1S02_standing_qualification/rehearsal/rehearse.R [--inject-fresh] [--allow-ledger-ids J-…,J-…]
##   종료 0 = 리허설 ok · 1 = 한 단계라도 fail(요약은 그래도 쓴다).
a <- commandArgs(trailingOnly = TRUE)
INJECT <- "--inject-fresh" %in% a
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
D <- "04_Research/programs/P1_RETURN/P1S02_standing_qualification"
if (!file.exists(file.path(ROOT, D, "round_spec.json"))) stop("판 2 사양 없음 — 저장소 루트가 아니다: ", ROOT)
RUN <- format(Sys.time(), "%Y%m%d_%H%M%S")
RID <- "P1SR02_rehearsal"; CODE <- "P1SR02_RH_C0"   # round_id 형식 ^P[0-9]+[A-Z]*[0-9]+_[a-z0-9_]+$(spec.R) · 꼬리표 P1SR02 = 판 2 의 리허설
MARK <- c("P1SR02_", "rehearsal.p1s02.mom121")                  # 리허설 표식 — 공유 원장에 나타나면 격리 실패
OUT <- file.path(ROOT, D, "rehearsal", "out", RUN)
SA <- file.path(OUT, "sa"); ISO <- file.path(OUT, "iso"); RVR <- file.path(ISO, "rv"); RD <- file.path(OUT, RID)
dir.create(ISO, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(RC_SA_ROOT = SA, QVEST_TG_DRY_RUN = "1")
suppressMessages(source(file.path(ROOT, "04_Research/programs/_lib/round_core/v3/load.R")))
suppressPackageStartupMessages(library(data.table))
ENG <- file.path(D, "rehearsal/engine/RP_REHEARSAL_MOM121/engine.R")
TAU <- as.Date("2022-12-31")
md5v <- function(p) unname(as.character(tools::md5sum(p)))
md5f <- function(p) if (file.exists(p)) md5v(p) else "absent"
T00 <- Sys.time(); STEPS <- list(); DEFECTS <- list(); INFO <- list()
step <- function(id, name, expr) {   # expr → list(pass = , note = ) · 오류 = fail
  t0 <- Sys.time()
  r <- tryCatch(expr, error = function(e) list(pass = FALSE, note = paste("오류:", conditionMessage(e))))
  sec <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  STEPS[[length(STEPS) + 1L]] <<- list(id = id, name = name, pass = isTRUE(r$pass), seconds = sec, note = as.character(r$note %||% "")[1])
  cat(sprintf("[리허설] %s %s — %s · %.1f초%s\n", id, name, if (isTRUE(r$pass)) "pass" else "FAIL", sec,
              if (nzchar(as.character(r$note %||% "")[1])) paste0(" · ", r$note) else ""))
  if (!isTRUE(r$pass)) DEFECTS[[length(DEFECTS) + 1L]] <<- list(step = id, what = as.character(r$note %||% "")[1])
  invisible(r)
}
dir_hash <- function(d, drop = NULL) {   # 폴더 안 파일 목록 + md5 를 한 값으로
  f <- sort(list.files(file.path(ROOT, d), recursive = TRUE, all.files = TRUE, no.. = TRUE))
  if (!is.null(drop)) f <- f[!grepl(drop, f)]
  if (!length(f)) return("empty")
  tf <- tempfile(); on.exit(unlink(tf), add = TRUE); writeLines(paste(f, md5v(file.path(ROOT, d, f))), tf, useBytes = TRUE); md5v(tf)
}
## --allow-ledger-ids J-…,J-… = Q 가 리허설 설계 · 결과를 손으로 남긴 판단 기록(본문에 리허설 판 이름이 든다) — 판단 원장 표식 대조에서만 뺀다
##   (11-12 첫 실행: S9 '공유 원장 표식 1' = 실행 도중 Q 가 기록한 J-20261112-003 하나뿐이었다 — 리허설이 쓴 것이 아니다 · 뺀 id 는 요약에 남긴다)
ALLOW <- if ("--allow-ledger-ids" %in% a) strsplit(a[which(a == "--allow-ledger-ids") + 1L], ",", fixed = TRUE)[[1]] else character(0)
marks_in <- function(f) { p <- file.path(ROOT, f); if (!file.exists(p)) return(0L)
  if (length(ALLOW) && grepl("q_judgment_ledger[.]json$", f)) {
    L <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(L)) {
      for (k in c("judgments", "reviews", "challenges")) L[[k]] <- Filter(function(e) !(as.character(e[["id"]] %||% "") %in% ALLOW), L[[k]] %||% list())
      x <- as.character(jsonlite::toJSON(L, auto_unbox = TRUE, null = "null"))
      return(as.integer(sum(vapply(MARK, function(m) lengths(regmatches(x, gregexpr(m, x, fixed = TRUE))), 0L))))
    }
  }
  x <- readLines(p, warn = FALSE, encoding = "UTF-8"); sum(vapply(MARK, function(m) sum(grepl(m, x, fixed = TRUE)), 0L)) }
REAL <- c("06_Registry/research_programs.json", "06_Registry/factor_db_vintage.json", "06_Registry/round_outcomes.jsonl",
          "04_Research/programs/_lib/round_core/RELEASES.json", ".cache/gpu_lease.json",
          "stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/standing_ledger.jsonl",
          "stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json",
          "stage_artifacts/programs/P1_RETURN/P1S02_standing_qualification/prereg.json",
          "stage_artifacts/programs/P1_RETURN/P1S02_standing_qualification/standing_ledger.jsonl",
          paste0("stage_artifacts/programs/P1_RETURN/", RID, "/prereg.json"))
DIRS <- list(list(d = "04_Research/programs/P1_RETURN/P1S01_standing_qualification", drop = NULL),
             list(d = D, drop = "^rehearsal/"))
SHARED <- c("06_Registry/q_judgment_ledger.json", "06_Registry/decision_register.json", "06_Registry/session_resume.json")
REAL0 <- vapply(REAL, function(f) md5f(file.path(ROOT, f)), ""); DIR0 <- vapply(DIRS, function(x) dir_hash(x$d, x$drop), "")
SH0 <- vapply(SHARED, marks_in, 0L)

## ── S0 격리 단정 ─────────────────────────────────────────────────────────────
step("S0", "격리 단정(rc_root · 코어 v3 · RC_SA_ROOT · 공유 원장 표식 0)", {
  ok <- identical(tolower(rc_root()), tolower(ROOT)) && identical(RC_VERSION, "v3") && grepl("/round_core/v3$", RC_DIR) &&
    identical(Sys.getenv("RC_SA_ROOT"), SA) && startsWith(tolower(SA), tolower(paste0(ROOT, "/", D, "/rehearsal/out/"))) && all(SH0 == 0L) &&
    identical(REAL0[[paste0("stage_artifacts/programs/P1_RETURN/", RID, "/prereg.json")]], "absent")
  list(pass = ok, note = sprintf("코어 %s · 공유 원장 표식 %s", RC_VERSION, paste(SH0, collapse = "/")))
})
if (!isTRUE(STEPS[[1]]$pass)) stop("격리 단정 실패 — 아무것도 하지 않고 멈춘다")

## ── S1 리허설 판 만들기(사양 = 판 2 사양 복제 · 칸 = 리허설 엔진 1칸 · reference) ───────────────
step("S1", "리허설 판(판 2 사양 복제 · 칸 1 · standing-validate)", {
  sp <- rc_json_read(file.path(ROOT, D, "round_spec.json"))
  cs <- rc_p1_cell_spec(CODE, ENG, list(url = "https://doi.org/10.1111/j.1540-6261.1993.tb04702.x",
                                        title = "리허설 엔진 — 12-1 모멘텀(형성 창 관행 · Jegadeesh & Titman 1993)", paper_key = "rehearsal.p1s02.mom121"),
                        "rehearsal.p1s02.mom121", 1L, "rehearsal_wiring_only_not_a_trial", root = ROOT)
  SP <- file.path(RD, "specs", paste0(CODE, ".json")); rc_json_write(cs, SP)
  sp$round_id <- RID
  sp$purpose <- "P1S02 등록 전 리허설(격리) — 판정 경로 배선 시험 · 리서치 산출 아님"
  sp$hypothesis <- "판 2 의 측정 · 판정 경로가 실제 워커 · 실제 자료로 끝까지 지난다(값은 보지 않는다)"
  sp$cells <- list(list(code = CODE, engine = "RH", role = "reference", spec = rc_rel(SP, ROOT)))
  sp$exposures <- list("리허설 — 판정 · 보고 원문은 out/ 아래 파일에만 · 성과 값 미열람")
  sp$conclusion_scope <- list("리허설 — 결론 없음(배선 시험)")
  sp$changes_after_review <- list(); sp$changes_after_superfan <- list()
  rc_json_write(sp, file.path(RD, "round_spec.json"))
  S <- rc_spec_load(file.path(RD, "round_spec.json"), root = ROOT); rc_standing_validate(S, ROOT)
  INFO$cell_spec_md5 <- rc_md5(SP)   # (step 의 식은 호출한 곳 = 전역에서 평가된다 — 전역 대입은 <-)
  list(pass = TRUE, note = sprintf("판 %s · 판 번호 %s · 칸 %s(reference)", RID, S$standing_cfg$edition, CODE))
})

## ── S2 초안 · 점검 스텁 · P1 스텁 · 등록(임시 등록부) ──────────────────────────────────
REG <- file.path(ISO, "research_programs.json"); LED <- file.path(ISO, "ledger.json")
step("S2", "초안 · 점검 스텁 · P1 스텁 · 등록(임시 등록부 · check_git/run_tests 끔)", {
  if (!isTRUE(file.copy(file.path(ROOT, "06_Registry/research_programs.json"), REG, overwrite = TRUE))) stop("등록부 사본 실패")
  rvf <- sprintf("04_Research/programs/_supervision/superfan/philosophy/%s_P1_%s.md", format(Sys.time(), "%Y%m%d_%H%M"), rc_round_tag(RID))
  dir.create(dirname(file.path(RVR, rvf)), recursive = TRUE, showWarnings = FALSE)
  writeLines("리허설 P1 스텁 — 실제 철학 리뷰 아님", file.path(RVR, rvf), useBytes = TRUE)
  rc_json_write(list(schema = "q_judgment_ledger_v1", judgments = list(),
                     reviews = list(list(id = "R-REHEARSAL", role = "philosophy", trigger = "P1", round = RID, file = rvf, challenges = list())),
                     challenges = list()), LED)
  d1 <- rc_draft(RD, ROOT)
  rvx <- file.path(ISO, "review_v1_stub.md"); writeLines("리허설 점검 스텁 — 실제 격리 교차 점검 아님", rvx, useBytes = TRUE)
  rc_mark_reviewed(RD, 1L, rvx, "ok", ROOT)
  rg <- rc_register(RD, ROOT, registry_path = REG, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR)
  pre_sa <- file.path(SA, rg$prereg); rr <- pr_get(pr_load(ROOT, REG), "P1_RETURN")$rounds
  hit <- Filter(function(r) identical(r$round_id, RID), rr %||% list())
  ok <- file.exists(pre_sa) && file.exists(file.path(RD, "prereg.json")) && length(hit) == 1L && identical(hit[[1]]$prereg_md5, rg$md5)
  list(pass = ok, note = sprintf("초안 v%d · 사전등록 %s(md5 %s) · 임시 등록부 기록 %d", d1$version, rc_rel(pre_sa, ROOT), substr(rg$md5, 1, 8), length(hit)))
})

## ── S3 스캔(시드만 — max_new = 0 · 레인 디렉터리는 읽기만) ───────────────────────────────
LEDGER <- file.path(SA, "stage_artifacts/programs/P1_RETURN", RID, "standing_ledger.jsonl")
step("S3", "scan(시드 enqueue · 레인 새 항목 0)", {
  sc <- rc_standing_scan(RD, ROOT, registry_path = REG, max_new = 0L, out = file.path(OUT, "scan.json"))
  I <- rc_standing_items(rc_standing_ledger_read(LEDGER))
  list(pass = identical(sc$enqueued, CODE) && identical(names(I), CODE),
       note = sprintf("레인 디렉터리 %d · 입구 통과 %d(넣지 않음) · 넣은 항목 %s", nrow(sc$table), sum(sc$table$eligible), paste(sc$enqueued, collapse = ",")))
})

## ── S4 측정(실제 워커 · 실제 GPU 관문 · 실제 신선도 → 낡음이면 음성 대조 뒤 --inject-fresh 로 한 번 더) ──────────
FR <- rc_fresh_gate(rc_data_freshness, ROOT)
INFO$freshness <- list(real_state = FR$state %||% NA, real_ok = isTRUE(FR$ok), real_as_of = FR$as_of %||% NA, real_reason = FR$reason %||% NA, injected = FALSE)
step("S4g", "GPU 관문 판별(리허설 엔진 = cpu 여야 한다 · 임대 없음)", {
  g <- rc_gpu_guard(ENG, sprintf("rc_standing:%s:%s", rc_round_tag(RID), CODE), "리허설 판별", ROOT)
  if (isTRUE(g$need)) g$release()
  INFO$gpu_guard <- list(state = g$state, need = g$need)
  list(pass = isTRUE(g$ok) && identical(g$state, "cpu"), note = sprintf("관문 %s(%s)", g$state, g$reason %||% ""))
})
MREC <- NULL
if (!isTRUE(FR$ok)) {
  step("S4a", "측정 — 실제 신선도 관문(낡음 → data_stale · 원장 무기록 = 음성 대조)", {
    n0 <- length(rc_standing_ledger_read(LEDGER))
    m <- rc_standing_measure_item(RD, CODE, ROOT, registry_path = REG)
    n1 <- length(rc_standing_ledger_read(LEDGER))
    list(pass = identical(m$status, "data_stale") && n1 == n0, note = sprintf("관문 %s · 원장 줄 %d → %d", m$status %||% "?", n0, n1))
  })
  if (INJECT) {
    INFO$freshness$injected <- TRUE
    step("S4b", "측정 — 신선도 주입(배선 시험) · 실제 워커 · 실제 지문", {
      m <- rc_standing_measure_item(RD, CODE, ROOT, registry_path = REG,
                                    freshness = function(root) list(ok = TRUE, state = "injected", reason = "리허설 주입 — 실제 관문은 S4a 에서 낡음"))
      MREC <- m
      list(pass = isTRUE(m$ok) && isTRUE(m$fp_same), note = sprintf("ok %s · 지문 동일 %s · rc %s · %.1f분%s", m$ok, m$fp_same, m$rc, as.numeric(m$seconds %||% NA) / 60,
                                                         if (!is.null(m$error)) paste0(" · ", m$error) else ""))
    })
  }
} else {
  step("S4", "측정 — 실제 신선도 · 실제 워커 · 실제 지문", {
    m <- rc_standing_measure_item(RD, CODE, ROOT, registry_path = REG)
    MREC <- m
    list(pass = isTRUE(m$ok) && isTRUE(m$fp_same), note = sprintf("ok %s · 지문 동일 %s · rc %s · %.1f분%s", m$ok, m$fp_same, m$rc, as.numeric(m$seconds %||% NA) / 60,
                                                       if (!is.null(m$error)) paste0(" · ", m$error) else ""))
  })
}
MEASURED <- isTRUE(MREC$ok) && isTRUE(MREC$fp_same)
if (!is.null(MREC)) {
  INFO$measure <- list(ok = MREC$ok, fp_same = MREC$fp_same, rc = MREC$rc, seconds = MREC$seconds, artifacts = rc_rel(as.character(MREC$artifacts %||% NA), ROOT),
                       error = MREC$error %||% NA, base_alignment = MREC$base_alignment)
}

## ── S5 판정 전 점검(판 2 도구 그대로 · 자식 프로세스 · --round-dir · --registry · --eval) ─────────────────
if (MEASURED) step("S5", "판정 전 점검 10항목(tools/prejudge_check.R --eval · 리허설 경로)", {
  lg <- file.path(OUT, "prejudge.log")
  rc5 <- system2("Rscript", c(shQuote(file.path(ROOT, D, "tools/prejudge_check.R")), CODE, "--eval", "--round-dir", shQuote(rc_rel(RD, ROOT)),
                              "--registry", shQuote(REG)), stdout = lg, stderr = paste0(lg, ".err"))
  x <- readLines(lg, warn = FALSE, encoding = "UTF-8"); res <- grep("^\\[점검 결과\\]", x, value = TRUE)
  list(pass = identical(as.integer(rc5), 0L), note = sprintf("종료 %s · %s", rc5, if (length(res)) sub("^\\[점검 결과\\] ", "", res[length(res)]) else "결과 줄 없음"))
})

## ── S6 judge(판정 원장 · 판정 파일 · 보는 창 파일) — 출력은 파일로(자격 여부를 화면에 찍지 않는다) ───────────────
if (MEASURED) step("S6", "judge(판정 줄 · 판정 파일 · standing_visible.json τ_D 검사)", {
  jo <- capture.output(J <- rc_standing_judge(RD, ROOT, registry_path = REG), type = "output"); writeLines(jo, file.path(OUT, "judge.log"), useBytes = TRUE)
  it <- rc_standing_items(rc_standing_ledger_read(LEDGER))[[CODE]]
  vf <- file.path(RD, "results", "standing_visible.json")
  v <- it$verdict; ef <- Filter(function(r) identical(r$event, "eval_failed") && identical(r$code, CODE), rc_standing_ledger_read(LEDGER))
  leaks <- if (file.exists(vf)) rc_after_tau_leaks(rc_json_read(vf), TAU) else "파일 없음"
  ok <- !is.null(v) && identical(v$status, "evaluated") && file.exists(rc_abs(v$verdict_file, ROOT)) && file.exists(vf) && !length(leaks)
  list(pass = ok, note = if (!is.null(v)) sprintf("판정 줄 있음 · status %s · 판정 파일 %s · 보는 창 파일 τ_D 뒤 날짜 %d", v$status,
                                                   if (file.exists(rc_abs(v$verdict_file, ROOT))) "있음" else "없음", length(leaks))
       else sprintf("판정 줄 없음 · eval_failed %d건%s", length(ef), if (length(ef)) paste0(" · ", substr(ef[[length(ef)]]$error %||% "", 1, 200)) else ""))
})

## ── S7 보고 드라이런(send = FALSE · QVEST_TG_DRY_RUN = 1) · S8 상태 줄 ─────────────────────────
if (MEASURED) step("S7", "standing-report 드라이런(발송 없음 · 원장 reported 무기록)", {
  ro <- capture.output(R7 <- rc_standing_report(RD, send = FALSE, root = ROOT, registry_path = REG), type = "output")
  writeLines(ro, file.path(OUT, "report_dryrun.txt"), useBytes = TRUE)
  rep <- Filter(function(r) identical(r$event, "reported"), rc_standing_ledger_read(LEDGER))
  list(pass = !isTRUE(R7$sent) && length(c(R7$pass, R7$fail)) == 1L && !length(rep) && any(grepl("dry_run", ro, fixed = TRUE)),
       note = sprintf("보고 대상 %d · 드라이런 출력 %d줄 · 원장 reported %d", length(c(R7$pass, R7$fail)), length(ro), length(rep)))
})
if (MEASURED) step("S8", "standing-status 줄(원장 사슬 정상)", {
  so <- rc_standing_status_lines(RD, ROOT, registry_path = REG); writeLines(so, file.path(OUT, "status.txt"), useBytes = TRUE)
  list(pass = length(so) >= 2L && grepl("원장 사슬 정상", so[1], fixed = TRUE) && rc_standing_ledger_verify(LEDGER)$ok,
       note = sprintf("상태 %d줄 · 원장 사슬 %s(%d줄)", length(so), if (rc_standing_ledger_verify(LEDGER)$ok) "정상" else "끊김", rc_standing_ledger_verify(LEDGER)$n))
})

## ── S9 격리 증명(앞뒤 md5 · 공유 원장 표식 · 실제 사전등록 뿌리에 리허설 판 없음) ─────────────────────────
step("S9", "격리 증명(실제 파일 md5 · 폴더 · 공유 원장 표식)", {
  REAL1 <- vapply(REAL, function(f) md5f(file.path(ROOT, f)), ""); DIR1 <- vapply(DIRS, function(x) dir_hash(x$d, x$drop), ""); SH1 <- vapply(SHARED, marks_in, 0L)
  ch <- names(REAL1)[REAL1 != REAL0]
  ## 등록부는 다른 프로세스(레인 인계 · 아침 체인)가 쓸 수 있다 — 바뀌었으면 리허설 표식이 없는지로 판정(바뀐 사실은 남긴다)
  reg_ok <- !("06_Registry/research_programs.json" %in% ch) || marks_in("06_Registry/research_programs.json") == 0L
  hard <- setdiff(ch, "06_Registry/research_programs.json")
  INFO$isolation <- list(real_changed = as.list(ch), dirs_same = all(DIR1 == DIR0), shared_marks_before = as.list(SH0), shared_marks_after = as.list(SH1),
                         allowed_ledger_ids = as.list(ALLOW),
                          real_sa_rehearsal = REAL1[[paste0("stage_artifacts/programs/P1_RETURN/", RID, "/prereg.json")]])
  list(pass = !length(hard) && reg_ok && all(DIR1 == DIR0) && all(SH1 == 0L),
       note = sprintf("실제 파일 바뀜 %s · 판 1/판 2 폴더 같음 %s · 공유 원장 표식 %s", if (length(ch)) paste(ch, collapse = ",") else "0", all(DIR1 == DIR0), paste(SH1, collapse = "/")))
})

## ── 요약 ─────────────────────────────────────────────────────────────────────
ok_all <- all(vapply(STEPS, function(s) isTRUE(s$pass), TRUE)) && MEASURED
SUM <- list(schema = "p1s02_rehearsal_summary_v1", ok = ok_all, at = rc_now(), run = RUN, run_dir = rc_rel(OUT, ROOT),
            core = list(version = RC_VERSION, manifest_md5 = rc_core_manifest()$manifest_md5), engine = ENG, engine_md5 = rc_md5(file.path(ROOT, ENG)),
            rehearsal_round = RID, code = CODE, cell_spec_md5 = INFO$cell_spec_md5 %||% NA, inject_fresh = INJECT,
            steps = STEPS, defects = DEFECTS, freshness = INFO$freshness, gpu_guard = INFO$gpu_guard, measure = INFO$measure, isolation = INFO$isolation,
            seconds_total = round(as.numeric(difftime(Sys.time(), T00, units = "secs")), 1),
            note = "성과 값 없음(통과 여부 · 유한 여부 · 개수 · τ_D 이전 날짜만) · 판정 · 보고 원문 = run_dir 파일")
rc_json_write(SUM, file.path(OUT, "rehearsal_summary.json"))
rc_json_write(SUM, file.path(ROOT, D, "rehearsal", "rehearsal_summary.json"))
cat(sprintf("[리허설] 요약 ok=%s · 단계 %d · 결함 %d · %.1f분 → %s\n", ok_all, length(STEPS), length(DEFECTS), SUM$seconds_total / 60,
            file.path(D, "rehearsal", "rehearsal_summary.json")))
quit(status = if (ok_all) 0L else 1L)
