#include "AudioBuffer.hpp"

namespace VoiceMonitor {

// Template instantiations for common types
template class AudioBuffer<float>;
template class AudioBuffer<double>;
template class MultiChannelBuffer<float>;
template class MultiChannelBuffer<double>;
template class DelayLine<float>;
template class DelayLine<double>;

} // namespace VoiceMonitor