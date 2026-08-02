#==============================================================================
# apply_factor_dedup.R — factor_registry.json 에 de-dup 라벨을 적재하는 writer
#
# 원칙 (도훈 mandate / 메모리 reference-code-identity-stability):
#   * 삭제·리넘버 금지. 코드는 안정 식별자다 — 기존 이름 조회는 계속 유효해야 한다.
#   * lifecycle.status 는 건드리지 않는다. 현재 어떤 코드도 그 필드를 읽지 않으므로
#     "deprecated" 로 바꾸면 **라벨만 바뀌고 행동은 그대로**인 위장이 된다.
#     de-dup 은 별도 `dedup` 블록 + resolve_factor_canonical()/drop_alias_factors()
#     소비 경로로 강제한다 (factor_dup_scan.R).
#
# role 3종:
#   canonical  — 이 코드가 그 정보의 정본
#   alias      — **구성상 같은 양**. canonical 로 접어도 정보 손실 0.
#   redundant  — 구성은 다른데 실측이 겹침. 자동 병합 금지, 선별 시 선언 강제.
#                (needs_review=TRUE 면 계보 추적이 아직 안 된 쌍)
#
# 사용: Rscript 02_Infrastructure/factor_db/apply_factor_dedup.R [--root PATH] [--dry-run]
#==============================================================================

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && length(args) > i[1]) args[i[1] + 1L] else default
}
DRY  <- "--dry-run" %in% args
ROOT <- .arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SCAN_DIR <- .arg("--scan-dir", file.path(ROOT, "04_Research/01_reports"))
RUNTAG <- .arg("--run-tag", "20260802")
STAMP  <- .arg("--stamp", format(Sys.Date(), "%Y%m%d"))

marker <- "02_Infrastructure/factor_db/factor_dup_scan.R"
if (!file.exists(file.path(ROOT, marker))) stop("[dedup] root 아님 (marker 부재): ", ROOT)
cat(sprintf("[dedup] root=%s  dry_run=%s\n", ROOT, DRY))

REG_PATHS <- c(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json"),
               file.path(ROOT, ".cache/factor_db/factor_registry.json"))
present <- REG_PATHS[file.exists(REG_PATHS)]
if (!length(present)) stop("[dedup] factor_registry.json 없음")
cat(sprintf("[dedup] registry copies found: %d / %d\n", length(present), length(REG_PATHS)))
for (p in REG_PATHS) if (!file.exists(p)) cat(sprintf("[dedup]   MISSING (skip): %s\n", p))

#==============================================================================
# 1. 실측 입력 — signal basis(Pearson) + rank basis 합집합
#==============================================================================
sig <- as.data.table(read_parquet(file.path(SCAN_DIR, sprintf("factor_dup_signal_pairs_%s.parquet", RUNTAG))))
hits <- sig[verdict %in% c("EXACT_DUP", "NEAR_DUP"),
            .(factor_a, factor_b, median_cor, median_abs, n_months, verdict,
              basis = "signal_zscore_pearson")]

rank_path <- file.path(SCAN_DIR, sprintf("factor_dup_rank_pairs_%s.parquet", RUNTAG))
if (file.exists(rank_path)) {
  rk <- as.data.table(read_parquet(rank_path))
  rk <- rk[verdict %in% c("EXACT_DUP", "NEAR_DUP"),
           .(factor_a, factor_b, median_cor, median_abs, n_months, verdict,
             basis = "signal_rank")]
  hits <- rbind(hits, rk)
  cat(sprintf("[dedup] rank basis merged (+%d rows)\n", nrow(rk)))
} else {
  cat("[dedup] WARNING: rank basis parquet 부재 — Pearson basis 만 사용\n")
}
# 같은 쌍이 두 basis 에 있으면 강한 쪽(=|cor| 큰 쪽) 채택
hits[, key := paste(pmin(factor_a, factor_b), pmax(factor_a, factor_b))]
setorder(hits, key, -median_abs)
hits <- hits[!duplicated(key)]
cat(sprintf("[dedup] duplicate pairs (union of bases): %d\n", nrow(hits)))

#==============================================================================
# 2. 연결 성분 -> cluster
#==============================================================================
.components <- function(pairs) {
  nodes <- sort(unique(c(pairs$factor_a, pairs$factor_b)))
  parent <- setNames(nodes, nodes)
  find <- function(x) { while (parent[[x]] != x) x <- parent[[x]]; x }
  for (i in seq_len(nrow(pairs))) {
    ra <- find(pairs$factor_a[i]); rb <- find(pairs$factor_b[i])
    if (ra != rb) parent[[rb]] <- ra
  }
  grp <- split(nodes, vapply(nodes, find, character(1)))
  grp <- grp[order(vapply(grp, function(g) sort(g)[1], character(1)))]
  lapply(grp, sort)
}
CLUST <- .components(hits)
names(CLUST) <- sprintf("DUPC-%03d", seq_along(CLUST))
cat(sprintf("[dedup] clusters: %d\n", length(CLUST)))

