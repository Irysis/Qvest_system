# catalog_admit_3.R — 비중 카탈로그 3종 등재(2026-11-11 · 도훈 승인 "네, 시작" · 설계 README §5)
#   구성 규칙 2(왜도 위험 패리티 · 위상 위험 패리티) = 논문 어댑터 검증 등재 · 위험 예측 1(등방 상관) = 기존 qepm:MVO 추정기 가족의 확장 형제.
#   사용(저장소 루트에서): Rscript 04_Research/01_reports/portfolio_paper_layer_split_20261112/scripts/catalog_admit_3.R [--commit]
#     --commit 없이 = 건식(등록부 · 원장 · 생성물 · 색인을 쓰지 않는다). --commit = 실제 등재 + 재색인(sync_catalog(probe = TRUE)).
#   성과를 읽지 않는다(검증은 합성 자료 계약 검사뿐). 등재 뒤 측정은 강화 사슬(P4) · 구성 프로그램(P3)이 한다.
args <- commandArgs(trailingOnly = TRUE)
COMMIT <- "--commit" %in% args
ROOT <- gsub("\\\\", "/", getwd())
stopifnot(file.exists(file.path(ROOT, "CLAUDE.md")), dir.exists(file.path(ROOT, "06_Registry")))
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)     # 등재 도구들이 루트를 환경변수로 찾는다 — 이 저장소로 고정
suppressWarnings(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/methods/register_method.R"))
}))
stopifnot(identical(gsub("\\\\", "/", .rm_root()), ROOT))
DESIGN <- "04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §5"
ROUTED <- function(test) sprintf("2026-11-11 · 4분법 분류(구성 규칙) → 비중 카탈로그 등재 · 도훈 승인 · 설계 %s · 검사 %s", DESIGN, test)

cat(sprintf("== 비중 카탈로그 3종 등재 — %s ==\n", if (COMMIT) "실제 등재" else "건식(무기록)"))

## ── 1. 왜도 위험 패리티(arXiv 2202.10721) ──────────────────────────────────────
r1 <- register_method(
  method_id = "SkewRPBKR2022", paper_id = "arxiv:2202.10721",
  paper_title = "Risk Parity Portfolios with Skewness Risk: An Application to Factor Investing and Alternative Risk Premia (Bruder · Kostyuchyk · Roncalli)",
  route = "optimizer", adapter_kind = "weight",
  adapter = "02_Infrastructure/methods/adapters/skew_rp_bruder_kostyuchyk_roncalli_2022.R",
  mechanism = paste0(
    "수익을 정상 국면 N(μ, Σ)과 점프 국면 N(μ+μ̃, Σ+Σ̃)의 2성분 가우시안 혼합으로 두고(§2.1.2), 혼합분포 99% 기대 손실(ES · 식 es1)의 ",
    "종목별 위험 기여(식 rc1)를 균등 예산에 맞춘다(§3.3 · 풀이 y* = argmin ES(y) − Σ b ln y). 점프가 없으면 가우시안 ES 위험 패리티 = 변동성 ",
    "ERC 와 같은 해다(§4.2). 점프가 있으면 점프일에 크게 움직이는 종목의 위험 기여가 커져 비중이 준다. 구현은 원문 예 1 · 예 2 의 표 값을 재현한다."),
  kr_mapping = paste0(
    "엔진이 고른 ≤25종의 비중만 정한다. 점프 국면 모수가 과모수라 점프를 시장 공통 한 요인으로 제한한다 — 받은 종목 균등가중 일별 수익에 ",
    "1차원 문턱 판정(|y| ≥ κσ · 정상 σ 는 점프 아닌 날로 다시 재며 고정점까지 · 부록 7.7 · 7.9) → 점프 강도 λ = 점프일 수/T · 점프 평균 · 분산은 ",
    "시장 계열에서 · 종목별 점프 진폭은 점프일 원점 회귀 계수. μ = 0(논문 §4.2 — ctx$mu 미사용). 점프일이 창에 없거나 추정 불가 · 존재 조건 실패 · ",
    "풀이 미수렴이면 가우시안 ES 위험 패리티로 내려가고 진단 줄(fallback=)에 남는다. 논문은 일별 추정을 문제 삼고 주간 · 월간을 선호했다 — ",
    "ctx 가 일별 창이라 일별로 쓴다. 상승 · 하락 점프를 같은 국면으로 센다(논문의 대칭 가정). ★점프 없는 창에서는 paper:ERCMRT2010 과 같은 해다",
    "(등록 검증 고정 자료는 점프 없는 정규 자료라 nearest_arm 이 근접으로 뜬다 — 중복이 아니라 논문 성질이고, 둘은 점프일이 있는 창에서만 갈린다)."),
  screen_axes = list(shrinkage_builtin = "no", statistic_order = "tail", screen_priority = "비중 카탈로그 등재(11-11 · 4분법 구성 규칙)"),
  selection_type = "chain",
  free_params = list(alpha = "0.99 — 논문 §3.3.1 · §4.2", kappa = "4.0 — 논문 부록 7.7 각주의 범위 3.5~4.0 의 상단 · 사전 고정(성과로 고르지 않음)",
                     v = "0 — 논문 §4.3 각주", budgets = "1/n"),
  routed_on = ROUTED("08_Tests/methods/test_skew_rp_bkr_2022.R"),
  root = ROOT, dry_run = !COMMIT)

