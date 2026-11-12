## P1R04 계보 짝 읽기(사전등록 결론 범위의 '읽는 법' 그대로 · 측정 전 고정 · 사양 pins 에 든다)
##   판단 T1 C-20261113-001(짝 통계 · 같은 배치 기준) · 철학 P1 C-20261113-026(강점 · 위기) · C-028(크기 성분) 수용.
##   계보(카테고리 14 + 토탈)마다 T1 칸(variant) ↔ 같은 배치 T0 기준 칸(reference · P1R03 같은 칸 재측정)을 짝짓는다.
##   ① 짝 증분 = 코어 R 계약 rc_pair_alpha(월 수익 차 T1 − T0 의 β-통제 알파 · NW lag 3 · 겹치는 달만)의 **보는 창** 증분 t
##   ② 표식(보는 창 진단 패킷 results/<칸>/visible/diagnosis_packet.json — 칸 평가가 쓴 계약 산출 · 손계산 없음):
##      strength_loss = T1 강세 상승 포착 중앙값 < 기준 − (1 − RC_P4_UC_SEG_KEEP)·|기준|(헌장 §5 빈칸 4 (B) · 13 — 기준 = 같은 계보 T0)
##      crisis_worse  = T1 위기 하락노출(낙폭 포착) 중앙값 > T0
##      size_tilt     = T1 크기 성분(동일가중−시총가중 · 연환산) > T0 ∧ T1 선택 성분(연환산) < T0
##   ③ 판정(측정 전 고정 · 문턱 = constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t):
##      셈 대상 짝 = 증분 t ≥ 문턱 ∧ 표식 없음 · 지지 = 셈 대상 계보 ≥ 2 또는 토탈 계보가 셈 대상 · 반증 = 그 밖(15 짝 모두 측정됐을 때만) ·
##      미측정 짝은 셈에서 빠진다(지지는 측정된 짝만으로도 · 반증이 아닌데 미측정 짝이 있으면 미시험)
##   ④ 서술: 원천 수(P1R03 셈법 — 토탈 제외 · 저위험 4 카테고리 = 한 원천 · 사이드카 저위험 쏠림 꼬리표가 붙은 카테고리는 저위험 묶음에 넣는다 ·
##      같은 배치 T0 에 없던 원천은 그 계보가 셈 대상 짝일 때만 'T1 이 연 원천') · 부호 셈(증분 t > 0) · 짝 기록(강세 구간 비 · 위기 · CDaR · β)
##   출력 = results/pair_reading_visible.json(보는 창 값만) · 표준출력 요약.
## 쓰기(저장소 루트 · 평가 연쇄 뒤): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_pair_reading.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
suppressPackageStartupMessages(library(data.table))
RD <- commandArgs(trailingOnly = TRUE)[1] %||% "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"   # 인자 = 라운드 폴더(시험용 · 기본 = 이 라운드)
RDA <- if (grepl("^([A-Za-z]:|/)", RD)) RD else file.path(ROOT, RD)
S <- rc_spec_load(file.path(RDA, "round_spec.json"), root = ROOT, check_files = FALSE)
TAU <- as.Date(S$tau_d)
THR <- as.numeric(rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t", ROOT))
KEEP <- as.numeric(RC_P4_UC_SEG_KEEP)                         # 헌장 §5 빈칸 4 (B) '같은 엔진 기준의 80%' — 코어 p4.R 단일 출처
if (!is.finite(THR) || !is.finite(KEEP)) stop("[p1r04 pair] 문턱 · 보존 비율을 정본에서 읽지 못했다")
LOWRISK <- c("defense", "risk", "liquidity", "regime")       # P1R03 결론 범위의 원천 셈법
num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))); if (length(v) == 1L) v else NA_real_ }
ev <- function(code) tryCatch(rc_json_read(file.path(RDA, "results", code, "eval.json")), error = function(e) NULL)
pk <- function(code) tryCatch(rc_json_read(file.path(RDA, "results", code, "visible", "diagnosis_packet.json")), error = function(e) NULL)
comp <- function(p, nm) { s <- p$exposure$summary; if (is.null(s)) return(NA_real_)
  r <- Filter(function(x) identical(x$component, nm), s); if (length(r)) num(r[[1]]$ann_mean) else NA_real_ }
keep_ok <- function(t1, t0) is.finite(t1) & is.finite(t0) & t1 >= t0 - (1 - KEEP) * abs(t0)
cells <- rbindlist(lapply(S$cells, function(c) data.table(code = c$code, engine = c$engine, role = c$role, lineage = c$lineage %||% NA_character_)))
if (anyNA(cells$lineage)) stop("[p1r04 pair] 사양 칸에 lineage 표식이 없다")
E <- rc_deps(ROOT)
V <- rc_json_read(file.path(RDA, "results", "evaluation_visible.json"))
TB <- data.table(code = vapply(V$table, function(r) as.character(r$code %||% NA_character_), ""),   # 표 = 행 목록(rc_json_read simplifyVector = FALSE)
                 qualify = vapply(V$table, function(r) isTRUE(r$qualify), TRUE))
