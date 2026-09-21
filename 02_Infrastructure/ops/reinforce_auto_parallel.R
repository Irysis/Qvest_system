#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_parallel.R — 강화 무인 러너 **병렬 배치** (도훈 지시 2026-08-30 "병렬로 실행")
#
# 왜 별도 파일인가 (reinforce_auto_run.R 과의 관계):
#   순차 러너는 claim mutex 로 **한 번에 한 칸**을 강제한다. 그 상태로 동시에 띄우면
#   다음 칸이 `attempts_used + 1` 이라 **넷 다 같은 칸**을 잡는다.
#   그래서 병렬은 구조를 바꾼다 — **원장 쓰기를 실행에서 떼어낸다**:
#     ① 사전 등록  : 순차 (rf_append_attempt — 원장 단독 접근)
#     ② 실행       : 병렬 (rf_cell_worker.R — 원장 미접근, 결과를 자기 JSON 에만 기록)
#     ③ 결과 수집  : 순차 (rf_record_result)
#   read-modify-write 경합이 원천적으로 없다.
#
# ★같은 블록 안에서만 병렬화한다. 블록 경계를 넘으면 안 되는 이유:
#   B2/B3 는 B1 승자 위에 서고 B4 는 B1~B3 승자 위에 선다. 승자가 확정되기 전에
#   다음 블록을 띄우면 **결정되지 않은 값 위에서 측정**하게 된다(공허한 시도).
#   이 규칙이 없으면 2026-08-30 의 "공허한 LOO" 사고가 병렬로 4배가 된다.
#
# 사용: Rscript reinforce_auto_parallel.R        (설정의 parallel_cells 만큼)
# 하드 가드는 순차 러너와 동일 — kill switch · claim · daily_cap · 자본 경계.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
# ★검사가 격리 사본을 쓸 수 있게 — 공유 설정을 검사가 직접 만지면 그 창에 tick 이 끼어든다
CFG_P  <- { .c <- Sys.getenv("QVEST_RF_CONFIG", "")
            if (nzchar(.c) && file.exists(.c)) .c
            else file.path(ROOT, "06_Registry/reinforce_auto_config.json") }
PROG_P <- file.path(ROOT, "06_Registry/reinforce_program.json")
LOG_P  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
# ★검사가 격리 사본을 쓸 수 있게 — 공유 claim 을 검사가 지우면 그 창에 tick 이 끼어들어
#   살아있는 배치 옆에 둘째 배치가 뜼다(원장 경합). 설정 격리(QVEST_RF_CONFIG)와 같은 형태.
CLAIM  <- { .cl <- Sys.getenv("QVEST_RF_CLAIM", "")
           if (nzchar(.cl)) .cl else file.path(ROOT, ".cache/reinforce_auto.claim") }
WDIR   <- file.path(ROOT, ".cache/rf_parallel")
dir.create(dirname(LOG_P), recursive = TRUE, showWarnings = FALSE)
dir.create(WDIR, recursive = TRUE, showWarnings = FALSE)

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "parallel"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_par] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse=","), 1, 80))),
                    sep = "=", collapse = " ")))
}

# ★등록 거부 누적 횟수 (entry·셀 코드 단위). 커서가 코드 기반이 된 뒤로 거부된 칸은
#   다음 tick 에 그대로 다시 잡힌다 — 회복은 되지만 **결정론적 거부에는 출구가 없다**
#   (2026-08-31 B3_11 16회 제자리 사고와 같은 형태). 그래서 상한을 두고 멈춰 세운다.
.append_fail_count <- function(code, bid) {
  if (!file.exists(LOG_P)) return(0L)
  tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    if (!grepl('"append_failed"', l, fixed = TRUE)) return(FALSE)
    r <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    !is.null(r) && identical(as.character(r$code %||% ""), code) &&
      identical(as.character(r$base_id %||% ""), bid)
  }, logical(1))), error = function(e) 0L)
}

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }
NPAR      <- as.integer(CFG$parallel_cells %||% 4L)
DAILY_CAP <- as.integer(CFG$daily_cap %||% 8L)
STALE_H   <- as.numeric(CFG$claim_stale_hours %||% 6)
# ★한 칸의 재시도 상한. 재개는 일시적 실패를 살리는 장치지 무한 재시도가 아니다.
MAX_RETRY <- as.integer(CFG$cell_max_retry %||% 2L)

done_today <- 0L
if (file.exists(LOG_P)) {
  today <- format(Sys.Date(), "%Y-%m-%d")
  done_today <- tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    o <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    isTRUE(!is.null(o) && identical(o$event, "cell_done") && startsWith(o$ts %||% "", today))
  }, logical(1))), error = function(e) 0L)
}
if (done_today >= DAILY_CAP) { jlog("halt_daily_cap", done = done_today, cap = DAILY_CAP); quit(status = 0) }

# ★claim 획득·해제는 rf_claim.R 하나. 2026-08-30 실사고 2회 — 배치 종료 후 unlink 이 조용히
#   실패해 빈 claim 이 남았고, 그러면 stale_hours(6h) 가 찰 때까지 전 tick 이 halt_claimed 로
#   물러난다. 그 로그는 **정상 대기와 글자 그대로 같아서** 아무도 못 본다(부팅 때 본 1.5h 공백).
#   그래서 owner.json(pid) 을 남기고, 다음 실행이 그 pid 사망을 보면 나이 무관 즉시 회수한다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R")))
# ★위임 호출에서는 부모가 이미 claim 을 쥐고 있다 — 자식이 다시 잡으려 하면 자기 부모에게 막혀
#   아무 일도 못 하고 끝난다(2026-08-30 실사고: halt_exhausted_delegate → halt_claimed 가 8분마다
#   2시간 반 동안 반복, 소진 전이가 영영 안 됐다). 부모가 이 플래그로 "이미 잡았다" 를 알린다.
.CLAIM_HELD <- nzchar(Sys.getenv("QVEST_RF_CLAIM_HELD", ""))
.ac <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited", age_h = NA_real_,
                            owner_pid = NA_integer_, note = "") else
       rf_claim_acquire(CLAIM, stale_hours = STALE_H)
if (!isTRUE(.ac$ok)) {
  if (identical(.ac$reason, "race")) jlog("halt_claim_race")
  else jlog("halt_claimed", age_h = round(.ac$age_h %||% NA_real_, 2), owner_pid = .ac$owner_pid %||% NA)
  quit(status = 0)
}
if (nzchar(.ac$note %||% "")) jlog("claim_stale_reclaim", note = .ac$note)

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
# ── 처치 전달 판정 헬퍼 — ★정본은 rf_spec_sig.R (2026-09-03 추출)
#   .fkeys 가 이 파일과 reinforce_auto_run.R 에 중복 정의돼 있었고, 커버리지 색인이
#   세 번째 복제본을 만들 참이었다. 서명이 갈리면 "같은 포트폴리오" 판정이 소비자마다 달라진다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
# ★기전 회피 표적 판정 — 정본은 rf_avoid.R (2026-09-05 추출 · 실사고 사연은 그 파일 머리)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_avoid.R"), local = TRUE))
PROG <- fromJSON(PROG_P, simplifyVector = FALSE)
led <- rf_load(1L, ROOT)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) {
  ## ★active 가 없으면 **다음 논문을 연다** (2026-09-05 실사고). 구판은 여기서 멈췄다 — 새 요청의 유일한 생산자
  ##   (reinforce_auto_next_paper.R)를 부르는 자리가 소진 위임뿐이라, entry 를 park 로 닫으면(소진 아님)
  ##   아무도 큐 상단을 열지 않고 8분마다 halt_no_active_entry + no_pending_request 만 반복됐다.
  ##   next_paper 는 자기 가드(enabled · active_exists · queue_empty)를 갖고 있어 중복 개설이 없다.
  jlog("halt_no_active_entry", note = "next_paper 에 위임 — 큐 상단 논문 개설 시도")
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); return(0L)
}
E <- act[[1]]; BID <- E$base_id
used <- as.integer(E$attempts_used %||% 0L)
# ★entry 별 상한 (2026-09-04 도훈 지시). B1 이 설계에 따라 가변 길이가 되면서,
#   전역 25 를 그대로 두면 B1 이 쓴 만큼 뒤 블록이 잘린다 — 실측: B1 14칸 -> B4(결합)가
#   아예 못 돌았다. 각 블록 승자를 합치는 칸을 못 보면 그 entry 는 A 로 갈 길이 없다.
#   "칸 수 제한을 두지 마라" 를 B1 에만 적용하고 총예산에 안 적용한 비대칭을 닫는다.
MAXA <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)
cells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))

# ── ★B1 설계 소비 (도훈 지시 2026-09-04 "블록 진입 시 1회만 LLM 설계") ────────
#   설계가 있으면 격자의 B1 칸을 **통째로** 갈아 끼운다. 칸 수가 5가 아니어도 뒤 블록의
#   코드(B2_6…)는 밀리지 않는다 — 커서가 위치가 아니라 **기록된 셀 코드**에서 나오기 때문이다
#   (2026-09-04 커서 수리). 구판 개수 커서였다면 B1 이 6칸인 순간 격자가 통째로 어긋났다.
#   설계가 없거나 검증에 떨어졌으면 이 블록은 아무것도 하지 않고, B1 은 규칙 선정으로 돈다.
.b1_design <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), local = TRUE))
  rf_b1_design_cells(BID, root = ROOT)
}, error = function(e) { jlog("b1_design_load_failed", err = conditionMessage(e)); NULL })
# ★블록 전이 설계 소비 (도훈 지시 ④ · 2026-09-04) — B2/B3/B5 도 설계가 있으면 그것으로 돈다.
#   설계는 앞 블록 기전 에이전트가 낸 것이고, 검증(카탈로그 실재성·중복)을 통과한 것만 저장돼 있다.
#   없으면 이 블록은 그냥 규칙 선정으로 돈다 — 폴백은 조용하지 않고 로그에 남는다.
.blk_design <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
  .out <- list()
  for (.bb in RFBD_BLOCKS) { .cc <- rfbd_cells(ROOT, BID, .bb); if (length(.cc)) .out[[.bb]] <- .cc }
  .out }, error = function(e) { jlog("block_design_load_failed", err = conditionMessage(e)); list() })
if (length(.blk_design)) for (.bb in names(.blk_design)) {
  .rest2 <- Filter(function(c) !identical(as.character(c$block %||% ""), .bb), cells)
  .new2  <- lapply(.blk_design[[.bb]], function(c) { c$block <- .bb
    c$axis <- switch(.bb, B2 = "weighting", B3 = "universe", B5 = "risk_overlay", "multifactor"); c })
  cells <- c(Filter(function(c) identical(as.character(c$block %||% ""), "B1"), .rest2),
             .new2,
             Filter(function(c) !identical(as.character(c$block %||% ""), "B1"), .rest2))
  jlog("block_design_applied", base_id = BID, block = .bb, cells = length(.new2),
       note = "앞 블록 기전이 낸 설계로 이 블록을 돈다")
}
if (length(.b1_design)) {
  .rest <- Filter(function(c) !identical(as.character(c$block %||% ""), "B1"), cells)
  cells <- c(lapply(.b1_design, function(c) { c$block <- "B1"; c$axis <- "multifactor"; c }), .rest)
  jlog("b1_design_applied", base_id = BID, cells = length(.b1_design),
       note = "설계 칸으로 B1 교체 — 칸 수는 설계가 정한다")
}

# ── ★상주 칸 (WP-R · 도훈 지시 2026-09-17 · 격자 정본 reinforce_program.json::standing_cells) ────────
#   BOOK_0001 PG2 오버레이의 동결 사양(pg2_risk_overlay_v1)을 **매 세대 B5 마다** 자기 코드(B5_31)로 한 번 잰다 —
#   설계·규칙 선정·회피 목록과 무관한 대조 칸이다. 판정은 rf_runner_gates.R::rf_standing_decision (순수 함수):
#   (a) 그 코드의 시도가 이미 있으면 항상 얹는다(재개·승자 해석이 **코드로** 칸을 찾는다 — 없으면 그 칸을 잃는다)
#   (b) B5 시도가 아직 없고 ∧ arm 이 카탈로그 active ∧ carry 에 없으면 얹는다
#   (c) 재설계 라운드(E$b5_redesign.active · B5 설계 레인이 쓴다)가 열려 있고 그 코드의 시도가 없으면 얹는다.
#   그 밖은 standing_cell_skipped 로 사유를 남긴다(조용한 통과 없음). B5 의 **첫 칸**에 넣어 첫 B5 배치에서 돈다.
#   예산은 아래 재도출식이 +1 로 센다(격자 25 밖의 칸이다).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), local = TRUE))
.n_standing_inserted <- 0L
.redesign_on <- rf_b5_redesign_active(E)
for (.sc in tryCatch(rfbd_standing_cells(ROOT),
                     error = function(e) { jlog("standing_cells_load_failed", err = conditionMessage(e)); list() })) {
  if (!identical(as.character(.sc$block %||% "B5"), "B5")) {
    jlog("standing_cell_skipped", code = as.character(.sc$code %||% ""), reason = "block_not_b5"); next }
  .dec <- rf_standing_decision(.sc, E$attempts, carry_overlay = E$carry$overlay,
                               catalog = tryCatch(.rfbd_b5_raw(ROOT), error = function(e) list()),
                               redesign_active = .redesign_on)
  if (!isTRUE(.dec$insert)) {
    jlog("standing_cell_skipped", code = as.character(.sc$code), arm = as.character(.sc$overlay_pick %||% ""),
         reason = .dec$reason); next }
  .cellS <- rf_standing_cell(.sc, .dec$kind, basis = .dec$basis)
  .kB5 <- which(vapply(cells, function(c) identical(as.character(c$block %||% ""), "B5"), logical(1)))
  cells <- if (length(.kB5)) append(cells, list(.cellS), after = .kB5[1] - 1L) else c(cells, list(.cellS))
  .n_standing_inserted <- .n_standing_inserted + 1L
  jlog("standing_cell_inserted", base_id = BID, code = .cellS$code, arm = .cellS$overlay$arm_id,
       kind = .cellS$overlay$kind, reason = .dec$reason, redesign = .redesign_on,
       note = "상주 칸 — B5 첫 칸으로 삽입(설계·규칙 선정과 무관 · 승격 carry 제외)")
}

