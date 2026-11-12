#!/usr/bin/env python3
import unittest
import xml.etree.ElementTree as ET

from add_appcast_item import SPARKLE, add_item, check_release, next_build

EMPTY = """<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>flyt</title>
        <!-- kept by hand -->
    </channel>
</rss>
"""
SIG = 'sparkle:edSignature="abc123==" length="4567"'


def add(text, version, build, url="https://example.com/a.zip", **extra):
    return add_item(text, version, build, url, SIG, "14.6", **extra)


class AddItemTests(unittest.TestCase):
    def items(self, text):
        return ET.fromstring(text).find("channel").findall("item")

    def test_adds_an_item_with_the_fields_sparkle_reads(self):
        text = add(EMPTY, "0.6.0", "42", url="https://example.com/flyt-0.6.0.zip",
                   release_notes_url="https://example.com/notes?a=1&b=2",
                   date="Sat, 31 Oct 2026 00:00:00 GMT")
        (item,) = self.items(text)
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}version"), "42")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}shortVersionString"), "0.6.0")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}minimumSystemVersion"), "14.6")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}releaseNotesLink"), "https://example.com/notes?a=1&b=2")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.com/flyt-0.6.0.zip")
        self.assertEqual(enclosure.get("length"), "4567")
        self.assertEqual(enclosure.get(f"{{{SPARKLE}}}edSignature"), "abc123==")

    def test_newest_item_comes_first(self):
        second = add(add(EMPTY, "0.6.0", "42"), "0.7.0", "50")
        versions = [i.findtext(f"{{{SPARKLE}}}shortVersionString") for i in self.items(second)]
        self.assertEqual(versions, ["0.7.0", "0.6.0"])

    def test_rejects_a_build_that_is_not_higher_than_every_listed_one(self):
        once = add(EMPTY, "0.6.0", "42")
        for build in ["42", "042", "41"]:
            with self.assertRaises(ValueError):
                add(once, "0.6.1", build)

    def test_rejects_a_version_that_is_already_listed(self):
        once = add(EMPTY, "0.6.0", "42")
        with self.assertRaises(ValueError):
            add(once, "0.6.0", "43")

    def test_rejects_a_build_that_is_not_a_whole_number(self):
        with self.assertRaises(ValueError):
            add(EMPTY, "0.6.0", "1.2")

    def test_rejects_a_malformed_signature_line(self):
        with self.assertRaises(ValueError):
            add_item(EMPTY, "0.6.0", "42", "https://example.com/a.zip", "nonsense", "14.6")

    def test_rejects_an_appcast_without_a_channel(self):
        with self.assertRaises(ValueError):
            add('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"/>', "0.6.0", "42")
        with self.assertRaises(ValueError):
            add("not xml", "0.6.0", "42")

    def test_leaves_the_rest_of_the_document_as_it_was(self):
        text = add(add(EMPTY, "0.6.0", "42"), "0.7.0", "50")
        self.assertTrue(text.startswith('<?xml version="1.0" standalone="yes"?>'))
        self.assertIn("<!-- kept by hand -->", text)
        self.assertEqual(text.count("xmlns:sparkle"), 1)

    def test_next_build_is_one_past_the_highest_listed(self):
        self.assertEqual(next_build(EMPTY), 2)
        self.assertEqual(next_build(add(EMPTY, "0.6.0", "42")), 43)

    def test_check_passes_a_release_that_can_be_added(self):
        check_release(add(EMPTY, "0.6.0", "42"), "43", "0.6.1")


if __name__ == "__main__":
    unittest.main()