#==============================================================================
# 3. 계보 판정 (adjudication) — 소스코드로 추적해 "구성상 동일"을 확인한 쌍만 alias
#==============================================================================
ALIAS <- list(
  R12_Idiosyncratic_Risk = list(
    canonical = "D01_IdioVol",
    mechanism = paste(
      "factor_db_daily_phase6.R:286 `R12_Idiosyncratic_Risk <- D01_IdioVol` (리터럴 복사).",
      "월간 경로도 동일 양 — compute_risk.R:126 r12 = -sd(CAPM residuals),",
      "compute_defense.R:69 D01 = 동일 잔차 표준편차(252d).",
      "실측: Z_Score_Aligned 가 258/258 개월 bit-identical (maxdiff 0)."),
    reason = "D01 = evidence_tier A + 원본. R12 는 부호만 뒤집은 파생 등록."),
  M29_Mom_5d = list(
    canonical = "M11_ST_Reversal",
    mechanism = paste(
      "동일 수식이 compute_momentum.R 안에 두 번 — :186 m11 = prod(1+rets[(n-4):n])-1,",
      ":430 M29 = prod(1+Ret[(n-4):n])-1. 일간 경로는 더 노골적:",
      "factor_db_daily_phase6.R:144 M11 <- cr5, :168 M29 <- cr5 (같은 변수).",
      "실측: 258/258 개월 bit-identical."),
    reason = "M11 = 문헌 명명(단기 반전). M29 는 같은 값에 반대 방향 사전(higher_better)을 붙인 중복 등록."),
  CR04_Ownership_Concentration = list(
    canonical = "L02_Turnover",
    mechanism = paste(
      "compute_crowding.R:155-172 CR04 = mean(Vol/est_shares, 20d) —",
      "compute_liquidity.R:57-74 L02 와 같은 양(20일 평균 회전율).",
      "실측 median |cor| = 1.0000 (258개월)."),
    reason = paste(
      "L02 = 값과 이름이 일치. CR04 는 정의문('Turnover Ratio inverse',",
      "'low turnover = crowded')이 실제 저장값(회전율 그 자체)과 반대 — 명명 결함 동반.")),
  XF_LL05_WorkingCapital = list(
    canonical = "Q31_WC_to_Assets",
    mechanism = paste(
      "정의문 동일 — 양쪽 다 (CurrentAssets - CurrentLiab)/TotalAssets.",
      "data_source 만 다름 (Q31=fundamental/DART, XF_LL05=fundamental_xlsx).",
      "실측 median |cor| = 1.0000 (258개월). 단 12개월에서 부호 역전(min=-0.184)"),
    reason = "Q31 = DART 네이티브. xlsx 트윈은 소스 혼합 위험(월별 발산 12건 실측)."),
  M27_Analyst_Rev_Mom = list(
    canonical = "C02_EPS_Chg_1m",
    mechanism = paste(
      "M27 registry 정의문이 그대로 'eps_chg_1m. 1-month EPS revision (latest).' —",
      "C02_EPS_Chg_1m 과 같은 필드. 실측 median |cor| = 0.9992 (258개월)."),
    reason = "C02 = consensus 네이티브 코드. M27 은 momentum 카테고리로의 재등록."),
  V20_SP = list(
    canonical = "V08_PSR",
    mechanism = paste(
      "구성상 역수 — compute_value.R:160 V08 = MarketCap/Revenue,",
      ":279 V20 = Revenue/MarketCap. Pearson-on-Z 로는 |cor|<0.95 라 안 잡히지만",
      "**순위가 동일**해 top-N 선별에서 같은 포트를 만든다:",
      "rank basis median |cor| = 1.0000 (258/258 개월), deploy basis +0.9945.",
      "C13 방향정렬이 부호를 맞춘 뒤에는 같은 신호."),
    reason = paste(
      "역수 쌍은 정보량이 동일하다. V08 = registry 기본 명명(Price-to-Sales).",
      "★이 쌍은 Pearson 스캔만 돌렸으면 놓쳤다 — rank basis 추가의 직접 근거.")),
  V19_Debt_to_Market = list(
    canonical = "R17_Market_Leverage",
    mechanism = paste(
      "동일 수식 TotalDebt/MarketCap — compute_risk.R:207 (부호 반전) vs",
      "compute_value.R:272. 일간 경로에서는 문자 그대로 같은 식이 두 phase 에 존재",
      "(phase6:492 R17, phase8:194 V19). 실측 median |cor| = 0.9989 (258개월)."),
    reason = paste(
      "R17 = 커버리지 넓음(2026-06 실측 2130 vs 1900 — V19 는 TotalDebt>0 게이트로 축소)",
      "+ 승인 게이트 통계 우위(port_t +0.194 vs -0.106).",
      "주의: R17 저장부호는 Bhandari(1988) 방향과 반대이나 C13 정렬이 해소한다."))
)

