## repin_p1r04.R — P1R04 사전등록 핀 가운데 '바뀐 운영 파일'의 md5 잎만 다시 고정(결과 전 · lean-loop 5 '재개 때 재핀') · 선례 = P2R05 재핀(04_Research/01_reports/env_upgrade_20261109/repin_p2r05.R)
##
## 왜: 등급 v3.5(도훈 결정 GRADE-CR-NOTCH-BETA-SELECTION-20261113 · 등급 v3.5 세션)가 코어 기본 핀(RC_PIN_FILES_DEFAULT) 여섯 파일
##     (grade_v3.R · matched_controls.R · essence_score.R · 06_Registry/grade_v3.json · 06_Registry/matched_controls.json)을 바꾼다 — P1R04 등록(11-13 08:45) 뒤 · 측정 전.
##     P1R04 판정(IS β-통제 알파 t · IS 상승 포착률 · 계보 판정 도구의 기준 엔진 대비 증분 알파)은 등급을 읽지 않고, v3.5 는 MC8 기존 필드의 뜻을 바꾸지 않는다(새 필드만)
##     → 판정 입력 불변. 칸 측정 기록의 등급(보고 열)은 v3.5 로 채점된다. 등록 문서(사양 · 규칙 · 칸 · 결론 범위)는 그대로다.
## 바꾸는 것: pins.files 중 ALLOW 경로의 md5 잎만(지금 디스크 값). 덧붙이는 것: repins[](시각 · 승인 · 사유 · 옛 md5 · 바뀐 잎).
## 안전: ① 두 사본 md5 같음 ② 바꾸지 않은 채 다시 직렬화 = 바이트 동일(register 와 같은 직렬화 rc_json_write) ③ status = registered · 칸 결과 파일 없음(R2)
##       ④ 바뀐 잎 ⊂ ALLOW md5(그 밖이 바뀌면 중단) ⑤ 재핀 뒤 핀 전체 = 지금 디스크(rc_pins_mismatches 0 — 다른 핀이 어긋나 있으면 중단 · 사람 확인)
## 실행(저장소 루트): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/repin_p1r04.R            계획만(쓰기 0)
##                   Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/repin_p1r04.R --apply    두 사본 → 등록부 supersede(옛 md5)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
APPLY <- "--apply" %in% commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RID <- "P1R04_combiner_t1_icw"
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN", RID)
PR <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN", RID, "prereg.json"); PRC <- file.path(RD, "prereg.json")
ALLOW <- c("02_Infrastructure/contracts/grade_v3.R", "02_Infrastructure/contracts/matched_controls.R", "02_Infrastructure/contracts/essence_score.R",
           "06_Registry/grade_v3.json", "06_Registry/matched_controls.json",
           "02_Infrastructure/contracts/diagnosis_packet.R")   # 11-13 v3.5 세션 추가 — IS 요약에 '시가총액 · β 일치 무작위 대조 귀속' 줄 + controls.beta_match 필드(기존 필드 불변 · τ_D 불변성 검사 통과)
md5 <- function(f) unname(as.character(tools::md5sum(f)))
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
ser <- function(x) toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)   # round_core rc_json_write 와 같은 직렬화
wr <- function(x, f) writeLines(ser(x), f, useBytes = TRUE)
cj <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))

if (!identical(md5(PR), md5(PRC))) stop("[repin p1r04] 사전등록 두 사본 md5 불일치 — 중단")
OLD <- md5(PR)
pre <- fromJSON(PR, simplifyVector = FALSE)
if (!identical(pre$status, "registered")) stop("[repin p1r04] status ≠ registered — 결과 뒤에는 바꿀 수 없다(R2)")
done <- list.files(file.path(RD, "results"), pattern = "\\.json$", recursive = TRUE)
if (length(done)) stop("[repin p1r04] results/ 에 측정 · 평가 파일이 있다(", length(done), ") — 결과 뒤 재핀 금지(R2)")
tf <- tempfile(fileext = ".json"); wr(pre, tf)
if (!identical(md5(tf), OLD)) stop("[repin p1r04] 바꾸지 않은 다시 직렬화가 바이트 동일이 아니다(", md5(tf), " ≠ ", OLD, ") — 서식 보존 불가 · 중단")
cat(sprintf("[repin p1r04] 옛 사전등록 md5 %s · 다시 직렬화 바이트 동일 ✓\n", OLD))

new <- pre
paths <- vapply(pre$pins$files, function(z) as.character(z$path), "")
idx <- which(paths %in% ALLOW)
if (!setequal(paths[idx], ALLOW) || length(idx) != length(ALLOW)) stop("[repin p1r04] 허용 경로가 핀 목록에 정확히 한 번씩 있지 않다")
for (i in idx) new$pins$files[[i]]$md5 <- md5(file.path(ROOT, paths[i]))
CH <- unlist(lapply(idx, function(i) if (identical(pre$pins$files[[i]]$md5, new$pins$files[[i]]$md5)) NULL else
  sprintf("pins.files[%d].md5(%s): %s → %s", i, paths[i], pre$pins$files[[i]]$md5, new$pins$files[[i]]$md5)))
