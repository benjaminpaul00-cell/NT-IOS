# Compiler NecroTube 1.1 (3) et préparer TestFlight sans Mac physique

## Ce que fait le workflow

Le workflow `.github/workflows/ios-build.yml` utilise le runner hébergé GitHub `xcode-27` sur macOS/Apple Silicon. Le projet cible déjà iOS 27 et utilise des réglages Xcode 27 ; aucune réduction de version minimale n'est appliquée. L'iPhone de test doit donc exécuter **iOS 27 ou ultérieur**. Les minutes macOS d'un dépôt privé consomment le quota GitHub Actions du compte.

La validation se lance sur un push vers `main` ou `ci/**`, une pull request vers `main`, ou manuellement. Elle ne demande aucun secret Apple. Elle vérifie les versions et les 11 langues, valide les fichiers `.strings` avec `plutil`, résout les dépendances verrouillées, compile Debug puis Release pour un appareil iOS générique sans signature et inspecte le bundle réellement produit. Les journaux et les résultats Xcode sont conservés pendant sept jours. Il n'y a pas de cible de tests automatisés dans ce projet : il s'agit d'une compilation et de contrôles du bundle, pas d'un test d'interface sur iPhone.

Le schéma partagé `NecroTubeXcode` est versionné pour rendre le projet utilisable sur un runner vierge. La seule dépendance Swift Package directe est Firebase iOS SDK, verrouillée en 13.0.1 dans `Package.resolved` avec 12 dépendances transitives. Le fichier de verrouillage doit rester inchangé. Les vérifications de signatures/empreintes Swift Package et les contrôles de sécurité Xcode ne sont pas contournés. Le projet référence Firebase sans déclarer de produits Firebase liés à la cible ; les imports existants sont conditionnels à `canImport`. La CI conserve exactement cette intégration et n'active pas de nouvelle fonctionnalité Analytics.

## Lancer la validation depuis GitHub

1. Ouvrir `https://github.com/benjaminpaul00-cell/NT-IOS`.
2. Intégrer la branche contenant ces fichiers à `main` après revue. Ne pas remplacer les corrections 1.1 (3) et de localisation déjà présentes. Un push de la branche `ci/**` permet déjà une première compilation, avant fusion.
3. Ouvrir **Actions**. Si GitHub le demande, activer les workflows pour ce dépôt ; ne pas modifier les règles de protection ou les permissions de sécurité pour contourner un échec.
4. Sélectionner **NecroTube iOS 1.1 (3)**, puis **Run workflow**.
5. Choisir `main`, laisser **deploy_testflight** décoché et cliquer sur **Run workflow**. Le bouton manuel apparaît une fois le workflow présent sur la branche par défaut.
6. Ouvrir le job **Validate unsigned iOS build**. Vérifier que Debug, Release et les contrôles du bundle réussissent. En cas d'échec, télécharger l'artefact `ios-validation-<run_id>-<attempt>` et examiner les logs.

Une app compilée sans signature ne s'installe pas sur un iPhone. La validation n'effectue aucun envoi vers Apple.

## Informations Apple nécessaires — GitHub Secrets uniquement

Un abonnement Apple Developer Program actif et la fiche App Store Connect existante de NecroTube sont nécessaires. L'identifiant de bundle doit rester `com.corticalabs.NecroTubeXcode`.

Créer un environnement GitHub nommé `testflight` dans **Settings → Environments**. Le limiter à `main` et conserver les protections existantes ; un approbateur peut être ajouté si le plan GitHub le permet. Ajouter les secrets suivants dans cet environnement via **Add environment secret**. Des Repository Secrets peuvent aussi fournir ces valeurs, mais l'environnement restreint leur accès au job de distribution.

| Nom exact du secret | Valeur attendue |
| --- | --- |
| `APPLE_DISTRIBUTION_P12_BASE64` | Fichier `.p12` encodé en Base64 sur une seule ligne, contenant le certificat **Apple Distribution et sa clé privée** |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Mot de passe non vide protégeant ce `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Profil `.mobileprovision` **App Store Connect** pour le bundle exact, signé avec le certificat correspondant, encodé en Base64 sur une seule ligne |
| `KEYCHAIN_PASSWORD` | Mot de passe aléatoire non vide pour le trousseau temporaire du runner |
| `APPLE_TEAM_ID` | Team ID de l'équipe Apple ayant le certificat, le profil et l'application ; doit correspondre au projet existant |
| `ASC_KEY_ID` | Key ID d'une **clé API d'équipe App Store Connect** |
| `ASC_ISSUER_ID` | Issuer ID UUID de cette équipe App Store Connect |
| `ASC_PRIVATE_KEY_P8` | Contenu PEM complet du fichier `AuthKey_<KEY_ID>.p8`, avec ses lignes BEGIN/END et ses retours à la ligne ; **pas** de Base64 |

Créer la clé d'équipe dans **App Store Connect → Users and Access → Integrations → App Store Connect API** avec un rôle autorisé à téléverser les builds, par exemple **App Manager**. Une clé individuelle n'est pas utilisée par cette configuration. La clé privée ne se télécharge qu'une fois. Ne pas envoyer ces valeurs dans le chat, ne pas les committer et ne pas les placer dans des Repository Variables, fichiers YAML ou artefacts.

Un certificat `.cer` seul ne suffit pas : la clé privée correspondante est indispensable. Un profil Development, Ad Hoc ou Enterprise ne convient pas à TestFlight. Aucun UDID d'iPhone n'est nécessaire pour TestFlight.

### Préparer les éléments depuis Windows

Si un `.p12` de distribution avec sa clé privée existe déjà dans une sauvegarde sécurisée, le réutiliser avec un profil valide correspondant. Sinon, il est possible de créer une nouvelle clé et une CSR avec une installation de confiance d'OpenSSL sur Windows, sans utiliser de Mac physique :

```powershell
openssl genpkey -algorithm RSA -aes-256-cbc -pkeyopt rsa_keygen_bits:2048 -out distribution.key
openssl req -new -key distribution.key -out distribution.csr
```

Les mots de passe sont saisis à l'invite. Soumettre la CSR dans **Apple Developer → Certificates, Identifiers & Profiles → Certificates → Apple Distribution**. Télécharger le certificat `distribution.cer`, puis créer le `.p12` :

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12
```

