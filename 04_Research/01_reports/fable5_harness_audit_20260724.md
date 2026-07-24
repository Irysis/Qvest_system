# Fable 5 하네스 전수 감사 + 아키텍처 업그레이드 (2026-07-24)

**의뢰**: 도훈 — "Qvest 시스템을 Fable 5에 정합하게 수정. 공식문서 참고, 과도한 Hook·불필요한 Skill·장황한 프롬프트 비판 점검. 정합한 부분과 잘 구분해서 전체 아키텍처 업그레이드."
**방법**: 57-agent 워크플로우(wf_3fe2009e-460) — 공식문서 조사 1 + 표면감사 4(훅/스킬·커맨드/autoload 프롬프트/모델·설정) + 변경제안 전건 2-렌즈 적대검증(반박자 + 증거검수). finding 115건 = keep 45 / 변경제안 70 (검증 26: CONFIRMED 16 · PARTIAL 10 · REJECTED 0 / 잔여 44 리더 triage).

---

## 1. 정합 판정 (keep 45 — 손대지 않음)

Fable 5 전환과 무관하게 **설계 의도대로 작동 실증**된 표면:

- **게이트급 훅 (실차단 증거)**: safety_guard(05_Production/01_Literature fail-closed) · backtest_contract_audit(.py 자체합성 block 포함) · discovery_graduation_gate(HARD 3종 fail-closed) · legacy_write_block · worktask_constraint_enforcer(25종·long-only·Σw=1) · axiom_enforcement_hook · worktask_sequence_enforcer · telegram_direct_call_guard · performance_realmeasure_gate(Stop) · research_continuity_guard(Continuity Firewall — 당일도 block 실발화) · auto_commit/auto_push(최대 실가동) · governor_concord_certifier · cert 발급 계열(alpha_discovery 등 — 07-18 실발급 4건).
- **라우터 구조**: qvest_hook_router dispatch(병렬 fan-out·first-block verbatim·fail-closed) — Claude Code 공식 훅 실행 모델과 정합.
- **저비용 advisory 모범**: factor_rotation_pit_guard · dispatch_measurement_gate · artifact_placement_guard · overlay_pit_grep · answer_principles_grep — 전부 grep-only(python 스폰 없음) + 조기 exit + 실전달. **이번 수리의 목표 상태가 이미 구현된 선례.**
- **effort 배치**: judge/governor/dispatch/ramp = xhigh, 리서치 5종 = high — Fable 5 공식 권고(기본 high, 판정-critical 상향)와 정확히 일치.
- **permissions 전면 allow + acceptEdits**: permission 레이어가 아닌 hook 레이어를 방어선으로 삼는 의도적 설계 — 유지.
- **스킬 본문 정합**: alpha-search · factor-db-discovery · cleaner · ramp · qvest-telegram(SOT로서) · qvest-alpha-style · qvest-risk-style(에이전트 실소비·비중복) · 커맨드 4종(alpha-search/factor-rotation/ramp/worktask).
- **autoload 규범 코어**: pit.md C1~C15 전문 · measurement-graduation §1~§7b HARD 수치 · backtest-contract 전문 — 압축 대상 아님(제1목표 직결).

## 2. 이번 세션 수리 실행 (검증 완료)

### 2a. 하드게이트 보안 수리 — 주입형 fail-open 4건 (CONFIRMED, 실행 재현 후 수리)
`'''$CONTENT'''` 소스 보간: content에 `'''` 또는 백슬래시(Windows 경로·JSON escape) 포함 시 python SyntaxError → ERR trap `{}` = **게이트 침묵 통과**. v8.1.2 constraint_enforcer 선례 패턴(env-경유 + quoted heredoc)으로 수리:
- worktask_spec_validator.sh:33 / method_shopping_limiter.sh:45 / challenge_loop_limiter.sh:30 / role_objective_guard.sh:54
- **실증**: 적대 페이로드(`'''`+백슬래시) 4/4 block 유지 + 정상 케이스 통과.

