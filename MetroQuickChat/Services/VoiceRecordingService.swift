import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceRecordingService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private let maxDuration: TimeInterval = 60.0 // 60 seconds max
    private var recordingStartTime: Date?
    
    var onRecordingComplete: ((Data, Int) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.recordingDuration = Date().timeIntervalSince(self.recordingStartTime ?? Date())
                if self.recordingDuration >= self.maxDuration {
                    self.stopRecording()
                }
            }
        } catch {
            print("Failed to start recording: \(error)")
            isRecording = false
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        isRecording = false
        
        guard let recorder = audioRecorder else {
            onRecordingCancelled?()
            return
        }
        
        let duration = Int(recordingDuration)
        let url = recorder.url
        
        // Read the recorded file
        do {
            let data = try Data(contentsOf: url)
            // Clean up file
            try? FileManager.default.removeItem(at: url)
            onRecordingComplete?(data, duration)
        } catch {
            print("Failed to read recording: \(error)")
            onRecordingCancelled?()
        }
        
        audioRecorder = nil
        recordingStartTime = nil
        recordingDuration = 0
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        if let url = audioRecorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        onRecordingCancelled?()
    }
    
    func playVoice(data: Data) {
        stopPlayback()
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            playbackProgress = 0.0
            
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / player.duration
                if self.playbackProgress >= 1.0 {
                    self.stopPlayback()
                }
            }
        } catch {
            print("Failed to play voice: \(error)")
            isPlaying = false
        }
    }
    
    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0.0
    }
    
    deinit {
        // deinit is not on MainActor, so we directly cleanup resources
        recordingTimer?.invalidate()
        playbackTimer?.invalidate()
        
        // Stop audio operations directly without MainActor isolation
        audioRecorder?.stop()
        audioPlayer?.stop()
        
        // Clean up file if recording was in progress
        if let url = audioRecorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        
        audioRecorder = nil
        audioPlayer = nil
    }
}

extension VoiceRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            cancelRecording()
        }
    }
}

extension VoiceRecordingService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}

