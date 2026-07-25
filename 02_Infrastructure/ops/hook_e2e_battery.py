#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""hook_e2e_battery.py — 등록 hook 한글 payload 전후 회귀 배터리 (v8.1.2 2026-06-11)

용도: hook 파서/이스케이프 패치 전후 동작 비교 (블록 1 + 통과 1 per hook).
각 케이스 검증: ① stdout이 valid JSON ② 기대 판정(block/deny/allow/context)
③ lone surrogate(0xD800-0xDFFF) 0개.

실행: PYTHONUTF8=1 python3 02_Infrastructure/ops/hook_e2e_battery.py
프로젝트 루트에서 실행 (hook 상대경로 전제).
"""
import datetime
import json
import os
import shutil
import subprocess
import sys

H = "02_Infrastructure/hooks"
# 프로젝트 상대경로 — native python과 MSYS bash가 같은 위치를 보도록 (/tmp는 양쪽 매핑이 다름)
TMP_WT = ".cache/_battery_wt"


def run_hook(hook, payload_obj, pre_shell=None):
    """payload를 stdin으로 hook 실행. pre_shell이 있으면 중간 bash에서 marker 셋업."""
    payload = json.dumps(payload_obj, ensure_ascii=False)
    if pre_shell:
        # agent_role_guard용: hook의 PPID = 중간 bash($$) 이므로 marker를 $$로 작성
        script = (
            pre_shell
            + '\nprintf "%s" "$BATTERY_PAYLOAD" | bash "$BATTERY_HOOK"\nrc=$?\n'
            + 'rm -f "/tmp/qvest_current_agent_$$"\nexit $rc\n'
        )
        p = subprocess.run(
            ["bash", "-c", script],
            env={**os.environ, "BATTERY_PAYLOAD": payload, "BATTERY_HOOK": f"{H}/{hook}"},
            capture_output=True,
        )
    else:
        p = subprocess.run(["bash", f"{H}/{hook}"], input=payload.encode("utf-8"), capture_output=True)
    return p.stdout.decode("utf-8", errors="replace").strip()


def judge(out, expect):
    """expect: 'block' | 'deny' | 'allow' | 'context'"""
    try:
        d = json.loads(out)
    except Exception:
        return False, f"INVALID_JSON: {out[:60]!r}"
    sur = sum(1 for ch in out if 0xD800 <= ord(ch) <= 0xDFFF)
    if sur:
        return False, f"SURROGATES={sur}"
    hso = d.get("hookSpecificOutput", {}) if isinstance(d, dict) else {}
    if expect == "block":
        ok = d.get("decision") == "block"
    elif expect == "deny":
        ok = hso.get("permissionDecision") == "deny"
    elif expect == "context":
        # hookSpecificOutput 채널(직접등록 훅) + top-level 단일키 채널(라우터 dispatch 훅) 양쪽 수용
        ok = bool(hso.get("additionalContext")) or bool(d.get("additionalContext"))
    else:  # allow
        ok = d == {} or (d.get("decision") in (None, "approve") and not hso.get("permissionDecision"))
    return ok, ("OK" if ok else f"UNEXPECTED: {out[:80]!r}")


def main():
    results = []

    def case(name, ok, note):
        results.append((name, ok, note))
        print(f"{'PASS' if ok else 'FAIL'} {name}: {note}")

    KR = "한글 내용 — 테스트용 메모입니다."

    # ── agent_role_guard: alpha가 risk_package 쓰기 = block / 자기 산출물 = allow
    pre = 'echo "alpha-research" > "/tmp/qvest_current_agent_$$"'
    out = run_hook("agent_role_guard.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-D20990101_001/risk_package.json", "content": KR}}, pre_shell=pre)
    case("agent_role_guard.block", *judge(out, "block"))
    out = run_hook("agent_role_guard.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-D20990101_001/alpha_scores_v1.parquet", "content": KR}}, pre_shell=pre)
    case("agent_role_guard.allow", *judge(out, "allow"))

    # ── worktask_constraint_enforcer: Σw=0.8 한글 필드 = block / Σw=1.0 = allow (개별 weight ≤0.20 준수)
    w8 = {f"A{i:06d}": 0.10 for i in range(8)}    # Σ=0.8 위반
    w10 = {f"A{i:06d}": 0.10 for i in range(10)}  # Σ=1.0 정상
    bad = json.dumps({"target_weights": w8, "메모": KR}, ensure_ascii=False)
    out = run_hook("worktask_constraint_enforcer.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-P20990101_001/optimization_package.json", "content": bad}})
    case("wt_constraint.block_sum08", *judge(out, "block"))
    good = json.dumps({"target_weights": w10, "메모": KR}, ensure_ascii=False)
    out = run_hook("worktask_constraint_enforcer.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-P20990101_001/optimization_package.json", "content": good}})
    case("wt_constraint.allow_sum10", *judge(out, "allow"))
    # 적대 케이스: valid JSON + triple-quote/backslash 포함 + Σw=0.5 위반 → 반드시 block
    # (구 heredoc 보간에선 python 소스가 깨져 ERR trap '{}' fail-open — 차등 검증 케이스)
    w5 = {f"A{i:06d}": 0.10 for i in range(5)}
    evil = json.dumps({"target_weights": w5, "note": "''' \\ 한글 인용"}, ensure_ascii=False)
    out = run_hook("worktask_constraint_enforcer.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-P20990101_001/optimization_package.json", "content": evil}})
    case("wt_constraint.block_evil_quotes", *judge(out, "block"))

    # ── codex_round_pre_enforcer: REMOVED v8.2 (Codex Critic Round 폐지 — self-adversarial in-agent)

    # ── telegram_direct_call_guard: tg_send 직접 = deny / tg_agent_brief = allow
    out = run_hook("telegram_direct_call_guard.sh", {"tool_name": "Bash", "tool_input": {
        "command": "Rscript -e 'source(\"02_Infrastructure/telegram/telegram_notify.R\"); tg_send(\"한글 알림\")'"}})
    case("tg_guard.deny_direct", *judge(out, "deny"))
    out = run_hook("telegram_direct_call_guard.sh", {"tool_name": "Bash", "tool_input": {
        "command": "Rscript -e 'tg_agent_brief(\"forge\",\"제목 한글\", sections)'"}})
    case("tg_guard.allow_brief", *judge(out, "allow"))

    # ── sr_provenance_pre_certifier: forge_package 필드 누락이어도 {} (안내만) / 비대상 {}
    out = run_hook("sr_provenance_pre_certifier.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-P20990101_001/forge_package.json",
        "content": json.dumps({"task_id": "x", "비고": KR}, ensure_ascii=False)}})
    case("sr_pre_cert.smoke_forge", *judge(out, "allow"))

    # ── axiom_context_inject: Agent spawn = additionalContext (한글 axiom 주입)
    out = run_hook("axiom_context_inject.sh", {"tool_name": "Agent", "tool_input": {
        "subagent_type": "alpha-search", "prompt": "테스트 한글 프롬프트"}})
    ok, note = judge(out, "context")
    if ok:
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        ok = "AX-000" in ctx
        note = f"OK (ctx {len(ctx)} chars, AX-000 {'present' if ok else 'MISSING'})"
    case("axiom_inject.context", ok, note)

    # ── milestone_commit: 비대상 경로 = {} 조기종료 (커밋 미발생 — full path는 실커밋이라 배터리 제외)
    out = run_hook("milestone_commit.sh", {"tool_name": "Write", "tool_input": {
        "file_path": "04_Research/not_a_milestone.txt", "content": KR}})
    case("milestone.early_exit", *judge(out, "allow"))
    # STMT 추출 스닉펫 동작 (한글 statement) — AX-008 실파일
    #   (2026-07-05) 구 AX-003은 Distilled 강등으로 active 제거 → 잔존 active Law 중 'statement' 필드 보유한 AX-008로 교체.
    ax = "qepm/memory/axioms/active/AX-008.json"
    if os.path.exists(ax):
        p = subprocess.run(["python3", "-c",
            "import json,sys\n"
            "try:\n"
            "    d=json.load(open(sys.argv[1], encoding='utf-8'))\n"
            "    print((d.get('statement') or '')[:80])\n"
            "except: print('')", ax], capture_output=True)
        stmt = p.stdout.decode("utf-8", errors="replace").strip()
        case("milestone.stmt_extract_kr", len(stmt) > 0, f"statement len={len(stmt)}")

    # ── ast_spec_gate: AST v1.1 스펙 게이트 (2026-07-25 S2d — SOT qvest_ast_v1_1_sot.md §7)
    #    block(mechanism 결측) / allow(정상 v1.1) / 구식 통과(advisory context) +
    #    ast_verify FAIL_LOOKAHEAD 픽스처(fx2 재무 당일참조) 1건.
    #    QVEST_AST_GATE_BATTERY=1 — registry 경보 append만 억제 (판정 동일).
    os.environ["QVEST_AST_GATE_BATTERY"] = "1"
    AP = "qepm/mailbox/worktask/WT-D20990101_001/alpha_package.json"
    ast_ok = {"op": "ADD", "children": [
        {"op": "CS_RANK", "children": [{"op": "TS_MEAN", "window": 231, "children": [
            {"op": "TS_LAG", "k": 21, "unit": "d", "children": [
                {"leaf": "FIELD", "group_id": "A1_RAWDATA_OHLCVS_daily", "field": "Ret"}]}]}]},
        {"leaf": "REGISTRY", "factor": "M08_Residual_Mom"}]}
    hyp_ok = {"mechanism": {"agent": "기관 수급 주체", "friction": "공매도 제약 하 가격반영 지연",
                            "path": "수급 지속 → 잔차모멘텀"},
              "falsification": [{"field": "M08_Residual_Mom", "observation": "잔차모멘텀 rank-IC 음전 시 기각"}],
              "regime_scope": {"weakens_or_reverses_in": ["crisis"]}}
    pit_ok = {"sig_date": "2026-05-31", "decision_ts": "2026-06-01"}

    def ap_payload(pkg):
        return {"tool_name": "Write", "tool_input": {
            "file_path": AP, "content": json.dumps(pkg, ensure_ascii=False)}}

    # block 1 — v1.1 mechanism 결측
    out = run_hook("ast_spec_gate.sh", ap_payload({
        "spec_version": "ast_v1.1", "strategy_id": "BATTERY_NOMECH",
        "hypothesis": {"falsification": hyp_ok["falsification"],
                       "regime_scope": hyp_ok["regime_scope"]},
        "pit": pit_ok, "ast": ast_ok}))
    case("ast_spec_gate.block_no_mechanism", *judge(out, "block"))

    # allow — 정상 v1.1 (mechanism 3필드 + falsification field_dictionary 내 + regime + 𝒪 내 + verify PASS)
    out = run_hook("ast_spec_gate.sh", ap_payload({
        "spec_version": "ast_v1.1", "strategy_id": "BATTERY_V11_PASS",
        "hypothesis": hyp_ok, "pit": pit_ok, "ast": ast_ok}))
    case("ast_spec_gate.allow_v11_clean", *judge(out, "allow"))

    # 구식(spec_version 부재) — 통과 + advisory additionalContext (v1.1 전환 권고)
    out = run_hook("ast_spec_gate.sh", ap_payload({
        "strategy_id": "BATTERY_LEGACY", "diagnostics": {"메모": KR}}))
    case("ast_spec_gate.context_legacy_pass", *judge(out, "context"))

    # block 2 — ast_verify FAIL_LOOKAHEAD 픽스처 (fx2 재무 당일참조 AST 재사용 — 사고2 계열)
    fx2_path = "02_Infrastructure/ast/tests/fixtures/fx2_fund_sameday_fail.json"
    with open(fx2_path, encoding="utf-8") as f:
        fx2 = json.load(f)
    out = run_hook("ast_spec_gate.sh", ap_payload({
        "spec_version": "ast_v1.1", "strategy_id": "BATTERY_LOOKAHEAD",
        "hypothesis": hyp_ok, "pit": fx2["pit"], "ast": fx2["ast"]}))
    ok, note = judge(out, "block")
    if ok:
        ok = "FAIL_LOOKAHEAD" in out
        note = "OK" if ok else f"block인데 FAIL_LOOKAHEAD 사유 아님: {out[:80]!r}"
    case("ast_spec_gate.block_verify_lookahead", ok, note)
    os.environ.pop("QVEST_AST_GATE_BATTERY", None)

    shutil.rmtree(TMP_WT, ignore_errors=True)
    n_fail = sum(1 for _, ok, _ in results if not ok)
    print(f"\nRESULT: {len(results) - n_fail}/{len(results)} PASS" + (f" ({n_fail} FAIL)" if n_fail else ""))
    # (2026-07-17 B3) 결과 영속화 — print 전용이라 부트/감사가 최근 배터리 상태를 소급 확인 못 하던 갭.
    #   stdout 계약 불변 · 기록 실패는 배터리 판정에 불계상 (fail-soft).
    try:
        os.makedirs(".cache", exist_ok=True)
        with open(".cache/hook_e2e_battery_latest.json", "w", encoding="utf-8") as f:
            json.dump({
                "ran_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "cases": [{"name": name, "result": "PASS" if ok else "FAIL"} for name, ok, _ in results],
                "n_pass": len(results) - n_fail,
                "n_fail": n_fail,
            }, f, ensure_ascii=False, indent=2)
    except OSError as e:
        print(f"WARN: hook_e2e_battery_latest.json 기록 실패 ({e}) — 판정 불계상")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
