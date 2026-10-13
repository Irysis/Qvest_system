## P4R01 — 측정 뒤: 처방 칸 평가(round_kit) · 반증 기계 판정(골격 보는 창 패킷 기준) · 기계 선택 규칙 · ③ 리뷰어 레인 준비(md 만)
## 실행: Rscript evaluate.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
PROGRAM <- "P4_ASSEMBLY"; ROUND <- "P4R01_skeleton_rx"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
PR <- file.path(P$prereg_dir, "prereg.json")
rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(pr_load(ROOT), PROGRAM)$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P4R01 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path); if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P4R01 평가] 설정 사본 변경")
TAU <- as.Date(pre$tau_d)
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL
EVS <- lapply(pre$cells, function(cl) rk_eval_cell(ROOT, RD, cl, env, TAU)); names(EVS) <- vapply(pre$cells, function(z) z$code, character(1))
base_pk <- fromJSON(file.path(RD, "base", "diagnosis_packet.json"), simplifyVector = FALSE)
cmp <- function(a, op, b) if (!is.finite(a) || !is.finite(b)) NA else switch(op, "<" = a < b, "<=" = a <= b, ">" = a > b, ">=" = a >= b)
rule_eval <- function(vis, q) { a <- rk_getf(vis, q$field)
  b <- if (identical(q$ref, "base")) rk_getf(base_pk, q$field) + as.numeric(q$delta) else as.numeric(q$value)
  list(field = q$field, op = q$op, value = a, threshold = b, ref = q$ref %||% "abs", triggered = cmp(a, q$op, b)) }
rows <- list(); rev_md <- list()
for (z in pre$prescriptions) {
  code <- paste0("P4R01_", z$id); e <- EVS[[code]]
  if (is.null(e) || !(e$status %in% c("evaluated", "axis_violation"))) { rows[[code]] <- list(id = z$id, code = code, status = e$status %||% "not_measured"); next }
  vis <- fromJSON(file.path(RD, "results", code, "visible", "diagnosis_packet.json"), simplifyVector = FALSE)
  fal <- lapply(z$falsification, function(q) rule_eval(vis, q))
  trig <- vapply(fal, function(f) isTRUE(f$triggered), logical(1)); unk <- vapply(fal, function(f) is.na(f$triggered), logical(1))
  req <- lapply(pre$final_selection$require %||% list(), function(q) rule_eval(vis, q))
  rows[[code]] <- list(id = z$id, code = code, status = e$status, rejected = any(trig) || identical(e$status, "axis_violation"),
                       undetermined = any(unk) && !any(trig), falsification = fal,
                       require_ok = all(vapply(req, function(f) isTRUE(f$triggered), logical(1))),
                       primary = rk_getf(vis, pre$final_selection$primary), tie = rk_getf(vis, pre$final_selection$tie_break),
                       grade = e$full$grade, S = e$full$S, visible = e$visible, axis_ok = isTRUE(e$axis$ok))
  rev_md[[code]] <- file.path(RD, "results", code, "visible", "diagnosis_packet.md")
}
## 기계 선택(처방 담당이 사전등록한 규칙 그대로)
FS <- pre$final_selection
cand <- Filter(function(r) identical(r$status, "evaluated") && !isTRUE(r$rejected) && !isTRUE(r$undetermined) && isTRUE(r$require_ok) && is.finite(r$primary), rows)
sel <- NULL
if (length(cand)) {
  pv <- vapply(cand, function(r) r$primary, numeric(1)); best <- if (FS$direction == "max") max(pv) else min(pv)
  near <- cand[abs(pv - best) <= as.numeric(FS$tie_eps)]
  tv <- vapply(near, function(r) r$tie, numeric(1)); tv[!is.finite(tv)] <- if (FS$tie_direction == "max") -Inf else Inf
  sel <- near[[if (FS$tie_direction == "max") which.max(tv) else which.min(tv)]]
}
res <- list(schema = "p4r01_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            rows = rows, selected = if (is.null(sel)) NULL else list(id = sel$id, code = sel$code, primary = sel$primary),
            base = list(code = pre$base$code, calmar = rk_getf(base_pk, "performance.strategy.calmar"), port_t = rk_getf(base_pk, "performance.strategy.port_t"),
                        uc = rk_getf(base_pk, "behavior.summary.bull_up_capture_median"), dc = rk_getf(base_pk, "behavior.summary.crisis_cum_capture_median")))
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "results", "evaluation.json"))
for (r in rows) cat(sprintf("[P4R01] %s — %s · 기각 %s · 후보 조건 %s · primary %s\n", r$id, r$status, isTRUE(r$rejected), isTRUE(r$require_ok),
                            format(r$primary %||% NA)))
