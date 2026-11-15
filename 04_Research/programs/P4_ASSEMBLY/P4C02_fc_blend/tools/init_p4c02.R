#!/usr/bin/env Rscript
## P4C02 블렌딩 사슬 1호 판 2 — 사슬 판 초안 생성(rc_p4_chain_new · 코어 v5 · p4_rules_v3). 설계 = ../DESIGN_draft.md(P4C01 DESIGN_draft 승계 · 달라진 것만)
##   왜 판 2: P4C01(코어 v4)은 등록 · 기저 측정 뒤 첫 무인 틱(11-15 08:37)에서 생성기 작업 폴더 만들기가 멈췄다 — v4 설계 입력의 사유 코드 설명(코어 상수)에
##     든 리뷰 id 날짜가 처방 입력 검사에 걸린다(풀을 넘기는 모든 v4 사슬이 같다). 고치다 본 둘째 구멍: 목적 글(purpose)이 생성기 입력에 없었다 — P4C01 의
##     범위 문장('걸음 = blend 만' · '부품 = T0 만 · 생성기가 지킨다')은 생성기가 볼 수 없었다. 출시 판은 고치지 않으므로(RELEASES immutability) 코어 v5 로 다시 등록한다.
##   P4C01 과 같은 것: 기저 규칙(아래 · 기계) · 채택 규칙 7(그대로 옮김) · 예산(최대 걸음 20 · 잡음 2) · 닫기 판독 ①~⑤ · 부품 범위.
##   달라진 것: 코어 v5 · 걸음 정책 step_policy(blocks = blend · part_engine_rx = T0 엔진 경로 — 범위를 기계로 검사) · 목적 글 첫머리(판 2 사유) · 예산 근거 문구(P4C01 기저 1 시행).
##   실행 조건(하나라도 아니면 중단): ① RELEASES v5 ② 기저 풀 T0 후보 · 고른 기저 = P4C01 기저(같지 않으면 멈춘다 — 풀이 바뀌었으면 설계를 다시 본다) ③ 이 폴더에 chain_spec.json 없음.
##   그다음: 철학 P1 + 판단 T1(동시) → round.sh <사슬> p4-check → p4-register --p1 <id> --t1 <id> → p4-base-measure(손 · 아침 체인 밖) → 생성기 작업 폴더 시험 → tick_hold 삭제.
## 실행(저장소 루트): Rscript 04_Research/programs/P4_ASSEMBLY/P4C02_fc_blend/tools/init_p4c02.R [--dry-run]
suppressMessages(source("04_Research/programs/_lib/round_core/v5/load.R"))
stopifnot(identical(RC_VERSION, "v5"), identical(RC_P4_RULES_VERSION, "p4_rules_v3"))
root <- rc_root(); dry <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)
cd <- "04_Research/programs/P4_ASSEMBLY/P4C02_fc_blend"; c1 <- "04_Research/programs/P4_ASSEMBLY/P4C01_fc_blend"
if (file.exists(file.path(root, cd, "chain_spec.json"))) stop("[init_p4c02] chain_spec.json 이 이미 있다 — 덮어쓰지 않는다")
rel <- jsonlite::fromJSON(file.path(root, "04_Research/programs/_lib/round_core/RELEASES.json"), simplifyVector = FALSE)
if (!dry && !("v5" %in% vapply(rel$releases, function(r) as.character(r$version), ""))) stop("[init_p4c02] RELEASES 에 v5 출시 항목 없음(--dry-run 은 출시 전에도 돈다 · 쓰지 않는다)")
if (!dry) { r5 <- Filter(function(r) identical(as.character(r$version), "v5"), rel$releases)[[1]]   # 사슬은 코어 매니페스트를 핀하지 않는다 — 지금 파일 = 출시 기록(변경분 점검 R-3)
  if (!identical(rc_core_manifest()$manifest_md5, as.character(r5$manifest_md5))) stop("[init_p4c02] 지금 v5 파일의 매니페스트 ≠ RELEASES v5 — 출시 뒤 코어가 바뀌었다") }
S1 <- rc_json_read(file.path(root, c1, "chain_spec.json"))

