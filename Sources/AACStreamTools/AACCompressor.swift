import Foundation
import AVFoundation




public class AACCompressor {
  
  let converter : AVAudioConverter
  let aacfmt    : AACFormat
  
  
  public init? ( from: AVAudioFormat, to aac: AACFormat ) {
    
    guard
      let converter = AVAudioConverter(from: from, to: aac.avformat)
    else {
      print("can't create conveter for formats")
      return nil
    }
    self.aacfmt    = aac
    self.converter = converter
  }
  
  
  
  public func compress ( pcmbuffer: AVAudioPCMBuffer ) -> AVAudioCompressedBuffer {
    
    // set up a buffer, we get 1024 frames of PCM per packet, so, ....
    let compressed = AVAudioCompressedBuffer (
      format           : aacfmt.avformat,
      packetCapacity   : (pcmbuffer.frameLength / 1024) + 1,
      maximumPacketSize: converter.maximumOutputPacketSize
    )

//    print(compressed.packetCapacity)
//    print(converter.maximumOutputPacketSize)
    
    // now we need a block to provide the input, which is our input buffer, so ...
    let block: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return pcmbuffer
    }
    
    var error : NSError? = nil
    let status = converter.convert(to: compressed, error: &error, withInputFrom: block)
    
    // how to handle erorr though?
    print(error)
    
    
    return compressed
  }
  
}