### 2b. 전달 0 훅 복원 6건 (0ab8b039 2026-05-29 회귀 — 감지하되 `{}`만 출력)
- mandate_compliance_check(6분기 mandate 검증) · rationalization_detector(합리화 표현 — challenge_note 카운터 52회 누적·전달 0 실측) → PostToolUse `hookSpecificOutput.additionalContext` 실전달 복원.
- feature_registry_economic_rationale · risk_crowding_score_check · cache_registry_enforce(07-03 감사 quick-win P2-2 이행) → 라우터 context 채널(`additionalContext` 단일키) 격상.

### 2c. ★ axiom_context_inject SyntaxError 수리 (감사 중 배터리가 적발한 미기록 결함)
07-13 "판정 어휘 규약" 추가분의 미이스케이프 따옴표 → python -c 인자 절단 → **07-13 이후 모든 Agent spawn에서 공리 주입(AX 전제·고정축·Distilled 지도)이 `{}` 침묵 결손**. 수리 후 2,482자 주입 복원. (Continuity Firewall 어휘가 정작 주입면을 깨뜨리고 있던 아이러니 — 신규 주입문은 반드시 battery 케이스로 검증할 것.)

### 2d. 성능 — 조기-exit 도입 (raw-INPUT superset grep, python 파싱 앞)
- Read 3훅(selection_contamination/covariance_freshness/lockbox_audit_trail): **모든 Read마다 bash 3+python 3스폰(회당 ~0.8s×3)** → 비매치 Read 0.16s. 정밀 판별·차단 표면은 무손실(superset 필터).
- W/E advisory 7훅(2b 3종 + ml_uncertainty/ml_cost_aware + mandate 3스폰 + rationalization 2스폰) 동일 패턴.
- sr_provenance_pre_certifier **라우터 dispatch 해제**: 전 경로 `echo "{}"`만 가능(GUIDE_MSG 조립 후 미사용·로그 0)·cert 발급은 PostToolUse sr_provenance_check 전담 — 행동 동일성 입증된 유일한 등록 해제. 파일 FS retain. dispatch 17→16.
- milestone_commit: `git push origin master`(stale ref — milestone 커밋 원격 미도달) → 현 브랜치 push + L-code 현행 계층(`l_code/<mode>/*.json`) 매치 추가. forge_integration_audit: WT_DIR 절대경로 앵커(0-byte 스냅샷 2/3 수리).

### 2e. Fable 5 모델 정합
- **에이전트 `model: opus` 핀 11종 전부 제거** → 세션 모델(Fable 5) 상속. 구 핀은 "자동 최신"이 아니라 Opus 4.8 고정 = 메인보다 하위 강등이었음. 폴백 = 한도/스폰 실패 시 opus 명시 재시도(도훈 07-14 정책, FS 외부화라 무손실). /qlead 커맨드 핀도 제거 + Scout/tmux listener stale 정리.
- **caching.md 전면 재작성**: 5분 TTL → 1시간 실측 · ScheduleWakeup ≤270s 폐기(대상-기반 대기로) · TeamCreate/Codex 절 삭제 · 모델 라우팅 절 재작성("세션 모델 미만 강등 핀 금지" 원칙으로 계승).
- CLAUDE.md: 표제 Fable 5-Native 패치 · Self-Adversarial 주체 = 세션 모델 · Axioms 요약의 AX-003/004/005/007 Distilled 강등 표기(axioms.md와 모순 해소) · 훅 카운트 48 현행화. axioms.md AX-008 · _shared_prefix `<execution_style>`(구 opus48 태그) · harness.md(2026-07-24 정합 절 신설 + Tier1 sr_provenance Pre 오표기 정정 + 카운트) 동반.

