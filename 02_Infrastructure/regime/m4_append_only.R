#!/usr/bin/env Rscript
## m4_append_only.R — m4 패널 append-only 게이트 (도훈 지시 2026-08-13:
##   "과거값 소급변경 시키지말고 최신 데이터만 행 추가시켜")
##
## **왜 필요한가** (2026-08-13 실측):
##   `factor_engine.R` 은 매 실행마다 패널을 **전량 재생성**한다. m4 자체 기계는 PIT-안전해서
##   안정적이나(ret_net 0/269 · bocpd_norm 0/269 · decay_* 0/234 변경), **매크로 국면 입력이
##   재생성될 때마다 과거를 재서술**한다 — 2026-07-02 백업 대비 2026-08-01 현재본에서
##   `MSM_Crisis_Prob_lag` **268/268 행**(최대 Δ 0.199) · `Regime_Score_lag` 250/268 행 변경.
##   그 결과 최종 결정값 `weight_str1715` 가 **8개 행에서 소급 변경**됐다:
##     2008-02-01 1.0000→0.8443 · 2011-12-01 1.0000→0.8480 · 2012-01-02 1.0000→0.8480
##     2026-05-04 0.8064→1.0000 · 2026-06-01 0.8064→1.0000 (+ 3건)
##   그리고 **2026-07 행이 통째로 사라졌다**(백업 n=270 max 2026-07 → 현재 n=270 max 2026-08).
##   배포된 달의 오버레이 승수가 사후에 바뀌는 것은 북 기록의 의미를 없앤다.
##
## **설계**: 발행된 과거는 정본이고 절대 덮지 않는다. 새 달만 이어붙인다.
##   - 발행 원장: 06_Registry/m4_published/m4_panel_published.parquet (append-only)
##   - 매 실행: 재생성본과 발행본을 대조 → **드리프트는 보고만 하고 적용하지 않는다**
##   - 운영 산출물 2종(parquet · m4_extended.csv)을 발행본으로 되돌려 소비자가 안정된 이력을 본다
##
## **소비자 2군** (2026-08-13 census — 둘 다 같은 factor_engine 실행이 씀):
##   parquet  : forward_weights_D3_M4gAE.R(배포 정본) · forward_weights.R · forward_weights_R05_AR.R
##   extended : run_layer5_rerun_extended.R · extend_nolayer4_series.R · run_nolayer4_monthly.sh 등
##
## **도훈 대원칙 2026-08-13** — 이 스크립트가 강제하는 두 가지:
##   ① 새로운 리밸런싱 시점에 **과거 데이터가 변경되면 안 된다** → 발행 원장 append-only
##   ② 모든 결과값은 **직전 데이터까지만** 활용 (PIT) → 신규 행의 매크로 관측일 < 결정일 검증
##
## **★PIT C11 표식 승계 (2026-09-24 · 판정서 V-04 · 결정 PIT-C11-BOOK0001 · PIT-C11-P2-AUX ②)**:
##   factor_engine.R 은 행마다 C11 표식 3열(c11_info_cutoff · c11_regime_key · c11_status)을 싣는다.
##   구판 병합(`add[, .SD, .SDcols = names(pub)]`)과 두 쓰기(발행 원장 · 운영 패널)는 발행 원장 열 이름으로
##   잘라 **새 열을 조용히 버렸다** — 소비자(pg2 arm · 배포 생성기)는 C11 상태를 영영 못 봤다.
##   현행: ① 신규 행이 표식을 싣고 오면 발행 원장이 열을 승계한다(기발행 행 = "unresolved" — 수리 전 상류 위
##   산출이라는 상태 표기이지 값 재서술이 아니다) ② 표식 일부만 오면 중단(2) ③ 신규 행 C11 검사 —
##   verified 인데 c11_info_cutoff > Date 또는 상태값 미지 = PIT 위반(4) · unresolved·epoch 불일치 = 경고(기록)
##   ④ 사이드카·드리프트 로그에 표식 요약. epoch 재초기화 = m4_epoch_reinit.R(구판 보관 → 원장 이관 → --init).
##
## 사용:  Rscript m4_append_only.R --as-of 2026-09-01 [--dry-run] [--init]
##        --init = 발행 원장이 **없을 때만** — 빈 원장에 재생성본 결정행(월 첫 행, Date <= AS_OF)을 잇는다
##                 (병합 경로와 같은 후보 필터·C11·PIT·AS_OF 검사·dry-run·동기화). 원장이 있으면 거부(2).
## 종료:  0 정상 / 1 드리프트 검출(과거 재서술 시도, 발행본 보존) / 2 입력·환경 오류
##        3 AS_OF 행 미생성(침묵 낡음 차단) / 4 PIT 위반(결정일 이후 매크로 관측 사용 · C11 컷오프 위반)

