
import Foundation
import AudioToolbox
import AVFAudio


/*
 m'kay. in order to get the correct ADTS headers for streaming
 we need to do some messed up shit.
 we could, of course, write a routine to do this, hell, GPT will knock you
 one out in seconds (theres one in here if you're interested in doing the
 comparison)
 
 Or ... we could also just use Apple's maintained (lol) and battle tested code.
 I'm generally in favour of doing that when we can, but as is often the case,
 we will have to bend things a little.
 
 It will not have escaped the attention of the curious reader that we can just spam
 our audio buffers to a file, and the file writer will add headers for us (don't
 forget your magic cookie if you do this!)
 
 So can we just use the file writer but like, not write? YES!
 
 We will set up an Audio File pipeline that works with callbacks using the
 AudioFileInitializeWithCallbacks API and then we will spam packets at it
 with AudioFileWritePackets and it will do the business for us.
 
 sort of.
 
*/

public class ADTSPacketizer {
  
  
  public enum Error : Swift.Error {
    case packetDescsMissing
    case createFail          ( OSStatus )
    case writeFail           ( OSStatus )
  }
  
  public class Context {
    var id            : AudioFileID!
    var packet        = Data()
    var packetIdx     = 0
    var callCount     = 0
    var descs         : UnsafeMutablePointer<AudioStreamPacketDescription>?
    
    public var packetHandler : ((Result<Data, Error>) -> Void)? = nil
  }
  
  public let context = Context()
  
  public init? ( aacFmt: AACFormat ) {
    /*
      write callback for AudioFileWritePackets, we will stub the rest
      super fun fact time, this actually gets caled twice per packet,
      once for the ADTS header and then once for the data
    */
    let writeProc : AudioFile_WriteProc = { ctxt, inPos, reqCnt, buff, actCnt in
      let ctxt = Unmanaged<Context>.fromOpaque(ctxt).takeUnretainedValue()
      
      ctxt.callCount += 1
      
      if (ctxt.callCount % 2) != 0 {  // header
        // grab the packet desc
        guard let desc = ctxt.descs?[ ctxt.packetIdx ]
        else {
          print ( "no packet descs, bad!" )
          ctxt.packetHandler? ( .failure(.packetDescsMissing) )
          return kAudioFileUnspecifiedError
        }
        // usually the header is 7, it can be 9, IDK in what circs, so, careful does it
        ctxt.packet = Data ( capacity: Int ( reqCnt + desc.mDataByteSize ) )
        ctxt.packet.append ( contentsOf: UnsafeRawBufferPointer(start: buff, count: Int(reqCnt)) )
      }
      else {  // packet
        ctxt.packet.append ( contentsOf: UnsafeRawBufferPointer(start: buff, count: Int(reqCnt)) )
        ctxt.packetIdx += 1
        ctxt.packetHandler? ( .success(ctxt.packet) )
      }
      
      actCnt.pointee = reqCnt
      return 0
    }
    
    let ctxt = UnsafeMutableRawPointer ( Unmanaged.passUnretained(context).toOpaque())
    var asbd = aacFmt.description
    
    let status = AudioFileInitializeWithCallbacks (
      ctxt,
      { _,_,_,_,_ in 0 },
      writeProc,
      { _         in 0 },
      { _, _      in 0 },
      aacFmt.filetype,
      &asbd,
      [],
      &context.id
    )
    
    if status != noErr {
      print("creation fail \(status)")
      return nil
    }
  }
  
  
  
  public func packetize ( avacb: AVAudioCompressedBuffer ) {
    
    // we will need these
    context.descs = avacb.packetDescriptions
    
    var iopax  = avacb.packetCount
    let status = AudioFileWritePackets (
        context.id,
        false,
        avacb.byteLength,
        avacb.packetDescriptions,
        0,
        &iopax,
        avacb.data
    )
    print("write -> \(status): \(iopax) packets")
    context.packetHandler? ( .failure( .writeFail(status) ) )
  }
  
}
