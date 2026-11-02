"""Check the actual import account ConfigMaps; native Argo checks stay local."""
import csv
import os
from pathlib import Path
import shutil
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "k8s/config/argocd/patch-argocd-rbac-cm.yaml"
ARGOCD = os.environ.get("ARGOCD_BIN", "argocd")


class ImportRBACTests(unittest.TestCase):
    def test_account_and_permissions_are_limited_to_import_reads_and_scoped_repositories(self):
        account = yaml.safe_load((ROOT / "k8s/config/argocd/patch-argocd-cm.yaml").read_text())
        self.assertEqual(account["data"]["accounts.cmp-import"], "apiKey")
        config = yaml.safe_load(POLICY.read_text())
        self.assertEqual(config["kind"], "ConfigMap")
        self.assertEqual(config["metadata"]["name"], "argocd-rbac-cm")
        self.assertEqual(config["data"]["policy.default"], "role:denied")
        rows = [tuple(value.strip() for value in row) for row in csv.reader(
            line for line in config["data"]["policy.csv"].splitlines()
            if line.strip() and not line.lstrip().startswith("#"))]
        self.assertIn(("g", "cmp-import", "role:cmp-import"), rows)
        self.assertEqual({row for row in rows if len(row) > 1 and row[1] == "role:cmp-import"}, {
            ("p", "role:cmp-import", "applicationsets", "get", "*/cnp-apps", "allow"),
            ("p", "role:cmp-import", "applicationsets", "get", "*/cnp-image-updaters", "allow"),
            ("p", "role:cmp-import", "applications", "get", "*/*", "allow"),
            ("p", "role:cmp-import", "repositories", "get", "*/https://github.com/*", "allow"),
            ("p", "role:cmp-import", "repositories", "create", "*/https://github.com/*", "allow"),
        })

    @unittest.skipUnless(shutil.which(ARGOCD), "Set ARGOCD_BIN to the reviewed Argo CD CLI for native offline RBAC checks")
    def test_native_argo_policy_allows_project_repositories_and_denies_global_or_unrelated_access(self):
        common = ["--policy-file", str(POLICY), "--config", os.devnull,
                  "--kubeconfig", os.devnull, "--server", "http://127.0.0.1:9"]
        environment = {name: os.environ[name] for name in ("HOME", "USER") if name in os.environ}
        environment.update({"PATH": os.defpath, "KUBECONFIG": os.devnull})
        valid = subprocess.run([ARGOCD, "admin", "settings", "rbac", "validate", *common],
                               capture_output=True, text=True, timeout=20, env=environment)
        self.assertEqual(valid.returncode, 0, valid.stdout + valid.stderr)
        cases = [
            ("get", "repositories", "tenant/https://github.com/external/source.git", True),
            ("create", "repositories", "tenant/https://github.com/external/source.git", True),
            ("create", "repositories", "https://github.com/external/source.git", False),
            ("get", "repositories", "https://github.com/external/source.git", False),
            ("create", "repositories", "tenant/https://gitlab.com/external/source.git", False),
            ("create", "repositories", "tenant/ssh://git@github.com/external/source.git", False),
            ("update", "repositories", "tenant/https://github.com/external/source.git", False),
            ("delete", "repositories", "tenant/https://github.com/external/source.git", False),
            ("get", "applications", "tenant/imported-app", True),
            ("sync", "applications", "tenant/imported-app", False),
            ("create", "applications", "tenant/imported-app", False),
            ("get", "applicationsets", "default/cnp-apps", True),
            ("get", "applicationsets", "default/unrelated", False),
            ("get", "clusters", "https://kubernetes.default.svc", False),
        ]
        for action, resource, target, allowed in cases:
            with self.subTest(action=action, resource=resource, target=target):
                result = subprocess.run([ARGOCD, "admin", "settings", "rbac", "can",
                                         "cmp-import", action, resource, target, *common],
                                        capture_output=True, text=True, timeout=20, env=environment)
                self.assertEqual(result.returncode, 0 if allowed else 1, result.stdout + result.stderr)
                self.assertEqual(result.stdout.strip(), "Yes" if allowed else "No")


if __name__ == "__main__":
    unittest.main()
