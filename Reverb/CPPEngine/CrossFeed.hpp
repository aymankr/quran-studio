#pragma once

#include "Utils/AudioMath.hpp"
#include "Parameters.hpp"
#include <cmath>

namespace VoiceMonitor {

/// Professional stereo cross-feed processor
/// Implements various stereo width and imaging effects similar to AD 480
class CrossFeedProcessor {
public:
    CrossFeedProcessor();
    ~CrossFeedProcessor() = default;
    
    /// Initialize with sample rate
    void initialize(double sampleRate);
    
    /// Process stereo audio block
    void processBlock(float* leftChannel, float* rightChannel, int numSamples);
    
    /// Set cross-feed amount (0.0 = no effect, 1.0 = maximum cross-feed)
    void setCrossFeedAmount(float amount);
    
    /// Set stereo width (-1.0 = mono, 0.0 = normal, 1.0 = extra wide)
    void setStereoWidth(float width);
    
    /// Set phase inversion for one channel
    void setPhaseInvert(bool invertLeft, bool invertRight);
    
    /// Set frequency-dependent cross-feed (high-freq rolloff)
    void setHighFreqRolloff(float frequency); // Hz
    
    /// Set delay between channels for spatial effect
    void setInterChannelDelay(float delayMs); // milliseconds
    
    /// Enable/disable processing
    void setEnabled(bool enabled);
    
    /// Reset internal state
    void reset();
    
    /// Get current parameter values
    float getCrossFeedAmount() const { return crossFeedAmount_.getCurrentValue(); }
    float getStereoWidth() const { return stereoWidth_.getCurrentValue(); }
    bool isEnabled() const { return enabled_; }

private:
    // Core parameters
    SmoothParameter<float> crossFeedAmount_;
    SmoothParameter<float> stereoWidth_;
    SmoothParameter<float> highFreqRolloff_;
    SmoothParameter<float> interChannelDelay_;
    
    // State variables
    bool enabled_;
    bool phaseInvertLeft_;
    bool phaseInvertRight_;
    double sampleRate_;
    
    // High-frequency rolloff filters
    AudioMath::BiquadFilter highFreqFilterLeft_;
    AudioMath::BiquadFilter highFreqFilterRight_;
    
    // Inter-channel delay lines
    std::vector<float> delayBufferLeft_;
    std::vector<float> delayBufferRight_;
    int delayBufferSize_;
    int delayIndexLeft_;
    int delayIndexRight_;
    
    // Processing methods
    void updateFilters();
    void updateDelayLines();
    float processDelayLine(float input, std::vector<float>& buffer, int& index, float delaySamples);
};

/// Mid/Side stereo processor for advanced stereo manipulation
class MidSideProcessor {
public:
    MidSideProcessor() = default;
    ~MidSideProcessor() = default;
    
    /// Convert L/R to M/S
    static void encodeToMidSide(float left, float right, float& mid, float& side);
    
    /// Convert M/S to L/R
    static void decodeFromMidSide(float mid, float side, float& left, float& right);
    
    /// Process block with separate processing for mid and side
    void processBlock(float* leftChannel, float* rightChannel, int numSamples,
                     std::function<float(float)> midProcessor = nullptr,
                     std::function<float(float)> sideProcessor = nullptr);
    
    /// Set mid/side balance (-1.0 = only mid, 0.0 = balanced, 1.0 = only side)
    void setMidSideBalance(float balance);
    
    /// Set side channel gain
    void setSideGain(float gain);
    
    /// Set mid channel gain  
    void setMidGain(float gain);

private:
    float midSideBalance_ = 0.0f;
    float sideGain_ = 1.0f;
    float midGain_ = 1.0f;
};

/// Stereo chorus effect for width enhancement
class StereoChorus {
public:
    StereoChorus();
    ~StereoChorus() = default;
    
    /// Initialize with sample rate
    void initialize(double sampleRate, int maxDelayMs = 50);
    
    /// Process stereo block
    void processBlock(float* leftChannel, float* rightChannel, int numSamples);
    
    /// Set chorus rate (Hz)
    void setRate(float rateHz);
    
    /// Set chorus depth (0.0-1.0)
    void setDepth(float depth);
    
    /// Set stereo offset (phase difference between L/R modulation)
    void setStereoOffset(float offsetDegrees);
    
    /// Set feedback amount
    void setFeedback(float feedback);
    
    /// Set wet/dry mix
    void setWetDryMix(float wetDryMix);
    
    /// Reset state
    void reset();

private:
    double sampleRate_;
    
    // Delay lines
    std::vector<float> delayBufferLeft_;
    std::vector<float> delayBufferRight_;
    int delayBufferSize_;
    int writeIndexLeft_;
    int writeIndexRight_;
    
    // LFO state
    float lfoPhaseLeft_;
    float lfoPhaseRight_;
    float lfoRate_;
    float lfoDepth_;
    float stereoOffset_;
    
    // Parameters
    float feedback_;
    float wetDryMix_;
    float baseDelayMs_;
    
    // Processing helpers
    float processDelay(float input, std::vector<float>& buffer, int& writeIndex, float delayMs);
    float generateLFO(float& phase, float rate);
};

/// Haas effect processor for stereo widening
class HaasProcessor {
public:
    HaasProcessor();
    ~HaasProcessor() = default;
    
    /// Initialize with sample rate
    void initialize(double sampleRate);
    
    /// Process stereo block
    void processBlock(float* leftChannel, float* rightChannel, int numSamples);
    
    /// Set delay time for Haas effect (1-40ms typical)
    void setDelayTime(float delayMs);
    
    /// Set which channel gets delayed (true = delay right, false = delay left)
    void setDelayRight(bool delayRight);
    
    /// Set level reduction for delayed channel
    void setDelayedChannelLevel(float level);
    
    /// Set wet/dry mix
    void setWetDryMix(float wetDryMix);

private:
    double sampleRate_;
    
    // Delay buffer
    std::vector<float> delayBuffer_;
    int delayBufferSize_;
    int writeIndex_;
    
    // Parameters
    float delayTimeMs_;
    bool delayRight_;
    float delayedChannelLevel_;
    float wetDryMix_;
    
    // Processing
    float processDelay(float input, float delayMs);
};

/// Complete stereo enhancement suite
class StereoEnhancer {
public:
    StereoEnhancer();
    ~StereoEnhancer() = default;
    
    /// Initialize all processors
    void initialize(double sampleRate);
    
    /// Process complete stereo enhancement
    void processBlock(float* leftChannel, float* rightChannel, int numSamples);
    
    /// Cross-feed controls
    void setCrossFeedAmount(float amount);
    void setStereoWidth(float width);
    
    /// Chorus controls
    void setChorusEnabled(bool enabled);
    void setChorusRate(float rate);
    void setChorusDepth(float depth);
    void setChorusMix(float mix);
    
    /// Haas effect controls
    void setHaasEnabled(bool enabled);
    void setHaasDelay(float delayMs);
    void setHaasMix(float mix);
    
    /// Mid/Side controls
    void setMidSideEnabled(bool enabled);
    void setMidGain(float gain);
    void setSideGain(float gain);
    
    /// Master controls
    void setEnabled(bool enabled);
    void reset();

private:
    CrossFeedProcessor crossFeed_;
    StereoChorus chorus_;
    HaasProcessor haas_;
    MidSideProcessor midSide_;
    
    bool enabled_;
    bool chorusEnabled_;
    bool haasEnabled_;
    bool midSideEnabled_;
    
    // Temporary processing buffers
    std::vector<float> tempBufferLeft_;
    std::vector<float> tempBufferRight_;
};

} // namespace VoiceMonitor