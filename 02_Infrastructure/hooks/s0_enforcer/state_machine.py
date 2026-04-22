#!/usr/bin/env python3
"""state_machine.py — S0 Debate 상태 머신 (Phase C3.5 split, v55 strict)

호출 패턴 (s0_enforcer.sh wrapper):
  cat <stdin-input-json> | python3 state_machine.py <DTYPE> <HYP_ID>
    DTYPE ∈ {R1, R2, R3, VERDICT}
    HYP_ID = 가설 ID (e.g. H_1643)

stdin: Claude Code tool input JSON ({tool_input: {file_path, content, ...}})
stdout: 다음 구조의 JSON 한 줄
  {
    "hook_decision": {} | {"decision": "block", "reason": "..."} | {"hookSpecificOutput": {...}},
    "telegram": ["msg1", "msg2", ...],
    "post_actions": [{"type": "codex_r2_trigger"|"compact_factcheck", ...}]
  }

상태 파일 스키마(/tmp/s0_debate_state_<HYP_ID>.json) 불변:
  {hypothesis_id, state, r1_roles, r2_roles, r3_roles, r3_needed_roles?}
상태: IDLE → R1_IN_PROGRESS → R1_COMPLETE → R2_IN_PROGRESS
     → (R2_COMPLETE || R3_NEEDED) → VERDICT_READY → DONE
"""
from __future__ import annotations

import glob
import json
import os
import sys
import time

VALID_STANCES = {"APPROVE", "APPROVE_CONDITIONAL", "REVISE", "REJECT"}
VALID_CHANGES = {"UNCHANGED", "UPGRADED", "DOWNGRADED"}
VALID_TIERS = {"UNANIMOUS", "MAJORITY", "MINORITY", "DEADLOCK"}

ROLE_ICONS = {
    "risk_manager": "🎯", "governor": "🏛️", "quant": "📐",
    "academic": "📖", "codex_critic": "🤖", "judge": "⚖️",
}
STANCE_ICONS = {
    "APPROVE": "✅", "APPROVE_CONDITIONAL": "🟡",
    "REVISE": "🔄", "REJECT": "❌",
}
CHANGE_ICONS = {"UPGRADED": "⬆️", "DOWNGRADED": "⬇️", "UNCHANGED": "➡️"}
VERDICT_ICONS = {
    "APPROVE": "✅", "APPROVE_CONDITIONAL": "🟡",
    "REVISE": "🔄", "REJECT": "❌",
}

LOG_PATH = "/tmp/s0_debate_enforcer.log"


