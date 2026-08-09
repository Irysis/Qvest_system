#==============================================================================
# d4_double_vote_impact.R — 이중 투표가 **실제로** 무엇을 바꾸는가 (과제 C = 본체)
#
# 재는 것 (가정하지 않는다):
#   (1) 선언 cluster 중 실제로 같은 풀에 동시 출현하는 쌍 수  ← 0 이면 이론적 위험
#   (2) 그중 자동 축약 가능(alias↔canonical) 쌍 수
#   (3) top-25 선별 멤버십이 정본 해석 전후로 바뀌는가 (몇 종)
#   (4) 중복이 가져가는 가중 비중 (SUE 3중 등록의 실제 표 수)
#
# 선별 규칙: 풀 전체 Z_Score_Aligned 의 종목별 평균 = EW 합성 → 상위 25.
#   ★이것은 전략이 아니라 **기전 프로브**다 (metric_type = diagnostic).
#   성과 수치를 주장하지 않는다 — 멤버십 변화만 센다.
#
# C15 준수: 전 구간 load_month_factors() 경유. parquet 직접 read 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/infra/factor_dedup_wiring_20260809")
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

reg <- .load_registry()
cat(sprintf("[d4] registry entries = %d\n", length(reg)))

# ── 선언 지도 ───────────────────────────────────────────────────────────────
ded <- rbindlist(lapply(names(reg), function(f) {
  d <- reg[[f]]$dedup
  if (is.null(d)) return(NULL)
  g <- function(k) { v <- d[[k]]; if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1] }
  data.table(factor = f, role = g("role"), cluster = g("cluster"), canonical = g("canonical"))
}), fill = TRUE)
cat(sprintf("[d4] 선언 팩터 %d / cluster %d / alias %d\n",
            nrow(ded), uniqueN(ded$cluster), sum(ded$role == "alias", na.rm = TRUE)))

MONTHS <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30",
                    "2018-06-29", "2022-06-30", "2026-06-30"))

# 정본 해석(패널 수준): alias 행은 **canonical 이 같은 패널에 있을 때만** 제거.
# canonical 부재 시 alias 를 남긴다 — 이름을 바꾸면 그 달 배출되지 않은 코드를
# 날조하게 된다.
.collapse <- function(dt, ded) {
  present <- unique(dt$Factor_Name)
  al <- ded[role == "alias" & !is.na(canonical)]
  drop <- al[factor %in% present & canonical %in% present, factor]
  list(kept = dt[!(Factor_Name %in% drop)], dropped = drop)
}

rows <- list(); memb <- list(); wt <- list()
for (sd_i in MONTHS) {
  sd_i <- as.Date(sd_i)
  dt <- load_month_factors(sig_date = sd_i)     # factor_names=NULL = 전 팩터 풀
  dt <- as.data.table(dt)
  pool <- sort(unique(dt$Factor_Name))
  asof <- attr(dt, "factor_db_asof_date")

  # (1) 동시 출현 — 선언 cluster 기준
  co <- ded[factor %in% pool & !is.na(cluster), .N, by = cluster][N >= 2L]
  n_pairs_co <- sum(co$N * (co$N - 1L) / 2L)
  # (2) 자동 축약 가능 쌍 (alias & canonical 동시 존재)
  al <- ded[role == "alias" & !is.na(canonical)]
  al_co <- al[factor %in% pool & canonical %in% pool]

  # (3) top-25 멤버십
  cmp <- function(d) {
    s <- d[, .(score = mean(Z_Score_Aligned, na.rm = TRUE), n_f = .N), by = Ticker]
    s <- s[n_f >= 30L]                       # 팩터 커버 최소 — 얕은 종목 배제
    setorder(s, -score)
    head(s$Ticker, 25L)
  }
  cl <- .collapse(dt, ded)
  t_before <- cmp(dt); t_after <- cmp(cl$kept)
  changed <- length(setdiff(t_before, t_after))

  # (4) 중복이 가져가는 표 — cluster 별 풀 내 멤버 수
  dupvotes <- ded[factor %in% pool & !is.na(cluster), .N, by = cluster][N >= 2L]
  excess <- sum(dupvotes$N - 1L)             # 정본 1표만 남길 때 사라지는 표 수

  cat(sprintf("\n[d4] %s (asof %s) 풀=%d팩터\n", sd_i, asof, length(pool)))
  cat(sprintf("   (1) 동시 출현 cluster=%d → 쌍=%d\n", nrow(co), n_pairs_co))
  cat(sprintf("   (2) alias↔canonical 동시 존재=%d쌍 %s\n", nrow(al_co),
              if (nrow(al_co)) paste0("[", paste(al_co$factor, "->", al_co$canonical,
                                                 collapse = ", "), "]") else ""))
  cat(sprintf("   (3) top-25 변화=%d종 (제거 alias %d종)\n", changed, length(cl$dropped)))
  cat(sprintf("   (4) 선언 cluster 초과 표 수=%d / 풀 %d = %.1f%%\n",
              excess, length(pool), 100 * excess / length(pool)))

  rows[[length(rows) + 1L]] <- data.table(
    sig_date = sd_i, asof = as.character(asof), pool_size = length(pool),
    n_cluster_copresent = nrow(co), n_pairs_copresent = n_pairs_co,
    n_alias_collapsible = nrow(al_co),
    alias_dropped = paste(cl$dropped, collapse = "|"),
    top25_changed = changed, excess_votes = excess,
    excess_pct = round(100 * excess / length(pool), 2))
  memb[[length(memb) + 1L]] <- data.table(
    sig_date = sd_i, before = paste(t_before, collapse = "|"),
    after = paste(t_after, collapse = "|"))
}
res <- rbindlist(rows)
fwrite(res, file.path(OUT, "d4_impact_by_month.csv"))
fwrite(rbindlist(memb), file.path(OUT, "d4_top25_membership.csv"))
cat("\n[d4] ===== 요약 =====\n"); print(res[, .(sig_date, pool_size, n_pairs_copresent,
                                                n_alias_collapsible, top25_changed, excess_votes)])
cat("\n[d4] ★0건이면 계측 사망부터 의심 — pool_size 가 0 이 아닌지 확인할 것\n")
