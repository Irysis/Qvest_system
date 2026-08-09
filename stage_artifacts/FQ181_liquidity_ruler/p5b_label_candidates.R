## FQ-181 P5b — 후보 8건의 신원 해소 (path 로 원장 엔트리를 되짚는다)
## ★"미상 8건" 은 조치 불가능한 보고다 — 조치 불가능한 보고는 결국 무시된다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
QM <- gsub("\\\\","/",Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
CAND <- fread(file.path(OUT, "p5_flip_candidates.csv"))
J <- fromJSON("06_Registry/hypothesis_index.json", simplifyVector = FALSE)

## path 예: "/entries[37]/measurement/portfolio_alpha_t" → 조상 노드에서 식별자를 찾는다
resolve <- function(path) {
  parts <- strsplit(sub("^/", "", path), "/")[[1]]
  node <- J; ancestors <- list()
  for (p in parts) {
    if (grepl("\\[[0-9]+\\]$", p)) {
      nm <- sub("\\[[0-9]+\\]$", "", p); ix <- as.integer(sub(".*\\[([0-9]+)\\]$", "\\1", p))
      if (nzchar(nm)) node <- node[[nm]]
      node <- node[[ix]]
    } else node <- node[[p]]
    ancestors[[length(ancestors)+1L]] <- node
  }
  keys <- c("hypothesis_id","strategy_id","id","wt_id","title","hypothesis_signature",
            "family","verdict","status","measured_at","date")
  found <- list()
  for (a in rev(ancestors)) {
    if (is.list(a) && !is.null(names(a)))
      for (k in keys) if (is.null(found[[k]]) && !is.null(a[[k]]) && is.character(a[[k]][1]))
        found[[k]] <- a[[k]][1]
  }
  found
}

rows <- list()
for (i in seq_len(nrow(CAND))) {
  f <- tryCatch(resolve(CAND$path[i]), error = function(e) list())
  rows[[i]] <- data.table(
    port_t = CAND$port_t[i], dist = CAND$dist[i], side = CAND$side[i],
    hypothesis_id = f$hypothesis_id %||% NA_character_,
    strategy_id   = f$strategy_id %||% NA_character_,
    id            = f$id %||% NA_character_,
    family        = f$family %||% NA_character_,
    verdict       = f$verdict %||% NA_character_,
    status        = f$status %||% NA_character_,
    signature     = substr(f$hypothesis_signature %||% NA_character_, 1, 90),
    path          = CAND$path[i])
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a
E <- rbindlist(rows, fill = TRUE)
cat("=== ④ 뒤집힘 후보 8건 — 신원 ===\n")
print(E[, .(port_t, dist, side, strategy_id, hypothesis_id, family, verdict)], nrows = 20)
cat("\n--- signature (식별 보조) ---\n")
for (i in seq_len(nrow(E))) cat(sprintf("  [%d] t=%.4f  %s\n", i, E$port_t[i], E$signature[i]))
fwrite(E, file.path(OUT, "p5b_flip_candidates_labeled.csv"))
write_json(E, file.path(OUT, "p5b_flip_candidates_labeled.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p5b_flip_candidates_labeled.{csv,json}\n")
