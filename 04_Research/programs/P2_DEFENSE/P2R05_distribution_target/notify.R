## P2R05 분기점 알림(도훈 10-13 '개선 프로세스는 분기점마다 1통(푸시)' · 정본 발송기 prep_send · P2R04 notify.R 형식) — notify_done.sh · warm_cache.sh 가 부른다.
##   알리는 것: 워밍 끝 · 중단(--warm) / 측정 · 판정이 끝났다(보는 창 판정 라벨 · 규칙별 결과 · ⑮ 꼬리 계기) / 측정하지 않았다(precheck · 배리어 · GPU 잠금 · 워밍 센티널 ·
##   칸 목록) / 평가 실패 / 마감 지연. 결과 보고(요약 + 차트 + 다음 리서치 브리핑 — SKILL §0.7)는 세션이 따로 보낸다. 시험 창 수치는 싣지 않는다(evaluation_visible.json 만 읽는다 ·
##   워밍 센티널 = 운영 기록 · 성과 수치 없음). 판정 어휘(verdict 값)는 evaluate.R 이 정한다 — 아래 사전에 없는 값은 원문 그대로 싣는다(조회 실패로 알림이 죽지 않게).
## 실행: Rscript notify.R [--timeout | --warm] [--eval=<evaluation_visible.json>] [--state=<센티널 폴더>]   (QVEST_TG_DRY_RUN=1 이면 발송 없이 본문만)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py"))) stop("[notify] 프로젝트 루트 표지 없음: ", ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%or%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
source("02_Infrastructure/programs/program_report.R")
a <- commandArgs(trailingOnly = TRUE)
arg <- function(k, d) { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), a, value = TRUE, perl = TRUE)); if (length(v)) v[1] else d }
RD <- "04_Research/programs/P2_DEFENSE/P2R05_distribution_target"
EVJ <- arg("eval", file.path(ROOT, RD, "results", "evaluation_visible.json"))
ST <- arg("state", file.path(ROOT, "04_Research/programs/_lib/night_state"))
sent <- function(f) { p <- file.path(ST, f); if (file.exists(p)) readLines(p, warn = FALSE)[1] else NA_character_ }
kv <- function(s, k) { if (is.na(s)) return(NA_character_); m <- regmatches(s, regexpr(paste0(k, "=[^ ]+"), s, perl = TRUE)); if (length(m)) sub(paste0("^", k, "="), "", m) else NA_character_ }
lk <- function(map, k) { k <- as.character(k %or% NA_character_)[1]; if (!is.na(k) && k %in% names(map)) map[[k]] else (k %or% "?") }   # 사전에 없으면 원문
ms <- sent("p2r05_measured.done"); es <- sent("p2r05_evaluated.done")
VW <- c(supported = "지지", partial = "부분 지지", falsified = "반증", untested = "미시험")
DN <- c(V1 = "꼬리 거부(q̂10 하위 20% 제외 → q̂50)", V2 = "꼬리 순위(q̂10)")
EN <- c(E2 = "DNN 원형", E3 = "B6_36")
## 판정어 이름 = 판정 구현 evaluate.R::P2R05_VERDICT_NAMES 와 같은 글자(격리 점검 v2 선택 4 — v1 필수 1 때 주석만 '같은 이름'이고 글자가 달랐다) · 별칭 4개는 ⑮ 이름 후보
CW <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어(β 짝 미통과)",
        selection_unmeasured = "선택 귀속 미측정 — 방어 이름 보류",
        size_or_exposure_defense = "크기 · 노출 방어(⑭ 미통과)", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 대조 미측정",
        asymmetry_unmet = "β 비대칭 미달(⑤ 수준 또는 Δ — 꼬리 회피 기계 아님)",
        defense_but_strength_or_path = "꼬리 회피 기계(방어만 · 복리 없음 — ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 미달)", untested = "미시험",
        untested_tail_instrument = "미시험(꼬리 계기 — 원천 ① 반증 아님)",
        tail_untested = "미시험(꼬리 계기 — 원천 ① 반증 아님)", tail_instrument_untested = "미시험(꼬리 계기 — 원천 ① 반증 아님)",   # ⑮ 어휘(판정 구현 쪽 이름 후보)
        instrument_untested = "미시험(꼬리 계기 — 원천 ① 반증 아님)", untested_instrument = "미시험(꼬리 계기 — 원천 ① 반증 아님)")
