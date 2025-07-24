import SwiftUI

struct CustomReverbView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.presentationMode) var presentationMode
    @State private var showingResetAlert = false
    
    // États locaux pour les paramètres personnalisés
    @State private var wetDryMix: Float = 35
    @State private var size: Float = 0.82
    @State private var decayTime: Float = 2.0
    @State private var preDelay: Float = 75.0
    @State private var crossFeed: Float = 0.5
    @State private var highFrequencyDamping: Float = 50.0
    @State private var density: Float = 70.0
    @State private var hasCrossFeed: Bool = false
    
    // Couleurs du thème
    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.13)
    private let sliderColor = Color.blue
    
    var body: some View {
        ZStack {
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 15) {
                    Text("Réverbération Personnalisée")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                    
                    // Description
                    Text("Ajustez les paramètres pour créer votre propre atmosphère acoustique.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                    
                    // Zone de réglages
                    VStack(spacing: 15) {
                        // Mélange Wet/Dry
                        DirectSliderView(
                            title: "Mélange (Wet/Dry)",
                            value: $wetDryMix,
                            range: 0...100,
                            step: 1,
                            icon: "slider.horizontal.3",
                            displayText: { String(Int($0)) + "%" },
                            onChange: { newValue in
                                wetDryMix = newValue
                                updateCustomReverb()
                            }
                        )
                        
                        // Taille de l'espace
                        DirectSliderView(
                            title: "Taille de l'espace",
                            value: $size,
                            range: 0...1,
                            step: 0.01,
                            icon: "rectangle.expand.vertical",
                            displayText: { String(Int($0 * 100)) + "%" },
                            onChange: { newValue in
                                size = newValue
                                updateCustomReverb()
                            }
                        )
                        
                        // Durée de réverbération
                        DirectSliderView(
                            title: "Durée de réverbération",
                            value: $decayTime,
                            range: 0.1...8,
                            step: 0.1,
                            icon: "clock",
                            displayText: { String(format: "%.1fs", $0) },
                            onChange: { newValue in
                                decayTime = newValue
                                updateCustomReverb()
                            },
                            highPriority: true
                        )
                        
                        // Pré-délai
                        DirectSliderView(
                            title: "Pré-délai",
                            value: $preDelay,
                            range: 0...200,
                            step: 1,
                            icon: "arrow.left.and.right",
                            displayText: { String(Int($0)) + "ms" },
                            onChange: { newValue in
                                preDelay = newValue
                                updateCustomReverb()
                            }
                        )
                        
                        // Cross-feed
                        VStack(alignment: .leading) {
                            Text("Diffusion stéréo (Cross-feed)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 12) {
                                Toggle("Activer", isOn: $hasCrossFeed)
                                    .toggleStyle(SwitchToggleStyle(tint: sliderColor))
                                    .foregroundColor(.white)
                                    .onChange(of: hasCrossFeed) { _ in
                                        updateCustomReverb()
                                    }
                                
                                if hasCrossFeed {
                                    HStack {
                                        DirectSlider(
                                            value: $crossFeed,
                                            range: 0...1,
                                            step: 0.01,
                                            onChange: { newValue in
                                                crossFeed = newValue
                                                updateCustomReverb()
                                            }
                                        )
                                        .accentColor(sliderColor)
                                        .disabled(!hasCrossFeed)
                                        
                                        Text(String(Int(crossFeed * 100)) + "%")
                                            .foregroundColor(.white)
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(12)
                        
                        // Atténuation des aigus
                        DirectSliderView(
                            title: "Atténuation des aigus",
                            value: $highFrequencyDamping,
                            range: 0...100,
                            step: 1,
                            icon: "waveform.path.ecg",
                            displayText: { String(Int($0)) + "%" },
                            onChange: { newValue in
                                highFrequencyDamping = newValue
                                updateCustomReverb()
                            }
                        )
                        
                        // Densité
                        DirectSliderView(
                            title: "Densité",
                            value: $density,
                            range: 0...100,
                            step: 1,
                            icon: "wave.3.right",
                            displayText: { String(Int($0)) + "%" },
                            onChange: { newValue in
                                density = newValue
                                updateCustomReverb()
                            }
                        )
                    }
                    .padding(.horizontal)
                    
                    // Boutons
                    HStack(spacing: 15) {
                        Button(action: {
                            showingResetAlert = true
                        }) {
                            Text("Réinitialiser")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.gray.opacity(0.6))
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("Fermer")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(sliderColor)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal)
                }
            }
        }
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Réinitialiser les paramètres"),
                message: Text("Êtes-vous sûr de vouloir revenir aux paramètres par défaut?"),
                primaryButton: .destructive(Text("Réinitialiser")) {
                    resetToDefaults()
                },
                secondaryButton: .cancel(Text("Annuler"))
            )
        }
        .onAppear {
            loadCurrentSettings()
            
            // S'assurer que nous sommes en mode personnalisé
            if audioManager.selectedReverbPreset != .custom {
                audioManager.updateReverbPreset(.custom)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Charge les paramètres actuels
    private func loadCurrentSettings() {
        let defaultSettings = CustomReverbSettings.default
        wetDryMix = defaultSettings.wetDryMix
        size = defaultSettings.size
        decayTime = defaultSettings.decayTime
        preDelay = defaultSettings.preDelay
        crossFeed = defaultSettings.crossFeed
        highFrequencyDamping = defaultSettings.highFrequencyDamping
        density = defaultSettings.density
        hasCrossFeed = false
    }
    
    /// Met à jour les paramètres de réverbération personnalisés
    private func updateCustomReverb() {
        // Créer une structure de paramètres personnalisés
        let customSettings = CustomReverbSettings(
            size: size,
            decayTime: decayTime,
            preDelay: preDelay,
            crossFeed: crossFeed,
            wetDryMix: wetDryMix,
            highFrequencyDamping: highFrequencyDamping,
            density: density
        )
        
        // Mettre à jour les paramètres statiques
        ReverbPreset.updateCustomSettings(customSettings)
        
        // Appliquer immédiatement si en mode custom
        if audioManager.selectedReverbPreset == .custom {
            audioManager.updateReverbPreset(.custom)
            
            // Mettre à jour le cross-feed si disponible
            audioEngineService?.updateCrossFeed(enabled: hasCrossFeed, value: crossFeed)
        }
    }
    
    /// Réinitialise aux valeurs par défaut
    private func resetToDefaults() {
        let defaultSettings = CustomReverbSettings.default
        
        withAnimation(.easeInOut(duration: 0.3)) {
            wetDryMix = defaultSettings.wetDryMix
            size = defaultSettings.size
            decayTime = defaultSettings.decayTime
            preDelay = defaultSettings.preDelay
            crossFeed = defaultSettings.crossFeed
            highFrequencyDamping = defaultSettings.highFrequencyDamping
            density = defaultSettings.density
            hasCrossFeed = false
        }
        
        // Appliquer immédiatement
        updateCustomReverb()
    }
    
    /// Référence à l'AudioEngineService
    private var audioEngineService: AudioEngineService? {
        return audioManager.audioEngineService
    }
}

// MARK: - DirectSlider avec Binding

/// Slider optimisé avec support de Binding
struct DirectSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let onChange: (Float) -> Void
    let highPriority: Bool
    
    @State private var isEditingNow = false
    @State private var lastUpdateTime = Date()
    private let throttleInterval: TimeInterval = 0.05
    private let highPriorityInterval: TimeInterval = 0.02
    
    init(value: Binding<Float>, range: ClosedRange<Float>, step: Float, onChange: @escaping (Float) -> Void, highPriority: Bool = false) {
        self._value = value
        self.range = range
        self.step = step
        self.onChange = onChange
        self.highPriority = highPriority
    }
    
    var body: some View {
        Slider(
            value: $value,
            in: range,
            step: step,
            onEditingChanged: { editing in
                isEditingNow = editing
                
                if !editing {
                    // Appliquer immédiatement à la fin de l'édition
                    onChange(value)
                }
            }
        )
        .onChange(of: value) { newValue in
            // Pendant l'édition, appliquer avec throttling
            if isEditingNow {
                let now = Date()
                let interval = highPriority ? highPriorityInterval : throttleInterval
                
                if now.timeIntervalSince(lastUpdateTime) >= interval {
                    onChange(newValue)
                    lastUpdateTime = now
                }
            } else {
                // Si pas en édition, appliquer immédiatement
                onChange(newValue)
            }
        }
    }
}

// MARK: - DirectSliderView avec Binding

/// Vue complète pour un slider avec titre, icône et affichage de valeur
struct DirectSliderView: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let icon: String
    let displayText: (Float) -> String
    let onChange: (Float) -> Void
    let highPriority: Bool
    
    init(title: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float, icon: String,
         displayText: @escaping (Float) -> String, onChange: @escaping (Float) -> Void, highPriority: Bool = false) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.icon = icon
        self.displayText = displayText
        self.onChange = onChange
        self.highPriority = highPriority
    }
    
    private let sliderColor = Color.blue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.white.opacity(0.7))
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            HStack {
                DirectSlider(
                    value: $value,
                    range: range,
                    step: step,
                    onChange: onChange,
                    highPriority: highPriority
                )
                .accentColor(sliderColor)
                
                Text(displayText(value))
                    .foregroundColor(.white)
                    .frame(width: 55, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct CustomReverbView_Previews: PreviewProvider {
    static var previews: some View {
        CustomReverbView(audioManager: AudioManager.shared)
            .preferredColorScheme(.dark)
    }
}
