## P2R05 등록 전 리허설(P2R04 rehearse.R 형식 · 골격 = 측정 기계 에이전트 C · 판정 구현 API 맞춤 = 판정 구현 에이전트 B 10-18) — 본 판정 함수(evaluate.R)를
##   P2R04 같은 배치 칸 산출 + 합성 구성 증거에 그대로 돌려 새 경로(⑩ 개정 · ⑮ 꼬리 계기 · 진단 · 비교 기준 · 기록 · 유동성 귀속)가 끝까지 무오류로 도는지 증명한다
##   (판정용 아님 · 코드 경로 증명). 판정 함수의 검사는 약화 · 우회하지 않는다 — 구성 증거(⑩)는 합성 입력이 정당하게(실제 측정이 남기는 것과 같은 형식으로) 채운다.
##   함수가 없으면 그 단계 = 실패(error_class not_implemented) → 리허설 실패 → register.R 이 등록을 거부한다(건너뛰어 통과하는 길 없음).
## 합성 재료(읽기만 · 실행 때만 연다 — 요약에는 판정 어휘 · 통과 여부 · 사유 코드 · 걸린 시간만 · 성과 수치 없음):
##   · 셀 산출 = P2R04 같은 배치 칸(새 epoch · 결과 json 의 artifacts 경로)을 리허설 가짜 코드로 복사 — RX0 ← P2R04_E2_RX0 · V2 · V1 · S2 ← P2R04_E2_H2(보유가 RX0 와 다름) ·
##     LV ← P2R04_E2_W2(사양 사본이 같은 칸) · 무처치 대조(NULL) ← RX0 산출 · Q50 자리 ← V 와 같은 산출(V1 = Q50 무처치) 또는 RX0 산출(V1 ≠ Q50 진행)
##   · 사양 = 실제 P2R05 사양(specs/P2R05_E2_*.json — RX0 와 base_signal 만 다름 · 분위 칸 base_signal = 실제 DT 엔진 파일)
##   · 셀 로그 = RX0 · LV 는 P2R04 원 로그 그대로(기저 적재 줄 = RX0 엔진 md5 · months=) · 분위 칸은 합성 — 실제 셀 엔진 형식(기저 적재 줄 = 그 DT 엔진 md5 앞 12자 ·
##     요약 줄 = cell 리허설 코드 · univ · wt · months · rows 는 RX0 원 로그 값 · factors = 사양(E2 = none))
##   · 엔진 핀 = 현재 파일 md5(사전등록이 박을 값과 같은 계산) · 템플릿 차분 대조 = 실제 검사기 실행(평가 때와 같은 호출 p5_template_check)
##   · 분위 예측표 = 합성(RAWDATA · 측정 축 주입 멤버 · 보는 창 월말 신호일만) — 양성 대조 '신탁'(q̂10 = 표본 밖 실현 순위 − 폭 → ⑮ 통과해야) ·
##     음성 대조 '무정보'(q̂10 = τ + 작은 잡음 → ⑮ 미달이어야). ★신탁은 미래 라벨을 쓴다 — 평가기의 양성 대조일 뿐 측정 · 판정 입력이 아니다
##   · 워밍 센티널 = 합성 3종(ok · 캐시 한 달 모자람 · 없음) — ⑩(a) 구성 증거 경로
##   · 측정 묶음 센티널 = 합성(results 사본 자리 · qpred = 리허설 예측표의 저장소 상대 경로 · md5 — warm_engine.R finalize 형식) — R4 가 본 실행과 같은 경로
##     p5_warm_resolve → p5_qpred_bound → p5_tail_block 으로 ⑮ 를 잰다(격리 점검 v2 권고 6 · 미묶임 = unbound · md5 다름 = 평가 중단도 같은 단계)
##   · R10 ⑮ 예측표 셀 로그 대조(격리 점검 v2 필수 1) = 실제 사양(분위 · 평균 · 재시드 · 결합) + 합성 셀 로그(셀 엔진 기저 적재 줄 · DT 엔진 '[DT qpred] path=' 줄 형식) —
##     같음 · E3 · W2 연쇄 · 다른 판본(평가 중단) · 줄 없음(대조 불가 꼬리표)
## 음성 경로는 각자 맞는 사유로 미시험이어야 한다(사유 코드 단정): R3 a 엔진 핀 불일치 · b 무처치(⑩(c) 전달량 0 · 구성 증거 통과) · c 워밍 한 달 모자람 · d 센티널 없음 ·
##   R6 V1 = Q50(무처치 · 구성 증거 통과) — 그리고 같은 칸이 V1 ≠ Q50 이면 끝까지 판정된다(양성 대조)
## 쓰기 = rehearsal/out(끝나면 삭제) · rehearsal/summary.json(schema p2r05_rehearsal_v1 — evaluate · round_rules · rehearse md5 · 단계별 통과 · 판정 어휘 · 사유 코드 · 시간만)
##   칸 평가(p2_eval_cell)의 콘솔 줄(보는 창 UC · DC · CAGR 등 성과 수치)은 리허설 로그에도 싣지 않는다(capture.output 으로 버린다)
## 실행: Rscript rehearse.R   (evaluate.R · round_rules.R 이 생긴 뒤 · 약 5~15분)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py"))) stop("[리허설] 프로젝트 루트 표지 없음: ", ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD_REL <- "04_Research/programs/P2_DEFENSE/P2R05_distribution_target"
RD <- file.path(ROOT, RD_REL)
P4R <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/results")
SUMF <- file.path(RD, "rehearsal", "summary.json"); dir.create(dirname(SUMF), recursive = TRUE, showWarnings = FALSE)
md5f <- function(f) if (file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
## 리허설이 실제로 적재한 판본의 md5 — 적재 전에 잰다(끝에서 재면 실행 중 편집이 기록을 속인다) · 끝에서 다시 재어 바뀌었으면 실패
MD5_AT_LOAD <- vapply(c("evaluate.R", "round_rules.R", "rehearse.R"), function(f) md5f(file.path(RD, f)), character(1))
early_fail <- function(why) {
  writeLines(toJSON(list(schema = "p2r05_rehearsal_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), pass = FALSE, why = why,
                         evaluate_md5 = MD5_AT_LOAD[["evaluate.R"]], round_rules_md5 = MD5_AT_LOAD[["round_rules.R"]], rehearse_md5 = MD5_AT_LOAD[["rehearse.R"]]),
                    auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), SUMF, useBytes = TRUE)
  cat("[리허설] 실패 —", why, "\n"); quit(status = 1L)
}
if (anyNA(MD5_AT_LOAD[c("evaluate.R", "round_rules.R")])) early_fail("evaluate.R · round_rules.R 이 아직 없다(판정 구현 쪽 산출 대기)")
source(file.path(RD, "evaluate.R"))                                             # 도우미만(본 실행 블록은 sys.nframe 가드 — 판정 구현 쪽 계약)
source(file.path(RD, "round_rules.R"))
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
source("02_Infrastructure/contracts/measurement_axis.R")
## 행동 카드 설정 — 사전등록 사본(register 가 만든다)이 있으면 그것 · 없으면 정본을 읽기만(이 리허설은 사본을 만들지 않는다)
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json"); if (!file.exists(BCP)) BCP <- file.path(ROOT, "06_Registry/behavior_card.json")
call_rr <- function(fn) { fm <- names(formals(fn)); ctx <- list(root = ROOT, bcfg_path = BCP, bcp = BCP, bc_path = BCP)
  r <- tryCatch(do.call(fn, ctx[intersect(fm, names(ctx))]), error = function(e) e); if (!inherits(r, "error")) r else fn(ROOT, BCP) }
FS <- call_rr(p2r05_final_selection_rule); TAU <- as.Date(fromJSON(BCP)$tau_d)
TI <- FS$tail_instrument %||% list()
OUTD <- file.path(RD, "rehearsal", "out"); unlink(OUTD, recursive = TRUE); RES <- file.path(OUTD, "results"); dir.create(RES, recursive = TRUE)

## ── NEEDS 표 — 단계가 부르는 evaluate.R 함수(판정 구현 실제 이름 · 10-18 B 맞춤) ────────────────────────────────────────
NEEDS <- list(
  R0 = list(eval_cell = c("p2_eval_cell")),
  R1 = list(eval_pair = c("p5_eval_pair"), tail_gate = c("p5_apply_tail_gate"), warm = c("p5_warm_check"), template = c("p5_template_check")),
  R2 = list(eval_pair = c("p5_eval_pair"), tail_gate = c("p5_apply_tail_gate")),
  R3 = list(eval_pair = c("p5_eval_pair"), warm = c("p5_warm_check")),
  R4 = list(tail_block = c("p5_tail_block"), warm_resolve = c("p5_warm_resolve"), qbound = c("p5_qpred_bound"), ydef = c("p5_ydef_check"), dt_files = c("p5_dt_engine_files"),
            liq_from = c("p5_liq_from"), nw = c("p5_nw_fun"), rel = c("p5_rel")),
  R5 = list(eval_pair = c("p5_eval_pair"), readings = c("p5_readings"), lv_weight = c("p5_lv_expect_weight")),
  R6 = list(eval_pair = c("p5_eval_pair"), tail_gate = c("p5_apply_tail_gate")),
  R7 = list(identity = c("p2_rx0_identity"), identity_core = c("p2_rx0_identity_core"), holdings = c(".p2_read_holdings")),
  R8 = list(verdict = c("p2_round_verdict"), select = c("p2_select"), noise = c("p2_noise_reading"), a_distance = c("p2_a_distance"), visible = c("p2_visible_only")),
  R9 = list(visible = c("p2_visible_only"), conclusion = c("p5_conclusion"), liq_round = c("p5_liq_attr_round"), liq_from = c("p5_liq_from"), liq_for = c("p5_liq_attr_for")),
  R10 = list(qlog = c("p5_qpred_log_check"), warm_resolve = c("p5_warm_resolve"), qbound = c("p5_qpred_bound"), conclusion = c("p5_conclusion"), rel = c("p5_rel")))
fn_of <- function(st, key) { c0 <- NEEDS[[st]][[key]]; h <- c0[vapply(c0, function(n) exists(n, mode = "function"), logical(1))]; if (length(h)) get(h[1], mode = "function") else NULL }
missing_of <- function(st) { m <- names(NEEDS[[st]])[vapply(names(NEEDS[[st]]), function(k) is.null(fn_of(st, k)), logical(1))]
  if (length(m)) paste(vapply(m, function(k) paste(NEEDS[[st]][[k]], collapse = "|"), ""), collapse = " · ") else character(0) }
VOCAB <- if (exists("P2R05_VERDICTS")) get("P2R05_VERDICTS") else character(0)

## ── 합성 재료 ────────────────────────────────────────────────────────────────────
SRC <- c(RX0 = "P2R04_E2_RX0", V2 = "P2R04_E2_H2", LV = "P2R04_E2_W2")
CODE <- c(RX0 = "P2R05_REH_E2_RX0", V2 = "P2R05_REH_E2_V2", V1 = "P2R05_REH_E2_V1", S2 = "P2R05_REH_E2_S2", LV = "P2R05_REH_E2_LV", NULLC = "P2R05_REH_E2_NULL",
          Q50 = "P2R05_REH_E2_Q50")
for (k in names(SRC)) for (ext in c(".json", ".log")) { s <- file.path(P4R, paste0(SRC[[k]], ext)); if (!file.exists(s)) early_fail(paste("재료 없음:", basename(s))) }
cpf <- function(src, code, ext) file.copy(file.path(P4R, paste0(src, ext)), file.path(RES, paste0(code, ext)), overwrite = TRUE)
## 측정 json(ok · artifacts) — 산출은 원 칸 그대로 · RX0 · LV 셀 로그 = 원 로그 그대로(원 칸 이름 = expect_cell · expect_cell_rx0)
invisible(c(cpf(SRC[["RX0"]], CODE[["RX0"]], ".json"), cpf(SRC[["RX0"]], CODE[["RX0"]], ".log"), cpf(SRC[["LV"]], CODE[["LV"]], ".json"), cpf(SRC[["LV"]], CODE[["LV"]], ".log"),
            cpf(SRC[["V2"]], CODE[["V2"]], ".json"), cpf(SRC[["V2"]], CODE[["V1"]], ".json"), cpf(SRC[["V2"]], CODE[["S2"]], ".json"), cpf(SRC[["RX0"]], CODE[["NULLC"]], ".json")))
SP5 <- function(cp) file.path(RD_REL, "specs", sprintf("P2R05_E2_%s.json", cp))
SRX <- p2_parse_cell_log(.p2_read_lines(file.path(RES, paste0(CODE[["RX0"]], ".log"))))
if (!isTRUE(SRX$found)) early_fail("RX0 원 로그에 셀 요약 줄 없음(재료 형식)")
## 분위 칸 셀 로그(합성 · 실제 셀 엔진 형식) — 기저 적재 줄(엔진 md5 앞 12자 = 핀) + 요약 줄(months = RX0 원 로그 — 같은 배치)
eng_of <- function(comp) file.path(P2R05_DT_DIR, P2R05_RULES[[comp]]$engine %||% P2R05_DIAGNOSTICS[[comp]]$engine_file)
syn_log <- function(code, comp) { m <- md5f(file.path(ROOT, eng_of(comp)))
  writeLines(c(sprintf("[rf_cell_engine] 기저 캐시 적중 — base_v2_%s_%s.rds (%d행)", substr(m, 1L, 12L), m, SRX$rows),
               sprintf("[rf_cell_engine] cell=%s | univ=%s | factors=none | wt=%s | months=%d | rows=%d", code, SRX$univ, SRX$wt, SRX$months, SRX$rows)),
             file.path(RES, paste0(code, ".log")), useBytes = TRUE) }
cr <- list(code = CODE[["RX0"]], engine = "E2", component = "RX0", reference = TRUE, path = SP5("RX0"))
cm <- list(code = CODE[["V2"]], engine = "E2", component = "V2", path = SP5("V2"))
c1 <- list(code = CODE[["V1"]], engine = "E2", component = "V1", path = SP5("V1"))
cs <- list(code = CODE[["S2"]], engine = "E2", component = "S2", diagnostic = TRUE, control = "vol_proxy", path = SP5("S2"))
cl <- list(code = CODE[["LV"]], engine = "E2", component = "LV", diagnostic = TRUE, control = "lowvol_screen", path = SP5("LV"))
cn <- list(code = CODE[["NULLC"]], engine = "E2", component = "V2", path = SP5("V2"))
syn_log(cm$code, "V2"); syn_log(c1$code, "V1"); syn_log(cs$code, "S2"); syn_log(cn$code, "V2")
## 합성 분위 예측표 — 보는 창 월말 신호일 × 측정 축 멤버 · 라벨 = 시가 d+1 → 종가 d+5(행 이동 · 합성이라 격자 결측은 근사) · 그날 순위 재척도
qpred_synth <- function(kind, seed = 20261018L) {
  if (!exists(".REH_RAW")) {
    cols <- c("Date", "Ticker", "Open", "Close", "Vol", "K200", "KQ150", "AdminStock", "TradingHalt", "UnfaithfulDisc")
    R <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache", "RAWDATA.parquet"), col_select = tidyselect::all_of(cols)))
    R[, Date := as.Date(Date)]
    R <- ma_inject_universe(R, ma_epoch_by_universe("ALL_HYG", root = ROOT))$RAWDATA
    setorder(R, Ticker, Date)
    R[, lab := shift(Close, 5L, type = "lead") / shift(Open, 1L, type = "lead") - 1, by = Ticker]
    ud <- sort(unique(R$Date)); me <- ud[!duplicated(format(ud, "%Y%m"), fromLast = TRUE)]
    me <- me[me >= as.Date("2005-01-31") & me < as.Date(format(TAU, "%Y-%m-01"))]   # 보는 창 신호일(DESIGN §5 ⑮ — 2005-01-31 ~ 2022-11-30 · 셀 경로 첫 신호 = §2.1)
    assign(".REH_RAW", R[Date %in% me & K200 == 1 & is.finite(lab), .(Date, Ticker, lab)], envir = globalenv())
  }
  Q <- copy(get(".REH_RAW", envir = globalenv()))
  Q[, y := frank(lab, ties.method = "average") / .N, by = Date]
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  set.seed(seed)
  if (identical(kind, "oracle")) { Q[, q10 := pmax(1e-4, y - 0.25)]; Q[, q50 := y]; Q[, q90 := pmin(1, y + 0.25)] }
  else { Q[, q10 := pmin(pmax(1e-4, 0.1 + stats::rnorm(.N, 0, 0.01)), 1)]; Q[, q50 := 0.5]; Q[, q90 := 0.9] }
  Q[, s_perm := q10[sample.int(.N)], by = Date]; Q[, sigma252 := stats::runif(.N)]; Q[, s_sigma := frank(sigma252) / .N, by = Date]   # 짝 점수 열(무정보 합성 · 기록 경로용)
  if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv())   # 전역 난수 상태 복원
  Q[, `:=`(q10_raw = q10, q50_raw = q50, q90_raw = q90)]
  f <- file.path(OUTD, sprintf("qpred_%s.parquet", kind)); arrow::write_parquet(Q[, P2R05_QPRED_COLS, with = FALSE], f)   # 예측표 계약 열 전부(p5_qpred_load 단정)
  list(path = f, QY = Q[, .(Date, Ticker, y, q10, q50, q90)])                  # QY = 라벨(y) 붙은 예측 — ⑮ 함수 입력(판정 구현 p5_tail_instrument 의 QY 형식)
}
warm_synth <- function(kind, path = NULL, qpred = NULL) {                       # ok · partial(한 달 모자람) · missing(파일 없음) — 형식 = warm_engine.R finalize(cache_months = "완료/전체" · qpred{path, md5, bytes, match})
  f <- path %||% file.path(OUTD, sprintf("warm_%s.json", kind)); if (identical(kind, "missing")) return(f)
  n <- 261L; c0 <- if (identical(kind, "partial")) n - 1L else n
  writeLines(toJSON(list(schema = "p2r05_warm_v1", status = "ok", round_id = "P2R05_distribution_target", code_version = "DT_2002_06975/dnn_quantile/rev1",
                         cache_months = sprintf("%d/%d", c0, n), cache_done = c0, cache_total = n, sched_months = n, cache_months_text = sprintf("%d/%d", c0, n),
                         positive_control = list(pass = TRUE), q50 = list(all_cuda = TRUE), reseed = list(status = "ok", cache_months = sprintf("%d/%d", n, n), cache_done = n, cache_total = n),
                         rx0 = list(status = "ok"), qpred = qpred, note = "리허설 합성 센티널(측정 아님)"), auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
  f
}
QS <- list(oracle = qpred_synth("oracle"), null = qpred_synth("null")); QP <- lapply(QS, function(z) z$path)
WS <- list(ok = warm_synth("ok"), partial = warm_synth("partial"), missing = warm_synth("missing"))
## ── 판정 맥락(⑩ · ⑮) — 엔진 핀 = 현재 md5 · 템플릿 차분 대조 = 실제 검사기 · 워밍 = 합성 센티널 · ⑮ = 신탁 예측표 계기(본 실행처럼 시험 조건 문 입력)
PINS <- lapply(c(P2R05_RX0_ENGINE, eng_of("V1"), eng_of("V2"), eng_of("S2")), function(p) list(path = p, md5 = md5f(file.path(ROOT, p))))
PINS_BAD <- lapply(PINS, function(z) if (grepl("engine_V2[.]R$", z$path)) list(path = z$path, md5 = strrep("0", 32L)) else z)   # R3 a — V2 엔진 핀만 어긋남
TEMPL <- if (exists("p5_template_check", mode = "function")) p5_template_check(ROOT) else list(ok = FALSE, status = "not_implemented")
ctx_of <- function(warm = WS$ok, pins = PINS) list(pre = list(operational_pins = list(files = pins)), root = ROOT, warm = p5_warm_check(warm), template = TEMPL,
                                                   tail_d = list(status = "rehearsal"))
NWF <- if (exists("p5_nw_fun", mode = "function")) p5_nw_fun(ROOT) else NULL
TIo <- if (!is.null(NWF) && exists("p5_tail_instrument", mode = "function")) p5_tail_instrument(QS$oracle$QY, TI, NWF) else list(status = "unmeasured", pass = FALSE)
opj <- function(ctx = ctx_of(), ...) c(list(role = "judge", ctx = ctx, tail_ok = isTRUE(TIo$pass), tail = TIo, expect_cell_rx0 = SRC[["RX0"]]), list(...))        # 본 실행 판정 칸 opts 와 같은 이름
opd <- function(ctx = ctx_of(), ...) c(list(role = "diagnostic", ctx = ctx, tail_ok = isTRUE(TIo$pass), tail = TIo, expect_cell_rx0 = SRC[["RX0"]]), list(...))   # 진단 · 비교 기준 칸
LVW <- if (exists("p5_lv_expect_weight", mode = "function")) p5_lv_expect_weight(list(list(engine = "E3", component = "RX0", path = file.path(RD_REL, "specs", "P2R05_E3_RX0.json"))), ROOT) else NA_real_
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCP); env$raw <- NULL; env$liq <- NULL
X <- list(root = ROOT, res = RES, out = OUTD, env = env, fs = FS, tau = TAU, ea = new.env())
t0 <- Sys.time(); S <- list(); OBJ <- list()
lg <- function(nm, s) cat(sprintf("[리허설] %s — %s · %s초%s\n", nm, if (isTRUE(s$pass)) "통과" else "실패", format(s$seconds),
                                  if (identical(s$error_class, "not_implemented")) paste0(" · 미구현: ", s$missing) else ""))
lgl1 <- function(v) is.logical(v) && length(v) == 1L && !is.na(v)
## 사유 코드 — 순서대로 첫 일치(구체 사유가 일반 사유보다 앞) · 판정 구현의 why 문구에서
why_code <- function(w) { if (is.null(w) || !length(w) || is.na(w[1])) return(NA_character_)
  pats <- c(engine_pin = "엔진 핀", warm_missing = "워밍 센티널 없음", warm_incomplete = "분위 캐시 ", template = "템플릿 차분 대조", no_treatment_q50 = "무처치(⑩ V1 = Q50)",
            no_treatment_rx0 = "무처치(⑩) —", construction_evidence = "구성 증거", tail_instrument = "꼬리 계기", eval_status = "평가 상태", inputs_na = "판정 입력 NA")
  h <- names(pats)[vapply(pats, function(p) grepl(p, w[1], fixed = TRUE), logical(1))]; if (length(h)) h[1] else "other" }
stage <- function(nm, st, fn) { t1 <- Sys.time()
  miss <- missing_of(st)
  r <- if (length(miss)) list(pass = FALSE, error_class = "not_implemented", missing = miss)
       else tryCatch(fn(), error = function(e) list(pass = FALSE, error_class = "stage_error", error = conditionMessage(e)))
  r$seconds <- round(as.numeric(difftime(Sys.time(), t1, units = "secs"))); S[[nm]] <<- r[setdiff(names(r), "error")]
  if (!is.null(r$error)) cat(sprintf("[리허설] %s — 단계 오류: %s\n", nm, if (exists(".p2_redact_chr")) .p2_redact_chr(r$error, TAU) else "(가림 함수 없음 — 문구 미표시)"))
  lg(nm, r); invisible(r) }
vshape <- function(o, extra = list()) {                                         # 판정 객체의 공통 모양(판정 구현 필드 이름)
  chk <- c(tested_flag = lgl1(o$tested), verdict_in_vocab = !length(VOCAB) || isTRUE(o$verdict %in% VOCAB), verdict_name = !is.null(o$verdict_name),
           construction_recorded = !is.null(o$construction), tail_gate_recorded = !is.null(o$tail_gate))
  c(list(pass = all(chk) && all(unlist(extra)), checks = as.list(c(chk, unlist(extra))), verdict = o$verdict %||% NA_character_, why_code = why_code(o$why %||% NA_character_)))
}
quiet <- function(expr) { v <- NULL; invisible(utils::capture.output(v <- expr)); v }   # 칸 평가 콘솔 줄(성과 수치)을 로그에 남기지 않는다
cpdir <- function(from, to) { dir.create(file.path(RES, to), recursive = TRUE, showWarnings = FALSE)       # 같은 산출 = 같은 보는 창 패킷(칸 평가 사본)
  invisible(file.copy(file.path(RES, from, c("visible", "full")), file.path(RES, to), recursive = TRUE)) }

## R0 — 칸 평가 분리 저장(보는 창 / 사람 쪽 · 열람 금지 표식 · 실효 시작) · 같은 산출 칸(V1 · S2 ← V2 · NULL · Q50 ← RX0)은 패킷 사본
stage("R0_cell_eval", "R0", function() { f <- fn_of("R0", "eval_cell")
  em <- quiet(f(ROOT, RES, cm, env, TAU)); er <- quiet(f(ROOT, RES, cr, env, TAU)); el <- quiet(f(ROOT, RES, cl, env, TAU)); OBJ$em <<- em; OBJ$er <<- er; OBJ$el <<- el
  cpdir(cm$code, c1$code); cpdir(cm$code, cs$code); cpdir(cr$code, cn$code); cpdir(cr$code, CODE[["Q50"]])
  fv <- file.path(RES, cm$code, "visible"); ff <- file.path(RES, cm$code, "full")
  chk <- c(status_evaluated = all(vapply(list(em, er, el), function(z) identical(z$status, "evaluated"), logical(1))), visible_dir = dir.exists(fv), full_dir = dir.exists(ff),
           marker = file.exists(file.path(ff, "NO_VISIBLE_REVIEW.txt")), effective_start_ok = identical(em$effective_start$status, "ok"),
           packet_copies = all(file.exists(file.path(RES, c(c1$code, cs$code, cn$code, CODE[["Q50"]]), "visible", "diagnosis_packet.json"))),
           visible_packet_dates_le_tau = !file.exists(file.path(fv, "diagnosis_packet.json")) ||
             !length(dp_scan_dates(fromJSON(file.path(fv, "diagnosis_packet.json"), simplifyVector = FALSE)[c("window", "behavior")], TAU)))
  list(pass = all(chk), checks = as.list(chk), status = list(V2 = em$status, RX0 = er$status, LV = el$status)) })
## R1 — 원 창 판정(⑩ (a) 엔진 핀 ∧ 사양 구성 키 ∧ 셀 로그 ∧ 기저 적재 줄 ∧ 워밍 (b) 템플릿 차분 대조 ∧ months= (c) 전달량 (d) 교차율 기록 · ①~⑭ · ⑮ 시험 조건 문 · 기록)
stage("R1_original_window", "R1", function() { f <- fn_of("R1", "eval_pair"); g <- fn_of("R1", "tail_gate")
  o <- g(f(X, "E2", "V2", cm, cr, OBJ$em, OBJ$er, opts = opj()), TIo); OBJ$R1 <<- o
  vshape(o, list(rules_computed = isTRUE(o$rules_computed), tested = isTRUE(o$tested), construction_ok = isTRUE(o$construction$ok),
                 holdings_differ = isTRUE(o$holdings_overlap$n_differ > 0L), warm_ok = identical(o$construction$warm$status, "ok"),
                 template_ok = identical(o$construction$template$status, "ok"), tail_gate_pass = isTRUE(o$tail_gate$pass))) })
## R2 — 공통 창 강제(RX0 첫 수익일 + 1개월) · β 짝 k 0.9 강제
stage("R2_common_window_forced_k", "R2", function() { f <- fn_of("R2", "eval_pair"); g <- fn_of("R2", "tail_gate")
  first_ret <- min(as.Date(fread(file.path(env$E$ta_resolve_artifact(OBJ$er$artifacts)$dir, "03_period_returns.csv"))$date))
  fs <- seq(first_ret, by = "month", length.out = 2L)[2]; OBJ$fs <<- fs
  o <- g(f(X, "E2", "V2", cm, cr, OBJ$em, OBJ$er, opts = opj(force_start = fs, force_k = 0.9)), TIo); OBJ$R2 <<- o
  vshape(o, list(rules_computed = isTRUE(o$rules_computed), window_common = identical(o$window, paste0("common_from_", format(fs))), k_forced = isTRUE(o$rules$beta_deep$k_forced))) })
## R3 — 미시험 경로(사유 코드 단정): (a) 엔진 md5 ≠ 핀 (b) 무처치(변형 = RX0 산출 · 구성 증거는 통과) (c) 워밍 캐시 한 달 모자람 (d) 워밍 센티널 없음
stage("R3_untested_paths", "R3", function() { f <- fn_of("R3", "eval_pair")
  oa <- f(X, "E2", "V2", cm, cr, OBJ$em, OBJ$er, opts = opj(ctx = ctx_of(pins = PINS_BAD)))
  em_null <- list(code = CODE[["NULLC"]], status = OBJ$er$status, artifacts = OBJ$er$artifacts, effective_start = OBJ$er$effective_start)
  ob <- f(X, "E2", "V2", cn, cr, em_null, OBJ$er, opts = opj())
  oc <- f(X, "E2", "V2", cm, cr, OBJ$em, OBJ$er, opts = opj(ctx = ctx_of(warm = WS$partial)))
  od <- f(X, "E2", "V2", cm, cr, OBJ$em, OBJ$er, opts = opj(ctx = ctx_of(warm = WS$missing)))
  rs <- list(a = why_code(oa$why), b = why_code(ob$why), c = why_code(oc$why), d = why_code(od$why))
  chk <- c(a_engine_pin = !isTRUE(oa$tested) && identical(rs$a, "engine_pin"),
           b_no_treatment = !isTRUE(ob$tested) && identical(rs$b, "no_treatment_rx0") && isTRUE(ob$construction$ok),
           c_warm_partial = !isTRUE(oc$tested) && identical(rs$c, "warm_incomplete"), d_warm_missing = !isTRUE(od$tested) && identical(rs$d, "warm_missing"))
  list(pass = all(chk), checks = as.list(chk), verdicts = list(a = oa$verdict, b = ob$verdict, c = oc$verdict, d = od$verdict), reasons = rs) })
## R4 — ⑮ 꼬리 계기 · 측정 묶음 경로(격리 점검 v2 권고 6 — 본 실행과 같은 호출): 합성 센티널(results 사본 자리 · qpred = 리허설 예측표 저장소 상대 경로 · md5) →
##   p5_warm_resolve(night_state 판 없음) → p5_qpred_bound(묶인 판 1개 · 같은 폴더 다른 판 = 기록만) → p5_tail_block(보는 창 RAW · 실제 DT 엔진 표적 정의 · 정본 NW · 사양 PRM) —
##   신탁 = ⑮ 통과 · 무정보 = ⑮ 미달(양성 · 음성 대조) · qpred 필드 없음 = unbound(⑮ 미측정) · md5 다름 = 평가 중단(사유 단정)
qrec <- function(f) list(path = fn_of("R4", "rel")(gsub("\\\\", "/", f), ROOT), md5 = md5f(f), bytes = file.size(f), match = TRUE)
bind_dir <- function(nm, qp) { d <- file.path(OUTD, nm); dir.create(d, recursive = TRUE, showWarnings = FALSE); warm_synth("ok", path = file.path(d, "warm_sentinel.json"), qpred = qp); d }
NO_NIGHT <- file.path(OUTD, "no_night_state.done")                               # night_state 판 없음 — 측정 묶음 사본만 읽힌다
stage("R4_tail_bound_path", "R4", function() {
  wr <- fn_of("R4", "warm_resolve"); qb <- fn_of("R4", "qbound"); tb <- fn_of("R4", "tail_block"); nw <- fn_of("R4", "nw")(ROOT)
  YD <- fn_of("R4", "ydef")(fn_of("R4", "dt_files")(list(c1, cm, cs), ROOT), ROOT)
  sv1 <- fromJSON(file.path(ROOT, SP5("V1")), simplifyVector = FALSE)
  RAWV <- p5_visible_cut(local({ R <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache", "RAWDATA.parquet"), col_select = tidyselect::all_of(c("Date", "Ticker", "Open", "Close", "Vol", "Size"))))
                                 if (!inherits(R$Date, "Date")) R[, Date := as.Date(Date)]; R[, Ticker := as.character(Ticker)]; R }), TAU)
  PRM <- list(veto_share = YD$veto_share, n_max = as.integer(sv1$fixed_axes$n_max %||% NA), liq_min = as.numeric(sv1$fixed_axes$liq_adv20_min %||% NA), n_bins = YD$quint,
              liq = fn_of("R4", "liq_from")(RAWV))                                 # 본 실행 PRM 과 같은 출처(V1 사양 fixed_axes · 표적 정의)
  run <- function(kind) { W <- wr(bind_dir(paste0("bind_", kind), qrec(QP[[kind]])), NO_NIGHT); Q <- qb(ROOT, W, TAU, qdir = OUTD)
    list(W = W, Q = Q, T = if (identical(Q$status, "ok")) quiet(tb(Q$Qv, RAWV, YD, TI, nw, PRM, character(0), "visible")) else NULL) }
  po <- run("oracle"); ne <- run("null")
  un <- qb(ROOT, wr(bind_dir("bind_unbound", NULL), NO_NIGHT), TAU, qdir = OUTD)
  bad <- qrec(QP$oracle); bad$md5 <- strrep("0", 32L)
  hm <- tryCatch({ qb(ROOT, wr(bind_dir("bind_md5", bad), NO_NIGHT), TAU, qdir = OUTD); "no_halt" }, p5_halt = function(e) e$reason)
  rm(RAWV); invisible(gc(FALSE))
  pi <- po$T$instrument %||% list(); ni <- ne$T$instrument %||% list()
  chk <- c(ydef_ok = isTRUE(YD$ok), sentinel_from_bound_copy = identical(po$W$source, "results/warm_sentinel.json") && identical(po$W$status, "ok"),
           bound_one_file = identical(po$Q$status, "ok") && identical(po$Q$n_files, 1L) && identical(po$Q$bound$path, qrec(QP$oracle)$path) && identical(po$Q$n_other, 1L),
           oracle_passes = isTRUE(pi$pass), null_fails = identical(pi$status, "ok") && identical(ni$status, "ok") && !isTRUE(ni$pass),
           t_recorded = is.finite(suppressWarnings(as.numeric(pi$t %||% NA))), window_le_tau = !length(dp_scan_dates(list(window = pi$window), TAU)),
           records_present = is.list(po$T$records) && !is.null(po$T$records$d_sigma) && !is.null(po$T$records$transfer),
           unbound_unmeasured = identical(un$status, "unbound"), md5_mismatch_halts = identical(hm, "예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred.md5)"),
           names_unique = !anyDuplicated(names(pi)) && !anyDuplicated(names(ni)))
  list(pass = all(chk), checks = as.list(chk), status = list(oracle = pi$status %||% NA_character_, null = ni$status %||% NA_character_, unbound = un$status, md5_mismatch = hm)) })
## R5 — 진단(S2 · 변동성 순위 대응 짝) · 비교 기준(LV · P2R04 ⑩ 형식) — 판정 표 밖 · 끝까지 판정 · 진단 읽기 묶음
stage("R5_diagnostic_and_comparison", "R5", function() { f <- fn_of("R5", "eval_pair"); rd <- fn_of("R5", "readings")
  od <- f(X, "E2", "S2", cs, cr, OBJ$em, OBJ$er, opts = opd())
  ol <- f(X, "E2", "LV", cl, cr, OBJ$el, OBJ$er, opts = opd(expect_cell = SRC[["LV"]], expect_weight = LVW))
  OBJ$R5 <<- list(od = od, ol = ol)
  rr <- tryCatch(rd(list(OBJ$R1), list(od, ol), as.numeric(FS$crisis_improve_min), list(ok = NA), as.numeric(TI$t_min %||% NA)), error = function(e) e)
  chk <- c(diag_role = identical(od$role, "diagnostic"), diag_computed = isTRUE(od$rules_computed), cmp_role = identical(ol$role, "diagnostic"),
           cmp_computed = isTRUE(ol$rules_computed), cmp_flavor = identical(ol$construction$flavor, "lowvol_screen"),
           readings_ok = !inherits(rr, "error") && is.list(rr$per_rule) && !is.null(rr$lowvol$E2))
  list(pass = all(chk), checks = as.list(chk), verdicts = list(S2 = od$verdict, LV = ol$verdict), reasons = list(S2 = why_code(od$why %||% NA), LV = why_code(ol$why %||% NA))) })
## R6 — V1 전달량: Q50 자리에 V 와 같은 산출 = 무처치(⑩ V1 = Q50 · 구성 증거 통과) · Q50 자리에 RX0 산출 = 전달 → 끝까지 판정(같은 추첨 판독 기록)
stage("R6_v1_delivery_vs_q50", "R6", function() { f <- fn_of("R6", "eval_pair"); g <- fn_of("R6", "tail_gate")
  dq <- function(a) list(status = "ok", dir = env$E$ta_resolve_artifact(a)$dir, cell = CODE[["Q50"]], path = SP5("Q50"))
  os <- f(X, "E2", "V1", c1, cr, OBJ$em, OBJ$er, opts = opj(q50 = dq(OBJ$em$artifacts)))
  odf <- g(f(X, "E2", "V1", c1, cr, OBJ$em, OBJ$er, opts = opj(q50 = dq(OBJ$er$artifacts))), TIo)
  chk <- c(same_untested = !isTRUE(os$tested) && identical(why_code(os$why), "no_treatment_q50") && isTRUE(os$construction$ok),
           differ_delivered = identical(odf$delivery_q50$status, "ok"), differ_computed = isTRUE(odf$rules_computed), same_draw_recorded = !is.null(odf$same_draw$status))
  list(pass = all(chk), checks = as.list(chk), verdicts = list(same = os$verdict, differ = odf$verdict), reasons = list(same = why_code(os$why), differ = why_code(odf$why %||% NA)),
       same_draw = odf$same_draw$status %||% NA_character_) })
## R7 — RX0 동일성(P2R04 RX0 대비 · 같은 산출을 가리키므로 '같음' 기대 — 판본이 다르면 '다름'도 정상) · 자기 자신 = 같음(양성 대조)
stage("R7_rx0_identity", "R7", function() { fi <- fn_of("R7", "identity"); fc <- fn_of("R7", "identity_core"); rh <- fn_of("R7", "holdings")
  d <- env$E$ta_resolve_artifact(OBJ$er$artifacts)$dir; rp <- function(x) { y <- fread(file.path(x, "03_period_returns.csv")); y[, date := as.Date(date)]; y }
  self <- fc(rh(d), rh(d), rp(d), rp(d), TAU)
  ri <- fi(X, OBJ$er$artifacts, file.path(P4R, "P2R04_E2_RX0.json"))
  chk <- c(status_ok = identical(ri$status, "ok"), self_same = isTRUE(self$holdings_same) && isTRUE(self$returns_same))
  list(pass = all(chk), checks = as.list(chk)) })
## R8 — 라운드 도우미(판정 표 · 선택 · R7 판독 · A 거리) + 보는 창 직렬화 · τ_D 이후 날짜 전수 검사(가림 뒤 0)
stage("R8_round_helpers_and_visible_file", "R8", function() {
  o1 <- OBJ$R1; o2 <- OBJ$R2; o2$engine <- "E3"
  TB <- rbindlist(list(o1$tbl, copy(o2$tbl)[, engine := "E3"]), use.names = TRUE, fill = TRUE)
  rv <- fn_of("R8", "verdict")(TB)
  sel <- fn_of("R8", "select")(setNames(lapply(rv$both %||% character(0), function(dv) list(o1, o2)), rv$both %||% character(0)))
  nr <- fn_of("R8", "noise")(list(o1, o2), rv$both %||% character(0), FS$tie_eps, FS$majority_share)
  vis <- fn_of("R8", "visible")
  VIS <- list(cells = lapply(list(o1, o2, OBJ$R5$od, OBJ$R5$ol), vis, tau = TAU), table = TB, noise = nr)
  tf <- file.path(OUTD, "vis_test.json"); writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tf, useBytes = TRUE)
  back <- fromJSON(tf, simplifyVector = FALSE)
  chk <- c(verdict_vocab = isTRUE(rv$verdict %in% c("supported", "partial", "falsified", "untested")), select_shape = is.list(sel) || is.null(sel),
           noise_logical = is.logical(nr$result) && length(nr$result) == 1L, json_roundtrip = length(back$cells) == 4L, no_dates_after_tau = !length(dp_scan_dates(back, TAU)))
  list(pass = all(chk), checks = as.list(chk), round_verdict = rv$verdict) })
