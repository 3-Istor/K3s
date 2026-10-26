#!/usr/bin/env python3
"""Check a saved Terraform plan before the initial GitHub broker activation.

Usage: terraform show -json saved.tfplan | python3 scripts/check_github_identity_plan.py
Plan JSON contains secrets: this program never logs input values.
"""
import argparse
import json
import sys

ADDRESS = 'module.github_account_linking[0].keycloak_oidc_github_identity_provider.github'


def check(plan, realm='3istor'):
    if not isinstance(plan, dict) or not isinstance(plan.get('resource_changes'), list):
        raise ValueError('A complete Terraform plan JSON is required')
    if plan.get('errored') or plan.get('complete') is False or plan.get('applyable') is False or plan.get('deferred_changes'):
        raise ValueError('The plan has errors or unresolved changes')
    if plan.get('resource_drift'):
        raise ValueError('Remote drift requires a separate review before activation')
    creates = []
    for resource in plan['resource_changes']:
        change = resource.get('change', {})
        actions = change.get('actions')
        if change.get('importing') or resource.get('previous_address'):
            raise ValueError('Imports and moves require a separate review')
        if actions in (['no-op'], ['read']):
            continue
        if resource.get('address') != ADDRESS or actions != ['create']:
            raise ValueError('Only creation of the reviewed GitHub broker is allowed')
        if resource.get('provider_name') != 'registry.terraform.io/keycloak/keycloak':
            raise ValueError('Unexpected provider')
        after = change.get('after', {})
        expected = {'realm': realm, 'alias': 'github', 'provider_id': 'github',
                    'enabled': True, 'link_only': True, 'hide_on_login_page': True,
                    'trust_email': False, 'store_token': False,
                    'add_read_token_role_on_create': False, 'github_json_format': True,
                    'default_scopes': 'user:email', 'sync_mode': 'IMPORT',
                    'base_url': 'https://github.com', 'api_url': 'https://api.github.com'}
        if any(after.get(key) != value for key, value in expected.items()):
            raise ValueError('The broker configuration differs from the account-linking contract')
        if after.get('extra_config'):
            raise ValueError('Unexpected custom broker configuration')
        if not after.get('client_id') or not after.get('client_secret'):
            raise ValueError('OAuth credentials are missing or unknown')
        if change.get('after_sensitive', {}).get('client_secret') is not True:
            raise ValueError('The OAuth secret must be marked sensitive')
        creates.append(resource)
    if len(creates) != 1:
        raise ValueError('Expected exactly one GitHub broker creation')
    for name, change in plan.get('output_changes', {}).items():
        if name != 'github_identity_provider_urls' and change.get('actions') != ['no-op']:
            raise ValueError('An unrelated output would change')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--realm', default='3istor')
    args = parser.parse_args()
    try:
        check(json.load(sys.stdin), args.realm)
    except (ValueError, TypeError, KeyError):
        # Do not print exception values: they could originate from the plan input.
        print('STOP: plan refused; inspect it securely for unrelated changes, drift or an invalid broker contract', file=sys.stderr)
        return 1
    print('OK: one account-linking GitHub broker creation; all other resources unchanged. No apply performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
