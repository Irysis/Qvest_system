## Scout: Gap-driven S0 Hypotheses (SR gap 0.976, core_alpha)
cat("=== Scout: Gap-driven S0 Allocation ===\n")

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
library(jsonlite)

SG_CACHE <- file.path(PROJECT_ROOT, ".cache", "stage_gate")
dir.create(SG_CACHE, recursive = TRUE, showWarnings = FALSE)

manual_sg_init <- function(factor_id, strategy_id) {
  tracker <- list(
    factor_id = factor_id, strategy_id = strategy_id,
    current_stage = "S0_pending",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stage_log = list(
      S0 = list(status="pending",artifact=NULL,completed_at=NULL),
      S1 = list(status="blocked",artifact=NULL,completed_at=NULL),
      S2 = list(status="blocked",artifact=NULL,completed_at=NULL),
      S3 = list(status="blocked",artifact=NULL,completed_at=NULL),
      S4 = list(status="blocked",artifact=NULL,completed_at=NULL),
      S5 = list(status="blocked",artifact=NULL,completed_at=NULL),
      S6 = list(status="blocked",artifact=NULL,completed_at=NULL)
    )
  )
  write_json(tracker, file.path(SG_CACHE, paste0(factor_id, "_tracker.json")), auto_unbox=T, pretty=T)
}

hypotheses <- list(
  list(
    slug = "momentum_crowding_alpha",
    fid = "CR07_Momentum_Crowding",
    hyp = "Momentum crowding proxy: anti-crowded stocks outperform. Conditional IC matrix 1st (cond_value 0.114). Bad regime IC=0.083 — strongest defensive alpha across all unused factors.",
    rat = "Behavioral + structural: crowded momentum positions create fragility. When momentum reverses, crowded names crash hardest. Anti-crowding = contrarian alpha that activates during stress. Stein(2009) crowded trades, Lou-Polk(2022) comomentum.",
    src = "Stein (2009) Presidential address: Sophisticated investors and market efficiency; Lou & Polk (2022) Comomentum",
    pa = "Novel",
    eo = "CR카테고리 내 CR05/CR08과 부분 상관. M카테고리(momentum)와 음의 상관 기대. 기존 방어/품질 전략과 독립적.",
    why_now = "SR gap 0.976의 핵심 원인은 위기 구간 SR 저하. CR07의 ic_bad=0.083은 위기에서 방어 + alpha 동시 제공. 현재 포트폴리오에 crowding 차원 부재 — 새로운 alpha source.",
    role = "core_alpha",
    cond_value = 0.114, icir = -0.020, ic_bad = 0.083
  ),
  list(
    slug = "forward_pbr_value",
    fid = "V05_fPBR",
    hyp = "Forward PBR: consensus BPS 기반 밸류에이션. Bad regime IC=+0.015(양수), good regime IC=-0.034. Value-growth rotation의 regime-conditional alpha.",
    rat = "Risk premium + behavioral: value stocks underperform in bull markets but provide crash cushion. Forward PBR uses analyst consensus BPS — more timely than trailing. Asness et al.(2013) value everywhere.",
    src = "Asness et al. (2013) Value and momentum everywhere; Fama-French (1992)",
    pa = "Novel",
    eo = "V카테고리 내 V01_BM, V04_fPER과 상관 예상. 그러나 forward consensus 기반으로 trailing 대비 차별화. Quality/Defense와 직교 기대.",
    why_now = "현재 포트폴리오가 consensus/momentum 편향. Value 차원 부재가 SR 취약점. 하락장에서 positive IC = SR stabilizer. Growth rotation 시 방어 역할.",
    role = "core_alpha",
    cond_value = 0.049, icir = -0.221, ic_bad = 0.015
  ),
  list(
    slug = "altman_z_quality",
    fid = "Q24_Altman_Z",
    hyp = "Altman Z-score: 재무건전성 종합 지표. Bad regime IC=+0.013(양수) — 위기에서 distress 종목 회피 alpha. Quality 차원의 gap 보완.",
    rat = "Structural + risk premium: Altman(1968) Z-score는 부도 확률의 고전적 예측 모델. 고Z(건전) 종목은 위기 시 생존 → crisis alpha. Campbell et al.(2008) distress risk anomaly.",
    src = "Altman (1968) Financial ratios and prediction of bankruptcy; Campbell et al. (2008) In search of distress risk",
    pa = "Novel",
    eo = "Q카테고리 내 Q03_ROA, Q25_Ohlson_O와 부분 상관. 그러나 Z-score는 5개 재무비율 복합 → 단일 비율 대비 포괄적 정보. Defense와 약한 상관 기대.",
    why_now = "SR gap 해소에 crisis resilience 필수. Altman Z는 위기 전 distressed 종목 조기 배제 → MDD 방어 + SR 개선. 현재 quality sleeve에 distress screening 부재.",
    role = "core_alpha",
    cond_value = 0.034, icir = -0.043, ic_bad = 0.013
  )
)

cat(sprintf("[Scout] %d gap-driven hypotheses. Allocating...\n\n", length(hypotheses)))

for (h in hypotheses) {
  strat_id <- allocate_str(h$slug)
  art_dir <- file.path(PROJECT_ROOT, "04_Research/strategies", strat_id, "stage_artifacts")
  dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)
  manual_sg_init(h$fid, strat_id)

  s0 <- list(
    factor_id = h$fid, strategy_id = strat_id,
    hypothesis = h$hyp, economic_rationale = h$rat,
    prior_art = h$pa, source_reference = h$src,
    expected_orthogonality = h$eo,
    expected_role = h$role, why_now = h$why_now,
    gap_context = list(sr_gap = 0.976, sleeve_need = "core_alpha"),
    conditional_ic = list(cond_value = h$cond_value, icir_3y = h$icir, ic_bad = h$ic_bad),
    overlay = "none",
    overlay_note = "S0/S1 pure factor only. DD/VT/Regime at S5.",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    created_by = "scout_v5.0_gap_driven"
  )
  s0_path <- file.path(art_dir, sprintf("s0_record_%s.json", h$fid))
  write_json(s0, s0_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  [OK] %s | %s | cond_value %.3f | role: %s\n", strat_id, h$fid, h$cond_value, h$role))
}

cat("\n[Scout] === 3 gap-driven S0 records created ===\n")
