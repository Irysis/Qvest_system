#!/usr/bin/env python3
# =============================================================================
# rf_preaudit.py — 충실구현 **측정 전 기계 사전검사** (declaration gate · 2026-10-05 도훈 지시
#   "반복 감사 지적의 기계 검사화 진행해줘. 빠른 리서치 중요해")
#
# ★왜: 적대적 충실도 감사(rf_fidelity_fanout → rf_fidelity_merge.R)는 6축 중 **한 축이라도** 근거 있는
#   미신고 1건을 내면 misdeclared → 전체 재구현이다(merge.R:85). 09-01 이후 26편 중 20편이 1패스로 안 끝났고
#   패스 1회 = 에이전트 + 측정(5~20분) + 감사(7~17분). 그중 **논문을 안 읽고도 잡히는 유형**은 감사까지 갈 이유가 없다.
#   이 검사기는 engine.R · FIDELITY.json · 팩터 등록부만 읽어 그 유형을 몇 초 안에 잡는다.
#
# ★무엇을 안 하나: 논문 판독(L 유형 — 창 종점이 논문과 맞는지, 전처리 단계가 논문에 있는지)은 못 한다.
#   대신 구현자가 그것을 **구조 필드로 적었는지**(paper_steps · windows · factor_mapping)만 본다 — 내용의 참거짓은
#   여전히 LLM 감사의 몫이다. 이 검사기는 감사를 대체하지 않고, 감사가 확실히 기각할 형태를 앞에서 거른다.
#
# ★청정성: 측정 산출물·성과 파일을 **읽지 않는다**(입력 = 작업 디렉터리의 engine.R·FIDELITY.json + 등록부).
#   그래서 이 보고가 재구현 피드백(FAILFB · failure=declaration_gate)으로 실려도 청정 판독을 깨지 않는다.
#
# 규칙(정규식·키워드·필수 키)은 06_Registry/rf_preaudit.json 이 정본이다 — 코드에 목록을 들고 있지 않는다.
#
# 사용:
#   rf_preaudit.py --wdir <WDIR> --root <ROOT> [--cfg <rf_preaudit.json>] [--out <report.json>] [--feedback-out <txt>]
# 종료 코드: 0 = pass · 1 = findings(fail 등급 ≥1) · 3 = 검사 불능(입력·설정 파손 — 호출자는 fail-open 으로 통과시킨다)
# 검사 = 08_Tests/ops/test_rf_preaudit.py (양성·음성·돌연변이 대조)
# =============================================================================
import argparse
import difflib
import io
import json
import os
import re
import shutil
import sys
import time

EXIT_PASS, EXIT_FINDINGS, EXIT_ERROR = 0, 1, 3


def _load_json(p):
    return json.loads(io.open(p, "rb").read().decode("utf-8-sig"))


def strip_r_comments(src):
    """R 소스에서 주석(# … 줄끝)을 지운다 — 문자열 안의 # 는 남긴다. 줄 수는 보존(줄 번호 보고용)."""
    out_lines = []
    for line in src.split("\n"):
        buf, q, esc = [], None, False
        for ch in line:
            if q:
                buf.append(ch)
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == q:
                    q = None
                continue
            if ch in ("'", '"', "`"):
                q = ch
                buf.append(ch)
                continue
            if ch == "#":
                break
            buf.append(ch)
        out_lines.append("".join(buf))
    return "\n".join(out_lines)


def _lines_matching(code_lines, rx):
    hits = []
    for i, ln in enumerate(code_lines, 1):
        if rx.search(ln):
            hits.append(i)
    return hits


# 신고 말뭉치에 넣는 필드 — **구현자 자신의 서술만**. 등록부 정의 원문(registry_definition)·논문 인용(paper_quote)·
#   논문 명세(windows.paper)는 넣지 않는다: 외부 문장의 단어('market cap' 등)가 신고 키워드로 오인돼 미신고를 가린다
#   (2026-10-05 검사 M1 실측 — 등록부 정의가 섞인 말뭉치에서 undeclared clip 이 통과했다).
_DECL_FIELDS = {"paper_steps": ("step", "note"), "windows": ("name", "impl"), "factor_mapping": ("factor_id", "deviation"),
                "constants": ("name", "note")}


