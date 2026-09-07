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
# ★무인 루프와의 충돌 규약 (도훈 2026-09-07):
#   Qvest_ReinforceAutoLoop(8분 주기)가 .cache/rawdata.parquet 을 읽는다. 재빌드 중
#   읽히면 절단된 파일을 볼 수 있으므로, --apply 는 06_Registry/reinforce_auto_config.json
#   의 enabled=false (킬스위치 하강) 를 **재도출로 확인**한 뒤에만 진행한다.
#
# 사용법 (dry-run):
#   cd <root> && Rscript -e 'source("02_Infrastructure/data/seam_scale_repair.R")'
# 실쓰기 (킬스위치 하강 후):
#   SEAM_REPAIR_APPLY=1 Rscript -e 'source("02_Infrastructure/data/seam_scale_repair.R")'
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

if (!exists("PROJECT_ROOT")) source("02_Infrastructure/config.R")
source(file.path(DATA_DIR, "seam_scale_guard.R"))

SEAM_REPAIR_RAWDATA <- file.path(CACHE_DIR, "rawdata.parquet")

# ★seam_detect() 는 2026-09-07 에 **가드 정본(seam_scale_guard.R)으로 이관**했다.
#   소비자가 셋(이 도구 · incremental_update_file 의 덮어쓰기 후 재검사 · 우선순위 배관)이라
#   한쪽에만 두면 다음 사람이 또 한쪽만 고친다. 위 source() 로 이미 들어와 있다.

#' 무인 루프 킬스위치 재도출 (진술이 아니라 파일에서).
seam_autoloop_enabled <- function(root = PROJECT_ROOT) {
  p <- file.path(root, "06_Registry", "reinforce_auto_config.json")
  if (!file.exists(p)) return(NA)
  isTRUE(jsonlite::fromJSON(p)$enabled)
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

  if (!file.exists(raw_path)) stop("[seam_repair] rawdata 부재: ", raw_path)
  raw <- as.data.table(read_parquet(raw_path))
  raw[, Date := as.Date(Date)]
  cat(sprintf("  rawdata: %s rows | %s ~ %s\n", format(nrow(raw), big.mark = ","),
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

  if (!apply_writes) {
    cat("[seam_repair] DRY-RUN 종료 — rawdata.parquet 미변경.\n")
    return(invisible(list(seams = seams, reports = reports, applied = FALSE)))
  }

  # ── 실쓰기 ────────────────────────────────────────────────────────────────
  bak <- file.path(CACHE_DIR, sprintf("rawdata_pre_seamguard_%s.parquet",
                                      format(Sys.Date(), "%Y%m%d")))
  if (!file.exists(bak)) { file.copy(raw_path, bak); cat(sprintf("  백업: %s\n", basename(bak))) }
  else cat(sprintf("  백업 존재(재사용): %s\n", basename(bak)))

  for (lbl in names(reports)) raw <- seam_apply_actions(raw, reports[[lbl]])

  setorder(raw, Date, Ticker)
  tmp <- paste0(raw_path, ".tmp", Sys.getpid())
  write_parquet(raw, tmp)
  n_tmp <- nrow(read_parquet(tmp))          # "썼다" 와 "읽을 수 있는 것을 썼다" 는 다르다
  if (n_tmp != nrow(raw)) { file.remove(tmp); stop("[seam_repair] tmp 검증 실패 — 정본 미갱신") }
  if (file.exists(raw_path)) file.remove(raw_path)
  file.rename(tmp, raw_path)
  cat(sprintf("[seam_repair] APPLY 완료: %s rows\n", format(nrow(raw), big.mark = ",")))
  invisible(list(seams = seams, reports = reports, applied = TRUE))
}

.seam_repair_apply_flag <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  isTRUE("--apply" %in% a) || identical(Sys.getenv("SEAM_REPAIR_APPLY"), "1")
}

if (!identical(Sys.getenv("SEAM_REPAIR_NO_AUTORUN"), "1")) {
  invisible(seam_repair_run(apply_writes = .seam_repair_apply_flag()))
}
