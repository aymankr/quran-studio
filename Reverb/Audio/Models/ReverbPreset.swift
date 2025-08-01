import Foundation
import AVFoundation

/// Structure for custom reverb settings
public struct CustomReverbSettings {
    var size: Float = 0.82             // 0.0-1.0 (relates to room dimensions)
    var decayTime: Float = 2.0         // 0.1-8.0 seconds
    var preDelay: Float = 75.0         // 0-200 ms
    var crossFeed: Float = 0.5         // 0.0-1.0 (stereo spread)
    var wetDryMix: Float = 35          // 0-100%
    var highFrequencyDamping: Float = 50.0 // 0-100%
    var density: Float = 70.0          // 0-100%
    
    static let `default` = CustomReverbSettings()
}

/// Model for reverb presets optimized for Quranic recitation
public enum ReverbPreset: String, CaseIterable, Identifiable {
    // Préréglages optimisés pour la récitation coranique
    case clean = "Clean"          // Voix pure, sans effet
    case vocalBooth = "Vocal Booth" // Légère ambiance, clarté maximale
    case studio = "Studio"        // Ambiance équilibrée, présence harmonieuse
    case cathedral = "Cathedral"    // Réverbération noble et profonde
    case custom = "Personnalisé"    // Paramètres personnalisés par l'utilisateur
    
    public var id: String { rawValue }
    
    /// Returns the corresponding AVAudioUnitReverbPreset as base
    var preset: AVAudioUnitReverbPreset {
        switch self {
        case .clean: return .smallRoom
        case .vocalBooth: return .mediumRoom
        case .studio: return .largeRoom
        case .cathedral: return .mediumHall // Ajusté pour plus de stabilité
        case .custom: return .mediumHall    // Base pour paramétrage personnalisé
        }
    }
    
    /// Returns the wet/dry mix value (0-100)
    var wetDryMix: Float {
        switch self {
        case .clean: return 0       // Aucun effet
        case .vocalBooth: return 18   // Subtil mais perceptible
        case .studio: return 40     // Équilibré, présence notable
        case .cathedral: return 65   // Important mais pas excessif pour éviter les saccades
        case .custom: return CustomReverbSettings.default.wetDryMix
        }
    }
    
    /// Returns the decay time in seconds
    var decayTime: Float {
        switch self {
        case .clean: return 0.1
        case .vocalBooth: return 0.9  // Légèrement plus long pour la douceur
        case .studio: return 1.7      // Durée moyenne pour l'intelligibilité
        case .cathedral: return 2.8   // Réduit pour éviter les saccades, reste noble
        case .custom: return CustomReverbSettings.default.decayTime
        }
    }
    
    /// Returns pre-delay in ms (0-100ms)
    var preDelay: Float {
        switch self {
        case .clean: return 0
        case .vocalBooth: return 8     // Clarté des consonnes
        case .studio: return 15        // Séparation naturelle
        case .cathedral: return 25     // Réduit pour éviter les saccades
        case .custom: return CustomReverbSettings.default.preDelay
        }
    }
    
    /// Returns room size (0-100)
    var roomSize: Float {
        switch self {
        case .clean: return 0
        case .vocalBooth: return 35    // Pièce intime
        case .studio: return 60        // Espace confortable
        case .cathedral: return 85     // Grande mais pas maximale pour maintenir la stabilité
        case .custom: return CustomReverbSettings.default.size * 100 // Convert 0-1 to 0-100
        }
    }
    
    /// Returns density value (0-100)
    var density: Float {
        switch self {
        case .clean: return 0
        case .vocalBooth: return 70    // Dense pour éviter le flottement
        case .studio: return 85        // Naturel et riche
        case .cathedral: return 60     // Réduit pour limiter la charge CPU
        case .custom: return CustomReverbSettings.default.density
        }
    }
    
    /// Returns HF damping (0-100) - Contrôle l'absorption des hautes fréquences
    var highFrequencyDamping: Float {
        switch self {
        case .clean: return 0
        case .vocalBooth: return 30    // Conserve la clarté
        case .studio: return 45        // Équilibré
        case .cathedral: return 60     // Plus d'absorption pour limiter les résonances aiguës
        case .custom: return CustomReverbSettings.default.highFrequencyDamping
        }
    }
    
    /// Returns the cross feed value (0-100)
    var crossFeed: Float {
        switch self {
        case .clean: return 0
        case .vocalBooth: return 30    // Stéréo légère
        case .studio: return 50        // Équilibré
        case .cathedral: return 70     // Large espace
        case .custom: return CustomReverbSettings.default.crossFeed * 100 // Convert 0-1 to 0-100
        }
    }
    
    /// Description of how this preset affects recitation
    var description: String {
        switch self {
        case .clean:
            return "Signal pur, fidèle à la voix originale, sans aucun effet."
        case .vocalBooth:
            return "Légère ambiance spatiale qui préserve la clarté et l'intelligibilité de chaque mot."
        case .studio:
            return "Réverbération équilibrée qui enrichit la voix tout en conservant la précision de la récitation."
        case .cathedral:
            return "Profondeur et noblesse qui évoquent l'espace d'un lieu de culte, pour une récitation solennelle."
        case .custom:
            return "Paramètres personnalisés pour créer votre propre environnement acoustique."
        }
    }
}

// MARK: - Extensions pour la gestion des paramètres personnalisés

extension ReverbPreset {
    /// Retourne les paramètres personnalisés avec une source statique
    static var customSettings: CustomReverbSettings = CustomReverbSettings.default
    
    /// Met à jour les paramètres personnalisés
    static func updateCustomSettings(_ settings: CustomReverbSettings) {
        customSettings = settings
    }
    
    /// Version avec paramètres dynamiques
    func values(with customSettings: CustomReverbSettings? = nil) -> (wetDryMix: Float, decayTime: Float, preDelay: Float, roomSize: Float, density: Float, highFrequencyDamping: Float, crossFeed: Float) {
        let settings = customSettings ?? ReverbPreset.customSettings
        
        switch self {
        case .clean:
            return (0, 0.1, 0, 0, 0, 0, 0)
        case .vocalBooth:
            return (18, 0.9, 8, 35, 70, 30, 30)
        case .studio:
            return (40, 1.7, 15, 60, 85, 45, 50)
        case .cathedral:
            return (65, 2.8, 25, 85, 60, 60, 70)
        case .custom:
            return (settings.wetDryMix, settings.decayTime, settings.preDelay, settings.size * 100, settings.density, settings.highFrequencyDamping, settings.crossFeed * 100)
        }
    }
}
