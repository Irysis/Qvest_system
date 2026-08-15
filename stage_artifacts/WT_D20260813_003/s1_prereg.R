## s1_prereg.R — WT-D20260813_003 사전등록 (측정 전 고정)
## ★본 스크립트는 예측기 sigma_hat 과 노출 매핑 e 만 만들고, 그것의 *주변 분포*로 검정력을
##   투영한다. 수익 계열 r 과의 정렬(=VT2/VT2b 통계량)은 여기서 계산하지 않는다.
##   s2_vt.R 이 그 뒤에 실행된다(파일 mtime 이 순서의 증거).
## 승계: alpha_hypothesis.json (판정순서 VT1->VT2->VT2b->VT4, basis=총 실현 vol, grid 금지)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/validation/overlay_pit_guard.R")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ── 1. 벤치 일별 원장 (WT-002 와 동일 원천·동일 말단 배제) ──────────────────
RB <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date", "BM_Ret")))
BD <- unique(RB, by = "Date")[order(Date)][is.finite(BM_Ret)]
BP <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date, BM_Ret2 = BM_Ret)]
par <- merge(BD, BP, by = "Date")
parity_cor <- cor(par$BM_Ret, par$BM_Ret2, use = "complete.obs")
cat(sprintf("[parity] daily bench overlap n=%d cor=%.6f\n", nrow(par), parity_cor))
BD <- BD[Date <= as.Date("2026-08-08")]      # 말단 0 채움 배제 (WT-002 규약)
cat(sprintf("[bench] daily n=%d  %s ~ %s\n", nrow(BD), min(BD$Date), max(BD$Date)))

## ── 2. 홀딩월 격자 + C5 컷오프 ──────────────────────────────────────────────
BD[, ym := format(Date, "%Y-%m")]
MO <- BD[, .(n_days_in_month = .N, last_day = max(Date)), by = ym][order(ym)]
MO[, hold_start := as.Date(paste0(ym, "-01"))]
## ★완료월 정의 — 원장 말단이 속한 달은 미완료 → 배제 (진행 중인 구간 동결 금지 교훈)
last_ym <- format(max(BD$Date), "%Y-%m")
MO[, complete_month := ym != last_ym]
cat(sprintf("[grid] months=%d  incomplete(excluded)=%s\n", nrow(MO), last_ym))

## ── 3. sigma_hat — trailing 252 거래일 실현변동성, Date < hold_start (raw level) ──
LB <- 252L
MO[, sigma_d := vapply(hold_start, function(cut) {
  r <- BD[Date < cut, BM_Ret]
  if (length(r) < LB) return(NA_real_)
  stats::sd(tail(r, LB))
}, numeric(1))]
MO[, used_cutoff := hold_start]
S <- MO[is.finite(sigma_d)]
assert_overlay_pit(S$used_cutoff, S$hold_start, label = "sigma_hat")
cat(sprintf("[pit] assert_overlay_pit PASS (sigma_hat)  n=%d  %s ~ %s\n", nrow(S), S$ym[1], S$ym[nrow(S)]))
S[, sigma_m := sigma_d * sqrt(21)]           # 월 스케일 (표시용 — 매핑은 비율이라 스케일 불변)

## ── 4. 승계 parity — 재구축 sigma_hat 이 승계 패널 VOL 과 같은 대상인가 ─────
## VOL(승계) = 전체 격자 위 expanding-z (vol_basis_correction.json 정본 basis)
exp_z <- function(x) { n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) { s <- stats::sd(x[1:i]); if (is.finite(s) && s > 0) o[i] <- (x[i] - mean(x[1:i])) / s }
  o }
S[, VOL_rebuilt := exp_z(sigma_d)]
P002 <- as.data.table(read_parquet("stage_artifacts/WT_D20260813_002/alpha_scores.parquet"))[, .(ym, VOL_inherited = VOL)]
J <- merge(S, P002, by = "ym")
inherit_cor_s   <- cor(J$VOL_rebuilt, J$VOL_inherited, method = "spearman", use = "complete.obs")
inherit_cor_p   <- cor(J$VOL_rebuilt, J$VOL_inherited, method = "pearson",  use = "complete.obs")
inherit_maxabs  <- max(abs(J$VOL_rebuilt - J$VOL_inherited), na.rm = TRUE)
cat(sprintf("[inherit] rebuilt vs inherited VOL: n=%d spearman=%.6f pearson=%.6f max|diff|=%.2e\n",
            nrow(J), inherit_cor_s, inherit_cor_p, inherit_maxabs))
