# Reverb

Une application macOS pour ajouter des effets de réverbération en temps réel à votre voix ou à votre chant.

## Fonctionnalités

- Enregistrement et lecture audio en temps réel
- Trois préréglages de réverbération (Cathédrale, Grande Salle, Petite Pièce)
- Interface utilisateur simple et intuitive
- Traitement audio local sans latence

## Configuration requise

- macOS 14.0 ou ultérieur
- Microphone intégré ou externe

## Installation

1. Clonez ce dépôt:
```
git clone https://github.com/votreusername/Reverb.git
```

2. Ouvrez le projet dans Xcode:
```
cd Reverb
open Reverb.xcodeproj
```

3. Compilez et exécutez l'application:
   - Sélectionnez l'appareil cible (votre Mac)
   - Cliquez sur le bouton de lecture (▶️) ou utilisez le raccourci Cmd+R

## Utilisation

1. Lancez l'application Reverb
2. Choisissez l'un des trois préréglages de réverbération
3. Cliquez sur le bouton "Start" pour commencer l'enregistrement en temps réel
4. Parlez ou chantez dans votre microphone
5. Cliquez sur le bouton "Stop" pour arrêter l'enregistrement

## Architecture

L'application est développée en Swift en utilisant SwiftUI pour l'interface utilisateur et AVFoundation pour le traitement audio. Elle utilise une architecture MVVM (Model-View-ViewModel) pour la séparation des responsabilités:

- **Modèle**: Gestion de l'audio et de l'historique des enregistrements
- **Vue**: Interface utilisateur SwiftUI
- **ViewModel**: Liaison entre le modèle et la vue

## Licence

Ce projet est sous licence MIT. Voir le fichier LICENSE pour plus de détails. 