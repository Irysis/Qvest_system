#!/usr/bin/env Rscript
# test_basis_regression_guard.R — **표적 이설 2026-09-07 저녁**
#
# 구판(같은 날 아침)은 "xlsx 가 naver 구간을 덮으면 stop" 을 검사했다.
# 그 방향은 도훈 설계와 **반대**였다:
#   "퀀티와이즈 데이터가 있으면 최우선, 네이버는 최신 보충. 퀀티가 업데이트되면 네이버
#    데이터를 퀀티 기준으로 바꿔라." + 후속 확인('분할 종목이 5배 달라지는데?') → "퀀티 그대로 덮기".
# ⇒ **덮기는 정상 경로다.** 막을 것은 덮기가 아니라 "덮은 뒤 새 경계에서 조정기준 단절을
#    아무도 안 보는 상태" 다. 그래서 이 파일의 검사 명제를 통째로 옮긴다.
#
# 검사 명제 (양방향):
#   A. 퀀티가 네이버 구간을 덮으면 **통과**한다 (과잉 차단 없음)
#   B. 덮은 **직후** 이음매 재검사가 실제로 돌고 조정기준 단절이 잡힌다
#   C. 경계가 **이동**하면 새 경계에서 잡힌다 (부분 덮기 · 고정 씨앗 창 밖까지)
#   D. 우선순위 **설정**을 바꾸면 판정이 따라 움직인다 (하드코딩 아님을 실증)
#   E. 위반 주입 — 재검사 호출을 제거하면 조작된 -80%% 하루수익률이 살아남는다(빨강)
#
# ★검사는 운영 상태를 빌리지 않는다: 샌드박스 ROOT + 합성 픽스처. 운영 .cache 미접근.
# ★소스 좌표(행번호·변수명)를 못박지 않는다 — 의미 앵커로 블록을 재도출한다.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m,
                                                     if (nzchar(why)) paste0(" - ", why) else "", "\n") }
fin <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"basis_regression_guard","pass":%d,"fail":%d,"total":%d}\n',
              PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
suppressWarnings(suppressMessages(library(data.table)))

ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DATA_DIR_REAL <- file.path(ROOT, "02_Infrastructure/data")
SRC <- file.path(DATA_DIR_REAL, "incremental_update_file.R")
PRI_JSON <- file.path(ROOT, "06_Registry/rawdata_source_priority.json")

## ── 0. 블록 재도출 — 소비 파일에서 **실제로 도는 코드**를 잘라 실행한다 ───────
ln <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
A_ST <- "update_dates <- unique(all_long$Date)"
A_EN <- "# BM_Ret 매핑"
st <- grep(A_ST, ln, fixed = TRUE); en <- grep(A_EN, ln, fixed = TRUE)
if (length(st) == 1L && length(en) == 1L && en[1] > st[1])
  ok(sprintf("A0 병합 블록 추출 (%d줄)", en[1] - st[1])) else {
  ng("A0 병합 블록을 못 찾았다 — 표적 상실"); fin() }
BLK <- ln[st[1]:(en[1] - 1L)]

