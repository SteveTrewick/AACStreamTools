
import Foundation
import AVFoundation

// courtesy include for testing. look for the full package which (one day) be on github.

public class PCMToneGen {
  
  /*
    bits and bobs of tone gen for bonking up some PCM noise
    (will go here, for now we just have the sine wave)
  */
  
  public init() {}
  
  public func sine (freqHz: Float = 400, durationSec: Float = 5, sampleRate: Float = 44100, amplitude: Float = 1) -> AVAudioPCMBuffer? {
    
    /*
      y(t) = A * sin ( 2πft + ø ), mkay
      here we increment the phase from 0 to 2πf (one full sine cycle)
      so ∆phase is 2πf divided into the sample rate
      we will also use tau as 2π to avoid repeated multiplications
      embrace tau https://www.tauday.com
    */
    let tau   = 2 * Float.pi
    var phase : Float = 0
    let dPhase: Float = (tau * freqHz) / sampleRate
    
    /*
      In PCM (and some others) one *frame* is one sample so we just drop
      any decimal portion of this, we canoy have 0.1 of a sample.
      This evidently means that some precise time periods cannot be represented
    */
    let frames = Int( sampleRate * durationSec )
    
    
    // now we need a format and some buffers
    guard
      let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else {
      print("Failed to create buffer")
      return nil
    }
    
    
    // we MUST ALWAYS set this, IDK why, but if we don't, sadness.
    buffer.frameLength = AVAudioFrameCount(frames)
    
    
    // we need a ref to the sample buffer
    guard let samples = buffer.floatChannelData?[0]
    else {
      print("Buffer is wonky, no sample data")
      return nil
    }
  
    
    // ok, lets do the thang
    
    for i in 0..<frames {
      samples[i] = amplitude * sin(phase)
      phase += dPhase
      if phase > tau { phase -= tau }  // fmod is allegedly slower than this, FYI, FML, etc
    }                                  // NB that we DO NOT reset it to 0, tsk.
    
    // that's it, that all she (or I, in this case, wrote)
    
    return buffer
  }

}
