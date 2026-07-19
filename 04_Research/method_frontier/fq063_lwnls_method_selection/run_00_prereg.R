# =============================================================================
# FQ-063 run_00: 사전등록 — lw_nls 기반 "비중결정 방법 선택"이 유의한가.
#   NP4는 고정 MVO에 Σ만 swap(linear LW->lw_nls)해 paired NULL이었다. 그건 MVO 한
#   방법만 실측했고, "⑤비중 층 소진·estimator-무관"은 나머지 방법(HRP/ERC/MaxDiv/GMV/
#   CVaR)에 대해선 외삽이었다. 본 라운드는 그 외삽을 canonical PORT_t 측정으로 settle.
#   도훈 질문: "옵티마이저가 lw_nls 기반으로 비중결정 *모델*을 고르면 유의한 것 아닌가."
# 설계: 2 모드 joint 스윕(최선 vs 기준선).
#   Mode A (비중 방법 스윕, 고정 top-25 선택): {EW, LinearTilt, MVO, HRP, ERC, MaxDiv,
#     GMV, CVaR-LP} — 각 25x25 Σ=lw_nls(p<n라 sample과 tie 예상, NP4 MVO-only 완성 축).
#   Mode B (★핵심, 대형 유니버스 p>n 위험선택+비중): {GMV/min-var, MaxDiv, HRP}가 Σ 구조로
#     25종 선택+비중. Σ 3-A/B (sample / linear LW=μI 퇴화 / lw_nls=퇴화교정). 알파-무관
#     순수위험 + 알파-결합(위험선택×LinearTilt) 양쪽. NP4 미측정 셀 = lw_nls 퇴화교정이
#     물릴 유일 영역.
# 판정: 1급 = canonical PORT_t(cap-w authoritative) + oos_retention + calmar. best-of-sweep
#   가 EW/LinearTilt 기준선 PORT_t를 paired NW-t(lag3)로 유의 초과하는가. sweep형 selection
#   -> DSR>=0.5 HARD 적용 + method_shopping_log 전수. dual-basis(cap-w vs EW-uni + cap-tier).
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
PRE_PATH <- file.path(OUT_DIR, "fq063_preregistration.json")

if (file.exists(PRE_PATH)) {
  cat("[prereg] 이미 존재 — 불변성 유지, overwrite 거부:", PRE_PATH, "\n")
  quit(save = "no", status = 0)
}

