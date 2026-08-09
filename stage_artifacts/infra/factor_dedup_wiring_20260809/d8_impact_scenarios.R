#==============================================================================
# d8_impact_scenarios.R — 이중 투표 영향 실측 (과제 C 본체, 배선 후 재측정)
#
# 시나리오 4종을 같은 달·같은 선별 규칙 위에서 비교한다:
#   S0  현행(dedup 없음)                       — 오늘 실제로 도는 것
#   S1a alias 축약, **5쌍 등재 전** registry    — 배선만 했을 때
#   S1b alias 축약, 5쌍 등재 후 (= dedup=TRUE)  — 이 라운드 결과
#   S2  cluster 당 1종만 (redundant 까지 접음)  — 이중 투표의 **상한**(배선 대상 아님)
#
# 선별 규칙 = 풀 전체 Z_Score_Aligned 종목별 평균 → 상위 25.
#   ★전략이 아니라 기전 프로브(metric_type = diagnostic). 성과를 주장하지 않는다 —
#   "정본 해석이 선별 결과를 바꾸는가"만 센다.
#
# C15 준수: load_month_factors() 경유. factor_db 재빌드 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/infra/factor_dedup_wiring_20260809")
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

REG_NOW <- .load_registry()
BAK <- Sys.glob(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json.bak_*_dedup5"))
if (!length(BAK)) stop("[d8] 5쌍 등재 전 백업 없음 — before/after 대조 불가")
REG_OLD <- fromJSON(BAK[1], simplifyVector = FALSE)
cat(sprintf("[d8] before-registry = %s\n", basename(BAK[1])))

.roles <- function(reg) {
  rbindlist(lapply(names(reg), function(f) {
    d <- reg[[f]]$dedup
    if (is.null(d)) return(NULL)
    g <- function(k) { v <- d[[k]]; if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1] }
    data.table(factor = f, role = g("role"), cluster = g("cluster"), canonical = g("canonical"))
  }), fill = TRUE)
}
R_NOW <- .roles(REG_NOW); R_OLD <- .roles(REG_OLD)
cat(sprintf("[d8] alias: before=%d after=%d / cluster: before=%d after=%d\n",
            sum(R_OLD$role == "alias", na.rm = TRUE), sum(R_NOW$role == "alias", na.rm = TRUE),
            uniqueN(R_OLD$cluster), uniqueN(R_NOW$cluster)))

top25 <- function(d) {
  s <- d[, .(score = mean(Z_Score_Aligned, na.rm = TRUE), n_f = .N), by = Ticker]
  s <- s[n_f >= 30L]; setorder(s, -score); head(s$Ticker, 25L)
}
collapse_alias <- function(dt, R) {
  present <- unique(dt$Factor_Name)
  al <- R[role == "alias" & !is.na(canonical)]
  drop <- al[factor %in% present & canonical %in% present, factor]
  list(dt = dt[!(Factor_Name %in% drop)], drop = drop)
}
# cluster 당 1종만 남기기 = 이중 투표 상한. 대표는 canonical > 이름 사전순.
collapse_cluster <- function(dt, R) {
  present <- unique(dt$Factor_Name)
  m <- R[factor %in% present & !is.na(cluster)]
  if (!nrow(m)) return(list(dt = dt, drop = character(0)))
  setorderv(m, c("cluster", "role", "factor"))   # canonical < alias < redundant (사전순 우연 아님: 명시 정렬)
  m[, rep := factor[which.max(role == "canonical" | seq_len(.N) == 1L)], by = cluster]
  keep_rep <- unique(m$rep)
  drop <- setdiff(m$factor, keep_rep)
  list(dt = dt[!(Factor_Name %in% drop)], drop = drop)
}

MONTHS <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30",
                    "2018-06-29", "2022-06-30", "2026-06-30"))
rows <- list()
for (sd_i in MONTHS) {
  sd_i <- as.Date(sd_i)
  dt <- as.data.table(load_month_factors(sig_date = sd_i))
  t0 <- top25(dt)

  a_old <- collapse_alias(dt, R_OLD); a_new <- collapse_alias(dt, R_NOW)
  cl    <- collapse_cluster(dt, R_NOW)
  t1a <- top25(a_old$dt); t1b <- top25(a_new$dt); t2 <- top25(cl$dt)

  r <- data.table(
    sig_date = sd_i, pool = uniqueN(dt$Factor_Name),
    drop_S1a = length(a_old$drop), drop_S1b = length(a_new$drop), drop_S2 = length(cl$drop),
    chg_S1a = length(setdiff(t0, t1a)),
    chg_S1b = length(setdiff(t0, t1b)),
    chg_5pairs_only = length(setdiff(t1a, t1b)),   # 5쌍 등재가 추가로 만든 변화
    chg_S2 = length(setdiff(t0, t2)))
  rows[[length(rows) + 1L]] <- r
  cat(sprintf("[d8] %s 풀=%d | 제거 S1a=%d S1b=%d S2=%d | top25 변화 S1a=%d S1b=%d (5쌍기여=%d) S2=%d\n",
              sd_i, r$pool, r$drop_S1a, r$drop_S1b, r$drop_S2,
              r$chg_S1a, r$chg_S1b, r$chg_5pairs_only, r$chg_S2))
}
res <- rbindlist(rows)
fwrite(res, file.path(OUT, "d8_impact_scenarios.csv"))

cat("\n[d8] ===== 요약 (top-25 중 바뀐 종목 수) =====\n")
print(res)
cat(sprintf("\n[d8] 평균: S1a(기존 alias만)=%.2f  S1b(5쌍 포함)=%.2f  S2(상한)=%.2f  / 25종\n",
            mean(res$chg_S1a), mean(res$chg_S1b), mean(res$chg_S2)))
cat(sprintf("[d8] 5쌍 등재의 순 기여 = 평균 %.2f종 (S1a→S1b)\n", mean(res$chg_5pairs_only)))
cat("[d8] ★S2 는 배선 대상이 아니다 — redundant 는 자동 병합 금지(선언 강제). 상한 표시용.\n")