q <- function(cc) { x <- TB[TB$code == cc]; if (nrow(x)) isTRUE(x$qualify[1]) else NA }
SC <- tryCatch(rc_json_read(file.path(RDA, "results", "lowrisk_share_visible.json")), error = function(e) NULL)   # 저위험 몫 사이드카(철학 C-027 · 없으면 꼬리표 미적용 · 서술에 표기)
tilt_tag <- function(ln) { if (is.null(SC)) return(NA); x <- SC$tags[[ln]]; if (is.null(x)) NA else isTRUE(x) }
rows <- list()
for (ln in unique(cells$lineage)) {
  v <- cells[lineage == ln & role == "variant"]; b <- cells[lineage == ln & role == "reference"]
  if (nrow(v) != 1L || nrow(b) != 1L) stop("[p1r04 pair] 계보 ", ln, " 의 짝이 1:1 이 아니다")
  ev_v <- ev(v$code); ev_b <- ev(b$code)
  ok <- identical(ev_v$status, "evaluated") && identical(ev_b$status, "evaluated")
  pa <- if (ok) tryCatch(rc_pair_alpha(E, ev_v$artifacts, ev_b$artifacts, TAU)$visible, error = function(e) NULL) else NULL
  p1 <- if (ok) pk(v$code) else NULL; p0 <- if (ok) pk(b$code) else NULL
  b1 <- p1$behavior$summary; b0 <- p0$behavior$summary
  uc1 <- num(b1$bull_up_capture_median); uc0 <- num(b0$bull_up_capture_median)
  dd1 <- num(b1$crisis_dd_capture_median); dd0 <- num(b0$crisis_dd_capture_median)
  ew1 <- comp(p1, "ew_cw"); ew0 <- comp(p0, "ew_cw"); se1 <- comp(p1, "selection"); se0 <- comp(p0, "selection")
  ## 강세 구간 비(기록) — 시작 연월로 맞춘 구간 중 T1 상승 포착 ≥ 기준 − (1 − KEEP)·|기준| 인 비율
  bp1 <- p1$behavior$bull_phases; bp0 <- p0$behavior$bull_phases
  bseg <- if (length(bp1) && length(bp0)) {
    m0 <- setNames(vapply(bp0, function(z) num(z$up_capture), 1), vapply(bp0, function(z) as.character(z$start_ym), ""))
    m1 <- setNames(vapply(bp1, function(z) num(z$up_capture), 1), vapply(bp1, function(z) as.character(z$start_ym), ""))
    k <- intersect(names(m0), names(m1)); if (length(k)) mean(keep_ok(m1[k], m0[k])) else NA_real_ } else NA_real_
  ## 깊은 위기 비악화 비(기록) — 시작일로 맞춘 위기 중 시장 낙폭이 중앙값 이상인 위기에서 T1 낙폭 포착 ≤ T0 인 비율
  cr1 <- p1$behavior$crises; cr0 <- p0$behavior$crises
  deep <- if (length(cr1) && length(cr0)) {
    f <- function(cr) data.table(pk = vapply(cr, function(z) as.character(z$peak_date), ""), bm = vapply(cr, function(z) num(z$bm_dd), 1),
                                 dc = vapply(cr, function(z) num(z$dd_capture), 1))
    X <- merge(f(cr1), f(cr0), by = "pk", suffixes = c("1", "0")); X <- X[is.finite(bm0) & is.finite(dc1) & is.finite(dc0)]
    if (nrow(X)) { thr <- stats::median(abs(X$bm0)); D <- X[abs(bm0) >= thr]; if (nrow(D)) mean(D$dc1 <= D$dc0) else NA_real_ } else NA_real_ } else NA_real_
  rows[[ln]] <- data.table(lineage = ln, t1 = v$code, t0_ref = b$code, status = if (is.null(pa)) "untested" else "evaluated",
                           d_t_vis = pa$t %||% NA_real_, d_alpha_ann_vis = pa$d_alpha %||% NA_real_, n_vis = pa$n %||% NA_integer_,
                           window_vis = if (is.null(pa)) NA_character_ else paste(pa$window, collapse = "~"),
                           uc_t1 = uc1, uc_t0 = uc0, dd_med_t1 = dd1, dd_med_t0 = dd0,
                           dd_worst_t1 = num(b1$crisis_dd_capture_worst), dd_worst_t0 = num(b0$crisis_dd_capture_worst),
                           cdar_t1 = num(p1$behavior$stats$cdar), cdar_t0 = num(p0$behavior$stats$cdar),
                           beta_t1 = num(p1$behavior$stats$beta), beta_t0 = num(p0$behavior$stats$beta),
                           ew_cw_t1 = ew1, ew_cw_t0 = ew0, selection_t1 = se1, selection_t0 = se0,
                           bull_seg_keep_share = bseg, deep_crisis_nonworse_share = deep,
                           strength_loss = !keep_ok(uc1, uc0), crisis_worse = is.finite(dd1) & is.finite(dd0) & dd1 > dd0,
                           size_tilt = is.finite(ew1) & is.finite(ew0) & is.finite(se1) & is.finite(se0) & ew1 > ew0 & se1 < se0,
                           lowrisk_tilt_tag = tilt_tag(ln), t1_qualify = q(v$code), t0_ref_qualify = q(b$code))
}
P <- rbindlist(rows)
P[, pass_t := is.finite(d_t_vis) & d_t_vis >= THR]
P[, counted := pass_t & !strength_loss & !crisis_worse & !size_tilt]
src_of <- function(ln, tg) if (ln %in% LOWRISK || isTRUE(tg)) "lowrisk" else if (identical(ln, "total")) NA_character_ else ln
P[, source := mapply(src_of, lineage, lowrisk_tilt_tag)]
n_cnt <- sum(P$counted); tot_cnt <- isTRUE(P[lineage == "total"]$counted)
## 미측정 짝은 셈에서 빠진다(격리 점검 v1 R-4) — 지지는 측정된 짝만으로도 · 반증은 15 짝이 모두 측정됐을 때만(아니면 미시험)
P[status != "evaluated", `:=`(pass_t = FALSE, counted = FALSE)]
n_cnt <- sum(P$counted); tot_cnt <- isTRUE(P[lineage == "total"]$counted)
verdict <- if (n_cnt >= 2L || tot_cnt) "support" else if (all(P$status == "evaluated")) "falsified" else "untested"
src_t1 <- sort(unique(na.omit(P[t1_qualify %in% TRUE]$source))); src_t0 <- sort(unique(na.omit(P[t0_ref_qualify %in% TRUE]$source)))
src_new <- sort(unique(na.omit(P[t1_qualify %in% TRUE & counted & !(source %in% src_t0)]$source)))
out <- list(schema = "p1r04_pair_reading_visible_v2", round_id = S$round_id, audience = "보는 창(τ_D 이전)만 — 시험 창 값 없음",
            threshold = THR, threshold_ref = "02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t",
            uc_keep = KEEP, uc_keep_ref = "round_core p4.R RC_P4_UC_SEG_KEEP(헌장 §5 빈칸 4 (B) · 13)",
            rule = "셈 대상 짝 = 증분 t ≥ 문턱 ∧ 강점 손실 · 위기 악화 · 크기 틸트 표식 없음 · 지지 = 셈 대상 계보 ≥ 2 또는 토탈 셈 대상 · 반증 = 그 밖(15 짝 모두 측정됐을 때만) · 미측정 짝 = 셈 밖",
            verdict = verdict, n_lineages = nrow(P), n_pass_t = sum(P$pass_t), n_counted = n_cnt, total_counted = tot_cnt,
            n_positive = sum(is.finite(P$d_t_vis) & P$d_t_vis > 0),
            n_tag = list(strength_loss = sum(P$strength_loss), crisis_worse = sum(P$crisis_worse), size_tilt = sum(P$size_tilt)),
            lowrisk_sidecar = if (is.null(SC)) "absent(꼬리표 미적용)" else "applied",
            sources_t1 = as.list(src_t1), sources_t0_ref = as.list(src_t0), sources_new_counted = as.list(src_new), table = P)
lk <- rc_after_tau_leaks(out, TAU); if (length(lk)) stop("[p1r04 pair] 출력에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
rc_json_write(out, file.path(RDA, "results", "pair_reading_visible.json"))
cat(sprintf("[p1r04 pair] %s — 증분 t ≥ %.1f 계보 %d/%d · 표식 뒤 셈 대상 %d · 토탈 %s · 양의 증분 %d · 표식(강점 %d · 위기 %d · 크기 %d) · T1 원천 %s · 같은 배치 T0 원천 %s · T1 이 연 원천 %s · 사이드카 %s\n",
            verdict, THR, sum(P$pass_t), nrow(P), n_cnt, if (tot_cnt) "셈 대상" else "아님", out$n_positive, sum(P$strength_loss), sum(P$crisis_worse),
            sum(P$size_tilt), paste(src_t1, collapse = ","), paste(src_t0, collapse = ","), if (length(src_new)) paste(src_new, collapse = ",") else "없음",
            out$lowrisk_sidecar))