CLUSTER_LABEL <- list(
  D01_IdioVol            = "volatility_residual",
  V08_PSR                = "sales_to_price",
  C01_SUE                = "earnings_surprise",
  Q14_Current_Ratio      = "liquidity_ratio",
  D16_Coskewness         = "coskewness",
  D53_Range_Vol          = "range_volatility",
  L01_Amihud             = "amihud_illiquidity",
  L13_Vol_Variance_Ratio = "volume_concentration",
  V16_Tobins_Q           = "assets_to_market"
)
INERT_TERM_NOTE <- paste(
  "★결함 유도 동일성 — 합(sum) 항이 값에 영향을 주지 못한다. 자동 병합 금지:",
  "접으면 팩터가 아니라 **결함이 라벨 뒤로 사라진다**. 수리 후 재측정할 것.")
CLUSTER_NOTE <- list(
  sales_to_price = paste(
    "V13_EV_Sales = EV/Revenue (EV = MarketCap + TotalDebt - Cash) 인데 저장값이",
    "V08_PSR(MarketCap/Revenue)과 258/258 개월 cor = 1.000000 이다.",
    "원천 재구성 실측(2026-06-30, 2582종목): NetDebt==0 인 종목 0.0%,",
    "|NetDebt|/MarketCap 중앙값 0.266, cor(MC/Rev, EV/Rev) = 0.900 (Spearman 0.753).",
    "즉 EV 를 제대로 넣으면 0.90 이어야 하는데 1.000000 이 나온다 ->",
    "저장된 V13 에서 **EV 항이 무력**하다.", INERT_TERM_NOTE,
    "영향 의심 범위(미확정): V07_EV_EBITDA / V14_EBIT_EV / V22_FCFF_EV."),
  assets_to_market = paste(
    "V16_Tobins_Q = (MarketCap + TotalLiab)/TotalAssets, V18_AM = TotalAssets/MarketCap.",
    "이 둘이 rank basis 258/258 개월 |cor| = 1.0000 이려면 V16 이 사실상",
    "MarketCap/TotalAssets (= 1/V18) 여야 한다 — 즉 **+TotalLiab 항이 무력**.",
    "sales_to_price 의 EV 항 무력화와 같은 계통의 독립 2번째 사례.", INERT_TERM_NOTE),
  liquidity_ratio = paste(
    "Current Ratio 와 Quick Ratio 는 정의가 실제로 다르다(재고 포함/제외).",
    "median |cor| 0.975 로 겹치나 병합은 리서치 판단.",
    "★부수 적발: 258개월 중 10개월에서 정렬 후 부호가 뒤집힌다(min=-0.975)",
    "— C13 IC-기반 방향추론이 이 쌍에서 불안정하다는 별도 신호.")
)

#==============================================================================
# 4. dedup 블록 생성
#==============================================================================
EVID_RUN <- sprintf("04_Research/01_reports/factor_db_dedup_%s.md", RUNTAG)
pair_stat <- function(a, b) {
  r <- hits[(factor_a == a & factor_b == b) | (factor_a == b & factor_b == a)]
  if (!nrow(r)) return(NULL)
  list(median_abs_cor = round(r$median_abs[1], 6),
       median_cor     = round(r$median_cor[1], 6),
       n_months       = as.integer(r$n_months[1]),
       basis          = r$basis[1],
       verdict        = r$verdict[1])
}

