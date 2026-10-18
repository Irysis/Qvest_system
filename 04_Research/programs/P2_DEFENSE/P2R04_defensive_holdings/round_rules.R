## P2R04 공용 규칙 상수 — register.R(초안 · 등록)과 rehearse.R · evaluate_fixture.R 이 같은 정의를 쓴다(사전등록 final_selection_rule 의 원천 ·
##   평가는 사전등록 사본만 읽는다 — evaluate.R 은 이 파일을 읽지 않는다).
##   P2R03 round_rules.R 의 키 · 값 · 근거 문장을 그대로 잇고(DESIGN §10 '같은 이름 · 같은 값') 두 키를 더한다:
##     mc8_label_required             — ⑭ 선택 귀속(MC8 귀속 라벨 enum · matched_controls.R mc_attribution)
##     state_unturned_max_drop_crises — 기록용 '상태 미전환 최대 하락 위기'(판정 아님 · 철학 P1 C-019 이름 — 구 from_top_crises) ·
##                                      _design_notes/state_turn_classify.md 의 해당 줄을 그대로 읽는다(손으로 옮겨 적지 않는다)
##   숫자 출처: 등급 정본(constraint_defaults.json::tier_graduation · grade_v3.json) · 행동 카드 설정 사본(uc_floor · majority_share) ·
##   헌장 빈칸 1 · 4 · 7(도훈 확정 2026-10-16 · 10-17) · 문헌(빠른 급락 = Mishkin & White 2002) · P2R01 · P3R0x 승계(근거 문장 병기)
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 기록용 위기 목록의 원천(설계 입력 · 벤치만 · τ_D 까지 · 성과 무관) — 줄 머리말이 바뀌면 멈춘다(fail-closed)
P2R04_STATE_TURN_NOTE <- "04_Research/programs/P2_DEFENSE/_design_notes/state_turn_classify.md"
P2R04_STATE_TURN_PREFIX <- "- 판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기(빠른 · 느린 모두): "

## state_turn_classify.md 의 '판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기' 줄 → 위기 키('고점 저점' · evaluate.R .p2_key 와 같은 형식)
p2r04_state_unturned_crises <- function(root, note = P2R04_STATE_TURN_NOTE) {
  p <- file.path(root, note)
  if (!file.exists(p)) stop("[P2R04 규칙] 설계 입력 없음: ", note)
  L <- sub("\r$", "", readLines(p, warn = FALSE, encoding = "UTF-8"))
  s <- L[startsWith(L, P2R04_STATE_TURN_PREFIX)]
  if (length(s) != 1L) stop(sprintf("[P2R04 규칙] %s 에 '판정 창 … 상태 전환 전에 온 위기' 줄이 %d개(1개여야 함)", note, length(s)))
  v <- trimws(strsplit(substring(s, nchar(P2R04_STATE_TURN_PREFIX) + 1L), " · ", fixed = TRUE)[[1]])
  rx <- "^([0-9]{4}-[0-9]{2}-[0-9]{2}) → ([0-9]{4}-[0-9]{2}-[0-9]{2})$"
  if (!length(v) || !all(grepl(rx, v))) stop("[P2R04 규칙] 위기 표기 해석 실패(고점 → 저점): ", paste(v, collapse = " | "))
  list(keys = sub(rx, "\\1 \\2", v), md5 = unname(as.character(tools::md5sum(p))))
}

p2r04_final_selection_rule <- function(root, bcfg_path) {
  TD <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
  GV <- fromJSON(file.path(root, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
  BC <- fromJSON(bcfg_path, simplifyVector = FALSE)
  SU <- p2r04_state_unturned_crises(root)
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
       fast_evidence = "Mishkin & White (2002) U.S. Stock Market Crashes and Their Aftermath, NBER WP 8992 p.7 — 20% 하락 = 급락 · 속도 창 1일 · 5일 · 1개월 · 3개월 · 1년 중 1개월(≈ 21거래일)을 '빠름' 경계로(헌장 빈칸 6 — 사전 고정)",
       mc8_label_required = "selection_defense",
       mc8_label_required_evidence = paste0("DESIGN §5 ⑭ · §8.2 — 변형 칸 보는 창 패킷의 MC8 귀속 라벨(controls.attribution.label · matched_controls.R mc_attribution ",
                                            "nested_majority_placebo_v2)이 selection_defense = 크기 · 평균 노출 짝 플라시보를 위기 과반에서 넘음. size_defense · exposure_defense · ",
                                            "no_defense · insufficient · 라벨 없음 = 통과 불가(라벨 그대로 기록) — 방어 틸트는 대형주 쪽으로 기울 수 있어 크기 방어를 선택 방어로 세지 않는다(§4)"),
       state_unturned_max_drop_crises = SU$keys,
       state_unturned_max_drop_crises_evidence = sprintf(paste0("기록용 '상태 미전환 최대 하락 위기'(판정 아님 · DESIGN §5 기록 · 철학 P1 C-019 이름 — 구 '꼭대기 시작 손실 위기') — ",
                                                                "%s(벤치만 · τ_D 까지 · 전략 성과 무관 · md5 %s)의 '판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기' 줄을 그대로 읽음",
                                                                "(최대 21거래일 하락 구간 직전 월말에 r252 ≥ 0 ∧ 낙폭 ≤ 확장창 중앙값). 깊은 위기로는 1건뿐이라 판정 조건으로 두지 않는다",
                                                                "(원칙 2 — 한 위기로 통과를 정하지 않는다)"), P2R04_STATE_TURN_NOTE, SU$md5))
}
