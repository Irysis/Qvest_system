source("02_Infrastructure/telegram/telegram_notify.R")

spec_mass_dir <- "stage_artifacts/alpha_search/20260727_202754_49064"
chart_eq  <- file.path(spec_mass_dir, "equity_curve.png")
chart_ann <- file.path(spec_mass_dir, "annual_returns.png")
charts <- c(chart_eq, chart_ann)[file.exists(c(chart_eq, chart_ann))]

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "리서치 소스 배분 + 팩터 마이닝 (20260727)",
  relaxed = TRUE,
  force   = TRUE,
  lock_scope = "paper_router_20260727",
  charts  = if (length(charts) > 0) charts else NULL,
  sections = list(
    list(
      emoji   = "📊",
      heading = "소스 배분 결과 (28편)",
      body    = paste(
        "alpha 3편 · optimizer 7편 · risk 4편 · regime 3편 · skip 11편",
        "curated 신규처리: 0건 (15건 전량 기처리)",
        "팩터후보 testable 2건 / uncertain 2건",
        sep = "\n"
      )
    ),
    list(
      emoji   = "🔬",
      heading = "팩터 추출 오버레이 — testable 2건",
      body    = paste(
        "[1] resid_info_vol (2606.08141) — 변동성 조건부 잔차 볼륨, DB신규",
        "[2] spec_mass_lowfreq (2607.19497) — 60일 저주파 PSD 비율, DB신규",
        "uncertain: DART감성(NLP인프라↑) · 뉴스FinBERT(뉴스피드 미구축)",
        sep = "\n"
      )
    ),
    list(
      emoji   = "📈",
      heading = "AUTORUN #1 — spec_mass_lowfreq_60d",
      body    = paste(
        "저주파 스펙트럼 질량: '긴 파동 많은 종목=추세 잘 이어짐' 가설",
        "CAGR 12.7% | SR 0.517 | MDD -61.4% | PORT_t<2.95",
        "Grade C FAIL | L-code L-AS-20260727_202754_49064 적립",
        "긍정: FMB λ t=2.68(횡단면 유의) · 위기 3/3 초과수익",
        sep = "\n"
      )
    ),
    list(
      emoji   = "🔎",
      heading = "spec_mass — 실패기전·next_probe",
      body    = paste(
        "실패기전: post-2017 알파 소진 + MDD 위기동반급락(하락추세도 지속)",
        "[P1] overlay 소비: 추세지속성 신호 → PG2 오버레이 입력 경로",
        "[P2] 저변동성 결합: D03_Vol_20d 필터 시 MDD 축소·신호력 유지 검증",
        sep = "\n"
      )
    ),
    list(
      emoji   = "⏳",
      heading = "AUTORUN #2 — resid_info_vol 백테 진행중",
      body    = paste(
        "논문: Bucci, Palomba, Rossi (2026) arXiv:2606.08141",
        "팩터: 변동성 조건부 잔차 볼륨 (정보 거래 활동 지시자)",
        "상태: 팩터엔진 구현 완료 → canonical_screen_bt 실행 중",
        "결과: 완료 시 별도 텔레그램 발송",
        sep = "\n"
      )
    ),
    list(
      emoji   = "📋",
      heading = "optimizer 큐 7편 (dispatch 소비 예정)",
      body    = paste(
        "TDA군집 포트구성(2607.21170) · MVN강건결정(2607.18813)",
        "AlphaZeroBeta DRL(2607.18001) · SciPhyRL HJB(2607.15195)",
        "모호성MVO+베이지안(2606.11318) · BAVAR-BLED(2606.09104)",
        "분수위확률지배(2607.15317) — 전건 α̂고정 A/B 대상",
        sep = "\n"
      )
    ),
    list(
      emoji   = "⚠️",
      heading = "risk 큐 4편",
      body    = paste(
        "OT모델위험(2607.20343) · GJR-GARCH꼬리(2607.16450)",
        "AGCA극단의존(2607.13112) · LLM-Bayes위험(2606.15473)",
        sep = "\n"
      )
    ),
    list(
      emoji   = "🌀",
      heading = "regime 큐 3편",
      body    = paste(
        "★스펙트럼추세이론(2607.19497) — spec_mass overlay 소비후보",
        "Observable Matrix 위기탐지(2607.19005)",
        "현금오버레이 VKOSPI/ECOS KR버전 가능(2606.09025)",
        sep = "\n"
      )
    ),
    list(
      emoji   = "📚",
      heading = "음성지식: 학술팩터 대형주 무용",
      body    = paste(
        "Chen & Welch (2026) 2607.06502: ~200 이상현상",
        "post-2005 비-마이크로캡 → 7bp/월 (비용 후 소멸)",
        "우리 16/16 단독팩터 FAIL과 정확히 부합",
        "→ 비-return 원천(DART insider 등) 집중 mandate 재확인",
        sep = "\n"
      )
    )
  )
)

cat("\n[router_tg] 텔레그램 발송 완료\n")