## ★진행 표식 (2026-08-13) — 러너 안에서 **첫 출력 전에** 블록되는 사례를 잡기 위해.
##   블록 지점이 라이브러리 로드인지 파일 열기인지 로그만으로 갈리도록 단계마다 찍는다.
##   (단독 실행은 1초인데 러너 안에서 무한 대기 — 재현은 되나 지점 미특정 상태였다)
cat(sprintf("[m4-append] start %s pid=%d\n", format(Sys.time(), "%H:%M:%S"), Sys.getpid())); flush(stdout())
## ★★arrow 교착 방어 (2026-08-13 실측 확정 — 이 게이트가 러너 안에서 무한 대기한 진짜 원인)
##   `ARROW_IO_THREADS=1` ∧ `mmap=FALSE` 조합에서만 read_parquet 가 자기 교착한다.
##   2×3 격자 실측(271행 파일): io미설정×{T,F} OK · io=1×mmap=TRUE OK · **io=1×mmap=FALSE HANG**
##   · io=2×F OK · io=4×F OK — 정확히 한 칸만 멈춘다(단일 IO 스레드풀 self-deadlock).
##   호출자(run_nolayer4_monthly.sh)가 =1 을 export 했고 이 스크립트는 mmap=FALSE 를 쓴다.
##   저장소 관행이 이미 `Sys.setenv(ARROW_IO_THREADS="2")` (reports/ 등 15개 스크립트) — 그 관행에 합류.
##   ★호출자 환경에 의존하지 않도록 **여기서** 올린다. library(arrow) **전에** 걸어야 한다.
if (suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))) %in% 1L) Sys.setenv(ARROW_IO_THREADS = "2")
suppressPackageStartupMessages({library(data.table); library(arrow)})
try(if (arrow::io_thread_count() < 2L) arrow::set_io_thread_count(2L), silent = TRUE)  # 로드 후 2차 방어
cat(sprintf("[m4-append] libs ok (arrow io_threads=%s)\n",
            tryCatch(arrow::io_thread_count(), error = function(e) "?"))); flush(stdout())
options(scipen = 999)

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
PANEL <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")
M4EXT <- file.path(ROOT, "stage_artifacts/WT-D20260430_001_m4_extended.csv")
PUBDIR <- file.path(ROOT, "06_Registry/m4_published")
PUB <- file.path(PUBDIR, "m4_panel_published.parquet")
DRIFT_LOG <- file.path(PUBDIR, "m4_drift_log.jsonl")

## 2계층: 결정열이 바뀌면 hard, 입력열은 로그만 (AE 배관 ae_regime_monthly.py 와 같은 규약)
DECISION_COLS <- c("weight_str1715", "weight_cash")
INPUT_COLS <- c("Regime_Score_lag", "MSM_Crisis_Prob_lag", "combined_regime", "conjunction_score")
## ★C11 표식 3열 — 생산자 factor_engine.R(c11_regime_check · result_cols)과 같은 이름. 값 규약:
##   c11_status ∈ {verified(컷오프 있음) · no_regime(국면 미사용 워밍업 행) · unresolved(표식 없음 — 수리 전 상류)}
C11_COLS <- c("c11_info_cutoff", "c11_regime_key", "c11_status")
C11_STATUS_OK <- c("verified", "no_regime", "unresolved")

die <- function(code, msg) { cat(sprintf("[m4-append] ERROR %s\n", msg)); quit(status = code) }
say <- function(...) cat(sprintf(...))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## ---- args ----
a <- commandArgs(TRUE)
getarg <- function(k, d = NA) { i <- which(a == k); if (length(i) && length(a) > i[1]) a[i[1] + 1L] else d }
AS_OF <- as.Date(getarg("--as-of", NA))
DRY <- "--dry-run" %in% a
INIT <- "--init" %in% a
if (is.na(AS_OF)) die(2, "--as-of YYYY-MM-01 필수")
if (as.integer(format(AS_OF, "%d")) != 1L) die(2, sprintf("--as-of 는 월 1일이어야 함: %s", AS_OF))

## ★Windows: read_parquet 기본값 mmap=TRUE 는 파일을 **매핑한 채 잡고 있어** 같은 경로 쓰기가
##   `[Windows error 1224] 사용자가 매핑한 구역이 열려 있는 상태` 로 실패한다(실측 2026-08-13).
##   나중에 되쓰는 파일은 반드시 mmap=FALSE 로 읽는다.
rp <- function(p) as.data.table(read_parquet(p, mmap = FALSE))

if (!file.exists(PANEL)) die(2, sprintf("m4 패널 부재: %s", PANEL))