prereg <- list(
  id = "FQ-063",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "optimizer-research",
  registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  pin_tag = "fq057_20260718_171024",
  pin_note = paste0("FQ-057/NP4/P1c vintage 상속(read_pinned, daily_refresh 활성 — measurement-graduation §7). ",
    "월간수익/스냅샷/liq/일간/score 입력 전부 pinned 재사용(재빌드 없음)."),
  metric_type = "optimizer_lane_ab_diagnostic",
  selection_objective = "net_ir (paired canonical PORT_t, NW lag3) — sweep형 argmax",
  capital_claim = FALSE, graduation_claim = FALSE,

  hypothesis = paste0(
    "production STR_1715 score_eff(§7b production-parity) 알파 위에서, 비중결정 방법을 lw_nls 기반으로 ",
    "고르면(Mode A 8-방법 스윕 / Mode B 대형-유니버스 위험선택 3-방법 × Σ 3-A/B) best-of-sweep 의 ",
    "canonical PORT_t(cap-w authoritative)가 EW/LinearTilt 기준선을 paired NW-t(lag3)로 유의 초과하는가."),

  alpha_base = list(
    signal = "STR_1715 score_eff (alpha_scores_str1715_268m_cleanT1.parquet, production_parity_verified spearman 0.975~0.997)",
    section7b = "production 코드 파생 신호만 소비(저장 파생 패널 직접 재사용 아님, parity 라벨 후 소비, 05_Production 무수정)",
    note = "NP4는 12-1 모멘텀(OOS-dead) 사용 — 본 라운드는 live-grade production 알파로 격상(더 결정적)"),

  modes = list(
    A = list(
      role = "완결성 축 (NP4 MVO-only -> 전방법)",
      selection = "score_eff top-25 among elig (고정)",
      weighting_sweep = c("EW","LinearTilt(prod λ=1.5, incumbent)","MVO(λ=2.0,psi=0.3)",
                          "GMV/min-var","HRP","ERC","MaxDiv","CVaR-LP(β=0.95, lpSolve RU)"),
      sigma = "lw_nls on 25x25 (60m). p(25)<n(60) -> lw_nls≈sample 예상(P1c 정합). sample도 병기 산출(tie 진단).",
      baselines = c("EW-top25","LinearTilt-top25(incumbent recipe)"),
      prior = "tie 예상 — LinearTilt(알파비례)가 single-cluster book서 위험기반 희석 지배(HRP frontier 07-03). EW=sizing 천장."),
    B = list(
      role = "★핵심 — lw_nls 퇴화교정이 물릴 유일 영역 (NP4 미측정)",
      universe = "full elig (p≈280~320 > n=60)",
      risk_methods = c("GMV/min-var","MaxDiv","HRP"),
      sigma_ab = c("sample(p>n 특이 -> ridge 정규화, flag)","ledoit_wolf(linear LW, p>n μI 퇴화 cond≈1)","lw_nls(full-rank PSD)"),
      variants = c("pure_risk(알파-무관 위험선택 25종)","alpha_combined(위험선택 25종 × LinearTilt score_eff)"),
      cardinality = "위험방법 full-universe 해 -> top-25 by weight 선택 -> 재정규화/재해(GMV·MaxDiv 서브셋 재해, HRP top25 renorm)",
      prior = paste0("미달 예상 — 위험선택은 알파선택 대체(직교≠수익 + min-var-settled 벽). lw_nls는 GMV를 well-conditioned로 ",
        "만들어 실제 min-var 포트 생성(linear LW는 μI->EW 붕괴)하나 그 포트는 저변동/방어틸트로 알파 edge 부재 예상. ",
        "-> lw_nls '작동'하나 PORT_t는 기준선 미달 예상. 단 측정으로 판정.")),

  hard_constraints = "max_names<=25 / long-only / weight [0,0.20] / Σw=1 / LIQ 2e8 t-1 / 15bps one-way delta / PIT C1~C15. 위반 시 stopifnot 감사 + infeasibility_report.",
  cost_model = "15bps one-way delta (BOP_m vs EOP_{m-1}); round-trip = x2. 캘린더 연 실합산(x12 금지). TO 상한 11.0/yr 준수 확인, 초과 시 disqualify.",
  benchmark = "PRIMARY: cap-w K200|KQ150 fresh (Size, Return.portfolio). dual-basis: EW-uni(elig 균등) 병기 + cap-tier(MEGA<=30/MID 31-150/SMALL>150) holdings 분해.",
  portfolio_construction = "PerformanceAnalytics::Return.portfolio(verbose=TRUE) only (자체합성 금지). 월말 t 비중 -> 월 t+1 적용.",

  measurement = list(
    primary = "canonical PORT_t = NW lag-3 t of net active(port_net - cap-w bench), full-range",
    graduation_gates = "PORT_t>=2.95(HARD) / oos_retention_v2 중앙값>=0.7(HARD) / calmar>=0.64(HARD) — 자본 판정용(본 라운드 capital_claim=FALSE, 게이트값은 기록)",
    paired = "best-of-sweep vs baseline: paired NW-t(lag3) on active_best - active_baseline",
    dsr = "sweep형 selection -> DSR(Bailey-LdP, n_trials=전 스윕 셀 수) >=0.5 HARD 적용"),

  decision_rules = list(
    exceed = "best-of-sweep canonical PORT_t 가 max(EW,LinearTilt) 기준선을 paired NW-t(lag3) t>=2.0 로 유의 초과 ∧ DSR>=0.5 -> capability_established(모드·Σ·방법 명시)",
    not_exceed = "미충족 -> config_scoped_negative: '⑤비중 층은 lw_nls 대형-Σ로도 미달'을 MVO-only(NP4)->전방법 실측 확정(NP4 강화)",
    screen_route = "위험선택 특정 셀이 신호력(screening) 있으나 자본 미달이면 screen_route 라벨"),

  R_discipline = ".R 파일 경유·setDTthreads(1)·arrow temp-rename·RAM 80%·Return.portfolio only·05_Production read-only·.get_cor_cov 3종 경유(자체 공분산 합성 금지)·quadprog/lpSolve 표준 solver",
  self_adversarial = "finalize 직전 약점 >=3(p<n 모드A lw_nls≈sample 자명성 / 위험선택의 알파포기 / DSR 다중검정 / production parity / min_names·box 제약 봉투 지배) -> challenge_note. AX-008 3-source 중 1."
)

write_json(prereg, PRE_PATH, auto_unbox = TRUE, pretty = TRUE)
cat("[prereg] 기록 완료(불변):", PRE_PATH, "\n")