### 2f. 스킬/커맨드 정리
- **삭제 2건** (git rm): telegram-protocol(DEPRECATED 스텁 — v8.0 plan 'cruft 삭제' 기승인, 훅 안내 문자열 동시 교체) · worktask 구스킬(구 ID 형식·구 lifecycle 주입 오염원, commands/worktask.md 포인터 단일화 + 예시 현행화).
- **stale 수리 6건**: qvest-attribution-style(judge/governor 매 spawn 주입 — "Forge+Codex" → Self-Adversarial, **DSR≥0.5/MDD≤45%/turnover≤6 구 게이트 → HARD 3종·sweep-DSR·structural MDD·1,100% 현행화**) · qvest-opt-style(**DPL '실험 옵션' 광고 → settled-negative 재제안 금지**로 — INV-7 위반 상태였음) · qvest-worktask §7(v53 TeamCreate 현재형 서술 → 폐지 명기) · qvest-hook-debug(Codex 4절 제거 + bare python3 금지 + E2E 배터리·신규 등록 의무 패턴 3종 명문화) · factor-rotation §11(역-stale — "미빌드" 목록이 전부 실존) · qvest-cert-paths(codex-round.md 참조 → AX-008/harness Tier 6).
- **autoload/로드 다이어트 (내용 무손실 이관)**: measurement-graduation.md Change log 8.3KB → `docs/rules/measurement-graduation-changelog.md` (21.3→13.2KB, 매 세션 회수) · /qvest Version 절 8KB → `docs/CHANGELOG_qvest_command.md` (27.2→19.3KB) + v53 절·죽은 Plan 경로 정리.

### 2g. 검증 (전 GREEN)
- hook_e2e_battery **11/11 PASS** (감사 전 10/11 — axiom_inject FAIL이 기존재였음)
- 수정 훅 18종 `bash -n` 전부 OK · router selftest OK · router_dispatch.json 파싱 OK(17 엔트리)
- 주입 페이로드 테스트 4/4 block · advisory 전달 3종 JSON 스키마 확인 · 조기-exit 타이밍 실측

## 3. 도훈 confirm 큐 — **C1·C5·C6 승인·실행 완료 (2026-07-24 당일)**, 잔여 대기

**실행 완료 (도훈 승인)**:
- **C1 ✅**: enabledPlugins `codex@openai-codex` 해제 (settings.json `{}` — JSON 유효성 검증 PASS) + harness.md:158·00_Lawbook/DEPRECATION.md 동시 개정 (로컬 codex CLI·debate_helpers는 FS retain).
- **C5 ✅**: CLAUDE.md 역사 블록 이관 — 계보 10단·v8.1 8불릿·Release Status 이전버전/검증이력·v53 절·삭제 커맨드 행 상세 → `CHANGELOG_constitution.md` "이관 아카이브" 절에 verbatim 보존 + 본문 포인터화. CLAUDE.md 24.2→21.8KB (Fable 5 패치 신규 내용 추가분 상쇄 포함).
- **C6 ✅**: _shared_prefix.md 중복 대수술 — answer_principles(rule 대비 드리프트 실증)·backtest_contract 축자 사본 → "Read 의무 + 절대 최소 인덱스" 스텁, telegram v6.5 → v7 SOT 스텁, stage_order·s0_debate_consensus v6.0/v55 블록 삭제(tombstone 주석). 위반절차 L1~L3 등 prefix-고유 내용 보존. 21.9→**15.2KB** (agent spawn당 −6.7KB). 검증: memory_knowledge_health **Hard fail 0** (axioms 블록 무변경).