## ★오진 기록(남겨둠 — 같은 함정에 다시 빠지지 않기 위해): 이 read 가 러너 안에서 무한 대기했을 때
##   "스텝[1]이 방금 쓴 파일을 OneDrive/잔존 핸들이 잡고 있다"고 가정하고 크기-안정화 대기 + 임시사본
##   경유 읽기를 넣었다 — **둘 다 헛수고**였다. 판별한 것은 **카나리아**(무관한 271행 파일을 먼저 읽기)로,
##   그 작은 파일에서도 똑같이 멈춰 원인이 파일이 아니라 **arrow 스레드풀**임을 드러냈다(위 상단 격자 참조).
##   교훈 = "막힌 대상"을 고치기 전에 **무관한 대조 대상**으로 대상 특정성부터 가를 것.
cat(sprintf("[m4-append] opening PANEL (size=%s bytes)\n",
            format(file.info(PANEL)$size, big.mark = ","))); flush(stdout())
fresh <- rp(PANEL); fresh[, Date := as.Date(Date)]
cat("[m4-append] PANEL read ok\n"); flush(stdout())
setorder(fresh, Date)
say("[m4-append] 재생성본 n=%d  %s ~ %s\n", nrow(fresh), min(fresh$Date), max(fresh$Date))

## ---- 발행 원장 적재 / 초기화 ----
##   ★(2026-09-24 C11 epoch 재초기화 대비 수리) 구판 --init 은 재생성본을 **통째로** 원장에 쓰고 바로 끝났다 —
##     (a) 데이터 꼬리 행·기발행 월 중복 결정행까지 원장에 박히고(아래 2026-08-29 수리가 막는 바로 그 행들)
##     (b) PIT·C11·AS_OF 검사도, 운영 산출물 2종·사이드카 동기화도 없었다.
##     또 원장이 이미 있으면 --init 을 **말없이 무시**하고 병합 경로로 흘렀다(사용자는 초기화됐다고 믿는다).
##   현행: init = '빈 원장에 잇기'. 병합 경로를 그대로 타므로 검사·기록이 전부 같다. 원장이 있으면 거부.
if (!dir.exists(PUBDIR)) dir.create(PUBDIR, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(PUB)) {
  if (!INIT) die(2, sprintf("발행 원장 부재 — 최초 1회 --init 로 재생성본 결정행을 기준선으로 동결할 것: %s", PUB))
  pub <- fresh[0L]
  say("[m4-append] ★발행 원장 초기화 모드 — 빈 원장에 재생성본 결정행(월 첫 행 · Date <= %s)을 잇는다\n", AS_OF)
  say("            (후보 필터·C11 표식·PIT·AS_OF 검사·dry-run·동기화 = 병합 경로와 동일)\n")
} else {
  if (INIT) die(2, paste0("--init 인데 발행 원장이 이미 있다 — 덮어쓰지 않는다. epoch 재초기화는 ",
                          "m4_epoch_reinit.R(구판 보관 → 원장 이관 → --init) 로: ", PUB))
  pub <- rp(PUB); pub[, Date := as.Date(Date)]
  setorder(pub, Date)
  say("[m4-append] 발행 원장   n=%d  %s ~ %s\n", nrow(pub), min(pub$Date), max(pub$Date))
}

## ---- 드리프트 대조 (공통 행) — 보고만, 적용 않음 ----
common <- intersect(as.character(pub$Date), as.character(fresh$Date))
say("[m4-append] 공통 %d행 대조\n", length(common))
drift_hard <- list(); drift_soft <- list()
cmpcol <- function(cl) {
  if (!(cl %in% names(pub)) || !(cl %in% names(fresh))) return(NULL)
  p <- pub[as.character(Date) %in% common][order(Date)]
  f <- fresh[as.character(Date) %in% common][order(Date)]
  x <- p[[cl]]; y <- f[[cl]]
  if (!is.numeric(x) || !is.numeric(y)) return(NULL)
  bad <- which(!is.na(x) & !is.na(y) & abs(x - y) > 1e-12)
  if (!length(bad)) return(NULL)
  list(col = cl, n = length(bad), max_delta = max(abs(y[bad] - x[bad])),
       examples = paste(sprintf("%s %.4f->%.4f", as.character(p$Date[bad]), x[bad], y[bad])[seq_len(min(4, length(bad)))],
                        collapse = " | "))
}
for (cl in DECISION_COLS) { r <- cmpcol(cl); if (!is.null(r)) drift_hard[[cl]] <- r }
for (cl in INPUT_COLS)    { r <- cmpcol(cl); if (!is.null(r)) drift_soft[[cl]] <- r }

