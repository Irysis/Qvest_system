# =============================================================================
# analyze_persistence2.R — WT-D20260803_005 (FQ-131) Step C2
#   Step C의 자기비판 3건을 정면 처리:
#   (i)  factor-clustered bootstrap은 유효표본을 과대평가한다 (풀 내 factor가 서로 상관).
#        → |cor(active)| >= 0.70 단일연결 클러스터 단위 bootstrap + 유효 독립계열 수 진단.
#   (ii) bin별 persistence에 클러스터 CI 부재 → 추가.
#   (iii) "게이트를 실제로 운용하면 무슨 일이 나는가"의 직접 시뮬 부재
#        → 문턱 tau별 선발 후 다음 창 PORT_t 기대값/양수비율/랭크상관.
#   ★ 사전등록 판별식·창 격자·정의 변경 없음 (추가 진단만).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/analyze_persistence2.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005C2] ", fmt, "\n"), ...))
PR0 <- readRDS(file.path(OUT, "persistence_results.rds"))
A <- PR0$A; POOL <- PR0$pool; PR <- PR0$PR; TG <- PR0$TG; GRIDS <- PR0$grids

# ── (i) 상관 클러스터 = bootstrap 단위 ──────────────────────────────────────
CM <- suppressWarnings(cor(A, use = "pairwise.complete.obs")); CM[!is.finite(CM)] <- 0
D  <- as.dist(1 - abs(CM))
HC <- hclust(D, method = "single")
CLU <- cutree(HC, h = 1 - 0.70)             # |cor| >= 0.70 단일연결 병합
CLUDT <- data.table(Factor_Name = names(CLU), cluster = as.integer(CLU))
say("상관 클러스터(|cor|>=0.70 단일연결): %d factor → %d 클러스터 (최대 %d)",
    length(CLU), uniqueN(CLU), max(table(CLU)))
# 유효 독립계열 수: 완전관측 factor의 active 공분산 PC 수 (분산 90%)
Ac <- A[, colSums(is.na(A)) == 0L, drop = FALSE]
ev <- eigen(cor(Ac), symmetric = TRUE, only.values = TRUE)$values
n_pc90 <- which(cumsum(ev) / sum(ev) >= 0.90)[1]
say("유효 독립성 진단: 완전관측 %d factor의 active 상관행렬 PC 90%% = %d개 (PC1 분산비 %.2f)",
    ncol(Ac), n_pc90, ev[1] / sum(ev))

boot_cl <- function(P, stat_fun, B = 2000L, seed = 20260803L, unit = "cluster") {
  set.seed(seed)
  Q <- merge(P, CLUDT, by = "Factor_Name", all.x = TRUE)
  gv <- if (unit == "cluster") Q$cluster else Q$Factor_Name
  gs <- unique(gv); n <- length(gs)
  idx_map <- split(seq_len(nrow(Q)), gv)
  base <- stat_fun(Q)
  bs <- vapply(seq_len(B), function(b) {
    gg <- sample(gs, n, replace = TRUE)
    stat_fun(Q[unlist(idx_map[as.character(gg)])])
  }, numeric(1))
  c(est = base, lo = unname(quantile(bs, .025, na.rm = TRUE)),
    hi = unname(quantile(bs, .975, na.rm = TRUE)), n_units = n)
}
f_persist <- function(Q) mean(sign(Q$t_k) == sign(Q$t_next))
say("--- P_persist 클러스터-bootstrap 재산출 ---")
CLBOOT <- rbindlist(lapply(names(PR), function(nm) {
  a <- boot_cl(PR[[nm]], f_persist, unit = "cluster")
  b <- boot_cl(PR[[nm]], f_persist, unit = "factor")
  data.table(grid = nm, p = a["est"], cl_lo = a["lo"], cl_hi = a["hi"], n_clusters = a["n_units"],
             fa_lo = b["lo"], fa_hi = b["hi"], n_factors = b["n_units"])
}))
print(CLBOOT)
say("★ 클러스터 CI 폭 / factor CI 폭 = %.2f배 (factor 단위 CI는 그만큼 과신)",
    mean((CLBOOT$cl_hi - CLBOOT$cl_lo) / (CLBOOT$fa_hi - CLBOOT$fa_lo)))

# ── (ii) bin별 클러스터 CI ─────────────────────────────────────────────────
bin_ci <- function(P, gridnm) {
  Q <- copy(P); Q[, absk := abs(t_k)]
  Q[, bin := cut(absk, c(-Inf, .5, 1, 2, Inf),
                 labels = c("[0,0.5)", "[0.5,1)", "[1,2)", "[2,inf)"), right = FALSE)]
  rbindlist(lapply(levels(Q$bin), function(bb) {
    S <- Q[bin == bb]
    if (!nrow(S)) return(NULL)
    r <- boot_cl(S, f_persist, unit = "cluster")
    data.table(grid = gridnm, bin = bb, n = nrow(S), p = r["est"],
               lo = r["lo"], hi = r["hi"], n_clusters = r["n_units"],
               mean_t_next = S[, mean(sign(t_k) * t_next)])
  }))
}
BINCI <- rbindlist(lapply(names(PR), function(nm) bin_ci(PR[[nm]], nm)))
print(BINCI)
say("★ primary 최상위 bin [2,inf): p=%.3f CI [%.3f, %.3f] — 0.5 포함 여부 = %s",
    BINCI[grid == "primary" & bin == "[2,inf)", p], BINCI[grid == "primary" & bin == "[2,inf)", lo],
    BINCI[grid == "primary" & bin == "[2,inf)", hi],
    ifelse(BINCI[grid == "primary" & bin == "[2,inf)", lo <= 0.5 & hi >= 0.5], "포함(동전던지기 배제 못함)", "배제"))

