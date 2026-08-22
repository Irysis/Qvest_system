suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/config.R")
MB <- "qepm/mailbox/worktask/WT-D20260822_004"
f <- file.path(MB, "alpha_package.json"); d <- fromJSON(f, simplifyVector = FALSE)
old <- d$pit
d$pit <- list(
  sig_date = "2026-06-30", decision_ts = "2026-07-01",
  note = "팩터 sig_date T = T월 말 관측 -> 패널 anchor 는 T+1개월 스탬프. 발행 alpha_vector 의 홀딩월 anchor = 2026-07-01 이므로 그 결정에 쓰인 최종 관측은 2026-06-30. 선별 통계량은 anchor < 홀딩 anchor 인 실현 통계만 소비(rows (i-36)..(i-1)); 결합은 홀딩월 당월 z.",
  rules = old$rules, C13 = old$C13, C15 = old$C15,
  anchor_frame_verification_inherited = list(
    source = "WT-D20260822_002 (FQ-237) alpha_package.pit.anchor_frame_verification",
    transport_basis = "★동일 패널 파일을 소비한다 — stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet. 프레임 검증은 패널의 성질이므로 파일 동일성으로 승계된다(재측정 불요, 사본 아님).",
    documented_defect_signature = -0.9423,
    broken_frame_ic = -0.94230033, fixed_frame_ic = 0.0053261,
    n_factors_over_abs_0_10_fixed = 0,
    verdict = "위반 주입이 문서화된 지문을 재현했고 정상 프레임은 0/13 — 앵커 검사에 검출력이 있고 본 프레임은 정상."),
  panel_fidelity_inherited = list(source = "WT-D20260822_002 alpha_package.pit.panel_fidelity",
    n_ge_0_99 = 13, n_total = 13, median_cor = 0.99637849, min_cor = 0.9933122),
  this_round_pit_stress = list(
    LAG1 = "결합 입력 z 를 t-1 월 z 로 교체: PORT_t 0.9474 -> 0.3501 (부호·구조 유지, 붕괴 없음) = 동월 누출 징후 부재",
    LEAK1 = "결합 입력 z 를 t+1 월 z 로 교체(위반 주입): PORT_t 0.9474 -> 1.1825, paired +1.00%p/yr (t +0.667)",
    vintage_monotonicity = "LAG1 -2.44 / C0 0 / LEAK1 +1.00 %p/yr — 정보 신선도 축이 예측 방향으로 단조. 단 |t| 둘 다 2 미만이라 이 스트레스의 판별력은 제한적임을 명시(FQ-237 과 같은 한계).")
)
write_json(d, f, pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[patched pit]\n")