if (length(drift_soft)) {
  say("[m4-append] 입력 드리프트(로그): ")
  for (r in drift_soft) say("%s %d행(최대 Δ%.4f)  ", r$col, r$n, r$max_delta)
  say("\n            └ 매크로 국면 재생성 산물 — 결정값에 닿지 않는 한 통과\n")
}
if (length(drift_hard)) {
  say("\n[m4-append] ★★과거 결정값 재서술 시도 검출 — 적용하지 않고 발행본을 유지한다\n")
  for (r in drift_hard) {
    say("   %s: %d행 변경 (최대 Δ%.4f)\n      %s\n", r$col, r$n, r$max_delta, r$examples)
  }
}
## ★C11 표식 드리프트 (로그만 — 2026-09-24). 기발행 행의 표식은 발행 시점 상태의 기록이라 덮지 않는다.
##   재생성본과 갈리면 상류 표식 소실(예: 국면 원장 병합이 표식 열을 지움 · 판정서 사후검증 NON-BLOCKING)이나
##   규칙 epoch 변경의 지문이다 — 조용히 넘기지 않고 수를 남긴다.
c11_drift <- list()
if (length(common) && "c11_status" %in% names(pub) && "c11_status" %in% names(fresh)) {
  .p <- pub[as.character(Date) %in% common][order(Date)]
  .f <- fresh[as.character(Date) %in% common][order(Date)]
  .neq <- function(a, b) { a <- as.character(a); b <- as.character(b)
                           which(xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)) }
  .ds <- .neq(.p$c11_status, .f$c11_status)
  .dk <- if ("c11_regime_key" %in% names(pub) && "c11_regime_key" %in% names(fresh))
    .neq(.p$c11_regime_key, .f$c11_regime_key) else integer(0)
  c11_drift <- list(status_n = length(.ds), key_n = length(.dk),
                    examples = paste(sprintf("%s %s->%s", as.character(.p$Date[.ds]), .p$c11_status[.ds],
                                             .f$c11_status[.ds])[seq_len(min(4L, length(.ds)))], collapse = " | "))
  if (length(.ds) || length(.dk))
    say("[m4-append] C11 표식 드리프트(로그): status %d행 · epoch 키 %d행  %s\n            └ 발행 표식 유지 — 상류 표식 소실/epoch 변경 점검\n",
        length(.ds), length(.dk), c11_drift$examples)
}

## ---- append-only 병합 ----
pub_max <- if (nrow(pub)) max(pub$Date) else as.Date(NA)
add <- if (nrow(pub)) fresh[Date > pub_max] else copy(fresh)
if (INIT && nrow(add)) {
  ## 초기화는 'AS_OF 시점의 기준선'이다 — AS_OF 뒤 행은 다음 병합 실행의 몫(PIT 검사도 그때 받는다).
  .late <- add$Date > AS_OF
  if (any(.late)) say("[m4-append] 초기화 — AS_OF 뒤 %d행 제외: %s\n", sum(.late),
                      paste(as.character(add$Date[.late]), collapse = " "))
  add <- add[!.late]
}
## ★(2026-08-29 수리) 독트린 정합 — "새 달만 잇는다" (선언 §16 그대로의 구현):
##   재생성본은 발행 후보가 아닌 행 2류를 만들 수 있다 —
##   ① 기발행 월의 중복 결정행(달력 1일 vs 실거래 첫날 표기 차: 발행 08-01 vs 재생성 08-03)
##   ② 데이터 꼬리 행(마지막 데이터일 — 결정일이 아님. 월중 실행 시에만 생김)
##   실측(2026-08-29, AS_OF=2026-09-01): add = {08-03(①), 08-28(②), 09-01(진짜 새 달)}.
##   ②가 자기 달 말 라벨 매크로를 물어 PIT 게이트가 전체를 차단했다 — 게이트 판정은 옳았으나
##   그 행은 애초에 발행 후보가 아니다. **미발행 월의 첫 행만** 후보로 삼는다
##   (패널 불변량 = 월 1행 · 결정행 = 그 달 첫 행). PIT 검사는 남은 후보에 그대로 걸린다.
if (nrow(add)) {
  .add_ym <- format(add$Date, "%Y-%m")
  .pub_ym <- unique(format(pub$Date, "%Y-%m"))
  .keep <- !duplicated(.add_ym) & !(.add_ym %in% .pub_ym)
  if (any(!.keep)) {
    say("[m4-append] 발행 후보 제외 %d행 (기발행 월 중복/데이터 꼬리 — 결정행 아님): %s\n",
        sum(!.keep), paste(as.character(add$Date[!.keep]), collapse = " "))
  }
  add <- add[.keep]
}
if (nrow(add)) {
  say("[m4-append] 신규 %d행 추가: %s\n", nrow(add), paste(as.character(add$Date), collapse = " "))
} else {
  say("[m4-append] 신규 행 없음 (발행 종점 %s >= 재생성 종점 %s)\n", as.character(pub_max), max(fresh$Date))
}
miss <- setdiff(names(pub), names(add))
if (length(miss) && nrow(add)) {
  if (any(miss %in% C11_COLS))
    die(2, sprintf(paste0("신규 행에 C11 표식 열 결손: %s — 발행 원장은 표식을 싣는데 상류(factor_engine)가 표식을 ",
                          "내지 않았다(구판 엔진·표식 소실). 표식 없는 행을 표식 원장에 잇지 않는다"),
                   paste(intersect(miss, C11_COLS), collapse = ",")))
  die(2, sprintf("신규 행에 발행 원장 컬럼 결손: %s", paste(miss, collapse = ",")))
}
## ★PIT C11 표식 승계 (2026-09-24 · 판정서 V-04 · 사후검증 NON-BLOCKING 'm4_append_only.R:165·264·267').
##   구판은 아래 rbindlist 를 names(pub) 로 잘라 신규 행의 표식 열을 버렸고, 그 final 을 발행 원장(PUB)과
##   운영 패널(PANEL)에 되써 **재생성본의 표식까지 지웠다** — 소비자(pg2 arm · 배포 생성기)는 C11 상태를 못 봤다.
##   신규 행이 표식을 싣고 오면 원장이 열을 승계한다. 기발행 행 = 수리 전 상류 위 산출 → c11_status "unresolved"
##   (값 재서술이 아니라 상태 표기 · 컷오프·키는 모름 = NA). 표식 일부만 오면 계약 위반으로 중단.
.c11_in_add <- intersect(C11_COLS, names(add))
if (nrow(add) && length(.c11_in_add) && length(.c11_in_add) < length(C11_COLS))
  die(2, sprintf("신규 행의 C11 표식이 일부만 있다(%s / 필요 %s) — 표식 계약 불일치, 원장에 잇지 않는다",
                 paste(.c11_in_add, collapse = ","), paste(C11_COLS, collapse = ",")))
