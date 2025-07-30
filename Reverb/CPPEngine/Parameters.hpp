#pragma once

#include <atomic>
#include <cmath>
#include <algorithm>
#include <map>
#include <string>

namespace VoiceMonitor {

/// Smooth parameter interpolation to avoid audio clicks and pops
/// Thread-safe parameter management for real-time audio processing
template<typename T = float>
class SmoothParameter {
public:
    explicit SmoothParameter(T initialValue = T(0), T smoothingTime = T(0.05))
        : targetValue_(initialValue)
        , currentValue_(initialValue)
        , smoothingTime_(smoothingTime)
        , sampleRate_(44100.0)
        , smoothingCoeff_(0.0) {
        updateSmoothingCoeff();
    }
    
    /// Set target value (thread-safe)
    void setValue(T newValue) {
        targetValue_.store(newValue);
    }
    
    /// Get current smoothed value (call from audio thread)
    T getNextValue() {
        T target = targetValue_.load();
        currentValue_ += smoothingCoeff_ * (target - currentValue_);
        return currentValue_;
    }
    
    /// Get current value without updating
    T getCurrentValue() const {
        return currentValue_;
    }
    
    /// Get target value
    T getTargetValue() const {
        return targetValue_.load();
    }
    
    /// Set smoothing time in seconds
    void setSmoothingTime(T timeInSeconds) {
        smoothingTime_ = timeInSeconds;
        updateSmoothingCoeff();
    }
    
    /// Update sample rate (affects smoothing calculation)
    void setSampleRate(double sampleRate) {
        sampleRate_ = sampleRate;
        updateSmoothingCoeff();
    }
    
    /// Reset to immediate value (no smoothing)
    void resetToValue(T value) {
        targetValue_.store(value);
        currentValue_ = value;
    }
    
    /// Check if parameter is still changing
    bool isSmoothing() const {
        return std::abs(currentValue_ - targetValue_.load()) > T(1e-6);
    }

private:
    void updateSmoothingCoeff() {
        if (smoothingTime_ > T(0) && sampleRate_ > 0) {
            smoothingCoeff_ = T(1.0 - std::exp(-1.0 / (smoothingTime_ * sampleRate_)));
        } else {
            smoothingCoeff_ = T(1.0); // Immediate change
        }
    }
    
    std::atomic<T> targetValue_;
    T currentValue_;
    T smoothingTime_;
    double sampleRate_;
    T smoothingCoeff_;
};

/// Parameter with range constraints and scaling
template<typename T = float>
class RangedParameter : public SmoothParameter<T> {
public:
    RangedParameter(T minValue, T maxValue, T initialValue, T smoothingTime = T(0.05))
        : SmoothParameter<T>(clamp(initialValue, minValue, maxValue), smoothingTime)
        , minValue_(minValue)
        , maxValue_(maxValue) {
    }
    
    /// Set value with automatic clamping
    void setValue(T newValue) {
        SmoothParameter<T>::setValue(clamp(newValue, minValue_, maxValue_));
    }
    
    /// Set value from normalized 0-1 range
    void setNormalizedValue(T normalizedValue) {
        T clampedNorm = clamp(normalizedValue, T(0), T(1));
        T scaledValue = minValue_ + clampedNorm * (maxValue_ - minValue_);
        setValue(scaledValue);
    }
    
    /// Get normalized value (0-1)
    T getNormalizedValue() const {
        T current = this->getCurrentValue();
        if (maxValue_ == minValue_) return T(0);
        return (current - minValue_) / (maxValue_ - minValue_);
    }
    
    /// Get range information
    T getMinValue() const { return minValue_; }
    T getMaxValue() const { return maxValue_; }
    T getRange() const { return maxValue_ - minValue_; }

private:
    T clamp(T value, T min, T max) const {
        return std::max(min, std::min(max, value));
    }
    
    T minValue_;
    T maxValue_;
};

/// Exponential parameter for frequencies, times, etc.
template<typename T = float>
class ExponentialParameter : public RangedParameter<T> {
public:
    ExponentialParameter(T minValue, T maxValue, T initialValue, T smoothingTime = T(0.05))
        : RangedParameter<T>(minValue, maxValue, initialValue, smoothingTime)
        , logMinValue_(std::log(minValue))
        , logMaxValue_(std::log(maxValue)) {
    }
    
    /// Set value from normalized 0-1 range with exponential scaling
    void setNormalizedValue(T normalizedValue) {
        T clampedNorm = std::max(T(0), std::min(T(1), normalizedValue));
        T logValue = logMinValue_ + clampedNorm * (logMaxValue_ - logMinValue_);
        T expValue = std::exp(logValue);
        this->setValue(expValue);
    }
    
