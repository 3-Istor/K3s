import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('github_plan', ROOT/'scripts/check_github_identity_plan.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def proposal():
    return {'complete': True, 'resource_changes': [{
        'address': guard.ADDRESS, 'provider_name': 'registry.terraform.io/keycloak/keycloak',
        'change': {'actions': ['create'], 'after_sensitive': {'client_secret': True},
            'after': {'realm': '3istor', 'alias': 'github', 'provider_id': 'github',
                'enabled': True, 'link_only': True, 'hide_on_login_page': True,
                'trust_email': False, 'store_token': False, 'add_read_token_role_on_create': False,
                'github_json_format': True, 'default_scopes': 'user:email', 'sync_mode': 'IMPORT',
                'base_url': 'https://github.com', 'api_url': 'https://api.github.com',
                'client_id': 'test-client', 'client_secret': 'test-secret-never-print'}}
    }]}


class GithubIdentityPlanTests(unittest.TestCase):
    def test_only_the_reviewed_broker_can_be_created(self):
        guard.check(proposal())

    def test_unrelated_mutations_deletions_and_replacements_are_refused(self):
        for address, actions in [('keycloak_realm.kube_lab', ['update']), (guard.ADDRESS, ['delete']),
                                 (guard.ADDRESS, ['delete', 'create'])]:
            plan = proposal()
            change = copy.deepcopy(plan['resource_changes'][0])
            change['address'], change['change']['actions'] = address, actions
            plan['resource_changes'].append(change)
            with self.subTest(address=address, actions=actions), self.assertRaises(ValueError):
                guard.check(plan)

    def test_unsafe_authentication_and_missing_credentials_are_refused(self):
        for field, value in [('link_only', False), ('trust_email', True), ('store_token', True),
                             ('realm', 'master'), ('client_secret', None), ('default_scopes', 'repo'),
                             ('api_url', 'https://other.example.org'), ('extra_config', {'unexpected': 'override'})]:
            plan = proposal()
            plan['resource_changes'][0]['change']['after'][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                guard.check(plan)

    def test_drift_imports_and_incomplete_plans_are_refused(self):
        for changes in [{'complete': False}, {'resource_drift': [{'address': 'keycloak_realm.kube_lab'}]},
                        {'deferred_changes': [{}]}, {'errored': True}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                guard.check({**proposal(), **changes})
        plan = proposal()
        plan['resource_changes'][0]['change']['importing'] = {'id': '3istor/github'}
        with self.assertRaises(ValueError): guard.check(plan)

    def test_unrelated_outputs_and_unprotected_secrets_are_refused(self):
        plan = proposal()
        plan['output_changes'] = {'openid_client_secret': {'actions': ['update']}}
        with self.assertRaises(ValueError): guard.check(plan)
        plan = proposal()
        plan['resource_changes'][0]['change']['after_sensitive']['client_secret'] = False
        with self.assertRaises(ValueError): guard.check(plan)


if __name__ == '__main__': unittest.main()
