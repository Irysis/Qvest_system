## P2R01 공통 정의 — measure.R · rx0_measure.R 가 같은 RX0 사양을 만들게 한 곳에 둔다
## RX0 = 기저 B6_36 그대로 · 같은 데이터 판본 대조(처방 아님 · 새 시행 아님 — 시행 수 = 계보 측정 수 + 기저 1)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
rc_md5 <- function(f) unname(as.character(tools::md5sum(f)))

# 계보 측정 시도 수(L1 · 2002.06975 · essence/grade 보유)
rc_lineage_trials <- function(root) {
  L1 <- jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  ents <- if (!is.null(L1$entries)) L1$entries else L1
  as.integer(sum(vapply(ents, function(e) if (identical(as.character(e$paper_key %||% ""), "2002.06975"))
    sum(vapply(e$attempts %||% list(), function(a) !is.null(a$essence) || !is.null(a$grade), logical(1))) else 0L, numeric(1))))
}

rc_rx0_spec <- function(P, round_id, n_lin) {
  base_spec <- jsonlite::fromJSON(file.path(P$round_dir, "base", "base_cell_spec.json"), simplifyVector = FALSE)
  SA0 <- list(selection_type = "sweep", family_root = base_spec$selection_accounting$family_root %||% NA_character_,
              lineage = c(paste0("RX_", round_id), unlist(base_spec$selection_accounting$lineage)),
              n_family_at_registration = as.integer(n_lin + 1L),
              n_trials_basis = sprintf("rx_pilot RX0: 기저 재측정(새 시행 아님) — L1 계보 측정 시도 %d + 기저 1", as.integer(n_lin)))
  rx_compile_spec(base_spec, list(), code = "P2R01_RX0", label = "기저 재측정(같은 판본 대조)",
                  idea = sprintf("[처방 루프 v0 · %s · RX0] 기저 B6_36 그대로 — 같은 데이터 판본 대조(처방 아님)", round_id),
                  selection_accounting = SA0)
}

rc_write_spec <- function(sp, f) {
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
  rc_md5(f)
}

# 칸 1개 측정 — 정본 셀 워커(원장 미개방 · L-code 미발행 · 텔레그램 없음 · close_t1)
rc_measure_cell <- function(root, spec_path, code, res_dir) {
  dir.create(res_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(res_dir, paste0(code, ".json"))
  if (file.exists(out) && isTRUE(jsonlite::fromJSON(out)$ok)) { cat("[측정] 이미 있음:", code, "\n"); return(invisible(0L)) }
  t0 <- Sys.time()
  rc <- system2("Rscript", c(file.path(root, "02_Infrastructure/ops/rf_cell_worker.R"), shQuote(spec_path), "1", code, shQuote(out)),
                stdout = file.path(res_dir, paste0(code, ".log")), stderr = file.path(res_dir, paste0(code, ".err.log")))
  cat(sprintf("[측정] %s rc=%s · %.1f분\n", code, rc, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(rc)
}
