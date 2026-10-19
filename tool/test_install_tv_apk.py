import unittest
from install_tv_apk import PACKAGE, validate_update
class InstallerTest(unittest.TestCase):
    def test_accepts_same_signed_monotonic_update(self):
        validate_update(PACKAGE,1003,1002,'same','same',['armeabi-v7a'],['armeabi-v7a'])
    def test_rejects_universal_downgrade(self):
        with self.assertRaises(ValueError): validate_update(PACKAGE,3,1002,'same','same',['armeabi-v7a'],['armeabi-v7a'])
    def test_rejects_signature_mismatch(self):
        with self.assertRaises(ValueError): validate_update(PACKAGE,1003,1002,'new','old',['armeabi-v7a'],['armeabi-v7a'])
    def test_rejects_wrong_abi(self):
        with self.assertRaises(ValueError): validate_update(PACKAGE,1003,1002,'same','same',['arm64-v8a'],['armeabi-v7a'])
    def test_rejects_other_package(self):
        with self.assertRaises(ValueError): validate_update('another.app',1003,1002,'same','same',['armeabi-v7a'],['armeabi-v7a'])
if __name__ == '__main__': unittest.main()
