#!/usr/bin/env python3
import unittest
import xml.etree.ElementTree as ET

from add_appcast_item import SPARKLE, add_item

EMPTY = open(__file__.replace("scripts/test_add_appcast_item.py", "docs/appcast.xml")).read()
SIG = 'sparkle:edSignature="abc123==" length="4567"'


class AddItemTests(unittest.TestCase):
    def items(self, text):
        return ET.fromstring(text).find("channel").findall("item")

    def test_adds_an_item_with_the_fields_sparkle_reads(self):
        text = add_item(EMPTY, "0.6.0", "42", "https://example.com/flyt-0.6.0.zip", SIG, date="Sat, 31 Oct 2026 00:00:00 GMT")
        (item,) = self.items(text)
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}version"), "42")
        self.assertEqual(item.findtext(f"{{{SPARKLE}}}shortVersionString"), "0.6.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.com/flyt-0.6.0.zip")
        self.assertEqual(enclosure.get("length"), "4567")
        self.assertEqual(enclosure.get(f"{{{SPARKLE}}}edSignature"), "abc123==")

    def test_newest_item_comes_first(self):
        first = add_item(EMPTY, "0.6.0", "42", "https://example.com/a.zip", SIG)
        second = add_item(first, "0.7.0", "50", "https://example.com/b.zip", SIG)
        versions = [i.findtext(f"{{{SPARKLE}}}shortVersionString") for i in self.items(second)]
        self.assertEqual(versions, ["0.7.0", "0.6.0"])

    def test_rejects_a_build_that_is_already_listed(self):
        once = add_item(EMPTY, "0.6.0", "42", "https://example.com/a.zip", SIG)
        with self.assertRaises(ValueError):
            add_item(once, "0.6.1", "42", "https://example.com/b.zip", SIG)

    def test_rejects_a_malformed_signature_line(self):
        with self.assertRaises(ValueError):
            add_item(EMPTY, "0.6.0", "42", "https://example.com/a.zip", "nonsense")

    def test_output_is_still_a_valid_sparkle_appcast_document(self):
        text = add_item(EMPTY, "0.6.0", "42", "https://example.com/a.zip", SIG)
        self.assertTrue(text.startswith('<?xml version="1.0" standalone="yes"?>'))
        self.assertIn("xmlns:sparkle", text)


if __name__ == "__main__":
    unittest.main()
