#include "Parameters.hpp"

namespace VoiceMonitor {

// Template instantiations for common types
template class SmoothParameter<float>;
template class SmoothParameter<double>;
template class RangedParameter<float>;
template class RangedParameter<double>;
template class ExponentialParameter<float>;
template class ExponentialParameter<double>;

} // namespace VoiceMonitor