#!/usr/bin/env Rscript
## m4_epoch_reinit.R — m4 발행 원장 epoch 재초기화 (구판 보관 → 새 epoch 기준선)
##
## **왜** (결정 PIT-C11-P2-AUX ② · 도훈 2026-09-24 "m4 발행 원장 구판 보관 후 C11 epoch 로 재초기화"):
##   m4 발행 원장(06_Registry/m4_published/m4_panel_published.parquet)은 append-only 다 — 과거 행은 절대 덮지
##   않는다(m4_append_only.R · 도훈 2026-08-13). 그런데 PIT C11 판정(04_Research/01_reports/pit_c11_20260924/
##   PIT_C11_verdict_20260924.md V-04)이 **발행 이력 전체가 해외 정보 공표 전 값 위에서 계산됐다**고 확정했다
##   (홀딩월 행이 M−1 월말 unified 행 = 미국 월말 종가·미공표 주간값을 씀). 그 이력을 정본으로 붙들면 BOOK_0001 게이트
##   이력 재산출(결정 PIT-C11-BOOK0001)이 불가능하다. append-only 를 깨는 유일한 합법 경로가 이 스크립트다:
##   구판을 **지우지 않고 보관**하고, C11 표식이 붙은 재생성본으로 새 epoch 의 기준선을 세운다.
##
## **하는 일** (기본 = dry-run · 운영 트리에 아무것도 쓰지 않는다):
##   1. 전제 검사 — 재생성본(운영 패널 = factor_engine 산출)이 새 epoch 기준선 자격이 있는가
##        · C11 표식 3열 실재 · 결정행(월 첫 행, Date <= AS_OF) 전부 verified/no_regime(unresolved 0)
##        · verified 행 c11_info_cutoff <= Date · c11_regime_key == 현행 규칙 epoch · AS_OF 행 실재
##   2. 드리프트 귀속 보고 — 구 원장 대비 결정값(weight_str1715·weight_cash) 변경 행과, 그 행에서 **무엇이**
##      바뀌었는지(국면 입력 · BOCPD 입력 · decay 입력 · 입력 불변 = 엔진 로직 변경)를 재도출한다.
##      ★재초기화는 C11 교정만 들이는 게 아니다 — 현행 엔진이 구판 원장 이후 바뀐 로직(예: 2026-08-30 BOCPD
##        가드 수리 · PROVENANCE_bocpd_guard_defect.md 가 '되돌리지 말 것'으로 묶어 둔 4개월)도 함께 들어온다.
##        '입력 불변 = 로직' 행은 그 몫이다. 적용 전에 사람이 이 귀속을 읽어야 한다(그래서 기본이 dry-run).
##   3. --apply '<사유>' 일 때만: 구판 보관(복사 + md5 대조) → 원장·PROVENANCE 이관(rename, 삭제 없음) →
##      m4_append_only.R --as-of X --init(단일 기록자 — 원장 쓰기는 그 스크립트만 한다) → 사후 검증 →
##      PROVENANCE_c11_epoch.md 작성 · m4_drift_log.jsonl 에 epoch_reinit 기록. 실패하면 이관을 되돌린다.
##
## 사용:  Rscript m4_epoch_reinit.R --as-of 2026-09-01 [--report <json 경로>] [--apply '<사유>'] [--root <루트>]
## 종료:  0 OK(dry-run = 전제 충족) / 2 입력·환경 / 5 전제 미충족 / 6 init 실패(이관 원복) / 7 사후 검증 실패(이관 원복)
if (suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))) %in% 1L) Sys.setenv(ARROW_IO_THREADS = "2")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen = 999)

a <- commandArgs(TRUE)
getarg <- function(k, d = NA) { i <- which(a == k); if (length(i) && length(a) > i[1]) a[i[1] + 1L] else d }
say <- function(...) cat(sprintf(...))
die <- function(code, msg) { cat(sprintf("[m4-reinit] ERROR %s\n", msg)); quit(status = code) }
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

