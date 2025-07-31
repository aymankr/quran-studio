# Architecture de traitement Offline (Mode "Bounce")

## 🎛️ Vue d'ensemble

L'implémentation du traitement offline s'inspire des capacités du AD 480 RE pour traiter des fichiers audio complets en mode non temps réel. Cette fonctionnalité utilise `AVAudioEngine.manualRenderingMode` pour traiter l'audio plus rapidement que le temps réel, idéal pour le design sonore et la production professionnelle.

## ⚡ Fonctionnalités principales

### Traitement offline simple
- **OfflineReverbProcessor** : Traitement de fichiers individuels
- Modes : Wet seul, Dry seul, Mix, Wet+Dry séparés
- Formats de sortie : WAV, AIFF, CAF (16/24/32-bit)
- Vitesse : 5-20x plus rapide que temps réel (selon CPU)

### Traitement par lot (Batch)
- **BatchOfflineProcessor** : Traitement de multiples fichiers en série
- Templates pré-configurés pour différents workflows
- Gestion de file d'attente avec réorganisation
- Rapports détaillés et statistiques

## 🔧 Architecture technique

### Pipeline de traitement offline

```
Fichier d'entrée → AVAudioEngine (manualRenderingMode) → Traitement Reverb → Fichier de sortie
                                        ↓
                    AVAudioFile → PlayerNode → [Reverb Path] → OutputFile
                                              → [Dry Path]   →
```

### Modes de traitement

1. **Wet Only** : `Input → Reverb → Output` (100% wet)
2. **Dry Only** : `Input → Output` (bypass reverb)
3. **Mix** : `Input → [Direct + Reverb] → Mix → Output` (wet/dry selon réglages)
4. **Wet+Dry Separate** : Deux passes séparées pour wet et dry

### Configuration du moteur offline

```swift
// Activation du mode manuel de rendu
try engine.enableManualRenderingMode(.offline, format: processingFormat, maximumFrameCount: 1024)

// Traitement par blocs
while processedSamples < totalSamples {
    try engine.manualRenderingBlock(framesToRender, buffer) { (bufferToFill, frameCount) in
        bufferToFill.frameLength = frameCount
        return .success
    }
    
    try outputFile.write(from: buffer)
}
```

## 📊 Optimisations de performance

### Traitement plus rapide que temps réel
- **Buffer optimal** : 1024 frames pour équilibre performance/latence
- **Format optimal** : Float32 non-interleaved pour traitement DSP
- **Threading** : Traitement asynchrone avec Task/async-await
- **Monitoring** : Suivi en temps réel de la vitesse de traitement

### Gestion mémoire
- Traitement par chunks pour éviter les pics mémoire
- Nettoyage automatique des buffers temporaires
- Gestion d'erreurs robuste avec rollback

## 🎯 Templates de traitement

### Templates pré-configurés

1. **Vocal Processing**
   - Preset: Vocal Booth
   - Wet/Dry: 30%
   - Format: WAV 24-bit
   - Usage: Voix parlée et chant

2. **Music Production**
   - Preset: Studio
   - Mode: Wet+Dry séparés
   - Format: WAV 24-bit
   - Usage: Production musicale professionnelle

3. **Cinematic Processing**
   - Preset: Cathedral
   - Wet/Dry: 60%
   - Mode: Wet+Dry séparés
   - Usage: Ambiances cinématographiques

4. **Podcast Cleanup**
   - Preset: Clean
   - Wet/Dry: 10%
   - Format: WAV 16-bit
   - Usage: Enhancement podcast

### Template personnalisé
- Configuration complète des paramètres
- Sauvegarde pour réutilisation
- Export/Import de templates

## 📁 Gestion de fichiers

### Formats d'entrée supportés
- **WAV** : PCM non compressé
- **AIFF** : PCM Apple
- **CAF** : Core Audio Format
- **MP3** : Compressed (décodage automatique)
- **M4A/AAC** : Advanced Audio Coding

### Formats de sortie
- **WAV** : Standard industrie, compatible universel
- **AIFF** : Format Apple, métadonnées étendues
- **CAF** : Core Audio, optimisé macOS

### Structure de sortie
```
~/Documents/OfflineProcessing/
├── input_file_wet_20240131_143025.wav
├── input_file_dry_20240131_143025.wav
└── input_file_processed_20240131_143025.wav
```

## 🔄 Workflow de traitement par lot

### Configuration de la file
1. Sélection du template ou configuration personnalisée
2. Ajout de multiples fichiers audio
3. Réorganisation optionnelle de la file
4. Validation des paramètres

### Traitement en série
```swift
for item in processingQueue {
    // Traitement individuel
    let results = try await processAudioFile(item)
    
    // Mise à jour des statistiques
    updateProgress(item, results)
    
    // Gestion des erreurs
    handleErrors(item, error)
}
```

### Reporting avancé
- Statistiques de performance (vitesse moyenne)
- Taux de réussite/échec
- Temps de traitement détaillé
- Export de rapport texte

## 🚀 Avantages du mode offline

### Vs traitement temps réel
- **Vitesse** : 5-20x plus rapide selon CPU
- **Qualité** : Traitement sans contraintes de latence
- **Stabilité** : Pas de drop-outs possibles
- **Flexibilité** : Traitement de fichiers de toute durée

### Applications professionnelles
- **Design sonore** : Traitement de banques de sons
- **Post-production** : Batch processing de multiples prises
- **Mastering** : Application uniforme de traitements
- **Archivage** : Conversion de formats legacy

## 📈 Monitoring et diagnostics

### Métriques temps réel
- Progression globale (0-100%)
- Vitesse de traitement (multiplier vs temps réel)
- Temps estimé restant
- Fichier en cours de traitement

### Statistiques de session
- Nombre de fichiers traités
- Taux de réussite
- Vitesse moyenne de traitement
- Temps total de traitement

### Gestion d'erreurs
- Validation des fichiers d'entrée
- Détection de formats non supportés
- Gestion des erreurs d'écriture
- Récupération gracieuse

## 🔮 Extensions futures

### Formats avancés
- Support DSD (Direct Stream Digital)
- Formats surround (5.1, 7.1)
- Formats haute résolution (192kHz, 32-bit float)

### Traitement avancé
- Chaînes d'effets multiples
- Automation de paramètres
- Traitement adaptatif selon contenu

### Intégration workflow
- Plugin DAW pour traitement batch
- API pour intégration externe
- Support ligne de commande

## 💡 Cas d'usage recommandés

### Production musicale
1. Traitement de multiples prises vocales
2. Application uniforme de réverbération
3. Création de versions wet/dry pour mixage

### Post-production audio
1. Traitement de dialogues (films, podcasts)
2. Création d'ambiances sonores
3. Uniformisation de banques de sons

### Design sonore
1. Traitement de bibliothèques audio
2. Création de variations d'effets
3. Génération de textures sonores

Cette architecture offline complète les capacités temps réel de l'application en offrant une solution professionnelle pour le traitement de fichiers, inspirée des standards de l'industrie comme l'AD 480 RE.