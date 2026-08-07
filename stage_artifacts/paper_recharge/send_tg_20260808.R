## AlphaSearch 큐 소비자 런 결과 텔레그램 보고
## TODAY=20260808, MAX_ALPHA=2
## 단일 진입점: tg_agent_brief(agent="AlphaSearch", ...)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "alpha-search 큐 가동 (팩터->모드) 20260808",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(
      emoji   = "📋",
      heading = "큐 처리 결과 (MAX_ALPHA=2)",
      type    = "bullet",
      items   = c(
        "Run 1/2 FQ-110B(저 jump-share long): ADOPT — 신호 진성 확인(IC +0.0278, OOS 1.27), Grade F(MDD 62.7% 구조낙폭). 자본 배포 아님.",
        "Run 2/2 2608.05755(IndustrySectorMomentum_LSTM): EV_D1_GATED — M18_IndustrMom DB 기등재+FAIL, KR long-only 이식 불가.",
        "오늘 누적: 신규 2건 처리 완료 / processed 총 14 paper_id"
      )
    ),
    list(
      emoji   = "🔬",
      heading = "Run 1 — FQ-110B Direction B",
      type    = "kv",
      kv      = list(
        "판정"        = "ADOPT (L1~L4 4/4 PASS — 신호 진성, 자본 배포 아님)",
        "IC"          = "+0.0278 / ICIR 0.248 / pos_rate 62.4%",
        "OOS"         = "retention 1.27 (IS SR 0.321 < OOS SR 0.406)",
        "AlphaTrend"  = "ratio 2.60x (최근 3Y SR 0.915, 개선 추세)",
        "MDD"         = "62.7% hard_fail (45%+ episodes 16 / Calmar 0.131)",
        "기전"        = "frog-in-the-pan REVERSE: 저 jump-share = 지속 모멘텀",
        "next_probe"  = "FQ-110C(cap-tier 분해) / FQ-153(시장 jump-share 오버레이)"
      )
    ),
    list(
      emoji   = "📦",
      heading = "Run 2 — 2608.05755 EV_D1_GATED",
      type    = "kv",
      kv      = list(
        "판정"     = "EV_D1_GATED (백테 미실행)",
        "근거"     = "M18_IndustrMom DB 기등재, DIST-QPM-027 standalone FAIL",
        "batch434" = "LSTM+섹터임베딩=S&P500 long-short 전용, KR 이식 불가",
        "탈출조건" = "dohoon_triage: KR LSTM 잔차가 M18 신호공간 이탈 시(cor<0.8)"
      )
    ),
    list(
      emoji   = "➡️",
      heading = "소비면 및 다음 탐색",
      type    = "bullet",
      items   = c(
        "FQ-110C: mega vs mid-cap 방향 B 분리 실측 (MDD 구조 분해) — 즉시 착수 가능",
        "FQ-153: 시장 jump-share 오버레이 probe (lane=overlay_probe, auto_regime 인프라 필요)",
        "FQ-149(FX_Intensity Grade C): post-2020 서브샘플/cap-tier 소비면 우선(메모리 등재)"
      )
    )
  )
)

cat("[send_tg_20260808] Done.\n")
