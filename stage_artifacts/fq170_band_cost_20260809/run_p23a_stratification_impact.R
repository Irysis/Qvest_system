## P23a — 접두 휴리스틱 층화가 실제 표본을 얼마나 왜곡했는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  오늘 P9c/P17a/P19b(52종)·P20a(43종) 표본은 **내 접두 규칙으로 "계열당 3종" 층화**한 것이다.
##  P22b-2 에서 선언 계열은 **15종**(레지스트리 category)임이 확인됐다.
##  ⇒ 그 표본들을 **선언 계열로 다시 집계**해 실제 다양성을 본다.
##  ★결론(전부 미달)은 임계가 올라가므로 방향상 강해진다. 그러나 **표본 구성이 달랐다는 건 별개 사실**이며
##    "19계열 층화" 라는 내 서술이 정확했는지를 여기서 판정한다.
##  판정:
##   O1_ACCURATE : 표본별 선언 계열 수가 내 서술과 ±1 이내 ∧ 최대 계열 비중 <= 0.35
##   O2_SKEWED   : 선언 계열 수는 비슷하나 **한 계열이 과대표집**(최대 비중 > 0.35)
##   O3_MISDESCRIBED : 선언 계열 수가 내 서술과 2 이상 차이 → 표본 서술 정정 필요
##  ★결론 재산출도 함께: 각 표본의 **선언 계열 수**로 임계를 다시 계산해 판정이 유지되는지.
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/cluster_power.R"))

REGP <- "02_Infrastructure/factor_db/factor_registry.json"
stopifnot(file.exists(REGP))
REG <- fromJSON(REGP, simplifyVector = FALSE)
DECL <- rbindlist(lapply(names(REG), function(nm) {
  v <- REG[[nm]][["category"]]
  if (is.null(v)) v <- tryCatch(REG[[nm]][["labels"]][["economic_family"]], error=function(e) NULL)
  data.table(base = nm, decl = if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1])
}), fill = TRUE)
cat(sprintf("[선언 분류] 항목 %d · 계열 %d\n", nrow(DECL), uniqueN(DECL[!is.na(decl), decl])))

S52 <- fread(file.path(OUT, "p11c_net.csv"))[, .(base, my_fam = fam)]     # P9c/P17a/P19b 표본
S43 <- fread(file.path(OUT, "p20a_fresh.csv"))[, .(base, my_fam = fam)]   # P20a 표본
audit <- function(S, label, claimed) {
  M <- merge(S, DECL, by = "base", all.x = TRUE)
  miss <- sum(is.na(M$decl))
  T <- M[!is.na(decl), .N, by = decl][order(-N)]
  nd <- nrow(T); top <- if (nd) T$N[1]/sum(T$N) else NA_real_
  cat(sprintf("\n=== %s (n=%d, 내 서술 '%d계열') ===\n", label, nrow(S), claimed))
  cat(sprintf("  선언 매칭 실패 %d · **선언 계열 %d종** · 최대 계열 비중 %.3f (%s %d종)\n",
              miss, nd, top, T$decl[1], T$N[1]))
  print(T)
  ## 내 접두 계열 ↔ 선언 계열 교차 (휴리스틱이 무엇을 쪼갰/뭉갰는지)
  X <- M[!is.na(decl), .N, by = .(my_fam, decl)][order(my_fam, -N)]
  split_fams <- X[, .(k = uniqueN(decl)), by = my_fam][k > 1L]
  merged <- X[, .(k = uniqueN(my_fam)), by = decl][k > 1L]
  cat(sprintf("  ★내 계열 1개가 선언 여러 계열로 쪼개진 경우: %d · 선언 1계열이 내 여러 계열에 흩어진 경우: %d\n",
              nrow(split_fams), nrow(merged)))
  if (nrow(split_fams)) print(head(X[my_fam %in% split_fams$my_fam], 10))
  list(label = label, n = nrow(S), claimed = claimed, n_declared = nd,
       top_share = top, n_missing = miss, table = T,
       n_split = nrow(split_fams), n_merged = nrow(merged))
}
A <- audit(S52, "P9c/P17a/P19b 표본", 19L)
B <- audit(S43, "P20a 표본",          15L)

cat("\n=== 선언 계열 수로 판정 재산출 ===\n")
for (r in list(list(A, 0.500, "P19b rho .500"), list(B, 0.410, "P20a rho .410"))) {
  a <- r[[1]]; rho <- r[[2]]; nm <- r[[3]]
  v_claim <- cp_feasibility(rho, a$claimed, a$n)$verdict
  v_decl  <- cp_feasibility(rho, a$n_declared, a$n)$verdict
  cat(sprintf("  %-16s 내 서술 %2d계열(임계 %.3f) → %-22s · 선언 %2d계열(임계 %.3f) → %s\n",
              nm, a$claimed, cp_critical_rho(a$claimed), v_claim,
              a$n_declared, cp_critical_rho(a$n_declared), v_decl))
}
acc <- function(a) abs(a$n_declared - a$claimed) <= 1L && isTRUE(a$top_share <= 0.35)
verdict <- if (abs(A$n_declared - A$claimed) >= 2L || abs(B$n_declared - B$claimed) >= 2L) "O3_MISDESCRIBED" else
           if (!acc(A) || !acc(B)) "O2_SKEWED" else "O1_ACCURATE"
cat(sprintf("\n판정: %s\n", verdict))
cat("★결론(전부 미달)은 임계가 오르면 강해진다 — 그러나 표본 서술의 정확성은 별개다\n")
write_json(list(verdict=verdict, declared_total=uniqueN(DECL[!is.na(decl), decl]),
                sample_52=A, sample_43=B),
           file.path(OUT,"p23a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