if (nrow(add) && length(.c11_in_add) == length(C11_COLS)) {
  .n_new <- sum(!C11_COLS %in% names(pub))
  if (!"c11_info_cutoff" %in% names(pub)) pub[, c11_info_cutoff := as.Date(NA)]
  if (!"c11_regime_key" %in% names(pub))  pub[, c11_regime_key := NA_character_]
  if (!"c11_status" %in% names(pub))      pub[, c11_status := if (.N) "unresolved" else character(0)]
  if (.n_new) say("[m4-append] ★C11 표식 열 %d개 승계 — 기발행 %d행 = unresolved(수리 전 상류 위 산출 · 값 불변)\n",
                  .n_new, nrow(pub))
  add[, c11_info_cutoff := as.Date(c11_info_cutoff)]
  add[, c11_regime_key := as.character(c11_regime_key)]
  add[, c11_status := as.character(c11_status)]
}
final <- if (nrow(add)) rbindlist(list(pub, add[, .SD, .SDcols = names(pub)]), use.names = TRUE) else copy(pub)
setorder(final, Date)

## ---- 검증: 월 결손 ----
ym_all <- format(seq(min(final$Date), max(final$Date), by = "month"), "%Y-%m")
ym_have <- format(final$Date, "%Y-%m")
gaps <- setdiff(ym_all, ym_have)
if (length(gaps)) {
  say("[m4-append] ★월 결손 %d개: %s\n", length(gaps),
      paste(utils::head(gaps, 12), collapse = " "))
  say("            └ 이미 유실된 달은 이 게이트가 되살리지 못한다(값 특정 불가). 기록만 남긴다.\n")
}
## ---- 원칙 2: PIT — 신규 행이 쓴 매크로 관측이 결정일 **이전**인가 ----
##   (도훈 대원칙 2026-08-13: "모든 결과값은 직전 데이터까지만 활용")
##   m4 행에는 매크로 입력이 `MSM_Crisis_Prob_lag` 로 **값째 박혀** 있다. 그 값이 매크로 계열의
##   어느 관측일에서 왔는지 역추적해 **결정일보다 이전인지** 검증한다.
##   ★이 검사가 필요한 이유: 매크로 계열은 월말 스탬프인데 마지막 행이 **진행 중인 달**일 수 있고
##     (실측: 2026-08-13 현재 종점 2026-08-31), 그걸 집어 쓰면 동월 look-ahead 가 된다.
##   ★BOCPD/decay 축은 ret_net[1..t-1] 만 쓰도록 설계돼 있고 재생성 간 변경 0 으로 실측 확인됨.
MACRO <- file.path(ROOT, ".cache/unified_regime_signal.parquet")
## ★규칙 (도훈 2026-08-13, 명시): **결정월 M 의 비중은 M−1 월 마지막 영업일 데이터까지만 쓴다.**
##   7월 비중 ← 6월말 · 8월 비중 ← 7월말. 그 이후(자기 달 포함)를 쓰면 미래참조,
##   그 이전(M−2 이하)을 쓰면 규칙 위반(낡음). **양방향 모두 차단**한다.
##   ⚠구판은 "과거 어딘가에서 왔나"만 봐서 M−2 를 통과시켰다 — 실제로 현행 2026-08 행이
##     2026-06-30(M−2)을 써놓고 통과했다. 기대 관측을 **먼저 지정**하고 대조하는 방식으로 바꾼다.
pit_check_rows <- function(rows) {
  if (!nrow(rows)) return(list(viol = list(), unver = list(), ok = list()))
  if (!file.exists(MACRO)) { say("[m4-append] ★매크로 계열 부재 — PIT 검증 불능\n"); return(NULL) }
  mac <- rp(MACRO); mac[, Date := as.Date(Date)]
  if (!("MSM_Crisis_Prob" %in% names(mac))) { say("[m4-append] ★매크로에 MSM_Crisis_Prob 없음 — 검증 불능\n"); return(NULL) }
  setorder(mac, Date)
  TOL <- 1e-6   # 재생성 드리프트 중앙값 7.4e-6 대비 — 갓 계산된 신규 행은 거리 ~0
  viol <- list(); unver <- list(); okl <- list()
  for (i in seq_len(nrow(rows))) {
    t <- rows$Date[i]; v <- rows$MSM_Crisis_Prob_lag[i]
    if (is.na(v)) { unver[[length(unver)+1L]] <- sprintf("%s (값 NA)", t); next }
    ## 기대 관측 = 결정월 직전월의 마지막 관측
    m_start <- as.Date(format(t, "%Y-%m-01"))
    prev_rows <- mac[Date < m_start]
    if (!nrow(prev_rows)) { unver[[length(unver)+1L]] <- sprintf("%s (직전월 관측 없음)", t); next }
    exp_date <- max(prev_rows$Date)
    exp_ym <- format(exp_date, "%Y-%m")
    want_ym <- format(seq(m_start, by = "-1 month", length.out = 2)[2], "%Y-%m")
    ## ★매크로에 M−1 관측이 아예 없으면 "직전 관측"이 M−2 가 되어, M−2 를 쓴 행이 기대값과
    ##   일치해 **통과해 버린다**. 그건 규칙 준수가 아니라 계열이 낡은 것이다 — 여기서 막는다.
    ##   (실사고: 2026-08 행이 2026-06-30 을 썼다. 그때 07-31 행이 없었다면 이 분기가 잡았을 것)
    if (!identical(exp_ym, want_ym)) {
      viol[[length(viol)+1L]] <- sprintf(
        "%s ← 매크로에 직전월(%s) 관측이 없음 · 가장 최근이 %s [계열 낡음 — 갱신 후 재실행]",
        t, want_ym, exp_date)
      next
    }
    exp_v <- prev_rows[Date == exp_date]$MSM_Crisis_Prob[1]
    if (!is.na(exp_v) && abs(exp_v - v) < TOL) {
      okl[[length(okl)+1L]] <- sprintf("%s ← 매크로 %s (직전월 %s 말, 값차 %.2e)", t, exp_date, want_ym,
                                       abs(exp_v - v))
      next
    }
    ## 기대와 다르다 — 실제 출처를 찾아 방향을 판정
    cand <- mac[!is.na(MSM_Crisis_Prob) & abs(MSM_Crisis_Prob - v) < TOL]
    if (!nrow(cand)) {
      unver[[length(unver)+1L]] <- sprintf("%s (기대 %s 와 불일치·출처 특정 불가 — 값차 %.2e)",
                                           t, exp_date, abs(exp_v - v)); next
    }
    src <- cand$Date[which.min(abs(as.integer(cand$Date - exp_date)))]
    dir <- if (src >= m_start) "미래참조(자기 달 이후)" else "낡음(직전월보다 이전)"
    viol[[length(viol)+1L]] <- sprintf("%s ← 매크로 %s [%s] · 기대 %s(%s말)", t, src, dir, exp_date, want_ym)
  }
  list(viol = viol, unver = unver, ok = okl)
}
pc <- pit_check_rows(add)
if (!is.null(pc)) {
  for (s in pc$ok)    say("[m4-append] PIT OK   %s\n", s)
  for (s in pc$unver) say("[m4-append] PIT ?    %s — 검증 불능(차단 안 함, 기록)\n", s)
  if (length(pc$viol)) {
    say("\n[m4-append] ★★PIT 위반 — 신규 행이 결정일 이후 매크로 관측을 썼다\n")
    for (s in pc$viol) say("   %s\n", s)
    say("            기록하지 않고 중단한다.\n")
    quit(status = 4)
  }
}

