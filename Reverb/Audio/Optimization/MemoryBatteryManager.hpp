#pragma once

#include <memory>
#include <vector>
#include <atomic>
#include <thread>
#include <chrono>
#include <cmath>

#ifdef __APPLE__
#include <mach/mach.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>
#endif

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

namespace Reverb {
namespace Optimization {

/**
 * @brief Memory and battery optimization manager for iOS devices
 * 
 * This manager handles:
 * - Memory allocation strategy optimized for iOS constraints
 * - Denormal prevention for CPU efficiency
 * - Battery-aware processing modes
 * - Background audio management
 * - Performance monitoring and adaptive quality
 */

class MemoryBatteryManager {
public:
    
    // Battery and performance modes
    enum class PowerMode {
        HighPerformance,    // Full quality, maximum CPU usage
        Balanced,          // Good quality, moderate CPU usage  
        PowerSaver,        // Reduced quality, minimum CPU usage
        Background         // Minimal processing, background-friendly
    };
    
    // Memory allocation strategy
    enum class MemoryStrategy {
        Preallocated,      // Pre-allocate all buffers at startup
        Dynamic,           // Allocate buffers as needed
        Pooled             // Use memory pools for frequent allocations
    };
    
    // Audio processing quality levels
    enum class ProcessingQuality {
        Maximum,           // Full reverb algorithm, all features
        High,             // Reduced reverb tails, good quality
        Standard,         // Basic reverb, acceptable quality
        Minimal           // Simple delay-based reverb only
    };
    
private:
    // Current system state
    std::atomic<PowerMode> currentPowerMode_{PowerMode::Balanced};
    std::atomic<ProcessingQuality> currentQuality_{ProcessingQuality::Standard};
    std::atomic<bool> isBackgroundMode_{false};
    std::atomic<bool> isLowBattery_{false};
    std::atomic<bool> isThermalThrottling_{false};
    
    // Memory management
    MemoryStrategy memoryStrategy_;
    size_t totalAllocatedMemory_;
    size_t maxMemoryBudget_;
    std::atomic<size_t> currentMemoryUsage_{0};
    
    // Performance monitoring
    std::atomic<double> averageCPULoad_{0.0};
    std::atomic<double> peakCPULoad_{0.0};
    std::atomic<uint64_t> denormalPreventionCount_{0};
    
    // Battery monitoring (iOS specific)
#ifdef __APPLE__
    std::atomic<float> batteryLevel_{1.0f};
    std::atomic<bool> isCharging_{false};
    std::thread batteryMonitorThread_;
    std::atomic<bool> shouldMonitorBattery_{false};
#endif
    
    // Memory pools for frequent allocations
    struct MemoryPool {
        std::vector<std::unique_ptr<float[]>> buffers;
        std::vector<bool> isUsed;
        size_t bufferSize;
        size_t alignment;
        
        MemoryPool(size_t size, size_t align, size_t count) 
            : bufferSize(size), alignment(align) {
            buffers.reserve(count);
            isUsed.resize(count, false);
            
            for (size_t i = 0; i < count; ++i) {
#ifdef __APPLE__
                void* ptr = aligned_alloc(align, size * sizeof(float));
#else
                void* ptr = std::aligned_alloc(align, size * sizeof(float));
#endif
                buffers.emplace_back(static_cast<float*>(ptr));
            }
        }
        
        ~MemoryPool() {
            for (auto& buffer : buffers) {
                free(buffer.release());
            }
        }
    };
    
    std::vector<std::unique_ptr<MemoryPool>> memoryPools_;
    
public:
    
    /**
     * @brief Initialize memory and battery manager
     * 
     * @param memoryBudgetMB Maximum memory budget in megabytes
     * @param strategy Memory allocation strategy
     */
    explicit MemoryBatteryManager(size_t memoryBudgetMB = 32, 
                                 MemoryStrategy strategy = MemoryStrategy::Pooled)
        : memoryStrategy_(strategy)
        , totalAllocatedMemory_(0)
        , maxMemoryBudget_(memoryBudgetMB * 1024 * 1024) {
        
        // Initialize memory pools for common buffer sizes
        if (strategy == MemoryStrategy::Pooled) {
            initializeMemoryPools();
        }
        
        // Start battery monitoring on iOS
#ifdef __APPLE__
        startBatteryMonitoring();
#endif
        
        // Set initial power mode based on system state
        updatePowerMode();
    }
    
    ~MemoryBatteryManager() {
#ifdef __APPLE__
        stopBatteryMonitoring();
#endif
    }
    
    // Disable copy and move for singleton-like behavior
    MemoryBatteryManager(const MemoryBatteryManager&) = delete;
    MemoryBatteryManager& operator=(const MemoryBatteryManager&) = delete;
    