# ── ★entry 예산 — **매 tick 재도출** (도훈 2026-09-04 · 2026-09-17 "예산 상한은 신경쓰지말고 반영") ────────
#   자동 = 기본(원장 max_attempts) + B1 설계 초과 + B5 설계 초과 + 상주 삽입 + 재설계 추가(E$b5_redesign.cells_added).
#   구판은 B1 설계가 있을 때만 셌다 — B5 설계가 7칸이거나 상주 칸이 얹히면 그만큼 뒤 블록(B4 결합)이 잘렸다.
#   실제 상한 = max(자동, 수동): 수동 상향은 덮지 않고(구판은 매 tick 되돌려 써 추가 칸이 1개만 돌았다),
#   자동은 자동식 위로 못 올린다. 바뀔 때만 원장에 쓴다. 산식 정본 = rf_runner_gates.R::rf_budget_auto/rf_budget_want.
.nB1d <- length(.b1_design)
.b5c  <- rf_b5_design_counts(length(.blk_design[["B5"]] %||% list()), E)
.slot_of <- function(id) { for (b in PROG$blocks) if (identical(b$id, id)) return(as.integer(b$n %||% length(b$cells))); 5L }
.auto <- rf_budget_auto(led$max_attempts %||% 25L, .nB1d, .b5c$n_base, .n_standing_inserted, .b5c$n_redesign,
                        slot_b1 = .slot_of("B1"), slot_b5 = .slot_of("B5"))
.want <- rf_budget_want(.auto, E$max_attempts)
.cur  <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)
if (.want != .cur) {
  ok_b <- tryCatch({ rf_record_entry_budget(1L, BID, .want,
            sprintf("예산 재도출 %d -> %d = 기본 %d + B1 설계 초과 %d(설계 %d칸) + B5 설계 초과 %d(설계 %d칸) + 상주 %d + 재설계 추가 %d — 뒤 블록이 잘리지 않도록",
                    .cur, .want, as.integer(led$max_attempts %||% 25L), max(0L, .nB1d - .slot_of("B1")), .nB1d,
                    max(0L, .b5c$n_base - .slot_of("B5")), .b5c$n_design, .n_standing_inserted, .b5c$n_redesign),
            root = ROOT); TRUE },
          error = function(e) { jlog("entry_budget_failed", err = conditionMessage(e)); FALSE })
  if (isTRUE(ok_b)) { MAXA <- .want
    jlog("entry_budget_raised", base_id = BID, max_attempts = .want, auto = .auto, b1_cells = .nB1d,
         b5_cells = .b5c$n_design, standing = .n_standing_inserted, redesign = .b5c$n_redesign) }
} else MAXA <- .cur

# ★미측정(등록만 된) 칸 — **소진 판정보다 먼저** 본다. 등록됐는데 실행이 실패한 칸을
#   exhausted 로 넘기면 그 칸이 영구 소실된다(2026-08-30 실사고: 워커 4개 미기동으로 17~20 이 빈 채 소비).
# ★단 terminal 로 닫힌 칸은 제외한다. 재개는 *일시적* 실패만 상정한 장치였는데, 구조적 실패
#   (같은 스펙이면 같은 자리에서 죽는 것)에는 출구가 없어 루프가 제자리를 돌았다
#   (2026-08-31 실사고: B3_11 이 00:16~07:46 사이 16회 동일 실패, used 15 고정).
#   terminal 은 성공 위장이 아니다 — essence 는 여전히 없고, 재개 대상에서만 빠진다.
pending <- Filter(function(a) (is.null(a$essence) || is.null(a$essence$port_t)) && !isTRUE(a$terminal),
                  E$attempts)

## ── ★기전 백필 (2026-09-04) — 블록 L-code 는 있는데 기전(LLM 서술)이 빈 블록을 한 번 더 시도한다 ──
##   실사고: 15블록 중 6블록의 '배운 것' 이 비었다(모델 400 · 킬스위치 · 호출부 도입 전). 기전 레인은 블록 종료
##   직후 한 번만 불리고 실패하면 영영 비었다. 상한 2회(mechanism_tries) · 레인 스위치가 꺼져 있으면 안 부른다.
if (isTRUE(CFG$enabled) && isTRUE((CFG$lcode_mechanism %||% list())$enabled)) tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), local = TRUE))
  .bf <- rf_mech_backfill_targets(BID, ROOT)
  for (.b in utils::head(.bf, 2L)) {
    jlog("mechanism_backfill", base_id = BID, block = .b, note = "기전이 빈 블록 — 레인 재시도(상한 2회)")
    system2("bash", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh")), BID, .b),
            stdout = FALSE, stderr = FALSE)
  }
}, error = function(e) jlog("mechanism_backfill_failed", err = conditionMessage(e)))

## ★소진 루틴 하나 — 예산 소진(used >= MAXA)과 격자 소진(빈 칸 0 · 아래 halt_no_jobs 자리) 두 입구가 같은 출구를 쓴다.
##   구판은 퇴역된 reinforce_auto_run.R 에 위임했는데 그 파일은 안내문만 찍고 종료해 promo2 소진 → 승격이 조용히 실패했다.
##   퇴역 러너가 하던 루틴 그대로: exhaust_reached → status=exhausted(writer) → entry_exhausted → next_paper(동기).
.exhaust_and_delegate <- function(why) {
  # ★Windows 에서 system2(env=) 는 무시된다(실측 2026-08-30: 자식이 로그 한 줄도 안 남겼다).
  #   부모 환경에 심어 자식이 상속하게 한다.
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  jlog("exhaust_reached", base_id = BID, used = used, why = why)
  tryCatch(rf_exhaust_entry(1L, BID, root = ROOT),
           error = function(e) jlog("exhaust_mark_failed", base_id = BID, err = conditionMessage(e)))
  jlog("entry_exhausted", base_id = BID)
  ## ★wait=TRUE — 부모가 먼저 끝나면 자식이 함께 죽어 이월이 조용히 안 된다(2026-08-30 실사고).
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")),
          wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); 0L
}
if (!length(pending) && used >= MAXA) { jlog("halt_exhausted_delegate", used = used)
  return(.exhaust_and_delegate("budget")) }

# 기저 논문 — 전략의 출처. B1 등록부 셀(계열 맵에 없는 계열)과 B5 오버레이 셀의 근거로 쓴다.
# ★배치 선정보다 **앞에** 둔다 — B1 picker 가 fallback_paper 로 받아야 하기 때문이다.
.base_paper <- tryCatch({
  ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
  if (nzchar(ap) && file.exists(ap)) fromJSON(ap, simplifyVector = FALSE)$replication$source_paper else NULL
}, error = function(e) NULL)

# ── ★블록 순서 적응 (C층 · 도훈 승인 2026-09-03) ─────────────────────────────
#   실측 근거: B1 승자 port_t 1.578 위에 오버레이를 마지막에 얹자 다섯 칸이 -0.78~0.72 로 무너졌다.
#   구판 순서는 **오버레이 없는 구성**을 최적화한 뒤 위험 통제를 나중에 붙인다 —
#   그런데 출하되는 구성에는 오버레이가 있다. 최적화 대상과 출하 대상이 어긋나 있었다.
#   규칙은 사전 선언(rf_block_order_decide)이고, 결정은 다음 배치 **전에** 원장에 한 번만 쓴다.
.blk_order <- as.character(E$block_order %||% character(0))
if (!length(.blk_order) && used >= 5L && !length(pending)) {
  .dec <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"), local = TRUE))
    rf_block_order_decide(E, PROG, root = ROOT)
  }, error = function(e) { jlog("block_order_decide_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.dec) && length(.dec$order)) {
    ok_rec <- tryCatch({ rf_record_block_order(1L, BID, .dec$order, .dec$reason,
                                               adaptive = isTRUE(.dec$adaptive), root = ROOT); TRUE },
                       error = function(e) { jlog("block_order_record_failed", err = conditionMessage(e)); FALSE })
    if (isTRUE(ok_rec)) {
      .blk_order <- .dec$order
      jlog("block_order_decided", order = paste(.dec$order, collapse = ">"),
           adaptive = isTRUE(.dec$adaptive), reason = substr(.dec$reason, 1, 130))
    }
  }
}
if (length(.blk_order)) {
  # 안정 정렬 — 블록 안 칸 순서는 그대로. 소비된 B1 은 순서 1이라 자리를 지킨다.
  .bk  <- vapply(cells, function(c) as.character(c$block %||% ""), character(1))
  .rnk <- match(.bk, .blk_order); .rnk[is.na(.rnk)] <- 99L
  cells <- cells[order(.rnk, seq_along(cells))]
}

# ── ★블록 경계 강제: 같은 블록 안에서만 묶는다 (재개분이 없을 때만 신규 배치) ──
batch <- list(); first <- NULL
if (!length(pending) && used < length(cells)) {
  # ★커서는 개수가 아니라 **아직 자리가 빈 셀 코드**에서 뽑는다 (2026-09-04 · 정본 rf_spec_sig.R).
  #   구판 `cells[[used + 1L]]` 은 등록 거부 1건에 격자 위치가 영구히 어긋났다 —
  #   그 칸은 영영 안 재고 다른 칸이 두 번 탄다(실측 사연은 rf_spec_sig.R 주석).
  .free <- .rf_free_cells(cells, E$attempts)
  if (!length(.free)) { jlog("halt_no_free_cell", used = used,
                             taken = length(.rf_taken_codes(E$attempts, cells))); return(0L) }
  first <- cells[[.free[1]]]
  for (k in .free) {
    if (length(batch) >= NPAR) break
    if (!identical(cells[[k]]$block, first$block)) break
    batch[[length(batch) + 1L]] <- cells[[k]]
  }
  # ★예산 축이 둘이다 — 하루 상한과 25칸 상한. 상한을 넘겨 등록하면 원장이 거부하고,
  #   그 거부가 곧 격자 훼손이었다. 넘길 일을 애초에 만들지 않는다.
  room <- max(0L, min(DAILY_CAP - done_today, MAXA - used))
  if (length(batch) > room) batch <- batch[seq_len(room)]

# ★B1(멀티팩터) 칸도 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-09-01). 구판은 팩터 5종이 격자에 문자로 박혀 있어 **모든 논문이 같은 5팩터**를
#   썼다 — 331종을 등록해 두고 5종만 쓴 셈이다. 격자의 B1 cells 는 스냅샷일 뿐 정본이 아니다.
#   ★시드 오프셋 = 원장 누적 entry 수. 이게 없으면 그리디가 결정론이라 전 논문이 같은 사슬을
#     받아 총 조합이 entry 수와 무관하게 5개로 고정된다(계열 라운드로빈으로 회전).
# ★설계가 있으면 규칙 선정기를 부르지 않는다 — 두 선정이 겹치면 설계가 조용히 덮인다.
if (length(batch) && identical(first$block, "B1") && !length(.b1_design)) {
  .done_fsets <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s0 <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s0)) NULL else paste(sort(vapply(.rp_all_factors(s0),
      function(f) as.character(f$id %||% ""), character(1))), collapse = "+")
  })))
  .fp <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
                    rf_pick_factor_sets(length(batch), exclude = .done_fsets %||% character(0),
                                        seed_offset = length(led$entries),
                                        depths = unlist(PROG$blocks[[1]]$depths %||% list()),
                                        fallback_paper = .base_paper, root = ROOT) },
                  error = function(e) { jlog("factor_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.fp) && length(.fp$cells)) {
    for (j in seq_along(batch)) if (j <= length(.fp$cells)) {
      .c <- .fp$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B1"; .c$axis <- "multifactor"
      batch[[j]] <- .c
    }
    jlog("factor_arms_picked", seed = .fp$seed_id, offset = .fp$seed_offset,
         chain = paste(.fp$picked_ids, collapse = ","), pool = .fp$n_available,
         max_rho = round(.fp$max_rho %||% NA_real_, 4), asof = .fp$substrate_asof,
         excl_no_ic = length(.fp$excluded_no_ic), excl_axis = length(.fp$excluded_axis))
  } else {
    jlog("factor_arms_fallback", note = "picker 미산출 — 격자 스냅샷 셀로 진행(측정은 계속된다)")
  }
}

