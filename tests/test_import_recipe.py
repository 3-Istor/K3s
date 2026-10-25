"""The branch recipe must select only its one project from the test registry."""

import fnmatch
import importlib.util
from pathlib import Path
import unittest

import yaml

from test_application_import import render

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("recipe", ROOT / "scripts/render_import_recipe.py")
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)


class ImportRecipeTests(unittest.TestCase):
    def test_other_projects_keep_following_main_without_duplicate_test_record(self):
        for filename in ["applicationset-projects.yaml", "applicationset-apps.yaml", "applicationset-image-updaters.yaml"]:
            for document in yaml.safe_load_all((ROOT / "k8s/config/argocd" / filename).read_text()):
                generators = recipe.recipe_generators(document["spec"]["generators"], "joetest", "import-fichier-joe-raph")
                selected = []
                for generator in generators:
                    for git in recipe.git_nodes(generator):
                        for project in ["joetest", "sandbox", "production"]:
                            path = f"registry/projects/{project}.yaml"
                            includes = any(fnmatch.fnmatch(path, item["path"]) for item in git["files"] if not item.get("exclude"))
                            excludes = any(fnmatch.fnmatch(path, item["path"]) for item in git["files"] if item.get("exclude"))
                            if includes and not excludes:
                                selected.append((project, git["revision"]))
                self.assertCountEqual(selected, [("joetest", "import-fichier-joe-raph"), ("sandbox", "main"), ("production", "main")])

    def test_only_test_project_uses_the_reviewed_updater_chart(self):
        operations = yaml.safe_load((ROOT / "k8s/overlays/import-joetest/cnp-image-updaters.patch.yaml").read_text())
        expression = next(item["value"] for item in operations if item["path"] == "/spec/template/spec/source/targetRevision")
        pinned = next(item["value"]["cnp.3istor.com/import-test-k3s-revision"] for item in operations if item["path"] == "/metadata/annotations")
        self.assertEqual(render(expression, {"metadata": {"name": "joetest"}}), pinned)
        self.assertEqual(render(expression, {"metadata": {"name": "production"}}), "HEAD")


if __name__ == "__main__":
    unittest.main()
