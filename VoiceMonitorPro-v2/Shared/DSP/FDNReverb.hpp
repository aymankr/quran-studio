#pragma once

#include <vector>
#include <memory>
#include <cmath>

namespace VoiceMonitor {

/// High-quality FDN (Feedback Delay Network) reverb implementation
/// Based on professional reverb algorithms similar to AD 480
class FDNReverb {
public:
    static constexpr int DEFAULT_DELAY_LINES = 8;
    static constexpr int MAX_DELAY_LENGTH = 96000; // 1 second at 96kHz
    
private:
    // Delay line with interpolation
    class DelayLine {
    public:
        DelayLine(int maxLength);
        void setDelay(float delaySamples);
        float process(float input);
        void clear();
        
    private:
        std::vector<float> buffer_;
        int writeIndex_;
        float delay_;
        int maxLength_;
    };
    
    // All-pass filter for diffusion
    class AllPassFilter {
    public:
        AllPassFilter(int delayLength, float gain = 0.7f);
        float process(float input);
        void clear();
        void setGain(float gain) { gain_ = gain; }
        
    private:
        DelayLine delay_;
        float gain_;
    };
    
    // High-frequency damping filter
    class DampingFilter {
    public:
        DampingFilter();
        float process(float input);
        void setDamping(float damping); // 0.0 = no damping, 1.0 = full damping
        void clear();
        
    private:
        float dampingCoeff_;
        float state_;
    };
    
    // Modulated delay for chorus-like effects
    class ModulatedDelay {
    public:
        ModulatedDelay(int maxLength);
        void setBaseDelay(float delaySamples);
        void setModulation(float depth, float rate);
        float process(float input);
        void clear();
        void updateSampleRate(double sampleRate);
        
    private:
        DelayLine delay_;
        float baseDelay_;
        float modDepth_;
        float modRate_;
        float modPhase_;
        double sampleRate_;
    };

public:
    FDNReverb(double sampleRate, int numDelayLines = DEFAULT_DELAY_LINES);
    ~FDNReverb();
    
    // Core processing
    void processMono(const float* input, float* output, int numSamples);
    void processStereo(const float* inputL, const float* inputR, 
                      float* outputL, float* outputR, int numSamples);
    
    // Parameter control
    void setDecayTime(float decayTimeSeconds);
    void setPreDelay(float preDelaySamples);
    void setRoomSize(float size); // 0.0 - 1.0
    void setDensity(float density); // 0.0 - 1.0 (affects diffusion)
    void setHighFreqDamping(float damping); // 0.0 - 1.0
    void setModulation(float depth, float rate);
    
    // Utility
    void reset();
    void clear();
    void updateSampleRate(double sampleRate);
    
    // Quality settings
    void setDiffusionStages(int stages); // Number of all-pass stages
    void setInterpolation(bool enabled) { useInterpolation_ = enabled; }

private:
    // Core components
    std::vector<std::unique_ptr<DelayLine>> delayLines_;
    std::vector<std::unique_ptr<AllPassFilter>> diffusionFilters_;
    std::vector<std::unique_ptr<DampingFilter>> dampingFilters_;
    std::vector<std::unique_ptr<ModulatedDelay>> modulatedDelays_;
    
    // Configuration
    double sampleRate_;
    int numDelayLines_;
    bool useInterpolation_;
    
    // Current parameters
    float decayTime_;
    float preDelay_;
    float roomSize_;
    float density_;
    float highFreqDamping_;
    
    // FDN matrix and state
    std::vector<std::vector<float>> feedbackMatrix_;
    std::vector<float> delayOutputs_;
    std::vector<float> matrixOutputs_;
    
    // Pre-delay
    std::unique_ptr<DelayLine> preDelayLine_;
    
    // Internal processing buffers
    std::vector<float> tempBuffer_;
    
    // Initialization helpers
    void setupDelayLengths();
    void setupFeedbackMatrix();
    void calculateDelayLengths(std::vector<int>& lengths, float baseSize);
    void generateHouseholderMatrix();
    
    // Prime numbers for delay lengths (avoid flutter echoes)
    static const std::vector<int> PRIME_DELAYS;
    
    // DSP utilities
    float interpolateLinear(const std::vector<float>& buffer, float index, int bufferSize);
    void processMatrix();
};

} // namespace VoiceMonitor