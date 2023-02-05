"""
Copyright (c) 2008-2022 synodriver <synodriver@gmail.com>
"""
import os
from unittest import TestCase
import sys

sys.path.append('.')
from pyrucfs import INODE_DIRECTORY, INODE_FILE, INODE_SYMLINK, Context, normalize_path


def path_to_str(p):
    """
    directory or file or symlink
    """
    if p.type == INODE_DIRECTORY:
        return "directory"
    elif p.type == INODE_FILE:
        return "file"
    elif p.type == INODE_SYMLINK:
        return "symlink"


class TestAll(TestCase):
    def setUp(self) -> None:
        with open(f"{os.path.dirname(__file__)}/rucfs.img", "rb") as f:
            self.ctx = Context.load(f.read())

    def tearDown(self) -> None:
        pass

    def test_enumpath(self):
        for p in self.ctx.enumerate_path(b"/"):
            print(p.name, path_to_str(p))

    def test_exist(self):
        self.assertTrue(self.ctx.exist(b"/img"))
        self.assertTrue(self.ctx.exist(b"/.gitignore"))
        # self.assertTrue(self.ctx.exist(b'/.gitignore'))
        self.assertTrue(self.ctx.exist(b"/src/rucfs.c"))
        self.assertFalse(self.ctx.exist(b"/src/none"))

    def test_rootdir(self):
        print("haha",self.ctx.rootdir.item_count)

    def test_fopen(self):
        file = self.ctx.fopen(b'/.git')
        print("file: ",bytes(file))

    def test_normpath(self):
        buf = bytearray(20)
        up = normalize_path(buf, b"//fff//dd////d39.bb/", False)
        print(buf)
        self.assertEqual(up, 14)
        self.assertEqual(bytes(buf[:14]), b'/fff/dd/d39.bb')
        up = normalize_path(buf, b"//fff//dd////d39.bb/", True)
        self.assertEqual(up, 16)
        self.assertEqual(bytes(buf[:16]), b'/fff/dd/d39.bb//')


if __name__ == "__main__":
    import unittest

    unittest.main()
