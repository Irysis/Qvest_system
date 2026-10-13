## P2R01 라운드 종료 — ① 라운드 보고서(md · 사람 쪽 전기간) → ④ 교훈 1건(L-code · 보는 창 수치만 · 검사 후 적립) → ② 등록부 기록(pr_record_round · 같은 round_id/prereg) → ③ 보고 1통(prep_send)
##   (번호는 산출물 이름 · 실행 순서는 ① ④ ② ③ — 교훈 검사가 멈추면 등록부 · 발송 전에 멈춘다)
## 실행: Rscript close_round.R [record] [send]
##   send 없으면 텔레그램은 미리보기(QVEST_TG_DRY_RUN=1) · record 없으면 등록부 무변경 · 보고서 md 는 항상 쓴다
## 수치 = 계약 산출만 인용(authoritative_remeasure.json · 전기간 행동 카드 · 패킷) — 여기서 성과를 새로 계산하지 않는다(AX-008)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
args <- commandArgs(trailingOnly = TRUE)
RECORD <- "record" %in% args; SEND <- "send" %in% args
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_report.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R01_s2_pilot"; PNAME <- "방어 엔진"
P <- rx_paths(PROGRAM, ROUND, ROOT)
RES <- file.path(P$round_dir, "results")
PRE <- file.path(P$prereg_dir, "prereg.json"); PRE_REL <- sprintf("stage_artifacts/programs/%s/%s/prereg.json", PROGRAM, ROUND)
pre <- fromJSON(PRE, simplifyVector = FALSE)
rows <- fromJSON(file.path(RES, "summary_full.json"), simplifyVector = FALSE)
sel <- fromJSON(file.path(RES, "selection_visible.json"), simplifyVector = FALSE)
rv_out <- file.path(P$lane("reviewer"), "out.md")
rv <- if (file.exists(rv_out)) tryCatch(rx_parse_json(readLines(rv_out, warn = FALSE, encoding = "UTF-8")), error = function(e) NULL) else NULL
if (is.null(rv)) stop("[close] 리뷰어 응답(json 블록) 없음 — 리뷰어 레인을 먼저 돌린다")

LBL_DEF <- c(selection_defense = "선택 방어", size_defense = "크기 방어", exposure_defense = "노출 방어",
             no_defense = "방어 없음", insufficient = "판정 불가")
lbl <- function(x) if (is.null(x) || is.na(x)) "대조 없음" else unname(LBL_DEF[x] %||% x)
names_rx <- setNames(vapply(pre$prescriptions, function(z) z$name %||% z$id, ""), vapply(pre$prescriptions, function(z) z$id, ""))
short <- c(RX0 = "기저(같은 판본 재측정)", RX1 = "처방 1 · 하방 비대칭 팩터", RX2 = "처방 2 · 회전 상한", RX3 = "처방 3 · 추세 상태 베타 오버레이")
lk <- function(v, k, d = k) if (is.null(k) || length(k) != 1L || is.na(k) || !(k %in% names(v))) d else unname(v[[k]])
f2 <- function(v) if (is.null(v) || !is.finite(as.numeric(v))) "—" else formatC(as.numeric(v), format = "f", digits = 2)
pct <- function(v, signed = TRUE) prep_fmt_pct(as.numeric(v %||% NA_real_), 1L, signed)

## 축 감사(처방 · 조립 축 = 롱온리 · ≤ max_names 종) — 실제 보유(04_holdings)로 잰다. 사양이 엔진 파서를 통과해도
##   집행 규칙이 책을 불릴 수 있다(10-13 실측: turnover_cap 이 직전 보유와 목표를 섞고 종목 수 상한을 다시 걸지 않아 최대 120종).
##   위반 칸 = 측정 무효(미시험) — 등급은 인용하지 않는다(등급 파일은 손대지 않는다 · AX-008).
MAXN <- as.integer(fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_soft_deployment$max_names)
if (length(MAXN) != 1L || is.na(MAXN)) stop("[close] constraint_defaults.json::tier_soft_deployment.max_names 판독 실패")
axis_audit <- function(dir, to = NULL) {
  H <- fread(file.path(dir, "04_holdings.csv"), select = c("date", "target_weight"))
  if (!is.null(to)) H <- H[as.Date(date) <= as.Date(to)]
  nn <- H[target_weight > 0, .N, by = date]
  neg <- H[target_weight < 0, .N]
  list(n_rebal = nrow(nn), n_max = max(nn$N), n_mean = mean(nn$N), n_over = sum(nn$N > MAXN), neg = neg,
       ok = max(nn$N) <= MAXN && neg == 0L)
}