# ★B5(오버레이) 칸은 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-08-30 "오버레이 방법론을 특정하는건 별로인데"). 이미 측정한 팔은 제외하므로
#   승격 사슬·다음 논문에서 같은 다섯 개를 반복 측정하지 않는다. 격자의 B5 cells 는 스냅샷일 뿐이다.
if (length(batch) && identical(first$block, "B5") && is.null(.blk_design[["B5"]])) {
  # ★중첩(v10.2) 이후 overlay 는 단수 객체 또는 층 리스트다. 구판 s$overlay$arm_id 는
  #   리스트에서 NULL 을 내 제외 목록이 통째로 비고, 이미 측정한 팔이 다시 뽑힌다.
  .arm_ids <- .ov_arm_ids   # 정본 = rf_spec_sig.R
  .done_arms <- unique(c(
    unlist(lapply(E$attempts, function(a) {
      sp <- a$essence$spec
      if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
      s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
      if (is.null(s)) NULL else .arm_ids(s$overlay)
    })),
    # ★carry 에 이미 깔린 팔도 제외한다 — 같은 팔을 또 뽑으면 .ov_stack 이 중복을 지워
    #   그 칸이 무처치로 닫힌다(측정 0으로 칸 하나 소각).
    .arm_ids(E$carry$overlay),
    # ★상주 arm 도 뺀다 (2026-09-17 · WP-R) — 상주 칸(B5_31)이 자기 코드로 매 세대 이미 잰다(같은 팔 두 번 = 칸 소각).
    tryCatch(rfbd_standing_picks(ROOT), error = function(e) character(0))))
  .done_arms <- .done_arms[nzchar(.done_arms)]
  # ★상주 칸은 자리를 내주지 않는다 — 픽커는 **비상주 슬롯만** 채운다(정본 rf_runner_gates.R::rf_batch_open_slots).
  .slots <- rf_batch_open_slots(batch)
  .pk <- if (!length(.slots)) NULL else
         tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R")))
                    rf_pick_overlay_arms(length(.slots), exclude = .done_arms %||% character(0), root = ROOT) },
                  error = function(e) { jlog("overlay_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.pk) && length(.pk$cells)) {
    for (j in seq_along(.slots)) if (j <= length(.pk$cells)) {
      .c <- .pk$cells[[j]]; .c$code <- batch[[.slots[j]]]$code; .c$block <- "B5"; .c$axis <- "risk_overlay"
      batch[[.slots[j]]] <- .c
    }
    jlog("overlay_arms_picked", ids = paste(.pk$picked_ids, collapse = ","),
         excluded = paste(.done_arms %||% character(0), collapse = ","),
         standing_slots = length(batch) - length(.slots))
  }
}
# ★B2(비중) 칸도 등록부에서 뽑는다 (2026-09-03). B1·B5 와 같은 형태 —
#   격자의 B2 cells 는 스냅샷일 뿐이고, 이미 측정한 label 은 제외해 반복 측정을 막는다.
#   구판은 이 호출이 아예 없어 카탈로그 52종이 격자에 한 번도 닿지 않았다.
if (length(batch) && identical(first$block, "B2") && is.null(.blk_design[["B2"]])) {
  .done_wt <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s)) NULL else (s$weighting$label %||% s$weighting$catalog_id)
  })))
  .wk <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R")))
                    rf_pick_weight_arms(length(batch), exclude = .done_wt %||% character(0)) },
                  error = function(e) { jlog("weight_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.wk) && length(.wk$cells)) {
    for (j in seq_along(batch)) if (j <= length(.wk$cells)) {
      .c <- .wk$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B2"; .c$axis <- "weighting"
      batch[[j]] <- .c
    }
    jlog("weight_arms_picked",
         ids = paste(vapply(.wk$cells, function(c) as.character(c$weighting$label %||% ""), character(1)),
                     collapse = ","),
         excluded = paste(.done_wt %||% character(0), collapse = ","))
  }
}
  if (!length(batch)) { jlog("halt_no_room", room = room); return(0L) }
  jlog("batch_start", block = first$block, n_cells = length(batch),
       codes = paste(vapply(batch, function(c) c$code, character(1)), collapse = ","))
}

# ── 승자 해석 (배치 전체가 같은 승자 위에 선다) ───────────────────────────────
.metric <- function(a, key) { es <- a$essence
  if (is.list(es) && !is.null(es[[key]])) as.numeric(es[[key]]) else NA_real_ }
.cell_by_code <- function(cd) { k <- which(vapply(cells, function(c) identical(c$code, cd), logical(1)))
  if (length(k)) cells[[k[1]]] else NULL }
.winner_of <- function(bid, by = "port_t", gate = NULL) {
  idx <- which(vapply(cells, function(c) identical(c$block, bid), logical(1)))
  cand <- Filter(function(a) { if (is.null(a$essence)) return(FALSE); cd <- a$essence$cell_code
    if (!is.null(cd) && nzchar(cd)) startsWith(cd, paste0(bid, "_")) else (a$n %in% idx) }, E$attempts)
  # ★소비 술어 (2026-09-17 · 적대검증 G2): 게이트가 있으면 통과한 시도만 승자 후보다 — verdict 부재(구 attempt)·pass 만.
  #   fail/error/not_candidate 는 등급 불변 · **소비만 보류**(블록 승자·B4 바닥·carry 에서 제외). 제외는 로그로 드러낸다.
  if (!is.null(gate) && length(cand)) {
    .keep <- vapply(cand, gate, logical(1))
    for (a in cand[!.keep])
      jlog("winner_excluded_adversary", block = bid, n = a$n, code = a$essence$cell_code %||% "",
           verdict = as.character((a$adversary %||% list())$verdict %||% ""),
           note = "적대검증 pass 아님 — 블록 승자·B4 바닥에서 제외(등급 불변 · 소비 보류)")
    cand <- cand[.keep]
  }
  if (!length(cand)) return(NULL)
  v <- vapply(cand, function(a) .metric(a, by), numeric(1)); if (all(is.na(v))) return(NULL)
  w <- cand[[which.max(replace(v, !is.finite(v), -Inf))]]; cd <- w$essence$cell_code
  # ★승자는 **측정된 spec 파일**에서 읽는다 — 격자에서 코드로 조회하면 안 된다(2026-09-01).
  #   B1·B5 셀은 이제 배치 시점에 등록부에서 뽑히므로 **격자에 존재하지 않는다**.
  #   격자를 조회하면 실제로 이긴 구성이 아니라 스냅샷 셀이 나오고, B2/B3/B4 가 이기지도 않은
  #   구성 위에 서게 된다. 격자를 손보는 순간 조용히 엇갈리는 것과 같은 계통의 병이다.
  #   spec 은 factors/weighting/universe/overlay/root_paper 를 그대로 들고 있어 드롭인이다.
  out <- NULL
  .sp <- w$essence$spec
  if (!is.null(.sp) && nzchar(.sp) && file.exists(.sp))
    out <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(out) && !is.null(cd) && nzchar(cd)) out <- .cell_by_code(cd)   # 구 entry 폴백
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  # 승자의 지표를 함께 실어 보낸다 — 채택 여부(기준선 초과)를 호출부가 판정할 수 있게.
  if (!is.null(out)) attr(out, "best_val") <- max(replace(v, !is.finite(v), -Inf))
  out
}

# ── ★carry 기준선 게이트 (도훈 지시 2026-08-31 "기준선 미달이면 carry 유지") ──
#   승계 entry 의 기준선은 **부모 승자 성능**이다. 블록 승자가 그걸 못 넘었다면 그 블록은
#   개선을 찾지 못한 것이고, 그런 승자를 다음 블록에 얹으면 뒤 블록 전체가 **더 나쁜 구성**
#   위에서 측정된다. 실측 2026-08-31: 기저 신호가 강한 논문에서 팩터를 하나 얹으면 등가중
#   컴포짓이 기저 가중을 1/2 -> 1/3 로 낮춰, B1 다섯 칸 어느 것도 기준선(2.63)을 못 넘었다
#   (최고 0.814). 그런데도 승자를 얹으면 B2~B4 가 전부 희석된 구성 위에서 돈다.
#   ★carry 가 없는 최초 entry 에는 기준선이 없다 — 항상 채택한다(게이트 무발화).
.carry_base <- if (!is.null(E$carry)) suppressWarnings(as.numeric(E$parent$best_port_t %||% NA)) else NA_real_
.beats_carry <- function(w, tag) {
  if (is.null(w) || !is.finite(.carry_base)) return(TRUE)
  bv <- suppressWarnings(as.numeric(attr(w, "best_val") %||% NA))
  okv <- is.finite(bv) && bv > .carry_base
  if (!okv) jlog("winner_below_carry_base", block = tag, best_val = bv, carry_base = .carry_base,
                 note = "블록이 개선을 못 찾음 — 그 축은 carry 유지(승자 미채택)")
  okv
}
.blk <- if (!is.null(first)) first$block else "B4"   # 재개분은 스펙이 이미 있어 승자를 다시 안 쓴다
w1 <- if (!identical(.blk, "B1")) .winner_of("B1", "port_t") else NULL
if (!length(pending) && !identical(.blk, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = .blk); return(1L) }
w2 <- .winner_of("B2", "port_t"); w3 <- .winner_of("B3", "calmar")

# ★B5 승자의 오버레이 — .winner_of 가 이미 승자의 spec 을 돌려주므로 그 안의 overlay 를 쓴다.
#   (격자 B5 cells 는 스냅샷이라 실제로 돈 arm 과 다를 수 있다 — 승자 기준 = calmar,
#    오버레이의 목적이 낙폭이기 때문이다. 격자 B5.select_winner_by 와 정합.)
#   ★적대검증 게이트 (2026-09-17 · G2): pass 또는 verdict 부재(구 attempt)만 승자 후보. 전부 탈락이면 w5=NULL —
#     B4 의 'B5 포함' 칸은 carry 오버레이(부모 위험통제)만 깐다(승자 없음 ≠ 부모 통제 해제 · LOO 대조 보존).
w5 <- .winner_of("B5", "calmar", gate = rf_adversary_ok)
.w5_overlay <- if (!is.null(w5)) w5$overlay else E$carry$overlay

# 승자의 팩터 축을 집합으로 정규화 — 등록부 셀은 factors(복수), 구 격자 셀은 factor2(단수)
.win_factors <- function(w) {
  if (is.null(w)) return(NULL)
  if (!is.null(w$factors) && length(w$factors)) return(w$factors)
  if (!is.null(w$factor2)) return(list(w$factor2))
  NULL
}

# ★B5(오버레이)는 블록 승자가 아니라 **지금까지의 전체 최고 구성** 위에 얹는 층이다.
#   격자 셀은 자기가 바꾼 축만 들고 있으므로(예: B3_12 는 universe 만) 승자의 **실제 스펙 파일**을
#   읽어 그대로 깐다 — 그래야 "그 전략에 오버레이를 얹었을 때" 를 재는 것이 된다.
.wbest_spec <- NULL
.wbest_code <- NA_character_   # ★바닥 attempt 의 코드 — B5 스펙 floor_code(적대검증 바닥 식별 1순위 · 2026-09-17)
{ .cd0 <- Filter(function(a) !is.null(a$essence), E$attempts)
  # ★바닥도 적대검증 판정을 따른다 (2026-09-17 · WP-R 사후 지적). 판정 fail/error/not_candidate 인 B5 칸이
  #   PORT_t 최고면 그 오버레이가 뒤 블록(B2·B3)의 바닥으로 **승계**돼 소비 보류가 새어 나갔다 — 승자·carry·A 후보만
  #   막고 누적 바닥은 안 막은 비대칭. 판정 필드가 없는 시도(구 entry · B5 밖 칸)는 그대로 후보다(rf_adversary_ok).
  .cd0_all <- .cd0
  .cd0 <- Filter(rf_adversary_ok, .cd0)
  if (length(.cd0_all) > length(.cd0)) {
    .va <- vapply(.cd0_all, function(a) .metric(a, "port_t"), numeric(1))
    .ba <- .cd0_all[[which.max(replace(.va, !is.finite(.va), -Inf))]]
    if (!rf_adversary_ok(.ba))
      jlog("floor_excluded_adversary", base_id = BID, n = .ba$n, code = .ba$essence$cell_code %||% "",
           verdict = as.character((.ba$adversary %||% list())$verdict %||% ""),
           note = "PORT_t 최고였지만 적대검증 미통과 — 누적 바닥에서 제외(오버레이 승계 차단)")
  }
  if (length(.cd0)) {
    .v0 <- vapply(.cd0, function(a) .metric(a, "port_t"), numeric(1))
    if (!all(is.na(.v0))) {
      .w0 <- .cd0[[which.max(replace(.v0, !is.finite(.v0), -Inf))]]
      .sp0 <- .w0$essence$spec
      if (!is.null(.sp0) && nzchar(.sp0) && file.exists(.sp0)) {
        .wbest_spec <- tryCatch(fromJSON(.sp0, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(.wbest_spec)) .wbest_code <- .rf_attempt_code(.w0, cells)
      }
    } } }

# ── ★arm × 유니버스 양립성 관문 — 등록·재개 **두 경로가 같은 함수** (2026-09-13) ──────────
#   실사고 2002.06975 promo3: B4_21/22/25 의 lean:hrp × KQ150 은 첫 조우라 등록 시점 장부에 기록이 없었다.
#   엔진이 커버리지로 끊은 뒤 **재개 경로는 장부를 안 읽고** 같은 spec 을 다시 돌려 두 번째 실패 = terminal
#   로 닫힐 참이었다. 강등 규칙이 있어도 재개가 안 부르면 첫 조우 칸에는 출구가 없다(이월 경로가 둘이면
#   표식도 둘이 같아야 한다). 판정·기록 순서의 정본은 rf_arm_compat::rac_gate_apply — 여기는 부작용을 주입만 한다.
#   @return "run" | "closed"   (강등이면 spec 파일을 고쳐 쓰고 carry_degraded 를 로그에 남긴다)
.rac_gate_apply <- function(spec, sp, CELL, n, path) {
  ok <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
                   TRUE },
                 error = function(e) { jlog("arm_compat_gate_failed", code = CELL$code, path = path,
                                            err = conditionMessage(e)); FALSE })
  if (!ok) return("run")   # 관문 고장은 차단 사유가 아니다 — 엔진 가드가 최종선이다(구판 거동과 동일)
  rac_gate_apply(spec, sp, CELL, n, path, cells = cells, root = ROOT,
                 record_fn = function(n, ...) rf_record_result(1L, BID, n, ..., root = ROOT),
                 log_fn = jlog)
}

