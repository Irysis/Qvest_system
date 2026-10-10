#==============================================================================
# mc2_l2v1.R — PR-L2-ROLESLEEVE-V1 단계 2: MC2_v1(방어 슬리브 v1 의 약세월 방어) 1회 측정 → verdict_v1/mc2_v1.json (덮어쓰기 거부)
#
# 1차(관문 · 사전등록 manipulation_checks.MC2_v1):
#   평가 창 보유월 2015-10~2026-09 중 사후 PS 약세월(06_Registry/strategy_role.json regimes.ps_bear = strategy_role.R::sr_regimes
#   — 평가 표적 전용)에서 mean(r_sleeve − r_candEW) > 0 ∧ NW lag-3 t ≥ 1.0 (v0 MC2 와 같은 문턱 · 비교 가능성).
#   r = 정본 월간화 모듈 월수익(rf_diversification_gate.R::rfd_monthly) · 슬리브 = 결정일 dd(보유월 첫날) β− 하위 삼분위 동일가중 ·
#   candEW = dd 적격 후보 동일가중 · 포함 월 = 슬리브 구성원 월수익 ≥1(v0 규칙).
#   t = backtest_result_contract.R::.nw_t_mean(lag 3)(v0 MC2 와 같은 계약) — beta_controlled_alpha(r_s, r_c)$port_t 와 항등 대조(lib).
# 2차(보고 · 관문 아님): 약세월 실현 β 차(beta_controlled_alpha) · v0 식 β-잔차 지표(strategy_role.R::sr_card — v1 슬리브·후보 EW) ·
#   비약세월 d · 평균 · 창 전체 β · 슬리브 크기.
# 잠금 대조(운영): v1 초안(색인 sha256) pins.mc2/lib/design = 이 파일들 · 라벨 매니페스트의 잠금 초안 sha = 같은 초안 ·
#   매니페스트 builder sha = pins.labels_builder · 라벨 parquet sha = 매니페스트.
# L2V1_DRYRUN=1 = 잠금 전 코드 검사(L2V1_OUT_DIR 의 드라이런 라벨 · 보유월 L2V1_DRY_FIRST~L2V1_DRY_LAST < 평가 창 · 값 미출력).
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("mc2_l2v1.R")'
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[mc2_l2v1] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
PREREG_ID <- "PR-L2-ROLESLEEVE-V1"
sha <- function(p) digest::digest(file = p, algo = "sha256")
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
absp <- function(p) if (grepl("^([A-Za-z]:)?[/\\\\]", p)) p else file.path(ROOT, p)
SELF <- file.path(L2DIR, "mc2_l2v1.R"); LIB <- file.path(L2DIR, "lib_l2v1.R"); DESIGN_P <- file.path(L2DIR, "l2v1_design.json")
DESIGN <- fromJSON(DESIGN_P, simplifyVector = FALSE)
source(LIB)
first_hm <- as.Date(DESIGN$window$first_holding_month); last_hm <- as.Date(DESIGN$window$last_holding_month)