## R9 — 기록 경로(위기 유형 입력 · 판정 여유 · Dimson · 같은 추첨 · 크기 × β · 유동성 십분위 · 결론 이름) + 유동성 구간별 위기 손익 귀속(철학 P4 C-076) —
##   실제 측정 산출(보유 04 · 계약 03 ret_gross)로 재구성 대조(분위 합 = 구간 손익 = 03 구간 합 · |차| < 1e-10) · 모양 · τ_D 이후 날짜 0 만 본다(수치는 요약에 싣지 않는다)
stage("R9_records", "R9", function() {
  o <- OBJ$R1; rec <- o$record %||% list(); vis <- fn_of("R9", "visible")(o, TAU)
  RAWV <- p5_visible_cut(local({ R <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache", "RAWDATA.parquet"), col_select = tidyselect::all_of(c("Date", "Ticker", "Close", "Vol", "Ret"))))
                                 if (!inherits(R$Date, "Date")) R[, Date := as.Date(Date)]; R[, Ticker := as.character(Ticker)]; R }), TAU)
  env$liq <- fn_of("R9", "liq_from")(RAWV)
  LQ <- fn_of("R9", "liq_round")(X, setNames(list(OBJ$er, OBJ$em), c(cr$code, cm$code)), list(cr, cm), "E2", RAWV, FS, TAU); rm(RAWV); invisible(gc(FALSE))
  L <- LQ$E2; pcs <- unlist(lapply(L$per_cell %||% list(), function(z) lapply(z$per_crisis %||% list(), function(a) a)), recursive = FALSE)
  la <- fn_of("R9", "liq_for")(LQ, "E2", "V2"); cn5 <- fn_of("R9", "conclusion")(c(o, list(liq_attr = la)), NULL, NULL)
  chk <- c(record_present = is.list(rec) && length(rec) > 0L, visible_no_dates_after_tau = !length(dp_scan_dates(vis$record %||% list(), TAU)),
           record_keys_core = all(c("state_unturned_max_drop", "size_decile", "rolling") %in% names(rec)), margins_present = is.list(o$margins),
           liq_status_ok = identical(L$status, "ok"), liq_cells_ok = length(L$per_cell) == 2L && all(vapply(L$per_cell, function(z) identical(z$status, "ok"), logical(1))),
           liq_crises_present = length(pcs) > 0L, liq_all_measured = length(pcs) > 0L && all(vapply(pcs, function(a) identical(a$status, "ok"), logical(1))),
           liq_recon_all = length(pcs) > 0L && all(vapply(pcs, function(a) isTRUE(a$recon_ok), logical(1))),
           liq_identity_all = length(pcs) > 0L && all(vapply(pcs, function(a) isTRUE(abs(a$sum_terciles - a$total) < 1e-12), logical(1))),
           liq_improvement_ok = identical(la$status, "ok"), liq_visible_no_dates = !length(dp_scan_dates(p2_redact_after_tau(L[setdiff(names(L), "per_cell")], TAU), TAU)),
           conclusion_ok = is.character(cn5$name) && length(cn5$name) == 1L && is.character(cn5$tags))
  list(pass = all(chk), checks = as.list(chk), record_keys = as.list(utils::head(names(rec), 40L)), liq_tags_kind = as.list(sub("\\(.*$", "", unlist(la$tags %||% list())))) })

