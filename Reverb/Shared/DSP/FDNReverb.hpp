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
        float lastOutput_; // State for all-pass feedback
    };
    
    // Professional damping filter with separate HF/LF biquads (AD 480 style)
    class DampingFilter {
    public:
        DampingFilter(double sampleRate = 48000.0);
        float process(float input);
        void setHFDamping(float dampingPercent, float cutoffHz = 8000.0f);  // HF: 1kHz-12kHz range
        void setLFDamping(float dampingPercent, float cutoffHz = 200.0f);   // LF: 50Hz-500Hz range
        void updateSampleRate(double sampleRate);
        void clear();
        
        // Getters for current state
        float getHFCutoff() const { return hfCutoffHz_; }
        float getLFCutoff() const { return lfCutoffHz_; }
        float getHFDamping() const { return hfDampingPercent_; }
        float getLFDamping() const { return lfDampingPercent_; }
        
    private:
        // Professional biquad filter implementation
        struct BiquadFilter {
            float b0, b1, b2;  // Numerator coefficients
            float a1, a2;      // Denominator coefficients (a0 = 1)
            float x1, x2;      // Input delay states
            float y1, y2;      // Output delay states
            
            BiquadFilter() : b0(1), b1(0), b2(0), a1(0), a2(0), x1(0), x2(0), y1(0), y2(0) {}
            
            float process(float input) {
                // Direct Form II implementation
                float output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
                
                // Update delay states
                x2 = x1; x1 = input;
                y2 = y1; y1 = output;
                
                return output;
            }
            
            void clear() {
                x1 = x2 = y1 = y2 = 0.0f;
            }
        };
        
        BiquadFilter hfFilter_;         // High-frequency lowpass filter
        BiquadFilter lfFilter_;         // Low-frequency highpass filter
        
        double sampleRate_;             // Current sample rate
        float hfCutoffHz_;              // HF cutoff frequency
        float lfCutoffHz_;              // LF cutoff frequency
        float hfDampingPercent_;        // HF damping amount (0-100%)
        float lfDampingPercent_;        // LF damping amount (0-100%)
        
        // Calculate Butterworth lowpass biquad coefficients
        void calculateLowpassCoeffs(BiquadFilter& filter, float cutoffHz, float dampingPercent);
        
        // Calculate Butterworth highpass biquad coefficients  
        void calculateHighpassCoeffs(BiquadFilter& filter, float cutoffHz, float dampingPercent);
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
    
    // Professional stereo cross-feed processor (AD 480 style)
    class CrossFeedProcessor {
    public:
        CrossFeedProcessor(double sampleRate = 48000.0);
        void processStereo(float* left, float* right, int numSamples);
        void setCrossFeedAmount(float amount);     // 0.0 = no cross-feed, 1.0 = full mono mix
        void setCrossDelayMs(float delayMs);       // Cross-feed delay in milliseconds (0-50ms)
        void setPhaseInversion(bool invert);       // L/R phase inversion on cross-feed
        void setStereoWidth(float width);         // 0.0 = mono, 2.0 = wide stereo
        void setBypass(bool bypass);              // Bypass cross-feed processing
        void updateSampleRate(double sampleRate);
        void clear();
        
        // Getters for current state
        float getCrossFeedAmount() const { return crossFeedAmount_; }
        float getCrossDelayMs() const { return crossDelayMs_; }
        bool getPhaseInversion() const { return phaseInvert_; }
        bool isBypassed() const { return bypass_; }
        
    private:
        std::unique_ptr<DelayLine> crossDelayL_;   // L->R cross-feed delay
        std::unique_ptr<DelayLine> crossDelayR_;   // R->L cross-feed delay
        
        float crossFeedAmount_;    // 0.0 to 1.0
        float crossDelayMs_;       // Delay in milliseconds
        float stereoWidth_;        // Stereo width control
        bool phaseInvert_;         // Phase inversion on cross-feed
        bool bypass_;              // Bypass cross-feed
        double sampleRate_;        // Sample rate for delay calculation
        
        void updateDelayLengths(); // Update delay lines when parameters change
    };
    
    // Professional stereo spread processor (AD 480 "Spread" control)
    class StereoSpreadProcessor {
    public:
        StereoSpreadProcessor();
        void processStereo(float* left, float* right, int numSamples);
        void setStereoWidth(float width);           // 0.0 = mono, 1.0 = natural, 2.0 = wide
        void setCompensateGain(bool compensate);    // Compensate mid gain for constant volume
        void clear();
        
        // Getters for current state
        float getStereoWidth() const { return stereoWidth_; }
        bool isGainCompensated() const { return compensateGain_; }
        
    private:
        float stereoWidth_;        // 0.0 to 2.0 range
        bool compensateGain_;      // Gain compensation for constant volume
        
        // Calculate compensation gain for constant perceived volume
        float calculateMidGainCompensation(float width) const;
    };
    
    // Professional tone filter for global High Cut and Low Cut (AD 480 style)
    class ToneFilter {
    public:
        ToneFilter(double sampleRate = 48000.0);
        void processStereo(float* left, float* right, int numSamples);
        void setHighCutFreq(float freqHz);          // High cut filter (lowpass)
        void setLowCutFreq(float freqHz);           // Low cut filter (highpass)
        void setHighCutEnabled(bool enabled);       // Enable/disable high cut
        void setLowCutEnabled(bool enabled);        // Enable/disable low cut
        void updateSampleRate(double sampleRate);
        void clear();
        
        // Getters for current state
        float getHighCutFreq() const { return highCutFreq_; }
        float getLowCutFreq() const { return lowCutFreq_; }
        bool isHighCutEnabled() const { return highCutEnabled_; }
        bool isLowCutEnabled() const { return lowCutEnabled_; }
        
    private:
        // Reuse BiquadFilter struct from DampingFilter
        struct BiquadFilter {
            float b0, b1, b2;  // Numerator coefficients
            float a1, a2;      // Denominator coefficients (a0 = 1)
            float x1, x2;      // Input delay states
            float y1, y2;      // Output delay states
            
            BiquadFilter() : b0(1), b1(0), b2(0), a1(0), a2(0), x1(0), x2(0), y1(0), y2(0) {}
            
            float process(float input) {
                // Direct Form II implementation
                float output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
                
                // Update delay states
                x2 = x1; x1 = input;
                y2 = y1; y1 = output;
                
                return output;
            }
            
            void clear() {
                x1 = x2 = y1 = y2 = 0.0f;
            }
        };
        
        // Stereo filters (L and R channels)
        BiquadFilter highCutL_, highCutR_;     // High cut (lowpass) filters
        BiquadFilter lowCutL_, lowCutR_;       // Low cut (highpass) filters
        
        double sampleRate_;         // Current sample rate
        float highCutFreq_;         // High cut frequency (Hz)
        float lowCutFreq_;          // Low cut frequency (Hz)
        bool highCutEnabled_;       // High cut filter enabled
        bool lowCutEnabled_;        // Low cut filter enabled
        
        // Calculate biquad coefficients for filters
        void calculateLowpassCoeffs(BiquadFilter& filter, float cutoffHz);
        void calculateHighpassCoeffs(BiquadFilter& filter, float cutoffHz);
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
    void setLowFreqDamping(float damping);  // 0.0 - 1.0 (AD 480 feature)
    void setModulation(float depth, float rate);
    
    // Advanced stereo control (AD 480 style)
    void setCrossFeedAmount(float amount);      // 0.0 = no cross-feed, 1.0 = full mono mix
    void setCrossDelayMs(float delayMs);        // Cross-feed delay in milliseconds (0-50ms)
    void setPhaseInversion(bool invert);        // L/R phase inversion on cross-feed
    void setStereoWidth(float width);           // 0.0 = mono, 2.0 = wide stereo (Cross-feed processor)
    void setCrossFeedBypass(bool bypass);       // Bypass cross-feed processing
    
    // Stereo spread control (AD 480 "Spread" - output wet processing)
    void setStereoSpread(float spread);         // 0.0 = mono wet, 1.0 = natural, 2.0 = wide wet
    void setStereoSpreadCompensation(bool compensate); // Compensate mid gain for constant volume
    
    // Global tone control (AD 480 "High Cut" and "Low Cut" - output EQ)
    void setHighCutFreq(float freqHz);          // High cut filter frequency (1kHz-20kHz)
    void setLowCutFreq(float freqHz);           // Low cut filter frequency (20Hz-1kHz)
    void setHighCutEnabled(bool enabled);       // Enable/disable high cut filter
    void setLowCutEnabled(bool enabled);        // Enable/disable low cut filter
    
    // Utility
    void reset();
    void clear();
    void updateSampleRate(double sampleRate);
    
    // Quality settings
    void setDiffusionStages(int stages); // Number of all-pass stages
    void setInterpolation(bool enabled) { useInterpolation_ = enabled; }
    
    // Diagnostic and optimization methods
    void printFDNConfiguration() const; // Debug: print current FDN setup
    bool verifyMatrixOrthogonality() const; // Verify feedback matrix properties
    std::vector<int> getCurrentDelayLengths() const; // Get current delay lengths
    
    // RT60 validation methods
    std::vector<float> generateImpulseResponse(int lengthSamples = 48000 * 4); // 4 seconds at 48kHz
    float measureRT60FromImpulseResponse(const std::vector<float>& impulseResponse) const;

private:
    // Core components
    std::vector<std::unique_ptr<DelayLine>> delayLines_;
    std::vector<std::unique_ptr<AllPassFilter>> diffusionFilters_;
    std::vector<std::unique_ptr<DampingFilter>> dampingFilters_;
    std::vector<std::unique_ptr<ModulatedDelay>> modulatedDelays_;
    std::unique_ptr<CrossFeedProcessor> crossFeedProcessor_;
    std::unique_ptr<StereoSpreadProcessor> stereoSpreadProcessor_;
    std::unique_ptr<ToneFilter> toneFilter_;
    
    // Early reflections processing (before FDN)
    std::vector<std::unique_ptr<AllPassFilter>> earlyReflectionFilters_;
    static constexpr int MAX_EARLY_REFLECTIONS = 4;
    int numEarlyReflections_;
    
    // Configuration
    double sampleRate_;
    int numDelayLines_;
    bool useInterpolation_;
    
    // Buffer flush management for size changes
    float lastRoomSize_;
    bool needsBufferFlush_;
    static constexpr float ROOM_SIZE_CHANGE_THRESHOLD = 0.05f;
    
    // Current parameters
    float decayTime_;
    float preDelay_;
    float roomSize_;
    float density_;
    float highFreqDamping_;
    float lowFreqDamping_;
    
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
    void setupEarlyReflections();
    
    // Buffer management for size changes
    void checkAndFlushBuffers();
    void flushAllBuffers();
    
    // AD 480 calibration helpers
    float calculateAverageDelayTime();
    float calculateMaxDecayForSize(float roomSize);
    
    // Prime numbers for delay lengths (avoid flutter echoes)
    static const std::vector<int> PRIME_DELAYS;
    static const std::vector<int> EARLY_REFLECTION_DELAYS; // Prime delays for early reflections
    
    // DSP utilities
    float interpolateLinear(const std::vector<float>& buffer, float index, int bufferSize);
    void processMatrix();
    float processEarlyReflections(float input);
};

} // namespace VoiceMonitor