if (!length(CH)) { cat("[repin p1r04] 허용 파일 md5 가 등록 때와 같다 — 재핀 불필요\n"); quit(status = 0L) }
## 바뀐 잎 = 허용 경로 md5 뿐(최상위 · 핀 다른 칸 · 다른 파일 잎이 같아야 한다)
top <- setdiff(names(pre), "pins")
if (!identical(cj(pre[top]), cj(new[top]))) stop("[repin p1r04] 핀 밖 칸이 바뀌었다 — 중단")
if (!identical(cj(pre$pins[setdiff(names(pre$pins), "files")]), cj(new$pins[setdiff(names(new$pins), "files")]))) stop("[repin p1r04] 핀의 core · packages · r_version 이 바뀌었다 — 중단")
if (!identical(cj(pre$pins$files[-idx]), cj(new$pins$files[-idx]))) stop("[repin p1r04] 허용 밖 핀 파일 잎이 바뀌었다 — 중단")
cat(sprintf("[repin p1r04] 바뀐 잎 %d개:\n", length(CH))); cat(paste0("  · ", CH, collapse = "\n"), "\n")
## 재핀 뒤 핀 전체 = 지금 디스크(코어 판정과 같은 함수)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "04_Research/programs/_lib/round_core/v3/load.R")))))
mm <- rc_pins_mismatches(new$pins, ROOT)
if (length(mm)) stop("[repin p1r04] 재핀 뒤에도 핀 불일치(허용 밖 — 사람 확인):\n", paste(mm, collapse = "\n"))
cat("[repin p1r04] 재핀 뒤 핀 전체 = 지금 디스크 ✓\n")
new$repins <- c(pre$repins %||% list(), list(list(
  at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), by = "Q",
  approved = "등급 v3.5 세션 조율(11-13 · 교체 순서 (나) — 지금 교체 · P1R04 는 측정 시작 때 재핀) · lean-loop 5 '막지 않는다 — 재개 때 재핀 · 사전등록 내용은 바꾸지 않는다'",
  reason = "등급 v3.5(도훈 GRADE-CR-NOTCH-BETA-SELECTION-20261113 — CR '강함' 가점의 선택 방어에 시가총액 × β 짝 요구)로 코어 기본 핀 여섯 파일(diagnosis_packet.R 포함 — 새 필드만)이 바뀌었다 — 결과 전 · P1R04 판정 입력(IS 알파 t · 상승 포착률 · 기준 엔진 대비 증분 알파)은 등급을 읽지 않는다 · MC8 기존 필드 뜻 불변 · 칸 등급(보고 열)은 v3.5",
  from_md5 = OLD, changed = as.list(CH))))
NEWF <- tempfile(fileext = ".json"); wr(new, NEWF); NEW <- md5(NEWF)
chk <- fromJSON(NEWF, simplifyVector = FALSE)
stopifnot(identical(cj(chk$cells), cj(pre$cells)), identical(cj(chk$rules_resolved), cj(pre$rules_resolved)), identical(cj(chk$spec), cj(pre$spec)),
          identical(chk$spec_md5, pre$spec_md5), length(rc_pins_mismatches(chk$pins, ROOT)) == 0L)
cat(sprintf("[repin p1r04] 새 사전등록 md5 %s (옛 %s) · repins %d건\n", NEW, OLD, length(new$repins)))
if (!APPLY) { cat("[repin p1r04] 계획만 — 쓰지 않았다(--apply 로 적용)\n"); quit(status = 0L) }

## 적용 — 옛 판 보관 → 두 사본 → 등록부(R2 supersede). 등록부 실패 시 두 사본을 옛 판으로 되돌린다.
BK <- file.path(ROOT, ".cache/installers", sprintf("p1r04_prereg_before_repin_%s.json", OLD))
dir.create(dirname(BK), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(BK) && !isTRUE(file.copy(PR, BK))) stop("[repin p1r04] 옛 사전등록 보관 실패")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
tryCatch({
  if (!isTRUE(file.copy(NEWF, PR, overwrite = TRUE)) || !isTRUE(file.copy(NEWF, PRC, overwrite = TRUE))) stop("사본 쓰기 실패")
  if (!identical(md5(PR), NEW) || !identical(md5(PRC), NEW)) stop("쓴 뒤 md5 불일치")
  pr_record_round("P1_RETURN", list(round_id = RID, prereg = rel(PR), prereg_md5 = NEW, status = "registered",
                                    supersedes = list(md5 = OLD, reason = new$repins[[length(new$repins)]]$reason)), root = ROOT)
}, error = function(e) {
  file.copy(BK, PR, overwrite = TRUE); file.copy(BK, PRC, overwrite = TRUE)
  stop("[repin p1r04] 적용 중단 — 두 사본을 옛 판으로 되돌렸다: ", conditionMessage(e))
})
rr <- Filter(function(r) identical(r$round_id, RID), pr_get(pr_load(ROOT), "P1_RETURN")$rounds)[[1]]
cat(sprintf("[repin p1r04] 적용 — 두 사본 md5 %s · 등록부 prereg_md5 %s · supersede_history %d건 · 옛 판 보관 %s\n", NEW, rr$prereg_md5,
            length(rr$supersede_history %||% list()), rel(BK)))
