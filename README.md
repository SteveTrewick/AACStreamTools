# AACStreamTools

AACStreamTools is a smol package of Swift classes for creating and decoding/decompressing 
AAC compressed data packets, specifically ADTS packets that you either got over a 
network or want to fling into one.

There is basically no custom code in here, it's just a cobbling together of all the bits of API
that you knew for a fact were already in the system so why can't we use them dammit!

There are also no queues or anything internally becuase I don't know what you kids are using for
that these days, so you'll have to BYO async paradigm.

FRankly it feels like there is probably an easier way to acheive all this, but this is where I landed. Do, 
in fact, @me if you feel the urge to demostrate the super simple way I could have done it.

Demo code of a round trip from PCM to compressed packets and back again is below.

## AACFormat
AACFormat encapuslates an `AudioSreamBasicDescription`, an `AVAudioFormat` and the `kAudioFileAAC_ADTSType` 
constant purely for convenience and so I didn't have to keep typing them.

## AACCompressor

AACCompressor takes PCM Buffers and compresses them to an AAC encoded `AVAudioCompressedBuffer`,
or it doesn't and gives you an error.

`public func compress ( pcmbuffer: AVAudioPCMBuffer ) -> Result<AVAudioCompressedBuffer, Error> `


## ADTSPacketizer

ADTSPacketizer takes the compressed buffer and spits out AAC packets with ADTS headers on them
via a callback that you assign. Or it doesn't and gives you an error which may or may not be
particularly heplful depending on how you feel about OSStatus.

```swift
  // ...
  
  packetizer.packetize(avacb: compressed)

  // ...

  packetizer.context.packetHandler = { result in
    switch result {
      case .success(let data) : // fling at a network, or whatever, I'm not your mum.
      case .failure(let error): print(error)
    }
  }
```

## AACStreamDecompressor

This one is the approximate inverse of the above process. It takes in AAC packets with ADTS headers
and gives you back `AVAudioPCMBuffer`s, or, it doesn't and ... you get the gist.

```swift
 
  // ... you obtain some data from somewhere, it is a mystery, no one can kno it
 
  decompressor.decompress(data: data)
 
  // .. some time later 
 
  decompressor.packetHandler = { result in

    switch result {
      case .success(let buff) : // do things with PCM buffers
      case .failure(let error): print(error)
    }

  }
 
```

## AACBufferDecompressor

On the off chance you just have a compressed buffer and you want PCM back out of it, 
you can use `AACBufferDecompressor`

`decompress ( aac: AVAudioCompressedBuffer ) -> Result<AVAudioPCMBuffer, Error>`


## Example - PCM Round Trip

And that's it, there's not really that much to it TBH. Here is a sample so you can see all that working.

```swift

import Foundation
import AVFoundation
import AACStreamTools


/*
  OK, first thing we'll do is set up an AVAudioEngine instance so that
  we can hear stuff is working, this is important, it turns out
*/

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!

engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
do { try engine.start() } catch { print("Engine failed to start: \(error)") }
player.play()

/*
  We need to set up some formats, I happen to be working with 48KHz sampling, so we'll use that
  but like, whatever is good for you on youir platform (IIRC 48K for iOS and 44.1 for macOS as
  standards, because resons? who knows)
 */

guard let pcmfmt  = AVAudioFormat (
  commonFormat: .pcmFormatFloat32,
  sampleRate  : 48000,
  channels    : 1,
  interleaved : false
)
else { fatalError("avaudioformat create failes") }

guard let aacfmt  = AACFormat ( sampleRate: 48000, channels: 1 ) else { fatalError("aacformat create failes") }


/*
  Now we set up the compressor, the packetizer and the decompressor, all of these have
  failible inits because they all touch failible things when setting up, sigh.
*/

guard let compressor   = AACCompressor         ( from: pcmfmt, to: aacfmt ) else { fatalError( "compressor create failed"  ) }
guard let packetizer   = ADTSPacketizer        ( aacFmt: aacfmt )           else { fatalError( "packetizer create failed"  ) }
guard let decompressor = AACStreamDecompressor ( to: pcmfmt )               else { fatalError( "decompressor create failed") }



/*
  Now let's do a round trip, we will generate 5 seconds of mono sine waves at 48KHz in PCM format,
  compress them and then packetize them.
 
  To prove things are happening, we will then decompress them and play them.
*/


// make some sines
if let sines = PCMToneGen().sine(freqHz: 400, durationSec: 5, sampleRate: 48000, amplitude: 1) {

 
  // handler for the packets from the packetizer, when we get
  // our packets, chuck them straight at the decompressor
  packetizer.context.packetHandler = { result in
    switch result {
      case .success(let data) : decompressor.decompress(data: data)
      case .failure(let error): print(error)
    }
    
  }
  
  // when they have been decompressed, fling them at the player
  // so we can hear them
  decompressor.packetHandler = { result in
    
    switch result {
      case .success(let buff) : player.scheduleBuffer(buff, completionHandler: nil)
      case .failure(let error): print(error)
    }
    
  }
  
  // compress the sines and then hand them off to the packetizer
  switch compressor.compress ( pcmbuffer: sines ) {
    
    case .success(let compressed) : packetizer.packetize(avacb: compressed)
    case .failure(let error)      : print(error)
  }
  
}

RunLoop.current.run()

```