Créer ensuite un profil de distribution **App Store Connect** pour l'identifiant existant en sélectionnant ce certificat. Ne pas révoquer un certificat de production existant pour libérer une place sans vérifier son utilisation.

Pour copier chaque fichier binaire au format attendu sans imprimer sa valeur dans le terminal :

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path './distribution.p12'))) | Set-Clipboard
# Coller dans APPLE_DISTRIBUTION_P12_BASE64.
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path './profile.mobileprovision'))) | Set-Clipboard
# Coller dans APPLE_PROVISIONING_PROFILE_BASE64.
Get-Content -Raw './AuthKey_VOTRE_KEY_ID.p8' | Set-Clipboard
# Coller dans ASC_PRIVATE_KEY_P8.
```

Stocker ces fichiers et leurs mots de passe dans un emplacement sécurisé hors du dépôt, puis vider le presse-papiers. La génération d'une nouvelle clé de distribution ne nécessite pas de changer l'identifiant de bundle ou les données de l'application.

## Activer et lancer TestFlight — uniquement après configuration

Le déploiement est désactivé par défaut. Ne pas créer le drapeau d'activation avant d'avoir renseigné tous les secrets.

1. Attendre la réussite de la validation sans signature sur `main`.
2. Configurer les huit Secrets ci-dessus et confirmer qu'ils correspondent à la même application/équipe.
3. Dans **Settings → Secrets and variables → Actions → Variables**, créer la **Repository Variable** `ENABLE_TESTFLIGHT` avec la valeur exacte `true`. Ce drapeau n'est pas une information confidentielle ; toutes les valeurs Apple restent dans Secrets.
4. Dans **Actions → NecroTube iOS 1.1 (3) → Run workflow**, sélectionner **main**, cocher **deploy_testflight**, puis lancer.
5. Le job de validation se réexécute. Le job TestFlight ne s'exécute qu'après sa réussite, sur un lancement manuel depuis `main` et avec le drapeau activé. Si un secret manque, il échoue avant l'import des certificats et l'archivage ; aucune valeur n'est imprimée.
6. La distribution vérifie l'expiration, l'équipe et le type du profil, puis la correspondance entre certificat valide, clé privée et profil. Elle archive en Release, vérifie les 11 localisations, la version 1.1 (3) et la signature, exporte une IPA App Store Connect, la valide avec Apple puis l'envoie.
7. Le trousseau et les fichiers de signature temporaires sont supprimés avec une étape `always()`, même en cas d'échec. Les fichiers `.p12`, `.p8`, profils, archives signées et IPA ne sont pas publiés comme artefacts.

Les actions tierces sont limitées à celles de GitHub et référencées par SHA complet. Le jeton GitHub a uniquement `contents: read` et n'est pas conservé dans le checkout. Aucun contournement TLS, de signature de packages, de validation de plugins/macros ou de protection de branche n'est configuré. `CODE_SIGNING_ALLOWED=NO` ne concerne que la compilation de validation explicitement non signée ; le job de distribution exige la signature Apple.

La version et le build ne sont jamais incrémentés automatiquement. **Si 1.1 (3) a déjà été accepté par App Store Connect, Apple peut refuser un nouvel envoi du même numéro.** Dans ce cas, il faut autoriser un nouveau numéro de build ; relancer le workflow ne remplace pas le binaire déjà envoyé.

## Installer sur l'iPhone

1. Ouvrir **App Store Connect → NecroTube → TestFlight → iOS** et attendre la fin du traitement du build **1.1 (3)**.
2. Répondre aux éventuelles questions de conformité/export pour ce build à partir des caractéristiques réelles de l'application. La CI ne renseigne pas de déclaration réglementaire à votre place.
3. Ajouter le build à un groupe de testeurs internes et ajouter votre compte Apple autorisé dans ce groupe. Pour des testeurs externes, une revue bêta Apple peut être nécessaire.
4. Installer l'application **TestFlight** depuis l'App Store sur l'iPhone, accepter l'invitation avec le compte concerné, puis toucher **Installer** pour NecroTube.
5. Vérifier sur l'iPhone les autorisations dans les 11 langues, le choix indépendant du lexique et les parcours existants. Un workflow vert ne remplace pas les tests caméra/microphone/SLS/EMF sur appareil ni la revue Apple.

## Références officielles

- [Runner Xcode 27 sur macOS](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)
- [Installer un certificat Apple sur GitHub Actions](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Téléverser des builds vers App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [Authentification et commandes altool](https://help.apple.com/asc/appsaltool/en.lproj/static.html)
- [Firebase Apple SDK : notes de version](https://firebase.google.com/support/release-notes/ios)