## ── 1. 샌드박스 ROOT — 사이드카가 운영 .cache 로 새지 않게 격리 ──────────────
SBX <- file.path(tempdir(), paste0("basisguard_sbx_", Sys.getpid()))
mk_sbx <- function(pri_json_text = NULL) invisible(.mk_sbx(pri_json_text))
.mk_sbx <- function(pri_json_text = NULL) {
  unlink(SBX, recursive = TRUE)
  dir.create(file.path(SBX, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(SBX, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(SBX, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  writeLines("# sandbox marker", file.path(SBX, "02_Infrastructure/hooks/qvest_hook_router.py"))
  invisible(file.copy(file.path(DATA_DIR_REAL, "seam_guard_config.json"),
            file.path(SBX, "02_Infrastructure/data/seam_guard_config.json"), overwrite = TRUE))
  if (is.null(pri_json_text)) {
    invisible(file.copy(PRI_JSON, file.path(SBX, "06_Registry/rawdata_source_priority.json"), overwrite = TRUE))
  } else {
    writeLines(pri_json_text, file.path(SBX, "06_Registry/rawdata_source_priority.json"),
               useBytes = TRUE)
  }
  SBX
}

## ── 2. 합성 픽스처 ───────────────────────────────────────────────────────────
#   A_CONT  : 전 구간 조정기준 동일 → on_scale
#   A_BREAK : 퀀티 5000 vs naver 1000 → 경계에서 ratio 0.2 (1/5 분할 지문)
TK <- c("A_CONT", "A_BREAK")
CQ <- c(A_CONT = 1000, A_BREAK = 5000); CN <- c(A_CONT = 1000, A_BREAK = 1000)
mk_raw <- function(s_qw, s_nv) {
  q <- CJ(Date = s_qw, Ticker = TK, sorted = FALSE)[, `:=`(Close = CQ[Ticker], source = "quantiwise")]
  n <- CJ(Date = s_nv, Ticker = TK, sorted = FALSE)[, `:=`(Close = CN[Ticker], source = "naver")]
  r <- rbind(q, n)
  r[, `:=`(Open = Close, High = Close, Low = Close, Vol = 1e6, Size = 1e11, Ret = NA_real_)]
  setorder(r, Date, Ticker); r[]
}
mk_upd <- function(d) {
  u <- CJ(Date = d, Ticker = TK, sorted = FALSE)[, `:=`(Close = CQ[Ticker], source = "quantiwise_update")]
  u[, `:=`(Open = Close, High = Close, Low = Close, Vol = 1e6, Size = 1e11)]; u[]
}
S_QW <- as.Date(c("2026-08-26", "2026-08-27", "2026-08-28"))
S_NV_SHORT <- as.Date(c("2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04"))
S_NV_LONG  <- as.Date(c("2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04",
                        "2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11"))

#' 블록을 격리 환경에서 실행. sbx 를 PROJECT_ROOT 로 심어 사이드카를 가둔다.
run_block <- function(raw, all_long, blk = BLK, sbx = SBX) {
  ge <- globalenv()
  old_pr <- if (exists("PROJECT_ROOT", envir = ge, inherits = FALSE))
    get("PROJECT_ROOT", envir = ge) else NULL
  old_qm <- Sys.getenv("QM_ROOT", unset = NA_character_)
  assign("PROJECT_ROOT", sbx, envir = ge); Sys.setenv(QM_ROOT = sbx)
  # 설정 캐시가 이전 케이스의 값을 물고 있으면 D(설정 경유)가 거짓 초록이 된다 — 매번 재로드
  for (nm in c(".rsp_cfg_cache", ".seam_cfg_cache"))
    if (exists(nm, envir = ge, inherits = FALSE)) rm(list = nm, envir = ge)
  for (f in c("rawdata_source_priority.R", "seam_scale_guard.R"))
    sys.source(file.path(DATA_DIR_REAL, f), envir = ge)
  e <- new.env(parent = ge)
  assign("raw", copy(raw), envir = e); assign("all_long", copy(all_long), envir = e)
  assign("DATA_DIR", DATA_DIR_REAL, envir = e)
  log <- character(0)
  res <- tryCatch({
    log <- capture.output(eval(parse(text = paste(blk, collapse = "\n")), envir = e),
                          type = "output")
    list(err = NULL, dt = get("raw", envir = e))
  }, error = function(x) list(err = conditionMessage(x), dt = NULL))
  if (!is.null(old_pr)) assign("PROJECT_ROOT", old_pr, envir = ge)
  if (!is.na(old_qm)) Sys.setenv(QM_ROOT = old_qm) else Sys.unsetenv("QM_ROOT")
  c(res, list(log = paste(log, collapse = "\n")))
}
ret_of <- function(dt, d, tk) {
  if (is.null(dt)) return(NA_real_)
  v <- dt[Date == as.Date(d) & Ticker == tk]$Ret
  if (!length(v)) NA_real_ else v[1]
}

## ── A. 양성 — 퀀티가 네이버 구간을 덮는 것은 정상 경로다 ─────────────────────
cat("=== A. 양성 — 퀀티가 네이버 구간을 덮으면 통과한다 ===\n")
mk_sbx()
rawA <- mk_raw(S_QW, S_NV_SHORT); updA <- mk_upd(as.Date(c("2026-08-31", "2026-09-01", "2026-09-02")))
rA <- run_block(rawA, updA)
if (is.null(rA$err)) ok("A1 덮기가 stop 없이 진행된다 (구판의 역행 차단은 폐기됐다)") else
  ng("A1 덮기가 막혔다 — 도훈 설계와 반대", rA$err)
if (!is.null(rA$dt) && identical(sort(unique(as.character(
      rA$dt[Date %in% updA$Date]$source))), "quantiwise_update"))
  ok("A2 덮은 구간의 source 가 전부 quantiwise_update — 퀀티가 정본") else
  ng("A2 덮은 구간에 naver 가 남았다",
     paste(unique(rA$dt[Date %in% updA$Date]$source), collapse = ","))
if (grepl("우선순위로 보존 0 rows", rA$log, fixed = TRUE))
  ok("A3 현행 표에서 보존 0행 — quantiwise_update 가 naver 를 이긴다") else
  ng("A3 보존 행수 보고가 없다/0이 아니다")

## ── B. 덮은 직후 재검사가 실제로 돈다 ────────────────────────────────────────
cat("=== B. 덮은 직후 이음매 재검사가 실제로 돈다 ===\n")
if (grepl("경계 신설/이동: 2026-09-03 (quantiwise_update -> naver)", rA$log, fixed = TRUE))
  ok("B1 새 경계 09-03 을 재도출해 보고한다") else
  ng("B1 새 경계 보고 없음 — 재도출이 안 돌았다")
if (grepl("adjustment_basis_break", rA$log, fixed = TRUE))
  ok("B2 조정기준 단절을 판정한다 (adjustment_basis_break)") else
  ng("B2 단절이 판정되지 않았다")
sc_dir <- file.path(SBX, ".cache", "seam_scale_guard")
sc <- if (dir.exists(sc_dir)) list.files(sc_dir, pattern = "^seam_.*\\.json$") else character(0)
if (length(sc) >= 2L) ok(sprintf("B3 이음매 사이드카 %d건 기록 (조용한 통과 없음)", length(sc))) else
  ng("B3 사이드카가 안 남았다 — 재검사가 실제로 돌았다는 증거 부재")
pr_dir <- file.path(SBX, ".cache", "rawdata_source_priority")
if (dir.exists(pr_dir) && length(list.files(pr_dir, pattern = "^priority_.*\\.json$")))
  ok("B4 우선순위 판정 사이드카 기록") else ng("B4 우선순위 사이드카 부재")
rb <- ret_of(rA$dt, "2026-09-03", "A_BREAK")
if (!is.na(rb) && abs(rb) < 1e-9) ok("B5 새 경계의 조작된 하루수익률이 0 으로 재정렬됐다") else
  ng("B5 새 경계 Ret 이 처리 안 됨", sprintf("Ret=%s", format(rb)))

## ── C. 경계 이동 — 고정 씨앗 창 **밖**으로 나가도 잡는다 ─────────────────────
cat("=== C. 경계가 이동하면 새 경계에서 잡는다 ===\n")
mk_sbx()
rawC <- mk_raw(S_QW, S_NV_LONG)
updC <- mk_upd(as.Date(c("2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04",
                         "2026-09-07", "2026-09-08", "2026-09-09")))
rC <- run_block(rawC, updC)
if (is.null(rC$err)) ok("C0 부분 덮기가 진행된다") else ng("C0 부분 덮기 실패", rC$err)
if (grepl("경계 신설/이동: 2026-09-10", rC$log, fixed = TRUE))
  ok("C1 이동한 경계 09-10 을 재도출한다 (min(update_dates)=08-31 창 밖)") else
  ng("C1 이동한 경계를 못 찾았다 — 날짜를 박은 가드는 여기서 죽는다")
rc10 <- ret_of(rC$dt, "2026-09-10", "A_BREAK")
if (!is.na(rc10) && abs(rc10) < 1e-9)
  ok("C2 창 밖 새 경계의 단절이 처리됐다 (Ret 0)") else
  ng("C2 창 밖 경계가 미처리", sprintf("Ret=%s", format(rc10)))
## 조작된 -0.8 이 남아 있으면 그건 통과가 아니라 오염이다
if (is.na(rc10) || abs(rc10 + 0.8) > 1e-9) ok("C3 조작된 -80pct 하루수익률이 남지 않았다") else
  ng("C3 -0.8 이 그대로 살아남았다")

## ── D. 설정 경유 실증 — 표를 바꾸면 판정이 따라 움직인다 ─────────────────────
cat("=== D. 우선순위 설정을 바꾸면 판정이 따라 움직인다 ===\n")
pj <- readLines(PRI_JSON, encoding = "UTF-8", warn = FALSE)
# naver 를 최상위로: rank 60 -> 5 (문자열 치환은 fixed — 정규식 이스케이프 함정 회피)
i_nv <- grep('"source": "naver"', pj, fixed = TRUE)
if (!length(i_nv)) { ng("D0 naver 항목을 못 찾았다 — 정본 스키마 변경?"); fin() }
i_rk <- i_nv[1] + 1L
if (!grepl('"rank": 60', pj[i_rk], fixed = TRUE)) {
  # 행 위치를 못박지 않는다 — naver 블록 안에서 rank 줄을 찾는다
  cand <- i_nv[1] + seq_len(4)
  i_rk <- cand[grepl('"rank"', pj[cand], fixed = TRUE)][1]
}
if (is.na(i_rk)) { ng("D0 naver rank 줄을 못 찾았다"); fin() }
pj2 <- pj; pj2[i_rk] <- sub("[0-9]+", "5", pj2[i_rk])
ok(sprintf("D0 설정 변조 준비: naver rank -> %s", trimws(pj2[i_rk])))
mk_sbx(pri_json_text = pj2)
rD <- run_block(rawA, updA)
if (is.null(rD$err)) ok("D1 표를 바꿔도 진행은 된다") else ng("D1 변조 설정에서 정지", rD$err)
if (!is.null(rD$dt) && "naver" %in% rD$dt[Date %in% updA$Date]$source)
  ok("D2 naver 가 상위가 되자 덮기가 보존으로 뒤집혔다 — 판정이 설정에서 온다") else
  ng("D2 설정을 바꿨는데 판정이 안 움직였다 — 하드코딩 의심")
if (grepl("incumbent_wins", rD$log, fixed = TRUE))
  ok("D3 판정 사유(incumbent_wins)를 로그가 말한다") else ng("D3 판정 사유 미표기")
## 설정 부재 = stop
mk_sbx(); invisible(file.remove(file.path(SBX, "06_Registry/rawdata_source_priority.json")))
rD2 <- run_block(rawA, updA)
if (!is.null(rD2$err) && grepl("우선순위 정본 부재", rD2$err, fixed = TRUE))
  ok("D4 설정 부재 = stop (조용한 기본값 없음)") else
  ng("D4 설정이 없는데 진행됐다", rD2$err %||% "(정지 안 함)")

## ── E. 위반 주입 — 재검사 호출을 제거하면 오염이 살아남는다 ──────────────────
cat("=== E. 위반 주입 — 재검사를 제거하면 빨강이어야 한다 ===\n")
i_seam <- grep("seam_seeds <- tryCatch({", BLK, fixed = TRUE)
i_rethd <- grep("# Ret 재계산", BLK, fixed = TRUE)
i_retln <- grep("raw[, Ret := Close / shift(Close) - 1, by = Ticker]", BLK, fixed = TRUE)
if (length(i_seam) && length(i_rethd) && length(i_retln)) {
  MUT <- c(BLK[1:(i_seam[1] - 1L)], BLK[i_rethd[1]:i_retln[1]])
  ok(sprintf("E0 변이체 구성: 재검사 블록 %d줄 제거", length(BLK) - length(MUT)))
  mk_sbx()
  rE <- run_block(rawC, updC, blk = MUT)
  rE10 <- ret_of(rE$dt, "2026-09-10", "A_BREAK")
  if (!is.na(rE10) && abs(rE10 + 0.8) < 1e-9)
    ok("E1 재검사 없는 변이체에서는 -80pct 가 살아남는다 — C2/C3 이 죽은 검사가 아니다") else
    ng("E1 변이체도 통과했다 — C2/C3 이 재검사가 아니라 다른 것을 재고 있다",
       sprintf("Ret=%s", format(rE10)))
  if (!grepl("adjustment_basis_break", rE$log %||% "", fixed = TRUE))
    ok("E2 변이체는 단절을 판정조차 하지 않는다 (양성 대조 성립)") else
    ng("E2 변이체가 여전히 판정한다 — 제거가 표적을 못 맞췄다")
} else ng("E0 변이체 앵커를 못 찾았다 — 위반 주입 불가")

## ── F. 배선 — 이 경로가 실제 위험 지점인가 ───────────────────────────────────
cat("=== F. 배선 ===\n")
if (any(grepl("rawdata_priority_decide", ln, fixed = TRUE)) &&
    any(grepl("rawdata_source_priority.R", ln, fixed = TRUE)))
  ok("F1 병합 지점이 우선순위 정본 리졸버를 경유한다") else ng("F1 리졸버 미경유")
if (any(grepl("seam_detect_changed", ln, fixed = TRUE)))
  ok("F2 경계를 날짜가 아니라 source 전환점 차집합에서 재도출한다") else
  ng("F2 경계 재도출 부재 — 날짜를 박은 가드는 이동을 못 버틴다")
if (!any(grepl("조정기준 역행 차단", ln, fixed = TRUE)))
  ok("F3 구판 역행 차단문이 남아 있지 않다 (죽은 표적 금지)") else
  ng("F3 폐기된 역행 차단이 소스에 남아 있다")
dr <- Filter(file.exists, file.path(ROOT, c("02_Infrastructure/data/daily_refresh.sh",
                                            "02_Infrastructure/ops/daily_refresh.sh")))
if (length(dr)) {
  drl <- sub("#.*$", "", readLines(dr[1], encoding = "UTF-8", warn = FALSE))
  if (any(grepl("incremental_update_all", drl, fixed = TRUE)))
    ok("F4 daily_refresh 가 이 경로를 부른다 — 가드가 실제 위험 지점에 있다") else
    ng("F4 daily_refresh 가 이 경로를 안 부른다 — 가드 위치 재검토")
} else ng("F4 daily_refresh.sh 를 못 찾았다")

unlink(SBX, recursive = TRUE)
fin()
