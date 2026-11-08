## repin_p2r05.R — P2R05 사전등록의 '환경 고정값'만 새 판으로 다시 고정(결과 전 · 도훈 11-08 "지금 전부 · P2R05 다시 고정") · 2026-11-08
##
## 왜: R 4.5.2 → 4.6.2 · Python 3.12.10 → 3.15.2 · torch 2.12.1+cu126 → 2.15.0+cu132 등 환경 최신화로 사전등록 핀(판 · DT 시험 증거 md5 ·
##     평가 경로 md5)이 현재와 달라 precheck 가 '판 불일치'로 막는다. 설계(칸 · 규칙 · 상수 · 최종 후보 선택 규칙 · 운영 경로 50 · 카탈로그)는 그대로다.
## 값은 등록 때와 **같은 함수**로 만든다(손으로 적지 않는다):
##   operational_pins.r_version = R.version.string · operational_pins.packages = packageVersion(같은 이름들)      (register.R .ops_pins 와 같은 정의)
##   engines.python  = P2R05_DTC$python_versions(ROOT)                                                         (register.R PYV)
##   tests_dt.files  = P2R05_DTC$test_evidence_check(ROOT)$record                                              (register.R TEV$record · 새 환경 run_all_tests.R 8/8)
##   reseed.rng_facts = path · md5 · fields(같은 필드 목록) · cuda(옛 문장 그대로)                              (register.R 864행과 같은 정의)
##   evaluation.files = 같은 경로 목록의 md5 다시 계산                                                          (register.R .eval_pins)
## 바꾸지 않는 것(역사 기록 — 그때의 파일을 가리킨다): rehearsal · evaluate_consistency · philosophy_p1 · draft_md5 · registered_at ·
##   reviewed_drafts · git_head_at_register · cells · rules · final_selection_rule · operational_pins.files/catalog/factor_registry.
## 덧붙이는 것: repins[] (시각 · 승인 · 사유 · 옛 md5 · 바뀐 칸 · 리허설 미재실행 사유 · 옛 증거 보관 위치).
## 안전: ① 두 사본 md5 같음 ② 바꾸지 않은 채 다시 직렬화 = 바이트 동일(아니면 중단 — 서식이 바뀌면 안 된다) ③ 바뀐 칸 = 허용 목록 안 ④ 새 값 = 현재 실측.
## 실행: Rscript repin_p2r05.R            계획만(쓰기 0)
##       Rscript repin_p2r05.R --apply    두 사본 쓰기 → 등록부 pr_record_round(supersedes md5 = 옛 md5 · 사유)
##   (11-08 밤 추가) --entry=<json>          repins[] 서술 칸(approved · reason · 그 밖의 설명 칸)을 파일에서 읽는다 — 없으면 11-08 첫 재핀 문구 그대로
##                   --expect-changed=<a,b>  바뀐 잎 경로 집합이 정확히 이것이 아니면 중단(두 번째 재핀 = PerformanceAnalytics 1칸)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
ARGS <- commandArgs(trailingOnly = TRUE)
APPLY <- "--apply" %in% ARGS
ENTRY <- sub("^--entry=", "", grep("^--entry=", ARGS, value = TRUE))
EXPECT <- unlist(strsplit(sub("^--expect-changed=", "", grep("^--expect-changed=", ARGS, value = TRUE)), ","))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R05_distribution_target")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json")
PRC <- file.path(RD, "prereg.json")
md5 <- function(f) unname(as.character(tools::md5sum(f)))
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
ser <- function(x) toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)   # register.R 와 같은 직렬화
wr <- function(x, f) writeLines(ser(x), f, useBytes = TRUE)
cj <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))

