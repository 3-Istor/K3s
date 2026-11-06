"""Production CMP keeps optional import credentials absent until explicitly configured."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "k8s/config/arcl-cmp"
OAUTH = {"GITHUB_OAUTH_CLIENT_ID", "GITHUB_OAUTH_CLIENT_SECRET",
         "GITHUB_OAUTH_REDIRECT_URI", "GITHUB_OAUTH_TOKEN_KEY"}
IMPORT = {"IMPORT_WORKFLOW_REPO", "IMPORT_WORKFLOW_REF", "IMPORT_DISPATCH_WORKFLOW",
          "IMPORT_CHART_SHA", "IMPORT_WORKFLOW_SHA", "IMPORT_OIDC_AUDIENCE",
          "IMPORT_USER_AUDIENCE", "IMPORT_IMAGE_PREFIX", "IMPORT_MAX_IMAGE_BYTES",
          "IMPORT_DOMAIN", "IMPORT_ALLOWED_PROJECT", "IMPORT_CALLBACK_URL",
          "IMPORT_ARGOCD_URL", "IMPORT_ARGOCD_TOKEN"}


class CMPImportConfigTests(unittest.TestCase):
    def test_new_credentials_are_optional_and_cannot_implicitly_enable_import(self):
        values = yaml.safe_load((CONFIG / "cmp-values.yaml").read_text())
        self.assertEqual(values["env"]["backend"]["IMPORT_ENABLED"], "false")
        fields = {item["name"]: item for item in values["extraEnv"]}
        self.assertNotIn("IMPORT_ENABLED", fields)
        for names, secret in ((OAUTH, "arcl-cmp-github-oauth"),
                              (IMPORT, "arcl-cmp-repository-import")):
            for name in names:
                with self.subTest(name=name):
                    ref = fields[name]["valueFrom"]["secretKeyRef"]
                    self.assertEqual(ref["name"], secret)
                    self.assertEqual(ref["key"], name.lower().replace("_", "-"))
                    self.assertIs(ref["optional"], True)

    def test_opt_in_secrets_match_mappings_and_do_not_change_existing_vault_resources(self):
        base = yaml.safe_load((CONFIG / "kustomization.yaml").read_text())
        self.assertFalse(any("optional/" in resource for resource in base["resources"]))
        existing = {item["metadata"]["name"] for item in yaml.safe_load_all((CONFIG / "secrets.yaml").read_text())}
        for filename, names, secret, path in (
            ("github-oauth-vaultsecret.yaml", OAUTH, "arcl-cmp-github-oauth", "kvv2/arcl-cmp/github-oauth"),
            ("repository-import-vaultsecret.yaml", IMPORT, "arcl-cmp-repository-import", "kvv2/arcl-cmp/repository-import"),
        ):
            document = yaml.safe_load((CONFIG / "optional" / filename).read_text())
            self.assertEqual(document["kind"], "VaultSecret")
            self.assertEqual(document["metadata"], {"name": secret, "namespace": "arcl-cmp"})
            self.assertNotIn(secret, existing)
            self.assertEqual(document["spec"]["path"], path)
            self.assertEqual(document["spec"]["vaultRole"], "arcl-cmp-role")
            self.assertEqual(set(document["spec"]["keys"]), {name.lower().replace("_", "-") for name in names})


if __name__ == "__main__":
    unittest.main()
