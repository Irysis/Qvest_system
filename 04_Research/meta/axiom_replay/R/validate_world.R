# validate_world.R — 세계 빌더 양성 대조 (사전등록 §3 P0-a')
# 재구성한 배치가 레인 로그의 실제 batch_start 와 맞는가.
source("R/build_world.R")

ar_lane_batches <- function(log_path = "C:/qm_cache/reinforce_auto_log.jsonl") {
  if (!file.exists(log_path)) return(NULL)
  ln <- readLines(log_path, warn = FALSE)
  ln <- grep('"event":"batch_start"', ln, fixed = TRUE, value = TRUE)
  out <- lapply(ln, function(x) {
    j <- tryCatch(fromJSON(x, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(j) || is.null(j$codes)) return(NULL)
    data.frame(ts = .ar_ts(j$ts), block = as.character(j$block %||% NA),
               n_cells = as.integer(j$n_cells %||% NA),
               codes = paste(sort(strsplit(as.character(j$codes), ",")[[1]]), collapse = ","),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), out))
}

#' 재구성 배치 집합 (트리별)
ar_recon_batches <- function(ws) {
  out <- lapply(ws, function(w) {
    s <- split(w$nodes, w$nodes$batch)
    do.call(rbind, lapply(s, function(b) data.frame(
      base_id = w$base_id, batch = b$batch[1],
      ts = min(b$opened_at, na.rm = TRUE), block = b$block[1], n_cells = nrow(b),
      codes = paste(sort(b$cell_code), collapse = ","), stringsAsFactors = FALSE)))
  })
  do.call(rbind, out)
}

#' 대조 — 코드 집합 일치 ∧ 시각 tol 분 이내
ar_batch_match <- function(lane, recon, tol_min = 90) {
  if (is.null(lane) || !nrow(lane)) return(NULL)
  lane$matched <- FALSE; lane$why <- "no_recon_with_same_codes"
  for (i in seq_len(nrow(lane))) {
    cand <- recon[recon$codes == lane$codes[i], , drop = FALSE]
    if (!nrow(cand)) next
    dt <- abs(as.numeric(difftime(cand$ts, lane$ts[i], units = "mins")))
    if (any(is.finite(dt) & dt <= tol_min)) { lane$matched[i] <- TRUE; lane$why[i] <- "ok" }
    else lane$why[i] <- sprintf("codes_ok_time_off_%.0fmin", suppressWarnings(min(dt, na.rm = TRUE)))
  }
  lane
}
