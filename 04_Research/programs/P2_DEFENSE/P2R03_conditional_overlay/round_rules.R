## P2R03 공용 규칙 상수 — register.R(초안 · 등록)과 rehearse.R 이 같은 정의를 쓴다(사전등록 final_selection_rule 의 원천 · 평가는 사전등록 사본만 읽는다)
##   숫자 출처: 등급 정본(constraint_defaults.json::tier_graduation · grade_v3.json) · 행동 카드 설정 사본(uc_floor · majority_share) ·
##   헌장 빈칸 1 · 4 · 7(도훈 확정 2026-10-16 · 10-17) · 문헌(빠른 급락 = Mishkin & White 2002) · P2R01 · P3R0x 승계(근거 문장 병기)
suppressPackageStartupMessages(library(jsonlite))
p2r03_final_selection_rule <- function(root, bcfg_path) {
  TD <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
  GV <- fromJSON(file.path(root, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
  BC <- fromJSON(bcfg_path, simplifyVector = FALSE)
  list(calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw, w_calmar = GV$weights$calmar, w_port_t = GV$weights$port_t,
       tie_eps = 0.02, tie_eps_role = "S 비열등 여유(P3R01 · P3R02 · P3R03 승계)",
       uc_floor = BC$uc_floor, uc_floor_source = "behavior_card_cfg_at_prereg.json uc_floor — 철학 '강세 참여 ≥ 55%' 절대 하한",
       majority_share = BC$majority_share, majority_share_source = paste0("behavior_card_cfg_at_prereg.json majority_share — ", BC$majority_share_source %||% ""),
       crisis_improve_min = 0.03, crisis_improve_min_evidence = "P2R01 R6 지속성 필터의 '기저 대비 0.03 이상 개선된 위기'(낙폭 포착 기준) 승계 · P3R03 동일 — 결과 전 고정",
       alpha_t_floor = -2, alpha_t_floor_evidence = "헌장 빈칸 4(C)(2026-10-16 도훈 확정) — 유의한 감소 없음(t > −2)",
       alpha_margin_frac = 0.2, alpha_margin_frac_evidence = "헌장 빈칸 4(C)(2026-10-16 도훈 확정) — 감소 ≤ 엔진 자체 보는 창 β-통제 알파의 20% · 엔진 알파 ≤ 0 이면 감소 허용 0",
       single_name_loss_floor = -0.10, single_name_loss_floor_evidence = "헌장 빈칸 1(2026-10-16 도훈 확정) — 깊은 위기 한 종목 기여 < −10% = 집중",
       bull_ratio = 0.8, bull_ratio_evidence = "헌장 빈칸 7(2026-10-17 도훈 확정 · CHARTER-GAPS-2) · 빈칸 4(B)의 80% — 강세 구간 과반에서 기준의 80% 이상",
       fast_window_days = 21L, fast_drop = -0.20,
       fast_evidence = "Mishkin & White (2002) U.S. Stock Market Crashes and Their Aftermath, NBER WP 8992 p.7 — 20% 하락 = 급락 · 속도 창 1일 · 5일 · 1개월 · 3개월 · 1년 중 1개월(≈ 21거래일)을 '빠름' 경계로(헌장 빈칸 6 — 사전 고정)")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