# ── ①-0 재개 검사: 등록됐으나 essence 없는 칸이 있으면 **그 칸부터 다시 실행**한다 ──
#   병렬은 등록 → 실행 순서라 실행이 실패하면 칸이 측정 없이 소비된다.
#   재개가 없으면 무인 상태에서 실패 1회 = 칸 영구 소실 (2026-08-30 실사고).
jobs <- list()
if (length(pending)) {
  jlog("resume_pending", n_pending = length(pending),
       ns = paste(vapply(pending, function(a) as.character(a$n), character(1)), collapse = ","))
  for (a in pending) {
    ## ★코드로 찾는다 — 정본 rf_spec_sig.R::rf_resume_cell (2026-09-05). 구판은 essence 없는 실패 칸을
    ##   cells[[a$n]] 위치로 떨어뜨려, B3 설계 4칸(cells 24개)에서 n=21→B4_22 · n=25→NULL 로 밀렸다.
    .rc <- rf_resume_cell(a, cells, .cell_by_code)
    CELL <- .rc$cell
    if (identical(.rc$how, "positional_legacy")) jlog("resume_positional_fallback", n = a$n, code = CELL$code %||% "",
         note = "attempt 에 cell_code 가 없어 위치로 찾았다 — 구 entry 호환 폴백")
    if (is.null(CELL)) { jlog("resume_skip_unknown_cell", n = a$n, how = .rc$how); next }
    # entry 별 spec 이 정본. 구 이름(spec_<code>.json)은 이 수리 이전 entry 호환용 폴백이다.
    sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
    if (!file.exists(sp)) sp <- file.path(WDIR, sprintf("spec_%s.json", CELL$code))
    if (!file.exists(sp)) { jlog("resume_skip_no_spec", n = a$n, code = CELL$code); next }
    ## ★재개도 양립성 관문을 지난다 (2026-09-13) — 첫 조우 커버리지 실패는 ③이 장부에 적은 뒤 여기서 강등된다.
    .rsp <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(.rsp) && identical(.rac_gate_apply(.rsp, sp, CELL, as.integer(a$n), "resume"), "closed")) next
    jobs[[length(jobs) + 1L]] <- list(n = as.integer(a$n), code = CELL$code, spec = sp,
      name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
      out = file.path(WDIR, sprintf("result_%s.json", CELL$code)),
      resume = TRUE)   # ★재개분 표식 — 실행 절이 기존 결과 재사용 여부를 이 표식으로만 판단한다(신규 job 은 항상 재실행)
  }
  if (length(jobs) > NPAR) jobs <- jobs[seq_len(NPAR)]
}

