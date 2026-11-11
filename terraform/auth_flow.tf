# =============================================================================
# ROLES & GROUP MAPPINGS
# =============================================================================

# Role required to access 3-Istor Apps
resource "keycloak_role" "openid_client_access" {
  realm_id    = keycloak_realm.kube_lab.id
  name        = "openid_client_access"
  description = "Role required to access 3-Istor Apps"
}

# Authorize the 'member' group
resource "keycloak_group_roles" "member_app_access" {
  realm_id = keycloak_realm.kube_lab.id
  group_id = keycloak_group.member.id
  role_ids = [keycloak_role.openid_client_access.id]
}

# =============================================================================
# PHASE 0: ROOT AUTHENTICATION FLOW
# =============================================================================

resource "keycloak_authentication_flow" "browser_openid_client" {
  realm_id    = keycloak_realm.kube_lab.id
  alias       = "Browser-3-istor-Login-v4"
  description = "Complete Flow: Authentication Wrapper followed by RBAC Wrapper"
}

# =============================================================================
# PHASE 1: LOGIN WRAPPER
# Groups every authentication method.
# If ANY method succeeds, the user is authenticated.
# =============================================================================

resource "keycloak_authentication_subflow" "login_wrapper" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_openid_client.alias
  alias             = "3-istor-login-wrapper"
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 10
}

# =============================================================================
# PHASE 1.1: SSO AUTHENTICATION METHODS
# =============================================================================

# Checks if the user already has a valid Keycloak SSO cookie.
# If yes, login is transparent.
resource "keycloak_authentication_execution" "cookie" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.login_wrapper.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

# Checks for Kerberos ticket (Active Directory SSO)
resource "keycloak_authentication_execution" "kerberos" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.login_wrapper.alias
  authenticator     = "auth-spnego"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

# Redirect to external identity provider if configured
resource "keycloak_authentication_execution" "idp_redirector" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.login_wrapper.alias
  authenticator     = "identity-provider-redirector"
  requirement       = "ALTERNATIVE"
  priority          = 30
}

# =============================================================================
# PHASE 1.2: MANUAL LOGIN FALLBACK
# If no SSO method worked, fallback to username/password login
# =============================================================================

resource "keycloak_authentication_subflow" "forms_wrapper" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.login_wrapper.alias
  alias             = "3-istor-forms-wrapper"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 40
}

# Standard Keycloak login page
resource "keycloak_authentication_execution" "username_password" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.forms_wrapper.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

# =============================================================================
# PHASE 1.3: MULTI FACTOR AUTHENTICATION
# Triggered after successful username/password authentication. Mandatory for all.
# =============================================================================

resource "keycloak_authentication_subflow" "mandatory_otp" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.forms_wrapper.alias
  alias             = "3-istor-mandatory-otp"
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 20
}

# Ask for OTP token. If the user doesn't have one configured,
# Keycloak will automatically force them to set it up (QR Code screen).
resource "keycloak_authentication_execution" "otp_form" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.mandatory_otp.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 10
}
# =============================================================================
# PHASE 2: RBAC WRAPPER
# The user is authenticated at this point.
# We now verify if the user is authorized to access the application.
# =============================================================================

resource "keycloak_authentication_subflow" "rbac_deny_wrapper" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_openid_client.alias
  alias             = "3-istor-rbac-deny-wrapper"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

# Check if user has required role
resource "keycloak_authentication_execution" "condition_role" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.rbac_deny_wrapper.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "condition_role_config" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.condition_role.id
  alias        = "deny-if-not-3-istor-access"

  config = {
    condUserRole = keycloak_role.openid_client_access.name
    negate       = "true"
  }
}

# If user does NOT have required role -> deny access
resource "keycloak_authentication_execution" "deny_access" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.rbac_deny_wrapper.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}

# =============================================================================
# BROWSER FLOW v5: PASSKEY FIRST
# The username/password form also takes a passkey (passwordless_passkeys_enabled on the
# realm). A passkey with user verification is already two factors, so it skips the OTP.
# The password path always ends with the OTP form: a user without OTP sets it up before the
# session opens, so a password alone never logs in. v4 stays defined until v5 is validated,
# so a rollback is only the client bindings.
# =============================================================================