## R10 — ⑮ 예측표 셀 로그 대조(격리 점검 v2 필수 1 · 권고 6) — 실제 사양(분위 엔진 V1 · V2 · Q50 · 결합 W2 · 평균 엔진 RX0 · LV · 재시드 RX0S · E3 V1 · V2) +
##   합성 셀 로그(셀 엔진 기저 적재 줄 = 실제 엔진 md5 · DT 엔진 '[DT qpred] path=' 줄) — 같음(E2 V1 · V2 실행) · 연쇄(E3 V1 · V2 · W2 = 같은 기저 캐시) · 재시드 짝 대상 밖 ·
##   출처 없음(Q50) = 대조 불가 꼬리표 · 다른 판본 = 평가 중단 · 모두 적중 = 전부 대조 불가 · 결론 꼬리표(R1 판정 객체)
stage("R10_qpred_cell_logs", "R10", function() {
  qc <- fn_of("R10", "qlog"); W <- fn_of("R10", "warm_resolve")(bind_dir("bind_r10", qrec(QP$oracle)), NO_NIGHT)
  B <- fn_of("R10", "qbound")(ROOT, W, TAU, qdir = OUTD)$bound
  m <- function(pth) md5f(file.path(ROOT, pth)); cf <- function(pth) sprintf("base_v2_%s_%s.rds", substr(m(pth), 1L, 12L), m(pth))
  hit <- function(pth) sprintf("[rf_cell_engine] 기저 캐시 적중 — %s (%d행)", cf(pth), SRX$rows)
  run <- function(pth) sprintf("[rf_cell_engine] 기저 캐시 미스 — 엔진 실행: %s [absent · %s]", basename(pth), cf(pth))
  ql <- function(f) sprintf("[DT qpred] path=%s rows=%d months=%d", gsub("\\\\", "/", f), nrow(QS$oracle$QY), uniqueN(QS$oracle$QY$Date))
  rx <- P2R05_RX0_ENGINE; v1 <- eng_of("V1"); v2 <- eng_of("V2"); q5 <- eng_of("Q50")
  E3P <- function(cp) file.path(RD_REL, "specs", sprintf("P2R05_E3_%s.json", cp))
  CL <- lapply(list(c("E2", "RX0"), c("E2", "RX0S"), c("E2", "V1"), c("E2", "V2"), c("E2", "Q50"), c("E2", "W2"), c("E2", "LV"), c("E3", "V1"), c("E3", "V2")),
               function(z) list(code = sprintf("R10_%s_%s", z[1], z[2]), engine = z[1], component = z[2], path = if (z[1] == "E2") SP5(z[2]) else E3P(z[2])))
  wl <- function(nm, logs) { d <- file.path(OUTD, nm); dir.create(d, showWarnings = FALSE); for (cd in names(logs)) writeLines(logs[[cd]], file.path(d, paste0(cd, ".log")), useBytes = TRUE); d }
  same <- list(R10_E2_RX0 = hit(rx), R10_E2_RX0S = ql(QP$null), R10_E2_V1 = c(run(v1), ql(B$abs)), R10_E2_V2 = c(run(v2), ql(B$abs)), R10_E2_Q50 = hit(q5),
               R10_E2_W2 = c(hit(rx), hit(v2), sprintf("[rf_cell_engine] engine_blend 2개 — 공통 %d행 (%s + %s)", SRX$rows, basename(rx), basename(v2))),
               R10_E2_LV = hit(rx), R10_E3_V1 = hit(v1), R10_E3_V2 = hit(v2))
  differ <- modifyList(same, list(R10_E2_V1 = c(run(v1), ql(QP$null))))
  nolines <- modifyList(same, list(R10_E2_V1 = hit(v1), R10_E2_V2 = hit(v2)))
  st <- function(z) setNames(as.list(z$per_cell$status), z$per_cell$code)
  a <- qc(CL, wl("r10_same", same), ROOT, B); n <- qc(CL, wl("r10_nolines", nolines), ROOT, B)
  hd <- tryCatch({ qc(CL, wl("r10_differ", differ), ROOT, B); "no_halt" }, p5_halt = function(e) e$reason)
  sa <- st(a); sn <- st(n)
  cz <- fn_of("R10", "conclusion"); tg <- "⑮ 예측표 셀 로그 대조 불가(셀 로그 예측표 줄 없음 · 기저 캐시 출처 미확인)"
  chk <- c(same_ok = identical(a$status, "ok"), targets_dt_only = setequal(names(sa), c("R10_E2_V1", "R10_E2_V2", "R10_E2_Q50", "R10_E2_W2", "R10_E3_V1", "R10_E3_V2")),
           same_match = identical(sa$R10_E2_V1, "match") && identical(sa$R10_E2_V2, "match"),
           chained = identical(sa$R10_E3_V1, "chained") && identical(sa$R10_E3_V2, "chained") && identical(sa$R10_E2_W2, "chained"),
           q50_unverifiable = identical(sa$R10_E2_Q50, "unverifiable") && isTRUE(a$n_unverifiable == 1L) && grepl("대조 불가 1칸", a$tag %||% "", fixed = TRUE),
           differ_halts = identical(hd, "셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)"),
           nolines_unverifiable = identical(n$status, "ok") && all(unlist(sn) == "unverifiable"),
           conclusion_tag = tg %in% cz(c(OBJ$R1, list(qpred_log = list(status = "unverifiable"))), NULL, NULL)$tags &&
             !(tg %in% cz(c(OBJ$R1, list(qpred_log = list(status = "chained"))), NULL, NULL)$tags))
  list(pass = all(chk), checks = as.list(chk), status = list(same = sa, nolines = sn, differ = hd)) })