def _decl_corpus(fid):
    """신고 말뭉치 — changed · changed_items · 구조 필드 중 구현자 서술 하위 필드(소문자). 키워드 대조용."""
    parts = []

    def walk(o):
        if isinstance(o, str):
            parts.append(o)
        elif isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    for k in ("changed", "changed_items"):
        walk(fid.get(k))
    for k, sub in _DECL_FIELDS.items():
        items = fid.get(k)
        if isinstance(items, list):
            for it in items:
                if isinstance(it, dict):
                    for s in sub:
                        walk(it.get(s))
    return "\n".join(parts).lower()


def _norm(s):
    return re.sub(r"\s+", " ", str(s or "")).strip().lower()


def _r_num(s):
    """R 숫자 리터럴(12L · 1e-3 · '20') → float. 숫자가 아니면 None(c(…)·as.Date(…) 는 문자열 대조로 간다)."""
    try:
        return float(str(s).strip().rstrip("L"))
    except ValueError:
        return None


def harness_block(root, cfg):
    """하네스 공시 블록(프롬프트 절) — 체결 규약은 하네스 설정에서 그때 읽는다(하네스가 바뀌면 블록도 따라 바뀐다).
    반환 = (프롬프트 절 텍스트, exec_price). 설정·규약 판독 불능이면 예외(호출자는 블록 없이 진행한다)."""
    H = cfg.get("harness") or {}
    ec = _load_json(os.path.join(root, H.get("exec_config") or "02_Infrastructure/worktask/constraint_defaults.json"))
    node = ec
    for k in (H.get("exec_key") or "execution.exec_price").split("."):
        node = node.get(k) if isinstance(node, dict) else None
    ep = str(node or "")
    st = (H.get("exec_statements") or {}).get(ep)
    if not st:
        raise RuntimeError("체결 규약 %r 의 공시 문장이 설정에 없다 — 블록을 지어내지 않는다" % ep)
    body = [H.get("marker") or "[HARNESS-DISCLOSURE v1]"]
    for ln in H.get("lines") or []:
        body.append("- " + ln.replace("{exec_statement}", st))
    body.append(H.get("end_marker") or "[/HARNESS-DISCLOSURE]")
    head = (H.get("prompt_head") or "## 하네스 고지") + " · exec=" + ep
    return "\n".join([head, H.get("prompt_guide") or "", ""] + body), ep


