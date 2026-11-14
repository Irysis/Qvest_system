#!/usr/bin/env Rscript
## P4C01 블렌딩 사슬 1호 — 사슬 판 초안 생성(rc_p4_chain_new · 코어 v4 · p4_rules_v3). 설계 = ../DESIGN_draft.md
##   실행 조건(모두 — 하나라도 아니면 중단): ① RELEASES v4 · 등급 v3.5 핀(317a9c0e0) ② P1S03 상설 판 T0 엔진 통과 + v4 관문(기저 풀 eligible)
##   ③ 원천 라운드 P1R03 · P1R04 칸 산출이 현재 판 표식 뒤(코어 v4 가 원천 시행을 등록 때 다시 본다 — 여기서는 기저 선택만)
##   ④ 이 폴더에 chain_spec.json 이 없다(덮어쓰지 않는다).
##   기저 규칙(기계 · 등록 전 고정 · 보는 창만 — 판단 T4 C-20261113-040 · DESIGN_draft §2): 후보 = 기저 풀 eligible 행 가운데 P1R03 동일가중(T0) 엔진
##     (04_Research/strategies/FC_FAM_<카테고리>/engine.R · FC_TOTAL_EW/engine.R — family_root FC:<카테고리> | FC:total · origin own_spec).
##     선택 = rc_p4_gap(그 행 산출)의 S_vis 최대 · 동률(차 < 1e-12)이면 port_t_vis 큰 쪽 · 그다음 key 사전순. Q 는 고르지 않는다.
##   산출: chain_spec.json · base_cell_spec.json · pool_snapshot.json(코어) + base_selection.json(후보 · 보는 창 S · PORT_t · 고른 규칙 — 이 스크립트).
##   그다음: 철학 P1 + 판단 T1(동시) → round.sh <사슬> p4-check → p4-register --p1 <id> --t1 <id> → p4-base-measure.
## 실행(저장소 루트): Rscript 04_Research/programs/P4_ASSEMBLY/P4C01_fc_blend/tools/init_p4c01.R [--dry-run]
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
stopifnot(identical(RC_VERSION, "v4"), identical(RC_P4_RULES_VERSION, "p4_rules_v3"))
root <- rc_root(); dry <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)
cd <- "04_Research/programs/P4_ASSEMBLY/P4C01_fc_blend"
if (file.exists(file.path(root, cd, "chain_spec.json"))) stop("[init_p4c01] chain_spec.json 이 이미 있다 — 덮어쓰지 않는다")
rel <- jsonlite::fromJSON(file.path(root, "04_Research/programs/_lib/round_core/RELEASES.json"), simplifyVector = FALSE)
if (!("v4" %in% vapply(rel$releases, function(r) as.character(r$version), ""))) stop("[init_p4c01] RELEASES 에 v4 출시 항목 없음")

pool <- data.table::as.data.table(rc_p4_base_pool(root))
t0rx <- "^04_Research/strategies/FC_(FAM_[a-z_]+|TOTAL_EW)/engine\\.R$"
## 11-15 수리: P1S03 시드(FC_FAM_value — P1R03 T0 밸류와 같은 엔진)는 기저 풀 행 origin 이 "seed" 다. DESIGN_draft §2 의 "origin own_spec" 은 T0 엔진을 가리키는 말이었고
##   (§3 부품 목록에 밸류 포함) 시드를 빼려는 뜻이 아니었다 — 경로 규칙(FC T0 엔진) ∧ origin ∈ {own_spec, seed}. 수리 전 dry-run 이 시드를 뺀 후보 7 의 보는 창 S 를 보였다(노출 · DESIGN_draft §2).
## 11-15 판단 C-20261115-050: 판별자 = own_spec_engine 열(origin 대신 — 시드 · 스캔 항목 모두 TRUE)
cand <- pool[eligible %in% TRUE & grepl(t0rx, engine_path) & !grepl("_ICW/", engine_path) & own_spec_engine %in% TRUE]
cat(sprintf("[init_p4c01] 기저 풀 %d 행 · eligible %d · T0 후보 %d\n", nrow(pool), sum(pool$eligible %in% TRUE), nrow(cand)))
if (!nrow(cand)) stop("[init_p4c01] T0 후보 0 — P1S03 통과 · v4 관문(철학 P2 · 저위험 풀림) 뒤에 다시")
g <- data.table::rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  r <- cand[i]; x <- rc_p4_gap(r$artifacts, root)
  data.table::data.table(pool_key = r$key, engine_path = r$engine_path, family_root = r$family_root, label_class = r$label_class,
                         S_vis = x$metrics$S_vis, port_t_vis = x$metrics$port_t_vis, calmar_vis = x$metrics$calmar_vis, window_end = x$window[2])
}))
data.table::setorder(g, -S_vis, -port_t_vis, pool_key)   # 열 이름 key 는 data.table() 의 key 인자와 겹친다(11-15 수리)
if (nrow(g) > 1L && abs(g$S_vis[1] - g$S_vis[2]) < 1e-12 && abs(g$port_t_vis[1] - g$port_t_vis[2]) < 1e-12) cat("[init_p4c01] S · PORT_t 모두 동률 — key 사전순으로 고른다\n")
base_key <- g$pool_key[1]
cat(sprintf("[init_p4c01] 기저 = %s(%s · %s) — 보는 창 S 최대(후보 %d)\n", base_key, basename(dirname(g$engine_path[1])), g$label_class[1], nrow(g)))

RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps",
       source = "P3R03 최종 선택 규칙 tie_eps 승계(파일럿 P4C90 와 같은 규칙 — 잡음 수준 개선은 채택하지 않는다)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor", source = "헌장 §2 강세 참여 ≥ 55%"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0,
       basis = "정의 — 비악화 = 부모 이하", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">",
       value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장 §5 빈칸 4 · 7 · 24 · 도훈 CHARTER-GAP-BULL-PARTICIPATION-UNIT(현행 유지)"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">",
       value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장 §5 빈칸 2 · 23"),
  list(id = "beta_asym", type = "threshold", label = "β 비대칭(N5 — β 로 산 방어 아님)", metric = "beta_asym_ok_vis", op = ">=", value = 1,
       basis = "정의 — N5 통과 = 1", source = paste0(RC_P4_BETA_ASYM_SOURCE, " · p4_rules_v3 필수(blend · 노출 층 걸음)")),
  ## 11-15 철학 P1 C-20261115-038(첫 사슬 판 조건 C-20261111-077) — N4 집중: 깊은 위기 한 종목 최악 기여가 문턱보다 나쁘면 채택 안 함 · 미측정 = 미시험
  list(id = "concentration", type = "threshold", label = "집중(N4 — 깊은 위기 한 종목 기여)", metric = "worst_name_contrib_deep_vis", op = ">=",
       value_ref = "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json::final_selection_rule.single_name_loss_floor",
       source = "헌장 §5 빈칸 1(집중) · 철학 C-002(P2R03 집중 손실 문턱 승계) · 첫 사슬 판 조건 C-20261111-077 · 철학 C-20261115-038"))
BUD <- list(max_steps = 20L,
            max_steps_source = paste0("programs/trial_budget.R(rc 0.8 — K 50 → 요구 t 2.52 · K 100 → 2.62) · 시행 집합 = 원천 45(P1R03 15 + P1R04 30 — 코어 v4 원천 시행 · 갈음 뒤 고유 경로 30 · 보수 쪽 — 판단 C-20261115-047) + 기저 1 + 걸음 ≤ 20 ≈ 66 → 요구 t ≈ 2.55 · ",
                                      "걸음을 늘려도 요구 t 증가가 완만해 시행이 아니라 생성 비용 · 시간이 상한을 정한다(DESIGN_draft §5)"),
            noise_k = 2L, noise_k_source = "체계 §4 R7(연속 2 걸음 '잡음 이내'면 닫기) · P2 R7 선례 · 파일럿 P4C90 와 같다")
