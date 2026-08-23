# test_knowledge_index_consumer_heal.R — knowledge_index 소비면 자가치유 **배선** 시험
#
# 대상 배선 (2026-08-24 신설):
#   ① 02_Infrastructure/memory/distill_stats.R :: qv_ledger_stats()  ← .qv_heal_knowledge_index()
#      = 이 저장소에서 knowledge_index 를 읽는 유일한 R 소비 함수. 저자가 지목한 소비면
#        weekly_distill.R / monthly_distill.R / loop_integrator.R (+ data/daily_refresh.sh)
#        이 **전부 이 함수를 지난다** — 그래서 이 진입점 1곳이 R 소비면 전부를 덮는다.
#   ② 02_Infrastructure/ops/handbook_facts_audit.sh (LCODE 집계 직전)
#      = python 으로 파일을 직접 읽어 ①을 우회하는 유일한 소비면 → 자기 배선을 따로 가진다.
#
# 왜 이 시험이 필요한가:
#   원 결함이 정확히 "계기는 있는데 **부르는 생산 호출자가 0**" 이었다
#   (check_knowledge_index_freshness 검출력 17/17 · repair_knowledge_index 동작 확인 —
#    그런데 유일한 호출자 memory_knowledge_health.R:928 은 경보만 내고 끝났다).
#   같은 계통을 또 만들지 않으려면 "붙였다" 가 아니라 "**도달한다**" 를 재야 한다
#   (WIRE-1 / test_label_gate_wiring.R 선례). 그래서 세 층으로 잰다:
#     ① 배선 존재  — production 원본이 자가치유를 *실제로 호출*하는가 (사본 아닌 원본 파싱)
#     ② 배선 검출력 — 그 호출부를 지운 사본에서 ①이 **실제로 실패**하는가 (돌연변이).
#                     이게 없으면 ①은 장식이다("경고 0" 보고 순간이 최고 위험 — 양방향 규약).
#     ③ 동작 실효  — 낙후 주입 시 소비값이 **복구된 수**로 나오는가 + fail-open 이 지켜지는가
#
# ★정본 보호: 모든 변형은 TEMP 사본에서만 한다. 06_Registry / .cache 정본은 읽기 전용이며,
#   마지막에 정본 mtime 불변을 명시 검증한다(2026-08-22 '검사가 정본을 변형' 실사고 규약).
#
# ★루트 분리: worktree 에서는 **코드가 worktree 에, .cache/ 는 main 에** 있다. 한 변수로
#   합치면 worktree 에서 고친 배선을 두고 main 의 구판을 검사한다 — 옳은 것을 재지만
#   잘못된 지점을 잰다(test_label_gate_wiring.R 와 같은 규약).
#
# 실행: Rscript 08_Tests/hooks/test_knowledge_index_consumer_heal.R

suppressWarnings(suppressMessages(library(jsonlite)))

