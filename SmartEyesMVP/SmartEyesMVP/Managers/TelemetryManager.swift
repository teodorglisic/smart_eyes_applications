import Foundation
import UIKit
import Combine

public struct TrialRecord: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let phase: String
    public let source: String
    public let captureMode: String
    public let imageWidth: Double
    public let imageHeight: Double
    public let latencySeconds: Double
    public let customPrompt: String
    public let rawResponseText: String
    public let parsedSeverity: String
    public let aiModel: String?
    
    // User feedback parameters
    public var isCorrect: Bool?
    public var rating1To5: Int?
    public var notes: String?
    
    // Token usage parameters — all values sourced directly from Firebase AI SDK
    public var inputTokens: Int?        // promptTokenCount (text + image combined)
    public var textInputTokens: Int?    // TEXT modality from promptTokensDetails
    public var imageInputTokens: Int?   // IMAGE modality from promptTokensDetails
    public var outputTokens: Int?       // candidatesTokenCount (text out)
    public var totalTokens: Int?        // totalTokenCount
    public var thinkingTokens: Int?     // thoughtsTokenCount
}

public extension TrialRecord {
    var formattedModelName: String {
        guard let model = aiModel else { return "Gemini Flash" }
        switch model {
        case "gemini-3.5-flash": return "Gemini 3.5 Flash"
        case "gemini-2.5-flash": return "Gemini 2.5 Flash"
        case "gemini-2.5-flash-lite": return "Gemini 2.5 Flash Lite"
        case "gemma-4-26b-a4b-it": return "Gemma 4 26B (MoE)"
        case "gemma-4-31b-it": return "Gemma 4 31B (Dense)"
        default: return model.replacingOccurrences(of: "gemini-", with: "").capitalized
        }
    }
}


@MainActor
public class TelemetryManager: ObservableObject {
    public static let shared = TelemetryManager()
    
    @Published public var records: [TrialRecord] = []
    
    private init() {
        loadRecords()
    }
    