def _log(msg: str) -> None:
    try:
        with open(LOG_PATH, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except Exception:
        pass


def _clip(s, n: int = 120) -> str:
    s = str(s).strip().replace("\n", " ")
    return s if len(s) <= n else s[: n - 3] + "..."


def _progress_bar(n: int, total: int = 5) -> str:
    return "".join("▰" if i <= n else "░" for i in range(1, total + 1))


def read_state(state_file: str) -> str:
    if not os.path.exists(state_file):
        return "IDLE"
    try:
        with open(state_file) as f:
            return json.load(f).get("state", "IDLE")
    except Exception:
        return "IDLE"


def write_state(state_file: str, hyp_id: str, new_state: str, **extra) -> None:
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                d = json.load(f)
        except Exception:
            d = {}
    else:
        d = {}
    d.setdefault("hypothesis_id", hyp_id)
    d.setdefault("r1_roles", [])
    d.setdefault("r2_roles", [])
    d.setdefault("r3_roles", [])
    d["state"] = new_state
    d.update(extra)
    with open(state_file, "w") as f:
        json.dump(d, f, indent=2)


def add_role(state_file: str, round_key: str, role: str) -> int:
    with open(state_file) as f:
        d = json.load(f)
    key = f"{round_key}_roles"
    d.setdefault(key, [])
    if role not in d[key]:
        d[key].append(role)
    with open(state_file, "w") as f:
        json.dump(d, f, indent=2)
    return len(d[key])


def debate_mode(hyp_id: str = None) -> str:
    """
    Debate mode 결정 (Gap-6 Option B, Session 68 Day 2).

    우선순위:
      1. hypothesis-level marker file: /tmp/qvest_debate_mode_compact_{HYP_ID} (존재 시 compact)
      2. global marker file: /tmp/qvest_debate_mode_compact (존재 시 compact)
      3. env var QVEST_DEBATE_MODE (hook context에서 자주 누락)
      4. default: full

    이유: PostToolUse Write hook은 Claude Bash shell과 별도 프로세스 컨텍스트로
    시작되어 env var가 전달되지 않음. Marker file은 filesystem 기반으로 hook도 읽음.

    Marker 생성 (Q-Lead 또는 사용자):
      touch /tmp/qvest_debate_mode_compact                    # 전역
      touch /tmp/qvest_debate_mode_compact_H_SMOKE_v55        # 가설별
    """
    if hyp_id:
        per_hyp_marker = f"/tmp/qvest_debate_mode_compact_{hyp_id}"
        if os.path.exists(per_hyp_marker):
            return "compact"
    if os.path.exists("/tmp/qvest_debate_mode_compact"):
        return "compact"
    return os.environ.get("QVEST_DEBATE_MODE", "full")


def threshold_for(mode: str) -> int:
    return 3 if mode == "compact" else 5


# ─── Validation helpers ────────────────────────────────────────────────

def _validate_r1(content: str) -> dict:
    try:
        d = json.loads(content)
    except Exception as e:
        return {"ok": False, "error": f"JSON 파싱 실패: {e}"}
    role = d.get("role", "unknown")
    stance = str(d.get("stance", "")).upper()
    veto = d.get("veto_flag", "MISSING")
    crit = d.get("critical_concerns", []) or []
    sup = d.get("supporting_arguments", []) or []
    errors = []
    if stance not in VALID_STANCES:
        errors.append(f"stance='{stance}' 누락/비정상 (APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT 중 하나 필수)")
    if veto == "MISSING":
        errors.append("veto_flag 키 누락 (null이라도 명시 필수)")
    if len(crit) + len(sup) < 1:
        errors.append("critical_concerns + supporting_arguments 합산 0건 (1건+ 필수)")
    if errors:
        return {"ok": False, "error": "; ".join(errors)}
    veto_disp = "null" if veto in (None, "null", "") else str(veto)
    return {"ok": True, "role": role, "stance": stance, "veto": veto_disp}


def _validate_r2(content: str) -> dict:
    try:
        d = json.loads(content)
    except Exception as e:
        return {"ok": False, "error": f"JSON 파싱 실패: {e}"}
    errors = []
    role = d.get("role", "unknown")
    r1_stance = str(d.get("r1_stance", "")).upper()
    stance_change = str(d.get("stance_change", "")).upper()
    new_stance = str(d.get("new_stance", "")).upper()
    veto_flag = d.get("veto_flag", "MISSING")
    r1_veto = d.get("r1_veto_flag", d.get("veto_flag_r1"))
    unresolved = d.get("unresolved", [])
    reason = d.get("stance_change_reason", "") or ""

    if stance_change not in VALID_CHANGES:
        errors.append(f"stance_change='{stance_change}' 누락/비정상 (UNCHANGED/UPGRADED/DOWNGRADED 필수)")
    if new_stance not in VALID_STANCES:
        errors.append(f"new_stance='{new_stance}' 누락/비정상")
    if veto_flag == "MISSING":
        errors.append("veto_flag 키 누락 (null이라도 명시 필수)")
    if len(unresolved) < 1:
        errors.append("unresolved 0건 — 최소 1건 필수 (토론 없는 R2 = 반복)")
    if stance_change != "UNCHANGED" and len(reason) < 50:
        errors.append(f"stance_change={stance_change}인데 stance_change_reason 50자 미만 ({len(reason)}자)")

    if errors:
        return {"ok": False, "error": "; ".join(errors)}

    r1v = str(r1_veto).lower() not in ("", "none", "null", "false", "missing")
    r2v = str(veto_flag).lower() not in ("", "none", "null", "false", "missing")
    veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(veto_flag).lower())
    veto_disp = "null" if veto_flag in (None, "null", "") else str(veto_flag)
    return {
        "ok": True, "role": role, "r1_stance": r1_stance, "new_stance": new_stance,
        "stance_change": stance_change, "veto": veto_disp, "veto_changed": veto_changed,
    }


