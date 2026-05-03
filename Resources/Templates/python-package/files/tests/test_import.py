import unittest

from {{package_name}} import name


class PackageTests(unittest.TestCase):
    def test_name(self) -> None:
        self.assertEqual(name(), "{{project_name}}")


if __name__ == "__main__":
    unittest.main()
