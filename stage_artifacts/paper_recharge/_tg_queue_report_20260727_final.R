suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if (!dir.exists(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(title = "오늘 런 요약 (20260727)",
       body  = "처리 3건 | QUARANTINE 3건 | ADOPT 0건\nskip 1건(resid_info_vol, paper_id 중복)\n누적 done: 6건 (2607.19497 신규)"),

  list(title = "① spec_mass_lowfreq_60d — grade C ⚠️검증FAIL",
       body  = "논문: Sepp-Lucic 2026 (추세추종 시스템)\n팩터: 60거래일 periodogram 저주파(f<1/30) PSD 비율\n샤프 0.52 | 연복리 12.7% | MDD -61.4%\nOOS잔류율 0.26 < 0.50 → HARD FAIL"),

  list(title = "  spec_mass 검증 레이어",
       body  = "L1 PIT: ✅PASS\nL2 계약: ✅PASS\nL3 강건성: ❌FAIL (OOS 0.26, Calmar 0.21)\nL4 충실성: ✅PASS\nL5 게이트: ⚠️ QUARANTINE"),

  list(title = "  spec_mass 팩터분석",
       body  = "FF3 대비 알파: 4.28%/yr (t=1.47)\nCarhart 알파: 3.26%/yr (t=1.10)\nFama-MacBeth λ t=2.68 ★\n→ 팩터 통제 후 신호 잔존. MDD 구조가 한계."),

  list(title = "  spec_mass 기전 진단 & 다음 가설",
       body  = "post-2017 SR: 0.71→-0.55 (소진)\nbatch_434: 미해당(라벨=실행 일치)\n① OVERLAY_CANDIDATE (MDD overlay)\n② 저변동 subset 조건부 검증"),

  list(title = "② hill_tail_index — grade F ⚠️검증FAIL",
       body  = "논문: 2607.16450 (Taiwan ETF heavy tails)\nPORT_t 0.77 << 2.95 | IC≈0.0067\nFF3/FF5 α t < 1 → 신호 예측력 없음\n부활: 역방향(꼬리 얇은 종목) 또는 regime조건부"),

  list(title = "③ vol_adj_volume_surprise — grade F ⚠️검증FAIL",
       body  = "논문: 2606.08141 (SMAR volume-vol-ret)\nPORT_t -1.454 (음수) | OOS -0.58\n회전율 996%/yr → 비용 잠식\nD3 dead class 재확증. 이벤트조건부 재설계 가능"),

  list(title = "소비면 (spec_mass 신호력)",
       body  = "③ OVERLAY_CANDIDATE: ✅ 적합\n⑦ 타모드: regime FR 레이어 입력 후보\nFQ 신규 등재 권고: spec_mass overlay lane"),

  list(title = "용어 풀이",
       body  = "PORT_t: 포트 초과수익 t값 (2.95 이상=배포)\nOOS잔류율: 검증/학습 샤프 비율\nCalmar: 연복리/최대낙폭 (0.64 이상=배포)\nQUARANTINE: 자본 배포 불가, 부활조건 대기")
)

result <- tryCatch(
  tg_agent_brief(
    agent    = "AlphaSearch",
    title    = "alpha-search 큐 소비자 20260727 런 최종보고 (3건)",
    relaxed  = TRUE,
    force    = TRUE,
    sections = sections
  ),
  error = function(e) list(ok = FALSE, error = conditionMessage(e))
)

if (isTRUE(result$ok)) {
  cat("[TG] 텔레그램 발송 성공\n")
} else {
  cat("[TG] 발송 실패:", result$error %||% "unknown", "\n")
}