    /**
     * @brief Allocate aligned memory buffer optimized for iOS
     * 
     * @param numElements Number of float elements
     * @param alignment Memory alignment (16 for NEON, 32 for AVX)
     * @return Aligned pointer or nullptr on failure
     */
    float* allocateAlignedBuffer(size_t numElements, size_t alignment = 16) {
        const size_t sizeBytes = numElements * sizeof(float);
        
        // Check memory budget
        if (currentMemoryUsage_.load() + sizeBytes > maxMemoryBudget_) {
            // Try to free unused buffers from pools
            if (!reclaimPoolMemory(sizeBytes)) {
                return nullptr; // Out of memory budget
            }
        }
        
        float* buffer = nullptr;
        
        if (memoryStrategy_ == MemoryStrategy::Pooled) {
            buffer = allocateFromPool(numElements, alignment);
        }
        
        if (!buffer) {
            // Fallback to direct allocation
#ifdef __APPLE__
            buffer = static_cast<float*>(aligned_alloc(alignment, 
                                        ((sizeBytes + alignment - 1) / alignment) * alignment));
#else
            buffer = static_cast<float*>(std::aligned_alloc(alignment, 
                                        ((sizeBytes + alignment - 1) / alignment) * alignment));
#endif
        }
        
        if (buffer) {
            currentMemoryUsage_.fetch_add(sizeBytes);
            totalAllocatedMemory_ += sizeBytes;
        }
        
        return buffer;
    }
    
    /**
     * @brief Free aligned memory buffer
     * 
     * @param buffer Pointer to buffer
     * @param numElements Number of elements (for pool management)
     */
    void freeAlignedBuffer(float* buffer, size_t numElements = 0) {
        if (!buffer) return;
        
        const size_t sizeBytes = numElements * sizeof(float);
        
        if (memoryStrategy_ == MemoryStrategy::Pooled && numElements > 0) {
            if (returnToPool(buffer, numElements)) {
                // Successfully returned to pool, don't actually free
                return;
            }
        }
        
        // Direct deallocation
        free(buffer);
        
        if (sizeBytes > 0) {
            currentMemoryUsage_.fetch_sub(sizeBytes);
        }
    }
    
    /**
     * @brief Prevent denormals in audio buffer using ARM64 optimizations
     * 
     * Denormals can cause significant CPU overhead on some processors.
     * This function adds tiny DC offset to prevent denormal calculations.
     * 
     * @param buffer Audio buffer to process
     * @param numSamples Number of samples
     * @param dcOffset DC offset to add (default optimized for ARM64)
     */
    void preventDenormals(float* buffer, size_t numSamples, float dcOffset = 1.0e-25f) {
        denormalPreventionCount_.fetch_add(1);
        
#ifdef __ARM_NEON__
        // Use NEON SIMD for efficient processing
        const float32x4_t dc_vec = vdupq_n_f32(dcOffset);
        const size_t numChunks = numSamples / 4;
        
        for (size_t i = 0; i < numChunks; ++i) {
            const size_t idx = i * 4;
            float32x4_t samples = vld1q_f32(&buffer[idx]);
            samples = vaddq_f32(samples, dc_vec);
            vst1q_f32(&buffer[idx], samples);
        }
        
        // Handle remaining samples
        for (size_t i = numChunks * 4; i < numSamples; ++i) {
            buffer[i] += dcOffset;
        }
#else
        // Fallback implementation
        for (size_t i = 0; i < numSamples; ++i) {
            buffer[i] += dcOffset;
        }
#endif
    }
    
    /**
     * @brief Apply DC blocking filter to prevent denormals
     * 
     * High-pass filter that removes DC component and prevents denormals
     * More sophisticated than simple DC offset addition
     * 
     * @param input Input buffer
     * @param output Output buffer (can be same as input)
     * @param numSamples Number of samples
     * @param cutoffHz Cutoff frequency in Hz (typically 20 Hz)
     * @param sampleRate Sample rate
     * @param state Filter state (persistent across calls)
     */
    void dcBlockingFilter(const float* input, float* output, size_t numSamples,
                         float cutoffHz, float sampleRate, float& state) {
        
        // Calculate filter coefficient
        const float omega = 2.0f * M_PI * cutoffHz / sampleRate;
        const float alpha = std::exp(-omega);
        
        float prevInput = state;
        float prevOutput = 0.0f;
        
        for (size_t i = 0; i < numSamples; ++i) {
            const float currentInput = input[i];
            const float currentOutput = alpha * (prevOutput + currentInput - prevInput);
            
            output[i] = currentOutput;
            
            prevInput = currentInput;
            prevOutput = currentOutput;
        }
        
        // Update state
        state = prevInput;
    }
    
