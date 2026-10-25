# Activer la liaison GitHub dans le SSO CNP

Diagnostic réel du 25 octobre 2026, en lecture : Keycloak 26.5.5, realm 3istor,
aucun Identity Provider (`GET identity-provider/instances` renvoie une liste vide).
Les clients account et account-console sont actifs. L’utilisateur réussit sa
connexion SSO, mais la route des comptes liés n’existe pas dans sa navigation.

Le HTTP 200 d’une page SPA et la présence d’une route dans le JavaScript ne
prouvent pas que la fonctionnalité est active. L’indicateur public non authentifié
isLinkedAccountsEnabled=false n’était pas une preuve suffisante non plus :
Keycloak le met également à false lorsqu’aucun utilisateur n’est connecté.
Le diagnostic repose donc sur la configuration d’administration réelle, lue
sans modifier de rôle, de compte, de provider ou de client.

## Proposition à valider par l’administrateur du SSO

Le fichier github-identity-provider.example.json est une proposition inactive :
il n’est pas référencé dans Kustomize et ne contient aucun secret réel.

Configuration du provider :

- realm : 3istor ; providerId et alias : github ; enabled : true ;
- linkOnly : true, pour la liaison à un compte CNP existant ;
- hideOnLoginScreen : true ; trustEmail : false ; storeToken : false ;
- pas de création ni de liaison automatique par simple égalité d’adresse email ;
- clientId / clientSecret : credentials OAuth de l’App GitHub choisie.

L’App CNP-Portal existe déjà et est installée sur 3-Istor. Le Client ID OAuth public
de cette App a été retrouvé en lecture ; le Client secret OAuth n’est pas présent
dans les configurations locales connues. La clé privée de l’App et le secret du
client CNP Keycloak ne remplacent pas ce secret OAuth GitHub.

1. Dans les paramètres de l’App GitHub choisie, ajouter ce callback exact :

       https://auth.3istor.com/realms/3istor/broker/github/endpoint

2. Récupérer/générer son Client secret OAuth et le stocker dans le gestionnaire
   de secrets, sans l’ajouter à Git ni l’envoyer dans une discussion.
3. Dans Keycloak → realm 3istor → Identity Providers → GitHub, créer le provider
   selon la proposition, avec le Client ID et ce secret. Ne pas modifier le
   browser flow, les clients existants ni les rôles utilisateur pour cette étape.
4. Vérifier avec un utilisateur réellement connecté que Comptes liés / Linked
   accounts apparaît et propose GitHub ; terminer le parcours OAuth de liaison.
   Ne pas conclure à partir d’un simple HTTP 200.
5. Après cette vérification, configurer dans le backend CMP :

       GITHUB_ACCOUNT_LINK_URL=https://auth.3istor.com/realms/3istor/account/account-security/linked-accounts

   Pour le CMP local, utiliser son backend/.env ignoré puis redémarrer. Pour un
   déploiement, passer la valeur via les variables du service après validation.
   Cette URL ne donne aucune autorisation : la fédération et les droits GitHub
   restent revérifiés avant l’enregistrement et avant chaque étape d’import.
6. Dans CMP Compte, rattacher l’installation CNP existante. Vérifier la concordance
   de l’ID GitHub et l’appartenance à l’organisation, puis les refus sans identité.

L’ajout du provider touche le SSO partagé et nécessite les credentials OAuth
manquants. Rien n’a été activé pendant le diagnostic ; aucun push n’a été effectué.
Le bouton CMP bloque et explique le prérequis tant que l’URL de liaison n’a pas
été configurée après validation du provider. Une identité déjà liée peut toujours
rattacher son installation après vérification, indépendamment de cette URL d’aide.

Sources : [GitHub dans Keycloak](https://www.keycloak.org/docs/latest/server_admin/index.html#_github),
[calcul du menu dans Keycloak 26.5.5](https://github.com/keycloak/keycloak/blob/26.5.5/services/src/main/java/org/keycloak/services/resources/account/AccountConsole.java).
