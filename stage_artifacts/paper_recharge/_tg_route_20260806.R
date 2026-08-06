## Telegram 발송 — 논문 라우터 v2 (2026-08-06)
## 호출: Rscript -e 'source("stage_artifacts/paper_recharge/_tg_route_20260806.R")'

source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "논문 라우터 v2 | 리서치 소스 배분 + 팩터 마이닝 (2026-08-06)",
  relaxed  = TRUE,
  force    = TRUE,
  lock_scope = "paper_router_20260806",
  sections = list(

    # ── 1. 요약 (비전공자 1줄 결론) ─────────────────────────────────────────
    list(
      type    = "text",
      emoji   = "📰",
      heading = "오늘의 논문 배분 요약",
      body    = paste0(
        "arxiv 30편을 분석해 각 연구 모드에 배분했습니다. ",
        "주식 종목선별 신호로 쓸 수 있는 팩터 후보 1건(Markov 예측 변동성 순위)을 발굴했고, ",
        "지금 KR 백테스트를 실행 중입니다. ",
        "curated 기관 리서치 15건은 이미 처리 완료."
      )
    ),

    # ── 2. 쉬운 설명 ────────────────────────────────────────────────────────
    list(
      type    = "bullet",
      emoji   = "📖",
      heading = "쉬운 설명",
      items   = c(
        "시도: 오늘 새로 나온 arxiv 논문 30편을 읽고 '이건 종목선택 신호', '이건 포트폴리오 가중법', '이건 리스크 모델' 식으로 분류했습니다",
        "발굴: 변동성 순위가 다음 달에도 비슷하게 유지되는 경향(Markov 전이 확률)을 이용해 안정적인 저변동성 종목을 예측하는 팩터를 발견했습니다",
        "확인: KR KOSPI200∪KOSDAQ150 유니버스에서 2005~현재 월간 백테스트를 자동 실행 중입니다",
        "결과: 테스트가 끝나면 다중검정 t값(PORT_t ≥ 2.95 기준) 통과 여부를 별도 보고합니다"
      )
    ),

    # ── 3. 배분 결과 ────────────────────────────────────────────────────────
    list(
      type    = "bullet",
      emoji   = "🗂",
      heading = "route 배분 결과 (30편)",
      items   = c(
        "alpha (횡단면 종목선별): 2편 — Markov vol rank ★testable, QLoRA감성(null result)",
        "optimizer (포트폴리오 가중법): 3편 — MFCCA 다중프랙탈 리스크, 경로 서명 최적화, Conformal Kelly 사이징",
        "risk (공분산/꼬리위험 모델): 2편 — preference-robust 왜곡 리스크, 고유점수 변동성 필터",
        "regime (국면·오버레이): 1편 — 추세추종 스펙트럼(FQ-145 Grade F 기확인, FQ-146 오버레이 미측정)",
        "skip (범위 외): 22편 — 크립토/FX/HFT/파생/이론/거버넌스 등"
      )
    ),

    # ── 4. 팩터 마이닝 결과 ─────────────────────────────────────────────────
    list(
      type    = "bullet",
      emoji   = "🔍",
      heading = "팩터 추출 오버레이 (route 무관 발굴)",
      items   = c(
        "★ testable: Markov_PredVolRank — 월간 변동성 순위 Markov 전이로 다음 기간 저변동성 종목 예측",
        "  출처: 2607.27461 'Are Three Matrices All You Need?' (Halperin 2026) — OOS 샤프 1.32 실증",
        "  vs D01_IdioVol: D01=현재 변동성 수준, Markov=전이 패턴 포함 → vol 회귀/지속 구분 신규",
        "uncertain: Hurst 지수 횡단면(2608.04987 다중프랙탈) — 논문이 직접 검증 않음, FQ 등재 보류",
        "infeasible: LLM감성(KR데이터 미보유 + 논문 자체 FDR 전부 비유의)"
      )
    ),

    # ── 5. 오토런 상태 ──────────────────────────────────────────────────────
    list(
      type    = "bullet",
      emoji   = "⚙",
      heading = "alpha-search 오토런 (MAX_ALPHA=2 중 1건)",
      items   = c(
        "실행 중 ⏳: Markov_PredVolRank (2607.27461) — 5층 자동 검증 진행 중",
        "  팩터: trailing 21d 변동성 decile 순위 → 36개월 Markov P 추정 → 예측 decile Score = -E[next_rank]",
        "  기준: PORT_t ≥ 2.95 HARD, oos_retention ≥ 0.7 HARD",
        "  판정 완료 시 별도 텔레그램 발송 예정",
        "미사용 슬롯: 2번째 alpha-search 슬롯(MAX_ALPHA=2) — 추가 testable 후보 없음"
      )
    ),

    # ── 6. optimizer/risk/regime 큐 ─────────────────────────────────────────
    list(
      type    = "bullet",
      emoji   = "📋",
      heading = "mode_queue 등재 (모닝런 소비 대상)",
      items   = c(
        "[optimizer × 3] MFCCA 다중프랙탈 리스크함수 / 경로 서명 최적화 / Conformal Kelly → α̂ 고정 A/B 대상",
        "[risk × 2] preference-robust 왜곡 리스크 / 고유점수 변동성 필터 → Σ 고도화 수동 분석",
        "[regime × 1] 추세추종 스펙트럼(2607.19497) → FQ-146 오버레이 방향, 재디스패치 주의"
      )
    ),

    # ── 7. 인프라 메모 ──────────────────────────────────────────────────────
    list(
      type    = "text",
      emoji   = "💾",
      heading = "산출 파일",
      body    = paste0(
        "alpha_search_route_20260806.json (30편 배분) | ",
        "mode_queue_20260806.json (optimizer 3·risk 2·regime 1, 평면형태) | ",
        "curated_routed.json 갱신(신규 0건, 누적 15건)"
      )
    )
  )
)

cat("[router] 텔레그램 발송 완료\n")
