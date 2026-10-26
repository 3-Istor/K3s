# Liaison GitHub : configuration Terraform de K3s

Le realm 3istor, ses clients, ses flows et ses rôles sont gérés dans `terraform/`.
Le fournisseur GitHub doit être géré dans ce même state, plutôt qu’être ajouté
manuellement dans la console. Le diagnostic des 25 et 26 octobre 2026, en lecture,
a confirmé l’absence de fournisseur d’identité sur le realm et dans le Terraform.

## Code prêt à relire

- `terraform/github_identity_provider.tf` : intégration au realm existant ;
- `terraform/modules/github-identity-provider/` : ressource native
  `keycloak_oidc_github_identity_provider`, version déjà épinglée 5.9.0 ;
- `terraform/variables.tf` et `secrets_variables.tfvars.example` : activation
  explicite, Client ID OAuth et Client secret sensible ;
- `scripts/check_github_identity_plan.py` : contrôle du plan avant activation.

Le flag d’activation est false par défaut : publier la branche n’active pas le
SSO. Le module impose link_only et hide_on_login_page, refuse les credentials
vides, ne fait pas confiance aux emails du fournisseur et ne conserve pas les
tokens OAuth. Il ne modifie aucun flow, client, rôle ni groupe existant.
Sa destruction est protégée. L’ancien exemple JSON inactif est remplacé par ce
module : il ne faut pas créer le provider par une autre voie puis gérer deux états.

## Préparation OAuth par l’administrateur GitHub

Une App GitHub ou une OAuth App dédiée à l’identité peut être utilisée. Les accès
aux repos continuent d’utiliser l’installation CNP-Portal déjà approuvée. Les deux
identifiants OAuth doivent appartenir à la même application.

1. Ajouter le callback exact :

       https://auth.3istor.com/realms/3istor/broker/github/endpoint

2. Fournir le Client ID et le Client secret OAuth par un fichier local protégé ou
   le gestionnaire de secrets. Ne pas les confondre avec la clé privée GitHub App
   ou le secret du client CNP Keycloak. Le secret ne doit pas entrer dans Git.
3. Si CNP-Portal est réutilisée, activer sa permission utilisateur **Email
   addresses: read**. Le contrôle du 26 octobre ne la trouvait pas dans ses
   métadonnées. Une OAuth App classique utilise le scope `user:email`.

## Plan dans l’environnement Terraform habituel de l’équipe

Le state racine gère aussi Vault et Cloudflare. Utiliser les vraies variables et
les accès S3 habituels de l’équipe ; ne pas remplir les autres secrets par des
valeurs factices. Sur cette machine aucun fichier racine de variables privées ni
profil AWS 3-istor n’a été trouvé ; aucun plan réel du state n’a donc été exécuté.

Définir les variables par le gestionnaire de secrets/l’environnement sécurisé :

    TF_VAR_github_identity_provider_enabled=true
    TF_VAR_github_oauth_client_id=<client ID OAuth approuvé>
    TF_VAR_github_oauth_client_secret=<secret OAuth protégé>

Préparer un plan complet avec le fichier habituel de l’équipe, sans apply :

```sh
umask 077
plan_dir=$(mktemp -d)
cd terraform
terraform init -input=false -lockfile=readonly
terraform plan -input=false -var-file=<fichier habituel> -out="$plan_dir/github.tfplan"
set -o pipefail
terraform show -json "$plan_dir/github.tfplan" | python3 ../scripts/check_github_identity_plan.py
```

Le JSON du plan contient des secrets en clair : le transmettre au contrôle par
stdin, sans le publier dans Git ou dans une discussion. La validation autorise
exactement une création du broker GitHub attendu. Toute modification d’un autre
objet, remplacement, suppression, import, déplacement, drift ou plan incomplet
bloque la suite. Corriger et refaire valider le plan avant de continuer.

Faire approuver le plan concret. Après autorisation seulement, appliquer **ce plan
enregistré**, puis vérifier la configuration du provider en lecture. Aucun apply
réel n’a été exécuté pendant le développement du module.

Si un fournisseur github existe déjà au moment du plan, arrêter : il doit être
repris proprement dans ce state après revue. Ne pas recréer le fournisseur ni
forcer son remplacement. Son adresse Terraform attendue est :

    module.github_account_linking[0].keycloak_oidc_github_identity_provider.github

## Recette connectée

1. Avec un utilisateur connecté, vérifier que Linked accounts / Comptes liés
   apparaît et propose GitHub. Un HTTP 200 de la SPA ne suffit pas : l’ancienne
   route était servie mais indisponible en l’absence de fournisseur.
2. Configurer le backend CMP local avec l’URL renvoyée par `account_link_url` :

       GITHUB_ACCOUNT_LINK_URL=https://auth.3istor.com/realms/3istor/account/account-security/linked-accounts

   Redémarrer CMP. Ce réglage propose le lien ; il ne donne aucun droit.
3. L’utilisateur termine lui-même OAuth dans les comptes liés puis clique sur
   Rattacher l’installation CNP existante. Vérifier la correspondance des IDs
   GitHub et les droits ; ne pas écrire de lien de compte par une API admin.
4. Continuer la recette d’import seulement après toutes les autres validations :
   branches/CI/chart publiés, callback HTTPS, Argo et registre joetest compatibles.

## Vérifications déjà effectuées

La configuration racine valide sans backend, le module valide et ses quatre
tests natifs avec provider simulé passent. Les tests K3s couvrent aussi le refus
des plans dangereux. Aucun secret réel dans les tests ni modification de SSO.

Source du provider :
https://github.com/keycloak/terraform-provider-keycloak/blob/v5.9.0/docs/resources/oidc_github_identity_provider.md
