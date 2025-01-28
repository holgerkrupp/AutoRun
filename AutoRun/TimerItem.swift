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
    enum LauchType:Int, Codable {
        case app, script
    }
    
    enum TimerError: Error {
        case invalidURL(url: URL?)
        
    }
    
    
    var creationDate: Date?
    var name: String?

    var fileName: URL?
    var launchItem:[LauchType: String]?
    
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
    @Transient  var progress:Double? {
        if timer?.isValid == true {
            guard let nextDate = timer?.fireDate else { return nil }
          //  guard let interval = interval else { return nil }
            let lastDate = nextDate.addingTimeInterval(-interval)
            let now = Date()
            let elapsedTime = now.timeIntervalSince(lastDate)
            return elapsedTime/interval
        }else{
            return nil
        }
    }
    
    
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
        case creationDate, name, active, fileName, fireDate, interval, doesRepeat, order, launchItem
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
        try container.encode(launchItem, forKey: .launchItem)

    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        name = try container.decode(String.self, forKey: .name)
        launchItem = try container.decode([LauchType: String].self, forKey: .launchItem)
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
    }
    
    func startTimer() -> Bool{
        print("timer start")
        //guard let interval = interval,
        guard let _ = fileName else { print("error - no file to launch "); return false }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: doesRepeat) { timer in
           try? self.fireTimer()
        }
        nextFireDate = timer?.fireDate
        
        return timer?.isValid ?? false
    }
    
    func fireTimer() throws{
        guard let fileName = fileName else { throw TimerError.invalidURL(url: fileName) }

        print("Timer fired at \(Date().formatted())")
        do{
            try openApp()
        }catch{
            print("timer failed to open the app")
        }
     
        
        nextFireDate = Date().addingTimeInterval(timer?.timeInterval ?? self.interval)
        
        
        print ("next FireDate: \(nextFireDate?.formatted() ?? "unknown")")
    }
    
    func openApp() throws{
        guard let fileName = fileName else { throw TimerError.invalidURL(url: fileName) }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: fileName,
                                           configuration: configuration,
                                           completionHandler: nil)
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


