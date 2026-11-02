# NecroTube iOS 1.1 (3) — audit de localisation et de soumission

Date : 2 novembre 2026. Audit des fichiers disponibles dans ce dépôt Windows. Xcode, le compilateur Swift et plutil ne sont pas disponibles. Aucune compilation, archive, installation, exécution iOS ou validation App Store n'a été réalisée. Le projet n'est pas déclaré prêt pour publication.

## 1. Version et build définitifs dans les sources

La cible principale NecroTubeXcode a les mêmes valeurs dans ses deux configurations :

| Configuration | MARKETING_VERSION | CURRENT_PROJECT_VERSION |
| --- | --- | --- |
| Debug | 1.1 | 3 |
| Release | 1.1 | 3 |

Le dépôt indiquait 1.0 (1) au début de cette passe. Les valeurs sont maintenant celles explicitement demandées. Le fichier Info.plist de l'application est généré (GENERATE_INFOPLIST_FILE = YES). GoogleService-Info.plist configure Firebase et ne contient pas les versions de l'application. Aucun autre fichier de configuration de version n'a été trouvé.

L'autre modification de configuration de cette passe est INFOPLIST_KEY_UIPrefersShowingLanguageSettings = YES, en Debug et Release. Elle rend le choix de langue visible dans les réglages iOS même pour une personne ayant une seule langue préférée, conformément à la recommandation Apple.

## 2. Résultat de l'audit des 11 langues

| Langue | Code/dossier | Clés Localizable.strings | Clés InfoPlist.strings | Résultat statique |
| --- | --- | --- | --- | --- |
| Français | fr.lproj | 146 | 3 | OK |
| Anglais | en.lproj | 146 | 3 | OK |
| Espagnol | es.lproj | 146 | 3 | OK |
| Allemand | de.lproj | 146 | 3 | OK |
| Italien | it.lproj | 146 | 3 | OK |
| Portugais | pt.lproj | 146 | 3 | OK, variante brésilienne harmonisée |
| Japonais | ja.lproj | 146 | 3 | OK |
| Khmer | km.lproj | 146 | 3 | OK |
| Chinois | zh.lproj | 146 | 3 | OK, textes en chinois simplifié |
| Arabe | ar.lproj | 146 | 3 | OK |
| Roumain | ro.lproj | 146 | 3 | OK |

Les 22 fichiers .strings ont été inspectés. Les ensembles de clés sont identiques dans les 11 langues pour chaque table. Aucun doublon, valeur vide, clé manquante entre les tables, caractère Unicode de remplacement ou paramètre de format manquant n'a été trouvé après correction. Les 24 appels explicites String(localized:) ainsi que les libellés statiques SwiftUI contrôlés ont une clé disponible dans les 11 langues. Les libellés dynamiques ont été revus et leurs usages incorrects corrigés. Les noms de produits, acronymes et unités restent invariants.

La revue des traductions a corrigé l'intitulé japonais de la langue du lexique, la terminologie italienne de la caméra, ainsi que le mélange entre portugais européen et brésilien. Les traductions ont été relues dans le cadre de cet audit ; cette revue ne constitue pas une certification linguistique par des locuteurs natifs.

### Autorisations effectivement utilisées

| Accès | API trouvée | Clé localisée |
| --- | --- | --- |
| Caméra | AVCaptureDevice.requestAccess(for: .video) | NSCameraUsageDescription |
| Microphone EVP et vidéo | AVAudioApplication.requestRecordPermission() | NSMicrophoneUsageDescription |
| Ajout de vidéos à Photos | PHPhotoLibrary.requestAuthorization(for: .addOnly) | NSPhotoLibraryAddUsageDescription |

Les descriptions correspondent aux usages du code : aperçu et vidéo, postures SLS, mesure du niveau sonore et enregistrement EVP/son vidéo, ajout des vidéos à Photos. Aucune demande d'accès en lecture à la photothèque, de localisation ou de reconnaissance vocale trouvée. SpeechService utilise la synthèse vocale AVSpeechSynthesizer. Les capteurs utilisent CMMotionManager pour l'accélération et le champ magnétique bruts ; aucune nouvelle demande d'autorisation n'a été ajoutée.