# ── ① 사전 등록 (순차 — 원장 단독 접근). 재개분이 있으면 건너뛴다 ────────────
# ★이미 측정된 칸들의 서명. 새 칸이 여기 걸리면 같은 포트폴리오를 다시 재는 것이다.
.seen_sig <- list()
for (.a in E$attempts) {
  .sp <- .a$essence$spec
  if (is.null(.sp) || !nzchar(.sp) || !file.exists(.sp)) next
  .so <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(z) NULL)
  if (!is.null(.so)) .seen_sig[[.spec_sig(.so)]] <- .a$essence$cell_code %||% paste0("n", .a$n)
}
if (!length(jobs)) for (CELL in batch) {
  .no_treatment <- FALSE
  SPEC <- list(code = CELL$code, label = CELL$label, block = CELL$block,
               fixed_axes = PROG$fixed_axes,
               # ★기저 신호는 원장의 충실구현 engine_path 에서 물려받는다 — 논문이 바뀌면 기저도 바뀐다.
               #   경로가 없거나 파일이 없으면 mom_12_1 로 떨어진다(구 entry 하위호환).
               # ★entry 가 base_signal 을 명시하면 그것이 정본이다(결합 entry 는 engine_blend 로
               #   엔진 두 개를 물린다). 명시가 없을 때만 engine_path 하나로 떨어진다 —
               #   구판은 이 분기가 없어 결합 entry 가 단일 엔진으로 **조용히** 돌 뻔했다.
               base_signal = if (!is.null(E$base_signal)) E$base_signal else { .ep <- E$engine_path %||% ""
                 if (nzchar(.ep) && file.exists(.ep)) list(kind = "engine", path = .ep)
                 else list(kind = "mom_12_1") },
               # ★기저 가중 — 등가중이면 팩터 n개에서 논문신호가 1/(1+n) 로 떨어져 결합 깊이와
               #   기저 희석이 교락된다. 격자 fixed_axes 가 정본이고 엔진은 값이 없으면 등가중이다.
               base_weight = PROG$fixed_axes$base_weight,
               # ★팩터 축은 **집합**이다(2026-09-01). 등록부 셀은 factors(복수)를 들고 오고,
               #   구 격자 셀의 factor2(단수)는 길이 1 집합으로 정규화한다.
               factors = (if (!is.null(CELL$factors) && length(CELL$factors)) CELL$factors
                          else if (!is.null(CELL$factor2)) list(CELL$factor2)
                          else if (.beats_carry(w1, "B1")) .win_factors(w1) else NULL),
               weighting = CELL$weighting %||% list(kind = "ew"),
               universe = CELL$universe %||% list(kind = "k200_kq150"),
               # ★B6(집행 주기) 칸의 규칙 — 빠지면 그 칸은 **조용한 무처치**가 된다
               #   (격자 셀의 rebalance 를 여기서 안 실으면 엔진은 월간 그대로 돈다)
               rebalance = CELL[["rebalance"]])
  # ── ★블록 누적 — 실행 순서를 따라간다 (도훈 지시 2026-09-04) ────────────────
  #   구판은 B2·B3 가 **B1 승자만** 물었다. 블록 순서가 고정(B1→B2→B3→B5→B4)일 때는
  #   맞았지만, 교훈 재귀가 순서를 적응시키면서(2026-09-04 B5 를 2번째로) 전제가 깨졌다.
  #   실측: B5_18 이 Calmar 0.405 를 냈는데 그 다음에 돈 B2·B3 는 overlay=none 으로 돌았다 —
  #   **순서는 바뀌었는데 누적 규칙이 안 따라갔다.** 궤적이 언덕이 아니라 부채꼴이 된 이유다
  #   (블록 최고 1.454 → 1.163 → 1.472 → 1.147 → 1.167, 34칸 쓰고 첫 블록 대비 +0.018).
  #
  #   그래서 축 목록을 나열하지 않는다 — **지금까지 최고 구성**을 바닥으로 깔고 자기 축만 덮는다.
  #   순서가 또 바뀌어도 어긋나지 않는다(개수 대신 격자에서 재도출한 것과 같은 원리).
  #   ★"지금까지 최고" 이므로 더 나쁜 구성 위에 서는 일이 원리상 없다(도훈 ②).
  #     기준은 port_t — Grade A 두 축 중 더 멀리 있는 쪽이다(1.47/2.95 vs 0.42/0.64).
  #     이 기본값을 뒤집을 근거는 설계 레인이 처방으로 낸다(예: 낙폭이 구속이면 Calmar 기준).
  #   ★구판의 `B3 는 weighting 을 EW 로 되돌린다` 줄은 여기서 폐기된다 — 그 줄이 B2 승자를
  #     매번 버렸다. 유니버스를 재려고 비중을 리셋하면 그건 통제가 아니라 누적 파괴다.
  if (!(CELL$block %in% c("B1", "B4")) && !is.null(.wbest_spec)) {
    .own <- switch(CELL$block, B2 = "weighting", B3 = "universe", B5 = "overlay",
                   B6 = "rebalance", NA_character_)
    if (is.null(SPEC$factors) || !length(SPEC$factors)) SPEC$factors <- .wbest_spec$factors
    if (!identical(.own, "weighting") && !is.null(.wbest_spec$weighting)) SPEC$weighting <- .wbest_spec$weighting
    if (!identical(.own, "universe")  && !is.null(.wbest_spec$universe))  SPEC$universe  <- .wbest_spec$universe
    # ★overlay 는 정확 일치로 읽는다 (2026-09-17 WP-R) — 바닥이 B1~B3 칸이면 스펙에 overlay 키가 없고 overlay_cell=[] 만
    #   있어 `$overlay` 가 부분 일치로 그 빈 리스트를 집는다(서명은 같지만 B2/B3 스펙에 "overlay": [] 가 새로 박힌다).
    if (!identical(.own, "overlay")   && !is.null(.wbest_spec[["overlay"]])) SPEC$overlay <- .wbest_spec[["overlay"]]
    # ★B6(집행 주기)도 누적 축이다 — 빠지면 "승계 목록에서 빠진 축은 없는 축이 된다"(2026-09-05 교훈)
    if (!identical(.own, "rebalance") && !is.null(.wbest_spec[["rebalance"]])) SPEC$rebalance <- .wbest_spec[["rebalance"]]
    jlog("block_accumulate", code = CELL$code, own_axis = .own %||% "-",
         w = (SPEC$weighting$kind %||% "?"), u = (SPEC$universe$kind %||% "?"),
         ov = length(.ov_layers(SPEC$overlay)),
         note = "직전까지 최고 구성을 바닥으로 — 순서 무관 누적")
  } else if (identical(CELL$block, "B3") && is.null(.wbest_spec)) {
    SPEC$weighting <- list(kind = "ew")   # 측정이 아직 없을 때만 구판 기본값
  }
  if (identical(CELL$block, "B4")) {
    use <- unlist(CELL$combo$use)
    # ★B4 에는 carry 기준선 게이트를 걸지 않는다. 게이트의 취지는 "개선 못 찾은 승자를
    #   **다음 탐색의 바닥**으로 깔지 말라" 인데(B2·B3 가 B1 위에 서는 자리), B4 는 탐색이
    #   아니라 **분해**다 — 축을 합치고 하나씩 빼서 기여를 가른다. 승자가 기준선을 못
    #   넘었어도 합쳤을 때 어떤지가 이 블록이 재려는 값이다.
    #   ★2026-08-31 실사고: 게이트를 여기까지 걸었더니 아무것도 안 얹혀 네 칸이 같은 t(2.241)를 냈다.
    # ★2026-09-01 4축으로 확장 — 구판은 3축(팩터·비중·유니버스)만 봤는데 그 부분집합 격자는
    #   이미 완비였다(단일 = 각 블록 승자 · 쌍 = LOO · 전체 1). 빈 곳은 칸이 아니라 축이고,
    #   그 축은 오버레이다: A 를 막는 것이 낙폭인데 구판 B4 는 오버레이를 보지 않았다.
    SPEC$factors   <- if ("B1" %in% use) .win_factors(w1) else NULL
    SPEC$weighting <- if ("B2" %in% use && !is.null(w2)) (w2$weighting %||% list(kind="ew")) else list(kind = "ew")
    SPEC$universe  <- if ("B3" %in% use && !is.null(w3)) (w3$universe  %||% list(kind="k200_kq150")) else list(kind = "k200_kq150")
    # ★B5 승자 스펙은 이미 carry 를 포함한 중첩판이라 그대로 쓴다(이중 적용 없음).
    #   B5 를 뺀 칸도 부모의 오버레이는 기저로 남겨야 LOO 대조가 성립한다 —
    #   안 그러면 "B5 제외" 가 이 세대 처치와 부모 위험통제를 동시에 벗기는 두 겹 처치가 된다.
    SPEC$overlay   <- if ("B5" %in% use) .w5_overlay else (E$carry$overlay %||% NULL)
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    jlog("b4_axes", code = CELL$code, use = paste(use, collapse = "+"),
         f = length(SPEC$factors %||% list()), w = SPEC$weighting$kind %||% "?",
         u = SPEC$universe$kind %||% "?", ov = rf_ov_txt(SPEC$overlay))   # ★스택도 전 층을 적는다(구판은 리스트면 "none")
  }
  # ── ★승격 entry 의 carry 병합 (도훈 지시 2026-08-30 "B등급 이상 추가 강화") ──
  #   승격은 B+ 를 낸 승자 구성을 **기저로 물려받아** 그 위에서 25칸을 다시 탐색한다.
  #   기저 신호(engine_path)는 그대로다 — 바뀌는 것은 그 위에 깔린 팩터·비중·유니버스다.
  #   축 소유권: 자기 축을 탐색하는 블록은 carry 를 덮는다(B2=비중 · B3=유니버스),
  #   B4 는 **이 entry 안의 승자**를 조합하는 블록이라 carry 가 그 선택을 덮지 않는다.
  if (!is.null(E$carry)) {
    .cur <- SPEC$factors
    if (is.null(.cur)) {
      .cur <- list()
      if (!is.null(SPEC$factor2) && !identical(SPEC$factor2$kind, "none")) .cur <- c(.cur, list(SPEC$factor2))
      if (!is.null(SPEC$factor3)) .cur <- c(.cur, list(SPEC$factor3))
    }
    # ★중복 제거. 스코어는 rowMeans(zb, z1, z2, ...) 등가중이라 같은 팩터가 두 번 들어가면
    #   **기저 신호 가중이 조용히 깎인다**(1/2 -> 1/3). 실측 2026-08-31: 부모 B3_12
    #   factors=[Amihud] PORT_t 2.63 -> 자식 factors=[Amihud,Amihud] 2.251, 기저 캐시 md5 동일.
    #   승계가 물려받은 구성을 희석하면 promote 조건(부모 최고 초과)은 원리상 만족될 수 없다.
    SPEC$factors <- .dedup_factors(c(E$carry$factors %||% list(), .cur))
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    if (!(CELL$block %in% c("B2", "B4")) && !is.null(E$carry$weighting)) SPEC$weighting <- E$carry$weighting
    if (!(CELL$block %in% c("B3", "B4")) && !is.null(E$carry$universe))  SPEC$universe  <- E$carry$universe
    # ★2026-09-03 오버레이 승계 — 구판은 이 줄이 없었다. weighting/universe 는 물려받는데
    #   overlay 만 안 물려받아, 승격된 자식의 B1/B2/B3 는 부모의 위험 통제가 벗겨진 채 돌았다.
    #   팩터는 누적(.dedup_factors)되는데 오버레이는 세대마다 0 으로 리셋된 것이다.
    #   B5 는 자기 축이라 아래에서 **중첩**으로 처리하고, B4 는 부분집합 조립이라 제외한다.
    if (!(CELL$block %in% c("B5", "B4")) && !is.null(E$carry$overlay)) SPEC$overlay <- E$carry$overlay
  }
  # ★B5 오버레이 — 전체 최고 구성을 그대로 깔고 그 위에 노출 스케일만 얹는다
  if (identical(CELL$block, "B5")) {
    if (!is.null(.wbest_spec)) {
      SPEC$factors   <- .wbest_spec$factors
      SPEC$factor2   <- .wbest_spec$factor2
      SPEC$factor3   <- .wbest_spec$factor3
      SPEC$weighting <- .wbest_spec$weighting %||% list(kind = "ew")
      SPEC$universe  <- .wbest_spec$universe  %||% list(kind = "k200_kq150")
    }
    # ★중첩 — carry 의 오버레이를 지우지 않고 그 위에 이 칸의 arm 을 얹는다(v10.2).
    #   구판은 덮어쓰기라 부모가 낙폭을 30% 깎아 승격됐어도 자식 B5 는 그 30% 를 버리고
    #   처음부터 다시 깎았다. 노출은 곱으로 합성된다(rf_cell_engine .ov_compose).
    SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)
    # ★자기 층·바닥 표식 (2026-09-17 · 적대검증 G2 소비): overlay_cell = 이 칸이 **직접 얹은** 층(엔진 층별 처치 가드 ·
    #   기전 지도·승격 carry·적대검증의 '자기 층' 정본) · floor_code = 이 칸이 깔린 바닥 attempt 의 코드(적대검증 바닥
    #   식별 1순위 · 서명 대조는 2순위). 둘 다 부기 필드다 — .spec_sig 는 factors/base_weight/weighting/universe/overlay/
    #   base_signal 만 접으므로 서명 불변(test_rf_runner_standing_adversary.R 이 실제 스펙으로 대조한다).
    SPEC$overlay_cell <- CELL$overlay
    if (!is.na(.wbest_code)) SPEC$floor_code <- .wbest_code
    SPEC$overlay_basis <- CELL$basis %||% ""
    if (!is.null(.base_paper)) SPEC$root_paper <- .base_paper
  }
  # ★B1~B3 는 자기 층이 없다 — 오버레이는 전부 승계분(carry · block_accumulate 바닥)이다. 빈 리스트로 **명시**해
  #   하류(.ov_own_layers 의 'overlay − carry' 폴백)가 바닥의 B5 층을 이 칸의 처치로 오귀속하지 않게 한다.
  #   엔진은 overlay_cell 이 비면 층별 처치 가드를 승계 층에 걸지 않는다(합성 가드는 그대로 · rf_cell_engine .OV_OWN).
  if (CELL$block %in% c("B1", "B2", "B3")) SPEC$overlay_cell <- list()
  # ★무처치 판정은 **조립이 끝난 뒤** 한다. 구판은 carry 병합 블록 안에서 쟀는데,
  #   B5(오버레이)는 그 뒤에 overlay 를 붙이므로 판정 시점엔 팩터·비중·유니버스가 carry 와
  #   같아 전부 "무처치" 로 닫혔다 — 정작 처치인 오버레이가 아직 없을 때 판정한 것이다.
  #   2026-08-31 실사고: B5 다섯 칸이 측정 0건으로 소비돼 25 소진이 찍히고 다음 논문으로
  #   넘어갔다. 계기가 재려는 것(처치가 있나)이 아니라 재기 쉬운 것(그 시점 세 축)을 쟀다.
  #   ★overlay 는 carry 에 없는 축이므로, 오버레이가 붙은 칸은 자동으로 처치 있음이 된다.
  if (!is.null(E$carry)) {
    .no_treatment <- identical(.fkeys(SPEC$factors), .fkeys(E$carry$factors %||% list())) &&
      .same_axis(SPEC$weighting, E$carry$weighting %||% list(kind = "ew")) &&
      .same_axis(SPEC$universe,  E$carry$universe  %||% list(kind = "k200_kq150")) &&
      .same_axis(SPEC$overlay,   E$carry$overlay   %||% list()) &&
      .same_axis(SPEC[["rebalance"]], E$carry[["rebalance"]] %||% list())
  }
  # ★근거 논문 (2026-09-02 수리). 구판의 폴백 사슬(셀 논문 → B1 승자 논문)은
  #   ①B1 이 시드 계열 논문 하나만 붙이고(사슬이 접두 집합 → 4계열 컴포짓 5칸 전부 Amihud 2002)
  #   ②B5 는 자체 논문이 없어 **B1 승자 논문을 차용**했다 — 낙폭 브레이크가 유동성 논문을 인용했고,
  #     위 B5 분기가 넣은 기저 논문(SPEC$root_paper <- .base_paper)은 여기서 덮어써져 죽은 코드였다.
  #   그래서 "같은 root_papers 3회 연속" WARN 이 20칸 연속 발화했다 — 표기 결함을 재고 있었다.
  #   현행: source_paper(단수) = **기저 논문**(이 entry 가 강화하는 논문 — 모든 셀은 그 변형이다).
  #         원장 root_papers(복수) = 기저 + 셀 자체 처치 논문(B2 비중·B3 유니버스) + 팩터 **전 계열** 논문
  #         (+ risk_overlay 는 method 항목 선두). 매핑 없는 계열은 버리지 않고 이름으로 남긴다.
  rp <- .base_paper %||% CELL$root_paper %||% w1$root_paper
  SPEC$root_paper <- rp
  .rpz <- tryCatch({
    if (!exists("rf_root_papers_for")) suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
    rf_root_papers_for(SPEC, base_paper = rp, cell_paper = CELL$root_paper, root = ROOT)
  }, error = function(e) { jlog("root_papers_failed", code = CELL$code, err = conditionMessage(e))
    list(papers = Filter(function(z) is.list(z) && nzchar(as.character(z$url %||% "")), list(rp, CELL$root_paper)),
         families = character(0), unmapped_families = character(0)) })
  .root_papers <- .rpz$papers
  if (identical(CELL$axis, "risk_overlay"))
    .root_papers <- c(list(list(method = CELL$basis %||% CELL$label, url = rp$url %||% "")), .root_papers)
  SPEC$root_papers <- .root_papers
  SPEC$root_paper_families <- .rpz$families
  SPEC$unmapped_families <- .rpz$unmapped_families
  if (length(.rpz$unmapped_families))
    jlog("root_paper_unmapped_family", code = CELL$code, families = paste(.rpz$unmapped_families, collapse = ","))
  # ★sprintf 영길이 붕괴 방어 (2026-09-03). 인자 하나가 NULL/character(0)/NA 면 sprintf 는
  #   경고 없이 character(0) 을 돌려주고, 그 값이 원장에 idea=[] 로 박힌다.
  #   모든 조각을 길이 1 문자열로 강제한 뒤에만 조립한다.
  .s1 <- function(x, alt = "?") {
    x <- suppressWarnings(as.character(x))
    if (!length(x) || is.na(x[[1L]]) || !nzchar(x[[1L]])) alt else x[[1L]]
  }
  SPEC$idea <- sprintf("[무인 병렬 %s] %s — %s/%s · factor2=%s · weighting=%s · universe=%s · overlay=%s",
                       .s1(CELL$code), .s1(CELL$label), .s1(CELL$block), .s1(CELL$axis),
                       .s1(SPEC$factor2$id %||% SPEC$factor2$kind, "none"),
                       .s1(SPEC$weighting$kind, "ew"), .s1(SPEC$universe$kind, "k200_kq150"),
                       .s1(rf_ov_txt(SPEC$overlay), "none"))   # ★오버레이 스택(a × b) — 원장 서술에 전 층이 남는다(2026-09-17)
  # ★지식 주입(착수 전 의무) — hypothesis_index 죽은 선례 + 직전 교훈. 차단 아님, 기록.
  SPEC <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                     rf_preflight(SPEC, BID) },
                   error = function(e) { jlog("preflight_failed", code = CELL$code, err = conditionMessage(e)); SPEC })
  .pf <- SPEC$preflight
  if (!is.null(.pf) && length(.pf$dead_precedents))
    jlog("preflight_dead_precedent", code = CELL$code,
         kw = paste(names(.pf$dead_precedents), collapse = ","),
         note = "죽은 선례 존재 — 실행은 진행(AX-000: 사실 기록이지 금지 목록 아님)")
  # ★spec 경로에 entry 식별자를 넣는다. 구판은 spec_<code>.json 고정이라 다음 entry 가
  #   같은 이름으로 덮어썼고, 원장이 그 경로를 가리키는 채로 **부모 스펙이 소실**됐다
  #   (2026-08-31: 부모 B3_12 의 spec 을 열면 자식 것이 나온다 — 사후 재현 불가).
  sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
  # ★등록이 먼저다 (2026-09-03). 구판은 spec 을 먼저 쓰고 등록을 시도해서, 거부된 칸의
  #   산출물이 디스크에 남았다(실측: spec 5 vs 원장 4 — 산출물만 보면 5칸을 돈 것처럼 보인다).
  #   원장이 정본이므로 원장에 없는 칸의 흔적을 남기지 않는다.
  att <- tryCatch(rf_append_attempt(1L, BID, SPEC$idea, CELL$axis, .root_papers, wt_id = NULL, root = ROOT,
                                    unmapped_families = .rpz$unmapped_families,
                                    # ★실제 적재 여부를 넘긴다 — 상수 TRUE 는 거짓 기록이었다
                                    axiom_injected = isTRUE(SPEC$preflight$axiom_injected),
                                    # ★격자 좌표를 등록 시점에 박는다 — 커서의 정본(2026-09-04)
                                    cell_code = CELL$code),
                  error = function(e) { jlog("append_failed", base_id = BID, code = CELL$code,
                                             err = conditionMessage(e)); NULL })
  if (is.null(att)) {
    unlink(sp, force = TRUE)
    # ★거부된 칸은 자리를 잃지 않는다 — 커서가 코드 집합 기반이라 다음 tick 에 다시 잡힌다.
    #   다만 같은 사유로 계속 거부되면 근면하게 제자리를 돌 뿐이므로 상한에서 멈춰 세운다.
    .afc <- .append_fail_count(CELL$code, BID)
    if (.afc >= MAX_RETRY) {
      jlog("halt_append_stuck", code = CELL$code, fails = .afc,
           note = "등록 반복 거부 — 조용히 건너뛰지 않는다. 거부 사유를 고치고 재개할 것")
      break
    }
    next
  }
  ## ── ★기전 회피 집행은 **등록 뒤** (2026-09-05 이동) ──────────────────────────────
  ##   실사고 09:14: 이 블록이 등록(att <- rf_append_attempt) 앞에 있어 att$n 을 미정의로
  ##   읽고 러너가 fatal 로 죽었다 — 8분마다 같은 자리에서 반복되는 결정론적 정지.
  ##   "예산은 쓰되 측정은 안 한다" 는 등록이 먼저라는 뜻이다. 건너뛴 칸은 spec 을 남기지 않는다.
  ## ── ★기전 회피 목록 집행 (2026-09-04) ──────────────────────────────────────
  ##   실측: avoid 를 읽는 코드가 rf_b1_design_lib.R 하나뿐이었다(B1 설계 프롬프트).
  ##   러너는 안 읽으므로 격자 기본 칸에는 **원리상 안 걸렸다** — 기전이 무엇을 쓰지
  ##   말라고 적든 그대로 돌았다(실사고: B3_11 KOSDAQ150 단독).
  ##   ★건너뛰는 것은 **측정 무효 사유**뿐이다. "성과가 나빴다" 는 금지 목록이 아니라
  ##     사실 기록이므로(AX-000) 그건 로그만 남기고 실행한다.
  .avoid_hit <- tryCatch({
    lcd <- file.path(ROOT, "stage_artifacts/l_code/reinforcement")
    fs2 <- list.files(lcd, pattern = "[.]json$", full.names = TRUE)
    ## ★부모 사슬을 함께 본다 — 승격이 **구성은 물려받는데 교훈은 안 물려받았다**.
    ##   실사고 2026-09-04 21:50: B3_11 회피가 부모(rescued_rulefast) L-code 에 있는데
    ##   promo1 것만 보느라 안 걸렸고, 그 칸이 두 번 돌아 terminal 이 됐다.
    ##   (같은 계통: "승계 목록에서 빠진 축은 없는 축이 된다" — 오버레이가 세대마다 리셋됐던 건)
    .chain <- BID
    { .e0 <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL); .cur <- BID; .n <- 0L
      while (!is.null(.e0) && .n < 5L) {
        .k <- .rf_find(.e0, .cur); if (is.na(.k)) break
        .pp <- as.character((.e0$entries[[.k]]$parent %||% list())$base_id %||% "")
        if (!nzchar(.pp) || .pp %in% .chain) break
        .chain <- c(.chain, .pp); .cur <- .pp; .n <- .n + 1L
      } }
    fs2 <- fs2[vapply(basename(fs2), function(b)
                 any(startsWith(b, paste0("l_code_", .chain, "_B"))), logical(1))]
    hit <- NULL
    if (length(fs2)) {
      fs2 <- fs2[order(file.info(fs2)$mtime)]
      for (f2 in rev(fs2)) {
        L2 <- tryCatch(fromJSON(f2, simplifyVector = TRUE), error = function(e) NULL)
        av2 <- as.character(unlist((L2 %||% list())$avoid %||% list()))
        ## ★표적 판정은 rf_avoid.R 하나 (2026-09-05). 구판은 셀 코드가 문장 **어디에든** 나오면
        ##   표적으로 읽어, 조부모 B4 회피문("세 칸이 전부 B2_6 아래이고 … 생존편향")이 손자
        ##   B2_6(CDaR_LP · 설계 머리 칸)을 측정 무효로 잡았다 — 비교 기준으로 언급된 코드였다.
        ##   같은 문장의 "B3_13 이 대체한다" 도 표적으로 읽혀 **권고 칸**을 건너뛸 뻔했다.
        .at <- rf_avoid_target(av2, CELL$code)
        for (x in .at$noted)
          jlog("avoid_noted", code = CELL$code, why = substr(x, 1, 120),
               note = "기전 회피 목록에 있으나 **성과 사유** — 실행한다(AX-000: 사실 기록이지 금지 목록 아님)")
        if (!is.null(.at$hit)) { hit <- .at$hit; break }
      }
    }
    hit
  }, error = function(e) NULL)
  ## ★상주 칸은 회피 목록으로 건너뛰지 않는다 (2026-09-17 · WP-R) — 매 세대 재는 대조 칸이라 기전이 '쓰지 말 것' 이라
  ##   적어도 측정은 남긴다(AX-000: 사실 기록이지 금지 목록 아님). 무시했다는 사실은 로그로 드러낸다.
  if (!is.null(.avoid_hit) && isTRUE(CELL$standing)) {
    jlog("avoid_exempt_standing", n = att$n, code = CELL$code, why = substr(.avoid_hit, 1, 130),
         note = "상주 칸 — 회피 지정을 무시하고 측정한다(대조 칸은 매 세대 잰다)")
    .avoid_hit <- NULL
  }
  if (!is.null(.avoid_hit)) {
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — 기전 회피: 측정 무효 사유)",
      lessons = sprintf("%s: 기전이 측정 무효 사유로 회피 지정 — %s",
                        CELL$code, substr(.avoid_hit, 1, 160)),
      terminal = TRUE,
      terminal_reason = sprintf("기전 회피 집행 — %s", substr(.avoid_hit, 1, 160)),
      root = ROOT)
    jlog("avoid_enforced", n = att$n, code = CELL$code, why = substr(.avoid_hit, 1, 130),
         note = "측정 무효 사유 — 예산은 쓰되 측정은 안 한다(결과가 무효라 재도 소용없다)")
    next
  }

  write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  # ★중복 판정 — 배치 안 · entry 안 · **전 entry**(2026-09-03 확장) 세 층을 본다.
  #   먼저 온 칸 하나는 측정하고 나머지를 닫는다. 같은 포트폴리오에 다른 이름을 붙이지 않는다.
  #   전 entry 층을 넓힌 근거: 258 측정 중 고유 서명 230 — 28칸이 이미 잰 구성의 재측정이었고
  #   한 구성은 3개 entry 에 걸쳐 7회 반복됐다. 25칸 예산에서 그만큼이 그냥 날아간 것이다.
  .sig <- .spec_sig(SPEC)
  .dup <- .seen_sig[[.sig]]
  if (is.null(.dup) && !isTRUE(.no_treatment)) {
    .xh <- tryCatch({
      if (!exists(".COVIDX")) {
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_coverage.R"), local = TRUE))
        .COVIDX <<- rf_coverage_index(ROOT)
      }
      rf_coverage_find(.sig, .COVIDX, exclude_base = BID)
    }, error = function(e) { jlog("coverage_lookup_failed", err = conditionMessage(e)); NULL })
    if (!is.null(.xh) && nrow(.xh))
      .dup <- sprintf("%s/%s(전 entry · Grade %s)", .xh$base_id[1], .xh$cell_code[1], .xh$grade[1])
  }
  if (!isTRUE(.no_treatment) && !is.null(.dup)) {
    ## ★같은 entry 안의 중복이면 **기존 결과를 승계**한다 (도훈 지시 2026-09-04).
    ##   중복 판정은 옳다 — 같은 포트폴리오를 두 번 재지 않는다. 문제는 **답이 있는데
    ##   NA 로 남는 것**이었다: B4 전결합(=B3_11)과 유니버스 LOO(=B2_6)가 NA 로 끝나
    ##   35칸을 태운 결론(4축 LOO 표)을 사람이 손으로 재구성해야 했다.
    ##   ★뿌리는 설계 모순이다 — block_accumulate 가 앞 승자를 물려주므로 마지막 블록의
    ##     승자가 이미 전결합이고, B4 의 전결합 칸은 구조적으로 항상 중복이다.
    ##     여기서 승계하면 그 모순이 정보 손실로 바뀌지 않는다(측정은 여전히 0회).
    .prev_code <- if (!is.null(.seen_sig[[.sig]])) as.character(.seen_sig[[.sig]]) else NA_character_
    .prev_att <- NULL
    if (!is.na(.prev_code)) {
      .E9 <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL)
      .i9 <- if (!is.null(.E9)) .rf_find(.E9, BID) else NA
      if (!is.na(.i9)) {
        .cands <- Filter(function(a) identical(as.character(a$cell_code %||% ""), .prev_code),
                         .E9$entries[[.i9]]$attempts %||% list())
        if (length(.cands)) .prev_att <- .cands[[length(.cands)]]
      }
    }
    if (!is.null(.prev_att) && !is.null(.prev_att$essence) &&
        is.finite(suppressWarnings(as.numeric(.prev_att$essence$port_t %||% NA)))) {
      rf_record_result(1L, BID, att$n,
        grade = as.character(.prev_att$grade %||% "NA (승계)"),
        essence = c(.prev_att$essence, list(inherited_from = .prev_code)),
        artifacts = .prev_att$artifacts,
        lessons = sprintf("%s: 스펙이 %s 과 동일 — 측정하지 않고 그 결과를 승계한다(같은 포트폴리오다). block_accumulate 아래서 결합 칸이 앞 블록 승자와 같아지는 것은 구조적이다.",
                          CELL$code, .prev_code),
        terminal = TRUE,
        terminal_reason = sprintf("스펙 중복(%s) — 측정 생략, 결과 승계", .prev_code),
        root = ROOT)
      jlog("cell_duplicate_inherited", n = att$n, code = CELL$code, same_as = .prev_code,
           grade = as.character(.prev_att$grade %||% ""),
           note = "같은 entry 안 중복 — 기존 결과 승계(측정 0회, 답은 남는다)")
      next
    }
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — 기존 칸과 동일 스펙)",
      lessons = sprintf("%s: 스펙 서명이 %s 과 동일 — 같은 포트폴리오를 다시 재지 않는다", CELL$code, .dup),
      terminal = TRUE,
      terminal_reason = sprintf("스펙 중복(%s 와 동일) — factors=%s weighting=%s universe=%s overlay=%s",
        .dup, paste(.fkeys(SPEC$factors), collapse = "+"),
        SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?", rf_ov_txt(SPEC$overlay)),
      root = ROOT)
    jlog("cell_duplicate_spec", n = att$n, code = CELL$code, same_as = .dup,
         note = "기존 칸과 스펙 동일 — 미결 종결(실행 안 함)")
    next
  }
  .seen_sig[[.sig]] <- CELL$code
  if (isTRUE(.no_treatment)) {
    # 원장에는 칸이 남되(격자 번호 대응 유지) 측정은 없다. essence 가 없으므로
    # .winner_of 후보에서 자동으로 빠진다 — 무처치 칸이 승자가 되는 경로가 닫힌다.
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — carry 와 동일·처치 미전달)",
      lessons = sprintf("%s: 중복 제거 후 구성이 carry 와 동일 — 같은 포트폴리오에 다른 이름을 붙이지 않는다", CELL$code),
      terminal = TRUE,
      terminal_reason = sprintf("무처치(carry 동일) — factors=%s weighting=%s universe=%s overlay=%s",
        paste(.fkeys(SPEC$factors), collapse = "+"), SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?",
        rf_ov_txt(SPEC$overlay)),
      root = ROOT)
    jlog("cell_no_treatment", n = att$n, code = CELL$code,
         note = "carry 와 동일 — 미결 종결(실행 안 함)")
    next
  }
  # ── ★arm × 유니버스 양립성 사전 검사 (도훈 지시 ③ · 2026-09-04) ──
  #   실사고: 비중 arm entropy 가 KQ150 단독 위에서 커버리지 77%(<80%) 로 막혔다.
  #   엔진 가드는 옷게 발화했지만 **백테를 다 돌린 뒤**였고, 결정론이라 재시도까지 태웠다
  #   (3칸 × 2회). 같은 조합은 몇 번을 돌려도 같은 자리에서 죽는다.
  #   ⇒ 이미 막힌 적 있는 조합이면 스폰하지 않고 미결로 닫는다. 판정 근거는 **실행 기록**
  #     뿐이고 추정하지 않는다 — 첫 조합은 여전히 한 번 태운다(정직한 비용).
  ## ★승계 비중이 이 유니버스에서 불가면 칸을 닫지 않고 EW 로 강등해 측정한다 (2026-09-04 · B4 포함 2026-09-13).
  ##   판정 = rf_arm_compat::rac_gate (차단 → rac_degrade_plan → 강등 spec 재검사). 재개 경로와 같은 헬퍼다.
  ##   ⚠강등은 위 중복 판정 **뒤**에 일어난다 — B4 전결합이 강등되면 같은 배치의 '−비중' 칸과 같은 구성이
  ##     되어 두 칸 모두 측정된다(의도: 죽은 칸보다 측정된 중복 · loo_equivalent 가 동치를 명시한다).
  if (identical(.rac_gate_apply(SPEC, sp, CELL, att$n, "register"), "closed")) next
  jobs[[length(jobs) + 1L]] <- list(n = as.integer(att$n), code = CELL$code, spec = sp,
    name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
    out = file.path(WDIR, sprintf("result_%s.json", CELL$code)))
}
if (!length(jobs)) {
  ## ★격자 소진 (2026-09-05 실사고): B1 설계 9칸으로 예산 25→29, B3 설계 4칸이라 격자 총합 28 → used 28 < 29 로
  ##   예산 소진이 영영 안 서고 매 tick halt_no_jobs — 승격·다음 논문 모두 정지(무동작이 대기로 보였다).
  ##   빈 칸이 없고 재개 대상도 없으면 예산이 남아도 소진이다(정본 rf_spec_sig.R::rf_grid_consumed — 커서와 같은 정의).
  if (isTRUE(rf_grid_consumed(cells, E$attempts))) {
    jlog("grid_consumed", base_id = BID, used = used, max_attempts = MAXA, n_cells = length(cells),
         note = "격자 전 칸 측정 완료 — 예산 미달이어도 소진 처리")
    return(.exhaust_and_delegate("grid"))
  }
  jlog("halt_no_jobs"); return(1L)
}