purpose <- paste0(
  "블렌딩 사슬 1호: 서로 다른 수익 원천의 P1 자격 엔진(자체 사양 동일가중 카테고리 엔진 — 밸류 · 성장 · 컨센서스 · 저β 묶음)을 한 포트폴리오로 섞으면 ",
  "보는 창 종합점수 S(Calmar 6 : PORT_t 4)와 강세 참여 · 위기 하락노출이 단일 기저보다 나아지는가. ",
  "가설: 원천이 다른 엔진의 초과수익은 상관이 낮아, 결합하면 같은 β 에서 선택 알파의 t 가 오르고 원천별 낙폭 시점이 어긋나 낙폭이 얕아진다. ",
  "반증: 채택 걸음 0(모든 blend 가 채택 규칙 미달) · 또는 채택 걸음이 저β 상대를 섞어 β 만 낮춘 경우(N5 β 비대칭 · same_lineage_blend 표식)뿐. ",
  "걸음 = 가설 하나 · 블록 하나 · 칸 하나 — blend 블록(기저 + 부품 1개 추가)부터 설계한다. ",
  "부품 = 같은 기저 풀의 P1R03 동일가중(T0) 자격 엔진(P1S03 통과 · v4 관문 통과분). T1(정보계수 가중) 엔진은 부품이 아니다(사슬 2호부터 — P1R04 결론 범위 · 판단 C-20261113-004). ",
  "저β 엔진(방어 · 위험 · 유동성 · 쏠림 · 토탈)은 '저β 수익 엔진' 표기 · 방어 주장 없음(도훈 LOWBETA-ENGINES-BASE-USE-20261113 · CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113). ",
  "같은 계보(토탈 ⊃ 카테고리 · 같은 카테고리) 블렌드 = 꼬리표 same_lineage_blend(거부 아님 · 닫기 결론에 '한 원천의 결합 가중'). ",
  "기저 = 기저 풀 T0 후보 가운데 보는 창 S 최대(기계 규칙 · base_selection.json). 닫기 = 마지막 채택 걸음 · 원천 시행 포함 선택 현실 점검 재채점(등급 v3.5 · --regrade-write). ",
  "걸음 = blend 블록만 — 비중 · 구성 · 유니버스 걸음은 이 사슬에서 열지 않는다(N5 β 비대칭 규칙이 그 걸음을 보지 않는다 · 철학 C-20261115-038). ",
  "부품 = 동일가중(T0) 엔진만 — IC 가중(_ICW) 엔진은 기저 풀에 eligible 로 있어도 부품으로 쓰지 않는다(기계 차단 없음 · 생성기가 지킨다 · 판단 C-20261115-048). ",
  "순서: 이 사슬이 열려 있는 동안 FC 엔진 재생성(방향 수정 · 생성기 개정)을 하지 않는다 — 사슬은 걸음 칸과 기준 칸의 엔진 md5 를 대조하지 않는다(판단 C-20261115-033 · 방향 수정은 닫기 뒤 새 엔진). ",
  "닫기 판독(사전 고정 · 채택 규칙 밖): ① 알파 비악화 = 최종 후보 대 기저 rc_pair_alpha 보는 창 t > −tier_graduation.grade_b_min_portfolio_alpha_t ∧ 연 알파 감소 ≤ 1 − RC_P4_UC_SEG_KEEP(헌장 §5 빈칸 4 — 같은 엔진 기준의 80% 보존) — 어기면 결론 '알파 악화'(채택 규칙에 알파 차 지표가 없는 알려진 한계 · 판단 C-20261115-032 · 엄격안 = p4_rules_v4) ",
  "② 시장 대비 위기 결론 = 깊은 위기 과반 비악화 + 빠른 급락 각각(중앙값은 기록 · 철학 C-20261115-037) ③ 최종 후보 귀속 = 시가총액 × β 짝 라벨 · 기저 대비 Δβ · 시드 띠 해당 없음(결정론 엔진) — 'β 만 낮춤' 반증 가지 판독(철학 C-20261115-036) ",
  "④ 잡음 2 연속 닫기로 안 잰 부품은 '미시험'으로 적고 기각으로 읽지 않는다(판단 C-20261115-045) ⑤ 희소 구성원 쏠림 대조 = 미측정(사이드카 없음 · 철학 C-20261115-016).")

sel <- list(schema = "p4c01_base_selection_v1", at = rc_now(), audience = "보는 창(τ_D 이전)만 · 등급 계약 gv3_S(rc_p4_gap) · 시험 창 값 없음",
            rule = "후보 = 기저 풀 eligible ∧ P1R03 T0 엔진(FC_FAM_<카테고리> · FC_TOTAL_EW · origin own_spec | seed — P1S03 시드 = T0 밸류) · 선택 = S_vis 최대 → port_t_vis → key",
            pool_md5 = rc_p4_pool_md5(pool), candidates = g, base_key = base_key)
lk <- rc_after_tau_leaks(sel[setdiff(names(sel), "at")], as.Date(rc_ref_value("06_Registry/behavior_card.json::tau_d", root)))
if (length(lk)) stop("[init_p4c01] 기저 선택 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
if (dry) { print(g[, .(pool_key, engine = basename(dirname(engine_path)), label_class, S_vis, port_t_vis)]); cat("[init_p4c01] --dry-run — 쓰지 않았다\n"); quit(status = 0) }
sp <- rc_p4_chain_new(file.path(root, cd), "P4C01_fc_blend", base_key, pool, adoption_rules = RULES, budget = BUD, purpose = purpose, root = root)
rc_json_write(sel, file.path(root, cd, "base_selection.json"))
cat(sprintf("[init_p4c01] 사슬 판 %s · md5 %s · 기저 %s · 규칙 %d(%s) · 예산 걸음 %d · 잡음 %d\n", rc_rel(sp, root), rc_md5(sp), base_key, length(RULES),
            RC_P4_RULES_VERSION, BUD$max_steps, BUD$noise_k))