ROOT <- getarg("--root", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
ROOT <- gsub("\\\\", "/", ROOT)
AS_OF <- as.Date(getarg("--as-of", NA))
REASON <- getarg("--apply", NA)
APPLY <- "--apply" %in% a
REPORT <- getarg("--report", NA)
if (is.na(AS_OF)) die(2, "--as-of YYYY-MM-01 필수")
if (as.integer(format(AS_OF, "%d")) != 1L) die(2, sprintf("--as-of 는 월 1일이어야 함: %s", AS_OF))
if (APPLY && (is.na(REASON) || !nzchar(trimws(REASON)) || startsWith(REASON, "--")))
  die(2, "--apply 에는 사유 문자열이 필요하다 (예: --apply 'PIT-C11-P2-AUX ②: ...') — 사유 없는 재초기화 금지")

PANEL <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")
PUBDIR <- file.path(ROOT, "06_Registry/m4_published")
PUB <- file.path(PUBDIR, "m4_panel_published.parquet")
SIDE <- file.path(PUBDIR, "m4_published_ledger.jsonl")
DRIFT_LOG <- file.path(PUBDIR, "m4_drift_log.jsonl")
GATE <- file.path(ROOT, "02_Infrastructure/regime/m4_append_only.R")
FA <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES <- file.path(ROOT, "06_Registry/fred_availability_rules.json")

C11_COLS <- c("c11_info_cutoff", "c11_regime_key", "c11_status")
DECISION_COLS <- c("weight_str1715", "weight_cash")
## 귀속 그룹 — 재생성 드리프트의 원인 축. 열 이름은 생산자 factor_engine.R result_cols 그대로(없는 열은 건너뛴다).
GROUPS <- list(
  regime = c("Regime_Score_lag", "Cash_Pct_lag", "MSM_Crisis_Prob_lag", "combined_regime"),
  bocpd  = c("bocpd_change_prob_lag", "bocpd_short_run_mass_lag", "bocpd_expected_runlen_lag", "bocpd_norm"),
  decay  = c("decay_signal", "decay_norm", "decay_R2", "decay_lambda", "decay_rolling_sr_recent", "decay_rolling_sr_base"),
  base   = c("ret_net"))

rp <- function(p) as.data.table(read_parquet(p, mmap = FALSE))
for (p in c(PANEL, GATE, FA, RULES)) if (!file.exists(p)) die(2, sprintf("필수 파일 부재: %s", p))
if (!file.exists(PUB)) die(2, sprintf("발행 원장 부재 — 재초기화가 아니라 최초 초기화다: Rscript %s --as-of %s --init", GATE, AS_OF))

## ---- 현행 규칙 epoch ----
KEY_NOW <- tryCatch({
  e <- new.env(parent = globalenv()); suppressMessages(suppressWarnings(sys.source(FA, envir = e)))
  as.character(e$fred_avail_rules_meta(RULES)$regime_key)
}, error = function(err) NA_character_)
if (is.na(KEY_NOW) || !nzchar(KEY_NOW)) die(2, "현행 규칙 epoch 판독 불가 — fred_availability.R / rules json 확인")
say("[m4-reinit] ROOT=%s · AS_OF=%s · 현행 epoch %s · 모드 %s\n", ROOT, AS_OF, KEY_NOW,
    if (APPLY) "APPLY" else "dry-run(쓰기 없음)")

fresh <- rp(PANEL); fresh[, Date := as.Date(Date)]; setorder(fresh, Date)
old <- rp(PUB); old[, Date := as.Date(Date)]; setorder(old, Date)
say("[m4-reinit] 재생성본 n=%d (%s~%s) · 구 원장 n=%d (%s~%s)\n", nrow(fresh), min(fresh$Date), max(fresh$Date),
    nrow(old), min(old$Date), max(old$Date))

## ---- 1. 전제 검사 (새 epoch 기준선 자격) ----
## 기준선 후보 = m4_append_only.R 의 --init 과 같은 규칙: 월 첫 행 · Date <= AS_OF
base <- fresh[Date <= AS_OF]
base <- base[!duplicated(format(Date, "%Y-%m"))]
fails <- character(0)
miss <- setdiff(C11_COLS, names(base))
if (length(miss)) {
  fails <- c(fails, sprintf("P1 재생성본에 C11 표식 열 없음(%s) — factor_engine 을 C11 상류 위에서 다시 돌리지 않았다", paste(miss, collapse = ",")))
} else {
  st <- as.character(base$c11_status); cut <- as.Date(base$c11_info_cutoff); key <- as.character(base$c11_regime_key)
  n_un <- sum(is.na(st) | st == "unresolved"); n_bad <- sum(!is.na(st) & !(st %in% c("verified", "no_regime", "unresolved")))
  ver <- which(st %in% "verified")
  n_cut <- sum(is.na(cut[ver]) | cut[ver] > base$Date[ver])
  n_key <- sum(is.na(key[ver]) | key[ver] != KEY_NOW)
  n_nr <- sum(st %in% "no_regime")
  say("[m4-reinit] 기준선 %d행 — verified %d · no_regime %d · unresolved/NA %d · 상태 미지 %d · 컷오프 위반 %d · epoch 불일치 %d\n",
      nrow(base), length(ver), n_nr, n_un, n_bad, n_cut, n_key)
  if (n_un) fails <- c(fails, sprintf("P2 unresolved %d행 — 상류 unified 월간 C11 표식이 factor_engine 에 닿지 않았다(국면 원장 병합의 표식 삭제 여부 확인)", n_un))
  if (n_bad) fails <- c(fails, sprintf("P2 c11_status 값이 계약 밖 %d행", n_bad))
  if (n_cut) fails <- c(fails, sprintf("P3 verified 인데 c11_info_cutoff > Date(또는 결측) %d행 — PIT C11 위반", n_cut))
  if (n_key) fails <- c(fails, sprintf("P4 epoch 키 ≠ 현행(%s) %d행 — 옛 규칙 판 상류(재빌드 후 재생성 필요)", KEY_NOW, n_key))
  ## no_regime 은 국면 미사용 워밍업 행이어야 한다(국면 점수가 있는데 no_regime 이면 계약 밖)
  if (n_nr && "Regime_Score_lag" %in% names(base) && any(!is.na(base$Regime_Score_lag[st %in% "no_regime"])))
    fails <- c(fails, "P5 no_regime 행에 Regime_Score_lag 값이 있다 — 생산자 계약 밖")
}
if (!any(base$Date == AS_OF)) fails <- c(fails, sprintf("P6 기준선에 AS_OF(%s) 행 없음 — factor_engine 이 그 달을 만들지 못했다", AS_OF))
if (!nrow(base)) fails <- c(fails, "P7 기준선 0행")
## P8 (2026-09-25 적대 검증 M4AE NB-1): AS_OF < 구 원장 최신 발행 월이면 그 뒤에 발행된 달(예: 10-01 행)이 새 원장·운영 패널·
##   m4_extended 에서 빠진 채 exit 0 으로 끝났다(미러 재현). 재초기화 AS_OF 는 '최신 발행 월' 이상이어야 한다(월 단위 대조 —
##   발행 행 날짜는 월 첫 거래일이라 월 1일과 다를 수 있다).
.old_last_m <- if (nrow(old)) max(format(old$Date, "%Y-%m")) else NA_character_
if (!is.na(.old_last_m) && .old_last_m > format(AS_OF, "%Y-%m"))
  fails <- c(fails, sprintf("P8 AS_OF(%s) < 구 원장 최신 발행 월(%s) — 그 뒤 발행된 달이 새 원장에서 빠진다(--as-of 를 최신 발행 월로)",
                            format(AS_OF, "%Y-%m"), .old_last_m))

## ---- 2. 드리프트 귀속 (구 원장 → 새 기준선) ----
num_changed <- function(x, y) { x <- as.numeric(x); y <- as.numeric(y)
  xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & abs(x - y) > 1e-12) }
