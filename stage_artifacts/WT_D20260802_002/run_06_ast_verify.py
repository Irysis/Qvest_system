# run_06_ast_verify.py — factors[].ast 각각을 ast_verify 에 태워 판정 수집.
# 왜 wrapper 인가: ast_spec_gate.sh 는 2026-08-02 ALB-006 수리로 extract_asts(factors[] 포함)를
# 갖췄으나, 같은 날 수리가 ast_verify.py 의 CLI 진입점(extract_ast, 627행)에는 적용되지 않아
# **CLI 로 직접 검증하면 factors[] 표현이 FAIL_CONTRACT(ast 노드 부재) 로 떨어진다**.
# 여기서는 게이트와 동일한 수집 규칙을 재현해 팩터별 판정을 받는다(패키지 변형 없음).
import json, io, os, sys, subprocess, tempfile
QM = r"C:\Users\99922\OneDrive\Quant_Module_Moltbot"
PKG = os.path.join(QM, "qepm", "mailbox", "worktask", "WT-D20260802_002", "alpha_package.json")
OUT = os.path.join(QM, "stage_artifacts", "WT_D20260802_002", "ast_verify_verdict.json")
pkg = json.load(io.open(PKG, encoding="utf-8"))

roots = []
for holder in (pkg, pkg.get("factor_definition") or {}, pkg.get("spec") or {}):
    if isinstance(holder, dict) and isinstance(holder.get("ast"), dict):
        roots.append(("top_level", holder["ast"]))
for f in (pkg.get("factors") or []):
    if isinstance(f, dict) and isinstance(f.get("ast"), dict):
        roots.append((f.get("factor_id", "unnamed"), f["ast"]))

if not roots:
    sys.exit("no ast roots found")

results = []
for fid, ast in roots:
    shim = {k: pkg[k] for k in ("task_id", "as_of_date", "pit") if k in pkg}
    shim["ast"] = ast
    shim["strategy_id"] = "FQ084_" + str(fid)
    tf = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
    json.dump(shim, tf, ensure_ascii=False)
    tf.close()
    p = subprocess.run([sys.executable, os.path.join(QM, "02_Infrastructure", "ast", "ast_verify.py"), tf.name],
                       capture_output=True, text=True, encoding="utf-8")
    os.unlink(tf.name)
    try:
        v = json.loads(p.stdout)
    except Exception:
        v = {"verdict": "RUNNER_ERROR", "stdout": p.stdout[-2000:], "stderr": p.stderr[-2000:]}
    v["factor_id"] = fid
    results.append(v)
    print("[%s] verdict=%s  restatement_leaves=%d  violations=%d  contract_failures=%d"
          % (fid, v.get("verdict"), len(v.get("restatement_leaves") or []),
             len(v.get("violations") or []), len(v.get("contract_failures") or [])))
    for r in (v.get("restatement_leaves") or []):
        print("    restatement:", json.dumps(r, ensure_ascii=False)[:300])
    for r in (v.get("contract_failures") or []):
        print("    contract_fail:", json.dumps(r, ensure_ascii=False)[:300])
    for r in (v.get("violations") or []):
        print("    violation:", json.dumps(r, ensure_ascii=False)[:300])

order = {"FAIL_LOOKAHEAD": 0, "FAIL_CONTRACT": 1, "WARN_RESTATEMENT": 2, "PASS": 3}
overall = min((r.get("verdict", "FAIL_CONTRACT") for r in results), key=lambda v: order.get(v, 1))
agg = {"schema": "ast_verify_multifactor/v1", "package": PKG, "overall_verdict": overall,
       "n_ast_roots": len(results), "per_factor": results,
       "wrapper_rationale": ("ast_verify.py CLI extract_ast(627행)는 factors[] 를 보지 않는다 — "
                             "ast_spec_gate.sh 의 ALB-006 수리(extract_asts)가 CLI 진입점에 미반영. "
                             "본 wrapper 는 게이트와 동일 수집 규칙을 재현할 뿐 패키지를 변형하지 않는다.")}
with io.open(OUT, "w", encoding="utf-8") as f:
    json.dump(agg, f, ensure_ascii=False, indent=2)
print("\n[OVERALL] %s  -> %s" % (overall, OUT))