# ── ② 실행 (병렬 — 워커는 원장 미접근) ────────────────────────────────────────
for (j in jobs) {
  ## ★재개 job — **신뢰할 수 있는 기존 결과는 다시 재지 않는다** (2026-09-07 · 정본 rf_spec_sig.R::rf_result_reusable).
  ##   실사고 2026-09-05 23:14: 워커 5개 스폰 직후 절전으로 부모만 죽었는데(SCHED_S_TASK_TERMINATED) 워커 4개는
  ##   result_B2_{6,8,9,10}.json 을 정상 완료했다. 다음 tick 이 아래 unlink 로 그 파일을 지우고 5칸을 전부 재실행 —
  ##   8분 낭비 + 같은 칸의 중복 산출물·L-code. 조건(ok · 같은 칸 · 같은 spec · spec 보다 새것 · essence ·
  ##   artifacts/authoritative_remeasure.json 실재) 하나라도 어긋나면 현행대로 지우고 다시 돈다.
  ##   재사용한 결과는 ③ 수집 절이 평소대로 읽어 원장에 기록한다(워커 미스폰 · 대기 루프는 파일 존재로 곧장 통과).
  if (isTRUE(j$resume)) {
    .ru <- rf_result_reusable(j, ROOT)
    if (isTRUE(.ru$reuse)) {
      jlog("resume_reuse_result", n = j$n, code = j$code, artifacts = .ru$artifacts,
           note = "완료된 워커 결과 재사용 — 재측정 없이 수집 절로")
      next
    }
    jlog("resume_rerun", n = j$n, code = j$code, why = .ru$why)
  }
  unlink(j$out, force = TRUE)
  # ★stderr 는 파일명/TRUE/FALSE 만 받는다. "2>&1"(셸 관용구)을 넘기면 R 이 **파일명으로 해석**하고
  #   Windows 에서 '>' 는 부정 문자라 실행이 조용히 죽는다(2026-08-30 실사고 — 워커 4개 전부 미기동).
  .wlog <- file.path(WDIR, sprintf("log_%s.txt", j$code))
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R")),
                       shQuote(j$spec), j$n, shQuote(j$name), shQuote(j$out)),
          wait = FALSE, stdout = .wlog, stderr = .wlog)
  jlog("worker_spawn", n = j$n, code = j$code)
}
TIMEOUT_S <- as.integer(CFG$worker_timeout_sec %||% 5400L)
t0 <- Sys.time()
repeat {
  ndone <- sum(vapply(jobs, function(j) file.exists(j$out), logical(1)))
  if (ndone >= length(jobs)) break
  if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > TIMEOUT_S) {
    jlog("worker_timeout", done = ndone, total = length(jobs)); break }
  Sys.sleep(20)
}

