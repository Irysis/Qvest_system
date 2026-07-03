# Qvest Legacy Boundary — v55 / S0-S7 격리

**버전**: v1.0 (2026-05-01 Session 75 Sprint 1 Phase 1)
**목적**: v8.1 active path와 legacy v55/S0-S7 명확 격리. **legacy 삭제 안 함, compat 호환 격리**.
**Active SOT**: `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md`

---

## 1. v8.1 Active vs Legacy 비교

| 영역 | v8.1 Active | Legacy v55 / S0-S7 |
|---|---|---|
| **lifecycle 단위** | WorkTask (`WT-{D|P|S|H}YYYYMMDD_NNN`) | Strategy (`STR_NNNN`) + Stage (`S0~S7`) |
| **roles** | alpha-research / risk-research / optimizer-research / forge / judge / governor | scout (alpha-research로 흡수) / forge / judge / governor / risk-manager / blender |
| **gates** | PG0~PG3 (admission) + Gate 0~18 (judge) | PG0~PG3 + Gate 0~6 (legacy judge) + S0 Debate v55 5인 |
| **자체 적대검증** | Self-Adversarial Challenge (v8.2 — Codex Round 제거, Opus 4.8 자체 적대검증, challenge_note.md) 6 role | v55 S0 Debate codex critic (cross-model 1 of 5) |
| **certificate** | 5 cert + 1 health (Charter v1.2/v1.7 §10) | (legacy 없음) |
| **hook tier** | T1~T6 router (Phase 4) | 17~18 individual hooks |
| **artifact** | `qepm/mailbox/worktask/{WT_ID}/` | `04_Research/strategies/STR_NNNN_*/` + `stage_artifacts/` |

---

## 2. Legacy 자산 보존 + 격리 정책

### 2.1 보존 자산 (수정 금지)

- `04_Research/strategies/STR_NNNN_*/` — 기존 178+ 전략 결과
- `06_Registry/` — 기존 strategy registry
- `qepm/memory/axioms/active/AX-*.json` — 기존 active axioms
- `qepm/memory/axioms/candidates/CAND_*.json` — pending candidates
- `qepm/state_archive/` — 과거 책 active state
- `methodology_archive.md` (L-000 ~ L-129) — 구 L-codes
- `methodology_memory_v3_archive.md` — v3 L-528 ~ L-568

### 2.2 격리 자산 (`_archive_` prefix)

- `02_Infrastructure/hooks/_archive_v55/` — v55 폐기 hook 6 (이미 격리)
  - judge_autospawn.sh / s5_spawn_order.sh 등
- `02_Infrastructure/hooks/_archive_4_6/` — v4.6 legacy
- (Phase 9에서 추가 격리 검토): `_archive_v6_3_3_pre_router/` — v6.3.3 individual hook 17건

### 2.3 호환 자산 (legacy compat retain)

| 자산 | 상태 |
|---|---|
| TeamCreate teammate (Scout/Forge/Judge/Governor) | retain — v8.1도 사용 |
| `tmux rc` (telegram listener) | retain — v8.1도 사용 |
| `qepm/scripts/hybrid_mode.R` | retain — `hybrid_commit()` 등 R0~R6 |
| `02_Infrastructure/data/daily_refresh.sh` | retain — Cron daily |
| `02_Infrastructure/regime/regime_engine.R` v7.1 | retain |
| `02_Infrastructure/factor_db/` | retain — 288 factor monthly + 309 daily |
| `02_Infrastructure/portfolio/measurement_basis_audit.R` | retain — Health Score 산출 |
| `02_Infrastructure/ops/cert_backfill_audit.R` | retain — Layer 2 sweep |

---

## 3. Legacy → v8.1 Migration Path (점진)

### 3.1 Strategy → WorkTask 전환

기존 `STR_NNNN` 전략은 deployment WT로 wrapping 가능:
```r
wt_create(
  hypothesis_title = "STR_1715 deployment",
  wt_type = "deployment",
  discovery_of = "STR_1715"  # legacy STR ID retain
)
```
→ `WT-PYYYYMMDD_NNN` 생성 + legacy STR_1715 metadata + cert backfill via Layer 2.

**기존 admit 전략** (e.g., STR_1715 PG2 active):
- book_state.json `admitted_ids: [STR_1715_WT016_Iter31_GridBestProd]` 유지
- WT-P20260429_002 (deployment WT) lifecycle 정합 (Charter v1.7 §10 적용)
- 5 cert backfill 완료 (Session 73 Day 3)

### 3.2 S0~S7 Stage → WT phase 매핑

| Legacy Stage | v8.1 Equivalent |
|---|---|
| S0 (가설 설계) | alpha-research Step 0 (Hypothesis Discovery) |
| S1 (factor construction) | alpha-research Step 1 (factor_specs) |
| S2 (profiling) | alpha-research Step 2 (diagnostics) |
| S3 (orthogonality) | alpha-research Step 3 + risk-research crowding |
| S4 (integration test) | risk-research stress + optimizer feasibility |
| S5 (mutation lab) | (deprecated v6.0 — alpha-research 자율 흡수) |
| S6 (validation) | judge agent Gate 0~18 |
| S7 (disposition) | governor agent PG0~PG3 |

### 3.3 v55 S0 Debate → v8.2 Self-Adversarial Challenge

