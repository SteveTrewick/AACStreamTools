import Foundation
import AVFoundation


/*
  so, you have some audio, probably in PCM format and you want to compress it to AAC,
  maybe so you can send it over a network in handy packets, I gotchu fam.
  
  first we will comrpess it using the below, then we need to use the packetizer to split them up
  and add those fun fun ADST headers on them.
*/

public class AACCompressor {
  
  
  public enum Error : Swift.Error {
    case compressorFail( status: AVAudioConverterOutputStatus, error: NSError? )
    case createFail
  }
  
  
  let converter : AVAudioConverter
  let aacfmt    : AACFormat
  
  
  public init ( from: AVAudioFormat, to aac: AACFormat ) throws {
    
    guard
      let converter = AVAudioConverter(from: from, to: aac.avformat)
    else {
      print("can't create conveter for formats")
      throw Error.createFail
    }
    self.aacfmt    = aac
    self.converter = converter
  }
  
  
  
  public func compress ( pcmbuffer: AVAudioPCMBuffer ) -> Result<AVAudioCompressedBuffer, Error> {
    
    // set up a buffer, we get 1024 frames of PCM per packet, so, ....
    let compressed = AVAudioCompressedBuffer (
      format           : aacfmt.avformat,
      packetCapacity   : (pcmbuffer.frameLength / 1024) + 1,
      maximumPacketSize: converter.maximumOutputPacketSize
    )
    
    // now we need a block to provide the input, which is our input buffer, so ...
    let block: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return pcmbuffer
    }
    
    var error : NSError? = nil
    let status = converter.convert(to: compressed, error: &error, withInputFrom: block)
    if case .haveData = status {
        return .success( compressed )
    }
    else {
      return .failure( .compressorFail(status: status, error: error) )
    }

    
    
    
  }
  
}