common <- intersect(as.character(old$Date), as.character(base$Date))
o <- old[as.character(Date) %in% common][order(Date)]
n <- base[as.character(Date) %in% common][order(Date)]
dec_chg <- Reduce(`|`, lapply(intersect(DECISION_COLS, intersect(names(o), names(n))), function(cl) num_changed(o[[cl]], n[[cl]])),
                  rep(FALSE, nrow(o)))
## ★귀속 규칙 = 배경 드리프트 대비 (문턱 수치 없음 · 데이터에서 재도출).
##   재생성은 결정이 안 바뀐 행에서도 입력을 조금씩 움직인다(매크로 국면 재생성 — m4_append_only.R drift_soft).
##   그래서 "입력이 바뀌었다(>0)" 는 원인 증거가 아니다. 열마다 **결정 불변 행들의 최대 |Δ|(배경)** 를 재고,
##   결정이 바뀐 행에서 그 배경을 넘은 열만 '실질 변경'으로 센다. 실질 변경 그룹이 없으면 =
##   입력은 배경 수준으로만 움직였는데 결정이 바뀜 → 엔진 로직 변경 몫(logic).
##   (실측 2026-09-24 미러: 현행 엔진 × 운영 원장 — 2020-06/07/09/10 4행이 logic = BOCPD 가드 수리 ·
##    2008-02/2009-05 는 Cash_Pct_lag 가 배경 0 을 넘어 regime · 2026-09 는 bocpd·국면이 배경의 수십 배 = 입력 완결.)
gcols <- lapply(GROUPS, function(cols) intersect(cols, intersect(names(o), names(n))))
absd <- function(cl) { x <- as.numeric(o[[cl]]); y <- as.numeric(n[[cl]]); d <- abs(x - y); d[xor(is.na(x), is.na(y))] <- Inf; d }
unch <- which(!dec_chg)
BG <- vapply(unlist(gcols, use.names = FALSE), function(cl) { d <- absd(cl)[unch]; d <- d[is.finite(d)]
  if (length(d)) max(d) else 0 }, numeric(1))