> v8.2 (도훈 mandate): QEPM 파이프라인의 외부 Codex Critic Round 완전 제거. 메인 에이전트(Opus 4.8)가 자체 적대검증(Self-Adversarial Challenge)을 수행하므로 중복. AX-008 3-source는 Forge + Self-Adversarial + Architect (2/3 불변). 아래 좌측 v55 S0 Debate는 별개 legacy 시스템으로 보존.

| v55 S0 Debate (legacy 보존) | v8.2 Self-Adversarial Challenge |
|---|---|
| 5인 토론자 (Codex / Risk Mgr / Governor / Quant / Academic) | alpha-research 자체 Step 0 통합 흡수 |
| Bash codex_critic 1 of 5 토론자 | 메인 에이전트 Opus 4.8 자체 적대검증 (외부 spawn 없음) |
| stance/veto 점수제 | stance (APPROVE/REVISE/REJECT) + challenge_note.md (self-adversarial record) ACCEPT/PARTIAL/REBUTTAL |
| consensus_tally 5인 합 | 자체 적대 verdict + agent rebuttal |
| veto 권한 (codex 외 4인) | veto 권한 없음 (모든 적대검증은 devil's advocate) |

---

## 4. Legacy 메모리 격리 정책

| 메모리 | 정책 |
|---|---|
| `methodology_active.md` (L-130 ~ L-270) | active retain. v6.4 신규 lessons는 v8.1에 흡수 |
| `methodology_archive.md` (L-000 ~ L-129) | archive retain (read-only on demand) |
| `methodology_memory_v3_archive.md` (L-528 ~ L-568) | archive retain (구 v3 reference) |
| `experiment_log.md` (612 KB) | retain on-demand (특정 실험 검색 시) |
| `feedback_*.md` (~40건) | retain on-demand. autoload 1건 (`feedback_INDEX.md`) |
| `core_knowledge_base.md` | retain on-demand (논문 참조 Scout S0 → v8.1 alpha-research Step 0) |

---

## 5. 명확화 — 도훈 자주 묻는 혼동 case

### Q1: Scout는 이제 없나?
**A**: agent definition (`.claude/agents/scout.md`) **archive**. 역할은 alpha-research가 흡수 (Step 0 Hypothesis Discovery 자율). 단 `.claude/skills/scout-*` 등 일부 skill은 retain (alpha-research가 internally 사용).

### Q2: STR_1715 100% PG2 admit은 v8.1과 호환?
**A**: ✅ 완전 호환. WT-P20260429_002 deployment WT lineage + 5 cert backfill 완료 + book_state.json admitted_ids 유지. Charter v1.7 §10 Role Card "deployment" wt_type으로 정합.

### Q3: QEPM 자체 적대검증은 v55 S0 Debate랑 다른가?
**A**: 다름. v55 = 5인 토론자 중 1명(codex critic) + veto 권한 있는 4인 추가 (별개 legacy 시스템, 보존). QEPM v8.2 = **메인 에이전트 Opus 4.8 자체 적대검증(Self-Adversarial Challenge)** — v8.2에서 외부 Codex Round 제거(도훈 mandate), veto 없음, agent rebuttal 가능, challenge_note.md 기록. **6 role 모두 의무** (alpha/risk/opt/forge/judge/governor).

### Q4: 기존 hook 17건 다 폐기?
**A**: ❌ Phase 4에서 router 경유로 **변경** (폐기 X). 같은 hook이 `qvest_hook_router.py` policy JSON 참조하는 형태로 통합. legacy hook 자체는 retain.

### Q5: 16h 패치 다 끝난 후 리서치 재개?
**A**: ✅ 본 패치는 연구 지능 unchanged. 패치 동안 **리서치 실행 금지** (도훈 명시). Sprint 3 Phase 9.5 E2E dry-run cycle 후 정상 리서치 재개.

---

## 6. Verification (Sprint 1 Phase 1 결산)

```bash
# Active SOT 존재 확인
ls -la 02_Infrastructure/docs/qvest_v8_1_sot.md 02_Infrastructure/docs/qvest_modes_sot.md

# Legacy boundary 존재 확인
ls -la 02_Infrastructure/docs/qvest_legacy_boundary.md

# 보존 자산 무손상 확인
ls 04_Research/strategies/ | wc -l   # 178+
ls qepm/memory/axioms/active/ | wc -l  # 6
cat qepm/mailbox/governor/book_state.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('admitted_ids'))"
# expect: ['STR_1715_WT016_Iter31_GridBestProd']
```

---

## 변경 이력

- **v1.0** — 2026-05-01 Session 75 Sprint 1 Phase 1 — 신규 발행. v6.4 active vs legacy 명확 격리 + 5 혼동 case 명문화 + migration path.
- **v1.1** — 2026-06-12 — v8.1 SOT 흡수 후 active path 라벨 동기화.
- **v1.2** — 2026-06-30 — v8.2 도훈 mandate: QEPM 외부 Codex Critic Round 제거(메인 Opus 4.8 자체 적대검증으로 대체). §1 비교표·§3.3 매핑·Q3 라이브 서술을 Self-Adversarial Challenge로 reframe. **legacy v55 S0 Debate codex critic 설명은 별개 시스템으로 보존**(§1 우측열·§3.3 좌측열·§1 gates `S0 Debate v55 5인`).