def _validate_verdict(content: str, mode: str) -> dict:
    try:
        d = json.loads(content)
    except Exception as e:
        return {"ok": False, "error": f"JSON 파싱 실패: {e}"}
    errors = []

    rounds = d.get("transcript", {}).get("rounds", [])
    if len(rounds) < 2:
        errors.append(f"transcript.rounds {len(rounds)}개 (최소 2라운드: R1+R2 필수)")

    fst = d.get("final_stances", {})
    if not isinstance(fst, dict) or not fst:
        errors.append("final_stances 누락 또는 빈 객체 (v55 필수, final_scores는 무시됨)")

    if mode == "compact":
        compact_core = {"codex_critic", "risk_manager"}
        compact_flex = {"judge", "governor"}
        fs_keys = set(fst.keys()) if isinstance(fst, dict) else set()
        if not compact_core.issubset(fs_keys):
            errors.append(f"final_stances에 compact 필수 역할 누락: {compact_core - fs_keys}")
        if not fs_keys.intersection(compact_flex):
            errors.append("final_stances에 judge 또는 governor 중 하나 필수")
        required_roles = list(fs_keys.intersection(compact_core | compact_flex))
        expected_n = 3
    else:
        required_roles = ["codex_critic", "risk_manager", "governor", "quant", "academic"]
        expected_n = 5

    if isinstance(fst, dict):
        for role in required_roles:
            if role not in fst:
                errors.append(f"final_stances에 {role} 누락")
                continue
            entry = fst[role]
            if "r1" not in entry or "final" not in entry:
                errors.append(f"final_stances.{role}에 r1/final 누락")
                continue
            if str(entry.get("r1", "")).upper() not in VALID_STANCES:
                errors.append(f"final_stances.{role}.r1 '{entry.get('r1')}' 비정상")
            if str(entry.get("final", "")).upper() not in VALID_STANCES:
                errors.append(f"final_stances.{role}.final '{entry.get('final')}' 비정상")
            if "stance_change" not in entry or str(entry.get("stance_change", "")).upper() not in VALID_CHANGES:
                errors.append(f"final_stances.{role}.stance_change 누락/비정상")
            if "veto_flag" not in entry:
                errors.append(f"final_stances.{role}.veto_flag 키 누락 (null이라도 명시)")

    tally = d.get("consensus_tally", {})
    if not isinstance(tally, dict):
        errors.append("consensus_tally 누락 (v55 필수)")
    else:
        for k in ("approve", "approve_conditional", "revise", "reject", "veto_count"):
            if k not in tally:
                errors.append(f"consensus_tally.{k} 누락")
        try:
            stance_sum = int(tally.get("approve", 0)) + int(tally.get("approve_conditional", 0)) \
                + int(tally.get("revise", 0)) + int(tally.get("reject", 0))
            if stance_sum != expected_n:
                errors.append(f"consensus_tally stance 합 {stance_sum} != {expected_n} (mode={mode})")
        except Exception:
            errors.append("consensus_tally 숫자 변환 실패")

    tier = str(d.get("consensus_tier", "")).upper()
    if tier not in VALID_TIERS:
        errors.append(f"consensus_tier '{tier}' 비정상 (UNANIMOUS/MAJORITY/MINORITY/DEADLOCK)")

    debaters = d.get("debaters", [])
    min_debaters = 3 if mode == "compact" else 5
    if len(debaters) < min_debaters:
        errors.append(f"debaters {len(debaters)}건 ({min_debaters}건 필수, mode={mode})")
    else:
        roles_found = set()
        for db in debaters:
            r = db.get("role", "").lower()
            if "critic" in r: roles_found.add("codex_critic")
            elif "risk" in r: roles_found.add("risk_manager")
            elif "gov" in r: roles_found.add("governor")
            elif "judge" in r: roles_found.add("judge")
            elif "quant" in r: roles_found.add("quant")
            elif "academic" in r: roles_found.add("academic")
        if mode == "compact":
            if "codex_critic" not in roles_found:
                errors.append("debaters에 codex_critic 누락")
            if "risk_manager" not in roles_found:
                errors.append("debaters에 risk_manager 누락")
            if not roles_found.intersection({"judge", "governor"}):
                errors.append("debaters에 judge 또는 governor 중 하나 필수")
        else:
            required_set = {"codex_critic", "risk_manager", "governor", "quant", "academic"}
            missing = required_set - roles_found
            if missing:
                errors.append(f"debaters 역할 누락: {missing}")
        for i, db in enumerate(debaters):
            if "stance" not in db:
                errors.append(f"debaters[{i}].stance 누락")
            elif str(db.get("stance", "")).upper() not in VALID_STANCES:
                errors.append(f"debaters[{i}].stance '{db.get('stance')}' 비정상")
            if "veto_flag" not in db:
                errors.append(f"debaters[{i}].veto_flag 키 누락")

    if not d.get("consensus_points"):
        errors.append("consensus_points 누락 또는 빈 배열 (1건+ 필수)")
    if "unresolved_disputes" not in d:
        errors.append("unresolved_disputes 키 누락")

    verdict = str(d.get("verdict", "")).upper()
    if verdict not in VALID_STANCES:
        errors.append(f"verdict '{verdict}' 비정상")

    if errors:
        return {"ok": False, "error": "; ".join(errors)}
    consensus = "; ".join(d.get("consensus_points", [])[:2])
    disputes_list = d.get("unresolved_disputes", []) or []
    disputes = "; ".join([str(x) for x in disputes_list[:2]]) if disputes_list else "(없음)"
    return {
        "ok": True, "verdict": verdict, "tier": tier,
        "a": int(tally.get("approve", 0)), "c": int(tally.get("approve_conditional", 0)),
        "rv": int(tally.get("revise", 0)), "rj": int(tally.get("reject", 0)),
        "veto_n": int(tally.get("veto_count", 0)),
        "consensus": consensus, "disputes": disputes,
    }


# ─── R1 summary builders ───────────────────────────────────────────────