### Intégration et secours anglais

Les codes AppLanguage, les 11 dossiers .lproj, les ressources des lexiques et les 11 langues de knownRegions concordent. Base est uniquement la région structurelle Xcode ; il n'y a pas de douzième traduction utilisateur. Aucun catalogue .xcstrings n'est présent.

Le dossier NecroTubeXcode est un PBXFileSystemSynchronizedRootGroup rattaché à la cible principale par fileSystemSynchronizedGroups, sans exception d'appartenance. Les ressources suivent cette intégration automatique ; aucune référence manuelle redondante n'a été ajoutée.

La langue de développement est en. Les valeurs de confidentialité générées en Debug/Release sont identiques aux valeurs anglaises d'InfoPlist.strings. Le fichier Localizable.strings anglais est complet. L'application résout la langue choisie par iOS via Bundle.main.preferredLocalizations, normalise son code avec Locale et utilise l'anglais si le code n'est pas reconnu. Le choix effectif du bundle et ses mécanismes de secours restent ceux de Foundation. Il faut vérifier le comportement d'une langue système non prise en charge dans le binaire.

## 3. Sélecteur de langue et persistance

Le bouton existant ouvre les réglages de l'application avec UIApplication.openSettingsURLString. Le choix de langue reste officiel et géré par iOS ; aucune réintroduction d'un sélecteur interne dissocié des autorisations, aucune écriture de AppleLanguages et aucune API privée.

- Les 11 langues disposent des ressources nécessaires pour être proposées par iOS. Leur apparition réelle dans le sélecteur doit être confirmée sur iPhone après compilation.
- UIPrefersShowingLanguageSettings demande l'affichage du réglage même avec une seule langue préférée.
- Au lancement, AppState utilise AppLanguage.systemLanguage pour suivre la localisation du bundle.
- Au retour à l'état actif, RootView appelle refreshAppLanguage ; la langue publiée est mise à jour si nécessaire. Le redémarrage de l'application recharge également la langue système.
- La persistance du choix d'interface relève d'iOS et doit être vérifiée par un changement suivi d'une fermeture/relance.
- La langue du lexique reste sélectionnable indépendamment parmi les 11 langues via AppLanguage.allCases. Sa clé UserDefaults lexicon.language, son chargement au lancement et sa sauvegarde restent inchangés. Les 11 fichiers de lexique existent.
- Aucun effacement ni migration des données ou des préférences : app.language, lexicon.language, mots personnalisés, historique et réglages audio ne sont pas supprimés. L'ancienne valeur interne app.language reste stockée mais n'est plus utilisée pour imposer une langue à SwiftUI, conformément à la correction précédente. Si elle diffère du choix iOS, l'utilisateur doit sélectionner sa langue dans les réglages iOS.

Les chaînes des autorisations et les erreurs personnalisées utilisent les tables du même bundle. Le texte propre au système, notamment les boutons des autorisations, est fourni par iOS ; l'application ne peut pas traduire ces boutons elle-même. Leur rendu doit être contrôlé notamment en khmer et en arabe.

## 4. Problèmes détectés et corrigés pendant cette passe

- Version/build du dépôt : passage de 1.0 (1) à 1.1 (3), Debug et Release.
- Possibilité de réglage de langue absent sur un appareil monolingue : ajout de UIPrefersShowingLanguageSettings.
- Langue capturée uniquement à l'initialisation et correspondance stricte des codes : résolution du code de langue normalisé et rafraîchissement au retour à l'état actif.
- Titres d'alerte et confirmations de suppression français : remplacement par des clés sources traduites.
- Erreurs caméra, audio/EVP, radio, capteurs et lexique codées en français : localisation des textes sans changer les conditions d'erreur ni les traitements.
- Messages de station suivante et de sortie audio occupée : localisation.
- Statuts dynamiques, interrupteurs caméra, commandes et libellés d'accessibilité qui utilisaient String au lieu d'une clé localisée : correction de la présentation uniquement.
- Préfixe d'activité des capteurs dans l'historique et son texte partagé : localisation de l'affichage, sans modifier les événements enregistrés ou leur stockage.
- Japonais : LEXICON LANGUAGE corrigé de « vocabulaire et langue » vers « langue du vocabulaire ».
- Italien : terminologie fotocamera harmonisée.
- Portugais : autorisations, refus, messages d'export et nouveaux messages harmonisés avec le portugais brésilien de l'interface existante.
- Ajout de 29 clés traduites dans chaque langue, soit 146 clés d'interface au total.

