#==============================================================================
# d7_apply_dedup_5pairs.R — 미선언 5쌍 정본 지정 (과제 B)
#
# 원칙 (apply_factor_dedup.R 의 규약 답습):
#   * 추가만. 삭제·리넘버·이름 재사용 금지. 기존 조회는 계속 유효.
#   * lifecycle.status 는 건드리지 않는다.
#   * cluster 번호 하드코딩 금지 — 쓰기 직전 max+1, 쓴 뒤 재읽기 확인.
#   * 형식 보존: pretty=TRUE(=2칸, d6 실측) + CRLF + digits=NA.
#   * 사본 2벌(02_Infrastructure, .cache) 동시 갱신 + md5 정합 확인.
#
# 판정 근거 (전부 이 라운드 실측):
#   d3 — CONSENSUS 원천이 **일간**(관측 간격 중앙 1일). .cons_history() 는 관측
#        행을 주므로 x[1:4] = 4영업일 = 같은 분기값 4벌 ⇒ mean==latest 100%
#        (2010/2018/2024 전건). ⇒ C10/C13 동일성은 **중복 등록이 아니라 무력 창 결함**.
#   d5 — 배출 이력: C01/C09/C10 동률(300개월·동일 행수 = 비트동일 정합),
#        C04/C13 동률(303개월), C11 757행 > M25 735행 (커버리지 우위).
#
# ★C10/C13 처리의 긴장 (명시):
#   결함 유래 동일성을 alias 로 접으면 **결함이 라벨 뒤로 숨는다**(registry 의
#   INERT_TERM_NOTE 가 경고한 실패 양식). 그러나 접지 않으면 오늘 실제로 이중
#   투표한다. 채택: **접되 결함을 registry 에 명시 기록**(`defect` + `revisit_on`)
#   하고 창 수리를 별건 큐로 올린다. 접는 근거는 "정보 동일"이 아니라
#   "현 빌드에서 값이 동일" — 조건부 선언임을 필드로 못박는다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

ROOT  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
STAMP <- format(Sys.Date(), "%Y%m%d")
DRY   <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)
REPORT <- "04_Research/01_reports/factor_emission_identity_audit_20260809.md"

REG_PATHS <- c(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json"),
               file.path(ROOT, ".cache/factor_db/factor_registry.json"))
present <- REG_PATHS[file.exists(REG_PATHS)]
if (!length(present)) stop("[d7] registry 없음")
cat(sprintf("[d7] registry copies = %d ; dry_run = %s\n", length(present), DRY))

reg0 <- fromJSON(present[1], simplifyVector = FALSE)

# ── cluster 번호: 하드코딩 금지, 쓰기 직전 max+1 ────────────────────────────
cls <- unlist(lapply(reg0, function(e) {
  if (is.null(e$dedup) || is.null(e$dedup$cluster)) NULL else as.character(e$dedup$cluster)[1]
}))
nums <- as.integer(sub("^DUPC-", "", grep("^DUPC-[0-9]+$", cls, value = TRUE)))
maxn <- max(nums)
CL_ESBR   <- sprintf("DUPC-%03d", maxn + 1L)
CL_STREAK <- sprintf("DUPC-%03d", maxn + 2L)
CL_SUE    <- as.character(reg0$C01_SUE$dedup$cluster)[1]   # 기존 cluster 승계
cat(sprintf("[d7] 기존 max cluster = DUPC-%03d → 신규 %s(ESBR) / %s(streak) ; SUE 는 기존 %s 확장\n",
            maxn, CL_ESBR, CL_STREAK, CL_SUE))

EV <- function(...) c(list(...), list(measured_at = "2026-08-09", report = REPORT,
                                      window = "표본 6월 (200506/201006/201406/201806/202206/202606)"))
RULE_ALIAS <- paste("선별/Ω 추정에서는 canonical 만 사용(drop_alias_factors()).",
                    "코드 조회·과거 산출물 참조는 계속 유효 — 삭제·리넘버 없음.")

