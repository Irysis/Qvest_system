#!/usr/bin/env python3
# =============================================================================
# test_rf_paper_text.py — 원문 축자본 선수집(02_Infrastructure/ops/rf_paper_text.py · 2026-10-17) 오프라인 검사
#   html(LaTeXML) · e-print(tar.gz · gzip 단일 .tex) · PDF 변환 · 재사용(sha256) · 실패 = rc 3 · 빈 산출 · manifest ·
#   산출 디렉터리가 청정 규칙(사전등록 핀 lane_file_regex)의 레인 파일인지 — 핀 파일에서 재도출. 네트워크를 쓰지 않는다.
# 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_rf_paper_text.py
# =============================================================================
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PT = os.path.join(ROOT, "02_Infrastructure", "ops", "rf_paper_text.py")
PY = sys.executable
RESULTS = []


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond)))
    print("%s %s%s" % ("PASS" if cond else "FAIL", name, ("  — " + info) if (info and not cond) else ""))


def run(wdir, url, **src):
    cmd = [PY, PT, "--url", url, "--wdir", wdir, "--offline"]   # 네트워크 무접촉(재사용 · --from-* 만)
    for k, v in src.items():
        cmd += ["--from-" + k, v]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    return p.returncode, (p.stdout.strip().split("\n") or [""])[-1]


def paper(wdir):
    p = os.path.join(wdir, ".clean_paper", "paper.md")
    return io.open(p, encoding="utf-8").read() if os.path.isfile(p) else ""


FILLER = " ".join("We form portfolios each month and hold them for one month before rebalancing again." for _ in range(40))
HTML = ("<html><head><script>var leak=1;</script><style>.a{}</style></head><body><nav>Back to arXiv</nav>"
        "<header>Report issue</header><article class=\"ltx_document\"><h1 class=\"ltx_title\">Test Paper</h1>"
        "<section><h2>2 Method</h2><p>Let <math alttext=\"\\beta_{t-1}\"><mi>INNER_MATHML</mi></math> be the loading.</p>"
        "<table><tr><td>J</td><td>K</td></tr><tr><td>12</td><td>1</td></tr></table>"
        "<p>Footnote<span class=\"ltx_note\"><sup>1</sup>skip one month</span></p><p>" + FILLER + "</p></section></article>"
        "<footer>arXiv footer text</footer></body></html>")


def make_pdf(lines):
    content = b"BT /F1 9 Tf 30 770 Td 11 TL " + b" ".join(b"(" + l.encode("latin-1") + b") '" for l in lines) + b" ET"
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out = io.BytesIO()
    out.write(b"%PDF-1.4\n")
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(out.tell())
        out.write(b"%d 0 obj\n" % i + o + b"\nendobj\n")
    xref = out.tell()
    out.write(b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1))
    for o in offs:
        out.write(b"%010d 00000 n \n" % o)
    out.write(b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref))
    return out.getvalue()


