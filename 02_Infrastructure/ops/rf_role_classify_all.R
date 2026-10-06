#==============================================================================
# rf_role_classify_all.R — 기존 DB 전략 역할 일괄 분류 + 2계층 풀 대표 선정 (2026-10-06)
#   사용: cd 02_Infrastructure/ops && Rscript -e 'source("rf_role_classify_all.R")'   (env RF_ROLE_DRY=1 = 레지스트리 미기록)
#   ① 분류(기록): 원장 L1 칸·기저 + 카탈로그(원장 밖 B+) + BOOK 전부에 역할 카드 → 06_Registry/strategy_roles.json
#   ② 풀 대표(편입): 역할마다 B+ 중 ⓐ 계보마다 역할 t 최대 1개 → ⓑ 그 대표들을 2요인 잔차 상관 군집(complete linkage ·
#      1 − τ_dup)으로 묶어 군집마다 역할 t 최대 1개만 pool_rep. 강화 칸은 같은 계보 안에서 거의 복제본이다 — 전부 넣으면 풀이 커질 뿐 다양해지지 않는다(도훈 2026-10-06).
#      τ_dup = 06_Registry/rf_diversification_gate.json calibration.provisional_values_resid2_all.tau_dup_rho(재생 §11 보정값).
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
.root <- local({ p <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); p })
setwd(.root)
source("02_Infrastructure/contracts/strategy_role.R")
E <- .sr_env
t0 <- Sys.time()
cfg <- sr_cfg(.root); dcfg <- E$rfd_cfg(.root)
tau <- as.numeric(dcfg$calibration$provisional_values_resid2_all$tau_dup_rho)
if (!is.finite(tau)) stop("τ_dup 판독 불가 — rf_diversification_gate.json calibration")
mem <- E$rfd_members(.root, dcfg); mem[, mid := paste0("S", seq_len(.N))]
bm <- E$rfd_bench_daily(.root, dcfg); fac <- E$rfd_factor_monthly(.root, dcfg); R <- sr_regimes(bm)
bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
mon <- list()
for (k in seq_len(nrow(mem))) { x <- E$rfd_monthly(E$rfd_read_series(mem$series[k]), bm, fac); if (!is.null(x)) mon[[mem$mid[k]]] <- x }
mats <- E$rfd_matrix(mon)
pool <- copy(E$rfd_pool(mem, dcfg, exclude_flags = character(0))); pool[, member_id := mid]
cards <- list()
for (k in names(mon)) {
  m <- merge(merge(mon[[k]][, .(ym, r)], bmm, by = "ym"), fac, by = "ym", all.x = TRUE)
  cd <- sr_card(m, R, cfg)
  cd <- sr_add_diversifier(cd, mon[[k]], mem[mid == k, lineage], pool, mats, cfg, dcfg)
  cards[[k]] <- cd
}
flat <- rbindlist(lapply(names(cards), function(k) {
  cd <- cards[[k]]; if (!identical(cd$status, "ok")) return(data.table(mid = k, status = cd$status))
  g <- function(r) if (!is.null(cd$roles[[r]])) cd$roles[[r]]$grade else NA_character_
  tt <- function(r) if (!is.null(cd$roles[[r]])) suppressWarnings(as.numeric(cd$roles[[r]]$t)) else NA_real_
  data.table(mid = k, status = "ok", primary_role = cd$primary_role, primary_grade = cd$primary_grade,
             g_defensive = g("defensive"), g_offensive = g("offensive"), g_rebound = g("rebound"), g_alpha = g("alpha"), g_diversifier = g("diversifier"),
             t_defensive = tt("defensive"), t_offensive = tt("offensive"), t_rebound = tt("rebound"), t_alpha = tt("alpha"), t_diversifier = tt("diversifier"))
}), fill = TRUE)
flat <- merge(mem[, .(mid, member_id, kind, lineage, entry_id, cell, essence_grade = grade, port_t, series)], flat, by = "mid", all.x = TRUE)
# --- 풀 대표: 역할별 군집 ---
reps <- list()
for (role in c("defensive", "offensive", "rebound", "alpha", "diversifier")) {
  gcol <- paste0("g_", role); tcol <- paste0("t_", role)
  B <- flat[get(gcol) %in% c("A", "B") & mid %in% colnames(mats$E2)]
  if (!nrow(B)) next
  n_bplus <- nrow(B)
  # 1단: 계보(논문·결합 키)마다 역할 t 최대 1개 — 같은 계보의 강화 변형은 풀에 하나만
  setorderv(B, tcol, -1L); B <- B[!duplicated(lineage)]
  if (nrow(B) == 1L) { B[, cl := 1L] } else {
    C <- suppressWarnings(cor(mats$E2[, B$mid], use = "pairwise.complete.obs")); C[!is.finite(C)] <- 0
    B[, cl := cutree(hclust(as.dist(1 - C), method = "complete"), h = 1 - tau)]
  }
  setorderv(B, c("cl", tcol), c(1L, -1L))
  rp <- B[!duplicated(cl)]
  reps[[role]] <- data.table(role = role, mid = rp$mid, cluster = rp$cl, cluster_size = B[, .N, by = cl][match(rp$cl, cl), N], n_bplus = n_bplus)
}
REP <- rbindlist(reps)
flat[, pool_rep_roles := vapply(mid, function(k) paste(REP[mid == k, role], collapse = ";"), "")]
cat("분류", nrow(flat), "· 역할 B+ 보유", sum(!is.na(flat$primary_grade) & (flat$g_defensive %in% c("A","B") | flat$g_offensive %in% c("A","B") | flat$g_rebound %in% c("A","B") | flat$g_alpha %in% c("A","B") | flat$g_diversifier %in% c("A","B"))), "\n")
print(REP[, .(rep_n = .N, lineage_reps = sum(cluster_size), members_bplus = n_bplus[1]), by = role])
cat("풀 대표 고유 전략:", uniqueN(REP$mid), "· 계보", uniqueN(flat[mid %in% REP$mid, lineage]), "\n")
print(flat[mid %in% REP$mid, .(member_id, kind, lineage = substr(lineage, 1, 36), essence_grade, pool_rep_roles)][order(pool_rep_roles)])
out_dir <- file.path(.root, "04_Research/01_reports/strategy_role_grading_20261006/classify_20261006")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
fwrite(flat, file.path(out_dir, "role_classification.csv")); fwrite(REP, file.path(out_dir, "pool_representatives.csv"))
if (!identical(Sys.getenv("RF_ROLE_DRY"), "1")) {
  items <- list()
  for (i in seq_len(nrow(flat))) {
    k <- flat$mid[i]; if (is.null(cards[[k]])) next
    id <- flat$member_id[i]
    items[[id]] <- list(card = cards[[k]], meta = list(member_id = id, kind = flat$kind[i], lineage = flat$lineage[i], entry_id = flat$entry_id[i],
                        cell = flat$cell[i], essence_grade = flat$essence_grade[i], series = flat$series[i],
                        pool_rep_roles = if (nzchar(flat$pool_rep_roles[i])) strsplit(flat$pool_rep_roles[i], ";")[[1]] else list()))
  }
  n <- sr_registry_upsert(items, .root, source = "rf_role_classify_all.R")
  cat("레지스트리 기록:", n, "→", sr_registry_path(.root), "\n")
}
cat("소요", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "초\n")
