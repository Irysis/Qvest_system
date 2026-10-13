## P2R01 S2 파일럿 — 측정 뒤: 변형별 보는 창 패킷(리뷰어) · 전기간 카드 + 등급(사람) · 반증 기계 판정 · ③ 리뷰어 레인 준비
## 실행: Rscript evaluate.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R01_s2_pilot"
P <- rx_paths(PROGRAM, ROUND, ROOT)
md5 <- function(f) unname(as.character(tools::md5sum(f)))

## 사전등록 불변 확인(R2) — 등록부에 적힌 md5 와 같아야 한다
PR <- file.path(P$prereg_dir, "prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(reg, PROGRAM)$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, md5(PR))) stop("[evaluate] 사전등록 md5 불일치 — 결과 뒤 변경 의심(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
base_pk <- fromJSON(file.path(P$round_dir, "base", "diagnosis_packet.json"), simplifyVector = FALSE)

getf <- function(x, path) { for (k in strsplit(path, ".", fixed = TRUE)[[1]]) { if (is.null(x)) return(NA_real_); x <- x[[k]] }
                            v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }
cmp <- function(a, op, b) if (!is.finite(a) || !is.finite(b)) NA else switch(op, "<" = a < b, "<=" = a <= b, ">" = a > b, ">=" = a >= b)

RES <- file.path(P$round_dir, "results")
raw <- mc_load_raw(ROOT, from = "2004-11-01")
## ★반증 · 리뷰어 재료 = 사전등록 당시 행동 카드 설정(위기 정의 v1 · 고점 회복까지)으로 고정(R2) —
##   10-13 도훈 결정으로 위기 정의가 LT 20/20 으로 바뀌어도 이 라운드의 반증 의미는 등록 때 그대로다. 사람 쪽 전기간 카드 · 등급은 현행 정의.
BCFG_PRE <- file.path(P$round_dir, "behavior_card_cfg_at_prereg.json")
if (!identical(unname(tools::md5sum(BCFG_PRE)), "f9ebd5e9090433c0df1071ccc0da529e")) stop("[evaluate] 사전등록 당시 행동 카드 설정 사본이 바뀌었다")
rows <- list(); rev_files <- list(); rev_json <- list()   # 레인엔 md 만(json 은 청정 레인 내용 가드 R1_content 가 막는다) · json 은 날짜 검사용
## 같은 판본 기저 대조(RX0) — 반증 ref = base 의 기준 · 리뷰어 기저 패킷
c0 <- pre$control_cell; base_src <- "prescription_time_base(09-23 판본)"
r0f <- file.path(RES, paste0(c0$code, ".json"))
if (file.exists(r0f) && isTRUE(fromJSON(r0f)$ok)) {
  r0 <- fromJSON(r0f, simplifyVector = FALSE); out0 <- file.path(RES, c0$code); dir.create(out0, showWarnings = FALSE)
  v0 <- dp_build(r0$artifacts, root = ROOT, cell_spec = c0$spec$path, bcfg = BCFG_PRE); dp_write(v0, file.path(out0, "visible"))
  k0 <- mc_card(r0$artifacts, root = ROOT, raw = raw); mc_write(k0, file.path(out0, "full"), root = ROOT)
  a0 <- fromJSON(file.path(r0$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  base_pk <- v0; base_src <- "RX0(같은 판본 재측정)"
  base_md <- file.path(out0, "visible", "diagnosis_packet.md"); base_json <- file.path(out0, "visible", "diagnosis_packet.json")
  rows[[c0$code]] <- list(id = "RX0", code = c0$code, status = "measured", control = TRUE, artifacts = r0$artifacts,
                          grade = a0$essence_grade, grade_v3 = a0$grade_v3,
                          visible = list(perf = v0$performance$strategy, verdict = v0$behavior$verdict, summary = v0$behavior$summary,
                                         attribution = v0$controls$attribution),
                          full = list(cr = k0$overall$verdict, cr_visible = k0$visible$verdict, cr_test = k0$test$verdict,
                                      attribution = k0$controls$attribution, stats = k0$stats))
} else {
  base_md <- file.path(P$round_dir, "base", "diagnosis_packet.md"); base_json <- file.path(P$round_dir, "base", "diagnosis_packet.json")
  rows[[c0$code]] <- list(id = "RX0", code = c0$code, status = "measure_failed", control = TRUE)
}
cat("반증 기준(ref = base):", base_src, "\n")
for (z in pre$prescriptions) {
  if (is.null(z$spec)) next
  code <- z$spec$code; rj <- file.path(RES, paste0(code, ".json"))
  if (!file.exists(rj)) { rows[[code]] <- list(id = z$id, code = code, status = "not_measured"); next }
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) { rows[[code]] <- list(id = z$id, code = code, status = "measure_failed", err = r$err %||% NA); next }
  dir <- r$artifacts
  out <- file.path(RES, code); dir.create(out, showWarnings = FALSE)
  vis <- dp_build(dir, root = ROOT, cell_spec = z$spec$path, bcfg = BCFG_PRE) # 보는 창 — 리뷰어 재료(사전등록 당시 위기 정의)
  dp_write(vis, file.path(out, "visible"))
  card <- mc_card(dir, root = ROOT, raw = raw)                               # 전기간 — 사람 쪽(등급 · 시험 창)
  mc_write(card, file.path(out, "full"), root = ROOT)
  ar <- fromJSON(file.path(dir, "authoritative_remeasure.json"), simplifyVector = FALSE)
  # 반증 기계 판정(보는 창 · 사전등록 규칙 그대로)
  fal <- lapply(z$falsification, function(q) {
    a <- getf(vis, q$field)
    b <- if (identical(q$ref, "base")) getf(base_pk, q$field) + as.numeric(q$delta) else as.numeric(q$value)
    list(field = q$field, op = q$op, value = a, threshold = b, ref = q$ref %||% "abs", triggered = cmp(a, q$op, b))
  })
  trig <- vapply(fal, function(f) isTRUE(f$triggered), logical(1)); unk <- vapply(fal, function(f) is.na(f$triggered), logical(1))
  rows[[code]] <- list(id = z$id, code = code, status = "measured", artifacts = dir,
                       vis_json = file.path(out, "visible", "diagnosis_packet.json"),
                       falsification = fal, rejected = any(trig), undetermined = any(unk) && !any(trig),
                       grade = ar$essence_grade, grade_v3 = ar$grade_v3,
                       visible = list(perf = vis$performance$strategy, verdict = vis$behavior$verdict, summary = vis$behavior$summary,
                                      attribution = vis$controls$attribution),
                       full = list(cr = card$overall$verdict, cr_visible = card$visible$verdict, cr_test = card$test$verdict,
                                   attribution = card$controls$attribution, stats = card$stats))
  rev_files[[paste0(code, "_visible_packet.md")]] <- file.path(out, "visible", "diagnosis_packet.md")
  rev_json[[code]] <- file.path(out, "visible", "diagnosis_packet.json")
}
writeLines(toJSON(rows, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "summary_full.json"), useBytes = TRUE)

## ── 최종 후보 선택 규칙 — 기계 적용(R 계산 · 리뷰어는 확인만) ──────────────────────────────
##   상수는 사전등록 문구(final_selection_rule ②~④)에서 옮겼다 — 문구 대조로 묶어 둔다(문구가 다르면 정지).
##   ④ '0.02 이내 동률' = 최고 Calmar 와 0.02 이내인 후보 집합으로 읽는다 → 그 안에서 CAGR → PORT_t → 못 가르면 ⑤ 선정 없음.
SR <- pre$final_selection_rule
for (frag in c("0.03 이상 개선된 위기'가 2건 이상", "Calmar 차가 0.02 이내"))
  if (!grepl(frag, SR, fixed = TRUE)) stop("[evaluate] 선택 규칙 문구가 옮긴 상수와 다르다: ", frag)
SEL_GAIN <- 0.03; SEL_MIN_CRISES <- 2L; SEL_TIE <- 0.02; EPS <- 1e-12   # EPS = 부동소수 경계
crisis_tab <- function(f) {
  if (is.null(f) || !file.exists(f)) return(NULL)
  x <- fromJSON(f, simplifyVector = TRUE)$behavior$crises
  if (is.null(x) || !NROW(x)) NULL else data.frame(peak = as.character(x$peak_date), dd = suppressWarnings(as.numeric(x$dd_capture)))
}
num <- function(v) { v <- suppressWarnings(as.numeric(v)); if (length(v) == 1L) v else NA_real_ }
cb <- crisis_tab(base_json)
sel <- list()
for (rw in rows) {
  if (isTRUE(rw$control)) next
  if (!identical(rw$status, "measured")) { sel[[rw$id]] <- list(id = rw$id, stage = rw$status, survive = FALSE); next }
  passed <- !isTRUE(rw$rejected) && !isTRUE(rw$undetermined)
  cv <- crisis_tab(rw$vis_json)
  m <- if (is.null(cv) || is.null(cb)) NULL else merge(cv, cb, by = "peak", suffixes = c("_rx", "_base"))
  n_imp <- if (is.null(m)) NA_integer_ else sum(is.finite(m$dd_rx) & is.finite(m$dd_base) & (m$dd_base - m$dd_rx) >= SEL_GAIN - EPS)
  pf <- rw$visible$perf
  sel[[rw$id]] <- list(id = rw$id, stage = "measured", falsification_passed = passed, n_crises_matched = if (is.null(m)) 0L else nrow(m),
                       n_crises_improved = n_imp, survive = passed && isTRUE(n_imp >= SEL_MIN_CRISES),
                       calmar = num(pf$calmar), cagr = num(pf$cagr), port_t = num(pf$port_t))
}
cand <- Filter(function(s) isTRUE(s$survive), sel)
pick <- "none"; why <- "① · ② 를 통과한 처방 없음 — 선정 없음"
if (length(cand)) {
  cal <- vapply(cand, function(s) s$calmar, 0)
  if (any(!is.finite(cal))) { why <- "후보 Calmar 결측 — 선정 없음(⑤)" } else {
    top <- cand[cal >= max(cal) - SEL_TIE - EPS]
    if (length(top) == 1L) { pick <- top[[1]]$id; why <- "③ 남은 후보 중 Calmar 최고" } else {
      cg <- vapply(top, function(s) s$cagr, 0)
      if (any(!is.finite(cg))) { why <- "④ CAGR 결측 — 선정 없음(⑤)" } else {
        top2 <- top[cg == max(cg)]
        if (length(top2) == 1L) { pick <- top2[[1]]$id; why <- "④ Calmar 0.02 이내 동률 → CAGR 높은 쪽" } else {
          pt <- vapply(top2, function(s) s$port_t, 0)
          top3 <- if (any(!is.finite(pt))) list() else top2[pt == max(pt)]
          if (length(top3) == 1L) { pick <- top3[[1]]$id; why <- "④ Calmar · CAGR 동률 → PORT_t 높은 쪽" } else why <- "⑤ ③④로 가르지 못함 — 선정 없음"
        }
      }
    }
  }
}
selection <- list(rule = SR, constants = list(gain = SEL_GAIN, min_crises = SEL_MIN_CRISES, tie = SEL_TIE),
                  base_ref = base_src, per_prescription = unname(sel), selected = pick, reason = why)
writeLines(toJSON(selection, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA),
           file.path(RES, "selection_visible.json"), useBytes = TRUE)
f4 <- function(v) if (is.finite(v)) formatC(v, format = "f", digits = 4) else "—"
sel_md <- c("# 최종 후보 선택 규칙 — 기계 적용 (보는 창 · R 계산 · 사전등록 규칙 그대로)", "",
            paste0("기저(ref) = ", base_src, " · 개선 = 기저 하락 포착 − 처방 하락 포착 ≥ ", SEL_GAIN, " 인 위기 수(같은 위기 = 같은 고점일)"), "",
            "| 처방 | 반증 통과 | 대조 위기 | 개선 위기 | ② 생존 | Calmar | CAGR | PORT_t |", "|---|---|---|---|---|---|---|---|")
for (s in sel) sel_md <- c(sel_md, if (!identical(s$stage, "measured")) sprintf("| %s | 측정 안 됨(%s) | — | — | 아니오 | — | — | — |", s$id, s$stage) else
  sprintf("| %s | %s | %d | %s | %s | %s | %s | %s |", s$id, if (s$falsification_passed) "예" else "아니오", s$n_crises_matched,
          if (is.na(s$n_crises_improved)) "—" else as.character(s$n_crises_improved), if (s$survive) "예" else "아니오",
          f4(s$calmar), f4(s$cagr), f4(s$port_t)))
sel_md <- c(sel_md, "", sprintf("**선정: %s** — %s", pick, why))
sel_txt <- paste(sel_md, collapse = "\n")
writeLines(sel_txt, file.path(RES, "selection_visible.md"), useBytes = TRUE)

## 리뷰어 재료 — 보는 창만(전기간 등급 · 시험 창 · 전기간 카드는 넣지 않는다)
fal_md <- c("# 반증 조건 기계 판정 (보는 창 · R 계산 · 사전등록 규칙 그대로)", "",
            paste0("기저(ref = base) = ", base_src, " — base_packet.md 가 그 패킷이다."), "",
            "| 처방 | 필드 | 연산 | 처방 값 | 문턱 | 기준 | 참(=기각) |", "|---|---|---|---|---|---|---|")
for (rw in rows) {
  if (isTRUE(rw$control)) next
  if (!identical(rw$status, "measured")) { fal_md <- c(fal_md, sprintf("| %s | — | — | — | — | — | 측정 안 됨(%s) |", rw$id, rw$status)); next }
  for (f in rw$falsification) fal_md <- c(fal_md, sprintf("| %s | %s | %s | %s | %s | %s | %s |", rw$id, f$field, f$op,
                                                          formatC(f$value, format = "f", digits = 4), formatC(f$threshold, format = "f", digits = 4),
                                                          f$ref, if (is.na(f$triggered)) "판정 불가" else if (isTRUE(f$triggered)) "참" else "거짓"))
}
fal_txt <- paste(fal_md, collapse = "\n")
writeLines(fal_txt, file.path(RES, "falsification_visible.md"), useBytes = TRUE)
pre_rev <- pre; pre_rev$agents <- NULL; pre_rev$base$artifact <- NULL; pre_rev$base$flags <- NULL
pre_rev$registered_at <- NULL; pre_rev$purpose <- NULL                    # 등록 시각 · 목적 문구(결정 id) — 판독에 불필요 · 처방 입력 검사 대상
pre_txt <- toJSON(pre_rev, auto_unbox = TRUE, pretty = TRUE, null = "null")
LR <- P$lane("reviewer")
prompt <- paste0(
"# 역할: 처방 루프 v0 — ③ 리뷰어 (청정 레인 · 읽기 전용)

당신은 리뷰어다. **수치가 아니라 기전을 판독**한다 — 처방이 사전등록한 기전대로 작동했는가.
작업 디렉터리: ", LR, "
- prereg.md — 사전등록 원문(json 블록 · 처방 · 기대 방향 · 반증 규칙 · 최종 후보 선택 규칙). 결과를 본 뒤 바꿀 수 없다.
- base_packet.md — 기저 보는 창 진단(같은 데이터 판본으로 다시 잰 기저 — 반증 · 선택의 기준)
- <처방코드>_visible_packet.md — 처방 변형마다 같은 계약으로 만든 보는 창 진단
- falsification_visible.md — 반증 규칙의 기계 판정(R 계산)
- selection_visible.md — 최종 후보 선택 규칙의 기계 적용(R 계산)
- charter.md · analyst_report.md
모든 수치는 보는 창(2005-02 ~ 2022-12)이다. 2023년 이후 정보 · 사전학습 사건 지식을 쓰지 마라. 수치를 새로 계산하지 마라(인용만).

## 판독 항목 (처방마다)
1. 반증 판정 — 기계 판정 결과 그대로(참이 하나라도 있으면 기각). 판정 불가 항목은 그 이유.
2. 기전 확인 — 개선(또는 악화)이 **겨냥한 약점 · 위기**에서 왔는가? 기저와 처방 패킷의 위기별 표 · 노출 분해 · 위기 귀속을 대조하라.
3. 지속성(R6) — 개선이 여러 위기에 걸쳐 있는가, 한 위기에 몰렸는가.
4. 대조(R5 · MC8) — 노출 짝 · 크기 짝을 넘었는가(귀속 라벨 · 무작위 분위 p). '노출 방어' · '크기 방어'면 실력으로 세지 마라.
5. 강점 보존 — 사전등록한 보존 지표(선택 성분 · 상승 포착 등)가 유지됐는가.
6. 비용 — 무엇을 잃었나(상승 포착 · PORT_t · 회전).

## 종합
- 최종 후보: selection_visible.md 가 사전등록 선택 규칙의 기계 적용이다 — `selected` 에는 그 결과를 **그대로** 적는다. 규칙 해석에 이견이 있으면 selection_reasoning 에 근거와 함께 적어라(선정을 바꾸지 않는다).
- 다음 수: deepen(같은 기전 정교화) / combine(성공 처방 누적) / switch(새 약점 가설) / stop(개선이 잡음 이내 — R7) 중 하나와 이유.
- 교훈(보는 창 수치만 · 기전이 특정되는 것만): 다음 논문의 처방 담당이 읽을 1~3줄.

응답 맨 끝에 ```json 블록 하나:
```json
{\"per_prescription\": [{\"id\": \"RX1\", \"falsified\": true, \"mechanism\": \"confirmed|partial|not_confirmed\", \"persistence\": \"broad|single_episode|none\",
   \"control_beaten\": \"selection|size|exposure|none\", \"strengths_preserved\": true, \"evidence\": [\"...\"], \"concerns\": [\"...\"]}],
 \"selected\": \"RX?|none\", \"selection_reasoning\": \"...\",
 \"next_move\": \"deepen|combine|switch|stop\", \"next_move_reasoning\": \"...\",
 \"next_hypotheses\": [\"...\"], \"lessons\": [\"...\"]}
```
")
pre_md <- paste0("# 사전등록 원문 (", ROUND, " · 결과 뒤 변경 불가 · 등록 md5 ", md5(PR), " · 판독에 불필요한 등록 시각 · 목적 · 산출 경로는 뺐다)\n\n```json\n",
                 pre_txt, "\n```\n")
files <- c(list(`prereg.md` = I(pre_md), `falsification_visible.md` = I(fal_txt), `selection_visible.md` = I(sel_txt),
                `base_packet.md` = base_md,
                `charter.md` = file.path(P$round_dir, "charter.md"),
                `analyst_report.md` = file.path(P$round_dir, "analyst_report.md")), rev_files)
## 리뷰어 재료 전수 검사 — md 의 원천 패킷(json)은 τ_D 뒤 날짜 0 이어야 한다(레인 복사 전)
for (f in c(base_json, unlist(rev_json))) {
  pk <- fromJSON(f, simplifyVector = FALSE)
  bad <- dp_scan_dates(pk[setdiff(names(pk), c("created_at", "tau_d"))], as.Date("2022-12-31"))
  if (length(bad)) stop("[evaluate] 리뷰어 재료에 τ_D 뒤 날짜: ", f, " ", paste(head(bad, 3), collapse = ","))
}
rx_prepare_lane(LR, files = files, prompt = prompt, root = ROOT)
cat("reviewer lane:", LR, "\n"); print(list.files(LR))
for (rw in rows) cat(sprintf("%s %s · 등급 %s · 반증 %s\n", rw$id, rw$status, rw$grade %||% "—",
                             if (isTRUE(rw$rejected)) "기각" else if (isTRUE(rw$undetermined)) "판정 불가 포함" else "통과"))