def _build_r1_summary_md(artifacts_dir: str, hyp_id: str, out_path: str) -> None:
    lines = [
        f"# R1 요약본 — {hyp_id} (R2 Rebuttal용, v55)", "",
        f"> Full transcript: stage_artifacts/s0_debate_transcript_{hyp_id}.json",
        "> 토큰 절감을 위해 stance/veto/핵심 논거만 압축. 점수 없음 (v55).", "",
    ]
    for f in sorted(glob.glob(os.path.join(artifacts_dir, f"s0_debate_r1_*_{hyp_id}.json"))):
        try:
            with open(f) as fh:
                dd = json.load(fh)
        except Exception:
            continue
        role = dd.get("role", "?")
        stance = str(dd.get("stance", "?")).upper()
        veto = dd.get("veto_flag")
        veto_disp = "null" if veto in (None, "null", "") else str(veto)
        concerns = dd.get("critical_concerns", []) or []
        supports = dd.get("supporting_arguments", []) or []
        gate_items = dd.get("s1_gate_items", []) or []
        lines.append(f"## {role}  [stance={stance}, veto={veto_disp}]")
        if concerns:
            lines.append("**critical_concerns:**")
            for c in concerns[:2]:
                lines.append(f"- {_clip(c)}")
        if supports:
            lines.append("**supporting_arguments:**")
            for s in supports[:2]:
                lines.append(f"- {_clip(s)}")
        if gate_items:
            lines.append("**s1_gate_items:**")
            for g in gate_items[:2]:
                lines.append(f"- {_clip(g)}")
        lines.append("")
    try:
        with open(out_path, "w") as fh:
            fh.write("\n".join(lines))
    except Exception:
        pass


def _telegram_r1_summary(artifacts_dir: str, hyp_id: str) -> str:
    lines = [f"📋 [S0 Debate · {hyp_id}] R1 Opening Complete",
             "━━━━━━━━━━━━━━━━━━━━━━━━"]
    tally = {"APPROVE": 0, "APPROVE_CONDITIONAL": 0, "REVISE": 0, "REJECT": 0}
    veto_count = 0
    for f in sorted(glob.glob(os.path.join(artifacts_dir, f"s0_debate_r1_*_{hyp_id}.json"))):
        try:
            with open(f) as fh:
                dd = json.load(fh)
        except Exception:
            continue
        role = dd.get("role", "?")
        ricon = ROLE_ICONS.get(role, "👤")
        stance = str(dd.get("stance", "?")).upper()
        sicon = STANCE_ICONS.get(stance, "❔")
        veto = dd.get("veto_flag")
        tally[stance] = tally.get(stance, 0) + 1
        if veto and str(veto).lower() not in ("null", "none", "") and "codex" not in role.lower():
            veto_count += 1
        veto_disp = f"  🚫{veto}" if veto and str(veto).lower() not in ("null", "none", "") else ""
        crit = dd.get("critical_concerns") or []
        lines.append(f"{ricon} {role}  {sicon} {stance}{veto_disp}")
        if crit:
            lines.append(f"   💭 {_clip(crit[0], 110)}")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append(f"📊 R1 tally: ✅{tally['APPROVE']} 🟡{tally['APPROVE_CONDITIONAL']} 🔄{tally['REVISE']} ❌{tally['REJECT']}  veto={veto_count}")
    lines.append("💬 R2 Rebuttal 시작...")
    return "\n".join(lines)


def _telegram_r2_summary(artifacts_dir: str, hyp_id: str) -> str:
    lines = [f"📊 [S0 Debate · {hyp_id}] R2 Rebuttal Complete",
             "━━━━━━━━━━━━━━━━━━━━━━━━"]
    tally = {"APPROVE": 0, "APPROVE_CONDITIONAL": 0, "REVISE": 0, "REJECT": 0}
    veto_count = 0
    veto_list = []
    for f in sorted(glob.glob(os.path.join(artifacts_dir, f"s0_debate_r2_*_{hyp_id}.json"))):
        try:
            with open(f) as fh:
                dd = json.load(fh)
        except Exception:
            continue
        role = dd.get("role", "?")
        ricon = ROLE_ICONS.get(role, "👤")
        r1_st = str(dd.get("r1_stance", "")).upper()
        new_st = str(dd.get("new_stance", dd.get("stance", ""))).upper()
        sc = str(dd.get("stance_change", "UNCHANGED")).upper()
        cicon = CHANGE_ICONS.get(sc, "•")
        r1_si = STANCE_ICONS.get(r1_st, "❔")
        new_si = STANCE_ICONS.get(new_st, "❔")
        tally[new_st] = tally.get(new_st, 0) + 1
        veto = dd.get("veto_flag")
        if veto and str(veto).lower() not in ("null", "none", "") and "codex" not in role.lower():
            veto_count += 1
            veto_list.append(f"{role}={veto}")
        veto_disp = f"  🚫{veto}" if veto and str(veto).lower() not in ("null", "none", "") else ""
        unr = dd.get("unresolved") or []
        unr_txt = ""
        if unr:
            first = unr[0]
            if isinstance(first, dict):
                unr_txt = _clip(first.get("point", ""), 100)
            else:
                unr_txt = _clip(str(first), 100)
        lines.append(f"{ricon} {role}  {r1_si}{r1_st} {cicon} {new_si}{new_st}{veto_disp}")
        if unr_txt:
            lines.append(f"   ❓ {unr_txt}")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append(f"📊 R2 tally: ✅{tally['APPROVE']} 🟡{tally['APPROVE_CONDITIONAL']} 🔄{tally['REVISE']} ❌{tally['REJECT']}  veto={veto_count}")
    if veto_list:
        lines.append("🚫 " + "; ".join(veto_list[:3]))
    lines.append("⚖️ VERDICT 작성 가능")
    return "\n".join(lines)


# ─── R3 Decision (R2 완료 시) ──────────────────────────────────────────

