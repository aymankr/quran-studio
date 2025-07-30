#pragma once

#include <vector>
#include <atomic>
#include <algorithm>
#include <cstring>

namespace VoiceMonitor {

/// Thread-safe circular audio buffer for real-time processing
/// Supports lock-free reading/writing for audio threads
template<typename T = float>
class AudioBuffer {
public:
    explicit AudioBuffer(size_t capacity = 0) 
        : capacity_(0), writeIndex_(0), readIndex_(0) {
        if (capacity > 0) {
            resize(capacity);
        }
    }
    
    /// Resize buffer (not thread-safe, call before audio processing)
    void resize(size_t newCapacity) {
        if (newCapacity == capacity_) return;
        
        capacity_ = newCapacity;
        buffer_.resize(capacity_);
        clear();
    }
    
    /// Clear all data and reset pointers
    void clear() {
        std::fill(buffer_.begin(), buffer_.end(), T(0));
        writeIndex_.store(0);
        readIndex_.store(0);
    }
    
    /// Write a single sample (thread-safe)
    bool write(const T& sample) {
        size_t currentWrite = writeIndex_.load();
        size_t nextWrite = (currentWrite + 1) % capacity_;
        
        if (nextWrite == readIndex_.load()) {
            return false; // Buffer full
        }
        
        buffer_[currentWrite] = sample;
        writeIndex_.store(nextWrite);
        return true;
    }
    
    /// Write multiple samples (thread-safe)
    size_t write(const T* samples, size_t numSamples) {
        size_t written = 0;
        for (size_t i = 0; i < numSamples; ++i) {
            if (!write(samples[i])) {
                break;
            }
            ++written;
        }
        return written;
    }
    
    /// Read a single sample (thread-safe)
    bool read(T& sample) {
        size_t currentRead = readIndex_.load();
        
        if (currentRead == writeIndex_.load()) {
            return false; // Buffer empty
        }
        
        sample = buffer_[currentRead];
        readIndex_.store((currentRead + 1) % capacity_);
        return true;
    }
    
    /// Read multiple samples (thread-safe)
    size_t read(T* samples, size_t numSamples) {
        size_t read = 0;
        for (size_t i = 0; i < numSamples; ++i) {
            if (!this->read(samples[i])) {
                break;
            }
            ++read;
        }
        return read;
    }
    
    /// Peek at data without consuming it
    bool peek(T& sample, size_t offset = 0) const {
        size_t currentRead = readIndex_.load();
        size_t peekIndex = (currentRead + offset) % capacity_;
        
        if (peekIndex == writeIndex_.load()) {
            return false;
        }
        
        sample = buffer_[peekIndex];
        return true;
    }
    
    /// Get number of samples available for reading
    size_t available() const {
        size_t write = writeIndex_.load();
        size_t read = readIndex_.load();
        
        if (write >= read) {
            return write - read;
        } else {
            return capacity_ - read + write;
        }
    }
    
    /// Get free space available for writing
    size_t freeSpace() const {
        return capacity_ - available() - 1; // -1 to distinguish full from empty
    }
    
    /// Check if buffer is empty
    bool empty() const {
        return readIndex_.load() == writeIndex_.load();
    }
    
    /// Check if buffer is full
    bool full() const {
        return freeSpace() == 0;
    }
    
    /// Get buffer capacity
    size_t capacity() const {
        return capacity_;
    }

private:
    std::vector<T> buffer_;
    size_t capacity_;
    std::atomic<size_t> writeIndex_;
    std::atomic<size_t> readIndex_;
};

/// Multi-channel audio buffer for interleaved or planar processing
template<typename T = float>
class MultiChannelBuffer {
public:
    explicit MultiChannelBuffer(int numChannels = 2, size_t framesPerChannel = 0)
        : numChannels_(numChannels), framesPerChannel_(framesPerChannel) {
        if (framesPerChannel > 0) {
            resize(numChannels, framesPerChannel);
        }
    }
    
    /// Resize buffer for specific channel count and frame count
    void resize(int numChannels, size_t framesPerChannel) {
        numChannels_ = numChannels;
        framesPerChannel_ = framesPerChannel;
        
        // Planar storage (separate buffer per channel)
        channels_.resize(numChannels_);
        for (auto& channel : channels_) {
            channel.resize(framesPerChannel_);
        }
        
        // Interleaved storage
        interleavedBuffer_.resize(numChannels_ * framesPerChannel_);
    }
    
    /// Clear all channels
    void clear() {
        for (auto& channel : channels_) {
            std::fill(channel.begin(), channel.end(), T(0));
        }
        std::fill(interleavedBuffer_.begin(), interleavedBuffer_.end(), T(0));
    }
    
    /// Get pointer to channel data (planar)
    T* getChannelData(int channel) {
        if (channel >= 0 && channel < numChannels_) {
            return channels_[channel].data();
        }
        return nullptr;
    }
    
    /// Get const pointer to channel data
    const T* getChannelData(int channel) const {
        if (channel >= 0 && channel < numChannels_) {
            return channels_[channel].data();
        }
        return nullptr;
    }
    
    /// Get array of channel pointers (for AVAudioPCMBuffer compatibility)
    T** getChannelArrayData() {
        channelPointers_.resize(numChannels_);
        for (int i = 0; i < numChannels_; ++i) {
            channelPointers_[i] = channels_[i].data();
        }
        return channelPointers_.data();
    }
    
