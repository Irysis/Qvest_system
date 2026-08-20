# test_knowledge_index_stale.R — knowledge_index 신선도 검사의 **검출력** 시험
#
# 대상: 02_Infrastructure/ops/knowledge_index_freshness.R
#   (check_knowledge_index_freshness / repair_knowledge_index)
#
# 왜 이 시험이 본체인가:
#   신선도 계기를 mtime 대리 지표에서 **내용 카운트/ID 집합**으로 바꾸는 작업은
#   검출력을 죽이기 쉽다. 오탐만 사라지고 진짜 낙후를 못 잡으면 이전보다 나쁘다 —
#   검사 사망과 정상은 겉보기가 같다(둘 다 초록). 그래서 양방향으로 잰다:
#     [정상]  실제 일치 상태에서 경보가 **안 뜨는지**
#     [위반]  일부러 만든 진짜 드리프트에서 경보가 **뜨는지**
#   그리고 ★모든 위반 주입은 **조작 선행검증**(사본이 실제로 의도한 상태가 됐는지)을
#   먼저 통과해야 결론을 낼 자격이 생긴다 — 치환 실패를 "전파 안 됨"으로 오귀속한 사고 방지.
#
# 픽스처: native Windows 임시 디렉터리(TEMP)에 정본 입력을 **복사**해서만 만든다.
#   원본 06_Registry / .cache 는 읽기만 하고 절대 쓰지 않는다.
#
# 실행: Rscript 08_Tests/hooks/test_knowledge_index_stale.R

suppressWarnings(suppressMessages(library(jsonlite)))