def _decide_r3(artifacts_dir: str, hyp_id: str, mode: str) -> dict:
    new_stances = []
    need_r3_roles = []
    any_veto_change = False
    for f in sorted(glob.glob(os.path.join(artifacts_dir, f"s0_debate_r2_*_{hyp_id}.json"))):
        try:
            with open(f) as fh:
                dd = json.load(fh)
        except Exception:
            continue
        role = dd.get("role", "?")
        stance_change = str(dd.get("stance_change", "")).upper()
        new_stance = str(dd.get("new_stance", dd.get("stance", ""))).upper()
        r1_veto = dd.get("r1_veto_flag") or dd.get("veto_flag_r1")
        r2_veto = dd.get("veto_flag")
        r1v = str(r1_veto).lower() not in ("", "none", "null", "false")
        r2v = str(r2_veto).lower() not in ("", "none", "null", "false")
        veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(r2_veto).lower())
        new_stances.append(new_stance)
        if veto_changed:
            any_veto_change = True
        if stance_change != "UNCHANGED" or veto_changed:
            need_r3_roles.append(role)

    unique = set(s for s in new_stances if s)
    if mode == "compact" and len(unique) == 1 and not any_veto_change and len(new_stances) >= 3:
        return {"skip": True, "stance": next(iter(unique)), "tier": "strong", "roles": []}
    if not need_r3_roles:
        tier = "strong" if len(unique) == 1 else "mixed"
        one = next(iter(unique)) if len(unique) == 1 else "mixed"
        return {"skip": True, "stance": one, "tier": tier, "roles": []}
    return {"skip": False, "stance": "mixed", "tier": "mixed", "roles": need_r3_roles}


# ─── Handlers ─────────────────────────────────────────────────────────

def emit(result: dict) -> None:
    """stdout에 결과 JSON 한 줄 출력."""
    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    sys.stdout.write("\n")


def block(reason: str) -> dict:
    return {"hook_decision": {"decision": "block", "reason": reason}, "telegram": [], "post_actions": []}


def passthrough() -> dict:
    return {"hook_decision": {}, "telegram": [], "post_actions": []}


def _hook_context(ctx: str) -> dict:
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ctx}}


def handle_r1(hyp_id: str, state_file: str, file_path: str, content: str) -> dict:
    cur = read_state(state_file)
    if cur not in ("IDLE", "R1_IN_PROGRESS"):
        _log(f"ENFORCER BLOCK: R1 Write in state {cur}")
        return block(f"[S0 Debate Enforcer] 현재 상태 {cur}에서 R1 Write 불가. 새 토론은 기존 토론 완료 후 시작하세요.")

    v = _validate_r1(content)
    if not v["ok"]:
        _log(f"ENFORCER BLOCK R1: {v['error']}")
        return block(
            f"[S0 Debate Enforcer v55] R1 검증 실패: {v['error']}\\n\\n"
            "v55 R1 스키마: {role, stance, critical_concerns[], supporting_arguments[], veto_flag, s1_gate_items[]}\\n"
            "점수제(score) 폐기됨. SKILL.md Round 1 출력 스키마 참조."
        )

    if cur == "IDLE":
        write_state(state_file, hyp_id, "R1_IN_PROGRESS")
    n_roles = add_role(state_file, "r1", v["role"])

    mode = debate_mode(hyp_id)
    r1_total = threshold_for(mode)
    veto_disp = f"  🚫{v['veto']}" if v["veto"] != "null" and v["veto"] else ""
    tg_msg = (f"🎙 [S0 · {hyp_id} · R1]  {ROLE_ICONS.get(v['role'], '👤')} {v['role']}  "
              f"{STANCE_ICONS.get(v['stance'], '❔')} {v['stance']}{veto_disp}   "
              f"{_progress_bar(n_roles)} ({n_roles}/{r1_total})")
    _log(f"ENFORCER R1: {v['role']} [{v['stance']} veto={v['veto']}] [{n_roles}/{r1_total}]")

    if n_roles != r1_total:
        return {"hook_decision": {}, "telegram": [tg_msg], "post_actions": []}

    # R1 완료
    write_state(state_file, hyp_id, "R1_COMPLETE")
    artifacts_dir = os.path.dirname(file_path) or "stage_artifacts"
    summary_path = f"/tmp/s0_debate_r1_summary_{hyp_id}.md"
    try:
        _build_r1_summary_md(artifacts_dir, hyp_id, summary_path)
    except Exception as e:
        _log(f"R1 summary 생성 실패: {e}")

    tg_summary = _telegram_r1_summary(artifacts_dir, hyp_id)
    _log(f"ENFORCER: R1 COMPLETE → R2 시작 지시 (mode={mode})")

    post_actions = [{"type": "codex_r2_trigger", "artifacts_dir": artifacts_dir}]
    if mode == "compact":
        post_actions.append({"type": "compact_factcheck", "artifacts_dir": artifacts_dir})

    if mode == "compact":
        ctx = (
            f"[S0 Debate Enforcer] R1 3/3 Compact 완료. 다음 단계:\\n"
            f"1. 3개 R1 결과를 stage_artifacts/s0_debate_transcript_{hyp_id}.json으로 컴파일\\n"
            "2. R2 Rebuttal: 3인 재스폰 (R1 요약본 프롬프트에 주입)\\n"
            "3. R2 필수: 동의 1건+ / 반박 1건+ / 점수수정시 이유\\n"
            "4. academic_factcheck + quant_factcheck → background 실행 중\\n\\n"
            "[S2.13] Codex R2 Verify background 실행 중."
        )
    else:
        ctx = (
            f"[S0 Debate Enforcer] R1 5/5 완료. 다음 단계:\\n"
            f"1. 5개 R1 결과를 stage_artifacts/s0_debate_transcript_{hyp_id}.json으로 컴파일\\n"
            "2. R2 Rebuttal: 5인 재스폰 (transcript 전문 프롬프트에 주입)\\n"
            "3. R2 필수: 동의 1건+ / 반박 1건+ / 점수수정시 이유 / 최강 반론 지목\\n\\n"
            f"[S2.13] Codex R2 Verify는 background로 실행 중 — stage_artifacts/r2_codex_verdict_{hyp_id}.json 생성 확인 후 VERDICT 작성 시 참고하세요."
        )
    return {
        "hook_decision": _hook_context(ctx),
        "telegram": [tg_msg, tg_summary],
        "post_actions": post_actions,
    }


