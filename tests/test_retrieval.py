"""Integration tests for the selective knowledge retrieval worker (retrieval.py).

Opt-in, matching the repo's integration-test convention: point
LOGSEQD_TEST_URL at a disposable logseqd daemon and run

    java -jar desktop/target/logseq-datalog.jar /tmp/recall-graph 8491 &
    LOGSEQD_TEST_URL=http://127.0.0.1:8491 \\
      python3 -m unittest discover -s tests -p test_retrieval.py -v

The fixture graph should encode the Phase 0 audit findings (see
docs/PHASE0-AUDIT.md): a namespaced ghost page, a fenced [[ref]], inline and
property-zone id:: blocks, a TODO block, and a journal entry.
"""

import json
import os
import sys
import unittest
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from retrieval import STATIC_LIMITATIONS, RecallError, edn, recall  # noqa: E402

BASE_URL = os.environ.get("LOGSEQD_TEST_URL", "http://127.0.0.1:8491")


def daemon_up(url):
    try:
        with urllib.request.urlopen(url + "/health", timeout=2) as resp:
            return resp.status == 200
    except Exception:
        return False


@unittest.skipUnless(daemon_up(BASE_URL), "no disposable logseqd daemon (set LOGSEQD_TEST_URL)")
class TestEdn(unittest.TestCase):
    def test_rendering(self):
        self.assertEqual(edn("hello"), '"hello"')
        self.assertEqual(edn("?b"), "?b")
        self.assertEqual(edn(":block/refs"), ":block/refs")
        self.assertEqual(edn(True), "true")
        self.assertEqual(edn(["?b", ":block/page", "?bp"]), "[?b :block/page ?bp]")
        self.assertEqual(edn('(includes? ?c "x")'), '(includes? ?c "x")')


@unittest.skipUnless(daemon_up(BASE_URL), "no disposable logseqd daemon (set LOGSEQD_TEST_URL)")
class TestRecall(unittest.TestCase):
    def test_empty_query_raises(self):
        with self.assertRaises(RecallError):
            recall("   ", base_url=BASE_URL)

    def test_title_match_carries_citations(self):
        packet = recall("Alpha", base_url=BASE_URL)
        top = packet["packet"][0]
        self.assertEqual(top["page"], "Alpha")
        self.assertTrue(top["file"].endswith("Alpha.md"))
        self.assertTrue(top["span"] and top["block_id"])
        self.assertTrue(any("title" in r for r in top["reasons"]))

    def test_backlinks_found_via_datalog(self):
        packet = recall("Alpha", base_url=BASE_URL)
        self.assertGreaterEqual(packet["related"]["Alpha"]["backlink_count"], 1)
        self.assertIn("Beta", packet["related"]["Alpha"]["backlinked_by"])
        self.assertTrue(any("backlink into [[Alpha]]" in e["reasons"] for e in packet["packet"]))

    def test_ghost_namespaced_page_is_flagged_not_fatal(self):
        packet = recall("nested page", base_url=BASE_URL)
        joined = json.dumps(packet)
        self.assertIn("deep/Nested Page", joined)
        self.assertTrue(any("ghost" in w for w in packet["trace"]["warnings"]))

    def test_todo_blocks_reachable_despite_stripped_marker(self):
        packet = recall("todo", base_url=BASE_URL)
        self.assertTrue(any("TODO/task block" in e["reasons"] for e in packet["packet"]))

    def test_journal_content_not_in_search_but_in_packet(self):
        packet = recall("journal morning", base_url=BASE_URL)
        self.assertTrue(any(e["page"] == "2026_11_02" for e in packet["packet"]))
        self.assertTrue(any("journal block" in r for e in packet["packet"] for r in e["reasons"]))

    def test_journal_date_fetches_page_with_spans(self):
        packet = recall("2026_11_02", base_url=BASE_URL)
        self.assertTrue(any(e["span"] and e["span"][0] is not None for e in packet["packet"]))

    def test_budget_and_limit_enforced(self):
        tight = recall("Alpha", base_url=BASE_URL, char_budget=400)
        self.assertLessEqual(tight["trace"]["budget"]["used_chars"], 400)
        self.assertLessEqual(len(tight["packet"]), 3)
        limited = recall("Alpha", base_url=BASE_URL, source_limit=2)
        self.assertLessEqual(len(limited["packet"]), 2)

    def test_trace_is_user_visible_and_bounded(self):
        packet = recall("Alpha", base_url=BASE_URL)
        tr = packet["trace"]
        self.assertTrue(tr["endpoints"] and tr["candidates"])
        self.assertGreaterEqual(tr["duration_ms"], 0)
        self.assertEqual(tr["budget"]["cap_chars"], 4000)
        self.assertTrue(all("kept" in c for c in tr["candidates"]))

    def test_limitations_declared(self):
        self.assertTrue(STATIC_LIMITATIONS)
        self.assertTrue(all(isinstance(x, str) for x in STATIC_LIMITATIONS))


if __name__ == "__main__":
    unittest.main()