.resolve_proj <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
              "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())) {
    if (nzchar(p) && dir.exists(file.path(p, "06_Registry")) &&
        dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  getwd()
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

SRC <- file.path(PROJ, "02_Infrastructure/ops/knowledge_index_freshness.R")
if (!file.exists(SRC)) { cat(sprintf("  FAIL: source_present — 검사기 부재: %s\n", SRC)); quit(status = 1L) }
source(SRC, local = FALSE)

# ── 픽스처 유틸 ──────────────────────────────────────────────────────────────
TMPBASE <- Sys.getenv("TEMP", unset = Sys.getenv("TMP", unset = file.path(PROJ, ".cache")))
FXROOT  <- file.path(TMPBASE, sprintf("kif_test_%s_%s", Sys.getpid(),
                                      format(Sys.time(), "%H%M%S")))
dir.create(FXROOT, recursive = TRUE, showWarnings = FALSE)

REAL_CORPUS <- file.path(PROJ, ".cache/lcode_corpus.json")
REAL_INDEX  <- file.path(PROJ, "06_Registry/knowledge_index.json")

# 픽스처 1개 = {corpus, index} 한 쌍. 정본을 복사한 뒤 변형자(mutator)를 적용한다.
new_fixture <- function(name, mutate_corpus = identity, mutate_index = identity,
                        drop_corpus = FALSE, drop_index = FALSE) {
  d <- file.path(FXROOT, name)
  dir.create(file.path(d, ".cache"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  if (!drop_corpus) {
    co <- fromJSON(REAL_CORPUS, simplifyVector = FALSE)
    co <- mutate_corpus(co)
    write_json(co, file.path(d, ".cache/lcode_corpus.json"), auto_unbox = TRUE, null = "null")
  }
  if (!drop_index) {
    ix <- fromJSON(REAL_INDEX, simplifyVector = FALSE)
    ix <- mutate_index(ix)
    write_json(ix, file.path(d, "06_Registry/knowledge_index.json"), auto_unbox = TRUE, null = "null")
  }
  d
}
fx_check <- function(d) check_knowledge_index_freshness(
  corpus_path = file.path(d, ".cache/lcode_corpus.json"),
  index_path  = file.path(d, "06_Registry/knowledge_index.json"))

# 픽스처 실측 상태 (조작 선행검증용) — 검사기를 **거치지 않고** 직접 센다.
fx_state <- function(d) {
  cp <- file.path(d, ".cache/lcode_corpus.json"); ip <- file.path(d, "06_Registry/knowledge_index.json")
  co <- if (file.exists(cp)) fromJSON(cp, simplifyVector = FALSE) else NULL
  ix <- if (file.exists(ip)) fromJSON(ip, simplifyVector = FALSE) else NULL
  list(corpus_exists = !is.null(co), index_exists = !is.null(ix),
       n_corpus = if (is.null(co)) NA_integer_ else length(co$lcodes),
       n_index  = if (is.null(ix)) NA_integer_ else length(ix$lcode_corpus),
       index_counts_field = if (is.null(ix)) NA_integer_ else as.integer(ix$counts$lcode_corpus),
       corpus_ids = if (is.null(co)) character(0) else vapply(co$lcodes, function(e) as.character(e$l_code %||% "")[1], character(1)),
       index_ids  = if (is.null(ix)) character(0) else vapply(ix$lcode_corpus, function(e) as.character(e$id %||% "")[1], character(1)))
}

cat("=== knowledge_index 신선도 검사 — 양방향 검출력 시험 ===\n")
cat(sprintf("  픽스처 루트: %s\n", FXROOT))

# 정본 실측 (읽기 전용, 판정에 쓰지 않음 — 기준선 인용용)
real_state <- list(
  n_corpus = length(fromJSON(REAL_CORPUS, simplifyVector = FALSE)$lcodes),
  n_index  = length(fromJSON(REAL_INDEX,  simplifyVector = FALSE)$lcode_corpus))
cat(sprintf("  정본 실측: corpus %d / index %d\n\n", real_state$n_corpus, real_state$n_index))

# ── [정상] 카운트·ID 일치 → 경보 없음 ────────────────────────────────────────
cat("--- [정상] 일치 상태 ---\n")
fx_ok <- new_fixture("ok")
st <- fx_state(fx_ok)
# ★조작 선행검증: 무변형 사본이 정본과 같은 상태인지 먼저 확인
if (identical(st$n_corpus, st$n_index) && st$n_corpus == real_state$n_corpus)
  ok("setup_ok_fixture_is_matched", sprintf("사본 corpus %d = index %d (정본과 동일)", st$n_corpus, st$n_index))
else
  bad("setup_ok_fixture_is_matched", sprintf("사본이 의도한 일치 상태가 아님 (c=%s i=%s)", st$n_corpus, st$n_index))

r <- fx_check(fx_ok)
if (identical(r$status, "OK")) ok("normal_no_alarm", sprintf("status=OK (%s)", r$reason))
else bad("normal_no_alarm", sprintf("일치 상태인데 경보 — status=%s reason=%s", r$status, r$reason))

# ── [위반 주입 A] index 카운트를 낮춘 사본 → 경보 ───────────────────────────
# 실사고 재현: corpus 는 늘었는데 index 만 정체 (부팅 없는 세션의 L-code 적립).
cat("\n--- [위반 주입 A] index 낙후 (행 3개 삭제 + counts 동반 하향) ---\n")
fx_a <- new_fixture("stale_index", mutate_index = function(ix) {
  keep <- seq_len(length(ix$lcode_corpus) - 3L)
  ix$lcode_corpus <- ix$lcode_corpus[keep]
  ix$counts$lcode_corpus <- length(keep)      # 빌더가 만든 것처럼 일관되게 낮춤
  ix
})
st_a <- fx_state(fx_a)
# ★조작 선행검증
if (st_a$n_index == real_state$n_index - 3L && identical(st_a$index_counts_field, st_a$n_index))
  ok("setup_A_mutation_took", sprintf("index %d → %d (counts 필드도 %d 로 동반 하향 = 자기일관 낙후)",
                                      real_state$n_index, st_a$n_index, st_a$index_counts_field))
else
  bad("setup_A_mutation_took", sprintf("조작 미적용 — index=%s counts=%s (기대 %d)",
                                       st_a$n_index, st_a$index_counts_field, real_state$n_index - 3L))

r <- fx_check(fx_a)
if (identical(r$status, "STALE") && r$n_missing_in_index == 3L)
  ok("inject_A_alarm", sprintf("status=STALE · missing_in_index=%d · %s",
                               r$n_missing_in_index, paste(r$missing_sample, collapse = ",")))
else
  bad("inject_A_alarm", sprintf("진짜 낙후를 못 잡음 — status=%s reason=%s", r$status, r$reason))

# ── [위반 주입 B] corpus 에 L-code 추가 → 경보 ──────────────────────────────
cat("\n--- [위반 주입 B] corpus 신규 적립 (index 미반영) ---\n")
NEWID <- "L-TEST-INJECT-0001"
fx_b <- new_fixture("new_lcode", mutate_corpus = function(co) {
  proto <- co$lcodes[[1]]
  proto$l_code <- NEWID
  proto$lesson_text <- "위반 주입용 합성 L-code (테스트 픽스처 전용)"
  co$lcodes <- c(co$lcodes, list(proto))
  co$n_lcodes <- length(co$lcodes)
  co$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+00:00")
  co
})
st_b <- fx_state(fx_b)
# ★조작 선행검증: 새 ID 가 corpus 에 실재하고 index 엔 없는지
if (st_b$n_corpus == real_state$n_corpus + 1L && NEWID %in% st_b$corpus_ids && !(NEWID %in% st_b$index_ids))
  ok("setup_B_mutation_took", sprintf("corpus %d → %d, %s 가 corpus 에만 존재",
                                      real_state$n_corpus, st_b$n_corpus, NEWID))
else
  bad("setup_B_mutation_took", sprintf("조작 미적용 — n_corpus=%s, id 존재=%s",
                                       st_b$n_corpus, NEWID %in% st_b$corpus_ids))

r <- fx_check(fx_b)
if (identical(r$status, "STALE") && NEWID %in% r$missing_sample)
  ok("inject_B_alarm", sprintf("status=STALE · %s (신규 적립분이 index 결측으로 지목됨)", r$reason))
else
  bad("inject_B_alarm", sprintf("신규 적립 낙후를 못 잡음 — status=%s reason=%s", r$status, r$reason))

# ── [위반 주입 C] 카운트는 같은데 멤버가 다름 → 경보 (카운트 단독의 사각) ───
cat("\n--- [위반 주입 C] 동수 다른멤버 (카운트-only 검사가 놓치는 축) ---\n")
SWAPID <- "L-TEST-SWAPPED-9999"
fx_c <- new_fixture("swapped", mutate_index = function(ix) {
  ix$lcode_corpus[[1]]$id <- SWAPID   # 개수 불변, 멤버만 교체
  ix
})
st_c <- fx_state(fx_c)
# ★조작 선행검증: 개수는 같고 ID 집합만 달라졌는지
if (identical(st_c$n_index, st_c$n_corpus) && SWAPID %in% st_c$index_ids)
  ok("setup_C_mutation_took", sprintf("개수 동일(%d=%d)인데 index 에 %s 삽입", st_c$n_index, st_c$n_corpus, SWAPID))
else
  bad("setup_C_mutation_took", sprintf("조작 미적용 — n=%s/%s, swap 존재=%s",
                                       st_c$n_index, st_c$n_corpus, SWAPID %in% st_c$index_ids))

r <- fx_check(fx_c)
if (identical(r$status, "STALE") && r$n_extra_in_index >= 1L && r$n_missing_in_index >= 1L)
  ok("inject_C_alarm_beats_count_only", sprintf("status=STALE · missing %d / extra %d (카운트만 봤으면 초록)",
                                                r$n_missing_in_index, r$n_extra_in_index))
else
  bad("inject_C_alarm_beats_count_only", sprintf("동수-다른멤버를 못 잡음 — status=%s reason=%s", r$status, r$reason))

# ── [위반 주입 D] counts 필드만 낙후 (행은 최신) → 경보 ─────────────────────
# 소비면(distill_stats.R / loop_integrator.R / weekly_distill.R)은 counts 필드를 그대로
# 읽어 보고한다 — 필드가 행과 어긋나면 보고 수치가 거짓이 된다.
cat("\n--- [위반 주입 D] index counts 필드 ↔ 실제 행수 불일치 ---\n")
fx_d <- new_fixture("counts_field_drift", mutate_index = function(ix) {
  ix$counts$lcode_corpus <- length(ix$lcode_corpus) - 7L
  ix
})
st_d <- fx_state(fx_d)
if (st_d$index_counts_field == st_d$n_index - 7L)
  ok("setup_D_mutation_took", sprintf("counts 필드 %d vs 실제 행 %d", st_d$index_counts_field, st_d$n_index))
else
  bad("setup_D_mutation_took", sprintf("조작 미적용 — counts=%s rows=%s", st_d$index_counts_field, st_d$n_index))

r <- fx_check(fx_d)
if (identical(r$status, "STALE") && grepl("index_counts_field_stale", r$reason))
  ok("inject_D_alarm", sprintf("status=STALE · %s", r$reason))
else
  bad("inject_D_alarm", sprintf("counts 필드 드리프트를 못 잡음 — status=%s reason=%s", r$status, r$reason))

# ── [대리 지표 대조] mtime 만 봤다면 무엇이 초록이었나 ──────────────────────
# ★이 축이 "왜 내용 기반이어야 하는가"의 실증이다.
cat("\n--- [대리 지표 대조] mtime 계기 vs 내용 계기 ---\n")
fx_p <- new_fixture("proxy_probe", mutate_corpus = function(co) {
  proto <- co$lcodes[[1]]; proto$l_code <- "L-TEST-PROXY-0002"
  co$lcodes <- c(co$lcodes, list(proto)); co$n_lcodes <- length(co$lcodes); co
})
cp <- file.path(fx_p, ".cache/lcode_corpus.json")
ip <- file.path(fx_p, "06_Registry/knowledge_index.json")
# index 를 corpus 보다 **나중에** 만진 것처럼 만든다 (내용은 낙후인 채로).
Sys.setFileTime(cp, Sys.time() - 3600)
Sys.setFileTime(ip, Sys.time())
proxy_green <- file.info(ip)$mtime > file.info(cp)$mtime      # 구식 mtime 계기의 판정
if (isTRUE(proxy_green))
  ok("setup_proxy_green", "mtime 대리 지표는 초록 (index 가 더 최신으로 보임)")
else
  bad("setup_proxy_green", "mtime 조작 미적용 — 대조의 전제가 성립 안 함")

r <- fx_check(fx_p)
if (isTRUE(proxy_green) && identical(r$status, "STALE"))
  ok("content_beats_mtime_proxy", sprintf("mtime=초록인데 내용 계기는 STALE (%s) — append 로 계기 끄기 불가", r$reason))
else
  bad("content_beats_mtime_proxy", sprintf("대리 지표와 같이 눈멀었음 — status=%s", r$status))

# ── [advisory 오탐 방지] 내용 일치 + corpus 타임스탬프만 최신 → OK 유지 ─────
cat("\n--- [오탐 방지] 내용 일치인데 corpus 타임스탬프만 최신 ---\n")
fx_adv <- new_fixture("ts_only", mutate_corpus = function(co) {
  co$last_updated <- format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%S+00:00"); co
})
r <- fx_check(fx_adv)
if (identical(r$status, "OK") && isTRUE(r$ts_advisory))
  ok("advisory_not_escalated", sprintf("status=OK 유지 + advisory 표기 (%s)", r$reason))
else if (identical(r$status, "OK"))
  ok("advisory_not_escalated", sprintf("status=OK 유지 (ts_advisory=%s)", r$ts_advisory))
else
  bad("advisory_not_escalated", sprintf("타임스탬프 단독으로 STALE 승격 = 오탐 — reason=%s", r$reason))

# ── [폴백] 입력 부재 / 파싱 실패 → 죽지 않고 명확한 사유 ────────────────────
cat("\n--- [폴백] 입력 부재·손상 ---\n")
fx_nc <- new_fixture("no_corpus", drop_corpus = TRUE)
r <- tryCatch(fx_check(fx_nc), error = function(e) e)
if (inherits(r, "error")) bad("fallback_corpus_missing", paste("stop() 으로 죽음:", conditionMessage(r)))
else if (identical(r$status, "SKIP") && grepl("corpus_missing", r$reason))
  ok("fallback_corpus_missing", sprintf("status=SKIP · %s", r$reason))
else bad("fallback_corpus_missing", sprintf("부재를 SKIP 으로 처리 안 함 — status=%s reason=%s", r$status, r$reason))

fx_ni <- new_fixture("no_index", drop_index = TRUE)
r <- tryCatch(fx_check(fx_ni), error = function(e) e)
if (inherits(r, "error")) bad("fallback_index_missing", paste("stop() 으로 죽음:", conditionMessage(r)))
else if (identical(r$status, "SKIP") && grepl("index_missing", r$reason))
  ok("fallback_index_missing", sprintf("status=SKIP · %s", r$reason))
else bad("fallback_index_missing", sprintf("부재를 SKIP 으로 처리 안 함 — status=%s reason=%s", r$status, r$reason))

fx_bad <- new_fixture("corrupt_index")
writeLines("{ this is not json", file.path(fx_bad, "06_Registry/knowledge_index.json"))
r <- tryCatch(fx_check(fx_bad), error = function(e) e)
if (inherits(r, "error")) bad("fallback_index_corrupt", paste("stop() 으로 죽음:", conditionMessage(r)))
else if (identical(r$status, "SKIP") && grepl("parse_error", r$reason))
  ok("fallback_index_corrupt", sprintf("status=SKIP · %s", substr(r$reason, 1, 60)))
else bad("fallback_index_corrupt", sprintf("손상 파일을 SKIP 으로 처리 안 함 — status=%s", r$status))

# 스키마 이탈(필드명 변경) — STALE 로 오보하지 않고 SKIP
fx_sch <- new_fixture("schema_drift", mutate_index = function(ix) {
  ix$lcode_corpus <- NULL; ix })
r <- tryCatch(fx_check(fx_sch), error = function(e) e)
if (inherits(r, "error")) bad("fallback_schema_drift", paste("stop() 으로 죽음:", conditionMessage(r)))
else if (identical(r$status, "SKIP") && grepl("no_lcode_corpus_field", r$reason))
  ok("fallback_schema_drift", sprintf("status=SKIP · %s", r$reason))
else bad("fallback_schema_drift", sprintf("스키마 이탈을 오보 — status=%s reason=%s", r$status, r$reason))

# ── [부작용 없음] 검사가 정본을 건드리지 않는지 ─────────────────────────────
cat("\n--- [부작용 없음] 검사기는 정본을 쓰지 않는다 ---\n")
before <- file.info(c(REAL_INDEX, file.path(PROJ, "06_Registry/knowledge_index.md")))$mtime
invisible(check_knowledge_index_freshness(root = PROJ))
after <- file.info(c(REAL_INDEX, file.path(PROJ, "06_Registry/knowledge_index.md")))$mtime
if (isTRUE(all(before == after)))
  ok("check_is_read_only", "정본 knowledge_index.{json,md} mtime 불변")
else
  bad("check_is_read_only", "검사가 정본을 재작성함 — 계기가 증거를 지운다")

# ── [repair opt-in] 명시 호출 시에만 재빌드 ─────────────────────────────────
cat("\n--- [repair] 명시 opt-in 재빌드 ---\n")
if (!is.function(get0("repair_knowledge_index")))
  bad("repair_exists", "repair_knowledge_index() 부재")
else {
  # 픽스처 루트를 빌더가 요구하는 최소 구조로 채운다 (정본에서 복사).
  fx_r <- new_fixture("repair", mutate_index = function(ix) {
    ix$lcode_corpus <- ix$lcode_corpus[seq_len(length(ix$lcode_corpus) - 5L)]
    ix$counts$lcode_corpus <- length(ix$lcode_corpus); ix })
  dir.create(file.path(fx_r, "qepm/memory/axioms/active"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fx_r, "qepm/memory/axioms/deprecated"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fx_r, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(PROJ, "qepm/memory/axioms/active"), pattern = "^AX-\\d+\\.json$", full.names = TRUE),
            file.path(fx_r, "qepm/memory/axioms/active"), overwrite = TRUE)
  file.copy(list.files(file.path(PROJ, "qepm/memory/axioms/deprecated"), pattern = "demoted.*\\.json$", full.names = TRUE),
            file.path(fx_r, "qepm/memory/axioms/deprecated"), overwrite = TRUE)
  file.copy(file.path(PROJ, "06_Registry/distilled_knowledge.json"),
            file.path(fx_r, "06_Registry/distilled_knowledge.json"), overwrite = TRUE)
  file.copy(file.path(PROJ, "02_Infrastructure/ops/build_knowledge_index.R"),
            file.path(fx_r, "02_Infrastructure/ops/build_knowledge_index.R"), overwrite = TRUE)

  pre <- fx_check(fx_r)
  if (identical(pre$status, "STALE"))
    ok("setup_repair_fixture_is_stale", sprintf("재빌드 전 STALE (%s)", pre$reason))
  else
    bad("setup_repair_fixture_is_stale", sprintf("픽스처가 STALE 이 아님 — status=%s", pre$status))

  res <- suppressMessages(repair_knowledge_index(root = fx_r, verbose = FALSE))
  post <- fx_check(fx_r)
  if (isTRUE(res$rebuilt) && identical(post$status, "OK"))
    ok("repair_restores_ok", sprintf("재빌드 후 corpus %d / index %d 일치", post$n_corpus, post$n_index))
  else
    bad("repair_restores_ok", sprintf("재빌드 실패 또는 미해소 — rebuilt=%s status=%s", res$rebuilt, post$status))
}

# ── 정리 ────────────────────────────────────────────────────────────────────
unlink(FXROOT, recursive = TRUE, force = TRUE)

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"knowledge_index_stale","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