def main():
    tmp = tempfile.mkdtemp(prefix="ptext_")
    try:
        sys.path.insert(0, os.path.dirname(PT))
        import rf_paper_text as M
        check("I1 arxiv_id — abs · html v · pdf · e-print → id · arXiv 아님 → 빈 값",
              M.arxiv_id("https://arxiv.org/abs/1908.01112") == "1908.01112" and M.arxiv_id("https://arxiv.org/html/2411.08864v2") == "2411.08864"
              and M.arxiv_id("https://arxiv.org/pdf/1801.01777v4") == "1801.01777" and M.arxiv_id("https://arxiv.org/e-print/2412.12516v1") == "2412.12516"
              and M.arxiv_id("https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1") == "")

        # ── H html(LaTeXML) ──
        hf = os.path.join(tmp, "p.html"); io.open(hf, "w", encoding="utf-8").write(HTML)
        w1 = os.path.join(tmp, "w1"); os.makedirs(w1)
        rc, out = run(w1, "https://arxiv.org/abs/9999.00001", html=hf)
        t = paper(w1)
        check("H1 html → rc 0 · ok kind=html version=v1", rc == 0 and out.startswith("ok kind=html version=v1"), out)
        check("H2 headings · 수식 alttext($…$) · 표 칸 · 각주 본문 보존", "# Test Paper" in t and "## 2 Method" in t and "$\\beta_{t-1}$" in t
              and "| J | K" in t and "skip one month" in t, t[:300])
        check("H3 본문 밖(nav · header · footer · script) · MathML 내부 글자 제외", not any(s in t for s in ("Back to arXiv", "Report issue", "arXiv footer", "var leak", "INNER_MATHML")))
        check("H4 줄 길이 ≤ 400(공백에서만 끊는다 · Read 친화)", max(len(x) for x in t.splitlines()) <= 400)
        man = json.loads(io.open(os.path.join(w1, ".clean_paper", "manifest.json"), encoding="utf-8").read())
        check("H5 manifest = 종류 · 판 · sha256(파일과 일치) · 시도 기록 · 원 링크",
              man.get("kind") == "html" and man.get("version") == "v1" and man.get("source_page") == "https://arxiv.org/abs/9999.00001"
              and man.get("sha256") == hashlib.sha256(io.open(os.path.join(w1, ".clean_paper", "paper.md"), "rb").read()).hexdigest()
              and man.get("tried") and man["tried"][-1].get("kind") == "html", json.dumps(man, ensure_ascii=False)[:200])
        rc2, out2 = run(w1, "https://arxiv.org/abs/9999.00001")   # 원천 없이 다시 — 캐시가 아니면 실패해야 한다
        check("H6 재사용 — 같은 링크 · sha256 일치면 다시 받지 않는다(cached=1)", rc2 == 0 and "cached=1" in out2, out2)
        io.open(os.path.join(w1, ".clean_paper", "paper.md"), "a", encoding="utf-8").write("tampered\n")
        rc3, out3 = run(w1, "https://arxiv.org/abs/9999.00001")
        check("H7 파일이 바뀌면(sha256 불일치) 재사용하지 않는다 ★음성", rc3 == 3 and out3.startswith("fail"), out3)

        # ── E e-print ──
        tf = os.path.join(tmp, "src.tar.gz")
        with tarfile.open(tf, "w:gz") as z:
            for name, body in (("main.tex", "\\documentclass{article}\n\\begin{document}\n%% secret comment\nIntro text 50\\% done.\n"
                                            "\\input{sections/method}\n\\end{document}\n"),
                               ("sections/method.tex", "We sort stocks into deciles by 12-1 momentum.\n" + FILLER + "\n"),
                               ("appendix_unused.tex", "Appendix B robustness table.\n")):
                b = body.encode("utf-8"); ti = tarfile.TarInfo(name); ti.size = len(b); z.addfile(ti, io.BytesIO(b))
        w2 = os.path.join(tmp, "w2"); os.makedirs(w2)
        rc, out = run(w2, "https://arxiv.org/abs/9999.00002", eprint=tf)
        t = paper(w2)
        check("E1 tar.gz LaTeX → kind=latex · \\input 본문 인라인 · 주석 제거(\\% 는 유지)",
              rc == 0 and "kind=latex" in out and "We sort stocks into deciles" in t and "secret comment" not in t and "50\\% done" in t, out)
        check("E2 본문 미참조 .tex 도 뒤에 붙인다(부록 유실 없음)", "Appendix B robustness table" in t)
        gf = os.path.join(tmp, "single.gz"); io.open(gf, "wb").write(gzip.compress(("\\documentclass{article}\n" + FILLER).encode("utf-8")))
        w3 = os.path.join(tmp, "w3"); os.makedirs(w3)
        rc, out = run(w3, "https://arxiv.org/abs/9999.00003", eprint=gf)
        check("E3 gzip 단일 .tex → kind=latex", rc == 0 and "kind=latex" in out, out)

        # ── P PDF ──
        pf = os.path.join(tmp, "p.pdf")
        io.open(pf, "wb").write(make_pdf(["Line %02d replication text with a lookback of twelve months." % i for i in range(60)]))
        w4 = os.path.join(tmp, "w4"); os.makedirs(w4)
        rc, out = run(w4, "https://arxiv.org/abs/9999.00004", pdf=pf)
        t = paper(w4)
        check("P1 PDF → kind=pdf · 쪽 표식 · 본문 글자", rc == 0 and "kind=pdf" in out and "[p. 1]" in t and "lookback of twelve months" in t, out)
        ep = os.path.join(tmp, "eprint_is_pdf"); shutil.copyfile(pf, ep)
        w5 = os.path.join(tmp, "w5"); os.makedirs(w5)
        rc, out = run(w5, "https://arxiv.org/abs/9999.00005", eprint=ep)
        check("P2 e-print 가 PDF(원천 없는 편) → kind=pdf_from_eprint", rc == 0 and "kind=pdf_from_eprint" in out, out)

        # ── F 실패 = rc 3 · 산출 없음 ──
        sf = os.path.join(tmp, "short.html"); io.open(sf, "w", encoding="utf-8").write("<article><p>Abstract only.</p></article>")
        w6 = os.path.join(tmp, "w6"); os.makedirs(w6)
        rc, out = run(w6, "https://arxiv.org/abs/9999.00006", html=sf)
        check("F1 너무 짧은 본문(초록 · 안내 페이지) → rc 3 · fail · paper.md 없음", rc == 3 and out.startswith("fail why=") and not paper(w6), out)

        # ── N 네트워크 경로 = 레인과 같은 인터프리터(QVEST_PY — venv 아닌 시스템 파이썬)로 로컬 HTTP 서버에서 받는다(10-17 실운영 실측:
        #   검사는 venv 로만 돌아 'No module named requests' 를 못 잡았다 — 오프라인 모드는 받기 경로를 안 탄다) ──
        import http.server, threading, functools
        lane_py = os.environ.get("QVEST_PY") or PY
        srv_dir = os.path.join(tmp, "srv"); os.makedirs(srv_dir); shutil.copyfile(hf, os.path.join(srv_dir, "paper.html"))
        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=srv_dir))
        th = threading.Thread(target=httpd.serve_forever, daemon=True); th.start()
        try:
            base = "http://127.0.0.1:%d" % httpd.server_address[1]
            wn = os.path.join(tmp, "wn"); os.makedirs(wn)
            p = subprocess.run([lane_py, PT, "--url", base + "/paper.html", "--wdir", wn, "--timeout", "20"], capture_output=True, text=True, encoding="utf-8")
            outn = (p.stdout.strip().split("\n") or [""])[-1]
            check("N1 레인 인터프리터(QVEST_PY)로 HTTP 받기 → kind=html · 축자본 생성(비 arXiv 링크 = 그 주소 그대로)",
                  p.returncode == 0 and "kind=html" in outn and "## 2 Method" in paper(wn), "py=%s rc=%s out=%s err=%s" % (lane_py, p.returncode, outn, p.stderr[-200:]))
            wm = os.path.join(tmp, "wm"); os.makedirs(wm)
            p = subprocess.run([lane_py, PT, "--url", base + "/no_such.html", "--wdir", wm, "--timeout", "20"], capture_output=True, text=True, encoding="utf-8")
            check("N2 HTTP 404 → rc 3 · fail(상태 코드 기록) · 축자본 없음", p.returncode == 3 and "404" in p.stdout and not paper(wm), p.stdout[-200:])
        finally:
            httpd.shutdown()
        src_txt = io.open(PT, encoding="utf-8").read()
        check("N3 수집기는 표준 라이브러리 + pypdf(지연 import)만 — requests 등 venv 전용 의존 없음",
              not re.search(r"^\s*import requests|^\s*from requests", src_txt, re.M))

        # ── C 청정 규칙 — 산출 디렉터리 이름이 사전등록 핀의 레인 파일 정규식 안인가(핀 파일에서 재도출) ──
        rule = json.loads(io.open(os.path.join(ROOT, "06_Registry", "prereg", "clean_base_rule.config.json"), encoding="utf-8").read())
        rx = [re.compile(r) for r in ((rule.get("exposure") or {}).get("wdir") or {}).get("lane_file_regex") or []]
        top = [f for f in os.listdir(w1)]
        check("C1 산출(.clean_paper)이 청정 규칙 lane_file_regex 의 레인 파일 — 핀을 고치지 않는다",
              bool(rx) and top == [".clean_paper"] and all(any(r.search(f) for r in rx) for f in top), str(top))

        # ── A 감사 프롬프트도 같은 파일을 가리킨다(정보 동등 — 구현자 · 감사자 같은 원문) ──
        ops = os.path.join(ROOT, "02_Infrastructure", "ops")
        AUD = os.environ.get("RF_AUDIT_SRC") or os.path.join(ops, "rf_fidelity_audit.sh")
        FAN = os.environ.get("RF_FANOUT_SRC") or os.path.join(ops, "rf_fidelity_fanout.sh")
        au = io.open(AUD, encoding="utf-8").read()
        check("A1 단일 감사 — 축자본 줄(파일 있을 때만) · 대상 절에 배선 · '유일한 전문 경로' 단정 제거",
              '[ -s "$WDIR/.clean_paper/paper.md" ] && PAPERLINE=' in au and "${HTMLLINE}\n${PAPERLINE}\n" in au and "유일한 전문 경로" not in au)
        fs = io.open(FAN, encoding="utf-8").read()
        m = re.search(r"<<'PYEOF'\n(.*?)\nPYEOF\n", fs, re.S)
        if m:
            blk = os.path.join(tmp, "fanout_block.py"); io.open(blk, "w", encoding="utf-8").write(m.group(1))
            def fan(with_file):
                w = os.path.join(tmp, "fan_%d" % with_file); shutil.rmtree(w, ignore_errors=True); os.makedirs(w)
                if with_file:
                    os.makedirs(os.path.join(w, ".clean_paper")); io.open(os.path.join(w, ".clean_paper", "paper.md"), "w", encoding="utf-8").write("x")
                env = dict(os.environ, AXB="", HTMLU="https://arxiv.org/html/9999.00001v1", PURL="https://arxiv.org/abs/9999.00001", WDIR=w, ART="",
                           AXES=os.path.join(ROOT, "06_Registry", "rf_fidelity_axes.json"), PLAN=os.path.join(w, "plan.tsv"))
                subprocess.run([PY, blk], env=env, capture_output=True, text=True, encoding="utf-8")
                pf = os.path.join(w, ".audit_prompt_signal.txt")
                return io.open(pf, encoding="utf-8").read() if os.path.isfile(pf) else ""
            p1, p0 = fan(1), fan(0)
            check("A2 팬아웃 감사 — 축자본 있음 = 축자본 줄 + '대조 정본' 안내 · 없음 = 줄 없음(양방향) · '유일한 전문 경로' 단정 제거",
                  "원문 축자본(구현자가 읽은 같은 파일" in p1 and "그것이 대조 정본" in p1 and p0 and "원문 축자본(구현자가 읽은 같은 파일" not in p0
                  and "유일한 전문 경로" not in p1, p1[:200])
        else:
            check("A2 팬아웃 프롬프트 블록을 못 찾았다", False)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    n_fail = sum(1 for _, ok in RESULTS if not ok)
    print("== %d checks · %d failed" % (len(RESULTS), n_fail))
    print(json.dumps({"test": "rf_paper_text", "pass": len(RESULTS) - n_fail, "fail": n_fail, "total": len(RESULTS)}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