    /// Get interleaved data pointer
    T* getInterleavedData() {
        return interleavedBuffer_.data();
    }
    
    /// Convert from planar to interleaved
    void planarToInterleaved() {
        size_t index = 0;
        for (size_t frame = 0; frame < framesPerChannel_; ++frame) {
            for (int channel = 0; channel < numChannels_; ++channel) {
                interleavedBuffer_[index++] = channels_[channel][frame];
            }
        }
    }
    
    /// Convert from interleaved to planar
    void interleavedToPlanar() {
        size_t index = 0;
        for (size_t frame = 0; frame < framesPerChannel_; ++frame) {
            for (int channel = 0; channel < numChannels_; ++channel) {
                channels_[channel][frame] = interleavedBuffer_[index++];
            }
        }
    }
    
    /// Copy from another buffer
    void copyFrom(const MultiChannelBuffer& other) {
        int copyChannels = std::min(numChannels_, other.numChannels_);
        size_t copyFrames = std::min(framesPerChannel_, other.framesPerChannel_);
        
        for (int ch = 0; ch < copyChannels; ++ch) {
            std::copy(other.channels_[ch].begin(), 
                     other.channels_[ch].begin() + copyFrames,
                     channels_[ch].begin());
        }
    }
    
    /// Add (mix) from another buffer
    void addFrom(const MultiChannelBuffer& other, T gain = T(1)) {
        int copyChannels = std::min(numChannels_, other.numChannels_);
        size_t copyFrames = std::min(framesPerChannel_, other.framesPerChannel_);
        
        for (int ch = 0; ch < copyChannels; ++ch) {
            for (size_t frame = 0; frame < copyFrames; ++frame) {
                channels_[ch][frame] += other.channels_[ch][frame] * gain;
            }
        }
    }
    
    /// Apply gain to all channels
    void applyGain(T gain) {
        for (auto& channel : channels_) {
            for (auto& sample : channel) {
                sample *= gain;
            }
        }
    }
    
    /// Apply gain to specific channel
    void applyGain(int channel, T gain) {
        if (channel >= 0 && channel < numChannels_) {
            for (auto& sample : channels_[channel]) {
                sample *= gain;
            }
        }
    }
    
    /// Get RMS level for channel
    T getRMSLevel(int channel) const {
        if (channel < 0 || channel >= numChannels_ || framesPerChannel_ == 0) {
            return T(0);
        }
        
        T sum = T(0);
        for (const auto& sample : channels_[channel]) {
            sum += sample * sample;
        }
        
        return std::sqrt(sum / T(framesPerChannel_));
    }
    
    /// Get peak level for channel
    T getPeakLevel(int channel) const {
        if (channel < 0 || channel >= numChannels_) {
            return T(0);
        }
        
        T peak = T(0);
        for (const auto& sample : channels_[channel]) {
            peak = std::max(peak, std::abs(sample));
        }
        
        return peak;
    }
    
    /// Getters
    int getNumChannels() const { return numChannels_; }
    size_t getFramesPerChannel() const { return framesPerChannel_; }
    size_t getTotalSamples() const { return numChannels_ * framesPerChannel_; }

private:
    int numChannels_;
    size_t framesPerChannel_;
    std::vector<std::vector<T>> channels_;     // Planar storage
    std::vector<T> interleavedBuffer_;         // Interleaved storage
    std::vector<T*> channelPointers_;          // For getChannelArrayData()
};

/// Delay line with fractional delay support
template<typename T = float>
class DelayLine {
public:
    explicit DelayLine(size_t maxDelayInSamples = 0) {
        if (maxDelayInSamples > 0) {
            resize(maxDelayInSamples);
        }
    }
    
    void resize(size_t maxDelayInSamples) {
        buffer_.resize(maxDelayInSamples);
        maxDelay_ = maxDelayInSamples;
        clear();
    }
    
    void clear() {
        buffer_.clear();
        writeIndex_ = 0;
        delayInSamples_ = 0;
    }
    
    void setDelay(T delayInSamples) {
        delayInSamples_ = std::max(T(0), std::min(delayInSamples, T(maxDelay_ - 1)));
    }
    
    T process(T input) {
        // Write input
        buffer_[writeIndex_] = input;
        
        // Calculate read position with fractional delay
        T readPos = T(writeIndex_) - delayInSamples_;
        if (readPos < T(0)) {
            readPos += T(maxDelay_);
        }
        
        // Linear interpolation for fractional delay
        size_t readIndex1 = static_cast<size_t>(readPos) % maxDelay_;
        size_t readIndex2 = (readIndex1 + 1) % maxDelay_;
        T fraction = readPos - std::floor(readPos);
        
        T sample1 = buffer_[readIndex1];
        T sample2 = buffer_[readIndex2];
        T output = sample1 + fraction * (sample2 - sample1);
        
        // Advance write pointer
        writeIndex_ = (writeIndex_ + 1) % maxDelay_;
        
        return output;
    }
    
    T getMaxDelay() const { return T(maxDelay_); }
    T getCurrentDelay() const { return delayInSamples_; }

private:
    std::vector<T> buffer_;
    size_t maxDelay_;
    size_t writeIndex_;
    T delayInSamples_;
};

} // namespace VoiceMonitor