MD5_AT_END <- vapply(names(MD5_AT_LOAD), function(f) md5f(file.path(RD, f)), character(1))
unchanged <- identical(unname(MD5_AT_LOAD), unname(MD5_AT_END))
if (!unchanged) cat("[리허설] 실행 중 evaluate.R · round_rules.R · rehearse.R 가 바뀌었다 — 이 리허설은 무효(다시 돌린다)\n")
pass <- all(vapply(S, function(s) isTRUE(s$pass), logical(1))) && unchanged
res <- list(schema = "p2r05_rehearsal_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), evaluate_md5 = MD5_AT_LOAD[["evaluate.R"]],
            round_rules_md5 = MD5_AT_LOAD[["round_rules.R"]], rehearse_md5 = MD5_AT_LOAD[["rehearse.R"]], files_unchanged_during_run = unchanged,
            behavior_card_cfg = sub(paste0("^", ROOT, "/"), "", BCP), skeleton_version = 2L, needs = NEEDS,
            inputs = list(materials = as.list(SRC), fake_codes = unname(CODE), forced_start = format(OBJ$fs %||% as.Date(NA)), forced_k = 0.9,
                          specs = "실제 P2R05 사양(specs/P2R05_E2_{RX0,V1,V2,S2,LV,Q50}.json)",
                          synthetic = list(qpred = c("oracle(표본 밖 실현 순위 − 폭 · ⑮ 양성 대조)", "null(τ + 잡음 · ⑮ 음성 대조)"), warm_sentinel = c("ok", "partial(한 달 모자람)", "missing"),
                                           bound_sentinel = "측정 묶음 사본 자리(results/warm_sentinel.json) · qpred = 리허설 예측표 저장소 상대 경로 · md5(R4 · R10) · 미묶임 · md5 0(R4 음성)",
                                           cell_logs_r10 = "실제 사양 9칸(E2 RX0 · RX0S · V1 · V2 · Q50 · W2 · LV · E3 V1 · V2) + 합성 셀 로그(기저 적재 줄 = 실제 엔진 md5 · '[DT qpred] path=' 줄)",
                                           cell_logs = "분위 칸(V1 · V2 · S2 · NULL) 셀 로그 = 실제 셀 엔진 형식(기저 적재 줄 = DT 엔진 md5 · months = RX0 원 로그)",
                                           pins = "엔진 핀 = 현재 파일 md5(R3 a = V2 엔진 핀만 0)", template_check = "실제 검사기 실행"),
                          note = paste0("P2R04 같은 배치 칸(E2 RX0 · E2 저변동 틸트 H2 · E2 용량 짝 W2 = LV 사양 사본)을 가짜 코드로 묶은 코드 경로 증명 + 합성 분위 예측표 · 합성 워밍 센티널 · ",
                                        "합성 분위 칸 셀 로그 — 판정용 아님 · 성과 수치 · 시험 창 · 전기간 값은 이 요약에 싣지 않는다(칸 평가 콘솔 줄도 버린다)")),
            stages = S, pass = pass, seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), SUMF, useBytes = TRUE)
unlink(OUTD, recursive = TRUE)
cat(sprintf("[리허설] %s — %d초 · 요약 rehearsal/summary.json\n", if (pass) "통과" else "실패", res$seconds))
quit(status = if (pass) 0L else 1L)