## 대상별 권위 등급(재채점 뒤 파일을 다시 읽는다) + 전기간 카드
info <- list()
for (rw in rows) {
  id <- rw$id; code <- rw$code
  if (!identical(rw$status, "measured")) { info[[id]] <- list(id = id, code = code, status = rw$status); next }
  ax <- axis_audit(rw$artifacts); ax_vis <- axis_audit(rw$artifacts, to = pre$tau_d)
  ar <- fromJSON(file.path(rw$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  gv <- ar$grade_v3 %||% list()
  cf <- file.path(RES, code, "full", "behavior_card.json")
  card <- if (file.exists(cf)) fromJSON(cf, simplifyVector = TRUE) else NULL
  info[[id]] <- list(id = id, code = code, status = "measured", artifacts = rw$artifacts, control = isTRUE(rw$control),
                     grade = ar$essence_grade %||% NA, S = gv$S %||% NA, rules = gv$rules_version %||% NA,
                     notch = gv$notch %||% NA, blocked = unlist(gv$blocked_by %||% list()),
                     cr = card$overall$verdict %||% NA, cr_vis = card$visible$verdict %||% NA, cr_test = card$test$verdict %||% NA,
                     attr = card$controls$attribution$overall$label %||% NA,
                     attr_vis = card$controls$attribution$visible$label %||% NA, attr_test = card$controls$attribution$test$label %||% NA,
                     ## 성과 수치 = 권위 산출(essence · 일간) — 행동 카드 stats 는 월말 기준이라 섞지 않는다
                     cagr = ar$essence$cagr %||% NA, calmar = ar$essence$calmar %||% NA, mdd = ar$essence$mdd %||% NA,
                     sharpe = ar$essence$net_sharpe %||% NA, port_t = ar$essence$portfolio_alpha_t_nw_lag3 %||% NA,
                     dd_med = card$overall$crisis_dd_capture_median %||% NA, up_med = card$overall$bull_up_capture_median %||% NA,
                     n_crisis = card$overall$n_crisis %||% NA,
                     falsified = isTRUE(rw$rejected), undetermined = isTRUE(rw$undetermined),
                     fal = rw$falsification, card = card, axis = ax, axis_vis = ax_vis, axis_ok = isTRUE(ax$ok))
}
gtxt <- function(x) if (isTRUE(x$axis_ok)) as.character(x$grade) else sprintf("무효(축 위반 · 파일상 %s)", x$grade)
selected <- sel$selected %||% "none"
rvp <- setNames(rv$per_prescription %||% list(), vapply(rv$per_prescription %||% list(), function(z) z$id %||% "", ""))
mech_word <- c(confirmed = "기전 확인", partial = "기전 일부 확인", not_confirmed = "기전 미확인")
pers_word <- c(broad = "여러 위기에 걸침", single_episode = "한 위기에 몰림", none = "개선 없음")
ctl_word <- c(selection = "선택 방어", size = "크기 방어", exposure = "노출 방어", none = "방어 없음")
move_word <- c(deepen = "같은 기전 정교화", combine = "성공 처방 누적", switch = "새 약점 가설", stop = "이 기저 종료(개선이 잡음 이내)")

## ① 라운드 보고서(md)
fal_md <- readLines(file.path(RES, "falsification_visible.md"), warn = FALSE, encoding = "UTF-8")
sel_md <- readLines(file.path(RES, "selection_visible.md"), warn = FALSE, encoding = "UTF-8")
tab <- c("| 대상 | 반증 | Grade | 종합점수 S | 위기 방어(전체 · 보는 창 · 시험 창) | 방어 귀속(전체 · 보는 창 · 시험 창) | CAGR | Calmar | 최대낙폭 | PORT_t | 하락 포착 중앙 | 상승 포착 중앙 |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|")
for (k in names(info)) { x <- info[[k]]
  if (!identical(x$status, "measured")) { tab <- c(tab, sprintf("| %s | 측정 안 됨(%s) | — | — | — | — | — | — | — | — | — | — |", lk(short, k), x$status)); next }
  tab <- c(tab, sprintf("| %s | %s | %s | %s | %s · %s · %s | %s · %s · %s | %s | %s | %s | %s | %s | %s |",
                        lk(short, k), if (!isTRUE(x$axis_ok)) "**축 위반 — 무효(미시험)**" else if (x$control) "대조" else if (x$falsified) "**기각**" else if (x$undetermined) "판정 불가" else "통과",
                        gtxt(x), f2(x$S), prep_verdict_word(x$cr), prep_verdict_word(x$cr_vis), prep_verdict_word(x$cr_test),
                        lbl(x$attr), lbl(x$attr_vis), lbl(x$attr_test), pct(x$cagr), f2(x$calmar), pct(-as.numeric(x$mdd)),
                        f2(x$port_t), f2(x$dd_med), f2(x$up_med))) }
rv_md <- c()
for (k in names(rvp)) { z <- rvp[[k]]
  rv_md <- c(rv_md, sprintf("- **%s** — %s · %s · 대조: %s · 강점 보존 %s", lk(short, k), lk(mech_word, z$mechanism, z$mechanism %||% "—"),
                            lk(pers_word, z$persistence, z$persistence %||% "—"), lk(ctl_word, z$control_beaten, z$control_beaten %||% "—"),
                            if (isTRUE(z$strengths_preserved)) "예" else "아니오"),
            paste0("  - 근거: ", unlist(z$evidence %||% list())), paste0("  - 우려: ", unlist(z$concerns %||% list()))) }
rep_md <- c(sprintf("# %s — 처방 루프 v0 첫 라운드 (%s · arXiv 2002.06975 롱온리 계보) · %s", ROUND, PNAME, format(Sys.Date())), "",
            "> 등급 = `authoritative_remeasure.json::essence_grade`(등급 규칙 v3.1 재채점 후) · 위기 방어 · 귀속 = 전기간 행동 카드(MC8 · 위기 = Lunde-Timmermann 20/20) — 사람 쪽 전기간.",
            "> 반증 · 선택 · 리뷰어 = 보는 창(≤ 2022-12-31) · 사전등록 당시 행동 카드 설정(구 위기 정의)으로 고정(R2).", "",
            "## 요지", "",
            sprintf("- **선정: %s** — %s", if (identical(selected, "none")) "없음" else (lk(short, selected)), sub(" — 선정 없음$", "", sel$reason %||% "—")),
            sprintf("- 리뷰어 다음 수: **%s** — %s", lk(move_word, rv$next_move, rv$next_move %||% "—"), rv$next_move_reasoning %||% "—"),
            if (!is.null(rv$selection_reasoning) && nzchar(rv$selection_reasoning)) sprintf("- 리뷰어 선택 확인: %s", rv$selection_reasoning),
            "", "## 대상별 결과 (전기간 · 사람 쪽)", "", tab, "",
            sprintf("## 축 감사 (처방 · 조립 축 = 롱온리 · ≤ %d종 · 실제 보유 04_holdings 기준)", MAXN), "",
            vapply(names(info), function(k) { x <- info[[k]]; if (is.null(x$axis)) return(sprintf("- %s — 측정 안 됨", lk(short, k)))
              sprintf("- %s — %s · 리밸 %d회 · 최대 %d종 · 평균 %.1f종 · %d종 초과 %d회 · 음수 비중 %d", lk(short, k),
                      if (isTRUE(x$axis_ok)) "준수" else "**위반**", x$axis$n_rebal, x$axis$n_max, x$axis$n_mean, MAXN, x$axis$n_over, x$axis$neg) }, ""), "",
            "## 처방 (사전등록 원문 이름)", "", sprintf("- %s: %s", names(names_rx), names_rx), "",
            fal_md, "", sel_md, "", "## 리뷰어 판독 (보는 창만)", "", rv_md, "",
            "### 다음 가설 (리뷰어)", "", paste0("- ", unlist(rv$next_hypotheses %||% list("—"))), "",
            "### 교훈 (보는 창 수치만)", "", paste0("- ", unlist(rv$lessons %||% list("—"))), "",
            "## 산출물", "", sprintf("- 사전등록 `%s`(md5 %s)", PRE_REL, unname(tools::md5sum(PRE))),
            sprintf("- 결과 `04_Research/programs/%s/%s/results/`(summary_full · falsification_visible · selection_visible · 대상별 visible/full)", PROGRAM, ROUND),
            sprintf("- 리뷰어 `04_Research/programs/%s/%s/lane_reviewer/out.md`", PROGRAM, ROUND))
REP <- file.path(P$prereg_dir, "ROUND_REPORT.md")
writeLines(rep_md, REP, useBytes = TRUE)
cat("report:", REP, "\n")

## ④ 교훈 1건(L-code) — 처방 루프 = v10.01 의 강화 프로세스(mode reinforcement) · 라운드 요약(record_type summary · 등급 없음)
##   ★교훈 카드엔 τ_D 이전 수치만 — 수치는 전부 보는 창 패킷(diagnosis_packet · R 계약)에서 읽는다. 전기간 등급 · 시험 창은 싣지 않는다.
VP <- function(code) fromJSON(file.path(RES, code, "visible", "diagnosis_packet.json"), simplifyVector = TRUE)
pk <- setNames(lapply(c("P2R01_RX0", "P2R01_RX1", "P2R01_RX2", "P2R01_RX3"), function(c) tryCatch(VP(c), error = function(e) NULL)),
               c("RX0", "RX1", "RX2", "RX3"))
v <- function(id, path) { x <- pk[[id]]; for (k in strsplit(path, ".", fixed = TRUE)[[1]]) { if (is.null(x)) return(NA_real_); x <- x[[k]] }
                          suppressWarnings(as.numeric(x))[1] }
vl <- function(id) lbl(pk[[id]]$controls$attribution$label)
lesson <- sprintf(paste0("%s(arXiv 2002.06975 롱온리 각색 · 보는 창 ≤2022-12): 처방 3건 전부 사전등록 반증 기각 · 최종 후보 없음. ",
                         "기저(같은 판본) Calmar %.2f · 위기 하락 포착 중앙 %.2f · 최악 %.2f · 귀속 %s. ",
                         "① %s: 최악 %.2f · Calmar %.2f(위기 중앙 %.2f 개선에도 꼬리 악화). ",
                         "② %s: 측정 무효 — 엔진의 회전 상한이 직전 보유와 목표를 섞고 종목 수 상한을 다시 걸지 않아 보유 최대 %d종(≤%d 축 위반 · 보는 창 리밸 %d회 중 %d회 초과) · 연 회전 %.1f → %.1f(회전도 줄지 않았다) · 처방 검증기에 거부 규칙 추가. ",
                         "③ %s: 위기 중앙 %.2f 불변 · 귀속 %s · 평균 노출 %.2f(2017~20 · 2021~22 위기 개선분은 노출 축소로 설명) · Calmar %.2f. ",
                         "반증 필드 교훈: 위기 4개의 중앙값은 가운데 둘로만 정해진다 — 양 끝 위기만 바꾸는 처방은 중앙값을 못 움직인다(위기별 개선 수 · 최악값과 함께 쓸 것)."),
                  ROUND, v("RX0", "performance.strategy.calmar"), v("RX0", "behavior.summary.crisis_dd_capture_median"),
                  v("RX0", "behavior.summary.crisis_dd_capture_worst"), vl("RX0"),
                  lk(short, "RX1"), v("RX1", "behavior.summary.crisis_dd_capture_worst"), v("RX1", "performance.strategy.calmar"),
                  v("RX1", "behavior.summary.crisis_dd_capture_median"),
                  lk(short, "RX2"), info[["RX2"]]$axis_vis$n_max, MAXN, info[["RX2"]]$axis_vis$n_rebal, info[["RX2"]]$axis_vis$n_over,
                  v("RX0", "profile.turnover_annual"), v("RX2", "profile.turnover_annual"),
                  lk(short, "RX3"), v("RX3", "behavior.summary.crisis_dd_capture_median"), vl("RX3"), v("RX3", "profile.gl_mean"),
                  v("RX3", "performance.strategy.calmar"))
if (length(rv$lessons)) lesson <- paste0(lesson, " 리뷰어: ", paste(unlist(rv$lessons), collapse = " / "))
.rx_assert_clean(lesson, ROOT, "lesson")             # τ_D 뒤 날짜 · 등급 표기가 섞이면 멈춘다(교훈 카드 경계)
cat("lesson_text:", lesson, "\n")
fa <- lapply(setdiff(names(info), "RX0"), function(k) list(test = sprintf("%s — 사전등록 반증 조건(보는 창)", lk(short, k)),
                                                           result = if (isTRUE(info[[k]]$falsified)) "falsified" else "survived"))
nprobe <- unlist(rv$next_hypotheses %||% list())
if (length(nprobe) < 2L) nprobe <- c(nprobe, "반증 필드를 위기별 개선 수 · 최악값으로 등록해 같은 기저를 다시 처방",
                                     "노출 짝을 넘는 선택 방어 기전(종목 선택 축)을 다른 수익 엔진에서 시험")[seq_len(2L - length(nprobe))]
source("02_Infrastructure/axiom/lcode_emit.R")
lc <- emit_lcode(mode = "reinforcement", strategy_id = ROUND, grade = "", lesson_text = lesson,   # 요약형 관례 = 빈 문자열(NULL 은 {} 로 직렬화된다)
                 metric_type = "backtested", record_type = "summary", construction_type = "composite",
                 mechanism_hypothesis = "롱온리 각색판의 위기 손실은 시장 성분(평균 노출 1.00 · 하락장 베타 > 상승장 베타)에서 온다 — 종목 · 비용 · 상태 축 처방 어느 것도 노출 짝을 넘는 선택 방어를 만들지 못했다",
                 falsification_attempts = fa, next_probe = nprobe,
                 source_paper = "https://arxiv.org/abs/2002.06975", project_root = ROOT, dry_run = !RECORD)
cat("lesson:", if (is.list(lc)) lc$l_code else "—", if (RECORD) "(적립)" else "(미리보기)", "\n")

## ② 등록부 기록 — 같은 round_id · 같은 prereg(R2: writer 가 사전등록 변경을 거부)
res_rec <- lapply(info, function(x) if (!identical(x$status, "measured")) list(status = x$status) else
  list(code = x$code, grade = x$grade, S = x$S, rules_version = x$rules, cr = x$cr, cr_test = x$cr_test, attribution = x$attr,
       falsified = x$falsified, undetermined = x$undetermined, artifacts = sub(paste0("^", ROOT, "/"), "", x$artifacts),
       axis = list(ok = isTRUE(x$axis_ok), max_names = MAXN, n_max = x$axis$n_max, n_mean = round(x$axis$n_mean, 1),
                   n_over = x$axis$n_over, n_rebal = x$axis$n_rebal),
       validity = if (isTRUE(x$axis_ok)) "valid" else "invalid_axis_violation"))
if (RECORD) {
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = PRE_REL, status = "complete", results = res_rec,
                                selected = selected, selection_reason = sel$reason %||% NA,
                                reviewer = list(next_move = rv$next_move %||% NA, next_move_reasoning = rv$next_move_reasoning %||% NA,
                                                lessons = rv$lessons %||% list(), next_hypotheses = rv$next_hypotheses %||% list()),
                                report = sub(paste0("^", ROOT, "/"), "", REP), completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
                  root = ROOT)
  cat("registry: round recorded (complete)\n")
  pr_set_status(PROGRAM, "ready",
                sprintf("%s 완료 · %s · 리뷰어 권고 = %s(처방 3 노출 고정판 · 사전등록 지표를 꼬리로) · S2 파일럿 1회전 종료 — 다음 라운드 착수는 도훈 확인",
                        ROUND, if (identical(selected, "none")) "선정 없음" else paste("선정", selected),
                        lk(move_word, rv$next_move, rv$next_move %||% "—")), root = ROOT)
  cat("registry: program status → ready\n")
}

## ③ 보고 1통
base <- info[["RX0"]]
prev <- if (identical(base$status, "measured")) sprintf("같은 판본 기저 Grade %s · 종합점수 S %s · CAGR %s · Calmar %s · 위기 방어 %s · 귀속 %s",
                                                        base$grade, f2(base$S), pct(base$cagr), f2(base$calmar), prep_verdict_word(base$cr),
                                                        lbl(base$attr)) else "기저 재측정 실패"
n_rej <- sum(vapply(info, function(x) !isTRUE(x$control) && isTRUE(x$falsified), logical(1)))
target <- if (identical(selected, "none")) "처방 루프 첫 라운드 — 선정 없음" else sprintf("%s(선정)", lk(short, selected))
card_sel <- if (identical(selected, "none")) NULL else info[[selected]]$card
items <- c()
for (k in setdiff(names(info), "RX0")) { x <- info[[k]]
  items <- c(items, if (!identical(x$status, "measured")) sprintf("%s — 측정 안 됨", lk(short, k)) else
    if (!isTRUE(x$axis_ok)) sprintf("%s — 축 위반: 최대 %d종 · %d종 초과 %d/%d회 → 측정 무효(미시험) · 반증도 기각", lk(short, k),
                                   x$axis$n_max, MAXN, x$axis$n_over, x$axis$n_rebal) else
    sprintf("%s — 반증 %s · Grade %s · S %s · CAGR %s · Calmar %s · 위기 방어 %s · 귀속 %s", lk(short, k),
            if (x$falsified) "기각" else if (x$undetermined) "판정 불가" else "통과", x$grade, f2(x$S), pct(x$cagr), f2(x$calmar),
            prep_verdict_word(x$cr), if (!identical(x$attr, x$attr_vis)) sprintf("%s(보는 창 %s)", lbl(x$attr), lbl(x$attr_vis)) else lbl(x$attr))) }
rv_items <- c()
for (k in names(rvp)) { z <- rvp[[k]]
  rv_items <- c(rv_items, sprintf("%s — %s · %s · 대조 %s", lk(short, k), lk(mech_word, z$mechanism, "—"),
                                  lk(pers_word, z$persistence, "—"), lk(ctl_word, z$control_beaten, "—"))) }
extra <- list(list(type = "bullet", emoji = "🧪", heading = "처방별 결과 (전기간 권위 등급 · 행동 카드)", items = items),
              list(type = "bullet", emoji = "🔎", heading = "리뷰어 판독 (보는 창)", items = rv_items))
disp <- function(t) { t <- gsub("RX0", "기저", t, fixed = TRUE); t <- gsub("RX([1-3])", "처방 \\1", t)
                      t <- gsub("R5 에서", "짝 대조에서", t, fixed = TRUE); gsub("delta 가", "처방 변경이", t, fixed = TRUE) }
if (length(rv$lessons)) extra[[length(extra) + 1L]] <- list(type = "bullet", emoji = "📝", heading = "교훈 (보는 창 · 전문은 보고서)",
                                                           items = disp(sub(" — .*$", "", unlist(rv$lessons))))
n_rx <- length(info) - 1L
n_inv <- sum(vapply(info, function(x) !isTRUE(x$control) && identical(x$status, "measured") && !isTRUE(x$axis_ok), logical(1)))
verdict <- sprintf("%s · 반증 기각 %d/%d%s",
                   if (identical(selected, "none")) "최종 후보 선정 없음" else sprintf("선정 %s(%s)", lk(short, selected), sel$reason %||% ""),
                   n_rej, n_rx, if (n_inv > 0L) sprintf(" · 그중 축 위반(측정 무효) %d", n_inv) else "")
h1 <- disp(sub("\\. .*$", "", unlist(rv$next_hypotheses %||% list(""))[1]))
nxt <- sprintf("리뷰어 권고 = %s — %s · 사전등록 지표는 꼬리(최악 포착 · CDaR · 위기별 포착)로 · S2 파일럿 1회전 종료(다음 단계는 도훈 확인)",
               lk(move_word, rv$next_move, rv$next_move %||% "—"), h1)
CH <- file.path(P$prereg_dir, "charts")
charts <- c("누적 순자산 — 위기 음영(LT 20/20) · 기저 vs 처방 3건 · 점선 = τ_D" = file.path(CH, "cum_nav_crisis.png"),
            "위기별 하락 포착률 — 1 미만 = 시장보다 덜 빠짐(전기간 카드)" = file.path(CH, "crisis_dd_capture.png"))
charts <- charts[file.exists(charts)]
res <- prep_send(program = PNAME, target = target,
                 status = list(stage = "1계층 팩터전략 리서치 — 처방 루프 v0 첫 라운드(파일럿 · 1회전)",
                               position = sprintf("라운드 종료 · 처방 3건 측정 · 반증 기각 %d건 · 리뷰어 판독 완료", n_rej),
                               previous = prev),
                 card = card_sel, verdict_line = verdict, next_step = nxt,
                 artifact = REP, charts = if (length(charts)) charts else NULL, push = TRUE, extra = extra, root = ROOT)
if (is.list(res)) for (k in intersect(c("ok", "bytes", "dry_run"), names(res))) cat(k, "=", format(res[[k]]), "\n")
if (!SEND && is.list(res) && !is.null(res$text)) cat(res$text, "\n")