# ── (iii) 운용 게이트 시뮬 — 문턱 tau 선발 후 다음 창 ───────────────────────
gate_sim <- function(P, taus = c(0, 0.5, 1, 1.5, 2, 2.5, 3)) {
  rbindlist(lapply(taus, function(tau) {
    S <- P[t_k >= tau]
    if (nrow(S) < 10L) return(NULL)
    r <- boot_cl(S, function(Q) mean(Q$t_next), unit = "cluster")
    data.table(tau = tau, n_sel = nrow(S), n_windows = uniqueN(S$k),
               mean_t_next = r["est"], lo = r["lo"], hi = r["hi"],
               share_pos_next = S[, mean(t_next > 0)],
               median_t_next = S[, median(t_next)],
               mean_t_k = S[, mean(t_k)])
  }))
}
say("--- 운용 게이트 시뮬 (primary W=60): 창 k에서 t_k >= tau 로 선발 → 창 k+1 실측 ---")
GS <- gate_sim(PR$primary); print(GS)
say("--- 동 시뮬 (rob36) ---"); GS36 <- gate_sim(PR$rob36); print(GS36)
say("--- 동 시뮬 (rob24) ---"); GS24 <- gate_sim(PR$rob24); print(GS24)
# 전체 풀 평균(선발 없음) 대비
base_next <- vapply(PR, function(P) mean(P$t_next), numeric(1))
say("무선발 기준선 mean t_next: primary %+.3f / rob36 %+.3f / rob24 %+.3f",
    base_next["primary"], base_next["rob36"], base_next["rob24"])

# ── (iv) 상대 순위 지속성 — 창 전이별 Spearman ─────────────────────────────
rho_tab <- rbindlist(lapply(names(PR), function(nm) {
  P <- PR[[nm]]
  P[, .(n = .N, rho = suppressWarnings(cor(t_k, t_next, method = "spearman"))), by = k][, grid := nm][]
}))
print(rho_tab)
say("Spearman(t_k, t_next) 창전이별: 중앙값 primary %.3f / rob36 %.3f / rob24 %.3f",
    rho_tab[grid == "primary", median(rho)], rho_tab[grid == "rob36", median(rho)],
    rho_tab[grid == "rob24", median(rho)])

# ── (v) era 공통성분 — 창별 전체 factor 평균 t ─────────────────────────────
ERA <- rbindlist(lapply(names(TG), function(nm) {
  TT <- TG[[nm]]$t
  data.table(grid = nm, k = seq_len(nrow(TT)), from = TG[[nm]]$from, to = TG[[nm]]$to,
             mean_t = apply(TT, 1, mean, na.rm = TRUE),
             share_pos = apply(TT, 1, function(x) mean(x[is.finite(x)] > 0)))
}))
print(ERA[grid == "primary"]); print(ERA[grid == "rob36"])
say("★ era 공통성분: primary 창별 전체평균 t = %s | 양수비율 = %s",
    paste(sprintf("%+.2f", ERA[grid == "primary", mean_t]), collapse = " / "),
    paste(sprintf("%.2f", ERA[grid == "primary", share_pos]), collapse = " / "))

# ── (vi) 조건부 분해 클러스터 CI (family / cap / turnover) ─────────────────
P1 <- PR0$cond_pairs
cond_ci <- function(byv) {
  lv <- P1[!is.na(get(byv)), unique(get(byv))]
  rbindlist(lapply(lv, function(v) {
    S <- P1[get(byv) == v]
    if (nrow(S) < 10L) return(NULL)
    r <- boot_cl(S, f_persist, unit = "cluster")
    data.table(axis = byv, level = as.character(v), n = nrow(S),
               n_factors = uniqueN(S$Factor_Name), p = r["est"], lo = r["lo"], hi = r["hi"],
               n_clusters = r["n_units"])
  }))[order(-p)]
}
CONDCI <- rbindlist(lapply(c("family", "to_tercile", "cap_tercile"), cond_ci))
print(CONDCI)
say("★ 0.5 를 CI로 배제하는 조건: %s",
    paste(CONDCI[lo > 0.5 | hi < 0.5, sprintf("%s=%s(p %.3f)", axis, level, p)], collapse = " | "))

saveRDS(list(clusters = CLUDT, n_clusters = uniqueN(CLU), n_pc90 = n_pc90,
             pc1_share = ev[1]/sum(ev), clboot = CLBOOT, bin_ci = BINCI,
             gate_sim = list(primary = GS, rob36 = GS36, rob24 = GS24, base = base_next),
             rho = rho_tab, era = ERA, cond_ci = CONDCI,
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "persistence_results2.rds"))
say("저장 — persistence_results2.rds")
