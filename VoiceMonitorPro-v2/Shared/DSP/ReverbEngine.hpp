#pragma once

#include <vector>
#include <memory>
#include <atomic>
#include <cstdint>
#include "FDNReverb.hpp"
#include "CrossFeed.hpp"

namespace VoiceMonitor {

/// Main reverb engine implementing high-quality FDN (Feedback Delay Network)
/// Based on AD 480 specifications for studio-grade reverb quality
class ReverbEngine {
public:
    // Audio configuration
    static constexpr int MAX_CHANNELS = 2;
    static constexpr int MAX_DELAY_LINES = 8;
    static constexpr double MIN_SAMPLE_RATE = 44100.0;
    static constexpr double MAX_SAMPLE_RATE = 96000.0;
    
    // Preset definitions matching current Swift implementation
    enum class Preset {
        Clean,
        VocalBooth,
        Studio,
        Cathedral,
        Custom
    };
    
    // Parameter structure for thread-safe updates
    struct Parameters {
        std::atomic<float> wetDryMix{35.0f};        // 0-100%
        std::atomic<float> decayTime{2.0f};         // 0.1-8.0 seconds
        std::atomic<float> preDelay{75.0f};         // 0-200 ms
        std::atomic<float> crossFeed{0.5f};         // 0.0-1.0
        std::atomic<float> roomSize{0.82f};         // 0.0-1.0
        std::atomic<float> density{70.0f};          // 0-100%
        std::atomic<float> highFreqDamping{50.0f};  // 0-100%
        std::atomic<bool> bypass{false};
    };

public:
    ReverbEngine();
    ~ReverbEngine();
    
    // Core processing
    bool initialize(double sampleRate, int maxBlockSize = 512);
    void processBlock(const float* const* inputs, float* const* outputs, 
                     int numChannels, int numSamples);
    void reset();
    
    // Preset management
    void setPreset(Preset preset);
    Preset getCurrentPreset() const { return currentPreset_; }
    
    // Parameter control (thread-safe)
    void setWetDryMix(float value);
    void setDecayTime(float value);
    void setPreDelay(float value);
    void setCrossFeed(float value);
    void setRoomSize(float value);
    void setDensity(float value);
    void setHighFreqDamping(float value);
    void setBypass(bool bypass);
    
    // Getters
    float getWetDryMix() const { return params_.wetDryMix.load(); }
    float getDecayTime() const { return params_.decayTime.load(); }
    float getPreDelay() const { return params_.preDelay.load(); }
    float getCrossFeed() const { return params_.crossFeed.load(); }
    float getRoomSize() const { return params_.roomSize.load(); }
    float getDensity() const { return params_.density.load(); }
    float getHighFreqDamping() const { return params_.highFreqDamping.load(); }
    bool isBypassed() const { return params_.bypass.load(); }
    
    // Performance monitoring
    double getCpuUsage() const { return cpuUsage_.load(); }
    bool isInitialized() const { return initialized_; }

private:
    // Forward declarations
    class ParameterSmoother;
    class InternalCrossFeedProcessor;
    
    std::unique_ptr<FDNReverb> fdnReverb_;
    std::unique_ptr<StereoEnhancer> crossFeed_;
    std::unique_ptr<ParameterSmoother> smoother_;
    
    // Engine state
    Parameters params_;
    Preset currentPreset_;
    double sampleRate_;
    int maxBlockSize_;
    bool initialized_;
    
    // Performance monitoring
    std::atomic<double> cpuUsage_{0.0};
    
    // Internal processing buffers
    std::vector<std::vector<float>> tempBuffers_;
    std::vector<float> wetBuffer_;
    std::vector<float> dryBuffer_;
    
    // Preset configurations
    void applyPresetParameters(Preset preset);
    void updateInternalParameters();
    
    // Utility functions
    float clamp(float value, float min, float max) const;
};

} // namespace VoiceMonitor