#!/usr/bin/env python3
"""CHANGELOG 版本段落解析：标题分隔符兼容、标题级别、精确匹配与正文边界。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_ci", Path(__file__).with_name("release-ci.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

BODY = "首个公开版本，可用。\n\n- 修复一项问题。"

# CHANGELOG 实际出现或可能出现的标题写法：6 种分隔符 + 直接跟括号。
SEPARATED_TITLES = {
    "hyphen": "## 1.0.10 - 2026-11-11",
    "en-dash": "## 1.0.10 – 2026-11-11",
    "em-dash": "## 1.0.10 — 2026-11-11",
    "middle-dot": "## 1.0.10 · 2026-11-11（源码更新）",
    "pipe": "## 1.0.10 | 2026-11-11",
    "whitespace": "## 1.0.10    2026-11-11",
    "cjk-paren": "## 1.0.10（首个公开版，GitHub Releases）",
    "ascii-paren": "## 1.0.10(2026-11-11)",
    "bare": "## 1.0.10",
}


class ChangelogEntryTests(unittest.TestCase):
    def entry_from(self, text, version="1.0.10"):
        """在临时目录里写入 CHANGELOG.md，复用它作为 release-ci 的仓库根。"""
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "CHANGELOG.md").write_text(text, encoding="utf-8")
            with patch.object(release, "ROOT", Path(directory)):
                return release.changelog_entry(version)

    def assert_missing(self, text, version="1.0.10"):
        with self.assertRaises(ValueError) as raised:
            self.entry_from(text, version)
        self.assertEqual(str(raised.exception), "Release version has no changelog entry")

    def test_accepts_every_title_separator(self):
        for name, title in SEPARATED_TITLES.items():
            with self.subTest(separator=name):
                self.assertEqual(self.entry_from(title + "\n\n" + BODY + "\n"), BODY)

    def test_level_three_heading_is_not_an_entry(self):
        # ### 是段落内小节，不能当成版本段落；没有 ## 段落时应当报错。
        self.assert_missing("### 1.0.10 - 2026-11-11\n\n" + BODY + "\n")
        self.assert_missing("#### 1.0.10 - 2026-11-11\n\n" + BODY + "\n")

    def test_version_must_match_exactly(self):
        # 前缀版本号不能误匹配：1.0.10 不等于 1.0.100 / 1.0.1，也不是 1.0.10-dev.1 的段落。
        text = "\n".join(["## 1.0.100 - 2026-11-11", "长版本正文", "## 1.0.1 - 2026-11-10", "短版本正文",
                          "## 1.0.10-dev.1 - 2026-11-09", "预发布正文", ""])
        self.assert_missing(text)
        self.assertEqual(self.entry_from(text, "1.0.100"), "长版本正文")
        self.assertEqual(self.entry_from(text, "1.0.1"), "短版本正文")
        self.assertEqual(self.entry_from(text, "1.0.10-dev.1"), "预发布正文")

    def test_version_is_matched_literally(self):
        # re.escape：请求里的点不能当通配符。
        self.assert_missing("## 1a0b10 - 2026-11-11\n\n" + BODY + "\n")

    def test_missing_version_keeps_raising_value_error(self):
        self.assert_missing("## 1.0.9 - 2026-11-09\n\n" + BODY + "\n")
        self.assert_missing("")

    def test_body_stops_before_next_second_level_heading(self):
        text = "\n".join(["# 更新日志", "", "## 1.0.10 · 2026-11-11（首个公开版）", "", BODY, "",
                          "### 分发属性", "", "- 已公证。", "", "## 1.0.9 - 2026-11-09", "", "下一版本正文", ""])
        entry = self.entry_from(text)
        self.assertTrue(entry.startswith("首个公开版本"))
        # ### 小节属于本节，保留。
        self.assertIn("### 分发属性", entry)
        self.assertIn("- 已公证。", entry)
        # 下一个 ## 段落不属于本节。
        self.assertNotIn("1.0.9", entry)
        self.assertNotIn("下一版本正文", entry)
        # 末尾空白裁剪。
        self.assertEqual(entry, entry.strip())

    def test_empty_entry_raises_value_error(self):
        # 标题存在但正文为空（下一 ## 紧跟其后）应当报错，而不是返回空串。
        self.assert_missing("## 1.0.10 - 2026-11-11\n\n   \n\n## 1.0.9 - 2026-11-09\n\n上一版正文\n")
        self.assert_missing("## 1.0.10 - 2026-11-11\n")

    def test_first_matching_entry_wins(self):
        # 与原有语义一致：同名版本重复出现时取最前面（最新）的那一节。
        text = "## 1.0.10 · 2026-11-13（首个公开版）\n\n新正文\n\n## 1.0.10 · 2026-11-11（源码更新）\n\n旧正文\n"
        self.assertEqual(self.entry_from(text), "新正文")


class RealChangelogTests(unittest.TestCase):
    def test_current_release_and_legacy_entries_parse(self):
        entry = release.changelog_entry("1.0.10")
        self.assertTrue(entry.strip())
        self.assertFalse(entry.lstrip().startswith("##"))
        self.assertNotIn("未发布 · BlinkClip 清理", entry)
        # 向后兼容：旧的 `## 版本 - 日期` 段落仍可解析。
        self.assertIn("临时签名", release.changelog_entry("1.0.8"))

    def test_absent_version_raises_value_error(self):
        with self.assertRaises(ValueError):
            release.changelog_entry("99.99.99")


if __name__ == "__main__":
    unittest.main(verbosity=2)
