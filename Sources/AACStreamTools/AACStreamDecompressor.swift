

import Foundation
import AVFoundation
import AudioToolbox


/*
  Decompress AAC packets with ADTS headers on them
 
  To achieve this we will use the Audio File Stream API because it will
  parse the ADTS headers for us and retrieve the ASBD that we need to decode
  them. It will also generate descriptions for the packets with the correct
  header offsets and lengths.
 
  Again, you /could/ do this by hand, but the API is right there.
 
  So, we set up an AFS and then call AudioFileStreamParseBytes(..) with our data,
  we then get callbacks to two functions, one which fires a bunch of times for the
  various stream properties and one for the actual packets
 

*/



public class AACStreamDecompressor {
  
  
  public enum Error : Swift.Error {
    
    case afsOpenFail    (OSStatus)
    case decompressFail ( status: AVAudioConverterOutputStatus, error: NSError? )
    case parseFail      (OSStatus)
    case converterFail
  }
  
  
  var id        : AudioFileStreamID!
  let pcmFmt    : AVAudioFormat
  var aacFmt    : AVAudioFormat!
  var converter : AVAudioConverter?
  
  var asbd      = AudioStreamBasicDescription()
  var asbdSize  = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
  
  
  public var packetHandler : ((Result<AVAudioPCMBuffer,Error>) -> Void)? = nil
  
  public private(set) var error : Error? = nil
  
  public init? ( to pcmFmt: AVAudioFormat ) {

    self.pcmFmt = pcmFmt
    
    // set up the two call backs
    // in the properties call back we wait until we are ready to produce packets and
    // grab the format, then we create the actual converter based on that, neat huh?
    
    let properties : AudioFileStream_PropertyListenerProc = { ctxt, sid, pid, flags in
      let ctxt = Unmanaged<AACStreamDecompressor>.fromOpaque(ctxt).takeUnretainedValue()
      if pid == kAudioFileStreamProperty_ReadyToProducePackets {
        AudioFileStreamGetProperty ( ctxt.id, kAudioFileStreamProperty_DataFormat, &ctxt.asbdSize, &ctxt.asbd )
        ctxt.createCoverter()
      }
    }
    
    
    // packet callback, just pass the packet gubbins along to the decompression routine
    
    let packets : AudioFileStream_PacketsProc = { ctxt, lenBytes, lenPackets, buffer, descriptions in
      let ctxt = Unmanaged<AACStreamDecompressor>.fromOpaque(ctxt).takeUnretainedValue()
      ctxt.decompress ( lenBytes: lenBytes, lenPackets: lenPackets, buffer: buffer, descs: descriptions )
    }
    
    
    // set up our context pointer for the C callbacks
    let ctxt = UnsafeMutableRawPointer ( Unmanaged.passUnretained(self).toOpaque() )
    
    // attempt to open an audio file stream, there's really no good reason this /should/ fail
    // but it can, so ...
    let status = AudioFileStreamOpen ( ctxt, properties, packets, kAudioFileAAC_ADTSType, &id )
    if status != noErr {
      print("AFS open fail : \(status)")
      self.error = .afsOpenFail(status)
      return nil
    }
    
  }
  
  
  deinit {
    AudioFileStreamClose(id)
  }
  
  
  
  func createCoverter() {
   
    // set up the conveter using the format we want and the format we got from the
    // data stream, if we can't, well, nothing else is going to work
    // we also stash the AVAudioFormat from the aac ABSD because we need it for the
    // conveter buffers
    
    guard
      let infmt = AVAudioFormat    ( streamDescription: &asbd),
      let conv  = AVAudioConverter ( from: infmt, to: pcmFmt )
    else {
      print("Converter could not be init'd, your formats are probably wonky")
      packetHandler? ( .failure ( .converterFail ) )
      return
    }
    aacFmt    = infmt
    converter = conv
  }
  
  
  
  
  func decompress ( lenBytes: UInt32, lenPackets: UInt32, buffer: UnsafeRawPointer, descs: UnsafeMutablePointer<AudioStreamPacketDescription>? ) {
    /*
      so mostly we just get the one packet from the file stream, but it caches the first two while
      it reads the properties (no I don't know why either) so we need a loop.
     
      note that we get passed some AudioStreamPacketDescription, which is handy, because the afs parser
      leaves the headers on mStartOffset tells us where the actual data starts and mDataByteSize how
      long it is so that we can copy it
    */
    for packet in 0..<(Int(lenPackets)) {
      
      if let desc = descs?[packet] {
        
        // buffers in and out
        let outbuff = AVAudioPCMBuffer ( pcmFormat: pcmFmt, frameCapacity: 1024 )!
        
        let inbuff  = AVAudioCompressedBuffer (
          format           : aacFmt,
          packetCapacity   : 1,
          maximumPacketSize: Int(desc.mDataByteSize)
        )
        
        // again things that we have to set, if we don't these will both be 0
        // and nothing will work
        inbuff.byteLength  = desc.mDataByteSize
        inbuff.packetCount = 1
        
        // copy from the input buffer
        inbuff.data.copyMemory ( from: buffer.advanced(by: Int(desc.mStartOffset)), byteCount: Int(desc.mDataByteSize) )
        
        // we also need to provide a packet description, which since we have lopped the headers off
        // is just 0s, I suspect we could just bulk it over but I haven't yet figured out
        // how to copy the packet descs, will check that later
        
        inbuff.packetDescriptions?.pointee = AudioStreamPacketDescription (
          mStartOffset           : 0,
          mVariableFramesInPacket: 0,
          mDataByteSize          : desc.mDataByteSize
        )
        
        // we provide a callback to supply data to the converter, because reasons
        // no, me neither
        let block : AVAudioConverterInputBlock = { _, status in
          status.pointee = .haveData
          return inbuff
        }
        
        
        // if conveter is nil we failed earlier and will have sent a fail message down to our handler
        // so we just skip it, no point spamming thousands of error messages.
        // if there's any other kind of error we just shove it down the pipe indiscriminately though
        var error : NSError? = nil
        
        if let status = converter?.convert(to: outbuff, error: &error, withInputFrom: block) {
          if case .haveData = status {
            packetHandler?( .success(outbuff) )
          }
          else {
            packetHandler?( .failure(.decompressFail(status: status, error: error)) )
          }
        }
        
        
      } // if
    } // for
    
  }
  
  /*
    the only other bit of public API, fling data, get back back PCM buffers in the handler
  */
  
  public func decompress ( data: Data ) {
    
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      guard let baseAddress = buffer.baseAddress else { return }

      let status = AudioFileStreamParseBytes (
          id,
          UInt32(data.count),
          baseAddress,
          []
      )

      if status != noErr {
          print("Failed to parse bytes: \(status)")
          packetHandler?( .failure(.parseFail(status)) )
      }
    }
 
  }
 
}