## ── 2. 위상 위험 패리티(arXiv 2604.16773) ──────────────────────────────────────
r2 <- register_method(
  method_id = "TopoRPNKA2026", paper_id = "arxiv:2604.16773",
  paper_title = "Topological Risk Parity (Nayar · Kulkarni · Ainasse)",
  route = "optimizer", adapter_kind = "weight",
  adapter = "02_Infrastructure/methods/adapters/topological_rp_nayar_kulkarni_ainasse_2026.R",
  mechanism = paste0(
    "상관 거리 D = sqrt((1−C)/2) 의 최소 신장 나무를 만들고(§4.2), 뿌리에서 바깥으로 방향을 준 뒤 위상 인자 g_r = 1 · g_v = α_pa(v)·g_pa(v) · ",
    "α_u = (1−ρ) + ρ/b(u)(b = 자식 수 · §5.1 식 alpha · recursive-g)를 신호에 곱해 L1 정규화한다(w ∝ s·g). 내부 노드도 자산이라 자기 몫을 ",
    "그대로 갖고 자식에게는 α 배만 내려간다(HRP 의 이분할 역분산과 다른 비이진 나무 배분)."),
  kr_mapping = paste0(
    "변형 I(TRP-MST)만 구현 — 변형 II(SPY 뿌리 · 업종 ETF 층)는 ctx 에 지수 · 업종 계열이 없어 미구현. 롱온리 사상: 부호 신호 s ≡ +1(크기 1) → ",
    "w ∝ g(위상 인자만 남는다 · ctx$mu 미사용 · 논문의 시장 중립 · 헤지 성질은 작동하지 않는다 · 변동성도 쓰지 않는다 — 논문 Step 5). ",
    "ρ = 1: 논문은 수치를 주지 않는다 — ρ = 0 은 s ≡ 1 에서 정확히 균등이라 퇴화이고, 논문이 이름 붙인 비퇴화 극한이자 '위상 위험 패리티' ",
    "명칭을 허용한 값이 ρ = 1 이다(§6.1 · §12). 뿌리 = hub mode(최대 차수 · 동률은 이름순) — 다른 두 규칙은 s ≡ 1 에서 나무 기하와 무관해진다. ",
    "활동 필터 k = 창 전체 · ε = 0(논문 수치 없음). ★허브 집중: ρ = 1 에서 뿌리 비중 ≥ 1/(1 + 나무 최대 깊이) — 별 모양 나무면 한 종목 약 50%",
    "(비중 상한 없는 축이라 그대로 나간다). 나무는 상관 변화에 불연속이라 뿌리가 바뀌면 비중이 크게 바뀔 수 있다."),
  screen_axes = list(shrinkage_builtin = "no", statistic_order = "second", screen_priority = "비중 카탈로그 등재(11-11 · 4분법 구성 규칙) · 허브 집중 주의"),
  selection_type = "chain",
  free_params = list(rho = "1 — 논문이 이름 붙인 비퇴화 극한(§6.1 · §12) · 사전 고정", root_rule = "hub — §5.1 Step 2 의 세 규칙 중 하나",
                     tau = "1e-3 — 논문 §4.1", eps = "0", k = "T(창 전체)"),
  routed_on = ROUTED("08_Tests/methods/test_topological_rp_nka_2026.R"),
  root = ROOT, dry_run = !COMMIT)

## ── 3. 등방 상관 추정기(arXiv 2411.08864) — qepm:MVO 추정기 가족의 확장 형제 ────────
suppressWarnings(suppressMessages({
  .GV_QUIET_LOAD <- TRUE
  source(file.path(ROOT, "02_Infrastructure/methods/generate_weight_variants.R"))
}))
FAM <- "WVF_20260824011714_qepm_MVO_shrinkage_lift"          # 08-24 방출 가족(형제 5: sample · ledoit_wolf · lw_nls · gerber_rmt · OGK)
g <- generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = gv_recipe_ext("shrinkage_lift"),
                       extends_family = FAM, root = ROOT, dry_run = !COMMIT)
cat(sprintf("[isotropic] 가족 %s · 형제 수(누적) %d · 새 형제 %d · 표식 %s\n", g$ledger$trial_family_id, g$ledger$n_siblings,
            g$ledger$n_new, g$ledger$selection_type))

ok3 <- NA
if (COMMIT) {
  suppressWarnings(suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R"))))
  a3 <- admit_generated("02_Infrastructure/methods/adapters/gen/qepm_MVO__shr_isotropic.R", root = ROOT, resync = FALSE)
  ok3 <- isTRUE(a3$ok)
  cat("== 재색인 sync_catalog(probe = TRUE) ==\n")
  cg <- sync_catalog(root = ROOT, probe = TRUE, quiet = TRUE)
}
cat(sprintf("== 결과: SkewRPBKR2022 %s · TopoRPNKA2026 %s · isotropic %s ==\n",
            if (isTRUE(r1$ok)) "PASS" else "FAIL", if (isTRUE(r2$ok)) "PASS" else "FAIL",
            if (is.na(ok3)) "(건식)" else if (ok3) "ADMIT" else "REJECT"))
if (!isTRUE(r1$ok) || !isTRUE(r2$ok) || identical(ok3, FALSE)) quit(status = 1L)
