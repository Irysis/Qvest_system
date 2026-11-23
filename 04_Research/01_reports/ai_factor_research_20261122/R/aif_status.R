## aif_status.R — 진행 상태 파일(.cache/aif_research/status.json). 작업이 단위마다 갱신하고, 진행 알림과 감시 셸이 읽는다.
## 실행 줄 — 빈 값 = 1단계(기존 경로 그대로) · "followup" = 2단계. 감시 셸(aif_run.py --track)이 AIF_TRACK 으로 넘긴다. 줄마다 상태 파일 · 단계 목록 · 직전 통 기록을 따로 쓴다.
aif_track <- function() Sys.getenv("AIF_TRACK", "")
aif_track_out <- function(name, track = aif_track(), root = aif_root(), cfg = aif_cfg(root)) if (nzchar(track)) aif_out(track, name, root = root, cfg = cfg) else aif_out(name, root = root, cfg = cfg)
aif_progress_cfg <- function(cfg, track = aif_track()) if (nzchar(track)) cfg[[track]]$progress else cfg$progress
aif_status_path <- function(root = aif_root(), cfg = aif_cfg(root)) aif_track_out("status.json", root = root, cfg = cfg)
aif_status_read <- function(root = aif_root(), cfg = aif_cfg(root)) {
  p <- aif_status_path(root, cfg)
  if (!file.exists(p)) return(list(stage_progress = list()))
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) list(stage_progress = list()))
}
aif_status_set <- function(..., root = aif_root(), cfg = aif_cfg(root)) {
  st <- aif_status_read(root, cfg); up <- list(...)
  for (k in names(up)) st[[k]] <- up[[k]]
  st$updated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  g <- gc(FALSE); st$ram_gb <- round(sum(g[, 2]) / 1024, 2)          # 이 R 프로세스가 쓰는 메모리(대략)
  st$peak_ram_gb <- max(c(st$peak_ram_gb %||% 0, round(sum(g[, 6]) / 1024, 2)))
  tryCatch(aif_write_json(st, aif_status_path(root, cfg)),          # 상태 파일은 진행 표시일 뿐이다 — 못 써도 작업을 죽이지 않는다
           error = function(e) message("[aif] 상태 파일을 쓰지 못했다(작업은 계속): ", conditionMessage(e)))
  invisible(st)
}
## 단계 시작 — part_from ~ part_to 는 이 실행이 그 단계 진행률의 어느 구간을 맡는지(한 단계를 여러 실행으로 나눌 때)
aif_stage_begin <- function(key, unit_total, unit_name, part_from = 0, part_to = 1, threads = NA, ...) {
  st <- aif_status_read(...)
  sp <- st$stage_progress %||% list(); sp[[key]] <- max(c(sp[[key]] %||% 0, part_from))
  aif_status_set(stage_key = key, stage_state = "running", wait_reason = NULL, error = NULL, unit_done = 0L, unit_total = as.integer(unit_total),
                 unit_name = unit_name, detail = NULL, part_from = part_from, part_to = part_to, threads = threads,
                 stage_started_at = if (identical(st$stage_key, key) && !is.null(st$stage_started_at)) st$stage_started_at else format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                 run_started_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), stage_progress = sp, pid = Sys.getpid(), ...)
}
aif_stage_unit <- function(unit_done, detail = NULL, ...) {
  st <- aif_status_read(...); key <- st$stage_key
  f <- (st$part_from %||% 0) + ((st$part_to %||% 1) - (st$part_from %||% 0)) * unit_done / max(1L, st$unit_total %||% 1L)
  sp <- st$stage_progress %||% list(); sp[[key]] <- min(1, max(c(sp[[key]] %||% 0, f)))
  aif_status_set(unit_done = as.integer(unit_done), detail = detail, stage_state = "running", stage_progress = sp, ...)
}
aif_stage_end <- function(done = TRUE, ...) {
  st <- aif_status_read(...); key <- st$stage_key
  sp <- st$stage_progress %||% list(); sp[[key]] <- if (isTRUE(done)) 1 else (st$part_to %||% 1)
  aif_status_set(stage_state = if (isTRUE(done)) "done" else "running", stage_progress = sp, detail = NULL, ...)
}
## 전체 진행률(0~1) = 단계 가중치 × 단계 안 진행률
aif_overall <- function(st, cfg, track = aif_track()) {
  sg <- aif_progress_cfg(cfg, track)$stages
  w <- vapply(sg, function(s) as.numeric(s$weight), 0); k <- vapply(sg, function(s) s$key, "")
  f <- vapply(k, function(x) as.numeric((st$stage_progress %||% list())[[x]] %||% 0), 0)
  sum(w * pmin(1, pmax(0, f))) / sum(w)
}
## 프로세스 우선순위를 '보통 이하'로 낮춘다(자식 프로세스도 물려받는다)
aif_low_priority <- function() invisible(tryCatch(tools::psnice(Sys.getpid(), 15L), error = function(e) NA))
