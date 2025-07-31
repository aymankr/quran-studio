# Architecture d'enregistrement Wet/Dry

## 🎛️ Vue d'ensemble

L'implémentation de l'enregistrement wet/dry sépare permet d'enregistrer simultanément :
- **Mix** : Signal traité tel qu'entendu (comportement actuel) 
- **Wet** : Signal de réverbération isolé
- **Dry** : Signal direct sans traitement

Cette architecture s'inspire de l'AD 480 RE avec ses sorties séparées wet et dry pour la post-production professionnelle.

## 🔧 Architecture technique

### Modes d'enregistrement disponibles

1. **Mix seulement** - Signal traité tel qu'entendu (comportement actuel)
2. **Wet seulement** - Signal de réverbération isolé  
3. **Dry seulement** - Signal direct sans traitement
4. **Wet + Dry séparés** - Deux fichiers pour post-production
5. **Mix + Wet + Dry** - Trois fichiers pour flexibilité maximale

### Architecture audio WetDryAudioEngine

```
Input → InputGain → ┬─→ DrySignal ─┬─→ WetDryMixer → RecordingMixer → OutputMixer → Output
                    │              │
                    └─→ Reverb → WetSignal ─┘

Points de tap :
- Dry Tap : sur DrySignal node (signal pur dry)
- Wet Tap : sur WetSignal node (signal pur wet)  
- Mix Tap : sur RecordingMixer node (signal wet/dry mixé)
```

### Contrôle du mix wet/dry

- Le fader wet/dry gère le ratio wet/dry dans le bus mix final
- N'affecte pas les volumes relatifs des sorties séparées wet ou dry
- Le tap positionné après le mix respecte l'équilibre choisi par l'utilisateur
- Crossfade à puissance égale (courbes cosinus/sinus) pour transitions lisses

## 📁 Gestion des fichiers

### Nomenclature des fichiers
```
reverb_mix_20240131_143025.wav    - Signal mixé
reverb_wet_20240131_143025.wav    - Signal wet isolé
reverb_dry_20240131_143025.wav    - Signal dry isolé
```

### Synchronisation
- Timestamps identiques pour tous les fichiers d'une session
- Démarrage simultané de tous les enregistrements
- Durées identiques garanties par le timer partagé

### Formats supportés
- **WAV** : Non compressé, qualité studio (recommandé)
- **AAC** : Compressé, bonne qualité
- **MP3** : Compressé, compatible

## 🎚️ Implémentation

### Classes principales

1. **WetDryAudioEngine**
   - Gère l'architecture audio avec séparation wet/dry
   - Points de tap dédiés pour chaque signal
   - Contrôle du mix wet/dry avec crossfade

2. **WetDryRecordingManager**
   - Gestion des sessions d'enregistrement multi-fichiers
   - NonBlockingAudioRecorder pour chaque canal
   - Synchronisation des timestamps

3. **WetDryRecordingView**
   - Interface utilisateur pour sélection du mode
   - Contrôles de format et de session
   - Visualisation des sessions avec indicateurs wet/dry

### Architecture non-bloquante

- Buffer circulaire FIFO pour éviter les drop-outs
- Thread audio : Real-time tap → FIFO buffer  
- Thread I/O : FIFO → Écriture disque (background)
- Format optimal : Float32 non-interleaved, 2-channel, 48kHz

## 🔄 Fallback et compatibilité

### Mode de compatibilité
Si WetDryAudioEngine n'est pas disponible :
- Mix : Tap sur RecordingMixer (comportement actuel)
- Wet : Tap sur RecordingMixer avec note de limitation
- Dry : Tap sur InputNode (avant traitement)

### Intégration avec l'existant
- Compatible avec AudioEngineService existant
- Utilise NonBlockingAudioRecorder existant
- Conserve la stabilité audio actuelle

## 📊 Avantages pour la post-production

### Workflow professionnel
1. Enregistrer en mode "Wet + Dry séparés"
2. Importer les deux fichiers dans un DAW
3. Ajuster le mix wet/dry en post-production
4. Appliquer des traitements différents sur wet et dry
5. Réverbération créative avec le signal wet isolé

### Flexibilité créative
- Réglage précis du mix wet/dry après enregistrement
- Traitement séparé des signaux wet et dry
- Création d'effets avancés avec le signal wet isolé
- Conservation du signal dry pour re-processing

## 🎯 Cas d'usage

### Production musicale
- Enregistrement vocal avec réverbération ajustable
- Instruments avec possibilité de re-traitement
- Mixage professionnel avec contrôle total

### Post-production audio
- Synchronisation avec vidéo
- Adaptation du mix selon le contexte
- Création d'ambiances variables

### Archivage professionnel
- Conservation du signal dry original
- Possibilité de re-traitement futur
- Standards de l'industrie respectés

## 🔮 Extensions futures

### Multi-canal
- Support 5.1 surround avec réverbération spatiale
- Enregistrement multi-canal avec taps dédiés
- Format WAV polyphonique pour surround

### Formats avancés
- Support des formats haute résolution (96kHz, 24-bit)
- Formats broadcast (BWF) avec métadonnées
- Export direct vers formats pro (AIFF, CAF)

## 📝 Notes d'implémentation

Cette architecture respecte les standards de l'industrie pour l'enregistrement wet/dry, similaire aux processeurs de réverbération professionnels comme l'AD 480 RE. Le respect de l'équilibre wet/dry choisi par l'utilisateur et la possibilité d'enregistrer les signaux séparés offrent une flexibilité maximale pour la post-production.