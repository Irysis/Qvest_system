#==============================================================================
# seam_scale_repair.R — RAWDATA 이음매 레벨 연속성 소급 정정 (기본 = dry-run)
#
# 도훈 승인 2026-09-07 (A안). seam_scale_guard.R 과 **같은 계약**으로 이미 적재된
# .cache/rawdata.parquet 의 과거 이음매를 재판정한다. 가드는 앞으로의 증분을 막고,
# 이 도구는 가드가 없던 시절에 들어온 이음매를 되돌린다.
#
# ★날짜를 박지 않는다. 이음매는 `source` 열의 전환점에서 **재도출**한다 —
#   경계는 증분 수출마다 전진하므로 날짜를 박은 국소 수리는 원리적으로 못 버틴다
#   (벤치 배관이 07-27 을 고치고 08-09 에 07-29 로 재발한 전례).
#
# ★2026-11-13 개정(원천 이음매 결함 수리 · 도훈 "원천 이음매 결함 수리를 바로 시작해주고"):
#   ① 이음매 처분 뒤 **전 이력 감사**(rawdata_seam_audit.R)를 같은 표에 돌린다 — 적재기와 같은 처분(새 기준 단절 = Ret NA).
#      건식 실행도 감사 결과를 보고한다(무엇이 차단될지).
#   ② APPLY 는 리프레시 배리어 writer 잠금 아래에서만(QVEST_SEAM_REPAIR_LOCKED=1 — seam_repair_locked.sh 가 잠금을 쥐고 켠다).
#      구 킬스위치(reinforce_auto_config.enabled)는 무인 레인을 막지 못했다(11-13 실측: enabled=false 인데 충실구현 레인 측정 중) —
#      측정 러너가 실제로 읽는 것은 배리어다. 킬스위치 검사는 남긴다(추가 안전망).
#   ③ 교체는 tmp → 이름 바꾸기 + **재시도**(Windows 는 매핑이 열린 파일의 교체를 거부한다 · 오류 1224) + 교체 **뒤 재판독 검증**
#      (구판은 file.remove 실패를 무시하고 "APPLY 완료"를 찍을 수 있었다 — 썼다 ≠ 바뀌었다).
#   ④ 파일 이름 대소문자 유지(.cache/RAWDATA.parquet — 지우고 새로 만들면 소문자 이름으로 바뀐다).
#
# 사용법 (dry-run):
#   cd <root> && Rscript -e 'source("02_Infrastructure/data/seam_scale_repair.R")'
# 실쓰기 (배리어 writer 잠금 아래):
#   bash 02_Infrastructure/data/seam_repair_locked.sh --apply
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

if (!exists("PROJECT_ROOT")) source("02_Infrastructure/config.R")
source(file.path(DATA_DIR, "seam_scale_guard.R"))
source(file.path(DATA_DIR, "rawdata_seam_audit.R"))

#' 실제 파일 이름(대소문자 그대로) — 없으면 기본 이름
.seam_repair_raw_path <- function() {
  hit <- list.files(CACHE_DIR, pattern = "^rawdata\\.parquet$", ignore.case = TRUE, full.names = TRUE)
  if (length(hit)) hit[1] else file.path(CACHE_DIR, "RAWDATA.parquet")
}
SEAM_REPAIR_RAWDATA <- .seam_repair_raw_path()

# ★seam_detect() 는 2026-09-07 에 **가드 정본(seam_scale_guard.R)으로 이관**했다.
#   소비자가 셋(이 도구 · incremental_update_file 의 덮어쓰기 후 재검사 · 우선순위 배관)이라
#   한쪽에만 두면 다음 사람이 또 한쪽만 고친다. 위 source() 로 이미 들어와 있다.

#' 무인 루프 킬스위치 재도출 (진술이 아니라 파일에서).
seam_autoloop_enabled <- function(root = PROJECT_ROOT) {
  p <- file.path(root, "06_Registry", "reinforce_auto_config.json")
  if (!file.exists(p)) return(NA)
  isTRUE(jsonlite::fromJSON(p)$enabled)
}

#' 저장된 파일의 이음매 창 Ret 이 메모리의 정정본과 같은가 — 교체 뒤 재판독 검증.
.seam_repair_verify_file <- function(path, expect, dates) {
  x <- as.data.table(read_parquet(path, col_select = tidyselect::all_of(c("Date", "Ticker", "Ret")), mmap = FALSE))
  x[, Date := as.Date(Date)]
  x <- x[Date %in% dates]
  m <- merge(expect[, .(Date, Ticker, Ret_e = Ret)], x, by = c("Date", "Ticker"), all = TRUE)
  ok_n <- nrow(m) == nrow(expect)
  same <- (is.na(m$Ret) & is.na(m$Ret_e)) | (!is.na(m$Ret) & !is.na(m$Ret_e) & abs(m$Ret - m$Ret_e) <= 1e-12)
  list(ok = isTRUE(ok_n && all(same)), n = nrow(m), n_diff = sum(!same))
}

