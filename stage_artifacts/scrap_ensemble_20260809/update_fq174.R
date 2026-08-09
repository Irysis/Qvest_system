#!/usr/bin/env Rscript
# =============================================================================
# update_fq174.R — FQ-174 라운드 결과 갱신 + next_probe 등재 (정본 writer 경유)
# =============================================================================
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-174")
stopifnot(length(i) == 1)

Q$entries[[i]]$status <- "measured_uncond_axis_survives_frontier_open_20260809"

Q$entries[[i]]$result <- paste0(
  "측정 완료 2026-08-09 (metric_type=diagnostic_precheck·screen-tier, 자본 판정 아님). ",
  "재고: 명목 195 → 완전커버 191 → corr>=0.999 병합 **유효 독립 85**(축소 55.5%, 최대 중복그룹 49개). ",
  "중복 제거가 측정을 바꾼다 — 49개 그룹이 naive EW 비중 25.7%를 먹어 총계 알파를 부풀렸고, ",
  "dedup 후 풀 전체 active는 월 +0.021%(t 0.043)로 사실상 0. ",
  "base EW85(OOS 194개월 2010-02~2026-03): CAGR 10.45% SR 0.659 MDD 40.5% Calmar 0.258. ",
  "\n■ 죽은 축 3종. (1) **상태-조건부 선택 = 베타**: spearman(모듈 beta, 상태평균 active) = DOWN -0.9751 / SURGE +0.9851 ",
  "(rank R^2 0.951/0.970), beta 잔차화 시 split-half 지속성 -0.401/-0.716로 **음수 붕괴** ⇒ 멤버십 아닌 **노출 스케일 축**, ",
  "WT-D20260809_002 소관으로 이관. (2) **국면 라벨 무판별**: P(DOWN|DOWN_t-1)=0.133 vs base rate 0.122 · SURGE 0.245 vs 0.193 ",
  "⇒ 전이 정보 없음. PIT 지연 라벨 스위칭의 **전지식 상한조차 t=+1.76**. 동월 라벨로 잰 지속성은 실행 불가능한 세계의 수치. ",
  "(3) **MDD 축**: 유의한 개선에 필요 ΔMDD 4.49%p(block=12 rep=1000 paired SE 2.245%p) > 직접 측정 IS→OOS 전이 +2.90%p. ",
  "게다가 '달성가능 min MDD'가 독립 탐색 5회에서 30.5/33.4/34.1/34.5/35.6%(range 5.1%p)로 흔들려 **탐색 산포 > 필요 효과** ",
  "= 바가 진짜 개선과 탐색 운을 구별 못함. 저베타 선택은 MDD를 37.0%로 낮추나 CAGR 7.10%로 붕괴해 Calmar 0.192(base 0.258 미만).",
  "\n■ **살아남은 축 = 무조건부 성과 선택**(가장 밋밋한 규칙). 워크포워드 PIT, K 격자 전량: ",
  "무조건부 평균 K=10 paired +0.327%/m t_NW3 +2.598 Calmar 0.398 / K=20 +2.615 / K=30 +2.620 / K=40 +2.596 / K=50 +2.856. ",
  "무조건부 IR K=50 +2.723. t가 K에 **평평**해 argmax 취약성 낮음. ",
  "잔차-직교 선택은 열등: 직접 대결 paired t 전 K 음수(-1.98/-2.79/-2.43/-2.01/-3.14), Jaccard(잔차,무조건부평균) K=30 median 0.579. ",
  "⇒ **'직교성' 프레이밍 철회**. 회수율(PIT/ex-post 상한) = 27.2/26.5/33.2% — 상한의 67~73%를 **선택 잡음**이 먹는다(비용 아님: K=30 회전 33%x15bps ≈ 연 0.05%).",
  "\n■ 자격 미달 확인: 15 trial Bonferroni 문턱 2.94에 최고 2.856 미달 · Calmar 0.398 << HARD 0.64 · ",
  "종목수 max 25를 NAV-레벨 합성이 자동 충족하지 않음(모듈 sim_result에 보유 필드 부재, HOLDINGS_LOG만) ⇒ screen-tier 라벨."
)

Q$entries[[i]]$ml_disposition_20260809 <- paste0(
  "ML(A4 arm)은 **실행되지 않았다** — 검정력 관문 ABORT로 arm 진입 전 중단. 피처 패널은 빌드 완료",
  "(ml_feature_panel.rds, dedup 85 x 254개월, 결측 0). ",
  "★안 돌린 것이 옳다: (a) 학습 대상 축의 정체가 beta(R^2 0.95~0.97)라 ML은 beta를 재학습할 뿐 ",
  "(b) 입력 라벨이 무판별(P(DOWN|DOWN)=0.133 vs 0.122)이라 정보가 없는 입력에서 뽑을 모델이 없음 ",
  "(c) ML은 trial을 늘려 DSR/Bonferroni 바를 **올린다** — 이미 2.94를 못 넘는데 HPO 스윕이면 3.5+. ",
  "재조준: 측정된 병목은 예측이 아니라 **추정 분산**(선택 잡음이 상한의 67~73%). ",
  "따라서 다음 라운드의 ML 역할 = 예측기가 아니라 **축소추정기** — ①경험적 베이즈/James-Stein 축소 ",
  "②선택 규칙 앙상블(창 12/24/36/60m x 통계 평균/IR/중앙값 합의 투표) ③소프트 멤버십(FQ-059 축). ",
  "셋 다 자유도를 거의 안 늘려 다중검정 바를 올리지 않으면서 병목을 직접 겨냥한다. ",
  "무조건부 축이 이미 t 2.60~2.86이므로 분산 20% 축소로 문턱 도달 가능."
)