blocks <- list()
for (cid in names(CLUST)) {
  members <- CLUST[[cid]]
  label <- NULL
  for (m in members) if (!is.null(CLUSTER_LABEL[[m]])) { label <- CLUSTER_LABEL[[m]]; break }
  aliases_here <- intersect(members, names(ALIAS))

  for (m in members) {
    if (m %in% aliases_here) {
      spec <- ALIAS[[m]]
      blocks[[m]] <- list(
        role = "alias", canonical = spec$canonical, cluster = cid,
        deprecated_for_selection = TRUE,
        adjudicated = TRUE,
        mechanism = spec$mechanism, reason = spec$reason,
        evidence = c(pair_stat(m, spec$canonical),
                     list(measured_at = "2026-08-02", report = EVID_RUN,
                          window = "2005-01..2026-06 (258 months)")),
        consumption_rule = paste(
          "선별/Ω 추정에서는 canonical 만 사용(drop_alias_factors()).",
          "코드 조회·과거 산출물 참조는 계속 유효 — 삭제·리넘버 없음."))
    }
  }
  canon_here <- unique(vapply(aliases_here, function(a) ALIAS[[a]]$canonical, character(1)))
  for (cn in canon_here) {
    my_aliases <- aliases_here[vapply(aliases_here, function(a) ALIAS[[a]]$canonical == cn, logical(1))]
    blocks[[cn]] <- list(
      role = "canonical", cluster = cid, aliases = as.list(sort(my_aliases)),
      adjudicated = TRUE,
      evidence = list(measured_at = "2026-08-02", report = EVID_RUN,
                      window = "2005-01..2026-06 (258 months)"))
  }
  # 나머지 = redundant
  for (m in setdiff(members, c(aliases_here, canon_here))) {
    partners <- setdiff(members, m)
    nt <- if (!is.null(label) && !is.null(CLUSTER_NOTE[[label]])) CLUSTER_NOTE[[label]] else NULL
    blk <- list(
      role = "redundant", cluster = cid,
      partners = as.list(partners),
      adjudicated = !is.null(label),
      needs_review = is.null(label),
      evidence = list(
        max_pair_abs_cor = round(max(hits[factor_a == m | factor_b == m, median_abs]), 6),
        measured_at = "2026-08-02", report = EVID_RUN,
        window = "2005-01..2026-06 (258 months)"),
      consumption_rule = paste(
        "자동 병합 금지. 같은 cluster 의 둘 이상을 한 선별 풀에 넣으면",
        "report_redundant_clusters() 가 보고한다 — 선언하거나 하나로 접을 것."))
    if (!is.null(label)) blk$cluster_label <- label
    if (!is.null(nt))    blk$note <- nt
    blocks[[m]] <- blk
  }
}

cat(sprintf("[dedup] blocks: %d  (alias %d / canonical %d / redundant %d)\n",
            length(blocks),
            sum(vapply(blocks, function(b) b$role == "alias", logical(1))),
            sum(vapply(blocks, function(b) b$role == "canonical", logical(1))),
            sum(vapply(blocks, function(b) b$role == "redundant", logical(1)))))

#==============================================================================
# 5. 쓰기 — 두 벌 모두, 원자적으로, 그리고 **정합 확인**
#==============================================================================
apply_to <- function(path) {
  reg <- fromJSON(path, simplifyVector = FALSE)
  n_before <- length(reg)
  missing <- setdiff(names(blocks), names(reg))
  if (length(missing)) stop("[dedup] registry 에 없는 팩터: ", paste(missing, collapse = ", "))
  for (k in names(blocks)) reg[[k]]$dedup <- blocks[[k]]
  stopifnot(length(reg) == n_before)

  if (DRY) { cat(sprintf("[dedup] DRY-RUN — would write %s (%d entries)\n", path, n_before)); return(invisible(NULL)) }

  bak <- sprintf("%s.bak_%s_dedup", path, STAMP)
  if (!file.exists(bak)) file.copy(path, bak)
  tmp <- sprintf("%s.tmp%d", path, Sys.getpid())
  write_json(reg, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  chk <- fromJSON(tmp, simplifyVector = FALSE)
  if (length(chk) != n_before) { unlink(tmp); stop("[dedup] 재파싱 엔트리 수 불일치: ", path) }
  if (!all(names(chk) == names(reg))) { unlink(tmp); stop("[dedup] 키 순서/집합 변화: ", path) }
  if (!file.rename(tmp, path)) { unlink(tmp); stop("[dedup] rename 실패: ", path) }
  cat(sprintf("[dedup] wrote %s (backup %s)\n", path, basename(bak)))
}
for (p in present) apply_to(p)

if (!DRY && length(present) == 2L) {
  h <- vapply(present, function(p) unname(tools::md5sum(p)), character(1))
  if (h[1] == h[2]) cat(sprintf("[dedup] 2-copy coherence OK (%s)\n", substr(h[1], 1, 12)))
  else stop("[dedup] 2벌 md5 불일치 — 한쪽만 갱신됨: ", paste(substr(h, 1, 12), collapse = " / "))
} else if (!DRY) {
  cat("[dedup] NOTE: registry 사본이 1벌뿐 — 배포 트리에서 2벌 정합 재확인 필요\n")
}

## cluster 목록을 사람이 읽을 수 있게 남긴다
out <- rbindlist(lapply(names(CLUST), function(cid) data.table(
  cluster = cid, members = paste(CLUST[[cid]], collapse = ", "),
  n = length(CLUST[[cid]]),
  roles = paste(vapply(CLUST[[cid]], function(m) blocks[[m]]$role, character(1)), collapse = "/")
)))
print(out, nrows = 200)
if (!DRY) {
  fwrite(out, file.path(SCAN_DIR, sprintf("factor_dup_clusters_%s.csv", RUNTAG)))
  cat(sprintf("[dedup] cluster table -> %s\n",
              file.path(SCAN_DIR, sprintf("factor_dup_clusters_%s.csv", RUNTAG))))
}