if (!is.finite(inherit_cor_s) || inherit_cor_s < 0.99)
  stop("[inherit] 승계 parity 실패 — 재구축 sigma_hat 이 승계 VOL 과 다른 대상. 중단.")

## ── 5. 평가 표본 = 승계 367개월 ∩ 완료월 ────────────────────────────────────
EV <- merge(S, P002, by = "ym")[complete_month == TRUE][order(hold_start)]
theo <- nrow(P002)
cat(sprintf("[join] inherited=%d  after complete-month=%d  loss=%.2f%%\n",
            theo, nrow(EV), 100 * (1 - nrow(EV) / theo)))
if ((1 - nrow(EV) / theo) > 0.05) stop("[join] 손실 >5% — 키 컨벤션 의심, 중단")

## ── 6. 사전 고정 매핑 (grid 금지 — 각 1개) ──────────────────────────────────
## sigma_star = sigma_hat 의 expanding median (자기 교정값 — 자유 파라미터 아님).
## 전체 격자(S) 위에서 산출해 평가창 첫 달도 60개월+ 이력을 갖는다.
S[, sigma_star := vapply(seq_len(.N), function(i) stats::median(sigma_d[1:i]), numeric(1))]
E_MIN <- 0.50   # 노출 바닥 — 구조적 하한(현금 최대 50%). 대안 미측정.
E_MAX <- 1.00   # 레버리지 불가 (고정 축)
S[, e := pmin(E_MAX, pmax(E_MIN, sigma_star / sigma_d))]
EV <- merge(EV, S[, .(ym, sigma_star, e)], by = "ym")[order(hold_start)]

## ── 7. 검정력 사전 투영 — sigma_hat 주변분포만 사용 (수익 정렬 미사용) ──────
## 자기 정합 가정: 실현 월 분산 ∝ sigma_hat^2. 그러면
##   var(scaled) ∝ mean(e^2 * s^2),  var(control) ∝ ebar^2 * mean(s^2)
ebar_p  <- mean(EV$e)
s2      <- EV$sigma_d^2
G_proj  <- 1 - sqrt(mean(EV$e^2 * s2) / (ebar_p^2 * mean(s2)))
vol_base_ann <- stats::sd(EV$sigma_d) # 참고용
drag_proj_annual <- (ebar_p^2 * mean(s2) - mean(EV$e^2 * s2)) * 252 / 2   # sigma^2/2 드래그 절감(연)
cat(sprintf("[proj] ebar=%.4f  G_proj(relative vol timing gain)=%.4f  drag_proj=%.4f%%/yr\n",
            ebar_p, G_proj, 100 * drag_proj_annual))
cat(sprintf("[proj] e 분포: min=%.3f q25=%.3f med=%.3f q75=%.3f max=%.3f  bind(e<1)=%.1f%%  floor(e=%.2f)=%.1f%%\n",
            min(EV$e), quantile(EV$e,.25), median(EV$e), quantile(EV$e,.75), max(EV$e),
            100*mean(EV$e < 1), E_MIN, 100*mean(EV$e <= E_MIN + 1e-12)))