pool <- data.table::as.data.table(rc_p4_base_pool(root))
t0rx <- "^04_Research/strategies/FC_(FAM_[a-z_]+|TOTAL_EW)/engine\\.R$"
cand <- pool[eligible %in% TRUE & grepl(t0rx, engine_path) & !grepl("_ICW/", engine_path) & own_spec_engine %in% TRUE]   # P4C01 과 같은 후보 규칙(판단 C-20261115-050)
cat(sprintf("[init_p4c02] 기저 풀 %d 행 · eligible %d · T0 후보 %d\n", nrow(pool), sum(pool$eligible %in% TRUE), nrow(cand)))
if (!nrow(cand)) stop("[init_p4c02] T0 후보 0")
g <- data.table::rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  r <- cand[i]; x <- rc_p4_gap(r$artifacts, root)
  data.table::data.table(pool_key = r$key, engine_path = r$engine_path, family_root = r$family_root, label_class = r$label_class,
                         S_vis = x$metrics$S_vis, port_t_vis = x$metrics$port_t_vis, calmar_vis = x$metrics$calmar_vis, window_end = x$window[2])
}))
data.table::setorder(g, -S_vis, -port_t_vis, pool_key)
if (nrow(g) > 1L && abs(g$S_vis[1] - g$S_vis[2]) < 1e-12 && abs(g$port_t_vis[1] - g$port_t_vis[2]) < 1e-12) cat("[init_p4c02] S · PORT_t 모두 동률 — key 사전순으로 고른다\n")
base_key <- g$pool_key[1]
cat(sprintf("[init_p4c02] 기저 = %s(%s · %s) — 보는 창 S 최대(후보 %d)\n", base_key, basename(dirname(g$engine_path[1])), g$label_class[1], nrow(g)))
if (!identical(base_key, S1$base$key)) stop("[init_p4c02] 기저가 P4C01(", S1$base$key, ")과 다르다 — 풀이 바뀌었다 · 설계를 다시 본다(판 2 = 같은 설계 재등록)")

RULES <- S1$adoption$rules                       # P4C01 채택 규칙 7 그대로(값 참조 · 출처 문구 포함 — 다시 쓰지 않는다)
if (length(RULES) != 7L) stop("[init_p4c02] P4C01 채택 규칙 수가 7 이 아니다")
BUD <- S1$budget
BUD$max_steps_source <- paste0(BUD$max_steps_source, " · 판 2: 같은 기저의 앞 사슬 P4C01 기저 측정 1(같은 칸 사양 사본)이 닫기 시행 집합에 더해진다(p4.R 같은 기저 사슬 시행) — ",
                               "programs/trial_budget.R tb_rc_required_t_rho(ρ 0.8 · 계약 설정): K 66 → 67 요구 t 2.554 → 2.564 · 더해지는 시행은 기저 칸의 사본이라 최댓값 분포에 새 꼬리를 보태지 않는다(판단 C-20261115-076)")
POLICY <- list(blocks = list("blend"), axes = list("base_signal"), part_engine_rx = t0rx, blend_rule = "parent_plus_one",
               source = paste0("P4C01 목적의 범위 문장을 기계 검사로 — 걸음 = blend 만(철학 C-20261115-038 · N5 β 비대칭 규칙이 비중 · 구성 · 유니버스 걸음을 보지 않는다) · ",
                               "바꿀 축 = base_signal 만(blend 블록의 factors · base_weight 축 블렌드는 P1 자격 밖 부품 — 판단 C-20261115-074) · ",
                               "부품 = 동일가중(T0) 자체 사양 엔진만(판단 C-20261115-048 · IC 가중 · 레인 엔진 제외 — 기저 후보 규칙 t0rx 와 같은 정규식 · 판단 C-20261115-050) · ",
                               "블렌드 칸 = 부모 칸 엔진 전부 + 새 부품 정확히 1개(기저를 빼거나 한 걸음에 둘 이상 더하지 않는다 — 장치마다 판정 · 헌장 빈칸 23 · S0 엔진 보존 · 철학 C-20261115-081)"))
p1 <- S1$purpose
r1 <- "(N5 β 비대칭 규칙이 그 걸음을 보지 않는다 · 철학 C-20261115-038). "
r2 <- "부품 = 동일가중(T0) 엔진만 — IC 가중(_ICW) 엔진은 기저 풀에 eligible 로 있어도 부품으로 쓰지 않는다(기계 차단 없음 · 생성기가 지킨다 · 판단 C-20261115-048). "
if (!grepl(r1, p1, fixed = TRUE) || !grepl(r2, p1, fixed = TRUE)) stop("[init_p4c02] P4C01 목적 글에서 바꿀 문장을 찾지 못했다")
## 철학 P1 R-20261115-011(C-20261115-082 ~ 084) — 목적 글은 생성기가 읽는다: 오도 문구 셋 고침 · 저β 원천 하나 · 탐색 순서 · 닫기 판독 ⑥ ⑦
RP <- list(
  c("blend 블록(기저 + 부품 1개 추가)부터 설계한다. ", "blend 블록(기저 + 부품 1개 추가)만 설계한다 — 블렌드 칸 = 부모 칸 엔진 전부 + 새 부품 정확히 1개(판 2 = 걸음 정책 blend_rule 로 기계 검사 · 철학 C-20261115-081). "),
  c("(N5 β 비대칭 · same_lineage_blend 표식)뿐. ", "(닫기 판독 ③ — 시가총액 × β 라벨 · 기저 대비 Δβ 로 판독)뿐. "),
  c("(방향 수정 · 생성기 개정)", "(방향 수정 · FC 엔진 생성기 개정)"),
  c("⑤ 희소 구성원 쏠림 대조 = 미측정(사이드카 없음 · 철학 C-20261115-016).",
    paste0("⑤ 희소 구성원 쏠림 대조 = 미측정(사이드카 없음 · 철학 C-20261115-016) ",
           "⑥ 소형주 착시 = 유동성 3분위 위기 손익 귀속(P2 계약 rc_p2_liq_tercile_cell 재사용 · 보는 창 · 기준 칸 = 기저 측정 뒤 · 최종 후보 = 닫기 · 기록만 · 판정 무접촉 · ",
           "못 재면 '소형주 착시 미측정' 꼬리표 · 철학 C-20261115-070 · C-20261115-082) ",
           "⑦ 닫기 다음 탐침 ≥ 2 가운데 한 자리 = 새 기저 신호 원천(15 카테고리 밖 · 철학 C-20261115-068 (가)) · 기저 풀 철학 표 사이드카(C-068 (나) · 도구가 있으면 · 없으면 미측정)."))
)
for (r in RP) { if (!grepl(r[1], p1, fixed = TRUE)) stop("[init_p4c02] P4C01 목적 글에서 바꿀 문장을 찾지 못했다: ", substr(r[1], 1, 40)); p1 <- sub(r[1], r[2], p1, fixed = TRUE) }
r3 <- "방어 주장 없음(도훈 LOWBETA-ENGINES-BASE-USE-20261113 · CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113). "
if (!grepl(r3, p1, fixed = TRUE)) stop("[init_p4c02] 저β 표기 문장을 찾지 못했다")
p1 <- sub(r3, paste0(r3, "저β 다섯은 측정 원천 하나로 센다(P1R03 · P1R04 판정) — 저β 상대끼리 바꿔 끼우는 걸음은 새 원천 시행이 아니다 · ",
                     "부품은 측정 원천이 다른 것(성장 · 컨센서스)과 저β 묶음 하나를 먼저 고려한다(탐색 순서 · 등록 때 고정 · 철학 C-20261115-084). "), p1, fixed = TRUE)
