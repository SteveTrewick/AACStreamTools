
import Foundation
import AVFoundation


public class AACFormat {
  
  public let description : AudioStreamBasicDescription
  public let avformat    : AVAudioFormat
  public let filetype    = kAudioFileAAC_ADTSType
  
  public init? ( sampleRate: Float64, channels: UInt32 ) {
  
    var absd = AudioStreamBasicDescription (
      mSampleRate      : sampleRate,
      mFormatID        : kAudioFormatMPEG4AAC,
      mFormatFlags     : 0,
      mBytesPerPacket  : 0,
      mFramesPerPacket : 1024,
      mBytesPerFrame   : 0,
      mChannelsPerFrame: channels,
      mBitsPerChannel  : 0,
      mReserved        : 0
    )
    
    guard let format = AVAudioFormat(streamDescription: &absd) else { return nil}
    
    self.description = absd
    self.avformat    = format
    
  }
}