mat_cols <- function(i) {
  cl <- unlist(gcols, use.names = FALSE)
  if (!length(cl)) return(character(0))
  d <- vapply(cl, function(c) absd(c)[i], numeric(1))
  cl[!is.na(d) & d > BG[cl] + 1e-12]
}
attr_lab <- vapply(seq_len(nrow(o)), function(i) {
  mc <- mat_cols(i)
  g <- names(GROUPS)[vapply(names(GROUPS), function(k) any(gcols[[k]] %in% mc), logical(1))]
  if (length(g)) paste(g, collapse = "+") else "logic(입력 배경 수준)"
}, character(1))
chg_rows <- which(dec_chg)
attr_tab <- if (length(chg_rows)) as.list(table(attr_lab[chg_rows])) else list()
examples <- if (length(chg_rows)) lapply(chg_rows[seq_len(min(40L, length(chg_rows)))], function(i) {
  mc <- mat_cols(i)
  list(Date = as.character(o$Date[i]), w_old = o$weight_str1715[i], w_new = n$weight_str1715[i], cause = attr_lab[i],
       material = as.list(setNames(vapply(mc, function(c) absd(c)[i], numeric(1)), mc)))
}) else list()
only_old <- setdiff(as.character(old$Date), as.character(base$Date))
only_new <- setdiff(as.character(base$Date), as.character(old$Date))
say("[m4-reinit] 공통 %d행 · 결정값 변경 %d행 · 구 원장에만 %d행 · 새 기준선에만 %d행\n",
    length(common), length(chg_rows), length(only_old), length(only_new))
