#!/usr/bin/env Rscript
# =============================================================================
# claim_lane.R — 폐지줍기 라운드 레인 소유권 등재 (세션 간 충돌 방지, 도훈 지시 2026-08-09)
# 공유 원장 쓰기는 정본 writer 경유만 (digits/pretty 가드 + 손실 가드).
# =============================================================================
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
if ("FQ-174" %in% ids) { cat("[claim] FQ-174 이미 존재 — 중복 등재 중단\n"); quit(save = "no") }

e <- list(
  id = "FQ-174",
  lane = "recovery",
  title = "폐지 풀(C/F 195 모듈) 시점-조건부 ML 앙상블 — 등급 지속성 · 잔차 직교 · MDD 레버 소재 (도훈 지시 2026-08-09)",
  hypothesis = paste0(
    "module_performance 210 모듈 중 grade C 134 + F 61 = 195 개 '폐지' 풀을 시점-조건부로 배합하면 ",
    "개별로는 미달인 재료에서 앙상블 수준의 자격이 나오는가. ML 은 '언제 어떤 모듈을 켤지'를 학습한다(도훈 지시). ",
    "목표축은 수익이 아니라 MDD/calmar — 도훈 지적('MDD 컨트롤이 제일 문제')과 calmar 0.64 HARD 가 일치."
  ),
  ev_rationale = paste0(
    "FQ-058 이 drawdown-aware **weighting** 을 config-scoped negative 로 확정하며 남긴 진단이 정확히 이 라운드를 지목한다: ",
    "'calmar-FAIL 은 SELECTION(보유)에서 발생 = weighting 레버 부재' → next_probe P1 'selection-측 crash 통제'. ",
    "RAMP R1(07-05) 판정문의 열린 frontier 'soft-membership ML 앙상블' 과 FQ-059 도 같은 축. ",
    "재료비용 0(모든 NAV 기산출) · 하네스 기존재(run_wf_ensemble 계약 경유)."
  ),
  wall_check = paste0(
    "★P0 사전 실측(2026-08-09, stage_artifacts/scrap_ensemble_20260809/)이 이미 두 벽을 세웠다 — 라운드 설계는 이 위에서만 유효: ",
    "(1) SCRAP active PC1 share 0.805 · eff-N 1.5 → 195 모듈이 사실상 1.5 개 베팅(교차 선택 헤드룸 희박). ",
    "(2) 완전예지 월별 ELITE<->SCRAP 스위치 SR 0.721 / MDD 40.0% 가 **정적 ELITE(SR 1.126 / MDD 24.6%)보다 나쁘다** ",
    "→ 롱온리 모듈 로테이션은 원리적으로 MDD 를 못 잡는다(β 공유, Σw=1 로 현금 회피 불가). ",
    "따라서 'ML 로 타이밍하면 MDD 가 잡힌다'는 소박한 형태는 착수 전 기각. 남은 검증 축 = 등급 지속성 · PC1 잔차 직교. ",
    "다중 arm 비교는 sweep → DSR HARD 적용. 종목수 max 25 는 NAV 합성에서 자동 충족되지 않음(P1 확인 항목)."
  ),
  data_gate = "없음 — module_performance.json 210 모듈 sim_result NAV 전량 로드 확인(실패 0건, 294개월 패널).",
  owner = "CLAIMED Q-Lead session ba4a1c30 (2026-08-09) — 도훈 직접 지시 '폐지줍기 + ML 시점 선택 + MDD 제어'",
  status = "in_flight",
  boundary_note_20260809 = paste0(
    "★세션 간 소관 경계 (도훈 지시 '다른 세션 연구와 충돌 금지'): ",
    "[vs WT-D20260809_002 tail_targeted_regime_overlay] 그쪽 = 현행 book 의 **노출 스케일 축소**(선별 불변, alpha_inheritance_cor 1.0). ",
    "본 라운드 = **모듈 멤버십/배합**(무엇을 켤지). 공유 축은 국면 라벨뿐 — 본 라운드는 라벨을 ML 피처 1종으로만 쓰고 ",
    "'라벨 자격' 판정은 WT-002 소관으로 남긴다. 노출 스케일 축(exposure timing)은 본 라운드가 건드리지 않는다. ",
    "[vs FQ-167 / FQ-168] 그쪽 = within_sector_reversal **단일 재료** 1건의 vol-국면 게이팅/오버레이 전용. ",
    "본 라운드 = **풀 레벨(195 모듈) 일반화**. 본 라운드 P0 결과(롱온리 모듈 로테이션의 MDD 한계)는 FQ-167 전제에 직접 정보를 주므로 ",
    "그쪽 착수 세션은 본 라운드 산출을 먼저 읽을 것. 단 FQ-167/168 자체는 미배정으로 남긴다(본 세션 점유 안 함). ",
    "[vs FQ-165 / FQ-171 / FQ-173, session cee0bdd0] 재료·층 모두 상이(M26 book-marginal / 분위 형태 census / 섹터 인플레 틸트) — 겹침 없음. ",
    "[쓰기 격리] 산출물은 stage_artifacts/scrap_ensemble_20260809/ 전용. 공유 원장은 frontier_queue_io.R 경유만. ",
    "module_performance.json / hypothesis_index.json 직접 쓰기 안 함."
  ),
  precheck_20260809 = paste0(
    "P0 실측(metric_type=diagnostic_precheck, 253개월 200503..202603, 벤치 정합): ",
    "SCRAP EW CAGR 11.46% SR 0.599 MDD 41.6% Calmar 0.276 active +0.140%/m t(plain) +0.620 / ",
    "ELITE EW CAGR 17.47% SR 1.126 MDD 24.6% Calmar 0.709 active +0.527%/m t +2.349 / BM CAGR 9.36% SR 0.455 MDD 47.1%. ",
    "조건부 프로파일: ELITE 가 4개 시장상태 전부에서 SCRAP 지배 — TAIL(bm<=-10%, n=8) paired t +3.72 · DOWN(n=97) +4.17 · ",
    "UP(n=100) +0.70(비유의) · SURGE(n=48) -1.37(비유의). corr(scrap,elite) active 0.766 = 상보재 아닌 열화 복제. ",
    "★단 등급이 전기간 성과로 부여됐다면 이 지배는 동어반복 — 지속성 검정(p0c)이 결정 관문. ",
    "⚠ p0b 의 'lossaverse' 오라클은 ifelse(v<0,3v,v) 순서보존 no-op 버그로 수익 오라클과 bit-동일 → 무효, p0c [B] 가 대체."
  ),
  next_action = paste0(
    "P0c 결과 분기: ①등급 지속성이 약하면(rank persistence ~0) '폐지' 라벨은 전방 정보 없음 → 풀 핸디캡 없음 → ",
    "PC1 잔차 위 ML 선택으로 진행 ②지속성이 강하면 폐지 풀은 실제로 열등 → 라운드를 '잔차 직교 소수 추출'로 축소. ",
    "어느 쪽이든 MDD 축은 모듈 로테이션이 아니라 selection-측 crash 통제(FQ-058 P1)로만 공략."
  ),
  source_refs = c(
    "mandate: 도훈 2026-08-09 '폐지줍기 — F등급 전략 조합 앙상블' + '머신러닝으로 어느 시점에 어떤 전략' + 'MDD 컨트롤이 제일 문제'",
    "parent: FQ-058 next_probe P1 (selection-측 crash 통제) · FQ-059 (soft-membership ML 앙상블)",
    "prior: memory project-ramp-r1-residual-sleeve-stack-20260705 (11 sleeve stack best 2.54, survivors 0)",
    "prior: measurement-graduation §6 (롱온리 β 공유 · 잔차 직교 구조 실재)",
    "artifacts: stage_artifacts/scrap_ensemble_20260809/{p0_inventory,p0b_headroom,p0c_persistence}.{R,json}"
  )
)

Q$entries[[length(Q$entries) + 1]] <- e
res <- write_frontier_queue(Q)
cat("[claim] FQ-174 등재 완료. added=", paste(res$added, collapse = ","), " n=", res$n, "\n", sep = "")
