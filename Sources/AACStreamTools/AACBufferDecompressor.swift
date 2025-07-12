
import Foundation
import AVFoundation

/*
  ok, lastly, if you just have a big ol AVAudioCompressedBuffer that someone handed you,
  no questions asked, or you just want to do a round trip on your compression and see
  what it looks like, here is a class to just do a straight decompress of the buffer
  it's actually pretty straightforward
*/

public class AACBufferDecompressor {
  
  
  public enum Error : Swift.Error {
    case decompressFail ( status: AVAudioConverterOutputStatus, error: NSError? )
    case createFail
  }
  
  let pcmFmt : AVAudioFormat
  
  public init ( pcmFmt: AVAudioFormat ) {
    self.pcmFmt = pcmFmt
  }
  
  public func decompress ( aac: AVAudioCompressedBuffer ) -> Result<AVAudioPCMBuffer, Error> {
    
    guard
      let converter = AVAudioConverter ( from: aac.format, to: pcmFmt ),
      let outbuff   = AVAudioPCMBuffer ( pcmFormat: pcmFmt, frameCapacity: 1024 * aac.packetCount )
    else
    {
      return .failure (.createFail )
    }
  
    
    outbuff.frameLength = 1024 * aac.packetCount
    
    let inblock : AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return aac
    }
    
    var error : NSError? = nil
    let status = converter.convert(to: outbuff, error: &error, withInputFrom: inblock)
    if case .haveData = status {
      return .success ( outbuff )
    }
    else {
      return .failure ( .decompressFail(status: status, error: error) )
    }
  }
  
}
