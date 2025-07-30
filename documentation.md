# Reverb

# Atteindre la qualité audio d’AD 480 : analyse technologique et plan d’amélioration

AD 480 reste une référence sur iOS pour ses algorithmes de réération « studio-grade » et la faible latence de son moteur audio. Comprendre sa pile logicielle permet de définir la feuille de route pour porter votre application au même niveau – sur iOS comme sur Android – tout en pérennisant le code DSP en C++ multiplateforme.

## Vue d’ensemble d’AD 480

| Caractéristique clef | Implémentation indiquée par Fiedler Audio | Impact sur la qualité |
| --- | --- | --- |
| Latence I/O | 64 échantillons (≈1.3 ms @48 kHz)[1](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851) | Monitoring quasi-temps-réel |
| Plage d’échantillonnage | 44.1–96 kHz[1](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851)[2](https://www.synthtopia.com/content/2014/05/16/ad-480-pro-a-studio-reverb-effect-for-audiobus-inter-app-audio/) | Haute fidélité et compatibilité interfaces externes |
| Moteur stéréo « true stereo » | Deux blocs de réverb mono + cross-feed dédié[3](https://fiedler-audio.com/wp-content/uploads/2015/03/Manual-AD-480-Reverb-RE.pdf) | Image large et cohérente |
| Paramètres avancés | Size, Rev.Length, Dim, HF/ LF Damping, Spread, Pre-/Cross-Delay, Dry-Distance[3](https://fiedler-audio.com/wp-content/uploads/2015/03/Manual-AD-480-Reverb-RE.pdf) | Contrôle fin du caractère du champ réverbérant |
| Routing matriciel 24×24 + MIDI | Audiobus 2, Inter-App Audio, CoreMIDI[4](https://fiedler-audio.com/ad-480/)[1](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851) | Chaînage d’effets professionnel, automatisation externe |

## Stack logicielle supposée

1. **DSP Core**
    - C++ à virgule flottante 32/64 bits pour la partie temps réel (réutilisé ensuite dans le Rack Extension). [5](https://rekkerd.org/fiedler-audio-releases-ad-480-reverb-rack-extension/)
    - Optimisations ARM NEON / Accelerate vDSP pour les boucles de délai, filtres et all-pass.
2. **Couche iOS**
    - Core Audio / Audio Units (format « Inter-App Audio » et Audiobus). [2](https://www.synthtopia.com/content/2014/05/16/ad-480-pro-a-studio-reverb-effect-for-audiobus-inter-app-audio/)
    - AVAudioSession réglé sur 64 frames et `AVAudioSessionCategoryPlayAndRecord`.
    - CoreMIDI pour le contrôle temps réel des paramètres.
3. **Rack Extension**
    - SDK Reason Studios 4.x (C++) + scripts Lua « Jukebox »[6](https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-concepts). [7](https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-scripting-specification)
    - DSP identique empaqueté en DLL/Dylib, UI en SVG/PNG.
4. **UI**
    - UIKit (iPadOS) + touches multiples pour faders « big faders ». 8
    - Stage Mode dédié (contrastes inversés) géré côté GPU.

## Diagnostique de votre pile actuelle

| Composant | Stack actuelle (Swift + AVAudioEngine) | Limites observées |
| --- | --- | --- |
| Moteur DSP | Swift + AVAudioUnitReverb système | Algorithme fixe, contrôles restreints, latence dépendant du buffer |
| Mise à jour live | Binding SwiftUI ↔ AudioUnit | Risque de contention UI/audio-thread |
| Cross-platform | iOS uniquement | Pas d’Android, difficile d’exporter en VST/AU |
| Extensibilité future | Swift centré | Portage vers desktop/stand-alone complexe |

## Feuille de route « qualité AD 480 »

## 1. Un noyau DSP C++ multiplateforme

| Objectif | Recommandation | Bénéfice |
| --- | --- | --- |
| Mutualiser iOS/Android/Desktop | Extraire la réverb en librairie C++14 (float/double) | Maintien unique, performances natives |
| Framework C++ | JUCE 7 (ou Superpowered si priorité à mobile)[9](https://docs.superpowered.com/getting-started/how-to-integrate/ios/) | Hôtes AUv3, VST3, AAX + iOS/Android |
| Pipeline CI | CMake + GitHub Actions (ARM iOS, x86-64 macOS, ARM/Intel Android NDK) | Builds reproductibles |

## 2. Algorithme de réverbération « studio »

1. **Structure de base – FDN modulé**
    - Réseau de 4 à 8 lignes de délai, longueur premiers échos → `size`.
    - All-pass à phase retardée modulé (±7 cent) pour suppression de nodes métalliques. [10](https://www.sweetwater.com/insync/fiedler-audio-ad-480-reverb-app-demo-sweetwaters-ios-update-vol-81/)[11](https://dokumen.pub/designing-audio-effect-plugins-in-c-for-aax-au-and-vst3-with-dsp-theory-2nbsped-1138591890-9781138591899.html)
    - Damping HF/LF par paires de filtres Shelving IIR de Butterworth ordre 2.
2. **Modules complémentaires**
    - Cross-feed stéréo variable + inversion de phase L/R (comme AD 480). [3](https://fiedler-audio.com/wp-content/uploads/2015/03/Manual-AD-480-Reverb-RE.pdf)
    - Section EQ pré-et post réverb (12 dB/oct).
    - Early-Reflection switchable (conv FIFO) pour émulation « plate » ou « hall ».
    - Over-sampling ×2 interne pour moduler les all-pass sans aliasing.
3. **Traitement haute résolution**
    - Buffer interne 64-bit float puis downmix.
    - Dither Triangular PDF 24-bit à la sortie (if render) – inaudible en live.

## 3. iOS : latence & monitoring instantané

| Action | Détail | Gain |
| --- | --- | --- |
| `preferredIOBufferDuration = 64 / SR` | 64 frames @48 kHz ≈ 1.33 ms | Parité avec AD 480[1](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851) |
| `AVAudioEngine.manualRenderingMode` pour bounce | Stabilité, offline HQ | Rendu 32-bit/96 kHz |
| Thread audio : QoS `AVAudioSessionModeMeasurement` + `AudioWorkgroup` | Priorité > UI | Zéro drop |
| Communication UI → DSP | Atomics + lock-free ring buffer | Paramètres modifiés en <500 µs |

## 4. Android : parcours à faible latence

| Composant | Recommandation |
| --- | --- |
| API | Oboe (C++14) ou AAudio MMAP exclusif |
| Buffer size | 48–96 frames selon device, fallback OpenSL ES |
| Thread | `sched_setscheduler` SCHED_FIFO + priorité 1 en dessous IRQ |
| Interface MIDI | Jetpack MIDI + wrapper NDK |

## 5. Outils externes & bibliothèques

| Besoin | Lib conseillée | Raison |
| --- | --- | --- |
| SIMD portable | **Eigen** ou intrinsics NEON/SSE2 | Accélère FDN, filtres |
| FFT/Convolution | **ffts** (license BSD) ou **Apple vDSP** | Option IR longue |
| Mesure RT60 | **libsamplerate** + script Python acoustique | Validation QA |
|  |  |  |

## 6. Fonctionnalités premium inspirées d’AD 480

- **Routing Matriciel** : bus interne 16×16 (+ side-chain), patchable UI.
- **MIDI Learn + NRPN 14-bit** pour automation hardware[1](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851).
- **Mode Stage** : preset UI Dark/Hi-Contrast pour scène (brightness –50%).
- **Export/Import preset JSON** compatible AU/VST/Android.
- **Impulses personnalisées** : loader de fichiers WAV IR (convoluteur offline).

## 7. Assurance qualité et métrologie

| Test | Métrique cible | Référence |
| --- | --- | --- |
| Distorsion THD+N | < 0.002% @1 kHz, -1 dBFS | Bench AD 480 (subjectif) |
| Enveloppe RT60 | ±5% par rapport à courbe théorique | Mesure Room EQ Wizard |
| Jitter param live | < 0.3 ms pico-pico | Ring buffer atomic |
| Consommation CPU iPhone 13 | ≤ 15% pour 8 voies 48 kHz | Analyse Instruments |

## Tableau récapitulatif : stack recommandée

| Couche | iOS | Android | Partagée |
| --- | --- | --- | --- |
| I/O bas niveau | Core Audio (`AudioUnit`, `AVAudioEngine`) | Oboe / AAudio | — |
| DSP | C++14 (JUCE DSP ou Superpowered) | C++14 (même code) | Vectorisation NEON/SSE |
| UI | SwiftUI / UIKit | Jetpack Compose ou Qt | Skia/ImGui (debug) |
| MIDI | CoreMIDI | Jetpack MIDI + NDK | Wrapper C++ |

## Conclusion : continuer ou migrer ?

- **Rester 100% Swift/AVAudioUnit** limitera vos algorithmes, votre latence et le portage Android.
- **Migrer le DSP en C++** – tout en conservant SwiftUI pour l’interface – assure une qualité audio de niveau AD 480, réutilisable sur Android, macOS / Windows et au format plugin.
- **Android** : privilégier Oboe + AAudio MMAP, sinon latence >10 ms.
- **iOS** : conservez AVAudioEngine, mais hébergez votre AudioUnit personnel (AUv3) pour profiter du scheduling temps-réel Apple.

En suivant cette architecture, vous obtiendrez une qualité de réverbération et une réactivité comparables à AD 480, tout en assurant la pérennité multiplateforme de votre code DSP.

1. [https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851](https://apps.apple.com/ph/app/ad-480-free-studio-reverb/id662715851)
2. [https://www.synthtopia.com/content/2014/05/16/ad-480-pro-a-studio-reverb-effect-for-audiobus-inter-app-audio/](https://www.synthtopia.com/content/2014/05/16/ad-480-pro-a-studio-reverb-effect-for-audiobus-inter-app-audio/)
3. [https://fiedler-audio.com/wp-content/uploads/2015/03/Manual-AD-480-Reverb-RE.pdf](https://fiedler-audio.com/wp-content/uploads/2015/03/Manual-AD-480-Reverb-RE.pdf)
4. [https://fiedler-audio.com/ad-480/](https://fiedler-audio.com/ad-480/)
5. [https://rekkerd.org/fiedler-audio-releases-ad-480-reverb-rack-extension/](https://rekkerd.org/fiedler-audio-releases-ad-480-reverb-rack-extension/)
6. [https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-concepts](https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-concepts)
7. [https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-scripting-specification](https://developer.reasonstudios.com/documentation/rack-extension-sdk/4.3.0/jukebox-scripting-specification)
8. [https://www.youtube.com/watch?v=I4ceCb2gKPA](https://www.youtube.com/watch?v=I4ceCb2gKPA)
9. [https://docs.superpowered.com/getting-started/how-to-integrate/ios/](https://docs.superpowered.com/getting-started/how-to-integrate/ios/)
10. [https://www.sweetwater.com/insync/fiedler-audio-ad-480-reverb-app-demo-sweetwaters-ios-update-vol-81/](https://www.sweetwater.com/insync/fiedler-audio-ad-480-reverb-app-demo-sweetwaters-ios-update-vol-81/)
11. [https://dokumen.pub/designing-audio-effect-plugins-in-c-for-aax-au-and-vst3-with-dsp-theory-2nbsped-1138591890-9781138591899.html](https://dokumen.pub/designing-audio-effect-plugins-in-c-for-aax-au-and-vst3-with-dsp-theory-2nbsped-1138591890-9781138591899.html)
12. [https://logic-nation.com/forum/index.php?topic=10166.0](https://logic-nation.com/forum/index.php?topic=10166.0)
13. [https://audioxpress.com/news/AD-480-Reverb-available-for-iOS-devices](https://audioxpress.com/news/AD-480-Reverb-available-for-iOS-devices)
14. [https://play0ad.com](https://play0ad.com/)
15. [https://apps.apple.com/us/app/ad-480-free-studio-reverb/id662715851](https://apps.apple.com/us/app/ad-480-free-studio-reverb/id662715851)
16. [https://www.youtube.com/watch?v=CB9syzYk-Oo](https://www.youtube.com/watch?v=CB9syzYk-Oo)
17. [https://developers.google.com/publisher-tag/guides/ad-sizes](https://developers.google.com/publisher-tag/guides/ad-sizes)
18. [https://forum.reasontalk.com/viewtopic.php?t=7532154](https://forum.reasontalk.com/viewtopic.php?t=7532154)
19. [https://gearspace.com/board/new-product-alert-2-older-threads/869662-ad480-pro-reverb-app-ios.html](https://gearspace.com/board/new-product-alert-2-older-threads/869662-ad480-pro-reverb-app-ios.html)
20. [https://developers.google.com/google-ads/api/fields/v20/ad_group_ad](https://developers.google.com/google-ads/api/fields/v20/ad_group_ad)
21. [https://www.youtube.com/watch?v=iR8vsx-S7_c](https://www.youtube.com/watch?v=iR8vsx-S7_c)
22. [https://ask.video/article/audio/ad-480-reverb-rich-reverb-sound-now-for-ios/fr](https://ask.video/article/audio/ad-480-reverb-rich-reverb-sound-now-for-ios/fr)
23. [https://support.google.com/admanager/answer/10320506?hl=en](https://support.google.com/admanager/answer/10320506?hl=en)
24. [https://www.kvraudio.com/product/ad-480-free-by-fiedler_audio](https://www.kvraudio.com/product/ad-480-free-by-fiedler_audio)
25. [https://www.kvraudio.com/product/ad-480-basic-by-fiedler_audio](https://www.kvraudio.com/product/ad-480-basic-by-fiedler_audio)
26. [https://www.reasonstudios.com/shop/rack-extension/ad-480-reverb/](https://www.reasonstudios.com/shop/rack-extension/ad-480-reverb/)
27. [https://caraudioworld.eu/en/product/audiosystem-ad480/](https://caraudioworld.eu/en/product/audiosystem-ad480/)
28. [https://apps.apple.com/in/app/ad-480-free-studio-reverb/id662715851](https://apps.apple.com/in/app/ad-480-free-studio-reverb/id662715851)
29. [https://www.youtube.com/watch?v=XE4GsAbeJn8](https://www.youtube.com/watch?v=XE4GsAbeJn8)
30. [https://www.youtube.com/watch?v=3AK40_brEbE](https://www.youtube.com/watch?v=3AK40_brEbE)
31. [https://fiedler-audio.com](https://fiedler-audio.com/)
32. [https://fiedler-audio.com/ad-480-reverb-re-rack-extension/](https://fiedler-audio.com/ad-480-reverb-re-rack-extension/)
33. [https://stackoverflow.com/questions/5318989/reverb-algorithm](https://stackoverflow.com/questions/5318989/reverb-algorithm)
34. [https://apps.apple.com/mu/developer/fiedler-tech-llc/id1557254098](https://apps.apple.com/mu/developer/fiedler-tech-llc/id1557254098)
35. [https://ask.audio/articles/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/fr](https://ask.audio/articles/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/fr)
36. [https://dsp.stackexchange.com/questions/2792/high-quality-reverb-algorithm](https://dsp.stackexchange.com/questions/2792/high-quality-reverb-algorithm)
37. [https://professionalsupport.dolby.com/s/question/0D54u0000AZs2jZCQR/feature-request-apple-spatial-audio-mp4-export-functionality-for-presonus-studio-one-and-fiedler-audio-products?language=en_US](https://professionalsupport.dolby.com/s/question/0D54u0000AZs2jZCQR/feature-request-apple-spatial-audio-mp4-export-functionality-for-presonus-studio-one-and-fiedler-audio-products?language=en_US)
38. [https://ask.video/article/audio/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/ko](https://ask.video/article/audio/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/ko)
39. [https://gist.github.com/mmalex/3a538aaba60f0ca21eac868269525452](https://gist.github.com/mmalex/3a538aaba60f0ca21eac868269525452)
40. [https://nebkelectronics.wordpress.com/2019/05/07/c-reverb-dsp-final-project/](https://nebkelectronics.wordpress.com/2019/05/07/c-reverb-dsp-final-project/)
41. [https://ez.analog.com/dsp/software-and-development-tools/sigmastudio-for-sharc/f/q-a/111125/latency-and-block-size-in-sigma-studio](https://ez.analog.com/dsp/software-and-development-tools/sigmastudio-for-sharc/f/q-a/111125/latency-and-block-size-in-sigma-studio)
42. [https://discourse.ardour.org/t/fiedler-audio-dolby-atmos-composer-in-ardour-with-wine-yabridge/111654](https://discourse.ardour.org/t/fiedler-audio-dolby-atmos-composer-in-ardour-with-wine-yabridge/111654)
43. [https://www.ti.com/lit/pdf/slyt159](https://www.ti.com/lit/pdf/slyt159)
44. [https://audiosciencereview.com/forum/index.php?threads%2Fdsp-filter-latency.31474%2F](https://audiosciencereview.com/forum/index.php?threads%2Fdsp-filter-latency.31474%2F)
45. [https://macprovideo.com/article/audio-software/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason?sess_id=nackoe9d5id5v6q4tpmu66oj17](https://macprovideo.com/article/audio-software/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason?sess_id=nackoe9d5id5v6q4tpmu66oj17)
46. [https://audiob.us/apps/capability/ab3/page/12](https://audiob.us/apps/capability/ab3/page/12)
47. [https://www.reddit.com/r/DSP/comments/1baxiyo/reverb_algorithm/](https://www.reddit.com/r/DSP/comments/1baxiyo/reverb_algorithm/)
48. [https://www.reddit.com/r/NeuralDSP/comments/14lhil0/advice_to_reduce_latency/](https://www.reddit.com/r/NeuralDSP/comments/14lhil0/advice_to_reduce_latency/)
49. [https://forum.juce.com/t/juce-8d-audio-filter/58960](https://forum.juce.com/t/juce-8d-audio-filter/58960)
50. [https://www.thomannmusic.com/fiedler_audio_dolby_atmos_composer.htm](https://www.thomannmusic.com/fiedler_audio_dolby_atmos_composer.htm)
51. [https://gearspace.com/board/music-computers/618474-audio-interface-low-latency-performance-data-base-84.html](https://gearspace.com/board/music-computers/618474-audio-interface-low-latency-performance-data-base-84.html)
52. [https://ask.video/article/news/ad-480-reverb-rich-reverb-sound-now-for-ios/ko](https://ask.video/article/news/ad-480-reverb-rich-reverb-sound-now-for-ios/ko)
53. [https://fr.audiofanzine.com/reverb-algorithmique-logicielle/fiedler-audio/ad-480-reverb-re/](https://fr.audiofanzine.com/reverb-algorithmique-logicielle/fiedler-audio/ad-480-reverb-re/)
54. [https://www.youtube.com/watch?v=Rdx5H0a0EzE](https://www.youtube.com/watch?v=Rdx5H0a0EzE)
55. [https://learn.microsoft.com/en-us/archive/msdn-magazine/2012/april/c-a-code-based-introduction-to-c-amp](https://learn.microsoft.com/en-us/archive/msdn-magazine/2012/april/c-a-code-based-introduction-to-c-amp)
56. [https://gearspace.com/board/new-product-alert-2-older-threads/1378264-fiedler-audio-releases-spacelab-groundbreaking-3d-audio-featured-object-based-plug.html](https://gearspace.com/board/new-product-alert-2-older-threads/1378264-fiedler-audio-releases-spacelab-groundbreaking-3d-audio-featured-object-based-plug.html)
57. [https://www.diva-portal.org/smash/get/diva2:816829/FULLTEXT01.pdf](https://www.diva-portal.org/smash/get/diva2:816829/FULLTEXT01.pdf)
58. [https://gliderverb.updatestar.com](https://gliderverb.updatestar.com/)
59. [https://visualsproducer.wordpress.com/2024/05/28/fiedler-audios-new-gravitas-mds-is-keystone-of-dolby-atmos-composer/](https://visualsproducer.wordpress.com/2024/05/28/fiedler-audios-new-gravitas-mds-is-keystone-of-dolby-atmos-composer/)
60. [https://www.kvraudio.com/news/fiedler-audio-updates-dolby-atmos-composer-to-v1-6---introduces-obam-object-based-audio-module-plug-in-standard-63986](https://www.kvraudio.com/news/fiedler-audio-updates-dolby-atmos-composer-to-v1-6---introduces-obam-object-based-audio-module-plug-in-standard-63986)
61. [https://www.adrian.edu/files/resources/2020-2021adriancollegeundergraduate.revised12.23.2020.pdf](https://www.adrian.edu/files/resources/2020-2021adriancollegeundergraduate.revised12.23.2020.pdf)
62. [https://sms.onlinelibrary.wiley.com/doi/10.1002/sej.1534](https://sms.onlinelibrary.wiley.com/doi/10.1002/sej.1534)
63. [https://groups.google.com/g/comp.lang.asm.x86/c/cJTAiqcPYik/m/0LqluZtTeooJ](https://groups.google.com/g/comp.lang.asm.x86/c/cJTAiqcPYik/m/0LqluZtTeooJ)
64. [https://www.synthtopia.com/content/2023/06/16/fiedler-audio-intros-spacelab-version-1-5-public-beta-with-direct-3d-reverb-feed-into-dolby-atmos-composer/](https://www.synthtopia.com/content/2023/06/16/fiedler-audio-intros-spacelab-version-1-5-public-beta-with-direct-3d-reverb-feed-into-dolby-atmos-composer/)
65. [https://www.tandfonline.com/doi/pdf/10.1080/14459795.2024.2355907](https://www.tandfonline.com/doi/pdf/10.1080/14459795.2024.2355907)
66. [https://www.kvraudio.com/developer/fiedler-audio](https://www.kvraudio.com/developer/fiedler-audio)
67. [https://www.scribd.com/document/888049203/Transactional-Memory-1st-Edition-James-Larus-instant-download](https://www.scribd.com/document/888049203/Transactional-Memory-1st-Edition-James-Larus-instant-download)
68. [https://github.com/fredwillmore/SI2](https://github.com/fredwillmore/SI2)
69. [https://www.youtube.com/watch?v=7jYYoLgwiKI](https://www.youtube.com/watch?v=7jYYoLgwiKI)
70. [https://www.synapse-audio.com/rackextensions-dr1.html](https://www.synapse-audio.com/rackextensions-dr1.html)
71. [https://www.youtube.com/watch?v=VIDQaTTVbU8](https://www.youtube.com/watch?v=VIDQaTTVbU8)
72. [http://www.originalsoundversion.com/editorial-propellerheads-rack-extensions-is-no-friend-of-plugins/](http://www.originalsoundversion.com/editorial-propellerheads-rack-extensions-is-no-friend-of-plugins/)
73. [https://turn2on.com](https://turn2on.com/)
74. [https://www.kvraudio.com/video/ad-480-reverb-re---front-panel-explained-3464](https://www.kvraudio.com/video/ad-480-reverb-re---front-panel-explained-3464)
75. [https://www.macprovideo.com/article/news/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/ru](https://www.macprovideo.com/article/news/fiedler-audio-release-ad-480-reverb-re-rack-extension-for-reason/ru)