def run(wdir, root, cfg):
    F = []   # findings
    stats = {}

    def add(code, sev, title, detail, lines=None):
        F.append({"code": code, "severity": sev, "title": title, "detail": detail,
                  "lines": (lines or [])[:12]})

    eng_p = os.path.join(wdir, "engine.R")
    fid_p = os.path.join(wdir, "FIDELITY.json")
    if not os.path.isfile(eng_p):
        raise RuntimeError("engine.R 없음: %s" % eng_p)
    src = io.open(eng_p, "rb").read().decode("utf-8", "replace")
    code = strip_r_comments(src)
    code_lines = code.split("\n")
    stats["engine_lines"] = len(code_lines)

    # ── P1 FIDELITY 파싱·필수 키 ─────────────────────────────────────────────
    fid = None
    if not os.path.isfile(fid_p):
        add("P1_fidelity_missing", "fail", "FIDELITY.json 이 없다",
            "산출은 engine.R 과 FIDELITY.json 둘이다 — 신고 없는 엔진은 감사에서 전건 미신고가 된다.")
        fid = {}
    else:
        try:
            fid = _load_json(fid_p)
            if not isinstance(fid, dict):
                raise ValueError("최상위가 객체가 아니다")
        except Exception as e:
            add("P1_fidelity_unparsable", "fail", "FIDELITY.json 파싱 불가", str(e)[:200])
            fid = {}
    for k in cfg.get("required_keys") or []:
        if k not in fid:
            add("P1_key_missing", "fail", "FIDELITY 필수 키 누락: %s" % k,
                "키가 아예 없다(값이 null 이어도 되는 키는 null 로 적어라 — 예: commission_paper).")
    corpus = _decl_corpus(fid)

    # ── 엔진이 참조하는 등록부 지표(따옴표 리터럴 = 등록부 키 정확 일치) ───────────────────────────
    reg_rel = (cfg.get("factor_ref") or {}).get("registry") or "02_Infrastructure/factor_db/factor_registry.json"
    reg = {}
    try:
        reg = _load_json(os.path.join(root, reg_rel))
    except Exception as e:
        stats["registry_error"] = str(e)[:160]
    lit_rx = re.compile((cfg.get("factor_ref") or {}).get("literal_regex") or r"[\"']([A-Za-z0-9_]+)[\"']")
    used, used_lines = [], {}
    for i, ln in enumerate(code_lines, 1):
        for m in lit_rx.finditer(ln):
            fac_id = m.group(1)
            if fac_id in reg and isinstance(reg.get(fac_id), dict):
                if fac_id not in used_lines:
                    used.append(fac_id)
                    used_lines[fac_id] = []
                used_lines[fac_id].append(i)
    stats["registry_factors_used"] = len(used)

    # ── P2 factor_mapping 구조·포괄 ────────────────────────────────────────
    S = cfg.get("structured") or {}
    fm_cfg = S.get("factor_mapping") or {}
    fm = fid.get("factor_mapping")
    if used:
        if not isinstance(fm, list) or not fm:
            add("P2_factor_mapping_missing", "fail",
                "팩터 DB 지표 %d개를 쓰는데 factor_mapping 이 없다" % len(used),
                "지표마다 {factor_id, paper_item, registry_definition, deviation} 을 적어라. "
                "등록부 정의(창 길이·skip·half-life·중성화·부호)와 논문 정의의 차이가 감사의 단골 지적이다. "
                "쓰는 지표: " + ", ".join(used[:40]))
        else:
            mapped = {}
            for it in fm:
                if isinstance(it, dict) and it.get("factor_id"):
                    mapped[str(it.get("factor_id"))] = it
            miss = [u for u in used if u not in mapped]
            if miss:
                add("P2_factor_unmapped", "fail",
                    "엔진이 쓰는데 factor_mapping 에 없는 지표 %d개" % len(miss),
                    "다음 지표의 논문 대응·등록부 정의·차이를 적어라: " + ", ".join(miss[:40]),
                    [used_lines[m][0] for m in miss[:12]])
            req_fields = fm_cfg.get("required_fields") or ["factor_id", "paper_item", "registry_definition", "deviation"]
            thin = []
            for u in used:
                it = mapped.get(u)
                if not it:
                    continue
                empt = [f for f in req_fields if not str(it.get(f) or "").strip()]
                if empt:
                    thin.append("%s(%s)" % (u, "/".join(empt)))
            if thin:
                add("P2_factor_mapping_thin", "fail", "factor_mapping 항목의 빈 필드 %d건" % len(thin),
                    "빈 필드를 채워라(차이가 없으면 deviation 에 'none — 등록부 정의와 논문 정의가 같다' 라고 적는다): "
                    + ", ".join(thin[:30]))
            # ★읽었다는 증거 — registry_definition 이 등록부 definition 과 다르면(의역·지어냄) 경고.
            thr = float(fm_cfg.get("definition_similarity_min") or 0.6)
            off = []
            for u in used:
                it = mapped.get(u)
                if not it or not str(it.get("registry_definition") or "").strip():
                    continue
                truth = _norm((reg.get(u) or {}).get("definition"))
                if not truth:
                    continue
                r = difflib.SequenceMatcher(None, _norm(it.get("registry_definition")), truth).ratio()
                if r < thr:
                    off.append("%s(유사도 %.2f)" % (u, r))
            if off:
                add("P2_registry_definition_mismatch", fm_cfg.get("definition_mismatch_severity") or "warn",
                    "registry_definition 이 등록부 정의와 다르다 %d건" % len(off),
                    "등록부(design_view 사본)의 definition 문장을 그대로 옮기고 그 아래 deviation 에 논문과의 차이를 적어라: "
                    + ", ".join(off[:20]))

    # ── P3 등록부 중복 군집(DUPC) 동시 사용 ──────────────────────────────────
    clusters = {}
    for u in used:
        dd = (reg.get(u) or {}).get("dedup") or {}
        cl = dd.get("cluster")
        if cl:
            clusters.setdefault(cl, []).append(u)
    for cl, members in clusters.items():
        if len(members) >= 2 and cl.lower() not in corpus:
            add("P3_duplicate_cluster", "fail",
                "등록부 중복 군집 %s 의 지표를 %d개 함께 쓴다: %s" % (cl, len(members), ", ".join(members)),
                "등록부가 팩터 DB 값 기준으로 사실상 같은 신호(같은 값의 별칭 — 부호 사전이 반대일 수도 있다 — 또는 "
                "|상관|≥0.99)로 판정한 지표들이라 함께 쓰면 그 신호에 가중이 겹친다. 하나만 쓰거나, 논문도 같은 변환을 "
                "별개 지표로 두었다면(예: 시총·로그시총) 그 대응을 factor_mapping 에 적고 changed 에 군집 id(%s)를 남겨라." % cl,
                [used_lines[m][0] for m in members])

    # ── P4 논문 절차 단계(paper_steps) ──────────────────────────────────────
    ps_cfg = S.get("paper_steps") or {}
    ps = fid.get("paper_steps")
    if ps_cfg.get("required", True):
        if not isinstance(ps, list) or not ps:
            add("P4_paper_steps_missing", "fail", "paper_steps 가 없다",
                "논문이 서술한 절차 단계 전부(표본·전처리·결측·이상치·표준화·중성화·신호·정렬·분할·가중·리밸·비용)를 "
                "{step, paper_quote, status(implemented|changed|omitted), note} 로 적어라. "
                "감사의 단골 기각 사유가 '논문에 있는 단계를 구현도 신고도 안 했다' 이다.")
        else:
            ok_status = set(ps_cfg.get("status_enum") or ["implemented", "changed", "omitted"])
            bad = []
            for j, it in enumerate(ps, 1):
                if not isinstance(it, dict):
                    bad.append("#%d(객체 아님)" % j)
                    continue
                st = str(it.get("status") or "").strip().lower()
                if st not in ok_status:
                    bad.append("#%d(status=%s)" % (j, st or "빈칸"))
                elif not str(it.get("paper_quote") or "").strip():
                    bad.append("#%d(paper_quote 빈칸)" % j)
                elif st in ("changed", "omitted") and not str(it.get("note") or "").strip():
                    bad.append("#%d(%s 인데 note 빈칸)" % (j, st))
            if bad:
                add("P4_paper_steps_malformed", "fail", "paper_steps 항목 형식 위반 %d건" % len(bad),
                    "status 는 implemented|changed|omitted 중 하나, paper_quote 는 원문 짧은 인용, "
                    "changed/omitted 는 note 필수: " + ", ".join(bad[:20]))
            min_n = int(ps_cfg.get("min_items") or 0)
            if min_n and isinstance(ps, list) and len(ps) < min_n:
                add("P4_paper_steps_few", ps_cfg.get("few_severity") or "warn",
                    "paper_steps 가 %d개뿐이다(권장 ≥%d)" % (len(ps), min_n),
                    "논문 절차를 단계 단위로 쪼개 적어라 — 한 줄 요약은 감사가 대조할 수 없다.")

    # ── P5 창(windows) ──────────────────────────────────────────────────
    w_cfg = S.get("windows") or {}
    w_rx = [re.compile(r) for r in (cfg.get("window_code_regex") or [])]
    w_lines = sorted({i for rx in w_rx for i in _lines_matching(code_lines, rx)})
    stats["window_construct_lines"] = len(w_lines)
    wl = fid.get("windows")
    if w_lines:
        if not isinstance(wl, list) or not wl:
            add("P5_windows_missing", "fail",
                "엔진에 롤링·트레일링 창 구문이 %d줄 있는데 windows 가 없다" % len(w_lines),
                "창마다 {name, paper, impl} 을 적어라 — paper/impl 둘 다 **종점까지**(예: [t-12, t-1] · 당월 포함 여부). "
                "창 종점이 논문과 한 칸 어긋나는 것이 반복 지적이다.", w_lines)
        else:
            end_rx = re.compile(w_cfg.get("endpoint_regex") or r"t\s*[-−]\s*\d|\bt\b|당월|결정월|signal|sig|\[|\(")
            bad = []
            for j, it in enumerate(wl, 1):
                if not isinstance(it, dict):
                    bad.append("#%d(객체 아님)" % j)
                    continue
                if not str(it.get("paper") or "").strip() or not str(it.get("impl") or "").strip():
                    bad.append("#%d(paper/impl 빈칸)" % j)
                elif not end_rx.search(str(it.get("impl"))):
                    bad.append("#%d(impl 에 종점 표기 없음)" % j)
            if bad:
                add("P5_windows_malformed", "fail", "windows 항목 형식 위반 %d건" % len(bad),
                    "paper·impl 를 모두 적고 impl 에 종점(t-1 · 당월 포함 등)을 명시하라: " + ", ".join(bad[:20]))

    # ── P7 최상위 숫자 상수표(constants) — 감사 실측 최다 유형 GUARD(26건 · 엔진당 미신고 상수 중앙 18개) ─────────────
    #   이름 <- 숫자 리터럴(또는 c(숫자…) · as.Date("…")) 인 **최상위** 대입만 센다. 이름이 constants 에 없으면 미신고,
    #   value 가 코드 값과 다르면 자기 서술 오류(DECL_SELF 유형 — 신고가 사실과 다름)다.
    c_cfg = S.get("constants") or {}
    if c_cfg.get("required_when", "engine_has_top_level_numeric_constant"):
        crx = re.compile(c_cfg.get("assign_regex") or
                         r"^([A-Za-z_.][A-Za-z0-9_.]*)\s*(?:<-|=)\s*(-?[0-9][0-9.]*(?:[eE][+-]?[0-9]+)?L?|c\([-0-9.eEL, +]+\)|as\.Date\(\s*['\"][0-9-]+['\"]\s*\))\s*;?\s*$")
        top = []
        for i, ln in enumerate(code_lines, 1):
            m = crx.match(ln)
            if m:
                top.append((m.group(1), m.group(2), i))
        stats["top_level_constants"] = len(top)
        if top:
            cl = fid.get("constants")
            if not isinstance(cl, list) or not cl:
                add("P7_constants_missing", "fail",
                    "엔진 최상위 숫자 상수 %d개가 있는데 constants 가 없다" % len(top),
                    "상수마다 {name, value, source(paper|supplement|harness), note} 를 적어라 — 논문 값인지 보충값인지가 "
                    "감사가 가장 많이 묻는 것이다. 상수: " + ", ".join("%s=%s" % (n, v) for n, v, _ in top[:30]),
                    [i for _, _, i in top])
            else:
                decl = {}
                for it in cl:
                    if isinstance(it, dict) and it.get("name"):
                        decl[str(it.get("name"))] = it
                miss = [(n, v, i) for n, v, i in top if n not in decl]
                if miss:
                    add("P7_constants_undeclared", "fail", "constants 에 없는 최상위 상수 %d개" % len(miss),
                        "다음 상수의 값·출처(paper|supplement|harness)·근거를 적어라: "
                        + ", ".join("%s=%s" % (n, v) for n, v, _ in miss[:30]), [i for _, _, i in miss])
                ok_src = set(c_cfg.get("source_enum") or ["paper", "supplement", "harness"])
                bad_src, bad_val = [], []
                for n, v, i in top:
                    it = decl.get(n)
                    if not it:
                        continue
                    if str(it.get("source") or "").strip().lower() not in ok_src:
                        bad_src.append(n)
                    cv, dv = _r_num(v), _r_num(it.get("value"))
                    if cv is not None and dv is not None and abs(cv - dv) > 1e-12 * max(1.0, abs(cv)):
                        bad_val.append("%s(코드 %s · 신고 %s)" % (n, v, it.get("value")))
                    elif cv is None and _norm(v).replace(" ", "") != _norm(it.get("value")).replace(" ", "") \
                            and _norm(it.get("value")).replace(" ", "") not in _norm(v).replace(" ", ""):
                        bad_val.append("%s(코드 %s · 신고 %s)" % (n, v, it.get("value")))
                if bad_src:
                    add("P7_constants_source", "fail", "constants 의 source 가 paper|supplement|harness 가 아닌 항목 %d개" % len(bad_src),
                        ", ".join(bad_src[:30]))
                if bad_val:
                    add("P7_constants_value_mismatch", "fail", "constants 의 value 가 코드 값과 다르다 %d건" % len(bad_val),
                        "신고가 사실과 다르면 감사는 misdeclared 를 낸다 — 코드 값 그대로 적어라: " + ", ".join(bad_val[:20]))

    # ── P8 하네스 공시 — 프롬프트가 준 블록을 FIDELITY.harness_disclosure 에 옮겼는가(분류 보고서 HARNESS 12건) ──────────
    #   ★강제 조건 = 이번 실행의 prompt.txt 에 블록이 **실제로 실렸을 때만**. 블록 생성이 실패한 실행에서 강제하면 구현자는
    #     옮길 블록이 없는데 걸린다(보정 패스도 같은 결과 — 무의미한 패스).
    H = cfg.get("harness") or {}
    mk, ek = H.get("marker") or "[HARNESS-DISCLOSURE v1]", H.get("end_marker") or "[/HARNESS-DISCLOSURE]"
    pr_p = os.path.join(wdir, "prompt.txt")
    in_prompt = os.path.isfile(pr_p) and mk in io.open(pr_p, "rb").read().decode("utf-8", "replace")
    stats["harness_block_in_prompt"] = bool(in_prompt)
    if H.get("required") and in_prompt:
        hd = str(fid.get("harness_disclosure") or "")
        if mk not in hd or ek not in hd:
            add("P8_harness_disclosure_missing", "fail", "harness_disclosure 에 하네스 공시 블록이 없다",
                "프롬프트의 '하네스 고지' 대괄호 블록(%s … %s)을 FIDELITY.json 의 harness_disclosure 에 그대로 옮겨라 — "
                "하네스가 만든 차이(신호일 유니버스 결합·체결 규약·보유 드리프트·무산출 월 이월·비용·표본기간)는 이 블록이 공시한다." % (mk, ek))

    # ── P6 방어 코드 범주 — 코드에 있는데 신고 말뭉치에 키워드가 없으면 미신고 후보 ──────────────────
    for cat in cfg.get("categories") or []:
        try:
            crx = [re.compile(r) for r in cat.get("code_regex") or []]
            drx = [re.compile(r, re.I) for r in cat.get("decl_regex") or []]
        except re.error as e:
            raise RuntimeError("설정 정규식 오류(%s): %s" % (cat.get("id"), e))
        hits = sorted({i for rx in crx for i in _lines_matching(code_lines, rx)})
        if not hits:
            continue
        if any(rx.search(corpus) for rx in drx):
            continue
        add("P6_" + str(cat.get("id")), cat.get("severity") or "fail",
            "미신고 후보 — %s (%d줄)" % (cat.get("title") or cat.get("id"), len(hits)),
            (cat.get("guide") or "논문에 없는 처리라면 changed 에 적고, 논문에 있는 처리라면 paper_steps 에 원문 인용과 함께 적어라.")
            + " 해당 줄: " + ", ".join("L%d" % i for i in hits[:12]), hits)

    n_fail = sum(1 for f in F if f["severity"] == "fail")
    verdict = "pass" if n_fail == 0 else "findings"
    return {"schema": "rf_preaudit_report_v1", "verdict": verdict, "n_fail": n_fail,
            "n_warn": sum(1 for f in F if f["severity"] == "warn"),
            "findings": F, "stats": stats,
            "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "inputs": ["engine.R", "FIDELITY.json", reg_rel]}


def feedback_text(rep, max_chars):
    """FAILFB(declaration_gate) 로 실릴 지적문 — 성과 수치·산출물 경로 없음(입력이 그런 것을 안 읽는다)."""
    L = []
    for f in rep["findings"]:
        if f["severity"] != "fail":
            continue
        L.append("- [%s] %s — %s" % (f["code"], f["title"], f["detail"]))
    warns = [f for f in rep["findings"] if f["severity"] == "warn"]
    if warns:
        L.append("(참고 — 기각 사유는 아니지만 고치면 감사가 덜 걸린다)")
        for f in warns:
            L.append("- [%s] %s — %s" % (f["code"], f["title"], f["detail"]))
    s = "\n".join(L)
    return s if len(s) <= max_chars else s[:max_chars - 20] + "\n…(이하 생략)"


EXIT_GATE_REIMPLEMENT = 10


def _write_json_atomic(p, obj):
    tmp = p + ".tmp_preaudit"
    io.open(tmp, "wb").write(json.dumps(obj, ensure_ascii=False, indent=1).encode("utf-8"))
    os.replace(tmp, p)


def gate(a):
    """레인 관문 — 검사 + 요청 파일 처분. 표준출력 마지막 줄 = 'action=<proceed|reimplement> …'.

    종료 코드: 0 = 측정으로 진행(통과·비활성·회차 소진·검사 불능 fail-open) · 10 = 측정 없이 보정 패스 요청.
    ★카운터 분리: preaudit_rounds 만 올린다 — audit_retries(감사 재구현 1회)·auto_retries(skiplist 3회)는 건드리지 않는다.
    ★status=pending 으로 되돌리므로 레인 재시도 블록(failed_needs_session 전용)이 auto_retries 를 태우지 않는다.
    ★보정 패스의 피드백 통로 = 기존 '측정 실패' 절(failure=declaration_gate) — 청정 규칙이 아는 절이라 청정 판독을 깨지 않는다.
    """
    cfg_p = a.cfg or os.path.join(a.root, "06_Registry", "rf_preaudit.json")
    try:
        cfg = _load_json(cfg_p)
    except Exception as e:
        print("action=proceed verdict=error why=config_unreadable:%s" % str(e)[:80])
        return EXIT_PASS
    if not cfg.get("enabled", False):
        print("action=proceed verdict=skip why=disabled")
        return EXIT_PASS
    if str(a.is_combo) == "1" and not cfg.get("apply_to_combo", False):
        print("action=proceed verdict=skip why=combo")
        return EXIT_PASS
    try:
        req = _load_json(a.req)
    except Exception as e:
        print("action=proceed verdict=error why=request_unreadable:%s" % str(e)[:80])
        return EXIT_PASS
    # ★파일 이름은 청정 규칙의 작업 디렉터리 레인 파일 정규식(06_Registry/prereg/clean_base_rule.config.json
    #   exposure.wdir.lane_file_regex — 사전등록 핀) 안이어야 한다: '^\.clean_' · '^engine\.rejected[0-9A-Za-z_]*\.R$'.
    #   밖이면 다음 패스의 엔진보다 먼저 있던 '레인 밖 파일'로 잡혀 청정 판독이 깨진다(검사 G12 가 정규식으로 재도출한다).
    rep_p = os.path.join(a.wdir, ".clean_preaudit.json")
    fb_p = os.path.join(a.wdir, ".clean_preaudit_feedback.txt")
    try:
        rep = run(a.wdir, a.root, cfg)
    except Exception as e:
        rep = {"schema": "rf_preaudit_report_v1", "verdict": "error", "error": str(e)[:300],
               "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    io.open(rep_p, "w", encoding="utf-8").write(json.dumps(rep, ensure_ascii=False, indent=1))
    rounds = int(req.get("preaudit_rounds") or 0)
    max_r = int(cfg.get("max_rounds") or 0)
    codes = sorted({f["code"] for f in rep.get("findings") or []})
    hist = req.get("preaudit_history") if isinstance(req.get("preaudit_history"), list) else []
    hist.append({"at": rep.get("checked_at"), "verdict": rep.get("verdict"), "n_fail": rep.get("n_fail"),
                 "codes": codes, "round": rounds})
    req["preaudit_history"] = hist[-10:]
    if rep.get("verdict") == "findings" and rounds < max_r:
        fb = feedback_text(rep, int(cfg.get("feedback_max_chars") or 3500))
        io.open(fb_p, "w", encoding="utf-8").write(fb)
        # 앞 판 보존(사후 대조) — engine.R 은 그대로 둔다: 보정 패스가 그 자리에서 고친다(FAILFB 절 규약).
        try:
            src = os.path.join(a.wdir, "engine.R")
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(a.wdir, "engine.rejected_preaudit%d.R" % (rounds + 1)))
        except Exception:
            pass
        req["status"] = "pending"
        req["failure"] = "declaration_gate"
        req["failure_detail"] = fb
        req["preaudit_rounds"] = rounds + 1
        req["preaudit_last_at"] = rep.get("checked_at")
        _write_json_atomic(a.req, req)
        print("action=reimplement verdict=findings n_fail=%s round=%d/%d codes=%s"
              % (rep.get("n_fail"), rounds + 1, max_r, ",".join(codes)))
        return EXIT_GATE_REIMPLEMENT
    # 진행 — 앞 회차가 남긴 declaration_gate 사유는 지운다(다음 단계·다음 패스에 낡은 사유가 실리지 않게).
    if str(req.get("failure") or "") == "declaration_gate":
        req["failure"] = ""
        req["failure_detail"] = ""
    if rep.get("verdict") == "findings":
        req["preaudit_residual"] = {"at": rep.get("checked_at"), "codes": codes, "n_fail": rep.get("n_fail"),
                                    "note": "보정 회차 소진 — 측정·감사로 진행(감사가 최종 판정)"}
    _write_json_atomic(a.req, req)
    why = {"pass": "pass", "findings": "rounds_exhausted", "error": "checker_error"}.get(rep.get("verdict"), "unknown")
    print("action=proceed verdict=%s why=%s n_fail=%s codes=%s"
          % (rep.get("verdict"), why, rep.get("n_fail", "NA"), ",".join(codes)))
    return EXIT_PASS


def main(argv):
    if "--harness-block" in argv:
        # 프롬프트 조립용 — 실패하면 빈 출력·rc 3(레인은 블록 없이 진행하고 저널에 남긴다 · P8 은 그때 비활성 판단을 설정이 한다)
        ap0 = argparse.ArgumentParser()
        ap0.add_argument("--harness-block", action="store_true")
        ap0.add_argument("--root", required=True)
        ap0.add_argument("--cfg", default=None)
        a0 = ap0.parse_args(argv)
        try:
            cfg0 = _load_json(a0.cfg or os.path.join(a0.root, "06_Registry", "rf_preaudit.json"))
            if not cfg0.get("enabled", False) or not (cfg0.get("harness") or {}).get("required"):
                return EXIT_PASS
            txt, _ = harness_block(a0.root, cfg0)
            sys.stdout.write(txt + "\n")
            return EXIT_PASS
        except Exception as e:
            sys.stderr.write("[rf_preaudit] harness-block 실패: %s\n" % str(e)[:200])
            return EXIT_ERROR
    ap = argparse.ArgumentParser()
    ap.add_argument("--wdir", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--cfg", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--feedback-out", default=None)
    ap.add_argument("--gate", action="store_true", help="레인 관문 모드 — 요청 파일 처분까지")
    ap.add_argument("--req", default=None)
    ap.add_argument("--is-combo", default="0")
    a = ap.parse_args(argv)
    if a.gate:
        if not a.req:
            print("action=proceed verdict=error why=no_req")
            return EXIT_PASS
        return gate(a)
    cfg_p = a.cfg or os.path.join(a.root, "06_Registry", "rf_preaudit.json")
    try:
        cfg = _load_json(cfg_p)
        rep = run(a.wdir, a.root, cfg)
    except Exception as e:
        rep = {"schema": "rf_preaudit_report_v1", "verdict": "error", "error": str(e)[:300],
               "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        if a.out:
            io.open(a.out, "w", encoding="utf-8").write(json.dumps(rep, ensure_ascii=False, indent=1))
        print(json.dumps({"verdict": "error", "error": rep["error"]}, ensure_ascii=False))
        return EXIT_ERROR
    if a.out:
        io.open(a.out, "w", encoding="utf-8").write(json.dumps(rep, ensure_ascii=False, indent=1))
    if a.feedback_out:
        io.open(a.feedback_out, "w", encoding="utf-8").write(
            feedback_text(rep, int(cfg.get("feedback_max_chars") or 3500)))
    print(json.dumps({"verdict": rep["verdict"], "n_fail": rep["n_fail"], "n_warn": rep["n_warn"],
                      "codes": sorted({f["code"] for f in rep["findings"]})}, ensure_ascii=False))
    return EXIT_PASS if rep["verdict"] == "pass" else EXIT_FINDINGS


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