Q$entries[[i]]$next_action <- paste0(
  "[NP-1 최우선] 축소추정 라운드 — 무조건부 성과 추정치에 경험적 베이즈 축소 적용 후 t가 2.94를 넘는지. ",
  "사전등록: 축소 강도는 IS-only 결정, K 격자 고정, 전량 보고. ",
  "[NP-2] 선택 잡음 67~73% 손실의 분해 — 추정 오차(창 길이/축소로 개선 가능) vs 알파 감쇠(개선 불가). ",
  "PC1 추정 창 연장판과 축소판의 회수율 비교로 분리. ",
  "[NP-3] 국면 라벨 교체 — 현 라벨은 bm 실현치 기반이라 무판별. **사전 관측 가능** 지표로 교체 시 ",
  "P(DOWN|DOWN_t-1)이 base rate 0.122를 유의하게 넘는지가 상태-조건부 lane 재개의 단일 관문. ",
  "[NP-4 이관] beta 실측 3건(beta-상태 spearman -0.975/+0.985 · beta 잔차 지속성 -0.401/-0.716 · 라벨 전이표)을 ",
  "WT-D20260809_002 노출 스케일 축으로 전달 — 그쪽은 라벨 없이 정적 beta로 쓸 수 있어 본 라운드의 PIT 병목을 겪지 않는다."
)

Q$entries[[i]]$revival_signal <- paste0(
  "① 노출 스케일 축(WT-D20260809_002)이 beta를 별도 층에서 처리하면, 지금 묶여 있는 수익/낙폭 맞교환이 풀려 ",
  "멤버십 축의 Calmar 상한이 재산정된다 — 그때 무조건부 선택 위에 재도전. ",
  "② 사전 관측 가능한 국면 라벨이 base rate 대비 판별력을 확보하면 상태-조건부 lane 재개(NP-3). ",
  "③ 폐지 풀에 비-수익 원천 모듈이 유입돼 유효 독립 수(현 85, eff-N 2.33)가 늘면 선택 잡음 바닥이 내려간다."
)

Q$entries[[i]]$self_correction_20260809 <- paste0(
  "본 라운드에서 Q-Lead 자신이 만든 측정 결함 4건(전부 실측으로 검거·수리): ",
  "①음성 대조 설계 오류 — 시장조정 회귀 lm(y~bm)의 귀무로 y 행만 셔플해 beta가 0.701→-0.080으로 파괴되고 ",
  "절편이 시장수익을 흡수, 귀무 t>2가 85개 중 80.9개(귀무>실측=검사기 사망). 올바른 귀무 y=beta*bm+shuffle(resid)로 교체. ",
  "②중심화 항등식 — 열-중심화한 뒤 절편을 '잔차 알파'라 부름. 중심화하면 절편이 **항상 정확히 0**(측정 아닌 산술). ",
  "실측 증거 = 195개 전부 alpha +0.000 t +0.00, 기대오탐 4.9인데 0. ",
  "③순서보존 no-op 오라클 — ifelse(v<0,3v,v)는 랭킹 불변이라 '손실회피 오라클'이 수익 오라클과 bit-동일. ",
  "④대조군 누락 — 워크포워드 잔차 선택을 base/무작위와만 비교하고 **무조건부 선택과 비교 안 함**. ",
  "그 대조가 결론을 뒤집음(잔차 열등 확정). 지적 출처 = power-bar 서브에이전트. ",
  "부수: p0/p0b의 'PC1 share 0.805 · eff-N 1.5'는 complete-case 20개월 산물로 무효 → 정정 0.643 / 2.33. ",
  "base parity 불일치(CAGR 11.04 vs 11.64)는 방법론 차이 아님 — Return.portfolio에 가중을 xts로 주면 첫 기간을 떨어뜨려 ",
  "2005-02(EW +13.21%)가 빠지는 한 달 정렬 문제(BASE_PARITY_RESOLVED.md)."
)

Q$entries[[i]]$result_ref <- paste0(
  "stage_artifacts/scrap_ensemble_20260809/ : p0_inventory · p0d_fast · p0e_orthogonality · p0f_dupcheck · ",
  "p0g_recompute · p0h_base_parity(+BASE_PARITY_RESOLVED.md) · p0i_pc1_beta · p0j_null_fixed · p0k_blocknull · ",
  "p0l_wf_residual · p0m_uncond_control · prereg_power_bars · ml_feature_panel.rds · charts/"
)

res <- write_frontier_queue(Q)
cat("[fq174] 갱신 완료. added=", length(res$added), " removed=", length(res$removed), " n=", res$n, "\n", sep="")
