#!/usr/bin/env Rscript
## ============================================================================
## regen_audit_signal_panel_gc.R — R25 하네스 gc 추출 로직 교정 + 패널 재생성
##   (도훈 지시 2026-07-14: audit_signal_panel.parquet gc 오탐 위생 수리 · 데이터 위생만)
##
## 배경(실측 진단): R25 산출 audit_signal_panel.parquet 의 gc(going-concern) 플래그는 오탐.
##   원 생성 로직을 실측 역설계로 정확 재현(2786/2786 행 일치):
##     buggy gc = grepl(UNC, paste(emphs_matter, adt_reprt_spcmnt_matter, core_adt_matter))  [당기 행]
##   = 불확실성 disjunction(불확실/의심/…)만 매칭 + 필수 조건 '계속기업 AND' 누락 + KAM blob(core_adt_matter)
##     까지 포함. → KAM의 흔한 '추정/COVID/평가 불확실성'을 계속기업으로 오분류(196 gc=1).
##     예: A034730(SK) fy2025 canonical adt_opinion='적정의견'·계속기업 텍스트 0인데 panel gc=1.
##
## 교정 기준 = filing_delay_watch.R Part B(task #68) 클린 기준과 동일(단일 SOT):
##   gc = grepl("계속기업", txt) & grepl(UNC, txt),  txt = paste(emphs_matter, adt_reprt_spcmnt_matter)
##   (강조사항 ∪ 특기사항만. KAM blob 제외. 계속기업 텍스트 ∧ 불확실성 맥락 동시존재. benign 가정언급 제외)
##   대상 = 당기(current-term) 행. (ticker,fy)별 OR 집계.
##   결과: gc=1 196 → 12 (진짜 계속기업 doubt만: HMM/현대상선 fy2015-2020·대한항공 fy2020 COVID 등).
##
## 교정 범위(도훈 mandate): gc 컬럼만 교체. nonclean/has_emphs/has_kam/kam_count/rcept_dt/fy/ticker 불변.
##   R25 verdict(CONFIG_SCOPED_NEGATIVE) 불변 — 오탐이 보수 방향(exclusion 과다)이라 재판정 불요.
##   ⚠ 원 생성 스크립트는 ad-hoc inline으로 소실(FS·git 부재 확인). 본 스크립트가 교정 생성기 SOT.
##
## 규율: 단일스레드 · arrow io(2) · OneDrive temp-rename 쓰기 · 원본 .bak 백업(가역).
## 실행: cd stage_artifacts/WT_D20260714_001 && Rscript -e 'source("regen_audit_signal_panel_gc.R")'
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
arrow::set_io_thread_count(2L); setDTthreads(1L)

ROOT  <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT   <- file.path(ROOT, "stage_artifacts/WT_D20260714_001")
PANEL <- file.path(OUT, "audit_signal_panel.parquet")
CANON <- file.path(ROOT, "02_Infrastructure/data/dart_pledge_audit/t1_audit_opinion_fy2015_2025.parquet")
UNC   <- "불확실|의문|의구심|의심|존속능력|중대한 의심|중요한 불확실"   # filing_delay_watch Part B와 동일

## ---- 1. 기존 패널 로드 (gc 외 전 컬럼 authoritative) ----------------------
ap <- as.data.table(read_parquet(PANEL))
stopifnot(all(c("ticker","fy","gc") %in% names(ap)))
orig_cols   <- copy(names(ap))
snap        <- copy(ap)                          # 비-gc 컬럼 parity 대조용 스냅샷
orig_gc     <- ap$gc
ap[, ticker := as.character(ticker)]
ap[, sc := sub("^A", "", ticker)]                # 조인키(포맷 무관 6자리)
cat(sprintf("[load] panel rows=%d cols=%s\n", nrow(ap), paste(orig_cols, collapse=",")))
cat(sprintf("[load] BEFORE gc=1: %d / gc=0: %d\n", sum(orig_gc==1), sum(orig_gc==0)))

## ---- 2. canonical raw → 클린 gc 재도출 (당기 · (ticker,fy) OR) -------------
AO <- as.data.table(read_parquet(CANON))
AO[, qfy := suppressWarnings(as.integer(query_fy))]
AO[, sc  := sub("^A", "", as.character(ticker))]
AO <- AO[grepl("당기", bsns_year) & !is.na(qfy)]                 # current-term rows only (PIT: 당기)
AO[, txt := paste(emphs_matter, adt_reprt_spcmnt_matter)]        # 강조 ∪ 특기 (KAM blob 제외)
AO[, gc_clean := as.integer(grepl("계속기업", txt) & grepl(UNC, txt))]
gc_key <- AO[, .(gc_new = max(gc_clean)), by = .(sc, fy = qfy)]  # (ticker,fy)별 OR
cat(sprintf("[canon] 당기 rows=%d · clean gc=1 keys=%d\n", nrow(AO), gc_key[gc_new==1, .N]))

