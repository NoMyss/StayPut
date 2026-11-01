import AVFoundation
import CoreAudio
import AppKit

/// Plays a synthesized siren. Optionally unmutes the Mac and sets its output volume while playing.
final class AlarmPlayer {
    private let engine = AVAudioEngine()
    private let synth = SirenSynth()
    private var source: AVAudioSourceNode?
    private var savedVolume: Float32?
    private var savedMute: UInt32?
    private(set) var isPlaying = false

    init() {
        var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 48_000 }
        synth.sampleRate = sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let synth = self.synth
        let node = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let v = synth.next()
                for b in buffers { b.mData?.assumingMemoryBound(to: Float.self)[frame] = v }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// - Parameters:
    ///   - volume: 0…1
    ///   - overrideSystem: if true, unmute the Mac and set its output volume to `volume`.
    func play(volume: Double, overrideSystem: Bool) {
        guard !isPlaying else { return }
        if overrideSystem {
            savedVolume = SystemAudio.volume
            savedMute = SystemAudio.muted
            SystemAudio.muted = 0
            SystemAudio.volume = Float32(max(volume, 0.05))
            engine.mainMixerNode.outputVolume = 1
        } else {
            engine.mainMixerNode.outputVolume = Float(volume)
        }
        synth.reset()
        do {
            try engine.start()
            isPlaying = true
        } catch {
            NSSound.beep()
            restoreSystemAudio()
        }
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        isPlaying = false
        restoreSystemAudio()
    }

    private func restoreSystemAudio() {
        if let v = savedVolume { SystemAudio.volume = v }
        if let m = savedMute { SystemAudio.muted = m }
        savedVolume = nil
        savedMute = nil
    }
}

/// Generates a loud two-tone sweeping siren. Runs on the audio thread.
private final class SirenSynth {
    var sampleRate = 48_000.0
    private var phase = 0.0
    private var t = 0.0

    func reset() { phase = 0; t = 0 }

    func next() -> Float {
        // Frequency sweeps 650 → 1600 Hz and back, 2.5 times per second.
        let lfo = (t * 2.5).truncatingRemainder(dividingBy: 1)
        let tri = lfo < 0.5 ? lfo * 2 : 2 - lfo * 2
        let freq = 650 + 950 * tri
        phase += freq / sampleRate
        if phase >= 1 { phase -= 1 }
        t += 1 / sampleRate
        let s = sin(2 * .pi * phase)
        // Mix of sine and square: harsh and audible on small speakers.
        let v = 0.55 * s + 0.45 * (s >= 0 ? 1 : -1)
        // Short fade-in avoids a click.
        let fade = min(t / 0.03, 1)
        return Float(v * 0.85 * fade)
    }
}

/// Default output device volume and mute.
enum SystemAudio {
    private static var device: AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        guard let dev = device else { return nil }
        var addr = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func set<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: T) {
        guard let dev = device else { return }
        var addr = address(selector)
        var v = value
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    static var volume: Float32? {
        get { get(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)) }
        set { if let v = newValue { set(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, v) } }
    }

    static var muted: UInt32? {
        get { get(kAudioDevicePropertyMute, UInt32(0)) }
        set { if let v = newValue { set(kAudioDevicePropertyMute, v) } }
    }
}