## ---- ★PIT C11 — 신규 행의 해외 정보 컷오프 (2026-09-24 · 판정서 V-04) ----
##   위 원칙 2 검사는 MSM 값의 **라벨** 출처(M−1 월말 행)를 본다. 그 행이 담은 해외 정보가 결정일에 실제로
##   가용했는지는 라벨로 알 수 없다(C11) — 생산자가 실은 c11_info_cutoff 로만 안다(factor_engine.R c11_regime_check).
##   · verified 인데 컷오프 결측/컷오프 > 결정일(Date) · 상태값 미지 → PIT 위반(4). 생산자가 이미 멈추는 조건이라
##     여기 걸리면 패널이 생산자 밖에서 바뀐 것이다 — 발행 원장 앞 마지막 방어선이라 다시 잰다.
##   · unresolved(상류 표식 없음) · 규칙 epoch 불일치 → 경고·기록(결정 PIT-C11-BOOK0001 '표기'). 차단하지 않는다 —
##     소비자 pg2 arm 은 이 행들을 스스로 거부한다(fail-closed · pg2_risk_overlay.R .pg2_load_m4).
c11_rules_key_now <- function() {
  f <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
  rp_ <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
  if (!file.exists(f) || !file.exists(rp_)) return(NA_character_)
  tryCatch({
    e <- new.env(parent = globalenv())
    suppressMessages(suppressWarnings(sys.source(f, envir = e)))
    as.character(e$fred_avail_rules_meta(rp_)$regime_key)
  }, error = function(err) NA_character_)
}
c11_check_rows <- function(rows, key_now) {
  out <- list(n = nrow(rows), verified = 0L, no_regime = 0L, unresolved = 0L, key_mismatch = 0L,
              viol = character(0), warn = character(0))
  if (!nrow(rows)) return(out)
  if (!all(C11_COLS %in% names(rows))) {
    out$unresolved <- nrow(rows)
    out$warn <- sprintf("신규 %d행에 C11 표식 열 없음(상류 수리 전 판) — 원장 표식 미승계", nrow(rows))
    return(out)
  }
  st <- as.character(rows$c11_status); cut <- as.Date(rows$c11_info_cutoff); key <- as.character(rows$c11_regime_key)
  bad_st <- which(is.na(st) | !(st %in% C11_STATUS_OK))
  for (i in bad_st) out$viol <- c(out$viol, sprintf("%s c11_status='%s' (허용: %s)", rows$Date[i], st[i],
                                                    paste(C11_STATUS_OK, collapse = "/")))
  ver <- which(st %in% "verified")
  for (i in ver[is.na(cut[ver]) | cut[ver] > rows$Date[ver]])
    out$viol <- c(out$viol, sprintf("%s c11_status=verified · c11_info_cutoff %s > 결정일(또는 결측)", rows$Date[i],
                                    as.character(cut[i])))
  out$verified <- length(ver); out$no_regime <- sum(st %in% "no_regime"); out$unresolved <- sum(st %in% "unresolved")
  if (out$unresolved)
    out$warn <- c(out$warn, sprintf("신규 %d행 c11_status=unresolved — 상류 unified 월간 표식 없음(C11 미해소 표기)",
                                    out$unresolved))
  if (length(ver)) {
    km <- ver[is.na(key[ver]) | is.na(key_now) | key[ver] != key_now]
    out$key_mismatch <- length(km)
    if (length(km))
      out$warn <- c(out$warn, sprintf("신규 %d행 규칙 epoch '%s' ≠ 현행 '%s' — 옛 규칙 판(재빌드 대상)", length(km),
                                      key[km[1]], key_now))
  }
  out
}
C11_KEY_NOW <- c11_rules_key_now()
c11c <- c11_check_rows(add, C11_KEY_NOW)
if (nrow(add))
  say("[m4-append] C11 신규 %d행: verified %d · no_regime %d · unresolved %d · epoch 불일치 %d (현행 %s)\n",
      c11c$n, c11c$verified, c11c$no_regime, c11c$unresolved, c11c$key_mismatch,
      ifelse(is.na(C11_KEY_NOW), "판독 불가", C11_KEY_NOW))