DEFECT_WINDOW <- paste(
  "★무력 창(inert window) — 롤링 평균 항이 값에 영향을 주지 못한다.",
  ".cons_history() 는 CONSENSUS 원천의 **관측 행**을 최신순으로 돌려주는데 원천이",
  "일간이다(sue/esbr 관측 간격 중앙 1일, 2026-08-09 실측). 따라서 x[1:n] 은",
  "n'분기'가 아니라 n'영업일'을 본다 — 창 span 중앙 2~5일, 창 내 고유값 중앙 1.0,",
  "mean(창)==latest 가 2010/2018/2024 전 티커에서 성립(비율 1.0000).",
  "C15_Forecast_Error_Trend 의 사망 기전과 **같은 뿌리**다.",
  "이 alias 선언은 '정보가 같다'가 아니라 '현 빌드에서 값이 같다'는 조건부 선언이다.")

blocks <- list(

  # ── cluster: earnings_surprise (기존 DUPC-005 확장) ──────────────────────
  C01_SUE = list(
    role = "canonical", cluster = CL_SUE,
    aliases = list("C09_Earnings_Surprise_Sq", "C10_SUE_Persistence"),
    partners = list("C05_ESCR"),
    adjudicated = TRUE, needs_review = FALSE,
    cluster_label = "earnings_surprise",
    reason = paste(
      "SUE 원천 1종이 C01/C09/C10 3중 등록. C01 = 변환 없는 원본(compute_consensus.R:141",
      "Raw_Value = sue) + 북 incumbent. 배출 이력은 3종 동률(300개월·동일 행수)이므로",
      "이력이 아니라 **구성**이 정본을 정한다 — C09/C10 은 C01 의 파생이다."),
    evidence = EV(max_pair_abs_cor = 0.990436,
                  note = "0.990436 은 partner C05_ESCR 과의 값(2026-08-02 측정). alias 쌍 통계는 각 alias 블록 참조."),
    consumption_rule = paste(
      "alias(C09/C10)는 drop_alias_factors() 가 자동 축약한다.",
      "partner C05_ESCR 은 자동 병합 대상이 아니며 같은 풀에 함께 넣을 때 선언이 필요하다",
      "(report_redundant_clusters()).")),

  C09_Earnings_Surprise_Sq = list(
    role = "alias", canonical = "C01_SUE", cluster = CL_SUE,
    deprecated_for_selection = TRUE, adjudicated = TRUE,
    mechanism = paste(
      "compute_consensus.R:236-237 C09 = sign(sue) * sue^2 — 같은 latest sue 의",
      "**순증가 단조변환**이다(sign(x)x^2 는 R 전체에서 강증가). 따라서 순위가",
      "구조적으로 동일하고, 값은 다르므로 최대절대차로는 안 잡히고 랭크로만 잡힌다",
      "(실측 rho 0.9999982, 최대절대차 1.852). rho 가 정확히 1 이 아닌 것은 빌더의",
      "winsorize(1/99)·±3 clip 이 변환 **후** 걸려 동률 구조를 바꾸기 때문."),
    reason = paste(
      "registry 정의문 'sign(sue)*sue^2. Amplified surprises.' 의 증폭 의도는",
      "순위 기반 소비(top-N 선별·rank-IC)에서 실현되지 않는다 — 순위가 같기 때문."),
    identity_scope = paste(
      "★범위 한정(정직 라벨): 랭크 basis 에서 정보 손실 0. Z 값 basis 에서는",
      "제곱이 꼬리를 재배치하므로 z(C09) != z(C01) 이다 — 랭크가 아니라 z 값을",
      "가중합하는 소비자는 이 축약이 무손실이 아님을 인지할 것."),
    evidence = EV(max_rho = 0.9999982, min_rho = 0.9999838, max_abs_diff = 1.852,
                  basis = "signal_rank", verdict = "DUP_RANK_IDENTICAL"),
    consumption_rule = RULE_ALIAS),

  C10_SUE_Persistence = list(
    role = "alias", canonical = "C01_SUE", cluster = CL_SUE,
    deprecated_for_selection = TRUE, adjudicated = TRUE,
    mechanism = paste(
      "compute_consensus.R:249 C10 = mean(sue[1:min(N,4)]) — 의도는 '최근 4분기 평균",
      "(PEAD proxy)' 이나 실제로는 최근 4**영업일** 평균이라 latest 와 비트동일하다",
      "(실측 rho 1.000000, 최대절대차 0.000e+00)."),
    reason = "C01 = 창 결함에 오염되지 않은 원본. C10 은 현 빌드에서 C01 의 복제다.",
    defect = list(
      kind = "inert_rolling_window", detail = DEFECT_WINDOW,
      shares_root_cause_with = list("C13_Revision_Breadth_3m", "C15_Forecast_Error_Trend"),
      revisit_on = paste(
        ".cons_history() 가 분기 관측으로 축약되도록 수리되면 이 alias 선언은",
        "**무효**다 — 재측정 후 재선언할 것. 수리 전까지만 유효.")),
    evidence = EV(max_rho = 1.000000, min_rho = 1.000000, max_abs_diff = 0,
                  basis = "signal_rank", verdict = "DUP_EXACT_BITWISE"),
    consumption_rule = RULE_ALIAS),

  # ── cluster: revision_breadth (신규) ─────────────────────────────────────
  C04_ESBR = list(
    role = "canonical", cluster = CL_ESBR,
    aliases = list("C13_Revision_Breadth_3m"),
    adjudicated = TRUE, needs_review = FALSE,
    cluster_label = "revision_breadth",
    reason = paste(
      "C04 = compute_consensus.R:159 Raw_Value = esbr (원천 그대로).",
      "C13 은 그 3-관측 평균으로 등록됐으나 창이 무력해 비트동일."),
    evidence = EV(max_rho = 1.000000, max_abs_diff = 0),
    consumption_rule = paste("alias(C13)는 drop_alias_factors() 가 자동 축약한다.")),

  C13_Revision_Breadth_3m = list(
    role = "alias", canonical = "C04_ESBR", cluster = CL_ESBR,
    deprecated_for_selection = TRUE, adjudicated = TRUE,
    mechanism = paste(
      "compute_consensus.R:292 C13 = mean(esbr[1:min(N,3)]) — '3개월 롤링' 의도이나",
      "원천 esbr 이 일간이라 실제 창 span 중앙 2일·고유값 1개 ⇒ mean==latest",
      "(비율 1.0000, 2010/2018/2024). C04 와 비트동일(최대절대차 0.000e+00)."),
    reason = "C04 = 창 결함에 오염되지 않은 원본.",
    defect = list(
      kind = "inert_rolling_window", detail = DEFECT_WINDOW,
      shares_root_cause_with = list("C10_SUE_Persistence", "C15_Forecast_Error_Trend"),
      revisit_on = ".cons_history() 창 수리 후 이 선언은 무효 — 재측정 후 재선언."),
    evidence = EV(max_rho = 1.000000, min_rho = 1.000000, max_abs_diff = 0,
                  basis = "signal_rank", verdict = "DUP_EXACT_BITWISE"),
    consumption_rule = RULE_ALIAS),

  # ── cluster: earnings_streak (신규) ──────────────────────────────────────
  C11_Earnings_Streak = list(
    role = "canonical", cluster = CL_STREAK,
    aliases = list("M25_Earnings_Mom_Streak"),
    adjudicated = TRUE, needs_review = FALSE,
    cluster_label = "earnings_streak",
    reason = paste(
      "동일 신호가 계열 교차로 2중 등록(consensus C11 / momentum M25).",
      "C11 = consensus 네이티브 + 커버리지 우위(배출 원장 실측: 중앙 757행·누적",
      "217,198 vs M25 735행·204,800). 선례 정합 — M27_Analyst_Rev_Mom -> C02_EPS_Chg_1m",
      "도 momentum 카테고리 재등록을 alias 로 접었다."),
    evidence = EV(max_rho = 1.0000000, min_rho = 0.9999933, max_abs_diff = 0.168,
                  c11_median_rows = 757L, m25_median_rows = 735L),
    consumption_rule = "alias(M25)는 drop_alias_factors() 가 자동 축약한다."),

  M25_Earnings_Mom_Streak = list(
    role = "alias", canonical = "C11_Earnings_Streak", cluster = CL_STREAK,
    deprecated_for_selection = TRUE, adjudicated = TRUE,
    mechanism = paste(
      "compute_consensus.R:258-260 이 이미 'M25_Earnings_Mom_Streak",
      "(compute_momentum.R:339-360)과 식·원천·정렬이 동일' 이라고 2026-08-08 에",
      "기록했으나 그 제안이 registry 에 도달하지 않았다. 값으로 독립 재확인:",
      "rho 1.0000000 (최소 0.9999933), 최대절대차 0.168 — 잔차는 커버리지 차이",
      "(C11 757행 vs M25 735행)에서 온다."),
    reason = "C11 = consensus 네이티브 코드이며 커버리지가 넓다.",
    evidence = EV(max_rho = 1.0000000, min_rho = 0.9999933, max_abs_diff = 0.168,
                  basis = "signal_rank", verdict = "DUP_RANK_IDENTICAL"),
    consumption_rule = RULE_ALIAS)
)