if (!identical(md5(PR), md5(PRC))) stop("[repin] 사전등록 두 사본 md5 불일치 — 중단")
OLD <- md5(PR)
pre <- fromJSON(PR, simplifyVector = FALSE)
if (!identical(pre$status, "registered")) stop("[repin] status ≠ registered — 결과 뒤에는 바꿀 수 없다(R2)")
## 등록 때 R 문자 벡터였던 칸(한 줄 배열로 직렬화) — 다시 읽으면 리스트(여러 줄)가 된다 → 원래 형태로 되돌려야 바이트가 같다(실측 차이 = 이 한 칸뿐)
if (is.list(pre$philosophy_p1$statuses)) pre$philosophy_p1$statuses <- vapply(pre$philosophy_p1$statuses, as.character, "")
tf <- tempfile(fileext = ".json"); wr(pre, tf)
if (!identical(md5(tf), OLD)) stop("[repin] 바꾸지 않은 다시 직렬화가 바이트 동일이 아니다(", md5(tf), " ≠ ", OLD, ") — 서식 보존 불가 · 중단")
cat(sprintf("[repin] 옛 사전등록 md5 %s · 다시 직렬화 바이트 동일 ✓\n", OLD))

source(file.path(RD, "engine_checks.R")); DTC <- P2R05_DTC
new <- pre
op <- pre$operational_pins
new$operational_pins$r_version <- R.version.string
new$operational_pins$packages <- setNames(lapply(names(op$packages), function(p) as.character(utils::packageVersion(p))), names(op$packages))
PYV <- DTC$python_versions(ROOT)
if (!isTRUE(PYV$ok)) stop("[repin] 파이썬 판 조회 실패: ", PYV$why %||% "?")
new$engines$python <- PYV
TEV <- DTC$test_evidence_check(ROOT)
if (!isTRUE(TEV$ok)) stop("[repin] DT 시험 증거 미통과 — 다시 고정하지 않는다:\n  · ", paste(c(TEV$pending, TEV$errors), collapse = "\n  · "))
if (!setequal(vapply(TEV$record, function(z) z$path, ""), vapply(pre$tests_dt$files, function(z) z$path, ""))) stop("[repin] DT 시험 증거 목록 ≠ 사전등록(정의가 바뀌었다)")
new$tests_dt$files <- TEV$record
RF <- fromJSON(file.path(ROOT, DTC$RNG_FACTS), simplifyVector = FALSE)
new$reseed$rng_facts <- list(path = DTC$RNG_FACTS, md5 = md5(file.path(ROOT, DTC$RNG_FACTS)),
                             fields = RF[intersect(names(RF), c("hidden_init_equal", "output_row0_equal", "cpu_rng_state_after_init_equal", "batch_order_equal",
                                                                 "cpu_first_step_hidden_output_equal", "cpu_hidden_output_equal_when_rng_state_aligned",
                                                                 "model_built_on", "device", "torch", "ok"))],
                             cuda = pre$reseed$rng_facts$cuda)
## 공통 난수 사실(판정에 쓰는 논리 필드)은 판이 바뀌어도 같아야 한다 — 다르면 reseed.note 근거가 바뀐 것이므로 중단(사람 판단)
FACT_KEYS <- c("hidden_init_equal", "output_row0_equal", "cpu_rng_state_after_init_equal", "batch_order_equal",
               "cpu_first_step_hidden_output_equal", "cpu_hidden_output_equal_when_rng_state_aligned", "model_built_on", "device", "ok")
fd <- FACT_KEYS[!vapply(FACT_KEYS, function(k) identical(cj(pre$reseed$rng_facts$fields[[k]]), cj(new$reseed$rng_facts$fields[[k]])), logical(1))]
if (length(fd)) stop("[repin] 공통 난수 사실이 바뀌었다(", paste(fd, collapse = ", "), ") — reseed.note 근거 재검토 필요 · 중단")
new$evaluation$files <- lapply(pre$evaluation$files, function(f) list(path = f$path, md5 = md5(file.path(ROOT, f$path))))