if (length(chg_rows)) {
  say("[m4-reinit] 변경 귀속(배경 드리프트 대비): %s\n", paste(sprintf("%s=%d", names(attr_tab), unlist(attr_tab)), collapse = " · "))
  for (x in examples[seq_len(min(12L, length(examples)))])
    say("   %s  weight_str1715 %.4f -> %.4f  [%s]%s\n", x$Date, x$w_old, x$w_new, x$cause,
        if (length(x$material)) paste0("  실질Δ ", paste(sprintf("%s=%.4g", names(x$material), unlist(x$material)), collapse = ",")) else "")
  if (any(attr_lab[chg_rows] == "logic(입력 배경 수준)"))
    say("   ★'logic' = 입력은 배경 수준으로만 움직였는데 결정이 바뀐 행 — 구판 원장 이후 엔진 로직 변경 몫(C11 이 아니다).\n     예: 2026-08-30 BOCPD 가드 수리(PROVENANCE_bocpd_guard_defect.md '되돌리지 말 것'). 재초기화는 이것까지 이력에 들인다.\n")
}
if (length(only_old)) say("   구 원장에만: %s\n", paste(head(only_old, 12), collapse = " "))
## (NB-2) 라벨 이동 달 — 같은 달이 구 원장엔 d1, 새 기준선엔 d2 로 찍힌 경우(예: 2026-08-01 → 08-03). '결정값 변경' 집계는 공통 날짜만
##   보므로 여기서 따로 대조해 보고한다(도훈 확인 자료).
label_moved <- local({
  mo <- setNames(only_old, format(as.Date(only_old), "%Y-%m")); mn <- setNames(only_new, format(as.Date(only_new), "%Y-%m"))
  ms <- intersect(names(mo), names(mn))
  lapply(ms, function(m) { a <- old[as.character(Date) == mo[[m]]][1]; b <- base[as.character(Date) == mn[[m]]][1]
    list(month = m, old_date = mo[[m]], new_date = mn[[m]],
         w_old = if ("weight_str1715" %in% names(a)) a$weight_str1715 else NA, w_new = if ("weight_str1715" %in% names(b)) b$weight_str1715 else NA,
         decision_changed = any(vapply(intersect(DECISION_COLS, intersect(names(a), names(b))), function(cl) isTRUE(num_changed(a[[cl]], b[[cl]])), logical(1)))) })
})
for (x in label_moved) say("   라벨 이동 %s: %s → %s  weight_str1715 %.4f -> %.4f%s\n", x$month, x$old_date, x$new_date,
                           as.numeric(x$w_old), as.numeric(x$w_new), if (isTRUE(x$decision_changed)) "  ★결정값 변경" else "")

report <- list(tool = "m4_epoch_reinit.R", background_drift = as.list(BG), ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), as_of = as.character(AS_OF),
               root = ROOT, rules_key = KEY_NOW, mode = if (APPLY) "apply" else "dry_run", reason = if (APPLY) REASON else NA,
               n_old = nrow(old), n_new = nrow(base), n_common = length(common),
               decision_changed = length(chg_rows), attribution = attr_tab, examples = examples,
               only_old = only_old, only_new = only_new, label_moved = label_moved, preconditions_failed = fails,
               old_has_c11 = all(C11_COLS %in% names(old)))
if (!is.na(REPORT)) {
  dir.create(dirname(REPORT), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(report, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 12), REPORT, useBytes = TRUE)
  say("[m4-reinit] 보고서 → %s\n", REPORT)
}
if (length(fails)) {
  say("\n[m4-reinit] ★전제 미충족 %d건 — 재초기화하지 않는다\n", length(fails))
  for (f in fails) say("   · %s\n", f)
  quit(status = 5)
}
if (!APPLY) {
  say("[m4-reinit] dry-run OK — 전제 충족. 적용: Rscript %s --as-of %s --apply '<사유>'\n",
      "02_Infrastructure/regime/m4_epoch_reinit.R", AS_OF)
  quit(status = 0)
}