cat(sprintf("[d7] 선언 블록 %d개: %s\n", length(blocks), paste(names(blocks), collapse = ", ")))

# ── 사전 검증 ───────────────────────────────────────────────────────────────
miss <- setdiff(names(blocks), names(reg0))
if (length(miss)) stop("[d7] registry 에 없는 팩터: ", paste(miss, collapse = ", "))
for (nm in names(blocks)) {
  b <- blocks[[nm]]
  if (identical(b$role, "alias")) {
    cn <- b$canonical
    if (is.null(reg0[[cn]])) stop("[d7] alias ", nm, " 의 canonical 부재: ", cn)
    if (!identical(blocks[[cn]]$role, "canonical"))
      stop("[d7] alias ", nm, " 의 canonical(", cn, ")이 canonical role 이 아님")
  }
}
cat("[d7] 사전 검증 OK (canonical 실재 + role 정합)\n")

# ── 쓰기 ────────────────────────────────────────────────────────────────────
apply_to <- function(path) {
  reg <- fromJSON(path, simplifyVector = FALSE)
  n_before <- length(reg); keys_before <- names(reg)
  before_json <- vapply(reg, function(e) toJSON(e, auto_unbox = TRUE, digits = NA),
                        character(1))

  for (k in names(blocks)) reg[[k]]$dedup <- blocks[[k]]

  if (DRY) { cat(sprintf("[d7] DRY-RUN — %s 미기록\n", basename(path))); return(invisible(NULL)) }

  bak <- sprintf("%s.bak_%s_dedup5", path, STAMP)
  if (!file.exists(bak)) file.copy(path, bak)
  tmp <- sprintf("%s.tmp%d", path, Sys.getpid())
  write_json(reg, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)

  chk <- fromJSON(tmp, simplifyVector = FALSE)
  if (length(chk) != n_before)        { unlink(tmp); stop("[d7] 엔트리 수 변화") }
  if (!identical(names(chk), keys_before)) { unlink(tmp); stop("[d7] 키 순서/집합 변화") }
  after_json <- vapply(chk, function(e) toJSON(e, auto_unbox = TRUE, digits = NA),
                       character(1))
  changed <- keys_before[before_json != after_json]
  if (!setequal(changed, names(blocks))) {
    unlink(tmp)
    stop("[d7] ★의도 밖 변경: ", paste(setdiff(changed, names(blocks)), collapse = ", "))
  }
  cat(sprintf("[d7] %s — 변경 팩터 %d개 (의도와 일치), 나머지 %d개 무변경\n",
              basename(path), length(changed), n_before - length(changed)))
  if (!file.rename(tmp, path)) { unlink(tmp); stop("[d7] rename 실패") }
  cat(sprintf("[d7] wrote %s (backup %s)\n", basename(path), basename(bak)))
}
for (p in present) apply_to(p)