resource "keycloak_authentication_flow" "browser_v5" {
  realm_id    = keycloak_realm.kube_lab.id
  alias       = "Browser-3-istor-Login-v5"
  description = "Passkey first, password plus OTP as fallback, then RBAC"
}

resource "keycloak_authentication_subflow" "v5_login" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_v5.alias
  alias             = "3-istor-v5-login"
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution" "v5_cookie" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_login.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "v5_forms" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_login.alias
  alias             = "3-istor-v5-forms"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "v5_username_password" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_forms.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_subflow" "v5_second_factor" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_forms.alias
  alias             = "3-istor-v5-second-factor"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "v5_condition_no_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_second_factor.alias
  authenticator     = "conditional-credential"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v5_condition_no_passkey" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v5_condition_no_passkey.id
  alias        = "v5-otp-unless-passkey"
  config = {
    credentials = "webauthn-passwordless"
    included    = "false"
  }
}

# REQUIRED, not ALTERNATIVE with other second factors: alternatives that the user has not
# configured fail with "credential setup required", while a REQUIRED OTP form sends a user
# without OTP to the QR code setup.
resource "keycloak_authentication_execution" "v5_otp" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_second_factor.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_subflow" "v5_rbac" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_v5.alias
  alias             = "3-istor-v5-rbac"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "v5_condition_role" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_rbac.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v5_condition_role" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v5_condition_role.id
  alias        = "v5-deny-if-not-3-istor-access"
  config = {
    condUserRole = keycloak_role.openid_client_access.name
    negate       = "true"
  }
}

resource "keycloak_authentication_execution" "v5_deny_access" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v5_rbac.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}

# =============================================================================
# BROWSER FLOW v6: LEVELS OF AUTHENTICATION (STEP-UP)
# LoA 1 (acr "silver"): password plus OTP, or a passkey.
# LoA 2 (acr "gold"): a passkey used in this authentication. Clients ask for it with
# acr_values=gold, usually with max_age, before a destructive action.
# Members of a group holding the passkey-required role (infra, security-auditor) must use a
# passkey even at LoA 1. Their acr stays "silver" unless gold is asked: the passkey is a
# login requirement for them, not a standing step-up.
# v5 stays defined: rolling back is only the client bindings.
# =============================================================================

resource "keycloak_role" "passkey_required" {
  realm_id    = keycloak_realm.kube_lab.id
  name        = "passkey-required"
  description = "Must log in with a passkey (browser flow v6)"
}

# Not exhaustive: roles added to these groups elsewhere stay.
resource "keycloak_group_roles" "passkey_required" {
  for_each = {
    infra            = keycloak_group.infra.id
    security-auditor = keycloak_group.security_auditor.id
  }
  realm_id   = keycloak_realm.kube_lab.id
  group_id   = each.value
  role_ids   = [keycloak_role.passkey_required.id]
  exhaustive = false
}

resource "keycloak_authentication_flow" "browser_v6" {
  realm_id    = keycloak_realm.kube_lab.id
  alias       = "Browser-3-istor-Login-v6"
  description = "Levels of authentication: 1 password plus OTP or passkey, 2 passkey; then RBAC"
}

resource "keycloak_authentication_subflow" "v6_login" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_v6.alias
  alias             = "3-istor-v6-login"
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 10
}

# The cookie does not satisfy a request for a level the session has not reached (or reached
# longer ago than the level's max age): the user then goes through the levels below.
resource "keycloak_authentication_execution" "v6_cookie" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_login.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "v6_levels" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_login.alias
  alias             = "3-istor-v6-levels"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

# --- LoA 1 -------------------------------------------------------------------

resource "keycloak_authentication_subflow" "v6_loa1" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_levels.alias
  alias             = "3-istor-v6-loa1"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 10
}

resource "keycloak_authentication_execution" "v6_loa1_condition" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa1.alias
  authenticator     = "conditional-level-of-authentication"
  requirement       = "REQUIRED"
  priority          = 10
}

# Max age of LoA 1 = the SSO idle timeout, so the cookie keeps working as in v5.
resource "keycloak_authentication_execution_config" "v6_loa1_condition" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_loa1_condition.id
  alias        = "v6-loa1"
  config = {
    "loa-condition-level" = "1"
    "loa-max-age"         = "36000"
  }
}

resource "keycloak_authentication_execution" "v6_username_password" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa1.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_subflow" "v6_otp" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa1.alias
  alias             = "3-istor-v6-otp"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 30
}