    private var saveURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("telemetry_records.json")
    }
    
    /// Loads saved logs from local App storage
    public func loadRecords() {
        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            self.records = try decoder.decode([TrialRecord].self, from: data)
            print("Successfully loaded \(self.records.count) telemetry records.")
        } catch {
            print("No existing telemetry database found; starting clean session. Details: \(error)")
            self.records = []
        }
    }
    
    /// Purges all telemetry records from memory and disk
    public func purgeRecords() {
        self.records = []
        do {
            if FileManager.default.fileExists(atPath: saveURL.path) {
                try FileManager.default.removeItem(at: saveURL)
                print("Telemetry database successfully purged from disk.")
            }
        } catch {
            print("Failed to remove telemetry database file: \(error)")
        }
    }
    
    /// Persists logs back to device storage
    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: saveURL, options: [.atomicWrite])
        } catch {
            print("Error persisting telemetry logs: \(error)")
        }
    }
    
    /// Logs a new trial run
    public func logTrial(
        id: UUID = UUID(),
        phase: String,
        source: String,
        captureMode: String,
        imageSize: CGSize,
        latency: Double,
        prompt: String,
        response: String,
        severity: String,
        aiModel: String,
        inputTokens: Int? = nil,
        textInputTokens: Int? = nil,
        imageInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        thinkingTokens: Int? = nil
    ) {
        let record = TrialRecord(
            id: id,
            timestamp: Date(),
            phase: phase,
            source: source,
            captureMode: captureMode,
            imageWidth: Double(imageSize.width),
            imageHeight: Double(imageSize.height),
            latencySeconds: latency,
            customPrompt: prompt,
            rawResponseText: response,
            parsedSeverity: severity,
            aiModel: aiModel,
            isCorrect: nil,
            rating1To5: nil,
            notes: nil,
            inputTokens: inputTokens,
            textInputTokens: textInputTokens,
            imageInputTokens: imageInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            thinkingTokens: thinkingTokens
        )
        self.records.append(record)
        saveToDisk()
    }
    
    /// Updates accuracy assessments for a specific record
    public func submitFeedback(recordId: UUID, isCorrect: Bool?, rating: Int?, notes: String? = nil) {
        if let idx = records.firstIndex(where: { $0.id == recordId }) {
            if let correct = isCorrect {
                records[idx].isCorrect = correct
            }
            if let rat = rating {
                records[idx].rating1To5 = rat
            }
            if let noteText = notes {
                records[idx].notes = noteText
            }
            saveToDisk()
            print("Feedback updated for trial \(recordId): correct=\(String(describing: isCorrect)), rating=\(String(describing: rating))")
        }
    }
    
    /// Formats flat data to CSV format and returns the temporary file path
    public func exportAsCSV() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("smart_eyes_telemetry_\(Int(Date().timeIntervalSince1970)).csv")
        
        var csvString = "trial_id;;timestamp;;phase;;test_case;;source;;capture_mode;;image_width;;image_height;;latency_seconds;;custom_prompt;;parsed_severity;;is_correct;;rating;;ai_model;;output;;response_status;;text_input_tokens;;image_input_tokens;;total_input_tokens;;thinking_tokens;;output_tokens;;total_tokens\n"
        
        let formatter = ISO8601DateFormatter()
        
        for record in records {
            let id = record.id.uuidString
            let timestamp = formatter.string(from: record.timestamp)
            let phase = record.phase
            let source = record.source
            let captureMode = record.captureMode
            let width = String(format: "%.0f", record.imageWidth)
            let height = String(format: "%.0f", record.imageHeight)
            let latency = String(format: "%.2f", record.latencySeconds)
            
            // Sanitize string cells for CSV safety
            let customPrompt = escapeCSVField(record.customPrompt)
            let parsedSeverity = record.parsedSeverity
            let isCorrect = record.isCorrect != nil ? "\(record.isCorrect!)" : "N/A"
            let rating = record.rating1To5 != nil ? "\(record.rating1To5!)" : "N/A"
            let aiModel = record.aiModel ?? "N/A"
            let output = escapeCSVField(record.rawResponseText)
            
            let responseStatus: String
            let lowerResponse = record.rawResponseText.lowercased()
            if lowerResponse.contains("api error:") || lowerResponse.contains("error:") {
                responseStatus = "api_err"
            } else {
                responseStatus = "data_ok"
            }
            
            let textInputStr    = record.textInputTokens  != nil ? "\(record.textInputTokens!)"  : "N/A"
            let imageInputStr   = record.imageInputTokens != nil ? "\(record.imageInputTokens!)" : "N/A"
            let totalInputStr   = record.inputTokens      != nil ? "\(record.inputTokens!)"      : "N/A"
            let thinkingStr     = record.thinkingTokens   != nil ? "\(record.thinkingTokens!)"   : "N/A"
            let outputTokensStr = record.outputTokens     != nil ? "\(record.outputTokens!)"     : "N/A"
            let totalTokensStr  = record.totalTokens      != nil ? "\(record.totalTokens!)"      : "N/A"

            csvString += "\(id);;\(timestamp);;\(phase);;Please enter test case;;\(source);;\(captureMode);;\(width);;\(height);;\(latency);;\"\(customPrompt)\";;\(parsedSeverity);;\(isCorrect);;\(rating);;\(aiModel);;\"\(output)\";;\(responseStatus);;\(textInputStr);;\(imageInputStr);;\(totalInputStr);;\(thinkingStr);;\(outputTokensStr);;\(totalTokensStr)\n"
        }
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("CSV export failed: \(error)")
            return nil
        }
    }
    
    /// Helper to prevent cell breakdown caused by nested quotes and newlines
    private func escapeCSVField(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: "\"", with: "\"\"")
        clean = clean.replacingOccurrences(of: "\n", with: " ")
        clean = clean.replacingOccurrences(of: "\r", with: " ")
        clean = clean.replacingOccurrences(of: ";;", with: ";")
        return clean
    }
}