# ── 루트 해석 ────────────────────────────────────────────────────────────────
# CODE_ROOT = self-first (금칙 ④-b: 테스트 러너는 자기 위치를 먼저 믿는다).
#   이 파일은 08_Tests/hooks/ 에 있으므로 ../.. 가 코드 루트다.
.self_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grepl("^--file=", ca)])
  if (length(f) == 1L) dirname(normalizePath(f, winslash = "/", mustWork = FALSE)) else ""
}
.pick <- function(cands, probe) {
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, probe))]
  if (length(hit)) normalizePath(hit[1], winslash = "/", mustWork = FALSE) else ""
}
.sd <- .self_dir()
CODE_ROOT <- .pick(c(if (nzchar(.sd)) file.path(.sd, "..", "..") else "",
                     getwd(), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", "")),
                   "02_Infrastructure/memory/distill_stats.R")
# DATA_ROOT = 픽스처 원본(.cache/lcode_corpus.json)이 있는 곳. worktree 엔 없다(untracked).
DATA_ROOT <- .pick(c(Sys.getenv("QM_ROOT", ""), getwd(), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
                     "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                   ".cache/lcode_corpus.json")
if (!nzchar(CODE_ROOT)) stop("[heal-wiring] 코드 루트를 찾지 못함 — distill_stats.R 부재")
if (!nzchar(DATA_ROOT)) stop("[heal-wiring] 데이터 루트를 찾지 못함 — .cache/lcode_corpus.json 부재")
cat(sprintf("[root] CODE=%s\n[root] DATA=%s\n\n", CODE_ROOT, DATA_ROOT))

# ★정본 mtime 기준선 — 스크립트가 시작하기 전에 찍는다. 끝에서 이 값과 대조해
#   "테스트가 정본을 건드리지 않았다" 를 **실측으로** 단언한다(선언이 아니라).
REAL_FILES <- file.path(DATA_ROOT, c("06_Registry/knowledge_index.json",
                                     "06_Registry/knowledge_index.md",
                                     ".cache/lcode_corpus.json"))
BASE_MT <- file.info(REAL_FILES)$mtime

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

rd <- function(root, rel) {
  f <- file.path(root, rel)
  if (!file.exists(f)) return(character(0))
  readLines(f, warn = FALSE)
}
# ★부분문자열 포함만 쓴다 — 한글 혼재 blob 에서 정규식 단어경계는 조용히 FALSE 가 된다
#   (2026-08-08 실측: 같은 blob 에서 fixed 25건 vs 경계 0건). 0 을 결론으로 쓰지 않기 위함.
has  <- function(src, pat) any(grepl(pat, src, fixed = TRUE))
lineno <- function(src, pat) { h <- which(grepl(pat, src, fixed = TRUE)); if (length(h)) h[1] else NA_integer_ }

# ═══ ① 배선 존재 (production 원본 파싱) ══════════════════════════════════════
cat("=== (1) 배선 존재 — production 원본 ===\n")

DS <- rd(CODE_ROOT, "02_Infrastructure/memory/distill_stats.R")
HB <- rd(CODE_ROOT, "02_Infrastructure/ops/handbook_facts_audit.sh")

# 배선 판정자 — ②의 돌연변이도 같은 판정자를 쓴다(판정자가 다르면 ②는 ①을 검증하지 못한다).
wired_ds <- function(src) {
  has(src, ".qv_heal_knowledge_index <- function") &&
    has(src, "if (isTRUE(auto_repair)) .qv_heal_knowledge_index(root)") &&
    has(src, "check_knowledge_index_freshness(root = root)") &&
    has(src, "repair_knowledge_index(root = root, verbose = FALSE)")
}
wired_hb <- function(src) {
  has(src, "knowledge_index_freshness.R") && has(src, "--repair")
}

if (wired_ds(DS)) ok("wire_distill_stats", "qv_ledger_stats() 가 소비 전 자가치유를 호출") else
  bad("wire_distill_stats", "distill_stats.R 에 자가치유 호출부 없음")
if (wired_hb(HB)) ok("wire_handbook_audit", "handbook_facts_audit.sh 가 검사기 --repair 를 호출") else
  bad("wire_handbook_audit", "handbook_facts_audit.sh 에 --repair 호출 없음")

# ★순서 계약: 자가치유는 **소비 직전**이어야 한다. 소비 뒤에 있으면 그 실행에선 낡은 값을 읽는다.
i_heal <- lineno(DS, "if (isTRUE(auto_repair)) .qv_heal_knowledge_index(root)")
i_read <- lineno(DS, "j <- fromJSON(p, simplifyVector = FALSE)")
if (!is.na(i_heal) && !is.na(i_read) && i_heal < i_read)
  ok("order_distill_stats", sprintf("치유 L%d < 소비 L%d", i_heal, i_read)) else
  bad("order_distill_stats", sprintf("치유가 소비 이후이거나 부재 (heal=%s read=%s)", i_heal, i_read))

i_hb_heal <- lineno(HB, "Rscript \"$KIF_R\" --repair")
i_hb_read <- lineno(HB, "d.get('lcode_corpus',0)")
if (!is.na(i_hb_heal) && !is.na(i_hb_read) && i_hb_heal < i_hb_read)
  ok("order_handbook_audit", sprintf("치유 L%d < 소비 L%d", i_hb_heal, i_hb_read)) else
  bad("order_handbook_audit", sprintf("치유가 소비 이후이거나 부재 (heal=%s read=%s)", i_hb_heal, i_hb_read))

# ★fail-open 계약 — 배선이 증류를 막으면 안 된다. 두 배선 모두 실패를 흡수하는지 정적 확인.
if (has(DS, "}, error = function(e) {") && has(DS, "기존 인덱스로 진행"))
  ok("failopen_distill_stats", "복구 실패를 tryCatch 로 흡수 + 경보 후 진행") else
  bad("failopen_distill_stats", "자가치유 실패가 소비를 죽일 수 있음")
if (has(HB, "[facts][경고] knowledge_index"))
  ok("failopen_handbook_audit", "rc != 0 을 경보만 하고 기존 수치로 진행") else
  bad("failopen_handbook_audit", "handbook 배선에 fail-open 경보 없음")

# ★재시도 루프 금지 — 정적 확인(동작 확인은 ③-F).
.heal_blk <- local({
  a <- lineno(DS, ".qv_heal_knowledge_index <- function")
  b <- lineno(DS, "qv_ledger_stats <- function")
  if (is.na(a) || is.na(b) || b <= a) character(0) else DS[a:(b - 1L)]
})
if (length(.heal_blk) && !has(.heal_blk, "while") && !has(.heal_blk, "repeat") &&
    length(grep("repair_knowledge_index(", .heal_blk, fixed = TRUE)) == 1L)
  ok("no_retry_loop_static", sprintf("치유 블록 %d줄에 루프 0 · repair 호출 1회", length(.heal_blk))) else
  bad("no_retry_loop_static", "치유 블록에 루프가 있거나 repair 호출이 1회가 아님")

# ── 저자 지목 소비면 5곳이 배선된 진입점에 **도달**하는가 ────────────────────
# ★"각 소비면에 호출을 하나씩 박았는가" 가 아니라 "각 소비면이 치유를 통과하는가" 를 잰다.
#   전자는 같은 실행에서 검사를 N회 돌릴 뿐 도달 범위가 같고, hypothesis_index 선례
#   (자가치유는 consumer 함수 lookup_hypothesis 1곳, 호출자들은 그것을 상속)와도 어긋난다.
cat("\n--- 저자 지목 소비면 5곳의 도달 ---\n")
SURFACES <- list(
  list(key = "weekly_distill",   file = "02_Infrastructure/memory/weekly_distill.R",   via = "qv_ledger_stats("),
  list(key = "monthly_distill",  file = "02_Infrastructure/memory/monthly_distill.R",  via = "qv_ledger_stats("),
  list(key = "distill_stats",    file = "02_Infrastructure/memory/distill_stats.R",    via = ".qv_heal_knowledge_index(root)"),
  list(key = "loop_integrator",  file = "02_Infrastructure/memory/loop_integrator.R",  via = "qv_ledger_stats("),
  list(key = "handbook_facts_audit", file = "02_Infrastructure/ops/handbook_facts_audit.sh", via = "--repair")
)
for (s in SURFACES) {
  src <- rd(CODE_ROOT, s$file)
  if (!length(src)) { bad(paste0("reach_", s$key), sprintf("파일 부재: %s", s$file)); next }
  if (has(src, s$via)) ok(paste0("reach_", s$key), sprintf("%s → '%s'", basename(s$file), s$via)) else
    bad(paste0("reach_", s$key), sprintf("치유 진입점에 도달하지 않음 (%s 에 '%s' 없음)", s$file, s$via))
}

# ★소비면 밖 우회 감시 — knowledge_index.json 을 직접 읽는 **다른** 생산 경로가 생기면
#   그 경로는 치유를 우회한다. 알려진 소비면 목록을 고정하고 신규 출현을 잡는다.
cat("\n--- 우회 경로 감시 (knowledge_index.json 직접 read) ---\n")
# ★"세기 전에 범위를 선언한다" — 2026-08-24 실측 6곳을 역할과 함께 고정한다.
#   신규 파일이 인덱스를 직접 읽기 시작하면 여기 없으므로 FAIL 로 뜬다.
#   ⚠경보면(memory_knowledge_health.R · alerts_digest_build.sh)은 **일부러 배선하지 않는다** —
#     낙후 상태 자체를 재는 것이 그들의 일이라, 치유하면 자기가 신고할 증거를 지운다.
#     alerts_digest_build.sh:61-63 에 저자의 같은 판단이 이미 적혀 있다("--repair 를 부르지 않는다").
KNOWN <- c(
  "02_Infrastructure/memory/distill_stats.R",           # 소비 — 배선됨 (R 소비면 전체의 진입점)
  "02_Infrastructure/ops/handbook_facts_audit.sh",      # 소비 — 배선됨 (python 우회 경로)
  "02_Infrastructure/memory/loop_integrator.R",         # 소비 — qv_ledger_stats 경유(라벨 문자열만 보유)
  "02_Infrastructure/ops/build_knowledge_index.R",      # 생산자(쓰기)
  "02_Infrastructure/ops/knowledge_index_freshness.R",  # 계기
  "02_Infrastructure/ops/alerts_digest_build.sh")       # 경보면 — 치유 금지(의도적)
cand <- list.files(file.path(CODE_ROOT, "02_Infrastructure"),
                   pattern = "[.](R|sh|py)$", recursive = TRUE, full.names = TRUE)
cand <- cand[!grepl("_archive", cand, fixed = TRUE)]
hits <- character(0)
for (f in cand) {
  src <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
  if (has(src, "06_Registry/knowledge_index.json") || has(src, "\"knowledge_index.json\"")) {
    hits <- c(hits, sub(paste0(CODE_ROOT, "/"), "", f, fixed = TRUE))
  }
}
unknown <- setdiff(hits, KNOWN)
if (!length(unknown))
  ok("no_unwired_bypass", sprintf("직접 참조 %d곳 전부 선언된 역할 (소비 2 · 경유 1 · 생산 1 · 계기 1 · 경보 1)", length(hits))) else
  bad("no_unwired_bypass", sprintf("역할 미선언 신규 직접 참조 %d곳 — 치유 우회 가능: %s",
                                   length(unknown), paste(unknown, collapse = ", ")))

# ═══ ② 배선 검출력 (돌연변이 — 호출부를 지우면 ①이 실제로 실패하는가) ═══════
cat("\n=== (2) 배선 검출력 — 돌연변이 주입 ===\n")
TMPBASE <- Sys.getenv("TEMP", unset = Sys.getenv("TMP", unset = tempdir()))
MUT <- file.path(TMPBASE, sprintf("kihw_mut_%s_%s", Sys.getpid(), format(Sys.time(), "%H%M%S")))
dir.create(MUT, recursive = TRUE, showWarnings = FALSE)

ds_mut <- DS[!grepl("if (isTRUE(auto_repair)) .qv_heal_knowledge_index(root)", DS, fixed = TRUE)]
if (length(ds_mut) == length(DS) - 1L)
  ok("setup_mutation_ds", "distill_stats 호출부 1줄 제거 성공") else
  bad("setup_mutation_ds", sprintf("제거 실패 — %d → %d 줄", length(DS), length(ds_mut)))
if (!wired_ds(ds_mut))
  ok("mutation_kills_ds_detector", "호출부 제거 시 배선 판정자가 FAIL 로 뒤집힘 (①은 장식이 아니다)") else
  bad("mutation_kills_ds_detector", "호출부를 지웠는데도 배선 판정이 통과 = 판정자가 눈멀었음")

hb_mut <- HB[!grepl("--repair", HB, fixed = TRUE)]
if (length(hb_mut) < length(HB))
  ok("setup_mutation_hb", sprintf("handbook 호출부 %d줄 제거", length(HB) - length(hb_mut))) else
  bad("setup_mutation_hb", "제거 실패")
if (!wired_hb(hb_mut))
  ok("mutation_kills_hb_detector", "--repair 제거 시 배선 판정자가 FAIL 로 뒤집힘") else
  bad("mutation_kills_hb_detector", "제거했는데도 통과 = 판정자가 눈멀었음")

# ═══ ③ 동작 실효 (샌드박스 — 정본 미사용) ════════════════════════════════════
cat("\n=== (3) 동작 실효 — 낙후 주입 샌드박스 ===\n")
REAL_CORPUS <- file.path(DATA_ROOT, ".cache/lcode_corpus.json")
REAL_INDEX  <- file.path(DATA_ROOT, "06_Registry/knowledge_index.json")

# 자족 샌드박스: 치유가 root 아래에서 검사기·빌더를 찾으므로 코드도 함께 심는다
#   (memory_knowledge_health.R:928 과 같은 root-상대 해석). 코드는 CODE_ROOT 판본을 쓴다.
new_sandbox <- function(name, mutate_index = identity, mutate_corpus = identity,
                        builder_from = NULL, drop_builder = FALSE) {
  d <- file.path(MUT, name)
  for (sub in c(".cache", "06_Registry", "02_Infrastructure/ops",
                "qepm/memory/axioms/active", "qepm/memory/axioms/deprecated"))
    dir.create(file.path(d, sub), recursive = TRUE, showWarnings = FALSE)
  co <- mutate_corpus(fromJSON(REAL_CORPUS, simplifyVector = FALSE))
  write_json(co, file.path(d, ".cache/lcode_corpus.json"), auto_unbox = TRUE, null = "null")
  ix <- mutate_index(fromJSON(REAL_INDEX, simplifyVector = FALSE))
  write_json(ix, file.path(d, "06_Registry/knowledge_index.json"), auto_unbox = TRUE, null = "null")
  file.copy(file.path(DATA_ROOT, "06_Registry/distilled_knowledge.json"),
            file.path(d, "06_Registry/distilled_knowledge.json"), overwrite = TRUE)
  file.copy(list.files(file.path(DATA_ROOT, "qepm/memory/axioms/active"),
                       pattern = "^AX-\\d+\\.json$", full.names = TRUE),
            file.path(d, "qepm/memory/axioms/active"), overwrite = TRUE)
  file.copy(list.files(file.path(DATA_ROOT, "qepm/memory/axioms/deprecated"),
                       pattern = "demoted.*\\.json$", full.names = TRUE),
            file.path(d, "qepm/memory/axioms/deprecated"), overwrite = TRUE)
  file.copy(file.path(CODE_ROOT, "02_Infrastructure/ops/knowledge_index_freshness.R"),
            file.path(d, "02_Infrastructure/ops/knowledge_index_freshness.R"), overwrite = TRUE)
  if (!drop_builder) {
    if (is.null(builder_from))
      file.copy(file.path(CODE_ROOT, "02_Infrastructure/ops/build_knowledge_index.R"),
                file.path(d, "02_Infrastructure/ops/build_knowledge_index.R"), overwrite = TRUE)
    else writeLines(builder_from, file.path(d, "02_Infrastructure/ops/build_knowledge_index.R"))
  }
  d
}
sb_rows <- function(d) length(fromJSON(file.path(d, "06_Registry/knowledge_index.json"),
                                       simplifyVector = FALSE)$lcode_corpus)
sb_ids  <- function(d) vapply(fromJSON(file.path(d, "06_Registry/knowledge_index.json"),
                                       simplifyVector = FALSE)$lcode_corpus,
                              function(e) as.character(e$id)[1], character(1))
drop_n <- function(n) function(ix) {
  ix$lcode_corpus <- ix$lcode_corpus[seq_len(length(ix$lcode_corpus) - n)]
  ix$counts$lcode_corpus <- length(ix$lcode_corpus); ix }

# production 함수를 CODE_ROOT 판본으로 적재 (구판 상속 금지 — 코드 루트 우선)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
source(file.path(CODE_ROOT, "02_Infrastructure/memory/distill_stats.R"), local = FALSE)
if (is.function(get0("qv_ledger_stats")) && is.function(get0(".qv_heal_knowledge_index")))
  ok("functions_loaded", "qv_ledger_stats + .qv_heal_knowledge_index 적재") else
  bad("functions_loaded", "함수 적재 실패")

n_real <- length(fromJSON(REAL_CORPUS, simplifyVector = FALSE)$lcodes)
cat(sprintf("  (정본 실측 corpus %d — 기준선 인용용, 판정에 미사용)\n", n_real))

# ── [정상] 신선한 인덱스 → 재빌드 없음 + 값 그대로 ──────────────────────────
cat("\n--- [정상] 신선한 인덱스 ---\n")
sb_ok <- new_sandbox("fresh")
pre_mt <- file.info(file.path(sb_ok, "06_Registry/knowledge_index.json"))$mtime
if (identical(sb_rows(sb_ok), n_real))
  ok("setup_fresh_is_matched", sprintf("사본 index %d = corpus %d", sb_rows(sb_ok), n_real)) else
  bad("setup_fresh_is_matched", sprintf("사본이 일치 상태가 아님 (index=%d corpus=%d)", sb_rows(sb_ok), n_real))
st <- suppressMessages(qv_ledger_stats(root = sb_ok))
post_mt <- file.info(file.path(sb_ok, "06_Registry/knowledge_index.json"))$mtime
if (identical(as.integer(st$lcode), as.integer(n_real)) && isTRUE(pre_mt == post_mt))
  ok("fresh_no_rebuild", sprintf("lcode=%d · 인덱스 mtime 불변 (불필요한 재작성 없음)", st$lcode)) else
  bad("fresh_no_rebuild", sprintf("lcode=%s · mtime 변화=%s (신선한데 재빌드했거나 값이 틀림)",
                                  st$lcode, !isTRUE(pre_mt == post_mt)))

# ── [위반 A] 행 삭제 낙후 → 소비값이 복구된 수 ──────────────────────────────
cat("\n--- [위반 주입 A] index 낙후 (행 5개 삭제 + counts 동반 하향) ---\n")
sb_a <- new_sandbox("stale_rows", mutate_index = drop_n(5L))
if (identical(sb_rows(sb_a), n_real - 5L))
  ok("setup_A_mutation_took", sprintf("index %d → %d (자기일관 낙후)", n_real, sb_rows(sb_a))) else
  bad("setup_A_mutation_took", sprintf("조작 미적용 — index=%d (기대 %d)", sb_rows(sb_a), n_real - 5L))
st_a <- suppressMessages(qv_ledger_stats(root = sb_a))
if (identical(as.integer(st_a$lcode), as.integer(n_real)) && identical(sb_rows(sb_a), n_real))
  ok("A_heals_before_consume", sprintf("소비값 %d = 복구된 수 (낙후값 %d 아님)", st_a$lcode, n_real - 5L)) else
  bad("A_heals_before_consume", sprintf("낙후값을 그대로 소비 — lcode=%s · index rows=%d", st_a$lcode, sb_rows(sb_a)))

# ── [대조] auto_repair=FALSE → 낙후값 그대로 (치유가 원인임을 확정) ─────────
# ★이 대조가 없으면 A 의 복구를 다른 무엇(재복사·부수효과)에 오귀속할 수 있다.
cat("\n--- [대조] auto_repair=FALSE 는 치유하지 않는다 ---\n")
sb_off <- new_sandbox("stale_no_repair", mutate_index = drop_n(5L))
st_off <- suppressMessages(qv_ledger_stats(root = sb_off, auto_repair = FALSE))
if (identical(as.integer(st_off$lcode), as.integer(n_real - 5L)) && identical(sb_rows(sb_off), n_real - 5L))
  ok("control_off_stays_stale", sprintf("lcode=%d (낙후 유지) — A 의 복구는 자가치유의 효과", st_off$lcode)) else
  bad("control_off_stays_stale", sprintf("auto_repair=FALSE 인데 값이 변함 — lcode=%s rows=%d", st_off$lcode, sb_rows(sb_off)))

# ── [위반 B] corpus 신규 적립 → 그 ID 가 인덱스에 실제로 들어오는가 ─────────
cat("\n--- [위반 주입 B] corpus 신규 L-code (index 미반영) ---\n")
NEWID <- "L-TEST-HEAL-0001"
sb_b <- new_sandbox("new_lcode", mutate_corpus = function(co) {
  proto <- co$lcodes[[1]]; proto$l_code <- NEWID
  proto$lesson_text <- "배선 시험용 합성 L-code (픽스처 전용)"
  co$lcodes <- c(co$lcodes, list(proto)); co$n_lcodes <- length(co$lcodes); co })
if (!(NEWID %in% sb_ids(sb_b)))
  ok("setup_B_mutation_took", sprintf("%s 가 corpus 에만 존재 (index 결측)", NEWID)) else
  bad("setup_B_mutation_took", "조작 미적용 — 신규 ID 가 이미 index 에 있음")
st_b <- suppressMessages(qv_ledger_stats(root = sb_b))
if (NEWID %in% sb_ids(sb_b) && identical(as.integer(st_b$lcode), as.integer(n_real + 1L)))
  ok("B_new_lcode_reaches_index", sprintf("신규 %s 가 인덱스에 등재 · lcode=%d", NEWID, st_b$lcode)) else
  bad("B_new_lcode_reaches_index", sprintf("신규 적립분이 소비면에 도달 안 함 — lcode=%s", st_b$lcode))

# ── [fail-open C] 빌더 부재 → 죽지 않고 낙후값으로 진행 ─────────────────────
cat("\n--- [fail-open C] 빌더 부재 ---\n")
sb_c <- new_sandbox("no_builder", mutate_index = drop_n(5L), drop_builder = TRUE)
st_c <- tryCatch(suppressMessages(qv_ledger_stats(root = sb_c)), error = function(e) e)
if (inherits(st_c, "error")) bad("failopen_no_builder", paste("소비가 죽음:", conditionMessage(st_c))) else
  if (identical(as.integer(st_c$lcode), as.integer(n_real - 5L)))
    ok("failopen_no_builder", sprintf("stop() 없이 낙후값 %d 로 진행 (증류가 멈추지 않는다)", st_c$lcode)) else
    bad("failopen_no_builder", sprintf("예상 밖 반환 — lcode=%s", st_c$lcode))

# ── [fail-open D] corpus 손상(SKIP) → 복구 안 함 + 죽지 않음 ────────────────
cat("\n--- [fail-open D] corpus 손상 → SKIP (복구 금지 · 증거 보존) ---\n")
sb_d <- new_sandbox("corrupt_corpus", mutate_index = drop_n(5L))
writeLines("{ this is not json", file.path(sb_d, ".cache/lcode_corpus.json"))
st_d <- tryCatch(suppressMessages(qv_ledger_stats(root = sb_d)), error = function(e) e)
if (inherits(st_d, "error")) bad("failopen_corrupt_corpus", paste("소비가 죽음:", conditionMessage(st_d))) else
  if (identical(sb_rows(sb_d), n_real - 5L) && identical(as.integer(st_d$lcode), as.integer(n_real - 5L)))
    ok("failopen_corrupt_corpus", "SKIP 은 재빌드하지 않는다 — 손상 원천으로 인덱스를 덮어쓰지 않음") else
    bad("failopen_corrupt_corpus", sprintf("SKIP 인데 인덱스를 건드림 — rows=%d lcode=%s", sb_rows(sb_d), st_d$lcode))

# ── [F] 재시도 루프 금지 — 복구 불능 상황에서 빌더 호출 횟수 == 1 ───────────
# ★계수기 빌더: 호출될 때마다 파일에 한 줄 적고 인덱스는 **고치지 않는다**.
#   복구가 실패해도 루프를 돌지 않는지(= 1회 시도 후 진행) 를 직접 센다.
cat("\n--- [F] 재시도 루프 금지 (복구 불능 상황) ---\n")
CNT <- file.path(MUT, "builder_calls.txt")
stub <- c(
  "build_knowledge_index <- function(root = NULL, verbose = TRUE) {",
  sprintf("  cat('call\\n', file = %s, append = TRUE)", encodeString(CNT, quote = '"')),
  "  invisible(NULL)   # 일부러 인덱스를 고치지 않는다 = 복구 불능",
  "}",
  "if (!isTRUE(getOption('ki_no_autorun', FALSE))) build_knowledge_index()")
sb_f <- new_sandbox("no_retry", mutate_index = drop_n(5L), builder_from = stub)
if (file.exists(CNT)) unlink(CNT)
st_f <- tryCatch(suppressMessages(qv_ledger_stats(root = sb_f)), error = function(e) e)
n_calls <- if (file.exists(CNT)) length(readLines(CNT, warn = FALSE)) else 0L
if (inherits(st_f, "error")) bad("no_retry_loop_runtime", paste("소비가 죽음:", conditionMessage(st_f))) else
  if (identical(n_calls, 1L) && identical(as.integer(st_f$lcode), as.integer(n_real - 5L)))
    ok("no_retry_loop_runtime", sprintf("빌더 호출 %d회 후 낙후값 %d 로 진행", n_calls, st_f$lcode)) else
    bad("no_retry_loop_runtime", sprintf("빌더 %d회 호출(기대 1) · lcode=%s", n_calls, st_f$lcode))

# ── [G] handbook 배선이 쏘는 실제 명령이 복구하는가 ─────────────────────────
# ★handbook_facts_audit.sh 전체 실행은 git·parquet·python 전 계층을 훑으므로 여기서 돌리지
#   않는다. 대신 그 스크립트가 **실제로 발행하는 명령**(검사기 CLI --repair, 루트는
#   CLAUDE_PROJECT_DIR 로 전달)을 샌드박스에 그대로 쏴서 복구 여부를 잰다.
#   QM_ROOT 도 샌드박스로 고정한다 — 루트 해석이 어긋나도 **생산 정본에 절대 닿지 않게**.
cat("\n--- [G] handbook 배선이 발행하는 CLI 가 실제로 복구하는가 ---\n")
sb_g <- new_sandbox("handbook_cli", mutate_index = drop_n(5L))
rs <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
kif_g <- file.path(sb_g, "02_Infrastructure/ops/knowledge_index_freshness.R")
# ★system2(env=) 는 **Windows 에서 지원되지 않는다** — 조용히 무시되고 자식이 부모 환경을
#   그대로 상속한다. 그러면 이 검사는 샌드박스가 아니라 QM_ROOT(=생산 정본)에 --repair 를
#   쏜다. 검사가 정본을 만지는 그 사고 계통 자체다. Sys.setenv + on-exit 복원으로 바꾼다.
.old_env <- c(CLAUDE_PROJECT_DIR = Sys.getenv("CLAUDE_PROJECT_DIR", ""),
              QM_ROOT            = Sys.getenv("QM_ROOT", ""))
g_pre    <- sb_rows(sb_g)                      # 샌드박스 낙후 상태
prod_pre <- file.info(REAL_INDEX)$mtime        # 생산 정본 지문
Sys.setenv(CLAUDE_PROJECT_DIR = sb_g, QM_ROOT = sb_g)   # QM_ROOT 도 고정 = 폴백까지 봉쇄
rc <- tryCatch(suppressWarnings(system2(rs, c(shQuote(kif_g), "--repair"),
                                        stdout = TRUE, stderr = TRUE)),
               error = function(e) paste("system2 error:", conditionMessage(e)))
do.call(Sys.setenv, as.list(.old_env))
prod_post <- file.info(REAL_INDEX)$mtime
# ★조작 선행검증 = "자식이 **어느 루트**를 만졌나". 빌더 출력에는 경로가 없으므로(위 실측)
#   출력 문자열로 판별하지 않는다 — 샌드박스가 낙후였고 생산 정본이 불변인지로 판별한다.
#   이 검증이 없으면 "복구됐다"를 생산 루트 복구에 오귀속할 수 있다(무효 실험).
if (identical(g_pre, n_real - 5L) && isTRUE(prod_pre == prod_post))
  ok("setup_G_child_scoped_to_sandbox",
     sprintf("호출 전 샌드박스 %d(낙후) · 생산 정본 mtime 불변 = 자식이 샌드박스만 만짐", g_pre)) else
  bad("setup_G_child_scoped_to_sandbox",
      sprintf("무효 실험 — 샌드박스 pre=%s(기대 %d) · 생산 mtime 변화=%s",
              g_pre, n_real - 5L, !isTRUE(prod_pre == prod_post)))
if (identical(sb_rows(sb_g), n_real))
  ok("handbook_cli_repairs", sprintf("CLI 실행 후 index %d 복구 (LCODE 집계가 최신 수를 센다)", sb_rows(sb_g))) else
  bad("handbook_cli_repairs", sprintf("CLI 가 복구하지 못함 — rows=%d · 출력: %s",
                                      sb_rows(sb_g), paste(utils::head(rc, 4), collapse = " | ")))

# ═══ 정본 불변 ═══════════════════════════════════════════════
cat("
=== 정본 불변 ===
")
END_MT <- file.info(REAL_FILES)$mtime
same <- mapply(function(a, b) (is.na(a) && is.na(b)) || isTRUE(a == b), BASE_MT, END_MT)
if (all(same))
  ok("real_registry_untouched",
     sprintf("정본 %d개 mtime 불변 — 모든 변형은 사본에서만 (%s)", length(REAL_FILES), basename(MUT))) else
  bad("real_registry_untouched",
      sprintf("정본이 변형됨: %s", paste(basename(REAL_FILES)[!same], collapse = ", ")))

unlink(MUT, recursive = TRUE, force = TRUE)
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"knowledge_index_consumer_heal","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
