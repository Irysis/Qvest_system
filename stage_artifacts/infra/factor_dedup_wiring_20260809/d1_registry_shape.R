#==============================================================================
# d1_registry_shape.R — registry dedup 선언 구조 실측
# 목적: dedup 블록의 실제 shape / role 분포 / cluster 구성 / 선언 쌍 수를 센다.
#       (문서 주장 "기선언 224쌍" 을 재서 확인한다 — 가정하지 않는다)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "infra", "factor_dedup_wiring_20260809")
REG  <- file.path(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")

reg <- fromJSON(REG, simplifyVector = FALSE)
cat(sprintf("[d1] registry entries = %d\n", length(reg)))

# ── 어느 키 아래에 dedup 정보가 사는가 (dedup vs labels 오배치 확인) ────────
has_dedup  <- vapply(reg, function(e) !is.null(e$dedup), logical(1))
lab_dedup  <- vapply(reg, function(e) {
  L <- e$labels
  !is.null(L) && (!is.null(L$cluster) || !is.null(L$canonical) ||
                  !is.null(L$deprecated_for_selection))
}, logical(1))
cat(sprintf("[d1] dedup 블록 보유 = %d / labels 안에 dedup류 키 = %d\n",
            sum(has_dedup), sum(lab_dedup)))
if (any(lab_dedup)) {
  cat("[d1] ★labels 안에 dedup류 키를 가진 팩터: ",
      paste(names(reg)[lab_dedup], collapse = ", "), "\n")
}

# ── dedup 블록 상세 ─────────────────────────────────────────────────────────
rows <- rbindlist(lapply(names(reg), function(f) {
  d <- reg[[f]]$dedup
  if (is.null(d)) return(NULL)
  gv <- function(k) {
    v <- d[[k]]
    if (is.null(v) || length(v) == 0L) NA_character_ else as.character(v)[1]
  }
  gl <- function(k) {
    v <- d[[k]]
    if (is.null(v) || length(v) == 0L) NA_character_
    else paste(as.character(unlist(v)), collapse = "|")
  }
  data.table(
    factor      = f,
    status      = {
      s <- reg[[f]]$lifecycle$status
      if (is.null(s)) NA_character_ else as.character(s)[1]
    },
    role        = gv("role"),
    cluster     = gv("cluster"),
    canonical   = gv("canonical"),
    aliases     = gl("aliases"),
    partners    = gl("partners"),
    adjudicated = gv("adjudicated"),
    keys        = paste(sort(names(d)), collapse = ",")
  )
}), fill = TRUE)

cat("\n[d1] role 분포:\n"); print(rows[, .N, by = role][order(-N)])
cat("\n[d1] status 분포 (dedup 보유분):\n"); print(rows[, .N, by = status][order(-N)])
cat(sprintf("\n[d1] distinct cluster = %d\n", uniqueN(rows$cluster, na.rm = TRUE)))

# ── cluster 크기 → 쌍 수 ────────────────────────────────────────────────────
cl <- rows[!is.na(cluster), .(n_members = .N,
                              members = paste(sort(factor), collapse = "+"),
                              roles   = paste(role, collapse = "|")),
           by = cluster][order(-n_members)]
cl[, n_pairs := n_members * (n_members - 1L) / 2L]
cat(sprintf("[d1] cluster 멤버십으로 유도되는 쌍 수 합계 = %d\n", sum(cl$n_pairs)))
cat("\n[d1] cluster 크기 분포:\n"); print(cl[, .N, by = n_members][order(-n_members)])
cat("\n[d1] 3+ 멤버 cluster:\n"); print(cl[n_members >= 3L])

fwrite(rows, file.path(OUT, "d1_dedup_rows.csv"))
fwrite(cl,   file.path(OUT, "d1_dedup_clusters.csv"))

# ── alias 무결성: canonical 이 실재하고 canonical role 인가 ─────────────────
al <- rows[role == "alias"]
al[, canon_exists := canonical %in% names(reg)]
al[, canon_role := vapply(canonical, function(c0) {
  if (is.na(c0) || is.null(reg[[c0]])) return(NA_character_)
  r <- reg[[c0]]$dedup$role
  if (is.null(r)) NA_character_ else as.character(r)[1]
}, character(1))]
cat(sprintf("\n[d1] alias 수 = %d / canonical 실재 = %d / canonical 이 role=canonical = %d\n",
            nrow(al), sum(al$canon_exists), sum(al$canon_role %in% "canonical")))
if (nrow(al[!(canon_role %in% "canonical")])) {
  cat("[d1] ★canonical 이 canonical role 이 아닌 alias:\n")
  print(al[!(canon_role %in% "canonical"), .(factor, canonical, canon_role)])
}
fwrite(al, file.path(OUT, "d1_alias_integrity.csv"))

# ── 대상 5쌍의 현 선언 상태 ─────────────────────────────────────────────────
targets <- c("C01_SUE", "C09_Earnings_Surprise_Sq", "C10_SUE_Persistence",
             "C04_ESBR", "C13_Revision_Breadth_3m",
             "C11_Earnings_Streak", "M25_Earnings_Mom_Streak")
cat("\n[d1] 대상 7팩터 현 상태:\n")
for (t in targets) {
  e <- reg[[t]]
  cat(sprintf("  %-28s present=%-5s status=%-10s dedup=%s\n", t,
              !is.null(e),
              if (is.null(e)) "-" else as.character(e$lifecycle$status %||% NA),
              if (is.null(e) || is.null(e$dedup)) "NONE"
              else paste(sort(names(e$dedup)), collapse = ",")))
}
cat("[d1] done\n")