def handle_r2(hyp_id: str, state_file: str, file_path: str, content: str) -> dict:
    cur = read_state(state_file)
    if cur not in ("R1_COMPLETE", "R2_IN_PROGRESS"):
        _log(f"ENFORCER BLOCK: R2 Write in state {cur}")
        guide = ""
        if cur in ("IDLE", "R1_IN_PROGRESS"):
            guide = " R1이 아직 5/5 완료되지 않았습니다."
        return block(f"[S0 Debate Enforcer] R1 미완료 상태({cur})에서 R2 Write 불가.{guide}")

    v = _validate_r2(content)
    if not v["ok"]:
        _log(f"ENFORCER BLOCK R2: {v['error']}")
        return block(
            f"[S0 Debate Enforcer v55] R2 검증 실패: {v['error']}\\n\\n"
            "v55 R2 스키마: {role, r1_stance, stance_change, new_stance, stance_change_reason, veto_flag, r1_veto_flag, addressed_concerns[], unresolved[]}\\n"
            "점수제(r1_score/r2_score) 폐기. SKILL.md Round 2 출력 스키마 참조."
        )

    if cur == "R1_COMPLETE":
        write_state(state_file, hyp_id, "R2_IN_PROGRESS")
    n_roles = add_role(state_file, "r2", v["role"])

    mode = debate_mode(hyp_id)
    r2_threshold = threshold_for(mode)
    veto_disp = f"  🚫{v['veto']}" if v["veto"] != "null" and v["veto"] else ""
    if v["veto_changed"]:
        veto_disp += " ⚠️veto변동"
    tg_msg = (
        f"🔥 [S0 · {hyp_id} · R2]  {ROLE_ICONS.get(v['role'], '👤')} {v['role']}  "
        f"{STANCE_ICONS.get(v['r1_stance'], '❔')}{v['r1_stance']} "
        f"{CHANGE_ICONS.get(v['stance_change'], '•')} "
        f"{STANCE_ICONS.get(v['new_stance'], '❔')}{v['new_stance']}{veto_disp}   "
        f"{_progress_bar(n_roles)} ({n_roles}/{r2_threshold})"
    )
    _log(f"ENFORCER R2: {v['role']} [{v['r1_stance']}→{v['new_stance']} {v['stance_change']} "
         f"veto={v['veto']} veto_changed={int(v['veto_changed'])}] [{n_roles}/{r2_threshold}] mode={mode}")

    if n_roles != r2_threshold:
        return {"hook_decision": {}, "telegram": [tg_msg], "post_actions": []}

    # R2 완료 → R3 필요 여부 판단
    artifacts_dir = os.path.dirname(file_path) or "."
    decision = _decide_r3(artifacts_dir, hyp_id, mode)

    if decision["skip"]:
        write_state(state_file, hyp_id, "VERDICT_READY")
        tg_summary = _telegram_r2_summary(artifacts_dir, hyp_id)
        _log(f"ENFORCER v55: R3 SKIP (mode={mode}, stance={decision['stance']}, tier={decision['tier']})")
        if mode == "compact":
            ctx = (
                f"[S0 Debate Enforcer v55] R2 3/3 Compact 완료. stance 만장일치({decision['stance']}) "
                f"+ veto 무변동 → R3 생략 (consensus_tier: {decision['tier']}).\\n"
                "VERDICT를 v55 스키마로 작성하세요:\\n"
                "- transcript.rounds (R1, R2 2라운드+)\\n"
                "- final_stances (각 role별 r1/final/stance_change/veto_flag)\\n"
                "- consensus_tally (approve/approve_conditional/revise/reject/veto_count, 합 = 3)\\n"
                "- consensus_tier (UNANIMOUS/MAJORITY/MINORITY/DEADLOCK)\\n"
                "- consensus_points + unresolved_disputes\\n"
                "- debaters 배열 (3건)\\n"
                "- 점수(total_score/final_scores) 폐기"
            )
        else:
            ctx = (
                f"[S0 Debate Enforcer v55] R2 {r2_threshold}/{r2_threshold} 완료. "
                "전원 stance UNCHANGED + veto 변동 0 → R3 불필요.\\n"
                "VERDICT를 v55 스키마로 작성하세요:\\n"
                "- transcript.rounds (R1, R2 2라운드+)\\n"
                "- final_stances (각 role별 r1/final/stance_change/veto_flag)\\n"
                f"- consensus_tally (합 = {r2_threshold})\\n"
                "- consensus_tier\\n"
                "- consensus_points + unresolved_disputes\\n"
                f"- debaters 배열 ({r2_threshold}건)\\n"
                "- 점수제 폐기"
            )
        return {"hook_decision": _hook_context(ctx), "telegram": [tg_msg, tg_summary], "post_actions": []}

    # R3 필요
    write_state(state_file, hyp_id, "R3_NEEDED", r3_needed_roles=decision["roles"])
    r3_check = ",".join(decision["roles"]) if decision["roles"] else "NONE"
    tg_r3 = (f"🔄 [S0 Debate v55] {hyp_id} — R3 필요\n\n"
             f"stance/veto 변동 role: {r3_check}\nR3 Closing 재소환 후 최종 확정.")
    _log(f"ENFORCER v55: R3 NEEDED roles={r3_check}")
    ctx = (
        f"[S0 Debate Enforcer v55] R2 {r2_threshold}/{r2_threshold} 완료. "
        f"stance_change != UNCHANGED 또는 veto 변동 발생 role: {r3_check}\\n"
        "R3 Closing: 해당 role만 재소환하여 final_stance + final_veto_flag + closing_statement(150자+) 확정.\\n"
        f"출력: stage_artifacts/s0_debate_r3_{{role}}_{hyp_id}.json"
    )
    return {"hook_decision": _hook_context(ctx), "telegram": [tg_msg, tg_r3], "post_actions": []}