TARGET <- "분포 표적(분위 DNN · 원천 ①) 소비 규칙 2종 × 구성 2 · 진단 6 · 비교 기준 2 · 재시드 2"
status <- list(stage = "방어 엔진 — P2R05 분위 캐시 워밍 · 측정 · 셀 평가 · 판정(분리 실행 · 데이터 갱신 뒤)", position = NA,
               previous = "P2R04 방어적 보유(팩터 틸트) 4종 — 반증(10-18 15:59)")
NEXT <- "세션에서 결과 보고(누적 수익 · 낙폭 · 증분 알파 차트 — 시험 창은 사람 쪽 보고) + 다음 리서치 브리핑 · 철학 Superfan P2(방향 판정)"
send <- function(target, verdict_line, extra = NULL, next_step = NEXT, artifact = NULL) {
  r <- prep_send(program = "방어 엔진", target = target, status = status, verdict_line = verdict_line, next_step = next_step,
                 artifact = artifact, push = TRUE, extra = extra, root = ROOT)
  cat("prep_send ok =", isTRUE(r$ok), "\n"); invisible(r)
}
if ("--warm" %in% a) {
  SJ <- file.path(ST, "p2r05_warm.done"); LF <- file.path(ROOT, RD, "warm", "last_failure.txt")
  fail_newer <- file.exists(LF) && (!file.exists(SJ) || file.mtime(LF) > file.mtime(SJ))
  if (fail_newer) {
    lf <- readLines(LF, warn = FALSE)[1]
    status$position <- "분위 캐시 워밍 중단"
    why <- c(barrier_held = "데이터 갱신 배리어가 2시간 뒤에도 잡혀 있었다", precheck_fail = "워밍 직전 대조(정적 PIT · 템플릿 차분 · 핀 · 커밋) 불일치",
             gpu_locked = "GPU 잠금을 다른 워밍 · 측정이 쥐고 있었다", lane_on = "충실구현 레인이 켜져 있다 — 도훈 확인(정지 또는 허용) 필요",
             smi_fail = "nvidia-smi 조회 불가(다른 연산 0 을 확인할 수 없다)", gpu_busy = "다른 연산(Type C) 프로세스가 마감까지 남아 있었다(끄지 않았다)",
             cuda_unavailable = "venv torch 가 CUDA 를 못 본다(CPU 학습을 만들지 않았다)", q50_failed = "분위 엔진(engine_Q50.R) 단독 실행 실패",
             rx0s_missing = "재시드 엔진(engine_RX0S.R) 경로 해석 실패 또는 파일 없음", rx0s_failed = "재시드 엔진(engine_RX0S.R) 단독 실행 실패",
             rx0_failed = "RX0 평균 캐시 확인(engine.R) 실패")
    send(paste(TARGET, "— 분위 캐시 워밍 중단"), sprintf("%s(%s · rc %s)", lk(why, kv(lf, "status")), kv(lf, "status") %or% "?", kv(lf, "rc") %or% "?"),
         next_step = "세션에서 warm/ 로그(warm_q50.log · warm_rx0.log · monitor.log · precheck_warm.json · gpu_gate.json) 확인 뒤 다시 워밍", artifact = file.path(RD, "warm"))
  } else if (file.exists(SJ)) {
    w <- fromJSON(SJ, simplifyVector = FALSE)
    ok <- identical(w$status, "ok")
    status$position <- if (ok) "분위 캐시 워밍 완료" else "분위 캐시 워밍 — 완료했으나 단정 실패"
    vl <- sprintf("%s — 분위 캐시 %s · 학습 %s · 적중 %s · 장치 [%s] · 양성 대조 %s · 재시드 캐시 %s(%s) · RX0 평균 캐시 확인 %s · GPU memory.used %s → %s MiB · 감시 경고 %s%s",
                  if (ok) "워밍 완료" else "워밍 단정 실패", w$cache_months_text %or% "?", format(w$trained_months %or% NA), format(w$cached_months %or% NA),
                  paste(unlist(w$q50$devices), collapse = ","), if (isTRUE(w$positive_control$pass)) "통과" else "미확인",
                  w$reseed$cache_months_text %or% "?", w$reseed$status %or% "?", w$rx0$status %or% "?",
                  format(w$gpu$memory_used_mib_start %or% NA), format(w$gpu$memory_used_mib_end %or% NA), format(w$monitor_warnings %or% NA),
                  if (!ok) paste0(" · 사유: ", paste(unlist(w$why), collapse = " · ")) else "")
    send(paste(TARGET, if (ok) "— 분위 캐시 워밍 완료" else "— 분위 캐시 워밍 단정 실패"), vl,
         next_step = if (ok) "측정(bash measure_now_vram.sh — 같은 배치 · 측정 직전 워밍 신선도 단정 · 분리 실행) + 알림 감시(notify_done.sh)" else "세션에서 센티널 사유 · warm/ 로그 확인 뒤 다시 워밍",
         artifact = sub(paste0("^", ROOT, "/"), "", SJ))
  } else {
    status$position <- "분위 캐시 워밍 — 기록 없음"
    send(paste(TARGET, "— 워밍 기록 없음"), "warm_cache.sh 가 센티널도 중단 기록도 남기지 않았다", next_step = "세션에서 워밍 로그 확인")
  }
} else if ("--timeout" %in% a) {
  status$position <- "측정 지연"
  send(paste(TARGET, "— 측정 지연"), sprintf("마감까지 측정 · 판정이 끝나지 않았다(측정 센티널: %s · 평가 센티널: %s)", kv(ms, "status") %or% "없음", kv(es, "status") %or% "없음"),
       next_step = "세션에서 측정 로그 확인 뒤 재측정 · 평가")
} else if (!is.na(ms) && kv(ms, "status") %in% c("precheck_fail", "barrier_held", "gpu_locked", "warm_stale", "warm_invalid", "cells_mismatch", "gpu_busy", "sentinel_copy_failed")) {
  midrun <- identical(kv(ms, "status"), "gpu_busy") || identical(kv(ms, "stage"), "regroup")    # 일부 칸을 잰 뒤 멈춤(폴백 GPU 게이트 · 묶음 재측정 전 센티널 사본 실패)
  status$position <- if (midrun) "측정 중단(일부 칸 측정 뒤)" else "측정 안 함"
  why <- c(precheck_fail = "측정 직전 핀 대조(precheck) 불일치 — 사전등록과 다른 코드 · 엔진 · 데이터 조건", barrier_held = "데이터 갱신 배리어가 2시간 뒤에도 잡혀 있었다",
           gpu_locked = "GPU 잠금을 다른 워밍 · 측정이 쥐고 있었다", warm_stale = "워밍 뒤 데이터 판본이 바뀌었다(분위 캐시가 낡았다 — 다시 워밍 · 바뀐 달만 재학습)",
           warm_invalid = "워밍 센티널이 없거나 무효(상태 · 엔진 md5 · 캐시 전 달 · cuda · 양성 대조 · RX0 확인 중 하나)", cells_mismatch = "측정 스크립트의 칸 목록 ≠ 사전등록 cells",
           gpu_busy = paste0("RX0 · RX0S 셀 로그가 DNN 캐시 적중을 못 보여 분위 엔진 첫 칸을 단독으로 재려 했으나 GPU 게이트가 최대 대기 안에 열리지 않았다",
                             "(다른 연산 프로세스 — 끄지 않는다 · ", kv(ms, "group") %or% "?", " 묶음 · 게이트 rc ", kv(ms, "gate_rc") %or% "?", ")"),
           sentinel_copy_failed = paste0("워밍 센티널 사본(results/warm_sentinel.json)을 측정 묶음에 쓰지 못했다(", if (identical(kv(ms, "stage"), "regroup")) paste0(kv(ms, "group") %or% "?", " 묶음 재측정 전") else "측정 시작 전",
                                         ") — 사본 없이는 평가가 측정과 다른 판으로 묶일 수 있어 측정을 멈췄다(격리 점검 v2 권고 5)"))
  send(paste(TARGET, if (identical(kv(ms, "status"), "gpu_busy")) "— 측정 중단(GPU)" else if (identical(kv(ms, "status"), "sentinel_copy_failed")) "— 측정 중단(센티널 사본)" else "— 측정 안 함"), why[[kv(ms, "status")]],
       next_step = if (kv(ms, "status") %in% c("warm_stale", "warm_invalid")) "세션에서 warm_cache.sh 를 다시 띄운 뒤(레인 GPU 배분 확인) 측정 — 또는 measure.sh --rewarm"
                   else if (identical(kv(ms, "status"), "gpu_busy")) "레인 GPU 배분 확인(도훈) → GPU 가 빈 뒤 measure.sh 를 같은 명령으로 다시(ok 칸은 건너뛴다 · 워밍이 낡았으면 --rewarm)"
                   else if (identical(kv(ms, "status"), "sentinel_copy_failed")) "세션에서 사본 실패 원인(results 폴더 · 디스크 · 권한) 확인 뒤 measure.sh 를 같은 명령으로 다시(ok 칸은 건너뛴다)"
                   else "세션에서 원인 확인(results/precheck.json · 측정 로그) 뒤 다시 띄운다",
       artifact = file.path(RD, "results"))
} else if (!is.na(es) && !identical(kv(es, "status"), "evaluated")) {
  status$position <- "평가 실패"
  send(paste(TARGET, "— 평가 실패"), sprintf("측정 ok %s · 셀 평가 · 판정이 rc=%s 로 멈췄다(핀 · 지문 · 워밍 센티널 · 측정 연기 · 캐시 단정 중 하나 — 평가 로그에 사유)", kv(es, "ok") %or% "?", kv(es, "rc") %or% "?"),
       next_step = "세션에서 평가 로그(evaluate.log) 확인 — 지문 불일치 · 측정 연기면 그 묶음 재측정 뒤 평가", artifact = file.path(RD, "evaluate.log"))
} else {
  ev <- fromJSON(EVJ, simplifyVector = FALSE)
  status$position <- sprintf("측정 · 판정 완료 — 측정 ok %s", kv(es, "ok") %or% "?")
  rule_of <- function(x) as.character(x$rule %or% x$device %or% x$component %or% NA_character_)[1]
  is_diag <- function(x) isTRUE(x$diagnostic) || isTRUE(x$comparison) || isTRUE(as.character(x$role %or% "") %in% c("diagnostic", "comparison")) ||
    grepl("^(Q50|N[0-9]|S[0-9]|W[0-9]|LV|RX0S)$", as.character(x$component %or% ""))           # 진단 · 비교 기준 칸은 규칙 목록에서 뺀다(판정 표 밖)
  nm <- function(x) if (length(x)) paste(vapply(unlist(x), function(d) lk(DN, d), ""), collapse = " · ") else "없음"
  exl <- if (length(ev$excluded)) paste(vapply(ev$excluded, function(x) lk(DN, if (is.list(x)) rule_of(x) else x), ""), collapse = " · ") else "없음"
  vl <- sprintf("%s(판정 %s/%s칸) — 두 구성 통과 %s · 한 구성 통과 %s · 집중 제외 %s", lk(VW, ev$verdict), ev$n_judged %or% "?", ev$n_total %or% "?",
                nm(ev$pass_both), nm(ev$pass_one), exl)
  tl <- function(x) { ti <- x$tail_instrument %or% x$rules$tail_instrument
    if (is.null(ti)) return("")
    t <- suppressWarnings(as.numeric(ti$t %or% ti$nw_t %or% NA)); p <- ti$pass %or% ti$ok
    sprintf(" · ⑮ NW t %s(%s)", if (is.finite(t)) sprintf("%.2f", t) else "?", if (isTRUE(p)) "통과" else if (identical(p, FALSE)) "미달 = 미시험(계기)" else "?") }
  items <- vapply(names(DN), function(d) {
    xs <- Filter(function(x) identical(rule_of(x), d) && !is_diag(x), ev$cells %or% list())
    paste0(DN[[d]], " — ", if (length(xs)) paste(vapply(xs, function(x) sprintf("%s %s%s", lk(EN, x$engine), lk(CW, x$verdict), tl(x)), ""), collapse = " · ") else "칸 없음")
  }, character(1))
  sel <- if (length(ev$selected)) sprintf("선택: %s(S 증분 평균 %+.3f)", lk(DN, rule_of(ev$selected[[1]])), as.numeric(ev$selected[[1]]$dS %or% NA_real_)) else "선택 없음"
  send(paste(TARGET, "— 측정 · 판정 완료"), vl,
       extra = list(list(heading = "소비 규칙별 판정(보는 창 · 구성 2)", type = "bullet", items = unname(c(items, sel)))),
       artifact = file.path(RD, "results", "evaluation_visible.json"))
}