## ---- 3. 적용 ----
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
slug <- gsub("[^A-Za-z0-9._-]+", "_", sub("^c11_avail:", "", KEY_NOW))   # 경로 길이(Windows 260자) — 접두 제거
ARCH <- file.path(PUBDIR, "_epoch_archive", sprintf("%s_to_%s", ts, slug))
dir.create(ARCH, recursive = TRUE, showWarnings = FALSE)
keep <- c(PUB, SIDE, DRIFT_LOG, list.files(PUBDIR, pattern = "^PROVENANCE_.*\\.md$", full.names = TRUE))
keep <- keep[file.exists(keep)]
for (f in keep) if (!file.copy(f, file.path(ARCH, basename(f)), overwrite = FALSE, copy.date = TRUE))
  die(2, sprintf("구판 보관 복사 실패: %s", f))
md5_src <- tools::md5sum(keep); md5_dst <- tools::md5sum(file.path(ARCH, basename(keep)))
if (!identical(unname(md5_src), unname(md5_dst))) die(2, sprintf("구판 보관 md5 불일치 — 중단(원장 무변경): %s", ARCH))
report$archive <- ARCH; report$archive_md5 <- as.list(setNames(unname(md5_src), basename(keep)))
writeLines(toJSON(report, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 12),
           file.path(ARCH, "reinit_drift_report.json"), useBytes = TRUE)
say("[m4-reinit] 구판 보관 %d파일 → %s (md5 대조 OK)\n", length(keep), ARCH)

## 이관(rename — 삭제 없음): 원장 + 구 epoch 를 서술하는 PROVENANCE(새 원장에는 거짓이 된다)
moved <- c(PUB, list.files(PUBDIR, pattern = "^PROVENANCE_.*\\.md$", full.names = TRUE))
moved_to <- file.path(ARCH, paste0(basename(moved), ".live_at_reinit"))
ok_mv <- file.rename(moved, moved_to)
restore <- function() {
  for (i in seq_along(moved)) if (file.exists(moved_to[i])) {
    if (file.exists(moved[i])) file.rename(moved[i], file.path(ARCH, paste0(basename(moved[i]), ".failed_init")))
    file.rename(moved_to[i], moved[i])
  }
  ## 사이드카는 init 이 새 기준선으로 덮었을 수 있다 — 보관본으로 되돌린다(git 추적 사료)
  sb <- file.path(ARCH, basename(SIDE))
  if (file.exists(sb)) invisible(file.copy(sb, SIDE, overwrite = TRUE, copy.date = TRUE))
  say("[m4-reinit] 원복 — 원장·PROVENANCE·사이드카 복귀. 운영 패널·m4_extended 가 새 기준선 내용일 수 있다:\n")
  say("            Rscript 02_Infrastructure/regime/m4_append_only.R --as-of %s  (병합 경로 = 발행본으로 재동기화)\n", AS_OF)
}
if (!all(ok_mv)) { restore(); die(2, "원장 이관(rename) 실패 — 원복") }

## 단일 기록자: 원장 쓰기는 m4_append_only.R 만 한다
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
say("[m4-reinit] init 호출: %s --as-of %s --init\n", GATE, AS_OF)
rc <- system2(RS, c("--no-save", shQuote(GATE), "--as-of", as.character(AS_OF), "--init"), stdout = "", stderr = "")
if (!identical(as.integer(rc), 0L)) { restore(); die(6, sprintf("m4_append_only.R --init rc=%s — 이관 원복(운영 패널·m4_extended 는 .regen_* 백업 확인)", rc)) }

