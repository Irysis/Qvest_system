#!/usr/bin/env python3
# =============================================================================
# rf_paper_text.py — 충실구현 레인 **원문 축자본 선수집** (2026-10-17 도훈 "사전 코드 감사로 기각되는 상황을 만들지 않는 게 최우선")
#
# ★왜: 1차 기각 원인 분석(04_Research/01_reports/first_pass_rejection_rootcause_20261017/README.md) — 10-05 이후 첫 판 13편 중
#   12편 기각 · 지적 74건 중 24건(32%)이 '전문 미열람'이고 전부 요약만 읽은 6편에서 나왔다(축자 완독 6편은 0건). WebFetch 는
#   페이지를 소형 모델이 질문별로 요약하는 도구(호출당 1~3천 자 · 인용 125자 상한)라 html 전문 주소를 줘도 원문이 들어오지 않는다.
#   ⇒ 레인이 에이전트 기동 전에 원문을 **축자 그대로** 작업 디렉터리에 받아 두고, 구현자 · 감사자가 **같은 파일**을 Read 로 끝까지 읽는다
#   (판 일치 · html v1 이 없는 편 해소 — 1801.01777 · 2412.12516 · 2507.01964 는 html v1 404).
#
# 출처 순서(arXiv): ① html v1(LaTeXML — 감사자가 읽던 판 · 수식 = alttext 의 LaTeX) ② e-print v1(LaTeX 원천 — html 이 없는 편)
#   ③ pdf v1 텍스트(pypdf — 수식 배치는 잃는다). arXiv 가 아닌 링크는 그 주소를 그대로(HTML → 텍스트 · PDF → pypdf).
# 산출: <wdir>/.clean_paper/paper.md + manifest.json(출처 · 판 · 종류 · sha256 · 글자 수 · 시도 기록).
#   이름이 .clean_ 으로 시작하는 이유 = 청정 규칙(06_Registry/prereg/clean_base_rule.config.json wdir.lane_file_regex '^\.clean_')의
#   레인 파일 — 사전등록 핀을 고치지 않는다. 이미 있고 sha256 이 맞으면 다시 받지 않는다(재구현 판 · 검증기만 재실행).
# 청정성: 입력 = 논문 링크뿐 — 측정 산출물 · 성과 파일을 읽지 않는다.
# 사용: rf_paper_text.py --url <논문 링크> --wdir <WDIR> [--timeout 60]
#       검사용 오프라인 입력: --from-html F | --from-eprint F | --from-pdf F (네트워크 없이 그 파일을 원천으로)
# 종료: 0 = 축자본 있음(마지막 줄 'ok kind=… version=… chars=… path=…') · 3 = 못 받음('fail why=…' — 레인은 대체 지시로 진행)
# 검사 = 08_Tests/ops/test_rf_paper_text.py
# =============================================================================
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import sys
import tarfile
import time
from html.parser import HTMLParser

EXIT_OK, EXIT_FAIL = 0, 3
OUT_DIR = ".clean_paper"
MIN_CHARS = 2000            # 이보다 짧으면 오류 · 변환 실패 쪽(초록만 · 404 안내) — 다음 출처로 간다
WRAP = 400                  # Read 친화 줄 길이(공백에서만 끊는다)
MAX_ARCHIVE = 40 * 1024 * 1024
UA = "Qvest-replication-lane/1.0 (paper text prefetch for faithful replication)"


# ── 링크 → arXiv id ───────────────────────────────────────────────────────────
def arxiv_id(url):
    m = re.search(r"arxiv\.org/(?:abs|html|pdf|e-print)/([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?", url or "")
    return m.group(1) if m else ""