## ── 8. prereg 작성 (측정 전) ────────────────────────────────────────────────
prereg <- list(
  wt_id = "WT-D20260813_003",
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stage = "prereg_VT",
  authority = "alpha_hypothesis.json judgment_order 승계 — 재작성 아님",
  selection_type = "chain", n_trials = 1L,
  selection_note = "매핑 파라미터 grid 탐색 0회. sigma_star=expanding median(자기 교정값), e_min/e_max 각 1개 사전 고정. DSR HARD 부적용(sweep 아님) — 수치는 진단 산출.",
  panel = list(
    inherited_signal_panel = "stage_artifacts/WT_D20260813_002/alpha_scores.parquet",
    inheritance_parity = list(spearman = inherit_cor_s, pearson = inherit_cor_p,
      max_abs_diff = inherit_maxabs, n = nrow(J),
      note = "매핑 e=min(1, sigma*/sigma_hat) 은 z 가 아니라 level 을 요구하므로 동일 컷오프·동일 창으로 raw sigma_hat 을 재산출했다. 승계 VOL 과 동일 대상임을 spearman>=0.99 로 실증(재구축이지 재설계 아님)."),
    daily_source_parity_cor = parity_cor,
    n_months_eval = nrow(EV), window = c(EV$ym[1], EV$ym[nrow(EV)]),
    excluded_incomplete_month = last_ym
  ),
  mapping = list(
    formula = "e_m = clip(sigma_star_m / sigma_hat_m, 0.50, 1.00)",
    sigma_hat = "trailing 252 거래일 벤치 일수익 표준편차, Date < first-day-of-holding-month (C5)",
    sigma_star = "sigma_hat 의 expanding median (1..m) — 자기 교정값, 자유 파라미터 아님",
    e_min = E_MIN, e_max = E_MAX,
    e_max_rationale = "레버리지 불가 = 고정 축(AX-000 따름정리). 저변동기 e>1 경로는 설계상 부재.",
    e_min_rationale = "구조적 하한(현금 최대 50%). 데이터에서 도출한 값 아님 — 대안 바닥 미측정(grid 금지). VT2/VT2b 는 exposure-matched 통제라 바닥 수준에 판정이 의존하지 않는다.",
    cash_return = "rf = 0 가정. rf>0 이면 저노출 월이 현금이자를 벌어 처치군에 유리 — 따라서 보수적."
  ),
  judgment_rules = list(
    VT1 = list(role = "기록 의무(관문 아님)", stat = "spearman(sigma_hat_m, 홀딩월 내 실현 벤치 vol)",
               note = "1차 예측기 VOL = trailing 실현변동성 그 자체 — '더 나은 예측' 신규성 주장 없음(승계 자인)."),
    VT2 = list(role = "1차 판정",
      stat = "G = 1 - sd(e_m*r_m) / sd(ebar*r_m)   (basis = 총 실현 vol, active/TE 아님)",
      control = "exposure-matched: ebar = mean(e) — 노출 축소의 기계적 vol 감소를 제거",
      null = "e 계열 circular block permutation (block=6개월, B=2000). e 자기상관 보존 + r 과의 정렬만 파괴",
      pass_rule = "G > q95(null) AND G >= 0.02 (최소 효과크기, 승계 고정)",
      min_effect_provenance = "alpha_hypothesis.json effect_size_precalc 에서 승계(TAIL 조작점 산술). VOL 패널 재투영값 G_proj 를 아래 병기 — 문턱은 승계값 유지(사후 하향 금지)"),
    VT2b = list(role = "결정 관문",
      stat = "d_m = (e_m - ebar) * r_m ;  mean(d) 의 NW lag-3 t (.nw_t_mean 재사용, 자체합성 금지)",
      reject_rule = "t <= -2.0 이면 '수익 희생' 으로 기각",
      tie_rule = "점추정 음수·비유의면 순효과 = mean(d) + (var(control)-var(scaled))/2 (기하수익 근사) 부호로 판정"),
    VT3 = list(role = "PIT 무효 조건(상시)",
      checks = c("assert_overlay_pit HARD",
                 "lag1 스트레스: e shift(1) 판에서 G 붕괴 여부",
                 "strict-PIT A/B: 느슨 컷오프(동월말 정보) 판 대비 인플레 >5% 면 재판정",
                 "저변동 구간 유의 이득 = 누출 역진단(승계 boundary_rationale (a))")),
    VT4 = list(role = "성과 — VT2 PASS AND VT2b 비기각 시에만 착수",
      note = "canonical_screen_bt / forge 경로. 사전 기대 낮음(인접 negative 3건) 라벨 승계.")
  ),
  power_projection = list(
    metric_type = "design_projection_from_sigma_marginal",
    method = "실현 월 분산 ∝ sigma_hat^2 자기정합 가정. sigma_hat 주변분포만 사용 — VT2/VT2b 통계량(수익 정렬) 미사용.",
    mean_exposure = ebar_p,
    G_projected = G_proj,
    variance_drag_reduction_annual_pct = 100 * drag_proj_annual,
    bind_rate = mean(EV$e < 1), floor_rate = mean(EV$e <= E_MIN + 1e-12),
    e_quantiles = as.list(round(quantile(EV$e, c(0, .1, .25, .5, .75, .9, 1)), 4)),
    obligation_note = "승계 handoff (2) '효과크기 VOL 패널 재계산' 이행. 승계 설계 투영(+0.24%/yr, TAIL 조작점 산술)과 비교해 기록."
  ),
  falsification_inherited = "alpha_hypothesis.json::selected.falsification (재작성 금지 — 그대로 적용)"
)
write_json(prereg, file.path(OUT, "prereg_VT.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
saveRDS(list(EV = EV, S = S, BD = BD, MO = MO), file.path(OUT, "vt_inputs.rds"))
cat("\n[done] prereg_VT.json + vt_inputs.rds written — 측정 미착수\n")