Les fonctions Spirit Box, EVP, SLS, EMF, abonnements et historique n'ont reçu aucune modification de traitement métier. Les modifications dans ces fichiers concernent uniquement les textes et leur localisation. La structure et le style général des écrans sont conservés. Aucune dépendance ajoutée.

## 5. Conformité aux motifs signalés

### Guideline 2.3.6

Aucune déclaration ou fonctionnalité de vérification d'âge ou de contrôle parental contradictoire trouvée dans les sources Swift et la configuration du projet. Aucune utilisation trouvée de FamilyControls, Screen Time ou DeclaredAgeRange. Aucun mécanisme ajouté.

« Age Assurance : None » est considéré comme corrigé dans App Store Connect selon votre indication. Le compte App Store Connect n'a pas été consulté ; ses métadonnées ne sont pas stockées dans ce dépôt.

### Guideline 4.0

Les trois autorisations utilisées possèdent des descriptions dans les 11 langues. L'interface et les messages personnalisés suivent la localisation iOS du bundle. Le décalage causé par l'ancien sélecteur interne n'est pas réintroduit. La conformité du rendu réel nécessite toutefois les tests iPhone ci-dessous.

## 6. Vérifications effectuées et reproductibles

Commande : node scripts/verify-localization.cjs

Résultat : succès, 11 langues, 146 clés UI et 3 descriptions par langue ; 24 appels String(localized:) couverts ; versions Debug/Release 1.1 (3).

Le script vérifie syntaxe des paires .strings utilisées ici, doublons, valeurs vides, encodage, paramètres, parité des clés, présence des lexiques, codes de langue, réglage de langue visible, intégration synchronisée et valeurs anglaises de secours. Il vérifie également les clés littérales des contrôles SwiftUI concernés. Ce contrôle statique n'est pas un parseur Swift et n'émule pas iOS.

git diff --check passe en tenant compte des fins de ligne Windows (core.whitespace=cr-at-eol).

## 7. Vérifications obligatoires avec Xcode sur macOS

1. Compiler Debug puis archiver Release avec le SDK compatible avec les réglages existants. Vérifier la signature et les éventuels diagnostics Swift, notamment l'isolation des types et les initialisations SwiftUI.
2. Vérifier dans l'archive CFBundleShortVersionString = 1.1 et CFBundleVersion = 3. Vérifier CFBundleDevelopmentRegion = en et UIPrefersShowingLanguageSettings de type booléen vrai.
3. Valider les 22 fichiers .strings avec plutil -lint. Inspecter le bundle : 11 dossiers .lproj, leurs deux tables .strings, les 11 lexiques et aucune ressource exclue ou dupliquée.
4. Installer sur un iPhone initialement monolingue, ouvrir le bouton de réglage de langue et vérifier que les 11 langues sont proposées.
5. Pour chacune des 11 langues, sélectionner la langue, revenir dans l'application, fermer puis relancer. Vérifier l'interface, les nouveaux messages, les textes longs et les libellés d'accessibilité. Vérifier le sens de lecture arabe, les glyphes khmers et les troncatures sur petit écran.
6. Réinitialiser les autorisations avant chaque série. Tester caméra, microphone EVP, microphone vidéo et ajout à Photos en acceptant puis en refusant ; vérifier la langue de la description, du titre et des boutons iOS. Tester aussi les restrictions et les autorisations déjà accordées.
7. Tester langue du système différente de celle de l'application, variantes régionales (dont chinois), et langue système non prise en charge pour vérifier le secours.
8. Choisir une langue de lexique différente de celle de l'interface ; vérifier sa conservation après relance, les mots personnalisés et l'absence de modification des historiques et enregistrements existants.
9. Vérifier les parcours existants d'enregistrement EVP et vidéo avec son, l'export Photos et la conservation locale quand Photos est refusé. Vérifier l'affichage localisé du partage d'historique.
10. Faire relire les traductions par des locuteurs natifs et vérifier le rendu des textes système pour les langues dont la prise en charge iOS peut différer de celle de l'application.
11. Confirmer la sélection « Age Assurance : None » pour la soumission finale dans App Store Connect et vérifier que les métadonnées n'annoncent aucun contrôle parental ou mécanisme de vérification d'âge.