# ── ③ 결과 수집 (순차 — 원장 단독 접근) ──────────────────────────────────────
# ★fail_count 는 **지금 원장**에서 읽는다. main() 초입의 E 스냅샷은 신규 배치에서
#   등록(rf_append_attempt)보다 앞서 찍혀 그 칸을 아예 모른다 — 스냅샷을 뒤지면
#   재개분에서만 맞고 신규분에서는 subscript 오류로 배치 전체가 fatal 로 떨어진다.
.fail_count_of <- function(n) {
  e <- tryCatch(Filter(function(x) identical(x$base_id, BID), rf_load(1L, ROOT)$entries)[[1]],
                error = function(z) NULL)
  if (is.null(e)) return(0L)
  a <- Filter(function(x) identical(as.integer(x$n), as.integer(n)), e$attempts)
  if (!length(a)) 0L else as.integer(a[[1]]$fail_count %||% 0L)
}
## ── ★Grade A 발행 1함수 (2026-09-17 · 보류/해제 두 경로가 같은 코드를 쓴다) ──────────────────────────────
##   judge_request + grade_a_queue + 팡파레 + 텔레그램. 구판은 수집 루프 인라인이었는데 적대검증 보류(아래)가
##   블록 경계에서 같은 발행을 다시 해야 해서 함수로 뺐다 — 발행 경로가 둘이면 표식도 둘이 같아야 한다.
.grade_a_enqueue <- function(n, code, artifacts, essence) {
  jr <- file.path(ROOT, "qepm/mailbox/judge_request.json")
  dir.create(dirname(jr), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = "reinforce_auto_parallel",
                    base_id = BID, attempt = n, cell = code, artifacts = artifacts, grade = "A"),
               auto_unbox = TRUE, pretty = TRUE), jr)
  # ★Grade A 는 **리서치를 멈추지 않는다** (도훈 지시 2026-08-30 "A등급 달성하더라도 리서치가 이어지게").
  #   구판은 enabled=false 로 전 루프를 세웠는데, 그건 **리서치 루프**와 **BOOK 등재 관문**을 뒤섞은 것이다.
  #   후보 하나가 A 를 찍었다고 나머지 칸·다음 논문이 설 이유가 없다. A 는 큐에 쌓이고 루프는 계속 돈다.
  #   ★불변: BOOK 등재는 여전히 Judge(PIT) + 도훈 confirm 을 거친다 — 자동 등재는 없다(헌법).
  .aq <- file.path(ROOT, "06_Registry/grade_a_queue.json")
  .q <- if (file.exists(.aq)) tryCatch(fromJSON(.aq, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(.q) || is.null(.q$entries)) .q <- list(schema = "grade_a_queue_v1",
    note = "essence Grade A 후보 대기열. Judge(PIT) 검증 + 도훈 confirm 후 BOOK 등재. 러너는 여기 쌓기만 하고 멈추지 않는다.",
    entries = list())
  .q$entries[[length(.q$entries) + 1L]] <- list(
    queued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), base_id = BID, attempt = n,
    cell = code, artifacts = artifacts, grade = "A", status = "awaiting_judge")
  write(toJSON(.q, auto_unbox = TRUE, pretty = TRUE, null = "null"), .aq)
  jlog("grade_a_queued", n = n, code = code, note = "루프 계속 — Judge/BOOK 만 confirm 대기")
  tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
             ## ★A 는 즉시 경로에서도 팡파레를 앞세운다 (중복은 마커가 막는다)
             tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_grade_fanfare.R"))
                        .EA <- rf_load(1L, ROOT); .iA <- .rf_find(.EA, BID)
                        if (!is.na(.iA)) rf_grade_fanfare(BID, "A", code,
                          essence %||% list(), n = n, maxa = MAXA,
                          title = .rf_target_label(.EA$entries[[.iA]]),
                          base_grade = .EA$entries[[.iA]]$base_grade %||% "", root = ROOT) },
                      error = function(e) jlog("grade_fanfare_failed", err = conditionMessage(e)))
             rf_auto_notify(BID, n, kind = "grade_a") }, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  invisible(TRUE)
}
.held_a <- list()   # ★적대검증 보류 중인 A (이 tick) — 블록 경계에서 verdict 로 풀거나 막는다
nb <- 0L
for (j in jobs) {
  if (!file.exists(j$out)) {
    .fc0 <- .fail_count_of(j$n)
    .term <- (.fc0 + 1L) >= MAX_RETRY
    rf_record_result(1L, BID, j$n, grade = "NA (등급 미발행 — 병렬 워커 미완료/시간초과)",
                     lessons = sprintf("워커 산출 부재: %s (로그 %s)", j$out, file.path(WDIR, sprintf("log_%s.txt", j$code))),
                     terminal = .term,
                     terminal_reason = if (.term) sprintf("워커 산출 부재 %d회 연속 — 재시도 상한 %d 도달", .fc0 + 1L, MAX_RETRY) else NULL,
                     root = ROOT)
    jlog("cell_missing", n = j$n, code = j$code, fail_count = .fc0 + 1L, terminal = .term); next
  }
  R <- fromJSON(j$out, simplifyVector = FALSE)
  if (!isTRUE(R$ok)) {
    .err <- R$err %||% "?"
    # ★두 종류의 실패를 가른다. 재개는 하나에만 의미가 있다.
    #   ① 구조적(결정론) — rf_cell_engine 의 "측정 무효" 계열. 처치가 전달되지 않았거나
    #      기저가 그 변환을 지지하지 않는다. 스펙이 그대로면 재실행해도 같은 자리에서 죽는다.
    #      이건 실행 실패가 아니라 **판정**이다 — 미결(미측정)로 닫는다.
    #   ② 일시적 — 워커 미기동·시간초과·자원. 재개가 존재하는 이유. 단 무한은 아니다:
    #      같은 칸이 cell_max_retry 회 실패하면 닫는다(무한 루프는 침묵과 같다).
    .structural <- grepl("측정 무효|처치 미전달", .err)
    .fc0 <- .fail_count_of(j$n)
    .term <- .structural || (.fc0 + 1L) >= MAX_RETRY
    .reason <- if (.structural) sprintf("구조적 미결(결정론) — %s", .err)
               else sprintf("일시 실패 %d회 연속 — 재시도 상한 %d 도달: %s", .fc0 + 1L, MAX_RETRY, .err)
    rf_record_result(1L, BID, j$n,
                     grade = if (.structural) "NA (미결 — 처치 미전달·측정 무효)"
                             else "NA (등급 미발행 — 병렬 실행 실패)",
                     lessons = sprintf("%s 실패: %s", j$code, .err),
                     terminal = .term, terminal_reason = if (.term) .reason else NULL,
                     root = ROOT)
    # ★커버리지 실패를 장부에 남긴다 — 다음부터는 백테 전에 막힌다.
    #   다른 실패는 기록하지 않는다(과잉 차단 금지) — 엔진 메시지가 정본이다.
    if (grepl("커버리지", .err, fixed = TRUE))
      tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
                 .sp3 <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
                 if (!is.null(.sp3)) rac_record(.sp3, "coverage_fail", ROOT,
                                                detail = substr(.err, 1, 160), cell = j$code) },
               error = function(e) jlog("arm_compat_record_failed", err = conditionMessage(e)))
    jlog("cell_error", n = j$n, code = j$code, err = .err,
         structural = .structural, fail_count = .fc0 + 1L, terminal = .term); next
  }
  es <- R$essence
  # ★교훈은 지표 되풀이가 아니라 **기전 서술**이다 (2026-09-03). essence 의 숫자를 그대로
  #   옮겨 적으면 한계 정보량이 0이고, 그게 무인 교훈 269건 중 247건(92%)의 상태였다.
  #   무엇이 막았고 carry 대비 위험·수익이 어느 쪽으로 더 움직였는지를 적는다 — LLM 불필요.
  .carry_es <- tryCatch({
    .cw <- Filter(function(a) is.list(a$essence) && !is.null(a$essence$port_t), E$attempts)
    if (length(.cw)) .cw[[length(.cw)]]$essence else NULL
  }, error = function(e) NULL)
  .lsn <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"))
    rf_lesson_text(j$code, R$grade, es, carry_es = .carry_es, root = ROOT)
  }, error = function(e) sprintf("[%s] Grade %s (기전 서술 생성 실패: %s)",
                                 j$code, R$grade, conditionMessage(e)))
  ## ★강등 표식을 원장 교훈 머리에도 (2026-09-13) — spec.carry_degraded 에만 있으면 원장·텔레그램 독자는
  ##   "전 요소 결합(4축)" 이 실제로는 비중을 EW 로 바꿔 잰 칸인 줄 모른다. 조용한 통과 금지.
  .cdg <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE)$carry_degraded, error = function(e) NULL)
  if (is.list(.cdg)) .lsn <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
    paste(rac_degrade_note(.cdg), .lsn) }, error = function(e) .lsn)
  rf_record_result(1L, BID, j$n, grade = R$grade, essence = es, artifacts = R$artifacts,
    lessons = .lsn, root = ROOT)
  # ★고정 축 사후 검증 — 공리를 주입하는 대신 산출물에서 재도출해 확인한다
  .vf <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                    rf_preflight_verify_axes(file.path(R$artifacts, "authoritative_remeasure.json"),
                                             PROG$fixed_axes) },
                  error = function(e) list(ok = NA, note = conditionMessage(e)))
  if (identical(.vf$ok, FALSE))
    jlog("AXIS_VIOLATION", n = j$n, code = j$code, violations = paste(.vf$violations, collapse = "; "))
  # ★장부 기록 — 통과한 (arm, universe) 조합을 남긴다. 실패만 모으면 장부가 금지 목록이 되고,
  #   금지 목록은 AX-000 위반이다. 성공도 같이 남겨야 "막힌 적 있다" 가 의미를 갖는다.
  tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
             .sp2 <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
             if (!is.null(.sp2)) rac_record(.sp2, "ok", ROOT, detail = "cell_done", cell = j$code) },
           error = function(e) jlog("arm_compat_record_failed", err = conditionMessage(e)))
  jlog("cell_done", n = j$n, code = j$code, grade = R$grade,
       port_t = es$port_t, calmar = es$calmar, axes_ok = .vf$ok, artifacts = R$artifacts)
  nb <- nb + 1L
  if (identical(R$grade, "A")) {
    # ★적대검증 보류 (2026-09-17 · G2): 자기 오버레이 층을 가진 B5 칸의 A 는 반증(lag-1 · strict-PIT · 노출 짝지은
    #   placebo · 정적 등가)을 지나야 Judge 큐에 오른다 — 동월 누출로 낸 A 를 Judge 앞에 세우지 않는다.
    #   보류 = 등급 불변 · 발행만 미룸(정본 rf_runner_gates.R::rf_grade_a_hold). 블록 경계(아래)에서 verdict 로 푼다.
    .spA <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
    if (rf_grade_a_hold(j$code, .spA, E$carry$overlay)) {
      .held_a[[length(.held_a) + 1L]] <- list(n = j$n, code = j$code, artifacts = R$artifacts, essence = es)
      jlog("grade_a_hold_adversary", n = j$n, code = j$code,
           note = "B5 자기 층 A — 적대검증 pass 전엔 judge_request·grade_a_queue 미발행(등급 불변)")
    } else .grade_a_enqueue(j$n, j$code, R$artifacts, es)
  }
}