    /// Get normalized value with exponential scaling
    T getNormalizedValue() const {
        T current = this->getCurrentValue();
        T logCurrent = std::log(std::max(current, this->getMinValue()));
        return (logCurrent - logMinValue_) / (logMaxValue_ - logMinValue_);
    }

private:
    T logMinValue_;
    T logMaxValue_;
};

/// Parameter group for managing multiple related parameters
class ParameterGroup {
public:
    ParameterGroup() = default;
    
    /// Add a parameter to the group
    template<typename T>
    void addParameter(const std::string& name, SmoothParameter<T>* parameter) {
        parameters_[name] = parameter;
    }
    
    /// Update sample rate for all parameters
    void setSampleRate(double sampleRate) {
        for (auto& pair : parameters_) {
            if (auto* smoothParam = static_cast<SmoothParameter<float>*>(pair.second)) {
                smoothParam->setSampleRate(sampleRate);
            }
        }
    }
    
    /// Set smoothing time for all parameters
    void setSmoothingTime(float smoothingTime) {
        for (auto& pair : parameters_) {
            if (auto* smoothParam = static_cast<SmoothParameter<float>*>(pair.second)) {
                smoothParam->setSmoothingTime(smoothingTime);
            }
        }
    }
    
    /// Check if any parameter is still smoothing
    bool isAnySmoothing() const {
        for (const auto& pair : parameters_) {
            if (auto* smoothParam = static_cast<SmoothParameter<float>*>(pair.second)) {
                if (smoothParam->isSmoothing()) {
                    return true;
                }
            }
        }
        return false;
    }

private:
    std::map<std::string, void*> parameters_;
};

/// Specialized parameters for audio applications

/// Decibel parameter with linear-to-dB conversion
class DecibelParameter : public RangedParameter<float> {
public:
    DecibelParameter(float minDB, float maxDB, float initialDB, float smoothingTime = 0.05f)
        : RangedParameter<float>(minDB, maxDB, initialDB, smoothingTime) {
    }
    
    /// Get linear gain value
    float getLinearGain() const {
        return dbToLinear(getCurrentValue());
    }
    
    /// Set from linear gain
    void setLinearGain(float linearGain) {
        setValue(linearToDb(linearGain));
    }

private:
    float dbToLinear(float db) const {
        return std::pow(10.0f, db * 0.05f);
    }
    
    float linearToDb(float linear) const {
        return 20.0f * std::log10(std::max(1e-6f, linear));
    }
};

/// Frequency parameter with musical scaling
class FrequencyParameter : public ExponentialParameter<float> {
public:
    FrequencyParameter(float minHz, float maxHz, float initialHz, float smoothingTime = 0.05f)
        : ExponentialParameter<float>(minHz, maxHz, initialHz, smoothingTime) {
    }
    
    /// Set from MIDI note number
    void setFromMidiNote(float midiNote) {
        float frequency = 440.0f * std::pow(2.0f, (midiNote - 69.0f) / 12.0f);
        setValue(frequency);
    }
    
    /// Get as MIDI note number
    float getMidiNote() const {
        float freq = getCurrentValue();
        return 69.0f + 12.0f * std::log2(freq / 440.0f);
    }
};

/// Time parameter with musical timing options
class TimeParameter : public ExponentialParameter<float> {
public:
    TimeParameter(float minSeconds, float maxSeconds, float initialSeconds, float smoothingTime = 0.05f)
        : ExponentialParameter<float>(minSeconds, maxSeconds, initialSeconds, smoothingTime)
        , bpm_(120.0f) {
    }
    
    /// Set BPM for musical timing calculations
    void setBPM(float bpm) {
        bpm_ = std::max(30.0f, std::min(300.0f, bpm));
    }
    
    /// Set from musical note value (1.0 = quarter note, 0.5 = eighth note, etc.)
    void setFromNoteValue(float noteValue) {
        float secondsPerBeat = 60.0f / bpm_;
        float timeInSeconds = noteValue * secondsPerBeat;
        setValue(timeInSeconds);
    }
    
    /// Get as note value relative to current BPM
    float getNoteValue() const {
        float secondsPerBeat = 60.0f / bpm_;
        return getCurrentValue() / secondsPerBeat;
    }
    
    /// Get in milliseconds
    float getMilliseconds() const {
        return getCurrentValue() * 1000.0f;
    }
    
    /// Set in milliseconds
    void setMilliseconds(float ms) {
        setValue(ms * 0.001f);
    }

private:
    float bpm_;
};

/// Percentage parameter (0-100%)
class PercentageParameter : public RangedParameter<float> {
public:
    PercentageParameter(float initialPercent = 50.0f, float smoothingTime = 0.05f)
        : RangedParameter<float>(0.0f, 100.0f, initialPercent, smoothingTime) {
    }
    
    /// Get as 0-1 ratio
    float getRatio() const {
        return getCurrentValue() * 0.01f;
    }
    
    /// Set from 0-1 ratio
    void setRatio(float ratio) {
        setValue(std::clamp(ratio, 0.0f, 1.0f) * 100.0f);
    }
};

} // namespace VoiceMonitor