//
//  Item.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import Foundation
import SwiftData
import AppKit



@Model
final class TimerItem: Codable, ObservableObject {
    enum LaunchType:Int, Codable, CaseIterable, Identifiable, CustomStringConvertible {
        var id: Self { self }
        
        var description: String {
            switch self {
            case .app:
                "Launch App"
            case .script:
                "Run Script"
            }
        }
        
        case app, script
    }
    
    enum TimerError: Error {
        case invalidURL(url: URL?)
        case invalidItem
        
    }
    
    
    var creationDate: Date?
    var name: String?

    var fileName: URL?
    var launchType: LaunchType = LaunchType.app
    var launchValue: String = ""
    
    @Transient @Published var isActive: Bool = false
    @Transient @Published var nextFireDate: Date?
    var interval: TimeInterval = 0.0
    var doesRepeat: Bool = false
    var order: Int? = 0
    
    @Transient var fileIcon: NSImage? {
        if let fileString = fileName?.absoluteString{
            return NSWorkspace.shared.icon(forFile: fileString)
        }else{
            return nil
        }
    }
    var icon: Data?
    
    @Transient @Published var timer: Timer?

    
    @Transient var durationDescription:String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        
        let formattedString = formatter.string(from: TimeInterval(interval))!
        return formattedString
    }
    
    init() {
        self.creationDate = Date()
      //  active = false
    }
    
    enum CodingKeys: CodingKey{
        case creationDate, name, active, fileName, fireDate, interval, doesRepeat, order, launchItem, launchType
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(name, forKey: .name)
  //      try container.encode(active, forKey: .active)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(nextFireDate, forKey: .fireDate)
        try container.encode(interval, forKey: .interval)
        try container.encode(doesRepeat, forKey: .doesRepeat)
        try container.encode(order, forKey: .order)
        
        try container.encode(launchValue, forKey: .launchItem)
        try container.encode(launchType, forKey: .launchType)

    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        name = try container.decode(String.self, forKey: .name)
        launchValue = try container.decode(String.self, forKey: .launchItem)
        launchType = try container.decode(LaunchType.self, forKey: .launchType)
     //   active = try container.decode(Bool.self, forKey: .active)
        fileName = try container.decode(URL.self, forKey: .fileName)
        
        nextFireDate = try container.decode(Date.self, forKey: .fireDate)
        interval = try container.decode(TimeInterval.self, forKey: .interval)
        
        doesRepeat = try container.decode(Bool.self, forKey: .doesRepeat)
        order = try container.decode(Int.self, forKey: .order)
    }
    
    func delete(){
        timer?.invalidate()
        if let modelContext {
            modelContext.delete(self)
        }
    }
    
    func startStop(){
        if let timer, timer.isValid == true{
            stopTimer()
          
        }else{
            _ = startTimer()
        }
    }
    
    func stopTimer(){
        print("timer invalidate")
        timer?.invalidate()
        nextFireDate = nil
        isActive = false
    }
    
    func startTimer() -> Bool{
        print("timer start")

        if launchValue == "", let fileName{
            launchValue = fileName.absoluteString
        }
        guard launchValue != "" else { print("error - nothing to launch "); return false }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: doesRepeat) { timer in
           try? self.fireTimer()
            
        }
        nextFireDate = timer?.fireDate
        isActive = timer?.isValid ?? false
        return timer?.isValid ?? false
    }
    
    func fireTimer() throws{
       
     
        print("Timer fired at \(Date().formatted())")
        try launch() 
     
     
        
        nextFireDate = Date().addingTimeInterval(timer?.timeInterval ?? self.interval)
        if doesRepeat == false { stopTimer() }
        
        print ("next FireDate: \(nextFireDate?.formatted() ?? "unknown")")
    }
    
    
    func openApp() throws {
        guard let fileName = fileName else { throw TimerError.invalidURL(url: fileName) }
        try openApp(fileName: fileName)

    }
    
    
    func openApp(fileName: URL) throws{
      //  guard let fileName = fileName else { throw TimerError.invalidURL(url: fileName) }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: fileName,
                                           configuration: configuration,
                                           completionHandler: nil)
    }
    
    func launch() throws {
        
        switch launchType {
        case .app:
            guard let url = URL(string: launchValue) else { throw TimerError.invalidItem }
            try openApp(fileName: url)
        case .script:
            try runScript(script: launchValue)
      
        }
    }
    
    func runScript(script: String) throws{
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = nil
        task.arguments = ["-c", script]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil
        
        try task.run()
    }
    
    func calcProgress() -> Double? {
        dump(timer)
        print("calculating progress")
        if timer?.isValid == true {
            guard (nextFireDate != nil) else {
                print("nextDate")
                return nil
            }

            guard let lastDate = nextFireDate?.addingTimeInterval(-interval) else { return nil }
            let now = Date()
            let elapsedTime = now.timeIntervalSince(lastDate)
            return elapsedTime/interval
        }else{
            print("nil")
            return nil
        }
    }
    
    
}