p1 <- sub(r1, "(N5 β 비대칭 규칙이 그 걸음을 보지 않는다 · 철학 C-20261115-038 · 판 2 = 걸음 정책 blocks 로 기계 검사). ", p1, fixed = TRUE)
p1 <- sub(r2, paste0("부품 = 동일가중(T0) 엔진만 — IC 가중(_ICW) 엔진 · 레인 엔진은 기저 풀에 eligible 로 있어도 부품으로 쓰지 않고, 팩터(factors) · 기저 비중(base_weight) 축으로 섞지도 않는다",
                     "(판 2 = 걸음 정책 part_engine_rx · axes 로 기계 검사 · 판단 C-20261115-048 · C-20261115-074). "), p1, fixed = TRUE)
## 목적 글은 설계 입력 §0 에 실린다(처방 입력 — 판단 C-20261115-078 (ii)): 판 2 사유(하네스 사연)는 DESIGN_draft §1 에 두고 목적엔 한 줄만
purpose <- paste0("블렌딩 사슬 1호 판 2(P4C02) — P4C01 과 같은 설계다 · 걸음 블록 · 바꿀 축 · 부품 엔진 범위는 아래 걸음 정책 줄이 기계로 검사한다. ", p1)

sel <- list(schema = "p4c01_base_selection_v1", at = rc_now(), audience = "보는 창(τ_D 이전)만 · 등급 계약 gv3_S(rc_p4_gap) · 시험 창 값 없음",
            rule = "P4C01 과 같다 — 후보 = 기저 풀 eligible ∧ P1R03 T0 엔진(FC_FAM_<카테고리> · FC_TOTAL_EW · own_spec_engine) · 선택 = S_vis 최대 → port_t_vis → key · 판 2: 고른 기저 = P4C01 기저여야 한다",
            pool_md5 = rc_p4_pool_md5(pool), candidates = g, base_key = base_key, same_as = list(chain = "P4C01_fc_blend", base_key = S1$base$key))
lk <- rc_after_tau_leaks(sel[setdiff(names(sel), "at")], as.Date(rc_ref_value("06_Registry/behavior_card.json::tau_d", root)))
if (length(lk)) stop("[init_p4c02] 기저 선택 기록에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
if (is.null(.rcp4_purpose_view(purpose, rc_ref_value("06_Registry/behavior_card.json::tau_d", root)))) stop("[init_p4c02] 목적 글이 설계 입력 검사를 못 지난다")
if (dry) { print(g[, .(pool_key, engine = basename(dirname(engine_path)), label_class)]); cat("[init_p4c02] --dry-run — 쓰지 않았다\n"); quit(status = 0) }
sp <- rc_p4_chain_new(file.path(root, cd), "P4C02_fc_blend", base_key, pool, adoption_rules = RULES, budget = BUD, purpose = purpose, root = root, step_policy = POLICY)
rc_json_write(sel, file.path(root, cd, "base_selection.json"))
cat(sprintf("[init_p4c02] 사슬 판 %s · md5 %s · 기저 %s · 규칙 %d(%s) · 예산 걸음 %s · 잡음 %s · 걸음 정책 blocks = %s\n", rc_rel(sp, root), rc_md5(sp), base_key, length(RULES),
            RC_P4_RULES_VERSION, BUD$max_steps, BUD$noise_k, paste(unlist(POLICY$blocks), collapse = ",")))