seam_repair_run <- function(apply_writes = FALSE, raw_path = SEAM_REPAIR_RAWDATA) {
  cat("=== seam_scale_repair ", if (apply_writes) "[APPLY]" else "[DRY-RUN]", " ===\n", sep = "")
  cfg <- seam_guard_config()
  cat(sprintf("  설정: %s\n", cfg$config_path))
  cat(sprintf("  SEAM_MAX_RET=%.4g  SCALE_SNAP_TOL=%.4g  SCALE_FAMILY=%s  rescale_ret_enabled=%s\n",
              cfg$SEAM_MAX_RET, cfg$SCALE_SNAP_TOL, cfg$SCALE_FAMILY, cfg$rescale_ret_enabled))

  enabled <- seam_autoloop_enabled()
  cat(sprintf("  무인 루프 kill switch: reinforce_auto_config.enabled = %s\n", enabled))
  if (apply_writes && !identical(enabled, FALSE)) {
    stop("[seam_repair] APPLY 거부 — 무인 루프가 살아 있다(enabled=", enabled, "). ",
         "재빌드 중 rawdata.parquet 이 읽히면 절단본을 보게 된다. ",
         "킬스위치를 내린 뒤 다시 부를 것.")
  }
  if (apply_writes && !identical(Sys.getenv("QVEST_SEAM_REPAIR_LOCKED"), "1"))
    stop("[seam_repair] APPLY 거부 — 리프레시 배리어 writer 잠금 밖이다. ",
         "bash 02_Infrastructure/data/seam_repair_locked.sh --apply 로 부를 것(측정 러너가 읽는 것은 배리어다).")

  if (!file.exists(raw_path)) stop("[seam_repair] rawdata 부재: ", raw_path)
  raw <- as.data.table(read_parquet(raw_path, mmap = FALSE))
  raw[, Date := as.Date(Date)]
  cat(sprintf("  rawdata: %s | %s rows | %s ~ %s\n", basename(raw_path), format(nrow(raw), big.mark = ","),
              min(raw$Date), max(raw$Date)))

  seams <- seam_detect(raw)
  cat(sprintf("  이음매 재도출: %d건\n", nrow(seams)))
  for (i in seq_len(nrow(seams)))
    cat(sprintf("    %s : %s -> %s\n", seams$seam_date[i], seams$from[i], seams$to[i]))

  reports <- list()
  for (i in seq_len(nrow(seams))) {
    sd_ <- seams$seam_date[i]
    lbl <- sprintf("%s_to_%s", seams$from[i], seams$to[i])
    # ★창으로 훑는다 — 이음매 당일 값이 직전 수출본의 정지값 그대로여서 단절이
    #   하루 뒤에 나타나는 종목이 있다(실측 naver 경계 08-31 5건 / 09-01 8건).
    rep <- seam_scan_report(raw, seam_scan_dates(raw, sd_, cfg), cfg)
    seam_report_print(rep, lbl)

    key_raw <- paste0(as.character(raw$Date), "|", raw$Ticker)
    pos <- match(paste0(as.character(rep$tbl$Date), "|", rep$tbl$Ticker), key_raw)
    rep$ret_before <- ifelse(is.na(pos), NA_real_, raw$Ret[pos])
    tb <- copy(rep$tbl)[, ret_before := rep$ret_before]
    tb[, ret_after := fifelse(action == "block_ret", NA_real_,
                       fifelse(action == "rescale_ret", implied_ret, ret_before))]
    chg <- tb[action %in% c("block_ret", "rescale_ret")]
    cat(sprintf("    정정 대상 %d종 (block %d / rescale %d)\n", nrow(chg),
                tb[action == "block_ret", .N], tb[action == "rescale_ret", .N]))
    if (nrow(chg)) {
      show <- head(chg[order(-abs(ret_before))], 12)
      cat("    ── 전후 (|ret_before| 상위 12) ──\n")
      for (k in seq_len(nrow(show)))
        cat(sprintf("      %-9s %s %10.2f -> %s %10.2f  ratio %9.4f  scale %-6s  %-22s %s | ret %8.4f -> %s\n",
                    show$Ticker[k], show$anchor_date[k], show$anchor_close[k],
                    as.character(show$Date[k]), show$seam_close[k], show$ratio[k],
                    ifelse(is.na(show$canonical_scale[k]), "-", format(show$canonical_scale[k])),
                    show$verdict[k], show$action[k], show$ret_before[k],
                    ifelse(is.na(show$ret_after[k]), "NA", sprintf("%.4f", show$ret_after[k]))))
    }
    rep$tbl <- tb
    rep$label <- lbl
    reports[[lbl]] <- rep
    cat(sprintf("    사이드카: %s\n",
                seam_write_sidecar(rep, paste0(if (apply_writes) "apply_" else "dryrun_", lbl))))
    cat("\n")
  }

  # ── 전 이력 감사(같은 처분을 얹은 뒤) ─────────────────────────────────────────
  #   건식 실행 = 가벼운 사본(Date · Ticker · Close · Size · Ret)에 처분을 얹어 잰다 · APPLY = 본표에 얹고 잰 뒤 새 단절 차단.
  tgt <- if (apply_writes) raw else raw[, .(Date, Ticker, Close, Size, Ret)]
  for (lbl in names(reports)) tgt <- seam_apply_actions(tgt, reports[[lbl]])
  aud <- rsa_audit(tgt)
  rsa_print(aud, if (apply_writes) "repair_apply" else "repair_dryrun")
  cat(sprintf("  [seam_audit] 사이드카: %s\n", rsa_write_sidecar(aud, if (apply_writes) "repair_apply" else "repair_dryrun")))
  if (nrow(aud$days_alarm))
    cat("  ⚠ 처분 뒤에도 집단 극단 수익일이 남았다 — 차단 대상이 아니므로(어느 종목인지 모른다) 사람 확인이 필요하다\n")

  if (!apply_writes) {
    cat(sprintf("[seam_repair] DRY-RUN 종료 — %s 미변경 · 감사 차단 예정 %d행\n", basename(raw_path), nrow(aud$hits_new)))
    return(invisible(list(seams = seams, reports = reports, audit = aud, applied = FALSE)))
  }

  # ── 실쓰기 ────────────────────────────────────────────────────────────────
  raw <- rsa_block_new(tgt, aud)
  cat(sprintf("  [seam_audit] 새 기준 단절 차단 %d행(Ret := NA) · 채움 %d행 · 수동 등록부 강제 %d행\n", attr(raw, "seam_audit_blocked"),
              attr(raw, "seam_audit_filled"), attr(raw, "seam_audit_registry_fixed") %||% 0L))
  bak <- file.path(CACHE_DIR, sprintf("rawdata_pre_seamguard_%s.parquet", format(Sys.Date(), "%Y%m%d")))
  if (!file.exists(bak)) { stopifnot(file.copy(raw_path, bak)); cat(sprintf("  백업: %s\n", basename(bak))) }
  else cat(sprintf("  백업 존재(재사용): %s\n", basename(bak)))

  # 교체 뒤 재판독 범위 = 이 실행이 Ret 을 바꿀 수 있는 날 전부(이음매 창 · 새 · 알려진 · 비어 있던 단절 · 등록부 강제)
  vdates <- sort(unique(c(as.Date(unlist(lapply(reports, function(r) r$dates))), aud$hits_new$Date, aud$hits_known$Date,
                          aud$hits_blocked$Date, aud$registry_fix$Date)))
  expect <- raw[Date %in% vdates, .(Date, Ticker, Ret)]
  setorder(raw, Date, Ticker)
  tmp <- file.path(dirname(raw_path), sprintf(".%s.seamrepair.%d", basename(raw_path), Sys.getpid()))
  write_parquet(raw, tmp)
  n_tmp <- nrow(read_parquet(tmp, col_select = "Date", mmap = FALSE))   # "썼다" 와 "읽을 수 있는 것을 썼다" 는 다르다
  if (n_tmp != nrow(raw)) { file.remove(tmp); stop("[seam_repair] tmp 검증 실패 — 정본 미갱신") }
  tries <- as.integer(Sys.getenv("QVEST_SEAM_REPAIR_TRIES", "30")); wait_s <- as.numeric(Sys.getenv("QVEST_SEAM_REPAIR_WAIT_S", "20"))
  done <- FALSE
  for (t in seq_len(tries)) {
    done <- isTRUE(suppressWarnings(file.rename(tmp, raw_path)))   # Windows MoveFileEx(REPLACE_EXISTING) — 이름 대소문자 유지
    if (done) break
    cat(sprintf("  … 교체 실패(%d/%d) — 다른 프로세스가 파일을 잡고 있다(매핑) · %.0f초 뒤 재시도\n", t, tries, wait_s))
    Sys.sleep(wait_s)
  }
  if (!done) { file.remove(tmp); stop("[seam_repair] 교체 실패 — 정본 미갱신(백업 그대로 · 재시도 필요)") }
  v <- .seam_repair_verify_file(raw_path, expect, vdates)
  if (!v$ok) stop(sprintf("[seam_repair] 교체 뒤 재판독 불일치(%d/%d행) — 백업 %s 로 되돌릴 것", v$n_diff, v$n, basename(bak)))
  cat(sprintf("[seam_repair] APPLY 완료: %s rows · 교체 뒤 재판독 %d행 일치(이음매 창 %s)\n", format(nrow(raw), big.mark = ","),
              v$n, paste(as.character(range(vdates)), collapse = " ~ ")))
  invisible(list(seams = seams, reports = reports, audit = aud, applied = TRUE, backup = bak))
}

.seam_repair_apply_flag <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  isTRUE("--apply" %in% a) || identical(Sys.getenv("SEAM_REPAIR_APPLY"), "1")
}

if (!identical(Sys.getenv("SEAM_REPAIR_NO_AUTORUN"), "1")) {
  invisible(seam_repair_run(apply_writes = .seam_repair_apply_flag()))
}