def handle_r3(hyp_id: str, state_file: str, file_path: str, content: str) -> dict:
    cur = read_state(state_file)
    if cur != "R3_NEEDED":
        return block(f"[S0 Debate Enforcer] R3는 R3_NEEDED 상태에서만 허용. 현재: {cur}")

    try:
        d = json.loads(content)
        role = d.get("role", "unknown")
    except Exception:
        role = "unknown"
    add_role(state_file, "r3", role)

    # 남은 R3 대상 계산
    with open(state_file) as f:
        st = json.load(f)
    r3_done = st.get("r3_roles", [])
    if "r3_needed_roles" not in st:
        # fallback: r2 파일에서 재계산
        artifacts_dir = os.path.dirname(file_path) or "."
        needed = []
        for f in glob.glob(os.path.join(artifacts_dir, f"s0_debate_r2_*_{hyp_id}.json")):
            try:
                with open(f) as fh:
                    dd = json.load(fh)
            except Exception:
                continue
            stance_change = str(dd.get("stance_change", "")).upper()
            r1_veto = dd.get("r1_veto_flag") or dd.get("veto_flag_r1")
            r2_veto = dd.get("veto_flag")
            r1v = str(r1_veto).lower() not in ("", "none", "null", "false")
            r2v = str(r2_veto).lower() not in ("", "none", "null", "false")
            veto_changed = (r1v != r2v) or (r1v and r2v and str(r1_veto).lower() != str(r2_veto).lower())
            if stance_change != "UNCHANGED" or veto_changed:
                needed.append(dd.get("role", "?"))
        st["r3_needed_roles"] = needed
        with open(state_file, "w") as f:
            json.dump(st, f, indent=2)

    needed_all = st.get("r3_needed_roles", [])
    remaining = [r for r in needed_all if r not in r3_done]
    n_remaining = len(remaining)

    tg_msg = f"🔄 [S0 Debate] {hyp_id} — R3 {role} 최종 확정"
    _log(f"ENFORCER R3: {role} 제출, 남은 대상 수={n_remaining}")

    if n_remaining > 0:
        write_state(state_file, hyp_id, "R3_NEEDED")
        _log(f"ENFORCER R3: R3_NEEDED 유지 (남은 {n_remaining} 인)")
        ctx = f"[S0 Debate Enforcer] R3 {role} 완료. 아직 {n_remaining}명 R3 미제출. R3_NEEDED 상태 유지."
        return {"hook_decision": _hook_context(ctx), "telegram": [tg_msg], "post_actions": []}

    write_state(state_file, hyp_id, "VERDICT_READY")
    _log("ENFORCER R3: 전원 완료 → VERDICT_READY")
    tg_done = f"✅ [S0 Debate] {hyp_id} — R3 전원 완료\n⚖️ VERDICT 작성 가능"
    ctx = "[S0 Debate Enforcer] R3 전원 완료. VERDICT 작성하세요."
    return {"hook_decision": _hook_context(ctx), "telegram": [tg_msg, tg_done], "post_actions": []}