if (!DRY && length(present) == 2L) {
  h <- vapply(present, function(p) unname(tools::md5sum(p)), character(1))
  if (h[1] == h[2]) cat(sprintf("[d7] 2벌 정합 OK (%s)\n", substr(h[1], 1, 12)))
  else stop("[d7] 2벌 md5 불일치")
}

# ── 재읽기 확인 ─────────────────────────────────────────────────────────────
if (!DRY) {
  r2 <- fromJSON(present[1], simplifyVector = FALSE)
  al <- names(r2)[vapply(r2, function(e) identical(e$dedup$role, "alias"), logical(1))]
  cat(sprintf("\n[d7] 재읽기: alias 총 %d종 = %s\n", length(al), paste(sort(al), collapse = ", ")))
  cl2 <- unlist(lapply(r2, function(e) if (is.null(e$dedup$cluster)) NULL else e$dedup$cluster))
  cat(sprintf("[d7] 재읽기: cluster %d개 / dedup 보유 %d종\n", length(unique(cl2)), length(cl2)))
  for (nm in names(blocks)) {
    d <- r2[[nm]]$dedup
    cat(sprintf("   %-26s role=%-9s cluster=%s%s\n", nm, d$role, d$cluster,
                if (!is.null(d$canonical)) paste0(" -> ", d$canonical) else ""))
  }
}
cat("[d7] done\n")