for (s in c11c$warn) say("[m4-append] ★C11 경고 %s\n", s)
if (length(c11c$viol)) {
  say("\n[m4-append] ★★PIT C11 위반 — 신규 행의 해외 정보 컷오프가 결정일 뒤이거나 표식이 계약 밖\n")
  for (s in c11c$viol) say("   %s\n", s)
  say("            기록하지 않고 중단한다.\n")
  quit(status = 4)
}

## ---- fail-closed: AS_OF 행 필수 ----
##   ★이 게이트가 막으려는 원래 결함이 "행이 없으면 조용히 직전 달 값을 쓴다" 이다.
##   따라서 AS_OF 행 미생성은 **쓰기 전에, dry-run 에서도 동일하게** 중단해야 한다.
##   (초판은 이 검사가 dry-run 분기 뒤 + 쓰기 뒤에 있어서 dry-run 이 exit 0 을 냈다 — 자체 검출 후 수정)
has_asof <- any(final$Date == AS_OF)
say("[m4-append] AS_OF %s 행 %s\n", AS_OF, ifelse(has_asof, "존재", "★부재"))
if (!has_asof) {
  say("[m4-append] ★AS_OF 행 미생성 — 상류(factor_engine)가 이 달을 만들지 못했다.\n")
  say("            기록하지 않고 중단한다. 이대로 진행하면 배포 생성기가 직전 달 m4 를 조용히 쓴다.\n")
  quit(status = 3)
}