## 바뀐 칸 = 허용 목록 안인가(최상위 키 단위 · 그 안은 아래 출력으로 확인)
ALLOWED <- c("operational_pins", "engines", "tests_dt", "reseed", "evaluation")
ch_top <- names(pre)[!vapply(names(pre), function(k) identical(cj(pre[[k]]), cj(new[[k]])), logical(1))]
if (length(setdiff(ch_top, ALLOWED))) stop("[repin] 허용 밖 칸이 바뀌었다: ", paste(setdiff(ch_top, ALLOWED), collapse = ", "))
sub_ch <- function(a, b, path) {   # 바뀐 잎 경로 목록
  if (is.list(a) && is.list(b) && !is.null(names(a)) && identical(sort(names(a)), sort(names(b))))
    unlist(lapply(names(a), function(k) sub_ch(a[[k]], b[[k]], paste0(path, ".", k))))
  else if (is.list(a) && is.list(b) && is.null(names(a)) && length(a) == length(b))
    unlist(lapply(seq_along(a), function(i) sub_ch(a[[i]], b[[i]], sprintf("%s[%d]", path, i))))
  else if (identical(cj(a), cj(b))) character(0) else sprintf("%s: %s → %s", path, substr(cj(a), 1, 70), substr(cj(b), 1, 70))
}
CH <- unlist(lapply(ch_top, function(k) sub_ch(pre[[k]], new[[k]], k)))
## 엔진 절 안에서 바뀐 것은 python 뿐이어야 한다(생성 엔진 · 매니페스트 · 정적 PIT · 상수 · 재시드 엔진 핀은 그대로)
if (any(!grepl("^engines\\.python", grep("^engines\\.", CH, value = TRUE)))) stop("[repin] 엔진 절에서 python 밖이 바뀌었다")
if (any(!grepl("^reseed\\.rng_facts", grep("^reseed\\.", CH, value = TRUE)))) stop("[repin] reseed 절에서 rng_facts 밖이 바뀌었다")
if (any(!grepl("^operational_pins\\.(r_version|packages)", grep("^operational_pins\\.", CH, value = TRUE)))) stop("[repin] 운영 핀에서 판 밖(경로 · 카탈로그)이 바뀌었다")
cat(sprintf("[repin] 바뀐 잎 %d개:\n", length(CH))); cat(paste0("  · ", CH, collapse = "\n"), "\n")
if (length(EXPECT)) {   # 바뀐 잎 '경로'(값 앞부분)가 기대 집합과 정확히 같아야 한다
  got <- sub(":.*$", "", CH)
  if (!setequal(got, EXPECT)) stop("[repin] 바뀐 잎이 기대와 다르다 — 기대 {", paste(EXPECT, collapse = ", "), "} · 실제 {", paste(got, collapse = ", "), "} · 중단")
  cat("[repin] 바뀐 잎 = 기대 집합 ✓\n")
}

ev_changed <- vapply(seq_along(pre$evaluation$files), function(i) !identical(pre$evaluation$files[[i]]$md5, new$evaluation$files[[i]]$md5), logical(1))
txt <- if (length(ENTRY)) fromJSON(ENTRY[1], simplifyVector = FALSE) else list(   # 기본 = 11-08 첫 재핀 문구(그대로)
  approved = "도훈 2026-11-08 — 'R과 파이썬, 그리고 각종 사용 패키지들도 최신화' · 시점 '지금 전부 · P2R05 다시 고정' · '진행해줘'",
  reason = paste0("환경 최신화(R ", sub("^R version ([0-9.]+).*$", "\\1", op$r_version), " → ", sub("^R version ([0-9.]+).*$", "\\1", R.version.string),
                  " · Python ", pre$engines$python$python, " → ", PYV$python, " · torch ", pre$engines$python$torch, " → ", PYV$torch,
                  ") — 결과 전 · 설계(칸 · 규칙 · 상수 · 최종 후보 선택 규칙 · 운영 경로 · 카탈로그) 불변 · 환경 핀만 교체"),
  evaluation_change = "evaluate.R · precheck.R — bare bash → qv_bash()(금칙 ⑦ · 메인 PC WSL bash 가로챔 수리) 두 곳만 · 지문 정의 · 판정 논리 · 입력 불변",
  tests_dt_rerun = paste0("DT tests/run_all_tests.R 느린 판을 새 환경에서 재실행(", PYV$python, " · ", PYV$torch, ") — 8/8 통과 · 시험 중 파일 md5 불변 · ",
                          "옛 증거(Python 3.12 판) 보관 = .cache/installers/p2r05_dt_out_py312_20261108/ · 11-06 세션 재개 메모의 '재실행 금지'는 등록 핀 보호용 — 이 재고정이 대체"),
  rehearsal_not_rerun = "rehearse.R 은 다시 돌리지 않았다 — rehearsal.evaluate_md5 는 리허설 때 파일(옛 evaluate.R)을 가리키는 역사 기록 · 옛 판과의 차이 = bash 해석 두 곳뿐(판정 논리 불변)",
  warm = "워밍 센티널(night_state/p2r05_warm.done)은 아직 없다 — 워밍은 새 사전등록 md5 · 새 torch 로 처음부터(precheck --warm-check 가 사전등록 md5 를 대조)")