| # | 항목 | 근거 | 권고 |
|---|---|---|---|
| C1 | `enabledPlugins codex@openai-codex` 해제 | **유령 설정 실증**: `~/.claude/plugins/installed_plugins.json` 빈 상태(미설치·companion.mjs 부재) + 보존 근거("S0/RAMP codex CLI 사용")도 실체 없음. 단 v8.2 결정문이 '유지' 명시 | 해제 권고 (harness.md:158·DEPRECATION.md:91 동시 개정. 이미 harness.md에 실측 정정 주석 기입) |
| C2 | selection_contamination_detector·covariance_freshness_gate **완전 deregister** | 둘 다 구조적 dead(marker writer 부재 — PPID 설계 자체 불가 07-03 확정 / advisory 무전달·매치 대상 6-8 이후 무접촉). 단 07-03 감사가 '수리·retain' 결정 | 조기-exit trim으로 비용 ~90% 이미 회수 — 잔여는 급하지 않음. 결정 시 pit.md·harness_health REQUIRED_HOOKS 동기 개정 |
| C3 | 스킬 5종 정리 (alpha/risk/optimizer-research + execution/monitoring) | init 프롬프트(26.7/20.3/22.4KB)·에이전트 본문의 축약 중복, 자동 소비경로 0. 단 **07-05 결정문 "동명 SKILL 현역 유지" 번복** + 3종은 수동 슬래시 진입 표면이 소실됨 | 삭제 대신 `skillOverrides` 은닉 또는 qvest-worktask 리다이렉트 스텁 권고 |
| C4 | kr-inverse-pattern-miner 스킬 | 입력(methodology_memory.md) 부재 + Scout/S0 핸드오프 사멸로 절차 실행 불가 | 현행 경로(hypothesis_index + Distilled 부활신호)로 재작성 또는 은닉 |
| C5 | CLAUDE.md 역사 블록 이관 (~6KB: v8.1 핵심·계보·Release 상세·v53 절·삭제 커맨드 행) | 헌법 P2 원칙("CHANGELOG_constitution.md가 SOT")과 정합이나 헌법 본문 대수술이라 confirm | 승인 시 1커밋으로 이관 (24.2→~18KB) |
| C6 | _shared_prefix.md 중복 대수술 (answer_principles 사본 3.3KB — 이미 rule 대비 드리프트 발생 · backtest_contract 사본 3.5KB · stage_order/s0_debate v55 블록 1.5KB · telegram v6.5 블록) | agent spawn 주입면 — 포인터화 시 스폰당 ~8KB 회수. 단 스폰 컨텍스트 자립성 trade-off | rule 파일 Read 의무 + 1줄 포인터 전환 권고 |
| C7 | execution/monitoring에 `model: opus` 재핀 (비용 차등) | 기계적 역할(주문 분해·임계 비교)이라 Fable 5(2x 비용) 불요 논거. 현재는 통일 상속 | 도훈 취향 — 월 1회 cron이라 실비용 차이 미미 |
| C8 | 무인 스케줄러 3종(alpha_search_queue_run 등) opus 폴백 자동배선 | 현재 spend_limit 문자열 경보만 — Fable 한도 시 무인 라인 정지 | next_probe: 실패 감지 → `--model claude-opus-4-8` 재시도 래퍼 |
| C9 | agent_stop_continuity_check(SubagentStop) 재설계 | 생애 발화 0 실측·WT 추정 휴리스틱 약함·escalate 무전달 — Continuity Firewall SOT에도 미등재 | Firewall과 통합 재설계 또는 deregister |
| C10 | milestone s7/pg2 레인 제거 | v8.3 SOT D4(grade_a_catalog 격리) 계류 건과 묶임 | D4 결정 시 동반 |

## 4. 잔여 미검증 finding

워크플로우 미검증 44건 중 본 세션 리더가 실파일 재확인 후 실행한 것(2e/2f 대부분)·확인 대기 큐(§3)로 전량 배분 — 방치분 없음. 원 데이터: 세션 스크래치패드 `confirmed/partial/unverified/keeps.md` + 워크플로우 저널.

## 5. 다음 사이클 (next_probe)

1. **C1~C6 confirm 회부** (본 보고서 §3 표 기준 — C1·C5·C6이 토큰/정합 효익 최대).
2. **훅 신규 등록 의무 패턴의 기계 강제**: qvest-hook-debug §10에 명문화한 3의무(env-경유·조기-exit·additionalContext)를 hook_e2e_battery에 lint 케이스로 추가 — `'''$CONTENT'''` 패턴 grep 시 FAIL.
3. **주입문 배터리 커버리지**: axiom_context_inject 류(셸→python 조립 주입문)는 신규 문구 추가 시 battery 케이스 동반 의무 — 07-13 침묵 결손 재발 방지.