## ---- 3. gc 컬럼만 교체 (행 순서·기타 컬럼 불변; update-join) ---------------
ap[, gc_new := 0L]
ap[gc_key, on = .(sc, fy), gc_new := i.gc_new]
n_unmatched <- ap[!(sc %in% gc_key$sc), .N]      # canonical 당기 매치 없는 패널 행(gc=0 유지)

## ---- 4. 검증 게이트 (위반 시 abort — 쓰기 전) ------------------------------
new_gc <- ap$gc_new
added_fp   <- sum(new_gc == 1L & orig_gc == 0L)  # 신규 양성(있으면 안 됨: 클린 ⊆ 원)
removed_fp <- sum(new_gc == 0L & orig_gc == 1L)  # 제거된 오탐
a034730_after <- ap[sc == "034730", gc_new]
# 비-gc 컬럼 parity: gc/gc_new/sc 제외 전부 스냅샷과 동일해야 함
noncmp <- setdiff(orig_cols, "gc")
parity_ok <- all(vapply(noncmp, function(cc) identical(ap[[cc]], snap[[cc]]), logical(1)))

cat("\n==== VERIFICATION ====\n")
cat(sprintf("  clean gc=1 (AFTER)     : %d\n", sum(new_gc==1L)))
cat(sprintf("  removed false positives: %d  (196→%d 기대)\n", removed_fp, sum(new_gc==1L)))
cat(sprintf("  newly-added positives  : %d  (MUST be 0: 클린은 원 gc의 부분집합)\n", added_fp))
cat(sprintf("  panel rows w/o 당기 match: %d (gc=0 유지)\n", n_unmatched))
cat(sprintf("  A034730(SK) gc AFTER   : {%s}  (MUST all be 0)\n", paste(unique(a034730_after), collapse=",")))
cat(sprintf("  non-gc columns unchanged: %s\n", parity_ok))
stopifnot(added_fp == 0L)                        # 오탐만 제거, 신규 양성 0
stopifnot(all(a034730_after == 0L))              # 사례 종목 교정 확인
stopifnot(isTRUE(parity_ok))                     # gc 외 무변경 보증
stopifnot(sum(new_gc==1L) >= 1L)                 # 진짜 계속기업 doubt 보존(전멸 아님)

## ---- 5. gc 확정 + 컬럼/타입/순서 원복 -------------------------------------
ap[, gc := as.integer(gc_new)]
ap[, c("gc_new","sc") := NULL]
setcolorder(ap, orig_cols)
stopifnot(identical(names(ap), orig_cols))

## ---- 6. 백업 + OneDrive temp-rename 쓰기 (arrow mmap 회피) ------------------
BAK <- file.path(OUT, "audit_signal_panel.parquet.bak_pre_gcfix")
if (!file.exists(BAK)) file.copy(PANEL, BAK)     # 원본 1회 백업(가역)
rm(AO, snap); invisible(gc())                    # 읽기 mmap 해제
tmp <- paste0(PANEL, ".tmp_", Sys.getpid())
write_parquet(ap, tmp)
if (file.exists(PANEL)) file.remove(PANEL)
invisible(file.rename(tmp, PANEL))
cat(sprintf("\n[write] panel 재생성 완료 → %s (backup: %s)\n", basename(PANEL), basename(BAK)))

## ---- 7. 교정 로그 JSON -----------------------------------------------------
log_obj <- list(
  task = "R25 audit_signal_panel gc 오탐 교정 (도훈 지시 2026-07-14)",
  panel = PANEL, backup = BAK,
  root_cause = paste0("생성기 gc = grepl(UNC, paste(emphs_matter,adt_reprt_spcmnt_matter,core_adt_matter)) ",
                      "[당기] — 불확실성 disjunction만·'계속기업 AND' 누락·KAM blob 포함 → 오탐 196. ",
                      "실측 역설계로 2786/2786 정확 재현."),
  fix_criteria = "filing_delay_watch.R Part B: grepl('계속기업',txt) & grepl(UNC,txt), txt=paste(emphs_matter,adt_reprt_spcmnt_matter), 당기, (ticker,fy) OR",
  gc_before = sum(orig_gc==1L), gc_after = sum(new_gc==1L),
  false_positives_removed = removed_fp, newly_added = added_fp,
  a034730_fixed = all(a034730_after==0L),
  non_gc_columns_unchanged = parity_ok,
  columns_touched = "gc (only)",
  verdict_impact = "R25 CONFIG_SCOPED_NEGATIVE 불변 — 오탐은 exclusion-과다(보수) 방향. 재판정 불요(도훈 mandate).",
  downstream_note = paste0("measurement_results.json / canonical_exclusion.json 은 교정 전 gc(196)로 산출된 ",
                           "R25 종결 산출물(historical record) — 도훈 '재판정 불요' 지시로 미변경. 패널만 위생 수리."),
  generator_provenance = "원 생성 스크립트는 ad-hoc inline으로 소실 확인 → 본 스크립트가 교정 생성기 SOT")
write_json(log_obj, file.path(OUT, "gc_correction_log.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat(sprintf("[log] gc_correction_log.json 기록 (gc %d→%d, FP 제거 %d)\n",
            sum(orig_gc==1L), sum(new_gc==1L), removed_fp))
cat("[DONE]\n")