## ---- 4. 사후 검증 ----
new <- rp(PUB); new[, Date := as.Date(Date)]; setorder(new, Date)
pv <- character(0)
if (!all(C11_COLS %in% names(new))) {
  pv <- c(pv, "새 원장에 C11 표식 열 없음")
} else {
  if (any(!(new$c11_status %in% c("verified", "no_regime")))) pv <- c(pv, "새 원장에 unresolved/미지 상태 행")
  vv <- new$c11_status %in% "verified"
  if (any(is.na(new$c11_info_cutoff[vv]) | as.Date(new$c11_info_cutoff[vv]) > new$Date[vv])) pv <- c(pv, "컷오프 > Date 행")
  if (any(is.na(new$c11_regime_key[vv]) | new$c11_regime_key[vv] != KEY_NOW)) pv <- c(pv, "epoch 불일치 행")
}
if (!identical(as.character(new$Date), as.character(base$Date))) pv <- c(pv, sprintf("새 원장 날짜 집합 ≠ 기준선(%d vs %d)", nrow(new), nrow(base)))
pan <- rp(PANEL); pan[, Date := as.Date(Date)]
if (!isTRUE(all.equal(as.data.frame(pan[order(Date)]), as.data.frame(new), check.attributes = FALSE)))
  pv <- c(pv, "운영 패널 ≠ 새 원장(동기화 실패)")
if (length(pv)) {
  say("[m4-reinit] ★사후 검증 실패: %s\n", paste(pv, collapse = " · "))
  restore(); die(7, "이관 원복 — 새 원장은 _epoch_archive 의 .failed_init 로 보관")
}

## ---- 5. 새 epoch 표지 + 기록 ----
prov <- file.path(PUBDIR, "PROVENANCE_c11_epoch.md")
writeLines(c(
  "# m4 발행 원장 — C11 epoch 기준선",
  "",
  sprintf("**발효**: %s · **규칙 epoch**: `%s` · **AS_OF**: %s · **행**: %d (%s ~ %s)", format(Sys.time(), "%Y-%m-%d %H:%M"),
          KEY_NOW, AS_OF, nrow(new), min(new$Date), max(new$Date)),
  sprintf("**사유**: %s", REASON),
  sprintf("**구판 보관**: `%s` (원장·사이드카·드리프트 로그·PROVENANCE 복사 + md5 대조 · 이관본 *.live_at_reinit)",
          sub(paste0("^", ROOT, "/"), "", ARCH)),
  "",
  "이 원장의 전 행은 C11 가용시점 결합 상류(unified 월간 avail 표식) 위에서 현행 factor_engine.R 로 재생성된 값이다.",
  "구판 원장(수리 전 상류 · 2026-08-30 BOCPD 가드 결함 구간 라벨 포함)의 수치는 보관본에서만 인용한다.",
  sprintf("재초기화 드리프트: 공통 %d행 중 결정값 변경 %d행 — 귀속 %s (상세 `reinit_drift_report.json`).",
          length(common), length(chg_rows),
          if (length(attr_tab)) paste(sprintf("%s=%d", names(attr_tab), unlist(attr_tab)), collapse = ", ") else "없음"),
  "",
  "이후 규칙 epoch 가 바뀌면 소비자(pg2 arm)가 epoch 불일치로 거부한다 — 상류 재빌드 뒤 이 스크립트로 다시 재초기화한다."),
  prov, useBytes = TRUE)
cat(toJSON(list(event = "epoch_reinit", ts = ts, as_of = as.character(AS_OF), reason = REASON, rules_key = KEY_NOW,
                archive = ARCH, n_old = nrow(old), n_new = nrow(new), decision_changed = length(chg_rows),
                attribution = attr_tab), auto_unbox = TRUE), "\n", file = DRIFT_LOG, append = TRUE)
say("[m4-reinit] OK — 새 epoch 기준선 %d행 · PROVENANCE_c11_epoch.md · drift log epoch_reinit 기록\n", nrow(new))
quit(status = 0)
