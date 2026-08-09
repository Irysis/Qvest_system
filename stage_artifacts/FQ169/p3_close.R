## FQ-169 P3 — 판정 기록 + 원장 환류 + close_round
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ169")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }
S <- fread(file.path(OUT, "p2_divergence_summary.csv"))

V <- list(
  round_id = "FQ-169", parent = "WT-D20260809_003",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  prereg_ref = "stage_artifacts/FQ169/preregistration.json (측정 전 작성)",
  input_reality = list(rows = 81298L, months = 282L, period = "2003-01 ~ 2026-06",
    factors_loaded = 11L, load_path = "load_month_factors() 계약 경유 (C15)",
    coverage_min = 0.9749),
  verdict = "FAMILY_WIDE",
  prereg_classification = list(
    divergent_targets = S[role=="target" & cls=="DIVERGENT", factor],
    partial_targets   = S[role=="target" & cls=="PARTIAL", factor],
    aligned_targets   = S[role=="target" & cls=="ALIGNED", factor],
    n_divergent = S[role=="target" & cls=="DIVERGENT", .N],
    G1_family_wide = TRUE, G2_d03_specific = FALSE,
    G3_neg_controls_aligned = TRUE, G4_pos_control = S[role=="pos_control", cls]),
  stronger_finding = list(
    statistic = "sp_gap = spearman(decile, 평균초과 − 중앙값초과)",
    prereg_status = "사전등록 statistics 목록에 포함된 지표 — 사후 도입 아님",
    targets_range = c(min(S[role=="target", sp_gap]), max(S[role=="target", sp_gap])),
    pos_control = S[role=="pos_control", sp_gap],
    neg_controls = S[role=="neg_control", .(factor, sp_gap)],
    reading = paste0(
      "★대상 8종 + 양성대조 전부 sp_gap −0.95~−1.00, 음성대조는 +0.273/+0.721 — **겹침 0**. ",
      "즉 '평균−중앙값 격차가 decile 따라 감소' 라는 기전 자체는 vol/tail 계열에 **사실상 보편**이고, ",
      "DIVERGENT/PARTIAL/ALIGNED 분류 차이는 그 기전이 mean 프로파일의 **부호를 뒤집을 만큼 강한가**의 문제일 뿐이다. ",
      "sp_med 도 8종 전부 +0.855~+0.976 로 균질 — 갈리는 것은 sp_mean(−0.430~+0.297) 하나다."),
    honest_note = "분류 규칙(±0.30 문턱)이 이 연속체를 3구간으로 자른 것이며, 'DIVERGENT 4개' 라는 개수는 문턱 위치에 민감하다. 개수보다 sp_gap 분리가 강건한 진술이다."),
  declared_confound_realized = list(
    claim = "8종은 독립 8검정이 아니다 (사전등록 선언분)",
    measured_cor_spearman = "월평균 횡단면 상관 0.38~0.98 (D45↔D47 0.98 · D03↔D45 0.93 · D03↔D47 0.91 · D34↔D42 0.94)",
    row_identity = "D03_RealVol · D45_Downside_Dev · D47_CVaR_5pct 는 월별 행수·종목수가 완전 동일(536,458 / 3,352) — 동일 입력 계열 시사",
    implication = "★'4/8' 을 4건의 독립 확인으로 읽으면 안 된다. 유효 독립 개수는 그보다 훨씬 적다."),
  implication = paste0(
    "rank-IC(순위)와 PORT_t·평균(원수익)의 괴리는 D03 고유가 아니라 **vol/tail 계열 성질**이다. ",
    "measurement-graduation §2 가 rank-IC 를 ADVISORY 로 둔 규정의 적용 경계가 실측으로 그어졌다 — ",
    "변동성·꼬리 측도 계열에서는 rank-IC 를 재료 자격 근거로 인용하는 것이 구조적으로 위험하다."),
  scope_honesty = c(
    "1유니버스·282개월·gross 관측. 비용·회전율 층은 보지 않았다.",
    "align_factor_direction 이 IC-추론 방향정렬을 하므로 rank-IC 부호 자체를 독립 증거로 인용하지 않는다(사전등록 선언분). 괴리 판정은 두 프로파일 간 비교라 이 정렬에 영향받지 않는다.",
    "형태→소비면 대응은 여전히 미측정(FQ-170)."),
  artifacts = c("preregistration.json","p0_avail.R","p1_load.R","p2_divergence.R",
                "p2_divergence_summary.csv","p2_decile_detail.csv","panel.rds"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록")

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-169")
Q$entries[[i]]$status <- "family_wide_established_20260809"
Q$entries[[i]]$owner  <- "COMPLETE — Q-Lead session 2026-08-09. 후속은 FQ-170(형태별 소비면) 및 factor_registry 라벨 노출 제안."
Q$entries[[i]]$next_action <- paste0(
  "★판정 FAMILY_WIDE. 대상 8종 중 DIVERGENT 4(", paste(S[role=="target"&cls=="DIVERGENT", factor], collapse=", "),
  ") · PARTIAL 3 · ALIGNED 1. 양성대조 D03_RealVol DIVERGENT · 음성대조 M26/M01 둘 다 ALIGNED(설계 정상). ",
  "★★개수보다 강건한 진술 = **sp_gap 분리**: 대상+양성 9종 전부 −0.95~−1.00 vs 음성대조 +0.273/+0.721, **겹침 0**. ",
  "sp_med 도 8종 전부 +0.855~+0.976 균질 — 갈리는 건 sp_mean(−0.430~+0.297) 하나뿐이다. ",
  "⚠선언한 교락 실현: 8종 월평균 횡단면 상관 0.38~0.98(D45↔D47 0.98) + D03/D45/D47 행수·종목수 완전 동일 ⇒ **'4/8' 을 독립 4건으로 읽지 말 것**. ",
  "함의: rank-IC 를 vol/tail 계열의 재료 자격 근거로 인용하는 것은 구조적으로 위험 — measurement-graduation §2 ADVISORY 규정의 **적용 경계가 실측으로 그어졌다**.")
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ169/validation.json"
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 환류 완료 · 재읽기 status=%s",
    read_frontier_queue()$entries[[i]]$status)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-169", verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "평균/순위 괴리는 D03 고유가 아니라 vol/tail 계열 성질이다. 대상 8종 + 양성대조 전부에서 ",
    "(평균초과 − 중앙값초과) 격차가 decile 따라 단조 감소하고(sp_gap −0.95~−1.00) 중앙값 프로파일은 균질하게 상향(+0.855~+0.976)인데, ",
    "평균 프로파일만 −0.430~+0.297 로 갈린다. 즉 기전은 보편이고 분류 차이는 '기전이 부호를 뒤집을 만큼 강한가' 의 정도 문제다. ",
    "음성대조 M26·M01 은 sp_gap +0.721/+0.273 로 명확히 분리되어 측정 절차 산물이 아님이 확인됐다."),
  next_probes = c(
    "sp_gap 을 factor_registry 라벨로 노출 — 재료 자격 심사 시 'rank-IC 인용 위험' 플래그를 기계가 띄우게(현재는 사람이 기억해야 함).",
    "유효 독립 개수 추정 — 8종 상관 0.38~0.98 이라 '4/8' 이 과대 표시다. PCA 또는 클러스터로 유효 차원을 세고 그 위에서 재판정.",
    "FQ-170 형태별 소비면 대응 실측 — 괴리 재료는 랭킹이 아니라 어느 면에서 쓰여야 하는가. tail/CVaR 채널(FQ-108c 인접)이 1순위 후보.",
    "비용층 확장 — 본 라운드는 gross 다. 괴리가 net 에서 어떻게 변하는지는 미측정.",
    "M26 이 sp_gap +0.721 로 **반대 방향**인 이유 — 모멘텀·개정 계열은 상위 decile 이 더 우편향인가. 계열 대비 축으로 확장."),
  consumer_surfaces = c(
    "①팩터 랭킹 — vol/tail 계열은 rank-IC 로 랭킹 자격을 논하면 안 됨(실측 근거 확보)",
    "②유니버스 필터 — 미측정", "③오버레이 — 미측정",
    "④위험모델 — 괴리 재료의 자연 소비면 후보(꼬리 채널, FQ-108c 인접)",
    "⑤monitoring — sp_gap 상시 지표화 제안",
    "⑥선별 라벨 — factor_registry 플래그 노출(next_probe 1)",
    "⑦타 모드 — RAMP/FR 성분 선별 전 사전진단으로 이식"),
  frontier_update = "FQ-169 status=family_wide_established_20260809 (실제 기록 후 재읽기로 확인)",
  live_trigger = "sp_gap 라벨을 게이트로 승격하는 조건: ①유효 독립 개수 위에서 재판정 ②net(비용 반영) 에서도 분리 유지 ③FQ-170 에서 대체 소비면이 실측 지지. 그 전까지 sp_gap 은 **진단 플래그**이지 차단 기준이 아니다.",
  layer = "측정무결성 + ④construction",
  evidence_refs = c("stage_artifacts/FQ169/validation.json",
                    "stage_artifacts/FQ169/p2_divergence_summary.csv",
                    "stage_artifacts/WT_D20260809_003/alpha_validation.json"))
say("=== FQ-169 종료 ===")
