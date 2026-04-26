## STR_1702 Forge Brief — tg_agent_brief v4
source("02_Infrastructure/telegram/telegram_notify.R")

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260426_005")
OUT_DIR  <- file.path(WT_DIR, "backtest_result")

# ---- Performance comparison table ----
perf_df <- data.frame(
  Strategy   = c("Iter12 STR_1702", "Iter11 STR_1701", "Iter5 STR_1699",
                  "Iter6 STR_1700", "MEGA_05 PG2"),
  SR         = c("0.6448", "1.3638", "1.0052", "1.1000", "0.9345"),
  CAGR       = c("12.64%", "33.90%", "20.64%", "15.61%", "14.23%"),
  MDD        = c("-38.81%", "-40.77%", "-34.93%", "-22.98%", "-24.82%"),
  Harvey_t   = c("3.1598", "5.8510", "4.5661", "4.9075", "4.2626"),
  stringsAsFactors = FALSE
)

# ---- FF5 regression table ----
ff5_df <- data.frame(
  Spec     = c("CAPM", "Carhart_3", "Carhart_4", "FF5", "FF6"),
  Alpha_Ann = c("13.48%", "12.68%", "12.63%", "12.20%", "12.13%"),
  t_NW     = c("2.6248", "2.4582", "2.4164", "2.3632", "2.3335"),
  Pass_295 = c("❌", "❌", "❌", "❌", "❌"),
  R2       = c("0.0014", "0.0084", "0.0084", "0.0113", "0.0113"),
  stringsAsFactors = FALSE
)

# ---- Scenario table ----
scen_df <- data.frame(
  Scenario    = c("A: Iter12 100%", "AB: 80/20 blend", "B: 60/20/20 blend", "D: PG2 current"),
  SR          = c("0.6448", "0.8731", "1.1995", "0.9345"),
  CAGR        = c("12.64%", "14.79%", "19.27%", "14.23%"),
  MDD         = c("-38.81%", "-34.52%", "-28.84%", "-24.82%"),
  stringsAsFactors = FALSE
)

# ---- Regime table ----
regime_df <- data.frame(
  Regime  = c("BULL (n=69)", "NORMAL (n=116)", "CAUTION (n=23)", "CRISIS (n=5)"),
  CAGR    = c("17.54%", "5.52%", "14.88%", "N/A"),
  SR      = c("0.8679", "0.2940", "0.6590", "N/A"),
  MDD     = c("-17.77%", "-35.54%", "-15.25%", "N/A"),
  stringsAsFactors = FALSE
)

result <- tg_agent_brief(
  agent = "Forge",
  title = "STR_1702 Iter12 백테스트 완료 (LinTilt+Kelly+3Layer Quarterly)",
  as_of = "2026-04-26",
  sections = list(
    list(
      type    = "kv",
      heading = "핵심 실측 결과 (Pre-LB 2006-01 ~ 2023-12)",
      kv = list(
        "STR_1702 SR"       = "0.5893 (prelb 213M) | 0.6448 (243M full)",
        "STR_1702 CAGR"     = "11.59% (prelb) | 12.64% (243M)",
        "STR_1702 MDD"      = "-38.81% (prelb=pre-lockbox walk-forward)",
        "CVaR_d realized"   = "0.0243 < 0.025 cap — PASS (margin 6.8bps)",
        "Iter11 CVaR_d"     = "0.0259 — cap BREACH (Iter12 개선됨)",
        "Harvey t (FF5)"    = "0/5 specs pass t≥2.95 (alpha_ann~12%, t~2.4)",
        "DSR post-penalty"  = "1.4799 (raw 2.4799 − 1.00 penalty)",
        "Hash audit"        = "PASS (alpha/risk/opt 입력 불변 확인)",
        "OOS 2024-26 SR"    = "1.3461 (frozen weights, n=28M)",
        "OOS 2024-26 MDD"   = "-19.55%"
      )
    ),
    list(
      type    = "table",
      heading = "5전략 동일기간 비교 (2006-02 ~ 2026-04, N=240M)",
      df      = perf_df
    ),
    list(
      type    = "table",
      heading = "FF5 Harvey 검증 (threshold t≥2.95, 5/5 FAIL)",
      df      = ff5_df
    ),
    list(
      type    = "table",
      heading = "시나리오 비교 (A/AB/B/D)",
      df      = scen_df
    ),
    list(
      type    = "table",
      heading = "국면별 성과",
      df      = regime_df
    ),
    list(
      type  = "text",
      heading = "Iter11 vs Iter12 솔직한 평가",
      body  = paste0(
        "Iter11(STR_1701) SR=1.3638 vs Iter12(STR_1702) SR=0.6448 — Iter11이 SR 기준으로 명확히 우세함(+0.719).",
        " Iter12의 3-Layer 오버레이(DD Brake + VolReg + FM Cash)는 CVaR를 0.0259→0.0243으로 개선하고 cap 통과에 성공했으나,",
        " 과도한 cash drag(avg 21.8%, 89.7% dates cash>0)으로 CAGR 33.90%→12.64% 대폭 하락.",
        " Quarterly rebalance TO 4.72/yr(vs monthly 5.86)로 비용절감 확인.",
        " Harvey t 0/5 FAIL은 낮은 SR의 직접적 결과로 alpha는 존재하나 통계적으로 미약함.",
        " 결론: Iter12는 CVaR cap이 binding constraint인 경우에만 우선 선택 이유가 있음.",
        " 시나리오B(60/20/20) SR=1.1995가 현 PG2(0.9345)를 상회하는 유일한 개선 경로임."
      )
    ),
    list(
      type  = "bullet",
      heading = "다음 단계",
      items = c(
        "Judge S6 진입: forge_package.json → judge_ready/ 전달 완료",
        "Harvey t 0/5 FAIL → Judge에서 Grade 하향 판정 예상 (Grade B 또는 C)",
        "CVaR cap PASS — risk 제약 달성 유일 항목",
        "시나리오B 매력: STR_1702 60% + STR_1701 20% + STR_1699 20% → SR 1.1995",
        "Iter13 고려: VolReg target 10%(현 12%)로 강화 시 CVaR_d ~0.020 예상",
        "Codex Round 진행 중 (forge persona) — 완료 후 codex_critic_response_forge.json"
      )
    )
  ),
  charts = c(
    file.path(OUT_DIR, "equity_curve.png"),
    file.path(OUT_DIR, "annual_returns.png"),
    file.path(OUT_DIR, "oos_zoom.png"),
    file.path(OUT_DIR, "scenario_comparison.png")
  ),
  footer = "STR_1702 | Forge v6.1 | WT-D20260426_005 | walk_forward=TRUE | hash_audit=PASS"
)

cat("Telegram brief result:", result$ok, "\n")