if (DRY) { say("[m4-append] dry-run — 기록 안 함\n"); quit(status = if (length(drift_hard)) 1 else 0) }

## ---- 기록 ----
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
if (file.exists(PUB)) invisible(file.copy(PUB, paste0(PUB, ".bak_", ts), overwrite = FALSE))
write_parquet(final, PUB)
## 운영 산출물 2종을 발행본으로 되돌린다 (소비자가 안정된 이력을 보게)
invisible(file.copy(PANEL, paste0(PANEL, ".regen_", ts), overwrite = FALSE))
write_parquet(final, PANEL)
if (file.exists(M4EXT)) invisible(file.copy(M4EXT, paste0(M4EXT, ".regen_", ts), overwrite = FALSE))
fwrite(final[, .(Date, weight_str1715, weight_cash)], M4EXT)
say("[m4-append] 기록 완료 — 발행 원장 n=%d, 운영 산출물 2종 동기화\n", nrow(final))

## ── git 추적 가능한 텍스트 사이드카 ────────────────────────────────────────
##   발행 원장(.parquet)은 `.gitignore:20 *.parquet` 에 걸려 버전 관리가 안 된다. 운영 패널도
##   미추적이고 m4_extended.csv 는 `*.csv` 로 무시된다 — 즉 **m4 이력이 어디에도 버전 관리되지 않는다.**
##   원칙①("과거가 바뀌면 안 된다")의 증거는 diff 로 확인돼야 하므로, 결정값과 그 매크로 출처를
##   담은 사이드카를 텍스트로 남긴다. 바이너리 강제추가보다 **읽히는 diff** 가 감사에 맞다.
SIDE <- file.path(PUBDIR, "m4_published_ledger.jsonl")
side_cols <- intersect(c("Date","weight_str1715","weight_cash","Regime_Score_lag",
                         "Cash_Pct_lag","MSM_Crisis_Prob_lag","conjunction_score", C11_COLS), names(final))
sd_ <- final[, .SD, .SDcols = side_cols][order(Date)]
sd_[, Date := as.character(Date)]
if ("c11_info_cutoff" %in% names(sd_)) sd_[, c11_info_cutoff := as.character(as.Date(c11_info_cutoff))]  # ★C11 표식도 diff 로 감사
con <- file(SIDE, "w", encoding = "UTF-8")
for (i in seq_len(nrow(sd_))) writeLines(jsonlite::toJSON(as.list(sd_[i]), auto_unbox = TRUE, digits = 12), con)
close(con)
say("[m4-append] 사이드카 %s (%d행, git 추적용)\n", basename(SIDE), nrow(sd_))

## 드리프트 감사 로그
rec <- list(ts = ts, as_of = as.character(AS_OF), n_published = nrow(final),
            n_added = nrow(add), gaps = gaps, init = INIT,
            c11 = list(rules_key = C11_KEY_NOW, added_verified = c11c$verified, added_no_regime = c11c$no_regime,
                       added_unresolved = c11c$unresolved, added_key_mismatch = c11c$key_mismatch,
                       ledger_has_marker = all(C11_COLS %in% names(final)),
                       drift_status_n = c11_drift$status_n %||% 0L, drift_key_n = c11_drift$key_n %||% 0L),
            drift_hard = lapply(drift_hard, function(r) list(col = r$col, n = r$n, max_delta = r$max_delta, examples = r$examples)),
            drift_soft = lapply(drift_soft, function(r) list(col = r$col, n = r$n, max_delta = r$max_delta)))
cat(jsonlite::toJSON(rec, auto_unbox = TRUE), "\n", file = DRIFT_LOG, append = TRUE)

if (length(drift_hard)) {
  say("[m4-append] 종료 1 — 과거 재서술이 시도됐다(발행본 보존됨). 상류(매크로 국면 재생성) 확인 필요.\n")
  quit(status = 1)
}
say("[m4-append] OK\n")
quit(status = 0)