if (!all(c("approved", "reason") %in% names(txt))) stop("[repin] --entry 에 approved · reason 이 없다")
new$repins <- c(pre$repins %||% list(), list(c(
  list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), by = "Q", approved = txt$approved, reason = txt$reason,
       from_md5 = OLD, changed = as.list(CH),
       evaluation_files_changed = as.list(vapply(pre$evaluation$files[ev_changed], function(f) f$path, ""))),
  txt[setdiff(names(txt), c("approved", "reason"))])))
NEWF <- tempfile(fileext = ".json"); wr(new, NEWF); NEW <- md5(NEWF)
chk <- fromJSON(NEWF, simplifyVector = FALSE)
stopifnot(identical(chk$operational_pins$r_version, R.version.string), identical(cj(chk$engines$python[DTC$PY_KEYS]), cj(PYV[DTC$PY_KEYS])),
          isTRUE(DTC$test_evidence_check(ROOT, pins = chk$tests_dt$files)$ok), identical(cj(chk$cells), cj(pre$cells)),
          identical(cj(chk$final_selection_rule), cj(pre$final_selection_rule)), identical(cj(chk$rehearsal), cj(pre$rehearsal)),
          identical(cj(chk$evaluate_consistency), cj(pre$evaluate_consistency)))
cat(sprintf("[repin] 새 사전등록 md5 %s (옛 %s) · repins %d건\n", NEW, OLD, length(new$repins)))
if (!APPLY) { cat("[repin] 계획만 — 쓰지 않았다(--apply 로 적용)\n"); quit(status = 0L) }

## 적용 — 두 사본 → 등록부(R2 supersede). 등록부 실패 시 두 사본을 옛 판으로 되돌린다.
BK <- file.path(ROOT, ".cache/installers", sprintf("p2r05_prereg_before_repin_%s.json", OLD))
if (!file.exists(BK) && !isTRUE(file.copy(PR, BK))) stop("[repin] 옛 사전등록 보관 실패")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
tryCatch({
  if (!isTRUE(file.copy(NEWF, PR, overwrite = TRUE)) || !isTRUE(file.copy(NEWF, PRC, overwrite = TRUE))) stop("사본 쓰기 실패")
  if (!identical(md5(PR), NEW) || !identical(md5(PRC), NEW)) stop("쓴 뒤 md5 불일치")
  pr_record_round("P2_DEFENSE", list(round_id = "P2R05_distribution_target", prereg = rel(PR), prereg_md5 = NEW, status = "registered",
                                     supersedes = list(md5 = OLD, reason = new$repins[[length(new$repins)]]$reason)), root = ROOT)
}, error = function(e) {
  file.copy(BK, PR, overwrite = TRUE); file.copy(BK, PRC, overwrite = TRUE)
  stop("[repin] 적용 중단 — 두 사본을 옛 판으로 되돌렸다: ", conditionMessage(e))
})
rr <- Filter(function(r) identical(r$round_id, "P2R05_distribution_target"), pr_get(pr_load(ROOT), "P2_DEFENSE")$rounds)[[1]]
cat(sprintf("[repin] 적용 — 두 사본 md5 %s · 등록부 prereg_md5 %s · supersede_history %d건 · 옛 판 보관 %s\n", NEW, rr$prereg_md5,
            length(rr$supersede_history %||% list()), rel(BK)))
