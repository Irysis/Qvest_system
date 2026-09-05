# 다음 세션 인계 — 2026-09-05 (무인 루프 재개 · promo3 진행 중 · 하네스 수리 6건)

## 지금 상태 한 줄

**무인 리서치 루프는 돌고 있다** — `reinforce_auto_config.json::enabled = true`, 예약작업 `Qvest_ReinforceAutoLoop` = Ready(8분 주기).
활성 entry = `RP_20260904_163647_18444_rescued_rulefast_promo3`(depth 3 · 예산 29 · B1 9/9 착지 · 최고 B1_3 GR03 B 2.553).
다음 = **B5 리스크 오버레이**(적응 순서 B1→B5→B2→B3→B4 · 기전이 6칸 설계를 남김 · avoid: 목표변동성 스칼라 3종·스칼라 곱·ts_mom_sign).

## 오늘 일어난 일 (시간순)

1. 도훈 지시로 무인 루프 전면 재개(아키텍처 검증 정지 해제). 재개 전 재도출: kill switch·claim mutex(격리 사본·실제 Windows PID 픽스처).
2. promo2 B5·B2·B3·B4 완주(25/25) → 소진 → **승격(유니버스 리셋)** → promo3 개설.
3. **하네스 수리 6건** (전부 최소 · 양방향 검사 동반 · 배터리 등록은 이설 세션 뒤로 보류):
   - 러너 fatal(`att` 미정의: 회피 집행이 등록 앞) + 회피 표적 오판 → `rf_avoid.R`(문장이 셀 코드로 시작할 때만 표적) · `test_rf_avoid_target.R` 11/11
   - 설계 검증기 ↔ 엔진 카탈로그 술어 불일치(unverified/probe 실패 arm 통과) → `rfbd_catalog` 가 `weight_catalog_arms()` 호출 · `test_rf_block_design_catalog_parity.R` 6/6
   - 설계 칸 코드 위치 매김(B3 pick=격자 코드인데 슬롯으로 밀림) → `rfbd_cells` 코드=pick · `test_rf_block_design_code_follows_pick.R` 5/5
   - 재개(resume) 매핑 위치 의존(cells 24개에서 n=21→B4_22) → `rf_spec_sig.R::rf_resume_cell` · `test_rf_resume_cell_by_code.R` 7/7 · 원장 n=21/22 복구
   - 소진 위임이 퇴역 러너(`reinforce_auto_run.R`) 호출 → `reinforce_ledger.R::rf_exhaust_entry` + `next_paper.R` 직접 동기 호출 · `test_rf_exhaust_delegate.R` 6/6
   - 승격 carry 유니버스 리셋(도훈 결정) → `rf_promote.R::rf_promote_carry` · `test_rf_promote_carry_universe_reset.R` 5/5 · `test_rf_promote.R` 13/13
   ★공통 뿌리: **"n번째 = 격자 n번째"** 는 LLM 설계가 칸 수를 바꾸는 순간 거짓 — 위치로 찾는 코드는 전부 후보(`grep "\[\[a\$n\]\]\|\[\[used"`).
4. **오판 1건 (되돌림)**: promo2 n=17(코드 B3_12 · 실내용 KOSDAQ150 단독 · B 2.567)을 "PIT C6 상방 편의" 로 무효화했다가 철회.
   근거 카드(`project-kq150-membership-backfill-projection-20260822`)의 **머리 철회문**을 안 읽었다. 엔진 패널 실측: KQ150 2010-01 128종→2015-04 150→2015-12 166,
   2010~2015 편입 38/퇴출 0(K200 통제 92/90) = 편입만 기록되는 누적 명부, 미래참조 아님, 방향 하방/중립. 진짜 caveat = **창**(NAV 2010-02~ 200개월 · 2008 제외).
   복원 사슬: 원장 writer → L-code 재발행 → 코퍼스 재수확 → 클러스터 supporters 교체 → 철회 텔레그램. 조부모 B2 L-code 의 잘못된 회피문도 정정.
5. 텔레그램: 9칸·6칸 블록 본문(7.4~7.7KB · 4332자)이 4096자 한계로 실패 → 도훈 지시 "압축판 말고 제한에 맞추라" → **수리 7번째**: `rf_auto_notify.R::.cap_items`(처방 3건·160자 / 회피 3건·120자 + L-code 포인터 · 기전 문단은 보존) + `telegram_notify.R::tg_agent_brief` `.tg_fit_parts`(3900자 초과 시 가장 긴 섹션부터 절삭 · 표식 · <b>/<i> 재균형 · 제목 보존). 실물 재렌더 B5 3820자·B1 3771자(절삭 없이 통과). `test_rf_notify_fit_length.R` 9/9 · 회귀 rank_distinct 16/16 · send_verdict 3/3 · block_insights 19/19. 자동 분할 칩은 철회.

## 열린 결정 (도훈)

- **승격 carry 비중**: promo3 carry 가 EW — 승자 B3_12 가 KQ150 에서 cvar→EW 강등된 스펙이라. 유니버스 리셋 시 강등 전 비중(cvar) 복원할지(`rf_promote_carry` 한 줄).
- **팡파레**: 현행 "entry 에 처음 나온 등급" 만. 같은 등급이라도 entry 최고 PORT_t 갱신 시 울릴지(오염 팡파레 위험 병기).
- **무인 LLM 레인 모델**: 전부 opus. Fable 5.1 은 CLI 2.1.170 < 2.1.251 로 차단(config `llm.blocked_model`). `claude update` 시점 = 도훈. 이후 ②config ③산출물 검증은 세션.
- promo2 에서 소실된 KOSPI200 단독 칸(n=16 오판 회피) 재측정 여부 — 예산 밖.

## 칩 (별도 세션) · 미검증

- 진행 중 2: 다음 블록 서술 정합(rf_block_lcode 정적 순서) · 낡은 검사 이설(test_reinforce_auto.sh 3건 → 현행 러너)
- 대기 3: `prior_action_status` "0건 집행" 파생 결함 · **CDaR_LP 어댑터**(B2 결정적 질문의 유일 칸) · 텔레그램 자동 분할
- 미검증 1: `daily_cap` 백스톱(현행 러너)

## 카드 (오늘 신설·정정)

`feedback-a-crash-exposed-a-silent-wrong-skip-avoid-target-by-position-code-20260905`(4회 발화 누적 · C6 오판 정정 포함) ·
`feedback-eligibility-predicate-must-be-the-consumers-function-not-a-reread-of-its-data-20260905` · `feedback-promotion-carry-resets-universe-to-fixed-axis-20260905` ·
`feedback-regression-guards-catch-old-code-not-missing-new-code-20260905`(퇴역 위임 라이브 발화 추가) · MEMORY.md KQ150 훅 정정.
