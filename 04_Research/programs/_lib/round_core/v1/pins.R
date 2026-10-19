## round_core v1 · pins — 판정에 닿는 전체를 한 함수로 계산 · 대조(사전등록 체크리스트 3 — '핀 = 판정에 닿는 전체')
##   등록(초안 · 등록) · 측정 직전 · 판정 시작(샤드 포함)이 같은 함수를 쓴다(현행은 라운드마다 3벌 복사 — register · precheck · evaluate).
##   대조 함수가 없는 핀 종류는 불일치로 센다(대조 없이 통과하지 않는다 · 양성 대조 없는 계기 금지).

## 템플릿 공통 운영 파일(측정 경로 · 칸 평가 · 등급 계약 · 설정) — 사양 pins.files 로 더하고, 칸 사양이 가리키는 엔진 파일은 자동으로 더한다
RC_PIN_FILES_DEFAULT <- c(
  "02_Infrastructure/alpha_search/run_paper_replication.R", "02_Infrastructure/backtest_harness.R", "02_Infrastructure/config.R",
  "02_Infrastructure/ops/rf_cell_worker.R", "02_Infrastructure/reinforcement/rf_cell_engine.R", "02_Infrastructure/reinforcement/rf_axes.R",
  "02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/essence_score.R", "02_Infrastructure/contracts/grade_v3.R",
  "02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/behavior_card.R", "02_Infrastructure/contracts/matched_controls.R",
  "02_Infrastructure/contracts/tilt_attribution.R", "02_Infrastructure/contracts/tilt_attribution_config.json",
  "02_Infrastructure/contracts/beta_controlled_alpha.R", "02_Infrastructure/worktask/constraint_defaults.json",
  "06_Registry/grade_v3.json", "06_Registry/matched_controls.json")
RC_PIN_PACKAGES <- c("data.table", "jsonlite", "arrow", "PerformanceAnalytics", "bbdetection")
RC_PIN_KINDS <- c("core", "files", "packages", "r_version")

## 코어 매니페스트 — 이 판(v1) 모듈 파일의 md5(정렬) → 매니페스트 md5(출시 판은 RELEASES.json 값과 같아야 한다)
rc_core_manifest <- function(dir = RC_DIR) {
  fs <- sort(list.files(dir, pattern = "[.](R|sh)$", full.names = FALSE))
  md <- vapply(fs, function(f) rc_md5(file.path(dir, f)), character(1))
  txt <- paste(sprintf("%s %s", fs, md), collapse = "\n")
  tf <- tempfile(); on.exit(unlink(tf), add = TRUE); writeLines(txt, tf, useBytes = TRUE)
  list(version = RC_VERSION, files = as.list(setNames(unname(md), fs)), manifest_md5 = rc_md5(tf))
}

## 칸 사양이 가리키는 엔진 파일(base_signal.path) — 저장소 상대 경로로
rc_cell_engine_files <- function(spec, root = rc_root()) {
  out <- character(0)
  for (c in spec[["cells"]]) if (!is.null(c[["spec"]])) {
    cs <- rc_json_read(rc_abs(c[["spec"]], root))
    p <- cs[["base_signal"]][["path"]]
    if (!is.null(p) && nzchar(p)) out <- c(out, rc_rel(p, root))
  }
  unique(out)
}

rc_pins_compute <- function(spec, root = rc_root()) {
  files <- unique(c(RC_PIN_FILES_DEFAULT, unlist(spec[["pins"]][["files"]]), rc_cell_engine_files(spec, root),
                    unlist(lapply(spec[["cells"]], function(c) c[["spec"]])), spec[["ext"]] %||% character(0),
                    spec[["behavior_card_cfg"]] %||% character(0)))
  files <- files[nzchar(files)]
  miss <- files[!file.exists(rc_abs(files, root))]
  if (length(miss)) stop("[round_core pins] 핀 대상 파일 없음: ", paste(miss, collapse = ", "))
  pk <- vapply(RC_PIN_PACKAGES, function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_), character(1))
  list(core = rc_core_manifest(),
       files = lapply(sort(files), function(f) list(path = f, md5 = rc_md5(rc_abs(f, root)))),
       packages = as.list(pk), r_version = R.version$version.string)
}

## 대조 — 사전등록에 실린 핀(pins)을 지금 다시 계산해 비교 · 반환 = 불일치 설명(없으면 길이 0)
rc_pins_mismatches <- function(pins, root = rc_root()) {
  out <- character(0)
  unk <- setdiff(names(pins), RC_PIN_KINDS)
  if (length(unk)) out <- c(out, paste("대조 함수가 없는 핀 종류:", paste(unk, collapse = ",")))
  cm <- rc_core_manifest()
  if (!identical(pins[["core"]][["manifest_md5"]], cm$manifest_md5) || !identical(pins[["core"]][["version"]], cm$version))
    out <- c(out, sprintf("코어 판 · 매니페스트 불일치(등록 %s/%s · 지금 %s/%s)", pins[["core"]][["version"]] %||% "?",
                          substr(pins[["core"]][["manifest_md5"]] %||% "?", 1, 8), cm$version, substr(cm$manifest_md5, 1, 8)))
  for (f in pins[["files"]]) {
    p <- rc_abs(f[["path"]], root)
    if (!file.exists(p)) out <- c(out, paste("핀 파일 없음:", f[["path"]]))
    else if (!identical(rc_md5(p), f[["md5"]])) out <- c(out, paste("핀 파일 md5 변경:", f[["path"]]))
  }
  for (p in names(pins[["packages"]])) {
    now <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
    if (!identical(now, pins[["packages"]][[p]])) out <- c(out, sprintf("패키지 판 변경: %s %s → %s", p, pins[["packages"]][[p]] %||% "NA", now))
  }
  if (!identical(pins[["r_version"]], R.version$version.string)) out <- c(out, paste("R 판 변경:", pins[["r_version"]], "→", R.version$version.string))
  out
}