# ── 텔레그램: 블록 경계를 넘었으면 1회 ────────────────────────────────────────
led2 <- rf_load(1L, ROOT)
E2 <- Filter(function(e) identical(e$base_id, BID), led2$entries)[[1]]
u2 <- as.integer(E2$attempts_used %||% 0L)
# ★조건에 `u2 > used` 를 걸면 **재개 경로에서 영영 안 나간다**(재개는 used 가 이미 최종값).
#   2026-08-30 실사고: 17~20 을 재개로 측정하고도 20/20 텔레그램이 0건이었다.
#   판정 축을 "칸 수가 늘었나" 가 아니라 "이번 배치가 실제로 기록했나(nb>0)" 로 바꾼다.
# ★블록 경계는 **격자에서 재도출**한다 (2026-09-04). 구판은 `u2 %% 5L == 0L` — 개수였다.
#   B1 이 설계에 따라 가변 길이가 된 순간 그 판정이 틀린다: 실측으로 B1 설계 14칸에서
#   5칸·10칸(블록 **한가운데**)에 쏘고 14칸(진짜 경계)에는 **안 쐈다** — 그 블록의 텔레그램과
#   L-code 가 통째로 증발했다. 격자 커서를 코드 기반으로 바꾼 것과 같은 병이 알림 층에 남아 있었다.
#   판정 축: "이 블록에 아직 빈 칸이 남았는가". 남지 않았으면 그게 경계다.
.blk_now <- if (!is.null(first)) as.character(first$block %||% "") else {
  .cc <- vapply(E2$attempts %||% list(),
                function(a) as.character(a$cell_code %||% (a$essence$cell_code %||% "")), character(1))
  .cc <- .cc[nzchar(.cc)]
  if (length(.cc)) sub("_.*$", "", .cc[length(.cc)]) else ""
}
.blk_left <- if (nzchar(.blk_now)) {
  .fr2 <- .rf_free_cells(cells, E2$attempts %||% list())
  sum(vapply(cells[.fr2], function(c) identical(as.character(c$block %||% ""), .blk_now), logical(1)))
} else 0L

# ── ★B5 적대 반증 (G2 · 2026-09-17) — B5 블록이 닫혔거나 보류된 A 가 있으면 L-code **앞에서** 돈다 ─────────
#   pass 만 블록 승자·carry·Grade A 후보로 소비된다(rf_overlay_adversary.R 소비자 규약 · 표식은 원장 attempt$adversary).
#   실패는 러너를 세우지 않는다(adversary_failed 로 남긴다). 보류된 A 는 A 를 낸 순간 entry 가 graduated 로 바뀌어
#   다음 tick 이 이 entry 를 다시 안 보므로 **같은 tick 안에서** 풀어야 한다 — 그래서 블록 미완이어도 보류 A 가 있으면 돈다.
.adv_ran <- FALSE
if (nb > 0L && ((identical(.blk_now, "B5") && .blk_left == 0L) || length(.held_a))) {
  .adv <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), local = TRUE))
    rf_overlay_adversary_run(BID, "B5", 1L, root = ROOT)
  }, error = function(e) { jlog("adversary_failed", base_id = BID, block = "B5", err = conditionMessage(e)); NULL })
  if (!is.null(.adv)) { .adv_ran <- TRUE
    jlog("adversary_done", base_id = BID, block = "B5", n = NROW(.adv),
         verdicts = if (NROW(.adv)) paste(sprintf("%s=%s", .adv$code, .adv$verdict), collapse = ",") else "",
         held_a = length(.held_a)) }
  # 보류된 A — verdict 는 **원장에서 다시 읽는다**(러너 지역 목록은 n·산출물만 든다). pass → 발행 · 그 밖 → 막힘(등급 불변).
  if (length(.held_a)) {
    .EH <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL); .iH <- if (!is.null(.EH)) .rf_find(.EH, BID) else NA
    for (h in .held_a) {
      .aH <- if (!is.na(.iH)) Filter(function(a) identical(as.integer(a$n), as.integer(h$n)), .EH$entries[[.iH]]$attempts %||% list()) else list()
      .vH <- if (length(.aH)) as.character((.aH[[1]]$adversary %||% list())$verdict %||% "")[1] else ""
      if (identical(.vH, "pass")) {
        jlog("grade_a_released", n = h$n, code = h$code, verdict = .vH, note = "적대검증 pass — judge_request·grade_a_queue 발행")
        .grade_a_enqueue(h$n, h$code, h$artifacts, h$essence)
      } else if (.vH %in% c("fail", "error", "not_candidate")) {
        jlog("grade_a_adversary_blocked", n = h$n, code = h$code, verdict = .vH,
             note = "적대검증 미통과 — Judge 큐 미발행(등급 불변 · 소비 보류). 수리·재측정 후 재검증")
      } else jlog("grade_a_hold_unresolved", n = h$n, code = h$code, adversary_ran = .adv_ran,
                  note = "verdict 없음(적대검증 미완) — 발행 보류 유지. 수동: rf_overlay_adversary_run 후 grade_a 발행")
    }
  }
  # ★재설계 라운드 종료 표식 (B5 설계 레인 계약) — 재설계 배치가 다 돌고 적대검증까지 지나면 러너가 닫는다.
  if (.redesign_on && identical(.blk_now, "B5") && .blk_left == 0L)
    tryCatch({ rf_record_b5_redesign(1L, BID, list(active = FALSE, closed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                                                   closed_by = "reinforce_auto_parallel:b5_boundary", adversary_ran = .adv_ran),
                                     root = ROOT)
               jlog("b5_redesign_closed", base_id = BID, adversary_ran = .adv_ran) },
             error = function(e) jlog("b5_redesign_close_failed", base_id = BID, err = conditionMessage(e)))
}
if (nb > 0L && (.blk_left == 0L || u2 >= MAXA)) {
  # ★순서 (2026-09-04): L-code -> 기전 -> **텔레그램**.
  #   구판은 텔레그램이 먼저라 기전·처방이 메시지에 영원히 못 들어갔다 — 도훈이 받는 보고에
  #   "무엇을 배웠고 다음에 뭘 할 것인가" 가 빠져 있었다. 발송을 뒤로 옮긴다.
  lc <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R"))
                   rf_emit_block_lcode(BID, u2, root = ROOT) },
                 error = function(e) { jlog("lcode_failed", err = conditionMessage(e)); NULL })
  jlog("lcode_block", n = u2, l_code = as.character(lc %||% "NA"))
  # 기전 서술 — 규칙이 적은 수치 척추 위에 "왜" 한 문단 + 다음 블록 처방.
  #   재료에 이 전략의 앞선 블록 L-code 를 함께 넣는다(누적 교훈 참조).
  #   병합은 R 이 하고 구조 검증(셀 인용·금칙어·처방 존재)을 통과해야 얹힌다.
  if (!is.null(lc) && nzchar(as.character(lc))) {
    .mblk <- if (!is.na(.blk_now) && nzchar(.blk_now)) .blk_now else NA_character_
    if (!is.na(.mblk)) tryCatch(system2("bash",
        c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh")),
          shQuote(BID), shQuote(.mblk)), wait = TRUE, stdout = TRUE, stderr = TRUE),
      error = function(e) jlog("lcode_mechanism_failed", err = conditionMessage(e)))
  }
  # ★등급 팡파레 — 블록 보고 **앞에** 짧은 이펙트 하나 (도훈 지시 2026-09-04).
  #   이번 블록이 이 entry 의 **첫 B(또는 A)** 를 냈을 때만. 원장에서 재도출한다 —
  #   "B 가 있다" 가 아니라 "이번 블록이 처음 만들었다" 여야 한다. 그러지 않으면
  #   B 하나 나온 뒤 매 블록 축포가 울려 소음이 된다(적응형 절이 밟은 그 병).
  tryCatch({
    source(file.path(ROOT, "02_Infrastructure/ops/rf_grade_fanfare.R"))
    .E3 <- rf_load(1L, ROOT); .i3 <- .rf_find(.E3, BID)
    if (!is.na(.i3)) {
      .en3 <- .E3$entries[[.i3]]
      .bc  <- vapply(cells, function(c) as.character(c$code %||% ""), character(1))
      .bc  <- .bc[startsWith(.bc, paste0(.blk_now, "_"))]
      .ng  <- rf_fanfare_new_grade(.en3, .bc)
      if (!is.na(.ng)) {
        .hit <- Filter(function(a) identical(toupper(substr(as.character(a$grade %||% ""), 1, 1)), .ng) &&
                         as.character(a$cell_code %||% "") %in% .bc, .en3$attempts %||% list())
        if (length(.hit)) {
          .h1 <- .hit[[which.max(vapply(.hit, function(a)
                    suppressWarnings(as.numeric((a$essence %||% list())$port_t %||% NA)), numeric(1)))]]
          .fok <- rf_grade_fanfare(BID, .ng, as.character(.h1$cell_code %||% ""),
                    .h1$essence %||% list(), n = u2, maxa = MAXA,
                    title = .rf_target_label(.en3), base_grade = .en3$base_grade %||% "",
                    root = ROOT)
          jlog("grade_fanfare", grade = .ng, code = as.character(.h1$cell_code %||% ""), sent = .fok)
        }
      }
    }
  }, error = function(e) jlog("grade_fanfare_failed", err = conditionMessage(e)))
  # ★"보냈다" 를 예외 부재로 지어내지 않는다 — rf_auto_notify 가 실제 발송 결과를 돌려준다.
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   isTRUE(rf_auto_notify(BID, u2, kind = "block")) },
                 error = function(e) { jlog("telegram_failed", err = conditionMessage(e)); FALSE })
  if (!ok) jlog("telegram_send_failed", n = u2,
                note = "발송 실패 — lock 미생성이므로 다음 tick 이 재발송을 시도한다")
  jlog("telegram_block", n = u2, sent = ok)
  # ★증류 주기 맞춤 (도훈 지시 2026-09-04) — corpus 는 부팅마다 갱신되는데 증류
  #   (cluster_extractor)는 주간 cleaner 안에서만 돌았다. 강화는 하루에 블록 L-code 를
  #   5~6건 내므로 주 1회로는 못 따라간다 — 실측: 강화 75건이 corpus 에 있는데
  #   distilled 에는 0건이었다(오늘 수동 실행하자 후보 7건이 바로 나왔다).
  #   ⇒ 블록 L-code 를 낸 자리에서 증류도 같이 돈다. 실패해도 루프는 안 선다.
  tryCatch(system2(Sys.getenv("QVEST_PY", "python"),
      c(shQuote(file.path(ROOT, "02_Infrastructure/axiom/lcode_harvester.py"))),
      env = character(0), wait = TRUE, stdout = FALSE, stderr = FALSE),
    error = function(e) jlog("harvest_failed", err = conditionMessage(e)))
  .dz <- tryCatch(system2(Sys.getenv("QVEST_PY", "python"),
      c(shQuote(file.path(ROOT, "02_Infrastructure/axiom/cluster_extractor.py"))),
      wait = TRUE, stdout = TRUE, stderr = TRUE), error = function(e) NULL)
  jlog("distill_ran", n = u2,
       new_cands = length(grep("CAND_", as.character(.dz %||% character(0)), value = TRUE)),
       note = "블록 L-code 발행 직후 증류 — 주간 주기가 강화 속도를 못 따라간다")
}
jlog("batch_done", block = (if (!is.null(first)) first$block else "resume"), recorded = nb, used = u2)
0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
.rel <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited") else rf_claim_release(CLAIM)
# ★표식이 남은 해제는 실패가 아니다(2026-09-19) — 다음 tick 이 released.json 을 보고 즉시 제자리 인수한다.
#   구판은 이것을 claim_release_failed 로 찍어 09-13~17 에만 19건 상시 오탐이 됐다(진짜 실패를 가린다).
if (identical(.rel$reason, "marker_left")) jlog("claim_release_marker", reason = .rel$reason,
     note = "디렉터리는 못 지웠지만 해제 표식을 남겼다 — 다음 tick 이 즉시 제자리 인수한다(정보)")
if (!isTRUE(.rel$ok)) jlog("claim_release_failed", reason = .rel$reason, err = .rel$err %||% "",
     note = "디렉터리도 표식도 남았다 — owner.json 의 pid 가 죽으면(빈 고아면 60초 뒤) 다음 tick 이 회수한다")
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