    /**
     * @brief Get current power mode
     */
    PowerMode getPowerMode() const {
        return currentPowerMode_.load();
    }
    
    /**
     * @brief Set power mode manually
     * 
     * @param mode New power mode
     */
    void setPowerMode(PowerMode mode) {
        currentPowerMode_.store(mode);
        adaptProcessingQuality();
    }
    
    /**
     * @brief Get current processing quality
     */
    ProcessingQuality getProcessingQuality() const {
        return currentQuality_.load();
    }
    
    /**
     * @brief Check if app is in background mode
     */
    bool isInBackgroundMode() const {
        return isBackgroundMode_.load();
    }
    
    /**
     * @brief Set background mode state
     * 
     * @param background True if app is in background
     */
    void setBackgroundMode(bool background) {
        isBackgroundMode_.store(background);
        updatePowerMode();
    }
    
    /**
     * @brief Get current memory usage in bytes
     */
    size_t getCurrentMemoryUsage() const {
        return currentMemoryUsage_.load();
    }
    
    /**
     * @brief Get memory usage percentage of budget
     */
    double getMemoryUsagePercent() const {
        return static_cast<double>(currentMemoryUsage_.load()) / maxMemoryBudget_ * 100.0;
    }
    
    /**
     * @brief Update CPU load statistics
     * 
     * @param currentLoad Current CPU load (0.0 to 100.0)
     */
    void updateCPULoad(double currentLoad) {
        // Update running average
        const double prevAvg = averageCPULoad_.load();
        const double newAvg = prevAvg * 0.95 + currentLoad * 0.05; // 95% decay
        averageCPULoad_.store(newAvg);
        
        // Update peak
        double currentPeak = peakCPULoad_.load();
        while (currentLoad > currentPeak && 
               !peakCPULoad_.compare_exchange_weak(currentPeak, currentLoad)) {
            // Retry until successful
        }
        
        // Check for thermal throttling based on sustained high CPU
        if (newAvg > 80.0) {
            isThermalThrottling_.store(true);
            updatePowerMode();
        } else if (newAvg < 60.0) {
            isThermalThrottling_.store(false);
        }
    }
    
    /**
     * @brief Get recommended buffer size based on current power mode
     * 
     * @param basebufferSize Base buffer size
     * @return Recommended buffer size
     */
    size_t getRecommendedBufferSize(size_t baseBufferSize) const {
        switch (currentPowerMode_.load()) {
            case PowerMode::HighPerformance:
                return baseBufferSize; // Use minimum latency
            case PowerMode::Balanced:
                return baseBufferSize * 2; // Balanced latency/power
            case PowerMode::PowerSaver:
                return baseBufferSize * 4; // Higher latency, lower power
            case PowerMode::Background:
                return baseBufferSize * 8; // Maximum latency for background
        }
        return baseBufferSize;
    }
    
    /**
     * @brief Get performance statistics
     */
    struct PerformanceStats {
        double averageCPULoad;
        double peakCPULoad;
        size_t currentMemoryUsage;
        double memoryUsagePercent;
        uint64_t denormalPreventionCount;
        PowerMode currentPowerMode;
        ProcessingQuality currentQuality;
        bool isLowBattery;
        bool isThermalThrottling;
        float batteryLevel;
        bool isCharging;
    };
    
    PerformanceStats getPerformanceStats() const {
        return {
            .averageCPULoad = averageCPULoad_.load(),
            .peakCPULoad = peakCPULoad_.load(),
            .currentMemoryUsage = currentMemoryUsage_.load(),
            .memoryUsagePercent = getMemoryUsagePercent(),
            .denormalPreventionCount = denormalPreventionCount_.load(),
            .currentPowerMode = currentPowerMode_.load(),
            .currentQuality = currentQuality_.load(),
            .isLowBattery = isLowBattery_.load(),
            .isThermalThrottling = isThermalThrottling_.load(),
#ifdef __APPLE__
            .batteryLevel = batteryLevel_.load(),
            .isCharging = isCharging_.load()
#else
            .batteryLevel = 1.0f,
            .isCharging = false
#endif
        };
    }
    
    /**
     * @brief Reset performance counters
     */
    void resetPerformanceCounters() {
        averageCPULoad_.store(0.0);
        peakCPULoad_.store(0.0);
        denormalPreventionCount_.store(0);
    }
    
private:
    
    void initializeMemoryPools() {
        // Common buffer sizes for audio processing
        const std::vector<size_t> poolSizes = {
            64,    // Small buffers for parameters
            256,   // Medium buffers for processing
            1024,  // Large buffers for delay lines
            4096   // Very large buffers for impulse responses
        };
        
        const size_t alignment = 16; // NEON alignment
        const size_t buffersPerPool = 8;
        
        for (size_t size : poolSizes) {
            memoryPools_.emplace_back(
                std::make_unique<MemoryPool>(size, alignment, buffersPerPool)
            );
        }
    }
    