resource "keycloak_authentication_execution" "v6_otp_condition" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_otp.alias
  authenticator     = "conditional-credential"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v6_otp_condition" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_otp_condition.id
  alias        = "v6-otp-unless-passkey"
  config = {
    credentials = "webauthn-passwordless"
    included    = "false"
  }
}

# Same as v5: REQUIRED so a user without OTP is sent to the QR code setup.
resource "keycloak_authentication_execution" "v6_otp" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_otp.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 20
}

# An admin who came in with password plus OTP still has to present a passkey. The OTP runs
# first on purpose: an admin without a passkey registers one only after the second factor,
# so a stolen password alone cannot enrol the attacker's passkey.
resource "keycloak_authentication_subflow" "v6_admin_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa1.alias
  alias             = "3-istor-v6-admin-passkey"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 40
}

resource "keycloak_authentication_execution" "v6_admin_condition_role" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_admin_passkey.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v6_admin_condition_role" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_admin_condition_role.id
  alias        = "v6-admin-if-passkey-required"
  config = {
    condUserRole = keycloak_role.passkey_required.name
    negate       = "false"
  }
}

resource "keycloak_authentication_execution" "v6_admin_condition_no_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_admin_passkey.alias
  authenticator     = "conditional-credential"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_execution_config" "v6_admin_condition_no_passkey" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_admin_condition_no_passkey.id
  alias        = "v6-admin-unless-passkey"
  config = {
    credentials = "webauthn-passwordless"
    included    = "false"
  }
}

resource "keycloak_authentication_execution" "v6_admin_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_admin_passkey.alias
  authenticator     = "webauthn-authenticator-passwordless"
  requirement       = "REQUIRED"
  priority          = 30
}

# --- LoA 2 -------------------------------------------------------------------

resource "keycloak_authentication_subflow" "v6_loa2" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_levels.alias
  alias             = "3-istor-v6-loa2"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "v6_loa2_condition" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa2.alias
  authenticator     = "conditional-level-of-authentication"
  requirement       = "REQUIRED"
  priority          = 10
}

# Must not exceed the CMP's STEP_UP_MAX_AGE, or a request for gold within this window is
# answered from the cookie with an auth_time the CMP then refuses.
resource "keycloak_authentication_execution_config" "v6_loa2_condition" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_loa2_condition.id
  alias        = "v6-loa2"
  config = {
    "loa-condition-level" = "2"
    "loa-max-age"         = "300"
  }
}

# A first login that asks for gold and already used a passkey at LoA 1 is not asked twice.
resource "keycloak_authentication_subflow" "v6_loa2_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa2.alias
  alias             = "3-istor-v6-loa2-passkey"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "v6_loa2_condition_no_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa2_passkey.alias
  authenticator     = "conditional-credential"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v6_loa2_condition_no_passkey" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_loa2_condition_no_passkey.id
  alias        = "v6-loa2-unless-passkey"
  config = {
    credentials = "webauthn-passwordless"
    included    = "false"
  }
}

# A user without a passkey is sent to register one here, behind a session that already
# passed LoA 1 with password plus OTP.
resource "keycloak_authentication_execution" "v6_loa2_passkey" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_loa2_passkey.alias
  authenticator     = "webauthn-authenticator-passwordless"
  requirement       = "REQUIRED"
  priority          = 20
}

# --- RBAC (same as v5) ---------------------------------------------------------

resource "keycloak_authentication_subflow" "v6_rbac" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_flow.browser_v6.alias
  alias             = "3-istor-v6-rbac"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "v6_condition_role" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_rbac.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "v6_condition_role" {
  realm_id     = keycloak_realm.kube_lab.id
  execution_id = keycloak_authentication_execution.v6_condition_role.id
  alias        = "v6-deny-if-not-3-istor-access"
  config = {
    condUserRole = keycloak_role.openid_client_access.name
    negate       = "true"
  }
}

resource "keycloak_authentication_execution" "v6_deny_access" {
  realm_id          = keycloak_realm.kube_lab.id
  parent_flow_alias = keycloak_authentication_subflow.v6_rbac.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}

# acr claim <-> level. Set per client because the realm-wide map is not exposed by the
# provider as a typed field; both clients bound to v6 carry the same map.
locals {
  acr_loa_map = jsonencode({ silver = 1, gold = 2 })
}
