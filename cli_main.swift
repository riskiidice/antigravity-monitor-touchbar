import Foundation

// Struct matching JSON output from python helper
struct QuotaData: Codable {
    let gemini_weekly: Double
    let gemini_5h: Double
    let claude_weekly: Double
    let claude_5h: Double
    let gemini_weekly_reset: String
    let gemini_5h_reset: String
    let claude_weekly_reset: String
    let claude_5h_reset: String
    let cost: Double
    let status: String
}

func makeAnsiBar(percent: Double) -> String {
    let filled = Int(round(percent / 10.0))
    let safeFilled = max(0, min(10, filled))
    let barChars = String(repeating: "█", count: safeFilled) + String(repeating: "░", count: 10 - safeFilled)
    
    let color: String
    if percent > 50.0 {
        color = "\u{001B}[32m" // Green
    } else if percent > 30.0 {
        color = "\u{001B}[33m" // Yellow
    } else {
        color = "\u{001B}[31m" // Red
    }
    
    return "\(color)\(barChars)\u{001B}[0m"
}

func main() {
    let args = CommandLine.arguments
    let isMock = args.contains("--mock") || args.contains("-m")
    let isJson = args.contains("--json")
    
    // Call the python helper in the background to get JSON data
    let task = Process()
    task.launchPath = "/bin/zsh"
    
    var cmd = "python3 -m agy_touchbar.cli --json"
    if isMock {
        cmd += " --mock"
    }
    task.arguments = ["-c", cmd]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe() // silence stderr
    
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let rawOutput = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawOutput.isEmpty else {
        print("Gemini: Offline")
        return
    }
    
    // If the user requested raw JSON output from our Swift CLI
    if isJson {
        print(rawOutput)
        return
    }
    
    // Otherwise, parse and format as colored plain text
    guard let jsonData = rawOutput.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(QuotaData.self, from: jsonData) else {
        print("Gemini: Offline")
        return
    }
    
    if decoded.status == "offline" {
        print("Gemini: Offline")
        return
    }
    
    let gwBar = makeAnsiBar(percent: decoded.gemini_weekly)
    let g5Bar = makeAnsiBar(percent: decoded.gemini_5h)
    
    var gwText = "\(Int(decoded.gemini_weekly))%"
    if decoded.gemini_weekly_reset != "Available" && decoded.gemini_weekly_reset != "N/A" {
        gwText += "(\(decoded.gemini_weekly_reset))"
    }
    
    var g5Text = "\(Int(decoded.gemini_5h))%"
    if decoded.gemini_5h_reset != "Available" && decoded.gemini_5h_reset != "N/A" {
        g5Text += "(\(decoded.gemini_5h_reset))"
    }
    
    print("Gemini: [Wk \(gwBar) \(gwText) / 5h \(g5Bar) \(g5Text)]")
}

main()