cat("[P4R01] 선택:", if (is.null(sel)) "없음" else sel$id, "\n")
## ③ 리뷰어 레인 — md 만(보는 창) · 사전등록 · 반증 · 선택 결과를 md 로 렌더
LR <- P$lane("reviewer"); unlink(LR, recursive = TRUE); dir.create(LR, recursive = TRUE, showWarnings = FALSE)
L <- c("# 반증 · 선택 결과(보는 창 · R 기계 판정)", "")
for (r in rows) { L <- c(L, sprintf("## %s — %s", r$id, if (isTRUE(r$rejected)) "기각" else if (isTRUE(r$undetermined)) "판정 불가" else "반증 통과"))
  for (f in r$falsification %||% list()) L <- c(L, sprintf("- %s %s %s → 값 %s · %s", f$field, f$op, format(signif(f$threshold, 4)), format(signif(f$value, 4)),
                                                          if (isTRUE(f$triggered)) "참(기각)" else if (isFALSE(f$triggered)) "거짓" else "판정 불가"))
  L <- c(L, sprintf("- 후보 조건(require) 충족: %s · primary(%s) = %s", isTRUE(r$require_ok), FS$primary, format(signif(r$primary %||% NA, 4))), "") }
L <- c(L, sprintf("**최종 선택(사전등록 규칙 기계 적용): %s**", if (is.null(sel)) "없음" else sel$id))
fs_md <- paste(L, collapse = "\n"); .rx_assert_clean(fs_md, ROOT, "reviewer_falsification")
pre_md <- paste0("# 사전등록(요약)\n\n```\n", paste(readLines(file.path(P$lane("prescriber"), "out.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n"), "\n```\n")
files <- list(`falsification_selection.md` = I(fs_md), `prescriptions.md` = file.path(P$lane("prescriber"), "out.md"),
              `analyst_report.md` = file.path(P$lane("analyst"), "out.md"), `base_packet.md` = file.path(RD, "base", "diagnosis_packet.md"),
              `charter.md` = file.path(RD, "charter.md"))
for (cd in names(rev_md)) files[[paste0(sub("^P4R01_", "", cd), "_packet.md")]] <- rev_md[[cd]]
prompt <- paste0(
"# 역할: 조립 · 처방 루프 1라운드 — ③ 리뷰어 (청정 레인 · 읽기 전용)

처방 변형들이 측정됐다. 당신은 **리뷰어**다 — 반증과 선택은 R 이 사전등록 규칙대로 기계 판정했다(falsification_selection.md). 당신의 일은
① 기계 판정 확인(이견이 있으면 근거와 함께 기록 — 판정을 바꾸지는 않는다) ② **기전 판독**: 각 처방이 왜 그 결과를 냈나(패킷 수치 인용 · 위기별 · MC8 귀속)
③ 다음 라운드 권고: deepen(같은 기전 정교화) · pivot(다른 기전) · stop(R7 — 개선이 잡음 이내).

## 재료(작업 디렉터리 ", LR, ")
- falsification_selection.md · prescriptions.md(처방전 · 사전등록) · analyst_report.md · base_packet.md(골격) · RX*_packet.md(처방 변형의 보는 창 패킷) · charter.md

## 규칙
- 수치를 새로 계산하지 마라 — 패킷 인용만. 2023년 이후 정보는 근거로 쓰지 마라. 보는 창 밖 수치는 없다.
- 크기 방어 · 노출 방어를 실력으로 쓰지 마라(MC8 귀속 라벨을 따른다).

## 산출 — 리뷰(한국어 · 마크다운) + 맨 끝 ```json 블록:
```json
{\"agree_with_machine\": true, \"dissent\": \"...\", \"mechanism_readings\": [{\"id\": \"RX1\", \"reading\": \"...\"}],
 \"recommendation\": \"deepen|pivot|stop\", \"next_probes\": [\"...\", \"...\"], \"noise_judgement\": \"개선이 잡음 이내|잡음 밖\"}
```
")
rx_prepare_lane(LR, files = files, prompt = prompt, root = ROOT)
cat("reviewer lane:", LR, "\n")