def handle_verdict(hyp_id: str, state_file: str, _file_path: str, content: str,
                   project_root: str) -> dict:
    cur = read_state(state_file)
    if cur not in ("VERDICT_READY", "DONE"):
        _log(f"ENFORCER BLOCK VERDICT: state={cur}")
        guide = "R2까지 완료해야 VERDICT 작성 가능합니다."
        if cur == "IDLE":
            guide = "토론이 시작되지 않았습니다. /s0-debate로 R1부터 시작하세요."
        elif cur == "R1_IN_PROGRESS":
            guide = "R1이 아직 진행 중입니다 (5/5 미완료)."
        elif cur == "R1_COMPLETE":
            guide = "R2 Rebuttal이 아직 실행되지 않았습니다."
        elif cur == "R2_IN_PROGRESS":
            guide = "R2가 아직 진행 중입니다 (5/5 미완료)."
        elif cur == "R3_NEEDED":
            guide = "R3 Closing이 필요한 에이전트가 있습니다."
        return block(f"[S0 Debate Enforcer] 토론 미완료 상태({cur})에서 VERDICT 작성 불가. {guide}")

    codex_r2_path = os.path.join(project_root, f"stage_artifacts/r2_codex_verdict_{hyp_id}.json")
    if not os.path.exists(codex_r2_path) and os.environ.get("QVEST_SKIP_CODEX_R2", "0") != "1":
        _log(f"ENFORCER BLOCK VERDICT: codex R2 verdict missing ({hyp_id})")
        return block(
            f"[S2.13 Codex R2 Guard] VERDICT 작성 차단 ({hyp_id}): "
            f"stage_artifacts/r2_codex_verdict_{hyp_id}.json 미생성. "
            "Codex R2 Verify가 아직 진행 중이거나 실패했습니다. "
            "/tmp/codex_critic_r2_stderr.log 확인 후 재시도하거나 QVEST_SKIP_CODEX_R2=1로 우회하세요."
        )

    mode = debate_mode(hyp_id)
    v = _validate_verdict(content, mode)
    if not v["ok"]:
        _log(f"ENFORCER BLOCK VERDICT: {v['error']}")
        return block(
            f"[S0 Debate Enforcer v55] VERDICT 검증 실패: {v['error']}\\n\\n"
            "v55 VERDICT 필수 필드: hypothesis_id, verdict, consensus_tier, "
            "consensus_tally{approve, approve_conditional, revise, reject, veto_count}, "
            "transcript.rounds, final_stances{role: {r1, final, stance_change, veto_flag}}, "
            "debaters[{role, stance, veto_flag}], consensus_points[], unresolved_disputes[]\\n"
            "점수제(total_score/final_scores) 폐기. SKILL.md Verdict 섹션 참조."
        )

    write_state(state_file, hyp_id, "DONE")
    vicon = VERDICT_ICONS.get(v["verdict"], "⚖️")
    tg_msg = (
        f"⚖️ [S0 Debate · {hyp_id}] VERDICT (v55)\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"{vicon} {v['verdict']}   (tier: {v['tier']})\n"
        f"📊 tally  ✅{v['a']}  🟡{v['c']}  🔄{v['rv']}  ❌{v['rj']}   🚫veto={v['veto_n']}\n\n"
        f"✅ 합의점\n{v['consensus']}\n\n"
        f"❓ 미해결\n{v['disputes']}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    _log(f"ENFORCER VERDICT v55: {hyp_id} {v['verdict']} tier={v['tier']} "
         f"tally=A{v['a']}/C{v['c']}/Rv{v['rv']}/Rj{v['rj']} veto={v['veto_n']}")
    return {"hook_decision": {}, "telegram": [tg_msg], "post_actions": []}


# ─── Main ──────────────────────────────────────────────────────────────

def main() -> int:
    if len(sys.argv) < 3:
        emit(passthrough())
        return 0
    dtype = sys.argv[1]
    hyp_id = sys.argv[2]
    state_file = f"/tmp/s0_debate_state_{hyp_id}.json"

    try:
        inp = json.load(sys.stdin)
    except Exception as e:
        _log(f"ENFORCER BAD INPUT: {e}")
        emit(passthrough())
        return 0

    tool_input = inp.get("tool_input", {}) if isinstance(inp, dict) else {}
    file_path = tool_input.get("file_path", "") or ""
    content = tool_input.get("content", "") or ""

    project_root = os.environ.get(
        "QVEST_PROJECT_ROOT",
        "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    )

    try:
        if dtype == "R1":
            result = handle_r1(hyp_id, state_file, file_path, content)
        elif dtype == "R2":
            result = handle_r2(hyp_id, state_file, file_path, content)
        elif dtype == "R3":
            result = handle_r3(hyp_id, state_file, file_path, content)
        elif dtype == "VERDICT":
            result = handle_verdict(hyp_id, state_file, file_path, content, project_root)
        else:
            result = passthrough()
    except Exception as e:
        _log(f"ENFORCER FATAL: {e}")
        result = passthrough()
    emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