    float* allocateFromPool(size_t numElements, size_t alignment) {
        // Find appropriate pool
        for (auto& pool : memoryPools_) {
            if (pool->bufferSize >= numElements && 
                pool->alignment >= alignment) {
                
                // Find available buffer in pool
                for (size_t i = 0; i < pool->isUsed.size(); ++i) {
                    if (!pool->isUsed[i]) {
                        pool->isUsed[i] = true;
                        return pool->buffers[i].get();
                    }
                }
            }
        }
        
        return nullptr; // No available buffer in pools
    }
    
    bool returnToPool(float* buffer, size_t numElements) {
        for (auto& pool : memoryPools_) {
            if (pool->bufferSize >= numElements) {
                for (size_t i = 0; i < pool->buffers.size(); ++i) {
                    if (pool->buffers[i].get() == buffer) {
                        pool->isUsed[i] = false;
                        return true;
                    }
                }
            }
        }
        
        return false; // Buffer not found in pools
    }
    
    bool reclaimPoolMemory(size_t neededBytes) {
        // Implementation to free unused buffers from pools
        // For now, just return false to use direct allocation
        return false;
    }
    
    void updatePowerMode() {
        PowerMode newMode = PowerMode::Balanced;
        
        if (isBackgroundMode_.load()) {
            newMode = PowerMode::Background;
        } else if (isLowBattery_.load() || isThermalThrottling_.load()) {
            newMode = PowerMode::PowerSaver;
#ifdef __APPLE__
        } else if (isCharging_.load() && batteryLevel_.load() > 0.8f) {
            newMode = PowerMode::HighPerformance;
#endif
        }
        
        currentPowerMode_.store(newMode);
        adaptProcessingQuality();
    }
    
    void adaptProcessingQuality() {
        ProcessingQuality newQuality = ProcessingQuality::Standard;
        
        switch (currentPowerMode_.load()) {
            case PowerMode::HighPerformance:
                newQuality = ProcessingQuality::Maximum;
                break;
            case PowerMode::Balanced:
                newQuality = ProcessingQuality::High;
                break;
            case PowerMode::PowerSaver:
                newQuality = ProcessingQuality::Standard;
                break;
            case PowerMode::Background:
                newQuality = ProcessingQuality::Minimal;
                break;
        }
        
        currentQuality_.store(newQuality);
    }
    
#ifdef __APPLE__
    void startBatteryMonitoring() {
        shouldMonitorBattery_.store(true);
        batteryMonitorThread_ = std::thread([this]() {
            while (shouldMonitorBattery_.load()) {
                updateBatteryStatus();
                std::this_thread::sleep_for(std::chrono::seconds(10));
            }
        });
    }
    
    void stopBatteryMonitoring() {
        shouldMonitorBattery_.store(false);
        if (batteryMonitorThread_.joinable()) {
            batteryMonitorThread_.join();
        }
    }
    
    void updateBatteryStatus() {
        // Get battery information using IOKit
        CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
        if (!powerInfo) return;
        
        CFArrayRef powerSources = IOPSCopyPowerSourcesList(powerInfo);
        if (!powerSources) {
            CFRelease(powerInfo);
            return;
        }
        
        for (CFIndex i = 0; i < CFArrayGetCount(powerSources); ++i) {
            CFTypeRef powerSource = CFArrayGetValueAtIndex(powerSources, i);
            CFDictionaryRef description = IOPSGetPowerSourceDescription(powerInfo, powerSource);
            
            if (description) {
                // Get battery level
                CFNumberRef capacity = static_cast<CFNumberRef>(
                    CFDictionaryGetValue(description, CFSTR(kIOPSCurrentCapacityKey))
                );
                if (capacity) {
                    int level;
                    CFNumberGetValue(capacity, kCFNumberIntType, &level);
                    batteryLevel_.store(level / 100.0f);
                    
                    // Check low battery threshold
                    isLowBattery_.store(level < 20);
                }
                
                // Get charging status
                CFStringRef powerState = static_cast<CFStringRef>(
                    CFDictionaryGetValue(description, CFSTR(kIOPSPowerSourceStateKey))
                );
                if (powerState) {
                    isCharging_.store(CFStringCompare(powerState, 
                                                    CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo);
                }
            }
        }
        
        CFRelease(powerSources);
        CFRelease(powerInfo);
        
        // Update power mode based on new battery status
        updatePowerMode();
    }
#endif
};

} // namespace Optimization
} // namespace Reverb