# ── HTML(LaTeXML) → 텍스트 ────────────────────────────────────────────────────
class _HtmlText(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
    SKIP = {"script", "style", "nav", "header", "footer", "noscript", "button", "svg", "form"}
    BLOCK = {"p", "div", "section", "article", "li", "ul", "ol", "table", "figure", "figcaption", "blockquote",
             "dd", "dt", "dl", "caption", "pre"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.buf, self.stack = [], []
        self.skip_at = None          # 건너뛰기를 시작한 스택 깊이
        self.math_at = None          # <math> 안(alttext 로 이미 냈다)
        self.has_article = False

    def _emit(self, s):
        self.buf.append(s)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag not in self.VOID:
            self.stack.append(tag)
        if self.skip_at is not None or self.math_at is not None:
            return
        if tag == "article":
            self.has_article = True
        if tag in self.SKIP:
            self.skip_at = len(self.stack)
            return
        if tag == "math":
            alt = (a.get("alttext") or "").strip()
            self._emit(" $%s$ " % alt if alt else " ")
            self.math_at = len(self.stack)
            return
        if re.fullmatch(r"h[1-6]", tag):
            self._emit("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in ("td", "th"):
            self._emit(" | ")
        elif tag == "tr":
            self._emit("\n")
        elif tag == "br":
            self._emit("\n")
        elif tag == "li":
            self._emit("\n- ")
        elif tag in self.BLOCK:
            self._emit("\n\n")

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        if tag in self.stack:                       # 닫히지 않은 태그는 함께 닫는다(느슨한 HTML)
            while self.stack:
                t = self.stack.pop()
                if t == tag:
                    break
        depth = len(self.stack)
        if self.skip_at is not None and depth < self.skip_at:
            self.skip_at = None
            return
        if self.math_at is not None and depth < self.math_at:
            self.math_at = None
            return
        if self.skip_at is None and self.math_at is None:
            if re.fullmatch(r"h[1-6]", tag) or tag in self.BLOCK:
                self._emit("\n\n")

    def handle_data(self, data):
        if self.skip_at is None and self.math_at is None:
            self._emit(data)


def _norm_text(raw):
    lines = []
    for para in re.split(r"\n\s*\n", raw):
        p = re.sub(r"[ \t\r\f\v]+", " ", para).strip()
        p = re.sub(r" *\n *", "\n", p)
        if not p:
            continue
        for ln in p.split("\n"):
            ln = ln.strip()
            while len(ln) > WRAP:                    # 공백에서만 끊는다
                cut = ln.rfind(" ", 0, WRAP)
                if cut <= 0:
                    break
                lines.append(ln[:cut])
                ln = ln[cut + 1:]
            if ln:
                lines.append(ln)
        lines.append("")
    return "\n".join(lines).strip() + "\n"


def html_to_text(doc):
    article = re.search(r"<article\b.*?</article>", doc, re.S | re.I)   # LaTeXML 본문만(사이트 머리 · 꼬리 제외)
    p = _HtmlText()
    p.feed(article.group(0) if article else doc)
    p.close()
    return _norm_text("".join(p.buf))


# ── LaTeX 원천(e-print) → 텍스트 ──────────────────────────────────────────────
def _strip_tex_comments(s):
    return "\n".join(re.sub(r"(?<!\\)%.*$", "", ln) for ln in s.splitlines())


def eprint_to_text(data):
    """e-print 바이트 → (텍스트, 종류). tar(.gz) · gzip 단일 .tex · PDF(원천 없음) 를 가린다."""
    if len(data) > MAX_ARCHIVE:
        raise RuntimeError("e-print 가 너무 크다(%d bytes)" % len(data))
    if data[:4] == b"%PDF":
        return pdf_to_text(data), "pdf_from_eprint"
    files = {}
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:   # 디스크에 풀지 않는다(경로 탈출 없음)
            for m in tf.getmembers():
                if m.isfile() and m.name.lower().endswith(".tex") and m.size <= MAX_ARCHIVE:
                    files[m.name] = tf.extractfile(m).read().decode("utf-8", "replace")
    except tarfile.TarError:
        try:
            raw = gzip.decompress(data)
        except OSError:
            raw = data
        if raw[:4] == b"%PDF":
            return pdf_to_text(raw), "pdf_from_eprint"
        files["main.tex"] = raw.decode("utf-8", "replace")
    if not files:
        raise RuntimeError("e-print 에 .tex 가 없다")
    mains = [k for k, v in files.items() if "\\documentclass" in v]
    main = sorted(mains, key=lambda k: ("\\begin{document}" not in files[k], len(k)))[0] if mains else sorted(files)[0]
    by_stem = {}
    for k in files:
        by_stem.setdefault(re.sub(r"\.tex$", "", k, flags=re.I), k)
        by_stem.setdefault(re.sub(r"\.tex$", "", os.path.basename(k), flags=re.I), k)
    seen = set()

    def expand(name, depth):
        if name in seen or depth > 6:
            return ""
        seen.add(name)
        body = _strip_tex_comments(files[name])
        base = os.path.dirname(name)

        def sub(m):
            ref = m.group(2).strip()
            ref = re.sub(r"\.tex$", "", ref, flags=re.I)
            cand = [os.path.normpath(os.path.join(base, ref)).replace("\\", "/"), ref, os.path.basename(ref)]
            for c in cand:
                if c in by_stem:
                    return "\n%% ---- %s ----\n%s\n" % (by_stem[c], expand(by_stem[c], depth + 1))
            return m.group(0)
        return re.sub(r"\\(input|include)\s*\{([^}]+)\}", sub, body)

    text = expand(main, 0)
    rest = [k for k in sorted(files) if k not in seen]                # 본문에서 안 불린 .tex 도 뒤에 붙인다(부록 · 별도 파일)
    for k in rest:
        text += "\n\n%% ---- %s (본문 미참조) ----\n%s\n" % (k, _strip_tex_comments(files[k]))
    return text.strip() + "\n", "latex"


# ── PDF → 텍스트 ──────────────────────────────────────────────────────────────
def pdf_to_text(data):
    from pypdf import PdfReader
    r = PdfReader(io.BytesIO(data))
    pages = []
    for i, pg in enumerate(r.pages, 1):
        pages.append("[p. %d]\n%s" % (i, (pg.extract_text() or "").strip()))
    return _norm_text("\n\n".join(pages))


# ── 받기 ──────────────────────────────────────────────────────────────────────
def _get(url, timeout):
    """표준 라이브러리만(urllib) — 레인의 QVEST_PY 는 venv 가 아닌 시스템 파이썬이라 requests 가 없다(10-17 첫 실운영 실측:
    2601.04602 세 출처 전부 'No module named requests'). 리디렉션은 urllib 가 따른다 · HTTP 오류는 상태 코드로 돌려준다."""
    import urllib.error
    import urllib.request
    last = None
    for _ in range(2):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read(), (r.headers.get("content-type") or "")
        except urllib.error.HTTPError as e:      # 404 등 — 다음 출처로(재시도 없음)
            return e.code, b"", ""
        except Exception as e:                   # 연결 오류만 한 번 더
            last = e
            time.sleep(3)
    raise RuntimeError("요청 실패: %s" % str(last)[:160])


def collect(url, timeout, offline=None):
    """(텍스트, 종류, 판, 출처 URL, 시도 기록). offline = {'html'|'eprint'|'pdf': 경로} 면 네트워크를 쓰지 않는다."""
    tried = []
    aid = arxiv_id(url)

    def take(kind, data):
        if kind == "html":
            txt, k = html_to_text(data.decode("utf-8", "replace")), "html"
        elif kind == "eprint":
            txt, k = eprint_to_text(data)
        else:
            txt, k = pdf_to_text(data), "pdf"
        if len(txt) < MIN_CHARS:
            raise RuntimeError("본문이 너무 짧다(%d자 — 변환 실패 · 안내 페이지)" % len(txt))
        return txt, k

    plans = []
    if offline:
        for kind in ("html", "eprint", "pdf"):
            if offline.get(kind):
                plans.append((kind, "file:" + offline[kind]))
    elif aid:
        plans = [("html", "https://arxiv.org/html/%sv1" % aid), ("eprint", "https://arxiv.org/e-print/%sv1" % aid),
                 ("pdf", "https://arxiv.org/pdf/%sv1" % aid)]
    elif url:
        plans = [("auto", url)]
    for kind, src in plans:
        try:
            if src.startswith("file:"):
                data, status, ctype = io.open(src[5:], "rb").read(), 200, ""
            else:
                status, data, ctype = _get(src, timeout)
            if status != 200:
                tried.append({"url": src, "status": status})
                continue
            if kind == "auto":
                kind = "pdf" if (data[:4] == b"%PDF" or "pdf" in ctype.lower()) else "html"
            txt, k = take(kind, data)
            tried.append({"url": src, "status": status, "kind": k, "chars": len(txt)})
            return txt, k, ("v1" if aid else ""), src, tried
        except Exception as e:
            tried.append({"url": src, "error": str(e)[:200]})
    raise RuntimeError("축자본을 못 받았다 — " + "; ".join("%s → %s" % (t["url"], t.get("status", t.get("error"))) for t in tried))


def _sha(p):
    return hashlib.sha256(io.open(p, "rb").read()).hexdigest()


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="")
    ap.add_argument("--wdir", required=True)
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--from-html", default=None)
    ap.add_argument("--from-eprint", default=None)
    ap.add_argument("--from-pdf", default=None)
    ap.add_argument("--offline", action="store_true", help="네트워크를 쓰지 않는다(재사용 또는 --from-* 만 · 검사용)")
    a = ap.parse_args(argv)
    od = os.path.join(a.wdir, OUT_DIR)
    pp, mp = os.path.join(od, "paper.md"), os.path.join(od, "manifest.json")
    rel = "%s/paper.md" % OUT_DIR
    try:                                                           # 재사용 — 같은 링크 · sha256 일치
        m = json.loads(io.open(mp, "rb").read().decode("utf-8"))
        if m.get("source_page") == a.url and os.path.isfile(pp) and _sha(pp) == m.get("sha256"):
            print("ok kind=%s version=%s chars=%s path=%s cached=1" % (m.get("kind"), m.get("version") or "-", m.get("chars"), rel))
            return EXIT_OK
    except Exception:
        pass
    offline = {k: v for k, v in (("html", a.from_html), ("eprint", a.from_eprint), ("pdf", a.from_pdf)) if v} or None
    if a.offline and not offline:
        print("fail why=offline — 재사용할 축자본이 없고 원천 파일도 주지 않았다")
        return EXIT_FAIL
    try:
        txt, kind, ver, src, tried = collect(a.url, a.timeout, offline)
    except Exception as e:
        print("fail why=%s" % str(e)[:300].replace("\n", " "))
        return EXIT_FAIL
    os.makedirs(od, exist_ok=True)
    head = ("<!-- 원문 축자본 — 레인이 에이전트 기동 전에 받은 원문 그대로(요약 아님). 구현자와 감사자가 이 파일을 함께 읽는다.\n"
            "     출처 %s · 종류 %s · 판 %s · 수식 = LaTeX($…$ 또는 원천 그대로) · 받은 시각 %s -->\n\n"
            % (src, kind, ver or "-", time.strftime("%Y-%m-%dT%H:%M:%S%z")))
    body = head + txt
    tmp = pp + ".tmp"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(body)
    os.replace(tmp, pp)
    man = {"schema": "paper_text_v1", "source_page": a.url, "source_fetched": src, "arxiv_id": arxiv_id(a.url), "kind": kind,
           "version": ver, "chars": len(body), "lines": body.count("\n"), "sha256": _sha(pp),
           "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "tried": tried}
    io.open(mp + ".tmp", "w", encoding="utf-8").write(json.dumps(man, ensure_ascii=False, indent=1))
    os.replace(mp + ".tmp", mp)
    print("ok kind=%s version=%s chars=%d path=%s cached=0" % (kind, ver or "-", len(body), rel))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