## 8. Risques résiduels

- Absence de compilation et de validation macOS : l'intégration dans le binaire, les types du plist généré et le comportement iOS ne sont pas certifiés.
- Les textes longs, l'accessibilité, le rendu arabe et khmer et les traductions nécessitent une validation visuelle et linguistique.
- Des erreurs provenant directement des frameworks utilisent error.localizedDescription ; leur traduction dépend de la prise en charge système. Les erreurs personnalisées identifiées ont été traduites.
- L'ancienne préférence interne app.language peut différer du choix système ; ses données sont conservées mais le choix effectif reste celui d'iOS.
- Les métadonnées App Store Connect n'ont pas été vérifiées directement. Aucun rejet évité ni aucune acceptation Apple ne peut être garanti par cet audit de sources.

## 9. Liste exacte des fichiers modifiés ou créés pendant cette passe

- NecroTubeXcode.xcodeproj/project.pbxproj
- NecroTubeXcode/App/AppState.swift
- NecroTubeXcode/App/RootView.swift
- NecroTubeXcode/Core/Models/AppLanguage.swift
- NecroTubeXcode/Features/EVP/EVPRecorderView.swift
- NecroTubeXcode/Features/History/SessionHistory.swift
- NecroTubeXcode/Features/Investigation/InvestigationControls.swift
- NecroTubeXcode/Features/Investigation/InvestigationHeader.swift
- NecroTubeXcode/Features/Investigation/InvestigationView.swift
- NecroTubeXcode/Features/SpiritBox/SpiritBoxView.swift
- NecroTubeXcode/Services/Audio/EVPAudioEngine.swift
- NecroTubeXcode/Services/Camera/CameraSLSService.swift
- NecroTubeXcode/Services/Lexicon/LexiconEngine.swift
- NecroTubeXcode/Services/Radio/RadioSweepEngine.swift
- NecroTubeXcode/Services/Sensors/SensorFusionEngine.swift
- NecroTubeXcode/Resources/ar.lproj/Localizable.strings
- NecroTubeXcode/Resources/de.lproj/Localizable.strings
- NecroTubeXcode/Resources/en.lproj/Localizable.strings
- NecroTubeXcode/Resources/es.lproj/Localizable.strings
- NecroTubeXcode/Resources/fr.lproj/Localizable.strings
- NecroTubeXcode/Resources/it.lproj/Localizable.strings
- NecroTubeXcode/Resources/ja.lproj/Localizable.strings
- NecroTubeXcode/Resources/km.lproj/Localizable.strings
- NecroTubeXcode/Resources/pt.lproj/Localizable.strings
- NecroTubeXcode/Resources/ro.lproj/Localizable.strings
- NecroTubeXcode/Resources/zh.lproj/Localizable.strings
- NecroTubeXcode/Resources/pt.lproj/InfoPlist.strings
- scripts/verify-localization.cjs
- APP_STORE_REVIEW_AUDIT.md

Les autres InfoPlist.strings et SettingsView.swift corrigés lors de la passe précédente ont été relus mais n'ont pas été modifiés pendant cette passe. Les changements précédents restent présents dans l'espace de travail ; aucun commit, archivage ou envoi n'a été effectué.

## Références Apple

- [WWDC24 — Build multilingual-ready apps, section 14:50 : réglage de langue et UIPrefersShowingLanguageSettings](https://developer.apple.com/videos/play/wwdc2024/10185/)
- [UIApplication.openSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)
- [Foundation — préférences et localisations du bundle](https://developer.apple.com/documentation/foundation/bundle/1409418-preferredlocalizations)
- [InfoPlist.strings et localisation des valeurs Info.plist](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html)