# ── 0. 모드 · 잠금 대조 ─────────────────────────────────────────────────────────
DRY <- identical(Sys.getenv("L2V1_DRYRUN", ""), "1")
if (DRY) {
  OUT <- normalizePath(Sys.getenv("L2V1_OUT_DIR", ""), winslash = "/", mustWork = TRUE)
  if (startsWith(tolower(OUT), tolower(normalizePath(L2DIR, winslash = "/")))) stop("[mc2_l2v1] 드라이런 출력은 이 디렉터리 밖")
  MAN_P <- file.path(OUT, "l2v1_inputs_manifest.json")
  HM <- seq(as.Date(Sys.getenv("L2V1_DRY_FIRST")), as.Date(Sys.getenv("L2V1_DRY_LAST")), by = "month")
  if (!length(HM) || max(HM) >= first_hm) stop("[mc2_l2v1] 드라이런 보유월은 평가 창 앞이어야 한다")
  THR <- as.numeric(DESIGN$mc2_v1$t_threshold); LAG <- as.integer(DESIGN$mc2_v1$nw_lag)
  LOCK <- list(mode = "dryrun")
} else {
  OUT <- file.path(L2DIR, "verdict_v1"); MAN_P <- file.path(L2DIR, "work/l2v1_inputs_manifest.json")
  HM <- seq(first_hm, last_hm, by = "month")
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
  pcfg <- rf_prereg_config(ROOT)
  pr <- rf_prereg_load(PREREG_ID, "draft", root = ROOT, cfg = pcfg)
  integ <- attr(pr, "integrity")
  need <- list(mc2 = SELF, lib = LIB, design = DESIGN_P)
  for (k in names(need)) if (!identical(pr$pins[[k]]$sha256, sha(need[[k]])))
    stop(sprintf("[mc2_l2v1] %s sha256 ≠ 초안 pins.%s — 잠금 뒤 변경(개정 = 새 초안 rev)", need[[k]], k))
  mc <- pr$manipulation_checks$MC2_v1
  THR <- as.numeric(mc$nw_t_threshold); LAG <- as.integer(mc$nw_lag)
  if (!isTRUE(abs(THR - as.numeric(DESIGN$mc2_v1$t_threshold)) < 1e-12) || !identical(LAG, as.integer(DESIGN$mc2_v1$nw_lag)))
    stop("[mc2_l2v1] 초안 MC2_v1 문턱/lag ≠ 설계")
  LOCK <- list(mode = "production", draft_path = integ$path, draft_sha256 = integ$sha256, draft_rev = integ$rev, verified_at = integ$verified_at)
}
stopifnot(is.finite(THR), is.finite(LAG), LAG >= 1L)
out_json <- file.path(OUT, "mc2_v1.json")
if (file.exists(out_json)) stop("[mc2_l2v1] MC2_v1 은 1회 — 이미 있다: ", out_json)
if (!file.exists(MAN_P)) stop("[mc2_l2v1] 라벨 매니페스트 없음(빌더 먼저): ", MAN_P)
MAN <- fromJSON(MAN_P, simplifyVector = FALSE)
LAB_P <- absp(MAN$files$defensive_labels$path)
if (!identical(sha(LAB_P), MAN$files$defensive_labels$sha256)) stop("[mc2_l2v1] 라벨 parquet sha256 ≠ 매니페스트")
if (!DRY) {
  if (!identical(MAN$lock$mode, "production") || !identical(MAN$lock$draft_sha256, LOCK$draft_sha256))
    stop("[mc2_l2v1] 라벨이 이 초안 잠금 뒤에 만들어지지 않았다(매니페스트 lock ≠ 초안)")
  if (!identical(MAN$builder$sha256, pr$pins$labels_builder$sha256) || !identical(MAN$lib$sha256, pr$pins$lib$sha256))
    stop("[mc2_l2v1] 라벨 빌더/lib sha256 ≠ 초안 pins")
}
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── 1. 자료 · 정본 계약 ─────────────────────────────────────────────────────────
lab <- as.data.table(read_parquet(LAB_P))
lab[, decision_date := as.Date(decision_date)][, ym := format(decision_date, "%Y-%m")]
hm_ym <- format(HM, "%Y-%m")
if (!all(hm_ym %in% lab$ym)) stop("[mc2_l2v1] 보유월 일부에 라벨이 없다")
source(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R"))
scfg <- sr_cfg(ROOT); dcfg <- .sr_env$rfd_cfg(ROOT)
bm <- .sr_env$rfd_bench_daily(ROOT, dcfg); fac <- .sr_env$rfd_factor_monthly(ROOT, dcfg); R <- sr_regimes(bm)
bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
cand <- fread(file.path(ROOT, DESIGN$candidates$file))
mon <- rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  s <- .sr_env$rfd_read_series(file.path(ROOT, cand$series_dir[i], "03_period_returns.csv"))
  m <- .sr_env$rfd_monthly(s, bm, NULL)
  if (is.null(m)) return(NULL)
  m[, .(member_id = cand$member_id[i], ym, r)]
}))
bca_env <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R"), envir = bca_env, keep.source = FALSE)
bt_env <- new.env(parent = globalenv())
for (e in as.list(parse(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"), encoding = "UTF-8", keep.source = FALSE)))
  if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && identical(as.character(e[[2]]), ".nw_t_mean")) eval(e, bt_env)
if (!is.function(bt_env$.nw_t_mean)) stop("[mc2_l2v1] .nw_t_mean 계약 판독 실패")

# ── 2. MC2_v1 ──────────────────────────────────────────────────────────────────
x <- l2v1_mc2_table(mon, lab[, .(ym, member_id, eligible, in_sleeve)], hm_ym, bmm)
st <- l2v1_mc2_stats(x, R, bt_env$.nw_t_mean, bca_env$beta_controlled_alpha, LAG, THR)
v0_style <- function(rcol) {   # v0 MC2 판정식(sr_card 방어 평균 · 창 전체 β 잔차 · NW t) — 보고 전용
  mdt <- merge(merge(x[, .(ym, r = get(rcol))], bmm, by = "ym"), fac, by = "ym", all.x = TRUE)[order(ym)]
  card <- sr_card(mdt, R, scfg)
  if (!identical(card$status, "ok")) return(list(status = card$status, n_months = card$n_months))
  mm2 <- merge(mdt, R, by = "ym")[order(ym)]
  e_res <- mm2$r - card$beta * mm2$b; bear <- mm2$ps_bear %in% TRUE
  nwt <- bt_env$.nw_t_mean(e_res[bear], lag = LAG)
  list(status = "ok", n_months = card$n_months, beta = card$beta, n_bear_months = sum(bear), mean_bear_resid = card$roles$defensive$mean,
       mean_bear_resid_recomputed = mean(e_res[bear]), t_plain = card$roles$defensive$t, nw_t = nwt, grade_role_defensive = card$roles$defensive$grade,
       pass_v0_rule = isTRUE(card$roles$defensive$mean > 0) && isTRUE(nwt >= THR), note = "v0 MC2 식(β 를 통제한 잔차) — 보고 전용 · 관문 아님")
}
V0S <- list(sleeve_v1 = v0_style("r_s"), candidate_ew = v0_style("r_c"))
lab_w <- lab[ym %in% hm_ym, .(n_eligible = n_eligible[1], n_low = n_low[1]), by = ym]
q3 <- function(v) { v <- v[is.finite(v)]; if (!length(v)) return(NULL); list(min = min(v), median = stats::median(v), max = max(v)) }
tab <- st$table
RES <- list(
  schema = "l2v1_mc2_v1", prereg_id = PREREG_ID, at = now(), lock = LOCK,
  window = list(first_holding_month = format(min(HM)), last_holding_month = format(max(HM)), n_holding_months = length(HM),
                n_months_included = st$n_months, first_ym = st$first_ym, last_ym = st$last_ym, n_bear_months = st$n_bear_months),
  rule = list(primary = "mean_bear(r_sleeve − r_candEW) > 0 ∧ NW lag-3 t ≥ 문턱", t_threshold = THR, nw_lag = LAG,
              contract_t = "backtest_result_contract.R::.nw_t_mean (교차 확인 beta_controlled_alpha port_t)",
              bear_months = "strategy_role.R::sr_regimes(정본 벤치 전기간) ps_bear — 사후 PS 연대기 · 평가 표적 전용",
              months = "평가 창 보유월 ∩ 슬리브 구성원 월수익 ≥1 ∩ 벤치 월(v0 MC2 포함 규칙)"),
  primary = st$primary, pass = isTRUE(st$primary$pass),
  decision = if (isTRUE(st$primary$pass)) "PASS — 단계 3(arm 측정) 진행 자격" else "FAIL — 단계 2에서 종료(arm 미측정 · H1 라벨 없음)",
  secondary = c(st$secondary, list(v0_style = V0S)),
  sleeve_size = list(labels_n_eligible = q3(lab_w$n_eligible), labels_n_low = q3(lab_w$n_low),
                     sleeve_members_with_return = q3(tab$n_s), candidates_with_return = q3(tab$n_c),
                     by_month = lapply(seq_len(nrow(lab_w)), function(i) list(ym = lab_w$ym[i], n_eligible = lab_w$n_eligible[i], n_low = lab_w$n_low[i]))),
  bear_months = as.list(tab[ps_bear %in% TRUE]$ym),
  monthly = lapply(seq_len(nrow(tab)), function(i) list(ym = tab$ym[i], ps_bear = isTRUE(tab$ps_bear[i]), n_s = tab$n_s[i], n_c = tab$n_c[i],
                                                       r_s = tab$r_s[i], r_c = tab$r_c[i], d = tab$d[i], b = tab$b[i])),
  inputs = list(manifest = list(path = sub(paste0("^", ROOT, "/"), "", MAN_P), sha256 = sha(MAN_P)),
                labels = list(path = MAN$files$defensive_labels$path, sha256 = MAN$files$defensive_labels$sha256),
                benchmark = list(path = attr(bm, "rfd_path"), sha256 = sha(attr(bm, "rfd_path")), mtime = attr(bm, "rfd_mtime")),
                strategy_role_cfg_sha256 = sha(file.path(ROOT, "06_Registry/strategy_role.json")),
                code = list(mc2 = sha(SELF), lib = sha(LIB), design = sha(DESIGN_P))),
  not_a_grade = "MC2_v1 은 단계 3 진입 관문(기전 전제 조작 확인)이다 — 등급·H1 라벨이 아니다")
writeLines(toJSON(RES, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out_json, useBytes = TRUE)
if (DRY) {
  cat(sprintf("[mc2_l2v1] dryrun · 포함 월 %d · 약세월 %d · 값 유한 %s · v0식 상태 %s/%s · 기록 %s (값 미출력)\n", st$n_months, st$n_bear_months,
              all(is.finite(c(st$primary$value, st$primary$t, st$secondary$bear_beta_diff$value))), V0S$sleeve_v1$status, V0S$candidate_ew$status, out_json))
} else {
  cat(sprintf("[mc2_l2v1] MC2_v1 %s · 약세월 %d/%d · mean d %+.4f%%/월 · NW t %.3f (문턱 %.2f) · β 차 %+.3f · sha %s\n",
              if (RES$pass) "PASS" else "FAIL", st$n_bear_months, st$n_months, 100 * st$primary$value, st$primary$t, THR,
              st$secondary$bear_beta_diff$value, substr(sha(out_json), 1, 12)))
}
